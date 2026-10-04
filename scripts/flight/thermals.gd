## Termika (M6.3): stoupavé bubliny nad poli a sídly v teplých slunných dnech (11–17 h),
## táhnou s větrem a žijí 5–15 herních minut. Nad lesem a vodou nevnikají (ochlazuje),
## za bouřky se na výstupní straně kupení přidává silné stoupání / sestupné proudy.
## `Aircraft` se ptá `lift_at(pos)` → svislá složka proudění (m/s, + nahoru).
## Systém drží `World` (uzel „Termika“), spawn i drift běží v reálném čase,
## životnost bublin se počítá v herních minutách (clock.speed násobí tok času).
class_name Thermals
extends Node

## Laditelné parametry termiky (čísla zjednodušená – hratelnost před fyzikální přesností).
const SPAWN_EVERY_MIN := 8.0       # jak často se zkouší nová bublina (herní minuty)
const MAX_BUBBLES := 10            # strop počtu živých bublin
const LIFE_MIN := [5.0, 15.0]      # životnost bubliny (herní minuty)
const RADIUS := [60.0, 140.0]      # poloměr bubliny (m)
const STRENGTH := [0.5, 3.0]       # stoupání v ose (m/s), sílí k poledni
const TOP_AGL := [350.0, 900.0]    # strop termiky nad zemí (m AGL)
const SPAWN_DIST := [300.0, 1500.0]# jak daleko od hráče bublina vzniká (m)
const SEASON_M := [5, 9]           # měsíce, kdy termika létá (květen–září)
const HOURS := [11.0, 17.0]        # denní okno termiky
const T_MIN := 18.0                # minimální teplota vzduchu (°C)
const FOREST_MAX := 0.35           # nad touto pokryvností lesa termika nevzniká
const SINK_RING := 1.4             # do tohoto násobku poloměru kolem bubliny slabě klesá (−0,3 m/s)
const STORM_LIFT := 4.0            # max stoupání / sestup pod bouřkou (m/s), šumově
const DEBUG_R := 0.0               # >0: ladění – fixní bublina nad hráčem o poloměru (m)

var world: World
var bubbles: Array = []            # {pos: Vector2, r: float, w: float (m/s), top: float (m AGL), zbyva: float (herní min)}
var _spawn_in := 2.0               # herní minuty do dalšího pokusu o bublinu
var _storm_noise := FastNoiseLite.new()


func setup(w: World) -> void:
	world = w
	_storm_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_storm_noise.frequency = 0.002
	_storm_noise.seed = 1379


## Letní teplé poledne: jasno / polojasno, nad T_MIN °C, hodina 11–17, květen–září.
func season_on() -> bool:
	if world == null or world.weather == null or world.clock == null:
		return false
	var m := world.clock.month()
	return m >= SEASON_M[0] and m <= SEASON_M[1]


func active() -> bool:
	if not season_on():
		return false
	var h := world.clock.hour()
	if h < HOURS[0] or h > HOURS[1]:
		return false
	if not (world.weather.kind in ["jasno", "polojasno"]):
		return false
	return world.weather.temp >= T_MIN


func _process(delta: float) -> void:
	if world == null or world.clock == null:
		return
	var gmin := delta * 0.5 * world.clock.speed        # herní minuty za reálnou sekundu (1 h = 2 min při speed 1)
	var wind := world.weather.wind_vector() if world.weather else Vector3.ZERO
	for i in range(bubbles.size() - 1, -1, -1):
		var b: Dictionary = bubbles[i]
		b["zbyva"] = float(b["zbyva"]) - gmin
		b["pos"] = (b["pos"] as Vector2) + Vector2(wind.x, wind.z) * delta     # bublina táhne s větrem (reálný čas)
		if float(b["zbyva"]) <= 0.0:
			bubbles.remove_at(i)
	if DEBUG_R > 0.0:
		return
	if active():
		_spawn_in -= gmin
		if _spawn_in <= 0.0 and bubbles.size() < MAX_BUBBLES:
			_spawn_in = SPAWN_EVERY_MIN * randf_range(0.6, 1.4)
			_spawn_bubble()
	else:
		_spawn_in = minf(_spawn_in, SPAWN_EVERY_MIN)


## Nová bublina: náhodný bod kolem nejbližšího hráče na poli / sídli (ne les, ne voda).
func _spawn_bubble() -> void:
	if world.players.is_empty():
		return
	var anchor: Vector3 = world.player_pos(world.players.keys()[randi() % world.players.size()])
	for _try in 8:
		var ang := randf() * TAU
		var d := randf_range(SPAWN_DIST[0], SPAWN_DIST[1])
		var x := anchor.x + sin(ang) * d
		var z := anchor.z + cos(ang) * d
		if not world.terrain.contains(x, z, 40.0):
			continue
		if world.fauna and world.fauna.forest_at(x, z) > FOREST_MAX:
			continue
		if world.water and float(world.water.info_at(x, z)["depth"]) > 0.0:
			continue
		# polední maximum – okolo 13:30 sílí, k ránu / večeru slábne
		var h := world.clock.hour()
		var mid := (HOURS[0] + HOURS[1]) * 0.5
		var day_k := 1.0 - clampf(absf(h - mid) / ((HOURS[1] - HOURS[0]) * 0.5), 0.0, 1.0) * 0.6
		bubbles.append({"pos": Vector2(x, z), "r": randf_range(RADIUS[0], RADIUS[1]),
			"w": randf_range(STRENGTH[0], STRENGTH[1]) * day_k, "top": randf_range(TOP_AGL[0], TOP_AGL[1]),
			"zbyva": randf_range(LIFE_MIN[0], LIFE_MIN[1])})
		return


## Svislá složka proudění v `pos` (m/s; + stoupá). Součet bublin + bouřkové stoupání / sestupné šumy.
func lift_at(pos: Vector3) -> float:
	var w := 0.0
	var p := Vector2(pos.x, pos.z)
	if DEBUG_R > 0.0:
		var anchor := world.player_pos(1) if world and world.players.has(1) else pos
		if p.distance_to(Vector2(anchor.x, anchor.z)) < DEBUG_R:
			w += STRENGTH[1]
		return w
	for b in bubbles:
		var d: float = p.distance_to(b["pos"])
		var r: float = b["r"]
		if d < r:
			var gy := world.terrain.height_at(pos.x, pos.z)
			var agl := pos.y - gy
			var cap := lerpf(1.0, 0.0, clampf((agl - float(b["top"]) * 0.75) / (float(b["top"]) * 0.25), 0.0, 1.0))
			w += float(b["w"]) * (1.0 - (d / r) * (d / r)) * cap      # vrchol bubliny stoupá nejvíc, ke stropu slábne
		elif d < r * SINK_RING:
			w -= 0.3 * (1.0 - (d - r) / (r * (SINK_RING - 1.0)))        # mírné sestupné kolo okolo
	# pod bouřkou: silný stoupavý i sestupný šum (jednoduchá „shelf“ náběžka)
	if world.weather and world.weather.storm > 0.25:
		var n := _storm_noise.get_noise_3d(pos.x, pos.y, pos.z + Time.get_ticks_msec() * 0.001)
		w += n * STORM_LIFT * world.weather.storm
	return w


## Číselný stav pro ladění / HUD (počet živých bublin).
func debug_status() -> String:
	return "termika: %d bublin%s" % [bubbles.size(), "" if active() else " (neaktivní)"]
