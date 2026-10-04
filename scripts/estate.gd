## Registr nemovitostí (M1.7), jeden uzel ve `World` (`World.estate`).
##
## - **Nemovitost** = budova z `BuildingDetails` (id = osm_id z `data/buildings.json`, stálé mezi spuštěními): SMYŠLENÉ
##   popisné číslo, typ (`TYPES`), dveře (`door`, `normal`), střed, půdorys, počet podlaží a u bytového domu počet bytů.
##   Bez `buildings.json` se registr složí jen z míst v `pois.json` (id < 0) – hra běží, jen bez bytového domu (viz `_pick_start`).
## - **Čísla popisná jsou vymyšlená** (právní zásady obsahu): číslují se deterministicky 1..N bez děr od středu obce (náves =
##   dveře úřadu) po prstencích `RING_M`, v prstenci po směru hodinových ručiček od úhlu daného `NUMBER_SEED`. Nic se nebere
##   z RÚIAN / ČÚZK; skutečné číslo původního domu hráče (`AVOID_NO_*`) se nikdy nezobrazí.
## - **Cedulka s číslem** (smaltovaná, obecný vzhled bez znaku obce) vedle dveří každé očíslované budovy, `Label3D` jen zblízka.
## - **Domov = vlastnictví / nájem:** `home_of(pid)` → {estate, flat (−1 = celý dům), rent, paid_jd, debt, reminders}.
##   Nová hra: nájemní byt v bytovém domě vylosovaném náhodně z celé mapy (`start_id`, `_pick_start`).
##   Staré uložení (verze 1): hráč vlastní
##   původní dům z podkladů (`lot_id`, `migrate_legacy`). `World.apply_home` podle toho přesune místo „domov“, rádio a interiér.
## - **Usedlost** (`lot_id`, původní dům hráče z podkladů): u ní zůstává hospodářství (a body včelaře, překupníka, hajného).
##   Zahrada a výběh koně jsou pronajaté **u domova** (`World.home_grounds`; stěhují se s `apply_home`), hospodářská
##   zvířata jen s vlastním domem (`owns_house`, M4.7).
## - **Děda Vomáčka** bydlí v nejbližším rodinném domě k lavičce (`deda_id`, nové smyšlené číslo).
## - **Nájem** `RENT_KC` jednou za 7 herních dní; bez peněz dluh a upomínka (událost `rent_overdue` – hák pro M3 práce / dluhy).
##
## API: `info(id)`, `number_of(id)`, `label(id)`, `home_estate(pid)`, `home_flat(pid)`, `is_flat(pid)`, `owns_house(pid)`,
## `home_label(pid)` („byt 3 v č. p. 48“), `home_where(pid)`, `home_title(pid)`, `home_door(pid)`, `lot_door()`, `lot_park()`,
## `lot_label()`, `deda_label()`, `rent_text(pid)`, `set_home`, `ensure_home`, `to_dict(pid)`, `from_dict(pid, d)`, `migrate_legacy(pid)`.
class_name Estate
extends Node3D

# ------------------------------------------------------------------ laditelné hodnoty

const TYPES := {"rodinny_dum": "rodinný dům", "bytovy_dum": "bytový dům", "hospodarska": "hospodářská budova",
	"verejna": "veřejná budova"}
## Typ budovy z `BuildingDetails.RULES` → typ nemovitosti. Místa z pois.json jsou vždy „verejna“.
const KIND_TYPE := {"house": "rodinny_dum", "public": "verejna", "church": "verejna", "hall": "hospodarska",
	"barn": "hospodarska", "garage": "hospodarska", "shed": "hospodarska"}
## Které budovy dostanou číslo popisné (kůlny, garáže a stodoly patří k domu a vlastní číslo nemají).
const NUMBERED := ["house", "public", "church", "hall"]
const RING_M := 120.0                    # m – šířka prstence při číslování od návsi
const NUMBER_SEED := 48611               # posun počátečního úhlu číslování (jiný seed = jiné, ale stálé číslování)
## Skutečné č. p. podkladu původního domu hráče (`meta.domov_hrace`) – ve hře se nesmí zobrazit (právní zásady obsahu).
## Hodnota v kódu není – chrání se úsek podkladového číslování AVOID_NO_MIN..AVOID_NO_MAX.
const AVOID_NO_MIN := 118
const AVOID_NO_MAX := 126
# bytový dům pro začátek hry: NÁHODNÝ los mezi obytnými budovami z celé mapy (žádná vazba na konkrétní dům);
# přednost mají domy s aspoň FLAT_MIN_FLOORS podlažími (interiér bytového domu se schodištěm), jinak los
# mezi budovami s půdorysem aspoň FLAT_FALLBACK_AREA
const FLAT_MIN_FLOORS := 2
const FLAT_FALLBACK_AREA := 150.0        # m²
const FLAT_AREA := 80.0                  # m² půdorysu na jeden byt a podlaží (i se schodištěm) → počet bytů
const FLATS_MIN := 4
const FLATS_MAX := 8
const RENT_KC := 1200                    # Kč za týden – DOPLNIT: výše nájmu (herní odhad; start s 1 500 Kč, úkoly za stovky)
const RENT_DAYS := 7
const PLATE_VIS := 40.0                  # m – dál se cedulka s číslem nekreslí (jako okna jen zblízka)
const PLATE_Y := 2.0                     # m nad terénem u dveří (střed cedulky)
const PLATE_GAP := 0.45                  # m od hrany dveří / vrat
const PLATE_SIZE := Vector2(0.30, 0.20)  # m
const PLATE_COLOR := Color(0.62, 0.09, 0.08)   # červený smalt (obecný vzhled, bez znaku obce)
const PLATE_RIM := Color(0.93, 0.93, 0.9)
const CHECK_S := 1.0

# ------------------------------------------------------------------ stav

var world: World
var estates := {}               # id → {id, no, type, kind, place, center (Vector2), poly, area, floors, flats, door, normal, door_w}
var by_no := {}                 # číslo popisné → id
var lot_id := 0                 # usedlost = původní dům hráče z podkladů (zahrada, výběh, hospodářství)
var start_id := 0               # bytový dům nové hry (náhodný los v _pick_start při startu světa)
var start_flat := 1
var deda_id := 0                # dům dědy Vomáčky (nejbližší rodinný dům k jeho lavičce)
var centre := Vector2.ZERO      # náves (dveře úřadu)
var homes := {}                 # pid → {estate, flat, rent, paid_jd, debt, reminders}
var _lot_data := {}             # původní záznam místa „domov“ z pois.json (dveře, parkování, face_yaw) – usedlost
var _t := 0.0
var _last_jd := -1


## Sestaví registr (volá `World.build` po místech, fasádách a interiérech).
func setup(w: World) -> void:
	world = w
	name = "Nemovitosti"
	if w.places.has("domov"):
		_lot_data = (w.places["domov"] as Place).data.duplicate()
	if w.building_details != null and w.building_details.loaded:
		_from_buildings(w.building_details)
	if estates.is_empty() or lot_id == 0:
		_from_places(not estates.is_empty())
	var urad: Place = w.places.get("urad")
	centre = Vector2(urad.door.x, urad.door.z) if urad else _lot_door2()
	_number()
	_pick_start()
	_pick_deda()
	_build_plates()
	_last_jd = w.clock.jd() if w.clock else -1


# ------------------------------------------------------------------ sestavení registru

func _from_buildings(bd: BuildingDetails) -> void:
	var all := bd.buildings()
	var home_id := bd.building_of_home()
	for id_v in all:
		var id: int = id_v
		var b: Dictionary = all[id_v]
		var kind: String = b["type"]
		var poi: String = b["poi"]
		var typ: String = KIND_TYPE.get(kind, "hospodarska")
		if poi != "":
			typ = "verejna"
		if id == home_id:
			typ = "rodinny_dum"
			poi = ""
		var poly: PackedVector2Array = b["poly"]
		var floors := 1
		if b["known"]:
			floors = _floors(float(b["eave"]) - float(b["ground"]))
		var door := Vector3.INF
		var normal := Vector3(0, 0, 1)
		var door_w := BuildingDetails.DOOR_W
		var di := bd.door_info(id)
		if not di.is_empty():
			door = di["pos"]
			normal = di["normal"]
			door_w = float(di["width"])
		estates[id] = {"id": id, "no": 0, "type": typ, "kind": kind, "place": poi, "center": _centroid(poly), "poly": poly,
			"area": float(b["area"]), "floors": floors, "flats": 0, "door": door, "normal": normal, "door_w": door_w}
	if home_id != 0 and estates.has(home_id):
		lot_id = home_id


## Bez dat budov (nebo bez domova v nich): nemovitosti z míst pois.json (id −1, −2, …; jen místa, co v registru chybí).
func _from_places(partial: bool) -> void:
	var keys: Array = world.places.keys()
	keys.sort()
	var have := {}
	for id in estates:
		if String(estates[id]["place"]) != "":
			have[String(estates[id]["place"])] = true
	var n := 0
	for k in keys:
		var key := String(k)
		n += 1
		if have.has(key) or (partial and key != "domov"):
			continue
		var pl: Place = world.places[key]
		var face := float(pl.data.get("face_yaw", 0.0))
		var nrm := Vector3(sin(face), 0.0, cos(face))
		var id := -n
		var c := Vector2(pl.door.x - nrm.x * 5.0, pl.door.z - nrm.z * 5.0)
		estates[id] = {"id": id, "no": 0, "type": "rodinny_dum" if key == "domov" else "verejna",
			"kind": "house" if key == "domov" else "public", "place": "" if key == "domov" else key, "center": c,
			"poly": PackedVector2Array(), "area": 120.0, "floors": 2 if key == "domov" else 1, "flats": 0,
			"door": pl.door, "normal": nrm, "door_w": BuildingDetails.DOOR_W}
		if key == "domov":
			lot_id = id


## Počet podlaží ze stěny (okap nad terénem) – stejné prahy jako okna v `BuildingDetails`.
static func _floors(wall: float) -> int:
	if wall < BuildingDetails.FLOOR2_MIN_WALL:
		return 1
	return 2 + int(floor((wall - BuildingDetails.FLOOR2_MIN_WALL) / BuildingDetails.FLOOR_H))


static func _centroid(poly: PackedVector2Array) -> Vector2:
	if poly.is_empty():
		return Vector2.ZERO
	var c := Vector2.ZERO
	for p in poly:
		c += p
	return c / float(poly.size())


func _lot_door2() -> Vector2:
	var d := lot_door()
	return Vector2(d.x, d.z)


## Smyšlená čísla popisná 1..N: prstence od návsi, v prstenci podle úhlu (od úhlu ze seedu), shoda → menší id.
func _number() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = NUMBER_SEED
	var a0 := rng.randf() * TAU
	var keys := {}
	var cand := []
	for id_v in estates:
		var e: Dictionary = estates[id_v]
		if not (String(e["kind"]) in NUMBERED or String(e["place"]) != "" or int(id_v) == lot_id):
			continue
		var c: Vector2 = e["center"]
		var d := c - centre
		var ang := fposmod(atan2(d.x, -d.y) - a0, TAU)
		keys[id_v] = [int(floor(d.length() / RING_M)), ang]
		cand.append(id_v)
	cand.sort_custom(func(a, b) -> bool:
		var ka: Array = keys[a]
		var kb: Array = keys[b]
		if int(ka[0]) != int(kb[0]):
			return int(ka[0]) < int(kb[0])
		if float(ka[1]) != float(kb[1]):
			return float(ka[1]) < float(kb[1])
		return int(a) < int(b))
	by_no = {}
	for i in cand.size():
		estates[cand[i]]["no"] = i + 1
		by_no[i + 1] = cand[i]
	# skutečné číslo původního domu se nesmí objevit – výměna se sousedním číslem (zůstává 1..N bez děr)
	if estates.has(lot_id):
		var no: int = estates[lot_id]["no"]
		if no >= AVOID_NO_MIN and no <= AVOID_NO_MAX and by_no.size() > 1:
			var other_no := no + 1 if by_no.has(no + 1) else no - 1
			var oid: int = by_no[other_no]
			estates[oid]["no"] = no
			estates[lot_id]["no"] = other_no
			by_no[no] = oid
			by_no[other_no] = lot_id


## Bytový dům nové hry: NÁHODNÝ los z celé mapy (rozhodnutí uživatele před zveřejněním – žádná vazba na jednu
## konkrétní budovu). 1) Kandidáti: všechny obytné budovy (typ house, ne místo, ne usedlost, s dveřmi) s aspoň
## FLAT_MIN_FLOORS podlažími. 2) Když žádná nesedí, los mezi budovami s půdorysem ≥ FLAT_FALLBACK_AREA. 3) Bez
## dat budov podnájem v usedlosti (byt 1 ze 2). Losuje se při každém startu světa (uložená hra má domov v save).
func _pick_start() -> void:
	var cands := []
	var small := []
	for id_v in estates:
		var id: int = id_v
		var e: Dictionary = estates[id_v]
		if not _dwelling_ok(id, e):
			continue
		if int(e["floors"]) >= FLAT_MIN_FLOORS:
			cands.append(id)
		elif float(e["area"]) >= FLAT_FALLBACK_AREA:
			small.append(id)
	if cands.is_empty():
		cands = small
	if cands.is_empty():
		start_id = lot_id
		if estates.has(lot_id):
			estates[lot_id]["flats"] = 2
		start_flat = 1
		return
	cands.sort()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var best: int = cands[rng.randi() % cands.size()]
	start_id = best
	var s: Dictionary = estates[best]
	s["type"] = "bytovy_dum"
	var flats := clampi(roundi(float(s["floors"]) * float(s["area"]) / FLAT_AREA), FLATS_MIN, FLATS_MAX)
	s["flats"] = flats
	start_flat = 1 + rng.randi() % flats


func _dwelling_ok(id: int, e: Dictionary) -> bool:
	return String(e["kind"]) == "house" and String(e["place"]) == "" and id != lot_id and int(e["no"]) > 0 \
		and e["door"] != Vector3.INF


## Dům dědy Vomáčky: nejbližší rodinný dům k jeho lavičce (ne usedlost, ne bytový dům).
func _pick_deda() -> void:
	var at := _lot_door2()
	if world.npcs.has("deda"):
		var dp: Vector3 = (world.npcs["deda"] as Node3D).global_position
		at = Vector2(dp.x, dp.z)
	var bd := INF
	for id_v in estates:
		var id: int = id_v
		var e: Dictionary = estates[id_v]
		if id == start_id or String(e["type"]) != "rodinny_dum" or not _dwelling_ok(id, e):
			continue
		var ec: Vector2 = e["center"]
		var d := ec.distance_to(at)
		if d < bd:
			bd = d
			deda_id = id


# ------------------------------------------------------------------ cedulky s číslem

func _build_plates() -> void:
	var rim := BoxMesh.new()
	rim.size = Vector3(PLATE_SIZE.x + 0.03, PLATE_SIZE.y + 0.03, 0.012)
	var rim_mat := StandardMaterial3D.new()
	rim_mat.albedo_color = PLATE_RIM
	rim_mat.roughness = 0.35
	rim.material = rim_mat
	var face := BoxMesh.new()
	face.size = Vector3(PLATE_SIZE.x, PLATE_SIZE.y, 0.014)
	var face_mat := StandardMaterial3D.new()
	face_mat.albedo_color = PLATE_COLOR
	face_mat.roughness = 0.25          # smalt se leskne
	face.material = face_mat
	for no in range(1, by_no.size() + 1):
		var e: Dictionary = estates[by_no[no]]
		var door: Vector3 = e["door"]
		if door == Vector3.INF:
			continue
		var n: Vector3 = e["normal"]
		n.y = 0.0
		n = n.normalized() if n.length() > 0.01 else Vector3(0, 0, 1)
		var along := Vector3(n.z, 0.0, -n.x)
		var node := Node3D.new()
		node.name = "Cislo_%d" % no
		node.position = door + along * (float(e["door_w"]) * 0.5 + PLATE_GAP) + Vector3.UP * PLATE_Y + n * 0.03
		node.rotation.y = atan2(n.x, n.z)
		add_child(node)
		for m in [[rim, 0.0], [face, 0.006]]:
			var mi := MeshInstance3D.new()
			mi.mesh = m[0]
			mi.position = Vector3(0, 0, float(m[1]))
			mi.visibility_range_end = PLATE_VIS
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.add_child(mi)
		var lab := Label3D.new()
		lab.text = str(no)
		lab.font_size = 48
		lab.pixel_size = 0.0028
		lab.outline_size = 0
		lab.modulate = PLATE_RIM
		lab.position = Vector3(0, 0, 0.015)
		lab.visibility_range_end = PLATE_VIS
		node.add_child(lab)


# ------------------------------------------------------------------ dotazy

func info(id: int) -> Dictionary:
	return estates.get(id, {})


func number_of(id: int) -> int:
	return int(estates[id]["no"]) if estates.has(id) else 0


## „č. p. 48“ (nebo „budova bez čísla“).
func label(id: int) -> String:
	var no := number_of(id)
	return "č. p. %d" % no if no > 0 else "budova bez čísla"


func lot_label() -> String:
	return label(lot_id)


## M3.2: vlastník budovy, která nepatří hráči (statek → „hospodář“; hák pro M4.7 koupě / prohlídky). "" = nikdo zapsaný.
func set_estate_owner(id: int, who: String, place := "") -> void:
	if not estates.has(id):
		return
	estates[id]["owner"] = who
	if place != "":
		estates[id]["owner_place"] = place      # místo (Place), ke kterému budova patří – ne `place` (to řídí interiéry)


func owner_of(id: int) -> String:
	return String((estates.get(id, {}) as Dictionary).get("owner", ""))


## Hospodářská budova pro statek (M3.2): ne usedlost hráče, ne bytový dům, daleko od usedlosti (`min_lot`), co nejdál
## od návsi v pásmu `r0`–`r1` a co největší (skóre = plocha × vzdálenost). 0 = nic vhodného (bez dat budov).
func pick_farmstead(min_lot: float, r0: float, r1: float) -> int:
	var lot := _lot_door2()
	var best := 0
	var best_s := -1.0
	for id_v in estates:
		var id: int = id_v
		var e: Dictionary = estates[id_v]
		if id == lot_id or id == start_id or String(e["type"]) != "hospodarska" or String(e["place"]) != "":
			continue
		var c: Vector2 = e["center"]
		var dc := c.distance_to(centre)
		if dc < r0 or dc > r1 or c.distance_to(lot) < min_lot:
			continue
		var s := float(e["area"]) * clampf(dc / r0, 1.0, 3.0) * (1.3 if (e["door"] as Vector3) != Vector3.INF else 1.0)
		if s > best_s:
			best_s = s
			best = id
	return best


## M3.3: rodinný dům pro zakázku (zahradník u sousedů, rozvoz): ne domov žádného hráče, ne usedlost, s dveřmi, do `max_d` m
## od návsi; `seed_` vybere stále stejně pro stejné číslo. 0 = nic vhodného (bez dat budov).
func pick_customer_house(seed_: int, max_d := 700.0, avoid: Array = []) -> int:
	var taken := []
	for p in homes:
		taken.append(int((homes[p] as Dictionary).get("estate", 0)))
	var ids := []
	for id_v in estates:
		var id: int = id_v
		var e: Dictionary = estates[id_v]
		if String(e["type"]) != "rodinny_dum" or not _dwelling_ok(id, e) or taken.has(id) or avoid.has(id):
			continue
		if (e["center"] as Vector2).distance_to(centre) > max_d:
			continue
		ids.append(id)
	if ids.is_empty():
		return 0
	ids.sort()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	return int(ids[rng.randi() % ids.size()])


func deda_label() -> String:
	return label(deda_id) if deda_id != 0 else "vedle usedlosti %s" % lot_label()


## Dveře usedlosti (původní bod `door_x/z` místa „domov“ z pois.json – stálý, i když hráč bydlí jinde).
func lot_door() -> Vector3:
	if _lot_data.has("door_x"):
		var x := float(_lot_data["door_x"])
		var z := float(_lot_data["door_z"])
		return Vector3(x, world.terrain.height_at(x, z), z)
	var e := info(lot_id)
	return e.get("door", Vector3.ZERO)


func lot_park() -> Vector3:
	if _lot_data.has("park_x"):
		var x := float(_lot_data["park_x"])
		var z := float(_lot_data["park_z"])
		return Vector3(x, world.terrain.height_at(x, z), z)
	return lot_door()


## Původní záznam místa „domov“ z pois.json (pro návrat domova na usedlost).
func lot_data() -> Dictionary:
	return _lot_data


func default_home() -> Dictionary:
	return {"estate": start_id, "flat": start_flat, "rent": true, "paid_jd": world.clock.jd() if world.clock else 0,
		"debt": 0, "reminders": 0}


func home_of(pid: int) -> Dictionary:
	return homes.get(pid, default_home())


func home_estate(pid: int) -> int:
	return int(home_of(pid)["estate"])


## Číslo bytu (1..), −1 = celý dům.
func home_flat(pid: int) -> int:
	return int(home_of(pid)["flat"])


func is_flat(pid: int) -> bool:
	return home_flat(pid) > 0


## Vlastní dům (ne byt, ne nájem) – hospodářská zvířata, kácení na vlastní zahradě, topení dřevem.
func owns_house(pid: int) -> bool:
	var h := home_of(pid)
	return int(h["flat"]) <= 0 and not bool(h["rent"])


## „byt 3 v č. p. 48“ / „č. p. 48“.
func home_label(pid: int) -> String:
	var id := home_estate(pid)
	if is_flat(pid):
		return "byt %d v č. p. %d" % [home_flat(pid), number_of(id)]
	return label(id)


## Pro věty „Domů, …, je to …“: „do bytu 3 v čísle 48“ / „k číslu 48“.
func home_where(pid: int) -> String:
	var no := number_of(home_estate(pid))
	if is_flat(pid):
		return "do bytu %d v čísle %d" % [home_flat(pid), no]
	return "k číslu %d" % no


func home_title(pid: int) -> String:
	if is_flat(pid):
		return "Doma (byt %d, č. p. %d)" % [home_flat(pid), number_of(home_estate(pid))]
	return "Doma (%s)" % label(home_estate(pid))


## Dveře budovy domova na fasádě (Vector3.INF bez dat budov).
func home_door(pid: int) -> Vector3:
	return info(home_estate(pid)).get("door", Vector3.INF)


## Řádek pro nabídku domova: nájem, dluh.
func rent_text(pid: int) -> String:
	var h := home_of(pid)
	if not bool(h["rent"]):
		return "Bydlíš ve vlastním (%s)." % home_label(pid)
	var s := "Nájem %d Kč týdně (strhne se sám), další za %d dní." % [RENT_KC,
		maxi(0, int(h["paid_jd"]) + RENT_DAYS - world.clock.jd())]
	if int(h["debt"]) > 0:
		s += " Dluh na nájmu: %d Kč!" % int(h["debt"])
	return s


## Dluh na nájmu hráče `pid` v Kč (0 = bez dluhu nebo vlastní bydlení).
func rent_debt(pid: int) -> int:
	var h := home_of(pid)
	return int(h.get("debt", 0)) if bool(h.get("rent", false)) else 0


## Zaplatí dluh na nájmu z hotovosti hráče (M3.1: nabídka při výplatě). Vrací zaplacenou částku (0 = nic / málo peněz).
func pay_rent_debt(pid: int) -> int:
	var due := rent_debt(pid)
	var p: Player = world.players.get(pid)
	if due <= 0 or p == null or p.money < due:
		return 0
	p.money -= due
	homes[pid]["debt"] = 0
	world.play_sfx(pid, "cash")
	world.notify(pid, "show_message", ["Dluh na nájmu (%s) zaplacen: %d Kč." % [home_label(pid), due], 4.0])
	world.emit_game_event(pid, "rent_paid", {"kc": due})
	return due


# ------------------------------------------------------------------ vlastnictví a nájem

func ensure_home(pid: int) -> void:
	if not homes.has(pid):
		homes[pid] = default_home()


## Hráč `pid` bydlí v nemovitosti `id`: `flat` = číslo bytu (−1 = celý dům), `rent` = v nájmu. (M4.7: koupě / prodej.)
func set_home(pid: int, id: int, flat: int, rent: bool) -> void:
	homes[pid] = {"estate": id, "flat": flat, "rent": rent, "paid_jd": world.clock.jd() if world.clock else 0, "debt": 0,
		"reminders": 0}


## Staré uložení (verze 1, dům hráče byl pevně daný): hráč vlastní usedlost (smyšlené číslo nahradí podkladové),
## zahrada, výběh i hospodářství zůstávají, kde byly.
func migrate_legacy(pid: int) -> void:
	set_home(pid, lot_id, -1, false)


func to_dict(pid: int) -> Dictionary:
	var h := home_of(pid)
	return {"estate": int(h["estate"]), "flat": int(h["flat"]), "rent": bool(h["rent"]), "paid_jd": int(h["paid_jd"]),
		"debt": int(h["debt"]), "reminders": int(h["reminders"])}


## Načtení (SaveGame verze ≥ 2). Neznámá nemovitost (jiná data budov) → usedlost, když ji hráč vlastnil, jinak startovní byt.
func from_dict(pid: int, d: Dictionary) -> void:
	var id := int(d.get("estate", start_id))
	var flat := int(d.get("flat", -1))
	var rent := bool(d.get("rent", false))
	if not estates.has(id):
		if rent:
			id = start_id
			flat = start_flat
		else:
			id = lot_id
			flat = -1
	set_home(pid, id, flat, rent)
	homes[pid]["paid_jd"] = int(d.get("paid_jd", homes[pid]["paid_jd"]))
	homes[pid]["debt"] = int(d.get("debt", 0))
	homes[pid]["reminders"] = int(d.get("reminders", 0))


func _process(delta: float) -> void:
	if world == null or world.clock == null:
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = CHECK_S
	var jd := world.clock.jd()
	if jd == _last_jd:
		return
	_last_jd = jd
	for pid in homes:
		_rent_check(int(pid), jd)


## Nájem za každých celých RENT_DAYS dní od posledního placení (i po spánku / skoku času); bez peněz dluh a upomínka.
func _rent_check(pid: int, jd: int) -> void:
	var h: Dictionary = homes[pid]
	var p: Player = world.players.get(pid)
	if p == null or not bool(h["rent"]):
		return
	var weeks := (jd - int(h["paid_jd"])) / RENT_DAYS
	var due := int(h["debt"]) + maxi(weeks, 0) * RENT_KC
	if weeks > 0:
		h["paid_jd"] = int(h["paid_jd"]) + weeks * RENT_DAYS
	if due <= 0:
		return
	var pc: Computer = world.get("computer")
	if pc and pc.pay_rent(pid, due):             # M3.4: trvalý příkaz z účtu (Moje banka) má přednost před hotovostí
		h["debt"] = 0
		world.emit_game_event(pid, "rent_paid", {"kc": due, "ucet": true})
		return
	if p.money >= due:
		p.money -= due
		h["debt"] = 0
		world.play_sfx(pid, "cash")
		world.notify(pid, "show_message", ["Nájem za byt (%s): zaplaceno %d Kč." % [home_label(pid), due], 4.0])
		world.emit_game_event(pid, "rent_paid", {"kc": due})
	elif weeks > 0:
		h["debt"] = due
		h["reminders"] = int(h["reminders"]) + 1
		world.notify(pid, "popup", ["Upomínka od majitele bytu: dlužíš na nájmu %d Kč. Zaplatí se samo, jakmile budeš mít peníze." % due, 6.0])
		world.emit_game_event(pid, "rent_overdue", {"debt": due, "reminders": int(h["reminders"])})
