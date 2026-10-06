## BT akce „Označ dnešek“ (vlna 0d – LimboAI): zapíše do blackboardu pod `day_var` dnešní den
## (`Clock.jd`) – viz podmínka `not_done_today.gd`. Vždy SUCCESS.
## Načítá se jen z behavior stromu (`ai/villager_routine.tres`) – vyžaduje addon LimboAI.
extends BTAction

@export var day_var := "shop_day"   # klíč blackboardu


func _tick(_delta: float) -> Status:
	var w = blackboard.get_var("world", null, false)
	var c = w.get("clock") if w != null else null
	if c != null:
		blackboard.set_var(day_var, int(c.jd()))
	return SUCCESS


func _generate_name() -> String:
	return "Označ dnešek „%s“" % day_var
