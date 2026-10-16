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
## M8.10 Lokomoce 2 (přepínač realismu „animal_gait“ → `QuadrupedRig.v2`):
## - chod podle **Froudova čísla** Fr = v² / (g·L), L = výška ramenního kloubu (dynamická podobnost,
##   Alexander & Jayes 1983; Hildebrandovy fázové posuny v GAITS): prahy a hystereze per druh v AnimalSpecs
##   („froude“, „froude_hyst“); posuny fází, střída, kmitočet i styl pohupu se mezi chody plynule prolínají,
## - **páteř**: boční ohyb v zatáčce (krk a ocas do oblouku), flexe / extenze ve cvalu a skocích (přední a zadní
##   nohy se k sobě přitahují a rozevírají – „pružina“), předek nahoru při rozjezdu, trup podle dráhy skoku,
##   dech v klidu (boky; po běhu rychleji),
## - **sekundární pohyb** jako tlumené oscilátory θ'' = −ω²(θ − cíl) − 2ζωθ' − k·a_trupu (uši, ocas): uši se
##   natáčí ke zdroji zvuku (`listen_yaw`), při útěku ocas nahoru a zrcátko srnce se rozevře (`flee`),
##   hlava se stabilizuje, krk se při pastvě natáhne, divočák běží s nízkou hlavou.
## Detail (`detail`): páteř, dech a pružiny jen do SECONDARY_R od kamery (zjišťuje se 2× za s); dál starý pohyb.
## Výkon: animate() nealokuje (data nohou a uší v Packed polích), terén pro IK chodidel se nevzorkuje pod každým
## kopytem každý snímek, ale jako rovina ze 3 bodů jednou za IK_RESAMPLE_S.
##
## Vstupy nastavuje chování (Animal / Horse / FarmAnimal) každý snímek: speed, turn_rate, slope, graze, alert,
## lie, look_yaw, airborne, dead, crouch, sit (+ M8.10 nepovinně listen, listen_yaw, flee, vy); volá animate(delta).
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
const GAIT_ORDER := ["walk", "trot", "canter", "gallop"]   # index 3 = spec "gallop_kind" (gallop / bound)

## --- M8.10 laditelné konstanty (druhové hodnoty jsou v AnimalSpecs)
const G := 9.8
const SECONDARY_R := 60.0            # m od kamery – do té vzdálenosti páteř, dech a pružiny uší / ocasu
const LOD_CHECK_S := 0.5             # jak často se přepočítá `detail` podle kamery
const IK_RESAMPLE_S := 0.1           # jak často se znovu změří rovina terénu pod zvířetem (3 vzorky)
const GAIT_BLEND := 6.0              # 1/s – prolínání posunů fází, střídy a kmitočtu mezi chody
const STYLE_BLEND := 4.0             # 1/s – prolínání stylu pohupu (krok/klus ↔ cval)
const BEND_MAX := 0.35               # rad – největší boční ohyb páteře
const FLEX_PHASE := 0.8              # fáze cyklu s největší flexí (nohy pod tělem, před dopadem zadních)
const SURGE_MAX := 0.12              # rad – strop zvednutí předku při rozjezdu
const SPRING_DT := 0.02              # s – nejdelší krok integrace pružin (stabilita při delším snímku)
const PUFF_UP := 0.6                 # 1/s – jak rychle se zadýchá při běhu (rychlost > PUFF_SPEED)
const PUFF_DOWN := 0.04              # 1/s – jak rychle se vydýchá
const PUFF_SPEED := 3.0              # m/s

## Zapnutí M8.10 (přepínač realismu „animal_gait“; nastavuje Fauna z `World.realism_on`). Vypnuto = starý pohyb
## (výběr chodu podle rychlosti z `gaits`, bez pružin a páteře); výkonové úpravy platí vždy.
static var v2 := true

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
var listen := 0.0                    # M8.10: 0..1 poslouchá zdroj zvuku (uši se k němu natočí)
var listen_yaw := 0.0                # M8.10: směr ke zdroji zvuku vůči trupu (rad, + doleva)
var flee := 0.0                      # M8.10: 0..1 útěk (ocas nahoru, zrcátko se rozevře)
var vy := 0.0                        # M8.10: svislá rychlost (m/s) – sklon trupu podle dráhy skoku
var gait := "walk"

var foot_ik := true                  # IK chodidel podle terénu (vypíná se ve vzdáleném LOD)
var ground_fn := Callable()          # (x, z) → výška terénu; prázdné = rovná země bez IK
var ik_max := 0.18                   # max. náprsa nohy IK (m)
var detail := 2                      # M8.10: 2 = plný pohyb (blízko kamery), 1 = zjednodušený
var detail_auto := true              # false = `detail` nastavuje vlastník

var phase := 0.0
var _move_w := 0.0
var _off := PackedFloat32Array([0.25, 0.75, 0.0, 0.5])
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

# --- M8.10 předpočítaná data (bez alokací v animate)
var _prepped := false
var _gi := 0                         # index chodu v GAIT_ORDER
var _fast := "gallop"
var _goff := PackedFloat32Array([0.25, 0.75, 0.0, 0.5])
var _gduty := 0.64
var _gk := 0.85                      # cílový kmitočtový násobič chodu
var _k := 0.85                       # prolínaný kmitočtový násobič
var _v_up := PackedFloat32Array([1.0, 3.0, 6.0])     # rychlosti prahů nahoru (z Froudova čísla)
var _v_dn := PackedFloat32Array([0.9, 2.7, 5.5])     # … a dolů (hystereze)
var _s_lim := PackedFloat32Array([1.3, 3.0, 6.0, 12.0])   # horní hranice rychlosti chodů (spec "gaits")
var _trot_w := 0.0                   # prolínání: 1 = klus
var _style := 0.0                    # prolínání: 0 = krok/klus, 1 = cval/trysk
var _rock_a := 0.06
var _nlegs := 0
var _lnodes: Array[Node3D] = []      # 4 × 3 články nohou
var _lfront := PackedByteArray()
var _lrest := PackedFloat32Array()
var _lfold := PackedFloat32Array()
var _llie := PackedFloat32Array()
var _llen := PackedFloat32Array()
var _ljpos := PackedVector3Array()
var _ear_side := PackedFloat32Array()
var _ear_rest := PackedVector3Array()
var _tail_rest := Vector3.ZERO
var _neck_len := 0.3
var _torso: Node3D                   # síť trupu (dech) – jen ona, ne nohy
var _torso_scaled := false
var _lean_k := 0.5
var _spine_lat := 0.16
var _spine_flex := 0.05
var _surge := 0.02
var _head_stab := 0.5
var _neck_reach := 0.05
var _breath_hz := 0.35
var _breath_amp := 0.012
var _ear_w := 22.0                   # rad/s
var _ear_z := 0.35
var _ear_turn := 0.9
var _ear_flop := 0.012
var _tail_w := 13.8
var _tail_z := 0.3
var _tail_flop := 0.015
var _flare_s := 1.0
var _head_low := 0.0
var _L := 1.0                        # délka trupu
var _bob := 0.03
var _step_k := 1.0
var _graze_a := 1.25
var _tail_up := 0.9
var _rise_ff := false
# stav M8.10
var _bend := 0.0
var _flex := 0.0
var _acc_s := 0.0                    # vyhlazené podélné zrychlení (m/s²)
var _prev_y := 0.0
var _vel_y := 0.0
var _acc_y := 0.0                    # svislé zrychlení trupu (pohup) – budí pružiny
var _breath_p := 0.0
var _puff := 0.0
var _flare := 0.0
var _flee_w := 0.0
var _listen_w := 0.0
var _spr := PackedFloat32Array()     # pružiny: [ucho0 x, v, y, v, ucho1 x, v, y, v, ocas x, v, y, v]
var _spr_live := false
var _lod_t := 0.0
var _ik_t := 0.0
var _ik_ok := false                  # rovina terénu změřená
var _gp := Vector3.ZERO              # kde se rovina měřila
var _gh := 0.0
var _ggx := 0.0
var _ggz := 0.0


func _ready() -> void:
	_rng.randomize()
	_t = _rng.randf() * 10.0
	_lod_t = _rng.randf() * LOD_CHECK_S
	_ik_t = _rng.randf() * IK_RESAMPLE_S


## Jednou při první animaci: data nohou, uší a druhové konstanty do Packed polí / proměnných.
func _prep() -> void:
	_prepped = true
	_fast = String(spec.get("gallop_kind", "gallop"))
	var g: Dictionary = spec["gaits"]
	_s_lim[0] = float(g["walk"])
	_s_lim[1] = float(g["trot"])
	_s_lim[2] = float(g["canter"])
	_s_lim[3] = float(g["gallop"])
	var fr: Array = spec.get("froude", [0.5, 2.5, 6.0])
	var hy: float = spec.get("froude_hyst", 0.2)
	var L := maxf(shoulder_h, 0.1)
	for i in 3:
		_v_up[i] = sqrt(float(fr[i]) * G * L)
		_v_dn[i] = sqrt(float(fr[i]) * (1.0 - hy) * G * L)
	_nlegs = legs.size()
	_lfront.resize(_nlegs)
	_lrest.resize(_nlegs * 3)
	_lfold.resize(_nlegs * 3)
	_llie.resize(_nlegs * 3)
	_llen.resize(_nlegs * 3)
	_ljpos.resize(_nlegs)
	_lnodes.clear()
	for i in _nlegs:
		var Ld: Dictionary = legs[i]
		_lfront[i] = 1 if Ld["front"] else 0
		_ljpos[i] = Ld["jpos"]
		var rest: Array = Ld["rest"]
		var fold: Array = Ld["fold"]
		var lie_a: Array = Ld["lie"]
		var lens: Array = Ld["lens"]
		var nodes: Array = Ld["nodes"]
		for j in 3:
			_lrest[i * 3 + j] = float(rest[j])
			_lfold[i * 3 + j] = float(fold[j])
			_llie[i * 3 + j] = float(lie_a[j])
			_llen[i * 3 + j] = float(lens[j])
			_lnodes.append(nodes[j] as Node3D)
	_ear_side.resize(ears.size())
	_ear_rest.resize(ears.size())
	for e in ears.size():
		_ear_side[e] = float(ears[e].get_meta("side", 1.0))
		_ear_rest[e] = ears[e].get_meta("rest", ears[e].rotation)
	if tail:
		_tail_rest = tail.get_meta("rest", tail.rotation)
	if head:
		_neck_len = head.position.z
	if body:
		for c in body.get_children():
			if c is MeshInstance3D:
				_torso = c
				break
	_L = float(spec.get("length", 1.0))
	_bob = float(spec.get("bob", 0.03))
	_step_k = float(spec.get("step_k", 1.0))
	_graze_a = float(spec.get("graze_angle", 1.25))
	_tail_up = float(spec.get("tail_up", 0.9))
	_rise_ff = bool(spec.get("rise_front_first", false))
	_lean_k = float(spec.get("lean_k", 0.5))
	var sp: Array = spec.get("spine", [0.16, 0.05])
	_spine_lat = float(sp[0])
	_spine_flex = float(sp[1])
	_surge = float(spec.get("surge_pitch", 0.02))
	_head_stab = float(spec.get("head_stab", 0.5))
	_neck_reach = float(spec.get("neck_reach", 0.05))
	var br: Array = spec.get("breath", [0.35, 0.012])
	_breath_hz = float(br[0])
	_breath_amp = float(br[1])
	var es: Array = spec.get("ear_spring", [3.5, 0.35])
	_ear_w = TAU * float(es[0])
	_ear_z = float(es[1])
	_ear_turn = float(spec.get("ear_turn", 0.9))
	_ear_flop = float(spec.get("ear_flop", 0.012))
	var ts: Array = spec.get("tail_spring", [2.2, 0.3])
	_tail_w = TAU * float(ts[0])
	_tail_z = float(ts[1])
	_tail_flop = float(spec.get("tail_flop", 0.015))
	var rf: Array = spec.get("rump_flare", [])
	_flare_s = float(rf[2]) if rf.size() >= 3 else 1.0
	_head_low = float(spec.get("run_head_low", 0.0))
	_spr.resize(12)
	_spr.fill(0.0)
	_set_gait(0)


func _set_gait(gi: int) -> void:
	_gi = gi
	gait = _fast if gi == 3 else String(GAIT_ORDER[gi])
	var gd: Dictionary = GAITS[gait]
	var off: Array = gd["off"]
	for i in 4:
		_goff[i] = float(off[i])
	_gduty = float(gd["duty"])
	_gk = float(gd["k"])


## Výběr chodu podle rychlosti (s hysterezí, aby chod na hranici nepřeskakoval) – původní pravidlo (v2 vypnuto).
func _pick_gait_speed(v: float) -> int:
	var want := 3
	for i in 3:
		if v <= _s_lim[i]:
			want = i
			break
	# hystereze ±8 %
	if want > _gi and _gi < 3 and v < _s_lim[_gi] * 1.08:
		want = _gi
	elif want < _gi and _gi > 0 and v > _s_lim[_gi - 1] * 0.92:
		want = _gi
	return want


## M8.10: výběr chodu podle Froudova čísla – nahoru při překročení prahu, dolů až pod nižší práh (hystereze).
func _pick_gait_froude(v: float) -> int:
	var want := 0
	for i in 3:
		if v > _v_up[i]:
			want = i + 1
	if want > _gi:
		return want
	var w := _gi
	while w > 0 and v < _v_dn[w - 1]:
		w -= 1
	return w


## Detail podle vzdálenosti kamery (2× za sekundu, bez alokací).
func _check_detail(delta: float) -> void:
	_lod_t -= delta
	if _lod_t > 0.0:
		return
	_lod_t = LOD_CHECK_S
	if not detail_auto:
		return
	if not is_inside_tree():
		detail = 1
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		detail = 1
		return
	detail = 2 if cam.global_position.distance_squared_to(global_position) < SECONDARY_R * SECONDARY_R else 1


## Rovina terénu pod zvířetem ze 3 vzorků (střed, +x, +z) – IK chodidel z ní čte výšku pod každým kopytem.
func _sample_ground() -> void:
	var gp := global_position
	var d := maxf(_L * 0.5, 0.3)
	var h0: float = ground_fn.call(gp.x, gp.z)
	var hx: float = ground_fn.call(gp.x + d, gp.z)
	var hz: float = ground_fn.call(gp.x, gp.z + d)
	_gp = gp
	_gh = h0
	_ggx = (hx - h0) / d
	_ggz = (hz - h0) / d
	_ik_ok = true


## Tlumený oscilátor (pružina) na indexu `i` v `_spr`: θ'' = −ω²(θ − cíl) − 2ζωθ' + síla. Vrací novou polohu.
func _spring(i: int, target: float, force: float, w: float, z: float, dt: float) -> float:
	var x := _spr[i]
	var v := _spr[i + 1]
	var n := maxi(ceili(dt / SPRING_DT), 1)
	var h := dt / float(n)
	for _s in n:
		v += (-w * w * (x - target) - 2.0 * z * w * v + force) * h
		x += v * h
	x = clampf(x, target - 1.2, target + 1.2)
	_spr[i] = x
	_spr[i + 1] = v
	return x


func animate(delta: float) -> void:
	if not _prepped:
		_prep()
	_t += delta
	_check_detail(delta)
	var full := v2 and detail >= 2
	var v := absf(speed)
	var gi := _pick_gait_froude(v) if v2 else _pick_gait_speed(v)
	if gi != _gi:
		_set_gait(gi)
	# plynulý přechod posunů fází, střídy a kmitočtu mezi chody
	var k := 1.0 - exp(-delta * GAIT_BLEND)
	for i in 4:
		var d := wrapf(_goff[i] - _off[i], -0.5, 0.5)
		_off[i] = fposmod(_off[i] + d * k, 1.0)
	_duty = lerpf(_duty, _gduty, k)
	var ks := 1.0 - exp(-delta * STYLE_BLEND)
	if v2:
		_k = lerpf(_k, _gk, k)
		_trot_w = lerpf(_trot_w, 1.0 if _gi == 1 else 0.0, ks)
		_style = lerpf(_style, 1.0 if _gi >= 2 else 0.0, ks)
		_rock_a = lerpf(_rock_a, 0.13 if gait == "bound" else 0.06, ks)
	else:
		_k = _gk
		_trot_w = 1.0 if _gi == 1 else 0.0
		_style = 1.0 if _gi >= 2 else 0.0
		_rock_a = 0.13 if gait == "bound" else 0.06
	# rychlostní rozsah současného chodu (pro kmitočet uvnitř chodu)
	var lo := 0.0
	var hi := 0.0
	if v2:
		lo = 0.0 if _gi == 0 else _v_up[_gi - 1]
		hi = _s_lim[3] if _gi == 3 else _v_up[_gi]
	else:
		lo = 0.0 if _gi == 0 else _s_lim[_gi - 1]
		hi = _s_lim[_gi]
	# přešlapování: při otáčení na místě (bez jízdy vpřed) nohy kráčí mírným krokem
	var vv := v
	var turning_in_place := v < 0.08 and absf(turn_rate) > 0.3 and lie < 0.5 and dead < 0.5
	if turning_in_place:
		vv = clampf(absf(turn_rate) * 0.7, 0.2, 1.0)
	var frac := clampf((vv - lo) / maxf(hi - lo, 0.01), 0.0, 1.0)
	var freq: float = _k * sqrt(9.8 / maxf(shoulder_h, 0.1)) / PI * _step_k * lerpf(0.85, 1.15, frac)
	var prev := phase
	if vv > 0.02:
		phase = fposmod(phase + freq * delta * (signf(speed) if v > 0.02 else signf(turn_rate)), 1.0)
	_move_w = move_toward(_move_w, 1.0 if vv > 0.05 else 0.0, delta * 4.0)
	var stride := vv / maxf(freq, 0.1)
	var amp := clampf(atan(stride * _duty * 0.5 / maxf(shoulder_h, 0.1)), 0.0, 0.8) * _move_w
	var lift := clampf(0.55 + vv * 0.06, 0.55, 1.0) * _move_w
	# prudké brzdění ze rychlého chodu: trup se vykloní, zadní nohy podstrčí pod tělo
	var acc := (v - _prev_v) / maxf(delta, 0.001)
	var decel := maxf(-acc, 0.0)
	_brake = lerpf(_brake, clampf(decel / 9.0, 0.0, 1.0) * clampf(_prev_v / 5.0, 0.0, 1.0), minf(delta * 5.0, 1.0))
	_prev_v = v
	_acc_s = lerpf(_acc_s, acc, minf(delta * 4.0, 1.0))
	# lehání a vstávání po dvojicích nohou: lehá předními; vstává předními (kůň) nebo zadními
	var rising := lie < _lie_prev - 0.002
	_lie_prev = lie
	var fr0 := 0.0                  # okno lehnutí předních (lehá předními jako první)
	var fr1 := 0.6
	var hr0 := 0.4
	var hr1 := 1.0
	if rising:
		if _rise_ff:
			fr0 = 0.55
			fr1 = 1.0
			hr0 = 0.0
			hr1 = 0.6
		else:
			hr0 = 0.55
			hr1 = 1.0
	for i in 4:
		_leg_lie[i] = smoothstep(fr0, fr1, lie) if i < 2 else smoothstep(hr0, hr1, lie)

	# --- trup (pohup krok/klus ↔ houpání cvalu se prolíná)
	var bob := _bob
	var dy_wt := -bob * cos(phase * TAU * 2.0) * _move_w * (1.0 + 0.3 * _trot_w)
	var dy_c := bob * 1.6 * sin(phase * TAU) * _move_w
	var rock := _rock_a * sin(phase * TAU + 1.2) * _move_w * _style
	var dy := lerpf(dy_wt, dy_c, _style)
	var roll := -atan(speed * turn_rate / 9.8) * (_lean_k if v2 else 0.5)
	var pitch := -slope + rock
	var lw := maxf(lie, dead)
	var sit_w := sit * (1.0 - lw)
	pitch -= _brake * 0.13                      # brzdění: předek nahoru
	if full:
		pitch -= clampf(_acc_s * _surge, 0.0, SURGE_MAX) * (1.0 - lw)   # rozjezd: předek nahoru
		if airborne > 0.05:
			# ve skoku trup sleduje dráhu: nahoru čenichem vzhůru, dolů předkem dolů
			pitch = lerpf(pitch, -atan2(vy, maxf(v, 1.0)) * 0.8, airborne)
	pitch = lerpf(pitch, -0.82, sit_w * 0.85)   # sed na zadních: trup skoro svisle
	var y := body_y + dy
	y = lerpf(y, lie_y, lw)
	y = lerpf(y, lerpf(body_y, lie_y, 0.55), crouch * (1.0 - lw))
	y += sit_w * shoulder_h * 0.06
	# páteř: boční ohyb do zatáčky a flexe/extenze ve cvalu
	var kb := 1.0 - exp(-delta * 5.0)
	if full:
		var want_b := clampf(turn_rate * _spine_lat * clampf(0.3 + v * 0.25, 0.3, 1.5), -BEND_MAX, BEND_MAX)
		_bend = lerpf(_bend, want_b * (1.0 - lw), kb)
		_flex = _spine_flex * _style * _move_w * cos(TAU * (phase - FLEX_PHASE)) * (1.0 - lw)
	else:
		_bend = lerpf(_bend, 0.0, kb)
		_flex = 0.0
	body.position.y = y
	body.position.z = -sit_w * _L * 0.12
	body.rotation = Vector3(lerpf(pitch, 0.0, lw), _bend * 0.3, lerpf(roll, 1.45, dead))
	# svislé zrychlení trupu (budí pružiny uší a ocasu)
	if full:
		var dt := maxf(delta, 0.001)
		var vy_b := (y - _prev_y) / dt
		_acc_y = lerpf(_acc_y, (vy_b - _vel_y) / dt, minf(delta * 10.0, 1.0))
		_vel_y = vy_b
	_prev_y = y
	# dech: boky se rozšiřují (jen síť trupu, ne nohy); po běhu rychleji
	_puff = move_toward(_puff, 1.0 if v > PUFF_SPEED else 0.0, delta * (PUFF_UP if v > PUFF_SPEED else PUFF_DOWN))
	if _torso:
		if full and v < 0.6 and dead < 0.5:
			_breath_p = fmod(_breath_p + delta * _breath_hz * (1.0 + _puff * 1.8) * TAU, TAU)
			var br := sin(_breath_p) * _breath_amp * (1.0 + _puff)
			_torso.scale = Vector3(1.0 + br, 1.0 + br * 0.5, 1.0)
			_torso_scaled = true
		elif _torso_scaled:
			_torso.scale = Vector3.ONE
			_torso_scaled = false

	# --- terén pro IK (rovina, throttlovaně)
	var ik_on := foot_ik and ground_fn.is_valid() and is_inside_tree()
	if ik_on:
		_ik_t -= delta
		if _ik_t <= 0.0 or not _ik_ok:
			_ik_t = IK_RESAMPLE_S
			_sample_ground()
	else:
		_ik_ok = false
	var flex_dz := _flex * _L

	# --- nohy
	var bpy := body.position.y
	var bpz := body.position.z
	var brx := body.rotation.x
	for i in _nlegs:
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
		var front := _lfront[i] == 1
		# brzdění: přední se postaví proti, zadní podstrčí dopředu pod tělo
		s += _brake * (0.18 if front else 0.45)
		# sed na zadních: přední zvednuté v nohavicích, zadní pod tělem
		if sit_w > 0.0:
			f = maxf(f, sit_w * 0.85)
		var b3 := i * 3
		var a0 := _lrest[b3] + _lfold[b3] * f + s
		var a1 := _lrest[b3 + 1] + _lfold[b3 + 1] * f
		var a2 := _lrest[b3 + 2] + _lfold[b3 + 2] * f
		var ll := _leg_lie[i] * (1.0 - dead)
		a0 = lerpf(a0, _llie[b3], ll)
		a1 = lerpf(a1, _llie[b3 + 1], ll)
		a2 = lerpf(a2, _llie[b3 + 2], ll)
		var l0 := _llen[b3]
		var l1 := _llen[b3 + 1]
		var l2 := _llen[b3 + 2]
		# flexe páteře: přední a zadní kloub se k sobě přiblíží / vzdálí
		var jp := _ljpos[i]
		var jz := jp.z + (-flex_dz if front else flex_dz)
		var n0 := _lnodes[b3]
		if full or n0.position.z != jp.z:
			n0.position.z = jz
		# IK chodidla: výška terénu pod kopytem z roviny a noha se prohne / natáhne, ať leží na zemi
		var ik_t := 0.0
		var ik_w := (1.0 - minf(f, 1.0)) * (1.0 - lw) * (1.0 - airborne) * (1.0 - dead)
		if ik_on and _ik_ok and ik_w > 0.05:
			var horiz := l0 * sin(a0) + l1 * sin(a1) + l2 * sin(a2)
			var vert := l0 * cos(a0) + l1 * cos(a1) + l2 * cos(a2)
			var foot_w := to_global(Vector3(jp.x, bpy + jp.y - vert, jz + bpz + horiz))
			var gy := _gh + _ggx * (foot_w.x - _gp.x) + _ggz * (foot_w.z - _gp.z)
			ik_t = clampf((gy - foot_w.y) * ik_w, -ik_max, ik_max)
		_ik[i] = lerpf(_ik[i], ik_t, minf(delta * 9.0, 1.0))
		var ikv := _ik[i]
		if absf(ikv) > 0.002:
			var w0: float = IK_W[0]
			var w1: float = IK_W[1]
			var w2: float = IK_W[2]
			var den := l0 * maxf(sin(a0), 0.12) * w0 + l1 * maxf(sin(a1), 0.12) * w1 + l2 * maxf(sin(a2), 0.12) * w2
			if den > 0.02:
				a0 += ikv * w0 / den
				a1 += ikv * w1 / den
				a2 += ikv * w2 / den
		n0.rotation.x = -a0 - brx * (1.0 - lw)
		_lnodes[b3 + 1].rotation.x = -(a1 - a0)
		_lnodes[b3 + 2].rotation.x = -(a2 - a1)

	# --- krk a hlava
	var nod_wt := cos(phase * TAU * 2.0 + 0.6) * 0.05 * _move_w
	var nod := lerpf(nod_wt, -rock * 1.2, _style)
	if rooting and graze > 0.5:
		nod += sin(_t * 7.0) * 0.12
	var neck_pitch := -neck_angle + graze * _graze_a - alert * 0.22 + nod
	neck_pitch = lerpf(neck_pitch, -neck_angle * 0.35, lie * 0.5)
	neck_pitch = lerpf(neck_pitch, 0.35, dead)
	neck_pitch += crouch * 0.4
	neck_pitch += sit_w * 0.55                     # v sedu krk vyrovná vztyčený trup
	var look := clampf(look_yaw, -1.2, 1.2)
	if full:
		# divočák běží s nízkou hlavou; hlava drží sklon, i když se trup houpe; krk se při pastvě natáhne
		var run := clampf((v - _v_up[0]) / maxf(_v_up[1] - _v_up[0], 0.1), 0.0, 1.0)
		neck_pitch += _head_low * run * (1.0 - graze) * (1.0 - lw)
		neck_pitch -= brx * _head_stab * (1.0 - lw) * (1.0 - sit_w)
		head.position.z = _neck_len * (1.0 + _neck_reach * graze)
	elif head.position.z != _neck_len:
		head.position.z = _neck_len
	neck.rotation = Vector3(neck_pitch, look * 0.55 * (1.0 - graze) + _bend * 0.9, 0.0)
	head.rotation = Vector3(head_tilt - graze * 0.25 - alert * 0.12 - nod * 0.5, look * 0.4, 0.0)

	# --- uši (škubnutí, nastražení, přitisknutí; M8.10 pružiny a natočení ke zvuku)
	_ear_t -= delta
	if _ear_t <= 0.0:
		_ear_t = _rng.randf_range(1.5, 6.0)
		_ear_twitch = 0.35
	_ear_twitch = move_toward(_ear_twitch, 0.0, delta * 2.5)
	_listen_w = lerpf(_listen_w, clampf(listen, 0.0, 1.0), minf(delta * 4.0, 1.0))
	var head_yaw := look * 0.95 + _bend * 0.9
	var ear_dir := clampf(wrapf(listen_yaw - head_yaw, -PI, PI), -_ear_turn, _ear_turn) * _listen_w
	if full and not _spr_live:
		_spr.fill(0.0)
		for e in ears.size():
			_spr[e * 4] = ears[e].rotation.x
			_spr[e * 4 + 2] = ears[e].rotation.y
		if tail:
			_spr[8] = tail.rotation.x
			_spr[10] = tail.rotation.y
	_spr_live = full
	for e in ears.size():
		var sd := _ear_side[e]
		var base := _ear_rest[e]
		# +x = špička ucha dopředu (nastražené), −x = dozadu (přitisknuté)
		var tx := base.x + alert * 0.35 - crouch * 1.1 - _ear_twitch * (1.0 if sd > 0 else 0.0)
		var ez := base.z * (1.0 - crouch * 0.6)
		if full:
			# ucho na straně zdroje se natočí víc, druhé méně (každé má vlastní pružinu)
			var side_k := 1.0 + 0.25 * signf(ear_dir) * sd
			var ty := base.y + ear_dir * side_k * (1.0 - crouch)
			tx += _listen_w * 0.2 * (1.0 - crouch)
			var ex := _spring(e * 4, tx, -_acc_y * _ear_flop * _ear_w * _ear_w, _ear_w, _ear_z, delta)
			var ey := _spring(e * 4 + 2, ty, 0.0, _ear_w, _ear_z, delta)
			ears[e].rotation = Vector3(ex, ey, ez)
		else:
			ears[e].rotation = Vector3(tx, base.y, ez)

	# --- ocas (švihání, při útěku nahoru; M8.10 pružina, zrcátko)
	if tail:
		_tail_t += delta * (2.0 + v * 0.3)
		_flee_w = lerpf(_flee_w, clampf(flee, 0.0, 1.0), minf(delta * 4.0, 1.0))
		var up := clampf((v - 3.0) / 5.0, 0.0, 1.0) * _tail_up
		if v2:
			up = maxf(up, _flee_w * _tail_up)
		var tx := _tail_rest.x + up + sin(_tail_t * 0.7) * 0.05
		var ty := sin(_tail_t) * 0.25 * (1.0 - minf(up, 1.0) * 0.7)
		if full:
			ty -= _bend * 1.0
			tail.rotation = Vector3(_spring(8, tx, _acc_y * _tail_flop * _tail_w * _tail_w, _tail_w, _tail_z, delta),
				_spring(10, ty, 0.0, _tail_w, _tail_z, delta), 0.0)
		else:
			tail.rotation = Vector3(tx, ty, 0.0)
		if _flare_s > 1.0:
			_flare = lerpf(_flare, _flee_w if v2 else 0.0, minf(delta * 5.0, 1.0))
			var fs := lerpf(1.0, _flare_s, _flare)
			tail.scale = Vector3(fs, fs, 1.0)
