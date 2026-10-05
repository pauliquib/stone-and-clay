## Doprava: auta hráčů (každý hráč své), zaparkovaná auta u domů, AI auta jezdící po silnicích
## (A* trasy, pravý jízdní pruh, v obci 50 km/h). Daleká / zaseknutá AI auta se přesunou blíž
## k některému hráči (auta se rozdělí mezi hráče), vzdálenost se měří k nejbližšímu hráči.
class_name Traffic
extends Node3D

const N_AI := 5
const N_PARKED := 14
const COLORS := [Color(0.75, 0.75, 0.78), Color(0.1, 0.1, 0.12), Color(0.15, 0.25, 0.55), Color(0.55, 0.08, 0.06),
	Color(0.9, 0.9, 0.9), Color(0.3, 0.35, 0.3), Color(0.55, 0.45, 0.3), Color(0.2, 0.4, 0.35)]
# M1.6: váhy výskytu modelů (hodně osobních, občas dodávka / pickup). Traktor jezdí zvlášť (sezóna, okresky).
const AI_WEIGHTS := {"octavia": 3.0, "fabia": 3.0, "sedan120": 1.5, "rodinka": 2.5, "van": 0.8, "bednar": 1.0, "lesak": 1.2}
const PARKED_WEIGHTS := {"octavia": 3.0, "fabia": 3.0, "sedan120": 1.5, "rodinka": 2.5, "van": 0.6, "bednar": 0.8, "lesak": 1.0,
	"pionyrek": 0.5, "vcelka": 0.5, "armadka": 0.3, "krosak": 0.2}
const TRACTOR_KINDS := ["tertiary", "unclassified", "service", "track"]   # jen okresky a polní cesty (DOPLNIT: podle grafu silnic)
const TRACTOR_ID := "traktorek"
const TRACTOR_CHECK_S := 15.0
const VILLAGE_CENTER := Vector2(120.0, 180.0)
const VILLAGE_R := 520.0

var graph: RoadGraph
var terrain: Terrain
var world: Node                   # World – seznam hráčů
var player_cars := {}             # id hráče → Car (auto hráče)
var player_vehicles := {}         # id hráče → [Car] všechna jeho vozidla (auto, dědovo kolo, Jawa)
var ai_cars: Array[Car] = []
var parked: Array[Car] = []
var rng := RandomNumberGenerator.new()
var _stuck := {}
var _plate_n := 1000
var _tractor_t := 0.0
var _zones: Array = []           # [Vector3(x, z, r)] zóny „v obci“ – Dukelčice + katastry z obce.json
var respawn_log: Array = []      # [čas ms, auto, důvod] – pro --traffictest


func setup(g: RoadGraph, t: Terrain, w: Node) -> void:
	graph = g
	terrain = t
	world = w
	rng.seed = 490
	# zóny „v obci“ (limit 50 km/h, svědci u policie/pověsti): Dukelčice + každá obec
	# z World.obce (střed + ekvivalentní poloměr katastru); parkování zůstává jen Dukelčice
	_zones = [Vector3(VILLAGE_CENTER.x, VILLAGE_CENTER.y, VILLAGE_R)]
	var obce: Variant = w.get("obce") if w != null else null
	if obce is Array:
		for o in obce:
			var c: Array = o.get("center", [])
			if c.size() >= 2:
				_zones.append(Vector3(float(c[0]), float(c[1]), float(o.get("radius", 500.0))))


## Je bod (x, z) uvnitř některé obce – Dukelčice (VILLAGE_CENTER/R) nebo katastru okolní
## obce z data/obce.json (střed ± radius)? Sdílený test pro limit 50 km/h AI aut
## a pro svědky/hlídky (police.gd, reputation.gd).
func in_village(p: Vector2) -> bool:
	if _zones.is_empty():
		return p.distance_to(VILLAGE_CENTER) < VILLAGE_R
	for z in _zones:
		if p.distance_to(Vector2(z.x, z.y)) < z.z:
			return true
	return false


## Smyšlená SPZ – písmeno Q se v českých SPZ nevydává, takže se nemůže shodovat s reálným vozidlem.
func plate() -> String:
	_plate_n += rng.randi_range(7, 311)
	return "%dQQ %04d" % [rng.randi_range(1, 9), _plate_n % 10000]


## Umístí auto na silnici: pozice (x, z), směr (yaw), výška z terénu.
func place_car(c: Car, pos: Vector2, yaw: float) -> void:
	var y := terrain.height_at(pos.x, pos.y)
	# silnice leží těsně nad terénem → spustit paprskem
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space:
		var q := PhysicsRayQueryParameters3D.create(Vector3(pos.x, y + 6.0, pos.y), Vector3(pos.x, y - 4.0, pos.y), 1)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			y = hit["position"].y
	c.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(pos.x, y + 0.25, pos.y))
	c.linear_velocity = Vector3.ZERO
	c.angular_velocity = Vector3.ZERO
	c._prev_xf = c.global_transform
	c._cur_xf = c.global_transform
	c._prev_vel = Vector3.ZERO


## Vážený náhodný výběr modelu z tabulky {id: váha}.
func pick_model(weights: Dictionary) -> String:
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	var r := rng.randf() * total
	for k in weights:
		r -= float(weights[k])
		if r <= 0.0:
			return String(k)
	return String(weights.keys()[0])


## Sezóna polních prací: duben–říjen, 6–19 h (traktor jezdí jen tehdy).
func farm_season() -> bool:
	var m: int = world.clock.month()
	var h: float = world.clock.hour()
	return m >= 4 and m <= 10 and h >= 6.0 and h < 19.0


func tractor() -> Car:
	for c in ai_cars:
		if c.model_id == TRACTOR_ID and is_instance_valid(c):
			return c
	return null


## Traktor v AI dopravě: v sezóně se objeví (jede po okreskách a polních cestách), mimo ni zmizí, jakmile ho nikdo nevidí.
func _update_tractor(delta: float) -> void:
	_tractor_t -= delta
	if _tractor_t > 0.0:
		return
	_tractor_t = TRACTOR_CHECK_S
	var t := tractor()
	if farm_season():
		if t == null and not ai_cars.is_empty():
			var c := make_car(TRACTOR_ID, Color(0.15, 0.4, 0.2) if rng.randf() < 0.5 else Color(0.7, 0.12, 0.08))
			c.name = "AI_Traktor"
			ai_cars.append(c)
			world._connect_car(c)
			_respawn(c, true)
			if c.ai_path.is_empty():            # graf nemá okresku / polňačku poblíž hráče → bez traktoru
				ai_cars.erase(c)
				c.queue_free()
	elif t != null and world.nearest_player_dist(t.global_position) > 60.0:
		ai_cars.erase(t)
		_stuck.erase(t)
		t.queue_free()


func make_car(model_id: String, color: Color, police := false, plate_text := "") -> Car:
	var c := Car.new()
	c.setup(model_id, color, police, plate_text if plate_text != "" else plate())
	c.weather = world.weather
	c.clock = world.clock
	add_child(c)
	return c


## Auto hráče `pid` (červená Octavia; další hráči mají jiné SPZ).
func spawn_player_car(pid: int, pos: Vector2, yaw: float) -> Car:
	var c := make_car("octavia", Color(0.62, 0.06, 0.05), false, "4QQ 7302" if pid == 1 else "4QQ %04d" % (2200 + pid))
	c.name = "AutoHrace" if pid == 1 else "AutoHrace_%d" % pid
	c.owner_id = pid
	place_car(c, pos, yaw)
	player_cars[pid] = c
	player_vehicles[pid] = [c]
	return c


## Dědovo kolo a motorka hráče `pid` – na volných místech kolem parkoviště u domu (pos, yaw = parkoviště auta).
func spawn_player_bikes(pid: int, pos: Vector2, yaw: float) -> Array[Car]:
	var out: Array[Car] = []
	for d in [["kolo", Color(0.09, 0.28, 0.17), "Kolo"], ["jawa", Color(0.5, 0.04, 0.03), "Jawa"]]:
		var c := make_car(d[0], d[1], false, "4QQ %d%02d" % [pid, 18 + out.size()] if d[0] == "jawa" else "-")
		c.name = d[2] if pid == 1 else "%s_%d" % [d[2], pid]
		c.owner_id = pid
		var spot := free_spot(pos, yaw, Vector3(0.8, 1.1, 2.2))
		place_car(c, Vector2(spot.x, spot.y), spot.z)
		out.append(c)
		player_vehicles[pid].append(c)
	return out


## Volné místo pro malé vozidlo vedle parkoviště (zkouší body po stranách, před a za autem).
## Vrací (x, z, yaw). Kvádr `size` nesmí zasahovat do budov, aut ani věcí.
func free_spot(pos: Vector2, yaw: float, size: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = size
	q.shape = box
	q.collision_mask = 1 | 4 | 8 | 16
	var b := Basis(Vector3.UP, yaw)
	for lp in [Vector3(2.0, 0, 0.5), Vector3(-2.0, 0, 0.5), Vector3(2.0, 0, -1.5), Vector3(-2.0, 0, -1.5),
			Vector3(2.9, 0, 0.5), Vector3(-2.9, 0, 0.5), Vector3(0, 0, -4.0), Vector3(0, 0, 4.0), Vector3(3.8, 0, -2.0),
			Vector3(-3.8, 0, -2.0), Vector3(1.2, 0, -4.5), Vector3(-1.2, 0, 4.5)]:
		var w: Vector3 = Vector3(pos.x, 0, pos.y) + b * lp
		var y := terrain.height_at(w.x, w.z)
		var ray := PhysicsRayQueryParameters3D.create(Vector3(w.x, y + 4.0, w.z), Vector3(w.x, y - 3.0, w.z), 1)
		var hit := space.intersect_ray(ray)
		if hit.is_empty() or hit["position"].y > y + 0.5:
			continue           # střecha / zeď
		q.transform = Transform3D(b, hit["position"] + Vector3(0, size.y * 0.5 + 0.3, 0))
		if space.intersect_shape(q, 1).is_empty():
			return Vector3(w.x, w.z, yaw)
	return Vector3(pos.x + b.x.x * 2.5, pos.y + b.x.z * 2.5, yaw)


## Zkušební vozidlo libovolného modelu (--drive=<id>) vedle auta hráče – patří hráči.
func spawn_test_vehicle(pid: int, model_id: String) -> Car:
	var c := make_car(model_id, Color(0.2, 0.32, 0.6), false, "TEST %03d" % rng.randi_range(0, 999))
	c.name = "Test_%s" % model_id
	c.owner_id = pid
	var car := car_of(pid)
	var yaw := car.global_rotation.y if car else 0.0
	var at := Vector2(car.global_position.x, car.global_position.z) if car else Vector2.ZERO
	var spot := free_spot(at, yaw, Vector3(2.0, 1.4, 4.8))
	place_car(c, Vector2(spot.x, spot.y), spot.z)
	player_vehicles[pid].append(c)
	return c


func car_of(pid: int) -> Car:
	var c: Car = player_cars.get(pid)
	return c if c and is_instance_valid(c) else null


## Všechna vozidla hráče (auto, kolo, motorka).
func vehicles_of(pid: int) -> Array:
	var out := []
	for c in player_vehicles.get(pid, []):
		if is_instance_valid(c):
			out.append(c)
	return out


func spawn_parked(near: Array) -> void:
	# podél silnic v obci, 3,3 m vpravo od osy
	var cand := graph.nodes_within(VILLAGE_CENTER, VILLAGE_R, ["residential", "service", "unclassified"])
	var used: Array[Vector2] = []
	for p in near:
		used.append(p)
	var tries := 0
	while parked.size() < N_PARKED and tries < 500 and not cand.is_empty():
		tries += 1
		var i: int = cand[rng.randi() % cand.size()]
		var nb: Array = graph.adj[i]
		if nb.is_empty():
			continue
		var j: int = nb[0]
		var d := (graph.nodes[j] - graph.nodes[i]).normalized()
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var p := graph.nodes[i] + Vector2(-d.y, d.x) * 3.4 * side
		var ok := true
		for u in used:
			if u.distance_to(p) < 25.0:
				ok = false
		if not ok:
			continue
		used.append(p)
		var yaw := atan2(d.x, d.y) + (0.0 if side > 0 else PI)
		var c := make_car(pick_model(PARKED_WEIGHTS), COLORS[rng.randi() % COLORS.size()])
		c.name = "Zaparkovane_%d" % parked.size()
		place_car(c, p, yaw)
		parked.append(c)


func spawn_ai() -> void:
	for i in N_AI:
		var c := make_car(pick_model(AI_WEIGHTS), COLORS[rng.randi() % COLORS.size()])
		c.name = "AI_%d" % i
		ai_cars.append(c)
		_respawn(c, true)


## Nová trasa z náhodného místa 120–450 m od hráče (auta se rozdělí mezi hráče podle pořadí).
func _respawn(c: Car, first := false) -> void:
	var anchor: Vector3 = world.player_anchor(maxi(ai_cars.find(c), 0))
	var pp := Vector2(anchor.x, anchor.z)
	var is_tractor := c.model_id == TRACTOR_ID
	var a := graph.astar(TRACTOR_KINDS if is_tractor else RoadGraph.CAR_KINDS)
	for attempt in 30:
		var ang := rng.randf() * TAU
		var r := rng.randf_range(120.0, 450.0) if not first else rng.randf_range(60.0, 500.0)
		var s := a.get_closest_point(pp + Vector2(cos(ang), sin(ang)) * r)
		var sp := graph.nodes[s]
		if sp.distance_to(pp) < 90.0:
			continue
		var ang2 := rng.randf() * TAU
		var e := a.get_closest_point(sp + Vector2(cos(ang2), sin(ang2)) * rng.randf_range(500.0, 1600.0))
		var ids := a.get_id_path(s, e)
		if ids.size() < 6:
			continue
		var pts := graph.lane_points(ids, terrain)
		var d := Vector2(pts[1].x - pts[0].x, pts[1].z - pts[0].z)
		place_car(c, Vector2(pts[0].x, pts[0].z), atan2(d.x, d.y))
		var v_obci := in_village(sp)
		c.set_ai_route(pts, minf(13.9 if v_obci else 19.0, float(c.model.spec.get("ai_vmax", 99.0))))
		_stuck[c] = 0.0
		return


func _physics_process(delta: float) -> void:
	if world.players.is_empty():
		return
	_update_tractor(delta)
	var respawns := 0                  # hledání trasy (A*) je drahé – nejvýš jedno přeplánování za krok
	for c in ai_cars:
		if c.drive != Car.Drive.AI:
			continue
		var d: float = world.nearest_player_dist(c.global_position)
		# rychlostní limit podle obce (Dukelčice + katastry okolních obcí)
		var v_obci := in_village(Vector2(c.global_position.x, c.global_position.z))
		c.ai_speed_limit = minf(13.9 if v_obci else 19.0, float(c.model.spec.get("ai_vmax", 99.0)))
		if absf(c.speed) < 0.6 and c.ai_blocked <= 0.0:
			_stuck[c] = float(_stuck.get(c, 0.0)) + delta
		else:
			_stuck[c] = 0.0
		# zaseknuté / dlouho zablokované auto daleko od hráče se přesune jinam (hráč to nevidí)
		var blocked_long := c.ai_blocked > 40.0 and d > 80.0
		if d > 650.0 or c.ai_done() or float(_stuck.get(c, 0.0)) > 25.0 or c.damage >= 100.0 or blocked_long:
			if d > 60.0 and respawns == 0:
				respawns += 1
				var why := "daleko" if d > 650.0 else ("dojel" if c.ai_done() else ("zaseknutý" if float(_stuck.get(c, 0.0)) > 25.0 \
					else ("zničený" if c.damage >= 100.0 else "zablokovaný")))
				respawn_log.append([Time.get_ticks_msec(), c.name, why])
				c.repair()
				_respawn(c)
		# daleko od hráče → uspat fyziku kol (šetří výkon), ale jen když nestojí na trase
		c.set_physics_process(true)
