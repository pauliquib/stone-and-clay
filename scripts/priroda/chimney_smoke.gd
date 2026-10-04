## Kouř z komínů podle teploty (M1.3) – čistě vizuál klienta.
##
## Každé ~2 s vezme komíny do `NEAR_R` od kamery (`BuildingDetails.chimneys_near`), pro každý určí, jestli
## dům právě topí (pravděpodobnost `p(T)` × denní chod, deterministicky podle komína a dne), a nejbližším
## kouřícím přiřadí emitor z poolu (max. `POOL` GPUParticles3D). Síla, barva, vítr, mlha a déšť se nastavují
## podle tabulky `SmokeRules` níže. Bez `World.building_details` (chybí data/buildings.json) nedělá nic.
##
## Úpravy: tabulka `SmokeRules` (prahy teploty, denní chod, vítr, mlha).
class_name ChimneySmoke
extends Node3D

## Laditelná pravidla. DOPLNIT: hodnoty jsou výchozí odhad z promptu M1.3, ladit vizuálně.
const SmokeRules := {
	## [teplota °C, pravděpodobnost topení] – lineárně mezi body (řazeno od nejteplejší).
	"p_curve": [[16.0, 0.03], [12.0, 0.15], [8.0, 0.35], [3.0, 0.65], [0.0, 0.85], [-5.0, 1.0]],
	"morning": [5.0, 9.0, 1.2],        # [od h, do h, násobek] – zatápění
	"evening": [16.0, 22.0, 1.2],
	"night": [23.0, 4.0, 0.7],         # přes půlnoc, dohořívá
	"gale": 6.0,                       # m/s – nad tím se kouř trhá a leží níž
	"fog_inversion": 0.4,              # fog nad tímto = inverze
	"frost_calm_temp": 0.0,            # mráz za bezvětří ráno = inverze
	"frost_calm_wind": 1.5,
	"life": 8.0,                       # s – životnost částice v klidu
}
const POOL := 24
const NEAR_R := 350.0
const TICK_S := 2.0

var world: World
var player: Player
var _t := 0.0
var _slots: Array = []                 # [{node: GPUParticles3D, mat: ParticleProcessMaterial, key: Vector3 (pozice komína), amount: int}]
var _mesh: QuadMesh
var _ramp: GradientTexture1D
var _smoke_mat: StandardMaterial3D
var last_active := 0                   # kolik emitorů právě kouří (ladění)


func setup(w: World, p: Player) -> void:
	world = w
	player = p
	_t = 0.5


## Pravděpodobnost, že dům topí, při teplotě `temp` (bez denního chodu).
static func heat_probability(temp: float) -> float:
	var c: Array = SmokeRules["p_curve"]
	if temp >= float(c[0][0]):
		return float(c[0][1])
	if temp <= float(c[c.size() - 1][0]):
		return float(c[c.size() - 1][1])
	for i in c.size() - 1:
		var a: Array = c[i]
		var b: Array = c[i + 1]
		if temp <= float(a[0]) and temp >= float(b[0]):
			var k := (float(a[0]) - temp) / (float(a[0]) - float(b[0]))
			return lerpf(float(a[1]), float(b[1]), k)
	return 0.0


## Násobek podle denní doby (ráno a večer víc, v noci méně).
static func day_factor(hour: float) -> float:
	var m: Array = SmokeRules["morning"]
	var e: Array = SmokeRules["evening"]
	var n: Array = SmokeRules["night"]
	if hour >= float(m[0]) and hour < float(m[1]):
		return float(m[2])
	if hour >= float(e[0]) and hour < float(e[1]):
		return float(e[2])
	if hour >= float(n[0]) or hour < float(n[1]):
		return float(n[2])
	return 1.0


## Pseudonáhodné číslo 0..1 stálé pro komín a den (nezávisí na teplotě ani hodině → během dne neblikne).
static func roll(id: int, pos: Vector3, jd: int) -> float:
	var h := (id * 73856093) ^ (int(pos.x * 4.0) * 19349663) ^ (int(pos.z * 4.0) * 83492791) ^ (jd * 2654435761)
	h = (h ^ (h >> 15)) * 2246822519 & 0x7fffffff
	h = (h ^ (h >> 13)) * 3266489917 & 0x7fffffff
	h = h ^ (h >> 16)
	return float(h & 0xffff) / 65535.0


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0 or world == null or world.clock == null or world.weather == null:
		return
	_t = TICK_S
	_refresh()


func _refresh() -> void:
	var bd: BuildingDetails = world.building_details
	if bd == null:
		_release_all()
		return
	var cam := get_viewport().get_camera_3d()
	var center: Vector3 = cam.global_position if cam else (player.global_position if player else Vector3.ZERO)
	var w: Weather = world.weather
	var clock: Clock = world.clock
	var hour := clock.hour()
	var jd := clock.jd()
	var p := minf(heat_probability(w.temp) * day_factor(hour), 1.0)
	# kouřící komíny v dosahu, nejbližší první; komín domova kouří vždy, když se doma topí v kamnech (M2.2)
	var forced_id := world.home_chimney_id()
	var cands: Array = []
	if p > 0.0 or forced_id > 0:
		for c in bd.chimneys_near(center, NEAR_R):
			var cp: Vector3 = c["pos"]
			if (forced_id > 0 and int(c["id"]) == forced_id) or (p > 0.0 and roll(int(c["id"]), cp, jd) < p):
				var dx := cp.x - center.x
				var dz := cp.z - center.z
				cands.append([dx * dx + dz * dz, cp])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	if cands.size() > POOL:
		cands.resize(POOL)
	# emitory, které už na svém komíně stojí, si ho nechají
	var spare: Array = []
	var wanted: Array = []
	for c in cands:
		wanted.append(c[1])
	for s in _slots:
		var k: Vector3 = s["key"]
		var idx := -1
		for i in wanted.size():
			if (wanted[i] as Vector3).is_equal_approx(k):
				idx = i
				break
		if idx >= 0 and s["node"].visible:
			wanted.remove_at(idx)
			s["keep"] = true
		else:
			s["keep"] = false
			spare.append(s)
	for pos in wanted:
		var s: Dictionary
		if not spare.is_empty():
			s = spare.pop_back()
		elif _slots.size() < POOL:
			s = _make_slot()
		else:
			break
		s["key"] = pos
		s["node"].global_position = pos
		s["keep"] = true
	var active := 0
	for s in _slots:
		var node: GPUParticles3D = s["node"]
		if s["keep"]:
			node.visible = true
			_apply(s, w, hour, clock)
			active += 1
		else:
			node.emitting = false
			node.visible = false
	last_active = active


func _release_all() -> void:
	for s in _slots:
		s["node"].emitting = false
		s["node"].visible = false
	last_active = 0


## Nastaví emitor podle počasí a denní doby.
func _apply(s: Dictionary, w: Weather, hour: float, clock: Clock) -> void:
	var node: GPUParticles3D = s["node"]
	var m: ParticleProcessMaterial = s["mat"]
	var frost := clampf((16.0 - w.temp) / 21.0, 0.0, 1.0)         # 0 v teple … 1 při −5 °C
	var strength := 0.25 + 0.75 * frost
	var gale: float = SmokeRules["gale"]
	var windy := clampf((w.wind - gale) / gale, 0.0, 1.0)
	var inversion: bool = w.fog > float(SmokeRules["fog_inversion"]) or (
		w.temp < float(SmokeRules["frost_calm_temp"]) and w.wind < float(SmokeRules["frost_calm_wind"])
		and hour >= 4.0 and hour < 10.0)
	var life: float = SmokeRules["life"] * (1.0 - 0.4 * clampf(w.rain, 0.0, 1.0)) * (1.0 - 0.4 * windy)
	# vítr: zrychlení po větru (částice za život urazí zhruba polovinu rychlosti větru × život)
	var wv := w.wind_vector()
	var buoy := 0.28 * (1.0 - 0.7 * windy)
	if inversion:
		m.direction = Vector3.UP
		m.spread = 75.0
		m.initial_velocity_min = 1.2
		m.initial_velocity_max = 2.4
		m.damping_min = 0.8
		m.damping_max = 1.1
		m.gravity = Vector3(wv.x * 0.06, 0.0, wv.z * 0.06)
		life *= 1.4
	else:
		m.direction = Vector3.UP
		m.spread = 10.0 + 25.0 * windy
		m.initial_velocity_min = (0.9 + 0.5 * strength) * (1.0 - 0.4 * windy)
		m.initial_velocity_max = (1.5 + 0.9 * strength) * (1.0 - 0.4 * windy)
		m.damping_min = 0.0
		m.damping_max = 0.15
		m.gravity = Vector3(wv.x * 0.2, buoy, wv.z * 0.2)
	m.turbulence_enabled = windy > 0.0
	m.turbulence_noise_strength = 1.0 + 3.0 * windy
	m.turbulence_influence_min = 0.05
	m.turbulence_influence_max = 0.05 + 0.25 * windy
	# barva: ráno při zatápění tmavší, pak světlejší; v noci ztlumit (materiál je bez osvětlení)
	var dark := 0.0
	if hour >= 5.0 and hour < 9.0:
		dark = 1.0 - clampf((hour - 5.0) / 4.0, 0.0, 1.0)
	var grey := lerpf(0.72, 0.34, dark) * lerpf(0.22, 1.0, clock.daylight())
	var alpha := (0.22 + 0.33 * strength) * (1.0 - 0.35 * clampf(w.rain, 0.0, 1.0))
	m.color = Color(grey, grey, grey * 1.03, alpha)
	m.scale_min = 0.9 + 0.6 * strength
	m.scale_max = 1.6 + 1.2 * strength + (0.8 if inversion else 0.0)
	# množství: rate ≈ amount / life
	var amount := int(clampf(round((3.0 + 10.0 * strength) * life / 3.0), 4.0, 48.0))
	if node.amount != amount:
		node.amount = amount
	node.lifetime = life
	node.emitting = true
	# viditelnost boxu podle dosahu kouře
	var reach := 6.0 + wv.length() * life * 0.5
	node.visibility_aabb = AABB(Vector3(-reach, -2.0, -reach), Vector3(reach * 2.0, 16.0, reach * 2.0))


func _make_slot() -> Dictionary:
	_ensure_shared()
	var node := GPUParticles3D.new()
	node.name = "Kour%d" % _slots.size()
	node.amount = 12
	node.lifetime = SmokeRules["life"]
	node.emitting = false
	node.visible = false
	node.local_coords = false
	node.explosiveness = 0.0
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_aabb = AABB(Vector3(-15, -2, -15), Vector3(30, 16, 30))
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.18
	m.color_ramp = _ramp
	m.scale_curve = _scale_curve()
	node.process_material = m
	node.draw_pass_1 = _mesh
	add_child(node)
	var s := {"node": node, "mat": m, "key": Vector3(INF, INF, INF), "keep": false}
	_slots.append(s)
	return s


func _scale_curve() -> CurveTexture:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.35))
	c.add_point(Vector2(1.0, 1.0))
	var ct := CurveTexture.new()
	ct.curve = c
	return ct


func _ensure_shared() -> void:
	if _mesh != null:
		return
	# sytost v čase života: rychlý nástup, pomalé vytrácení (násobí se s barvou emitoru)
	var gr := Gradient.new()
	gr.offsets = PackedFloat32Array([0.0, 0.12, 0.7, 1.0])
	gr.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.0)])
	_ramp = GradientTexture1D.new()
	_ramp.gradient = gr
	# měkká textura kouře: radiální přechod (bez externích souborů)
	var rg := Gradient.new()
	rg.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	rg.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
	var rt := GradientTexture2D.new()
	rt.gradient = rg
	rt.fill = GradientTexture2D.FILL_RADIAL
	rt.fill_from = Vector2(0.5, 0.5)
	rt.fill_to = Vector2(0.5, 0.0)
	rt.width = 64
	rt.height = 64
	_smoke_mat = StandardMaterial3D.new()
	_smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_smoke_mat.vertex_color_use_as_albedo = true
	_smoke_mat.albedo_texture = rt
	_smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_smoke_mat.billboard_keep_scale = true
	_smoke_mat.disable_receive_shadows = true
	_mesh = QuadMesh.new()
	_mesh.size = Vector2(1.0, 1.0)
	_mesh.material = _smoke_mat
