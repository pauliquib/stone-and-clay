## Lesní dělník (M3.3) – pracoviště práce „Lesní dělník“ (`data/prace.json` → `lesni_delnik`, zaměstnavatel smyšlená lesní
## správa, vedoucí u myslivecké chaty = místo „chata“). Jeden uzel ve `World` (`World.les`), vzniká v `World.add_player`.
##
## - **Paseka**: nejbližší kus lesa (`Fauna.forest_at` ≥ `FOREST_MIN`) `PASEKA_R0`–`PASEKA_R1` m od chaty, dál než `ROAD_GAP`
##   od silnic, s dost stromy. U okraje paseky (směrem k chatě) stojí **hromada dřeva** (roste s počtem složených kusů).
## - **Vyznačené stromy** (poskytovatel `les_znacene`): jednou za den `MARK_N` stojících stromů na pasece dostane barevný pruh
##   na kmeni. Kácení vyznačeného stromu na směně je s povolením (`World.has_permit` → `work_permit`), jiný strom v lese
##   zůstává přestupek (Forestry M2.1).
## - **Úkoly** (typ „modul“ – pokrok hlásí tenhle modul přes `Jobs.progress` z událostí hráče, `Jobs.set_event_hook`):
##   `les_kaceni` (tree_felled vyznačeného stromu), `les_zpracovani` (odvětvit / rozřezat kmen na pasece – log_lopped, log_cut),
##   `les_vysadba` (III–V, X–XI: zasadit zapůjčenou sazenici na pasece – tree_planted); `les_hromada` je typ „akce“
##   (`slozit_drevo` na hromadu: špalek na rameni (G) nebo 4 polena z kapsy).
## - **Pila jen s ochranou** (M2.3): na směně lesního dělníka motorovou pilou bez přilby a ochranných kalhot (`Wardrobe.has_saw_gear`)
##   vedoucí kácet ani řezat nepustí (`Actions.chain_target_check`).
## Ukládání `to_dict` / `restore` (klíč `les` v `SaveGame`; starý save = nic vyznačeno, prázdná hromada).
class_name LesniPrace
extends Node3D

const JOB_ID := "lesni_delnik"
const PLACE := "chata"
const PASEKA_R0 := 40.0              # m od dveří chaty – hledání paseky
const PASEKA_R1 := 220.0
const PASEKA_R := 28.0               # m – poloměr paseky (vyznačené stromy, zpracování, výsadba)
const FOREST_MIN := 0.55             # hustota lesa z mapy stanovišť
const ROAD_GAP := 14.0               # m od silnice (Forestry.ROAD_R + rezerva) – kácení nesmí ohrozit provoz
const MIN_TREES := 6                 # aspoň tolik stromů na pasece
const MARK_N := 3                    # vyznačených stromů za den (DOPLNIT: počet)
const MARK_COLOR := Color(1.0, 0.45, 0.05)
const MARK_H := 1.35                 # m nad zemí – pruh na kmeni
const PERMIT_R := 1.2                # m – tolerance polohy stromu pro povolení kácení
const POLENA_PER_PIECE := 4          # kolik polen z kapsy = jeden kus na hromadu
const PILE_MAX_VIS := 24             # víc kusů hromada vizuálně neroste
const SAW_TOOLS := ["motorova_pila"]
const TICK_S := 2.0

var world: World
var center := Vector3.INF            # střed paseky
var pile_pos := Vector3.INF          # hromada dřeva
var marked: Array = []               # indexy vyznačených stromů (TreeManager)
var mark_jd := -1                    # den posledního značení
var pile_n := 0                      # složených kusů na hromadě
var _bands := {}                     # index stromu → MeshInstance3D pruhu
var _cut := []                       # polohy vyznačených stromů pokácených v poslední době (povolení pro Forestry._check_law)
var _pile_mi: MeshInstance3D
var _t := 0.0


func setup(w: World) -> void:
	world = w
	name = "Lesni_prace"
	_find_paseka()
	Jobs.set_provider("les_znacene", func(_w: World, _id: int, _j: Dictionary) -> Array: return _marked_points())
	Jobs.set_provider("les_kmeny", func(_w: World, _id: int, _j: Dictionary) -> Array: return _log_points())
	Jobs.set_provider("les_hromada", func(_w: World, id: int, _j: Dictionary) -> Array: return _pile_points(id))
	Jobs.set_provider("les_paseka", func(_w: World, _id: int, _j: Dictionary) -> Array: return [] if center == Vector3.INF else [center])
	Jobs.set_event_hook(JOB_ID, _on_job_event)
	Actions.set_handler("slozit_drevo", _on_stack)
	Actions.chain_target_check("slozit_drevo", _check_stack)
	for a in ["pokacet", "odvetvit", "rozrezat"]:
		Actions.chain_target_check(a, _check_saw)


# ------------------------------------------------------------------ paseka

## Paseka: bod v lese nejblíž chatě (prstence po 15 m, 16 směrů), dál od silnic, s aspoň `MIN_TREES` stromy v okolí.
func _find_paseka() -> void:
	var pl: Place = world.places.get(PLACE)
	if pl == null or world.fauna == null or world.trees == null:
		push_warning("Lesní dělník: chybí chata, mapa lesa nebo stromy – paseka nebude.")
		return
	var d := pl.door
	var r := PASEKA_R0
	while r <= PASEKA_R1:
		for k in 16:
			var a := TAU * float(k) / 16.0 + r * 0.01
			var x := d.x + cos(a) * r
			var z := d.z + sin(a) * r
			if world.fauna.forest_at(x, z) < FOREST_MIN or world.dist_to_roads(Vector2(x, z)) < ROAD_GAP:
				continue
			var p := Vector3(x, world.terrain.height_at(x, z), z)
			if _candidates(p, 99).size() < MIN_TREES:
				continue
			center = p
			var to_door := Vector3(d.x - x, 0, d.z - z).normalized()
			pile_pos = p + to_door * (PASEKA_R * 0.6)
			pile_pos.y = world.terrain.height_at(pile_pos.x, pile_pos.z)
			_build_pile()
			return
		r += 15.0
	push_warning("Lesní dělník: v okolí chaty se nenašel les pro paseku.")


## Stojící stromy na pasece (bez zasazených, dál od silnice a v lese), nejvýš `n`; pořadí dané semínkem dne.
func _candidates(c: Vector3, n: int, seed_ := 0) -> Array:
	var out := []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_ * 7727 + 3
	for i in 60:
		if out.size() >= n:
			break
		var a := rng.randf() * TAU
		var rr := sqrt(rng.randf()) * PASEKA_R
		var q := c + Vector3(cos(a) * rr, 0, sin(a) * rr)
		var t := world.trees.nearest_tree(q, 4.0)
		if t < 0 or t >= TreeManager.DYN_BASE or out.has(t) or marked.has(t) or world.trees.is_felled(t):
			continue
		var tp := world.trees.pos_of(t)
		if Vector2(tp.x - c.x, tp.z - c.z).length() > PASEKA_R or world.dist_to_roads(Vector2(tp.x, tp.z)) < ROAD_GAP:
			continue
		out.append(t)
	return out


func _today() -> int:
	return world.clock.jd() if world.clock else 0


## Body vyznačených stojících stromů; když žádný nezbyl a dnes se ještě neznačilo, vyznačí `MARK_N` nových.
func _marked_points() -> Array:
	_clean_marked()
	if marked.is_empty() and mark_jd != _today() and center != Vector3.INF:
		mark_jd = _today()
		for t in _candidates(center, MARK_N, mark_jd):
			_mark(int(t))
	var out := []
	for t in marked:
		out.append(world.trees.pos_of(int(t)) + Vector3(0, MARK_H, 0))
	return out


func _mark(t: int) -> void:
	if marked.has(t) or not world.trees.has_tree(t):
		return
	marked.append(t)
	var tp := world.trees.pos_of(t)
	var gy := world.terrain.height_at(tp.x, tp.z)
	var r := world.trees.trunk_radius(t) + 0.02
	var k := MeshKit.new()
	k.cylinder(Vector3.ZERO, r, r, 0.16, MARK_COLOR, Vector3.ZERO, 12)
	var mi := MeshKit.mesh_instance(self, k.commit(MeshKit.vc_material(0.7, 0.0, 0.25)), 120.0)
	mi.position = Vector3(tp.x, gy + MARK_H, tp.z)
	_bands[t] = mi


func _unmark(t: int) -> void:
	marked.erase(t)
	var mi: MeshInstance3D = _bands.get(t)
	if mi and is_instance_valid(mi):
		mi.queue_free()
	_bands.erase(t)


## Vyznačené stromy, které mezitím někdo pokácel (i mimo směnu), přijdou o pruh.
func _clean_marked() -> void:
	for t in marked.duplicate():
		if not world.trees.has_tree(int(t)) or world.trees.is_felled(int(t)):
			_unmark(int(t))


## Kmeny ležící na pasece (Forestry): cíl úkolu „Zpracovat kmeny“ – nejbližší bod osy k hráči.
func _log_points() -> Array:
	var out := []
	if world.forestry == null or center == Vector3.INF:
		return out
	for lg in world.forestry.logs:
		if is_instance_valid(lg) and (lg as Node3D).global_position.distance_to(center) < PASEKA_R + 12.0:
			out.append((lg.target as Dictionary).get("pos", (lg as Node3D).global_position))
	return out


## Hromada: je co skládat? (špalky na pasece, špalek na rameni, polena v kapse)
func _pile_points(id: int) -> Array:
	if pile_pos == Vector3.INF:
		return []
	var p: Player = world.players.get(id)
	var has := p != null and (p.item_count("polena") >= POLENA_PER_PIECE or (world.cargo and world.cargo.carried_kind(id) == "spalek"))
	if not has and world.forestry:
		for b in world.forestry.blocks:
			if is_instance_valid(b) and (b as Node3D).global_position.distance_to(center) < PASEKA_R + 12.0:
				has = true
				break
	if not has:
		return []
	# čtyři místa podél hromady (Jobs počítá každý cíl jednou – úkol „4 kusy“ potřebuje 4 cíle)
	var along := Vector3(center.z - pile_pos.z, 0, pile_pos.x - center.x).normalized() if center != Vector3.INF else Vector3.RIGHT
	var out := []
	for k in 4:
		out.append(pile_pos + along * (-0.75 + k * 0.5) + Vector3(0, 0.6, 0))
	return out


# ------------------------------------------------------------------ události práce

func _on_job_event(jb: Jobs, kind: String, data: Dictionary) -> void:
	if center == Vector3.INF:
		return
	match kind:
		"tree_felled":
			var t := int(data.get("tree", -1))
			if marked.has(t):
				_cut.append(world.trees.pos_of(t))
				if _cut.size() > 12:
					_cut = _cut.slice(_cut.size() - 12)
				_unmark(t)
				if not jb.progress("les_kaceni"):
					world.notify(jb.pid, "show_message", ["Vyznačený strom je dole.", 2.0])
			elif jb.on_shift(JOB_ID) and _near(data.get("pos", Vector3.INF), 4.0):
				world.notify(jb.pid, "show_message", ["Tenhle strom vyznačený nebyl – to nebylo v zadání!", 3.0])
				jb.adjust_rating(-3.0)
		"log_lopped", "log_cut":
			if _near(data.get("pos", Vector3.INF), 14.0):
				jb.progress("les_zpracovani")
		"tree_planted":
			if _near(data.get("pos", Vector3.INF), 10.0):
				var sp: Dictionary = PlantedTrees.SPECIES.get(String(data.get("species", "")), {})
				jb.unlend(String(sp.get("item", "")), 1)       # zapůjčená sazenice je v zemi – po směně se nevrací
				jb.progress("les_vysadba")


func _near(pos: Variant, extra: float) -> bool:
	return pos is Vector3 and (pos as Vector3) != Vector3.INF and Vector2((pos as Vector3).x - center.x,
		(pos as Vector3).z - center.z).length() <= PASEKA_R + extra


## Povolení ke kácení (volá `World.has_permit`): na směně lesního dělníka jen vyznačený strom (i právě pokácený).
func work_permit(id: int, pos: Vector3) -> bool:
	var jb: Jobs = world.jobs.get(id)
	if jb == null or not jb.on_shift(JOB_ID):
		return false
	for t in marked:
		var tp := world.trees.pos_of(int(t))
		if Vector2(tp.x - pos.x, tp.z - pos.z).length() <= PERMIT_R:
			return true
	for c in _cut:
		if Vector2((c as Vector3).x - pos.x, (c as Vector3).z - pos.z).length() <= PERMIT_R:
			return true
	return false


# ------------------------------------------------------------------ pila a hromada

## Na směně lesního dělníka motorová pila jen s přilbou a ochrannými kalhotami (M2.3).
func _check_saw(_aim: Dictionary, id: int) -> String:
	var p: Player = world.players.get(id)
	var jb: Jobs = world.jobs.get(id)
	if p == null or jb == null or not jb.on_shift(JOB_ID) or not (p.equipped in SAW_TOOLS):
		return ""
	if Wardrobe.has_saw_gear(p.outfit):
		return ""
	return "Bez ochranné přilby a kalhot k pile tě vedoucí s pilou nepustí (vezmi sekeru)."


func _check_stack(_aim: Dictionary, id: int) -> String:
	var p: Player = world.players.get(id)
	if p == null:
		return ""
	if (world.cargo and world.cargo.carried_kind(id) == "spalek") or p.item_count("polena") >= POLENA_PER_PIECE:
		return ""
	return "Přines špalek na rameni (G) nebo aspoň %d polena." % POLENA_PER_PIECE


func _on_stack(id: int, _def: Dictionary, _aim: Dictionary, ok: bool) -> void:
	var p: Player = world.players.get(id)
	if not ok or p == null:
		return
	if world.cargo and world.cargo.carried_kind(id) == "spalek":
		world.cargo.consume_carried(id)
	elif not p.remove_item("polena", POLENA_PER_PIECE):
		return
	pile_n += 1
	_build_pile()
	world.sound.emit(pile_pos, "thud", randf_range(1.1, 1.3), -6.0, 60.0)
	world.notify(id, "show_message", ["Na hromadě je %d kusů dřeva." % pile_n, 2.0])


## Hromada: skládané špalky ve vrstvách (vizuálně nejvýš `PILE_MAX_VIS`), podklad ze dvou trámků.
func _build_pile() -> void:
	if _pile_mi and is_instance_valid(_pile_mi):
		_pile_mi.queue_free()
	if pile_pos == Vector3.INF:
		return
	var k := MeshKit.new()
	for sx in [-0.7, 0.7]:
		k.box(Vector3(sx, 0.06, 0), Vector3(0.12, 0.12, 2.2), Forestry.BARK)
	var n := mini(pile_n, PILE_MAX_VIS) + 2          # pár kusů tam leží vždycky
	for i in n:
		var layer := i / 6
		var col := i % 6
		var z := -0.9 + col * 0.36 + (0.18 if layer % 2 == 1 else 0.0)
		var y := 0.3 + layer * 0.33
		k.cylinder(Vector3(0, y, minf(z, 0.95)), 0.16, 0.16, 1.9, Forestry.BARK, Vector3(0, 0, PI * 0.5), 8)
		k.cylinder(Vector3(0.955, y, minf(z, 0.95)), 0.15, 0.15, 0.01, Forestry.CUT_FACE, Vector3(0, 0, PI * 0.5), 8)
	_pile_mi = MeshKit.mesh_instance(self, k.commit(MeshKit.vc_material(0.9)), 160.0)
	_pile_mi.position = pile_pos
	if center != Vector3.INF:
		_pile_mi.rotation.y = atan2(center.x - pile_pos.x, center.z - pile_pos.z)


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0 or world == null:
		return
	_t = TICK_S
	_clean_marked()


# ------------------------------------------------------------------ ukládání

func to_dict() -> Dictionary:
	return {"marked": marked.duplicate(), "mark_jd": mark_jd, "pile": pile_n}


## Starý save bez klíče `les` = nic vyznačeno, prázdná hromada.
func restore(d: Dictionary) -> void:
	for t in marked.duplicate():
		_unmark(int(t))
	_cut.clear()
	mark_jd = int(d.get("mark_jd", -1))
	pile_n = int(d.get("pile", 0))
	for t in d.get("marked", []):
		var i := int(t)
		if world.trees and world.trees.has_tree(i) and not world.trees.is_felled(i):
			_mark(i)
	_build_pile()
