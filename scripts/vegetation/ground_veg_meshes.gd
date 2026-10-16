## M8.14 Přízemní vegetace – low-poly modely nových typů (vlhká a suchá louka, kapradí, borůvčí, mech, jarní
## byliny, hrabanka / jehličí, devětsil, šípek). Každý ≤ ~40 trojúhelníků, patka v počátku, UV.y = poměrná výška.
##
## **Barvy vrcholů podle 00_PRINCIPY kap. 4** (ne albedo!): `r` ohebnost (0 patka … 1 špička), `g` fáze listu / stébla
## (hash 0..1), `b` váha třepetání (0 stonek, 1 list / květ), `a` okluze (0 jádro trsu … 1 okraj). Albedo dodá shader
## z uniformů `veg_lo` → `veg_hi` (po výšce) a `veg_acc` (květ / bobule – UV.x > 0,5), viz `VegetationManager.VEG_CONFIG`.
##
## Stejný kód používá offline generátor (`tools/gen_vegetation_meshes.gd` → `assets/models/vegetation/<id>.res`)
## i hra jako fallback, když `.res` chybí (`VegetationManager._mesh`) – modely jsou deterministické.
class_name GroundVegMeshes
extends RefCounted

const IDS := ["herb_wet", "herb_dry", "fern", "bilberry", "moss", "spring_flowers", "litter", "butterbur", "rosehip"]
const FOLIAGE_U := 0.25                 # UV.x listu / stonku
const ACCENT_U := 0.75                  # UV.x květu / bobule (shader → veg_acc)

var _v := PackedVector3Array()
var _n := PackedVector3Array()
var _c := PackedColorArray()
var _uv := PackedVector2Array()
var _i := PackedInt32Array()
var _max_h := 1.0
var _phase := 0.0


## Postaví model `id` (jeden z IDS). Neznámé id → prázdný mesh (a varování).
static func build(id: String) -> ArrayMesh:
	var b := GroundVegMeshes.new()
	match id:
		"herb_wet":
			b._herb_wet()
		"herb_dry":
			b._herb_dry()
		"fern":
			b._fern()
		"bilberry":
			b._bilberry()
		"moss":
			b._moss()
		"spring_flowers":
			b._spring_flowers()
		"litter":
			b._litter()
		"butterbur":
			b._butterbur()
		"rosehip":
			b._rosehip()
		_:
			push_warning("GroundVegMeshes: neznámý model %s" % id)
	return b._commit(id)


func _next_phase() -> float:
	_phase = fposmod(_phase + 0.618034, 1.0)
	return _phase


func _col(y: float, leaf: float, occl: float) -> Color:
	return Color(clampf(y / _max_h, 0.0, 1.0), _phase, leaf, occl)


## Svislý panel (pás quadů) natočený `theta`; `rows` = [půlšířka, výška, vybočení ven].
func _panel(theta: float, rows: Array, leaf := 0.6) -> void:
	_next_phase()
	var rot := Basis(Vector3.UP, theta)
	var nrm := rot * Vector3(0, 0.25, 1).normalized()
	var base := _v.size()
	for r in rows:
		var y: float = r[1]
		for s in [-1.0, 1.0]:
			_v.append(rot * Vector3(s * float(r[0]), y, float(r[2])))
			_n.append(nrm)
			_c.append(_col(y, leaf * clampf(y / _max_h * 1.5, 0.0, 1.0), lerpf(0.35, 1.0, y / _max_h)))
			_uv.append(Vector2(FOLIAGE_U, clampf(y / _max_h, 0.0, 1.0)))
	for ri in rows.size() - 1:
		var a := base + ri * 2
		_i.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])


## List (quad) mezi dvěma řadami bodů – od stonku ven (`out0` → `out1`), výšky `y0` → `y1`.
func _blade(theta: float, w: float, y0: float, y1: float, out0: float, out1: float, tip_w := 0.4) -> void:
	_next_phase()
	var rot := Basis(Vector3.UP, theta)
	var base := _v.size()
	var nrm := rot * Vector3(0, 1, 0.4).normalized()
	var pts := [Vector3(-w, y0, out0), Vector3(w, y0, out0), Vector3(-w * tip_w, y1, out1), Vector3(w * tip_w, y1, out1)]
	for k in 4:
		var p: Vector3 = pts[k]
		_v.append(rot * p)
		_n.append(nrm)
		var tip := 1.0 if k >= 2 else 0.4
		_c.append(Color(clampf(p.y / _max_h, 0.0, 1.0) * lerpf(0.6, 1.0, tip), _phase, tip, lerpf(0.5, 1.0, tip)))
		_uv.append(Vector2(FOLIAGE_U, clampf(p.y / _max_h, 0.0, 1.0)))
	_i.append_array([base, base + 1, base + 2, base + 1, base + 3, base + 2])


## Květ / bobule – osmistěn (8 trojúhelníků), albedo z `veg_acc`.
func _octa(center: Vector3, r: float, squash := 0.6) -> void:
	_next_phase()
	var base := _v.size()
	var pts := [Vector3(0, r * squash, 0), Vector3(r, 0, 0), Vector3(0, 0, r), Vector3(-r, 0, 0),
		Vector3(0, 0, -r), Vector3(0, -r * squash, 0)]
	for p in pts:
		_v.append(center + p)
		_n.append((p as Vector3).normalized())
		_c.append(Color(clampf(center.y / _max_h, 0.0, 1.0), _phase, 0.9, 1.0))
		_uv.append(Vector2(ACCENT_U, clampf((center.y + (p as Vector3).y) / _max_h, 0.0, 1.0)))
	for s in 4:
		var a := 1 + s
		var b := 1 + (s + 1) % 4
		_i.append_array([base, base + a, base + b])
		_i.append_array([base + 5, base + b, base + a])


## Plochý kus hrabanky / jehličí těsně nad zemí (bez ohybu: r = 0).
func _flat(theta: float, w: float, l: float, y: float) -> void:
	var rot := Basis(Vector3.UP, theta)
	var base := _v.size()
	for p in [Vector3(-w, y, -l), Vector3(w, y + 0.01, -l), Vector3(-w, y + 0.01, l), Vector3(w, y, l)]:
		_v.append(rot * p)
		_n.append(Vector3.UP)
		_c.append(Color(0.0, _next_phase(), 0.0, 0.8))
		_uv.append(Vector2(FOLIAGE_U, 0.5 + 0.5 * (p as Vector3).x / w))
	_i.append_array([base, base + 1, base + 2, base + 1, base + 3, base + 2])


func _commit(id: String) -> ArrayMesh:
	var m := ArrayMesh.new()
	if _v.is_empty():
		return m
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = _v
	arr[Mesh.ARRAY_NORMAL] = _n
	arr[Mesh.ARRAY_COLOR] = _c
	arr[Mesh.ARRAY_TEX_UV] = _uv
	arr[Mesh.ARRAY_INDEX] = _i
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.resource_name = id
	return m


func tri_count() -> int:
	return _i.size() / 3


# ------------------------------------------------------------------ modely

## Vlhká louka (pcháč zelinný, kohoutek, tužebník): vysoké stonky a fialové / růžové hlávky nahoře.
func _herb_wet() -> void:
	_max_h = 1.0
	for k in 3:
		_panel(k * TAU / 3.0, [[0.22, 0.0, 0.0], [0.20, 0.5, 0.06], [0.05, 0.92, 0.14]])
	_octa(Vector3(0.10, 0.95, 0.04), 0.06, 1.0)
	_octa(Vector3(-0.08, 0.88, -0.07), 0.05, 1.0)
	_octa(Vector3(0.02, 0.80, 0.12), 0.045, 1.0)


## Suchá stráň (šalvěj luční, mateřídouška, kostřava): nízký trs a drobné fialové květy.
func _herb_dry() -> void:
	_max_h = 0.40
	for k in 3:
		_panel(k * TAU / 3.0 + 0.3, [[0.16, 0.0, 0.0], [0.13, 0.18, 0.05], [0.03, 0.34, 0.10]])
	_octa(Vector3(0.08, 0.36, 0.02), 0.035, 1.6)
	_octa(Vector3(-0.06, 0.32, -0.05), 0.03, 1.6)
	_octa(Vector3(0.0, 0.38, 0.07), 0.03, 1.6)
	_octa(Vector3(-0.1, 0.12, 0.1), 0.04, 0.5)


## Kapradí (kapraď samec): 6 obloukových listů do kruhu.
func _fern() -> void:
	_max_h = 0.75
	for k in 6:
		var a := k * TAU / 6.0 + 0.2
		_blade(a, 0.12, 0.02, 0.55, 0.04, 0.32, 0.6)
		_blade(a, 0.10, 0.55, 0.70, 0.32, 0.55, 0.1)


## Borůvčí: nízký hustý keřík a tmavomodré bobule.
func _bilberry() -> void:
	_max_h = 0.35
	for k in 3:
		_panel(k * PI / 3.0, [[0.12, 0.0, 0.0], [0.28, 0.15, 0.05], [0.22, 0.29, 0.03], [0.06, 0.35, 0.0]], 0.8)
	_octa(Vector3(0.14, 0.20, 0.05), 0.022, 1.0)
	_octa(Vector3(-0.12, 0.24, -0.08), 0.022, 1.0)
	_octa(Vector3(0.03, 0.16, 0.16), 0.022, 1.0)


## Mech: nízký polštář (dva zploštělé osmistěny – albedo z veg_lo/veg_hi, ne akcent).
func _moss() -> void:
	_max_h = 0.10
	for c in [Vector3(0.0, 0.0, 0.0), Vector3(0.22, -0.01, 0.12)]:
		_next_phase()
		var base := _v.size()
		var r := 0.32
		var pts := [Vector3(0, 0.09, 0), Vector3(r, 0, 0), Vector3(0, 0, r), Vector3(-r, 0, 0), Vector3(0, 0, -r)]
		for p in pts:
			var q: Vector3 = (c as Vector3) + p
			_v.append(q)
			_n.append((p + Vector3(0, 0.2, 0)).normalized())
			_c.append(Color(0.0, _phase, 0.0, 0.6 + 0.4 * p.y / 0.09))
			_uv.append(Vector2(FOLIAGE_U, clampf(p.y / 0.09, 0.0, 1.0)))
		for s in 4:
			_i.append_array([base, base + 1 + s, base + 1 + (s + 1) % 4])


## Jarní podrost listnatého lesa (sasanka hajní, dymnivka): krátké listy a bílé / fialové květy.
func _spring_flowers() -> void:
	_max_h = 0.20
	for k in 4:
		_blade(k * TAU / 4.0 + 0.4, 0.06, 0.01, 0.12, 0.02, 0.12, 0.5)
	_octa(Vector3(0.05, 0.17, 0.02), 0.03, 0.5)
	_octa(Vector3(-0.07, 0.15, -0.04), 0.03, 0.5)
	_octa(Vector3(0.01, 0.16, -0.09), 0.028, 0.5)
	_octa(Vector3(-0.02, 0.18, 0.08), 0.028, 0.5)


## Hrabanka / jehličí: dva ploché kusy přes sebe (barvu – bukové listí / smrkové jehličí – dá tint instance).
func _litter() -> void:
	_max_h = 0.05
	_flat(0.0, 0.7, 0.55, 0.012)
	_flat(1.1, 0.55, 0.45, 0.02)


## Devětsil u potoka: velké kulaté listy na stopkách.
func _butterbur() -> void:
	_max_h = 0.65
	for k in 4:
		var a := k * TAU / 4.0 + 0.3
		_panel(a, [[0.02, 0.0, 0.0], [0.02, 0.45, 0.12]], 0.2)
		_blade(a, 0.22, 0.42, 0.55, 0.05, 0.42, 0.9)


## Šípek (růže šípková) – keř sukcese neposekaných luk: řídký keř s červenými šípky.
func _rosehip() -> void:
	_max_h = 1.4
	for k in 3:
		_panel(k * PI / 3.0, [[0.25, 0.0, 0.0], [0.6, 0.6, 0.08], [0.45, 1.1, 0.05], [0.1, 1.4, 0.0]], 0.7)
	_octa(Vector3(0.35, 0.9, 0.1), 0.04, 1.2)
	_octa(Vector3(-0.3, 1.0, -0.12), 0.04, 1.2)
	_octa(Vector3(0.1, 1.2, 0.3), 0.04, 1.2)
	_octa(Vector3(-0.15, 0.7, 0.35), 0.04, 1.2)
