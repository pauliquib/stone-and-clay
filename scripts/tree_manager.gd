## Stromy za běhu (M2.1): index stromů z `MapLoader.build_trees` (instance v MultiMeshích + kolizní válec),
## skrývání pokácených stromů, pařezy, dotaz „nejbližší strom“ a ukládání (`felled`).
##
## Číslování stromů = pořadí v `data/trees.bin` (stejné jako `Fauna.trees` a `TreeDecor` – klíč `k + 4`).
## Stromy, které `Water` zahodilo (koryta, rybníky), v indexu nejsou (`has_tree(i)` je false).
## Formát trees.bin: 11 × float32 na strom: x, y, z, rot, sx, sy, sz, r, g, b, proto (0–2 listnáč, 3+ jehličnan).
## Bez trees.bin / bez indexu (`set_index` se nezavolá) jsou všechny dotazy prázdné a nic nepadá.
##
## Dynamické stromy (M2.5): zasazené stromy (`PlantedTrees`, `planted`) mají číslo od `DYN_BASE` a jdou stejnými dotazy
## (has_tree / pos_of / height_of / nearest_tree / aim_tree / hide_tree…) jako mapové – kácení a `Forestry` je nerozliší.
class_name TreeManager
extends Node3D

## Strom pokácen / vrácen (načtení pozice). Ovoce v korunách a další systémy se přestaví.
signal tree_felled(i: int)
signal tree_restored(i: int)

const CELL := 64.0                      # mřížka pro nejbližší strom
const HIDE_SCALE := 0.0001              # „nulové“ měřítko skrytého stromu (nulová matice by dělala potíže shaderu)
const TRUNK_R_DECID := 0.09             # poloměr kmene = sx × konstanta (stejně jako kolize v MapLoader)
const TRUNK_R_CONIF := 0.07
const DYN_BASE := 1000000               # čísla od této hodnoty patří zasazeným stromům (PlantedTrees)
const STUMP_H := 0.4
const STUMP_COLOR := Color(0.45, 0.3, 0.17)
const STUMP_TOP := Color(0.72, 0.58, 0.38)

var world: World
var terrain: Terrain
var felled := {}                        # index stromu → herní den pokácení (ukládá se)
var count := 0                          # počet stromů v indexu
var planted: PlantedTrees               # zasazené stromy (M2.5)

var _d := PackedFloat32Array()          # trees.bin (11 floatů na strom)
var _meta := {}                         # i → [nkey, p, near_idx, fkey, group, far_idx, shape_idx]
var _near_mm := {}                      # [nkey, p] → MultiMesh
var _far_mm := {}                       # [fkey, group] → MultiMesh
var _shapes: Array = []                 # CollisionShape3D kmenů (podle pořadí ve `trunks`)
var _cells := {}                        # Vector2i(64 m) → PackedInt32Array stojících i pokácených stromů
var _stumps := {}                       # i → StaticBody3D pařezu
var _orig := {}                         # i → původní Transform3D skrytého stromu
var _stump_mat: StandardMaterial3D


func setup(w: World, t: Terrain) -> void:
	world = w
	terrain = t
	name = "StromyZaBehu"
	planted = PlantedTrees.new()
	add_child(planted)
	planted.setup(w, self)


## Zavolá `MapLoader.build_trees`: syrová data a mapy instancí. Postaví mřížku pro dotazy.
func set_index(d: PackedFloat32Array, meta: Dictionary, near_mm: Dictionary, far_mm: Dictionary, shapes: Array) -> void:
	_d = d
	_meta = meta
	_near_mm = near_mm
	_far_mm = far_mm
	_shapes = shapes
	count = meta.size()
	_cells.clear()
	for i in meta:
		var k := int(i) * 11
		var key := Vector2i(floori(_d[k] / CELL), floori(_d[k + 2] / CELL))
		if not _cells.has(key):
			_cells[key] = PackedInt32Array()
		var arr: PackedInt32Array = _cells[key]
		arr.append(int(i))
		_cells[key] = arr


# ------------------------------------------------------------------ data stromu

func has_tree(i: int) -> bool:
	if i >= DYN_BASE:
		return planted != null and planted.has_tree(i)
	return _meta.has(i)


func is_felled(i: int) -> bool:
	if i >= DYN_BASE:
		return planted != null and planted.is_felled(i)
	return felled.has(i)


## Poloha paty kmene (pro pokácený i stojící strom – po pokácení stojí pařez).
func pos_of(i: int) -> Vector3:
	if i >= DYN_BASE:
		return planted.pos_of(i) if planted != null else Vector3.ZERO
	var k := i * 11
	var p := Vector3(_d[k], _d[k + 1], _d[k + 2])
	if terrain:
		p.y = minf(p.y, terrain.height_at(p.x, p.z) - 0.15)
	return p


## Výška stromu v metrech.
func height_of(i: int) -> float:
	if i >= DYN_BASE:
		return planted.height_of(i) if planted != null else 1.0
	return _d[i * 11 + 5]


## Šířkové měřítko (sx) – rozhoduje o průměru kmene a době kácení.
func scale_of(i: int) -> float:
	if i >= DYN_BASE:
		return planted.scale_of(i) if planted != null else 1.0
	return _d[i * 11 + 4]


func proto_of(i: int) -> int:
	if i >= DYN_BASE:
		return planted.proto_of(i) if planted != null else 0
	return int(_d[i * 11 + 10])


func is_conifer(i: int) -> bool:
	return proto_of(i) >= 3


func trunk_radius(i: int) -> float:
	return maxf(scale_of(i) * (TRUNK_R_DECID if not is_conifer(i) else TRUNK_R_CONIF), 0.1)


## Barva listí / jehličí podle dat (r, g, b).
func color_of(i: int) -> Color:
	if i >= DYN_BASE:
		return planted.color_of(i) if planted != null else Color(0.18, 0.32, 0.1)
	var k := i * 11
	return Color(_d[k + 7], _d[k + 8], _d[k + 9])


# ------------------------------------------------------------------ dotazy

## Nejbližší stojící strom do `r` m od bodu (vodorovně, od osy kmene), −1 když žádný.
func nearest_tree(pos: Vector3, r: float) -> int:
	var best := -1
	var bd := r * r
	var c0 := Vector2i(floori((pos.x - r) / CELL), floori((pos.z - r) / CELL))
	var c1 := Vector2i(floori((pos.x + r) / CELL), floori((pos.z + r) / CELL))
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			var arr: PackedInt32Array = _cells.get(Vector2i(cx, cz), PackedInt32Array())
			for i in arr:
				if felled.has(i):
					continue
				var dx := _d[i * 11] - pos.x
				var dz := _d[i * 11 + 2] - pos.z
				var d2 := dx * dx + dz * dz
				if d2 < bd:
					bd = d2
					best = i
	if planted != null:
		var pi := planted.nearest(pos, sqrt(bd))
		if pi >= 0:
			best = pi
	return best


## Cíl kácení pro hráče: nejbližší strom do `reach` m (od povrchu kmene) v zorném směru `dir` (vodorovně).
## Vrací {kind: "tree", pos, tree: i} nebo {}.
func aim_tree(p: Player, dir: Vector3, reach := 2.5) -> Dictionary:
	if count == 0 and (planted == null or planted.count() == 0):
		return {}
	var pp := p.global_position
	var flat := Vector3(dir.x, 0, dir.z)
	if flat.length() < 0.01:
		return {}
	flat = flat.normalized()
	var best := -1
	var bd := INF
	var c0 := Vector2i(floori((pp.x - reach - 1.0) / CELL), floori((pp.z - reach - 1.0) / CELL))
	var c1 := Vector2i(floori((pp.x + reach + 1.0) / CELL), floori((pp.z + reach + 1.0) / CELL))
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			var arr: PackedInt32Array = _cells.get(Vector2i(cx, cz), PackedInt32Array())
			for i in arr:
				if felled.has(i):
					continue
				var to := Vector3(_d[i * 11] - pp.x, 0, _d[i * 11 + 2] - pp.z)
				var dist := to.length() - trunk_radius(i)
				if dist > reach:
					continue
				if dist > 0.3 and to.normalized().dot(flat) < 0.55:
					continue
				if dist < bd:
					bd = dist
					best = i
	if planted != null:
		var pb := planted.aim_candidate(pp, flat, reach, bd)
		if pb >= 0:
			best = pb
	if best < 0:
		return {}
	return {"kind": "tree", "pos": pos_of(best) + Vector3(0, 1.0, 0), "tree": best}


# ------------------------------------------------------------------ pokácení

## Skryje strom (nulové měřítko ve všech MultiMeshích, vypnutá kolize) a postaví pařez.
## `day` = herní den pokácení. Vrací false, když strom neexistuje nebo už je pokácený.
func hide_tree(i: int, day := 0, silent := false) -> bool:
	if i >= DYN_BASE:
		if planted == null or not planted.fell(i, day):
			return false
		_make_stump(i)
		if not silent:
			tree_felled.emit(i)
		return true
	if not _meta.has(i) or felled.has(i):
		return false
	felled[i] = day
	_set_visible(i, false)
	_make_stump(i)
	if not silent:
		tree_felled.emit(i)
	return true


## Vrátí strom (jen při načtení pozice, kde ještě nebyl pokácený).
func show_tree(i: int) -> void:
	if not felled.has(i):
		return
	felled.erase(i)
	_set_visible(i, true)
	if _stumps.has(i):
		(_stumps[i] as Node).queue_free()
		_stumps.erase(i)
	tree_restored.emit(i)


func _set_visible(i: int, on: bool) -> void:
	var m: Array = _meta[i]
	var far: MultiMesh = _far_mm.get([m[3], m[4]])
	var xf := Transform3D.IDENTITY
	if far and int(m[5]) < far.instance_count:
		xf = far.get_instance_transform(int(m[5]))
	if on:
		if _orig.has(i):
			xf = _orig[i]
			_orig.erase(i)
	else:
		if not _orig.has(i):
			_orig[i] = xf              # původní transformace pro případ vrácení (načtení pozice)
		xf = Transform3D(Basis.from_scale(Vector3.ONE * HIDE_SCALE), xf.origin)
	if far and int(m[5]) < far.instance_count:
		far.set_instance_transform(int(m[5]), xf)
	if m[0] != null:
		var near: MultiMesh = _near_mm.get([m[0], m[1]])
		if near and int(m[2]) >= 0 and int(m[2]) < near.instance_count:
			near.set_instance_transform(int(m[2]), xf)
	var si := int(m[6])
	if si >= 0 and si < _shapes.size() and is_instance_valid(_shapes[si]):
		(_shapes[si] as CollisionShape3D).set_deferred("disabled", not on)


func _make_stump(i: int) -> void:
	if _stumps.has(i):
		return
	if _stump_mat == null:
		_stump_mat = MeshKit.vc_material(0.95)
	var r := trunk_radius(i) * 1.2
	var k := MeshKit.new()
	k.cylinder(Vector3(0, STUMP_H * 0.5, 0), r * 0.95, r * 1.1, STUMP_H, STUMP_COLOR, Vector3.ZERO, 12)
	k.cylinder(Vector3(0, STUMP_H + 0.005, 0), r * 0.9, r * 0.9, 0.012, STUMP_TOP, Vector3.ZERO, 12)
	var b := StaticBody3D.new()
	b.collision_layer = 1
	b.collision_mask = 0
	b.set_meta("surface", "strom")
	b.position = pos_of(i)
	MeshKit.mesh_instance(b, k.commit(_stump_mat), 150.0)
	var cs := CollisionShape3D.new()
	var s := CylinderShape3D.new()
	s.radius = r
	s.height = STUMP_H
	cs.shape = s
	cs.position = Vector3(0, STUMP_H * 0.5, 0)
	b.add_child(cs)
	add_child(b)
	_stumps[i] = b


# ------------------------------------------------------------------ ukládání

func to_dict() -> Dictionary:
	var f := {}
	for i in felled:
		f[str(i)] = int(felled[i])
	return {"felled": f, "planted": planted.to_dict() if planted != null else {}}


## Nastaví pokácené stromy podle uložené pozice: ostatní se vrátí, chybějící klíč = žádný pokácený strom.
func from_dict(d: Dictionary) -> void:
	if planted != null:            # zasazené stromy (M2.5); starý save bez klíče = žádné
		for i in _stumps.keys():
			if int(i) >= DYN_BASE:
				(_stumps[i] as Node).queue_free()
				_stumps.erase(i)
		planted.restore(d.get("planted", {}))
		for i in planted.felled_ids():
			_make_stump(i)
	var want := {}
	var fd: Dictionary = d.get("felled", {})
	for k in fd:
		want[int(k)] = int(fd[k])
	for i in felled.keys():
		if not want.has(i):
			show_tree(i)
	for i in want:
		if _meta.has(i):
			hide_tree(i, int(want[i]), true)
	for i in want:
		if _meta.has(i):
			tree_felled.emit(i)
