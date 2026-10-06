## Dron (M6.1): RigidBody3D – v letu simulace „rychlostního serva“ (custom_integrator: vrtule drží výšku,
## příkaz letu = cílová rychlost, vítr strhuje), při pádu / v zaparkovaném stavu standardní fyzika.
##
## Autorita světa: stav dronu vlastní `World.drones[pid]`, pilot čte `pilot.input` (InputState – plní ho
## LocalClient, v MP přijde po síti). Kamera a OSD existují jen u lokálního pilota (`pilot.camera`).
##
## Režimy (`mode`): "zemi" zaparkovaný · "start" automatický vzlet na 2 m · "let" pilot · "rth" návrat domů
## · "pristat" řízené klesání · "spadl" volný pád (normální fyzika) · "strom" uvízl v koruně (po chvíli spadne).
##
## Ovládání (jako chůze): WASD let vpřed/strany, myš = otáčení dronu + naklápění kamery, Mezerník stoupat,
## Ctrl klesat, Shift sportovní režim, V kamera z dronu / za dronem, F přistát / návrat, O nebo LMB fotka.
##
## Práva (ÚCL / EU 2019/947 – zjednodušená herní simulace): registrace provozovatele `dron_provozovatel`,
## A1/A3 `dron_a1a3` pro >250 g, max 120 m AGL, ne nad lidmi, VLOS 500 m, soukromí (30 m / 30 s nad cizím
## pozemkem). Přestupky jdou přes `World.commit_offense`, jen když drona někdo uvidí (`World.drone_witnessed`).
class_name Drone
extends RigidBody3D

const MAX_ALT := 120.0                 # nejvýš dovolená výška AGL (m) – přestupek + odepření stoupání
const TAKEOFF_H := 2.0                 # vzlet na tuto výšku (m nad bod startu)
const VLOS_M := 500.0                  # vizuální dohled – varování / po VLOS_OFF_S přestupek
const VLOS_OFF_S := 60.0               # jak dlouho mimo dohled = přestupek (s letu)
const PRIVACY_AGL := 30.0              # soukromí: pod touto výškou nad cizím pozemkem…
const PRIVACY_S := 30.0                # …déle než tolik sekund vrtění = přestupek
const PERSON_R := 25.0                 # „nad lidmi“ – vodorovná vzdálenost osoby pod dronem (m)
const CRASH_V := 4.0                   # náraz rychlejší než tolik = nehoda (m/s)
const BUMP_V := 1.6                    # menší ťuknutí = jen poškrábání + odraz
const CRASH_DMG := 55.0                # poškození (%), od kterého už dron nemůže vzlétnout (oprava)
const DMG_PER_V := 9.0                 # poškození za m/s nárazu
const STUCK_S := 6.0                   # jak dlouho visí dron ve stromu, než spadne
const BAT_WARN := 0.15                 # varování nízké baterie
const BAT_RTH := 0.05                  # automatický návrat při 5 %
const DRAIN_SPORT := 1.4               # sportovní režim = −40 % výdrže
const DRAIN_COLD := 1.43               # mráz (<0 °C) = −30 % výdrže
const ACCEL := 22.0                    # jak rychle dron mění rychlost (m/s²) – odezva vrtulí
const ACCEL_RTH := 10.0                # jemnější při návratu
const SCARE_S := 1.6                   # bzučení plaší zvěř každých tolik sekund
const LAW_S := 1.0                     # právní kontroly (výška, lidé, dohled, soukromí) za tolik s
const OFF_CD := 120.0                  # stejný přestupek se hlásí nejdřív po tolika s letu
const VIS_TURN := Basis(Vector3.UP, PI)   # model drona má nos na +Z, fyzika letí do −Z → vizuál otočit

var world: World
var pilot: Player                      # kdo právě ovládá (null = zaparkovaný / autonomní)
var owner_pid := 0
var model := "dron"
var spec: Dictionary
var mode := "zemi"
var home_pos := Vector3.ZERO           # bod vzletu – cíl návratu (RTH)
var home_ground := 0.0
var bat_s := 0.0                       # zbývá sekund letu (reálných)
var dmg := 0.0                         # poškození 0–100 %
var photo_t := 0                       # pořízené fotky za tento let
var sig := 1.0                         # síla signálu 0..1 (vzdálenost + překážky)
var sig_los := true                    # přímá viditelnost pilot–dron (signál dochází dál)

var _yaw := 0.0
var _cam_pitch := -0.15
var _cam_3rd := false                  # false = kamera dronu (FPV), true = kamera za dronem
var _hover_y := 0.0                    # cílová výška automatického vzletu
var _tilt := Vector2.ZERO              # vizuální náklon (pitch/roll podle rychlosti)
var _gust_t := 0.0
var _law_t := 0.0
var _sig_t := 0.0
var _scare_t := 0.0
var _stuck_t := 0.0
var _life_t := 0.0                     # čas od vzletu (časovače přestupků)
var _vlos_t := 0.0                     # jak dlouho letí mimo dohled
var _privacy_t := 0.0                  # jak dlouho vrtí nad cizím pozemkem
var _crowd_t := 0.0                    # jak dlouho visí nad lidmi
var _bat_warned := false
var _rth_reason := ""
var _off_cd := {}                      # id přestupku → čas posledního nahlášení
var _xp_d := 0.0                       # ujetá vzdálenost pro XP (Skills)
var _fly_push := Vector3.ZERO          # M6.2: „protivítr“ od hranice letu (World.flight_bounds)
var _fly_warn := false                 # M6.2: v pásmu varování „opouštíš oblast“

var vis: Node3D                        # vizuál s interpolací (top_level, jako Player.visual)
var cam: Camera3D                      # kamera dronu – jen lokální pilot (jako Car._cam)
var snd: AudioStreamPlayer3D
var pad: MeshInstance3D                # přistávací značka na místě vzletu
var _rotors: Array[Node3D] = []
var _led: MeshInstance3D
var _spin := 0.0
var _prev_pos := Vector3.ZERO
var _cur_pos := Vector3.ZERO
var _prev_yaw := 0.0
var _cur_yaw := 0.0


## Postaví dron (fyzika, vizuál, zvuk). Volá `World.drone_launch` / `drone_spawn_world`.
func setup(w: World, pid: int, model_id: String) -> void:
	world = w
	owner_pid = pid
	model = model_id
	spec = DroneModel.spec(model)
	bat_s = float(spec["batt"])
	mass = maxf(float(spec["kg"]), 0.15)
	collision_layer = 8                # fyzikální objekty (jako prop) – auta i postavy ho registrují
	collision_mask = 1 | 2 | 4 | 8 | 16
	contact_monitor = true
	max_contacts_reported = 4
	can_sleep = false
	custom_integrator = true           # v letu řídíme rychlost sami (bez gravitace)
	gravity_scale = 0.0
	var s: float = spec["size"]
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(s * 2.2, s * 0.8, s * 2.2)
	cs.shape = bx
	add_child(cs)
	body_entered.connect(_on_body)
	# vizuál (interpolovaný mimo fyzikální transform – jako Player.visual)
	vis = Node3D.new()
	vis.top_level = true
	add_child(vis)
	var mi := MeshInstance3D.new()
	mi.mesh = DroneModel.body_mesh(model)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	vis.add_child(mi)
	for off in DroneModel.rotor_offsets(model):
		var r := MeshInstance3D.new()
		r.mesh = DroneModel.rotor_mesh(model)
		r.position = off
		vis.add_child(r)
		_rotors.append(r)
	_led = MeshInstance3D.new()
	_led.mesh = DroneModel.led_mesh(model)
	vis.add_child(_led)
	pad = MeshInstance3D.new()
	pad.mesh = DroneModel.pad_mesh(model)
	pad.top_level = true
	pad.visible = false
	add_child(pad)
	snd = AudioStreamPlayer3D.new()
	snd.stream = Sfx.drone_loop()
	snd.unit_size = 8.0
	snd.max_distance = 60.0
	snd.volume_db = -14.0
	add_child(snd)
	_prev_pos = global_position
	_cur_pos = global_position


## Zaparkovat na `pos` (inventář → zem, načtení save). Režim "zemi", zamrznuté.
func park(pos: Vector3, face_yaw: float) -> void:
	mode = "zemi"
	freeze = true
	custom_integrator = true
	global_position = pos
	_yaw = face_yaw
	_prev_yaw = face_yaw
	_cur_yaw = face_yaw
	_prev_pos = pos
	_cur_pos = pos
	rotation = Vector3(0, face_yaw, 0)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	pad.visible = false
	vis.global_transform = Transform3D(Basis(Vector3.UP, face_yaw) * VIS_TURN, pos)


## Vzlet (volá `World.drone_launch`): připoutá pilota, kameru, start na TAKEOFF_H.
func take_off(p: Player) -> void:
	pilot = p
	p.drone = self
	add_collision_exception_with(p)
	custom_integrator = true          # po opravě a novém vzletu zase „servo“ (po havárii byla normální fyzika)
	gravity_scale = 0.0
	_yaw = p.yaw
	_prev_yaw = _yaw
	_cur_yaw = _yaw
	_cam_pitch = -0.15
	home_pos = global_position
	home_ground = world.terrain.height_at(home_pos.x, home_pos.z) if world.terrain else home_pos.y - 0.1
	_hover_y = home_ground + TAKEOFF_H
	pad.global_position = Vector3(home_pos.x, home_ground + 0.03, home_pos.z)
	pad.visible = true
	p.controls_locked = true
	p.velocity = Vector3.ZERO
	if p.visual:
		p.visual.hold(DroneModel.remote())
	if p.camera != null:
		# lokální pilot: kamera dronu (vzor Car.set_player_driver – uvolní se v release())
		cam = Camera3D.new()
		cam.fov = 72.0
		cam.near = 0.05
		cam.far = 9000.0
		vis.add_child(cam)
		cam.position = Vector3(0, -spec["size"] * 0.4, spec["size"] * 0.6)
		cam.rotation = Vector3(0, PI, 0)      # FPV: dívat se k nosu (+Z modelu)
		cam.current = true
	mode = "start"
	freeze = false
	_life_t = 0.0
	_vlos_t = 0.0
	_privacy_t = 0.0
	_crowd_t = 0.0
	_bat_warned = false
	_off_cd = {}
	snd.play()


## Pilot odpoután (přistání, pád, uložení, odpojení): kamera a ovládání zpět hráči, dron zůstane ve světě.
func release() -> void:
	if pilot:
		if pilot.drone == self:
			pilot.drone = null
		pilot.controls_locked = false
		pilot.input.clear()          # zahodit nasčítaný pohled, ať po přistání hráč necukne kamerou
		if pilot.visual:
			pilot.visual.hold(null)
		remove_collision_exception_with(pilot)
	pilot = null
	if cam:
		cam.queue_free()
		cam = null
	if snd.playing:
		snd.stop()


## Je dron ve vzduchu (motory jedou)?
func flying() -> bool:
	return mode in ["start", "let", "rth", "pristat"]


func agl() -> float:
	var g := world.terrain.height_at(global_position.x, global_position.z) if world.terrain else global_position.y
	return global_position.y - g


func bat_frac() -> float:
	return clampf(bat_s / float(spec["batt"]), 0.0, 1.0)


func pilot_dist() -> float:
	return global_position.distance_to(pilot.global_position) if pilot else 0.0


## F: poblíž pilota přistát, jinak návrat domů; v „rth“ = zrušit návrat.
func request_land() -> void:
	match mode:
		"let", "start":
			if pilot_dist() < 3.5:
				mode = "pristat"
				world.notify(owner_pid, "show_message", ["Dron přistává.", 1.5])
			else:
				_start_rth("ruční návrat")
		"rth":
			mode = "let"
			_rth_reason = ""
			world.notify(owner_pid, "show_message", ["Návrat zrušen – zase pilotuješ.", 2.0])
		"spadl", "strom", "zemi":
			pass


func _start_rth(reason: String) -> void:
	if mode == "rth":
		return
	mode = "rth"
	_rth_reason = reason
	world.notify(owner_pid, "show_message", ["Návrat domů: %s." % reason, 3.0])
	world.emit_game_event(owner_pid, "drone_rth", {"reason": reason})


# ------------------------------------------------------------------ fyzika

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var dt := state.step
	_prev_pos = _cur_pos
	_prev_yaw = _cur_yaw
	_cur_pos = state.transform.origin
	_cur_yaw = _yaw
	if not flying():
		return                        # zemi/spadl/strom: standardní fyzika (gravitační pád)
	_life_t += dt
	_read_sticks(dt)
	_drain(dt)
	var wish := _wish()
	var vel := state.linear_velocity
	vel = vel.move_toward(wish, (ACCEL_RTH if mode == "rth" else ACCEL) * dt)
	state.linear_velocity = vel
	state.angular_velocity = Vector3.ZERO
	state.transform = Transform3D(Basis(Vector3.UP, _yaw), _cur_pos)
	_sig_t -= dt
	if _sig_t <= 0.0:
		_sig_t = 0.4
		_signal_check()
		_bounds_check()
	_law_t -= dt
	if _law_t <= 0.0:
		_law_t = LAW_S
		_legal_check()
	_scare_t -= dt
	if _scare_t <= 0.0:
		_scare_t = SCARE_S
		_scare_wildlife()


## Vstup pilota (myš, páčka ovladače, pohled); pohybové páčky čte `_wish`.
func _read_sticks(dt: float) -> void:
	if pilot == null:
		return
	var la := pilot.input.look_axis          # pravá páčka ovladače (hráčova je při letu uzamčená)
	if la.length() > 0.15:
		_yaw -= la.x * 2.6 * dt
		_cam_pitch = clampf(_cam_pitch - la.y * 1.8 * dt, -1.4, 0.9)
	var rel := pilot.input.take_look()
	var sens := pilot.mouse_sensitivity
	_yaw -= rel.x * sens
	_cam_pitch = clampf(_cam_pitch - rel.y * sens, -1.4, 0.9)
	var z := pilot.input.take_zoom()
	if z != 0.0 and cam:
		cam.fov = clampf(cam.fov + z * 6.0, 45.0, 100.0)
	if pilot.input.take_toggle_view():
		_cam_3rd = not _cam_3rd


## Cílová rychlost podle režimu (let / start / rth / pristat).
func _wish() -> Vector3:
	var wv := world.weather.wind_vector() if world.weather else Vector3.ZERO
	var wk: float = spec["wind_k"]
	_gust_t += 0.016
	var gust := wv * wk * 0.35 * (sin(_gust_t * 2.1) * sin(_gust_t * 0.63 + 1.7))   # turbulence kolem středního driftu
	match mode:
		"start":
			var up := clampf((_hover_y - global_position.y) * 2.5, 0.0, 2.2)
			if global_position.y >= _hover_y - 0.05:
				mode = "let"
				world.emit_game_event(owner_pid, "drone_launch", {"model": model})
				world.notify(owner_pid, "show_message", [
					"Dron nahoře – WASD let, myš natáčení, Mezerník/Ctrl výška, Shift sport, V pohled, F přistát, O foto", 6.0])
			return Vector3(wv.x * wk * 0.3, up, wv.z * wk * 0.3)
		"let":
			if pilot == null:
				return Vector3.ZERO
			var mv: Vector2 = pilot.input.move
			var dir := Basis(Vector3.UP, _yaw) * Vector3(mv.x, 0.0, mv.y)
			var top: float = spec["sport"] if pilot.input.sprint else spec["spd"]
			var wish := dir * top + wv * wk * 0.6 + gust
			var vz := 0.0
			if pilot.input.jump:
				vz += float(spec["climb"])
			if pilot.input.crouch:
				vz -= float(spec["climb"])
			if vz > 0.0 and agl() >= MAX_ALT:
				vz = 0.0
			wish.y = vz - dmg * 0.004            # poškozený dron lehce klesá
			return wish + _fly_push              # M6.2: protivítr od hranice letu / dolů od stropu
		"rth":
			var to := Vector3(home_pos.x - global_position.x, 0, home_pos.z - global_position.z)
			var hd := to.length()
			var wish2 := Vector3.ZERO
			if hd > 3.0:
				var cruise := home_ground + 22.0
				wish2 = to.normalized() * minf(float(spec["spd"]) * 0.7, hd * 0.5 + 1.0)
				wish2.y = clampf((cruise - global_position.y) * 0.8, -1.5, float(spec["climb"]) * 0.8)
			else:
				wish2.y = -2.0
			if hd < 3.0 and agl() < 0.22:
				_land()
				return Vector3.ZERO
			return wish2 + wv * wk * 0.5
		"pristat":
			if agl() < 0.22:
				_land()
				return Vector3.ZERO
			return Vector3(0, -clampf(agl() * 0.9, 0.9, 5.0), 0) + wv * wk * 0.25   # rychlost klesání podle výšky (rychle nahoře, jemně u země)
	return Vector3.ZERO


## Dosednutí (start pristat i RTH): zaparkovat; pilot blízko → rovnou do inventáře.
func _land() -> void:
	mode = "zemi"
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	var gy := world.terrain.height_at(global_position.x, global_position.z) if world.terrain else global_position.y
	global_position.y = maxf(global_position.y, gy + spec["size"] * 0.65)   # na střeše/autě zůstane nahoře
	_cur_pos = global_position
	_prev_pos = global_position
	pad.visible = false
	world.emit_game_event(owner_pid, "drone_land", {})
	_flush_xp()
	if pilot and pilot.global_position.distance_to(global_position) < 2.5:
		world.drone_pickup(owner_pid)
	else:
		release()
		world.notify(owner_pid, "show_message", ["Dron přistál – seber ho (E).", 3.0])


## XP do letectví za uletěnou vzdálenost – připíše se při dosednutí / havárii / sebrání.
func _flush_xp() -> void:
	if _xp_d <= 0.5 or world == null:
		return
	world.give_xp(owner_pid, "letectvi", _xp_d * 0.04, "let dronem")
	_xp_d = 0.0


## Baterie: spotřeba podle režimu, varování 15 %, návrat 5 %, pád 0 %.
func _drain(dt: float) -> void:
	var k := 1.0
	if mode == "let" and pilot and pilot.input.sprint:
		k *= DRAIN_SPORT
	if world.weather and world.weather.temp < 0.0:
		k *= DRAIN_COLD
	bat_s -= dt * k
	var f := bat_frac()
	if f <= BAT_WARN and not _bat_warned:
		_bat_warned = true
		world.notify(owner_pid, "police_banner", ["Dron: baterie %d %%!" % roundi(f * 100.0), 3.0])
		world.play_sfx(owner_pid, "fail", 1.4, -8.0)
	if f <= BAT_RTH and mode == "let":
		_start_rth("baterie %d %%" % roundi(f * 100.0))
	if bat_s <= 0.0:
		bat_s = 0.0
		_crash("vybitá baterie")


## Signál: dosah zkrácený za překážkou (raycast mezi pilotem a dronem), ztráta → návrat.
func _signal_check() -> void:
	if pilot == null:
		sig = 0.0
		return
	var eye := pilot.global_position + Vector3(0, 1.55, 0)
	sig_los = world.line_clear(eye, global_position) if world else true
	var rng: float = spec["range"] if sig_los else spec["range_nlos"]
	sig = clampf(1.0 - pilot_dist() / rng, 0.0, 1.0)
	if sig <= 0.0 and mode == "let":
		_start_rth("ztráta signálu")


## Letové hranice (M6.2, `World.flight_bounds`): v pásmu před hranicí varování + protivítr
## (_fly_push se přičte k cílové rychlosti v `_wish`), za hranicí (katastr + World.FLY_LIMIT_M)
## návrat domů jako u ztráty signálu. Strop World.FLY_CEIL_AGL tlačí dron dolů přes _fly_push.y.
func _bounds_check() -> void:
	if world == null:
		return
	var fb: Dictionary = world.flight_bounds(global_position)
	_fly_push = fb["push"]
	var w := bool(fb["warn"]) and mode == "let"
	if w and not _fly_warn:
		world.notify(owner_pid, "police_banner", ["Dál už nelétej – opouštíš oblast!", 3.0])
	_fly_warn = w
	if not bool(fb["ok"]) and mode == "let":
		_start_rth("hranice letu")


# ------------------------------------------------------------------ právo a okolí

## Pravidelná kontrola přestupků (každou LAW_S): 120 m AGL, lidé pod dronem, VLOS, soukromí,
## registrace a kvalifikace podle modelu. Přestupek jen se svědkem (dron uvidí i slyší ~150 m).
func _legal_check() -> void:
	if pilot == null or mode not in ["let", "rth"]:
		return
	var a := agl()
	if a > MAX_ALT + 1.0:
		_offense("dron_vyska_120", {"vyska": roundi(a)})
	# dohled (vlastní oko)
	if pilot_dist() > VLOS_M or not sig_los:
		_vlos_t += LAW_S
		if _vlos_t > VLOS_OFF_S:
			_offense("dron_mimo_dohled", {})
	else:
		_vlos_t = 0.0
	# lidé pod dronem (v obci rychle odhalí policie i sousedi)
	if world.drone_person_under(global_position, PERSON_R):
		_crowd_t += LAW_S
		if _crowd_t > 2.0:
			_offense("dron_nad_lidmi", {})
	else:
		_crowd_t = 0.0
	# registrace a kvalifikace (jen v zástavbě to reálně kontrolují)
	var settled: float = world.fauna.settle_at(global_position.x, global_position.z) if world.fauna else 0.0
	if settled > 0.4:
		if not world.has_permit(owner_pid, "dron_provozovatel", global_position):
			_offense("dron_bez_registrace", {})
		if bool(spec["needs_a1a3"]) and not world.has_permit(owner_pid, "dron_a1a3", global_position):
			_offense("dron_bez_kvalifikace", {})
	# soukromí: vrtění nízko nad cizím zastavěným pozemkem
	if settled > 0.4 and a < PRIVACY_AGL and world.forestry and world.forestry.zone_at(global_position, owner_pid) == "settled" \
			and Vector2(linear_velocity.x, linear_velocity.z).length() < 2.0:
		_privacy_t += LAW_S
		if _privacy_t > PRIVACY_S:
			_offense("narusovani_soukromi_dron", {})
	else:
		_privacy_t = 0.0
	# XP do letectví za uletěnou vzdálenost (Skills dává řízení obdobně)
	_xp_d += Vector2(linear_velocity.x, linear_velocity.z).length() * LAW_S


## Přestupek jen když ho někdo uvidí (svědek do ~150 m – dron je slyšet i vidět).
func _offense(off_id: String, data: Dictionary) -> void:
	if _life_t - float(_off_cd.get(off_id, -1000.0)) < OFF_CD:
		return
	if not world.drone_witnessed(global_position, owner_pid):
		return
	_off_cd[off_id] = _life_t
	world.commit_offense(owner_pid, off_id, data)


## Bzučení plaší zvěř do 45 m (a koně); nízko a blízko víc. Volá `Animal.hear_shot` jako zbraně.
func _scare_wildlife() -> void:
	if world.fauna == null:
		return
	for a in world.fauna.animals:
		if is_instance_valid(a) and not a.dead and a.global_position.distance_to(global_position) < 45.0:
			a.hear_shot(global_position, 8.0)


# ------------------------------------------------------------------ nárazy

func _physics_process(delta: float) -> void:
	var __t0 := Tests.prof_t0()
	_physics_process_impl(delta)
	Tests.prof_add("dron_phys", __t0)


func _physics_process_impl(delta: float) -> void:
	if mode == "strom":
		_stuck_t -= delta
		if _stuck_t <= 0.0:
			freeze = false
			custom_integrator = false
			gravity_scale = 1.0
			mode = "spadl"
			world.notify(owner_pid, "show_message", ["Dron se uvolnil ze stromu a padá!", 3.0])
	elif mode == "spadl" and not freeze and get_contact_count() > 0 and linear_velocity.length() < 1.2:
		# dopadl a přestal se kutálet
		mode = "zemi"
		freeze = true
		custom_integrator = true
	if global_position.y < -80.0:
		_lost()                  # pojistka: propadl pod mapu → zpátky do batohu (poškrábaný)


## Kontakt (body_entered): strom = zaseknutí, země/budova = nehoda podle rychlosti, člověk/zvíře = zranění.
func _on_body(b: Node) -> void:
	if not is_instance_valid(b) or freeze:
		return
	var impact := linear_velocity.length()
	if b is RigidBody3D or b is VehicleBody3D:
		var bv: Vector3 = b.get("linear_velocity")
		impact = maxf(impact, (linear_velocity - bv).length())
	var surf := String(b.get_meta("surface", ""))
	if flying():
		if surf == "strom":
			if impact > CRASH_V:
				_stick_tree()
			else:
				_bump(impact)
		elif b is Villager or b is Player or b is Animal or b is Horse or b is Npc:
			_hit_person(b, impact)
		elif mode in ["pristat", "rth"] and impact <= CRASH_V:
			_land()                      # cílené klesání dosáhlo povrchu (i střecha / střecha auta)
		elif impact > CRASH_V:
			_crash(surf if surf != "" else "překážka")
			if b.has_method("on_hit"):
				b.on_hit(impact)
		elif impact > BUMP_V:
			_bump(impact)


## Ťuknutí bez havárie: poškrábání + krátké „cuknutí“ servo (ztratí část rychlosti přes solver).
func _bump(impact: float) -> void:
	dmg = minf(dmg + impact * 1.5, 100.0)
	world.emit_game_event(owner_pid, "sfx", {"name": "thud", "delay": 0.0})


## Náraz do člověka / zvířete: zranění (knock), přestupek, havárie dronu.
func _hit_person(b: Node, impact: float) -> void:
	if impact <= BUMP_V:
		return
	if b.has_method("knock"):
		b.knock(linear_velocity * 0.4 + Vector3.UP * impact * 0.2, minf(impact, 8.0))
	if impact > CRASH_V:
		# zraněný je sám svědek – přestupek bez ohledu na okolí
		if _life_t - float(_off_cd.get("dron_zraneni", -1000.0)) >= OFF_CD:
			_off_cd["dron_zraneni"] = _life_t
			world.commit_offense(owner_pid, "dron_zraneni", {"impact": roundi(impact)})
		_crash("zvíře" if b is Animal else "osoba")
	else:
		_bump(impact)


## Zaseknutí v koruně stromu: dron zamrzne, po STUCK_S spadne.
func _stick_tree() -> void:
	mode = "strom"
	freeze = true
	_stuck_t = STUCK_S
	release()
	pad.visible = false
	world.notify(owner_pid, "police_banner", ["Dron zůstal viset ve stromu! Počkej, než se uvolní.", 4.0])
	world.emit_game_event(owner_pid, "drone_stuck", {})
	world.play_sfx(owner_pid, "crash", 1.2, -6.0)


## Ztráta dronu (propadl pod terén / mimo svět): vrátí se do inventáře poškrábaný.
func _lost() -> void:
	_flush_xp()
	var st := to_inventory()
	var p: Player = world.players.get(owner_pid)
	if p:
		p.add_item(model)
	var rec: Dictionary = world._drone_rec(owner_pid, model)
	rec["bat"] = st["bat"]
	rec["dmg"] = minf(float(st["dmg"]) + 15.0, 100.0)
	world.drones.erase(owner_pid)
	world.notify(owner_pid, "show_message", ["Dron se ti ztratil mimo mapu – našel se a vrátil do batohu (poškrábaný).", 4.0])
	world.emit_game_event(owner_pid, "drone_lost", {"model": model})
	queue_free()


## Nehoda: motorům konec, dron padá volným pádem (normální fyzika). Případné následky řeší _hit_person / on_hit.
func _crash(reason: String) -> void:
	if mode in ["spadl", "strom", "zemi"]:
		return
	mode = "spadl"
	custom_integrator = false
	gravity_scale = 1.0
	dmg = minf(dmg + linear_velocity.length() * DMG_PER_V, 100.0)
	angular_velocity = Vector3(randf_range(-9, 9), randf_range(-6, 6), randf_range(-9, 9))
	release()
	pad.visible = false
	snd.stop()
	_flush_xp()
	world.notify(owner_pid, "police_banner", ["Dron spadl! (%s)" % reason, 4.0])
	world.emit_game_event(owner_pid, "drone_crash", {"reason": reason})
	world.sound.emit(global_position, "crash", randf_range(1.4, 1.7), -6.0, 60.0)


## Zpátky do batohu (volá `World.drone_pickup` po uvolnění pilota).
func to_inventory() -> Dictionary:
	release()
	pad.visible = false
	return {"bat": bat_s, "dmg": dmg}


## Data pro uložení (světový dron mimo inventář – zaparkovaný / rozbitý).
func save_dict() -> Dictionary:
	return {"model": model, "pos": [global_position.x, global_position.y, global_position.z],
		"yaw": _yaw, "bat": bat_s, "dmg": dmg}


## Telemetrie pro HUD (klient volá každý frame, když `player.drone` letí).
func status() -> Dictionary:
	var w := []
	match mode:
		"start": w.append("VZLETÁM…")
		"rth": w.append("NÁVRAT DOMŮ%s" % (" – %s" % _rth_reason if _rth_reason != "" else ""))
		"pristat": w.append("PŘISTÁVÁM…")
	if mode == "let":
		if pilot_dist() < 3.5:
			w.append("[F] přistát")
		else:
			w.append("[F] návrat domů")
	var f := bat_frac()
	if f <= BAT_RTH:
		w.append("BATERIE %d %% – PADÁ!" % roundi(f * 100.0))
	elif f <= BAT_WARN:
		w.append("NÍZKÁ BATERIE %d %%" % roundi(f * 100.0))
	if sig < 0.18:
		w.append("SLABÝ SIGNÁL" + ("" if sig_los else " (překážka)"))
	if _fly_warn:
		w.append("DÁL UŽ NELÉTEJ – OPOUŠTÍŠ OBLAST")
	var a := agl()
	if a > MAX_ALT:
		w.append("NAD 120 m – PŘESTUPEK!")
	if _vlos_t > 1.5:
		w.append("MIMO DOHLED")
	if _crowd_t > 0.5:
		w.append("LIDÉ POD DRONEM")
	if _privacy_t > 1.5:
		w.append("SOUKROMÍ – ODLÉTEJ")
	if dmg >= CRASH_DMG:
		w.append("POŠKOZENÝ (oprav doma)")
	if not world.has_permit(owner_pid, "dron_provozovatel", global_position):
		w.append("BEZ REGISTRACE")
	elif bool(spec["needs_a1a3"]) and not world.has_permit(owner_pid, "dron_a1a3", global_position):
		w.append("BEZ A1/A3")
	return {"mode": mode, "model": spec["name"], "bat": f, "sig": sig, "agl": a, "alt_msl": global_position.y,
		"dist": pilot_dist(), "spd": linear_velocity.length(), "vs": linear_velocity.y,
		"sport": pilot != null and pilot.input.sprint, "cam3": _cam_3rd, "dmg": dmg,
		"reg": world.permits.number(owner_pid, "dron_provozovatel") if world.permits else "",
		"warns": w, "fotek": photo_t, "xp_d": _xp_d}


# ------------------------------------------------------------------ vizuál (interpolace + kamera + rotor)

func _process(delta: float) -> void:
	var __t0 := Tests.prof_t0()
	_process_impl(delta)
	Tests.prof_add("dron", __t0)


func _process_impl(delta: float) -> void:
	var f := Engine.get_physics_interpolation_fraction()
	var pos := _prev_pos.lerp(_cur_pos, f)
	var tb := Basis(Vector3.UP, lerp_angle(_prev_yaw, _cur_yaw, f))
	# náklon podle rychlosti (vizuální – dopředu dolů při letu vpřed)
	var lv := tb.inverse() * linear_velocity
	_tilt = _tilt.lerp(Vector2(clampf(lv.z * 0.05, -0.5, 0.5), clampf(-lv.x * 0.05, -0.5, 0.5)),
		1.0 - exp(-6.0 * delta))
	if mode == "spadl" or (mode == "zemi" and dmg >= CRASH_DMG):
		_tilt = _tilt.lerp(Vector2(0.2, -0.15), delta * 3.0)     # pobořený leží nakřivo
	vis.global_transform = Transform3D(tb * Basis(Vector3.RIGHT, _tilt.x) * Basis(Vector3.BACK, _tilt.y) * VIS_TURN, pos)
	# rotory: točí se, když jedou motory
	if flying():
		_spin += delta * (120.0 if mode != "start" else 95.0)
	for i in _rotors.size():
		_rotors[i].rotation.y = _spin * (1.0 if i % 2 == 0 else -1.0)
	_led.visible = flying() and fmod(_life_t, 1.0) < 0.6       # stroboskop
	# kamera: FPV na gimbalu / 3. osoba za dronem
	if cam:
		if _cam_3rd:
			var back := Vector3(0, spec["size"] * 1.6 - _cam_pitch * 1.2, -spec["size"] * 6.0)   # za dronem = −Z modelu
			cam.transform = Transform3D(Basis(), back)
			cam.look_at(vis.global_position + Vector3(0, spec["size"] * 0.5, 0), Vector3.UP)
		else:
			cam.position = Vector3(0, -spec["size"] * 0.4, spec["size"] * 0.6)
			cam.rotation = Vector3(_cam_pitch, PI, 0)
	# bzučení vrtulí podle „plynu“
	if flying() and not snd.playing:
		snd.play()
	if snd.playing:
		var load_ := clampf(linear_velocity.length() / 18.0, 0.0, 1.0)
		snd.pitch_scale = lerpf(0.9, 1.35, load_) + sin(_life_t * 30.0) * 0.015
		snd.volume_db = -14.0 if mode != "start" else -12.0
