## BT podmínka „Dnes ještě ne“ (vlna 0d – LimboAI): v blackboardu pod `day_var` je den (juliánské číslo
## `Clock.jd`), kdy se činnost naposledy udělala (`mark_day.gd`). SUCCESS, když to dnes ještě nebylo –
## brání tomu, aby vesničan chodil nakupovat pořád dokola.
## Načítá se jen z behavior stromu (`ai/villager_routine.tres`) – vyžaduje addon LimboAI.
extends BTCondition

@export var day_var := "shop_day"   # klíč blackboardu s číslem dne poslední činnosti


func _tick(_delta: float) -> Status:
	var w = blackboard.get_var("world", null, false)
	var c = w.get("clock") if w != null else null
	if c == null:
		return FAILURE
	return SUCCESS if int(blackboard.get_var(day_var, -1, false)) != int(c.jd()) else FAILURE


func _generate_name() -> String:
	return "Dnes ještě „%s“ ne?" % day_var
