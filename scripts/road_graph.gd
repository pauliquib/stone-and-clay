## Graf silnic a cest z OSM (map.json → roads) – pohyb botů, trasy aut (A*), jízdní pruhy.
class_name RoadGraph
extends RefCounted

const CAR_KINDS := ["secondary", "tertiary", "unclassified", "residential", "service", "living_street"]
## Koncové body tras AI aut (start, cíl) – ne na účelových cestách (service = vjezdy do dvorů,
## garáží a areálů, často slepé; auta jimi jen projíždějí).
const END_KINDS := ["secondary", "tertiary", "unclassified", "residential", "living_street"]
# jízdní pruh: offset od osy silnice vpravo (m)
const LANE_OFFSET := {"secondary": 1.6, "tertiary": 1.6, "residential": 1.0, "unclassified": 1.0}
const LANE_OFFSET_DEFAULT := 0.8
const LANE_MITRE_MAX := 2.0        # mitre korekce offsetu v rohu nejvýš 2× (lom ~120°)
# zaoblení ostrých lomů osy (místo mazání „vlásenek“)
const ROUND_MIN_TURN := 0.6        # lom ostřejší než ~35° se zaoblí (rad)
const ROUND_R := 7.0               # cílový poloměr oblouku na ose (m) – omezený délkou sousedních úseků
const ROUND_STEPS := 4             # počet dílků oblouku
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
## Ostré lomy osy se nejdřív zaoblí (`_round_corners` – dřív se „vlásenky“ mazaly a trasa pak
## seřízla roh přes zahrady), pruh se pak posune o offset podle druhu silnice s mitre korekcí
## 1/cos(θ/2) – v rohu zůstane pruh rovnoběžný s osou (bez korekce se v zatáčce přibližoval ose).
func lane_points(ids_in: PackedInt64Array, terrain: Terrain) -> PackedVector3Array:
	var n := ids_in.size()
	var axis := PackedVector2Array()
	var ks := PackedStringArray()       # druh úseku, který z bodu vychází (poslední bod: příjezdový)
	for k in n:
		axis.append(nodes[ids_in[k]])
		if k < n - 1:
			ks.append(edge(ids_in[k], ids_in[k + 1]))
		else:
			ks.append(edge(ids_in[k - 1], ids_in[k]) if k > 0 else "")
	var rounded := _round_corners(axis, ks)
	var pts: PackedVector2Array = rounded[0]
	var kinds_at: PackedStringArray = rounded[1]
	var out := PackedVector3Array()
	var m := pts.size()
	for k in m:
		var p := pts[k]
		var d0 := (p - pts[k - 1]).normalized() if k > 0 else Vector2.ZERO
		var d1 := (pts[k + 1] - p).normalized() if k < m - 1 else Vector2.ZERO
		var d := d0 + d1
		if d.length() < 0.05:
			d = d0 if d0 != Vector2.ZERO else d1      # otočka o 180° – posun podle příjezdu
		d = d.normalized()
		# i na úzkých účelových cestách jezdí auta vpravo, aby se dvě protijedoucí vyhnula
		var off: float = LANE_OFFSET.get(kinds_at[k], LANE_OFFSET_DEFAULT)
		if d0 != Vector2.ZERO and d1 != Vector2.ZERO:
			# mitre: cos(θ/2) = průmět směru úseku do osy rohu
			off /= maxf(d.dot(d1), 1.0 / LANE_MITRE_MAX)
		var q := p + Vector2(-d.y, d.x) * off
		out.append(Vector3(q.x, terrain.height_at(q.x, q.y) + 0.1, q.y))
	return out


## Zaoblí lomy osy ostřejší než `ROUND_MIN_TURN`: roh se nahradí kvadratickou Bézierovou křivkou
## tečnou k oběma úsekům (tečné body ve vzdálenosti ROUND_R·tan(θ/2), nejvýš 45 % kratšího úseku –
## sousední roh má svůj oblouk). Pokrývá i „Y“ odbočky, kde A* dojede do uzlu a vrací se druhou větví.
## Vrací [body, druhy úseků].
func _round_corners(pts: PackedVector2Array, ks: PackedStringArray) -> Array:
	var out_p := PackedVector2Array()
	var out_k := PackedStringArray()
	var m := pts.size()
	for k in m:
		var p := pts[k]
		if k == 0 or k == m - 1:
			out_p.append(p)
			out_k.append(ks[k])
			continue
		var l0 := pts[k - 1].distance_to(p)
		var l1 := p.distance_to(pts[k + 1])
		if l0 < 0.1 or l1 < 0.1:
			if l0 >= 0.1:            # zdvojený bod – stačí jeden
				out_p.append(p)
				out_k.append(ks[k])
			continue
		var u0 := (p - pts[k - 1]) / l0
		var u1 := (pts[k + 1] - p) / l1
		var th := absf(u0.angle_to(u1))
		if th < ROUND_MIN_TURN:
			out_p.append(p)
			out_k.append(ks[k])
			continue
		var t := minf(ROUND_R * tan(minf(th, 3.0) * 0.5), 0.45 * minf(l0, l1))
		var a := p - u0 * t
		var b := p + u1 * t
		for i in ROUND_STEPS + 1:
			var f := float(i) / ROUND_STEPS
			out_p.append(a.lerp(p, f).lerp(p.lerp(b, f), f))
			out_k.append(ks[k - 1] if f < 0.5 else ks[k])
	return [out_p, out_k]


## Rychlostní limit úseku (m/s) – v obci max. 50 km/h.
func speed_limit(a: int, b: int, in_village: bool) -> float:
	var v: float = SPEED.get(edge(a, b), 12.0)
	return minf(v, 13.9) if in_village else v
