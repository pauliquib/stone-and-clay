## Správce interiérů (M1.8), jeden uzel ve `World` (`World.interior_streamer`). Interiér se staví, jen když je hráč u dveří
## (do `BUILD_R`), stavba se rozloží do snímků (jeden krok = jedna místnost za snímek, `Interior.build_step`), a ruší se,
## když se hráč vzdálí na víc než `FREE_R` a není uvnitř. Postavených (i rozestavěných) je nejvýš `MAX_BUILT`.
##
## - **Pevné interiéry** (domov M1.4 / M1.7, veřejné budovy M1.5) mají stálé sloty 0–6 jako dřív (uložené pozice uvnitř platí).
## - **Generované** (`InteriorGen`): každá nemovitost z `Estate` s dveřmi, která není místem z pois.json – id interiéru "b:<id>",
##   druh podle typu: rodinný dům `gen_house`, bytový dům `gen_flats` (i usedlost s podnájmem), hospodářská `gen_hall`.
## - **Mapové** (Fáze 2, `MapInteriors` / FuncGodot): pevný veřejný interiér, ke kterému existuje `data/maps/<místo>.map`,
##   má druh `qodot` – staví se z .map místo `PublicInteriors` (chybí-li mapa/addon, padá zpět na procedurální).
##   Slot podle pořadí id → stálé souřadnice pod mapou (`World.INTERIOR_BASE`, mřížka `COLS` × `World.INTERIOR_STEP`).
##   Veřejná budova bez místa (kostel…) má jen zamčené dveře.
## - **Přístup** (`access`): bytový dům (chodba) otevřený; vlastní byt → „domov“, cizí byt zamčený (zazvonit); hospodářská budova
##   otevřená u usedlosti / domova (`LOT_R`), jinak zamčená; cizí rodinný dům jen s pozváním (zaklepat → obyvatel otevře podle
##   nálady, přátelství, pověsti a denní doby). Vloupání není (hák: událost "trespass", M4.4).
## - **Obyvatelé**: cizí dům obývá vesničan (`Characters` přes Personu vesničana, dům dědy děda), doma podle hodiny
##   (`HOME_PROB`, stejné v rámci 3 h). Když je doma, sedí u stolu v kuchyni (`Npc`, jen když je hráč uvnitř).
##
## API: `setup(world, parent)`, `add_estates(estate)`, `ensure(iid)`, `set_home(title, flat)`, `door_interactables(pid)`,
## `entry_for(pid, iid)`, `may_enter(pid, iid)`, `exit_to_stairs(pid, iid, fade)`, `on_enter(player, iid)`, `grant_invite`,
## `gen_id(estate_id)`, `built_count()`.
class_name InteriorStreamer
extends Node

# ------------------------------------------------------------------ laditelné hodnoty

const BUILD_R := 8.0                # m od dveří – začne se stavět
const FREE_R := 25.0                # m od dveří – zruší se (když hráč není uvnitř)
const MAX_BUILT := 3                # nejvýš postavených / rozestavěných interiérů najednou
const CHECK_S := 0.25               # s – jak často se přepočítá, co stavět / rušit
const DOOR_R := 2.4                 # m – dosah E u dveří generované budovy
const GRID := 32.0                  # m – buňka mřížky dveří (hledání blízkých)
const COLS := 32                    # sloupců mřížky slotů pod mapou
const FIXED := [["domov", "domov"], ["hospoda", "hospoda"], ["obchod", "obchod"], ["urad", "urad"],
	["palenice", "palenice"], ["sklep", "sklep"], ["chata", "chata"]]
const GEN_KIND := {"rodinny_dum": "gen_house", "bytovy_dum": "gen_flats", "hospodarska": "gen_hall"}
const HALL_NAME := {"barn": "Stodola", "garage": "Garáž", "hall": "Hala", "shed": "Kůlna"}
const LOT_R := 60.0                 # m – hospodářské budovy tak blízko usedlosti / domova jsou „tvoje“ (otevřené)
const INHABITED := 0.7              # podíl obydlených cizích domů / bytů
## Pravděpodobnost, že je obyvatel doma, podle hodiny (lineárně mezi body).   # DOPLNIT: odhad, doladit podle pocitu
const HOME_PROB := [[0.0, 0.92], [6.0, 0.85], [8.0, 0.45], [12.0, 0.55], [16.0, 0.5], [18.0, 0.8], [22.0, 0.92], [24.0, 0.92]]
const NIGHT := [22.0, 6.0]          # v noci otevře jen dobrý přítel
const KNOCK_BASE := 0.35            # základní šance, že obyvatel otevře a pozve dál
const KNOCK_MOOD := 0.4             # × nálada vůči hráči (−1..1)
const KNOCK_FRIEND := 0.6           # × přátelství / 100
const KNOCK_REP := 0.004            # × pověst (−100..100)
const KNOCK_NIGHT := -0.45
const KNOCK_AGAIN := -0.25          # znovu do hodiny = dotěrnost
const KNOCK_AGAIN_MOOD := -0.1
const KNOCK_COOLDOWN_MIN := 60.0    # herní minuty
const INVITE_MIN := 180.0           # herní minuty, po které platí pozvání
const TRESPASS_GRACE_S := 6.0       # s – po vypršení pozvání obyvatel hráče vyprovodí
const FRIEND_VISIT := 1.0           # přátelství za posezení u stolu (max. 1× za den, viz Persona)
const SIT_S := 6.0                  # s – jak dlouho host sedí u stolu

# ------------------------------------------------------------------ stav

var world: World
var root: Node3D
var specs := {}                     # iid → {iid, kind, eid, slot, door (Vector3, jen generované)}
var _grid := {}                     # Vector2i → Array[iid] (generované podle dveří)
var _building: Interior = null      # právě rozestavěný interiér (jeden krok za snímek)
var _t := 0.0
var _near := {}                     # pid → Array[iid]: generované budovy, jejichž dveře jsou do BUILD_R
var _invites := {}                  # pid → {eid: herní minuty konce pozvání}
var _knock_t := {}                  # "pid:eid" → herní minuty posledního klepání
var _trespass := {}                 # pid → s uvnitř bez pozvání
var _home_title := ""
var _home_flat := false


func setup(w: World, parent: Node3D) -> void:
	world = w
	root = parent
	name = "Interiery_sprava"
	for i in FIXED.size():
		var f: Array = FIXED[i]
		var iid: String = f[0]
		var kind := String(f[1])
		# Fáze 2: veřejná budova s .map (data/maps/<místo>.map) a addonem FuncGodot → mapový interiér
		if iid != "domov" and MapInteriors.has_map(iid):
			kind = "qodot"
		specs[iid] = {"iid": iid, "kind": kind, "eid": 0, "slot": i, "door": Vector3.INF}


## Generované interiéry ze všech nemovitostí s dveřmi (volá World.build po Estate.setup).
func add_estates(est: Estate) -> void:
	var ids: Array = est.estates.keys()
	ids.sort()
	var slot := FIXED.size()
	for id_v in ids:
		var eid: int = id_v
		var e: Dictionary = est.estates[id_v]
		var door: Vector3 = e["door"]
		if door == Vector3.INF or String(e["place"]) != "":
			continue
		var typ: String = e["type"]
		var kind: String = GEN_KIND.get(typ, "")
		if int(e["flats"]) > 0:
			kind = "gen_flats"
		var iid := gen_id(eid)
		specs[iid] = {"iid": iid, "kind": kind, "eid": eid, "slot": slot, "door": door}
		slot += 1
		var c := _cell(door)
		if not _grid.has(c):
			_grid[c] = []
		(_grid[c] as Array).append(iid)


static func gen_id(eid: int) -> String:
	return "b:%d" % eid


func _cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / GRID), floori(p.z / GRID))


func _origin(slot: int) -> Vector3:
	return World.INTERIOR_BASE + Vector3(World.INTERIOR_STEP * float(slot % COLS), 0.0,
		World.INTERIOR_STEP * float(floori(float(slot) / float(COLS))))


## Dveře interiéru venku (bod, od kterého se měří vzdálenost hráče).
func door_of(iid: String) -> Vector3:
	var sp: Dictionary = specs.get(iid, {})
	if sp.is_empty():
		return Vector3.INF
	var d: Vector3 = sp["door"]
	if d != Vector3.INF:
		return d
	return world.interior_exit(iid)[0]


func built_count() -> int:
	return world.interiors.size()


# ------------------------------------------------------------------ stavba a rušení

func _process(delta: float) -> void:
	if world == null:
		return
	if _building != null:
		if not is_instance_valid(_building):
			_building = null
		elif _building.build_step():
			_building = null
	_t -= delta
	if _t > 0.0:
		return
	_t = CHECK_S
	_update()
	_check_trespass(CHECK_S)


func _update() -> void:
	var want := {}                  # iid → vzdálenost (−1 = hráč uvnitř)
	for pid_v in world.players:
		var pid: int = pid_v
		var p: Player = world.players[pid_v]
		var wp := world.player_world_pos(p)
		if p.inside != "":
			want[p.inside] = -1.0
		var near: Array = []
		for iid_v in _candidates(wp):
			var iid: String = iid_v
			var dd := wp.distance_to(door_of(iid))
			if dd >= BUILD_R:
				continue
			if int(specs[iid]["eid"]) != 0:
				near.append(iid)
			if _buildable(iid, pid):
				want[iid] = minf(float(want.get(iid, INF)), dd)
		_near[pid] = near
	# zrušit vzdálené (hráč není uvnitř ani do FREE_R)
	for iid_v in world.interiors.keys():
		var iid: String = iid_v
		if not want.has(iid) and _dist(iid) > FREE_R:
			_free(iid)
	if _building != null:
		return
	# postavit nejbližší chybějící (jeden naráz)
	var best := ""
	var bd := INF
	for iid_v in want:
		var iid: String = iid_v
		if world.interiors.has(iid):
			continue
		var dd: float = want[iid_v]
		if dd < bd:
			bd = dd
			best = iid
	if best == "":
		return
	if not _make_room(bd):
		return
	_building = _start(best)


## Kandidáti do blízkosti bodu: pevné interiéry + generované z okolních buněk mřížky.
func _candidates(p: Vector3) -> Array:
	var out: Array = []
	for f in FIXED:
		out.append(String(f[0]))
	var c := _cell(p)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var k := Vector2i(c.x + dx, c.y + dz)
			if _grid.has(k):
				out.append_array(_grid[k])
	return out


## Stavět? Jen druhy s interiérem; vlastní rodinný dům hráče pokrývá interiér „domov“.
func _buildable(iid: String, pid: int) -> bool:
	var sp: Dictionary = specs[iid]
	if String(sp["kind"]) == "":
		return false
	var eid: int = sp["eid"]
	if eid != 0 and world.estate and eid == world.estate.home_estate(pid) and not world.estate.is_flat(pid):
		return false
	return true


## Nejmenší vzdálenost hráče od dveří interiéru (−1 = někdo je uvnitř).
func _dist(iid: String) -> float:
	var best := INF
	var door := door_of(iid)
	for p in world.players.values():
		var pl: Player = p
		if pl.inside == iid:
			return -1.0
		best = minf(best, world.player_world_pos(pl).distance_to(door))
	return best


## Uvolní místo pro nový interiér (vzdálenost `for_dist`): při plném počtu zruší nejvzdálenější neobsazený, který je dál.
## Obsazený (hráč uvnitř) se nikdy neruší.
func _make_room(for_dist: float) -> bool:
	while world.interiors.size() >= MAX_BUILT:
		var worst := ""
		var wd := for_dist
		for iid_v in world.interiors.keys():
			var iid: String = iid_v
			var dd := _dist(iid)
			if dd >= 0.0 and dd > wd:
				wd = dd
				worst = iid
		if worst == "":
			return false
		_free(worst)
	return true


func _start(iid: String) -> Interior:
	var sp: Dictionary = specs[iid]
	var it := Interior.make(world, iid, String(sp["kind"]), _origin(int(sp["slot"])))
	it.estate_id = int(sp["eid"])
	if iid == "domov":
		it.title = _home_title
		it.flat = _home_flat
	root.add_child(it)
	world.interiors[iid] = it
	it.begin_build()
	return it


func _free(iid: String) -> void:
	var it: Interior = world.interiors.get(iid)
	world.interiors.erase(iid)
	if it == null:
		return
	if _building == it:
		_building = null
	it.queue_free()


## Interiér hned k dispozici (vstup, načtení hry, F2): postaví / dostaví ho naráz. false = takový interiér není.
func ensure(iid: String) -> bool:
	if world.interiors.has(iid):
		var it: Interior = world.interiors[iid]
		if not it.built:
			it.build()
			if _building == it:
				_building = null
		return true
	if not specs.has(iid) or String(specs[iid]["kind"]) == "":
		return false
	_make_room(-0.5)                 # při plném počtu zruš nejvzdálenější neobsazený (klidně i bližší); jinak dočasně o 1 víc
	if _building != null and is_instance_valid(_building):
		_building.build()            # rozestavěný dokončit, ať se nekříží
	_building = null
	var nit := _start(iid)
	nit.build()
	return true


## Domov (M1.7): titulek a byt / dům – uloží se pro příští stavbu, postavený interiér se případně přestaví.
func set_home(title: String, flat: bool) -> void:
	_home_title = title
	_home_flat = flat
	var it: Interior = world.interiors.get("domov")
	if it:
		it.set_home(title, flat)
		if _building == it and it.built:
			_building = null


# ------------------------------------------------------------------ dveře, přístup, klepání

## Dveře generovaných budov u hráče (E): vstup, zamčeno, zaklepat. Vlastní dům / bytový dům řeší místo „domov“.
func door_interactables(pid: int) -> Array:
	var out := []
	var p: Player = world.players.get(pid)
	if p == null or p.inside != "":
		return out
	var home_eid := world.estate.home_estate(pid) if world.estate else 0
	for iid_v in _near.get(pid, []):
		var iid: String = iid_v
		var sp: Dictionary = specs[iid]
		var eid: int = sp["eid"]
		if eid == home_eid:
			continue
		out.append({"pos": sp["door"], "r": DOOR_R, "kind": "custom", "text": _door_text(pid, iid),
			"action": door_action.bind(iid)})
	return out


func _name(eid: int) -> String:
	var e: Dictionary = world.estate.info(eid) if world.estate else {}
	var kind := String(e.get("kind", ""))
	if int(e.get("no", 0)) <= 0 and HALL_NAME.has(kind):
		return String(HALL_NAME[kind])
	return world.estate.label(eid) if world.estate else "budova"


func _door_text(pid: int, iid: String) -> String:
	var sp: Dictionary = specs[iid]
	var eid: int = sp["eid"]
	match access(pid, iid):
		"open":
			if String(sp["kind"]) == "gen_flats":
				return "Vchod do domu – %s" % _name(eid)
			return "Vejít – %s" % _name(eid)
		"knock":
			return "Dveře – %s (zamčeno, zaklepat)" % _name(eid)
	return "Dveře – %s (zamčeno)" % _name(eid)


## "open" = smí dovnitř, "knock" = zamčeno, ale dá se zaklepat, "locked" = zamčeno.
func access(pid: int, iid: String) -> String:
	var sp: Dictionary = specs.get(iid, {})
	if sp.is_empty():
		return "locked"
	var eid: int = sp["eid"]
	match String(sp["kind"]):
		"gen_flats":
			return "open"
		"gen_hall":
			return "open" if _hall_is_mine(pid, eid) else "locked"
		"gen_house":
			return "open" if invited(pid, eid) else "knock"
	return "locked"


func _hall_is_mine(pid: int, eid: int) -> bool:
	if world.estate == null:
		return false
	var e := world.estate.info(eid)
	var c: Vector2 = e.get("center", Vector2.ZERO)
	var lot := world.lot_door()
	var hd := world.estate.home_door(pid)
	if c.distance_to(Vector2(lot.x, lot.z)) < LOT_R:
		return true
	return hd != Vector3.INF and c.distance_to(Vector2(hd.x, hd.z)) < LOT_R


func invited(pid: int, eid: int) -> bool:
	var inv: Dictionary = _invites.get(pid, {})
	return float(inv.get(eid, -1.0)) > world.clock.minutes


func grant_invite(pid: int, iid: String) -> void:
	var sp: Dictionary = specs.get(iid, {})
	if sp.is_empty() or String(sp["kind"]) != "gen_house":
		return
	if not _invites.has(pid):
		_invites[pid] = {}
	_invites[pid][int(sp["eid"])] = world.clock.minutes + INVITE_MIN


## E u dveří generované budovy.
func door_action(pid: int, iid: String) -> void:
	match access(pid, iid):
		"open":
			world.enter_interior(pid, iid)
		"knock":
			var eid: int = specs[iid]["eid"]
			world.notify(pid, "open_menu", ["Dveře – %s" % _name(eid),
				"Zamčeno. Do cizího domu se chodí jen na pozvání – můžeš zaklepat.", [["Zaklepat", knock.bind(pid, iid)]]])
		_:
			world.notify(pid, "show_message", ["Zamčeno.", 2.0])


## Vstup přes World.enter_interior: domov v bytě → nejdřív chodba bytového domu (M1.8).
func entry_for(pid: int, iid: String) -> String:
	if iid != "domov" or world.estate == null or not world.estate.is_flat(pid):
		return iid
	var st := gen_id(world.estate.home_estate(pid))
	if specs.has(st) and String(specs[st]["kind"]) == "gen_flats":
		return st
	return iid


## World._may_enter pro generované interiéry.
func may_enter(pid: int, iid: String) -> bool:
	if access(pid, iid) == "open":
		return true
	world.notify(pid, "show_message", ["Zamčeno.", 2.0])
	return false


## Zaklepání: obyvatel (je-li doma) otevře a pozve dál podle nálady, přátelství, pověsti a hodiny. Hák pro M4.5 (návštěvy).
func knock(pid: int, iid: String) -> void:
	var eid: int = specs[iid]["eid"]
	var now := world.clock.minutes
	var key := "%d:%d" % [pid, eid]
	var again := now - float(_knock_t.get(key, -99999.0)) < KNOCK_COOLDOWN_MIN
	_knock_t[key] = now
	world.play_sfx(pid, "door", 1.7, -3.0)
	world.notify(pid, "show_message", ["Klep, klep…", 1.5])
	await get_tree().create_timer(1.4).timeout
	var r := resident_of(eid, 0)
	var per: Persona = r.get("persona")
	var opened := false
	if per == null or not bool(r.get("home", false)):
		world.notify(pid, "show_message", ["Nikdo neotvírá.", 2.5])
	else:
		opened = _answer(pid, per, again, "(ve dveřích)")
	world.emit_game_event(pid, "knocked", {"estate": eid, "opened": opened})
	if opened:
		grant_invite(pid, iid)
		await get_tree().create_timer(0.8).timeout
		var p: Player = world.players.get(pid)
		if p and p.inside == "" and p.global_position.distance_to(door_of(iid)) < DOOR_R + 2.0:
			world.enter_interior(pid, iid)
		else:
			world.notify(pid, "show_message", ["Pozvání platí %d herní hodiny – stačí přijít ke dveřím (E)." % roundi(INVITE_MIN / 60.0), 3.0])


## Odpověď obyvatele na klepání / zvonek; vrací true = otevře a pozve dál.
func _answer(pid: int, per: Persona, again: bool, where: String) -> bool:
	var now := world.clock.minutes
	if again:
		per.add_mood(pid, KNOCK_AGAIN_MOOD, now)
	var mood := per.get_mood(pid, now)
	var fr := per.get_friendship(pid)
	var rep: Reputation = world.reputations.get(pid)
	var score := rep.score if rep else 0.0
	var h := world.clock.hour()
	var night := h >= float(NIGHT[0]) or h < float(NIGHT[1])
	var chance := KNOCK_BASE + mood * KNOCK_MOOD + fr / 100.0 * KNOCK_FRIEND + score * KNOCK_REP
	if night and fr < Persona.FRIEND_HIGH:
		chance += KNOCK_NIGHT
	if again:
		chance += KNOCK_AGAIN
	var ok := randf() < clampf(chance, 0.02, 0.95)
	var line := "„Pojďte dál, sousede.“"
	if not ok:
		if again:
			line = "„Pořád klepete? Nechte mě být!“"
		elif night:
			line = "„V tuhle hodinu? Přijďte zítra.“"
		elif mood < -0.2 or score < -30.0:
			line = "„S vámi nemám o čem mluvit.“"
		else:
			line = "„Teď se to nehodí, promiňte.“"
	elif fr >= Persona.FRIEND_HIGH:
		line = "„No ahoj, pojď dál, zrovna vařím kafe!“"
	world.notify(pid, "show_message", ["%s %s: %s" % [per.display_name(), where, line], 4.0])
	return ok


## Obyvatel nemovitosti (`flat` = číslo bytu, 0 = dům): {persona, home} nebo {} (neobydleno). Usedlost je prázdná (M4.7).
func resident_of(eid: int, flat: int) -> Dictionary:
	var est := world.estate
	if est == null or eid == est.lot_id:
		return {}
	var per: Persona = null
	if flat == 0 and eid == est.deda_id and world.npcs.has("deda"):
		per = (world.npcs["deda"] as Npc).persona
	else:
		var hsh := absi(hash("%d:%d" % [eid, flat]))
		if float(hsh % 1000) / 1000.0 >= INHABITED:
			return {}
		per = _villager_persona(floori(float(hsh) / 1000.0))
	if per == null:
		return {}
	return {"persona": per, "home": _home_now(eid, flat)}


func _villager_persona(i: int) -> Persona:
	var vs: Array = []
	for v in world.bots_root.get_children():
		if v is Villager:
			vs.append(v)
			if vs.size() >= World.N_VILLAGERS:      # víkendoví vesničané navíc se nepočítají (stálé přiřazení)
				break
	if vs.is_empty():
		return null
	return (vs[i % vs.size()] as Villager).persona


func _home_now(eid: int, flat: int) -> bool:
	var h := world.clock.hour()
	var prob := 0.9
	for i in range(1, HOME_PROB.size()):
		var a: Array = HOME_PROB[i - 1]
		var b: Array = HOME_PROB[i]
		if h <= float(b[0]):
			prob = lerpf(float(a[1]), float(b[1]), (h - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.001))
			break
	var blk := world.clock.jd() * 8 + floori(h / 3.0)
	var r := float(absi(hash("%d:%d:%d" % [eid, flat, blk])) % 1000) / 1000.0
	return r < prob


# ------------------------------------------------------------------ uvnitř: obyvatel, stůl, schody, byty

## Volá World.interior_mark: v cizím domě posadí obyvatele ke stolu (je-li doma), jinak ho schová.
func on_enter(pl: Player, iid: String) -> void:
	var it: Interior = world.interiors.get(iid)
	if it == null or it.kind != "gen_house":
		return
	var r := resident_of(it.estate_id, 0)
	var per: Persona = r.get("persona")
	var home := per != null and bool(r.get("home", false))
	for o in it.objects.duplicate():
		if String(o["key"]) == "resident":
			it.objects.erase(o)
	if not home or not it.spots.has("res_seat"):
		if it.resident and is_instance_valid(it.resident):
			it.resident.visible = false
		return
	var sp: Array = it.spots["res_seat"]
	var local := it.to_local(sp[0] as Vector3)
	if it.resident == null or not is_instance_valid(it.resident) or it.resident.persona != per:
		if it.resident and is_instance_valid(it.resident):
			it.resident.queue_free()
		var n := Npc.make(per.display_name(), "", Color.WHITE, absi(it.estate_id), local, float(sp[1]) + PI, world, true)
		Characters.apply_look(n.visual, per.profile)
		n.persona = per
		n.role = "resident"
		n.face_player = false
		it.add_child(n)
		it.resident = n
	it.resident.visible = true
	it.add_object(local + Vector3(0, 0, 0.9), 1.4, "resident", "%s (promluvit)" % per.display_name())
	it.resident.say("Posaďte se, ať nám tu nestojíte." if invited(pl.id, it.estate_id) else "Co tady děláte?!", 3.5)


## Posedět u stolu (host v cizím domě): posadí hráče na židli, obyvatel se potěší (přátelství).
func sit(pid: int, iid: String) -> void:
	var p: Player = world.players.get(pid)
	var it: Interior = world.interiors.get(iid)
	if p == null or it == null or not it.spots.has("guest_seat") or p.controls_locked or p.busy:
		return
	var sp: Array = it.spots["guest_seat"]
	p.teleport(sp[0] as Vector3, float(sp[1]), false)
	p.controls_locked = true
	p.visual.pose = "sit"
	var host: Npc = it.resident if it.resident and is_instance_valid(it.resident) and it.resident.visible else null
	if host:
		host.persona.add_friendship(pid, FRIEND_VISIT, world.clock.minutes, world.clock.day())
		host.persona.add_mood(pid, 0.05, world.clock.minutes)
		var t: String = Dialog.rumor(world.dialog_context(pid, host))
		host.say(t, 5.0)
		world.emit_game_event(pid, "visited", {"estate": it.estate_id})
	else:
		world.notify(pid, "show_message", ["Chvíli posedíš u stolu.", 2.0])
	await get_tree().create_timer(SIT_S).timeout
	if is_instance_valid(p):
		p.visual.pose = "stand"
		p.controls_locked = false


## Rozhovor s obyvatelem (E u něj).
func talk(pid: int, iid: String) -> void:
	var it: Interior = world.interiors.get(iid)
	if it == null or it.resident == null or not is_instance_valid(it.resident) or not it.resident.visible:
		return
	var t: String = Dialog.rumor(world.dialog_context(pid, it.resident))
	it.resident.say(t, 4.5)
	it.resident.persona.met[pid] = true


## Nabídka pater u schodiště bytového domu.
func stairs_menu(pid: int, iid: String) -> void:
	var it: Interior = world.interiors.get(iid)
	if it == null:
		return
	var opts := []
	var f := 0
	while it.spots.has("floor:%d" % f):
		opts.append([InteriorGen.floor_name(f).capitalize() if f == 0 else InteriorGen.floor_name(f),
			move_to.bind(pid, iid, "floor:%d" % f, true)])
		f += 1
	world.notify(pid, "open_menu", ["Schodiště", "Kam půjdeš?", opts])


## Dveře bytu v chodbě bytového domu: vlastní → domov (byt z M1.7), cizí → zamčeno, zazvonit.
func flat_door(pid: int, iid: String, n: int) -> void:
	var it: Interior = world.interiors.get(iid)
	if it == null or world.estate == null:
		return
	if world.estate.home_estate(pid) == it.estate_id and world.estate.home_flat(pid) == n and ensure("domov"):
		move_to(pid, "domov", "", true)
		return
	world.notify(pid, "open_menu", ["Byt %d" % n, "Cizí byt – zamčeno.", [["Zazvonit", ring.bind(pid, it.estate_id, n)]]])


func ring(pid: int, eid: int, n: int) -> void:
	world.play_sfx(pid, "door", 2.2, -6.0)
	world.notify(pid, "show_message", ["Crrr…", 1.2])
	await get_tree().create_timer(1.4).timeout
	var key := "%d:%d:%d" % [pid, eid, n]
	var now := world.clock.minutes
	var again := now - float(_knock_t.get(key, -99999.0)) < KNOCK_COOLDOWN_MIN
	_knock_t[key] = now
	var r := resident_of(eid, n)
	var per: Persona = r.get("persona")
	if per == null or not bool(r.get("home", false)):
		world.notify(pid, "show_message", ["Nikdo neotvírá.", 2.5])
		world.emit_game_event(pid, "knocked", {"estate": eid, "flat": n, "opened": false})
		return
	# DOPLNIT: interiéry cizích bytů – zatím se mluví jen přes dveře
	var ok := _answer(pid, per, again, "(přes dveře)")
	if ok:
		per.add_friendship(pid, Persona.FRIEND_POLITE, now, world.clock.day())
	world.emit_game_event(pid, "knocked", {"estate": eid, "flat": n, "opened": ok})


## Přesun v rámci interiérů (patro, byt ↔ chodba): krátké ztmavení, přepnutí interiéru, teleport na místo `spot`
## ("" = vchod interiéru).
func move_to(pid: int, iid: String, spot: String, fade: bool) -> void:
	var p: Player = world.players.get(pid)
	if p == null or not ensure(iid):
		return
	var it: Interior = world.interiors[iid]
	var sp: Array = it.spots.get(spot, [it.inside_door, it.inside_yaw])
	var prev := p.inside
	if fade:
		p.controls_locked = true
		world.blackout(pid, 0.6)
		await get_tree().create_timer(0.25).timeout
		world.play_sfx(pid, "door")
	world.interior_mark(p, iid)
	p.teleport((sp[0] as Vector3) + Vector3(0, 0.1, 0), float(sp[1]), false)
	p.controls_locked = false
	if prev != iid:
		if prev != "":
			world.emit_game_event(pid, "exited_interior", {"id": prev})
		world.emit_game_event(pid, "entered_interior", {"id": iid})


## Odchod z bytu (domov v bytovém domě) vede do chodby před dveře bytu, ne rovnou ven. true = vyřízeno.
func exit_to_stairs(pid: int, iid: String, fade: bool) -> bool:
	if iid != "domov" or world.estate == null or not world.estate.is_flat(pid):
		return false
	var st := gen_id(world.estate.home_estate(pid))
	if not specs.has(st) or String(specs[st]["kind"]) != "gen_flats" or not ensure(st):
		return false
	move_to(pid, st, "flat:%d" % world.estate.home_flat(pid), fade)
	return true


## Hráč v cizím domě bez (platného) pozvání: obyvatel se ozve a po chvíli ho vyprovodí. Hák pro zákon (M4.4):
## porušování domovní svobody – § 178 tr. zákoníku (zjednodušeně; ověřit aktuální znění), událost "trespass".
func _check_trespass(dt: float) -> void:
	for pid_v in world.players:
		var pid: int = pid_v
		var p: Player = world.players[pid_v]
		var sp: Dictionary = specs.get(p.inside, {})
		if sp.is_empty() or String(sp["kind"]) != "gen_house" or invited(pid, int(sp["eid"])):
			_trespass.erase(pid)
			continue
		var first := not _trespass.has(pid)
		_trespass[pid] = float(_trespass.get(pid, 0.0)) + dt
		var it: Interior = world.interiors.get(p.inside)
		var host: Npc = it.resident if it and it.resident and is_instance_valid(it.resident) and it.resident.visible else null
		if first:
			if host:
				host.say("Už byste měl jít, mám práci.", 4.0)
				world.emit_game_event(pid, "trespass", {"estate": int(sp["eid"]), "resident": host.persona.display_name()})
			world.notify(pid, "show_message", ["Pozvání vypršelo – je čas jít.", 3.0])
		elif float(_trespass[pid]) >= TRESPASS_GRACE_S:
			_trespass.erase(pid)
			world.exit_interior(pid)
