## Pole a louky podle kalendáře: mapa využití ploch (data/landuse.bin z tools/landuse.py, zdroj OSM)
## a tabulka plodin `CROPS` s barvami polí po celý rok.
##
## - `class_at(x, z)` / `field_at(x, z)` – třída plochy (1 orná půda, 2 louka, 3 sad, 4 zahrádky) a číslo pole
## - plodina každého pole je deterministická podle (číslo pole, rok) s váhami osevního postupu (`weight`)
## - `lut_image(doy, year)` – tabulka 256×2 px pro shader terénu: řádek 0 = barva plodiny (lineární RGB)
##   + síla přimíchání, řádek 1 = síla rýh po orbě a směr rýh
## Terénní shader (shaders/terrain.gdshader) podle toho pole přebarvuje; louky dostávají jen květy (`meadow_bloom`).
class_name Fields
extends RefCounted

const PATH := "res://data/landuse.bin"
const HEADER := 28                   # magic(4) + verze(4) + x0, z0, cell (12) + nx, nz (8)

## Plodiny. `cal` = kalendář [den v roce, Color(r, g, b, síla přimíchání), rýhy 0..1 (nepovinné)]
## s lineární interpolací mezi řádky (barvy v sRGB, do shaderu jdou převedené na lineární).
## Ozimé plodiny (`winter`) jsou na jaře už zelené; `sown` = barva vzcházejících semínek na podzim.
## Žně a další termíny se u každého pole posouvají o ±`DATE_SPREAD` dní.
const DATE_SPREAD := 6
const CROPS := {
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
	# na podzim se po podmítce zelenají vzcházející ozimy příští plodiny
	if doy > 275.0:
		var nspec: Dictionary = CROPS[crop_of(id, year + 1)]
		if nspec.get("winter", false):
			var sown: Color = nspec["sown"]
			var t := smoothstep(275.0, 305.0, doy)
			s[0] = lerpf(s[0], sown.r, t)
			s[1] = lerpf(s[1], sown.g, t)
			s[2] = lerpf(s[2], sown.b, t)
			s[3] = lerpf(s[3], sown.a, t)
			s[4] = lerpf(s[4], 0.0, t)
	return s


## Tabulka 256×2 pro terénní shader (RGBA8, lineární barvy): řádek 0 = barva + síla, řádek 1 = rýhy, směr rýh.
func lut_image(doy: float, year: int) -> Image:
	var img := Image.create(256, 2, false, Image.FORMAT_RGBA8)
	for id in range(1, 256):
		var s := field_state(id, doy, year)
		var c := Color(s[0], s[1], s[2]).srgb_to_linear()
		img.set_pixel(id, 0, Color(c.r, c.g, c.b, s[3]))
		img.set_pixel(id, 1, Color(s[4], float(_hash(id, 3) % 2), 0.0, 1.0))
	return img
