## Generátor low-poly modelů vegetace (Fáze 9 – §9): ukládá ArrayMesh do
## `assets/models/vegetation/*.res`. Každý model ≤ ~40 trojúhelníků, patka v počátku (y=0),
## UV.y = poměrná výška vrcholu (0 u země, 1 na špičce) – shader `shaders/vegetation.gdshader`
## podle ní ohýbá rostlinu větrem. Albedo v barvách vrcholů.
##
## Spuštění:  godot --headless --path . --script tools/gen_vegetation_meshes.gd
## Po změně tvarů znovu spustit a .res commitnout (reprodukovatelnost).
extends SceneTree

const OUT := "res://assets/models/vegetation/"

var _v := PackedVector3Array()
var _n := PackedVector3Array()
var _c := PackedColorArray()
var _uv := PackedVector2Array()
var _i := PackedInt32Array()
var _max_h := 1.0                       # pro UV.y (poměrná výška)
var _col_lo := Color(0.2, 0.35, 0.1)    # barva patky
var _col_hi := Color(0.4, 0.55, 0.2)    # barva špičky


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_grass_tall()
	_nettle()
	_bush("bush_hazel", 4, 0.62, 1.05, Color(0.10, 0.22, 0.07), Color(0.28, 0.45, 0.15), 0.0)
	_bush("bush_blackthorn", 3, 0.55, 1.30, Color(0.09, 0.16, 0.07), Color(0.22, 0.34, 0.16), 0.35)
	_wheat()
	_weed()
	_garden_veg()
	print("gen_vegetation_meshes: hotovo → %s" % OUT)
	quit(0)


# ------------------------------------------------------------------ stavba panelů

## Svislý „panel“ (stěna z quads) natočený `theta` kolem Y. `rows` = trojice
## [půlšířka, výška, vybočení ven]; `cols` = volitelně barva pro každý řádek (jinak lerp lo→hi).
func panel(theta: float, rows: Array, cols: Array = []) -> void:
	var rot := Basis(Vector3.UP, theta)
	var nrm := rot * Vector3(0, 0.25, 1).normalized()
	var base := _v.size()
	for ri in rows.size():
		var r: Array = rows[ri]
		var cc: Color = cols[ri] if cols.size() == rows.size() else _col_lo.lerp(_col_hi, r[1] / _max_h)
		for s in [-1.0, 1.0]:
			_v.append(rot * Vector3(s * r[0], r[1], r[2]))
			_n.append(nrm)
			_c.append(cc)
			_uv.append(Vector2(0.5 + s * 0.5, clampf(r[1] / _max_h, 0.0, 1.0)))
	for ri in rows.size() - 1:
		var a := base + ri * 2
		var b := a + 1
		var c2 := a + 2
		var d := a + 3
		_i.append_array([a, b, c2, b, d, c2])


## Vodorovná / nakloněná „čepeľ“ (list) – quad mezi dvěma řadami bodů, použito pro listy kopřiv aj.
func blade(theta: float, w: float, y0: float, y1: float, out0: float, out1: float,
		col: Color) -> void:
	var rot := Basis(Vector3.UP, theta)
	var base := _v.size()
	var nrm := rot * Vector3(0, 1, 0.4).normalized()
	for p in [Vector3(-w, y0, out0), Vector3(w, y0, out0), Vector3(-w * 0.4, y1, out1), Vector3(w * 0.4, y1, out1)]:
		_v.append(rot * p)
		_n.append(nrm)
		_c.append(col)
	_uv.append_array([Vector2(0, y0 / _max_h), Vector2(1, y0 / _max_h),
		Vector2(0, y1 / _max_h), Vector2(1, y1 / _max_h)])
	_i.append_array([base, base + 1, base + 2, base + 1, base + 3, base + 2])


## Osmistěn (bobulka / klasek) – 8 trojúhelníků.
func octa(center: Vector3, r: float, col: Color, squash := 0.6) -> void:
	var base := _v.size()
	var pts := [Vector3(0, r * squash, 0), Vector3(r, 0, 0), Vector3(0, 0, r), Vector3(-r, 0, 0),
		Vector3(0, 0, -r), Vector3(0, -r * squash, 0)]
	for p in pts:
		_v.append(center + p)
		_n.append(p.normalized())
		_c.append(col)
		_uv.append(Vector2(0.5, clampf((center.y + p.y) / _max_h, 0.0, 1.0)))
	# horní jehlan + dolní jehlan
	for s in 4:
		var a := 1 + s
		var b := 1 + (s + 1) % 4
		_i.append_array([base, base + a, base + b])
		_i.append_array([base + 5, base + b, base + a])


func commit(name: String) -> void:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = _v
	arr[Mesh.ARRAY_NORMAL] = _n
	arr[Mesh.ARRAY_COLOR] = _c
	arr[Mesh.ARRAY_TEX_UV] = _uv
	arr[Mesh.ARRAY_INDEX] = _i
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.resource_name = name
	var err := ResourceSaver.save(m, OUT + name + ".res")
	var tris := _i.size() / 3
	print("  %s.res: %d vrcholů, %d tris → %s" % [name, _v.size(), tris, error_string(err)])
	_v = PackedVector3Array()
	_n = PackedVector3Array()
	_c = PackedColorArray()
	_uv = PackedVector2Array()
	_i = PackedInt32Array()


# ------------------------------------------------------------------ modely

## Vysoká tráva: 3 zkřížené listovce prohnuté ven.
func _grass_tall() -> void:
	_max_h = 0.85
	_col_lo = Color(0.13, 0.26, 0.07)
	_col_hi = Color(0.38, 0.52, 0.18)
	for k in 3:
		panel(k * TAU / 3.0, [[0.30, 0.0, 0.0], [0.30, 0.45, 0.07], [0.06, 0.85, 0.18]])
	commit("grass_tall")


## Kopřiva: 2 zkřížené kmenové listovce + 4 vystrčené listy.
func _nettle() -> void:
	_max_h = 0.65
	_col_lo = Color(0.05, 0.16, 0.05)
	_col_hi = Color(0.18, 0.36, 0.12)
	for k in 2:
		panel(k * TAU / 2.0 + 0.4, [[0.30, 0.0, 0.0], [0.33, 0.35, 0.0], [0.22, 0.65, 0.02]])
	for k in 4:
		blade(k * TAU / 4.0 + 0.8, 0.16, 0.18 + 0.12 * (k % 2), 0.30 + 0.12 * (k % 2), 0.05, 0.34,
			Color(0.12, 0.3, 0.1))
	commit("nettle")


## Keř: `panels` prohnutých stěn po obvodu (dó­m), `sq` zploštění špičky (0 kulatý, 0.35 rozložitý).
func _bush(name: String, panels: int, w: float, h: float, lo: Color, hi: Color, sq: float) -> void:
	_max_h = h
	_col_lo = lo
	_col_hi = hi
	for k in panels:
		panel(k * PI / panels,
			[[w * 0.45, 0.0, 0.0], [w, h * 0.42, 0.06 + sq * 0.1], [w * 0.8, h * 0.8, 0.04],
			 [w * 0.22, h, 0.0]])
	# víko – dvě zkřížené plošky nahoře
	for k in 2:
		blade(k * PI / 2.0, w * 0.5, h * 0.88, h * 0.96, -w * 0.5, w * 0.5, hi)
	commit(name)


## Obilný trs: 2 zkřížené úzké listovce (stéblo) + klasek (osmistěn nahoře).
func _wheat() -> void:
	_max_h = 1.05
	_col_lo = Color(0.28, 0.38, 0.12)
	_col_hi = Color(0.55, 0.50, 0.18)
	for k in 2:
		panel(k * TAU / 2.0 + 0.3, [[0.05, 0.0, 0.0], [0.045, 0.55, 0.0], [0.035, 0.85, 0.01]])
	octa(Vector3(0, 0.95, 0), 0.09, Color(0.72, 0.58, 0.22), 1.6)
	octa(Vector3(0.02, 0.99, 0.01), 0.06, Color(0.78, 0.63, 0.24), 1.4)
	commit("wheat")


## Polní plevel: nízká rozetta nakloněných listů.
func _weed() -> void:
	_max_h = 0.30
	_col_lo = Color(0.14, 0.26, 0.08)
	_col_hi = Color(0.36, 0.42, 0.14)
	for k in 5:
		blade(k * TAU / 5.0, 0.12, 0.02, 0.24, 0.03, 0.30, _col_lo.lerp(_col_hi, 0.6))
	panel(0.4, [[0.10, 0.0, 0.0], [0.06, 0.30, 0.03]])
	commit("weed_field")


## Zahrádková rostlina: listnatý trs s bobulkami (rajče/květ).
func _garden_veg() -> void:
	_max_h = 0.55
	_col_lo = Color(0.10, 0.22, 0.07)
	_col_hi = Color(0.30, 0.45, 0.15)
	for k in 3:
		panel(k * TAU / 3.0 + 0.2, [[0.10, 0.0, 0.0], [0.30, 0.22, 0.10], [0.18, 0.50, 0.22]])
	octa(Vector3(0.12, 0.30, 0.06), 0.055, Color(0.72, 0.16, 0.08), 0.9)
	octa(Vector3(-0.10, 0.38, -0.04), 0.045, Color(0.78, 0.25, 0.08), 0.9)
	octa(Vector3(0.02, 0.45, -0.12), 0.05, Color(0.85, 0.35, 0.12), 0.9)
	commit("garden_veg")
