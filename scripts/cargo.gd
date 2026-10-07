## Náklad a přeprava (M2.10), jeden uzel ve `World` (`World.cargo`). Sjednocuje, čím se co doveze domů:
##
##  1. **Rameno** (G): jedno břemeno na rameni – ulovená zvěř (`Hunting.lift`, zajíc / sele / srnec), špalek a pytel (tady).
##     Rychlost chůze × clamp(1 − kg/60, 0,35, 0,9), žádný sprint, jen malý hop, výdrž ubývá s kg; při nule ho hráč upustí.
##     Divočák a všechno nad 35 kg: „Sám ho neuneseš.“ – jen na vozík / do auta (G u nich, i přímo ze země).
##  2. **Auto**: G u kufru (vlastní vozidlo, dosah ~3,4 m) naloží nesené břemeno – kapacita `kufr_l × 0,15` kg (DOPLNIT, prompt: ×0,1), velký kus (divočák)
##     jen kombi / dodávka / pickup (`LARGE_MIN_L` litrů kufru, nebo ložná plocha). Náklad v kufru je NEVIDITELNÝ (kontrola policií
##     M4.6), pickup ho vozí na ložné ploše (vidět), hmotnost zvedne `mass` auta (`Car.set_cargo_kg`). E u auta = vyložit vedle něj.
##  3. **Nosič motorky / kola**: jen náklad s `bike_rack` (ne divočák), viditelný; kolo jen do 15 kg, motorka do 35 kg; víc kmitá
##     (`Car._balance`), těžiště dozadu.
##  4. **Ruční vozík** (`HandCart`, koupit v Potravinách, po koupi stojí u domu): E u vozíku = uchopit oj a táhnout (pružina, do kopce
##     pomalu a za výdrž, z kopce tlačí), E znovu = pustit (na svahu ujede) nebo pustit s podloženým kolem; G naloží (nosnost 200 kg,
##     divočák, špalky, pytle), E vyloží; plachta (`plachta`) náklad skryje.
##
## Viditelnost (M4.6 to dotáhne): `visible_tag(id)` = tag nákladu, který je vidět (na rameni, na nosiči, na vozíku bez plachty);
## `cargo_seen` se ohlásí, když ho uvidí vesničan (`Forestry.witness_near`).
## Ukládání: `to_dict` / `restore` (klíč `cargo`), náklad ve vozidle `vehicle_to_dict` / `vehicle_restore` (klíč `cargo` u vozidla).
## V2 (druhý hráč místo pomocníka): háček `two_person_partner`.
class_name Cargo
extends Node3D

## Druhy nákladu: kg (typická hmotnost; u zvěře se bere skutečná), size (small / medium / large), shoulder (jde na rameno),
## two_person (jde nést ve dvou – M2.10 mimo Minimum), bike_rack (jde na nosič motorky), tag (co je vidět: zverina / drevo / material).
const CARGO := {
	"zajic": {"name": "Zajíc", "kg": 4.0, "size": "small", "shoulder": true, "two_person": false, "bike_rack": true, "tag": "zverina"},
	"srnec": {"name": "Srnec", "kg": 22.0, "size": "medium", "shoulder": true, "two_person": true, "bike_rack": true, "tag": "zverina"},
	"divocak": {"name": "Divočák", "kg": 80.0, "size": "large", "shoulder": false, "two_person": true, "bike_rack": false, "tag": "zverina"},
	"spalek": {"name": "Špalek", "kg": 15.0, "size": "medium", "shoulder": true, "two_person": false, "bike_rack": true, "tag": "drevo"},
	"pytel": {"name": "Pytel (25 kg)", "kg": 25.0, "size": "medium", "shoulder": true, "two_person": false, "bike_rack": true, "tag": "material"},
	# M3.3 práce: bedna se zbožím (prodavač – ze skladu do regálu)
	"bedna": {"name": "Bedna se zbožím", "kg": 12.0, "size": "medium", "shoulder": true, "two_person": false, "bike_rack": true, "tag": "material"},
	# M3.3 práce: soudek s kvasem (pomocník v pálenici – ze sklepa ke kotli)
	"sud": {"name": "Soudek s kvasem", "kg": 30.0, "size": "medium", "shoulder": true, "two_person": false, "bike_rack": false, "tag": "material"},
	# M6.4: sbalený paramotor (25 kg – na zádech / v kufru; položka inventáře `paramotor` má stejnou kg)
	"paramotor": {"name": "Sbalený paramotor", "kg": 25.0, "size": "medium", "shoulder": true, "two_person": false, "bike_rack": false, "tag": "material"},
}
const SHOULDER_MAX_KG := 35.0        # víc na rameno nevezmeš
const LIFT_R := 3.0                  # dosah zvednutí ze země (G)
const CART_REACH := 3.0              # dosah nakládky na vozík (m od hráče)
const VEH_REACH := 3.4               # dosah nakládky do vozidla (m od kufru / nosiče)
const LARGE_MIN_L := 600             # velký kus (divočák) jen do kufru od tolika litrů (kombi, dodávka), nebo na ložnou plochu
const KG_PER_LITER := 0.15           # kapacita kufru: `kufr_l × 0,15` kg (DOPLNIT: prompt chce ×0,1, ale pak se vyvržený divočák nevejde ani do kombi)
const BED_MAX_KG := 400.0            # nosnost ložné plochy pickupu
const RACK_MAX_KG := 35.0            # nosič motorky / mopedu
const BICYCLE_MAX_KG := 15.0         # nosič kola: jen malé věci
const SHOULDER := Vector3(0.0, 1.3, 0.0)
const STAMINA_K := 0.03              # úbytek výdrže za s při chůzi × (kg / 20)
## zdroje modifikátorů rychlosti hráče (`Player.set_speed_mod`)
const MOD_OWN := "rameno"
const MOD_CART := "vozik"
const JUMP_CARRIED := 2.0            # skok s nákladem (malý hop; bez nákladu `Player.jump_velocity`)
const GRIP_LOST_R := 3.6             # vzdálenost od madla, kdy oj vyklouzne z ruky
const CART_STAMINA_K := 0.03         # úbytek výdrže za s při tažení × (kg / 60) × (1 + 6 × stoupání)
const SEEN_R := 25.0                 # do kolika m vesničan uvidí viditelný náklad
const SEEN_COOLDOWN_S := 30.0
const TICK_S := 3.0
const BARK := Color(0.32, 0.22, 0.13)
const CUT_FACE := Color(0.78, 0.62, 0.4)
const SACK := Color(0.72, 0.64, 0.46)
const SACK_TIE := Color(0.45, 0.32, 0.2)
const CRATE := Color(0.62, 0.46, 0.28)        # M3.3 bedna se zbožím
const CRATE_GOODS := [Color(0.85, 0.7, 0.35), Color(0.2, 0.5, 0.2), Color(0.8, 0.25, 0.2)]
const HELPER_FEE := 200              # DOPLNIT: pomocník ve dvou (cena 200 Kč / přátelství ≥ 40) – mimo Minimum, viz PROJECT_LOG

var world: World
var carts: Array = []                # Array[HandCart]
var sacks: Array = []                # pytle ležící na zemi (StaticBody3D)
var two_person_partner := {}         # V2 háček: id hráče → id druhého hráče / NPC, se kterým nese náklad ve dvou (zatím nepoužito)
var _store: Dictionary = {}          # Car → Array záznamů nákladu (kufr / ložná plocha / nosič)
var _own: Dictionary = {}            # id hráče → {e}: špalek / pytel na rameni
var _grip: Dictionary = {}           # id hráče → {cart}: drží oj vozíku
var _seen_cd := {}                   # id hráče → čas (s), do kdy se `cargo_seen` neopakuje
var _tick_t := 0.0
var _rng := RandomNumberGenerator.new()


# ------------------------------------------------------------------ data

## Popis druhu nákladu; neznámý druh se chová jako střední náklad na rameno.
static func info(kind: String) -> Dictionary:
	if CARGO.has(kind):
		return CARGO[kind]
	return {"name": kind, "kg": 20.0, "size": "medium", "shoulder": true, "two_person": false, "bike_rack": true, "tag": "material"}


func setup(w: World) -> void:
	world = w
	name = "Naklad"
	_rng.randomize()


func _player(id: int) -> Player:
	return world.players.get(id)


func _msg(id: int, text: String, dur := 3.0) -> void:
	world.notify(id, "show_message", [text, dur])


func _gut_k() -> float:
	return world.hunting._gut_k() if world.hunting else 0.8


func _ground_pos(pos: Vector3) -> Vector3:
	return Vector3(pos.x, world.terrain.height_at(pos.x, pos.z), pos.z)


## Nese hráč něco v rukou (rameno / oj vozíku)? Hunting.lift to hlídá, ať se neseš dvě věci.
func hands_busy(id: int) -> bool:
	return _own.has(id) or _grip.has(id)


# ------------------------------------------------------------------ záznamy nákladu

## Záznam nákladu: {kind, kg, tag, r (poloměr špalku), c (Carcass | null), node (model / mrtvé tělo)}.
func _entry_carcass(c: Carcass) -> Dictionary:
	var kind := c.cargo_kind if CARGO.has(c.cargo_kind) else "srnec"
	return {"kind": kind, "kg": c.weight_kg(_gut_k()), "tag": String(info(kind).get("tag", "zverina")), "r": 0.0, "c": c, "node": c.node}


## Záznam špalku / pytle bez modelu (model se dodělá v `_visual_for`).
func _entry_data(kind: String, r := 0.2) -> Dictionary:
	var inf := info(kind)
	return {"kind": kind, "kg": float(inf.get("kg", 20.0)), "tag": String(inf.get("tag", "material")), "r": r, "c": null, "node": null}


func _entry_simple(kind: String, r := 0.2) -> Dictionary:
	var e := _entry_data(kind, r)
	e["node"] = _make_visual(kind, r)
	return e


## Model špalku / pytle (jeden draw call). Kořen je Node3D, aby šel snadno přemístit a natočit.
func _make_visual(kind: String, r := 0.2) -> Node3D:
	var root := Node3D.new()
	var k := MeshKit.new()
	if kind == "bedna":
		k.box(Vector3(0, 0.02, 0), Vector3(0.5, 0.04, 0.35), CRATE)
		for sx in [-0.24, 0.24]:
			k.box(Vector3(sx, 0.14, 0), Vector3(0.02, 0.24, 0.35), CRATE)
		for sz in [-0.165, 0.165]:
			k.box(Vector3(0, 0.14, sz), Vector3(0.5, 0.24, 0.02), CRATE)
		for i in 3:
			k.box(Vector3(-0.15 + i * 0.15, 0.2, 0), Vector3(0.13, 0.12, 0.28), CRATE_GOODS[i])
	elif kind == "sud":
		k.cylinder(Vector3(0, 0.3, 0), 0.2, 0.2, 0.6, CRATE.darkened(0.25), Vector3.ZERO, 12)
		k.cylinder(Vector3(0, 0.3, 0), 0.235, 0.235, 0.26, CRATE.darkened(0.15), Vector3.ZERO, 12)
		for y in [0.08, 0.52]:
			k.cylinder(Vector3(0, y, 0), 0.215, 0.215, 0.035, Color(0.3, 0.3, 0.32), Vector3.ZERO, 12)
	elif kind == "pytel":
		k.box(Vector3(0, 0.24, 0), Vector3(0.42, 0.48, 0.26), SACK)
		k.box(Vector3(0, 0.5, 0), Vector3(0.2, 0.08, 0.14), SACK)
		k.box(Vector3(0, 0.46, 0), Vector3(0.24, 0.03, 0.18), SACK_TIE)
	else:
		var bh := 0.45
		k.cylinder(Vector3(0, bh * 0.5, 0), r * 0.95, r, bh, BARK, Vector3.ZERO, 10)
		k.cylinder(Vector3(0, bh + 0.004, 0), r * 0.9, r * 0.9, 0.01, CUT_FACE, Vector3.ZERO, 10)
	MeshKit.mesh_instance(root, k.commit(MeshKit.vc_material(0.9)), 150.0)
	return root


func _entry_kg_sum(list: Array) -> float:
	var s := 0.0
	for e in list:
		s += float(e.get("kg", 0.0))
	return s


func _ser(e: Dictionary) -> Dictionary:
	var d := {"kind": e["kind"], "kg": e["kg"], "tag": e["tag"], "r": e.get("r", 0.2)}
	var c = e.get("c")
	if c is Carcass:
		d["c"] = (c as Carcass).to_dict()
	return d


## Obnoví záznam z uložených dat (`_ser`); null = nejde (chybí zvěř ve světě).
func _deser(d: Dictionary, where: String) -> Variant:
	if d.has("c"):
		if world.hunting == null:
			return null
		var c: Carcass = world.hunting.spawn_carcass(d["c"])
		if c == null:
			return null
		c.stored = where
		c.node.set_physics_process(false)
		return {"kind": String(d.get("kind", "srnec")), "kg": float(d.get("kg", 20.0)), "tag": String(d.get("tag", "zverina")),
			"r": 0.0, "c": c, "node": c.node}
	var kind := String(d.get("kind", "pytel"))
	var e := _entry_simple(kind, float(d.get("r", 0.2)))
	e["kg"] = float(d.get("kg", e["kg"]))
	return e


# ------------------------------------------------------------------ předměty na zemi

## Nejbližší zvednutelná věc do `LIFT_R`: {type: carcass | block | sack, obj, d}. Prázdný slovník = nic.
func _nearest_ground(p: Player) -> Dictionary:
	var best := {}
	var bd := LIFT_R
	var pp := p.global_position
	if world.hunting:
		for c in world.hunting.carcasses:
			if c.carried_by != 0 or c.stored != "" or c.node == null or not is_instance_valid(c.node):
				continue
			var d: float = c.pos.distance_to(pp)
			if d < bd:
				bd = d
				best = {"type": "carcass", "obj": c, "d": d}
	if world.forestry:
		for b in world.forestry.blocks:
			if not is_instance_valid(b):
				continue
			var d2: float = (b as Node3D).global_position.distance_to(pp)
			if d2 < bd:
				bd = d2
				best = {"type": "block", "obj": b, "d": d2}
	for s in sacks:
		if not is_instance_valid(s):
			continue
		var d3: float = (s as Node3D).global_position.distance_to(pp)
		if d3 < bd:
			bd = d3
			best = {"type": "sack", "obj": s, "d": d3}
	return best


## Záznam pro věc ze země (zatím bez zásahu do světa).
func _entry_of_ground(g: Dictionary) -> Dictionary:
	match String(g["type"]):
		"carcass":
			return _entry_carcass(g["obj"] as Carcass)
		"block":
			var b: Node = g["obj"]
			return _entry_data("spalek", float(b.get_meta("r", 0.2)))
	return _entry_data(String((g["obj"] as Node).get_meta("kind", "pytel")), 0.2)


## Odebere věc ze země (špalek / pytel zmizí, mrtvé tělo zůstane – jen se přepne `stored` / `carried_by`).
func _detach_ground(g: Dictionary) -> void:
	match String(g["type"]):
		"block":
			world.forestry.take_block(g["obj"])
		"sack":
			sacks.erase(g["obj"])
			(g["obj"] as Node).queue_free()


func _visual_for(e: Dictionary) -> void:
	if e.get("node") == null and e.get("c") == null:
		e["node"] = _make_visual(String(e["kind"]), float(e.get("r", 0.2)))


## Pytel na zemi (F2, později úkoly / obchod).
func spawn_sack(pos: Vector3, kind := "pytel") -> Node3D:
	var b := StaticBody3D.new()
	b.name = "Pytel" if kind == "pytel" else "Naklad_" + kind
	b.collision_layer = 1
	b.collision_mask = 0
	b.set_meta("kg", float(info(kind).get("kg", 25.0)))
	b.set_meta("kind", kind)                  # M3.3: i bedna se zbožím
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.44, 0.5, 0.3)
	cs.shape = bs
	cs.position = Vector3(0, 0.25, 0)
	b.add_child(cs)
	var vis := _make_visual(kind)
	b.add_child(vis)
	add_child(b)
	b.global_position = _ground_pos(pos)
	b.rotation.y = _rng.randf() * TAU
	sacks.append(b)
	return b


## Vrátí záznam na zem do `pos`: mrtvé tělo se vrátí ke zvěři, špalek do lesnictví, pytel na zem.
func _place_on_ground(e: Dictionary, pos: Vector3, yaw := 0.0) -> void:
	pos = _ground_pos(pos)
	var c = e.get("c")
	if c is Carcass:
		var cc := c as Carcass
		var n := cc.node
		if n == null or not is_instance_valid(n):
			return
		if n.get_parent() != null:
			n.get_parent().remove_child(n)
		if world.fauna:
			world.fauna.root_animals.add_child(n)
		else:
			add_child(n)
		n.global_transform = Transform3D(Basis.IDENTITY, pos + Vector3(0, 0.05, 0))
		n.yaw = yaw
		n.rig.rotation.y = yaw
		n.visible = true
		n.rig.visible = true
		n.set_physics_process(true)
		cc.stored = ""
		cc.carried_by = 0
		cc.pos = n.global_position
		return
	var vis = e.get("node")
	if vis is Node and is_instance_valid(vis):
		(vis as Node).queue_free()
	e["node"] = null
	if String(e["kind"]) == "spalek" and world.forestry:
		world.forestry.put_block(pos, float(e.get("r", 0.2)))
	else:
		spawn_sack(pos, String(e["kind"]))


# ------------------------------------------------------------------ G

## G (akce `whistle` ve `World.player_action`, před hvízdnutím na koně): nese-li hráč něco, naloží to na vozík / do auta u sebe,
## jinak to položí; jinak zvedne nejbližší věc ze země (těžkou naloží přímo na vozík / do auta u sebe). Vrací true, když akci převzal.
func on_g(id: int) -> bool:
	var p := _player(id)
	if p == null or p.car != null or p.horse != null:
		return false
	if _grip.has(id):
		_g_with_cart(id, p)
		return true
	if not _carried_entry(id).is_empty():
		if not _load_carried(id, p):
			_drop_carried(id, p)
		return true
	var g := _nearest_ground(p)
	if g.is_empty():
		return false
	_lift_ground(id, p, g)
	return true


func _lift_ground(id: int, p: Player, g: Dictionary) -> void:
	var e := _entry_of_ground(g)
	var inf := info(String(e["kind"]))
	var kg := float(e["kg"])
	if not bool(inf.get("shoulder", false)) or kg > SHOULDER_MAX_KG:
		var tgt := _nearest_target(id, p)
		if tgt.is_empty():
			_msg(id, "Sám ho neuneseš. Naložíš ho (G) na ruční vozík nebo do auta (kombi, dodávka, pickup); ve dvou to zatím nejde.", 4.0)
			return
		var err := _can_load(tgt, e)
		if err != "":
			_msg(id, err, 3.5)
			return
		_detach_ground(g)
		_visual_for(e)
		_do_load(id, tgt, e)
		return
	if String(g["type"]) == "carcass":
		world.hunting.lift(id, g["obj"] as Carcass)          # rameno zvěře (Hunting: nese, zpomalení, výdrž, upuštění)
		return
	if world.hunting and world.hunting.carried_by(id) != null:
		_msg(id, "Už něco neseš (G = položit).", 2.0)
		return
	_detach_ground(g)
	_visual_for(e)
	_own_lift(id, p, e)


# ------------------------------------------------------------------ rameno (špalek, pytel)

func _own_lift(id: int, p: Player, e: Dictionary) -> void:
	var kg := float(e["kg"])
	_own[id] = {"e": e}
	var k := clampf(1.0 - kg / 60.0, 0.35, 0.9)
	p.set_speed_mod(MOD_OWN, {"walk_k": k, "no_sprint": true, "jump": JUMP_CARRIED})   # s břemenem na rameni se neběhá
	var vis := e["node"] as Node3D
	if vis.get_parent() != self:
		if vis.get_parent() != null:
			vis.get_parent().remove_child(vis)
		add_child(vis)
	_msg(id, "Neseš %s (%d kg). G = položit." % [String(info(String(e["kind"])).get("name", e["kind"])), roundi(kg)], 3.0)
	world.emit_game_event(id, "cargo_lift", {"kind": e["kind"], "kg": kg, "tag": e["tag"]})


## Sundá modifikátor rychlosti daného zdroje (`MOD_OWN` rameno / `MOD_CART` vozík).
func _restore_speeds(p: Player, source: String) -> void:
	if p != null:
		p.clear_speed_mod(source)


## Sundá vlastní břemeno z ramene a vrátí jeho záznam (model zůstane, volající ho umístí).
func _own_release(id: int) -> Dictionary:
	if not _own.has(id):
		return {}
	var o: Dictionary = _own[id]
	_restore_speeds(_player(id), MOD_OWN)
	_own.erase(id)
	return o["e"]


# ------------------------------------------------------------------ co hráč nese

func _carried_entry(id: int) -> Dictionary:
	if _own.has(id):
		return _own[id]["e"]
	if world.hunting:
		var c := world.hunting.carried_by(id)
		if c != null:
			return _entry_carcass(c)
	return {}


## M3.3: druh břemena na rameni ("spalek", "pytel", "bedna"), "" = nic (zvěř se nepočítá).
func carried_kind(id: int) -> String:
	return String((_own[id]["e"] as Dictionary)["kind"]) if _own.has(id) else ""


## M3.3: břemeno z ramene „zmizí“ (složené na hromadu, bedna vybalená do regálu). Vrací jeho záznam, {} = nic nenesl.
func consume_carried(id: int) -> Dictionary:
	if not _own.has(id):
		return {}
	var e := _own_release(id)
	var vis = e.get("node")
	if vis is Node and is_instance_valid(vis):
		(vis as Node).queue_free()
	e["node"] = null
	return e


## M3.3: dá hráči na rameno nový kus nákladu (bedna ze skladu). False = má plné ruce / nese něco jiného.
func shoulder_new(id: int, kind: String) -> bool:
	var p := _player(id)
	if p == null or p.car != null or p.horse != null or hands_busy(id) or not _carried_entry(id).is_empty():
		return false
	_own_lift(id, p, _entry_simple(kind))
	return true


func carried_kg(id: int) -> float:
	var e := _carried_entry(id)
	return float(e.get("kg", 0.0))


## Sundá nesené břemeno z ramene (bez položení) a vrátí jeho záznam.
func _take_carried(id: int) -> Dictionary:
	if _own.has(id):
		return _own_release(id)
	if world.hunting:
		var c := world.hunting.release_carried(id)
		if c != null:
			return _entry_carcass(c)
	return {}


func _drop_carried(id: int, p: Player) -> void:
	if _own.has(id):
		var e := _own_release(id)
		var fwd := Basis(Vector3.UP, p.yaw) * Vector3.FORWARD
		_place_on_ground(e, p.global_position + fwd * 1.0)
		_msg(id, "Položeno.", 1.5)
	elif world.hunting:
		world.hunting.drop(id)


## Náklad, který je vidět (na rameni, na nosiči, na vozíku bez plachty): tag, jinak "" (viz `World.visible_cargo`).
func visible_tag(id: int) -> String:
	var e := _carried_entry(id)
	if not e.is_empty():
		return String(e["tag"])
	if _grip.has(id):
		var cart: HandCart = _grip[id]["cart"]
		if is_instance_valid(cart) and not cart.covered and not cart.cargo.is_empty():
			return String((cart.cargo[0] as Dictionary)["tag"])
	var p := _player(id)
	if p != null:
		for car in world.traffic.vehicles_of(id):
			if _veh_mode(car) == "" or _veh_mode(car) == "trunk" or not _store.has(car):
				continue
			if (_store[car] as Array).size() > 0 and car.global_position.distance_to(p.global_position) < 8.0:
				return String(((_store[car] as Array)[0] as Dictionary)["tag"])
	return ""


# ------------------------------------------------------------------ cíle nakládky (vozík, auto)

## Nejbližší vozík (do `CART_REACH`) nebo vlastní vozidlo (do `VEH_REACH` od kufru) u hráče: {type: cart | veh, obj}.
func _nearest_target(id: int, p: Player) -> Dictionary:
	var best := {}
	var bd := INF
	for c in carts:
		if not is_instance_valid(c):
			continue
		var d: float = (c as Node3D).global_position.distance_to(p.global_position)
		if d < CART_REACH and d < bd:
			bd = d
			best = {"type": "cart", "obj": c}
	for car in world.traffic.vehicles_of(id):
		if _veh_mode(car) == "":
			continue
		var d2: float = car.trunk_point().distance_to(p.global_position)
		if d2 < VEH_REACH and d2 < bd:
			bd = d2
			best = {"type": "veh", "obj": car}
	return best


## Vejde záznam do cíle? "" = ano, jinak text důvodu.
func _can_load(tgt: Dictionary, e: Dictionary) -> String:
	var kg := float(e["kg"])
	if String(tgt["type"]) == "cart":
		var cart: HandCart = tgt["obj"]
		if kg > cart.free_kg():
			return "Vozík je plný (nosnost %d kg, volno %d kg)." % [roundi(HandCart.CAPACITY_KG), roundi(cart.free_kg())]
		return ""
	return _veh_can_load(tgt["obj"] as Car, e)


func _do_load(id: int, tgt: Dictionary, e: Dictionary) -> void:
	var nm := String(info(String(e["kind"])).get("name", e["kind"]))
	if String(tgt["type"]) == "cart":
		_cart_load(tgt["obj"] as HandCart, e)
		_msg(id, "Naloženo na vozík: %s (%d kg)." % [nm, roundi(float(e["kg"]))], 2.5)
	else:
		var car := tgt["obj"] as Car
		_veh_load(car, e)
		var mode := _veh_mode(car)
		_msg(id, "Naloženo %s: %s (%d kg)." % [{"trunk": "do kufru (neviditelné)", "bed": "na ložnou plochu", "rack": "na nosič"}[mode],
			nm, roundi(float(e["kg"]))], 3.0)
	world.play_sfx(id, "pickup")
	world.emit_game_event(id, "cargo_load", {"kind": e["kind"], "kg": e["kg"], "tag": e["tag"], "to": String(tgt["type"])})


## G s nesením u cíle: naloží. Vrací true, když naložil (jinak se dá břemeno položit).
func _load_carried(id: int, p: Player) -> bool:
	var tgt := _nearest_target(id, p)
	if tgt.is_empty():
		return false
	var e := _carried_entry(id)
	var err := _can_load(tgt, e)
	if err != "":
		_msg(id, err + " Polož to vedle.", 3.5)
		return false
	e = _take_carried(id)
	_do_load(id, tgt, e)
	return true


## G s ojí v ruce: naloží nejbližší věc ze země na vlastní vozík.
func _g_with_cart(id: int, p: Player) -> void:
	var cart: HandCart = _grip[id]["cart"]
	var g := _nearest_ground(p)
	if g.is_empty():
		_msg(id, "Není co naložit – přijď k nákladu (G). E = pustit vozík.", 2.5)
		return
	var e := _entry_of_ground(g)
	var tgt := {"type": "cart", "obj": cart}
	var err := _can_load(tgt, e)
	if err != "":
		_msg(id, err, 3.0)
		return
	_detach_ground(g)
	_visual_for(e)
	_do_load(id, tgt, e)


# ------------------------------------------------------------------ vozidla: kufr, ložná plocha, nosič

## Způsob uložení: "trunk" (kufr, nevidět), "bed" (ložná plocha pickupu, vidět), "rack" (nosič motorky / kola, vidět), "" = nejde.
## Náklad uložený v kufru / na ložné ploše vozidla (M4.6: policejní kontrola kufru). Jen čtení, kopie seznamu.
func vehicle_items(car: Car) -> Array:
	return (_store.get(car, []) as Array).duplicate()


func _veh_mode(car: Car) -> String:
	if car.two_wheeler:
		return "rack" if car.has_rack() else ""
	if not car.cargo_bed().is_empty():
		return "bed"
	if car.trunk_liters() > 0:
		return "trunk"
	return ""


func _veh_cap(car: Car) -> float:
	match _veh_mode(car):
		"trunk":
			return float(car.trunk_liters()) * KG_PER_LITER
		"bed":
			return BED_MAX_KG
		"rack":
			return BICYCLE_MAX_KG if car.model.kind == "bike" else RACK_MAX_KG
	return 0.0


func _veh_kg(car: Car) -> float:
	return _entry_kg_sum(_store.get(car, []))


func _veh_can_load(car: Car, e: Dictionary) -> String:
	var mode := _veh_mode(car)
	if mode == "":
		return "Do tohohle vozidla se nakládat nedá."
	var inf := info(String(e["kind"]))
	var kg := float(e["kg"])
	if mode == "rack":
		if not bool(inf.get("bike_rack", false)):
			return "Tohle se na nosič nevejde."
		if car.model.kind == "bike" and kg > BICYCLE_MAX_KG:
			return "Na kolo jen malé věci (do %d kg)." % roundi(BICYCLE_MAX_KG)
	if mode == "trunk" and String(inf.get("size", "small")) == "large" and car.trunk_liters() < LARGE_MIN_L:
		return "Divočák se vejde jen do kombi, dodávky nebo pickupu."
	var cap := _veh_cap(car)
	if _veh_kg(car) + kg > cap:
		return "Tolik se tam nevejde (kapacita %d kg, volno %d kg)." % [roundi(cap), roundi(maxf(cap - _veh_kg(car), 0.0))]
	return ""


func _veh_load(car: Car, e: Dictionary) -> void:
	var mode := _veh_mode(car)
	var c = e.get("c")
	if c is Carcass:
		(c as Carcass).stored = {"trunk": "kufr", "bed": "korba", "rack": "nosic"}[mode]
		(c as Carcass).carried_by = 0
		if (c as Carcass).node != null:
			(c as Carcass).node.set_physics_process(false)
	var n = e.get("node")
	if n is Node3D and is_instance_valid(n):
		if (n as Node).get_parent() != null:
			(n as Node).get_parent().remove_child(n)
		car.add_child(n)
	var list: Array = _store.get(car, [])
	list.append(e)
	_store[car] = list
	_veh_update(car)


func _veh_update(car: Car) -> void:
	var list: Array = _store.get(car, [])
	var mode := _veh_mode(car)
	var i := 0
	var spec: Dictionary = car.model.spec
	for e in list:
		var n = e.get("node")
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		var node3 := n as Node3D
		var big := String(info(String(e["kind"])).get("size", "small")) == "large"
		var lp := Vector3.ZERO
		match mode:
			"bed":
				var bd: Dictionary = car.cargo_bed()
				var cc: Vector3 = bd["c"]
				if big:
					lp = cc + Vector3(0, 0.04, 0)
				else:
					lp = cc + Vector3((float(i % 3) - 1.0) * 0.45, 0.04 + 0.25 * float(i / 9), (float((i / 3) % 3) - 1.0) * 0.5)
			"rack":
				lp = Vector3(0, float(spec.get("tail_y", 0.7)) + 0.12 + 0.22 * float(i),
					float(spec.get("tail_z", -0.9)) + 0.3)
		node3.transform = Transform3D(Basis.IDENTITY, lp)
		if node3 is Animal:
			(node3 as Animal).rig.rotation.y = PI * 0.5 if mode == "rack" else 0.0
			(node3 as Animal).rig.visible = true
		node3.visible = mode != "trunk"
		i += 1
	car.set_cargo_kg(_entry_kg_sum(list))


## Místo na zemi za autem, kam se dává vyložený náklad.
func _veh_drop_spot(car: Car, i: int) -> Vector3:
	var back := car.global_transform.basis.z * -1.0
	back.y = 0.0
	back = back.normalized() if back.length() > 0.1 else Vector3.BACK
	var side := back.cross(Vector3.UP)
	return car.trunk_point() + back * 1.3 + side * ((float(i % 3) - 1.0) * 0.6) + back * float(i / 3) * 0.6


func _veh_unload_one(id: int, car: Car, e: Dictionary, i := 0) -> void:
	(_store[car] as Array).erase(e)
	_place_on_ground(e, _veh_drop_spot(car, i), _rng.randf() * TAU)
	_veh_update(car)
	world.emit_game_event(id, "cargo_unload", {"kind": e["kind"], "kg": e["kg"], "from": "veh"})


func _veh_unload_menu(id: int, car: Car) -> void:
	var cl = world.clients.get(id)
	var list: Array = _store.get(car, [])
	if cl == null or not is_instance_valid(car):
		return
	if list.is_empty():
		_msg(id, "Je prázdné.", 1.5)
		return
	var opts := []
	var text := "Naloženo %d ks, %d kg (%s)." % [list.size(), roundi(_veh_kg(car)), {"trunk": "kufr", "bed": "ložná plocha", "rack": "nosič"}.get(_veh_mode(car), "")]
	var shown := 0
	for e in list:
		if shown >= 6:
			break
		opts.append(["Vyložit: %s (%d kg)" % [String(info(String(e["kind"])).get("name", e["kind"])), roundi(float(e["kg"]))],
			_veh_unload_pick.bind(id, car, e)])
		shown += 1
	opts.append(["Vyložit vše", _veh_unload_all.bind(id, car)])
	opts.append(["Nechat", func(): pass])
	cl.hud.open_menu("Náklad ve vozidle", text, opts)


func _veh_unload_pick(id: int, car: Car, e: Dictionary) -> void:
	if is_instance_valid(car) and (_store.get(car, []) as Array).has(e):
		_veh_unload_one(id, car, e)
		_msg(id, "Vyloženo vedle auta.", 2.0)


func _veh_unload_all(id: int, car: Car) -> void:
	if not is_instance_valid(car):
		return
	var i := 0
	for e in (_store.get(car, []) as Array).duplicate():
		_veh_unload_one(id, car, e, i)
		i += 1
	_msg(id, "Vyloženo vedle auta.", 2.0)


# ------------------------------------------------------------------ ruční vozík

func spawn_cart(pos: Vector3, yaw: float) -> HandCart:
	var c := HandCart.make(_ground_pos(pos) + Vector3(0, 0.25, 0), yaw)
	world.add_child(c)
	carts.append(c)
	return c


## Vozík koupený v Potravinách (`World.buy`) stojí u domova (M1.7: u vchodu bytu / domu; volné místo jako u koně / zahrady),
## předmět z kapsy mizí.
func deliver_cart(id: int) -> void:
	var p := _player(id)
	if p == null or not world.places.has("domov"):
		return
	p.remove_item("rucni_vozik")
	var door: Vector3 = world.places["domov"].door
	var pos := door + Vector3(6.0, 0.0, 4.0)
	var yaw := 0.0
	var seed_ := 221 + id * 13 + carts.size()          # jen seed (historická hodnota)
	var sp := world._ground_spot(door, Vector2(door.x, door.z), seed_, Vector3(1.2, 1.2, 2.2), 5.0, 4.0)
	if not sp.is_empty():
		pos = sp[0]
		yaw = float(sp[1])
	spawn_cart(pos, yaw)
	_msg(id, "Ruční vozík ti dovezli a stojí u domu. E = uchopit a táhnout, G = naložit.", 4.0)


func _cart_load(cart: HandCart, e: Dictionary) -> void:
	var c = e.get("c")
	if c is Carcass:
		(c as Carcass).stored = "vozik"
		(c as Carcass).carried_by = 0
		if (c as Carcass).node != null:
			(c as Carcass).node.set_physics_process(false)
	cart.add_cargo(e)


func _cart_unload_one(id: int, cart: HandCart, e: Dictionary, i := 0) -> void:
	cart.remove_cargo(e)
	var side := cart.global_transform.basis.x
	side.y = 0.0
	var pos := cart.global_position + side.normalized() * (1.3 + float(i / 3) * 0.6) + cart.global_transform.basis.z * ((float(i % 3) - 1.0) * 0.5)
	_place_on_ground(e, pos, _rng.randf() * TAU)
	world.emit_game_event(id, "cargo_unload", {"kind": e["kind"], "kg": e["kg"], "from": "cart"})


func _cart_menu(id: int, cart: HandCart) -> void:
	var p := _player(id)
	var cl = world.clients.get(id)
	if p == null or cl == null or not is_instance_valid(cart):
		return
	var opts := []
	var text := "Ruční vozík: %d kg z %d kg%s%s." % [roundi(cart.cargo_kg()), roundi(HandCart.CAPACITY_KG),
		", pod plachtou" if cart.covered else "", ", kolo podložené" if cart.chocked else ""]
	if cart.gripped_by == 0:
		opts.append(["Uchopit oj a táhnout", _grip_start.bind(id, cart)])
	if not _carried_entry(id).is_empty():
		opts.append(["Naložit, co neseš", _load_to_cart.bind(id, cart)])
	var shown := 0
	for e in cart.cargo:
		if shown >= 5:
			break
		opts.append(["Vyložit: %s (%d kg)" % [String(info(String(e["kind"])).get("name", e["kind"])), roundi(float(e["kg"]))],
			_cart_unload_pick.bind(id, cart, e)])
		shown += 1
	if not cart.cargo.is_empty():
		opts.append(["Vyložit vše", _cart_unload_all.bind(id, cart)])
	if cart.covered:
		opts.append(["Sundat plachtu", _cart_tarp.bind(id, cart, false)])
	elif p.item_count("plachta") > 0:
		opts.append(["Zakrýt plachtou (schová náklad)", _cart_tarp.bind(id, cart, true)])
	if cart.chocked:
		opts.append(["Vyndat podložku z kola", _cart_chock.bind(id, cart, false)])
	else:
		opts.append(["Podložit kolo (zabrzdit)", _cart_chock.bind(id, cart, true)])
	opts.append(["Nechat být", func(): pass])
	cl.hud.open_menu("Ruční vozík", text, opts)


func _load_to_cart(id: int, cart: HandCart) -> void:
	var p := _player(id)
	if p == null or not is_instance_valid(cart) or cart.global_position.distance_to(p.global_position) > CART_REACH + 1.0:
		return
	var e := _carried_entry(id)
	if e.is_empty():
		return
	var err := _can_load({"type": "cart", "obj": cart}, e)
	if err != "":
		_msg(id, err, 3.0)
		return
	e = _take_carried(id)
	_do_load(id, {"type": "cart", "obj": cart}, e)


func _cart_unload_pick(id: int, cart: HandCart, e: Dictionary) -> void:
	if is_instance_valid(cart) and cart.cargo.has(e):
		_cart_unload_one(id, cart, e)
		_msg(id, "Vyloženo.", 1.5)


func _cart_unload_all(id: int, cart: HandCart) -> void:
	if not is_instance_valid(cart):
		return
	var i := 0
	for e in cart.cargo.duplicate():
		_cart_unload_one(id, cart, e, i)
		i += 1
	_msg(id, "Vyloženo.", 1.5)


func _cart_tarp(id: int, cart: HandCart, on: bool) -> void:
	var p := _player(id)
	if p == null or not is_instance_valid(cart):
		return
	if on:
		if p.item_count("plachta") <= 0:
			return
		p.remove_item("plachta")
		cart.set_covered(true)
		_msg(id, "Náklad přikryt plachtou – není vidět.", 2.5)
		world.emit_game_event(id, "cargo_covered", {"kg": cart.cargo_kg()})
	else:
		cart.set_covered(false)
		p.add_item("plachta")
		_msg(id, "Plachta sundána.", 2.0)


func _cart_chock(id: int, cart: HandCart, on: bool) -> void:
	if not is_instance_valid(cart):
		return
	cart.set_chocked(on)
	_msg(id, "Kolo podloženo – vozík stojí." if on else "Podložka vyndána – na svahu vozík ujede!", 2.5)


func _grip_start(id: int, cart: HandCart) -> void:
	var p := _player(id)
	if p == null or not is_instance_valid(cart) or p.car != null or p.horse != null:
		return
	if cart.gripped_by != 0:
		_msg(id, "Vozík už někdo drží.", 2.0)
		return
	if not _carried_entry(id).is_empty():
		_msg(id, "Máš plné ruce – polož, co neseš (G), nebo to nalož na vozík.", 3.0)
		return
	if p.inside != "":
		return
	cart.gripped_by = id
	cart.puller = p
	cart.chocked = false
	cart.sleeping = false
	cart.add_collision_exception_with(p)
	_grip[id] = {"cart": cart}
	p.set_speed_mod(MOD_CART, {"walk_k": 1.0, "no_sprint": true, "jump": JUMP_CARRIED})
	_msg(id, "Držíš oj vozíku (%d kg). G = naložit věc ze země, E = pustit / zabrzdit." % roundi(cart.total_kg()), 3.5)


## Pustí oj. `chock`: podložit kolo (vozík zůstane stát i na svahu), jinak na svahu ujede.
func grip_release(id: int, chock := false) -> void:
	if not _grip.has(id):
		return
	var o: Dictionary = _grip[id]
	var cart: HandCart = o["cart"]
	var p := _player(id)
	_restore_speeds(p, MOD_CART)
	_grip.erase(id)
	if is_instance_valid(cart):
		if p != null:
			cart.remove_collision_exception_with(p)
		cart.gripped_by = 0
		cart.puller = null
		if chock:
			cart.set_chocked(true)
		else:
			cart.sleeping = false


func _grip_menu(id: int) -> void:
	if not _grip.has(id):
		return
	var cart: HandCart = _grip[id]["cart"]
	var p := _player(id)
	var cl = world.clients.get(id)
	if cl == null or p == null or not is_instance_valid(cart):
		return
	var opts := [["Pustit vozík (na svahu ujede)", _grip_release_msg.bind(id, false)],
		["Pustit a podložit kolo (zabrzdit)", _grip_release_msg.bind(id, true)]]
	if cart.covered:
		opts.append(["Sundat plachtu", _cart_tarp.bind(id, cart, false)])
	elif p.item_count("plachta") > 0:
		opts.append(["Zakrýt plachtou (schová náklad)", _cart_tarp.bind(id, cart, true)])
	for e in cart.cargo.slice(0, 4):
		opts.append(["Vyložit: %s (%d kg)" % [String(info(String(e["kind"])).get("name", e["kind"])), roundi(float(e["kg"]))],
			_cart_unload_pick.bind(id, cart, e)])
	opts.append(["Držet dál", func(): pass])
	cl.hud.open_menu("Ruční vozík", "Neseš oj: %d kg. Do kopce se šlape hůř a unavuje; z kopce vozík tlačí." % roundi(cart.total_kg()), opts)


func _grip_release_msg(id: int, chock: bool) -> void:
	grip_release(id, chock)
	_msg(id, "Vozík zabrzděn." if chock else "Pustil jsi vozík.", 2.0)


# ------------------------------------------------------------------ smyčka

func _physics_process(delta: float) -> void:
	var __t0 := Tests.prof_t0()
	_physics_process_impl(delta)
	Tests.prof_add("cargo", __t0)


func _physics_process_impl(delta: float) -> void:
	if world == null or not world.ready_done:
		return
	for id in _own.keys():
		_own_follow(id, delta)
	for id in _grip.keys():
		_grip_update(id, delta)
	_tick_t -= delta
	if _tick_t > 0.0:
		return
	_tick_t = TICK_S
	_clean()
	_seen_tick()


func _own_follow(id: int, delta: float) -> void:
	var o: Dictionary = _own[id]
	var e: Dictionary = o["e"]
	var p := _player(id)
	var vis = e.get("node")
	if p == null or not (vis is Node3D) or not is_instance_valid(vis):
		_own_release(id)
		return
	if p.car != null or p.horse != null:
		_drop_carried(id, p)
		return
	var v := vis as Node3D
	var right := Basis(Vector3.UP, p.yaw) * Vector3.RIGHT
	v.global_position = p.global_position + SHOULDER + right * 0.2
	v.global_transform = Transform3D(Basis(Vector3.UP, p.yaw) * Basis(Vector3.BACK, PI * 0.5), v.global_position)     # leží na rameni napříč
	var hv := Vector2(p.velocity.x, p.velocity.z).length()
	if hv > 0.5:
		p.drain_stamina(delta * STAMINA_K * float(e["kg"]) / 20.0)
	if p.stamina <= 0.01:
		_msg(id, "Došly ti síly – náklad ti sklouzl z ramene.", 3.0)
		_drop_carried(id, p)


func _grip_update(id: int, delta: float) -> void:
	var o: Dictionary = _grip[id]
	var cart: HandCart = o["cart"]
	var p := _player(id)
	if p == null or not is_instance_valid(cart):
		_restore_speeds(p, MOD_CART)
		_grip.erase(id)
		return
	if p.car != null or p.horse != null or p.inside != "" or p.fallen > 0.0:
		grip_release(id, false)
		return
	if cart.handle_world().distance_to(p.global_position) > GRIP_LOST_R:
		_msg(id, "Vozík ti vyklouzl z ruky.", 2.5)
		grip_release(id, false)
		return
	var total := cart.total_kg()
	var fwd := Basis(Vector3.UP, p.yaw) * Vector3.FORWARD
	var pp := p.global_position
	var grade := (world.terrain.height_at(pp.x + fwd.x * 2.0, pp.z + fwd.z * 2.0) - world.terrain.height_at(pp.x, pp.z)) / 2.0
	var k := clampf(1.0 - total / 320.0, 0.45, 0.9)
	if grade > 0.0:
		k *= clampf(1.0 - grade * (2.0 + total / 120.0), 0.3, 1.0)          # do kopce pomalu (DOPLNIT: ladění podle pocitu)
	p.set_speed_mod(MOD_CART, {"walk_k": k, "no_sprint": true, "jump": JUMP_CARRIED})
	var hv := Vector2(p.velocity.x, p.velocity.z).length()
	if hv > 0.5:
		p.drain_stamina(delta * CART_STAMINA_K * (total / 60.0) * (1.0 + maxf(grade, 0.0) * 6.0))
	if p.stamina <= 0.01:
		_msg(id, "Došly ti síly – pustil jsi vozík.", 3.0)
		grip_release(id, false)
		return
	# z kopce vozík dojíždí hráče a tlačí ho (musí brzdit – couvat / zastavit)
	var to_p := pp - cart.handle_world()
	to_p.y = 0.0
	if to_p.length() < 0.6 and to_p.length() > 0.01:
		var dirp := to_p.normalized()
		var over := cart.linear_velocity.dot(dirp)
		if over > 0.5:
			p.velocity += dirp * minf(over, 3.0) * 8.0 * delta


## Úklid: záznamy s mrtvým tělem, zaniklá vozidla / vozíky.
func _clean() -> void:
	for car in _store.keys():
		if not is_instance_valid(car):
			_store.erase(car)
			continue
		var list: Array = _store[car]
		var changed := false
		for e in list.duplicate():
			var c = e.get("c")
			if c is Carcass and ((c as Carcass).node == null or not is_instance_valid((c as Carcass).node)):
				list.erase(e)
				changed = true
		if changed:
			_veh_update(car)
	for i in range(carts.size() - 1, -1, -1):
		if not is_instance_valid(carts[i]):
			carts.remove_at(i)
			continue
		var cart: HandCart = carts[i]
		for e in cart.cargo.duplicate():
			var c2 = e.get("c")
			if c2 is Carcass and ((c2 as Carcass).node == null or not is_instance_valid((c2 as Carcass).node)):
				cart.remove_cargo(e)


## Viditelný náklad a vesničan v dohledu → událost `cargo_seen` (M4.6: hajný, policie, kontrola).
func _seen_tick() -> void:
	if world.forestry == null:
		return
	var t := Time.get_ticks_msec() / 1000.0
	for id in world.players.keys():
		var tag := visible_tag(id)
		if tag == "" or t < float(_seen_cd.get(id, 0.0)):
			continue
		var p := _player(id)
		if p == null or not world.witness_seen(id, p.global_position, "naklad", SEEN_R):
			continue
		_seen_cd[id] = t + SEEN_COOLDOWN_S
		world.emit_game_event(id, "cargo_seen", {"tag": tag, "kg": carried_kg(id), "pos": p.global_position})


# ------------------------------------------------------------------ interakce (E)

func interactables(id: int) -> Array:
	var out := []
	var p := _player(id)
	if p == null or p.car != null or p.horse != null:
		return out
	if _grip.has(id):
		out.append({"pos": p.global_position, "r": 2.0, "kind": "custom", "text": "Ruční vozík – pustit / zabrzdit / plachta",
			"action": _grip_menu})
		return out
	for c in carts:
		if not is_instance_valid(c):
			continue
		var cart := c as HandCart
		if cart.global_position.distance_to(p.global_position) > 6.0:
			continue
		out.append({"pos": cart.global_position + Vector3(0, 0.6, 0), "r": 2.4, "kind": "custom",
			"text": "Ruční vozík (%d kg%s) – uchopit / naložit / vyložit" % [roundi(cart.cargo_kg()), ", plachta" if cart.covered else ""],
			"action": _cart_menu.bind(cart)})
	var carrying := not _carried_entry(id).is_empty()
	for car in world.traffic.vehicles_of(id):
		var mode := _veh_mode(car)
		if mode == "" or car.trunk_point().distance_to(p.global_position) > VEH_REACH + 0.5:
			continue
		var n := (_store.get(car, []) as Array).size()
		if n > 0:
			out.append({"pos": car.trunk_point(), "r": VEH_REACH, "kind": "custom",
				"text": "Vyložit z vozidla (%d ks, %d kg)" % [n, roundi(_veh_kg(car))], "action": _veh_unload_menu.bind(car)})
		elif carrying:
			out.append({"pos": car.trunk_point(), "r": VEH_REACH, "kind": "custom", "text": "Naložit, co neseš (G)",
				"action": _load_carried_e})
	return out


func _load_carried_e(id: int) -> void:
	var p := _player(id)
	if p != null and not _carried_entry(id).is_empty() and not _load_carried(id, p):
		_msg(id, "Nejde to naložit.", 2.0)


# ------------------------------------------------------------------ ukládání

func to_dict() -> Dictionary:
	var cs := []
	for c in carts:
		if not is_instance_valid(c):
			continue
		var cart := c as HandCart
		var items := []
		for e in cart.cargo:
			items.append(_ser(e))
		cs.append({"pos": _v3(cart.global_position), "yaw": cart.global_rotation.y, "cargo": items, "covered": cart.covered,
			"chocked": cart.chocked})
	var ss := []
	for s in sacks:
		if is_instance_valid(s):
			var sk := String((s as Node).get_meta("kind", "pytel"))
			# pytel jako dřív (pole souřadnic), jiný druh (M3.3 bedna) jako {pos, kind}
			ss.append(_v3((s as Node3D).global_position) if sk == "pytel" else {"pos": _v3((s as Node3D).global_position), "kind": sk})
	# to, co hráč právě nese na rameni (špalek / pytel), se uloží jako položené u jeho nohou
	var dropped := []
	for id in _own.keys():
		var p := _player(id)
		var e: Dictionary = _own[id]["e"]
		if p != null:
			dropped.append({"kind": e["kind"], "r": e.get("r", 0.2), "pos": _v3(p.global_position)})
	return {"carts": cs, "sacks": ss, "dropped": dropped}


## Starý save bez klíče `cargo` = žádný vozík, pytle ani náklad. Volat po `Hunting.restore` (těla se obnovují tam).
func restore(d: Dictionary) -> void:
	for id in _grip.keys():
		grip_release(id, false)
	for id in _own.keys():
		var e := _own_release(id)
		var vis = e.get("node")
		if vis is Node and is_instance_valid(vis):
			(vis as Node).queue_free()
	for car in _store.keys():
		if is_instance_valid(car):
			for e in _store[car]:
				var vis2 = e.get("node")
				if e.get("c") == null and vis2 is Node and is_instance_valid(vis2):
					(vis2 as Node).queue_free()
			(car as Car).set_cargo_kg(0.0)
	_store.clear()
	for c in carts:
		if is_instance_valid(c):
			(c as Node).queue_free()
	carts.clear()
	for s in sacks:
		if is_instance_valid(s):
			(s as Node).queue_free()
	sacks.clear()
	for cd in d.get("carts", []):
		var cart := spawn_cart(_to_v3(cd.get("pos")), float(cd.get("yaw", 0.0)))
		for ed in cd.get("cargo", []):
			var e2 = _deser(ed, "vozik")
			if e2 != null:
				cart.add_cargo(e2)
		cart.set_covered(bool(cd.get("covered", false)))
		cart.set_chocked(bool(cd.get("chocked", false)))
	for sp in d.get("sacks", []):
		if sp is Dictionary:
			spawn_sack(_to_v3((sp as Dictionary).get("pos")), String((sp as Dictionary).get("kind", "pytel")))
		else:
			spawn_sack(_to_v3(sp))
	for dd in d.get("dropped", []):
		var e3 := _entry_simple(String(dd.get("kind", "pytel")), float(dd.get("r", 0.2)))
		_place_on_ground(e3, _to_v3(dd.get("pos")) + Vector3(0.8, 0, 0))


## Náklad vozidla do uložení (prázdné pole = nic).
func vehicle_to_dict(car: Car) -> Array:
	var out := []
	for e in _store.get(car, []):
		out.append(_ser(e))
	return out


## Obnoví náklad vozidla (po `restore`; starý save bez klíče = prázdné).
func vehicle_restore(car: Car, arr: Array) -> void:
	if car == null or not is_instance_valid(car):
		return
	var mode := _veh_mode(car)
	if mode == "":
		return
	var where: String = {"trunk": "kufr", "bed": "korba", "rack": "nosic"}[mode]
	for ed in arr:
		var e = _deser(ed, where)
		if e != null:
			_veh_load(car, e)


static func _v3(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func _to_v3(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2])) if a is Array and a.size() >= 3 else Vector3.ZERO


# ------------------------------------------------------------------ ladění (F2)

## F2 → Příroda / Hráč: položí před hráče testovací náklad. what = srnec | divocak | spalek | pytel | vozik.
func debug(id: int, what: String) -> String:
	var p := _player(id)
	if p == null:
		return ""
	var fwd := Basis(Vector3.UP, p.yaw) * Vector3.FORWARD
	var pos := p.global_position + fwd * 2.2
	match what:
		"srnec", "divocak":
			return world.hunting.spawn_debug_carcass(id, what) if world.hunting else "Lov není k dispozici."
		"spalek":
			if world.forestry:
				world.forestry.put_block(_ground_pos(pos), 0.2)
				return "Špalek leží před tebou."
		"pytel":
			spawn_sack(pos)
			return "Pytel leží před tebou."
		"vozik":
			spawn_cart(pos, p.yaw + PI)
			return "Ruční vozík stojí před tebou."
	return ""
