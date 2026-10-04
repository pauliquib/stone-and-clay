## Bazar vozidel u silnice (M1.6): cedule „BAZAR“ nedaleko obce, nabídka 3–5 vozidel, která se mění každý týden
## (seed podle týdne), koupě za peníze (vozidlo se přistaví k domovu hráče – M1.7 `World.home_label`) a výkup vlastních koupených vozidel
## za 60 % ceny podle poškození. Základní vozidla rodiny (Oktávka, kolo, Javor) se neprodávají.
## Interakce: `interactables(id)` → položka „custom“ (World.interactables). Stav (prodané kusy) ukládá SaveGame.
## PC / online bazar později (M3.4) použije stejné API: `offers()`, `buy(id, idx)`, `sell_value(car)`, `sell(id, car)`.
class_name Bazaar
extends Node3D

## Přibližná poloha cedule (x, z) ve hře – DOPLNIT: skutečné místo u silnice upřesní uživatel (výchozí = kousek od návsi);
## za běhu se snapne na nejbližší uzel silnice (okresky / obecní cesty do SNAP_R), takže funguje i bez ručních souřadnic.
const HINT := Vector2(170.0, 150.0)
const SNAP_R := 350.0
const SNAP_KINDS := ["residential", "unclassified", "tertiary", "service"]
const SIDE_OFFSET := 4.5             # cedule stojí takhle vpravo od osy silnice (m)
const SELL_R := 30.0                 # vozidlo k výkupu musí stát nejvýš tak daleko od cedule (m)
const SELL_RATIO := 0.6              # výkup: 60 % původní ceny, snížené podle poškození
const INTERACT_R := 4.0

var world: World
var pos := Vector3.ZERO              # poloha cedule (svět)
var ok := false
var sold := {}                       # klíč nabídky "týden:index" → true (už koupeno)
var _cache_week := -1
var _cache: Array = []


func setup(w: World) -> void:
	world = w
	var g: RoadGraph = w.traffic.graph
	var p2 := HINT
	var side := Vector2.ZERO
	if g != null:
		var cand := g.nodes_within(HINT, SNAP_R, SNAP_KINDS)
		var best := -1
		var bd := INF
		for i in cand:
			var d := g.nodes[i].distance_to(HINT)
			if d < bd:
				bd = d
				best = i
		if best >= 0:
			p2 = g.nodes[best]
			var nb: Array = g.adj[best]
			if not nb.is_empty():
				var dir: Vector2 = (g.nodes[nb[0]] - p2).normalized()
				side = Vector2(dir.y, -dir.x) * SIDE_OFFSET           # vpravo od směru k prvnímu sousedovi
	p2 += side
	pos = Vector3(p2.x, w.terrain.height_at(p2.x, p2.y), p2.y)
	_build_sign()
	ok = true


func _build_sign() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.32, 0.22, 0.13)
	wood.roughness = 0.9
	var board := StandardMaterial3D.new()
	board.albedo_color = Color(0.93, 0.85, 0.2)
	board.roughness = 0.7
	var root := Node3D.new()
	root.name = "CedulePosBazar"
	root.position = pos
	add_child(root)
	for sx in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.12, 2.6, 0.12)
		post.mesh = bm
		post.material_override = wood
		post.position = Vector3(sx * 0.9, 1.3, 0.0)
		root.add_child(post)
	var b := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(2.2, 0.95, 0.06)
	b.mesh = bb
	b.material_override = board
	b.position = Vector3(0, 2.05, 0.0)
	root.add_child(b)
	for zz in [0.04, -0.04]:
		var l := Label3D.new()
		l.text = "BAZAR\nauta · motorky · traktory"
		l.font_size = 64
		l.pixel_size = 0.0038
		l.modulate = Color(0.1, 0.06, 0.03)
		l.outline_size = 0
		l.position = Vector3(0, 2.05, zz)
		l.rotation.y = 0.0 if zz > 0.0 else PI
		l.double_sided = false
		root.add_child(l)


func interactables(id: int) -> Array:
	var p: Player = world.players.get(id)
	if not ok or p == null or p.inside != "":
		return []
	return [{"pos": pos + Vector3(0, 1.2, 0), "r": INTERACT_R, "kind": "custom", "text": "Bazar vozidel – koupit / prodat",
		"action": open_menu}]


# ------------------------------------------------------------------ nabídka

func week_index() -> int:
	return int(world.clock.day() / 7)


## Nabídka tohoto týdne (stejná pro celý týden, seed podle týdne): [{key, id, name, year, price, damage, paint, plate, sold}].
func offers() -> Array:
	var w := week_index()
	if w != _cache_week:
		_cache = _make_offers(w)
		_cache_week = w
		for k in sold.keys():                       # prodané kusy z minulých týdnů už nepotřebujeme
			if not String(k).begins_with("%d:" % w):
				sold.erase(k)
	for o in _cache:
		o["sold"] = sold.has(o["key"])
	return _cache


func _make_offers(w: int) -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = 7301 + w * 97
	var ids: Array = []
	for id in CarModel.MODELS:
		if int(CarModel.MODELS[id].get("cena", 0)) > 0:
			ids.append(id)
	for i in range(ids.size() - 1, 0, -1):          # zamíchání podle týdne (Fisher–Yates)
		var j := r.randi_range(0, i)
		var t = ids[i]
		ids[i] = ids[j]
		ids[j] = t
	var n := mini(3 + r.randi() % 3, ids.size())
	var out: Array = []
	for i in n:
		var id: String = ids[i]
		var m: Dictionary = CarModel.MODELS[id]
		var year := mini(int(m.get("rok", 2000)) + r.randi_range(-2, 8), 2025)
		var dmg := r.randi_range(0, 35)
		var jitter := r.randf_range(0.9, 1.1)
		var hue := r.randf()
		var price := int(float(m["cena"]) * (1.0 + (year - int(m.get("rok", 2000))) * 0.035) * (1.0 - dmg / 250.0) * jitter / 500.0) * 500
		out.append({"key": "%d:%d" % [w, i], "id": id, "name": String(m.get("name", id)), "year": year,
			"price": maxi(price, 1000), "damage": dmg, "paint": Color.from_hsv(hue, r.randf_range(0.35, 0.75), r.randf_range(0.35, 0.8)),
			"plate": "%dQQ %04d" % [r.randi_range(1, 9), r.randi_range(0, 9999)], "sold": false})
	return out


static func kc(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = " " + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out + " Kč"


# ------------------------------------------------------------------ menu

func open_menu(id: int) -> void:
	var cl = world.clients.get(id)
	var p: Player = world.players.get(id)
	if cl == null or p == null:
		return
	var opts := []
	for o in offers():
		if o["sold"]:
			continue
		var c := CarModel.catalog(o["id"])
		var label := "%s, %d · %s · poškození %d %% · ŘP %s" % [o["name"], o["year"], kc(o["price"]), o["damage"], c["skupina_rp"]]
		opts.append([label, buy.bind(id, o["key"]), p.money >= o["price"]])
	if opts.is_empty():
		opts.append(["(tento týden nic dalšího – přijď příští)", func(): pass, false])
	opts.append(["Prodat moje vozidlo…", open_sell_menu.bind(id)])
	cl.hud.open_menu("Bazar vozidel", "Máš %s. Nabídka se mění každý týden. Koupené vozidlo ti přistavíme domů (%s); výkup dává %d %% ceny podle poškození."
		% [kc(p.money), world.home_label(id), roundi(SELL_RATIO * 100.0)], opts)


func open_sell_menu(id: int) -> void:
	var cl = world.clients.get(id)
	var p: Player = world.players.get(id)
	if cl == null or p == null:
		return
	var opts := []
	for c in sellable(id):
		opts.append(["%s – výkup %s (poškození %d %%)" % [c.model.spec.get("name", c.model_id), kc(sell_value(c)), roundi(c.damage)],
			sell.bind(id, c)])
	if opts.is_empty():
		opts.append(["(nemáš tu nic k prodeji)", func(): pass, false])
	opts.append(["← Zpět", open_menu.bind(id)])
	cl.hud.open_menu("Výkup vozidel", "Vykoupím jen vozidla z bazaru, která stojí u cedule (do %d m) a nikdo v nich nesedí. Rodinná vozidla (Oktávka, kolo, Javor) nejdou prodat." % roundi(SELL_R), opts)


# ------------------------------------------------------------------ koupě a prodej

func _offer(key: String) -> Dictionary:
	for o in offers():
		if o["key"] == key:
			return o
	return {}


func buy(id: int, key: String) -> Car:
	var p: Player = world.players.get(id)
	var o := _offer(key)
	if p == null or o.is_empty() or o["sold"]:
		return null
	if p.money < int(o["price"]):
		world.notify(id, "show_message", ["Na to nemáš dost peněz.", 2.5])
		return null
	p.money -= int(o["price"])
	sold[key] = true
	var c := deliver(id, o["id"], o["paint"], o["plate"], int(o["year"]), int(o["price"]), float(o["damage"]))
	world.play_sfx(id, "cash")
	world.notify(id, "show_message", ["Koupeno: %s (%s). Stojí u tvého domova (%s)." % [o["name"], kc(o["price"]), world.home_label(id)], 4.0])
	return c


## Vytvoří vozidlo hráče `id` u domova – parkoviště místa „domov“ (nebo na `at` [Vector3 poloha, yaw] při načtení hry).
func deliver(id: int, model_id: String, paint: Color, plate: String, year: int, price: int, damage: float, at := []) -> Car:
	var t: Traffic = world.traffic
	var c := t.make_car(model_id, paint, false, plate)
	c.owner_id = id
	c.bazaar_price = price
	c.bazaar_year = year
	c.damage = damage
	c.name = "Bazar_%s_%d" % [model_id, t.vehicles_of(id).size()]
	if at.size() == 2:
		var ap: Vector3 = at[0]
		t.place_car(c, Vector2(ap.x, ap.z), float(at[1]))
	else:
		var home: Place = world.places["domov"]
		var side := Vector3.ZERO if id == 1 else Basis(Vector3.UP, home.park_yaw) * Vector3(4.0 * (id - 1), 0, 0)
		var base := Vector2(home.park.x + side.x, home.park.z + side.z)
		var size := Vector3(c.model.half_width * 2.0 + 0.3, 1.4, c.model.length + 0.3)
		var spot := t.free_spot(base, home.park_yaw, size)
		t.place_car(c, Vector2(spot.x, spot.y), spot.z)
	if not t.player_vehicles.has(id):
		t.player_vehicles[id] = []
	t.player_vehicles[id].append(c)
	world._connect_car(c)
	return c


## Vozidla hráče, která bazar vykoupí: koupená v bazaru, u cedule, bez řidiče.
func sellable(id: int) -> Array:
	var p: Player = world.players.get(id)
	var out := []
	for c in world.traffic.vehicles_of(id):
		if c.bazaar_price > 0 and c != p.car and c.global_position.distance_to(pos) <= SELL_R:
			out.append(c)
	return out


## Výkupní cena: 60 % pořizovací ceny, snížené podle poškození (0 % = plná, 100 % = zbývá 1/3), nejméně 5 %.
func sell_value(c: Car) -> int:
	return roundi(float(c.bazaar_price) * SELL_RATIO * maxf(1.0 - c.damage / 150.0, 0.05) / 100.0) * 100


func sell(id: int, c: Car) -> void:
	var p: Player = world.players.get(id)
	if p == null or c == null or not is_instance_valid(c) or c.bazaar_price <= 0 or p.car == c:
		return
	var v := sell_value(c)
	p.money += v
	world.traffic.player_vehicles[id].erase(c)
	c.detach_trailer()
	c.queue_free()
	world.play_sfx(id, "cash")
	world.notify(id, "show_message", ["Prodáno za %s." % kc(v), 3.0])


# ------------------------------------------------------------------ uložení

func to_dict() -> Dictionary:
	return {"sold": sold.keys(), "week": week_index()}


func from_dict(d: Dictionary) -> void:
	sold.clear()
	if int(d.get("week", -1)) == week_index():
		for k in d.get("sold", []):
			sold[String(k)] = true
	_cache_week = -1
