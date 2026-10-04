## Krajina za okrajem katastru (M6.2) – levné okolí mapy pro pohled z výšky.
## Data: `data/surround_height.bin` (výšky, krok ~25 m) a `data/surround_surface.bin`
## (maska povrchu – třídy jako `SurfaceMap` + 8 voda), připraví `tools/surroundings.py`
## (bin soubory nejsou v gitu). Výšky čte vertex shader (`shaders/surroundings.gdshader`),
## barva tříd sdílí paletu s `terrain.gdshader`. Oblast katastru shader zapustí pod
## detailní terén (díra `HOLE_SINK` / `HOLE_BLEND`), okraje dlaždic mají sukně.
## Bez kolizí a bez stínů. Les = tmavší povrch + MultiMesh hrubých kuželů do `CONE_RANGE`.
## Když data chybí → plochá zvlněná krajina ve výšce okraje katastru (fallback) – hra funguje.
class_name Surroundings
extends Node3D

const TILE_M := 2048.0          # hrana dlaždice okolí (m) – 64×64 quadů na dlaždici
const TILE_QUADS := 64
const HOLE_SINK := 3.0          # zapuštění pod detailní terén uvnitř katastru (m)
const HOLE_BLEND := 30.0        # náběh zapuštění od hranice katastru (m)
const SKIRT_DEPTH := 60.0       # sukně okrajů dlaždic (m)
const FALLBACK_EXTENT := 4500.0 # bez dat: jak daleko za katastr sahá krajina (m)
const FALLBACK_STEP := 64.0     # krok fallback mřížky (m)
const FALLBACK_NOISE := 16.0    # zvlnění fallback krajiny (m)
const FALLBACK_EDGE := 300.0    # fallback: do této vzdálenosti od katastru přesná výška okraje (m)
const CONE_RANGE := 4000.0      # hrubé kužely lesa do této vzdálenosti od katastru (m)
const CONE_STEP := 90.0         # rozestup kuželů (m)
const CONE_H := 16.0            # výška kuželu lesa (m)
const HEADER := 28              # hlavička .bin (magic 4 + verze 4 + x0,z0,krok 12 + nx,nz 8)
const CLS_FOREST := 3           # třída masky = les (jako SurfaceMap.FOREST)
const HEIGHT_PATH := "res://data/surround_height.bin"
const SURFACE_PATH := "res://data/surround_surface.bin"

var x0 := 0.0                   # levý horní roh mřížky okolí (Godot x, z)
var z0 := 0.0
var spacing := 25.0             # krok mřížky (m)
var nx := 0                     # počet bodů mřížky
var nz := 0
var heights := PackedFloat32Array()
var loaded := false             # true = reálná data ze surround_height.bin, false = fallback
var material: ShaderMaterial

var _surface := PackedByteArray()
var _kat := Rect2()             # obdélník detailního terénu (katastr)
var _rng := RandomNumberGenerator.new()


## Postaví okolí podle terénu katastru (volá World po `terrain.build`).
func setup(terrain: Terrain) -> void:
	_kat = Rect2(terrain.x0, terrain.z0, (terrain.w - 1) * terrain.spacing,
		(terrain.h - 1) * terrain.spacing)
	_rng.seed = 122
	if not _load_data():
		_make_fallback(terrain)
	_build_material()
	_build_tiles()
	_build_cones()


## Výška okolí v bodě (bilineárně) – pro kužely lesa a ladění. Vně mřížky svírá na okraj.
func height_at(x: float, z: float) -> float:
	if nx < 2 or nz < 2:
		return 0.0
	var fx := clampf((x - x0) / spacing, 0.0, nx - 1.001)
	var fz := clampf((z - z0) / spacing, 0.0, nz - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * nx + ix
	return lerpf(lerpf(heights[i], heights[i + 1], tx), lerpf(heights[i + nx], heights[i + nx + 1], tx), tz)


## Vzdálenost bodu za obdélník katastru (0 = uvnitř).
func _kat_dist(x: float, z: float) -> float:
	var cx := clampf(x, _kat.position.x, _kat.position.x + _kat.size.x)
	var cz := clampf(z, _kat.position.y, _kat.position.y + _kat.size.y)
	return Vector2(x - cx, z - cz).length()


# ------------------------------------------------------------------ data

## Načte `data/surround_height.bin` (SURH) a volitelně `data/surround_surface.bin` (SURS).
## Vrací false, když výšky chybí / jsou neplatné → fallback.
func _load_data() -> bool:
	if not FileAccess.file_exists(HEIGHT_PATH):
		return false
	var b := FileAccess.get_file_as_bytes(HEIGHT_PATH)
	if b.size() < HEADER or b.slice(0, 4).get_string_from_ascii() != "SURH":
		push_warning("Surroundings: neznámý formát %s" % HEIGHT_PATH)
		return false
	x0 = b.decode_float(8)
	z0 = b.decode_float(12)
	spacing = b.decode_float(16)
	nx = b.decode_s32(20)
	nz = b.decode_s32(24)
	var want := nx * nz * 4
	if nx < 2 or nz < 2 or spacing <= 0.0 or b.size() < HEADER + want:
		push_warning("Surroundings: %s je useknutý" % HEIGHT_PATH)
		return false
	heights = b.slice(HEADER, HEADER + want).to_float32_array()
	loaded = true
	if FileAccess.file_exists(SURFACE_PATH):
		var sb := FileAccess.get_file_as_bytes(SURFACE_PATH)
		if sb.size() >= HEADER + nx * nz and sb.slice(0, 4).get_string_from_ascii() == "SURS":
			_surface = sb.slice(HEADER, HEADER + nx * nz)
		else:
			push_warning("Surroundings: %s chybí nebo nesedí mřížce – povrch bude jen tráva" % SURFACE_PATH)
	return true


## Fallback bez dat: mřížka `FALLBACK_STEP` m přes katastr + `FALLBACK_EXTENT` na každou stranu;
## u okraje katastru přesná výška detailního terénu, dál průměr okraje + jemný šum; povrch
## tráva se skvrnami lesa ze šumu (žádná reálná data → neurčitý vzhled za mlhou).
func _make_fallback(terrain: Terrain) -> void:
	push_warning("Surroundings: chybí %s – plochá krajina okolí (tools/surroundings.py)" % HEIGHT_PATH)
	spacing = FALLBACK_STEP
	x0 = _kat.position.x - FALLBACK_EXTENT
	z0 = _kat.position.y - FALLBACK_EXTENT
	nx = int(ceil((_kat.size.x + 2.0 * FALLBACK_EXTENT) / spacing)) + 1
	nz = int(ceil((_kat.size.y + 2.0 * FALLBACK_EXTENT) / spacing)) + 1
	# průměrná výška na okraji katastru
	var avg := 0.0
	var n := 0
	for fx in range(0, int(_kat.size.x), 96):
		avg += terrain.height_at(_kat.position.x + fx, _kat.position.y)
		avg += terrain.height_at(_kat.position.x + fx, _kat.position.y + _kat.size.y)
		n += 2
	for fz in range(0, int(_kat.size.y), 96):
		avg += terrain.height_at(_kat.position.x, _kat.position.y + fz)
		avg += terrain.height_at(_kat.position.x + _kat.size.x, _kat.position.y + fz)
		n += 2
	avg /= maxf(float(n), 1.0)
	var noise := FastNoiseLite.new()
	noise.seed = 122
	noise.frequency = 0.0006
	noise.fractal_octaves = 3
	var fnoise := FastNoiseLite.new()
	fnoise.seed = 123
	fnoise.frequency = 0.0011
	heights.resize(nx * nz)
	_surface.resize(nx * nz)
	for j in nz:
		var wz := z0 + j * spacing
		for i in nx:
			var wx := x0 + i * spacing
			var d := _kat_dist(wx, wz)
			var cx := clampf(wx, _kat.position.x, _kat.position.x + _kat.size.x)
			var cz := clampf(wz, _kat.position.y, _kat.position.y + _kat.size.y)
			var edge_h := terrain.height_at(cx, cz)
			var far_h := avg + (noise.get_noise_2d(wx, wz) * 0.5 + 0.5) * FALLBACK_NOISE - FALLBACK_NOISE * 0.4
			var blend := clampf(d / FALLBACK_EDGE, 0.0, 1.0)
			heights[j * nx + i] = lerpf(edge_h, far_h, blend)
			# skvrny lesa ve fallback masce (jen když je bod pěkně za katastrem)
			_surface[j * nx + i] = CLS_FOREST if d > 150.0 and fnoise.get_noise_2d(wx, wz) > 0.22 else 0


# ------------------------------------------------------------------ stavba

func _build_material() -> void:
	var himg := Image.create_from_data(nx, nz, false, Image.FORMAT_RF, heights.to_byte_array())
	var simg := Image.create(2, 2, false, Image.FORMAT_R8)
	if _surface.size() == nx * nz:
		simg = Image.create_from_data(nx, nz, false, Image.FORMAT_R8, _surface)
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
	material.shader = load("res://shaders/surroundings.gdshader")
	material.set_shader_parameter("height_tex", ImageTexture.create_from_image(himg))
	material.set_shader_parameter("surface_tex", ImageTexture.create_from_image(simg))
	material.set_shader_parameter("detail_noise", ntex)
	material.set_shader_parameter("grid_origin", Vector2(x0, z0))
	material.set_shader_parameter("spacing", spacing)
	material.set_shader_parameter("grid_size", Vector2(nx, nz))
	material.set_shader_parameter("kat_rect",
		Vector4(_kat.position.x, _kat.position.y, _kat.size.x, _kat.size.y))
	material.set_shader_parameter("hole_sink", HOLE_SINK)
	material.set_shader_parameter("hole_blend", HOLE_BLEND)
	material.set_shader_parameter("skirt_depth", SKIRT_DEPTH)


## Dlaždice `TILE_M` × `TILE_M` přes celou mřížku okolí; ty celé uvnitř katastru se přeskočí
## (shader je zapustí – nejsou vidět). Bez stínů, ~10–25 draw callů.
func _build_tiles() -> void:
	var mesh := _grid_mesh(TILE_QUADS, TILE_M)
	var hmin := heights[0]
	var hmax := hmin
	for hv in heights:
		hmin = minf(hmin, hv)
		hmax = maxf(hmax, hv)
	var xmax := x0 + (nx - 1) * spacing
	var zmax := z0 + (nz - 1) * spacing
	var ix := 0
	while x0 + ix * TILE_M < xmax:
		var iz := 0
		while z0 + iz * TILE_M < zmax:
			var tx := x0 + ix * TILE_M
			var tz := z0 + iz * TILE_M
			var tile := Rect2(tx, tz, TILE_M, TILE_M)
			iz += 1
			if _kat.encloses(tile.grow(-1.0)):
				continue            # celá dlaždice hluboko uvnitř katastru – není vidět
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = material
			mi.custom_aabb = AABB(Vector3(0, hmin - SKIRT_DEPTH, 0),
				Vector3(TILE_M, hmax - hmin + 2.0 * SKIRT_DEPTH, TILE_M))
			mi.position = Vector3(tx, 0.0, tz)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
		ix += 1


## MultiMesh hrubých kuželů na buňkách masky „les“ do `CONE_RANGE` od katastru (1 draw call).
func _build_cones() -> void:
	if _surface.size() != nx * nz:
		return
	var stride := maxi(1, int(CONE_STEP / spacing))
	var xforms: Array[Transform3D] = []
	for j in range(0, nz, stride):
		var wz := z0 + j * spacing
		for i in range(0, nx, stride):
			if _surface[j * nx + i] != CLS_FOREST:
				continue
			var wx := x0 + i * spacing
			var d := _kat_dist(wx, wz)
			if d <= 0.0 or d > CONE_RANGE:
				continue
			var jx := _rng.randf_range(-spacing * 1.2, spacing * 1.2)
			var jz := _rng.randf_range(-spacing * 1.2, spacing * 1.2)
			var s := _rng.randf_range(0.7, 1.5)
			var b := Basis(Vector3.UP, _rng.randf_range(0.0, TAU)) * Basis.from_scale(Vector3(s, s, s))
			xforms.append(Transform3D(b, Vector3(wx + jx, height_at(wx, wz) + CONE_H * 0.5 * s - 1.0, wz + jz)))
	if xforms.is_empty():
		return
	var cone := CylinderMesh.new()
	cone.top_radius = 0.6
	cone.bottom_radius = 8.5
	cone.height = CONE_H
	cone.radial_segments = 6
	cone.rings = 1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.13, 0.20, 0.10)      # tmavý les – laděno k flat_color(3)
	mat.roughness = 1.0
	cone.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = cone
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "LesKuzele"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


## Mřížka n×n čtverců přes `size` metrů + sukně po obvodu (vrcholy s y = −1 shader stáhne dolů).
## Stejný vzor jako Terrain._grid_mesh.
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
