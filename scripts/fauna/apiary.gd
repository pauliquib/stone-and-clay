## Včelnice: 3–5 úlů na podstavci a včely létající mezi česnem a květy v okolí.
##
## Včely létají jen za příznivého počasí (nad ~10 °C, bez deště, silného větru a za světla) a když něco
## kvete (Seasons.BLOOM). Kdo se zdrží u úlu (blíž než 2,2 m déle než 1,5 s), toho strážkyně pronásledují
## a bodají (drobné zranění), dokud neuteče ~30 m daleko nebo nenastoupí do auta.
## Včely jsou MultiMesh (1 draw call), simulace běží jen když je hráč do 90 m.
##
## Multiplayer: včely a mravenci jsou čistě klientský efekt (každý klient si je simuluje sám, nic se
## neposílá). Rozzlobené včely a bodnutí (zranění, událost `bee_sting`) rozhoduje server – `_sting` se volá
## jen s autoritou (`authority`, výchozí true = singleplayer / server). Klient s `authority = false`
## včely jen kreslí; zranění mu přijde ze serveru.
class_name Apiary
extends Node3D

const N_BEES := 110
const FORAGE_R := 45.0               # jak daleko létají na květy (m) – ve hře kratší než ve skutečnosti
const BEE_SPEED := 5.5               # m/s (skutečnost 6–7 m/s)
const ANGRY_N := 22
const HIVE_COLORS := [Color(0.25, 0.45, 0.72), Color(0.3, 0.6, 0.35), Color(0.85, 0.72, 0.25), Color(0.75, 0.35, 0.25), Color(0.9, 0.9, 0.85)]

var fauna: Fauna
var authority := true                # false = klient v MP: bodnutí neřeší (rozhoduje server)
var rng := RandomNumberGenerator.new()
var hives: Array[Vector3] = []       # česna (vletové otvory) ve světě
var flowers: Array[Vector3] = []
var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _tgt := PackedVector3Array()
var _st := PackedInt32Array()        # 0 v úlu, 1 letí ven, 2 na květu, 3 letí domů, 4 útočí
var _wait := PackedFloat32Array()
var _snd: AudioStreamPlayer3D
var _near := false
var _disturb := 0.0
var _angry_t := 0.0
var _angry_id := 0
var _sting_cool := 0.0
var _t := 0.0


func setup(f: Fauna, pos: Vector3, seed_: int) -> void:
	fauna = f
	rng.seed = seed_
	position = pos
	name = "Vcelnice_%d" % (seed_ % 10000)


func _ready() -> void:
	_build_hives()
	for i in 14:
		var p: Vector3 = fauna.random_point(global_position, FORAGE_R, "meadow", rng, 4)
		flowers.append(p + Vector3(0, 0.4, 0))
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.mesh = _bee_mesh()
	_mm.instance_count = N_BEES
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = _mm
	_mmi.top_level = true
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mmi.visibility_range_end = 90.0
	add_child(_mmi)
	_mmi.global_transform = Transform3D.IDENTITY
	_pos.resize(N_BEES)
	_vel.resize(N_BEES)
	_tgt.resize(N_BEES)
	_st.resize(N_BEES)
	_wait.resize(N_BEES)
	for i in N_BEES:
		var h := hives[i % hives.size()]
		_pos[i] = h
		_st[i] = 0
		_wait[i] = rng.randf_range(0.0, 12.0)
		_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * 0.001), h))
	_snd = NatureSfx.player3d(self, 22.0, -6.0)
	_snd.position = Vector3(0, 0.8, 0)


func _build_hives() -> void:
	var k := MeshKit.new()
	var wood := Color(0.42, 0.3, 0.18)
	var n := rng.randi_range(3, 5)
	var yaw := rng.randf() * TAU
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	# podstavec
	var span := n * 0.75
	var base_y := fauna.terrain.height_at(global_position.x, global_position.z) - global_position.y
	k.box(Vector3(0, base_y + 0.22, 0), Vector3(span + 0.3, 0.06, 0.7), wood, Vector3(0, yaw, 0))
	for s: float in [-1.0, 1.0]:
		for t: float in [-1.0, 1.0]:
			k.box(Vector3(0, base_y + 0.1, 0) + right * s * span * 0.45 + fwd * t * 0.28, Vector3(0.07, 0.25, 0.07), wood.darkened(0.3))
	for i in n:
		var c: Color = HIVE_COLORS[rng.randi() % HIVE_COLORS.size()]
		var p := right * (i - (n - 1) * 0.5) * 0.75 + Vector3(0, base_y + 0.25, 0)
		var hh := rng.randf_range(0.55, 0.75)
		k.box(p + Vector3(0, hh * 0.5, 0), Vector3(0.55, hh, 0.55), c, Vector3(0, yaw, 0))
		# stříška
		k.box(p + Vector3(0, hh + 0.04, 0), Vector3(0.68, 0.06, 0.68), Color(0.35, 0.35, 0.36), Vector3(0, yaw, 0))
		k.box(p + Vector3(0, hh + 0.1, 0), Vector3(0.5, 0.06, 0.5), Color(0.3, 0.3, 0.31), Vector3(0, yaw, 0))
		# česno a přistávací prkénko
		var ent := p + fwd * 0.28 + Vector3(0, 0.1, 0)
		k.box(ent, Vector3(0.22, 0.025, 0.02), Color(0.05, 0.04, 0.03), Vector3(0, yaw, 0))
		k.box(ent + fwd * 0.05 - Vector3(0, 0.03, 0), Vector3(0.25, 0.015, 0.1), c.lightened(0.3), Vector3(0, yaw, 0))
		hives.append(global_position + ent + fwd * 0.08)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.6, hh + 0.4, 0.6)
		cs.shape = bs
		cs.position = p + Vector3(0, (hh + 0.4) * 0.5 - 0.2, 0)
		cs.rotation.y = yaw
		body.add_child(cs)
	var mi := MeshKit.mesh_instance(self, k.commit(QuadrupedModel.fur_material(1.0)), 260.0)
	mi.name = "Ule"


func _bee_mesh() -> ArrayMesh:
	var k := MeshKit.new()
	var yel := Color(0.85, 0.6, 0.1)
	var blk := Color(0.08, 0.06, 0.04)
	k.sphere(Vector3(0, 0, -0.004), 0.0045, yel, Vector3(1, 1, 1.5), Vector3.ZERO, 8, 5)
	k.sphere(Vector3(0, 0, -0.006), 0.0047, blk, Vector3(0.9, 0.9, 0.6), Vector3.ZERO, 8, 5)
	k.sphere(Vector3(0, 0, 0.004), 0.0035, blk, Vector3.ONE, Vector3.ZERO, 8, 5)
	k.sphere(Vector3(0, 0, 0.008), 0.0025, blk, Vector3.ONE, Vector3.ZERO, 6, 4)
	for s: float in [1.0, -1.0]:
		k.sphere(Vector3(s * 0.005, 0.003, 0.002), 0.001, Color(0.85, 0.88, 0.92), Vector3(4.0, 0.3, 2.2), Vector3(0, 0, s * 0.3), 6, 3)
	# ve hře jsou včely o něco větší, aby byly vidět (skutečně ~1,3 cm)
	var m := k.commit(QuadrupedModel.fur_material(1.0))
	return m


# ------------------------------------------------------------------ simulace

func _physics_process(delta: float) -> void:
	_t += delta
	var w = fauna.world
	var d: float = w.nearest_player_dist(global_position)
	_near = d < 90.0
	_mmi.visible = _near
	if not _near:
		if _snd.playing:
			_snd.stop()
		return
	var act := _activity()
	# zvuk
	var loud := clampf(act * 1.2 + (0.6 if _angry_t > 0.0 else 0.0), 0.0, 1.0)
	if loud > 0.05:
		if not _snd.playing:
			_snd.stream = NatureSfx.get_stream("bees")
			_snd.play()
		_snd.volume_db = lerpf(-24.0, -2.0, loud)
	elif _snd.playing:
		_snd.stop()
	_check_disturb(delta, act)
	var player: Player = w.nearest_player(global_position)
	var ppos := player.global_position + Vector3(0, 1.5, 0) if player else Vector3.INF
	var n_angry := 0
	for i in N_BEES:
		var st := _st[i]
		var p := _pos[i]
		match st:
			0:  # v úlu
				_wait[i] -= delta
				if _wait[i] <= 0.0 and rng.randf() < act:
					_st[i] = 1
					_tgt[i] = flowers[rng.randi() % flowers.size()] + Vector3(rng.randf_range(-2, 2), rng.randf_range(0, 0.6), rng.randf_range(-2, 2))
					_vel[i] = (_tgt[i] - p).normalized() * 1.0
				elif _wait[i] <= 0.0:
					_wait[i] = rng.randf_range(3.0, 10.0)
			1, 3:  # let
				var to := _tgt[i] - p
				var dist := to.length()
				if dist < 0.3:
					if st == 1:
						_st[i] = 2
						_wait[i] = rng.randf_range(2.0, 7.0)
					else:
						_st[i] = 0
						_wait[i] = rng.randf_range(4.0, 15.0) / maxf(act, 0.2)
						p = _tgt[i]
				else:
					var sp := minf(BEE_SPEED, dist * 2.0 + 0.4)
					var wob := Vector3(sin(_t * 9.0 + i), sin(_t * 7.0 + i * 1.7) * 0.6, cos(_t * 8.0 + i * 0.7)) * 1.5
					_vel[i] = _vel[i].lerp(to / dist * sp + wob, 1.0 - exp(-delta * 4.0))
					p += _vel[i] * delta
			2:  # na květu – popojíždí
				_wait[i] -= delta
				p += Vector3(sin(_t * 3.0 + i), 0, cos(_t * 2.5 + i)) * 0.15 * delta
				_vel[i] = Vector3(sin(_t * 3.0 + i), 0, cos(_t * 2.5 + i))
				if _wait[i] <= 0.0 or act < 0.05:
					_st[i] = 3
					_tgt[i] = hives[i % hives.size()]
			4:  # útočí
				n_angry += 1
				if _angry_t <= 0.0 or ppos == Vector3.INF:
					_st[i] = 3
					_tgt[i] = hives[i % hives.size()]
				else:
					var to := ppos + Vector3(sin(_t * 5.0 + i) * 0.5, sin(_t * 4.0 + i) * 0.4, cos(_t * 6.0 + i) * 0.5) - p
					_vel[i] = _vel[i].lerp(to.normalized() * 7.5, 1.0 - exp(-delta * 5.0))
					p += _vel[i] * delta
					if authority and to.length() < 0.5 and _sting_cool <= 0.0 and rng.randf() < delta * 1.5:
						_sting(player)
		_pos[i] = p
		var scl := 0.001 if st == 0 else 2.2
		var v := _vel[i]
		var b := Basis()
		if v.length() > 0.05:
			b = Basis.looking_at(-v.normalized(), Vector3.UP) if absf(v.normalized().y) < 0.99 else Basis()
		_mm.set_instance_transform(i, Transform3D(b.scaled(Vector3.ONE * scl), p))
	_sting_cool -= delta
	if _angry_t > 0.0:
		_angry_t -= delta
		if player == null or player.global_position.distance_to(global_position) > 30.0 or player.get("car") != null:
			_angry_t = 0.0
		# posily z úlu
		if n_angry < ANGRY_N:
			for i in N_BEES:
				if _st[i] != 4 and rng.randf() < 0.05:
					_st[i] = 4
					if _pos[i].distance_to(hives[i % hives.size()]) < 0.1:
						_pos[i] = hives[i % hives.size()]
					break


## 0..1 kolik včel vylétá – teplota, déšť, vítr, světlo, kvetení.
func _activity() -> float:
	var w: Weather = fauna.weather
	var c: Clock = fauna.clock
	var a := clampf(c.daylight() * 1.3 - 0.2, 0.0, 1.0)
	if w:
		a *= clampf((w.temp - 9.0) / 8.0, 0.0, 1.0)
		a *= 1.0 - smoothstep(0.02, 0.15, w.rain)
		a *= 1.0 - smoothstep(7.0, 12.0, w.wind)
	a *= clampf(Seasons.bloom(c.day_of_year()) * 1.4 + 0.08, 0.0, 1.0)
	return a


func _check_disturb(delta: float, act: float) -> void:
	var w = fauna.world
	var p: Player = w.nearest_player(global_position)
	if p == null or act < 0.02 or p.beekeeper_suit:
		_disturb = 0.0          # v kukle (úkol Med) včely nebodají
		return
	var close := false
	for h in hives:
		if h.distance_to(p.global_position + Vector3(0, 0.5, 0)) < 2.2:
			close = true
			break
	_disturb = _disturb + delta if close else maxf(_disturb - delta * 0.5, 0.0)
	if _disturb > 1.5 and _angry_t <= 0.0:
		_angry_t = 25.0
		_angry_id = p.id
		w.notify(p.id, "show_message", ["Rozzlobil jsi včely! Uteč od úlů.", 3.0])


func _sting(p: Player) -> void:
	if p == null or not p.has_method("knock"):
		return
	_sting_cool = rng.randf_range(0.8, 2.5)
	p.body.hurt(1.5, "bodnutí včelou")
	fauna.world.emit_game_event(p.id, "bee_sting", {})
