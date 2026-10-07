## BT akce „Počkej“ (Fáze 3 – LimboAI): vesničan stojí na místě `duration` reálných
## sekund (+ náhodný `jitter`). SUCCESS po uplynutí, RUNNING během čekání.
## Načítá se jen z behavior stromu (`ai/villager_routine.tres`) – vyžaduje addon LimboAI.
extends BTAction

@export var duration := 20.0   # reálné sekundy (herní čas běží 30× rychleji)
@export var jitter := 0.0      # náhodný příděl 0..jitter s navíc

var _wait := 0.0


func _enter() -> void:
	_wait = duration + (randf() * jitter if jitter > 0.0 else 0.0)


func _tick(_delta: float) -> Status:
	return SUCCESS if get_elapsed_time() >= _wait else RUNNING


func _generate_name() -> String:
	return "Počkej %.0f s" % duration
