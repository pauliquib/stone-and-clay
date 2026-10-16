## Hejno špačků – murmurace (M8.10): na podzim (září–listopad) za soumraku se nad polem u hráče stovky špačků
## vlní v jednom oblaku, občas se rozvlní před „sokolem“, a když slunce zapadne, sestoupí na nocoviště a zmizí.
##
## Podle čeho: boidy (Reynolds 1987) s **topologickými sousedy** – každý pták sleduje ~7 sousedů, ne všechny
## v dosahu (Ballerini et al. 2008, PNAS): oddělení, zarovnání, soudržnost + přitažlivost ke středu nad polem
## a k výšce oblaku, útěk před dravcem.
##
## Simulace je jen vzhled (klient): neukládá se, ve `World` nic nemění. Vzniká a zaniká přes `tick()` (volá Fauna
## jednou za ENCOUNTER_T): měsíc v MONTHS, večer s výškou slunce v SUN_EL, bez deště, vítr do WIND_MAX, přepínač
## realismu „animal_gait“ a jen ve 2 ze 3 večerů (podle data – deterministicky).
##
## Výkon: nejvýš MAX_BIRDS ptáků v jedné MultiMesh (1 draw call); boidy se přepočítávají v plátcích (celé hejno
## za SLICES snímků), sousedé přes prostorovou mřížku v Packed polích (žádné alokace za běhu); mezi přepočty
## polohu dopočítá vertex shader `shaders/murmuration.gdshader` z rychlosti v INSTANCE_CUSTOM. Daleko od hráče
## (> SIM_R) se nesimuluje ani nekreslí.
class_name Murmuration
extends Node3D

const MONTHS := [9, 10, 11]
const SUN_EL := Vector2(-4.0, 6.0)   # ° – okno výšky slunce (večer); pod spodní mezí hejno zapadne na nocoviště
const CHANCE_DAYS := 3               # (jd·7919) % CHANCE_DAYS != 0 → ten večer hejno je (2 ze 3 večerů)
const MAX_BIRDS := 400
const MIN_BIRDS := 180
const SPAWN_DIST := Vector2(150.0, 380.0)   # m od hráče
const SIM_R := 700.0                 # m – dál od hráče se nesimuluje ani nekreslí
const GONE_R := 1200.0               # m – dál od hráče hejno zmizí
const WIND_MAX := 9.0                # m/s
const ALT := Vector2(25.0, 70.0)     # m nad terénem – výška oblaku (střed se v tom rozmezí vlní)
const WANDER_R := 60.0               # m – jak daleko od bodu nad polem střed oblaku bloudí
const SPEED := Vector2(9.0, 14.0)    # m/s – rychlost špačka
const NEIGH := 7                     # topologičtí sousedé
const CELL := 5.0                    # m – buňka mřížky sousedů (x, z)
const HASH := 1024                   # počet buněk hashe (mocnina 2)
const SLICES := 4                    # za kolik snímků se přepočte celé hejno
const SEP_R := 1.6                   # m – blíž se ptáci odpuzují
const W_SEP := 6.0
const W_ALI := 1.4
const W_COH := 0.9
const W_HOME := 0.025                # přitažlivost ke středu oblaku (vodorovně, 1/s² na m)
const W_ALT := 0.5                   # přitažlivost k výšce oblaku (1/s² na m)
const HAWK_EVERY := Vector2(6.0, 14.0)   # s – jak často proletí dravec (vlna v hejnu)
const HAWK_R := 14.0                 # m – dosah strachu z dravce
const W_HAWK := 40.0
const ROOST_S := 25.0                # s – sestup na nocoviště, pak hejno zmizí
const SIZE := 1.2                    # měřítko modelu (rozpětí ~0,4 m × tohle)
const FLAP_HZ := 11.0

var fauna: Fauna
var center := Vector3.ZERO           # bod nad polem, kolem kterého oblak krouží (y = terén)
var rng := RandomNumberGenerator.new()

var _n := 0
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _last := PackedFloat32Array()    # čas posledního přepočtu ptáka
var _head := PackedInt32Array()      # hash buňky → první pták (−1 = prázdná)
var _next := PackedInt32Array()
var _buf := PackedFloat32Array()     # MultiMesh: 12 transformace + 4 vlastní data na ptáka
var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _mat: ShaderMaterial
var _time := 0.0
var _slice := 0
var _ground := 0.0
var _roost := -1.0                   # s od začátku sestupu (−1 = ještě ne)
var _hawk_t := 8.0
var _hawk_p := Vector3.INF
var _hawk_v := Vector3.ZERO
var _hawk_left := 0.0
var _aabb_t := 0.0
var _near := true


## Volá Fauna jednou za ENCOUNTER_T: založí hejno, když jsou podmínky, a vrátí ho (nebo `current`, nebo null).
static func tick(f: Fauna, current: Murmuration) -> Murmuration:
	if current != null and is_instance_valid(current):
		return current
	if not FlightModel.on or f.world == null or f.clock == null or f.weather == null:
		return null
	var c: Clock = f.clock
	if not (c.month() in MONTHS) or c.hour() < 12.0:
		return null
	var el := c.sun_elevation()
	if el < SUN_EL.x + 1.0 or el > SUN_EL.y:
		return null
	if f.weather.rain > 0.05 or f.weather.wind > WIND_MAX:
		return null
	if (c.jd() * 7919) % CHANCE_DAYS == 0:
		return null
	var p: Player = null
	for pl in f.world.players.values():
		if pl.inside == "":
			p = pl
			break
	if p == null:
		return null
	var r := RandomNumberGenerator.new()
	r.seed = c.jd() * 31 + 7
	for i in 10:
		var a := r.randf() * TAU
		var d := r.randf_range(SPAWN_DIST.x, SPAWN_DIST.y)
		var x := p.global_position.x + cos(a) * d
		var z := p.global_position.z + sin(a) * d
		if f.score("field", x, z) > 0.35:
			var m := Murmuration.new()
			m.fauna = f
			m.center = Vector3(x, f.terrain.height_at(x, z), z)
			m.rng.seed = r.randi()
			m.name = "Spacci"
			f.root_birds.add_child(m)
			return m
	return null


func _ready() -> void:
	_n = rng.randi_range(MIN_BIRDS, MAX_BIRDS)
	_pos.resize(_n)
	_vel.resize(_n)
	_last.resize(_n)
	_next.resize(_n)
	_head.resize(HASH)
	_buf.resize(_n * 16)
	_ground = center.y
	var alt := (ALT.x + ALT.y) * 0.5
	var dir0 := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)).normalized()
	for i in _n:
		var o := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.4, 0.4), rng.randf_range(-1.0, 1.0)) * 25.0
		_pos[i] = center + Vector3(0.0, alt, 0.0) + o
		_vel[i] = (dir0 + Vector3(rng.randf_range(-0.3, 0.3), 0.0, rng.randf_range(-0.3, 0.3))).normalized() * SPEED.x
		_last[i] = 0.0
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true
	_mm.mesh = _bird_mesh()
	_mm.instance_count = _n
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/murmuration.gdshader")
	_mat.set_shader_parameter("flap_hz", FLAP_HZ)
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = _mm
	_mmi.material_override = _mat
	_mmi.top_level = true
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mmi)
	_mmi.global_transform = Transform3D.IDENTITY
	for i in _n:
		_write(i)
	_mm.buffer = _buf
	_update_aabb()


## Model špačka: tělo a dvě trojúhelníková křídla (+Z dopředu), barva v shaderu.
func _bird_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var nose := Vector3(0.0, 0.0, 0.1)
	var tail := Vector3(0.0, 0.0, -0.1)
	var rf := Vector3(0.0, 0.0, 0.04)
	var rb := Vector3(0.0, 0.0, -0.05)
	for s: float in [1.0, -1.0]:
		var tip := Vector3(0.2 * s, 0.0, -0.04)
		st.add_vertex(rf)
		st.add_vertex(tip)
		st.add_vertex(rb)
		var side := Vector3(0.03 * s, 0.0, 0.0)
		st.add_vertex(nose)
		st.add_vertex(side)
		st.add_vertex(tail)
	return st.commit()


func _physics_process(delta: float) -> void:
	var __t0 := Tests.prof_t0()
	_step(delta)
	Tests.prof_add("murmuration", __t0)


func _step(delta: float) -> void:
	if fauna == null or fauna.world == null:
		return
	var d: float = fauna.world.nearest_player_dist(center)
	if d > GONE_R or not FlightModel.on:
		queue_free()
		return
	var near := d < SIM_R
	if near != _near:
		_near = near
		_mmi.visible = near
	if not near:
		return
	_time += delta
	# konec okna (slunce pod obzorem) → sestup na nocoviště
	if _roost < 0.0 and fauna.clock.sun_elevation() < SUN_EL.x:
		_roost = 0.0
	if _roost >= 0.0:
		_roost += delta
		if _roost > ROOST_S:
			queue_free()
			return
	# dravec: jednou za čas proletí oblakem → vlna
	_hawk_t -= delta
	if _hawk_t <= 0.0 and _roost < 0.0:
		_hawk_t = rng.randf_range(HAWK_EVERY.x, HAWK_EVERY.y)
		var a := rng.randf() * TAU
		var c := _cloud_center()
		_hawk_p = c + Vector3(cos(a), 0.0, sin(a)) * 60.0
		_hawk_v = (c - _hawk_p).normalized() * 22.0
		_hawk_left = 5.0
	if _hawk_left > 0.0:
		_hawk_left -= delta
		_hawk_p += _hawk_v * delta
		if _hawk_left <= 0.0:
			_hawk_p = Vector3.INF
	# plátek: na začátku cyklu se přestaví mřížka sousedů
	if _slice == 0:
		_build_grid()
	var from := _slice * _n / SLICES
	var to := (_slice + 1) * _n / SLICES
	var c2 := _cloud_center()
	for i in range(from, to):
		_boid(i, c2)
	_slice = (_slice + 1) % SLICES
	_mm.buffer = _buf
	_mat.set_shader_parameter("flock_time", _time)
	_aabb_t -= delta
	if _aabb_t <= 0.0:
		_aabb_t = 1.0
		_update_aabb()


## Střed oblaku: bloudí kolem bodu nad polem a vlní se ve výšce; při sestupu klesá k zemi.
func _cloud_center() -> Vector3:
	var alt := lerpf(ALT.x, ALT.y, 0.5 + 0.5 * sin(_time * 0.11))
	if _roost >= 0.0:
		alt = lerpf(alt, 1.0, clampf(_roost / (ROOST_S * 0.7), 0.0, 1.0))
	return center + Vector3(sin(_time * 0.07) * WANDER_R, alt, cos(_time * 0.053) * WANDER_R)


func _hash(x: float, z: float) -> int:
	var cx := floori(x / CELL)
	var cz := floori(z / CELL)
	return ((cx * 73856093) ^ (cz * 19349663)) & (HASH - 1)


func _build_grid() -> void:
	_head.fill(-1)
	for i in _n:
		var p := _pos[i] + _vel[i] * (_time - _last[i])
		var h := _hash(p.x, p.z)
		_next[i] = _head[h]
		_head[h] = i


## Jeden pták: sousedé z 3×3 buněk (nejvýš NEIGH), síly hejna, integrace, zápis do bufferu MultiMesh.
func _boid(i: int, cc: Vector3) -> void:
	var dt := clampf(_time - _last[i], 0.0, 0.25)
	var p := _pos[i] + _vel[i] * dt
	var v := _vel[i]
	var sep := Vector3.ZERO
	var ali := Vector3.ZERO
	var coh := Vector3.ZERO
	var cnt := 0
	var cx := floori(p.x / CELL)
	var cz := floori(p.z / CELL)
	for ox in range(-1, 2):
		for oz in range(-1, 2):
			if cnt >= NEIGH:
				break
			var j := _head[(((cx + ox) * 73856093) ^ ((cz + oz) * 19349663)) & (HASH - 1)]
			while j >= 0 and cnt < NEIGH:
				if j != i:
					var q := _pos[j] + _vel[j] * (_time - _last[j])
					var dd := p - q
					var l2 := dd.length_squared()
					if l2 < 100.0:
						cnt += 1
						ali += _vel[j]
						coh += q
						if l2 < SEP_R * SEP_R and l2 > 0.0001:
							sep += dd / l2
				j = _next[j]
	var acc := Vector3.ZERO
	if cnt > 0:
		acc += sep * W_SEP + (ali / float(cnt) - v) * W_ALI + (coh / float(cnt) - p) * W_COH
	# střed oblaku (vodorovně) a výška
	var hc := Vector3(cc.x - p.x, 0.0, cc.z - p.z)
	acc += hc * W_HOME
	acc.y += (cc.y - p.y) * W_ALT
	if _hawk_p != Vector3.INF:
		var dh := p - _hawk_p
		var l := dh.length()
		if l < HAWK_R and l > 0.01:
			acc += dh / l * W_HAWK * (1.0 - l / HAWK_R)
	v += acc * dt
	var spd := v.length()
	var lo := SPEED.x * (0.4 if _roost >= 0.0 else 1.0)
	if spd > SPEED.y:
		v *= SPEED.y / spd
	elif spd < lo and spd > 0.001:
		v *= lo / spd
	_pos[i] = p
	_vel[i] = v
	_last[i] = _time
	_write(i)


## Transformace (natočení podle rychlosti) a vlastní data (rychlost, čas) ptáka `i` do bufferu MultiMesh.
## Pták u země při sestupu na nocoviště se schová (nulové měřítko).
func _write(i: int) -> void:
	var p := _pos[i]
	var v := _vel[i]
	var z := v.normalized() if v.length_squared() > 0.0001 else Vector3.FORWARD
	var x := Vector3.UP.cross(z)
	if x.length_squared() < 0.0001:
		x = Vector3.RIGHT
	x = x.normalized()
	var y := z.cross(x)
	var s := SIZE
	if _roost >= 0.0 and p.y < _ground + 3.0:
		s = 0.0
	var o := i * 16
	_buf[o] = x.x * s
	_buf[o + 1] = y.x * s
	_buf[o + 2] = z.x * s
	_buf[o + 3] = p.x
	_buf[o + 4] = x.y * s
	_buf[o + 5] = y.y * s
	_buf[o + 6] = z.y * s
	_buf[o + 7] = p.y
	_buf[o + 8] = x.z * s
	_buf[o + 9] = y.z * s
	_buf[o + 10] = z.z * s
	_buf[o + 11] = p.z
	_buf[o + 12] = v.x
	_buf[o + 13] = v.y
	_buf[o + 14] = v.z
	_buf[o + 15] = _time


func _update_aabb() -> void:
	var c := _cloud_center()
	_mmi.custom_aabb = AABB(c - Vector3(160.0, 120.0, 160.0), Vector3(320.0, 240.0, 320.0))
