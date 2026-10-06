## Policie: hlídkový vůz jezdící po hlavních silnicích + silniční kontrola (vůz s majáky a policista
## u krajnice). Všímá si řidičů (hráčů): rychlost, kličkování v opilosti, nehody, náhodná kontrola.
## Pronásleduje a kontroluje vždy jednoho konkrétního hráče (`target` / `_stop_player`);
## zákaz řízení a pátrání jsou vlastnosti hráče (Player.license_suspended_until, wanted_until).
## Pronásledování se sirénou (trasa po silnicích, zblízka přímo), zastavení → policista dojde
## k okénku řidiče (u kontroly ze stanoviště, jinak vystoupí z hlídkového vozu), podá alkohol-tester
## → dechová zkouška → vrátí se zpět.
## V ČR platí nulová tolerance; hodnoty do 0,24 ‰ se kvůli přesnosti přístroje netrestají.
class_name Police
extends Node3D

signal busted(player_id: int, promile: float, reason: String)
signal test_passed(player_id: int, promile: float)
signal escaped(player_id: int)

enum State { PATROL, CHASE, STOPPING, CHECKPOINT }

var traffic: Traffic
var graph: RoadGraph
var terrain: Terrain
var world: Node                     # World – hráči, zprávy hráčům, události
var clock: Clock

var patrol: Car
var patrol_state := State.PATROL
var checkpoint_car: Car
var checkpoint_cop: Npc
var checkpoint_pos := Vector3.INF
var checkpoint_seen := {}           # id hráče → true: ví o silniční kontrole (viděl / slyšel drb)
var chaser: Car
var target: Player                  # pronásledovaný hráč
var last_test_promile := -1.0

var _route_t := 0.0
var _suspicion := {}                # id hráče → podezření 0..1
var _crash_t := {}                  # id hráče → herní minuta poslední nehody zapsané svědkem (M4.4)
const CRASH_CD_MIN := 60.0          # herních minut mezi nehodami ze svědectví (série nárazů = jedna nehoda)
const CRASH_NO_OFFENSE := ["silnice", "cesta", "terén"]   # pád / náraz do povrchu – bez cizí škody, bez přestupku
var _lost_t := 0.0
var _stop_t := 0.0
var _cp_state := 0                  # 0 nic, 1 hráč se blíží, 2 minul blízko
var _cp_player: Player              # řidič, kterého silniční kontrola právě řeší
var _cp_min_d := INF
var _rng := RandomNumberGenerator.new()
var _checked_recently := 0.0
var _cop_walk: Npc
# policista, který jde k okénku: fáze 0 jde, 1 u okénka s testerem
var _stop_cop: Npc
var _stop_player: Player             # kontrolovaný hráč
var _stop_cop_temp := false          # vystoupil z hlídkového vozu (po kontrole zase nastoupí)
var _stop_car: Car                   # vůz, ze kterého vystoupil
var _stop_phase := 0
var _stop_context := ""
var _stop_plan := "ok"               # co policista u okénka udělá: "test" dech, "ticket" pokuta, "ok" jen doklady
var _viol := {}                      # id hráče → nejzávažnější zjištěný přestupek {id, sev, t} (herní minuty)
var _returning: Array = []           # [npc, dočasný?, vůz | null, stanoviště, směr]
var _cp_post := Vector3.INF
var _cp_yaw := 0.0
const COP_WALK := 1.7                # m/s


func setup(t: Traffic, g: RoadGraph, ter: Terrain, w: Node, c: Clock) -> void:
	traffic = t
	graph = g
	terrain = ter
	world = w
	clock = c
	_rng.randomize()


func _banner(p: Player, text: String, dur := 4.0) -> void:
	if p and is_instance_valid(p):
		world.notify(p.id, "police_banner", [text, dur])


func _valid(p: Player) -> bool:
	return p != null and is_instance_valid(p) and world.players.get(p.id) == p


## Nejbližší hráč, který řídí (sedí za volantem), nebo null.
func _nearest_driver(pos: Vector3) -> Player:
	var best: Player = null
	var bd := INF
	for p in world.players.values():
		if p.car:
			var d: float = p.global_position.distance_squared_to(pos)
			if d < bd:
				bd = d
				best = p
	return best


func spawn_patrol() -> void:
	patrol = traffic.make_car("octavia", Color(0.88, 0.9, 0.93), true, "POLICIE")
	patrol.name = "Policie_hlidka"
	_new_patrol_route(true)


func _new_patrol_route(first := false) -> void:
	var a := graph.astar(RoadGraph.CAR_KINDS)
	var ends := graph.astar(RoadGraph.END_KINDS)     # start / cíl ne na účelové cestě (vjezd do dvora)
	var near: Node3D = null if first else world.nearest_player(patrol.global_position)
	var anchor: Vector3 = world.player_world_pos(near as Player) if near else world.player_anchor(0)
	var pp := Vector2(anchor.x, anchor.z)
	var far: bool = first or near == null or patrol.global_position.distance_to(anchor) > 700.0
	for attempt in 20:
		var ang := _rng.randf() * TAU
		var s: int
		if far:
			s = ends.get_closest_point(pp + Vector2(cos(ang), sin(ang)) * _rng.randf_range(250.0, 600.0))
			if s < 0 or not a.has_point(s):
				continue
		else:
			s = a.get_closest_point(Vector2(patrol.global_position.x, patrol.global_position.z))
		var e := ends.get_closest_point(graph.nodes[s] + Vector2(cos(ang + 1.0), sin(ang + 1.0)) * _rng.randf_range(600.0, 1500.0))
		if e < 0 or not a.has_point(e):
			continue
		var ids := a.get_id_path(s, e)
		if ids.size() < 6:
			continue
		var pts := graph.lane_points(ids, terrain)
		if far:
			var d := Vector2(pts[1].x - pts[0].x, pts[1].z - pts[0].z)
			traffic.place_car(patrol, Vector2(pts[0].x, pts[0].z), atan2(d.x, d.y))
		patrol.set_ai_route(pts, 15.0)
		if not far:
			patrol.reroute(pts)       # jede odtud, kde stojí – body za autem přeskočit
		return


## Silniční kontrola na silnici v bodě `pos` (x, z) – vůz u krajnice, policista na kraji vozovky.
func set_checkpoint(pos: Vector2) -> void:
	clear_checkpoint()
	var a := graph.astar(RoadGraph.CAR_KINDS)
	var n := a.get_closest_point(pos)
	var nb: Array = graph.adj[n]
	var d := Vector2(0, 1)
	if nb.size() >= 2:
		# tečna silnice v uzlu (ne jen směr k jednomu sousedovi – v zatáčce by vůz stál v pruhu)
		d = ((graph.nodes[nb[0]] - graph.nodes[n]).normalized() - (graph.nodes[nb[1]] - graph.nodes[n]).normalized())
		d = d.normalized() if d.length() > 0.1 else (graph.nodes[nb[0]] - graph.nodes[n]).normalized()
	elif not nb.is_empty():
		d = (graph.nodes[nb[0]] - graph.nodes[n]).normalized()
	var p := graph.nodes[n]
	var right := Vector2(-d.y, d.x)
	checkpoint_car = traffic.make_car("octavia", Color(0.88, 0.9, 0.93), true, "POLICIE")
	checkpoint_car.name = "Policie_kontrola"
	# vůz stojí na krajnici, mimo jízdní pruh – ze stran/vzdáleností vybere místo nejdál od všech silnic
	# (u křižovatky by jinak stál v pruhu jiné silnice)
	var best := p + right * 5.2
	var best_d := -1.0
	for off in [5.2, -5.2, 6.5, -6.5, 8.0, -8.0]:
		var cand: Vector2 = p + right * off
		var dd: float = world.dist_to_roads(cand)
		if dd > best_d + 0.5:
			best_d = dd
			best = cand
		if dd > 4.2:
			break
	traffic.place_car(checkpoint_car, best, atan2(d.x, d.y))
	checkpoint_car.drive = Car.Drive.NONE
	# policista stojí na krajnici (mimo jízdní pruh – auta ho jinak objíždějí)
	var cp := p + right * 3.3 + d * 7.0
	checkpoint_pos = Vector3(cp.x, terrain.height_at(cp.x, cp.y), cp.y)
	checkpoint_cop = Npc.make("Policista", "police", Color(0.12, 0.15, 0.3), 77, checkpoint_pos,
		atan2(-right.x, -right.y), world)
	add_child(checkpoint_cop)
	checkpoint_cop.visual.waving = true
	_cp_post = checkpoint_pos
	_cp_yaw = checkpoint_cop.base_yaw
	var sign := PropModels.road_sign("STOP", Color(0.8, 0.05, 0.05), Color(1, 1, 1), "octagon", 0.7)
	sign.position = checkpoint_pos + Vector3(right.x, 0, right.y) * 0.8 + Vector3(d.x, 0, d.y) * 1.5
	sign.rotation.y = atan2(-d.x, -d.y)
	add_child(sign)
	checkpoint_cop.set_meta("sign", sign)
	_cp_state = 0
	_cp_min_d = INF


func clear_checkpoint() -> void:
	if checkpoint_car and is_instance_valid(checkpoint_car):
		checkpoint_car.queue_free()
	if checkpoint_cop and is_instance_valid(checkpoint_cop):
		var s: Node = checkpoint_cop.get_meta("sign", null)
		if s:
			s.queue_free()
		checkpoint_cop.queue_free()
	checkpoint_car = null
	checkpoint_cop = null
	checkpoint_pos = Vector3.INF
	_cp_post = Vector3.INF


func license_ok(p: Player) -> bool:
	return clock.minutes >= p.license_suspended_until


## Pustí hráče z honičky / kontroly (načtení uložené pozice) – policista se vrátí k vozu nebo na stanoviště.
func release(pl: Player) -> void:
	_suspicion.erase(pl.id)
	if patrol_state == State.STOPPING and _stop_player == pl:
		if _stop_cop and is_instance_valid(_stop_cop):
			_returning.append([_stop_cop, _stop_cop_temp, _stop_car, _cp_post, _cp_yaw])
		elif _stop_car and is_instance_valid(_stop_car):
			_stop_car.ai_stop = false
		if pl.car:
			pl.car.police_hold = false
		pl.controls_locked = false
		_stop_cop = null
		_stop_player = null
		_end_chase()
	elif patrol_state == State.CHASE and target == pl:
		_end_chase()


# ------------------------------------------------------------------ hlavní smyčka

func _physics_process(delta: float) -> void:
	var __t0 := Tests.prof_t0()
	_physics_process_impl(delta)
	Tests.prof_add("police", __t0)


func _physics_process_impl(delta: float) -> void:
	if patrol == null or world.players.is_empty():
		return
	_checked_recently = maxf(_checked_recently - delta, 0.0)
	_walk_back(delta)
	# --- silniční kontrola
	if checkpoint_car and is_instance_valid(checkpoint_car):
		checkpoint_car._beacons()
		checkpoint_car._t += delta
		_checkpoint_logic(delta)
	match patrol_state:
		State.PATROL:
			if patrol.ai_done() or world.nearest_player_dist(patrol.global_position) > 900.0:
				_new_patrol_route()
			for p in world.players.values():
				if p.car or p.horse:          # jezdec na koni je účastník provozu stejně jako řidič
					_watch(delta, patrol, p)
		State.CHASE:
			_chase(delta)
		State.STOPPING:
			_stopping(delta)


## Dohled policie za mlhy (hlídka i policista u kontroly v mlze vidí hůř).
func _see_r(base: float) -> float:
	var w: Weather = world.get("weather") as Weather
	return base * lerpf(1.0, 0.4, w.fog if w else 0.0)


## Hlídka sleduje auto hráče `pl` a vyhodnocuje podezření.
func _watch(delta: float, cop: Car, pl: Player) -> void:
	var pcar := pl.car
	var pnode: Node3D = pcar if pcar != null else pl.horse      # auto, nebo kůň s jezdcem
	var d := cop.global_position.distance_to(pnode.global_position)
	var sus: float = _suspicion.get(pl.id, 0.0)
	if d > _see_r(70.0) or not _los(cop.global_position + Vector3(0, 1.3, 0), pnode.global_position + Vector3(0, 1.0, 0)):
		_suspicion[pl.id] = maxf(sus - delta * 0.1, 0.0)
		return
	var spd_v: float = pcar.speed if pcar != null else pl.horse.speed
	var wobble: float = absf(pcar.steer_in) if pcar != null else absf(pl.horse._yaw_rate) * 0.6
	var kmh := absf(spd_v) * 3.6
	var in_village := traffic.in_village(Vector2(pnode.global_position.x, pnode.global_position.z))
	var limit := 50.0 if in_village else 90.0
	var reason := ""
	if kmh > limit + 12.0:
		sus += delta * (kmh - limit) / 20.0
		reason = "překročení rychlosti (%d km/h)" % int(kmh)
		_note(pl.id, _speed_offense(in_village, kmh - limit), clampf((kmh - limit - 12.0) / 30.0, 0.1, 1.0))
	var p := pl.body.promile()
	if p > 0.6 and wobble > 0.25 and kmh > (15.0 if pcar != null else 4.0):
		sus += delta * p * 0.35
		reason = "podezřelá jízda (kličkování)" if pcar != null else "podezřelá jízda na koni"
	elif pcar != null and wobble > 0.6 and kmh > 40.0:
		_note(pl.id, "nesoustredena_jizda", 0.3)
	if pcar != null and clock.minutes < pl.wanted_until:
		sus = 1.0
		reason = "hledané vozidlo"
		_note(pl.id, "", 2.0)          # prázdné id = hledané vozidlo → vždy dechová zkouška, ne pokuta
	if pcar != null and not license_ok(pl):
		sus += delta * 0.3
		reason = "řidič se zákazem řízení"
	# náhodná kontrola při míjení
	if d < 22.0 and _checked_recently <= 0.0 and (pcar != null or p >= 0.2):    # jezdce hlídka kontroluje, když cítí alkohol
		_checked_recently = 120.0
		# řidiče se špatnou pověstí policie zná a kontroluje častěji
		var rep: Reputation = world.reputations.get(pl.id)
		if _rng.randf() < 0.3 + (rep.police_extra() if rep else 0.0):
			sus = 1.0
			reason = "běžná silniční kontrola"
	_suspicion[pl.id] = sus
	if sus >= 1.0:
		start_chase(cop, reason, pl)


## Nehoda auta řízeného hráčem `pl` – vidí ji policie poblíž?
func report_crash(pos: Vector3, what: String, pl: Player) -> void:
	for cop in [patrol, checkpoint_car]:
		if cop and is_instance_valid(cop) and cop.global_position.distance_to(pos) < 90.0 and pl.car:
			if _los(cop.global_position + Vector3(0, 1.3, 0), pos + Vector3(0, 1.0, 0)):
				if not (what in CRASH_NO_OFFENSE):
					world.commit_offense(pl.id, "nehoda_skoda", {"severity": 0.5})     # M4.4: oživený přestupek
				start_chase(cop, "nehoda (%s)" % what, pl)
				return
	# nikdo z policie: svědek z vesnice nehodu nahlásí, jinak zůstane nenahlášená (M4.4)
	if what in CRASH_NO_OFFENSE:
		return
	if world.clock.minutes - float(_crash_t.get(pl.id, -1.0e9)) < CRASH_CD_MIN:
		return
	if pl.car:
		_crash_t[pl.id] = world.clock.minutes
		if world.witness_reported(pl.id, pos, "nehoda", 60.0, 60.0):
			world.commit_offense(pl.id, "nehoda_skoda", {"severity": 0.5})
		else:
			world.add_unreported(pl.id, {"kind": "nehoda", "offenses": ["nehoda_skoda"], "pos": [pos.x, pos.y, pos.z],
				"t": world.clock.minutes, "value": 0, "severity": 0.5, "tool": what, "discover_p": 0.3})


func report_hit_person(pos: Vector3, pl: Player) -> void:
	# sražený chodec – policie přijede vždy
	if patrol_state != State.CHASE and pl.car:
		if patrol.global_position.distance_to(pos) > 400.0:
			var a := graph.astar(RoadGraph.CAR_KINDS)
			var s := a.get_closest_point(Vector2(pos.x, pos.z) + Vector2(250, 0).rotated(_rng.randf() * TAU))
			var sp := graph.nodes[s]
			traffic.place_car(patrol, sp, 0.0)
		world.commit_offense(pl.id, "srazeni_chodce", {"severity": 1.0})     # M4.4: policie přijede vždy
		start_chase(patrol, "sražení chodce", pl)


## Zapamatuje si přestupek hráče `pid` (zachová nejzávažnější; prázdné id = hledané vozidlo).
func _note(pid: int, oid: String, sev: float) -> void:
	var now := clock.minutes
	var cur: Dictionary = _viol.get(pid, {})
	if cur.is_empty() or float(cur["sev"]) < sev or now - float(cur["t"]) > 3.0:
		_viol[pid] = {"id": oid, "sev": sev, "t": now}
	elif String(cur["id"]) == oid:
		cur["t"] = now


## Přestupek zjištěný za poslední 3 herní minuty (jinak prázdný slovník).
func _recent(pid: int) -> Dictionary:
	var v: Dictionary = _viol.get(pid, {})
	if v.is_empty() or clock.minutes - float(v["t"]) > 3.0:
		return {}
	return v


func _speed_offense(in_village: bool, over: float) -> String:
	if over >= 40.0:
		return "rychlost_vyrazna"
	return "rychlost_obec" if in_village else "rychlost_mimo_obec"


## Co policista u okénka udělá: "test" dechová zkouška (podezření na alkohol, bez zákazu, nebo náhodně),
## "ticket" pokuta za zjištěný přestupek, "ok" jen kontrola dokladů.
func _plan(pl: Player) -> String:
	var v := _recent(pl.id)
	if pl.body.promile() >= 0.2 or not license_ok(pl) or (not v.is_empty() and String(v["id"]).is_empty()):
		return "test"
	if pl.car and not world.license_check(pl.id, pl.car)["ok"]:      # M4.1: řídí bez skupiny řidičáku
		return "ticket"
	if not v.is_empty():
		return "ticket"
	return "test" if _rng.randf() < 0.3 else "ok"


## Vystaví pokutu a body za zjištěný přestupek (přes zákon). Vrací výsledek `World.commit_offense`, nebo {}.
func _ticket(pl: Player) -> Dictionary:
	var oid := ""
	var sev := 1.0
	if pl.car and not world.license_check(pl.id, pl.car)["ok"]:
		oid = "rizeni_bez_opravneni"          # M4.1: jízda bez skupiny řidičáku
	else:
		var v := _recent(pl.id)
		if v.is_empty() or String(v["id"]).is_empty():
			return {}
		oid = String(v["id"])
		sev = float(v["sev"])
	var res: Dictionary = world.commit_offense(pl.id, oid, {"severity": sev, "quiet": true})
	_viol.erase(pl.id)
	if not res.get("ok", false):
		return {}
	var text := "PŘESTUPEK: %s\nPokuta %d Kč (zaplaceno %d Kč), +%d bodů (celkem %d / %d)." % [res["name"], res["fine"],
		res["paid"], res["points"], res["total_points"], int(Law.setting("body_limit", 12.0))]
	if float(res["ban_h"]) > 0.0:
		text += "\nZákaz řízení %d h." % int(res["ban_h"])
	if res["points_ban"]:
		text += "\nDosáhl jsi limitu bodů – zákaz řízení na rok."
	_banner(pl, text, 7.0)
	return res


func start_chase(cop: Car, reason: String, pl: Player) -> void:
	if patrol_state == State.CHASE or patrol_state == State.STOPPING:
		return
	chaser = cop
	target = pl
	patrol_state = State.CHASE
	_suspicion[pl.id] = 0.0
	_lost_t = 0.0
	_stop_t = 0.0
	chaser.set_siren(true)
	chaser.drive = Car.Drive.AI
	chaser.ai_path = PackedVector3Array()
	_banner(pl, "POLICIE! Zastavte vozidlo!  (%s)" % reason)
	world.emit_game_event(pl.id, "police_chase", {"reason": reason})


func _chase(delta: float) -> void:
	if chaser == null or not is_instance_valid(chaser):
		patrol_state = State.PATROL
		return
	if not _valid(target):
		_end_chase()
		return
	var pcar := target.car
	var target_node: Node3D = pcar if pcar else target
	var tpos := target_node.global_position
	var d := chaser.global_position.distance_to(tpos)
	_route_t -= delta
	if d < _see_r(45.0) and _los(chaser.global_position + Vector3(0, 1.2, 0), tpos + Vector3(0, 1.0, 0)):
		# zblízka přímo za autem (cíl kousek za hráčem)
		var back := Vector3.ZERO
		if pcar:
			back = -pcar.global_transform.basis.z * 7.0
		chaser.ai_direct_target = tpos + back
		chaser.ai_speed_limit = maxf(absf(pcar.speed) + 6.0, 8.0) if pcar else 6.0
	else:
		chaser.ai_direct_target = Vector3.INF
		if _route_t <= 0.0:
			_route_t = 1.5
			var ids := graph.route(Vector2(chaser.global_position.x, chaser.global_position.z), Vector2(tpos.x, tpos.z),
				RoadGraph.CAR_KINDS + ["track"])
			if ids.size() >= 2:
				# trasa začíná v nejbližším uzlu (často za autem) – body za autem se rovnou odbaví
				chaser.reroute(graph.lane_points(ids, terrain))
		chaser.ai_speed_limit = 33.0
	# zastavil? / vystoupil z auta poblíž?
	var stopped := (pcar != null and absf(pcar.speed) < 1.5 and d < 16.0) or (pcar == null and d < 25.0)
	if stopped:
		_stop_t += delta
		if _stop_t > 1.2:
			_begin_stop()
	else:
		_stop_t = 0.0
	# ujel?
	if d > 450.0:
		_lost_t += delta
		if _lost_t > 20.0:
			var who := target
			_end_chase()
			who.wanted_until = clock.minutes + 5.0 * 60.0
			_banner(who, "Policie tě ztratila… zatím. Tvoje SPZ je hledaná.", 5.0)
			escaped.emit(who.id)
	else:
		_lost_t = 0.0
	# policie se převrátila / zničila (chaser může být null po _end_chase výše)
	if chaser != null and chaser.damage >= 100.0:
		_end_chase()


func _end_chase() -> void:
	if is_instance_valid(target):
		_viol.erase(target.id)
	if chaser and is_instance_valid(chaser):
		chaser.set_siren(false)
		chaser.beacons_off()
		chaser.ai_direct_target = Vector3.INF
		if chaser == checkpoint_car:
			chaser.drive = Car.Drive.NONE
	patrol_state = State.PATROL
	chaser = null
	target = null
	if patrol:
		_new_patrol_route()


func _begin_stop() -> void:
	var cop: Npc = null
	if chaser:
		chaser.ai_direct_target = Vector3.INF
		chaser.ai_path = PackedVector3Array()
		chaser.ai_stop = true
		# policista vystoupí z hlídkového vozu
		var door := chaser.driver_door_world()
		door.y = terrain.height_at(door.x, door.z)
		cop = Npc.make("Policista", "police", Color(0.12, 0.15, 0.3), 78, door, chaser.rotation.y, world)
		add_child(cop)
	_banner(target, "POLICIE – zastav a zůstaň v autě, policista jde k tobě.", 3.0)
	world.emit_game_event(target.id, "sfx", {"name": "whistle"})
	_start_stop(cop, true, chaser, "zastavení policejní hlídkou", target)


func _start_stop(cop: Npc, temp: bool, from_car: Car, context: String, pl: Player) -> void:
	patrol_state = State.STOPPING
	_stop_t = 0.0
	_stop_phase = 0
	_stop_player = pl
	_stop_cop = cop
	_stop_cop_temp = temp
	_stop_car = from_car
	_stop_context = context
	if cop:
		cop.visual.waving = false
		cop.face_player = false
		cop.collision_layer = 0          # neprojde „skrz“ auto a nestrčí do něj
	if pl.car:
		pl.car.police_hold = true


## Místo u okénka řidiče (řidič sedí vlevo = +X vozu), nebo u hráče, když vystoupil.
func _window_pos() -> Vector3:
	var p: Vector3
	var sp := _stop_player
	if sp.car:
		var c := sp.car
		p = c.global_transform * Vector3(c.model.half_width + 0.55, 0.0, 0.35)
	else:
		var from := _stop_cop.global_position if _stop_cop else sp.global_position + Vector3(1, 0, 0)
		var dir := from - sp.global_position
		dir.y = 0.0
		p = sp.global_position + (dir.normalized() if dir.length() > 0.1 else Vector3.RIGHT) * 1.1
	p.y = terrain.height_at(p.x, p.z)
	return p


## Posune policistu o krok k cíli (po terénu). Vrací true, když je na místě.
func _walk(cop: Npc, target: Vector3, delta: float) -> bool:
	var to := target - cop.global_position
	to.y = 0.0
	var d := to.length()
	if d < 0.3:
		cop.visual.speed = 0.0
		return true
	var p := cop.global_position + to / d * minf(COP_WALK * delta, d)
	p.y = terrain.height_at(p.x, p.z)
	cop.global_position = p
	cop.base_yaw = atan2(to.x, to.z)
	cop.face_player = false
	cop.visual.speed = COP_WALK
	return false


func _stopping(delta: float) -> void:
	_stop_t += delta
	var sp := _stop_player
	if not _valid(sp):
		# kontrolovaný hráč zmizel (odpojení) – policista se vrátí
		if _stop_cop and is_instance_valid(_stop_cop):
			_returning.append([_stop_cop, _stop_cop_temp, _stop_car, _cp_post, _cp_yaw])
		elif _stop_car and is_instance_valid(_stop_car):
			_stop_car.ai_stop = false
		_stop_cop = null
		_stop_player = null
		_end_chase()
		return
	sp.controls_locked = sp.car == null     # pěšky neuteče; v autě drží ruční brzdu
	var cop := _stop_cop if _stop_cop and is_instance_valid(_stop_cop) else null
	match _stop_phase:
		0:
			# policista jde k okénku (když by nedošel – třeba zeď – po 25 s se tam „objeví“)
			if cop == null or _walk(cop, _window_pos(), delta) or _stop_t > 25.0:
				if cop and _stop_t > 25.0:
					cop.global_position = _window_pos()
				_stop_phase = 1
				_stop_t = 0.0
				_stop_plan = _plan(sp)
				if cop:
					cop.visual.speed = 0.0
					cop.face_player = true
				if _stop_plan == "test":
					if cop:
						cop.say("Dobrý den, silniční kontrola. Doklady, prosím… a dýchněte si sem.", 3.5)
						cop.visual.hold(PropModels.breathalyzer())
						cop.visual.start_action("offer")
					_banner(sp, "Policista: Dobrý den, silniční kontrola. Dýchněte si, prosím.", 3.0)
				else:
					if cop:
						cop.say("Dobrý den, silniční kontrola. Doklady, prosím.", 3.0)
					_banner(sp, "Policista: Dobrý den, silniční kontrola. Doklady, prosím.", 3.0)
		1:
			if _stop_t > 3.2:
				if cop:
					cop.visual.stop_action()
				var said := ""
				match _stop_plan:
					"test":
						breath_test(sp, _stop_context)
						var p := last_test_promile
						said = "%s ‰. %s" % [("%.2f" % p).replace(".", ","),
							"Děkuji, šťastnou cestu." if p < 0.25 and license_ok(sp) else "Vystupte si, prosím."]
					"ticket":
						var res := _ticket(sp)
						said = "Pokuta %d Kč, %d bodů. Šťastnou cestu." % [res.get("fine", 0), res.get("points", 0)] \
							if not res.is_empty() else "Doklady v pořádku, šťastnou cestu."
					_:
						_banner(sp, "Policista: Doklady v pořádku. Šťastnou cestu.", 3.0)
						said = "Doklady v pořádku, šťastnou cestu."
				_viol.erase(sp.id)
				if cop:
					cop.say(said, 4.0)
					_returning.append([cop, _stop_cop_temp, _stop_car, _cp_post, _cp_yaw])
				elif _stop_car and is_instance_valid(_stop_car):
					_stop_car.ai_stop = false
				if sp.car:
					sp.car.police_hold = false
				_stop_cop = null
				_stop_player = null
				_end_chase()


## Policisté po kontrole: ten z hlídky dojde zpátky k vozu a nastoupí (vůz pak odjede),
## ten ze silniční kontroly se vrátí na stanoviště a zase mává.
func _walk_back(delta: float) -> void:
	for r in _returning.duplicate():
		if not is_instance_valid(r[0]):
			_returning.erase(r)
			continue
		var cop: Npc = r[0]
		if cop._say_t > 1.0:
			continue          # ještě domlouvá
		var car: Car = r[2] if r[2] != null and is_instance_valid(r[2]) else null
		var target: Vector3
		if r[1]:
			if car == null:
				cop.queue_free()
				_returning.erase(r)
				continue
			target = car.driver_door_world()
		else:
			target = r[3]
			if target == Vector3.INF:
				cop.queue_free()
				_returning.erase(r)
				continue
		target.y = terrain.height_at(target.x, target.z)
		if _walk(cop, target, delta):
			_returning.erase(r)
			if r[1]:
				cop.queue_free()
				car.ai_stop = false
			else:
				cop.base_yaw = r[4]
				cop.face_player = true
				cop.visual.waving = true
				cop.collision_layer = 4


func breath_test(pl: Player, context: String) -> void:
	pl.controls_locked = false
	if pl.car:
		pl.car.police_hold = false
	var p := pl.body.promile()
	last_test_promile = p
	# M2.8: při kontrole se hledí i do inventáře – puška bez zbrojního oprávnění se zabaví (pokuta a záznam přes zákon)
	var wpn = world.get("weapons")
	if wpn != null:
		wpn.police_check(pl.id, context)
	var riding := pl.car == null and pl.horse != null        # na koni se zákaz řízení neuplatní, promile ano
	var ban := not riding and not license_ok(pl)
	if p >= 0.25 or ban:
		var reason := ""
		var what := "jízda na koni" if riding else "řízení"
		if ban:
			reason = "řízení přes zákaz"
		elif p >= 1.0:
			reason = "%s pod vlivem – trestný čin (%.2f ‰)" % [what, p]
		else:
			reason = "%s pod vlivem – přestupek (%.2f ‰)" % [what, p]
		busted.emit(pl.id, p, reason)
	else:
		var msg := "Dechová zkouška: %.2f ‰." % p
		if p > 0.0:
			msg += " V toleranci přístroje (do 0,24 ‰)."
		msg += " Děkujeme, šťastnou cestu."
		_banner(pl, msg, 4.0)
		test_passed.emit(pl.id, p)
	world.emit_game_event(pl.id, "breath_test", {"promile": p, "context": context})


## Silniční kontrola řeší nejbližšího řidiče; pěší jen pozdraví.
func _checkpoint_logic(delta: float) -> void:
	if checkpoint_pos == Vector3.INF:
		return
	var pl := _nearest_driver(checkpoint_pos)
	if pl != _cp_player:
		_cp_player = pl
		_cp_state = 0
		_cp_min_d = INF
	if pl == null:
		var walker: Player = world.nearest_player(checkpoint_pos)
		if walker:
			var dw := Vector2(walker.global_position.x - checkpoint_pos.x, walker.global_position.z - checkpoint_pos.z).length()
			if dw < 5.0 and checkpoint_cop._say_t <= 0.0:
				var p: float = walker.body.promile()
				checkpoint_cop.say("Dobrý večer." if p < 0.5 else "Pane, dojděte v klidu domů, ať nejste pod koly.", 3.0)
		return
	var pcar := pl.car
	var d := Vector2(pl.global_position.x - checkpoint_pos.x, pl.global_position.z - checkpoint_pos.z).length()
	if patrol_state != State.PATROL:
		return
	if d < _see_r(45.0) and _cp_state == 0:
		_cp_state = 1
		_banner(pl, "Silniční kontrola! Zastav u policisty.", 3.0)
		checkpoint_cop.say("Stůjte! Silniční kontrola.", 3.0)
	if _cp_state >= 1:
		_cp_min_d = minf(_cp_min_d, d)
		if d < 16.0 and absf(pcar.speed) < 1.0:
			_cp_state = 0
			_cp_min_d = INF
			chaser = null
			_start_stop(checkpoint_cop, false, null, "silniční kontrola", pl)
			_banner(pl, "Silniční kontrola – zůstaň v autě, policista jde k tobě.", 3.0)
			return
		if _cp_min_d < 14.0 and d > 26.0:
			# projel kolem → pronásledování
			_cp_state = 0
			_cp_min_d = INF
			start_chase(checkpoint_car, "ujel jsi ze silniční kontroly", pl)
		elif d > 80.0:
			_cp_state = 0   # otočil se dřív


func _los(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()
