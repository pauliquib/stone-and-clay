## Společný letový model ultralehkých letadel (M6.3) – arcade-realistický:
## vztlak a odpor z CL(α) / CD0 + indukovaný odpor, tah motoru podle plynu a rychlosti,
## vítr `Weather.wind_vector()` s výškovým profilem v(h)=v10·(h/10)^0,14 a turbulence
## (bouřka, les, závětrná strana kopce), termika `Thermals`, hranice letu `World.flight_bounds`.
## Ovládání: W/S plyn, A/D překlopení→zatáčení, Mezerník zatáhnout / na zemi brzda,
## Ctrl přiklonit, V kamera, F nastoupit/vystoupit (jen na zemi). Auto-trim drží rychlost v_trim.
## Pojízdní podvozek, rozjezd, přistání, tvrdé přistání nad 3 m/s, havárie o překážku.
## Stroje jsou data v `SPECS` (paraglidové parametry – M6.4 naváže, rogalo M6.5).
##
## FYZIKA (vlna 0d): `custom_integrator` + `_integrate_forces` (vzor `Drone`) – Jolt pak
## nepřičítá vlastní tlumení ani gravitaci (dřív linear_damp 0,1 COMBINE = fiktivní odpor
## 0,2·m·v a stroj nevzlétl). Kolize s terénem je vypnutá (výjimka na TerrainBody) – zem
## i dosednutí řešíme analyticky přes `World.ground_height`, budovy / stromy / props kolidují.
## Počátek tělesa = zem + gear_h; vizuál `vis` je posunutý o −gear_h (y = 0 = kola na zemi).
class_name Aircraft
extends RigidBody3D

const RHO := 1.225                 # hustota vzduchu (kg/m³)
const G := 9.81                    # tíhové zrychlení (m/s²)
const CL_STALL := 0.45             # podíl CL_max po přetáčení
const NEG_A_CL := -0.15            # minimální CL při záporném náběhu (záchrana padáku)
const TURB_BASE := 0.35            # základní turbulence (m/s²)
const TURB_STORM := 2.5            # příspěvek bouřky (násobek storm 0..1)
const TURB_FOREST := 0.9           # příspěvek letu nad lesem (násobek forest_at)
const TURB_LEE := 12.0             # příspěvek závětrné strany kopce (násobek sklonu)
const HARD_LAND_VY := 3.0          # m/s sestupu – tvrdé přistání (poškození + zranění)
const CRASH_LAND_VY := 8.0         # m/s sestupu – havárie
const CRASH_SPD := 9.0             # m/s nárazu do překážky – havárie
const MU_GRASS := 0.045            # valivý odpor na trávě (mokro ×1,3)
const BRAKE_DECEL := 4.0           # brzda na zemi (Mezerník), m/s²
const GROUND_STEER := 0.9          # rad/s zatáčení na zemi při plné rychlosti
const ROLL_RATE := 2.0             # rad/s přibližování banku
const PITCH_RATE := 1.6            # rad/s přibližování pitchi
const OFF_CD := 60.0               # s mezi stejným přestupkem
const XP_PER_M := 0.04             # XP letectví za metr vzdušní dráhy
const DRUNK_DELAY := 0.1           # s zpoždění vstupu na promile (vzor Car)
const CAM_DIST := 6.0              # chase kamera – vzdálenost (m)
const CAM_UP := 2.4                # chase kamera – výška nad zemí pod strojem (vizuál stojí na y = 0)
const ENGINE_BASE_PITCH := 0.7
const THRUST_DROP := 0.5           # tah T = T0·plyn·(1 − 0,5·(v/v_max)²) – stejná křivka na zemi i ve vzduchu
const THRUST_MIN := 0.15           # spodní mez poměru tahu (nad v_max)
const ROT_ALPHA_K := 0.6           # náběh při rotaci na vzlet = 0,6·a_crit (vzlet ~1,2·v_pádová)
const ELEV_PITCH := 0.18           # rad – výchylka pitche výškovkou (Mezerník / Ctrl)
const TRIM_ELEV_V := 0.3           # výškovka posune cílovou rychlost auto-trimu o ±30 % v_trim
const TRIM_W := 0.5                # rad/s – vlastní frekvence držáku rychlosti (perioda ~13 s)
const TRIM_ZETA := 0.8             # tlumení držáku rychlosti (bez fugoidního houpání)
const LAND_GRACE := 0.5            # s po odlepení, kdy se dosednutí nepočítá (hystereze)
const LAND_VY := -0.1              # m/s – dosednutí jen při klesání vůči terénu
const LAND_GAP := 0.05             # m – dosednutí až pod gear_h − LAND_GAP

## Katalog strojů: hodnoty „létající bedna“ = lehký motorový paraglide (tříkolka + padák).
## klíče: name, kg (prázdný), S (m²), AR (poměr stran), e, CL0, CL_A (1/rad), a_crit (°),
## CD0, thrust (N), v_min / v_trim / v_max (m/s), tank_l, dojezd_min (plný plyn), gear_h,
## roll_max (rad), glide (klouzavost 1:x – podle ní je CD0 kalibrované)
## Kalibrace (vlna 0d, PROJECT_LOG): CL_trim = 2·m·g/(ρ·S·v_trim²) při plné nádrži,
## CD0 = CL_trim/glide − CL_trim²/(π·AR·e); auto-trim drží rychlost v_trim (`_trim_alpha`).
const SPECS := {
	"test_letoun": {"name": "Testovací letoun „Létající bedna“", "kg": 62.0, "S": 25.0, "AR": 3.0,
		"e": 0.85, "CL0": 0.35, "CL_A": 2.8, "a_crit": 16.0, "CD0": 0.022, "thrust": 760.0,
		"v_min": 9.0, "v_trim": 13.0, "v_max": 18.0, "tank_l": 12.0, "dojezd_min": 30.0,
		"gear_h": 0.55, "roll_max": 0.55, "glide": 9.0},
	# M6.4: motorový paraglide (třída `Paramotor`) – padákové křídlo ~24 m², motor na zádech,
	# trim ~38 km/h, min ~25 km/h, max ~50 km/h s trimry, klouzavost ~7, spotřeba ~3,8 l/h.
	"paramotor": {"name": "Paramotor „Vlaštovka 24“", "kg": 28.0, "S": 24.0, "AR": 3.1,
		"e": 0.8, "CL0": 0.55, "CL_A": 3.0, "a_crit": 18.0, "CD0": 0.036, "thrust": 650.0,
		"v_min": 7.0, "v_trim": 10.5, "v_max": 14.0, "tank_l": 11.0, "dojezd_min": 175.0,
		"gear_h": 0.9, "roll_max": 0.7, "glide": 7.0},
	# M6.5: motorové rogalo (třída `Trike`) – tříkolka s rogalovým křídlem ~15 m²,
	# cestovní ~90 km/h, pádová ~55 km/h, max ~130 km/h, tah ~1 400 N (stoupání ~5 m/s sólo,
	# ~4 m/s se spolujezdcem – vlna 0d), nádrž 50 l
	# (~14 l/h → dojezd ~210 min), prázdná ~200 kg, MTOW ~450 kg, 2 sedadla za sebou.
	"trike": {"name": "Motorové rogalo „Vlaštovka T-60“", "kg": 200.0, "S": 15.0, "AR": 6.7,
		"e": 0.7, "CL0": 0.4, "CL_A": 3.4, "a_crit": 15.0, "CD0": 0.048, "thrust": 1400.0,
		"v_min": 15.3, "v_trim": 25.0, "v_max": 36.0, "tank_l": 50.0, "dojezd_min": 210.0,
		"gear_h": 0.85, "roll_max": 0.6, "glide": 8.0},
}

## Továrna na stroj podle modelu (M6.4: „paramotor“ staví `Paramotor`, jinak základní `Aircraft`).
static func make(model_id: String) -> Aircraft:
	if model_id == "paramotor":
		return Paramotor.new()
	if model_id == "trike":
		return Trike.new()
	return Aircraft.new()

const PILOT_KG := 85.0             # hmotnost pilota (zjednodušení)
const FUEL_KG_L := 0.72            # hustota benzinu (kg/l)

var world: World
var owner_id := 0
var pilot: Player
var pilot_input: InputState
var body_state: BodyState
var model := ""
var spec := {}
## Sedadlo pilota vůči `vis` (y = 0 = zem pod koly, −Z vpřed); postava je otočená o 180°
## (Humanoid kouká do +Z). `rider` = póza pro `Humanoid.ride` (souřadnice postavy, +Z vpřed),
## `eye_pos` = oči pilota pro kameru z kabiny. Každý stroj je nastaví v `_build_mesh`.
var seat_pos := Vector3(0.0, 0.2, -0.45)
var rider := {}
var eye_pos := Vector3(0.0, 1.37, -0.5)

var fuel_l := 0.0                  # zbývá paliva (l)
var dmg := 0.0                     # poškození 0..100
var throttle := 0.0                # vyhlazený plyn 0..1
## Stav „na zemi“ drží stavový automat `_chart` (Fáze 4 – godot-state-charts); zápis
## (`on_ground = …`) jen pošle událost vzlet/dosednutí, čtení se odvozuje z aktivního stavu.
## Bez addonu (GDScript třídy chybí) běží zjednodušený fallback na bool flagy – fyzika stejná.
var on_ground: bool:
	get:
		if _chart_up():
			return _st_zeme.active
		return _fb_ground
	set(v):
		_stav_event(&"dosednuti" if v else &"vzlet")
var speed := 0.0                   # pozemní rychlost při pojíždění / celková rychlost stroje (m/s)

var _yaw := 0.0
var _pitch := 0.0
var _bank := 0.0
## Přetažení = aktivita stavu „Pretazeni“ (jen čtení; stav řídí události pretazeni/zotaveni).
var _stalled: bool:
	get:
		if _chart_up():
			return _st_stall.active
		return _fb_stall
var _fb_ground := true             # fallback bez addonu / dokud chart nevstoupil do init stavu
var _fb_stall := false
var _stall_warn_t := -10.0         # _life_t posledního varování přetažení (turbulence jinak spamuje)
var _off_cd := {}
var _law_t := 0.0
var _life_t := 0.0
var _xp_d := 0.0                   # nalétané metry → XP při dosednutí
var _fuel_warned := false
var _edge_warned := false
var _hist: Array = []              # opožděný vstup při opilosti (vzor Car)
var _turb := FastNoiseLite.new()
var _prev_xf := Transform3D.IDENTITY
var _cur_xf := Transform3D.IDENTITY
## Pracovní stav kroku `_integrate_forces`: podtřídy čtou / zapisují `_xf` a `_v` místo
## global_transform / linear_velocity (ty se zapíšou do body state na konci kroku).
var _xf := Transform3D.IDENTITY
var _v := Vector3.ZERO
var _air_t := -10.0                # _life_t odlepení (hystereze dosednutí)

var vis: Node3D
var _cam_rig: Node3D
var _cam: Camera3D
var cam_mode := 0                  # 0 = chase, 1 = pilot (FPP)
var _cam_yaw := 0.0                # volný pohled myší (chase, drift zpět)
var _cam_pos := Vector3.ZERO       # vyhlazená pozice chase kamery
var snd: AudioStreamPlayer3D
var _prop: MeshInstance3D

# --------------------------------------------------- stavový automat letu (Fáze 4)
## addon godot-state-charts (GDScript, `addons/godot_state_charts`) – třídy se načítají
## dynamicky, aby `aircraft.gd` fungoval i bez addonu (fallback na `_fb_*` flagy).
const GSC_DIR := "res://addons/godot_state_charts/"
## Uzly chartu držíme jako Variant (netypované) – addon třídy nemusejí existovat
## a volání `send_event`/`active`/`initial_state` tak zůstane dynamické (fallback OK).
var _chart = null                  # StateChart uzel (nebo null bez addonu)
var _st_zeme = null                # AtomicState „Zeme“
var _st_vzduch = null              # CompoundState „Vzduch“
var _st_stall = null               # AtomicState „Pretazeni“


## Je addon godot-state-charts v projektu k dispozici?
static func chart_addon() -> bool:
	return ResourceLoader.exists(GSC_DIR + "state_chart.gd") \
		and ResourceLoader.exists(GSC_DIR + "atomic_state.gd") \
		and ResourceLoader.exists(GSC_DIR + "compound_state.gd") \
		and ResourceLoader.exists(GSC_DIR + "transition.gd")


## Chart řídí stav teprve po vstupu do výchozího stavu (init běží deferred po _ready).
func _chart_up() -> bool:
	return _chart != null and _chart.is_node_ready() \
		and _st_zeme != null and (_st_zeme.active or _st_vzduch.active)


## Událost do stavového automatu; bez addonu (nebo dokud init nenaběhl) jen přepíše flagy.
func _stav_event(ev: StringName) -> void:
	if _chart_up():
		_chart.send_event(ev)
		return
	match ev:
		&"vzlet":
			_fb_ground = false
			_fb_stall = false   # vstup do Vzduch → výchozí podstav Let (stejně jako v chartu)
		&"pretazeni":
			if not _fb_ground:
				_fb_stall = true
		&"zotaveni":
			_fb_stall = false
		&"dosednuti":
			_fb_ground = true
			_fb_stall = false


## Sestaví stavový automat programově (stroj vzniká čistě v kódu – žádná .tscn):
##   Koren (Compound, init Zeme)
##   ├── Zeme   (Atomic) – pojíždění / parkování; událost vzlet → Vzduch
##   └── Vzduch (Compound, init Let) – událost dosednuti → Zeme (z obou podstavů)
##       ├── Let        (Atomic) – událost pretazeni → Pretazeni
##       └── Pretazeni  (Atomic) – událost zotaveni → Let
func _build_chart() -> void:
	if not chart_addon():
		return
	var atomic: GDScript = load(GSC_DIR + "atomic_state.gd")
	var compound: GDScript = load(GSC_DIR + "compound_state.gd")
	var trans_gd: GDScript = load(GSC_DIR + "transition.gd")
	var chart_gd: GDScript = load(GSC_DIR + "state_chart.gd")
	if atomic == null or compound == null or trans_gd == null or chart_gd == null:
		push_warning("Aircraft: godot-state-charts se nepodařilo načíst – fallback na bool flagy.")
		return
	_chart = chart_gd.new()
	_chart.name = "StavLetu"
	var koren = compound.new()
	koren.name = "Koren"
	_st_zeme = atomic.new()
	_st_zeme.name = "Zeme"
	_st_vzduch = compound.new()
	_st_vzduch.name = "Vzduch"
	var st_let = atomic.new()
	st_let.name = "Let"
	_st_stall = atomic.new()
	_st_stall.name = "Pretazeni"
	_chart.add_child(koren)
	koren.add_child(_st_zeme)
	koren.add_child(_st_vzduch)
	_st_vzduch.add_child(st_let)
	_st_vzduch.add_child(_st_stall)
	koren.initial_state = NodePath("Zeme")           # před vstupem do stromu (onready se váže)
	_st_vzduch.initial_state = NodePath("Let")
	var mk_tr := func(parent, nazev: String, ev: StringName, to: NodePath) -> void:
		var t = trans_gd.new()
		t.name = nazev
		t.event = ev
		t.to = to
		parent.add_child(t)
	# `to` je relativní k uzlu Transition (ne ke stavu) → sourozenci rodiče = „../../Cil“
	mk_tr.call(_st_zeme, "NaVzlet", &"vzlet", NodePath("../../Vzduch"))
	mk_tr.call(st_let, "NaPretazeni", &"pretazeni", NodePath("../../Pretazeni"))
	mk_tr.call(_st_stall, "NaZotaveni", &"zotaveni", NodePath("../../Let"))
	mk_tr.call(_st_vzduch, "NaDosednuti", &"dosednuti", NodePath("../../Zeme"))
	# §4.3: enter/exit hooky – přetažení hlásí + varovný tón, dosednutí jen přepne stav
	_st_zeme.state_entered.connect(_on_zeme_entered)
	_st_stall.state_entered.connect(_on_pretazeni_entered)
	_st_stall.state_exited.connect(_on_pretazeni_exited)
	add_child(_chart)


## Vstup do stavu „Zeme“ (dosednutí, havárie, parkování): let se ukončuje – uklidíme
## volný pohled a varování okraje, ať příští vzlet startuje čistě (fyzika dosednutí
## zůstává v `_in_air` – tam jsou podmínky, dopad i XP).
func _on_zeme_entered() -> void:
	_cam_yaw = 0.0
	_edge_warned = false


## Vstup do stavu „Pretazeni“: varování pilota (HUD hláška v `status()` trvá, dokud stav trvá;
## hláška + tón jen jednou za ~6 s, aby turbulence kolem a_crit nespamovala oznámení).
func _on_pretazeni_entered() -> void:
	if _life_t - _stall_warn_t < 6.0:
		return
	_stall_warn_t = _life_t
	_notify(_stall_hint(), 3.0)
	if world:
		world.play_sfx(owner_id, "fail", 1.6, -6.0)


## Výstup z přetažení (zotavení i dosednutí) – hláška v HUD mizí sama přes `status()`.
func _on_pretazeni_exited() -> void:
	pass


## Hláška při vstupu do přetažení (podtřídy mohou přepsat – u paramotoru se pouští brzdy).
func _stall_hint() -> String:
	return "PŘETAŽENÍ! Nos padá – přikloň (Ctrl) a přidej plyn."


## Aktuální stav automatu pro testy / ladění („Zeme“, „Let“, „Pretazeni“; „-“ bez chartu).
func stav_letu() -> String:
	if _chart_up():
		if _st_zeme.active:
			return "Zeme"
		if _st_stall.active:
			return "Pretazeni"
		if _st_vzduch.active:
			return "Let"
		return "-"
	return "Zeme" if _fb_ground else ("Pretazeni" if _fb_stall else "Let")


func spec_of(m: String) -> Dictionary:
	return SPECS.get(m, {})


## Postaví stroj (fyzika, vizuál z MeshKit, zvuk). Volá `World.spawn_aircraft` / načtení save.
func setup(w: World, pid: int, model_id: String) -> void:
	world = w
	owner_id = pid
	model = model_id
	spec = SPECS.get(model_id, SPECS["test_letoun"])
	fuel_l = float(spec["tank_l"])
	mass = float(spec["kg"]) + PILOT_KG
	collision_layer = 16                   # vozidla – registrují ho terén, props i postavy
	collision_mask = 1 | 2 | 4 | 8 | 16
	contact_monitor = true
	max_contacts_reported = 8
	can_sleep = false
	custom_integrator = true               # sílu počítáme sami v _integrate_forces (Jolt nepřidá tlumení ani gravitaci)
	gravity_scale = 0.0                    # gravitaci počítáme sami (G = 9,81 ≠ default 20)
	continuous_cd = true                   # Jolt: CCD – letoun v rychlosti neprostřelí budovu
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE   # pojistka: i bez custom_integratoru nulové tlumení
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.0
	var gh := float(spec["gear_h"])
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(1.8, 1.6, 3.0)
	cs.position = Vector3(0, 0.25 + 0.8 - gh, 0)   # spodek kvádru 0,25 m nad zemí (kola nekolidují)
	cs.shape = bx
	add_child(cs)
	# terén nekoliduje: zem a dosednutí řešíme analyticky (A2-07 – bank / hrbol už není „náraz“;
	# okrajové zdi katastru `Terrain._add_bounds` patří k TerrainBody → let nad okolí funguje)
	if world.terrain:
		var tb := world.terrain.get_node_or_null("TerrainBody") as PhysicsBody3D
		if tb:
			add_collision_exception_with(tb)
	body_entered.connect(_on_body)
	vis = Node3D.new()
	vis.top_level = true
	add_child(vis)
	_build_mesh()
	snd = AudioStreamPlayer3D.new()
	snd.stream = Sfx.engine_loop()
	snd.unit_size = 6.0
	snd.max_distance = 80.0
	snd.volume_db = -18.0
	add_child(snd)
	_turb.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_turb.frequency = 0.6
	_turb.seed = 4501 + pid
	_prev_xf = global_transform
	_cur_xf = global_transform
	_build_chart()                       # Fáze 4: stavový automat letu (on_ground / _stalled)


## Póza sedícího pilota pro `Humanoid.ride` z bodů ve `vis` (−Z vpřed): převod do souřadnic
## postavy (otočené o 180°, počátek = `seat`). `hips` = výška pánve nad `seat`.
static func rider_pose(seat: Vector3, hips: float, lean: float, hands: Vector3, feet: Vector3) -> Dictionary:
	var h := Vector3(0.0, hands.y - seat.y, seat.z - hands.z)
	var f := Vector3(0.0, feet.y - seat.y, seat.z - feet.z)
	return {"hips": hips, "lean": lean, "hands": [h], "feet": [f, f]}


## Trubka mezi body (sdílí `BikeModel.tube` – lanka, vzpěry, trubky rogala).
static func rod(mk: MeshKit, a: Vector3, b: Vector3, r: float, col: Color, seg := 6) -> void:
	BikeModel.tube(mk, a, b, r, col, seg)


## Procedurální „létající bedna“: hornoplošník s otevřenou gondolou, tlačnou vrtulí za
## křídlem, ocasním nosníkem a příďovým podvozkem. `vis`: y = 0 zem, −Z vpřed, 1 j = 1 m.
func _build_mesh() -> void:
	var mk := MeshKit.new()
	var frame := Color(0.35, 0.35, 0.38)
	var dark := Color(0.12, 0.12, 0.13)
	var pod := Color(0.92, 0.9, 0.84)
	var cloth := Color(0.85, 0.45, 0.15)
	# gondola (otevřená shora – pilot z ní kouká po ramena) + sedačka
	mk.capsule(Vector3(0, 0.6, -0.55), 0.42, 2.1, pod, Vector3(PI * 0.5, 0, 0), Vector3(0.95, 0.85, 1.0))
	mk.box(Vector3(0, 0.56, -0.4), Vector3(0.48, 0.12, 0.45), Color(0.2, 0.2, 0.22))    # sedák (vršek 0,62)
	mk.box(Vector3(0, 0.85, -0.12), Vector3(0.48, 0.5, 0.08), Color(0.2, 0.2, 0.22))    # opěradlo
	mk.box(Vector3(0, 0.62, -1.05), Vector3(0.36, 0.06, 0.14), Color(0.25, 0.25, 0.27)) # pedály
	rod(mk, Vector3(0, 0.45, -0.85), Vector3(0, 0.84, -0.86), 0.018, dark)                 # knipl
	# křídlo: profil přes rozpětí 8,6 m, hloubka 2,6 m (25 m² ≈ „bedna“), vršek na 2,1 m
	_airfoil_wing(mk, 4.3, 2.6, 2.6, Vector3(0, 2.0, -0.95), 0.16, 0.06, cloth, cloth.darkened(0.25), 8)
	# vzpěry křídla do V + kabina k nosníku
	for sx in [-1.0, 1.0]:
		rod(mk, Vector3(sx * 0.32, 0.55, -0.6), Vector3(sx * 2.4, 1.98, -0.55), 0.025, frame)
		rod(mk, Vector3(sx * 0.32, 0.55, -0.4), Vector3(sx * 2.4, 1.98, 0.9), 0.025, frame)
	rod(mk, Vector3(0, 0.95, 0.35), Vector3(0, 2.0, 0.4), 0.04, frame)
	# motor za pilotem pod odtokovou hranou + ocasní nosník nad vrtulí
	mk.box(Vector3(0, 1.3, 1.25), Vector3(0.42, 0.42, 0.55), Color(0.3, 0.3, 0.32))
	rod(mk, Vector3(0, 0.9, 0.4), Vector3(0, 1.25, 1.0), 0.035, frame)
	rod(mk, Vector3(0, 2.05, 1.5), Vector3(0, 1.85, 4.3), 0.05, frame)
	mk.box(Vector3(0, 1.85, 4.05), Vector3(2.6, 0.05, 0.75), cloth)                      # VOP
	mk.box(Vector3(0, 2.3, 4.1), Vector3(0.05, 0.9, 0.7), cloth)                         # SOP
	# podvozek: dvě hlavní kola + příďové, nohy
	for sx in [-1.0, 1.0]:
		mk.cylinder(Vector3(sx * 0.78, 0.22, 0.05), 0.22, 0.22, 0.1, dark, Vector3(0, 0, PI * 0.5), 12)
		rod(mk, Vector3(sx * 0.3, 0.4, -0.3), Vector3(sx * 0.74, 0.22, 0.05), 0.025, frame)
	mk.cylinder(Vector3(0, 0.2, -1.55), 0.2, 0.2, 0.09, dark, Vector3(0, 0, PI * 0.5), 12)
	rod(mk, Vector3(0, 0.45, -1.4), Vector3(0, 0.2, -1.55), 0.025, frame)
	var mi := MeshInstance3D.new()
	mi.mesh = mk.commit(MeshKit.vc_material(0.75))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	vis.add_child(mi)
	_prop = MeshInstance3D.new()           # list vrtule (točí se kolem Z)
	var pmk := MeshKit.new()
	pmk.box(Vector3.ZERO, Vector3(0.08, 1.3, 0.03), Color(0.1, 0.1, 0.1))
	_prop.mesh = pmk.commit(MeshKit.vc_material(0.6))
	_prop.position = Vector3(0, 1.3, 1.6)
	vis.add_child(_prop)
	# pilot: pánev ~5 cm nad sedákem (vršek 0,62), nohy na pedálech, ruka na kniplu
	seat_pos = Vector3(0, 0.62 + 0.06 - 0.5, -0.42)
	rider = rider_pose(seat_pos, 0.5, -0.08, Vector3(0, 0.86, -0.86), Vector3(0, 0.66, -1.05))
	eye_pos = seat_pos + Vector3(0, 1.17, -0.06)


## Křídlo s profilem (uzavřený loft přes rozpětí): `half` půlrozpětí, `c_root` / `c_tip` hloubka,
## `le` = náběžná hrana u kořene (vis), `thick` tloušťka profilu (podíl hloubky), `dihedral` m
## na konci, `n` stanic na polovinu. Pořadí bodů profilu náběžná → horní strana → odtoková
## → spodní strana, stanice od −X do +X → normály ven (viz `MeshKit.loft`).
func _airfoil_wing(mk: MeshKit, half: float, c_root: float, c_tip: float, le: Vector3,
		thick: float, dihedral: float, top_col: Color, bot_col: Color, n: int) -> void:
	var rings := []
	var cols := []
	const PROF := [[0.0, 0.0], [0.05, 0.55], [0.25, 1.0], [0.55, 0.75], [1.0, 0.0]]   # (x/c, horní tloušťka)
	for i in range(-n, n + 1):
		var t := float(i) / n
		var x := t * half
		var c := lerpf(c_root, c_tip, absf(t))
		var y0 := le.y + absf(t) * dihedral
		var z0 := le.z + absf(t) * 0.1
		var ring := PackedVector3Array()
		var rc := []
		for pp in PROF:                                    # horní strana od náběžné k odtokové
			ring.append(Vector3(x, y0 + float(pp[1]) * thick * c * 0.6, z0 + float(pp[0]) * c))
			rc.append(top_col)
		for k in range(PROF.size() - 2, 0, -1):            # spodní strana zpět k náběžné
			var pb: Array = PROF[k]
			ring.append(Vector3(x, y0 - float(pb[1]) * thick * c * 0.25, z0 + float(pb[0]) * c))
			rc.append(bot_col)
		rings.append(ring)
		cols.append(rc)
	mk.loft(rings, cols, true)
	cap_ring(mk, rings[0], true, bot_col)                  # koncové oblouky křídla
	cap_ring(mk, rings[rings.size() - 1], false, bot_col)


## Víčko uzavřeného profilu (vějíř ze středu) – `first` = první stanice loftu (normála ven proti
## směru stanic), jinak poslední (normála po směru). Pořadí bodů jako v `_airfoil_wing`.
static func cap_ring(mk: MeshKit, r: PackedVector3Array, first: bool, col: Color) -> void:
	var ctr := Vector3.ZERO
	for q in r:
		ctr += q
	ctr /= float(r.size())
	for j in r.size():
		var a2 := r[j]
		var b2 := r[(j + 1) % r.size()]
		if first:
			mk.tri(ctr, a2, b2, col)
		else:
			mk.tri(ctr, b2, a2, col)


## Zaparkovat na místo (spawn / načtení save).
func park(pos: Vector3, face_yaw: float) -> void:
	on_ground = true
	freeze = true
	_yaw = face_yaw
	_pitch = 0.0
	_bank = 0.0
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	speed = 0.0
	global_transform = Transform3D(Basis(Vector3.UP, face_yaw), pos)
	_xf = global_transform
	_v = Vector3.ZERO
	_prev_xf = global_transform
	_cur_xf = global_transform
	vis.global_transform = _vis_xf(global_transform)


## Vizuál stojí na zemi: počátek tělesa je gear_h nad terénem, `vis` o gear_h níž (A2-06).
func _vis_xf(body_xf: Transform3D) -> Transform3D:
	return body_xf * Transform3D(Basis.IDENTITY, Vector3(0.0, -float(spec["gear_h"]), 0.0))


## Výška země pod bodem: terén katastru, za ním hrubé okolí (`World.ground_height`, A2-11).
func _gh(x: float, z: float) -> float:
	if world == null:
		return 0.0
	return world.ground_height(x, z)


## Nastoupení pilota (World.enter_aircraft → Player.enter_aircraft).
func set_pilot(p: Player) -> void:
	pilot = p
	pilot_input = p.input
	body_state = p.body
	freeze = false
	throttle = 0.0
	cam_mode = 1                       # po nástupu pohled z kabiny (V = chase)
	_fuel_warned = fuel_l <= 0.0
	if p.camera:
		_cam_rig = Node3D.new()
		_cam_rig.top_level = true
		add_child(_cam_rig)
		_cam = Camera3D.new()
		_cam.fov = 72.0
		_cam.near = 0.1
		_cam.far = 9000.0
		_cam_rig.add_child(_cam)
		_cam_pos = _vis_xf(global_transform) * Vector3(0, CAM_UP, CAM_DIST)
		_cam_rig.global_position = _cam_pos
		_cam.current = true
		_cam_yaw = 0.0


func clear_pilot() -> void:
	if _cam_rig:
		_cam_rig.queue_free()
		_cam_rig = null
		_cam = null
	pilot = null
	pilot_input = null
	body_state = null
	_hist.clear()
	if on_ground:
		freeze = true
		if snd:
			snd.stop()


func camera() -> Camera3D:
	return _cam


func flying() -> bool:
	return not on_ground


## Rychlost chůze / běhu postavy pilota (Humanoid.speed) – sedící pilot 0; paramotor přepisuje.
func rider_speed() -> float:
	return 0.0


func speed_kmh() -> float:
	return speed * 3.6


## Celková vzletová hmotnost (kg) – prázdný + pilot + palivo.
func total_kg() -> float:
	return float(spec["kg"]) + PILOT_KG + fuel_l * FUEL_KG_L


## Vítr v `pos`: v10 z Weather + výškový profil (h/10)^0,14 + svislá složka z termiky.
func wind_at(pos: Vector3) -> Vector3:
	var w := Vector3.ZERO
	if world and world.weather:
		w = world.weather.wind_vector()
		var agl := maxf(pos.y - _gh(pos.x, pos.z), 1.0)
		w *= pow(agl / 10.0, 0.14)
		if world.thermals:
			w.y += world.thermals.lift_at(pos)
	return w


## Turbulence (m/s²): základ + bouřka + les + závětrná strana kopce proti větru.
func _turbulence(pos: Vector3) -> Vector3:
	if world == null or world.weather == null:
		return Vector3.ZERO
	var amp := TURB_BASE + world.weather.storm * TURB_STORM
	if world.fauna:
		amp += world.fauna.forest_at(pos.x, pos.z) * TURB_FOREST
	if world.terrain:
		var wd := world.weather.wind_vector()
		if wd.length() > 0.5:
			var w2 := Vector2(wd.x, wd.z).normalized()
			var h_up := _gh(pos.x - w2.x * 60.0, pos.z - w2.y * 60.0)
			var h_here := _gh(pos.x, pos.z)
			if pos.y - h_here < 200.0:                   # závětří působí jen nízko
				amp += maxf((h_up - h_here) / 60.0, 0.0) * TURB_LEE * minf(wd.length() / 6.0, 1.0)
	var t := Time.get_ticks_msec() * 0.001
	return Vector3(_turb.get_noise_2d(pos.x * 0.05 + t, pos.z * 0.05),
		_turb.get_noise_2d(pos.y * 0.1 + t, pos.x * 0.05),
		_turb.get_noise_2d(pos.z * 0.05, pos.y * 0.1 - t)) * amp


## Opožděný vstup v opilosti (stejný princip jako Car): [thr, steer, elev]
func _delayed_input(dt: float) -> Array:
	var thr := clampf(pilot_input.throttle - pilot_input.brake * 0.3, 0.0, 1.0) if pilot_input else 0.0
	var steer := -pilot_input.steer if pilot_input else 0.0            # A = bank vlevo
	var elev := 0.0
	if pilot_input:
		if pilot_input.jump:
			elev += 1.0                                              # zatáhnout / na zemi brzda
		if pilot_input.crouch:
			elev -= 1.0                                              # přiklonit
	var delay := clampf(body_state.promile() * DRUNK_DELAY, 0.0, 0.45) if body_state else 0.0
	_hist.append([_life_t, [thr, steer, elev]])
	while _hist.size() > 1 and _life_t - float(_hist[1][0]) >= delay:
		_hist.pop_front()
	if _hist.is_empty():
		return [0.0, 0.0, 0.0]
	return _hist[0][1]


## Krok fyziky (A2-01): custom_integrator – rychlost i orientaci počítáme sami a zapíšeme
## do body state; Jolt jen posune těleso o v·dt a vyřeší kolize s budovami / stromy / props.
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var dt := state.step
	_life_t += dt
	_xf = state.transform
	_v = state.linear_velocity
	if pilot == null or world == null:
		_prev_xf = _cur_xf                                       # bez pilota stojí (park / freeze)
		_cur_xf = _xf
		return
	if dmg >= 100.0:
		_wreck_step(dt)                                          # havárie – jen klesá a dojede
	else:
		_fly_step(dt)
	state.transform = _xf
	state.linear_velocity = _v
	state.angular_velocity = Vector3.ZERO
	_prev_xf = _cur_xf
	_cur_xf = _xf


## Vrak: gravitace, dojezd po zemi (terén nekoliduje → zem analyticky).
func _wreck_step(dt: float) -> void:
	var pos := _xf.origin
	var v := _v + Vector3(0, -G, 0) * dt
	var floor_y := _gh(pos.x, pos.z) + float(spec["gear_h"]) * 0.6
	if pos.y <= floor_y:
		pos.y = floor_y
		v.y = maxf(v.y, 0.0)
		var k := exp(-3.0 * dt)
		v.x *= k
		v.z *= k
	_xf = Transform3D(Basis.from_euler(Vector3(_pitch, _yaw, _bank)), pos)
	_v = v
	speed = v.length()


func _fly_step(dt: float) -> void:
	var pos := _xf.origin
	var gy: float = _gh(pos.x, pos.z)
	var agl: float = pos.y - gy
	var inp := _delayed_input(dt)
	var thr_in: float = inp[0]
	var steer_in: float = inp[1]
	var elev_in: float = inp[2]
	throttle = lerpf(throttle, thr_in, minf(dt * 4.0, 1.0))
	# hranice letu (M6.2): „protivítr“ zpět nad katastr / dolů pod strop – přičte se k větru
	# (m/s proudění, ne zrychlení – A2-12); na zemi se neuplatní
	var fb: Dictionary = world.flight_bounds(pos)
	_edge_warned = bool(fb["warn"]) and not on_ground
	if on_ground:
		_on_ground(_xf, gy, steer_in, elev_in, dt)
	else:
		var wind := wind_at(pos) + _turbulence(pos) + (fb["push"] as Vector3)
		_in_air(_xf, wind, _v, agl, gy, steer_in, elev_in, dt)
	_law_check(dt)
	# XP za nalétané metry (zapíše se při dosednutí / vystoupení)
	if not on_ground:
		_xp_d += Vector3(_v.x, 0, _v.z).length() * dt
		speed = _v.length()


# ------------------------------------------------------------------ aerodynamika (sdílená)

## Tah motoru – jedna křivka na zemi i ve vzduchu (A2-02): T0·plyn·(1 − 0,5·(v/v_max)²).
func _thrust(va: float) -> float:
	if fuel_l <= 0.0:
		return 0.0
	var vm := float(spec["v_max"]) + _v_max_bonus()
	return float(spec["thrust"]) * throttle * maxf(1.0 - THRUST_DROP * pow(va / vm, 2.0), THRUST_MIN)


## Součinitel vztlaku bez přetažení (na zemi i ve vzduchu).
func _cl_of(alpha: float) -> float:
	var cl_max := float(spec["CL0"]) + float(spec["CL_A"]) * deg_to_rad(float(spec["a_crit"]))
	return clampf(float(spec["CL0"]) + float(spec["CL_A"]) * alpha, NEG_A_CL, cl_max)


func _cd_of(cl: float) -> float:
	return float(spec["CD0"]) + cl * cl / (PI * float(spec["AR"]) * float(spec["e"])) + _extra_drag()


## Náběh při rotaci na vzlet (a při pomalém letu po odlepení).
func _rot_alpha() -> float:
	return deg_to_rad(float(spec["a_crit"])) * ROT_ALPHA_K


## Auto-trim (A2-02) = tlumený držák rychlosti v_trim: požadovaná změna sklonu dráhy
## γ̇ = (ω²·(v − v_trim) + 2ζω·v̇) / g → potřebný vztlak L = m·(g·cos γ + v·γ̇) − T·sin α
## → náběh (max. náběh rotace). Ustáleně letí v_trim: bez motoru klouže s klouzavostí `glide`,
## s plynem stoupá (přebytek tahu). Výškovka posune cílovou rychlost (Mezerník pomaleji / Ctrl
## rychleji). `vdot` = podélné zrychlení vůči vzduchu, `t_norm` = složka tahu kolmo k proudu.
func _trim_alpha(va: float, vdot: float, gamma: float, t_norm: float, elev_in: float) -> float:
	var v_t := float(spec["v_trim"]) * (1.0 - TRIM_ELEV_V * clampf(elev_in, -1.0, 1.0))
	var vv := maxf(va, 1.0)
	var gdot := (TRIM_W * TRIM_W * (vv - v_t) + 2.0 * TRIM_ZETA * TRIM_W * vdot) / G
	var lift := total_kg() * (G * cos(gamma) / maxf(cos(_bank), 0.5) + vv * gdot) - t_norm   # v zatáčce víc vztlaku
	var cl := lift / (0.5 * RHO * vv * vv * float(spec["S"]))
	return clampf((cl - float(spec["CL0"])) / float(spec["CL_A"]), -0.1, _rot_alpha())


## Aerodynamika na zemi (A2-03): rychlost je vodorovná, náběh = pitch − sklon terénu.
## `wing` = násobek křídla (paramotor s křídlem na zemi 0). Vrací {va: dopředná rychlost
## vůči vzduchu, lift: N, drag: N (kladný brzdí)}.
func _ground_aero(pos: Vector3, fwd: Vector3, v_ground: float, slope: float, wing := 1.0) -> Dictionary:
	var wind := wind_at(pos)
	var vf := v_ground - fwd.dot(Vector3(wind.x, 0.0, wind.z))     # protivítr přidává
	var alpha := _pitch - atan(clampf(slope, -0.4, 0.4))
	var cl := _cl_of(alpha) * _lift_scale() * wing
	var qs := 0.5 * RHO * vf * absf(vf) * float(spec["S"])
	return {"va": maxf(vf, 0.0), "lift": maxf(qs, 0.0) * cl, "drag": qs * _cd_of(cl) * wing}


## Sklon terénu ve směru jízdy (rozjezd do kopce / z kopce).
func _slope_at(pos: Vector3, fwd: Vector3) -> float:
	var h_a := _gh(pos.x + fwd.x * 2.0, pos.z + fwd.z * 2.0)
	var h_b := _gh(pos.x - fwd.x * 2.0, pos.z - fwd.z * 2.0)
	return (h_a - h_b) / 4.0


## Společný pohyb po zemi: řízení příďovým kolem, pitch podle terénu + rotace při rychlosti,
## počátek gear_h nad zemí, rychlost vodorovně ve směru yaw.
func _ground_move(pos: Vector3, gy: float, slope: float, v_ground: float, va: float,
		steer_in: float, dt: float, can_rotate := true) -> void:
	_yaw -= steer_in * GROUND_STEER * clampf(v_ground / 6.0, 0.0, 1.0) * dt
	_bank = lerpf(_bank, -steer_in * 0.05, minf(dt * 3.0, 1.0))
	var pitch_tgt := atan(clampf(slope, -0.4, 0.4))
	if can_rotate and va >= float(spec["v_min"]) * 0.9:
		pitch_tgt += _rot_alpha()                                  # rotace na vzlet
	_pitch = lerpf(_pitch, pitch_tgt, minf(dt * 3.0, 1.0))
	pos.y = gy + float(spec["gear_h"])
	_xf = Transform3D(Basis.from_euler(Vector3(_pitch, _yaw, _bank)), pos)
	_v = Vector3(-sin(_yaw), 0.0, -cos(_yaw)) * v_ground
	speed = v_ground


## Odlepení: vztlak převáží tíhu při rychlosti vůči vzduchu ≥ 0,95·v_min (a stroj se už valí).
func _try_liftoff(lift: float, va: float, v_ground: float) -> bool:
	if lift <= total_kg() * G or va < float(spec["v_min"]) * 0.95 or v_ground < 1.0:
		return false
	on_ground = false
	_air_t = _life_t
	_v.y = 0.2
	return true


## Pojíždění po zemi: tah − aerodynamický odpor − valivý odpor (zatížení zmenšené o vztlak),
## řízení kolem svislé osy, terén kopíruje profil, vzlet sám, když vztlak převáží.
func _on_ground(xf: Transform3D, gy: float,
		steer_in: float, elev_in: float, dt: float) -> void:
	var pos := xf.origin
	var fwd := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var slope := _slope_at(pos, fwd)
	var v_ground := maxf(speed, 0.0)
	var m := total_kg()
	var ae := _ground_aero(pos, fwd, v_ground, slope)
	var t := _thrust(float(ae["va"]))
	var mu := _mu_ground() * (1.3 if world.weather and world.weather.surface_grip("teren") < 0.9 else 1.0)
	var wload := maxf(m * G - float(ae["lift"]), 0.0)
	var a := (t - float(ae["drag"]) - mu * wload) / m - G * slope * 0.5
	if elev_in > 0.0:                                            # Mezerník na zemi = brzda
		a -= BRAKE_DECEL
	v_ground = maxf(v_ground + a * dt, 0.0)
	_burn_fuel(dt)
	_ground_move(pos, gy, slope, v_ground, float(ae["va"]), steer_in, dt)
	if _try_liftoff(float(ae["lift"]), float(ae["va"]), v_ground):
		_notify(_takeoff_hint(), 4.0)


## Ve vzduchu: aerodynamika (CL(α) s přetáčením, CD0 + CL²/(π·AR·e)), tah, gravitace;
## orientaci držíme sami – bank ze steer → zatáčka g·tan(φ)/v, pitch auto-trim na γ+α_trim.
func _in_air(xf: Transform3D, wind: Vector3, v: Vector3,
		agl: float, gy: float, steer_in: float, elev_in: float, dt: float) -> void:
	var pos := xf.origin
	var basis := Basis.from_euler(Vector3(_pitch, _yaw, _bank))
	var air_v := v - wind
	var va := maxf(air_v.length(), 0.01)
	var lrw := basis.inverse() * (-air_v)                 # proudění vůči stroji (lokálně)
	var vf := maxf(lrw.z, 0.01)                          # dopředná složka proti vzduchu
	var alpha := atan2(lrw.y, vf)                        # náběh (rad)
	var a_crit := deg_to_rad(float(spec["a_crit"]))
	if not _stalled and alpha > a_crit:
		_stav_event(&"pretazeni")
	elif _stalled and alpha < a_crit * 0.75:
		_stav_event(&"zotaveni")
	var cl: float
	if _stalled:
		cl = (float(spec["CL0"]) + float(spec["CL_A"]) * a_crit) * CL_STALL * signf(alpha)
	else:
		cl = clampf(float(spec["CL0"]) + float(spec["CL_A"]) * alpha, NEG_A_CL, 3.0)
	cl *= _lift_scale()
	var q := 0.5 * RHO * va * va * float(spec["S"])
	var air_dir := air_v / va if va > 0.05 else -basis.z
	var up := basis.y
	var lift_dir := (up - air_dir * up.dot(air_dir))
	lift_dir = lift_dir.normalized() if lift_dir.length() > 0.01 else basis.y
	var f := lift_dir * q * cl - air_dir * q * _cd_of(cl)      # vztlak + odpor
	var t_norm := 0.0                                    # složka tahu kolmo k proudu (pro auto-trim)
	if fuel_l > 0.0:
		var t := _thrust(va)
		f += (-basis.z) * t                              # tah proti −Z (vpřed)
		t_norm = t * sin(alpha)
		_burn_fuel(dt)
	elif not _fuel_warned:
		_fuel_warned = true
		_notify("Došlo palivo – motor stojí. Klouž a hledej pole na přistání.", 4.0)
	var m := total_kg()
	var vdot := f.dot(air_dir) / m - G * air_dir.y       # podélné zrychlení vůči vzduchu (auto-trim)
	v += (f / m + Vector3(0, -G, 0)) * dt
	# orientace: bank ze steer, zatáčka z banku, pitch = dráha + auto-trim + výškovka
	_bank = move_toward(_bank, _bank_target(steer_in), ROLL_RATE * dt)
	var yaw_rate := G * tan(clampf(_bank, -1.2, 1.2)) / maxf(va, float(spec["v_min"]))
	_yaw += yaw_rate * dt
	air_v = v - wind
	var gamma := atan2(air_v.y, maxf(Vector3(air_v.x, 0, air_v.z).length(), 1.0))
	var pitch_tgt := gamma + _trim_alpha(air_v.length(), vdot, gamma, t_norm, elev_in) + elev_in * ELEV_PITCH
	if _stalled or va < float(spec["v_min"]):
		pitch_tgt = minf(pitch_tgt, gamma - 0.06)        # přetáčení: nos padá dolů
	_pitch = move_toward(_pitch, clampf(pitch_tgt, -0.9, 0.7), PITCH_RATE * dt)
	var new_basis := Basis.from_euler(Vector3(_pitch, _yaw, _bank))
	# dotyk země (A2-04 hystereze): pod gear_h − 5 cm, klesání vůči terénu, ≥ 0,5 s po odlepení;
	# jinak stroj nad terénem jen podržíme (terén nekoliduje – A2-07)
	var gy_rate := (_gh(pos.x + v.x * 0.1, pos.z + v.z * 0.1) - gy) / 0.1   # stoupání terénu pod dráhou (m/s)
	var rel_vy := v.y - gy_rate
	var floor_y := gy + float(spec["gear_h"]) - LAND_GAP
	if agl <= float(spec["gear_h"]) - LAND_GAP:
		if rel_vy < LAND_VY and _life_t - _air_t >= LAND_GRACE:
			_touchdown(pos, gy, v, -rel_vy)
			return
		pos.y = floor_y
		v.y = maxf(v.y, gy_rate)
	_xf = Transform3D(new_basis, pos)
	_v = v


## Dosednutí: měkké / tvrdé / havárie (paramotor: flare oběma brzdami → měkké doskočení).
## `impact` = rychlost klesání vůči terénu (m/s) – náraz do svahu se počítá jako tvrdý.
func _touchdown(pos: Vector3, gy: float, v: Vector3, impact: float) -> void:
	var hg := Vector3(v.x, 0, v.z)
	if impact > CRASH_LAND_VY:
		pos.y = gy + float(spec["gear_h"])
		_xf = Transform3D(Basis.from_euler(Vector3(_pitch, _yaw, _bank)), pos)
		_v = hg * 0.3
		_crash(pos, "Tvrdá havárie při přistání")
		return
	on_ground = true
	pos.y = gy + float(spec["gear_h"])
	speed = hg.length()
	_yaw = atan2(-hg.x, -hg.z) if speed > 0.5 else _yaw
	_pitch = 0.0
	_bank = 0.0
	var flared := _flare_ok()
	if impact > HARD_LAND_VY and not flared:
		dmg = minf(dmg + (impact - HARD_LAND_VY) * 12.0, 100.0)
		if body_state:
			body_state.hurt((impact - HARD_LAND_VY) * 8.0, "tvrdé přistání letounem")
		world.play_sfx(owner_id, "land", 0.7, 0.0)
		_notify("Tvrdé přistání (%.1f m/s) – podvozek dostal zabrat." % impact, 3.0)
	elif flared:
		_flare_land(impact)
	elif speed > 0.5:
		world.play_sfx(owner_id, "land", 1.0, -6.0)
	_xp_flush()
	_xf = Transform3D(Basis.from_euler(Vector3(0.0, _yaw, 0.0)), pos)
	_v = Vector3(-sin(_yaw), 0.0, -cos(_yaw)) * speed


# ------------------------------------------------------------------ háčky pro M6.4 paramotor

## Přídavný odpor (brzdy, „uši“) – základ 0.
func _extra_drag() -> float:
	return 0.0


## Valivý odpor na zemi (trike na trávě se rozjíždí déle – M6.5 přepisuje).
func _mu_ground() -> float:
	return MU_GRASS


## Hláška po vzletu (trike má jiné řízení hrazdou – M6.5 přepisuje).
func _takeoff_hint() -> String:
	return "Vzletl jsi – A/D překlápění, Mezerník/Ctrl trim, S uber plyn k přistání."


## Násobek vztlaku (křídlo na zemi = 0, částečně zavřené ~0,5) – základ 1.
func _lift_scale() -> float:
	return 1.0


## Bonus k v_max (povolené trimry) – základ 0.
func _v_max_bonus() -> float:
	return 0.0


## Cílový náklon pro daný řídicí vstup (paramotor přepisuje při zavření křídla).
func _bank_target(steer_in: float) -> float:
	return -steer_in * float(spec["roll_max"])


## Má se dosednutí počítat jako měkké i při vyšší sestupné rychlosti? (Paramotor: flare.)
func _flare_ok() -> bool:
	return false


## Měkké dosednutí po flaru (paramotor: na nohy, doběhne; základ nedělá nic).
func _flare_land(_impact: float) -> void:
	pass


func _burn_fuel(dt: float) -> void:
	if fuel_l <= 0.0:
		return
	fuel_l = maxf(fuel_l - throttle * float(spec["tank_l"]) / (float(spec["dojezd_min"]) * 60.0) * dt, 0.0)


func _xp_flush() -> void:
	if _xp_d > 1.0 and world:
		world.give_xp(owner_id, "letectvi", _xp_d * XP_PER_M, "let")
	_xp_d = 0.0


## Létání pod vlivem: svědek ~150 m (sdílíme droní svědectví), přestupek nejdřív po OFF_CD.
func _law_check(dt: float) -> void:
	_law_t += dt
	if _law_t < 3.0:
		return
	_law_t = 0.0
	if body_state == null or body_state.promile() < 0.01:
		return
	if on_ground:
		return
	if _life_t - float(_off_cd.get("letectvi_pod_vlivem", -1000.0)) < OFF_CD:
		return
	if not world.drone_witnessed(global_position, owner_id):
		return
	_off_cd["letectvi_pod_vlivem"] = _life_t
	world.commit_offense(owner_id, "letectvi_pod_vlivem",
		{"promile": body_state.promile(), "pos": global_position})


func _crash(pos: Vector3, why: String) -> void:
	if dmg >= 100.0:
		return
	dmg = 100.0
	if body_state:
		body_state.hurt(60.0, "havárie letounu")
	world.play_sfx(owner_id, "crash", 0.9, 0.0)
	_notify("%s – stroj je na odpis." % why, 5.0)
	world.emit_game_event(owner_id, "aircraft_crash", {"model": model, "pos": pos})
	on_ground = true
	_bank = 0.45                         # vrak leží nakloněný na boku
	_pitch = -0.1


## Náraz do překážky (strom, budova, prop, postava): nad práh = havárie, jinak jen šrám.
func _on_body(b: Node) -> void:
	var spd := linear_velocity.length()
	if dmg >= 100.0 or spd < 2.0:
		return
	if b and String(b.get_meta("surface", "")) == "teren":
		return                           # terén řeší analytické dosednutí (A2-07), ne „náraz“
	if spd >= CRASH_SPD:
		_crash(global_position, "Náraz do překážky (%s)" % (b.name if b else "?"))
	elif not on_ground:
		dmg = minf(dmg + spd * 2.0, 99.0)
		world.play_sfx(owner_id, "thud", 0.8, -4.0)


func _notify(t: String, dur: float) -> void:
	if world:
		world.notify(owner_id, "show_message", [t, dur])


## Telemetrie pro `FlightHud` (analogie `Drone.status`): {} znamená panel schovat.
func status() -> Dictionary:
	var pos := global_position
	var gy := _gh(pos.x, pos.z) if world else pos.y
	var wind := wind_at(pos)
	var air := linear_velocity - wind
	var warns := []
	if _stalled or (not on_ground and air.length() < float(spec["v_min"]) * 1.15):
		warns.append("PŘETÁŽENÍ – přidej plyn / uvolni")
	if _edge_warned:
		warns.append("HRANICE LETU – toč zpět nad katastr")
	if fuel_l <= 0.0:
		warns.append("PRAZDNÁ NÁDRŽ – klouzavý let")
	elif fuel_l < float(spec["tank_l"]) * 0.15:
		warns.append("MÁLO PALIVA")
	if dmg >= 100.0:
		warns.append("HAVÁRIE")
	var fwd := -global_transform.basis.z
	return {"model": String(spec.get("name", model)), "on_ground": on_ground,
		"alt": pos.y, "agl": pos.y - gy, "ias": air.length(),
		"gs": Vector3(linear_velocity.x, 0, linear_velocity.z).length(), "vs": linear_velocity.y,
		"fuel": fuel_l, "fuel_max": float(spec["tank_l"]), "thr": throttle,
		# geografický kurz – stejná konvence jako Hud._compass_text (north − yaw)
		"hdg": fposmod(world.weather.north_deg - rad_to_deg(atan2(-fwd.x, -fwd.z)), 360.0) if world.weather else 0.0,
		"wind": {"dir": fposmod(world.weather.wind_bearing + 180.0, 360.0), "ms": world.weather.wind} if world.weather else {"dir": 0.0, "ms": 0.0},
		"stall": _stalled, "dmg": dmg, "warns": warns, "xp_d": _xp_d}


## Uložení: pozice, yaw, palivo, poškození (vzor droního „world“ záznamu; let ve vzduchu
## se ukládá jako přistání pod sebou – stejně jako Drone.save_dict).
func save_dict() -> Dictionary:
	var pos := global_position
	if not on_ground and world:
		pos.y = _gh(pos.x, pos.z) + float(spec["gear_h"])
	return {"model": model, "pos": [pos.x, pos.y, pos.z], "yaw": _yaw, "fuel": fuel_l, "dmg": dmg}


func _process(delta: float) -> void:
	# interpolovaný vizuál + vrtule + kamera + zvuk motoru
	var f := Engine.get_physics_interpolation_fraction()
	vis.global_transform = _vis_xf(_prev_xf.interpolate_with(_cur_xf, f))
	if _prop:
		_prop.rotate_z(delta * (8.0 + throttle * 40.0))
	if snd:
		if pilot != null and fuel_l > 0.0 and throttle > 0.02:
			if not snd.playing:
				snd.play()
			snd.pitch_scale = ENGINE_BASE_PITCH + throttle * 0.9
			snd.volume_db = -20.0 + throttle * 10.0
		elif snd.playing:
			snd.stop()
	if pilot != null and _cam:
		_update_camera(delta)


## Vodorovný směr nosu (yaw) – kamera ho bere jako v autě: bez náklonu a klopení těla.
func _nose_yaw() -> float:
	var fwd := -vis.global_transform.basis.z
	return atan2(-fwd.x, -fwd.z)


## Kamera jako v autě (Car._update_camera): chase = za strojem, vyhlazená pozice, dívá se na obzor;
## kabina = oči pilota, jen yaw. Rig se natáčí přes look_at / basis, `_cam` zůstává v identitě
## (dřív se lokální rotace kamery nevynulovala a po přepnutí pohled „rozhodil“).
func _update_camera(delta: float) -> void:
	if pilot_input:
		var rel := pilot_input.take_look()
		_cam_yaw = clampf(_cam_yaw - rel.x * 0.004, -1.4, 1.4)
		_cam_yaw = lerpf(_cam_yaw, 0.0, minf(delta * 0.6, 1.0))        # volný pohled se vrací
		if pilot_input.take_toggle_view():
			cam_mode = (cam_mode + 1) % 2
	var xf := vis.global_transform
	var yaw := _nose_yaw() + _cam_yaw
	_cam.transform = Transform3D.IDENTITY
	if cam_mode == 0:
		var want := xf.origin + Vector3(0, CAM_UP, 0) + Basis(Vector3.UP, yaw) * Vector3(0, 0, CAM_DIST)
		_cam_pos = _cam_pos.lerp(want, 1.0 - exp(-8.0 * delta))
		_cam_rig.global_position = _cam_pos
		_cam_rig.look_at(xf.origin + Vector3(0, 1.4, 0) + Basis(Vector3.UP, yaw) * Vector3(0, 0, -2.0), Vector3.UP)
	else:
		_cam_pos = xf * eye_pos                                       # oči pilota (vis: y = 0 zem)
		_cam_rig.global_transform = Transform3D(Basis(Vector3.UP, yaw), _cam_pos)
	# opilý pilot: kamera se vlní (vzor Car)
	if body_state:
		var d := body_state.drunk_level()
		if d > 0.05:
			_cam.rotation.z += sin(_life_t * 1.7) * d * 0.02
			_cam.rotation.x += sin(_life_t * 1.3) * d * 0.015
