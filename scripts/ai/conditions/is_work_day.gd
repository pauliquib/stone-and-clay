## BT podmínka „Pracovní den“ (Fáze 3 – LimboAI): pondělí–pátek (`Clock.weekday` 0–4)
## a není státní svátek (`Clock.holiday`) – stejná pravidla volna jako u míst (`Place`).
## Čte blackboard klíč `world` (World.clock).
## Načítá se jen z behavior stromu (`ai/villager_routine.tres`) – vyžaduje addon LimboAI.
extends BTCondition


func _tick(_delta: float) -> Status:
	var w = blackboard.get_var("world", null, false)
	var c = w.get("clock") if w != null else null
	if c == null:
		return FAILURE
	if int(c.weekday()) >= 5:        # sobota, neděle
		return FAILURE
	if String(c.holiday()) != "":    # státní svátek = volno
		return FAILURE
	return SUCCESS


func _generate_name() -> String:
	return "Je pracovní den?"
