## Vizuální validátor Stone & Clay – enginová část (SceneTree skript). Spouští ho `tools/vizual/run.sh`:
##
##   tools/vizual/godot_xvfb.sh --path . --resolution 960x540 -s res://tools/vizual/validator.gd -- \
##       --out=/abs/cesta/vystupu [--quick] [--only=geom,gallery,views] [--radius=400] [--preset=nizka|stredni|vysoka|ultra]
##
## Vrstvy (`--only`, výchozí všechny; pořadí běhu je vždy gallery → geom → views):
##   gallery  galerie procedurálních modelů bez světa (`gallery.gd`) → gallery/*.png + gallery.json
##   geom     geometrické kontroly postaveného světa kolem spawnu (`world_checks.gd`) → geometry.json
##   views    standardní pohledy jedné hry (`views.gd`) → views/*.png + views.json
## `--quick`: galerie 5 modelů, 4 pohledy (ulice, náves, dron, noc); geometrie beze změny.
##
## Svět se staví jen jednou (geom i views ho sdílí) – stejně jako `scripts/main.gd` (World + LocalClient + hráč 1),
## jen s pevnými parametry: datum 2026-06-15, 11:00, jasno, hráč na spawnu z map.json. Parametr `vizualtest`
## (končí na „test“) přepne klienta do automatického režimu (`LocalClient.is_automated`: výchozí nastavení,
## žádné načtení `user://nastaveni.cfg`, žádná pauza při ztrátě fokusu; `GameSettings.realism_saved` = výchozí).
## HUD a nabídky (CanvasLayer pod klientem) jsou skryté.
##
## Výstup (`--out`, adresář se vytvoří): geometry.json {"findings": [...], "stats": {...}}, views.json, gallery.json,
## summary.json (stav vrstev, časy). Na konci `print("VIZUAL HOTOVO …")` a `quit(0)` – chyby jsou v JSON.
## Bez `data/terrain_height.bin` (svět nejde postavit) zapíše geometry.json / views.json s nálezem FAIL `world`.
## Hlídací časovač (`--timeout=s`, výchozí 1500 s) při zaseknutí zapíše, co má, a skončí.
extends SceneTree

const GeomChecks := preload("res://tools/vizual/geom_checks.gd")
const Gallery := preload("res://tools/vizual/gallery.gd")
const WorldChecks := preload("res://tools/vizual/world_checks.gd")
const Views := preload("res://tools/vizual/views.gd")

const LAYERS := ["gallery", "geom", "views"]
const WORLD_DATE := "2026-06-15"
const WORLD_TIME := "11"
const WORLD_WEATHER := "jasno"
const SETTLE_S := 8.0               # s po postavení světa (streaming vegetace, LOD stromů, interiéry kolem hráče)

var args := {}
var out_dir := ""
var only: Array = []
var quick := false
var summary := {"layers": {}, "started": "", "version": 1}
var main_node: Node3D
var world: World
var client: LocalClient
var _finished := false
var _t0 := 0


## `Main` bez vlastního `_ready` (svět staví validátor s pevnými parametry, ne z příkazové řádky).
class VizualMain extends Main:
	func _ready() -> void:
		pass


func _initialize() -> void:
	_t0 = Time.get_ticks_msec()
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	out_dir = String(args.get("out", "user://vizual"))
	if out_dir.begins_with("res://") or out_dir.begins_with("user://"):
		out_dir = ProjectSettings.globalize_path(out_dir)
	elif not out_dir.is_absolute_path():
		out_dir = ProjectSettings.globalize_path("res://").path_join(out_dir)
	DirAccess.make_dir_recursive_absolute(out_dir)
	quick = args.has("quick")
	only = LAYERS.duplicate()
	if args.has("only") and String(args["only"]) != "":
		only = []
		for s in String(args["only"]).split(",", false):
			var k := s.strip_edges()
			if k in LAYERS:
				only.append(k)
			else:
				push_warning("vizual: neznámá vrstva %s (známé: %s)" % [k, ", ".join(LAYERS)])
	summary["started"] = Time.get_datetime_string_from_system()
	summary["args"] = args
	summary["only"] = only
	summary["quick"] = quick
	var timeout := float(args.get("timeout", "1500"))
	var tm := create_timer(timeout, true, false, true)
	tm.timeout.connect(_on_timeout)
	print("VIZUAL start: out=%s only=%s quick=%s" % [out_dir, ",".join(only), quick])
	_run.call_deferred()


func _run() -> void:
	await process_frame
	if "gallery" in only:
		var t := Time.get_ticks_msec()
		var g := Gallery.new()
		var res: Dictionary = await g.run(self, out_dir, quick)
		summary["layers"]["gallery"] = {"ok": true, "ms": Time.get_ticks_msec() - t, "stats": res["stats"]}
	if "geom" in only or "views" in only:
		var t2 := Time.get_ticks_msec()
		var ok := await _build_world()
		summary["layers"]["world"] = {"ok": ok, "ms": Time.get_ticks_msec() - t2}
		if not ok:
			var msg := "svět nelze postavit: chybí data/terrain_height.bin (vygeneruj data/*.bin)"
			if "geom" in only:
				_write_json("geometry.json", {"findings": [GeomChecks.finding("FAIL", "world", "", msg)], "stats": {}})
			if "views" in only:
				_write_json("views.json", {"views": [], "stats": {"error": msg}})
		else:
			if "geom" in only:
				var t3 := Time.get_ticks_msec()
				var wc := WorldChecks.new()
				var sp: Dictionary = world.meta["spawn"]
				var c := Vector3(float(sp["x"]), 0.0, float(sp["z"]))
				c.y = world.terrain.height_at(c.x, c.z)
				var gres := wc.run(world, main_node, c, float(args.get("radius", "400")))
				gres["stats"]["svet_ms"] = summary["layers"]["world"]["ms"]
				_write_json("geometry.json", gres)
				summary["layers"]["geom"] = {"ok": true, "ms": Time.get_ticks_msec() - t3, "findings": gres["stats"]["nalezy"]}
			if "views" in only:
				var t4 := Time.get_ticks_msec()
				var v := Views.new()
				var vres: Dictionary = await v.run(self, world, client, out_dir, quick)
				summary["layers"]["views"] = {"ok": true, "ms": Time.get_ticks_msec() - t4, "count": (vres["views"] as Array).size()}
	_finish("ok")


## Postaví svět jako `Main._ready` (World, LocalClient, hráč 1 na spawnu z map.json) a počká na ustálení.
func _build_world() -> bool:
	if not FileAccess.file_exists("res://data/terrain_height.bin") or not FileAccess.file_exists("res://data/map.json"):
		return false
	var a := {"vizualtest": "", "time": WORLD_TIME, "date": WORLD_DATE, "weather": WORLD_WEATHER}
	if args.has("preset"):
		a["preset"] = args["preset"]
	main_node = VizualMain.new()
	main_node.name = "Main"
	(main_node as Main)._args = a
	root.add_child(main_node)
	current_scene = main_node           # LimboAI stromy vesničanů berou kořen scény z current_scene
	DevTune.ensure()
	world = World.new()
	world.name = "Svet"
	world.args = a
	main_node.add_child(world)
	(main_node as Main).world = world
	client = LocalClient.new()
	client.name = "Klient"
	client.world = world
	client.args = a
	main_node.add_child(client)
	(main_node as Main).client = client
	world.loading.connect(client.hud.set_loading)
	world.init_clock()
	client.build_environment()
	var t0 := Time.get_ticks_msec()
	await world.build()
	var sp: Dictionary = world.meta["spawn"]
	var x := float(sp["x"])
	var z := float(sp["z"])
	var pos := Vector3(x, world.terrain.height_at(x, z) + 0.2, z)
	var yaw := atan2(-(float(sp["look_x"]) - x), -(float(sp["look_z"]) - z))
	var p := world.add_player(Main.LOCAL_ID, pos, yaw)
	client.attach(p)
	world.start()
	client.hud.finish_loading()
	client.ready_done = true
	world.clock.paused = true
	print("VIZUAL svět postaven za %d ms" % (Time.get_ticks_msec() - t0))
	_hide_hud()
	# ustálení: fyzika aut a zvířat dosedne, streaming kolem hráče
	var t1 := Time.get_ticks_msec()
	var frames := 0
	while frames < 20 or Time.get_ticks_msec() - t1 < int(SETTLE_S * 1000.0):
		await process_frame
		frames += 1
	_hide_hud()
	return true


func _hide_hud() -> void:
	if client == null:
		return
	var stack: Array = [client]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is CanvasLayer:
			(n as CanvasLayer).visible = false
		for c in n.get_children():
			stack.append(c)


func _write_json(name_: String, d: Dictionary) -> void:
	var f := FileAccess.open(out_dir.path_join(name_), FileAccess.WRITE)
	if f == null:
		push_error("vizual: nelze zapsat %s" % out_dir.path_join(name_))
		return
	f.store_string(JSON.stringify(d, "  "))
	f.close()


func _on_timeout() -> void:
	if _finished:
		return
	push_warning("vizual: vypršel časový limit")
	if "geom" in only and not FileAccess.file_exists(out_dir.path_join("geometry.json")):
		_write_json("geometry.json", {"findings": [GeomChecks.finding("FAIL", "timeout", "",
			"validátor nedoběhl v časovém limitu (svět se nepostavil / zasekl)")], "stats": {}})
	_finish("timeout")


func _finish(status: String) -> void:
	if _finished:
		return
	_finished = true
	summary["status"] = status
	summary["total_ms"] = Time.get_ticks_msec() - _t0
	_write_json("summary.json", summary)
	var parts := []
	for k in summary["layers"]:
		parts.append("%s=%s" % [k, "ok" if summary["layers"][k].get("ok", false) else "chyba"])
	print("VIZUAL HOTOVO %s out=%s %s (%d s)" % [status, out_dir, " ".join(parts), summary["total_ms"] / 1000])
	quit(0)
