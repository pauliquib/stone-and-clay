## Graf silnic a cest z OSM (map.json → roads) – pohyb botů, trasy aut (A*), jízdní pruhy.
class_name RoadGraph
extends RefCounted

const CAR_KINDS := ["secondary", "tertiary", "unclassified", "residential", "service", "living_street"]
const SPEED := {"secondary": 19.4, "tertiary": 16.7, "unclassified": 13.9, "residential": 12.5,
	"service": 8.3, "living_street": 5.5, "track": 7.0}

var nodes: PackedVector2Array = PackedVector2Array()   # (x, z)
var adj: Array = []                                     # seznam sousedů
var kinds: PackedStringArray = PackedStringArray()
var edge_kind := {}                                     # klíč min*1e6+max → druh silnice
var _index := {}
var _astars := {}


func build(roads: Array) -> void:
	for rd in roads:
		var pts: Array = rd["pts"]
		var prev := -1
		var kind: String = rd["kind"]
		for k in pts.size():
			var p := Vector2(pts[k][0], pts[k][1])
			if prev >= 0:
				# zahuštění – boti pak sledují zatáčky
				var a := nodes[prev]
				var n := int(a.distance_to(p) / 12.0)
				for s in range(1, n + 1):
					var q := a.lerp(p, float(s) / (n + 1))
					var mid := _node(q, kind, false)
					_link(prev, mid, kind)
					prev = mid
			var id := _node(p, kind, true)
			if prev >= 0 and prev != id:
				_link(prev, id, kind)
			prev = id


func _node(p: Vector2, kind: String, snap: bool) -> int:
	if snap:
		var key := Vector2i(roundi(p.x), roundi(p.y))
		if _index.has(key):
			return _index[key]
		_index[key] = nodes.size()
	nodes.append(p)
	adj.append([])
	kinds.append(kind)
	return nodes.size() - 1


func _link(a: int, b: int, kind: String) -> void:
	if not adj[a].has(b):
		adj[a].append(b)
	if not adj[b].has(a):
		adj[b].append(a)
	edge_kind[_ek(a, b)] = kind


func _ek(a: int, b: int) -> int:
	return mini(a, b) * 1000000 + maxi(a, b)


func edge(a: int, b: int) -> String:
	return edge_kind.get(_ek(a, b), "")


func nearest(p: Vector2) -> int:
	var best := -1
	var bd := INF
	for i in nodes.size():
		var d := nodes[i].distance_squared_to(p)
		if d < bd and not adj[i].is_empty():
			bd = d
			best = i
	return best


func nodes_within(p: Vector2, r: float, kinds_ok: Array = []) -> Array:
	var out := []
	for i in nodes.size():
		if adj[i].is_empty():
			continue
		if not kinds_ok.is_empty() and not kinds_ok.has(kinds[i]):
			continue
		if nodes[i].distance_to(p) < r:
			out.append(i)
	return out


func next_node(cur: int, prev: int, rng: RandomNumberGenerator) -> int:
	var opts: Array = adj[cur]
	if opts.is_empty():
		return cur
	if opts.size() == 1:
		return opts[0]
	var cand := []
	for o in opts:
		if o != prev:
			cand.append(o)
	return cand[rng.randi() % cand.size()]


# ------------------------------------------------------------------ trasy pro auta

## A* nad hranami zadaných druhů (hlavní silnice mají nižší "cenu" – auta je preferují).
func astar(kinds_ok: Array) -> AStar2D:
	var key := ",".join(kinds_ok)
	if _astars.has(key):
		return _astars[key]
	var a := AStar2D.new()
	a.reserve_space(nodes.size())
	for ek in edge_kind:
		var k: String = edge_kind[ek]
		if not kinds_ok.has(k):
			continue
		var i: int = ek / 1000000
		var j: int = ek % 1000000
		for n in [i, j]:
			if not a.has_point(n):
				var w := 1.0
				match kinds[n]:
					"secondary", "tertiary":
						w = 0.8
					"service":
						w = 1.3
					"track":
						w = 1.6
				a.add_point(n, nodes[n], w)
		a.connect_points(i, j)
	_astars[key] = a
	return a


## Trasa mezi dvěma body (uzly grafu) po silnicích pro auta.
func route(from: Vector2, to: Vector2, kinds_ok: Array = CAR_KINDS) -> PackedInt64Array:
	var a := astar(kinds_ok)
	if a.get_point_count() == 0:
		return PackedInt64Array()
	var s := a.get_closest_point(from)
	var e := a.get_closest_point(to)
	return a.get_id_path(s, e)


func car_node_near(p: Vector2, kinds_ok: Array = CAR_KINDS) -> int:
	return astar(kinds_ok).get_closest_point(p)


## Z posloupnosti uzlů udělá body jízdního pruhu (vpravo od osy silnice) ve 3D.
func lane_points(ids_in: PackedInt64Array, terrain: Terrain) -> PackedVector3Array:
	var ids := _cut_hairpins(ids_in)
	var out := PackedVector3Array()
	var n := ids.size()
	for k in n:
		var p := nodes[ids[k]]
		var d := Vector2.ZERO
		if k < n - 1:
			d += (nodes[ids[k + 1]] - p).normalized()
		if k > 0:
			d += (p - nodes[ids[k - 1]]).normalized()
		d = d.normalized()
		var kind := edge(ids[k], ids[mini(k + 1, n - 1)]) if k < n - 1 else edge(ids[k - 1], ids[k]) if k > 0 else ""
		# i na úzkých účelových cestách jezdí auta vpravo, aby se dvě protijedoucí vyhnula
		var off := 1.6 if kind in ["secondary", "tertiary"] else (1.0 if kind in ["residential", "unclassified"] else 0.8)
		var q := p + Vector2(-d.y, d.x) * off
		out.append(Vector3(q.x, terrain.height_at(q.x, q.y) + 0.1, q.y))
	return out


## Odbočka do „Y“: A* dojede do uzlu a hned se vrací druhou větví (lom > 125°) – auto takový
## lom neprojede, tak se roh vynechá (řidič odbočí rovnou). Opakuje se, dokud nějaký zbývá.
func _cut_hairpins(ids_in: PackedInt64Array) -> PackedInt64Array:
	var ids := ids_in.duplicate()
	var again := true
	while again and ids.size() > 3:
		again = false
		for k in range(1, ids.size() - 1):
			var d0 := nodes[ids[k]] - nodes[ids[k - 1]]
			var d1 := nodes[ids[k + 1]] - nodes[ids[k]]
			if d0.length() < 0.1 or d1.length() < 0.1 or absf(d0.angle_to(d1)) > 2.2:
				ids.remove_at(k)
				again = true
				break
	return ids


## Rychlostní limit úseku (m/s) – v obci max. 50 km/h.
func speed_limit(a: int, b: int, in_village: bool) -> float:
	var v: float = SPEED.get(edge(a, b), 12.0)
	return minf(v, 13.9) if in_village else v
