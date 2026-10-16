## Pole a louky podle kalendáře: mapa využití ploch (data/landuse.bin z tools/landuse.py, zdroj OSM)
## a tabulka plodin `CROPS` s barvami polí po celý rok.
##
## - `class_at(x, z)` / `field_at(x, z)` – třída plochy (1 orná půda, 2 louka, 3 sad, 4 zahrádky) a číslo pole
## - plodina každého pole je deterministická podle (číslo pole, rok) s váhami osevního postupu (`weight`)
## - `lut_image(doy, year)` – tabulka 256×2 px pro shader terénu: řádek 0 = barva plodiny (lineární RGB)
##   + síla přimíchání, řádek 1 = síla rýh po orbě a směr rýh
## Terénní shader (shaders/terrain.gdshader) podle toho pole přebarvuje; louky dostávají jen květy (`meadow_bloom`).
##
## **M8.12 (přepínač `crops`):** každé pole (id) má stav plodiny z `CropModel` (`eco[id]` = {`cur` letošní plodina, `nxt` ozim
## zasetý na podzim pro příští rok}). Denní krok v `World.eco_day` po kouscích (`EcoClock.slice`, `FIELDS_PER_FRAME` polí
## za snímek), vstupy: hodinové teploty a záření (`CropModel.DayAcc` z `eco_hour`), teplotní posun místa z `World.micro`
## (noc v kotlině), vlhkost půdy `World.soil_water.moisture_at` ve středu pole. Barva pole se bere z kalendáře `CROPS[..].cal`
## v **„fenologickém“ dni** (den normálu se stejnou sumou teplot) – v normálním roce stejná jako dřív, v teplém / suchém
## roce dřív zlátne a žne se dřív; suchem žloutne navíc (`DRY_YELLOW_K`), zakrslé obilí je nižší (řádek 1, kanál B LUT
## → `vegetation.gdshader`). Plodina pole dál podle `crop_of` (determinismus s `tools/vegetation.py`).
## API: `crop_height_at(pos)` (výška porostu v m – zvěř M8.10/M8.15), `field_info(id)`, `yield_ratio_of(id)` (výnos vůči
## normálu – výkup / statek), `journal_line()` (deník J → Počasí: „Letošní úroda: …“), `to_dict/restore` (save `fields_eco`).
class_name Fields
extends RefCounted

const PATH := "res://data/landuse.bin"
const HEADER := 28                   # magic(4) + verze(4) + x0, z0, cell (12) + nx, nz (8)

## Plodiny. `cal` = kalendář [den v roce, Color(r, g, b, síla přimíchání), rýhy 0..1 (nepovinné)]
## s lineární interpolací mezi řádky (barvy v sRGB, do shaderu jdou převedené na lineární).
## Ozimé plodiny (`winter`) jsou na jaře už zelené; `sown` = barva vzcházejících semínek na podzim.
## Žně a další termíny se u každého pole posouvají o ±`DATE_SPREAD` dní.
## M8.D2c: `static var` (F3 → Příroda/Pole a louky – váhy osevního postupu, posun termínů, setí ozimů), výchozí beze změny.
static var DATE_SPREAD := 6
static var SOW_FROM_DOY := 275.0     # po podmítce se od tohoto dne zelenají vzcházející ozimy
static var SOW_TO_DOY := 305.0       # … naplno
static var CROPS := {
	"psenice": {"name": "ozimá pšenice", "weight": 0.35, "winter": true, "sown": Color(0.30, 0.46, 0.20, 0.85), "cal": [
		[1, Color(0.30, 0.46, 0.20, 0.85)], [70, Color(0.30, 0.46, 0.20, 0.85)],
		[100, Color(0.30, 0.52, 0.18, 0.9)], [150, Color(0.32, 0.55, 0.20, 0.9)],
		[168, Color(0.55, 0.60, 0.26, 0.9)], [182, Color(0.78, 0.68, 0.30, 0.92)],
		[196, Color(0.86, 0.71, 0.30, 0.94)], [207, Color(0.87, 0.72, 0.32, 0.94)],
		[209, Color(0.78, 0.66, 0.38, 0.92)], [235, Color(0.72, 0.62, 0.36, 0.92)],
		[246, Color(0.52, 0.38, 0.24, 0.92), 1.0], [258, Color(0.40, 0.29, 0.20, 0.92), 1.0],
		[366, Color(0.40, 0.29, 0.20, 0.92), 0.8]]},
	"jecmen": {"name": "jarní ječmen", "weight": 0.15, "cal": [
		[1, Color(0.40, 0.29, 0.20, 0.92), 0.8], [75, Color(0.42, 0.31, 0.21, 0.92), 0.6],
		[88, Color(0.50, 0.38, 0.26, 0.92), 0.3], [104, Color(0.50, 0.40, 0.28, 0.9)],
		[118, Color(0.40, 0.58, 0.25, 0.9)], [150, Color(0.35, 0.55, 0.20, 0.92)],
		[168, Color(0.58, 0.60, 0.28, 0.92)], [182, Color(0.85, 0.72, 0.34, 0.94)],
		[194, Color(0.86, 0.73, 0.34, 0.94)], [196, Color(0.78, 0.66, 0.38, 0.92)],
		[236, Color(0.72, 0.62, 0.36, 0.92)], [248, Color(0.52, 0.38, 0.24, 0.92), 1.0],
		[262, Color(0.40, 0.29, 0.20, 0.92), 1.0], [366, Color(0.40, 0.29, 0.20, 0.92), 0.8]]},
	"repka": {"name": "řepka", "weight": 0.15, "winter": true, "sown": Color(0.28, 0.45, 0.20, 0.85), "cal": [
		[1, Color(0.28, 0.45, 0.20, 0.85)], [95, Color(0.30, 0.50, 0.20, 0.9)],
		[112, Color(0.60, 0.65, 0.18, 0.9)], [122, Color(0.95, 0.84, 0.10, 0.95)],
		[140, Color(0.93, 0.82, 0.10, 0.95)], [152, Color(0.50, 0.56, 0.20, 0.92)],
		[180, Color(0.55, 0.48, 0.20, 0.92)], [198, Color(0.50, 0.38, 0.20, 0.92)],
		[201, Color(0.70, 0.60, 0.35, 0.92)], [236, Color(0.62, 0.52, 0.32, 0.92)],
		[248, Color(0.48, 0.36, 0.23, 0.92), 1.0], [260, Color(0.40, 0.29, 0.20, 0.92), 1.0],
		[366, Color(0.40, 0.29, 0.20, 0.92), 0.8]]},
	"kukurice": {"name": "kukuřice", "weight": 0.20, "cal": [
		[1, Color(0.40, 0.29, 0.20, 0.92), 0.8], [110, Color(0.42, 0.31, 0.21, 0.92), 0.6],
		[126, Color(0.46, 0.34, 0.22, 0.92), 0.3], [146, Color(0.40, 0.50, 0.22, 0.75)],
		[180, Color(0.24, 0.50, 0.15, 0.92)], [245, Color(0.28, 0.48, 0.14, 0.92)],
		[268, Color(0.55, 0.50, 0.22, 0.92)], [288, Color(0.60, 0.50, 0.28, 0.92)],
		[292, Color(0.52, 0.40, 0.25, 0.92)], [302, Color(0.40, 0.29, 0.20, 0.92), 1.0],
		[366, Color(0.40, 0.29, 0.20, 0.92), 0.8]]},
	"slunecnice": {"name": "slunečnice", "weight": 0.05, "cal": [
		[1, Color(0.40, 0.29, 0.20, 0.92), 0.8], [112, Color(0.42, 0.31, 0.21, 0.92), 0.6],
		[128, Color(0.46, 0.34, 0.22, 0.92), 0.3], [152, Color(0.34, 0.50, 0.15, 0.85)],
		[190, Color(0.32, 0.50, 0.15, 0.92)], [204, Color(0.72, 0.64, 0.14, 0.95)],
		[226, Color(0.74, 0.64, 0.14, 0.95)], [252, Color(0.48, 0.38, 0.18, 0.92)],
		[272, Color(0.40, 0.30, 0.19, 0.92)], [284, Color(0.40, 0.29, 0.20, 0.92), 1.0],
		[366, Color(0.40, 0.29, 0.20, 0.92), 0.8]]},
	"picniny": {"name": "pícniny (jetel)", "weight": 0.10, "cal": [
		[1, Color(0.38, 0.38, 0.22, 0.7)], [90, Color(0.35, 0.48, 0.22, 0.8)],
		[130, Color(0.30, 0.55, 0.20, 0.9)], [150, Color(0.32, 0.55, 0.20, 0.9)],
		[153, Color(0.62, 0.60, 0.32, 0.9)], [166, Color(0.30, 0.55, 0.20, 0.9)],
		[198, Color(0.32, 0.54, 0.20, 0.9)], [201, Color(0.60, 0.58, 0.30, 0.9)],
		[214, Color(0.30, 0.54, 0.20, 0.9)], [262, Color(0.32, 0.48, 0.20, 0.85)],
		[310, Color(0.36, 0.42, 0.22, 0.75)], [366, Color(0.38, 0.38, 0.22, 0.7)]]},
}

var loaded := false
var nx := 0
var nz := 0
var x0 := 0.0
var z0 := 0.0
var cell := 4.0
var _data := PackedByteArray()      # [třída, id pole] po buňkách, řádek = z


## Načte data/landuse.bin. Vrací false, když soubor chybí (spusť tools/landuse.py) – hra pak funguje bez polí.
func load_data() -> bool:
	if not FileAccess.file_exists(PATH):
		push_warning("Fields: chybí %s (tools/landuse.py)" % PATH)
		return false
	var b := FileAccess.get_file_as_bytes(PATH)
	if b.size() < HEADER or b.slice(0, 4).get_string_from_ascii() != "LUSE":
		push_warning("Fields: neznámý formát landuse.bin")
		return false
	x0 = b.decode_float(8)
	z0 = b.decode_float(12)
	cell = b.decode_float(16)
	nx = b.decode_s32(20)
	nz = b.decode_s32(24)
	if b.size() < HEADER + nx * nz * 2:
		push_warning("Fields: landuse.bin je useknutý")
		return false
	_data = b.slice(HEADER, HEADER + nx * nz * 2)
	loaded = true
	return true


## Rastr jako RG8 textura pro shader (R = třída, G = id pole).
func make_texture() -> ImageTexture:
	var img := Image.create_from_data(nx, nz, false, Image.FORMAT_RG8, _data)
	return ImageTexture.create_from_image(img)


## (x0, z0, šířka, výška) v metrech – pro uniform `landuse_rect`.
func rect() -> Vector4:
	return Vector4(x0, z0, nx * cell, nz * cell)


## Třída plochy v bodě: 0 nic, 1 orná půda, 2 louka / pastvina, 3 sad / vinice, 4 zahrádky.
func class_at(x: float, z: float) -> int:
	if not loaded:
		return 0
	var ix := floori((x - x0) / cell)
	var iz := floori((z - z0) / cell)
	if ix < 0 or iz < 0 or ix >= nx or iz >= nz:
		return 0
	return _data[(iz * nx + ix) * 2]


## Číslo pole (1..255) na orné půdě, jinak 0.
func field_at(x: float, z: float) -> int:
	if not loaded:
		return 0
	var ix := floori((x - x0) / cell)
	var iz := floori((z - z0) / cell)
	if ix < 0 or iz < 0 or ix >= nx or iz >= nz:
		return 0
	return _data[(iz * nx + ix) * 2 + 1]


# ------------------------------------------------------------------ plodiny

static func _hash(a: int, b: int) -> int:
	var h: int = ((a * 73856093) ^ (b * 19349663)) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return h ^ (h >> 16)


## Klíč plodiny pole `id` v daném roce (osevní postup podle vah).
static func crop_of(id: int, year: int) -> String:
	var total := 0.0
	for k in CROPS:
		var w: float = CROPS[k]["weight"]
		total += w
	var r: float = float(_hash(id, year) % 10000) / 10000.0 * total
	var acc := 0.0
	var last := "psenice"
	for k in CROPS:
		var w: float = CROPS[k]["weight"]
		acc += w
		last = k
		if r <= acc:
			break
	return last


static func crop_name(key: String) -> String:
	return String(CROPS[key]["name"])


## Plodina v bodě (klíč) nebo "" mimo pole.
func crop_at(x: float, z: float, year: int) -> String:
	var id := field_at(x, z)
	return crop_of(id, year) if id > 0 else ""


## Hodnota kalendáře v daném dni: [r, g, b, síla, rýhy].
static func _sample(cal: Array, doy: float) -> PackedFloat32Array:
	var out := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])
	var n := cal.size()
	var i := 1
	while i < n - 1 and doy > float(cal[i][0]):
		i += 1
	var a: Array = cal[maxi(i - 1, 0)]
	var b: Array = cal[mini(i, n - 1)]
	var t := 0.0
	if float(b[0]) > float(a[0]):
		t = clampf((doy - float(a[0])) / (float(b[0]) - float(a[0])), 0.0, 1.0)
	var ca: Color = a[1]
	var cb: Color = b[1]
	var fa: float = a[2] if a.size() > 2 else 0.0
	var fb: float = b[2] if b.size() > 2 else 0.0
	out[0] = lerpf(ca.r, cb.r, t)
	out[1] = lerpf(ca.g, cb.g, t)
	out[2] = lerpf(ca.b, cb.b, t)
	out[3] = lerpf(ca.a, cb.a, t)
	out[4] = lerpf(fa, fb, t)
	return out


## Barva a rýhy pole `id` v daném dni roku (s posunem termínů pole a přechodem na ozim po sklizni).
static func field_state(id: int, doy: float, year: int) -> PackedFloat32Array:
	var key := crop_of(id, year)
	var spec: Dictionary = CROPS[key]
	var shift := float(_hash(id, year + 7) % (2 * DATE_SPREAD + 1) - DATE_SPREAD)
	var s := _sample(spec["cal"], clampf(doy - shift, 1.0, 366.0))
	s = _autumn(s, id, doy, year)
	return s


## Na podzim se po podmítce zelenají vzcházející ozimy příští plodiny (společné pro kalendář i model M8.12).
static func _autumn(s: PackedFloat32Array, id: int, doy: float, year: int) -> PackedFloat32Array:
	if doy <= SOW_FROM_DOY:
		return s
	var nspec: Dictionary = CROPS[crop_of(id, year + 1)]
	if not nspec.get("winter", false):
		return s
	var sown: Color = nspec["sown"]
	var t := smoothstep(SOW_FROM_DOY, SOW_TO_DOY, doy)
	s[0] = lerpf(s[0], sown.r, t)
	s[1] = lerpf(s[1], sown.g, t)
	s[2] = lerpf(s[2], sown.b, t)
	s[3] = lerpf(s[3], sown.a, t)
	s[4] = lerpf(s[4], 0.0, t)
	return s


## Tabulka 256×2 pro terénní shader (RGBA8, lineární barvy): řádek 0 = barva + síla, řádek 1 = rýhy, směr rýh.
func lut_image(doy: float, year: int) -> Image:
	var img := Image.create(256, 2, false, Image.FORMAT_RGBA8)
	var eco_on := _eco_on()
	for id in range(1, 256):
		var s := field_state_eco(id, doy, year) if eco_on else field_state(id, doy, year)
		var c := Color(s[0], s[1], s[2]).srgb_to_linear()
		img.set_pixel(id, 0, Color(c.r, c.g, c.b, s[3]))
		img.set_pixel(id, 1, Color(s[4], float(_hash(id, 3) % 2), _short_of(id), 1.0))
	return img


# ------------------------------------------------------------------ M8.12: plodiny polí podle růstového modelu

## M8.12: laditelné (F3 → Příroda/Plodiny a zahrada) – `static var`.
static var FIELDS_PER_FRAME := 12        # polí za snímek v denním kroku (255 polí ≈ 22 snímků)
static var HARVEST_DELAY_MAX_D := 6      # sklizeň 0..tolik dní po dozrání (podle pole), ne za deště
static var DRY_YELLOW_K := 0.45          # suchem žloutnoucí pole: přimíchání slámové barvy při plném stresu
static var DRY_YELLOW_FROM := 0.6        # … od klouzavého stresu vody pod tímto
static var SHORT_MAX := 0.6              # zakrslé obilí nejvýš o tolik nižší (shader vegetace)
static var MOIST_DRY_MONTH := 0.35       # deník: měsíc „suchý“ pod touto průměrnou vlhkostí půdy …
static var MOIST_WET_MONTH := 0.85       # … „mokrý“ nad touto
static var RATIO_WEAK := 0.75            # deník: úroda „slabá“ pod tímto podílem normálu …
static var RATIO_RICH := 1.15            # … „bohatá“ nad
const CENTER_STRIDE := 3                 # středy polí: vzorek každé 3. buňky (12 m) – jednou při startu
const STRAW := Color(0.80, 0.70, 0.32)

var world: World
var eco := {}                            # id pole → {"cur": stav CropModel, "nxt": ozim na příští rok}
var year_log := {}                       # "rok" → {"m": {měsíc: [součet vlhkosti, dnů]}, "h": {plodina: [součet podílu, n, první den]}}
var lut_gen := 0                         # zvýší se po dokončení denního kroku všech polí (SeasonFx přepočítá LUT)
var _cx := PackedFloat32Array()
var _cz := PackedFloat32Array()
var _cn := PackedInt32Array()
var _height := PackedFloat32Array()      # m – výška porostu pole (crop_height_at)
var _acc := CropModel.DayAcc.new()
var _day := {}                           # vstupy dne, který se právě počítá (doy, year, t, tmin, tmax, rad, rain, gap)
var _last_jd := -1


## Napojení na eko-takt (volá World po `load_data`, po Microclimate / SoilWater). Bez dat landuse nic.
func setup_eco(w: World) -> void:
	world = w
	if not loaded:
		return
	_find_centers()
	w.eco_hour.connect(_on_eco_hour)
	w.eco_day.connect(_on_eco_day)
	_last_jd = w.clock.jd() if w.clock else -1
	_init_from_clim()


func _eco_on() -> bool:
	return world != null and loaded and world.realism_on("crops")


## Středy polí (průměr buněk) – vzorek mřížky po `CENTER_STRIDE`, jednou.
func _find_centers() -> void:
	_cx.resize(256)
	_cz.resize(256)
	_cn.resize(256)
	_height.resize(256)
	_cx.fill(0.0)
	_cz.fill(0.0)
	_cn.fill(0)
	_height.fill(0.0)
	for iz in range(0, nz, CENTER_STRIDE):
		var row := iz * nx
		for ix in range(0, nx, CENTER_STRIDE):
			var k := (row + ix) * 2
			if _data[k] != 1:
				continue
			var id := _data[k + 1]
			if id == 0:
				continue
			_cx[id] += x0 + (float(ix) + 0.5) * cell
			_cz[id] += z0 + (float(iz) + 0.5) * cell
			_cn[id] += 1
	for id in 256:
		if _cn[id] > 0:
			_cx[id] /= float(_cn[id])
			_cz[id] /= float(_cn[id])


## Den výsevu plodiny na poli (v rozmezí `seti` podle čísla pole a roku).
static func sow_doy(id: int, key: String, year: int) -> float:
	var sp := CropModel.spec(key)
	var seti: Array = sp.get("seti", [100, 110])
	var a := float(seti[0])
	var b := float(seti[1])
	return floorf(a + float(_hash(id, year + 11) % 1000) / 1000.0 * (b - a))


## Start hry / bez savu: stav každého pole podle klimatického normálu k dnešku.
func _init_from_clim() -> void:
	eco.clear()
	if world == null or world.clock == null:
		return
	var year := world.clock.year()
	var doy := floorf(world.clock.day_of_year())
	for id in range(1, 256):
		if _cn[id] == 0:
			continue
		eco[id] = {"cur": _clim_for(id, year, doy, false), "nxt": _clim_for(id, year + 1, doy, true)}
		_refresh_height(id)
	lut_gen += 1


## Stav plodiny pole `id` pro rok sklizně `hy` podle normálu, jak by vypadal dne `doy` (roku `hy`; u `autumn` roku hy − 1).
func _clim_for(id: int, hy: int, doy: float, autumn: bool) -> Dictionary:
	var key := crop_of(id, hy)
	if not CropModel.modeled(key):
		return {}
	var sp := CropModel.spec(key)
	var winter := bool(sp.get("ozim", false))
	if autumn and not winter:
		return {}
	var sow := sow_doy(id, key, hy)
	var idx: int
	if winter and not autumn:
		idx = int(doy + 365.0 - sow)          # zaseto loni na podzim
	else:
		idx = int(doy - sow)                  # zaseto letos (jaro, nebo ozim na podzim)
	if idx < 0:
		return {}
	var s := CropModel.clim_state(key, sow, hy, idx)
	var c := CropModel.clim(key)
	var harv_idx := int(c["mat"]) + _harvest_delay(id, hy)
	if idx >= harv_idx:
		s["harv"] = sow + float(harv_idx) - (365.0 if winter else 0.0)
		s["yr"] = 1.0
	return s


func _harvest_delay(id: int, hy: int) -> int:
	return _hash(id, hy + 23) % (HARVEST_DELAY_MAX_D + 1)


func _on_eco_hour(dt_h: float) -> void:
	if not _eco_on():
		return
	var wt: Weather = world.weather
	_acc.add(wt.temp if wt != null else 12.0, CropModel.ghi_now(world), dt_h)


## Nový den `jd` – spočítá včerejšek (po kouscích, `FIELDS_PER_FRAME` polí za snímek).
func _on_eco_day(jd: int) -> void:
	if not _eco_on():
		_last_jd = jd
		_acc.reset()
		_refresh_heights_clim()
		return
	var gap := clampi(jd - _last_jd, 1, 400) if _last_jd >= 0 else 1
	_last_jd = jd
	var d := Clock.from_jdn(jd - 1)
	var year: int = d["year"]
	var doy := float(jd - 1 - Clock.jdn(year, 1, 1) + 1)
	var wt: Weather = world.weather
	var t := CropModel.clim_temp(doy)
	var r := CropModel.clim_range(doy)
	_day = {"doy": doy, "year": year, "gap": gap, "t": t, "tmin": t - r * 0.5, "tmax": t + r * 0.5,
		"rad": CropModel.clim_rad_mj(doy, wt.cloud if wt != null else CropModel.CLIM_CLOUD),
		"rain": wt != null and wt.is_raining(), "now_t": wt.temp if wt != null else t}
	if _acc.valid():
		_day["t"] = _acc.mean()
		_day["tmin"] = _acc.tmin
		_day["tmax"] = _acc.tmax
		_day["rad"] = _acc.rad_mj()
	_acc.reset()
	# deník: vlhkost půdy po měsících (průměr katastru, fallback z počasí)
	var m := 0.5
	var sw: SoilWater = world.soil_water
	if sw != null:
		m = sw.mean_moist if sw.active() else sw.moisture_at(0.0, 0.0)
	var lg := _log(year)
	var mo: Dictionary = lg["m"]
	var mk := str(int(d["month"]))
	var mm: Array = mo.get(mk, [0.0, 0])
	mo[mk] = [float(mm[0]) + m, int(mm[1]) + 1]
	if world.eco != null:
		world.eco.slice(255, FIELDS_PER_FRAME, _step_field)
	else:
		for i in 255:
			_step_field(i)


func _log(year: int) -> Dictionary:
	var k := str(year)
	if not year_log.has(k):
		year_log[k] = {"m": {}, "h": {}}
		for old in year_log.keys():          # drž jen poslední 2 roky
			if int(old) < year - 1:
				year_log.erase(old)
	return year_log[k]


## Denní krok jednoho pole (`i` = id − 1).
func _step_field(i: int) -> void:
	var id := i + 1
	if i == 254:
		lut_gen += 1
	if id >= _cn.size() or _cn[id] == 0 or _day.is_empty():
		return
	var doy: float = _day["doy"]
	var year: int = _day["year"]
	var e: Dictionary = eco.get(id, {})
	var cur: Dictionary = e.get("cur", {})
	var nxt: Dictionary = e.get("nxt", {})
	# nový rok: ozim zasetý loni se stává letošní plodinou
	if not cur.is_empty() and int(cur["y"]) < year:
		cur = {}
	if cur.is_empty() and not nxt.is_empty() and int(nxt["y"]) == year:
		cur = nxt
		nxt = {}
	elif not nxt.is_empty() and int(nxt["y"]) <= year:
		nxt = {}
	# jarní výsev
	var key := crop_of(id, year)
	if cur.is_empty() and CropModel.modeled(key) and not bool(CropModel.spec(key).get("ozim", false)):
		var sd := sow_doy(id, key, year)
		if doy >= sd and doy < sd + 30.0:
			cur = CropModel.new_state(key, doy, year)
	# podzimní výsev ozimu na příští rok (letošní plodina musí být sklizená – jinak se sklidí hned)
	var nkey := crop_of(id, year + 1)
	if nxt.is_empty() and CropModel.modeled(nkey) and bool(CropModel.spec(nkey).get("ozim", false)) \
			and doy >= sow_doy(id, nkey, year + 1):
		if not cur.is_empty() and int(cur.get("harv", -1)) < 0:
			_harvest(id, cur, doy, year)
		nxt = CropModel.new_state(nkey, doy, year + 1)
	var off := 0.0
	var mc: Microclimate = world.micro
	if mc != null:
		off = mc.temp_at(Vector3(_cx[id], 0.0, _cz[id])) - float(_day["now_t"])   # noční posun místa (kotlina, svah) – hrubě
	var moist := 0.5
	var sw: SoilWater = world.soil_water
	if sw != null:
		moist = sw.moisture_at(_cx[id], _cz[id])
	var gap: int = _day["gap"]
	for st in [cur, nxt]:
		var s: Dictionary = st
		if s.is_empty() or int(s.get("harv", -1)) >= 0:
			continue
		var sp := CropModel.spec(String(s["k"]))
		for g in gap:
			var last := g == gap - 1
			var dd := doy - float(gap - 1 - g)
			var t: float = _day["t"] if last else CropModel.clim_temp(dd)
			var r := CropModel.clim_range(dd)
			var tmin: float = _day["tmin"] if last else t - r * 0.5
			var tmax: float = _day["tmax"] if last else t + r * 0.5
			var rad: float = _day["rad"] if last else CropModel.clim_rad_mj(dd, CropModel.CLIM_CLOUD)
			CropModel.step_day(s, sp, t + off * 0.5, tmin + off, tmax, rad, moist)
			if int(s.get("dead", 0)) != 0:
				break
		if int(s.get("dead", 0)) != 0:
			_harvest(id, s, doy, year)          # zničený porost se zaorá (výnos 0)
		elif int(s["st"]) >= CropModel.ST_RIPE and int(s.get("dm", 0)) >= _harvest_delay(id, int(s["y"])) \
				and not bool(_day["rain"]):
			_harvest(id, s, doy, year)
	eco[id] = {"cur": cur, "nxt": nxt}
	_refresh_height(id)


func _harvest(id: int, s: Dictionary, doy: float, year: int) -> void:
	s["harv"] = doy
	var key := String(s["k"])
	var sp := CropModel.spec(key)
	# nedozrálé (pole se musí uvolnit pro ozim) = odhad, jako by dozrálo normálně; zničené = 0
	var ratio := CropModel.yield_ratio(s, sp, key) if int(s.get("st", 0)) >= CropModel.ST_RIPE \
		else CropModel.yield_forecast_ratio(s, sp, key)
	s["yr"] = ratio
	if int(s.get("y", year)) == year:
		note_harvest(key, ratio, doy, year)


## Sklizeň do ročního shrnutí (podíl normálu; volá i zahrada).
func note_harvest(key: String, ratio: float, doy: float, year: int) -> void:
	var h: Dictionary = _log(year)["h"]
	var a: Array = h.get(key, [0.0, 0, doy])
	h[key] = [float(a[0]) + ratio, int(a[1]) + 1, minf(float(a[2]), doy)]


func _refresh_height(id: int) -> void:
	var e: Dictionary = eco.get(id, {})
	var hgt := 0.0
	for st in [e.get("cur", {}), e.get("nxt", {})]:
		var s: Dictionary = st
		if s.is_empty():
			continue
		var key := String(s["k"])
		var sp := CropModel.spec(key)
		hgt = maxf(hgt, float(sp.get("vyska", 0.5)) * CropModel.height_frac(s, sp, key))
	_height[id] = hgt


## Bez modelu (přepínač vypnutý): výšky polí podle normálu k dnešku (jednou za den, 255 polí).
func _refresh_heights_clim() -> void:
	if world == null or world.clock == null or _cn.is_empty():
		return
	var year := world.clock.year()
	var doy := floorf(world.clock.day_of_year())
	for id in range(1, 256):
		if _cn[id] == 0:
			continue
		var hgt := 0.0
		for st in [_clim_for(id, year, doy, false), _clim_for(id, year + 1, doy, true)]:
			var s: Dictionary = st
			if s.is_empty():
				continue
			var key := String(s["k"])
			var sp := CropModel.spec(key)
			hgt = maxf(hgt, float(sp.get("vyska", 0.5)) * CropModel.height_frac(s, sp, key))
		_height[id] = hgt


## M8.12 API: výška porostu (m) v bodě – obilí, řepka, kukuřice; 0 mimo pole, po sklizni a bez dat.
## Levné (dva indexy do pole) – smí se volat často (zvěř M8.10 / M8.15, kryt).
func crop_height_at(pos: Vector3) -> float:
	if _height.is_empty():
		return 0.0
	var id := field_at(pos.x, pos.z)
	return _height[id] if id > 0 else 0.0


## Stav plodiny pole (letošní nesklizená, jinak zasetý ozim, jinak sklizená) – {} bez modelu.
func field_info(id: int) -> Dictionary:
	var e: Dictionary = eco.get(id, {})
	var cur: Dictionary = e.get("cur", {})
	if not cur.is_empty() and int(cur.get("harv", -1)) < 0:
		return cur
	var nxt: Dictionary = e.get("nxt", {})
	return nxt if not nxt.is_empty() else cur


## Výnos pole vůči normálu (sklizený, jinak odhad) – pro výkup / statek. 1 = běžný rok.
func yield_ratio_of(id: int) -> float:
	var s: Dictionary = (eco.get(id, {}) as Dictionary).get("cur", {})
	if s.is_empty():
		return 1.0
	if s.has("yr"):
		return float(s["yr"])
	var key := String(s["k"])
	return CropModel.yield_forecast_ratio(s, CropModel.spec(key), key)


## Zakrslost porostu pole 0..SHORT_MAX (řádek 1 LUT, kanál B – shader vegetace zkrátí obilí).
func _short_of(id: int) -> float:
	if not _eco_on():
		return 0.0
	var s := field_info(id)
	if s.is_empty() or int(s.get("st", 0)) == CropModel.ST_GERM or int(s.get("harv", -1)) >= 0:
		return 0.0
	return clampf(1.0 - CropModel.vigor(s, String(s["k"])), 0.0, SHORT_MAX)


## Barva pole s modelem: kalendář plodiny ve „fenologickém“ dni (normál se stejnou sumou teplot), po sklizni dny od
## skutečné sklizně, suchem žlutější. Pole bez stavu modelu (pícniny, před výsevem) = kalendář jako dřív.
func field_state_eco(id: int, doy: float, year: int) -> PackedFloat32Array:
	var e: Dictionary = eco.get(id, {})
	var cur: Dictionary = e.get("cur", {})
	if cur.is_empty() or int(cur.get("y", 0)) != year or not CROPS.has(String(cur["k"])):
		return field_state(id, doy, year)
	var key := String(cur["k"])
	var sp := CropModel.spec(key)
	var zne := float(sp.get("zne_doy", 210))
	var eff: float
	if int(cur.get("harv", -1)) >= 0:
		eff = zne + 1.0 + maxf(doy - float(cur["harv"]), 0.0)
	else:
		var c := CropModel.clim(key)
		var idx := CropModel.clim_index_for_gdd(c, float(cur.get("gdd", 0.0)))
		eff = float(cur["sow"]) + float(idx) - (365.0 if bool(sp.get("ozim", false)) else 0.0)
		eff = clampf(eff, 1.0, zne - 1.0)
	var s := _sample(CROPS[key]["cal"], clampf(eff, 1.0, 366.0))
	if int(cur.get("harv", -1)) < 0 and int(cur.get("st", 0)) >= CropModel.ST_VEG:
		var y := DRY_YELLOW_K * clampf((DRY_YELLOW_FROM - float(cur.get("wa", 1.0))) / maxf(DRY_YELLOW_FROM, 0.01), 0.0, 1.0)
		s[0] = lerpf(s[0], STRAW.r, y)
		s[1] = lerpf(s[1], STRAW.g, y)
		s[2] = lerpf(s[2], STRAW.b, y)
	s = _autumn(s, id, doy, year)
	return s


static func _doy_text(year: int, doy: float) -> String:
	var d := Clock.from_jdn(Clock.jdn(year, 1, 1) + int(doy) - 1)
	return "%d. %d." % [int(d["day"]), int(d["month"])]


## Deník J: „Letošní úroda: suchý červen, brambory slabá úroda (60 %), obilí se začalo žnout 12. 7.“ ("" vypnuto / bez dat).
func journal_line() -> String:
	if not _eco_on() or world.clock == null:
		return ""
	var year := world.clock.year()
	var lg: Dictionary = year_log.get(str(year), {})
	if lg.is_empty():
		return ""
	var parts: Array[String] = []
	var mo: Dictionary = lg.get("m", {})
	for mk in range(3, 11):
		var a: Array = mo.get(str(mk), [0.0, 0])
		if int(a[1]) < 10:
			continue
		var avg := float(a[0]) / float(a[1])
		if avg < MOIST_DRY_MONTH:
			parts.append("suchý %s" % Clock.MONTHS_1[mk - 1])
		elif avg > MOIST_WET_MONTH:
			parts.append("mokrý %s" % Clock.MONTHS_1[mk - 1])
	var h: Dictionary = lg.get("h", {})
	var grain := INF
	for key in h:
		var a: Array = h[key]
		var r := float(a[0]) / maxf(float(a[1]), 1.0)
		var sp := CropModel.spec(String(key))
		var nm := String(sp.get("nazev", key)).to_lower()
		if r < RATIO_WEAK:
			parts.append("%s slabá úroda (%d %%)" % [nm, roundi(r * 100.0)])
		elif r > RATIO_RICH:
			parts.append("%s bohatá úroda (%d %%)" % [nm, roundi(r * 100.0)])
		if String(key) == "psenice" or String(key) == "jecmen":
			grain = minf(grain, float(a[2]))
	if grain < INF:
		parts.append("obilí se začalo žnout %s" % _doy_text(year, grain))
	if parts.is_empty():
		return "Letošní úroda: zatím běžný rok."
	return "Letošní úroda: %s." % ", ".join(parts)


# ------------------------------------------------------------------ M8.12: ukládání (klíč `fields_eco`)

func to_dict() -> Dictionary:
	var out := {}
	for id in eco:
		out[str(id)] = eco[id]
	return {"eco": out, "last_jd": _last_jd, "log": year_log}


## Starý save bez klíče = stav polí podle normálu k dnešku (`_init_from_clim`).
func restore(d: Dictionary) -> void:
	if world == null or not loaded:
		return
	if not d.has("eco"):
		_init_from_clim()
		return
	eco.clear()
	var src: Dictionary = d.get("eco", {})
	for k in src:
		var e: Dictionary = src[k]
		eco[int(k)] = {"cur": e.get("cur", {}), "nxt": e.get("nxt", {})}
	_last_jd = int(d.get("last_jd", world.clock.jd() if world.clock else -1))
	year_log = d.get("log", {})
	for id in range(1, 256):
		if _cn[id] > 0:
			_refresh_height(id)
	lut_gen += 1
