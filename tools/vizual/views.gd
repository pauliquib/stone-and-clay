## Vizuální validátor – standardní pohledy jedné hry (svět se načte jen jednou): ulice u spawnu, náves,
## pole, okraj lesa, vyhlídka z kopce, dron nad vsí, soumrak, noc, déšť, zima.
##
## Polohy se volí deterministicky z dat (map.json spawn, buildings.json, Fields, TreeManager, Terrain) → stejné
## mezi běhy, snímky jdou porovnávat. Čas, počasí a datum se mění za běhu přes API světa (`World.set_time`,
## `World.set_weather`, `World.set_date`; hodiny stojí – `Clock.paused`) a po každé změně se čeká na ustálení
## (streaming vegetace / LOD stromů, expozice oblohy). Hráč se přenese pod kameru (streaming kolem hráče),
## jeho postava se skryje; HUD je skrytý. Snímek = celé okno (rozlišení `--resolution`).
##
## Výstup: `<out>/views/<jméno>.png` + `<out>/views.json` {"views": [{name, png, pos, yaw, pitch, time, weather,
## date, fov, look_at, why, fps, draw_calls, primitives}], "stats": {...}}
extends RefCounted

const EYE := 1.7                    # m – výška očí nad terénem
const SETTLE_S := 3.0               # s – čekání po přesunu kamery (streaming, LOD)
const SETTLE_CHANGE_S := 3.5        # s – čekání po změně času / počasí / data (přechody oblohy, expozice)
const MIN_FRAMES := 8
const BASE_DATE := [2026, 6, 15]    # datum 1. dne (letní den – shoduje se s parametry světa ve validator.gd)
const WINTER_DATE := [2027, 1, 20]  # zima: posun kalendáře dopředu (EcoClock dožene hrubým krokem)
const FOV := 70.0
const HIDE_LAYER := 1 << 19         # vrstva vizuálu hráče – kamera validátoru ji nekreslí
const CEREALS := ["psenice", "jecmen"]   # obilniny (Fields.CROPS) – jen na nich rostou 3D klasy (tools/vegetation.py)
const FIELD_PITCH := 6.0            # ° – pohled „pole“ mírně dolů přes porost
const EDGE_OPEN := [SurfaceMap.GRASS, SurfaceMap.ARABLE, SurfaceMap.ORCHARD, SurfaceMap.TRACK]
const EDGE_CAM_M := 32.0            # m – kamera před okrajem lesa (25–40 m)
const EDGE_TREES_MIN := 5           # stromů do 25 m za okrajem (les v syntetickém světě má rozestup ~10 m)

var tree: SceneTree
var world: World
var client: LocalClient
var out_dir := ""
var cam: Camera3D
var places := {}                    # jméno → {pos, look, why}
var _cur := {"time": 11.0, "weather": "jasno", "date": "%04d-%02d-%02d" % BASE_DATE}


func run(t: SceneTree, w: World, c: LocalClient, out: String, quick: bool) -> Dictionary:
	tree = t
	world = w
	client = c
	out_dir = out
	DirAccess.make_dir_recursive_absolute(out_dir.path_join("views"))
	world.clock.paused = true
	_pick_places()
	cam = Camera3D.new()
	cam.name = "VizualKamera"
	cam.fov = FOV
	cam.near = 0.05
	cam.far = 20000.0
	client.add_child(cam)
	cam.current = true
	cam.cull_mask &= ~HIDE_LAYER
	if client.player:
		_hide_player(client.player)
	# plán: [jméno, místo, hodina, počasí, zima]
	var plan := [
		["ulice", "ulice", 11.0, "jasno", false],
		["naves", "naves", 11.0, "jasno", false],
		["pole", "pole", 11.0, "jasno", false],
		["okraj_lesa", "okraj_lesa", 11.0, "jasno", false],
		["vyhlidka", "vyhlidka", 11.0, "jasno", false],
		["dron", "dron", 11.0, "jasno", false],
		["dest", "ulice", 14.0, "dest", false],
		["soumrak", "naves", 21.0, "jasno", false],
		["noc", "naves", 23.0, "jasno", false],
		["zima", "ulice", 11.0, "snih", true],
	]
	if quick:
		plan = plan.filter(func(p): return p[0] in ["ulice", "naves", "dron", "noc"])
	var views := []
	for p in plan:
		var e := await _shoot(p[0], places[p[1]], float(p[2]), String(p[3]), bool(p[4]))
		views.append(e)
		print("VIZUAL pohled: %s  %s" % [p[0], e["png"]])
	var res := {"views": views, "stats": {"views": views.size(), "resolution": [
		tree.root.get_visible_rect().size.x, tree.root.get_visible_rect().size.y],
		"places": _places_json()}}
	var f := FileAccess.open(out_dir.path_join("views.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(res, "  "))
	f.close()
	return res


# ------------------------------------------------------------------ výběr míst (deterministicky z dat)

func _h(x: float, z: float) -> float:
	return world.terrain.height_at(x, z)


func _pick_places() -> void:
	var sp: Dictionary = world.meta["spawn"]
	var s := Vector3(float(sp["x"]), 0, float(sp["z"]))
	s.y = _h(s.x, s.z) + EYE
	var look := Vector3(float(sp["look_x"]), 0, float(sp["look_z"]))
	look.y = _h(look.x, look.z) + EYE - 0.3
	places["ulice"] = {"pos": s, "look": look, "why": "map.json spawn → look_x/look_z"}
	var c := _village_center()
	places["naves"] = _naves_place(c)
	places["pole"] = _field_place(c)
	places["okraj_lesa"] = _forest_edge_place(c)
	places["vyhlidka"] = _hill_place(c)
	var dir := Vector3(-0.6, 0, 0.8).normalized()
	var dp := c + dir * 170.0
	dp.y = _h(c.x, c.z) + 120.0
	places["dron"] = {"pos": dp, "look": Vector3(c.x, _h(c.x, c.z), c.z),
		"why": "120 m nad středem vsi, 170 m jihozápadně, šikmo dolů"}


## Střed vsi: budova s nejvíc sousedními budovami do 80 m, průměr jejich středů.
func _village_center() -> Vector3:
	var cents: Array[Vector2] = []
	var bdata = JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings.json"))
	if bdata is Array:
		for b in bdata:
			var poly: Array = b.get("poly", [])
			if poly.size() < 3:
				continue
			var acc := Vector2.ZERO
			for p in poly:
				acc += Vector2(float(p[0]), float(p[1]))
			cents.append(acc / poly.size())
	if cents.is_empty():
		var sp: Dictionary = world.meta["spawn"]
		return Vector3(float(sp["x"]), _h(float(sp["x"]), float(sp["z"])), float(sp["z"]))
	var best := 0
	var best_n := -1
	for i in cents.size():
		var n := 0
		for j in cents.size():
			if cents[i].distance_squared_to(cents[j]) < 6400.0:
				n += 1
		if n > best_n:
			best_n = n
			best = i
	var acc2 := Vector2.ZERO
	var k := 0
	for j in cents.size():
		if cents[best].distance_squared_to(cents[j]) < 6400.0:
			acc2 += cents[j]
			k += 1
	var c2 := acc2 / maxi(k, 1)
	return Vector3(c2.x, _h(c2.x, c2.y), c2.y)


## Náves: uzel silnice 25–60 m od středu (nejblíž 35 m), kamera v očích chodce kouká na střed.
func _naves_place(c: Vector3) -> Dictionary:
	var g: RoadGraph = world.graph
	var best := Vector2.INF
	var best_d := INF
	if g:
		for i in g.nodes_within(Vector2(c.x, c.z), 60.0, RoadGraph.CAR_KINDS):
			var p: Vector2 = g.nodes[i]
			var d := p.distance_to(Vector2(c.x, c.z))
			if d < 25.0:
				continue
			var score := absf(d - 35.0) + (p.x + p.y) * 1e-6     # deterministický tie-break
			var eye := Vector3(p.x, _h(p.x, p.y) + EYE, p.y)
			if not world.line_clear(eye, Vector3(c.x, c.y + 2.0, c.z)):
				score += 100.0                                      # dům v cestě – až když není nic lepšího
			if score < best_d:
				best_d = score
				best = p
	if best == Vector2.INF:
		best = Vector2(c.x + 35.0, c.z)
	var pos := Vector3(best.x, _h(best.x, best.y) + EYE, best.y)
	return {"pos": pos, "look": Vector3(c.x, c.y + 2.0, c.z), "why": "střed vsi (hustota budov do 80 m), pohled ze silnice ~35 m"}


func _building_near(p: Vector2, r: float) -> bool:
	var bd = world.building_details
	if bd == null:
		return false
	for id in bd.buildings():
		var poly: PackedVector2Array = bd.buildings()[id]["poly"]
		if poly[0].distance_to(p) < r + 40.0:
			for q in poly:
				if q.distance_to(p) < r:
					return true
	return false


func _trees_near(p: Vector2, r: float) -> int:
	if world.trees == null:
		return 0
	return world.trees.ids_near(Vector3(p.x, 0, p.y), r).size()


## Spirála bodů na mřížce `step` od středu ven (deterministické pořadí: vzdálenost, pak úhel).
func _spiral(c: Vector3, r0: float, r1: float, step: float) -> Array:
	var pts := []
	var n := int(r1 / step)
	for ix in range(-n, n + 1):
		for iz in range(-n, n + 1):
			var p := Vector2(c.x + ix * step, c.z + iz * step)
			var d := p.distance_to(Vector2(c.x, c.z))
			if d >= r0 and d <= r1 and world.terrain.contains(p.x, p.y, 50.0):
				pts.append([d + atan2(iz, ix) * 0.001, p])
	pts.sort_custom(func(a, b): return a[0] < b[0])
	return pts.map(func(e): return e[1])


func _best_dir(p: Vector2, score: Callable) -> Vector2:
	var best := Vector2(1, 0)
	var best_s := -INF
	for k in 8:
		var a := k * TAU / 8.0
		var d := Vector2(cos(a), sin(a))
		var s: float = score.call(d)
		if s > best_s:
			best_s = s
			best = d
	return best


## Pole: nejbližší bod orné půdy (Fields.class_at == 1) s obilninou letošního roku (`Fields.crop_at` ∈ CEREALS –
## jen tam rostou 3D klasy CROP_WHEAT, tools/vegetation.py) 200–1200 m od středu bez budov a stromů v okolí.
## Směr = kam je nejdál stejné obilné pole (ne přes louku / trávník); kamera v očích (EYE), mírně dolů (FIELD_PITCH).
## Bez obilného pole libovolná orná půda, bez landuse.bin otevřená plocha (bez budov do 80 m a stromů do 40 m).
func _field_place(c: Vector3) -> Dictionary:
	var f: Fields = world.fields
	var has_f := f != null and f.loaded
	var year: int = world.clock.year() if world.clock else BASE_DATE[0]
	var res := {}
	if has_f:
		res = _field_search(c, true, year)
		if res.is_empty():
			res = _field_search(c, false, year)
	else:
		res = _field_search(c, false, year)
	return res if not res.is_empty() else _fallback(c, "pole nenalezeno")


func _field_search(c: Vector3, cereal: bool, year: int) -> Dictionary:
	var f: Fields = world.fields
	var has_f := f != null and f.loaded
	for p: Vector2 in _spiral(c, 200.0, 1200.0, 40.0):
		var fid := 0
		if has_f:
			if f.class_at(p.x, p.y) != 1:
				continue
			fid = f.field_at(p.x, p.y)
			if cereal and (fid <= 0 or not (f.crop_at(p.x, p.y, year) in CEREALS)):
				continue
		if _building_near(p, 80.0) or _trees_near(p, 30.0 if has_f else 40.0) > 0:
			continue
		var score := _field_score.bind(p, has_f, fid if cereal else -1)
		var dir := _best_dir(p, score)
		if cereal and float(score.call(dir)) < 6.0:
			continue                                    # obilí jen kousek před kamerou – hledat dál
		var pos := Vector3(p.x, _h(p.x, p.y) + EYE, p.y)
		var la := p + dir * 60.0
		var look := Vector3(la.x, pos.y - 60.0 * tan(deg_to_rad(FIELD_PITCH)), la.y)   # sklon od očí, ne od terénu
		var why := "orná půda (landuse.bin)" if has_f else "otevřená plocha (bez landuse.bin)"
		if cereal:
			why = "pole s obilninou (%s, pole %d, rok %d – Fields.crop_at), pohled přes pole %.0f° dolů" % [
				f.crop_at(p.x, p.y, year), fid, year, FIELD_PITCH]
		return {"pos": pos, "look": look, "why": why}
	return {}


## Kolik vzorků po 20 m ve směru `d` od `p` leží na poli (`fid` ≥ 0: na tomtéž poli; bez landuse.bin: bez stromů).
func _field_score(d: Vector2, p: Vector2, has_f: bool, fid := -1) -> float:
	var s := 0.0
	for i in range(1, 10):
		var q := p + d * (i * 20.0)
		if has_f:
			if world.fields.class_at(q.x, q.y) != 1 or (fid >= 0 and world.fields.field_at(q.x, q.y) != fid):
				break                                   # za okrajem pole už se nepočítá
			s += 1.0
		elif _trees_near(q, 10.0) == 0:
			s += 1.0
	return s


func _forest_score(d: Vector2, p: Vector2) -> float:
	return float(_trees_near(p + d * 60.0, 30.0))


## Okraj lesa z mapy povrchu (SurfaceMap.class_at == FOREST): soustředné kružnice od středu vsi (krok 8 m),
## první buňka lesa, za kterou (proti směru `d`) je souvislý les (40 m) s ≥ EDGE_TREES_MIN stromy (TreeManager)
## a před ní ve směru `d` 6–48 m otevřená plocha (tráva, orná půda, sad, polní cesta – ne dvůr ani budovy).
## Kamera EDGE_CAM_M před okrajem v otevřené ploše, kouká na les. Bez surface.bin podle hustoty stromů (`_forest_edge_by_trees`).
func _forest_edge_place(c: Vector3) -> Dictionary:
	var sm: SurfaceMap = world.surface
	if sm == null or not sm.loaded:
		return _forest_edge_by_trees(c)
	var r := 150.0
	while r <= 2500.0:
		var n := maxi(int(TAU * r / 8.0), 16)
		for k in n:
			var a := TAU * k / n
			var p := Vector2(c.x + cos(a) * r, c.z + sin(a) * r)
			if sm.class_at(p.x, p.y) != SurfaceMap.FOREST or not world.terrain.contains(p.x, p.y, 80.0):
				continue
			var res := _forest_edge_at(p, sm)
			if not res.is_empty():
				res["why"] = "%s, %.0f m od středu vsi" % [res["why"], r]
				return res
		r += 8.0
	return _forest_edge_by_trees(c)


## Je les v bodě `p` okrajem (viz `_forest_edge_place`)? Vrací místo pohledu nebo {}.
func _forest_edge_at(p: Vector2, sm: SurfaceMap) -> Dictionary:
	for k in 16:
		var a := k * TAU / 16.0
		var d := Vector2(cos(a), sin(a))
		var ok := true
		for i in range(2, 17):                          # 6–48 m před okrajem: otevřená plocha
			var q := p + d * (i * 3.0)
			if not (sm.class_at(q.x, q.y) in EDGE_OPEN):
				ok = false
				break
		if not ok:
			continue
		for i in 9:                                     # 0–40 m za okrajem: les
			var q2 := p - d * (i * 5.0)
			if sm.class_at(q2.x, q2.y) != SurfaceMap.FOREST:
				ok = false
				break
		if not ok:
			continue
		var nf := _trees_near(p - d * 25.0, 25.0)
		var cp := p + d * EDGE_CAM_M
		if nf < EDGE_TREES_MIN or _trees_near(cp, 10.0) > 0 or _building_near(cp, 40.0):
			continue
		var pos := Vector3(cp.x, _h(cp.x, cp.y) + EYE, cp.y)
		var la := p - d * 20.0
		return {"pos": pos, "look": Vector3(la.x, _h(la.x, la.y) + 4.0, la.y),
			"why": "okraj lesa (surface.bin FOREST vedle otevřené plochy, %d stromů do 25 m za okrajem), kamera %.0f m před ním" % [
				nf, EDGE_CAM_M]}
	return {}


## Okraj lesa bez surface.bin: nejbližší místo bez stromů do 25 m, za kterým (60 m) je hustý les (≥ 12 stromů do 30 m).
func _forest_edge_by_trees(c: Vector3) -> Dictionary:
	var best_p := Vector2.INF
	var best_dir := Vector2.ZERO
	var best_n := 0
	for p: Vector2 in _spiral(c, 150.0, 1500.0, 40.0):
		if _trees_near(p, 25.0) > 0:
			continue
		var dir := _best_dir(p, _forest_score.bind(p))
		var n := _trees_near(p + dir * 60.0, 30.0)
		if n > best_n and not _building_near(p, 40.0):
			best_n = n
			best_p = p
			best_dir = dir
		if best_n >= 12:
			break
	if best_n >= 4:
		var p := best_p
		var dir := best_dir
		var cp := p - dir * 15.0
		var pos := Vector3(cp.x, _h(cp.x, cp.y) + EYE, cp.y)
		var la := p + dir * 60.0
		return {"pos": pos, "look": Vector3(la.x, _h(la.x, la.y) + 6.0, la.y),
			"why": "bez stromů do 25 m, nejhustší les 60 m směrem pohledu (%d stromů do 30 m; TreeManager.ids_near)" % best_n}
	return _fallback(c, "okraj lesa nenalezen")


## Vyhlídka: nejvyšší bod terénu (mřížka 25 m) do 1500 m od středu; kouká na střed vsi.
func _hill_place(c: Vector3) -> Dictionary:
	var best := Vector2(c.x, c.z)
	var best_h := -INF
	for p: Vector2 in _spiral(c, 100.0, 1500.0, 25.0):
		var hh := _h(p.x, p.y)
		if hh > best_h + 0.01:
			best_h = hh
			best = p
	# kamera kousek pod vrcholem směrem ke vsi (vrchol zakrytý stromy by nebyl vidět)
	var to_c := (Vector2(c.x, c.z) - best).normalized()
	var cp := best + to_c * 10.0
	var pos := Vector3(cp.x, maxf(_h(cp.x, cp.y), best_h) + EYE + 1.0, cp.y)
	return {"pos": pos, "look": Vector3(c.x, c.y + 5.0, c.z),
		"why": "nejvyšší bod terénu do 1,5 km (%.1f m n. terénu vsi %+.1f m)" % [best_h, best_h - c.y]}


func _fallback(c: Vector3, why: String) -> Dictionary:
	var p := Vector3(c.x + 60.0, 0, c.z + 60.0)
	p.y = _h(p.x, p.z) + EYE
	return {"pos": p, "look": c, "why": why + " – náhradní místo 85 m od středu"}


func _places_json() -> Dictionary:
	var d := {}
	for k in places:
		var p: Vector3 = places[k]["pos"]
		var l: Vector3 = places[k]["look"]
		d[k] = {"pos": _v(p), "look": _v(l), "why": places[k]["why"]}
	return d


static func _v(p: Vector3) -> Array:
	return [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)]


# ------------------------------------------------------------------ snímek

## Postava hráče stojí pod kamerou (streaming) – její geometrie na vrstvu, kterou kamera nekreslí
## (spolehlivější než `visible`, které si hráč přepíná sám, a i pro díly přestavěné oblečením).
func _hide_player(pl: Player) -> void:
	var stack: Array = [pl]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is VisualInstance3D:
			(n as VisualInstance3D).layers = HIDE_LAYER
		for c in n.get_children():
			if not (c is Camera3D):
				stack.append(c)


func _shoot(name_: String, place: Dictionary, hour: float, weather: String, winter: bool) -> Dictionary:
	var changed := false
	if winter and _cur["date"] != "%04d-%02d-%02d" % WINTER_DATE:
		world.set_date(WINTER_DATE[0], WINTER_DATE[1], WINTER_DATE[2])
		_cur["date"] = "%04d-%02d-%02d" % WINTER_DATE
		_cur["weather"] = ""
		changed = true
	if absf(world.clock.hour() - hour) > 0.01:
		world.set_time(hour)
		changed = true
	if _cur["weather"] != weather:
		world.set_weather(weather)
		_cur["weather"] = weather
		changed = true
	_cur["time"] = hour
	var pos: Vector3 = place["pos"]
	var look: Vector3 = place["look"]
	# hráč pod kameru (streaming vegetace, interiérů a LOD kolem hráče), postava skrytá
	var pl := client.player
	if pl:
		var gy := _h(pos.x, pos.z)
		pl.global_position = Vector3(pos.x, gy + 0.2, pos.z)
		pl.velocity = Vector3.ZERO
		_hide_player(pl)
	cam.look_at_from_position(pos, look, Vector3.UP)
	cam.current = true
	if changed and client.atmosphere:
		# adaptace expozice (oka) je pomalá – po skoku času / počasí ji srovnat hned (jinak závisí na pořadí pohledů)
		client.atmosphere.update(1000.0)
	var t0 := Time.get_ticks_msec()
	var wait_s := SETTLE_S + (SETTLE_CHANGE_S if changed else 0.0)
	var frames := 0
	while frames < MIN_FRAMES or Time.get_ticks_msec() - t0 < int(wait_s * 1000.0):
		await tree.process_frame
		frames += 1
		if pl:
			pl.velocity = Vector3.ZERO
	await RenderingServer.frame_post_draw
	var img := tree.root.get_texture().get_image()
	var png := "views/%s.png" % name_
	img.save_png(out_dir.path_join(png))
	var e := cam.global_transform.basis.get_euler()
	return {"name": name_, "png": png, "pos": _v(pos), "look_at": _v(look),
		"yaw": snappedf(rad_to_deg(e.y), 0.1), "pitch": snappedf(rad_to_deg(e.x), 0.1), "fov": FOV,
		"time": "%02d:%02d" % [int(hour), int(round(fmod(hour, 1.0) * 60.0))], "weather": weather,
		"weather_now": world.weather.kind if world.weather else "",
		"snow_cover": snappedf(world.weather.snow_cover, 0.01) if world.weather else 0.0,
		"date": "%04d-%02d-%02d" % [world.clock.date()["year"], world.clock.date()["month"], world.clock.date()["day"]],
		"why": place["why"], "frames": frames, "fps": Engine.get_frames_per_second(),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)}
