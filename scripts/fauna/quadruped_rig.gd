## Kostra a procedurální animace čtyřnohého zvířete (staví ji QuadrupedModel z AnimalSpecs).
##
## Chůze: fáze kroku běží s kmitočtem podle délky nohou (dynamická podobnost – větší zvíře kráčí pomaleji),
## každá noha má posun fáze podle chodu (krok = 4 takty, klus = diagonální dvojice, cval = 3 takty,
## trysk / skoky zajíce). Noha na zemi (stojná fáze, podíl „duty“) se pohybuje dozadu přesně tak rychle,
## jak jde tělo dopředu (chodidla neklouzají), ve fázi přenosu se ohne a přenese dopředu.
## Trup se pohupuje (krok, klus) nebo houpe (cval), naklání se do zatáčky a podle svahu, hlava vyrovnává.
##
## IK chodidel: je-li nastaveno `ground_fn` (x, z) → y terénu, každá stojící noha se podle země
## prohne / natáhne tak, aby kopyto leželo na ní (svahy, nerovnosti); při přenosu nohy a ve vzduchu
## se náprava pomalu vrací na nulu. Lehání jde po dvojicích nohou (lehá předními, vstává podle druhu),
## při otáčení na místě nohy přešlapují, z prudkého brzdění se trup vykloní.
##
## Vstupy nastavuje chování (Animal / Horse) každý snímek: speed, turn_rate, slope, graze, alert, lie,
## look_yaw, airborne, dead, crouch, sit; volá animate(delta).
class_name QuadrupedRig
extends Node3D

signal footfall(leg: int)            # dopad kopyta (zvuk) – 0 LP, 1 PP, 2 LZ, 3 PZ

## váhy IK nápravy na články nohy (stehno / holeň / spěnka)
const IK_W := [0.45, 0.9, 0.7]

## posuny fází nohou [LP, PP, LZ, PZ] a podíl stojné fáze
const GAITS := {
	"walk": {"off": [0.25, 0.75, 0.0, 0.5], "duty": 0.64, "k": 0.85},
	"trot": {"off": [0.0, 0.5, 0.5, 0.0], "duty": 0.46, "k": 1.2},
	"canter": {"off": [0.3, 0.55, 0.0, 0.3], "duty": 0.38, "k": 1.3},
	"gallop": {"off": [0.45, 0.55, 0.0, 0.1], "duty": 0.3, "k": 1.5},
	"bound": {"off": [0.42, 0.5, 0.0, 0.04], "duty": 0.26, "k": 1.45},
}

var spec: Dictionary
var body: Node3D
var neck: Node3D
var head: Node3D
var tail: Node3D
var ears: Array[Node3D] = []
var saddle: Node3D                   # sedlo (kůň) – sem si sedá jezdec
var legs: Array = []                 # {nodes:[3× Node3D], front, side, rest, fold, lie, lift_per_fold}
var body_y := 0.5                    # klidová výška osy trupu nad zemí
var lie_y := 0.2                     # výška osy trupu vleže
var shoulder_h := 0.5                # výška ramenního kloubu (pro kmitočet kroku)
var neck_angle := 1.0
var head_tilt := 0.9
var ride := {}                       # póza jezdce (kůň): seat, stirrups, hands (lokálně vůči saddle)

# --- vstupy (nastavuje chování)
var speed := 0.0                     # m/s dopředu (záporná = couvání)
var turn_rate := 0.0                 # rad/s (+ doleva)
var slope := 0.0                     # sklon terénu ve směru pohybu (rad, + do kopce)
var graze := 0.0                     # 0..1 hlava u země (pastva / rytí)
var alert := 0.0                     # 0..1 hlava nahoře, uši nastražené
var lie := 0.0                       # 0..1 leží
var crouch := 0.0                    # 0..1 přikrčený (zajíc v pelechu), uši přitisknuté
var look_yaw := 0.0                  # otočení hlavy k cíli (rad, + doleva)
var airborne := 0.0                  # 0..1 ve skoku (nohy složené)
var dead := 0.0                      # 0..1 uhynulé (leží na boku)
var sit := 0.0                       # 0..1 sedí na zadních, přední v nohavicích (zajíc „panáček")
var rooting := false                 # rytí (kývání hlavou u země)
var gait := "walk"

var foot_ik := true                  # IK chodidel podle terénu (vypíná se ve vzdáleném LOD)
var ground_fn := Callable()          # (x, z) → výška terénu; prázdné = rovná země bez IK
var ik_max := 0.18                   # max. náprsa nohy IK (m)

var phase := 0.0
var _move_w := 0.0
var _off := [0.25, 0.75, 0.0, 0.5]
var _duty := 0.64
var _t := 0.0
var _ear_t := 0.0
var _ear_twitch := 0.0
var _tail_t := 0.0
var _ik := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])   # vyhlazená náprsa dosahu nohy (m)
var _leg_lie := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _lie_prev := 0.0
var _prev_v := 0.0
var _brake := 0.0                    # prudké brzdění 0..1 (postoj „na zadní")
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_t = _rng.randf() * 10.0


## Výběr chodu podle rychlosti (s hysterezí, aby chod na hranici nepřeskakoval).
func _pick_gait(v: float) -> String:
	var g: Dictionary = spec["gaits"]
	var fast: String = spec.get("gallop_kind", "gallop")
	var order := ["walk", "trot", "canter", fast]
	var cur := order.find(gait)
	if cur < 0:
		cur = 0
	var lim := [float(g["walk"]), float(g["trot"]), float(g["canter"])]
	var want := 3
	for i in 3:
		if v <= lim[i]:
			want = i
			break
	# hystereze ±8 %
	if want > cur and cur < 3 and v < lim[cur] * 1.08:
		want = cur
	elif want < cur and cur > 0 and v > lim[cur - 1] * 0.92:
		want = cur
	return order[want]


func animate(delta: float) -> void:
	_t += delta
	var v := absf(speed)
	gait = _pick_gait(v)
	var gd: Dictionary = GAITS[gait]
	# plynulý přechod posunů fází mezi chody
	var k := 1.0 - exp(-delta * 6.0)
	for i in 4:
		var target: float = gd["off"][i]
		var d := wrapf(target - _off[i], -0.5, 0.5)
		_off[i] = fposmod(_off[i] + d * k, 1.0)
	_duty = lerpf(_duty, gd["duty"], k)
	var lims: Dictionary = spec["gaits"]
	var lo := 0.0
	var hi: float = lims["walk"]
	match gait:
		"trot":
			lo = lims["walk"]; hi = lims["trot"]
		"canter":
			lo = lims["trot"]; hi = lims["canter"]
		"gallop", "bound":
			lo = lims["canter"]; hi = lims["gallop"]
	# přešlapování: při otáčení na místě (bez jízdy vpřed) nohy kráčí mírným krokem
	var vv := v
	var turning_in_place := v < 0.08 and absf(turn_rate) > 0.3 and lie < 0.5 and dead < 0.5
	if turning_in_place:
		vv = clampf(absf(turn_rate) * 0.7, 0.2, 1.0)
	var frac := clampf((vv - lo) / maxf(hi - lo, 0.01), 0.0, 1.0)
	var freq: float = gd["k"] * sqrt(9.8 / maxf(shoulder_h, 0.1)) / PI * float(spec["step_k"]) * lerpf(0.85, 1.15, frac)
	var prev := phase
	if vv > 0.02:
		phase = fposmod(phase + freq * delta * (signf(speed) if v > 0.02 else signf(turn_rate)), 1.0)
	_move_w = move_toward(_move_w, 1.0 if vv > 0.05 else 0.0, delta * 4.0)
	var stride := vv / maxf(freq, 0.1)
	var amp := clampf(atan(stride * _duty * 0.5 / maxf(shoulder_h, 0.1)), 0.0, 0.8) * _move_w
	var lift := clampf(0.55 + vv * 0.06, 0.55, 1.0) * _move_w
	# prudké brzdění ze rychlého chodu: trup se vykloní, zadní nohy podstrčí pod tělo
	var decel := maxf(_prev_v - v, 0.0) / maxf(delta, 0.001)
	_brake = lerpf(_brake, clampf(decel / 9.0, 0.0, 1.0) * clampf(_prev_v / 5.0, 0.0, 1.0), minf(delta * 5.0, 1.0))
	_prev_v = v
	# lehání a vstávání po dvojicích nohou: lehá předními; vstává předními (kůň) nebo zadními
	var rising := lie < _lie_prev - 0.002
	_lie_prev = lie
	var fr := Vector2(0.0, 0.6)      # okno lehnutí předních (lehá předními jako první)
	var hr := Vector2(0.4, 1.0)
	if rising:
		if spec.get("rise_front_first", false):
			fr = Vector2(0.55, 1.0)
			hr = Vector2(0.0, 0.6)
		else:
			fr = Vector2(0.0, 0.6)
			hr = Vector2(0.55, 1.0)
	for i in 4:
		var r: Vector2 = fr if i < 2 else hr
		_leg_lie[i] = smoothstep(r.x, r.y, lie)

	# --- trup
	var bob: float = spec["bob"]
	var dy := 0.0
	var rock := 0.0
	if gait == "walk" or gait == "trot":
		dy = -bob * cos(phase * TAU * 2.0) * _move_w * (1.0 if gait == "walk" else 1.3)
	else:
		dy = bob * 1.6 * sin(phase * TAU) * _move_w
		rock = (0.13 if gait == "bound" else 0.06) * sin(phase * TAU + 1.2) * _move_w
	var roll := -atan(speed * turn_rate / 9.8) * 0.5
	var pitch := -slope + rock
	var lw := maxf(lie, dead)
	var sit_w := sit * (1.0 - lw)
	pitch -= _brake * 0.13                      # brzdění: předek nahoru
	pitch = lerpf(pitch, -0.82, sit_w * 0.85)   # sed na zadních: trup skoro svisle
	var y := body_y + dy
	y = lerpf(y, lie_y, lw)
	y = lerpf(y, lerpf(body_y, lie_y, 0.55), crouch * (1.0 - lw))
	y += sit_w * shoulder_h * 0.06
	body.position.y = y
	body.position.z = -sit_w * float(spec["length"]) * 0.12
	body.rotation = Vector3(lerpf(pitch, 0.0, lw), 0.0, lerpf(roll, 1.45, dead))

	# --- nohy
	for i in legs.size():
		var L: Dictionary = legs[i]
		var p := fposmod(phase + _off[i], 1.0)
		var s := 0.0
		var f := 0.0
		if p < _duty:
			s = amp * (1.0 - 2.0 * p / _duty)
		else:
			var t := (p - _duty) / (1.0 - _duty)
			s = amp * (-1.0 + 2.0 * smoothstep(0.0, 1.0, t))
			f = sin(PI * t) * lift
		# dopad (konec přenosu) → zvuk kopyta
		if _move_w > 0.5 and v > 0.3:
			var pp := fposmod(prev + _off[i], 1.0)
			if pp > p and speed > 0.0:
				footfall.emit(i)
		f = maxf(f, airborne * 0.85)
		f = lerpf(f, 0.6, crouch * (1.0 - lw))
		# brzdění: přední se postaví proti, zadní podstrčí dopředu pod tělo
		if L["front"]:
			s += _brake * 0.18
		else:
			s += _brake * 0.45
		# sed na zadních: přední zvednuté v nohavicích, zadní pod tělem
		if sit_w > 0.0:
			f = maxf(f, sit_w * 0.85)
		var rest: Array = L["rest"]
		var fold: Array = L["fold"]
		var lie_a: Array = L["lie"]
		var ll: float = _leg_lie[i]
		var aj := [rest[0] + fold[0] * f + s, rest[1] + fold[1] * f, rest[2] + fold[2] * f]
		for j in 3:
			aj[j] = lerpf(aj[j], lie_a[j], ll * (1.0 - dead))
		# IK chodidla: pod kopytem se změří terén a noha se prohne / natáhne, ať leží na zemi
		var ik_t := 0.0
		var ik_w := (1.0 - minf(f, 1.0)) * (1.0 - lw) * (1.0 - airborne) * (1.0 - dead)
		if foot_ik and ground_fn.is_valid() and is_inside_tree() and ik_w > 0.05:
			var lens: Array = L["lens"]
			var horiz: float = lens[0] * sin(aj[0]) + lens[1] * sin(aj[1]) + lens[2] * sin(aj[2])
			var vert: float = lens[0] * cos(aj[0]) + lens[1] * cos(aj[1]) + lens[2] * cos(aj[2])
			var jp: Vector3 = L["jpos"]
			var foot_w := to_global(Vector3(jp.x, body.position.y + jp.y - vert, jp.z + body.position.z + horiz))
			ik_t = clampf((float(ground_fn.call(foot_w.x, foot_w.z)) - foot_w.y) * ik_w, -ik_max, ik_max)
		_ik[i] = lerpf(_ik[i], ik_t, minf(delta * 9.0, 1.0))
		if absf(_ik[i]) > 0.002:
			var den := 0.0
			for j in 3:
				den += L["lens"][j] * maxf(sin(aj[j]), 0.12) * IK_W[j]
			if den > 0.02:
				for j in 3:
					aj[j] += _ik[i] * IK_W[j] / den
		var nodes: Array = L["nodes"]
		var acc := 0.0
		for j in 3:
			var rel: float = aj[j] - acc
			acc = aj[j]
			if j == 0:
				(nodes[0] as Node3D).rotation.x = -rel - body.rotation.x * (1.0 - lw)
			else:
				(nodes[j] as Node3D).rotation.x = -rel

	# --- krk a hlava
	var nod := 0.0
	if gait == "walk" or gait == "trot":
		nod = cos(phase * TAU * 2.0 + 0.6) * 0.05 * _move_w
	else:
		nod = -rock * 1.2
	if rooting and graze > 0.5:
		nod += sin(_t * 7.0) * 0.12
	var neck_pitch := -neck_angle + graze * float(spec["graze_angle"]) - alert * 0.22 + nod
	neck_pitch = lerpf(neck_pitch, -neck_angle * 0.35, lie * 0.5)
	neck_pitch = lerpf(neck_pitch, 0.35, dead)
	neck_pitch += crouch * 0.4
	neck_pitch += sit_w * 0.55                     # v sedu krk vyrovná vztyčený trup
	neck.rotation = Vector3(neck_pitch, clampf(look_yaw, -1.2, 1.2) * 0.55 * (1.0 - graze), 0.0)
	head.rotation = Vector3(head_tilt - graze * 0.25 - alert * 0.12 - nod * 0.5, clampf(look_yaw, -1.2, 1.2) * 0.4, 0.0)

	# --- uši (škubnutí, nastražení, přitisknutí)
	_ear_t -= delta
	if _ear_t <= 0.0:
		_ear_t = _rng.randf_range(1.5, 6.0)
		_ear_twitch = 0.35
	_ear_twitch = move_toward(_ear_twitch, 0.0, delta * 2.5)
	for e in ears:
		var sd: float = e.get_meta("side")
		var base: Vector3 = e.get_meta("rest")
		# +x = špička ucha dopředu (nastražené), −x = dozadu (přitisknuté)
		e.rotation = Vector3(base.x + alert * 0.35 - crouch * 1.1 - _ear_twitch * (1.0 if sd > 0 else 0.0),
			base.y, base.z * (1.0 - crouch * 0.6))

	# --- ocas (švihání, při útěku nahoru)
	if tail:
		_tail_t += delta * (2.0 + v * 0.3)
		var up := clampf((v - 3.0) / 5.0, 0.0, 1.0) * float(spec.get("tail_up", 0.9))
		var base_t: Vector3 = tail.get_meta("rest")
		tail.rotation = Vector3(base_t.x + up + sin(_tail_t * 0.7) * 0.05, sin(_tail_t) * 0.25 * (1.0 - up * 0.7), 0.0)
