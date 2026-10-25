## Procedurální textury pro materiály bez staženích textur (Poly Haven v checkoutu nejsou, viz ASSETY.md).
## Jedna sdílená bezešvá RGBA textura šumů 256 × 256 (mipmapy, opakování) – shader z ní čte několik druhů
## šumu jedním čtením:
##   R = buněčný šum, hodnota buňky (kamínky, tašky, záplaty – náhodný jas na buňku)
##   G = fbm simplex nízké frekvence (skvrny, opotřebení, mapy výskytu)
##   B = buněčný šum F2 − F1 (≈ 0 na hranicích buněk → praskliny, spáry mezi kamínky)
##   A = fbm simplex střední frekvence (zrnitost omítky, roztřepené okraje)
## Generuje se jednou (≈ desítky ms) a sdílí se mezi všemi materiály.
class_name ProcTextures
extends RefCounted

const SIZE := 256

static var _noise_rgba: ImageTexture = null


## Sdílená RGBA textura šumů (viz popis třídy). Bezpečné volat opakovaně.
static func noise_rgba() -> ImageTexture:
	if _noise_rgba != null:
		return _noise_rgba
	var chans: Array[PackedByteArray] = []
	# R: hodnota buňky (~42 buněk na dlaždici)
	chans.append(_channel(FastNoiseLite.TYPE_CELLULAR, 1.0 / 6.0, 1, 11,
		FastNoiseLite.RETURN_CELL_VALUE))
	# G: nízkofrekvenční fbm
	chans.append(_channel(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0 / 64.0, 5, 23))
	# B: hranice buněk (F2 − F1) – trochu větší buňky než R
	chans.append(_channel(FastNoiseLite.TYPE_CELLULAR, 1.0 / 10.0, 1, 37,
		FastNoiseLite.RETURN_DISTANCE2_SUB))
	# A: středofrekvenční fbm
	chans.append(_channel(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0 / 14.0, 3, 51))
	var n := SIZE * SIZE
	var out := PackedByteArray()
	out.resize(n * 4)
	for c in 4:
		var src: PackedByteArray = chans[c]
		var o := c
		for i in n:
			out[o] = src[i]
			o += 4
	var img := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGBA8, out)
	img.generate_mipmaps()
	_noise_rgba = ImageTexture.create_from_image(img)
	return _noise_rgba


## Jeden kanál: bezešvý obraz šumu (L8, normalizovaný 0–255) jako pole bajtů.
static func _channel(kind: int, freq: float, octaves: int, seed_: int, ret := -1) -> PackedByteArray:
	var fn := FastNoiseLite.new()
	fn.noise_type = kind
	fn.frequency = freq
	fn.seed = seed_
	if octaves > 1:
		fn.fractal_type = FastNoiseLite.FRACTAL_FBM
		fn.fractal_octaves = octaves
	else:
		fn.fractal_type = FastNoiseLite.FRACTAL_NONE
	if ret >= 0:
		fn.cellular_return_type = ret
		fn.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
		fn.cellular_jitter = 0.9
	var img := fn.get_seamless_image(SIZE, SIZE, false, false, 0.1, true)
	if img.get_format() != Image.FORMAT_L8:
		img.convert(Image.FORMAT_L8)
	return img.get_data()
