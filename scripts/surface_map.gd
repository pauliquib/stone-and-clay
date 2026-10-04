## Maska povrchu terénu (data/surface.bin z tools/surface.py): třídy 0–7 v rastru 4 m.
## Používá ji shader terénu (textura R8) a minimapa (barvy tříd). Když soubor chybí, `loaded` = false a terén
## si třídu odvodí z landuse_tex + hustoty lesa (fallback), minimapa z `Fields` a `Fauna.forest_at`.
class_name SurfaceMap
extends RefCounted

const PATH := "res://data/surface.bin"
const HEADER := 28

const GRASS := 0
const ARABLE := 1
const ORCHARD := 2
const FOREST := 3
const YARD := 4
const BANK := 5
const ROCK := 6
const TRACK := 7

## Barvy tříd pro minimapu (sRGB).
const COLORS := [
	Color(0.47, 0.62, 0.30),   # tráva / louka
	Color(0.62, 0.50, 0.34),   # orná půda
	Color(0.52, 0.66, 0.32),   # sad / zahrada
	Color(0.20, 0.36, 0.20),   # les
	Color(0.70, 0.65, 0.56),   # zástavba / dvůr
	Color(0.42, 0.40, 0.30),   # břeh / mokřad
	Color(0.55, 0.53, 0.50),   # skála
	Color(0.68, 0.60, 0.46),   # polní cesta
]

var loaded := false
var x0 := 0.0
var z0 := 0.0
var cell := 4.0
var nx := 0
var nz := 0
var _data := PackedByteArray()


## Načte data/surface.bin. Vrací false, když chybí nebo je neplatný (hra pak použije fallback ve shaderu).
func load_data() -> bool:
	if not FileAccess.file_exists(PATH):
		push_warning("SurfaceMap: chybí %s (tools/surface.py) – terén použije odvozené třídy" % PATH)
		return false
	var b := FileAccess.get_file_as_bytes(PATH)
	if b.size() < HEADER or b.slice(0, 4).get_string_from_ascii() != "SURF":
		push_warning("SurfaceMap: neznámý formát surface.bin")
		return false
	x0 = b.decode_float(8)
	z0 = b.decode_float(12)
	cell = b.decode_float(16)
	nx = b.decode_s32(20)
	nz = b.decode_s32(24)
	if nx <= 0 or nz <= 0 or b.size() < HEADER + nx * nz:
		push_warning("SurfaceMap: surface.bin je useknutý")
		return false
	_data = b.slice(HEADER, HEADER + nx * nz)
	loaded = true
	return true


## Rastr jako R8 textura pro shader (`surface_tex`).
func make_texture() -> ImageTexture:
	return ImageTexture.create_from_image(Image.create_from_data(nx, nz, false, Image.FORMAT_R8, _data))


## (x0, z0, šířka, výška) v metrech – pro uniform `surface_rect`.
func rect() -> Vector4:
	return Vector4(x0, z0, nx * cell, nz * cell)


## Třída povrchu v bodě (0 mimo mapu i bez dat).
func class_at(x: float, z: float) -> int:
	if not loaded:
		return 0
	var ix := floori((x - x0) / cell)
	var iz := floori((z - z0) / cell)
	if ix < 0 or iz < 0 or ix >= nx or iz >= nz:
		return 0
	return _data[iz * nx + ix]


## Obrázek minimapy přes obdélník `area` (metry: x0, z0, šířka, výška) s krokem `step` m. Barvy tříd + jednoduché
## stínování reliéfu. Bez surface.bin se třída odvodí z `fields` (orná půda, sady) a `fauna.forest_at` (les).
static func make_map_image(sm: SurfaceMap, area: Rect2, step: float, terrain: Terrain, fields: Fields, fauna: Fauna) -> Image:
	var w := int(ceil(area.size.x / step))
	var h := int(ceil(area.size.y / step))
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for j in h:
		var z := area.position.y + (j + 0.5) * step
		for i in w:
			var x := area.position.x + (i + 0.5) * step
			var c := GRASS
			if sm != null and sm.loaded:
				c = sm.class_at(x, z)
			else:
				if fields != null and fields.loaded:
					var fc := fields.class_at(x, z)
					if fc == 1:
						c = ARABLE
					elif fc >= 3:
						c = ORCHARD
				if fauna != null and fauna.forest_at(x, z) > 0.5:
					c = FOREST
			var col: Color = COLORS[c]
			if terrain != null and terrain.contains(x, z, 6.0):
				var h0 := terrain.height_at(x, z)
				var sh := (h0 - terrain.height_at(x + step, z)) + (h0 - terrain.height_at(x, z + step))
				col = col * clampf(1.0 + sh * 0.05, 0.7, 1.25)
				col.a = 1.0
			img.set_pixel(i, j, col)
	return img
