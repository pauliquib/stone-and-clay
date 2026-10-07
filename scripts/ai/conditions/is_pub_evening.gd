## BT podmínka „Večer v hospodě“ (Fáze 3 – LimboAI): vybraný den v týdnu
## (`days`, 0 = pondělí … 6 = neděle – výchozí pá a so) a herní hodina od
## `hour_from` do `hour_to` (stejné rámce jako `Place.HOURS` hospody).
## Čte blackboard klíč `world` (World.clock).
## Načítá se jen z behavior stromu (`ai/villager_routine.tres`) – vyžaduje addon LimboAI.
extends BTCondition

@export var days: Array[int] = [4, 5]   # pátek, sobota
@export var hour_from := 17.0           # herní hodiny od (včetně)
@export var hour_to := 24.0             # herní hodiny do (mimo; hospoda pá/so do 3:00 – večer stačí)


func _tick(_delta: float) -> Status:
	var w = blackboard.get_var("world", null, false)
	var c = w.get("clock") if w != null else null
	if c == null:
		return FAILURE
	if not int(c.weekday()) in days:
		return FAILURE
	var h: float = c.hour()
	return SUCCESS if h >= hour_from and h < minf(hour_to, 24.0) else FAILURE


func _generate_name() -> String:
	return "Večer v hospodě (%g–%g h)?" % [hour_from, hour_to]
