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

## M8.5: expozice (adaptace oka) – cíl EV100 → vyhlazená `exposure_ev`, pak na tonemapping.
## `EXPOSURE_MID_EV` je kalibrována na jasné poledne (SkyModel), aby se tam `tonemap_exposure`
## chovalo jako dřív (≈1,0); v soumraku a v noci násobič roste, ať je scéna čitelná (Purkyně).
const EXPOSURE_MID_EV := 15.5
const EXPOSURE_DARK_GAIN := 0.07
const EXPOSURE_MAX_MULT := 3.2
const ADAPT_RATE_LIGHT := 10.0       # EV/s – adaptace do světla rychlá (~2 s na typický skok)
const ADAPT_RATE_DARK := 1.0         # EV/s – adaptace do tmy pomalá (~20 s)
const INDOOR_REF_LUX := 150.0        # hrubý odhad osvětlení uvnitř budovy (umělé světlo) – jen pro skok expozice při vstupu/výstupu

var clock: Clock
var weather: Weather
var env: Environment
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var terrain: Terrain               # M6.2: pro výšku kamery nad terénem (dohled ve výšce); může být null
var north_deg := 78.37
var indoor := false                  # hráč je v interiéru (M1.4): tlumené světlo prostředí, bez padajících srážek, tlumený déšť a vítr
var _indoor_s := 0.0
var light_pollution := 0.0           # M5.12: cílový světelný smog 0..1 (StreetLights.pollution podle kamery); obloha ho plynule přebírá
var _lp := 0.0
var realism: Dictionary = {}         # M8.5: odkaz na `GameSettings.realism` (nastaví `LocalClient`); chybějící klíč "sky" = zapnuto (fallback)
var exposure_ev := EXPOSURE_MID_EV   # M8.5 API: aktuální vyhlazená EV100 scény (SkyModel) – čtou další kroky (8.9, 8.12, 8.16, 8.18)


## M8.5 – zjednodušený fyzikální model oblohy (Rayleigh + Mie rozptyl + ozon, à la Hillaire 2020 /
## Preetham, viz 00_PRINCIPY kap. 8 „Obloha a světlo“). Žádná plná předpočítaná LUT textura (časový
## rozpočet M8, kap. 6 – jen pár vyhodnocení za snímek, ne za pixel); transmitance a jas se počítají
## analytickými vzorci přímo tady. Čisté statické funkce – volatelné odkudkoli i bez uzlu kamery
## (`Atmosphere.SkyModel.sun_illuminance_lux(...)`), takže je můžou číst i budoucí serverové kroky M8
## (8.9 mikroklima, 8.12 plodiny, 8.16 tělo, 8.18 zvuk), ne jen tento klientský vzhled.
class SkyModel:
	const SUN_LUX_ZENITH := 100000.0   # jasné nebe, slunce v zenitu
	const SKY_LUX_CLEAR := 18000.0     # difuzní nebe jasného dne při slunci vysoko
	const SKY_LUX_OVERCAST := 10000.0  # celé zatažené nebe (jen difuzní)
	const SKY_LUX_TWILIGHT := 3.4      # konec občanského soumraku (elevace −6°)
	const SKY_LUX_NIGHT := 0.0005      # konec nautického soumraku (elevace −12°) – jen zbytek difuze
	const MOON_LUX_FULL := 0.25        # úplněk vysoko na obloze
	const STARLIGHT_LUX := 0.001       # jasná bezměsíčná noc, jen hvězdy
	const EV_REF_LUX := 2.5            # ISO: EV100 = log2(lux / 2,5)

	## Kasten & Young 1989 – vzdušná hmota podle zenitového úhlu (zjednodušeně, bez tlakové korekce).
	static func air_mass(elev_deg: float) -> float:
		var z := clampf(90.0 - elev_deg, 0.0, 94.0)
		var cz := cos(deg_to_rad(z))
		return 1.0 / (cz + 0.50572 * pow(maxf(96.07995 - z, 0.001), -1.6364))

	## Rayleigh + ozon (optická hloubka ~0,10 jasná obloha) + Mie podle oparu / mlhy (0..1 → +0,5).
	static func _extinction(am: float, haze: float) -> float:
		var tau := 0.10 + 0.5 * clampf(haze, 0.0, 1.0)
		return exp(-tau * am)

	## Barva slunce a jeho přímého světla podle vzdušné hmoty – Rayleigh ~ 1/λ⁴, nízko nad obzorem
	## ubývá modré a zelené složky rychleji než červené → slunce zčervená (fyzikální, ne namíchané).
	static func sun_tint(elev_deg: float, haze: float) -> Color:
		if elev_deg <= -5.0:
			return Color(1.0, 0.55, 0.3)
		var am := air_mass(maxf(elev_deg, 0.2))
		var tau := 0.10 + 0.5 * clampf(haze, 0.0, 1.0)
		var r := exp(-tau * am * 0.55)
		var g := exp(-tau * am * 0.9)
		var b := exp(-tau * am * 1.6)
		var c := Color(r, g, b)
		return c / maxf(c.g, 0.001)   # normalizovat na zelenou, ať je slunce v poledne bílé, ne přitmavené

	## Přímá sluneční osvětlenost vodorovné plochy (lux) – 00_PRINCIPY kap. 8: jasné poledne ~100 000 lx.
	static func sun_illuminance_lux(elev_deg: float, cloud_cover: float, haze: float) -> float:
		if elev_deg <= -5.0:
			return 0.0
		var am := air_mass(maxf(elev_deg, 0.2))
		var trans := _extinction(am, haze)
		var geo := clampf(sin(deg_to_rad(elev_deg)), 0.0, 1.0)
		var direct := SUN_LUX_ZENITH * trans * geo
		direct *= lerpf(1.0, 0.08, smoothstep(0.2, 0.9, clampf(cloud_cover, 0.0, 1.0)))
		return direct

	## Difuzní osvětlenost oblohy (bez přímého slunce) – ve dne podle výšky slunce a zatažení
	## (zataženo ~10 000 lx), v soumraku a v noci interpolace mezi kalibračními body kap. 8
	## (občanský soumrak ~3 lx) až po hvězdnou noc.
	static func sky_illuminance_lux(elev_deg: float, cloud_cover: float, haze: float) -> float:
		var cc := clampf(cloud_cover, 0.0, 1.0)
		if elev_deg >= 0.0:
			var clear := SKY_LUX_CLEAR * clampf(sin(deg_to_rad(elev_deg)), 0.05, 1.0)
			var overcast := SKY_LUX_OVERCAST * clampf(sin(deg_to_rad(elev_deg)) * 0.6 + 0.4, 0.1, 1.0)
			return lerpf(clear, overcast, smoothstep(0.3, 0.9, cc)) * (1.0 - haze * 0.3)
		if elev_deg >= -6.0:
			var t0 := SKY_LUX_CLEAR * 0.05        # jas u obzoru v okamžiku západu (elev = 0)
			var t := clampf((-elev_deg) / 6.0, 0.0, 1.0)
			return lerpf(t0, SKY_LUX_TWILIGHT, t)
		if elev_deg >= -12.0:
			var t := clampf((-6.0 - elev_deg) / 6.0, 0.0, 1.0)
			return SKY_LUX_TWILIGHT * pow(SKY_LUX_NIGHT / SKY_LUX_TWILIGHT, t)
		return SKY_LUX_NIGHT

	## Měsíční osvětlenost (lux) – úplněk vysoko na obloze ~0,25 lx (kap. 8).
	static func moon_illuminance_lux(phase01: float, moon_elev_deg: float) -> float:
		var up := smoothstep(-2.0, 5.0, moon_elev_deg)
		return MOON_LUX_FULL * clampf(phase01, 0.0, 1.0) * up

	## Celková osvětlenost scény (slunce + obloha + měsíc + hvězdy + světelný smog obce) – vstup pro expozici.
	static func total_illuminance_lux(elev_deg: float, cloud_cover: float, haze: float, moon_phase01: float,
			moon_elev_deg: float, light_pollution01: float) -> float:
		var lux := sun_illuminance_lux(elev_deg, cloud_cover, haze) + sky_illuminance_lux(elev_deg, cloud_cover, haze)
		lux += moon_illuminance_lux(moon_phase01, moon_elev_deg) + STARLIGHT_LUX
		lux += clampf(light_pollution01, 0.0, 1.0) * 0.05
		return lux

	## EV100 = log2(lux / 2,5) (ISO 12232) – vstup pro expozici / adaptaci oka.
	static func ev100_from_lux(lux: float) -> float:
		return log(maxf(lux, 0.0001) / EV_REF_LUX) / log(2.0)

	## Sluneční elevace v pásu (−6°, 0°] = občanský soumrak (nejkratší telefonní budka civilního soumraku).
	static func is_civil_twilight(elev_deg: float) -> bool:
		return elev_deg <= 0.0 and elev_deg > -6.0

	## Hrubý odhad globálního horizontálního záření (W/m²) z osvětlenosti přes světelnou účinnost
	## slunečního záření (~110 lm/W, Michalsky 1988) – pro M8.12 (fotosyntéza) stačí řádová shoda.
	static func global_horizontal_irradiance_wm2(elev_deg: float, cloud_cover: float, haze: float) -> float:
		if elev_deg <= 0.0:
			return 0.0
		var lux := sun_illuminance_lux(elev_deg, cloud_cover, haze) + sky_illuminance_lux(elev_deg, cloud_cover, haze)
		return lux / 110.0

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


# ------------------------------------------------------------------ M8.5 API (fyzikální světlo)

func _sky_on() -> bool:
	return bool(realism.get("sky", true))


func _haze_now() -> float:
	var fog := weather.fog if weather else 0.0
	var rain := weather.rain if weather else 0.0
	return clampf(fog * 0.9 + rain * 0.35, 0.0, 1.0)


## Přímá sluneční osvětlenost vodorovné plochy právě teď (lux) – vždy fyzikální (SkyModel), nezávisle
## na přepínači "sky" (ten řídí jen vzhled oblohy a adaptaci expozice, ne tuhle hodnotu pro ostatní kroky).
func sun_illuminance_lux() -> float:
	if clock == null:
		return SkyModel.SUN_LUX_ZENITH
	return SkyModel.sun_illuminance_lux(clock.sun_elevation(), weather.cloud if weather else 0.3, _haze_now())


## Difuzní osvětlenost oblohy právě teď (lux).
func sky_illuminance_lux() -> float:
	if clock == null:
		return SkyModel.SKY_LUX_CLEAR
	return SkyModel.sky_illuminance_lux(clock.sun_elevation(), weather.cloud if weather else 0.3, _haze_now())


## Globální horizontální záření (W/m²) – pro M8.12 (fotosyntéza) a M8.16 (tepelná bilance těla).
func global_horizontal_irradiance_wm2() -> float:
	if clock == null:
		return 0.0
	return SkyModel.global_horizontal_irradiance_wm2(clock.sun_elevation(), weather.cloud if weather else 0.3, _haze_now())


## Je právě občanský soumrak (slunce −6°..0°)? Pro M8.18 (ptáci / cvrčci / rozsvícení lamp).
func is_civil_twilight() -> bool:
	if clock == null:
		return false
	return SkyModel.is_civil_twilight(clock.sun_elevation())


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
	var haze := _haze_now()
	var moon_elev := rad_to_deg(asin(clampf(md.y, -1.0, 1.0)))
	var sky_on := _sky_on()

	# --- M8.5: fyzikální osvětlenost (lux) a adaptace expozice – počítá se vždy (levné, čisté funkce),
	# ať ji budoucí kroky M8 (8.9, 8.12, 8.16, 8.18) můžou číst i když je vizuální přepínač "sky" vypnutý;
	# jen vzhled oblohy / tonemapping / Purkyňův posun níž se mění podle `sky_on`.
	var sun_lux := SkyModel.sun_illuminance_lux(elev, cloud, haze)
	var sky_lux := SkyModel.sky_illuminance_lux(elev, cloud, haze)
	var moon_lux := SkyModel.moon_illuminance_lux(clock.moon_illumination(), moon_elev)
	var total_lux := sun_lux + sky_lux + moon_lux + SkyModel.STARLIGHT_LUX + _lp * 0.05
	var target_ev := lerpf(SkyModel.ev100_from_lux(total_lux), SkyModel.ev100_from_lux(INDOOR_REF_LUX), _indoor_s)
	var adapt_rate := ADAPT_RATE_LIGHT if target_ev > exposure_ev else ADAPT_RATE_DARK
	exposure_ev = move_toward(exposure_ev, target_ev, delta * adapt_rate)

	var sun_up := smoothstep(-2.0, 3.0, elev)
	var moon_up := smoothstep(-2.0, 4.0, moon_elev)
	if sky_on:
		sun.light_color = SkyModel.sun_tint(elev, haze)
		sun.light_energy = SUN_ENERGY * clampf(sun_lux / SkyModel.SUN_LUX_ZENITH, 0.0, 1.0) * sun_up
		moon.light_energy = MOON_ENERGY * clampf(moon_lux / SkyModel.MOON_LUX_FULL, 0.0, 1.0) * moon_up * (1.0 - day) * (1.0 - overcast * 0.85)
	else:
		sun.light_color = Color(1.0, 0.96, 0.9).lerp(Color(1.0, 0.58, 0.32), warm)
		sun.light_energy = SUN_ENERGY * sun_up * (1.0 - overcast * 0.78) * (1.0 - fog * 0.5)
		moon.light_energy = MOON_ENERGY * moon_up * (0.25 + 0.75 * clock.moon_illumination()) * (1.0 - day) * (1.0 - overcast * 0.85)
	sun.visible = sun.light_energy > 0.01
	sun.shadow_opacity = 1.0 - overcast * 0.85
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
	sky_mat.set_shader_parameter("haze", haze)
	sky_mat.set_shader_parameter("sky_on", sky_on)   # M8.5: Pás Venuše při soumraku jen v nové obloze
	_lp = move_toward(_lp, light_pollution, delta * 0.4)
	sky_mat.set_shader_parameter("light_pollution", _lp)
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
	if sky_on:
		# M8.5: expozice z vyhlazené EV100 (SkyModel) – kalibrováno, ať je jasné poledne ≈ jako dřív (1,0),
		# v soumraku a v noci násobič roste (oko se roztáhne), ať zůstane scéna čitelná (Purkyně).
		var exp_mult := 1.0 + EXPOSURE_DARK_GAIN * maxf(EXPOSURE_MID_EV - exposure_ev, 0.0)
		env.tonemap_exposure = clampf(exp_mult, 1.0, EXPOSURE_MAX_MULT) * (1.0 + overcast * 0.08)
		env.adjustment_enabled = true
		env.adjustment_brightness = 1.0
		env.adjustment_contrast = 1.0
		# Purkyňův posun: pod cca 1 lx ztrácí oko barvocit (tyčinkové vidění) – postupná desaturace do ~8 EV tmy
		var purkinje := clampf(-exposure_ev / 8.0, 0.0, 1.0)
		env.adjustment_saturation = lerpf(1.0, 0.35, purkinje)
	else:
		env.tonemap_exposure = lerpf(1.7, 1.0, day) * (1.0 + overcast * 0.12)
		env.adjustment_enabled = false
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
