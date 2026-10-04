## Procedurální model malotraktoru „Traktůrek“ (M1.6): kapota s motorem, podvozek, blatníky, sedadlo, volant,
## ochranný rám (ROPS) se stříškou, výfuk, světla, tažná oj. Souřadnice jako CarModel: +Z dopředu, +X doleva,
## Y nahoru, počátek na zemi uprostřed rozvoru. Volá ho `CarModel.build` pro záznam se `spec["builder"] == "tractor"`.
## Plní do CarModel: tělo (body_mesh, deformovatelné), materiály, kolizní kvádr, rozměry, pózu řidiče (seat, rider, eye).
class_name TractorModel
extends RefCounted

const DARK := Color(0.07, 0.07, 0.075)
const GREY := Color(0.32, 0.33, 0.35)
const CHROME := Color(0.72, 0.73, 0.75)
const SEAT := Color(0.1, 0.1, 0.11)


static func build(m: CarModel) -> ArrayMesh:
	var s := m.spec
	var wb: float = s["wb"]
	var tr: float = s["track"] * 0.5
	var wr: float = s["wheel_r"]
	m.length = 3.3
	m.half_width = tr + 0.2
	m.height = 2.0
	m.body_mesh = ArrayMesh.new()
	m._light_mats()
	var kp := MeshKit.new()     # lak
	var kt := MeshKit.new()     # tmavé díly, sedadlo, chrom (barva z vrcholů)
	var kh := MeshKit.new()     # přední světla
	var ktl := MeshKit.new()    # zadní světla
	var zf := wb * 0.5
	var zr := -wb * 0.5
	# podvozek (blok převodovky) a nápravy
	kt.box(Vector3(0, 0.62, -0.1), Vector3(0.42, 0.3, 2.7), GREY)
	kt.box(Vector3(0, wr, zf), Vector3(tr * 2.0, 0.14, 0.14), DARK)
	kt.box(Vector3(0, wr, zr), Vector3(tr * 2.0, 0.16, 0.16), DARK)
	# kapota s motorem (zaoblená přední část), mřížka chladiče
	kp.box(Vector3(0, 0.98, 0.92), Vector3(0.64, 0.5, 1.1), Color.WHITE)
	kp.sphere(Vector3(0, 1.0, 1.42), 0.27, Color.WHITE, Vector3(1.15, 0.95, 0.5), Vector3.ZERO, 14, 8)
	kp.box(Vector3(0, 1.26, 0.9), Vector3(0.5, 0.04, 1.0), Color.WHITE.darkened(0.08))
	kt.box(Vector3(0, 0.98, 1.62), Vector3(0.5, 0.4, 0.04), DARK)
	for i in 4:
		kt.box(Vector3(0, 0.86 + i * 0.09, 1.645), Vector3(0.46, 0.02, 0.02), CHROME)
	# přední závaží / nárazník
	kt.box(Vector3(0, 0.6, 1.6), Vector3(0.5, 0.16, 0.14), DARK)
	# blatníky zadních kol
	for sx in [-1.0, 1.0]:
		BikeModel.fender(kp, Vector3(sx * tr, wr, zr), wr + 0.06, 0.05, PI - 0.05, 0.19, Color.WHITE)
		# stupátko
		kt.box(Vector3(sx * (tr - 0.12), 0.66, zr + 0.2), Vector3(0.22, 0.04, 0.5), DARK)
	# plošina řidiče, sedadlo, opěradlo
	kt.box(Vector3(0, 0.86, -0.75), Vector3(0.9, 0.05, 0.9), DARK)
	kt.box(Vector3(0, 1.08, -0.9), Vector3(0.42, 0.1, 0.4), SEAT)
	kt.box(Vector3(0, 1.3, -1.1), Vector3(0.42, 0.36, 0.08), SEAT, Vector3(-0.2, 0, 0))
	# sloupek řízení, volant, páky
	kt.cylinder(Vector3(0, 1.12, -0.28), 0.03, 0.03, 0.5, DARK, Vector3(-0.9, 0, 0), 8)
	var swb := Basis.from_euler(Vector3(-1.05, 0, 0))
	var tor := TorusMesh.new()
	tor.inner_radius = 0.15
	tor.outer_radius = 0.18
	tor.rings = 18
	tor.ring_segments = 6
	kt.add_prim(tor, Transform3D(swb, Vector3(0, 1.36, -0.42)), DARK)
	kt.cylinder(Vector3(0.25, 1.1, -0.55), 0.015, 0.015, 0.4, CHROME, Vector3(0.2, 0, 0.1), 6)
	kt.sphere(Vector3(0.25, 1.32, -0.6), 0.03, DARK)
	# ochranný rám (ROPS) se stříškou
	for sx in [-1.0, 1.0]:
		BikeModel.tube(kt, Vector3(sx * 0.42, 0.88, -1.25), Vector3(sx * 0.42, 1.95, -1.25), 0.03, DARK, 8)
		BikeModel.tube(kt, Vector3(sx * 0.42, 0.88, -0.35), Vector3(sx * 0.42, 1.95, -0.6), 0.025, DARK, 8)
		BikeModel.tube(kt, Vector3(sx * 0.42, 1.95, -1.25), Vector3(sx * 0.42, 1.95, -0.6), 0.025, DARK, 8)
	BikeModel.tube(kt, Vector3(-0.42, 1.95, -1.25), Vector3(0.42, 1.95, -1.25), 0.025, DARK, 8)
	kp.box(Vector3(0, 1.98, -0.92), Vector3(1.0, 0.05, 0.85), Color.WHITE.darkened(0.15))
	# výfuk (svislý) s klapkou
	BikeModel.tube(kt, Vector3(0.2, 1.2, 1.05), Vector3(0.2, 1.72, 1.05), 0.03, DARK, 8)
	kt.cylinder(Vector3(0.2, 1.75, 1.05), 0.04, 0.03, 0.05, CHROME, Vector3.ZERO, 8)
	# tažná oj a čep zadního závěsu
	kt.box(Vector3(0, 0.55, zr - 0.5), Vector3(0.5, 0.07, 0.42), DARK)
	kt.cylinder(Vector3(0, 0.6, zr - 0.62), 0.035, 0.035, 0.14, CHROME, Vector3.ZERO, 8)
	# SPZ (bez popisku – jen bílá deska) a světla
	kt.box(Vector3(0, 0.95, -1.5), Vector3(0.5, 0.11, 0.012), Color(0.95, 0.95, 0.95))
	for sx in [-1.0, 1.0]:
		kh.sphere(Vector3(sx * 0.24, s["head_y"], s["head_z"] - 0.05), 0.075, Color(1.0, 0.98, 0.9), Vector3(1.2, 1.0, 0.6))
		ktl.sphere(Vector3(sx * 0.4, s["tail_y"] + 0.1, s["tail_z"]), 0.05, Color(0.9, 0.05, 0.03), Vector3(1.2, 1.0, 0.6))
	# kolizní kvádr: zvednutý spodek, výška po rám
	var hp := PackedVector3Array()
	for x in [-m.half_width, m.half_width]:
		for y in [0.72, m.height]:
			for z in [-1.6, 1.7]:
				hp.append(Vector3(x, y, z))
	m.hull_points = hp
	# materiály a plochy
	m.paint_mat = StandardMaterial3D.new()
	m.paint_mat.albedo_color = m.paint
	m.paint_mat.metallic = 0.3
	m.paint_mat.roughness = 0.45
	m._add_surface(kp, m.paint_mat)
	m._add_surface(kt, MeshKit.vc_material(0.55, 0.2, 0.0, false))
	m._add_surface(kh, m.head_mat)
	m._add_surface(ktl, m.tail_mat)
	# řidič: sedí uprostřed na sedadle, ruce na volantu, nohy na plošině
	m.seat = Vector3(0, 0.66, -0.9)
	var sw := Vector3(0, 1.36, -0.42)
	var pedal := Vector3(0, 0.93, m.seat.z + 0.62) - m.seat
	m.rider = {"hips": 0.5, "lean": -0.1, "hands": [sw - m.seat], "feet": [pedal, pedal]}
	m.eye = m.seat + Vector3(0, 1.17, 0.06)
	return m.body_mesh
