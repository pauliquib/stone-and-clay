## Statická postava (hostinský, prodavačka, štamgast, starosta, policista…): stojí / sedí,
## otáčí se k nejbližšímu hráči, když je blízko, umí něco říct (bublina nad hlavou).
## `persona` (povaha, povolání) a `role` (keeper / deda / regular / cop) řídí odpovědi v rozhovoru (Dialog).
class_name Npc
extends StaticBody3D

var display_name := ""
var visual: Humanoid
var sitting := false
var face_player := true
var base_yaw := 0.0
var world: Node                  # World – odkud se berou hráči
var persona: Persona             # povaha a paměť (nastaví místo / svět; výchozí: přátelská)
var role := "npc"                # keeper (obsluha místa), deda, regular (štamgast), cop
var place := ""                  # klíč místa, kde obsluhuje
var _label: Label3D
var _name_label: Label3D
var _say_t := 0.0
var _yaw := 0.0
var _far := false                 # za simulační bublinou – vizuál schovaný (NPC „jen u hráče“)


static func make(name_: String, outfit: String, shirt: Color, seed_: int, pos: Vector3, yaw: float,
		w: Node, sit := false) -> Npc:
	var n := Npc.new()
	n.display_name = name_
	n.position = pos
	n.base_yaw = yaw
	n.world = w
	n.sitting = sit
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var h := Humanoid.new()
	h.outfit = outfit
	h.shirt = shirt
	h.pants = Color(0.2, 0.2, 0.25).lerp(Color(0.3, 0.25, 0.18), rng.randf())
	h.hair = [Color(0.25, 0.16, 0.08), Color(0.08, 0.06, 0.05), Color(0.75, 0.75, 0.72),
		Color(0.55, 0.4, 0.2)][rng.randi() % 4]
	h.hair_style = rng.randi() % 4
	h.moustache = rng.randf() < 0.4
	h.beard = rng.randf() < 0.15
	h.skin = Color(0.96, 0.7, 0.55).darkened(rng.randf() * 0.12)
	h.fat = rng.randf() * 0.6 if outfit != "police" else 0.0
	h.vis_end = 160.0
	n.visual = h
	return n


func _ready() -> void:
	if persona == null:
		persona = Persona.make({"name": display_name, "trait": "prisny" if visual.outfit == "police" else "pratelsky",
			"job": "policista" if visual.outfit == "police" else "", "age": 45, "topics": []})
		if visual.outfit == "police":
			role = "cop"
	collision_layer = 4
	collision_mask = 0
	var sh := CapsuleShape3D.new()
	sh.radius = 0.3
	sh.height = 1.7 if not sitting else 1.2
	var cs := CollisionShape3D.new()
	cs.shape = sh
	cs.position.y = sh.height * 0.5
	add_child(cs)
	add_child(visual)
	if sitting:
		visual.pose = "sit"
	_yaw = base_yaw
	visual.rotation.y = _yaw
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0, 2.3 if not sitting else 1.8, 0)
	_label.font_size = 40
	_label.outline_size = 10
	_label.modulate = Color(1, 1, 0.9)
	_label.width = 700.0
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM   # delší text roste nahoru
	_label.visible = false
	add_child(_label)
	_name_label = Label3D.new()
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.position = Vector3(0, 2.02 if not sitting else 1.55, 0)
	_name_label.font_size = 28
	_name_label.outline_size = 8
	_name_label.modulate = Color(0.75, 0.9, 1.0)
	_name_label.text = display_name
	_name_label.visibility_range_end = 18.0
	add_child(_name_label)


func say(text: String, dur := 4.0) -> void:
	_label.text = text
	_label.visible = true
	_say_t = dur


func _process(delta: float) -> void:
	var __t0 := Tests.prof_t0()
	_process_impl(delta)
	Tests.prof_add("npc", __t0)


func _process_impl(delta: float) -> void:
	if _say_t > 0.0:
		_say_t -= delta
		if _say_t <= 0.0:
			_label.visible = false
	var player: Node3D = world.nearest_player(global_position) if world else null
	if player == null:
		return
	var to := player.global_position - global_position
	# za simulační bublinou se NPC schová (jen u hráče) – otáčení za ním nemá smysl počítat
	var simr: float = world.sim_radius if world != null else 320.0
	var d := to.length()
	if d > simr:
		if not _far:
			_far = true
			visual.visible = false
		return
	elif _far:
		_far = false
		visual.visible = true
	var want := base_yaw
	if face_player and d < 7.0 and not sitting:
		want = atan2(to.x, to.z)
	_yaw = lerp_angle(_yaw, want, 1.0 - exp(-4.0 * delta))
	visual.rotation.y = _yaw
	visual.waving = _say_t > 0.0 and _say_t < 1.2 and not sitting
