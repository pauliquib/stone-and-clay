## Sdílený vzhled ohně (M2.2): částice plamenů / jisker / kouře a mihotavé světlo.
## Vytaženo z `VillageEvents` (hranice čarodějnic) – používá ho i táborák `Fire` a požár trávy `GrassFire`.
## Jen statické funkce, žádný stav (kromě sdílených materiálů).
class_name FireFx
extends RefCounted

const FLAME_RAMP := [Color(1.0, 0.95, 0.6, 0.9), Color(1.0, 0.5, 0.1, 0.7), Color(0.5, 0.1, 0.05, 0.0)]
const SPARK_RAMP := [Color(1.0, 0.9, 0.4, 1.0), Color(1.0, 0.5, 0.1, 0.8), Color(1.0, 0.3, 0.05, 0.0)]
const SMOKE_RAMP := [Color(0.5, 0.5, 0.5, 0.0), Color(0.45, 0.45, 0.45, 0.4), Color(0.3, 0.3, 0.3, 0.0)]

static var _dot_mat: StandardMaterial3D
static var _smoke_mat: StandardMaterial3D


## Částice ohně: koule emisí, vzlínají vzhůru, barva podle životnosti (color_ramp), aditivní měkké kolečko.
## `y` = výška emitoru nad počátkem `parent`, `smoke` = běžný (ne aditivní) materiál pro kouř.
static func particles(parent: Node3D, radius: float, amount: int, quad: Vector2, life: float, v_min: float, v_max: float,
		ramp: Array, y := 0.6, smoke := false) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.emitting = false
	p.position = Vector3(0, y, 0)
	p.visibility_aabb = AABB(Vector3(-5, -1, -5), Vector3(10, 10, 10))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = radius
	m.direction = Vector3.UP
	m.spread = 14.0
	m.initial_velocity_min = v_min * 0.5
	m.initial_velocity_max = v_max * 0.5
	m.gravity = Vector3(0, 1.2, 0)
	m.scale_min = 0.6
	m.scale_max = 1.3
	var gr := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in ramp.size():
		offs.append(float(i) / (ramp.size() - 1))
		cols.append(ramp[i])
	gr.offsets = offs
	gr.colors = cols
	var gt := GradientTexture1D.new()
	gt.gradient = gr
	m.color_ramp = gt
	p.process_material = m
	var qm := QuadMesh.new()
	qm.size = quad
	qm.material = smoke_material() if smoke else soft_dot_material()
	p.draw_pass_1 = qm
	parent.add_child(p)
	return p


## Sdílený materiál měkkého svítícího kolečka (aditivní, billboard, barva z částic).
static func soft_dot_material() -> StandardMaterial3D:
	if _dot_mat:
		return _dot_mat
	var m := _dot_material(true)
	_dot_mat = m
	return m


## Sdílený materiál kouře (průhledný, ne aditivní).
static func smoke_material() -> StandardMaterial3D:
	if _smoke_mat:
		return _smoke_mat
	var m := _dot_material(false)
	_smoke_mat = m
	return m


static func _dot_material(additive: bool) -> StandardMaterial3D:
	var gt := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	gr.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0)])
	gt.gradient = gr
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	gt.width = 64
	gt.height = 64
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = gt
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.no_depth_test = false
	return m


## Sestaví plameny (2 emitory), volitelně kouř a světlo (`light_range` > 0). `k` = měřítko (1 = táborák).
## Vrací {"flame", "sparks", "smoke", "light"} (uzly už jsou přidané do `parent`; nic nehoří, dokud se `emitting` nezapne).
static func make(parent: Node3D, k := 1.0, with_smoke := true, light_range := 9.0) -> Dictionary:
	var out := {}
	out["flame"] = particles(parent, 0.22 * k, int(44.0 * k) + 8, Vector2(0.34, 0.34) * k, 0.9, 1.0, 2.0, FLAME_RAMP, 0.25 * k + 0.1)
	out["sparks"] = particles(parent, 0.18 * k, int(10.0 * k) + 3, Vector2(0.04, 0.04) * k, 1.4, 1.5, 3.4, SPARK_RAMP, 0.4 * k + 0.1)
	if with_smoke:
		var sm := particles(parent, 0.2 * k, int(14.0 * k) + 4, Vector2(0.9, 0.9) * k, 4.0, 0.8, 1.6, SMOKE_RAMP, 0.9 * k + 0.2, true)
		(sm.process_material as ParticleProcessMaterial).spread = 25.0
		(sm.process_material as ParticleProcessMaterial).scale_max = 2.2
		sm.visibility_aabb = AABB(Vector3(-8, -1, -8), Vector3(16, 14, 16))
		out["smoke"] = sm
	if light_range <= 0.0:
		return out
	var l := OmniLight3D.new()
	l.position = Vector3(0, 0.7 * k + 0.2, 0)
	l.light_color = Color(1.0, 0.55, 0.22)
	l.omni_range = light_range
	l.light_energy = 0.0
	l.shadow_enabled = false
	l.distance_fade_enabled = true
	l.distance_fade_begin = 90.0
	parent.add_child(l)
	out["light"] = l
	return out


## Mihotání světla: `t` = čas (s), `base` = základní energie.
static func flicker(t: float, base: float) -> float:
	var fl := 0.8 + 0.25 * sin(t * 13.0) + 0.15 * sin(t * 31.0 + 1.7) + 0.1 * sin(t * 7.3)
	return base * fl
