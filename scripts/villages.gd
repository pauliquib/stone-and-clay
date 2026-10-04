## Vesnice v okolí katastru (data/obce.json, nástroj tools/obce.py) – jen vizuální zástavba
## pro pohled z výšky a z letadla: půdorysy budov vytažené do nízkých kvádrů (zdi) se
## sedlovou/valbovou střechou podle podélné osy půdorysu. Bez kolizí, NPC a stínů.
##
## Na každou obec jeden ArrayMesh (2 plochy: světlé zdi + tmavé střechy přes MeshKit,
## barvy z vrcholů) → 5 MeshInstance3D = ~10 draw callů. Výška terénu z `Terrain`
## uvnitř katastru, jinak z hrubé mřížky `Surroundings.height_at` (25 m) – paty zdí
## kopírují terén po bodech, základ je zapuštěný SINK pod terén kvůli svahům.
## Bez dat (chybí obce.json nebo grid okolí) se nic nestaví – hra běží (fallback jako Surroundings).
class_name Villages
extends Node3D

const DATA_PATH := "res://data/obce.json"
const SINK := 0.35              # zapuštění základu pod terén (m) – hrubá 25 m mřížka, svahy
const OVERHANG := 0.15          # přesah střechy přes zdi (m)
const SMALL_AREA := 20.0        # m² – menší budovy (garáž, kůlna) = nízký kvádr s plochou střechou
const MIN_AREA := 1.5           # m² – menší půdorys se přeskočí (šum v datech)
const MIN_EDGE := 0.05          # m – kratší hrana půdorysu se přeskočí (degenerace)

## Výšky okapu a hřebene podle druhu budovy [min, max] (m) + příznaky:
##   flat  = plochá střecha (triangulovaná čepice místo hřebene)
##   tower = věžička nad hřebenem (kostel/kaple – dominanta obce)
const STYLES := {
	"house":      {"eave": [2.9, 3.7], "ridge": [1.1, 1.7]},
	"public":     {"eave": [3.6, 5.0], "ridge": [1.2, 1.9]},
	"commercial": {"eave": [3.4, 4.6], "ridge": [0.6, 1.2], "flat": true},
	"industrial": {"eave": [4.2, 6.0], "ridge": [0.3, 0.8], "flat": true},
	"barn":       {"eave": [3.4, 4.5], "ridge": [1.8, 2.6]},
	"garage":     {"eave": [2.2, 2.7], "ridge": [0.4, 0.8], "flat": true},
	"shed":       {"eave": [1.9, 2.5], "ridge": [0.3, 0.7], "flat": true},
	"church":     {"eave": [6.5, 8.5], "ridge": [2.6, 3.6], "tower": 3.4},
	"chapel":     {"eave": [4.2, 5.4], "ridge": [1.6, 2.2], "tower": 1.8},
	"tower":      {"eave": [7.0, 11.0], "ridge": [1.8, 2.6]},
}

## Palety (vertex colors – žádné textury); váhy výběru v _pick.
const WALL_COLORS := [
	[Color(0.92, 0.90, 0.86), 0.34],   # bílá omítka
	[Color(0.87, 0.82, 0.72), 0.24],   # béžová
	[Color(0.85, 0.77, 0.55), 0.14],   # bledě žlutá
	[Color(0.80, 0.73, 0.62), 0.12],   # tmavší béž
	[Color(0.62, 0.44, 0.34), 0.10],   # tehlová
	[Color(0.78, 0.80, 0.72), 0.06],   # bledě zelená
]
const ROOF_COLORS := [
	[Color(0.48, 0.24, 0.16), 0.38],   # cihlová pálenka
	[Color(0.21, 0.21, 0.24), 0.28],   # antracit
	[Color(0.34, 0.24, 0.17), 0.22],   # hnědá
	[Color(0.40, 0.31, 0.23), 0.12],   # světlejší hnědá
]
const WALL_CHURCH := Color(0.93, 0.90, 0.83)
const ROOF_CHURCH := Color(0.36, 0.18, 0.13)
const WALL_INDUSTRIAL := Color(0.62, 0.62, 0.60)
const ROOF_INDUSTRIAL := Color(0.36, 0.37, 0.40)

var stats := {}                  # ladění / testy: id obce → {buildings, tris, aabb}
var _surr: Surroundings
var _terr: Terrain


## Postaví zástavbu okolních obcí. Volá World po `surroundings.setup` (potřebuje height_at).
## `terrain` je nepovinný – uvnitř katastru zpřesní posazení budov na okrajích.
func setup(surr: Surroundings, terrain: Terrain = null) -> void:
	_surr = surr
	_terr = terrain
	if _surr == null:
		push_warning("Villages: chybí Surroundings – obce se nestaví")
		return
	if not FileAccess.file_exists(DATA_PATH):
		push_warning("Villages: chybí %s – okolní obce bez zástavby (tools/obce.py)" % DATA_PATH)
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not (data is Dictionary) or not (data as Dictionary).has("obce"):
		push_warning("Villages: neznámý formát %s" % DATA_PATH)
		return
	for obec in (data as Dictionary)["obce"]:
		_build_obec(obec)


# ------------------------------------------------------------------ data → mesh

func _build_obec(obec: Dictionary) -> void:
	var id := String(obec.get("id", "obec"))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absi(id.hash()))
	var walls := MeshKit.new()
	var roofs := MeshKit.new()
	var nb := 0
	for b in obec.get("buildings", []):
		if _building(walls, roofs, b, rng):
			nb += 1
	if walls.is_empty() and roofs.is_empty():
		return
	var mesh := ArrayMesh.new()
	if not walls.is_empty():
		walls.commit(MeshKit.vc_material(0.9), mesh)
	if not roofs.is_empty():
		roofs.commit(MeshKit.vc_material(0.85), mesh)
	var mi := MeshInstance3D.new()
	mi.name = "Obec_" + id
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # vzdálené – výkon
	mi.set_meta("obec_id", id)
	add_child(mi)
	stats[id] = {"buildings": nb, "tris": (walls.idx.size() + roofs.idx.size()) / 3,
		"aabb": mesh.get_aabb()}


## Jedna budova: půdorys (absolutní souřadnice) → zdi do `walls`, střecha do `roofs`.
func _building(walls: MeshKit, roofs: MeshKit, b: Dictionary, rng: RandomNumberGenerator) -> bool:
	var poly := PackedVector2Array()
	for p in b.get("poly", []):
		if p is Array and p.size() >= 2 and (poly.is_empty() or poly[poly.size() - 1].distance_to(
				Vector2(float(p[0]), float(p[1]))) > MIN_EDGE):
			poly.append(Vector2(float(p[0]), float(p[1])))
	if poly.size() >= 2 and poly[0].distance_to(poly[poly.size() - 1]) <= MIN_EDGE:
		poly.remove_at(poly.size() - 1)
	if poly.size() < 3:
		return false
	var area := _signed_area(poly)
	if absf(area) < MIN_AREA:
		return false
	if area < 0.0:                       # sjednotit na CCW (interiér vlevo od hrany)
		poly.reverse()
		area = -area
	var c := _centroid(poly)
	var kind := String(b.get("kind", "house"))
	var style: Dictionary = STYLES.get(kind, STYLES["house"])
	var n := poly.size()

	# výšky: pata zdi kopíruje terén po bodech (svah), okap vodorovný na výšce centroidu
	var bottoms := PackedFloat32Array()
	bottoms.resize(n)
	for i in n:
		bottoms[i] = _ground(poly[i].x, poly[i].y) - SINK
	var gc := _ground(c.x, c.y)
	var eave: float = rng.randf_range(style["eave"][0], style["eave"][1])
	var eave_y := gc + eave

	var wcol := _pick(WALL_COLORS, rng)
	var rcol := _pick(ROOF_COLORS, rng)
	match kind:
		"church", "chapel":
			wcol = WALL_CHURCH
			rcol = ROOF_CHURCH
		"industrial":
			wcol = WALL_INDUSTRIAL
			rcol = ROOF_INDUSTRIAL

	# zdi – čtyřstěn na každé hraně, normála ven (vpravo od hrany u CCW polygonu)
	for i in n:
		var j := (i + 1) % n
		var e := poly[j] - poly[i]
		if e.length() < MIN_EDGE:
			continue
		var out := Vector3(e.y, 0.0, -e.x).normalized()
		_quad_n(walls, Vector3(poly[i].x, bottoms[i], poly[i].y),
			Vector3(poly[j].x, bottoms[j], poly[j].y),
			Vector3(poly[j].x, eave_y, poly[j].y), Vector3(poly[i].x, eave_y, poly[i].y),
			wcol, out)

	if area < SMALL_AREA or style.get("flat", false):
		_flat_cap(roofs, poly, c, eave_y, rcol)
	else:
		_ridge_roof(roofs, poly, c, eave_y, style, rng, rcol)
	var tower_h := float(style.get("tower", 0.0))
	if tower_h > 0.0:
		_tower(walls, roofs, poly, c, gc, eave_y, tower_h, wcol, rcol)
	return true


# ------------------------------------------------------------------ střechy

## Plochá čepice (garáže, kůlny, komerce) – triangulace půdorysu ve výšce okapu.
func _flat_cap(roofs: MeshKit, poly: PackedVector2Array, c: Vector2, y: float, col: Color) -> void:
	var local := PackedVector2Array()
	for p in poly:
		local.append(p - c)
	var tris := Geometry2D.triangulate_polygon(local)
	for k in range(0, tris.size(), 3):
		var a3 := Vector3(c.x + local[tris[k]].x, y, c.y + local[tris[k]].y)
		var b3 := Vector3(c.x + local[tris[k + 1]].x, y, c.y + local[tris[k + 1]].y)
		var c3 := Vector3(c.x + local[tris[k + 2]].x, y, c.y + local[tris[k + 2]].y)
		_tri_n(roofs, a3, b3, c3, col, Vector3.UP)


## Sedlová/valbová střecha: hřeben leží na podélné ose půdorysu (PCA), jeho délka =
## podélný rozsah − příčný (čtverec → pyramidová špice). Každá hrana půdorysu se
## s přesahem OVERHANG zvedne k příslušnému úseku hřebene → pro obdélník sedlovka,
## pro L-tvary valba podle tvaru – ze vzduchu působí jako skutečná střecha.
func _ridge_roof(roofs: MeshKit, poly: PackedVector2Array, c: Vector2, eave_y: float,
		style: Dictionary, rng: RandomNumberGenerator, col: Color) -> void:
	var ax := _axis(poly, c)
	var u: Vector2 = ax[0]
	var v := Vector2(-u.y, u.x)
	var n := poly.size()
	var ts := PackedFloat32Array()
	var ss := PackedFloat32Array()
	ts.resize(n)
	ss.resize(n)
	var tmin := INF
	var tmax := -INF
	var smin := INF
	var smax := -INF
	for i in n:
		var d := poly[i] - c
		ts[i] = d.dot(u)
		ss[i] = d.dot(v)
		tmin = minf(tmin, ts[i])
		tmax = maxf(tmax, ts[i])
		smin = minf(smin, ss[i])
		smax = maxf(smax, ss[i])
	var ridge_half := maxf(0.0, ((tmax - tmin) - (smax - smin)) * 0.5)
	var t_mid := (tmin + tmax) * 0.5
	var s_mid := (smin + smax) * 0.5
	var tr0 := t_mid - ridge_half
	var tr1 := t_mid + ridge_half
	var ridge_h: float = rng.randf_range(style["ridge"][0], style["ridge"][1])
	var ridge_y := eave_y + ridge_h

	# okapový věnec s přesahem + bod hřebene nad kolmicí každého vrcholu
	var eaves := PackedVector3Array()
	var rps := PackedVector3Array()
	eaves.resize(n)
	rps.resize(n)
	for i in n:
		var e_prev := poly[i] - poly[(i - 1 + n) % n]
		var e_next := poly[(i + 1) % n] - poly[i]
		var nv := Vector2(e_prev.y, -e_prev.x).normalized() + Vector2(e_next.y, -e_next.x).normalized()
		if nv.length() < 0.01:
			nv = Vector2(e_next.y, -e_next.x).normalized()
		eaves[i] = Vector3(poly[i].x + nv.x * OVERHANG, eave_y, poly[i].y + nv.y * OVERHANG)
		var tr := clampf(ts[i], tr0, tr1)
		var rp: Vector2 = c + u * tr + v * s_mid
		rps[i] = Vector3(rp.x, ridge_y, rp.y)

	for i in n:
		var j := (i + 1) % n
		var e := poly[j] - poly[i]
		if e.length() < MIN_EDGE:
			continue
		var out := Vector3(e.y, 0.3, -e.x)      # ven + nahoru (přesný směr dopočítá _tri_n/_quad_n)
		if eaves[i].distance_squared_to(eaves[j]) < MIN_EDGE * MIN_EDGE:
			continue
		if rps[i].distance_squared_to(rps[j]) < 0.0025:
			_tri_n(roofs, eaves[i], eaves[j], rps[i], col, out)
		else:
			_quad_n(roofs, eaves[i], eaves[j], rps[j], rps[i], col, out)


## Věžička kostela/kaple: hranol od země přes hřeben + jehlanová špice.
## Stojí na začátku hřebene (u kostela loď + věž); když bod leží mimo půdorys, do středu.
func _tower(walls: MeshKit, roofs: MeshKit, poly: PackedVector2Array, c: Vector2, gc: float,
		eave_y: float, tower_h: float, wcol: Color, rcol: Color) -> void:
	var ax := _axis(poly, c)
	var u: Vector2 = ax[0]
	var v := Vector2(-u.y, u.x)
	var tmin := INF
	var smin := INF
	var smax := -INF
	for p in poly:
		var d := p - c
		tmin = minf(tmin, d.dot(u))
		var s := d.dot(v)
		smin = minf(smin, s)
		smax = maxf(smax, s)
	var hw := clampf((smax - smin) * 0.18, 1.1, 1.8)
	var tc: Vector2 = c + u * (tmin + hw * 1.15) + v * (smin + smax) * 0.5
	if not Geometry2D.is_point_in_polygon(tc, poly):
		tc = c
	var y0 := gc - SINK
	var y1 := eave_y + 1.2 + tower_h
	var u3 := Vector3(u.x, 0.0, u.y) * hw
	var v3 := Vector3(v.x, 0.0, v.y) * hw
	var cc := Vector3(tc.x, 0.0, tc.y)
	for s in [-1.0, 1.0]:
		var fc: Vector3 = cc + u3 * s
		_quad_n(walls, Vector3(fc.x, y0, fc.z) - v3, Vector3(fc.x, y0, fc.z) + v3,
			Vector3(fc.x, y1, fc.z) + v3, Vector3(fc.x, y1, fc.z) - v3, wcol, u3.normalized() * s)
		fc = cc + v3 * s
		_quad_n(walls, Vector3(fc.x, y0, fc.z) - u3, Vector3(fc.x, y0, fc.z) + u3,
			Vector3(fc.x, y1, fc.z) + u3, Vector3(fc.x, y1, fc.z) - u3, wcol, v3.normalized() * s)
	# jehlanová špice
	var apex := Vector3(tc.x, y1 + hw * 1.5, tc.y)
	var su := u3 * 1.08
	var sv := v3 * 1.08
	var corners := [cc - su - sv, cc + su - sv, cc + su + sv, cc - su + sv]
	for i in 4:
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[(i + 1) % 4]
		a.y = y1
		b.y = y1
		var e := b - a
		_tri_n(roofs, a, b, apex, rcol, Vector3(e.z, 0.5, -e.x))   # ven ze štětiny + nahoru


# ------------------------------------------------------------------ pomocné

## Výška povrchu pro posazení: detailní terén uvnitř katastru, jinak mřížka okolí.
func _ground(x: float, z: float) -> float:
	if _terr != null and _terr.contains(x, z, 0.0):
		return _terr.height_at(x, z)
	return _surr.height_at(x, z)


static func _signed_area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


static func _centroid(poly: PackedVector2Array) -> Vector2:
	var cx := 0.0
	var cz := 0.0
	var a := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		var w := p.x * q.y - q.x * p.y
		a += w
		cx += (p.x + q.x) * w
		cz += (p.y + q.y) * w
	if absf(a) < 1e-6:
		return poly[0]
	return Vector2(cx / (3.0 * a), cz / (3.0 * a))


## Podélná osa půdorysu: vlastní vektor kovariance (PCA); u symetrie nejdelší hrana.
static func _axis(poly: PackedVector2Array, c: Vector2) -> Array:
	var sxx := 0.0
	var szz := 0.0
	var sxz := 0.0
	for p in poly:
		var d := p - c
		sxx += d.x * d.x
		szz += d.y * d.y
		sxz += d.x * d.y
	var u := Vector2.RIGHT
	if absf(sxz) < 1e-6:
		u = Vector2.RIGHT if sxx >= szz else Vector2(0.0, 1.0)
	else:
		var lam := 0.5 * (sxx + szz) + sqrt(0.25 * (sxx - szz) * (sxx - szz) + sxz * sxz)
		u = Vector2(sxz, lam - sxx).normalized()
	if absf(sxx - szz) < 0.02 * (sxx + szz):
		# skoro čtverec/kruh – PCA neurčitá, vzít nejdelší hranu
		var best := -1.0
		for i in poly.size():
			var l := poly[i].distance_squared_to(poly[(i + 1) % poly.size()])
			if l > best:
				best = l
				u = (poly[(i + 1) % poly.size()] - poly[i]).normalized()
	return [u]


static func _pick(palette: Array, rng: RandomNumberGenerator) -> Color:
	var r := rng.randf()
	for item in palette:
		r -= float(item[1])
		if r <= 0.0:
			return item[0]
	return palette[0][0]


## Trojúhelník s garantovanou orientací normály k `n` (winding podle potřeby obrátí).
static func _tri_n(kit: MeshKit, a: Vector3, b: Vector3, c: Vector3, col: Color, n: Vector3) -> void:
	if (c - a).cross(b - a).dot(n) >= 0.0:
		kit.tri(a, b, c, col)
	else:
		kit.tri(a, c, b, col)


## Čtyřstěn (a→b→c→d po obvodu) s normálou k `n`.
static func _quad_n(kit: MeshKit, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		col: Color, n: Vector3) -> void:
	if (c - a).cross(b - a).dot(n) >= 0.0:
		kit.quad(a, b, c, d, col)
	else:
		kit.quad(a, d, c, b, col)
