## M8.18 Drobný život u hráče (klient, přepínač `soundscape`): netopýři za soumraku nad vodou a v obci (u lamp),
## světlušky v červnu v teplé noci na okraji lesa a v nivě, motýli nad kvetoucí loukou ve dne (bělásek, babočky,
## žluťásek, modrásek), komáří roj nad vodou za soumraku, jepice nad potokem v květnu.
## Každý druh = jedna MultiMesh (1 draw call); pohyb kolem kotvy počítá shader `shaders/small_life.gdshader`
## (CPU zapisuje transformace jen při změně kotev, nejvýš 1× za `TICK` s – žádná práce za snímek kromě prolnutí).
## Kotvy = buňky zvukové krajiny (`Soundscape.cell_feat`: voda, okraj lesa, niva, louka, obec) do `LIFE_R` m od hráče.
## Podmínky podle fenologie a počasí: měsíc / den v roce, výška slunce (`Clock.sun_elevation`), teplota
## (`World.micro.temp_at`), déšť a vítr (zruší je), kvetení louky (`Phenology.bees_bloom` / `Seasons.bloom`).
## Viděné zblízka (`SEEN_R`) → deník pozorování (`NatureLog.observe`: netopyr, svetluska, motyl, jepice).
class_name SmallLife
extends Node3D

const K_BAT := 0
const K_FIREFLY := 1
const K_BUTTERFLY := 2
const K_MOSQUITO := 3
const K_MAYFLY := 4
const LOG_KEYS := ["netopyr", "svetluska", "motyl", "", "jepice"]
const BUTTERFLY_COLORS := [Color(0.95, 0.95, 0.9), Color(0.62, 0.16, 0.1), Color(0.95, 0.85, 0.3),
	Color(0.45, 0.6, 0.95), Color(0.85, 0.45, 0.15)]

## M8.D: laditelné (F3 → Zvěř/Hmyz a drobný život).
static var TICK := 1.0                  # s – výběr kotev a podmínek
static var LIFE_R := 70.0               # m – kotvy do této vzdálenosti od hráče
static var FADE_S := 2.0                # s – prolnutí objevení / zmizení
static var SEEN_R := 25.0               # m – „viděno“ do deníku
static var LUX_FULL := 20000.0          # lx – plný jas barev (motýli); za soumraku tmavší
static var LIGHT_MIN := 0.06
# netopýři
static var BAT_ANCHORS := 3
static var BAT_PER := 2
static var BAT_SUN_MAX := -1.5          # ° – létají, když je slunce pod touto výškou
static var BAT_T_MIN := 8.0             # °C
static var BAT_WIND_MAX := 7.0          # m/s
static var BAT_RAIN_MAX := 0.15
static var BAT_ROAM := 9.0              # m
static var BAT_SPEED := 1.0
static var BAT_HEIGHT := 4.0            # m nad zemí
static var BAT_VILLAGE_W := 0.6         # váha obce (lampy) proti vodě
# světlušky
static var FF_ANCHORS := 3
static var FF_PER := 25
static var FF_DOY_A := 158.0            # den v roce – od (začátek června)
static var FF_DOY_B := 196.0            # … do (polovina července)
static var FF_SUN_MAX := -6.0           # ° – jen za tmy
static var FF_T_MIN := 14.0
static var FF_WIND_MAX := 3.0
static var FF_RAIN_MAX := 0.03
static var FF_ROAM := 6.0
static var FF_HEIGHT := 0.6
static var FF_GLOW := 4.0
static var FF_BLINK_HZ := 0.35
# motýli
static var BF_ANCHORS := 4
static var BF_PER := 3
static var BF_MONTH_A := 4
static var BF_MONTH_B := 9
static var BF_SUN_MIN := 15.0           # ° – jen za dne
static var BF_T_MIN := 13.0
static var BF_WIND_MAX := 5.0
static var BF_RAIN_MAX := 0.03
static var BF_BLOOM_MIN := 0.15
static var BF_ROAM := 4.0
static var BF_HEIGHT := 0.5
static var BF_FLAP_HZ := 7.0
# komáři
static var MQ_ANCHORS := 2
static var MQ_PER := 40
static var MQ_MONTH_A := 5
static var MQ_MONTH_B := 9
static var MQ_SUN_MIN := -8.0           # ° – soumrak / svítání: slunce mezi
static var MQ_SUN_MAX := 8.0
static var MQ_T_MIN := 10.0
static var MQ_WIND_MAX := 2.5
static var MQ_RAIN_MAX := 0.1
static var MQ_ROAM := 0.8
static var MQ_HEIGHT := 1.8
# jepice
static var MF_ANCHORS := 2
static var MF_PER := 15
static var MF_DOY_A := 125.0            # začátek května
static var MF_DOY_B := 165.0            # polovina června
static var MF_HOUR_A := 10.0
static var MF_HOUR_B := 21.0
static var MF_T_MIN := 12.0
static var MF_WIND_MAX := 4.0
static var MF_RAIN_MAX := 0.05
static var MF_ROAM := 1.5
static var MF_HEIGHT := 0.8

var world: World
var client: Node
var soundscape: Soundscape
var _mm: Array[MultiMesh] = []
var _mmi: Array[MultiMeshInstance3D] = []
var _mat: Array[ShaderMaterial] = []
var _amount := PackedFloat32Array()
var _target := PackedFloat32Array()
var _sent := PackedFloat32Array()
var _sig := PackedInt64Array()          # podpis kotev (změna → přepis transformací)
var _anchors: Array[PackedVector3Array] = []
var _t := 0.0
var _light := 1.0


func setup(w: World, c: Node, s: Soundscape) -> void:
	world = w
	client = c
	soundscape = s
	name = "DrobnyZivot"
	var shader: Shader = load("res://shaders/small_life.gdshader")
	var counts := [BAT_ANCHORS * BAT_PER, FF_ANCHORS * FF_PER, BF_ANCHORS * BF_PER, MQ_ANCHORS * MQ_PER, MF_ANCHORS * MF_PER]
	var meshes: Array[Mesh] = [_wing_mesh(0.32, 0.1), _dot_mesh(), _wing_mesh(0.08, 0.05), _dot_mesh(), _dot_mesh()]
	for k in 5:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = meshes[k]
		mm.instance_count = maxi(int(counts[k]), 1)
		mm.visible_instance_count = 0
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("kind", k)
		mat.set_shader_parameter("amount", 0.0)
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 16.0
		mi.visibility_range_end = LIFE_R + 40.0
		mi.top_level = true
		mi.visible = false
		add_child(mi)
		_mm.append(mm)
		_mmi.append(mi)
		_mat.append(mat)
		_anchors.append(PackedVector3Array())
	_amount.resize(5)
	_amount.fill(0.0)
	_target.resize(5)
	_target.fill(0.0)
	_sent.resize(5)
	_sent.fill(-1.0)
	_sig.resize(5)
	_sig.fill(-1)
	_apply_params()
	if DevTune.hub() != null:
		DevTune.hub().changed.connect(_on_tune)


func _on_tune(id: String, _v: Variant) -> void:
	if id.begins_with("life."):
		_apply_params()


## Parametry shaderu z laditelných hodnot (při startu a změně v F3).
func _apply_params() -> void:
	var p := [[BAT_ROAM, BAT_SPEED, 11.0, 0.9, 0.0], [FF_ROAM, 1.0, 0.0, 0.0, 0.035], [BF_ROAM, 1.0, BF_FLAP_HZ, 1.2, 0.0],
		[MQ_ROAM, 1.0, 0.0, 0.0, 0.012], [MF_ROAM, 1.0, 0.0, 0.0, 0.02]]
	for k in _mat.size():
		var m := _mat[k]
		m.set_shader_parameter("roam", p[k][0])
		m.set_shader_parameter("speed", p[k][1])
		m.set_shader_parameter("flap_hz", p[k][2])
		m.set_shader_parameter("flap_amp", p[k][3])
		m.set_shader_parameter("dot_size", p[k][4])
		m.set_shader_parameter("glow", FF_GLOW)
		m.set_shader_parameter("blink_hz", FF_BLINK_HZ)


## Křídlatý model: tělíčko a dvě křídla (|x| > 0 mávají v shaderu), +Z dopředu.
static func _wing_mesh(span: float, ln: float) -> ArrayMesh:
	var h := span * 0.5
	var v := PackedVector3Array([
		Vector3(0, 0, ln * 0.6), Vector3(-h, 0, ln * 0.1), Vector3(0, 0, -ln * 0.5),
		Vector3(0, 0, ln * 0.6), Vector3(0, 0, -ln * 0.5), Vector3(h, 0, ln * 0.1),
		Vector3(0, 0, -ln * 0.2), Vector3(-h * 0.7, 0, -ln * 0.6), Vector3(0, 0, -ln * 0.5),
		Vector3(0, 0, -ln * 0.2), Vector3(0, 0, -ln * 0.5), Vector3(h * 0.7, 0, -ln * 0.6),
	])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am


static func _dot_mesh() -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	return q


func _process(delta: float) -> void:
	if world == null:
		return
	var __t0 := Tests.prof_t0()
	_t -= delta
	if _t <= 0.0:
		_t = TICK
		_tick()
	var a := clampf(delta / maxf(FADE_S, 0.01), 0.0, 1.0)
	for k in 5:
		if _amount[k] == _target[k] and _sent[k] == _amount[k]:
			continue
		_amount[k] = move_toward(_amount[k], _target[k], a)
		if absf(_amount[k] - _sent[k]) > 0.02 or _amount[k] == _target[k]:
			_sent[k] = _amount[k]
			_mat[k].set_shader_parameter("amount", _amount[k])
		_mmi[k].visible = _amount[k] > 0.001
	Tests.prof_add("small_life", __t0)


func _player() -> Player:
	return client.get("player") if client != null else null


## 1× za TICK: podmínky druhů a kotvy v okolí hráče.
func _tick() -> void:
	var p := _player()
	var c: Clock = world.clock
	if p == null or c == null or soundscape == null:
		return
	var on := world.realism_on("soundscape") and p.inside == ""
	var pos := p.global_position
	var elev := c.sun_elevation()
	var month := c.month()
	var doy := c.day_of_year()
	var hour := c.hour()
	var T: float = world.micro.temp_at(pos) if world.micro != null else (world.weather.temp if world.weather != null else 12.0)
	var rain: float = world.weather.rain if world.weather != null else 0.0
	var wind: float = world.weather.wind if world.weather != null else 2.0
	var wf: WindField = world.wind_field
	if wf != null and wf.enabled():
		wind = wf.speed()
	var cond := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])
	if on:
		if month >= 4 and month <= 10 and elev < BAT_SUN_MAX and T >= BAT_T_MIN and wind < BAT_WIND_MAX and rain < BAT_RAIN_MAX:
			cond[K_BAT] = 1.0
		if doy >= FF_DOY_A and doy <= FF_DOY_B and elev < FF_SUN_MAX and T >= FF_T_MIN and wind < FF_WIND_MAX and rain < FF_RAIN_MAX:
			cond[K_FIREFLY] = 1.0
		if month >= BF_MONTH_A and month <= BF_MONTH_B and elev > BF_SUN_MIN and T >= BF_T_MIN and wind < BF_WIND_MAX \
				and rain < BF_RAIN_MAX and _bloom(pos, doy) >= BF_BLOOM_MIN:
			cond[K_BUTTERFLY] = 1.0
		if month >= MQ_MONTH_A and month <= MQ_MONTH_B and elev > MQ_SUN_MIN and elev < MQ_SUN_MAX and T >= MQ_T_MIN \
				and wind < MQ_WIND_MAX and rain < MQ_RAIN_MAX:
			cond[K_MOSQUITO] = 1.0
		if doy >= MF_DOY_A and doy <= MF_DOY_B and hour >= MF_HOUR_A and hour <= MF_HOUR_B and T >= MF_T_MIN \
				and wind < MF_WIND_MAX and rain < MF_RAIN_MAX:
			cond[K_MAYFLY] = 1.0
	_light = LIGHT_MIN
	var atm: Atmosphere = client.get("atmosphere") if client != null else null
	if atm != null:
		_light = clampf((atm.sun_illuminance_lux() + atm.sky_illuminance_lux()) / LUX_FULL, LIGHT_MIN, 1.0)
	for k in 5:
		if cond[k] <= 0.0:
			_target[k] = 0.0
			continue
		var n := _pick_anchors(k, pos)
		_target[k] = 1.0 if n > 0 else 0.0
		if k != K_FIREFLY:
			_mat[k].set_shader_parameter("light_k", _light)
		if n > 0 and _amount[k] > 0.5 and LOG_KEYS[k] != "" and world.nature_log != null and p.car == null:
			for a in _anchors[k]:
				if a.distance_to(pos) < SEEN_R:
					world.nature_log.observe(p, LOG_KEYS[k])
					break


func _bloom(pos: Vector3, doy: float) -> float:
	var ph: Phenology = world.phenology
	if ph != null:
		return ph.bees_bloom(pos)
	return Seasons.bloom(doy)


## Váha buňky pro druh (rysy Soundscape: 0 les, 1 okraj, 2 louka, 3 pole, 4 obec, 5 voda, 6 nádrž, 7 niva).
func _cell_w(k: int, f: PackedFloat32Array) -> float:
	match k:
		K_BAT:
			return maxf(f[5], f[4] * BAT_VILLAGE_W)
		K_FIREFLY:
			return maxf(f[1], f[7])
		K_BUTTERFLY:
			return maxf(f[2], f[4] * 0.4) * (1.0 - f[0])
		K_MOSQUITO:
			return maxf(f[6], f[5] * 0.7)
		K_MAYFLY:
			return f[5] * (1.0 - f[6] * 0.6)
	return 0.0


## Vybere nejlepší buňky v okolí (váha × stabilní hash) a při změně přepíše instance MultiMesh.
func _pick_anchors(k: int, pos: Vector3) -> int:
	var cell := Soundscape.CELL
	var r := int(ceil(LIFE_R / cell))
	var c0 := Vector2i(floori(pos.x / cell), floori(pos.z / cell))
	var want: int = [BAT_ANCHORS, FF_ANCHORS, BF_ANCHORS, MQ_ANCHORS, MF_ANCHORS][k]
	var best_w := PackedFloat32Array()
	var best_c: Array[Vector2i] = []
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			var cc := c0 + Vector2i(dx, dz)
			var f := soundscape.cell_feat(cc)
			if f.is_empty():
				continue
			var w := _cell_w(k, f)
			if w < 0.3:
				continue
			w *= 0.6 + 0.4 * Soundscape._hash01(cc.x, cc.y, 500 + k)
			var at := best_w.size()
			while at > 0 and best_w[at - 1] < w:
				at -= 1
			if at >= want:
				continue
			best_w.insert(at, w)
			best_c.insert(at, cc)
			if best_w.size() > want:
				best_w.resize(want)
				best_c.resize(want)
	var sig := 0
	for cc in best_c:
		sig = sig * 31 + cc.x * 7919 + cc.y
	if sig == _sig[k] and not best_c.is_empty():
		return best_c.size()
	_sig[k] = sig
	_write(k, best_c)
	return best_c.size()


func _write(k: int, cells: Array[Vector2i]) -> void:
	var mm := _mm[k]
	var per: int = [BAT_PER, FF_PER, BF_PER, MQ_PER, MF_PER][k]
	var base_h: float = [BAT_HEIGHT, FF_HEIGHT, BF_HEIGHT, MQ_HEIGHT, MF_HEIGHT][k]
	var cell := Soundscape.CELL
	var anchors := PackedVector3Array()
	var n := 0
	for cc in cells:
		var f := soundscape.cell_feat(cc)
		var ax := (cc.x + 0.5) * cell + (Soundscape._hash01(cc.x, cc.y, 600 + k) - 0.5) * cell * 0.6
		var az := (cc.y + 0.5) * cell + (Soundscape._hash01(cc.x, cc.y, 700 + k) - 0.5) * cell * 0.6
		var ay := world.terrain.height_at(ax, az) if world.terrain != null else f[Soundscape.F_Y]
		var anchor := Vector3(ax, ay, az)
		anchors.append(anchor)
		for j in per:
			if n >= mm.instance_count:
				break
			var h1 := Soundscape._hash01(cc.x * 13 + j, cc.y, 800 + k)
			var h2 := Soundscape._hash01(cc.x, cc.y * 17 + j, 900 + k)
			var spread := 0.0 if k == K_MOSQUITO else (8.0 if k == K_FIREFLY else 2.0)
			var o := Vector3((h1 - 0.5) * spread, 0.0, (h2 - 0.5) * spread)
			mm.set_instance_transform(n, Transform3D(Basis(), anchor + o))
			var col := Color(0.08, 0.06, 0.05)
			if k == K_BUTTERFLY:
				col = BUTTERFLY_COLORS[int(h1 * 97.0) % BUTTERFLY_COLORS.size()]
			elif k == K_MOSQUITO:
				col = Color(0.12, 0.12, 0.12)
			elif k == K_MAYFLY:
				col = Color(0.75, 0.7, 0.55)
			mm.set_instance_color(n, col)
			mm.set_instance_custom_data(n, Color(h1, h2 * 0.8, base_h * (0.7 + 0.6 * h2), fposmod(h1 * 7.3 + h2, 1.0)))
			n += 1
	mm.visible_instance_count = n
	_anchors[k] = anchors
