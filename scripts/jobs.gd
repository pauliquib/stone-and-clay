## Zaměstnání jednoho hráče (M3.1) – per hráč `World.jobs[id]`, stejně jako úkoly a pověst.
##
## Katalog prací a pracovních úkolů je v `data/prace.json` (upravuje člověk; podniky jsou smyšlené):
##   prace.<id>: nazev, zamestnavatel, vedouci, misto (klíč Place), pozadavky {dovednosti, ridicak, obleceni_tag,
##               rejstrik_cisty, povest_min, respekt}, smeny [{dny 1–7, od, do}], mzda_hod (hrubá), vyplata "tyden" / "den",
##               sance_pohovoru, ukoly [id úkolů po sobě dokola], ukolu_za_hodinu, dovednosti_xp {dovednost: násobek}, respekt (komunita)
##   ukoly.<id>:  nazev, popis, typ "akce" (N× kontextová akce M0.4 `akce` na cílech `cile`) / "dojdi" (dojít k bodu `cile`, `r`)
## Cíle úkolů dodávají „poskytovatelé“ (`Jobs.set_provider(jméno, Callable(world, pid, job) -> Array[Vector3])`);
## vestavěné: "misto" (dveře pracoviště), "hospoda_stoly" (stoly v interiéru hospody, venku zahrádka), "popelnice_u_mista".
## Úkol typu „akce“ bez `cile` počítá každou akci `akce` v areálu pracoviště (pro M3.2: krmení, dojení, rytí…).
## M3.2 – rozšíření katalogu (vše volitelné):
##   prace.<id>: areal_r (m, areál místo `AREA_R` – obecní údržba chodí po celé vsi), povest_tyden (pověst za týden bez
##               napomenutí, vyplatí se při výplatě), pozadavky.obleceni_slot (tag musí být na tomhle slotu – „pracovní boty“),
##               pozadavky.strizlivost (na pohovor jen střízlivý).
##   ukoly.<id>: mesice [1–12] a snih_min / snih_max (`Weather.snow_cover`) – úkol se zadá jen v sezóně / za počasí;
##               zapujcit [id] nebo {id: počet} – nářadí / materiál zapůjčený na směnu (po směně se vrátí, `lend` / `unlend`);
##               r_cile (dosah cíle v m, výchozí `TABLE_R`); dovednosti_xp (přebije XP práce za hotový úkol); kompas (jméno
##               poskytovatele bodu pro kompas u úkolu bez `cile`, např. výčep). Úkol bez cílů (vše posekané, odklizené…) se
##               přeskočí; když není co dělat, vedoucí čeká (`RETRY_MIN`) a hodiny se počítají (neplatí `IDLE_MIN`).
##   Akce s klíčem `job: true` v `Actions.DEFS` mají kontrolu „cíl s `data.pid` patří jen tomu hráči“ (`own_target`).
## M3.3 – další práce (vše volitelné):
##   ukoly.<id>.typ "modul": pokrok hlásí modul práce přes `progress(task, n)` (vyznačené stromy, pokladna, pálenice…);
##               `cile` (poskytovatel) jen určí, jestli je co dělat, a bod pro kompas; bez `cile` kompas z `kompas`.
##   ukoly.<id>.hodiny [od, do]: úkol jen v tu denní dobu (převzetí pečiva ráno).
##   prace.<id>.smeny[].nazev + smeny_volba: true – hráč si při přijetí vybere variantu („ranní“ / „odpolední“, `shift_pick`),
##               platí jen směny s tím názvem (a směny bez názvu); změnit jde u zaměstnavatele mimo směnu.
##   prace.<id>.druh "zakazka" (brigáda na zavolání – zahradník, opravář): bez `smeny`; u zaměstnavatele „Vzít zakázku“ →
##               tvůrce zakázky (`set_contract_maker`, jméno v `zakazka.tvurce`) vrátí {pos, label, customer, ukoly, odmena,
##               seed?, zadani?};
##               úkoly zakázky jdou jednou po sobě, areál = místo zakázky (`zakazka.areal_r`), lhůta `zakazka.lhuta_h`;
##               hotovo = odměna na ruku + respekt `respekt` (`zakazka.respekt`), nestihl = hodnocení a napomenutí.
##   `set_event_hook(job_id, Callable(jobs, kind, data))` – modul práce dostává herní události hráče, který tu práci dělá.
##
## Směna: do 15 min od začátku (`LATE_MIN`) musí být hráč do `ARRIVE_R` m od místa práce → „Začal jsi směnu“; později = pozdní
## příchod (napomenutí), po 60 min (`ABSENT_MIN`) absence. S promile > `DRUNK_PROMILE` ho vedoucí pošle domů (napomenutí).
## Během směny: přítomnost v areálu (`AREA_R`) + plnění úkolů → výdělek; kdo se `IDLE_MIN` herních minut neposune v úkolu,
## tomu se hodiny nepočítají; odchod z areálu na déle než `LEAVE_MIN` = odchod ze směny (absence). Pití alkoholu v práci =
## napomenutí. `napomenuti_do_vypovedi` (3) napomenutí → výpověď; zadržení policií (událost `busted`) nebo vězení (`jailed`,
## M4.3) → výpověď. Zmeškané směny během přeskočeného času (spánek, záchytka) se započtou jako absence.
## Výplata: týdně v pátek po směně (nebo denně) hotově u zaměstnavatele (E u místa → „Vyzvednout výplatu“), čistá mzda
## (zjednodušeně × `cista_mzda_k`) + prémie 0–20 % podle hodnocení; při dluhu na nájmu nabídne zaplacení (`Estate.pay_rent_debt`).
## Volno: státní svátky (`Clock.holiday_on`), dny mimo `smeny`.
## M3.4 – počítač: `pay_bank` (výplata na účet – přepínač u zaměstnavatele / v bance; v den výplaty přijde sama),
##   `invite(job)` (odpověď na inzerát v „Práce v kraji“ → pozvánka na pohovor na `INVITE_DAYS` dní, šance + `INVITE_BONUS`).
## Události (`World.emit_game_event`): job_hired, job_quit, job_fired, job_warning, shift_started, shift_done, job_task_done, job_paid.
## Zprávy jen přes `World.notify`. Ukládání `to_dict` / `from_dict` (klíč `jobs` v `SaveGame`; starý save = bez práce).
class_name Jobs
extends Node

const PATH := "res://data/prace.json"
const ARRIVE_R := 30.0          # m od dveří pracoviště – příchod na směnu
const AREA_R := 45.0            # m – „v areálu“ během směny (zahrádka, popelnice u silnice)
const EARLY_MIN := 45.0         # herních minut před začátkem se směna ukáže v HUD („přijď do…“)
const LATE_MIN := 15.0          # pozdní příchod po tolika herních minutách
const ABSENT_MIN := 60.0        # nepřišel do tolika minut = absence
const LEAVE_MIN := 20.0         # herních minut mimo areál během směny = odchod ze směny
const IDLE_MIN := 60.0          # herních minut bez pokroku v úkolu → hodiny se přestanou počítat
const DRUNK_PROMILE := 0.2      # ‰ při příchodu → poslán domů
const APPLY_PROMILE := 0.5      # ‰ na pohovoru → skoro jistě neuspěje
const ATTENDANCE_MAX := 20      # kolik posledních směn si docházka pamatuje
const RESOLVED_MAX := 40
const MISSED_MAX := 5           # nejvýš tolik zmeškaných směn naráz (dlouhý skok času)
const TASK_XP := 6.0            # XP za hotový úkol × násobek z `dovednosti_xp`
const HOUR_XP := 8.0            # XP za odpracovanou hodinu × násobek
const PAY_DEFAULT_H := 14.0     # hodina výplaty v pátek, když ten den není směna
const FRIDAY := 4               # Clock.weekday(): 0 = pondělí
const TICK_S := 0.5
const TABLE_R := 1.3            # dosah cíle „stůl“ (m)
## Změny hodnocení 0–100 (prémie a doporučení).
const RATING := {"vcas": 3.0, "pozde": -6.0, "absence": -15.0, "opily": -15.0, "odesel": -12.0, "pil": -10.0,
	"ukol": 1.0, "malo_ukolu": -4.0, "bez_obleceni": -3.0}
const STATUS_TEXT := {"vcas": "včas", "pozde": "pozdě", "absence": "absence", "opily": "opilý – poslán domů",
	"odesel": "odešel ze směny", "zakazka": "zakázka hotová", "nesplneno": "zakázka nesplněna", "zrusena": "zakázka zrušena"}
const STATUS_COLOR := {"vcas": "8f8", "pozde": "fd6", "absence": "f88", "opily": "f88", "odesel": "f88", "zakazka": "8f8",
	"nesplneno": "f88", "zrusena": "ccc"}
## Odpovědi na pohovoru: [text, úprava šance].
const INTERVIEW := [
	["„Potřebuju vydělat na nájem a práce se nebojím.“", 0.12],
	["„Jsem spolehlivý, chodím včas a umím vzít za práci.“", 0.08],
	["„Nic lepšího tady stejně není, tak proč ne.“", -0.3],
]
const TAG_NAMES := {"pracovni": "pracovní oblečení", "reflexni": "reflexní vesta", "ochrana_pila": "ochranné oblečení k pile",
	"slavnostni": "slavnostní oblečení"}
const DAY_NAMES := ["Po", "Út", "St", "Čt", "Pá", "So", "Ne"]
const ROMAN := ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII"]
const ERRAND_R := 200.0         # m od pracoviště – během úkolu „dojdi“ (pochůzka) se to počítá jako přítomnost
const MISSED_SPAN_MAX := 2880.0 # herních minut: delší skok (F2 → Datum) se jako zmeškané směny nepočítá
const RETRY_MIN := 30.0         # M3.2: bez úkolu (vše hotovo / mimo sezónu) se nový úkol zkusí zadat po tolika herních minutách
const CONTRACT_R := 30.0        # M3.3: areál zakázky (m od místa zakázky), když katalog neřekne `zakazka.areal_r`
const CONTRACT_H := 8.0         # M3.3: lhůta zakázky v herních hodinách (`zakazka.lhuta_h`)
const CONTRACT_PAUSE_H := 2.0   # M3.3: další zakázka nejdřív po tolika herních hodinách (`zakazka.pauza_h`)
const CONTRACT_RATING := {"hotovo": 4.0, "nesplneno": -10.0}
const INVITE_DAYS := 7           # M3.4: pozvánka na pohovor z inzerátu platí tolik herních dní
const INVITE_BONUS := 0.15       # M3.4: šance na pohovoru navíc, když přijde na pozvání

static var _cache := {}
static var _providers := {}      # jméno → Callable(world: World, pid: int, job: Dictionary) -> Array (Vector3)
static var _hooks := {}          # M3.3: id práce → Callable(jobs: Jobs, kind: String, data: Dictionary) – události pro modul práce
static var _makers := {}         # M3.3: jméno → Callable(world: World, pid: int, job: Dictionary) -> Dictionary (zakázka)
static var _checks_done := false

var game: World
var player: Player
var pid := 0
var current := ""                # id práce, "" = bez zaměstnání
var hired_jd := -1
var hired_min := 0.0             # herní minuty přijetí (směny před tím se nepočítají)
var warnings := 0
var attendance: Array = []       # posledních ATTENDANCE_MAX směn: {jd, od, do, stav, h, ukoly, kc}
var earned_unpaid := 0.0         # hrubá mzda k výplatě (Kč)
var pay_from_min := -1.0         # od kdy je výplata k vyzvednutí (herní minuty), −1 = nic
var rating := 50.0               # hodnocení 0–100
var total_net := 0               # čistého vyděláno celkem (Kč)
var history: Array = []          # dřívější zaměstnání: {job, from_jd, to_jd, why}
var retry := {}                  # id práce → juliánský den, od kdy se smí znovu ucházet
var shift := {}                  # probíhající / blížící se směna (viz `_make_shift`), {} = žádná
var resolved: Array = []         # klíče vyřízených směn "jd:od"
var warned_since_pay := false    # M3.2: napomenutí od poslední výplaty (pověst za poctivý týden – `povest_tyden`)
var shift_pick := ""             # M3.3: zvolená varianta směn („ranní“ / „odpolední“), "" = všechny směny práce
var contract_next := -1.0        # M3.3: od kdy (herní minuty) jde vzít další zakázku
var pay_bank := false            # M3.4: výplata na účet (Computer.deposit) místo hotově u zaměstnavatele
var invited := {}                # M3.4: id práce → juliánský den, do kdy platí pozvánka na pohovor (inzerát z PC)
var _t := 0.0
var _last_min := -1.0
var _targets: Array = []         # cíle aktuálního úkolu registrované v ActionRunner


func setup(g: World, p: Player) -> void:
	game = g
	player = p
	pid = p.id
	if not _checks_done:
		_checks_done = true
		_register_builtin()


## Vestavění poskytovatelé cílů a kontrola cíle akce (statická funkce – lambdy nejsou vázané na instanci hráče).
static func _register_builtin() -> void:
	set_provider("misto", func(w: World, _id: int, j: Dictionary) -> Array:
		var pl: Place = w.places.get(String(j.get("misto", "")))
		return [pl.door] if pl else [])
	set_provider("hospoda_stoly", func(w: World, id: int, j: Dictionary) -> Array: return Jobs._tables_provider(w, id, j))
	set_provider("popelnice_u_mista", func(w: World, id: int, j: Dictionary) -> Array: return Jobs._bin_provider(w, id, j))
	# cíle pracovních úkolů patří jen hráči, který úkol plní (v MP je vidí i ostatní); M3.2: všechny akce s `job: true`
	# (akce s vlastní kontrolou – krmení, posyp… – si ji přidají samy přes `Jobs.own_target`)
	for aid in Actions.DEFS:
		if bool((Actions.DEFS[aid] as Dictionary).get("job", false)):
			Actions.set_target_check(String(aid), func(aim: Dictionary, player_id: int) -> String:
				return Jobs.own_target(aim, player_id))


## Cíl pracovního úkolu registrovaný pro jiného hráče (`data.pid`) → důvod; cíl bez `pid` (hromada sena, sníh) jde komukoli.
static func own_target(aim: Dictionary, player_id: int) -> String:
	var t: Dictionary = aim.get("target", {})
	var d: Dictionary = t.get("data", {})
	if d.has("pid") and int(d["pid"]) != player_id:
		return "Tohle není tvoje práce."
	return ""


# ------------------------------------------------------------------ katalog

## Celý katalog `data/prace.json` (cache); chybí-li soubor, prázdné `prace` a `ukoly`.
static func catalog() -> Dictionary:
	if _cache.is_empty():
		var txt := FileAccess.get_file_as_string(PATH)
		var d = JSON.parse_string(txt) if txt != "" else null
		_cache = d if d is Dictionary else {}
		if not (_cache.get("prace") is Dictionary):
			_cache["prace"] = {}
		if not (_cache.get("ukoly") is Dictionary):
			_cache["ukoly"] = {}
	return _cache


static func all_jobs() -> Dictionary:
	return catalog()["prace"]


static func job(id: String) -> Dictionary:
	return (all_jobs().get(id, {}) as Dictionary)


static func task_def(id: String) -> Dictionary:
	return ((catalog()["ukoly"] as Dictionary).get(id, {}) as Dictionary)


static func setting(key: String, def: float) -> float:
	return float(catalog().get(key, def))


## Id prací, které nabízí místo `place`.
static func jobs_at(place: String) -> Array:
	var out := []
	for id in all_jobs():
		if String((all_jobs()[id] as Dictionary).get("misto", "")) == place:
			out.append(String(id))
	return out


## Zaregistruje poskytovatele cílů úkolů (M3.2+: statek, obec…): Callable(world, pid, job) -> Array bodů (Vector3).
static func set_provider(name_: String, f: Callable) -> void:
	_providers[name_] = f


## M3.3: modul práce `job_id` dostane herní události hráče, který ji právě dělá: Callable(jobs: Jobs, kind, data).
static func set_event_hook(job_id: String, f: Callable) -> void:
	_hooks[job_id] = f


## M3.3: tvůrce zakázky (práce `druh: "zakazka"`, jméno v `zakazka.tvurce`): Callable(world, pid, job) -> Dictionary
## {pos: Vector3, label: String, customer: String, ukoly: [id úkolů], odmena: int, seed?: int, zadani?: String}; {} = teď nic.
static func set_contract_maker(name_: String, f: Callable) -> void:
	_makers[name_] = f


## Práce na zavolání (zakázky místo směn) – M3.3.
static func is_contract(j: Dictionary) -> bool:
	return String(j.get("druh", "")) == "zakazka"


## Varianty směn (`smeny[].nazev`) u práce se `smeny_volba` – ["ranní", "odpolední"]; jinak [].
static func shift_variants(j: Dictionary) -> Array:
	var out := []
	if not bool(j.get("smeny_volba", false)):
		return out
	for s in j.get("smeny", []):
		var n := String((s as Dictionary).get("nazev", ""))
		if n != "" and not out.has(n):
			out.append(n)
	return out


## Směny práce `j` v den `jd`: [[od, do], …]; o státních svátcích volno. `pick` = varianta směn (M3.3), "" = všechny.
static func shifts_on(j: Dictionary, jd: int, pick := "") -> Array:
	var out := []
	if Clock.holiday_on(jd) != "":
		return out
	var ms: Array = j.get("mesice", [])  # M3.3: sezónní práce (pálenice IX–XII) – mimo sezónu bez směn
	if not ms.is_empty():
		var m := int(Clock.from_jdn(jd)["month"])
		if not (m in ms) and not (float(m) in ms):
			return out
	var dow := jd % 7 + 1                 # 1 = pondělí … 7 = neděle
	for s in j.get("smeny", []):
		var n := String((s as Dictionary).get("nazev", ""))
		if pick != "" and n != "" and n != pick:
			continue
		for d in (s as Dictionary).get("dny", []):
			if int(d) == dow:
				out.append([float(s.get("od", 0.0)), float(s.get("do", 0.0))])
				break
	return out


## Směny hráče (se zvolenou variantou).
func _my_shifts(j: Dictionary, jd: int) -> Array:
	return shifts_on(j, jd, shift_pick)


## „Po–Pá 16:00–20:00“ (M3.3: u variant „Po–Pá 6:00–12:00 (ranní)“, u zakázek „na zavolání“).
static func shifts_text(j: Dictionary, pick := "") -> String:
	if is_contract(j) and (j.get("smeny", []) as Array).is_empty():
		return "na zavolání (zakázky)"
	var parts := []
	for s in j.get("smeny", []):
		var sn := String((s as Dictionary).get("nazev", ""))
		if pick != "" and sn != "" and sn != pick:
			continue
		var dny: Array = []
		for d in (s as Dictionary).get("dny", []):
			dny.append(int(d))
		dny.sort()
		var dt := ""
		if dny.size() >= 3 and int(dny[-1]) - int(dny[0]) == dny.size() - 1:
			dt = "%s–%s" % [DAY_NAMES[int(dny[0]) - 1], DAY_NAMES[int(dny[-1]) - 1]]
		else:
			var names := []
			for d in dny:
				names.append(DAY_NAMES[clampi(int(d) - 1, 0, 6)])
			dt = ", ".join(names)
		parts.append("%s %s–%s%s" % [dt, _hm(float(s.get("od", 0.0))), _hm(float(s.get("do", 0.0))),
			" (%s)" % sn if sn != "" else ""])
	var txt := "; ".join(parts) if not parts.is_empty() else "bez směn"
	var ms: Array = j.get("mesice", [])
	if not ms.is_empty():
		txt += " – sezóna %s–%s" % [ROMAN[clampi(int(ms[0]), 1, 12) - 1], ROMAN[clampi(int(ms[-1]), 1, 12) - 1]]
	return txt


static func _hm(h: float) -> String:
	var m := roundi(h * 60.0)
	return "%d:%02d" % [(m / 60) % 24, m % 60]


static func _kc(v: float) -> String:
	var s := str(roundi(v))
	return (s.substr(0, s.length() - 3) + " " + s.substr(s.length() - 3) if s.length() > 3 else s) + " Kč"


func _abs_min(jd: int, h: float) -> float:
	return float(jd - game.clock.start_jd) * 1440.0 + h * 60.0


func _jd_of(minutes: float) -> int:
	return game.clock.start_jd + int(floorf(minutes / 1440.0))


func _day_text(jd: int) -> String:
	var d := Clock.from_jdn(jd)
	return "%s %d. %d." % [DAY_NAMES[jd % 7], int(d["day"]), int(d["month"])]


func title() -> String:
	return String(job(current).get("nazev", current)) if current != "" else ""


# ------------------------------------------------------------------ požadavky a pohovor

## Splňuje hráč požadavky práce? {ok, reasons: [text], checks: [[text, splněno]]}.
func can_apply(job_id: String) -> Dictionary:
	var j := job(job_id)
	var checks := []
	var reasons := []
	if j.is_empty():
		return {"ok": false, "reasons": ["Taková práce není."], "checks": []}
	var req: Dictionary = j.get("pozadavky", {})
	var sk: Skills = game.skills.get(pid)
	var dv: Dictionary = req.get("dovednosti", {})
	for s in dv:
		var need := int(dv[s])
		var have := sk.level(String(s)) if sk else 1
		checks.append(["%s aspoň %d (máš %d)" % [Skills.skill_name(String(s)), need, have], have >= need])
	var rid := String(req.get("ridicak", ""))
	if rid != "":
		# zjednodušeně do M4.1: platný řidičák = není zákaz řízení (skupiny oprávnění doplní autoškola)
		var ok_r := game.police == null or game.police.license_ok(player)
		checks.append(["Řidičské oprávnění sk. %s bez zákazu řízení" % rid, ok_r])
	var tag := String(req.get("obleceni_tag", ""))
	if tag != "":
		checks.append(["Na sobě: %s" % _outfit_name(req), _outfit_ok(req)])
	if bool(req.get("strizlivost", false)):
		checks.append(["Střízlivý (%s ‰)" % ("%.2f" % player.body.promile()).replace(".", ","), player.body.promile() <= DRUNK_PROMILE])
	if bool(req.get("rejstrik_cisty", false)):
		checks.append(["Čistý rejstřík (bez trestného činu)", _record_clean()])
	var rep: Reputation = game.reputations.get(pid)
	if req.has("povest_min") and rep:
		var pm := float(req["povest_min"])
		checks.append(["Pověst v obci aspoň %+d (máš %+d)" % [roundi(pm), roundi(rep.score)], rep.score >= pm])
	var rs: Dictionary = req.get("respekt", {})
	for c in rs:
		if rep:
			var v := rep.respect_of(String(c))
			checks.append(["Respekt – %s: aspoň „%s“ (teď „%s“)" % [Reputation.community_name(String(c)),
				Reputation.respect_word(float(rs[c])), Reputation.respect_word(v)], v >= float(rs[c])])
	for c in checks:
		if not c[1]:
			reasons.append(c[0])
	if current == job_id:
		reasons.append("Tady už pracuješ.")
	elif current != "":
		reasons.append("Už pracuješ jako %s – nejdřív dej výpověď." % title().to_lower())
	var jd := game.clock.jd()
	if int(retry.get(job_id, -1)) > jd:
		reasons.append("Na pohovoru jsi tu byl – zkus to zase zítra.")
	return {"ok": reasons.is_empty(), "reasons": reasons, "checks": checks}


func _record_clean() -> bool:
	var lr: Law.LawRecord = game.law.get(pid)
	if lr == null:
		return true
	for r in lr.records:
		if bool((r as Dictionary).get("trestny_cin", false)):
			return false
	return true


## Oblečení z požadavků: tag (`obleceni_tag`), volitelně na konkrétním slotu (`obleceni_slot`, M3.2 – „pracovní boty“).
func _outfit_ok(req: Dictionary) -> bool:
	var tag := String(req.get("obleceni_tag", ""))
	if tag == "":
		return true
	var slot := String(req.get("obleceni_slot", ""))
	if slot != "":
		return Wardrobe.slot_has_tag(player.outfit, slot, tag)
	return Wardrobe.has_tag(player.outfit, tag)


static func _outfit_name(req: Dictionary) -> String:
	var tag := String(req.get("obleceni_tag", ""))
	var slot := String(req.get("obleceni_slot", ""))
	if tag == "pracovni" and slot == "boty":
		return "pracovní boty"
	return String(TAG_NAMES.get(tag, tag)) + (" (%s)" % slot if slot != "" else "")


## Nabídka zaměstnavatele „Hledáte pracovníky?“: práce místa s požadavky (splněné zeleně, nesplněné šedě) a „Ucházet se“.
func open_offers(place: String) -> void:
	var ids := jobs_at(place)
	var boss := _boss_name(place)
	if ids.is_empty():
		game.notify(pid, "show_message", ["„Teď nikoho nehledáme.“", 3.0])
		return
	var text := "%s: „Hledáme, hledáme. Co bys chtěl dělat?“" % boss
	var opts := []
	for id in ids:
		var j := job(id)
		var chk := can_apply(id)
		var pay := "%d Kč/h hrubého" % int(j.get("mzda_hod", 0))
		if is_contract(j):                 # M3.3: úkolová odměna za zakázku
			var od: Array = (j.get("zakazka", {}) as Dictionary).get("odmena", [0, 0])
			pay = "%d–%d Kč za zakázku" % [int(od[0]) if not od.is_empty() else 0, int(od[-1]) if not od.is_empty() else 0]
		opts.append(["── %s · %s · %s ──" % [j.get("nazev", id), pay, shifts_text(j)], func(): pass, false])
		if String(j.get("popis", "")) != "":
			opts.append(["   %s" % j["popis"], func(): pass, false])
		for c in chk["checks"]:
			opts.append(["   %s %s" % ["✔" if c[1] else "✘", c[0]], func(): pass, false,
				Color(0.5, 0.95, 0.5) if c[1] else Color(0.6, 0.6, 0.6)])
		if (chk["checks"] as Array).is_empty():
			opts.append(["   ✔ bez zvláštních požadavků", func(): pass, false, Color(0.5, 0.95, 0.5)])
		for r in chk["reasons"]:
			if not (r in _check_texts(chk)):
				opts.append(["   ✘ %s" % r, func(): pass, false, Color(0.6, 0.6, 0.6)])
		opts.append(["Ucházet se: %s" % j.get("nazev", id), apply.bind(id), chk["ok"]])
	game.notify(pid, "open_menu", [String(job(ids[0]).get("zamestnavatel", "Zaměstnavatel")), text, opts])


static func _check_texts(chk: Dictionary) -> Array:
	var out := []
	for c in chk["checks"]:
		out.append(c[0])
	return out


## Pohovor: krátký rozhovor v nabídce místa; šance podle výřečnosti, pověsti a respektu komunity.
func apply(job_id: String) -> void:
	var chk := can_apply(job_id)
	if not chk["ok"]:
		game.notify(pid, "show_message", [String((chk["reasons"] as Array)[0]), 3.5])
		return
	var j := job(job_id)
	var opts := []
	for i in INTERVIEW.size():
		opts.append([INTERVIEW[i][0], _interview.bind(job_id, i)])
	game.notify(pid, "open_menu", ["Pohovor – %s" % j.get("nazev", job_id),
		"%s si tě změří pohledem: „Tak proč bys chtěl dělat zrovna u nás?“" % _boss_name(String(j.get("misto", ""))), opts])


func _interview(job_id: String, answer: int) -> void:
	var j := job(job_id)
	var sk: Skills = game.skills.get(pid)
	var rep: Reputation = game.reputations.get(pid)
	var chance := float(j.get("sance_pohovoru", 0.5))
	chance += 0.35 * (sk.bonus("vyrecnost") if sk else 0.0)
	chance += float(INTERVIEW[clampi(answer, 0, INTERVIEW.size() - 1)][1])
	if rep:
		chance += rep.score / 250.0
		var comm := String(j.get("respekt", ""))
		if comm != "":
			chance += rep.respect_of(comm) / 400.0
	if int(invited.get(job_id, -1)) >= game.clock.jd():
		chance += INVITE_BONUS             # M3.4: přišel na pozvání z inzerátu
	invited.erase(job_id)
	var drunk := player.body.promile() > APPLY_PROMILE
	if drunk:
		chance -= 0.6
	chance = clampf(chance, 0.05, 0.95)
	game.give_xp(pid, "vyrecnost", 5.0, "pohovor")
	var misto := String(j.get("misto", ""))
	if randf() < chance:
		_hire(job_id)
		return
	retry[job_id] = game.clock.jd() + 1
	_boss_say(misto, "Z tebe je cítit chlast. Takhle ne – přijď střízlivý." if drunk
		else "Promiň, teď to nevidím. Zkus to jindy.")
	game.emit_game_event(pid, "job_rejected", {"job": job_id})


func _hire(job_id: String) -> void:
	var j := job(job_id)
	current = job_id
	hired_jd = game.clock.jd()
	hired_min = game.clock.minutes
	warnings = 0
	attendance = []
	rating = 50.0
	shift = {}
	resolved = []
	contract_next = -1.0
	var vars := shift_variants(j)
	shift_pick = String(vars[0]) if not vars.is_empty() else ""
	_clear_targets()
	if is_contract(j):
		_boss_say(String(j.get("misto", "")), "Dobře, dám o tobě vědět sousedům. Kdykoli se zastav pro zakázku.")
		var zc: Dictionary = j.get("zakazka", {})
		game.notify(pid, "popup", ["PŘIJAT: %s\n%s · %s\nÚkolová odměna %d–%d Kč za zakázku (na ruku, hned po práci).\nZakázku vezmeš u: %s. Deník J → Práce." % [
			j.get("nazev", job_id), j.get("zamestnavatel", ""), shifts_text(j), int((zc.get("odmena", [0, 0]) as Array)[0]),
			int((zc.get("odmena", [0, 0]) as Array)[-1]), _boss_name(String(j.get("misto", "")))], 8.0])
	else:
		_boss_say(String(j.get("misto", "")), "Tak jo, beru tě. Ať chodíš včas a střízlivý!")
		game.notify(pid, "popup", ["PŘIJAT: %s\n%s · směny %s\nMzda %d Kč/h hrubého, výplata %s u zaměstnavatele.\nDeník J → Práce." % [
			j.get("nazev", job_id), j.get("zamestnavatel", ""), shifts_text(j, shift_pick), int(j.get("mzda_hod", 0)),
			"v pátek po směně" if String(j.get("vyplata", "tyden")) == "tyden" else "po každé směně"], 8.0])
	game.play_sfx(pid, "success")
	game.emit_game_event(pid, "job_hired", {"job": job_id})
	if vars.size() > 1:
		_pick_menu()


## M3.3: výběr varianty směn (ranní / odpolední) – po přijetí a u zaměstnavatele mimo směnu.
func _pick_menu() -> void:
	var j := job(current)
	var opts := []
	for v in shift_variants(j):
		opts.append(["%s%s: %s" % ["▶ " if String(v) == shift_pick else "", String(v).capitalize(), shifts_text(j, String(v))],
			_set_pick.bind(String(v))])
	game.notify(pid, "open_menu", ["Směny – %s" % title(), "Kterou směnu chceš dělat?", opts])


func _set_pick(v: String) -> void:
	if not shift.is_empty():
		game.notify(pid, "show_message", ["Během směny se to měnit nedá.", 2.5])
		return
	shift_pick = v
	game.notify(pid, "show_message", ["Směny: %s." % shifts_text(job(current), v), 3.5])


## Dobrovolná výpověď (E u zaměstnavatele). Nevyplacená mzda se doplatí hned.
func quit() -> void:
	if current == "":
		return
	var misto := String(job(current).get("misto", ""))
	_boss_say(misto, "Škoda. Kdybys chtěl, víš, kde mě najdeš.")
	_leave("výpověď na vlastní žádost", "job_quit", 0.0)


## Výpověď od zaměstnavatele (3 napomenutí, zadržení policií, vězení M4.3). Respekt komunity klesne.
func fire(reason: String) -> void:
	if current == "":
		return
	game.notify(pid, "police_banner", ["VÝPOVĚĎ z práce (%s): %s" % [title(), reason], 6.0])
	_leave(reason, "job_fired", -5.0)


func _leave(why: String, event: String, respect_delta: float) -> void:
	var j := job(current)
	var id := current
	if not shift.is_empty() and String(shift.get("state", "")) == "prace":
		_add_earnings(float(shift.get("paid_min", 0.0)) / 60.0 * float(j.get("mzda_hod", 0)), j)
	_return_lent()
	shift = {}
	_clear_targets()
	if earned_unpaid > 0.0:
		_pay_out("Doplatek mzdy při odchodu")
	history.append({"job": id, "from_jd": hired_jd, "to_jd": game.clock.jd(), "why": why})
	if history.size() > 10:
		history = history.slice(history.size() - 10)
	var rep: Reputation = game.reputations.get(pid)
	var comm := String(j.get("respekt", ""))
	if rep and comm != "" and respect_delta != 0.0:
		rep.change_respect(comm, respect_delta, "výpověď z práce")
	current = ""
	warnings = 0
	game.emit_game_event(pid, event, {"job": id, "reason": why})


# ------------------------------------------------------------------ nabídka u místa

## Položky do nabídky místa (volá `Quests.place_options`): práce, výplata, výpověď. Formát jako `Hud.open_menu`.
func place_options(place: String) -> Array:
	var out := []
	var here := current != "" and String(job(current).get("misto", "")) == place
	if here:
		var j := job(current)
		if can_collect():
			out.append(["Vyzvednout výplatu (%s čistého)" % _kc(_net_of(earned_unpaid)), collect_pay])
		elif earned_unpaid > 0.0:
			out.append(["Výplata až v %s (zatím %s hrubého)" % [_payday_text(), _kc(earned_unpaid)], func(): pass, false])
		if is_contract(j):
			out.append_array(_contract_options(j))
		elif not shift.is_empty() and String(shift.get("state", "")) == "prace":
			var td := task_def(String(shift.get("task", "")))
			out.append(["Směna: %s" % _task_line(td), func(): game.notify(pid, "popup", [String(td.get("popis", "")), 5.0])])
		elif shift.is_empty() and shift_variants(j).size() > 1:
			out.append(["Změnit směnu (teď: %s)" % shift_pick, _pick_menu])
		if not is_contract(j):
			out.append(["Výplata: %s – přepnout na %s" % ["na účet" if pay_bank else "hotově", "hotovost" if pay_bank else "účet"],
				set_pay_bank.bind(not pay_bank)])
		out.append(["Dát výpověď (%s)" % j.get("nazev", current), _confirm_quit])
	for id in jobs_at(place):             # M3.4: pozvánka na pohovor z inzerátu (počítač → Práce v kraji)
		if int(invited.get(id, -1)) >= game.clock.jd() and current != id:
			out.append(["Jdu na pohovor (inzerát): %s" % job(id).get("nazev", id), apply.bind(id)])
	var offers := jobs_at(place)
	if not offers.is_empty() and not (here and offers.size() == 1):
		out.append(["Hledáte pracovníky?", open_offers.bind(place)])
	return out


## M3.4: odpověď na inzerát (počítač → Práce v kraji). Vrací "" = pozván, jinak důvod.
func invite(job_id: String) -> String:
	var j := job(job_id)
	if j.is_empty():
		return "Inzerát už neplatí."
	if current == job_id:
		return "Tady už pracuješ."
	if int(invited.get(job_id, -1)) >= game.clock.jd():
		return "Na tenhle inzerát jsi už odpověděl – pozvánka platí do %s." % _day_text(int(invited[job_id]))
	invited[job_id] = game.clock.jd() + INVITE_DAYS
	return ""


## M3.4: výplata na účet / hotově. Připravená výplata na účet odejde hned.
func set_pay_bank(on: bool) -> void:
	pay_bank = on and game.get("computer") != null
	game.notify(pid, "show_message", ["Výplata: %s." % ("na účet (Moje banka)" if pay_bank else "hotově u zaměstnavatele"), 3.0])
	if pay_bank and can_collect():
		_bank_pay()


func _confirm_quit() -> void:
	game.notify(pid, "open_menu", ["Výpověď", "Opravdu chceš skončit jako %s? Nevyplacenou mzdu dostaneš hned." % title().to_lower(), [
		["Ano, končím", quit],
		["Ne, rozmyslel jsem si to", func(): pass]]])


# ------------------------------------------------------------------ výplata

func can_collect() -> bool:
	return earned_unpaid > 0.0 and pay_from_min >= 0.0 and game.clock.minutes >= pay_from_min


func bonus_k() -> float:
	return clampf((rating - 50.0) / 50.0, 0.0, 1.0) * setting("premie_max", 0.2)


func _net_of(gross: float) -> float:
	return (gross * (1.0 + bonus_k())) * setting("cista_mzda_k", 0.85)


## Výplata u zaměstnavatele; při dluhu na nájmu nabídne jeho zaplacení (`Estate`).
func collect_pay() -> void:
	if not can_collect():
		return
	_boss_say(String(job(current).get("misto", "")), "Tady máš výplatu. Dobrá práce se cení.")
	var clean := not warned_since_pay
	_pay_out("Výplata")
	_after_pay(clean, true)


## M3.4: výplata na účet – sama v den výplaty (tick), bez cesty k zaměstnavateli.
func _bank_pay() -> void:
	var clean := not warned_since_pay
	_pay_out("Výplata na účet", true)
	_after_pay(clean, false)


## Po výplatě: pověst za poctivý týden, naturálie, respekt komunity; osobně navíc nabídka zaplatit dluh na nájmu.
func _after_pay(clean: bool, in_person: bool) -> void:
	var rep: Reputation = game.reputations.get(pid)
	var pt := float(job(current).get("povest_tyden", 0.0))
	if rep and pt != 0.0 and clean:
		rep.change(pt, "poctivá práce (%s) – týden bez napomenutí" % title().to_lower())
	var nat: Dictionary = job(current).get("naturalie", {})     # M3.3: výplata i v naturáliích (pálenice: lahev slivovice)
	for it in nat:
		if ItemsDB.exists(String(it)) and int(nat[it]) > 0:
			player.add_item(String(it), int(nat[it]))
			game.notify(pid, "show_message", ["K výplatě navíc: %d× %s. (Pozor na pokušení – v práci se nepije!)" % [
				int(nat[it]), ItemsDB.name_of(String(it))], 5.0])
	var comm := String(job(current).get("respekt", ""))
	if rep and comm != "":
		var d := clampf((rating - 50.0) / 25.0, -2.0, 2.0)
		if absf(d) >= 0.5:
			rep.change_respect(comm, d, "doporučení od zaměstnavatele" if d > 0.0 else "zaměstnavatel si stěžuje")
	var est: Estate = game.estate
	if in_person and est and est.rent_debt(pid) > 0:
		var debt := est.rent_debt(pid)
		game.notify(pid, "open_menu", ["Dluh na nájmu", "Dlužíš na nájmu %s (%s). Máš %s." % [_kc(debt), game.home_label(pid), _kc(player.money)], [
			["Zaplatit dluh na nájmu (%s)" % _kc(debt), func(): est.pay_rent_debt(pid), player.money >= debt],
			["Později", func(): pass]]])


func _pay_out(what: String, to_bank := false) -> void:
	var gross := earned_unpaid
	var bonus := gross * bonus_k()
	var net := roundi(_net_of(gross))
	earned_unpaid = 0.0
	pay_from_min = -1.0
	warned_since_pay = false
	var pc: Computer = game.get("computer")
	if (to_bank or pay_bank) and pc:           # M3.4: na účet (i doplatek při odchodu, když má hráč výplatu na účet)
		pc.deposit(pid, net, "Mzda – %s (%s)" % [title(), job(current).get("zamestnavatel", "")])
		what += " (na účet)"
	else:
		player.money += net
	total_net += net
	game.play_sfx(pid, "cash")
	game.notify(pid, "popup", ["%s: hrubá mzda %s + prémie %s (%d %%)\n→ čistá mzda %s (zjednodušeno: −%d %% daň a pojištění)." % [
		what, _kc(gross), _kc(bonus), roundi(bonus_k() * 100.0), _kc(net), roundi((1.0 - setting("cista_mzda_k", 0.85)) * 100.0)], 7.0])
	game.emit_game_event(pid, "job_paid", {"job": current, "gross": roundi(gross), "bonus": roundi(bonus), "net": net})


func _add_earnings(gross: float, j: Dictionary) -> void:
	if gross <= 0.0:
		return
	if earned_unpaid <= 0.0 or pay_from_min < 0.0:
		pay_from_min = _payday_min(j)
	earned_unpaid += gross


## Kdy bude výplata: „den“ = hned po směně, „tyden“ = pátek tohoto týdne po poslední páteční směně (jinak ve 14:00).
func _payday_min(j: Dictionary) -> float:
	var now := game.clock.minutes
	if String(j.get("vyplata", "tyden")) == "den":
		return now
	var jd := game.clock.jd()
	var fri := jd + posmod(FRIDAY - jd % 7, 7)
	var h := PAY_DEFAULT_H
	var sh := _my_shifts(j, fri)
	if not sh.is_empty():
		h = 0.0
		for s in sh:
			h = maxf(h, float(s[1]))
	return _abs_min(fri, h)


func _payday_text() -> String:
	if pay_from_min < 0.0:
		return "pátek"
	var jd := _jd_of(pay_from_min)
	return "%s po %s" % [_day_text(jd), _hm(fmod(pay_from_min, 1440.0) / 60.0)]


# ------------------------------------------------------------------ směna

func _process(delta: float) -> void:
	if game == null or game.clock == null:
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = TICK_S
	tick()


## Jeden krok: průběh směny, zmeškané směny (skok času), nová směna.
func tick() -> void:
	var now := game.clock.minutes
	if _last_min < 0.0 or now < _last_min:
		_last_min = now
	var prev := _last_min
	var dt := now - prev
	_last_min = now
	if current == "":
		return
	var j := job(current)
	if j.is_empty():                 # práce zmizela z katalogu (upravený JSON)
		current = ""
		shift = {}
		_clear_targets()
		return
	if not shift.is_empty():
		_update_shift(j, now, dt)
	if pay_bank and can_collect() and current != "":
		_bank_pay()                   # M3.4: výplata na účet přijde sama
	if current == "" or not shift.is_empty():
		return
	if dt > 5.0 and dt <= MISSED_SPAN_MAX:
		_check_missed(j, prev, now)
		if current == "":
			return
	var s := _shift_at(j, now)
	if not s.is_empty() and not resolved.has(s["key"]):
		shift = s


func _make_shift(jd: int, od: float, do_: float) -> Dictionary:
	return {"key": "%d:%s" % [jd, str(od)], "jd": jd, "od": od, "do": do_, "start": _abs_min(jd, od), "end": _abs_min(jd, do_),
		"state": "cekani", "late": false, "paid_min": 0.0, "idle": 0.0, "away": 0.0, "tasks": 0, "task": "", "task_i": -1,
		"n": 0, "goal": 0, "done_idx": [], "zone": "", "drank": false, "warned_away": false, "warned_idle": false,
		"lent": {}, "retry_at": 0.0}


## Směna, která právě běží nebo začne do EARLY_MIN (dnes nebo přes půlnoc ze včerejška).
func _shift_at(j: Dictionary, now: float) -> Dictionary:
	var today := _jd_of(now)
	for jd in [today - 1, today]:
		for s in _my_shifts(j, jd):
			var sh := _make_shift(jd, float(s[0]), float(s[1]))
			if now >= float(sh["start"]) - EARLY_MIN and now < float(sh["end"]) and float(sh["start"]) >= hired_min:
				return sh
	return {}


## Směny, které celé proběhly během přeskočeného času (spánek, záchytka) → absence.
func _check_missed(j: Dictionary, prev: float, now: float) -> void:
	var n := 0
	for jd in range(_jd_of(prev) - 1, _jd_of(now) + 1):
		for s in _my_shifts(j, jd):
			var sh := _make_shift(jd, float(s[0]), float(s[1]))
			if resolved.has(sh["key"]) or float(sh["start"]) < hired_min:
				continue
			if float(sh["start"]) + ABSENT_MIN > prev and float(sh["end"]) <= now:
				n += 1
				if n > MISSED_MAX:
					return
				_resolve(j, sh, "absence", "Zaspal jsi / nepřišel jsi na směnu (%s %s)." % [_day_text(jd), _hm(float(s[0]))])
				if current == "":
					return


func _near_work(j: Dictionary, r: float) -> bool:
	if bool(shift.get("zakazka", false)):          # M3.3: zakázka – areál je u zákazníka
		return game.player_pos(pid).distance_to(_site()) <= r
	var misto := String(j.get("misto", ""))
	if player.inside != "" and player.inside == misto:
		return true
	var pl: Place = game.places.get(misto)
	if pl == null:
		return false
	return game.player_pos(pid).distance_to(pl.door) <= r


## Poloměr areálu práce (M3.2: `areal_r` v katalogu – obecní údržba chodí po vsi, statek má výběh a záhony).
static func area_r(j: Dictionary) -> float:
	if is_contract(j):
		return float((j.get("zakazka", {}) as Dictionary).get("areal_r", CONTRACT_R))
	return float(j.get("areal_r", AREA_R))


## V areálu pracoviště, nebo na pochůzce z úkolu „dojdi“ do ERRAND_R.
func _present(j: Dictionary) -> bool:
	if _near_work(j, area_r(j)):
		return true
	var td := task_def(String(shift.get("task", "")))
	return String(td.get("typ", "")) == "dojdi" and _near_work(j, maxf(ERRAND_R, area_r(j)))


func _update_shift(j: Dictionary, now: float, dt: float) -> void:
	var misto := String(j.get("misto", ""))
	if bool(shift.get("zakazka", false)):
		_update_contract(j, now)
		return
	if String(shift["state"]) == "cekani":
		if now > float(shift["start"]) + ABSENT_MIN or now >= float(shift["end"]):
			_resolve(j, shift, "absence", "Nepřišel jsi na směnu – absence.")
			return
		if now < float(shift["start"]) or not _near_work(j, ARRIVE_R):
			return
		if player.body.promile() > DRUNK_PROMILE:
			_boss_say(misto, "Ty jsi pil! Takhle tě do práce nepustím. Jdi domů (%s) a vyspi se." % game.home_label(pid))
			_resolve(j, shift, "opily", "Přišel jsi do práce pod vlivem (%s ‰) – poslán domů." % ("%.2f" % player.body.promile()).replace(".", ","))
			return
		shift["state"] = "prace"
		shift["late"] = now > float(shift["start"]) + LATE_MIN
		var req: Dictionary = j.get("pozadavky", {})
		if not _outfit_ok(req):
			_boss_say(misto, "Kde máš %s? Příště ať to vidím." % _outfit_name(req))
			rating = clampf(rating + float(RATING["bez_obleceni"]), 0.0, 100.0)
		if bool(shift["late"]):
			_boss_say(misto, "Jdeš pozdě o %d minut! To si zapíšu." % int(now - float(shift["start"])))
			_warn("Pozdní příchod na směnu.")
			if current == "":
				return
		game.emit_game_event(pid, "shift_started", {"job": current, "late": bool(shift["late"])})
		_next_task(j, false)
		var td := task_def(String(shift.get("task", "")))
		game.notify(pid, "popup", ["%s (%s, %s–%s).\nÚkol: %s – %s" % ["Začal jsi směnu" if not bool(shift["late"]) else "Směna (pozdě)",
			title(), _hm(float(shift["od"])), _hm(float(shift["do"])), td.get("nazev", "pomáhej"), td.get("popis", "")], 6.0])
		return
	# --- práce (nepřítomnost se počítá dřív než konec směny – kdo odejde a prospí konec, odešel ze směny)
	var present := _present(j)
	if not present:
		shift["away"] = float(shift["away"]) + dt
		if float(shift["away"]) > LEAVE_MIN:
			_resolve(j, shift, "odesel", "Odešel jsi ze směny bez dovolení – absence.")
			return
	if now >= float(shift["end"]):
		_resolve(j, shift, "pozde" if bool(shift["late"]) else "vcas", "")
		return
	if present:
		shift["away"] = 0.0
		shift["warned_away"] = false
		if String(shift.get("task", "")) != "":
			shift["idle"] = float(shift["idle"]) + dt
		elif now >= float(shift.get("retry_at", 0.0)):
			# M3.2: nebylo co dělat (vše hotovo / mimo sezónu) – vedoucí zkusí najít novou práci
			shift["retry_at"] = now + RETRY_MIN
			_next_task(j, true)
		if float(shift["idle"]) <= IDLE_MIN:
			shift["paid_min"] = float(shift["paid_min"]) + dt
		elif not bool(shift["warned_idle"]):
			shift["warned_idle"] = true
			_boss_say(misto, "Nestůj tu jak svatý na obrázku a makej! Za postávání neplatím.")
	elif not bool(shift["warned_away"]):
		shift["warned_away"] = true
		game.notify(pid, "show_message", ["Jsi mimo pracoviště – vrať se do %d min, jinak je to absence." % int(LEAVE_MIN), 4.0])
	_update_task(j)


## Konec směny (i předčasný). stav: vcas / pozde (odpracováno), absence, opily, odesel.
func _resolve(j: Dictionary, sh: Dictionary, status: String, text: String) -> void:
	var hours := float(sh.get("paid_min", 0.0)) / 60.0
	var gross := hours * float(j.get("mzda_hod", 0))
	var tasks := int(sh.get("tasks", 0))
	resolved.append(String(sh["key"]))
	if resolved.size() > RESOLVED_MAX:
		resolved = resolved.slice(resolved.size() - RESOLVED_MAX)
	if String(sh["key"]) == String(shift.get("key", "")):
		_return_lent()
		shift = {}
		_clear_targets()
	attendance.append({"jd": int(sh["jd"]), "od": float(sh["od"]), "do": float(sh["do"]), "stav": status,
		"h": snappedf(hours, 0.1), "ukoly": tasks, "kc": roundi(gross)})
	if attendance.size() > ATTENDANCE_MAX:
		attendance = attendance.slice(attendance.size() - ATTENDANCE_MAX)
	var dr := float(RATING.get(status, 0.0))
	if status in ["vcas", "pozde"]:
		var expected := maxf(1.0, floorf((float(sh["do"]) - float(sh["od"])) * float(j.get("ukolu_za_hodinu", 0.75))))
		if tasks < int(expected * 0.5):
			dr += float(RATING["malo_ukolu"])
	rating = clampf(rating + dr, 0.0, 100.0)
	_add_earnings(gross, j)
	var xp: Dictionary = j.get("dovednosti_xp", {})
	if hours >= 0.5:
		for s in xp:
			game.give_xp(pid, String(s), HOUR_XP * hours * float(xp[s]), "práce")
	game.emit_game_event(pid, "shift_done", {"job": current, "status": status, "hours": hours, "tasks": tasks, "gross": roundi(gross)})
	match status:
		"vcas", "pozde":
			var pay_txt := "Výplata v %s u zaměstnavatele." % _payday_text()
			if can_collect():
				pay_txt = "Výplata je připravená – E u zaměstnavatele."
			game.notify(pid, "popup", ["Konec směny. Odpracováno %s h, úkolů %d, vyděláno %s hrubého.\n%s" % [
				("%.1f" % hours).replace(".", ","), tasks, _kc(gross), pay_txt], 6.0])
		_:
			_warn(text)


## Napomenutí; po `napomenuti_do_vypovedi` výpověď.
func _warn(text: String) -> void:
	warnings += 1
	warned_since_pay = true
	var lim := int(setting("napomenuti_do_vypovedi", 3.0))
	game.notify(pid, "police_banner", ["Napomenutí v práci (%d / %d): %s" % [warnings, lim, text], 6.0])
	game.emit_game_event(pid, "job_warning", {"job": current, "text": text, "warnings": warnings})
	if warnings >= lim:
		fire("%d napomenutí (pozdní příchody, absence, alkohol)" % warnings)


# ------------------------------------------------------------------ pracovní úkoly

## Další úkol v pořadí `ukoly` (dokola). M3.2: přeskočí úkoly mimo sezónu / počasí (`task_ok`) a úkoly bez cílů
## (vše posekané, odklizené…); když není nic, úkol je "" a vedoucí to za `RETRY_MIN` zkusí znovu.
func _next_task(j: Dictionary, announce := true) -> void:
	var contract := bool(shift.get("zakazka", false))
	var list: Array = shift.get("ukoly_z", []) if contract else j.get("ukoly", [])
	_clear_targets()
	var prev := String(shift.get("task", ""))
	shift["task"] = ""
	shift["n"] = 0
	shift["goal"] = 1
	shift["done_idx"] = []
	shift["zone"] = ""
	if list.is_empty():
		return
	var start := int(shift["task_i"])
	# M3.3: zakázka jde po úkolech jednou (bez opakování dokola); po posledním je hotová
	var n_try := list.size() - (start + 1) if contract else list.size()
	for k in maxi(n_try, 0):
		var i := (start + 1 + k) % list.size()
		var id := String(list[i])
		var td := task_def(id)
		if not task_ok(td, game) or not _has_work(td, j):
			continue
		shift["task_i"] = i
		shift["task"] = id
		shift["goal"] = int(td.get("pocet", 1)) if String(td.get("typ", "")) in ["akce", "modul"] else 1
		_lend_for(td)
		if announce:
			game.notify(pid, "popup", ["Další úkol: %s – %s" % [td.get("nazev", id), td.get("popis", "")], 5.0])
		return
	if contract:
		_contract_end(int(shift.get("tasks", 0)) > 0, "")
		return
	shift["retry_at"] = game.clock.minutes + RETRY_MIN
	if announce and prev != "":
		_boss_say(String(j.get("misto", "")), "Teď tu pro tebe nic není. Počkej, za chvíli něco najdu.")


## Hodí se úkol na dnešek? `mesice` [1–12], `snih_min` / `snih_max` (sníh na zemi 0..1, `Weather.snow_cover`).
static func task_ok(td: Dictionary, w: World) -> bool:
	if td.is_empty():
		return false
	var months: Array = td.get("mesice", [])
	if not months.is_empty() and w.clock and not (w.clock.month() in months) and not (float(w.clock.month()) in months):
		return false
	var snow := w.weather.snow_cover if w.weather else 0.0
	if td.has("snih_min") and snow < float(td["snih_min"]):
		return false
	if td.has("snih_max") and snow > float(td["snih_max"]):
		return false
	var hh: Array = td.get("hodiny", [])          # M3.3: denní doba [od, do)
	if hh.size() >= 2 and w.clock and (w.clock.hour() < float(hh[0]) or w.clock.hour() >= float(hh[1])):
		return false
	return true


## Má úkol na čem pracovat (cíle od poskytovatele)? Úkol bez `cile` (akce kdekoli v areálu) vždy.
func _has_work(td: Dictionary, j: Dictionary) -> bool:
	if String(td.get("cile", "")) == "":
		return true
	return not _points(td, j).is_empty()


func _task_line(td: Dictionary) -> String:
	if td.is_empty():
		return "pomáhej v areálu"
	var s := String(td.get("nazev", ""))
	if int(shift.get("goal", 1)) > 1:
		s += " (%d / %d)" % [int(shift["n"]), int(shift["goal"])]
	return s


func _points(td: Dictionary, j: Dictionary) -> Array:
	var f: Callable = _providers.get(String(td.get("cile", "")), Callable())
	if not f.is_valid():
		return []
	var r = f.call(game, pid, j)
	return r if r is Array else []


static func _target_r(td: Dictionary) -> float:
	return float(td.get("r_cile", TABLE_R))


func _update_task(j: Dictionary) -> void:
	var td := task_def(String(shift.get("task", "")))
	if td.is_empty():
		return
	var pts := _points(td, j)
	match String(td.get("typ", "")):
		"dojdi":
			if pts.is_empty():
				_task_done(j)             # bez bodu (chybí data) se úkol přeskočí
				return
			var r := float(td.get("r", 3.0))
			var pp := player.global_position if player.inside == "" else game.player_pos(pid)
			if pp.distance_to(pts[0]) <= r:
				_task_done(j)
		"modul":
			# M3.3: pokrok hlásí modul (`progress`); cíle došly (vše pokácené, žádný zákazník…) → uznat / přeskočit
			if String(td.get("cile", "")) != "" and pts.is_empty():
				if int(shift["n"]) > 0:
					_task_done(j)
				else:
					_next_task(j)
		"akce":
			if String(td.get("cile", "")) == "":
				return                     # počítá se každá akce v areálu (on_event)
			if pts.is_empty():
				# M3.2: cíle došly (posekáno, sebráno, sníh roztál) – rozdělaný úkol se uzná, jinak se přeskočí
				if int(shift["n"]) > 0:
					_task_done(j)
				else:
					_next_task(j)
				return
			var zone := "%d:%s" % [pts.size(), str(pts[0])]
			if zone != String(shift["zone"]):
				shift["zone"] = zone
				shift["done_idx"] = []
				_register_targets(td, pts)
				# venku (bez interiéru) jsou třeba jen 2 stoly – cíl úkolu se zkrátí na počet dostupných cílů
				shift["goal"] = maxi(1, mini(int(td.get("pocet", 1)), int(shift["n"]) + pts.size()))
				if int(shift["n"]) >= int(shift["goal"]):
					_task_done(j)


func _register_targets(td: Dictionary, pts: Array) -> void:
	_clear_targets()
	var done: Array = shift.get("done_idx", [])
	for i in pts.size():
		if done.has(i):
			continue
		var ad: Dictionary = Actions.DEFS.get(String(td.get("akce", "")), {})
		var t := {"pos": pts[i], "r": _target_r(td), "kind": String(ad.get("target", "job")),
			"data": {"pid": pid, "job": current, "idx": i}}
		_targets.append(t)
		game.register_target(t)


func _clear_targets() -> void:
	for t in _targets:
		game.unregister_target(t)
	_targets.clear()


func _task_done(j: Dictionary) -> void:
	var td := task_def(String(shift.get("task", "")))
	shift["tasks"] = int(shift["tasks"]) + 1
	shift["idle"] = 0.0
	shift["warned_idle"] = false
	rating = clampf(rating + float(RATING["ukol"]), 0.0, 100.0)
	var xp: Dictionary = td.get("dovednosti_xp", j.get("dovednosti_xp", {}))
	for s in xp:
		game.give_xp(pid, String(s), TASK_XP * float(xp[s]), String(td.get("nazev", "úkol")))
	game.play_sfx(pid, "pickup")
	game.notify(pid, "show_message", ["✔ Hotovo: %s" % td.get("nazev", "úkol"), 3.0])
	game.emit_game_event(pid, "job_task_done", {"job": current, "task": String(shift.get("task", ""))})
	_next_task(j)


## Pokrok v úkolu typu „akce“ (akce M0.4 skončila).
func _on_action(data: Dictionary) -> void:
	if shift.is_empty() or String(shift["state"]) != "prace":
		return
	var j := job(current)
	var td := task_def(String(shift.get("task", "")))
	if String(td.get("typ", "")) != "akce" or String(data.get("action", "")) != String(td.get("akce", "")):
		return
	if not bool(data.get("ok", true)):
		return
	var pos: Vector3 = data.get("pos", Vector3.INF)
	if String(td.get("cile", "")) != "":
		# cíl z registru: odškrtni nejbližší (stůl, dlaždici trávy, koryto…)
		var best: Dictionary = {}
		var bd := INF
		for t in _targets:
			var d := (t["pos"] as Vector3).distance_to(pos)
			if d < bd:
				bd = d
				best = t
		if best.is_empty() or bd > _target_r(td) + 0.5:
			return
		(shift["done_idx"] as Array).append(int(best["data"]["idx"]))
		game.unregister_target(best)
		_targets.erase(best)
	elif not _near_work(j, area_r(j)):
		return
	_step(j, td, 1)


## Krok úkolu (+`n`); po dosažení cíle úkol hotový.
func _step(j: Dictionary, td: Dictionary, n: int) -> void:
	shift["n"] = int(shift["n"]) + n
	shift["idle"] = 0.0
	shift["warned_idle"] = false
	if int(shift["n"]) >= int(shift["goal"]):
		_task_done(j)
	else:
		game.notify(pid, "show_message", ["%s: %d / %d" % [td.get("nazev", ""), int(shift["n"]), int(shift["goal"])], 2.0])


## M3.3: pokrok v úkolu typu „modul“ (nebo jakémkoli) hlášený modulem práce – jen když je úkol `task` právě zadaný.
## Vrací true, když se započítal.
func progress(task: String, n := 1) -> bool:
	if not on_shift() or String(shift.get("task", "")) != task or n <= 0:
		return false
	_step(job(current), task_def(task), n)
	return true


## M3.3: místo probíhající zakázky (Vector3.INF = žádná).
func _site() -> Vector3:
	var a: Array = shift.get("site", [])
	return Vector3(float(a[0]), float(a[1]), float(a[2])) if a.size() >= 3 else Vector3.INF


## M3.3: probíhající zakázka {key, pos, label, customer} nebo {} – pro moduly prací (zóna u zákazníka).
func contract() -> Dictionary:
	if not bool(shift.get("zakazka", false)):
		return {}
	return {"key": String(shift.get("key", "")), "pos": _site(), "label": String(shift.get("site_label", "")),
		"customer": String(shift.get("customer", "")), "seed": int(shift.get("seed", 0))}


# ------------------------------------------------------------------ zakázky (M3.3)

func _contract_options(j: Dictionary) -> Array:
	var out := []
	if shift.is_empty():
		var wait := contract_next - game.clock.minutes
		if wait > 0.0:
			out.append(["Zakázka: teď nic (zkus to za %d h)" % ceili(wait / 60.0), func(): pass, false])
		else:
			out.append(["Vzít zakázku", take_contract])
	else:
		out.append(["Zakázka: %s – %s, do %s" % [shift.get("customer", "?"), shift.get("site_label", ""), _hm(float(shift["do"]))],
			func(): game.notify(pid, "popup", [_contract_text(), 6.0])])
		out.append(["Vzdát zakázku", func(): _contract_end(false, "vzdal")])
	return out


## Nová zakázka od tvůrce zakázek (`zakazka.tvurce`): místo u zákazníka, úkoly, odměna, lhůta.
func take_contract() -> void:
	var j := job(current)
	if not is_contract(j) or not shift.is_empty():
		return
	var zc: Dictionary = j.get("zakazka", {})
	var f: Callable = _makers.get(String(zc.get("tvurce", "")), Callable())
	var c = f.call(game, pid, j) if f.is_valid() else {}
	var misto := String(j.get("misto", ""))
	if not (c is Dictionary) or (c as Dictionary).is_empty() or ((c as Dictionary).get("ukoly", []) as Array).is_empty():
		_boss_say(misto, "Teď nikdo nic nepotřebuje. Zkus to zase za pár hodin.")
		contract_next = game.clock.minutes + 60.0
		return
	var now := game.clock.minutes
	var jd := game.clock.jd()
	var od := (now - _abs_min(jd, 0.0)) / 60.0
	var hours := float(zc.get("lhuta_h", CONTRACT_H))
	shift = _make_shift(jd, od, od + hours)
	shift["key"] = "z:%d" % int(now)
	shift["state"] = "prace"
	shift["zakazka"] = true
	var pos: Vector3 = c.get("pos", Vector3.ZERO)
	shift["site"] = [pos.x, pos.y, pos.z]
	shift["site_label"] = String(c.get("label", ""))
	shift["customer"] = String(c.get("customer", "soused"))
	shift["reward"] = int(c.get("odmena", 500))
	shift["seed"] = int(c.get("seed", 0))
	var ids := []
	for t in c.get("ukoly", []):
		ids.append(String(t))
	shift["ukoly_z"] = ids
	var brief := String(c.get("zadani", "%s potřebuje pomoct." % shift["customer"]))
	_boss_say(misto, "%s Běž tam, ať to máš do %s." % [brief, _hm(float(shift["do"]))])
	game.notify(pid, "popup", [_contract_text(), 8.0])
	game.play_sfx(pid, "pickup")
	game.emit_game_event(pid, "job_contract", {"job": current, "reward": int(shift["reward"]), "tasks": ids})
	_next_task(j, false)


func _contract_text() -> String:
	var names := []
	for t in shift.get("ukoly_z", []):
		names.append(String(task_def(String(t)).get("nazev", t)).to_lower())
	return "ZAKÁZKA: %s (%s)\nPráce: %s.\nOdměna %s na ruku, hotovo do %s. Kompas ukáže místo." % [shift.get("customer", "?"),
		shift.get("site_label", ""), ", ".join(names), _kc(float(shift.get("reward", 0))), _hm(float(shift.get("do", 0.0)))]


## Zakázka běží: lhůta, místo u zákazníka, úkoly (bez hodinové mzdy a bez absencí – odměna jen za hotovou práci).
func _update_contract(j: Dictionary, now: float) -> void:
	if now >= float(shift["end"]):
		_contract_end(false, "nestihl")
		return
	if not _present(j):
		return
	if String(shift.get("task", "")) == "" and now >= float(shift.get("retry_at", 0.0)):
		shift["retry_at"] = now + RETRY_MIN
		_next_task(j, true)
		if shift.is_empty():
			return
	_update_task(j)


## Konec zakázky: hotová (odměna na ruku, respekt), nestihl / vzdal (hodnocení, respekt; nestihl = napomenutí),
## `why` "" bez hotového úkolu = zrušená (není co dělat, bez postihu).
func _contract_end(ok: bool, why: String) -> void:
	if not bool(shift.get("zakazka", false)):
		return
	var j := job(current)
	var zc: Dictionary = j.get("zakazka", {})
	var sh := shift
	var reward := int(sh.get("reward", 0))
	var tasks := int(sh.get("tasks", 0))
	var misto := String(j.get("misto", ""))
	var status := "zakazka" if ok else ("zrusena" if why == "" else "nesplneno")
	_return_lent()
	shift = {}
	_clear_targets()
	contract_next = game.clock.minutes + float(zc.get("pauza_h", CONTRACT_PAUSE_H)) * 60.0
	attendance.append({"jd": int(sh["jd"]), "od": float(sh["od"]), "do": float(sh["do"]), "stav": status,
		"h": 0.0, "ukoly": tasks, "kc": reward if ok else 0})
	if attendance.size() > ATTENDANCE_MAX:
		attendance = attendance.slice(attendance.size() - ATTENDANCE_MAX)
	var rep: Reputation = game.reputations.get(pid)
	var comm := String(j.get("respekt", ""))
	if ok:
		rating = clampf(rating + float(CONTRACT_RATING["hotovo"]), 0.0, 100.0)
		player.money += reward
		total_net += reward
		if rep and comm != "":
			rep.change_respect(comm, float(zc.get("respekt", 1.5)), "zakázka pro souseda (%s)" % sh.get("customer", ""))
		game.play_sfx(pid, "cash")
		game.notify(pid, "popup", ["Zakázka hotová! %s ti zaplatil %s na ruku.\n(Zjednodušeno: brigáda bez odvodů – viz poznámka v data/prace.json.)" % [
			sh.get("customer", "Zákazník"), _kc(float(reward))], 6.0])
		game.emit_game_event(pid, "job_paid", {"job": current, "gross": reward, "bonus": 0, "net": reward, "contract": true})
		game.emit_game_event(pid, "job_contract_done", {"job": current, "reward": reward, "tasks": tasks})
		return
	if why == "":
		_boss_say(misto, "Tak nakonec není co dělat, zakázka padá. Nic se neděje.")
		return
	rating = clampf(rating + float(CONTRACT_RATING["nesplneno"]), 0.0, 100.0)
	if rep and comm != "":
		rep.change_respect(comm, -1.0, "nedokončená zakázka")
	game.emit_game_event(pid, "job_contract_failed", {"job": current, "reason": why})
	if why == "nestihl":
		_warn("Nedokončená zakázka (%s) – zákazník si stěžoval." % sh.get("customer", ""))
	else:
		game.notify(pid, "show_message", ["Zakázku jsi vzdal – %s to nepotěšilo." % sh.get("customer", "zákazníka"), 4.0])


# ------------------------------------------------------------------ zapůjčené nářadí (M3.2)

## Na začátku úkolu půjčí vedoucí nářadí / materiál z `zapujcit`, pokud ho hráč nemá (vlastní se nepůjčuje).
func _lend_for(td: Dictionary) -> void:
	var z = td.get("zapujcit", [])
	var want := {}
	if z is Array:
		for it in z:
			want[String(it)] = 1
	elif z is Dictionary:
		for it in z:
			want[String(it)] = int(z[it])
	var got := []
	for it in want:
		var n := int(want[it]) - player.item_count(it)
		if n > 0 and ItemsDB.exists(it):
			lend(it, n)
			got.append("%s%s" % [ItemsDB.name_of(it), " (%d×)" % n if n > 1 else ""])
	if not got.is_empty():
		game.notify(pid, "show_message", ["%s ti půjčil: %s. Po směně ho vrátíš. (Q = vzít do ruky)" % [
			_boss_name(String(job(current).get("misto", ""))), ", ".join(got)], 4.5])


## Půjčí hráči `n` kusů na směnu (po směně se vrátí). Volá i Statek (seno z hromady).
func lend(item: String, n := 1) -> void:
	if shift.is_empty() or n <= 0:
		return
	player.add_item(item, n)
	var l: Dictionary = shift.get("lent", {})
	l[item] = int(l.get(item, 0)) + n
	shift["lent"] = l


## Spotřebovaný zapůjčený materiál (seno do koryta, písek na chodník) – už se nevrací.
func unlend(item: String, n := 1) -> void:
	var l: Dictionary = shift.get("lent", {})
	if l.has(item):
		l[item] = maxi(int(l[item]) - n, 0)
		if int(l[item]) <= 0:
			l.erase(item)


## Po směně (i předčasném konci) vrátí zapůjčené kusy, které hráč ještě má.
func _return_lent() -> void:
	var l: Dictionary = shift.get("lent", {})
	var back := []
	for it in l.keys():
		var n := mini(int(l[it]), player.item_count(String(it)))
		if n > 0:
			player.remove_item(String(it), n)
			back.append(ItemsDB.name_of(String(it)))
	if not shift.is_empty():
		shift["lent"] = {}
	if not back.is_empty():
		game.notify(pid, "show_message", ["Vrátil jsi zapůjčené: %s." % ", ".join(back), 3.0])


## Hráč právě pracuje na směně práce `job_id` (M3.2: statek, výčep – kontrola cílů mimo Jobs).
func on_shift(job_id := "") -> bool:
	return current != "" and (job_id == "" or current == job_id) and not shift.is_empty() \
		and String(shift.get("state", "")) == "prace"


## Id právě zadaného úkolu ("" = žádný).
func task_id() -> String:
	return String(shift.get("task", "")) if on_shift() else ""


## Úprava hodnocení 0–100 zvenku (výčep: spokojený / naštvaný host).
func adjust_rating(d: float) -> void:
	rating = clampf(rating + d, 0.0, 100.0)


## Cíl pro kompas / mapu (Vector3.INF = nic): pracoviště před směnou a mimo areál, jinak bod úkolu.
func target() -> Vector3:
	if current == "" or shift.is_empty():
		return Vector3.INF
	var j := job(current)
	var pl: Place = game.places.get(String(j.get("misto", "")))
	var door := pl.door if pl else Vector3.INF
	if bool(shift.get("zakazka", false)):
		door = _site()                           # M3.3: zakázka – místo u zákazníka
	if String(shift["state"]) != "prace" or not _present(j):
		return door
	var td := task_def(String(shift.get("task", "")))
	if String(td.get("typ", "")) == "dojdi":
		var pts := _points(td, j)
		return pts[0] if not pts.is_empty() else door
	var best := Vector3.INF
	for t in _targets:
		var p: Vector3 = t["pos"]
		if best == Vector3.INF or p.distance_squared_to(player.global_position) < best.distance_squared_to(player.global_position):
			best = p
	if best == Vector3.INF and String(td.get("typ", "")) == "modul" and String(td.get("cile", "")) != "":
		for p in _points(td, j):                 # M3.3: modul – nejbližší bod od poskytovatele (vyznačený strom…)
			if best == Vector3.INF or (p as Vector3).distance_squared_to(player.global_position) < best.distance_squared_to(player.global_position):
				best = p
	if best == Vector3.INF and String(td.get("kompas", "")) != "":
		var f: Callable = _providers.get(String(td["kompas"]), Callable())
		if f.is_valid():
			var r = f.call(game, pid, j)
			if r is Array and not (r as Array).is_empty():
				best = r[0]
	return best


# ------------------------------------------------------------------ poskytovatelé cílů

## Stoly hospody: v postaveném interiéru, když je v něm hráč (M1.5 / M1.8 – staví se jen zblízka), jinak stoly zahrádky.
static func _tables_provider(w: World, id: int, _j: Dictionary) -> Array:
	var p: Player = w.players.get(id)
	var it: Interior = w.interiors.get("hospoda")
	if p and p.inside == "hospoda" and it and it.built:
		var out := []
		for k in it.spots:
			if String(k).begins_with("stul:"):
				out.append((it.spots[k] as Array)[0])
		if not out.is_empty():
			return out
	var pl: Place = w.places.get("hospoda")
	var outs := []
	if pl:
		for c in pl.garden_tables:
			outs.append(c + Vector3(0, 0.8, 0))
	return outs


## Nejbližší popelnice u silnice (rekvizita) do 150 m od pracoviště; bez ní bod 6 m vedle dveří.
static func _bin_provider(w: World, _id: int, j: Dictionary) -> Array:
	var pl: Place = w.places.get(String(j.get("misto", "")))
	if pl == null:
		return []
	var root := w.get_node_or_null("Vybaveni_ulic")
	var best := Vector3.INF
	if root:
		for c in root.get_children():
			if c is Prop and (c as Prop).kind == "popelnice":
				var p: Vector3 = (c as Prop).global_position
				if p.distance_to(pl.door) < 150.0 and (best == Vector3.INF or p.distance_to(pl.door) < best.distance_to(pl.door)):
					best = p
	if best == Vector3.INF:
		var face := float(pl.data.get("face_yaw", 0.0))
		best = pl.door + Basis(Vector3.UP, face) * Vector3(6.0, 0, 2.0)
	return [best]


# ------------------------------------------------------------------ události

func on_event(kind: String, data: Dictionary) -> void:
	if current != "":
		var hook: Callable = _hooks.get(current, Callable())
		if hook.is_valid():
			hook.call(self, kind, data)          # M3.3: modul práce (vyznačené stromy, výsadba…)
	match kind:
		"action_done":
			_on_action(data)
		"drank":
			if current != "" and not shift.is_empty() and String(shift["state"]) == "prace" and not bool(shift["drank"]) \
					and Consumables.is_alcohol(String(data.get("id", ""))):
				shift["drank"] = true
				rating = clampf(rating + float(RATING["pil"]), 0.0, 100.0)
				_boss_say(String(job(current).get("misto", "")), "V práci se nepije! To máš napomenutí.")
				_warn("Pití alkoholu v práci.")
		"busted":
			if current != "":
				fire("zadržen policií")
		"jailed":                       # M4.3 vězení
			if current != "":
				fire("nástup do vězení")


# ------------------------------------------------------------------ texty (HUD, deník)

func _boss_name(place: String) -> String:
	for id in jobs_at(place):
		var b := String(job(id).get("vedouci", ""))
		if b != "":
			return b
	var pl: Place = game.places.get(place)
	return pl.keeper.display_name if pl and pl.keeper else "Vedoucí"


## Vedoucí něco řekne (bublina u obsluhy místa + text v HUD).
func _boss_say(place: String, text: String) -> void:
	var pl: Place = game.places.get(place)
	if pl and pl.keeper and is_instance_valid(pl.keeper):
		pl.keeper.say(text, 4.5)
	elif pl == null and game.npcs.has(place) and is_instance_valid(game.npcs[place]):
		(game.npcs[place] as Npc).say(text, 4.5)      # M3.3: děda (zakázky zahradníka) není Place
	game.notify(pid, "show_message", ["%s: „%s“" % [_boss_name(place), text], 5.0])


## Malý řádek do panelu úkolu nahoře (BBCode); "" = nic (bez práce / daleko do směny).
func hud_text() -> String:
	if current == "":
		return ""
	var now := game.clock.minutes
	if shift.is_empty():
		if can_collect():
			return "[b]%s[/b]  [color=#8f8]výplata připravená – E u zaměstnavatele[/color]" % title()
		return ""
	if bool(shift.get("zakazka", false)):
		var hz := "[b]Zakázka do %s[/b]  [color=#aaa](%s – %s, %s)[/color]" % [_hm(float(shift["do"])), title(),
			shift.get("customer", ""), shift.get("site_label", "")]
		if not _present(job(current)):
			return hz + "\n▸ Jdi k zákazníkovi (%s) – kompas ukazuje směr. Odměna %s." % [shift.get("site_label", ""),
				_kc(float(shift.get("reward", 0)))]
		return hz + "\n▸ Úkol: %s\n  [color=#9fd]odměna %s na ruku po dokončení[/color]" % [
			_task_line(task_def(String(shift.get("task", "")))), _kc(float(shift.get("reward", 0)))]
	var head := "[b]Směna %s–%s[/b]  [color=#aaa](%s)[/color]" % [_hm(float(shift["od"])), _hm(float(shift["do"])), title()]
	if String(shift["state"]) == "cekani":
		var left := float(shift["start"]) - now
		var pl: Place = game.places.get(String(job(current).get("misto", "")))
		var place_name := String(pl.data.get("name", "práce")) if pl else "práce"
		if left > 0.0:
			return head + "\n▸ Přijď na pracoviště (%s) – začátek za %d min" % [place_name, int(left)]
		return head + "\n▸ [color=#f96]Jdeš pozdě (%d min)! Rychle na pracoviště (%s).[/color]" % [int(-left), place_name]
	var td := task_def(String(shift.get("task", "")))
	var s := head + "\n▸ Úkol: %s" % _task_line(td)
	s += "\n  [color=#9fd]dnes %s h · %s hrubého[/color]" % [("%.1f" % (float(shift["paid_min"]) / 60.0)).replace(".", ","),
		_kc(float(shift["paid_min"]) / 60.0 * float(job(current).get("mzda_hod", 0)))]
	if float(shift["away"]) > 0.0:
		s += "\n  [color=#f96]mimo pracoviště %d / %d min[/color]" % [int(shift["away"]), int(LEAVE_MIN)]
	return s


## Oddíl „Práce“ do deníku J.
func journal_bbcode() -> String:
	var s := "\n[b]PRÁCE[/b]\n"
	if current == "":
		var offers := []
		for id in all_jobs():
			var j := job(String(id))
			offers.append("%s – %s" % [j.get("nazev", id), j.get("zamestnavatel", "")])
		s += "Bez zaměstnání."
		if not offers.is_empty():
			s += " Práci nabízí (E u místa → „Hledáte pracovníky?“):\n  [color=#ccc]• %s[/color]\n" % "\n  • ".join(offers)
		else:
			s += "\n"
	else:
		var j := job(current)
		var lim := int(setting("napomenuti_do_vypovedi", 3.0))
		s += "%s – %s, vedoucí %s (od %s)\n" % [j.get("nazev", current), j.get("zamestnavatel", ""), j.get("vedouci", "?"), _day_text(hired_jd)]
		if is_contract(j):
			var zc: Dictionary = j.get("zakazka", {})
			var od: Array = zc.get("odmena", [0, 0])
			s += "Na zavolání: zakázku vezmeš u %s · odměna %d–%d Kč za zakázku na ruku\n" % [_boss_name(String(j.get("misto", ""))),
				int(od[0]) if not od.is_empty() else 0, int(od[-1]) if not od.is_empty() else 0]
			if not shift.is_empty():
				s += "[color=#9fd]%s[/color]\n" % _contract_text().replace("\n", " ")
		else:
			s += "Směny: %s · mzda %d Kč/h hrubého · výplata %s\n" % [shifts_text(j, shift_pick), int(j.get("mzda_hod", 0)),
				("v pátek" if String(j.get("vyplata", "tyden")) == "tyden" else "po směně") + (" na účet" if pay_bank else " u zaměstnavatele")]
		s += "Napomenutí: [color=#%s]%d / %d[/color]   Hodnocení: %d / 100 (prémie %d %%)\n" % [
			"f88" if warnings >= lim - 1 else "ccc", warnings, lim, roundi(rating), roundi(bonus_k() * 100.0)]
		if earned_unpaid > 0.0:
			s += "K výplatě: %s hrubého (%s)\n" % [_kc(earned_unpaid), "připraveno" if can_collect() else "od " + _payday_text()]
	s += "Vyděláno celkem: %s čistého\n" % _kc(total_net)
	if not attendance.is_empty():
		s += "Docházka (poslední směny):\n"
		var last: Array = attendance.slice(maxi(attendance.size() - 8, 0))
		last.reverse()
		for a in last:
			var st := String(a.get("stav", ""))
			s += "  %s %s–%s  [color=#%s]%s[/color]" % [_day_text(int(a["jd"])), _hm(float(a["od"])), _hm(float(a["do"])),
				STATUS_COLOR.get(st, "ccc"), STATUS_TEXT.get(st, st)]
			if float(a.get("h", 0.0)) > 0.0:
				s += ", %s h, úkolů %d, %s" % [("%.1f" % float(a["h"])).replace(".", ","), int(a.get("ukoly", 0)), _kc(float(a.get("kc", 0)))]
			s += "\n"
	if not history.is_empty():
		var h: Dictionary = history[-1]
		s += "Dříve: %s (%s)\n" % [job(String(h["job"])).get("nazev", h["job"]), h.get("why", "")]
	return s


# ------------------------------------------------------------------ ladění (F2 → Hráč)

func debug(what: String) -> String:
	if what.begins_with("hire:"):        # M3.2: F2 → Hráč → „Práce: přijmout…“ s výběrem práce (bez požadavků a pohovoru)
		var id := what.substr(5)
		if job(id).is_empty():
			return "Taková práce v katalogu není."
		if current == id:
			return "Už pracuješ: %s." % title()
		if current != "":
			_leave("přeřazení (ladění F2)", "job_quit", 0.0)
		_hire(id)
		return "Přijat: %s." % title()
	match what:
		"hire":
			var ids := all_jobs().keys()
			if ids.is_empty():
				return "Katalog prací je prázdný (data/prace.json)."
			if current != "":
				return "Už pracuješ: %s." % title()
			_hire(String(ids[0]))
			return "Přijat: %s." % title()
		"req":                            # M3.2: splnit požadavky prací (výřečnost 3, pracovní boty na sobě, střízlivost)
			var sk: Skills = game.skills.get(pid)
			if sk:
				# M3.3: + dřevorubectví 8 (lesní dělník), zahradničení 5 (zahradník)
				var lv := {"vyrecnost": 3, "chovatelstvi": 3, "drevorubectvi": 8, "zahradnictvi": 5}
				for s in lv:
					var need := Skills.xp_for_level(int(lv[s])) - sk.total_xp(String(s))
					if need > 0.0:
						game.give_xp(pid, String(s), need + 1.0, "ladění")
			if player.item_count("pracovni_boty") <= 0:
				player.add_item("pracovni_boty")
			player.body.body_alc = 0.0
			player.body.stomach_alc = 0.0
			Wardrobe.change(game, pid, "boty", "pracovni_boty", true)
			return "Výřečnost a chovatelství 3, dřevorubectví 8, zahradničení 5, pracovní boty na sobě, střízlivý."
		"shift":
			if current == "":
				return "Nejdřív se nech zaměstnat."
			var j := job(current)
			var now := game.clock.minutes
			if is_contract(j):                  # M3.3: zakázka hned + teleport k zákazníkovi
				contract_next = -1.0
				if shift.is_empty():
					take_contract()
				if shift.is_empty():
					return "Zakázka teď není."
				var sp := _site()
				game.teleport_player(pid, sp + Vector3(3.0, 0, 3.0), player.yaw)
				return "Zakázka: %s." % String(shift.get("site_label", ""))
			for d in 8:
				var jd := _jd_of(now) + d
				for s in _my_shifts(j, jd):
					var st := _abs_min(jd, float(s[0])) - 5.0
					if st > now:
						game.clock.minutes = st
						_last_min = st
						if game.weather:
							game.weather._last_min = st      # jako World.set_time – počasí nepřepočítává skok
						var pl: Place = game.places.get(String(j.get("misto", "")))
						if pl:
							game.teleport_player(pid, pl.door, player.yaw)
						return "Čas posunut na 5 min před směnu (%s %s)." % [_day_text(jd), _hm(float(s[0]))]
			return "Žádná směna v příštím týdnu."
		"pay":
			if current == "":
				return "Bez práce."
			if earned_unpaid <= 0.0:
				earned_unpaid = 600.0
			pay_from_min = game.clock.minutes
			return "Výplata připravena u zaměstnavatele (%s hrubého)." % _kc(earned_unpaid)
		"warn":
			if current == "":
				return "Bez práce."
			_warn("ladění (F2)")
			return "Napomenutí %d." % warnings
	return ""


# ------------------------------------------------------------------ ukládání

func to_dict() -> Dictionary:
	return {"current": current, "hired_jd": hired_jd, "hired_min": hired_min, "warnings": warnings, "attendance": attendance,
		"earned": earned_unpaid, "pay_from": pay_from_min, "rating": rating, "total_net": total_net, "history": history,
		"retry": retry, "resolved": resolved, "shift": _shift_save(), "warned_since_pay": warned_since_pay,
		"shift_pick": shift_pick, "contract_next": contract_next, "pay_bank": pay_bank, "invited": invited}


func _shift_save() -> Dictionary:
	if shift.is_empty():
		return {}
	var d := shift.duplicate(true)
	d["zone"] = ""               # cíle se po načtení zaregistrují znovu
	d["done_idx"] = []
	return d


## Načtení (starý save bez klíče `jobs` = bez zaměstnání). Neznámá práce (změněný katalog) = bez práce.
func from_dict(d: Dictionary) -> void:
	_clear_targets()
	current = String(d.get("current", ""))
	if current != "" and job(current).is_empty():
		current = ""
	hired_jd = int(d.get("hired_jd", -1))
	hired_min = float(d.get("hired_min", 0.0))
	warnings = int(d.get("warnings", 0))
	attendance = (d.get("attendance", []) as Array).duplicate(true)
	earned_unpaid = float(d.get("earned", 0.0))
	pay_from_min = float(d.get("pay_from", -1.0))
	rating = float(d.get("rating", 50.0))
	total_net = int(d.get("total_net", 0))
	history = (d.get("history", []) as Array).duplicate(true)
	retry = {}
	var r: Dictionary = d.get("retry", {})
	for k in r:
		retry[String(k)] = int(r[k])
	resolved = []
	for k in d.get("resolved", []):
		resolved.append(String(k))
	warned_since_pay = bool(d.get("warned_since_pay", false))
	shift_pick = String(d.get("shift_pick", ""))          # M3.3 (starý save = všechny směny; práce s variantami → první)
	var vars := shift_variants(job(current)) if current != "" else []
	if not vars.is_empty() and not vars.has(shift_pick):
		shift_pick = String(vars[0])
	contract_next = float(d.get("contract_next", -1.0))
	pay_bank = bool(d.get("pay_bank", false))             # M3.4 (starý save = hotově)
	invited = {}
	var inv: Dictionary = d.get("invited", {})
	for k in inv:
		invited[String(k)] = int(inv[k])
	shift = {}
	var sh: Dictionary = d.get("shift", {})
	if current != "" and not sh.is_empty() and sh.has("key"):
		shift = _make_shift(int(sh.get("jd", 0)), float(sh.get("od", 0.0)), float(sh.get("do", 0.0)))
		for k in ["state", "late", "paid_min", "idle", "away", "tasks", "task", "task_i", "n", "goal", "drank", "retry_at",
				"key", "zakazka", "site", "site_label", "customer", "reward", "seed", "ukoly_z"]:      # M3.3: zakázka
			if sh.has(k):
				shift[k] = sh[k]
		if bool(shift.get("zakazka", false)):
			shift["reward"] = int(shift.get("reward", 0))
			shift["seed"] = int(shift.get("seed", 0))
			var ids := []
			for t in shift.get("ukoly_z", []):
				ids.append(String(t))
			shift["ukoly_z"] = ids
		var lent := {}                 # M3.2: zapůjčené nářadí (vrátí se po směně)
		var ls: Dictionary = sh.get("lent", {})
		for k in ls:
			lent[String(k)] = int(ls[k])
		shift["lent"] = lent
		shift["state"] = String(shift["state"])
		shift["task"] = String(shift["task"])
		shift["task_i"] = int(shift["task_i"])
		shift["n"] = int(shift["n"])
		shift["goal"] = int(shift["goal"])
		shift["tasks"] = int(shift["tasks"])
	_last_min = game.clock.minutes if game and game.clock else -1.0
