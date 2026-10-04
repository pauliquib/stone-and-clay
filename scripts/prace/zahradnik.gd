## Zahradník u sousedů (M3.3) – brigáda na zavolání (`data/prace.json` → `zahradnik`, `druh: "zakazka"`, zakázky dává děda
## Vomáčka – E u jeho lavičky → „Vzít zakázku“). Jeden uzel ve `World` (`World.zahradnik`), vzniká v `World.add_player`.
##
## - **Zakázka** (tvůrce `zahradnik` pro `Jobs.set_contract_maker`): smyšlený soused z rodinného domu (`Estate.pick_customer_house`,
##   adresa = smyšlené číslo popisné z M1.7), 2–3 práce podle sezóny z `ukoly` práce (`Jobs.task_ok`), odměna `REWARD`
##   (400–900 Kč podle počtu prací a dovednosti), lhůta z katalogu.
## - **Dočasná zóna** na zahradě zákazníka (`World._ground_spot` u dveří domu, jinak před domem): přerostlá tráva (`posekat_zahradu`
##   kosou), keře (`strihat_ker` zahradními nůžkami), záhony (`ryt_cizi` lopatou / motykou), místa pro květiny
##   (`vysadit_kvetiny` se sazenicemi). Nářadí a sazenice zapůjčí zákazník (`zapujcit` v katalogu). Po konci zakázky zóna zmizí.
## Cíle úkolů registruje `Jobs` (typ „akce“ s poskytovateli `zahrada_*`), tady jen vzhled a stav prvků.
## Stav se neukládá: po načtení rozdělané zakázky se zóna u zákazníka postaví znovu (hotové kusy se neuchovají).
class_name ZahradnikPrace
extends Node3D

const JOB_ID := "zahradnik"
const MAX_D := 750.0                 # m od návsi – kde bydlí zákazníci
const ZONE := Vector3(9.0, 1.2, 6.0) # zahrada zakázky (š × v × h)
const REWARD := [250, 150, 100]      # základ + za každou práci + náhoda 0..; výsledek 400–900 Kč
const REWARD_RANGE := [400, 900]
const SKILL_BONUS := 0.25            # +25 % odměny při plném Zahradničení
const TASKS_N := [2, 3]
## Rozložení zóny v místních souřadnicích (x napříč, z do hloubky): [druh, poloha]
const LAYOUT := [
	["trava", Vector3(-3.0, 0, -1.5)], ["trava", Vector3(0.0, 0, -1.5)], ["trava", Vector3(3.0, 0, -1.5)], ["trava", Vector3(-3.0, 0, 1.2)],
	["ker", Vector3(-4.0, 0, 2.5)], ["ker", Vector3(-2.3, 0, 2.5)],
	["zahon", Vector3(1.0, 0, 1.8)], ["zahon", Vector3(3.0, 0, 1.8)],
	["kvetina", Vector3(0.4, 0, 0.3)], ["kvetina", Vector3(1.6, 0, 0.3)], ["kvetina", Vector3(2.8, 0, 0.3)],
]
## Smyšlení zákazníci (oslovení bez příjmení).
const CUSTOMERS := ["paní Zdena", "pan Karel", "paní Jiřina", "pan Bohouš", "paní Olga", "paní Marie", "paní Libuše", "pan Jarda"]
const GRASS := Color(0.3, 0.5, 0.16)
const BUSH := Color(0.16, 0.36, 0.12)
const SOIL := Color(0.3, 0.2, 0.12)
const FLOWERS := [Color(0.95, 0.3, 0.4), Color(0.95, 0.85, 0.2), Color(0.6, 0.35, 0.9)]

var world: World
var _z := {}                         # pid → {key, items: [{kind, pos, done, mi, mi2}]}
var _yaws := {}                      # semínko zakázky → natočení zahrady (po načtení uložené hry neznámé → 0)
var _t := 0.0


func setup(w: World) -> void:
	world = w
	name = "Zahradnik"
	Jobs.set_contract_maker("zahradnik", _make_contract)
	for kind in ["trava", "ker", "zahon", "kvetina"]:
		Jobs.set_provider("zahrada_" + kind, _points.bind(kind))
	Actions.set_handler("posekat_zahradu", _on_done.bind("trava"))
	Actions.set_handler("strihat_ker", _on_done.bind("ker"))
	Actions.set_handler("ryt_cizi", _on_done.bind("zahon"))
	Actions.set_handler("vysadit_kvetiny", _on_done.bind("kvetina"))
	Actions.chain_target_check("vysadit_kvetiny", func(_aim: Dictionary, id: int) -> String:
		var p: Player = world.players.get(id)
		return "" if p and p.item_count("sazenice_kvetin") > 0 else "Došly ti sazenice květin.")


# ------------------------------------------------------------------ zakázka

## Tvůrce zakázky (volá `Jobs.take_contract`): zákazník, místo, práce podle sezóny, odměna. {} = teď nic.
func _make_contract(w: World, id: int, j: Dictionary) -> Dictionary:
	if w.estate == null:
		return {}
	var now := int(w.clock.minutes)
	var house := w.estate.pick_customer_house(now * 31 + id, MAX_D)
	if house == 0:
		return {}
	var e := w.estate.info(house)
	var rng := RandomNumberGenerator.new()
	rng.seed = now * 17 + house
	var pool := []
	for t in j.get("ukoly", []):
		if Jobs.task_ok(Jobs.task_def(String(t)), w) and not pool.has(String(t)):
			pool.append(String(t))
	if pool.is_empty():
		return {}
	# pořadí prací: tráva → keře → rytí → výsadba (jak to na zahradě dává smysl), náhodný výběr 2–3
	var pick := pool.duplicate()
	while pick.size() > rng.randi_range(int(TASKS_N[0]), int(TASKS_N[1])):
		pick.remove_at(rng.randi() % pick.size())
	var ordered := []
	for t in pool:
		if pick.has(t):
			ordered.append(t)
	var sk: Skills = w.skills.get(id)
	var bonus := 1.0 + SKILL_BONUS * (sk.bonus("zahradnictvi") if sk else 0.0)
	var reward := int(REWARD[0]) + int(REWARD[1]) * ordered.size() + rng.randi_range(0, int(REWARD[2]))
	reward = clampi(int(roundf(reward * bonus / 10.0) * 10.0), int(REWARD_RANGE[0]), int(REWARD_RANGE[1]))
	var door: Vector3 = e.get("door", Vector3.INF)
	var seed_ := now + house
	var site := _zone_center(door, e.get("normal", Vector3(0, 0, 1)), seed_)
	_yaws[seed_] = float(site[1])
	var who := String(CUSTOMERS[rng.randi() % CUSTOMERS.size()])
	return {"pos": site[0], "label": w.estate.label(house), "customer": who, "ukoly": ordered, "odmena": reward, "seed": seed_,
		"zadani": "%s z %s potřebuje pomoct na zahradě." % [who.left(1).to_upper() + who.substr(1), w.estate.label(house)]}


## Střed a natočení zahrady u domu: volné rovné místo u dveří (`World._ground_spot`), jinak kus před domem. [pozice, yaw]
func _zone_center(door: Vector3, normal: Vector3, seed_: int) -> Array:
	var n := Vector3(normal.x, 0, normal.z)
	n = n.normalized() if n.length() > 0.01 else Vector3(0, 0, 1)
	var sp: Array = world._ground_spot(door + n * 6.0, Vector2(door.x, door.z), seed_, ZONE, 2.0, 4.0)
	if sp.is_empty():
		var p := door + n * 7.0
		return [Vector3(p.x, world.terrain.height_at(p.x, p.z), p.z), atan2(n.x, n.z)]
	return sp


# ------------------------------------------------------------------ zóna u zákazníka

## Zóna hráče pro jeho probíhající zakázku (postaví ji, když chybí – i po načtení uložené hry); {} = žádná zakázka.
func _zone(id: int) -> Dictionary:
	var jb: Jobs = world.jobs.get(id)
	var c := jb.contract() if jb and jb.current == JOB_ID else {}
	if c.is_empty():
		_clear(id)
		return {}
	var z: Dictionary = _z.get(id, {})
	if String(z.get("key", "")) == String(c["key"]):
		return z
	_clear(id)
	var pos: Vector3 = c["pos"]
	var yaw := float(_yaws.get(int(c.get("seed", 0)), 0.0))      # místo i semínko jsou uložené v zakázce (Jobs)
	z = {"key": String(c["key"]), "items": []}
	var b := Basis(Vector3.UP, yaw)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(c.get("seed", 0))
	for l in LAYOUT:
		var q: Vector3 = pos + b * (l[1] as Vector3)
		q.y = world.terrain.height_at(q.x, q.z)
		var it := {"kind": String(l[0]), "pos": q, "done": false}
		_build_item(it, yaw, rng)
		(z["items"] as Array).append(it)
	_z[id] = z
	return z


func _build_item(it: Dictionary, yaw: float, rng: RandomNumberGenerator) -> void:
	var k := MeshKit.new()
	var k2 := MeshKit.new()
	match String(it["kind"]):
		"trava":                        # přerostlá tráva: trsy stébel (po posekání zmizí)
			for i in 26:
				var x := rng.randf_range(-1.4, 1.4)
				var z := rng.randf_range(-1.4, 1.4)
				var h := rng.randf_range(0.3, 0.55)
				k.box(Vector3(x, h * 0.5, z), Vector3(0.05, h, 0.05), GRASS.lightened(rng.randf() * 0.2), Vector3(rng.randf_range(-0.3, 0.3), 0, 0))
		"ker":                          # rozcuchaný keř → zastřižený kvádr
			for i in 5:
				k.sphere(Vector3(rng.randf_range(-0.3, 0.3), 0.75 + rng.randf_range(-0.15, 0.3), rng.randf_range(-0.3, 0.3)),
					rng.randf_range(0.45, 0.6), BUSH.lightened(rng.randf() * 0.15))
			k2.box(Vector3(0, 0.55, 0), Vector3(1.0, 1.1, 0.9), BUSH)
		"zahon":                        # zrytý záhon (před rytím není vidět)
			k2.box(Vector3(0, 0.04, 0), Vector3(1.4, 0.1, 2.0), SOIL)
			for i in 5:
				k2.box(Vector3(0, 0.1, -0.8 + i * 0.4), Vector3(1.3, 0.04, 0.12), SOIL.darkened(0.2))
		"kvetina":                      # zasazené květiny (před výsadbou kolíček)
			k.box(Vector3(0, 0.15, 0), Vector3(0.03, 0.3, 0.03), Color(0.6, 0.45, 0.25))
			for i in 4:
				var fp := Vector3(rng.randf_range(-0.2, 0.2), 0.0, rng.randf_range(-0.2, 0.2))
				k2.box(fp + Vector3(0, 0.1, 0), Vector3(0.03, 0.2, 0.03), Color(0.2, 0.5, 0.15))
				k2.sphere(fp + Vector3(0, 0.24, 0), 0.07, FLOWERS[rng.randi() % FLOWERS.size()])
	if not k.verts.is_empty():
		var mi := MeshKit.mesh_instance(self, k.commit(MeshKit.vc_material(0.9)), 120.0)
		mi.position = it["pos"]
		mi.rotation.y = yaw
		it["mi"] = mi
	if not k2.verts.is_empty():
		var mi2 := MeshKit.mesh_instance(self, k2.commit(MeshKit.vc_material(0.9)), 120.0)
		mi2.position = it["pos"]
		mi2.rotation.y = yaw
		mi2.visible = false
		it["mi2"] = mi2


func _clear(id: int) -> void:
	var z: Dictionary = _z.get(id, {})
	for it in z.get("items", []):
		for k in ["mi", "mi2"]:
			var n = (it as Dictionary).get(k)
			if n is Node and is_instance_valid(n):
				(n as Node).queue_free()
	_z.erase(id)


## Poskytovatel `zahrada_<druh>`: nehotové prvky zóny hráče (výška kvůli zaměřování).
func _points(_w: World, id: int, _j: Dictionary, kind: String) -> Array:
	var out := []
	var z := _zone(id)
	for it in z.get("items", []):
		if String(it["kind"]) == kind and not bool(it["done"]):
			out.append((it["pos"] as Vector3) + Vector3(0, 0.4, 0))
	return out


func _on_done(id: int, _def: Dictionary, aim: Dictionary, ok: bool, kind: String) -> void:
	if not ok:
		return
	var z := _zone(id)
	var pos: Vector3 = aim.get("pos", Vector3.INF)
	var best := {}
	var bd := 2.5
	for it in z.get("items", []):
		if String(it["kind"]) != kind or bool(it["done"]):
			continue
		var d := ((it["pos"] as Vector3) + Vector3(0, 0.4, 0)).distance_to(pos)
		if d < bd:
			bd = d
			best = it
	if best.is_empty():
		return
	best["done"] = true
	var mi = best.get("mi")
	if mi is Node3D and is_instance_valid(mi) and kind != "zahon":
		(mi as Node3D).visible = false
	var mi2 = best.get("mi2")
	if mi2 is Node3D and is_instance_valid(mi2):
		(mi2 as Node3D).visible = true
	if kind == "kvetina":
		var p: Player = world.players.get(id)
		var jb: Jobs = world.jobs.get(id)
		if p and p.remove_item("sazenice_kvetin", 1) and jb:
			jb.unlend("sazenice_kvetin", 1)


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0 or world == null:
		return
	_t = 1.0
	for id in _z.keys():                # zakázka skončila → zóna zmizí
		var jb: Jobs = world.jobs.get(id)
		var c := jb.contract() if jb and jb.current == JOB_ID else {}
		if c.is_empty() or String(c["key"]) != String((_z[id] as Dictionary).get("key", "")):
			_clear(id)
