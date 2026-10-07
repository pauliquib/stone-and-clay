## Pověst jednoho hráče v obci (World.reputations[id]) – hodnotí, jestli se chová slušně a podle zákona.
## Skóre −100..100 (začíná na 0). Body ubírají přestupky a trestné činy (řízení pod vlivem nebo přes zákaz,
## ujetí policii, sražení chodce, vandalismus, nehody, rychlá jízda obcí, výtržnosti v opilosti, urážky
## a vyhrůžky), přidávají dobré skutky (splněné úkoly, čistá dechová zkouška, slušné chování v rozhovoru).
## Bez nových přestupků se špatná pověst pomalu zlepšuje (lidi zapomínají).
##
## Na pověst reagují: vesničané (pozdravy, odpovědi – Dialog.attitude), hostinský / vinař (odmítnou nalít),
## ceny (vážený občan má slevu, postrach vsi přirážku), policie (častější náhodné kontroly).
## Události přicházejí z World.emit_game_event; průběžné přestupky (jízda) hlídá _physics_process.
##
## M0.6: kromě pověsti (−100..100, kterou vidí všichni) jsou tu dvě další osy:
##  - respekt po komunitách (COMMUNITIES, −100..100): slušnost, splněné úkoly a urážky mění respekt té skupiny,
##    do níž patří postava / zadavatel (community_of); ovlivní tón pozdravu (World.dialog_context → ctx.respect)
##    a v dalších krocích dostupnost práce a spolků (respect_of);
##  - skrytá karma (−100..100): přestupky a špatné skutky ji snižují i bez svědků, dobré zvyšují; hráč ji vidí
##    jen slovně (karma_word), hra ji používá jako „štěstí“ (luck) – úspěch akcí, nálezy, náhodné události.
## Přestupek z katalogu zákona (událost „offense“) mění jen karmu – pověst už strhla původní událost (busted…).
class_name Reputation
extends Node

const TIERS := [   # [od skóre, klíč, název, barva]
	[60.0, "vazeny", "vážený občan", Color(0.45, 0.95, 0.5)],
	[25.0, "slusny", "slušný soused", Color(0.7, 0.95, 0.55)],
	[-25.0, "neutral", "nenápadný obyvatel", Color(0.9, 0.9, 0.85)],
	[-60.0, "problemovy", "problémový soused", Color(1.0, 0.7, 0.35)],
	[-101.0, "postrach", "postrach vsi", Color(1.0, 0.35, 0.3)],
]
## Komunity: id → [název, kdo do ní patří, barva]. Zařazení postavy řeší community_of.
const COMMUNITIES := {
	"sousede": ["Sousedé", "běžní obyvatelé, důchodci, úřad, obchod", Color(0.75, 0.85, 0.95)],
	"stamgasti": ["Štamgasti", "hospoda, pálenice, sklep, vinaři", Color(0.95, 0.75, 0.3)],
	"hasici": ["Hasiči", "sbor dobrovolných hasičů", Color(0.95, 0.3, 0.25)],
	"fotbal": ["Fotbalisté", "fotbalový oddíl a jeho fanoušci", Color(0.4, 0.85, 0.5)],
	"zemedelci": ["Zemědělci a myslivci", "pole, les, zvěř, včely, chata", Color(0.55, 0.7, 0.35)],
	"mladez": ["Mládež", "mladí do ~25 let", Color(0.75, 0.55, 0.95)],
}
## Laditelná tabulka dopadů. Klíč = událost; hodnoty: respect (komunita se určí podle události – viz on_event),
## karma. Pověst tu zůstává v on_event beze změny (dopady se nesmí změnit).
const EVENT_EFFECTS := {
	"quest_done": {"respect": 6.0, "karma": 1.0},
	"quest_failed": {"respect": -1.0, "karma": 0.0},
	"hit_reported": {"karma": 2.0},
	"hit_person": {"karma": -5.0},
	"breath_test_ok": {"karma": 0.5},
}
## Přepis karmy za přestupek (id → změna). Výchozí hodnota je v katalogu `data/zakon.json` (pole `karma`);
## tady jen výjimky, které se mají lišit od dat. Bez obojího: −1, trestný čin −5.
const OFFENSE_KARMA := {}
const INSULT_RESPECT := -3.0
const INSULT_KARMA := -1.0
const POLITE_RESPECT := 1.0       # slušný rozhovor: max. +2 za den od jedné postavy (Persona.allow_respect)
const KARMA_LUCK := 0.2           # luck() = karma / 100 * KARMA_LUCK
const FORGIVE_AFTER_H := 24.0     # po tolika herních hodinách bez přestupku se pověst začne zlepšovat
const FORGIVE_PER_H := 0.6        # o kolik bodů za herní hodinu (jen do nuly)

var game: World
var player: Player
var pid := 0
var score := 0.0
var offenses := {}                # druh přestupku → počet
var good_deeds := 0
var respect := {}                 # komunita → −100..100
var karma := 0.0                  # −100..100, skrytá
var karma_history: Array = []     # [{t, text, delta}] – posledních 30 změn (jen pro ladění, hráč nevidí)
var history: Array = []           # [{t: herní minuty, text, delta}] – posledních 30 změn
var last_offense_min := -1.0e9
var last_offense_text := ""       # pro drby („povídá se, že prý …“)

var _tick := 0.0
var _dui_trip := false            # tahle jízda už se započítala jako řízení pod vlivem
var _ban_trip := false            # … jako řízení přes zákaz
var _dui_t := 0.0
var _speed_cool := 0.0
var _drunk_cool := 0.0
var _last_h := -1.0


func setup(g: World, p: Player) -> void:
	game = g
	player = p
	pid = p.id
	for k in COMMUNITIES:
		respect[k] = 0.0


# ------------------------------------------------------------------ stav

func tier() -> Array:
	for t in TIERS:
		if score >= t[0]:
			return t
	return TIERS[-1]


func tier_key() -> String:
	return tier()[1]


func tier_name() -> String:
	return tier()[2]


func tier_color() -> Color:
	return tier()[3]


## Násobič cen v obchodech a hospodě.
func price_mult() -> float:
	match tier_key():
		"vazeny": return 0.9
		"problemovy": return 1.1
		"postrach": return 1.25
	return 1.0


## Obsluha odmítne nalít / prodat (hospoda, sklep, pálenice) – jen postrachu vsi.
func refused_at(place: String) -> bool:
	return tier_key() == "postrach" and place in ["hospoda", "sklep", "palenice"]


## Kolik k pravděpodobnosti náhodné policejní kontroly přidat (špatná pověst = častěji).
func police_extra() -> float:
	return clampf(-score / 100.0, 0.0, 1.0) * 0.4


# ------------------------------------------------------------------ respekt a karma (M0.6)

static func community_name(comm: String) -> String:
	return String(COMMUNITIES[comm][0]) if COMMUNITIES.has(comm) else comm


func respect_of(comm: String) -> float:
	return float(respect.get(comm, 0.0))


## Slovní stupeň respektu komunity (deník J).
static func respect_word(v: float) -> String:
	if v >= 60.0: return "obdivují tě"
	if v >= 25.0: return "váží si tě"
	if v > -15.0: return "nevšímají si tě"
	if v > -50.0: return "nemají tě rádi"
	return "nesnášejí tě"


static func respect_color(v: float) -> Color:
	if v >= 25.0: return Color(0.6, 0.95, 0.6)
	if v > -15.0: return Color(0.8, 0.8, 0.8)
	return Color(1.0, 0.55, 0.5)


## Změna respektu komunity `comm`; krátká zpráva jako u pověsti („Hasiči: +3 – pomohl při soutěži“).
func change_respect(comm: String, delta: float, text: String) -> void:
	if delta == 0.0 or not COMMUNITIES.has(comm):
		return
	respect[comm] = clampf(respect_of(comm) + delta, -100.0, 100.0)
	game.notify(pid, "respect_changed", [community_name(comm), delta, text])


## Skrytá změna karmy – bez hlášky na HUD, jen do historie.
func change_karma(delta: float, why: String) -> void:
	if delta == 0.0:
		return
	karma = clampf(karma + delta, -100.0, 100.0)
	karma_history.append({"t": game.clock.minutes, "text": why, "delta": delta})
	if karma_history.size() > 30:
		karma_history.pop_front()


## Slovní popis karmy (5 stupňů) – hráč číslo nevidí.
func karma_word() -> String:
	if karma >= 40.0: return "čisté svědomí"
	if karma >= 12.0: return "klidné svědomí"
	if karma > -12.0: return "nic zvláštního"
	if karma > -40.0: return "něco tě tíží"
	return "prokletý"


func karma_color() -> Color:
	if karma >= 12.0: return Color(0.6, 0.95, 0.6)
	if karma > -12.0: return Color(0.8, 0.8, 0.8)
	return Color(1.0, 0.55, 0.5)


## „Štěstí“ z karmy −0,2..+0,2 (háček: šance na nález, úspěch akce, náhodné události).
func luck() -> float:
	return clampf(karma / 100.0, -1.0, 1.0) * KARMA_LUCK


## Komunita postavy podle povolání, témat, místa a věku (priorita: hasiči, zemědělci, fotbal, štamgasti, mládež).
static func community_of(persona: Persona) -> String:
	if persona == null:
		return "sousede"
	var pr: Dictionary = persona.profile
	var job := String(pr.get("job", "")).to_lower()
	var topics: Array = pr.get("topics", [])
	if "hasici" in topics or job.contains("hasič"):
		return "hasici"
	if job.contains("zeměděl") or job.contains("myslivec") or job.contains("traktor") or job.contains("včelař") \
			or "pole" in topics or "zver" in topics or "vcely" in topics:
		return "zemedelci"
	if "fotbal" in topics or job.contains("trenér"):
		return "fotbal"
	if String(pr.get("place", "")) in ["hospoda", "sklep", "palenice"] or "pivo" in topics or "vino" in topics \
			or job.contains("hospod") or job.contains("vinař"):
		return "stamgasti"
	if int(pr.get("age", 40)) <= 25 or String(pr.get("trait", "")) == "mlady":
		return "mladez"
	return "sousede"


## Komunita zadavatele úkolu (klíč místa v Quest.giver).
static func community_of_giver(giver: String) -> String:
	match giver:
		"hospoda", "sklep", "palenice": return "stamgasti"
		"chata": return "zemedelci"
	return "sousede"


func _apply_effects(key: String, why: String, comm := "") -> void:
	var e: Dictionary = EVENT_EFFECTS.get(key, {})
	if comm != "" and e.has("respect"):
		change_respect(comm, float(e["respect"]), why)
	if e.has("karma"):
		change_karma(float(e["karma"]), why)


## Rozhovor s postavou (volá World._apply_reply): slušnost = respekt komunity a přátelství, urážka je snižuje.
## `polite` = odpověď přidala pověst; `insult` = urážka / vyhrůžka; `cop` = policista (bez komunity, karmu řeší přestupek).
func on_chat(per: Persona, polite: bool, insult: bool, cop: bool) -> void:
	if per == null:
		return
	var day := game.clock.day()
	var now := game.clock.minutes
	var comm := community_of(per)
	if insult:
		per.add_friendship(pid, Persona.FRIEND_INSULT, now, day)
		if cop:
			return
		change_respect(comm, INSULT_RESPECT, "urazil %s" % per.first_name())
		change_karma(INSULT_KARMA, "urážka")
	elif polite:
		var d := per.allow_respect(pid, day, POLITE_RESPECT)
		if d > 0.0:
			change_respect(comm, d, "slušný rozhovor s %s" % per.first_name())
		per.add_friendship(pid, Persona.FRIEND_POLITE, now, day)


# ------------------------------------------------------------------ změny

## Změna pověsti. `offense` = druh přestupku do rejstříku (nebo "" – jen změna pověsti).
func change(delta: float, text: String, offense := "") -> void:
	if delta == 0.0:
		return
	var old_tier := tier_key()
	score = clampf(score + delta, -100.0, 100.0)
	var now := game.clock.minutes
	history.append({"t": now, "text": text, "delta": delta})
	if history.size() > 30:
		history.pop_front()
	if offense != "":
		offenses[offense] = int(offenses.get(offense, 0)) + 1
		last_offense_min = now
		last_offense_text = text
	elif delta > 0.0:
		good_deeds += 1
	game.notify(pid, "reputation_changed", [delta, text, score, tier_name(), tier_color(), tier_key() != old_tier])


func on_event(kind: String, data: Dictionary) -> void:
	match kind:
		"offense":
			# pověst už strhla původní událost (busted, chase…); tady jen skrytá karma
			var oid := String(data.get("id", ""))
			var def_k: float = -5.0 if data.get("criminal", false) else -1.0
			var kd := float(OFFENSE_KARMA.get(oid, Law.offense(oid).get("karma", def_k)))
			change_karma(kd, "přestupek: %s" % oid)
		"busted":
			var p: float = data.get("promile", 0.0)
			var reason: String = data.get("reason", "")
			if reason.begins_with("řízení přes zákaz"):
				change(-18.0, "řídil přes zákaz řízení", "řízení přes zákaz")
			elif p >= 1.0:
				change(-25.0, "řídil opilý (%s ‰) – trestný čin" % _pm(p), "řízení pod vlivem (trestný čin)")
			else:
				change(-12.0, "řídil pod vlivem (%s ‰)" % _pm(p), "řízení pod vlivem (přestupek)")
		"escaped_police":
			change(-15.0, "ujel policii", "ujetí policii")
		"police_chase":
			var reason: String = data.get("reason", "")
			if reason.begins_with("překročení rychlosti"):
				change(-3.0, "jel příliš rychle %s" % reason.trim_prefix("překročení rychlosti "), "překročení rychlosti")
		"hit_person":
			change(-30.0, "srazil chodce autem", "sražení chodce")
			_apply_effects("hit_person", "srazil chodce")
		"hit_animal":
			if data.get("species", "") == "kun":
				change(-8.0, "srazil koně", "sražení zvířete")
			else:
				change(-1.0, "srazil zvíře na silnici")
		"hit_unreported":
			change(-5.0, "neohlásil srážku se zvěří", "neohlášená srážka se zvěří")
		"hit_reported":
			change(2.0, "včas nahlásil srážku se zvěří")
			_apply_effects("hit_reported", "nahlásil srážku")
		"prop_damaged":
			change(-4.0, "poškodil %s" % String(data.get("what", "cizí věc")), "poškození cizí věci")
		"car_crash":
			var what: String = data.get("what", "")
			if what == "auto" and float(data.get("impact", 0.0)) >= 4.0:
				change(-5.0, "naboural jiné auto", "dopravní nehoda")
			elif float(data.get("impact", 0.0)) >= 8.0 and what not in ["silnice", "cesta", "terén"]:
				change(-2.0, "naboural (%s)" % what, "dopravní nehoda")
		"breath_test":
			if float(data.get("promile", 1.0)) < 0.25 and game.police.license_ok(player):
				change(3.0, "dechová zkouška v pořádku (0,00 ‰ za volantem)")
				_apply_effects("breath_test_ok", "čistá dechová zkouška")
		"vomited":
			if _witnesses(15.0) > 0:
				change(-3.0, "zvracel na veřejnosti", "výtržnost v opilosti")
		"passed_out":
			if player.global_position.distance_to(game.places["domov"].door) > 25.0:
				change(-5.0, "ležel opilý v bezvědomí na veřejnosti", "výtržnost v opilosti")
		"quest_done":
			change(8.0, "pomohl ve vsi: %s" % String(data.get("title", "")))
			_apply_effects("quest_done", "pomohl: %s" % String(data.get("title", "")), community_of_giver(String(data.get("giver", ""))))
		"quest_failed":
			if String(data.get("reason", "")) != "Úkol jsi vzdal.":
				change(-2.0, "nesplnil, co slíbil: %s" % String(data.get("title", "")))
				_apply_effects("quest_failed", "nesplnil: %s" % String(data.get("title", "")), community_of_giver(String(data.get("giver", ""))))
		"exited_car":
			_dui_trip = false
			_ban_trip = false
			_dui_t = 0.0


## Kolik vesničanů a postav je do `r` m od hráče (svědci).
func _witnesses(r: float) -> int:
	var n := 0
	var pos := game.player_pos(pid)
	for w in game.witness_check(pid, pos, "pověst", r):      # M4.4: jednotné svědky (vidí = počítá se)
		if w["sees"]:
			n += 1
	return n


static func _pm(p: float) -> String:
	return ("%.2f" % p).replace(".", ",")


# ------------------------------------------------------------------ průběžně (jízda, opilost, zapomínání)

func _physics_process(delta: float) -> void:
	var __t0 := Tests.prof_t0()
	_physics_process_impl(delta)
	Tests.prof_add("reputation", __t0)


func _physics_process_impl(delta: float) -> void:
	if game == null or not game.ready_done or not is_instance_valid(player):
		return
	_speed_cool = maxf(_speed_cool - delta, 0.0)
	_drunk_cool = maxf(_drunk_cool - delta, 0.0)
	_tick += delta
	if _tick < 0.5:
		return
	var dt := _tick
	_tick = 0.0
	var p := player.body.promile()
	var c := player.car
	if c and absf(c.speed) > 3.0:
		# řízení pod vlivem (i na kole) – svědomí, i když to nikdo nevidí: jednou za jízdu, pak za každou minutu
		if p >= 0.25:
			if not _dui_trip:
				_dui_trip = true
				change(-6.0, "řídil pod vlivem (%s ‰)" % _pm(p), "řízení pod vlivem")
			_dui_t += dt
			if _dui_t > 60.0:
				_dui_t = 0.0
				change(-2.0, "dál řídí pod vlivem")
		if not game.police.license_ok(player) and not _ban_trip:
			_ban_trip = true
			change(-5.0, "řídí přes zákaz řízení", "řízení přes zákaz")
		# rychlá jízda obcí kolem lidí
		var kmh := absf(c.speed) * 3.6
		var pos := c.global_position
		if kmh > 65.0 and _speed_cool <= 0.0 and \
				game.traffic.in_village(Vector2(pos.x, pos.z)) and _witnesses(35.0) > 0:
			_speed_cool = 45.0
			change(-3.0, "řítil se obcí %d km/h kolem lidí" % int(kmh), "rychlá jízda obcí")
	elif c == null and player.horse == null and p > 1.6 and _drunk_cool <= 0.0 and _witnesses(10.0) > 0:
		# opilý na ulici – lidi to vidí
		_drunk_cool = 90.0
		change(-1.0, "motal se opilý po vsi")
	# zapomínání: den bez přestupku → špatná pověst se pomalu lepší
	var now := game.clock.minutes
	if _last_h < 0.0:
		_last_h = now
	var dh := (now - _last_h) / 60.0
	if dh >= 1.0:
		_last_h = now
		if score < 0.0 and now - last_offense_min > FORGIVE_AFTER_H * 60.0:
			score = minf(score + FORGIVE_PER_H * dh, 0.0)


# ------------------------------------------------------------------ uložení

func to_dict() -> Dictionary:
	return {"score": score, "offenses": offenses, "good_deeds": good_deeds, "history": history,
		"last_offense_min": last_offense_min, "last_offense_text": last_offense_text,
		"respect": respect, "karma": karma, "karma_history": karma_history}


func from_dict(d: Dictionary) -> void:
	score = float(d.get("score", 0.0))
	offenses = {}
	var o: Dictionary = d.get("offenses", {})
	for k in o:
		offenses[k] = int(o[k])
	good_deeds = int(d.get("good_deeds", 0))
	history = d.get("history", [])
	last_offense_min = float(d.get("last_offense_min", -1.0e9))
	last_offense_text = String(d.get("last_offense_text", ""))
	for k in COMMUNITIES:
		respect[k] = clampf(float((d.get("respect", {}) as Dictionary).get(k, 0.0)), -100.0, 100.0)
	karma = clampf(float(d.get("karma", 0.0)), -100.0, 100.0)
	karma_history = d.get("karma_history", [])
	_last_h = game.clock.minutes
	_dui_trip = false
	_ban_trip = false
