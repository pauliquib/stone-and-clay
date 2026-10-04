## Procedurální modely drobných předmětů: lahve a sklenice podle druhu nápoje, cigareta, jídlo,
## a pouliční vybavení (popelnice, poštovní schránka, lampa, lavička, dopravní značky).
class_name PropModels
extends RefCounted

static var _glass: StandardMaterial3D
static var _liquid: StandardMaterial3D
static var _emis: StandardMaterial3D


static func glass_mat() -> StandardMaterial3D:
	if _glass == null:
		_glass = StandardMaterial3D.new()
		_glass.vertex_color_use_as_albedo = true
		_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glass.roughness = 0.04
		_glass.metallic = 0.1
		_glass.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
		_glass.rim_enabled = true
		_glass.rim = 0.4
	return _glass


static func liquid_mat() -> StandardMaterial3D:
	if _liquid == null:
		_liquid = StandardMaterial3D.new()
		_liquid.vertex_color_use_as_albedo = true
		_liquid.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_liquid.roughness = 0.1
	return _liquid


static func emissive_mat() -> StandardMaterial3D:
	if _emis == null:
		_emis = StandardMaterial3D.new()
		_emis.vertex_color_use_as_albedo = true
		_emis.emission_enabled = true
		_emis.emission = Color(1.0, 0.45, 0.1)
		_emis.emission_energy_multiplier = 3.0
	return _emis


## Lahev / sklenice pro nápoj `id` (dno v počátku, osa Y).
static func drink_model(id: String) -> Node3D:
	var info := Consumables.info(id)
	var kind: String = info.get("bottle", "beer")
	var liquid: Color = info.get("color", Color(0.8, 0.6, 0.2))
	var root := Node3D.new()
	var g := MeshKit.new()     # sklo
	var l := MeshKit.new()     # tekutina
	var o := MeshKit.new()     # etiketa, uzávěr (neprůhledné)
	var gl := Color(0.9, 0.95, 0.95, 0.35)
	var prof: PackedVector2Array
	var fill := 0.8
	match kind:
		"beer":
			gl = Color(0.35, 0.2, 0.05, 0.75) if id != "nealko" else Color(0.15, 0.4, 0.12, 0.75)
			prof = PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.032, 0.0), Vector2(0.034, 0.01), Vector2(0.034, 0.14),
				Vector2(0.03, 0.17), Vector2(0.014, 0.2), Vector2(0.013, 0.24), Vector2(0.015, 0.245)])
			o.lathe(PackedVector2Array([Vector2(0.0351, 0.05), Vector2(0.0351, 0.11)]), Transform3D.IDENTITY,
				Color(0.9, 0.85, 0.7), 14)
			o.cylinder(Vector3(0, 0.249, 0), 0.016, 0.016, 0.01, Color(0.75, 0.7, 0.2))
		"wine", "sliv", "vodka", "becher", "rum":
			var r := {"wine": 0.037, "sliv": 0.036, "vodka": 0.04, "becher": 0.042, "rum": 0.04}[kind] as float
			var hb := {"wine": 0.19, "sliv": 0.17, "vodka": 0.17, "becher": 0.14, "rum": 0.15}[kind] as float
			var top := {"wine": 0.3, "sliv": 0.31, "vodka": 0.28, "becher": 0.24, "rum": 0.25}[kind] as float
			if kind == "wine":
				gl = Color(0.1, 0.3, 0.1, 0.8)
			elif kind == "becher":
				gl = Color(0.15, 0.35, 0.18, 0.8)
			prof = PackedVector2Array([Vector2(0.0, 0.0), Vector2(r - 0.002, 0.0), Vector2(r, 0.01), Vector2(r, hb),
				Vector2(r * 0.75, hb + 0.03), Vector2(0.013, hb + 0.07), Vector2(0.013, top), Vector2(0.015, top + 0.005)])
			var lab := Color(0.95, 0.93, 0.85)
			match kind:
				"sliv": lab = Color(0.35, 0.2, 0.45)
				"vodka": lab = Color(0.85, 0.1, 0.1)
				"rum": lab = Color(0.9, 0.8, 0.5)
				"becher": lab = Color(0.9, 0.9, 0.85)
			o.lathe(PackedVector2Array([Vector2(r + 0.0012, 0.04), Vector2(r + 0.0012, hb - 0.03)]), Transform3D.IDENTITY, lab, 16)
			o.cylinder(Vector3(0, top + 0.012, 0), 0.016, 0.016, 0.025,
				Color(0.5, 0.05, 0.08) if kind == "wine" else Color(0.7, 0.7, 0.72))
			fill = 0.85
		"mug":
			prof = PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.04, 0.0), Vector2(0.042, 0.015), Vector2(0.046, 0.16),
				Vector2(0.046, 0.17)])
			g.capsule(Vector3(0.0, 0.09, -0.062), 0.009, 0.1, gl, Vector3.ZERO)
			l.lathe(PackedVector2Array([Vector2(0.0, 0.015), Vector2(0.038, 0.015), Vector2(0.041, 0.13), Vector2(0.0, 0.13)]),
				Transform3D.IDENTITY, liquid, 14)
			l.lathe(PackedVector2Array([Vector2(0.0, 0.13), Vector2(0.042, 0.13), Vector2(0.044, 0.162), Vector2(0.0, 0.165)]),
				Transform3D.IDENTITY, Color(1, 1, 0.97, 0.95), 14)
			fill = 0.0
		"shot":
			prof = PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.018, 0.0), Vector2(0.018, 0.012), Vector2(0.022, 0.065)])
			fill = 0.7
		"glass":
			prof = PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.035, 0.0), Vector2(0.004, 0.006), Vector2(0.004, 0.08),
				Vector2(0.03, 0.1), Vector2(0.038, 0.14), Vector2(0.034, 0.18)])
			l.lathe(PackedVector2Array([Vector2(0.0, 0.085), Vector2(0.028, 0.1), Vector2(0.035, 0.13), Vector2(0.0, 0.13)]),
				Transform3D.IDENTITY, Color(liquid, 0.8), 14)
			fill = 0.0
		"cup":
			o.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.03, 0.0), Vector2(0.042, 0.075), Vector2(0.04, 0.08)]),
				Transform3D.IDENTITY, Color(0.95, 0.95, 0.93), 16, 1.0, 1.0, PackedColorArray(), false, false)
			o.lathe(PackedVector2Array([Vector2(0.0, 0.07), Vector2(0.039, 0.07)]), Transform3D.IDENTITY, liquid, 16)
			o.capsule(Vector3(0.048, 0.04, 0), 0.007, 0.05, Color(0.95, 0.95, 0.93))
			fill = 0.0
		"water":
			gl = Color(0.7, 0.85, 1.0, 0.3)
			prof = PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.03, 0.0), Vector2(0.033, 0.02), Vector2(0.033, 0.16),
				Vector2(0.018, 0.2), Vector2(0.013, 0.215)])
			o.cylinder(Vector3(0, 0.22, 0), 0.015, 0.015, 0.015, Color(0.1, 0.35, 0.8))
			o.lathe(PackedVector2Array([Vector2(0.0335, 0.06), Vector2(0.0335, 0.12)]), Transform3D.IDENTITY, Color(0.2, 0.5, 0.9), 14)
	if prof.size() > 0:
		g.lathe(prof, Transform3D.IDENTITY, gl, 16)
		if fill > 0.0:
			var lp := PackedVector2Array()
			var ymax := prof[prof.size() - 1].y * fill
			lp.append(Vector2(0.0, 0.004))
			for p in prof:
				if p.y > 0.003 and p.y < ymax:
					lp.append(Vector2(maxf(p.x - 0.003, 0.0), p.y))
			lp.append(Vector2(lp[lp.size() - 1].x, ymax))
			lp.append(Vector2(0.0, ymax))
			l.lathe(lp, Transform3D.IDENTITY, Color(liquid, 0.85), 14)
	if not o.is_empty():
		MeshKit.mesh_instance(root, o.commit(MeshKit.vc_material(0.5)))
	if not l.is_empty():
		MeshKit.mesh_instance(root, l.commit(liquid_mat()))
	if not g.is_empty():
		MeshKit.mesh_instance(root, g.commit(glass_mat()))
	root.set_meta("hold_kind", "bottle")     # úchop v ruce: tabulka Humanoid.HOLD_GRIPS
	return root


## Jídlo v ruce (rohlík, párek, chleba…) – zjednodušené tvary.
static func food_model(id: String) -> Node3D:
	var root := Node3D.new()
	var k := MeshKit.new()
	var c: Color = Consumables.info(id).get("color", Color(0.8, 0.6, 0.3))
	match id:
		"rohlik", "parek":
			k.capsule(Vector3(0, 0.02, 0), 0.022, 0.16, Color(0.85, 0.6, 0.28), Vector3(0, 0, PI / 2))
			if id == "parek":
				k.capsule(Vector3(0, 0.035, 0), 0.012, 0.19, Color(0.75, 0.35, 0.25), Vector3(0, 0, PI / 2))
		"burt", "burt_opeceny":
			k.capsule(Vector3(0, 0.03, 0), 0.02, 0.15, c, Vector3(0, 0, PI / 2))
		"jablko":
			k.sphere(Vector3(0, 0.04, 0), 0.04, c, Vector3(1, 0.9, 1))
		"chleba_sadlo", "tlacenka":
			k.box(Vector3(0, 0.01, 0), Vector3(0.12, 0.018, 0.09), Color(0.55, 0.38, 0.22))
			k.box(Vector3(0, 0.022, 0), Vector3(0.11, 0.008, 0.08), c)
		_:
			k.box(Vector3(0, 0.015, 0), Vector3(0.09, 0.03, 0.07), c)
	MeshKit.mesh_instance(root, k.commit(MeshKit.vc_material(0.7)))
	return root


static func cigarette() -> Node3D:
	var root := Node3D.new()
	var k := MeshKit.new()
	k.cylinder(Vector3(0, 0.03, 0), 0.0042, 0.0042, 0.06, Color(0.96, 0.96, 0.94), Vector3.ZERO, 8)
	k.cylinder(Vector3(0, -0.01, 0), 0.0044, 0.0044, 0.022, Color(0.85, 0.55, 0.25), Vector3.ZERO, 8)
	MeshKit.mesh_instance(root, k.commit(MeshKit.vc_material(0.8)))
	var t := MeshKit.new()
	t.cylinder(Vector3(0, 0.0625, 0), 0.0043, 0.0043, 0.005, Color(1.0, 0.35, 0.05), Vector3.ZERO, 8)
	MeshKit.mesh_instance(root, t.commit(emissive_mat()))
	return root


## Alkohol-tester (Dräger) s náustkem.
static func breathalyzer() -> Node3D:
	var root := Node3D.new()
	var k := MeshKit.new()
	k.box(Vector3(0, 0.0, 0), Vector3(0.065, 0.15, 0.035), Color(0.12, 0.12, 0.13))
	k.box(Vector3(0, 0.035, 0.018), Vector3(0.045, 0.04, 0.004), Color(0.35, 0.55, 0.4))
	k.box(Vector3(0, -0.04, 0.0), Vector3(0.067, 0.05, 0.037), Color(0.95, 0.75, 0.1))
	k.cylinder(Vector3(0, 0.1, 0), 0.007, 0.007, 0.06, Color(0.95, 0.95, 0.95), Vector3.ZERO, 8)
	MeshKit.mesh_instance(root, k.commit(MeshKit.vc_material(0.6)))
	root.set_meta("hold_kind", "breathalyzer")
	return root


# ------------------------------------------------------------ pouliční vybavení (statický mesh)

static func trash_bin(color: Color) -> ArrayMesh:
	var k := MeshKit.new()
	k.box(Vector3(0, 0.5, 0), Vector3(0.58, 0.95, 0.72), color)
	k.box(Vector3(0, 1.0, -0.02), Vector3(0.62, 0.06, 0.78), color.darkened(0.2), Vector3(0.05, 0, 0))
	k.box(Vector3(0, 0.95, -0.4), Vector3(0.5, 0.04, 0.06), Color(0.1, 0.1, 0.1))
	for s in [-1.0, 1.0]:
		k.cylinder(Vector3(0.24 * s, 0.1, -0.36), 0.1, 0.1, 0.05, Color(0.08, 0.08, 0.08), Vector3(0, 0, PI / 2), 12)
	return k.commit(MeshKit.vc_material(0.6))


static func mailbox() -> ArrayMesh:
	var k := MeshKit.new()
	k.box(Vector3(0, 0.55, 0), Vector3(0.06, 1.1, 0.06), Color(0.3, 0.3, 0.3))
	k.box(Vector3(0, 1.22, 0), Vector3(0.36, 0.3, 0.18), Color(0.85, 0.65, 0.1))
	k.box(Vector3(0, 1.3, 0.091), Vector3(0.25, 0.02, 0.01), Color(0.1, 0.1, 0.1))
	return k.commit(MeshKit.vc_material(0.45, 0.3))


static func street_lamp() -> ArrayMesh:
	var k := MeshKit.new()
	k.cylinder(Vector3(0, 3.0, 0), 0.05, 0.08, 6.0, Color(0.35, 0.37, 0.38), Vector3.ZERO, 10)
	k.capsule(Vector3(0, 5.95, 0.5), 0.035, 1.0, Color(0.35, 0.37, 0.38), Vector3(PI / 2, 0, 0))
	k.box(Vector3(0, 5.9, 1.0), Vector3(0.22, 0.1, 0.5), Color(0.3, 0.3, 0.32))
	k.box(Vector3(0, 5.84, 1.0), Vector3(0.18, 0.02, 0.42), Color(1.0, 0.95, 0.8))
	return k.commit(MeshKit.vc_material(0.5, 0.4))


static func bench() -> ArrayMesh:
	var k := MeshKit.new()
	var wood := Color(0.5, 0.33, 0.18)
	for i in 3:
		k.box(Vector3(0, 0.45, -0.12 + i * 0.13), Vector3(1.6, 0.04, 0.1), wood)
	for i in 2:
		k.box(Vector3(0, 0.62 + i * 0.14, -0.23), Vector3(1.6, 0.1, 0.03), wood, Vector3(-0.2, 0, 0))
	for s in [-1.0, 1.0]:
		k.box(Vector3(0.7 * s, 0.22, 0), Vector3(0.05, 0.45, 0.4), Color(0.15, 0.15, 0.15))
	return k.commit(MeshKit.vc_material(0.8))


## Kulatá/trojúhelníková dopravní značka s textem (Label3D).
static func road_sign(text: String, bg: Color, fg: Color, shape := "rect", w := 0.9, h := 0.6) -> Node3D:
	var root := Node3D.new()
	var k := MeshKit.new()
	k.cylinder(Vector3(0, 1.2, 0), 0.03, 0.03, 2.4, Color(0.55, 0.57, 0.6), Vector3.ZERO, 8)
	match shape:
		"octagon":
			k.cylinder(Vector3(0, 2.2, 0.04), w * 0.5, w * 0.5, 0.02, bg, Vector3(PI / 2, 0, 0), 8)
		"round":
			k.cylinder(Vector3(0, 2.2, 0.04), w * 0.5, w * 0.5, 0.02, bg, Vector3(PI / 2, 0, 0), 24)
		_:
			k.box(Vector3(0, 2.2, 0.04), Vector3(w, h, 0.02), bg)
	MeshKit.mesh_instance(root, k.commit(MeshKit.vc_material(0.4, 0.2)))
	var l := Label3D.new()
	l.text = text
	l.font_size = 48
	l.pixel_size = 0.004 * w / 0.9
	l.modulate = fg
	l.outline_size = 0
	l.position = Vector3(0, 2.2, 0.052)
	l.double_sided = false
	root.add_child(l)
	return root
