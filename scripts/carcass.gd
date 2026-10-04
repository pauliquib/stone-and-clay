## Ulovená (mrtvá) zvěř ve světě – záznam pro `Hunting` (M2.9). Tělo samo je mrtvý `Animal` (`node`, model leží na boku),
## tady je jen to, co hra o úlovku potřebuje: druh, hmotnost, čas úmrtí, legálnost a stav zpracování.
## Není v inventáři; hráč ji nese na rameni (`Hunting.lift`), vyvrhne (`Hunting._gut`) a zpracuje doma (`Hunting._process_home`).
## M2.10 (`Cargo`) použije `cargo_kind`, `weight_kg()` a `Hunting.carried_by(id)` / `Hunting.lift` / `Hunting.drop` / `Hunting.release_carried`;
## úlovek naložený na vozík / do auta má `stored` a ukládá ho `Cargo` (ne `Hunting.to_dict`).
class_name Carcass
extends RefCounted

var species := ""
var male := false
var young := false
var live_kg := 0.0                # živá hmotnost (kg)
var died_min := 0.0               # herní minuta úmrtí (`Clock.minutes`)
var legal := true                 # legální úlovek (puška, doklady, doba lovu …) – `World.is_legal_hunt`
var gutted := false               # vyvrženo (hmotnost −20 %, maso se nekazí tak rychle)
var gutted_min := 0.0
var spoiled := false              # maso se znehodnotilo
var pos := Vector3.ZERO
var owner_id := 0                 # kdo zvíře zastřelil (0 = nikdo: sražená autem, přivlastněná)
var weapon := ""
var reported := false             # za tenhle kus už byl udělen přestupek (svědek)
var found := false                # hráč k postřelenému zvířeti došel (jinak karma −5 „postřelené zvíře trpí“)
var unfound_penalty := false      # zvíře zhynulo na následky postřelení mimo hráčův dohled
var carried_by := 0               # id hráče, který ho nese (0 = leží)
var stored := ""                  # M2.10: "" = leží ve světě, jinak uložen v nákladu: "vozik" | "kufr" | "korba" | "nosic" (spravuje `Cargo`)
var cargo_kind := ""              # druh nákladu pro M2.10 (`Cargo`): "zajic", "srnec", "divocak"
var node: Animal                  # mrtvé tělo ve světě (může zmizet)


## Hmotnost úlovku (kg): vyvržený kus je o 20 % lehčí.
func weight_kg(gut_k := 0.8) -> float:
	return live_kg * (gut_k if gutted else 1.0)


## Stáří v herních hodinách.
func age_h(now_min: float) -> float:
	return maxf(now_min - died_min, 0.0) / 60.0


func to_dict() -> Dictionary:
	return {"species": species, "male": male, "young": young, "live_kg": live_kg, "died_min": died_min, "legal": legal,
		"gutted": gutted, "gutted_min": gutted_min, "spoiled": spoiled, "pos": [pos.x, pos.y, pos.z], "owner": owner_id,
		"weapon": weapon, "reported": reported, "found": found, "unfound_penalty": unfound_penalty, "cargo": cargo_kind}


static func from_dict(d: Dictionary) -> Carcass:
	var c := Carcass.new()
	c.species = String(d.get("species", "srnec"))
	c.male = bool(d.get("male", false))
	c.young = bool(d.get("young", false))
	c.live_kg = float(d.get("live_kg", 20.0))
	c.died_min = float(d.get("died_min", 0.0))
	c.legal = bool(d.get("legal", true))
	c.gutted = bool(d.get("gutted", false))
	c.gutted_min = float(d.get("gutted_min", 0.0))
	c.spoiled = bool(d.get("spoiled", false))
	var a: Array = d.get("pos", [0, 0, 0])
	c.pos = Vector3(float(a[0]), float(a[1]), float(a[2]))
	c.owner_id = int(d.get("owner", 0))
	c.weapon = String(d.get("weapon", ""))
	c.reported = bool(d.get("reported", false))
	c.found = bool(d.get("found", false))
	c.unfound_penalty = bool(d.get("unfound_penalty", false))
	c.cargo_kind = String(d.get("cargo", ""))
	return c
