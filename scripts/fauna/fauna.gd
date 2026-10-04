## Fauna katastru: mapa stanovišť a rozmístění zvířat (v multiplayeru poběží na serveru).
##
## Mapa stanovišť (mřížka 32 m) vzniká z dat mapy: hustota stromů (trees.bin) → les, okraj lesa;
## střechy budov (roofs.bin) → zástavba, silnice (graf OSM). Zvířata si podle ní vybírají, kam jít
## (score): srnci les a okraje, divočáci les, zajíci pole, všichni se vyhýbají vesnici.
##
## Počty a rozmístění upravuje tabulka POPULATION. Zvířata jsou ve světě pořád, jen daleko od hráčů
## se hýbou zjednodušeně (viz Animal / Bird). Aby je hráč vůbec potkal (katastr je velký a zvěř se
## vesnici vyhýbá), _encounter_scan každých pár sekund hlídá, jestli je hráč ve vhodném stanovišti
## (les, okraj lesa, pole, louka, zahrada) a v dohledu nemá žádnou zvěř – pak mu 120–300 m od něj
## vygeneruje skupinu (Herd.transient), která po jeho odchodu zase zmizí. Ve vesnici (žádné vhodné
## stanoviště) ji vygeneruje na nejbližším vhodném místě v okolí 90–250 m, ať ji jde vidět z okraje
## vesnice. Nová skupina se nikdy neobjeví hráči před očima (do 120 m mimo zorný kužel). Občas přiletí
## i hejno ptáků (i do vesnice: kos, vlaštovka, vrána). Ptákům Fauna dodává bidýlka (perch_spots:
## koruny stromů, střechy a předměty nalezené paprskem, ridge_row: řada na hřebeni střechy).
##
## Multiplayer (příprava, bez sítě): server (`authority = true`, výchozí) simuluje vše a umí vyrobit snímek
## (`snapshot` / `snapshot_for` / `flock_snapshot`, kompaktní celočíselné záznamy; `pack_snapshot` je zploští
## do PackedInt32Array). Klient (`authority = false`, `setup_client`) nesimuluje: `apply_snapshot` mu vyrábí
## a řídí „loutky“ (Animal bez AI), `apply_flock_snapshot` hejna ptáků. Popis napojení: ZVIRATA.md.
class_name Fauna
extends Node3D

const CELL := 32.0

## druh → [počet skupin, min. rozestup skupin (m)] ; velikost skupiny je v AnimalSpecs.group
const POPULATION := {
	"srnec": [13, 260.0],
	"divocak": [5, 500.0],
	"zajic": [18, 150.0],
}
const APIARIES := 7                 # včelnice (u zahrad a na lesních loukách)
const ANTHILLS := 45                # mraveniště v lesích
const CROW_FLOCKS := 4
const BLACKBIRDS := 16
const SWALLOW_FLOCKS := 4
const BUZZARDS := 3

# procedurální setkání u hráče (les / okraj / pole / louka / zahrada)
const ENCOUNTER_T := 3.0          # jak často se skenuje okolí hráčů (s)
const ENCOUNTER_R := 220.0        # v tomto okruhu už je zvěř → novou negenerovat
const ENCOUNTER_NEAR := 2         # tolik živých (neprchajících) kusů v okruhu stačí
const SPAWN_MIN := 70.0           # nová skupina nejméně tak daleko od hráče (m)
const SPAWN_MAX := 170.0
const HABITAT_MIN := 0.2          # nejmenší score stanoviště, kde se ještě generuje
const NEAR_RING := [90.0, 250.0]  # ve vesnici: kde se hledá nejbližší vhodné stanoviště (m)
const VIEW_HALF_ANGLE := 40.0     # zorný kužel hráče (± °), v něm se blízko nespawnuje
const VIEW_CLEAR := 120.0         # do této vzdálenosti se nespawnuje před očima hráče (m)
const BIRD_CHANCE := 0.5          # pravděpodobnost hejna při jednom skenu
const TRANSIENT_MAX := 10         # strop skupin vygenerovaných kvůli hráčům
const TRANSIENT_GONE := 750.0     # dál od všech hráčů → skupina/hejno zmizí
## kde hráč stojí → [[druh, váha], …] (druh se ještě snaží sednout svému stanovišti)
const ENCOUNTER_SPECIES := {
	"forest": [["divocak", 0.55], ["srnec", 0.45]],
	"edge": [["srnec", 0.7], ["divocak", 0.15], ["zajic", 0.15]],
	"field": [["zajic", 0.6], ["srnec", 0.4]],
	"meadow": [["srnec", 0.5], ["zajic", 0.5]],
	"garden": [["zajic", 1.0]],
}
## kde hráč stojí → jaké hejno může přiletět; druh → stanoviště pro výběr místa
const ENCOUNTER_BIRDS := {
	"field": ["vrana", "vlastovka"],
	"meadow": ["vrana", "vlastovka"],
	"edge": ["kane"],
	"garden": ["kos"],
	"village": ["kos", "vlastovka", "vrana"],
	"forest": [],
}
const FLOCK_HAB := {"vrana": "field", "kos": "garden", "vlastovka": "meadow", "kane": "edge"}

## Druhy ve snímku zvěře / hejn (index v poli = číslo ve snímku; nové druhy jen na konec).
const SPECIES_IDS := ["srnec", "divocak", "sele", "zajic"]
const FLOCK_SPECIES := ["vrana", "kos", "vlastovka", "kane"]
const INTEREST_R := 400.0         # oblast zájmu hráče pro snímek zvěře (m)
const FLOCK_INTEREST_R := 500.0   # …a hejn ptáků (ta se simulují do 450 m)
const PUPPET_GONE := 3.0          # loutka, která ze snímků chybí déle než tolik s, se uvolní
const REC_LEN := 9                # počet čísel v záznamu zvířete (viz Animal.net_record)

## true = tady se simuluje (singleplayer, server); false = klient v MP (jen loutky ze snímků)
var authority := true
var puppets := {}                    # klient: net_id → Animal (loutka)
var flock_puppets := {}              # klient: net_id → BirdFlock (loutka)
var _puppet_seen := {}               # klient: net_id → čas posledního snímku (s)
var _flock_seen := {}
var _puppet_gc_t := 0.0
var _next_net_id := 1

var world: World
var terrain: Terrain
var clock: Clock
var weather: Weather
var rng := RandomNumberGenerator.new()

var nx := 0
var nz := 0
var gx0 := 0.0
var gz0 := 0.0
var forest := PackedFloat32Array()   # 0..1 les
var forest_wide := PackedFloat32Array()  # les v okolí ~100 m (okraje)
var settle := PackedFloat32Array()   # 0..1 zástavba v okolí
var road := PackedFloat32Array()     # 0..1 silnice v buňce
var trees := PackedFloat32Array()    # x, y, z, výška – po čtveřicích
var tree_cells := {}                 # Vector2i(128 m) → PackedInt32Array indexů stromů

var animals: Array = []
var herds: Array = []
var horses := {}                     # id hráče → Horse
var root_animals: Node3D
var root_birds: Node3D
var root_insects: Node3D
var _transient: Array = []           # Herd-y vygenerované kvůli hráči
var _transient_flocks: Array = []    # BirdFlock-y vygenerované kvůli hráči
var _scan_t := 3.0                   # první sken až po startu (hráč se zrovna objevuje)
var _seed_i := 3000


func setup(w: World) -> void:
	world = w
	terrain = w.terrain
	clock = w.clock
	weather = w.weather
	rng.seed = 2026
	_build_habitat()
	root_animals = _root("Zver")
	root_birds = _root("Ptaci")
	root_insects = _root("Hmyz")
	_spawn_animals()
	_spawn_insects()
	_spawn_birds()


func _root(n: String) -> Node3D:
	var r := Node3D.new()
	r.name = n
	add_child(r)
	return r


# ------------------------------------------------------------------ síť: snímky a loutky

## Další stabilní síťové číslo (zvířata a hejna; kůň má číslo hráče, viz Horse).
func _new_net_id() -> int:
	var id := _next_net_id
	_next_net_id += 1
	return id


## Klientský režim: bez mapy stanovišť a bez vlastní zvěře, jen kořeny pro loutky. Svět (terén, hodiny,
## počasí) musí mít klient načtený. Volá se místo `setup` (a před přidáním do stromu se nic nespouští).
func setup_client(w: World) -> void:
	authority = false
	world = w
	terrain = w.terrain
	clock = w.clock
	weather = w.weather
	root_animals = _root("Zver")
	root_birds = _root("Ptaci")
	root_insects = _root("Hmyz")


## Snímek zvěře v okruhu `radius` od bodu `center`: [Animal.net_record(), …] (mrtvá zvířata také).
## Server ho posílá ~10× za s (unreliable); každý hráč dostane snímek kolem sebe (`snapshot_for`).
func snapshot(center: Vector3, radius := INTEREST_R) -> Array:
	var out := []
	var r2 := radius * radius
	for a in animals:
		if not is_instance_valid(a) or a.net_id == 0:
			continue
		var d: Vector3 = a.global_position - center
		if d.x * d.x + d.z * d.z <= r2:
			out.append(a.net_record())
	return out


## Snímek zvěře pro hráče `p` (oblast zájmu kolem něj). Každý hráč má svůj, průnik oblastí se posílá dvakrát.
func snapshot_for(p: Player, radius := INTEREST_R) -> Array:
	return snapshot(p.global_position, radius)


## Záznamy zploštěné do jednoho pole celých čísel (REC_LEN čísel na zvíře) – pro RPC nejmenší.
static func pack_snapshot(arr: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(arr.size() * REC_LEN)
	var i := 0
	for rec in arr:
		var r: Array = rec
		for k in REC_LEN:
			out[i] = int(r[k])
			i += 1
	return out


static func unpack_snapshot(packed: PackedInt32Array) -> Array:
	var out := []
	for i in range(0, packed.size() - REC_LEN + 1, REC_LEN):
		out.append(Array(packed.slice(i, i + REC_LEN)))
	return out


## Klient: převezme snímek zvěře (čas příjmu `now_s` v s – např. Time.get_ticks_msec() / 1000.0).
## Neznámé net_id → nová loutka, známé → nový cíl interpolace. Kdo ze snímků vypadne, po PUPPET_GONE s zmizí.
func apply_snapshot(arr: Array, now_s: float) -> void:
	for rec in arr:
		var r: Array = rec
		var id: int = r[0]
		var a: Animal = puppets.get(id)
		if a == null or not is_instance_valid(a):
			a = _spawn_puppet(r)
			puppets[id] = a
		a.puppet_push(now_s, _rec_pos(r), float(r[5]) / 1024.0 * TAU, float(r[6]) * 0.1, int(r[7]), int(r[8]))
		_puppet_seen[id] = now_s


func _rec_pos(r: Array) -> Vector3:
	return Vector3(float(r[2]) * 0.1, float(r[3]) * 0.1, float(r[4]) * 0.1)


## Loutka zvířete podle záznamu: stejný model a rig jako skutečné zvíře, ale bez AI a bez kolizí.
func _spawn_puppet(r: Array) -> Animal:
	var id: String = SPECIES_IDS[clampi(int(r[1]), 0, SPECIES_IDS.size() - 1)]
	var flags := int(r[8])
	var nid := int(r[0])
	var a := Animal.new()
	a.authority = false
	a.net_id = nid
	var variant := {"male": (flags & Animal.FLAG_MALE) != 0, "winter": (flags & Animal.FLAG_WINTER) != 0,
		"tint": 0.88 + float(nid % 23) * 0.01}
	a.setup(self, id, _rec_pos(r), null, variant, nid)
	a.name = "%s_p%d" % [id, nid]
	root_animals.add_child(a)
	return a


## Snímek hejn ptáků v okruhu: [BirdFlock.flock_state(), …]. Stačí při změně a jednou za ~1 s (reliable).
func flock_snapshot(center: Vector3, radius := FLOCK_INTEREST_R) -> Array:
	var out := []
	for fl in root_birds.get_children():
		if fl is BirdFlock and fl.net_id != 0 and fl.spot.distance_to(center) <= radius:
			out.append(fl.flock_state())
	return out


## Klient: převezme stav hejn (nové net_id → hejno se vyrobí deterministicky ze seedu a přepne do stavu serveru).
func apply_flock_snapshot(arr: Array, now_s: float) -> void:
	for rec in arr:
		var s: Array = rec
		var id: int = s[0]
		var fl: BirdFlock = flock_puppets.get(id)
		if fl == null or not is_instance_valid(fl):
			fl = BirdFlock.new()
			fl.authority = false
			fl.net_id = id
			var hx := float(s[8]) * 0.1
			var hz := float(s[9]) * 0.1
			var hy: float = terrain.height_at(hx, hz)
			fl.setup(self, FLOCK_SPECIES[clampi(int(s[1]), 0, FLOCK_SPECIES.size() - 1)], Vector3(hx, hy, hz), int(s[2]))
			root_birds.add_child(fl)
			flock_puppets[id] = fl
		fl.apply_flock_state(s)
		_flock_seen[id] = now_s


## Klient: uklidí loutky, které ze snímků chybí déle než PUPPET_GONE s (kontrola 1× za s).
func _puppet_gc(delta: float) -> void:
	_puppet_gc_t -= delta
	if _puppet_gc_t > 0.0:
		return
	_puppet_gc_t = 1.0
	var now := Time.get_ticks_msec() / 1000.0
	for id in _puppet_seen.keys():
		if now - float(_puppet_seen[id]) > PUPPET_GONE:
			var a: Animal = puppets.get(id)
			if a != null and is_instance_valid(a):
				a.queue_free()
			puppets.erase(id)
			_puppet_seen.erase(id)
	for id in _flock_seen.keys():
		if now - float(_flock_seen[id]) > PUPPET_GONE * 10.0:      # hejna se posílají jen při změně → delší lhůta
			var fl: BirdFlock = flock_puppets.get(id)
			if fl != null and is_instance_valid(fl):
				fl.queue_free()
			flock_puppets.erase(id)
			_flock_seen.erase(id)


# ------------------------------------------------------------------ mapa stanovišť

func _build_habitat() -> void:
	gx0 = terrain.x0
	gz0 = terrain.z0
	nx = int(ceil((terrain.w - 1) * terrain.spacing / CELL))
	nz = int(ceil((terrain.h - 1) * terrain.spacing / CELL))
	var count := PackedFloat32Array()
	count.resize(nx * nz)
	# stromy
	var tb := FileAccess.get_file_as_bytes("res://data/trees.bin")
	var n := tb.decode_s32(4)
	var d := tb.slice(8).to_float32_array()
	trees.resize(n * 4)
	for i in n:
		var k := i * 11
		var x := d[k]
		var z := d[k + 2]
		trees[i * 4] = x
		trees[i * 4 + 1] = d[k + 1]
		trees[i * 4 + 2] = z
		trees[i * 4 + 3] = d[k + 5]
		var c := _cell(x, z)
		if c >= 0:
			count[c] += 1.0
		var tk := Vector2i(floori(x / 128.0), floori(z / 128.0))
		if not tree_cells.has(tk):
			tree_cells[tk] = PackedInt32Array()
		tree_cells[tk].append(i)
	# budovy (vrcholy střech)
	var bcount := PackedFloat32Array()
	bcount.resize(nx * nz)
	var rb := FileAccess.get_file_as_bytes("res://data/roofs.bin")
	var nch := rb.decode_s32(4)
	var off := 8
	for _c in nch:
		var nv := rb.decode_s32(off)
		off += 4
		var pos := rb.slice(off, off + nv * 12).to_float32_array()
		off += nv * 36
		for i in range(0, nv, 3):
			var c := _cell(pos[i * 3], pos[i * 3 + 2])
			if c >= 0:
				bcount[c] += 1.0
	# silnice (osy z grafu; lesní a polní cesty se nepočítají)
	road.resize(nx * nz)
	var g: RoadGraph = world.graph
	for i in g.nodes.size():
		for j in g.adj[i]:
			if j < i or not (g.edge(i, j) in RoadGraph.CAR_KINDS):
				continue
			var a: Vector2 = g.nodes[i]
			var b: Vector2 = g.nodes[j]
			var steps := int(a.distance_to(b) / (CELL * 0.5)) + 1
			for s in steps + 1:
				var p := a.lerp(b, float(s) / steps)
				var c := _cell(p.x, p.y)
				if c >= 0:
					road[c] = 1.0
	forest = _blur(count, 1)
	for i in forest.size():
		forest[i] = smoothstep(1.2, 4.5, forest[i])
	forest_wide = _blur(forest, 2)
	settle = _blur(bcount, 3)
	for i in settle.size():
		settle[i] = clampf(settle[i] * 0.6, 0.0, 1.0)


func _cell(x: float, z: float) -> int:
	var ix := int((x - gx0) / CELL)
	var iz := int((z - gz0) / CELL)
	if ix < 0 or iz < 0 or ix >= nx or iz >= nz:
		return -1
	return iz * nx + ix


## Průměr v okně (2r+1)² buněk.
func _blur(src: PackedFloat32Array, r: int) -> PackedFloat32Array:
	var tmp := PackedFloat32Array()
	tmp.resize(nx * nz)
	var out := PackedFloat32Array()
	out.resize(nx * nz)
	for iz in nz:
		for ix in nx:
			var s := 0.0
			for dx in range(-r, r + 1):
				var x := clampi(ix + dx, 0, nx - 1)
				s += src[iz * nx + x]
			tmp[iz * nx + ix] = s / (2 * r + 1)
	for iz in nz:
		for ix in nx:
			var s := 0.0
			for dz in range(-r, r + 1):
				var z := clampi(iz + dz, 0, nz - 1)
				s += tmp[z * nx + ix]
			out[iz * nx + ix] = s / (2 * r + 1)
	return out


func _sample(arr: PackedFloat32Array, x: float, z: float) -> float:
	var fx := clampf((x - gx0) / CELL - 0.5, 0.0, nx - 1.001)
	var fz := clampf((z - gz0) / CELL - 0.5, 0.0, nz - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * nx + ix
	var i1 := mini(ix + 1, nx - 1) - ix
	var j1 := nx if iz + 1 < nz else 0
	return lerpf(lerpf(arr[i], arr[i + i1], tx), lerpf(arr[i + j1], arr[i + j1 + i1], tx), tz)


func forest_at(x: float, z: float) -> float:
	return _sample(forest, x, z)


func settle_at(x: float, z: float) -> float:
	return _sample(settle, x, z)


## Jak vhodné je místo pro stanoviště (0 nevhodné … 1 ideální): forest, edge, field, garden, meadow.
func score(hab: String, x: float, z: float) -> float:
	if not terrain.contains(x, z, 60.0):
		return -1.0
	var f := _sample(forest, x, z)
	var fw := _sample(forest_wide, x, z)
	var st := _sample(settle, x, z)
	var rd := _sample(road, x, z)
	match hab:
		"forest":
			return f - st * 2.0 - rd * 0.3
		"edge":
			return clampf(fw * 2.2, 0.0, 1.0) * (1.0 - f * 0.55) - st * 2.0 - rd * 0.4
		"field":
			return (1.0 - f) * (1.0 - fw * 0.4) - st * 2.2 - rd * 0.6
		"garden":            # okraj zástavby (zahrady, sady)
			return clampf(st * 3.0, 0.0, 1.0) * (1.0 - clampf(st * 1.5 - 0.6, 0.0, 1.0)) * (1.0 - f * 0.5)
		"meadow":            # louka u lesa (včely, kosi)
			return clampf(fw * 2.5, 0.0, 1.0) * (1.0 - f) - st * 1.5
	return 0.0


## Nejvhodnější z několika náhodných bodů v kruhu (pro cíle přesunů a útěku).
func random_point(center: Vector3, radius: float, hab: String, r: RandomNumberGenerator, tries := 10) -> Vector3:
	var best := center
	var bs := -INF
	for i in tries:
		var a := r.randf() * TAU
		var d := sqrt(r.randf()) * radius
		var p := center + Vector3(cos(a) * d, 0, sin(a) * d)
		var s := score(hab, p.x, p.z) + r.randf() * 0.15
		if s > bs:
			bs = s
			best = p
	best.y = terrain.height_at(best.x, best.z)
	return best


## Stromy v okruhu – [Vector4(x, y, z, výška)] (bidýlka ptáků, stezky mravenců).
func trees_near(p: Vector3, r: float, max_n := 40) -> Array:
	var out := []
	var tm: TreeManager = world.trees if world != null else null   # pokácené stromy (M2.1) se vynechají
	var c0 := Vector2i(floori((p.x - r) / 128.0), floori((p.z - r) / 128.0))
	var c1 := Vector2i(floori((p.x + r) / 128.0), floori((p.z + r) / 128.0))
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			var arr: PackedInt32Array = tree_cells.get(Vector2i(cx, cz), PackedInt32Array())
			for i in arr:
				var dx := trees[i * 4] - p.x
				var dz := trees[i * 4 + 2] - p.z
				if dx * dx + dz * dz < r * r:
					if tm != null and tm.is_felled(i):
						continue
					out.append(Vector4(trees[i * 4], trees[i * 4 + 1], trees[i * 4 + 2], trees[i * 4 + 3]))
					if out.size() >= max_n:
						return out
	return out


# ------------------------------------------------------------------ bidýlka ptáků

const PERCH_RAYS := 24            # nejvýš tolik paprsků na jedno volání perch_spots
const PERCH_NORMAL_Y := 0.45      # nejmenší normála.y plochy, na kterou pták sedne (ne svislá zeď)
const RIDGE_STEP := 1.5           # vzdálenost pomocných paprsků kolem zásahu (hřeben střechy)
const PERCH_MASK := 1 | 8         # statika (terén, budovy) + rekvizity, auta ne

var _rays_left := 0


## Paprsek shora dolů v bodě (x, z); prázdný slovník = nic netrefil / vyčerpán limit paprsků.
func _perch_ray(x: float, z: float) -> Dictionary:
	if _rays_left <= 0:
		return {}
	_rays_left -= 1
	var gy := terrain.height_at(x, z)
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, gy + 40.0, z), Vector3(x, gy - 1.0, z), PERCH_MASK)
	return get_world_3d().direct_space_state.intersect_ray(q)


## Střecha / předmět v bodě (x, z): nejvyšší z pěti zásahů (střed + 4× ±RIDGE_STEP) = hřeben.
## Vrací Vector3.INF, když tam holá zem (výš než `min_h` nad terénem není nic) nebo příliš strmá plocha.
func _roof_spot(x: float, z: float, min_h: float) -> Vector3:
	var hit := _perch_ray(x, z)
	if hit.is_empty():
		return Vector3.INF
	var pos: Vector3 = hit["position"]
	var nrm: Vector3 = hit["normal"]
	if pos.y <= terrain.height_at(x, z) + min_h or nrm.y < PERCH_NORMAL_Y:
		return Vector3.INF
	var best := pos
	for k in 4:
		var a := k * PI * 0.5
		var h2 := _perch_ray(pos.x + cos(a) * RIDGE_STEP, pos.z + sin(a) * RIDGE_STEP)
		if h2.is_empty():
			continue
		var p2: Vector3 = h2["position"]
		var n2: Vector3 = h2["normal"]
		if p2.y > best.y and n2.y >= PERCH_NORMAL_Y:
			best = p2
	return best


## Náhodný bod v kruhu, který je nejspíš v zástavbě (mřížka zástavby je levná, paprsky drahé).
func _roof_candidate(center: Vector3, radius: float) -> Vector2:
	var best := Vector2(center.x, center.z)
	var bs := -1.0
	for i in 5:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * radius
		var x := center.x + cos(a) * d
		var z := center.z + sin(a) * d
		var s := settle_at(x, z) + rng.randf() * 0.05
		if s > bs:
			bs = s
			best = Vector2(x, z)
	return best


## Bidýlka pro ptáky v kruhu: až `n` × Vector4(x, y, z, kind), kind 0 = koruna stromu, 1 = střecha / předmět.
## `roof_share` = podíl střech a předmětů (0 = jen stromy), `tree_min` = nejnižší strom (m), `min_h` = o kolik
## musí být zásah nad terénem. Střechy se hledají paprsky (max PERCH_RAYS), volat jen z _physics_process.
func perch_spots(center: Vector3, radius: float, n: int, min_h := 1.0, roof_share := 0.5, tree_min := 6.0) -> Array:
	var out := []
	_rays_left = PERCH_RAYS
	var want_roofs := roundi(n * roof_share)
	var tries := 0
	while out.size() < want_roofs and _rays_left >= 5 and tries < 14:
		tries += 1
		var c := _roof_candidate(center, radius)
		var r := _roof_spot(c.x, c.y, min_h)
		if r != Vector3.INF:
			out.append(Vector4(r.x, r.y, r.z, 1.0))
	# stromy: vršek koruny
	if out.size() < n:
		var ok := []
		for t in trees_near(center, radius, 60):
			if t.w >= tree_min and t.w <= 40.0:
				ok.append(t)
		while out.size() < n and not ok.is_empty():
			var tt: Vector4 = ok.pop_at(rng.randi() % ok.size())
			out.append(Vector4(tt.x, tt.y + tt.w * rng.randf_range(0.8, 0.97), tt.z, 0.0))
	# málo stromů → ještě zkus střechy
	while out.size() < n and roof_share > 0.0 and _rays_left >= 5 and tries < 20:
		tries += 1
		var c2 := _roof_candidate(center, radius)
		var r2 := _roof_spot(c2.x, c2.y, min_h)
		if r2 != Vector3.INF:
			out.append(Vector4(r2.x, r2.y, r2.z, 1.0))
	return out


## Řada `n` bidýlek 0,15–0,25 m od sebe podél hřebene střechy (vlaštovky). Prázdné, když se hřeben nenašel.
## Hřeben = směr, kterým je výška zásahu ±RIDGE_STEP od bodu nejvyrovnanější.
func ridge_row(center: Vector3, radius: float, n: int) -> Array:
	_rays_left = PERCH_RAYS * 2
	for attempt in 6:
		var c := _roof_candidate(center, radius)
		var r := _roof_spot(c.x, c.y, 2.0)
		if r == Vector3.INF:
			continue
		var best_dir := Vector2.ZERO
		var best_dev := 0.25
		for k in 4:
			var a := k * PI * 0.25
			var dir := Vector2(cos(a), sin(a))
			var dev := 0.0
			var okr := true
			for sgn in [-1.0, 1.0]:
				var h := _perch_ray(r.x + dir.x * RIDGE_STEP * sgn, r.z + dir.y * RIDGE_STEP * sgn)
				if h.is_empty():
					okr = false
					break
				var hp: Vector3 = h["position"]
				dev = maxf(dev, absf(hp.y - r.y))
			if okr and dev < best_dev:
				best_dev = dev
				best_dir = dir
		if best_dir == Vector2.ZERO:
			continue
		var step := rng.randf_range(0.15, 0.25)
		var row := []
		for i in n:
			var o := (i - (n - 1) * 0.5) * step
			row.append(Vector4(r.x + best_dir.x * o, r.y, r.z + best_dir.y * o, 1.0))
		return row
	return []


## Náhodná místa vhodná pro stanoviště, navzájem aspoň `spacing` od sebe.
func _sites(hab: String, n: int, spacing: float, min_score := 0.45, near: Vector3 = Vector3.INF, near_r := 0.0) -> Array:
	var out: Array = []
	var guard := 0
	while out.size() < n and guard < n * 400:
		guard += 1
		var x := gx0 + rng.randf() * nx * CELL
		var z := gz0 + rng.randf() * nz * CELL
		if near != Vector3.INF and guard < n * 200:
			var a := rng.randf() * TAU
			var d := sqrt(rng.randf()) * near_r
			x = near.x + cos(a) * d
			z = near.z + sin(a) * d
		if score(hab, x, z) < min_score:
			continue
		var ok := true
		for o in out:
			if Vector2(o.x, o.z).distance_to(Vector2(x, z)) < spacing:
				ok = false
				break
		if ok:
			out.append(Vector3(x, terrain.height_at(x, z), z))
	return out


# ------------------------------------------------------------------ zvěř

func _spawn_animals() -> void:
	var sp: Dictionary = world.meta["spawn"]
	var home := Vector3(float(sp["x"]), 0, float(sp["z"]))
	for id in POPULATION:
		var spec := AnimalSpecs.get_spec(id)
		var hab: String = spec["habitat"]
		# první skupina každého druhu kousek od domu hráče, ať je hráč může potkat
		var sites := _sites(hab, 1, 0.0, 0.5, home, 900.0)
		sites.append_array(_sites(hab, int(POPULATION[id][0]) - sites.size(), POPULATION[id][1]))
		for site in sites:
			_make_herd(id, site)


## Vytvoří skupinu druhu `id` na místě `site` (skladba podle ročního období, selata, samci).
func _make_herd(id: String, site: Vector3) -> Herd:
	var spec := AnimalSpecs.get_spec(id)
	var month := clock.month()
	var winter := month >= 11 or month <= 3
	var piglets := month >= 3 and month <= 8
	var herd := Herd.new()
	herd.home = site
	var gs: Array = spec["group"]
	var size := rng.randi_range(gs[0], gs[1])
	if id == "srnec" and winter:
		size += rng.randi_range(1, 4)               # v zimě se srnci sdružují do tlup
	var members := []
	for i in size:
		var mid: String = id
		var male := false
		if id == "srnec":
			male = i == 1 or (size == 1 and rng.randf() < 0.5)
		elif id == "divocak":
			male = size <= 2 and rng.randf() < 0.6    # samotář = kňour
		members.append([mid, male])
	if id == "divocak" and piglets and size >= 3:
		herd.has_young = true
		for k in rng.randi_range(3, 6):
			members.append(["sele", false])
	for i in members.size():
		var a := Animal.new()
		var off := Vector3(rng.randf_range(-4, 4), 0, rng.randf_range(-4, 4))
		var p: Vector3 = site + off
		p.y = terrain.height_at(p.x, p.z)
		var variant := {"male": members[i][1], "winter": winter, "tint": rng.randf_range(0.88, 1.1)}
		a.setup(self, members[i][0], p, herd, variant, _seed_i)
		_seed_i += 1
		a.slot_i = i
		a.net_id = _new_net_id()
		a.name = "%s_%d" % [members[i][0], _seed_i]
		herd.add(a)
		root_animals.add_child(a)
		animals.append(a)
	herds.append(herd)
	return herd


# ------------------------------------------------------- setkání zvěře u hráče

func _process(delta: float) -> void:
	if not authority:
		_puppet_gc(delta)
		return
	_scan_t -= delta
	if _scan_t > 0.0:
		return
	_scan_t = ENCOUNTER_T
	if world == null:
		return
	_despawn_far()
	if world.players.is_empty():
		return
	for p in world.players.values():
		if p.inside == "":            # hráč v interiéru (pod mapou) – zvěř kolem něj se negeneruje
			_encounter_for(p)


## Kde hráč stojí → nejvhodnější stanoviště ("" = vesnice / nevhodné, nic negenerovat).
func _habitat_at(pos: Vector3) -> String:
	var best := ""
	var bs := HABITAT_MIN
	for hab in ENCOUNTER_SPECIES:
		var s := score(hab, pos.x, pos.z)
		if s > bs:
			bs = s
			best = hab
	return best


## Nejvhodnější stanoviště v prstenci NEAR_RING kolem `pos` (12 bodů po kruhu) → [stanoviště, bod]
## nebo [] (pro hráče ve vesnici: zvěř se ukáže na okraji vesnice).
func _habitat_near(pos: Vector3) -> Array:
	var best := []
	var bs := HABITAT_MIN
	var a0 := rng.randf() * TAU
	for k in 12:
		var a := a0 + k * TAU / 12.0
		var d := rng.randf_range(NEAR_RING[0], NEAR_RING[1])
		var x := pos.x + cos(a) * d
		var z := pos.z + sin(a) * d
		for hab in ENCOUNTER_SPECIES:
			var s := score(hab, x, z)
			if s > bs:
				bs = s
				best = [hab, Vector3(x, terrain.height_at(x, z), z)]
	return best


## Míří hráč (směr pohledu) na bod `pt`? Směr pohledu = -Z otočené o player.yaw (jako pohyb vpřed).
func _in_view(p: Player, pt: Vector3) -> bool:
	var to := Vector3(pt.x - p.global_position.x, 0.0, pt.z - p.global_position.z)
	if to.length() < 0.1:
		return true
	var fwd := Vector3(-sin(p.yaw), 0.0, -cos(p.yaw))
	return fwd.dot(to.normalized()) > cos(deg_to_rad(VIEW_HALF_ANGLE))


## Hráč je ve stanovišti (nebo aspoň poblíž) a v dohledu nemá zvěř → vygeneruj mu skupinu / občas hejno.
func _encounter_for(p: Player) -> void:
	var pos: Vector3 = p.global_position
	var hab := _habitat_at(pos)
	var anchor := Vector3.INF          # ve vesnici: kde je nejbližší vhodné stanoviště
	var village := false
	if hab == "":
		village = settle_at(pos.x, pos.z) > 0.3
		var hn := _habitat_near(pos)
		if not hn.is_empty():
			hab = hn[0]
			anchor = hn[1]
	# zvěř
	if hab != "" and _transient.size() < TRANSIENT_MAX:
		var near := 0
		for a in animals:
			if is_instance_valid(a) and not a.dead and a.state != "flee" \
					and a.global_position.distance_squared_to(pos) < ENCOUNTER_R * ENCOUNTER_R:
				near += 1
		if near < ENCOUNTER_NEAR:
			_spawn_encounter(_pick_species(hab), pos, p, anchor, hab)
	# ptáci (stačí jedno hejno v okolí)
	var key := "village" if village else hab
	var fopts: Array = ENCOUNTER_BIRDS.get(key, [])
	if not fopts.is_empty() and rng.randf() < BIRD_CHANCE:
		for fl in root_birds.get_children():
			if fl.spot.distance_to(pos) < 500.0:
				return
		_spawn_flock(fopts, pos, p, village, false)


## Druh zvěře podle vah ve stanovišti `hab`.
func _pick_species(hab: String) -> String:
	var options: Array = ENCOUNTER_SPECIES[hab]
	var roll := rng.randf()
	for o in options:
		roll -= float(o[1])
		if roll <= 0.0:
			return o[0]
	return options[0][0]


## Nové hejno ptáků z nabídky `fopts` kolem hráče (`force` = bez ohledu na skóre stanoviště). Vrací druh nebo "".
func _spawn_flock(fopts: Array, pos: Vector3, p: Player, village: bool, force: bool) -> String:
	var fid: String = fopts[rng.randi() % fopts.size()]
	if fid == "vlastovka" and not Seasons.swallows_present(clock.day_of_year()):
		fid = "vrana"
	var dmin := 40.0 if (village or force) else 80.0
	var dmax := 120.0 if force else (150.0 if village else 250.0)
	var site := _encounter_site(pos, FLOCK_HAB[fid], dmin, dmax, p)
	if site == Vector3.INF and (village or force):
		site = _encounter_site(pos, FLOCK_HAB[fid], dmin, dmax, p, -2.0)
	if site == Vector3.INF:
		return ""
	var fl := BirdFlock.new()
	fl.setup(self, fid, site, rng.randi())
	fl.net_id = _new_net_id()
	root_birds.add_child(fl)
	_transient_flocks.append(fl)
	return fid


## Místo pro novou skupinu `dist_min..dist_max` od hráče, ve stanovišti `hab` (INF = nenašlo se).
## Blíž než VIEW_CLEAR m se nesmí objevit v zorném kuželu hráče `p` (pop-in před očima).
func _encounter_site(pos: Vector3, hab: String, dist_min: float, dist_max: float, p: Player = null, min_score := 0.35) -> Vector3:
	for i in 12:
		var a := rng.randf() * TAU
		var d := rng.randf_range(dist_min, dist_max)
		var c := pos + Vector3(cos(a) * d, 0, sin(a) * d)
		var pt := random_point(c, 80.0, hab, rng, 6)
		var dd := Vector2(pt.x - pos.x, pt.z - pos.z).length()
		if dd < dist_min or dd > TRANSIENT_GONE or not terrain.contains(pt.x, pt.z, 60.0):
			continue
		if score(hab, pt.x, pt.z) <= min_score:
			continue
		if p != null and dd < VIEW_CLEAR and _in_view(p, pt):
			continue
		return pt
	return Vector3.INF


## Nová skupina druhu `id` (na `anchor` v stanovišti `hab`, jinak podle druhu 70–170 m od hráče).
## `force` = vynucené setkání (menu F2): 60–110 m, bez ohledu na skóre a limity. Vrací skupinu nebo null.
func _spawn_encounter(id: String, pos: Vector3, p: Player, anchor := Vector3.INF, hab := "", force := false) -> Herd:
	var site := Vector3.INF
	if anchor != Vector3.INF:
		site = random_point(anchor, 40.0, hab, rng, 6)
		if not terrain.contains(site.x, site.z, 60.0) or (p != null and site.distance_to(pos) < VIEW_CLEAR and _in_view(p, site)):
			site = Vector3.INF
	elif force:
		var sh: String = AnimalSpecs.get_spec(id)["habitat"]
		site = _encounter_site(pos, sh, 60.0, 110.0, p, -2.0)
	else:
		var sh: String = AnimalSpecs.get_spec(id)["habitat"]
		site = _encounter_site(pos, sh, SPAWN_MIN, SPAWN_MAX, p)
	if site == Vector3.INF:
		return null
	var herd := _make_herd(id, site)
	herd.transient = true
	_transient.append(herd)
	# nová skupina hráče nezaregistruje hned (žádná předchozí pozornost) a v klidu se pase
	for m in herd.members:
		m.aware = 0.0
		m.state = "graze"
	return herd


## Vynucené setkání u hráče (menu F2): zvěř 60–110 m mimo zorný kužel. Vrací popis pro hlášku.
func spawn_encounter_near(pos: Vector3, p: Player) -> String:
	var hab := _habitat_at(pos)
	if hab == "":
		var hn := _habitat_near(pos)
		hab = hn[0] if not hn.is_empty() else "field"
	var id := _pick_species(hab)
	var h := _spawn_encounter(id, pos, p, Vector3.INF, hab, true)
	if h == null:
		return "Nepodařilo se najít místo (zkus se otočit nebo přejít jinam)."
	var leader = h.get_leader()
	var d: int = int(leader.global_position.distance_to(pos)) if leader else 0
	return "%s: %d ks, asi %d m od tebe." % [AnimalSpecs.get_spec(id)["name"], h.members.size(), d]


## Vynucené hejno ptáků 40–120 m od hráče (menu F2). Vrací popis pro hlášku.
func spawn_flock_near(pos: Vector3, p: Player) -> String:
	var village := _habitat_at(pos) == "" and settle_at(pos.x, pos.z) > 0.3
	var opts: Array = ["kos", "vlastovka", "vrana"] if village else ["vrana", "kos", "vlastovka", "kane"]
	var fid := _spawn_flock(opts, pos, p, village, true)
	if fid == "":
		return "Nepodařilo se najít místo pro hejno."
	return "Hejno: %s." % Bird.SPECIES[fid]["name"]


## Skupiny a hejna vygenerovaná kvůli hráči zase uklidí, když jsou od všech hráčů daleko.
func _despawn_far() -> void:
	for h in _transient.duplicate():
		var alive := []
		var nearest := INF
		for m in h.members:
			if is_instance_valid(m) and not m.dead:
				alive.append(m)
				nearest = minf(nearest, world.nearest_player_dist(m.global_position))
		h.members = alive
		if alive.is_empty() or nearest > TRANSIENT_GONE:
			for m in alive:
				animals.erase(m)
				m.queue_free()
			herds.erase(h)
			_transient.erase(h)
	for fl in _transient_flocks.duplicate():
		if not is_instance_valid(fl) or world.nearest_player_dist(fl.home) > TRANSIENT_GONE:
			if is_instance_valid(fl):
				fl.queue_free()
			_transient_flocks.erase(fl)


# ------------------------------------------------------------------ hmyz a ptáci

func _spawn_insects() -> void:
	var sites := _sites("garden", APIARIES - 2, 250.0, 0.35)
	sites.append_array(_sites("meadow", 2, 400.0, 0.4))
	for s in sites:
		var ap := Apiary.new()
		ap.setup(self, s, rng.randi())
		root_insects.add_child(ap)
	for s in _sites("forest", ANTHILLS, 60.0, 0.55):
		var ah := AntHill.new()
		ah.setup(self, s, rng.randi())
		root_insects.add_child(ah)


func _spawn_birds() -> void:
	var sp: Dictionary = world.meta["spawn"]
	var home := Vector3(float(sp["x"]), 0, float(sp["z"]))
	var defs := [
		["vrana", "field", CROW_FLOCKS, 500.0, 0.5],
		["kos", "garden", BLACKBIRDS, 120.0, 0.25],
		["vlastovka", "garden", SWALLOW_FLOCKS, 400.0, 0.25],
		["kane", "edge", BUZZARDS, 900.0, 0.5],
	]
	for d in defs:
		var sites := _sites(d[1], 1, 0.0, d[4], home, 500.0)
		sites.append_array(_sites(d[1], int(d[2]) - sites.size(), d[3], d[4]))
		for s in sites:
			var fl := BirdFlock.new()
			fl.setup(self, d[0], s, rng.randi())
			fl.net_id = _new_net_id()
			root_birds.add_child(fl)


# ------------------------------------------------------------------ kůň hráče

## Kůň hráče `id` u domu hráče (volné místo hledá fyzikou, až je ve světě kolize).
func spawn_horse(id: int, near: Vector3, yaw: float) -> Horse:
	var h := Horse.new()
	h.name = "Kun_%d" % id
	h.setup(self, near, yaw, id, 900 + id)
	root_animals.add_child(h)
	horses[id] = h
	return h


func horse_of(id: int) -> Horse:
	return horses.get(id)
