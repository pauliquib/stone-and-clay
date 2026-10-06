## Hlavní scéna: spojí svět (World – simulace, v MP server) a lokálního klienta (LocalClient – vstup,
## HUD, kamera, zvuky, efekty) a v singleplayeru do světa přidá jednoho hráče s id 1.
## Singleplayer = „server s jedním hráčem“, stejná kódová cesta jako budoucí multiplayer.
##
## Ladicí parametry (za `--` na příkazové řádce):
##   --shot=cesta.png  po načtení uloží snímek obrazovky a skončí
##   --view=fp|tp      pohled pro snímek      --pos=x,z  --yaw=stupně  --pitch=stupně  --zoom=m
##   --vsync=off|fifo  jiný režim vsync (výchozí mailbox)   --maxfps=n  strop snímků/s
##   --time=hh         denní doba při startu    --promile=x   hráč začne s daným množstvím alkoholu
##   --drive[=id]      hráč začne v autě; id = kolo / jawa, nebo libovolný model z CarModel.MODELS
##                     (přistaví se vedle auta hráče – zkouška nového vozidla)
##   --exittest        výstup z auta: poloha hráče, zdraví a stav auta po vystoupení
##   --date=RRRR-MM-DD datum 1. dne (výchozí dnešek)   --weather=druh  vynucené počasí (Weather.TYPES, snih)
##   --load=slot       po načtení světa nahraje uloženou pozici (rychly, auto, 1, 2, 3 – viz SaveGame)
##   --testmove / --bottest / --cartest / --drinktest / --questtest / --traffictest / --faunatest / --naturesynctest
##   --weathertest  testy (tests.gd); weathertest = přilnavost a brzdná dráha za všech situací
##   --interiortest  mapový interiér hospody přes FuncGodot (Fáze 2) + vstup/výstup a fallback
##   --villagertest  behavior strom vesničana přes LimboAI (Fáze 3): blackboard, větve denní
##                   rutiny (zahrada, hospoda), chůze za cílem; bez addonu jen fallback
##   --flighttest    stavový automat letouna přes godot-state-charts (Fáze 4): vzlet z dráhy,
##                   přetažení/zotavení, dosazení + přímé události; bez addonu fallback flagy
##   --fencetest     ploty a ohrady (Fáze 7): kolize drží, branky průchodné, kůň projde brankou
##   --gardentest    zahrada a dvoříště (Fáze 8): růst/plodiny vizuálně, kompost → hnůj → hnojení,
##                   studna naplní konev, skleník ochrání před mrazem, garden_visuals save
##   --vegetationtest vegetace (Fáze 9): vegetation.bin VEG1, chunky MultiMeshů, LOD podle
##                   vzdálenosti, detail=0 skryje, wind_strength z Weather, field_lut u obilí
##   --terraintest   terén (Fáze 9 / §12): mikroreliéf vs. kolize, wetness → shader, louže
##                   (Puddles) při wetness > 0,7, wet_boost asfaltu, north_xz pro sněhové jazyky
##   --obcetest      okolní obce (data/obce.json → World.obce, Villages): 5 fiktivních
##                   obcí, obec_at, postavená zástavba; --shot=… navíc snímek mapy okolí
class_name Main
extends Node3D

const LOCAL_ID := 1

## „Nová hra“ z nabídky: `reload_current_scene` postaví svět znovu; true = při nejbližším `_ready`
## ignorovat ladicí parametry z příkazové řádky (včetně `--load`), ať startuje opravdu čistá hra.
static var FRESH_START := false

var world: World
var client: LocalClient
var _args := {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else ""
	if FRESH_START:
		FRESH_START = false
		_args.clear()
	# vsync: výchozí MAILBOX (project.godot) – FIFO pod XWayland/KWin čeká na překreslení kompozitoru,
	# které spouští hlavně pohyb kurzoru → obraz se zasekává, jakmile se myš zastaví
	if _args.has("novsync") or _args.get("vsync", "") == "off":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	elif _args.get("vsync", "") == "fifo":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	if _args.has("maxfps"):
		Engine.max_fps = int(_args["maxfps"])
	world = World.new()
	world.name = "Svet"
	world.args = _args
	add_child(world)
	client = LocalClient.new()
	client.name = "Klient"
	client.world = world
	client.args = _args
	add_child(client)
	world.loading.connect(client.hud.set_loading)
	world.init_clock()
	var t0 := Time.get_ticks_msec()
	client.build_environment()
	await world.build()

	# lokální hráč (id 1) – výchozí místo u domova (M1.7 nájemní byt, los z celé mapy), nebo --pos / --yaw
	var sp := world.default_spawn()
	var pos: Vector3 = sp[0]
	var yaw: float = sp[1]
	if _args.has("pos"):
		var xz: PackedStringArray = _args["pos"].split(",")
		var x := float(xz[0])
		var z := float(xz[1])
		var look: Dictionary = world.meta["spawn"]
		var d := Vector2(float(look["look_x"]) - x, float(look["look_z"]) - z)
		pos = Vector3(x, world.terrain.height_at(x, z) + 0.2, z)
		yaw = atan2(-d.x, -d.y)
	if _args.has("yaw"):
		yaw = deg_to_rad(float(_args["yaw"]))
	var p := world.add_player(LOCAL_ID, pos, yaw)
	client.attach(p)
	world.start()
	if _args.has("promile"):
		var want := float(_args["promile"])
		p.body.body_alc = want * p.body.widmark_r() * p.body.weight
	print("Stone & Clay: svět načten za %d ms" % (Time.get_ticks_msec() - t0))
	client.hud.finish_loading()
	client.ready_done = true
	if _args.has("load"):
		await _frames(2)
		client.load_game(String(_args["load"]) if _args["load"] != "" else "rychly")
	if _args.has("drive"):
		await _frames(3)
		var veh := world.traffic.car_of(LOCAL_ID)
		for v in world.traffic.vehicles_of(LOCAL_ID):
			if v.model_id == _args["drive"]:
				veh = v
		if veh.model_id != _args["drive"] and CarModel.MODELS.has(_args["drive"]):
			veh = world.traffic.spawn_test_vehicle(LOCAL_ID, _args["drive"])   # zkouška nového modelu
			world._connect_car(veh)
			await _frames(2)
		world.enter_car(LOCAL_ID, veh)
	if _args.has("shot"):
		client.screenshot()
	if _args.has("bottest"):
		Tests.bot_test(self)
	if _args.has("map"):
		client.hud._toggle_map()
	if _args.has("testmove"):
		Tests.move_test(self)
	if _args.has("exittest"):
		Tests.exit_test(self)
	if _args.has("cartest"):
		Tests.car_test(self)
	if _args.has("drinktest"):
		Tests.drink_test(self)
	if _args.has("questtest"):
		Tests.quest_test(self)
	if _args.has("traffictest"):
		Tests.traffic_test(self)
	if _args.has("faunatest"):
		Tests.fauna_test(self)
	if _args.has("naturesynctest"):
		Tests.nature_sync_test(self)
	if _args.has("weathertest"):
		Tests.weather_test(self)
	if _args.has("interiortest"):
		Tests.interior_test(self)
	if _args.has("villagertest"):
		Tests.villager_test(self)
	if _args.has("flighttest"):
		Tests.flight_test(self)
	if _args.has("fencetest"):
		Tests.fence_test(self)
	if _args.has("gardentest"):
		Tests.garden_test(self)
	if _args.has("vegetationtest"):
		Tests.vegetation_test(self)
	if _args.has("terraintest"):
		Tests.terrain_test(self)
	if _args.has("obcetest"):
		Tests.obec_test(self)
	if _args.has("perf"):
		Tests.perf_test(self)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
