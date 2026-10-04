## Bot – vesničan. Každý je jiná smyšlená postava (Characters: jméno, povolání, povaha, vzhled, tempo chůze).
## Chodí po silnicích a cestách (graf z OSM), občas se zastaví; když k němu hráč přijde, otočí se, zamává
## a pozdraví podle své povahy, nálady a pověsti hráče (Dialog.greet). Odpovídá na to, co hráč řekne (T),
## a na E prozradí drb. Vždy řeší nejbližšího hráče.
## Daleko od všech hráčů se pohybuje bez fyziky (jen po terénu) – šetří výkon.
class_name Villager
extends CharacterBody3D

const PHYSICS_RANGE := 160.0

var graph: RoadGraph
var terrain: Terrain
var world: Node
var rng := RandomNumberGenerator.new()

var _cur := 0
var _prev := -1
var _next := 0
var _side := 1.2
var _speed := 1.4
var _pause := 0.0
var _talk := 0.0
var _talk_cool := 0.0
var _stuck := 0.0
var _visual: Humanoid
var _label: Label3D
var _yaw := 0.0
var _knocked := 0.0
var _flee_t := 0.0                 # do kdy (s) vesničan utíká před střelbou (M2.8, `Weapons`)
var _flee_from := Vector3.ZERO
var persona: Persona               # kdo to je (jméno, povaha…) a jak se na hráče dívá
var _name_label: Label3D
var _talk_len := 3.5              # jak dlouho aktuální replika trvá (mává jen na začátku)
var _wait := 0.0                  # hráč píše odpověď (T) – postůj a nikam neodcházej


func setup(g: RoadGraph, t: Terrain, w: Node, start_node: int, seed_: int, prof: Dictionary) -> void:
	graph = g
	terrain = t
	world = w
	rng.seed = seed_
	persona = Persona.make(prof)
	name = "Vesnican_" + String(prof["name"]).replace(" ", "_")
	_cur = start_node
	_next = graph.next_node(_cur, -1, rng)
	# chodí při krajnici (auta jezdí 1–1,6 m od osy silnice)
	_side = rng.randf_range(2.9, 3.6) * (1.0 if rng.randf() < 0.5 else -1.0)
	_speed = float(prof.get("speed", 1.3)) * rng.randf_range(0.93, 1.07)
	var n := graph.nodes[_cur]
	position = Vector3(n.x, terrain.height_at(n.x, n.y) + 0.1, n.y)


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 2 | 4 | 8 | 16
	floor_snap_length = 0.5
	floor_max_angle = deg_to_rad(50)
	var sh := CapsuleShape3D.new()
	sh.radius = 0.32
	sh.height = 1.75
	var cs := CollisionShape3D.new()
	cs.shape = sh
	cs.position.y = 0.875
	add_child(cs)
	_visual = Humanoid.new()
	Characters.apply_look(_visual, persona.profile)
	add_child(_visual)
	_name_label = Label3D.new()
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.position = Vector3(0, 2.0 * _visual.scale_factor, 0)
	_name_label.font_size = 26
	_name_label.outline_size = 8
	_name_label.modulate = Color(0.8, 0.92, 1.0)
	_name_label.text = persona.display_name()
	_name_label.visibility_range_end = 14.0
	add_child(_name_label)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0, 2.25, 0)
	_label.font_size = 42
	_label.outline_size = 10
	_label.modulate = Color(1, 1, 0.9)
	_label.no_depth_test = false
	_label.width = 700.0
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM   # delší text roste nahoru
	_label.visible = false
	add_child(_label)


func _physics_process(delta: float) -> void:
	var player: Node3D = world.nearest_player(global_position)
	var to_player := player.global_position - global_position if player else Vector3(INF, 0, 0)
	var dist := to_player.length()
	_talk_cool = maxf(_talk_cool - delta, 0.0)

	# --- sražený autem: leží, pak vstane
	if _knocked > 0.0:
		_knocked -= delta
		velocity.x = move_toward(velocity.x, 0.0, 6.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 6.0 * delta)
		velocity.y -= 20.0 * delta
		move_and_slide()
		if global_position.y < terrain.height_at(global_position.x, global_position.z) - 1.0:
			global_position.y = terrain.height_at(global_position.x, global_position.z) + 0.3
		if _knocked <= 0.0:
			_visual.pose = "stand"
			_label.visible = false
		return
	# --- útěk před střelbou (M2.8): pryč od zdroje, rychle, bez hovoru
	if _flee_t > 0.0:
		_flee_t -= delta
		var away := global_position - _flee_from
		away.y = 0.0
		away = away.normalized() if away.length() > 0.1 else Vector3.FORWARD
		var run := away * 4.6
		_yaw = lerp_angle(_yaw, atan2(run.x, run.z), 1.0 - exp(-8.0 * delta))
		velocity.x = move_toward(velocity.x, run.x, 12.0 * delta)
		velocity.z = move_toward(velocity.z, run.z, 12.0 * delta)
		velocity.y = -0.5 if is_on_floor() else velocity.y - 20.0 * delta
		move_and_slide()
		_visual.rotation.y = _yaw
		_visual.speed = Vector3(velocity.x, 0, velocity.z).length()
		_visual.on_floor = true
		_visual.waving = false
		if _flee_t <= 0.0:
			_label.visible = false
		return
	# --- pozdrav
	var in_car: bool = player != null and player.get("car") != null
	if dist < 3.2 and _talk_cool <= 0.0 and _talk <= 0.0 and not in_car:
		_talk = 3.5
		_talk_len = _talk
		_talk_cool = 14.0
		_label.text = Dialog.greet(world.dialog_context(int(player.get("id")), self))
		_label.visible = true
	var desired := Vector3.ZERO
	if _talk > 0.0:
		_talk -= delta
		_yaw = lerp_angle(_yaw, atan2(to_player.x, to_player.z), 1.0 - exp(-6.0 * delta))
		_visual.waving = _talk > _talk_len - 1.7
		if _talk <= 0.0:
			_label.visible = false
			_visual.waving = false
	elif _wait > 0.0:
		_wait -= delta
		if dist < 11.0:
			_yaw = lerp_angle(_yaw, atan2(to_player.x, to_player.z), 1.0 - exp(-4.0 * delta))
		else:
			_wait = 0.0     # hráč zatím odešel daleko, nečekej nadarmo
	elif _pause > 0.0:
		_pause -= delta
	else:
		var goal := _goal()
		var d := Vector2(goal.x - global_position.x, goal.y - global_position.z)
		if d.length() < 1.3:
			_advance()
		else:
			desired = Vector3(d.x, 0, d.y).normalized() * _speed
			# neprojít skrz hráče
			if dist < 1.6 and to_player.normalized().dot(desired.normalized()) > 0.5:
				desired = Vector3.ZERO
			_yaw = lerp_angle(_yaw, atan2(desired.x, desired.z), 1.0 - exp(-5.0 * delta)) \
				if desired.length() > 0.1 else _yaw

	if dist > PHYSICS_RANGE:
		# daleko: kinematicky po terénu
		global_position += desired * delta
		global_position.y = terrain.height_at(global_position.x, global_position.z)
		velocity = desired
	else:
		velocity.x = move_toward(velocity.x, desired.x, 8.0 * delta)
		velocity.z = move_toward(velocity.z, desired.z, 8.0 * delta)
		if is_on_floor():
			velocity.y = -0.5
		else:
			velocity.y -= 20.0 * delta
		move_and_slide()
		# zaseknutý (plot, strom, hráč) → otočit se
		if desired.length() > 0.1 and Vector3(velocity.x, 0, velocity.z).length() < 0.25:
			_stuck += delta
			if _stuck > 2.0:
				_stuck = 0.0
				var t := _next
				_next = _cur
				_cur = t
				_side = -_side
		else:
			_stuck = 0.0
		if global_position.y < terrain.height_at(global_position.x, global_position.z) - 3.0:
			global_position.y = terrain.height_at(global_position.x, global_position.z) + 0.5

	_visual.rotation.y = _yaw
	_visual.speed = Vector3(velocity.x, 0, velocity.z).length()
	_visual.on_floor = true


func _goal() -> Vector2:
	var a := graph.nodes[_cur]
	var b := graph.nodes[_next]
	var dir := (b - a).normalized()
	# na silnici při krajnici, na pěšině / polní cestě uprostřed
	var side := _side if graph.edge(_cur, _next) in RoadGraph.CAR_KINDS else signf(_side) * 0.6
	return b + Vector2(-dir.y, dir.x) * side


func _advance() -> void:
	var nxt := graph.next_node(_next, _cur, rng)
	_prev = _cur
	_cur = _next
	_next = nxt
	if rng.randf() < 0.06:
		_pause = rng.randf_range(2.0, 6.0)


## Rozhovor (E): drb z vesnice.
func talk() -> String:
	var p: Node3D = world.nearest_player(global_position)
	var t: String = Dialog.rumor(world.dialog_context(int(p.get("id")), self)) if p else "Dobrý den."
	say(t, 4.5)
	return t


## Řekne něco (bublina nad hlavou) – zastaví se a otočí k hráči. Délka podle délky textu.
func say(text: String, dur := -1.0) -> void:
	if _knocked > 0.0:
		return
	_talk = dur if dur > 0.0 else clampf(2.0 + text.length() / 14.0, 3.5, 9.0)
	_talk_len = _talk
	_talk_cool = maxf(_talk_cool, 10.0)
	_label.text = text
	_label.visible = true


## Hráč otevřel řádek na promluvu (T) – postůj poblíž, ať má čas dopsat a odeslat.
func wait_for_reply(dur := 20.0) -> void:
	if _knocked > 0.0 or _flee_t > 0.0:
		return
	_wait = maxf(_wait, dur)


func is_knocked() -> bool:
	return _knocked > 0.0


## Uteč pryč od `src` na `dur` s (vesničan se leknul střelby; M2.8).
func flee_from(src: Vector3, dur := 8.0) -> void:
	if _knocked > 0.0:
		return
	_flee_from = src
	_flee_t = dur
	_talk = 0.0
	_pause = 0.0


## Sražení autem.
func knock(vel: Vector3, spd: float) -> void:
	_knocked = 4.0 + spd * 0.2
	velocity = vel
	_visual.pose = "lie"
	_visual.waving = false
	_talk = 0.0
	_label.text = "Au!! Ty blázne!"
	_label.visible = true
