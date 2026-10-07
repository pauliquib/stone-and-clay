## BT akce „Náhodná procházka“ (Fáze 3 – LimboAI): fallback větev stromu – zruší
## cíl z behavior stromu (`Villager.clear_target`) a vesničan dál chodí po silničním
## grafu jako před LimboAI (`Villager._goal`/`_advance`). Vrací SUCCESS (ne RUNNING):
## BTSelector si pamatuje index běžícího potomka a začíná od něj – věčné RUNNING
## poslední větve by navždy vypnulo přepočet podmínek rutin (strom by „zamkl“ na
## procházce). SUCCESS → selektor se resetuje a další tick znovu zkusí rutiny.
## Načítá se jen z behavior stromu (`ai/villager_routine.tres`) – vyžaduje addon LimboAI.
extends BTAction


func _tick(_delta: float) -> Status:
	var v = agent
	if v == null:
		return FAILURE
	v.clear_target()
	return SUCCESS


func _generate_name() -> String:
	return "Náhodná procházka po cestách"
