## Květy v trávě: MultiMesh drobných květů (bílé, žluté, fialové, růžové) na loukách, v sadech a zahrádkách
## (Fields třídy 2–4) v okolí hráče. Hustota podle `Seasons.bloom(doy)`; přestavuje se, když se hráč posune
## o `REBUILD_DIST`, změní se den nebo se kvetení výrazně změní. Květy jsou přichycené k pevné mřížce buněk
## (stabilní poloha při přestavbě), nerostou na silnicích a cestách (maska podle grafu silnic) ani v zástavbě.
## Na zem přidávají i barevné tečky v terénním shaderu (`meadow_bloom`) – zdálky.
## Přestavba běží po kouscích přes několik snímků (FRAME_BUDGET_US) a do MultiMesh se zapíše najednou
## jedním bufferem – pohyb hráče tak nezpůsobí záseky. `detail` (Nastavení → Grafika) zmenší okruh, 0 = bez květů.
class_name MeadowFlowers
extends Node3D

const RADIUS := 70.0
const CELL := 1.7                     # m – jedna buňka = nejvýš jeden květ
const MAX_FLOWERS := 4000
const FRAME_BUDGET_US := 1500          # nejvýš ~1,5 ms přestavby za snímek
const REBUILD_DIST := 25.0
const ROAD_HALF := 3.2                # m od osy silnice/cesty bez květů
## Podíl buněk s květem při plném kvetení podle třídy plochy (2 louka, 3 sad, 4 zahrádky)
const DENSITY := {2: 0.34, 3: 0.3, 4: 0.16}
const SETTLE_MAX := 0.7               # v husté zástavbě na louce květy nejsou
## Barvy: bílá, žlutá, fialová, růžová; na jaře (kolem dne 100) víc bílé a žluté, v létě fialové a růžové
const PALETTE := [Color(0.95, 0.95, 0.92), Color(0.98, 0.85, 0.15), Color(0.6, 0.35, 0.8), Color(0.95, 0.55, 0.7)]

var world: World
var fields: Fields
var terrain: Terrain
var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _last_pos := Vector3(1e9, 0, 1e9)
var _last_jd := -1
var _last_bloom := -1.0
var _busy := false
var detail := 1.0                      # 0 = vypnuto, 0.5–1 = poměr okruhu (Nastavení → Grafika → Vegetace)


func set_detail(d: float) -> void:
	if is_equal_approx(d, detail):
		return
	detail = d
	_last_pos = Vector3(1e9, 0, 1e9)       # přestavět při příští aktualizaci


func setup(w: World) -> void:
	world = w
	fields = w.fields
	terrain = w.terrain
	top_level = true
	var mesh := SphereMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.07
	mesh.radial_segments = 6
	mesh.rings = 3
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.85
	mesh.material = mat
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = mesh
	_mm.instance_count = MAX_FLOWERS
	_mm.visible_instance_count = 0
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = _mm
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mmi)


## Volá se párkrát za sekundu: `pos` = poloha hráče, `doy` = den v roce, `snow` = sníh na zemi 0..1.
func update(pos: Vector3, doy: float, snow: float, jd: int) -> void:
	if fields == null or not fields.loaded:
		return
	if _busy:
		return
	var bloom := Seasons.bloom(doy) * (1.0 - clampf(snow * 2.0, 0.0, 1.0))
	if bloom < 0.03 or detail <= 0.0:
		_mmi.visible = false
		_last_bloom = bloom
		return
	_mmi.visible = true
	var moved := Vector2(pos.x - _last_pos.x, pos.z - _last_pos.z).length()
	if moved < REBUILD_DIST and jd == _last_jd and absf(bloom - _last_bloom) < 0.08:
		return
	_last_pos = pos
	_last_jd = jd
	_last_bloom = bloom
	_rebuild(pos, doy, bloom)


func _rebuild(pos: Vector3, doy: float, bloom: float) -> void:
	_busy = true
	var rad := RADIUS * detail
	var n_side := int(2.0 * rad / CELL) + 1
	var cx0 := floori((pos.x - rad) / CELL)
	var cz0 := floori((pos.z - rad) / CELL)
	var road: PackedByteArray = await _road_mask(cx0, cz0, n_side, rad)
	# jarní směs (bílá, žlutá) → letní (fialová, růžová)
	var summer := smoothstep(120.0, 190.0, doy)
	var buf := PackedFloat32Array()
	buf.resize(MAX_FLOWERS * 16)
	var n := 0
	var t0 := Time.get_ticks_usec()
	for gz in n_side:
		if Time.get_ticks_usec() - t0 > FRAME_BUDGET_US:
			await get_tree().process_frame
			if not is_inside_tree():
				return
			t0 = Time.get_ticks_usec()
		if n >= MAX_FLOWERS:
			break
		for gx in n_side:
			var cx := cx0 + gx
			var cz := cz0 + gz
			var h1 := Fields._hash(cx, cz)
			var x := (cx + 0.15 + 0.7 * float(h1 % 1000) / 1000.0) * CELL
			var z := (cz + 0.15 + 0.7 * float((h1 / 1000) % 1000) / 1000.0) * CELL
			if (x - pos.x) * (x - pos.x) + (z - pos.z) * (z - pos.z) > rad * rad:
				continue
			var cls := fields.class_at(x, z)
			if cls < 2 or cls > 4:
				continue
			var roll: float = float((h1 / 1000000) % 1000) / 1000.0
			var dens: float = DENSITY[cls]
			if roll >= dens * bloom:
				continue
			if road[gz * n_side + gx] != 0:
				continue
			if cls == 2 and world.fauna and world.fauna.settle_at(x, z) > SETTLE_MAX:
				continue
			var h2 := Fields._hash(cx * 31 + 7, cz * 17 + 3)
			var pick := float(h2 % 1000) / 1000.0
			var ci := 0
			if pick < lerpf(0.55, 0.15, summer):
				ci = 0 if (h2 / 1000) % 2 == 0 else 1
			else:
				ci = 2 if (h2 / 1000) % 3 != 0 else 3
			var y := terrain.height_at(x, z) + 0.04
			var sc := 0.7 + float((h2 / 7) % 100) / 100.0 * 0.7
			# řádky matice 3×4 (otočení kolem Y a měřítko) + barva RGBA
			var a := float(h2 % 628) / 100.0
			var c := cos(a) * sc
			var si := sin(a) * sc
			var col: Color = PALETTE[ci]
			var o := n * 16
			buf[o] = c; buf[o + 1] = 0.0; buf[o + 2] = si; buf[o + 3] = x
			buf[o + 4] = 0.0; buf[o + 5] = sc; buf[o + 6] = 0.0; buf[o + 7] = y
			buf[o + 8] = -si; buf[o + 9] = 0.0; buf[o + 10] = c; buf[o + 11] = z
			buf[o + 12] = col.r; buf[o + 13] = col.g; buf[o + 14] = col.b; buf[o + 15] = col.a
			n += 1
			if n >= MAX_FLOWERS:
				break
	_mm.buffer = buf
	_mm.visible_instance_count = n
	_busy = false


## Maska buněk u silnic a cest (podle grafu silnic): 1 = bez květů.
func _road_mask(cx0: int, cz0: int, n_side: int, rad: float) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(n_side * n_side)
	var g: RoadGraph = world.graph
	if g == null:
		return mask
	var center := Vector2((cx0 + n_side * 0.5) * CELL, (cz0 + n_side * 0.5) * CELL)
	var reach := int(ROAD_HALF / CELL) + 1
	var t0 := Time.get_ticks_usec()
	for i in g.nodes_within(center, rad * 1.5 + 30.0):
		if Time.get_ticks_usec() - t0 > FRAME_BUDGET_US:
			await get_tree().process_frame
			t0 = Time.get_ticks_usec()
		var a: Vector2 = g.nodes[i]
		for j in g.adj[i]:
			if j < i:
				continue
			var b: Vector2 = g.nodes[j]
			var steps := maxi(int(a.distance_to(b) / (CELL * 0.6)), 1)
			for s in steps + 1:
				var q := a.lerp(b, float(s) / steps)
				var gx := floori(q.x / CELL) - cx0
				var gz := floori(q.y / CELL) - cz0
				for dz in range(-reach, reach + 1):
					for dx in range(-reach, reach + 1):
						var ix := gx + dx
						var iz := gz + dz
						if ix < 0 or iz < 0 or ix >= n_side or iz >= n_side:
							continue
						var cxw := (cx0 + ix + 0.5) * CELL
						var czw := (cz0 + iz + 0.5) * CELL
						if (cxw - q.x) * (cxw - q.x) + (czw - q.y) * (czw - q.y) < ROAD_HALF * ROAD_HALF:
							mask[iz * n_side + ix] = 1
	return mask
