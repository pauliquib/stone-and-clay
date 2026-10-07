## Registry oprávnění a dokladů hráčů (M6.1, rozšířen M4.1): registrace provozovatele dronu, kvalifikace A1/A3,
## létací průkazy, řidičský průkaz se skupinami (M4.1), budoucí zbrojní / lovecký / rybářský doklad (M4.6).
## Server (`World`) drží stav per hráč: `grants[pid][kind] = {"no", "jd", "sub": {skupina: jd},
## "valid_until": jd | -1, "revoked": {} | {"reason", "jd", "until_jd", "retest"}}`.
## Kontrola jde přes `World.has_permit(id, kind)` → `Permits.has` (+ ladicí `_cheat_permits`).
## Ukládání `to_dict(pid)` / `from_dict(pid, d)` – klíč `permits` v `SaveGame`. Starý save bez `ridicsky` dostane B + AM + A.
class_name Permits
extends Node

## Známé druhy oprávnění: id → [název, vydavatel, poznámka pro UI]. Nový druh VŽDY sem (jinak se při načtení zahodí).
const KINDS := {
	"dron_provozovatel": ["Registrace provozovatele UAS", "ÚVL – portál bezpilotních letů",
		"Bezplatná registrace; registrační číslo se vyznačuje na dronu."],
	"dron_a1a3": ["Osvědčení pilota UAS – A1/A3", "ÚVL – online zkouška",
		"Potřebné pro drony nad 250 g a pro let v blízkosti lidí."],
	# M4.1 řidičský průkaz – skupiny (sub) přidává autoškola; odebrání za 12 bodů → revoked
	"ridicsky": ["Řidičský průkaz", "obecní úřad obce s rozšířenou působností (smyšlený)",
		"Skupiny: B (osobní), AM (moped), A1, A2, A (motorky), T (traktor). Zákaz za 12 bodů = nutné přezkoušení."],
	# M6.4 paramotor (sportovní létající zařízení – zjednodušeně)
	"pilot_pg_motor": ["Pilotní průkaz paramotoru (SLZ)", "ÚVL – létací škola",
		"Teorie (eTest „paramotor“) + 5 výcvikových vzletů s instruktorem; výcvik 35 000 Kč."],
	"pg_registrace": ["Registrace paramotoru (poznávací značka)", "ÚVL – evidence SLZ",
		"Registrační značka se vyznačuje na křídle."],
	"pg_pojisteni": ["Pojištění odpovědnosti paramotoru", "Pojišťovna (roční)",
		"Povinná výbava provozovatele; ve hře roční platba 1 200 Kč."],
	# M6.5 motorové rogalo / ultralehké letadlo (ULL – zjednodušeně, LAA ČR)
	"pilot_ul": ["Pilotní průkaz ULL (rogalo)", "ÚVL – létací škola",
		"Teorie (eTest „ultralehké“) + 10 výcvikových letů s instruktorem; výcvik 75 000 Kč."],
	"ul_registrace": ["Registrace UL stroje (poznávací značka)", "ÚVL – evidence UL",
		"Registrační značka se vyznačuje na vozíku."],
	"ul_pojisteni": ["Pojištění odpovědnosti UL stroje", "Pojišťovna (roční)",
		"Povinná výbava provozovatele; ve hře roční platba 3 000 Kč."],
	# M4.6 doklady (udělí se až v M4.4 / M4.6; druhy jsou tu, aby se uložené doklady nezahodily)
	"kaceni": ["Povolení ke kácení dřevin", "obec (smyšlený úřad)", "Pro kácení vyznačených stromů mimo lesní práci."],
	"zbrojni": ["Zbrojní průkaz", "policie (smyšlený odbor)", "Držení zbraní; zkouška a zdravotní posudek."],
	"lovecky_listek": ["Lovecký lístek", "myslivecký spolek (smyšlený)", "Zkouška z myslivosti."],
	"povolenka_lov": ["Povolenka k lovu", "myslivecký spolek (smyšlený)", "Platí na honitbě v roce."],
	"rybarsky_listek": ["Rybářský lístek", "rybářský spolek (smyšlený)", "Zkouška z rybolovu."],
	"povolenka_rybolov": ["Povolenka k rybolovu", "rybářský spolek (smyšlený)", "Platí na revíru v roce."],
}

## Skupiny řidičáku, které jedna skupina zahrnuje (zjednodušeně; ověřit podle 361/2000 Sb.).
const ZAHRNUJE := {"B": ["AM"], "A": ["A2", "A1"], "A2": ["A1"]}

var world: World
var grants := {}                      # pid → {kind: {...}} (viz hlavička)


func setup(w: World) -> void:
	world = w
	name = "Permits"


## Nová hra: řidičák B + AM (moped). Starý save řeší `from_dict`.
func add_player(pid: int) -> void:
	if not grants.has(pid):
		grants[pid] = {}
	if not has(pid, "ridicsky"):
		grant(pid, "ridicsky", "RP-%04d" % pid, "B")
		grant(pid, "ridicsky", "", "AM")


func _g(pid: int) -> Dictionary:
	if not grants.has(pid):
		grants[pid] = {}
	return grants[pid]


func _now() -> int:
	return world.clock.jd() if world and world.clock else 0


## Statická pomoc: drží-li skupina `drzi` i skupinu `potreba` (přímo nebo přes ZAHRNUJE).
static func skupina_kryje(drzi: String, potreba: String) -> bool:
	return drzi == potreba or (ZAHRNUJE.get(drzi, []) as Array).has(potreba)


## Má hráč platné oprávnění `kind`? Odebrané (revoked) se nepočítá. `sub` = skupina (řidičák) – musí ji držet
## přímo nebo přes zahrnutí. Bez `sub` u řidičáku stačí aspoň jedna skupina.
func has(pid: int, kind: String, sub := "") -> bool:
	var e: Dictionary = _g(pid).get(kind, {})
	if e.is_empty() or not _active_revoke(e).is_empty():
		return false
	var vu := int(e.get("valid_until", -1))
	if vu >= 0 and _now() > vu:
		return false                  # povolenka s platností (M4.6) prošla
	if sub == "":
		return kind != "ridicsky" or not (e.get("sub", {}) as Dictionary).is_empty()
	for g in (e.get("sub", {}) as Dictionary):
		if skupina_kryje(String(g), sub):
			return true
	return false


## Udělí oprávnění (registrace na ÚVL, složený test). `no` = evidenční číslo. `sub` = skupina (řidičák).
## Druhé volání se skupinou skupinu jen přidá. Bez `sub` u existujícího druhu nedělá nic.
func grant(pid: int, kind: String, no := "", sub := "", valid_until := -1) -> void:
	var g := _g(pid)
	if not g.has(kind):
		g[kind] = {"no": no, "jd": _now(), "sub": {}, "valid_until": valid_until, "revoked": {}}
	var e: Dictionary = g[kind]
	if sub != "" and not (e["sub"] as Dictionary).has(sub):
		(e["sub"] as Dictionary)[sub] = _now()


## Vydá nebo prodlouží doklad s platností do `until_jd` (povolenky k lovu a rybolovu, M4.6). Existující doklad jen dostane nový termín.
func renew(pid: int, kind: String, until_jd: int, no := "") -> void:
	if not _g(pid).has(kind):
		grant(pid, kind, no, "", until_jd)
		return
	(_g(pid)[kind] as Dictionary)["valid_until"] = until_jd


## Odebere doklad (12 bodů, zákaz řízení). `until_jd` = do kdy platí zákaz (-1 = natrvalo), `retest` = nutné přezkoušení.
func revoke(pid: int, kind: String, reason: String, until_jd := -1, retest := false) -> void:
	var e: Dictionary = _g(pid).get(kind, {})
	if e.is_empty():
		return
	e["revoked"] = {"reason": reason, "jd": _now(), "until_jd": until_jd, "retest": retest}


## Vrátí odebraný doklad (po přezkoušení / rozhodnutí úřadu).
func restore(pid: int, kind: String) -> void:
	var e: Dictionary = _g(pid).get(kind, {})
	if not e.is_empty():
		e["revoked"] = {}


## Důvod odebrání: {reason, jd, until_jd, retest} nebo prázdný slovník (platný / neexistuje / zákaz už vypršel).
func is_revoked(pid: int, kind: String) -> Dictionary:
	return _active_revoke(_g(pid).get(kind, {}))


## Platné odebrání dokladu. Zákaz s termínem a bez přezkoušení (soud, M4.3) po `until_jd` sám skončí;
## odebrání s přezkoušením (12 bodů) trvá, dokud ho nevrátí autoškola (`restore`).
func _active_revoke(e: Dictionary) -> Dictionary:
	var rv: Dictionary = e.get("revoked", {})
	if rv.is_empty() or bool(rv.get("retest", false)):
		return rv
	var until := int(rv.get("until_jd", -1))
	if until >= 0 and _now() > until:
		return {}
	return rv


## Skupiny, které hráč u druhu drží (řidičák: B, AM…).
func subs(pid: int, kind: String) -> Array:
	return ((_g(pid).get(kind, {}) as Dictionary).get("sub", {}) as Dictionary).keys()


## Evidenční číslo dokladu (dron: vyznačuje se na trupu).
func number(pid: int, kind: String) -> String:
	return String((_g(pid).get(kind, {}) as Dictionary).get("no", ""))


## Datum udělení (herní den) nebo -1.
func granted_day(pid: int, kind: String) -> int:
	return int((_g(pid).get(kind, {}) as Dictionary).get("jd", -1))


## Přehled dokladů pro panel P / deník: [{kind, name, no, jd, subs, revoked}] jen pro existující doklady.
func list(pid: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for k in KINDS:
		var e: Dictionary = _g(pid).get(k, {})
		if e.is_empty():
			continue
		out.append({"kind": k, "name": KINDS[k][0], "no": String(e.get("no", "")), "jd": int(e.get("jd", -1)),
			"subs": subs(pid, k), "revoked": _active_revoke(e).duplicate(), "valid_until": int(e.get("valid_until", -1))})
	return out


## Přehled dokladů do deníku / obrazovek (textově).
func describe(pid: int) -> String:
	var out := ""
	for d in list(pid):
		var line := "· %s%s" % [d["name"], " (%s)" % d["no"] if String(d["no"]) != "" else ""]
		if not (d["subs"] as Array).is_empty():
			line += " – skupiny %s" % ", ".join(PackedStringArray(d["subs"]))
		if not (d["revoked"] as Dictionary).is_empty():
			line += " – odebráno, nutné přezkoušení" if bool(d["revoked"].get("retest", false)) else " – odebráno"
		out += line + "\n"
	return out


func to_dict(pid: int) -> Dictionary:
	return (_g(pid) as Dictionary).duplicate(true)


## Načtení. Starý save bez klíče `ridicsky` (před M4.1) dostane B + AM + A, aby motorka nevedla k přestupku.
## Odebraný řidičák se ukládá jako položka s `revoked`, takže ho migrace nevrátí.
func from_dict(pid: int, d: Dictionary) -> void:
	grants[pid] = {}
	for k in d:
		if not KINDS.has(String(k)):
			continue
		var e: Dictionary = d[k]
		var sub := {}
		for s in (e.get("sub", {}) as Dictionary):
			sub[String(s)] = int(e["sub"][s])
		grants[pid][String(k)] = {"no": String(e.get("no", "")), "jd": int(e.get("jd", 0)), "sub": sub,
			"valid_until": int(e.get("valid_until", -1)), "revoked": (e.get("revoked", {}) as Dictionary).duplicate(true)}
	if not d.has("ridicsky"):
		grant(pid, "ridicsky", "RP-%04d" % pid, "B")
		grant(pid, "ridicsky", "", "AM")
		grant(pid, "ridicsky", "", "A")
