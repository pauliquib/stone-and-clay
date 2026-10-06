## Motorové rogalo / trike (M6.5) – podtřída `Aircraft` (model „trike“).
## Tříkolka (řízené příďové kolo + dvě hlavní), vozík s kapotáží, tlačná vrtule vzadu,
## stožár a trojúhelníkové rogalo (~15 m²). Dvě sedadla za sebou – druhé pro spolujezdce.
##
## ŘÍZENÍ HRAZDOU – výchozí INTUITIVNÍ (vlna 0d, A2-13): W = nos nahoru, S = dolů, A = vlevo.
## Přepínač „Realistické řízení rogala“ (Esc → Nastavení) zapne obrácené řízení hrazdou
## (weight-shift): S = hrazdu od sebe → nos nahoru, W = k sobě → klesat, A = zatáčka DOPRAVA.
## Plyn = PÁČKA, která drží polohu: Shift přidat, Ctrl ubrat.
## Na zemi: A/D řídí příďové kolo (normálně), Mezerník brzdí, rozjezd na trávě delší.
##
## PRAVIDLA (zjednodušené ULL / LAA ČR): průkaz `pilot_ul` (škola 75 000 Kč = eTest „ul“
## + 10 výcvikových letů), registrace stroje `ul_registrace`, pojištění `ul_pojisteni`,
## létání jen za dne a VFR; přistání mimo letiště jen v nouzi → přestupek `ul_pristani_mimo`.
## Spolujezdec: vesničan s přátelstvím ≥ 60 (akce „vyhlídkový let“, viz World.trike_*).
class_name Trike
extends Aircraft

const THR_RATE := 0.55             # 1/s – rychlost pojezdu páky plynu (Shift/Ctrl)
const MU_TRIKE := 0.06             # valivý odpor tříkolky na trávě (rozjezd delší)
const UL_LAW_TICK := 4.0           # s – perioda kontroly přestupků
const UL_LOW_ALT := 150.0          # m AGL – minimum nad obcí
const UL_PERSON_R := 35.0          # m – osoba pod strojem (nad shromážděním)
const LAND_HINT_AGL := 30.0        # m AGL – pod tím se ukazuje přistávací nápověda
const PAX_TALK_MIN := 14.0         # s – min. odstup bublin spolujezdce
const PAX_TALK_MAX := 30.0         # s – max. odstup
const PAX_SEAT := Vector3(0.0, 0.44, 0.3)    # postava spolujezdce (vůči vis; sedák vršek 0,88)
const HANG := Vector3(0.0, 2.75, 0.15)       # závěs křídla na stožáru (vis)
const BAR := Vector3(0.0, 1.25, -0.8)        # střed řídicí hrazdy (vis) – úchop pilota
const BAR_HALF := 0.7                        # m – polovina šířky hrazdy
const SPAN_HALF := 4.9                       # m – polorozpětí rogala
const NOSE_Z := -1.75                        # nos kýlu vůči závěsu
const TIP_LE_Z := 0.75                       # konec náběžné hrany (šíp)
const KEEL_TE_Z := 1.3                       # odtoková hrana u kýlu
const TIP_TE_Z := 1.35                       # odtoková hrana na konci
const SAIL_ST := 16                          # stanic plachty přes rozpětí

## Hlášky spolujezdce při vyhlídkovém letu (smyšlené, vesnický humor).
const PAX_LINES := [
	"Tady bydlím! Přímo tam dole!",
	"To pole pod náma orbu děda!",
	"Vidím náš komín – a řekni mu, ať kouří míň!",
	"Jéé, tam je hospoda. Sletíme na jedno?",
	"Krásný, jak z dronu – jen to víc hučí!",
	"Ty jo, tak TAKHLE vypadá naše vesnice?!",
	"Děda prý letěl taky. Ale jen ze schodů.",
]

var _lever := 0.0                  # poloha páky plynu (drží se, na rozdíl od paramotoru)
var _intuitive := true             # výchozí intuitivní hrazda; Esc → Nastavení → realistické
var _pax: Villager                 # spolujezdec na zadním sedadle (vyhlídkový let)
var _pax_vis: Humanoid             # viditelná postava spolujezdce v sedadle (vesničan je skrytý)
var _pax_rider := {}               # póza spolujezdce (Humanoid.ride)
var _pax_talk_t := 0.0             # odpočet do další bubliny
var _was_flying := false           # detekce přechodu vzduch → zem (přistání / pravidla)
var _law_ul_t := 0.0

var _nw: MeshInstance3D            # příďové kolo (vizuální řízení)
var _wing: Node3D                  # rogalo + A-rám (závěs v HANG)


# ------------------------------------------------------------------ vstup a řízení

## Vstup pilota → [plyn, klon, pitch]. Plyn drží páka (Shift/Ctrl); ve vzduchu W/S = pitch
## (intuitivně W nahoru, realisticky obráceně), na zemi Mezerník = brzda kol.
func _delayed_input(dt: float) -> Array:
	var steer := 0.0
	var elev := 0.0
	_intuitive = _read_intuitive()
	if pilot_input:
		# páka plynu drží polohu
		if pilot_input.sprint:
			_lever = clampf(_lever + THR_RATE * dt, 0.0, 1.0)
		if pilot_input.crouch:
			_lever = clampf(_lever - THR_RATE * dt, 0.0, 1.0)
		steer = -pilot_input.steer                                # A → +… viz _bank_target
		if on_ground:
			elev = 1.0 if pilot_input.jump else 0.0               # Mezerník = brzda kol
		else:
			# hrazda: intuitivně W = nos nahoru; realisticky S (hrazda od sebe) = nahoru
			var bar := pilot_input.brake - pilot_input.throttle   # S − W
			elev = -bar if _intuitive else bar
	else:
		_lever = 0.0
	_ul_tick(dt)
	var thr := _lever
	var delay := clampf(body_state.promile() * DRUNK_DELAY, 0.0, 0.45) if body_state else 0.0
	_hist.append([_life_t, [thr, steer, elev]])
	while _hist.size() > 1 and _life_t - float(_hist[1][0]) >= delay:
		_hist.pop_front()
	if _hist.is_empty():
		return [0.0, 0.0, 0.0]
	return _hist[0][1]


## Přepínač z nastavení klienta (výchozí = intuitivní; realistické obrácené jen na přání).
func _read_intuitive() -> bool:
	if world == null:
		return true
	var cl = world.clients.get(owner_id)
	return not (cl != null and cl.settings != null and bool(cl.settings.trike_realistic))


## Smysl zatáčení hrazdou: intuitivně A = vlevo; realisticky A = hrazda doleva = zatáčka vpravo.
func _bank_target(steer_in: float) -> float:
	var roll := float(spec["roll_max"])
	return (-steer_in * roll) if _intuitive else (steer_in * roll)


## Těžší stroj na trávě → delší rozjezd než letoun/běh.
func _mu_ground() -> float:
	return MU_TRIKE


## Hláška po vzletu – ovládání hrazdy (místo obecného textu letounu).
func _takeoff_hint() -> String:
	return ("Vzlet! W nos nahoru, S dolů, A/D zatáčení · Shift/Ctrl páka plynu." if _intuitive
		else "Vzlet! Hrazda (realisticky): S nos NAHORU / zpomalit, W klesat · A/D zatáčí OBRÁCENĚ · Shift/Ctrl páka.")


## Nápověda ovládání při nastoupení (World.enter_aircraft, Trike.set_pilot).
func controls_hint() -> String:
	var air := ("ve vzduchu W nos nahoru, S dolů, A/D zatáčení" if _intuitive
		else "ve vzduchu HRAZDA realisticky: S nos NAHORU, W klesat, A/D zatáčí OBRÁCENĚ")
	return "%s – páka plynu Shift přidat / Ctrl ubrat (drží polohu), na zemi A/D příďové kolo a Mezerník brzda; %s. V kamera, F vystoupit." % [
		String(spec.get("name", model)), air]


## Celková vzletová hmotnost navíc o spolujezdce (~80 kg).
func total_kg() -> float:
	return super.total_kg() + (80.0 if _pax != null else 0.0)


# ------------------------------------------------------------------ stavy pilota a spolujezdec

func set_pilot(p: Player) -> void:
	super.set_pilot(p)
	_lever = 0.0
	_intuitive = _read_intuitive()


func clear_pilot() -> void:
	_pax_off("Pilot vystoupil – let končí.")
	super.clear_pilot()
	_lever = 0.0


## Nastoupení spolujezdce na zadní sedadlo (volá `World.ul_board_passenger`).
## Vesničan se schová a vypne, v sedadle sedí jeho viditelná kopie (`_pax_vis`, stejný vzhled).
func board_passenger(v: Villager) -> void:
	_pax = v
	_pax_talk_t = 8.0
	v.set_physics_process(false)
	v.visible = false
	v.collision_layer = 0
	v.collision_mask = 0
	if _pax_vis == null and v.persona != null:
		_pax_vis = Humanoid.new()
		Characters.apply_look(_pax_vis, v.persona.profile)
		vis.add_child(_pax_vis)
		_pax_vis.position = PAX_SEAT
		_pax_vis.rotation = Vector3(0.0, PI, 0.0)         # Humanoid kouká do +Z, stroj letí do −Z
		_pax_vis.ride = _pax_rider
		_pax_vis.pose = "ride"
		_pax_vis.on_floor = true


## Vysazení spolujezdce vedle stroje (přistání, vystoupení pilota, uložení).
func _pax_off(msg := "") -> void:
	if _pax_vis != null:
		_pax_vis.queue_free()
		_pax_vis = null
	var v := _pax
	if v == null:
		return
	_pax = null
	if not is_instance_valid(v):
		return
	var exit := vis.global_transform * (PAX_SEAT + Vector3(1.8, 0.0, 0.0))
	if world:
		exit.y = _gh(exit.x, exit.z) + 0.05
	v.global_position = exit
	v.collision_layer = 4
	v.collision_mask = 1 | 2 | 4 | 8 | 16
	v.visible = true
	v.set_physics_process(true)
	v.persona.add_friendship(owner_id, 8.0, world.clock.minutes if world.clock else 0.0,
		world.clock.jd() if world.clock else 0)
	var rep: Reputation = world.reputations.get(owner_id)
	if rep:
		rep.change(3.0, "svezl vesničana na vyhlídkový let")
	_notify("%s vystoupil%s. „To bylo parádní, díky!“ (+ přátelství, + pověst)" % [
		v.persona.display_name(), ": %s" % msg if msg != "" else ""], 4.0)
	world.emit_game_event(owner_id, "trike_ride_done", {"kdo": v.persona.display_name()})


## Vrátí spolujezdce (pro interakce / HUD).
func passenger() -> Villager:
	return _pax


# ------------------------------------------------------------------ tick: přistání, pravidla, bubliny

## Volá se z `_delayed_input` každý fyzikální krok (jako `Paramotor._pg_tick`):
## přechod vzduch→zem (přistání mimo letiště = přestupek + vysazení paxe),
## přestupkové kontroly za letu a bubliny spolujezdce.
func _ul_tick(dt: float) -> void:
	if pilot == null or world == null:
		return
	if on_ground:
		if _was_flying:
			_was_flying = false
			_on_landed()
		return
	if not _was_flying:
		_was_flying = true
		world.ul_training_takeoff(owner_id)               # výcvikový let (škola na PC)
	# bubliny spolujezdce
	if _pax != null and is_instance_valid(_pax):
		_pax_talk_t -= dt
		if _pax_talk_t <= 0.0:
			_pax_talk_t = randf_range(PAX_TALK_MIN, PAX_TALK_MAX)
			_notify("%s (za zády): „%s“" % [_pax.persona.display_name(),
				String(PAX_LINES[randi() % PAX_LINES.size()])], 4.0)
	elif _pax != null:
		_pax_off.call_deferred()                          # vesničan zmizel – uklidit i jeho postavu v sedadle
	_law_ul(dt)


## Dosednutí: mimo dráhu letiště = přestupek `ul_pristani_mimo` (svědek ~800 m),
## na dráze = pochvala. Spolujezdec se vysazuje sám.
func _on_landed() -> void:
	var pos := global_position
	var on_rwy := world.airfield != null and world.airfield.on_runway(pos)
	if not on_rwy and world.pg_noise_witnessed(pos):
		_law_offense("ul_pristani_mimo", true, {"pos": pos})
	elif not on_rwy:
		_notify("Přistání mimo letiště – nikdo to neviděl. (Mimo nouzi se přistává jen na letišti!)", 4.0)
	elif speed > 0.5:
		_notify("Přistání na dráze – hezká práce.", 3.0)
	if _pax != null:
		_pax_off.call_deferred()                        # běží z fyzikálního kroku – vysazení až po něm


## Přestupky UL (nad rámec alkoholu z `Aircraft._law_check`): bez průkazu / registrace / pojištění,
## nízko nad obcí, nad lidmi, v noci a mimo VFR podmínky. Svědek = hluk motoru ~800 m.
func _law_ul(dt: float) -> void:
	_law_ul_t += dt
	if _law_ul_t < UL_LAW_TICK:
		return
	_law_ul_t = 0.0
	var pos := global_position
	if not world.pg_noise_witnessed(pos):
		return
	var agl := pos.y - _gh(pos.x, pos.z)
	_law_offense("ul_bez_prukazu", not world.has_permit(owner_id, "pilot_ul", pos), {})
	_law_offense("ul_bez_registrace", not world.has_permit(owner_id, "ul_registrace", pos), {})
	_law_offense("ul_bez_pojisteni", not world.has_permit(owner_id, "ul_pojisteni", pos), {})   # A4-08
	_law_offense("ul_nizko_nad_obci", agl < UL_LOW_ALT and world.pg_over_village(pos), {"agl": agl})
	_law_offense("ul_nad_lidmi", world.drone_person_under(pos, UL_PERSON_R), {})
	_law_offense("ul_noc", world.clock.is_night() if world.clock else false, {})
	_law_offense("ul_mraky", world.weather != null and (world.weather.cloud > 0.75 or world.weather.fog > 0.5), {})


func _law_offense(oid: String, cond: bool, data: Dictionary) -> void:
	if not cond:
		return
	if _life_t - float(_off_cd.get(oid, -10000.0)) < OFF_CD * 1.5:
		return
	_off_cd[oid] = _life_t
	world.commit_offense(owner_id, oid, data)


# ------------------------------------------------------------------ model (MeshKit)

## Vizuál triku (`vis`: y = 0 zem pod koly, −Z vpřed, 1 j = 1 m): vozík s kapotáží příďové
## části, dvě sedadla za sebou, příďové řízené kolo + dvě hlavní, stožár a přední vzpěra,
## motor s tlačnou vrtulí, rogalo s náběžnými trubkami, kýlem, kingpostem, prohnutou
## plachtou (horní i spodní plocha s vlastními normálami) a řídicí hrazdou (A-rám).
func _build_mesh() -> void:
	var mk := MeshKit.new()
	var frame := Color(0.62, 0.64, 0.68)
	var dark := Color(0.15, 0.15, 0.17)
	var body := Color(0.75, 0.2, 0.15)      # kapotáž (červená – smyšlený stroj)
	var seat_c := Color(0.2, 0.2, 0.24)
	# vozík: kýlová trubka podvozku, kapotáž přídě, sedadla, stupačky spolujezdce
	rod(mk, Vector3(0, 0.38, -1.42), Vector3(0, 0.38, 0.85), 0.04, frame)
	mk.capsule(Vector3(0, 0.62, -0.95), 0.36, 1.3, body, Vector3(PI * 0.5, 0, 0), Vector3(0.95, 0.8, 1.0))
	mk.box(Vector3(0, 0.66, -0.3), Vector3(0.5, 0.12, 0.42), seat_c)                  # sedadlo pilota (vršek 0,72)
	mk.box(Vector3(0, 0.98, -0.06), Vector3(0.48, 0.5, 0.08), seat_c)                 # opěradlo pilota
	mk.box(Vector3(0, 0.82, 0.3), Vector3(0.5, 0.12, 0.42), seat_c)                   # sedadlo spolujezdce (vršek 0,88)
	mk.box(Vector3(0, 1.15, 0.54), Vector3(0.48, 0.55, 0.08), seat_c)                 # opěradlo spolujezdce
	rod(mk, Vector3(0, 0.38, 0.3), Vector3(0, 0.76, 0.3), 0.035, frame)               # sloupek sedadla
	for sx in [-1.0, 1.0]:
		rod(mk, Vector3(0, 0.42, -0.12), Vector3(sx * 0.32, 0.45, -0.12), 0.02, frame, 5)   # stupačky
	# hlavní podvozek: dvě kola na ramenech
	for sx in [-1.0, 1.0]:
		mk.cylinder(Vector3(sx * 0.8, 0.28, 0.25), 0.28, 0.28, 0.16, dark, Vector3(0, 0, PI * 0.5), 14)
		mk.cylinder(Vector3(sx * 0.8, 0.28, 0.25), 0.12, 0.12, 0.17, frame, Vector3(0, 0, PI * 0.5), 10)
		rod(mk, Vector3(sx * 0.1, 0.4, 0.05), Vector3(sx * 0.72, 0.3, 0.25), 0.025, frame, 6)
		rod(mk, Vector3(sx * 0.1, 0.4, 0.55), Vector3(sx * 0.72, 0.3, 0.25), 0.02, frame, 6)
	rod(mk, Vector3(0, 0.55, -1.42), Vector3(0, 0.26, -1.5), 0.03, frame)              # vidlice příďového kola
	# stožár (z vozíku za spolujezdcem k závěsu) a přední vzpěra (nad hlavou pilota)
	rod(mk, Vector3(0, 0.4, 0.85), HANG, 0.045, frame)
	rod(mk, Vector3(0, 0.55, -1.45), HANG + Vector3(0, -0.05, -0.1), 0.03, frame)
	# motor s chladičem a tlačnou vrtulí
	mk.box(Vector3(0, 0.95, 1.05), Vector3(0.5, 0.45, 0.5), dark)
	mk.box(Vector3(0, 1.25, 0.9), Vector3(0.3, 0.12, 0.2), Color(0.5, 0.5, 0.52))
	rod(mk, Vector3(0, 0.4, 0.8), Vector3(0, 0.8, 0.95), 0.035, frame)
	mk.cylinder(Vector3(0, 0.95, 1.33), 0.08, 0.08, 0.1, dark, Vector3(PI * 0.5, 0, 0), 10)
	var mi := MeshInstance3D.new()
	mi.mesh = mk.commit(MeshKit.vc_material(0.7))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	vis.add_child(mi)
	# rogalo + A-rám (uzel se závěsem v HANG)
	_wing = Node3D.new()
	_wing.position = HANG
	vis.add_child(_wing)
	var wmi := MeshInstance3D.new()
	wmi.mesh = _wing_mesh()
	wmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_wing.add_child(wmi)
	# příďové kolo (otáčí se s řízením) + tlačná vrtule
	_nw = MeshInstance3D.new()
	var nmk := MeshKit.new()
	nmk.cylinder(Vector3.ZERO, 0.22, 0.22, 0.12, dark, Vector3(0, 0, PI * 0.5), 12)
	_nw.mesh = nmk.commit(MeshKit.vc_material(0.6))
	_nw.position = Vector3(0, 0.22, -1.5)
	vis.add_child(_nw)
	_prop = MeshInstance3D.new()                                       # tlačná vrtule za motorem
	var pmk := MeshKit.new()
	pmk.box(Vector3.ZERO, Vector3(0.09, 1.6, 0.04), Color(0.1, 0.1, 0.1))
	_prop.mesh = pmk.commit(MeshKit.vc_material(0.6))
	_prop.position = Vector3(0, 0.95, 1.4)
	vis.add_child(_prop)
	# pilot vpředu: pánev ~6 cm nad sedákem, nohy na pedálech řízení v kapotáži, ruce na hrazdě
	seat_pos = Vector3(0, 0.72 + 0.06 - 0.5, -0.3)
	rider = rider_pose(seat_pos, 0.5, -0.05, BAR, Vector3(0, 0.42, -1.05))
	eye_pos = seat_pos + Vector3(0, 1.17, -0.05)
	# spolujezdec vzadu výš: nohy na stupačkách vedle sedadla pilota, ruce na pilotovi
	_pax_rider = rider_pose(PAX_SEAT, 0.5, -0.1, Vector3(0, 1.05, -0.05), Vector3(0, 0.45, -0.12))


## Bod plachty rogala vůči závěsu: `x` přes rozpětí, `u` 0..1 od náběžné k odtokové hraně.
## Prohnutí profilu (camber) nejvíc u kořene, k okrajům zkrut (washout – odtoková hrana výš).
func _sail_pt(x: float, u: float) -> Vector3:
	var s := absf(x) / SPAN_HALF
	var z_le := NOSE_Z + (TIP_LE_Z - NOSE_Z) * s
	var z_te := KEEL_TE_Z + (TIP_TE_Z - KEEL_TE_Z) * s
	var camber := 0.22 * (1.0 - 0.55 * s) * sin(PI * pow(u, 0.7))
	return Vector3(x, 0.05 + camber + 0.14 * s * u, lerpf(z_le, z_te, u))


## Rogalo: horní a spodní plocha (dva lofty s opačnými normálami – A2-10), náběžné trubky,
## kýl, kingpost s horními lanky, A-rám s hrazdou a spodními lanky.
func _wing_mesh() -> ArrayMesh:
	var wmk := MeshKit.new()
	var cloth := Color(0.95, 0.78, 0.2)
	var band := Color(0.8, 0.22, 0.16)
	var under := Color(0.86, 0.72, 0.3)
	var tube_c := Color(0.7, 0.72, 0.75)
	var wire := Color(0.55, 0.55, 0.58)
	const US := [0.0, 0.08, 0.25, 0.5, 0.75, 1.0]
	var top := []
	var bot := []
	var ctop := []
	var cbot := []
	for i in range(SAIL_ST + 1):
		var x := -SPAN_HALF + 2.0 * SPAN_HALF * float(i) / SAIL_ST
		var rt := PackedVector3Array()
		var rb := PackedVector3Array()
		var ct := []
		var cb := []
		for u in US:
			var p := _sail_pt(x, float(u))
			rt.append(p)
			rb.append(p - Vector3(0, 0.015, 0))
			ct.append(band if float(u) < 0.1 else cloth)
			cb.append(under)
		top.append(rt)
		bot.append(rb)
		ctop.append(ct)
		cbot.append(cb)
	wmk.loft(top, ctop, false)                  # horní plocha – normály nahoru
	wmk.loft(bot, cbot, false, true)            # spodní plocha – normály dolů
	# trubky: náběžné hrany, kýl, kingpost
	var nose := _sail_pt(0.0, 0.0)
	for sx in [-1.0, 1.0]:
		rod(wmk, nose, _sail_pt(sx * SPAN_HALF, 0.0), 0.035, tube_c, 8)
	rod(wmk, nose + Vector3(0, -0.04, -0.05), Vector3(0, 0.01, KEEL_TE_Z + 0.05), 0.035, tube_c, 8)
	var kp := Vector3(0, 0.8, -0.05)
	rod(wmk, Vector3(0, 0.05, -0.05), kp, 0.025, tube_c, 6)
	for sx in [-1.0, 1.0]:
		rod(wmk, kp, _sail_pt(sx * SPAN_HALF * 0.55, 0.0), 0.005, wire, 3)
	rod(wmk, kp, nose, 0.005, wire, 3)
	rod(wmk, kp, Vector3(0, 0.05, KEEL_TE_Z), 0.005, wire, 3)
	# A-rám: stojny ze závěsu k hrazdě, hrazda, spodní lanka k okrajům a kýlu
	var bar_l := BAR - HANG + Vector3(-BAR_HALF, 0, 0)
	var bar_r := BAR - HANG + Vector3(BAR_HALF, 0, 0)
	rod(wmk, Vector3(-0.06, -0.02, -0.08), bar_l, 0.025, tube_c, 6)
	rod(wmk, Vector3(0.06, -0.02, -0.08), bar_r, 0.025, tube_c, 6)
	rod(wmk, bar_l, bar_r, 0.028, Color(0.12, 0.12, 0.14), 8)
	for b in [bar_l, bar_r]:
		var sx: float = signf(b.x)
		rod(wmk, b, _sail_pt(sx * SPAN_HALF, 0.0), 0.005, wire, 3)
		rod(wmk, b, _sail_pt(sx * SPAN_HALF * 0.55, 0.0) - Vector3(0, 0.03, 0), 0.005, wire, 3)
		rod(wmk, b, nose, 0.005, wire, 3)
		rod(wmk, b, Vector3(0, 0.03, KEEL_TE_Z), 0.005, wire, 3)
	return wmk.commit(MeshKit.vc_material(0.8))


# ------------------------------------------------------------------ vizuál / HUD / save

func _process(delta: float) -> void:
	super._process(delta)
	# příďové kolo sleduje řízení na zemi (A = kolo i stroj doleva)
	if _nw and pilot_input and on_ground:
		_nw.rotation.y = lerpf(_nw.rotation.y, pilot_input.steer * 0.45, minf(delta * 6.0, 1.0))
	# spolujezdec: vesničan je skrytý, pozici držíme u stroje (viditelná je `_pax_vis` v sedadle)
	if _pax != null and is_instance_valid(_pax):
		_pax.global_position = vis.global_transform * PAX_SEAT


## Telemetrie navíc: poloha páky, nápověda hrazdy, spolujezdec, přistávací hint, VFR.
func status() -> Dictionary:
	var st := super.status()
	if st.is_empty():
		return st
	var warns: Array = st["warns"]
	if on_ground:
		warns.append("PÁČKA %d %% (Shift+/Ctrl−) · A/D příďové kolo · Mezerník brzda" % roundi(_lever * 100.0))
	elif float(st["agl"]) < LAND_HINT_AGL:
		warns.append("PŘISTÁNÍ: proti větru ~65 km/h, dosedni na hlavní kola")
	else:
		warns.append("HRAZDA: %s" % ("W nahoru · S dolů · A vlevo" if _intuitive
			else "realisticky – S nahoru/zpomalit · A zatáčka VPRAVO"))
	if _pax != null:
		warns.append("SPOLUJEZDEC: %s" % _pax.persona.display_name())
	if world and not world.has_permit(owner_id, "pilot_ul", global_position):
		warns.append("LETÍŠ BEZ PRŮKAZU ULL – pokuta, když tě uslyší!")
	if world and not world.has_permit(owner_id, "ul_pojisteni", global_position):
		warns.append("BEZ POJIŠTĚNÍ ODPOVĚDNOSTI – pokuta (PC → Letectví – ÚCL)")
	if world and world.clock and world.clock.is_night():
		warns.append("NOC – UL smí létat jen za dne (VFR)")
	elif world and world.weather and (world.weather.cloud > 0.75 or world.weather.fog > 0.5):
		warns.append("MIMO VFR – mraky / mlha, dohlednost špatná")
	st["warns"] = warns
	st["thr"] = _lever            # přístroj ukazuje polohu páky, ne vyhlazený tah
	return st


## Uložení – navíc vysadí spolujezdce (vesničan se neskládá do save, zůstane stát u stroje).
func save_dict() -> Dictionary:
	_pax_off("Ukládám hru.")
	return super.save_dict()
