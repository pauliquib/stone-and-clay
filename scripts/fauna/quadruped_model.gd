## Stavitel modelu čtyřnohého zvířete z AnimalSpecs → QuadrupedRig (uzly kloubů + meshe).
##
## Trup je „loft“ eliptických průřezů od zadku po hruď (rozměry chest / belly / hips), krk a hlava jsou
## rotační tělesa podél vlastní osy, nohy mají 3 články (stehno / předloktí, holeň / záprstí, spěnka
## s kopytem). Délky článků se dopočítají tak, aby noha v klidovém úhlu přesně dosáhla na zem.
## Doplňky podle druhu: parůžky, kly, hříva, žíně, lysina, zrcátko, pruhy selat, sedlo s uzdečkou.
##
## Meshe se pro stejný druh a variantu staví jen jednou a sdílejí (výkon); jedinci se liší odstínem srsti.
class_name QuadrupedModel
extends RefCounted

const RING := 16                     # bodů na průřez trupu
const VIS_END := 230.0               # do jaké vzdálenosti je zvíře vidět

static var _cache := {}
static var _mats := {}


## variant: {"male": bool, "winter": bool, "tint": 0.85–1.15, "young": bool}
static func build(spec: Dictionary, variant := {}) -> QuadrupedRig:
	var g := geometry(spec)
	var rig := QuadrupedRig.new()
	rig.spec = spec
	rig.body_y = g["y_mid"]
	rig.lie_y = g["lie_y"]
	rig.shoulder_h = g["shoulder_h"]
	rig.neck_angle = spec["neck"][2]
	rig.head_tilt = spec["head"][3]
	var male: bool = variant.get("male", false)
	var winter: bool = variant.get("winter", false)
	var key := "%s|%s|%s" % [spec["id"], male, winter]
	if not _cache.has(key):
		_cache[key] = _build_meshes(spec, g, male, winter)
	var ms: Dictionary = _cache[key]
	var fur := fur_material(float(variant.get("tint", 1.0)))

	rig.body = _node(rig, Vector3(0, g["y_mid"], 0))
	_mi(rig.body, ms["torso"], fur)
	rig.neck = _node(rig.body, g["neck_base"])
	_mi(rig.neck, ms["neck"], fur)
	rig.head = _node(rig.neck, Vector3(0, 0, float(spec["neck"][0])))
	_mi(rig.head, ms["head"], fur)
	for side: float in [1.0, -1.0]:
		var hr: float = spec["head"][1]
		var e := _node(rig.head, Vector3(side * hr * 0.5, hr * 0.72, -hr * 0.05))
		e.set_meta("side", side)
		e.set_meta("rest", Vector3(-0.35, 0.0, -side * float(spec["ears"][2])))
		e.rotation = e.get_meta("rest")
		_mi(e, ms["ear"], fur)
		rig.ears.append(e)
	rig.tail = _node(rig.body, g["tail_base"])
	rig.tail.set_meta("rest", Vector3(-float(spec["tail"][2]), 0, 0))
	rig.tail.rotation = rig.tail.get_meta("rest")
	_mi(rig.tail, ms["tail"], fur)
	# nohy: 0 LP, 1 PP, 2 LZ, 3 PZ
	for i in 4:
		var front := i < 2
		var side := 1.0 if i % 2 == 0 else -1.0
		var jp: Vector3 = g["shoulder"] if front else g["hip"]
		var top := _node(rig.body, Vector3(jp.x * side, jp.y, jp.z))
		var lens: Array = g["front_len"] if front else g["hind_len"]
		var n1 := _node(top, Vector3(0, -lens[0], 0))
		var n2 := _node(n1, Vector3(0, -lens[1], 0))
		var pre := "f" if front else "h"
		_mi(top, ms[pre + "0"], fur)
		_mi(n1, ms[pre + "1"], fur)
		_mi(n2, ms[pre + "2"], fur)
		rig.legs.append({"nodes": [top, n1, n2], "front": front, "side": side,
			"jpos": Vector3(jp.x * side, jp.y, jp.z), "lens": lens,
			"rest": spec["front_rest" if front else "hind_rest"], "fold": spec["front_fold" if front else "hind_fold"],
			"lie": spec["front_lie" if front else "hind_lie"]})
	if spec.get("tack", false):
		var sp: Vector3 = g["saddle"]
		rig.saddle = _node(rig.body, sp)
		rig.ride = g["ride"]
	return rig


## Rozměry odvozené ze specifikace (vše vůči uzlu trupu, který je ve výšce y_mid nad zemí).
static func geometry(spec: Dictionary) -> Dictionary:
	var L: float = spec["length"]
	var ch: Array = spec["chest"]
	var hp: Array = spec["hips"]
	var be: Array = spec["belly"]
	var y_cf: float = spec["withers"] - ch[1]
	var y_cr: float = spec["croup"] - hp[1]
	var y_mid := (y_cf + y_cr) * 0.5
	var g := {"L": L, "y_cf": y_cf, "y_cr": y_cr, "y_mid": y_mid}
	g["shoulder"] = Vector3(ch[0] * 0.55, y_cf - ch[1] * 0.35 - y_mid, L * 0.5 - ch[1] * 0.45)
	g["hip"] = Vector3(hp[0] * 0.6, y_cr - hp[1] * 0.25 - y_mid, -L * 0.5 + hp[1] * 0.55)
	g["shoulder_h"] = y_cf - ch[1] * 0.35
	g["hip_h"] = y_cr - hp[1] * 0.25
	g["neck_base"] = Vector3(0, y_cf - y_mid + ch[1] * 0.4, L * 0.5 - ch[1] * 0.2)
	g["tail_base"] = Vector3(0, y_cr - y_mid + hp[1] * 0.55, -L * 0.5 - hp[1] * 0.3)
	g["lie_y"] = maxf(ch[1], be[1]) * 1.02 + float(spec["belly_drop"])
	g["front_len"] = _seg_lengths(spec["front_seg"], spec["front_rest"], g["shoulder_h"])
	g["hind_len"] = _seg_lengths(spec["hind_seg"], spec["hind_rest"], g["hip_h"])
	if spec.get("tack", false):
		var zs: float = L * 0.5 - ch[1] * 1.25
		var st := station_at_z(spec, g, zs)
		var top: float = st[1] + st[3]
		g["saddle_top"] = top
		g["saddle_z"] = zs
		g["saddle"] = Vector3(0, top + 0.1, zs)
		# póza jezdce vůči sedlu: třmeny, ruce s otěžemi nad kohoutkem
		g["ride"] = {"stirrup": Vector3(st[2] + 0.07, -0.74, 0.04), "hands": Vector3(0, 0.3, 0.48), "spread_x": st[2]}
	return g


## Délky článků nohy tak, aby v klidových úhlech sahala z kloubu (výška h) přesně na zem.
static func _seg_lengths(ratios: Array, rest: Array, h: float) -> Array:
	var sum := 0.0
	for j in 3:
		sum += float(ratios[j]) * cos(float(rest[j]))
	var k := h / maxf(sum, 0.05)
	return [ratios[0] * k, ratios[1] * k, ratios[2] * k]


## Průřez trupu v poměrné poloze u (0 zadek … 1 hruď): [z, střed y, rx, ry].
static func station(spec: Dictionary, g: Dictionary, u: float) -> Array:
	var ch: Array = spec["chest"]
	var hp: Array = spec["hips"]
	var be: Array = spec["belly"]
	var L: float = g["L"]
	var z := lerpf(-L * 0.5 - hp[1] * 0.45, L * 0.5 + ch[1] * 0.4, u)
	var rx: float
	var ry: float
	var yc: float
	var y_r: float = g["y_cr"] - g["y_mid"]
	var y_f: float = g["y_cf"] - g["y_mid"]
	var y_b: float = -float(spec["belly_drop"])
	if u <= 0.2:
		rx = hp[0]; ry = hp[1]; yc = y_r
	elif u <= 0.5:
		var t := smoothstep(0.2, 0.5, u)
		rx = lerpf(hp[0], be[0], t); ry = lerpf(hp[1], be[1], t); yc = lerpf(y_r, (y_r + y_f) * 0.5 + y_b, t)
	elif u <= 0.78:
		var t := smoothstep(0.5, 0.78, u)
		rx = lerpf(be[0], ch[0], t); ry = lerpf(be[1], ch[1], t); yc = lerpf((y_r + y_f) * 0.5 + y_b, y_f, t)
	else:
		rx = ch[0]; ry = ch[1]; yc = y_f
	# zaoblené konce
	var sc := 1.0
	if u < 0.2:
		sc = sqrt(clampf(1.0 - pow((0.2 - u) / 0.2, 2.2), 0.0, 1.0))
	elif u > 0.8:
		sc = sqrt(clampf(1.0 - pow((u - 0.8) / 0.2, 2.2), 0.0, 1.0))
	sc = maxf(sc, 0.04)
	# konce se zužují víc do šířky než do výšky (zadek, prsa)
	return [z, yc, rx * sc, ry * lerpf(1.0, sc, 0.85)]


static func station_at_z(spec: Dictionary, g: Dictionary, z: float) -> Array:
	var ch: Array = spec["chest"]
	var hp: Array = spec["hips"]
	var L: float = g["L"]
	var u := inverse_lerp(-L * 0.5 - hp[1] * 0.45, L * 0.5 + ch[1] * 0.4, z)
	return station(spec, g, clampf(u, 0.0, 1.0))


# ------------------------------------------------------------------ stavba meshů

static func _build_meshes(spec: Dictionary, g: Dictionary, male: bool, winter: bool) -> Dictionary:
	var ms := {}
	var coat: Color = spec.get("winter_coat", spec["coat"]) if winter else spec["coat"]
	var belly_c: Color = spec["belly_col"]
	var dark: Color = spec["dark"]
	var fur := fur_material(1.0)
	# ---------------- trup
	var k := MeshKit.new()
	var rings := []
	var cols := []
	var us := [0.0, 0.02, 0.05, 0.1, 0.16, 0.22, 0.32, 0.42, 0.52, 0.62, 0.72, 0.8, 0.86, 0.92, 0.96, 0.985, 1.0]
	var rump: Color = spec["rump"]
	var stripes: Color = spec["stripes"]
	for u in us:
		var st := station(spec, g, u)
		var ring := PackedVector3Array()
		var rc := PackedColorArray()
		for j in RING:
			var a := TAU * j / RING
			var sa := sin(a)
			ring.append(Vector3(st[2] * cos(a), st[1] + st[3] * sa, st[0]))
			var c := coat.lerp(belly_c, smoothstep(-0.2, -0.75, sa))
			if sa > 0.85:
				c = c.darkened(0.1)
			if rump.r >= 0.0 and u < 0.17:
				c = c.lerp(rump, (1.0 - u / 0.17) * smoothstep(0.95, 0.2, sa))
			if stripes.r >= 0.0 and sa > -0.35 and j % 2 == 0 and u > 0.08 and u < 0.9:
				c = stripes
			rc.append(c)
		rings.append(ring)
		cols.append(rc)
	k.loft(rings, cols, true)
	# štětinová hříva divočáka (hřbet od kohoutku do poloviny)
	var mane: float = spec.get("mane", 0.0)
	if mane > 0.0 and not spec.get("tack", false):
		for i in 10:
			var u := lerpf(0.9, 0.35, i / 9.0)
			var st := station(spec, g, u)
			var hgt := mane * (1.0 - i / 12.0)
			k.box(Vector3(0, st[1] + st[3] + hgt * 0.3, st[0]), Vector3(0.025, hgt, 0.09), dark.darkened(0.2), Vector3(-0.25, 0, 0))
	if spec.get("tack", false):
		_tack_body(k, spec, g)
	ms["torso"] = k.commit(fur)

	# ---------------- krk (podél +Z)
	k = MeshKit.new()
	var nk: Array = spec["neck"]
	var r0: float = nk[1]
	var rt: float = spec["neck_top_r"]
	var nl: float = nk[0]
	var to_z := Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3.ZERO)
	k.lathe(PackedVector2Array([Vector2(r0 * 0.3, -r0 * 1.1), Vector2(r0 * 0.95, -r0 * 0.5), Vector2(r0, 0.0),
		Vector2(lerpf(r0, rt, 0.55), nl * 0.5), Vector2(rt, nl), Vector2(rt * 0.7, nl + rt * 0.5)]), to_z, coat, 14, 0.72, 1.0)
	if mane > 0.0 and spec.get("tack", false):
		var hair: Color = spec.get("hair", dark)
		for i in 11:
			var t := i / 10.0
			var r := lerpf(r0, rt, t)
			k.box(Vector3(0.012 * sin(i * 1.7), r * 0.98 + mane * 0.35, t * nl * 1.02 - nl * 0.02), Vector3(0.035, mane * (1.1 - t * 0.35), nl / 9.0),
				hair, Vector3(0.15, 0, 0.12 * sin(i * 2.3)))
	if mane > 0.0 and not spec.get("tack", false):
		for i in 5:
			var t := i / 4.0
			k.box(Vector3(0, lerpf(r0, rt, t) + mane * 0.35, t * nl), Vector3(0.025, mane, nl / 4.0), dark.darkened(0.2))
	if spec.get("tack", false):
		_reins(k, spec, nl, rt)
	ms["neck"] = k.commit(fur)

	# ---------------- hlava (podél +Z)
	k = MeshKit.new()
	var hd: Array = spec["head"]
	var hl: float = hd[0]
	var hr: float = hd[1]
	var sr: float = hd[2]
	var nose: Color = spec["nose"]
	var prof := PackedVector2Array([Vector2(0.002, -hr * 0.6), Vector2(hr * 0.72, -hr * 0.38), Vector2(hr, -hr * 0.05),
		Vector2(hr * 0.93, hl * 0.28), Vector2(lerpf(hr, sr, 0.55), hl * 0.6), Vector2(sr * 1.12, hl * 0.86),
		Vector2(sr, hl * 0.97), Vector2(sr * 0.55, hl + 0.004), Vector2(0.002, hl + 0.006)])
	var pc := PackedColorArray([coat, coat, coat, coat, coat.lerp(nose, 0.15), coat.lerp(nose, 0.5), nose, nose, nose])
	k.lathe(prof, to_z, coat, 16, 0.8, 1.0, pc)
	var blaze: Color = spec.get("blaze", Color(-1, 0, 0))
	if blaze.r >= 0.0:
		k.sphere(Vector3(0, hr * 0.8, hl * 0.42), 1.0, blaze, Vector3(hr * 0.2, hr * 0.14, hl * 0.4))
	# kly
	var tusk: float = spec.get("tusks", 0.0) * (1.0 if male else 0.45)
	if tusk > 0.0:
		for s: float in [1.0, -1.0]:
			k.capsule(Vector3(s * sr * 1.05, sr * 0.2, hl * 0.84), 0.008 + tusk * 0.08, tusk, Color(0.92, 0.88, 0.78),
				Vector3(0.9, 0, -s * 0.5))
	# parůžky srnce (v listopadu a prosinci shozené)
	var ant: float = spec.get("antlers", 0.0)
	if ant > 0.0 and male and not winter:
		var bone := Color(0.42, 0.34, 0.25)
		for s: float in [1.0, -1.0]:
			var base := Vector3(s * hr * 0.32, hr * 0.85, hr * 0.15)
			k.sphere(base, 0.018, bone.darkened(0.2))
			var top := base + Vector3(s * 0.03, ant, -ant * 0.2)
			_stick(k, base, top, 0.012, 0.007, bone)
			_stick(k, base + (top - base) * 0.55, base + (top - base) * 0.55 + Vector3(0, ant * 0.25, ant * 0.35), 0.008, 0.005, bone.lightened(0.15))
			_stick(k, top, top + Vector3(0, ant * 0.12, -ant * 0.25), 0.007, 0.004, bone.lightened(0.3))
	if spec.get("tack", false):
		_bridle(k, hl, hr, sr)
		var hair: Color = spec.get("hair", dark)
		k.sphere(Vector3(0, hr * 0.95, -hr * 0.05), 1.0, hair, Vector3(0.035, 0.05, 0.1), Vector3(0.6, 0, 0))
	var head_mesh := k.commit(fur)
	var ke := MeshKit.new()
	var er: float = spec["eye_r"]
	for s: float in [1.0, -1.0]:
		ke.sphere(Vector3(s * hr * 0.74, hr * 0.38, hl * 0.2), er, Color(0.02, 0.015, 0.01), Vector3.ONE, Vector3.ZERO, 8, 5)
	ke.commit(eye_material(), head_mesh)
	ms["head"] = head_mesh

	# ---------------- ucho (podél +Y, zploštělé)
	k = MeshKit.new()
	var ea: Array = spec["ears"]
	var el: float = ea[0]
	var ew: float = ea[1]
	var tip: Color = spec.get("ear_tip", coat)
	var inner: Color = spec["inner_ear"]
	k.lathe(PackedVector2Array([Vector2(ew * 0.25, 0.0), Vector2(ew * 0.5, el * 0.15), Vector2(ew * 0.52, el * 0.5),
		Vector2(ew * 0.34, el * 0.82), Vector2(0.002, el)]), Transform3D.IDENTITY, coat, 10, 1.0, 0.32,
		PackedColorArray([coat, coat, coat.lerp(inner, 0.25), tip, tip]))
	ms["ear"] = k.commit(fur)

	# ---------------- ocas (podél −Z)
	k = MeshKit.new()
	var tl: Array = spec["tail"]
	var to_mz := Transform3D(Basis(Vector3.RIGHT, -PI / 2), Vector3.ZERO)
	var tr: float = tl[1]
	var tlen: float = tl[0]
	k.lathe(PackedVector2Array([Vector2(0.002, -tr), Vector2(tr, 0.0), Vector2(tr * 0.8, tlen * 0.6),
		Vector2(tr * 0.5, tlen), Vector2(0.002, tlen + tr * 0.3)]), to_mz, coat, 10)
	var th: float = spec.get("tail_hair", 0.0)
	if th > 0.0:
		var hair: Color = spec.get("hair", dark)
		k.sphere(Vector3(0, -0.02, -(tlen + th * 0.42)), 1.0, hair, Vector3(0.075, 0.06, th * 0.5))
	if spec["id"] in ["divocak", "sele"]:
		k.sphere(Vector3(0, 0, -tlen), tr * 3.0, dark)
	if rump.r >= 0.0 and spec["behaviour"] == "hare":
		k.sphere(Vector3(0, 0, -tlen * 0.5), tr * 1.2, rump)
	ms["tail"] = k.commit(fur)

	# ---------------- nohy (podél −Y)
	var lr: Array = spec["leg_r"]
	var hoof: Array = spec["hoof"]
	for front in [true, false]:
		var lens: Array = g["front_len"] if front else g["hind_len"]
		var pre := "f" if front else "h"
		var r_top: float = lr[0] * (1.0 if front else 1.35)
		var radii := [[r_top, lerpf(r_top, lr[1], 0.55)], [lerpf(r_top, lr[1], 0.6), lr[1] * 1.1], [lr[1], lr[1] * 0.95]]
		for j in 3:
			k = MeshKit.new()
			var l: float = lens[j]
			var ra: float = radii[j][0]
			var rb: float = radii[j][1]
			var c := coat.lerp(dark, [0.0, 0.35, 0.8][j])
			if j == 0:
				# stehno / plece přechází do trupu – širší horní konec
				k.lathe(PackedVector2Array([Vector2(0.002, -l - rb * 0.5), Vector2(rb, -l), Vector2(lerpf(ra, rb, 0.5), -l * 0.5),
					Vector2(ra, -l * 0.1), Vector2(ra * 0.95, ra * 0.5), Vector2(0.002, ra * 1.1)]), Transform3D.IDENTITY,
					coat, 12, 0.8, 1.0)
			else:
				k.lathe(PackedVector2Array([Vector2(0.002, -l - rb * 0.4), Vector2(rb, -l), Vector2(lerpf(ra, rb, 0.5), -l * 0.5),
					Vector2(ra, 0.0), Vector2(0.002, ra * 0.7)]), Transform3D.IDENTITY, c, 10, 0.85, 1.0)
			if j == 2:
				var hc: Color = spec["hoof_col"]
				if spec["paws"]:
					k.sphere(Vector3(0, -l, hoof[0] * 1.5), 1.0, c.lightened(0.1), Vector3(hoof[0] * 1.3, hoof[1] * 0.6, hoof[0] * 3.0))
				else:
					# kopyto natočené rovně k zemi (proti sklonu spěnky)
					var rest_a: float = (spec["front_rest"] if front else spec["hind_rest"])[2]
					k.cylinder(Vector3(0, -l + hoof[1] * 0.35, hoof[0] * 0.25), hoof[0] * 0.8, hoof[0] * 1.05, hoof[1], hc,
						Vector3(-rest_a * 0.8, 0, 0), 10)
			ms[pre + str(j)] = k.commit(fur)
	return ms


static func _stick(k: MeshKit, a: Vector3, b: Vector3, ra: float, rb: float, c: Color) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.001:
		return
	var y := d / l
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	var m := CylinderMesh.new()
	m.top_radius = rb
	m.bottom_radius = ra
	m.height = l
	m.radial_segments = 6
	m.rings = 1
	k.add_prim(m, Transform3D(Basis(x, y, z), (a + b) * 0.5), c)


# ------------------------------------------------------------------ výstroj koně

static func _tack_body(k: MeshKit, spec: Dictionary, g: Dictionary) -> void:
	var zs: float = g["saddle_z"]
	var top: float = g["saddle_top"]
	var st := station_at_z(spec, g, zs)
	var rx: float = st[2]
	var ry: float = st[3]
	var yc: float = st[1]
	var leather := Color(0.24, 0.13, 0.06)
	var pad := Color(0.16, 0.2, 0.34)
	# podsedlová dečka a sedlo
	k.sphere(Vector3(0, top - 0.03, zs), 1.0, pad, Vector3(rx * 1.08, 0.075, 0.38))
	k.sphere(Vector3(0, top + 0.02, zs), 1.0, leather, Vector3(rx * 0.72, 0.075, 0.28))
	k.sphere(Vector3(0, top + 0.08, zs + 0.2), 1.0, leather.darkened(0.2), Vector3(0.07, 0.06, 0.06))   # hrušky
	k.sphere(Vector3(0, top + 0.09, zs - 0.22), 1.0, leather, Vector3(rx * 0.55, 0.06, 0.05))           # zadní rozsocha
	# podbřišník
	k.lathe(PackedVector2Array([Vector2(1.0, -0.035), Vector2(1.0, 0.035)]),
		Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, yc, zs + 0.12)), leather.darkened(0.3), 20, rx * 1.03, ry * 1.03)
	# třmeny na řemenech
	var metal := Color(0.6, 0.6, 0.62)
	for s: float in [1.0, -1.0]:
		var x := s * (rx + 0.03)
		k.box(Vector3(x, top - 0.33, zs + 0.03), Vector3(0.012, 0.6, 0.035), leather)
		k.box(Vector3(x + s * 0.02, top - 0.69, zs + 0.03), Vector3(0.1, 0.012, 0.12), metal)
		k.box(Vector3(x + s * 0.02, top - 0.64, zs + 0.03 + 0.055), Vector3(0.1, 0.1, 0.012), metal)
		k.box(Vector3(x + s * 0.02, top - 0.64, zs + 0.03 - 0.055), Vector3(0.1, 0.1, 0.012), metal)


## Uzdečka: nánosník, čelenka, lícnice a udidlo.
static func _bridle(k: MeshKit, hl: float, hr: float, sr: float) -> void:
	var strap := Color(0.2, 0.11, 0.05)
	var nb_z := hl * 0.72
	var r_nb := lerpf(hr, sr, 0.72) * 1.08
	k.lathe(PackedVector2Array([Vector2(1.0, -0.018), Vector2(1.0, 0.018)]),
		Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0, nb_z)), strap, 14, r_nb * 0.82, r_nb)
	k.lathe(PackedVector2Array([Vector2(1.0, -0.016), Vector2(1.0, 0.016)]),
		Transform3D(Basis(Vector3.RIGHT, PI / 2 - 0.5), Vector3(0, hr * 0.15, hr * 0.15)), strap, 14, hr * 0.84, hr * 1.02)
	for s: float in [1.0, -1.0]:
		k.box(Vector3(s * hr * 0.8, hr * 0.1, hl * 0.4), Vector3(0.012, 0.03, hl * 0.7), strap, Vector3(-0.12, 0, 0))
		k.sphere(Vector3(s * sr * 1.05, -sr * 0.35, hl * 0.86), 0.022, Color(0.7, 0.7, 0.72))


## Otěže: od udidla podél krku ke kohoutku (jezdec je drží nad kohoutkem).
static func _reins(k: MeshKit, spec: Dictionary, nl: float, rt: float) -> void:
	var strap := Color(0.2, 0.11, 0.05)
	for s: float in [1.0, -1.0]:
		var hd: Array = spec["head"]
		var a := Vector3(s * float(hd[2]) * 1.05, 0, nl) + Basis(Vector3.RIGHT, float(hd[3])) * Vector3(0, -float(hd[2]) * 0.35, float(hd[0]) * 0.86)
		var b := Vector3(s * rt * 0.7, rt * 1.5, nl * 0.02)
		_stick(k, a, b, 0.008, 0.008, strap)


# ------------------------------------------------------------------ pomocné

static func fur_material(tint := 1.0) -> StandardMaterial3D:
	var key := "fur_%.2f" % tint
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true       # barvy ve specifikaci jsou sRGB (jako v editoru barev)
	m.albedo_color = Color(tint, tint, tint)
	m.roughness = 0.88
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_BURLEY
	_mats[key] = m
	return m


static func eye_material() -> StandardMaterial3D:
	if _mats.has("eye"):
		return _mats["eye"]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.12
	m.metallic_specular = 0.9
	_mats["eye"] = m
	return m


static func _node(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


static func _mi(parent: Node3D, mesh: ArrayMesh, fur: Material) -> MeshInstance3D:
	var mi := MeshKit.mesh_instance(parent, mesh, VIS_END)
	mi.set_surface_override_material(0, fur)
	return mi
