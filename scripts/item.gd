## Sběratelský předmět: hřib (les, léto–podzim), jablko (zahrady, srpen–říjen), šípek (listopad–únor), dukát (silnice v obci), zlatý žalud (vzdálené lesy).
class_name Item
extends Area3D

signal collected(item: Item, by: Player)   # kdo ho sebral

## Alias na jednotný katalog `ItemsDB.ITEMS` (M0.2); sběratelské předměty mají klíč `points`, název v `short`.
const INFO := ItemsDB.ITEMS

var kind := "dukat"
var _visual: Node3D
var _t := 0.0
var _base_y := 0.0
var _taken := false
var active := true          # sezónní předmět mimo sezónu: skrytý a nesbíratelný (World.refresh_season_items)


func setup(k: String, pos: Vector3) -> void:
	kind = k
	position = pos
	_base_y = pos.y


## Zapne / vypne předmět (mimo sezónu nebo bez vláhy je skrytý a nejde sebrat).
func set_active(a: bool) -> void:
	if a == active:
		return
	active = a
	visible = a
	if is_inside_tree():
		set_deferred("monitoring", a)


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitorable = false
	monitoring = active
	visible = active
	var s := SphereShape3D.new()
	s.radius = 1.0 if kind != "zalud" else 1.4
	var cs := CollisionShape3D.new()
	cs.shape = s
	cs.position.y = 0.5
	add_child(cs)
	_visual = Node3D.new()
	add_child(_visual)
	_t = randf() * 10.0
	match kind:
		"hrib":
			_add(_cyl(0.07, 0.09, 0.22), Vector3(0, 0.11, 0), Color(0.92, 0.88, 0.78))
			var cap := _add(_sphere(0.17), Vector3(0, 0.24, 0), Color(0.45, 0.24, 0.1))
			cap.scale = Vector3(1, 0.6, 1)
		"jablko":
			_add(_sphere(0.1), Vector3(0, 0.12, 0), Color(0.8, 0.1, 0.08), 0.35)
			_add(_cyl(0.01, 0.01, 0.06), Vector3(0, 0.24, 0), Color(0.3, 0.2, 0.1))
			var lf := _add(_box(Vector3(0.06, 0.005, 0.03)), Vector3(0.03, 0.24, 0), Color(0.2, 0.55, 0.15))
			lf.rotation.z = 0.4
		"sipek":
			# větvička s 6 červenými šípky
			var twig := _add(_cyl(0.008, 0.012, 0.32), Vector3(0, 0.15, 0), Color(0.3, 0.2, 0.12))
			twig.rotation.z = 0.35
			for k in 6:
				var a := float(k) / 6.0 * TAU
				var berry := _add(_sphere(0.035), Vector3(cos(a) * 0.06, 0.1 + 0.035 * k, sin(a) * 0.06), Color(0.85, 0.1, 0.08), 0.3)
				berry.scale = Vector3(0.8, 1.15, 0.8)
		"dukat":
			var coin := _add(_cyl(0.18, 0.18, 0.035), Vector3(0, 0.6, 0), Color(1.0, 0.78, 0.2), 0.25, 1.0, 0.25)
			coin.rotation.x = PI / 2
		"zalud":
			_add(_sphere(0.16), Vector3(0, 0.75, 0), Color(1.0, 0.8, 0.25), 0.2, 1.0, 1.2).scale = Vector3(1, 1.3, 1)
			var cup := _add(_sphere(0.17), Vector3(0, 0.9, 0), Color(0.75, 0.55, 0.15), 0.4, 1.0, 0.6)
			cup.scale = Vector3(1, 0.55, 1)
			# světelný sloup – vidět zdálky
			var beam := MeshInstance3D.new()
			beam.mesh = _cyl(1.2, 1.2, 80.0)
			beam.position.y = 40.0
			var bm := StandardMaterial3D.new()
			bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			bm.albedo_color = Color(1.0, 0.85, 0.3, 0.28)
			bm.cull_mode = BaseMaterial3D.CULL_DISABLED
			bm.disable_fog = true
			beam.material_override = bm
			beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(beam)
			var light := OmniLight3D.new()
			light.light_color = Color(1.0, 0.8, 0.35)
			light.omni_range = 6.0
			light.light_energy = 1.5
			light.position.y = 1.0
			light.distance_fade_enabled = true
			light.distance_fade_begin = 80.0
			add_child(light)
	body_entered.connect(_on_body)


func _process(delta: float) -> void:
	_t += delta
	match kind:
		"dukat", "zalud":
			_visual.rotation.y += delta * 2.2
			_visual.position.y = sin(_t * 2.0) * 0.08
		_:
			_visual.position.y = sin(_t * 1.5) * 0.02
	if _taken:
		_visual.scale = _visual.scale.lerp(Vector3.ZERO, 1.0 - exp(-10.0 * delta))
		_visual.position.y += delta * 3.0


func _on_body(b: Node) -> void:
	if _taken or not (b is Player):
		return
	_taken = true
	collected.emit(self, b)
	var tw := create_tween()
	tw.tween_interval(0.5)
	tw.tween_callback(queue_free)


func _add(m: Mesh, pos: Vector3, c: Color, rough := 0.7, metal := 0.0, emit := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.roughness = rough
	mat.metallic = metal
	if emit > 0.0:
		mat.emission_enabled = true
		mat.emission = c
		mat.emission_energy_multiplier = emit
	mi.material_override = mat
	_visual.add_child(mi)
	return mi


func _cyl(rt: float, rb: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = rt
	m.bottom_radius = rb
	m.height = h
	m.radial_segments = 20
	return m


func _sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2
	return m


func _box(s: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = s
	return m
