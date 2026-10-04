## Motorový paraglide / paramotor (M6.4) – podtřída `Aircraft` (model „paramotor“).
## Rozdíly oproti letounu:
##  - START: křídlo se na louce rozloží za pilota (World.pg_prepare), F = navléct nosiče;
##    W = rozběh po nohou, křídlo se naplní jen čelem proti větru (HUD šipka větru);
##    boční vítr / slabý rozběh → křídlo spadne na stranu; vítr > 8 m/s → vytržení a pád;
##    plyn (Shift) před nahozeným křídlem → pád na záda / vrtule do trávy.
##  - ŘÍZENÍ: A/D = levá / pravá brzda (zatáčení), S = obě brzdy (zpomalení; hluboký tah →
##    propad / stall), W nebo Shift = plyn, Mezerník (držet) = povolené trimry (rychlejší let),
##    Ctrl = „uši“ (větší odpor → rychlejší klesání). Turbulence křídlo částečně zavře
##    (propad na stranu 1–3 s, srovnání opačnou brzdou).
##  - PŘISTÁNÍ: ~1 m nad zemí obě brzdy naplno (flare) → měkké dosednutí na nohy a doběh;
##    jinak tvrdé přistání (zranění). Po dosednutí křídlo padne za pilota; E = „Složit křídlo“.
##  - PRAVIDLA: pilotní průkaz `pilot_pg_motor` (škola 35 000 Kč – teorie eTest „paramotor“
##    + 5 výcvikových vzletů s instruktorem „rádiem“), registrace stroje a pojištění na
##    počítači (Letectví – ÚCL). Přestupky: bez průkazu / registrace, nízko nad obcí
##    (<150 m AGL, svědek slyší motor ~800 m), nad lidmi, v noci, za ztížené viditelnosti.
## Stroj stojí `World` (`aircrafts`), uložení sdílí `Aircraft.save_dict` + `pg_item`.
class_name Paramotor
extends Aircraft

const RUN_ACC := 4.5               # m/s² zrychlení rozběhu po nohou (W)
const RUN_MIN_V := 4.2             # m/s – min. rozběh / čelní vítr pro naplnění křídla
const RUN_MAX_V := 7.5             # m/s – strop rychlosti rozběhu nohama
const INFLATE_T := 1.6             # s – doba zvedání křídla nad hlavu
const CROSS_MAX := 3.5             # m/s – max. boční složka větru pro čisté nahození
const WIND_SAFE := 8.0             # m/s – silnější vítr křídlo vytrhne (pád)
const FUMBLE_LOCK := 1.6           # s blokáda po pádu / vytržení
const BRAKE_CD := 0.5              # přídavný odpor obou brzd naplno (S)
const SIDE_BRAKE_CD := 0.18        # přídavný odpor jednostranné brzdy (A/D)
const EARS_CD := 0.25              # „uši“ (Ctrl) – přídavný odpor → rychlejší klesání
const EARS_SINK := 0.8             # m/s přídavné klesání při „uších“ (přes odpor, laditelné)
const TRIM_V := 1.0                # m/s bonus k v_max na povolených trimrech (Mezerník)
const COLLAPSE_TURB := 1.1         # m/s² turbulence, od které hrozí zavření křídla
const COLLAPSE_P := 0.06           # šance zavření za s nad práhem (× přebytek turbulence)
const COLLAPSE_MIN := 1.0          # s min. délka částečného zavření
const COLLAPSE_MAX := 3.0          # s max. délka
const COLLAPSE_LIFT := 0.45        # násobek vztlaku při zavření
const COLLAPSE_BANK := 0.8         # rad – propad na stranu při zavření
const RECOVER_K := 2.5             # násobitel zotavení opačnou brzdou
const SINK_STALL_T := 0.7          # s hlubokého tahu obou brzd → propad (stall křídla)
const FLARE_AGL := 1.6             # m – okno pro vyrovnání přistání oběma brzdami
const FLARE_BRAKE := 0.7           # potřebný tah obou brzd pro flare
const WING_H := 6.6                # m – výška křídla nad závěsem (vizuální kyvadlo)
const PG_LAW_TICK := 4.0           # s – perioda kontroly přestupků
const PG_LOW_ALT := 150.0          # m AGL – minimum nad obcí / „šumový“ limit
const PG_PERSON_R := 35.0          # m – osoba pod paramotorem (nad shromážděním)

## Fáze přípravy: „laid“ = křídlo rozložené na zemi (bez pilota), „carried“ = pilot
## navlečený, křídlo za zády na zemi, „wing_up“ = křídlo nahozené nad hlavou.
var pg_state := "laid"
var pg_item := "paramotor"         # která položka inventáře se vrátí po sbalení (nový / ojetý)

var _inflate := 0.0                # 0..1 postup nahazování křídla
var _lock_t := -1.0                # do _life_t blokáda po fumble / vytržení
var _collapse_t := 0.0             # zbývající čas částečného zavření křídla (s)
var _collapse_side := 0.0          # -1 vlevo / +1 vpravo (strana propadu)
var _brake_l := 0.0                # levá brzda (A) 0..1
var _brake_r := 0.0                # pravá brzda (D) 0..1
var _brake_both := 0.0             # obě brzdy (S) 0..1
var _ears := false                 # Ctrl = „uši“
var _trims := 0.0                  # 0..1 povolené trimry (držený Mezerník)
var _sink_t := 0.0                 # s hlubokého tahu obou brzd (→ propad)
var _law_pg_t := 0.0
var _was_flying := false
var _infl_warned := false          # hláška „křídlo spadlo na stranu“ jen jednou za pokus

var _wing_root: Node3D             # vizuál křídla (pohybuje se podle fáze / kyvadla)
var _lines: MeshInstance3D         # šňůry (jen když křídlo stoupá / je nahoře)


# ------------------------------------------------------------------ vstup

## Drží pilot motor (Shift) – plyn před nahozeným křídlem je fumble.
func _sprint_in() -> bool:
	return pilot_input != null and pilot_input.sprint


## Vstup pilota → [plyn, brzdy-strany, zatažení]. Boční a společné brzdy, „uši“ a trimry
## čteme živě (opilost zpožďuje jen plyn / diferenciální brzdu / zatažení jako u letouna).
func _delayed_input(dt: float) -> Array:
	var thr := 0.0
	var steer := 0.0
	var elev := 0.0
	if pilot_input:
		_brake_l = clampf(pilot_input.steer, 0.0, 1.0)          # A = levá brzda
		_brake_r = clampf(-pilot_input.steer, 0.0, 1.0)         # D = pravá brzda
		_brake_both = clampf(pilot_input.brake, 0.0, 1.0)       # S = obě brzdy
		_ears = pilot_input.crouch                               # Ctrl = „uši“
		_trims = move_toward(_trims, 1.0 if pilot_input.jump else 0.0, dt * 0.8)
		steer = -pilot_input.steer                               # A → náklon vlevo (jako letoun)
		elev = _brake_both * 0.55                                # brzdy mírně zvedají nos (pak stall)
		if on_ground:
			thr = (pilot_input.throttle if pg_state == "wing_up" else 0.0)
			if _sprint_in():
				thr = 1.0 if pg_state == "wing_up" else 0.0
		else:
			thr = maxf(pilot_input.throttle, 1.0 if _sprint_in() else 0.0)
			thr = clampf(thr - _brake_both * 0.3, 0.0, 1.0)
	else:
		_brake_l = 0.0
		_brake_r = 0.0
		_brake_both = 0.0
		_trims = 0.0
		_ears = false
	var delay := clampf(body_state.promile() * DRUNK_DELAY, 0.0, 0.45) if body_state else 0.0
	_hist.append([_life_t, [thr, steer, elev]])
	while _hist.size() > 1 and _life_t - float(_hist[1][0]) >= delay:
		_hist.pop_front()
	_pg_tick(dt)
	if _hist.is_empty():
		return [0.0, 0.0, 0.0]
	return _hist[0][1]


## Stavy mimo samotné řízení: zavírání křídla v turbulenci, propad po hlubokém tahu,
## přestupkové kontroly a sledování přechodu vzduch→zem (křídlo padne za pilota).
func _pg_tick(dt: float) -> void:
	if pilot == null or world == null:
		return
	if on_ground:
		if _was_flying and pg_state == "wing_up":
			pg_state = "carried"                                 # po dosednutí křídlo padá za záda
		_was_flying = false
		_collapse_t = 0.0
		_sink_t = 0.0
		return
	_was_flying = true
	# hluboký tah obou brzd → propad (stall se řeší aerodynamikou přes elev)
	if _brake_both > 0.85:
		_sink_t += dt
		if _sink_t > SINK_STALL_T and _collapse_t <= 0.0:
			_start_collapse("Hluboký tah – křídlo propadlo")
			_sink_t = 0.0
	else:
		_sink_t = 0.0
	# turbulence → šance částečného zavření; opačná brzda zrychlí naplnění
	if _collapse_t <= 0.0:
		var tb := _turbulence(global_position).length()
		if tb > COLLAPSE_TURB and randf() < (tb - COLLAPSE_TURB) * COLLAPSE_P:
			_start_collapse("Turbulence – křídlo se částečně zavřelo")
	else:
		var recover := _brake_r if _collapse_side < 0.0 else _brake_l   # spadlo doleva → pravá brzda (D)
		_collapse_t -= dt * (1.0 + recover * RECOVER_K)
		if _collapse_t <= 0.0:
			_collapse_t = 0.0
			_notify("Křídlo se zase naplnilo.", 2.5)
	_law_pg(dt)


func _start_collapse(msg: String) -> void:
	_collapse_t = randf_range(COLLAPSE_MIN, COLLAPSE_MAX)
	_collapse_side = -1.0 if randf() < 0.5 else 1.0
	_notify("%s %s – srovnej opačnou brzdou (%s)." % [msg,
		"vlevo!" if _collapse_side < 0.0 else "vpravo!",
		"D" if _collapse_side < 0.0 else "A"], 3.5)


# ------------------------------------------------------------------ stavy pilota

func set_pilot(p: Player) -> void:
	super.set_pilot(p)
	if pg_state == "laid":
		pg_state = "carried"
		_notify("Nosiče navlečené. Otoč se ČELEM PROTI VĚTRU (šipka na přístrojích), " +
			"rozběhni se (W) – křídlo se zvedne nad hlavu. Pak přidej plyn (Shift).", 7.0)


func clear_pilot() -> void:
	super.clear_pilot()
	pg_state = "laid"
	_inflate = 0.0
	_collapse_t = 0.0


# ------------------------------------------------------------------ země: rozběh a nahození

## Pojíždění = běh pilota s motorem na zádech. W = nohy; tah vrtule se započítá až s křídlem
## nad hlavou (plyn předtím = fumble). Vzlet při v_min a dostatečném vztlaku padáku.
func _on_ground(state: PhysicsDirectBodyState3D, xf: Transform3D, gy: float,
		steer_in: float, elev_in: float, dt: float) -> void:
	var pos := xf.origin
	var fwd := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var h_a := world.terrain.height_at(pos.x + fwd.x * 2.0, pos.z + fwd.z * 2.0)
	var h_b := world.terrain.height_at(pos.x - fwd.x * 2.0, pos.z - fwd.z * 2.0)
	var slope := (h_a - h_b) / 4.0
	var v_ground := maxf(speed, 0.0)
	var wind := wind_at(pos)
	var m := total_kg()
	if pg_state == "carried" or pg_state == "wing_up":
		var run_in := clampf(pilot_input.throttle, 0.0, 1.0) if pilot_input else 0.0   # W = nohy
		var a := run_in * RUN_ACC * (1.0 - v_ground / RUN_MAX_V) - MU_GRASS * G - G * slope * 0.5
		if elev_in > 0.0:                                        # Mezerník na zemi = zabrždění
			a -= BRAKE_DECEL * 0.5
		if pg_state == "wing_up":
			a += float(spec["thrust"]) * throttle / m            # tah vrtule pomáhá doběhnout
		elif _sprint_in() and _life_t > _lock_t:
			_fumble(state)
			return
		v_ground = maxf(v_ground + a * dt, 0.0)
		if _life_t < _lock_t:
			v_ground = 0.0                                       # po pádu se sbalíš a stojíš
		_yaw -= steer_in * GROUND_STEER * clampf(v_ground / 6.0, 0.0, 1.0) * dt
		_bank = lerpf(_bank, -steer_in * 0.05, minf(dt * 3.0, 1.0))
		var pitch_tgt := atan(clampf(slope, -0.4, 0.4))
		if v_ground >= float(spec["v_min"]) * 0.9:
			pitch_tgt = 0.12
		_pitch = lerpf(_pitch, pitch_tgt, minf(dt * 4.0, 1.0))
		pos.y = gy + float(spec["gear_h"])
		var new_basis := Basis.from_euler(Vector3(_pitch, _yaw, _bank))
		state.transform = Transform3D(new_basis, pos)
		state.linear_velocity = new_basis * Vector3(0, 0, -v_ground)
		speed = v_ground
		_burn_fuel(dt)
		_update_inflate(dt, wind, v_ground)
		# vzlet: křídlo nahoře a vztlak převáží
		if pg_state == "wing_up" and v_ground >= float(spec["v_min"]) * 0.95:
			var rw := wind_at(pos) - state.linear_velocity
			var lrw := new_basis.inverse() * rw
			var va := maxf(lrw.length(), 0.01)
			var cl := float(spec["CL0"]) + float(spec["CL_A"]) * atan2(lrw.y, maxf(lrw.z, 0.01))
			if 0.5 * RHO * va * va * float(spec["S"]) * cl * _lift_scale() > m * G:
				on_ground = false
				_pitch = 0.14
				world.pg_training_takeoff(owner_id)
				_notify("Odlepení! Usaď se v sedačce – A/D brzdy do stran, S obě (pozor na propad), " +
					"W/Shift plyn, Mezerník trimry, Ctrl uši.", 6.0)


## Nahazování křídla: potřebný čelní proud (rozběh + protivítr), málo boční složky.
## Vítr > WIND_SAFE křídlo vytrhne a přežene přes pilota (pád).
func _update_inflate(dt: float, wind: Vector3, v_ground: float) -> void:
	if pg_state != "carried":
		return
	var fwd := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var w2 := Vector3(wind.x, 0.0, wind.z)
	var head := v_ground - fwd.dot(w2)                    # proud čelně = rozběh + protivítr
	var cross := (w2 - fwd * fwd.dot(w2)).length()        # boční složka větru
	if w2.length() > WIND_SAFE and _life_t > _lock_t:
		_fumble_wind("Silný vítr křídlo vytrhl a táhlo tě po louce! Počkej na slabší vítr.")
		return
	if head >= RUN_MIN_V and cross <= CROSS_MAX and _life_t > _lock_t:
		_inflate = minf(_inflate + dt / INFLATE_T, 1.0)
		_infl_warned = false
		if _inflate >= 1.0:
			pg_state = "wing_up"
			_notify("Křídlo je nad hlavou! Plyn (Shift nebo drž W) a doběhni vzlet.", 4.0)
	else:
		if _inflate > 0.4 and not _infl_warned:
			_infl_warned = true
			_notify("Křídlo spadlo na stranu – nedostatečný rozběh nebo boční vítr. Znovu a čelem proti větru!", 3.5)
		_inflate = maxf(_inflate - dt * 1.2 / INFLATE_T, 0.0)


## Plyn (Shift) dřív, než je křídlo nad hlavou → pád na záda, vrtule do trávy.
func _fumble(state: PhysicsDirectBodyState3D) -> void:
	dmg = minf(dmg + 8.0, 99.0)
	if body_state:
		body_state.hurt(6.0, "pád při rozběhu paramotoru")
	world.play_sfx(owner_id, "thud", 0.8, -2.0)
	_notify("Plyn před křídlem! Motor tě převrátil na záda a vrtule jede do trávy. Nejdřív křídlo nahlas, pak plyn.", 4.5)
	_lock_t = _life_t + FUMBLE_LOCK
	_inflate = 0.0
	throttle = 0.0
	speed = 0.0
	state.linear_velocity = Vector3.ZERO


## Vytržení křídla silným větrem (vléčení, pád).
func _fumble_wind(msg: String) -> void:
	dmg = minf(dmg + 4.0, 99.0)
	if body_state:
		body_state.hurt(8.0, "vítr vytrhl křídlo")
	world.play_sfx(owner_id, "thud", 0.9, -2.0)
	_notify(msg, 4.5)
	_lock_t = _life_t + FUMBLE_LOCK
	_inflate = 0.0
	speed = 0.0


# ------------------------------------------------------------------ háčky Aircraft (aerodynamika)

func _extra_drag() -> float:
	var d := _brake_both * BRAKE_CD + (_brake_l + _brake_r) * 0.5 * SIDE_BRAKE_CD
	if _ears:
		d += EARS_CD
	return d


func _lift_scale() -> float:
	if _collapse_t > 0.0:
		return COLLAPSE_LIFT
	return 1.0


func _v_max_bonus() -> float:
	return _trims * TRIM_V


func _bank_target(steer_in: float) -> float:
	if _collapse_t > 0.0:
		return _collapse_side * COLLAPSE_BANK                  # zavřené křídlo padá na stranu
	return -steer_in * float(spec["roll_max"])               # diferenciální brzda → náklon


func _flare_ok() -> bool:
	if world == null or world.terrain == null:
		return false
	var gy := world.terrain.height_at(global_position.x, global_position.z)
	return global_position.y - gy <= FLARE_AGL and _brake_both >= FLARE_BRAKE


func _flare_land(impact: float) -> void:
	pg_state = "carried"                                     # křídlo po doskočení padá za záda
	if impact > 2.2:
		if body_state:
			body_state.hurt((impact - 2.2) * 9.0, "špatné doskočení parametru")
		_notify("Pozdní flare – tvrdé doskočení (%.1f m/s)." % impact, 3.0)
		world.play_sfx(owner_id, "land", 0.8, -2.0)
	else:
		_notify("Pěkné dosednutí na nohy – doběhni! (E = složit křídlo)", 3.5)
		world.play_sfx(owner_id, "land", 1.0, -6.0)


# ------------------------------------------------------------------ přestupky (svědek = hluk ~800 m)

## Nad rámec alkoholu (`Aircraft._law_check`): bez průkazu / registrace, nízko nad obcí,
## nad lidmi, v noci, za ztížené viditelnosti. Svědek musí motor slyšet (~800 m).
func _law_pg(dt: float) -> void:
	_law_pg_t += dt
	if _law_pg_t < PG_LAW_TICK:
		return
	_law_pg_t = 0.0
	var pos := global_position
	if not world.pg_noise_witnessed(pos):
		return
	var gy := world.terrain.height_at(pos.x, pos.z) if world.terrain else pos.y
	var agl := pos.y - gy
	_offense("pg_bez_prukazu", not world.has_permit(owner_id, "pilot_pg_motor", pos), {})
	_offense("pg_bez_registrace", not world.has_permit(owner_id, "pg_registrace", pos), {})
	_offense("pg_nizko_nad_obci", agl < PG_LOW_ALT and world.pg_over_village(pos), {"agl": agl})
	_offense("pg_nad_lidmi", world.drone_person_under(pos, PG_PERSON_R), {})
	_offense("pg_noc", world.clock.is_night() if world.clock else false, {})
	_offense("pg_mraky", world.weather != null and (world.weather.cloud > 0.75 or world.weather.fog > 0.5), {})


func _offense(oid: String, cond: bool, data: Dictionary) -> void:
	if not cond:
		return
	if _life_t - float(_off_cd.get(oid, -10000.0)) < OFF_CD * 1.5:
		return
	_off_cd[oid] = _life_t
	world.commit_offense(owner_id, oid, data)


# ------------------------------------------------------------------ model (MeshKit)

## Vizuál: motor s klecí a vrtulí na zádech sedačky, závěsy se šňůrami a padákové křídlo
## (barevný loft oblouk ~10 m rozpětí) – samostatný uzel `_wing_root` (kyvadlo / fáze).
func _build_mesh() -> void:
	seat_pos = Vector3(0, -0.4, 0.1)   # postava „visí“ v postroji: nohy ~0,5 m nad zemí (gear_h 0,9)
	var mk := MeshKit.new()
	var frame := Color(0.32, 0.33, 0.36)
	var dark := Color(0.16, 0.16, 0.18)
	mk.box(Vector3(0, 0.55, 0.1), Vector3(0.55, 0.45, 0.4), Color(0.2, 0.2, 0.22))       # sedačka / sedák
	mk.box(Vector3(0, 0.85, 0.42), Vector3(0.5, 0.7, 0.28), dark)                        # motor na zádech
	mk.box(Vector3(0, 1.25, 0.42), Vector3(0.3, 0.12, 0.2), Color(0.5, 0.3, 0.1))        # nádrž
	# klec vrtule: prsten + 4 paprsky (za pilotem, rovina XZ svisle = rotace o X)
	mk.cylinder(Vector3(0, 1.05, 0.62), 0.52, 0.52, 0.04, dark, Vector3(PI * 0.5, 0, 0), 20)
	for ang in [0.0, PI * 0.5]:
		mk.box(Vector3(0, 1.05, 0.6), Vector3(0.05, 1.0, 0.04), frame, Vector3(0, 0, ang))
	mk.box(Vector3(-0.34, 1.35, 0.05), Vector3(0.05, 1.4, 0.05), frame)                  # závěsy (risery)
	mk.box(Vector3(0.34, 1.35, 0.05), Vector3(0.05, 1.4, 0.05), frame)
	var mi := MeshInstance3D.new()
	mi.mesh = mk.commit(MeshKit.vc_material(0.75))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	vis.add_child(mi)
	_prop = MeshInstance3D.new()                                   # vrtule v kleci (točí se kolem Z)
	var pmk := MeshKit.new()
	pmk.box(Vector3.ZERO, Vector3(0.06, 0.95, 0.03), Color(0.1, 0.1, 0.1))
	pmk.box(Vector3.ZERO, Vector3(0.95, 0.06, 0.03), Color(0.1, 0.1, 0.1))
	_prop.mesh = pmk.commit(MeshKit.vc_material(0.6))
	_prop.position = Vector3(0, 1.05, 0.6)
	vis.add_child(_prop)
	# křídlo: loft oblouk přes rozpětí (buňky = barevné pruhy přes rozpětí)
	_wing_root = Node3D.new()
	vis.add_child(_wing_root)
	var wmk := MeshKit.new()
	var palette := [Color(0.85, 0.25, 0.2), Color(0.95, 0.85, 0.25), Color(0.2, 0.45, 0.8)]
	var rings := []
	var cols := []
	for i in range(9):
		var x := -5.0 + i * (10.0 / 8.0)
		var arc := 0.9 * (1.0 - (x / 5.0) * (x / 5.0))
		rings.append(PackedVector3Array([Vector3(x, arc, -1.05), Vector3(x, arc * 0.85, 1.05)]))
		cols.append([palette[i % 3], palette[i % 3].darkened(0.15)])
	wmk.loft(rings, cols, false)
	var wmi := MeshInstance3D.new()
	wmi.mesh = wmk.commit(MeshKit.vc_material(0.85, 0.0, 0.0, false))
	wmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_wing_root.add_child(wmi)
	# šňůry: ~16 tenkých válečků ze závěsů k okraji křídla (vizuální, jen když stoupá/je nahoře)
	var lmk := MeshKit.new()
	for side in [-1.0, 1.0]:
		for i in range(8):
			var tx: float = side * (0.6 + i * 0.62)
			var ty: float = WING_H + 0.9 * (1.0 - (tx / 5.0) * (tx / 5.0))
			_rope(lmk, Vector3(side * 0.34, 2.0, 0.05), Vector3(tx, ty, 0.05), Color(0.75, 0.75, 0.75))
	_lines = MeshInstance3D.new()
	_lines.mesh = lmk.commit(MeshKit.vc_material(0.5))
	vis.add_child(_lines)


## Tenký váleček šňůry mezi body a→b (MeshKit.add_prim s bází podle směru).
func _rope(mk: MeshKit, a: Vector3, b: Vector3, color: Color) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.01:
		return
	var y_ax := d / len
	var x_ax := y_ax.cross(Vector3.FORWARD)
	x_ax = y_ax.cross(Vector3.RIGHT).normalized() if x_ax.length() < 0.01 else x_ax.normalized()
	var z_ax := x_ax.cross(y_ax)
	var cm := CylinderMesh.new()
	cm.top_radius = 0.012
	cm.bottom_radius = 0.012
	cm.height = len
	cm.radial_segments = 5
	mk.add_prim(cm, Transform3D(Basis(x_ax, y_ax, z_ax), (a + b) * 0.5), color)


# ------------------------------------------------------------------ vizuál / HUD / save

func _process(delta: float) -> void:
	super._process(delta)
	# postava pilota: ve vzduchu sedí v sedačce, na zemi stojí/běží
	if pilot != null and pilot.visual:
		pilot.visual.pose = "ride" if not on_ground else "stand"
	# poloha křídla podle fáze (na zemi za zády → nahození → nad hlavou) + kyvadlo
	if _wing_root:
		var t := clampf(_inflate, 0.0, 1.0)
		if not on_ground or pg_state == "wing_up":
			t = maxf(t, 0.999)
		# položené křídlo leží za pilotem, nahozené visí ~WING_H nad závěsem
		var lay := Vector3(0, 0.45, 3.4)
		_wing_root.position = lay.lerp(Vector3(0, WING_H, 0.1), ease(t, 0.5))
		var rot_x := lerpf(-1.25, 0.0, ease(t, 0.5))                # vztyčení při nahození
		var sway := -_bank * 0.4                                     # kyvadlo: v zatáčce pilot vylétává ven
		var pump := _brake_both * 0.12                               # brzdy houpu vpřed/vzad
		if _collapse_t > 0.0:
			sway += _collapse_side * 0.55
			pump += 0.15
		_wing_root.rotation = Vector3(rot_x + pump, 0.0, sway)
	if _lines:
		_lines.visible = _inflate > 0.25 or not on_ground


## Telemetrie navíc: fáze přípravy, zavření křídla, výstrahy pro `FlightHud`.
func status() -> Dictionary:
	var st := super.status()
	if st.is_empty():
		return st
	var warns: Array = st["warns"]
	if on_ground:
		if pg_state == "carried":
			warns.append("KŘÍDLO NA ZEMI – čelem proti větru a rozběh (W); plyn Shift až když křídlo stoupá" if _inflate < 0.05
				else "KŘÍDLO STOUPÁ %d %%" % roundi(_inflate * 100.0))
		elif world and world.weather and world.weather.wind > WIND_SAFE:
			warns.append("SILNÝ VÍTR %.0f m/s – start vyhraje na houby" % world.weather.wind)
	if _collapse_t > 0.0:
		warns.append("ZAVŘENÉ KŘÍDLO – opačná brzda %s!" % ("A" if _collapse_side > 0.0 else "D"))
	if _ears:
		warns.append("UŠI – rychlé klesání")
	if world and not world.has_permit(owner_id, "pilot_pg_motor", global_position):
		warns.append("LETÍŠ BEZ PRŮKAZU – pokuta, když tě uslyší!")
	st["warns"] = warns
	return st


func save_dict() -> Dictionary:
	var d := super.save_dict()
	d["pg_item"] = pg_item
	return d
