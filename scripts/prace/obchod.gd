## Prodavač/ka v Potravinách (M3.3) – pracoviště práce „Prodavač/ka v Potravinách“ (`data/prace.json` → `prodavac`,
## ranní / odpolední směna – `smeny_volba`). Jeden uzel ve `World` (`World.obchod`), vzniká v `World.add_player`; stav per hráč.
##
## - **Pokladna** (úkol `obchod_pokladna`, typ „modul“): když je úkol na řadě, přijde zákazník (`Npc`, smyšlené jméno) k pokladně
##   (v postaveném interiéru `Interior.spots["pokladna"]`, jinak ke stánku před obchodem). LMB na pokladnu (akce `markovat`)
##   otevře minihru v nabídce: 1) kolik nákup dělá (součet z cen `Place.OFFERS["obchod"]`), 2) zákazník platí bankovkou – vrať
##   drobné mincemi (200 / 100 / 50 / 20 / 10 / 5 / 2 / 1 Kč). Správně = spokojený zákazník (hodnocení +); málo = zákazník si
##   řekne; moc = manko (strhne se z nevyplacené mzdy). Kdo nechá zákazníka čekat `PATIENCE_S`, ten odejde naštvaný.
## - **Regály** (`obchod_regaly`, typ „akce“ `doplnit_regal`): vzít bednu se zbožím u skladu (akce `vzit_bednu` → náklad na rameni
##   M2.10, `Cargo.shoulder_new`) a vybalit ji do regálu (uvnitř čela regálů, venku stánek).
## - **Pečivo** (`obchod_pecivo`, jen 6–8 h): u parkoviště obchodu čekají přepravky od pekárny – převzít (akce `prevzit_pecivo`),
##   bedna jde rovnou na rameno.
## Stav se neukládá (zákazník a bedna jsou jen na směně; rozdělaná směna se po načtení rozběhne znovu).
class_name ProdavacPrace
extends Node3D

const JOB_ID := "prodavac"
const PLACE := "obchod"
const TASK_TILL := "obchod_pokladna"
const TASK_SHELF := "obchod_regaly"
const TASK_BREAD := "obchod_pecivo"
const CUSTOMER_WAIT := [8.0, 20.0]   # s mezi zákazníky
const PATIENCE_S := 120.0            # s – zákazník čeká u pokladny
const NOTES := [100, 200, 500, 1000, 2000]
const COINS := [200, 100, 50, 20, 10, 5, 2, 1]
## Co zákazníci kupují (ceny z `Place.OFFERS["obchod"]`, jinak `ItemsDB.price`).
const BASKET := ["rohlik", "rohlik", "pivo", "jablko", "parek", "tlacenka", "chipsy", "voda", "nealko", "burt", "sirky", "vino_bile"]
## Smyšlení zákazníci (jen křestní jména / oslovení, žádné skutečné osoby).
const CUSTOMERS := [["paní Květa", Color(0.7, 0.3, 0.4)], ["pan Mirek", Color(0.3, 0.4, 0.6)], ["babička Věra", Color(0.5, 0.45, 0.6)],
	["Tonda z bytovky", Color(0.25, 0.5, 0.3)], ["paní Hanka", Color(0.8, 0.6, 0.2)], ["děda Lojza", Color(0.45, 0.4, 0.35)]]
const MANKO_RATING := -2.0
const GOOD_RATING := 0.5
const SHORT_RATING := -1.0

var world: World
var stand_pos := Vector3.INF         # stánek před obchodem (pokladna a „regál“ venku)
var sklad_pos := Vector3.INF         # bedny se zbožím u skladu
var bread_pos := Vector3.INF         # přepravky s pečivem u parkoviště
var _bread_mi: MeshInstance3D
var _bread_jd := {}                  # pid → den, kdy pečivo převzal
var _s := {}                         # pid → {cust, basket, total, paid, given, stage, wait, t, till_t, sklad_t}


func setup(w: World) -> void:
	world = w
	name = "Prodavac"
	var pl: Place = w.places.get(PLACE)
	if pl == null:
		return
	var face := float(pl.data.get("face_yaw", 0.0))
	var b := Basis(Vector3.UP, face)
	stand_pos = _ground(pl.door + b * Vector3(-2.3, 0, 2.2))
	sklad_pos = _ground(pl.door + b * Vector3(-4.6, 0, 0.9))
	bread_pos = _ground(pl.park + b * Vector3(1.5, 0, 0))
	_build_stand(face)
	_build_sklad(face)
	var k := MeshKit.new()
	for i in 3:
		k.box(Vector3(0, 0.12 + i * 0.24, 0), Vector3(0.6, 0.22, 0.4), Color(0.85, 0.55, 0.15))
		k.box(Vector3(0, 0.2 + i * 0.24, 0), Vector3(0.5, 0.08, 0.3), Color(0.8, 0.62, 0.35))
	_bread_mi = MeshKit.mesh_instance(self, k.commit(MeshKit.vc_material(0.8)), 120.0)
	_bread_mi.position = bread_pos
	_bread_mi.rotation.y = face
	_bread_mi.visible = false
	Jobs.set_provider("obchod_pokladna", func(_w: World, id: int, _j: Dictionary) -> Array: return [till_pos(id)])
	Jobs.set_provider("obchod_regaly", func(_w: World, id: int, _j: Dictionary) -> Array: return shelf_points(id))
	Jobs.set_provider("obchod_pecivo", func(_w: World, id: int, _j: Dictionary) -> Array: return _bread_points(id))
	Actions.set_handler("markovat", _on_till)
	Actions.set_handler("vzit_bednu", _on_take_crate)
	Actions.set_handler("doplnit_regal", _on_shelf)
	Actions.set_handler("prevzit_pecivo", _on_bread)
	Actions.chain_target_check("doplnit_regal", func(_aim: Dictionary, id: int) -> String:
		return "" if world.cargo and world.cargo.carried_kind(id) == "bedna" else "Nejdřív přines bednu se zbožím ze skladu (vedle obchodu).")
	Actions.chain_target_check("vzit_bednu", func(_aim: Dictionary, id: int) -> String:
		if world.cargo == null:
			return "Náklad není k dispozici."
		return "Už něco neseš." if world.cargo.carried_kind(id) != "" or world.cargo.hands_busy(id) else "")
	Actions.chain_target_check("prevzit_pecivo", func(_aim: Dictionary, id: int) -> String:
		return "Nejdřív polož, co neseš (G)." if world.cargo and (world.cargo.carried_kind(id) != "" or world.cargo.hands_busy(id)) else "")


func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, world.terrain.height_at(p.x, p.z), p.z)


func _build_stand(face: float) -> void:
	var k := MeshKit.new()
	k.box(Vector3(0, 0.45, 0), Vector3(1.6, 0.9, 0.7), Color(0.55, 0.38, 0.22))
	k.box(Vector3(0, 0.92, 0), Vector3(1.7, 0.04, 0.8), Color(0.65, 0.48, 0.3))
	var fruit := [Color(0.85, 0.15, 0.1), Color(0.95, 0.75, 0.15), Color(0.35, 0.65, 0.2), Color(0.85, 0.6, 0.3)]
	for i in 4:
		k.box(Vector3(-0.6 + i * 0.4, 1.0, 0), Vector3(0.36, 0.12, 0.5), Color(0.6, 0.45, 0.28))
		k.box(Vector3(-0.6 + i * 0.4, 1.08, 0), Vector3(0.3, 0.06, 0.42), fruit[i])
	k.box(Vector3(0.65, 1.05, 0.2), Vector3(0.3, 0.2, 0.25), Color(0.2, 0.2, 0.22))       # pokladna
	var mi := MeshKit.mesh_instance(self, k.commit(MeshKit.vc_material(0.8)), 150.0)
	mi.position = stand_pos
	mi.rotation.y = face


func _build_sklad(face: float) -> void:
	var k := MeshKit.new()
	for i in 6:
		var x := -0.3 + (i % 2) * 0.55
		var y := 0.13 + (i / 2) * 0.27
		k.box(Vector3(x, y, 0), Vector3(0.5, 0.25, 0.35), Color(0.62, 0.46, 0.28))
		k.box(Vector3(x, y + 0.08, 0), Vector3(0.42, 0.1, 0.3), [Color(0.85, 0.7, 0.35), Color(0.2, 0.5, 0.2), Color(0.8, 0.25, 0.2)][i % 3])
	var mi := MeshKit.mesh_instance(self, k.commit(MeshKit.vc_material(0.85)), 150.0)
	mi.position = sklad_pos
	mi.rotation.y = face


# ------------------------------------------------------------------ místa (uvnitř / venku)

func _inside(id: int) -> Interior:
	var p: Player = world.players.get(id)
	var it: Interior = world.interiors.get(PLACE)
	if p and p.inside == PLACE and it and it.built:
		return it
	return null


## Pokladna: v postaveném interiéru na pultu, jinak na stánku před obchodem.
func till_pos(id: int) -> Vector3:
	var it := _inside(id)
	if it and it.spots.has("pokladna"):
		return (it.spots["pokladna"] as Array)[0]
	return stand_pos + Vector3(0, 1.1, 0)


func _customer_pos(id: int) -> Vector3:
	var it := _inside(id)
	if it and it.spots.has("zakaznik"):
		return (it.spots["zakaznik"] as Array)[0]
	var pl: Place = world.places.get(PLACE)
	var face := float(pl.data.get("face_yaw", 0.0)) if pl else 0.0
	return _ground(stand_pos + Basis(Vector3.UP, face) * Vector3(0, 0, 1.2))


## Regály: uvnitř čela čtyř regálů, venku tři bedýnky stánku.
func shelf_points(id: int) -> Array:
	var it := _inside(id)
	var out := []
	if it:
		for i in 4:
			if it.spots.has("regal:%d" % i):
				out.append((it.spots["regal:%d" % i] as Array)[0])
	if out.is_empty() and stand_pos != Vector3.INF:
		var pl: Place = world.places.get(PLACE)
		var b := Basis(Vector3.UP, float(pl.data.get("face_yaw", 0.0)) if pl else 0.0)
		for x in [-0.6, 0.0, 0.6]:
			out.append(stand_pos + b * Vector3(x, 1.0, 0))
	return out


func _bread_points(id: int) -> Array:
	if bread_pos == Vector3.INF or int(_bread_jd.get(id, -1)) == world.clock.jd():
		return []
	return [bread_pos + Vector3(0, 0.5, 0)]


# ------------------------------------------------------------------ průběh

func _active(id: int, task: String) -> bool:
	var jb: Jobs = world.jobs.get(id)
	return jb != null and jb.on_shift(JOB_ID) and jb.task_id() == task


func _state(id: int) -> Dictionary:
	if not _s.has(id):
		_s[id] = {"cust": null, "basket": [], "total": 0, "paid": 0, "given": 0, "stage": 0, "wait": 4.0, "t": 0.0,
			"till_t": {}, "sklad_t": {}}
	return _s[id]


func _process(delta: float) -> void:
	if world == null or stand_pos == Vector3.INF:
		return
	var bread_on := false
	for id_v in world.players:
		var id := int(id_v)
		var jb: Jobs = world.jobs.get(id)
		var on := jb != null and jb.on_shift(JOB_ID)
		if not on:
			if _s.has(id):
				_reset(id)
			continue
		var s := _state(id)
		if _active(id, TASK_BREAD) and not _bread_points(id).is_empty():
			bread_on = true
		_tick_till(id, s, delta)
		_tick_sklad(id, s)
	if _bread_mi:
		_bread_mi.visible = bread_on


## Zákazníci chodí jen při úkolu „Pokladna“; čekající zákazník má cíl `job_pokladna` na pokladně.
func _tick_till(id: int, s: Dictionary, delta: float) -> void:
	var c = s["cust"]
	if not _active(id, TASK_TILL):
		if c != null:
			_customer_leave(id, s, "")
		return
	if c == null or not is_instance_valid(c):
		s["cust"] = null
		s["wait"] = float(s["wait"]) - delta
		if float(s["wait"]) <= 0.0:
			_customer_come(id, s)
		return
	var npc := c as Npc
	npc.global_position = _customer_pos(id)       # hráč vešel / vyšel – zákazník jde s ním (uvnitř / u stánku)
	var tt: Dictionary = s["till_t"]
	if tt.is_empty():
		tt = {"pos": till_pos(id), "r": 1.2, "kind": "job_pokladna", "data": {"pid": id, "job": JOB_ID}}
		s["till_t"] = tt
		world.register_target(tt)
	else:
		tt["pos"] = till_pos(id)
	s["t"] = float(s["t"]) + delta
	if float(s["t"]) > PATIENCE_S:
		var jb: Jobs = world.jobs.get(id)
		if jb:
			jb.adjust_rating(-1.5)
		_customer_leave(id, s, "To je fronta jak za socíku! Jdu jinam.")
		world.notify(id, "show_message", ["Zákazník se nedočkal a odešel.", 3.0])


## Sklad: cíl „vzít bednu“ jen při úkolu „Regály“ a s volnýma rukama.
func _tick_sklad(id: int, s: Dictionary) -> void:
	var want := _active(id, TASK_SHELF) and world.cargo != null and world.cargo.carried_kind(id) == ""
	var st: Dictionary = s["sklad_t"]
	if want and st.is_empty():
		st = {"pos": sklad_pos + Vector3(0, 0.6, 0), "r": 1.4, "kind": "job_sklad", "data": {"pid": id, "job": JOB_ID}}
		s["sklad_t"] = st
		world.register_target(st)
	elif not want and not st.is_empty():
		world.unregister_target(st)
		s["sklad_t"] = {}


func _customer_come(id: int, s: Dictionary) -> void:
	var cd: Array = CUSTOMERS[randi() % CUSTOMERS.size()]
	var npc := Npc.make(String(cd[0]), "", cd[1], randi(), _customer_pos(id), 0.0, world)
	npc.persona = Persona.make({"name": String(cd[0]), "trait": "pratelsky", "job": "zákazník v Potravinách", "age": 50,
		"topics": ["obchod", "drby"]})
	add_child(npc)
	npc.global_position = _customer_pos(id)
	s["cust"] = npc
	s["t"] = 0.0
	s["stage"] = 0
	s["given"] = 0
	var basket := []
	var total := 0
	var used := {}
	for i in randi_range(2, 4):
		var it := String(BASKET[randi() % BASKET.size()])
		if used.has(it):
			continue
		used[it] = true
		var n := randi_range(1, 4) if it == "rohlik" else randi_range(1, 2)
		var price := _price(it)
		basket.append([it, n, price])
		total += n * price
	s["basket"] = basket
	s["total"] = total
	var paid := total
	if randf() > 0.12:                    # občas platí přesně
		for nt in NOTES:
			if int(nt) > total:
				paid = int(nt)
				break
	s["paid"] = paid
	npc.say("Dobrý den, zaplatím.", 4.0)
	world.notify(id, "show_message", ["%s čeká u pokladny – LMB na pokladnu." % cd[0], 3.5])


func _price(item: String) -> int:
	for o in Place.OFFERS.get(PLACE, []):
		if String(o[0]) == item and String(o[2]) == "buy":
			return int(o[1])
	return int(ItemsDB.info(item).get("price", 10)) if ItemsDB.exists(item) else 10


func _customer_leave(id: int, s: Dictionary, text: String) -> void:
	var c = s["cust"]
	if c != null and is_instance_valid(c):
		var npc := c as Npc
		if text != "":
			npc.say(text, 3.0)
		get_tree().create_timer(2.5).timeout.connect(func():
			if is_instance_valid(npc):
				npc.queue_free())
	s["cust"] = null
	s["wait"] = randf_range(float(CUSTOMER_WAIT[0]), float(CUSTOMER_WAIT[1]))
	var tt: Dictionary = s["till_t"]
	if not tt.is_empty():
		world.unregister_target(tt)
	s["till_t"] = {}


func _reset(id: int) -> void:
	var s: Dictionary = _s[id]
	_customer_leave(id, s, "")
	var st: Dictionary = s["sklad_t"]
	if not st.is_empty():
		world.unregister_target(st)
	_s.erase(id)


# ------------------------------------------------------------------ pokladna (minihra v nabídce)

func _on_till(id: int, _def: Dictionary, _aim: Dictionary, ok: bool) -> void:
	if not ok or not _s.has(id):
		return
	var s: Dictionary = _s[id]
	if s["cust"] == null:
		world.notify(id, "show_message", ["U pokladny nikdo není.", 2.0])
		return
	if int(s["stage"]) == 0:
		_menu_sum(id)
	else:
		_menu_change(id)


func _basket_text(s: Dictionary) -> String:
	var lines := []
	for b in s["basket"]:
		lines.append("  %d× %s à %d Kč" % [int(b[1]), ItemsDB.name_of(String(b[0])) if ItemsDB.exists(String(b[0])) else b[0], int(b[2])])
	return "\n".join(lines)


## Krok 1: kolik nákup dělá (4 možnosti, jedna správně).
func _menu_sum(id: int) -> void:
	var s: Dictionary = _s.get(id, {})
	if s.is_empty() or s["cust"] == null:
		return
	var total := int(s["total"])
	var cands := [total]
	var b0: Array = (s["basket"] as Array)[0]
	for d in [int(b0[2]), -int(b0[2]), 10, -10, 5, 20]:
		if cands.size() >= 4:
			break
		if total + int(d) > 0 and not cands.has(total + int(d)):
			cands.append(total + int(d))
	cands.shuffle()
	var opts := []
	for c in cands:
		opts.append(["%d Kč" % int(c), _pick_sum.bind(id, int(c))])
	var name_ := (s["cust"] as Npc).display_name if is_instance_valid(s["cust"]) else "Zákazník"
	world.notify(id, "open_menu", ["Pokladna", "%s si nese:\n%s\n\nKolik to dělá dohromady?" % [name_, _basket_text(s)], opts])


func _pick_sum(id: int, v: int) -> void:
	var s: Dictionary = _s.get(id, {})
	if s.is_empty() or s["cust"] == null:
		return
	var jb: Jobs = world.jobs.get(id)
	if v != int(s["total"]):
		if is_instance_valid(s["cust"]):
			(s["cust"] as Npc).say("To nesedí, přepočítejte si to!", 3.0)
		if jb:
			jb.adjust_rating(SHORT_RATING)
		_menu_sum(id)
		return
	s["stage"] = 1
	s["given"] = 0
	if int(s["paid"]) == int(s["total"]):
		world.notify(id, "show_message", ["Zákazník platí přesně %d Kč – nic se nevrací." % int(s["paid"]), 3.0])
		_done(id, s, 0)
		return
	_menu_change(id)


## Krok 2: zákazník platí bankovkou, hráč skládá drobné z mincí (každá volba nabídku otevře znovu).
func _menu_change(id: int) -> void:
	var s: Dictionary = _s.get(id, {})
	if s.is_empty() or s["cust"] == null:
		return
	var opts := []
	for c in COINS:
		if int(c) < int(s["paid"]):
			opts.append(["+ %d Kč" % int(c), _add_coin.bind(id, int(c))])
	opts.append(["Podat drobné zákazníkovi (%d Kč)" % int(s["given"]), _give.bind(id)])
	opts.append(["Vrátit mince do kasy (znovu)", _add_coin.bind(id, -int(s["given"]))])
	world.notify(id, "open_menu", ["Pokladna – vracení", "Nákup za %d Kč. Zákazník platí %d Kč.\nNa pultu máš připraveno: %d Kč." % [
		int(s["total"]), int(s["paid"]), int(s["given"])], opts])


func _add_coin(id: int, v: int) -> void:
	var s: Dictionary = _s.get(id, {})
	if s.is_empty():
		return
	s["given"] = maxi(int(s["given"]) + v, 0)
	world.play_sfx(id, "pickup", 1.6, -12.0)
	_menu_change(id)


func _give(id: int) -> void:
	var s: Dictionary = _s.get(id, {})
	if s.is_empty() or s["cust"] == null:
		return
	var change := int(s["paid"]) - int(s["total"])
	var g := int(s["given"])
	if g < change:
		if is_instance_valid(s["cust"]):
			(s["cust"] as Npc).say("Vrátil jste mi málo, chybí %d Kč!" % (change - g), 3.5)
		var jb: Jobs = world.jobs.get(id)
		if jb:
			jb.adjust_rating(SHORT_RATING)
		_menu_change(id)
		return
	_done(id, s, g - change)


## Nákup vyřízený: `extra` = kolik hráč vrátil navíc (manko – strhne se z nevyplacené mzdy).
func _done(id: int, s: Dictionary, extra: int) -> void:
	var jb: Jobs = world.jobs.get(id)
	if extra > 0:
		if jb:
			jb.adjust_rating(MANKO_RATING)
			jb.earned_unpaid = maxf(jb.earned_unpaid - float(extra), 0.0)
		world.notify(id, "show_message", ["Vrátil jsi o %d Kč víc – manko se strhne z výplaty." % extra, 3.5])
		_customer_leave(id, s, "Děkuju, na shledanou!")
	else:
		if jb:
			jb.adjust_rating(GOOD_RATING)
		world.play_sfx(id, "cash")
		_customer_leave(id, s, ["Děkuju, na shledanou!", "Tak zase zítra.", "Díky, hezký den."][randi() % 3])
	world.give_xp(id, "vyrecnost", 2.0, "pokladna")
	if jb:
		jb.progress(TASK_TILL)


# ------------------------------------------------------------------ regály a pečivo

func _on_take_crate(id: int, _def: Dictionary, _aim: Dictionary, ok: bool) -> void:
	if ok and world.cargo and world.cargo.shoulder_new(id, "bedna"):
		world.notify(id, "show_message", ["Neseš bednu se zbožím – vybal ji do regálu (LMB na regál).", 3.0])


func _on_shelf(id: int, _def: Dictionary, _aim: Dictionary, ok: bool) -> void:
	if ok and world.cargo:
		world.cargo.consume_carried(id)


func _on_bread(id: int, _def: Dictionary, _aim: Dictionary, ok: bool) -> void:
	if not ok:
		return
	_bread_jd[id] = world.clock.jd()
	if world.cargo and world.cargo.shoulder_new(id, "bedna"):
		world.notify(id, "show_message", ["Řidič z pekárny: „Dneska rohlíky, chleba a koláče. Podepiš tady.“ Bednu s pečivem vybal do regálu.", 4.0])
