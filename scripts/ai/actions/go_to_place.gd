## BT akce „Jdi na místo“ (Fáze 3 – LimboAI): cílovou pozici čte z blackboardu
## (`place_var` – klíč s Vector3 pozicí; Vector3.INF = cíl neexistuje → FAILURE).
## Vesničan jde po silnicích a cestách (`Villager.move_to` – trasa přes `RoadGraph` A*);
## SUCCESS při dosažení do `arrive` metrů, RUNNING cestou.
## Načítá se jen z behavior stromu (`ai/villager_routine.tres`) – vyžaduje addon LimboAI.
extends BTAction

@export var place_var := "target"   # klíč blackboardu s cílovou pozicí (Vector3)
@export var arrive := 2.0           # vzdálenost dosažení cíle (m)


func _tick(_delta: float) -> Status:
	var v = agent
	var t = blackboard.get_var(place_var, Vector3.INF, false)
	if v == null or not (t is Vector3) or t == Vector3.INF:
		return FAILURE
	if Vector2(t.x - v.global_position.x, t.z - v.global_position.z).length() < arrive:
		return SUCCESS
	v.move_to(t)
	return RUNNING


func _generate_name() -> String:
	return "Jdi na „%s“" % String(place_var)
