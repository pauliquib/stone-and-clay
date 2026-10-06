## Potoky, řeka a rybníky podle skutečných dat (OSM / DIBAVOD, tools/water.py → data/water.json).
## Koryta jsou už vyhloubená v terénu (Terrain._apply_water_carve); tady se staví hladina:
## pás podél osy toku (hladina po bodech klesá po proudu) a plochy nádrží.
## Dotazy: info_at (hloubka a jméno toku v bodě – brodění, kroky), nearest_stream (šumění potoka).
## V mrazu voda zamrzá (rybníky dřív, tekoucí voda později), v dešti a větru víc vlnek.
class_name Water
extends Node3D

const CELL := 32.0                    # mřížka pro hledání nejbližšího úseku
const VIS_RANGE := 1100.0
const FLOW := {"river": 0.55, "canal": 0.3, "stream": 0.9, "ditch": 0.4, "drain": 0.4}

var world: World
var terrain: Terrain
var data := {}
var streams := []                     # [{name, kind, half_w, pts: PackedVector3Array}]
var ponds := []                       # [{name, level, poly: PackedVector2Array, aabb: Rect2}]
var drop_trees := {}                  # pořadí stromu v trees.bin → true (stojí ve vodě)
var ice := 0.0                        # zamrznutí rybníků 0..1 (tekoucí voda: ice_flow)
var ice_flow := 0.0

var _cells := {}                      # Vector2i → [[stream, i], …]
var _mat_stream: ShaderMaterial
var _mats := []                       # všechny materiály (led, vlnky)
var _last_min := -1.0
var _tick := 0.0


## Načte data (bez stavby) – hned po terénu, ať MapLoader ví, které stromy vynechat.
func load_data() -> bool:
	if not FileAccess.file_exists("res://data/water.json"):
		push_warning("Chybí data/water.json (python3 tools/water.py) – svět bude bez potoků.")
		return false
	data = JSON.parse_string(FileAccess.get_file_as_string("res://data/water.json"))
	for i in data.get("drop_trees", []):
		drop_trees[int(i)] = true
	return true


func build(w: World, t: Terrain) -> void:
	world = w
	terrain = t
	if data.is_empty():
		return
	var noise := FastNoiseLite.new()
	noise.frequency = 0.05
	noise.fractal_octaves = 3
	var ntex := NoiseTexture2D.new()
	ntex.width = 256
	ntex.height = 256
	ntex.seamless = true
	ntex.generate_mipmaps = true
	ntex.noise = noise
	var kinds: Dictionary = data.get("kinds", {})
	var by_kind := {}
	for s in data.get("streams", []):
		var kind := String(s["kind"])
		var pts := PackedVector3Array()
		for p in s["pts"]:
			pts.append(Vector3(p[0], p[2], p[1]))
		var st := {"name": String(s.get("name", "")), "kind": kind,
			"half_w": float(kinds.get(kind, {}).get("half_w", 1.5)), "pts": pts}
		var si := streams.size()
		streams.append(st)
		for i in pts.size() - 1:
			var key := Vector2i(floori(pts[i].x / CELL), floori(pts[i].z / CELL))
			for dx in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					var k2 := key + Vector2i(dx, dz)
					if not _cells.has(k2):
						_cells[k2] = []
					_cells[k2].append([si, i])
		if not by_kind.has(kind):
			by_kind[kind] = []
		by_kind[kind].append(si)
	# hladiny toků: jeden mesh na tok (po druzích kvůli rychlosti proudu)
	for kind in by_kind:
		var m := _material(ntex, float(FLOW.get(kind, 0.6)))
		if kind == "river":
			m.set_shader_parameter("shallow_color", Color(0.33, 0.36, 0.27))
			m.set_shader_parameter("deep_color", Color(0.12, 0.14, 0.09))
		for si in by_kind[kind]:
			var mi := MeshInstance3D.new()
			mi.name = "Tok_%d" % si
			mi.mesh = _ribbon(streams[si])
			mi.material_override = m
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_end = _vis_end(mi.mesh)
			add_child(mi)
	# rybníky
	var mp := _material(ntex, 0.0)
	mp.set_shader_parameter("shallow_color", Color(0.25, 0.33, 0.26))
	for pd in data.get("ponds", []):
		var poly := PackedVector2Array()
		for q in pd["poly"]:
			poly.append(Vector2(q[0], q[1]))
		if Geometry2D.is_polygon_clockwise(poly):
			poly.reverse()
		var level := float(pd["level"])
		var tri := Geometry2D.triangulate_polygon(poly)
		if tri.is_empty():
			continue
		var v := PackedVector3Array()
		var uv := PackedVector2Array()
		for i in range(tri.size() - 1, -1, -1):       # Godot: přední strana po směru hodin
			var q := poly[tri[i]]
			v.append(Vector3(q.x, level, q.y))
			uv.append(q)
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_TEX_UV] = uv
		var nn := PackedVector3Array()
		nn.resize(v.size())
		nn.fill(Vector3.UP)
		arr[Mesh.ARRAY_NORMAL] = nn
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mi := MeshInstance3D.new()
		mi.name = "Rybnik"
		mi.mesh = am
		mi.material_override = mp
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = _vis_end(am)
		add_child(mi)
		var r := Rect2(poly[0], Vector2.ZERO)
		for q in poly:
			r = r.expand(q)
		ponds.append({"name": String(pd.get("name", "")), "level": level, "poly": poly, "aabb": r.grow(1.0)})


## Dohled hladiny: Godot ho měří od STŘEDU AABB meshe. Tok je jeden mesh dlouhý i několik km
## (union mapa), takže pevný VIS_RANGE by ho schoval i hráči stojícímu na břehu daleko od
## středu toku → dohled + půlka vodorovné úhlopříčky (každý kus toku vidět aspoň do VIS_RANGE).
static func _vis_end(m: Mesh) -> float:
	var ab := m.get_aabb()
	return VIS_RANGE + Vector2(ab.size.x, ab.size.z).length() * 0.5


func _material(ntex: Texture2D, flow: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/water.gdshader")
	m.set_shader_parameter("noise_tex", ntex)
	m.set_shader_parameter("flow_speed", flow)
	m.set_meta("flowing", flow > 0.01)
	_mats.append(m)
	return m


## Pás hladiny podél osy: v každém bodě dva vrcholy (vlevo / vpravo) ve výšce hladiny.
func _ribbon(st: Dictionary) -> ArrayMesh:
	var pts: PackedVector3Array = st["pts"]
	var hw: float = st["half_w"]
	var n := pts.size()
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var nn := PackedVector3Array()
	var idx := PackedInt32Array()
	var along := 0.0
	for i in n:
		var a := pts[maxi(i - 1, 0)]
		var b := pts[mini(i + 1, n - 1)]
		var tng := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
		var side := Vector3(-tng.z, 0.0, tng.x) * hw
		if i > 0:
			along += Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length()
		v.append(pts[i] - side)
		v.append(pts[i] + side)
		uv.append(Vector2(along, 0.0))
		uv.append(Vector2(along, 1.0))
		nn.append(Vector3.UP)
		nn.append(Vector3.UP)
	for i in n - 1:
		var k := i * 2
		idx.append_array([k, k + 2, k + 1, k + 1, k + 2, k + 3])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nn
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


# ------------------------------------------------------------------ dotazy

## Voda v bodě: {depth (m, 0 = sucho), name, kind ("river", "stream", …, "pond"), level}.
func info_at(x: float, z: float) -> Dictionary:
	var best := {"depth": 0.0, "name": "", "kind": "", "level": -INF}
	var key := Vector2i(floori(x / CELL), floori(z / CELL))
	var p := Vector2(x, z)
	for e in _cells.get(key, []):
		var st: Dictionary = streams[e[0]]
		var pts: PackedVector3Array = st["pts"]
		var a := pts[e[1]]
		var b := pts[e[1] + 1]
		var a2 := Vector2(a.x, a.z)
		var ab := Vector2(b.x, b.z) - a2
		var t := clampf((p - a2).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		if p.distance_to(a2 + ab * t) > float(st["half_w"]):
			continue
		var level := lerpf(a.y, b.y, t)
		var depth := level - terrain.height_at(x, z)
		if depth > best["depth"]:
			best = {"depth": depth, "name": st["name"], "kind": st["kind"], "level": level}
	for pd in ponds:
		if (pd["aabb"] as Rect2).has_point(p) and Geometry2D.is_point_in_polygon(p, pd["poly"]):
			var depth: float = pd["level"] - terrain.height_at(x, z)
			if depth > best["depth"]:
				best = {"depth": depth, "name": pd["name"], "kind": "pond", "level": pd["level"]}
	return best


## Nejbližší bod tekoucí vody do `r` m (pro šumění potoka): [bod, druh] nebo [].
func nearest_stream(pos: Vector3, r: float) -> Array:
	var best := []
	var bd := r
	var p := Vector2(pos.x, pos.z)
	var c0 := Vector2i(floori(pos.x / CELL), floori(pos.z / CELL))
	var reach := ceili(r / CELL)
	var seen := {}
	for dx in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			for e in _cells.get(c0 + Vector2i(dx, dz), []):
				var k: int = e[0] * 100000 + e[1]
				if seen.has(k):
					continue
				seen[k] = true
				var st: Dictionary = streams[e[0]]
				var pts: PackedVector3Array = st["pts"]
				var a := pts[e[1]]
				var b := pts[e[1] + 1]
				var q := Geometry3D.get_closest_point_to_segment(pos, a, b)
				var d := Vector2(q.x, q.z).distance_to(p)
				if d < bd:
					bd = d
					best = [q, st["kind"]]
	return best


# ------------------------------------------------------------------ led, vlnky, brodění hráčů

func _process(delta: float) -> void:
	var __t0 := Tests.prof_t0()
	_process_impl(delta)
	Tests.prof_add("water", __t0)


func _process_impl(delta: float) -> void:
	if world == null or world.clock == null:
		return
	_tick += delta
	if _tick < 0.2:
		return
	_tick = 0.0
	# hráči ve vodě (Player.wade brzdí chůzi)
	for pl in world.players.values():
		var pp: Vector3 = pl.global_position
		var inf := info_at(pp.x, pp.z)
		pl.wade = 0.0 if pl.car or pl.horse else maxf(float(inf["depth"]), 0.0) * (1.0 - ice_flow)
		pl.water_level = float(inf["level"])
		# teplota vody (M5.2): sezóna + vzduch – chladí tělo ve vodě (Player._update_body)
		if world.weather != null and world.clock != null:
			pl.water_temp = Koupaliste.water_temp(world.clock.day_of_year(), world.weather.temp)
	# zamrzání podle teploty (herní čas): rybník pod −1 °C, potok pod −5 °C, tání nad nulou
	var now: float = world.clock.minutes
	if _last_min < 0.0:
		_last_min = now
		var t0: float = world.weather.temp
		ice = clampf((-t0 - 1.0) / 4.0, 0.0, 1.0)
		ice_flow = clampf((-t0 - 5.0) / 6.0, 0.0, 1.0)
	var dh := clampf((now - _last_min) / 60.0, 0.0, 48.0)
	_last_min = now
	var temp: float = world.weather.temp
	ice = move_toward(ice, clampf((-temp - 1.0) / 4.0, 0.0, 1.0), dh * 0.08)
	ice_flow = move_toward(ice_flow, clampf((-temp - 5.0) / 6.0, 0.0, 1.0), dh * 0.05)
	var waves := 1.0 + world.weather.rain * 0.8 + clampf(world.weather.wind / 10.0, 0.0, 1.0) * 0.7
	for m in _mats:
		var ic := ice_flow if m.get_meta("flowing") else ice
		m.set_shader_parameter("ice", ic)
		m.set_shader_parameter("snow", world.weather.snow_cover * ic)
		m.set_shader_parameter("wave_scale", waves)
