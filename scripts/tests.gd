## Automatické testy spouštěné z příkazové řádky (viz main.gd). `g` je hlavní scéna:
## g.world (World – simulace), g.client (LocalClient – HUD, vstup); testuje se hráč s id 1.
##   --testmove   chůze, sprint (vstup přes klávesnici → InputState)
##   --bottest    vesničané a psi se hýbou
##   --drinktest  křivky promile pro různé scénáře (nalačno / s jídlem / obezita)
##   --cartest    zrychlení 0–100 km/h, brzdná dráha, AI jízda po trase
##   --questtest  všech 6 úkolů: splnění i selhání přes skutečné nabídky míst, nákupy a jízdu
##   --traffictest  provoz v obci několik minut: AI auta nesmí viset (křižovatky, překážky)
##   --faunatest  zvěř (srnci, divočáci, zajíc: pastva → pozornost → útěk), kůň (chody, zastavení),
##                počasí a kalendář; volitelně --shotdir=adresář pro snímky u zvířat a z koně
##   --naturesynctest  loopback příprava přírody na multiplayer (bez sítě): druhá „klientská“ Fauna dostává
##                     10× za s snímky zvěře a hejn z autoritativní, 60 s simulace s vyplašením zvěře; výpis
##                     odchylek poloh, velikosti snímku a round-trip Clock / Weather
##   --weathertest  počasí a hratelnost: přilnavost povrchů, brzdná dráha auta (měřená),
##                  expozice těla, trakce chůze, AI opatrnost, předpověď
##   --villagertest  vesničan s behavior stromem (Fáze 3, LimboAI): blackboard z herních dat,
##                  ráno zahrada + kopání, pátek večer stůl v hospodě + pivo; bez addonu fallback
class_name Tests
extends RefCounted


## Testovaný hráč (lokální, id 1).
static func _pl(g: Node) -> Player:
	return g.world.players[1]


static func bot_test(g: Node) -> void:
	var bots: Array = g.world.bots_root.get_children()
	var p0 := []
	for b in bots:
		p0.append(b.global_position)
	await g.get_tree().create_timer(15.0).timeout
	var moved := 0
	for i in bots.size():
		var d: float = bots[i].global_position.distance_to(p0[i])
		if d > 3.0:
			moved += 1
	print("BOTS moved: %d / %d" % [moved, bots.size()])
	g.get_tree().quit()


## Automatický test pohybu: chůze, sprint, skok, skluz – vypíše rychlosti a výšky.
static func move_test(g: Node) -> void:
	var player := _pl(g)
	await g.get_tree().create_timer(1.0).timeout
	var log := func(tag: String):
		var v := player.velocity
		print("%-10s pos=(%.1f, %.2f, %.1f) hspeed=%.2f vy=%.2f floor=%s stamina=%.2f" % [tag,
			player.global_position.x, player.global_position.y, player.global_position.z,
			Vector2(v.x, v.z).length(), v.y, player.is_on_floor(), player.stamina])
	player.yaw += PI
	log.call("start")
	Input.action_press("move_forward")
	for i in 4:
		await g.get_tree().create_timer(0.25).timeout
		log.call("walk")
	Input.action_press("sprint")
	for i in 6:
		await g.get_tree().create_timer(0.25).timeout
		log.call("sprint")
	Input.action_release("sprint")
	Input.action_release("move_forward")
	await g.get_tree().create_timer(0.5).timeout
	g.get_tree().quit()


static func drink_test(g: Node) -> void:
	var scenarios := [
		["5 piv za 2 h nalačno", 0, 82.0],
		["5 piv za 2 h + guláš předem", 980, 82.0],
		["5 piv za 2 h nalačno, 120 kg", 0, 120.0],
	]
	for sc in scenarios:
		var b := BodyState.new()
		b.weight = sc[2]
		if sc[1] > 0:
			b.stomach_kcal = sc[1]
		var line := "%-34s" % sc[0]
		var peak := 0.0
		var t_peak := 0.0
		var sober_h := -1.0
		for step in 12 * 12:   # 12 h po 5 min
			var t := step * 5.0 / 60.0
			if step % 6 == 0 and step <= 24:
				b.drink("pivo_cepovane", 500.0)
			b.update(5.0 / 60.0, 0.0)
			var p := b.promile()
			if p > peak:
				peak = p
				t_peak = t
			if step % 12 == 11:
				line += " %4.2f" % p
			if sober_h < 0.0 and step > 30 and p < 0.01:
				sober_h = t
		print("%s | vrchol %.2f ‰ v %.1f h | střízlivý za %.1f h | hmotnost %.1f kg" % [line, peak, t_peak, sober_h, b.weight])
		b.free()
	# panák na lačno vs. po jídle
	var b2 := BodyState.new()
	b2.drink("panak_slivovice", 50.0)
	var p10 := 0.0
	for i in 6:
		b2.update(5.0 / 60.0, 0.0)
		if i == 1:
			p10 = b2.promile()
	print("panák slivovice nalačno: po 10 min %.2f ‰, po 30 min %.2f ‰" % [p10, b2.promile()])
	b2.free()
	g.get_tree().quit()


## Výstup z auta: hráč nastoupí, popojede, zastaví a vystoupí – vypíše polohu, zdraví a stav auta.
static func exit_test(g: Node) -> void:
	var p: Player = _pl(g)
	var c: Car = g.world.traffic.car_of(1)
	await g.get_tree().create_timer(1.0).timeout
	g.world.enter_car(1, c)
	Input.action_press("move_forward")
	await g.get_tree().create_timer(1.5).timeout
	Input.action_release("move_forward")
	Input.action_press("move_back")
	await g.get_tree().create_timer(1.2).timeout
	Input.action_release("move_back")
	for round in 2:
		var h0 := p.body.health
		print("EXIT před: auto %s rychlost %.2f  hráč %s  zdraví %.1f" % [c.global_position, c.speed, p.global_position, h0])
		g.world.player_action(1, "car_enter")
		for i in 12:
			await g.get_tree().create_timer(0.25).timeout
			print("  t=%.2f hráč %s v=%s floor=%s zdraví %.1f | auto %s v=%.2f dmg=%.0f  vzdál %.2f" % [i * 0.25 + 0.25,
				p.global_position, p.velocity, p.is_on_floor(), p.body.health, c.global_position, c.linear_velocity.length(),
				c.damage, p.global_position.distance_to(c.global_position)])
		g.world.player_action(1, "car_enter")
		await g.get_tree().create_timer(1.0).timeout
	g.get_tree().quit()


static func car_test(g: Node) -> void:
	var tr: Traffic = g.world.traffic
	var p: Player = _pl(g)
	var c: Car = tr.car_of(1)
	if OS.get_cmdline_user_args().has("--probe_step"):
		var sp: PhysicsDirectSpaceState3D = g.get_world_3d().direct_space_state
		for zz in [252.5, 253.5, 254.5]:
			var line := "z=%.1f:" % zz
			for i in 12:
				var xx := 86.0 + i * 0.75
				var q := PhysicsRayQueryParameters3D.create(Vector3(xx, 50, zz), Vector3(xx, -80, zz), 1)
				var hh := sp.intersect_ray(q)
				line += " %.1f:%.2f%s" % [xx, hh["position"].y, String(hh["collider"].get_meta("surface", "?")).substr(0, 1)]
			print(line)
		g.get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--aionly"):
		await _ai_test(g, tr, p, c)
		return
	# 1) hráč řídí na rovném úseku silnice II/490 (378 m): 0–100 km/h, brzdění
	var a := Vector2(-830.0, 1135.0)
	var b := Vector2(-1184.0, 1269.0)
	var dir := (b - a).normalized()
	tr.place_car(c, a + Vector2(-dir.y, dir.x) * 1.6, atan2(dir.x, dir.y))
	await g.get_tree().create_timer(1.0).timeout
	g.world.enter_car(1, c)
	await g.get_tree().create_timer(0.5).timeout
	var t0 := Time.get_ticks_msec()
	var t100 := -1.0
	Input.action_press("move_forward")
	for i in 900:
		await g.get_tree().physics_frame
		_keep_heading(c, dir)
		var kmh := c.speed * 3.6
		if i % 30 == 0:
			print("t=%.1f s  %5.1f km/h  stupeň %d  %4d ot/min" % [(Time.get_ticks_msec() - t0) / 1000.0, kmh, c.gear, int(c.rpm)])
		if t100 < 0.0 and kmh >= 100.0:
			t100 = (Time.get_ticks_msec() - t0) / 1000.0
			print("0–100 km/h za %.1f s (reálná Octavia 1.4 TSI ~ 8,5 s)" % t100)
			break
	Input.action_release("move_forward")
	var v0 := c.speed
	var bp := c.global_position
	var tb := Time.get_ticks_msec()
	Input.action_press("move_back")
	while c.speed > 0.5 and Time.get_ticks_msec() - tb < 15000:
		await g.get_tree().physics_frame
		_keep_heading(c, dir)
	Input.action_release("move_back")
	var dist := c.global_position.distance_to(bp)
	var tt := (Time.get_ticks_msec() - tb) / 1000.0
	print("Brzdění z %.0f km/h: dráha %.1f m, čas %.1f s, zpomalení %.1f m/s² (reálně ~40 m, 8–9 m/s²)" % [
		v0 * 3.6, dist, tt, v0 / maxf(tt, 0.01)])
	print("poškození %d %%" % int(c.damage))
	await _ai_test(g, tr, p, c)


static func _ai_test(g: Node, tr: Traffic, p: Player, c: Car) -> void:
	# 2) AI po trase v obci
	var graph: RoadGraph = g.world.graph
	var ast := graph.astar(RoadGraph.CAR_KINDS)
	var ids := ast.get_id_path(ast.get_closest_point(Vector2(360, 240)), ast.get_closest_point(Vector2(20, -10)))
	var pts := graph.lane_points(ids, g.world.terrain)
	var d := Vector2(pts[1].x - pts[0].x, pts[1].z - pts[0].z)
	tr.place_car(c, Vector2(pts[0].x, pts[0].z), atan2(d.x, d.y))
	await g.get_tree().create_timer(0.5).timeout
	# hráč sedí za volantem, auto řídí AI (autopilot) – kamera auta
	if p.car == null:
		g.world.enter_car(1, c)
	c.set_ai_route(pts, 13.9)
	for k in range(0, 16):
		print("  bod %d: (%.1f, %.1f)" % [k, pts[k].x, pts[k].z])
	c.crashed.connect(func(imp: float, what: String, _o: Object):
		print("  AI náraz: %s %.1f m/s u %s (bod trasy %d/%d)" % [what, imp, c.global_position, c.ai_i, pts.size()]))
	var worst := 0.0
	var worst_at := ""
	var ta := Time.get_ticks_msec()
	while not c.ai_done() and Time.get_ticks_msec() - ta < 90000:
		await g.get_tree().physics_frame
		var err := INF
		var cp := Vector2(c.global_position.x, c.global_position.z)
		for k in pts.size() - 1:
			var q := Geometry2D.get_closest_point_to_segment(cp, Vector2(pts[k].x, pts[k].z), Vector2(pts[k + 1].x, pts[k + 1].z))
			err = minf(err, q.distance_to(cp))
		if err > worst:
			worst = err
			worst_at = "(%.0f, %.0f) bod %d" % [c.global_position.x, c.global_position.z, c.ai_i]
		if Engine.get_physics_frames() % (15 if c.ai_i >= 6 and c.ai_i <= 14 else 240) == 0:
			var tg: Vector3 = pts[mini(c.ai_i, pts.size() - 1)]
			print("  AI t=%.1f pos=(%.1f,%.1f,%.1f) i=%d cíl=(%.1f,%.1f) v=%.1f want=%.1f steer=%.2f thr=%.2f brk=%.2f odchylka=%.1f g=%d rpm=%d kola=%s" % [
				(Time.get_ticks_msec() - ta) / 1000.0, c.global_position.x, c.global_position.y, c.global_position.z, c.ai_i,
				tg.x, tg.z, c.speed, c.ai_target_speed, c.steer_in, c.throttle, c.brake_in, err, c.gear, int(c.rpm),
				"".join(c.wheels.map(func(w): return "%d/%.0f/%.1f " % [int(w.is_in_contact()), w.engine_force, w.brake])) + " kol=" + str(c.get_colliding_bodies().map(func(b): return "%s(%s)" % [b.name, b.get_meta("surface", "")]))])
	print("AI hospoda → domov: %.0f s, max. odchylka od pruhu %.1f m u %s, poškození %d %%, dojel: %s" % [
		(Time.get_ticks_msec() - ta) / 1000.0, worst, worst_at, int(c.damage), c.ai_done()])
	g.get_tree().quit()


static func _keep_heading(c: Car, dir: Vector2) -> void:
	var f := c.global_transform.basis.z
	var err := Vector2(f.x, f.z).angle_to(dir)
	# kladný úhel = cíl vlevo? (osa +X je vlevo)
	var s := clampf(-err * 3.0, -1.0, 1.0)
	Input.action_release("move_left")
	Input.action_release("move_right")
	if s > 0.02:
		Input.action_press("move_left", s)
	elif s < -0.02:
		Input.action_press("move_right", -s)


static func quest_test(g: Node) -> void:
	await g.get_tree().create_timer(1.0).timeout
	var q: Quests = g.world.quests_of(1)
	var res: Array = []     # [název, očekáváno, výsledek, ok]
	var check := func(name: String, qq, want: String) -> void:
		var ok: bool = qq.state == want
		res.append(ok)
		print("%s %-44s očekáváno %-6s → %-6s %s" % ["OK  " if ok else "CHYBA", name, want, qq.state,
			qq.result_text if qq.state == "done" else qq.fail_reason])

	# ---------------------------------------------------------------- 1. cigarety pro dědu
	var cig = q.by_id("cigarety")
	await _reset(g, 20.0)
	await _go(g, "deda")
	await _accept(g, "deda", cig)
	g.world.clock.minutes = cig.deadline + 1.0          # děda šel spát
	await _frames(g, 3)
	check.call("Cigarety – nestihl do 22:00", cig, "failed")
	await _reset(g, 10.0)
	await _go(g, "deda")
	await _accept(g, "deda", cig)
	await _go(g, "obchod")
	await _pick(g, "obchod", "Cigarety (krabička")
	await _frames(g, 3)
	print("     krok %d: %s" % [cig.step, cig.objective()])
	await _go(g, "deda")
	await _pick(g, "deda", "Dát dědovi cigarety")
	check.call("Cigarety – koupit v Potravinách a donést", cig, "done")

	# ---------------------------------------------------------------- 2. páteční pivo
	var pivo = q.by_id("pivo")
	await _reset(g, 18.0)
	await _go(g, "hospoda")
	await _accept(g, "hospoda", pivo)
	await _drink_round(g)
	print("     krok %d: %s  (%.2f ‰, vrchol %.2f ‰)" % [pivo.step, pivo.objective(), _pl(g).body.promile(),
		_pl(g).body.promile_peak_estimate()])
	g.world.traffic.place_car(g.world.traffic.car_of(1), Vector2(_pl(g).global_position.x + 3.0, _pl(g).global_position.z), 0.0)
	await _frames(g, 5)
	g.world.enter_car(1, g.world.traffic.car_of(1))
	await _frames(g, 3)
	check.call("Pivo – po pivech sedl do auta", pivo, "failed")
	g.world.exit_car(1)
	await _reset(g, 18.0)
	await _go(g, "hospoda")
	await _accept(g, "hospoda", pivo)            # druhý pokus: starý časový limit už neplatí
	await _frames(g, 5)
	await _drink_round(g)
	await _go(g, "domov")
	await _frames(g, 5)
	check.call("Pivo – 3 piva + panák, pěšky domů", pivo, "done")

	# ---------------------------------------------------------------- 3. slivovice pro starostu
	var sliv = q.by_id("slivovice")
	await _reset(g, 10.0)
	await _go(g, "urad")
	await _accept(g, "urad", sliv)
	await _go(g, "palenice")
	await _pick(g, "palenice", "Slivovice 50 %")
	await _frames(g, 3)
	_pl(g).use_item("slivovice")               # tlačítko „Napít se“ v inventáři
	await _frames(g, 3)
	check.call("Slivovice – otevřel lahev", sliv, "failed")
	await _reset(g, 10.0)
	await _go(g, "urad")
	await _accept(g, "urad", sliv)
	await _go(g, "palenice")
	await _pick(g, "palenice", "Ochutnat slivovici")
	await _idle(g)
	await _pick(g, "palenice", "Slivovice 50 %")
	await _go(g, "urad")
	await _frames(g, 3)
	await _pick(g, "urad", "Předat slivovici")
	check.call("Slivovice – koupit a předat neotevřenou", sliv, "done")

	# ---------------------------------------------------------------- 4. autem z hospody
	var aut = q.by_id("autem")
	await _reset(g, 20.0)
	await _go(g, "hospoda")
	await _accept(g, "hospoda", aut)             # Pepa přistrčí pivo „na cestu“
	await _idle(g)
	await _pick(g, "hospoda", "Točené pivo")     # … a ještě jedno
	await _idle(g)
	print("     sedá za volant s %.2f ‰ (vrchol %.2f ‰)" % [_pl(g).body.promile(), _pl(g).body.promile_peak_estimate()])
	await _drive_home(g, aut)
	check.call("Autem – opilý, silniční kontrola", aut, "failed")
	await _reset(g, 20.0)
	await _go(g, "hospoda")
	await _accept(g, "hospoda", aut)
	await _idle(g)
	await _go(g, "domov")
	await _pick(g, "domov", "Vyspat se")         # vystřízliví do rána
	await g.get_tree().create_timer(2.5).timeout
	print("     ráno %s: %.2f ‰" % [g.world.clock.text(), _pl(g).body.promile()])
	await _go(g, "hospoda")
	await _drive_home(g, aut)
	check.call("Autem – střízlivý domů bez nehody", aut, "done")

	# ---------------------------------------------------------------- 5. mejdan na chatě
	var mej = q.by_id("mejdan")
	for attempt in 2:
		await _reset(g, 12.0)
		await _go(g, "obchod")
		await _accept(g, "obchod", mej)
		for it in ["Vodka 40 %", "Tuzemský rum", "Víno bílé", "Víno červené"]:
			await _pick(g, "obchod", it)
		await _frames(g, 3)
		await _go(g, "chata")
		await _pick(g, "chata", "Předat nákup")
		for i in 2:
			await _pick(g, "chata", "Připít si")
			await _idle(g)
		print("     krok %d: %s" % [mej.step, mej.objective()])
		if attempt == 0:
			_pl(g).body.nausea = 1.5           # přebral to → žaludek se zvedne
			await _frames(g, 5)
			check.call("Mejdan – pozvracel se", mej, "failed")
		else:
			Engine.time_scale = 4.0              # 45 herních minut = 90 s → zrychlit
			var t0 := Time.get_ticks_msec()
			while mej.state == "active" and Time.get_ticks_msec() - t0 < 60000:
				await g.get_tree().process_frame
			Engine.time_scale = 1.0
			check.call("Mejdan – nákup, přípitky, 45 min na chatě", mej, "done")

	# ---------------------------------------------------------------- 6. degustace
	var deg = q.by_id("degustace")
	for attempt in 2:
		await _reset(g, 14.0)
		await _go(g, "sklep")
		await _accept(g, "sklep", deg)
		if attempt == 1:
			for i in 2:                           # najíst se předem
				await _pick(g, "sklep", "Chleba se sádlem")
				await _idle(g)
		for i in 6:
			await _pick(g, "sklep", "Ochutnat vzorek")
			await _idle(g)
		await g.get_tree().create_timer(4.0).timeout
		check.call("Degustace – nalačno" if attempt == 0 else "Degustace – s chlebem se sádlem", deg,
			"failed" if attempt == 0 else "done")

	var n_ok := res.count(true)
	print("VÝSLEDEK úkolů: %d/%d OK" % [n_ok, res.size()])
	g.get_tree().quit()


static func _frames(g: Node, n: int) -> void:
	for i in n:
		await g.get_tree().physics_frame


## Počká, až hráč dopije / dojí.
static func _idle(g: Node) -> void:
	var t0 := Time.get_ticks_msec()
	while _pl(g).busy and Time.get_ticks_msec() - t0 < 10000:
		await g.get_tree().process_frame
	await _frames(g, 2)


## Nový herní den v hodinu `h`: střízlivý, najedený nic, 5 000 Kč, prázdný inventář, bez zákazu řízení.
static func _reset(g: Node, h: float) -> void:
	var p: Player = _pl(g)
	if p.car:
		g.world.exit_car(1)
	g.client.hud.close_menu()
	await _idle(g)
	var b: BodyState = p.body
	b.body_alc = 0.0
	b.stomach_alc = 0.0
	b.stomach_kcal = 0.0
	b.nausea = 0.0
	b.health = 100.0
	b.alive = true
	b.weight = 82.0
	b._prev_promile = 0.0
	b._rise = 0.0
	p.inventory.clear()
	p.open_ml.clear()
	p.money = 5000
	p.fallen = 0.0
	p.license_suspended_until = -1.0
	p.wanted_until = -1.0
	g.world.traffic.car_of(1).repair()
	g.world.clock.minutes = (floor(g.world.clock.minutes / 1440.0) + 1.0) * 1440.0 + h * 60.0
	await _frames(g, 2)


## Dojde k místu (teleport kousek před dveře / k NPC).
static func _go(g: Node, key: String) -> void:
	var pos: Vector3
	if key == "deda":
		pos = g.world.npcs["deda"].global_position + Vector3(0, 0, 1.3)
	else:
		var pl: Place = g.world.places[key]
		pos = pl.door + Basis(Vector3.UP, float(pl.data.get("face_yaw", 0.0))) * Vector3(0, 0, 1.4)
	_pl(g).teleport(pos + Vector3(0, 0.3, 0), _pl(g).yaw, false)
	await _frames(g, 4)


## Otevře nabídku místa (jako klávesa E) a stiskne tlačítko obsahující `text`.
static func _pick(g: Node, key: String, text: String) -> bool:
	g.client.open_place_menu(key)
	for c in g.client.hud._menu_list.get_children():
		if c is Button and not c.is_queued_for_deletion() and c.text.contains(text):
			if c.disabled:
				print("     !! tlačítko „%s“ je neaktivní" % c.text)
				break
			c.pressed.emit()
			await _frames(g, 2)
			return true
	var have := []
	for c in g.client.hud._menu_list.get_children():
		if c is Button and not c.is_queued_for_deletion():
			have.append(c.text)
	print("     !! v nabídce „%s“ chybí „%s“ (je tam: %s)" % [key, text, ", ".join(have)])
	g.client.hud.close_menu()
	return false


static func _accept(g: Node, key: String, qq) -> void:
	if await _pick(g, key, "Úkol: " + qq.title):
		await _pick_open(g, "Přijmout úkol")
	await _frames(g, 2)


## Stiskne tlačítko v právě otevřené nabídce.
static func _pick_open(g: Node, text: String) -> void:
	for c in g.client.hud._menu_list.get_children():
		if c is Button and not c.is_queued_for_deletion() and c.text.contains(text):
			c.pressed.emit()
			break
	await _frames(g, 2)


static func _drink_round(g: Node) -> void:
	for i in 3:
		await _pick(g, "hospoda", "Točené pivo")
		await _idle(g)
	await _pick(g, "hospoda", "Panák slivovice")
	await _idle(g)


## Nastoupí do svého auta a nechá ho dovézt autopilotem domů (hráč sedí za volantem). U silniční
## kontroly zastaví jako hráč: zpomalí a stojí, dokud policista neudělá dechovou zkoušku.
static func _drive_home(g: Node, qq) -> void:
	var c: Car = g.world.traffic.car_of(1)
	var p: Player = _pl(g)
	p.teleport(c.global_position + c.global_transform.basis.x * 2.2 + Vector3(0, 0.5, 0), 0.0, false)
	await _frames(g, 3)
	g.world.enter_car(1, c)
	await _frames(g, 3)
	var pa: Vector3 = g.world.places["hospoda"].park
	var pb: Vector3 = g.world.places["domov"].park
	var ids: PackedInt64Array = g.world.graph.route(Vector2(pa.x, pa.z), Vector2(pb.x, pb.z))
	var pts: PackedVector3Array = g.world.graph.lane_points(ids, g.world.terrain)
	pts.append(pb + Vector3(0, 0.1, 0))
	c.set_ai_route(pts, 13.9)
	var pol: Police = g.world.police
	pol.last_test_promile = -1.0
	var on_crash := func(imp: float, what: String, _o: Object):
		if imp > 3.0:
			print("     náraz: %s %.1f m/s u (%.0f, %.0f), bod trasy %d/%d, poškození %d %%" % [what, imp,
				c.global_position.x, c.global_position.z, c.ai_i, pts.size(), int(c.damage)])
	c.crashed.connect(on_crash)
	var stopped := false
	var t0 := Time.get_ticks_msec()
	while qq.state == "active" and Time.get_ticks_msec() - t0 < 150000:
		await g.get_tree().physics_frame
		if pol.checkpoint_pos != Vector3.INF and not stopped:
			var d := Vector2(p.global_position.x - pol.checkpoint_pos.x, p.global_position.z - pol.checkpoint_pos.z).length()
			if d < 70.0:
				c.ai_speed_limit = 5.0
			if d < 13.0:
				c.ai_stop = true
				stopped = true
				print("     zastavil u silniční kontroly (%.0f m)" % d)
				var shot_done := false
				# čeká na začátek a konec kontroly (dechová zkouška nemusí být – policista může jen zkontrolovat doklady / udělit pokutu)
				while pol.patrol_state != Police.State.STOPPING and qq.state == "active" and Time.get_ticks_msec() - t0 < 30000:
					await g.get_tree().physics_frame
				while pol.patrol_state == Police.State.STOPPING and qq.state == "active" and Time.get_ticks_msec() - t0 < 150000:
					await g.get_tree().physics_frame
					if pol._stop_phase == 1 and not shot_done and pol._stop_t > 1.0 and g._args.has("stopshot"):
						shot_done = true
						c._cam_yaw = -1.3         # kamera z boku řidiče, ať je vidět okénko
						c._cam_idle = -5.0
						await g.get_tree().create_timer(0.6).timeout
						g.get_viewport().get_texture().get_image().save_png(g._args["stopshot"])
						print("     snímek kontroly: %s" % g._args["stopshot"])
				print("     výsledek kontroly: %s, dechová zkouška %.2f ‰" % [pol._stop_plan, pol.last_test_promile])
				c.ai_stop = false
				c.ai_speed_limit = 13.9
		if p.car == null:
			break
		if qq.step >= 2 and absf(c.speed) < 1.0:
			g.world.exit_car(1)
			await _frames(g, 3)
	print("     jízda %.0f s, poškození auta %d %%, auto %.0f m od domu (bod trasy %d/%d, blokuje: %s)" % [
		(Time.get_ticks_msec() - t0) / 1000.0, int(c.damage), c.global_position.distance_to(pb), c.ai_i, pts.size(),
		c.ai_blocker.name if c.ai_blocker and is_instance_valid(c.ai_blocker) else "nic"])
	c.crashed.disconnect(on_crash)
	if p.car:
		g.world.exit_car(1)
	c.drive = Car.Drive.NONE


## Provoz: hráč stojí ve vsi, AI auta a hlídka jezdí `--dur` s (výchozí 180). Pro každé auto se měří
## nejdelší stání mimo cíl trasy; > 20 s = auto „visí“ (křižovatka, vzájemné zablokování, překážka).
static func traffic_test(g: Node) -> void:
	var tr: Traffic = g.world.traffic
	var p: Player = _pl(g)
	var dur := float(g._args.get("dur", "180"))
	var cars: Array[Car] = []
	cars.append_array(tr.ai_cars)
	cars.append(g.world.police.patrol)
	var stand := {}
	var worst := {}
	var dist := {}
	var last := {}
	for c in cars:
		stand[c] = 0.0
		worst[c] = [0.0, Vector3.ZERO, ""]
		dist[c] = 0.0
		last[c] = c.global_position
	var t0 := Time.get_ticks_msec()
	var crashes := [0]
	for c in cars:
		c.crashed.connect(func(imp: float, what: String, o: Object):
			if imp > 4.0 or c.damage >= 100.0:
				crashes[0] += 1
				print("  náraz %s: %s %.1f m/s u (%.0f, %.0f), poškození %d %% (%s)" % [c.name, what, imp,
					c.global_position.x, c.global_position.z, int(c.damage), o.name if o else "?"]))
	print("hráč stojí u %s" % p.global_position)
	var next_print := 0.0
	while (Time.get_ticks_msec() - t0) / 1000.0 < dur:
		await g.get_tree().physics_frame
		var dt := 1.0 / Engine.physics_ticks_per_second
		var t := (Time.get_ticks_msec() - t0) / 1000.0
		for c in cars:
			var moved: float = c.global_position.distance_to(last[c])
			last[c] = c.global_position
			if moved < 5.0:        # respawn = skok, nepočítat
				dist[c] += moved
			else:
				stand[c] = 0.0
			if absf(c.speed) < 0.5 and not c.ai_done() and not c.ai_stop:
				stand[c] += dt
				if stand[c] > worst[c][0]:
					var why := "blokuje ho %s" % (c.ai_blocker.name if c.ai_blocker and is_instance_valid(c.ai_blocker) \
						else "nic") if c.ai_blocked > 0.0 else "stojí bez překážky"
					worst[c] = [stand[c], c.global_position, why]
			else:
				stand[c] = 0.0
		if t >= next_print:
			next_print += 30.0
			var line := "t=%3.0f s" % t
			for c in cars:
				line += " | %s %4.1f m/s" % [c.name, c.speed]
			print(line)
	var bad := 0
	print("--- provoz za %.0f s (hráč stojí u %s) ---" % [dur, p.global_position])
	for c in cars:
		var w: Array = worst[c]
		var flag := "OK" if w[0] < 20.0 else "VISÍ"
		if w[0] >= 20.0:
			bad += 1
		print("%-16s ujeto %5.0f m, nejdelší stání %4.1f s u (%.0f, %.0f) – %s  [%s]" % [c.name, dist[c], w[0],
			w[1].x, w[1].z, w[2], flag])
	var why := {}
	for r in tr.respawn_log:
		why[r[2]] = int(why.get(r[2], 0)) + 1
	print("přesunutí aut: %s" % str(why))
	print("VÝSLEDEK provozu: %s" % ("OK" if bad == 0 else "%d aut visí" % bad))
	g.get_tree().quit()


## Fauna a kůň: hráč se objeví 35 m a pak 7 m od zvířete (má si všimnout a utéct), pak nasedne na koně,
## pobídne ho do klusu a cvalu, zastaví a sesedne. Vypisuje stavy; s --shotdir ukládá snímky.
static func fauna_test(g: Node) -> void:
	var w: World = g.world
	var p: Player = _pl(g)
	var f: Fauna = w.fauna
	var shots: String = g._args.get("shotdir", "")
	await g.get_tree().create_timer(1.0).timeout
	print("FAUNA: zvířat %d, skupin %d · %s %s · %s · les u domu %.2f" % [f.animals.size(), f.herds.size(),
		w.clock.date_text(), w.clock.text(), w.weather.describe(), f.forest_at(p.global_position.x, p.global_position.z)])
	for sp in ["srnec", "divocak", "zajic"]:
		var a: Animal = null
		var bd := INF
		for x in f.animals:
			if x.species == sp and not x.dead and x.global_position.distance_to(p.global_position) < bd:
				bd = x.global_position.distance_to(p.global_position)
				a = x
		if a == null:
			print("FAUNA %s: žádné zvíře" % sp)
			continue
		var side := Vector3(1, 0, 0.3).normalized()
		var at := a.global_position + side * 35.0
		at.y = w.terrain.height_at(at.x, at.z) + 0.3
		p.teleport(at, atan2(side.x, side.z))
		await g.get_tree().create_timer(3.0).timeout
		print("FAUNA %s (35 m): stav %s, všiml si %.2f, rychlost %.1f, v lese %.2f" % [sp, a.state, a.aware, a.speed,
			f.forest_at(a.global_position.x, a.global_position.z)])
		if shots != "":
			g.get_viewport().get_texture().get_image().save_png("%s/fauna_%s.png" % [shots, sp])
		var a0 := a.global_position
		at = a.global_position + side * 6.0
		at.y = w.terrain.height_at(at.x, at.z) + 0.3
		p.teleport(at, atan2(side.x, side.z))
		await g.get_tree().create_timer(2.5).timeout
		print("FAUNA %s (6 m): stav %s, rychlost %.1f m/s, chod %s, uběhl %.1f m" % [sp, a.state, a.speed, a.rig.gait,
			a.global_position.distance_to(a0)])
	# --- kůň
	var h: Horse = f.horse_of(1)
	var hp := h.global_position + Vector3(1.6, 0, 0)
	hp.y = w.terrain.height_at(hp.x, hp.z) + 0.3
	p.teleport(hp, 0.0)
	await g.get_tree().create_timer(0.8).timeout
	w.player_action(1, "car_enter")
	await g.get_tree().create_timer(0.5).timeout
	print("KŮŇ: na koni %s, pozice %s" % [p.horse != null, h.global_position])
	Input.action_press("move_forward")
	await g.get_tree().create_timer(3.0).timeout
	print("KŮŇ krok: %.1f m/s (%s)" % [h.speed, h.gait_name()])
	for i in 2:
		Input.action_press("sprint")
		await g.get_tree().create_timer(0.15).timeout
		Input.action_release("sprint")
		await g.get_tree().create_timer(3.5).timeout
		print("KŮŇ %s: %.1f m/s, výdrž %.2f, chod rigu %s" % [h.gait_name(), h.speed, h.stamina, h.rig.gait])
	if shots != "":
		g.get_viewport().get_texture().get_image().save_png("%s/kun_jizda.png" % shots)
	Input.action_release("move_forward")
	await g.get_tree().create_timer(5.0).timeout
	print("KŮŇ po puštění W: %.1f m/s" % h.speed)
	w.player_action(1, "car_enter")
	await g.get_tree().create_timer(1.0).timeout
	print("KŮŇ sesednuto: %s, hráč %s, kůň %s" % [p.horse == null, p.global_position, h.global_position])
	if shots != "":
		g.get_viewport().get_texture().get_image().save_png("%s/kun_stoji.png" % shots)
	g.get_tree().quit()


## Loopback test přípravy přírody na multiplayer (bez sítě, jen s --naturesynctest). Druhá instance Fauny
## v klientském režimu (`setup_client`, loutky zvířat) dostává 10× za s `snapshot_for` autoritativní Fauny a
## 1× za s snímek hejn; 60 s se hráč přemísťuje ke zvěři (35 m → 6 m, srnec, divočák, zajíc) a plaší ji.
## Vypíše odchylku poloh loutek od autority, počet zvířat a velikost snímku, shodu stavů a režimů hejn a
## round-trip Clock / Weather (apply_state → state) včetně `remote_lightning` a vypnutých náhodných blesků.
static func nature_sync_test(g: Node) -> void:
	var w: World = g.world
	var p: Player = _pl(g)
	var f: Fauna = w.fauna
	await g.get_tree().create_timer(1.0).timeout
	# --- klientská příroda (jen loutky) a klientské hodiny / počasí
	var cf := Fauna.new()
	cf.name = "FaunaKlient"
	g.add_child(cf)
	cf.setup_client(w)
	var c2 := Clock.new()
	var w2 := Weather.new()
	w2.authority = false
	w2.setup(c2, w.weather.north_deg)
	var bolts := [0]
	w2.lightning.connect(func(_pos: Vector3): bolts[0] += 1)
	c2.apply_state(w.clock.state(), false)
	w2.apply_state(w.weather.state())
	print("NATURESYNC: start, zvířat %d, hejn %d, %s %s" % [f.animals.size(), f.root_birds.get_child_count(),
		w.clock.date_text(), w.clock.text()])
	var seq := ["srnec", "divocak", "zajic"]
	var ticks := 600
	var samples := 0
	var dev_sum := 0.0
	var dev_max := 0.0
	var devc_sum := 0.0
	var devc_max := 0.0
	var state_ok := 0
	var missing := 0
	var n_max := 0
	var n_sum := 0
	var bytes_max := 0
	var packed_max := 0
	var flock_ok := 0
	var flock_n := 0
	var clock_dev := 0.0
	var fled := 0
	for k in ticks:
		var ph := k / 150
		var lt := k % 150
		if ph < seq.size() and (lt == 0 or lt == 80):
			var best: Animal = null
			var bd := INF
			for x in f.animals:
				var an: Animal = x
				if an.species == seq[ph] and not an.dead and an.global_position.distance_to(p.global_position) < bd:
					bd = an.global_position.distance_to(p.global_position)
					best = an
			if best != null:
				var side := Vector3(1, 0, 0.3).normalized()
				var at := best.global_position + side * (35.0 if lt == 0 else 6.0)
				at.y = w.terrain.height_at(at.x, at.z) + 0.3
				p.teleport(at, atan2(side.x, side.z))
		await g.get_tree().create_timer(0.1).timeout
		var now := Time.get_ticks_msec() / 1000.0
		var arr: Array = f.snapshot_for(p)
		cf.apply_snapshot(arr, now)
		n_max = maxi(n_max, arr.size())
		n_sum += arr.size()
		bytes_max = maxi(bytes_max, var_to_bytes(arr).size())
		packed_max = maxi(packed_max, Fauna.pack_snapshot(arr).to_byte_array().size())
		c2._process(0.1)
		w2._process(0.1)
		clock_dev = maxf(clock_dev, absf(c2.minutes - w.clock.minutes))
		if k % 10 == 0:
			cf.apply_flock_snapshot(f.flock_snapshot(p.global_position), now)
			c2.apply_state(w.clock.state())
			w2.apply_state(w.weather.state())
		if k >= 20 and k % 5 == 0:
			for x in arr:
				var rec: Array = x
				var pup: Animal = cf.puppets.get(int(rec[0]))
				var auth: Animal = null
				for y in f.animals:
					var an2: Animal = y
					if an2.net_id == int(rec[0]):
						auth = an2
						break
				if pup == null or auth == null:
					missing += 1
					continue
				var d := pup.global_position.distance_to(auth.global_position)
				var dc := maxf(d - absf(auth.speed) * Animal.PUPPET_DELAY, 0.0)
				samples += 1
				dev_sum += d
				dev_max = maxf(dev_max, d)
				devc_sum += dc
				devc_max = maxf(devc_max, dc)
				if pup.state == auth.state:
					state_ok += 1
				if auth.state == "flee":
					fled += 1
			if k % 10 == 0:
				for fl in f.root_birds.get_children():
					var pf: BirdFlock = cf.flock_puppets.get(fl.net_id)
					if pf != null:
						flock_n += 1
						if pf.mode == fl.mode or pf.mode == "fly" or fl.mode == "fly":
							flock_ok += 1
	print("NATURESYNC zvěř: ve snímku průměrně %.1f zvířat (max %d), snímek %d B jako Array (var_to_bytes), %d B zploštěný PackedInt32Array" % [
		float(n_sum) / ticks, n_max, bytes_max, packed_max])
	print("NATURESYNC odchylka loutka vs. autorita: průměr %.2f m, max %.2f m; po odečtení zpoždění interpolace (%.2f s × rychlost): průměr %.2f m, max %.2f m (%d vzorků, %d bez dvojice, %d vzorků v útěku)" % [
		dev_sum / maxf(samples, 1), dev_max, Animal.PUPPET_DELAY, devc_sum / maxf(samples, 1), devc_max, samples, missing, fled])
	print("NATURESYNC shoda stavu (loutka = autorita): %.0f %%" % (100.0 * state_ok / maxf(samples, 1)))
	print("NATURESYNC hejna: loutek %d, shoda režimu (nebo přechod letem) %d / %d" % [cf.flock_puppets.size(), flock_ok, flock_n])
	print("NATURESYNC tok: %d B × 10 Hz = %.1f kB/s pro 1 hráče, %.1f kB/s pro 4 hráče (horní odhad, plný překryv oblastí); zploštěně %.1f / %.1f kB/s" % [
		bytes_max, bytes_max * 10.0 / 1000.0, bytes_max * 40.0 / 1000.0, packed_max * 10.0 / 1000.0, packed_max * 40.0 / 1000.0])
	# --- kalendář a počasí: round-trip
	var cs: Dictionary = w.clock.state()
	c2.apply_state(cs, false)
	var cs2: Dictionary = c2.state()
	print("NATURESYNC Clock: round-trip minut %s, start_jd %s, rychlost %s; největší rozdíl během běhu %.3f herní min" % [
		"OK" if absf(float(cs2["minutes"]) - float(cs["minutes"])) < 0.001 else "ROZDÍL", "OK" if cs2["start_jd"] == cs["start_jd"] else "ROZDÍL",
		"OK" if cs2["speed"] == cs["speed"] else "ROZDÍL", clock_dev])
	var ws: Dictionary = w.weather.state()
	w2.apply_state(ws)
	for i in 30:
		w2._process(0.5)
	var ws2: Dictionary = w2.state()
	var wdev := 0.0
	for key in Weather.STATE_FLOATS:
		wdev = maxf(wdev, absf(float(ws2[key]) - float(ws[key])))
	print("NATURESYNC Weather: kind %s → %s, největší rozdíl veličin po dorovnání %.4f (%s)" % [ws["kind"], ws2["kind"], wdev,
		"OK" if wdev < 0.01 and ws["kind"] == ws2["kind"] else "ROZDÍL"])
	bolts[0] = 0
	w2.remote_lightning(Vector3(100, 0, 100))
	var one: int = bolts[0]
	w2.storm = 1.0
	w2.rain = 0.9
	w2._process(60.0)
	print("NATURESYNC blesky: remote_lightning vyvolal %d× (čekáno 1), náhodné blesky na klientu za 60 s bouřky: %d (čekáno 0)" % [
		one, int(bolts[0]) - one])
	print("NATURESYNC oprávnění (SP): can_change_world %s, can_teleport %s" % [w.can_change_world(1), w.can_teleport(1)])
	cf.queue_free()
	w2.free()
	c2.free()
	g.get_tree().quit()


## Počasí a hratelnost: projede všechny situace (Weather.force) a vypíše přilnavost povrchů,
## teoretickou i měřenou brzdnou dráhu auta, expozici těla (BodyState env), trakci chůze,
## opatrnost AI a předpověď na zítřek.
static func weather_test(g: Node) -> void:
	var w: Weather = g.world.weather
	var p: Player = _pl(g)
	var tr: Traffic = g.world.traffic
	var c: Car = tr.car_of(1)
	print("== WEATHERTEST ==  %s %s" % [g.world.clock.date_text(), g.world.clock.text()])
	# 1) situace: stav veličin a přilnavost povrchů (Weather.SURF_GRIP × mokro / sníh / náledí / bahno)
	print("-- situace a přilnavost (suchý asfalt = 1.0) --")
	var v100 := 100.0 / 3.6
	for k in ["jasno", "zatazeno", "mlha", "prehanky", "dest", "bourka", "snih"]:
		_clean_force(w, k)
		print("%-9s %-16s %5.1f °C · déšť %.2f · mlha %.2f · vítr %4.1f m/s · sníh %.2f · mokro %.2f" % [
			k, w.kind_name(), w.temp, w.rain, w.fog, w.wind, w.snow_cover, w.wetness])
		for s in ["asfalt", "sterk", "teren"]:
			var grip := w.surface_grip(s)
			print("    %-6s přilnavost %.2f  →  brzdná dráha z 100 km/h ~%.0f m (sucho ~48 m)" % [
				s, grip, v100 * v100 / (2.0 * 8.0 * grip)])
		var fc := w.forecast()
		if not fc.is_empty():
			print("    předpověď na zítřek: %s, nejtepleji %d °C" % [fc["name"], fc["temp"]])
	# 2) náledí: mokro + mráz
	_clean_force(w, "naledi")
	print("-- náledí (mokro %.2f, %.0f °C): asfalt %.2f, štěrk %.2f, teren %.2f" % [
		w.wetness, w.temp, w.surface_grip("asfalt"), w.surface_grip("sterk"), w.surface_grip("teren")])
	# 3) expozice těla: 4 h venku v dešti vs. pod střechou (BodyState env)
	_clean_force(w, "dest")
	var bout := BodyState.new()
	var bin := BodyState.new()
	for i in 48:    # 4 herní hodiny po 5 minutách
		bout.update(5.0 / 60.0, 200.0, {"rain": w.rain, "temp": w.temp, "wind": w.wind, "in": false})
		bin.update(5.0 / 60.0, 200.0, {"rain": 0.0, "temp": w.temp, "wind": 0.0, "in": true})
	print("-- 4 h v dešti %.2f za %d °C a větru %.0f m/s:  venku mokro %.2f / zima %.2f,  pod střechou %.2f / %.2f" % [
		w.rain, roundi(w.temp), w.wind, bout.wetness, bout.cold, bin.wetness, bin.cold])
	bout.free()
	bin.free()
	# 4) trakce chůze (Player._ground_traction podle povrchu pod nohama)
	_clean_force(w, "snih")
	p._floor_surf = "asfalt"
	var trac_a := p._ground_traction()
	p._floor_surf = "teren"
	var trac_t := p._ground_traction()
	print("-- chůze na sněhu %.0f cm: trakce asfalt %.2f, teren %.2f" % [w.snow_cover * 10.0, trac_a, trac_t])
	# 5) AI opatrnost (stejný výpočet jako Car._ai_drive)
	for k in ["jasno", "mlha", "dest", "bourka", "snih"]:
		_clean_force(w, k)
		var caution := clampf(maxf(w.rain, w.snow_cover) + w.fog, 0.0, 1.0)
		print("    AI %s: opatrnost %.2f → rychlost ~%d %%, rozestup ×%.1f, světla %s" % [
			k, caution, roundi((1.0 - Car.AI_SLOW * caution) * 100.0), 1.0 + caution * Car.AI_GAP,
			"ano" if w.fog > 0.3 else "ne"])
	# 6) měřená brzdná dráha auta z ~80 km/h na rovném úseku II/490 (jako --cartest)
	print("-- měřené brzdění auta z ~80 km/h na asfaltu --")
	var a := Vector2(-830.0, 1135.0)
	var b := Vector2(-1184.0, 1269.0)
	var dir := (b - a).normalized()
	for k in ["jasno", "dest", "snih"]:
		_clean_force(w, k)
		if p.car:
			g.world.exit_car(1)
			await _frames(g, 3)
		tr.place_car(c, a + Vector2(-dir.y, dir.x) * 1.6, atan2(dir.x, dir.y))
		await g.get_tree().create_timer(0.8).timeout
		g.world.enter_car(1, c)
		await g.get_tree().create_timer(0.3).timeout
		Input.action_press("move_forward")
		var t0 := Time.get_ticks_msec()
		while c.speed * 3.6 < 80.0 and Time.get_ticks_msec() - t0 < 40000:
			await g.get_tree().physics_frame
			_keep_heading(c, dir)
		Input.action_release("move_forward")
		var v0 := c.speed
		var bp := c.global_position
		Input.action_press("move_back")
		var tb := Time.get_ticks_msec()
		while c.speed > 0.5 and Time.get_ticks_msec() - tb < 25000:
			await g.get_tree().physics_frame
			_keep_heading(c, dir)
		Input.action_release("move_back")
		print("    %s: z %.0f km/h dráha %.1f m za %.1f s (grip %.2f, mokro %.2f, sníh %.2f)" % [
			k, v0 * 3.6, c.global_position.distance_to(bp), (Time.get_ticks_msec() - tb) / 1000.0,
			w.surface_grip("asfalt"), w.wetness, w.snow_cover])
	w.unforce()
	if p.car:
		g.world.exit_car(1)
	c.drive = Car.Drive.NONE
	g.get_tree().quit()


## force() nuluje jen část stavu (mokro, sníh a teplota z předchozí situace zůstávají) –
## před každou situací testu vrátit čistý stav, aby se výsledky nemíchaly.
static func _clean_force(w: Weather, k: String) -> void:
	w.snow_cover = 0.0
	w.wetness = 0.0
	if w.temp < 2.0:
		w.temp = 8.0
	w.force(k)


## Mapový interiér (Fáze 2): hospoda z `data/maps/hospoda.map` přes FuncGodot. Ověří druh "qodot",
## neprázdný mesh + kolize, E-objekty a sedadla/spots ze značek, vstup a výstup hráče,
## a že místo bez .map zůstává procedurální (obchod). Bez addonu se hospoda staví procedurálně – OK.
static func interior_test(g: Node) -> void:
	var w: World = g.world
	await g.get_tree().create_timer(1.0).timeout
	var bad := []                        # lambda zachytává proměnné hodnotou → počítadlo jako pole
	var check := func(name: String, ok: bool) -> void:
		if not ok:
			bad.append(name)
		print("%s %s" % ["OK  " if ok else "CHYBA", name])
	print("INTERIOR: addon FuncGodot=%s, mapa hospoda=%s" % [MapInteriors.addon_ok(),
		FileAccess.file_exists(MapInteriors.map_path("hospoda"))])
	# --- hospoda: druh podle dostupnosti mapy
	var st: InteriorStreamer = w.interior_streamer
	var k := String(st.specs["hospoda"]["kind"])
	check.call("druh hospody = qodot (mapa+addon) nebo hospoda (fallback)", k == ("qodot" if MapInteriors.has_map("hospoda") else "hospoda"))
	check.call("obchod zůstává procedurální (kind obchod)", String(st.specs["obchod"]["kind"]) == "obchod")
	var fake := Interior.make(null, "neexistujici_misto", "qodot", Vector3.ZERO)
	check.call("místo bez .map → procedurální kroky", MapInteriors.steps(fake).size() == 1)
	if not w.ensure_interior("hospoda"):
		print("CHYBA: ensure_interior(hospoda) selhalo")
		g.get_tree().quit()
		return
	var it: Interior = w.interiors["hospoda"]
	var t0 := Time.get_ticks_msec()
	while not it.built and Time.get_ticks_msec() - t0 < 15000:
		await g.get_tree().process_frame
	check.call("hospoda dostavěna", it.built)
	var map := it.get_node_or_null("Mapa")
	if MapInteriors.has_map("hospoda"):
		check.call("mapový uzel Mapa existuje", map != null)
		var meshes: Array = map.find_children("*", "MeshInstance3D", true, false) if map else []
		var bodies: Array = map.find_children("*", "StaticBody3D", true, false) if map else []
		var faces := 0
		var shapes := 0
		for m in meshes:
			var mi := m as MeshInstance3D
			if mi.mesh:
				faces += mi.mesh.get_faces().size()
		for b in bodies:
			shapes += (b as StaticBody3D).get_child_count()
		print("  mesh instancí %d (stěn %d), kolizních těles %d (tvarů %d)" % [meshes.size(), faces, bodies.size(), shapes])
		check.call("mesh není prázdný", faces > 0)
		check.call("kolize vygenerovány", shapes > 0)
		var surf_ok := false
		for b in bodies:
			if String((b as StaticBody3D).get_meta("surface", "")) == "budova":
				surf_ok = true
		check.call("kolize mají surface=budova", surf_ok)
	# --- E-objekty a místa ze značek (platí pro mapový i procedurální interiér)
	var keys := []
	for o in it.objects:
		keys.append(String(o["key"]))
	print("  E-objekty: %s" % str(keys))
	check.call("E Vyjít ven", "exit" in keys)
	check.call("E obsluha (place:hospoda)", "place:hospoda" in keys)
	check.call("keeper_spot za pultem", it.keeper_spot != Vector3.INF)
	check.call("sedadla reg", it.seats.get("reg", []).size() > 0)
	check.call("sedadla fri", it.seats.get("fri", []).size() > 0)
	check.call("spots pipa + stoly", it.spots.has("pipa") and String(it.spots.keys()[0]) != "" and it.spots.keys().filter(
		func(s): return String(s).begins_with("stul:")).size() > 0)
	# --- vstup a výstup
	w.teleport_inside(1, "hospoda")
	await _frames(g, 5)
	var p: Player = _pl(g)
	check.call("hráč uvnitř hospody", p.inside == "hospoda")
	check.call("spawn u dveří čelem dovnitř (−Z)", it.inside_door != Vector3.ZERO and absf(it.inside_yaw) < 0.5)
	var interact := it.interactables()
	check.call("interactables uvnitř neprázdné", interact.size() > 0)
	w.exit_interior(1, false)            # bez fade – synchronní výstup
	await _frames(g, 5)
	check.call("hráč zase venku", p.inside == "")
	# --- procedurální interiér (obchod) – stejný vstup jako kontrola bez mapy
	w.teleport_inside(1, "obchod")
	await _frames(g, 10)
	var ob: Interior = w.interiors.get("obchod")
	check.call("interiér obchodu vytvořen", ob != null)
	if ob == null:
		g.get_tree().quit()
		return
	var t2 := Time.get_ticks_msec()
	while not ob.built and Time.get_ticks_msec() - t2 < 15000:
		await g.get_tree().process_frame
	check.call("obchod procedurálně dostavěn", ob.built)
	check.call("hráč uvnitř obchodu", p.inside == "obchod")
	w.exit_interior(1, false)
	await _frames(g, 5)
	print("VÝSLEDEK interiérů: %s" % ("OK" if bad.is_empty() else "%d chyb" % bad.size()))
	g.get_tree().quit()


## Vesničan s behavior stromem (Fáze 3, LimboAI): ověří, že se `ai/villager_routine.tres` načetl,
## instancoval u prvních `Villager.BT_VILLAGERS` vesničanů, blackboard se naplnil z herních dat
## (domov z Estate, pracoviště z povolání, stůl u hospody), strom vybírá větve podle denní doby
## a vesničan se za cílem hýbe. Bez addonu LimboAI jen zkontroluje, že boti běží jako dřív.
static func villager_test(g: Node) -> void:
	var w: World = g.world
	await g.get_tree().create_timer(1.0).timeout
	var bad := []
	var check := func(name: String, ok: bool) -> void:
		if not ok:
			bad.append(name)
		print("%s %s" % ["OK  " if ok else "CHYBA", name])
	var addon := ClassDB.class_exists("BehaviorTree")
	print("VILLAGER: addon LimboAI=%s, strom=%s" % [addon, ResourceLoader.exists(Villager.BT_TREE)])
	var bots: Array = []
	for b in w.bots_root.get_children():
		if b is Villager:
			bots.append(b)
	var with_bt: Array = bots.filter(func(v): return v._bt_inst != null)
	check.call("villager.gd bez addonu běží (žádná tvrdá reference na LimboAI)", true)
	if not addon:
		print("VILLAGER: addon chybí – vesničanů %d bez BT, fallback = původní chůze (OK)" % bots.size())
		check.call("villager.gd se načetl", bots.size() > 0)
		print("VÝSLEDEK villager: %s" % ("OK" if bad.is_empty() else "%d chyb" % bad.size()))
		g.get_tree().quit()
		return
	check.call("strom se načetl", ResourceLoader.exists(Villager.BT_TREE) and load(Villager.BT_TREE) != null)
	check.call("prvních %d vesničanů má BT" % Villager.BT_VILLAGERS,
		with_bt.size() == mini(Villager.BT_VILLAGERS, bots.size()))
	check.call("každý má vlastní instanci stromu", with_bt.filter(func(v):
		return v.persona != null and v.persona.daily_routine != null).size() == with_bt.size())
	if with_bt.is_empty():
		print("VÝSLEDEK villager: CHYBA – žádný vesničan nemá BT")
		g.get_tree().quit()
		return
	await _frames(g, 30)   # nechat líně naplnit blackboard (places + estate vznikly až po botách)
	var v: Villager = with_bt[0]
	for key in ["self", "world", "graph", "terrain", "home", "garden", "pub_table"]:
		check.call("blackboard má „%s“" % key, v._bt_bb.has_var(key) and v._bt_bb.get_var(key) != null)
	check.call("domov je skutečné místo (Estate)", v._bt_bb.get_var("home") is Vector3 \
		and v._bt_bb.get_var("home") != Vector3.INF)
	var wp = v._bt_bb.get_var("workplace")
	print("  %s – povolání „%s“, pracoviště %s" % [v.persona.display_name(),
		v.persona.profile.get("job", "?"), wp if wp is Vector3 and wp != Vector3.INF else "žádné"])

	# --- pracovní den 7:00 → větev „Ranní rutina“ (zahrada + kopání)
	while w.clock.weekday() >= 5:
		w.clock.minutes += 1440.0
	w.clock.minutes = floor(w.clock.minutes / 1440.0) * 1440.0 + 7.0 * 60.0
	var home: Vector3 = v._bt_bb.get_var("home")
	var n0 := w.graph.nearest(Vector2(home.x, home.z))
	var h2 := w.graph.nodes[n0] if n0 >= 0 else Vector2(home.x, home.z)
	v.global_position = Vector3(h2.x, w.terrain.height_at(h2.x, h2.y) + 0.1, h2.y)
	v.clear_target()
	var garden: Vector3 = v._bt_bb.get_var("garden")
	var arrived := false
	var digged := false
	var p0 := v.global_position
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 60000 and not digged:
		await g.get_tree().physics_frame
		if v.bt_target() == garden and Vector2(v.global_position.x - garden.x,
				v.global_position.z - garden.z).length() < 2.0:
			arrived = true
		if String(v._visual.action) == "dig":
			digged = true
	check.call("ranní rutina: BT zvolil cíl „zahrada“", v.bt_target() == garden or arrived)
	check.call("ranní rutina: došel na zahradu (<2 m)", arrived)
	check.call("ranní rutina: animace kopání (dig)", digged)
	print("  ráno 7:00 – cíl %s, ušel %.1f m, akce „%s“, bt_cíl %s" % [garden,
		v.global_position.distance_to(p0), v._visual.action, v.bt_target()])

	# --- pátek 18:00 → větev „Večerní hospoda“ (stůl, sednutí, pivo, promile)
	while w.clock.weekday() != 4:
		w.clock.minutes += 1440.0
	w.clock.minutes = floor(w.clock.minutes / 1440.0) * 1440.0 + 18.0 * 60.0
	var pub: Vector3 = v._bt_bb.get_var("pub_table")
	# 1) počkat, až se větev hospody chytí (doběhne předchozí rutina – sekvence si
	#    pamatuje běžící akci; kopání na zahradě trvá až 20 s)
	var tw := Time.get_ticks_msec()
	while v.bt_target() != pub and Time.get_ticks_msec() - tw < 40000:
		await g.get_tree().physics_frame
	check.call("hospoda: BT zvolil cíl „pub_table“", v.bt_target() == pub)
	# 2) teleport na uzel ~8 m od stolu + clear_target → BT musí trasu naplánovat.
	#    (Teleport přímo ke stolu/dveřím je moc blízko: d < arrive=1,5 → akce Jít
	#    uspěje hned bez move_to, bt_target zůstane INF a check „došel“ by neprošel.)
	var pub2 := Vector2(pub.x, pub.z)
	var n1 := -1
	var n1_diff := 1e9
	for i in w.graph.nodes.size():
		var dn: float = w.graph.nodes[i].distance_to(pub2)
		if dn >= 5.0 and dn <= 20.0 and absf(dn - 8.0) < n1_diff:
			n1_diff = absf(dn - 8.0)
			n1 = i
	if n1 < 0:
		var hosp: Place = w.places.get("hospoda")
		n1 = w.graph.nearest(Vector2(hosp.door.x, hosp.door.z) if hosp else pub2)
	var p2: Vector2 = w.graph.nodes[n1] if n1 >= 0 else pub2
	v.global_position = Vector3(p2.x, w.terrain.height_at(p2.x, p2.y) + 0.1, p2.y)
	v.clear_target()
	var sat := false
	var drank := false
	arrived = false
	p0 = v.global_position
	var dmin := 1e9
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 90000 and not drank:
		await g.get_tree().physics_frame
		var dp := Vector2(v.global_position.x - pub.x, v.global_position.z - pub.z).length()
		dmin = minf(dmin, dp)
		if dp < 1.8 and v.bt_target() == pub:
			arrived = true
		if v._visual.pose == "sit":
			sat = true
		if String(v._visual.action) == "drink" and v.promile > 0.0:
			drank = true
	check.call("hospoda: BT zvolil cíl „pub_table“", v.bt_target() == pub or arrived)
	check.call("hospoda: došel ke stolu (<1,8 m)", arrived)
	check.call("hospoda: sedl si (pose sit)", sat)
	check.call("hospoda: objednal pivo (drink + promile > 0)", drank)
	print("  pátek 18:00 – cíl %s, ušel %.1f m, min.vzdál. %.1f m, póza „%s“, promile %.2f ‰, stav %d" % [
		pub, v.global_position.distance_to(p0), dmin, v._visual.pose, v.promile,
		v._bt_inst.get_last_status()])
	check.call("strom tickuje (last_status RUNNING/SUCCESS)", v._bt_inst.get_last_status() in [1, 3])
	print("VÝSLEDEK villager: %s" % ("OK" if bad.is_empty() else "%d chyb" % bad.size()))
	g.get_tree().quit()
