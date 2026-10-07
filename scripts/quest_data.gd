## M7.3 Vedlejší úkoly jako data – obecný engine nad `Quests.Quest` (viz hlavička `quests.gd`).
## Proč: staré úkoly (cigarety, pivo…) jsou napsané ručně jako GDScript třídy – pro desítky sidequestů
## s morálním větvením je to příliš pomalé. Nové úkoly se místo toho popisují v `data/ukoly/*.json`
## a `Quests.setup()` je načte automaticky (`QuestData.load_all`) a přidá do `list` vedle starých úkolů.
## Staré úkoly se NEPŘEVÁDĚJÍ (čas na krok to nedovolil) – zůstávají jako GDScript třídy, obojí žije
## vedle sebe (shodné rozhraní `Quest`, shodné ukládání v `save_game.gd` přes `id`/`state`).
##
## --- Formát jednoho souboru data/ukoly/<id>.json ---
## {
##   "id": "...",                      jedinečné (= souborový název), neměnit po vydání (uložené hry)
##   "title": "...", "giver": "hospoda|obchod|palenice|sklep|chata|urad|vcelar|deda|stavebniny|pila",
##   "giver_name": "...", "intro": "...",
##   "requires": {"karma_min": -999, "karma_max": 999, "respect_min": {"komunita": -999}, "day_min": 0},
##       (karma_min/karma_max = kdo úkol vůbec uvidí – "postrach vsi" nízká karma dostane jiné nabídky
##        než ten s vysokou karmou; respect_min = potřebný respekt komunity; vynech, co není potřeba)
##   "steps": [ {"text": "text cíle v deníku", "need": {...}} , … ]     (po poslední se nabídne volba)
##     need.type: "near"  {place, offset:[dx,dz] (rel. k místu), radius}   – dojít na místo/bod
##                "item"  {id, count, consume:bool}                        – mít (a případně spotřebovat) předmět
##                "event" {kind, match:{klíč:hodnota}, count}              – herní událost (emit_game_event)
##                "talk"  {}                                               – jen tlačítko „Promluvit o tom“ u giver
##   "choice_text": "text, když dojdou kroky a čeká se na volbu (place `giver`)",
##   "branches": [
##     { "id": "...", "label": "text tlačítka", "honest": true/false, "result_text": "...",
##       "requires": {"money_min": n, "item": {"id":"...", "count": n}}     (kdy je volba nabídnutá)
##       "reward": {"money": ±n, "item_give":[{"id","count"}], "item_take":[{"id","count"}],
##                  "respect": {"komunita": ±n}, "karma": ±n, "friendship": ±n, "reputation": ±n},
##       "risk": {"chance": 0..1, "text": "co se stane, když tě chytí", "reward": {...navíc, obvykle záporné}} }
##   , … ]
## }
## Volba se počítá navíc k automatickým dopadům `Reputation.on_event("quest_done"/"quest_failed", …)`
## (+8 pověst / +respekt komunity dárce / +karma při úspěchu – platí i pro nečestné, ale neodhalené
## konce; proto nečestné větve dávají zápornou `karma` navíc = "skryté svědomí" i při viditelném úspěchu).
## Popularita (`Politics.popularity`) se nepočítá samostatně – je to vážený průměr pověsti, respektu
## komunit a přátelství (viz `politics.gd`), takže `respect`/`reputation`/`friendship` výš na ni působí
## automaticky, bez zvláštního kódu tady.
class_name QuestData
extends RefCounted

const DIR := "res://data/ukoly/"


## Načte všechny *.json z `data/ukoly/` jako hotové `DataQuest` instance (volá `Quests.setup()`).
static func load_all(game: Node, mgr: Node, player: Player) -> Array:
	var out: Array = []
	var dir := DirAccess.open(DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var fn := dir.get_next()
	while fn != "":
		if fn.ends_with(".json") and not dir.current_is_dir():
			var txt := FileAccess.get_file_as_string(DIR + fn)
			var parsed = JSON.parse_string(txt) if txt != "" else null
			if parsed is Dictionary:
				var q := DataQuest.new(parsed as Dictionary)
				q.game = game
				q.mgr = mgr
				q.player = player
				q.pid = player.id
				out.append(q)
		fn = dir.get_next()
	dir.list_dir_end()
	return out


## Jeden datový úkol – generický `Quest` řízený definicí z JSON (viz formát výš).
class DataQuest:
	extends Quests.Quest
	var def: Dictionary
	var _counts := {}     # index kroku → kolikrát už přišla sledovaná událost

	func _init(d: Dictionary) -> void:
		def = d
		id = String(def.get("id", ""))
		title = String(def.get("title", ""))
		giver = String(def.get("giver", ""))
		giver_name = String(def.get("giver_name", ""))
		intro = String(def.get("intro", ""))
		for s in (def.get("steps", []) as Array):
			steps.append(String((s as Dictionary).get("text", "")))
		if steps.is_empty():
			steps = ["Rozhodni se u %s" % giver_name]

	func _steps_def() -> Array:
		return def.get("steps", [])

	func _branches() -> Array:
		return def.get("branches", [])

	func can_start() -> bool:
		var req: Dictionary = def.get("requires", {})
		if req.is_empty():
			return true
		var rep: Reputation = game.reputations.get(pid)
		if req.has("karma_min") and (rep == null or rep.karma < float(req["karma_min"])):
			return false
		if req.has("karma_max") and (rep == null or rep.karma > float(req["karma_max"])):
			return false
		var rmin: Dictionary = req.get("respect_min", {})
		for comm in rmin:
			if rep == null or rep.respect_of(String(comm)) < float(rmin[comm]):
				return false
		if req.has("day_min") and game.clock.day() < int(req["day_min"]):
			return false
		return true

	func start() -> void:
		_counts = {}
		rules = {}

	func objective() -> String:
		if step < _steps_def().size():
			var sd: Dictionary = _steps_def()[step]
			return String(sd.get("text", "")) + closed_hint(giver)
		return String(def.get("choice_text", "Rozhodni se u %s, co dál [E]" % giver_name))

	func _near_pos(need: Dictionary) -> Vector3:
		var base_pos: Vector3 = game.place_pos(String(need.get("place", giver)))
		var off: Array = need.get("offset", [0.0, 0.0])
		return base_pos + Vector3(float(off[0]), 0.0, float(off[1]))

	func target() -> Vector3:
		if step < _steps_def().size():
			var need: Dictionary = (_steps_def()[step] as Dictionary).get("need", {})
			if String(need.get("type", "")) == "near":
				return _near_pos(need)
		return game.place_pos(giver)

	func update(delta: float) -> void:
		super.update(delta)
		if state != "active" or step >= _steps_def().size():
			return
		var need: Dictionary = (_steps_def()[step] as Dictionary).get("need", {})
		match String(need.get("type", "")):
			"near":
				if game.player_pos(pid).distance_to(_near_pos(need)) < float(need.get("radius", 10.0)):
					advance()
			"item":
				if player.item_count(String(need.get("id", ""))) >= int(need.get("count", 1)):
					if bool(need.get("consume", false)):
						player.remove_item(String(need["id"]), int(need.get("count", 1)))
					advance()

	func on_event(kind: String, data: Dictionary) -> void:
		super.on_event(kind, data)
		if state != "active" or step >= _steps_def().size():
			return
		var need: Dictionary = (_steps_def()[step] as Dictionary).get("need", {})
		if String(need.get("type", "")) != "event" or String(need.get("kind", "")) != kind:
			return
		var match_d: Dictionary = need.get("match", {})
		for k in match_d:
			if String(data.get(k, "")) != String(match_d[k]):
				return
		_counts[step] = int(_counts.get(step, 0)) + 1
		if _counts[step] >= int(need.get("count", 1)):
			advance()

	func options(place: String) -> Array:
		var out := []
		if place != giver:
			return out
		if step < _steps_def().size():
			var need: Dictionary = (_steps_def()[step] as Dictionary).get("need", {})
			if String(need.get("type", "")) == "talk":
				out.append(["Promluvit o tom (%s)" % title, advance])
			return out
		for b in _branches():
			var bd: Dictionary = b
			if _branch_ok(bd):
				out.append(["★ " + String(bd.get("label", "")), func(): _choose(bd)])
		return out

	func _branch_ok(b: Dictionary) -> bool:
		var req: Dictionary = b.get("requires", {})
		if req.has("money_min") and player.money < int(req["money_min"]):
			return false
		if req.has("item"):
			var it: Dictionary = req["item"]
			if player.item_count(String(it.get("id", ""))) < int(it.get("count", 1)):
				return false
		return true

	## Postava zadavatele pro přátelství (keeper místa, nebo npc stejného klíče – `deda`, `vcelar`…).
	func _giver_persona() -> Persona:
		if game.places.has(giver):
			var kp: Npc = (game.places[giver] as Place).keeper
			return kp.persona if kp else null
		if game.npcs.has(giver):
			return (game.npcs[giver] as Npc).persona
		return null

	func _apply_reward(r: Dictionary) -> void:
		player.money += int(r.get("money", 0))
		for it in (r.get("item_give", []) as Array):
			for i in int((it as Dictionary).get("count", 1)):
				player.add_item(String((it as Dictionary)["id"]))
		for it in (r.get("item_take", []) as Array):
			player.remove_item(String((it as Dictionary)["id"]), int((it as Dictionary).get("count", 1)))
		var rep: Reputation = game.reputations.get(pid)
		if rep:
			var resp: Dictionary = r.get("respect", {})
			for comm in resp:
				rep.change_respect(String(comm), float(resp[comm]), title)
			if r.has("karma"):
				rep.change_karma(float(r["karma"]), title)
			if r.has("reputation"):
				rep.change(float(r["reputation"]), title)
		if r.has("friendship"):
			var per := _giver_persona()
			if per:
				per.add_friendship(pid, float(r["friendship"]), game.clock.minutes, game.clock.day())

	func _choose(b: Dictionary) -> void:
		_apply_reward(b.get("reward", {}))
		var text: String = String(b.get("result_text", ""))
		if not bool(b.get("honest", true)) and b.has("risk"):
			var risk: Dictionary = b["risk"]
			if randf() < float(risk.get("chance", 0.0)):
				_apply_reward(risk.get("reward", {}))
				text += "  " + String(risk.get("text", ""))
		succeed(text, 0)
