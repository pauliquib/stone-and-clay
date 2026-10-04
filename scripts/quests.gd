## Úkoly (questy) jednoho hráče – každý hráč má vlastní uzel Quests (World.quests[id]) s vlastními
## instancemi úkolů. Vždy jeden aktivní. Každý úkol má kroky, cíl na mapě / kompasu a podmínky
## (nic nepoškodit, nezranit se, nenechat se chytit policií, dojít pěšky, nezvracet, stihnout čas…).
## Události přicházejí z world.gd (emit_game_event s id hráče): drank, ate, smoked, opened,
## bottle_broken, injured, fell, vomited, passed_out, entered_car, exited_car, car_crash, hit_person,
## hit_animal (srážka se zvěří → povinnost nahlásit, viz `hit_report`), prop_damaged, busted…  Zprávy hráči jdou přes World.notify (v MP to bude RPC na jeho klienta).
class_name Quests
extends Node

signal changed

var game: Node                   # World
var player: Player               # čí úkoly to jsou
var pid := 0
var list: Array = []
var active: Quest = null
## Srážka se zvěří čekající na nahlášení (Myslivecká chata): species, name, pos, animal, dead, deadline (herní min).
## Hlídá se odděleně od `active`, aby povinnost nezrušil jiný rozdělaný úkol; úkol „Srážka se zvěří“ ji jen zobrazuje.
var hit_report: Dictionary = {}
const HIT_REPORT_MIN := 60.0     # kolik herních minut je na nahlášení
const HIT_FINE := 2000           # pokuta za nenahlášení (Kč)
const HIT_REWARD := 150          # odměna za včasné nahlášení


func setup(g: Node, p: Player) -> void:
	game = g
	player = p
	pid = p.id
	list = [CigaretyQuest.new(), PivoQuest.new(), SlivoviceQuest.new(), AutemQuest.new(), MejdanQuest.new(),
		DegustaceQuest.new(), SrazkaZverQuest.new(), ScitaniZvereQuest.new(), KrmivoQuest.new(), ShozQuest.new(),
		MedQuest.new()]
	for q in list:
		q.game = game
		q.mgr = self
		q.player = p
		q.pid = pid


## Zpráva do HUD hráče (show_message, popup, quest_started…).
func notify(method: String, args: Array) -> void:
	game.notify(pid, method, args)


func by_id(id: String) -> Quest:
	for q in list:
		if q.id == id:
			return q
	return null


func available_at(place: String) -> Array:
	var out := []
	for q in list:
		if q.giver == place and q.state in ["available", "failed"] and q.can_start():
			out.append(q)
	return out


func accept(q: Quest) -> void:
	if active != null:
		notify("show_message", ["Už máš rozdělaný úkol: %s" % active.title, 3.0])
		return
	active = q
	q.state = "active"
	q.step = 0
	q.fail_reason = ""
	# podmínky a časový limit z minulého (nepovedeného) pokusu neplatí
	q.rules = {}
	q.deadline = -1.0
	q.start()
	notify("quest_started", [q])
	game.emit_game_event(pid, "sfx", {"name": "pickup"})
	changed.emit()


func abandon() -> void:
	if active:
		active.fail("Úkol jsi vzdal.")


func _physics_process(delta: float) -> void:
	if not hit_report.is_empty() and game.clock.minutes > float(hit_report["deadline"]):
		_hit_expired()
	if active:
		active.update(delta)


func on_event(kind: String, data: Dictionary) -> void:
	if kind == "hit_animal":
		register_hit(data)
	if active:
		active.on_event(kind, data)


## Místo, kde je hráč u dveří, může nabídnout akce aktivního úkolu (u chaty vždy i nahlášení srážky se zvěří).
func place_options(place: String) -> Array:
	var out := []
	if place == "chata" and not hit_report.is_empty():
		out.append(["Nahlásit srážku se zvěří (%s)" % hit_report["name"], report_hit])
	if active:
		out.append_array(active.options(place))
	var jb: Jobs = game.jobs.get(pid) if game.get("jobs") is Dictionary else null
	if jb:
		out.append_array(jb.place_options(place))      # M3.1: „Hledáte pracovníky?“, výplata, výpověď
	return out


# ------------------------------------------------------------------ srážka se zvěří

## Srazil jsi zvíře: do HIT_REPORT_MIN herních minut to nahlas na Myslivecké chatě, jinak pokuta.
func register_hit(data: Dictionary) -> void:
	if not hit_report.is_empty():
		notify("show_message", ["Další srážka – nahlásíš obě najednou na Myslivecké chatě.", 3.0])
		return
	var sp := String(data.get("species", ""))
	var nm := "zvíře"
	if sp != "":
		nm = String(AnimalSpecs.get_spec(sp)["name"]).to_lower()
	hit_report = {"species": sp, "name": nm, "pos": data.get("pos", Vector3.INF), "animal": data.get("animal"),
		"dead": bool(data.get("dead", false)), "deadline": game.clock.minutes + HIT_REPORT_MIN}
	var q := by_id("srazka")
	if active == null and q != null:
		accept(q)
	else:
		notify("popup", ["Srážku se zvěří (%s) nahlas do hodiny na Myslivecké chatě, jinak pokuta %d Kč." % [nm, HIT_FINE], 6.0])


## Nahlášení u chaty: myslivec pošle někoho, ať zvíře odveze; rozdělaný úkol „Srážka se zvěří“ se splní.
func report_hit() -> void:
	if hit_report.is_empty():
		return
	var rep := hit_report
	hit_report = {}
	if game.hunter:
		game.hunter.request_pickup(rep["animal"], rep["pos"])
	var dead := bool(rep["dead"])
	game.npc_say(pid, "chata", "Díky, že to hlásíš. Někoho tam pošlu, ať to odveze." if dead
		else "Díky, že to hlásíš. Zraněné zvíře nechte přírodě, my to pohlídáme.")
	game.emit_game_event(pid, "hit_reported", {"species": rep["species"]})
	if active != null and active.id == "srazka":
		active.succeed("Srážku jsi nahlásil včas. Myslivci zvíře odvezou.", HIT_REWARD)
	else:
		player.money += HIT_REWARD
		notify("show_message", ["Nahlášeno včas (+%d Kč od sdružení)." % HIT_REWARD, 3.0])


func _hit_expired() -> void:
	var rep := hit_report
	hit_report = {}
	var res: Dictionary = game.commit_offense(pid, "nenahlaseni_srazky", {"quiet": true})
	notify("police_banner", ["Srážku se zvěří jsi nenahlásil včas – pokuta mysliveckého sdružení %d Kč." % res.get("fine", HIT_FINE), 6.0])
	game.emit_game_event(pid, "hit_unreported", {"species": rep["species"]})
	if game.hunter:
		game.hunter.request_pickup(rep["animal"], rep["pos"])     # zvíře si myslivci najdou sami
	if active != null and active.id == "srazka":
		active.fail("Nahlášení jsi nestihl včas – pokuta %d Kč." % HIT_FINE)


func finished(q: Quest) -> void:
	if active == q:
		active = null
	changed.emit()


# ====================================================================== základ úkolu

class Quest:
	extends RefCounted
	var id := ""
	var title := ""
	var giver := ""          # klíč místa (hospoda, obchod, urad, sklep, palenice, deda)
	var giver_name := ""
	var intro := ""
	var steps: Array = []
	var step := 0
	var state := "available"  # available / active / done / failed
	var fail_reason := ""
	var result_text := ""
	var game: Node           # World
	var mgr: Node            # Quests hráče
	var player: Player       # hráč, který úkol plní
	var pid := 0
	# sledované podmínky
	var rules := {}           # "no_damage", "no_injury", "no_police", "on_foot", "no_passout", "no_vomit"
	var deadline := -1.0      # herní minuty
	var hidden := false       # nikdo ho nenabízí (vzniká z události) – v deníku se ukáže až po spuštění

	func can_start() -> bool:
		return true

	func start() -> void:
		pass

	func update(_delta: float) -> void:
		if deadline > 0.0 and game.clock.minutes > deadline:
			fail("Nestihl jsi to včas.")

	func objective() -> String:
		return steps[mini(step, steps.size() - 1)]

	## Poznámka k objektivu, když je cílové místo zavřené (otevírací doba).
	func closed_hint(place: String) -> String:
		if not game.places.has(place):
			return ""
		var pl: Place = game.places[place]
		if pl.is_open(game.clock.hour()):
			return ""
		return "  [color=#f96](teď zavřeno – otevírací doba: %s)[/color]" % pl.hours_text()

	## Vrátí úkol o krok zpět (např. hráč ztratil / spotřeboval potřebnou věc).
	func back_to(s: int, msg: String) -> void:
		if step == s:
			return
		step = s
		mgr.notify("show_message", ["↺ " + msg, 3.0])
		mgr.changed.emit()

	func target() -> Vector3:
		return Vector3.INF

	func options(_place: String) -> Array:
		return []

	func rule_lines() -> Array:
		var out := []
		var names := {"no_damage": "Nic nepoškodit", "no_injury": "Nezranit se", "no_police": "Nenechat se chytit policií",
			"on_foot": "Jít pěšky", "no_passout": "Neusnout / neomdlít", "no_vomit": "Nepozvracet se"}
		for k in rules:
			if rules[k]:
				out.append(names.get(k, k))
		if deadline > 0.0:
			var left: float = deadline - game.clock.minutes
			out.append("Zbývá %d h %02d min (herního času)" % [int(left / 60.0), int(left) % 60])
		return out

	func on_event(kind: String, data: Dictionary) -> void:
		if state != "active":
			return
		match kind:
			"injured":
				if rules.get("no_injury", false) and float(data["amount"]) >= 2.0:
					fail("Zranil ses (%s)." % data["reason"])
			"car_crash":
				# drobné ťuknutí (do ~15 km/h) se nepočítá, jen skutečná nehoda
				if rules.get("no_damage", false) and float(data["impact"]) >= 4.0 \
						and not (data["what"] in ["silnice", "cesta", "terén"]):
					fail("Naboural jsi: %s (%d km/h)." % [data["what"], int(float(data["impact"]) * 3.6)])
			"prop_damaged":
				if rules.get("no_damage", false):
					fail("Poškodil jsi: %s." % data["what"])
			"hit_person":
				if rules.get("no_damage", false) or rules.get("no_injury", false):
					fail("Srazil jsi člověka!")
			"busted":
				if rules.get("no_police", false):
					fail("Chytila tě policie: %s." % data["reason"])
			"entered_car":
				if rules.get("on_foot", false):
					fail("Slíbil jsi, že půjdeš pěšky.")
			"passed_out", "knocked_out":
				if rules.get("no_passout", false) or kind == "knocked_out":
					fail("Ztratil jsi vědomí.")
			"vomited":
				if rules.get("no_vomit", false):
					fail("Pozvracel ses.")

	func advance() -> void:
		step += 1
		mgr.notify("show_message", ["✔ " + objective(), 3.0])
		game.emit_game_event(pid, "sfx", {"name": "pickup"})
		mgr.changed.emit()

	func succeed(text: String, reward: int) -> void:
		state = "done"
		result_text = text
		player.money += reward
		mgr.notify("quest_done", [self, text, reward])
		game.emit_game_event(pid, "sfx", {"name": "success"})
		cleanup()
		mgr.finished(self)
		game.emit_game_event(pid, "quest_done", {"id": id, "title": title, "giver": giver})   # pověst (Reputation)

	func fail(reason: String) -> void:
		if state != "active":
			return
		state = "failed"
		fail_reason = reason
		mgr.notify("quest_failed", [self, reason])
		game.emit_game_event(pid, "sfx", {"name": "fail"})
		cleanup()
		mgr.finished(self)
		game.emit_game_event(pid, "quest_failed", {"id": id, "title": title, "reason": reason, "giver": giver})

	func cleanup() -> void:
		pass

	func near(place: String, r := 12.0) -> bool:
		return game.player_pos(pid).distance_to(game.place_pos(place)) < r


# ====================================================================== 1. cigarety pro dědu

class CigaretyQuest:
	extends Quest

	func _init() -> void:
		id = "cigarety"
		title = "Cigarety pro dědu"
		giver = "deda"
		giver_name = "Děda Vomáčka"
		intro = "Synku, došly mi cigára a nohy už nejsou co bývaly. Skoč mi do Potravin pro krabičku, ať to mám na večer. V deset jdu spát, tak ať to stihneš. Peníze ti vrátím."
		steps = ["Kup krabičku cigaret v Potravinách", "Přines cigarety dědovi Vomáčkovi (lavička u jeho domu)"]

	func start() -> void:
		# děda jde ve 22:00 spát – vždy ale aspoň 2 herní hodiny
		var day0: float = floor(game.clock.minutes / 1440.0) * 1440.0
		var bed := day0 + 22.0 * 60.0
		if bed < game.clock.minutes:
			bed += 1440.0
		deadline = maxf(bed, game.clock.minutes + 120.0)

	func objective() -> String:
		if step == 0:
			return "Kup krabičku cigaret v Potravinách (nebo v hospodě)" + closed_hint("obchod")
		return "Přines cigarety dědovi Vomáčkovi – sedí na lavičce u svého domu (%s) [E]" % game.deda_label()

	func target() -> Vector3:
		return game.place_pos("obchod") if step == 0 else game.place_pos("deda")

	func options(place: String) -> Array:
		if place == "deda" and step == 1 and player.item_count("cigarety") >= 20:
			return [["Dát dědovi cigarety", _give]]
		return []

	func update(delta: float) -> void:
		if state == "active" and deadline > 0.0 and game.clock.minutes > deadline:
			fail("Děda už šel spát – cigarety nedostal.")
			return
		super.update(delta)
		if state != "active":
			return
		if step == 0 and player.item_count("cigarety") >= 20:
			advance()
		elif step == 1 and player.item_count("cigarety") < 20:
			back_to(0, "Nemáš celou krabičku (20 ks) – kup novou v Potravinách.")

	func _give() -> void:
		player.remove_item("cigarety", 20)
		game.npc_say(pid, "deda", "Díky, synku! Na, tady máš za ně – a jednu si dej se mnou.")
		player.inventory["cigarety"] = player.item_count("cigarety") + 1
		succeed("Děda má cigarety a dal ti jednu. (Použij ji v inventáři – Tab.)", 250)


# ====================================================================== 2. páteční pivo

class PivoQuest:
	extends Quest
	var beers := 0
	var shot := false
	var walk_start := -1.0

	func _init() -> void:
		id = "pivo"
		title = "Páteční pivo"
		giver = "hospoda"
		giver_name = "Pepa (štamgast)"
		intro = "Čau! Sedni si, dáme tři točený a panáka slivovice na zdraví. Ale pak pěkně po svých domů – a ať tě ráno nevidím s modřinou!"
		steps = ["Vypij s chlapama 3 točená piva (0/3)", "Dej si s nimi panáka slivovice",
			"Dojdi pěšky domů – nic nerozbij, nezraň se"]

	func start() -> void:
		beers = 0
		shot = false
		walk_start = -1.0
		rules = {}

	func objective() -> String:
		if step == 0:
			return "Vypij s chlapama 3 točená piva (%d/3) – objednej u hostinského nebo u Pepy [E]" % beers \
				+ closed_hint("hospoda")
		if step == 1:
			return "Dej si s nimi panáka slivovice – objednej v hospodě [E]" + closed_hint("hospoda")
		return "Dojdi pěšky domů (%s) – jdi pomalu, neběhej, ať nezakopneš" % game.home_label(pid)


	func target() -> Vector3:
		return game.place_pos("hospoda") if step < 2 else game.place_pos("domov")

	func on_event(kind: String, data: Dictionary) -> void:
		super.on_event(kind, data)
		if state != "active":
			return
		if kind == "drank" and near("hospoda", 60.0):
			if step == 0 and data["id"] in ["pivo_cepovane", "pivo10"]:
				beers += 1
				game.npc_say(pid, "pepa", ["Na zdraví!", "Ještě jedno, ať nekulháš!", "Tak to je ono!"][mini(beers - 1, 2)])
				mgr.changed.emit()
				if beers >= 3:
					advance()
			elif step == 1 and data["id"] == "panak_slivovice":
				game.npc_say(pid, "pepa", "Ha! Tak a teď domů, a opatrně!")
				advance()
				walk_start = game.clock.minutes
				deadline = game.clock.minutes + 120.0
				rules = {"on_foot": true, "no_injury": true, "no_damage": true, "no_passout": true}

	func update(delta: float) -> void:
		super.update(delta)
		if state == "active" and step == 2 and player.car == null and near("domov", 7.0):
			var p: float = player.body.promile()
			succeed("Došel jsi domů v pořádku s %.2f ‰. Pepa ti proplatí útratu." % p, 300)


# ====================================================================== 3. slivovice pro starostu

class SlivoviceQuest:
	extends Quest
	var tasted := false
	var paid := false

	func _init() -> void:
		id = "slivovice"
		title = "Slivovice pro starostu"
		giver = "urad"
		giver_name = "Starosta Novák"
		intro = "Zítra máme návštěvu z kraje a já nemám čím pohostit! Dojdi mi do Pálenice U Kotla pro lahev slivovice. Ale neotvírat, ať ji nedostanu načatou! Tady máš 500 Kč."
		steps = ["Kup lahev slivovice v Pálenici U Kotla", "Doruč lahev neotevřenou starostovi na obecní úřad"]

	func start() -> void:
		tasted = false
		if not paid:     # peníze dá starosta jen napoprvé
			paid = true
			player.money += 500
		rules = {}

	func objective() -> String:
		if step == 0:
			return "Kup lahev slivovice v Pálenici U Kotla (450 Kč; v Potravinách 520 Kč)" + closed_hint("palenice")
		return "Doruč lahev neotevřenou starostovi na obecní úřad [E] – neotvírej ji, nerozbij ji (neupadni)"

	func update(delta: float) -> void:
		super.update(delta)
		if state != "active":
			return
		if step == 0 and player.item_count("slivovice") >= 1:
			advance()
		elif step == 1 and player.item_count("slivovice") == 0:
			back_to(0, "Nemáš žádnou celou lahev slivovice – kup novou.")

	func target() -> Vector3:
		return game.place_pos("palenice") if step == 0 else game.place_pos("urad")

	func on_event(kind: String, data: Dictionary) -> void:
		super.on_event(kind, data)
		if state != "active" or step < 1:
			return
		if kind == "opened" and data["id"] == "slivovice" and player.item_count("slivovice") == 0:
			fail("Otevřel jsi starostovu slivovici!")
		elif kind == "bottle_broken" and data["id"] == "slivovice" and player.item_count("slivovice") == 0:
			fail("Rozbil jsi lahev slivovice.")

	func options(place: String) -> Array:
		var out := []
		if place == "palenice" and not tasted and not player.busy:
			out.append(["Ochutnat slivovici zdarma (panák)", _taste])
		if place == "urad" and step == 1 and player.item_count("slivovice") >= 1:
			out.append(["Předat slivovici starostovi", _deliver])
		return out

	func _taste() -> void:
		tasted = true
		player.consume_served("panak_slivovice")
		game.npc_say(pid, "palenice", "No? Padesát procent, ze švestek od nás ze sadu!")

	func _deliver() -> void:
		player.remove_item("slivovice")
		game.npc_say(pid, "urad", "Výborně! Kraj bude koukat.")
		succeed("Starosta má slivovici a dal ti odměnu.", 400)


# ====================================================================== 4. autem z hospody

class AutemQuest:
	extends Quest
	var dmg0 := 0.0
	var drive_promile := -1.0

	func _init() -> void:
		id = "autem"
		title = "Autem z hospody"
		giver = "hospoda"
		giver_name = "Pepa (štamgast)"
		intro = "Tvoje Oktávka stojí před hospodou. Hele, dej si ještě jedno na cestu, jedno pivo nic není… Nebo počkej, až vystřízlivíš – najez se, dej si kafe. Hlavně ať tě nechytnou – prý dneska stojí policajti na hlavní."
		steps = ["Nastup do svého auta (červená Oktávka) u hospody [F] – nebo nejdřív vystřízlivěj (vyšší odměna)",
			"Dovez auto domů a zastav u domu", "Vystup z auta u domu [F]"]

	func can_start() -> bool:
		return game.traffic.car_of(pid) != null

	func start() -> void:
		drive_promile = -1.0
		game.move_player_car_to(pid, "hospoda")
		dmg0 = game.traffic.car_of(pid).damage
		player.consume_served("pivo_cepovane")
		mgr.notify("popup", ["Pepa ti přistrčil pivo „na cestu“ – už máš v sobě alkohol.", 4.0])
		game.setup_checkpoint_on_route("hospoda", "domov")
		rules = {"no_damage": true, "no_injury": true, "no_police": true}

	func objective() -> String:
		if step == 0:
			var p: float = player.body.promile_peak_estimate()
			if p >= 0.01:
				return steps[0] + "\n   Máš %.2f ‰ – střízlivý budeš asi za %.1f h (jídlo, kafe, spánek doma)." % [
					p, player.body.hours_to_sober()]
			return "Nastup do svého auta (červená Oktávka) u hospody [F] – máš 0,00 ‰, můžeš jet"
		return super.objective()

	func target() -> Vector3:
		if step == 0:
			return game.traffic.car_of(pid).global_position
		return game.place_park("domov")

	func on_event(kind: String, data: Dictionary) -> void:
		super.on_event(kind, data)
		if state != "active":
			return
		if kind == "entered_car" and data["car"] == game.traffic.car_of(pid) and step == 0:
			drive_promile = player.body.promile()
			advance()

	func update(delta: float) -> void:
		super.update(delta)
		if state != "active":
			return
		var car: Car = game.traffic.car_of(pid)
		if car.damage - dmg0 > 15.0:
			fail("Poškodil jsi auto (%d %%)." % int(car.damage - dmg0))
			return
		var at_home: bool = car.global_position.distance_to(game.place_park("domov")) < 18.0
		if step == 1 and at_home and absf(car.speed) < 1.5:
			advance()
		if step == 2 and at_home and player.car == null:
			if drive_promile < 0.01:
				succeed("Vzorný řidič! Počkal jsi, až budeš mít 0,00 ‰, a dojel domů bez škrábnutí.", 800)
			else:
				succeed("Dojel jsi domů s %.2f ‰ za volantem. Tentokrát to vyšlo – ale riskoval jsi život." % drive_promile, 300)
		elif step == 2 and not at_home:
			back_to(1, "Odjel jsi od domu – zastav u domu (%s)." % game.home_label(pid))

	func cleanup() -> void:
		game.police.clear_checkpoint()


# ====================================================================== 5. mejdan na chatě

class MejdanQuest:
	extends Quest
	var toasts := 0
	var party_t := 0.0
	var paid := false

	func _init() -> void:
		id = "mejdan"
		title = "Mejdan na chatě"
		giver = "obchod"
		giver_name = "Prodavačka Jarka"
		intro = "Myslivec Franta tu nechal vzkaz a 800 Kč: ať mu někdo koupí vodku, rum a dvě vína a donese to na Mysliveckou chatu do 22 hodin. Chata je v lese severně od vsi."
		steps = ["Kup vodku, rum a 2 lahve vína", "Dones nákup na Mysliveckou chatu", "Připij si s myslivci (2 panáky)",
			"Vydrž na mejdanu 45 minut – nepozvracej se, neusni"]

	func start() -> void:
		toasts = 0
		party_t = 0.0
		if not paid:     # Frantovy peníze jen napoprvé
			paid = true
			player.money += 800
		var day0: float = floor(game.clock.minutes / 1440.0) * 1440.0
		# do 22:00, ale vždy aspoň 2,5 herní hodiny
		deadline = maxf(day0 + 22.0 * 60.0, game.clock.minutes + 150.0)
		rules = {}

	func _have() -> bool:
		var p: Player = player
		return p.item_count("vodka") >= 1 and p.item_count("rum") >= 1 and \
			p.item_count("vino_bile") + p.item_count("vino_cervene") >= 2

	func objective() -> String:
		if step == 0:
			var p: Player = player
			return "Kup v Potravinách vodku (%d/1), rum (%d/1) a 2 vína (%d/2)" % [mini(p.item_count("vodka"), 1),
				mini(p.item_count("rum"), 1), mini(p.item_count("vino_bile") + p.item_count("vino_cervene"), 2)] \
				+ closed_hint("obchod")
		if step == 1:
			return "Dones nákup na Mysliveckou chatu (les severně od vsi) a předej ho myslivci Frantovi [E]"
		if step == 2:
			return "Připij si s myslivci (%d/2 panáky) [E]" % toasts
		if step == 3:
			var s := "Vydrž na mejdanu u chaty – zbývá %d herních min" % int(maxf(45.0 - party_t, 0.0))
			if not near("chata", 80.0):
				s += "  [color=#f96](vrať se k chatě!)[/color]"
			return s
		return super.objective()

	func update(delta: float) -> void:
		if step < 2:
			super.update(delta)
		if state != "active":
			return
		if step == 0 and _have():
			advance()
		elif step == 1 and not _have():
			back_to(0, "Něco z nákupu ti chybí (rozbitá / otevřená lahev) – dokup to.")
		elif step == 3:
			if near("chata", 80.0):
				party_t += delta * Clock.TIME_SCALE / 60.0
			if party_t >= 45.0:
				succeed("Myslivci jsou nadšení. Franta: „Příště jdeš s námi na hon!“", 400)

	func target() -> Vector3:
		return game.place_pos("obchod") if step == 0 else game.place_pos("chata")

	func options(place: String) -> Array:
		var out := []
		if place == "chata" and step == 1 and _have():
			out.append(["Předat nákup myslivcům", _hand_over])
		if place == "chata" and step == 2 and not player.busy:
			out.append(["Připít si (%s)" % ("vodka" if toasts == 0 else "slivovice"), _toast])
		return out

	func _hand_over() -> void:
		var p: Player = player
		p.remove_item("vodka")
		p.remove_item("rum")
		for i in 2:
			if not p.remove_item("vino_cervene"):
				p.remove_item("vino_bile")
		deadline = -1.0
		rules = {"no_vomit": true, "no_passout": true}
		game.npc_say(pid, "chata", "Ty jsi poklad! Tak na zdraví, nalej si!")
		advance()

	func _toast() -> void:
		player.consume_served("panak_vodky" if toasts == 0 else "panak_slivovice")
		toasts += 1
		game.npc_say(pid, "chata", ["Na zdraví!", "Lovu zdar!"][mini(toasts - 1, 1)])
		if toasts >= 2:
			advance()
		mgr.changed.emit()


# ====================================================================== 6. degustace vína

class DegustaceQuest:
	extends Quest
	var samples := 0
	const N := 6
	const LIMIT := 1.0

	func _init() -> void:
		id = "degustace"
		title = "Degustace ve sklepě"
		giver = "sklep"
		giver_name = "Vinař Zdeněk"
		intro = "Vítej ve sklepě! Ochutnáš šest vzorků a řekneš, co se ti líbí. Ale kdo se na konci motá (víc než 1,0 ‰), ten u mě nic nekoupí. Chleba se sádlem máme, jestli chceš."
		steps = ["Ochutnej 6 vzorků vína (0/6) [E u vinaře]", "Na konci ochutnávky měj nejvýš 1,0 ‰"]

	func start() -> void:
		samples = 0
		rules = {"no_vomit": true}

	func objective() -> String:
		if step == 0:
			var est: float = player.body.promile_peak_estimate()
			return ("Ochutnej 6 vzorků vína (%d/6) u vinaře [E] – mezi vzorky se najez (chleba se sádlem) a dej si čas\n" \
				+ "   Odhad tvého promile po vstřebání: [color=%s]%.2f ‰[/color] (limit 1,00 ‰)") % [
				samples, "#f66" if est > LIMIT else "#9f9", est]
		return super.objective()

	func target() -> Vector3:
		return game.place_pos("sklep")

	func options(place: String) -> Array:
		if place == "sklep" and step == 0 and samples < N and not player.busy:
			var names := ["Ryzlink rýnský", "Veltlínské zelené", "Muškát moravský", "Frankovka", "Svatovavřinecké", "Cabernet Moravia"]
			return [["Ochutnat vzorek: %s (%d/%d)" % [names[samples], samples + 1, N], _sample]]
		return []

	func _sample() -> void:
		player.consume_served("degustace")
		samples += 1
		mgr.changed.emit()
		if samples >= N:
			_evaluate.call_deferred()

	## Hodnotí se až po vypití posledního vzorku (odhad vrcholu promile po vstřebání).
	func _evaluate() -> void:
		await game.get_tree().create_timer(3.5).timeout
		if state != "active":
			return
		advance()
		var peak: float = player.body.promile_peak_estimate()
		if peak <= LIMIT:
			player.add_item("vino_cervene")
			succeed("Zvládl jsi to s odhadem %.2f ‰. Vinař ti dal lahev Frankovky." % peak, 200)
		else:
			fail("Vinař: „Ty už máš dost (%.2f ‰). Běž se vyspat!“" % peak)


# ====================================================================== 7. srážka se zvěří

## Vznikne sama po srážce auta se zvěří (Quests.register_hit); termín i pokutu hlídá Quests.hit_report.
class SrazkaZverQuest:
	extends Quest

	func _init() -> void:
		id = "srazka"
		title = "Srážka se zvěří"
		giver = "chata"
		giver_name = "Myslivec Franta"
		hidden = true
		intro = "Srazil jsi zvěř. Nahlas to mysliveckému sdružení, ať zvíře odvezou."
		steps = ["Nahlas srážku se zvěří na Myslivecké chatě"]

	func can_start() -> bool:
		return false

	func start() -> void:
		deadline = float(mgr.hit_report.get("deadline", game.clock.minutes + 60.0))

	func update(_delta: float) -> void:
		pass         # termín a pokutu řeší Quests (funguje i při jiném rozdělaném úkolu)

	func objective() -> String:
		var left: float = maxf(deadline - game.clock.minutes, 0.0)
		return "Nahlas srážku (%s) na Myslivecké chatě [E] – zbývá %d min herního času, jinak pokuta %d Kč" % [
			mgr.hit_report.get("name", "zvěř"), int(left), Quests.HIT_FINE]

	func target() -> Vector3:
		return game.place_pos("chata")


# ====================================================================== 8. sčítání zvěře

class ScitaniZvereQuest:
	extends Quest
	const N_NEED := 6
	const RANGE := 250.0            # dalekohledem započítá zvířata do této vzdálenosti (m)
	const CONE_DEG := 7.0           # … a jen v tomto kuželu okolo osy pohledu
	var seen := {}                  # instance zvířete → true (jedno zvíře se počítá jednou)
	var _t := 0.0

	func _init() -> void:
		id = "scitani"
		title = "Sčítání zvěře"
		giver = "chata"
		giver_name = "Myslivec Franta"
		intro = "Děláme jarní i podzimní sčítání zvěře. Vezmi dalekohled (držet X), vyraz na louky a k okraji lesa a spočítej mi šest kusů – každé zvíře jen jednou. Nezaháněj je. V zimě zkus krmelec."
		steps = ["Spočítej zvěř dalekohledem (0/6)", "Nahlas počet myslivci na chatě"]

	func start() -> void:
		seen = {}
		_t = 0.0
		deadline = game.clock.minutes + 240.0
		rules = {}

	func objective() -> String:
		if step == 0:
			return "Spočítej zvěř dalekohledem – drž [X] a zaměř zvíře do %d m (%d/%d). Louky, okraj lesa, v zimě krmelec." % [
				int(RANGE), seen.size(), N_NEED]
		return "Nahlas počet (%d ks) myslivci na Myslivecké chatě [E]" % seen.size()

	func target() -> Vector3:
		return game.place_pos("chata") if step == 1 else Vector3.INF

	func update(delta: float) -> void:
		super.update(delta)
		if state != "active" or step != 0:
			return
		_t -= delta
		if _t > 0.0:
			return
		_t = 0.4
		_scan()

	func _scan() -> void:
		var p: Player = player
		if p.scope < 0.6 or p.camera == null:
			return
		var origin: Vector3 = p.camera.global_position
		var fwd: Vector3 = -p.camera.global_transform.basis.z
		var cos_cone := cos(deg_to_rad(CONE_DEG))
		for a in game.fauna.animals:
			if not is_instance_valid(a) or a.dead or seen.has(a.get_instance_id()) or a._lod == Animal.Lod.FAR:
				continue
			var at: Vector3 = a.global_position + Vector3(0, 0.6, 0)
			var to: Vector3 = at - origin
			var d: float = to.length()
			if d > RANGE or d < 3.0 or fwd.dot(to / d) < cos_cone:
				continue
			if not game.line_clear(origin, at):
				continue
			seen[a.get_instance_id()] = true
			mgr.notify("show_message", ["Započítáno: %s (%d/%d)" % [String(a.spec["name"]).to_lower(), seen.size(), N_NEED], 2.0])
			mgr.changed.emit()
			if seen.size() >= N_NEED:
				advance()
				return

	func options(place: String) -> Array:
		if place == "chata" and step == 1:
			return [["Nahlásit sčítání (%d ks)" % seen.size(), _report]]
		return []

	func _report() -> void:
		game.npc_say(pid, "chata", "Šest kusů, dobrá práce. Zapíšu to do knihy.")
		succeed("Myslivec zapsal tvé sčítání do knihy. Zvěř ve zdejších lesích je v pořádku.", 300)


# ====================================================================== 9. krmivo ke krmelci

class KrmivoQuest:
	extends Quest
	var carrying := false
	var _walk0 := 0.0
	var _sprint0 := 0.0
	const SLOW := 0.8                # s pytlem se jde o pětinu pomaleji

	func _init() -> void:
		id = "krmivo"
		title = "Krmivo ke krmelci"
		giver = "chata"
		giver_name = "Myslivec Franta"
		intro = "Krmelec je skoro prázdný a zvěř nemá co žrát. Vezmi u chaty pytel krmiva (kaštany, seno, šrot) a vysyp ho do krmelce v lese. Pytel něco váží, tak nespěchej."
		steps = ["Vezmi pytel krmiva u chaty", "Odnes pytel ke krmelci a vysyp ho"]

	func start() -> void:
		carrying = false
		rules = {}

	func objective() -> String:
		if step == 0:
			return "Vezmi pytel krmiva u Myslivecké chaty [E]"
		return "Odnes pytel ke krmelci v lese (%d m) a vysyp ho [E]" % int(player.global_position.distance_to(target()))

	func target() -> Vector3:
		if step == 0 or game.hunter == null or game.hunter.feeders.is_empty():
			return game.place_pos("chata")
		return game.hunter.nearest_feeder(player.global_position)

	func options(place: String) -> Array:
		if place == "chata" and step == 0:
			return [["Vzít pytel krmiva (25 kg)", _take]]
		return []

	func _take() -> void:
		carrying = true
		_walk0 = player.walk_speed
		_sprint0 = player.sprint_speed
		player.walk_speed = _walk0 * SLOW
		player.sprint_speed = _sprint0 * SLOW
		game.npc_say(pid, "chata", "Krmelec najdeš v lese za chatou. Ať to zvěř nevyplašíš!")
		advance()

	## Volá Hunter, když hráč u krmelce stiskne E.
	func deliver(feeder_i: int) -> void:
		game.hunter.fill_feeder(feeder_i)
		succeed("Krmelec je plný. Zvěř bude mít v zimě co žrát.", 350)

	func cleanup() -> void:
		if carrying:
			player.walk_speed = _walk0
			player.sprint_speed = _sprint0
			carrying = false


# ====================================================================== 10. shoz parůžků

class ShozQuest:
	extends Quest
	const N := 4
	var found := 0

	func _init() -> void:
		id = "shoz"
		title = "Shozené parůžky"
		giver = "chata"
		giver_name = "Myslivec Franta"
		intro = "V březnu a dubnu srnci shazují paroží. Projdi les a okraje kolem chaty a najdi čtyři shozené parůžky – sbírat je můžeš, jen nezaháněj zvěř. Odevzdáš je u chaty."
		steps = ["Najdi shozené parůžky (0/4)", "Odevzdej parůžky myslivci na chatě"]

	func can_start() -> bool:
		var m: int = game.clock.month()
		return (m == 3 or m == 4) and game.hunter != null

	func start() -> void:
		found = 0
		rules = {}
		game.hunter.spawn_antlers(N)

	func objective() -> String:
		if step == 0:
			return "Najdi shozené parůžky v lese a na okraji lesa kolem chaty (%d/%d) [E]" % [found, N]
		return "Odevzdej parůžky (%d ks) myslivci na Myslivecké chatě [E]" % found

	func target() -> Vector3:
		if step == 1:
			return game.place_pos("chata")
		var n: Vector3 = game.hunter.nearest_antler(player.global_position)
		return n if n != Vector3.INF and n.distance_to(player.global_position) < 40.0 else Vector3.INF

	func update(delta: float) -> void:
		super.update(delta)
		if state == "active" and step == 0:
			var f: int = N - game.hunter.antlers_left()
			if f != found:
				found = f
				mgr.changed.emit()
			if found >= N:
				advance()

	func options(place: String) -> Array:
		if place == "chata" and step == 1:
			return [["Odevzdat parůžky (%d ks)" % found, _hand_over]]
		return []

	func _hand_over() -> void:
		game.npc_say(pid, "chata", "Krásné! Tyhle půjdou na stěnu do chaty. Máš ode mě odměnu.")
		succeed("Parůžky jsou na chatě. Myslivec Franta je pověsil na zeď.", 300)

	func cleanup() -> void:
		game.hunter.clear_antlers()


# ====================================================================== 11. med u včelaře

class MedQuest:
	extends Quest

	func _init() -> void:
		id = "med"
		title = "Vytočit med"
		giver = "vcelar"
		giver_name = "Včelař Vilém"
		intro = "Med je zralý a musí se vytočit dřív, než začne fermentovat. Vezmi si kuklu a kouřák, okuř úly a přines mi plátve. S kuklou tě včely nebodnou, bez ní bys toho litoval."
		steps = ["Vezmi si u včelaře kuklu a kouřák", "Dojdi k úlům a okuř je kouřákem (drž E 5 s)",
			"Odnes plástve včelaři do medometu"]

	func can_start() -> bool:
		var m: int = game.clock.month()
		var h: float = game.clock.hour()
		return m >= 4 and m <= 9 and h >= 7.0 and h < 19.0 and game.hunter != null and game.hunter.beekeeper != null

	func start() -> void:
		rules = {}

	func objective() -> String:
		match step:
			0:
				return "Vezmi si u včelaře kuklu a kouřák [E]"
			1:
				return "Dojdi k úlům (%d m) a okuř je kouřákem – drž [E] 5 s" % int(player.global_position.distance_to(target()))
		return "Odnes plátve včelaři do medometu [E]"

	func target() -> Vector3:
		if step == 1:
			return game.hunter.apiary_pos()
		return game.hunter.beekeeper_pos()

	func options(place: String) -> Array:
		if place != "vcelar":
			return []
		if step == 0:
			return [["Vzít kuklu a kouřák", _take_gear]]
		if step == 2:
			return [["Předat plátve a vytočit med", _finish]]
		return []

	func _take_gear() -> void:
		player.beekeeper_suit = true
		game.npc_say(pid, "vcelar", "Nasaď si kuklu, ať tě nepíchnou. Kouř rozvažuj pomalu, včely nemají rády spěch.")
		advance()

	## Volá Hunter po 5 s okuřování úlů.
	func smoked() -> void:
		if state == "active" and step == 1:
			mgr.notify("show_message", ["Úly jsou okuřené, včely se uklidnily. Vyber plátve a odnes je včelaři.", 3.5])
			advance()

	func _finish() -> void:
		game.npc_say(pid, "vcelar", "To je zlatý med! Na, vezmi si sklenici pro sebe.")
		player.add_item("med")
		succeed("Med je vytočený. Včelař ti dal sklenici lipového medu.", 350)

	func cleanup() -> void:
		player.beekeeper_suit = false
