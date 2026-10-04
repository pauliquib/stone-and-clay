## Sezónní výzdoba listnatých stromů kolem hráče (dekorace, žádná hra):
## - ovoce v korunách stromů v sadech a zahradách (srpen–říjen): červená / žlutá / fialová / zelená jablka, švestky, hrušky,
## - padané listí na zemi pod korunami (od podzimního zbarvení, přes zimu do sněhu, na jaře mizí).
## Oba jsou MultiMesh; přestavují se, když se hráč posune o `REBUILD_DIST`, změní se den nebo se výrazně změní
## množství (`FRUIT`, `LEAVES`). Ovoce jen do `FRUIT_RADIUS`, listí jen do `LEAF_RADIUS` od hráče.
## Poloha a velikost koruny se odhadují z výšky stromu (`CROWN_*`) – ladí se podle vzhledu.
class_name TreeDecor
extends Node3D

const FRUIT_RADIUS := 150.0
const LEAF_RADIUS := 50.0
const REBUILD_DIST := 30.0
const MAX_FRUIT := 1600
const MAX_LEAVES := 2600
const FRAME_BUDGET_US := 1200          # přestavba po kouscích – nejvýš ~1,2 ms za snímek
const FRUIT_PER_TREE := 14
const LEAVES_PER_TREE := 26
const FRUIT_TREE_H := [3.5, 10.0]       # ovocné stromy jsou menší (m)
const FRUIT_SHARE := 0.5                # podíl vhodných stromů, které nesou ovoce
const CROWN_CENTER := 0.62              # výška středu koruny (násobek výšky stromu)
const CROWN_R := 0.3                    # poloměr koruny (násobek výšky), omezeno na CROWN_R_MIN..MAX
const CROWN_R_MIN := 1.5
const CROWN_R_MAX := 4.5
## Množství ovoce a listí v roce [den, podíl 0..1]
const FRUIT := [[190, 0.0], [210, 0.3], [235, 0.85], [270, 1.0], [290, 0.7], [302, 0.15], [310, 0.0]]
const LEAVES := [[1, 0.85], [60, 0.5], [100, 0.0], [268, 0.0], [282, 0.15], [300, 0.55], [320, 0.95], [335, 1.0], [366, 0.85]]
const SNOW_HIDES_LEAVES := 0.35
const FRUIT_COLORS := [Color(0.82, 0.1, 0.07), Color(0.88, 0.76, 0.2), Color(0.32, 0.12, 0.42), Color(0.6, 0.72, 0.2)]
const LEAF_COLORS := [Color(0.85, 0.66, 0.1), Color(0.8, 0.4, 0.08), Color(0.55, 0.2, 0.08), Color(0.42, 0.29, 0.12),
	Color(0.7, 0.55, 0.12)]

var world: World
var fields: Fields
var terrain: Terrain
var _fruit: MultiMesh
var _fruit_mmi: MultiMeshInstance3D
var _leaf: MultiMesh
var _leaf_mmi: MultiMeshInstance3D
var _tree_data := PackedFloat32Array()      # po pěti: x, y, z, výška, index v trees.bin
var _cells := {}                            # Vector2i(64 m) → PackedInt32Array pořadí v _tree_data
var _last_pos := Vector3(1e9, 0, 1e9)
var _last_jd := -1
var _last_ff := -1.0
var _last_lf := -1.0
var _busy := false
var detail := 1.0                            # 0 = vypnuto, 0.5–1 = poměr okruhu (Nastavení → Grafika → Vegetace)


func set_detail(d: float) -> void:
	if is_equal_approx(d, detail):
		return
	detail = d
	_last_pos = Vector3(1e9, 0, 1e9)


func setup(w: World) -> void:
	world = w
	fields = w.fields
	terrain = w.terrain
	top_level = true
	_load_trees()
	if world.trees != null:      # pokácení / načtení pozice → ovoce a listí se přestaví při nejbližší aktualizaci
		world.trees.tree_felled.connect(func(_i: int): _last_pos = Vector3(1e9, 0, 1e9))
		world.trees.tree_restored.connect(func(_i: int): _last_pos = Vector3(1e9, 0, 1e9))
	var fm := SphereMesh.new()
	fm.radius = 0.07
	fm.height = 0.14
	fm.radial_segments = 6
	fm.rings = 3
	var fmat := StandardMaterial3D.new()
	fmat.vertex_color_use_as_albedo = true
	fmat.roughness = 0.4
	fm.material = fmat
	_fruit = _make_mm(fm, MAX_FRUIT)
	_fruit_mmi = _add_mmi(_fruit)
	var lm := BoxMesh.new()
	lm.size = Vector3(0.17, 0.006, 0.11)
	var lmat := StandardMaterial3D.new()
	lmat.vertex_color_use_as_albedo = true
	lmat.roughness = 1.0
	lm.material = lmat
	_leaf = _make_mm(lm, MAX_LEAVES)
	_leaf_mmi = _add_mmi(_leaf)


func _make_mm(mesh: Mesh, n: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = n
	mm.visible_instance_count = 0
	return mm


func _add_mmi(mm: MultiMesh) -> MultiMeshInstance3D:
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## Listnaté stromy (prototypy 0–2) z trees.bin bez těch, které zmizely v korytech potoků.
func _load_trees() -> void:
	var tb := FileAccess.get_file_as_bytes("res://data/trees.bin")
	var n := tb.decode_s32(4)
	var d := tb.slice(8).to_float32_array()
	var skip: Dictionary = world.water.drop_trees if world.water else {}
	var out := PackedFloat32Array()
	for i in n:
		var k := i * 11
		if int(d[k + 10]) >= 3 or skip.has(i):
			continue
		var idx := out.size() / 5
		out.append_array(PackedFloat32Array([d[k], d[k + 1], d[k + 2], d[k + 5], float(i)]))
		var key := Vector2i(floori(d[k] / 64.0), floori(d[k + 2] / 64.0))
		if not _cells.has(key):
			_cells[key] = PackedInt32Array()
		var arr: PackedInt32Array = _cells[key]
		arr.append(idx)
		_cells[key] = arr
	_tree_data = out


## Volá se párkrát za sekundu (SeasonFx).
func update(pos: Vector3, doy: float, snow: float, jd: int) -> void:
	if _busy:
		return
	var ff := Seasons.curve(FRUIT, doy) * (1.0 if detail > 0.0 else 0.0)
	var lf := Seasons.curve(LEAVES, doy) * (0.0 if snow > SNOW_HIDES_LEAVES else 1.0) * (1.0 if detail > 0.0 else 0.0)
	_fruit_mmi.visible = ff > 0.02
	_leaf_mmi.visible = lf > 0.02
	if not _fruit_mmi.visible and not _leaf_mmi.visible:
		_last_ff = ff
		_last_lf = lf
		return
	var moved := Vector2(pos.x - _last_pos.x, pos.z - _last_pos.z).length()
	if moved < REBUILD_DIST and jd == _last_jd and absf(ff - _last_ff) < 0.05 and absf(lf - _last_lf) < 0.05:
		return
	_last_pos = pos
	_last_jd = jd
	_last_ff = ff
	_last_lf = lf
	_rebuild_all(pos, ff, lf)


func _rebuild_all(pos: Vector3, ff: float, lf: float) -> void:
	_busy = true
	if _fruit_mmi.visible:
		await _rebuild_fruit(pos, ff)
	else:
		_fruit.visible_instance_count = 0
	if not is_inside_tree():
		return
	if _leaf_mmi.visible:
		await _rebuild_leaves(pos, lf)
	else:
		_leaf.visible_instance_count = 0
	_busy = false


## Předá čas dalšímu snímku, když přestavba v tomto snímku trvá déle než FRAME_BUDGET_US.
func _yield_if_late(t0: int) -> int:
	if Time.get_ticks_usec() - t0 > FRAME_BUDGET_US:
		await get_tree().process_frame
		return Time.get_ticks_usec()
	return t0


## Indexy stromů v okruhu `r` od bodu (v _tree_data).
func _near(pos: Vector3, r: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var c0 := Vector2i(floori((pos.x - r) / 64.0), floori((pos.z - r) / 64.0))
	var c1 := Vector2i(floori((pos.x + r) / 64.0), floori((pos.z + r) / 64.0))
	var r2 := r * r
	var tm: TreeManager = world.trees if world != null else null   # pokácené stromy (M2.1) bez ovoce a listí
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			var arr: PackedInt32Array = _cells.get(Vector2i(cx, cz), PackedInt32Array())
			for t in arr:
				var dx := _tree_data[t * 5] - pos.x
				var dz := _tree_data[t * 5 + 2] - pos.z
				if dx * dx + dz * dz < r2:
					if tm != null and tm.is_felled(int(_tree_data[t * 5 + 4])):
						continue
					out.append(t)
	return out


func _crown_r(h: float) -> float:
	return clampf(h * CROWN_R, CROWN_R_MIN, CROWN_R_MAX)


func _is_fruit_tree(t: int) -> bool:
	var h := _tree_data[t * 5 + 3]
	if h < FRUIT_TREE_H[0] or h > FRUIT_TREE_H[1]:
		return false
	var src := int(_tree_data[t * 5 + 4])
	if Fields._hash(src, 5) % 100 >= int(FRUIT_SHARE * 100.0):
		return false
	var x := _tree_data[t * 5]
	var z := _tree_data[t * 5 + 2]
	var cls := fields.class_at(x, z) if fields else 0
	if cls == 3 or cls == 4:
		return true
	var f := world.fauna
	return f != null and f.settle_at(x, z) > 0.15 and f.forest_at(x, z) < 0.35


func _rebuild_fruit(pos: Vector3, frac: float) -> void:
	var n := 0
	var buf := PackedFloat32Array()
	buf.resize(MAX_FRUIT * 16)
	var t0 := Time.get_ticks_usec()
	for t in _near(pos, FRUIT_RADIUS * detail):
		t0 = await _yield_if_late(t0)
		if n >= MAX_FRUIT:
			break
		if not _is_fruit_tree(t):
			continue
		var h := _tree_data[t * 5 + 3]
		var src := int(_tree_data[t * 5 + 4])
		var c := Vector3(_tree_data[t * 5], _tree_data[t * 5 + 1] + h * CROWN_CENTER, _tree_data[t * 5 + 2])
		var r := _crown_r(h)
		var kind := Fields._hash(src, 99) % FRUIT_COLORS.size()
		var base: Color = FRUIT_COLORS[kind]
		for k in FRUIT_PER_TREE:
			var hh := Fields._hash(src, k + 200)
			if float(hh % 1000) / 1000.0 >= frac:
				continue
			var cos_t := -0.3 + 1.3 * float((hh / 1000) % 1000) / 1000.0
			var sin_t := sqrt(maxf(1.0 - cos_t * cos_t, 0.0))
			var phi := float((hh / 1000000) % 1000) / 1000.0 * TAU
			var p := c + Vector3(sin_t * cos(phi), cos_t * 0.75, sin_t * sin(phi)) * r * 0.95
			var col := base.lightened(float(hh % 13) / 100.0)
			var o := n * 16
			buf[o] = 1.0; buf[o + 3] = p.x
			buf[o + 5] = 1.0; buf[o + 7] = p.y
			buf[o + 10] = 1.0; buf[o + 11] = p.z
			buf[o + 12] = col.r; buf[o + 13] = col.g; buf[o + 14] = col.b; buf[o + 15] = col.a
			n += 1
			if n >= MAX_FRUIT:
				break
	_fruit.buffer = buf
	_fruit.visible_instance_count = n


func _rebuild_leaves(pos: Vector3, frac: float) -> void:
	var n := 0
	var buf := PackedFloat32Array()
	buf.resize(MAX_LEAVES * 16)
	var t0 := Time.get_ticks_usec()
	for t in _near(pos, LEAF_RADIUS * detail):
		t0 = await _yield_if_late(t0)
		if n >= MAX_LEAVES:
			break
		var h := _tree_data[t * 5 + 3]
		if h < 4.0:
			continue
		var src := int(_tree_data[t * 5 + 4])
		var tx := _tree_data[t * 5]
		var tz := _tree_data[t * 5 + 2]
		var r := _crown_r(h) * 1.15
		for k in LEAVES_PER_TREE:
			var hh := Fields._hash(src, k + 500)
			if float(hh % 1000) / 1000.0 >= frac:
				continue
			var a := float((hh / 1000) % 1000) / 1000.0 * TAU
			var d := sqrt(float((hh / 1000000) % 1000) / 1000.0) * r
			var x := tx + cos(a) * d
			var z := tz + sin(a) * d
			var sc := 0.8 + float(hh % 5) * 0.1
			var xf := Transform3D(Basis(Vector3.UP, float(hh % 314) / 50.0).scaled(Vector3(sc, 1.0, sc)),
				Vector3(x, terrain.height_at(x, z) + 0.02, z))
			var col: Color = LEAF_COLORS[hh % LEAF_COLORS.size()]
			var o := n * 16
			buf[o] = xf.basis.x.x; buf[o + 1] = xf.basis.y.x; buf[o + 2] = xf.basis.z.x; buf[o + 3] = xf.origin.x
			buf[o + 4] = xf.basis.x.y; buf[o + 5] = xf.basis.y.y; buf[o + 6] = xf.basis.z.y; buf[o + 7] = xf.origin.y
			buf[o + 8] = xf.basis.x.z; buf[o + 9] = xf.basis.y.z; buf[o + 10] = xf.basis.z.z; buf[o + 11] = xf.origin.z
			buf[o + 12] = col.r; buf[o + 13] = col.g; buf[o + 14] = col.b; buf[o + 15] = col.a
			n += 1
			if n >= MAX_LEAVES:
				break
	_leaf.buffer = buf
	_leaf.visible_instance_count = n
