## Pták – model a letová fyzika. Popis druhů je v tabulce SPECIES (rozměry, barvy, let, chování).
##
## Let: rychlost podél směru letu se mění tahem (mávání), odporem (∝ v²) a složkou tíhy při stoupání;
## zatáčí se náklonem (úhlová rychlost = g·tan(náklon)/v, náklon omezený druhem), při malé rychlosti
## pták musí mávat, jinak klesá. Přistání = zpomalení a sestup k cíli, pak chůze / poskakování po zemi
## nebo sezení na větvi / střeše (klidová animace: otáčí hlavou, probírá peří). Mávání křídel a jejich
## složení se animuje podle stavu.
class_name Bird
extends Node3D

const G := 9.8

## length: délka těla (m), span: rozpětí, cruise: cestovní rychlost (m/s), flap_hz: mávání,
## bank: max. náklon (rad), climb: max. stoupání (rad), ground: walk / hop / none
const SPECIES := {
	"vrana": {"name": "Vrána obecná", "length": 0.46, "span": 0.95, "body": Color(0.07, 0.07, 0.08),
		"wing": Color(0.05, 0.05, 0.06), "belly": Color(0.09, 0.09, 0.1), "head": Color(0.05, 0.05, 0.06),
		"beak": Color(0.05, 0.05, 0.05), "legs": Color(0.05, 0.05, 0.05), "grey_morph": Color(0.42, 0.42, 0.44),
		"cruise": 11.0, "max_speed": 16.0, "flap_hz": 3.6, "bank": 0.8, "climb": 0.45, "ground": "walk",
		"walk_speed": 0.55, "flight_d": 28.0, "vis": 260.0, "call": "crow", "fingers": 4},
	"kos": {"name": "Kos černý", "length": 0.25, "span": 0.37, "body": Color(0.04, 0.04, 0.04),
		"wing": Color(0.03, 0.03, 0.03), "belly": Color(0.05, 0.05, 0.05), "head": Color(0.04, 0.04, 0.04),
		"beak": Color(0.95, 0.6, 0.08), "legs": Color(0.2, 0.15, 0.1), "female": Color(0.3, 0.22, 0.15),
		"cruise": 9.0, "max_speed": 13.0, "flap_hz": 9.0, "bank": 1.0, "climb": 0.6, "ground": "hop",
		"walk_speed": 0.0, "flight_d": 9.0, "vis": 90.0, "call": "blackbird"},
	"vlastovka": {"name": "Vlaštovka obecná", "length": 0.19, "span": 0.33, "body": Color(0.06, 0.08, 0.2),
		"wing": Color(0.04, 0.05, 0.12), "belly": Color(0.92, 0.88, 0.8), "head": Color(0.06, 0.08, 0.2),
		"throat": Color(0.6, 0.18, 0.1), "beak": Color(0.05, 0.05, 0.05), "legs": Color(0.1, 0.08, 0.07),
		"streamers": 0.07, "cruise": 11.0, "max_speed": 16.0, "flap_hz": 7.0, "bank": 1.25, "climb": 0.7,
		"ground": "none", "walk_speed": 0.0, "flight_d": 0.0, "vis": 150.0, "call": "swallow"},
	"kane": {"name": "Káně lesní", "length": 0.53, "span": 1.22, "body": Color(0.36, 0.25, 0.16),
		"wing": Color(0.3, 0.2, 0.12), "belly": Color(0.78, 0.7, 0.58), "head": Color(0.34, 0.24, 0.15),
		"beak": Color(0.2, 0.18, 0.15), "legs": Color(0.85, 0.75, 0.2), "cruise": 9.5, "max_speed": 18.0,
		"flap_hz": 2.6, "bank": 0.6, "climb": 0.35, "ground": "none", "walk_speed": 0.0, "flight_d": 45.0,
		"vis": 600.0, "call": "buzzard", "fingers": 5},
}

## Klidová animace na bidýlku: otáčení hlavy do stran a občasné probírání peří
const REST_LOOK := 0.8               # největší pootočení hlavy (rad)
const PREEN_TIME := 0.6              # jak dlouho trvá probírání peří (s)

static var _cache := {}

var spec: Dictionary
var species := ""
var state := "fly"                   # fly, ground, perch, soar
var vel := Vector3.ZERO
var speed := 0.0
var yaw := 0.0
var pitch := 0.0
var bank := 0.0
var target := Vector3.ZERO
var land_on := ""                    # "", ground, perch – co udělá u cíle
var soar_center := Vector3.ZERO
var soar_r := 50.0
var rng := RandomNumberGenerator.new()
var terrain: Terrain
var female := false
var grey := false
var perch_off := 0.05                # o kolik výš než bidýlko se pták posadí (střecha / předmět: nohy, strom: 0,05 m)

var _body: Node3D
var _head: Node3D
var _wings: Array[Node3D] = []       # [L vnitřní, L vnější, P vnitřní, P vnější]
var _tail: Node3D
var _flap := 0.0
var _flapping := true
var _fold := 0.0
var _glide := 0.0                    # klouzavý let – špičky křídel zahnuté dozadu
var _hop_t := 0.0
var _peck_t := 0.0
var _peck := 0.0
var _hop_y := 0.0
var _walk_p := 0.0                   # fáze kráčení (kývání hlavy vrány)
var _moving := 0.0                   # 0..1 pták se právě hýbe po zemi
var _head_z := 0.0                   # klidová poloha hlavy ve směru z
var _flick := 0.0                    # ocas vzhůru po dopadu / škleb (kos)
var _flick_t := 0.0
var _was_fly := true
var _look_t := 0.0                   # čas do dalšího pootočení hlavy na bidýlku
var _look_to := 0.0                  # cílové pootočení hlavy (rad)
var _preen_t := 0.0                  # zbývá probírání peří (s)
var _rest_yaw := 0.0                 # aktuální natočení hlavy (rad)
var _rest_pitch := 0.0               # aktuální sklon hlavy při probírání (rad)


func setup(id: String, t: Terrain, pos: Vector3, seed_: int) -> void:
	species = id
	spec = SPECIES[id]
	terrain = t
	rng.seed = seed_
	position = pos
	female = spec.has("female") and rng.randf() < 0.5
	grey = spec.has("grey_morph") and rng.randf() < 0.35
	yaw = rng.randf() * TAU
	speed = spec["cruise"]


func _ready() -> void:
	var key := "%s|%s|%s" % [species, female, grey]
	if not _cache.has(key):
		_cache[key] = _build_meshes()
	var ms: Dictionary = _cache[key]
	var vis: float = spec["vis"]
	_body = Node3D.new()
	add_child(_body)
	MeshKit.mesh_instance(_body, ms["body"], vis)
	_head = Node3D.new()
	_head_z = float(spec["length"]) * 0.38
	_head.position = Vector3(0, 0.02, _head_z)
	_body.add_child(_head)
	MeshKit.mesh_instance(_head, ms["head"], vis)
	_tail = Node3D.new()
	_tail.position = Vector3(0, 0, -spec["length"] * 0.28)
	_body.add_child(_tail)
	MeshKit.mesh_instance(_tail, ms["tail"], vis)
	var half: float = spec["span"] * 0.5
	for side: float in [1.0, -1.0]:
		var inner := Node3D.new()
		inner.position = Vector3(side * spec["length"] * 0.08, 0.02, spec["length"] * 0.08)
		_body.add_child(inner)
		MeshKit.mesh_instance(inner, ms["wing_in_l" if side > 0 else "wing_in_r"], vis)
		var outer := Node3D.new()
		outer.position = Vector3(side * half * 0.45, 0, 0)
		inner.add_child(outer)
		MeshKit.mesh_instance(outer, ms["wing_out_l" if side > 0 else "wing_out_r"], vis)
		_wings.append(inner)
		_wings.append(outer)


## Model: tělo a hlava z elipsoidů, zobák, křídla jako zploštělé tvarované plochy (vnitřní a vnější část),
## ocas vějíř (vlaštovka s dlouhými krajními pery).
func _build_meshes() -> Dictionary:
	var ms := {}
	var L: float = spec["length"]
	var half: float = spec["span"] * 0.5
	var bc: Color = spec["female"] if female else spec["body"]
	var wc: Color = spec["female"].darkened(0.1) if female else spec["wing"]
	var belly: Color = spec["female"].lightened(0.15) if female else spec["belly"]
	var hc: Color = spec["female"] if female else spec["head"]
	if grey:
		bc = spec["grey_morph"]
		belly = spec["grey_morph"].lightened(0.1)
	var mat := QuadrupedModel.fur_material(1.0)   # barvy vrcholů jako sRGB, oboustranné plochy
	var k := MeshKit.new()
	k.sphere(Vector3(0, 0, 0), L * 0.2, bc, Vector3(0.8, 0.75, 1.55))
	k.sphere(Vector3(0, -L * 0.05, L * 0.05), L * 0.17, belly, Vector3(0.78, 0.7, 1.3))
	if spec.has("throat"):
		k.sphere(Vector3(0, -L * 0.02, L * 0.27), L * 0.08, spec["throat"])
	# nohy (při letu zatažené pod tělem – jen krátké)
	for s: float in [1.0, -1.0]:
		k.box(Vector3(s * L * 0.05, -L * 0.2, -L * 0.02), Vector3(L * 0.02, L * 0.18, L * 0.02), spec["legs"])
		k.box(Vector3(s * L * 0.05, -L * 0.29, L * 0.03), Vector3(L * 0.05, L * 0.012, L * 0.1), spec["legs"])
	ms["body"] = k.commit(mat)
	k = MeshKit.new()
	k.sphere(Vector3(0, L * 0.02, 0), L * 0.1, hc, Vector3(0.9, 0.9, 1.1))
	k.cylinder(Vector3(0, L * 0.0, L * 0.13), 0.0005, L * 0.035, L * 0.12, spec["beak"], Vector3(PI / 2, 0, 0), 8)
	for s: float in [1.0, -1.0]:
		k.sphere(Vector3(s * L * 0.07, L * 0.04, L * 0.05), L * 0.014, Color(0.02, 0.02, 0.02))
	ms["head"] = k.commit(mat)
	k = MeshKit.new()
	var tl := L * 0.3
	k.quad(Vector3(-L * 0.04, 0, 0), Vector3(L * 0.04, 0, 0), Vector3(L * 0.1, 0, -tl), Vector3(-L * 0.1, 0, -tl), wc)
	var st: float = spec.get("streamers", 0.0)
	if st > 0.0:
		for s: float in [1.0, -1.0]:
			k.quad(Vector3(s * L * 0.06, 0, -tl * 0.8), Vector3(s * L * 0.09, 0, -tl * 0.8),
				Vector3(s * L * 0.13, 0, -tl - st), Vector3(s * L * 0.115, 0, -tl - st), wc)
	ms["tail"] = k.commit(mat)
	# křídla: vnitřní (od těla) a vnější (špička) díl, tětiva se k špičce zužuje
	var chord := L * 0.42 * (0.7 if species == "vlastovka" else 1.0)
	for side: float in [1.0, -1.0]:
		var s := side
		var tag := "l" if side > 0 else "r"
		k = MeshKit.new()
		var x1 := half * 0.45
		_wing_panel(k, s, 0.0, x1, chord, chord * 0.9, 0.0, -chord * 0.05, wc, belly.lerp(wc, 0.5))
		ms["wing_in_" + tag] = k.commit(mat)
		k = MeshKit.new()
		var x2 := half * 0.55
		var sweep := chord * (0.45 if species == "vlastovka" else 0.15)
		_wing_panel(k, s, 0.0, x2, chord * 0.9, chord * 0.35, -chord * 0.05, -sweep, wc.darkened(0.1), wc)
		# roztažené „prsty“ letek na špičce křídla (káně, vrána)
		var nf: int = spec.get("fingers", 0)
		if nf > 0:
			var ctip := chord * 0.35               # tětiva na špičce
			var zt := -chord * 0.05 - sweep        # náběžná hrana špičky
			var fc := wc.darkened(0.15)
			for fi in nf:
				var zr := zt - ctip * (0.3 + fi * 0.34)        # kořen péra po zadní hraně
				var fw := ctip * 0.30                        # šířka peříčka
				var fl := ctip * (2.4 - fi * 0.15)           # délka dozadu
				var xr := s * (x2 - ctip * 0.15)
				var xt := s * (x2 + ctip * (0.55 + fi * 0.14))
				k.quad(Vector3(xr, 0.004, zr), Vector3(xr + s * fw, 0.004, zr + fw * 0.2),
					Vector3(xt + s * fw * 0.5, 0.001, zr - fl), Vector3(xt, 0.001, zr - fl - fw * 0.4), fc)
		ms["wing_out_" + tag] = k.commit(mat)
	return ms


## Plocha křídla od x0 do x1 (na straně `s`), tětivy c0 → c1, náběžná hrana posunutá o z0 → z1.
## Horní a spodní strana (spodní světlejší), mírně klenutá.
func _wing_panel(k: MeshKit, s: float, x0: float, x1: float, c0: float, c1: float, z0: float, z1: float, top: Color, bottom: Color) -> void:
	var n := 4
	for i in n:
		var ta := float(i) / n
		var tb := float(i + 1) / n
		var xa := s * lerpf(x0, x1, ta)
		var xb := s * lerpf(x0, x1, tb)
		var ca := lerpf(c0, c1, ta)
		var cb := lerpf(c0, c1, tb)
		var za := lerpf(z0, z1, ta) + c0 * 0.3
		var zb := lerpf(z0, z1, tb) + c0 * 0.3
		var arch := 0.012 * c0
		var la := Vector3(xa, arch, za)
		var lb := Vector3(xb, arch, zb)
		var ra := Vector3(xa, 0, za - ca)
		var rb := Vector3(xb, 0, zb - cb)
		if s > 0:
			k.quad(la, lb, rb, ra, top)
			k.quad(la, ra, rb, lb, bottom)
		else:
			k.quad(lb, la, ra, rb, top)
			k.quad(lb, rb, ra, la, bottom)


# ------------------------------------------------------------------ let

## Krok letu směrem k `target`. Vrací vzdálenost k cíli.
func fly_step(delta: float, want_speed: float) -> float:
	var to := target - global_position
	var dist := to.length()
	var hd := Vector2(to.x, to.z).length()
	var want_yaw := atan2(to.x, to.z)
	var diff := wrapf(want_yaw - yaw, -PI, PI)
	var v := maxf(speed, 2.0)
	var max_rate := G * tan(float(spec["bank"])) / v
	var rate := clampf(diff * 2.5, -max_rate, max_rate)
	yaw = wrapf(yaw + rate * delta, -PI, PI)
	bank = lerpf(bank, atan(rate * v / G), 1.0 - exp(-delta * 6.0))
	var climb := clampf(atan2(to.y, maxf(hd, 0.5)), -float(spec["climb"]) * 1.4, float(spec["climb"]))
	# drž se nad terénem (a nad korunami)
	var ground := terrain.height_at(global_position.x + sin(yaw) * v, global_position.z + cos(yaw) * v)
	if land_on == "" and global_position.y < ground + 3.0:
		climb = maxf(climb, 0.35)
	pitch = lerpf(pitch, climb, 1.0 - exp(-delta * 3.0))
	# energie: tah mávání, odpor, tíha
	var cruise: float = spec["cruise"]
	var ws := minf(want_speed, float(spec["max_speed"]))
	_flapping = speed < ws * 0.95 or pitch > 0.08 or (species == "vlastovka" and fmod(Time.get_ticks_msec() * 0.001 + get_instance_id() % 7, 2.2) < 1.3)
	var thrust := 6.0 if _flapping else 0.0
	var drag := 0.5 * speed * speed / (cruise * cruise) * 3.0
	speed += (thrust - drag - G * sin(pitch)) * delta
	speed = clampf(speed, 1.0, float(spec["max_speed"]))
	if species == "kane" and not _flapping:
		speed = lerpf(speed, ws, delta * 0.5)     # stoupavý proud nese
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	vel = dir * speed
	global_position += vel * delta
	var gy := terrain.height_at(global_position.x, global_position.z)
	if global_position.y < gy + 0.3:
		global_position.y = gy + 0.3
	return dist


func _process(delta: float) -> void:
	if not visible:
		return
	# poloha těla a animace křídel
	_body.rotation = Vector3(-pitch, yaw, -bank) if state in ["fly", "soar"] else Vector3(0.05 + _peck * 0.35, yaw, 0.0)
	var flying := state in ["fly", "soar"]
	_fold = move_toward(_fold, 0.0 if flying else 1.0, delta * 4.0)
	# klouzavý let: vlaštovka a vrána zahnete špičky křídel dozadu (káně drží roztažené kruhy)
	var want_g := 1.0 if flying and not _flapping and species != "kane" else 0.0
	_glide = lerpf(_glide, want_g, minf(delta * 4.0, 1.0))
	# dopad / škleb: kos (i ostatní) hned po přistání ocas vykloní vzhůru
	if not flying and _was_fly:
		_flick = 1.0
	_was_fly = flying
	_flick = move_toward(_flick, 0.0, delta * 1.6)
	if species == "kos" and not flying:
		_flick_t -= delta
		if _flick_t <= 0.0:
			_flick_t = rng.randf_range(0.8, 2.4)
			_flick = 1.0
	var amp := 0.0
	if flying and _flapping:
		_flap += delta * float(spec["flap_hz"]) * TAU
		amp = 0.85 if species != "kane" else 0.45
	elif flying:
		_flap = lerp_angle(_flap, 0.0, delta * 3.0)
	var a := sin(_flap) * amp
	var b := sin(_flap - 0.6) * amp * 0.6
	var glide_dihedral := 0.08 if species != "kane" else 0.14
	for i in 2:
		var s := 1.0 if i == 0 else -1.0
		var inner := _wings[i * 2]
		var outer := _wings[i * 2 + 1]
		var up := a if flying else 0.0
		inner.rotation = Vector3(0, s * (_fold * 1.35 + _glide * 0.3), s * (up + glide_dihedral) * (1.0 - _fold) + s * _fold * 0.2)
		outer.rotation = Vector3(0, s * (_fold * 2.6 + _glide * 0.9), s * b * (1.0 - _fold))
	_tail.rotation.x = -pitch * 0.4 if flying else 0.22 + _flick * 0.55
	_head.position.z = _head_z + sin(_walk_p) * float(spec["length"]) * 0.06 * _moving
	# na bidýlku: hlava se plynule otáčí do stran, občas se pták probere v peří (hlava dolů k boku)
	var kk := 1.0 - exp(-delta * 6.0)
	var want_ry := 0.0
	var want_rp := 0.0
	if state == "perch":
		_look_t -= delta
		if _look_t <= 0.0:
			_look_t = rng.randf_range(1.0, 3.0)
			_look_to = rng.randf_range(-REST_LOOK, REST_LOOK)
			if _preen_t <= 0.0 and rng.randf() < 0.18:
				_preen_t = PREEN_TIME
				_look_to = REST_LOOK * (1.0 if _look_to >= 0.0 else -1.0)
		if _preen_t > 0.0:
			_preen_t -= delta
			want_rp = 0.7
		want_ry = _look_to
	_rest_yaw = lerpf(_rest_yaw, want_ry, kk)
	_rest_pitch = lerpf(_rest_pitch, want_rp, kk)
	_head.rotation.y = _rest_yaw
	_head.rotation.x = _peck * 1.1 + cos(_walk_p) * 0.18 * _moving + _rest_pitch
	_body.position.y = sin(clampf(_hop_y / 0.18, 0.0, 1.0) * PI) * float(spec["length"]) * 0.25 if _hop_y > 0.0 else 0.0


## Chůze / poskakování po zemi (vrána kráčí, kos skáče a zastavuje), občas klovne.
func ground_step(delta: float, dest: Vector3) -> void:
	var to := dest - global_position
	to.y = 0.0
	_peck_t -= delta
	if _peck_t <= 0.0:
		_peck_t = rng.randf_range(0.8, 3.5)
		_peck = 1.0
	_peck = move_toward(_peck, 0.0, delta * 3.0)
	if spec["ground"] == "hop":
		_hop_t -= delta
		if _hop_t <= 0.0 and to.length() > 0.3:
			_hop_t = rng.randf_range(0.35, 1.2)
			yaw = atan2(to.x, to.z) + rng.randf_range(-0.3, 0.3)
			_hop_y = 0.001
		if _hop_y > 0.0:
			_hop_y += delta
			var t := _hop_y / 0.18
			global_position += Vector3(sin(yaw), 0, cos(yaw)) * 1.6 * delta
			_hop_y = 0.0 if t >= 1.0 else _hop_y
	elif to.length() > 0.3:
		yaw = lerp_angle(yaw, atan2(to.x, to.z), 1.0 - exp(-delta * 3.0))
		global_position += Vector3(sin(yaw), 0, cos(yaw)) * float(spec["walk_speed"]) * delta
		# kráčivá chůze: fáze kroků pohání kývání hlavy (vrána)
		_walk_p += delta * float(spec["walk_speed"]) * TAU / maxf(float(spec["length"]) * 0.45, 0.05)
		_moving = 1.0
	else:
		_moving = move_toward(_moving, 0.0, delta * 6.0)
	global_position.y = terrain.height_at(global_position.x, global_position.z) + float(spec["length"]) * 0.28
	speed = 0.0
	pitch = 0.0
	bank = 0.0
