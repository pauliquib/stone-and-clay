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

## M8.D2d: všechny konstanty pohybu jsou `static var` – ladí je menu pro vývojáře (F3 → Zvěř/Pohyb a rig,
## `scripts/dev/tune_zver.gd`); výchozí hodnoty zůstávají tady. Změna druhových hodnot (`AnimalSpecs.live_spec`)
## zvedne `AnimalSpecs.tune_gen` → rig si data druhu znovu připraví (`_prep`).

## váhy IK nápravy na články nohy (stehno / holeň / spěnka)
static var IK_W := [0.45, 0.9, 0.7]

## posuny fází nohou [LP, PP, LZ, PZ] a podíl stojné fáze
static var GAITS := {
	"walk": {"off": [0.25, 0.75, 0.0, 0.5], "duty": 0.64, "k": 0.85},
	"trot": {"off": [0.0, 0.5, 0.5, 0.0], "duty": 0.46, "k": 1.2},
	"canter": {"off": [0.3, 0.55, 0.0, 0.3], "duty": 0.38, "k": 1.3},
	"gallop": {"off": [0.45, 0.55, 0.0, 0.1], "duty": 0.3, "k": 1.5},
	"bound": {"off": [0.42, 0.5, 0.0, 0.04], "duty": 0.26, "k": 1.45},
}
const GAIT_ORDER := ["walk", "trot", "canter", "gallop"]   # index 3 = spec "gallop_kind" (gallop / bound)

## --- M8.10 laditelné konstanty (druhové hodnoty jsou v AnimalSpecs)
static var G := 9.8
static var SECONDARY_R := 60.0       # m od kamery – do té vzdálenosti páteř, dech a pružiny uší / ocasu
static var LOD_CHECK_S := 0.5        # jak často se přepočítá `detail` podle kamery
static var IK_RESAMPLE_S := 0.1      # jak často se znovu změří rovina terénu pod zvířetem (3 vzorky)
static var GAIT_BLEND := 6.0         # 1/s – prolínání posunů fází, střídy a kmitočtu mezi chody
static var STYLE_BLEND := 4.0        # 1/s – prolínání stylu pohupu (krok/klus ↔ cval)
static var BEND_MAX := 0.35          # rad – největší boční ohyb páteře
static var FLEX_PHASE := 0.8         # fáze cyklu s největší flexí (nohy pod tělem, před dopadem zadních)
static var SURGE_MAX := 0.12         # rad – strop zvednutí předku při rozjezdu
static var SPRING_DT := 0.02         # s – nejdelší krok integrace pružin (stabilita při delším snímku)
static var PUFF_UP := 0.6            # 1/s – jak rychle se zadýchá při běhu (rychlost > PUFF_SPEED)
static var PUFF_DOWN := 0.04         # 1/s – jak rychle se vydýchá
static var PUFF_SPEED := 3.0         # m/s

## --- M8.D2d: čísla dřív zapsaná přímo ve vzorcích (stejné hodnoty)
# chody a kmitočet
static var OLD_HYST_UP := 1.08       # starý výběr chodu (v2 vypnuto): nahoru až nad hranici × tohle
static var OLD_HYST_DN := 0.92       # … dolů až pod předchozí hranici × tohle
static var OLD_LEAN_K := 0.5         # starý pohyb: náklon do zatáčky
static var FREQ_LO := 0.85           # kmitočet kroků na dolní hranici rychlosti chodu (násobek)
static var FREQ_HI := 1.15           # … na horní hranici
static var MOVE_BLEND := 4.0         # 1/s – náběh / doběh pohybu nohou
static var AMP_MAX := 0.8            # rad – největší rozkmit nohy
static var LIFT_BASE := 0.55         # zvednutí nohy při přenosu (podíl ohnutí) ve stání
static var LIFT_PER_V := 0.06        # … + tolik na m/s
static var LIFT_MAX := 1.0           # … nejvýš
static var ROCK_BASE := 0.06         # rad – houpání trupu ve cvalu
static var ROCK_BOUND := 0.13        # rad – houpání trupu ve skocích (zajíc)
static var ROCK_PHASE := 1.2         # rad – fázový posun houpání vůči kroku
static var TROT_BOB_K := 0.3         # pohup v klusu × (1 + tohle)
static var CANTER_BOB_K := 1.6       # pohup ve cvalu (násobek „bob“)
# přešlapování na místě
static var TURN_STEP_V := 0.08       # m/s – pod touto rychlostí se při otáčení přešlapuje
static var TURN_STEP_RATE := 0.3     # rad/s – od takového otáčení
static var TURN_STEP_K := 0.7        # rychlost přešlapování = otáčení × tohle (m/s na rad/s)
static var TURN_STEP_MIN := 0.2      # m/s
static var TURN_STEP_MAX := 1.0      # m/s
# brzdění, rozjezd, skok
static var BRAKE_DECEL := 9.0        # m/s² – zpomalení, při kterém se trup naplno vykloní
static var BRAKE_FROM_V := 5.0       # m/s – plné vyklonění až z této rychlosti
static var BRAKE_BLEND := 5.0        # 1/s
static var BRAKE_PITCH := 0.13       # rad – předek nahoru při plném brzdění
static var BRAKE_FRONT_S := 0.18     # rad – přední nohy se postaví proti
static var BRAKE_HIND_S := 0.45      # rad – zadní se podstrčí pod tělo
static var ACC_BLEND := 4.0          # 1/s – vyhlazení podélného zrychlení (rozjezd)
static var AIR_PITCH_K := 0.8        # ve skoku trup sleduje dráhu (podíl úhlu dráhy)
static var AIR_FOLD := 0.85          # ohnutí nohou ve vzduchu
# lehání, sed, přikrčení
static var LIE_FRONT_END := 0.6      # lehá předními v okně 0 … tohle
static var LIE_HIND_START := 0.4     # zadními v okně tohle … 1
static var RISE_LATE_START := 0.55   # vstávání: druhá dvojice nohou od tohoto podílu
static var RISE_EARLY_END := 0.6     # vstávání předními (kůň): zadní do tohoto podílu
static var SIT_PITCH := -0.82        # rad – sed na zadních: trup skoro svisle
static var SIT_PITCH_W := 0.85       # váha sklonu v sedu
static var SIT_LIFT := 0.06          # zvednutí trupu v sedu (podíl výšky ramene)
static var SIT_BACK := 0.12          # posun trupu dozadu v sedu (podíl délky)
static var SIT_FOLD := 0.85          # přední nohy v sedu (ohnutí)
static var SIT_NECK := 0.55          # rad – krk v sedu vyrovná vztyčený trup
static var CROUCH_H := 0.55          # přikrčení: výška trupu mezi stojem a lehem (podíl)
static var CROUCH_FOLD := 0.6        # přikrčení: ohnutí nohou
static var CROUCH_NECK := 0.4        # rad
static var DEAD_ROLL := 1.45         # rad – uhynulé leží na boku
static var DEAD_NECK := 0.35         # rad
# páteř a dech
static var BEND_BLEND := 5.0         # 1/s
static var BEND_V_MIN := 0.3         # ohyb páteře × clamp(tohle + v × BEND_V_K, tohle, BEND_V_MAX)
static var BEND_V_K := 0.25
static var BEND_V_MAX := 1.5
static var BEND_BODY := 0.3          # podíl ohybu, o který se natočí trup
static var BEND_NECK := 0.9          # podíl ohybu do krku
static var BEND_TAIL := 1.0          # podíl ohybu do ocasu
static var ACC_Y_BLEND := 10.0       # 1/s – vyhlazení svislého zrychlení trupu (budí pružiny)
static var BREATH_MAX_V := 0.6       # m/s – dýchá viditelně jen pomaleji
static var PUFF_RATE_K := 1.8        # zadýchaný: kmitočet dechu × (1 + puff × tohle)
static var PUFF_AMP_K := 1.0         # zadýchaný: rozšíření boků × (1 + puff × tohle)
static var BREATH_Y := 0.5           # dech: podíl rozšíření do výšky
# IK chodidel a dopady
static var IK_BLEND := 9.0           # 1/s – vyhlazení nápravy IK
static var FOOTFALL_MIN_V := 0.3     # m/s – zvuk / stopa dopadu až od této rychlosti
# krk a hlava
static var NOD_AMP := 0.05           # rad – kývání hlavou v kroku
static var NOD_ROCK := 1.2           # kývání ve cvalu (podíl houpání)
static var NOD_HEAD := 0.5           # podíl kývání do hlavy
static var ROOT_HZ := 7.0            # rad/s – rytí: kývání rypákem
static var ROOT_AMP := 0.12          # rad
static var ALERT_NECK := 0.22        # rad – pozornost: krk nahoru
static var ALERT_HEAD := 0.12        # rad
static var GRAZE_HEAD := 0.25        # rad – pastva: hlava dolů
static var LIE_NECK := 0.35          # vleže krk × tohle
static var LIE_NECK_W := 0.5
static var LOOK_MAX := 1.2           # rad – nejvíc otočená hlava
static var LOOK_NECK := 0.55         # podíl otočení do krku
static var LOOK_HEAD := 0.4          # podíl otočení do hlavy
# uši
static var EAR_TWITCH_EVERY := [1.5, 6.0]   # s – škubnutí uchem jednou za (od–do)
static var EAR_TWITCH := 0.35        # rad
static var EAR_TWITCH_DECAY := 2.5   # rad/s
static var LISTEN_BLEND := 4.0       # 1/s
static var LISTEN_EAR := 0.2         # rad – poslouchá: uši dopředu
static var EAR_SIDE_K := 0.25        # ucho na straně zvuku se natočí víc o tento podíl
static var ALERT_EAR := 0.35         # rad – pozornost: uši nastražené
static var CROUCH_EAR := 1.1         # rad – přikrčený: uši přitisknuté
static var CROUCH_EAR_Z := 0.6       # přikrčený: uši k hlavě (podíl)
static var SPRING_CLAMP := 1.2       # rad – pružina uší / ocasu nejvýš tak daleko od cíle
# ocas
static var TAIL_HZ := 2.0            # rad/s švihání ocasem
static var TAIL_HZ_V := 0.3          # … + tolik na m/s
static var TAIL_UP_FROM := 3.0       # m/s – ocas nahoru od této rychlosti
static var TAIL_UP_RANGE := 5.0      # m/s – naplno o tolik rychleji
static var TAIL_BOB := 0.05          # rad – pomalé pohupování ocasu
static var TAIL_SWISH := 0.25        # rad – švihání do stran
static var TAIL_SWISH_UP := 0.7      # vztyčený ocas švihá o tento podíl méně
static var FLEE_BLEND := 4.0         # 1/s – náběh útěku (ocas, zrcátko)
static var FLARE_BLEND := 5.0        # 1/s – rozevření zrcátka

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
var _prep_gen := -1                  # M8.D2d: `AnimalSpecs.tune_gen` při posledním `_prep` (změna v menu F3 → znovu)
var _gi := 0                        # index chodu v GAIT_ORDER
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
	_prep_gen = AnimalSpecs.tune_gen
	_spr_live = false
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
	if want > _gi and _gi < 3 and v < _s_lim[_gi] * OLD_HYST_UP:
		want = _gi
	elif want < _gi and _gi > 0 and v > _s_lim[_gi - 1] * OLD_HYST_DN:
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
	x = clampf(x, target - SPRING_CLAMP, target + SPRING_CLAMP)
	_spr[i] = x
	_spr[i + 1] = v
	return x


func animate(delta: float) -> void:
	if not _prepped or _prep_gen != AnimalSpecs.tune_gen:
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
		_rock_a = lerpf(_rock_a, ROCK_BOUND if gait == "bound" else ROCK_BASE, ks)
	else:
		_k = _gk
		_trot_w = 1.0 if _gi == 1 else 0.0
		_style = 1.0 if _gi >= 2 else 0.0
		_rock_a = ROCK_BOUND if gait == "bound" else ROCK_BASE
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
	var turning_in_place := v < TURN_STEP_V and absf(turn_rate) > TURN_STEP_RATE and lie < 0.5 and dead < 0.5
	if turning_in_place:
		vv = clampf(absf(turn_rate) * TURN_STEP_K, TURN_STEP_MIN, TURN_STEP_MAX)
	var frac := clampf((vv - lo) / maxf(hi - lo, 0.01), 0.0, 1.0)
	var freq: float = _k * sqrt(G / maxf(shoulder_h, 0.1)) / PI * _step_k * lerpf(FREQ_LO, FREQ_HI, frac)
	var prev := phase
	if vv > 0.02:
		phase = fposmod(phase + freq * delta * (signf(speed) if v > 0.02 else signf(turn_rate)), 1.0)
	_move_w = move_toward(_move_w, 1.0 if vv > 0.05 else 0.0, delta * MOVE_BLEND)
	var stride := vv / maxf(freq, 0.1)
	var amp := clampf(atan(stride * _duty * 0.5 / maxf(shoulder_h, 0.1)), 0.0, AMP_MAX) * _move_w
	var lift := clampf(LIFT_BASE + vv * LIFT_PER_V, LIFT_BASE, LIFT_MAX) * _move_w
	# prudké brzdění ze rychlého chodu: trup se vykloní, zadní nohy podstrčí pod tělo
	var acc := (v - _prev_v) / maxf(delta, 0.001)
	var decel := maxf(-acc, 0.0)
	_brake = lerpf(_brake, clampf(decel / BRAKE_DECEL, 0.0, 1.0) * clampf(_prev_v / BRAKE_FROM_V, 0.0, 1.0), minf(delta * BRAKE_BLEND, 1.0))
	_prev_v = v
	_acc_s = lerpf(_acc_s, acc, minf(delta * ACC_BLEND, 1.0))
	# lehání a vstávání po dvojicích nohou: lehá předními; vstává předními (kůň) nebo zadními
	var rising := lie < _lie_prev - 0.002
	_lie_prev = lie
	var fr0 := 0.0                  # okno lehnutí předních (lehá předními jako první)
	var fr1 := LIE_FRONT_END
	var hr0 := LIE_HIND_START
	var hr1 := 1.0
	if rising:
		if _rise_ff:
			fr0 = RISE_LATE_START
			fr1 = 1.0
			hr0 = 0.0
			hr1 = RISE_EARLY_END
		else:
			hr0 = RISE_LATE_START
			hr1 = 1.0
	for i in 4:
		_leg_lie[i] = smoothstep(fr0, fr1, lie) if i < 2 else smoothstep(hr0, hr1, lie)

	# --- trup (pohup krok/klus ↔ houpání cvalu se prolíná)
	var bob := _bob
	var dy_wt := -bob * cos(phase * TAU * 2.0) * _move_w * (1.0 + TROT_BOB_K * _trot_w)
	var dy_c := bob * CANTER_BOB_K * sin(phase * TAU) * _move_w
	var rock := _rock_a * sin(phase * TAU + ROCK_PHASE) * _move_w * _style
	var dy := lerpf(dy_wt, dy_c, _style)
	var roll := -atan(speed * turn_rate / G) * (_lean_k if v2 else OLD_LEAN_K)
	var pitch := -slope + rock
	var lw := maxf(lie, dead)
	var sit_w := sit * (1.0 - lw)
	pitch -= _brake * BRAKE_PITCH                      # brzdění: předek nahoru
	if full:
		pitch -= clampf(_acc_s * _surge, 0.0, SURGE_MAX) * (1.0 - lw)   # rozjezd: předek nahoru
		if airborne > 0.05:
			# ve skoku trup sleduje dráhu: nahoru čenichem vzhůru, dolů předkem dolů
			pitch = lerpf(pitch, -atan2(vy, maxf(v, 1.0)) * AIR_PITCH_K, airborne)
	pitch = lerpf(pitch, SIT_PITCH, sit_w * SIT_PITCH_W)   # sed na zadních: trup skoro svisle
	var y := body_y + dy
	y = lerpf(y, lie_y, lw)
	y = lerpf(y, lerpf(body_y, lie_y, CROUCH_H), crouch * (1.0 - lw))
	y += sit_w * shoulder_h * SIT_LIFT
	# páteř: boční ohyb do zatáčky a flexe/extenze ve cvalu
	var kb := 1.0 - exp(-delta * BEND_BLEND)
	if full:
		var want_b := clampf(turn_rate * _spine_lat * clampf(BEND_V_MIN + v * BEND_V_K, BEND_V_MIN, BEND_V_MAX), -BEND_MAX, BEND_MAX)
		_bend = lerpf(_bend, want_b * (1.0 - lw), kb)
		_flex = _spine_flex * _style * _move_w * cos(TAU * (phase - FLEX_PHASE)) * (1.0 - lw)
	else:
		_bend = lerpf(_bend, 0.0, kb)
		_flex = 0.0
	body.position.y = y
	body.position.z = -sit_w * _L * SIT_BACK
	body.rotation = Vector3(lerpf(pitch, 0.0, lw), _bend * BEND_BODY, lerpf(roll, DEAD_ROLL, dead))
	# svislé zrychlení trupu (budí pružiny uší a ocasu)
	if full:
		var dt := maxf(delta, 0.001)
		var vy_b := (y - _prev_y) / dt
		_acc_y = lerpf(_acc_y, (vy_b - _vel_y) / dt, minf(delta * ACC_Y_BLEND, 1.0))
		_vel_y = vy_b
	_prev_y = y
	# dech: boky se rozšiřují (jen síť trupu, ne nohy); po běhu rychleji
	_puff = move_toward(_puff, 1.0 if v > PUFF_SPEED else 0.0, delta * (PUFF_UP if v > PUFF_SPEED else PUFF_DOWN))
	if _torso:
		if full and v < BREATH_MAX_V and dead < 0.5:
			_breath_p = fmod(_breath_p + delta * _breath_hz * (1.0 + _puff * PUFF_RATE_K) * TAU, TAU)
			var br := sin(_breath_p) * _breath_amp * (1.0 + _puff * PUFF_AMP_K)
			_torso.scale = Vector3(1.0 + br, 1.0 + br * BREATH_Y, 1.0)
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
		if _move_w > 0.5 and v > FOOTFALL_MIN_V:
			var pp := fposmod(prev + _off[i], 1.0)
			if pp > p and speed > 0.0:
				footfall.emit(i)
		f = maxf(f, airborne * AIR_FOLD)
		f = lerpf(f, CROUCH_FOLD, crouch * (1.0 - lw))
		var front := _lfront[i] == 1
		# brzdění: přední se postaví proti, zadní podstrčí dopředu pod tělo
		s += _brake * (BRAKE_FRONT_S if front else BRAKE_HIND_S)
		# sed na zadních: přední zvednuté v nohavicích, zadní pod tělem
		if sit_w > 0.0:
			f = maxf(f, sit_w * SIT_FOLD)
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
		_ik[i] = lerpf(_ik[i], ik_t, minf(delta * IK_BLEND, 1.0))
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
	var nod_wt := cos(phase * TAU * 2.0 + 0.6) * NOD_AMP * _move_w
	var nod := lerpf(nod_wt, -rock * NOD_ROCK, _style)
	if rooting and graze > 0.5:
		nod += sin(_t * ROOT_HZ) * ROOT_AMP
	var neck_pitch := -neck_angle + graze * _graze_a - alert * ALERT_NECK + nod
	neck_pitch = lerpf(neck_pitch, -neck_angle * LIE_NECK, lie * LIE_NECK_W)
	neck_pitch = lerpf(neck_pitch, DEAD_NECK, dead)
	neck_pitch += crouch * CROUCH_NECK
	neck_pitch += sit_w * SIT_NECK                     # v sedu krk vyrovná vztyčený trup
	var look := clampf(look_yaw, -LOOK_MAX, LOOK_MAX)
	if full:
		# divočák běží s nízkou hlavou; hlava drží sklon, i když se trup houpe; krk se při pastvě natáhne
		var run := clampf((v - _v_up[0]) / maxf(_v_up[1] - _v_up[0], 0.1), 0.0, 1.0)
		neck_pitch += _head_low * run * (1.0 - graze) * (1.0 - lw)
		neck_pitch -= brx * _head_stab * (1.0 - lw) * (1.0 - sit_w)
		head.position.z = _neck_len * (1.0 + _neck_reach * graze)
	elif head.position.z != _neck_len:
		head.position.z = _neck_len
	neck.rotation = Vector3(neck_pitch, look * LOOK_NECK * (1.0 - graze) + _bend * BEND_NECK, 0.0)
	head.rotation = Vector3(head_tilt - graze * GRAZE_HEAD - alert * ALERT_HEAD - nod * NOD_HEAD, look * LOOK_HEAD, 0.0)

	# --- uši (škubnutí, nastražení, přitisknutí; M8.10 pružiny a natočení ke zvuku)
	_ear_t -= delta
	if _ear_t <= 0.0:
		_ear_t = _rng.randf_range(EAR_TWITCH_EVERY[0], EAR_TWITCH_EVERY[1])
		_ear_twitch = EAR_TWITCH
	_ear_twitch = move_toward(_ear_twitch, 0.0, delta * EAR_TWITCH_DECAY)
	_listen_w = lerpf(_listen_w, clampf(listen, 0.0, 1.0), minf(delta * LISTEN_BLEND, 1.0))
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
		var tx := base.x + alert * ALERT_EAR - crouch * CROUCH_EAR - _ear_twitch * (1.0 if sd > 0 else 0.0)
		var ez := base.z * (1.0 - crouch * CROUCH_EAR_Z)
		if full:
			# ucho na straně zdroje se natočí víc, druhé méně (každé má vlastní pružinu)
			var side_k := 1.0 + EAR_SIDE_K * signf(ear_dir) * sd
			var ty := base.y + ear_dir * side_k * (1.0 - crouch)
			tx += _listen_w * LISTEN_EAR * (1.0 - crouch)
			var ex := _spring(e * 4, tx, -_acc_y * _ear_flop * _ear_w * _ear_w, _ear_w, _ear_z, delta)
			var ey := _spring(e * 4 + 2, ty, 0.0, _ear_w, _ear_z, delta)
			ears[e].rotation = Vector3(ex, ey, ez)
		else:
			ears[e].rotation = Vector3(tx, base.y, ez)

	# --- ocas (švihání, při útěku nahoru; M8.10 pružina, zrcátko)
	if tail:
		_tail_t += delta * (TAIL_HZ + v * TAIL_HZ_V)
		_flee_w = lerpf(_flee_w, clampf(flee, 0.0, 1.0), minf(delta * FLEE_BLEND, 1.0))
		var up := clampf((v - TAIL_UP_FROM) / TAIL_UP_RANGE, 0.0, 1.0) * _tail_up
		if v2:
			up = maxf(up, _flee_w * _tail_up)
		var tx := _tail_rest.x + up + sin(_tail_t * 0.7) * TAIL_BOB
		var ty := sin(_tail_t) * TAIL_SWISH * (1.0 - minf(up, 1.0) * TAIL_SWISH_UP)
		if full:
			ty -= _bend * BEND_TAIL
			tail.rotation = Vector3(_spring(8, tx, _acc_y * _tail_flop * _tail_w * _tail_w, _tail_w, _tail_z, delta),
				_spring(10, ty, 0.0, _tail_w, _tail_z, delta), 0.0)
		else:
			tail.rotation = Vector3(tx, ty, 0.0)
		if _flare_s > 1.0:
			_flare = lerpf(_flare, _flee_w if v2 else 0.0, minf(delta * FLARE_BLEND, 1.0))
			var fs := lerpf(1.0, _flare_s, _flare)
			tail.scale = Vector3(fs, fs, 1.0)
