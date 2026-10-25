## M8.14 Přízemní vegetace – low-poly modely všech typů (tráva, kopřivy, keře, obilí, plevel, zahrádky, vlhká a suchá
## louka, kapradí, borůvčí, mech, jarní byliny, hrabanka / jehličí, devětsil, šípek, louční květ). Patka v počátku,
## UV.y = poměrná výška (0 patka … 1 špička).
##
## **Barvy vrcholů podle 00_PRINCIPY kap. 4** (ne albedo!): `r` ohebnost (0 patka … 1 špička), `g` fáze listu / stébla
## (hash 0..1), `b` váha třepetání (0 stonek, 1 list / květ), `a` okluze (0 jádro trsu … 1 okraj). Albedo dodá shader
## z uniformů `veg_lo` → `veg_hi` (po výšce) a `veg_acc` (květ / bobule – UV.x > 0,5), viz `VegetationManager.VEG_CONFIG`.
##
## Vzhled 2026-10 (realistická vegetace): stébla a listy jsou **geometrie** (zúžená prohnutá stébla, kosočtverečné listy
## s přehybem – bez alfa testu, levné na všech předvolbách), keře / kapradí / devětsil / květy jsou **karty s
## procedurálním výřezem** ve `vegetation.gdshader` (listy v buňkách, lístky kapradí, okvětní lístky – žádná textura).
## Druh plochy říká UV.x (osminy, viz K_*), souřadnice uvnitř karty nese UV2 (x napříč 0..1, y podél 0..1).
## Normály jsou „měkké“ (ven z trsu / koruny keře + nahoru) – trs se stínuje jako celek, ne po plochých panelech.
##
## Stejný kód používá offline generátor (`tools/gen_vegetation_meshes.gd` → `assets/models/vegetation/<id>.res`)
## i hra jako fallback, když `.res` chybí (`VegetationManager._mesh`) – modely jsou deterministické (pevné semínko).
class_name GroundVegMeshes
extends RefCounted

const IDS := ["grass_tall", "nettle", "bush_hazel", "bush_blackthorn", "wheat", "weed_field", "garden_veg",
	"herb_wet", "herb_dry", "fern", "bilberry", "moss", "spring_flowers", "litter", "butterbur", "rosehip",
	"meadow_flower"]
## UV.x = druh plochy (střed osminy; shader: floor(UV.x · 8)); > 0,5 = akcent (veg_acc – květ, bobule, klas).
const K_DISC := 0.0625                  # 0 kulatý list (devětsil) – výřez
const K_LEAFCARD := 0.1875              # 1 karta trsu listů (keře, borůvčí) – výřez po buňkách
const FOLIAGE_U := 0.3125               # 2 plné stéblo / list / stonek (geometrie)
const K_FROND := 0.4375                 # 3 list kapradí (lístky) – výřez
const K_FLOWER_TOP := 0.5625            # 4 květ shora (okvětní lístky) – výřez, akcent
const K_FLOWER_SIDE := 0.6875           # 5 květ z boku – výřez, akcent
const ACCENT_U := 0.8125                # 6 plný akcent (bobule, klas, lata)
const K_LITTER := 0.9375                # 7 hrabanka (listí na zemi, okraj výřezem) – UV2 = souřadnice × LITTER_REP
const LITTER_REP := 5.0                 # = LITTER_REP ve vegetation.gdshader

var _v := PackedVector3Array()
var _n := PackedVector3Array()
var _c := PackedColorArray()
var _uv := PackedVector2Array()
var _uv2 := PackedVector2Array()
var _i := PackedInt32Array()
var _max_h := 1.0
var _phase := 0.0
var _rng := RandomNumberGenerator.new()


## Postaví model `id` (jeden z IDS). Neznámé id → prázdný mesh (a varování).
static func build(id: String) -> ArrayMesh:
	var b := GroundVegMeshes.new()
	b._rng.seed = hash(id)
	match id:
		"grass_tall":
			b._grass_tall()
		"nettle":
			b._nettle()
		"bush_hazel":
			b._bush(1.3, 0.62, 0.78, 15, 0.46, 0.0)
		"bush_blackthorn":
			b._bush(1.4, 0.58, 0.85, 17, 0.34, 0.35)
		"wheat":
			b._wheat()
		"weed_field":
			b._weed()
		"garden_veg":
			b._garden_veg()
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
		"meadow_flower":
			b._meadow_flower()
		_:
			push_warning("GroundVegMeshes: neznámý model %s" % id)
	return b._commit(id)


func _next_phase() -> float:
	_phase = fposmod(_phase + 0.618034, 1.0)
	return _phase


func _rel(y: float) -> float:
	return clampf(y / _max_h, 0.0, 1.0)


func _add(p: Vector3, n: Vector3, col: Color, kind: float, uv2: Vector2) -> int:
	_v.append(p)
	_n.append(n.normalized())
	_c.append(col)
	_uv.append(Vector2(kind, _rel(p.y)))
	_uv2.append(uv2)
	return _v.size() - 1


## Měkká normála: ven od osy trsu (xz) a nahoru – trs / keř se stínuje jako celek (ne ploché panely).
func _soft_n(p: Vector3, up := 0.8) -> Vector3:
	var o := Vector3(p.x, 0.0, p.z)
	if o.length() < 0.001:
		return Vector3.UP
	return (o.normalized() * (1.0 - up) + Vector3.UP * up).normalized()


## Zúžené prohnuté stéblo / stonek (geometrie, bez výřezu): pata `root`, směr vyklonění `ang` (rad), výška `h`,
## půlšířka `w`, vyklonění špičky `lean` (× h), `segs` úseků; poslední úsek končí hrotem (1 vrchol).
func _blade(root: Vector3, ang: float, h: float, w: float, lean: float, segs := 3, leaf := 0.6,
		kind := FOLIAGE_U, twist := 0.0) -> void:
	_next_phase()
	var out := Vector3(cos(ang), 0.0, sin(ang))
	var prev: Array = []
	for s in segs + 1:
		var t := float(s) / segs
		var p := root + out * (lean * h * t * t) + Vector3.UP * (h * t * (1.0 - 0.3 * lean * t * t))
		var side := Vector3(-out.z, 0.0, out.x).rotated(Vector3.UP, twist * t)
		var ww := w * pow(1.0 - t, 0.7) if s < segs else 0.0
		var nrm := (_soft_n(p, 0.55) + out * 0.3).normalized()
		var col := Color(_rel(p.y) * lerpf(0.7, 1.0, t), _phase, leaf * t, lerpf(0.45, 1.0, t))
		var cur: Array = []
		if s < segs:
			cur.append(_add(p - side * ww, nrm, col, kind, Vector2(0.0, t)))
			cur.append(_add(p + side * ww, nrm, col, kind, Vector2(1.0, t)))
		else:
			cur.append(_add(p, nrm, col, kind, Vector2(0.5, 1.0)))
		if not prev.is_empty():
			if cur.size() == 2:
				_i.append_array([prev[0], prev[1], cur[0], prev[1], cur[1], cur[0]])
			else:
				_i.append_array([prev[0], prev[1], cur[0]])
		prev = cur


## Kosočtverečný list s přehybem podél žilky (4 trojúhelníky): pata `base`, směr `ang`, délka `l`, půlšířka `w`,
## sklon `pitch` (+ nahoru, − převislý), `droop` = pokles špičky (× l).
func _leaf(base: Vector3, ang: float, l: float, w: float, pitch: float, droop := 0.15, fold := 0.25,
		occl := 0.9) -> void:
	_next_phase()
	var d := Vector3(cos(ang) * cos(pitch), sin(pitch), sin(ang) * cos(pitch))
	var side := Vector3(-sin(ang), 0.0, cos(ang))
	var up := d.cross(side).normalized()
	if up.y < 0.0:
		up = -up
	var mid := base + d * (l * 0.45) - Vector3.UP * (droop * l * 0.25)
	var tip := base + d * l - Vector3.UP * (droop * l)
	var lft := mid + side * w + up * (fold * w)
	var rgt := mid - side * w + up * (fold * w)
	var nrm := (up * 0.75 + _soft_n(mid, 0.5) * 0.5).normalized()
	var rb := _rel(base.y)
	var cb := Color(rb * 0.85, _phase, 0.45, occl * 0.8)
	var ct := Color(minf(rb + 0.1, 1.0), _phase, 1.0, occl)
	var i0 := _add(base, nrm, cb, FOLIAGE_U, Vector2(0.5, 0.0))
	var i1 := _add(lft, nrm, ct, FOLIAGE_U, Vector2(0.0, 0.45))
	var i2 := _add(rgt, nrm, ct, FOLIAGE_U, Vector2(1.0, 0.45))
	var i3 := _add(tip, nrm, ct, FOLIAGE_U, Vector2(0.5, 1.0))
	var i4 := _add(mid + up * 0.002, nrm, ct, FOLIAGE_U, Vector2(0.5, 0.45))
	_i.append_array([i0, i1, i4, i0, i4, i2, i4, i1, i3, i4, i3, i2])


## Karta (quad) se souřadnicemi UV2 0..1: střed `c`, osy `ax` (napříč, půldélka) a `ay` (podél, půldélka),
## normála `nrm` (měkká), `occl` okluze, `flex` ohebnost (r), `leaf` třepetání (b).
func _card(c: Vector3, ax: Vector3, ay: Vector3, nrm: Vector3, kind: float, occl: float, flex: float,
		leaf := 1.0) -> void:
	_next_phase()
	var col_lo := Color(flex * 0.85, _phase, leaf * 0.7, occl * 0.85)
	var col_hi := Color(flex, _phase, leaf, occl)
	var a := _add(c - ax - ay, nrm, col_lo, kind, Vector2(0, 0))
	var b := _add(c + ax - ay, nrm, col_lo, kind, Vector2(1, 0))
	var d := _add(c + ax + ay, nrm, col_hi, kind, Vector2(1, 1))
	var e := _add(c - ax + ay, nrm, col_hi, kind, Vector2(0, 1))
	_i.append_array([a, b, d, a, d, e])


## Prohnutý pás (list kapradí, stvol): body podél oblouku, šířka `w` × profil; UV2.y podél, UV2.x napříč.
func _strip(root: Vector3, ang: float, l: float, w: float, rise: float, segs: int, kind: float, occl := 0.9) -> void:
	_next_phase()
	var out := Vector3(cos(ang), 0.0, sin(ang))
	var side := Vector3(-out.z, 0.0, out.x)
	var prev: Array = []
	for s in segs + 1:
		var t := float(s) / segs
		# oblouk: stoupá, pak se špička skloní (list kapradí se klene ven)
		var p := root + out * (l * t) + Vector3.UP * (l * rise * sin(t * PI * 0.62) * (1.0 - 0.45 * t * t))
		var nrm := (Vector3.UP * 0.8 + out * 0.2 + _soft_n(p, 0.6) * 0.3).normalized()
		var col := Color(_rel(p.y) * 0.5 + 0.5 * t, _phase, t, lerpf(occl * 0.6, occl, t))
		var a := _add(p - side * w, nrm, col, kind, Vector2(0.0, t))
		var b := _add(p + side * w, nrm, col, kind, Vector2(1.0, t))
		if not prev.is_empty():
			_i.append_array([prev[0], prev[1], a, prev[1], b, a])
		prev = [a, b]


## Květ: karta shora (okvětí) + dvě zkřížené svislé karty z boku – zblízka i z dálky / shora.
func _flower(c: Vector3, r: float, tilt := 0.2) -> void:
	var ang := _rng.randf() * TAU
	var tdir := Vector3(cos(ang), 0.0, sin(ang))
	var nrm := (Vector3.UP + tdir * tilt).normalized()
	var ax := tdir.cross(Vector3.UP).normalized()
	var ay := nrm.cross(ax).normalized()
	var flex := _rel(c.y)
	_card(c, ax * r, ay * r, nrm, K_FLOWER_TOP, 1.0, flex, 1.0)
	for k in 2:
		var a2 := ang + k * PI * 0.5 + 0.4
		var sx := Vector3(cos(a2), 0.0, sin(a2)) * r
		_card(c + Vector3.UP * (r * 0.05), sx, Vector3.UP * r * 0.55, _soft_n(c + sx, 0.5), K_FLOWER_SIDE, 1.0, flex, 1.0)


## Bobule / klas / lata – osmistěn (8 trojúhelníků), albedo z akcentu.
func _octa(center: Vector3, r: float, squash := 0.6) -> void:
	_next_phase()
	var base := _v.size()
	var pts := [Vector3(0, r * squash, 0), Vector3(r, 0, 0), Vector3(0, 0, r), Vector3(-r, 0, 0),
		Vector3(0, 0, -r), Vector3(0, -r * squash, 0)]
	for p in pts:
		var q: Vector3 = center + p
		_v.append(q)
		_n.append(((p as Vector3).normalized() + Vector3.UP * 0.3).normalized())
		_c.append(Color(_rel(center.y), _phase, 0.9, 1.0))
		_uv.append(Vector2(ACCENT_U, _rel(q.y)))
		_uv2.append(Vector2(0.5, 0.5))
	for s in 4:
		var a := 1 + s
		var b := 1 + (s + 1) % 4
		_i.append_array([base, base + a, base + b])
		_i.append_array([base + 5, base + b, base + a])


## Klubko karet trsu listí na elipsoidu (keř, borůvčí): `n` karet velikosti `size` kolem středu `ctr`,
## poloosy `rad` (xz) × `ry`; normály ven z elipsoidu (měkké světlo), okluze podle vzdálenosti od středu.
func _leaf_dome(ctr: Vector3, rad: float, ry: float, n: int, size: float, flex := 0.8) -> void:
	for k in n:
		# rovnoměrně po horní ~3/4 elipsoidu (zlatý úhel)
		var u := (k + 0.5) / n
		var el := lerpf(1.25, -0.35, u) + _rng.randf_range(-0.12, 0.12)
		var az := k * 2.39996 + _rng.randf_range(-0.3, 0.3)
		var dirv := Vector3(cos(az) * cos(el), sin(el), sin(az) * cos(el))
		var depth := _rng.randf_range(0.55, 0.95)
		var p := ctr + Vector3(dirv.x * rad, dirv.y * ry, dirv.z * rad) * depth
		var nrm := Vector3(dirv.x / rad, dirv.y / ry, dirv.z / rad).normalized()
		# karta zhruba tečně k povrchu, náhodně natočená a nakloněná
		var t1 := nrm.cross(Vector3.UP if absf(nrm.y) < 0.9 else Vector3.RIGHT).normalized()
		var t2 := nrm.cross(t1).normalized()
		var rot := _rng.randf() * TAU
		var ax := (t1 * cos(rot) + t2 * sin(rot)) * size * 0.5
		var ay := (t2 * cos(rot) - t1 * sin(rot)) * size * 0.5
		var tilt := _rng.randf_range(-0.35, 0.35)
		ax = ax.rotated(ay.normalized(), tilt)
		_card(p, ax, ay, nrm, K_LEAFCARD, lerpf(0.55, 1.0, depth), flex * lerpf(0.6, 1.0, _rel(p.y)))
	# vnitřní výplň: dvě zkřížené svislé karty (tmavé jádro – keř není průhledný)
	for k in 2:
		var a := k * PI * 0.5 + 0.3
		var ax := Vector3(cos(a), 0.0, sin(a)) * rad * 0.85
		_card(ctr, ax, Vector3.UP * ry * 0.8, _soft_n(ctr + ax, 0.6), K_LEAFCARD, 0.35, flex * 0.5)


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
	arr[Mesh.ARRAY_TEX_UV2] = _uv2
	arr[Mesh.ARRAY_INDEX] = _i
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.resource_name = id
	return m


func tri_count() -> int:
	return _i.size() / 3


# ------------------------------------------------------------------ modely

## Vysoká tráva: trs ~24 zúžených prohnutých stébel + 3 kvetoucí stébla s latou (akcent).
func _grass_tall() -> void:
	_max_h = 0.95
	for k in 24:
		var a := k * 2.39996 + _rng.randf_range(-0.3, 0.3)
		var rr := _rng.randf_range(0.0, 0.12)
		var root := Vector3(cos(a) * rr, 0.0, sin(a) * rr)
		_blade(root, a + _rng.randf_range(-0.4, 0.4), _rng.randf_range(0.4, 0.85), _rng.randf_range(0.007, 0.013),
			_rng.randf_range(0.12, 0.5), 3, 0.6, FOLIAGE_U, _rng.randf_range(-0.8, 0.8))
	for k in 3:
		var a := k * TAU / 3.0 + 0.5
		var root := Vector3(cos(a) * 0.04, 0.0, sin(a) * 0.04)
		var h := _rng.randf_range(0.8, 0.92)
		var lean := 0.12
		_blade(root, a, h, 0.006, lean, 2, 0.3)
		var top := root + Vector3(cos(a), 0, sin(a)) * (lean * h) + Vector3.UP * (h * (1.0 - 0.3 * lean))
		_octa(top + Vector3.UP * 0.04, 0.008, 5.5)       # štíhlá lata / klas trávy


## Kopřiva: 4 lodyhy, vstřícné listy po patrech (křižmostojné), listy se zmenšují ke špičce.
func _nettle() -> void:
	_max_h = 0.8
	for s in 4:
		var a := s * TAU / 4.0 + _rng.randf_range(-0.4, 0.4)
		var root := Vector3(cos(a) * 0.08, 0.0, sin(a) * 0.08)
		var h := _rng.randf_range(0.55, 0.8)
		_blade(root, a, h, 0.008, 0.1, 2, 0.2)
		var out := Vector3(cos(a), 0, sin(a))
		for lv in 4:
			var t := 0.3 + 0.18 * lv
			var p := root + out * (0.1 * h * t * t) + Vector3.UP * (h * t)
			var la := a + lv * PI * 0.5 + _rng.randf_range(-0.2, 0.2)
			var l := lerpf(0.13, 0.06, float(lv) / 3.0)
			for side in 2:
				_leaf(p, la + side * PI, l, l * 0.42, lerpf(0.1, 0.45, float(lv) / 3.0), 0.3, 0.25, lerpf(0.7, 1.0, t))


## Keř (líska, trnka): pruty od země + klubko karet listí; `sq` zploštění (trnka je rozložitější).
func _bush(h: float, w: float, cy_k: float, cards: int, card: float, sq: float) -> void:
	_max_h = h
	for k in 6:
		var a := k * TAU / 6.0 + _rng.randf_range(-0.3, 0.3)
		_blade(Vector3(cos(a) * 0.05, 0, sin(a) * 0.05), a, h * _rng.randf_range(0.75, 0.95), 0.012, 0.35 + sq * 0.3, 3, 0.1)
	_leaf_dome(Vector3(0, h * cy_k * 0.72, 0), w * (1.0 + sq * 0.25), h * 0.42 * (1.0 - sq * 0.3), cards, card)


## Obilný trs: 6 stébel, na každém 2 listy a klas (akcent).
func _wheat() -> void:
	_max_h = 1.05
	for k in 6:
		var a := k * 2.39996 + _rng.randf_range(-0.2, 0.2)
		var root := Vector3(cos(a) * 0.035, 0.0, sin(a) * 0.035)
		var h := _rng.randf_range(0.82, 0.95)
		var lean := _rng.randf_range(0.04, 0.12)
		_blade(root, a, h, 0.007, lean, 3, 0.25)
		for lv in 2:
			_blade(root + Vector3.UP * (0.18 + 0.2 * lv), a + PI * (0.6 + lv * 0.9), 0.3, 0.012, 0.75, 2, 0.8)
		var top := root + Vector3(cos(a), 0, sin(a)) * (lean * h) + Vector3.UP * (h * (1.0 - 0.3 * lean))
		_octa(top + Vector3.UP * 0.045, 0.017, 2.8)


## Polní plevel: přízemní růžice listů a lodyha s drobnými květy.
func _weed() -> void:
	_max_h = 0.35
	for k in 7:
		var a := k * TAU / 7.0 + _rng.randf_range(-0.2, 0.2)
		_leaf(Vector3(0, 0.01, 0), a, _rng.randf_range(0.14, 0.2), 0.05, _rng.randf_range(0.15, 0.4), 0.25, 0.3, 0.85)
	_blade(Vector3.ZERO, 0.4, 0.3, 0.006, 0.1, 2, 0.3)
	_flower(Vector3(0.03, 0.31, 0.01), 0.03, 0.2)


## Zahrádková rostlina: listnatý trs (karty listí) a plody (rajče / paprika – akcent).
func _garden_veg() -> void:
	_max_h = 0.6
	for k in 4:
		var a := k * TAU / 4.0
		_blade(Vector3.ZERO, a, 0.5, 0.01, 0.3, 2, 0.2)
	_leaf_dome(Vector3(0, 0.32, 0), 0.26, 0.22, 7, 0.24, 0.6)
	_octa(Vector3(0.12, 0.28, 0.06), 0.045, 0.9)
	_octa(Vector3(-0.10, 0.36, -0.04), 0.04, 0.9)
	_octa(Vector3(0.02, 0.24, -0.13), 0.045, 0.9)


## Vlhká louka (pcháč zelinný, kohoutek, tužebník): lodyhy s listy a květenství nahoře.
func _herb_wet() -> void:
	_max_h = 1.0
	for s in 3:
		var a := s * TAU / 3.0 + 0.3
		var root := Vector3(cos(a) * 0.05, 0, sin(a) * 0.05)
		var h := _rng.randf_range(0.8, 0.95)
		_blade(root, a, h, 0.008, 0.12, 3, 0.2)
		for lv in 3:
			var t := 0.2 + 0.22 * lv
			var p := root + Vector3(cos(a), 0, sin(a)) * (0.12 * h * t * t) + Vector3.UP * (h * t)
			_leaf(p, a + lv * 2.1, lerpf(0.16, 0.09, lv / 2.0), 0.035, 0.3, 0.3, 0.3, lerpf(0.7, 1.0, t))
		var top := root + Vector3(cos(a), 0, sin(a)) * (0.12 * h) + Vector3.UP * (h * 0.964)
		_flower(top + Vector3.UP * 0.02, 0.05, 0.3)
	for k in 6:
		var a := k * TAU / 6.0
		_blade(Vector3.ZERO, a, _rng.randf_range(0.25, 0.4), 0.02, 0.5, 2, 0.6)


## Suchá stráň (šalvěj luční, mateřídouška, kostřava): nízký trs stébel a drobné květy.
func _herb_dry() -> void:
	_max_h = 0.42
	for k in 12:
		var a := k * 2.39996
		_blade(Vector3(cos(a) * 0.04, 0, sin(a) * 0.04), a, _rng.randf_range(0.18, 0.34), 0.009, _rng.randf_range(0.2, 0.55), 2, 0.6)
	for k in 4:
		var a := k * TAU / 4.0 + 0.6
		var root := Vector3(cos(a) * 0.05, 0, sin(a) * 0.05)
		var h := _rng.randf_range(0.3, 0.4)
		_blade(root, a, h, 0.005, 0.15, 2, 0.3)
		_flower(root + Vector3(cos(a), 0, sin(a)) * (0.15 * h) + Vector3.UP * (h * 0.97), 0.03, 0.4)


## Kapradí (kapraď samec): 7 klenutých listů (karty s výřezem lístků) do kruhu.
func _fern() -> void:
	_max_h = 0.75
	for k in 7:
		var a := k * TAU / 7.0 + _rng.randf_range(-0.2, 0.2)
		_strip(Vector3(cos(a) * 0.04, 0.02, sin(a) * 0.04), a, _rng.randf_range(0.6, 0.8), 0.13, 0.95, 4, K_FROND)


## Borůvčí: nízký hustý keřík (pruty + karty drobných listů) a tmavomodré bobule.
func _bilberry() -> void:
	_max_h = 0.35
	for k in 5:
		var a := k * TAU / 5.0
		_blade(Vector3.ZERO, a, 0.32, 0.006, 0.4, 2, 0.2)
	_leaf_dome(Vector3(0, 0.18, 0), 0.24, 0.14, 8, 0.16, 0.6)
	_octa(Vector3(0.14, 0.20, 0.05), 0.016, 1.0)
	_octa(Vector3(-0.12, 0.24, -0.08), 0.016, 1.0)
	_octa(Vector3(0.03, 0.16, 0.16), 0.016, 1.0)
	_octa(Vector3(-0.05, 0.13, 0.12), 0.016, 1.0)


## Mech: nízký polštář (dva zploštělé jehlany – albedo z veg_lo/veg_hi, ne akcent).
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
			_uv2.append(Vector2(0.5, 0.5))
		for s in 4:
			_i.append_array([base, base + 1 + s, base + 1 + (s + 1) % 4])


## Jarní podrost listnatého lesa (sasanka hajní, dymnivka): listy v přeslenu a bílé / fialové květy.
func _spring_flowers() -> void:
	_max_h = 0.20
	for k in 5:
		_leaf(Vector3(0, 0.08, 0), k * TAU / 5.0 + 0.4, 0.09, 0.035, 0.1, 0.3, 0.3, 0.9)
	for k in 3:
		var a := k * TAU / 3.0
		var root := Vector3(cos(a) * 0.05, 0, sin(a) * 0.05)
		_blade(root, a, 0.16, 0.004, 0.15, 2, 0.3)
		_flower(root + Vector3(cos(a), 0, sin(a)) * 0.024 + Vector3.UP * 0.165, 0.028, 0.35)


## Hrabanka / jehličí: dva ploché kusy přes sebe; listy a okraj výřezem v shaderu (barvu dá tint instance).
func _litter() -> void:
	_max_h = 0.05
	for k in 2:
		var rot := Basis(Vector3.UP, k * 1.1)
		var w := 0.75 - 0.15 * k
		var l := 0.6 - 0.1 * k
		var y := 0.012 + 0.008 * k
		_next_phase()
		var base := _v.size()
		var corners := [Vector3(-w, y, -l), Vector3(w, y + 0.01, -l), Vector3(-w, y + 0.01, l), Vector3(w, y, l)]
		var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]
		for j in 4:
			_v.append(rot * (corners[j] as Vector3))
			_n.append(Vector3.UP)
			_c.append(Color(0.0, _phase, 0.0, 0.8))
			_uv.append(Vector2(K_LITTER, (uvs[j] as Vector2).y))
			_uv2.append((uvs[j] as Vector2) * LITTER_REP)
		_i.append_array([base, base + 1, base + 2, base + 1, base + 3, base + 2])


## Devětsil u potoka: velké kulaté listy (výřez) na stopkách.
func _butterbur() -> void:
	_max_h = 0.65
	for k in 5:
		var a := k * TAU / 5.0 + 0.3
		var l := _rng.randf_range(0.3, 0.45)
		var out := Vector3(cos(a), 0, sin(a))
		_blade(Vector3.ZERO, a, l, 0.008, 0.45, 2, 0.2)
		var top := out * (0.45 * l) + Vector3.UP * (l * (1.0 - 0.3 * 0.45))
		var rr := _rng.randf_range(0.2, 0.26)
		var tilt := _rng.randf_range(0.15, 0.45)
		var nrm := (Vector3.UP + out * tilt).normalized()
		var ax := out.cross(Vector3.UP).normalized()
		var ay := nrm.cross(ax).normalized()
		_card(top + out * (rr * 0.6), ax * rr, ay * rr, nrm, K_DISC, 0.9, _rel(top.y), 1.0)


## Šípek (růže šípková) – keř sukcese neposekaných luk: obloukovité pruty, karty listí a červené šípky.
func _rosehip() -> void:
	_max_h = 1.4
	for k in 6:
		var a := k * TAU / 6.0 + _rng.randf_range(-0.3, 0.3)
		_blade(Vector3(cos(a) * 0.05, 0, sin(a) * 0.05), a, _rng.randf_range(1.0, 1.35), 0.012, 0.75, 3, 0.15)
	_leaf_dome(Vector3(0, 0.78, 0), 0.62, 0.48, 14, 0.36)
	for k in 7:
		var a := k * 2.39996
		var el := _rng.randf_range(-0.2, 0.9)
		var p := Vector3(cos(a) * cos(el) * 0.58, 0.78 + sin(el) * 0.46, sin(a) * cos(el) * 0.58)
		_octa(p, 0.035, 1.3)


## Louční květ (kopretina, pryskyřník, chrpa / jetel, kohoutek): stvol, dva lístky a květ. Barvu i tvar okvětí
## dává instance (`MeadowFlowers`: INSTANCE_CUSTOM.rgb barva, a = typ květu / 4).
func _meadow_flower() -> void:
	_max_h = 0.34
	_blade(Vector3.ZERO, 0.0, 0.3, 0.004, 0.12, 2, 0.3)
	_leaf(Vector3(0, 0.03, 0), 0.6, 0.09, 0.022, 0.35, 0.3, 0.3, 0.8)
	_leaf(Vector3(0, 0.06, 0), 3.5, 0.08, 0.02, 0.3, 0.3, 0.3, 0.8)
	_flower(Vector3(0.036, 0.305, 0.0), 0.04, 0.25)
