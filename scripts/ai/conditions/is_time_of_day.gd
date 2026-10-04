## BT podmínka „Denní doba“ (Fáze 3 – LimboAI): herní hodina (`Clock.hour`) v rozsahu
## [hour_from, hour_to); rozsah přes půlnoc (např. 22–3) se umí překlopit.
## Čte blackboard klíč `world` (World.clock).
## Načítá se jen z behavior stromu (`ai/villager_routine.tres`) – vyžaduje addon LimboAI.
extends BTCondition

@export var hour_from := 6.0   # herní hodiny od (včetně)
@export var hour_to := 8.0     # herní hodiny do (mimo)


func _tick(_delta: float) -> Status:
	var c = _clock()
	if c == null:
		return FAILURE
	var h: float = c.hour()
	if hour_from <= hour_to:
		return SUCCESS if h >= hour_from and h < hour_to else FAILURE
	return SUCCESS if h >= hour_from or h < hour_to else FAILURE   # rozsah přes půlnoc


func _clock():
	var w = blackboard.get_var("world", null, false)
	return w.get("clock") if w != null else null


func _generate_name() -> String:
	return "Je %g–%g h?" % [hour_from, hour_to]
