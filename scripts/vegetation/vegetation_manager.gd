## Vegetace katastru (Fáze 9 – §9): trsy vysoké trávy na loukách, kopřivy u cest a v lese,
## lískové keře a trnky v podrostu a na mezích, obilné řádky s klasy na polích, plevel
## a zahrádkové rostliny u domů. Statické body generuje offline tools/vegetation.py do
## `data/vegetation.bin` (formát a třídy viz hlavička nástroje) – načte se při stavbě světa
## do MultiMeshů po chunkách CHUNK m; nerostou na vozovkách, dvorech, březích ani mimo katastr.
##
## LOD: každá buňka × typ má vlastní MultiMeshInstance3D; `update(pos, …)` zapíná/vypíná
## celé chunky podle vzdálenosti hráče k AABB buňky (`view_range` na typ – keře dohlédnou
## dál než tráva). `detail` (Nastavení → Grafika → Vegetace) dosah násobí, 0 = vypnuto.
##
## Vítr: `_process` nastaví všem materiálům `wind_strength`/`wind_dir` z `Weather.wind_vector()`
## (clamp /10 → 0..2, §9.4). Sezóny řeší shader přes globální parametry (grass_green, foliage,
## snow_cover) a pro obilí tabulku `field_lut` (Fields.lut_image – klasy zrají a po žních
## strniště zůstane). Chybí-li vegetation.bin, jen varování – svět běží bez vegetace.
class_name VegetationManager
extends Node3D

const PATH := "res://data/vegetation.bin"
const HEADER := 12               # magic(4) + verze(4) + počet(4)
const RECORD := 28               # i32 typ, f32 x,y,z, f32 rot, f32 scale, u8 r,g,b,aux
const CHUNK := 64.0              # buňka LOD (m)
const WIND_TICK := 0.2           # s – jak často se přepočítává vítr

enum VegType {
	GRASS_TALL,      # 0 vysoká tráva na loukách
	NETTLE,          # 1 kopřivy u cest a na okrajích lesa
	BUSH_HAZEL,      # 2 lískové keře v podrostu
	BUSH_BLACKTHORN, # 3 trnky na mezích a okrajích cest
	CROP_WHEAT,      # 4 obilné klasy v řádcích (pole s obilninou)
	WEED_FIELD,      # 5 plevel v řádcích
	GARDEN_VEG       # 6 zahrádkové rostliny u domů
}

## mesh = model z tools/gen_vegetation_meshes.gd; density_per_m2 ≈ efektivní hustota ve
## výchozím roce (rozmístění určuje tools/vegetation.py); view_range = dosah LOD (m);
## bend_k = citlivost na vítr; season_mode: 0 bylina, 1 keř, 2 plodina (field_lut).
const VEG_CONFIG := {
	VegType.GRASS_TALL: {"mesh": "res://assets/models/vegetation/grass_tall.res",
		"density_per_m2": 0.004, "max_instances": 30000, "view_range": 95.0,
		"bend_k": 1.5, "season_mode": 0, "shader_param": "wind_strength"},
	VegType.NETTLE: {"mesh": "res://assets/models/vegetation/nettle.res",
		"density_per_m2": 0.01, "max_instances": 8000, "view_range": 80.0,
		"bend_k": 1.1, "season_mode": 0, "shader_param": "wind_strength"},
	VegType.BUSH_HAZEL: {"mesh": "res://assets/models/vegetation/bush_hazel.res",
		"density_per_m2": 0.004, "max_instances": 6000, "view_range": 220.0,
		"bend_k": 0.35, "season_mode": 1, "shader_param": "wind_strength"},
	VegType.BUSH_BLACKTHORN: {"mesh": "res://assets/models/vegetation/bush_blackthorn.res",
		"density_per_m2": 0.002, "max_instances": 4000, "view_range": 220.0,
		"bend_k": 0.3, "season_mode": 1, "shader_param": "wind_strength"},
	VegType.CROP_WHEAT: {"mesh": "res://assets/models/vegetation/wheat.res",
		"density_per_m2": 0.02, "max_instances": 24000, "view_range": 130.0,
		"bend_k": 1.3, "season_mode": 2, "shader_param": "wind_strength"},
	VegType.WEED_FIELD: {"mesh": "res://assets/models/vegetation/weed_field.res",
		"density_per_m2": 0.006, "max_instances": 9000, "view_range": 75.0,
		"bend_k": 1.2, "season_mode": 0, "shader_param": "wind_strength"},
	VegType.GARDEN_VEG: {"mesh": "res://assets/models/vegetation/garden_veg.res",
		"density_per_m2": 0.05, "max_instances": 5000, "view_range": 75.0,
		"bend_k": 1.0, "season_mode": 0, "shader_param": "wind_strength"},
}

var world: World
var terrain: Terrain
var loaded := false
var total := 0
var detail := 1.0                     # 0 = vypnuto, jinak násobek dosahu (Nastavení → Grafika)
var multimeshes := {}                 # VegType → Array[MultiMeshInstance3D] (chunky)
var counts := {}                      # VegType → počet instancí
var _chunks: Array = []               # {mmi, min: Vector2, max: Vector2, range: float}
var _mats := {}                       # VegType → ShaderMaterial
var _wind_t := 0.0


func set_detail(d: float) -> void:
	if is_equal_approx(d, detail):
		return
	detail = d
	_refresh_visibility(_last_pos)


func setup(w: World) -> void:
	world = w
	terrain = w.terrain
	name = "Vegetace"
	top_level = true
	_load_vegetation()


## Načte data/vegetation.bin a naplní chunky MultiMeshů. Bez souboru jen varování (hra běží).
func _load_vegetation() -> void:
	if not FileAccess.file_exists(PATH):
		push_warning("VegetationManager: chybí %s (tools/vegetation.py) – svět bez detailní vegetace" % PATH)
		return
	var b := FileAccess.get_file_as_bytes(PATH)
	if b.size() < HEADER or b.slice(0, 4).get_string_from_ascii() != "VEG1":
		push_warning("VegetationManager: neznámý formát vegetation.bin")
		return
	var n := b.decode_s32(8)
	if n <= 0 or b.size() < HEADER + n * RECORD:
		push_warning("VegetationManager: vegetation.bin je useknutý")
		return

	# seskupit podle (typ, chunk)
	var groups := {}               # [typ, Vector2i] → {"xf": [], "col": []}
	for i in n:
		var o := HEADER + i * RECORD
		var typ := b.decode_s32(o)
		if typ < 0 or typ > VegType.GARDEN_VEG:
			continue
		var x := b.decode_float(o + 4)
		var y := b.decode_float(o + 8)
		var z := b.decode_float(o + 12)
		var rot := b.decode_float(o + 16)
		var sc := b.decode_float(o + 20)
		var pk := b.decode_u32(o + 24)        # r | g<<8 | b<<16 | aux<<24
		var key := [typ, Vector2i(floori(x / CHUNK), floori(z / CHUNK))]
		if not groups.has(key):
			groups[key] = {"xf": [], "col": []}
		var g: Dictionary = groups[key]
		g["xf"].append(Transform3D(Basis(Vector3.UP, rot) * Basis.from_scale(Vector3.ONE * sc),
			Vector3(x, y, z)))
		var f := 1.0 / 255.0
		g["col"].append(Color((pk & 0xff) * f, ((pk >> 8) & 0xff) * f, ((pk >> 16) & 0xff) * f,
			((pk >> 24) & 0xff) * f))

	# postavit MultiMeshInstance3D pro každý chunk
	for key in groups:
		var typ: int = key[0]
		var g: Dictionary = groups[key]
		var xforms: Array = g["xf"]
		if xforms.size() > int(VEG_CONFIG[typ]["max_instances"]):
			xforms.resize(int(VEG_CONFIG[typ]["max_instances"]))
			g["col"].resize(xforms.size())
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true               # rgb = tint, a = číslo pole (plodiny)
		mm.mesh = load(String(VEG_CONFIG[typ]["mesh"]))
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i])
			mm.set_instance_custom_data(i, (g["col"] as Array)[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.material_override = _material(typ)
		mmi.visible = false                       # zapne až první LOD update(pos) od SeasonFx
		var c: Vector2i = key[1]
		var mn := Vector2(c.x * CHUNK, c.y * CHUNK)
		var aabb := AABB(Vector3(mn.x, -500.0, mn.y), Vector3(CHUNK, 4000.0, CHUNK))
		mmi.custom_aabb = aabb                  # instance drží světové souřadnice, uzel je v počátku
		add_child(mmi)
		_chunks.append({"mmi": mmi, "min": mn, "max": mn + Vector2(CHUNK, CHUNK),
			"range": float(VEG_CONFIG[typ]["view_range"])})
		if not multimeshes.has(typ):
			multimeshes[typ] = []
		multimeshes[typ].append(mmi)
		counts[typ] = int(counts.get(typ, 0)) + mm.instance_count
		total += mm.instance_count

	# obilí: tabulka barev polí, když už ji terén má (SeasonFx ji pak aktualizuje přes set_field_lut)
	if terrain != null and terrain.material != null:
		var lut = terrain.material.get_shader_parameter("field_lut")
		if lut != null:
			set_field_lut(lut)
	loaded = true


## ShaderMaterial typu – jeden na všechny chunky (uniform vítr/sezóna se nastavuje jednou).
func _material(typ: int) -> ShaderMaterial:
	if _mats.has(typ):
		return _mats[typ]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/vegetation.gdshader")
	m.set_shader_parameter("bend_k", VEG_CONFIG[typ]["bend_k"])
	m.set_shader_parameter("season_mode", VEG_CONFIG[typ]["season_mode"])
	m.set_shader_parameter("wind_dir", Vector2(0.8, 0.5))
	_mats[typ] = m
	return m


## Tabulka barev/stavu polí (Fields.lut_image jako ImageTexture) pro plodiny (season_mode 2).
func set_field_lut(tex: Texture2D) -> void:
	for m in _mats.values():
		(m as ShaderMaterial).set_shader_parameter("field_lut", tex)


## LOD: přepočet viditelnosti chunků podle vzdálenosti hráče k AABB buňky.
## Volá SeasonFx (párkrát za sekundu) s polohou hráče; doy/snow drží globální uniformy.
var _last_pos := Vector3(1e9, 0, 1e9)

func update(pos: Vector3, _doy := 0.0, _snow := 0.0) -> void:
	if not loaded:
		return
	if Vector2(pos.x - _last_pos.x, pos.z - _last_pos.z).length() < 6.0:
		return
	_last_pos = pos
	_refresh_visibility(pos)


func _refresh_visibility(pos: Vector3) -> void:
	var p := Vector2(pos.x, pos.z)
	var on := detail > 0.0
	for ch in _chunks:
		var mmi: MultiMeshInstance3D = ch["mmi"]
		var mn: Vector2 = ch["min"]
		var mx: Vector2 = ch["max"]
		var dx := maxf(mn.x - p.x, maxf(0.0, p.x - mx.x))
		var dz := maxf(mn.y - p.y, maxf(0.0, p.y - mx.y))
		var r := float(ch["range"]) * detail
		mmi.visible = on and dx * dx + dz * dz <= r * r


func _process(delta: float) -> void:
	var __t0 := Tests.prof_t0()
	_process_impl(delta)
	Tests.prof_add("veg", __t0)


func _process_impl(delta: float) -> void:
	if not loaded or _mats.is_empty():
		return
	_wind_t -= delta
	if _wind_t > 0.0:
		return
	_wind_t = WIND_TICK
	var wind := Vector2.ZERO
	if world != null and world.weather != null:
		var wv: Vector3 = world.weather.wind_vector()
		wind = Vector2(wv.x, wv.z)
	var s := clampf(wind.length() / 10.0, 0.0, 2.0)
	var dir := wind.normalized() if wind.length() > 0.01 else Vector2(0.8, 0.5)
	for m in _mats.values():
		var mat := m as ShaderMaterial
		mat.set_shader_parameter("wind_strength", s)
		mat.set_shader_parameter("wind_dir", dir)


# ------------------------------------------------------------------ testy / ladění

## Kolik chunků daného typu je viditelných (−1 = všechny typy dohromady).
func visible_chunks(typ := -1) -> int:
	var n := 0
	for ch in _chunks:
		var mmi: MultiMeshInstance3D = ch["mmi"]
		if typ >= 0 and mmi.material_override != _mats.get(typ):
			continue
		if mmi.visible:
			n += 1
	return n


func chunk_count() -> int:
	return _chunks.size()


func instance_count(typ: int) -> int:
	return int(counts.get(typ, 0))


## Aktuálně nastavená síla větru v materiálech (pro test).
func wind_uniform() -> float:
	if _mats.is_empty():
		return -1.0
	return float((_mats.values()[0] as ShaderMaterial).get_shader_parameter("wind_strength"))
