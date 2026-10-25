## Vegetace katastru (Fáze 9 – §9): trsy vysoké trávy na loukách, kopřivy u cest a v lese,
## lískové keře a trnky v podrostu a na mezích, obilné řádky s klasy na polích, plevel
## a zahrádkové rostliny u domů. Statické body generuje offline tools/vegetation.py do
## `data/vegetation.bin` (formát a třídy viz hlavička nástroje) – načte se při stavbě světa
## do MultiMeshů po chunkách CHUNK m; nerostou na vozovkách, dvorech, březích ani mimo katastr.
##
## LOD: každá buňka × typ má vlastní MultiMeshInstance3D; `update(pos, …)` zapíná/vypíná
## celé chunky podle vzdálenosti hráče k AABB buňky (`view_range` na typ – keře dohlédnou
## dál než tráva). `detail` (Nastavení → Grafika → Vegetace) dosah násobí, 0 = vypnuto.
## 2026-10: uvnitř dosahu instance plynule mizí (shader, `veg_fade_end` = dosah − FADE_MARGIN, mez podle hashe
## instance 0,6–1 ×) – hustota do dálky řídne a zapnutí chunku není vidět; stíny jen od Vysoké (`SHADOW_Q`).
##
## Vítr: `_process` nastaví všem materiálům `wind_strength` z `Weather.wind_vector()` (stará cesta; M8.4: směr,
## rychlost a nárazy jsou globální uniformy `wind_*` z `World.wind_field`, nastavuje Atmosphere)
## (clamp /10 → 0..2, §9.4). Sezóny řeší shader přes globální parametry (grass_green, foliage,
## snow_cover) a pro obilí tabulku `field_lut` (Fields.lut_image – klasy zrají a po žních
## strniště zůstane). Chybí-li vegetation.bin, jen varování – svět běží bez vegetace.
##
## M8.14 Přízemní vegetace: formát `VEG2` (`tools/vegetation.py --eco`, `VEG1` dál funguje) přidává typy podle
## stanoviště a druhu stromu nad nimi (vlhká / suchá louka, kapradí, borůvčí, mech, jarní byliny, hrabanka a jehličí,
## devětsil). Nové modely mají barvy vrcholů podle 00_PRINCIPY kap. 4 a albedo z uniformů (`color`, `lo`, `hi`, `acc`
## ve `VEG_CONFIG`); bez `.res` je postaví `GroundVegMeshes`. Klíče `mow` / `path` / `trample` říkají, jak typ reaguje
## na seč louky (`Meadows` → `meadow_h`), pěšiny (`Footpaths` → `path_tex`) a sešlapání (`GroundVegFx` → `trample_src`).
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
	GARDEN_VEG,      # 6 zahrádkové rostliny u domů
	HERB_WET,        # 7 M8.14 vlhká louka (pcháč, kohoutek, tužebník)
	HERB_DRY,        # 8 M8.14 suchá stráň (šalvěj, mateřídouška)
	FERN,            # 9 M8.14 kapradí (smrčina, stinný les)
	BILBERRY,        # 10 M8.14 borůvčí (smrk, borovice)
	MOSS,            # 11 M8.14 mech (smrčina)
	SPRING_FLOWERS,  # 12 M8.14 jarní podrost (dub, habr, lípa – sasanky, dymnivky)
	LITTER,          # 13 M8.14 hrabanka (buk) / jehličí (smrk) – barva v tintu instance
	BUTTERBUR,       # 14 M8.14 devětsil a kopřivy v olšině u potoka
	ROSEHIP          # 15 M8.14 šípek – keř sukcese (jen GroundVegFx, ne ve vegetation.bin)
}
const MAX_TYPE := VegType.ROSEHIP

## mesh = model z tools/gen_vegetation_meshes.gd; density_per_m2 ≈ efektivní hustota ve
## výchozím roce (rozmístění určuje tools/vegetation.py); view_range = dosah LOD (m);
## bend_k = citlivost na vítr; season_mode: 0 bylina, 1 keř, 2 plodina (field_lut).
## M8.D2c: `static var` – `bend_k` laditelné v F3 → Příroda/Dřeviny a les (uniform materiálu, bez úpravy shaderu).
static var VEG_CONFIG := {
	# 2026-10: i původní typy staví GroundVegMeshes (stébla, listy, karty listí) – barvy z `lo` / `hi` / `acc`
	VegType.GRASS_TALL: {"mesh": "res://assets/models/vegetation/grass_tall.res", "gen": "grass_tall",
		"density_per_m2": 0.004, "max_instances": 30000, "view_range": 95.0,
		"bend_k": 1.5, "season_mode": 0, "shader_param": "wind_strength",
		"color": 1, "lo": Color(0.11, 0.22, 0.06), "hi": Color(0.40, 0.53, 0.19), "acc": Color(0.50, 0.44, 0.33)},
	VegType.NETTLE: {"mesh": "res://assets/models/vegetation/nettle.res", "gen": "nettle",
		"density_per_m2": 0.01, "max_instances": 8000, "view_range": 80.0,
		"bend_k": 1.1, "season_mode": 0, "shader_param": "wind_strength",
		"color": 1, "lo": Color(0.06, 0.16, 0.05), "hi": Color(0.17, 0.34, 0.11), "acc": Color(0.30, 0.38, 0.16)},
	VegType.BUSH_HAZEL: {"mesh": "res://assets/models/vegetation/bush_hazel.res", "gen": "bush_hazel",
		"density_per_m2": 0.004, "max_instances": 6000, "view_range": 220.0,
		"bend_k": 0.35, "season_mode": 1, "shader_param": "wind_strength",
		"color": 1, "lo": Color(0.10, 0.20, 0.07), "hi": Color(0.27, 0.43, 0.15), "acc": Color(0.45, 0.32, 0.18)},
	VegType.BUSH_BLACKTHORN: {"mesh": "res://assets/models/vegetation/bush_blackthorn.res", "gen": "bush_blackthorn",
		"density_per_m2": 0.002, "max_instances": 4000, "view_range": 220.0,
		"bend_k": 0.3, "season_mode": 1, "shader_param": "wind_strength",
		"color": 1, "lo": Color(0.09, 0.15, 0.07), "hi": Color(0.21, 0.33, 0.15), "acc": Color(0.16, 0.18, 0.32)},
	VegType.CROP_WHEAT: {"mesh": "res://assets/models/vegetation/wheat.res", "gen": "wheat",
		"density_per_m2": 0.02, "max_instances": 24000, "view_range": 130.0,
		"bend_k": 1.3, "season_mode": 2, "shader_param": "wind_strength",
		"color": 1, "lo": Color(0.28, 0.38, 0.12), "hi": Color(0.52, 0.50, 0.19), "acc": Color(0.70, 0.57, 0.23)},
	VegType.WEED_FIELD: {"mesh": "res://assets/models/vegetation/weed_field.res", "gen": "weed_field",
		"density_per_m2": 0.006, "max_instances": 9000, "view_range": 75.0,
		"bend_k": 1.2, "season_mode": 0, "shader_param": "wind_strength",
		"color": 1, "lo": Color(0.13, 0.25, 0.08), "hi": Color(0.32, 0.40, 0.14), "acc": Color(0.92, 0.80, 0.18), "petal": 1},
	VegType.GARDEN_VEG: {"mesh": "res://assets/models/vegetation/garden_veg.res", "gen": "garden_veg",
		"density_per_m2": 0.05, "max_instances": 5000, "view_range": 75.0,
		"bend_k": 1.0, "season_mode": 0, "shader_param": "wind_strength",
		"color": 1, "lo": Color(0.10, 0.22, 0.07), "hi": Color(0.28, 0.44, 0.15), "acc": Color(0.78, 0.22, 0.08)},
	# M8.14 – nové typy (color 1 = barvy vrcholů podle kap. 4, albedo lo → hi po výšce, acc = květ / bobule;
	# `petal` = tvar okvětí ve vegetation.gdshader: 0 kopretina, 1 pryskyřník, 2 úbor, 3 pětičetný)
	VegType.HERB_WET: {"mesh": "res://assets/models/vegetation/herb_wet.res", "gen": "herb_wet",
		"density_per_m2": 0.004, "max_instances": 7000, "view_range": 90.0, "bend_k": 1.3, "season_mode": 0,
		"color": 1, "lo": Color(0.12, 0.24, 0.08), "hi": Color(0.34, 0.48, 0.20), "acc": Color(0.62, 0.30, 0.62), "petal": 2},
	VegType.HERB_DRY: {"mesh": "res://assets/models/vegetation/herb_dry.res", "gen": "herb_dry",
		"density_per_m2": 0.004, "max_instances": 7000, "view_range": 70.0, "bend_k": 1.2, "season_mode": 0,
		"color": 1, "lo": Color(0.26, 0.32, 0.14), "hi": Color(0.52, 0.56, 0.30), "acc": Color(0.50, 0.36, 0.72), "petal": 3},
	VegType.FERN: {"mesh": "res://assets/models/vegetation/fern.res", "gen": "fern",
		"density_per_m2": 0.003, "max_instances": 5000, "view_range": 90.0, "bend_k": 0.8, "season_mode": 1,
		"color": 1, "lo": Color(0.08, 0.20, 0.05), "hi": Color(0.26, 0.46, 0.14), "acc": Color(0.26, 0.46, 0.14)},
	VegType.BILBERRY: {"mesh": "res://assets/models/vegetation/bilberry.res", "gen": "bilberry",
		"density_per_m2": 0.004, "max_instances": 6000, "view_range": 70.0, "bend_k": 0.6, "season_mode": 1,
		"color": 1, "lo": Color(0.07, 0.18, 0.06), "hi": Color(0.18, 0.36, 0.12), "acc": Color(0.10, 0.12, 0.30)},
	VegType.MOSS: {"mesh": "res://assets/models/vegetation/moss.res", "gen": "moss",
		"density_per_m2": 0.003, "max_instances": 5000, "view_range": 55.0, "bend_k": 0.0, "season_mode": 4,
		"color": 1, "lo": Color(0.12, 0.24, 0.06), "hi": Color(0.30, 0.44, 0.10), "acc": Color(0.30, 0.44, 0.10)},
	VegType.SPRING_FLOWERS: {"mesh": "res://assets/models/vegetation/spring_flowers.res", "gen": "spring_flowers",
		"density_per_m2": 0.004, "max_instances": 6000, "view_range": 60.0, "bend_k": 0.9, "season_mode": 3,
		"color": 1, "lo": Color(0.12, 0.26, 0.08), "hi": Color(0.28, 0.46, 0.16), "acc": Color(0.92, 0.92, 0.88), "petal": 3},
	VegType.LITTER: {"mesh": "res://assets/models/vegetation/litter.res", "gen": "litter",
		"density_per_m2": 0.004, "max_instances": 6000, "view_range": 55.0, "bend_k": 0.0, "season_mode": 4,
		"color": 1, "lo": Color(0.42, 0.28, 0.15), "hi": Color(0.50, 0.34, 0.18), "acc": Color(0.50, 0.34, 0.18)},
	VegType.BUTTERBUR: {"mesh": "res://assets/models/vegetation/butterbur.res", "gen": "butterbur",
		"density_per_m2": 0.002, "max_instances": 2000, "view_range": 80.0, "bend_k": 0.7, "season_mode": 1,
		"color": 1, "lo": Color(0.10, 0.24, 0.07), "hi": Color(0.22, 0.42, 0.14), "acc": Color(0.22, 0.42, 0.14)},
	VegType.ROSEHIP: {"mesh": "res://assets/models/vegetation/rosehip.res", "gen": "rosehip",
		"density_per_m2": 0.0, "max_instances": 2000, "view_range": 220.0, "bend_k": 0.3, "season_mode": 1,
		"color": 1, "lo": Color(0.10, 0.18, 0.07), "hi": Color(0.24, 0.38, 0.14), "acc": Color(0.75, 0.10, 0.06)},
}
## 2026-10: od které hodnoty `gfx_quality` typ vrhá stín (2 Vysoká, 3 Ultra; chybí = nikdy). Instancí je málo
## (desítky až stovky v dosahu stínů), na Nízké a Střední se stínový průchod vegetace nekreslí vůbec.
static var SHADOW_Q := {
	VegType.BUSH_HAZEL: 2, VegType.BUSH_BLACKTHORN: 2, VegType.ROSEHIP: 2, VegType.FERN: 2, VegType.BUTTERBUR: 2,
	VegType.NETTLE: 2, VegType.HERB_WET: 2,
	VegType.GRASS_TALL: 3, VegType.CROP_WHEAT: 3, VegType.GARDEN_VEG: 3, VegType.BILBERRY: 3, VegType.HERB_DRY: 3,
	VegType.WEED_FIELD: 3,
}
## Rezerva (m) mezi plynulým zmizením instancí (`veg_fade_end`) a vypnutím chunku: kamera je kus od hráče
## a viditelnost chunků se přepočítává po 6 m pohybu – chunk se tak zapne dřív, než jeho instance „vyrostou“.
const FADE_MARGIN := 12.0

## M8.14: reakce typu na seč louky (`mow`), pěšiny (`path`) a sešlapání (`trample` – citlivost ohybu). Laditelné
## (F3 → Příroda/Louky a podrost); chybějící typ = 0.
static var REACT := {
	VegType.GRASS_TALL: {"mow": 1.0, "path": 1.0, "trample": 1.0},
	VegType.NETTLE: {"mow": 0.0, "path": 1.0, "trample": 0.7},
	VegType.BUSH_HAZEL: {"mow": 0.0, "path": 0.0, "trample": 0.12},
	VegType.BUSH_BLACKTHORN: {"mow": 0.0, "path": 0.0, "trample": 0.12},
	VegType.CROP_WHEAT: {"mow": 0.0, "path": 1.0, "trample": 0.9},
	VegType.WEED_FIELD: {"mow": 0.0, "path": 1.0, "trample": 0.8},
	VegType.GARDEN_VEG: {"mow": 0.0, "path": 0.0, "trample": 0.6},
	VegType.HERB_WET: {"mow": 1.0, "path": 1.0, "trample": 1.0},
	VegType.HERB_DRY: {"mow": 1.0, "path": 1.0, "trample": 0.9},
	VegType.FERN: {"mow": 0.0, "path": 1.0, "trample": 0.8},
	VegType.BILBERRY: {"mow": 0.0, "path": 1.0, "trample": 0.4},
	VegType.MOSS: {"mow": 0.0, "path": 1.0, "trample": 0.0},
	VegType.SPRING_FLOWERS: {"mow": 0.0, "path": 1.0, "trample": 0.8},
	VegType.LITTER: {"mow": 0.0, "path": 1.0, "trample": 0.0},
	VegType.BUTTERBUR: {"mow": 0.0, "path": 1.0, "trample": 0.6},
	VegType.ROSEHIP: {"mow": 0.0, "path": 0.0, "trample": 0.1},
}

## M8.D2c: stará cesta větru (`wind_strength` = vítr / WIND_FULL_MS, strop WIND_MAX) – laditelné.
static var WIND_FULL_MS := 10.0
static var WIND_MAX := 2.0
## M8.D2c: změna `bend_k` v menu F3 → materiály se přenastaví při nejbližším ticku větru.
static var _gen := 0
## Optimalizace GPU (17. 10. 2026): násobek dosahu všech chunků vegetace navíc k předvolbě (`detail`) – F3 →
## Svět/Vykreslování (`tune_m8_19.gd` zvýší `_gen`, viditelnost se přepočítá při nejbližším ticku větru).
static var RANGE_K := 1.0

var world: World
var terrain: Terrain
var loaded := false
var _seen_gen := 0
var total := 0
var detail := 1.0                     # 0 = vypnuto, jinak násobek dosahu (Nastavení → Grafika)
var multimeshes := {}                 # VegType → Array[MultiMeshInstance3D] (chunky)
var counts := {}                      # VegType → počet instancí
var _chunks: Array = []               # {mmi, min: Vector2, max: Vector2, range: float}
var _mats := {}                       # VegType → ShaderMaterial
var _wind_t := 0.0
var fx: GroundVegFx                   # M8.14


func set_detail(d: float) -> void:
	if is_equal_approx(d, detail):
		return
	detail = d
	_refresh_visibility(_last_pos)
	for typ in _mats:
		_apply_fade(typ)


func setup(w: World) -> void:
	world = w
	terrain = w.terrain
	name = "Vegetace"
	top_level = true
	_load_vegetation()
	fx = GroundVegFx.new()               # M8.14: sešlapání, výška louky (meadow_h), keře sukcese a seno – klient
	add_child(fx)
	fx.setup(w, self)


## Načte data/vegetation.bin a naplní chunky MultiMeshů. Bez souboru jen varování (hra běží).
func _load_vegetation() -> void:
	if not FileAccess.file_exists(PATH):
		push_warning("VegetationManager: chybí %s (tools/vegetation.py) – svět bez detailní vegetace" % PATH)
		return
	var b := FileAccess.get_file_as_bytes(PATH)
	var magic := b.slice(0, 4).get_string_from_ascii() if b.size() >= HEADER else ""
	if magic != "VEG1" and magic != "VEG2":            # M8.14: VEG2 = --eco (nové typy), záznam stejný
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
		if typ < 0 or typ > MAX_TYPE:
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
		mm.mesh = _mesh(typ)
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
			"range": float(VEG_CONFIG[typ]["view_range"]), "typ": typ})
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


## M8.D2c: po změně `bend_k` v menu F3.
static func invalidate() -> void:
	_gen += 1


## Model typu: `.res` z tools/gen_vegetation_meshes.gd, u typů M8.14 bez souboru postavený `GroundVegMeshes`.
static func mesh_of(typ: int) -> Mesh:
	var cfg: Dictionary = VEG_CONFIG[typ]
	var path := String(cfg["mesh"])
	if ResourceLoader.exists(path):
		return load(path)
	if cfg.has("gen"):
		return GroundVegMeshes.build(String(cfg["gen"]))
	return load(path)


var _mesh_cache := {}

func _mesh(typ: int) -> Mesh:
	if not _mesh_cache.has(typ):
		_mesh_cache[typ] = mesh_of(typ)
	return _mesh_cache[typ]


## ShaderMaterial typu – jeden na všechny chunky (uniform vítr/sezóna se nastavuje jednou).
## M8.14: veřejné i pro GroundVegFx (keře sukcese sdílí materiál trnky / šípku).
func material_for(typ: int) -> ShaderMaterial:
	return _material(typ)


func _material(typ: int) -> ShaderMaterial:
	if _mats.has(typ):
		return _mats[typ]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/vegetation.gdshader")
	_mats[typ] = m
	_apply_params(typ)
	if world != null and not _mats.is_empty() and terrain != null and terrain.material != null:
		var lut = terrain.material.get_shader_parameter("field_lut")
		if lut != null:
			m.set_shader_parameter("field_lut", lut)
	return m


## Uniformy typu z VEG_CONFIG / REACT (při stavbě a po změně v menu F3).
func _apply_params(typ: int) -> void:
	var m: ShaderMaterial = _mats.get(typ)
	if m == null:
		return
	var cfg: Dictionary = VEG_CONFIG[typ]
	m.set_shader_parameter("bend_k", cfg["bend_k"])
	m.set_shader_parameter("season_mode", cfg["season_mode"])
	m.set_shader_parameter("veg_color_mode", int(cfg.get("color", 0)))
	if cfg.has("lo"):
		m.set_shader_parameter("veg_lo", cfg["lo"])
		m.set_shader_parameter("veg_hi", cfg["hi"])
		m.set_shader_parameter("veg_acc", cfg["acc"])
	m.set_shader_parameter("veg_petal", float(cfg.get("petal", 0)))
	var re: Dictionary = REACT.get(typ, {})
	m.set_shader_parameter("veg_mow", float(re.get("mow", 0.0)))
	m.set_shader_parameter("veg_path", float(re.get("path", 0.0)))
	m.set_shader_parameter("veg_trample", float(re.get("trample", 0.0)))
	_apply_fade(typ)


## Plynulé mizení instancí do dálky: mez = dosah chunků typu (× detail × RANGE_K) − rezerva FADE_MARGIN.
func _apply_fade(typ: int) -> void:
	var m: ShaderMaterial = _mats.get(typ)
	if m == null:
		return
	var r := float(VEG_CONFIG[typ]["view_range"]) * detail * RANGE_K
	m.set_shader_parameter("veg_fade_end", maxf(r - FADE_MARGIN, r * 0.6))


## 2026-10: stíny vegetace podle předvolby (`gfx_quality`, SHADOW_Q) – kontrola při ticku větru, mění se jen při změně.
var _shadow_q := -1.0

func _update_shadows() -> void:
	var q := float(RenderingServer.global_shader_parameter_get("gfx_quality"))
	if is_equal_approx(q, _shadow_q):
		return
	_shadow_q = q
	for ch in _chunks:
		var need := int(SHADOW_Q.get(int(ch["typ"]), 99))
		(ch["mmi"] as MultiMeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON \
			if q >= float(need) - 0.5 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if fx != null:
		fx.set_shadows(q > 1.5)


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
		var r := float(ch["range"]) * detail * RANGE_K
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
	_update_shadows()
	if _seen_gen != _gen:                         # M8.D2c: změna citlivosti na vítr v menu F3
		_seen_gen = _gen
		for typ in _mats:
			_apply_params(typ)                    # M8.14: i barvy a reakce na seč / pěšiny / sešlapání
		_refresh_visibility(_last_pos)            # RANGE_K z F3
	var wind := Vector2.ZERO
	if world != null and world.weather != null:
		var wv: Vector3 = world.weather.wind_vector()
		wind = Vector2(wv.x, wv.z)
	var s := clampf(wind.length() / WIND_FULL_MS, 0.0, WIND_MAX)
	for m in _mats.values():
		var mat := m as ShaderMaterial
		mat.set_shader_parameter("wind_strength", s)


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
