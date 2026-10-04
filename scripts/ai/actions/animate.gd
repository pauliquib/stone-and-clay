## BT akce „Přehraj animaci“ (Fáze 3 – LimboAI): na Humanoidu vesničana spustí
## `Humanoid.start_action(anim)` (dig, drink, smoke, eat, vomit…), případně nastaví
## pózu (`pose` = "sit"/"lie" – sezení u stolu). SUCCESS po `duration` reálných s.
## `promile_gain` přičte vesničanovi promile při startu akce (pití piva v hospodě –
## vesničan nemá `BodyState` jako hráč, hladina je zjednodušená, viz `Villager.promile`).
## Načítá se jen z behavior stromu (`ai/villager_routine.tres`) – vyžaduje addon LimboAI.
extends BTAction

@export var anim := ""           # `Humanoid.start_action`: "", "dig", "drink", "smoke", "eat"…
@export var pose := ""           # póza `Humanoid.pose` během akce: "", "sit", "lie"
@export var duration := 10.0     # reálné sekundy
@export var promile_gain := 0.0  # ‰ přičtené vesničanovi při _enter (objednané pivo)


func _enter() -> void:
	var v = agent
	if v == null or v._visual == null:
		return
	if anim != "":
		v._visual.start_action(anim)
	if pose != "":
		v._visual.pose = pose
	if promile_gain != 0.0:
		v.promile += promile_gain


func _tick(_delta: float) -> Status:
	return SUCCESS if get_elapsed_time() >= duration else RUNNING


func _exit() -> void:
	var v = agent
	if v == null or v._visual == null:
		return
	if anim != "":
		v._visual.stop_action()
	if pose != "" and v._visual.pose == pose:
		v._visual.pose = "stand"


func _generate_name() -> String:
	return "Animace „%s“" % (anim if anim != "" else pose)
