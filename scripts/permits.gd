## Registry oprávnění a dokladů hráčů (M6.1): registrace provozovatele dronu, kvalifikace A1/A3.
## Zatím malé – stejný mechanismus přejme později doklady M4.6 (zbrojní, lovecký, rybářský lístek,
## řidičák). Server (`World`) drží stav per hráč: `grants[pid][kind] = {"no": registrační číslo, "jd": den}`.
## Kontrola jde přes `World.has_permit(id, kind)` → `Permits.has` (+ ladicí `_cheat_permits`).
## Ukládání `to_dict(pid)` / `from_dict(pid, d)` – klíč `permits` v `SaveGame` (starý save bez klíče = žádná oprávnění).
class_name Permits
extends Node

## Známé druhy oprávnění: id → [název, vydavatel, poznámka pro UI].
const KINDS := {
	"dron_provozovatel": ["Registrace provozovatele UAS", "ÚVL – portál bezpilotních letů",
		"Bezplatná registrace; registrační číslo se vyznačuje na dronu."],
	"dron_a1a3": ["Osvědčení pilota UAS – A1/A3", "ÚVL – online zkouška",
		"Potřebné pro drony nad 250 g a pro let v blízkosti lidí."],
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
}

var world: World
var grants := {}                      # pid → {kind: {"no": String, "jd": int}}


func setup(w: World) -> void:
	world = w
	name = "Permits"


func add_player(pid: int) -> void:
	if not grants.has(pid):
		grants[pid] = {}


func _g(pid: int) -> Dictionary:
	if not grants.has(pid):
		grants[pid] = {}
	return grants[pid]


## Má hráč oprávnění `kind`? (Volá `World.has_permit` – cheat se řeší tam.)
func has(pid: int, kind: String) -> bool:
	return _g(pid).has(kind)


## Udělí oprávnění (registrace na ÚVL, složený test). `no` = registrační / evidenční číslo.
func grant(pid: int, kind: String, no := "") -> void:
	var g := _g(pid)
	if g.has(kind):
		return
	g[kind] = {"no": no, "jd": world.clock.jd() if world.clock else 0}


## Evidenční číslo dokladu (dron: vyznačuje se na trupu).
func number(pid: int, kind: String) -> String:
	return String((_g(pid).get(kind, {}) as Dictionary).get("no", ""))


## Datum udělení (herní den) nebo -1.
func granted_day(pid: int, kind: String) -> int:
	return int((_g(pid).get(kind, {}) as Dictionary).get("jd", -1))


## Přehled dokladů do deníku / obrazovek.
func describe(pid: int) -> String:
	var out := ""
	for k in KINDS:
		var e: Dictionary = _g(pid).get(k, {})
		if e.is_empty():
			continue
		var t: Array = KINDS[k]
		out += "· %s%s\n" % [t[0], " (%s)" % e["no"] if String(e.get("no", "")) != "" else ""]
	return out


func to_dict(pid: int) -> Dictionary:
	return (_g(pid) as Dictionary).duplicate(true)


## Načtení (starý save bez klíče = žádná oprávnění).
func from_dict(pid: int, d: Dictionary) -> void:
	grants[pid] = {}
	for k in d:
		if not KINDS.has(String(k)):
			continue
		var e: Dictionary = d[k]
		grants[pid][String(k)] = {"no": String(e.get("no", "")), "jd": int(e.get("jd", 0))}
