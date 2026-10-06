## Pouliční osvětlení v obci a světelný smog (M5.12) – klientská prezentace, stav odvozuje z hodin:
## - lampy podél silnic v obci (residential, tertiary, unclassified, living_street; ne service / track), deterministicky
##   (seed), ~35 m, střídavě po stranách, mimo křižovatky a mimo ostatní silnice; model PropModels.street_lamp v MultiMesh
## - svítící hlavice (MultiMesh, jas v instance custom data) – vidět z dálky jako řada světel
## - pool OmniLight3D jen u nejbližších svítících lamp u kamery (počet podle grafické předvolby, bez stínů)
## - rozsvícení za soumraku, zhasnutí za svítání, s náhodným zpožděním; v noci 0–4 h každá druhá lampa zhasnutá (úspora)
## - index světelného smogu v místě kamery (0 les … 1 náves) → Atmosphere (uniform light_pollution v obloze)
## Lampy jsou jen vizuál: bez kolize, bez stavu v uložené pozici (stav plyne z času a ze seedu).
class_name StreetLights
extends Node3D

## Ladicí konstanty
const ROAD_KINDS := ["residential", "tertiary", "unclassified", "living_street"]
const SEED := 12
const SPACING := 35.0              # m mezi lampami podél silnice (× 0,9–1,15 náhoda)
const OFFSET := 4.2                # m od osy silnice (střídavě levá / pravá strana)
const JUNCTION_GAP := 9.0          # m: lampa nestojí blíž ke křižovatce
const MIN_LAMP_GAP := 18.0         # m mezi dvěma lampami
const MAX_LAMPS := 320
const HEAD_LOCAL := Vector3(0, 5.84, 1.0)     # hlavice v modelu PropModels.street_lamp (vysunutá nad vozovku)
const FADE_S := 3.0                # reálné s přechodu rozsvícení / zhasnutí
const DELAY_MAX_S := 20.0          # reálné s – náhodné zpoždění jednotlivé lampy
const NIGHT_SAVE_FROM := 0.0       # herní hodiny: úsporný režim (každá druhá lampa zhasnutá)
const NIGHT_SAVE_TO := 4.0
const LIGHT_POOL := [0, 8, 16, 16]          # počet OmniLight3D podle předvolby GameSettings (0 … 3)
const LIGHT_RANGE := 13.0
const LIGHT_ENERGY := 2.4
const LIGHT_UPDATE_S := 0.5
const SMOG_SIGMA := 170.0          # m – dosah světelného smogu z lamp
const SMOG_UPDATE_S := 0.5
const SHOW_DIST := 620.0           # m – lampy dál od kamery se neposílají do pool světel (jen hlavice)

## Stav klienta
var pollution := 0.0               # index světelného smogu v místě kamery 0..1 (čte local_client → Atmosphere)
var lamp_count := 0

var _clock: Clock
var _world: World
var _settings: GameSettings
var _xz := PackedVector2Array()    # poloha lamp (svět x, z)
var _pos := PackedVector3Array()   # poloha hlavice (svět)
var _basis: Array[Basis] = []
var _lvl := PackedFloat32Array()   # jas 0..1
var _want := PackedFloat32Array()  # cílový jas
var _wait := PackedFloat32Array()  # zbývající zpoždění před přechodem (s)
var _delay := PackedFloat32Array() # náhodné zpoždění této lampy (s)
var _poles: MultiMeshInstance3D
var _heads: MultiMeshInstance3D
var _lights: Array[OmniLight3D] = []
var _ref := 1.0                    # smog v náves při všech lampách naplno (normalizace)
var _light_t := 0.0
var _smog_t := 0.0


## Postaví lampy podle silnic obce. Volá se po World.build() (graf silnic existuje).
func setup(world: World, settings: GameSettings) -> void:
	_world = world
	_clock = world.clock
	_settings = settings
	var graph: RoadGraph = world.graph
	var centre := Traffic.VILLAGE_CENTER
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var placed: Array[Vector2] = []
	var nodes := graph.nodes_within(centre, Traffic.VILLAGE_R, ROAD_KINDS)
	for i in nodes:
		if placed.size() >= MAX_LAMPS:
			break
		for j in graph.adj[i]:
			if not ROAD_KINDS.has(graph.edge(i, j)):
				continue
			var a: Vector2 = graph.nodes[i]
			var b: Vector2 = graph.nodes[j]
			var len_m := a.distance_to(b)
			if len_m < 2.0:
				continue
			var dir := (b - a) / len_m
			var normal := Vector2(-dir.y, dir.x)
			var side := 1.0 if rng.randf() < 0.5 else -1.0
			var d := 6.0 if graph.adj[i].size() <= 2 else JUNCTION_GAP
			while d < len_m - JUNCTION_GAP:
				var p := a + dir * d + normal * OFFSET * side
				d += SPACING * rng.randf_range(0.9, 1.15)
				side = -side
				if p.distance_to(centre) > Traffic.VILLAGE_R:
					continue
				if _near_junction(graph, p) or world.dist_to_roads(p) < OFFSET - 1.0:
					continue
				var too_close := false
				for q in placed:
					if q.distance_to(p) < MIN_LAMP_GAP:
						too_close = true
						break
				if too_close:
					continue
				placed.append(p)
				# hlavice míří přes vozovku: lokální +Z modelu → od kraje k silnici
				var f := -normal * side
				_basis.append(Basis(Vector3.UP, atan2(f.x, f.y)))
				_xz.append(p)
				if placed.size() >= MAX_LAMPS:
					break
			if placed.size() >= MAX_LAMPS:
				break
	_build_meshes(world)
	_build_lights()
	# normalizace smogu: náves při všech lampách naplno = 1
	_ref = 0.0
	for k in _xz.size():
		_ref += exp(-_xz[k].distance_squared_to(centre) / (2.0 * SMOG_SIGMA * SMOG_SIGMA))
	_ref = maxf(_ref, 0.001)
	lamp_count = _xz.size()


## Křižovatka (uzel s více než dvěma sousedy) poblíž bodu p.
func _near_junction(graph: RoadGraph, p: Vector2) -> bool:
	for n in graph.nodes_within(p, JUNCTION_GAP):
		if graph.adj[n].size() > 2:
			return true
	return false


func _build_meshes(world: World) -> void:
	var n := _xz.size()
	_lvl.resize(n)
	_want.resize(n)
	_wait.resize(n)
	_delay.resize(n)
	_pos.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 1
	var base_t: Array[Transform3D] = []
	for k in n:
		_lvl[k] = 0.0
		_want[k] = -1.0
		_wait[k] = 0.0
		_delay[k] = rng.randf_range(0.0, DELAY_MAX_S)
		var x := _xz[k].x
		var z := _xz[k].y
		base_t.append(Transform3D(_basis[k], Vector3(x, world.terrain.height_at(x, z) + 0.02, z)))
		_pos[k] = base_t[k] * HEAD_LOCAL
	# sloupy (bez stínů a kolize)
	var pole_mm := MultiMesh.new()
	pole_mm.transform_format = MultiMesh.TRANSFORM_3D
	pole_mm.mesh = PropModels.street_lamp()
	pole_mm.instance_count = n
	for k in n:
		pole_mm.set_instance_transform(k, base_t[k])
	_poles = MultiMeshInstance3D.new()
	_poles.name = "Sloupy"
	_poles.multimesh = pole_mm
	_poles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_poles.visibility_range_end = 700.0
	add_child(_poles)
	# svítící hlavice – jas v custom data (r), shader ho převádí na emisi
	var head_mm := MultiMesh.new()
	head_mm.transform_format = MultiMesh.TRANSFORM_3D
	head_mm.use_custom_data = true
	var box := BoxMesh.new()
	box.size = Vector3(0.22, 0.04, 0.46)
	head_mm.mesh = box
	head_mm.instance_count = n
	for k in n:
		head_mm.set_instance_transform(k, Transform3D(_basis[k], _pos[k]))
		head_mm.set_instance_custom_data(k, Color(0, 0, 0, 0))
	_heads = MultiMeshInstance3D.new()
	_heads.name = "Hlavice"
	_heads.multimesh = head_mm
	_heads.material_override = _head_material()
	_heads.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_heads.visibility_range_end = 900.0
	add_child(_heads)


func _head_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 lamp_col : source_color = vec3(1.0, 0.82, 0.52);
uniform float emit_max = 5.0;
varying float lamp;
void vertex() {
	lamp = INSTANCE_CUSTOM.r;
}
void fragment() {
	ALBEDO = vec3(0.55, 0.55, 0.5);
	EMISSION = lamp_col * lamp * emit_max;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


func _build_lights() -> void:
	for i in LIGHT_POOL[LIGHT_POOL.size() - 1]:
		var l := OmniLight3D.new()
		l.name = "Svetlo%d" % i
		l.light_color = Color(1.0, 0.78, 0.5)
		l.omni_range = LIGHT_RANGE
		l.shadow_enabled = false
		l.visible = false
		add_child(l)
		_lights.append(l)


## Plynulý přechod, zpoždění, noční úspora. Každý snímek (jen přepisuje změněné jasy).
func _process(delta: float) -> void:
	if _clock == null or _lvl.is_empty():
		return
	var night := _clock.is_night()
	var h := _clock.hour()
	var saving := h >= NIGHT_SAVE_FROM and h < NIGHT_SAVE_TO
	var head_mm := _heads.multimesh
	for k in _lvl.size():
		var want := 1.0 if (night and not (saving and k % 2 == 1)) else 0.0
		if want != _want[k]:
			_want[k] = want
			_wait[k] = _delay[k]
		if _wait[k] > 0.0:
			_wait[k] -= delta
			continue
		var lv := move_toward(_lvl[k], want, delta / FADE_S)
		if lv != _lvl[k]:
			_lvl[k] = lv
			head_mm.set_instance_custom_data(k, Color(lv, 0, 0, 0))
	var cam := _camera()
	if cam == null:
		return
	_light_t -= delta
	if _light_t <= 0.0:
		_light_t = LIGHT_UPDATE_S
		_update_lights(cam.global_position)
	_smog_t -= delta
	if _smog_t <= 0.0:
		_smog_t = SMOG_UPDATE_S
		_update_smog(cam.global_position)


func _camera() -> Camera3D:
	return get_viewport().get_camera_3d() if is_inside_tree() else null


## Pool světel: jen nejbližší svítící lampy u kamery (počet z předvolby).
func _update_lights(cam: Vector3) -> void:
	var preset := clampi(_settings.preset if _settings else 2, 0, LIGHT_POOL.size() - 1)
	var count: int = mini(LIGHT_POOL[preset], _lights.size())
	var picked: Array = []      # [d2, k]
	var c2 := Vector2(cam.x, cam.z)
	for k in _lvl.size():
		if _lvl[k] < 0.2:
			continue
		var d2 := _xz[k].distance_squared_to(c2)
		if d2 > SHOW_DIST * SHOW_DIST:
			continue
		if picked.size() < count:
			picked.append([d2, k])
			continue
		var worst := 0
		for i in picked.size():
			if picked[i][0] > picked[worst][0]:
				worst = i
		if d2 < picked[worst][0]:
			picked[worst] = [d2, k]
	for i in _lights.size():
		var l := _lights[i]
		if i < picked.size():
			var k: int = picked[i][1]
			l.visible = true
			l.position = _pos[k] + Vector3(0, -0.35, 0)
			l.light_energy = _lvl[k] * LIGHT_ENERGY
		else:
			l.visible = false


## Index světelného smogu: hustota svítících lamp kolem kamery (Gaussova jádra), normalizovaný k návsi.
func _update_smog(cam: Vector3) -> void:
	var c2 := Vector2(cam.x, cam.z)
	var raw := 0.0
	for k in _lvl.size():
		if _lvl[k] <= 0.0:
			continue
		raw += _lvl[k] * exp(-_xz[k].distance_squared_to(c2) / (2.0 * SMOG_SIGMA * SMOG_SIGMA))
	pollution = clampf(raw / _ref, 0.0, 1.0)
