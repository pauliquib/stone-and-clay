## Jedno hospodářské zvíře (M2.6): stav (hlad, žízeň, zdraví, spokojenost, věk), jednoduché bloudění
## po výběhu (do přístřešku v noci / za deště, jinak náhodné body – stejná myšlenka jako u `Animal`,
## ale bez útěku a vnímání hráče – zvíře je ve výběhu ochočené) a model.
##
## Model: čtyřnožci (`FarmSpecs.model` je klíč do `AnimalSpecs`) sdílí `QuadrupedModel` / `QuadrupedRig`
## se zvěří beze změny (jen `foot_ik` a `ground_fn` napojené na terén); slepice má vlastní jednoduchý
## model (tělo, hřebínek, zobáček) z `MeshKit`, protože `Bird` je stavěný na létání. Mládě je jen menší
## měřítko (`FarmSpecs.YOUNG_SCALE` → 1.0 do `grow_days`), žádný samostatný druh jako u divočáka / selete.
class_name FarmAnimal
extends Node3D

const WANDER_SPEED := 0.7           # m/s – klidná chůze po výběhu
const TURN_RATE := 1.6              # rad/s
const ESCAPE_CHECK_S := 6.0
const ESCAPE_CHANCE := 0.12         # na kontrolu, jen když je zvíře blízko otevřené branky
const ESCAPE_ROAM_R := 14.0         # jak daleko od branky se zatoulané zvíře drží

var farm: Farm
var uid := 0                        # pořadové číslo v rámci farmy (ukládání, nabídky)
var species := ""
var sex := "f"                      # "m" / "f"
var farm_name := ""                 # jméno od hráče (nepovinné)
var age_days := 0.0
var hunger := 1.0                   # 1 = nasyceno, 0 = hladové
var thirst := 1.0
var health := 1.0
var happiness := 0.6
var starve_h := 0.0                 # kolik hodin po sobě je hunger na nule (zanedbání, M4.4 háček)
var milk_l := 0.0                   # nadojeno, čeká na sebrání
var shear_year := -1                # rok poslední stříže (ovce)
var escaped := false
var hold_at := Vector3.INF          # M3.2: zvíře má stát na tomhle místě (statek – kráva na stání při dojení), INF = volně

var _rig: QuadrupedRig
var _bird_mi: MeshInstance3D
var _yaw := 0.0
var _speed := 0.0
var _target := Vector3.INF
var _wait_t := 0.0
var _escape_t := 0.0
var _t := 0.0
var _rng := RandomNumberGenerator.new()


func setup(f: Farm, uid_: int, sp: String, sex_: String, age: float) -> void:
	farm = f
	uid = uid_
	species = sp
	sex = sex_
	age_days = age
	_rng.randomize()
	_yaw = _rng.randf() * TAU
	_build_model()
	var spawn: Vector3 = farm.pen.shelter_pos(String(FarmSpecs.info(species).get("shelter", "")))
	global_position = spawn + Vector3(_rng.randf_range(-1.5, 1.5), 0, _rng.randf_range(-1.5, 1.5))
	global_position.y = farm.world.terrain.height_at(global_position.x, global_position.z)
	rotation.y = _yaw


func is_adult() -> bool:
	return FarmSpecs.is_adult(species, age_days)


func age_scale() -> float:
	if is_adult():
		return 1.0
	var grow: float = float(FarmSpecs.info(species).get("grow_days", 60.0))
	return lerpf(FarmSpecs.YOUNG_SCALE, 1.0, clampf(age_days / maxf(grow, 1.0), 0.0, 1.0))


func display_name() -> String:
	var base := FarmSpecs.display_name(species, sex)
	return "%s (%s)" % [farm_name, base] if farm_name != "" else base


func status_text() -> String:
	var age_txt := "mládě" if not is_adult() else "dospělé"
	return "%s – %s, hlad %d %%, žízeň %d %%, zdraví %d %%%s" % [display_name(), age_txt, roundi(hunger * 100.0),
		roundi(thirst * 100.0), roundi(health * 100.0), " – ZATOULANÉ" if escaped else ""]


# ------------------------------------------------------------------ model

func _build_model() -> void:
	var spec := FarmSpecs.info(species)
	var model_key := String(spec.get("model", ""))
	if model_key == "bird":
		_build_bird()
	else:
		_rig = QuadrupedModel.build(AnimalSpecs.get_spec(model_key), {"male": sex == "m"})
		add_child(_rig)
		_rig.foot_ik = true
		_rig.ground_fn = Callable(farm.world.terrain, "height_at")
	scale = Vector3.ONE * age_scale()


func _build_bird() -> void:
	var mk := MeshKit.new()
	var feather: Color = Color(0.55, 0.24, 0.1) if sex == "m" else Color(0.92, 0.9, 0.84)
	var comb := Color(0.82, 0.14, 0.12)
	var beak := Color(0.85, 0.62, 0.16)
	var leg := Color(0.85, 0.65, 0.2)
	mk.sphere(Vector3(0, 0.19, 0), 0.12, feather, Vector3(1.0, 0.85, 1.35))
	mk.sphere(Vector3(0, 0.31, 0.11), 0.05, feather)
	mk.box(Vector3(0, 0.37, 0.11), Vector3(0.014, 0.03, 0.05), comb)                       # hřebínek
	mk.box(Vector3(0, 0.265, 0.145), Vector3(0.012, 0.018, 0.018), comb)                   # laloky
	mk.box(Vector3(0, 0.3, 0.16), Vector3(0.017, 0.016, 0.03), beak)                       # zobáček
	for s: float in [-1.0, 1.0]:
		mk.box(Vector3(0.095 * s, 0.18, -0.02), Vector3(0.03, 0.12, 0.17), feather.darkened(0.1))   # křídla
	mk.box(Vector3(0, 0.28, -0.16), Vector3(0.02, 0.13, 0.03), feather.darkened(0.15), Vector3(0.55, 0, 0))  # ocas
	for s: float in [-1.0, 1.0]:
		mk.cylinder(Vector3(0.035 * s, 0.08, 0.0), 0.009, 0.009, 0.16, leg)
	_bird_mi = MeshKit.mesh_instance(self, mk.commit(MeshKit.vc_material(0.8)), 150.0)


func _animate_bird(delta: float) -> void:
	if not is_instance_valid(_bird_mi):
		return
	_t += delta * (7.0 if _speed > 0.05 else 1.2)
	_bird_mi.position.y = absf(sin(_t)) * (0.025 if _speed > 0.05 else 0.006)


# ------------------------------------------------------------------ pohyb (bloudění po výběhu)

func _process(delta: float) -> void:
	if farm == null or not is_instance_valid(farm) or not farm.pen.ok:
		return
	_wander(delta)
	if _rig:
		_rig.speed = _speed
		_rig.turn_rate = 0.0
		_rig.graze = 1.0 if _speed < 0.05 else 0.0
		_rig.animate(delta)
	else:
		_animate_bird(delta)
	_escape_t -= delta
	if _escape_t <= 0.0:
		_escape_t = ESCAPE_CHECK_S
		if farm.pen.gate_open and not escaped and global_position.distance_to(farm.pen.gate_world()) < 4.0 and _rng.randf() < ESCAPE_CHANCE:
			escaped = true
			_target = Vector3.INF
			global_position = farm.pen.gate_out()


## M3.2: pošle zvíře na místo a drží ho tam (INF = zase volně po výběhu).
func hold(pos: Vector3) -> void:
	if hold_at == pos:
		return
	hold_at = pos
	_target = Vector3.INF
	_wait_t = 0.0


func lead_back() -> void:
	escaped = false
	_target = Vector3.INF
	global_position = farm.pen.gate_in()


func _wander(delta: float) -> void:
	var want_speed := 0.0
	if _target == Vector3.INF:
		_wait_t -= delta
		if _wait_t <= 0.0:
			_pick_target()
	else:
		var to := _target - global_position
		to.y = 0.0
		var d := to.length()
		if d < 0.4:
			_target = Vector3.INF
			_wait_t = _rng.randf_range(3.0, 12.0)
		else:
			var want_yaw := atan2(to.x, to.z)
			var diff := wrapf(want_yaw - _yaw, -PI, PI)
			_yaw = wrapf(_yaw + clampf(diff, -TURN_RATE * delta, TURN_RATE * delta), -PI, PI)
			want_speed = WANDER_SPEED * clampf(cos(diff), 0.15, 1.0)
	_speed = move_toward(_speed, want_speed, 1.2 * delta)
	var fwd := Vector3(sin(_yaw), 0, cos(_yaw))
	var np := global_position + fwd * _speed * delta
	np.y = farm.world.terrain.height_at(np.x, np.z)
	global_position = np
	rotation.y = _yaw


func _pick_target() -> void:
	var shelter := String(FarmSpecs.info(species).get("shelter", ""))
	var want_shelter := farm.world.clock.is_night() or (farm.world.weather != null and farm.world.weather.is_raining())
	if hold_at != Vector3.INF and not escaped:
		_target = hold_at
		return
	if escaped:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(2.0, ESCAPE_ROAM_R)
		var base := farm.pen.gate_out()
		_target = base + Vector3(cos(a) * r, 0, sin(a) * r)
	elif want_shelter:
		var sp: Vector3 = farm.pen.shelter_pos(shelter)
		_target = sp + Vector3(_rng.randf_range(-1.2, 1.2), 0, _rng.randf_range(-1.2, 1.2))
	else:
		_target = farm.pen.random_point(_rng, 1.5)


# ------------------------------------------------------------------ ukládání

func to_dict() -> Dictionary:
	return {"uid": uid, "sp": species, "sex": sex, "name": farm_name, "age": snappedf(age_days, 0.01),
		"hunger": snappedf(hunger, 0.01), "thirst": snappedf(thirst, 0.01), "health": snappedf(health, 0.01),
		"happy": snappedf(happiness, 0.01), "starve_h": snappedf(starve_h, 0.1), "milk": snappedf(milk_l, 0.01),
		"shear_year": shear_year, "escaped": escaped,
		"x": snappedf(global_position.x, 0.01), "z": snappedf(global_position.z, 0.01)}


func from_dict(d: Dictionary) -> void:
	uid = int(d.get("uid", 0))
	farm_name = String(d.get("name", ""))
	age_days = float(d.get("age", 0.0))
	hunger = clampf(float(d.get("hunger", 1.0)), 0.0, 1.0)
	thirst = clampf(float(d.get("thirst", 1.0)), 0.0, 1.0)
	health = clampf(float(d.get("health", 1.0)), 0.0, 1.0)
	happiness = clampf(float(d.get("happy", 0.6)), 0.0, 1.0)
	starve_h = float(d.get("starve_h", 0.0))
	milk_l = float(d.get("milk", 0.0))
	shear_year = int(d.get("shear_year", -1))
	escaped = bool(d.get("escaped", false))
	scale = Vector3.ONE * age_scale()
	if d.has("x") and d.has("z"):
		global_position = Vector3(float(d["x"]), 0.0, float(d["z"]))
		global_position.y = farm.world.terrain.height_at(global_position.x, global_position.z)
