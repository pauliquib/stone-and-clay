class_name NoiseRegistry
extends RefCounted

## M4.4 část B: hluk a nedělní klid. Registr hlučných činností (`World.noise`). Kdo dělá hluk, slyší ho okolí
## (`World.witness_check` s `hear_r`). Když hluk porušuje noční klid (ze zákona) nebo nedělní klid (vyhláška),
## vznikne přestupek: nahlásí-li ho svědek hned, jinak zapíše nenahlášený čin (odhalí hajný / policie).
## Vesničané, kteří hluk slyšeli a nenahlásili ho, se trochu naštvou (nálada). Hluk v povolenou dobu nic nestojí.
## Zdroje hluku: motorová pila (`Forestry`), další kinda (sekačka, hudba z auta, výstřel) registrem, až budou ve hře.

# ------------------------------------------------------------------ laditelné hodnoty

const NIGHT_FROM := 22.0               # h – noční klid od (ze zákona)
const NIGHT_TO := 6.0                  # h – noční klid do
const DEFAULT_ZAKAZ := [8.0, 20.0]     # h – nedělní klid, výchozí (přepíše `zakazane_hodiny` v zakon.json → vyhlasky)
const COOLDOWN_MIN := 60.0             # herní min. – stejný přestupek ze stejného hluku se neopakuje
const SEV := 0.2                       # závažnost přestupku za hluk
const DISCOVER_P := 0.3                # šance, že nenahlášený hluk někdo odhalí
const MOOD_DROP := 0.02                # o kolik klesne nálada sousedů, kteří hluk slyšeli a nenahlásili

## Hlučné činnosti: `hear_r` (m) – kam je slyšet; `work` = hlučná práce (platí nedělní klid);
## `night` = platí noční klid. Nové činnosti přidej sem (sekačka, hudba z auta, výstřel…).
const KINDS := {
	"motorova_pila": {"nazev": "motorová pila", "hear_r": 300.0, "work": true, "night": false},
	"sekacka": {"nazev": "sekačka na trávu", "hear_r": 60.0, "work": true, "night": false},
	"krovinorez": {"nazev": "křovinořez", "hear_r": 60.0, "work": true, "night": false},
	"hudba_auto": {"nazev": "hlasitá hudba z auta", "hear_r": 80.0, "work": false, "night": true},
	"vystrel": {"nazev": "výstřel", "hear_r": 150.0, "work": false, "night": true},
}

var world: World
var _last := {}                        # "id:přestupek" → herní minuty posledního přestupku (jen v paměti)


func setup(w: World) -> void:
	world = w


## Zákaz nedělního klidu z katalogu (`vyhlasky` → `nedelni_klid` → `zakazane_hodiny`).
func _zakaz_hodiny() -> Array:
	for v in Law.load_catalog().get("vyhlasky", []):
		var d: Dictionary = v
		if String(d.get("id", "")) == "nedelni_klid":
			return d.get("zakazane_hodiny", DEFAULT_ZAKAZ) as Array
	return DEFAULT_ZAKAZ


## Neděle nebo státní svátek.
func rest_day() -> bool:
	return world.clock.weekday() == 6 or world.clock.holiday() != ""


## Přestupek, který by hluk teď porušil (`""` = nic). Čistě podle času a druhu činnosti.
func offense_for(kind: String) -> String:
	var k: Dictionary = KINDS.get(kind, {})
	if k.is_empty() or world == null or world.clock == null:
		return ""
	var h := world.clock.hour()
	if bool(k.get("work", false)) and rest_day():
		var z := _zakaz_hodiny()
		if h >= float(z[0]) and h < float(z[1]):
			return "poruseni_nedelniho_klidu"
	if bool(k.get("night", false)) and (h >= NIGHT_FROM or h < NIGHT_TO):
		return "ruseni_nocniho_klidu"
	return ""


## Hluk `kind` od hráče `id` na `pos`. Vrací přestupek, který vznikl (nebo `""`).
func emit(id: int, kind: String, pos: Vector3) -> String:
	var off := offense_for(kind)
	if off == "":
		return ""
	var now: float = world.clock.minutes
	var key := "%d:%s" % [id, off]
	if _last.has(key) and now >= float(_last[key]) and now - float(_last[key]) < COOLDOWN_MIN:
		return ""
	var r := float(KINDS[kind].get("hear_r", 60.0))
	var cands := world.witness_check(id, pos, "hluk", r * 0.5, r)
	var reported := false
	for w in cands:
		if bool(w.get("reports", false)):
			reported = true
		elif bool(w.get("hears", false)) and w.get("persona") != null:
			(w["persona"] as Persona).add_mood(id, -MOOD_DROP, now)
	_last[key] = now
	var nazev := String(KINDS[kind].get("nazev", kind))
	if reported:
		world.commit_offense(id, off, {"severity": SEV, "hluk": kind})
		world.notify(id, "popup", ["Sousedé slyšeli %s a nahlásili to." % nazev, 3.5])
	else:
		world.add_unreported(id, {"kind": off, "offenses": [off], "pos": [pos.x, pos.y, pos.z], "t": now,
			"value": 0.0, "severity": SEV, "tool": nazev, "discover_p": DISCOVER_P})
		world.notify(id, "show_message", ["Je slyšet %s. Zatím si toho nikdo nevšiml." % nazev, 3.0])
	return off
