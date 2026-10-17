## M8.8 Generované stromy: modely podle druhu, věku a vitality z `data/tree_species_protos.bin` (DBT2, `tools/treegen/`),
## LOD0 / LOD1 zblízka (streamované po buňkách, `TreeLodStreamer`) a impostory v dálce (jeden MultiMesh na buňku 256 m).
## Podle čeho: space colonization (Runions et al. 2007) / přeslenový růst, Weber & Penn 1995, oktaedrické / více-pohledové
## impostory (zjednodušeně 8 pohledů kolem osy Y) – viz hlavička `tools/treegen/treegen.py`.
##
## Vstup za běhu: `trees.bin` (poloha, natočení, měřítko, barva z ortofota) + `tree_eco.bin` (M8.3: druh, věk, vitalita –
## čte se přímo, protože `TreeEco` vzniká až po indexu stromů). Bez `tree_eco.bin` druh z prototypu (`TreeEco.FALLBACK_PROTO`).
## Index pro `TreeManager` (kácení, uložené pokácené stromy) má stejný tvar jako u `MapLoader.build_trees`:
## i → [nkey, varianta, near_idx, fkey, "imp", far_idx, trunk_idx]; near_mm[[nkey, varianta]] = [MultiMesh LOD1, LOD0]
## (null, dokud buňku streamer nepostavil), far_mm[[fkey, "imp"]] = impostory. Čísla stromů = pořadí v trees.bin.
##
## Přepínač: realismus „treegen“ (Esc → Nastavení → Realismus; projeví se po novém načtení světa). Bez souboru nebo
## vypnuto = `MapLoader.build_trees` jako dřív (6 prototypů DBT1).
class_name TreeGen
extends RefCounted

const PATH := "res://data/tree_species_protos.bin"
const TEX_LEAF := "res://assets/textures/trees/listi.png"
const TEX_BARK := "res://assets/textures/trees/kura.png"
const TEX_IMP_COLOR := "res://assets/textures/trees/impostor_barva.png"
const TEX_IMP_NORMAL := "res://assets/textures/trees/impostor_normala.png"

## Optimalizace GPU (17. 10. 2026): `static var` – laditelné v F3 → Svět/Vykreslování (`tune_m8_19.gd`); po změně
## `refresh_bands()`. Skutečná hranice = tohle × násobek z předvolby (`lod0_k` / `lod1_k`, `GameSettings.ECO_LEVELS`).
static var L0_END := 55.0             # m – do této vzdálenosti LOD0 (plný model), dál LOD1
static var L1_END := 170.0            # m – do této vzdálenosti LOD1 (= MapLoader.DEC_FULL_RANGE), dál impostor
const LOD_FADE := 6.0                 # m – půlšířka pásma prolínání (dither) mezi LOD
const CROWN_K := 0.85                 # poloměr koruny z dat = sx × CROWN_K (poloměr dřívějšího prototypu)
const XZ_MIN := 0.8                   # šířkové měřítko modelu vůči datům z ortofota – meze (model si drží tvar druhu)
const XZ_MAX := 1.25
## Vizuální výška × lerp(min, max, vitalita): strom na mělké suché půdě (nízká vitalita, M8.3) je menší, v nivě vyšší.
const VIGOR_H := Vector2(0.86, 1.04)
const YOUNG_H_FALLBACK := 9.0         # m – bez tree_eco.bin: nižší strom = „mladý“ model
const STIFF_CONIFER := 1.3

var shapes: Array = []                # {id, conifer, tile, stiff}
var species_map := {}                 # id druhu → index tvaru
var vit_split: Array = []
var age_split: Array = []
var imp_views := 8
var imp_px := 128
var grid := Vector2(4, 2)
var variants: Array = []              # {shape, vit, age, crown_r, w, y0, y1, lod: [Mesh LOD0, Mesh LOD1]}
var _var_idx := {}                    # shape*100 + vit*10 + age → index varianty
var _mats := {}                       # "tvar_list_pásmo" → ShaderMaterial
## M8.19B: násobek dosahu LOD0 podle detailu přírody v předvolbě grafiky (`GameSettings.ECO_LEVELS`, 1 = L0_END).
var lod0_k := 1.0
## Optimalizace GPU (17. 10. 2026): násobek hranice LOD1 → impostor (1 = L1_END); menší = méně buněk LOD1 kolem kamery
## (`TreeLodStreamer`), tedy méně MultiMeshů ve stínovém i hlavním průchodu.
var lod1_k := 1.0
var _full := {}                       # varianta → LOD0 bez pásma (zasazené stromy)
var _imp_mat: ShaderMaterial
var _imp_mesh: ArrayMesh
var _tex := {}


## Načte DBT2 a postaví meshe. null = soubor chybí / neplatný / chybí atlasy (pak se použijí staré prototypy).
static func load_protos() -> TreeGen:
	if not FileAccess.file_exists(PATH):
		push_warning("TreeGen: chybí %s (python3 tools/treegen/treegen.py) – stromy z prototypů" % PATH)
		return null
	for t in [TEX_LEAF, TEX_BARK, TEX_IMP_COLOR, TEX_IMP_NORMAL]:
		if not ResourceLoader.exists(t):
			push_warning("TreeGen: chybí textura %s – stromy z prototypů" % t)
			return null
	var g := TreeGen.new()
	if not g._parse(FileAccess.get_file_as_bytes(PATH)):
		push_warning("TreeGen: neplatný %s – stromy z prototypů" % PATH)
		return null
	return g


func _parse(b: PackedByteArray) -> bool:
	if b.size() < 32 or b.slice(0, 4).get_string_from_ascii() != "DBT2" or b.decode_s32(4) != 1:
		return false
	var off := 8
	var ns := b.decode_s32(off)
	off += 4
	for s in ns:
		var ln := b.decode_u8(off)
		var id := b.slice(off + 1, off + 1 + ln).get_string_from_ascii()
		off += 1 + ln
		shapes.append({"id": id, "conifer": b.decode_u8(off) == 1, "tile": b.decode_u8(off + 1),
			"stiff": b.decode_float(off + 4)})
		off += 8
	var nm := b.decode_s32(off)
	off += 4
	for m in nm:
		var ln := b.decode_u8(off)
		var sp := b.slice(off + 1, off + 1 + ln).get_string_from_ascii()
		species_map[sp] = b.decode_u8(off + 1 + ln)
		off += 2 + ln
	var nv := b.decode_s32(off)
	off += 4
	for k in nv - 1:
		vit_split.append(b.decode_float(off))
		off += 4
	var na := b.decode_s32(off)
	off += 4
	for k in na - 1:
		age_split.append(b.decode_float(off))
		off += 4
	imp_views = b.decode_s32(off)
	imp_px = b.decode_s32(off + 4)
	grid = Vector2(b.decode_s32(off + 8), b.decode_s32(off + 12))
	off += 16
	var nvar := b.decode_s32(off)
	off += 4
	if nvar <= 0 or nvar > 64:
		return false
	for k in nvar:
		var v := {"shape": b.decode_u8(off), "vit": b.decode_u8(off + 1), "age": b.decode_u8(off + 2),
			"crown_r": b.decode_float(off + 4), "w": b.decode_float(off + 8), "y0": b.decode_float(off + 12),
			"y1": b.decode_float(off + 16), "lod": []}
		off += 20
		var sh: Dictionary = shapes[clampi(int(v["shape"]), 0, shapes.size() - 1)]
		for lod in 2:
			var r := _mesh(b, off, int(v["shape"]), bool(sh["conifer"]), lod)
			v["lod"].append(r[0])
			off = r[1]
			if off > b.size():
				return false
		_var_idx[int(v["shape"]) * 100 + int(v["vit"]) * 10 + int(v["age"])] = variants.size()
		variants.append(v)
	return true


func _mesh(b: PackedByteArray, off: int, shape: int, conifer: bool, lod: int) -> Array:
	var nsurf := b.decode_s32(off)
	off += 4
	var m := ArrayMesh.new()
	for s in nsurf:
		var nv := b.decode_s32(off)
		var ni := b.decode_s32(off + 4)
		off += 8
		var pos := b.slice(off, off + nv * 12).to_float32_array()
		off += nv * 12
		var nrm := b.slice(off, off + nv * 12).to_float32_array()
		off += nv * 12
		var uv := b.slice(off, off + nv * 8).to_float32_array()
		off += nv * 8
		var uv2 := b.slice(off, off + nv * 8).to_float32_array()
		off += nv * 8
		var col := b.slice(off, off + nv * 4)
		off += nv * 4
		var idx := b.slice(off, off + ni * 4).to_int32_array()
		off += ni * 4
		if nv == 0 or ni == 0:
			continue
		var v := PackedVector3Array()
		var n := PackedVector3Array()
		var t := PackedVector2Array()
		var t2 := PackedVector2Array()
		var c := PackedColorArray()
		v.resize(nv)
		n.resize(nv)
		t.resize(nv)
		t2.resize(nv)
		c.resize(nv)
		for i in nv:
			v[i] = Vector3(pos[i * 3], pos[i * 3 + 1], pos[i * 3 + 2])
			n[i] = Vector3(nrm[i * 3], nrm[i * 3 + 1], nrm[i * 3 + 2])
			t[i] = Vector2(uv[i * 2], uv[i * 2 + 1])
			t2[i] = Vector2(uv2[i * 2], uv2[i * 2 + 1])
			c[i] = Color8(col[i * 4], col[i * 4 + 1], col[i * 4 + 2], col[i * 4 + 3])
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_TEX_UV] = t
		arr[Mesh.ARRAY_TEX_UV2] = t2
		arr[Mesh.ARRAY_COLOR] = c
		arr[Mesh.ARRAY_INDEX] = idx
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		m.surface_set_material(m.get_surface_count() - 1, material(shape, s == 1, lod))
	return [m, off]


func _texture(path: String) -> Texture2D:
	if not _tex.has(path):
		_tex[path] = load(path)
	return _tex[path]


## Materiál kůry / listí tvaru pro pásmo `band`: 0 = LOD0, 1 = LOD1, 2 = bez pásma (zasazené stromy).
func material(shape: int, leaf: bool, band: int) -> ShaderMaterial:
	var key := "%d_%d_%d" % [shape, int(leaf), band]
	if _mats.has(key):
		return _mats[key]
	var sh: Dictionary = shapes[clampi(shape, 0, shapes.size() - 1)]
	var conifer: bool = sh["conifer"]
	var m := MapLoader.tree_material(leaf, Color(0.05, 0.12, 0.05) if conifer else Color(0.09, 0.18, 0.05))
	m.set_shader_parameter("deciduous", not conifer)
	m.set_shader_parameter("use_vertex_color", true)
	m.set_shader_parameter("use_atlas", true)
	m.set_shader_parameter("leaf_atlas", _texture(TEX_LEAF))
	m.set_shader_parameter("bark_atlas", _texture(TEX_BARK))
	m.set_shader_parameter("atlas_grid", grid)
	m.set_shader_parameter("stiffness", maxf(float(sh["stiff"]), STIFF_CONIFER if conifer else 0.5))
	_set_band(m, band)
	_mats[key] = m
	return m


## Hranice LOD0 → LOD1 (m) s násobkem z předvolby (nikdy za hranicí LOD1).
func l0_end() -> float:
	return minf(L0_END * lod0_k, l1_end() - 2.0 * LOD_FADE)


## Hranice LOD1 → impostor (m) s násobkem z předvolby.
func l1_end() -> float:
	return maxf(L1_END * lod1_k, 4.0 * LOD_FADE)


## M8.19B: dosah LOD0 podle předvolby (Esc → Nastavení → Grafika → Detail přírody) – přepíše pásma hotových materiálů;
## `TreeLodStreamer` si buňky LOD0 přepočítá při nejbližší kontrole (CHECK_S).
func set_lod0_scale(k: float) -> void:
	set_lod_scales(k, lod1_k)


## Optimalizace GPU (17. 10. 2026): násobky hranic LOD0 i LOD1 najednou (detail přírody v předvolbě).
func set_lod_scales(k0: float, k1: float) -> void:
	k0 = clampf(k0, 0.2, 2.5)
	k1 = clampf(k1, 0.3, 2.0)
	if is_equal_approx(k0, lod0_k) and is_equal_approx(k1, lod1_k):
		return
	lod0_k = k0
	lod1_k = k1
	refresh_bands()


## Přepíše pásma LOD ve všech hotových materiálech (předvolba, F3 → L0_END / L1_END).
func refresh_bands() -> void:
	for key in _mats:
		_set_band(_mats[key] as ShaderMaterial, int(String(key).get_slice("_", 2)))
	if _imp_mat != null:
		_imp_mat.set_shader_parameter("lod_band", Vector4(l1_end(), 1e6, LOD_FADE, 0.0))


func _set_band(m: ShaderMaterial, band: int) -> void:
	if band == 0:
		m.set_shader_parameter("lod_band", Vector4(0.0, l0_end(), LOD_FADE, 0.0))
	elif band == 1:
		m.set_shader_parameter("lod_band", Vector4(l0_end(), l1_end(), LOD_FADE, 0.0))


## LOD meshe varianty: 0 = LOD0, 1 = LOD1 (materiály s pásmem pro streamované buňky).
func lod_mesh(vi: int, lod: int) -> Mesh:
	return (variants[clampi(vi, 0, variants.size() - 1)]["lod"] as Array)[lod]


## LOD0 bez LOD pásma (kreslí se v každé vzdálenosti) – zasazené stromy (M2.5), kterých je málo.
func full_mesh(vi: int) -> Mesh:
	if _full.has(vi):
		return _full[vi]
	var src := lod_mesh(vi, 0) as ArrayMesh
	var shape := int(variants[clampi(vi, 0, variants.size() - 1)]["shape"])
	var m := ArrayMesh.new()
	for s in src.get_surface_count():
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, src.surface_get_arrays(s))
		var leaf: bool = (src.surface_get_material(s) as ShaderMaterial).get_shader_parameter("is_leaf")
		m.surface_set_material(s, material(shape, leaf, 2))
	_full[vi] = m
	return m


## Index tvaru pro druh (dreviny.json); neznámý druh: jehličnan → smrk, jinak buk (první listnáč).
func shape_of(species_id: String, conifer_hint := false) -> int:
	if species_map.has(species_id):
		return int(species_map[species_id])
	for k in shapes.size():
		if bool(shapes[k]["conifer"]) == conifer_hint:
			return k
	return 0


## Varianta podle druhu, vitality (0..1) a věku (roky).
func variant_for(species_id: String, vigor: float, age_years: float, conifer_hint := false) -> int:
	var sh := shape_of(species_id, conifer_hint)
	var vc := 0
	for x in vit_split:
		if vigor >= float(x):
			vc += 1
	var ac := 0
	for x in age_split:
		if age_years >= float(x):
			ac += 1
	var key := sh * 100 + vc * 10 + ac
	if _var_idx.has(key):
		return _var_idx[key]
	for k in variants.size():               # chybí přesná varianta (generátor pustěný s --only) → jiná téhož tvaru
		if int(variants[k]["shape"]) == sh:
			return k
	return 0


## Transformace instance: výška = `h` (m), šířka z modelu druhu, mírně podle poloměru koruny z dat (`sx`).
func instance_basis(rot: float, sx: float, h: float, vi: int) -> Basis:
	var cr := maxf(float(variants[clampi(vi, 0, variants.size() - 1)]["crown_r"]), 0.05)
	var fxz := clampf(sx * CROWN_K / (cr * maxf(h, 0.5)), XZ_MIN, XZ_MAX)
	return Basis(Vector3.UP, rot) * Basis.from_scale(Vector3(h * fxz, h, h * fxz))


func is_conifer_variant(vi: int) -> bool:
	return bool(shapes[int(variants[clampi(vi, 0, variants.size() - 1)]["shape"])]["conifer"])


# ------------------------------------------------------------------ impostory

func impostor_material() -> ShaderMaterial:
	if _imp_mat != null:
		return _imp_mat
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/tree_impostor.gdshader")
	m.set_shader_parameter("imp_color", _texture(TEX_IMP_COLOR))
	m.set_shader_parameter("imp_normal", _texture(TEX_IMP_NORMAL))
	m.set_shader_parameter("imp_views", float(imp_views))
	m.set_shader_parameter("imp_rows", float(variants.size()))
	m.set_shader_parameter("lod_band", Vector4(l1_end(), 1e6, LOD_FADE, 0.0))   # konec 1e6: v float32 ještě ± prolínání
	var ext := PackedColorArray()
	ext.resize(64)
	for k in variants.size():
		var v: Dictionary = variants[k]
		ext[k] = Color(float(v["w"]), float(v["y0"]), float(v["y1"]), 0.0 if is_conifer_variant(k) else 1.0)
	m.set_shader_parameter("imp_ext", ext)
	_imp_mat = m
	return m


## Karta impostoru: rohy jen v UV (shader ji staví ve světě – world_vertex_coords), barva vrcholu bílá
## (shader čte variantu z barvy instance). AABB dost velký pro otočení ke kameře.
func impostor_mesh() -> ArrayMesh:
	if _imp_mesh != null:
		return _imp_mesh
	var v := PackedVector3Array([Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(0.5, 1, 0), Vector3(-0.5, 1, 0)])
	var uv := PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
	var n := PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
	var c := PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_COLOR] = c
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 2, 1, 0, 3, 2])
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.surface_set_material(0, impostor_material())
	m.custom_aabb = AABB(Vector3(-0.8, -0.05, -0.8), Vector3(1.6, 1.2, 1.6))
	_imp_mesh = m
	return m


# ------------------------------------------------------------------ stavba lesa

## Druh / vitalita / věk stromů přímo z tree_eco.bin (formát tools/tree_species.py, záznam TreeEco.REC).
## Vrací {"ids": [id druhu], "rec": PackedByteArray} nebo {} (chybí / nesedí počet stromů).
static func read_eco(n_trees: int) -> Dictionary:
	if not FileAccess.file_exists(TreeEco.PATH):
		return {}
	var b := FileAccess.get_file_as_bytes(TreeEco.PATH)
	if b.size() < 24 or b.slice(0, 4).get_string_from_ascii() != "TECO" or b.decode_s32(12) != TreeEco.REC:
		return {}
	var n := b.decode_s32(8)
	if n != n_trees:
		return {}
	var ns := b.decode_s32(16)
	var off := 20
	var ids: Array[String] = []
	for k in ns:
		var ln := b.decode_u8(off)
		ids.append(b.slice(off + 1, off + 1 + ln).get_string_from_ascii())
		off += 1 + ln
	off += 4                                  # počet porostů
	if off + n * TreeEco.REC > b.size():
		return {}
	return {"ids": ids, "rec": b.slice(off, off + n * TreeEco.REC)}


## Postaví stromy místo `MapLoader.build_trees` (stejné parametry, stejná návratová hodnota – kmeny pro kolize).
func build(parent: Node3D, skip: Dictionary, terrain: Terrain, mgr: TreeManager) -> Array:
	var tb := FileAccess.get_file_as_bytes("res://data/trees.bin")
	var n := tb.decode_s32(4)
	var d := tb.slice(8).to_float32_array()
	var eco := read_eco(n)
	var rec: PackedByteArray = eco.get("rec", PackedByteArray())
	var eco_ids: Array = eco.get("ids", [])
	var root := Node3D.new()
	root.name = "Stromy"
	parent.add_child(root)
	var streamer := TreeLodStreamer.new()
	streamer.name = "StromyLOD"
	streamer.setup(self, mgr)
	var site: Site = mgr.world.site if mgr != null and mgr.world != null else null   # M8.11: posun fenologie podle místa
	if mgr != null:
		mgr.lod_streamer = streamer
	var far_cells := {}       # fkey → [[xf], [custom], [color]]
	var trunks := []
	var meta := {}
	for i in n:
		if skip.has(i):
			continue
		var k := i * 11
		var pos := Vector3(d[k], d[k + 1], d[k + 2])
		if terrain:
			pos.y = minf(pos.y, terrain.height_at(pos.x, pos.z) - 0.15)
		var p := int(d[k + 10])
		var sp := ""
		var vig := TreeEco.FALLBACK_VIGOR
		var age := 50.0 if d[k + 5] >= YOUNG_H_FALLBACK else 10.0
		if not rec.is_empty():
			var si := rec.decode_u8(i * TreeEco.REC)
			sp = String(eco_ids[si]) if si < eco_ids.size() else ""
			age = float(rec.decode_u8(i * TreeEco.REC + 1))
			vig = rec.decode_u8(i * TreeEco.REC + 2) / 255.0
		else:
			sp = String(TreeEco.FALLBACK_PROTO[clampi(p, 0, TreeEco.FALLBACK_PROTO.size() - 1)])
		var vi := variant_for(sp, vig, age, p >= 3)
		var h := d[k + 5] * lerpf(VIGOR_H.x, VIGOR_H.y, vig)
		var xf := Transform3D(instance_basis(d[k + 3], d[k + 4], h, vi), pos)
		var col := Color(d[k + 7], d[k + 8], d[k + 9], Phenology.instance_alpha(sp, pos, site))   # M8.11: a = fenologický kód
		trunks.append([pos, d[k + 4] * (0.09 if p < 3 else 0.07), d[k + 5] * (0.5 if p < 3 else 0.3)])
		var fkey := Vector2i(floori(pos.x / MapLoader.TREE_FAR_CELL), floori(pos.z / MapLoader.TREE_FAR_CELL))
		if not far_cells.has(fkey):
			far_cells[fkey] = [[], [], []]
		far_cells[fkey][0].append(xf)
		far_cells[fkey][1].append(col)
		far_cells[fkey][2].append(Color(vi / 255.0, 0.0, 0.0, 1.0))
		var nkey := Vector2i(floori(pos.x / MapLoader.TREE_CELL), floori(pos.z / MapLoader.TREE_CELL))
		var near_idx := streamer.add_tree(nkey, vi, i, xf, col)
		meta[i] = [nkey, vi, near_idx, fkey, "imp", far_cells[fkey][0].size() - 1, trunks.size() - 1]

	var far_mm := {}
	MapLoader._far_mmis.clear()
	var imp := impostor_mesh()
	for key in far_cells:
		var g: Array = far_cells[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = imp
		mm.instance_count = (g[0] as Array).size()
		for j in mm.instance_count:
			mm.set_instance_transform(j, g[0][j])
			mm.set_instance_custom_data(j, g[1][j])
			mm.set_instance_color(j, g[2][j])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = MapLoader.TREE_FAR_RANGE
		far_mm[[key, "imp"]] = mm
		MapLoader._far_mmis.append(mmi)
		root.add_child(mmi)
	root.add_child(streamer)

	# kolize kmenů – stejně jako MapLoader.build_trees (tvary přímo na fyzikálním serveru, jedno tělo na buňku 256 m)
	var bodies := {}
	var shapes_out: Array = []
	var shape_rids: Array[RID] = []
	for t in trunks:
		var pos: Vector3 = t[0]
		var key := Vector2i(floori(pos.x / MapLoader.TREE_FAR_CELL), floori(pos.z / MapLoader.TREE_FAR_CELL))
		if not bodies.has(key):
			var bd := StaticBody3D.new()
			bd.collision_layer = 1
			bd.collision_mask = 0
			bd.set_meta("surface", "strom")
			root.add_child(bd)
			bodies[key] = [bd, 0]
		var br: Array = bodies[key]
		var body: StaticBody3D = br[0]
		var sr := PhysicsServer3D.cylinder_shape_create()
		PhysicsServer3D.shape_set_data(sr, {"radius": maxf(t[1], 0.15), "height": t[2]})
		PhysicsServer3D.body_add_shape(body.get_rid(), sr,
			Transform3D(Basis.IDENTITY, pos + Vector3(0, t[2] * 0.5, 0)))
		shape_rids.append(sr)
		shapes_out.append([body.get_rid(), br[1]])
		br[1] += 1
	if mgr != null:
		mgr.set_index(d, meta, streamer.near_mm, far_mm, shapes_out, shape_rids)
	return trunks
