class_name Katastr
extends Node

## Katastr a koupě / prodej nemovitostí (M4.7): domy (`Estate`) a parcely (orná půda, louky, sady, zahrádky) jen
## v DOMÁCÍM katastru (polygon `meta.boundary` v `data/map.json`). Jedna instance `World.katastr`.
## Vlastnictví je globální (`house_owner`, `parcel_owner`), rozjednané smlouvy a prodeje v `pending`.
## Koupě = kupní smlouva (platba hned + správní poplatek) → vklad do katastru za `DEPOSIT_DAYS` herních dní → převod.
## Prodej parcely obci je hned za `OBEC_SHARE` ceny; dům se prodá kupci za několik dní. Čísla parcel a ceny jsou smyšlené.
## Otevřené body: hypotéka (přes `Debts`), pronájem domu, cedule „Na prodej“, vliv vlastnictví na les a pole.

## herní dny od smlouvy do vkladu
const DEPOSIT_DAYS := 20
## Kč: správní poplatek za vklad (platí se při podpisu smlouvy)
const DEPOSIT_FEE := 1500
## dní do prodeje domu kupci (rozmezí; drahé domy se prodávají déle)
const SALE_DAYS := [3, 20]
## Kč za 500 000 Kč ceny navíc se prodej protahuje o 2 dny
const SALE_STEP_KC := 500000
## výkup parcely obcí = podíl tržní ceny (hned)
const OBEC_SHARE := 0.6
## prodej domu = podíl ceny (nabídka kupci)
const HOUSE_SALE_SHARE := 0.9
## inzeráty se mění po týdnech
const LISTING_WEEK_DAYS := 7
const LISTING_HOUSES := 5
const LISTING_PARCELS := 6
## Kč za m² podlahy domu (orientačně: podlaží × půdorys)
const HOUSE_KC_M2 := 4000
## m – mřížka kandidátních parcel (deterministická, podle seedu není potřeba: pevná mřížka)
const PARCEL_M := 100.0
## m² – výměra jedné parcely (1 ha)
const PARCEL_AREA := 10000.0
## m od dveří usedlosti – bez parcel těsně u původního domu
const PARCEL_MIN_LOT := 80.0
## Kč za m² podle třídy plochy (`Fields.class_at`)
const PARCEL_KC_M2 := {1: 40, 2: 25, 3: 60, 4: 120}
const PARCEL_NAMES := {1: "orná půda", 2: "louka / pastvina", 3: "sad / vinice", 4: "zahrádky"}
## číslo parcely = tento základ + pořadí (smyšlené)
const PARCEL_NO_BASE := 300
const SELLER_NAME := "Katastrální úřad (smyšlený)"
const CHECK_S := 1.0

var world: World
var parcels := []            # [{key, no, cls, center: Vector2}] – jen uvnitř domácího katastru, vytvořeno v setup
var parcel_by_key := {}      # klíč → index v `parcels`
var house_owner := {}        # id budovy (int) → "hrac" | "obec" | "kupec"; chybí = bez vlastníka (na trhu)
var parcel_owner := {}       # klíč parcely → "hrac" | "obec"
var pending := []            # [{kind: "koupe"/"prodej", what: "dum"/"pole", ref, price, due_jd, pid}]
var _poly := PackedVector2Array()
var _t := 0.0
var _last_jd := -1


func setup(w: World) -> void:
	world = w
	name = "Katastr"
	var raw: Variant = w.meta.get("boundary", []) if w.meta else []
	_poly = PackedVector2Array()
	if raw is Array:
		for q in raw:
			if q is Array and q.size() >= 2:
				_poly.append(Vector2(float(q[0]), float(q[1])))
	_build_parcels()
	_last_jd = w.clock.jd() if w.clock else -1


## Bod (x, z) je uvnitř domácího katastru (bez polygonu = všude, jen pro nouzi).
func in_cadastre(p: Vector2) -> bool:
	if _poly.size() < 3:
		return true
	return Geometry2D.is_point_in_polygon(p, _poly)


## Kandidátní parcely: mřížka PARCEL_M uvnitř katastru, na ploše s třídou z `Fields` (0 = nic → vynechat).
func _build_parcels() -> void:
	parcels = []
	parcel_by_key = {}
	if _poly.size() < 3 or world.fields == null or not world.fields.loaded:
		return
	var lo := _poly[0]
	var hi := _poly[0]
	for p in _poly:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var door := world.lot_door() if world.estate else Vector3.ZERO
	var dd := Vector2(door.x, door.z)
	var x := lo.x + PARCEL_M * 0.5
	while x < hi.x:
		var z := lo.y + PARCEL_M * 0.5
		while z < hi.y:
			var c := Vector2(x, z)
			var cls: int = world.fields.class_at(x, z)
			if PARCEL_KC_M2.has(cls) and in_cadastre(c) and c.distance_to(dd) >= PARCEL_MIN_LOT:
				var idx := parcels.size()
				var key := "P%d" % idx
				parcels.append({"key": key, "no": PARCEL_NO_BASE + idx, "cls": cls, "center": c})
				parcel_by_key[key] = idx
			z += PARCEL_M
		x += PARCEL_M


# ------------------------------------------------------------------ nabídka (inzeráty)

func _week() -> int:
	return int(world.clock.jd()) / LISTING_WEEK_DAYS if world and world.clock else 0


func _pending_has(what: String, ref) -> bool:
	for p in pending:
		if String(p["what"]) == what and str(p["ref"]) == str(ref):
			return true
	return false


## Domy na trhu (bez vlastníka, ne domov a ne usedlost, jen rodinné domy v katastru). Každý týden jiný výběr.
func market_houses() -> Array:
	var out := []
	if world.estate == null:
		return out
	var week := _week()
	var home := world.estate.home_estate(1)
	var ids := world.estate.estates.keys()
	ids.sort()
	for id_v in ids:
		var id: int = id_v
		var e: Dictionary = world.estate.estates[id]
		if id <= 0 or String(e["type"]) != "rodinny_dum" or id == world.estate.lot_id or id == home:
			continue
		if house_owner.has(id) or _pending_has("dum", id):
			continue
		if not in_cadastre(e["center"]):
			continue
		if posmod(hash([id, week]), 3) != 0:
			continue
		out.append(id)
		if out.size() >= LISTING_HOUSES:
			break
	return out


## Parcely na trhu (bez vlastníka a bez rozjednané smlouvy), výběr se mění po týdnech.
func market_parcels() -> Array:
	var out := []
	var week := _week()
	for p in parcels:
		var key := String(p["key"])
		if parcel_owner.has(key) or _pending_has("pole", key):
			continue
		if posmod(hash([key, week]), 3) != 0:
			continue
		out.append(key)
		if out.size() >= LISTING_PARCELS:
			break
	return out


func house_price(id: int) -> int:
	var e: Dictionary = world.estate.estates[id]
	return roundi(float(e["area"]) * float(e["floors"]) * HOUSE_KC_M2 / 1000.0) * 1000


func parcel_of(key: String) -> Dictionary:
	return parcels[parcel_by_key[key]] if parcel_by_key.has(key) else {}


func parcel_price(key: String) -> int:
	var p := parcel_of(key)
	if p.is_empty():
		return 0
	return int(PARCEL_KC_M2[int(p["cls"])]) * int(PARCEL_AREA)


func parcel_label(key: String) -> String:
	var p := parcel_of(key)
	if p.is_empty():
		return key
	return "parc. č. %d (%s, 1 ha)" % [int(p["no"]), String(PARCEL_NAMES[int(p["cls"])])]


func house_label(id: int) -> String:
	return "dům %s" % world.estate.label(id)


# ------------------------------------------------------------------ nákup a prodej

func _msg(pid: int, text: String, dur := 4.0) -> void:
	world.notify(pid, "show_message", [text, dur])


func _player(pid: int) -> Player:
	return world.players.get(pid)


## Kupní smlouva na dům. Vrací true, když se podepsala.
func buy_house(pid: int, id: int) -> bool:
	var pl := _player(pid)
	if pl == null or not market_houses().has(id):
		return false
	var price := house_price(id)
	var total := price + DEPOSIT_FEE
	if pl.money < total:
		_msg(pid, "Nemáš dost peněz: cena %s + poplatek za vklad %s." % [Bazaar.kc(price), Bazaar.kc(DEPOSIT_FEE)], 4.0)
		return false
	pl.money -= total
	world.play_sfx(pid, "cash")
	pending.append({"kind": "koupe", "what": "dum", "ref": id, "price": price, "due_jd": _jd() + DEPOSIT_DAYS, "pid": pid})
	_msg(pid, "Kupní smlouva na %s podepsána (%s). Vklad do katastru za %d dní." % [house_label(id), Bazaar.kc(total), DEPOSIT_DAYS], 6.0)
	world.emit_game_event(pid, "property_bought", {"what": "dum", "id": id, "kc": total})
	return true


func buy_parcel(pid: int, key: String) -> bool:
	var pl := _player(pid)
	if pl == null or not market_parcels().has(key):
		return false
	var price := parcel_price(key)
	var total := price + DEPOSIT_FEE
	if pl.money < total:
		_msg(pid, "Nemáš dost peněz: cena %s + poplatek za vklad %s." % [Bazaar.kc(price), Bazaar.kc(DEPOSIT_FEE)], 4.0)
		return false
	pl.money -= total
	world.play_sfx(pid, "cash")
	pending.append({"kind": "koupe", "what": "pole", "ref": key, "price": price, "due_jd": _jd() + DEPOSIT_DAYS, "pid": pid})
	_msg(pid, "Kupní smlouva na %s podepsána (%s). Vklad do katastru za %d dní." % [parcel_label(key), Bazaar.kc(total), DEPOSIT_DAYS], 6.0)
	world.emit_game_event(pid, "property_bought", {"what": "pole", "id": key, "kc": total})
	return true


## Výkup parcely obcí: hned, za OBEC_SHARE ceny.
func sell_parcel_obci(pid: int, key: String) -> bool:
	var pl := _player(pid)
	if pl == null or String(parcel_owner.get(key, "")) != "hrac":
		return false
	var amount := roundi(float(parcel_price(key)) * OBEC_SHARE / 100.0) * 100
	pl.money += amount
	parcel_owner[key] = "obec"
	world.play_sfx(pid, "cash")
	_msg(pid, "Obec odkoupila %s za %s. Parcela je veřejná." % [parcel_label(key), Bazaar.kc(amount)], 5.0)
	return true


## Nabídka vlastního domu kupci (ne domov): kupec se objeví za několik dní podle ceny.
func list_house(pid: int, id: int) -> bool:
	if String(house_owner.get(id, "")) != "hrac" or _pending_has("dum", id):
		return false
	if world.estate.home_estate(pid) == id:
		_msg(pid, "Ve svém domově prodávat nemůžeš – nejdřív se odstěhuj.", 4.0)
		return false
	var price := roundi(float(house_price(id)) * HOUSE_SALE_SHARE / 1000.0) * 1000
	var days: int = clampi(SALE_DAYS[0] + (price / SALE_STEP_KC) * 2, SALE_DAYS[0], SALE_DAYS[1])
	pending.append({"kind": "prodej", "what": "dum", "ref": id, "price": price, "due_jd": _jd() + days, "pid": pid})
	_msg(pid, "%s nabídnut kupci za %s. Kupec se ozve za zhruba %d dní." % [house_label(id), Bazaar.kc(price), days], 5.0)
	return true


## Nastaví vlastní dům jako domov (M1.7 `set_home` + `apply_home`); starý byt / nájem tím končí.
func set_home_house(pid: int, id: int) -> bool:
	if String(house_owner.get(id, "")) != "hrac" or _pending_has("dum", id):
		return false
	world.estate.set_home(pid, id, -1, false)
	world.apply_home(pid)
	_msg(pid, "Domov je nyní %s." % house_label(id), 5.0)
	return true


func owned_houses() -> Array:
	var out := []
	for id in house_owner.keys():
		if String(house_owner[id]) == "hrac":
			out.append(int(id))
	out.sort()
	return out


func owned_parcels() -> Array:
	var out := []
	for key in parcel_owner.keys():
		if String(parcel_owner[key]) == "hrac":
			out.append(String(key))
	return out


## Řádky pro nabídku úřadu (rozjednané vklady a prodeje hráče).
func status_lines(pid: int) -> Array:
	var out := []
	var jd := _jd()
	for p in pending:
		if int(p["pid"]) != pid:
			continue
		var what := house_label(int(p["ref"])) if String(p["what"]) == "dum" else parcel_label(String(p["ref"]))
		if String(p["kind"]) == "koupe":
			out.append("Vklad: %s – zbývá %d dní." % [what, maxi(0, int(p["due_jd"]) - jd)])
		else:
			out.append("Prodej: %s – kupec se ozve za %d dní." % [what, maxi(0, int(p["due_jd"]) - jd)])
	return out


func _jd() -> int:
	return int(world.clock.jd()) if world and world.clock else 0


# ------------------------------------------------------------------ denní krok (vklady a prodeje)

func _process(delta: float) -> void:
	if world == null or world.clock == null:
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = CHECK_S
	var jd := _jd()
	if jd == _last_jd:
		return
	_last_jd = jd
	var rest := []
	for p in pending:
		if int(p["due_jd"]) <= jd:
			_finish(p)
		else:
			rest.append(p)
	pending = rest


func _finish(p: Dictionary) -> void:
	var pid := int(p["pid"])
	var what := String(p["what"])
	var ref = p["ref"]
	var koupe := String(p["kind"]) == "koupe"
	var label := house_label(int(ref)) if what == "dum" else parcel_label(String(ref))
	if what == "dum":
		var id := int(ref)
		house_owner[id] = "hrac" if koupe else "kupec"
		world.estate.set_estate_owner(id, String(house_owner[id]))
		if not koupe:
			var pl := _player(pid)
			if pl:
				pl.money += int(p["price"])
				world.play_sfx(pid, "cash")
	else:
		parcel_owner[String(ref)] = "hrac" if koupe else "obec"
	var subj := "Vklad proveden: %s" % label if koupe else "Prodej proveden: %s" % label
	var body := ("Katastr zapsal vlastnictví: %s je váš." % label if koupe
		else "Kupec zaplatil %s za %s. Částka připsána v hotovosti." % [Bazaar.kc(int(p["price"])), label])
	body += "\n(Zjednodušená herní simulace – ověřit aktuální znění zákonů.)"
	world.send_mail(pid, SELLER_NAME, subj, body)


# ------------------------------------------------------------------ ukládání

func to_dict() -> Dictionary:
	var ho := {}
	for k in house_owner:
		ho[str(k)] = house_owner[k]
	return {"houses": ho, "parcels": parcel_owner.duplicate(), "pending": pending.duplicate(true)}


## Načtení (SaveGame verze ≥ 2, klíč `katastr`; starý save bez klíče = nic nikomu nepatří a nic se neprodává).
func from_dict(d: Dictionary) -> void:
	house_owner = {}
	for k in (d.get("houses", {}) as Dictionary):
		house_owner[int(k)] = String(d["houses"][k])
	parcel_owner = (d.get("parcels", {}) as Dictionary).duplicate()
	pending = []
	for p in d.get("pending", []):
		if not (p is Dictionary):
			continue
		var q: Dictionary = (p as Dictionary).duplicate()
		q["pid"] = int(q.get("pid", 1))
		q["price"] = int(q.get("price", 0))
		q["due_jd"] = int(q.get("due_jd", 0))
		if String(q.get("what", "")) == "dum":
			q["ref"] = int(q.get("ref", 0))
		pending.append(q)
	if world and world.estate:
		for id in house_owner:
			if world.estate.estates.has(id):
				world.estate.set_estate_owner(id, String(house_owner[id]))
