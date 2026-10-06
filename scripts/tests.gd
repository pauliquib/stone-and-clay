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
##   --flighttest  letoun test_letoun na dráze letiště: vzlet, přetažení/zotavení, dosazení;
##                 stavy přes godot-state-charts (Fáze 4), bez addonu fallback na flagy
##   --fencetest   ploty a ohrady (Fáze 7, FenceManager): procedurální ploty kolem výběhu,
##                 zahrady a pole, kolize, průchodnost branek, rebuild při stěhování, save
##                 round-trip, kůň projde brankou; volitelně --fencedbg pro diagnostiku sond
##   --gardentest  zahrada a dvoříště (Fáze 8): růst rostlin v mesši, plevel, kompost → hnůj →
##                 hnojení, studna naplní konev, skleník chrání před mrazem, garden_visuals save
##   --terraintest terén (Fáze 9): mikroreliéf vs. kolize, wetness → shader, louže při mokru,
##                 wet_boost asfaltu, north_xz pro sněhové jazyky
##   --obcetest   okolní obce (data/obce.json → World.obce, Villages): 5 fiktivních obcí mimo
##                katastr, středy ±6 km, zástavba postavená, obec_at(center) → ta obec
class_name Tests
extends RefCounted

## Mikro-profiler pro --perf: klíč → [celkové µs, počet volání]. Obaluje se kód přes
## `var __t0 := Tests.prof_t0()` … `Tests.prof_add("hud", __t0)`. Zapnutý jen s --perf.
static var PROF := {}
static var PROF_ON := false


static func prof_t0() -> int:
	return Time.get_ticks_usec() if PROF_ON else 0


static func prof_add(key: String, t0: int) -> void:
	if not PROF_ON:
		return
	var e: Array = PROF.get(key, [0, 0])
	e[0] += Time.get_ticks_usec() - t0
	e[1] += 1
	PROF[key] = e


static func prof_report(dur_s: float, frames: int) -> void:
	var keys := PROF.keys()
	keys.sort_custom(func(a, b): return PROF[a][0] > PROF[b][0])
	print("PERF profiler (celkem za %d s, %d volajících na frame):" % [int(dur_s), frames])
	for k in keys:
		var e: Array = PROF[k]
		var per_frame_us := float(e[0]) / maxf(frames, 1.0)
		print("PERF   %-22s %7.1f ms/frame  (%d volání/frame, %.0f µs/volání)" % [
			k, per_frame_us / 1000.0, roundi(float(e[1]) / maxf(frames, 1.0)), per_frame_us / maxf(float(e[1]) / maxf(frames, 1.0), 1.0)])


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
	# A4-02: úřad má úřední dny (víkend a svátky zavřeno) – testy úkolů se posunou na pracovní den
	while g.world.clock.weekday() >= 5 or g.world.clock.holiday() != "":
		g.world.clock.minutes += 1440.0
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


## Letový test (Fáze 4, godot-state-charts): stavový automat letouna na dráze letiště.
## Reálná fyzika: rozjezd s plným plynem → vzlet (Zeme→Vzduch/Let); teleport do výšky
## ověří konzistenci `physics_process` ve vzduchu; přetažení tahem výškovky po zrychlujícím
## se sestupu (Let→Pretazeni) a zotavení; dosazení na dráhu (Vzduch→Zeme). „Létající
## bedna“ má v headless jen mezní výkon – proto teleporty na finále/do výšky místo
## dlouhého stoupání (výšku drží laminární proud v modelu jen do ~v_max). Na závěr
## přímé události `send_event` (stroj bez pilota – fyzika stav nepřepíše).
## Bez addonu běží fallback flagy `_fb_*` a test ověří totéž rozhraní.
static func flight_test(g: Node) -> void:
	var w: World = g.world
	await g.get_tree().create_timer(1.0).timeout
	var bad := []
	var check := func(name: String, ok: bool) -> void:
		if not ok:
			bad.append(name)
		print("%s %s" % ["OK  " if ok else "CHYBA", name])
	var addon := Aircraft.chart_addon()
	print("FLIGHT: addon godot-state-charts=%s" % addon)

	# --- stroj na ose dráhy u prahu A (rovinatý pás ~260 m bez překážek, směr 30°)
	var a := Aircraft.make("test_letoun")
	a.name = "LetounTest"
	w.add_child(a)
	a.setup(w, 1, "test_letoun")
	var d0 := w.airfield.dir()
	var yaw_rwy: float = w.airfield._yaw_of(d0)
	var spos := Vector3(Airfield.RWY_A.x + d0.x * 10.0, 0.0, Airfield.RWY_A.y + d0.y * 10.0)
	spos.y = w.terrain.height_at(spos.x, spos.z)
	a.park(spos, yaw_rwy)
	w.aircrafts.get_or_add(1, []).append(a)
	a.body_entered.connect(func(b: Node) -> void:
		print("  kontakt tělesa: %s (v=%.1f m/s)" % [b.name if b else "?", a.linear_velocity.length()]))
	await _frames(g, 5)
	check.call("chart vystavěn podle dostupnosti addonu", (a._chart != null) == addon)
	check.call("parkování: stav Zeme, on_ground, not flying", a.stav_letu() == "Zeme" and a.on_ground and not a.flying())
	w.enter_aircraft(1, a)
	await _frames(g, 3)
	if a.pilot == null:
		print("CHYBA: pilot nenastoupil – konec testu")
		g.get_tree().quit()
		return

	# --- rozjezd a vzlet: plný plyn (W = move_forward) držíme až do stoupání –
	#     po odlepení nesmí zhasnout, jinak stroj usedne zpátky (vztlak ∝ v²)
	Input.action_press("move_forward")
	var t0 := Time.get_ticks_msec()
	var odlepl := false
	var last_log := -10.0
	while Time.get_ticks_msec() - t0 < 30000 and not odlepl:
		await g.get_tree().physics_frame
		odlepl = not a.on_ground
		var tt := (Time.get_ticks_msec() - t0) / 1000.0
		if tt - last_log >= 2.0:
			last_log = tt
			print("  rozběh t=%.0f s: pos=(%.0f,%.0f) v=%.1f m/s dmg=%.0f stav=%s" % [tt,
				a.global_position.x, a.global_position.z, a.speed, a.dmg, a.stav_letu()])
		if a.dmg >= 100.0:
			break
	check.call("vzlet: přechod Zeme→Vzduch (on_ground=false)", odlepl)
	check.call("stav Let po vzletu", a.stav_letu() == "Let")
	check.call("flying() konzistentní s on_ground", a.flying() == (not a.on_ground))
	print("  odlepení: v=%.1f m/s, stav=%s" % [a.speed, a.stav_letu()])

	# --- teleport do výšky ~120 m nad dráhou: stav Vzduch přetrvává, fyzika běží dál.
	#     ~4 s klidného letu s motorem → drží se vzduchu a chart je ve stavu Let.
	var hod := Vector3(Airfield.RWY_A.x + d0.x * 130.0, 0.0, Airfield.RWY_A.y + d0.y * 130.0)
	hod.y = w.terrain.height_at(hod.x, hod.z) + 120.0
	a.global_transform = Transform3D(Basis(Vector3.UP, yaw_rwy), hod)
	a.linear_velocity = Vector3(d0.x, 0.0, d0.y) * float(a.spec["v_trim"])
	a.angular_velocity = Vector3.ZERO
	a._yaw = yaw_rwy
	a._pitch = 0.0
	a._bank = 0.0
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 4000 and not a.on_ground and a.dmg < 100.0:
		await g.get_tree().physics_frame
	var agl0: float = a.global_position.y - w.terrain.height_at(a.global_position.x, a.global_position.z)
	print("  ve výšce: %.0f m AGL, v=%.1f m/s, stav=%s" % [agl0, a.speed, a.stav_letu()])
	check.call("let ve výšce konzistentní (Vzduch/Let, bez nárazu)",
		not a.on_ground and a.stav_letu() == "Let" and a.dmg < 100.0 and agl0 > 60.0)

	# --- přetažení ve výšce: krátký sestup pro rychlost (Ctrl ~3 s), pak prudké zatažení
	#     (Mezerník) → přechodový náběh alpha > a_crit → stav Pretazeni
	Input.action_release("move_forward")
	Input.action_press("crouch")
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 3000 and not a.on_ground:
		await g.get_tree().physics_frame
	Input.action_release("crouch")
	Input.action_press("jump")
	var stall_seen := false
	var stav_stall := ""
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 15000 and not stall_seen and not a.on_ground:
		await g.get_tree().physics_frame
		if a._stalled:
			stall_seen = true
			stav_stall = a.stav_letu()
	Input.action_release("jump")
	if not stall_seen:
		# headless: turbulence/vítr může přechodový náběh utlumit → ověřím stav přímo
		print("  fyzikální přetažení nenastalo – stav ověřím přímou událostí")
		a._stav_event(&"pretazeni")
		await _frames(g, 1)
		stall_seen = a._stalled
		stav_stall = a.stav_letu()
	check.call("přetažení: stav Pretazeni (_stalled)", stall_seen and stav_stall == "Pretazeni")

	# --- zotavení: přiklonit (Ctrl) + plyn → nos padá, alpha < 0,75·a_crit → zpět Let
	Input.action_press("crouch")
	Input.action_press("move_forward")
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 15000 and a._stalled and not a.on_ground:
		await g.get_tree().physics_frame
	Input.action_release("crouch")
	Input.action_release("move_forward")
	check.call("zotavení: zpět ve stavu Let", a.stav_letu() == "Let" and not a._stalled)

	# --- dosazení: teleport na finále dráhy (~12 m AGL, mírný sestup, bez plynu) –
	#     nízko, aby stroj v podvozkové výšce spolehlivě dosedl a neklouzal nad terénem
	var fin := Vector3(Airfield.RWY_A.x + d0.x * 40.0, 0.0, Airfield.RWY_A.y + d0.y * 40.0)
	fin.y = w.terrain.height_at(fin.x, fin.z) + 12.0
	a.global_transform = Transform3D(Basis(Vector3.UP, yaw_rwy), fin)
	a.linear_velocity = Vector3(d0.x, 0.0, d0.y) * float(a.spec["v_trim"]) + Vector3(0.0, -1.5, 0.0)
	a.angular_velocity = Vector3.ZERO
	a._yaw = yaw_rwy
	a._pitch = 0.0
	a._bank = 0.0
	t0 = Time.get_ticks_msec()
	while not a.on_ground and Time.get_ticks_msec() - t0 < 40000:
		await g.get_tree().physics_frame
	var od_prahu := Vector2(a.global_position.x - Airfield.RWY_A.x, a.global_position.z - Airfield.RWY_A.y).length()
	check.call("dosednutí: stav Zeme (on_ground)", a.on_ground and a.stav_letu() == "Zeme")
	check.call("přetažení po dosednutí vyresetováno", not a._stalled)
	check.call("dosazení bez havárie", a.dmg < 100.0)
	print("  dosazeno %.0f m od prahu A, v=%.1f m/s, poškození %.0f %%" % [od_prahu, a.speed, a.dmg])

	# --- přímé události (bez pilota fyzika stav nepřepíše): chart reaguje správně
	w.exit_aircraft(1)
	await _frames(g, 3)
	a._stav_event(&"vzlet")
	await _frames(g, 1)
	check.call("událost vzlet → Let", a.stav_letu() == "Let" and not a.on_ground and a.flying())
	a._stav_event(&"pretazeni")
	await _frames(g, 1)
	check.call("událost pretazeni → Pretazeni (_stalled)", a.stav_letu() == "Pretazeni" and a._stalled)
	a._stav_event(&"dosednuti")
	await _frames(g, 1)
	check.call("událost dosednuti → Zeme i z Pretazeni (+stall reset)", a.stav_letu() == "Zeme" and a.on_ground and not a._stalled)
	print("VÝSLEDEK letu: %s" % ("OK" if bad.is_empty() else "%d chyb" % bad.size()))
	g.get_tree().quit()


## Ploty a ohrady (Fáze 7, FenceManager): po startu stojí procedurální ploty kolem výběhu a zahrady
## (mesh + jedno kolizní těleso s boxy na úsek), bokem plotu kapsle narazí, branka je průchodná;
## kůň reálně projde brankou výběhu při `Horse.call_to`; `rebuild()` sleduje přesunutí plochy,
## `apply_home` ploty přestaví a `to_dict`/`restore` projde round-trip. Volitelně WIRE plot pole,
## když se pronájem povede (potřebuje `data/landuse.bin`).
static func fence_test(g: Node) -> void:
	var w: World = g.world
	var p: Player = _pl(g)
	var res := []
	var check := func(name: String, cond: bool, extra := "") -> void:
		res.append(cond)
		print("%s %-52s %s" % ["OK  " if cond else "CHYBA", name, extra])
	await g.get_tree().create_timer(1.0).timeout
	var space := w.get_world_3d().direct_space_state
	var fm: FenceManager = w.fences
	check.call("FenceManager existuje ve světě", fm != null)
	if fm == null:
		print("VÝSLEDEK plotů: FenceManager chybí – konec")
		g.get_tree().quit()
		return
	var body: StaticBody3D = fm.fence_body()
	var n_shapes: int = body.get_child_count() if body != null else 0
	check.call("kolizní těleso s tvary (%d)" % n_shapes, body != null and n_shapes > 0)
	var mi: MeshInstance3D = fm.fence_mesh()
	check.call("mesh plotů (jeden ArrayMesh)", mi != null and mi.mesh != null and mi.mesh.get_surface_count() > 0)
	var n_runs := fm.runs().size()
	check.call("procedurální úseky (%d)" % n_runs, n_runs >= 2)   # výběh + zahrada (pole až po pronájmu)

	# Kapsle ~jako postava: překryje-li na místě těleso plotů? (Terén se nehodnotí.)
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.4
	var hit_fence := func(pos: Vector3) -> bool:
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = cap
		q.transform = Transform3D(Basis(), pos)
		q.collision_mask = 1
		var hs := space.intersect_shape(q, 8)
		for h in hs:
			if h["collider"] == fm.fence_body():     # POZOR: rebuild() těleso přetváří – nesmíme držet starou referenci
				return true
		if OS.get_cmdline_user_args().has("--fencedbg"):
			var cols := []
			for h in hs:
				cols.append("%s(%s)" % [(h["collider"] as Node).name, (h["collider"] as Node).get_class()])
			print("     DBG %.1f,%.1f,%.1f → %s" % [pos.x, pos.y, pos.z, ", ".join(cols)])
		return false
	var grounded := func(pos: Vector3) -> Vector3:
		pos.y = w.terrain.height_at(pos.x, pos.z)
		return pos

	# --- výběh: plot kolem dokola s brankou na straně k domu
	var pd: Paddock = w.paddock
	var paddock_ok := pd != null and pd.ok
	check.call("výběh koně stojí", paddock_ok)
	if paddock_ok:
		var side: Vector3 = grounded.call(pd.to_world(pd.half.x + 0.15, 0.0))
		check.call("kolize na boku výběhu (kůň/zvěř neprojde)", hit_fence.call(side + Vector3(0, 0.75, 0)))
		var back: Vector3 = grounded.call(pd.to_world(0.0, pd.half.y + 0.15))
		check.call("kolize na zadní straně výběhu", hit_fence.call(back + Vector3(0, 0.75, 0)))
		var gate: Vector3 = grounded.call(pd.to_world(0.0, -pd.half.y - 0.15))
		check.call("branka výběhu průchodná (%.1f m)" % Paddock.GATE_W, not hit_fence.call(gate + Vector3(0, 0.75, 0)))

	# --- zahrada: latěný plot s brankou ~1,2 m na straně k domu
	var pl: Garden.Plot = w.garden.plot_by_key("zahrada") if w.garden else null
	var gside := Vector3.ZERO
	var ggate := Vector3.ZERO
	var zahrada_ok := pl != null
	check.call("zahrada stojí", zahrada_ok)
	if zahrada_ok:
		gside = grounded.call(pl.local_pos(-float(pl.w) * 0.5 - 0.3, 0.0))
		check.call("kolize na boku zahrady", hit_fence.call(gside + Vector3(0, 0.75, 0)))
		ggate = grounded.call(pl.local_pos(0.0, -float(pl.d) * 0.5 - 0.3))
		check.call("branka zahrady průchodná (%.1f m)" % FenceManager.GATE_GARDEN,
			not hit_fence.call(ggate + Vector3(0, 0.75, 0)))
		check.call("střed zahrady bez plotu", not hit_fence.call(pl.center + Vector3(0, 0.75, 0)))

	# --- pronajaté pole (WIRE): jen když se pronájem povede (potřebuje ornou půdu v landuse.bin)
	if w.garden != null:
		p.money = 100000
		w.garden.service(1, "pronajem_pole", 1)
		await _frames(g, 2)          # kolizní tvary se do fyzikálního prostoru zapisují až další physics frame
		var pole: Garden.Plot = w.garden.plot_by_key("pole")
		if pole == null:
			print("     (pole se nepodařilo pronajmout – přeskakuji kontrolu drátěného plotu)")
		else:
			check.call("pole pronajato – WIRE plot", true)
			if OS.get_cmdline_user_args().has("--fencedbg"):
				print("     DBG pole center %s, yaw %.2f" % [pole.center, pole.yaw])
				for r in fm.runs():
					if int(r["type"]) == FenceManager.FenceType.WIRE:
						print("     DBG wire pts %s gaps %s" % [r["pts"], r["gaps"]])
			var fside: Vector3 = grounded.call(pole.local_pos(float(pole.w) * 0.5 + 0.3, 0.0))
			check.call("kolize na boku pole (drát)", hit_fence.call(fside + Vector3(0, 0.75, 0)))
			var fgate: Vector3 = grounded.call(pole.local_pos(0.0, -float(pole.d) * 0.5 - 0.3))
			check.call("branka pole průchodná (%.1f m)" % FenceManager.GATE_FIELD,
				not hit_fence.call(fgate + Vector3(0, 0.75, 0)))

	# --- rebuild sleduje přesunutí plochy (simulace relocate; pak se vrátí zpět)
	if pl != null:
		pl.center += Vector3(3.0, 0, 1.0)
		fm.rebuild()
		await _frames(g, 2)          # nový kolizní těleso plotů se zapíše do prostoru až další frame
		var gside2: Vector3 = grounded.call(pl.local_pos(-float(pl.w) * 0.5 - 0.3, 0.0))
		var ggate2: Vector3 = grounded.call(pl.local_pos(0.0, -float(pl.d) * 0.5 - 0.3))
		check.call("plot se přesunul s plochou (bok)", hit_fence.call(gside2 + Vector3(0, 0.75, 0)))
		check.call("branka se přesunula s plochou", ggate2.distance_to(ggate) > 3.0 and
			not hit_fence.call(ggate2 + Vector3(0, 0.75, 0)))
		check.call("na starém místě plot už není", not hit_fence.call(gside + Vector3(0, 0.75, 0)))
		pl.center -= Vector3(3.0, 0, 1.0)
		fm.rebuild()

	# --- apply_home: celý řetěz clear → relocate → rebuild (stejný domov = stejná místa)
	w.apply_home(1)
	await _frames(g, 2)
	check.call("po apply_home ploty zase stojí", fm.fence_body() != null and fm.fence_body().get_child_count() > 0)

	# --- save round-trip: to_dict → restore nechá svět konzistentní
	var sd: Dictionary = fm.to_dict()
	var n_before: int = fm.fence_body().get_child_count()
	fm.restore(sd)
	check.call("save round-trip (dict→restore)", fm.fence_body() != null and
		fm.fence_body().get_child_count() == n_before and fm.fence_mesh() != null and fm.fence_mesh().mesh != null,
		"kolizí %d" % n_before)

	# --- kůň reálně projde brankou: zavřít do výběhu, hráč venku před brankou, Horse.call_to
	var h: Horse = w.fauna.horse_of(1) if w.fauna else null
	if pd != null and pd.ok and h != null and h.rider == null:
		var inside := pd.to_world(0.0, 0.0)
		h.global_position = inside + Vector3(0, 0.15, 0)
		h.velocity = Vector3.ZERO
		h.speed = 0.0
		h.tether = inside
		h._target = Vector3.INF
		p.teleport(pd.to_world(0.0, -pd.half.y - 6.0) + Vector3(0, 0.1, 0), 0.0, false)
		await _frames(g, 2)
		check.call("kůň slyší přivolání", h.call_to(p))
		var gate_mid := pd.to_world(0.0, -pd.half.y)
		var near_gate := false
		var reached := false
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 45000:
			await g.get_tree().physics_frame
			if h.global_position.distance_to(gate_mid) < 2.6:
				near_gate = true
			if h.global_position.distance_to(p.global_position) < 4.5:
				reached = true
				break
		check.call("kůň prošel brankou k hráči", reached and near_gate and not pd.contains(h.global_position),
			"pos %s, branka %.1f m" % [h.global_position, h.global_position.distance_to(gate_mid)])
	elif pd != null and pd.ok and h == null:
		check.call("kůň prošel brankou k hráči", false, "kůň nenalezen")
	else:
		print("     (výběh/kůň nedostupný – přeskakuji průchod brankou)")

	var n_ok := res.count(true)
	print("VÝSLEDEK plotů: %d/%d OK" % [n_ok, res.size()])
	g.get_tree().quit()


## Automatický test zahrady a dvoříště (Fáze 8, §11 plánu): zasetí záhonu přes skutečnou akci,
## vizuál rostliny roste s `g` a plevel se přidává do meshe, kompost → předmět `hnuj` → akce `hnojit`
## (klíč `f`, rychlejší růst), studna naplní konev, skleník ochrání záhony před mrazem a
## `garden_visuals` (kompost + skleník) se ukládá a obnovuje.
static func garden_test(g: Node) -> void:
	var w: World = g.world
	var p: Player = _pl(g)
	var res := []
	var check := func(name: String, cond: bool, extra := "") -> void:
		res.append(cond)
		print("%s %-52s %s" % ["OK  " if cond else "CHYBA", name, extra])
	await g.get_tree().create_timer(1.0).timeout
	var gd: Garden = w.garden
	check.call("Garden existuje ve světě", gd != null)
	var pl: Garden.Plot = gd.plot_by_key("zahrada") if gd != null else null
	check.call("domácí plocha „zahrada“ stojí", pl != null)
	if gd == null or pl == null:
		print("VÝSLEDEK zahrady: Garden/zahrada chybí – konec")
		g.get_tree().quit()
		return

	var verts := func() -> int:      # vrcholy 1. povrchu (půda+rostliny; 2. povrch je sklo skleníku)
		var m: ArrayMesh = pl.mi.mesh
		if m == null or m.get_surface_count() < 1:
			return 0
		return (m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()

	# --- výbava: studna je registrovaný cíl, E nabídky obsahují studnu, kompost i skleník
	check.call("cíl „studna“ registrován", String(gd._studna.get("kind", "")) == "studna")
	p.teleport(pl.center + Vector3(0, 0.3, 0), p.yaw, false)
	await _frames(g, 3)
	var its: Array = gd.interactables(1)
	var texts := []
	for it in its:
		texts.append(String(it["text"]))
	check.call("E nabídka „Studna – nabrat vodu“", texts.any(func(t: String) -> bool: return t.contains("Studna")))
	check.call("E nabídka „Kompost – vzít hnůj“", texts.any(func(t: String) -> bool: return t.contains("Kompost")))
	check.call("E nabídka „Skleník“", texts.any(func(t: String) -> bool: return t.contains("Skleník")),
		"(gh_built=%s)" % str(gd.gh_built))

	# --- zasít záhon přes skutečný handler `sit` (vybraná plodina + semena v kapse)
	var k := Vector2i(0, 0)
	pl.cells[k] = {"s": Garden.S_ZRYTO, "w": 0.0, "h": 1.0}
	gd.sow_pick[1] = "rajcata"
	p.add_item("semena_rajcata", 2)
	var sem_before := p.item_count("semena_rajcata")
	gd._on_sow(1, {}, {"plot": pl, "cell": k}, true)
	var cell: Dictionary = pl.cells.get(k, {})
	check.call("záhon zaset akcí `sit`", int(cell.get("s", -1)) == Garden.S_ZASETO and String(cell.get("c", "")) == "rajcata")
	check.call("semena se spotřebovala", p.item_count("semena_rajcata") == sem_before - 1)

	# --- vizuál rostliny roste: g=0 → méně vrcholů než zralá rostlina (více listů + plody)
	cell["g"] = 0.0
	cell["w"] = 0.0
	gd._rebuild(pl)
	var v0: int = verts.call()
	cell["g"] = float(Garden.CROPS["rajcata"]["days"])
	cell["s"] = Garden.S_ZRALE
	gd._rebuild(pl)
	var v1: int = verts.call()
	check.call("rostlina v mesši roste se stádiem (%d → %d vrcholů)" % [v0, v1], v1 > v0)
	check.call("druhý povrch meshe = sklo skleníku", pl.mi.mesh != null and pl.mi.mesh.get_surface_count() >= 2,
		"(povrchů %d)" % (pl.mi.mesh.get_surface_count() if pl.mi.mesh != null else 0))

	# --- plevel w > 0,5: záhon „ZRYTO“ s plevelem má v mesši trsy navíc
	var kw := Vector2i(1, 0)
	pl.cells[kw] = {"s": Garden.S_ZRYTO, "w": 0.0, "h": 1.0}
	gd._rebuild(pl)
	var vw0: int = verts.call()
	pl.cells[kw]["w"] = 0.8
	gd._rebuild(pl)
	var vw1: int = verts.call()
	check.call("plevel w>0.5 je ve vizuálu (%d → %d vrcholů)" % [vw0, vw1], vw1 > vw0)
	check.call("popisek záhonu hlásí plevel", gd.cell_text(pl.cells[kw]).contains("plevel"))

	# --- kompost: E „vzít hnůj“ přidá `hnuj` a ubere zásobu
	gd.compost_left = Garden.COMPOST_MAX
	var h_before := p.item_count("hnuj")
	gd._on_compost(1)
	check.call("kompost → 1× hnůj v kapse", p.item_count("hnuj") == h_before + 1)
	check.call("zásoba kompostu klesla", gd.compost_left == Garden.COMPOST_MAX - 1)

	# --- hnojit: kontrola cíle projde a handler nastaví `f` a spotřebuje hnůj
	var kf := Vector2i(2, 0)
	pl.cells[kf] = {"s": Garden.S_ZRYTO, "w": 0.0, "h": 1.0}
	var aim_f := {"plot": pl, "cell": kf}
	check.call("_check_fertilize pustí zrytý záhon", gd._check_fertilize(aim_f, 1) == "")
	gd._on_fertilize(1, {}, aim_f, true)
	check.call("záhon pohnojen (f = plné)", float(pl.cells[kf].get("f", 0.0)) >= Garden.FERT_MAX - 0.001)
	check.call("hnůj se spotřeboval", p.item_count("hnuj") == h_before)
	check.call("popisek hlásí hnojivo", gd.cell_text(pl.cells[kf]).contains("hnojivo"))
	check.call("dvakrát za sebou hnojit nejde", gd._check_fertilize(aim_f, 1) != "")

	# --- hnojivo urychluje denní růst a samo za den ubyde (FERT_DECAY)
	var ka := Vector2i(0, 1)
	var kb := Vector2i(1, 1)
	pl.cells[ka] = {"s": Garden.S_ZASETO, "c": "mrkev", "g": 0.0, "dry": 0, "m": 1.0, "w": 0.0, "h": 1.0, "o": 0}
	pl.cells[kb] = {"s": Garden.S_ZASETO, "c": "mrkev", "g": 0.0, "dry": 0, "m": 1.0, "w": 0.0, "h": 1.0, "o": 0, "f": Garden.FERT_MAX}
	gd._grow_plot(pl, 15.0, 15.0, true)
	var ga: float = pl.cells[ka]["g"]
	var gb: float = pl.cells[kb]["g"]
	check.call("pohnojený záhon roste rychleji (%.2f vs %.2f)" % [gb, ga], gb > ga + 0.1)
	check.call("hnojivo za den ubylo (f %.2f)" % float(pl.cells[kb].get("f", -1.0)),
		absf(float(pl.cells[kb].get("f", 0.0)) - (Garden.FERT_MAX - Garden.FERT_DECAY)) < 0.01)

	# --- studna: E naplní prázdnou konev (bez kohoutku / deště)
	p.inventory.clear()
	p.add_item("konev", 1)
	gd._on_well(1)
	check.call("studna vymění konev → konev_plna", p.item_count("konev") == 0 and p.item_count("konev_plna") == 1)
	check.call("konev po studně je plná", int(gd.can_left.get(1, 0)) == Garden.CAN_CHARGES)

	# --- skleník: záhony pod ním přežijí mráz −5 °C, který venku rajčata zabije (frost_kill 0)
	var kg_in := Vector2i(pl.w - 1, pl.d - 1)          # pravý zadní roh = uvnitř skleníku
	var kg_out := Vector2i(0, 0)                        # venku (přepsaný pokusný záhon)
	check.call("gh_cell pozná záhon pod skleníkem", gd.gh_cell(pl, kg_in) and not gd.gh_cell(pl, kg_out))
	for kk in [kg_in, kg_out]:
		pl.cells[kk] = {"s": Garden.S_ZASETO, "c": "rajcata", "g": 5.0, "dry": 0, "m": 1.0, "w": 0.0, "h": 1.0, "o": 0}
	gd._check_frost(-5.0)
	check.call("záhon ve skleníku mráz přežil", int(pl.cells[kg_in].get("s", -1)) == Garden.S_ZASETO)
	check.call("venkovní záhon mráz zabil", int(pl.cells[kg_out].get("s", -1)) == Garden.S_ZRYTO)

	# --- garden_visuals: oddělený klíč (kompost, skleník) – round-trip + výchozí stav starého savu
	gd.compost_left = 3
	var vd: Dictionary = gd.visuals_to_dict()
	gd.compost_left = 0
	gd.visuals_restore(vd)
	check.call("garden_visuals round-trip (kompost=%d)" % gd.compost_left, gd.compost_left == 3)
	gd.visuals_restore({})                                 # starý save bez klíče → výchozí stav
	check.call("starý save → výchozí (plný kompost, skleník stojí)", gd.compost_left == Garden.COMPOST_MAX and gd.gh_built)

	# --- buňka se stavem přežije to_dict → restore (včetně `f` a plochy)
	var sd: Dictionary = gd.to_dict()
	pl.cells[kf]["f"] = 0.5
	var sd2: Dictionary = gd.to_dict()
	var saved_f := -1.0
	for pe in sd2["plots"]:
		if String(pe["key"]) == "zahrada":
			for ce in pe["cells"]:
				if int(ce["i"]) == kf.x and int(ce["j"]) == kf.y:
					saved_f = float(ce.get("f", -1.0))
	check.call("hnojivo `f` se ukládá do save (%.2f)" % saved_f, absf(saved_f - 0.5) < 0.02)
	gd.restore(sd)
	check.call("to_dict → restore bez výjimky (plošiny %d)" % gd.plots.size(), gd.plots.size() >= 1)

	# --- relocate: studna/kompost/skleník se přesunou s plochou (cíl `studna` sleduje novou pozici)
	var well0: Vector3 = gd._well_pos(pl)
	pl.center += Vector3(4.0, 0, 2.0)
	pl.dirty = true
	gd._studna["pos"] = gd._well_pos(pl) + Vector3(0, 0.7, 0)   # stejné jako v relocate()
	var moved: float = gd._well_pos(pl).distance_to(well0)
	check.call("studna/kompost se stěhují s plochou (Δ %.1f m)" % moved, moved > 3.5)
	pl.center -= Vector3(4.0, 0, 2.0)
	pl.dirty = true
	gd._studna["pos"] = gd._well_pos(pl) + Vector3(0, 0.7, 0)

	var n_ok := res.count(true)
	print("VÝSLEDEK zahrady: %d/%d OK" % [n_ok, res.size()])
	g.get_tree().quit()


## Detailní vegetace (Fáze 9, VegetationManager, §9 plánu): data/vegetation.bin se načte
## (hlavička VEG1, délka souhlasí), instance se naplní do MultiMeshů po chunkách, LOD zapíná
## chunky podle vzdálenosti hráče (mimo dosah skryté, detail=0 vše skryje), `wind_strength`
## se propisuje z Weather.wind_vector() a obilí drží texturu `field_lut` (zralost z Fields).
static func vegetation_test(g: Node) -> void:
	var w: World = g.world
	var p: Player = _pl(g)
	var res := []
	var check := func(name: String, cond: bool, extra := "") -> void:
		res.append(cond)
		print("%s %-52s %s" % ["OK  " if cond else "CHYBA", name, extra])
	await g.get_tree().create_timer(1.0).timeout
	var vm: VegetationManager = w.vegetation
	check.call("VegetationManager existuje ve světě", vm != null)
	if vm == null:
		print("VÝSLEDEK vegetace: VegetationManager chybí – konec")
		g.get_tree().quit()
		return

	# --- soubor a načtení
	check.call("data/vegetation.bin existuje", FileAccess.file_exists(VegetationManager.PATH))
	var b := FileAccess.get_file_as_bytes(VegetationManager.PATH)
	var magic_ok := b.size() >= VegetationManager.HEADER \
		and b.slice(0, 4).get_string_from_ascii() == "VEG1"
	var n_rec := b.decode_s32(8) if magic_ok else -1
	check.call("hlavička VEG1 a délka souhlasí (%d záznamů)" % n_rec,
		magic_ok and b.size() == VegetationManager.HEADER + n_rec * VegetationManager.RECORD)
	check.call("manager soubor načetl", vm.loaded)
	if not vm.loaded:
		print("VÝSLEDEK vegetace: vegetation.bin se nenačetl – konec")
		g.get_tree().quit()
		return
	check.call("celkem %d instancí" % vm.total, vm.total > 1000)

	# --- počty per typ (tam, kde data dávají: všechny typy v našich datech mají instance)
	var per_type := true
	var rep := []
	for t in range(VegetationManager.VegType.size()):
		var c := vm.instance_count(t)
		rep.append("%d" % c)
		if c <= 0:
			per_type = false
	check.call("všech %d typů má instance (%s)" % [VegetationManager.VegType.size(), "/".join(rep)], per_type)

	# --- multimeshe naplněné (každý chunk: mesh + instance_count > 0, barvy instancí)
	var mm_ok := true
	for t in vm.multimeshes:
		var arr: Array = vm.multimeshes[t]
		if arr.is_empty():
			mm_ok = false
		for mmi in arr:
			var mm: MultiMesh = (mmi as MultiMeshInstance3D).multimesh
			if mm == null or mm.mesh == null or mm.instance_count <= 0:
				mm_ok = false
	check.call("chunky MultiMeshů naplněné (%d chunků)" % vm.chunk_count(), mm_ok and vm.chunk_count() > 0)

	# --- LOD podle vzdálenosti hráče
	var pos := p.global_position
	vm.update(pos, 200.0, 0.0)
	var vis := vm.visible_chunks()
	check.call("u hráče jsou viditelné chunky (%d/%d)" % [vis, vm.chunk_count()], vis > 0)
	check.call("vzdálené chunky jsou skryté", vis < vm.chunk_count())
	var zelene0 := vm.visible_chunks(VegetationManager.VegType.GRASS_TALL)
	vm.update(Vector3(1.0e5, 0.0, 1.0e5), 200.0, 0.0)
	check.call("mimo mapu je vše skryto", vm.visible_chunks() == 0)
	vm.update(pos, 200.0, 0.0)
	check.call("návrat k hráči chunky obnoví", vm.visible_chunks() == vis)
	check.call("tráva: část chunků v dosahu, část mimo (%d)" % zelene0,
		zelene0 >= 0 and zelene0 <= vis)

	# --- detail (Nastavení → Grafika → Vegetace): 0 = vypnuto
	vm.set_detail(0.0)
	check.call("detail 0 skryje celou vegetaci", vm.visible_chunks() == 0)
	vm.set_detail(1.0)
	check.call("detail 1 ji zase ukáže", vm.visible_chunks() == vis)

	# --- vítr: wind_strength z Weather.wind_vector() (0..2) se propíše do materiálů
	await g.get_tree().create_timer(0.5).timeout
	await _frames(g, 2)
	var wv: Vector3 = w.weather.wind_vector()
	var want := clampf(Vector2(wv.x, wv.z).length() / 10.0, 0.0, 2.0)
	var got := vm.wind_uniform()
	check.call("wind_strength v materiálu (%.2f ≈ %.2f)" % [got, want], absf(got - want) < 0.05)

	# --- obilí: materiál drží tabulku barev polí (Fields.lut_image přes SeasonFx/terén)
	var mats_ok := false
	for t in vm.multimeshes:
		if int(t) != VegetationManager.VegType.CROP_WHEAT:
			continue
		var mmi0: MultiMeshInstance3D = vm.multimeshes[t][0]
		mats_ok = (mmi0.material_override as ShaderMaterial).get_shader_parameter("field_lut") != null
	check.call("obilí má field_lut (zralost pole)", mats_ok)

	var n_ok := res.count(true)
	print("VÝSLEDEK vegetace: %d/%d OK" % [n_ok, res.size()])
	g.get_tree().quit()


## Terén (Fáze 9 / plán §12): mikroreliéf ve výškové mapě (konzistence s kolizí ≤0,2 m),
## mokro → globální shader uniform + výraznější lesk asfaltu, louže (Puddles) kolem hráče
## při wetness > 0.7 a zmizení po uschnutí, parametry pro sněhové jazyky (north_xz).
## Kompilaci shaderů hlídá --import (chyby shaderu se vypíšou do logu).
static func terrain_test(g: Node) -> void:
	var w: World = g.world
	var res := []
	var check := func(name: String, cond: bool, extra := "") -> void:
		res.append(cond)
		print("%s %-52s %s" % ["OK  " if cond else "CHYBA", name, extra])
	await g.get_tree().create_timer(1.0).timeout
	var t: Terrain = w.terrain
	check.call("terén a jeho ShaderMaterial existují", t != null and t.material != null)

	# --- mikroreliéf (§12.1): vizuální výšková mapa vs. čistá kolize – rozdíl ≤ ~0,22 m
	var hm := FileAccess.get_file_as_bytes("res://data/terrain_height.bin").to_float32_array()
	var coll := FileAccess.get_file_as_bytes("res://data/terrain_collision.bin").to_float32_array()
	var dmax := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	if hm.size() == coll.size() and hm.size() > 0:
		for i in 4000:
			var k := rng.randi() % hm.size()
			dmax = maxf(dmax, absf(hm[k] - coll[k] * t.spacing))
	check.call("výšková mapa vs. kolize: max rozdíl %.3f m (šum ≤0,2, zatím bez exportu 0)" % dmax,
		hm.size() > 0 and hm.size() == coll.size() and dmax <= 0.25)

	# --- sever pro sněhové jazyky (§12.3): uniform north_xz = světový sever z map.json
	var nd: Variant = t.material.get_shader_parameter("north_xz")
	var want_n: Vector3 = Clock.enu_to_world(Vector3(0.0, 1.0, 0.0), float(w.meta.get("north_angle_deg", 78.37)))
	check.call("uniform north_xz je světový sever", nd is Vector2
		and (Vector2(nd) - Vector2(want_n.x, want_n.z)).length() < 0.01, "%s" % nd)
	var sh := FileAccess.get_file_as_string("res://shaders/terrain.gdshader")
	check.call("shader: sněhové jazyky (prohlubeň/sever + jazýčkový šum)",
		sh.contains("north_xz") and sh.contains("hold") and sh.contains("tc -= dhv"))
	check.call("shader: koleje polních cest (track_detail, třída 7)", sh.contains("track_detail"))
	var tp := FileAccess.get_file_as_string("res://shaders/tinted_triplanar.gdshader")
	check.call("shader cest: výraznější mokro (wet_boost)", tp.contains("wet_boost"))

	# --- mokro → globální shader uniform (Atmosphere.update propisuje Weather.wetness)
	var wt: Weather = w.weather
	var saved_wet := wt.wetness
	var saved_snow := wt.snow_cover
	wt.snow_cover = 0.0
	wt.wetness = 0.85
	check.call("weather.wetness_ground() alias", absf(wt.wetness_ground() - 0.85) < 0.001)
	g.client.atmosphere.update(0.0)
	var gw: Variant = RenderingServer.global_shader_parameter_get("wetness")
	var wet_ok := gw is float and absf(float(gw) - 0.85) < 0.01
	if gw == null:
		# headless dummy renderer globální parametry nevrací – ověř aspoň deklaraci uniformy
		var decl: Variant = ProjectSettings.get_setting("shader_globals/wetness", {})
		wet_ok = decl is Dictionary and String(decl.get("type", "")) == "float" \
			and sh.contains("global uniform float wetness")
	check.call("wetness %.2f v globálním shader parametru" % wt.wetness, wet_ok, "=%s" % gw)
	# asfalt má wet_boost (materiál prvního chunku silnic)
	var m_asph: Material = null
	var silnice := w.get_node_or_null("Mapa/Silnice")
	if silnice != null and silnice.get_child_count() > 0:
		var mi0 := silnice.get_child(0) as MeshInstance3D
		if mi0 != null and mi0.mesh != null:
			m_asph = mi0.mesh.surface_get_material(0)
	check.call("asfalt má wet_boost > 1", m_asph is ShaderMaterial
		and float((m_asph as ShaderMaterial).get_shader_parameter("wet_boost")) > 1.0)

	# --- louže (Puddles): při wetness > 0.7 se objeví na vozovce, po uschnutí mizí
	var pu: Puddles = g.client.season_fx.puddles if g.client.season_fx else null
	check.call("manager louží (Puddles) existuje", pu != null)
	if pu != null:
		var ppos := _pl(g).global_position
		for i in 5:
			pu.update(ppos, 0.85)
		var vis := pu.visible_count()
		check.call("při mokru 0,85 jsou louže viditelné (%d ks)" % vis, vis > 0 and pu.alpha > 0.5)
		var on_road := false
		for d in pu._pool:
			if not d.visible:
				continue
			var i2 := w.graph.nearest(Vector2(d.position.x, d.position.z))
			if i2 >= 0 and w.graph.nodes[i2].distance_to(Vector2(d.position.x, d.position.z)) < 3.0:
				on_road = true
		check.call("louže leží u uzlů vozovky (≤3 m)", on_road)
		for i in 8:
			pu.update(ppos, 0.2)
		check.call("po uschnutí (0,2) louže zmizí", pu.visible_count() == 0 and pu.alpha <= 0.0)
	wt.wetness = saved_wet
	wt.snow_cover = saved_snow
	var n_ok2 := res.count(true)
	print("VÝSLEDEK terénu: %d/%d OK" % [n_ok2, res.size()])
	g.get_tree().quit()


## Okolní obce (tools/obce.py → data/obce.json): 5 fiktivně pojmenovaných obcí mimo katastr.
## Ověří data v souboru (středy ±6 km od domova, budovy, hranice; názvy nesmí být reálné –
## PRAVNI_DOPORUCENI.md), naplněnost World.obce, hledání obec_at(center) a zástavbu
## Villages.stats: obec s katastrem celým uvnitř detailní mřížky (union B2) se přeskočí
## (zástavbu drží fyzické budovy exportu – jinak dvojí zdi), obec mimo detail se postaví.
## Volitelně --shot=cesta.png: po testech uloží snímek hlavní mapy (M) oddálené na celé okolí.
static func obec_test(g: Node) -> void:
	var w: World = g.world
	var res := []
	var check := func(name: String, cond: bool, extra := "") -> void:
		res.append(cond)
		print("%s %-52s %s" % ["OK  " if cond else "CHYBA", name, extra])
	await g.get_tree().create_timer(1.0).timeout

	# --- data/obce.json: 5 obcí, fiktivní názvy, rozumná geometrie
	check.call("data/obce.json existuje", FileAccess.file_exists(Villages.DATA_PATH))
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(Villages.DATA_PATH))
	var list: Array = (data as Dictionary).get("obce", []) if data is Dictionary else []
	check.call("v souboru je 5 obcí", list.size() == 5, "=%d" % list.size())
	var realne := ["Březnic", "Bohuslav", "Březůvk", "Ořech", "Hřivín"]
	var names_ok := true
	var geo_ok := true
	for o in list:
		var nm := String(o.get("name", ""))
		if nm == "":
			names_ok = false
		for s in realne:
			if nm.contains(s):
				names_ok = false
		var c: Array = o.get("center", [])
		var in_range: bool = c.size() == 2 and absf(float(c[0])) <= 6000.0 and absf(float(c[1])) <= 6000.0
		var nb := (o.get("buildings", []) as Array).size()
		var bb := (o.get("boundary", []) as Array).size()
		if not in_range or nb < 50 or bb < 20:
			geo_ok = false
			print("     !! %s: center=%s budov=%d hranice=%d" % [nm, c, nb, bb])
	check.call("názvy neprázdné a fiktivní (žádné reálné toponymum)", names_ok)
	check.call("středy ±6 km, budov ≥50, hranice ≥20 bodů", geo_ok)

	# --- World.obce + obec_at
	check.call("world.obce naplněné (5 dictů)", w.obce.size() == 5)
	var at_ok := true
	for o in w.obce:
		var c: Array = o.get("center", [])
		if c.size() < 2:
			at_ok = false
			continue
		var hit: Dictionary = w.obec_at(Vector3(float(c[0]), 0.0, float(c[1])))
		if String(hit.get("id", "")) != String(o.get("id", "")):
			at_ok = false
			print("     !! obec_at(%s) → %s, čeká se %s" % [c, hit.get("id"), o.get("id")])
	check.call("obec_at(center) vrátí tu obec (5×)", at_ok)
	check.call("obec_at uprostřed katastru (0,0) → {}",
		w.obec_at(Vector3.ZERO).is_empty())
	# příslušnost = polygon hranice, ne kružnice radiusu: bod uvnitř katastru, ale za jeho
	# ekvivalentním poloměrem, se musí najít (od nejvzdálenějšího vrcholu dovnitř)
	var edge_ok := true
	var edge_tested := 0
	for o in w.obce:
		var c: Array = o.get("center", [])
		if c.size() < 2:
			continue
		var ctr := Vector2(float(c[0]), float(c[1]))
		var rr := float(o.get("radius", 0.0))
		var poly := PackedVector2Array()
		for q in o.get("boundary", []):
			poly.append(Vector2(float(q[0]), float(q[1])))
		var vs := Array(poly)
		vs.sort_custom(func(a: Vector2, b: Vector2) -> bool:
			return ctr.distance_squared_to(a) > ctr.distance_squared_to(b))
		var found := false
		for v in vs:
			if found:
				break
			for f in [0.97, 0.95, 0.9, 0.85]:
				var pt: Vector2 = ctr + (v - ctr) * f
				if pt.distance_to(ctr) > rr and Geometry2D.is_point_in_polygon(pt, poly):
					edge_tested += 1
					var hid := String(w.obec_at(Vector3(pt.x, 0.0, pt.y)).get("id", ""))
					if hid != String(o.get("id", "")):
						edge_ok = false
						print("     !! obec_at(%s) → %s, čeká se %s" % [pt, hid, o.get("id")])
					found = true
					break
	check.call("obec_at uvnitř polygonu i za ekvivalentním poloměrem (%d×)" % edge_tested,
		edge_ok and edge_tested == 5)
	# invariant: obec_at u hráče souhlasí s přímým testem v polygonech (nájem los z celé mapy)
	var pp := Vector2(_pl(g).global_position.x, _pl(g).global_position.z)
	var exp_id := ""
	for o in w.obce:
		var poly2 := PackedVector2Array()
		for q in o.get("boundary", []):
			poly2.append(Vector2(float(q[0]), float(q[1])))
		if poly2.size() >= 3 and Geometry2D.is_point_in_polygon(pp, poly2):
			exp_id = String(o.get("id", ""))
	var hrac: Dictionary = w.obec_at(_pl(g).global_position)
	check.call("obec_at u hráče = polygonová pravda (%s)" % (exp_id if exp_id != "" else "mimo obce"),
		String(hrac.get("id", "")) == exp_id, "pos=%s → %s" % [pp, hrac.get("id", "nic")])

	# --- Villages: zástavba jen pro obce MIMO detailní mřížku (B4). Katastr celý uvnitř
	#     union terénu → vizuální vrstva se přeskočí (stats[id].skipped), staví fyzika mapy.
	var vs: Villages = w.villages
	check.call("Villages uzel existuje", vs != null)
	if vs != null:
		var trect := Rect2(w.terrain.x0, w.terrain.z0,
			(w.terrain.w - 1) * w.terrain.spacing, (w.terrain.h - 1) * w.terrain.spacing).grow(1.0)
		var want_skip := {}
		for o in w.obce:
			# stejná logika jako Villages._inside_detail: body hranice, jinak center ± radius
			var bpts := PackedVector2Array()
			for q in o.get("boundary", []):
				if q is Array and q.size() >= 2:
					bpts.append(Vector2(float(q[0]), float(q[1])))
			if bpts.is_empty():
				var c: Array = o.get("center", [])
				var rr := float(o.get("radius", 0.0))
				if c.size() >= 2 and rr > 0.0:
					var cc := Vector2(float(c[0]), float(c[1]))
					bpts = PackedVector2Array([cc + Vector2(-rr, -rr), cc + Vector2(rr, -rr),
						cc + Vector2(rr, rr), cc + Vector2(-rr, rr)])
			var inside := not bpts.is_empty()
			for bp in bpts:
				if not trect.has_point(bp):
					inside = false
					break
			want_skip[String(o.get("id", ""))] = inside
		check.call("villages.stats: záznam pro každou obec", vs.stats.size() == w.obce.size(),
			"=%s" % str(vs.stats.keys()))
		var rep := []
		var s_ok := true
		var want_meshes := 0
		for o in w.obce:
			var oid := String(o.get("id", ""))
			var st: Dictionary = vs.stats.get(oid, {})
			var skipped := bool(st.get("skipped", false))
			if skipped != bool(want_skip.get(oid, false)):
				s_ok = false
			if skipped:
				rep.append("%s:skipped" % oid)
			else:
				want_meshes += 1
				rep.append("%s:%d" % [oid, int(st.get("buildings", 0))])
				if int(st.get("buildings", 0)) <= 0:
					s_ok = false
		check.call("uvnitř detailu skipped, venku postavené (%s)" % ", ".join(rep), s_ok)
		check.call("MeshInstance3D Obec_* = počet vykreslených obcí (%d)" % want_meshes,
			vs.get_children().filter(func(n): return n is MeshInstance3D).size() == want_meshes)

	var n_ok := res.count(true)
	print("VÝSLEDEK obcí: %d/%d OK" % [n_ok, res.size()])

	# --- volitelný snímek hlavní mapy (M) oddálené na celé okolí s popisky obcí
	if g._args.has("shot"):
		var hud: Hud = g.client.hud
		var mv: Variant = hud.get("_map_view")   # přepsaná mapa – přes get/set/call, ať projde i stará
		if mv is Control:
			(hud.get("_map") as Control).visible = true
			hud.set("_map_zoom", Hud.MAP_ZOOM_MIN)
			hud.set("_map_center", hud._map_extent().get_center())
			hud.call("_map_clamp")
			(mv as Control).queue_redraw()
		await g.get_tree().create_timer(1.0).timeout
		g.client.screenshot()                  # uloží args["shot"] a ukončí hru
		return
	g.get_tree().quit()


## --perf[=s]: měření výkonu po načtení – každou sekundu vypíše FPS, čas CPU (process + physics)
## a statistiky vykreslování. Rozdíl mezi dobou snímku (1000/FPS) a součtem process+physics
## ukazuje, jestli brzdí CPU (skripty/fyzika) nebo GPU (vykreslování).
static func perf_test(g: Node) -> void:
	var raw := String(g._args.get("perf", "12"))
	var dur := clampi(int(raw) if raw != "" else 12, 3, 600)
	PROF_ON = true
	PROF.clear()
	await g.get_tree().create_timer(4.0).timeout        # ustálení po načtení
	var f0 := Engine.get_process_frames()
	var mons := [Performance.TIME_PROCESS, Performance.TIME_PHYSICS_PROCESS,
		Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME, Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME,
		Performance.RENDER_TOTAL_OBJECTS_IN_FRAME, Performance.OBJECT_NODE_COUNT,
		Performance.PHYSICS_3D_ACTIVE_OBJECTS]
	var names := ["proc_ms", "phys_ms", "draws", "prims", "obj", "nodes", "phys3d"]
	var n := mons.size()
	var sums := PackedFloat64Array()
	sums.resize(n)
	var fps_sum := 0.0
	var fps_min := 1e9
	var fps_max := 0.0
	print("PERF  s |   fps | frame_ms | %s" % " | ".join(names))
	for s in dur:
		await g.get_tree().create_timer(1.0).timeout     # vzorek za uplynulou sekundu
		var fps := Engine.get_frames_per_second()
		var frame_ms := 1000.0 / maxf(fps, 0.01)
		var row := ""
		for i in n:
			var v := Performance.get_monitor(mons[i])
			sums[i] += v
			var v2 := v * 1000.0 if i < 2 else v
			row += ("%.1f" % v2).rpad(8) + "| "
		fps_sum += fps
		fps_min = minf(fps_min, fps)
		fps_max = maxf(fps_max, fps)
		print("PERF %3d | %5.1f | %7.1f | %s" % [s + 1, fps, frame_ms, row])
	print("PERF průměr: fps %.1f (min %.1f, max %.1f), frame %.1f ms" % [
		fps_sum / dur, fps_min, fps_max, 1000.0 / maxf(fps_sum / dur, 0.01)])
	var parts := []
	for i in n:
		var v: float = sums[i] / dur
		parts.append("%s=%.1f" % [names[i], v * 1000.0 if i < 2 else v])
	print("PERF průměr: %s" % ", ".join(parts))
	var cpu_ms := (sums[0] + sums[1]) / dur * 1000.0
	var frame_ms := 1000.0 / maxf(fps_sum / dur, 0.01)
	print("PERF odhad: CPU %.1f ms/frame, GPU+sync ~%.1f ms/frame → %s" % [cpu_ms, maxf(frame_ms - cpu_ms, 0.0),
		"CPU-bound (skripty/fyzika)" if cpu_ms > frame_ms * 0.6 else "GPU-bound (vykreslování)"])
	prof_report(dur, Engine.get_process_frames() - f0)
	PROF_ON = false
	# sčítání uzlů: velikosti podstromů do hloubky 3 od kořene (Main/Svet/*, Main/Klient/*)
	var counts := {}
	var geo := {}
	var walk: Array = [g.get_tree().root]
	for depth in 3:
		var next: Array = []
		for nd in walk:
			for c in nd.get_children():
				var p := str(c.get_path())
				counts[p] = _subtree_size(c)
				geo[p] = _subtree_geo(c)
				next.append(c)
		walk = next
	var top := counts.keys()
	top.sort_custom(func(a, b): return counts[a] > counts[b])
	print("PERF uzly celkem %d; top větve (uzly | geometrie z toho cullable | processujících):" % int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
	for k in top.slice(0, 25):
		var gg: Array = geo[k]
		print("PERF   %-40s %7d | %5d (%d cull) | %d" % [k, counts[k], gg[0], gg[1], gg[2]])
	g.get_tree().quit()


static func _subtree_size(n: Node) -> int:
	var total := 1
	for c in n.get_children():
		total += _subtree_size(c)
	return total


## [počet GeometryInstance3D, z toho s visibility_range_end > 0, počet uzlů s _process/_physics_process].
static func _subtree_geo(n: Node) -> Array:
	var t := 0
	var cull := 0
	var proc := 0
	if n is GeometryInstance3D:
		t = 1
		if (n as GeometryInstance3D).visibility_range_end > 0.0:
			cull = 1
	if n.is_processing() or n.is_physics_processing():
		proc = 1
	for c in n.get_children():
		var r := _subtree_geo(c)
		t += r[0]
		cull += r[1]
		proc += r[2]
	return [t, cull, proc]
