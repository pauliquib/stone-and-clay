## Načítání geometrie exportované z Blenderu (tools/export_map.py):
## budovy, střechy, cesty (DBM1, po dlaždicích 256 m) a stromy (DBT1 prototypy + DBI1 instance).
class_name MapLoader
extends RefCounted

const TREE_CELL := 128.0
const TREE_FAR_CELL := 256.0
const DEC_FULL_RANGE := 170.0
const TREE_FAR_RANGE := 2600.0

## Druhy procedurálních materiálů (uniform `mat_kind` v tinted_triplanar.gdshader).
const KIND_WALL := 1
const KIND_ROOF := 2
const KIND_ASPHALT := 3
const KIND_GRAVEL := 4
## Drapování silnic na terén (load_chunks): hrana se půlí, když terén v její polovině uhne od přímky o víc než
## DRAPE_TOL (a hrana je delší než DRAPE_MIN_EDGE), nebo je delší než DRAPE_LONG. Rozhoduje se jen podle hrany →
## sousední trojúhelníky ji rozdělí stejně (žádné T-spoje ani škvíry). Mřížka terénu je 2 m.
const DRAPE_TOL := 0.03
const DRAPE_MIN_EDGE := 0.45
const DRAPE_LONG := 8.0
## Zdvih pásu silnice o šířku × DRAPE_W_LIFT: na křižovatkách se pásy překrývají – širší silnice leží o pár mm výš,
## krajnice vedlejší pod ní zmizí a koplanární plochy neblikají.
const DRAPE_W_LIFT := 0.003
## Posun výšky drapování podle druhu povrchu (přičte se k `drape_h` z World): štěrková cesta leží v terénu níž, asfalt
## o kus výš – kde štěrk najíždí na asfalt, je pod ním aspoň ~4 cm (dřív 1 cm → z-fighting) a štěrk nevisí nad trávou.
const DRAPE_KIND_OFFSET := {KIND_ASPHALT: 0.015, KIND_GRAVEL: -0.015}

## Prototypy stromů (Mesh s materiály, pořadí jako v tree_protos.bin) po `build_trees`; pro zasazené stromy (M2.5). Prázdné = zatím nenačteno.
static var shared_protos: Array = []
## M8.8: generované stromy (TreeGen, data/tree_species_protos.bin) po `build_trees` s přepínačem „treegen“, jinak null.
static var tree_gen: TreeGen = null

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


## Materiál zdí, střech a cest (`tinted_triplanar.gdshader`). S texturami Poly Haven (`textures/<tex>_*_2k.jpg`)
## původní triplanární cesta; bez nich (čistý checkout, textury nejsou v gitu – ASSETY.md) procedurální materiál
## podle druhu odvozeného z názvu textury: omítka, pálené tašky / eternit, asfalt se záplatami, štěrková cesta.
## Druh nese i meta `proc_kind` – `load_chunks` podle něj dopočítá atributy vrcholů (pata a okap zdí, okraje cest).
static func tinted_material(tex: String, size_m: float, desat: float, gain: float,
		use_tint := true, base_tint := Color(1, 1, 1), normal_strength := 0.7) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/tinted_triplanar.gdshader")
	var kind := proc_kind(tex)
	var diff := "res://textures/%s_diff_2k.jpg" % tex
	var has_tex := tex_available(diff)
	if has_tex:
		m.set_shader_parameter("albedo_tex", load(diff))
		for pair in [["normal_tex", "nor_gl"], ["rough_tex", "rough"]]:
			var p := "res://textures/%s_%s_2k.jpg" % [tex, pair[1]]
			if tex_available(p):
				m.set_shader_parameter(pair[0], load(p))
	m.set_shader_parameter("use_tex", has_tex)
	m.set_shader_parameter("mat_kind", kind)
	m.set_shader_parameter("noise_tex", ProcTextures.noise_rgba())
	m.set_shader_parameter("north_xz", north_xz())
	m.set_shader_parameter("tex_size_m", size_m)
	m.set_shader_parameter("desaturate", desat)
	m.set_shader_parameter("gain", gain)
	m.set_shader_parameter("use_vertex_tint", use_tint)
	m.set_shader_parameter("base_tint", base_tint)
	m.set_shader_parameter("normal_strength", normal_strength)
	m.set_meta("proc_kind", kind)
	return m


## Je importovaná textura opravdu k dispozici? `ResourceLoader.exists` vrací true už podle `.import` souboru,
## který je v gitu i bez obrázku (ASSETY.md) – `load` pak hlásí chybu a vrací null. Ověří se i cíl importu
## (`.godot/imported/…`, po exportu v balíčku).
static func tex_available(path: String) -> bool:
	if not ResourceLoader.exists(path):
		return false
	var imp := path + ".import"
	if not FileAccess.file_exists(imp):
		return true
	var cf := ConfigFile.new()
	if cf.load(imp) != OK or not cf.has_section("remap"):
		return FileAccess.file_exists(path)
	for k in cf.get_section_keys("remap"):
		if String(k).begins_with("path") and FileAccess.file_exists(String(cf.get_value("remap", k))):
			return true
	return false


## Druh procedurálního materiálu podle názvu textury: 1 omítka, 2 střecha, 3 asfalt, 4 štěrk, 0 obecný.
static func proc_kind(tex: String) -> int:
	if tex.contains("wall") or tex.contains("plaster"):
		return KIND_WALL
	if tex.contains("roof"):
		return KIND_ROOF
	if tex.contains("asphalt"):
		return KIND_ASPHALT
	if tex.contains("gravel"):
		return KIND_GRAVEL
	return 0


static var _north := Vector2.INF

## Světový sever v rovině x, z (mech a lišejník na severních stranách střech). Úhel z map.json bez parsování celého
## JSONu (soubor má stovky kB) – stačí najít klíč.
static func north_xz() -> Vector2:
	if _north != Vector2.INF:
		return _north
	var deg := 78.37
	var s := FileAccess.get_file_as_string("res://data/map.json")
	var i := s.find("\"north_angle_deg\"")
	if i >= 0:
		var j := s.find(":", i)
		var k := j + 1
		while k < s.length() and k < j + 40 and not (s[k] in [",", "}", "\n"]):
			k += 1
		var t := s.substr(j + 1, k - j - 1).strip_edges()
		if t.is_valid_float():
			deg = t.to_float()
	var nd := Clock.enu_to_world(Vector3(0.0, 1.0, 0.0), deg)
	_north = Vector2(nd.x, nd.z).normalized()
	return _north


## Načte DBM1 soubor → seznam dlaždic {mesh: ArrayMesh, faces: PackedVector3Array, origin: Vector3}.
## Vrcholy meshe i `faces` jsou LOKÁLNÍ vůči `origin` = střed AABB dlaždice (add_chunks na něj posadí
## MeshInstance3D i kolizní těleso). Proč: Godot 4.3 ořezává visibility range podle středu AABB instance,
## ale prolínání VISIBILITY_RANGE_FADE_SELF počítá z POČÁTKU uzlu (RenderForwardClustered:
## `inst->transform.origin.distance_to(cam)`). S uzlem v počátku světa (dům hráče) a geometrií
## v absolutních souřadnicích tak každá dlaždice zprůhlednila, jakmile byla kamera dál než dohled
## od spawnu – „za spawnem nic není“ (vlna 0b).
## `drape` – terén: povrch silnic/cest se "přilepí" na terén (konstantní výška nad ním). V exportu
## některé silnice (např. III/49010 u úřadu) visely až 1 m nad terénem, zatímco navazující místní
## komunikace terén kopírovaly → na křižovatkách vznikaly svislé schody, přes které auto neprojelo.
## M9 (vlna E): drapované cesty se adaptivně dělí (hrany přes nerovný terén se půlí, viz DRAPE_TOL) – dřív se
## posouvaly jen vrcholy a terén mezi nimi prorůstal (6,4 % vzorků asfaltu pod terénem). Normály drapovaných cest
## jsou normály terénu. Atributy vrcholů pro procedurální materiál (UV): cesty (s, W) – s = 0 na okraji pásu, 1
## u protějšího vrcholu, W = šířka pásu (vzdálenost od okraje = min(s, 1 − s) · W, krajnice a vyjeté stopy; okraj
## zakrytý jiným pásem – ústí odbočky – se za okraj nepočítá a s ∈ 2..3 značí lineární vzdálenost, viz _set_side);
## zdi (pata, vrchol) – světová výška spodní a horní hrany svislého sloupce zdi (sokl, šmouhy pod okapem).
## Výpočet dlaždic běží paralelně (WorkerThreadPool), meshe se skládají v hlavním vlákně.
static func load_chunks(path: String, mat: Material, drape: Terrain = null, drape_h := 0.1) -> Array:
	var bytes := FileAccess.get_file_as_bytes(path)
	assert(bytes.slice(0, 4).get_string_from_ascii() == "DBM1")
	var n_chunks := bytes.decode_s32(4)
	var off := 8
	var kind: int = mat.get_meta("proc_kind", 0) if mat != null else 0
	var jobs: Array[Dictionary] = []
	for _c in n_chunks:
		var n := bytes.decode_s32(off)
		off += 4
		var job := {
			"pos": bytes.slice(off, off + n * 12).to_float32_array(),
			"nrm": bytes.slice(off + n * 12, off + n * 24).to_float32_array(),
			"col": bytes.slice(off + n * 24, off + n * 36).to_float32_array(),
		}
		off += n * 36
		jobs.append(job)
	var field: DrapeField = DrapeField.new(drape) if drape else null
	if field != null:
		drape_h += float(DRAPE_KIND_OFFSET.get(kind, 0.0))
	var work := func(i: int) -> void:
		var job: Dictionary = jobs[i]
		if field != null:
			_drape_chunk(job, field, drape_h)
		else:
			_plain_chunk(job, kind == KIND_WALL)
	var gid := WorkerThreadPool.add_group_task(work, jobs.size(), -1, true, "MapLoader.load_chunks")
	WorkerThreadPool.wait_for_group_task_completion(gid)
	if mat is ShaderMaterial:
		if field != null:
			(mat as ShaderMaterial).set_shader_parameter("road_uv", true)
		elif kind == KIND_WALL:
			(mat as ShaderMaterial).set_shader_parameter("wall_cols", true)
	var out := []
	for job in jobs:
		var v: PackedVector3Array = job["v"]
		if v.is_empty():
			continue
		var box := AABB(v[0], Vector3.ZERO)
		for p in v:
			box = box.expand(p)
		# posun do lokálních souřadnic dlaždice (střed AABB) – viz komentář nad funkcí
		var origin := box.get_center()
		for i in v.size():
			v[i] = v[i] - origin
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = job["n"]
		arr[Mesh.ARRAY_COLOR] = job["c"]
		if job.has("uv"):
			arr[Mesh.ARRAY_TEX_UV] = job["uv"]
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		m.surface_set_material(0, mat)
		out.append({"mesh": m, "faces": v, "origin": origin})
	return out


## Výška terénu pro drapování (kopie výškové mřížky, čte se z vláken): max(bilineární = `Terrain.height_at`
## a kolize, trojúhelníková síť vizuálu LOD0 s úhlopříčkou (i+1, j)–(i, j+1)) – cesta nesmí pod žádnou z nich.
class DrapeField extends RefCounted:
	var hs: PackedFloat32Array
	var w: int
	var h: int
	var sp: float
	var x0: float
	var z0: float

	func _init(t: Terrain) -> void:
		hs = t.heights
		w = t.w
		h = t.h
		sp = t.spacing
		x0 = t.x0
		z0 = t.z0

	func at(x: float, z: float) -> float:
		var fx := clampf((x - x0) / sp, 0.0, w - 1.001)
		var fz := clampf((z - z0) / sp, 0.0, h - 1.001)
		var ix := int(fx)
		var iz := int(fz)
		var tx := fx - ix
		var tz := fz - iz
		var i := iz * w + ix
		var a := hs[i]
		var b := hs[i + 1]
		var c := hs[i + w]
		var d := hs[i + w + 1]
		var bil := lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)
		var tri := a + (b - a) * tx + (c - a) * tz if tx + tz <= 1.0 \
			else d + (c - d) * (1.0 - tx) + (b - d) * (1.0 - tz)
		return maxf(bil, tri)

	## Normála terénu (gradient bilineární plošky).
	func normal(x: float, z: float) -> Vector3:
		var fx := clampf((x - x0) / sp, 0.0, w - 1.001)
		var fz := clampf((z - z0) / sp, 0.0, h - 1.001)
		var ix := int(fx)
		var iz := int(fz)
		var tx := fx - ix
		var tz := fz - iz
		var i := iz * w + ix
		var a := hs[i]
		var b := hs[i + 1]
		var c := hs[i + w]
		var d := hs[i + w + 1]
		var gx := lerpf(b - a, d - c, tz) / sp
		var gz := lerpf(c - a, d - b, tx) / sp
		return Vector3(-gx, 1.0, -gz).normalized()


## Dlaždice bez drapování (zdi, střechy). Zdi (`cols`): UV = (pata, vrchol) svislého sloupce vrcholů se stejným x, z.
## Vrchol štítu (sloupec s jediným vrcholem) dostane patu nejbližšího plného sloupce (sokl se nekreslí ve štítu).
static func _plain_chunk(job: Dictionary, cols: bool) -> void:
	var pos: PackedFloat32Array = job["pos"]
	var nrm: PackedFloat32Array = job["nrm"]
	var col: PackedFloat32Array = job["col"]
	var n := pos.size() / 3
	var v := PackedVector3Array()
	var nn := PackedVector3Array()
	var cc := PackedColorArray()
	v.resize(n)
	nn.resize(n)
	cc.resize(n)
	for i in n:
		var k := i * 3
		v[i] = Vector3(pos[k], pos[k + 1], pos[k + 2])
		nn[i] = Vector3(nrm[k], nrm[k + 1], nrm[k + 2])
		cc[i] = Color(col[k], col[k + 1], col[k + 2])
	job["v"] = v
	job["n"] = nn
	job["c"] = cc
	job.erase("pos")
	job.erase("nrm")
	job.erase("col")
	if not cols or n == 0:
		return
	var span := {}            # Vector2i (2 cm) → Vector2(min y, max y)
	for p in v:
		var key := Vector2i(roundi(p.x * 50.0), roundi(p.z * 50.0))
		var r: Vector2 = span.get(key, Vector2(INF, -INF))
		span[key] = Vector2(minf(r.x, p.y), maxf(r.y, p.y))
	var full: Array[Vector3] = []          # (x, z, pata) plných sloupců
	for key in span:
		var r: Vector2 = span[key]
		if r.y - r.x > 0.3:
			full.append(Vector3(key.x / 50.0, key.y / 50.0, r.x))
	var uv := PackedVector2Array()
	uv.resize(n)
	var lone := {}            # sloupec s jediným vrcholem → pata nejbližšího plného sloupce
	for i in n:
		var p := v[i]
		var key := Vector2i(roundi(p.x * 50.0), roundi(p.z * 50.0))
		var r: Vector2 = span[key]
		if r.y - r.x > 0.3:
			uv[i] = r
			continue
		if not lone.has(key):
			var best := p.y - 50.0
			var bd := 625.0           # do 25 m
			for f in full:
				var d2 := (f.x - p.x) * (f.x - p.x) + (f.y - p.z) * (f.y - p.z)
				if d2 < bd:
					bd = d2
					best = f.z
			lone[key] = best
		uv[i] = Vector2(lone[key], p.y)
	job["uv"] = uv


static func _ekey(a: Vector3, b: Vector3) -> Vector4i:
	var qa := Vector2i(roundi(a.x * 50.0), roundi(a.z * 50.0))
	var qb := Vector2i(roundi(b.x * 50.0), roundi(b.z * 50.0))
	if qa.x < qb.x or (qa.x == qb.x and qa.y < qb.y):
		return Vector4i(qa.x, qa.y, qb.x, qb.y)
	return Vector4i(qb.x, qb.y, qa.x, qa.y)


## Vzdálenost bodu `c` od přímky a–b v rovině x, z.
static func _line_dist(a: Vector3, b: Vector3, c: Vector3) -> float:
	var d := Vector2(b.x - a.x, b.z - a.z)
	var l := d.length()
	if l < 0.001:
		return Vector2(c.x - a.x, c.z - a.z).length()
	return absf(d.x * (c.z - a.z) - d.y * (c.x - a.x)) / l


## Drapovaná dlaždice cesty: okraje pásů z topologie (hrana jen v jednom trojúhelníku = okraj), adaptivní dělení
## podle terénu a výška = terén + `drape_h` + zdvih podle šířky pásu.
static func _drape_chunk(job: Dictionary, f: DrapeField, drape_h: float) -> void:
	var pos: PackedFloat32Array = job["pos"]
	var col: PackedFloat32Array = job["col"]
	var n := pos.size() / 3
	var nt := n / 3
	var p := PackedVector3Array()
	p.resize(n)
	for i in n:
		p[i] = Vector3(pos[i * 3], pos[i * 3 + 1], pos[i * 3 + 2])
	# --- okraje pásů
	var ecount := {}
	for t in nt:
		for e in 3:
			var k := _ekey(p[t * 3 + e], p[t * 3 + (e + 1) % 3])
			ecount[k] = int(ecount.get(k, 0)) + 1
	# okraj, za kterým hned pokračuje jiný pás (ústí odbočky, konec pásu uvnitř křižovatky), okrajem není – jinak by
	# se uprostřed vozovky kreslila rozpadlá krajnice (a v zimě sněhový mnohoúhelník) prosvítající přes druhý pás
	var grid := {}
	for t in nt:
		var lo := Vector2(minf(p[t * 3].x, minf(p[t * 3 + 1].x, p[t * 3 + 2].x)), minf(p[t * 3].z, minf(p[t * 3 + 1].z, p[t * 3 + 2].z)))
		var hi := Vector2(maxf(p[t * 3].x, maxf(p[t * 3 + 1].x, p[t * 3 + 2].x)), maxf(p[t * 3].z, maxf(p[t * 3 + 1].z, p[t * 3 + 2].z)))
		for gx in range(floori(lo.x / 4.0), floori(hi.x / 4.0) + 1):
			for gz in range(floori(lo.y / 4.0), floori(hi.y / 4.0) + 1):
				var gk := Vector2i(gx, gz)
				if not grid.has(gk):
					grid[gk] = PackedInt32Array()
				grid[gk].append(t)
	for t in nt:
		for e in 3:
			var a := p[t * 3 + e]
			var b := p[t * 3 + (e + 1) % 3]
			var k := _ekey(a, b)
			if int(ecount[k]) != 1:
				continue
			var o := p[t * 3 + (e + 2) % 3]
			var d := Vector2(b.x - a.x, b.z - a.z).normalized()
			var nrm := Vector2(-d.y, d.x)
			var mid := Vector2((a.x + b.x) * 0.5, (a.z + b.z) * 0.5)
			if nrm.dot(Vector2(o.x, o.z) - mid) > 0.0:
				nrm = -nrm                          # ven z pásu (od protějšího vrcholu)
			var q := mid + nrm * 0.3
			for t2 in grid.get(Vector2i(floori(q.x / 4.0), floori(q.y / 4.0)), PackedInt32Array()):
				if t2 != t and Geometry2D.point_is_inside_triangle(q, Vector2(p[t2 * 3].x, p[t2 * 3].z),
						Vector2(p[t2 * 3 + 1].x, p[t2 * 3 + 1].z), Vector2(p[t2 * 3 + 2].x, p[t2 * 3 + 2].z)):
					ecount[k] = -1                  # zakrytý okraj
					break
	# vrcholy na skutečném (b) a zakrytém (c) okraji – roh ústí odbočky leží na obou a platí jako skutečný okraj
	var on_b := {}
	var on_c := {}
	for t in nt:
		for e in 3:
			var c := int(ecount[_ekey(p[t * 3 + e], p[t * 3 + (e + 1) % 3])])
			if c == 1 or c == -1:
				for j in [e, (e + 1) % 3]:
					var vk := Vector2i(roundi(p[t * 3 + j].x * 50.0), roundi(p[t * 3 + j].z * 50.0))
					if c == 1:
						on_b[vk] = true
					else:
						on_c[vk] = true
	var sw := PackedVector2Array()        # (s, W) na vrchol trojúhelníku
	sw.resize(n)
	var multi: Array[int] = []            # trojúhelníky s více okraji (konce pásů) – po mediánu šířky
	var widths := PackedFloat32Array()
	for t in nt:
		var bnd: Array[int] = []
		for e in 3:
			if int(ecount[_ekey(p[t * 3 + e], p[t * 3 + (e + 1) % 3])]) == 1:
				bnd.append(e)
		if bnd.size() == 1:
			# protější strana pásu zakrytá jiným pásem → vzdálenost od okraje lineárně přes celý pás (s + 2)
			var o := p[t * 3 + (bnd[0] + 2) % 3]
			var ok := Vector2i(roundi(o.x * 50.0), roundi(o.z * 50.0))
			widths.append(_set_side(p, sw, t, bnd[0], on_c.has(ok) and not on_b.has(ok)))
		elif bnd.is_empty():
			var cov := -1
			for e in 3:
				if int(ecount[_ekey(p[t * 3 + e], p[t * 3 + (e + 1) % 3])]) == -1:
					cov = e if cov == -1 else -2
			var o2 := p[t * 3 + (cov + 2) % 3] if cov >= 0 else Vector3.ZERO
			if cov >= 0 and on_b.has(Vector2i(roundi(o2.x * 50.0), roundi(o2.z * 50.0))):
				# zakrytý okraj, protější vrchol na skutečném okraji: lineárně od něj (zakrytá strana = šířka pásu)
				var i0 := t * 3 + cov
				var i1 := t * 3 + (cov + 1) % 3
				var wd := maxf(_line_dist(p[i0], p[i1], o2), 0.5)
				sw[i0] = Vector2(3.0, wd)
				sw[i1] = Vector2(3.0, wd)
				sw[t * 3 + (cov + 2) % 3] = Vector2(2.0, wd)
			else:
				for j in 3:
					sw[t * 3 + j] = Vector2(0.5, -1.0)      # vnitřek (křižovatka): W < 0 = bez okrajů a stop
		else:
			multi.append(t)
	var med := 3.0
	if not widths.is_empty():
		var ws := widths.duplicate()
		ws.sort()
		med = ws[ws.size() / 2]
	for t in multi:
		var best := 0
		var bd := INF
		for e in 3:
			var a := p[t * 3 + e]
			var b := p[t * 3 + (e + 1) % 3]
			if int(ecount[_ekey(a, b)]) != 1:
				continue
			var dd := absf(_line_dist(a, b, p[t * 3 + (e + 2) % 3]) - med)
			if dd < bd:
				bd = dd
				best = e
		_set_side(p, sw, t, best)
	# zdvih podle šířky – na vrchol (pozice), ať sousední trojúhelníky sedí přesně na sebe
	var lift := {}
	for i in n:
		var k := Vector2i(roundi(p[i].x * 50.0), roundi(p[i].z * 50.0))
		lift[k] = maxf(float(lift.get(k, 0.0)), clampf(sw[i].y, 1.0, 8.0) * DRAPE_W_LIFT)
	# --- adaptivní dělení nejdelší hrany (longest-edge bisection – vždy skončí). Zásobník po 7 položkách:
	# 3 × pozice (y = terén), 3 × (s, W, zdvih), příznaky „zmrazených“ hran (ab, bc, ca). Hrana, která dělení
	# nepotřebuje, ale je nejdelší, se rozpůlí v PŘÍMCE (bod leží na hraně souseda – žádná škvíra) a její
	# poloviny se už podle terénu nedělí.
	var tol := DRAPE_TOL
	var min2 := DRAPE_MIN_EDGE * DRAPE_MIN_EDGE
	var long2 := DRAPE_LONG * DRAPE_LONG
	var v := PackedVector3Array()
	var nn := PackedVector3Array()
	var cc := PackedColorArray()
	var uv := PackedVector2Array()
	var stack: Array[Vector3] = []
	for t in nt:
		for j in 3:
			var q := p[t * 3 + j]
			q.y = f.at(q.x, q.z)
			stack.append(q)
		for j in 3:
			var i := t * 3 + j
			var k := Vector2i(roundi(p[i].x * 50.0), roundi(p[i].z * 50.0))
			stack.append(Vector3(sw[i].x, sw[i].y, lift[k]))
		stack.append(Vector3.ZERO)
		var tc := Color(col[t * 9], col[t * 9 + 1], col[t * 9 + 2])
		var guard := 0
		while not stack.is_empty():
			var sz := stack.size()
			var a: Vector3 = stack[sz - 7]
			var b: Vector3 = stack[sz - 6]
			var c: Vector3 = stack[sz - 5]
			var ua: Vector3 = stack[sz - 4]
			var ub: Vector3 = stack[sz - 3]
			var uc: Vector3 = stack[sz - 2]
			var fz: Vector3 = stack[sz - 1]
			stack.resize(sz - 7)
			guard += 1
			var any := false
			var longest := 0
			var ll := -1.0
			var need_l := false
			var hm_l := 0.0
			for e in 3:
				var e0: Vector3 = a if e == 0 else (b if e == 1 else c)
				var e1: Vector3 = b if e == 0 else (c if e == 1 else a)
				var dx := e1.x - e0.x
				var dz := e1.z - e0.z
				var l2 := dx * dx + dz * dz
				var need := false
				var hm := 0.0
				if fz[e] < 0.5 and l2 > min2:
					hm = f.at((e0.x + e1.x) * 0.5, (e0.z + e1.z) * 0.5)
					need = l2 > long2 or absf(hm - (e0.y + e1.y) * 0.5) > tol
					if not need and l2 > 4.0 * min2:
						# delší hrana přes víc buněk mřížky: odchylka nemusí být největší uprostřed – i čtvrtiny
						# (symetricky – soused na stejné hraně rozhodne stejně)
						var q1 := e0 * 0.75 + e1 * 0.25
						var q3 := e0 * 0.25 + e1 * 0.75
						need = absf(f.at(q1.x, q1.z) - q1.y) > tol or absf(f.at(q3.x, q3.z) - q3.y) > tol
				any = any or need
				if l2 > ll:
					ll = l2
					longest = e
					need_l = need
					hm_l = hm
			if not any and ll > min2 and guard <= 4000:
				# hrany sedí, ale terén se může vyboulit uvnitř trojúhelníku (prorůstání asfaltem) – těžiště;
				# rozpůlí se nejdelší hrana (v přímce, když sama dělení nepotřebuje)
				var ct := (a + b + c) / 3.0
				any = absf(f.at(ct.x, ct.z) - ct.y) > tol
			if not any or guard > 4000:
				for j in 3:
					var q: Vector3 = a if j == 0 else (b if j == 1 else c)
					var u: Vector3 = ua if j == 0 else (ub if j == 1 else uc)
					v.append(Vector3(q.x, q.y + drape_h + u.z, q.z))
					nn.append(f.normal(q.x, q.z))
					cc.append(tc)
					uv.append(Vector2(u.x, u.y))
				continue
			var s0: Vector3 = a if longest == 0 else (b if longest == 1 else c)
			var s1: Vector3 = b if longest == 0 else (c if longest == 1 else a)
			var m := (s0 + s1) * 0.5
			if need_l:
				m.y = hm_l
			var sf := 0.0 if need_l else 1.0
			# rozpůlení nejdelší hrany (pořadí vrcholů zachovává orientaci); příznaky: poloviny dělené hrany sf,
			# nová vnitřní hrana 0, ostatní beze změny
			if longest == 0:
				var um := (ua + ub) * 0.5
				stack.append_array([a, m, c, ua, um, uc, Vector3(sf, 0.0, fz.z),
					m, b, c, um, ub, uc, Vector3(sf, fz.y, 0.0)])
			elif longest == 1:
				var um := (ub + uc) * 0.5
				stack.append_array([b, m, a, ub, um, ua, Vector3(sf, 0.0, fz.x),
					m, c, a, um, uc, ua, Vector3(sf, fz.z, 0.0)])
			else:
				var um := (uc + ua) * 0.5
				stack.append_array([c, m, b, uc, um, ub, Vector3(sf, 0.0, fz.y),
					m, a, b, um, ua, ub, Vector3(sf, fz.x, 0.0)])
	job["v"] = v
	job["n"] = nn
	job["c"] = cc
	job["uv"] = uv
	job.erase("pos")
	job.erase("nrm")
	job.erase("col")


## Okraj pásu = hrana `e` trojúhelníku `t`: její vrcholy s = 0, protější vrchol s = 1; W = jeho vzdálenost od okraje.
## `lin` – protější strana pásu není okraj (zakrytá jiným pásem): s = 2 na okraji, 3 u protějšího vrcholu
## (shader: vzdálenost od okraje lineárně (s − 2) · W místo „stanu“ min(s, 1 − s) · W).
static func _set_side(p: PackedVector3Array, sw: PackedVector2Array, t: int, e: int, lin := false) -> float:
	var i0 := t * 3 + e
	var i1 := t * 3 + (e + 1) % 3
	var i2 := t * 3 + (e + 2) % 3
	var wd := maxf(_line_dist(p[i0], p[i1], p[i2]), 0.5)
	var s0 := 2.0 if lin else 0.0
	sw[i0] = Vector2(s0, wd)
	sw[i1] = Vector2(s0, wd)
	sw[i2] = Vector2(s0 + 1.0, wd)
	return wd


## Přidá dlaždice do scény; volitelně s kolizí (ConcavePolygonShape3D). Mesh i těleso stojí ve středu
## dlaždice (`origin` z load_chunks) – dohled i jeho prolínání se tak měří od dlaždice, ne od spawnu.
## `shadows` = false: dlaždice nevrhá stín (silnice a cesty položené na terénu – stín by nebyl vidět, jen by se
## kreslily znovu ve stínovém průchodu; optimalizace GPU 17. 10. 2026).
static func add_chunks(parent: Node3D, name: String, chunks: Array, collide: bool, vis_range := 0.0,
		surface := "", shadows := true) -> void:
	var root := Node3D.new()
	root.name = name
	parent.add_child(root)
	for ch in chunks:
		var origin: Vector3 = ch.get("origin", Vector3.ZERO)
		var mi := MeshInstance3D.new()
		mi.mesh = ch["mesh"]
		mi.position = origin
		if not shadows:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if vis_range > 0.0:
			mi.visibility_range_end = vis_range
			mi.visibility_range_end_margin = minf(vis_range * 0.08, 60.0)   # jemné dofadování
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
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
			body.position = origin           # faces jsou lokální vůči středu dlaždice
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
	var bark := "res://textures/bark_brown_02_diff_2k.jpg"
	if tex_available(bark):                    # bez textury (čistý checkout) kůru kreslí shader procedurálně
		m.set_shader_parameter("bark_tex", load(bark))
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
static func build_trees(parent: Node3D, skip := {}, terrain: Terrain = null, mgr: TreeManager = null,
		treegen := false) -> Array:
	tree_gen = TreeGen.load_protos() if treegen else null   # M8.8: modely podle druhu (bez dat → prototypy níž)
	if tree_gen != null:
		shared_protos = []
		return tree_gen.build(parent, skip, terrain, mgr)
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
	var eco := TreeGen.read_eco(n)            # M8.11: druh stromu pro fenologický kód (bez dat z prototypu)
	var eco_rec: PackedByteArray = eco.get("rec", PackedByteArray())
	var eco_ids: Array = eco.get("ids", [])
	var site: Site = mgr.world.site if mgr != null and mgr.world != null else null
	for i in n:
		if skip.has(i):
			continue
		var k := i * 11
		var pos := Vector3(d[k], d[k + 1], d[k + 2])
		if terrain:
			pos.y = minf(pos.y, terrain.height_at(pos.x, pos.z) - 0.15)
		var basis := Basis(Vector3.UP, d[k + 3]) * Basis.from_scale(Vector3(d[k + 4], d[k + 5], d[k + 6]))
		var xf := Transform3D(basis, pos)
		var p := int(d[k + 10])
		var sp := String(TreeEco.FALLBACK_PROTO[clampi(p, 0, TreeEco.FALLBACK_PROTO.size() - 1)])
		if not eco_rec.is_empty():
			var si := eco_rec.decode_u8(i * TreeEco.REC)
			sp = String(eco_ids[si]) if si < eco_ids.size() else sp
		var col := Color(d[k + 7], d[k + 8], d[k + 9], Phenology.instance_alpha(sp, pos, site))   # M8.11: a = fenologický kód
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

	# kolize kmenů – jedno statické těleso na buňku 256 m. Tvary se přidávají rovnou do fyzikálního
	# serveru (body_add_shape), NE jako CollisionShape3D uzly: ~50 tisíc uzlů ve scéně jen za existenci
	# stálo měřitelné ms na frame. `shapes` drží [RID těla, index tvaru] pro vypnutí při pokácení;
	# `shape_rids` drží RIDy tvarů, aby je TreeManager uvolnil při zániku světa (nová hra).
	var bodies := {}
	var shapes: Array = []
	var shape_rids: Array[RID] = []
	for t in trunks:
		var pos: Vector3 = t[0]
		var key := Vector2i(floori(pos.x / TREE_FAR_CELL), floori(pos.z / TREE_FAR_CELL))
		if not bodies.has(key):
			var b := StaticBody3D.new()
			b.collision_layer = 1
			b.collision_mask = 0
			b.set_meta("surface", "strom")
			root.add_child(b)
			bodies[key] = [b, 0]
		var rec: Array = bodies[key]
		var b: StaticBody3D = rec[0]
		var sr := PhysicsServer3D.cylinder_shape_create()
		PhysicsServer3D.shape_set_data(sr, {"radius": maxf(t[1], 0.15), "height": t[2]})
		PhysicsServer3D.body_add_shape(b.get_rid(), sr,
			Transform3D(Basis.IDENTITY, pos + Vector3(0, t[2] * 0.5, 0)))
		shape_rids.append(sr)
		shapes.append([b.get_rid(), rec[1]])
		rec[1] += 1
	if mgr != null:
		mgr.set_index(d, meta, near_mm, far_mm, shapes, shape_rids)
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
