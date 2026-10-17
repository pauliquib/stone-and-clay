## Bot – vesničan. Každý je jiná smyšlená postava (Characters: jméno, povolání, povaha, vzhled, tempo chůze).
## Chodí po silnicích a cestách (graf z OSM), občas se zastaví; když k němu hráč přijde, otočí se, zamává
## a pozdraví podle své povahy, nálady a pověsti hráče (Dialog.greet). Odpovídá na to, co hráč řekne (T),
## a na E prozradí drb. Vždy řeší nejbližšího hráče.
## Daleko od všech hráčů se pohybuje bez fyziky (jen po terénu) – šetří výkon.
## Fáze 3 (LimboAI): prvních `BT_VILLAGERS` vesničanů řídí behavior strom `ai/villager_routine.tres`
## (denní rutiny – zahrada, práce, hospoda, procházka). BT jen volí cíl (`move_to`/`clear_target`),
## samotný pohyb, zdravení i útěk řeší původní kód; bez addonu nebo stromu běží vše jako dřív.
## M8.17 Život vesnice: ostatní vesničany vede plán dne domácnosti (`Households` → `set_plan` jednou za herní
## hodinu: domů, na dvůr štípat, na zahradu, do práce, do hospody, na návštěvu); doma se schovají do domu
## (bez fyziky a vizuálu – `_enter_house`), za simulační bublinou se na cíl jen přesunou. Oblékají se podle
## teploty (`dress_level`). Bez domácností (vypnutý přepínač `village_life`) chodí jako dřív.
class_name Villager
extends CharacterBody3D

static var PHYSICS_RANGE := 160.0
## Krok kinematického pohybu hluboce uspaného vesničana (za simulační bublinou World.sim_radius).
static var SLEEP_STEP := 0.5
## Kolik prvních spawnutých vesničanů dostane behavior strom (0 = BT nikdo; Fáze 3: testovací podmnožina).
## M8.17: laditelné (F3 → Člověk/Život vesnice, platí po novém načtení světa); ostatní řídí plán domácnosti.
static var BT_VILLAGERS := 5
const BT_TREE := "res://ai/villager_routine.tres"
## Druhy hran pro pěší A* trasu k cíli z BT (vše, kudy vesničan chodí).
const WALK_KINDS := ["secondary", "tertiary", "unclassified", "residential", "service", "living_street",
	"track", "footway", "path"]
## Povolání postavy (Characters.PROFILES[].job) → klíč místa pracoviště (`World.places`). Páruje se po
## SLOVECH povolání (začátek slova = kmen), ne podřetězcem: „hospodský“ → hospoda, ale „hospodář“ → statek.
## Co nesedí, zaměstnání nemá (důchodce, student, maminka na mateřské…) → větev „Práce“ ve stromu selže.
const JOB_PLACE := {
	"úřad": "urad", "účetní": "urad", "starosta": "urad",
	"hospodsk": "hospoda", "hostinsk": "hospoda", "výčep": "hospoda",
	"prodavač": "obchod", "obchod": "obchod", "pošt": "obchod", "cukrář": "obchod",
	"vinař": "sklep", "sklep": "sklep",
	"pálen": "palenice", "palič": "palenice",
	"myslivec": "chata", "lesní": "chata", "hajn": "chata",
	"zemědělec": "statek", "hospodář": "statek", "chovatel": "statek", "farm": "statek",
}
## Kmeny slov, které povolání zneplatní („bývalý hasič“, „starosta sousední vsi“, „pošta v okresním městě“
## = nepracuje tady, jen to slovo zní podobně).
const JOB_EXCLUDE := ["býval", "soused", "okresn"]
## Po kolika zaseknutích cestou za jedním cílem z BT vesničan cíl vzdá (a na ~`BT_GIVEUP_S` s ho nezkouší).
static var BT_STUCK_MAX := 3
static var BT_GIVEUP_S := 90.0
## M8.D2b: chování vesničana – dřív čísla v kódu, laditelné v menu F3 (Člověk / NPC a vesničané). Sdílené všemi
## vesničany (`static var`, za snímek žádný registr ani alokace – desítky instancí).
static var DEEP_K := 1.7               # × simulační bublina – za ní hluboký spánek (schovaný, ~2 Hz)
static var GRAVITY := 20.0             # m/s² – pád vesničana (jako hráč)
static var WALK_ACCEL := 8.0           # m/s² – rozjezd a brzdění chůze
static var WALK_TURN := 5.0            # /s – natáčení do směru chůze
static var SIDE_MIN := 2.9             # m od osy silnice – chodí při krajnici (nově vytvoření vesničané)
static var SIDE_MAX := 3.6
static var PATH_SIDE_K := 0.6          # × odstup na pěšině / polní cestě (skoro uprostřed)
static var SPEED_DEFAULT := 1.3        # m/s – tempo chůze, když ho postava nemá v profilu (nově vytvoření)
static var SPEED_JITTER := 0.07        # ± podíl náhodné odchylky tempa (nově vytvoření)
static var ARRIVE_R := 1.3             # m – dosažení bodu trasy
static var ARRIVE_LAST_R := 1.0        # m – dosažení cíle z behavior stromu (musí být menší než `arrive` v BT)
static var TARGET_TOL := 3.0           # m – nový cíl z BT blíž než tohle = stejný cíl
static var PAUSE_P := 0.06             # šance zastavení na křižovatce
static var PAUSE_MIN := 2.0            # s
static var PAUSE_MAX := 6.0            # s
static var STUCK_V := 0.25             # m/s – pod touto rychlostí (a s cílem) je zaseknutý
static var STUCK_S := 2.0              # s zaseknutí, než se otočí / přeplánuje
static var AVOID_R := 1.6              # m – neprojde skrz hráče, který stojí v cestě
static var GREET_R := 3.2              # m – pozdraví hráče
static var GREET_S := 3.5              # s – délka pozdravu
static var GREET_CD := 14.0            # s – znovu pozdraví nejdřív za
static var WAVE_S := 1.7               # s – mává na začátku repliky
static var TALK_TURN := 6.0            # /s – otočení k hráči při hovoru
static var WAIT_R := 11.0              # m – čeká na odpověď hráče, dokud je blíž
static var WAIT_TURN := 4.0            # /s – otočení k hráči při čekání
static var SAY_BASE_S := 2.0           # s – délka repliky: základ
static var SAY_CHARS_PER_S := 14.0     # znaků za s čtení
static var SAY_MIN_S := 3.5
static var SAY_MAX_S := 9.0
static var SAY_CD := 10.0              # s – po replice nezdraví
static var FLEE_SPEED := 4.6           # m/s – útěk před střelbou
static var FLEE_ACCEL := 12.0          # m/s² – rozběh při útěku
static var FLEE_TURN := 8.0            # /s – otočení při útěku
static var KNOCK_S := 4.0              # s ležení po sražení autem
static var KNOCK_PER_V := 0.2          # s navíc za m/s nárazu
static var KNOCK_DECEL := 6.0          # m/s² – dobrzdění sraženého
static var PROMILE_DECAY := 0.01       # ‰/s reálně – vystřízlivění (zjednodušené)
static var DRUNK_FULL_PROMILE := 2.0   # ‰ – plné potácení
static var GARDEN_D := 4.0             # m před domem – zahrada (BT)
## Optimalizace CPU (17. 10. 2026) – LOD kroku podle vzdálenosti od hráče (F3 → Člověk/LOD postav, `tune_m8_19.gd`).
## Krok se počítá jednou za N fyzikálních kroků s nasčítaným časem (stejná trasa i rychlost, nižší frekvence).
static var LOD_NEAR_R := 40.0          # m – blíž plná frekvence fyziky (60 Hz)
static var LOD_MID_N := 3              # LOD_NEAR_R … PHYSICS_RANGE (move_and_slide) – každý N-tý krok (20 Hz)
static var LOD_FAR_N := 4              # za PHYSICS_RANGE (kinematika po terénu / střední pásmo) – každý N-tý krok
static var LOD_BEHIND_N := 4           # za kamerou (jen jeden hráč, dál než LOD_NEAR_R / 2) aspoň tolikátý krok
static var ENTER_NEAR_R := 5.0         # M8.17: zaseknutý u dveří blíž než tohle = zajde dovnitř (plot, schod)

var graph: RoadGraph
var terrain: Terrain
var world: Node
var rng := RandomNumberGenerator.new()

var _cur := 0
var _prev := -1
var _next := 0
var _side := 1.2
var _speed := 1.4
var _pause := 0.0
var _talk := 0.0
var _talk_cool := 0.0
var _stuck := 0.0
var _visual: Humanoid
var _label: Label3D
var _yaw := 0.0
var _knocked := 0.0
var _flee_t := 0.0                 # do kdy (s) vesničan utíká před střelbou (M2.8, `Weapons`)
var _flee_from := Vector3.ZERO
var persona: Persona               # kdo to je (jméno, povaha…) a jak se na hráče dívá
var _name_label: Label3D
var _talk_len := 3.5              # jak dlouho aktuální replika trvá (mává jen na začátku)
var _wait := 0.0                  # hráč píše odpověď (T) – postůj a nikam neodcházej
var promile := 0.0                # Fáze 3: zjednodušená hladina alkoholu vesničana (pije v hospodě)
var use_bt := false               # setup(): má dostat behavior strom (prvních BT_VILLAGERS)
var _seed := 0                    # seed ze setup() – určuje i domov vesničana pro BT
var _bt = null                    # BehaviorTree (Resource) – klon na vesničana; netypované (addon nemusí být)
var _bt_inst = null               # BTInstance – živá instance stromu (tickuje se v _physics_process)
var _bt_bb = null                 # Blackboard – self, world, graph, terrain, home, workplace, garden, pub_table
var _bt_vars_ok := false          # jsou v blackboardu naplněné cíle (places/estate vznikají až po botách)
var _bt_target_pos := Vector3.INF # cíl pohybu z BT (INF = choď po grafu jako dřív)
var _bt_path: PackedVector3Array = PackedVector3Array()   # body trasy k _bt_target_pos (uzly grafu → 3D)
var _bt_path_i := 0               # index aktuálního bodu trasy
var _bt_stuck_n := 0              # kolikrát se zasekl cestou za aktuálním cílem z BT (BT_STUCK_MAX → vzdá)
var _bt_giveup_pos := Vector3.INF # cíl, který vzdal (A4-03) – dočasně ho `move_to` odmítá
var _bt_giveup_until := 0         # do kdy (Time.get_ticks_msec) se vzdaný cíl nezkouší
var _bt_work_ok := false          # pracoviště v blackboardu je hotové (statek vzniká později než boti)
var _bt_home := Vector3.INF       # dveře domu vesničana (estate) – plní _bt_fill_vars
var _bt_home_normal := Vector3(0, 0, 1)
var _deep := false                # hluboký spánek za 1.7× simulační bubliny (schovaný vizuál, ~2 Hz chůze)
var _deep_dt := 0.0               # nasčítaný čas do dalšího kroku hlubokého spánku
var _mid := false                 # střední pásmo (sim_radius…1.7×): viditelný, kinematika bez kolizí
var household := -1               # M8.17: index domácnosti (`World.households`), −1 = bez domova v registru
var _plan_inside := false         # M8.17: po příchodu na cíl zajít dovnitř (domov, návštěva)
var _plan_anim := ""              # M8.17: póza na místě (chop, dig)
var _anim_on := false
var _arrived := false             # cíl z BT / plánu už je dosažen (jednorázová reakce `_on_arrive`)
var _inside := false              # M8.17: je v domě – schovaný, bez fyziky (probudí ho `set_plan`)
var _house_door := Vector3.INF
var _lod_acc := 0.0               # LOD: nasčítaný čas od posledního kroku
var _lod_left := 0                # LOD: fyzikálních kroků do dalšího výpočtu
var _lod_n := 1                   # LOD: aktuální perioda (kroků)
var _dress := -1                  # M8.17: úroveň oblečení podle teploty (0 lehce, 1 větrovka, 2 bunda + čepice)


func setup(g: RoadGraph, t: Terrain, w: Node, start_node: int, seed_: int, prof: Dictionary, bt := false) -> void:
	graph = g
	terrain = t
	world = w
	use_bt = bt
	_seed = seed_
	rng.seed = seed_
	persona = Persona.make(prof)
	name = "Vesnican_" + String(prof["name"]).replace(" ", "_")
	_cur = start_node
	_next = graph.next_node(_cur, -1, rng)
	# chodí při krajnici (auta jezdí 1–1,6 m od osy silnice)
	_side = rng.randf_range(SIDE_MIN, SIDE_MAX) * (1.0 if rng.randf() < 0.5 else -1.0)
	_speed = float(prof.get("speed", SPEED_DEFAULT)) * rng.randf_range(1.0 - SPEED_JITTER, 1.0 + SPEED_JITTER)
	var n := graph.nodes[_cur]
	position = Vector3(n.x, terrain.height_at(n.x, n.y) + 0.1, n.y)


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 2 | 4 | 8 | 16
	floor_snap_length = 0.5
	floor_max_angle = deg_to_rad(50)
	var sh := CapsuleShape3D.new()
	sh.radius = 0.32
	sh.height = 1.75
	var cs := CollisionShape3D.new()
	cs.shape = sh
	cs.position.y = 0.875
	add_child(cs)
	_visual = Humanoid.new()
	Characters.apply_look(_visual, persona.profile)
	_visual.vis_end = 220.0            # postava za ~220 m nikdo stejně nerozezná (šetří draw call)
	if terrain != null:
		_visual.ground_fn = Callable(terrain, "height_at")      # M8.6: Gait – sklon pod chodidly
	add_child(_visual)
	_name_label = Label3D.new()
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.position = Vector3(0, 2.0 * _visual.scale_factor, 0)
	_name_label.font_size = 26
	_name_label.outline_size = 8
	_name_label.modulate = Color(0.8, 0.92, 1.0)
	_name_label.text = persona.display_name()
	_name_label.visibility_range_end = 14.0
	add_child(_name_label)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0, 2.25, 0)
	_label.font_size = 42
	_label.outline_size = 10
	_label.modulate = Color(1, 1, 0.9)
	_label.no_depth_test = false
	_label.width = 700.0
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM   # delší text roste nahoru
	_label.visible = false
	add_child(_label)
	if use_bt:
		_bt_start()


## ----------------------------------------------------------------- Fáze 3: behavior strom (LimboAI)

## Spustí behavior strom – jen když je addon LimboAI a strom existuje; jinak zůstane původní chůze.
## Strom se klonuje na vesničana (`persona.daily_routine`), aby si nesdíleli runtime stav.
func _bt_start() -> void:
	if not ClassDB.class_exists("BehaviorTree") or not ResourceLoader.exists(BT_TREE):
		return
	var src: Resource = load(BT_TREE)
	if src == null or not src.has_method("instantiate"):
		return
	_bt = src.clone()
	if persona:
		persona.daily_routine = _bt
	_bt_bb = ClassDB.instantiate("Blackboard")
	for k in ["self", "world", "graph", "terrain", "home", "garden", "workplace", "pub_table", "shop"]:
		_bt_bb.set_var(k, Vector3.INF)
	_bt_bb.set_var("workplace_key", "")
	_bt_bb.set_var("self", self)
	_bt_bb.set_var("world", world)
	_bt_bb.set_var("graph", graph)
	_bt_bb.set_var("terrain", terrain)
	# custom_scene_root = hlavní scéna: runtime-add_child uzly nemají owner, jinak instantiate selže.
	_bt_inst = _bt.instantiate(self, _bt_bb, self, get_tree().current_scene)


## Naplní blackboard cíli z herních dat – až když existují místa a registr nemovitostí
## (vesničané se rodí před `_spawn_places`/`estate`, proto se to dělá líně za běhu).
func _bt_fill_vars() -> void:
	if _bt_vars_ok and _bt_work_ok:
		return                             # M8.19B: vše vyplněno – bez dvou dynamických `world.get()` každý fyzikální krok
	var places = world.get("places") if world else null
	if not (places is Dictionary) or places.is_empty() or world.get("estate") == null:
		return
	if not _bt_vars_ok:
		_bt_vars_ok = true
		_bt_home = _home_pos()
		_bt_bb.set_var("home", _bt_home)
		_bt_bb.set_var("garden", _garden_pos())
		_bt_bb.set_var("pub_table", _pub_table_pos())
		var shop: Place = places.get("obchod")
		_bt_bb.set_var("shop", shop.door if shop else Vector3.INF)
	# pracoviště zvlášť: místo „statek“ vzniká později než ostatní → zkoušej dál, dokud nevznikne
	if not _bt_work_ok:
		var key := _workplace_key()
		_bt_bb.set_var("workplace_key", key)
		if key == "":
			_bt_work_ok = true            # povolání bez pracoviště (důchodce…) – hotovo
		elif places.has(key):
			_bt_bb.set_var("workplace", _workplace_pos())
			_bt_work_ok = true


## Dveře domu vesničana – nemovitost z registru (`Estate.pick_customer_house`, seed = jeho spawn seed).
func _home_pos() -> Vector3:
	var e = world.get("estate")
	if e and e.has_method("pick_customer_house"):
		var id: int = e.pick_customer_house(_seed, 700.0)
		var info: Dictionary = e.info(id)
		var door = info.get("door", Vector3.INF)
		if door is Vector3 and door != Vector3.INF:
			var n = info.get("normal", Vector3(0, 0, 1))
			if n is Vector3:
				_bt_home_normal = n
			return door
	return global_position   # bez registru: kde stojí


## Vlastní zahrada u domu – kus před vchodem (normála fasády domu). Kopání ranno 6–8.
func _garden_pos() -> Vector3:
	if _bt_home == Vector3.INF:
		return Vector3.INF
	var g := _bt_home + _bt_home_normal * GARDEN_D
	g.y = terrain.height_at(g.x, g.z)
	return g


## Klíč místa pracoviště podle povolání (`JOB_PLACE`, po slovech); "" = zaměstnání tady nemá.
func _workplace_key() -> String:
	var job := String(persona.profile.get("job", "")).to_lower() if persona else ""
	var words: PackedStringArray = job.replace(",", " ").replace("–", " ").replace("-", " ").split(" ", false)
	for w in words:
		for x in JOB_EXCLUDE:
			if w.begins_with(x):
				return ""
	for w in words:
		for k in JOB_PLACE:
			if w.begins_with(k):
				return JOB_PLACE[k]
	return ""


## Dveře pracoviště podle povolání (`_workplace_key` → `World.places`); INF = zaměstnání nemá / místo ještě není.
func _workplace_pos() -> Vector3:
	var key := _workplace_key()
	if key == "":
		return Vector3.INF
	var pl: Place = world.get("places").get(key)
	return pl.door if pl else Vector3.INF


## Stůl na zahrádce u hospody (`Place.garden_tables`), jinak dveře hospody.
func _pub_table_pos() -> Vector3:
	var pl: Place = world.get("places").get("hospoda")
	if pl == null:
		return Vector3.INF
	if pl.garden_tables.size() > 0:
		return pl.garden_tables[0]
	return pl.door


## Povel z BT: jdi na pozici `target` (trasa po silnicích, `_bt_step`). Opakované volání
## se stejným cílem nic nemění; nový cíl přepočítá trasu. Vrací false, když cíl nelze (INF / vzdaný).
func move_to(target: Vector3) -> bool:
	if target == Vector3.INF:
		return false
	# cíl, který vesničan po opakovaném zaseknutí vzdal, chvíli nezkouší (A4-03) → BT akce selže
	if _bt_giveup_pos != Vector3.INF and Time.get_ticks_msec() < _bt_giveup_until \
			and _bt_giveup_pos.distance_to(target) <= TARGET_TOL:
		return false
	if _bt_target_pos == Vector3.INF or _bt_target_pos.distance_to(target) > TARGET_TOL:
		_bt_target_pos = target
		_bt_path = PackedVector3Array()
		_bt_path_i = 0
		_bt_stuck_n = 0
		_arrived = false
	return true


## BT větev skončila (procházka): zruš cíl – vesničan zase chodí po grafu náhodně.
func clear_target() -> void:
	_bt_target_pos = Vector3.INF
	_bt_path = PackedVector3Array()
	_bt_path_i = 0
	_arrived = false


## Aktuální cíl z BT (testy, ladění); Vector3.INF = žádný.
func bt_target() -> Vector3:
	return _bt_target_pos


## Naplánuj pěší trasu k `_bt_target_pos` přes A* silničního grafu (uzly → 3D body po terénu).
func _bt_replan() -> void:
	_bt_path = PackedVector3Array()
	_bt_path_i = 0
	if graph == null or _bt_target_pos == Vector3.INF:
		return
	var ids := graph.route(Vector2(global_position.x, global_position.z),
		Vector2(_bt_target_pos.x, _bt_target_pos.z), WALK_KINDS)
	for id in ids:
		var n := graph.nodes[id]
		_bt_path.append(Vector3(n.x, terrain.height_at(n.x, n.y) + 0.1, n.y))
	_bt_path.append(_bt_target_pos)


## Krok po naplánované trase – jako `_goal`/`_advance`, jen s pevným cílem. Vrací žádanou rychlost.
func _bt_step() -> Vector3:
	if _bt_path.is_empty():
		_bt_replan()
	while _bt_path_i < _bt_path.size():
		var goal := _bt_path[_bt_path_i]
		var d := Vector2(goal.x - global_position.x, goal.z - global_position.z)
		var last := _bt_path_i == _bt_path.size() - 1
		# poslední bod <1,0 m: musí být menší než `arrive` v BT akcích Jdi na… (1,5+), jinak
		# by vesničan zaparkoval na okraji a BT úkol zůstal navždy RUNNING
		if d.length() < (ARRIVE_LAST_R if last else ARRIVE_R):
			_bt_path_i += 1
			continue
		return Vector3(d.x, 0, d.y).normalized() * _speed
	if not _arrived:
		_arrived = true
		_on_arrive()
	return Vector3.ZERO


# ----------------------------------------------------------------- M8.17: plán dne domácnosti

## Povel z `Households` (jednou za herní hodinu): jdi na `target` (INF = choď volně), po příchodu zajdi dovnitř
## (`inside`) nebo dělej `anim` (štípání, rytí). `snap`: za simulační bublinou se přesune rovnou (žádná chůze).
func set_plan(target: Vector3, inside: bool, anim: String, snap: bool) -> void:
	if use_bt:
		return
	if _anim_on and anim != _plan_anim:
		_visual.stop_action()
		_anim_on = false
	_plan_anim = anim
	_plan_inside = inside
	if target == Vector3.INF:
		if _inside:
			_leave_house()
		clear_target()
		return
	if _inside:
		if inside and target.distance_to(_house_door) <= TARGET_TOL:
			return                     # zůstává doma
		_leave_house()
	if not move_to(target):
		return
	if snap and _deep:
		global_position = target
		_bt_path = PackedVector3Array([target])
		_bt_path_i = 1
		_arrived = true
		_on_arrive()


## Došel na cíl z plánu: dovnitř, nebo práce na místě.
func _on_arrive() -> void:
	if _plan_inside and _bt_target_pos != Vector3.INF:
		_enter_house(_bt_target_pos)
	elif _plan_anim != "" and not _anim_on and _visual != null:
		_visual.start_action(_plan_anim)
		_anim_on = true


## Zajde do domu: schovaný pod terénem, bez fyziky a kolizí (žádná cena za snímek, nikdo ho nenajde).
func _enter_house(door: Vector3) -> void:
	if _inside or _knocked > 0.0 or _flee_t > 0.0:
		return
	_inside = true
	_house_door = door
	if _anim_on:
		_visual.stop_action()
		_anim_on = false
	_visual.visible = false
	_visual.set_process(false)
	_label.visible = false
	_name_label.visible = false
	collision_layer = 0
	velocity = Vector3.ZERO
	global_position = door - Vector3(0.0, 40.0, 0.0)
	set_physics_process(false)


func _leave_house() -> void:
	if not _inside:
		return
	_inside = false
	var p := _house_door
	if terrain != null:
		p.y = terrain.height_at(p.x, p.z)
	global_position = p
	collision_layer = 4
	_deep = false
	_mid = false
	_deep_dt = 0.0
	_lod_acc = 0.0
	_lod_left = 0
	_visual.visible = true
	_visual.set_process(true)
	_name_label.visible = true
	set_physics_process(true)


func is_inside() -> bool:
	return _inside


## Oblečení podle teploty (M8.16 háček): 0 = jak má v profilu, 1 = větrovka, 2 = bunda, čepice, rukavice.
## Přestavba postavy jen při změně úrovně (pár za den).
func dress_level(lvl: int) -> void:
	if lvl == _dress or _visual == null:
		return
	_dress = lvl
	var look: Dictionary = persona.profile.get("look", {}) if persona else {}
	var coats := [Color(0.22, 0.27, 0.36), Color(0.33, 0.25, 0.18), Color(0.2, 0.32, 0.24), Color(0.45, 0.14, 0.12)]
	var c: Color = coats[absi(_seed) % coats.size()]
	_visual.jacket_style = "" if lvl == 0 else ("vetrovka" if lvl == 1 else "bunda")
	_visual.jacket_color = c
	_visual.sleeve_c = c if lvl > 0 else Color(0, 0, 0, 0)
	_visual.long_sleeves = lvl > 0 or bool(look.get("sleeves", false))
	_visual.head_style = "kulich" if lvl == 2 and not bool(look.get("hat", false)) else ""
	_visual.gloves = lvl == 2
	if _visual._root != null:
		_visual._rebuild()


func _physics_process(delta: float) -> void:
	var __t0 := Tests.prof_t0()
	_lod_acc += delta
	_lod_left -= 1
	if _lod_left <= 0:
		var dt := minf(_lod_acc, 0.5)
		_lod_acc = 0.0
		_lod_n = 1
		_physics_impl(dt)
		_lod_left = _lod_n
	Tests.prof_add("villager", __t0)


## LOD: perioda kroku (fyzikálních kroků) podle vzdálenosti od nejbližšího hráče; v singleplayeru navíc
## šetří postavy za kamerou. Sražený, utíkající, mluvící a čekající vesničan jede vždy naplno.
func _lod_steps(dist: float) -> int:
	if dist < LOD_NEAR_R or _knocked > 0.0 or _flee_t > 0.0 or _talk > 0.0 or _wait > 0.0:
		return 1
	var n := LOD_MID_N if dist <= PHYSICS_RANGE else LOD_FAR_N
	if world != null and world.players.size() <= 1 and dist > LOD_NEAR_R * 0.5:
		LodCam.refresh(self)
		if LodCam.behind(global_position, 2.0):
			n = maxi(n, LOD_BEHIND_N)
	return maxi(n, 1)


## move_and_slide s krokem `dt` delším než fyzikální krok (LOD): rychlost se na pohyb dočasně zvětší.
func _slide(dt: float) -> void:
	var k := dt / get_physics_process_delta_time()
	if k > 1.05:
		velocity *= k
		move_and_slide()
		velocity /= k
	else:
		move_and_slide()


func _physics_impl(delta) -> void:
	if world != null:
		_visual.gait_on = world.realism_on("gait")   # M8.6: ať jde přepínač vypnout i za běhu (Esc → Nastavení)
	var player: Player = world.nearest_player(global_position)
	var to_player: Vector3 = world.player_world_pos(player) - global_position if player else Vector3(INF, 0, 0)
	var dist := to_player.length()
	_lod_n = _lod_steps(dist)
	# --- simulační pásma okolo hráče (plynulá bublina): <simr plná fyzika+kolize+BT,
	# simr…1.7×simr MID = viditelný vizuál, ale pohyb jen kinematicky bez kolizí (každý frame
	# plynule, levné), >1.7×simr hluboký spánek = schovaný vizuál, chůze ~2 Hz
	var simr: float = world.sim_radius if world != null else 320.0
	if dist > simr and _knocked <= 0.0 and _flee_t <= 0.0:
		if dist > simr * DEEP_K:
			if not _deep:
				_deep = true
				_visual.visible = false
				_visual.set_process(false)
				_name_label.visible = false
				_label.visible = false
			_deep_dt += delta
			if _deep_dt < SLEEP_STEP:
				return
			delta = _deep_dt
			_deep_dt = 0.0
			_deep_step(delta)
			return
		# MID: viditelný, ale bez move_and_slide a řečí – plynulý kinematický krok
		if _deep:
			_deep = false
			_deep_dt = 0.0
			_visual.visible = true
			_visual.set_process(true)
		if not _mid:
			_mid = true
			_label.visible = false
			_name_label.visible = false
		_deep_step(delta)
		_visual.speed = velocity.length()
		_visual.rotation.y = _yaw
		_visual.on_floor = true
		return
	elif _deep or _mid:
		_deep = false
		_mid = false
		_deep_dt = 0.0
		_visual.visible = true
		_visual.set_process(true)
		_name_label.visible = true
	_talk_cool = maxf(_talk_cool - delta, 0.0)
	if promile > 0.0:
		promile = maxf(promile - delta * PROMILE_DECAY, 0.0)   # ~0,6 ‰ za reálnou minutu (Fáze 3)

	# --- sražený autem: leží, pak vstane
	if _knocked > 0.0:
		_knocked -= delta
		velocity.x = move_toward(velocity.x, 0.0, KNOCK_DECEL * delta)
		velocity.z = move_toward(velocity.z, 0.0, KNOCK_DECEL * delta)
		velocity.y -= GRAVITY * delta
		_slide(delta)
		if global_position.y < terrain.height_at(global_position.x, global_position.z) - 1.0:
			global_position.y = terrain.height_at(global_position.x, global_position.z) + 0.3
		if _knocked <= 0.0:
			_visual.pose = "stand"
			_label.visible = false
		return
	# --- útěk před střelbou (M2.8): pryč od zdroje, rychle, bez hovoru
	if _flee_t > 0.0:
		_flee_t -= delta
		var away := global_position - _flee_from
		away.y = 0.0
		away = away.normalized() if away.length() > 0.1 else Vector3.FORWARD
		var run := away * FLEE_SPEED
		_yaw = lerp_angle(_yaw, atan2(run.x, run.z), 1.0 - exp(-FLEE_TURN * delta))
		velocity.x = move_toward(velocity.x, run.x, FLEE_ACCEL * delta)
		velocity.z = move_toward(velocity.z, run.z, FLEE_ACCEL * delta)
		velocity.y = -0.5 if is_on_floor() else velocity.y - GRAVITY * delta
		_slide(delta)
		_visual.rotation.y = _yaw
		_visual.speed = Vector3(velocity.x, 0, velocity.z).length()
		_visual.on_floor = true
		_visual.waving = false
		if _flee_t <= 0.0:
			_label.visible = false
		return
	# --- pozdrav
	var in_car: bool = player != null and player.car != null
	if dist < GREET_R and _talk_cool <= 0.0 and _talk <= 0.0 and not in_car:
		_talk = GREET_S
		_talk_len = _talk
		_talk_cool = GREET_CD
		_label.text = Dialog.greet(world.dialog_context(int(player.get("id")), self))
		_label.visible = true
	var desired := Vector3.ZERO
	# --- Fáze 3: behavior strom zvolí cíl pohybu (_bt_target_pos); cíle se plní líně z herních dat
	if _bt_inst != null:
		_bt_fill_vars()
		_bt_inst.update(delta)
	if _talk > 0.0:
		_talk -= delta
		_yaw = lerp_angle(_yaw, atan2(to_player.x, to_player.z), 1.0 - exp(-TALK_TURN * delta))
		_visual.waving = _talk > _talk_len - WAVE_S
		if _talk <= 0.0:
			_label.visible = false
			_visual.waving = false
	elif _wait > 0.0:
		_wait -= delta
		if dist < WAIT_R:
			_yaw = lerp_angle(_yaw, atan2(to_player.x, to_player.z), 1.0 - exp(-WAIT_TURN * delta))
		else:
			_wait = 0.0     # hráč zatím odešel daleko, nečekej nadarmo
	elif _pause > 0.0:
		_pause -= delta
	else:
		if _bt_target_pos != Vector3.INF:
			# cíl z behavior stromu (Fáze 3): jdi po naplánované trase po silnicích
			desired = _bt_step()
		else:
			var goal := _goal()
			var d := Vector2(goal.x - global_position.x, goal.y - global_position.z)
			if d.length() < ARRIVE_R:
				_advance()
			else:
				desired = Vector3(d.x, 0, d.y).normalized() * _speed
		if desired.length() > 0.1:
			# neprojít skrz hráče
			if dist < AVOID_R and to_player.normalized().dot(desired.normalized()) > 0.5:
				desired = Vector3.ZERO
			_yaw = lerp_angle(_yaw, atan2(desired.x, desired.z), 1.0 - exp(-WALK_TURN * delta)) \
				if desired.length() > 0.1 else _yaw

	if dist > PHYSICS_RANGE:
		# daleko: kinematicky po terénu
		global_position += desired * delta
		global_position.y = terrain.height_at(global_position.x, global_position.z)
		velocity = desired
	else:
		velocity.x = move_toward(velocity.x, desired.x, WALK_ACCEL * delta)
		velocity.z = move_toward(velocity.z, desired.z, WALK_ACCEL * delta)
		if is_on_floor():
			velocity.y = -0.5
		else:
			velocity.y -= GRAVITY * delta
		_slide(delta)
		# zaseknutý (plot, strom, hráč) → otočit se
		if desired.length() > 0.1 and Vector3(velocity.x, 0, velocity.z).length() < STUCK_V:
			_stuck += delta
			if _stuck > STUCK_S:
				_stuck = 0.0
				if _plan_inside and _bt_target_pos != Vector3.INF \
						and global_position.distance_to(_bt_target_pos) < ENTER_NEAR_R:
					_enter_house(_bt_target_pos)       # M8.17: u vlastních dveří zaseknutý (plot) – prostě zajde dovnitř
					return
				if _bt_target_pos != Vector3.INF:
					# zaseknutý cestou za cílem z BT → přeskoč bod a naplánuj trasu znovu odsud;
					# po BT_STUCK_MAX zaseknutích cíl vzdej (replan jinak vrací přeskočení na začátek)
					_bt_stuck_n += 1
					if _bt_stuck_n >= BT_STUCK_MAX:
						_bt_giveup_pos = _bt_target_pos
						_bt_giveup_until = Time.get_ticks_msec() + int(BT_GIVEUP_S * 1000.0)
						clear_target()
						_bt_stuck_n = 0
					else:
						_bt_path_i += 1
						_bt_replan()
				else:
					var t := _next
					_next = _cur
					_cur = t
					_side = -_side
		else:
			_stuck = 0.0
		if global_position.y < terrain.height_at(global_position.x, global_position.z) - 3.0:
			global_position.y = terrain.height_at(global_position.x, global_position.z) + 0.5

	_visual.rotation.y = _yaw
	_visual.speed = Vector3(velocity.x, 0, velocity.z).length()
	_visual.on_floor = true
	_visual.drunk = clampf(promile / DRUNK_FULL_PROMILE, 0.0, 1.0)   # Fáze 3: potácení podle promile


## Pohyb hluboce uspaného vesničana (za simulační bublinou): posun po grafu / trase BT jedním
## velkým krokem – bez kolizí, zdravení, mávání a vizuálních animací (postava je schovaná).
func _deep_step(delta: float) -> void:
	if _bt_inst != null:
		_bt_fill_vars()
		_bt_inst.update(delta)
	var desired := Vector3.ZERO
	if _pause > 0.0:
		_pause -= delta
	elif _bt_target_pos != Vector3.INF:
		desired = _bt_step()
	else:
		var goal := _goal()
		var d := Vector2(goal.x - global_position.x, goal.y - global_position.z)
		if d.length() < ARRIVE_R:
			_advance()
		else:
			desired = Vector3(d.x, 0, d.y).normalized() * _speed
	if desired.length() > 0.1:
		_yaw = atan2(desired.x, desired.z)
	global_position += desired * delta
	global_position.y = terrain.height_at(global_position.x, global_position.z)
	velocity = desired


func _goal() -> Vector2:
	var a := graph.nodes[_cur]
	var b := graph.nodes[_next]
	var dir := (b - a).normalized()
	# na silnici při krajnici, na pěšině / polní cestě uprostřed
	var side := _side if graph.edge(_cur, _next) in RoadGraph.CAR_KINDS else signf(_side) * PATH_SIDE_K
	return b + Vector2(-dir.y, dir.x) * side


func _advance() -> void:
	var nxt := graph.next_node(_next, _cur, rng)
	_prev = _cur
	_cur = _next
	_next = nxt
	if rng.randf() < PAUSE_P:
		_pause = rng.randf_range(PAUSE_MIN, PAUSE_MAX)


## Rozhovor (E): drb z vesnice.
func talk() -> String:
	var p: Player = world.nearest_player(global_position)
	var t: String = Dialog.rumor(world.dialog_context(int(p.get("id")), self)) if p else "Dobrý den."
	say(t, 4.5)
	return t


## Řekne něco (bublina nad hlavou) – zastaví se a otočí k hráči. Délka podle délky textu.
func say(text: String, dur := -1.0) -> void:
	if _knocked > 0.0:
		return
	_talk = dur if dur > 0.0 else clampf(SAY_BASE_S + text.length() / SAY_CHARS_PER_S, SAY_MIN_S, SAY_MAX_S)
	_talk_len = _talk
	_talk_cool = maxf(_talk_cool, SAY_CD)
	_label.text = text
	_label.visible = true


## Hráč otevřel řádek na promluvu (T) – postůj poblíž, ať má čas dopsat a odeslat.
func wait_for_reply(dur := 20.0) -> void:
	if _knocked > 0.0 or _flee_t > 0.0:
		return
	_wait = maxf(_wait, dur)


func is_knocked() -> bool:
	return _knocked > 0.0


## Uteč pryč od `src` na `dur` s (vesničan se leknul střelby; M2.8).
func flee_from(src: Vector3, dur := 8.0) -> void:
	if _knocked > 0.0:
		return
	_flee_from = src
	_flee_t = dur
	_talk = 0.0
	_pause = 0.0


## Sražení autem.
func knock(vel: Vector3, spd: float) -> void:
	_knocked = KNOCK_S + spd * KNOCK_PER_V
	velocity = vel
	_visual.pose = "lie"
	_visual.waving = false
	_talk = 0.0
	_label.text = "Au!! Ty blázne!"
	_label.visible = true
