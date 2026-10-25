## Vizuální validátor – sdílené kontroly geometrie (galerie modelů i svět): transformace bez NaN / nekonečen,
## degenerované meshe (nulový počet vrcholů, nulový objem obálky), povrchy bez materiálu, ShaderMaterial
## s nenavázanými samplery (sampler2D bez hodnoty a bez výchozího hintu) a textury, které se nenačetly.
## Navíc obálky (AABB) uzlů ve světových i lokálních souřadnicích.
##
## Jen statické funkce. Nálezy mají tvar řádku `geometry.json`:
##   {"severity": "FAIL|WARN|INFO", "check": "…", "node": "cesta/uzlu", "msg": "…", "pos": [x, y, z]}
## Opakované nálezy na sdíleném meshi / materiálu se hlásí jednou (s počtem uzlů) – `ctx` drží mezipaměť.
extends RefCounted

const EPS_VOL := 1e-6            # m – pod tímto rozměrem je osa obálky „nulová“
const SAMPLER_TYPES := ["sampler2D", "sampler2DArray", "sampler3D", "samplerCube", "samplerCubeArray",
	"isampler2D", "usampler2D", "isampler3D", "usampler3D"]
## Hinty, se kterými má sampler výchozí texturu (nebo ho plní engine) → bez hodnoty je v pořádku.
const DEFAULT_HINTS := ["hint_default_", "hint_normal", "hint_roughness", "hint_anisotropy",
	"hint_screen_texture", "hint_depth_texture", "hint_normal_roughness_texture"]

static var _hint_cache := {}      # instance id shaderu → {jméno sampleru: true = má výchozí hint}
static var _sampler_seen := {}    # "shader|samplery" → počet materiálů s tímto nálezem (hlásí se jen první)


## Nový kontext kontrol (mezipaměť sdílených meshů a materiálů + počítadla).
static func new_ctx() -> Dictionary:
	return {"mesh_seen": {}, "mat_seen": {}, "mat_hits": {}, "nomat": {}, "checked_meshes": 0,
		"checked_materials": 0, "geometry_nodes": 0}


## Souhrn opakovaných nálezů samplerů: [[klíč, počet]] (počet > 1).
static func sampler_repeats() -> Array:
	var out := []
	for k in _sampler_seen:
		if int(_sampler_seen[k]) > 1:
			out.append([k, int(_sampler_seen[k])])
	return out


## Řádek nálezu pro JSON.
static func finding(sev: String, check: String, node: String, msg: String, pos := Vector3.INF) -> Dictionary:
	var d := {"severity": sev, "check": check, "node": node, "msg": msg}
	if vec_ok(pos):
		d["pos"] = [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), snappedf(pos.z, 0.01)]
	else:
		d["pos"] = null
	return d


static func vec_ok(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


static func xform_ok(t: Transform3D) -> bool:
	return vec_ok(t.origin) and vec_ok(t.basis.x) and vec_ok(t.basis.y) and vec_ok(t.basis.z)


## Cesta uzlu bez prefixu kořene (kratší, čitelná v JSON).
static func path_of(n: Node) -> String:
	if n == null:
		return ""
	if not n.is_inside_tree():
		return String(n.name)
	var p := String(n.get_path())
	return p.trim_prefix("/root/")


## Uzly, které se počítají do obálky / velikosti objektu (meshe; ne částice, popisky a pomocné obrysy).
static func is_solid(gi: Node) -> bool:
	return gi is MeshInstance3D or gi is MultiMeshInstance3D


## Obálka viditelné geometrie uzlu `n` (včetně potomků) v soustavě `frame` (výchozí = svět).
## Vrací {"aabb": AABB, "n": počet meshů}; n = 0 → prázdné.
static func aabb_of(n: Node, frame := Transform3D.IDENTITY, only_visible := true) -> Dictionary:
	var inv := frame.affine_inverse()
	var res := {"aabb": AABB(), "n": 0}
	_aabb_walk(n, inv, only_visible, res)
	return res


static func _aabb_walk(n: Node, inv: Transform3D, only_visible: bool, res: Dictionary) -> void:
	if n is Node3D and only_visible and not (n as Node3D).visible:
		return
	if is_solid(n):
		var gi := n as GeometryInstance3D
		var la := gi.get_aabb()
		if la.size.length() > 0.0 and xform_ok(gi.global_transform):
			var wa: AABB = (inv * gi.global_transform) * la
			if int(res["n"]) == 0:
				res["aabb"] = wa
			else:
				res["aabb"] = (res["aabb"] as AABB).merge(wa)
			res["n"] = int(res["n"]) + 1
	for c in n.get_children():
		_aabb_walk(c, inv, only_visible, res)


## Všechny GeometryInstance3D pod `n` (i neviditelné; filtr dělá volající).
static func geometry_under(n: Node, out: Array) -> void:
	if n is GeometryInstance3D:
		out.append(n)
	for c in n.get_children():
		geometry_under(c, out)


## Kontrola jedné GeometryInstance3D: transformace, mesh, materiály, shadery. Nálezy do `out`.
static func check_geometry(gi: GeometryInstance3D, out: Array, ctx: Dictionary, label := "") -> void:
	ctx["geometry_nodes"] = int(ctx["geometry_nodes"]) + 1
	var name_ := label if label != "" else path_of(gi)
	var xf := gi.global_transform if gi.is_inside_tree() else gi.transform
	if not xform_ok(xf):
		out.append(finding("FAIL", "nan_transform", name_, "transformace obsahuje NaN / nekonečno"))
		return
	var pos := xf.origin
	if gi is MeshInstance3D:
		var mi := gi as MeshInstance3D
		if mi.mesh == null:
			out.append(finding("WARN", "mesh_missing", name_, "MeshInstance3D bez meshe", pos))
			return
		_check_mesh(mi.mesh, name_, pos, out, ctx)
		for s in mi.mesh.get_surface_count():
			var m := mi.get_active_material(s)
			_check_material_slot(m, mi.mesh, s, name_, pos, out, ctx)
	elif gi is MultiMeshInstance3D:
		var mmi := gi as MultiMeshInstance3D
		var mm := mmi.multimesh
		if mm == null or mm.mesh == null:
			out.append(finding("WARN", "mesh_missing", name_, "MultiMeshInstance3D bez multimeshe / meshe", pos))
			return
		_check_mesh(mm.mesh, name_, pos, out, ctx)
		for s in mm.mesh.get_surface_count():
			var m: Material = mmi.material_override if mmi.material_override else mm.mesh.surface_get_material(s)
			_check_material_slot(m, mm.mesh, s, name_, pos, out, ctx)
		# vzorek instancí: NaN v transformacích
		var n := mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
		var step := maxi(1, n / 64)
		for i in range(0, n, step):
			if not xform_ok(mm.get_instance_transform(i)):
				out.append(finding("FAIL", "nan_transform", name_, "instance %d multimeshe má NaN / nekonečno" % i, pos))
				break
	elif gi.material_override:
		_check_material(gi.material_override, name_, pos, out, ctx)


static func _check_mesh(mesh: Mesh, name_: String, pos: Vector3, out: Array, ctx: Dictionary) -> void:
	var id := mesh.get_instance_id()
	if (ctx["mesh_seen"] as Dictionary).has(id):
		return
	ctx["mesh_seen"][id] = true
	ctx["checked_meshes"] = int(ctx["checked_meshes"]) + 1
	if mesh.get_surface_count() == 0:
		out.append(finding("WARN", "mesh_empty", name_, "mesh nemá žádný povrch (%s)" % mesh.get_class(), pos))
		return
	if mesh is ArrayMesh:
		var am := mesh as ArrayMesh
		for s in am.get_surface_count():
			if am.surface_get_array_len(s) == 0:
				out.append(finding("FAIL", "mesh_degenerate", name_, "povrch %d má 0 vrcholů" % s, pos))
	var a := mesh.get_aabb()
	if not (vec_ok(a.position) and vec_ok(a.size)):
		out.append(finding("FAIL", "mesh_nan", name_, "obálka meshe obsahuje NaN (vrcholy?)", pos))
		return
	var zero := 0
	for k in 3:
		if absf(a.size[k]) < EPS_VOL:
			zero += 1
	if zero >= 2:
		out.append(finding("FAIL" if zero == 3 else "WARN", "mesh_degenerate", name_,
			"obálka meshe je %s (%.3f × %.3f × %.3f m)" % ["bod" if zero == 3 else "úsečka", a.size.x, a.size.y, a.size.z], pos))


static func _check_material_slot(m: Material, mesh: Mesh, s: int, name_: String, pos: Vector3, out: Array,
		ctx: Dictionary) -> void:
	if m == null:
		var key := "%d:%d" % [mesh.get_instance_id(), s]
		if (ctx["nomat"] as Dictionary).has(key):
			ctx["nomat"][key]["n"] += 1
			return
		var f := finding("WARN", "material_missing", name_, "povrch %d nemá materiál (kreslí se výchozí šedou)" % s, pos)
		ctx["nomat"][key] = {"n": 1, "f": f}
		out.append(f)
		return
	_check_material(m, name_, pos, out, ctx)


## Materiál (a jeho next_pass): ShaderMaterial – shader a samplery, BaseMaterial3D – zapnuté mapy bez textury.
static func _check_material(m: Material, name_: String, pos: Vector3, out: Array, ctx: Dictionary) -> void:
	var guard := 0
	while m != null and guard < 4:
		guard += 1
		var id := m.get_instance_id()
		if (ctx["mat_seen"] as Dictionary).has(id):
			ctx["mat_hits"][id] = int(ctx["mat_hits"].get(id, 1)) + 1
			m = m.next_pass
			continue
		ctx["mat_seen"][id] = true
		ctx["checked_materials"] = int(ctx["checked_materials"]) + 1
		if m is ShaderMaterial:
			_check_shader_material(m as ShaderMaterial, name_, pos, out)
		elif m is BaseMaterial3D:
			_check_base_material(m as BaseMaterial3D, name_, pos, out)
		m = m.next_pass


static func _check_shader_material(sm: ShaderMaterial, name_: String, pos: Vector3, out: Array) -> void:
	var sh := sm.shader
	if sh == null:
		out.append(finding("FAIL", "shader_missing", name_, "ShaderMaterial bez shaderu", pos))
		return
	var hints := _sampler_hints(sh)
	var sh_name := sh.resource_path.get_file() if sh.resource_path != "" else "vložený shader"
	var unbound := []
	for u in sh.get_shader_uniform_list():
		var uname: String = u.get("name", "")
		if not hints.has(uname):
			continue                  # není sampler
		var v = sm.get_shader_parameter(uname)
		if v == null:
			if not bool(hints[uname]):
				unbound.append(uname)
		elif v is Texture2D:
			var t := v as Texture2D
			if t.get_width() <= 0 or t.get_height() <= 0:
				out.append(finding("FAIL", "texture_empty", name_, "%s: textura `%s` má nulovou velikost (nenačetla se?) %s" % [
					sh_name, uname, t.resource_path], pos))
	if not unbound.is_empty():
		# stejný shader se stejnými prázdnými samplery (instance materiálu na každý MultiMesh) → jen jednou
		var key := "%s|%s" % [sh_name, ",".join(unbound)]
		if _sampler_seen.has(key):
			_sampler_seen[key] += 1
			return
		_sampler_seen[key] = 1
		out.append(finding("WARN", "shader_sampler_unbound", name_,
			"%s: sampler bez hodnoty a bez výchozího hintu: %s (kreslí se výchozí bílá – nenačtená textura?)" % [
				sh_name, ", ".join(unbound)], pos))


## Jméno sampleru → má výchozí hint (`hint_default_*`, `hint_normal`, obrazovkové textury…).
static func _sampler_hints(sh: Shader) -> Dictionary:
	var id := sh.get_instance_id()
	if _hint_cache.has(id):
		return _hint_cache[id]
	var code := _expand_includes(sh.code, 0)
	var re := RegEx.new()
	re.compile("uniform\\s+(?:lowp\\s+|mediump\\s+|highp\\s+)?(\\w+)\\s+(\\w+)\\s*(?::\\s*([^;=]*))?")
	var res := {}
	for m in re.search_all(code):
		if not (m.get_string(1) in SAMPLER_TYPES):
			continue
		var h := m.get_string(3)
		var has_def := false
		for k in DEFAULT_HINTS:
			if h.find(k) >= 0:
				has_def = true
		res[m.get_string(2)] = has_def
	_hint_cache[id] = res
	return res


static func _expand_includes(code: String, depth: int) -> String:
	if depth > 3 or code.find("#include") < 0:
		return code
	var re := RegEx.new()
	re.compile("#include\\s+\"([^\"]+)\"")
	var extra := ""
	for m in re.search_all(code):
		var p := m.get_string(1)
		if FileAccess.file_exists(p):
			extra += "\n" + _expand_includes(FileAccess.get_file_as_string(p), depth + 1)
	return code + extra


static func _check_base_material(bm: BaseMaterial3D, name_: String, pos: Vector3, out: Array) -> void:
	# zapnutá funkce materiálu bez textury = textura se nenačetla (load() vrátil null)
	var pairs := [
		[bm.normal_enabled, BaseMaterial3D.TEXTURE_NORMAL, "normal"],
		[bm.heightmap_enabled, BaseMaterial3D.TEXTURE_HEIGHTMAP, "heightmap"],
		[bm.ao_enabled, BaseMaterial3D.TEXTURE_AMBIENT_OCCLUSION, "ao"],
		[bm.detail_enabled, BaseMaterial3D.TEXTURE_DETAIL_ALBEDO, "detail_albedo"],
	]
	for p in pairs:
		if bool(p[0]) and bm.get_texture(p[1]) == null:
			out.append(finding("WARN", "texture_null", name_, "StandardMaterial3D: zapnutá mapa `%s` bez textury (nenačetla se?)" % p[2], pos))
	for t_id in [BaseMaterial3D.TEXTURE_ALBEDO, BaseMaterial3D.TEXTURE_NORMAL, BaseMaterial3D.TEXTURE_ROUGHNESS]:
		var t := bm.get_texture(t_id)
		if t != null and (t.get_width() <= 0 or t.get_height() <= 0):
			out.append(finding("FAIL", "texture_empty", name_, "StandardMaterial3D: textura %d má nulovou velikost %s" % [t_id, t.resource_path], pos))


## Úhel (°) mezi osou Y báze a svislicí.
static func tilt_deg(b: Basis) -> float:
	var up := b.y.normalized()
	return rad_to_deg(acos(clampf(up.dot(Vector3.UP), -1.0, 1.0)))


## Rozměry obálky jako pole zaokrouhlené na cm.
static func size_arr(a: AABB) -> Array:
	return [snappedf(a.size.x, 0.01), snappedf(a.size.y, 0.01), snappedf(a.size.z, 0.01)]
