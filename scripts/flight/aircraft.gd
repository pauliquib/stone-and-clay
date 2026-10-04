## Společný letový model ultralehkých letadel (M6.3) – arcade-realistický:
## vztlak a odpor z CL(α) / CD0 + indukovaný odpor, tah motoru podle plynu a rychlosti,
## vítr `Weather.wind_vector()` s výškovým profilem v(h)=v10·(h/10)^0,14 a turbulence
## (bouřka, les, závětrná strana kopce), termika `Thermals`, hranice letu `World.flight_bounds`.
## Ovládání: W/S plyn, A/D překlopení→zatáčení, Mezerník zatáhnout / na zemi brzda,
## Ctrl přiklonit, V kamera, F nastoupit/vystoupit (jen na zemi). Auto-trim druh rychlost.
## Pojízdní podvozek, rozjezd, přistání, tvrdé přistání nad 3 m/s, havárie o překážku.
## Stroje jsou data v `SPECS` (paraglidové parametry – M6.4 naváže, rogalo M6.5).
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
const CAM_UP := 1.8                # chase kamera – výška nad strojem (m)
const ENGINE_BASE_PITCH := 0.7

## Katalog strojů: hodnoty „létající bedna“ = lehký motorový paraglide (tříkolka + padák).
## klíče: name, kg (prázdný), S (m²), AR (poměr stran), e, CL0, CL_A (1/rad), a_crit (°),
## CD0, thrust (N), v_min / v_trim / v_max (m/s), tank_l, dojezd_min (plný plyn), gear_h,
## roll_max (rad), glide (klouzavost 1:x – jen pro kontrolu / HUD hint)
const SPECS := {
	"test_letoun": {"name": "Testovací letoun „Létající bedna“", "kg": 62.0, "S": 25.0, "AR": 3.0,
		"e": 0.85, "CL0": 0.35, "CL_A": 2.8, "a_crit": 16.0, "CD0": 0.13, "thrust": 760.0,
		"v_min": 7.0, "v_trim": 11.0, "v_max": 16.0, "tank_l": 12.0, "dojezd_min": 30.0,
		"gear_h": 0.55, "roll_max": 0.55, "glide": 9.0},
	# M6.4: motorový paraglide (třída `Paramotor`) – padákové křídlo ~24 m², motor na zádech,
	# trim ~38 km/h, min ~25 km/h, max ~50 km/h s trimry, klouzavost ~7, spotřeba ~3,8 l/h.
	"paramotor": {"name": "Paramotor „Vlaštovka 24“", "kg": 28.0, "S": 24.0, "AR": 3.1,
		"e": 0.8, "CL0": 0.55, "CL_A": 3.0, "a_crit": 18.0, "CD0": 0.16, "thrust": 650.0,
		"v_min": 7.0, "v_trim": 10.5, "v_max": 14.0, "tank_l": 11.0, "dojezd_min": 175.0,
		"gear_h": 0.9, "roll_max": 0.7, "glide": 7.0},
	# M6.5: motorové rogalo (třída `Trike`) – tříkolka s rogalovým křídlem ~15 m²,
	# cestovní ~90 km/h, pádová ~55 km/h, max ~130 km/h, tah ~1 800 N, nádrž 50 l
	# (~14 l/h → dojezd ~210 min), prázdná ~200 kg, MTOW ~450 kg, 2 sedadla za sebou.
	"trike": {"name": "Motorové rogalo „Vlaštovka T-60“", "kg": 200.0, "S": 15.0, "AR": 6.7,
		"e": 0.7, "CL0": 0.4, "CL_A": 3.4, "a_crit": 15.0, "CD0": 0.07, "thrust": 1800.0,
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
var seat_pos := Vector3(0.0, 0.55, -0.15)

var fuel_l := 0.0                  # zbývá paliva (l)
var dmg := 0.0                     # poškození 0..100
var throttle := 0.0                # vyhlazený plyn 0..1
var on_ground := true
var speed := 0.0                   # pozemní rychlost při pojíždění / celková rychlost stroje (m/s)

var _yaw := 0.0
var _pitch := 0.0
var _bank := 0.0
var _stalled := false
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

var vis: Node3D
var _cam_rig: Node3D
var _cam: Camera3D
var cam_mode := 0                  # 0 = chase, 1 = pilot (FPP)
var _cam_yaw := 0.0                # volný pohled myší (chase, drift zpět)
var _cam_pos := Vector3.ZERO       # vyhlazená pozice chase kamery
var snd: AudioStreamPlayer3D
var _prop: MeshInstance3D


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
	gravity_scale = 0.0                    # gravitaci počítáme sami (G = 9,81 ≠ default 20)
	continuous_cd = true                   # Jolt: CCD – letoun v rychlosti neprostřelí terén
	angular_damp = 0.5                     # Jolt má jiné defaulty tlumení než Godot Physics
	linear_damp = 0.1
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(1.8, 1.6, 3.0)
	cs.position = Vector3(0, 0.8, 0)
	cs.shape = bx
	add_child(cs)
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


## Procedurální „létající bedna“: tříkolká bedna + bedňová křídla (padák zjednodušen),
## vrtule za pilotem, 3 kolečka. Pohled vpřed = −Z.
func _build_mesh() -> void:
	var mk := MeshKit.new()
	var frame := Color(0.35, 0.35, 0.38)
	var cloth := Color(0.85, 0.45, 0.15)
	mk.box(Vector3(0, 0.55, 0), Vector3(0.9, 0.5, 1.9), frame)                    # loď/bedna
	mk.box(Vector3(0, 0.62, -0.55), Vector3(0.5, 0.3, 0.6), Color(0.2, 0.2, 0.22)) # sedačka
	mk.box(Vector3(0, 2.6, 0), Vector3(7.2, 0.08, 1.5), cloth)                     # vrchní plocha (padák)
	mk.box(Vector3(-2.2, 2.0, 0), Vector3(0.06, 1.3, 0.06), frame)                 # vzpery
	mk.box(Vector3(2.2, 2.0, 0), Vector3(0.06, 1.3, 0.06), frame)
	mk.box(Vector3(0, 1.6, 0.95), Vector3(0.07, 2.0, 0.07), frame)                 # stožár k motoru
	mk.cylinder(Vector3(0, 1.3, 1.15), 0.55, 0.55, 0.05, Color(0.15, 0.15, 0.15), Vector3(PI * 0.5, 0, 0), 20) # kruh vrtule
	for wp in [Vector3(-0.5, 0.18, -0.6), Vector3(0.5, 0.18, -0.6), Vector3(0, 0.18, 0.9)]:
		mk.cylinder(wp, 0.18, 0.18, 0.12, Color(0.12, 0.12, 0.12), Vector3(0, 0, PI * 0.5), 10)
	var mi := MeshInstance3D.new()
	mi.mesh = mk.commit(MeshKit.vc_material(0.75))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	vis.add_child(mi)
	_prop = MeshInstance3D.new()           # list vrtule (točí se kolem Z)
	var pmk := MeshKit.new()
	pmk.box(Vector3.ZERO, Vector3(0.06, 1.1, 0.03), Color(0.1, 0.1, 0.1))
	pmk.box(Vector3.ZERO, Vector3(1.1, 0.06, 0.03), Color(0.1, 0.1, 0.1))
	_prop.mesh = pmk.commit(MeshKit.vc_material(0.6))
	_prop.position = Vector3(0, 1.3, 1.28)
	vis.add_child(_prop)


## Zaparkovat na místo (spawn / načtení save).
func park(pos: Vector3, face_yaw: float) -> void:
	on_ground = true
	freeze = true
	_yaw = face_yaw
	_pitch = 0.0
	_bank = 0.0
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = Transform3D(Basis(Vector3.UP, face_yaw), pos)
	_prev_xf = global_transform
	_cur_xf = global_transform
	vis.global_transform = global_transform


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
		_cam_pos = global_transform * Vector3(0, CAM_UP, CAM_DIST)
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
		var gy := world.terrain.height_at(pos.x, pos.z) if world.terrain else pos.y
		var agl := maxf(pos.y - gy, 1.0)
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
			var h_up := world.terrain.height_at(pos.x - w2.x * 60.0, pos.z - w2.y * 60.0)
			var h_here := world.terrain.height_at(pos.x, pos.z)
			var gy := world.terrain.height_at(pos.x, pos.z)
			if pos.y - gy < 200.0:                       # závětří působí jen nízko
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


func _physics_process(dt: float) -> void:
	_life_t += dt
	if pilot == null or world == null:
		return                                                    # bez pilota zamrzlý (park)
	if dmg >= 100.0:                                            # havárie – jen klesá a kutálí se
		linear_velocity += Vector3(0, -G, 0) * dt
		_prev_xf = _cur_xf
		_cur_xf = global_transform
		return
	var xf := global_transform
	var pos := xf.origin
	var gy: float = world.terrain.height_at(pos.x, pos.z) if world.terrain else pos.y
	var agl: float = pos.y - gy
	var v: Vector3 = linear_velocity
	var inp := _delayed_input(dt)
	var thr_in: float = inp[0]
	var steer_in: float = inp[1]
	var elev_in: float = inp[2]
	throttle = lerpf(throttle, thr_in, minf(dt * 4.0, 1.0))
	var wind := wind_at(pos) + _turbulence(pos)

	if on_ground:
		_on_ground(xf, gy, steer_in, elev_in, dt)
	else:
		_in_air(xf, wind, v, agl, gy, steer_in, elev_in, dt)

	# hranice letu (M6.2): přetáčivý protivítr / strop 1500 m AGL
	var fb: Dictionary = world.flight_bounds(global_transform.origin)
	linear_velocity += (fb["push"] as Vector3) * dt
	_edge_warned = bool(fb["warn"])
	_law_check(dt)
	# XP za nalétané metry (zapíše se při dosednutí / vystoupení)
	if not on_ground:
		_xp_d += Vector3(v.x, 0, v.z).length() * dt
	_prev_xf = _cur_xf
	_cur_xf = global_transform
	speed = linear_velocity.length()


## Pojíždění po zemi: tah–valivý odpor, řízení kolem svislé osy, terén kopíruje profil,
## vzlet sám při v_min (vztlak překročí váhu), posadka ze vzduchu řeší _in_air → dotyk.
func _on_ground(xf: Transform3D, gy: float,
		steer_in: float, elev_in: float, dt: float) -> void:
	var pos := xf.origin
	var fwd := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	# sklon terénu ve směru jízdy (rozjízdní / klesání svahu)
	var h_a := world.terrain.height_at(pos.x + fwd.x * 2.0, pos.z + fwd.z * 2.0)
	var h_b := world.terrain.height_at(pos.x - fwd.x * 2.0, pos.z - fwd.z * 2.0)
	var slope := (h_a - h_b) / 4.0
	var v_ground := maxf(speed, 0.0)
	var t := float(spec["thrust"]) * throttle * (1.0 - 0.4 * clampf(v_ground / float(spec["v_max"]), 0.0, 1.0))
	var m := total_kg()
	var mu := _mu_ground() * (1.3 if world.weather and world.weather.surface_grip("teren") < 0.9 else 1.0)
	var a := t / m - mu * G - G * slope * 0.5
	if elev_in > 0.0:                                            # Mezerník na zemi = brzda
		a -= BRAKE_DECEL
	v_ground = maxf(v_ground + a * dt, 0.0)
	_yaw -= steer_in * GROUND_STEER * clampf(v_ground / 6.0, 0.0, 1.0) * dt
	_bank = lerpf(_bank, -steer_in * 0.05, minf(dt * 3.0, 1.0))
	var pitch_tgt := atan(clampf(slope, -0.4, 0.4))
	if v_ground >= float(spec["v_min"]) * 0.9:
		pitch_tgt = 0.12                                           # rotace na vzlet
	_pitch = lerpf(_pitch, pitch_tgt, minf(dt * 4.0, 1.0))
	pos.y = gy + float(spec["gear_h"])
	var new_basis := Basis.from_euler(Vector3(_pitch, _yaw, _bank))
	global_transform = Transform3D(new_basis, pos)
	linear_velocity = new_basis * Vector3(0, 0, -v_ground)
	speed = v_ground
	_burn_fuel(dt)
	# vzlet: vztlak převáží
	var rw := wind_at(pos) - linear_velocity
	var lrw := new_basis.inverse() * rw
	var va := maxf(lrw.length(), 0.01)
	var cl := float(spec["CL0"]) + float(spec["CL_A"]) * atan2(lrw.y, maxf(lrw.z, 0.01))
	if 0.5 * RHO * va * va * float(spec["S"]) * cl > m * G and v_ground >= float(spec["v_min"]) * 0.95:
		on_ground = false
		_pitch = 0.14
		_notify(_takeoff_hint(), 4.0)


## Ve vzduchu: aerodynamika (CL(α) s přetáčením, CD0 + CL²/(π·AR·e)), tah, gravitace;
## orientaci držíme sami – bank ze steer → zatáčka g·tan(φ)/v, pitch auto-trim na γ+α_trim.
func _in_air(xf: Transform3D, wind: Vector3, v: Vector3,
		agl: float, gy: float, steer_in: float, elev_in: float, dt: float) -> void:
	var pos := xf.origin
	var basis := Basis.from_euler(Vector3(_pitch, _yaw, _bank))
	var rw := wind - v                                   # proudění vůči stroji
	var lrw := basis.inverse() * rw
	var va := maxf(lrw.length(), 0.01)
	var vf := maxf(lrw.z, 0.01)                          # dopředná složka proti vzduchu
	var alpha := atan2(lrw.y, vf)                        # náběh (rad)
	var a_crit := deg_to_rad(float(spec["a_crit"]))
	if not _stalled and alpha > a_crit:
		_stalled = true
	elif _stalled and alpha < a_crit * 0.75:
		_stalled = false
	var cl: float
	if _stalled:
		cl = (float(spec["CL0"]) + float(spec["CL_A"]) * a_crit) * CL_STALL * signf(alpha)
	else:
		cl = clampf(float(spec["CL0"]) + float(spec["CL_A"]) * alpha, NEG_A_CL, 3.0)
	var cd := float(spec["CD0"]) + cl * cl / (PI * float(spec["AR"]) * float(spec["e"])) + _extra_drag()
	var q := 0.5 * RHO * va * va * float(spec["S"])
	var air_dir := (v - wind).normalized() if (v - wind).length() > 0.01 else -basis.z
	var up := basis.y
	var lift_dir := (up - air_dir * up.dot(air_dir))
	lift_dir = lift_dir.normalized() if lift_dir.length() > 0.01 else basis.y
	var f := lift_dir * q * cl * _lift_scale() - air_dir * q * cd        # vztlak + odpor
	var t := 0.0
	if fuel_l > 0.0:
		t = float(spec["thrust"]) * throttle * clampf(1.0 - vf / (float(spec["v_max"]) + _v_max_bonus()), 0.15, 1.0)
		f += (-basis.z) * t                              # tah proti −Z (vpřed)
		_burn_fuel(dt)
	elif not _fuel_warned:
		_fuel_warned = true
		_notify("Došlo palivo – motor stojí. Klouž a hledej pole na přistání.", 4.0)
	var m := total_kg()
	v += (f / m + Vector3(0, -G, 0)) * dt
	# orientace: bank ze steer, zatáčka z banku, pitch = dráha + trim + výškovka
	_bank = move_toward(_bank, _bank_target(steer_in), ROLL_RATE * dt)
	var yaw_rate := G * tan(clampf(_bank, -1.2, 1.2)) / maxf(vf, float(spec["v_min"]))
	_yaw += yaw_rate * dt
	var air_v := v - wind
	var gamma := atan2(air_v.y, maxf(Vector3(air_v.x, 0, air_v.z).length(), 1.0))
	var pitch_tgt := gamma + deg_to_rad(4.0) + elev_in * 0.18
	if _stalled or vf < float(spec["v_min"]):
		pitch_tgt = minf(pitch_tgt, gamma - 0.06)        # přetáčení: nos padá dolů
	_pitch = move_toward(_pitch, clampf(pitch_tgt, -0.9, 0.7), PITCH_RATE * dt)
	var new_basis := Basis.from_euler(Vector3(_pitch, _yaw, _bank))
	# dotyk země: měkké / tvrdé / havárie (paramotor: flare oběma brzdami → měkké doskočení)
	if agl <= float(spec["gear_h"]) and v.y <= 1.0:
		var impact := -v.y
		if impact > CRASH_LAND_VY:
			_crash(pos, "Tvrdá havárie při přistání")
			return
		on_ground = true
		pos.y = gy + float(spec["gear_h"])
		var hg := Vector3(v.x, 0, v.z)
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
		v = Vector3(hg.x, 0.0, hg.z)
	global_transform = Transform3D(new_basis, pos)
	linear_velocity = v


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


## Náraz do překážky (strom, budova, prop, postava): nad práh = havárie, jinak jen šrám.
func _on_body(b: Node) -> void:
	var spd := linear_velocity.length()
	if dmg >= 100.0 or spd < 2.0:
		return
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
	var gy := world.terrain.height_at(pos.x, pos.z) if world and world.terrain else pos.y
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
	if not on_ground and world and world.terrain:
		pos.y = world.terrain.height_at(pos.x, pos.z) + float(spec["gear_h"])
	return {"model": model, "pos": [pos.x, pos.y, pos.z], "yaw": _yaw, "fuel": fuel_l, "dmg": dmg}


func _process(delta: float) -> void:
	# interpolovaný vizuál + vrtule + kamera + zvuk motoru
	var f := Engine.get_physics_interpolation_fraction()
	vis.global_transform = _prev_xf.interpolate_with(_cur_xf, f)
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
		_cam_rig.look_at(xf.origin + Vector3(0, 0.8, 0) + Basis(Vector3.UP, yaw) * Vector3(0, 0, -2.0), Vector3.UP)
	else:
		_cam_pos = xf * Vector3(0, 1.15, -0.4)
		_cam_rig.global_transform = Transform3D(Basis(Vector3.UP, yaw), _cam_pos)
	# opilý pilot: kamera se vlní (vzor Car)
	if body_state:
		var d := body_state.drunk_level()
		if d > 0.05:
			_cam.rotation.z += sin(_life_t * 1.7) * d * 0.02
			_cam.rotation.x += sin(_life_t * 1.3) * d * 0.015
