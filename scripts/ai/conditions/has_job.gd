## BT podmínka „Má zaměstnání?“ (Fáze 3 – LimboAI): v blackboardu je pod `place_var`
## pozice pracoviště (Vector3; Vector3.INF = zaměstnání nemá → FAILURE). Pozici
## plní `Villager` při startu BT z povolání postavy (`Villager._workplace_pos`).
## Načítá se jen z behavior stromu (`ai/villager_routine.tres`) – vyžaduje addon LimboAI.
extends BTCondition

@export var place_var := "workplace"   # klíč blackboardu s pozicí pracoviště


func _tick(_delta: float) -> Status:
	var p = blackboard.get_var(place_var, Vector3.INF, false)
	return SUCCESS if p is Vector3 and p != Vector3.INF else FAILURE


func _generate_name() -> String:
	return "Má zaměstnání?"
