## Atmosféra u klienta – jak počasí a roční období vypadají a zní (simulaci drží World: Clock + Weather):
## - slunce a měsíc podle skutečné polohy (Clock.sun_enu / moon_enu), barva a síla světla, stíny
## - obloha (shaders/sky.gdshader): mraky podle oblačnosti, červánky, hvězdy, měsíc s fází, opar
## - mlha a zatažená obloha tlumí světlo, blesky rozsvítí oblohu a se zpožděním zahřmí
## - déšť a sníh: částice kolem kamery, nepadají pod střechy (výšková kolize částic sleduje kameru)
## - zvuk deště a větru
## - globální parametry shaderů (project.godot → shader_globals): snow_cover, wetness, grass_green,
##   foliage, autumn, wind_strength → terén, stromy, střechy a silnice
class_name Atmosphere
extends Node3D

## Prahy a síly – ladění vzhledu
const SUN_ENERGY := 1.3
const MOON_ENERGY := 0.16
const FOG_BASE := 0.00022
const FOG_MIST := 0.012              # hustota v husté mlze
const FOG_RAIN := 0.0022
const RAIN_DROPS := 12000
const SNOW_FLAKES := 7000

var clock: Clock
var weather: Weather
var env: Environment
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var terrain: Terrain               # M6.2: pro výšku kamery nad terénem (dohled ve výšce); může být null
var north_deg := 78.37
var indoor := false                  # hráč je v interiéru (M1.4): tlumené světlo prostředí, bez padajících srážek, tlumený déšť a vítr
var _indoor_s := 0.0

var sky_mat: ShaderMaterial
var _rain: GPUParticles3D
var _snow: GPUParticles3D
var _rain_mat: ParticleProcessMaterial
var _snow_mat: ParticleProcessMaterial
var _collider: GPUParticlesCollisionHeightField3D
var _rain_snd: AudioStreamPlayer
var _wind_snd: AudioStreamPlayer
var _thunder: Array[AudioStreamPlayer] = []
var _flash := 0.0
var _flash_seq: Array = []           # [čas, síla] – záblesky jednoho blesku
var _cloud_off := Vector2.ZERO
var _t := 0.0


func setup(c: Clock, w: Weather, e: Environment, s: DirectionalLight3D, m: DirectionalLight3D, north: float,
		t: Terrain = null) -> void:
	clock = c
	weather = w
	env = e
	sun = s
	moon = m
	terrain = t
	north_deg = north
	_build_sky()
	_build_precip()
	_build_sounds()
	if weather:
		weather.lightning.connect(_on_lightning)
	update(0.0)


func _build_sky() -> void:
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.012
	noise.fractal_octaves = 5
	noise.fractal_gain = 0.55
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.generate_mipmaps = true
	tex.noise = noise
	sky_mat.set_shader_parameter("cloud_noise", tex)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.sky = sky


func _build_precip() -> void:
	# déšť – protáhlé průsvitné čárky
	_rain = GPUParticles3D.new()
	_rain.name = "Dest"
	_rain.amount = RAIN_DROPS
	_rain.lifetime = 1.6
	_rain.preprocess = 1.6
	_rain.local_coords = false
	_rain.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 50, 60))
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain_mat = ParticleProcessMaterial.new()
	_rain_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_rain_mat.emission_box_extents = Vector3(22, 1, 22)
	_rain_mat.direction = Vector3(0, -1, 0)
	_rain_mat.spread = 3.0
	_rain_mat.initial_velocity_min = 9.0
	_rain_mat.initial_velocity_max = 11.0
	_rain_mat.gravity = Vector3(0, -2.0, 0)
	_rain_mat.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	_rain.process_material = _rain_mat
	var q := QuadMesh.new()
	q.size = Vector2(0.012, 0.55)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.75, 0.8, 0.88, 0.28)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.billboard_keep_scale = true
	m.disable_receive_shadows = true
	q.material = m
	_rain.draw_pass_1 = q
	_rain.emitting = false
	add_child(_rain)
	# sníh – vločky pomalu padají a víří
	_snow = GPUParticles3D.new()
	_snow.name = "Snih"
	_snow.amount = SNOW_FLAKES
	_snow.lifetime = 9.0
	_snow.preprocess = 9.0
	_snow.local_coords = false
	_snow.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 50, 60))
	_snow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_snow_mat = ParticleProcessMaterial.new()
	_snow_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_snow_mat.emission_box_extents = Vector3(24, 5, 24)
	_snow_mat.direction = Vector3(0, -1, 0)
	_snow_mat.spread = 20.0
	_snow_mat.initial_velocity_min = 0.8
	_snow_mat.initial_velocity_max = 1.4
	_snow_mat.gravity = Vector3(0, -0.4, 0)
	_snow_mat.turbulence_enabled = true
	_snow_mat.turbulence_noise_strength = 1.2
	_snow_mat.turbulence_noise_scale = 4.0
	_snow_mat.turbulence_influence_min = 0.05
	_snow_mat.turbulence_influence_max = 0.12
	_snow_mat.scale_min = 0.6
	_snow_mat.scale_max = 1.3
	_snow_mat.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	_snow.process_material = _snow_mat
	var sq := QuadMesh.new()
	sq.size = Vector2(0.035, 0.035)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_color = Color(0.95, 0.96, 1.0, 0.85)
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sm.billboard_keep_scale = true
	sq.material = sm
	_snow.draw_pass_1 = sq
	_snow.emitting = false
	add_child(_snow)
	# střechy, stromy, auto – částice pod nimi zmizí (výšková mapa sleduje kameru)
	_collider = GPUParticlesCollisionHeightField3D.new()
	_collider.size = Vector3(48, 40, 48)
	_collider.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_256
	_collider.follow_camera_enabled = true
	_collider.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	add_child(_collider)


func _build_sounds() -> void:
	_rain_snd = AudioStreamPlayer.new()
	_rain_snd.volume_db = -80.0
	add_child(_rain_snd)
	_wind_snd = AudioStreamPlayer.new()
	_wind_snd.volume_db = -80.0
	add_child(_wind_snd)
	for i in 2:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_thunder.append(p)


# ------------------------------------------------------------------ každý snímek

func update(delta: float) -> void:
	_t += delta
	_indoor_s = move_toward(_indoor_s, 1.0 if indoor else 0.0, delta * 3.0)
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var day := clock.daylight()
	var cloud := weather.cloud if weather else 0.3
	var rain := weather.rain if weather else 0.0
	var fog := weather.fog if weather else 0.0
	var wind := weather.wind if weather else 2.0
	var dark := clampf(rain * 1.4 + (weather.storm if weather else 0.0) * 0.5, 0.0, 1.0)

	# --- slunce a měsíc
	var sd := Clock.enu_to_world(clock.sun_enu(), north_deg)
	var md := Clock.enu_to_world(clock.moon_enu(), north_deg)
	_aim(sun, sd)
	_aim(moon, md)
	var elev := clock.sun_elevation()
	var warm := 1.0 - clampf(elev / 22.0, 0.0, 1.0)
	var overcast := smoothstep(0.55, 1.0, cloud)
	sun.light_color = Color(1.0, 0.96, 0.9).lerp(Color(1.0, 0.58, 0.32), warm)
	var sun_up := smoothstep(-2.0, 3.0, elev)
	sun.light_energy = SUN_ENERGY * sun_up * (1.0 - overcast * 0.78) * (1.0 - fog * 0.5)
	sun.visible = sun.light_energy > 0.01
	sun.shadow_opacity = 1.0 - overcast * 0.85
	var moon_up := smoothstep(-2.0, 4.0, rad_to_deg(asin(clampf(md.y, -1.0, 1.0))))
	moon.light_energy = MOON_ENERGY * moon_up * (0.25 + 0.75 * clock.moon_illumination()) * (1.0 - day) * (1.0 - overcast * 0.85)
	moon.visible = moon.light_energy > 0.005 and not sun.visible

	# --- obloha
	# mraky táhnou po větru (ve výšce fouká víc, minimálně pomalý posun i za bezvětří)
	var wv0 := weather.wind_vector() if weather else Vector3(-2.0, 0, 0.5)
	_cloud_off += (Vector2(wv0.x, wv0.z) * 0.00035 + Vector2(-0.0004, 0.0001)) * delta
	sky_mat.set_shader_parameter("sun_dir", sd)
	sky_mat.set_shader_parameter("moon_dir", md)
	sky_mat.set_shader_parameter("moon_light", clock.moon_illumination())
	sky_mat.set_shader_parameter("cloud_cover", cloud)
	sky_mat.set_shader_parameter("cloud_dark", dark)
	sky_mat.set_shader_parameter("cloud_offset", _cloud_off)
	sky_mat.set_shader_parameter("haze", clampf(fog * 0.9 + rain * 0.35, 0.0, 1.0))
	_update_flash(delta)
	sky_mat.set_shader_parameter("flash", _flash)

	# --- světlo prostředí a mlha
	env.ambient_light_energy = lerpf(0.3, 1.0, day) * (1.0 - dark * 0.25) * lerpf(1.0, 0.4, _indoor_s) + _flash * 1.5 * (1.0 - _indoor_s)
	env.ambient_light_sky_contribution = 1.0
	var fog_col := Color(0.72, 0.8, 0.9).lerp(Color(0.7, 0.72, 0.75), overcast)
	fog_col = fog_col.lerp(Color(0.04, 0.05, 0.08), 1.0 - day).lerp(Color(0.9, 0.6, 0.45), warm * day * 0.45 * (1.0 - overcast))
	env.fog_light_color = fog_col
	# M6.2: dohled z výšky – nad ~150 m AGL se mlha ředí a horizont se táhne, ať je okolí
	# mapy (Surroundings) čitelné; v mlze zůstane dohled omezený (fog drží svoji část)
	var high := 0.0
	if cam != null:
		var ground := terrain.height_at(cam.global_position.x, cam.global_position.z) if terrain else 0.0
		high = smoothstep(150.0, 500.0, cam.global_position.y - ground)
	env.fog_density = (FOG_BASE + FOG_MIST * fog * fog + FOG_RAIN * rain) * (1.0 - 0.7 * high)
	env.fog_sky_affect = clampf(fog * 0.8 + rain * 0.3 + high * 0.25, 0.0, 0.9)
	env.fog_aerial_perspective = lerpf(0.5, 0.85, high) * (1.0 - fog)
	env.tonemap_exposure = lerpf(1.7, 1.0, day) * (1.0 + overcast * 0.12)
	MapLoader.set_tree_far_mult(lerpf(1.0, 2.6, high))      # M6.2: ve výšce vidět stromy dál

	# --- srážky kolem kamery
	var snowing := weather != null and weather.is_snowing()
	var raining := weather != null and weather.is_raining()
	if cam:
		var cp := cam.global_position
		var wv := weather.wind_vector() if weather else Vector3.ZERO
		_rain.global_position = cp + Vector3(0, 12, 0) - wv * 0.9 + cam.global_transform.basis.z * -8.0
		_snow.global_position = cp + Vector3(0, 7, 0) - wv * 2.0 + cam.global_transform.basis.z * -6.0
		_rain_mat.direction = (Vector3(0, -10, 0) + wv).normalized()
		_snow_mat.gravity = Vector3(wv.x * 0.25, -0.4, wv.z * 0.25)
	_rain.emitting = raining and _indoor_s < 0.5
	_snow.emitting = snowing and _indoor_s < 0.5
	_rain.amount_ratio = clampf(rain * 1.2, 0.05, 1.0)
	_snow.amount_ratio = clampf(rain * 1.5, 0.08, 1.0)

	# --- zvuky
	var muffle := -16.0 * _indoor_s          # uvnitř budovy je déšť i vítr slyšet jen tlumeně
	_loop(_rain_snd, "rain", (rain if raining else 0.0), -30.0 + muffle, 0.0 + muffle)
	_loop(_wind_snd, "wind", clampf((wind - 3.0) / 12.0, 0.0, 1.0), -32.0 + muffle, -6.0 + muffle)

	# --- globální parametry shaderů (terén, stromy, střechy)
	var doy := clock.day_of_year()
	var rs := RenderingServer
	rs.global_shader_parameter_set("snow_cover", weather.snow_cover if weather else 0.0)
	rs.global_shader_parameter_set("wetness", weather.wetness if weather else 0.0)
	rs.global_shader_parameter_set("grass_green", Seasons.green(doy) * (1.0 - (weather.snow_cover if weather else 0.0) * 0.3))
	rs.global_shader_parameter_set("foliage", Seasons.foliage(doy))
	rs.global_shader_parameter_set("autumn", Seasons.autumn(doy))
	rs.global_shader_parameter_set("wind_strength", clampf(wind / 16.0, 0.0, 1.0))


## Natočí směrové světlo tak, aby svítilo ze směru `to_light` (jednotkový vektor ke zdroji).
func _aim(l: DirectionalLight3D, to_light: Vector3) -> void:
	var dir := -to_light.normalized()
	var up := Vector3.UP if absf(dir.y) < 0.98 else Vector3.FORWARD
	l.global_transform = Transform3D(Basis.looking_at(dir, up), l.global_position)


func _loop(p: AudioStreamPlayer, name_: String, amount: float, db_min: float, db_max: float) -> void:
	if amount <= 0.01:
		if p.playing:
			p.volume_db = move_toward(p.volume_db, -60.0, 1.5)
			if p.volume_db <= -59.0:
				p.stop()
		return
	if not p.playing:
		p.stream = NatureSfx.get_stream(name_)
		p.volume_db = -60.0
		p.play()
	var want := lerpf(db_min, db_max, sqrt(amount))
	p.volume_db = move_toward(p.volume_db, want, 1.0)


# ------------------------------------------------------------------ blesky

func _on_lightning(pos: Vector3) -> void:
	var cam := get_viewport().get_camera_3d()
	var dist := cam.global_position.distance_to(pos) if cam else 1500.0
	var power := clampf(1.3 - dist / 4000.0, 0.25, 1.0)
	# 2–4 záblesky těsně po sobě (zpětné výboje)
	_flash_seq.clear()
	var t := 0.0
	for i in randi_range(2, 4):
		_flash_seq.append([t, power * randf_range(0.6, 1.0)])
		t += randf_range(0.06, 0.18)
	# hrom se zpožděním podle rychlosti zvuku, vzdálený je tišší a hlubší
	var delay := dist / 343.0
	get_tree().create_timer(delay).timeout.connect(_play_thunder.bind(dist))


func _play_thunder(dist: float) -> void:
	for p in _thunder:
		if not p.playing:
			p.stream = NatureSfx.get_stream("thunder")
			p.pitch_scale = clampf(1.15 - dist / 6000.0, 0.6, 1.2) * randf_range(0.9, 1.05)
			p.volume_db = clampf(2.0 - dist / 180.0, -26.0, 2.0)
			p.play()
			return


func _update_flash(delta: float) -> void:
	_flash = move_toward(_flash, 0.0, delta * 9.0)
	for i in range(_flash_seq.size() - 1, -1, -1):
		_flash_seq[i][0] -= delta
		if _flash_seq[i][0] <= 0.0:
			_flash = maxf(_flash, _flash_seq[i][1])
			_flash_seq.remove_at(i)
