## Načítání geometrie exportované z Blenderu (tools/export_map.py):
## budovy, střechy, cesty (DBM1, po dlaždicích 256 m) a stromy (DBT1 prototypy + DBI1 instance).
class_name MapLoader
extends RefCounted

const TREE_CELL := 128.0
const TREE_FAR_CELL := 256.0
const DEC_FULL_RANGE := 170.0
const TREE_FAR_RANGE := 2600.0

## Prototypy stromů (Mesh s materiály, pořadí jako v tree_protos.bin) po `build_trees`; pro zasazené stromy (M2.5). Prázdné = zatím nenačteno.
static var shared_protos: Array = []

## M6.2: daleké stromové MultiMeshe (dohled TREE_FAR_RANGE) – při letu vysoko Atmosphere
## prodlužuje přes `set_tree_far_mult`.
static var _far_mmis: Array = []


## Násobek dohledu dalekých stromů (1 = TREE_FAR_RANGE). Volá Atmosphere.update podle výšky kamery.
## Zachovává uživatelovu „dohlednost“ (GameSettings ji násobí přes meta `vr0`): meta se přepíše
## na novou základnu a aktuální konec se přepočítá z poslední aplikované škály.
static var _tree_far_mult := 1.0

static func set_tree_far_mult(mult: float) -> void:
	if is_equal_approx(mult, _tree_far_mult):
		return                      # volá se každý snímek – přepočet jen při změně
	_tree_far_mult = mult
	for mmi in _far_mmis:
		if not is_instance_valid(mmi):
			continue
		var o := Vector4(0.0, TREE_FAR_RANGE, 0.0, 0.0)
		if mmi.has_meta("vr0"):
			o = mmi.get_meta("vr0")
		var applied: float = mmi.visibility_range_end / maxf(o.y, 1.0)   # škála z posledního nastavení
		var base := TREE_FAR_RANGE * mult
		mmi.set_meta("vr0", Vector4(o.x, base, o.z, o.w))
		mmi.visibility_range_end = base * applied


static func tinted_material(tex: String, size_m: float, desat: float, gain: float,
		use_tint := true, base_tint := Color(1, 1, 1), normal_strength := 0.7) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/tinted_triplanar.gdshader")
	m.set_shader_parameter("albedo_tex", load("res://textures/%s_diff_2k.jpg" % tex))
	m.set_shader_parameter("normal_tex", load("res://textures/%s_nor_gl_2k.jpg" % tex))
	m.set_shader_parameter("rough_tex", load("res://textures/%s_rough_2k.jpg" % tex))
	m.set_shader_parameter("tex_size_m", size_m)
	m.set_shader_parameter("desaturate", desat)
	m.set_shader_parameter("gain", gain)
	m.set_shader_parameter("use_vertex_tint", use_tint)
	m.set_shader_parameter("base_tint", base_tint)
	m.set_shader_parameter("normal_strength", normal_strength)
	return m


## Načte DBM1 soubor → seznam dlaždic {mesh: ArrayMesh, faces: PackedVector3Array}.
## `drape` – terén: povrch silnic/cest se "přilepí" na terén (konstantní výška nad ním). V exportu
## některé silnice (např. III/49010 u úřadu) visely až 1 m nad terénem, zatímco navazující místní
## komunikace terén kopírovaly → na křižovatkách vznikaly svislé schody, přes které auto neprojelo.
static func load_chunks(path: String, mat: Material, drape: Terrain = null, drape_h := 0.1) -> Array:
	var bytes := FileAccess.get_file_as_bytes(path)
	assert(bytes.slice(0, 4).get_string_from_ascii() == "DBM1")
	var n_chunks := bytes.decode_s32(4)
	var off := 8
	var out := []
	for _c in n_chunks:
		var n := bytes.decode_s32(off)
		off += 4
		var pos := bytes.slice(off, off + n * 12).to_float32_array()
		off += n * 12
		var nrm := bytes.slice(off, off + n * 12).to_float32_array()
		off += n * 12
		var col := bytes.slice(off, off + n * 12).to_float32_array()
		off += n * 12
		var v := PackedVector3Array()
		var nn := PackedVector3Array()
		var cc := PackedColorArray()
		v.resize(n)
		nn.resize(n)
		cc.resize(n)
		for i in n:
			var k := i * 3
			v[i] = Vector3(pos[k], pos[k + 1], pos[k + 2])
			if drape:
				v[i].y = drape.height_at(v[i].x, v[i].z) + drape_h
			nn[i] = Vector3(nrm[k], nrm[k + 1], nrm[k + 2])
			cc[i] = Color(col[k], col[k + 1], col[k + 2])
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = nn
		arr[Mesh.ARRAY_COLOR] = cc
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		m.surface_set_material(0, mat)
		out.append({"mesh": m, "faces": v})
	return out


## Přidá dlaždice do scény; volitelně s kolizí (ConcavePolygonShape3D).
static func add_chunks(parent: Node3D, name: String, chunks: Array, collide: bool, vis_range := 0.0,
		surface := "") -> void:
	var root := Node3D.new()
	root.name = name
	parent.add_child(root)
	for ch in chunks:
		var mi := MeshInstance3D.new()
		mi.mesh = ch["mesh"]
		if vis_range > 0.0:
			mi.visibility_range_end = vis_range
		root.add_child(mi)
		if collide:
			var body := StaticBody3D.new()
			body.collision_layer = 1
			body.collision_mask = 0
			if surface != "":
				body.set_meta("surface", surface)
			var shape := ConcavePolygonShape3D.new()
			shape.backface_collision = true
			shape.set_faces(ch["faces"])
			var cs := CollisionShape3D.new()
			cs.shape = shape
			body.add_child(cs)
			root.add_child(body)


static func _proto_mesh(bytes: PackedByteArray, off: int, mats: Array) -> Array:
	var nsurf := bytes.decode_s32(off)
	off += 4
	var m := ArrayMesh.new()
	for s in nsurf:
		var n := bytes.decode_s32(off)
		off += 4
		var pos := bytes.slice(off, off + n * 12).to_float32_array()
		off += n * 12
		var nrm := bytes.slice(off, off + n * 12).to_float32_array()
		off += n * 12
		if n == 0:
			continue
		var v := PackedVector3Array()
		var nn := PackedVector3Array()
		v.resize(n)
		nn.resize(n)
		for i in n:
			v[i] = Vector3(pos[i * 3], pos[i * 3 + 1], pos[i * 3 + 2])
			nn[i] = Vector3(nrm[i * 3], nrm[i * 3 + 1], nrm[i * 3 + 2])
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = nn
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		m.surface_set_material(m.get_surface_count() - 1, mats[s])
	return [m, off]


static func tree_material(leaf: bool, base: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/tree.gdshader")
	m.set_shader_parameter("is_leaf", leaf)
	m.set_shader_parameter("base_color", base)
	m.set_shader_parameter("bark_tex", load("res://textures/bark_brown_02_diff_2k.jpg"))
	return m


## Nízkopolygonový listnáč pro dálku: kmen + zploštělá koule uvnitř koruny detailního modelu.
static func _low_dec_mesh(bark: Material, leaf: Material) -> ArrayMesh:
	var m := ArrayMesh.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.05
	cyl.bottom_radius = 0.09
	cyl.height = 0.55
	cyl.radial_segments = 5
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	var ca := cyl.get_mesh_arrays()
	var cv: PackedVector3Array = ca[Mesh.ARRAY_VERTEX]
	for i in cv.size():
		cv[i] += Vector3(0, 0.275, 0)
	ca[Mesh.ARRAY_VERTEX] = cv
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ca)
	m.surface_set_material(0, bark)
	var sph := SphereMesh.new()
	sph.radius = 1.0
	sph.height = 2.0
	sph.radial_segments = 10
	sph.rings = 6
	var sa := sph.get_mesh_arrays()
	var sv: PackedVector3Array = sa[Mesh.ARRAY_VERTEX]
	var sn: PackedVector3Array = sa[Mesh.ARRAY_NORMAL]
	for i in sv.size():
		sv[i] = Vector3(sv[i].x * 0.82, sv[i].y * 0.3 + 0.67, sv[i].z * 0.82)
		sn[i] = Vector3(sn[i].x / 0.82, sn[i].y / 0.3, sn[i].z / 0.82).normalized()
	sa[Mesh.ARRAY_VERTEX] = sv
	sa[Mesh.ARRAY_NORMAL] = sn
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, sa)
	m.surface_set_material(1, leaf)
	return m


## Stromy: MultiMesh po buňkách; listnáče detailně do ~170 m, dál nízkopolygonově; jehličnany vždy.
## Kolize: kmeny jako válce. `skip` – pořadí stromů, které stojí v korytě potoka / v rybníce (Water);
## `terrain` – stromy na zahloubeném terénu (koryta) se sníží, ať nevisí ve vzduchu.
## `mgr` (M2.1) – TreeManager dostane index: pro každý strom jeho instance v MultiMeshích a kolizní tvar,
## aby šel strom za běhu pokácet (`TreeManager.hide_tree`).
static func build_trees(parent: Node3D, skip := {}, terrain: Terrain = null, mgr: TreeManager = null) -> Array:
	shared_protos = []
	var bark := tree_material(false, Color.BLACK)
	var leaf := tree_material(true, Color(0.09, 0.18, 0.05))
	var needle := tree_material(true, Color(0.05, 0.12, 0.05))
	needle.set_shader_parameter("deciduous", false)   # jehličnany neopadávají
	var pb := FileAccess.get_file_as_bytes("res://data/tree_protos.bin")
	var nprot := pb.decode_s32(4)
	var off := 8
	var protos := []
	for p in nprot:
		var r := _proto_mesh(pb, off, [bark, leaf if p < 3 else needle])
		protos.append(r[0])
		off = r[1]
	shared_protos = protos       # M2.5: zasazené stromy sdílí prototypy a materiály (sezónní shader)
	var low_dec := _low_dec_mesh(bark, leaf)

	var tb := FileAccess.get_file_as_bytes("res://data/trees.bin")
	var n := tb.decode_s32(4)
	var d := tb.slice(8).to_float32_array()
	var near_cells := {}   # key → [ [xforms per proto], [colors per proto] ]
	var far_cells := {}    # key → {"low": [xf, col], "c3": …, "c4": …, "c5": …}
	var trunks := []       # pro kolize
	var meta := {}         # M2.1: i → [nkey, p, near_idx, fkey, group, far_idx, trunk_idx]
	for i in n:
		if skip.has(i):
			continue
		var k := i * 11
		var pos := Vector3(d[k], d[k + 1], d[k + 2])
		if terrain:
			pos.y = minf(pos.y, terrain.height_at(pos.x, pos.z) - 0.15)
		var basis := Basis(Vector3.UP, d[k + 3]) * Basis.from_scale(Vector3(d[k + 4], d[k + 5], d[k + 6]))
		var xf := Transform3D(basis, pos)
		var col := Color(d[k + 7], d[k + 8], d[k + 9])
		var p := int(d[k + 10])
		trunks.append([pos, d[k + 4] * (0.09 if p < 3 else 0.07), d[k + 5] * (0.5 if p < 3 else 0.3)])
		var fkey := Vector2i(floori(pos.x / TREE_FAR_CELL), floori(pos.z / TREE_FAR_CELL))
		if not far_cells.has(fkey):
			far_cells[fkey] = {}
		var group := "low" if p < 3 else "c%d" % p
		if not far_cells[fkey].has(group):
			far_cells[fkey][group] = [[], []]
		far_cells[fkey][group][0].append(xf)
		far_cells[fkey][group][1].append(col)
		var rec := [null, p, -1, fkey, group, far_cells[fkey][group][0].size() - 1, trunks.size() - 1]
		if p < 3:
			var nkey := Vector2i(floori(pos.x / TREE_CELL), floori(pos.z / TREE_CELL))
			if not near_cells.has(nkey):
				near_cells[nkey] = [[[], []], [[], []], [[], []]]
			near_cells[nkey][p][0].append(xf)
			near_cells[nkey][p][1].append(col)
			rec[0] = nkey
			rec[2] = near_cells[nkey][p][0].size() - 1
		meta[i] = rec

	var root := Node3D.new()
	root.name = "Stromy"
	parent.add_child(root)
	var near_mm := {}      # [nkey, p] → MultiMesh
	var far_mm := {}       # [fkey, group] → MultiMesh
	for key in near_cells:
		for p in 3:
			var g: Array = near_cells[key][p]
			if g[0].is_empty():
				continue
			var nmi := _mmi(protos[p], g[0], g[1], 0.0, DEC_FULL_RANGE)
			near_mm[[key, p]] = nmi.multimesh
			root.add_child(nmi)
	_far_mmis.clear()
	for key in far_cells:
		for group in far_cells[key]:
			var g: Array = far_cells[key][group]
			var mesh: Mesh = low_dec if group == "low" else protos[int(group.substr(1))]
			var mmi := _mmi(mesh, g[0], g[1], 0.0, TREE_FAR_RANGE)
			far_mm[[key, group]] = mmi.multimesh
			_far_mmis.append(mmi)
			root.add_child(mmi)

	# kolize kmenů – jedno statické těleso na buňku 256 m
	var bodies := {}
	var shapes: Array = []
	for t in trunks:
		var pos: Vector3 = t[0]
		var key := Vector2i(floori(pos.x / TREE_FAR_CELL), floori(pos.z / TREE_FAR_CELL))
		if not bodies.has(key):
			var b := StaticBody3D.new()
			b.collision_layer = 1
			b.collision_mask = 0
			b.set_meta("surface", "strom")
			root.add_child(b)
			bodies[key] = b
		var s := CylinderShape3D.new()
		s.radius = maxf(t[1], 0.15)
		s.height = t[2]
		var cs := CollisionShape3D.new()
		cs.shape = s
		cs.position = pos + Vector3(0, t[2] * 0.5, 0)
		bodies[key].add_child(cs)
		shapes.append(cs)
	if mgr != null:
		mgr.set_index(d, meta, near_mm, far_mm, shapes)
	return trunks


static func _mmi(mesh: Mesh, xforms: Array, colors: Array, r0: float, r1: float) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_custom_data(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.visibility_range_begin = r0
	mmi.visibility_range_end = r1
	return mmi
