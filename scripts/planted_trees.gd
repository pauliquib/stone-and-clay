## Zasazené stromy (M2.5): dynamická vrstva nad mapovými stromy z `TreeManager`.
##
## Záznam stromu = Dictionary {id, sp (druh), pos, rot, proto, planted (Clock.jd), age (dny růstu), cal (kalendářní dny od výsadby),
## health 0..1, moist (dny vláhy), prot (ochranný obal), felled (den pokácení, −1 = stojí), py / pk (rok a počet natrhaného ovoce),
## owner (id hráče), rewarded}. Čísla stromů začínají na `TreeManager.DYN_BASE`; `TreeManager` je přijímá stejnými dotazy
## jako mapové stromy, takže kácení (`Forestry`), míření (`ActionRunner`) i pařezy fungují beze změny.
##
## Vzhled: vlastní MultiMesh po prototypech (sdílí `MapLoader.shared_protos` a jejich sezónní shader – listí se barví jako u ostatních;
## bez nich nouzový model z `Forestry.tree_mesh`), kmen má kolizi od výšky `COLLIDE_MIN_H`, ovoce v koruně a ochranné obaly
## jsou další MultiMeshe.
##
## Růst: měřítko `START_SCALE` → 1 za `years × 365 / GROWTH_SPEEDUP` dnů růstu; v zimě strom spí, bez zálivky v prvních
## `ESTABLISH_DAYS` dnech zdraví klesá až sazenice uschne, srnci ožírají neobalené sazenice. Denní krok se dopočítá i po spánku
## a skoku data (`_advance_days`). Uložení: `to_dict` / `restore` (klíč `planted` v uložení `Forestry`).
class_name PlantedTrees
extends Node3D

const START_SCALE := 0.15                 # velikost čerstvé sazenice (~1 m)
## DOPLNIT: rychlost růstu – herní roky jsou dlouhé, proto 6× rychleji než realita (výchozí z promptu); ladit podle pocitu
const GROWTH_SPEEDUP := 6.0
const ESTABLISH_DAYS := 60                # tolik dní po výsadbě strom potřebuje vláhu; potom se ujme
const DORMANT_MONTHS := [11, 12, 1, 2]    # zimní klid: strom neroste a nevysychá
const WATER_DAYS := 4.0                   # dní vláhy po zalití
const RAIN_DAYS := 3.0                    # dní vláhy po dešti
const TREE_CAN_COST := 2                  # kolik „záhonů“ vody z konve spotřebuje zalití stromu
const DRY_DAMAGE := 0.06                  # ztráta zdraví za suchý den v prvních ESTABLISH_DAYS
const HEAL_WET := 0.05                    # zotavení zdraví za den s vláhou
const HEAL_SLOW := 0.02                   # zotavení ujatého stromu
const DRY_GROWTH := 0.5                   # násobek růstu v suchu
const SKIP_RAIN_BASE := 0.15              # šance deště za přeskočený den = základ + K × vlhko posledních dní
const SKIP_RAIN_K := 0.35
const MAX_CATCHUP_DAYS := 4000
const CHECK_S := 1.0
const BROWSE_R := 60.0                    # m – srnec takhle blízko může sazenici ožrat
const BROWSE_P := 0.15                    # šance za den
const BROWSE_DAMAGE := 0.5
const BROWSE_MAX_S := 0.5                 # ožírají se jen sazenice menší než tohle měřítko
const GUARD_OUTGROWN := 0.55              # od této velikosti už obal nechrání a zmizí
const MIN_TREE_DIST := 2.0                # m od jiného stromu
const MIN_BUILDING_DIST := 2.0            # m od zdi
const MIN_ROAD_DIST := 3.0                # m od silnice
const PLOT_MARGIN := 1.0                  # m od záhonů
const COLLIDE_MIN_H := 1.5                # kmen je pevný od této výšky stromu
const FRUIT_MIN_S := 0.7                  # ovocný strom plodí od této velikosti
const FRUIT_CAP := 10                     # ovoce na plně vzrostlém stromě v plné sezóně
const MAX_FRUIT := 700
const REWARD_DAYS := 60                   # po tolika dnech se strom „ujal“ → karma a pověst
const REWARD_MAX_PER_YEAR := 5
const NEIGHBOR_RESPECT := -1.0            # sázení na cizím pozemku (zástavba mimo vlastní zahradu) – jen háček, žádný přestupek

## Druhy: sazenice (ItemsDB), ovoce (ItemsDB), roky do plné velikosti (před zrychlením), výška a šířkové měřítko dospělého stromu
## (stejné jednotky jako trees.bin: sx, sy), prototypy modelu (0–2 listnáč, 3+ jehličnan), barva koruny, barva plodů.
const SPECIES := {
	"jablon": {"name": "Jabloň", "item": "sazenice_jablon", "fruit": "jablko", "years": 4.0, "h": 6.5, "sx": 2.6,
		"protos": [0, 1, 2], "leaf": Color(0.2, 0.36, 0.1), "fruit_color": Color(0.82, 0.1, 0.07)},
	"slivon": {"name": "Slivoň", "item": "sazenice_slivon", "fruit": "svestka", "years": 4.0, "h": 5.5, "sx": 2.4,
		"protos": [0, 1, 2], "leaf": Color(0.22, 0.34, 0.12), "fruit_color": Color(0.32, 0.12, 0.42)},
	"hrusen": {"name": "Hrušeň", "item": "sazenice_hrusen", "fruit": "hruska", "years": 4.0, "h": 8.0, "sx": 2.8,
		"protos": [0, 1, 2], "leaf": Color(0.19, 0.35, 0.1), "fruit_color": Color(0.6, 0.72, 0.2)},
	"tresen": {"name": "Třešeň", "item": "sazenice_tresen", "fruit": "tresne", "years": 4.0, "h": 9.0, "sx": 3.2,
		"protos": [0, 1, 2], "leaf": Color(0.2, 0.37, 0.11), "fruit_color": Color(0.6, 0.05, 0.1)},
	"dub": {"name": "Dub", "item": "sazenice_dub", "fruit": "", "years": 8.0, "h": 17.0, "sx": 5.0,
		"protos": [0, 1, 2], "leaf": Color(0.16, 0.3, 0.08), "fruit_color": Color.WHITE},
	"buk": {"name": "Buk", "item": "sazenice_buk", "fruit": "", "years": 8.0, "h": 18.0, "sx": 5.0,
		"protos": [0, 1, 2], "leaf": Color(0.18, 0.34, 0.1), "fruit_color": Color.WHITE},
	"smrk": {"name": "Smrk", "item": "sazenice_smrk", "fruit": "", "years": 6.0, "h": 18.0, "sx": 3.8,
		"protos": [3, 5], "leaf": Color(0.06, 0.14, 0.06), "fruit_color": Color.WHITE},
	"borovice": {"name": "Borovice", "item": "sazenice_borovice", "fruit": "", "years": 6.0, "h": 15.0, "sx": 3.4,
		"protos": [4], "leaf": Color(0.07, 0.16, 0.06), "fruit_color": Color.WHITE},
}
const SPECIES_ORDER := ["jablon", "slivon", "hrusen", "tresen", "dub", "buk", "smrk", "borovice"]
const GUARD_COLOR := Color(0.75, 0.92, 0.75, 0.4)

var world: World
var mgr: TreeManager
var recs := {}                            # id → záznam stromu
var next_id := TreeManager.DYN_BASE
var rewards := {}                         # id hráče → {"y": rok, "n": kolikrát odměněn}

var _last_jd := -1
var _rained_today := false
var _chk := 0.0
var _rt := 0.0
var _dirty := true
var _fruit_dirty := true
var _last_ff := -1.0
var _mmis := {}                           # prototyp → MultiMeshInstance3D
var _fallback := {}                       # prototyp → nouzový Mesh
var _fruit_mmi: MultiMeshInstance3D
var _guard_mmi: MultiMeshInstance3D
var _body: StaticBody3D


func setup(w: World, m: TreeManager) -> void:
	world = w
	mgr = m
	name = "ZasazeneStromy"
	Actions.set_handler("zasadit", _on_plant)
	Actions.set_handler("zalevat_strom", _on_water)
	Actions.set_handler("obalit", _on_guard)
	Actions.set_handler("natrhat_ovoce", _on_pick)
	Actions.set_handler("strom_info", _on_info)
	Actions.set_target_check("zasadit", _check_plant)
	Actions.set_target_check("zalevat_strom", _check_water)
	Actions.set_target_check("obalit", _check_guard)
	Actions.set_target_check("natrhat_ovoce", _check_pick)
	Actions.set_target_check("strom_info", _check_info)
	_body = StaticBody3D.new()
	_body.name = "KmenyZasazenych"
	_body.collision_layer = 1
	_body.collision_mask = 0
	_body.set_meta("surface", "strom")
	add_child(_body)


# ------------------------------------------------------------------ data stromu (pro TreeManager)

func count() -> int:
	return recs.size()


func has_tree(i: int) -> bool:
	return recs.has(i)


func is_felled(i: int) -> bool:
	return recs.has(i) and int((recs[i] as Dictionary)["felled"]) >= 0


## Čísla pokácených stromů (pařezy).
func felled_ids() -> Array:
	var out := []
	for i in recs:
		if int((recs[i] as Dictionary)["felled"]) >= 0:
			out.append(i)
	return out


func rec_of(aim: Dictionary) -> Dictionary:
	var i := int(aim.get("tree", -1))
	return recs.get(i, {}) if i >= TreeManager.DYN_BASE else {}


func pos_of(i: int) -> Vector3:
	return (recs[i] as Dictionary)["pos"] if recs.has(i) else Vector3.ZERO


## Dokončenost růstu 0..1.
func growth(rec: Dictionary) -> float:
	var spec: Dictionary = SPECIES[rec["sp"]]
	return clampf(float(rec["age"]) * GROWTH_SPEEDUP / (float(spec["years"]) * 365.0), 0.0, 1.0)


## Velikost 0.15 (sazenice) … 1 (dospělý strom).
func size_of(rec: Dictionary) -> float:
	return lerpf(START_SCALE, 1.0, growth(rec))


func height_of(i: int) -> float:
	if not recs.has(i):
		return 1.0
	var rec: Dictionary = recs[i]
	return float(SPECIES[rec["sp"]]["h"]) * size_of(rec)


func scale_of(i: int) -> float:
	if not recs.has(i):
		return 1.0
	var rec: Dictionary = recs[i]
	return float(SPECIES[rec["sp"]]["sx"]) * size_of(rec)


func proto_of(i: int) -> int:
	return int((recs[i] as Dictionary)["proto"]) if recs.has(i) else 0


func color_of(i: int) -> Color:
	return _tint(recs[i]) if recs.has(i) else Color(0.18, 0.32, 0.1)


func species_name(rec: Dictionary) -> String:
	return String(SPECIES[rec["sp"]]["name"])


## Nejbližší stojící zasazený strom do `r` m (vodorovně), −1 když žádný.
func nearest(pos: Vector3, r: float) -> int:
	var best := -1
	var bd := r * r
	for i in recs:
		var rec: Dictionary = recs[i]
		if int(rec["felled"]) >= 0:
			continue
		var q: Vector3 = rec["pos"]
		var d2 := (q.x - pos.x) * (q.x - pos.x) + (q.z - pos.z) * (q.z - pos.z)
		if d2 < bd:
			bd = d2
			best = int(i)
	return best


## Kandidát na cíl akce před hráčem (stejná pravidla jako `TreeManager.aim_tree`): číslo stromu s vzdáleností od povrchu kmene
## menší než `best_dist`, jinak −1.
func aim_candidate(pp: Vector3, flat: Vector3, reach: float, best_dist: float) -> int:
	var best := -1
	var bd := best_dist
	for i in recs:
		var rec: Dictionary = recs[i]
		if int(rec["felled"]) >= 0:
			continue
		var q: Vector3 = rec["pos"]
		var to := Vector3(q.x - pp.x, 0.0, q.z - pp.z)
		var dist := to.length() - mgr.trunk_radius(int(i))
		if dist > reach:
			continue
		if dist > 0.3 and to.normalized().dot(flat) < 0.55:
			continue
		if dist < bd:
			bd = dist
			best = int(i)
	return best


## Pokácení: strom zmizí z MultiMeshe a kolize (`TreeManager` postaví pařez). false, když neexistuje nebo už leží.
func fell(i: int, day: int) -> bool:
	if not recs.has(i) or is_felled(i):
		return false
	(recs[i] as Dictionary)["felled"] = maxi(day, 0)
	_dirty = true
	_fruit_dirty = true
	return true


func _tint(rec: Dictionary) -> Color:
	var c: Color = SPECIES[rec["sp"]]["leaf"]
	var h := float(int(rec["id"]) % 7) / 7.0 - 0.5
	return Color(c.r + h * 0.04, c.g + h * 0.05, c.b + h * 0.02)


# ------------------------------------------------------------------ výsadba

## Proč se na `pos` nedá sázet ("" = jde). Silnice, voda, záhon, jiný strom (i mapový) a zeď do 2 m.
func can_plant(pos: Vector3) -> String:
	if world.water != null and float(world.water.info_at(pos.x, pos.z).get("depth", 0.0)) > 0.0:
		return "Do vody se sázet nedá."
	if world.dist_to_roads(Vector2(pos.x, pos.z)) < MIN_ROAD_DIST:
		return "Na silnici ani těsně u ní se sázet nesmí."
	if world.garden != null and world.garden.in_plot(pos, PLOT_MARGIN):
		return "Do záhonu ne – najdi volné místo."
	if mgr != null and mgr.nearest_tree(pos, MIN_TREE_DIST) >= 0:
		return "Moc blízko jiného stromu (aspoň %d m)." % roundi(MIN_TREE_DIST)
	if _near_wall(pos):
		return "Moc blízko budovy nebo zdi (aspoň %d m)." % roundi(MIN_BUILDING_DIST)
	return ""


## Zeď (statická kolize vrstvy 1) do `MIN_BUILDING_DIST` m – osm vodorovných paprsků ve výšce 1,2 m.
func _near_wall(pos: Vector3) -> bool:
	var space := world.get_world_3d().direct_space_state
	var o := pos + Vector3(0, 1.2, 0)
	for k in 8:
		var a := TAU * float(k) / 8.0
		var q := PhysicsRayQueryParameters3D.create(o, o + Vector3(cos(a), 0, sin(a)) * MIN_BUILDING_DIST, 1)
		if not space.intersect_ray(q).is_empty():
			return true
	return false


## Sazenice, kterou hráč zasadí (první druh v pořadí `SPECIES_ORDER`, který má v inventáři). DOPLNIT: výběr druhu v nabídce.
func pick_species(p: Player) -> String:
	for sp in SPECIES_ORDER:
		if p.item_count(String(SPECIES[sp]["item"])) > 0:
			return sp
	return ""


## Založí strom (bez kontrol). Vrací jeho číslo.
func plant(sp: String, pos: Vector3, owner: int, age := 0.0) -> int:
	var spec: Dictionary = SPECIES[sp]
	var id := next_id
	next_id += 1
	var pl: Array = spec["protos"]
	var p := pos
	if world.terrain != null:
		p.y = world.terrain.height_at(p.x, p.z) - 0.1
	recs[id] = {"id": id, "sp": sp, "pos": p, "rot": randf() * TAU, "proto": int(pl[id % pl.size()]),
		"planted": world.clock.jd() if world.clock != null else 0, "age": age, "cal": 0, "health": 1.0, "moist": WATER_DAYS,
		"prot": false, "felled": -1, "py": 0, "pk": 0, "owner": owner, "rewarded": false}
	_dirty = true
	_fruit_dirty = true
	return id


func _check_plant(aim: Dictionary, id: int) -> String:
	var p: Player = world.players.get(id)
	if p == null:
		return ""
	if pick_species(p) == "":
		return "Nemáš sazenici (Potraviny)."
	return can_plant(aim["pos"])


func _on_plant(id: int, _def: Dictionary, aim: Dictionary, ok: bool) -> void:
	var p: Player = world.players.get(id)
	if p == null or not ok or can_plant(aim["pos"]) != "":
		return
	var sp := pick_species(p)
	if sp == "" or not p.remove_item(String(SPECIES[sp]["item"]), 1):
		return
	plant(sp, aim["pos"], id)
	world.give_xp(id, "zahradnictvi", 15.0, "sázení")
	world.play_sfx(id, "step", 0.6, -2.0)
	world.notify(id, "show_message", ["Zasazeno: %s. Zalévej ji, dokud se neujme (%d dní), a ochraň před zvěří." % [
		String(SPECIES[sp]["name"]).to_lower(), ESTABLISH_DAYS], 4.0])
	var pos: Vector3 = aim["pos"]
	if world.forestry != null and world.forestry.zone_at(pos) == "settled":
		var rep: Reputation = world.reputations.get(id)
		if rep != null:      # háček: sousedovi se výsadba na jeho pozemku nemusí líbit (žádný přestupek)
			rep.change_respect("sousede", NEIGHBOR_RESPECT, "strom zasazený na cizím pozemku")
	world.emit_game_event(id, "tree_planted", {"species": sp, "pos": pos})


# ------------------------------------------------------------------ zálivka, obal, ovoce, prohlídka

func _check_water(aim: Dictionary, id: int) -> String:
	var rec := rec_of(aim)
	if rec.is_empty() or int(rec["felled"]) >= 0:
		return "Tohle není zasazený strom."
	if float(rec["moist"]) >= WATER_DAYS - 0.5:
		return "Půda kolem stromu je ještě vlhká."
	if world.garden != null and not world.garden.can_water(id):
		return "Konev je prázdná."
	return ""


func _on_water(id: int, _def: Dictionary, aim: Dictionary, ok: bool) -> void:
	var p: Player = world.players.get(id)
	var rec := rec_of(aim)
	if p == null or not ok or rec.is_empty():
		return
	rec["moist"] = WATER_DAYS
	rec["health"] = minf(1.0, float(rec["health"]) + HEAL_WET)
	if world.garden != null and world.garden.spend_can(id, p, TREE_CAN_COST) and not world.garden.can_water(id):
		world.notify(id, "show_message", ["Konev je prázdná – naplň ji u kohoutku nebo u vody.", 3.0])


func _check_guard(aim: Dictionary, id: int) -> String:
	var rec := rec_of(aim)
	if rec.is_empty() or int(rec["felled"]) >= 0:
		return "Tohle není zasazený strom."
	if bool(rec["prot"]):
		return "Už je obalená."
	if size_of(rec) >= GUARD_OUTGROWN:
		return "Strom je na obal už moc velký."
	var p: Player = world.players.get(id)
	if p != null and p.item_count("ochranny_obal") <= 0:
		return "Chybí ochranný obal (Potraviny)."
	return ""


func _on_guard(id: int, _def: Dictionary, aim: Dictionary, ok: bool) -> void:
	var p: Player = world.players.get(id)
	var rec := rec_of(aim)
	if p == null or not ok or rec.is_empty() or not p.remove_item("ochranny_obal", 1):
		return
	rec["prot"] = true
	_dirty = true
	world.notify(id, "show_message", ["Sazenice je obalená – srnci ji neožerou.", 2.5])


## Kolik ovoce je teď na stromě k natrhání (roste s velikostí a podle sezóny `TreeDecor.FRUIT`, ubývá natrháním).
func fruit_available(rec: Dictionary) -> int:
	var spec: Dictionary = SPECIES[rec["sp"]]
	if String(spec["fruit"]) == "" or int(rec["felled"]) >= 0 or world.clock == null:
		return 0
	var s := size_of(rec)
	if s < FRUIT_MIN_S or float(rec["health"]) < 0.3:
		return 0
	var ff := Seasons.curve(TreeDecor.FRUIT, world.clock.day_of_year())
	var picked := int(rec["pk"]) if int(rec["py"]) == world.clock.year() else 0
	return maxi(0, floori(float(FRUIT_CAP) * s * ff) - picked)


func _check_pick(aim: Dictionary, _id: int) -> String:
	var rec := rec_of(aim)
	if rec.is_empty() or int(rec["felled"]) >= 0:
		return "Tohle není zasazený strom."
	var spec: Dictionary = SPECIES[rec["sp"]]
	if String(spec["fruit"]) == "":
		return "Tenhle strom neplodí."
	if size_of(rec) < FRUIT_MIN_S:
		return "Ještě je moc mladý (plodí od %d %% velikosti)." % roundi(FRUIT_MIN_S * 100.0)
	if fruit_available(rec) <= 0:
		var ff := Seasons.curve(TreeDecor.FRUIT, world.clock.day_of_year())
		return "Ovoce ještě není zralé (sezóna srpen–říjen)." if ff < 0.05 else "Už je oklepáno."
	return ""


func _on_pick(id: int, _def: Dictionary, aim: Dictionary, ok: bool) -> void:
	var p: Player = world.players.get(id)
	var rec := rec_of(aim)
	if p == null or not ok or rec.is_empty():
		return
	var n := fruit_available(rec)
	if n <= 0:
		return
	var item := String(SPECIES[rec["sp"]]["fruit"])
	p.add_item(item, n)
	if int(rec["py"]) != world.clock.year():
		rec["py"] = world.clock.year()
		rec["pk"] = 0
	rec["pk"] = int(rec["pk"]) + n
	_fruit_dirty = true
	world.give_xp(id, "zahradnictvi", 4.0 + float(n), "sběr ovoce")
	world.notify(id, "show_message", ["Natrháno: %d× %s" % [n, ItemsDB.name_of(item).to_lower()], 2.5])
	world.emit_game_event(id, "harvest", {"crop": String(rec["sp"]), "item": item, "n": n})


func _check_info(aim: Dictionary, _id: int) -> String:
	var rec := rec_of(aim)
	if rec.is_empty() or int(rec["felled"]) >= 0:
		return "Divoký strom – žádné údaje."
	return ""


func info_text(rec: Dictionary) -> String:
	var spec: Dictionary = SPECIES[rec["sp"]]
	var parts := ["%s – vzrostlá z %d %%" % [species_name(rec), roundi(growth(rec) * 100.0)],
		"výška %.1f m" % (float(spec["h"]) * size_of(rec)), "zdraví %d %%" % roundi(float(rec["health"]) * 100.0),
		"půda %s" % ("vlhká" if float(rec["moist"]) > 0.0 else "suchá")]
	if bool(rec["prot"]) and size_of(rec) < GUARD_OUTGROWN:
		parts.append("obalená")
	if int(rec["cal"]) < ESTABLISH_DAYS:
		parts.append("ujme se za %d dní" % (ESTABLISH_DAYS - int(rec["cal"])))
	if String(spec["fruit"]) != "":
		parts.append("plodí od %d %% velikosti" % roundi(FRUIT_MIN_S * 100.0))
	return ", ".join(parts) + "."


func _on_info(id: int, _def: Dictionary, aim: Dictionary, _ok: bool) -> void:
	var rec := rec_of(aim)
	if not rec.is_empty():
		world.notify(id, "show_message", [info_text(rec), 5.0])


# ------------------------------------------------------------------ denní krok

func _process(delta: float) -> void:
	if world == null or world.clock == null:
		return
	_rt -= delta
	if _rt <= 0.0:
		_rt = 0.25
		if _dirty:
			_rebuild()
		if _fruit_dirty:
			_rebuild_fruit()
	_chk -= delta
	if _chk > 0.0:
		return
	_chk = CHECK_S
	var jd := world.clock.jd()
	if recs.is_empty():
		_last_jd = jd
		return
	var w: Weather = world.weather
	if w != null and w.is_raining():
		_rained_today = true
	if _last_jd < 0:
		_last_jd = jd
	elif jd != _last_jd:
		if jd > _last_jd:
			_advance_days(mini(jd - _last_jd, MAX_CATCHUP_DAYS), jd)
		_last_jd = jd
		_rained_today = false
	var ff := Seasons.curve(TreeDecor.FRUIT, world.clock.day_of_year())
	if absf(ff - _last_ff) >= 0.05:
		_last_ff = ff
		_fruit_dirty = true


func _deer_near(pos: Vector3) -> bool:
	if world.fauna == null:
		return false
	for a in world.fauna.animals:
		if is_instance_valid(a) and a.species == "srnec" and not a.dead and (a as Node3D).global_position.distance_to(pos) < BROWSE_R:
			return true
	return false


## Posune růst o `n` herních dnů (spánek, skok času); `today` = dnešní Clock.jd(). První den se počítá se skutečným deštěm,
## přeskočené dny náhodně podle vlhka.
func _advance_days(n: int, today: int) -> void:
	var w: Weather = world.weather
	var raining_now := w != null and w.is_raining()
	var recent := w.rain_recent if w != null else 0.0
	var dead := []
	var browsed := []
	var rewarded := []
	for i in n:
		var month := int(Clock.from_jdn(today - n + 1 + i)["month"])
		var rained := (i == 0 and (_rained_today or raining_now)) or (i > 0 and randf() < SKIP_RAIN_BASE + SKIP_RAIN_K * recent)
		for id in recs.keys():
			var rec: Dictionary = recs[id]
			if int(rec["felled"]) >= 0 or dead.has(id):
				continue
			_grow(rec, rained, month)
			if not bool(rec["prot"]) and size_of(rec) < BROWSE_MAX_S and randf() < BROWSE_P and _deer_near(rec["pos"]):
				rec["health"] = float(rec["health"]) - BROWSE_DAMAGE
				browsed.append(id)
			if float(rec["health"]) <= 0.0:
				dead.append(id)
			elif not bool(rec["rewarded"]) and int(rec["cal"]) >= REWARD_DAYS and float(rec["health"]) >= 0.5:
				rec["rewarded"] = true
				rewarded.append(id)
	for id in browsed:
		if recs.has(id) and not dead.has(id):
			_notify_near((recs[id] as Dictionary)["pos"], "Srnec ožral sazenici – bez obalu ji neuchráníš.")
	for id in dead:
		_notify_near((recs[id] as Dictionary)["pos"], "%s uschla nebo ji zničila zvěř." % species_name(recs[id]))
		recs.erase(id)
	for id in rewarded:
		if recs.has(id):
			_reward(recs[id])
	_dirty = true
	_fruit_dirty = true


func _grow(rec: Dictionary, rained: bool, month: int) -> void:
	rec["cal"] = int(rec["cal"]) + 1
	if rained:
		rec["moist"] = maxf(float(rec["moist"]), RAIN_DAYS)
	var winter := DORMANT_MONTHS.has(month)
	var wet := float(rec["moist"]) > 0.0
	if wet:
		rec["moist"] = maxf(0.0, float(rec["moist"]) - 1.0)
		rec["health"] = minf(1.0, float(rec["health"]) + HEAL_WET)
	elif int(rec["cal"]) < ESTABLISH_DAYS and not winter:
		rec["health"] = float(rec["health"]) - DRY_DAMAGE
	else:
		rec["health"] = minf(1.0, float(rec["health"]) + HEAL_SLOW)
	if winter:
		return
	var thrive := wet or int(rec["cal"]) >= ESTABLISH_DAYS
	rec["age"] = float(rec["age"]) + (1.0 if thrive else DRY_GROWTH) * lerpf(0.4, 1.0, clampf(float(rec["health"]), 0.0, 1.0))


## Strom se ujal: karma +1 a pověst +1 (nejvýš `REWARD_MAX_PER_YEAR`× za rok).
func _reward(rec: Dictionary) -> void:
	var owner := int(rec["owner"])
	var rep: Reputation = world.reputations.get(owner)
	if rep == null or world.clock == null:
		return
	var year := world.clock.year()
	var r: Dictionary = rewards.get(owner, {"y": year, "n": 0})
	if int(r["y"]) != year:
		r = {"y": year, "n": 0}
	if int(r["n"]) < REWARD_MAX_PER_YEAR:
		r["n"] = int(r["n"]) + 1
		rep.change_karma(1.0, "zasazený strom se ujal")
		rep.change(1.0, "Zasazený strom se ujal")
		world.notify(owner, "show_message", ["%s se ujala. Ve vsi si všimli, že nejen kácíš." % species_name(rec), 4.0])
	rewards[owner] = r


func _notify_near(pos: Vector3, text: String) -> void:
	for id in world.players.keys():
		var p: Player = world.players[id]
		if p != null and p.global_position.distance_to(pos) < 120.0:
			world.notify(int(id), "show_message", [text, 4.0])


# ------------------------------------------------------------------ vzhled

func _proto_mesh(p: int) -> Mesh:
	var sh: Array = MapLoader.shared_protos
	if p >= 0 and p < sh.size():
		return sh[p]
	if not _fallback.has(p):           # bez tree_protos.bin: jednoduchý model jednotkové výšky z Forestry
		_fallback[p] = Forestry.tree_mesh(1.0, 0.035, 0.7 if p >= 3 else 0.6, p >= 3, false)
	return _fallback[p]


func _mmi_for(p: int) -> MultiMeshInstance3D:
	if _mmis.has(p):
		return _mmis[p]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.name = "Proto%d" % p
	add_child(mi)
	_mmis[p] = mi
	return mi


func _rebuild() -> void:
	_dirty = false
	var groups := {}                   # prototyp → [[transformace], [barvy]]
	for c in _body.get_children():
		c.queue_free()
	var guards := []
	for i in recs:
		var rec: Dictionary = recs[i]
		if int(rec["felled"]) >= 0:
			continue
		var spec: Dictionary = SPECIES[rec["sp"]]
		var s := size_of(rec)
		var sx := float(spec["sx"]) * s
		var sy := float(spec["h"]) * s
		var pos: Vector3 = rec["pos"]
		var basis := Basis(Vector3.UP, float(rec["rot"])) * Basis.from_scale(Vector3(sx, sy, sx))
		var p := int(rec["proto"])
		if not groups.has(p):
			groups[p] = [[], []]
		groups[p][0].append(Transform3D(basis, pos))
		groups[p][1].append(_tint(rec))
		if sy >= COLLIDE_MIN_H:
			var cs := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = maxf(sx * (0.07 if p >= 3 else 0.09), 0.12)
			cyl.height = maxf(sy * 0.5, COLLIDE_MIN_H)
			cs.shape = cyl
			cs.position = pos + Vector3(0, cyl.height * 0.5, 0)
			_body.add_child(cs)
		if bool(rec["prot"]) and s < GUARD_OUTGROWN:
			guards.append(Transform3D(Basis.from_scale(Vector3(1.0, 0.6 + s, 1.0)), pos + Vector3(0, 0.3 + s * 0.5, 0)))
	for p in _mmis.keys():
		if not groups.has(p):
			(_mmis[p] as MultiMeshInstance3D).multimesh.instance_count = 0
	for p in groups:
		var mi := _mmi_for(p)
		var mm := mi.multimesh
		var g: Array = groups[p]
		mm.mesh = _proto_mesh(p)
		mm.instance_count = (g[0] as Array).size()
		for k in (g[0] as Array).size():
			mm.set_instance_transform(k, g[0][k])
			mm.set_instance_custom_data(k, g[1][k])
	_rebuild_guards(guards)


func _rebuild_guards(guards: Array) -> void:
	if _guard_mmi == null:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.22
		cm.bottom_radius = 0.22
		cm.height = 1.0
		cm.radial_segments = 8
		cm.rings = 1
		var mat := StandardMaterial3D.new()
		mat.albedo_color = GUARD_COLOR
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.roughness = 0.9
		cm.material = mat
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = cm
		_guard_mmi = MultiMeshInstance3D.new()
		_guard_mmi.multimesh = mm
		_guard_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_guard_mmi)
	var gm := _guard_mmi.multimesh
	gm.instance_count = guards.size()
	for k in guards.size():
		gm.set_instance_transform(k, guards[k])


func _rebuild_fruit() -> void:
	_fruit_dirty = false
	if _fruit_mmi == null:
		var sm := SphereMesh.new()
		sm.radius = 0.07
		sm.height = 0.14
		sm.radial_segments = 6
		sm.rings = 3
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 0.4
		sm.material = mat
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = sm
		_fruit_mmi = MultiMeshInstance3D.new()
		_fruit_mmi.multimesh = mm
		_fruit_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_fruit_mmi)
	var xf := []
	var cols := []
	for i in recs:
		var rec: Dictionary = recs[i]
		var n := fruit_available(rec)
		if n <= 0:
			continue
		var spec: Dictionary = SPECIES[rec["sp"]]
		var h := float(spec["h"]) * size_of(rec)
		var crown := clampf(h * 0.3, 0.5, 4.5)
		var pos: Vector3 = rec["pos"]
		var rng := RandomNumberGenerator.new()
		rng.seed = int(i) * 7919
		for k in n:
			if xf.size() >= MAX_FRUIT:
				break
			var a := rng.randf() * TAU
			var rr := crown * sqrt(rng.randf()) * 0.85
			var y := h * 0.62 + rng.randf_range(-0.5, 0.5) * crown
			xf.append(Transform3D(Basis.IDENTITY, pos + Vector3(cos(a) * rr, y, sin(a) * rr)))
			cols.append(spec["fruit_color"])
	var fm := _fruit_mmi.multimesh
	fm.instance_count = xf.size()
	for k in xf.size():
		fm.set_instance_transform(k, xf[k])
		fm.set_instance_color(k, cols[k])


# ------------------------------------------------------------------ ukládání

func to_dict() -> Dictionary:
	var ts := []
	for i in recs:
		var r: Dictionary = recs[i]
		var p: Vector3 = r["pos"]
		ts.append({"id": int(i), "sp": String(r["sp"]), "x": snappedf(p.x, 0.01), "y": snappedf(p.y, 0.01), "z": snappedf(p.z, 0.01),
			"rot": snappedf(float(r["rot"]), 0.001), "proto": int(r["proto"]), "planted": int(r["planted"]),
			"age": snappedf(float(r["age"]), 0.01), "cal": int(r["cal"]), "health": snappedf(float(r["health"]), 0.01),
			"moist": snappedf(float(r["moist"]), 0.1), "prot": bool(r["prot"]), "felled": int(r["felled"]),
			"py": int(r["py"]), "pk": int(r["pk"]), "owner": int(r["owner"]), "rewarded": bool(r["rewarded"])})
	var rw := {}
	for id in rewards:
		rw[str(id)] = rewards[id]
	return {"trees": ts, "next_id": next_id, "rewards": rw}


## Starý save bez klíče = žádné zasazené stromy.
func restore(d: Dictionary) -> void:
	recs.clear()
	rewards.clear()
	for e in d.get("trees", []):
		var sp := String(e.get("sp", ""))
		if not SPECIES.has(sp):
			continue
		var id := int(e.get("id", -1))
		if id < TreeManager.DYN_BASE:
			continue
		var pl: Array = SPECIES[sp]["protos"]
		recs[id] = {"id": id, "sp": sp, "pos": Vector3(float(e.get("x", 0.0)), float(e.get("y", 0.0)), float(e.get("z", 0.0))),
			"rot": float(e.get("rot", 0.0)), "proto": int(e.get("proto", pl[0])), "planted": int(e.get("planted", 0)),
			"age": float(e.get("age", 0.0)), "cal": int(e.get("cal", 0)), "health": float(e.get("health", 1.0)),
			"moist": float(e.get("moist", 0.0)), "prot": bool(e.get("prot", false)), "felled": int(e.get("felled", -1)),
			"py": int(e.get("py", 0)), "pk": int(e.get("pk", 0)), "owner": int(e.get("owner", 1)),
			"rewarded": bool(e.get("rewarded", false))}
	next_id = maxi(int(d.get("next_id", TreeManager.DYN_BASE)), TreeManager.DYN_BASE)
	for id in recs:
		next_id = maxi(next_id, int(id) + 1)
	var rw: Dictionary = d.get("rewards", {})
	for k in rw:
		rewards[int(k)] = {"y": int((rw[k] as Dictionary).get("y", 0)), "n": int((rw[k] as Dictionary).get("n", 0))}
	_last_jd = -1
	_rained_today = false
	_dirty = true
	_fruit_dirty = true
