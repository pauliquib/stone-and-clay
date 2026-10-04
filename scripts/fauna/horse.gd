## Kůň – dopravní prostředek hráče (model a chody z AnimalSpecs["kun"]).
##
## Ovládání jezdce (InputState): W jet (drž), S zpomalit o chod / zastavit / couvat, A/D otěže,
## Shift pobídnout (o chod rychleji: krok → klus → cval → trysk), Mezerník skok (od klusu),
## myš rozhlížení, kolečko vzdálenost kamery, V pohled jezdce. F nasednout / sesednout (World).
##
## Fyzika: hmotnost ~550 kg → pozvolné zrychlení a brzdění, poloměr zatáčky roste s rychlostí
## (omezené dostředivé zrychlení), do kopce zpomalí, na příliš prudký svah nevyjde, výdrž klesá
## ve cvalu a trysku (vyčerpaný kůň zpomalí), skok je balistický. Náraz do zdi ve velké rychlosti
## koně zastaví a jezdec může spadnout. Bez jezdce se kůň pase u místa, kde ho jezdec nechal.
##
## Multiplayer (příprava): autoritu nad pohybem koně má KLIENT JEZDCE (jako řidič nad autem) – `net_owner` je
## id klienta (peer), který teď koně řídí (jezdec; bez jezdce server, -1). Ten klient posílá `net_state()`
## (~20 Hz, unreliable), server ho zkontroluje `validate_remote` (rychlost ≤ cval × REMOTE_SPEED_K, žádný
## teleport nad REMOTE_TELEPORT m) a rozešle ostatním. Kůň s `authority = false` (kůň jiného hráče, kopie na
## serveru) je „loutka“: nesimuluje, jen `apply_net_state` + interpolace (stejně jako Animal).
## Kdo koně nikdo nejezdí, řídí ho server (AI pastvy, přivolání). Cizí kůň bez jezdce jde půjčit
## (World.nearest_mountable_horse bere všechny koně).
class_name Horse
extends CharacterBody3D

const GAIT_NAMES := ["stojí", "krok", "klus", "cval", "trysk"]
const GRAVITY := 20.0
const STAMINA_GALLOP := 1.0 / 40.0   # za s v trysku
const STAMINA_CANTER := 1.0 / 160.0
const STAMINA_REST := 1.0 / 45.0
const HORSE_SLIP := 0.8              # podíl klouzavosti povrchu, který pocítí kopyto (1 = jako kolo)
const REMOTE_SPEED_K := 1.25         # server: nejvyšší uvěřitelná rychlost hlášená klientem = cval × tolik
const REMOTE_TELEPORT := 20.0        # server: skok polohy o víc než tolik m mezi dvěma stavy = odmítnout
const REMOTE_SLACK := 1.0            # server: rezerva k ujeté dráze za dt (m; jitter, kolize)
const STARTLE_R := 1400.0            # do této vzdálenosti blesku se kůň hromu poleká (m)
# ---- péče a přivolání (krok Příroda 04) – laditelné
const WHISTLE_R := 300.0             # do této vzdálenosti kůň hvízdnutí (G) uslyší (m)
const CALL_TRAB_D := 20.0            # dál než tolik m od hráče kůň klusá, dál než CALL_CANTER_D cválá
const CALL_CANTER_D := 80.0
const CALL_STOP_D := 3.0             # přiklusá až na tuto vzdálenost a otočí se k hráči
const CALL_MAX_S := 120.0            # po tolika s přivolání vzdá (zaseklý za překážkou)
const FED_DECAY := 1.0 / 1800.0      # ubývání sytosti za s reálného času (prázdný za ~30 min)
const WATER_DECAY := 1.0 / 1200.0    # ubývání napojení (prázdný za ~20 min)
const NEEDY_BELOW := 0.15            # hladový / žíznivý kůň nejde do trysku a hůř odpočívá
const REGEN_FED_K := 0.8             # výdrž se obnovuje ×(1 + K × sytost)
const NEEDY_REGEN := 0.6             # násobek obnovy výdrže u hladového / žíznivého koně
const FEED_AMOUNT := 0.5             # kolik sytosti přidá jedno nakrmení
const WATER_AMOUNT := 0.6            # … a napojení
const GROOM_BONUS_S := 240.0         # jak dlouho po vyčesání platí bonus k obnově výdrže (s)
const GROOM_REGEN := 1.25            # … o kolik rychleji
const DRUNK_SLOW := 0.5              # jezdec nad tolik ‰: kůň sám zpomalí (nejvýš klus)
const DRUNK_REFUSE := 1.5            # jezdec nad tolik ‰: kůň nevyjde
const DRUNK_FALL_K := 0.012          # šance pádu za s v klusu × promile²

var spec: Dictionary
var fauna: Fauna
var rig: QuadrupedRig
var owner_id := 0
var authority := true                # true = simuluje se tady (jezdcův klient / SP / server bez jezdce); false = loutka
var net_owner := -1                  # id klienta s autoritou nad pohybem (jezdec); -1 = server / singleplayer
var rider: Player = null
var rng := RandomNumberGenerator.new()
var level := 0                       # 0 stojí, 1 krok, 2 klus, 3 cval, 4 trysk
var yaw := 0.0
var speed := 0.0
var stamina := 1.0
var tether := Vector3.ZERO           # kde se pase bez jezdce
var state := "graze"

var _gait_v: Array = []
var _prev_sprint := false
var _prev_brake := false
var _back_t := 0.0
var _yaw_rate := 0.0
var _slope := 0.0
var _graze := 0.0
var _target := Vector3.INF
var _idle_t := 5.0
var _snd_hoof: Array[AudioStreamPlayer3D] = []
var _snd_voice: AudioStreamPlayer3D
var _hoof_i := 0
var _snort_t := 10.0
var _exhaust_msg := false
var _refuse_t := 0.0
var _foot: CollisionShape3D
var _torso: CollisionShape3D
var _prev_xf := Transform3D()
var _cur_xf := Transform3D()
var _surf := "teren"                 # povrch pod kopyty (raycast, obnovuje se ~3×/s)
var _surf_t := 0.0
var fed := 0.75                      # sytost 0..1 (krmení u žlabu)
var watered := 0.75                  # napojení 0..1
var groom_t := 0.0                   # zbývá s bonusu po vyčesání
var _caller: Player = null           # hráč, který koně přivolal hvízdnutím
var _call_way: Array = []            # mezibody přivolání (branka výběhu) – Array[Vector3]
var _call_t := 0.0
var _call_stop_t := 0.0
var _drunk_msg_t := 0.0
var _startle := -1.0                 # čeká na hrom z viděného blesku (s do polekání)
var _spooked := 0.0                  # > 0: poslední polekání → hlava nahoru (rig.alert)
var _spook_v := Vector3.ZERO         # boční škobrtnutí z polekání (m/s, doznívá)
# kamera (jen lokální jezdec)
var _cam_rig: Node3D
var _cam: Camera3D
var _cam_yaw := 0.0
var _cam_pitch := -0.2
var _cam_zoom := 6.0
var _cam_idle := 0.0
var _first_person := false
var _pbuf: Array = []                # loutka: poslední stavy [čas příjmu, poloha, yaw, rychlost]


func is_horse() -> bool:
	return true


func setup(f: Fauna, pos: Vector3, yaw_: float, owner: int, seed_: int) -> void:
	fauna = f
	spec = AnimalSpecs.get_spec("kun")
	owner_id = owner
	rng.seed = seed_
	position = pos + Vector3(0, 0.1, 0)
	tether = pos
	yaw = yaw_
	var g: Dictionary = spec["gaits"]
	_gait_v = [0.0, g["walk"] * 0.92, g["trot"] * 0.9, g["canter"] * 0.92, g["gallop"] * 0.9]
	rig = QuadrupedModel.build(spec, {"male": false, "tint": 1.0})
	rig.name = "Model"


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 8 | 16
	floor_max_angle = deg_to_rad(float(spec["max_slope"]) + 5.0)
	floor_snap_length = 0.6
	safe_margin = 0.03
	var geo := QuadrupedModel.geometry(spec)
	var sh := CapsuleShape3D.new()
	sh.radius = 0.3
	sh.height = float(geo["shoulder_h"])
	_foot = CollisionShape3D.new()
	_foot.shape = sh
	_foot.position.y = sh.height * 0.5
	add_child(_foot)
	var bx := BoxShape3D.new()
	bx.size = Vector3(0.62, 0.75, 2.1)
	_torso = CollisionShape3D.new()
	_torso.shape = bx
	_torso.position = Vector3(0, float(geo["y_mid"]) + 0.05, 0.15)
	add_child(_torso)
	add_child(rig)
	rig.top_level = true
	rig.ground_fn = fauna.terrain.height_at   # IK chodidel na svahu
	rig.footfall.connect(_on_footfall)
	for i in 2:
		_snd_hoof.append(NatureSfx.player3d(self, 45.0, -2.0))
	_snd_voice = NatureSfx.player3d(self, 120.0, 0.0)
	_snd_voice.position = Vector3(0, 1.8, 1.2)
	if fauna.weather:
		fauna.weather.lightning.connect(_on_lightning)
	_prev_xf = Transform3D(Basis(Vector3.UP, yaw), global_position)
	_cur_xf = _prev_xf


# ------------------------------------------------------------------ jezdec

func set_rider(p: Player) -> void:
	rider = p
	level = 0
	_caller = null
	_call_way = []
	_play_voice("snort" if rng.randf() < 0.7 else "neigh")
	if p.camera == null:
		return
	_cam_rig = Node3D.new()
	_cam_rig.top_level = true
	add_child(_cam_rig)
	var arm := SpringArm3D.new()
	arm.name = "Rameno"
	arm.collision_mask = 1
	arm.margin = 0.2
	var s := SphereShape3D.new()
	s.radius = 0.25
	arm.shape = s
	arm.add_excluded_object(get_rid())
	_cam_rig.add_child(arm)
	_cam = Camera3D.new()
	_cam.fov = 72.0
	_cam.near = 0.06
	_cam.far = 9000.0
	arm.add_child(_cam)
	_cam.current = true
	_cam_yaw = 0.0
	_first_person = p.first_person


func clear_rider() -> void:
	if rider and rider.visual:
		rider.visual.ride = {}
	rider = null
	level = 0
	tether = global_position
	state = "idle"
	_idle_t = 4.0
	if _cam_rig:
		_cam_rig.queue_free()
		_cam_rig = null
		_cam = null


## Volné místo na sesednutí: vlevo od koně (jezdec sesedá vlevo), jinak vpravo, za, před.
func dismount_spot() -> Vector3:
	var space := get_world_3d().direct_space_state
	var sh := CapsuleShape3D.new()
	sh.radius = 0.35
	sh.height = 1.8
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sh
	q.collision_mask = 1 | 4 | 8 | 16
	q.exclude = [get_rid()]
	var basis := Basis(Vector3.UP, yaw)
	for lp in [Vector3(1.1, 0, 0.2), Vector3(-1.1, 0, 0.2), Vector3(0, 0, -2.2), Vector3(0, 0, 2.4), Vector3(1.8, 0, 0), Vector3(-1.8, 0, 0)]:
		var p: Vector3 = global_position + basis * lp
		var ray := PhysicsRayQueryParameters3D.create(p + Vector3(0, 2.5, 0), p - Vector3(0, 3.0, 0), 1)
		var hit := space.intersect_ray(ray)
		if hit.is_empty():
			continue
		p = hit["position"] + Vector3(0, 0.08, 0)
		q.transform = Transform3D(Basis(), p + Vector3(0, 0.95, 0))
		if space.intersect_shape(q, 1).is_empty():
			return p
	return global_position + basis * Vector3(1.1, 0, 0)


## Kam se jezdec posadí (uzel sedla) a póza (ruce na otěžích, nohy ve třmenech, roztažené kolem hřbetu).
func rider_mount_point() -> Node3D:
	return rig.saddle


func gait_name() -> String:
	return GAIT_NAMES[clampi(level, 0, 4)] if rider else GAIT_NAMES[0]


# ------------------------------------------------------------------ smyčka

func _physics_process(delta: float) -> void:
	if fauna == null:
		return
	_prev_xf = _cur_xf
	if not authority:
		_puppet_process(delta)
		return
	var want := 0.0
	var steer := 0.0
	if rider:
		var r := _rider_input(delta)
		want = r[0]
		steer = r[1]
	else:
		var r := _idle_ai(delta)
		want = r[0]
		steer = r[1]
	# --- natočení: na místě se kůň otočí pomalu, v pohybu omezuje zatáčení dostředivé zrychlení
	var v := absf(speed)
	var turn_max := minf(float(spec["turn"]), float(spec["lat_acc"]) / maxf(v, 0.5))
	if v < 0.3:
		turn_max = 1.1
	var dyaw := clampf(steer, -1.0, 1.0) * turn_max * delta
	yaw = wrapf(yaw + dyaw, -PI, PI)
	_yaw_rate = dyaw / maxf(delta, 0.001)
	# --- svah
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	var t: Terrain = fauna.terrain
	var L: float = spec["length"]
	var h0 := t.height_at(global_position.x, global_position.z)
	var h1 := t.height_at(global_position.x + fwd.x * L * signf(want + 0.001), global_position.z + fwd.z * L * signf(want + 0.001))
	_slope = atan2(h1 - h0, L) * signf(want + 0.001)
	var max_s := deg_to_rad(float(spec["max_slope"]))
	if want > 0.0 and _slope > max_s * 0.5:
		want *= clampf(1.0 - (_slope - max_s * 0.5) / (max_s * 0.5), 0.0, 1.0)
		if _slope > max_s and _refuse_t <= 0.0 and rider:
			_refuse_t = 3.0
			_play_voice("snort")
			fauna.world.notify(rider.id, "show_message", ["Kůň odmítá jít do tak prudkého svahu.", 2.0])
	_refuse_t -= delta
	# --- povětrnostní kluzkost pod kopyty: bahno / mokrá hlína / náledí / sníh
	_surf_t -= delta
	if _surf_t <= 0.0:
		_surf_t = 0.3
		_surf = _surface_under()
	var grip := _hoof_grip()
	want *= lerpf(1.0, 0.55, 1.0 - grip)        # na kluzkém podkladu nerozjede plný chod
	# --- rychlost (zrychlení / brzdění podle hmotnosti; na kluzku horší)
	var acc: float = spec["accel"] if absf(want) > absf(speed) and signf(want) == signf(speed + want * 0.01) else spec["brake"]
	acc *= grip
	speed = move_toward(speed, want, acc * delta)
	# --- hrom z blesku: polekaný kůň sebou trhne stranou
	if _startle >= 0.0:
		_startle -= delta
		if _startle < 0.0:
			_do_startle()
	# --- péče: sytost a napojení pomalu ubývají
	fed = maxf(fed - FED_DECAY * delta, 0.0)
	watered = maxf(watered - WATER_DECAY * delta, 0.0)
	groom_t = maxf(groom_t - delta, 0.0)
	_drunk_msg_t -= delta
	if rider and level >= 2 and v > 3.0:
		var pm := rider.body.promile()
		if pm > DRUNK_SLOW and rng.randf() < delta * DRUNK_FALL_K * pm * pm:
			_drunk_fall()
	# --- výdrž
	if level >= 4 and v > _gait_v[3]:
		stamina -= STAMINA_GALLOP * delta
	elif level == 3 and v > _gait_v[2]:
		stamina -= STAMINA_CANTER * delta
	elif v < _gait_v[2] + 0.2:
		stamina += STAMINA_REST * delta * (1.6 if v < 0.3 else 1.0) * regen_mul()
	stamina = clampf(stamina, 0.0, 1.0)
	# --- pohyb
	var vy := velocity.y
	if is_on_floor():
		vy = -0.8
	else:
		vy -= GRAVITY * delta
	if rider and rider.input.jump_pressed and is_on_floor() and level >= 2 and v > 2.5:
		vy = sqrt(2.0 * GRAVITY * (float(spec["jump"]) + 0.15))
		_play_voice("snort")
	var pre_speed := speed
	# boční smyk: ve zatáčce na kluzkém povrchu kůň uhne ven ze zatáčky; plus škobrtnutí z polekání
	var drift := 0.0
	if grip < 0.85 and absf(_yaw_rate) > 0.05 and v > 1.5:
		drift = _yaw_rate * v * (1.0 - grip) * 0.8
	_spook_v = _spook_v.move_toward(Vector3.ZERO, delta * 5.0)
	velocity = fwd * speed + fwd.cross(Vector3.UP) * drift + _spook_v + Vector3(0, vy, 0)
	move_and_slide()
	# náraz do překážky
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var n := c.get_normal()
		if absf(n.y) < 0.5 and -n.dot(fwd) > 0.6:
			if absf(pre_speed) > 6.0:
				_crash(absf(pre_speed))
			speed = move_toward(speed, 0.0, absf(speed) * 0.7)
			break
	var gy := t.height_at(global_position.x, global_position.z)
	if global_position.y < gy - 1.5:
		global_position.y = gy + 0.2
		velocity.y = 0.0
	_cur_xf = Transform3D(Basis(Vector3.UP, yaw), global_position)
	# jezdec: postava drží pozici koně (pro vzdálenosti, úkoly, zvěř)
	if rider:
		rider.global_position = global_position + Vector3(0, 0.5, 0)
		rider.yaw = yaw + PI
	_snort_t -= delta
	if _snort_t <= 0.0:
		_snort_t = rng.randf_range(12.0, 35.0)
		if fauna.world.nearest_player_dist(global_position) < 60.0:
			_play_voice("snort" if rng.randf() < 0.75 else "neigh")


# ------------------------------------------------------------------ síť

## Stav koně pro síť (celá čísla): [majitel, x, y, z (dm), yaw (1/1024 otáčky), rychlost (dm/s), chod (level),
## id jezdce (-1 = nikdo), sytost 0..100, napojení 0..100, výdrž 0..100].
func net_state() -> Array:
	var p := global_position
	return [owner_id, roundi(p.x * 10.0), roundi(p.y * 10.0), roundi(p.z * 10.0),
		roundi(fposmod(yaw, TAU) / TAU * 1024.0), roundi(speed * 10.0), level,
		rider.id if rider else -1, roundi(fed * 100.0), roundi(watered * 100.0), roundi(stamina * 100.0)]


## Loutka (nebo serverová kopie cizího koně) dostala stav; `now_s` = čas příjmu v s.
func apply_net_state(s: Array, now_s: float) -> void:
	var ny := float(s[4]) / 1024.0 * TAU
	_pbuf.append([now_s, Vector3(float(s[1]) * 0.1, float(s[2]) * 0.1, float(s[3]) * 0.1), ny, float(s[5]) * 0.1])
	while _pbuf.size() > Animal.PUPPET_BUF:
		_pbuf.pop_front()
	level = int(s[6])
	fed = float(s[8]) * 0.01
	watered = float(s[9]) * 0.01
	stamina = float(s[10]) * 0.01


## Server: uvěřitelný stav od klienta jezdce? `dt` = s od posledního přijatého stavu. Odmítne rychlost nad
## cval × REMOTE_SPEED_K, skok polohy nad REMOTE_TELEPORT m a dráhu delší než rychlost × dt (+ REMOTE_SLACK).
func validate_remote(s: Array, dt: float) -> bool:
	var gallop: float = spec["gaits"]["gallop"]
	var vmax := gallop * REMOTE_SPEED_K
	if absf(float(s[5]) * 0.1) > vmax:
		return false
	var d := Vector2(float(s[1]) * 0.1 - global_position.x, float(s[3]) * 0.1 - global_position.z).length()
	if d > REMOTE_TELEPORT:
		return false
	return dt <= 0.0 or d <= vmax * dt + REMOTE_SLACK


## Krok loutky: bez fyziky a AI, poloha a yaw z posledních stavů (zpoždění Animal.PUPPET_DELAY).
func _puppet_process(delta: float) -> void:
	if _pbuf.is_empty():
		return
	var smp := Animal.puppet_sample(_pbuf, Time.get_ticks_msec() / 1000.0 - Animal.PUPPET_DELAY)
	var np: Vector3 = smp[0]
	var ny: float = smp[1]
	speed = smp[2]
	_yaw_rate = lerpf(_yaw_rate, wrapf(ny - yaw, -PI, PI) / maxf(delta, 0.001), 0.3)
	yaw = ny
	global_position = np
	velocity = Vector3.ZERO
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	var L: float = spec["length"]
	var t: Terrain = fauna.terrain
	_slope = atan2(t.height_at(np.x + fwd.x * L, np.z + fwd.z * L) - t.height_at(np.x, np.z), L)
	state = "graze" if absf(speed) < 0.2 and level == 0 else "idle"
	_cur_xf = Transform3D(Basis(Vector3.UP, yaw), np)
	if rider:
		rider.global_position = np + Vector3(0, 0.5, 0)
		rider.yaw = yaw + PI


## Povrch pod kopyty (meta "surface" kolize pod trupem), pro přilnavost i zvuk.
func _surface_under() -> String:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 0.5, 0),
		global_position - Vector3(0, 1.4, 0), 1)
	var hit := space.intersect_ray(q)
	if not hit.is_empty() and hit["collider"] is Node:
		return (hit["collider"] as Node).get_meta("surface", "teren")
	return "teren"


## Přilnavost kopyt na aktuálním povrchu (Weather.surface_grip zjemněná podílem HORSE_SLIP):
## mokrá hlína ~0.6, uježděný sníh ~0.5, náledí ~0.3.
func _hoof_grip() -> float:
	var w := fauna.weather
	if w == null:
		return 1.0
	return lerpf(1.0, w.grip_factor(_surf), HORSE_SLIP)


## Blesk z Weather: hrom uslyší kůň až se zpožděním vzdálenost / rychlost zvuku.
func _on_lightning(pos: Vector3) -> void:
	var d := global_position.distance_to(pos)
	if d > STARTLE_R:
		return
	var delay := d / 343.0
	if _startle < 0.0 or delay < _startle:
		_startle = delay


## Polekání hromem: kůň vrhne hlavou, ožeká a skočí stranou; s jezdcem zpomalí.
func _do_startle() -> void:
	_spooked = 3.5
	var side := Vector3(sin(yaw), 0, cos(yaw)).cross(Vector3.UP) * (1.0 if rng.randf() < 0.5 else -1.0)
	_spook_v = side * rng.randf_range(2.5, 4.0)
	speed = minf(speed, _gait_v[2])
	level = mini(level, 2)
	_play_voice("neigh")
	if rider:
		fauna.world.notify(rider.id, "show_message", ["Kůň se polekal hromu!", 2.0])


## Otěže a pobídky jezdce → [cílová rychlost, řízení].
func _rider_input(delta: float) -> Array:
	var inp := rider.input
	if rider.controls_locked:
		return [0.0, 0.0]
	var fwd_on := inp.throttle > 0.4
	var brake_on := inp.brake > 0.4
	var sprint_edge := inp.sprint and not _prev_sprint
	var brake_edge := brake_on and not _prev_brake
	_prev_sprint = inp.sprint
	_prev_brake = brake_on
	# opilý jezdec má zpožděné a nepřesné pobídky
	var drunk := rider.body.drunk_level()
	if fwd_on and level == 0:
		level = 1
	if sprint_edge and level >= 1:
		level = mini(level + 1, 4 if stamina > 0.15 else 3)
	if brake_edge:
		level = maxi(level - 1, 0)
	# omezení chodu: hladový / vyčerpaný kůň nejde do trysku, s opilým jezdcem jen klus, nad 1,5 ‰ vůbec
	var pm_r := rider.body.promile()
	var cap := 4
	if stamina <= 0.15 or is_needy():
		cap = 3
	if pm_r > DRUNK_SLOW:
		cap = 2
	if pm_r > DRUNK_REFUSE:
		cap = 0
		if (fwd_on or sprint_edge) and _drunk_msg_t <= 0.0:
			_drunk_msg_t = 6.0
			_play_voice("snort")
			fauna.world.notify(rider.id, "show_message", ["Kůň s opilým jezdcem (%s ‰) nevyjde – frká a couvá. Sesedni (F) a vyspi se." % (
				"%.1f" % pm_r).replace(".", ","), 3.5])
	elif pm_r > DRUNK_SLOW and level > cap and _drunk_msg_t <= 0.0:
		_drunk_msg_t = 8.0
		fauna.world.notify(rider.id, "show_message", ["Kůň cítí, že jsi pod vlivem – sám zpomalil.", 2.5])
	level = mini(level, cap)
	if stamina <= 0.02 and level == 4:
		level = 3
		if not _exhaust_msg:
			_exhaust_msg = true
			fauna.world.notify(rider.id, "show_message", ["Kůň je vyčerpaný – nech ho vydechnout v kroku.", 3.0])
	if stamina > 0.4:
		_exhaust_msg = false
	var want := 0.0
	if fwd_on and level > 0:
		want = _gait_v[level]
	elif not fwd_on and absf(speed) < 0.3 and not brake_on:
		level = 0
	# couvání: drž S na místě
	if brake_on and level == 0 and absf(speed) < 0.4:
		_back_t += delta
		if _back_t > 0.35:
			want = -0.9
	else:
		_back_t = 0.0
	var steer := inp.steer + sin(Time.get_ticks_msec() * 0.0013) * 0.25 * drunk
	return [want, steer]


## Kůň bez jezdce: pase se, občas popojde (drží se u místa, kde ho nechali).
func _idle_ai(delta: float) -> Array:
	if _caller != null:
		return _call_ai(delta)
	_idle_t -= delta
	if _target == Vector3.INF:
		if _idle_t <= 0.0:
			_idle_t = rng.randf_range(15.0, 45.0)
			var a := rng.randf() * TAU
			_target = tether + Vector3(cos(a), 0, sin(a)) * rng.randf_range(1.0, 6.0)
		state = "graze"
		return [0.0, 0.0]
	var to := _target - global_position
	to.y = 0.0
	if to.length() < 0.8 or _idle_t < -20.0:
		_target = Vector3.INF
		_idle_t = rng.randf_range(15.0, 45.0)
		return [0.0, 0.0]
	state = "move"
	var diff := wrapf(atan2(to.x, to.z) - yaw, -PI, PI)
	return [_gait_v[1] * 0.8 * clampf(cos(diff), 0.0, 1.0), clampf(diff * 2.0, -1.0, 1.0)]


func _crash(v: float) -> void:
	_play_voice("neigh")
	if rider == null:
		return
	var r := rider
	fauna.world.notify(r.id, "show_message", ["Kůň prudce zastavil před překážkou!", 2.0])
	if v > 9.0 or r.body.drunk_level() > 0.5 and v > 6.0:
		fauna.world.dismount_horse(r.id)
		r.velocity = Vector3(sin(yaw), 0.4, cos(yaw)) * v * 0.5
		r.fall(3.0, "spadl jsi z koně")
		r.body.hurt(v * 1.2, "pád z koně")


## Srážka s autem (volá Car): jezdec spadne, kůň se lekne.
func knock(vel: Vector3, spd: float) -> void:
	speed = 0.0
	velocity = vel * 0.2
	_play_voice("neigh")
	if rider:
		var r := rider
		fauna.world.dismount_horse(r.id)
		r.knock(vel, spd)


# ------------------------------------------------------------------ péče o koně

## Hladový nebo žíznivý kůň nejde do trysku a hůř odpočívá.
func is_needy() -> bool:
	return fed < NEEDY_BELOW or watered < NEEDY_BELOW


## Násobek obnovy výdrže: sytost ×(1 + 0,8 × fed), hlad / žízeň zpomalí, vyčesaný kůň je čilejší.
func regen_mul() -> float:
	var m := 1.0 + REGEN_FED_K * fed
	if is_needy():
		m *= NEEDY_REGEN
	if groom_t > 0.0:
		m *= GROOM_REGEN
	return m


## Krátký řádek pro HUD: sytost, napojení, případně hlad / žízeň.
func care_text() -> String:
	var s := "sytost %d %% · napojen %d %%" % [roundi(fed * 100.0), roundi(watered * 100.0)]
	if fed < NEEDY_BELOW:
		s += " · hladový"
	if watered < NEEDY_BELOW:
		s += " · žíznivý"
	if groom_t > 0.0:
		s += " · vyčesaný"
	return s


func feed_hay() -> void:
	fed = minf(fed + FEED_AMOUNT, 1.0)
	_play_voice("snort")


func give_water() -> void:
	watered = minf(watered + WATER_AMOUNT, 1.0)
	_play_voice("snort")


func groom() -> void:
	groom_t = GROOM_BONUS_S
	_play_voice("snort")


## Hvízdnutí: kůň bez jezdce do WHISTLE_R přiklusá k hráči po zemi (ze zavřeného výběhu přes branku).
## Vrací false, když hráče neslyší.
func call_to(p: Player) -> bool:
	if rider != null or p == null:
		return false
	if global_position.distance_to(p.global_position) > WHISTLE_R:
		return false
	_caller = p
	_call_t = 0.0
	_call_stop_t = 0.0
	_call_way = []
	_target = Vector3.INF
	var pd: Paddock = fauna.world.paddock
	if pd != null and pd.contains(global_position) and not pd.contains(p.global_position):
		_call_way = [pd.gate_in(), pd.gate_out()]
	_play_voice("neigh")
	return true


func _call_ai(delta: float) -> Array:
	_call_t += delta
	if not is_instance_valid(_caller) or _caller.horse != null or _caller.car != null or _call_t > CALL_MAX_S:
		_caller = null
		level = 0
		return [0.0, 0.0]
	var goal: Vector3 = _caller.global_position
	if not _call_way.is_empty():
		goal = _call_way[0]
	var to := goal - global_position
	to.y = 0.0
	var d := to.length()
	var diff := wrapf(atan2(to.x, to.z) - yaw, -PI, PI)
	if not _call_way.is_empty():
		if d < 1.6:
			_call_way.pop_front()
	elif d < CALL_STOP_D:
		# došel: zastaví, otočí se k hráči a chvíli počká, pak se zase pase
		level = 0
		_call_stop_t += delta
		state = "idle"
		if _call_stop_t > 5.0:
			_caller = null
			tether = global_position
			_idle_t = 6.0
		return [0.0, clampf(diff * 2.0, -1.0, 1.0)]
	# chod podle vzdálenosti (hladový kůň nejde cvalem)
	var gi := 1
	if d > CALL_CANTER_D and not is_needy() and stamina > 0.2:
		gi = 3
	elif d > CALL_TRAB_D:
		gi = 2
	level = gi
	state = "move"
	return [_gait_v[gi] * clampf(cos(diff) * 1.2, 0.15, 1.0), clampf(diff * 2.0, -1.0, 1.0)]


## Opilý jezdec se v sedle neudrží.
func _drunk_fall() -> void:
	var r := rider
	if r == null:
		return
	var v := absf(speed)
	_play_voice("neigh")
	fauna.world.notify(r.id, "show_message", ["Opilý jsi se v sedle neudržel!", 3.0])
	fauna.world.dismount_horse(r.id)
	r.velocity = Vector3(sin(yaw), 0.3, cos(yaw)) * v * 0.4
	r.fall(3.0, "spadl jsi z koně")
	r.body.hurt(v * 1.0 + 2.0, "pád z koně")


## Otisk kopyta ve sněhu (správce stop `World.tracks`).
func _stamp_track(leg: int) -> void:
	var tr: Tracks = fauna.world.tracks
	if tr == null or fauna.weather == null or fauna.weather.snow_cover < Tracks.SNOW_MIN:
		return
	var b := Basis(Vector3.UP, yaw)
	var lp := Vector3(0.14 if leg % 2 == 0 else -0.14, 0.0, 0.62 if leg < 2 else -0.6)
	tr.add("hoof", global_position + b * lp, yaw)


# ------------------------------------------------------------------ vzhled, kamera, zvuk

func _process(delta: float) -> void:
	var f := Engine.get_physics_interpolation_fraction()
	var xf := _prev_xf.interpolate_with(_cur_xf, f)
	rig.global_transform = xf
	var k := 1.0 - exp(-delta * 2.5)
	_graze = lerpf(_graze, 1.0 if rider == null and state == "graze" else 0.0, k)
	rig.speed = speed
	rig.turn_rate = _yaw_rate
	rig.slope = _slope
	rig.graze = _graze
	_spooked = maxf(_spooked - delta, 0.0)
	rig.alert = maxf(0.3 if rider else 0.0, _spooked / 3.5)   # polekaný kůň vrhne hlavou
	rig.airborne = clampf(absf(velocity.y) / 5.0, 0.0, 1.0) if not is_on_floor() else 0.0
	rig.animate(delta)
	if rider:
		_rider_pose()
	if _cam_rig:
		_camera(delta, xf)


## Póza jezdce: sed v sedle, v klusu vysedá (lehký klus), ve cvalu a trysku lehký sed v předklonu.
func _rider_pose() -> void:
	var vis := rider.visual
	var geo_ride: Dictionary = rig.ride
	var st: Vector3 = geo_ride["stirrup"]
	var hands: Vector3 = geo_ride["hands"]
	var post := 0.0
	var lean := 0.12
	match rig.gait:
		"trot":
			post = maxf(sin(rig.phase * TAU * 2.0), 0.0) * 0.07
			lean = 0.2
		"canter":
			post = 0.03 + sin(rig.phase * TAU) * 0.02
			lean = 0.3
		"gallop":
			post = 0.1
			lean = 0.55
	var hips := 0.5
	vis.position = Vector3(0, -hips + 0.02 + post, -0.02)
	# kyčle jsou roztažené kolem hřbetu → IK nohou v rovině odkloněné o úhel `spread`
	var hip_x := 0.093
	var drop := st.y - (vis.position.y + hips - 0.03)
	var spread := atan2(st.x - hip_x, -drop)
	var reach := Vector2(st.x - hip_x, drop).length()
	var foot_y := hips - 0.03 - reach
	var feet_z := st.z - vis.position.z
	vis.ride = {"hips": hips, "lean": lean, "spread": spread,
		"hands": [hands - vis.position], "feet": [Vector3(0, foot_y, feet_z), Vector3(0, foot_y, feet_z)]}


func _camera(delta: float, xf: Transform3D) -> void:
	var inp := rider.input
	var rel := inp.take_look()
	if rel != Vector2.ZERO:
		_cam_yaw -= rel.x * 0.003
		_cam_pitch = clampf(_cam_pitch - rel.y * 0.003, -1.2, 0.7)
		_cam_idle = 0.0
	else:
		_cam_idle += delta
	var z := inp.take_zoom()
	if z != 0.0:
		_cam_zoom = clampf(_cam_zoom + z, 3.0, 14.0)
	if inp.take_toggle_view():
		_first_person = not _first_person
		rider.first_person = _first_person
	# v pohybu se kamera sama vrací za koně
	if _cam_idle > 1.5 and absf(speed) > 1.0:
		_cam_yaw = lerp_angle(_cam_yaw, 0.0, 1.0 - exp(-delta * 1.5))
	var arm: SpringArm3D = _cam_rig.get_node("Rameno")
	var head := rig.saddle.global_position + Vector3(0, 0.85, 0)
	if _first_person:
		var b := xf.basis * Basis(Vector3.UP, _cam_yaw + PI) * Basis(Vector3.RIGHT, _cam_pitch)
		_cam_rig.global_transform = Transform3D(b, head + xf.basis.z * 0.15)
		arm.spring_length = 0.0
		rider.visual.set_first_person(true)
	else:
		var b2 := Basis(Vector3.UP, yaw + _cam_yaw + PI) * Basis(Vector3.RIGHT, _cam_pitch)
		_cam_rig.global_transform = Transform3D(b2, head + Vector3(0, 0.3, 0))
		arm.spring_length = _cam_zoom
		rider.visual.set_first_person(false)
	_cam.fov = lerpf(_cam.fov, 72.0 + clampf(absf(speed) - 7.0, 0.0, 8.0) * 1.2, 1.0 - exp(-delta * 3.0))


func _on_footfall(leg: int) -> void:
	if fauna.world.nearest_player_dist(global_position) > 45.0:
		return
	_stamp_track(leg)
	var p := _snd_hoof[_hoof_i]
	_hoof_i = (_hoof_i + 1) % _snd_hoof.size()
	# povrch pod koněm: asfalt / štěrk = klapot, tráva a hlína = dusot (_surf se obnovuje ve fyzice)
	var hard := _surf == "asfalt" or _surf == "sterk"
	p.stream = NatureSfx.get_stream("hoof" if hard else "hoof_soft")
	p.pitch_scale = rng.randf_range(0.9, 1.1)
	p.volume_db = -4.0 + minf(absf(speed), 12.0) * 0.4
	p.play()


func _play_voice(kind: String) -> void:
	if _snd_voice == null:
		return
	_snd_voice.stream = NatureSfx.get_stream(kind)
	_snd_voice.pitch_scale = rng.randf_range(0.92, 1.06)
	_snd_voice.play()
