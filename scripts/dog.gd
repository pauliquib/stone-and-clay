## Bot – pes. Pobíhá kolem svého domu; když se nejbližší hráč přiblíží, zaštěká a běží za ním,
## drží se kousek od něj. Když hráč uteče daleko, vrátí se domů.
class_name Dog
extends CharacterBody3D

var terrain: Terrain
var world: Node
var home := Vector3.ZERO
var rng := RandomNumberGenerator.new()

var _state := "wander"
var _target := Vector3.ZERO
var _wait := 0.0
var _phase := 0.0
var _yaw := 0.0
var _bark := 0.0
var _body: Node3D
var _legs: Array[Node3D] = []
var _tail: Node3D
var _head: Node3D
var _label: Label3D
var _deep := false                # hluboký spánek za simulační bublinou (schovaný, ~2 Hz pohyb)
var _deep_dt := 0.0

## Krok kinematického pohybu hluboce uspaného psa (za simulační bublinou World.sim_radius).
const SLEEP_STEP := 0.5


func setup(t: Terrain, w: Node, pos: Vector3, seed_: int) -> void:
	terrain = t
	world = w
	rng.seed = seed_
	home = pos
	position = pos + Vector3(0, 0.3, 0)
	_target = pos


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 2 | 4 | 8 | 16
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(55)
	var sh := CapsuleShape3D.new()
	sh.radius = 0.22
	sh.height = 0.8
	var cs := CollisionShape3D.new()
	cs.shape = sh
	cs.rotation.x = PI / 2
	cs.position.y = 0.35
	add_child(cs)
	var fur: Color = [Color(0.45, 0.3, 0.15), Color(0.12, 0.1, 0.08), Color(0.85, 0.75, 0.55),
		Color(0.6, 0.6, 0.58)][rng.randi() % 4]
	_body = Node3D.new()
	add_child(_body)
	_mesh(_body, _capsule(0.17, 0.75), Vector3(0, 0.45, 0), fur, Vector3(PI / 2, 0, 0))
	_head = Node3D.new()
	_head.position = Vector3(0, 0.62, 0.36)
	_body.add_child(_head)
	_mesh(_head, _sphere(0.14), Vector3.ZERO, fur)
	_mesh(_head, _box(Vector3(0.12, 0.1, 0.18)), Vector3(0, -0.03, 0.14), fur.lightened(0.1))
	_mesh(_head, _sphere(0.035), Vector3(0, 0.0, 0.24), Color(0.05, 0.05, 0.05))
	for s in [-1.0, 1.0]:
		_mesh(_head, _box(Vector3(0.06, 0.12, 0.05)), Vector3(0.09 * s, 0.13, -0.02), fur.darkened(0.3))
	for p in [Vector3(-0.1, 0.33, 0.24), Vector3(0.1, 0.33, 0.24), Vector3(-0.1, 0.33, -0.24), Vector3(0.1, 0.33, -0.24)]:
		var leg := Node3D.new()
		leg.position = p
		_body.add_child(leg)
		_mesh(leg, _capsule(0.045, 0.34), Vector3(0, -0.15, 0), fur)
		_legs.append(leg)
	_tail = Node3D.new()
	_tail.position = Vector3(0, 0.55, -0.38)
	_body.add_child(_tail)
	_mesh(_tail, _capsule(0.03, 0.3), Vector3(0, 0.1, -0.06), fur, Vector3(-0.6, 0, 0))
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0, 1.2, 0)
	_label.font_size = 40
	_label.outline_size = 10
	_label.text = "Haf! Haf!"
	_label.visible = false
	add_child(_label)


func _physics_process(delta: float) -> void:
	var __t0 := Tests.prof_t0()
	_physics_impl(delta)
	Tests.prof_add("dog", __t0)


func _physics_impl(delta) -> void:
	var player: Player = world.nearest_player(global_position)
	var to_p := world.player_world_pos(player) - global_position if player else Vector3(INF, 0, 0)
	var dist := to_p.length()
	# pásma okolo hráče: <160 m plná fyzika, 160 m…1.7×simr kinematika (viditelný, bez kolizí),
	# >1.7×simr hluboký spánek: schovaný vizuál, chůze jen kinematicky ~2 Hz
	var simr: float = world.sim_radius if world != null else 320.0
	if dist > simr * 1.7:
		if not _deep:
			_deep = true
			_body.visible = false
			_label.visible = false
		_deep_dt += delta
		if _deep_dt < SLEEP_STEP:
			return
		delta = _deep_dt
		_deep_dt = 0.0
	elif _deep:
		_deep = false
		_deep_dt = 0.0
		_body.visible = true
	var desired := Vector3.ZERO
	# za autem neběhá (vběhl by pod kola / tlačil by se před autem)
	var in_car: bool = player != null and player.get("car") != null
	match _state:
		"wander":
			if dist < 16.0 and not in_car:
				_state = "follow"
				_bark = 1.5
			elif _wait > 0.0:
				_wait -= delta
			else:
				var d := _target - global_position
				d.y = 0
				if d.length() < 0.8:
					_wait = rng.randf_range(1.0, 5.0)
					var a := rng.randf() * TAU
					_target = home + Vector3(cos(a), 0, sin(a)) * rng.randf_range(2.0, 12.0)
				else:
					desired = d.normalized() * 1.8
		"follow":
			if dist > 45.0 or global_position.distance_to(home) > 250.0 or in_car:
				_state = "home"
			elif dist > 2.4:
				var sp := clampf((dist - 2.0) * 2.2, 1.5, 8.5)
				desired = Vector3(to_p.x, 0, to_p.z).normalized() * sp
		"home":
			var d := home - global_position
			d.y = 0
			if d.length() < 2.0:
				_state = "wander"
			elif dist < 10.0 and global_position.distance_to(home) < 200.0 and not in_car:
				_state = "follow"
			else:
				desired = d.normalized() * 5.0

	if dist > 160.0:
		global_position += desired * delta
		global_position.y = terrain.height_at(global_position.x, global_position.z)
		velocity = desired
	else:
		velocity.x = move_toward(velocity.x, desired.x, 18.0 * delta)
		velocity.z = move_toward(velocity.z, desired.z, 18.0 * delta)
		if is_on_floor():
			velocity.y = -0.5
			# přeskočí nízkou překážku
			if desired.length() > 2.0 and is_on_wall():
				velocity.y = 5.0
		else:
			velocity.y -= 20.0 * delta
		move_and_slide()
		if global_position.y < terrain.height_at(global_position.x, global_position.z) - 3.0:
			global_position.y = terrain.height_at(global_position.x, global_position.z) + 0.5

	var hs := Vector3(velocity.x, 0, velocity.z).length()
	if hs > 0.3:
		_yaw = lerp_angle(_yaw, atan2(velocity.x, velocity.z), 1.0 - exp(-8.0 * delta))
	elif _state == "follow":
		_yaw = lerp_angle(_yaw, atan2(to_p.x, to_p.z), 1.0 - exp(-4.0 * delta))
	_body.rotation.y = _yaw
	_phase += delta * (hs * 3.2 + 0.001)
	var amp := clampf(hs / 3.0, 0.0, 1.0) * 0.8
	for i in _legs.size():
		var off := 0.0 if i in [0, 3] else PI
		if hs > 4.5:
			off = 0.0 if i < 2 else PI * 0.8   # cval
		_legs[i].rotation.x = sin(_phase + off) * amp
	_body.position.y = absf(sin(_phase)) * 0.04 * amp
	_tail.rotation.z = sin(Time.get_ticks_msec() * (0.025 if _state == "follow" else 0.008)) * 0.6
	_head.rotation.x = -0.25 if _state == "follow" and dist < 4.0 else 0.0
	if _bark > 0.0:
		_bark -= delta
		_label.visible = true
		if _bark <= 0.0:
			_label.visible = false


func _mesh(parent: Node3D, m: Mesh, pos: Vector3, c: Color, rot := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = pos
	mi.rotation = rot
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.roughness = 0.9
	mi.material_override = mat
	parent.add_child(mi)


func _capsule(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 10
	m.rings = 3
	return m


func _sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2
	m.radial_segments = 12
	m.rings = 6
	return m


func _box(s: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = s
	return m
