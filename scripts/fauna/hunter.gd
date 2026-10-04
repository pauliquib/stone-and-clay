## Myslivost a hospodáři (krok Příroda 04): krmelce a posed u Myslivecké chaty, zimní shromažďování zvěře
## u krmelce, vyzvednutí uhynulé zvěře po nahlášené srážce, shozené parůžky (březen–duben) a včelař
## u nejbližší včelnice (úkol Med: kukla, kouřák, okuřování úlů).
##
## Myslivec Franta u chaty (Place.KEEPERS["chata"]) zůstává obsluhou místa; tady je jen to, co se děje
## v lese. Nic tu nelovi – myslivec sčítá, přikrmuje a odváží zvěř sraženou na silnici.
##
## Interakce (klávesa E) dodává `interactables(id)` – World je přidá k místům; položky mají druh "custom"
## a `action` = Callable, který LocalClient zavolá s id hráče (bound argumenty přijdou až za id).
##
## Zvěř u krmelce: v zimě (`FEEDER_MONTHS` / sníh nad `FEEDER_SNOW` / krmelec naplněný úkolem) se `home`
## srnčích skupin z okruhu `FEEDER_R` přesune ke krmelci a vůdce skupiny za soumraku a v noci (od `FEED_FROM`
## do `FEED_TO` h) k němu sám zamíří. Mimo sezónu se původní `home` vrátí.
class_name Hunter
extends Node3D

# ---- krmelce a posed
const FEEDERS := 2                   # počet krmelců kolem chaty
const FEEDER_DIST := [80.0, 380.0]   # jak daleko od chaty (m) se hledá místo
const FEEDER_R := 600.0              # zvěř z tohoto okruhu se v zimě táhne ke krmelci (m)
const FEEDER_MONTHS := [12, 1, 2]
const FEEDER_SNOW := 0.3             # nebo když leží aspoň tolik sněhu
const FEEDER_FULL_H := 72.0          # krmelec naplněný úkolem táhne zvěř tolik herních hodin i mimo zimu
const FEED_FROM := 16.0              # zvěř se ke krmelci vydává od této hodiny …
const FEED_TO := 8.0                 # … do této
const FEED_SPECIES := ["srnec"]
const FEEDER_TICK := 15.0            # jak často (s) se přepočítává shromažďování zvěře
const STAND_DIST := [50.0, 95.0]     # posed stojí tak daleko od prvního krmelce (m)
# ---- vyzvednutí uhynulé zvěře
const PICKUP_WAIT_S := 45.0          # po nahlášení myslivec dorazí za tolik s reálného času
const PICKUP_FROM_D := 60.0          # … a přichází z takové vzdálenosti (od chaty)
const PICKUP_LOAD_S := 3.5
const PICKUP_QUIET_D := 120.0        # dál než tolik od hráče se zvíře odveze bez procházky (nikdo nevidí)
const WALK_SPEED := 1.7
# ---- parůžky, včelař
const ANTLER_R := 350.0              # parůžky se hledají tak daleko od chaty (m)
const SMOKE_S := 5.0                 # okuřování úlů
const BEEKEEPER_NAME := "Včelař Vilém"
const BEEKEEPER_MONTHS := [4, 9]     # včelař pracuje od dubna do září …
const BEEKEEPER_HOURS := [7.0, 19.0] # … přes den

var world: World
var fauna: Fauna
var terrain: Terrain
var clock: Clock
var rng := RandomNumberGenerator.new()
var chata := Vector3.ZERO
var feeders: Array[Vector3] = []
var stand := Vector3.INF
var beekeeper: Npc
var apiary: Apiary

var _feeder_nodes: Array = []        # Node3D krmelců
var _hay: Array = []                 # MeshInstance3D sena (viditelné, když krmelec táhne zvěř)
var _filled_until: Array[float] = [] # herní minuty, do kdy krmelec táhne zvěř po naplnění
var _antlers: Array = []             # Node3D shozených parůžků
var _pickups: Array = []             # {animal, pos, t, phase, npc, from}
var _tick := 5.0
var _bee_t := 2.0
var _smoking := {}                   # id hráče → true


func setup(w: World) -> void:
	world = w
	fauna = w.fauna
	terrain = w.terrain
	clock = w.clock
	rng.seed = 7071
	var pl: Place = w.places["chata"]
	chata = pl.door
	_build_feeders()
	_build_stand()
	_build_beekeeper()
	refresh()


# ------------------------------------------------------------------ stavba: krmelce, posed

func _flat(p: Vector3, r := 2.5, tol := 0.7) -> bool:
	var y := terrain.height_at(p.x, p.z)
	for o in [Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r)]:
		if absf(terrain.height_at(p.x + o.x, p.z + o.y) - y) > tol:
			return false
	return true


## Místo v lese u chaty: dost lesa, rovné, ne u silnice, dost daleko od `avoid`.
func _pick_site(center: Vector3, rmin: float, rmax: float, hab: String, avoid: Array, min_gap: float) -> Vector3:
	var best := Vector3.INF
	var bs := -INF
	for i in 60:
		var a := rng.randf() * TAU
		var r := rng.randf_range(rmin, rmax)
		var p := center + Vector3(cos(a) * r, 0.0, sin(a) * r)
		var sc := fauna.score(hab, p.x, p.z)
		if sc < 0.2 or world.dist_to_roads(Vector2(p.x, p.z)) < 25.0 or not _flat(p):
			continue
		var ok := true
		for o in avoid:
			var ov: Vector3 = o
			if ov.distance_to(p) < min_gap:
				ok = false
		if ok and sc > bs:
			bs = sc
			best = p
	if best == Vector3.INF:
		best = center + Vector3(rmin, 0.0, rmin)         # nouzově vedle
	best.y = terrain.height_at(best.x, best.z)
	return best


func _static_box(parent: Node3D, pos: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	cs.position = pos
	parent.add_child(cs)


func _build_feeders() -> void:
	var taken: Array = [chata]
	for i in FEEDERS:
		var p := _pick_site(chata, FEEDER_DIST[0], FEEDER_DIST[1], "forest", taken, 120.0)
		taken.append(p)
		feeders.append(p)
		_filled_until.append(-1.0)
		_feeder_nodes.append(_make_feeder(p, rng.randf() * TAU, i))


## Krmelec: dva sloupky se stříškou, žlab a žebřiňák se senem (statická kolize vrstvy 1).
func _make_feeder(p: Vector3, yaw: float, i: int) -> Node3D:
	var root := StaticBody3D.new()
	root.name = "Krmelec_%d" % i
	root.collision_layer = 1
	root.collision_mask = 0
	root.position = p
	root.rotation.y = yaw
	add_child(root)
	var wood := Color(0.42, 0.3, 0.18)
	var dark := wood.darkened(0.25)
	var k := MeshKit.new()
	for sx: float in [-1.4, 1.4]:
		k.box(Vector3(sx, 0.7, 0.0), Vector3(0.14, 2.2, 0.14), dark)              # sloupek
		k.box(Vector3(sx, 0.9, 0.0), Vector3(0.1, 0.1, 1.1), dark)                 # příčka
	k.box(Vector3(0.0, 0.32, 0.55), Vector3(3.0, 0.08, 0.5), wood)                 # žlab: dno
	k.box(Vector3(0.0, 0.46, 0.8), Vector3(3.0, 0.24, 0.05), wood)                 # přední stěna
	k.box(Vector3(0.0, 0.46, 0.3), Vector3(3.0, 0.24, 0.05), wood)                 # zadní stěna
	for sx: float in [-1.5, 1.5]:
		k.box(Vector3(sx, 0.46, 0.55), Vector3(0.05, 0.24, 0.55), wood)            # boky žlabu
	for sx: float in [-0.9, -0.3, 0.3, 0.9]:
		k.box(Vector3(sx, 1.2, -0.1), Vector3(0.05, 0.9, 0.05), wood, Vector3(0.45, 0.0, 0.0))   # tyčky žebřiňáku
	k.box(Vector3(0.0, 2.0, -0.35), Vector3(3.4, 0.06, 1.3), Color(0.32, 0.25, 0.18), Vector3(-0.28, 0.0, 0.0))  # stříška
	k.box(Vector3(0.0, 2.0, 0.35), Vector3(3.4, 0.06, 1.3), Color(0.3, 0.23, 0.16), Vector3(0.28, 0.0, 0.0))
	MeshKit.mesh_instance(root, k.commit(MeshKit.vc_material(0.85)), 500.0)
	var hk := MeshKit.new()
	hk.box(Vector3(0.0, 0.5, 0.55), Vector3(2.8, 0.2, 0.4), Color(0.78, 0.66, 0.3))    # seno ve žlabu
	hk.box(Vector3(0.0, 1.25, -0.1), Vector3(2.5, 0.7, 0.35), Color(0.72, 0.6, 0.28), Vector3(0.45, 0.0, 0.0))  # seno v žebřiňáku
	var hay := MeshKit.mesh_instance(root, hk.commit(MeshKit.vc_material(1.0)), 500.0)
	hay.name = "Seno"
	_hay.append(hay)
	_static_box(root, Vector3(0.0, 0.45, 0.55), Vector3(3.1, 0.9, 0.8))
	_static_box(root, Vector3(-1.4, 1.0, 0.0), Vector3(0.3, 2.0, 0.3))
	_static_box(root, Vector3(1.4, 1.0, 0.0), Vector3(0.3, 2.0, 0.3))
	return root


## Posed: čtyři nohy, plošina, kabina se třemi stěnami a stříškou, žebřík. Čelem ke krmelci.
func _build_stand() -> void:
	if feeders.is_empty():
		return
	var avoid: Array = [chata]
	avoid.append_array(feeders)
	stand = _pick_site(feeders[0], STAND_DIST[0], STAND_DIST[1], "edge", avoid, 40.0)
	var to := feeders[0] - stand
	var yaw := atan2(to.x, to.z)
	var root := StaticBody3D.new()
	root.name = "Posed"
	root.collision_layer = 1
	root.collision_mask = 0
	root.position = stand
	root.rotation.y = yaw
	add_child(root)
	var wood := Color(0.4, 0.29, 0.17)
	var dark := wood.darkened(0.25)
	var k := MeshKit.new()
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			k.box(Vector3(sx, 1.15, sz), Vector3(0.14, 2.9, 0.14), dark)            # nohy (zapuštěné pod terén)
	k.box(Vector3(0.0, 2.45, 0.0), Vector3(2.3, 0.1, 2.3), wood)                    # plošina
	k.box(Vector3(0.0, 3.1, -1.1), Vector3(2.3, 1.2, 0.06), wood)                   # zadní stěna
	k.box(Vector3(-1.1, 3.1, 0.0), Vector3(0.06, 1.2, 2.3), wood)                   # boky
	k.box(Vector3(1.1, 3.1, 0.0), Vector3(0.06, 1.2, 2.3), wood)
	k.box(Vector3(0.0, 2.85, 1.1), Vector3(2.3, 0.5, 0.06), wood)                   # parapet vpředu (výhled nad ním)
	k.box(Vector3(0.0, 3.85, 0.0), Vector3(2.7, 0.07, 2.7), Color(0.3, 0.3, 0.28), Vector3(0.08, 0.0, 0.0))   # stříška
	for sx: float in [-0.45, 0.45]:
		k.box(Vector3(sx, 1.3, -1.35), Vector3(0.07, 3.0, 0.07), dark, Vector3(-0.15, 0.0, 0.0))    # žebřík: postranice
	for j in 9:
		k.box(Vector3(0.0, 0.4 + j * 0.3, -1.2 - j * 0.045), Vector3(0.9, 0.05, 0.05), wood)        # příčle
	MeshKit.mesh_instance(root, k.commit(MeshKit.vc_material(0.85)), 500.0)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_static_box(root, Vector3(sx, 1.15, sz), Vector3(0.22, 2.9, 0.22))
	_static_box(root, Vector3(0.0, 3.1, -1.1), Vector3(2.3, 1.2, 0.2))
	_static_box(root, Vector3(-1.1, 3.1, 0.0), Vector3(0.2, 1.2, 2.3))
	_static_box(root, Vector3(1.1, 3.1, 0.0), Vector3(0.2, 1.2, 2.3))


# ------------------------------------------------------------------ včelař

func _build_beekeeper() -> void:
	var ref: Vector3 = world.lot_door()     # M1.7: stálý bod (usedlost), ne byt hráče
	var bd := INF
	for n in fauna.root_insects.get_children():
		if n is Apiary and (n as Apiary).global_position.distance_to(ref) < bd:
			bd = (n as Apiary).global_position.distance_to(ref)
			apiary = n as Apiary
	if apiary == null:
		return
	var away := ref - apiary.global_position
	away.y = 0.0
	var pos := apiary.global_position + away.normalized() * 4.5
	pos.y = terrain.height_at(pos.x, pos.z)
	beekeeper = Npc.make(BEEKEEPER_NAME, "", Color(0.92, 0.92, 0.88), 6161, pos, atan2(-away.x, -away.z), world)
	beekeeper.persona = Persona.make({"name": BEEKEEPER_NAME, "trait": "moudry", "job": "včelař", "age": 63,
		"hobby": "Včely jsou chytřejší než my. Stačí je nehonit.", "topics": ["vcely", "les", "pocasi"]})
	beekeeper.role = "keeper"
	beekeeper.place = "vcelar"
	add_child(beekeeper)
	world.npcs["vcelar"] = beekeeper


func beekeeper_pos() -> Vector3:
	return beekeeper.global_position if beekeeper != null else Vector3.INF


func apiary_pos() -> Vector3:
	return apiary.global_position if apiary != null else Vector3.INF


func _beekeeper_on() -> bool:
	var m := clock.month()
	var h := clock.hour()
	return m >= BEEKEEPER_MONTHS[0] and m <= BEEKEEPER_MONTHS[1] and h >= BEEKEEPER_HOURS[0] and h < BEEKEEPER_HOURS[1]


# ------------------------------------------------------------------ krmelce: stav a shromažďování zvěře

func feeder_active(i: int) -> bool:
	if clock.month() in FEEDER_MONTHS or world.weather.snow_cover > FEEDER_SNOW:
		return true
	return clock.minutes < _filled_until[i]


func nearest_feeder(pos: Vector3) -> Vector3:
	var best := Vector3.INF
	var bd := INF
	for f in feeders:
		if f.distance_to(pos) < bd:
			bd = f.distance_to(pos)
			best = f
	return best


## Úkol Krmivo: krmelec je naplněný, zvěř k němu chodí i mimo zimu.
func fill_feeder(i: int) -> void:
	_filled_until[i] = clock.minutes + FEEDER_FULL_H * 60.0
	refresh()


## Po změně data / naplnění: seno v krmelcích jen tam, kde se přikrmuje; včelař jen v sezóně.
func refresh() -> void:
	for i in _hay.size():
		(_hay[i] as MeshInstance3D).visible = feeder_active(i)
	if beekeeper != null:
		var on := _beekeeper_on()
		beekeeper.visible = on
		beekeeper.collision_layer = 4 if on else 0
	_feeder_tick(true)


## Přepočte `home` skupin podle krmelců; není-li `home_only`, vůdce za soumraku a v noci ke krmelci i zamíří.
func _feeder_tick(home_only := false) -> void:
	var night := clock.hour() >= FEED_FROM or clock.hour() < FEED_TO
	for herd in fauna.herds:
		var lead := (herd as Herd).get_leader() as Animal
		if lead == null or not (lead.species in FEED_SPECIES):
			continue
		var bi := -1
		var bd := FEEDER_R
		for i in feeders.size():
			var d := feeders[i].distance_to((herd as Herd).home)
			if d < bd and feeder_active(i):
				bd = d
				bi = i
		for m in (herd as Herd).members:
			if not is_instance_valid(m):
				continue
			if not m.has_meta("home0"):
				m.set_meta("home0", m.home)
			if bi < 0:
				m.home = m.get_meta("home0")                    # mimo sezónu se skupina vrací domů
			else:
				m.home = feeders[bi] + Vector3(rng.randf_range(-6.0, 6.0), 0.0, rng.randf_range(-6.0, 6.0))
		if home_only or bi < 0 or not night or lead.dead or (herd as Herd).alarmed() or lead.threat != null:
			continue
		if lead.state in ["graze", "move"] and lead.global_position.distance_to(feeders[bi]) > 18.0:
			lead.target = feeders[bi] + Vector3(rng.randf_range(-7.0, 7.0), 0.0, rng.randf_range(-7.0, 7.0))
			lead.state = "move"
			lead.state_t = 0.0


func _process(delta: float) -> void:
	if world == null or fauna == null:
		return
	_tick -= delta
	if _tick <= 0.0:
		_tick = FEEDER_TICK
		_feeder_tick()
	_bee_t -= delta
	if _bee_t <= 0.0:
		_bee_t = 5.0
		if beekeeper != null:
			var on := _beekeeper_on()
			if on != beekeeper.visible:
				beekeeper.visible = on
				beekeeper.collision_layer = 4 if on else 0
	_pickup_step(delta)


# ------------------------------------------------------------------ vyzvednutí sražené zvěře

## Po nahlášení srážky (nebo po pokutě) myslivec zvíře odveze. `animal` může být null / už zmizelé.
func request_pickup(animal, pos: Vector3) -> void:
	if animal == null or not is_instance_valid(animal) or not (animal is Animal) or not (animal as Animal).dead:
		return
	_pickups.append({"animal": animal, "pos": (animal as Animal).global_position, "t": PICKUP_WAIT_S, "phase": 0,
		"npc": null, "from": pos})


func _walk_to(npc: Npc, target: Vector3, delta: float) -> bool:
	var to := target - npc.global_position
	to.y = 0.0
	var d := to.length()
	if d < 0.5:
		npc.visual.speed = 0.0
		return true
	var p := npc.global_position + to / d * minf(WALK_SPEED * delta, d)
	p.y = terrain.height_at(p.x, p.z)
	npc.global_position = p
	npc.base_yaw = atan2(to.x, to.z)
	npc.face_player = false
	npc.visual.speed = WALK_SPEED
	return false


func _pickup_step(delta: float) -> void:
	for e in _pickups.duplicate():
		var a = e["animal"]
		var alive: bool = a != null and is_instance_valid(a)
		var npc: Npc = e["npc"]
		match int(e["phase"]):
			0:
				e["t"] = float(e["t"]) - delta
				if float(e["t"]) > 0.0:
					continue
				if not alive:
					_pickups.erase(e)
				elif world.nearest_player_dist(e["pos"]) > PICKUP_QUIET_D:
					(a as Node).queue_free()                    # nikdo se nedívá – odveze se bez procházky
					_pickups.erase(e)
				else:
					var epos: Vector3 = e["pos"]
					var dir: Vector3 = chata - epos
					dir.y = 0.0
					var start: Vector3 = epos + dir.normalized() * minf(PICKUP_FROM_D, dir.length())
					start.y = terrain.height_at(start.x, start.z)
					npc = Npc.make("Myslivec", "hunter", Color(0.25, 0.32, 0.2), 5150, start, atan2(-dir.x, -dir.z), world)
					add_child(npc)
					npc.face_player = false
					e["npc"] = npc
					e["from"] = start
					e["phase"] = 1
			1:
				if not alive:
					e["phase"] = 3
				elif _walk_to(npc, e["pos"], delta):
					e["phase"] = 2
					e["t"] = PICKUP_LOAD_S
					npc.say("Tak, a jedeme domů, kamaráde.", 3.0)
			2:
				e["t"] = float(e["t"]) - delta
				if float(e["t"]) <= 0.0:
					if alive:
						(a as Node).queue_free()
					e["phase"] = 3
			3:
				if _walk_to(npc, e["from"], delta):
					npc.queue_free()
					_pickups.erase(e)


# ------------------------------------------------------------------ shozené parůžky

func spawn_antlers(n: int) -> void:
	clear_antlers()
	var taken: Array = [chata]
	for i in n:
		var p := _pick_site(chata, 40.0, ANTLER_R, "edge", taken, 45.0)
		taken.append(p)
		var node := Node3D.new()
		node.name = "Paruzky_%d" % i
		node.position = p
		node.rotation.y = rng.randf() * TAU
		var k := MeshKit.new()
		var bone := Color(0.82, 0.75, 0.6)
		for s: float in [-1.0, 1.0]:
			k.capsule(Vector3(s * 0.07, 0.05, 0.0), 0.022, 0.32, bone, Vector3(0.9 * s, 0.0, 0.5 * s))      # kmen
			k.capsule(Vector3(s * 0.11, 0.09, 0.06), 0.014, 0.16, bone, Vector3(0.4, 0.0, 0.9 * s))        # výsada
		MeshKit.mesh_instance(node, k.commit(MeshKit.vc_material(0.9)), 120.0)
		add_child(node)
		_antlers.append(node)


func antlers_left() -> int:
	var n := 0
	for a in _antlers:
		if is_instance_valid(a):
			n += 1
	return n


func nearest_antler(pos: Vector3) -> Vector3:
	var best := Vector3.INF
	var bd := INF
	for a in _antlers:
		if is_instance_valid(a) and (a as Node3D).global_position.distance_to(pos) < bd:
			bd = (a as Node3D).global_position.distance_to(pos)
			best = (a as Node3D).global_position
	return best


func clear_antlers() -> void:
	for a in _antlers:
		if is_instance_valid(a):
			(a as Node).queue_free()
	_antlers.clear()


# ------------------------------------------------------------------ interakce (E)

## Aktivní úkol hráče (bez typu – volají se metody podtříd: deliver, smoked).
func _active_quest(id: int):
	var q: Quests = world.quests_of(id)
	return q.active if q else null


func interactables(id: int) -> Array:
	var out := []
	var p: Player = world.players.get(id)
	if p == null or p.horse != null:
		return out
	var act = _active_quest(id)
	for i in feeders.size():
		var txt := "Krmelec – %s" % ("plný sena a kaštanů" if feeder_active(i) else "prázdný")
		if act != null and act.id == "krmivo" and act.step == 1:
			txt = "Krmelec – vysypat pytel krmiva"
		out.append({"pos": feeders[i], "r": 3.6, "kind": "custom", "text": txt, "action": _on_feeder.bind(i)})
	for a in _antlers:
		if is_instance_valid(a):
			out.append({"pos": (a as Node3D).global_position, "r": 2.2, "kind": "custom", "text": "Shozené parůžky – sebrat",
				"action": _pick_antler.bind(a)})
	if beekeeper != null and beekeeper.visible:
		out.append({"pos": beekeeper.global_position, "r": 2.8, "kind": "custom", "text": BEEKEEPER_NAME,
			"action": _on_beekeeper})
	if apiary != null and act != null and act.id == "med" and act.step == 1 and not _smoking.has(id):
		for h in apiary.hives:
			if h.distance_to(p.global_position) < 3.4:
				out.append({"pos": h, "r": 3.4, "kind": "custom", "text": "Okuřovat úly kouřákem (%d s)" % int(SMOKE_S),
					"action": _smoke_hives})
				break
	return out


func _on_feeder(id: int, i: int) -> void:
	var act = _active_quest(id)
	if act != null and act.id == "krmivo" and act.step == 1:
		act.deliver(i)
		return
	world.notify(id, "show_message", ["Krmelec: %s. V zimě sem za soumraku chodí srnčí zvěř – pozoruj ji dalekohledem [X] z povzdálí." % (
		"seno a kaštany" if feeder_active(i) else "teď prázdný"), 5.0])


func _pick_antler(id: int, node: Node3D) -> void:
	if not is_instance_valid(node):
		return
	node.queue_free()
	_antlers.erase(node)
	var act = _active_quest(id)
	if act != null and act.id == "shoz":
		world.notify(id, "show_message", ["Našel jsi shozené parůžky.", 2.0])
		world.emit_game_event(id, "sfx", {"name": "pickup"})
	else:
		world.notify(id, "show_message", ["Shozené parůžky – nech je myslivci, nebo je hoď zpátky do lesa.", 3.0])


func _on_beekeeper(id: int) -> void:
	var cl = world.clients.get(id)
	if cl:
		cl.open_giver_menu("vcelar", BEEKEEPER_NAME, "„Včely nemají rády spěch, hluk ani pot. A ty smrdíš oběma.“")


func _smoke_hives(id: int) -> void:
	var p: Player = world.players.get(id)
	if p == null or _smoking.has(id):
		return
	_smoking[id] = true
	p.controls_locked = true
	world.notify(id, "show_message", ["Okuřuješ úly kouřákem… stůj v klidu.", SMOKE_S])
	_puff(p.global_position + Vector3(0, 0.9, 0) + Vector3(sin(p.yaw + PI), 0, cos(p.yaw + PI)) * 0.8)
	await get_tree().create_timer(SMOKE_S).timeout
	_smoking.erase(id)
	if not is_instance_valid(p):
		return
	p.controls_locked = false
	var act = _active_quest(id)
	if act != null and act.id == "med":
		act.smoked()


func _puff(pos: Vector3) -> void:
	var pt := CPUParticles3D.new()
	pt.amount = 40
	pt.lifetime = 2.5
	pt.one_shot = false
	pt.emitting = true
	pt.direction = Vector3.UP
	pt.spread = 25.0
	pt.gravity = Vector3(0.15, 0.25, 0.0)
	pt.initial_velocity_min = 0.2
	pt.initial_velocity_max = 0.5
	pt.scale_amount_min = 0.15
	pt.scale_amount_max = 0.3
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 6
	mesh.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.75, 0.72, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	pt.mesh = mesh
	add_child(pt)
	pt.global_position = pos
	get_tree().create_timer(SMOKE_S + 2.5).timeout.connect(pt.queue_free)
	get_tree().create_timer(SMOKE_S).timeout.connect(func(): pt.emitting = false)
