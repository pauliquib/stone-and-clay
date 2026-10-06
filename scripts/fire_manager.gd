## Oheň a topení (M2.2), jeden uzel ve `World` (`World.fire_mgr`; seznam ohňů `World.fires`).
##
## - Akce (viz `Actions.DEFS`): `rozdelat_ohen` / `zapalit_ohniste` (šance zapálení podle počasí a dovednosti Topení a oheň),
##   `opekat` (předměty s klíčem `cook_to` v `ItemsDB`), `uhasit`, `hasit` (požár trávy). Nabídka u ohně (E): přiložit, opékat, uhasit.
## - Teplo: `Player.heat` (0..1) a `Player.shelter_min` se nastavují každý snímek → `BodyState` (sušení 4×, zahřátí).
## - Zákon: oheň v lese / do 50 m od okraje = přestupek `ohen_u_lesa` (svědek hned, jinak šance odhalení kouře za hodinu hoření).
## - Šíření: nehlídaný oheň v suchu a větru přeskočí na trávu (`GrassFire`) → přestupek `zpusobeni_pozaru`, událost `fire_report` (háček M5.3).
## - Kamna doma (`stove_*`): 2 polena = 3 herní hodiny, teplý domov, kouří komín domova (`World.home_chimney_id`).
##   Jen v rodinném domě – byt (M1.7, `Estate.is_flat`) má radiátor ústředního topení: vždy teplo, bez kamen a komína.
## - Ukládání: `to_dict` / `restore` (klíč `fire` v `SaveGame`): ohniště (i vyhaslá), stav kamen.
## Čas se počítá podle hodin světa (`Clock.minutes`), takže spánek a přeskok času oheň dopálí.
class_name FireManager
extends Node

# ------------------------------------------------------------------ laditelné hodnoty

const MAX_FIRES := 24                  # nejvíc ohnišť ve světě (nejstarší vyhaslé se ruší)
const MIN_GAP := 1.6                   # m – nejmenší odstup dvou ohnišť
const KINDLING_FULL := {"vetve": 2, "polena": 2}      # 2× větve + 2× polena …
const KINDLING_ALT := {"vetve": 4}                    # … nebo 4× větve
const IGNITE_BASE := 0.9               # základní šance zapálení
const IGNITE_RAIN := -0.4              # déšť / sněžení
const IGNITE_WIND := -0.25             # vítr nad WIND_HARD
const IGNITE_WET := -0.2               # mokré dřevo (Weather.wetness ≥ WET_HARD)
const IGNITE_LIGHTER := 0.05           # zapalovač je spolehlivější než sirky
const IGNITE_SKILL := 0.08             # + při nejvyšší úrovni Topení a oheň
const WIND_HARD := 6.0                 # m/s
const WET_HARD := 0.35
const XP_LIGHT := 10.0
const XP_LIGHT_FAIL := 3.0
# --- zákon
const FOREST_BUFFER := 50.0            # m od okraje lesa (zákon o lesích)
const WITNESS_R := 150.0               # m – svědek (vesničan, myslivec, policie)
const SMOKE_SEEN_PER_H := 0.30         # šance odhalení kouře za hodinu hoření bez svědka
const KARMA_ILLEGAL := -1.0
const REP_SEEN := -3.0
# --- šíření trávou
const UNATTENDED_R := 40.0             # m – dál od hráče je oheň „nehlídaný“
const SPREAD_P_MIN := 0.03             # šance přeskoku za herní minutu (× vítr / 6)   DOPLNIT: ladit
const DRY_RAIN_RECENT := 0.2           # Weather.rain_recent pod tímto = sucho
const SPREAD_WIND := 4.0               # m/s
const OFFENSE_MIN_R := 4.0             # od tohoto poloměru je požár přestupek (menší jde uhasit „včas“)
const KARMA_FIRE := -5.0
# --- kamna doma
const STOVE_LOAD_MIN := 180.0          # 2 polena = 3 herní hodiny
const STOVE_MAX_MIN := 360.0
const STOVE_LOGS := 2
const HOME_HEATED_TEMP := 22.0         # °C pocitově doma s topením
const HOME_UNHEATED_OFFSET := 8.0      # doma bez topení = venku + tolik °C (nejvýš 18) → v zimě zima
const RADIATOR_HEAT_K := 0.6           # byt (M1.7): radiátor suší slaběji než kamna (násobek STOVE_HEAT)
const STOVE_HEAT := 0.5                # „teplo“ pro sušení doma
const HOME_COLD_MAX := 0.5             # nejvyšší prochladnutí po noci v nevytopeném domě
const HOME_COLD_PER_DEG := 0.04        # …za každý °C pod 5 °C
const SOUP_RECIPE := {"brambory": 2, "cibule": 1, "voda": 1}   # M2.4: bramborová polévka na kamnech
const SOUP_PORTIONS := 2
const SOUP_XP := 15.0
const HOME_COLD_HEAL := 6.0            # o kolik HP horší odpočinek v nevytopeném domě při < 5 °C

var world: World
var stove_min := 0.0                   # zbývající herní minuty hoření v kamnech domova
var roast_pick := {}                   # id hráče → předmět, který si vybral k opékání v nabídce

var _last_min := -1.0
var _slow := 0.0


func setup(w: World) -> void:
	world = w
	name = "Ohen"
	Actions.set_handler("rozdelat_ohen", _on_light)
	Actions.set_handler("zapalit_ohniste", _on_light)
	Actions.set_handler("opekat", _on_cook)
	Actions.set_handler("uhasit", _on_extinguish)
	Actions.set_handler("hasit", _on_fight)
	Actions.set_target_check("rozdelat_ohen", _check_light)
	Actions.set_target_check("zapalit_ohniste", _check_relight)
	Actions.set_target_check("opekat", _check_cook)
	Actions.set_target_check("uhasit", _check_extinguish)
	Actions.set_target_check("hasit", _check_fight)
	Actions.set_time_mod("uhasit", _mod_extinguish)


# ------------------------------------------------------------------ pomocné

func _rain_on_fire() -> float:
	var w: Weather = world.weather
	if w == null:
		return 0.0
	if w.is_raining():
		return w.rain
	if w.is_snowing():
		return w.rain * 0.35
	return 0.0


func _ground_y(pos: Vector3) -> float:
	return world.terrain.height_at(pos.x, pos.z) if world.terrain else pos.y


func _fire_of(aim: Dictionary) -> Fire:
	var t: Dictionary = aim.get("target", {})
	var n = t.get("node")
	return n as Fire if n != null and is_instance_valid(n) else null


func _grass_of(aim: Dictionary) -> GrassFire:
	var t: Dictionary = aim.get("target", {})
	var n = t.get("node")
	return n as GrassFire if n != null and is_instance_valid(n) else null


func _aim_for(f: Fire) -> Dictionary:
	return {"kind": "fire", "pos": f.target["pos"], "target": f.target}


## Kolik minut hoření dá roznětka, kterou hráč právě má (0 = nemá dost); `take` = rovnou odebrat.
func kindling_minutes(p: Player, take := false) -> float:
	var recipe := {}
	if _has_all(p, KINDLING_FULL):
		recipe = KINDLING_FULL
	elif _has_all(p, KINDLING_ALT):
		recipe = KINDLING_ALT
	if recipe.is_empty():
		return 0.0
	var minutes := 0.0
	for item in recipe:
		minutes += float(Fire.WOOD_MIN[item]) * int(recipe[item])
		if take:
			p.remove_item(item, int(recipe[item]))
	return minutes


func _has_all(p: Player, recipe: Dictionary) -> bool:
	for item in recipe:
		if p.item_count(item) < int(recipe[item]):
			return false
	return true


static func _hm(minutes: float) -> String:
	var m := int(ceil(minutes))
	return "%d h %02d min" % [floori(m / 60.0), m % 60] if m >= 60 else "%d min" % m


## Šance zapálení: základ, déšť, vítr, mokré dřevo, zapalovač a úroveň dovednosti.
func ignite_chance(id: int, tool_id: String) -> float:
	var c := IGNITE_BASE
	var w: Weather = world.weather
	if w:
		if w.is_raining() or w.is_snowing():
			c += IGNITE_RAIN
		if w.wind > WIND_HARD:
			c += IGNITE_WIND
		if w.wetness >= WET_HARD:
			c += IGNITE_WET
	if tool_id == "zapalovac":
		c += IGNITE_LIGHTER
	var sk: Skills = world.skills.get(id)
	if sk:
		c += IGNITE_SKILL * sk.bonus("ohen")
	return clampf(c, 0.05, 0.98)


# ------------------------------------------------------------------ rozdělání ohně

func _check_light(aim: Dictionary, id: int) -> String:
	var p: Player = world.players.get(id)
	if p == null:
		return "Teď ne."
	if kindling_minutes(p) <= 0.0:
		return "Na oheň potřebuješ 2× větve a 2× polena, nebo 4× větve."
	var pos: Vector3 = aim["pos"]
	for f in world.fires:
		if is_instance_valid(f) and Vector2(f.global_position.x - pos.x, f.global_position.z - pos.z).length() < MIN_GAP:
			return "Tady už ohniště je."
	return ""


func _check_relight(aim: Dictionary, id: int) -> String:
	var f := _fire_of(aim)
	if f == null:
		return "Cíl zmizel."
	if f.is_burning():
		return "Oheň už hoří."
	var p: Player = world.players.get(id)
	if p == null or kindling_minutes(p) <= 0.0:
		return "Na oheň potřebuješ 2× větve a 2× polena, nebo 4× větve."
	return ""


func _on_light(id: int, _def: Dictionary, aim: Dictionary, ok: bool) -> void:
	var p: Player = world.players.get(id)
	if p == null:
		return
	var tool_id := p.equipped
	if not ok or randf() >= ignite_chance(id, tool_id):
		world.give_xp(id, "ohen", XP_LIGHT_FAIL, "oheň")
		var why := "mokro" if _rain_on_fire() > 0.05 else ("vítr" if world.weather and world.weather.wind > WIND_HARD else "nechytá")
		world.notify(id, "show_message", ["Oheň se nechytil (%s) – zkus to znovu." % why, 2.5])
		return
	var minutes := kindling_minutes(p, true)
	if minutes <= 0.0:
		world.notify(id, "show_message", ["Došlo ti dříví.", 2.0])
		return
	var f := _fire_of(aim)
	if f == null:
		var pos: Vector3 = aim["pos"]
		pos.y = _ground_y(pos)
		_trim_fires()
		f = Fire.make(world, pos)
		world.fires.append(f)
	f.spread_done = false
	f.reported = false
	f.illegal = false
	f.ignite(minutes, id)
	world.play_sfx(id, "lighter")
	world.give_xp(id, "ohen", XP_LIGHT, "oheň")
	world.notify(id, "show_message", ["Oheň hoří. Přikládej dřevem (E), jinak dohasne.", 3.0])
	world.emit_game_event(id, "fire_lit", {"pos": f.global_position})
	_check_law(id, f)


func _trim_fires() -> void:
	while world.fires.size() >= MAX_FIRES:
		var victim: Fire = null
		for f in world.fires:
			if is_instance_valid(f) and not f.is_hot():
				victim = f
				break
		if victim == null:
			victim = world.fires[0]
		world.fires.erase(victim)
		if is_instance_valid(victim):
			victim.queue_free()


# ------------------------------------------------------------------ zákon

## Je bod v lese nebo do `FOREST_BUFFER` m od jeho okraje? (střed + kruhy 25 m a 50 m po 8 bodech). Bez dat zvěře false.
func near_forest(pos: Vector3) -> bool:
	var fa := world.fauna
	if fa == null:
		return false
	if fa.forest_at(pos.x, pos.z) > 0.5:
		return true
	for r in [FOREST_BUFFER * 0.5, FOREST_BUFFER]:
		for i in 8:
			var a := float(i) / 8.0 * TAU
			if fa.forest_at(pos.x + cos(a) * r, pos.z + sin(a) * r) > 0.5:
				return true
	return false


func _check_law(id: int, f: Fire) -> void:
	if not near_forest(f.global_position):
		return
	f.illegal = true
	var seen: bool = world.witness_reported(id, f.global_position, "ohen", WITNESS_R, WITNESS_R)
	if seen:
		world.notify(id, "popup", ["Někdo tě u ohně u lesa viděl!", 3.0])
		_report(f, true)
	else:
		world.notify(id, "show_message", ["Pozor: oheň u lesa je zakázaný (do 50 m od okraje).", 3.5])
		var rep: Reputation = world.reputations.get(id)
		if rep:
			rep.change_karma(KARMA_ILLEGAL, "oheň u lesa")


## Uplatní přestupek `ohen_u_lesa` pro toho, kdo oheň rozdělal (jednou za oheň).
func _report(f: Fire, seen: bool) -> void:
	if f.reported:
		return
	f.reported = true
	var id := f.owner_id
	if not world.players.has(id):
		return
	world.commit_offense(id, "ohen_u_lesa", {"severity": 0.3})
	var rep: Reputation = world.reputations.get(id)
	if rep and seen:
		rep.change(REP_SEEN, "oheň u lesa", "oheň u lesa")
	if not seen:
		world.notify(id, "popup", ["Někdo nahlásil kouř u lesa – přestupek.", 3.5])


# ------------------------------------------------------------------ opékání

## Předměty v kapse, které jdou opéct: [id, …].
func cookables(p: Player) -> Array:
	var out := []
	for item in p.inventory:
		if int(p.inventory[item]) > 0 and ItemsDB.cook_to(String(item)) != "":
			out.append(String(item))
	return out


func _pick_cook(p: Player) -> String:
	var pick := String(roast_pick.get(p.id, ""))
	if pick != "" and p.item_count(pick) > 0 and ItemsDB.cook_to(pick) != "":
		return pick
	var list := cookables(p)
	return String(list[0]) if not list.is_empty() else ""


func _check_cook(aim: Dictionary, id: int) -> String:
	var f := _fire_of(aim)
	if f == null or not f.is_hot():
		return "Oheň nehoří."
	var p: Player = world.players.get(id)
	if p == null or _pick_cook(p) == "":
		return "Nemáš co opékat (buřt, párek, chleba…)."
	return ""


func _on_cook(id: int, _def: Dictionary, aim: Dictionary, ok: bool) -> void:
	var p: Player = world.players.get(id)
	var f := _fire_of(aim)
	if p == null:
		return
	var item := _pick_cook(p)
	roast_pick.erase(id)
	if item == "":
		return
	if f == null or not f.is_hot():
		world.notify(id, "show_message", ["Oheň mezitím zhasl.", 2.0])
		return
	if not p.remove_item(item):
		return
	var res := ItemsDB.cook_to(item) if ok else ItemsDB.burnt_to(item)
	if not ItemsDB.exists(res):
		res = item
	p.add_item(res)
	world.play_sfx(id, "eat", 1.4, -6.0)
	if ok:
		world.notify(id, "show_message", ["Máš: %s" % ItemsDB.name_of(res), 2.5])
	else:
		world.notify(id, "show_message", ["Spálilo se ti to – %s." % ItemsDB.name_of(res).to_lower(), 2.8])
	world.emit_game_event(id, "cooked", {"item": item, "result": res, "ok": ok})


# ------------------------------------------------------------------ hašení

func _check_extinguish(aim: Dictionary, _id: int) -> String:
	var f := _fire_of(aim)
	if f == null or not f.is_hot():
		return "Oheň nehoří."
	return ""


func _mod_extinguish(aim: Dictionary, _tool_id: String) -> float:
	var pl := world.nearest_player(aim.get("pos", Vector3.ZERO))
	return 0.35 if pl != null and pl.item_count("voda") > 0 else 1.0


func _on_extinguish(id: int, _def: Dictionary, aim: Dictionary, ok: bool) -> void:
	var p: Player = world.players.get(id)
	var f := _fire_of(aim)
	if p == null or f == null or not ok:
		return
	var water := p.item_count("voda") > 0
	if water:
		p.remove_item("voda")
	f.extinguish()
	world.notify(id, "show_message", ["Oheň uhašen (%s)." % ("vodou" if water else "zašlapáno"), 2.5])
	world.emit_game_event(id, "fire_out", {"pos": f.global_position})


func _check_fight(aim: Dictionary, id: int) -> String:
	var g := _grass_of(aim)
	if g == null or g.finished:
		return "Oheň už dohořel."
	var p: Player = world.players.get(id)
	if p == null:
		return "Teď ne."
	if g.in_fire(p.global_position):
		return "Vylez z ohně!"
	if p.equipped != "lopata" and p.item_count("voda") <= 0:
		return "Na hašení potřebuješ lopatu v ruce nebo vodu."
	return ""


func _on_fight(id: int, _def: Dictionary, aim: Dictionary, ok: bool) -> void:
	var p: Player = world.players.get(id)
	var g := _grass_of(aim)
	if p == null or g == null or not ok:
		return
	if p.equipped != "lopata" and p.item_count("voda") > 0:
		p.remove_item("voda")
	g.suppress()
	if g.finished:
		world.notify(id, "popup", ["Požár trávy uhašen!", 3.0])
	else:
		world.notify(id, "show_message", ["Plameny ustoupily – hasit dál!", 2.5])


# ------------------------------------------------------------------ nabídka u ohně (E)

## Položky pro `World.interactables`: oheň do 2,4 m od hráče (venku).
func interactables(id: int) -> Array:
	var p: Player = world.players.get(id)
	if p == null or p.inside != "":
		return []
	var out := []
	for f in world.fires:
		if not is_instance_valid(f):
			continue
		if f.global_position.distance_to(p.global_position) > 6.0:
			continue
		var txt: String = {2: "Oheň", 1: "Žhavé uhlíky", 0: "Ohniště"}[f.state()]
		out.append({"pos": f.global_position + Vector3(0, 0.3, 0), "r": 2.4, "kind": "custom",
			"text": "%s – přiložit / opékat / uhasit" % txt, "action": open_fire_menu.bind(f)})
	return out


func open_fire_menu(id: int, f: Fire) -> void:
	var p: Player = world.players.get(id)
	if p == null or not is_instance_valid(f):
		return
	var st := f.state()
	var text := ""
	match st:
		2:
			text = "Oheň hoří, dříví vydrží asi %s." % _hm(f.fuel)
		1:
			text = "Žhavé uhlíky (ještě asi %s). Přilož, nebo zapal znovu." % _hm(f.ember)
		_:
			text = "Vyhaslé ohniště. Zapálíš ho sirkami / zapalovačem v ruce (Q) a levým tlačítkem (potřeba 2× větve a 2× polena, nebo 4× větve)."
	var opts := []
	for item in ["polena", "vetve", "vetve_cerstve"]:
		var n := p.item_count(item)
		opts.append(["Přiložit: %s (máš %d)" % [ItemsDB.name_of(item), n], add_fuel.bind(id, f, item), n > 0 and f.fuel < Fire.MAX_FUEL - 1.0])
	for item in cookables(p):
		opts.append(["Opékat: %s (máš %d)" % [ItemsDB.name_of(item), p.item_count(item)], start_cook.bind(id, f, item), f.is_hot()])
	if opts.size() == 2:
		text += "\nNemáš nic k opékání (buřty koupíš v Potravinách)."
	opts.append(["Uhasit oheň (%s)" % ("vodou, rychle" if p.item_count("voda") > 0 else "zašlapat, 10 s"),
		start_extinguish.bind(id, f), f.is_hot()])
	world.notify(id, "open_menu", ["Ohniště", text, opts])


func add_fuel(id: int, f: Fire, item: String) -> void:
	var p: Player = world.players.get(id)
	if p == null or not is_instance_valid(f) or p.item_count(item) <= 0:
		return
	if not f.add_fuel(item):
		world.notify(id, "show_message", ["Oheň je plný.", 1.8])
		return
	p.remove_item(item)
	world.play_sfx(id, "pickup")
	world.notify(id, "show_message", ["Přiloženo: %s (dříví na %s)." % [ItemsDB.name_of(item), _hm(f.fuel)], 2.2])
	if world.vyhlasky:
		world.vyhlasky.on_fuel(id, f, item)             # kouř z čerstvých větví, zákaz pálení (M4.4 část B)


func start_cook(id: int, f: Fire, item: String) -> void:
	if not is_instance_valid(f):
		return
	roast_pick[id] = item
	if not world.start_action(id, "opekat", _aim_for(f)):
		roast_pick.erase(id)


func start_extinguish(id: int, f: Fire) -> void:
	if is_instance_valid(f):
		world.start_action(id, "uhasit", _aim_for(f))


# ------------------------------------------------------------------ kamna doma

func stove_lit() -> bool:
	return stove_min > 0.0


## Zatopí / přiloží do kamen v domově (2 polena). Studená kamna se zapalují sirkami nebo zapalovačem z kapsy.
func stove_load(id: int) -> void:
	var p: Player = world.players.get(id)
	if p == null:
		return
	if stove_min >= STOVE_MAX_MIN - 1.0:
		world.notify(id, "show_message", ["Kamna jsou plná, víc se nevejde.", 2.0])
		return
	if p.item_count("polena") < STOVE_LOGS:
		world.notify(id, "show_message", ["Na zatopení potřebuješ %d× polena." % STOVE_LOGS, 2.5])
		return
	var fresh := not stove_lit()
	if fresh:
		var lighter := "zapalovac" if p.item_count("zapalovac") > 0 else ("sirky" if p.item_count("sirky") > 0 else "")
		if lighter == "":
			world.notify(id, "show_message", ["Na zatopení potřebuješ sirky nebo zapalovač.", 2.5])
			return
		p.wear_tool(lighter)
		world.play_sfx(id, "lighter")
	p.remove_item("polena", STOVE_LOGS)
	stove_min = minf(stove_min + STOVE_LOAD_MIN, STOVE_MAX_MIN)
	world.give_xp(id, "ohen", 4.0 if fresh else 2.0, "topení")
	world.notify(id, "show_message", ["%s Kamna hoří ještě asi %s." % ["Zatopeno." if fresh else "Přiloženo.", _hm(stove_min)], 3.0])
	world.emit_game_event(id, "stove_lit", {"minutes": stove_min})


func open_stove_menu(id: int) -> void:
	var p: Player = world.players.get(id)
	if p == null:
		return
	var text := "Kamna na dřevo. "
	text += ("Hoří, dříví vydrží asi %s." % _hm(stove_min)) if stove_lit() else "Jsou studená."
	var t := world.weather.temp if world.weather else 10.0
	if not stove_lit() and t < 5.0:
		text += "\nVenku je %d °C – bez topení tu bude zima." % roundi(t)
	var opts := [["%s (%d× polena, máš %d)" % ["Přiložit" if stove_lit() else "Zatopit", STOVE_LOGS, p.item_count("polena")],
		stove_load.bind(id), p.item_count("polena") >= STOVE_LOGS]]
	var soup_ok := stove_lit() and _has_all(p, SOUP_RECIPE)
	opts.append(["Uvařit bramborovou polévku (2× brambory, cibule, voda → %d× polévka)" % SOUP_PORTIONS,
		cook_soup.bind(id), soup_ok])
	if not stove_lit():
		text += "\nNa vaření polévky musí v kamnech hořet."
	world.notify(id, "open_menu", ["Kamna", text, opts])


## Recept „bramborová polévka“ (M2.4): brambory + cibule + voda z kapsy → polévka, vaří se na hořících kamnech doma.
func cook_soup(id: int) -> void:
	var p: Player = world.players.get(id)
	if p == null or not stove_lit() or not _has_all(p, SOUP_RECIPE):
		return
	for item in SOUP_RECIPE:
		p.remove_item(item, int(SOUP_RECIPE[item]))
	p.add_item("polevka", SOUP_PORTIONS)
	world.give_xp(id, "vareni", SOUP_XP, "polevka")
	world.notify(id, "show_message", ["Uvařeno: %d× bramborová polévka (voňavá, hřeje)." % SOUP_PORTIONS, 3.0])


## Je domov hráče vytopený? (pro spánek: kamna hoří aspoň půlku doby `hours`)
func home_heated_for(hours: float) -> bool:
	return stove_min >= hours * 30.0


## Kdy se venku kouří z komína domova: id budovy domova, nebo 0 (nezatopeno / byt / bez dat budov).
func home_chimney_id() -> int:
	if not stove_lit() or world.building_details == null or (world.estate != null and world.estate.is_flat(1)):
		return 0
	return world.home_building(1)


# ------------------------------------------------------------------ čas, teplo a šíření

func _process(delta: float) -> void:
	var __t0 := Tests.prof_t0()
	_process_impl(delta)
	Tests.prof_add("fire", __t0)


func _process_impl(delta: float) -> void:
	if world == null or world.clock == null:
		return
	var now := world.clock.minutes
	var dm := 0.0
	if _last_min >= 0.0:
		dm = clampf(now - _last_min, 0.0, 1440.0)
	_last_min = now
	if dm > 0.0:
		_advance(dm)
	for g in world.grass_fires.duplicate():
		if not is_instance_valid(g):
			world.grass_fires.erase(g)
		elif g.finished:
			_end_grass(g)
	_apply_heat()
	_slow -= delta
	if _slow <= 0.0:
		_slow = 0.5
		_update_active()


func _advance(dm: float) -> void:
	var rain := _rain_on_fire()
	for f in world.fires.duplicate():
		if not is_instance_valid(f):
			world.fires.erase(f)
			continue
		f.advance(dm, rain)
		if f.is_burning():
			_smoke_seen(f, dm)
			_try_spread(f, dm)
	stove_min = maxf(stove_min - dm, 0.0)
	for g in world.grass_fires:
		if is_instance_valid(g):
			g.advance(dm)


## Nehlídaný oheň v lese někdo zahlédne podle kouře.
func _smoke_seen(f: Fire, dm: float) -> void:
	if not f.illegal or f.reported:
		return
	if randf() < 1.0 - pow(1.0 - SMOKE_SEEN_PER_H, dm / 60.0):
		_report(f, false)


func _try_spread(f: Fire, dm: float) -> void:
	var w: Weather = world.weather
	if f.spread_done or w == null or world.clock == null:
		return
	if w.rain_recent >= DRY_RAIN_RECENT or w.is_raining() or w.wind <= SPREAD_WIND or world.clock.season() != "léto":
		return
	for p in world.players.values():
		if world.player_world_pos(p).distance_to(f.global_position) < UNATTENDED_R:
			return
	var pm := SPREAD_P_MIN * clampf(w.wind / 6.0, 0.6, 2.0)
	if randf() < 1.0 - pow(1.0 - pm, dm):
		_spread(f)


func _spread(f: Fire) -> void:
	f.spread_done = true
	var a := randf() * TAU
	var pos := f.global_position + Vector3(cos(a) * 2.0, 0.0, sin(a) * 2.0)
	pos.y = _ground_y(pos)
	world.grass_fires.append(GrassFire.make(world, pos, f.owner_id))
	var first := -1
	for id in world.players:
		if first < 0:
			first = int(id)
		if world.player_world_pos(world.players[id]).distance_to(pos) < 350.0:
			world.notify(int(id), "popup", ["Oheň přeskočil na trávu – hoří louka!", 4.0])
	var rid := f.owner_id if world.players.has(f.owner_id) else first
	if rid >= 0:
		world.emit_game_event(rid, "fire_report", {"pos": pos, "owner": f.owner_id})      # háček pro hasiče (M5.3)


func _end_grass(g: GrassFire) -> void:
	world.grass_fires.erase(g)
	var id := g.owner_id
	var rid := id if world.players.has(id) else (int(world.players.keys()[0]) if not world.players.is_empty() else -1)
	if rid >= 0:
		world.emit_game_event(rid, "fire_out", {"pos": g.global_position, "peak": g.peak_r})
	if world.players.has(id) and g.peak_r >= OFFENSE_MIN_R:
		world.commit_offense(id, "zpusobeni_pozaru", {"severity": clampf(g.peak_r / GrassFire.MAX_R, 0.0, 1.0)})
		var rep: Reputation = world.reputations.get(id)
		if rep:
			rep.change_karma(KARMA_FIRE, "způsobil požár")
		world.notify(id, "popup", ["Požár trávy dohořel – přestupek: způsobení požáru.", 4.0])


## Teplo od ohňů a kamen → hráči (`Player.heat`, `Player.shelter_min`), čte `BodyState` přes `Player._update_body`.
func _apply_heat() -> void:
	for id in world.players:
		var p: Player = world.players[id]
		var heat := 0.0
		var shelter := 18.0
		if p.inside == "":
			for f in world.fires:
				if is_instance_valid(f):
					heat = maxf(heat, f.heat_at(p.global_position))
		elif p.inside == "domov":
			if world.estate != null and world.estate.is_flat(id):     # byt: radiátor, vždy vytopeno (M1.7)
				heat = STOVE_HEAT * RADIATOR_HEAT_K
				shelter = HOME_HEATED_TEMP
			elif stove_lit():
				heat = STOVE_HEAT
				shelter = HOME_HEATED_TEMP
			else:
				var t := world.weather.temp if world.weather else 10.0
				shelter = clampf(t + HOME_UNHEATED_OFFSET, 3.0, 18.0)
		p.heat = heat
		p.shelter_min = shelter


func _update_active() -> void:
	for f in world.fires:
		if not is_instance_valid(f):
			continue
		var d := INF
		for p in world.players.values():
			d = minf(d, world.player_world_pos(p).distance_to(f.global_position))
		f.set_active(d < Fire.ACTIVE_R)


# ------------------------------------------------------------------ ukládání

func to_dict() -> Dictionary:
	var fs := []
	for f in world.fires:
		if is_instance_valid(f):
			fs.append(f.to_dict())
	return {"fires": fs, "stove": snappedf(stove_min, 0.1)}


## Starý save bez klíče = žádná ohniště, studená kamna.
func restore(d: Dictionary) -> void:
	for f in world.fires:
		if is_instance_valid(f):
			f.queue_free()
	world.fires.clear()
	for g in world.grass_fires:
		if is_instance_valid(g):
			g.queue_free()
	world.grass_fires.clear()
	for e in d.get("fires", []):
		var a = e.get("pos")
		if not (a is Array) or a.size() < 3:
			continue
		var f := Fire.make(world, Vector3(float(a[0]), float(a[1]), float(a[2])))
		f.from_dict(e)
		world.fires.append(f)
	stove_min = float(d.get("stove", 0.0))
	_last_min = -1.0
