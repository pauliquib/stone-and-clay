## Vizuální validátor – galerie procedurálních modelů (bez světa): postavy (`Humanoid`), auta a traktor
## (`CarModel`), jednostopá vozidla (`BikeModel`), zvířata (`QuadrupedModel` + `AnimalSpecs`), dron
## (`DroneModel`), pouliční vybavení (`PropModels`) a ploty (`FenceManager`).
##
## Každý model stojí sám na neutrální šedé zemi s mřížkou 1 m, vedle něj 1m kostka (u malých modelů 1m
## červenobílá lať); osvětlení = jedno DirectionalLight3D + WorldEnvironment s procedurální oblohou.
## Čtyři SubViewporty (každý VIEW × VIEW px) sdílejí svět kořene a koukají na model ze 4 úhlů po 90°
## (35°, 125°, 215°, 305° od přední strany +Z, 22° shora) → složí se do jednoho PNG 2 × 2 se jménem a rozměry.
##
## Výstup: `<out>/gallery/<id>.png` + `<out>/gallery.json`
##   {"models": [{id, name, category, png, aabb_size [x, y, z], aabb_min, meshes, findings: [...]}], "stats": {...}}
## Nálezy: kontroly `geom_checks.gd` (NaN, degenerovaný mesh, bez materiálu, samplery) + velikost podle kategorie
## a „spodek modelu na zemi“ (počátek modelu = země).
extends RefCounted

const GeomChecks := preload("res://tools/vizual/geom_checks.gd")

const VIEW := 240                       # px – jeden pohled (PNG modelu = 2 × VIEW)
const ANGLES := [35.0, 125.0, 215.0, 305.0]
const ELEV := 22.0                      # ° – kamera nad vodorovnou
const FOV := 40.0
const GROUND_TOL := 0.06                # m – spodek modelu smí být nejvýš tolik nad / pod zemí (počátek = země)

## Očekávané rozměry podle kategorie: osa obálky (lokální, model kouká do +Z) a rozsah v m.
const SIZE_RULES := {
	"postava": {"axis": 1, "min": 1.5, "max": 2.0, "what": "výška"},
	"auto": {"axis": 2, "min": 3.5, "max": 5.0, "what": "délka"},
	"dodavka": {"axis": 2, "min": 4.0, "max": 6.0, "what": "délka"},
	"traktor": {"axis": 2, "min": 2.2, "max": 4.0, "what": "délka"},
	"jednostopa": {"axis": 2, "min": 1.5, "max": 2.4, "what": "délka"},
	"zvire": {"axis": 2, "min": 0.3, "max": 3.8, "what": "délka"},
	"dron": {"axis": 0, "min": 0.15, "max": 1.0, "what": "šířka"},
}

var tree: SceneTree
var out_dir := ""
var stage: Node3D
var model_root: Node3D
var vps: Array[SubViewport] = []
var cams: Array[Camera3D] = []
var title: Label
var header: SubViewport
var cube: MeshInstance3D
var bar: MeshInstance3D
var rigs: Array = []                   # QuadrupedRig – animace v klidu (krok 0)


## Postaví scénu, vykreslí modely a uloží PNG + gallery.json. Vrací slovník gallery.json.
func run(t: SceneTree, out: String, quick: bool) -> Dictionary:
	tree = t
	out_dir = out
	DirAccess.make_dir_recursive_absolute(out_dir.path_join("gallery"))
	_build_stage()
	var defs := _defs(quick)
	var models := []
	var counts := {"FAIL": 0, "WARN": 0, "INFO": 0}
	for d in defs:
		var e := await _shoot(d)
		models.append(e)
		for f in e["findings"]:
			counts[f["severity"]] = int(counts.get(f["severity"], 0)) + 1
		print("VIZUAL galerie: %s  %s  nálezů %d" % [d["id"], str(e["aabb_size"]), (e["findings"] as Array).size()])
	var res := {"models": models, "stats": {"models": models.size(), "view_px": VIEW, "findings": counts}}
	var f := FileAccess.open(out_dir.path_join("gallery.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(res, "  "))
	f.close()
	stage.queue_free()
	for vp in vps:
		vp.queue_free()
	header.queue_free()
	tree.process_frame.disconnect(_animate)
	await tree.process_frame
	return res


# ------------------------------------------------------------------ scéna

func _build_stage() -> void:
	stage = Node3D.new()
	stage.name = "VizualGalerie"
	tree.root.add_child(stage)
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.38, 0.52, 0.72)
	sm.sky_horizon_color = Color(0.72, 0.76, 0.8)
	sm.ground_bottom_color = Color(0.3, 0.3, 0.3)
	sm.ground_horizon_color = Color(0.6, 0.62, 0.64)
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	stage.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	stage.add_child(sun)
	# neutrální šedá zem s mřížkou 1 m
	var ground := MeshInstance3D.new()
	ground.name = "Zem"
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_texture = _grid_texture()
	gm.uv1_scale = Vector3(60, 60, 1)
	gm.roughness = 0.95
	gm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	ground.material_override = gm
	ground.position.y = -0.002
	stage.add_child(ground)
	# měřítko: 1m kostka (šachovnice 0,5 m) a 1m lať (10 cm dílky)
	cube = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	cube.mesh = bm
	var cm := StandardMaterial3D.new()
	cm.albedo_texture = _checker_texture(2, Color(0.92, 0.92, 0.9), Color(0.25, 0.27, 0.3))
	cm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cm.albedo_color = Color(1, 1, 1, 0.35)
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	cube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cube.material_override = cm
	stage.add_child(cube)
	bar = MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(1.0, 0.02, 0.02)
	bar.mesh = bb
	var brm := StandardMaterial3D.new()
	brm.albedo_texture = _checker_texture(10, Color(0.85, 0.1, 0.08), Color(0.95, 0.95, 0.95))
	brm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	brm.uv1_scale = Vector3(1, 1, 1)
	bar.material_override = brm
	stage.add_child(bar)
	model_root = Node3D.new()
	model_root.name = "Model"
	stage.add_child(model_root)
	for i in 4:
		var vp := SubViewport.new()
		vp.size = Vector2i(VIEW, VIEW)
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.msaa_3d = Viewport.MSAA_2X
		vp.transparent_bg = false
		tree.root.add_child(vp)
		var cam := Camera3D.new()
		cam.fov = FOV
		cam.near = 0.02
		cam.far = 300.0
		vp.add_child(cam)
		cam.current = true
		vps.append(vp)
		cams.append(cam)
		var l := Label.new()
		l.text = "%d°" % int(ANGLES[i])
		l.position = Vector2(VIEW - 44, VIEW - 22)
		l.add_theme_font_size_override("font_size", 13)
		l.add_theme_color_override("font_color", Color(1, 1, 1))
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		l.add_theme_constant_override("outline_size", 4)
		vp.add_child(l)
	# záhlaví (jméno, rozměry) přes celou šířku složeného PNG – vlastní 2D SubViewport, prolne se nahoru
	header = SubViewport.new()
	header.size = Vector2i(VIEW * 2, 38)
	header.disable_3d = true
	header.transparent_bg = true
	header.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	tree.root.add_child(header)
	title = Label.new()
	title.position = Vector2(6, 2)
	title.size = Vector2(VIEW * 2 - 12, 36)
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(1, 1, 1))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	title.add_theme_constant_override("outline_size", 4)
	header.add_child(title)
	tree.process_frame.connect(_animate)


func _animate() -> void:
	for r in rigs:
		if is_instance_valid(r):
			(r as QuadrupedRig).speed = 0.0
			(r as QuadrupedRig).animate(1.0 / 30.0)


func _grid_texture() -> ImageTexture:
	var n := 128
	var img := Image.create(n, n, true, Image.FORMAT_RGB8)
	img.fill(Color(0.47, 0.47, 0.46))
	for i in n:
		for w in 2:
			img.set_pixel(i, w, Color(0.3, 0.3, 0.3))
			img.set_pixel(w, i, Color(0.3, 0.3, 0.3))
	# jemné dělení po 0,5 m
	for i in n:
		img.set_pixel(i, n / 2, Color(0.42, 0.42, 0.41))
		img.set_pixel(n / 2, i, Color(0.42, 0.42, 0.41))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _checker_texture(cells: int, a: Color, b: Color) -> ImageTexture:
	var n := cells * 8
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			img.set_pixel(x, y, a if ((x / 8) + (y / 8)) % 2 == 0 else b)
	return ImageTexture.create_from_image(img)


# ------------------------------------------------------------------ seznam modelů

func _defs(quick: bool) -> Array:
	var d := []
	d.append({"id": "postava_muz", "name": "Postava – muž (Humanoid)", "cat": "postava", "kind": "human",
		"arg": {"moustache": true}})
	d.append({"id": "postava_zena", "name": "Postava – žena (Humanoid)", "cat": "postava", "kind": "human",
		"arg": {"female": true, "hair_style": 2, "shirt": Color(0.8, 0.4, 0.5)}})
	d.append({"id": "postava_policista", "name": "Postava – policista (outfit police)", "cat": "postava", "kind": "human",
		"arg": {"outfit": "police", "shirt": Color(0.12, 0.15, 0.3)}})
	var cars := [["octavia", Color(0.7, 0.08, 0.06), "auto"], ["fabia", Color(0.15, 0.3, 0.6), "auto"],
		["sedan120", Color(0.85, 0.8, 0.6), "auto"], ["van", Color(0.9, 0.9, 0.9), "dodavka"],
		["bednar", Color(0.3, 0.45, 0.3), "dodavka"], ["lesak", Color(0.35, 0.4, 0.25), "auto"],
		["rodinka", Color(0.55, 0.6, 0.65), "auto"], ["traktorek", Color(0.8, 0.25, 0.1), "traktor"],
		["kolo", Color(0.2, 0.35, 0.6), "jednostopa"], ["jawa", Color(0.6, 0.05, 0.05), "jednostopa"],
		["pionyrek", Color(0.1, 0.4, 0.7), "jednostopa"], ["vcelka", Color(0.9, 0.75, 0.1), "jednostopa"],
		["armadka", Color(0.3, 0.35, 0.22), "jednostopa"], ["krosak", Color(0.95, 0.45, 0.05), "jednostopa"]]
	for c in cars:
		var id: String = c[0]
		if not CarModel.MODELS.has(id):
			continue
		d.append({"id": "vozidlo_" + id, "name": "%s (%s)" % [CarModel.MODELS[id].get("name", id), id], "cat": c[2],
			"kind": "vehicle", "arg": {"model": id, "color": c[1]}})
	for a in [["srnec", {"male": true}], ["divocak", {"male": false}], ["kun", {}], ["krava", {}], ["ovce", {}]]:
		var sid: String = a[0]
		if not AnimalSpecs.SPECIES.has(sid):
			continue
		d.append({"id": "zvire_" + sid, "name": "%s (AnimalSpecs.%s)" % [AnimalSpecs.get_spec(sid).get("name", sid), sid],
			"cat": "zvire", "kind": "animal", "arg": {"species": sid, "variant": a[1]}})
	d.append({"id": "dron", "name": "Dron (DroneModel.dron)", "cat": "dron", "kind": "drone", "arg": {"model": "dron"}})
	d.append({"id": "vybaveni_ulic", "name": "Lampa, lavička, popelnice, schránka, značka (PropModels)", "cat": "",
		"kind": "street", "arg": {}})
	d.append({"id": "ploty", "name": "Ploty: drát, latě, kůly, kámen, živý plot (FenceManager)", "cat": "",
		"kind": "fences", "arg": {}})
	if quick:
		var keep := ["postava_muz", "vozidlo_octavia", "vozidlo_kolo", "zvire_srnec", "vybaveni_ulic"]
		d = d.filter(func(e): return e["id"] in keep)
	return d


## Postaví model podle položky seznamu `_defs`.
func _build(d: Dictionary) -> Node3D:
	var arg: Dictionary = d["arg"]
	match String(d["kind"]):
		"human":
			var h := Humanoid.new()
			for k in arg:
				h.set(k, arg[k])
			return h
		"vehicle":
			return _vehicle(arg["model"], arg["color"])
		"animal":
			var rig := QuadrupedModel.build(AnimalSpecs.get_spec(arg["species"]), arg["variant"])
			rigs.append(rig)
			return rig
		"drone":
			return _drone(arg["model"])
		"street":
			return _street_props()
		"fences":
			return _fences()
	return Node3D.new()


## Vozidlo jako v `Car._ready` (karoserie, kola na `wheel_positions` ve výšce poloměru, vidlice, kliky), bez fyziky.
func _vehicle(id: String, col: Color) -> Node3D:
	var root := Node3D.new()
	var m := CarModel.new(id, col, false, "1A2 3456")
	var mesh := m.build()
	var bmi := MeshInstance3D.new()
	bmi.name = "Karoserie"
	bmi.mesh = mesh
	root.add_child(bmi)
	if m.scene_root:
		root.add_child(m.scene_root)
	var spec := m.spec
	var wr: float = spec["wheel_r"]
	var two := m.kind != "car"
	var done := {}
	for p: Vector3 in m.wheel_positions():
		var wp := Vector3(0.0 if two else p.x, wr, p.z)
		var key := "%.2f,%.2f" % [wp.x, wp.z]
		if done.has(key):
			continue
		done[key] = true
		var wm := MeshInstance3D.new()
		wm.name = "Kolo"
		if two:
			wm.mesh = BikeModel.wheel_mesh(wr, float(spec.get("tire_w", 0.045 if m.kind == "bike" else 0.1)), m.kind == "moto")
		else:
			wm.mesh = CarModel.wheel_mesh(wr, 1.0 if p.x > 0.0 else -1.0)
		if spec.has("wheel_scene"):
			wm.mesh = CarModel.first_mesh(spec["wheel_scene"])
		wm.position = wp
		root.add_child(wm)
	if m.fork_mesh:
		var f := MeshInstance3D.new()
		f.name = "Vidlice"
		f.mesh = m.fork_mesh
		f.position = m.fork_pivot
		root.add_child(f)
	if m.crank_mesh:
		var c := MeshInstance3D.new()
		c.name = "Kliky"
		c.mesh = m.crank_mesh
		c.position = m.crank_pivot
		root.add_child(c)
	return root


func _drone(id: String) -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	body.name = "Trup"
	body.mesh = DroneModel.body_mesh(id)
	root.add_child(body)
	for o: Vector3 in DroneModel.rotor_offsets(id):
		var r := MeshInstance3D.new()
		r.name = "Rotor"
		r.mesh = DroneModel.rotor_mesh(id)
		r.position = o
		root.add_child(r)
	# dron stojí na podvozku: spodek obálky posunout na zem
	var a := _local_aabb(root)
	root.position.y = -a.position.y
	var wrap := Node3D.new()
	wrap.add_child(root)
	return wrap


func _street_props() -> Node3D:
	var root := Node3D.new()
	var items := [
		["Lampa", PropModels.street_lamp(), Vector3(-2.4, 0, 0), 0.0],
		["Lavicka", PropModels.bench(), Vector3(-0.6, 0, 0.3), 0.0],
		["Popelnice", PropModels.trash_bin(Color(0.2, 0.35, 0.2)), Vector3(0.9, 0, 0.3), 0.0],
		["Schranka", PropModels.mailbox(), Vector3(1.9, 0, 0.3), 0.0],
	]
	for it in items:
		var mi := MeshInstance3D.new()
		mi.name = it[0]
		mi.mesh = it[1]
		mi.position = it[2]
		mi.rotation.y = it[3]
		root.add_child(mi)
	var sign := PropModels.road_sign("STOP", Color(0.8, 0.05, 0.05), Color.WHITE, "octagon")
	sign.name = "Znacka"
	sign.position = Vector3(3.0, 0, 0.3)
	root.add_child(sign)
	return root


func _fences() -> Node3D:
	var fm := FenceManager.new()
	fm.name = "Ploty"
	# FenceManager bez světa: výška terénu = 0
	for ty in 5:
		var z := -2.0 + ty * 1.0
		fm.build_line(PackedVector3Array([Vector3(-3.0, 0, z), Vector3(0.0, 0, z), Vector3(3.0, 0, z)]), ty, [], false)
	return fm


## Obálka přímých potomků (MeshInstance3D) uzlu mimo strom scény – v jeho lokálních souřadnicích.
static func _local_aabb(n: Node3D) -> AABB:
	var a := AABB()
	var first := true
	for c in n.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh:
			var wa: AABB = (c as MeshInstance3D).transform * (c as MeshInstance3D).mesh.get_aabb()
			a = wa if first else a.merge(wa)
			first = false
	return a


# ------------------------------------------------------------------ snímek jednoho modelu

func _shoot(d: Dictionary) -> Dictionary:
	for c in model_root.get_children():
		model_root.remove_child(c)
		c.queue_free()
	rigs.clear()
	var node: Node3D = _build(d)
	model_root.add_child(node)
	# postavy a rigy se staví v _ready; pár snímků na ustálení (animace v klidu)
	for i in 3:
		await tree.process_frame
	var findings := []
	var ctx := GeomChecks.new_ctx()
	var gis := []
	GeomChecks.geometry_under(node, gis)
	for gi in gis:
		if (gi as GeometryInstance3D).is_visible_in_tree():
			GeomChecks.check_geometry(gi, findings, ctx, "%s/%s" % [d["id"], String(node.get_path_to(gi))])
	var r: Dictionary = GeomChecks.aabb_of(node)
	var a: AABB = r["aabb"]
	if int(r["n"]) == 0:
		findings.append(GeomChecks.finding("FAIL", "model_empty", d["id"], "model nemá žádnou viditelnou geometrii"))
		a = AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE)
	elif not (GeomChecks.vec_ok(a.position) and GeomChecks.vec_ok(a.size)):
		findings.append(GeomChecks.finding("FAIL", "nan_aabb", d["id"], "obálka modelu obsahuje NaN"))
		a = AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE)
	else:
		_size_checks(d, a, findings)
	# kamera a měřítko
	var big := maxf(a.size.x, maxf(a.size.y, a.size.z)) > 0.8
	cube.visible = big
	bar.visible = true
	var c := a.get_center()
	if big:
		cube.position = Vector3(a.end.x + 1.2, 0.5, c.z)
		bar.position = Vector3(c.x, 0.012, a.end.z + 0.5)
	else:
		bar.position = Vector3(c.x, 0.012, a.end.z + 0.25)
	var frame := a.merge(AABB(bar.position - Vector3(0.5, 0.01, 0.01), Vector3(1.0, 0.02, 0.02)))
	if big:
		frame = frame.merge(AABB(cube.position - Vector3(0.5, 0.5, 0.5), Vector3.ONE))
	var fc := frame.get_center()
	var rad := maxf(frame.size.length() * 0.5, 0.35)
	var dist := rad / tan(deg_to_rad(FOV * 0.5)) * 1.05
	for i in 4:
		var az := deg_to_rad(float(ANGLES[i]))
		var el := deg_to_rad(ELEV)
		var dir := Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el))
		cams[i].look_at_from_position(fc + dir * dist, fc, Vector3.UP)
	title.text = "%s\n%.2f × %.2f × %.2f m (š×v×d) · mřížka 1 m · %s" % [d["name"], a.size.x, a.size.y, a.size.z,
		"kostka 1 m" if big else "lať 1 m"]
	# lavapipe: pár snímků, ať se obraz (stíny, mipmapy) ustálí
	for i in 4:
		await tree.process_frame
	await RenderingServer.frame_post_draw
	var img := Image.create(VIEW * 2, VIEW * 2, false, Image.FORMAT_RGBA8)
	for i in 4:
		var part := vps[i].get_texture().get_image()
		if part == null:
			continue
		part.convert(Image.FORMAT_RGBA8)
		img.blit_rect(part, Rect2i(Vector2i.ZERO, Vector2i(VIEW, VIEW)), Vector2i((i % 2) * VIEW, (i / 2) * VIEW))
	var hd := header.get_texture().get_image()
	if hd != null:
		hd.convert(Image.FORMAT_RGBA8)
		img.blend_rect(hd, Rect2i(Vector2i.ZERO, hd.get_size()), Vector2i.ZERO)
	var png := "gallery/%s.png" % d["id"]
	img.save_png(out_dir.path_join(png))
	return {"id": d["id"], "name": d["name"], "category": d["cat"], "png": png, "aabb_size": GeomChecks.size_arr(a),
		"aabb_min": [snappedf(a.position.x, 0.01), snappedf(a.position.y, 0.01), snappedf(a.position.z, 0.01)],
		"meshes": int(r["n"]), "findings": findings}


func _size_checks(d: Dictionary, a: AABB, out: Array) -> void:
	var cat: String = d["cat"]
	if absf(a.position.y) > GROUND_TOL and cat != "":
		out.append(GeomChecks.finding("WARN", "model_ground", d["id"],
			"spodek modelu je %.2f m %s počátku (počátek = země) – ve světě bude %s" % [absf(a.position.y),
				"nad" if a.position.y > 0 else "pod", "vznášet" if a.position.y > 0 else "zabořený"]))
	if SIZE_RULES.has(cat):
		var rule: Dictionary = SIZE_RULES[cat]
		var v: float = a.size[int(rule["axis"])]
		if v < float(rule["min"]) or v > float(rule["max"]):
			out.append(GeomChecks.finding("WARN", "model_size", d["id"], "%s %.2f m mimo očekávaný rozsah %.1f–%.1f m (%s)" % [
				rule["what"], v, rule["min"], rule["max"], cat]))
