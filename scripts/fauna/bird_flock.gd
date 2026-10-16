## Hejno / pár / samotný pták a jeho chování podle druhu. Bidýlka (koruny stromů, střechy, předměty)
## dodává Fauna.perch_spots / ridge_row; ptáci sedají spontánně i bez vyrušení (časy v konstantách níž):
## - vrány: hejno se prochází po poli a sbírá; po 60–150 s se s 50% šancí přesune na stromy / střechy,
##   posedí 30–90 s a vrátí se; když se přiblíží člověk (~18 m) nebo auto, vzlétne na bidýlka; večer
##   táhnou nocovat do lesa, v zimě jsou hejna větší
## - kos: poskakuje po zahradě, každých 20–60 s si sedne na střechu / strom; zblízka (6 m) odletí
##   s varovným hlasem; za svítání a soumraku (březen–červenec) zpívá z nejvyššího bidýlka
## - vlaštovky: od dubna do září loví hmyz v rychlém letu nízko nad loukami a vesnicí (před deštěm
##   létají níž), po 40–90 s se v řadě usadí na hřebeni střechy na 15–40 s; v noci a mimo sezónu nejsou
## - káně: za slunečného dne krouží ve stoupavých proudech 60–120 m nad polem (občas si sedne na strom),
##   jinak sedí na vrcholu vysokého stromu
## Na bidýlku hejno přeletí jinam, když se hráč přiblíží. Když se bidýlko nenajde, platí staré chování
## (koruny stromů / země). Simulace běží, jen když je hráč do 450 m (jinak jsou ptáci schovaní a stojí).
##
## Multiplayer (příprava): o vyrušení ptáků, přesunech a bidýlkách rozhoduje jen autorita (`authority`, výchozí
## true = singleplayer / server). Server posílá `flock_state()` (net_id, druh, seed, režim, `spot`, čas v režimu,
## domov, cíl přistání) při změně režimu / `spot` a jednou za ~1 s. Klient (`authority = false`) hejno vyrobí ze
## stejného seedu a domova (`_ready` je deterministické: počet a výchozí místa ptáků), po `apply_flock_state` už
## jen létá sám podle režimu: nové bidýlko / zem ze serveru → vzlétne a přistane (`_fly_all`), lov a kroužení
## loví lokálně. Jednotlivá bidýlka ptáků na klientu jen přibližně kolem `spot` serveru.
class_name BirdFlock
extends Node3D

## časy (s): [od, do]. M8.D2d: konstanty jsou `static var` – ladí je menu pro vývojáře (F3 → Zvěř/Hejna a murmurace).
static var CROW_GROUND := [60.0, 150.0]      # jak dlouho se hejno vran prochází po poli, než zvažuje bidýlka
static var CROW_PERCH_CHANCE := 0.5          # šance, že se pak přesune na bidýlka
static var CROW_STAY := [30.0, 90.0]         # jak dlouho vrány posedí
static var BLACKBIRD_CYCLE := [20.0, 60.0]   # kos: zem ↔ bidýlko
static var SWALLOW_HUNT := [40.0, 90.0]      # vlaštovky loví
static var SWALLOW_SIT := [15.0, 40.0]       # a pak sedí na hřebeni
static var BUZZARD_REST_EVERY := 180.0       # káně za termiky: jednou za tolik s hodí kostkou…
static var BUZZARD_REST_CHANCE := 0.15       # …a s touto šancí slétne na strom
static var BUZZARD_STAY := [40.0, 120.0]
## dosah vyrušení hráčem (m) na zemi / na bidýlku (auto × CAR_SCARE_K)
static var SCARE_GROUND := {"vrana": 18.0, "kos": 6.0}
static var SCARE_PERCH := {"vrana": 12.0, "kos": 6.0, "vlastovka": 8.0, "kane": 31.0}
static var RELOCATE_AWAY := 30.0             # nové bidýlko aspoň tak daleko od hráče
## Režimy a cíle přistání jako čísla pro síť (index v poli = číslo ve stavu; nové jen na konec).
const MODES := ["ground", "fly", "perch", "hunt", "soar"]
const LANDS := ["", "ground", "perch"]
## M8.10 boidy (Reynolds 1987) pro letící hejno vran: oddělení, zarovnání, soudržnost → posun cíle ptáka
static var BOID_S := 0.2                     # s – jak často se síly hejna přepočítají
static var BOID_SEP_R := 3.0                 # m – blíž než tohle se ptáci odpuzují
static var BOID_K := [4.0, 0.6, 0.15]        # váhy: oddělení, zarovnání, soudržnost
static var BOID_MAX := 8.0                   # m – největší posun cíle
## M8.10 káně a termika: krouží v nejbližší bublině `Thermals` (tam, kde stoupá i paraglide); bez bubliny
## v dosahu krouží nad okrskem ve „slabé termice“, kterou letecký model nesimuluje (BUZZARD_WEAK_LIFT)
static var BUZZARD_THERMAL_R := 1200.0       # m – jak daleko od domova káně bublinu najde
static var BUZZARD_WEAK_LIFT := 1.2          # m/s
static var BUZZARD_CEIL := 220.0             # m nad terénem – strop kroužení (výš ji termika „nepustí“)
## --- M8.D2d: čísla dřív zapsaná přímo ve vzorcích (stejné hodnoty)
static var SIM_R := 450.0                    # m – hejno se simuluje jen do této vzdálenosti od hráče
static var CAR_SCARE_K := 1.6                # auto vyruší ptáky z dosahu × tohle
static var CROW_N := [6, 12]                 # vran v hejnu (od–do)
static var CROW_WINTER_ADD := 6              # v zimě o tolik víc
static var SWALLOW_N := [5, 11]              # vlaštovek v hejnu (od–do)
static var CROW_NIGHT_DAY := 0.2             # vrány za soumraku (denní světlo pod tolik) táhnou nocovat
static var ROOST_R := 400.0                  # m – nocoviště v lese do této vzdálenosti
static var SCATTER_R := 160.0                # m – vyplašené vrány hledají stromy v tomto okruhu
static var FIELD_R := 250.0                  # m – návrat vran na pole v okruhu od domova
static var CROW_SPREAD := 12.0               # m – vrány se po poli rozptýlí do tolika
static var CROW_WANDER_P := 0.05             # 1/s – vrána si vybere nové místo na poli
static var KOS_SPREAD := 7.0                 # m – kos po zahradě
static var KOS_WANDER_P := 0.1               # 1/s
static var KOS_GARDEN_R := 25.0              # m – kos se vrací na zahradu v tomto okruhu
static var KOS_LEAVE_R := 14.0               # m – kos neslétne z bidýlka, je-li hráč blíž
static var SING_MORNING_H := 7.5             # h – kos zpívá za svítání do …
static var SING_EVENING_H := 19.0            # h – … a večer od
static var SING_P := 0.12                    # 1/s – šance na zpěv z bidýlka
static var SWALLOW_DAY := 0.15               # vlaštovky létají při denním světle nad tolik
static var SWALLOW_R := [5.0, 70.0]          # m – loví v okruhu od domova (od–do)
static var SWALLOW_LOW := [0.8, 4.0]         # m nad zemí – před deštěm (od–do)
static var SWALLOW_HIGH := [3.0, 20.0]       # m nad zemí – za pěkného počasí (od–do)
static var SWALLOW_LOW_CLOUD := 0.75         # nízko létají při oblačnosti nad tolik …
static var SWALLOW_LOW_RAIN := 0.05          # … nebo při dešti nad tolik
static var SWALLOW_SPEED := [10.0, 14.0]     # m/s – rychlost lovu (od–do)
static var SWALLOW_RETARGET_P := 0.15        # 1/s – nový cíl lovu
static var RIDGE_R := 90.0                   # m – hřeben střechy pro vlaštovky do této vzdálenosti
static var THERMAL_DAY := 0.6                # káně krouží (termika) při denním světle nad tolik …
static var THERMAL_CLOUD := 0.85             # … oblačnosti pod tolik …
static var THERMAL_RAIN := 0.05              # … a dešti pod tolik
static var SOAR_R := 55.0                    # m – poloměr kroužení (bez bubliny)
static var SOAR_WANDER := 150.0              # m – střed kroužení putuje nad okrskem
static var SOAR_ALT := 90.0                  # m nad terénem – výška kroužení (bez letového modelu / bubliny)
static var SOAR_ALT_VAR := 25.0              # m – kolísání výšky
static var SOAR_BUBBLE_K := 0.4              # v bublině poloměr kruhu = poloměr bubliny × tohle …
static var SOAR_R_MIN := 35.0                # m
static var SOAR_R_MAX := 60.0                # m
static var SOAR_SPEED := 9.5                 # m/s
static var APPROACH_D := 15.0                # m – blíž k místu přistání zpomalí …
static var APPROACH_K := 0.6                 # … na cestovní × tohle
static var LAND_TIMEOUT := 40.0              # s – po tolika s letu hejno přistane hned
static var PERCH_R_CROW := 90.0              # m – vrány hledají bidýlka v tomto okruhu
static var PERCH_R_KOS := 40.0               # m – kos
static var PERCH_R_KANE := 200.0             # m – káně

var fauna: Fauna
var net_id := 0                      # stabilní síťové číslo (Fauna ho přiděluje)
var authority := true                # false = klientská kopie hejna podle stavu ze serveru
var net_seed := 0                    # seed ze `setup` (klient z něj hejno znovu sestaví)
var species := ""
var home := Vector3.ZERO
var spot := Vector3.ZERO             # kde se hejno právě zdržuje
var birds: Array = []                # Array[Bird]
var mode := "ground"
var rng := RandomNumberGenerator.new()

var _goals := {}                     # bird → cílový bod na zemi / větvi
var _mode_t := 0.0
var _call_t := 3.0
var _snd: AudioStreamPlayer3D
var _soar_a := 0.0
var _near := false
var _stay := 60.0                    # jak dlouho má trvat současný klidový režim (ground / perch / hunt), s
var _rest_t := 0.0                   # káně: odpočet do dalšího „hodu kostkou“ na slétnutí
var _remote_set := false             # klient: přišel už aspoň jeden stav ze serveru
var _remote_mode := "ground"         # klient: režim, ve kterém je hejno podle serveru
var _remote_land := ""
var _remote_spot := Vector3.ZERO


func setup(f: Fauna, id: String, pos: Vector3, seed_: int) -> void:
	fauna = f
	species = id
	home = pos
	spot = pos
	net_seed = seed_
	rng.seed = seed_
	position = Vector3.ZERO
	name = "%s_%d" % [id, seed_ % 10000]


func _ready() -> void:
	var n := 1
	match species:
		"vrana":
			n = rng.randi_range(CROW_N[0], CROW_N[1]) + (CROW_WINTER_ADD if fauna.clock.month() in [11, 12, 1, 2] else 0)
			mode = "ground"
		"kos":
			n = 2 if fauna.clock.month() in [3, 4, 5, 6, 7] else 1
			mode = "ground"
		"vlastovka":
			n = rng.randi_range(SWALLOW_N[0], SWALLOW_N[1])
			mode = "hunt"
		"kane":
			n = 1
			mode = "soar"
	for i in n:
		var b := Bird.new()
		var p := home + Vector3(rng.randf_range(-6, 6), 0, rng.randf_range(-6, 6))
		p.y = fauna.terrain.height_at(p.x, p.z) + (0.2 if mode == "ground" else rng.randf_range(8.0, 20.0))
		if species == "kane":
			p.y += 70.0
		b.setup(species, fauna.terrain, p, rng.randi())
		b.world = fauna.world                # M8.10: vítr a termika pro letový model
		b.state = "ground" if mode == "ground" else "fly"
		add_child(b)
		birds.append(b)
		_goals[b] = p
	_snd = NatureSfx.player3d(self, 140.0 if species == "kane" or species == "vrana" else 70.0, 0.0)
	_soar_a = rng.randf() * TAU
	_stay = _roll_stay()


func _physics_process(delta: float) -> void:
	var __t0 := Tests.prof_t0()
	_physics_process_impl(delta)
	Tests.prof_add("flock", __t0)


func _physics_process_impl(delta: float) -> void:
	var w = fauna.world
	var near: bool = w.nearest_player_dist(spot) < SIM_R
	if near != _near:
		_near = near
		for b in birds:
			b.visible = near
	if not near:
		return
	var c: Clock = fauna.clock
	var weather: Weather = fauna.weather
	var day := c.daylight()
	_mode_t += delta
	if not authority:
		_client_step(delta, day, c, weather)
		_calls(delta, day, c)
		return
	match species:
		"vrana":
			_crows(delta, day, w)
		"kos":
			_blackbird(delta, day, w, c)
		"vlastovka":
			_swallows(delta, day, c, weather, w)
		"kane":
			_buzzard(delta, day, weather, w)
	_calls(delta, day, c)


# ------------------------------------------------------------------ síť

## Stav hejna pro klienty (celá čísla): [net_id, index druhu (Fauna.FLOCK_SPECIES), seed, index režimu (MODES),
## spot x, y, z (dm), čas v režimu (1/10 s), domov x, z (dm), index cíle přistání (LANDS)].
func flock_state() -> Array:
	var land := 0
	if not birds.is_empty():
		land = maxi(LANDS.find(String(birds[0].land_on)), 0)
	return [net_id, Fauna.FLOCK_SPECIES.find(species), net_seed, maxi(MODES.find(mode), 0),
		roundi(spot.x * 10.0), roundi(spot.y * 10.0), roundi(spot.z * 10.0), roundi(_mode_t * 10.0),
		roundi(home.x * 10.0), roundi(home.z * 10.0), land]


## Klient převezme stav hejna. Přepne až při změně režimu / cíle (`spot`) – o vyrušení rozhodl server.
func apply_flock_state(s: Array) -> void:
	var m: String = MODES[clampi(int(s[3]), 0, MODES.size() - 1)]
	var sp := Vector3(float(s[4]) * 0.1, float(s[5]) * 0.1, float(s[6]) * 0.1)
	var first := not _remote_set
	# káně při kroužení mění `spot` pořád (střed kruhu) – to není nový cíl
	var moved := m != "soar" and m != "hunt" and sp.distance_to(_remote_spot) > 0.5
	var changed := first or m != _remote_mode or moved
	_remote_set = true
	_remote_mode = m
	_remote_land = LANDS[clampi(int(s[10]), 0, LANDS.size() - 1)]
	_remote_spot = sp
	if m == "soar":
		_mode_t = float(s[7]) * 0.1         # střed kruhu se počítá z času v režimu → drž shodu se serverem
	if changed:
		_mode_t = float(s[7]) * 0.1
		_client_transition(first)


## Nový režim / cíl ze serveru: rozlétnout se k bidýlku nebo na zem, začít lovit / kroužit.
func _client_transition(first: bool) -> void:
	spot = _remote_spot
	match _remote_mode:
		"fly":
			_client_launch(_remote_land)
		"ground", "perch":
			if first:
				_client_place(_remote_mode == "ground")
		"hunt":
			for b in birds:
				b.state = "fly"
				b.land_on = ""
				b.speed = maxf(b.speed, 5.0)
		"soar":
			for b in birds:
				b.state = "soar"
				b.land_on = ""
				b.speed = maxf(b.speed, 6.0)
	if _remote_mode != "fly":
		mode = _remote_mode


## Hejno vzlétne k `spot` ze serveru a přistane na zem / bidýlko (každý pták kousek jinde).
func _client_launch(land: String) -> void:
	var ground := land == "ground"
	var spread := 8.0 if ground else 1.2
	for b in birds:
		var g := _remote_spot + Vector3(rng.randf_range(-spread, spread), 0, rng.randf_range(-spread, spread))
		if ground:
			g.y = fauna.terrain.height_at(g.x, g.z)
		b.perch_off = 0.05
		_goals[b] = g
		b.target = g + Vector3(0, 1.0 if ground else 1.5, 0)
		b.land_on = "ground" if ground else "perch"
		b.state = "fly"
		b.speed = maxf(b.speed, 4.0)
		b.pitch = 0.4 if ground else 0.5
	mode = "fly"
	_mode_t = 0.0
	_play_flap()


## Pozdní připojení: hejno rovnou stojí na zemi / bidýlku podle serveru (bez letu).
func _client_place(ground: bool) -> void:
	for b in birds:
		var g := _remote_spot + Vector3(rng.randf_range(-6, 6) if ground else rng.randf_range(-1.2, 1.2), 0,
			rng.randf_range(-6, 6) if ground else rng.randf_range(-1.2, 1.2))
		if ground:
			g.y = fauna.terrain.height_at(g.x, g.z)
		_goals[b] = g
		b.global_position = g + Vector3(0, float(b.spec["length"]) * 0.28 if ground else 0.05, 0)
		b.state = "ground" if ground else "perch"
		b.speed = 0.0
		b.pitch = 0.0
		b.bank = 0.0
		b.yaw = rng.randf() * TAU


## Krok klientské kopie hejna: let / přistání, chůze po zemi, lov vlaštovek, kroužení káněte.
func _client_step(delta: float, day: float, c: Clock, weather: Weather) -> void:
	if species == "vlastovka":
		var present := Seasons.swallows_present(c.day_of_year()) and day > SWALLOW_DAY
		for b in birds:
			b.visible = present
		if not present:
			return
	match _remote_mode:
		"hunt":
			_client_hunt(delta, weather)
		"soar":
			_client_soar(delta)
		_:
			var flying := false
			for b in birds:
				if b.state == "fly":
					flying = true
					break
			if flying:
				_fly_all(delta)
			elif _remote_mode == "ground":
				var spread: float = CROW_SPREAD if species == "vrana" else KOS_SPREAD
				var rate: float = CROW_WANDER_P if species == "vrana" else KOS_WANDER_P
				for b in birds:
					var g: Vector3 = _goals[b]
					if b.global_position.distance_to(g) < 0.4 or rng.randf() < delta * rate:
						g = spot + Vector3(rng.randf_range(-spread, spread), 0, rng.randf_range(-spread, spread))
						_goals[b] = g
					b.ground_step(delta, g)


## Vlaštovky loví (stejné jako `_swallows`, jen bez rozhodování o sednutí).
func _client_hunt(delta: float, weather: Weather) -> void:
	_hunt_step(delta, weather)


## Lov vlaštovek nízko nad loukami (před deštěm níž) – sdílí server (`_swallows`) i klient.
func _hunt_step(delta: float, weather: Weather) -> void:
	var low := weather != null and (weather.cloud > SWALLOW_LOW_CLOUD or weather.rain > SWALLOW_LOW_RAIN)
	for b in birds:
		var g: Vector3 = _goals[b]
		if b.global_position.distance_to(g) < 3.0 or rng.randf() < delta * SWALLOW_RETARGET_P:
			var a := rng.randf() * TAU
			var r := rng.randf_range(SWALLOW_R[0], SWALLOW_R[1])
			g = home + Vector3(cos(a) * r, 0, sin(a) * r)
			g.y = fauna.terrain.height_at(g.x, g.z) + (rng.randf_range(SWALLOW_LOW[0], SWALLOW_LOW[1]) if low else rng.randf_range(SWALLOW_HIGH[0], SWALLOW_HIGH[1]))
			_goals[b] = g
		b.target = g
		b.land_on = ""
		b.state = "fly"
		b.fly_step(delta, rng.randf_range(SWALLOW_SPEED[0], SWALLOW_SPEED[1]))


## Káně krouží nad domovem (stejný střed jako `_buzzard`, čas v režimu se hlídá se serverem).
func _client_soar(delta: float) -> void:
	var b: Bird = birds[0]
	_soar_step(delta, b)


# ------------------------------------------------------------------ vrány

func _crows(delta: float, day: float, w: Node) -> void:
	match mode:
		"ground":
			var threat := _threat(w, SCARE_GROUND["vrana"])
			if threat or day < CROW_NIGHT_DAY:
				if threat:
					_call("crow", 1.2)
				if day < CROW_NIGHT_DAY:
					_fly_to_trees(spot, ROOST_R, true)         # nocoviště v lese
				else:
					_scatter(SCATTER_R)
				return
			if _mode_t > _stay:
				if rng.randf() < CROW_PERCH_CHANCE:
					_scatter(SCATTER_R)
					return
				_mode_t = 0.0
				_stay = _roll_stay()
			for b in birds:
				var g: Vector3 = _goals[b]
				if b.global_position.distance_to(g) < 0.4 or rng.randf() < delta * CROW_WANDER_P:
					g = spot + Vector3(rng.randf_range(-CROW_SPREAD, CROW_SPREAD), 0, rng.randf_range(-CROW_SPREAD, CROW_SPREAD))
					_goals[b] = g
				b.ground_step(delta, g)
		"fly":
			_fly_all(delta)
		"perch":
			if _threat(w, SCARE_PERCH["vrana"]):
				_relocate(w)
			elif day >= CROW_NIGHT_DAY and _mode_t > _stay:
				# zpátky na pole (jinam, když tam pořád někdo je)
				spot = fauna.random_point(home, FIELD_R, "field", rng)
				_fly_all_to_ground(spot, 12.0)


## Vrány vzlétnou na bidýlka (stromy, střechy); nejsou-li, na koruny stromů / na zem.
func _scatter(tree_radius: float) -> void:
	if not _perch_to(_find_perches(spot)):
		_fly_to_trees(spot, tree_radius, false)


# ------------------------------------------------------------------ kos

func _blackbird(delta: float, day: float, w: Node, c: Clock) -> void:
	var sing_time := c.month() >= 3 and c.month() <= 7 and (c.hour() < SING_MORNING_H and day > 0.05 or c.hour() > SING_EVENING_H and day > 0.05)
	match mode:
		"ground":
			var threat := _threat(w, SCARE_GROUND["kos"])
			if threat or sing_time or day < 0.05 or _mode_t > _stay:
				if threat:
					_call("blackbird", 1.6)
				var ok := false
				if sing_time and not threat:
					ok = _sing_perch()
				if not ok:
					ok = _perch_to(_find_perches(spot))
				if not ok:
					_fly_to_trees(spot, 40.0, false, 3.0, 9.0)
				return
			for b in birds:
				var g: Vector3 = _goals[b]
				if b.global_position.distance_to(g) < 0.4 or rng.randf() < delta * KOS_WANDER_P:
					g = spot + Vector3(rng.randf_range(-KOS_SPREAD, KOS_SPREAD), 0, rng.randf_range(-KOS_SPREAD, KOS_SPREAD))
					_goals[b] = g
				b.ground_step(delta, g)
		"fly":
			_fly_all(delta)
		"perch":
			if _threat(w, SCARE_PERCH["kos"]):
				_relocate(w)
				return
			if sing_time and rng.randf() < delta * SING_P:
				_call("blackbird", 1.0)
			if not sing_time and day > 0.05 and _mode_t > _stay and not _threat(w, KOS_LEAVE_R):
				spot = fauna.random_point(home, KOS_GARDEN_R, "garden", rng, 4)
				_fly_all_to_ground(spot, 4.0)


## Kos zpívá z nejvyššího bidýlka do 40 m (hřeben střechy / vrchol stromu).
func _sing_perch() -> bool:
	var spots: Array = fauna.perch_spots(spot, PERCH_R_KOS, 5, 1.0, 0.6, 3.0)
	if spots.is_empty():
		return false
	var best: Vector4 = spots[0]
	for sv in spots:
		var s4: Vector4 = sv
		if s4.y > best.y:
			best = s4
	return _perch_to([best])


# ------------------------------------------------------------------ vlaštovky

func _swallows(delta: float, day: float, c: Clock, weather: Weather, w: Node) -> void:
	var present := Seasons.swallows_present(c.day_of_year()) and day > SWALLOW_DAY
	for b in birds:
		b.visible = present
	if not present:
		return
	if mode == "fly":                      # přelet na hřeben
		_fly_all(delta)
		return
	if mode == "perch":                    # sedí v řadě na hřebeni
		if _mode_t > _stay:
			_swallow_hunt()
		elif _threat(w, SCARE_PERCH["vlastovka"]):
			if not _swallow_sit(w):
				_swallow_hunt()
		return
	if _mode_t > _stay:                    # po lovu si sednou (nenajdou-li hřeben, loví dál)
		if _swallow_sit(null):
			return
		_mode_t = 0.0
		_stay = _roll_stay()
	# před deštěm (vlhko, nízká oblačnost) loví hmyz nízko nad zemí
	_hunt_step(delta, weather)


## Hejno se v řadě usadí na hřeben střechy do 90 m od domova (`w` = hráč, od kterého se utíká; null = nic).
func _swallow_sit(w: Node) -> bool:
	var row: Array = fauna.ridge_row(home, RIDGE_R, birds.size())
	if row.is_empty():
		return false
	if w != null:
		var p: Node3D = w.nearest_player(spot)
		var r0: Vector4 = row[0]
		if p != null and Vector2(r0.x - p.global_position.x, r0.z - p.global_position.z).length() < RELOCATE_AWAY:
			return false
	return _perch_to(row, 0.0, true)


## Vlaštovky slétnou z hřebene a zase loví.
func _swallow_hunt() -> void:
	mode = "hunt"
	_mode_t = 0.0
	_stay = _roll_stay()
	spot = home
	for b in birds:
		b.state = "fly"
		b.land_on = ""
		b.speed = 5.0
		b.pitch = 0.2


# ------------------------------------------------------------------ káně

func _buzzard(delta: float, day: float, weather: Weather, w: Node) -> void:
	var thermals := day > THERMAL_DAY and weather != null and weather.cloud < THERMAL_CLOUD and weather.rain < THERMAL_RAIN
	var b: Bird = birds[0]
	if mode == "fly":
		_fly_all(delta)
		return
	if mode == "perch":
		if _threat(w, SCARE_PERCH["kane"]):
			_relocate(w)
			return
		if thermals and _mode_t > _stay:        # po odpočinku zase krouží
			mode = "soar"
			_mode_t = 0.0
			b.land_on = ""
			b.speed = 6.0
			b.pitch = 0.0
		else:
			return
	if thermals:
		mode = "soar"
		_soar_step(delta, b)
		# občas si sedne na strom (jednou za pár minut kostka)
		_rest_t += delta
		if _rest_t > BUZZARD_REST_EVERY:
			_rest_t = 0.0
			if rng.randf() < BUZZARD_REST_CHANCE:
				_buzzard_perch()
	elif mode == "soar":
		_buzzard_perch()


## Kroužení káně: kruhy ~55 m kolem středu, který pomalu putuje nad okrskem (původní chování). M8.10: je-li
## v dosahu bublina `Thermals`, krouží v ní (střed bubliny táhne s větrem) a stoupá; jinak ji nese slabá termika
## `BUZZARD_WEAK_LIFT` u středu kruhu. Termika slábne pod stropem kroužení (`BUZZARD_CEIL` nad terénem).
func _soar_step(delta: float, b: Bird) -> void:
	var r := SOAR_R
	_soar_a += delta * b.speed / r
	spot = home + Vector3(sin(_mode_t * 0.01) * SOAR_WANDER, 0, cos(_mode_t * 0.013) * SOAR_WANDER)
	var gy := fauna.terrain.height_at(spot.x, spot.z) + SOAR_ALT + sin(_mode_t * 0.05) * SOAR_ALT_VAR
	if FlightModel.on and b.fm:
		var w: World = fauna.world
		var best := BUZZARD_THERMAL_R
		var found := false
		if w and w.thermals:
			for bb in w.thermals.bubbles:
				var bp: Vector2 = bb["pos"]
				var d := bp.distance_to(Vector2(home.x, home.z))
				if d < best:
					best = d
					found = true
					spot = Vector3(bp.x, 0.0, bp.y)
					r = clampf(float(bb["r"]) * SOAR_BUBBLE_K, SOAR_R_MIN, SOAR_R_MAX)
		var ground := fauna.terrain.height_at(spot.x, spot.z)
		b.fm.soar_ceil = ground + BUZZARD_CEIL
		# bez bubliny: slabá termika u středu kruhu (ať káně neztrácí výšku a nemává)
		b.fm.lift_bias = 0.0 if found else BUZZARD_WEAK_LIFT
		# cíl výšky = strop (stoupá, kolik ji termika pustí); v bublině kruh dle poloměru bubliny
		gy = ground + BUZZARD_CEIL if found else gy
	b.target = Vector3(spot.x + cos(_soar_a) * r, gy, spot.z + sin(_soar_a) * r)
	b.state = "soar"
	b.land_on = ""
	b.fly_step(delta, SOAR_SPEED)


func _buzzard_perch() -> void:
	if not _perch_to(_find_perches(home)):
		_fly_to_trees(home, PERCH_R_KANE, false)


# ------------------------------------------------------------------ společné

func _threat(w: Node, r: float) -> bool:
	var p: Node3D = w.nearest_player(spot)
	if p == null:
		return false
	for b in birds:
		var d: float = b.global_position.distance_to(p.global_position)
		var car: Node3D = p.get("car")
		if d < r or (car and d < r * CAR_SCARE_K):
			return true
	return false


## Hejno vzlétne a každý pták si vybere korunu stromu v okolí (nebo nocoviště v lese).
func _fly_to_trees(center: Vector3, radius: float, roost: bool, min_h := 6.0, max_h := 40.0) -> void:
	var trees: Array = fauna.trees_near(center, radius, 60)
	if roost:
		var p: Vector3 = fauna.random_point(center, radius, "forest", rng)
		trees = fauna.trees_near(p, 60.0, 40)
	var ok := []
	for t in trees:
		if t.w >= min_h and t.w <= max_h:
			ok.append(t)
	if ok.is_empty():
		# žádný strom – jinam na zem
		_fly_all_to_ground(fauna.random_point(center, radius, "field", rng), 10.0)
		return
	var tt: Vector4 = ok[rng.randi() % ok.size()]
	for b in birds:
		if rng.randf() < 0.5:
			tt = ok[rng.randi() % ok.size()]
		var top := Vector3(tt.x + rng.randf_range(-1.2, 1.2), tt.y + tt.w * rng.randf_range(0.8, 0.97), tt.z + rng.randf_range(-1.2, 1.2))
		_goals[b] = top
		b.perch_off = 0.05
		b.target = top + Vector3(0, 1.5, 0)
		b.land_on = "perch"
		b.state = "fly"
		b.speed = maxf(b.speed, 4.0)
		b.pitch = 0.5
	spot = Vector3(tt.x, tt.y, tt.z)
	mode = "fly"
	_mode_t = 0.0
	_play_flap()


func _fly_all_to_ground(p: Vector3, spread: float) -> void:
	spot = p
	for b in birds:
		var g := p + Vector3(rng.randf_range(-spread, spread), 0, rng.randf_range(-spread, spread))
		g.y = fauna.terrain.height_at(g.x, g.z)
		_goals[b] = g
		b.target = g + Vector3(0, 1.0, 0)
		b.land_on = "ground"
		b.state = "fly"
		b.speed = maxf(b.speed, 4.0)
		b.pitch = 0.4
	mode = "fly"
	_mode_t = 0.0
	_play_flap()


## Let celého hejna k cílům; kdo doletí, přistane (na zem / na větev). Až jsou všichni dole, mění se režim.
func _fly_all(delta: float) -> void:
	var landed := 0
	var last := ""
	_boids(delta)
	for b in birds:
		if b.state == "fly":
			var g: Vector3 = _goals[b]
			# na zemi i na předmětu stojí pták na nohách (0,28 délky), na větvi jen 0,05 m
			var off: float = float(b.spec["length"]) * 0.28 if b.land_on == "ground" else float(b.perch_off)
			b.set_land_goal(g + Vector3(0, off, 0))      # M8.10: letový model k tomu bodu brzdí a klesá
			var d: float = b.fly_step(delta, float(b.spec["cruise"]) * (1.0 if b.global_position.distance_to(g) > APPROACH_D else APPROACH_K))
			if d < b.land_reach() or _mode_t > LAND_TIMEOUT:
				b.global_position = g + Vector3(0, off, 0)
				b.yaw = rng.randf() * TAU                 # každý pták jinam
				b.state = "ground" if b.land_on == "ground" else "perch"
				b.speed = 0.0
				b.pitch = 0.0
				b.bank = 0.0
		if b.state != "fly":
			landed += 1
			last = b.state
	if landed == birds.size():
		mode = last
		_mode_t = 0.0
		_stay = _roll_stay()


var _boid_t := 0.0


## M8.10 boidy (Reynolds): letícím vránám se 5× za s spočte posun cíle – oddělení od sousedů blíž než
## BOID_SEP_R, zarovnání s průměrnou rychlostí hejna, soudržnost ke středu. Hejno ≤ ~18 ptáků → n² stačí.
func _boids(delta: float) -> void:
	if species != "vrana" or not FlightModel.on:
		return
	_boid_t -= delta
	if _boid_t > 0.0:
		return
	_boid_t = BOID_S
	var n := 0
	var c := Vector3.ZERO
	var av := Vector3.ZERO
	for b in birds:
		if b.state == "fly":
			n += 1
			c += b.global_position
			av += b.vel
	if n < 3:
		for b in birds:
			b.boid_bias = Vector3.ZERO
		return
	c /= float(n)
	av /= float(n)
	for b in birds:
		if b.state != "fly":
			continue
		var p: Vector3 = b.global_position
		var sep := Vector3.ZERO
		for o in birds:
			if o == b or o.state != "fly":
				continue
			var dd: Vector3 = p - o.global_position
			var l2 := dd.length_squared()
			if l2 < BOID_SEP_R * BOID_SEP_R and l2 > 0.0001:
				sep += dd / l2
		var bias: Vector3 = sep * float(BOID_K[0]) + (av - b.vel) * float(BOID_K[1]) + (c - p) * float(BOID_K[2])
		b.boid_bias = bias.limit_length(BOID_MAX)


## Jak dlouho potrvá klidový režim, do kterého se hejno právě dostalo (ground / perch / hunt).
func _roll_stay() -> float:
	var r: Array = [60.0, 60.0]
	match species:
		"vrana":
			r = CROW_GROUND if mode == "ground" else CROW_STAY
		"kos":
			r = BLACKBIRD_CYCLE
		"vlastovka":
			r = SWALLOW_HUNT if mode == "hunt" else SWALLOW_SIT
		"kane":
			r = BUZZARD_STAY
	return rng.randf_range(r[0], r[1])


## Bidýlka v okolí `center` podle druhu (Vector4 x, y, z, kind): vrány mix stromů a střech,
## kos hlavně střechy, káně jen vysoké stromy.
func _find_perches(center: Vector3) -> Array:
	match species:
		"vrana":
			return fauna.perch_spots(center, PERCH_R_CROW, mini(ceili(birds.size() / 2.0), 8), 1.0, 0.5, 6.0)
		"kos":
			return fauna.perch_spots(center, PERCH_R_KOS, 4, 1.0, 0.6, 3.0)
		"kane":
			return fauna.perch_spots(center, PERCH_R_KANE, 3, 1.0, 0.0, 10.0)
	return []


## Hejno vzlétne a rozdělí se na dané bidýlka (kind 0 strom, 1 střecha / předmět). `jitter` = rozptyl
## kolem bodu (m; -1 = strom 1,2 / střecha 0,25), `ordered` = každý pták další bidýlko v pořadí (řada).
## Vrací false, když nejsou žádná bidýlka.
func _perch_to(spots: Array, jitter := -1.0, ordered := false) -> bool:
	if spots.is_empty():
		return false
	var i := 0 if ordered else rng.randi() % spots.size()
	for b in birds:
		var sp: Vector4 = spots[i % spots.size()]
		i += 1
		var jit := jitter if jitter >= 0.0 else (1.2 if sp.w < 0.5 else 0.25)
		var goal := Vector3(sp.x + rng.randf_range(-jit, jit), sp.y, sp.z + rng.randf_range(-jit, jit))
		_goals[b] = goal
		b.perch_off = 0.05 if sp.w < 0.5 else float(b.spec["length"]) * 0.28
		b.target = goal + Vector3(0, 1.5, 0)
		b.land_on = "perch"
		b.state = "fly"
		b.speed = maxf(b.speed, 4.0)
		b.pitch = 0.5
	var s0: Vector4 = spots[0]
	spot = Vector3(s0.x, s0.y, s0.z)
	mode = "fly"
	_mode_t = 0.0
	_play_flap()
	return true


## Hráč se blíží k sedícímu hejnu → přeletí na jiné bidýlko (aspoň RELOCATE_AWAY od hráče), jinak dolů.
func _relocate(w: Node) -> void:
	var p: Node3D = w.nearest_player(spot)
	var far := []
	for sv in _find_perches(spot):
		var s4: Vector4 = sv
		if p == null or Vector2(s4.x - p.global_position.x, s4.z - p.global_position.z).length() > RELOCATE_AWAY:
			far.append(s4)
	if _perch_to(far):
		return
	# žádné vhodné bidýlko → původní chování
	match species:
		"kane":
			_fly_to_trees(home, PERCH_R_KANE, false)
		"kos":
			_fly_all_to_ground(fauna.random_point(home, KOS_GARDEN_R, "garden", rng, 4), 4.0)
		_:
			_fly_all_to_ground(fauna.random_point(home, FIELD_R, "field", rng), 12.0)


func _calls(delta: float, day: float, c: Clock) -> void:
	_call_t -= delta
	if _call_t > 0.0:
		return
	_call_t = rng.randf_range(8.0, 25.0)
	match species:
		"vrana":
			if day > 0.15 and rng.randf() < 0.6:
				_call("crow", 1.0)
		"vlastovka":
			if birds[0].visible and rng.randf() < 0.7:
				_call("swallow", 1.0)
		"kane":
			if mode == "soar" and rng.randf() < 0.35:
				_call("buzzard", 1.0)


func _call(sound: String, pitch: float) -> void:
	if birds.is_empty():
		return
	var b: Bird = birds[rng.randi() % birds.size()]
	_snd.global_position = b.global_position
	_snd.stream = NatureSfx.get_stream(sound)
	_snd.pitch_scale = pitch * rng.randf_range(0.92, 1.08)
	_snd.play()


func _play_flap() -> void:
	if birds.is_empty():
		return
	var p := NatureSfx.player3d(self, 40.0, -4.0)
	p.global_position = birds[0].global_position
	p.stream = NatureSfx.get_stream("flap")
	p.pitch_scale = rng.randf_range(0.9, 1.2) * (1.4 if species == "kos" else 1.0)
	p.play()
	p.finished.connect(p.queue_free)
