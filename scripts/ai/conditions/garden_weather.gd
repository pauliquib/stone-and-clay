## BT podmínka „Počasí na zahradu“ (vlna 0d – LimboAI): zahrada se kope jen v sezóně
## (`seasons`, výchozí jaro–podzim), když neprší / nesněží, není sníh na zemi a teplota je
## nad `min_temp` °C. Čte blackboard klíč `world` (World.clock, World.weather).
## Načítá se jen z behavior stromu (`ai/villager_routine.tres`) – vyžaduje addon LimboAI.
extends BTCondition

@export var seasons: Array[String] = ["jaro", "léto", "podzim"]   # `Clock.season()`
@export var min_temp := 3.0       # °C
@export var max_snow := 0.05      # `Weather.snow_cover` nad tuto mez = zahrada zasněžená


func _tick(_delta: float) -> Status:
	var w = blackboard.get_var("world", null, false)
	var c = w.get("clock") if w != null else null
	if c == null or not String(c.season()) in seasons:
		return FAILURE
	var we = w.get("weather")
	if we == null:
		return SUCCESS
	if we.is_raining() or float(we.snow_cover) > max_snow or float(we.temp) < min_temp:
		return FAILURE
	return SUCCESS


func _generate_name() -> String:
	return "Počasí na zahradu?"
