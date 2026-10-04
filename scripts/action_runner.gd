## Výběr cíle a průběh kontextových akcí hráčů (M0.4), jeden uzel ve `World` (`World.action_runner`).
##
## Cíle: další kroky je registrují přes `World.register_target({pos, r, kind, node?, data?})`; pro „ground“
## a „water“ se cíl určí paprskem z hlavy hráče ve směru pohledu (max. `AIM_RANGE` m).
## Průběh: LMB → `start(id, action_id, aim)`; akce trvá `Actions.duration`, hráč se nesmí hýbat
## (pohyb / skok / nabídka / Esc / výměna nástroje akci přeruší bez odměny), výdrž ubývá průběžně.
## Konec: šance na neúspěch (půl XP), jinak `gives`, opotřebení nástroje, XP, handler a událost
## `action_done` {id, action, target_kind, pos, ok} (napojí se zákon, úkoly…).
## HUD: `Hud.action_progress(název, 0..1)` (−1 = skrýt), `Hud.set_prompt` s důvodem, proč to nejde.
class_name ActionRunner
extends Node

const AIM_RANGE := 4.0
const ROD_RANGE := 8.0               # dosah na vodu s udicí v ruce (M2.7)
const TARGET_CONE := 0.55            # min. cos úhlu mezi pohledem a směrem k registrovanému cíli
const GRASS_MIN_ROAD_DIST := 3.5     # m od nejbližší silnice, aby šlo o trávu

var world: World
var targets: Array = []              # registrované cíle
var runs := {}                       # id hráče → {action, aim, t, len}


func _init(w: World) -> void:
	world = w
	name = "ActionRunner"


# ------------------------------------------------------------------ cíle

func register_target(t: Dictionary) -> void:
	if not targets.has(t):
		targets.append(t)


func unregister_target(t: Dictionary) -> void:
	targets.erase(t)


## Registrované cíle do `r` m od hráče (nejbližší první); cíle s uvolněným `node` se zahodí.
func targets_near(id: int, r: float) -> Array:
	var p: Player = world.players.get(id)
	if p == null:
		return []
	var out := []
	for t in targets.duplicate():
		if t.has("node") and not is_instance_valid(t["node"]):
			targets.erase(t)
			continue
		if (t["pos"] as Vector3).distance_to(p.global_position) <= r + float(t.get("r", 1.0)):
			out.append(t)
	out.sort_custom(func(a, b): return (a["pos"] as Vector3).distance_squared_to(p.global_position) \
		< (b["pos"] as Vector3).distance_squared_to(p.global_position))
	return out


## Směr pohledu hráče (z yaw / pitch – nezávisí na kameře, funguje i bez klienta).
func aim_dir(p: Player) -> Vector3:
	return Basis(Vector3.UP, p.yaw) * Basis(Vector3.RIGHT, p.pitch) * Vector3.FORWARD


func aim_origin(p: Player) -> Vector3:
	return p.global_position + Vector3(0, 1.55, 0)


## Kam hráč míří: {kind, pos, target?, grass?} nebo {} když do dosahu nic nespadlo.
func aim_point(id: int) -> Dictionary:
	var p: Player = world.players.get(id)
	if p == null or p.car != null or p.horse != null:
		return {}
	var dir := aim_dir(p)
	var origin := aim_origin(p)
	# 1) registrovaný cíl v zorném kuželu
	for t in targets_near(id, AIM_RANGE):
		var to: Vector3 = (t["pos"] as Vector3) - origin
		if to.length() < 0.05 or to.normalized().dot(dir) >= TARGET_CONE:
			return {"kind": t["kind"], "pos": t["pos"], "target": t}
	# 1b) strom před hráčem (M2.1; tisíce stromů se neregistrují jako cíle, TreeManager je hledá sám)
	if world.trees != null:
		var tt := world.trees.aim_tree(p, dir)
		if not tt.is_empty():
			return tt
	# 1c) záhon zahrady / pole (M2.4; mřížka 1 × 1 m, `Garden.aim_cell` míří paprskem jen poblíž záhonů)
	if world.garden != null:
		var gz := world.garden.aim_cell(p, dir, origin)
		if not gz.is_empty():
			return gz
	# 2) země / voda paprskem (s udicí v ruce až `ROD_RANGE` m, ale dál jen voda – M2.7 rybaření)
	var rod := p.equipped in Fishing.ROD_TOOLS
	var reach := ROD_RANGE if rod else AIM_RANGE
	var space := p.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * reach, 1)
	q.exclude = [p.get_rid()]
	var hit := space.intersect_ray(q)
	var pos: Vector3
	if hit.is_empty():
		# pohled ke špičkám bot / do dálky: zkus zem před hráčem
		if dir.y > -0.15:
			return {}
		pos = origin + dir * reach
		if world.terrain == null or pos.y > world.terrain.height_at(pos.x, pos.z) + 0.6:
			return {}
	else:
		pos = hit["position"]
	if world.water:
		var wi := world.water.info_at(pos.x, pos.z)
		if float(wi.get("depth", 0.0)) > 0.05:
			return {"kind": "water", "pos": pos, "data": wi}
	if rod and Vector2(pos.x - p.global_position.x, pos.z - p.global_position.z).length() > AIM_RANGE:
		return {}                      # dál než běžný dosah cílí udice jen na vodu
	if world.terrain == null or absf(pos.y - world.terrain.height_at(pos.x, pos.z)) > 0.35:
		return {}                      # zeď, střecha, strom… ne terén
	var grass := world.dist_to_roads(Vector2(pos.x, pos.z)) > GRASS_MIN_ROAD_DIST
	return {"kind": "ground", "pos": pos, "grass": grass}


# ------------------------------------------------------------------ výběr akce

## Nabídka pro HUD: {action, def, aim, reason, text} nejlepší akce pro to, na co hráč míří, nebo {}.
## Bez důvodu (`reason == ""`) má přednost před akcí, která nejde.
func hint(id: int) -> Dictionary:
	var p: Player = world.players.get(id)
	if p == null or runs.has(id):
		return {}
	if Weapons.is_weapon(p.equipped):
		return {}                      # zbraň v ruce: LMB = výstřel / natažení (M2.8), kontextové akce se nenabízejí
	var aim := aim_point(id)
	if aim.is_empty():
		return {}
	var sk: Skills = world.skills.get(id)
	var best := {}
	for aid in Actions.DEFS:
		var def: Dictionary = Actions.DEFS[aid]
		var tk := String(def.get("target", "any"))
		if tk != "any" and tk != aim["kind"]:
			continue
		var why := ""
		if String(def.get("needs", "")) == "grass" and not bool(aim.get("grass", false)):
			why = "Tady není tráva."
		if why == "":
			why = Actions.reason(def, p, sk)
		if why == "":
			why = Actions.target_reason(aid, aim, id)
		var lvl_txt := ""
		if sk and String(def.get("skill", "")) != "":
			lvl_txt = " (%s %d)" % [Skills.skill_name(def["skill"]), Actions.required_level(def, p.equipped)]
		var c := {"action": aid, "def": def, "aim": aim, "reason": why,
			"text": "%s%s" % [def["name"], lvl_txt]}
		# M2.7: akce, které nejdou kvůli chybějícímu nástroji, se řadí až za ty, které nejdou z jiného důvodu
		# (udice v ruce u vody ukazuje „Čekáš na záběr / Chybí návnada“, ne „Chybí nástroj: Konev“)
		c["rank"] = 0 if why == "" else (2 if not Actions.tool_ok(def, p.equipped) else 1)
		if best.is_empty() or int(c["rank"]) < int(best["rank"]):
			best = c
	return best


# ------------------------------------------------------------------ průběh

func is_running(id: int) -> bool:
	return runs.has(id)


## Spustí akci; vrací true, když se rozběhla (jinak hráči řekne proč ne).
func start(id: int, action_id: String, aim: Dictionary) -> bool:
	var p: Player = world.players.get(id)
	if p == null or runs.has(id) or not Actions.exists(action_id) or aim.is_empty():
		return false
	var def: Dictionary = Actions.DEFS[action_id]
	var sk: Skills = world.skills.get(id)
	var why := Actions.reason(def, p, sk)
	if why != "":
		world.notify(id, "show_message", [why, 2.0])
		return false
	why = Actions.target_reason(action_id, aim, id)
	if why != "":
		world.notify(id, "show_message", [why, 2.5])
		return false
	var len_s := Actions.duration(def, sk) * Actions.time_mod(action_id, aim, p.equipped)
	runs[id] = {"action": action_id, "aim": aim, "t": 0.0, "len": len_s, "tool": p.equipped}
	p.visual.start_action(String(def.get("anim", "kneel")))
	world.emit_game_event(id, "action_started", {"action": action_id, "target_kind": aim["kind"], "pos": aim["pos"]})
	return true


## Přeruší akci hráče bez odměny (pohyb, nabídka, výměna nástroje…). `msg` = volitelná hláška.
func cancel(id: int, msg := "") -> void:
	if not runs.has(id):
		return
	runs.erase(id)
	var p: Player = world.players.get(id)
	if p:
		p.visual.stop_action()
	world.notify(id, "action_progress", ["", -1.0])
	if msg != "":
		world.notify(id, "show_message", [msg, 1.6])


func _process(delta: float) -> void:
	for id in runs.keys():
		_tick(id, delta)


func _tick(id: int, delta: float) -> void:
	var p: Player = world.players.get(id)
	var r: Dictionary = runs[id]
	if p == null:
		runs.erase(id)
		return
	var def: Dictionary = Actions.DEFS[r["action"]]
	var aim: Dictionary = r["aim"]
	# --- přerušení
	if p.car != null or p.horse != null or p.fallen > 0.0 or p.busy or p.controls_locked:
		cancel(id)
		return
	if p.input.move.length() > 0.1 or p.input.jump:
		cancel(id, "Přerušeno.")
		return
	if p.equipped != r["tool"] or not Actions.tool_ok(def, p.equipped):
		cancel(id, "Přerušeno – změna nástroje.")
		return
	if aim.has("tree") and world.trees != null and world.trees.is_felled(int(aim["tree"])):
		cancel(id, "Strom už je pokácený.")
		return
	if aim.has("target") and aim["target"].has("node") and not is_instance_valid(aim["target"]["node"]):
		cancel(id, "Cíl zmizel.")
		return
	# --- průběh a výdrž (regenerace výdrže se po dobu akce blokuje)
	r["t"] = float(r["t"]) + delta
	var len_s: float = r["len"]
	p.drain_stamina(float(def.get("stamina", 0.0)) * delta / maxf(len_s, 0.1))
	world.notify(id, "action_progress", [def["name"], clampf(float(r["t"]) / len_s, 0.0, 1.0)])
	if float(r["t"]) >= len_s:
		runs.erase(id)
		_finish(id, String(r["action"]), p, def, aim)


func _finish(id: int, aid: String, p: Player, def: Dictionary, aim: Dictionary) -> void:
	var sk: Skills = world.skills.get(id)
	p.visual.stop_action()
	world.notify(id, "action_progress", ["", -1.0])
	var rep: Reputation = world.reputations.get(id)
	var ok := randf() >= Actions.fail_chance(def, sk, rep.luck() if rep else 0.0)
	var xp := float(def.get("xp", 0))
	if String(def.get("tool", "")) != "" and p.equipped != "":
		var tool_id := p.equipped
		if not p.wear_tool(tool_id, int(def.get("wear", 1))):
			world.notify(id, "show_message", ["%s se rozbil." % ItemsDB.name_of(tool_id), 3.0])
	if ok:
		var got := []
		var gives: Dictionary = def.get("gives", {})
		for item in gives:
			p.add_item(item, int(gives[item]))
			got.append("%d× %s" % [int(gives[item]), ItemsDB.name_of(item) if ItemsDB.exists(item) else item])
		if not got.is_empty():
			world.notify(id, "show_message", ["Máš: %s" % ", ".join(got), 2.5])
	else:
		xp *= 0.5
		world.notify(id, "show_message", ["Nepovedlo se – %s." % String(def["name"]).to_lower(), 2.5])
	if xp > 0.0 and String(def.get("skill", "")) != "":
		world.give_xp(id, def["skill"], xp, aid)
	var h := Actions.handler(aid)
	if h.is_valid():
		h.call(id, def, aim, ok)
	world.emit_game_event(id, "action_done", {"id": id, "action": aid, "target_kind": aim["kind"],
		"pos": aim["pos"], "ok": ok})
