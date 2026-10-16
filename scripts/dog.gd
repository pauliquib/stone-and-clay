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
static var SLEEP_STEP := 0.5

## M8.D2b: chování psa – dřív čísla v kódu, laditelné v menu F3 (Člověk / Pes). Sdílené všemi psy (`static var`).
static var DEEP_K := 1.7               # × simulační bublina – za ní hluboký spánek
static var PHYSICS_RANGE := 160.0      # m – dál od hráče kinematika bez kolizí
static var NOTICE_R := 16.0            # m – všimne si hráče a běží za ním
static var BARK_S := 1.5               # s štěkání
static var WAIT_MIN := 1.0             # s – postání při toulání
static var WAIT_MAX := 5.0
static var ROAM_MIN := 2.0             # m od domu – toulání
static var ROAM_MAX := 12.0
static var ARRIVE_R := 0.8             # m – dosažení cíle toulání
static var WANDER_SPEED := 1.8         # m/s – toulání
static var LOSE_R := 45.0              # m – hráč dál = vzdá to a jde domů
static var HOME_MAX := 250.0           # m od domu – dál za hráčem nepoběží
static var FOLLOW_GAP := 2.4           # m – drží se tak daleko od hráče
static var FOLLOW_STOP := 2.0          # m – vzdálenost, od které se počítá rychlost dohánění
static var FOLLOW_K := 2.2             # m/s rychlosti na metr odstupu
static var FOLLOW_MIN := 1.5           # m/s
static var FOLLOW_MAX := 8.5           # m/s – nejrychlejší běh
static var HOME_ARRIVE := 2.0          # m – doma
static var REFOLLOW_R := 10.0          # m – cestou domů se znovu přidá k hráči blíž než tohle
static var REFOLLOW_HOME := 200.0      # m od domu – …jen do této vzdálenosti
static var HOME_SPEED := 5.0           # m/s – návrat domů
static var ACCEL := 18.0               # m/s² – rozběh a brzdění
static var JUMP_VY := 5.0              # m/s – přeskok nízké překážky
static var JUMP_MIN_V := 2.0           # m/s – skáče jen v běhu
static var GRAVITY := 20.0             # m/s²
static var TURN := 8.0                 # /s – natáčení do směru běhu
static var FACE_TURN := 4.0            # /s – otočení k hráči ve stoje
static var STRIDE_K := 3.2             # rad/m – fáze kroku (kadence nohou)
static var GALLOP_V := 4.5             # m/s – od této rychlosti cval


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
	var to_p: Vector3 = world.player_world_pos(player) - global_position if player else Vector3(INF, 0, 0)
	var dist := to_p.length()
	# pásma okolo hráče: <160 m plná fyzika, 160 m…1.7×simr kinematika (viditelný, bez kolizí),
	# >1.7×simr hluboký spánek: schovaný vizuál, chůze jen kinematicky ~2 Hz
	var simr: float = world.sim_radius if world != null else 320.0
	if dist > simr * DEEP_K:
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
			if dist < NOTICE_R and not in_car:
				_state = "follow"
				_bark = BARK_S
			elif _wait > 0.0:
				_wait -= delta
			else:
				var d := _target - global_position
				d.y = 0
				if d.length() < ARRIVE_R:
					_wait = rng.randf_range(WAIT_MIN, WAIT_MAX)
					var a := rng.randf() * TAU
					_target = home + Vector3(cos(a), 0, sin(a)) * rng.randf_range(ROAM_MIN, ROAM_MAX)
				else:
					desired = d.normalized() * WANDER_SPEED
		"follow":
			if dist > LOSE_R or global_position.distance_to(home) > HOME_MAX or in_car:
				_state = "home"
			elif dist > FOLLOW_GAP:
				var sp := clampf((dist - FOLLOW_STOP) * FOLLOW_K, FOLLOW_MIN, FOLLOW_MAX)
				desired = Vector3(to_p.x, 0, to_p.z).normalized() * sp
		"home":
			var d := home - global_position
			d.y = 0
			if d.length() < HOME_ARRIVE:
				_state = "wander"
			elif dist < REFOLLOW_R and global_position.distance_to(home) < REFOLLOW_HOME and not in_car:
				_state = "follow"
			else:
				desired = d.normalized() * HOME_SPEED

	if dist > PHYSICS_RANGE:
		global_position += desired * delta
		global_position.y = terrain.height_at(global_position.x, global_position.z)
		velocity = desired
	else:
		velocity.x = move_toward(velocity.x, desired.x, ACCEL * delta)
		velocity.z = move_toward(velocity.z, desired.z, ACCEL * delta)
		if is_on_floor():
			velocity.y = -0.5
			# přeskočí nízkou překážku
			if desired.length() > JUMP_MIN_V and is_on_wall():
				velocity.y = JUMP_VY
		else:
			velocity.y -= GRAVITY * delta
		move_and_slide()
		if global_position.y < terrain.height_at(global_position.x, global_position.z) - 3.0:
			global_position.y = terrain.height_at(global_position.x, global_position.z) + 0.5

	var hs := Vector3(velocity.x, 0, velocity.z).length()
	if hs > 0.3:
		_yaw = lerp_angle(_yaw, atan2(velocity.x, velocity.z), 1.0 - exp(-TURN * delta))
	elif _state == "follow":
		_yaw = lerp_angle(_yaw, atan2(to_p.x, to_p.z), 1.0 - exp(-FACE_TURN * delta))
	_body.rotation.y = _yaw
	_phase += delta * (hs * STRIDE_K + 0.001)
	var amp := clampf(hs / 3.0, 0.0, 1.0) * 0.8
	for i in _legs.size():
		var off := 0.0 if i in [0, 3] else PI
		if hs > GALLOP_V:
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
