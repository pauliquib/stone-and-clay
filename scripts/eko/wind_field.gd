## Pole větru (M8.4, `World.wind_field`): vítr v bodě s nárazy, závětřím a výškovým profilem.
## Podle čeho: logaritmický profil `u(z) = u*/κ · ln(z/z0)` (navázaný na referenční louku přes „směšovací“
## výšku `BLEND_M`), nárazy jako zamrzlá turbulence posouvaná krajinou rychlostí větru (Taylorova hypotéza),
## expozice z mapy stanovišť (`Site.wind_exp`, M8.2), orografický vzestup `w = U·∇h` nad svahem.
##
## Simulace (deterministická z času a seedu, „server“): střední vítr 10 m nad otevřenou loukou dává `Weather`
## (`wind`, `wind_bearing`). Pole nárazů je jedna dlaždicová mřížka šumu `GUST_RES`² (`FastNoiseLite` se seedem,
## `get_seamless_image`) s buňkou `GUST_CELL` m – **stejná data** jdou do shaderů jako globální textura
## `wind_gust` (posun `wind_offset`), takže vlna přes obilí odpovídá tomu, co cítí drak nebo dron.
##
## Výkon: `wind_at` nealokuje (jen čísla, `Vector3` hodnotou). Terén / povrch / stanoviště se na buňku
## `GRID_CELL` m čtou **jen jednou** (líná mezipaměť v `PackedFloat32Array`), za běhu už jen index do pole.
## Volající, který zná výšku nad zemí, ji předá (`agl`) – jinak se vezme výška buňky (hrubší).
##
## Vypnuto (`realism["wind"] == false`) nebo bez `Weather` → dřívější chování (`Weather.wind_vector()`
## s mocninným profilem (h/10)^0,14), takže volající nepotřebují vlastní větvení.
class_name WindField
extends Node

## --- laditelné konstanty
const SEED := 8404
const GUST_RES := 256                 # textura nárazů GUST_RES × GUST_RES (L8)
const GUST_CELL := 4.0                # m na texel → dlaždice 1 024 m
const GUST_FREQ := 0.045              # frekvence šumu v texelech (≈ chuchvalce 60–100 m)
const GUST_GAIN := 2.2                # náraz: u × (1 + GAIN · I · (2g − 1))
const GUST_ADVECT := 1.0              # posun pole nárazů = střední vítr × tohle (Taylor)
const Z0_REF := 0.03                  # m – drsnost referenční louky, ke které se vztahuje Weather.wind (10 m)
const REF_M := 10.0                   # m – výška měření Weather.wind
const BLEND_M := 60.0                 # m – směšovací výška (nad ní drsnost povrchu „zapomenuta“)
const TOP_M := 300.0                  # m – strop profilu (mezní vrstva)
const TERRAIN_FADE_M := 200.0         # m – vliv expozice a svahu slábne s výškou nad zemí
const EXP_MIN := 0.6                  # násobek rychlosti v závětří (wind_exp = 0)
const EXP_MAX := 1.4                  # násobek na hřebeni (wind_exp = 1); wind_exp 0,5 → 1,0
const I_MIN := 0.15                   # intenzita turbulence nad hladkým povrchem
const I_MAX := 0.30                   # … nad lesem / zástavbou
const I_STORM := 0.05                 # přídavek za bouřky (strop 0,35)
const LEE_GAIN := 1.5                 # turbulence v závětří hrany / lesa
const GRID_CELL := 24.0               # m – buňka mezipaměti terénu a drsnosti
const GRID_HALF := 6000.0             # m – mezipaměť pokrývá ±GRID_HALF kolem počátku
const SLOPE_D := 24.0                 # m – krok pro gradient terénu (hřbet, ne kamínek)
## drsnost z0 (m) podle třídy povrchu `SurfaceMap` (GRASS, ARABLE, ORCHARD, FOREST, YARD, BANK, ROCK, TRACK)
const Z0_BY_CLASS := [0.03, 0.1, 0.5, 1.0, 0.8, 0.1, 0.05, 0.03]

const _STRIDE := 7                    # h, gx, gz, exp_mult, z0, 1/ln(BLEND/z0), i0
const _EMPTY := -1.0e9

var world: World
var weather: Weather
var time := 0.0                       # s reálného běhu (fáze kmitů ve shaderech – `wind_time`)
var offset := Vector2.ZERO            # m – posun pole nárazů (`wind_offset`), modulo dlaždice
var gust_image: Image                 # L8, GUST_RES² – zdroj `gust_texture`
var gust_texture: ImageTexture        # pro globální uniform `wind_gust` (nastavuje Atmosphere)

var _gust := PackedByteArray()
var _cache := PackedFloat32Array()
var _gn := 0                          # buněk na stranu mezipaměti
var _on := true
var _dir := Vector2(0.8, 0.5)         # jednotkový směr, KAM fouká (svět xz)
var _u10 := 0.0                       # m/s, Weather.wind
var _u_blend := 0.0                   # m/s ve směšovací výšce nad referenční loukou
var _i_storm := 0.0


func setup(w: World) -> void:
	world = w
	weather = w.weather
	var n := FastNoiseLite.new()
	n.seed = SEED
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = GUST_FREQ
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 3
	n.fractal_gain = 0.5
	gust_image = n.get_seamless_image(GUST_RES, GUST_RES, false, false, 0.1, true)
	if gust_image.get_format() != Image.FORMAT_L8:
		gust_image.convert(Image.FORMAT_L8)
	_gust = gust_image.get_data()
	gust_texture = ImageTexture.create_from_image(gust_image)
	_gn = int(ceil(GRID_HALF * 2.0 / GRID_CELL))
	_cache.resize(_gn * _gn * _STRIDE)
	_cache.fill(_EMPTY)
	_tick(0.0)


func _process(delta: float) -> void:
	_tick(delta)


## Jednou za snímek: střední vítr z Weather, posun pole nárazů (integrovaný – změna rychlosti neskočí).
func _tick(delta: float) -> void:
	_on = world == null or world.realism_on("wind")
	time = fmod(time + delta, 3600.0)
	if weather == null:
		_u10 = 0.0
		return
	_u10 = weather.wind
	var wv := weather.wind_vector()
	var d := Vector2(wv.x, wv.z)
	if d.length() > 0.001:
		_dir = d.normalized()                        # za bezvětří drží poslední směr
	_u_blend = _u10 * log(BLEND_M / Z0_REF) / log(REF_M / Z0_REF)
	_i_storm = I_STORM * weather.storm
	var tile := GUST_CELL * GUST_RES
	offset += _dir * (_u10 * GUST_ADVECT * delta)
	offset = Vector2(fposmod(offset.x, tile), fposmod(offset.y, tile))


## Jednotkový směr, kam vítr fouká (svět xz) – pro shader `wind_dir`.
func dir() -> Vector2:
	return _dir


## Střední rychlost 10 m nad referenční loukou (m/s) – pro shader `wind_speed`.
func speed() -> float:
	return _u10


func enabled() -> bool:
	return _on


# ------------------------------------------------------------------ dotazy (bez alokací)

## Vítr v bodě (m/s, svět). `agl` = výška nad zemí, když ji volající zná (jinak −1 → z mezipaměti).
## Složka y = orografický vzestup / pád nad svahem (ne termika – tu dává `Thermals`).
func wind_at(pos: Vector3, agl: float = -1.0) -> Vector3:
	if weather == null:
		return Vector3.ZERO
	if not _on:
		return _legacy(agl)
	var ci := _cell(pos.x, pos.z)
	var h := 0.0
	var gx := 0.0
	var gz := 0.0
	var em := 1.0
	var z0 := 0.1
	var il := 1.0 / log(BLEND_M / 0.1)
	var i0 := 0.2
	if ci >= 0:
		h = _cache[ci]
		gx = _cache[ci + 1]
		gz = _cache[ci + 2]
		em = _cache[ci + 3]
		z0 = _cache[ci + 4]
		il = _cache[ci + 5]
		i0 = _cache[ci + 6]
	if agl < 0.0:
		agl = pos.y - h
	var z := clampf(agl, z0 * 2.0, TOP_M)
	var fade := exp(-maxf(agl, 0.0) / TERRAIN_FADE_M)
	var u := _u_blend * log(z / z0) * il * lerpf(1.0, em, fade)
	var g := _gust_sample(pos.x, pos.z)
	u *= maxf(1.0 + GUST_GAIN * (i0 + _i_storm) * (2.0 * g - 1.0), 0.05)
	var w := u * (gx * _dir.x + gz * _dir.y) * fade
	return Vector3(_dir.x * u, w, _dir.y * u)


## Náraz 0..1 (0,5 = střed) v bodě – stejná hodnota, jakou vidí shader v `wind_gust`.
func gust_at(pos: Vector3) -> float:
	return _gust_sample(pos.x, pos.z)


## Turbulence σ (m/s) – pro dron, paraglide, trike: roste s drsností, bouřkou a v závětří hran a lesa.
func turbulence_at(pos: Vector3, agl: float = -1.0) -> float:
	if weather == null:
		return 0.0
	var ci := _cell(pos.x, pos.z)
	var i0 := 0.2
	var lee := 0.0
	var h := 0.0
	if ci >= 0:
		h = _cache[ci]
		i0 = _cache[ci + 6]
		lee = clampf(-(_cache[ci + 1] * _dir.x + _cache[ci + 2] * _dir.y) * 4.0, 0.0, 1.0)
	if agl < 0.0:
		agl = pos.y - h
	var fade := exp(-maxf(agl, 0.0) / TERRAIN_FADE_M)
	return _u10 * (i0 + _i_storm) * (1.0 + LEE_GAIN * lee * fade)


## Drsnost z0 (m) v bodě – les ≈ 1, louka 0,03 (Atmosphere: šum v korunách).
func roughness_at(pos: Vector3) -> float:
	var ci := _cell(pos.x, pos.z)
	return _cache[ci + 4] if ci >= 0 else 0.1


## Ladicí vrstva mapy „vitr“ (F2 → Příroda – ladění): rychlost 10 m nad zemí, modrá klid → červená vichr.
func debug_layer(x: float, z: float) -> Color:
	var v := wind_at(Vector3(x, 0.0, z), 10.0)
	var s := Vector2(v.x, v.z).length()
	var t := clampf(s / 16.0, 0.0, 1.0)
	return Color(0.15 + 0.85 * t, 0.55 * (1.0 - absf(t - 0.5) * 2.0) + 0.2, 0.9 * (1.0 - t), 0.25 + 0.45 * t)


# ------------------------------------------------------------------ vnitřek

func _legacy(agl: float) -> Vector3:
	var wv := weather.wind_vector()
	if agl >= 0.0:
		wv *= pow(maxf(agl, 1.0) / 10.0, 0.14)
	return wv


## Bilineární vzorek mřížky nárazů – shodně s lineárním filtrem GPU (středy texelů v i + 0,5).
func _gust_sample(x: float, z: float) -> float:
	var fu := fposmod((x - offset.x) / GUST_CELL - 0.5, float(GUST_RES))
	var fv := fposmod((z - offset.y) / GUST_CELL - 0.5, float(GUST_RES))
	var i0 := int(fu)
	var j0 := int(fv)
	var tx := fu - i0
	var tz := fv - j0
	var i1 := (i0 + 1) % GUST_RES
	var j1 := (j0 + 1) % GUST_RES
	var a := lerpf(float(_gust[j0 * GUST_RES + i0]), float(_gust[j0 * GUST_RES + i1]), tx)
	var b := lerpf(float(_gust[j1 * GUST_RES + i0]), float(_gust[j1 * GUST_RES + i1]), tx)
	return lerpf(a, b, tz) / 255.0


## Index první hodnoty buňky v mezipaměti (−1 mimo); prázdnou buňku dopočítá (jednou).
func _cell(x: float, z: float) -> int:
	var ix := int(floor((x + GRID_HALF) / GRID_CELL))
	var iz := int(floor((z + GRID_HALF) / GRID_CELL))
	if ix < 0 or iz < 0 or ix >= _gn or iz >= _gn:
		return -1
	var ci := (iz * _gn + ix) * _STRIDE
	if _cache[ci] <= _EMPTY:
		_fill(ci, -GRID_HALF + (ix + 0.5) * GRID_CELL, -GRID_HALF + (iz + 0.5) * GRID_CELL)
	return ci


func _fill(ci: int, x: float, z: float) -> void:
	var h := 0.0
	var gx := 0.0
	var gz := 0.0
	var t: Terrain = world.terrain if world else null
	if t != null:
		h = t.height_at(x, z)
		gx = (t.height_at(x + SLOPE_D, z) - t.height_at(x - SLOPE_D, z)) / (2.0 * SLOPE_D)
		gz = (t.height_at(x, z + SLOPE_D) - t.height_at(x, z - SLOPE_D)) / (2.0 * SLOPE_D)
	var em := 1.0                                     # fallback bez site.bin
	if world and world.site != null and world.site.loaded:
		em = lerpf(EXP_MIN, EXP_MAX, clampf(world.site.wind_exp(x, z), 0.0, 1.0))
	var z0 := 0.1
	if world and world.surface != null and world.surface.loaded:
		var c := world.surface.class_at(x, z)
		z0 = Z0_BY_CLASS[c] if c >= 0 and c < Z0_BY_CLASS.size() else 0.1
	elif world and world.fauna != null:
		z0 = lerpf(0.1, 1.0, clampf(world.fauna.forest_at(x, z), 0.0, 1.0))
	var rough := clampf(log(z0 / Z0_REF) / log(1.0 / Z0_REF), 0.0, 1.0)
	_cache[ci] = h
	_cache[ci + 1] = gx
	_cache[ci + 2] = gz
	_cache[ci + 3] = em
	_cache[ci + 4] = z0
	_cache[ci + 5] = 1.0 / log(BLEND_M / z0)
	_cache[ci + 6] = lerpf(I_MIN, I_MAX, rough)
