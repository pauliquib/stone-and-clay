## Stavebnice procedurálních modelů: skládá díly (primitiva, rotační tělesa, obecné smyčky profilů)
## do jednoho ArrayMesh s barvami vrcholů → jeden draw call na kloub postavy / díl auta.
class_name MeshKit
extends RefCounted

var verts := PackedVector3Array()
var norms := PackedVector3Array()
var cols := PackedColorArray()
var idx := PackedInt32Array()

static var _vc_mats := {}
static var _shaders := {}

const VC_SHADER := "res://shaders/vc_model.gdshader"
const VC_SHADER_2S := "res://shaders/vc_model_2s.gdshader"
const VC_PAINT := "res://shaders/vc_paint.gdshader"
const VC_FUR := "res://shaders/vc_fur.gdshader"


## Sdílený materiál s barvou z vrcholů. Vrací StandardMaterial3D (API pro volající, kteří ho přiřazují přímo),
## ale nese v meta `vc_shader` ShaderMaterial vc_model.gdshader se stejnými parametry – `commit()` a `shader_of()`
## ho použijí místo něj: šum podle druhu materiálu a zastínění spodku (dražší část až od Vysoké).
static func vc_material(rough := 0.8, metal := 0.0, emissive := 0.0, cull := true) -> StandardMaterial3D:
	var key := "%.2f_%.2f_%.2f_%s" % [rough, metal, emissive, cull]
	if _vc_mats.has(key):
		return _vc_mats[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = rough
	m.metallic = metal
	if emissive > 0.0:
		m.emission_enabled = true
		m.emission_energy_multiplier = emissive
		m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		m.emission = Color.WHITE
	if not cull:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var sm := ShaderMaterial.new()
	sm.shader = _shader(VC_SHADER if cull else VC_SHADER_2S)
	sm.set_shader_parameter("vc_rough", rough)
	sm.set_shader_parameter("vc_metal", metal)
	sm.set_shader_parameter("vc_emis", emissive)
	m.set_meta("vc_shader", sm)
	_vc_mats[key] = m
	return m


## Materiál, který se má opravdu kreslit: u materiálů z `vc_material()` / srsti jejich shaderová varianta.
static func shader_of(mat: Material) -> Material:
	if mat != null and mat.has_meta("vc_shader"):
		return mat.get_meta("vc_shader")
	return mat


## Lak vozidla (CarModel, BikeModel): barva `color` × barva vrcholu, metalíza a clearcoat od Vysoké (vc_paint.gdshader).
## `low_ao` = síla ztmavení a prachu u země (počátek modelu na zemi; tenký rám kola menší).
static func paint_material(color: Color, rough := 0.3, metal := 0.5, coat := 0.8, coat_rough := 0.15,
		low_ao := 1.0) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = _shader(VC_PAINT)
	sm.set_shader_parameter("vc_low_ao", low_ao)
	sm.set_shader_parameter("vc_paint", color)
	sm.set_shader_parameter("vc_rough", rough)
	sm.set_shader_parameter("vc_metal", metal)
	sm.set_shader_parameter("vc_coat", coat)
	sm.set_shader_parameter("vc_coat_rough", coat_rough)
	return sm


## Srst (QuadrupedModel.fur_material): barvy vrcholů v sRGB × odstín jedince, chlupy od Vysoké (vc_fur.gdshader).
static func fur_shader(rough: float, tint: float) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = _shader(VC_FUR)
	sm.set_shader_parameter("vc_rough", rough)
	sm.set_shader_parameter("vc_tint", tint)
	return sm


static func _shader(path: String) -> Shader:
	if not _shaders.has(path):
		_shaders[path] = load(path)
	return _shaders[path]


func is_empty() -> bool:
	return idx.is_empty()


## Přidá primitivum (CapsuleMesh, SphereMesh, BoxMesh, CylinderMesh…) transformované `xf`.
func add_prim(mesh: PrimitiveMesh, xf: Transform3D, color: Color) -> void:
	add_arrays(mesh.get_mesh_arrays(), xf, color)


func add_arrays(arr: Array, xf: Transform3D, color: Color) -> void:
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var ii: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var nb := xf.basis.inverse().transposed()
	var base := verts.size()
	for i in v.size():
		verts.append(xf * v[i])
		norms.append((nb * n[i]).normalized())
		cols.append(color)
	if ii.is_empty():
		ii = PackedInt32Array()
		for i in v.size():
			ii.append(i)
	# Záporný determinant (zrcadlení scale −1) obrací pořadí vrcholů → přehodit, jinak je těleso naruby.
	var mirrored := xf.basis.determinant() < 0.0
	var t := 0
	while t + 2 < ii.size():
		if mirrored:
			idx.append_array([base + ii[t], base + ii[t + 2], base + ii[t + 1]])
		else:
			idx.append_array([base + ii[t], base + ii[t + 1], base + ii[t + 2]])
		t += 3


func sphere(center: Vector3, r: float, color: Color, scl := Vector3.ONE, rot := Vector3.ZERO,
		seg := 14, rings := 8) -> void:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = seg
	m.rings = rings
	add_prim(m, Transform3D(Basis.from_euler(rot).scaled(scl), center), color)


func box(center: Vector3, size: Vector3, color: Color, rot := Vector3.ZERO) -> void:
	var m := BoxMesh.new()
	m.size = size
	add_prim(m, Transform3D(Basis.from_euler(rot), center), color)


func capsule(center: Vector3, r: float, h: float, color: Color, rot := Vector3.ZERO, scl := Vector3.ONE) -> void:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = maxf(h, r * 2.0)
	m.radial_segments = 12
	m.rings = 4
	add_prim(m, Transform3D(Basis.from_euler(rot).scaled(scl), center), color)


func cylinder(center: Vector3, rt: float, rb: float, h: float, color: Color, rot := Vector3.ZERO, seg := 16) -> void:
	var m := CylinderMesh.new()
	m.top_radius = rt
	m.bottom_radius = rb
	m.height = h
	m.radial_segments = seg
	m.rings = 1
	add_prim(m, Transform3D(Basis.from_euler(rot), center), color)


## Rotační těleso kolem osy Y. `profile` = body (poloměr, y) odspodu nahoru.
## Profil zadaný shora dolů (končetiny postavy: rameno → zápěstí) se sám otočí, aby plocha
## (pořadí vrcholů i normály) směřovala vždy ven; `cap_bottom` / `cap_top` = dno / víko podle y (ne podle pořadí bodů).
## sx/sz – eliptický průřez; `colors` volitelně barva pro každý bod profilu.
func lathe(profile: PackedVector2Array, xf: Transform3D, color: Color, seg := 16, sx := 1.0, sz := 1.0,
		colors: PackedColorArray = PackedColorArray(), cap_bottom := false, cap_top := false) -> void:
	var np := profile.size()
	if np >= 2 and profile[np - 1].y < profile[0].y:
		var rp := PackedVector2Array()
		var rc := PackedColorArray()
		for i in range(np - 1, -1, -1):
			rp.append(profile[i])
			if colors.size() == np:
				rc.append(colors[i])
		profile = rp
		if colors.size() == np:
			colors = rc
	var base := verts.size()
	var nb := xf.basis.inverse().transposed()
	for i in np:
		var a := profile[maxi(i - 1, 0)]
		var b := profile[mini(i + 1, np - 1)]
		var t := b - a
		var nrm2 := Vector2(t.y, -t.x).normalized()   # (radiální, y)
		var c := colors[i] if colors.size() == np else color
		for s in seg + 1:
			var ang := TAU * float(s) / seg
			var ca := cos(ang)
			var sa := sin(ang)
			var p := Vector3(profile[i].x * ca * sx, profile[i].y, profile[i].x * sa * sz)
			var nn := Vector3(nrm2.x * ca / sx, nrm2.y, nrm2.x * sa / sz).normalized()
			verts.append(xf * p)
			norms.append((nb * nn).normalized())
			cols.append(c)
	for i in np - 1:
		for s in seg:
			var a0 := base + i * (seg + 1) + s
			var b0 := a0 + seg + 1
			idx.append_array([a0, a0 + 1, b0, a0 + 1, b0 + 1, b0])
	if cap_bottom:
		_cap(profile[0], xf, color if colors.size() != np else colors[0], seg, sx, sz, false)
	if cap_top:
		_cap(profile[np - 1], xf, color if colors.size() != np else colors[np - 1], seg, sx, sz, true)


func _cap(p: Vector2, xf: Transform3D, color: Color, seg: int, sx: float, sz: float, top: bool) -> void:
	var nb := xf.basis.inverse().transposed()
	var n := (nb * (Vector3.UP if top else Vector3.DOWN)).normalized()
	var c0 := verts.size()
	verts.append(xf * Vector3(0, p.y, 0))
	norms.append(n)
	cols.append(color)
	for s in seg + 1:
		var ang := TAU * float(s) / seg
		verts.append(xf * Vector3(p.x * cos(ang) * sx, p.y, p.x * sin(ang) * sz))
		norms.append(n)
		cols.append(color)
	for s in seg:
		# úhel roste po směru hodinových ručiček při pohledu shora → víko (vidět shora) = c0, s, s+1; dno opačně
		if top:
			idx.append_array([c0, c0 + 1 + s, c0 + 2 + s])
		else:
			idx.append_array([c0, c0 + 2 + s, c0 + 1 + s])


## Trojúhelník s plochou normálou (body proti směru hodinových ručiček při pohledu zvenku v Godotu = CW).
func tri(a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	var n := (c - a).cross(b - a).normalized()
	var base := verts.size()
	for p in [a, b, c]:
		verts.append(p)
		norms.append(n)
		cols.append(color)
	idx.append_array([base, base + 1, base + 2])


func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	tri(a, b, c, color)
	tri(a, c, d, color)


## Spojí smyčky bodů (každá stejný počet bodů) do pláště; normály vyhlazené přes sousedy.
## `ring_colors[i][j]` barva bodu j smyčky i. Pokud `closed`, poslední bod smyčky se spojí s prvním.
func loft(rings: Array, ring_colors: Array, closed := false, flip := false) -> int:
	var nr := rings.size()
	var np: int = rings[0].size()
	var base := verts.size()
	for i in nr:
		var r: PackedVector3Array = rings[i]
		for j in np:
			var pi_ := rings[maxi(i - 1, 0)][j] as Vector3
			var pn := rings[mini(i + 1, nr - 1)][j] as Vector3
			var jm := (j - 1 + np) % np if closed else maxi(j - 1, 0)
			var jp := (j + 1) % np if closed else mini(j + 1, np - 1)
			var tu := pn - pi_
			var tv := r[jp] - r[jm]
			var n := tv.cross(tu).normalized()
			if flip:
				n = -n
			verts.append(r[j])
			norms.append(n)
			cols.append(ring_colors[i][j])
	var segs := np if closed else np - 1
	for i in nr - 1:
		for j in segs:
			var j2 := (j + 1) % np
			var a := base + i * np + j
			var b := base + i * np + j2
			var c := base + (i + 1) * np + j
			var d := base + (i + 1) * np + j2
			if flip:
				idx.append_array([a, b, c, b, d, c])
			else:
				idx.append_array([a, c, b, b, c, d])
	return base


## Hotový mesh (nová plocha do `into`, jinak nový ArrayMesh). `ground_ao` > 0: model stojí počátkem na zemi
## (auto, předmět, zvíře) – barvy vrcholů do této výšky (m) k zemi ztmavnou (levná náhrada okluze, upečená jednou).
func commit(mat: Material = null, into: ArrayMesh = null, ground_ao := 0.0) -> ArrayMesh:
	if ground_ao > 0.0:
		bake_ground_ao(ground_ao)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var m := into if into != null else ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.surface_set_material(m.get_surface_count() - 1, shader_of(mat if mat != null else vc_material()))
	return m


## Ztmaví barvy vrcholů blízko země (y = 0 v souřadnicích modelu) – kontaktní stín pod autem, u kopyt, u dna popelnice.
## Plochy natočené dolů ztmavnou víc. `h` = výška, nad kterou už se nic nemění.
func bake_ground_ao(h: float, strength := 0.45) -> void:
	for i in verts.size():
		var y := verts[i].y
		if y >= h:
			continue
		var t := clampf(y / h, 0.0, 1.0)
		t = t * t * (3.0 - 2.0 * t)
		var down := clampf(-norms[i].y, 0.0, 1.0)
		var f := 1.0 - strength * (1.0 - t) * (0.75 + 0.25 * down)
		var c := cols[i]
		cols[i] = Color(c.r * f, c.g * f, c.b * f, c.a)


func clear() -> void:
	verts = PackedVector3Array()
	norms = PackedVector3Array()
	cols = PackedColorArray()
	idx = PackedInt32Array()


static func mesh_instance(parent: Node3D, mesh: Mesh, vis_end := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if vis_end > 0.0:
		mi.visibility_range_end = vis_end
	parent.add_child(mi)
	return mi
