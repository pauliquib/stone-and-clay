## Motorové rogalo / trike (M6.5) – podtřída `Aircraft` (model „trike“).
## Tříkolka (řízené příďové kolo + dvě hlavní), vozík s kapotáží, tlačná vrtule vzadu,
## stožár a trojúhelníkové rogalo (~15 m²). Dvě sedadla za sebou – druhé pro spolujezdce.
##
## ŘÍZENÍ HRAZDOU (weight-shift) – realisticky OBRÁCENÉ proti letadlu:
##   S = hrazdu od sebe → nos nahoru / zpomalit,  W = hrazdu k sobě → klesat / zrychlit,
##   A = hrazda doleva → zatáčka DOPRAVA (závaží jde doleva → křídlo padá vpravo).
## Přepínač „Intuitivní řízení rogala“ (Esc → Nastavení) mapuje arkádově: W = nahoru,
## A = vlevo. Plyn = PÁČKA, která drží polohu: Shift přidat, Ctrl ubrat.
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
const PAX_SEAT := Vector3(0.0, 0.72, 0.55)   # zadní sedadlo (lokální, vůči vis)

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
var _intuitive := false            # Esc → Nastavení: arkádové mapování hrazdy
var _pax: Villager                 # spolujezdec na zadním sedadle (vyhlídkový let)
var _pax_talk_t := 0.0             # odpočet do další bubliny
var _was_flying := false           # detekce přechodu vzduch → zem (přistání / pravidla)
var _law_ul_t := 0.0

var _nw: MeshInstance3D            # příďové kolo (vizuální řízení)
var _bar: Node3D                   # hrazda (houpne se podle vstupu)


# ------------------------------------------------------------------ vstup a řízení

## Vstup pilota → [plyn, klon, pitch]. Plyn drží páka (Shift/Ctrl), hrazda je obrácená:
## ve vzduchu W/S = k sobě / od sebe (pitch), na zemi Mezerník = brzda kol.
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
			# hrazda: S (od sebe) = nos nahoru; v intuitivním režimu W = nahoru
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


## Přepínač z nastavení klienta (výchozí = realistické řízení hrazdou).
func _read_intuitive() -> bool:
	if world == null:
		return false
	var cl = world.clients.get(owner_id)
	return cl != null and cl.settings != null and bool(cl.settings.trike_intuitive)


## Smysl zatáčení hrazdou: realisticky A = hrazda doleva = zatáčka vpravo.
func _bank_target(steer_in: float) -> float:
	var roll := float(spec["roll_max"])
	return (-steer_in * roll) if _intuitive else (steer_in * roll)


## Těžší stroj na trávě → delší rozjezd než letoun/běh.
func _mu_ground() -> float:
	return MU_TRIKE


## Hláška po vzletu – ovládání hrazdy (místo obecného textu letounu).
func _takeoff_hint() -> String:
	return ("Vzlet! Hrazda: W nahoru, A vlevo (intuitivní režim)." if _intuitive
		else "Vzlet! Hrazda: S nos NAHORU / zpomalit, W klesat · A/D zatáčí OBRÁCENĚ · Shift/Ctrl páka.")


## Celková vzletová hmotnost navíc o spolujezdce (~80 kg).
func total_kg() -> float:
	return super.total_kg() + (80.0 if _pax != null else 0.0)


# ------------------------------------------------------------------ stavy pilota a spolujezdec

func set_pilot(p: Player) -> void:
	super.set_pilot(p)
	_lever = 0.0
	_notify("%s – páka plynu: Shift přidat, Ctrl ubrat (drží polohu). Hrazda: S nos NAHORU, " % String(spec.get("name", model))
		+ "W klesat/rychleji, A/D zatáčí OBRÁCENĚ (A = doprava). Na zemi A/D příďové kolo, Mezerník brzda.", 8.0)


func clear_pilot() -> void:
	_pax_off("Pilot vystoupil – let končí.")
	super.clear_pilot()
	_lever = 0.0


## Nastoupení spolujezdce na zadní sedadlo (volá `World.ul_board_passenger`).
func board_passenger(v: Villager) -> void:
	_pax = v
	_pax_talk_t = 8.0
	v.set_physics_process(false)
	v.visible = false
	v.collision_layer = 0
	v.collision_mask = 0


## Vysazení spolujezdce vedle stroje (přistání, vystoupení pilota, uložení).
func _pax_off(msg := "") -> void:
	var v := _pax
	if v == null:
		return
	_pax = null
	if not is_instance_valid(v):
		return
	var exit := global_transform * (PAX_SEAT + Vector3(1.8, 0.0, 0.0))
	if world and world.terrain:
		exit.y = world.terrain.height_at(exit.x, exit.z) + 0.05
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
		_pax = null
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
		_pax_off()


## Přestupky UL (nad rámec alkoholu z `Aircraft._law_check`): bez průkazu / registrace,
## nízko nad obcí, nad lidmi, v noci a mimo VFR podmínky. Svědek = hluk motoru ~800 m.
func _law_ul(dt: float) -> void:
	_law_ul_t += dt
	if _law_ul_t < UL_LAW_TICK:
		return
	_law_ul_t = 0.0
	var pos := global_position
	if not world.pg_noise_witnessed(pos):
		return
	var gy := world.terrain.height_at(pos.x, pos.z) if world.terrain else pos.y
	var agl := pos.y - gy
	_law_offense("ul_bez_prukazu", not world.has_permit(owner_id, "pilot_ul", pos), {})
	_law_offense("ul_bez_registrace", not world.has_permit(owner_id, "ul_registrace", pos), {})
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

## Vizuál triku: vozík s kapotáží a dvěma sedadly, příďové řízené kolo, dvě hlavní kola,
## motor s tlačnou vrtulí vzadu, stožár a trojúhelníkové rogalo (plachtovina + lanka + hrazda).
func _build_mesh() -> void:
	seat_pos = Vector3(0, 0.62, -0.35)   # přední sedadlo (pilot) – vůči vis
	var mk := MeshKit.new()
	var frame := Color(0.3, 0.32, 0.36)
	var dark := Color(0.15, 0.15, 0.17)
	var body := Color(0.75, 0.2, 0.15)      # kapotáž (červená – smyšlený stroj)
	var cloth := Color(0.9, 0.75, 0.2)      # plachtovina rogala
	mk.box(Vector3(0, 0.55, -0.4), Vector3(0.85, 0.42, 2.2), body)                 # vozík / kapotáž
	mk.box(Vector3(0, 0.72, -1.15), Vector3(0.55, 0.35, 0.5), body)                # příď
	mk.box(Vector3(0, 0.62, -0.35), Vector3(0.6, 0.25, 0.5), dark)                 # sedadlo pilota
	mk.box(Vector3(0, 0.72, 0.55), Vector3(0.6, 0.25, 0.5), dark)                  # sedadlo spolujezdce
	mk.box(Vector3(0, 0.78, -0.72), Vector3(0.4, 0.18, 0.22), Color(0.12, 0.14, 0.18))  # palubovka
	mk.box(Vector3(0, 1.15, 0.95), Vector3(0.55, 0.6, 0.45), dark)                 # motor vzadu
	mk.box(Vector3(0, 1.7, 0.15), Vector3(0.08, 1.9, 0.08), frame)                 # stožár křídla
	# hlavní podvozek (dvě kola) + noha příďového kola
	for wp in [Vector3(-0.75, 0.3, 0.35), Vector3(0.75, 0.3, 0.35)]:
		mk.cylinder(wp, 0.3, 0.3, 0.2, dark, Vector3(0, 0, PI * 0.5), 12)
		mk.box(Vector3(wp.x * 0.5, 0.55, 0.35), Vector3(0.05, 0.55, 0.05), frame)
	mk.box(Vector3(0, 0.45, -1.15), Vector3(0.05, 0.6, 0.05), frame)               # noha příďového kola
	# rogalo: delta plachtovina (dva trojúhelníkové panely přes rozpětí ~9,6 m) nad strojem
	var wmi := MeshInstance3D.new()
	var wing := MeshKit.new()
	for side in [-1.0, 1.0]:
		wing.add_arrays(_wing_panel(side), Transform3D.IDENTITY, cloth)
	wmi.mesh = wing.commit(MeshKit.vc_material(0.85, 0.0, 0.0, false))
	wmi.position = Vector3(0, 2.6, 0.1)
	wmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	vis.add_child(wmi)
	# lanka a A-hrazda pod křídlem
	var lmk := MeshKit.new()
	_pg_rope(lmk, Vector3(-4.4, 2.58, 0.35), Vector3(0, 1.05, -0.2), frame)
	_pg_rope(lmk, Vector3(4.4, 2.58, 0.35), Vector3(0, 1.05, -0.2), frame)
	lmk.box(Vector3(-0.55, 1.5, -0.2), Vector3(0.05, 1.0, 0.05), frame, Vector3(0, 0, -0.5))  # nohy A-hrazdy
	lmk.box(Vector3(0.55, 1.5, -0.2), Vector3(0.05, 1.0, 0.05), frame, Vector3(0, 0, 0.5))
	var lmi := MeshInstance3D.new()
	lmi.mesh = lmk.commit(MeshKit.vc_material(0.6))
	vis.add_child(lmi)
	var mi := MeshInstance3D.new()
	mi.mesh = mk.commit(MeshKit.vc_material(0.7))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	vis.add_child(mi)
	# hrazda (tyč mezi nohama, za niž pilot tahá) – samostatný uzel kvůli náklonu
	_bar = Node3D.new()
	_bar.position = Vector3(0, 1.02, -0.2)
	vis.add_child(_bar)
	var bmk := MeshKit.new()
	bmk.box(Vector3.ZERO, Vector3(1.15, 0.05, 0.05), dark)
	var bmi := MeshInstance3D.new()
	bmi.mesh = bmk.commit(MeshKit.vc_material(0.5))
	_bar.add_child(bmi)
	# příďové kolo (otáčí se s řízením) + tlačná vrtule
	_nw = MeshInstance3D.new()
	var nmk := MeshKit.new()
	nmk.cylinder(Vector3.ZERO, 0.28, 0.28, 0.14, dark, Vector3(0, 0, PI * 0.5), 12)
	_nw.mesh = nmk.commit(MeshKit.vc_material(0.6))
	_nw.position = Vector3(0, 0.28, -1.3)
	vis.add_child(_nw)
	_prop = MeshInstance3D.new()                                       # tlačná vrtule za motor
	var pmk := MeshKit.new()
	pmk.box(Vector3.ZERO, Vector3(0.07, 1.5, 0.04), Color(0.1, 0.1, 0.1))
	pmk.box(Vector3.ZERO, Vector3(1.5, 0.07, 0.04), Color(0.1, 0.1, 0.1))
	_prop.mesh = pmk.commit(MeshKit.vc_material(0.6))
	_prop.position = Vector3(0, 1.15, 1.28)
	vis.add_child(_prop)


## Jedna polovina delta plachtoviny (kýl uprostřed → konec křídla ~4,8 m);
## vrací pole mesh-polí pro `MeshKit.add_arrays` (materiál bez cullingu – vidět i zespoda).
func _wing_panel(side: float) -> Array:
	var k1 := Vector3(0, 0, -1.1)          # nos u kýlu
	var k2 := Vector3(0, 0, 1.6)           # zadní bod u kýlu
	var tip := Vector3(side * 4.8, 0.0, 0.35)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([k1, k2, tip])
	arr[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP])
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2] if side > 0.0 else [0, 2, 1])
	return arr


## Tenký váleček lana mezi body a→b (stejný trik jako `Paramotor._rope`).
func _pg_rope(mk: MeshKit, a: Vector3, b: Vector3, color: Color) -> void:
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
	# příďové kolo sleduje řízení na zemi
	if _nw and pilot_input and on_ground:
		_nw.rotation.y = lerpf(_nw.rotation.y, -pilot_input.steer * 0.45, minf(delta * 6.0, 1.0))
	# hrazda: náklon podle vstupu (vizuální zpětná vazba řízení)
	if _bar:
		var tx := 0.0
		var tz := 0.0
		if pilot_input and not on_ground:
			var bar := pilot_input.brake - pilot_input.throttle
			tx = bar * 0.2 * (-1.0 if _intuitive else 1.0)
			tz = pilot_input.steer * 0.15 * (-1.0 if _intuitive else 1.0)
		_bar.rotation.x = lerpf(_bar.rotation.x, tx, minf(delta * 6.0, 1.0))
		_bar.rotation.z = lerpf(_bar.rotation.z, tz, minf(delta * 6.0, 1.0))
	# spolujezdec sedí vzadu (postava skrytá – pozici držíme pro jistotu u stroje)
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
		warns.append("HRAZDA: %s" % ("W nahoru · A vlevo (intuitivní)" if _intuitive
			else "S nahoru/zpomalit · A zatáčka VPRAVO"))
	if _pax != null:
		warns.append("SPOLUJEZDEC: %s" % _pax.persona.display_name())
	if world and not world.has_permit(owner_id, "pilot_ul", global_position):
		warns.append("LETÍŠ BEZ PRŮKAZU ULL – pokuta, když tě uslyší!")
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
