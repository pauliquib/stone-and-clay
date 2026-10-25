## Fyzikální předmět u silnice (popelnice, poštovní schránka, lavička): dá se shodit / odhodit autem.
## Při prvním převržení nebo prudkém nárazu ohlásí poškození (pro podmínku úkolů "nic nepoškodit").
class_name Prop
extends RigidBody3D

signal damaged(prop: Prop, what: String)

var kind := "popelnice"
var what := "popelnici"
var _done := false
var _up0 := Vector3.UP
var _settle := 0                 # zbývající pokusy usadit předmět na povrch (první fyzikální kroky, zmrazený)
var _com_y := 0.23               # výška těžiště nad podstavou (m) – nízko, ať se na svahu sám nepřevrátí
var _foot := Vector2(0.3, 0.37)  # poloviční rozměry podstavy (x, z) – rohy pro usazení na nerovný terén
var _guard: Area3D               # hlídač okolí zmrazeného předmětu: vozidlo / jiný předmět blízko → uvolnit fyziku

const SLOPE_R := 0.9             # poloměr (m), ze kterého se bere sklon pro náklon (ne lokální hrbol pod rohem)
const GUARD_M := 0.7             # o kolik je hlídač větší než předmět (m) – auto ~0,5 m za fyzikální krok


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
			_com_y = 0.06                 # sloupek s betonovou patkou – úzká podstava (20 cm), těžiště u země
		"lavicka":
			what = "lavičku"
			mi.mesh = PropModels.bench()
			bs.size = Vector3(1.6, 0.8, 0.5)
			cs.position.y = 0.4
			mass = 35.0
			_com_y = 0.2
	cs.shape = bs
	_foot = Vector2(bs.size.x, bs.size.z) * 0.5
	add_child(cs)
	add_child(mi)
	mi.visibility_range_end = 250.0
	var pm := PhysicsMaterial.new()
	pm.friction = 0.8
	physics_material_override = pm
	can_sleep = true
	# těžiště nízko (zátěž ve dně / patka sloupku) – na svahu se samo nepřevrátí, autem shodit jde dál
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, _com_y, 0.0)
	_up0 = global_transform.basis.y
	# Validátor: čtvrtina popelnic a schránek na svazích ležela převrácená – spawn ve výšce terénu ve středu podstavy
	# zabořil horní hranu do svahu a vytlačení předmět převrhlo; dynamický předmět na prudkém svahu (náspy u silnic)
	# se navíc časem svezl. Proto stojí zmrazený (statický): usadí se na povrch (_settle_on_ground) a fyziku dostane až
	# při prvním dotyku – hráč (on_hit), vozidlo nebo jiný předmět v dosahu hlídače (_guard, uvolní před nárazem).
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true
	_settle = 4
	set_physics_process(true)
	sleeping_state_changed.connect(_on_sleeping_changed)
	_guard = Area3D.new()
	_guard.collision_layer = 0
	_guard.collision_mask = 8 | 16           # předměty, dron, vozíky (8) a vozidla (16); postavy řeší on_hit
	_guard.monitorable = false
	var gs := CollisionShape3D.new()
	var gb := BoxShape3D.new()
	gb.size = bs.size + Vector3(GUARD_M * 2.0, 0.4, GUARD_M * 2.0)
	gs.shape = gb
	gs.position = cs.position
	_guard.add_child(gs)
	add_child(_guard)
	_guard.body_entered.connect(_on_guard)


## Usadí předmět na povrch pod sebou: náklon podle roviny ze zásahů v okruhu SLOPE_R (svah, ne hrbol pod rohem –
## validátor toleruje sklon + 12°), výška tak, aby žádný roh podstavy nebyl pod povrchem.
## Bez zásahu (kolize ještě není) zkusí znovu v dalším kroku.
func _settle_on_ground() -> void:
	_settle -= 1
	var xf := global_transform.orthonormalized()
	var wide := _corner_hits(xf, Vector2(maxf(_foot.x, SLOPE_R), maxf(_foot.y, SLOPE_R)))
	var foot := _corner_hits(xf, _foot)
	if (wide.size() < 4 or foot.size() < 4) and _settle > 0:
		return
	_settle = 0
	set_physics_process(false)
	if wide.size() < 4 or foot.size() < 4:
		return
	var n := (wide[0] - wide[2]).cross(wide[1] - wide[3]).normalized()
	if n.y < 0.0:
		n = -n
	if n.y < 0.75:
		n = Vector3.UP                         # sráz / zeď v okolí – stát svisle
	var b := Basis(Quaternion(xf.basis.y.normalized(), n)) * xf.basis
	var ctr := (foot[0] + foot[1] + foot[2] + foot[3]) * 0.25
	var lift := 0.0
	for pt in foot:
		lift = maxf(lift, (pt - ctr).dot(n))
	global_transform = Transform3D(b, ctr + n * (lift + 0.01))
	_up0 = b.y


## Zásahy povrchu pod čtyřmi rohy obdélníku (poloviny `half`) kolem polohy – pořadí po obvodu.
func _corner_hits(xf: Transform3D, half: Vector2) -> Array[Vector3]:
	var space := get_world_3d().direct_space_state
	var pts: Array[Vector3] = []
	for c: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]:
		var o := xf.origin + xf.basis.x * (c.x * half.x) + xf.basis.z * (c.y * half.y)
		var q := PhysicsRayQueryParameters3D.create(o + Vector3.UP * 1.5, o + Vector3.DOWN * 3.0, 1)
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			pts.append(hit["position"])
	return pts


func _on_guard(b: Node3D) -> void:
	if b != self:
		_release()


## Zmrazený předmět dostane fyziku (dotyk hráče, vozidlo v dosahu hlídače). Hlídač pak už není potřeba.
func _release() -> void:
	if _settle > 0:
		_settle_on_ground()
	if not freeze:
		return
	freeze = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	set_physics_process(true)
	if _guard:
		_guard.set_deferred("monitoring", false)


func _on_sleeping_changed() -> void:
	set_physics_process(_settle > 0 or (not sleeping and not _done and not freeze))


func on_hit(impact: float) -> void:
	_release()                  # zmrazený (statický) předmět by byl pro hráče zeď
	if impact > 3.0:
		_report()


func _physics_process(_delta: float) -> void:
	var __t0 := Tests.prof_t0()
	_physics_process_impl(_delta)
	Tests.prof_add("prop", __t0)


func _physics_process_impl(_delta: float) -> void:
	if _settle > 0:
		_settle_on_ground()
		return
	if _done or sleeping or freeze:
		return
	if global_transform.basis.y.dot(_up0) < 0.55 or linear_velocity.length() > 4.0:
		_report()


func _report() -> void:
	if _done:
		return
	_done = true
	damaged.emit(self, what)
