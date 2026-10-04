## Osobnost a paměť jedné postavy (vesničan, obsluha, děda, štamgast, policista) vůči hráčům:
## profil (jméno, povaha, povolání – viz Characters), nálada vůči každému hráči (−1..1, urážky ji
## zhorší, slušnost zlepší, časem se vrací k 0), jestli se už znají, a strop na pověst získanou
## pouhým povídáním (aby se nedala „vyfarmit“ zdvořilostmi).
class_name Persona
extends RefCounted

const CHAT_REP_PER_DAY := 2.0     # kolik pověsti lze u jedné postavy denně získat slušným rozhovorem
const CHAT_RESPECT_PER_DAY := 2.0 # totéž pro respekt komunity (M0.6)
const FRIEND_POLITE := 2.0        # přátelství za slušný kontakt (max. 1× za herní den)
const FRIEND_INSULT := -8.0
const FRIEND_GIFT := 6.0          # základ za dárek (× hodnota předmětu, viz World.give_to_npc)
const FRIEND_HIGH := 60.0         # od této hodnoty postava zdraví přátelsky a pomůže (M2.10)

var profile := {}                 # name, trait, job, hobby, topics, age, female, role, place
var daily_routine = null          # Fáze 3: klon behavior stromu postavy (LimboAI `BehaviorTree`);
                                  # netypované – addon nemusí být nainstalovaný, plní `Villager._bt_start`
var mood := {}                    # id hráče → −1..1
var met := {}                     # id hráče → true: už se představili
var friendship := {}              # id hráče → 0..100
var _friend_day := {}             # id hráče → herní den posledního růstu z kontaktu
var _respect_given := {}          # id hráče → [herní den, získáno]
var _rep_given := {}              # id hráče → [herní den, získáno]
var _mood_t := {}                 # id hráče → herní minuty poslední změny nálady
var talk := {}                    # id hráče → krátká paměť rozhovoru (Dialog: téma, co už postava řekla, otázka zpět); neukládá se


static func make(prof: Dictionary) -> Persona:
	var p := Persona.new()
	p.profile = prof
	return p


func display_name() -> String:
	return String(profile.get("name", ""))


func first_name() -> String:
	return String(profile.get("name", "")).split(" ")[0]


func get_mood(id: int, now_min: float) -> float:
	var m: float = mood.get(id, 0.0)
	# nálada se vrací k nule zhruba o 0,1 za herní hodinu
	var t: float = _mood_t.get(id, now_min)
	var decay := (now_min - t) / 60.0 * 0.1
	if decay > 0.0:
		m = move_toward(m, 0.0, decay)
		mood[id] = m
		_mood_t[id] = now_min
	return m


func add_mood(id: int, d: float, now_min: float) -> void:
	mood[id] = clampf(get_mood(id, now_min) + d, -1.0, 1.0)
	_mood_t[id] = now_min


## Kolik z kladné změny pověsti `amount` smí rozhovor s touto postavou dnes přidat.
func allow_rep(id: int, day: int, amount: float) -> float:
	if amount <= 0.0:
		return amount
	var g: Array = _rep_given.get(id, [day, 0.0])
	if int(g[0]) != day:
		g = [day, 0.0]
	var ok := minf(amount, CHAT_REP_PER_DAY - float(g[1]))
	g[1] = float(g[1]) + maxf(ok, 0.0)
	_rep_given[id] = g
	return maxf(ok, 0.0)


## Kolik z kladné změny respektu `amount` smí rozhovor s touto postavou dnes přidat (max. CHAT_RESPECT_PER_DAY).
func allow_respect(id: int, day: int, amount: float) -> float:
	if amount <= 0.0:
		return amount
	var g: Array = _respect_given.get(id, [day, 0.0])
	if int(g[0]) != day:
		g = [day, 0.0]
	var ok := minf(amount, CHAT_RESPECT_PER_DAY - float(g[1]))
	g[1] = float(g[1]) + maxf(ok, 0.0)
	_respect_given[id] = g
	return maxf(ok, 0.0)


func get_friendship(id: int) -> float:
	return float(friendship.get(id, 0.0))


## Přátelství: kladné změny z kontaktu nejvýš 1× za herní den, dárek a urážka (záporné) vždy.
## `gift` = dárek (obejde denní limit).
func add_friendship(id: int, d: float, _now_min: float, day: int, gift := false) -> void:
	if d > 0.0 and not gift:
		if int(_friend_day.get(id, -1)) == day:
			return
		_friend_day[id] = day
	friendship[id] = clampf(get_friendship(id) + d, 0.0, 100.0)


func to_dict() -> Dictionary:
	var md := {}
	for k in mood:
		md[str(k)] = mood[k]
	var mt := []
	for k in met:
		mt.append(k)
	var fr := {}
	for k in friendship:
		fr[str(k)] = friendship[k]
	return {"mood": md, "met": mt, "friendship": fr}


func from_dict(d: Dictionary, now_min: float) -> void:
	mood = {}
	_mood_t = {}
	for k in d.get("mood", {}):
		mood[int(k)] = float(d["mood"][k])
		_mood_t[int(k)] = now_min
	met = {}
	for k in d.get("met", []):
		met[int(k)] = true
	friendship = {}
	for k in d.get("friendship", {}):
		friendship[int(k)] = clampf(float(d["friendship"][k]), 0.0, 100.0)
