## Terén celého katastru: výšková mřížka DMR 5G (2 m) z Blender exportu.
## - kolize: jeden HeightMapShape3D (stejná data jako vzhled)
## - vzhled: dlaždice 128 m, každá ve 4 LOD (2 / 4 / 8 / 32 m), výšky čte vertex shader z textury,
##   praskliny mezi LOD skrývají "sukně" (okraje stažené dolů)
class_name Terrain
extends Node3D

const LOD_QUADS := [64, 32, 16, 4]
const LOD_RANGES := [0.0, 190.0, 480.0, 1250.0, 100000.0]
## Dlaždicové textury procedurálního povrchu (M1.1): uniform, bit v `tex_mask`, soubor v `assets/` (AssetLib.has).
## DOPLNIT: názvy textur jsou doporučená výchozí volba (Poly Haven, CC0), uživatel je stáhne a případně změní; nic se nestahuje automaticky.
## Chybí-li soubor, shader použije plochou barvu třídy + šum. Seznam ke stažení (Poly Haven, CC0, 1k) je v ASSETY.md.
const SURFACE_TEXTURES := [
	["tex_grass", 1, "textures/terrain/leafy_grass_diff_1k.jpg"],
	["tex_soil", 2, "textures/terrain/brown_mud_dry_diff_1k.jpg"],
	["tex_forest", 4, "textures/terrain/forest_ground_04_diff_1k.jpg"],
	["tex_yard", 8, "textures/terrain/gravelly_sand_diff_1k.jpg"],
	["tex_mud", 16, "textures/terrain/brown_mud_leaves_01_diff_1k.jpg"],
	["tex_rock", 32, "textures/terrain/rocky_terrain_02_diff_1k.jpg"],
]
## Velikost dlaždice textury povrchu v metrech (3–6 m).
const SURFACE_TEX_SCALE := 4.5

var w: int
var h: int
var spacing: float
var x0: float
var z0: float
var chunk_cells: int
var heights: PackedFloat32Array
var material: ShaderMaterial
var use_ortho := false            # barva terénu z ortofota (F2 → Terén); výchozí = procedurální povrch


func build(meta: Dictionary) -> void:
	var hm: Dictionary = meta["height"]
	w = int(hm["w"])
	h = int(hm["h"])
	spacing = float(hm["spacing"])
	x0 = float(hm["x0"])
	z0 = float(hm["z0"])
	chunk_cells = int(hm["chunk_cells"])
	var hbytes := FileAccess.get_file_as_bytes("res://data/terrain_height.bin")
	heights = hbytes.to_float32_array()
	assert(heights.size() == w * h)
	var coll := FileAccess.get_file_as_bytes("res://data/terrain_collision.bin").to_float32_array()
	var nbytes := FileAccess.get_file_as_bytes("res://data/terrain_normal.bin")
	if _apply_water_carve(coll, nbytes):
		hbytes = heights.to_byte_array()

	# --- kolize
	var shape := HeightMapShape3D.new()
	shape.map_width = w
	shape.map_depth = h
	shape.map_data = coll
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.set_meta("surface", "teren")
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3.ONE * spacing
	cs.position = Vector3(x0 + (w - 1) * spacing * 0.5, 0.0, z0 + (h - 1) * spacing * 0.5)
	body.add_child(cs)
	add_child(body)
	_add_bounds(body)

	# --- textury
	var himg := Image.create_from_data(w, h, false, Image.FORMAT_RF, hbytes)
	var nimg := Image.create_from_data(w, h, false, Image.FORMAT_RGB8, nbytes)
	nimg.generate_mipmaps()
	var noise := FastNoiseLite.new()
	noise.frequency = 0.02
	noise.fractal_octaves = 4
	var ntex := NoiseTexture2D.new()
	ntex.width = 512
	ntex.height = 512
	ntex.seamless = true
	ntex.generate_mipmaps = true
	ntex.noise = noise

	material = ShaderMaterial.new()
	material.shader = load("res://shaders/terrain.gdshader")
	material.set_shader_parameter("height_tex", ImageTexture.create_from_image(himg))
	material.set_shader_parameter("normal_tex", ImageTexture.create_from_image(nimg))
	material.set_shader_parameter("detail_noise", ntex)
	material.set_shader_parameter("grid_origin", Vector2(x0, z0))
	material.set_shader_parameter("spacing", spacing)
	material.set_shader_parameter("grid_size", Vector2(w, h))
	# směr severu ve světě (sněhové jazyky na odvrácených svazích)
	var nd := Clock.enu_to_world(Vector3(0.0, 1.0, 0.0), float(meta.get("north_angle_deg", 78.37)))
	material.set_shader_parameter("north_xz", Vector2(nd.x, nd.z))
	for key in ["ortho_full", "ortho_core"]:
		var o: Dictionary = meta[key]
		material.set_shader_parameter(key, load(o["file"]))
		var rect := Vector4(o["x0"], o["z0"], o["size_x"], o["size_z"])
		material.set_shader_parameter("full_rect" if key == "ortho_full" else "core_rect", rect)

	_load_surface_textures()

	# --- dlaždice
	var size := chunk_cells * spacing
	var meshes := []
	for q in LOD_QUADS:
		meshes.append(_grid_mesh(q, size))
	var mm := FileAccess.get_file_as_bytes("res://data/terrain_chunks.bin").to_float32_array()
	var ncx := int(hm["ncx"])
	var ncz := int(hm["ncz"])
	for iz in ncz:
		for ix in ncx:
			var hmin := mm[(iz * ncx + ix) * 2] - 6.0
			var hmax := mm[(iz * ncx + ix) * 2 + 1] + 1.0
			var origin := Vector3(x0 + ix * size, 0.0, z0 + iz * size)
			var aabb := AABB(Vector3(0, hmin, 0), Vector3(size, hmax - hmin, size))
			for li in LOD_QUADS.size():
				var mi := MeshInstance3D.new()
				mi.mesh = meshes[li]
				mi.material_override = material
				mi.custom_aabb = aabb
				mi.position = origin
				mi.visibility_range_begin = LOD_RANGES[li]
				mi.visibility_range_end = LOD_RANGES[li + 1]
				if li >= 2:
					mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(mi)


## Pole a louky podle kalendáře (Fields): mapa využití ploch a její obdélník (x0, z0, šířka, výška).
func set_landuse(tex: Texture2D, rect: Vector4) -> void:
	material.set_shader_parameter("landuse_tex", tex)
	material.set_shader_parameter("landuse_rect", rect)


## Maska povrchu (SurfaceMap, data/surface.bin) pro shader. Bez ní se třída odvodí z landuse + lesa + sklonu.
func set_surface(tex: Texture2D, rect: Vector4) -> void:
	material.set_shader_parameter("surface_tex", tex)
	material.set_shader_parameter("surface_rect", rect)


## Fallback lesa bez surface.bin: hustota lesa 0..1 (R8) a její obdélník (x0, z0, šířka, výška).
func set_forest_density(tex: Texture2D, rect: Vector4) -> void:
	material.set_shader_parameter("forest_tex", tex)
	material.set_shader_parameter("forest_rect", rect)


## Barva terénu: true = ortofoto ČÚZK (porovnání), false = procedurální povrch (výchozí).
func set_ortho(on: bool) -> void:
	use_ortho = on
	material.set_shader_parameter("use_ortho", on)


## Načte dostupné textury povrchu; chybějící se přeskočí (procedurální barva).
func _load_surface_textures() -> void:
	var mask := 0
	for t in SURFACE_TEXTURES:
		if AssetLib.has(t[2]):
			var tex := load(AssetLib.ROOT + String(t[2])) as Texture2D
			if tex != null:
				material.set_shader_parameter(t[0], tex)
				mask |= int(t[1])
	material.set_shader_parameter("tex_mask", mask)
	material.set_shader_parameter("tex_scale", SURFACE_TEX_SCALE)
	material.set_shader_parameter("use_ortho", use_ortho)


## Tabulka barev plodin pro dnešní datum (Fields.lut_image).
func set_field_lut(tex: Texture2D) -> void:
	material.set_shader_parameter("field_lut", tex)


## Květy na loukách 0..1.
func set_meadow_bloom(v: float) -> void:
	material.set_shader_parameter("meadow_bloom", v)


## Koryta potoků a dna nádrží (tools/water.py → data/water_carve.bin): změněné body mřížky
## s novou výškou a normálou. Upraví výšky, kolizi (výška / rozestup) i normály. Vrací true, když se použilo.
func _apply_water_carve(coll: PackedFloat32Array, nbytes: PackedByteArray) -> bool:
	if not FileAccess.file_exists("res://data/water_carve.bin"):
		return false
	var b := FileAccess.get_file_as_bytes("res://data/water_carve.bin")
	if b.size() < 8 or b.slice(0, 4).get_string_from_ascii() != "DBW1":
		push_warning("water_carve.bin: neznámý formát")
		return false
	var n := b.decode_s32(4)
	var idx := b.slice(8, 8 + n * 4).to_int32_array()
	var hv := b.slice(8 + n * 4, 8 + n * 8).to_float32_array()
	var off := 8 + n * 8
	for k in n:
		var i := idx[k]
		heights[i] = hv[k]
		coll[i] = hv[k] / spacing
		nbytes[i * 3] = b[off + k * 3]
		nbytes[i * 3 + 1] = b[off + k * 3 + 1]
		nbytes[i * 3 + 2] = b[off + k * 3 + 2]
	return true


## Mřížka n×n čtverců přes `size` metrů + sukně po obvodu (vrcholy s y = −1 shader stáhne dolů).
func _grid_mesh(n: int, size: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	var step := size / n
	for j in n + 1:
		for i in n + 1:
			verts.append(Vector3(i * step, 0.0, j * step))
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			var b := a + 1
			var c := a + (n + 1)
			var d := c + 1
			idx.append_array([a, b, c, b, d, c])
	# sukně: obvod po směru, ke každé hraně oboustranný pás
	var ring := []
	for i in n + 1:
		ring.append(i)
	for j in range(1, n + 1):
		ring.append(j * (n + 1) + n)
	for i in range(n - 1, -1, -1):
		ring.append(n * (n + 1) + i)
	for j in range(n - 1, 0, -1):
		ring.append(j * (n + 1))
	ring.append(0)
	for k in ring.size() - 1:
		var t0: int = ring[k]
		var t1: int = ring[k + 1]
		var b0 := verts.size()
		verts.append(Vector3(verts[t0].x, -1.0, verts[t0].z))
		verts.append(Vector3(verts[t1].x, -1.0, verts[t1].z))
		idx.append_array([t0, t1, b0, t1, b0 + 1, b0, t0, b0, t1, t1, b0, b0 + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_INDEX] = idx
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	arr[Mesh.ARRAY_NORMAL] = normals
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## Neviditelné stěny na okraji výškové mřížky.
func _add_bounds(body: StaticBody3D) -> void:
	var xa := x0 + 4.0
	var xb := x0 + (w - 1) * spacing - 4.0
	var za := z0 + 4.0
	var zb := z0 + (h - 1) * spacing - 4.0
	var cx := (xa + xb) * 0.5
	var cz := (za + zb) * 0.5
	var walls := [
		[Vector3(xa - 5, 0, cz), Vector3(10, 2000, zb - za + 20)],
		[Vector3(xb + 5, 0, cz), Vector3(10, 2000, zb - za + 20)],
		[Vector3(cx, 0, za - 5), Vector3(xb - xa + 20, 2000, 10)],
		[Vector3(cx, 0, zb + 5), Vector3(xb - xa + 20, 2000, 10)],
	]
	for wdef in walls:
		var s := BoxShape3D.new()
		s.size = wdef[1]
		var c := CollisionShape3D.new()
		c.shape = s
		c.position = wdef[0]
		body.add_child(c)


## Výška terénu (bilineárně, stejně jako vizuál i kolize v rámci přesnosti).
func height_at(x: float, z: float) -> float:
	var fx := clampf((x - x0) / spacing, 0.0, w - 1.001)
	var fz := clampf((z - z0) / spacing, 0.0, h - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * w + ix
	var a := heights[i]
	var b := heights[i + 1]
	var c := heights[i + w]
	var d := heights[i + w + 1]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)


func contains(x: float, z: float, margin := 10.0) -> bool:
	return x > x0 + margin and x < x0 + (w - 1) * spacing - margin \
		and z > z0 + margin and z < z0 + (h - 1) * spacing - margin
