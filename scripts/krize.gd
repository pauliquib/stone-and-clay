## Kříže u cest, poutní místa a kaplička na návsi (zadání uživatele, mimo milníky). Polohy jsou data v `data/krize.json` (OSM, ODbL,
## převod lat/lon → herní souřadnice viz `tools/obce.py`); názvy jsou generické.
## Kříž = kamenný podstavec + dřevěný nebo kovový kříž; poutní místo / kaplička = malá kaple se zvoničkou.
## Fyzika jen u objektů v dosahu PHYS_R od hráče (jinak jen vizuál). E u objektu = krátká zpráva (modlitba),
## bez XP a karmy. Jeden uzel ve `World` (`World.krize`), nic se neukládá.
## Kaplička na návsi: `chapel_pos()` vrací polohu pro nedělní mši (M5.5) – mše sama se nemění.
class_name Krize
extends Node3D

const DATA_PATH := "res://data/krize.json"
const CHAPEL_ID := "kaplicka_navsi"
const PHYS_R := 150.0                      # m – fyzika jen v tomto dosahu hráče
const CHECK_S := 2.0                       # s – jak často se kontroluje dosah hráčů
const PRAY_R := 3.0                        # m – dosah E
const PRAY_S := 3.0                        # s – délka zprávy
const STONE := Color(0.52, 0.5, 0.46)
const WOOD := Color(0.45, 0.31, 0.18)
const IRON := Color(0.36, 0.37, 0.4)
const WALL := Color(0.86, 0.82, 0.74)
const ROOF := Color(0.5, 0.25, 0.2)
const MSG_CROSS := "Chvilku v tichu u kříže. Kolem jen vítr v trávě."
const MSG_CHAPEL := "Dveře kapličky jsou pootevřené. Chvilka ticha a klid."
const MSG_POUTNI := "Místo, kam lidé chodí na pouť. Tichá modlitba."

var world: World
var _items: Array = []   # [{id, typ, popis, pos, body}]
var _t := 0.0


func setup(w: World) -> void:
	world = w
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(d) != TYPE_DICTIONARY:
		return
	var kap: Dictionary = d.get("kaplicka", {})
	if not kap.is_empty():
		_add(kap, "kaplicka", 0)
	var idx := 0
	for o in d.get("objekty", []):
		_add(o, String(o.get("typ", "kriz")), idx)
		idx += 1
	_update_physics()


func _process(delta: float) -> void:
	_t += delta
	if _t < CHECK_S:
		return
	_t = 0.0
	_update_physics()


## Výška terénu pod bodem (x, z); bez terénu na nule.
func _ground(x: float, z: float) -> float:
	if world != null and world.terrain != null:
		return world.terrain.height_at(x, z)
	return 0.0


func _add(o: Dictionary, typ: String, idx: int) -> void:
	var x: float = float(o.get("x", 0.0))
	var z: float = float(o.get("z", 0.0))
	var yaw: float = float(o.get("yaw", 0.0))
	var y := _ground(x, z)
	var root := Node3D.new()
	root.position = Vector3(x, y, z)
	root.rotation.y = yaw
	add_child(root)
	var kit := MeshKit.new()
	var is_cross := typ == "kriz"
	if is_cross:
		_cross_kit(kit, idx % 2 == 1)      # každý druhý kříž je kovový
	else:
		_chapel_kit(kit)
	MeshKit.mesh_instance(root, kit.commit(MeshKit.vc_material(0.85, 0.0, 0.0, false)))
	# kolize se zapíná jen v dosahu hráče (collision_layer 0 = bez fyziky)
	var body := StaticBody3D.new()
	body.collision_layer = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.4, 3.0, 1.4) if is_cross else Vector3(4.0, 5.0, 6.0)
	cs.shape = bs
	cs.position = Vector3(0, bs.size.y * 0.5, 0)
	body.add_child(cs)
	root.add_child(body)
	var popis := String(o.get("popis", "Kříž u cesty"))
	if typ == "kaplicka":
		popis = "Kaplička u cesty"
	_items.append({"id": String(o.get("id", "")), "typ": typ, "popis": popis,
		"pos": Vector3(x, y, z), "body": body})


## Kamenný podstavec, dřík a příčka; `metal` = kovový kříž místo dřevěného.
func _cross_kit(kit: MeshKit, metal: bool) -> void:
	var c := IRON if metal else WOOD
	kit.box(Vector3(0, 0.25, 0), Vector3(1.1, 0.5, 1.1), STONE)
	kit.box(Vector3(0, 0.62, 0), Vector3(0.8, 0.24, 0.8), STONE.lightened(0.08))
	kit.box(Vector3(0, 1.9, 0), Vector3(0.16, 2.1, 0.16), c)
	kit.box(Vector3(0, 2.35, 0), Vector3(0.9, 0.16, 0.16), c)


## Malá kaple: loď, dvě střešní roviny, průčelí se zvoničkou a křížem, dveře.
func _chapel_kit(kit: MeshKit) -> void:
	kit.box(Vector3(0, 0.15, 0), Vector3(4.6, 0.3, 6.6), STONE)
	kit.box(Vector3(0, 1.8, 0), Vector3(3.6, 3.0, 5.0), WALL)
	kit.box(Vector3(-0.95, 4.0, 0), Vector3(2.5, 0.22, 5.4), ROOF, Vector3(0, 0, 0.55))
	kit.box(Vector3(0.95, 4.0, 0), Vector3(2.5, 0.22, 5.4), ROOF, Vector3(0, 0, -0.55))
	kit.box(Vector3(0, 3.0, -2.9), Vector3(1.4, 6.0, 1.4), WALL)
	kit.box(Vector3(0, 6.2, -2.9), Vector3(1.8, 0.2, 1.8), ROOF)
	kit.box(Vector3(0, 7.2, -2.9), Vector3(0.1, 1.6, 0.1), IRON)
	kit.box(Vector3(0, 7.4, -2.9), Vector3(0.6, 0.1, 0.1), IRON)
	kit.box(Vector3(0, 1.2, 2.51), Vector3(1.0, 2.0, 0.05), WOOD)


## Zapne kolizi u objektů v dosahu PHYS_R od alespoň jednoho hráče, ostatní nechá bez fyziky.
func _update_physics() -> void:
	if world == null:
		return
	for it in _items:
		var near := false
		var pos: Vector3 = it["pos"]
		for pid in world.players:
			var p: Player = world.players[pid]
			if p != null and p.global_position.distance_to(pos) < PHYS_R:
				near = true
				break
		var body: StaticBody3D = it["body"]
		if is_instance_valid(body):
			body.collision_layer = 1 if near else 0


## Poloha kapličky na návsi (pro nedělní mši, M5.5); bez dat nula.
func chapel_pos() -> Vector3:
	for it in _items:
		if String(it["id"]) == CHAPEL_ID:
			return it["pos"]
	return Vector3.ZERO


## Akce u kříže / kapličky (E): krátká zpráva. Vrací se přes `World.notify`.
func interactables(id: int) -> Array:
	var out: Array = []
	if world == null:
		return out
	var p: Player = world.players.get(id)
	if p == null or p.inside != "" or p.car != null:
		return out
	for i in _items.size():
		var it: Dictionary = _items[i]
		var pos: Vector3 = it["pos"]
		var d := Vector2(p.global_position.x - pos.x, p.global_position.z - pos.z).length()
		if d > PRAY_R:
			continue
		out.append({"pos": pos + Vector3(0, 1.0, 0), "r": PRAY_R, "kind": "custom",
			"text": "%s – pomodlit se" % String(it["popis"]), "action": _pray.bind(i)})
	return out


func _pray(id: int, i: int) -> void:
	if world == null or i < 0 or i >= _items.size():
		return
	var typ := String(_items[i]["typ"])
	var msg := MSG_CROSS
	if typ == "kaplicka":
		msg = MSG_CHAPEL
	elif typ != "kriz":
		msg = MSG_POUTNI
	world.notify(id, "show_message", [msg, PRAY_S])
