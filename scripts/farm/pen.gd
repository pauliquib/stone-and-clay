## Výběh pro hospodářská zvířata u usedlosti (M2.6; M1.7: původní dům hráče `Estate.lot_id`, zvířata jen s vlastním domem): dřevěná ohrada s kolizí (jako `Paddock`, kůň má
## svůj vlastní výběh a nemísí se sem), branka na straně k domu a tři přístřešky uvnitř – kurník (slepice,
## králíci), chlívek (prase) a otevřený přístřešek (koza, ovce, kráva) – plus jedna společná napáječka.
##
## Místo hledá `_find_spot` stejným způsobem jako `Paddock._find_spot` / `Garden._find_spot` (volná rovná
## plocha, mimo silnici, dům, kolizní věci) a navíc mimo výběh koně a zahradu; když se nenajde nic, výběh
## se nepostaví (`ok = false`) – `Farm` pak zvířata nekoupí (cedule to řekne).
class_name Pen
extends Node3D

const SIZES := [Vector2(20.0, 15.0), Vector2(16.0, 12.0), Vector2(13.0, 10.0)]   # DOPLNIT: „výběh ~20 × 15 m“ z promptu
const GATE_W := 3.0
const POST_STEP := 2.5
const FENCE_H := 1.1
const SPOT_R0 := 10.0
const SPOT_R1 := 100.0
const SPOT_TRIES := 260
const SPOT_MAX_DH := 2.2
const SPOT_ROAD_GAP := 3.0

var world: World
var ok := false
var center := Vector3.ZERO
var yaw := 0.0
var half := Vector2.ZERO
var gate_open := false
var water := Vector3.ZERO
var sign_pos := Vector3.ZERO
var shelters := {}                   # "kurnik" / "chlivek" / "pristresek" → {"pos": Vector3, "feed": Vector3}


func setup(w: World) -> void:
	world = w
	if not w.places.has("domov"):
		return
	var door := w.lot_door()          # M1.7: hospodářství zůstává u usedlosti
	var hc: Dictionary = w.meta.get("domov_hrace", {})
	var face := Vector2(float(hc.get("x", door.x)), float(hc.get("z", door.z)))
	setup_at(w, door, face, 2260)


## Výběh kolem libovolného bodu (M3.2: statek `Statek`) – `face` = bod, od kterého se výběh natočí (střed stavení),
## `seed_` = jiné pořadí hledání místa. Když se místo nenajde, `ok` zůstane false.
func setup_at(w: World, around: Vector3, face: Vector2, seed_: int) -> void:
	world = w
	var door := around
	for sz in SIZES:
		var size: Vector2 = sz
		var sp: Array = _find_spot(door, face, size, seed_)
		if sp.is_empty():
			continue
		center = sp[0]
		yaw = sp[1]
		half = size * 0.5
		ok = true
		break
	if not ok:
		push_warning("Výběh hospodářských zvířat: nenašlo se volné místo (seed %d)." % seed_)
		return
	_build()


func _fwd() -> Vector3:
	return Vector3(sin(yaw), 0.0, cos(yaw))


func _right() -> Vector3:
	return Vector3(cos(yaw), 0.0, -sin(yaw))


func to_world(lx: float, lz: float) -> Vector3:
	var p := center + _right() * lx + _fwd() * lz
	p.y = world.terrain.height_at(p.x, p.z)
	return p


func contains(p: Vector3) -> bool:
	if not ok:
		return false
	var d := p - center
	var lx := d.dot(_right())
	var lz := d.dot(_fwd())
	return absf(lx) < half.x - 0.3 and absf(lz) < half.y - 0.3


## Náhodný bod uvnitř výběhu (okraj o `margin` blíž ke středu) – vzor pastvy / bloudění zvířat.
func random_point(rng: RandomNumberGenerator, margin := 1.0) -> Vector3:
	var lx := rng.randf_range(-half.x + margin, half.x - margin)
	var lz := rng.randf_range(-half.y + margin, half.y - margin)
	return to_world(lx, lz)


func gate_in() -> Vector3:
	return to_world(0.0, -half.y + 1.6)


func gate_out() -> Vector3:
	return to_world(0.0, -half.y - 3.0)


func gate_world() -> Vector3:
	return to_world(0.0, -half.y)


func shelter_pos(kind: String) -> Vector3:
	var s: Dictionary = shelters.get(kind, {})
	if s.is_empty():
		return center
	var p: Vector3 = s["pos"]
	return p


func feed_pos(kind: String) -> Vector3:
	var s: Dictionary = shelters.get(kind, {})
	if s.is_empty():
		return center
	var p: Vector3 = s["feed"]
	return p


# ------------------------------------------------------------------ hledání místa (vzor `Paddock._find_spot`)

func _find_spot(around: Vector3, face_from: Vector2, size: Vector2, seed_ := 2260) -> Array:
	var space := world.get_world_3d().direct_space_state
	var bx := BoxShape3D.new()
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = bx
	q.collision_mask = 1 | 8 | 16
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var diag := size.length() * 0.5
	var pad = world.paddock
	var gard = world.garden
	for i in SPOT_TRIES:
		var a := rng.randf() * TAU
		var r := lerpf(SPOT_R0, SPOT_R1, float(i) / SPOT_TRIES)
		var x := around.x + cos(a) * r
		var z := around.z + sin(a) * r
		if world.dist_to_roads(Vector2(x, z)) < diag + SPOT_ROAD_GAP:
			continue
		if pad != null and pad.ok and Vector2(x, z).distance_to(Vector2(pad.center.x, pad.center.z)) < diag + pad.half.length() + 1.5:
			continue
		if gard != null:
			var too_close := false
			for pl in gard.plots:
				var gp: Garden.Plot = pl
				var pr: float = maxf(float(gp.w), float(gp.d)) * 0.5
				if Vector2(x, z).distance_to(Vector2(gp.center.x, gp.center.z)) < diag + pr + 2.0:
					too_close = true
					break
			if too_close:
				continue
		var away := Vector2(x, z) - face_from
		var yw := atan2(away.x, away.y)
		var fwd := Vector3(sin(yw), 0, cos(yw))
		var right := Vector3(cos(yw), 0, -sin(yw))
		var ok_ := true
		var hmin := INF
		var hmax := -INF
		for sx in [-1.0, 0.0, 1.0]:
			for sz_ in [-1.0, 0.0, 1.0]:
				var pp: Vector3 = Vector3(x, 0, z) + right * (size.x * 0.5 * float(sx)) + fwd * (size.y * 0.5 * float(sz_))
				var h: float = world.terrain.height_at(pp.x, pp.z)
				hmin = minf(hmin, h)
				hmax = maxf(hmax, h)
				var ray := PhysicsRayQueryParameters3D.create(Vector3(pp.x, h + 40.0, pp.z), Vector3(pp.x, h - 3.0, pp.z), 1)
				var hit := space.intersect_ray(ray)
				if hit.is_empty() or (hit["collider"] as Node).get_meta("surface", "") != "teren":
					ok_ = false
					break
			if not ok_:
				break
		if not ok_ or hmax - hmin > SPOT_MAX_DH:
			continue
		bx.size = Vector3(size.x + 1.0, 2.5, size.y + 1.0)
		q.transform = Transform3D(Basis(Vector3.UP, yw), Vector3(x, hmax + 0.2 + 1.25, z))
		if space.intersect_shape(q, 1).is_empty():
			return [Vector3(x, world.terrain.height_at(x, z), z), yw]
	return []


# ------------------------------------------------------------------ stavba

func _build() -> void:
	var body := StaticBody3D.new()
	body.name = "Plot"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var wood := Color(0.48, 0.34, 0.2)
	var dark := wood.darkened(0.3)
	var k := MeshKit.new()
	var hx := half.x
	var hz := half.y
	var g := GATE_W * 0.5
	var runs: Array = [
		_run(Vector2(-hx, -hz), Vector2(-g, -hz)),
		_run(Vector2(g, -hz), Vector2(hx, -hz)),
		_run(Vector2(hx, -hz), Vector2(hx, hz)),
		_run(Vector2(hx, hz), Vector2(-hx, hz)),
		_run(Vector2(-hx, hz), Vector2(-hx, -hz)),
	]
	var post_done := {}
	for run in runs:
		var pts: Array = run
		for i in pts.size():
			var pw: Vector3 = pts[i]
			var key := Vector2i(roundi(pw.x * 10.0), roundi(pw.z * 10.0))
			if not post_done.has(key):
				post_done[key] = true
				k.box(pw + Vector3(0, (FENCE_H - 0.3) * 0.5, 0), Vector3(0.13, FENCE_H + 0.3, 0.13), dark)
			if i == 0:
				continue
			var a: Vector3 = pts[i - 1]
			var d := pw - a
			var len_ := d.length()
			var rot := Vector3(-asin(clampf(d.y / len_, -1.0, 1.0)), atan2(d.x, d.z), 0.0)
			var mid := (pw + a) * 0.5
			for hh: float in [0.4, 0.85]:
				k.box(mid + Vector3(0, hh, 0), Vector3(0.045, 0.1, len_), wood, rot)
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(0.16, FENCE_H + 0.2, len_)
			cs.shape = bs
			cs.transform = Transform3D(Basis.from_euler(rot), mid + Vector3(0, (FENCE_H + 0.2) * 0.5 - 0.1, 0))
			body.add_child(cs)
	for sx: float in [-g, g]:
		var gp := to_world(sx, -hz)
		k.box(gp + Vector3(0, 0.65, 0), Vector3(0.18, 1.9, 0.18), dark)
	sign_pos = to_world(-hx - 0.5, -hz - 0.3)
	k.box(sign_pos + Vector3(0, 0.5, 0), Vector3(0.07, 1.0, 0.07), wood)
	k.box(sign_pos + Vector3(0, 0.85, 0), Vector3(0.55, 0.28, 0.04), Color(0.72, 0.6, 0.38))
	# tři přístřešky: kurník (roh u branky), chlívek (protilehlý roh), přístřešek pastvin (uprostřed zadní strany)
	shelters["kurnik"] = {"pos": to_world(-hx + 1.6, -hz + 1.8), "feed": to_world(-hx + 1.6, -hz + 3.0)}
	shelters["chlivek"] = {"pos": to_world(hx - 2.0, hz - 2.2), "feed": to_world(hx - 2.0, hz - 3.8)}
	shelters["pristresek"] = {"pos": to_world(-hx + 2.5, hz - 2.0), "feed": to_world(-hx + 2.5, hz - 3.6)}
	water = to_world(0.0, hz - 1.4)
	_build_kurnik(k, shelters["kurnik"]["pos"])
	_build_chlivek(k, shelters["chlivek"]["pos"])
	_build_pristresek(k, shelters["pristresek"]["pos"])
	k.cylinder(water + Vector3(0, 0.22, 0), 0.55, 0.5, 0.45, Color(0.35, 0.36, 0.38))
	k.cylinder(water + Vector3(0, 0.44, 0), 0.46, 0.46, 0.03, Color(0.3, 0.5, 0.65))
	var cs2 := CollisionShape3D.new()
	var b2 := BoxShape3D.new()
	b2.size = Vector3(1.1, 0.6, 1.1)
	cs2.shape = b2
	cs2.transform = Transform3D(Basis.IDENTITY, water + Vector3(0, 0.3, 0))
	body.add_child(cs2)
	var mi := MeshKit.mesh_instance(self, k.commit(MeshKit.vc_material(0.85)), 400.0)
	mi.name = "Hospodarstvi"


## Kurník: bedna na nohách s rampou (slepice do ní v noci vejdou po rampě – zjednodušeně jen vizuál,
## `FarmAnimal` na noc přejde k `shelter_pos` bez skutečného vylézání po rampě).
func _build_kurnik(k: MeshKit, p: Vector3) -> void:
	var wood := Color(0.55, 0.4, 0.25)
	k.box(p + Vector3(0, 0.75, 0), Vector3(1.4, 0.9, 1.0), wood)
	k.box(p + Vector3(0, 1.3, 0), Vector3(1.5, 0.12, 1.1), wood.darkened(0.2), Vector3(0.35, 0, 0))
	for sx: float in [-0.6, 0.6]:
		for sz: float in [-0.4, 0.4]:
			k.box(p + Vector3(sx, 0.3, sz), Vector3(0.08, 0.6, 0.08), wood.darkened(0.3))
	k.box(p + Vector3(0.35, 0.15, 0.55) + Vector3(0, 0.0, 0.35), Vector3(0.4, 0.03, 0.9), wood.darkened(0.1), Vector3(-0.5, 0, 0))


## Chlívek: nízká zděná / dřevěná bouda.
func _build_chlivek(k: MeshKit, p: Vector3) -> void:
	var wall := Color(0.72, 0.68, 0.6)
	var roof := Color(0.35, 0.28, 0.22)
	k.box(p + Vector3(0, 0.6, 0), Vector3(2.2, 1.2, 1.8), wall)
	k.box(p + Vector3(0, 1.3, 0), Vector3(2.4, 0.1, 2.0), roof, Vector3(0.25, 0, 0))


## Přístřešek pro kozy / ovce / krávu: tři strany a šikmá střecha, otevřený k výběhu.
func _build_pristresek(k: MeshKit, p: Vector3) -> void:
	var wood := Color(0.45, 0.32, 0.2)
	var roof := Color(0.32, 0.26, 0.2)
	for sx: float in [-1.3, 1.3]:
		k.box(p + Vector3(sx, 1.0, 0), Vector3(0.1, 2.0, 2.2), wood)
	k.box(p + Vector3(0, 1.0, -1.05), Vector3(2.6, 2.0, 0.1), wood)
	k.box(p + Vector3(0, 2.05, 0.1), Vector3(2.8, 0.12, 2.5), roof, Vector3(0.12, 0, 0))


func _run(a: Vector2, b: Vector2) -> Array:
	var n := maxi(ceili(a.distance_to(b) / POST_STEP), 1)
	var out := []
	for i in n + 1:
		var t := float(i) / n
		var l := a.lerp(b, t)
		out.append(to_world(l.x, l.y))
	return out
