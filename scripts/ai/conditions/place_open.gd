## BT podmínka „Místo otevřeno“ (vlna 0d – LimboAI): místo `World.places[klíč]` má právě teď otevřeno
## (`Place.is_open` – hodiny, víkend, svátek, událost v obci). Klíč buď napevno (`place_key`), nebo
## z blackboardu (`key_var`, např. „workplace_key“ plní `Villager._bt_fill_vars` podle povolání).
## Neexistující místo nebo prázdný klíč = FAILURE.
## Načítá se jen z behavior stromu (`ai/villager_routine.tres`) – vyžaduje addon LimboAI.
extends BTCondition

@export var place_key := ""    # klíč místa (`World.places`), např. "obchod", "hospoda"
@export var key_var := ""      # nebo klíč blackboardu, pod kterým je String s klíčem místa


func _tick(_delta: float) -> Status:
	var w = blackboard.get_var("world", null, false)
	if w == null:
		return FAILURE
	var k := place_key
	if key_var != "":
		k = String(blackboard.get_var(key_var, "", false))
	var places = w.get("places")
	var c = w.get("clock")
	if k == "" or not (places is Dictionary) or not places.has(k) or c == null:
		return FAILURE
	var pl = places[k]
	if pl == null or not is_instance_valid(pl):
		return FAILURE
	return SUCCESS if pl.is_open(float(c.hour())) else FAILURE


func _generate_name() -> String:
	return "Místo „%s“ otevřeno?" % (place_key if place_key != "" else key_var)
