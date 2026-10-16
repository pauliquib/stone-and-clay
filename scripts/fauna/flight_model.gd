## Let ptáků (M8.10, přepínač realismu „animal_gait“ → `FlightModel.on`): zjednodušená aerodynamika pro `Bird`.
##
## Podle čeho (Pennycuick 2008 „Modelling the Flying Bird“, zjednodušeně):
## - vztlak L = ½·ρ·v²·S·C_L → pádová rychlost v_pád = √(2·m·g / (ρ·S·C_Lmax)); pod ní × STALL_MARGIN pták musí mávat,
## - odpor D ∝ v² nastavený tak, aby ustálené klouzání při cestovní rychlosti mělo klouzavost druhu L/D
##   (D(v_cest) = g / (L/D)); bez mávání pták klesá klouzavým úhlem atan(1 / (L/D)),
## - mávání = tah (strop podle druhu, při vzletu × TAKEOFF_THRUST na TAKEOFF_S), stoupání stojí energii,
## - styl letu druhu: „flap_glide“ (vrána, vlaštovka – úseky mávání a klouzání), „bound“ (kos – vlnovitý let se
##   složenými křídly mezi mávnutími), „soar“ (káně – plachtí, mává jen při stoupání bez termiky / pod pádovou rychlostí),
## - let vůči vzduchu: posun vůči zemi = vzdušná rychlost + vítr (`WindField.wind_at`, M8.4); kurz se opravuje na boční
##   vítr, proti větru je postup pomalejší; svislá složka = orografie (WindField) + termika (`Thermals.lift_at`, M6.3)
##   + stoupání, které dodá hejno (slabá termika mimo bubliny `Thermals`, `lift_bias`),
## - přistání: v FLARE vzdálenosti křídla nahoru (klapka, brzdění FLARE_DECEL) a přímý sestup k místu dosednutí,
##   v silném větru tělem proti větru.
## Výkon: vítr, termika a terén se v bodě ptáka zjišťují jen AIR_SAMPLE_S (4× za s), krok letu nealokuje.
class_name FlightModel
extends RefCounted

const RHO := 1.2                     # kg/m³ hustota vzduchu
const G := 9.8
const AIR_SAMPLE_S := 0.25           # s – jak často se zjišťuje vítr, termika a terén pod ptákem
const WIND_CAP := 0.75               # vítr se do posunu počítá nejvýš do tohoto podílu cestovní rychlosti
const TAKEOFF_S := 0.9               # s silných mávnutí po vzletu
const TAKEOFF_THRUST := 1.8          # násobek tahu při vzletu
const FLARE_DECEL := 5.0             # m/s² – brzdění vztyčenými křídly při přistání
const FLARE_MIN := 4.0               # m – přistávací manévr začíná nejpozději tak blízko
const LAND_SPEED_K := 0.4            # rychlost dosednutí = v_pád × tohle
const LAND_REACH := 0.4              # m – na tolik od místa přistání pták dosedne (hejno ho posadí)
const STALL_MARGIN := 1.15           # pod v_pád × tohle musí mávat
const SOAR_CEIL_FADE := 30.0         # m – pod stropem kroužení (`soar_ceil`) termika slábne k nule
const GROUND_CLEAR := 3.0            # m – při letu bez přistání se drží aspoň tak vysoko nad terénem
const INTO_WIND_MIN := 2.0           # m/s – od tohoto větru se pták při přistání natáčí proti němu
const SOAR_FLAP_LIFT := 0.05         # m/s – plachtící pták mává, jen když ho nenese ani tolik…
const SOAR_FLAP_AGL := 40.0          # m – …a je níž nad terénem než tohle (výš raději klouže a hledá stoupání)

## Druhy: hmotnost (kg), plocha křídel (m²), C_Lmax, klouzavost L/D, tah mávání (m/s²), styl,
## délky úseků mávání a klouzání (s, od–do). Rozměry odhadem podle literatury (ověřit).
const SPECIES := {
	"vrana": {"mass": 0.55, "area": 0.15, "cl_max": 1.4, "ld": 9.0, "thrust": 7.0, "style": "flap_glide",
		"flap": [2.5, 5.0], "glide": [1.0, 2.5]},
	"kos": {"mass": 0.1, "area": 0.032, "cl_max": 1.3, "ld": 6.0, "thrust": 9.0, "style": "bound",
		"flap": [0.35, 0.6], "glide": [0.15, 0.3]},
	"vlastovka": {"mass": 0.019, "area": 0.012, "cl_max": 1.3, "ld": 8.0, "thrust": 9.0, "style": "flap_glide",
		"flap": [0.6, 1.4], "glide": [0.5, 1.2]},
	"kane": {"mass": 0.9, "area": 0.28, "cl_max": 1.6, "ld": 14.0, "thrust": 5.0, "style": "soar",
		"flap": [1.5, 3.0], "glide": [4.0, 8.0]},
}

static var on := true

var style := "flap_glide"
var v_stall := 5.0                   # m/s pádová rychlost
var glide_ang := 0.1                 # rad klouzavý úhel
var cruise := 10.0
var max_speed := 16.0
var bank_max := 0.8
var climb_max := 0.45
var thrust := 7.0
var drag_k := 0.01                   # D = drag_k · v²
var flapping := true                 # výstup pro animaci
var takeoff := 0.0                   # s zbývá silných mávnutí po vzletu
var flare := 0.0                     # 0..1 přistávací klapka (animace)
var air := Vector3.ZERO              # vítr v bodě ptáka (m/s)
var lift := 0.0                      # termika v bodě ptáka (m/s)
var lift_bias := 0.0                 # stoupání dodané hejnem (m/s)
var soar_ceil := INF                 # m n. m. – strop kroužení (nad ním termika ptáka už nenese)
var land_goal := Vector3.INF         # kam pták dosedne (nastavuje hejno při letu na přistání)

var _flap_r := Vector2(2.0, 4.0)
var _glide_r := Vector2(1.0, 2.0)
var _gliding := false
var _phase_t := 0.0
var _air_t := 0.0
var _gy := -INF                      # terén pod ptákem (při posledním vzorku)
var _gy_ahead := -INF                # terén ~1 s letu před ptákem
var _rng := RandomNumberGenerator.new()


func _init(id: String, bird_spec: Dictionary, seed_: int) -> void:
	var p: Dictionary = SPECIES.get(id, SPECIES["vrana"])
	style = String(p["style"])
	var m: float = p["mass"]
	var s: float = p["area"]
	var cl: float = p["cl_max"]
	var ld: float = p["ld"]
	v_stall = sqrt(2.0 * m * G / (RHO * s * cl))
	glide_ang = atan(1.0 / ld)
	cruise = float(bird_spec.get("cruise", 10.0))
	max_speed = float(bird_spec.get("max_speed", cruise * 1.5))
	bank_max = float(bird_spec.get("bank", 0.8))
	climb_max = float(bird_spec.get("climb", 0.45))
	thrust = float(p["thrust"])
	drag_k = G / ld / (cruise * cruise)
	var fr: Array = p["flap"]
	var gr: Array = p["glide"]
	_flap_r = Vector2(float(fr[0]), float(fr[1]))
	_glide_r = Vector2(float(gr[0]), float(gr[1]))
	_rng.seed = seed_ ^ 0x5f1a
	_phase_t = _rng.randf_range(_flap_r.x, _flap_r.y)
	_air_t = _rng.randf() * AIR_SAMPLE_S


## Začátek vzletu (pták se právě odlepil od země / větve).
func start_takeoff() -> void:
	takeoff = TAKEOFF_S
	_gliding = false
	_phase_t = _rng.randf_range(_flap_r.x, _flap_r.y)
	flare = 0.0


## Klesavost při klouzání rychlostí v (m/s): v · sin(klouzavý úhel), pod pádovou rychlostí rychle roste.
func sink_at(v: float) -> float:
	var slow := maxf(v_stall * 1.3 - v, 0.0) / maxf(v_stall, 0.1)
	return v * sin(glide_ang) * (1.0 + slow * 2.0)


## Vítr, termika a terén v bodě ptáka (4× za s).
func _sample_air(b: Bird, pos: Vector3) -> void:
	var v := maxf(b.speed, 2.0)
	_gy = b.terrain.height_at(pos.x, pos.z) if b.terrain else 0.0
	_gy_ahead = b.terrain.height_at(pos.x + sin(b.yaw) * v, pos.z + cos(b.yaw) * v) if b.terrain else 0.0
	air = Vector3.ZERO
	lift = 0.0
	var w: World = b.world
	if w == null:
		return
	if w.wind_field != null:
		air = w.wind_field.wind_at(pos, pos.y - _gy)
		var hz := Vector2(air.x, air.z)
		var cap := cruise * WIND_CAP
		if hz.length() > cap:
			hz = hz.normalized() * cap
			air.x = hz.x
			air.z = hz.y
	if style == "soar" and w.thermals != null:
		lift = w.thermals.lift_at(pos)


## Krok letu k `b.target` (nebo k `land_goal` při přistání). Vrací vzdálenost k cíli.
func step(b: Bird, delta: float, want_speed: float) -> float:
	var pos := b.global_position
	_air_t -= delta
	if _air_t <= 0.0 or _gy == -INF:
		_air_t = AIR_SAMPLE_S
		_sample_air(b, pos)
	takeoff = maxf(takeoff - delta, 0.0)
	# přistání: v dosahu klapky brzdí a klesá přímo k místu dosednutí
	if b.land_on != "" and land_goal != Vector3.INF:
		var dl := pos.distance_to(land_goal)
		var fd := maxf(b.speed * b.speed / (2.0 * FLARE_DECEL) + 2.0, FLARE_MIN)
		if dl < fd or (flare > 0.05 and dl < fd * 1.6):
			return _flare_step(b, delta, pos, dl)
	flare = move_toward(flare, 0.0, delta * 3.0)
	var goal := b.target
	var dist := pos.distance_to(goal)
	var to := goal - pos
	if dist > 15.0:
		to += b.boid_bias
	var hd := Vector2(to.x, to.z).length()
	# kurz s opravou na boční vítr (vzdušná rychlost míří tak, aby dráha vůči zemi vedla k cíli)
	var v := maxf(b.speed, 2.0)
	var dx := to.x / maxf(hd, 0.01)
	var dz := to.z / maxf(hd, 0.01)
	var along := air.x * dx + air.z * dz
	var cx := air.x - dx * along
	var cz := air.z - dz * along
	var fwd := sqrt(maxf(v * v - (cx * cx + cz * cz), 0.0))
	var want_yaw := atan2(dx * fwd - cx, dz * fwd - cz)
	var diff := wrapf(want_yaw - b.yaw, -PI, PI)
	var max_rate := G * tan(bank_max) / v
	var rate := clampf(diff * 2.5, -max_rate, max_rate)
	b.yaw = wrapf(b.yaw + rate * delta, -PI, PI)
	b.bank = lerpf(b.bank, atan(rate * v / G), 1.0 - exp(-delta * 6.0))
	var climb := clampf(atan2(to.y, maxf(hd, 0.5)), -climb_max * 1.4, climb_max)
	if takeoff > 0.0:
		climb = maxf(climb, climb_max * 0.8)
	# drž se nad terénem (a nad korunami)
	if b.land_on == "" and pos.y < maxf(_gy, _gy_ahead) + GROUND_CLEAR:
		climb = maxf(climb, 0.35)
	# termika (s útlumem pod stropem kroužení) + orografie
	var up := lift + (lift_bias if b.state == "soar" else 0.0)
	if soar_ceil != INF:
		up *= clampf((soar_ceil - pos.y) / SOAR_CEIL_FADE, 0.0, 1.0)
	up += air.y
	# mávat, nebo klouzat?
	var ws := minf(want_speed, max_speed)
	var must := b.speed < v_stall * STALL_MARGIN or takeoff > 0.0
	match style:
		"soar":
			# plachtí; mává jen pod pádovou rychlostí, nebo když má nízko nad zemí stoupat a nic ho nenese
			flapping = must or (climb > 0.05 and up < SOAR_FLAP_LIFT and pos.y - _gy < SOAR_FLAP_AGL) \
				or b.speed < ws * 0.7
		_:
			_phase_t -= delta
			if _phase_t <= 0.0:
				_gliding = not _gliding
				_phase_t = _rng.randf_range(_glide_r.x, _glide_r.y) if _gliding else _rng.randf_range(_flap_r.x, _flap_r.y)
			flapping = must or not _gliding or climb > 0.08 or b.speed < ws * 0.85
	# sklon dráhy: mávání = kam chce, klouzání nejvýš klouzavým úhlem (stoupá jen vzduch)
	var pitch_t := climb if flapping else minf(climb, -glide_ang)
	b.pitch = lerpf(b.pitch, pitch_t, 1.0 - exp(-delta * 3.0))
	# rychlost: tah − odpor − složka tíhy
	var drag := drag_k * b.speed * b.speed
	var t := 0.0
	if flapping:
		var tmax := thrust * (TAKEOFF_THRUST if takeoff > 0.0 else 1.0)
		t = clampf(drag_k * ws * ws + G * sin(b.pitch) + (ws - b.speed) * 2.0, 0.0, tmax)
	b.speed = clampf(b.speed + (t - drag - G * sin(b.pitch)) * delta, 1.5, max_speed)
	var dir := Vector3(sin(b.yaw) * cos(b.pitch), sin(b.pitch), cos(b.yaw) * cos(b.pitch))
	b.vel = dir * b.speed + Vector3(air.x, up, air.z)
	pos += b.vel * delta
	if pos.y < _gy + 0.3:
		pos.y = _gy + 0.3
	b.global_position = pos
	return dist


## Přistávací manévr: křídla nahoru (klapka), brzdění, přímý sestup k místu dosednutí, v silném větru proti větru.
func _flare_step(b: Bird, delta: float, pos: Vector3, dl: float) -> float:
	flare = move_toward(flare, 1.0, delta * 3.0)
	flapping = true
	var to := land_goal - pos
	var dir := to / maxf(dl, 0.001)
	b.speed = move_toward(b.speed, v_stall * LAND_SPEED_K, FLARE_DECEL * delta)
	var stp := minf(b.speed * delta, dl)
	b.global_position = pos + dir * stp
	b.vel = dir * b.speed
	var want_yaw := atan2(dir.x, dir.z) if Vector2(dir.x, dir.z).length() > 0.2 else b.yaw
	var wh := Vector2(air.x, air.z).length()
	if wh > INTO_WIND_MIN:
		want_yaw = lerp_angle(want_yaw, atan2(-air.x, -air.z), clampf((wh - INTO_WIND_MIN) / 6.0, 0.0, 0.6))
	var k := 1.0 - exp(-delta * 5.0)
	b.yaw = lerp_angle(b.yaw, want_yaw, k)
	b.bank = lerpf(b.bank, 0.0, k)
	b.pitch = lerpf(b.pitch, asin(clampf(dir.y, -1.0, 1.0)), k)
	return dl
