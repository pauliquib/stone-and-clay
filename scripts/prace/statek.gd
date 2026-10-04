## Statek „Na Kopci“ (M3.2, smyšlený) – pracoviště práce „Pomocník na farmě“ (`data/prace.json` → `statek_pomocnik`).
## Jeden uzel ve `World` (`World.statek`), vzniká v `World.add_player` až po hospodářství hráče (výběhy se nepřekrývají).
##
## - **Místo:** největší hospodářská budova na okraji obce z registru `Estate` (`Estate.pick_farmstead`: ne usedlost hráče,
##   ne bytový dům, aspoň `MIN_LOT` m od usedlosti, `R0`–`R1` m od návsi); zapíše se jí vlastník „hospodář“ (`Estate.set_estate_owner`,
##   hák pro M4.7). Bez dat budov bod u silnice na okraji obce (`FALLBACK_*`). Před budovou vznikne místo `Place` „statek“
##   (cedule, hospodář Vladimír – bručoun, nabídka prodeje ze dvora, E → práce přes `Jobs.place_options`).
## - **Výběh:** `Pen.setup_at` (stejná ohrada, kurník, chlívek a přístřešek jako u hráče) se stádem `HERD` (2 krávy, 6 slepic,
##   3 prasata – `FarmAnimal` z M2.6); Statek dědí `Farm` jen kvůli zvířatům, péči a zanedbání nepočítá (to je hospodářova věc).
## - **Stodola** s hromadou sena (cíl `seno_hromada` – akce `nabrat_seno`, jen na směně), koryta u přístřešků, hnojiště
##   a záhony za výběhem (vše jeden MeshKit mesh).
## - **Cíle pracovních úkolů** (poskytovatelé `Jobs.set_provider`): `statek_koryta`, `statek_napajecky`, `statek_stani`
##   (krávy na stání – při dojení je sem statek pošle, `FarmAnimal.hold`), `statek_hnizda`, `statek_hnuj`, `statek_zahony`.
## - Krmení: seno z hromady (`HAY_TAKE` otepí zapůjčených na směnu, `Jobs.lend`) → koryto (`nakrmit_koryto` otep spotřebuje).
## Daleko od hráče (`ACTIVE_R`) zvířata nestojí za výpočet – `set_process(false)`.
class_name Statek
extends Farm

const PLACE_KEY := "statek"
const TITLE := "Statek Na Kopci"
const JOB_ID := "statek_pomocnik"
const OWNER := "hospodář"
## Stádo: [druh, pohlaví, počet] – DOPLNIT: prompt „2 krávy, 6 slepic, 3 prasata“.
const HERD := [["krava", "f", 2], ["slepice", "f", 6], ["prase", "f", 3]]
const MIN_LOT := 150.0              # m od usedlosti hráče (tam je jeho hospodářství a hospodářské budovy jsou „jeho“)
const R0 := 250.0                   # m od návsi – „okraj obce“ začíná tady
const R1 := 1600.0                  # m od návsi – dál už jsou samoty mimo katastr / lesy
const FALLBACK_R := [350.0, 800.0]  # bez dat budov: uzel silnice v tomhle pásmu od návsi, co nejdál od usedlosti
const FALLBACK_OFF := 12.0          # m od osy silnice
const PEN_SEED := 3107
const HAY_TAKE := 3                 # otepí sena na jedno nabrání (tři koryta)
const TICK_S := 1.0
const ACTIVE_R := 220.0             # m – dál od hráče zvířata stojí (bez procesu)
const TARGET_Y := 0.7               # výška cílů akcí nad zemí (m)

var place: Place
var estate_id := 0                  # budova statku v `Estate` (0 = bez dat budov)
var hay_pos := Vector3.INF
var troughs: Array[Vector3] = []    # koryta (kurník, chlívek, přístřešek)
var drinkers: Array[Vector3] = []   # napáječky
var stands: Array[Vector3] = []     # stání pro dojení
var nests: Array[Vector3] = []      # hnízda v kurníku
var manure: Array[Vector3] = []     # kde se kydá hnůj
var beds: Array[Vector3] = []       # záhony za výběhem
var _hay_target := {}
var _tick := 0.0


func setup_statek(w: World) -> void:
	world = w
	name = "Statek"
	var site := _pick_site()
	if site.is_empty():
		push_warning("Statek: nenašlo se místo – práce na farmě nepůjde.")
		return
	_make_place(site[0], float(site[1]))
	pen = Pen.new()
	pen.name = "Vybeh_statek"
	add_child(pen)
	var c2: Vector2 = site[2]
	pen.setup_at(w, site[0], c2, PEN_SEED)
	if pen.ok:
		_layout()
		_build_extras()
		for h in HERD:
			for i in int(h[2]):
				_spawn(String(h[0]), String(h[1]), float(FarmSpecs.info(String(h[0])).get("grow_days", 60.0)) + 30.0)
		_hay_target = {"pos": hay_pos + Vector3(0, TARGET_Y, 0), "r": 1.8, "kind": "seno_hromada", "data": {"statek": true}}
		w.register_target(_hay_target)
	else:
		push_warning("Statek: výběh se nevešel – úkoly se zvířaty se přeskočí (zůstane jen místo).")
	_register_jobs()


# ------------------------------------------------------------------ místo

## [dveře (Vector3), face_yaw, střed budovy (Vector2)] nebo [].
func _pick_site() -> Array:
	var est: Estate = world.estate
	if est:
		var id := est.pick_farmstead(MIN_LOT, R0, R1)
		if id != 0:
			var e := est.info(id)
			var c: Vector2 = e["center"]
			var door: Vector3 = e["door"]
			var n: Vector3 = e["normal"]
			if door == Vector3.INF:
				# budova bez dveří v datech: bod před stěnou na straně k návsi
				var to := (est.centre - c).normalized() if est.centre.distance_to(c) > 1.0 else Vector2(0, 1)
				var r := sqrt(maxf(float(e["area"]), 20.0)) * 0.6 + 1.0
				door = Vector3(c.x + to.x * r, 0.0, c.y + to.y * r)
				n = Vector3(to.x, 0.0, to.y)
			n.y = 0.0
			n = n.normalized() if n.length() > 0.01 else Vector3(0, 0, 1)
			estate_id = id
			est.set_estate_owner(id, OWNER, PLACE_KEY)
			var d := door + n * 1.2
			d.y = world.terrain.height_at(d.x, d.z)
			return [d, atan2(n.x, n.z), c]
	# bez dat budov: uzel silnice na okraji obce co nejdál od usedlosti, statek kousek od silnice
	if world.graph == null:
		return []
	var centre := Vector2.ZERO
	var urad: Place = world.places.get("urad")
	if urad:
		centre = Vector2(urad.door.x, urad.door.z)
	var lot := world.lot_door()
	var best := -1
	var bd := -1.0
	for i in world.graph.nodes_within(centre, float(FALLBACK_R[1]), ["residential", "unclassified", "track", "service"]):
		var p: Vector2 = world.graph.nodes[i]
		if p.distance_to(centre) < float(FALLBACK_R[0]) or (world.graph.adj[i] as Array).is_empty():
			continue
		var dl := p.distance_to(Vector2(lot.x, lot.z))
		if dl > bd:
			bd = dl
			best = i
	if best < 0:
		return []
	var p0: Vector2 = world.graph.nodes[best]
	var nb: Vector2 = world.graph.nodes[int(world.graph.adj[best][0])]
	var dir := (nb - p0).normalized()
	var side := Vector2(-dir.y, dir.x)
	var dp := p0 + side * FALLBACK_OFF
	var d3 := Vector3(dp.x, world.terrain.height_at(dp.x, dp.y), dp.y)
	return [d3, atan2(-side.x, -side.y), dp + side * 8.0]


func _make_place(door: Vector3, face: float) -> void:
	var n := Vector3(sin(face), 0.0, cos(face))
	var park := door + n * 7.0
	var data := {"name": TITLE, "door_x": door.x, "door_z": door.z, "park_x": park.x, "park_z": park.z,
		"park_yaw": face + PI * 0.5, "face_yaw": face}
	place = Place.new()
	place.setup(PLACE_KEY, data, world.terrain, world)
	var root := world.get_node_or_null("Mista")
	if root:
		root.add_child(place)
	else:
		add_child(place)
	world.places[PLACE_KEY] = place
	if place.keeper:
		world.npcs[PLACE_KEY] = place.keeper


# ------------------------------------------------------------------ rozvržení a modely

## Body úkolů v souřadnicích výběhu (`Pen.to_world(lx, lz)`: x doprava, z od stavení dozadu).
func _layout() -> void:
	var hx := pen.half.x
	var hz := pen.half.y
	hay_pos = pen.to_world(hx + 4.2, -hz + 3.5)
	troughs = [pen.feed_pos("kurnik"), pen.feed_pos("chlivek"), pen.feed_pos("pristresek")]
	drinkers = [pen.water, pen.to_world(hx - 3.6, hz - 2.2)]
	stands = [pen.to_world(-hx + 1.6, hz - 4.6), pen.to_world(-hx + 3.6, hz - 4.6)]
	nests = [pen.to_world(-hx + 1.1, -hz + 1.8), pen.to_world(-hx + 2.1, -hz + 1.8)]
	manure = [pen.to_world(hx - 2.0, hz - 4.4), pen.to_world(-hx + 2.5, hz - 1.2), pen.to_world(hx - 4.5, -hz + 2.5)]
	beds = []
	for i in 4:
		beds.append(pen.to_world(-hx + 2.0 + i * 2.4, hz + 4.5))


func _build_extras() -> void:
	var k := MeshKit.new()
	var wood := Color(0.47, 0.34, 0.2)
	var dark := wood.darkened(0.35)
	var hay := Color(0.8, 0.68, 0.32)
	var rot := Vector3(0, pen.yaw, 0)
	# stodola: otevřený přístřešek na čtyřech sloupech, pod ním hromada sena (balíky)
	for sx: float in [-2.2, 2.2]:
		for sz: float in [-1.8, 1.8]:
			var pp := hay_pos + Basis(Vector3.UP, pen.yaw) * Vector3(sx, 0, sz)
			pp.y = world.terrain.height_at(pp.x, pp.z)
			k.box(pp + Vector3(0, 1.4, 0), Vector3(0.18, 2.8, 0.18), dark, rot)
	k.box(hay_pos + Vector3(0, 2.9, 0), Vector3(5.2, 0.14, 4.4), Color(0.36, 0.28, 0.2), rot + Vector3(0.1, 0, 0))
	for i in 3:
		for j in 2 - (i % 2):
			var off := Basis(Vector3.UP, pen.yaw) * Vector3(-1.1 + i * 1.1, 0, -0.5 + j * 1.0)
			k.box(hay_pos + off + Vector3(0, 0.35, 0), Vector3(1.0, 0.7, 0.9), hay.darkened(0.05 * (i + j)), rot)
	k.box(hay_pos + Vector3(0, 1.05, 0), Vector3(1.0, 0.7, 0.9), hay, rot + Vector3(0, 0.3, 0))
	# koryta u přístřešků
	for t in troughs:
		k.box(t + Vector3(0, 0.22, 0), Vector3(1.3, 0.3, 0.45), wood, rot)
		k.box(t + Vector3(0, 0.33, 0), Vector3(1.15, 0.06, 0.33), hay.darkened(0.25), rot)
	# hnojiště (hromada hnoje za chlívkem) a hnůj na místech ke kydání
	var hn := pen.to_world(pen.half.x + 3.2, pen.half.y - 2.0)
	k.sphere(hn + Vector3(0, 0.1, 0), 1.3, Color(0.3, 0.22, 0.12), Vector3(1.4, 0.45, 1.1))
	for m in manure:
		k.sphere(m + Vector3(0, 0.02, 0), 0.5, Color(0.33, 0.25, 0.14), Vector3(1.2, 0.25, 0.9))
	# záhony za výběhem (4 pruhy hlíny 1,2 × 5 m po terénu s řádky zeleniny)
	for b in beds:
		for s in 4:
			var bp := b + Basis(Vector3.UP, pen.yaw) * Vector3(0, 0, -1.9 + s * 1.25)
			bp.y = world.terrain.height_at(bp.x, bp.z)
			k.box(bp + Vector3(0, 0.05, 0), Vector3(1.2, 0.14, 1.25), Color(0.36, 0.26, 0.17), rot)
			for r: float in [-0.3, 0.3]:
				var rp := bp + Basis(Vector3.UP, pen.yaw) * Vector3(r, 0, 0)
				k.box(rp + Vector3(0, 0.17, 0), Vector3(0.14, 0.12, 1.05), Color(0.3, 0.55, 0.22), rot)
	# hnízda v kurníku (slaměné misky na bedně)
	for ne in nests:
		k.cylinder(ne + Vector3(0, 0.62, 0), 0.2, 0.16, 0.1, hay.darkened(0.15), Vector3.ZERO, 10)
	var mi := MeshKit.mesh_instance(self, k.commit(MeshKit.vc_material(0.9)), 350.0)
	mi.name = "Statek_vybaveni"
	# kolize stodoly (sloupy + balíky jako jeden kvádr, ať se nedá projít senem)
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(3.2, 1.4, 1.9)
	cs.shape = bs
	cs.transform = Transform3D(Basis(Vector3.UP, pen.yaw), hay_pos + Vector3(0, 0.7, 0))
	sb.add_child(cs)
	sb.set_meta("surface", "budova")
	add_child(sb)


# ------------------------------------------------------------------ napojení na práci (Jobs, Actions)

func _register_jobs() -> void:
	Jobs.set_provider("statek_koryta", func(_w: World, _id: int, _j: Dictionary) -> Array: return _up(troughs))
	Jobs.set_provider("statek_napajecky", func(_w: World, _id: int, _j: Dictionary) -> Array: return _up(drinkers))
	Jobs.set_provider("statek_stani", func(_w: World, _id: int, _j: Dictionary) -> Array: return _up(stands))
	Jobs.set_provider("statek_hnizda", func(_w: World, _id: int, _j: Dictionary) -> Array: return _up(nests))
	Jobs.set_provider("statek_hnuj", func(_w: World, _id: int, _j: Dictionary) -> Array: return _up(manure))
	Jobs.set_provider("statek_zahony", func(_w: World, _id: int, _j: Dictionary) -> Array: return _up(beds))
	Actions.set_target_check("nabrat_seno", _check_hay)
	Actions.set_target_check("nakrmit_koryto", _check_feed)
	Actions.set_handler("nabrat_seno", _on_hay)
	Actions.set_handler("nakrmit_koryto", _on_feed)
	Actions.set_handler("podojit", func(id: int, _d: Dictionary, _a: Dictionary, ok: bool) -> void:
		if ok:
			world.notify(id, "show_message", ["Nadojeno do kbelíku – mléko si hospodář odnese do chladicí vany.", 2.5]))
	Actions.set_handler("sebrat_vejce", func(id: int, _d: Dictionary, _a: Dictionary, ok: bool) -> void:
		if ok:
			world.notify(id, "show_message", ["Vejce jsou v košíku u kurníku.", 2.0]))


func _up(pts: Array) -> Array:
	var out := []
	for p in pts:
		out.append((p as Vector3) + Vector3(0, TARGET_Y, 0))
	return out


func _jobs_of(id: int) -> Jobs:
	return world.jobs.get(id) as Jobs


func _check_hay(aim: Dictionary, id: int) -> String:
	var jb := _jobs_of(id)
	if jb == null or not jb.on_shift(JOB_ID):
		return "Seno je hospodářovo – bereš si ho jen na směně."
	var p: Player = world.players.get(id)
	if p and p.item_count("seno") >= HAY_TAKE:
		return "Seno už neseš – nasyp ho do koryt."
	return Jobs.own_target(aim, id)


func _check_feed(aim: Dictionary, id: int) -> String:
	var why := Jobs.own_target(aim, id)
	if why != "":
		return why
	var p: Player = world.players.get(id)
	if p and p.item_count("seno") <= 0:
		return "Nejdřív naber seno z hromady ve stodole."
	return ""


func _on_hay(id: int, _def: Dictionary, _aim: Dictionary, ok: bool) -> void:
	var jb := _jobs_of(id)
	if not ok or jb == null:
		return
	jb.lend("seno", HAY_TAKE)
	world.notify(id, "show_message", ["Nabral jsi %d otepi sena – nasyp je do koryt." % HAY_TAKE, 2.5])


func _on_feed(id: int, _def: Dictionary, aim: Dictionary, ok: bool) -> void:
	var p: Player = world.players.get(id)
	var jb := _jobs_of(id)
	if not ok or p == null:
		return
	if p.remove_item("seno", 1) and jb:
		jb.unlend("seno", 1)
	# nakrmí zvířata přístřešku u toho koryta (jen vzhled a stav – statek péči nepočítá)
	var pos: Vector3 = aim.get("pos", Vector3.INF)
	var kinds := ["kurnik", "chlivek", "pristresek"]
	var best := ""
	var bd := INF
	for i in mini(troughs.size(), kinds.size()):
		var d := troughs[i].distance_to(pos)
		if d < bd:
			bd = d
			best = kinds[i]
	for a in _group(best):
		(a as FarmAnimal).hunger = 1.0
	world.play_sfx(id, "eat", 0.7, -6.0)


# ------------------------------------------------------------------ chod statku

func _process(delta: float) -> void:
	if world == null or pen == null or not pen.ok:
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = TICK_S
	var milking := false
	var near := false
	for id in world.players:
		var jb := _jobs_of(int(id))
		if jb and jb.task_id() == "statek_dojeni":
			milking = true
		if world.player_pos(int(id)).distance_to(pen.center) < ACTIVE_R:
			near = true
	var ci := 0
	for a in animals:
		var fa: FarmAnimal = a
		fa.set_process(near)
		if fa.species == "krava":
			fa.hold(stands[ci] if milking and ci < stands.size() else Vector3.INF)
			ci += 1


## Statek se neukládá (stádo a vybavení vzniknou při každém startu stejně); přebíjí `Farm.to_dict` / `restore`.
func to_dict() -> Dictionary:
	return {}


func restore(_d: Dictionary) -> void:
	pass
