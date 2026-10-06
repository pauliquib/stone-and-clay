## Kácení stromů a zpracování dřeva (M2.1), jeden uzel ve `World` (`World.forestry`).
##
## Řetězec: strom (cíl `tree`, `TreeManager`) → akce `pokacet` → padající strom (animovaný pivot, ~3 s, zásah osob a aut,
## prach a listí) → padlý kmen (cíl `log`) → `odvetvit` (→ větve) → `rozrezat` (→ špalky, cíl `block`) → `stipat` (→ polena).
## Vše se ukládá (`to_dict` / `restore`, klíč `forestry` v `SaveGame`): pokácené stromy + pařezy, kmeny, špalky, nenahlášené činy.
##
## Zákon: kde smíš kácet (vlastní zahrada = `OWN_GARDEN_R` kolem dveří vlastního domu; nájemník bytu jen na pronajaté
## zahradě `Garden` + `RENTED_MARGIN`, M1.7), co je přestupek (cizí zahrada, les, silnice)
## a kdo to vidí / slyší (`HEAR_*`). Bez svědků se čin uloží do společného registru `World.unreported` (M4.4 – `World.add_unreported`, `pending_offenses`, `commit_pending`).
## Povolení ke kácení (úřad, M4.4): `World.has_permit(id, "kaceni", pos)`. Ochranné pomůcky (M2.3): `has_gear(id)`.
##
## Poznámka k „fyzice“: strom padá po vypočtené dráze (zrychlené naklápění kolem paty kmene), ne jako RigidBody3D –
## je předvídatelný (směr od hráče, dopad na terén) a nekmitá. Po dopadu z něj vznikne statický kmen `Log`.
class_name Forestry
extends Node

# ------------------------------------------------------------------ laditelné hodnoty

const OWN_GARDEN_R := 35.0               # m od dveří vlastního domu – vlastní pozemek (DOPLNIT: skutečný tvar zahrady)
const RENTED_MARGIN := 3.0               # m kolem pronajaté zahrady (byt v nájmu, M1.7) – počítá se jako „vlastní“
const ROAD_R := 8.0                      # m od silnice – ohrožení provozu
const HEAR_AXE := 120.0                  # m – sekeru je slyšet
const HEAR_SAW := 300.0                  # m – motorovou pilu je slyšet
const CRIME_VALUE_KC := 10000            # součet hodnoty dřeva za herní den nad limit = trestný čin
const WOOD_KC_PER_M3 := 1800.0
const SEVERITY_VALUE_KC := 20000.0       # hodnota dřeva, od které je přestupek „nejtěžší“ (závažnost 1.0)
const KARMA_UNSEEN := -2.0               # kácení v cizím bez svědků (se svědkem se karma strhne přes offense)
const FELL_MIN_S := 2.4                  # nejkratší doba pádu stromu (s)
const FELL_PER_M := 0.05                 # + s na metr výšky
const FALL_JITTER := 0.12                # rad – náhodná odchylka směru pádu
const TRUNK_USE := 0.7                   # podíl výšky, který je použitelný kmen (zbytek jsou větve a špice)
const SPALEK_LEN := 1.0                  # m – délka špalku
const MAX_SPALKY := 14
const MAX_LOGS := 40
const MAX_BLOCKS := 160
const POLENA_PER_SPALEK := 4
const XP_FELL := [20.0, 80.0]            # XP za pokácení podle velikosti
const XP_VOLUME_FULL := 6.0              # m³, od kterého je XP maximální
const HIT_DAMAGE := [20.0, 55.0]         # zásah padajícím stromem podle výšky
const HURT_NO_GEAR := {"sekera_stara": 0.05, "sekera": 0.05, "motorova_pila": 0.15}   # šance úrazu bez pomůcek
const FELL_TOOL_K := {"sekera_stara": 1.6, "sekera": 1.0, "motorova_pila": 0.35}
const LOP_TOOL_K := {"sekera_stara": 1.6, "sekera": 1.0, "motorova_pila": 0.5}        # odvětvení
const CUT_TOOL_K := {"sekera_stara": 3.2, "sekera": 2.5, "motorova_pila": 0.5}        # rozřezání (sekerou pomalu)
const SPLIT_TOOL_K := {"sekera_stara": 1.3, "sekera": 1.0}
const SOUND_GAP := {"sekera_stara": 0.75, "sekera": 0.65, "motorova_pila": 0.32}
const BARK := Color(0.33, 0.23, 0.14)
const CUT_FACE := Color(0.72, 0.58, 0.38)
const LEAF_DECID := Color(0.18, 0.32, 0.1)
const LEAF_CONIF := Color(0.08, 0.2, 0.09)

var world: World
var trees: TreeManager
var logs: Array = []                     # Log (padlé kmeny)
var blocks: Array = []                   # StaticBody3D špalků
var daily_value := {}                    # id hráče → {"day": int, "sum": int} – hodnota dřeva pokáceného v cizím za den

var _falls: Array = []                   # padající stromy
var _snd_t := {}                         # id hráče → čas do dalšího zvuku
var _tgt_t := 0.0
var _mat: StandardMaterial3D


## Padlý kmen: statické těleso, osa +Y podél kmene od paty ke špičce.
class Log:
	extends StaticBody3D
	var length := 6.0              # celá délka kmene s vrškem (m)
	var radius := 0.2              # poloměr u paty
	var branched := false
	var conifer := false
	var crown_r := 2.0
	var height := 8.0              # výška původního stromu
	var target := {}               # cíl registrovaný ve World (pos se průběžně posouvá k hráči)

	## Použitelná (rozřezatelná) délka po odvětvení.
	func use_length() -> float:
		return height * Forestry.TRUNK_USE

	func axis() -> Vector3:
		return global_transform.basis.y.normalized()

	func base_point() -> Vector3:
		return global_position

	## Nejbližší bod osy kmene k bodu `p` (v použitelné délce nebo v celém kmeni podle stavu).
	func closest_to(p: Vector3) -> Vector3:
		var l := use_length() if branched else length
		var a := axis()
		var t := clampf((p - global_position).dot(a), 0.0, l)
		return global_position + a * t

	func rebuild() -> void:
		var mi := get_node_or_null("Model") as MeshInstance3D
		if mi:
			mi.mesh = Forestry.tree_mesh(height, radius, crown_r, conifer, branched)


## Mesh celého stromu ležícího / padajícího podél +Y (pata v počátku): kmen a koruna z barev vrcholů.
static func tree_mesh(h: float, r: float, crown_r: float, conifer: bool, branched: bool) -> ArrayMesh:
	var k := MeshKit.new()
	var full := h * 0.95
	var use := h * TRUNK_USE
	var l := use if branched else full
	var r_top := r * (1.0 - 0.72 * l / full)
	k.cylinder(Vector3(0, l * 0.5, 0), maxf(r_top, 0.03), r, l, BARK, Vector3.ZERO, 10)
	if branched:
		k.cylinder(Vector3(0, l + 0.004, 0), maxf(r_top, 0.03) * 0.95, maxf(r_top, 0.03) * 0.95, 0.01, CUT_FACE, Vector3.ZERO, 10)
	else:
		if conifer:
			k.cylinder(Vector3(0, h * 0.55, 0), 0.05, crown_r, h * 0.8, LEAF_CONIF, Vector3.ZERO, 8)
		else:
			k.sphere(Vector3(0, h * 0.68, 0), crown_r, LEAF_DECID, Vector3(1.0, 0.85, 1.0))
	return k.commit(MeshKit.vc_material(0.9))


# ------------------------------------------------------------------ start

func setup(w: World) -> void:
	world = w
	trees = w.trees
	name = "Drevorubectvi"
	Actions.set_handler("pokacet", _on_fell)
	Actions.set_handler("odvetvit", _on_lop)
	Actions.set_handler("rozrezat", _on_cut)
	Actions.set_handler("stipat", _on_split)
	Actions.set_time_mod("pokacet", _mod_fell)
	Actions.set_time_mod("odvetvit", _mod_lop)
	Actions.set_time_mod("rozrezat", _mod_cut)
	Actions.set_time_mod("stipat", _mod_split)
	Actions.set_target_check("odvetvit", _check_lop)
	Actions.set_target_check("rozrezat", _check_cut)


# ------------------------------------------------------------------ doba akcí a kontrola cílů

func _mod_fell(aim: Dictionary, tool_id: String) -> float:
	var i := int(aim.get("tree", -1))
	if trees == null or not trees.has_tree(i):
		return 1.0
	var k := clampf(trees.scale_of(i), 0.5, 2.2) * (0.8 + trees.height_of(i) / 40.0)
	return k * float(FELL_TOOL_K.get(tool_id, 1.0))


func _log_of(aim: Dictionary) -> Log:
	var t: Dictionary = aim.get("target", {})
	var n = t.get("node")
	return n as Log if n != null and is_instance_valid(n) else null


func _mod_lop(aim: Dictionary, tool_id: String) -> float:
	var lg := _log_of(aim)
	var len_k := lg.length / 6.0 if lg else 1.0
	return clampf(len_k, 0.5, 3.0) * float(LOP_TOOL_K.get(tool_id, 1.0))


func _mod_cut(aim: Dictionary, tool_id: String) -> float:
	var lg := _log_of(aim)
	var k := 1.0
	if lg:
		k = (lg.use_length() / 6.0) * clampf(lg.radius / 0.2, 0.6, 2.5)
	return clampf(k, 0.4, 5.0) * float(CUT_TOOL_K.get(tool_id, 2.5))


func _mod_split(_aim: Dictionary, tool_id: String) -> float:
	return float(SPLIT_TOOL_K.get(tool_id, 1.0))


func _check_lop(aim: Dictionary, _id: int) -> String:
	var lg := _log_of(aim)
	if lg and lg.branched:
		return "Kmen už je odvětvený."
	return ""


func _check_cut(aim: Dictionary, _id: int) -> String:
	var lg := _log_of(aim)
	if lg and not lg.branched:
		return "Nejdřív kmen odvětvi."
	return ""


# ------------------------------------------------------------------ pokácení

func _day() -> int:
	return int(world.clock.minutes / 1440.0)


func _on_fell(id: int, _def: Dictionary, aim: Dictionary, ok: bool) -> void:
	if not ok or trees == null or not aim.has("tree"):
		return
	var i := int(aim["tree"])
	var p: Player = world.players.get(id)
	if p == null or not trees.has_tree(i) or trees.is_felled(i):
		return
	var tool_id := p.equipped
	var base := trees.pos_of(i)
	var away := Vector3(base.x - p.global_position.x, 0, base.z - p.global_position.z)
	if away.length() < 0.15:
		away = Basis(Vector3.UP, p.yaw) * Vector3.FORWARD
	var dir := away.normalized().rotated(Vector3.UP, randf_range(-FALL_JITTER, FALL_JITTER))
	var h := trees.height_of(i)
	var r := trees.trunk_radius(i)
	var vol := PI * r * r * h * 0.6
	trees.hide_tree(i, _day())
	_start_fall(i, base, dir, h, r, trees.is_conifer(i), id)
	world.give_xp(id, "drevorubectvi", lerpf(XP_FELL[0], XP_FELL[1], clampf(vol / XP_VOLUME_FULL, 0.0, 1.0)), "kácení")
	world.emit_game_event(id, "tree_felled", {"tree": i, "pos": base, "height": h, "tool": tool_id})
	_check_gear(id, p, tool_id)
	_check_law(id, base, tool_id, int(roundf(vol * WOOD_KC_PER_M3 / 10.0) * 10.0))


## Ochranné pomůcky (M2.3): hráč nosí přilbu i ochranné kalhoty se štítkem `ochrana_pila` (`Wardrobe.has_saw_gear`).
func has_gear(id: int) -> bool:
	var p: Player = world.players.get(id)
	return p != null and Wardrobe.has_saw_gear(p.outfit)


func _check_gear(id: int, p: Player, tool_id: String) -> void:
	if has_gear(id):
		return
	world.notify(id, "show_message", ["Bez ochranných pomůcek riskuješ úraz.", 3.0])
	if randf() < float(HURT_NO_GEAR.get(tool_id, 0.05)):
		var dmg := randf_range(8.0, 25.0) if tool_id == "motorova_pila" else randf_range(3.0, 10.0)
		p.body.hurt(dmg, "úraz při kácení")


func _start_fall(i: int, base: Vector3, dir: Vector3, h: float, r: float, conifer: bool, feller: int) -> void:
	var crown := clampf(h * (0.16 if conifer else 0.3), 1.0 if conifer else 1.5, 3.0 if conifer else 4.5)
	var length := h * 0.95
	# na jaký úhel dopadne kmen (svah): kmen leží na terénu od paty ke špičce
	var slope := 0.0
	if world.terrain:
		var tip := base + dir * length
		slope = clampf(atan2(world.terrain.height_at(tip.x, tip.z) - base.y, length), -0.45, 0.45)
	var pivot := Node3D.new()
	pivot.name = "PadajiciStrom"
	pivot.position = base
	var mi := MeshInstance3D.new()
	mi.mesh = tree_mesh(h, r, crown, conifer, false)
	pivot.add_child(mi)
	world.add_child(pivot)
	var f := {"pivot": pivot, "base": base, "dir": dir, "axis": Vector3.UP.cross(dir).normalized(), "t": 0.0,
		"len": FELL_MIN_S + h * FELL_PER_M, "final": PI / 2.0 - slope, "h": h, "r": r, "crown": crown,
		"conifer": conifer, "feller": feller, "hit": {}, "slope": slope, "i": i}
	_falls.append(f)
	world.sound.emit(base, "crack", randf_range(0.85, 1.05), 4.0, 260.0)


func _process(delta: float) -> void:
	if world == null:
		return
	for f in _falls.duplicate():
		_fall_step(f, delta)
	_action_sounds(delta)
	_tgt_t -= delta
	if _tgt_t <= 0.0:
		_tgt_t = 0.25
		_update_targets()


func _fall_step(f: Dictionary, delta: float) -> void:
	f["t"] = float(f["t"]) + delta
	var k := clampf(float(f["t"]) / float(f["len"]), 0.0, 1.0)
	var angle := float(f["final"]) * k * k      # zrychlené naklánění (gravitace)
	var pivot: Node3D = f["pivot"]
	if not is_instance_valid(pivot):
		_falls.erase(f)
		return
	pivot.basis = Basis(f["axis"] as Vector3, angle)
	if angle > 0.35:
		_check_hits(f, angle)
	if k >= 1.0:
		_land(f)


## Kdo stojí v cestě padajícímu kmeni (od 15 % délky – u paty stojí kácející), dostane zásah (jednou).
func _check_hits(f: Dictionary, angle: float) -> void:
	var base: Vector3 = f["base"]
	var h: float = f["h"]
	var a: Vector3 = Basis(f["axis"] as Vector3, angle) * Vector3.UP
	var len := h * 0.95
	var hit: Dictionary = f["hit"]
	var dmg := lerpf(HIT_DAMAGE[0], HIT_DAMAGE[1], clampf(h / 30.0, 0.0, 1.0))
	for pid in world.players:
		var p: Player = world.players[pid]
		if p.car != null or hit.has(p):
			continue
		if _tree_dist(base, a, len, float(f["crown"]), p.global_position + Vector3(0, 1.0, 0)) < 0.9:
			hit[p] = true
			p.body.hurt(dmg, "zavalil tě strom")
			p.fall(3.0, "zasažen padajícím stromem")
			world.notify(int(pid), "show_message", ["Strom tě zasáhl!", 3.0])
			world.emit_game_event(int(pid), "tree_hit", {"who": "player", "damage": dmg})
	if world.bots_root:
		for v in world.bots_root.get_children():
			if v is Villager and not hit.has(v):
				if _tree_dist(base, a, len, float(f["crown"]), v.global_position + Vector3(0, 1.0, 0)) < 0.9:
					hit[v] = true
					v.knock(a.slide(Vector3.UP).normalized() * 4.0, 4.0)
	if world.traffic:
		for c in world.traffic.get_children():
			if c is Car and not hit.has(c):
				if _tree_dist(base, a, len, float(f["crown"]), c.global_position + Vector3(0, 0.8, 0)) < 1.6:
					hit[c] = true
					c.damage = minf(c.damage + dmg * 0.6, 100.0)
					world.sound.emit(c.global_position, "crash", 0.8, 2.0, 120.0)


## Vzdálenost bodu od osy padajícího kmene; kolem koruny (horní část) je tolerance větší. 99 = nedotýká se / u paty.
func _tree_dist(base: Vector3, axis: Vector3, len: float, crown: float, q: Vector3) -> float:
	var t := (q - base).dot(axis)
	if t < len * 0.15 or t > len:
		return 99.0
	var d := (q - (base + axis * t)).length()
	return d - (crown * 0.8 if t > len * 0.4 else 0.0)


func _land(f: Dictionary) -> void:
	_falls.erase(f)
	var pivot: Node3D = f["pivot"]
	var base: Vector3 = f["base"]
	var dir: Vector3 = f["dir"]
	var slope: float = f["slope"]
	var h: float = f["h"]
	var axis3 := (dir * cos(slope) + Vector3.UP * sin(slope)).normalized()
	if is_instance_valid(pivot):
		pivot.queue_free()
	var lg := _make_log(base, axis3, h, float(f["r"]), float(f["crown"]), bool(f["conifer"]), false)
	logs.append(lg)
	_trim_logs()
	var mid := base + axis3 * h * 0.5
	world.sound.emit(mid, "thud", randf_range(0.8, 1.0), 6.0, 260.0)
	_dust(base + axis3 * h * 0.7 + Vector3(0, 0.5, 0), float(f["crown"]))


func _make_log(base: Vector3, axis3: Vector3, h: float, r: float, crown: float, conifer: bool, branched: bool) -> Log:
	var lg := Log.new()
	lg.name = "PadlyKmen"
	lg.height = h
	lg.length = h * 0.95
	lg.radius = r
	lg.crown_r = crown
	lg.conifer = conifer
	lg.branched = branched
	lg.collision_layer = 1
	lg.collision_mask = 0
	lg.set_meta("surface", "strom")
	lg.transform = Transform3D(Basis(Quaternion(Vector3.UP, axis3)), base + Vector3(0, r * 0.9, 0))
	var mi := MeshInstance3D.new()
	mi.name = "Model"
	mi.mesh = tree_mesh(h, r, crown, conifer, branched)
	lg.add_child(mi)
	var cs := CollisionShape3D.new()
	var s := CylinderShape3D.new()
	s.radius = maxf(r * 0.7, 0.12)
	s.height = lg.use_length() if branched else lg.length * 0.7
	cs.shape = s
	cs.position = Vector3(0, s.height * 0.5, 0)
	lg.add_child(cs)
	world.add_child(lg)
	lg.target = {"pos": lg.global_position + axis3 * h * 0.3, "r": 0.9, "kind": "log", "node": lg}
	world.register_target(lg.target)
	return lg


func _trim_logs() -> void:
	while logs.size() > MAX_LOGS:
		_remove_log(logs[0])


func _remove_log(lg: Log) -> void:
	logs.erase(lg)
	if is_instance_valid(lg):
		world.unregister_target(lg.target)
		lg.queue_free()


## Prach a listí při dopadu.
func _dust(pos: Vector3, crown: float) -> void:
	var pt := CPUParticles3D.new()
	pt.one_shot = true
	pt.amount = 48
	pt.lifetime = 2.0
	pt.explosiveness = 0.95
	pt.direction = Vector3.UP
	pt.spread = 75.0
	pt.initial_velocity_min = 1.2
	pt.initial_velocity_max = 4.0 + crown * 0.5
	pt.gravity = Vector3(0, -5.0, 0)
	pt.scale_amount_min = 0.7
	pt.scale_amount_max = 1.6
	pt.color = Color(0.4, 0.4, 0.18)
	var bm := BoxMesh.new()
	bm.size = Vector3(0.12, 0.02, 0.09)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	bm.material = m
	pt.mesh = bm
	pt.position = pos
	world.add_child(pt)
	pt.emitting = true
	get_tree().create_timer(3.5).timeout.connect(pt.queue_free)


# ------------------------------------------------------------------ zpracování kmene

func _on_lop(id: int, _def: Dictionary, aim: Dictionary, ok: bool) -> void:
	var lg := _log_of(aim)
	var p: Player = world.players.get(id)
	if not ok or lg == null or p == null or lg.branched:
		return
	lg.branched = true
	lg.rebuild()
	var cs := lg.get_child(lg.get_child_count() - 1) as CollisionShape3D
	if cs and cs.shape is CylinderShape3D:
		(cs.shape as CylinderShape3D).height = lg.use_length()
		cs.position = Vector3(0, lg.use_length() * 0.5, 0)
	var n := clampi(int(lg.crown_r * 2.0) + 2, 3, 10)
	p.add_item(Vyhlasky.FRESH_ITEM, n)              # čerstvé větve: schnou ~30 dní (Vyhlasky)
	if world.vyhlasky:
		world.vyhlasky.add_fresh(id, n)
	world.notify(id, "show_message", ["Máš: %d× %s" % [n, ItemsDB.name_of(Vyhlasky.FRESH_ITEM)], 2.5])
	world.emit_game_event(id, "log_lopped", {"pos": lg.base_point(), "length": lg.use_length()})     # M3.3 lesní dělník


func _on_cut(id: int, _def: Dictionary, aim: Dictionary, ok: bool) -> void:
	var lg := _log_of(aim)
	if not ok or lg == null or not lg.branched:
		return
	var n := clampi(int(roundf(lg.use_length() / SPALEK_LEN)), 1, MAX_SPALKY)
	var a := lg.axis()
	var base := lg.base_point()
	var r := lg.radius
	var perp := a.cross(Vector3.UP)
	for k in n:
		var q := base + a * (SPALEK_LEN * (float(k) + 0.5))
		q += perp.normalized() * ((randf() - 0.5) * 0.25) if perp.length() > 0.01 else Vector3.ZERO
		_make_block(q, r)
	_remove_log(lg)
	world.notify(id, "show_message", ["Rozřezáno na %d špalků." % n, 2.5])
	world.emit_game_event(id, "log_cut", {"pos": base, "blocks": n})     # M3.3 lesní dělník


func _make_block(pos: Vector3, r: float) -> StaticBody3D:
	var bh := 0.45
	var gy := world.terrain.height_at(pos.x, pos.z) if world.terrain else pos.y
	var k := MeshKit.new()
	k.cylinder(Vector3(0, bh * 0.5, 0), r * 0.95, r, bh, BARK, Vector3.ZERO, 10)
	k.cylinder(Vector3(0, bh + 0.004, 0), r * 0.9, r * 0.9, 0.01, CUT_FACE, Vector3.ZERO, 10)
	var b := StaticBody3D.new()
	b.name = "Spalek"
	b.collision_layer = 1
	b.collision_mask = 0
	b.set_meta("surface", "strom")
	b.set_meta("r", r)
	b.position = Vector3(pos.x, gy, pos.z)
	MeshKit.mesh_instance(b, k.commit(MeshKit.vc_material(0.9)), 120.0)
	var cs := CollisionShape3D.new()
	var s := CylinderShape3D.new()
	s.radius = r
	s.height = bh
	cs.shape = s
	cs.position = Vector3(0, bh * 0.5, 0)
	b.add_child(cs)
	world.add_child(b)
	b.set_meta("target", {"pos": b.position + Vector3(0, 0.3, 0), "r": 0.6, "kind": "block", "node": b})
	world.register_target(b.get_meta("target"))
	blocks.append(b)
	while blocks.size() > MAX_BLOCKS:
		_remove_block(blocks[0])
	return b


## M2.10 (`Cargo`): postaví špalek na zem (položení nákladu, vyložení z vozíku).
func put_block(pos: Vector3, r: float) -> StaticBody3D:
	return _make_block(pos, r)


## M2.10 (`Cargo`): špalek zmizí ze země (hráč ho vzal na rameno / naložil).
func take_block(b: StaticBody3D) -> void:
	_remove_block(b)


func _remove_block(b: StaticBody3D) -> void:
	blocks.erase(b)
	if is_instance_valid(b):
		world.unregister_target(b.get_meta("target"))
		b.queue_free()


func _on_split(id: int, _def: Dictionary, aim: Dictionary, ok: bool) -> void:
	var t: Dictionary = aim.get("target", {})
	var b = t.get("node")
	var p: Player = world.players.get(id)
	if not ok or b == null or not is_instance_valid(b) or p == null:
		return
	_remove_block(b)
	p.add_item("polena", POLENA_PER_SPALEK)
	world.notify(id, "show_message", ["Máš: %d× %s" % [POLENA_PER_SPALEK, ItemsDB.name_of("polena")], 2.5])


# ------------------------------------------------------------------ cíle a zvuky

## Kmeny jsou dlouhé – cíl `log` se posouvá k nejbližšímu bodu osy kmene u hráče, ať sedí kužel pohledu.
func _update_targets() -> void:
	for lg in logs:
		if not is_instance_valid(lg):
			continue
		var pl := world.nearest_player(lg.global_position)
		if pl == null or pl.global_position.distance_to(lg.global_position) > lg.length + 12.0:
			continue
		lg.target["pos"] = lg.closest_to(pl.global_position)


func _action_sounds(delta: float) -> void:
	if world.action_runner == null:
		return
	for id in world.action_runner.runs.keys():
		var r: Dictionary = world.action_runner.runs[id]
		var aid := String(r["action"])
		if not aid in ["pokacet", "odvetvit", "rozrezat", "stipat"]:
			continue
		var p: Player = world.players.get(id)
		if p == null:
			continue
		var tool_id := String(r.get("tool", ""))
		_snd_t[id] = float(_snd_t.get(id, 0.0)) - delta
		if float(_snd_t[id]) <= 0.0:
			_snd_t[id] = float(SOUND_GAP.get(tool_id, 0.7))
			var saw := tool_id == "motorova_pila"
			world.sound.emit(p.global_position, "saw" if saw else "chop", randf_range(0.9, 1.1), 0.0,
				HEAR_SAW if saw else HEAR_AXE)


# ------------------------------------------------------------------ zákon

## Zóna pozemku: "own" (zahrada vlastního domu / pronajatá zahrada), "road", "settled" (cizí zahrada), "forest", "other".
## `id` = hráč (M1.7: vlastník domu vs. nájemník bytu; výchozí místní hráč).
func zone_at(pos: Vector3, id := 1) -> String:
	var home: Place = world.places.get("domov")
	var own_house := world.estate == null or world.estate.owns_house(id)
	if own_house and home and Vector2(pos.x - home.door.x, pos.z - home.door.z).length() < OWN_GARDEN_R:
		return "own"
	if not own_house and world.garden != null and world.garden.in_plot(pos, RENTED_MARGIN):
		return "own"
	if world.fauna:
		if world.fauna.settle_at(pos.x, pos.z) > 0.5:
			return "settled"
		if world.fauna.forest_at(pos.x, pos.z) > 0.5:
			return "forest"
	return "other"


## Někdo, kdo pokácení uvidí / uslyší do `r` m: vesničan, obsluha míst (myslivec), hlídka policie.
## (M4.4: tenký obal nad `World.witness_reported` – nahlásí-li někdo čin; `id` = pachatel, pro přátelství.)
func witness_near(pos: Vector3, r: float, id := -1) -> bool:
	return world.witness_reported(id, pos, "les", r, r)


## Které přestupky by pokácení na místě způsobilo: [id přestupku, …]. Vlastní zahrada = nic.
func offenses_for(id: int, pos: Vector3, criminal: bool) -> Array:
	var zone := zone_at(pos, id)
	if zone == "own":
		return []
	var out := []
	if world.dist_to_roads(Vector2(pos.x, pos.z)) < ROAD_R:
		out.append("ohrozeni_provozu_kaceni")
	var theft := "kradez_dreva_trestna" if criminal else "kradez_dreva"
	match zone:
		"settled":
			out.append("poskozeni_cizi_veci")
			out.append(theft)
		"forest":
			if not world.has_permit(id, "kaceni", pos):
				out.append("kaceni_bez_povoleni")
				out.append(theft)
		_:
			out.append(theft)        # DOPLNIT: pole a louky mimo les / zástavbu – výchozí volba: jen krádež dřeva
	return out


func _check_law(id: int, pos: Vector3, tool_id: String, value: int) -> void:
	if zone_at(pos, id) == "own":
		return
	var day := _day()
	var dv: Dictionary = daily_value.get(id, {})
	if int(dv.get("day", -1)) != day:
		dv = {"day": day, "sum": 0}
	dv["sum"] = int(dv["sum"]) + value
	daily_value[id] = dv
	var crim := int(dv["sum"]) > CRIME_VALUE_KC
	var offs := offenses_for(id, pos, crim)
	if offs.is_empty():
		return
	var sev := clampf(float(value) / SEVERITY_VALUE_KC, 0.0, 1.0)
	var rep: Reputation = world.reputations.get(id)
	var hear := HEAR_SAW if tool_id == "motorova_pila" else HEAR_AXE
	if witness_near(pos, hear, id):
		world.notify(id, "popup", ["Někdo tě při kácení viděl!", 3.0])
		for oid in offs:
			world.commit_offense(id, oid, {"severity": sev})
		if rep:
			rep.change(-4.0, "pokácel cizí strom", "kácení cizího stromu")
	else:
		world.add_unreported(id, {"kind": "kaceni", "offenses": offs, "pos": [pos.x, pos.y, pos.z], "t": world.clock.minutes,
			"value": value, "severity": sev, "tool": tool_id, "discover_p": 0.3})
		if rep:
			rep.change_karma(KARMA_UNSEEN, "kácení v cizím")


## Nenahlášené činy hráče (M4.6: hajný / policie je později zjistí). Položky viz `_check_law`.
## (M4.4: registr je společný ve `World` – tyto funkce jsou obaly.)
func pending_offenses(id: int) -> Array:
	return world.pending_offenses(id)


## Uplatní nenahlášený čin číslo `idx` (zjištěn): zapíše přestupky a čin odstraní.
func commit_pending(id: int, idx: int) -> void:
	world.commit_pending(id, idx)


# ------------------------------------------------------------------ ukládání

func _v3(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]


func _to_v3(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2])) if a is Array and a.size() >= 3 else Vector3.ZERO


func to_dict(id: int) -> Dictionary:
	var d: Dictionary = trees.to_dict() if trees else {}
	var ls := []
	for lg in logs:
		if is_instance_valid(lg):
			ls.append({"pos": _v3(lg.base_point() - Vector3(0, lg.radius * 0.9, 0)), "axis": _v3(lg.axis()), "h": lg.height, "r": lg.radius,
				"crown": lg.crown_r, "conifer": lg.conifer, "branched": lg.branched})
	d["logs"] = ls
	var bs := []
	for b in blocks:
		if is_instance_valid(b):
			bs.append({"pos": _v3(b.position), "r": float(b.get_meta("r", 0.2))})
	d["blocks"] = bs
	d["daily"] = daily_value.get(id, {})
	return d


## Vrátí svět do uloženého stavu (starý save bez klíče = žádné pokácené stromy, kmeny ani špalky).
func restore(d: Dictionary, id: int) -> void:
	for f in _falls:
		if is_instance_valid(f["pivot"]):
			(f["pivot"] as Node).queue_free()
	_falls.clear()
	for lg in logs.duplicate():
		_remove_log(lg)
	for b in blocks.duplicate():
		_remove_block(b)
	if trees:
		trees.from_dict(d)
	for e in d.get("logs", []):
		var pos := _to_v3(e.get("pos"))
		var ax := _to_v3(e.get("axis"))
		if ax.length() < 0.5:
			continue
		var lg := _make_log(pos, ax.normalized(), float(e.get("h", 8.0)), float(e.get("r", 0.2)),
			float(e.get("crown", 2.0)), bool(e.get("conifer", false)), bool(e.get("branched", false)))
		logs.append(lg)
	for e in d.get("blocks", []):
		var q := _to_v3(e.get("pos"))
		_make_block(q, float(e.get("r", 0.2)))
	daily_value[id] = (d.get("daily", {}) as Dictionary).duplicate(true)
