## BT podmínka „Promile pod limitem“ (Fáze 3 – LimboAI): `Villager.promile` < `limit`.
## Vesničan nemá `BodyState` jako hráč – hladina alkoholu je zjednodušená číselná
## proměnná, roste při „Objednej pivo“ a klesá časem (viz `Villager._physics_process`).
## Načítá se jen z behavior stromu (`ai/villager_routine.tres`) – vyžaduje addon LimboAI.
extends BTCondition

@export var limit := 0.5   # ‰


func _tick(_delta: float) -> Status:
	var v = agent
	if v == null:
		return FAILURE
	return SUCCESS if float(v.get("promile")) < limit else FAILURE


func _generate_name() -> String:
	return "Promile < %g ‰?" % limit
