## Motorový paraglide / paramotor (M6.4) – podtřída `Aircraft` (model „paramotor“).
## Rozdíly oproti letounu:
##  - START: křídlo se na louce rozloží za pilota (World.pg_prepare), F = navléct nosiče;
##    W = rozběh po nohou, křídlo se naplní jen čelem proti větru (HUD šipka větru);
##    boční vítr / slabý rozběh → křídlo spadne na stranu; vítr > 8 m/s → vytržení a pád;
##    plyn (Shift) před nahozeným křídlem jen varuje (tah se nepřičte).
##  - ŘÍZENÍ: A/D = levá / pravá brzda (zatáčení), S = obě brzdy (zpomalení; hluboký tah →
##    propad / stall), W nebo Shift = plyn, Mezerník (držet) = povolené trimry (rychlejší let),
##    Ctrl = „uši“ (větší odpor → rychlejší klesání). Turbulence křídlo částečně zavře
##    (propad na stranu 1–3 s, srovnání opačnou brzdou).
##  - PŘISTÁNÍ: ~1 m nad zemí obě brzdy naplno (flare) → měkké dosednutí na nohy a doběh;
##    jinak tvrdé přistání (zranění). Po dosednutí křídlo padne za pilota; E = „Složit křídlo“.
##  - PRAVIDLA: pilotní průkaz `pilot_pg_motor` (škola 35 000 Kč – teorie eTest „paramotor“
##    + 5 výcvikových vzletů s instruktorem „rádiem“), registrace stroje a pojištění na
##    počítači (Letectví – ÚVL). Přestupky: bez průkazu / registrace, nízko nad obcí
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
const FUMBLE_LOCK := 1.6           # s blokáda po vytržení křídla větrem
const SHIFT_WARN_CD := 3.0         # s mezi varováními „plyn až s křídlem nad hlavou“
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
const WING_H := 7.4                # m – vrchol oblouku křídla nad zemí (vis) při visu / letu
const RISER := Vector3(0.3, 2.0, 0.05)   # karabiny riserů (vis) = čep kyvadla křídla
const WING_R := 6.0                # m – poloměr oblouku křídla (čelní pohled)
const WING_ARC := 0.9              # rad – půlúhel oblouku (rozpětí ~9,4 m v průmětu)
const WING_CHORD := 2.6            # m – hloubka uprostřed
const WING_TIP_CHORD := 1.3        # m – hloubka na konci
const WING_CELLS := 14             # barevných komor
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
var _shift_warn_t := -10.0         # _life_t posledního varování Shift před křídlem

var _wing_root: Node3D             # čep křídla v karabinách (fáze nahazování / kyvadlo)
var _wing_mi: MeshInstance3D       # mesh křídla (na zemi naplocho – scale y)
var _wing_vis := 0.0               # vizuální fáze křídla 0 = leží, 1 = nahoře (plynule padá)
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
			_inflate = 0.0
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
	if p.visual and on_ground:
		p.visual.position = Vector3.ZERO                         # na zemi stojí nohama na trávě
		p.visual.pose = "stand"
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
## nad hlavou (Shift předtím jen varuje – A2-13). Vzlet, když vztlak padáku převáží tíhu.
## Rychlost na zemi je vodorovná a náběh = pitch (A2-03, společné `Aircraft._ground_aero`).
func _on_ground(xf: Transform3D, gy: float,
		steer_in: float, elev_in: float, dt: float) -> void:
	var pos := xf.origin
	var fwd := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var slope := _slope_at(pos, fwd)
	var v_ground := maxf(speed, 0.0)
	var wind := wind_at(pos)
	var m := total_kg()
	var wing_up := pg_state == "wing_up"
	var ae := _ground_aero(pos, fwd, v_ground, slope, 1.0 if wing_up else 0.0)
	var run_in := clampf(pilot_input.throttle, 0.0, 1.0) if pilot_input else 0.0   # W = nohy
	var a := run_in * RUN_ACC * maxf(1.0 - v_ground / RUN_MAX_V, 0.0) - MU_GRASS * G - G * slope * 0.5
	if elev_in > 0.0:                                            # Mezerník na zemi = zabrždění
		a -= BRAKE_DECEL * 0.5
	if wing_up:
		a += (_thrust(float(ae["va"])) - float(ae["drag"])) / m   # tah vrtule pomáhá doběhnout
	elif _sprint_in():
		_shift_warn()
	v_ground = maxf(v_ground + a * dt, 0.0)
	if _life_t < _lock_t:
		v_ground = 0.0                                           # po vytržení se sbíráš a stojíš
	_ground_move(pos, gy, slope, v_ground, float(ae["va"]), steer_in, dt, wing_up)
	_burn_fuel(dt)
	_update_inflate(dt, wind, v_ground)
	# vzlet: křídlo nahoře a vztlak převáží
	if wing_up and _try_liftoff(float(ae["lift"]), float(ae["va"]), v_ground):
		world.pg_training_takeoff(owner_id)
		_notify("Odlepení! Usaď se v sedačce – A/D brzdy do stran, S obě (pozor na propad), " +
			"W/Shift plyn, Mezerník trimry, Ctrl uši.", 6.0)


## Shift před nahozeným křídlem: jen varování (dřív pád na záda – A2-13), tah se nepřičte.
func _shift_warn() -> void:
	if _life_t - _shift_warn_t < SHIFT_WARN_CD:
		return
	_shift_warn_t = _life_t
	_notify("Plyn až s křídlem nad hlavou! Nejdřív čelem proti větru rozběh (W), Shift potom.", 3.0)


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
	if world == null:
		return false
	return _xf.origin.y - _gh(_xf.origin.x, _xf.origin.z) <= FLARE_AGL and _brake_both >= FLARE_BRAKE


func _flare_land(impact: float) -> void:
	pg_state = "carried"                                     # křídlo po doskočení padá za záda
	_inflate = 0.0
	if impact > 2.2:
		if body_state:
			body_state.hurt((impact - 2.2) * 9.0, "špatné doskočení parametru")
		_notify("Pozdní flare – tvrdé doskočení (%.1f m/s)." % impact, 3.0)
		world.play_sfx(owner_id, "land", 0.8, -2.0)
	else:
		_notify("Pěkné dosednutí na nohy – doběhni! (E = složit křídlo)", 3.5)
		world.play_sfx(owner_id, "land", 1.0, -6.0)


## Hláška při vstupu do přetažení (Fáze 4, stav „Pretazeni“) – u padáku se pouštějí brzdy.
func _stall_hint() -> String:
	return "PŘETAŽENÍ křídla! Povol brzdy a přidej plyn – nos padne a křídlo se zase chytí."


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
	var agl := pos.y - _gh(pos.x, pos.z)
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

## Vizuál (`vis`: y = 0 zem pod nohama, −Z vpřed): sedačka s opěrou, motor s nádrží a klecí
## vrtule na zádech pilota, závěsy (risery) a padákové křídlo – profilovaný oblouk s barevnými
## komorami a šňůrami. Křídlo visí na uzlu `_wing_root` s čepem v karabinách (kyvadlo, fáze
## nahazování); na zemi leží naplocho za pilotem (A2-09).
func _build_mesh() -> void:
	var mk := MeshKit.new()
	var frame := Color(0.62, 0.63, 0.66)
	var dark := Color(0.16, 0.16, 0.18)
	var harness := Color(0.18, 0.22, 0.3)
	mk.box(Vector3(0, 0.76, 0.25), Vector3(0.46, 0.06, 0.36), harness)                  # sedák (vršek 0,79)
	mk.box(Vector3(0, 1.08, 0.24), Vector3(0.44, 0.6, 0.08), harness)                   # opěra / zádový chránič
	mk.box(Vector3(0, 1.0, 0.4), Vector3(0.34, 0.4, 0.24), dark)                        # motor
	mk.cylinder(Vector3(0, 1.0, 0.54), 0.07, 0.07, 0.1, dark, Vector3(PI * 0.5, 0, 0), 10)  # náboj reduktoru
	mk.box(Vector3(0, 0.66, 0.38), Vector3(0.32, 0.2, 0.22), Color(0.85, 0.5, 0.12))    # nádrž
	# klec vrtule: obruč z 20 trubek + 4 paprsky
	var cage_c := Vector3(0, 1.02, 0.62)
	for i in range(20):
		var a0 := TAU * i / 20.0
		var a1 := TAU * (i + 1) / 20.0
		rod(mk, cage_c + Vector3(cos(a0), sin(a0), 0) * 0.62, cage_c + Vector3(cos(a1), sin(a1), 0) * 0.62, 0.012, frame, 4)
	for i in range(4):
		var a2 := TAU * i / 4.0 + PI * 0.25
		rod(mk, cage_c + Vector3(0, 0, -0.06), cage_c + Vector3(cos(a2), sin(a2), 0) * 0.62, 0.01, frame, 4)
	# ramena k karabinám a risery vzhůru
	for sx in [-1.0, 1.0]:
		rod(mk, Vector3(sx * 0.18, 1.2, 0.34), Vector3(sx * 0.26, 1.42, 0.06), 0.015, frame, 5)
		rod(mk, Vector3(sx * 0.26, 1.42, 0.06), Vector3(sx * RISER.x, RISER.y, RISER.z), 0.012, dark, 4)
	var mi := MeshInstance3D.new()
	mi.mesh = mk.commit(MeshKit.vc_material(0.75))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	vis.add_child(mi)
	_prop = MeshInstance3D.new()                                   # vrtule v kleci (točí se kolem Z)
	var pmk := MeshKit.new()
	pmk.box(Vector3.ZERO, Vector3(0.07, 1.1, 0.03), Color(0.1, 0.1, 0.1))
	_prop.mesh = pmk.commit(MeshKit.vc_material(0.6))
	_prop.position = cage_c + Vector3(0, 0, -0.02)
	vis.add_child(_prop)
	# křídlo: čep `_wing_root` v karabinách, mesh křídla posunutý nahoru (vrchol oblouku = WING_H)
	_wing_root = Node3D.new()
	_wing_root.position = Vector3(0, RISER.y, RISER.z)
	vis.add_child(_wing_root)
	_wing_mi = MeshInstance3D.new()
	_wing_mi.mesh = _wing_mesh()
	_wing_mi.position = Vector3(0, WING_H - RISER.y, 0)
	_wing_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_wing_root.add_child(_wing_mi)
	_lines = MeshInstance3D.new()
	_lines.mesh = _lines_mesh()
	_wing_root.add_child(_lines)
	# pilot: ve vzduchu sedí v sedačce (pánev ~6 cm nad sedákem), nohy volně vpředu dole,
	# ruce u riserů (řidičky brzd); na zemi stojí (seat (0,0,0), póza stand – viz _process)
	seat_pos = Vector3(0, 0.79 + 0.06 - 0.5, 0.06)
	rider = rider_pose(seat_pos, 0.5, -0.1, Vector3(0, 1.55, 0.02), Vector3(0, 0.1, -0.35))
	eye_pos = seat_pos + Vector3(0, 1.17, -0.06)


## Bod profilu křídla ve stanici `th` (rad podél oblouku) – `u` 0..1 podél hloubky od náběžné
## hrany, `side` +1 horní / −1 spodní plocha. Souřadnice vůči vrcholu oblouku (mesh křídla).
func _wing_pt(th: float, u: float, side: float) -> Vector3:
	var c := WING_CHORD - (WING_CHORD - WING_TIP_CHORD) * pow(th / WING_ARC, 2.0)
	var nrm := Vector3(sin(th), cos(th), 0.0)
	var ctr := Vector3(WING_R * sin(th), WING_R * cos(th) - WING_R, 0.0)
	var thick := 0.14 * c * sin(PI * pow(u, 0.6))
	var off := thick * (0.7 if side > 0.0 else -0.3)
	return ctr + nrm * off + Vector3(0, 0, -0.3 * c + u * c)


## Padákové křídlo: oblouk WING_CELLS komor (každá komora vlastní barva – zdvojené stanice),
## uzavřený profil (horní / spodní plocha), víčka na koncích.
func _wing_mesh() -> ArrayMesh:
	var wmk := MeshKit.new()
	var palette := [Color(0.85, 0.22, 0.18), Color(0.97, 0.85, 0.25), Color(0.2, 0.45, 0.82)]
	const US := [0.0, 0.08, 0.3, 0.6, 1.0]
	var rings := []
	var cols := []
	for i in range(WING_CELLS):
		var col: Color = palette[i % palette.size()]
		for e in [0, 1]:
			var th := -WING_ARC + 2.0 * WING_ARC * float(i + e) / WING_CELLS
			var ring := PackedVector3Array()
			var rc := []
			for u in US:                                          # horní plocha náběžná → odtoková
				ring.append(_wing_pt(th, float(u), 1.0))
				rc.append(col)
			for k in range(US.size() - 2, 0, -1):                # spodní plocha zpět
				ring.append(_wing_pt(th, float(US[k]), -1.0))
				rc.append(col.darkened(0.3))
			rings.append(ring)
			cols.append(rc)
	wmk.loft(rings, cols, true)
	cap_ring(wmk, rings[0], true, palette[0].darkened(0.3))
	cap_ring(wmk, rings[rings.size() - 1], false, palette[(WING_CELLS - 1) % palette.size()].darkened(0.3))
	return wmk.commit(MeshKit.vc_material(0.85))


## Šňůry: z karabin (čep `_wing_root`) k přední (A) a zadní (C) řadě na spodní ploše křídla.
func _lines_mesh() -> ArrayMesh:
	var lmk := MeshKit.new()
	var up := Vector3(0, WING_H - RISER.y, 0)
	for sx in [-1.0, 1.0]:
		var root := Vector3(sx * RISER.x, 0.0, 0.0)
		for k in range(6):
			var th: float = sx * WING_ARC * (k + 0.5) / 6.0
			for u in [0.12, 0.62]:
				rod(lmk, root, up + _wing_pt(th, u, -1.0), 0.008, Color(0.82, 0.82, 0.8), 3)
	return lmk.commit(MeshKit.vc_material(0.5))


# ------------------------------------------------------------------ vizuál / HUD / save

## Pilot paramotoru na zemi běží (Humanoid.speed), ve vzduchu sedí.
func rider_speed() -> float:
	return speed if on_ground and pilot != null else 0.0


func _process(delta: float) -> void:
	super._process(delta)
	# postava pilota: ve vzduchu sedí v sedačce, na zemi stojí nohama na trávě a běží
	if pilot != null and pilot.visual and pilot.visual.get_parent() == vis:
		var air := not on_ground
		pilot.visual.pose = "ride" if air else "stand"
		pilot.visual.on_floor = true
		pilot.visual.position = pilot.visual.position.lerp(seat_pos if air else Vector3.ZERO, minf(delta * 4.0, 1.0))
	# křídlo: položené naplocho za pilotem → nahazování obloukem → nad hlavou + kyvadlo
	if _wing_root:
		var t := clampf(_inflate, 0.0, 1.0)
		if not on_ground or pg_state == "wing_up":
			t = 1.0
		_wing_vis = move_toward(_wing_vis, t, delta * (4.0 if t > _wing_vis else 0.7))
		var k := ease(_wing_vis, 0.6)
		var lay := (1.0 - k) * PI * 0.5                            # 90° = křídlo leží vzadu
		_wing_root.position = Vector3(0, lerpf(0.25, RISER.y, k), RISER.z)
		var sway := -_bank * 0.4 * k                               # kyvadlo: v zatáčce pilot vylétává ven
		var pump := _brake_both * 0.12 * k                         # brzdy houpou vpřed/vzad
		if _collapse_t > 0.0:
			sway += _collapse_side * 0.55
			pump += 0.15
		_wing_root.rotation = Vector3(lay + pump, 0.0, sway)
		_wing_mi.rotation = Vector3(-lay, 0.0, 0.0)                # hloubka zůstává vodorovně
		_wing_mi.scale = Vector3(1.0, lerpf(0.06, 1.0, k), 1.0)    # na zemi oblouk naplocho
	if _lines:
		_lines.visible = _wing_vis > 0.85


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
