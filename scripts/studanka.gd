## Studánka a skautský tábor (M5.10): pramen v lese u potoka (E = napít se, naplnit konev; v zimě zamrzne)
## a stálé tábořiště na bezstromé mýtince. V červenci (1.–14.) tam stojí stany a táborák jako letní událost
## (kalendář M5.5 – `VillageEvents.register("tabor", …)`).
##
## Místa jsou odvozena z dat (les = hustota stromů z `trees.bin`, potok z `water.json`, lesní cesta z `map.json`);
## souřadnice jsou konstanty, uživatel je může upravit. Oddíl je smyšlený („Lesní Sovy“), bez loga a symbolů.
## Jeden uzel ve `World` (`World.studanka`). Vlastní stav nemá, takže se nic neukládá.
class_name Studanka
extends Node3D

const SPRING_POS := Vector2(-220.0, 400.0)   # les, potok ~10 m, lesní cesta ~30 m (odvozeno z dat)
const CAMP_POS := Vector2(-430.0, 110.0)     # bezstromá mýtina ~450 m od návsi, cesta ~36 m, potok ~330 m
const SPRING_NAME := "Studánka U Jelena"
const CAMP_NAME := "Tábor oddílu Lesních Sov"
const SPRING_R := 3.0                         # m – dosah E u studánky
const CAMP_EVENT_R := 300.0                   # m – stany a oheň se zobrazí, když je hráč blízko
const CAMP_MONTH := 7
const CAMP_LAST_DAY := 14
const FREEZE_TEMP := 0.0                      # °C – pod nulou je studánka zamrzlá
const CHECK_S := 2.0
const STONE := Color(0.52, 0.5, 0.46)
const WATER_C := Color(0.25, 0.42, 0.48)
const WOOD := Color(0.45, 0.31, 0.18)
const MAST_C := Color(0.72, 0.6, 0.42)
const CLOTH_A := Color(0.55, 0.62, 0.38)
const CLOTH_B := Color(0.72, 0.55, 0.25)
const EMBER := Color(1.0, 0.5, 0.15)

var world: World
var _spring_pos := Vector3.ZERO
var _camp_pos := Vector3.ZERO
var _spring_root: Node3D
var _camp_root: Node3D
var _event_root: Node3D
var _fire_light: OmniLight3D
var _t := 0.0


## Pravidlo kalendáře (M5.5): tábor běží 1.–14. července.
static func camp_day(jd: int) -> bool:
	var d := Clock.from_jdn(jd)
	return int(d["month"]) == CAMP_MONTH and int(d["day"]) <= CAMP_LAST_DAY


func setup(w: World) -> void:
	world = w
	_spring_pos = _ground(SPRING_POS)
	_camp_pos = _ground(CAMP_POS)
	_build_spring()
	_build_camp()
	_build_event()
	if world.village_events != null:
		world.village_events.register("tabor", Studanka.camp_day, "Skautský tábor v lese (1.–14. 7.)")
	_update_camp()


func _process(delta: float) -> void:
	_t += delta
	if _t < CHECK_S:
		return
	_t = 0.0
	_update_camp()


## Výška terénu pod bodem (x, z); bez terénu jen na nule.
func _ground(p: Vector2) -> Vector3:
	var y := 0.0
	if world != null and world.terrain != null:
		y = world.terrain.height_at(p.x, p.y)
	return Vector3(p.x, y, p.y)


func _build_spring() -> void:
	_spring_root = Node3D.new()
	_spring_root.position = _spring_pos
	add_child(_spring_root)
	var kit := MeshKit.new()
	# kamenný obrys žlábku a nádržka s vodou
	for i in 8:
		var a := TAU * float(i) / 8.0
		kit.box(Vector3(cos(a) * 0.95, 0.22, sin(a) * 0.95), Vector3(0.5, 0.44, 0.5), STONE)
	kit.cylinder(Vector3(0, 0.12, 0), 0.62, 0.62, 0.12, WATER_C)
	# stříška na dvou sloupcích, cedule a hrnek na řetízku
	kit.box(Vector3(-0.85, 1.1, 0), Vector3(0.14, 2.2, 0.14), WOOD)
	kit.box(Vector3(0.85, 1.1, 0), Vector3(0.14, 2.2, 0.14), WOOD)
	kit.box(Vector3(0, 2.25, 0), Vector3(2.2, 0.14, 1.6), WOOD, Vector3(0.12, 0, 0))
	kit.box(Vector3(1.25, 1.1, 0.0), Vector3(0.08, 0.5, 0.6), MAST_C)
	kit.box(Vector3(-0.5, 0.95, 0.9), Vector3(0.06, 0.06, 0.06), WOOD)
	kit.cylinder(Vector3(-0.5, 0.95, 0.95), 0.07, 0.07, 0.14, Color(0.8, 0.8, 0.82))
	MeshKit.mesh_instance(_spring_root, kit.commit(MeshKit.vc_material(0.85, 0.0, 0.0, false)))
	var lb := Label3D.new()
	lb.text = SPRING_NAME
	lb.font_size = 40
	lb.pixel_size = 0.005
	lb.position = Vector3(1.25, 1.1, 0.33)
	_spring_root.add_child(lb)


func _build_camp() -> void:
	_camp_root = Node3D.new()
	_camp_root.position = _camp_pos
	add_child(_camp_root)
	var kit := MeshKit.new()
	# stožár se vlajkou (vlajka je smyšlená, bez znaku), kruh kamenů, lavice z kulatiny
	kit.cylinder(Vector3(0, 3.0, 0), 0.07, 0.09, 6.0, MAST_C)
	kit.box(Vector3(0.35, 5.6, 0), Vector3(0.7, 0.45, 0.03), CLOTH_B)
	for i in 8:
		var a := TAU * float(i) / 8.0
		kit.cylinder(Vector3(cos(a) * 1.5, 0.12, sin(a) * 1.5), 0.22, 0.22, 0.24, STONE)
	kit.cylinder(Vector3(0, 0.08, 0), 0.5, 0.5, 0.1, Color(0.12, 0.1, 0.08))
	for a in [0.0, PI * 0.5, PI, PI * 1.5]:
		var c := Vector3(cos(a) * 3.0, 0.3, sin(a) * 3.0)
		kit.cylinder(c, 0.18, 0.18, 0.6, WOOD, Vector3(0, 0, 0))
		kit.box(c + Vector3(0, 0.22, 0), Vector3(1.4, 0.12, 0.1), WOOD)
	kit.box(Vector3(-4.5, 1.2, 0), Vector3(0.12, 2.4, 0.12), WOOD)
	kit.box(Vector3(-4.5, 2.2, 0), Vector3(1.8, 0.6, 0.06), MAST_C)
	MeshKit.mesh_instance(_camp_root, kit.commit(MeshKit.vc_material(0.85, 0.0, 0.0, false)))
	var lb := Label3D.new()
	lb.text = CAMP_NAME
	lb.font_size = 36
	lb.pixel_size = 0.005
	lb.position = Vector3(-4.5, 2.2, 0.06)
	_camp_root.add_child(lb)


## Letní události: tři stany a záře ohně. Postaveno jednou, zapíná se podle kalendáře.
func _build_event() -> void:
	_event_root = Node3D.new()
	_event_root.position = _camp_pos
	_event_root.visible = false
	add_child(_event_root)
	var kit := MeshKit.new()
	for s in [[Vector3(-2.5, 0, -3.0), 0.3, CLOTH_A], [Vector3(4.0, 0, -2.5), -0.5, CLOTH_B], [Vector3(2.0, 0, 4.5), 1.1, CLOTH_A]]:
		var base: Vector3 = s[0]
		var yaw: float = s[1]
		var col: Color = s[2]
		var rot := Vector3(0, yaw, 0)
		kit.box(base + Vector3(0, 0.7, 0).rotated(Vector3.UP, yaw), Vector3(2.2, 1.0, 1.6), col, rot)
		kit.box(base + Vector3(0, 1.45, 0).rotated(Vector3.UP, yaw), Vector3(2.0, 0.6, 1.4), col.darkened(0.15), rot)
	# polena kolem ohniště
	for i in 4:
		var a := TAU * float(i) / 4.0 + 0.4
		kit.cylinder(Vector3(cos(a) * 0.9, 0.2, sin(a) * 0.9), 0.14, 0.14, 0.9, WOOD, Vector3(PI * 0.5, a, 0))
	kit.cylinder(Vector3(0, 0.35, 0), 0.28, 0.12, 0.5, EMBER)
	MeshKit.mesh_instance(_event_root, kit.commit(MeshKit.vc_material(0.85, 0.0, 0.0, false)))
	_fire_light = OmniLight3D.new()
	_fire_light.position = Vector3(0, 1.2, 0)
	_fire_light.light_color = EMBER
	_fire_light.light_energy = 1.4
	_fire_light.omni_range = 12.0
	_event_root.add_child(_fire_light)


## Stany se ukážou jen v době tábora a když je hráč v dosahu tábořiště.
func _update_camp() -> void:
	if _event_root == null or world == null or world.clock == null:
		return
	var active := camp_day(world.clock.jd())
	var near := false
	for pid in world.players:
		var p: Player = world.players[pid]
		if p != null and p.global_position.distance_to(_camp_pos) < CAMP_EVENT_R:
			near = true
			break
	_event_root.visible = active and near


func frozen() -> bool:
	return world != null and world.weather != null and world.weather.temp <= FREEZE_TEMP


## Akce u studánky (E): napít se a naplnit konev. Vrací se přes `World.notify`, bez HUD volání ze světa.
func interactables(id: int) -> Array:
	var out: Array = []
	if world == null:
		return out
	var p: Player = world.players.get(id)
	if p == null or p.inside != "" or p.car != null:
		return out
	var d := Vector2(p.global_position.x - _spring_pos.x, p.global_position.z - _spring_pos.z).length()
	if d > SPRING_R:
		return out
	var pos := _spring_pos + Vector3(0, 0.7, 0)
	var ice := " (zamrzlá)" if frozen() else ""
	out.append({"pos": pos, "r": SPRING_R, "kind": "custom", "text": "%s – napít se%s" % [SPRING_NAME, ice],
		"action": _drink})
	out.append({"pos": pos, "r": SPRING_R, "kind": "custom", "text": "%s – naplnit konev%s" % [SPRING_NAME, ice],
		"action": _fill})
	return out


func _drink(id: int) -> void:
	if frozen():
		world.notify(id, "show_message", ["Studánka je zamrzlá, voda neteče.", 3.0])
		return
	# žízeň zatím v BodyState není (viz otevřené body) – jen chuť a zpráva
	world.notify(id, "show_message", ["Studená a čistá voda z pramene. Osvěží.", 3.0])


func _fill(id: int) -> void:
	var p: Player = world.players.get(id)
	if p == null:
		return
	if frozen():
		world.notify(id, "show_message", ["Studánka je zamrzlá, konev nenaplníš.", 3.0])
		return
	if p.item_count("konev") <= 0:
		world.notify(id, "show_message", ["Potřebuješ prázdnou konev.", 2.5])
		return
	p.remove_item("konev")
	p.add_item("konev_plna")
	world.notify(id, "show_message", ["Konev je plná studené vody z pramene.", 3.0])
