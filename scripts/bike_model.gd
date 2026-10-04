## Procedurální model jednostopých vozidel: dědovo kolo (Favorit, 70. léta), motorka Jawa 250 Kývačka, moped Pionýrek a skútr Včelka (M1.6).
## Souřadnice jako u CarModel: +Z dopředu, +X doleva, Y nahoru, počátek na zemi uprostřed rozvoru.
## Plní do CarModel (m): tělo (m.body_mesh, deformovatelné), natáčenou vidlici s řídítky (m.fork_mesh),
## kliky s pedály (m.crank_mesh), kolizní kvádr, pózu jezdce (m.rider) a světla (m.head_mat, m.tail_mat).
class_name BikeModel
extends RefCounted

const CHROME := Color(0.78, 0.79, 0.8)
const BLACK := Color(0.05, 0.05, 0.05)
const RUBBER := Color(0.08, 0.08, 0.08)
const LEATHER := Color(0.16, 0.1, 0.07)


static func build(m: CarModel) -> ArrayMesh:
	var s := m.spec
	var wr: float = s["wheel_r"]
	var wb: float = s["wb"]
	var hull: Array = s["hull"]
	m.length = wb + wr * 2.0 + 0.1
	m.half_width = hull[0]
	m.height = hull[3]
	var hp := PackedVector3Array()
	for x in [-hull[0], hull[0]]:
		for y in [hull[1], hull[3]]:
			for z in [-hull[2], hull[2]]:
				hp.append(Vector3(x, y, z))
	m.hull_points = hp
	m.body_mesh = ArrayMesh.new()
	var kp := MeshKit.new()     # lak (rám kola / nádrž a blatníky motorky)
	var kt := MeshKit.new()     # chrom, guma, kůže, hliník (barva z vrcholů)
	var kf := MeshKit.new()     # vidlice + řídítka (natáčí se)
	var kh := MeshKit.new()     # přední světlo
	var ktl := MeshKit.new()    # zadní světlo / odrazka
	# stavitel podle spec["builder"] (výchozí: kolo → _bicycle, motorka → _jawa); nové typy přidej sem
	match m.spec.get("builder", "bicycle" if m.kind == "bike" else "jawa"):
		"bicycle":
			_bicycle(m, kp, kt, kf, kh, ktl)
		"moped":
			_moped(m, kp, kt, kf, kh, ktl)
		"scooter":
			_scooter(m, kp, kt, kf, kh, ktl)
		"armadka":
			_armadka(m, kp, kt, kf, kh, ktl)
		"krosak":
			_krosak(m, kp, kt, kf, kh, ktl)
		_:
			_jawa(m, kp, kt, kf, kh, ktl)
	m.paint_mat = StandardMaterial3D.new()
	m.paint_mat.albedo_color = m.paint
	m.paint_mat.metallic = 0.35
	m.paint_mat.roughness = 0.35
	m.paint_mat.clearcoat_enabled = true
	m.paint_mat.clearcoat = 0.6
	m.head_mat = StandardMaterial3D.new()
	m.head_mat.vertex_color_use_as_albedo = true
	m.head_mat.emission_enabled = true
	m.head_mat.emission = Color(1.0, 0.95, 0.8)
	m.head_mat.emission_energy_multiplier = 0.3
	m.head_mat.roughness = 0.1
	m.tail_mat = StandardMaterial3D.new()
	m.tail_mat.vertex_color_use_as_albedo = true
	m.tail_mat.emission_enabled = true
	m.tail_mat.emission = Color(1.0, 0.05, 0.02)
	m.tail_mat.emission_energy_multiplier = 0.4
	m.tail_mat.roughness = 0.2
	m._add_surface(kp, m.paint_mat)
	m._add_surface(kt, MeshKit.vc_material(0.4, 0.6))
	m._add_surface(ktl, m.tail_mat)
	# vidlice: vlastní mesh (natáčí ji Car podle rejdu), světlo motorky je v kapotě řídítek
	m.fork_mesh = ArrayMesh.new()
	kf.commit(MeshKit.vc_material(0.35, 0.6), m.fork_mesh)
	if m.kind == "moto":
		kh.commit(m.head_mat, m.fork_mesh)
	else:
		m._add_surface(kh, m.head_mat)
	return m.body_mesh


## Trubka (válec) mezi body a–b.
static func tube(k: MeshKit, a: Vector3, b: Vector3, r: float, col: Color, seg := 8) -> void:
	var d := b - a
	var ln := d.length()
	if ln < 0.001:
		return
	var y := d / ln
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = ln
	cm.radial_segments = seg
	cm.rings = 1
	k.add_prim(cm, Transform3D(Basis(x, y, z), (a + b) * 0.5), col)


## Blatník: oblouk kolem osy kola (střed c) od úhlu a0 do a1 (0 = vpřed, PI/2 = nahoru), šířka w.
static func fender(k: MeshKit, c: Vector3, r: float, a0: float, a1: float, w: float, col: Color, n := 14) -> void:
	for i in n:
		var t0 := lerpf(a0, a1, float(i) / n)
		var t1 := lerpf(a0, a1, float(i + 1) / n)
		var p0 := c + Vector3(0, sin(t0), cos(t0)) * r
		var p1 := c + Vector3(0, sin(t1), cos(t1)) * r
		var q0 := c + Vector3(0, sin(t0), cos(t0)) * (r - 0.03)
		var q1 := c + Vector3(0, sin(t1), cos(t1)) * (r - 0.03)
		var ww := Vector3(w, 0, 0)
		# vnější plocha a boční lemy – oboustranně (materiály mají zapnutý culling)
		for f in [[p0 + ww, p1 + ww, p1 - ww, p0 - ww], [p0 + ww, p1 + ww, q1 + ww, q0 + ww],
				[p0 - ww, p1 - ww, q1 - ww, q0 - ww]]:
			k.quad(f[0], f[1], f[2], f[3], col)
			k.quad(f[3], f[2], f[1], f[0], col)


## Drátové kolo: pneumatika, ráfek, náboj, výplet. Osa kola = X (jako CarModel.wheel_mesh).
static func wheel_mesh(r: float, tire_w: float, moto: bool) -> ArrayMesh:
	var k := MeshKit.new()
	var rot := Transform3D(Basis.from_euler(Vector3(0, 0, PI / 2)), Vector3.ZERO)
	var h := tire_w * 0.5
	var th := tire_w * 0.9          # výška profilu pneumatiky
	k.lathe(PackedVector2Array([Vector2(r - th, -h * 0.8), Vector2(r - th * 0.5, -h), Vector2(r - th * 0.1, -h * 0.75),
		Vector2(r, -h * 0.3), Vector2(r, h * 0.3), Vector2(r - th * 0.1, h * 0.75), Vector2(r - th * 0.5, h),
		Vector2(r - th, h * 0.8)]), rot, RUBBER, 28)
	var rr := r - th
	k.lathe(PackedVector2Array([Vector2(rr - 0.025, -h * 0.5), Vector2(rr, -h * 0.8), Vector2(rr, h * 0.8),
		Vector2(rr - 0.025, h * 0.5), Vector2(rr - 0.025, -h * 0.5)]), rot, CHROME, 28)
	var hub_r := 0.075 if moto else 0.025
	var hub_w := 0.12 if moto else 0.09
	k.cylinder(Vector3.ZERO, hub_r, hub_r, hub_w, CHROME if not moto else Color(0.6, 0.6, 0.62), Vector3(0, 0, PI / 2), 14)
	var n := 36
	for i in n:
		var a := TAU * i / n
		var side := 1.0 if i % 2 == 0 else -1.0
		var from := Vector3(side * hub_w * 0.4, sin(a + 0.2 * side) * hub_r * 0.8, cos(a + 0.2 * side) * hub_r * 0.8)
		var to := Vector3(side * 0.005, sin(a) * (rr - 0.02), cos(a) * (rr - 0.02))
		tube(k, from, to, 0.0025 if not moto else 0.003, CHROME, 4)
	return k.commit(MeshKit.vc_material(0.4, 0.55))


# ------------------------------------------------------------------ kolo Favorit

static func _bicycle(m: CarModel, kp: MeshKit, kt: MeshKit, kf: MeshKit, kh: MeshKit, ktl: MeshKit) -> void:
	var wr: float = m.spec["wheel_r"]
	var wb: float = m.spec["wb"]
	var ra := Vector3(0, wr, -wb * 0.5)     # zadní osa
	var fa := Vector3(0, wr, wb * 0.5)      # přední osa
	var bb := Vector3(0, 0.28, -0.12)        # střed šlapání
	var st := Vector3(0, 0.86, -0.33)        # horní konec sedlové trubky
	var ht := Vector3(0, 0.92, 0.36)         # hlavová trubka nahoře
	var hb := Vector3(0, 0.74, 0.42)         # hlavová trubka dole
	var tr := 0.017
	# rám (dámský ne – pánský „diamant“)
	tube(kp, st, ht, tr, Color.WHITE)
	tube(kp, bb, hb, tr * 1.1, Color.WHITE)
	tube(kp, bb, st + Vector3(0, 0.04, -0.012), tr, Color.WHITE)
	tube(kp, hb - Vector3(0, 0.03, -0.01), ht + Vector3(0, 0.04, -0.013), 0.021, Color.WHITE)
	for sx in [-1.0, 1.0]:
		tube(kp, bb + Vector3(sx * 0.03, 0, 0), ra + Vector3(sx * 0.055, 0, 0), 0.01, Color.WHITE)
		tube(kp, st + Vector3(sx * 0.02, -0.02, 0), ra + Vector3(sx * 0.055, 0, 0), 0.009, Color.WHITE)
	# sedlo (kožené, pružinové) a sedlovka
	tube(kt, st, st + Vector3(0, 0.1, -0.03), 0.012, CHROME)
	var saddle := st + Vector3(0, 0.14, -0.03)
	kt.sphere(saddle, 0.1, LEATHER, Vector3(0.95, 0.35, 1.25), Vector3.ZERO, 12, 6)
	kt.sphere(saddle + Vector3(0, 0.0, 0.12), 0.05, LEATHER, Vector3(0.8, 0.5, 1.4), Vector3.ZERO, 8, 4)
	for sx in [-1.0, 1.0]:
		kt.cylinder(saddle + Vector3(sx * 0.05, -0.06, -0.06), 0.018, 0.018, 0.05, CHROME)
	# blatníky (chrom), nosič, kryt řetězu, řetěz, dynamo
	fender(kt, ra, wr + 0.03, -0.35, PI + 0.1, 0.03, CHROME)
	fender(kt, fa, wr + 0.03, 0.25, PI - 0.3, 0.03, CHROME)
	var rack_y := wr + 0.44
	for sx in [-1.0, 1.0]:
		tube(kt, Vector3(sx * 0.07, rack_y, -0.22), Vector3(sx * 0.07, rack_y, -0.82), 0.006, CHROME, 5)
		tube(kt, Vector3(sx * 0.07, rack_y, -0.8), ra + Vector3(sx * 0.06, 0, 0), 0.006, CHROME, 5)
		tube(kt, Vector3(sx * 0.07, rack_y, -0.24), st + Vector3(sx * 0.02, -0.06, -0.02), 0.005, CHROME, 5)
	for zz in [-0.35, -0.5, -0.65]:
		tube(kt, Vector3(-0.07, rack_y, zz), Vector3(0.07, rack_y, zz), 0.005, CHROME, 5)
	kp.box(Vector3(-0.075, 0.33, -0.34), Vector3(0.012, 0.11, 0.5), Color.WHITE)          # kryt řetězu (vpravo)
	tube(kt, bb + Vector3(-0.06, 0.1, 0), ra + Vector3(-0.06, 0.04, 0), 0.006, BLACK, 4)
	tube(kt, bb + Vector3(-0.06, -0.1, 0), ra + Vector3(-0.06, -0.04, 0), 0.006, BLACK, 4)
	kt.cylinder(ra + Vector3(0.07, 0.12, 0.1), 0.018, 0.018, 0.08, CHROME)             # dynamo
	kt.cylinder(ra + Vector3(-0.065, 0, 0), 0.04, 0.04, 0.008, BLACK, Vector3(0, 0, PI / 2), 14)   # pastorek
	# stojánek (vlevo, sklopený)
	tube(kt, bb + Vector3(0.04, -0.03, -0.12), bb + Vector3(0.2, -0.28, -0.28), 0.008, CHROME, 5)
	# přední světlo na držáku u hlavové trubky, zadní odrazka na blatníku
	var lamp := Vector3(0, m.spec["head_y"], m.spec["head_z"])
	kt.cylinder(lamp - Vector3(0, 0, 0.04), 0.045, 0.04, 0.07, CHROME, Vector3(PI / 2, 0, 0), 14)
	kh.cylinder(lamp + Vector3(0, 0, 0.0), 0.042, 0.042, 0.01, Color(1.0, 0.97, 0.85), Vector3(PI / 2, 0, 0), 14)
	tube(kt, lamp - Vector3(0, 0.02, 0.07), hb + Vector3(0, 0.02, 0.02), 0.006, CHROME, 4)
	ktl.box(Vector3(0, m.spec["tail_y"], m.spec["tail_z"]), Vector3(0.05, 0.07, 0.02), Color(0.9, 0.05, 0.03), Vector3(-0.5, 0, 0))
	# vidlice + představec + zahnutá řídítka (natáčí se kolem osy hlavové trubky)
	m.fork_pivot = ht
	m.fork_axis = (ht - hb).normalized()
	var fl := fa - ht
	for sx in [-1.0, 1.0]:
		tube(kf, hb - ht + Vector3(sx * 0.03, 0, 0), fl + Vector3(sx * 0.05, 0, 0), 0.011, m.paint, 6)
	tube(kf, Vector3(0, -0.02, 0), Vector3(0, 0.14, -0.02), 0.012, CHROME)
	var grip_y := 1.1 - ht.y
	var grip_z := 0.1 - ht.z
	var bar := [Vector3(0.0, 0.14, -0.02), Vector3(0.14, 0.15, 0.02), Vector3(0.24, grip_y, -0.1), Vector3(0.25, grip_y - 0.005, grip_z)]
	for sx in [-1.0, 1.0]:
		for i in bar.size() - 1:
			tube(kf, bar[i] * Vector3(sx, 1, 1), bar[i + 1] * Vector3(sx, 1, 1), 0.011, CHROME, 6)
		kf.capsule(Vector3(sx * 0.25, grip_y, grip_z - 0.05), 0.016, 0.12, BLACK, Vector3(PI / 2, 0, 0))
		tube(kf, Vector3(sx * 0.2, grip_y + 0.01, -0.05), Vector3(sx * 0.2, grip_y - 0.02, grip_z - 0.02), 0.004, CHROME, 4)   # brzdová páka
	kf.cylinder(Vector3(0.12, 0.16, 0.02), 0.022, 0.022, 0.02, CHROME, Vector3(0, 0, 0), 10)       # zvonek
	# kliky: levá kliky dolů, pravá nahoru (rotaci řídí Car podle šlapání); převodník vpravo
	m.crank_pivot = bb
	var kc := MeshKit.new()
	kc.cylinder(Vector3(-0.07, 0, 0), 0.1, 0.1, 0.006, CHROME, Vector3(0, 0, PI / 2), 24)
	kc.cylinder(Vector3.ZERO, 0.03, 0.03, 0.15, CHROME, Vector3(0, 0, PI / 2), 10)
	for sx in [1.0, -1.0]:
		var dir := -1.0 if sx > 0 else 1.0
		kc.box(Vector3(sx * 0.085, dir * 0.085, 0), Vector3(0.012, 0.19, 0.025), CHROME)
		kc.box(Vector3(sx * 0.13, dir * 0.17, 0), Vector3(0.09, 0.022, 0.07), BLACK)
	m.crank_mesh = kc.commit(MeshKit.vc_material(0.35, 0.6))
	# jezdec: sedí na sedle, ruce na řídítkách, nohy na pedálech (Humanoid.ride, souřadnice vůči seat)
	m.seat = Vector3(0, saddle.y + 0.02 - 0.85, saddle.z - 0.02)
	var lean := 0.32
	m.rider = {"hips": 0.88, "lean": lean, "hands": [Vector3(0, ht.y + grip_y, ht.z + grip_z - 0.04) - m.seat],
		"crank": bb - m.seat, "crank_r": 0.17}
	m.eye = m.seat + Vector3(0, 0.88 + 0.67 * cos(lean), 0.67 * sin(lean) + 0.08)


# ------------------------------------------------------------------ Jawa 250 Kývačka

static func _jawa(m: CarModel, kp: MeshKit, kt: MeshKit, kf: MeshKit, kh: MeshKit, ktl: MeshKit) -> void:
	var wr: float = m.spec["wheel_r"]
	var wb: float = m.spec["wb"]
	var ra := Vector3(0, wr, -wb * 0.5)
	var fa := Vector3(0, wr, wb * 0.5)
	var head := Vector3(0, 0.97, 0.44)
	var frame := Color(0.06, 0.06, 0.06)
	var alu := Color(0.62, 0.63, 0.64)
	var ivory := Color(0.9, 0.86, 0.74)
	# rám: páteř, kolébka pod motorem, zadní rám
	tube(kt, head, Vector3(0, 0.82, -0.28), 0.022, frame)
	tube(kt, head - Vector3(0, 0.12, -0.03), Vector3(0, 0.3, 0.2), 0.02, frame)
	tube(kt, Vector3(0, 0.3, 0.2), Vector3(0, 0.24, -0.1), 0.02, frame)
	tube(kt, Vector3(0, 0.24, -0.1), Vector3(0, 0.82, -0.28), 0.02, frame)
	for sx in [-1.0, 1.0]:
		tube(kt, Vector3(sx * 0.1, 0.8, -0.28), Vector3(sx * 0.1, 0.8, -0.8), 0.014, frame)
		# kyvná vidlice a tlumiče
		tube(kt, Vector3(sx * 0.09, 0.4, -0.2), ra + Vector3(sx * 0.09, 0, 0), 0.018, frame)
		tube(kt, ra + Vector3(sx * 0.12, 0.03, 0.02), Vector3(sx * 0.12, 0.78, -0.55), 0.028, CHROME)
		tube(kt, Vector3(sx * 0.12, 0.62, -0.58), Vector3(sx * 0.12, 0.78, -0.55), 0.036, frame)
	# motor: kliková skříň, válec s žebry, hlava, karburátor
	kt.box(Vector3(0, 0.42, -0.02), Vector3(0.26, 0.26, 0.42), alu)
	kt.sphere(Vector3(0.13, 0.42, 0.06), 0.1, alu, Vector3(0.3, 1.0, 1.0))
	kt.sphere(Vector3(-0.13, 0.42, -0.08), 0.12, alu, Vector3(0.3, 1.0, 1.0))
	for i in 7:
		kt.cylinder(Vector3(0, 0.58 + i * 0.032, 0.1 + i * 0.008), 0.085 - (i % 2) * 0.012, 0.085 - (i % 2) * 0.012,
			0.02, alu.darkened(0.1 * (i % 2)), Vector3(-0.25, 0, 0), 14)
	kt.cylinder(Vector3(0, 0.82, 0.16), 0.05, 0.06, 0.05, alu, Vector3(-0.25, 0, 0), 12)
	kt.cylinder(Vector3(0.0, 0.66, -0.12), 0.035, 0.035, 0.12, alu, Vector3(PI / 2, 0, 0), 10)
	# výfuky – Jawa má dva, po obou stranách, s „rybím ocasem“
	for sx in [-1.0, 1.0]:
		var p0 := Vector3(sx * 0.05, 0.6, 0.2)
		var p1 := Vector3(sx * 0.13, 0.36, 0.26)
		var p2 := Vector3(sx * 0.17, 0.3, 0.0)
		var p3 := Vector3(sx * 0.19, 0.36, -0.55)
		tube(kt, p0, p1, 0.022, CHROME)
		tube(kt, p1, p2, 0.022, CHROME)
		tube(kt, p2, p3, 0.03, CHROME)
		kt.capsule(p3 + Vector3(0, 0.02, -0.18), 0.045, 0.42, CHROME, Vector3(PI / 2 - 0.12, 0, 0))
		kt.box(p3 + Vector3(0, 0.05, -0.42), Vector3(0.02, 0.1, 0.08), CHROME, Vector3(-0.2, 0, 0))
		# stupačky
		tube(kt, Vector3(sx * 0.12, 0.3, -0.02), Vector3(sx * 0.24, 0.3, -0.02), 0.018, RUBBER)
	# nádrž (lak + chromované boky), sedlo, boční kryty („kývačka“), blatníky
	kp.sphere(Vector3(0, 0.9, 0.17), 0.2, Color.WHITE, Vector3(0.85, 0.6, 1.5), Vector3(0.12, 0, 0), 18, 10)
	for sx in [-1.0, 1.0]:
		kt.sphere(Vector3(sx * 0.12, 0.9, 0.17), 0.1, CHROME, Vector3(0.25, 0.55, 1.2), Vector3(0.12, 0, 0), 12, 6)
		kt.box(Vector3(sx * 0.13, 0.63, -0.3), Vector3(0.03, 0.24, 0.36), ivory)
	kt.capsule(Vector3(0, 0.84, -0.42), 0.08, 0.7, LEATHER.darkened(0.3), Vector3(PI / 2, 0, 0), Vector3(1.8, 0.8, 1.0))
	tube(kt, Vector3(-0.15, 0.86, -0.58), Vector3(0.15, 0.86, -0.58), 0.01, CHROME, 6)
	fender(kp, ra, wr + 0.05, -0.55, PI - 0.25, 0.075, Color.WHITE)
	fender(kp, fa, wr + 0.05, 0.1, PI - 0.4, 0.07, Color.WHITE)
	# zadní světlo a SPZ na blatníku
	ktl.sphere(Vector3(0, m.spec["tail_y"], m.spec["tail_z"]), 0.05, Color(0.9, 0.05, 0.03), Vector3(1.2, 0.7, 0.7))
	kt.box(Vector3(0, m.spec["tail_y"] - 0.13, m.spec["tail_z"] - 0.06), Vector3(0.2, 0.15, 0.01), Color(0.95, 0.95, 0.95), Vector3(-0.2, 0, 0))
	m.plate_pos = Vector3(0, m.spec["tail_y"] - 0.13, m.spec["tail_z"] - 0.07)
	# stojan
	tube(kt, Vector3(0.1, 0.28, -0.1), Vector3(0.28, 0.02, -0.18), 0.012, frame, 5)
	# teleskopická vidlice, kapota řídítek se světlem (typická pro Kývačku), řídítka
	m.fork_pivot = head
	m.fork_axis = (head - fa).normalized()
	var fl := fa - head
	for sx in [-1.0, 1.0]:
		tube(kf, Vector3(sx * 0.08, 0.0, 0.0), Vector3(sx * 0.08, 0.0, 0.0) + fl * 0.55, 0.028, m.paint, 10)
		tube(kf, Vector3(sx * 0.08, 0.0, 0.0) + fl * 0.5, fl + Vector3(sx * 0.08, 0, 0), 0.02, CHROME, 8)
	kf.sphere(Vector3(0, 0.04, 0.06), 0.13, m.paint, Vector3(1.3, 0.8, 1.2), Vector3.ZERO, 16, 8)
	kf.cylinder(Vector3(0, 0.04, 0.18), 0.1, 0.1, 0.03, CHROME, Vector3(PI / 2, 0, 0), 18)
	kh.cylinder(Vector3(0, 0.04, 0.196), 0.088, 0.088, 0.008, Color(1.0, 0.97, 0.85), Vector3(PI / 2, 0, 0), 18)
	var grip := Vector3(0.26, 1.02 - head.y, 0.3 - head.z)
	for sx in [-1.0, 1.0]:
		tube(kf, Vector3(sx * 0.1, 0.1, 0.02), Vector3(sx * 0.18, 0.1, -0.05), 0.012, CHROME, 6)
		tube(kf, Vector3(sx * 0.18, 0.1, -0.05), grip * Vector3(sx, 1, 1) + Vector3(-sx * 0.06, 0, 0), 0.012, CHROME, 6)
		kf.capsule(grip * Vector3(sx, 1, 1), 0.019, 0.13, BLACK, Vector3(0, 0, PI / 2))
		kf.box(grip * Vector3(sx, 1, 1) + Vector3(-sx * 0.02, 0.0, 0.07), Vector3(0.14, 0.012, 0.02), CHROME, Vector3(0, sx * 0.3, 0))
		kf.sphere(Vector3(sx * 0.2, 0.15, -0.02), 0.03, CHROME, Vector3(1, 1, 1))     # zrcátko
	# jezdec: sedí vpředu na dvojsedle, nohy na stupačkách, ruce na řídítkách
	m.seat = Vector3(0, 0.0, -0.24)
	var lean := 0.3
	var peg := Vector3(0, 0.37, -0.02) - m.seat
	m.rider = {"hips": 0.93, "lean": lean, "hands": [head + grip - m.seat], "feet": [peg, peg]}
	m.eye = m.seat + Vector3(0, 0.93 + 0.67 * cos(lean), 0.67 * sin(lean) + 0.08)


# ------------------------------------------------------------------ moped Pionýrek 50 (M1.6)

static func _moped(m: CarModel, kp: MeshKit, kt: MeshKit, kf: MeshKit, kh: MeshKit, ktl: MeshKit) -> void:
	var wr: float = m.spec["wheel_r"]
	var wb: float = m.spec["wb"]
	var ra := Vector3(0, wr, -wb * 0.5)
	var fa := Vector3(0, wr, wb * 0.5)
	var head := Vector3(0, 0.86, 0.4)
	var frame := Color(0.07, 0.07, 0.07)
	var alu := Color(0.62, 0.63, 0.64)
	# rám s nízkým průlezem: hlavová trubka → dolů k motoru → dozadu → nahoru k sedlu
	tube(kp, head, Vector3(0, 0.36, 0.14), 0.03, Color.WHITE)
	tube(kp, Vector3(0, 0.36, 0.14), Vector3(0, 0.34, -0.3), 0.028, Color.WHITE)
	tube(kp, Vector3(0, 0.34, -0.3), Vector3(0, 0.66, -0.42), 0.028, Color.WHITE)
	tube(kt, head, Vector3(0, 0.7, -0.35), 0.014, frame)
	for sx in [-1.0, 1.0]:
		tube(kt, Vector3(sx * 0.05, 0.4, -0.32), ra + Vector3(sx * 0.07, 0, 0), 0.014, frame)
		tube(kt, Vector3(sx * 0.05, 0.62, -0.4), ra + Vector3(sx * 0.07, 0, 0), 0.012, frame)
		tube(kt, ra + Vector3(sx * 0.1, 0.03, 0.0), Vector3(sx * 0.1, 0.62, -0.4), 0.022, CHROME)   # tlumič
	# motor s klikovou skříní a válcem, pedály
	kt.box(Vector3(0, 0.34, 0.0), Vector3(0.2, 0.2, 0.28), alu)
	kt.cylinder(Vector3(0.0, 0.5, 0.0), 0.06, 0.06, 0.12, alu, Vector3(-0.5, 0, 0), 12)
	for sx in [-1.0, 1.0]:
		tube(kt, Vector3(sx * 0.1, 0.32, 0.0), Vector3(sx * 0.2, 0.32, 0.0), 0.012, frame)
		kt.box(Vector3(sx * 0.24, 0.25, 0.0), Vector3(0.09, 0.02, 0.07), RUBBER)
	# výfuk vpravo
	tube(kt, Vector3(-0.05, 0.4, 0.06), Vector3(-0.14, 0.22, -0.1), 0.02, CHROME)
	kt.capsule(Vector3(-0.14, 0.24, -0.42), 0.04, 0.55, CHROME, Vector3(PI / 2 + 0.05, 0, 0))
	# nádrž (nad rámem), sedlo, blatníky
	kp.sphere(Vector3(0, 0.72, 0.02), 0.13, Color.WHITE, Vector3(0.8, 0.6, 1.5), Vector3(0.1, 0, 0), 14, 8)
	kt.capsule(Vector3(0, 0.74, -0.46), 0.075, 0.5, LEATHER.darkened(0.3), Vector3(PI / 2, 0, 0), Vector3(1.5, 0.8, 1.0))
	fender(kp, ra, wr + 0.04, -0.45, PI - 0.3, 0.05, Color.WHITE)
	fender(kp, fa, wr + 0.04, 0.15, PI - 0.5, 0.05, Color.WHITE)
	# nosič nad zadním kolem, zadní světlo a SPZ
	for sx in [-1.0, 1.0]:
		tube(kt, Vector3(sx * 0.08, 0.63, -0.55), Vector3(sx * 0.08, 0.63, -0.85), 0.007, CHROME, 5)
	tube(kt, Vector3(-0.08, 0.63, -0.85), Vector3(0.08, 0.63, -0.85), 0.007, CHROME, 5)
	ktl.sphere(Vector3(0, m.spec["tail_y"], m.spec["tail_z"]), 0.04, Color(0.9, 0.05, 0.03), Vector3(1.2, 0.7, 0.7))
	kt.box(Vector3(0, m.spec["tail_y"] - 0.12, m.spec["tail_z"] - 0.05), Vector3(0.2, 0.13, 0.01), Color(0.95, 0.95, 0.95), Vector3(-0.2, 0, 0))
	m.plate_pos = Vector3(0, m.spec["tail_y"] - 0.12, m.spec["tail_z"] - 0.06)
	tube(kt, Vector3(0.08, 0.3, -0.25), Vector3(0.24, 0.02, -0.32), 0.01, frame, 5)     # stojan
	# vidlice, světlo, řídítka (natáčí se)
	m.fork_pivot = head
	m.fork_axis = (head - fa).normalized()
	var fl := fa - head
	for sx in [-1.0, 1.0]:
		tube(kf, Vector3(sx * 0.06, 0.0, 0.0), Vector3(sx * 0.06, 0.0, 0.0) + fl * 0.55, 0.02, frame, 8)
		tube(kf, Vector3(sx * 0.06, 0.0, 0.0) + fl * 0.5, fl + Vector3(sx * 0.06, 0, 0), 0.015, CHROME, 8)
	kf.cylinder(Vector3(0, 0.05, 0.1), 0.075, 0.07, 0.07, CHROME, Vector3(PI / 2, 0, 0), 14)
	kh.cylinder(Vector3(0, 0.05, 0.138), 0.065, 0.065, 0.008, Color(1.0, 0.97, 0.85), Vector3(PI / 2, 0, 0), 14)
	var grip := Vector3(0.24, 0.98 - head.y, 0.05)
	for sx in [-1.0, 1.0]:
		tube(kf, Vector3(sx * 0.02, 0.0, 0.0), Vector3(sx * 0.06, 0.09, -0.02), 0.011, CHROME, 6)
		tube(kf, Vector3(sx * 0.06, 0.09, -0.02), grip * Vector3(sx, 1, 1), 0.011, CHROME, 6)
		kf.capsule(grip * Vector3(sx, 1, 1), 0.017, 0.11, BLACK, Vector3(0, 0, PI / 2))
	# jezdec: sedí na sedle, nohy na pedálech, ruce na řídítkách
	m.seat = Vector3(0, 0.0, -0.3)
	var lean := 0.22
	var peg := Vector3(0, 0.27, 0.0) - m.seat
	m.rider = {"hips": 0.82, "lean": lean, "hands": [head + grip - m.seat], "feet": [peg, peg]}
	m.eye = m.seat + Vector3(0, 0.82 + 0.67 * cos(lean), 0.67 * sin(lean) + 0.08)


# ------------------------------------------------------------------ skútr Včelka 125 (M1.6)

static func _scooter(m: CarModel, kp: MeshKit, kt: MeshKit, kf: MeshKit, kh: MeshKit, ktl: MeshKit) -> void:
	var wr: float = m.spec["wheel_r"]
	var wb: float = m.spec["wb"]
	var ra := Vector3(0, wr, -wb * 0.5)
	var fa := Vector3(0, wr, wb * 0.5)
	var head := Vector3(0, 0.82, 0.5)
	var frame := Color(0.07, 0.07, 0.07)
	# plastové karoserie: čelní štít (kolena), podlaha (stupačky), zadní kapotáž se sedlem
	kp.box(Vector3(0, 0.55, 0.42), Vector3(0.36, 0.55, 0.06), Color.WHITE, Vector3(0.28, 0, 0))
	kp.box(Vector3(0, 0.3, 0.12), Vector3(0.44, 0.05, 0.62), Color.WHITE)
	kp.box(Vector3(0, 0.42, -0.02), Vector3(0.16, 0.24, 0.16), Color.WHITE.darkened(0.05))
	kp.sphere(Vector3(0, 0.5, -0.42), 0.26, Color.WHITE, Vector3(0.75, 0.9, 1.7), Vector3(0.12, 0, 0), 16, 10)
	kt.box(Vector3(0, 0.75, -0.36), Vector3(0.3, 0.09, 0.62), LEATHER.darkened(0.3), Vector3(0.05, 0, 0))
	kt.box(Vector3(0, 0.3, 0.12), Vector3(0.4, 0.012, 0.56), RUBBER)                       # gumová podlážka
	# motor s variátorem (u zadního kola), tlumiče, výfuk
	kt.box(Vector3(0.08, 0.3, -0.5), Vector3(0.16, 0.2, 0.5), Color(0.55, 0.56, 0.58))
	for sx in [-1.0, 1.0]:
		tube(kt, ra + Vector3(sx * 0.11, 0.03, 0.02), Vector3(sx * 0.11, 0.55, -0.35), 0.022, CHROME)
	kt.capsule(Vector3(-0.13, 0.27, -0.6), 0.05, 0.5, CHROME, Vector3(PI / 2 - 0.08, 0, 0))
	# blatníky, zadní světlo, SPZ
	fender(kp, fa, wr + 0.04, 0.1, PI - 0.5, 0.055, Color.WHITE)
	kt.box(Vector3(0, 0.6, -0.78), Vector3(0.24, 0.06, 0.16), Color(0.1, 0.1, 0.11))      # držák / nosič
	ktl.box(Vector3(0, m.spec["tail_y"], m.spec["tail_z"]), Vector3(0.22, 0.06, 0.03), Color(0.9, 0.05, 0.03))
	kt.box(Vector3(0, m.spec["tail_y"] - 0.14, m.spec["tail_z"] - 0.03), Vector3(0.2, 0.13, 0.01), Color(0.95, 0.95, 0.95), Vector3(-0.15, 0, 0))
	m.plate_pos = Vector3(0, m.spec["tail_y"] - 0.14, m.spec["tail_z"] - 0.04)
	tube(kt, Vector3(0.1, 0.3, -0.3), Vector3(0.24, 0.02, -0.36), 0.01, frame, 5)
	# vidlice, kapota řídítek se světlem, řídítka
	m.fork_pivot = head
	m.fork_axis = (head - fa).normalized()
	var fl := fa - head
	for sx in [-1.0, 1.0]:
		tube(kf, Vector3(sx * 0.07, 0.0, 0.0), Vector3(sx * 0.07, 0.0, 0.0) + fl * 0.55, 0.022, frame, 8)
		tube(kf, Vector3(sx * 0.07, 0.0, 0.0) + fl * 0.5, fl + Vector3(sx * 0.07, 0, 0), 0.016, CHROME, 8)
	kf.sphere(Vector3(0, 0.08, 0.05), 0.15, m.paint, Vector3(1.5, 0.8, 1.1), Vector3.ZERO, 16, 8)
	kf.cylinder(Vector3(0, 0.02, 0.16), 0.07, 0.065, 0.03, CHROME, Vector3(PI / 2, 0, 0), 14)
	kh.cylinder(Vector3(0, 0.02, 0.176), 0.06, 0.06, 0.008, Color(1.0, 0.97, 0.85), Vector3(PI / 2, 0, 0), 14)
	var grip := Vector3(0.26, 0.12, 0.0)
	for sx in [-1.0, 1.0]:
		tube(kf, Vector3(sx * 0.03, 0.1, 0.0), grip * Vector3(sx, 1, 1), 0.012, CHROME, 6)
		kf.capsule(grip * Vector3(sx, 1, 1), 0.018, 0.12, BLACK, Vector3(0, 0, PI / 2))
		kf.sphere(Vector3(sx * 0.24, 0.24, 0.0), 0.028, CHROME)       # zrcátko
	# jezdec: sedí na sedle, nohy na podlážce, ruce na řídítkách
	m.seat = Vector3(0, 0.0, -0.32)
	var lean := 0.15
	var peg := Vector3(0, 0.33, 0.12) - m.seat
	m.rider = {"hips": 0.85, "lean": lean, "hands": [head + grip - m.seat], "feet": [peg, peg]}
	m.eye = m.seat + Vector3(0, 0.85 + 0.67 * cos(lean), 0.67 * sin(lean) + 0.08)


# ------------------------------------------------------------------ Armádka 750 (vojenská, styl „flathead“ V-twin 40. let)

static func _armadka(m: CarModel, kp: MeshKit, kt: MeshKit, kf: MeshKit, kh: MeshKit, ktl: MeshKit) -> void:
	var wr: float = m.spec["wheel_r"]
	var wb: float = m.spec["wb"]
	var ra := Vector3(0, wr, -wb * 0.5)
	var fa := Vector3(0, wr, wb * 0.5)
	var head := Vector3(0, 0.97, 0.40)
	var frame := Color(0.06, 0.06, 0.05)
	var alu := Color(0.58, 0.59, 0.6)
	var canvas := Color(0.35, 0.28, 0.15)      # plátno / kůže brašen
	# rám: páteř, spodní trubka, zadní pevný rám (bez tlumičů – éra tuhé zadní vidlice)
	tube(kt, head, Vector3(0, 0.78, -0.32), 0.024, frame)
	tube(kt, head - Vector3(0, 0.14, -0.02), Vector3(0, 0.3, 0.32), 0.022, frame)
	tube(kt, Vector3(0, 0.3, 0.32), Vector3(0, 0.28, -0.1), 0.022, frame)
	for sx in [-1.0, 1.0]:
		tube(kt, Vector3(sx * 0.08, 0.78, -0.32), ra + Vector3(sx * 0.09, 0, 0), 0.014, frame)
		tube(kt, Vector3(sx * 0.08, 0.28, -0.1), ra + Vector3(sx * 0.09, 0, 0), 0.014, frame)
		tube(kt, Vector3(sx * 0.08, 0.5, -0.32), Vector3(sx * 0.08, 0.78, -0.32), 0.014, frame)
	# vidlicový motor „flathead“: kliková skříň + dva žebrované válce do V (přední dopředu, zadní dozadu)
	kt.box(Vector3(0, 0.38, 0.12), Vector3(0.3, 0.26, 0.38), alu)
	kt.sphere(Vector3(0.15, 0.38, 0.14), 0.11, alu.darkened(0.15), Vector3(0.3, 1.0, 1.0))
	for i in 7:
		kt.cylinder(Vector3(0, 0.52 + i * 0.031, 0.26 + i * 0.017), 0.082 - (i % 2) * 0.011,
			0.082 - (i % 2) * 0.011, 0.02, alu.darkened(0.1 * (i % 2)), Vector3(-0.5, 0, 0), 14)
		kt.cylinder(Vector3(0, 0.55 + i * 0.031, -0.03 - i * 0.014), 0.082 - (i % 2) * 0.011,
			0.082 - (i % 2) * 0.011, 0.02, alu.darkened(0.1 * (i % 2)), Vector3(0.38, 0, 0), 14)
	kt.cylinder(Vector3(0, 0.76, 0.42), 0.055, 0.06, 0.05, alu, Vector3(-0.5, 0, 0), 12)      # hlava předního válce
	kt.cylinder(Vector3(0, 0.8, -0.17), 0.055, 0.06, 0.05, alu, Vector3(0.38, 0, 0), 12)      # hlava zadního válce
	kt.box(Vector3(0, 0.2, 0.1), Vector3(0.34, 0.03, 0.55), frame)                            # kryt pod motorem
	# padací rám + nášlapné plošinky místo stupaček
	for sx in [-1.0, 1.0]:
		tube(kt, Vector3(sx * 0.2, 0.56, 0.34), Vector3(sx * 0.25, 0.3, 0.05), 0.013, frame)
		tube(kt, Vector3(sx * 0.25, 0.3, 0.05), Vector3(sx * 0.2, 0.3, -0.2), 0.013, frame)
		kt.box(Vector3(sx * 0.19, 0.22, 0.1), Vector3(0.15, 0.02, 0.3), RUBBER)
		kt.box(Vector3(sx * 0.19, 0.235, 0.1), Vector3(0.16, 0.008, 0.02), CHROME)
	# výfuk vpravo s „rybím ocasem“
	tube(kt, Vector3(0.06, 0.52, 0.3), Vector3(0.16, 0.3, 0.3), 0.024, CHROME)
	tube(kt, Vector3(0.16, 0.3, 0.3), Vector3(0.18, 0.26, -0.15), 0.024, CHROME)
	tube(kt, Vector3(0.18, 0.26, -0.15), Vector3(0.19, 0.3, -0.45), 0.028, CHROME)
	kt.capsule(Vector3(0.19, 0.32, -0.62), 0.045, 0.35, CHROME, Vector3(PI / 2 - 0.06, 0, 0))
	kt.box(Vector3(0.19, 0.33, -0.83), Vector3(0.02, 0.1, 0.1), CHROME, Vector3(-0.2, 0, 0))
	# nádrž (lak), palubní štítek, sedlo s pružinami + druhé sedlo, brašny, nosič
	kp.sphere(Vector3(0, 0.87, 0.1), 0.17, Color.WHITE, Vector3(0.9, 0.62, 1.65), Vector3(0.1, 0, 0), 18, 10)
	kt.cylinder(Vector3(0, 0.98, 0.14), 0.025, 0.025, 0.02, CHROME)
	kt.box(Vector3(0, 0.94, -0.02), Vector3(0.12, 0.015, 0.18), frame)
	kt.capsule(Vector3(0, 0.79, -0.4), 0.095, 0.34, LEATHER.darkened(0.15), Vector3(PI / 2, 0, 0), Vector3(1.7, 0.85, 1.0))
	for sx in [-1.0, 1.0]:
		kt.cylinder(Vector3(sx * 0.05, 0.7, -0.48), 0.016, 0.016, 0.14, CHROME)
		kt.box(Vector3(sx * 0.22, 0.5, -0.6), Vector3(0.09, 0.3, 0.42), canvas)
		kt.box(Vector3(sx * 0.22, 0.66, -0.6), Vector3(0.11, 0.04, 0.44), canvas.darkened(0.15))
	kt.capsule(Vector3(0, 0.77, -0.72), 0.07, 0.22, LEATHER.darkened(0.3), Vector3(PI / 2, 0, 0), Vector3(1.6, 0.8, 1.0))
	for sx in [-1.0, 1.0]:
		tube(kt, Vector3(sx * 0.11, 0.71, -0.8), Vector3(sx * 0.11, 0.71, -1.0), 0.007, CHROME, 5)
		tube(kt, Vector3(sx * 0.11, 0.71, -0.98), Vector3(sx * 0.09, 0.6, -0.88), 0.007, CHROME, 5)
	tube(kt, Vector3(-0.11, 0.71, -1.0), Vector3(0.11, 0.71, -1.0), 0.007, CHROME, 5)
	# hluboké blatníky s návazností (lak)
	fender(kp, ra, wr + 0.055, -0.25, PI + 0.28, 0.1, Color.WHITE)
	fender(kp, fa, wr + 0.055, 0.15, PI + 0.05, 0.1, Color.WHITE)
	# zadní světlo + SPZ na blatníku
	ktl.box(Vector3(0, m.spec["tail_y"], m.spec["tail_z"]), Vector3(0.07, 0.09, 0.03), Color(0.9, 0.05, 0.03))
	kt.box(Vector3(0, m.spec["tail_y"] - 0.13, m.spec["tail_z"] - 0.06), Vector3(0.2, 0.15, 0.01), Color(0.95, 0.95, 0.95), Vector3(-0.2, 0, 0))
	m.plate_pos = Vector3(0, m.spec["tail_y"] - 0.13, m.spec["tail_z"] - 0.07)
	# stojan vlevo
	tube(kt, Vector3(0.12, 0.28, -0.12), Vector3(0.3, 0.02, -0.22), 0.012, frame, 5)
	# vidlice springer: dvě paralelní lišty + vzpěra svinuté pružiny nahoře, široká „beach“ řídítka
	m.fork_pivot = head
	m.fork_axis = (head - fa).normalized()
	var fl := fa - head
	for sx in [-1.0, 1.0]:
		tube(kf, Vector3(sx * 0.055, 0.0, 0.0), Vector3(sx * 0.055, 0.0, 0.0) + fl * 0.55, 0.022, m.paint, 8)
		tube(kf, Vector3(sx * 0.05, -0.04, 0.06), fl + Vector3(sx * 0.05, 0.0, 0.03), 0.013, CHROME, 6)
		kf.cylinder(Vector3(sx * 0.055, -0.03, 0.04), 0.026, 0.026, 0.13, frame, Vector3(-0.5, 0, 0), 10)
	kf.cylinder(fl, 0.035, 0.035, 0.14, CHROME, Vector3(0, 0, PI / 2), 12)
	# velké světlo v baňce s krycí klapkou + houkačka
	kf.cylinder(Vector3(0, 0.03, 0.21), 0.09, 0.095, 0.09, frame, Vector3(PI / 2, 0, 0), 16)
	kh.cylinder(Vector3(0, 0.03, 0.257), 0.08, 0.08, 0.008, Color(1.0, 0.97, 0.85), Vector3(PI / 2, 0, 0), 16)
	kf.box(Vector3(0, 0.12, 0.23), Vector3(0.13, 0.06, 0.1), frame, Vector3(-0.2, 0, 0))
	kf.cylinder(Vector3(0, -0.03, 0.24), 0.035, 0.04, 0.035, frame, Vector3(PI / 2, 0, 0), 10)
	var grip := Vector3(0.3, 0.13, -0.2)
	for sx in [-1.0, 1.0]:
		tube(kf, Vector3(sx * 0.05, 0.0, 0.0), Vector3(sx * 0.09, 0.1, -0.04), 0.012, CHROME, 6)
		tube(kf, Vector3(sx * 0.09, 0.1, -0.04), Vector3(sx * 0.2, 0.14, -0.11), 0.012, CHROME, 6)
		tube(kf, Vector3(sx * 0.2, 0.14, -0.11), grip * Vector3(sx, 1, 1), 0.012, CHROME, 6)
		kf.capsule(grip * Vector3(sx, 1, 1) + Vector3(sx * 0.03, 0, 0), 0.018, 0.11, BLACK, Vector3(0, 0, PI / 2))
	kf.cylinder(Vector3(0.22, 0.16, -0.08), 0.025, 0.025, 0.012, CHROME)                       # zrcátko
	# jezdec: pružené sedlo, nohy na nášlapech dopředu, široká řídítka tažená k jezdci
	m.seat = Vector3(0, 0.0, -0.38)
	var lean := 0.2
	var board := Vector3(0.19, 0.26, 0.1) - m.seat
	m.rider = {"hips": 0.84, "lean": lean, "hands": [head + grip - m.seat], "feet": [board, board]}
	m.eye = m.seat + Vector3(0, 0.84 + 0.67 * cos(lean), 0.67 * sin(lean) + 0.08)


# ------------------------------------------------------------------ Krosák 1000 (ultra-rychlá kroska, litrový motor)

static func _krosak(m: CarModel, kp: MeshKit, kt: MeshKit, kf: MeshKit, kh: MeshKit, ktl: MeshKit) -> void:
	var wr: float = m.spec["wheel_r"]
	var wb: float = m.spec["wb"]
	var ra := Vector3(0, wr, -wb * 0.5)
	var fa := Vector3(0, wr, wb * 0.5)
	var head := Vector3(0, 1.02, 0.38)
	var frame := Color(0.06, 0.06, 0.07)
	var alu := Color(0.6, 0.61, 0.63)
	# dvoukloubový rám: svařované nosníky podél nádrže, subrám dozadu, kyvná vidlice
	for sx in [-1.0, 1.0]:
		tube(kt, Vector3(sx * 0.07, 0.9, 0.3), Vector3(sx * 0.07, 0.68, -0.32), 0.032, alu, 8)
		tube(kt, Vector3(sx * 0.05, 0.75, -0.3), Vector3(sx * 0.05, 0.92, -0.6), 0.011, frame, 6)
		kt.box(Vector3(sx * 0.1, 0.36, -0.42), Vector3(0.03, 0.09, 0.62), alu, Vector3(0.06, 0, 0))
		tube(kt, Vector3(sx * 0.09, 0.42, -0.14), ra + Vector3(sx * 0.09, 0, 0), 0.018, frame)
	# kompaktní řadový motor + výfuk vedený vysoko vpravo (kroskový styl)
	kt.box(Vector3(0, 0.42, 0.12), Vector3(0.3, 0.3, 0.42), alu.darkened(0.1))
	kt.box(Vector3(0, 0.62, 0.14), Vector3(0.24, 0.15, 0.3), alu)
	kt.cylinder(Vector3(0.0, 0.34, 0.14), 0.1, 0.1, 0.24, alu.darkened(0.2), Vector3(0, 0, PI / 2), 14)
	kt.box(Vector3(0, 0.24, 0.1), Vector3(0.28, 0.03, 0.5), frame)
	for sx in [-1.0, 1.0]:
		tube(kt, Vector3(sx * 0.11, 0.34, 0.02), Vector3(sx * 0.21, 0.34, 0.02), 0.015, frame)
		kt.box(Vector3(sx * 0.24, 0.33, 0.02), Vector3(0.09, 0.015, 0.07), RUBBER)
	tube(kt, Vector3(0.07, 0.45, 0.24), Vector3(0.15, 0.56, -0.02), 0.026, CHROME)
	tube(kt, Vector3(0.15, 0.56, -0.02), Vector3(0.17, 0.8, -0.38), 0.026, CHROME)
	kt.capsule(Vector3(0.17, 0.82, -0.56), 0.05, 0.36, alu, Vector3(PI / 2 - 0.1, 0, 0))
	# úzká nádrž (lak), špičaté kryty chladiče (lak), dlouhé ploché sedlo, krátký ocas
	kp.sphere(Vector3(0, 0.9, 0.08), 0.14, Color.WHITE, Vector3(0.78, 0.68, 1.55), Vector3(0.12, 0, 0), 16, 10)
	for sx in [-1.0, 1.0]:
		kp.box(Vector3(sx * 0.15, 0.74, 0.28), Vector3(0.025, 0.34, 0.3), Color.WHITE, Vector3(-0.35, sx * -0.2, sx * 0.08))
		kp.box(Vector3(sx * 0.12, 0.86, -0.05), Vector3(0.02, 0.1, 0.4), Color.WHITE, Vector3(0.1, 0, sx * 0.05))
	kt.box(Vector3(0, 0.9, -0.32), Vector3(0.16, 0.05, 0.78), Color(0.08, 0.08, 0.09), Vector3(0.04, 0, 0))
	kp.box(Vector3(0, 0.87, -0.72), Vector3(0.13, 0.04, 0.3), Color.WHITE, Vector3(-0.18, 0, 0))
	fender(kp, ra, wr + 0.04, PI * 0.5, PI + 0.15, 0.055, Color.WHITE)
	# zadní světlo + SPZ pod ocasem
	ktl.box(Vector3(0, m.spec["tail_y"], m.spec["tail_z"]), Vector3(0.1, 0.04, 0.03), Color(0.9, 0.05, 0.03))
	kt.box(Vector3(0, m.spec["tail_y"] - 0.1, m.spec["tail_z"] - 0.02), Vector3(0.18, 0.13, 0.01), Color(0.95, 0.95, 0.95), Vector3(-0.3, 0, 0))
	m.plate_pos = Vector3(0, m.spec["tail_y"] - 0.1, m.spec["tail_z"] - 0.03)
	tube(kt, Vector3(0.1, 0.3, -0.2), Vector3(0.26, 0.02, -0.28), 0.011, frame, 5)
	# USD vidlice: tlusté vnější nohy v laku, tenké chromované písty; vysoký blatník, čelní maska se světlem
	m.fork_pivot = head
	m.fork_axis = (head - fa).normalized()
	var fl := fa - head
	for sx in [-1.0, 1.0]:
		tube(kf, Vector3(sx * 0.065, 0.0, 0.0), Vector3(sx * 0.065, 0.0, 0.0) + fl * 0.62, 0.027, m.paint, 10)
		tube(kf, Vector3(sx * 0.065, 0.0, 0.0) + fl * 0.58, fl + Vector3(sx * 0.065, 0, 0), 0.016, CHROME, 8)
	kf.cylinder(fl, 0.03, 0.03, 0.16, alu, Vector3(0, 0, PI / 2), 12)
	fender(kf, fl, wr + 0.11, 0.45, PI - 0.55, 0.075, m.paint)
	kf.box(Vector3(0, 0.02, 0.15), Vector3(0.2, 0.32, 0.025), m.paint, Vector3(-0.48, 0, 0))
	kh.cylinder(Vector3(0, 0.0, 0.163), 0.05, 0.05, 0.008, Color(1.0, 0.97, 0.85), Vector3(PI / 2 - 0.48, 0, 0), 14)
	var grip := Vector3(0.27, 0.12, -0.06)
	tube(kf, Vector3(-0.27, 0.12, -0.06), Vector3(0.27, 0.12, -0.06), 0.012, CHROME, 6)
	for sx in [-1.0, 1.0]:
		tube(kf, Vector3(sx * 0.06, 0.0, 0.0), Vector3(sx * 0.08, 0.11, -0.04), 0.013, alu, 6)
		kf.capsule(grip * Vector3(sx, 1, 1) + Vector3(sx * 0.03, 0, 0), 0.018, 0.11, BLACK, Vector3(0, 0, PI / 2))
	kf.box(Vector3(0, 0.12, -0.05), Vector3(0.06, 0.03, 0.05), RUBBER)
	# jezdec: vysoko posazený, trup mírně vepředu, nohy na stupačkách pod tělem
	m.seat = Vector3(0, 0.0, -0.3)
	var lean := 0.32
	var peg := Vector3(0.16, 0.45, -0.02) - m.seat
	m.rider = {"hips": 0.96, "lean": lean, "hands": [head + grip - m.seat], "feet": [peg, peg]}
	m.eye = m.seat + Vector3(0, 0.96 + 0.67 * cos(lean), 0.67 * sin(lean) + 0.08)
