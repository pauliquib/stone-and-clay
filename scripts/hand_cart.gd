## Ruční vozík (M2.10): dvoukolák s korbou a ojí. Fyzikální tělo (`RigidBody3D`, ~25 kg + náklad) s kluznou podložkou
## místo kol (boční skluz se ruší v `_integrate_forces` – kola se kutálejí jen dopředu), takže:
##  * hráč vozík **táhne**: pružina mezi madlem (`handle_world()`) a bodem u hráče; do kopce hráče zpomaluje `Cargo`,
##  * pustený vozík na svahu **ujede** (nízké tření + malý útlum), ruční brzda = **podložené kolo** (`chocked`): stojí,
##  * náklad (záznamy `cargo`, každý s `node` = model / mrtvé tělo) leží na korbě, přes ni jde přetáhnout **plachta** (`covered`).
## Logiku (nakládání, uchopení, ukládání) vlastní `Cargo`; tady je jen model, fyzika a rozložení nákladu na korbě.
class_name HandCart
extends RigidBody3D

const EMPTY_KG := 25.0
const CAPACITY_KG := 200.0              # nosnost korby (kg)
const HANDLE_LOCAL := Vector3(0.0, 0.85, -1.45)   # madlo na konci oje (vozík jede oj napřed = −Z)
const BED_TOP := 0.5                    # výška podlahy korby (m)
const BED_CENTER_Z := 0.2
const BED_SIZE := Vector3(0.8, 0.28, 1.2)        # šířka × výška bočnic × délka
const HOLD_DIST := 0.8                  # vzdálenost madla od hráče při tažení (m)
const PULL_ACC := 14.0                  # pružina: zrychlení (m/s²) na 1 m vzdálenosti od cíle
const PULL_DAMP := 4.0
const PULL_MAX_ACC := 12.0
const FREE_DAMP := 0.9                  # útlum pusteného vozíku (na svahu ujede pomalu, na rovině zastaví)
const WHEEL_R := 0.25
const COL_BODY := Color(0.6, 0.2, 0.1)
const COL_WOOD := Color(0.55, 0.4, 0.22)
const COL_METAL := Color(0.22, 0.22, 0.24)
const COL_TARP := Color(0.2, 0.4, 0.6)

var cargo: Array = []                   # záznamy nákladu {kind, kg, tag, r, c: Carcass|null, node: Node3D}
var gripped_by := 0                     # id hráče, který drží oj (0 = nikdo)
var chocked := false                    # podložené kolo (zabrzděno)
var covered := false                    # přetažená plachta
var puller: Player                      # hráč, který táhne (nastavuje `Cargo`)
var _wheels: Array[MeshInstance3D] = []
var _tarp: MeshInstance3D
var _rolled := 0.0


static func make(pos: Vector3, yaw: float) -> HandCart:
	var c := HandCart.new()
	c.position = pos
	c.rotation.y = yaw
	return c


func _ready() -> void:
	name = "RucniVozik"
	collision_layer = 8                                  # jako rekvizity: auta ho vidí jako překážku (Car.ai_blocker)
	collision_mask = 1 | 2 | 4 | 8 | 16
	mass = EMPTY_KG
	linear_damp = FREE_DAMP
	angular_damp = 3.0
	can_sleep = true
	custom_integrator = false
	contact_monitor = false
	var pm := PhysicsMaterial.new()
	pm.friction = 0.04
	pm.bounce = 0.0
	physics_material_override = pm
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.35, 0.2)
	# kolize: nízká kluzná podložka + korba (aby hráč a auta vozík neprošli)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.9, 0.12, 1.5)
	cs.shape = bs
	cs.position = Vector3(0, 0.1, 0.05)
	add_child(cs)
	var cb := CollisionShape3D.new()
	var bb := BoxShape3D.new()
	bb.size = Vector3(0.9, 0.35, 1.25)
	cb.shape = bb
	cb.position = Vector3(0, BED_TOP + 0.05, BED_CENTER_Z)
	add_child(cb)
	_build_model()
	set_meta("kind", "ruční vozík")


func _build_model() -> void:
	var k := MeshKit.new()
	var hw := BED_SIZE.x * 0.5
	var hl := BED_SIZE.z * 0.5
	# podlaha a bočnice korby
	k.box(Vector3(0, BED_TOP - 0.03, BED_CENTER_Z), Vector3(BED_SIZE.x, 0.05, BED_SIZE.z), COL_WOOD)
	k.box(Vector3(-hw, BED_TOP + BED_SIZE.y * 0.5 - 0.03, BED_CENTER_Z), Vector3(0.04, BED_SIZE.y, BED_SIZE.z), COL_BODY)
	k.box(Vector3(hw, BED_TOP + BED_SIZE.y * 0.5 - 0.03, BED_CENTER_Z), Vector3(0.04, BED_SIZE.y, BED_SIZE.z), COL_BODY)
	k.box(Vector3(0, BED_TOP + BED_SIZE.y * 0.5 - 0.03, BED_CENTER_Z + hl), Vector3(BED_SIZE.x, BED_SIZE.y, 0.04), COL_BODY)
	k.box(Vector3(0, BED_TOP + BED_SIZE.y * 0.5 - 0.03, BED_CENTER_Z - hl), Vector3(BED_SIZE.x, BED_SIZE.y * 0.6, 0.04), COL_BODY)
	# rám, náprava
	k.cylinder(Vector3(0, WHEEL_R, BED_CENTER_Z), 0.02, 0.02, BED_SIZE.x + 0.34, COL_METAL, Vector3(0, 0, PI * 0.5), 8)
	# oj: dvě tyče od korby k madlu a příčné madlo
	for s in [-1.0, 1.0]:
		var a := Vector3(s * 0.3, BED_TOP - 0.03, BED_CENTER_Z - hl)
		var b := Vector3(s * 0.3, HANDLE_LOCAL.y, HANDLE_LOCAL.z)
		var mid := (a + b) * 0.5
		var d := b - a
		var dl := d.length()
		var xf := Transform3D(Basis.looking_at(d.normalized(), Vector3.UP) * Basis(Vector3.RIGHT, PI * 0.5), mid)
		k.add_prim(_cyl_mesh(0.02, dl), xf, COL_METAL)
	k.cylinder(HANDLE_LOCAL, 0.025, 0.025, 0.7, COL_WOOD, Vector3(0, 0, PI * 0.5), 8)
	# opěrná noha vzadu (vozík nepřepadne)
	k.box(Vector3(0, 0.2, BED_CENTER_Z + hl - 0.05), Vector3(0.5, 0.04, 0.06), COL_METAL)
	MeshKit.mesh_instance(self, k.commit(MeshKit.vc_material(0.85)), 200.0)
	# kola (otáčí se podle jízdy)
	var wm := CylinderMesh.new()
	wm.top_radius = WHEEL_R
	wm.bottom_radius = WHEEL_R
	wm.height = 0.08
	wm.radial_segments = 14
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.08, 0.08, 0.09)
	wmat.roughness = 0.9
	for s in [-1.0, 1.0]:
		var w := MeshInstance3D.new()
		w.mesh = wm
		w.material_override = wmat
		w.position = Vector3(s * (hw + 0.1), WHEEL_R, BED_CENTER_Z)
		w.rotation.z = PI * 0.5
		w.visibility_range_end = 120.0
		add_child(w)
		_wheels.append(w)
	# plachta (schovaná, dokud není `covered`)
	var tk := MeshKit.new()
	tk.box(Vector3(0, 0, 0), Vector3(BED_SIZE.x + 0.12, 0.05, BED_SIZE.z + 0.1), COL_TARP)
	_tarp = MeshInstance3D.new()
	_tarp.mesh = tk.commit(MeshKit.vc_material(0.95))
	_tarp.position = Vector3(0, BED_TOP + BED_SIZE.y + 0.28, BED_CENTER_Z)
	_tarp.scale = Vector3(1.0, 1.0, 1.0)
	_tarp.visible = false
	add_child(_tarp)


static func _cyl_mesh(r: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = h
	m.radial_segments = 6
	return m


## Madlo ve světě.
func handle_world() -> Vector3:
	return global_transform * HANDLE_LOCAL


## Celková hmotnost (kg): vozík + náklad.
func total_kg() -> float:
	return EMPTY_KG + cargo_kg()


func cargo_kg() -> float:
	var s := 0.0
	for e in cargo:
		s += float(e.get("kg", 0.0))
	return s


func free_kg() -> float:
	return maxf(CAPACITY_KG - cargo_kg(), 0.0)


## Přidá záznam nákladu na korbu (model `e["node"]` se připne k vozíku).
func add_cargo(e: Dictionary) -> void:
	cargo.append(e)
	var n = e.get("node")
	if n is Node3D and is_instance_valid(n):
		if (n as Node).get_parent() != self:
			if (n as Node).get_parent() != null:
				(n as Node).get_parent().remove_child(n)
			add_child(n)
	_after_change()


func remove_cargo(e: Dictionary) -> void:
	cargo.erase(e)
	_after_change()


func _after_change() -> void:
	mass = total_kg()
	layout()
	if not covered and gripped_by == 0:
		sleeping = false


## Rozloží náklad po korbě (mřížka 2 × 3, další vrstvy nahoru; velký kus přes celou délku). Plachta schová model.
func layout() -> void:
	var y0 := BED_TOP - 0.005
	var k := 0
	var layer_h := 0.0
	for e in cargo:
		var n = e.get("node")
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		var big := String(Cargo.info(String(e.get("kind", ""))).get("size", "small")) == "large"
		var node3 := n as Node3D
		var lp: Vector3
		if big:
			lp = Vector3(0.0, y0 + layer_h, BED_CENTER_Z)
			layer_h += 0.3
			k = maxi(k, 6)              # další kusy nad něj
		else:
			var col := k % 2
			var row := (k / 2) % 3
			var layer := k / 6
			lp = Vector3((float(col) - 0.5) * 0.36, y0 + layer_h + 0.22 * float(layer), BED_CENTER_Z + (float(row) - 1.0) * 0.38)
			k += 1
		node3.transform = Transform3D(Basis.IDENTITY, lp)
		if node3 is Animal:
			(node3 as Animal).rig.rotation.y = 0.0
			(node3 as Animal).rig.visible = true
		node3.visible = not covered
	if _tarp:
		_tarp.visible = covered
		var h := clampf(0.3 + layer_h + float(k / 6) * 0.22, 0.3, 1.0)
		_tarp.position.y = BED_TOP + h * 0.5 + 0.12
		_tarp.scale.y = 1.0


func set_covered(on: bool) -> void:
	covered = on
	layout()


func set_chocked(on: bool) -> void:
	chocked = on
	if on:
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
	else:
		sleeping = false


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var xf := state.transform
	if chocked and gripped_by == 0:
		state.linear_velocity = Vector3(0.0, minf(state.linear_velocity.y, 0.0), 0.0)
		state.angular_velocity = Vector3.ZERO
		return
	var dt := state.step
	var v := state.linear_velocity
	# kola nejdou bokem: zruš boční složku rychlosti
	var right := xf.basis.x
	right.y = 0.0
	right = right.normalized() if right.length() > 0.01 else Vector3.RIGHT
	v -= right * right.dot(v) * minf(1.0, 14.0 * dt)
	state.linear_velocity = v
	# vozík se nepřeklopí na bok (stabilizace klopení kolem podélné osy)
	var fwd := -xf.basis.z
	var err := xf.basis.y.cross(Vector3.UP).dot(fwd)
	state.apply_torque(fwd * (err * 10.0 - state.angular_velocity.dot(fwd) * 3.0) * mass)
	# táhnutí: pružina mezi madlem a bodem u hráče
	if gripped_by != 0 and puller != null and is_instance_valid(puller):
		var h := xf * HANDLE_LOCAL
		var pp := puller.global_position
		var d := Vector3(pp.x - h.x, 0.0, pp.z - h.z)
		var dist := d.length()
		var dir := d / dist if dist > 0.01 else Vector3.ZERO
		var rel := Vector3(v.x - puller.velocity.x, 0.0, v.z - puller.velocity.z)
		var acc := dir * maxf(dist - HOLD_DIST, 0.0) * PULL_ACC - rel * PULL_DAMP
		if dist < HOLD_DIST:
			acc = -rel * PULL_DAMP * 1.5
		if acc.length() > PULL_MAX_ACC:
			acc = acc.normalized() * PULL_MAX_ACC
		state.apply_force(acc * mass, h - xf.origin)


func _process(delta: float) -> void:
	# kola se točí podle rychlosti dopředu (vizuál)
	var fv := linear_velocity.dot(-global_transform.basis.z)
	_rolled += fv / WHEEL_R * delta
	for w in _wheels:
		w.rotation = Vector3(0.0, 0.0, PI * 0.5)
		w.rotate_object_local(Vector3.UP, _rolled)
