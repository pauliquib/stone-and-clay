## Myslivecký hajný a rybářská stráž (M4.6): NPC na obchůzce, slyší výstřely, hledají pytláky a kontrolují doklady.
## Jedna třída, dvě instance: `World.gamekeeper` (hajný – lesy, slyší výstřely, svědek vždy hlásí) a
## `World.rybar_straz` (rybářská stráž – obchůzka, jen na službě o víkendu ráno, kontroluje rybaření).
## Svědci: `World.add_witness_source(gamekeeper.witness_candidates)` (jen na službě). Doklady a kurzy se kupují
## v myslivecké chatě (`interactables`), složený eTest vydá doklad přes `test_passed` (volá `Computer.record_test`).
## Stav per hráč (zaplacené kurzy) se ukládá v klíči `gamekeeper` (`to_dict` / `from_dict`).
class_name Gamekeeper
extends Node3D

# ------------------------------------------------------------------ laditelné hodnoty

const HAJNY := "hajny"
const STRAZ := "straz"
const WALK_SPEED := 1.4                # m/s obchůzka
const RUN_SPEED := 3.2                 # m/s k výstřelu / k místu činu
const PATROL_R := 900.0                # m od chaty – okruh obchůzky
const HEAR_SHOT_R := 1500.0            # m – výstřel, který hajný slyší
const HEAR_P := 0.7                    # šance, že hajný výstřel vyslechne a vyrazí
const INVESTIGATE_S := 240.0           # s – jak dlouho hledá místo činu
const CONTROL_R := 15.0                # m – dosah kontroly dokladů
const CHECK_CD_MIN := 90.0             # herních minut mezi kontrolami téhož hráče
const CARCASS_NEAR_R := 8.0            # m – nelegální úlovek u hráče (kus na zemi)
const CAPSULE_H := 1.75                # m – výška modelu NPC (procedurální kapsle)
const CHATA_R := 12.0                  # m od dveří chaty – nabídka spolku
const TEST_DOC := {"zbrojni": "zbrojni", "lovecky": "lovecky_listek", "rybarsky": "rybarsky_listek"}   # eTest → doklad
const PRICES := {"zbrojni": 4000, "lovecky_listek": 5000, "rybarsky_listek": 1000,
	"povolenka_lov": 1500, "povolenka_rybolov": 1800}     # kurz / poplatek nebo povolenka (orientačně, ověřit)
const POV_NEEDS := {"povolenka_lov": "lovecky_listek", "povolenka_rybolov": "rybarsky_listek"}
const POV_DAYS := {"povolenka_lov": 30, "povolenka_rybolov": 365}
const DOC_NO := {"zbrojni": "ZBP", "lovecky_listek": "LL", "rybarsky_listek": "RL"}

# ------------------------------------------------------------------ stav

var world: World
var role := HAJNY
var _rng := RandomNumberGenerator.new()
var _center := Vector3.ZERO
var _center_set := false
var _target := Vector3.INF
var _invest_left := 0.0               # s – > 0 = jde na místo činu / hledá
var _on := false
var _acc := 0.0
var _checked := {}                    # id → herní minuta poslední kontroly
var _kurz := {}                       # id → {druh dokladu: true} zaplacené kurzy (jen hajný)


## Připojí hajného nebo stráž. Volat až po `add_child` (nastaví globální polohu).
func setup(w: World, r: String) -> void:
	world = w
	role = r
	name = "Hajny" if r == HAJNY else "RybarskaStraz"
	_rng.randomize()
	_build_mesh()
	_ensure_center()
	global_position = _center


func _build_mesh() -> void:
	var mi := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.3
	cap.height = CAPSULE_H
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.32, 0.18) if role == HAJNY else Color(0.2, 0.3, 0.45)
	cap.material = mat
	mi.mesh = cap
	mi.position = Vector3(0, CAPSULE_H * 0.5, 0)
	add_child(mi)


## Střed obchůzky = dveře chaty (myslivec); když místa ještě nejsou, zkusí to znovu.
func _ensure_center() -> void:
	if _center_set or world == null or not world.places.has("chata"):
		return
	var pl: Place = world.places["chata"]
	_center = pl.door
	_center_set = true


func _flat_dist(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()


func _msg(id: int, text: String, dur := 4.0) -> void:
	world.notify(id, "show_message", [text, dur])


# ------------------------------------------------------------------ pohyb a služba

func _process(delta: float) -> void:
	if world == null or world.clock == null:
		return
	_ensure_center()
	_on = _on_duty()
	visible = _on
	if not _on:
		return
	_move(delta)
	_acc += delta
	if _acc >= 1.0:
		_acc = 0.0
		_check_players()


## Hajný je v lese pořád; rybářská stráž jen o víkendu ráno (5–12 h, sobota a neděle).
func _on_duty() -> bool:
	if role == HAJNY:
		return true
	var h := world.clock.hour()
	return world.clock.weekday() >= 5 and h >= 5.0 and h < 12.0


func _move(delta: float) -> void:
	if _invest_left > 0.0:
		_invest_left = maxf(0.0, _invest_left - delta)
		if _invest_left <= 0.0:
			_target = Vector3.INF
	if _target == Vector3.INF:
		_pick_patrol()
	var d := _flat_dist(_target)
	if d < 2.0:
		if _invest_left <= 0.0:
			_pick_patrol()
		return
	var dir := Vector3(_target.x - global_position.x, 0.0, _target.z - global_position.z).normalized()
	var sp := RUN_SPEED if _invest_left > 0.0 else WALK_SPEED
	global_position += dir * minf(sp * delta, d)
	global_position.y = world.terrain.height_at(global_position.x, global_position.z) if world.terrain else 0.0
	look_at(global_position + dir, Vector3.UP)


func _pick_patrol() -> void:
	if world.fauna:
		_target = world.fauna.random_point(_center, PATROL_R, "forest", _rng)
	else:
		_target = _center + Vector3(_rng.randf_range(-PATROL_R, PATROL_R), 0.0, _rng.randf_range(-PATROL_R, PATROL_R))


# ------------------------------------------------------------------ slyšení a svědci

## Události světa: výstřel (`gunshot`) a pytlácký čin (`poaching`) – hajný jde k místu činu.
func on_event(_id: int, kind: String, data: Dictionary) -> void:
	if role != HAJNY or not _on or (kind != "gunshot" and kind != "poaching"):
		return
	var at = data.get("pos", Vector3.INF)
	if not (at is Vector3) or (at as Vector3) == Vector3.INF:
		return
	if _flat_dist(at) > HEAR_SHOT_R or _rng.randf() > HEAR_P:
		return
	_target = at
	_invest_left = INVESTIGATE_S


## Zdroj svědků pro `World.witness_check`: hajný / stráž na službě vidí a slyší; nahlásí vždy (role „hajny“).
func witness_candidates(_id: int, _pos: Vector3, _see_r: float, _hear_r: float) -> Array:
	if not _on:
		return []
	return [{"node": self, "name": "hajný" if role == HAJNY else "rybářská stráž", "persona": null, "role": "hajny"}]


# ------------------------------------------------------------------ kontrola dokladů

func _check_players() -> void:
	for id in world.players:
		var p: Player = world.players[id]
		if p == null or not is_instance_valid(p) or p.inside != "" or p.car != null or p.horse != null:
			continue
		if p.global_position.distance_to(global_position) > CONTROL_R:
			continue
		if world.clock.minutes - float(_checked.get(id, -1.0e9)) < CHECK_CD_MIN:
			continue
		if not _suspicious(id, p):
			continue
		_checked[id] = world.clock.minutes
		_control(id)
		return                        # jedna kontrola naráz


func _suspicious(id: int, p: Player) -> bool:
	if role == HAJNY:
		var armed := p.item_count("puska") > 0 or Weapons.WEAPONS.has(p.equipped)
		return armed or not _carcasses_near(id, p).is_empty()
	return world.fishing != null and world.fishing.sessions.has(id)


func _carcasses_near(id: int, p: Player) -> Array:
	var out: Array = []
	if world.hunting == null:
		return out
	for c in world.hunting.carcasses:
		if c.owner_id != id or c.legal:
			continue
		if c.carried_by == id or c.pos.distance_to(p.global_position) < CARCASS_NEAR_R:
			out.append(c)
	return out


## Co je v nepořádku: [{text, offense (id zákona, nebo ""), seize (bool)}].
func _issues(id: int) -> Array:
	var out: Array = []
	var p: Player = world.players.get(id)
	if p == null:
		return out
	if role == HAJNY:
		var cs := _carcasses_near(id, p)
		if not cs.is_empty():
			out.append({"text": "nelegální úlovek (zvěř bez práva)", "offense": "pytlactvi", "seize": false})
		var gun := p.item_count("puska") > 0 or bool((Weapons.WEAPONS.get(p.equipped, {}) as Dictionary).get("firearm", false))
		if gun and not world.has_permit(id, "zbrojni", p.global_position):
			out.append({"text": "zbraň bez zbrojního oprávnění", "offense": "", "seize": true})
	elif world.fishing != null and world.fishing.sessions.has(id):
		if not (world.has_permit(id, "rybarsky_listek", p.global_position) and world.has_permit(id, "povolenka_rybolov", p.global_position)):
			out.append({"text": "rybaření bez lístku a povolenky", "offense": "rybarske_pytlactvi", "seize": false})
	return out


func _control(id: int) -> void:
	var head := "Dobrý den, myslivecká stráž. Doklady prosím." if role == HAJNY \
		else "Dobrý den, rybářská stráž. Lístek a povolenku prosím."
	var opts := [
		["Ukázat doklady", _show_docs.bind(id)],
		["Zapírat", _deny.bind(id)],
		["Utéct (hajný volá policii)", _flee.bind(id)],
		["Nechat být", func(): pass],
	]
	world.notify(id, "open_menu", ["Kontrola", head, opts])      # zprávy hráči jen přes World.notify


func _apply(id: int, issues: Array) -> void:
	var texts := ""
	for i in issues:
		texts += ("; " if texts != "" else "") + String(i["text"])
		if String(i.get("offense", "")) != "":
			world.commit_offense(id, String(i["offense"]), {"severity": 0.5})
		if bool(i.get("seize", false)) and world.weapons:
			world.weapons.police_check(id, "hajny")
	_msg(id, "Zapisuji: %s." % texts, 5.0)


func _show_docs(id: int) -> void:
	var issues := _issues(id)
	if issues.is_empty():
		_msg(id, "V pořádku, lovu zdar." if role == HAJNY else "V pořádku, hezký den u vody.")
		return
	_apply(id, issues)


func _deny(id: int) -> void:
	var issues := _issues(id)
	if issues.is_empty():
		_msg(id, "Nevěří ti, ale nemá na tebe nic. Dám na tebe pozor.")
		return
	_apply(id, issues)


func _flee(id: int) -> void:
	var p: Player = world.players.get(id)
	if p == null:
		return
	p.wanted_until = maxf(p.wanted_until, world.clock.minutes + 120.0)
	world.notify(id, "police_banner", ["Hajný utíká za tebou a volá policii!", 4.0])
	var issues := _issues(id)
	if not issues.is_empty():
		_apply(id, issues)


# ------------------------------------------------------------------ myslivecká chata: kurzy a povolenky

## Nabídka u chaty (jen hajný): kurzy, povolenky. Akce dostává id hráče.
func interactables(id: int) -> Array:
	var out: Array = []
	if role != HAJNY or world == null:
		return out
	var p: Player = world.players.get(id)
	if p == null or p.inside != "" or p.car != null or _center.distance_to(p.global_position) > CHATA_R:
		return out
	out.append({"pos": _center + Vector3(0, 0.3, 0), "r": 3.0, "kind": "custom",
		"text": "Myslivecký a rybářský spolek – kurzy a povolenky", "action": _office_menu})
	return out


func _office_menu(id: int) -> void:
	var opts := [
		["Zbrojní průkaz – kurz a poplatek (%d Kč)" % PRICES["zbrojni"], _enroll.bind(id, "zbrojni")],
		["Lovecký lístek – kurz (%d Kč)" % PRICES["lovecky_listek"], _enroll.bind(id, "lovecky_listek")],
		["Povolenka k lovu na 30 dní (%d Kč)" % PRICES["povolenka_lov"], _buy.bind(id, "povolenka_lov")],
		["Rybářský lístek – kurz (%d Kč)" % PRICES["rybarsky_listek"], _enroll.bind(id, "rybarsky_listek")],
		["Povolenka k rybolovu na rok (%d Kč)" % PRICES["povolenka_rybolov"], _buy.bind(id, "povolenka_rybolov")],
		["Zavřít", func(): pass],
	]
	world.notify(id, "open_menu", ["Spolek v chatě", "Kurz se zaplatí na místě, zkoušku složíš na počítači doma (eTesty).", opts])


func _has_kurz(id: int, kind: String) -> bool:
	return bool((_kurz.get(id, {}) as Dictionary).get(kind, false))


func _enroll(id: int, kind: String) -> void:
	var p: Player = world.players.get(id)
	if p == null:
		return
	if _has_kurz(id, kind) or world.permits.has(id, kind):
		_msg(id, "Tenhle kurz už máš – polož test na počítači doma.")
		return
	var price: int = PRICES[kind]
	if p.money < price:
		_msg(id, "Na kurz nemáš dost peněz (%d Kč)." % price)
		return
	p.money -= price
	if not _kurz.has(id):
		_kurz[id] = {}
	(_kurz[id] as Dictionary)[kind] = true
	world.play_sfx(id, "cash")
	_msg(id, "Kurz zaplacen. Test najdeš v počítači doma (eTesty).", 5.0)


func _buy(id: int, kind: String) -> void:
	var p: Player = world.players.get(id)
	if p == null:
		return
	var need := String(POV_NEEDS[kind])
	if not world.permits.has(id, need):
		_msg(id, "Nejdřív potřebuješ: %s." % Permits.KINDS[need][0])
		return
	var price: int = PRICES[kind]
	if p.money < price:
		_msg(id, "Povolenku nemáš za co koupit (%d Kč)." % price)
		return
	p.money -= price
	world.permits.renew(id, kind, int(world.clock.jd()) + int(POV_DAYS[kind]), "%s-%04d" % [kind.substr(0, 3).to_upper(), id])
	world.play_sfx(id, "cash")
	_msg(id, "Povolenka zakoupena: %s." % Permits.KINDS[kind][0], 5.0)


## Složený eTest (volá `Computer.record_test`): doklad se vydá jen po zaplaceném kurzu v chatě.
func test_passed(id: int, test_id: String) -> void:
	if not TEST_DOC.has(test_id):
		return
	var kind: String = TEST_DOC[test_id]
	if world.permits.has(id, kind):
		return
	if not _has_kurz(id, kind):
		_msg(id, "Test je složený, ale doklad vydají až po kurzu v myslivecké chatě.", 5.0)
		return
	world.permits.grant(id, kind, "%s-%04d" % [DOC_NO[kind], id])
	world.notify(id, "popup", ["Doklad vydán: %s" % Permits.KINDS[kind][0], 5.0])
	world.emit_game_event(id, "doklad_vydan", {"kind": kind})


# ------------------------------------------------------------------ ukládání

func to_dict(id: int) -> Dictionary:
	return {"kurz": (_kurz.get(id, {}) as Dictionary).duplicate()}


func from_dict(id: int, d: Dictionary) -> void:
	_kurz[id] = (d.get("kurz", {}) as Dictionary).duplicate()
