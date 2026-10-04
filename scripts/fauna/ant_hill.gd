## Mraveniště mravence lesního (Formica rufa): kupa z jehličí a mravenci na stezkách k okolním stromům
## (lezou pro medovici mšic) a po povrchu kupy. Nad ~6 °C a bez sněhu jsou venku, v zimě jen kupa.
## Kdo si stoupne na mraveniště, tomu mravenci vlezou do bot (drobné zranění, zpráva).
## Mravenci jsou MultiMesh a hýbou se jen, když je hráč do 25 m.
class_name AntHill
extends Node3D

const N_ANTS := 220
const ANT_SPEED := 0.05              # m/s (skutečnost 3–5 cm/s)
const ANT_SCALE := 1.6               # zvětšení proti skutečnosti (~9 mm), ať jsou vidět

var fauna: Fauna
var rng := RandomNumberGenerator.new()
var radius := 0.8
var height := 0.6
var trails: Array = []               # [PackedVector3Array bodů stezky (světové)]
var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _trail := PackedInt32Array()     # -1 = po kupě
var _s := PackedFloat32Array()       # poloha na stezce (m)
var _dir := PackedFloat32Array()     # +1 od kupy, −1 ke kupě
var _ang := PackedFloat32Array()     # po kupě: úhel a výška
var _h := PackedFloat32Array()
var _t := 0.0
var _bite_t := 0.0


func setup(f: Fauna, pos: Vector3, seed_: int) -> void:
	fauna = f
	rng.seed = seed_
	position = pos
	radius = rng.randf_range(0.55, 1.1)
	height = radius * rng.randf_range(0.6, 0.85)
	name = "Mraveniste_%d" % (seed_ % 10000)


func _ready() -> void:
	_build_mound()
	# stezky k nejbližším stromům (2–5)
	var near: Array = fauna.trees_near(global_position, 14.0, 30)
	near.sort_custom(func(a: Vector4, b: Vector4): return Vector2(a.x, a.z).distance_to(Vector2(global_position.x, global_position.z)) \
		< Vector2(b.x, b.z).distance_to(Vector2(global_position.x, global_position.z)))
	for i in mini(near.size(), rng.randi_range(2, 5)):
		var tr: Vector4 = near[i]
		var a := Vector3(global_position.x, 0, global_position.z)
		var b := Vector3(tr.x, 0, tr.z)
		var pts := PackedVector3Array()
		var n := int(a.distance_to(b) / 0.25) + 2
		var side := rng.randf_range(-1.0, 1.0)
		var perp := (b - a).normalized().cross(Vector3.UP)
		for k in n:
			var t := float(k) / (n - 1)
			var p := a.lerp(b, t) + perp * sin(t * PI) * side * 1.2 + perp * sin(t * 17.0 + side * 5.0) * 0.08
			p.y = fauna.terrain.height_at(p.x, p.z) + 0.005
			pts.append(p)
		# kousek po kmeni nahoru
		for k in 6:
			pts.append(Vector3(tr.x, tr.y + 0.15 + k * 0.3, tr.z) + perp * 0.12)
		trails.append(pts)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.mesh = _ant_mesh()
	_mm.instance_count = N_ANTS
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = _mm
	_mmi.top_level = true
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mmi)
	_mmi.global_transform = Transform3D.IDENTITY
	_mmi.visible = false
	_trail.resize(N_ANTS)
	_s.resize(N_ANTS)
	_dir.resize(N_ANTS)
	_ang.resize(N_ANTS)
	_h.resize(N_ANTS)
	for i in N_ANTS:
		var on_trail := not trails.is_empty() and i % 3 != 0
		_trail[i] = (i % trails.size()) if on_trail else -1
		_s[i] = rng.randf() * (_trail_len(_trail[i]) if on_trail else 1.0)
		_dir[i] = 1.0 if rng.randf() < 0.5 else -1.0
		_ang[i] = rng.randf() * TAU
		_h[i] = rng.randf()


func _trail_len(ti: int) -> float:
	if ti < 0:
		return 0.0
	return (trails[ti] as PackedVector3Array).size() * 0.25


## Kupa z jehličí: rotační těleso s nepravidelným povrchem, tmavší vrchol, vchody.
func _build_mound() -> void:
	var k := MeshKit.new()
	var prof := PackedVector2Array()
	var cols := PackedColorArray()
	var n := 9
	for i in n:
		var t := float(i) / (n - 1)
		var r := radius * cos(t * PI * 0.5) * (1.0 + 0.1 * sin(t * 5.0))
		prof.append(Vector2(maxf(r, 0.002), height * sin(t * PI * 0.5) - 0.08 * (1.0 - t)))
		cols.append(Color(0.34, 0.24, 0.14).lerp(Color(0.22, 0.14, 0.08), t))
	var y0 := fauna.terrain.height_at(global_position.x, global_position.z) - global_position.y
	k.lathe(prof, Transform3D(Basis(), Vector3(0, y0, 0)), Color(0.3, 0.2, 0.12), 20, 1.0, 1.0, cols, false, true)
	# drobné větvičky a jehličí navrchu
	for i in 40:
		var a := rng.randf() * TAU
		var rr := sqrt(rng.randf()) * radius * 0.9
		var t := rr / radius
		var y := height * sqrt(maxf(1.0 - t * t, 0.0)) + y0
		k.box(Vector3(cos(a) * rr, y, sin(a) * rr), Vector3(0.012, 0.012, rng.randf_range(0.06, 0.16)),
			Color(0.4, 0.3, 0.18).lerp(Color(0.18, 0.12, 0.07), rng.randf()), Vector3(rng.randf() * 0.6, rng.randf() * TAU, 0))
	var mi := MeshKit.mesh_instance(self, k.commit(QuadrupedModel.fur_material(1.0)), 160.0)
	mi.name = "Kupa"


func _ant_mesh() -> ArrayMesh:
	var k := MeshKit.new()
	var red := Color(0.35, 0.12, 0.05)
	var blk := Color(0.06, 0.04, 0.03)
	var s := 0.001 * ANT_SCALE
	k.sphere(Vector3(0, s * 1.2, -s * 2.6), s * 1.5, blk, Vector3(1, 0.9, 1.3), Vector3.ZERO, 6, 4)
	k.sphere(Vector3(0, s * 1.3, 0), s * 0.9, red, Vector3(1, 1, 1.8), Vector3.ZERO, 6, 4)
	k.sphere(Vector3(0, s * 1.3, s * 2.2), s * 0.9, red.darkened(0.2), Vector3.ONE, Vector3.ZERO, 6, 4)
	for side: float in [1.0, -1.0]:
		for j in 3:
			k.box(Vector3(side * s * 1.4, s * 0.6, (j - 1) * s * 1.1), Vector3(s * 2.4, s * 0.25, s * 0.25), blk, Vector3(0, 0, side * 0.5))
	return k.commit(QuadrupedModel.fur_material(1.0))


func _physics_process(delta: float) -> void:
	_t += delta
	var w = fauna.world
	var p: Player = w.nearest_player(global_position)
	var d := p.global_position.distance_to(global_position) if p else INF
	var weather: Weather = fauna.weather
	var active := weather == null or (weather.temp > 6.0 and weather.snow_cover < 0.1)
	_mmi.visible = d < 25.0 and active
	# mravenci v botách
	if p and active and d < radius + 0.15 and p.get("car") == null and p.get("horse") == null:
		_bite_t -= delta
		if _bite_t <= 0.0:
			_bite_t = 2.5
			p.body.hurt(0.4, "kousnutí mravenců")
			w.emit_game_event(p.id, "ant_bite", {})
	if not _mmi.visible:
		return
	var y0 := global_position.y
	for i in N_ANTS:
		var xf: Transform3D
		var ti := _trail[i]
		if ti >= 0:
			var pts: PackedVector3Array = trails[ti]
			var L := pts.size() * 0.25
			_s[i] += _dir[i] * ANT_SPEED * (0.8 + 0.4 * sin(i * 1.3 + _t * 0.3)) * delta
			if _s[i] >= L or _s[i] <= 0.0:
				_dir[i] = -_dir[i]
				_s[i] = clampf(_s[i], 0.0, L)
			var f := _s[i] / 0.25
			var k := clampi(int(f), 0, pts.size() - 2)
			var a := pts[k]
			var b := pts[k + 1]
			var pos := a.lerp(b, f - k)
			var fwd := (b - a).normalized() * _dir[i]
			var lat := fwd.cross(Vector3.UP).normalized() * sin(i * 7.1 + _t * 1.5) * 0.02
			# u kupy a na kmeni: lezou po povrchu
			var hd := Vector2(pos.x - global_position.x, pos.z - global_position.z).length()
			if hd < radius:
				var tt := hd / radius
				pos.y = maxf(pos.y, y0 + height * sqrt(maxf(1.0 - tt * tt, 0.0)))
			xf = _orient(pos + lat, fwd)
		else:
			_ang[i] += (sin(i * 3.7 + _t * 0.7) * 0.4) * delta
			_h[i] = clampf(_h[i] + sin(i * 2.3 + _t * 0.5) * 0.02 * delta, 0.05, 0.98)
			var rr := radius * _h[i]
			var tt := _h[i]
			var pos := global_position + Vector3(cos(_ang[i]) * rr, 0, sin(_ang[i]) * rr)
			pos.y = y0 + height * sqrt(maxf(1.0 - tt * tt, 0.0)) + 0.003
			var fwd := Vector3(-sin(_ang[i]), 0, cos(_ang[i]))
			xf = _orient(pos, fwd)
		_mm.set_instance_transform(i, xf)


func _orient(pos: Vector3, fwd: Vector3) -> Transform3D:
	if fwd.length() < 0.01:
		return Transform3D(Basis(), pos)
	var f := fwd.normalized()
	var up := Vector3.UP if absf(f.y) < 0.95 else Vector3.BACK
	return Transform3D(Basis.looking_at(-f, up), pos)
