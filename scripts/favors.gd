## Prosby vesničanů (M4.5): každý herní den 2–4 vesničané (z celé vsi) chtějí pomoc. Prosbu přijmeš
## v nabídce u vesničana (E → `LocalClient.open_favor_menu`). Splní se herní událostí (`World.emit_game_event`)
## nebo předáním dárku (`World.give_to_npc` → `gift_given`). Nesplněný slib → přátelství −10.
## Jedna instance `World.favors`; stav per hráč: `offers[pid][jméno vesničana] = {tpl, state, day, progress}`.
## Ukládání `to_dict(pid)` / `from_dict(pid, d)` – klíč `favors` v `SaveGame` (starý save bez klíče = žádné prosby).
class_name Favors
extends RefCounted

## Šablony prosby. `event` = herní událost, která ji plní; `n` = počet splnění; `give` = u dárku typ předmětu.
## Zahrada a sníh se plní jakoukoli sklizní / dobrovolnickým úklidem (hra nerozlišuje, pro koho).
const FAVORS := {
	"zahrada": {"title": "Pomůžeš mi na zahradě?", "event": "harvest", "n": 2, "text": "Sklidit na zahradě 2×"},
	"snih": {"title": "Odhrneš mi sníh?", "event": "snow_volunteer", "n": 1, "text": "Odhrnout sníh (dobrovolně)"},
	"nakup": {"title": "Donesl bys mi nákup?", "event": "gift_given", "give": "food", "n": 1,
		"text": "Donést jídlo a předat ho (dárek)"},
}
const DAILY_MIN := 2
const DAILY_MAX := 4
const REWARD_FRIEND := 15.0       # přátelství za splněný slib (obejde denní limit)
const REWARD_RESPECT := 3.0       # respekt komunity postavy
const REWARD_REP := 2.0           # pověst
const REWARD_KARMA := 1.0         # skrytá karma
const BREAK_FRIEND := -10.0       # nesplněný slib
const PERK_FRIEND := 40.0         # ≥ 40: pomůže nést, půjčí nářadí (háček M2.10 / M5)
const PERK_WARN := 60.0           # ≥ 60: nenahlásí drobný přestupek (háček M4.4 witness_check), varuje před kontrolou

var world: World
var offers := {}                  # id hráče → {jméno vesničana → {tpl, state, day, progress}}
var _day := {}                    # id hráče → herní den, pro který je seznam prosob vygenerován


func setup(w: World) -> void:
	world = w


## Vygeneruje dnešní prosby (jednou za den), starý nesplněný slib předtím označí jako zklamaný.
func _roll_day(pid: int) -> void:
	var today := world.clock.day()
	if int(_day.get(pid, -1)) == today:
		return
	_day[pid] = today
	var mine: Dictionary = offers.get(pid, {})
	for k in mine.keys():
		var o: Dictionary = mine[k]
		if o["state"] == "accepted":
			_break(pid, k)
	mine.clear()
	offers[pid] = mine
	var names := []
	for key in world.personas():
		if String(key).begins_with("v"):
			names.append(world.personas()[key].display_name())
	names.sort()
	var rng := RandomNumberGenerator.new()
	rng.seed = today * 7919 + pid * 31
	var tpls := FAVORS.keys()
	var cnt := rng.randi_range(DAILY_MIN, DAILY_MAX)
	for i in cnt:
		if names.is_empty():
			break
		var nm: String = names.pop_at(rng.randi() % names.size())
		mine[nm] = {"tpl": tpls[rng.randi() % tpls.size()], "state": "offer", "day": today, "progress": 0}


## Prosba, kterou vesničan `name` dnes nabízí hráči `pid` (prázdný slovník = nic).
func offer_for(pid: int, name: String) -> Dictionary:
	_roll_day(pid)
	return (offers.get(pid, {}) as Dictionary).get(name, {})


## Hráč prosbu přijme (stav `offer` → `accepted`).
func accept(pid: int, name: String) -> void:
	var o := offer_for(pid, name)
	if o.is_empty() or o["state"] != "offer":
		return
	o["state"] = "accepted"
	world.notify(pid, "show_message", ["%s: „To bys mi fakt udělal? Díky.“" % _first(name), 3.0])


## Událost ze světa – posune splněné prosby (zavolá `World.emit_game_event`).
func on_event(pid: int, kind: String, data: Dictionary) -> void:
	_roll_day(pid)
	var mine: Dictionary = offers.get(pid, {})
	for k in mine.keys():
		var o: Dictionary = mine[k]
		if o["state"] != "accepted":
			continue
		var f: Dictionary = FAVORS.get(o["tpl"], {})
		if String(f.get("event", "")) != kind:
			continue
		if kind == "gift_given":
			if String(data.get("to", "")) != k or ItemsDB.type_of(String(data.get("item", ""))) != String(f.get("give", "")):
				continue
		o["progress"] = int(o["progress"]) + 1
		if int(o["progress"]) >= int(f.get("n", 1)):
			_done(pid, k)


func _done(pid: int, name: String) -> void:
	var per := _persona(name)
	var o: Dictionary = offers[pid][name]
	o["state"] = "done"
	if per == null:
		return
	var now := world.clock.minutes
	per.add_friendship(pid, REWARD_FRIEND, now, world.clock.day(), true)
	var comm := Reputation.community_of(per)
	var rep: Reputation = world.reputations.get(pid)
	if rep:
		rep.change_respect(comm, REWARD_RESPECT, "pomohl %s" % per.first_name())
		rep.change(REWARD_REP, "pomohl %s" % per.first_name())
		rep.change_karma(REWARD_KARMA, "prosba: %s" % per.first_name())
	world.notify(pid, "show_message", ["Prosba splněna: %s. Díky!" % _first(name), 3.5])
	world.emit_game_event(pid, "favor_done", {"to": name, "tpl": o["tpl"]})


func _break(pid: int, name: String) -> void:
	var per := _persona(name)
	offers[pid][name]["state"] = "failed"
	if per == null:
		return
	per.add_friendship(pid, BREAK_FRIEND, world.clock.minutes, world.clock.day())
	world.notify(pid, "show_message", ["%s: „Slíbils to a nic… Zklamals mě.“" % _first(name), 3.5])


## Přátelské výhody podle hodnoty přátelství (texty do nabídky; efekty napojit na M4.4 / M5.11).
func perks(per: Persona, pid: int) -> Array:
	var out := []
	var f := per.get_friendship(pid)
	if f >= PERK_FRIEND:
		out.append("pomůže s nošením, půjčí nářadí")
	if f >= PERK_WARN:
		out.append("nenahlásí drobný přestupek, varuje před kontrolou")
	return out


func _persona(name: String) -> Persona:
	for key in world.personas():
		var p: Persona = world.personas()[key]
		if p.display_name() == name:
			return p
	return null


func _first(name: String) -> String:
	return name.split(" ")[0]


func to_dict(pid: int) -> Dictionary:
	var out := {}
	for k in (offers.get(pid, {}) as Dictionary).keys():
		out[k] = offers[pid][k]
	return {"offers": out, "day": int(_day.get(pid, -1))}


func from_dict(pid: int, d: Dictionary) -> void:
	offers[pid] = (d.get("offers", {}) as Dictionary).duplicate(true)
	_day[pid] = int(d.get("day", -1))
