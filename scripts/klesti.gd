## Hromada klestí u domu (M4.4 část B) – objekt ve světě, jedna na hráče, který vlastní dům (`Estate.owns_house`).
##
## - Hromada leží 3 m vpravo od dveří domu, je to cíl `klesti_hromada` (`World.register_target`, `data.pid` = majitel)
##   a má vizuál z klestí (suché tmavší, čerstvé světlejší).
## - Akce `slozit_vetve`: všechny čerstvé větve z kapsy (`vetve_cerstve`) se složí na hromadu a schnou jako dávky ve
##   `Vyhlasky` (`DRY_DAYS`, rychleji za sucha, pomaleji za deště); suché `vetve` z kapsy jdou rovnou do suchých.
##   Akce `vzit_vetve`: suché klestí z hromady do kapsy (nejvíc `MAX_TAKE` najednou). Suché větve pak jdou do ohně.
## - Sušení: `_process` každých `TICK_MIN` herních minut.
## - Ukládání: klíč `klesti` v záznamu hráče (`to_dict(id)` / `restore(id, d)`); starý save = prázdná hromada.
## - Zjednodušení: hromada nesleduje kusy zvlášť (jako `Vyhlasky`). Byt bez pozemku hromadu nemá (otevřený bod).
class_name Klesti
extends Node3D

const TICK_MIN := 60.0                 # herní minuty mezi průchody sušení
const TICK_S := 2.0                    # reálné s mezi kontrolou nových hráčů
const MAX_TAKE := 20                   # nejvíc suchých větví z hromady najednou
const PILE_OFFSET := Vector3(3.0, 0.0, 0.0)   # m od dveří domu (vpravo)
const TARGET_R := 1.8                  # m – dosah cíle hromady
const KIND := "klesti_hromada"
const FRESH_ITEM := "vetve_cerstve"
const DRY_ITEM := "vetve"
const DRY_DROUGHT_K := 1.5             # stejné ladění jako `Vyhlasky` (sucho zrychluje)
const DRY_RAIN_K := 0.4                # déšť zpomaluje
const VIS_MAX := 30                    # víc klestí hromada vizuálně neroste
const COL_DRY := Color(0.4, 0.3, 0.18)
const COL_FRESH := Color(0.45, 0.4, 0.22)

var world: World
var items := {}                        # id hráče → {cerstve: [{n, dny}], suche: int}
var spots := {}                        # id hráče → {pos: Vector3, mi: MeshInstance3D, target: Dictionary}
var _last_min := -1.0
var _t := 0.0


func setup(w: World) -> void:
	world = w
	name = "Klesti"
	Actions.set_handler("slozit_vetve", _on_stack)
	Actions.set_handler("vzit_vetve", _on_take)
	Actions.set_target_check("slozit_vetve", _check_stack)
	Actions.set_target_check("vzit_vetve", _check_take)


# ------------------------------------------------------------------ hromada hráče

func _state(id: int) -> Dictionary:
	if not items.has(id):
		items[id] = {"cerstve": [], "suche": 0}
	return items[id]


## Vytvoří hromadu u domu hráče `id` (jen vlastníkům domu, jednou). Volá se průběžně z `_process`.
func _ensure(id: int) -> void:
	if spots.has(id) or world.estate == null or not world.estate.owns_house(id):
		return
	var door: Vector3 = world.estate.home_door(id)
	if door == Vector3.INF:
		return
	var pos := door + PILE_OFFSET
	pos.y = world.terrain.height_at(pos.x, pos.z) if world.terrain else door.y
	var target := {"pos": pos + Vector3(0, 0.5, 0), "r": TARGET_R, "kind": KIND, "data": {"pid": id}}
	world.register_target(target)
	spots[id] = {"pos": pos, "mi": null, "target": target}
	_build(id)


## Cíl hromady patří hráči `id` (`aim.data.pid`).
func _is_mine(aim: Dictionary, id: int) -> bool:
	return int((aim.get("data", {}) as Dictionary).get("pid", -1)) == id


func _check_stack(aim: Dictionary, id: int) -> String:
	if not _is_mine(aim, id):
		return "Tahle hromada klestí není tvoje."
	var p: Player = world.players.get(id)
	if p == null or (p.item_count(FRESH_ITEM) + p.item_count(DRY_ITEM)) <= 0:
		return "Nemáš v kapse žádné větve."
	return ""


func _check_take(aim: Dictionary, id: int) -> String:
	if not _is_mine(aim, id):
		return "Tahle hromada klestí není tvoje."
	if int(_state(id)["suche"]) <= 0:
		return "Na hromadě nejsou suché větve (čerstvé musí proschnout)."
	return ""


func _on_stack(id: int, _def: Dictionary, _aim: Dictionary, ok: bool) -> void:
	var p: Player = world.players.get(id)
	if not ok or p == null or not spots.has(id):
		return
	var st := _state(id)
	var n_fresh := p.item_count(FRESH_ITEM)
	if n_fresh > 0 and p.remove_item(FRESH_ITEM, n_fresh):
		(st["cerstve"] as Array).append({"n": n_fresh, "dny": 0.0})
	var n_dry := p.item_count(DRY_ITEM)
	if n_dry > 0 and p.remove_item(DRY_ITEM, n_dry):
		st["suche"] = int(st["suche"]) + n_dry
	_build(id)
	world.sound.emit(spots[id]["pos"], "thud", randf_range(1.0, 1.2), -8.0, 40.0)
	world.notify(id, "show_message", ["Na hromadě klestí: %d čerstvých, %d suchých." % [_fresh_total(id), int(st["suche"])], 2.5])


func _on_take(id: int, _def: Dictionary, _aim: Dictionary, ok: bool) -> void:
	var p: Player = world.players.get(id)
	if not ok or p == null:
		return
	var st := _state(id)
	var n := mini(int(st["suche"]), MAX_TAKE)
	if n <= 0:
		return
	st["suche"] = int(st["suche"]) - n
	p.add_item(DRY_ITEM, n)
	_build(id)
	world.notify(id, "show_message", ["Vzal sis %d suchých větví z hromady." % n, 2.0])


func _fresh_total(id: int) -> int:
	var t := 0
	for b in _state(id)["cerstve"]:
		t += int((b as Dictionary).get("n", 0))
	return t


# ------------------------------------------------------------------ ukládání

## Stav hromady hráče `id` (klíč `klesti` v záznamu hráče). Poloha se odvozuje z domu.
func to_dict(id: int) -> Dictionary:
	var st := _state(id)
	return {"cerstve": (st["cerstve"] as Array).duplicate(true), "suche": int(st["suche"])}


## Starý save bez klíče = prázdná hromada.
func restore(id: int, d: Dictionary) -> void:
	items[id] = {"cerstve": (d.get("cerstve", []) as Array).duplicate(true), "suche": int(d.get("suche", 0))}
	_build(id)


# ------------------------------------------------------------------ sušení

func _process(delta: float) -> void:
	if world == null or world.clock == null:
		return
	_t -= delta
	if _t <= 0.0:
		_t = TICK_S
		for pid in world.players.keys():
			_ensure(int(pid))
	var m := world.clock.minutes
	if _last_min < 0.0 or m < _last_min:
		_last_min = m                  # první průchod nebo skok v kalendáři
		return
	if m - _last_min >= TICK_MIN:
		_tick(m - _last_min)
		_last_min = m


func _tick(dt_min: float) -> void:
	var rate := 1.0
	if world.weather:
		rate *= 1.0 + (DRY_DROUGHT_K - 1.0) * clampf(world.weather.drought, 0.0, 1.0)
		rate *= lerpf(1.0, DRY_RAIN_K, clampf(world.weather.rain_recent, 0.0, 1.0))
	var dd := dt_min / 1440.0 * rate
	var dry_days := float(Vyhlasky.DRY_DAYS)
	for id in items.keys():
		var st: Dictionary = items[id]
		var keep := []
		var changed := false
		for b in st["cerstve"]:
			var bd: Dictionary = b
			bd["dny"] = float(bd.get("dny", 0.0)) + dd
			if float(bd["dny"]) < dry_days:
				keep.append(bd)
			else:
				st["suche"] = int(st["suche"]) + int(bd.get("n", 0))
				changed = true
		st["cerstve"] = keep
		if changed and spots.has(id):
			_build(int(id))


# ------------------------------------------------------------------ vizuál

## Hromada: větve kladené vrstvami (suché dole, čerstvé nahoře); vizuálně nejvýš `VIS_MAX` kusů.
func _build(id: int) -> void:
	if not spots.has(id):
		return
	var sp: Dictionary = spots[id]
	if sp["mi"] and is_instance_valid(sp["mi"]):
		(sp["mi"] as MeshInstance3D).queue_free()
	var st := _state(id)
	var n_dry := int(st["suche"])
	var n_all := mini(n_dry + _fresh_total(id), VIS_MAX) + 2     # pár kusů tam leží vždycky
	var k := MeshKit.new()
	for sx in [-0.6, 0.6]:
		k.box(Vector3(sx, 0.05, 0), Vector3(0.12, 0.1, 2.0), COL_DRY)
	for i in n_all:
		var layer := i / 5
		var col := i % 5
		var z := -0.8 + col * 0.36 + (0.18 if layer % 2 == 1 else 0.0)
		var y := 0.22 + layer * 0.26
		var c := COL_DRY if i < mini(n_dry, VIS_MAX) else COL_FRESH
		k.cylinder(Vector3(0, y, minf(z, 0.9)), 0.12, 0.12, 1.7, c, Vector3(0, 0, PI * 0.5), 6)
	var mi := MeshKit.mesh_instance(self, k.commit(MeshKit.vc_material(0.95)), 160.0)
	mi.position = sp["pos"]
	sp["mi"] = mi
