## Generátor behavior stromu vesničana (Fáze 3 – LimboAI): postaví `ai/villager_routine.tres`.
## Spuštění:  godot --headless --path . --script tools/gen_villager_bt.gd
## Strom staví z nativních BT tříd addonu a GDScript tasků ze `scripts/ai/`; po změně
## struktury znovu spustit a výsledek commitnout.
extends SceneTree

const OUT := "res://ai/villager_routine.tres"


func _init() -> void:
	assert(ClassDB.class_exists("BehaviorTree"), "LimboAI GDExtension není načtený")
	var tree = ClassDB.instantiate("BehaviorTree")
	tree.description = "Denní rutina vesničana (Fáze 3): ráno zahrada (za vhodného počasí), přes den práce (je-li místo otevřeno), " + \
		"o víkendu nákup, v pá/so večer hospoda, jinak procházka po cestách. Cíle plní Villager do blackboardu."
	var root = ClassDB.instantiate("BTSelector")
	root.custom_name = "Denní rutina"
	tree.root_task = root

	# ------------------------------------------------ Ranní rutina: 6–8 kopání na zahradě (jen za vhodného počasí a sezóny)
	var rano = ClassDB.instantiate("BTSequence")
	rano.custom_name = "Ranní rutina"
	rano.add_child(_cond("res://scripts/ai/conditions/is_time_of_day.gd",
		{"hour_from": 6.0, "hour_to": 8.0}, "Je 6–8 h?"))
	rano.add_child(_cond("res://scripts/ai/conditions/garden_weather.gd", {}, "Počasí na zahradu?"))
	rano.add_child(_act("res://scripts/ai/actions/go_to_place.gd",
		{"place_var": "garden", "arrive": 1.8}, "Jdi na zahradu"))
	rano.add_child(_act("res://scripts/ai/actions/animate.gd",
		{"anim": "dig", "duration": 20.0}, "Kope na zahradě"))
	root.add_child(rano)

	# ------------------------------------------------ Práce: pracovní den + zaměstnání + pracovní doba + místo otevřeno
	var prace = ClassDB.instantiate("BTSequence")
	prace.custom_name = "Práce"
	prace.add_child(_cond("res://scripts/ai/conditions/is_work_day.gd", {}, "Je pracovní den?"))
	prace.add_child(_cond("res://scripts/ai/conditions/has_job.gd", {}, "Má zaměstnání?"))
	prace.add_child(_cond("res://scripts/ai/conditions/is_time_of_day.gd",
		{"hour_from": 6.5, "hour_to": 16.0}, "Je 6:30–16:00?"))
	prace.add_child(_cond("res://scripts/ai/conditions/place_open.gd",
		{"key_var": "workplace_key"}, "Pracoviště otevřeno?"))
	prace.add_child(_act("res://scripts/ai/actions/go_to_place.gd",
		{"place_var": "workplace", "arrive": 2.5}, "Jdi do práce"))
	prace.add_child(_act("res://scripts/ai/actions/wait.gd",
		{"duration": 30.0, "jitter": 10.0}, "Pracuje na místě"))
	root.add_child(prace)

	# ------------------------------------------------ Víkendový nákup: sobota / neděle / svátek, obchod otevřen, 1× denně
	var nakup = ClassDB.instantiate("BTSequence")
	nakup.custom_name = "Víkendový nákup"
	nakup.add_child(_cond("res://scripts/ai/conditions/is_free_day.gd", {}, "Je víkend / svátek?"))
	nakup.add_child(_cond("res://scripts/ai/conditions/is_time_of_day.gd",
		{"hour_from": 9.0, "hour_to": 18.0}, "Je 9–18 h?"))
	nakup.add_child(_cond("res://scripts/ai/conditions/not_done_today.gd",
		{"day_var": "shop_day"}, "Dnes ještě „shop_day“ ne?"))
	nakup.add_child(_cond("res://scripts/ai/conditions/place_open.gd",
		{"place_key": "obchod"}, "Místo „obchod“ otevřeno?"))
	nakup.add_child(_act("res://scripts/ai/actions/go_to_place.gd",
		{"place_var": "shop", "arrive": 2.5}, "Jdi do obchodu"))
	nakup.add_child(_act("res://scripts/ai/actions/wait.gd",
		{"duration": 15.0, "jitter": 10.0}, "Nakupuje"))
	nakup.add_child(_act("res://scripts/ai/actions/mark_day.gd",
		{"day_var": "shop_day"}, "Označ dnešek „shop_day“"))
	root.add_child(nakup)

	# ------------------------------------------------ Večerní hospoda: pá/so večer, otevřeno, střízlivý → stůl, sedni, pivo
	var hospoda = ClassDB.instantiate("BTSequence")
	hospoda.custom_name = "Večerní hospoda"
	hospoda.add_child(_cond("res://scripts/ai/conditions/is_pub_evening.gd",
		{"days": [4, 5], "hour_from": 17.0, "hour_to": 24.0}, "Je pá/so večer?"))
	hospoda.add_child(_cond("res://scripts/ai/conditions/below_promile.gd",
		{"limit": 0.5}, "Promile < 0,5 ‰?"))
	hospoda.add_child(_cond("res://scripts/ai/conditions/place_open.gd",
		{"place_key": "hospoda"}, "Místo „hospoda“ otevřeno?"))
	hospoda.add_child(_act("res://scripts/ai/actions/go_to_place.gd",
		{"place_var": "pub_table", "arrive": 1.5}, "Jdi ke stolu u hospody"))
	hospoda.add_child(_act("res://scripts/ai/actions/animate.gd",
		{"pose": "sit", "duration": 3.0}, "Sedni ke stolu"))
	hospoda.add_child(_act("res://scripts/ai/actions/animate.gd",
		{"anim": "drink", "pose": "sit", "duration": 10.0, "promile_gain": 0.4}, "Objednej pivo"))
	root.add_child(hospoda)

	# ------------------------------------------------ Posezení: kdo už má dost, sedí u stolu (jinak by kmital pryč a zpět)
	var posezeni = ClassDB.instantiate("BTSequence")
	posezeni.custom_name = "Posezení u stolu"
	posezeni.add_child(_cond("res://scripts/ai/conditions/is_pub_evening.gd",
		{"days": [4, 5], "hour_from": 17.0, "hour_to": 24.0}, "Je pá/so večer?"))
	posezeni.add_child(_cond("res://scripts/ai/conditions/place_open.gd",
		{"place_key": "hospoda"}, "Místo „hospoda“ otevřeno?"))
	posezeni.add_child(_act("res://scripts/ai/actions/go_to_place.gd",
		{"place_var": "pub_table", "arrive": 1.5}, "Jdi ke stolu u hospody"))
	posezeni.add_child(_act("res://scripts/ai/actions/animate.gd",
		{"pose": "sit", "duration": 20.0}, "Sedí a povídá"))
	root.add_child(posezeni)

	# ------------------------------------------------ Fallback: procházka po cestách (jako dřív; i víkend a neděle)
	var prochazka = ClassDB.instantiate("BTSequence")
	prochazka.custom_name = "Procházka"
	prochazka.add_child(_act("res://scripts/ai/actions/random_walk.gd", {}, "Náhodná procházka"))
	root.add_child(prochazka)

	var err := ResourceSaver.save(tree, OUT)
	print("gen_villager_bt: %s → %s" % [OUT, error_string(err)])
	tree.root_task.print_tree(0)
	quit(0 if err == OK else 1)


## Task (`BTTask` potomek) s naším GDScriptem a nastavenými exporty + českým jménem uzlu.
func _task(base: String, script_path: String, props: Dictionary, cname: String):
	var t = ClassDB.instantiate(base)
	var scr: Script = load(script_path)
	assert(scr != null, "chybí skript " + script_path)
	t.set_script(scr)
	for k in props:
		t.set(k, props[k])
	t.custom_name = cname
	return t


func _act(script_path: String, props: Dictionary, cname: String):
	return _task("BTAction", script_path, props, cname)


func _cond(script_path: String, props: Dictionary, cname: String):
	return _task("BTCondition", script_path, props, cname)
