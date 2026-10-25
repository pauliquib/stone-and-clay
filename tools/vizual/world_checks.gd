## Vizuální validátor – geometrická vrstva nad postaveným světem (`--only=geom`).
##
## V poloměru `radius` kolem středu (spawn z map.json) projde:
## - všechny viditelné GeometryInstance3D (MeshInstance3D, MultiMeshInstance3D) – `geom_checks.gd`: NaN, degenerované
##   meshe, povrchy bez materiálu, nenavázané samplery shaderů, nenačtené textury;
## - objekty po kategoriích (postavy = každý `Humanoid` mimo auto / koně, auta a jednostopá vozidla = `Car`,
##   zvířata = `Animal` / `Horse` / `Dog` / `FarmAnimal`, předměty = `Item`, fyzikální věci = `Prop` a RigidBody3D
##   přímo pod `World`): spodek obálky vs. `Terrain.height_at` pod půdorysem (vznáší se / zabořený), velikost
##   podle kategorie, svislost (osa Y vs. svislice, u aut vůči sklonu terénu), střed v půdorysu domu
##   (`data/buildings.json`);
## - stromy (instance MultiMeshů pod uzlem „Stromy“): pata kmene vs. terén, kmen v domě, kmen na silnici;
## - vegetaci (`World.vegetation`, vzorek instancí): vs. terén, v domě;
## - pouliční lampy (`StreetLights` „Sloupy“): pata vs. terén, svislost, výška, v domě;
## - ploty (`FenceManager.runs()`): body vs. terén, úsek přes dům;
## - fasády (`BuildingDetails`, uzel „Fasady“): okna (skla) a dveře v rovině zdi (< 0,15 m od hrany půdorysu),
##   mezi zemí a okapem, rozměry oken 0,6–2 m a dveří ~2 m;
## - z-fighting: silnice / cesty vs. terén (< 2 cm i uprostřed trojúhelníků), štěrkové cesty přes asfalt
##   (koplanární dlaždice), duplicitní instance (stejný mesh, stejná transformace), koplanární ploché meshe.
##
## Výsledek: {"findings": [...], "stats": {...}} – zapisuje ho `validator.gd` do geometry.json.
extends RefCounted

const GeomChecks := preload("res://tools/vizual/geom_checks.gd")

const MAX_PER_CHECK := 40           # podrobných nálezů na jeden druh kontroly; zbytek jen souhrnem
const GRID := 32.0                  # m – buňka mřížky budov a silnic
const MM_SAMPLE := 3000             # max. vzorkovaných instancí na MultiMesh (vegetace)
## Poloviční šířky vozovek (m) – kmen stromu blíž ose = strom na silnici.
const ROAD_HALF := {"secondary": 3.0, "tertiary": 2.75, "unclassified": 2.25, "residential": 2.25,
	"living_street": 2.25, "service": 1.5}
## Tolerance podle kategorie: float = spodek nad terénem (m), bury = spodek pod terénem (m), tilt = ° od svislice,
## size = [osa lokální obálky, min, max] (0 = x, 1 = y výška, 2 = z délka).
const RULES := {
	"postava": {"float": 0.12, "bury": 0.12, "tilt": 10.0, "size": [1, 1.5, 2.0]},
	"auto": {"float": 0.2, "bury": 0.2, "tilt": 12.0, "size": [2, 3.5, 5.0]},
	"dodavka": {"float": 0.2, "bury": 0.2, "tilt": 12.0, "size": [2, 4.0, 6.0]},
	"traktor": {"float": 0.2, "bury": 0.2, "tilt": 12.0, "size": [2, 2.2, 4.0]},
	"jednostopa": {"float": 0.15, "bury": 0.15, "tilt": 30.0, "size": [2, 1.5, 2.4]},
	"zvire": {"float": 0.25, "bury": 0.25, "tilt": 30.0, "size": [2, 0.25, 3.8]},
	"predmet": {"float": 0.08, "bury": 0.1, "tilt": 180.0, "size": []},
	"prop": {"float": 0.1, "bury": 0.12, "tilt": 12.0, "size": []},
}
const BIG_CARS := ["van", "bednar"]
const HOVER_ITEMS := ["dukat", "zalud"]     # sběratelské předměty se záměrně vznášejí a točí (Item._process)

var world: World
var main: Node
var center := Vector3.ZERO
var radius := 400.0
var findings: Array = []
var stats := {}
var _per_check := {}
var _ctx: Dictionary
var _b := {}                        # id → {poly, ground, eave, ridge, bb: Rect2}
var _bgrid := {}                    # Vector2i → [id]
var _rseg: Array = []               # [a: Vector2, b: Vector2, half: float, kind]
var _rgrid := {}                    # Vector2i → [index segmentu]
var _space: PhysicsDirectSpaceState3D


func run(w: World, main_node: Node, c: Vector3, r: float) -> Dictionary:
	world = w
	main = main_node
	center = c
	radius = r
	_ctx = GeomChecks.new_ctx()
	GeomChecks._sampler_seen.clear()
	_space = w.get_world_3d().direct_space_state if w.is_inside_tree() else null
	var t0 := Time.get_ticks_msec()
	_load_buildings()
	_index_roads()
	_stat("budovy_v_datech", _b.size())
	_check_generic()
	_check_entities()
	_check_trees()
	_check_vegetation()
	_check_lamps()
	_check_fences()
	_check_facades()
	_check_roads_zfight()
	_check_duplicates_and_coplanar()
	for k in _per_check:
		var n: int = _per_check[k]
		if n > MAX_PER_CHECK:
			findings.append(GeomChecks.finding("INFO", k, "", "… a dalších %d nálezů této kontroly (vypsáno prvních %d)" % [
				n - MAX_PER_CHECK, MAX_PER_CHECK]))
	for rep in GeomChecks.sampler_repeats():
		findings.append(GeomChecks.finding("INFO", "shader_sampler_unbound", "", "%s: stejný nález u dalších %d materiálů" % [
			rep[0], int(rep[1]) - 1]))
	stats["nalezy_podle_kontroly"] = _per_check.duplicate()
	stats["meshe_zkontrolovano"] = _ctx["checked_meshes"]
	stats["materialy_zkontrolovano"] = _ctx["checked_materials"]
	stats["geometrie_uzlu"] = _ctx["geometry_nodes"]
	stats["stred"] = [snappedf(c.x, 0.01), snappedf(c.y, 0.01), snappedf(c.z, 0.01)]
	stats["polomer_m"] = r
	stats["trvani_ms"] = Time.get_ticks_msec() - t0
	var sev := {"FAIL": 0, "WARN": 0, "INFO": 0}
	for f in findings:
		sev[f["severity"]] = int(sev.get(f["severity"], 0)) + 1
	stats["nalezy"] = sev
	return {"findings": findings, "stats": stats}


# ------------------------------------------------------------------ pomocné

func _add(sev: String, check: String, node: String, msg: String, pos := Vector3.INF) -> void:
	var n: int = _per_check.get(check, 0) + 1
	_per_check[check] = n
	if n <= MAX_PER_CHECK:
		findings.append(GeomChecks.finding(sev, check, node, msg, pos))


func _stat(key: String, v) -> void:
	stats[key] = v


func _cat_stat(cat: String, key: String, add := 1) -> void:
	if not stats.has("kategorie"):
		stats["kategorie"] = {}
	var c: Dictionary = stats["kategorie"]
	if not c.has(cat):
		c[cat] = {"pocet": 0, "ok": 0, "fail": 0, "warn": 0}
	c[cat][key] = int(c[cat].get(key, 0)) + add


func _in_radius(p: Vector3) -> bool:
	return Vector2(p.x - center.x, p.z - center.z).length() <= radius


func _h(x: float, z: float) -> float:
	return world.terrain.height_at(x, z)


## Rozsah terénu pod obdélníkem obálky (střed + 4 rohy + středy hran) → [min, max].
func _ground_range(a: AABB) -> Vector2:
	var lo := INF
	var hi := -INF
	for fx in [0.0, 0.5, 1.0]:
		for fz in [0.0, 0.5, 1.0]:
			var g := _surf(a.position.x + a.size.x * fx, a.position.z + a.size.z * fz, a.end.y + 0.3)
			lo = minf(lo, g)
			hi = maxf(hi, g)
	return Vector2(lo, hi)


## Výška povrchu pod bodem: max(terén, první statická kolize – vrstva 1: terén, silnice +0,1 m, podlahy, schody)
## paprskem shora od `from_y`. Bez fyziky jen `Terrain.height_at`.
func _surf(x: float, z: float, from_y: float) -> float:
	var g := _h(x, z)
	if _space == null:
		return g
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, maxf(from_y, g + 0.5), z), Vector3(x, g - 0.5, z), 1)
	q.collide_with_areas = false
	var hit := _space.intersect_ray(q)
	if hit.is_empty():
		return g
	return maxf(g, (hit["position"] as Vector3).y)


static func _pos_str(p: Vector3) -> String:
	return "[%.1f, %.1f, %.1f]" % [p.x, p.y, p.z]


# ------------------------------------------------------------------ budovy a silnice

func _load_buildings() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings.json"))
	if not (data is Array):
		_add("WARN", "data", "data/buildings.json", "nelze načíst – kontroly „v domě“ a fasád vynechány")
		return
	for d in data:
		var poly := PackedVector2Array()
		for p in d.get("poly", []):
			poly.append(Vector2(float(p[0]), float(p[1])))
		if poly.size() < 3:
			continue
		var id := int(d.get("id", 0))
		var bb := Rect2(poly[0], Vector2.ZERO)
		for p in poly:
			bb = bb.expand(p)
		var g := float(d.get("ground_y", d.get("eave_y", 0.0)))
		_b[id] = {"poly": poly, "ground": g, "eave": float(d.get("eave_y", g + 3.0)),
			"ridge": float(d.get("ridge_y", d.get("eave_y", g + 3.0))), "bb": bb, "type": str(d.get("type", ""))}
		for cx in range(floori(bb.position.x / GRID), floori(bb.end.x / GRID) + 1):
			for cz in range(floori(bb.position.y / GRID), floori(bb.end.y / GRID) + 1):
				var k := Vector2i(cx, cz)
				if not _bgrid.has(k):
					_bgrid[k] = []
				_bgrid[k].append(id)


## Id budovy, v jejímž půdorysu (zmenšeném o `inset` m) leží bod; 0 = žádná.
func _building_at(p: Vector2, inset := 0.0) -> int:
	var k := Vector2i(floori(p.x / GRID), floori(p.y / GRID))
	for id_v in _bgrid.get(k, []):
		var id: int = id_v
		var b: Dictionary = _b[id]
		if not (b["bb"] as Rect2).grow(0.01).has_point(p):
			continue
		var poly: PackedVector2Array = b["poly"]
		if Geometry2D.is_point_in_polygon(p, poly):
			if inset <= 0.0 or _edge_dist(p, poly) >= inset:
				return id
	return 0


## Vzdálenost bodu od nejbližší hrany polygonu.
static func _edge_dist(p: Vector2, poly: PackedVector2Array) -> float:
	var best := INF
	for i in poly.size():
		var q := Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])
		best = minf(best, q.distance_to(p))
	return best


## Nejbližší budova k bodu (podle hrany půdorysu) do `r` m → [id, vzdálenost].
func _nearest_building(p: Vector2, r: float) -> Array:
	var best_id := 0
	var best := INF
	var k0 := Vector2i(floori((p.x - r) / GRID), floori((p.y - r) / GRID))
	var k1 := Vector2i(floori((p.x + r) / GRID), floori((p.y + r) / GRID))
	var seen := {}
	for cx in range(k0.x, k1.x + 1):
		for cz in range(k0.y, k1.y + 1):
			for id_v in _bgrid.get(Vector2i(cx, cz), []):
				var id: int = id_v
				if seen.has(id):
					continue
				seen[id] = true
				var d := _edge_dist(p, _b[id]["poly"])
				if d < best:
					best = d
					best_id = id
	return [best_id, best]


func _index_roads() -> void:
	var g: RoadGraph = world.graph
	if g == null:
		return
	for i in g.nodes.size():
		var a: Vector2 = g.nodes[i]
		if a.distance_to(Vector2(center.x, center.z)) > radius + 100.0:
			continue
		for j_v in g.adj[i]:
			var j: int = j_v
			if j < i and g.nodes[j].distance_to(Vector2(center.x, center.z)) <= radius + 100.0:
				continue
			var kind := g.edge(i, j)
			if not ROAD_HALF.has(kind):
				continue
			var b: Vector2 = g.nodes[j]
			var si := _rseg.size()
			_rseg.append([a, b, float(ROAD_HALF[kind]), kind])
			var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y))
			var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
			for cx in range(floori(lo.x / GRID), floori(hi.x / GRID) + 1):
				for cz in range(floori(lo.y / GRID), floori(hi.y / GRID) + 1):
					var k := Vector2i(cx, cz)
					if not _rgrid.has(k):
						_rgrid[k] = []
					_rgrid[k].append(si)


## Vozovka pod bodem → [druh, vzdálenost od osy, poloviční šířka] nebo [] (mimo silnici).
func _road_at(p: Vector2, margin := 0.0) -> Array:
	var best: Array = []
	var bd := INF
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			for si_v in _rgrid.get(Vector2i(floori(p.x / GRID) + dx, floori(p.y / GRID) + dz), []):
				var s: Array = _rseg[si_v]
				var q := Geometry2D.get_closest_point_to_segment(p, s[0], s[1])
				var d := q.distance_to(p)
				if d < float(s[2]) - margin and d < bd:
					bd = d
					best = [s[3], d, s[2]]
	return best


# ------------------------------------------------------------------ obecná kontrola všech meshů

func _check_generic() -> void:
	var gis := []
	GeomChecks.geometry_under(main, gis)
	var n := 0
	for gi_v in gis:
		var gi: GeometryInstance3D = gi_v
		if not gi.is_visible_in_tree() or not GeomChecks.is_solid(gi):
			continue
		var xf := gi.global_transform
		if not GeomChecks.xform_ok(xf):
			_add("FAIL", "nan_transform", GeomChecks.path_of(gi), "transformace obsahuje NaN / nekonečno")
			continue
		var wa: AABB = xf * gi.get_aabb()
		# v okruhu: obálka zasahuje do kruhu (velké meshe – terén, okolí – projdou taky)
		var cx := clampf(center.x, wa.position.x, wa.end.x)
		var cz := clampf(center.z, wa.position.z, wa.end.z)
		if Vector2(cx - center.x, cz - center.z).length() > radius:
			continue
		n += 1
		var tmp := []
		GeomChecks.check_geometry(gi, tmp, _ctx)
		for f in tmp:
			var p = f["pos"]
			_add(f["severity"], f["check"], f["node"], f["msg"], Vector3(p[0], p[1], p[2]) if p is Array else Vector3.INF)
	_stat("geometrie_v_okruhu", n)


# ------------------------------------------------------------------ objekty po kategoriích

var _prop_boxes: Array = []         # obálky fyzikálních věcí (stohování beden: horní stojí na spodní)


func _check_entities() -> void:
	var ents := []
	_collect_entities(main, ents)
	for e in ents:
		if e[1] == "prop" and (e[0] as Node3D).is_visible_in_tree():
			var r := GeomChecks.aabb_of(e[2])
			if int(r["n"]) > 0:
				_prop_boxes.append([r["aabb"], e[0]])
	for e in ents:
		_check_entity(e[0], e[1], e[2])
		if e[0] is Car:
			_check_car_wheels(e[0] as Car)


## Kola auta (top_level MeshInstance3D přímo pod `Car`) musí být u auta – ne např. v počátku světa.
func _check_car_wheels(c: Car) -> void:
	if not c.is_visible_in_tree() or c.vis == null or not _in_radius(c.vis.global_position):
		return
	var cp := c.vis.global_position
	_cat_stat("kola_aut", "pocet")
	var lim := (c.model.length if c.model else 5.0) * 0.75 + 0.5
	var bad := 0
	var ex := Vector3.ZERO
	for ch in c.get_children():
		if ch is MeshInstance3D and (ch as MeshInstance3D).top_level and (ch as MeshInstance3D).visible:
			var wp := (ch as MeshInstance3D).global_position
			if wp.distance_to(cp) > lim:
				bad += 1
				ex = wp
	if bad > 0:
		_add("FAIL", "wheel_detached", GeomChecks.path_of(c),
			"vozidlo %s: %d kol je %.0f m od auta (kolo v %s, auto v %s) – vizuál kol se neaktualizoval (uspané auto?)" % [
				c.model_id, bad, ex.distance_to(cp), _pos_str(ex), _pos_str(cp)], cp)
		_cat_stat("kola_aut", "fail")
	else:
		_cat_stat("kola_aut", "ok")


## Stojí obálka `a` na jiné fyzikální věci (bedna na bedně)?
func _supported_by_prop(a: AABB, me: Node) -> bool:
	for pb in _prop_boxes:
		if pb[1] == me:
			continue
		var o: AABB = pb[0]
		if o.end.y < a.position.y - 0.15 or o.end.y > a.position.y + 0.15:
			continue
		if o.position.x < a.end.x and o.end.x > a.position.x and o.position.z < a.end.z and o.end.z > a.position.z:
			return true
	return false


## [uzel, kategorie, soustava pro rozměry (uzel s vizuálem)]
func _collect_entities(n: Node, out: Array) -> void:
	if n is Humanoid:
		var h := n as Humanoid
		var skip := h.pose != "stand"
		var a := n.get_parent()
		while a != null and a != main:
			if a is Car or a is Horse or a is QuadrupedRig:
				skip = true
				break
			a = a.get_parent()
		if not skip:
			out.append([h, "postava", h])
		return
	if n is Car:
		var c := n as Car
		var cat := "auto"
		if c.model != null and c.model.kind != "car":
			cat = "jednostopa"
		elif c.model_id in BIG_CARS:
			cat = "dodavka"
		elif c.model != null and c.model.spec.has("builder"):
			cat = "traktor"
		out.append([c, cat, c.vis if c.vis != null else c])
		return
	if n is Animal or n is Horse or n is Dog or n is FarmAnimal:
		out.append([n, "zvire", n])
		return
	if n is Item:
		out.append([n, "predmet", n])
		return
	if n is Prop or (n is RigidBody3D and n.get_parent() == world):
		out.append([n, "prop", n])
		return
	for c in n.get_children():
		_collect_entities(c, out)


func _check_entity(e: Node3D, cat: String, vis: Node3D) -> void:
	if not e.is_visible_in_tree():
		return
	var rule: Dictionary = RULES[cat]
	var name_ := GeomChecks.path_of(e)
	var wr := GeomChecks.aabb_of(vis)
	if int(wr["n"]) == 0:
		return
	var wa: AABB = wr["aabb"]
	if not _in_radius(wa.get_center()):
		return
	_cat_stat(cat, "pocet")
	var bad := 0
	var warn := 0
	var pos := wa.get_center()
	pos.y = wa.position.y
	if not (GeomChecks.vec_ok(wa.position) and GeomChecks.vec_ok(wa.size)):
		_add("FAIL", "nan_aabb", name_, "obálka obsahuje NaN")
		_cat_stat(cat, "fail")
		return
	# --- terén: vznáší se / zabořený
	var gr := _ground_range(wa)
	var bottom := wa.position.y
	var label := _label(e, cat)
	var hover := e is Item and (e as Item).kind in HOVER_ITEMS
	# míč – obálka natočené koule je krychle o hraně až √3 × průměr → spodek z polohy středu a poloměru
	var round_ := false
	for ch in vis.get_children():
		if ch is MeshInstance3D and (ch as MeshInstance3D).mesh is SphereMesh:
			round_ = true
			var mi := ch as MeshInstance3D
			var r_ := (mi.mesh as SphereMesh).radius * mi.global_transform.basis.get_scale().y
			if cat == "prop":
				bottom = mi.global_position.y - r_
	if e is Item:
		bottom = (e as Item).global_position.y         # předmět bobuje ±2 cm – měří se počátek (stojí na zemi)
	elif e is Car:
		# počátek modelu vozidla = země uprostřed rozvoru (CarModel); obálka karoserie bez kol by „visela“
		var vp := vis.global_position
		bottom = vp.y
		# spodek kol z fyzikálních kol (stejně jako Car._update_wheel_visuals: úchyt − pružení − poloměr);
		# nezávisí na tom, jestli se vizuál kol aktualizoval (uspané auto → wheel_detached)
		var c := e as Car
		var wb := INF
		var att = c.get("_wheel_attach")
		if att is Array and att.size() == c.wheels.size():
			var cxf := c.global_transform
			var up := cxf.basis.y.normalized()
			for i in c.wheels.size():
				var w = c.wheels[i]
				var wc: Vector3 = (cxf * (att[i] as Vector3)) - up * minf(float(w.sus_len), float(w.rest) + float(w.travel))
				wb = minf(wb, wc.y - float(w.radius))
		if wb != INF:
			bottom = wb
		var gc := _surf(vp.x, vp.z, vp.y + 1.0)
		gr = Vector2(gc, gc)
		var half_l := (e as Car).model.length * 0.5 if (e as Car).model else 2.0
		var fwd := vis.global_transform.basis.z.normalized() * half_l
		for q in [vp + fwd, vp - fwd]:
			var gq := _surf(q.x, q.z, vp.y + 1.5)
			gr = Vector2(minf(gr.x, gq), maxf(gr.y, gq))
		gr = Vector2(gc - (gc - gr.x) * 0.5, gc + (gr.y - gc) * 0.5)   # počátek je uprostřed: polovina převýšení
	if hover:
		_cat_stat(cat, "vznasi_zamerne")
	elif cat == "prop" and bottom > gr.y + float(rule["float"]) and _supported_by_prop(wa, e):
		_cat_stat(cat, "stohovano")
	elif bottom > gr.y + float(rule["float"]):
		var d := bottom - gr.y
		var sev := "FAIL" if d > float(rule["float"]) * 2.5 else "WARN"
		_add(sev, "floating", name_, "%s se vznáší %.2f m nad povrchem (spodek %.2f, povrch – terén / silnice / podlaha – %.2f–%.2f)" % [
			label, d, bottom, gr.x, gr.y], pos)
		if sev == "FAIL":
			bad += 1
		else:
			warn += 1
	elif bottom < gr.x - float(rule["bury"]):
		var d2 := gr.x - bottom
		var sev2 := "FAIL" if d2 > float(rule["bury"]) * 2.5 else "WARN"
		_add(sev2, "buried", name_, "%s je zabořený %.2f m pod povrchem (spodek %.2f, povrch %.2f–%.2f)" % [
			label, d2, bottom, gr.x, gr.y], pos)
		if sev2 == "FAIL":
			bad += 1
		else:
			warn += 1
	# --- svislost (u aut vůči sklonu terénu)
	var basis := vis.global_transform.basis.orthonormalized()
	var tilt := GeomChecks.tilt_deg(basis)
	var slope := _slope_deg(pos.x, pos.z)
	if not round_ and tilt - slope > float(rule["tilt"]):
		_add("WARN", "not_upright", name_, "%s je nakloněný %.0f° od svislice (svah %.0f°, tolerance %.0f°)" % [
			label, tilt, slope, rule["tilt"]], pos)
		warn += 1
	# --- velikost v lokální soustavě
	var sz: Array = rule["size"]
	if not sz.is_empty():
		var frame := Transform3D(basis, vis.global_position)
		var la: AABB = GeomChecks.aabb_of(vis, frame)["aabb"]
		var v: float = la.size[int(sz[0])]
		if v < float(sz[1]) * 0.9 or v > float(sz[2]) * 1.1:
			_add("WARN", "size", name_, "%s: %s %.2f m mimo rozsah %.1f–%.1f m" % [label,
				["šířka", "výška", "délka"][int(sz[0])], v, sz[1], sz[2]], pos)
			warn += 1
	# --- v domě: střed půdorysu (a u velkých objektů i rohy zmenšené o 25 %)
	var c2 := Vector2(wa.get_center().x, wa.get_center().z)
	var bid := _building_at(c2, 0.3)
	if bid != 0:
		var b: Dictionary = _b[bid]
		if wa.end.y > float(b["ground"]) - 1.0 and wa.position.y < float(b["ridge"]) + 0.5:
			var sev3 := "WARN" if cat == "postava" else "FAIL"
			_add(sev3, "inside_building", name_, "%s stojí uvnitř půdorysu budovy %d (%s)" % [label, bid, b["type"]], pos)
			if sev3 == "FAIL":
				bad += 1
			else:
				warn += 1
	elif cat in ["auto", "dodavka", "traktor", "prop"]:
		var hits := 0
		for fx in [0.2, 0.8]:
			for fz in [0.2, 0.8]:
				if _building_at(Vector2(wa.position.x + wa.size.x * fx, wa.position.z + wa.size.z * fz), 0.1) != 0:
					hits += 1
		if hits > 0:
			_add("WARN", "intersects_building", name_, "%s zasahuje do půdorysu budovy (%d ze 4 rohů)" % [label, hits], pos)
			warn += 1
	if bad > 0:
		_cat_stat(cat, "fail")
	elif warn > 0:
		_cat_stat(cat, "warn")
	else:
		_cat_stat(cat, "ok")


func _label(e: Node, cat: String) -> String:
	if e is Car:
		return "vozidlo %s" % (e as Car).model_id
	if e is Item:
		return "předmět %s" % (e as Item).kind
	if e is Humanoid:
		var p := e.get_parent()
		if p == null:
			return "postava"
		var ps := p.get_script() as Script
		return "postava (%s %s)" % [String(ps.get_global_name()) if ps else p.get_class(), p.name]
	if e is Prop:
		return "prop %s" % String(e.get("kind")) if e.get("kind") != null else "prop"
	var s := e.get_script() as Script
	return "%s %s" % [cat, String(s.get_global_name()) if s else e.get_class()]


func _slope_deg(x: float, z: float) -> float:
	var d := 1.5
	var gx := (_h(x + d, z) - _h(x - d, z)) / (2.0 * d)
	var gz := (_h(x, z + d) - _h(x, z - d)) / (2.0 * d)
	return rad_to_deg(atan(Vector2(gx, gz).length()))


# ------------------------------------------------------------------ stromy, vegetace, lampy, ploty

func _find_named(n: Node, nm: String, out: Array) -> void:
	if String(n.name) == nm:
		out.append(n)
	for c in n.get_children():
		_find_named(c, nm, out)


## Instance MultiMeshů pod `root` v okruhu (deduplikované podle polohy). Vrací [Transform3D globální, mmi].
func _mm_instances(root: Node, limit_per_mm := 0) -> Array:
	var out := []
	var seen := {}
	var gis := []
	GeomChecks.geometry_under(root, gis)
	for gi in gis:
		if not (gi is MultiMeshInstance3D):
			continue
		var mmi := gi as MultiMeshInstance3D
		var mm := mmi.multimesh
		if mm == null:
			continue
		var gx := mmi.global_transform
		var n := mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
		var step := 1 if limit_per_mm <= 0 else maxi(1, n / limit_per_mm)
		for i in range(0, n, step):
			var xf := gx * mm.get_instance_transform(i)
			var o := xf.origin
			if not _in_radius(o):
				continue
			if xf.basis.get_scale().length() < 0.01:
				continue                    # skrytá instance (pokácený strom – HIDE_SCALE)
			var key := Vector3i(roundi(o.x * 20.0), roundi(o.y * 20.0), roundi(o.z * 20.0))
			if seen.has(key):
				continue
			seen[key] = true
			out.append([xf, mmi])
	return out


func _check_trees() -> void:
	var roots := []
	_find_named(world, "Stromy", roots)
	var n := 0
	var cat := "strom"
	for r in roots:
		for e in _mm_instances(r):
			var xf: Transform3D = e[0]
			var o := xf.origin
			n += 1
			_cat_stat(cat, "pocet")
			var g := _h(o.x, o.z)
			var name_ := GeomChecks.path_of(e[1])
			var bad := false
			if o.y > g + 0.05:
				_add("FAIL", "floating", name_, "strom: pata kmene %.2f m nad terénem" % (o.y - g), o)
				bad = true
			elif o.y < g - 0.8:
				_add("WARN", "buried", name_, "strom: pata kmene %.2f m pod terénem (data trees.bin)" % (g - o.y), o)
				bad = true
			var p2 := Vector2(o.x, o.z)
			var bid := _building_at(p2, 0.2)
			if bid != 0:
				_add("FAIL", "tree_in_building", name_, "strom stojí v budově %d (%s)" % [bid, _b[bid]["type"]], o)
				bad = true
			var rd := _road_at(p2, 0.3)
			if not rd.is_empty():
				_add("WARN", "tree_on_road", name_, "strom na silnici (%s, %.1f m od osy, půlšířka %.1f m)" % [rd[0], rd[1], rd[2]], o)
				bad = true
			_cat_stat(cat, "fail" if bad else "ok")
	_stat("stromy_v_okruhu", n)


func _check_vegetation() -> void:
	var vm = world.vegetation
	if vm == null:
		return
	var cat := "vegetace"
	var n := 0
	for e in _mm_instances(vm, MM_SAMPLE):
		var xf: Transform3D = e[0]
		var o := xf.origin
		n += 1
		_cat_stat(cat, "pocet")
		var g := _h(o.x, o.z)
		var name_ := GeomChecks.path_of(e[1])
		var bad := false
		if o.y > g + 0.15:
			_add("WARN", "floating", name_, "vegetace: instance %.2f m nad terénem" % (o.y - g), o)
			bad = true
		elif o.y < g - 0.5:
			_add("WARN", "buried", name_, "vegetace: instance %.2f m pod terénem" % (g - o.y), o)
			bad = true
		var bid := _building_at(Vector2(o.x, o.z), 0.3)
		if bid != 0:
			_add("WARN", "veg_in_building", name_, "vegetace uvnitř budovy %d" % bid, o)
			bad = true
		_cat_stat(cat, "warn" if bad else "ok")
	_stat("vegetace_vzorek", n)


func _check_lamps() -> void:
	var sl: StreetLights = null
	var roots := []
	_find_named(main, "VerejneOsvetleni", roots)
	if not roots.is_empty():
		sl = roots[0] as StreetLights
	if sl == null:
		return
	var poles := []
	_find_named(sl, "Sloupy", poles)
	if poles.is_empty():
		return
	var mmi := poles[0] as MultiMeshInstance3D
	var mh := mmi.multimesh.mesh.get_aabb().size.y if mmi.multimesh and mmi.multimesh.mesh else 0.0
	var cat := "lampa"
	for e in _mm_instances(mmi):
		var xf: Transform3D = e[0]
		var o := xf.origin
		_cat_stat(cat, "pocet")
		var g := _h(o.x, o.z)
		var name_ := GeomChecks.path_of(mmi)
		var bad := false
		if o.y > g + 0.05:
			_add("FAIL", "floating", name_, "lampa: pata sloupu %.2f m nad terénem" % (o.y - g), o)
			bad = true
		elif o.y < g - 0.3:
			_add("WARN", "buried", name_, "lampa: pata sloupu %.2f m pod terénem" % (g - o.y), o)
			bad = true
		var tilt := GeomChecks.tilt_deg(xf.basis.orthonormalized())
		if tilt > 3.0:
			_add("WARN", "not_upright", name_, "lampa nakloněná %.1f°" % tilt, o)
			bad = true
		var h := mh * xf.basis.get_scale().y
		if h < 4.0 or h > 9.0:
			_add("WARN", "size", name_, "lampa vysoká %.1f m (čekáno 4–9 m)" % h, o)
			bad = true
		var bid := _building_at(Vector2(o.x, o.z), 0.0)
		if bid != 0:
			_add("FAIL", "inside_building", name_, "lampa stojí v budově %d" % bid, o)
			bad = true
		var rd := _road_at(Vector2(o.x, o.z), 0.2)
		if not rd.is_empty():
			_add("WARN", "lamp_on_road", name_, "lampa na vozovce (%s, %.1f m od osy)" % [rd[0], rd[1]], o)
			bad = true
		_cat_stat(cat, "fail" if bad else "ok")


func _check_fences() -> void:
	var fm: FenceManager = world.fences
	if fm == null:
		return
	var cat := "plot"
	for run in fm.runs():
		var pts: PackedVector3Array = run["pts"]
		_cat_stat(cat, "pocet")
		var bad := false
		for i in pts.size():
			var p := pts[i]
			if not _in_radius(p):
				continue
			var g := _h(p.x, p.z)
			if absf(p.y - g) > 0.1:
				_add("WARN", "floating" if p.y > g else "buried", "World/FenceManager",
					"plot (typ %d): bod %d je %.2f m %s terénem" % [run["type"], i, absf(p.y - g), "nad" if p.y > g else "pod"], p)
				bad = true
			if i + 1 < pts.size() and not (run["gaps"] as Array).has(i):
				var q := pts[i + 1]
				var steps := maxi(1, ceili(Vector2(q.x - p.x, q.z - p.z).length() / 1.0))
				for s in steps + 1:
					var m := p.lerp(q, float(s) / steps)
					var bid := _building_at(Vector2(m.x, m.z), 0.2)
					if bid != 0:
						_add("FAIL", "fence_through_building", "World/FenceManager",
							"plot (typ %d) prochází budovou %d (úsek %d)" % [run["type"], bid, i], m)
						bad = true
						break
		_cat_stat(cat, "fail" if bad else "ok")


# ------------------------------------------------------------------ fasády

func _check_facades() -> void:
	var bd: BuildingDetails = world.building_details
	if bd == null:
		_stat("fasady", "BuildingDetails chybí (bez data/buildings.json)")
		return
	var cat := "okno"
	for c in bd.get_children():
		if not (c is MeshInstance3D):
			continue
		var mi := c as MeshInstance3D
		if mi.mesh == null or mi.mesh.get_surface_count() == 0:
			continue
		var mat := mi.mesh.surface_get_material(0)
		if not (mat is ShaderMaterial and (mat as ShaderMaterial).shader
				and (mat as ShaderMaterial).shader.resource_path.ends_with("window_glass.gdshader")):
			continue
		var verts: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var xf := mi.global_transform
		for k in range(0, verts.size() - 5, 6):
			var bl := xf * verts[k]
			var tl := xf * verts[k + 1]
			var tr := xf * verts[k + 2]
			var ctr := (bl + tr) * 0.5
			if not _in_radius(ctr):
				continue
			_cat_stat(cat, "pocet")
			var bad := false
			var w := bl.distance_to(Vector3(tr.x, bl.y, tr.z))
			var h := tl.y - bl.y
			var nb := _nearest_building(Vector2(ctr.x, ctr.z), 3.0)
			var name_ := GeomChecks.path_of(mi)
			if int(nb[0]) == 0 or float(nb[1]) > 0.15:
				_add("FAIL", "window_off_wall", name_, "okno %.2f m od nejbližší zdi (budova %d) – není v rovině zdi" % [
					float(nb[1]) if int(nb[0]) != 0 else INF, nb[0]], ctr)
				bad = true
			else:
				var b: Dictionary = _b[int(nb[0])]
				var g := _h(ctr.x, ctr.z)
				if bl.y < g - 0.05:
					_add("FAIL", "window_below_ground", name_, "okno budovy %d začíná %.2f m pod terénem" % [nb[0], g - bl.y], ctr)
					bad = true
				if tl.y > float(b["eave"]) + 0.05:
					_add("FAIL", "window_above_eave", name_, "okno budovy %d přesahuje okap o %.2f m" % [nb[0], tl.y - float(b["eave"])], ctr)
					bad = true
			if w < 0.4 or w > 2.2 or h < 0.4 or h > 2.5:
				_add("WARN", "window_size", name_, "okno %.2f × %.2f m mimo 0,6–2 m" % [w, h], ctr)
				bad = true
			_cat_stat(cat, "fail" if bad else "ok")
	# dveře / vrata: bod na fasádě u terénu (BuildingDetails._doors)
	var doors: Dictionary = bd.get("_doors") if bd.get("_doors") != null else {}
	for id in doors:
		var dinfo: Dictionary = doors[id]
		var p: Vector3 = dinfo["pos"]
		if not _in_radius(p):
			continue
		_cat_stat("dvere", "pocet")
		var bad := false
		var nm := "Fasady/dvere_%d" % int(id)
		var kind: String = dinfo.get("kind", "door")
		var hgt := float(dinfo.get("height", BuildingDetails.DOOR_H))   # skutečná výška (dveře snížené pod okap)
		var b2: Dictionary = bd.buildings().get(id, {})
		if kind == "gate" and not dinfo.has("height"):
			var rule: Dictionary = BuildingDetails.RULES.get(b2.get("type", "house"), {})
			hgt = float(rule.get("gate", [3.0, 2.5])[1])
		if _b.has(int(id)):
			var ed := _edge_dist(Vector2(p.x, p.z), _b[int(id)]["poly"])
			if ed > 0.15:
				_add("FAIL", "door_off_wall", nm, "dveře budovy %d jsou %.2f m od zdi" % [id, ed], p)
				bad = true
			var top := p.y + (BuildingDetails.DOOR_STEP if kind == "door" else 0.02) + hgt
			if top > float(_b[int(id)]["eave"]) + 0.05:
				_add("FAIL", "door_above_eave", nm, "%s budovy %d končí %.2f m nad okapem (terén u dveří %.2f, okap %.2f)" % [
					"dveře" if kind == "door" else "vrata", id, top - float(_b[int(id)]["eave"]), p.y, _b[int(id)]["eave"]], p)
				bad = true
			if p.y < float(_b[int(id)]["ground"]) - 1.0:
				_add("WARN", "door_ground", nm, "dveře budovy %d: terén u dveří %.2f m pod ground_y budovy" % [
					id, float(_b[int(id)]["ground"]) - p.y], p)
				bad = true
		if kind == "door" and (hgt < 1.8 or hgt > 2.3):
			_add("WARN", "door_size", nm, "dveře vysoké %.2f m (čekáno ~2 m)" % hgt, p)
			bad = true
		_cat_stat("dvere", "fail" if bad else "ok")


# ------------------------------------------------------------------ z-fighting

## Silnice / cesty vs. terén (vrcholy, středy hran a těžiště trojúhelníků < 2 cm nad terénem nebo pod ním) a štěrkové
## cesty položené přes asfalt (koplanární dlaždice 1 cm nad sebou → blikání).
func _check_roads_zfight() -> void:
	var asph := _road_tris("Silnice")
	var grav := _road_tris("Cesty")
	for pair in [["Silnice", asph], ["Cesty", grav]]:
		var tris: Array = pair[1]
		var n := 0
		var low := 0
		var under := 0
		var ex_low := Vector3.INF
		var ex_under := Vector3.INF
		for t in tris:
			for s in _tri_samples(t):
				var d: float = s.y - _h(s.x, s.z)
				n += 1
				if d < -0.01:
					under += 1
					if ex_under == Vector3.INF:
						ex_under = s
				elif d < 0.02:
					low += 1
					if ex_low == Vector3.INF:
						ex_low = s
		_stat("zfight_%s_vzorku" % pair[0], n)
		if n == 0:
			continue
		if under > 0:
			_add("WARN" if float(under) / n < 0.01 else "FAIL", "road_under_terrain", "Mapa/%s" % pair[0],
				"%d z %d vzorků povrchu (%.1f %%) leží pod terénem – terén prorůstá" % [under, n, 100.0 * under / n], ex_under)
		if low > 0:
			_add("WARN", "zfight_road_terrain", "Mapa/%s" % pair[0],
				"%d z %d vzorků povrchu (%.1f %%) je < 2 cm nad terénem – riziko z-fightingu" % [low, n, 100.0 * low / n], ex_low)
	# štěrk přes asfalt: těžiště štěrkových trojúhelníků uvnitř asfaltového trojúhelníku s rozdílem výšky < 3 cm
	var grid := {}
	for i in asph.size():
		var t: Array = asph[i]
		var lo := Vector2(minf(t[0].x, minf(t[1].x, t[2].x)), minf(t[0].z, minf(t[1].z, t[2].z)))
		var hi := Vector2(maxf(t[0].x, maxf(t[1].x, t[2].x)), maxf(t[0].z, maxf(t[1].z, t[2].z)))
		for cx in range(floori(lo.x / 4.0), floori(hi.x / 4.0) + 1):
			for cz in range(floori(lo.y / 4.0), floori(hi.y / 4.0) + 1):
				var k := Vector2i(cx, cz)
				if not grid.has(k):
					grid[k] = []
				grid[k].append(i)
	var area := 0.0
	var cnt := 0
	var ex := Vector3.INF
	for t in grav:
		var c: Vector3 = (t[0] + t[1] + t[2]) / 3.0
		var c2 := Vector2(c.x, c.z)
		for i in grid.get(Vector2i(floori(c.x / 4.0), floori(c.z / 4.0)), []):
			var a: Array = asph[i]
			var pa := PackedVector2Array([Vector2(a[0].x, a[0].z), Vector2(a[1].x, a[1].z), Vector2(a[2].x, a[2].z)])
			if Geometry2D.is_point_in_polygon(c2, pa):
				var ya: float = (a[0].y + a[1].y + a[2].y) / 3.0
				if absf(ya - c.y) < 0.03:
					cnt += 1
					area += 0.5 * (t[1] - t[0]).cross(t[2] - t[0]).length()
					if ex == Vector3.INF:
						ex = c
				break
	_stat("zfight_sterk_pres_asfalt_m2", snappedf(area, 0.1))
	if cnt > 0:
		_add("WARN" if area < 20.0 else "FAIL", "zfight_gravel_asphalt", "Mapa/Cesty",
			"%d trojúhelníků štěrku (%.1f m²) leží v rovině asfaltu (rozdíl < 3 cm) – blikání (z-fighting)" % [cnt, area], ex)


## Trojúhelníky dlaždic `Mapa/<jméno>` v okruhu (světové souřadnice) → [[a, b, c], …].
func _road_tris(nm: String) -> Array:
	var out := []
	var roots := []
	for c in world.get_children():
		if String(c.name) == "Mapa":
			_find_named(c, nm, roots)
	for r in roots:
		for mi_v in r.get_children():
			if not (mi_v is MeshInstance3D):
				continue
			var mi := mi_v as MeshInstance3D
			if mi.mesh == null:
				continue
			var wa: AABB = mi.global_transform * mi.mesh.get_aabb()
			var cx := clampf(center.x, wa.position.x, wa.end.x)
			var cz := clampf(center.z, wa.position.z, wa.end.z)
			if Vector2(cx - center.x, cz - center.z).length() > radius:
				continue
			var xf := mi.global_transform
			var arr := mi.mesh.surface_get_arrays(0)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx := PackedInt32Array()
			if arr[Mesh.ARRAY_INDEX] != null:
				idx = arr[Mesh.ARRAY_INDEX]
			var indexed := idx.size() > 0
			var tri_n: int = (idx.size() if indexed else v.size()) / 3
			for t in tri_n:
				var ia: int = t * 3
				var a: Vector3 = xf * (v[idx[ia]] if indexed else v[ia])
				var b: Vector3 = xf * (v[idx[ia + 1]] if indexed else v[ia + 1])
				var c: Vector3 = xf * (v[idx[ia + 2]] if indexed else v[ia + 2])
				if _in_radius(a):
					out.append([a, b, c])
	return out


## Vzorky na trojúhelníku: těžiště a středy hran (vrcholy leží přesně na terénu + výška – ty nic neřeknou).
static func _tri_samples(t: Array) -> Array:
	var a: Vector3 = t[0]
	var b: Vector3 = t[1]
	var c: Vector3 = t[2]
	return [(a + b + c) / 3.0, (a + b) * 0.5, (b + c) * 0.5, (c + a) * 0.5]


## Duplicitní instance (stejný mesh, stejná transformace na 1 cm) a koplanární překrývající se ploché meshe.
func _check_duplicates_and_coplanar() -> void:
	var seen := {}
	var dup := 0
	var gis := []
	GeomChecks.geometry_under(main, gis)
	var flat := {}               # [osa, rovina cm] → [[Rect2, uzel]]
	for gi_v in gis:
		var gi: GeometryInstance3D = gi_v
		if not gi.is_visible_in_tree():
			continue
		if gi is MeshInstance3D:
			var mi := gi as MeshInstance3D
			if mi.mesh == null:
				continue
			if mi.top_level and mi.get_parent() is Car:
				continue                    # kola aut – hlásí wheel_detached
			var xf := mi.global_transform
			if not _in_radius((xf * mi.get_aabb()).get_center()) and not _in_radius(xf.origin):
				continue
			var key := _xf_key(mi.mesh.get_instance_id(), xf)
			if seen.has(key):
				dup += 1
				_add("WARN", "zfight_duplicate", GeomChecks.path_of(mi), "stejný mesh se stejnou transformací jako %s" % seen[key],
					(xf * mi.get_aabb()).get_center())
			else:
				seen[key] = GeomChecks.path_of(mi)
			var wa: AABB = xf * mi.get_aabb()
			for ax in 3:
				if wa.size[ax] < 0.005 and wa.size[(ax + 1) % 3] > 0.05 and wa.size[(ax + 2) % 3] > 0.05:
					var pk := Vector2i(ax, roundi(wa.position[ax] * 100.0))
					var u := (ax + 1) % 3
					var w := (ax + 2) % 3
					var rect := Rect2(wa.position[u], wa.position[w], wa.size[u], wa.size[w])
					if not flat.has(pk):
						flat[pk] = []
					for other in flat[pk]:
						var inter: Rect2 = (other[0] as Rect2).intersection(rect)
						if inter.get_area() > 0.01:
							_add("WARN", "zfight_coplanar", GeomChecks.path_of(mi), "koplanární plocha překrytá s %s (%.2f m²)" % [
								other[1], inter.get_area()], wa.get_center())
					flat[pk].append([rect, GeomChecks.path_of(mi)])
		elif gi is MultiMeshInstance3D:
			var mmi := gi as MultiMeshInstance3D
			var mm := mmi.multimesh
			if mm == null or mm.mesh == null:
				continue
			var mid := mm.mesh.get_instance_id()
			var gx := mmi.global_transform
			var n := mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
			var local := {}
			for i in range(0, n, maxi(1, n / MM_SAMPLE)):
				var xf2 := gx * mm.get_instance_transform(i)
				if not _in_radius(xf2.origin) or xf2.basis.get_scale().length() < 0.01:
					continue
				var k2 := _xf_key(mid, xf2)
				if local.has(k2) or seen.has(k2):
					dup += 1
					_add("WARN", "zfight_duplicate", GeomChecks.path_of(mmi), "instance %d má stejný mesh a transformaci jako jiná instance" % i, xf2.origin)
				local[k2] = true
			for k3 in local:
				seen[k3] = GeomChecks.path_of(mmi)
	_stat("duplicitni_instance", dup)


static func _xf_key(mesh_id: int, xf: Transform3D) -> String:
	var o := xf.origin
	var b := xf.basis
	return "%d|%d,%d,%d|%d,%d,%d|%d,%d,%d" % [mesh_id, roundi(o.x * 100), roundi(o.y * 100), roundi(o.z * 100),
		roundi(b.x.x * 100), roundi(b.x.z * 100), roundi(b.y.y * 100), roundi(b.z.x * 100), roundi(b.z.z * 100), roundi(b.y.x * 100)]
