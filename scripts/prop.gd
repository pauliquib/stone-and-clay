## Fyzikální předmět u silnice (popelnice, poštovní schránka, lavička): dá se shodit / odhodit autem.
## Při prvním převržení nebo prudkém nárazu ohlásí poškození (pro podmínku úkolů "nic nepoškodit").
class_name Prop
extends RigidBody3D

signal damaged(prop: Prop, what: String)

var kind := "popelnice"
var what := "popelnici"
var _done := false
var _up0 := Vector3.UP


static func make(k: String, pos: Vector3, yaw: float) -> Prop:
	var p := Prop.new()
	p.kind = k
	p.position = pos
	p.rotation.y = yaw
	return p


func _ready() -> void:
	collision_layer = 8
	collision_mask = 1 | 2 | 4 | 8 | 16
	set_meta("kind", {"popelnice": "popelnice", "schranka": "poštovní schránka", "lavicka": "lavička"}[kind])
	var mi := MeshInstance3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	match kind:
		"popelnice":
			what = "popelnici"
			mi.mesh = PropModels.trash_bin([Color(0.15, 0.35, 0.15), Color(0.2, 0.2, 0.22), Color(0.6, 0.55, 0.1),
				Color(0.15, 0.3, 0.6)][randi() % 4])
			bs.size = Vector3(0.6, 1.05, 0.75)
			cs.position.y = 0.52
			mass = 18.0
		"schranka":
			what = "poštovní schránku"
			mi.mesh = PropModels.mailbox()
			bs.size = Vector3(0.36, 1.38, 0.2)
			cs.position.y = 0.69
			mass = 12.0
		"lavicka":
			what = "lavičku"
			mi.mesh = PropModels.bench()
			bs.size = Vector3(1.6, 0.8, 0.5)
			cs.position.y = 0.4
			mass = 35.0
	cs.shape = bs
	add_child(cs)
	add_child(mi)
	mi.visibility_range_end = 250.0
	var pm := PhysicsMaterial.new()
	pm.friction = 0.8
	physics_material_override = pm
	can_sleep = true
	sleeping = true
	_up0 = global_transform.basis.y


func on_hit(impact: float) -> void:
	if impact > 3.0:
		_report()


func _physics_process(_delta: float) -> void:
	var __t0 := Tests.prof_t0()
	_physics_process_impl(_delta)
	Tests.prof_add("prop", __t0)


func _physics_process_impl(_delta: float) -> void:
	if _done or sleeping:
		return
	if global_transform.basis.y.dot(_up0) < 0.55 or linear_velocity.length() > 4.0:
		_report()


func _report() -> void:
	if _done:
		return
	_done = true
	damaged.emit(self, what)
