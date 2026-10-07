## BT podmínka „Volný den“ (vlna 0d – LimboAI): sobota, neděle nebo státní svátek
## (opak `is_work_day.gd`). Čte blackboard klíč `world` (World.clock).
## Načítá se jen z behavior stromu (`ai/villager_routine.tres`) – vyžaduje addon LimboAI.
extends BTCondition


func _tick(_delta: float) -> Status:
	var w = blackboard.get_var("world", null, false)
	var c = w.get("clock") if w != null else null
	if c == null:
		return FAILURE
	if int(c.weekday()) >= 5 or String(c.holiday()) != "":
		return SUCCESS
	return FAILURE


func _generate_name() -> String:
	return "Je víkend / svátek?"
