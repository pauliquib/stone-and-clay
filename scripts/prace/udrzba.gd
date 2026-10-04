## Obecní údržba (M3.2) – pracoviště práce „Obecní údržba“ (`data/prace.json` → `obec_udrzba`, zaměstnavatel obecní úřad).
## Jeden uzel ve `World` (`World.udrzba`), vzniká v `World.add_player`. Úkoly podle sezóny a počasí (podmínky `mesice`,
## `snih_min` / `snih_max` v katalogu; cíle dodávají poskytovatelé `Jobs.set_provider`):
## - **Tráva** (`udrzba_trava`, akce `posekat` kosou): zóny u hřiště (za hospodou U Hřiště) a na návsi (u úřadu), dlaždice
##   `TILE` m; posekaná dlaždice je `REGROW_DAYS` dní kratší a světlejší (plocha nad terénem – jen vzhled zóny).
## - **Odpadky** (`udrzba_odpadky`, akce `sebrat_odpadek`): `LITTER_MIN`–`LITTER_MAX` kusů u silnic do `LITTER_R` m od úřadu,
##   rozhodí se, když úkol přijde na řadu a včerejší jsou sebrané; kompas ukazuje nejbližší (`Jobs.target`).
## - **Lavička** (`udrzba_lavicka`, akce `opravit_lavicku` kladivem, Kutilství): obecní lavička na návsi; když přijde úkol na
##   řadu a od opravy uběhlo `BENCH_DAYS`, někdo z ní ulomil prkno (prkno leží vedle).
## - **Listí** (`udrzba_listi`, akce `shrabat_listi` hráběmi, IX–XI): hromádky listí na návsi, po shrabání napadá za `LEAF_DAYS`.
## - **Sníh** (`udrzba_snih`, akce `odklidit_snih` lopatou) na chodníku před úřadem, Potravinami a u zastávky; odklizený kus
##   zůstane tmavý (plocha nad sněhem), dokud nenapadne `NEW_SNOW` nového sněhu. **Posyp** (`udrzba_posyp`, akce `posypat`,
##   písek zapůjčený na směnu) jen na odklizené kusy.
## - **Dobrovolně** (i bez zaměstnání): odklizený sníh u sousedů / na chodníku dá respekt sousedů a karmu (nejvýš
##   `VOLUNTEER_MAX` za den) a událost `snow_volunteer` (hák M4.5).
## Ukládání `to_dict` / `restore` (klíč `udrzba` v `SaveGame`; starý save = vše neposekané, bez odpadků).
class_name ObecniUdrzba
extends Node3D

const TILE := 3.0                    # m – dlaždice trávy a listí
const SNOW_TILE := 2.0               # m – kus chodníku
const GRASS_ZONES := [["hriste", "hospoda", Vector2i(3, 2), 5101], ["naves", "urad", Vector2i(3, 2), 5102]]
const LEAF_ZONE := ["naves_listi", "urad", Vector2i(2, 2), 5103]
const LEAF_MONTHS := [9, 10, 11]
const REGROW_DAYS := 7               # posekaná tráva doroste
const LEAF_DAYS := 3                 # listí znovu napadá
const BENCH_DAYS := 3                # lavička se může znovu rozbít (vandal) nejdřív po tolika dnech
const LITTER_MIN := 8
const LITTER_MAX := 15
const LITTER_R := 320.0
const SNOW_MIN := 0.1                # od kolika `snow_cover` je co odklízet
const NEW_SNOW := 0.12               # nový sníh na odklizený kus → zase zasněžený
const VOLUNTEER_RESPECT := 0.5       # respekt sousedů za dobrovolně odklizený kus
const VOLUNTEER_KARMA := 0.3
const VOLUNTEER_MAX := 4             # odměněných kusů za den
const TICK_S := 2.0
const COL_MOWN := Color(0.56, 0.7, 0.3)
const COL_LEAVES := Color(0.62, 0.36, 0.12)
const COL_CLEARED := Color(0.3, 0.29, 0.28)
const COL_SAND := Color(0.52, 0.42, 0.3)
const LITTER_COLORS := [Color(0.85, 0.1, 0.1), Color(0.2, 0.45, 0.85), Color(0.92, 0.92, 0.9), Color(0.25, 0.6, 0.25)]

var world: World
var zones: Array = []                # {id, kind: trava/listi/snih, title, tiles: [{pos, key, mi, mi2, m, r, c, s, f}]}
var bench: Prop
var bench_plank: MeshInstance3D
var bench_broken := false
var bench_rep_jd := -999
var litter: Array = []               # {pos, node}
var litter_jd := -1
var _vol := {}                       # "pid:jd" → počet odměněných kusů
var _vol_targets := {}               # klíč dlaždice → cíl (sníh pro kohokoli)
var _last_snow := 0.0
var _t := 0.0


func setup(w: World) -> void:
	world = w
	name = "Obecni_udrzba"
	for z in GRASS_ZONES:
		_make_ground_zone(String(z[0]), "trava", String(z[1]), z[2], int(z[3]),
			"tráva u hřiště" if z[0] == "hriste" else "tráva na návsi", COL_MOWN)
	_make_ground_zone(String(LEAF_ZONE[0]), "listi", String(LEAF_ZONE[1]), LEAF_ZONE[2], int(LEAF_ZONE[3]), "listí na návsi", COL_LEAVES)
	for k in ["urad", "obchod"]:
		var pl: Place = w.places.get(k)
		if pl:
			var face := float(pl.data.get("face_yaw", 0.0))
			_make_snow_zone("snih_" + k, "chodník před: %s" % pl.data.get("name", k), pl.door, face, 2.4)
	var stop := _bus_stop()
	if not stop.is_empty():
		_make_snow_zone("snih_zastavka", "chodník u zastávky", stop[0], float(stop[1]), 1.6)
	_make_bench()
	_last_snow = w.weather.snow_cover if w.weather else 0.0
	_register()
	_refresh()


# ------------------------------------------------------------------ zóny

func _make_ground_zone(id: String, kind: String, place_key: String, grid: Vector2i, seed_: int, title: String, col: Color) -> void:
	var pl: Place = world.places.get(place_key)
	if pl == null:
		return
	var size := Vector3(grid.x * TILE, 1.2, grid.y * TILE)
	var sp: Array = world._ground_spot(pl.door, Vector2(pl.door.x, pl.door.z), seed_, size, 10.0, 4.0)
	if sp.is_empty():
		push_warning("Obecní údržba: zóna %s se nevešla." % id)
		return
	var c: Vector3 = sp[0]
	var yaw := float(sp[1])
	var b := Basis(Vector3.UP, yaw)
	var tiles := []
	for ix in grid.x:
		for iz in grid.y:
			var p := c + b * Vector3((ix - (grid.x - 1) * 0.5) * TILE, 0, (iz - (grid.y - 1) * 0.5) * TILE)
			p.y = world.terrain.height_at(p.x, p.z)
			var t := {"pos": p, "key": "%s:%d:%d" % [id, ix, iz], "m": -999, "r": -999, "c": false, "s": false, "f": 0.0}
			t["mi"] = _patch(p, Vector2(TILE, TILE), yaw, col, kind == "listi")
			tiles.append(t)
	zones.append({"id": id, "kind": kind, "title": title, "tiles": tiles})


func _make_snow_zone(id: String, title: String, door: Vector3, face: float, out: float) -> void:
	var n := Vector3(sin(face), 0, cos(face))
	var along := Vector3(n.z, 0, -n.x)
	var tiles := []
	for i in 3:
		var p := door + n * out + along * ((i - 1) * SNOW_TILE)
		p.y = world.terrain.height_at(p.x, p.z)
		var t := {"pos": p, "key": "%s:%d" % [id, i], "m": -999, "r": -999, "c": false, "s": false, "f": 0.0}
		t["mi"] = _patch(p, Vector2(SNOW_TILE, SNOW_TILE * 0.9), face, COL_CLEARED, false)
		t["mi2"] = _patch(p + Vector3(0, 0.01, 0), Vector2(SNOW_TILE * 0.9, SNOW_TILE * 0.8), face, COL_SAND, true)
		tiles.append(t)
	zones.append({"id": id, "kind": "snih", "title": title, "tiles": tiles})


## Zastávka (smyšlená, bez značky dopravce): krajnice silnice ~120 m od úřadu směrem k Potravinám. [pozice, face] nebo [].
func _bus_stop() -> Array:
	var urad: Place = world.places.get("urad")
	var obchod: Place = world.places.get("obchod")
	if urad == null or world.graph == null:
		return []
	var u := Vector2(urad.door.x, urad.door.z)
	var o := Vector2(obchod.door.x, obchod.door.z) if obchod else u + Vector2(100, 0)
	var best := -1
	var bd := INF
	for i in world.graph.nodes_within(u, 260.0, ["secondary", "tertiary", "unclassified", "residential"]):
		var p: Vector2 = world.graph.nodes[i]
		if (world.graph.adj[i] as Array).size() != 2 or p.distance_to(u) < 60.0 or p.distance_to(o) < 40.0:
			continue
		var score := absf(p.distance_to(u) - 120.0) + p.distance_to(o) * 0.3
		if score < bd:
			bd = score
			best = i
	if best < 0:
		return []
	var p0: Vector2 = world.graph.nodes[best]
	var nb: Vector2 = world.graph.nodes[int(world.graph.adj[best][0])]
	var dir := (nb - p0).normalized()
	var side := Vector2(-dir.y, dir.x)
	var sp := p0 + side * 5.0
	var pos := Vector3(sp.x, world.terrain.height_at(sp.x, sp.y), sp.y)
	var face := atan2(-side.x, -side.y)          # čelem k silnici
	# sloupek s cedulí „ZASTÁVKA“ a lavička (obecný vzhled)
	var root := Node3D.new()
	root.name = "Zastavka"
	root.position = pos + Vector3(0, 0, 0) + Vector3(side.x, 0, side.y) * 1.2
	root.rotation.y = face
	add_child(root)
	var k := MeshKit.new()
	k.cylinder(Vector3(0, 1.3, 0), 0.04, 0.04, 2.6, Color(0.55, 0.56, 0.58), Vector3.ZERO, 8)
	k.box(Vector3(0, 2.45, 0), Vector3(0.55, 0.4, 0.04), Color(0.95, 0.8, 0.15))
	MeshKit.mesh_instance(root, k.commit(MeshKit.vc_material(0.6)), 200.0)
	for s in [0.025, -0.025]:
		var l := Label3D.new()
		l.text = "ZASTÁVKA"
		l.font_size = 48
		l.pixel_size = 0.004
		l.modulate = Color(0.1, 0.1, 0.1)
		l.outline_size = 0
		l.position = Vector3(0, 2.45, s)
		l.rotation.y = 0.0 if s > 0.0 else PI
		l.double_sided = false
		l.visibility_range_end = 60.0
		root.add_child(l)
	return [pos, face]


func _make_bench() -> void:
	var urad: Place = world.places.get("urad")
	if urad == null:
		return
	var sp: Array = world._ground_spot(urad.door, Vector2(urad.door.x, urad.door.z), 5104, Vector3(1.8, 1.0, 0.8), 6.0, 3.5)
	if sp.is_empty():
		return
	var pos: Vector3 = sp[0]
	bench = Prop.make("lavicka", pos + Vector3(0, 0.02, 0), float(sp[1]))
	bench.name = "Obecni_lavicka"
	add_child(bench)
	var k := MeshKit.new()
	k.box(Vector3.ZERO, Vector3(1.5, 0.04, 0.14), Color(0.5, 0.33, 0.18), Vector3(0, 0, 0.12))
	bench_plank = MeshKit.mesh_instance(self, k.commit(MeshKit.vc_material(0.9)), 80.0)
	bench_plank.position = pos + Basis(Vector3.UP, float(sp[1])) * Vector3(0.2, 0.05, 0.75)
	bench_plank.rotation.y = float(sp[1]) + 0.3
	bench_plank.visible = false


## Plocha 1 × `size` m po terénu (mřížka 4 × 4), barvy z vrcholů, bez stínů; `spots` = skvrny (listí, písek).
func _patch(center: Vector3, size: Vector2, yaw: float, col: Color, spots: bool) -> MeshInstance3D:
	var k := MeshKit.new()
	var b := Basis(Vector3.UP, yaw)
	var n := 4
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(center)
	for i in n + 1:
		for j in n + 1:
			var lp := Vector3((float(i) / n - 0.5) * size.x, 0, (float(j) / n - 0.5) * size.y)
			var wp := center + b * lp
			k.verts.append(Vector3(wp.x - center.x, world.terrain.height_at(wp.x, wp.z) - center.y + 0.05, wp.z - center.z))
			k.norms.append(Vector3.UP)
			var c := col
			if spots:
				c = col.darkened(rng.randf_range(0.0, 0.3)) if rng.randf() < 0.7 else col.lightened(0.15)
			k.cols.append(c)
	for i in n:
		for j in n:
			var a := i * (n + 1) + j
			k.idx.append_array([a, a + 1, a + n + 1, a + 1, a + n + 2, a + n + 1])
	var mi := MeshKit.mesh_instance(self, k.commit(MeshKit.vc_material(0.95, 0.0, 0.0, false)), 150.0)
	mi.position = center
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	return mi


# ------------------------------------------------------------------ napojení na práci

func _register() -> void:
	Jobs.set_provider("udrzba_trava", func(_w: World, _id: int, _j: Dictionary) -> Array: return _todo("trava"))
	Jobs.set_provider("udrzba_listi", func(_w: World, _id: int, _j: Dictionary) -> Array: return _todo("listi"))
	Jobs.set_provider("udrzba_snih", func(_w: World, _id: int, _j: Dictionary) -> Array: return _todo("snih"))
	Jobs.set_provider("udrzba_posyp", func(_w: World, _id: int, _j: Dictionary) -> Array: return _todo("posyp"))
	Jobs.set_provider("udrzba_lavicka", func(_w: World, _id: int, _j: Dictionary) -> Array: return _bench_points())
	Jobs.set_provider("udrzba_odpadky", func(_w: World, _id: int, _j: Dictionary) -> Array: return _litter_points())
	Actions.set_handler("posekat", func(id: int, _d: Dictionary, aim: Dictionary, ok: bool) -> void: _on_tile(id, "trava", aim, ok))
	Actions.set_handler("shrabat_listi", func(id: int, _d: Dictionary, aim: Dictionary, ok: bool) -> void: _on_tile(id, "listi", aim, ok))
	Actions.set_handler("odklidit_snih", func(id: int, _d: Dictionary, aim: Dictionary, ok: bool) -> void: _on_tile(id, "snih", aim, ok))
	Actions.set_handler("posypat", func(id: int, _d: Dictionary, aim: Dictionary, ok: bool) -> void: _on_tile(id, "posyp", aim, ok))
	Actions.set_handler("opravit_lavicku", _on_bench)
	Actions.set_handler("sebrat_odpadek", _on_litter)
	Actions.set_target_check("posypat", func(aim: Dictionary, id: int) -> String:
		var why := Jobs.own_target(aim, id)
		var p: Player = world.players.get(id)
		if why == "" and p and p.item_count("pisek") <= 0:
			why = "Došel ti písek – vezmi si další na úřadě (nový úkol)."
		return why)


func _today() -> int:
	return world.clock.jd() if world.clock else 0


func _snow() -> float:
	return world.weather.snow_cover if world.weather else 0.0


## Body dlaždic, na kterých je co dělat (výška +0,3 m kvůli zaměřování).
func _todo(what: String) -> Array:
	var out := []
	var jd := _today()
	var snow := _snow()
	for z in zones:
		var kind := String(z["kind"])
		for t in z["tiles"]:
			var need := false
			match what:
				"trava":
					need = kind == "trava" and jd - int(t["m"]) >= REGROW_DAYS and snow < 0.05
				"listi":
					need = kind == "listi" and _leaf_season() and jd - int(t["r"]) >= LEAF_DAYS and snow < 0.05
				"snih":
					need = kind == "snih" and snow >= SNOW_MIN and not bool(t["c"])
				"posyp":
					need = kind == "snih" and snow >= SNOW_MIN and bool(t["c"]) and not bool(t["s"])
			if need:
				out.append((t["pos"] as Vector3) + Vector3(0, 0.3, 0))
	return out


func _leaf_season() -> bool:
	return world.clock != null and world.clock.month() in LEAF_MONTHS


## Dlaždice druhu `kind` nejblíž bodu (do `r` m) nebo {}.
func _tile_at(kind: String, pos: Vector3, r: float) -> Dictionary:
	var best := {}
	var bd := r
	for z in zones:
		if String(z["kind"]) != kind:
			continue
		for t in z["tiles"]:
			var d := (t["pos"] as Vector3).distance_to(pos)
			if d <= bd:
				bd = d
				best = t
	return best


func _on_tile(id: int, what: String, aim: Dictionary, ok: bool) -> void:
	if not ok:
		return
	var pos: Vector3 = aim.get("pos", Vector3.INF)
	var kind := "snih" if what == "posyp" else what
	var t := _tile_at(kind, pos - Vector3(0, 0.3, 0), TILE)
	if t.is_empty():
		return
	match what:
		"trava":
			t["m"] = _today()
		"listi":
			t["r"] = _today()
		"snih":
			t["c"] = true
			t["s"] = false
			t["f"] = 0.0
			_volunteer(id)
		"posyp":
			var p: Player = world.players.get(id)
			var jb: Jobs = world.jobs.get(id)
			if p and p.remove_item("pisek", 1) and jb:
				jb.unlend("pisek", 1)
			t["s"] = true
	_refresh()


## Dobrovolné odklízení sněhu mimo směnu obecní údržby (hák M4.5: respekt, karma).
func _volunteer(id: int) -> void:
	var jb: Jobs = world.jobs.get(id)
	if jb and jb.on_shift("obec_udrzba"):
		return
	var key := "%d:%d" % [id, _today()]
	var n := int(_vol.get(key, 0))
	world.give_xp(id, "kondice", 3.0, "odklízení sněhu")
	world.emit_game_event(id, "snow_volunteer", {"count": n + 1})
	if n >= VOLUNTEER_MAX:
		return
	_vol[key] = n + 1
	var rep: Reputation = world.reputations.get(id)
	if rep:
		rep.change_respect("sousede", VOLUNTEER_RESPECT, "odklizený sníh na chodníku")
		rep.change_karma(VOLUNTEER_KARMA, "pomoc sousedům – sníh")
	if n == 0:
		world.notify(id, "show_message", ["Sousedé si všimli, že jsi jim odházel chodník. (respekt sousedů +)", 3.0])


# ------------------------------------------------------------------ lavička a odpadky

## Lavička: když přijde úkol na řadu a od opravy uběhlo `BENCH_DAYS`, je rozbitá (ulomené prkno).
func _bench_points() -> Array:
	if bench == null or not is_instance_valid(bench):
		return []
	if not bench_broken and _today() - bench_rep_jd >= BENCH_DAYS:
		bench_broken = true
		_refresh()
	return [bench.global_position + Vector3(0, 0.5, 0)] if bench_broken else []


func _on_bench(id: int, _def: Dictionary, _aim: Dictionary, ok: bool) -> void:
	if not ok:
		return
	bench_broken = false
	bench_rep_jd = _today()
	world.notify(id, "show_message", ["Lavička je zase jako nová – prkno přitlučené.", 2.5])
	_refresh()


func _litter_points() -> Array:
	if litter.is_empty() and litter_jd != _today():
		_spawn_litter(_today())
	var out := []
	for l in litter:
		out.append((l["pos"] as Vector3) + Vector3(0, 0.15, 0))
	return out


## Rozhodí odpadky u silnic kolem úřadu (seed = den – stejné pro stejný den).
func _spawn_litter(jd: int, saved: Array = []) -> void:
	_clear_litter()
	litter_jd = jd
	var urad: Place = world.places.get("urad")
	if urad == null or world.graph == null:
		return
	var pts := []
	if saved.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = jd * 7919 + 17
		var cand := world.graph.nodes_within(Vector2(urad.door.x, urad.door.z), LITTER_R, ["residential", "tertiary", "unclassified", "service"])
		if cand.is_empty():
			return
		var n := rng.randi_range(LITTER_MIN, LITTER_MAX)
		for i in n * 3:
			if pts.size() >= n:
				break
			var ni: int = cand[rng.randi() % cand.size()]
			var nb: Array = world.graph.adj[ni]
			if nb.is_empty():
				continue
			var dir: Vector2 = (world.graph.nodes[int(nb[0])] - world.graph.nodes[ni]).normalized()
			var side := 1.0 if rng.randf() < 0.5 else -1.0
			var p2: Vector2 = world.graph.nodes[ni] + Vector2(-dir.y, dir.x) * side * rng.randf_range(2.6, 4.0)
			var ok := true
			for q in pts:
				if Vector2((q as Array)[0], (q as Array)[1]).distance_to(p2) < 12.0:
					ok = false
					break
			if ok:
				pts.append([p2.x, p2.y, rng.randi() % 3])
	else:
		pts = saved
	for q in pts:
		var x := float(q[0])
		var z := float(q[1])
		var pos := Vector3(x, world.terrain.height_at(x, z), z)
		litter.append({"pos": pos, "node": _litter_model(pos, int(q[2]) if (q as Array).size() > 2 else 0), "kind": int(q[2]) if (q as Array).size() > 2 else 0})


func _litter_model(pos: Vector3, kind: int) -> MeshInstance3D:
	var k := MeshKit.new()
	var col: Color = LITTER_COLORS[int(abs(hash(pos))) % LITTER_COLORS.size()]
	match kind:
		0:   # plechovka na boku
			k.cylinder(Vector3(0, 0.035, 0), 0.033, 0.033, 0.12, col, Vector3(0, 0, PI * 0.5), 10)
		1:   # zmačkaný sáček
			k.sphere(Vector3(0, 0.06, 0), 0.09, col.lightened(0.3), Vector3(1.2, 0.6, 1.0))
		_:   # PET lahev
			k.cylinder(Vector3(0, 0.04, 0), 0.04, 0.04, 0.24, Color(0.75, 0.88, 0.95), Vector3(0, 0, PI * 0.5), 10)
			k.cylinder(Vector3(0.14, 0.04, 0), 0.016, 0.016, 0.04, col, Vector3(0, 0, PI * 0.5), 8)
	var mi := MeshKit.mesh_instance(self, k.commit(MeshKit.vc_material(0.5)), 90.0)
	mi.position = pos
	mi.rotation.y = randf() * TAU
	return mi


func _clear_litter() -> void:
	for l in litter:
		if is_instance_valid(l["node"]):
			(l["node"] as Node).queue_free()
	litter.clear()


func _on_litter(id: int, _def: Dictionary, aim: Dictionary, ok: bool) -> void:
	if not ok:
		return
	var pos: Vector3 = aim.get("pos", Vector3.INF)
	var best := -1
	var bd := 1.5
	for i in litter.size():
		var d := (litter[i]["pos"] as Vector3).distance_to(pos - Vector3(0, 0.15, 0))
		if d < bd:
			bd = d
			best = i
	if best < 0:
		return
	if is_instance_valid(litter[best]["node"]):
		(litter[best]["node"] as Node).queue_free()
	litter.remove_at(best)
	world.notify(id, "show_message", ["Do pytle s ním. Zbývá %d." % litter.size() if not litter.is_empty() else "Všechny odpadky sebrané.", 2.0])


# ------------------------------------------------------------------ stav a vzhled

func _process(delta: float) -> void:
	if world == null:
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = TICK_S
	var snow := _snow()
	var d := snow - _last_snow
	_last_snow = snow
	var changed := false
	for z in zones:
		if String(z["kind"]) != "snih":
			continue
		for t in z["tiles"]:
			if not bool(t["c"]):
				continue
			if snow < 0.02:
				t["c"] = false             # roztálo – není co odklízet ani posypávat
				t["s"] = false
				t["f"] = 0.0
				changed = true
			elif d > 0.0:
				t["f"] = float(t["f"]) + d
				if float(t["f"]) >= NEW_SNOW:
					t["c"] = false         # napadl nový sníh
					t["s"] = false
					t["f"] = 0.0
					changed = true
	if changed:
		_refresh()
	else:
		_refresh_visual()


## Přepočítá vzhled a dobrovolnické cíle (sníh pro kohokoli).
func _refresh() -> void:
	_refresh_visual()
	var want := {}
	if _snow() >= SNOW_MIN:
		for z in zones:
			if String(z["kind"]) != "snih":
				continue
			for t in z["tiles"]:
				if not bool(t["c"]):
					want[String(t["key"])] = t
	for k in _vol_targets.keys():
		if not want.has(k):
			world.unregister_target(_vol_targets[k])
			_vol_targets.erase(k)
	for k in want:
		if not _vol_targets.has(k):
			var tg := {"pos": (want[k]["pos"] as Vector3) + Vector3(0, 0.3, 0), "r": SNOW_TILE, "kind": "snih", "data": {"tile": k}}
			_vol_targets[k] = tg
			world.register_target(tg)


func _refresh_visual() -> void:
	var jd := _today()
	var snow := _snow()
	for z in zones:
		var kind := String(z["kind"])
		for t in z["tiles"]:
			var mi: MeshInstance3D = t["mi"]
			match kind:
				"trava":
					mi.visible = jd - int(t["m"]) < REGROW_DAYS and snow < 0.2
				"listi":
					mi.visible = _leaf_season() and jd - int(t["r"]) >= LEAF_DAYS and snow < 0.2
				"snih":
					mi.visible = bool(t["c"]) and snow > 0.05
					(t["mi2"] as MeshInstance3D).visible = mi.visible and bool(t["s"])
	if bench_plank:
		bench_plank.visible = bench_broken


# ------------------------------------------------------------------ ukládání

func to_dict() -> Dictionary:
	var tiles := {}
	for z in zones:
		for t in z["tiles"]:
			tiles[String(t["key"])] = [int(t["m"]), int(t["r"]), bool(t["c"]), bool(t["s"]), snappedf(float(t["f"]), 0.001)]
	var lit := []
	for l in litter:
		var p: Vector3 = l["pos"]
		lit.append([snappedf(p.x, 0.01), snappedf(p.z, 0.01), int(l.get("kind", 0))])
	return {"tiles": tiles, "bench": [bench_broken, bench_rep_jd], "litter_jd": litter_jd, "litter": lit}


## Starý save bez klíče `udrzba` = vše neposekané, lavička celá, žádné odpadky.
func restore(d: Dictionary) -> void:
	var tiles: Dictionary = d.get("tiles", {})
	for z in zones:
		for t in z["tiles"]:
			var s: Array = tiles.get(String(t["key"]), [])
			if s.size() >= 5:
				t["m"] = int(s[0])
				t["r"] = int(s[1])
				t["c"] = bool(s[2])
				t["s"] = bool(s[3])
				t["f"] = float(s[4])
	var b: Array = d.get("bench", [false, -999])
	bench_broken = bool(b[0]) if b.size() > 0 else false
	bench_rep_jd = int(b[1]) if b.size() > 1 else -999
	var lit: Array = d.get("litter", [])
	if lit.is_empty():
		_clear_litter()
		litter_jd = int(d.get("litter_jd", -1))
	else:
		_spawn_litter(int(d.get("litter_jd", -1)), lit)
	_last_snow = _snow()
	_refresh()
