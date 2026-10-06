class_name Court
extends Node

## Soud a vězení (M4.3): trestný čin → obvinění (`World.commit_offense` misto „soud“) → předvolání poštou →
## jednání s volbami (přiznat / mlčet / zapírat / obhájce) → rozsudek: peněžitý trest (Debts, kind „trest“),
## zákaz řízení (Permits), podmínka, obecně prospěšné práce (zatím jen evidence), nepodmíněný trest
## (`World.skip_long`). Jedna instance `World.court`, stav per hráč (klíč `court` v save_game).
## Sazby a rozmezí jsou v `data/zakon.json` → `tresty`; tady jen logika a váhy skóre.

## dny od obvinění do předvolání (rozmezí); jednání je o 2 dny později
const SUMMON_DAYS := [3, 7]
const TRIAL_GAP_DAYS := 2
## hodina jednání, okno pro příchod, herní doba jednání (posun času)
const TRIAL_HOUR := 9.0
const ATTEND_HOURS := 2.0
const TRIAL_HOURS := 4.0
## dočasně místo autobusové zastávky (ve hře zatím není – otevřený bod): dveře úřadu
const ATTEND_RADIUS := 40.0
const TRAFFIC := ["alkohol_nad_1", "alkohol_do_1", "rizeni_pres_zakaz"]
const SOURCE := "Okresní soud (smyšlený)"
## váhy skóre jednání (vyšší = mírnější rozsudek)
const SCORE_VOLBA := {"priznat": 2, "mlcet": 0, "zapirat": -1}
const SCORE_OBHAJCE := 1
const SCORE_RECIDIVA := -1
const SCORE_RECIDIVA_MAX := 3
const SCORE_POVEST := 1          # polehčující: pověst ≥ 30 (−1 při ≤ −30)
const SCORE_KARMA := 1           # polehčující: karma ≥ 30
const HARD_POKUTA := 30000       # těžký čin: nejvyšší pokuta z katalogu ≥ tato částka …
const HARD_RECIDIVA := 2         # … nebo aspoň tolik předchozích trestů
const ABSENT_FINE_MULT := 1.5

var world: World
var _cases := {}       # pid → Array[Dictionary] {id, oid, name, par, drb, pokuta_max, t, stav, summon_jd, trial_jd, obhajce, open_ms, verdict}
var _probation := {}   # pid → {do_jd, podm_mes}
var _opp := {}         # pid → {h_left, deadline_jd} (OPP – evidence, odpracování v dalším kroku)
var _seq := {}         # pid → počet případů (unikátní id)


func setup(w: World) -> void:
	world = w


static func _tr() -> Dictionary:
	return Law.load_catalog().get("tresty", {}) as Dictionary


static func _rng(key: String, sev: float) -> float:
	return Law._lerp_range(_tr().get(key), sev)


func _ensure(pid: int) -> void:
	if not _cases.has(pid):
		_cases[pid] = []


func _case(pid: int, cid: String) -> Dictionary:
	for c in _cases.get(pid, []):
		if String(c["id"]) == cid:
			return c
	return {}


func _jd() -> int:
	return world.clock.jd()


## Zavolá World.commit_offense při přestupku s misto „soud“. rec_t = čas záznamu v rejstříku (dohledání záznamu).
func open_case(pid: int, res: Dictionary, rec_t: float) -> String:
	_ensure(pid)
	var o := Law.offense(String(res.get("id", "")))
	var n: int = int(_seq.get(pid, 0)) + 1
	_seq[pid] = n
	var jd := _jd()
	var summon := jd + randi_range(int(_tr().get("zkouska_dni", SUMMON_DAYS)[0]), int(_tr().get("zkouska_dni", SUMMON_DAYS)[1]))
	var pm: Array = o.get("pokuta", [0, 0])
	var c := {"id": "c%d" % n, "oid": String(res.get("id", "")), "name": String(res.get("name", "")),
		"par": String(res.get("par", "?")), "drb": String(o.get("drb", "")), "pokuta_max": int(pm[1]) if pm.size() > 1 else 0,
		"t": rec_t, "stav": "obvineni", "summon_jd": summon, "trial_jd": summon + TRIAL_GAP_DAYS, "obhajce": false, "open_ms": 0}
	(_cases[pid] as Array).append(c)
	if world.law.has(pid):
		var lr: Law.LawRecord = world.law[pid]
		for r in lr.records:
			if String((r as Dictionary).get("id", "")) == c["oid"] and is_equal_approx(float((r as Dictionary).get("t", -1.0)), rec_t):
				(r as Dictionary)["stav"] = "obvineni"
	world.notify(pid, "show_message", ["Obvinění: %s. Předvolání k soudu přijde poštou." % c["name"], 5.0])
	return String(c["id"])


## Denní krok / kontrola každý snímek (levné): předvolání, začátek jednání, nepřítomnost.
func tick() -> void:
	if world == null or world.clock == null:
		return
	var jd := _jd()
	var h := world.clock.hour()
	for pid in _cases.keys():
		for c in _cases[pid]:
			var st := String(c["stav"])
			if st == "obvineni" and jd >= int(c["summon_jd"]):
				c["stav"] = "predvolan"
				world.send_mail(pid, SOURCE, "Předvolání k soudu",
					"Byl jste předvolán k jednání ve věci: %s (%s).\nTermín: za %d dní od doručení, 9:00. Odvoz k soudu zajišťuje obec (zastávka u úřadu).\nZjednodušená herní simulace – ověřit aktuální znění zákonů." % [
					c["name"], c["par"], int(c["trial_jd"]) - jd])
				st = "predvolan"
			if st == "predvolan" and jd >= int(c["trial_jd"]):
				if h >= TRIAL_HOUR and h < TRIAL_HOUR + ATTEND_HOURS and _at_court(pid):
					_open_trial(pid, c)
				elif h >= TRIAL_HOUR + ATTEND_HOURS or jd > int(c["trial_jd"]):
					_verdict_absent(pid, c)
			elif st == "jednani" and Time.get_ticks_msec() - int(c["open_ms"]) > 60000 and _at_court(pid):
				_open_trial(pid, c)     # menu zavřené bez volby → znovu (nejvýš jednou za minutu)


func _at_court(pid: int) -> bool:
	var urad: Place = world.places.get("urad")
	return urad != null and world.player_pos(pid).distance_to(urad.door) <= ATTEND_RADIUS


func _open_trial(pid: int, c: Dictionary) -> void:
	c["stav"] = "jednani"
	c["open_ms"] = Time.get_ticks_msec()
	var pl: Player = world.players.get(pid)
	var cid := String(c["id"])
	var text := "Jednání u soudu (smyšlená budova za hranicí katastru).\nObžaloba čte skutek: %s – %s.\n\nJak se k tomu postavíš?" % [c["drb"], c["name"]]
	var opts := [
		["Přiznat a litovat", func(): choose(pid, cid, "priznat")],
		["Mlčet", func(): choose(pid, cid, "mlcet")],
		["Zapírat", func(): choose(pid, cid, "zapirat")],
	]
	if not bool(c["obhajce"]) and pl != null and pl.money >= int(_tr().get("obhajce_kc", 5000)):
		opts.append(["Vzít si obhájce (%s)" % _thousands(int(_tr().get("obhajce_kc", 5000))), func(): _hire(pid, cid)])
	world.notify(pid, "open_menu", ["Soud – %s" % c["name"], text, opts])


func _hire(pid: int, cid: String) -> void:
	var c := _case(pid, cid)
	var pl: Player = world.players.get(pid)
	if c.is_empty() or pl == null or bool(c["obhajce"]):
		return
	pl.money -= int(_tr().get("obhajce_kc", 5000))
	c["obhajce"] = true
	world.play_sfx(pid, "cash")
	_open_trial(pid, c)


## Volba u jednání: skóre → rozsudek, pak 4 h jednání (zatemnění + posun času).
func choose(pid: int, cid: String, volba: String) -> void:
	var c := _case(pid, cid)
	if c.is_empty() or String(c["stav"]) != "jednani":
		return
	var score := _score(pid, c, volba)
	var s := _sentence(pid, c, score, false)
	await world.blackout(pid, 2.0)
	world.skip_time(pid, TRIAL_HOURS, false)
	_verdict(pid, c, s, volba, false)


func _verdict_absent(pid: int, c: Dictionary) -> void:
	var s := _sentence(pid, c, 0, true)
	_verdict(pid, c, s, "", true)


## Skóre jednání: volba + obhájce + recidiva (záporně) + pověst / karma (polehčující).
func _score(pid: int, c: Dictionary, volba: String) -> int:
	var sc: int = int(SCORE_VOLBA.get(volba, 0))
	if bool(c["obhajce"]):
		sc += SCORE_OBHAJCE
	sc += SCORE_RECIDIVA * mini(_recidiva(pid), SCORE_RECIDIVA_MAX)
	var rep: Reputation = world.reputations.get(pid)
	if rep:
		if rep.score >= 30.0:
			sc += SCORE_POVEST
		elif rep.score <= -30.0:
			sc -= SCORE_POVEST
		if rep.karma >= 30.0:
			sc += SCORE_KARMA
	return sc


func _recidiva(pid: int) -> int:
	var lr: Law.LawRecord = world.law.get(pid)
	return lr.criminal_record().size() if lr else 0


## Rozsudek podle skóre (zjednodušená tabulka – váhy v konstantách, rozmezí v zakon.json → tresty).
func _sentence(pid: int, c: Dictionary, score: int, absent: bool) -> Dictionary:
	var s := {"pokuta": 0, "podm_mes": 0, "nepodm_mes": 0, "opp_h": 0.0, "zakaz_roky": 0.0, "popis": ""}
	var rec := _recidiva(pid)
	var hard: bool = int(c["pokuta_max"]) >= HARD_POKUTA or rec >= HARD_RECIDIVA
	var fine_base := clampi(int(c["pokuta_max"]), int(_tr().get("penize", [10000, 200000])[0]),
		int(_tr().get("penize", [10000, 200000])[1]))
	var traffic: bool = TRAFFIC.has(String(c["oid"]))
	var prob: Dictionary = _probation.get(pid, {})
	if absent:
		s["pokuta"] = _round10(fine_base * ABSENT_FINE_MULT)
		if traffic:
			s["zakaz_roky"] = _rng("zakaz_rizeni_roky", 0.5)
		if hard:
			s["nepodm_mes"] = int(round(_rng("nepodminene_mesice", 0.5)))   # vykoná se po zadržení (otevřený bod)
		else:
			s["podm_mes"] = int(round(_rng("podminka_roky", 0.0) * 12.0))
		s["popis"] = "v nepřítomnosti"
		return s
	var sev := 0.0
	if score >= 4:
		sev = 0.3
		s["podm_mes"] = int(round(_rng("podminka_roky", sev) * 12.0))
		s["pokuta"] = _round10(fine_base * 0.5)
	elif score >= 2:
		sev = 0.5
		s["pokuta"] = _round10(fine_base * 0.8)
		s["opp_h"] = _rng("opp_h", sev)
	elif score >= 0:
		sev = 0.8
		s["pokuta"] = _round10(fine_base)
		s["opp_h"] = _rng("opp_h", sev)
		if hard:
			s["nepodm_mes"] = int(round(_rng("nepodminene_mesice", 0.4)))
	else:
		s["pokuta"] = _round10(fine_base * 1.3)
		if hard:
			s["nepodm_mes"] = int(round(_rng("nepodminene_mesice", 0.8)))
		else:
			s["podm_mes"] = int(round(_rng("podminka_roky", 0.0) * 12.0))
	if traffic:
		s["zakaz_roky"] = _rng("zakaz_rizeni_roky", clampf(0.2 + 0.1 * float(maxi(0, 4 - score)), 0.0, 1.0))
	if not prob.is_empty():     # porušení podmínky: odsedí se podmíněný trest a k tomu nový nepodmíněný
		s["nepodm_mes"] = int(s["nepodm_mes"]) + int(prob.get("podm_mes", 0))
		s["podm_mes"] = 0
		s["popis"] = "podmínka porušena"
	if int(s["nepodm_mes"]) > 0:
		s["opp_h"] = 0.0
		s["podm_mes"] = 0
	return s


func _verdict(pid: int, c: Dictionary, s: Dictionary, volba: String, absent: bool) -> void:
	var jd := _jd()
	var pl: Player = world.players.get(pid)
	c["stav"] = "v_nepritomnosti" if absent else "rozhodnuto"
	var druhy := []
	# peněžitý trest → dluhy (M4.2, kind „trest“ se platí na úřadě)
	var pokuta := int(s["pokuta"])
	if pokuta > 0:
		world.debts.add(pid, "trest", pokuta, jd + Debts.DUE_DAYS, "%s (soud – peněžitý trest)" % c["name"], String(c["oid"]))
		druhy.append("peněžitý trest %s" % _thousands(pokuta))
	# zákaz řízení (Permits, ridicsky) na roky
	var zakaz := float(s["zakaz_roky"])
	if zakaz > 0.0 and world.permits:
		var until := jd + int(round(zakaz * 365.0))
		world.permits.revoke(pid, "ridicsky", "soud: %s" % c["name"], until, false)
		druhy.append("zákaz řízení %d let" % int(ceil(zakaz)))
	# obecně prospěšné práce – evidence (odpracování v dalším kroku, otevřený bod)
	var opp := float(s["opp_h"])
	if opp > 0.0:
		_opp[pid] = {"h_left": opp, "deadline_jd": jd + int(_tr().get("opp_lhuta_dni", 365))}
		druhy.append("OPP %d h (lhůta 1 rok)" % int(round(opp)))
	# podmínka
	var podm_mes := int(s["podm_mes"])
	if podm_mes > 0:
		_probation[pid] = {"do_jd": jd + podm_mes * 30, "podm_mes": podm_mes}
		druhy.append("podmínka %d měs." % podm_mes)
	elif _probation.has(pid) and int(s["nepodm_mes"]) > 0:
		_probation.erase(pid)
	# zápis do rejstříku (rozsudek → rejstřík trestů)
	var nepodm := int(s["nepodm_mes"])
	var druh := "nepodmineny" if nepodm > 0 else ("podminka" if podm_mes > 0 else ("pokuta" if pokuta > 0 else "bez_trestu"))
	_set_record(pid, c, {"druh": druh, "delka": nepodm if nepodm > 0 else podm_mes, "do_jd": jd, "volba": volba})
	var text := "ROZSUDEK: %s (%s)\n%s" % [c["name"], c["par"], ", ".join(PackedStringArray(druhy)) if not druhy.is_empty() else "bez trestu"]
	if absent:
		text = "Soud rozhodl v tvé nepřítomnosti.\n" + text
		if pl:
			pl.wanted_until = maxf(pl.wanted_until, world.clock.minutes + float(_tr().get("zatykac_dni", 30)) * 1440.0)
		text += "\nVydán zatykač – policie tě zadrží, až tě potká."
	world.send_mail(pid, SOURCE, "Rozsudek: %s" % c["name"], text + "\n(Zjednodušená herní simulace – ověřit aktuální znění.)")
	world.notify(pid, "popup", [text, 6.0])
	if nepodm > 0 and not absent:
		await _serve(pid, c, nepodm)
	world.emit_game_event(pid, "verdict", {"druh": druh, "oid": c["oid"]})


## Nástup do vězení: zatemnění, souhrnný časový skok (World.skip_long), propuštění u úřadu se shrnutím.
func _serve(pid: int, c: Dictionary, mesice: int) -> void:
	var pl: Player = world.players.get(pid)
	if pl == null:
		return
	var scale := float(_tr().get("vezeni_meritko", 1.0))
	var days := int(round(float(mesice) * float(_tr().get("vezeni_mesic_dni", 30)) * scale))
	await world.blackout(pid, 3.0)
	world.notify(pid, "show_message", ["Nastupuješ výkon trestu (%d měsíců)." % mesice, 4.0])
	var sum: Dictionary = world.skip_long(pid, days)
	var urad: Place = world.places.get("urad")
	if urad:
		world.interior_clear(pl)
		world.teleport_player(pid, urad.door + Vector3(0, 0.3, 0), pl.yaw)
	var text := "Propuštěn po %d měsících.\n%s" % [mesice, String(sum.get("summary", ""))]
	world.send_mail(pid, SOURCE, "Propuštění z výkonu trestu", text)
	world.notify(pid, "show_message", [text, 9.0])


func _set_record(pid: int, c: Dictionary, rozsudek: Dictionary) -> void:
	if not world.law.has(pid):
		return
	var lr: Law.LawRecord = world.law[pid]
	for r in lr.records:
		var rd := r as Dictionary
		if String(rd.get("id", "")) == String(c["oid"]) and is_equal_approx(float(rd.get("t", -1.0)), float(c["t"])):
			rd["rozsudek"] = rozsudek
			rd["stav"] = "rozsudek"
			return


## Prázdný stav pro hráče bez případů (kvůli rychlému dotazu z Jobs / deníku).
func has_open(pid: int) -> bool:
	for c in _cases.get(pid, []):
		if String(c["stav"]) in ["obvineni", "predvolan", "jednani"]:
			return true
	return false


## Řádky pro deník / P (otevřené případy, podmínka, OPP).
func status_lines(pid: int) -> Array:
	var out := []
	for c in _cases.get(pid, []):
		var st := String(c["stav"])
		if st in ["obvineni", "predvolan", "jednani"]:
			out.append("%s – %s" % [c["name"], {"obvineni": "obviněn", "predvolan": "předvolán", "jednani": "u soudu"}.get(st, st)])
	if _probation.has(pid):
		out.append("Podmínka do %d (herní den)" % int((_probation[pid] as Dictionary).get("do_jd", 0)))
	if _opp.has(pid):
		out.append("OPP zbývá %d h" % int(round(float((_opp[pid] as Dictionary).get("h_left", 0.0)))))
	return out


static func _round10(v: float) -> int:
	return int(roundf(v / 10.0) * 10.0)


static func _thousands(n: int) -> String:
	var s := str(n)
	return s.substr(0, s.length() - 3) + " " + s.substr(s.length() - 3) if s.length() > 3 else s


func to_dict(pid: int) -> Dictionary:
	_ensure(pid)
	return {"cases": (_cases[pid] as Array).duplicate(true), "probation": (_probation.get(pid, {}) as Dictionary).duplicate(true),
		"opp": (_opp.get(pid, {}) as Dictionary).duplicate(true), "seq": int(_seq.get(pid, 0))}


func from_dict(pid: int, d: Dictionary) -> void:
	_cases[pid] = (d.get("cases", []) as Array).duplicate(true)
	_probation[pid] = (d.get("probation", {}) as Dictionary).duplicate(true)
	_opp[pid] = (d.get("opp", {}) as Dictionary).duplicate(true)
	_seq[pid] = int(d.get("seq", (_cases[pid] as Array).size()))
