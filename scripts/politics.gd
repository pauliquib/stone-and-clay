## Cesta na starostu (M7.1 – hlavní cíl hry): popularita, kritéria kandidatury, petice, protikandidát.
## Zjednodušená herní simulace komunálních voleb (satira) – čísla u paragrafů: viz `data/volby.json`
## (`VOLBY`, zákon č. 491/2001 Sb., ověřit aktuální znění). Jedna instance `World.politics`:
## - termín voleb (`election_jd`), protikandidát a ostatní kandidáti, 3 „přání obce“ jsou společné všem hráčům;
## - popularita, podpisy petice, skrytý klam (`deceit`) a vítězství (`mayor`) jsou per hráč.
##
## Popularita (0..100 %, `popularity`) = podíl voličů, kteří by hráče volili: váží pověst (`Reputation.score`),
## respekt komunit váhovaný počtem jejích členů (`Characters.PROFILES` → `Reputation.community_of`),
## přátelství s postavami (`Persona.friendship`) a skrytý klam. Karma popularitu neovlivňuje (jen štěstí / konec příběhu).
## Petice: `sign_petition` volá `World._apply_reply` při záměru rozhovoru „petition“ (`DialogThemes.THEMES["petition"]`).
## M7.2 (`scripts/campaign.gd`, `World.campaign`): mítinky, letáky, úplatky, pomluvy, podvody (plní `deceit`),
## volební den (`resolve_election`, voláno z `tick()`). Navazují: M7.3 (vedlejší úkoly), M7.4 (starostování).
## Ukládání: `to_dict(pid)` / `from_dict(pid, d)` – klíč `politics` v `SaveGame` (starý save bez klíče = žádná kandidatura).
class_name Politics
extends RefCounted

const PATH := "res://data/volby.json"
static var _cache := {}

## Od kolika úrovní Výřečnosti hráč vidí přesné % popularity (jinak jen slovní odhad).
const POP_SKILL_LEVEL := 5
## Váhy složek popularity (součet 1.0 bez klamu – klam je navíc, skrytý podvod).
const W_REP := 0.45
const W_RESPECT := 0.35
const W_FRIEND := 0.20
const W_DECEIT := 0.3          # háček pro M7.2 (podvod zvedne viditelnou popularitu, ne skutečnou důvěru)
## Protikandidát a náhodná procházka jeho popularity (M7.1 minimum; vazba na konkrétní události doplní M7.3).
const OPPONENT_NAME := "Starosta Novák"
const OPPONENT_POP_START := 55.0
const OPPONENT_DRIFT_DAY := 1.5     # o kolik max. za herní den (náhodná procházka)
const OPPONENT_POP_MIN := 25.0
const OPPONENT_POP_MAX := 80.0
## Smyšlená jména dalších 1–2 kandidátů (losují se podle hry, satira – žádná reálná strana).
const OTHER_CANDIDATES := ["Berta Homolová (Strana za lepší chodníky)", "Ferdinand Žbrnda (nezávislý)",
	"Miloslava Trnková (Spolek pro klidnou ves)"]

var world: World
var law: Dictionary = {}
var election_jd := -1
var term_days := 1461
var opponent_pop := OPPONENT_POP_START
var candidates: Array = []          # [{"name":, "pop":}] vylosovaní soupeři kromě hráče a protikandidáta
var wishes: Array = []              # [{"id","text"}] 3 aktuální přání obce
var signatures := {}                # pid → int (počet podpisů petice)
var signers := {}                   # pid → Array[String] (jméno postavy, aby nešlo podepsat 2×)
var deceit := {}                    # pid → float, skrytá (M7.2 háček)
var mayor := {}                      # pid → bool, vítěz posledních voleb (M7.2 `Campaign.resolve_election`, čte M7.4)
var _last_jd := -1


func setup(w: World) -> void:
	world = w
	law = _load_law()
	term_days = int(law.get("obdobi_dni", 1461))
	if election_jd < 0:
		election_jd = _first_election_jd(world.clock.jd())
	if wishes.is_empty():
		_roll_wishes()
	if candidates.is_empty():
		_roll_candidates()


static func _load_law() -> Dictionary:
	if _cache.is_empty():
		var txt := FileAccess.get_file_as_string(PATH)
		var d = JSON.parse_string(txt) if txt != "" else null
		_cache = d if d is Dictionary else {}
	return _cache


# ------------------------------------------------------------------ kalendář voleb

## Juliánské číslo první (a od pak každé 1. října) pátku v roce `year`.
static func _oct_friday(year: int) -> int:
	var first := Clock.jdn(year, 10, 1)
	return first + posmod(4 - first % 7, 7)       # 4 = pátek (0 = po … 6 = ne)


## Nejbližší reálný termín komunálních voleb v ČR od `from_jd`: první pátek října,
## jen v letech ≡ 2 (mod 4) – odpovídá historickému cyklu (2002, 2006, …, 2022, 2026…).
static func _first_election_jd(from_jd: int) -> int:
	var y := int(Clock.from_jdn(from_jd).get("year", 2026))
	while true:
		if posmod(y, 4) == 2:
			var jd := _oct_friday(y)
			if jd > from_jd:
				return jd
		y += 1
	return from_jd + 1461  # nedosažitelné, jen aby typová kontrola měla návrat


func _roll_wishes() -> void:
	var pool: Array = (law.get("prani_obce", []) as Array).duplicate()
	pool.shuffle()
	wishes = pool.slice(0, mini(3, pool.size()))


func _roll_candidates() -> void:
	var pool := OTHER_CANDIDATES.duplicate()
	pool.shuffle()
	var n := randi() % 2 + 1          # 1–2 další kandidáti, jiná hra = jiný výběr
	candidates.clear()
	for i in mini(n, pool.size()):
		candidates.append({"name": pool[i], "pop": randf_range(5.0, 20.0)})
	opponent_pop = OPPONENT_POP_START + randf_range(-10.0, 10.0)


## Nová kandidatura po prohraných volbách (M7.2 `Campaign.resolve_election`): nová přání obce a soupeři,
## petice se nepřenáší (začíná se znovu sbírat podpisy – skrytý klam `deceit` zůstává, je to vlastnost hráče).
func reroll_for_new_term() -> void:
	wishes.clear()
	candidates.clear()
	signatures.clear()
	signers.clear()
	_roll_wishes()
	_roll_candidates()


## Denní krok (volat z World._process_impl): náhodná procházka popularity protikandidáta
## a oznámení blížících se voleb. Přesná vazba na konkrétní události (skandály, opravy) je M7.3.
func tick(jd: int) -> void:
	if jd == _last_jd:
		return
	_last_jd = jd
	opponent_pop = clampf(opponent_pop + randf_range(-OPPONENT_DRIFT_DAY, OPPONENT_DRIFT_DAY), OPPONENT_POP_MIN, OPPONENT_POP_MAX)
	for c in candidates:
		c["pop"] = clampf(float(c["pop"]) + randf_range(-OPPONENT_DRIFT_DAY, OPPONENT_DRIFT_DAY), 0.0, 60.0)
	if jd > election_jd:
		if world.campaign:             # M7.2: hlasování, vyhlášení výsledku a nový termín (výhra / doplňovací volby)
			world.campaign.resolve_election()
		else:
			election_jd += term_days
		return
	var zbyva := election_jd - jd
	if zbyva in [60, 30, 14, 7, 1]:
		for id in world.players:
			world.notify(id, "popup", ["Do komunálních voleb zbývá %d dní." % zbyva, 5.0])


# ------------------------------------------------------------------ popularita

static func _community_weights() -> Dictionary:
	var counts := {}
	for k in Reputation.COMMUNITIES:
		counts[k] = 0
	var total := 0
	for i in Characters.count():
		var per := Persona.make(Characters.profile(i))
		var c := Reputation.community_of(per)
		counts[c] = int(counts.get(c, 0)) + 1
		total += 1
	return {"counts": counts, "total": maxi(total, 1)}


## Respekt komunit zprůměrovaný podle váhy (počtu členů) – blok voličů s největším počtem lidí rozhoduje nejvíc.
func weighted_respect(pid: int) -> float:
	var rep: Reputation = world.reputations.get(pid)
	if rep == null:
		return 0.0
	var w := _community_weights()
	var counts: Dictionary = w["counts"]
	var total: int = w["total"]
	var sum := 0.0
	for k in Reputation.COMMUNITIES:
		sum += rep.respect_of(k) * float(counts.get(k, 0)) / float(total)
	return sum


## Průměrné přátelství se všemi postavami, které hráč už potkal (0, když ještě nikoho nezná).
func avg_friendship(pid: int) -> float:
	var ps: Dictionary = world.personas()
	var sum := 0.0
	var n := 0
	for key in ps:
		var per: Persona = ps[key]
		if per.met.has(pid):
			sum += per.get_friendship(pid)
			n += 1
	return sum / float(n) if n > 0 else 0.0


## Popularita 0..100 %. Klam (`deceit`) ji zvedá uměle (M7.2 – podplácení, podvody), aniž by rostla skutečná důvěra.
func popularity(pid: int) -> float:
	var rep: Reputation = world.reputations.get(pid)
	var rep_score := rep.score if rep else 0.0
	var raw := W_REP * rep_score + W_RESPECT * weighted_respect(pid) + W_FRIEND * avg_friendship(pid) \
		+ W_DECEIT * float(deceit.get(pid, 0.0))
	return clampf(raw, 0.0, 100.0)


## Slovní odhad popularity (hráč bez Výřečnosti nevidí přesné %).
static func popularity_word(pop: float) -> String:
	if pop >= 60.0: return "by tě zvolila většina vesnice"
	if pop >= 40.0: return "máš slušnou podporu"
	if pop >= 20.0: return "o tobě lidé pomalu slyší"
	if pop > 0.0: return "tě skoro nikdo nezná"
	return "o tvé kandidatuře zatím neví vůbec nikdo"


## Text popularity do deníku – přesné % až od `POP_SKILL_LEVEL` Výřečnosti, jinak jen slovně.
func popularity_text(pid: int) -> String:
	var pop := popularity(pid)
	var sk: Skills = world.skills.get(pid)
	var exact := sk != null and sk.has_level("vyrecnost", POP_SKILL_LEVEL)
	if exact:
		return "%d %% – %s" % [roundi(pop), popularity_word(pop)]
	return popularity_word(pop)


# ------------------------------------------------------------------ kritéria kandidatury

## Trvalý pobyt v obci (§ 4 zákona č. 491/2001 Sb., ověřit aktuální znění) – ve hře má hráč bydlení od začátku (M1.7).
func has_residency(pid: int) -> bool:
	return world.estate == null or world.estate.home_estate(pid) >= 0


## Bez odsouzení za úmyslný trestný čin v posledních letech (zjednodušeno, viz `data/volby.json`).
func clean_record(pid: int) -> bool:
	var rec: Law.LawRecord = world.law.get(pid)
	if rec == null:
		return true
	var limit := float(law.get("bez_odsouzeni_roky", 3)) * 525600.0   # herní minuty za rok (= Law.setting "body_odpocet_rok_min")
	var now := world.clock.minutes
	for r in rec.criminal_record():
		if now - float((r as Dictionary).get("t", 0.0)) < limit:
			return false
	return true


func signatures_needed() -> int:
	return int(law.get("potreba_podpisu", 15))


func signatures_of(pid: int) -> int:
	return int(signatures.get(pid, 0))


## Shrnutí kritérií pro deník (M7.1 minimum – samu registraci kandidatury řeší M7.2).
func criteria(pid: int) -> Dictionary:
	var jd := world.clock.jd()
	return {
		"trvaly_pobyt": has_residency(pid),
		"bez_odsouzeni": clean_record(pid),
		"podpisy_mam": signatures_of(pid),
		"podpisy_treba": signatures_needed(),
		"podpisy_ok": signatures_of(pid) >= signatures_needed(),
		"election_jd": election_jd,
		"dni_do_voleb": election_jd - jd,
		"registrace_dni_pred": int(law.get("registrace_dni_pred_volbami", 66)),
		"registrace_otevrena": election_jd - jd <= int(law.get("registrace_dni_pred_volbami", 66)),
	}


# ------------------------------------------------------------------ petice (rozhovor)

## Podpis petice (téma „petition“ v rozhovoru) – `attitude` je stejná −100..100 hodnota jako v `World.dialog_context`.
## Jedna postava podepíše jen jednou. Vrací {"text": doplňující hláška ke standardní odpovědi tématu}.
func sign_petition(pid: int, per: Persona, attitude: float) -> Dictionary:
	if per == null:
		return {"text": ""}
	var key := String(per.profile.get("name", per.display_name()))
	var mine: Array = signers.get(pid, [])
	if key in mine:
		return {"text": "(Podpis už jsi od ní/něj dostal.)"}
	if attitude < 0.0:
		return {"text": "Petici nepodepisuju, mám na tebe jiný názor."}
	mine.append(key)
	signers[pid] = mine
	signatures[pid] = signatures_of(pid) + 1
	return {"text": "Jasně, kamaráde, podpis máš (%d/%d)." % [signatures_of(pid), signatures_needed()]}


## Skrytý klam (M7.2 – podvod, podplácení, nastavuje `Campaign`).
func add_deceit(pid: int, delta: float) -> void:
	deceit[pid] = clampf(float(deceit.get(pid, 0.0)) + delta, -100.0, 100.0)


## Je hráč starostou po posledních vyhodnocených volbách (M7.2 `Campaign.resolve_election`, čte M7.4)?
func is_mayor(pid: int) -> bool:
	return bool(mayor.get(pid, false))


# ------------------------------------------------------------------ deník (J → „Obec“)

func journal_bbcode(pid: int) -> String:
	var c := criteria(pid)
	var d := Clock.from_jdn(int(c["election_jd"]))
	var s := "\n\n[b]OBEC – CESTA NA STAROSTU[/b]\n"
	s += "Popularita: %s\n" % popularity_text(pid)
	var opp_stav := "[color=#f99]vede[/color]" if opponent_pop > popularity(pid) else "[color=#9f9]zaostává[/color]"
	s += "Protikandidát (%s): %s\n" % [OPPONENT_NAME, opp_stav]
	for cand in candidates:
		s += "  %s – okrajový kandidát\n" % String(cand["name"])
	s += "Volby: %s %d. %d. %d  (zbývá %d dní)\n" % [Clock.WEEKDAYS[int(c["election_jd"]) % 7], int(d["day"]),
		int(d["month"]), int(d["year"]), int(c["dni_do_voleb"])]
	s += "Registrace kandidátky: %s\n" % ("otevřená" if c["registrace_otevrena"] else \
		"otevře se %d dní před volbami" % int(c["registrace_dni_pred"]))
	s += "\n[b]Kritéria kandidatury[/b]\n"
	s += "  trvalý pobyt v obci: %s\n" % ("[color=#9f9]splněno[/color]" if c["trvaly_pobyt"] else "[color=#f99]chybí[/color]")
	s += "  bez odsouzení za úmyslný trestný čin: %s\n" % ("[color=#9f9]splněno[/color]" if c["bez_odsouzeni"] else "[color=#f99]chybí[/color]")
	s += "  podpisy petice: [color=#%s]%d / %d[/color]\n" % ["9f9" if c["podpisy_ok"] else "ff6", int(c["podpisy_mam"]), int(c["podpisy_treba"])]
	s += "\n[b]Přání obce[/b]\n"
	for w in wishes:
		s += "  • %s\n" % String(w.get("text", ""))
	if is_mayor(pid):
		s += "\n[color=#9f9][b]Jsi starostou/starostkou obce.[/b][/color]\n"
	if world.campaign:         # M7.2: mítinky, letáky, úplatky, pomluvy – „Příběh kampaně“
		s += world.campaign.journal_section(pid)
	return s


# ------------------------------------------------------------------ uložení

func to_dict(pid: int) -> Dictionary:
	return {"election_jd": election_jd, "wishes": wishes, "candidates": candidates, "opponent_pop": opponent_pop,
		"signatures": signatures_of(pid), "signers": signers.get(pid, []), "deceit": float(deceit.get(pid, 0.0)),
		"mayor": is_mayor(pid)}


func from_dict(pid: int, d: Dictionary) -> void:
	if d.is_empty():
		return
	election_jd = int(d.get("election_jd", election_jd))
	var w: Array = d.get("wishes", [])
	if not w.is_empty():
		wishes = w
	var c: Array = d.get("candidates", [])
	if not c.is_empty():
		candidates = c
	opponent_pop = float(d.get("opponent_pop", opponent_pop))
	signatures[pid] = int(d.get("signatures", 0))
	signers[pid] = d.get("signers", [])
	deceit[pid] = float(d.get("deceit", 0.0))
	mayor[pid] = bool(d.get("mayor", false))      # M7.2: starý save bez klíče = ne starosta
