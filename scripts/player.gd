## Hráč: CharacterBody3D s "arkádově-realistickou" fyzikou pohybu + simulace těla (alkohol, jídlo, cigarety).
## - zrychlení / brzdění s různou odezvou na zemi a ve vzduchu, rychlé otočení
## - skok s proměnnou výškou, coyote time, jump buffer, těžší pád
## - sprint s výdrží, přikrčení (Ctrl/C), skluz ze sprintu, sjíždění z příkrých svahů
## - strkání do fyzikálních objektů, dopad s propružením kamery, zranění pádem z výšky
## - opilost: zpožděné reakce, drift do stran, potácení kamery, zakopnutí a pád, zvracení, okno
## - obezita zpomaluje a snižuje výdrž, kouření snižuje výdrž (dehet v plicích)
## - inventář (lahve, jídlo, cigarety), peníze; konzumace s animací (pití, jídlo, kouření)
## - nastupování do auta (postava sedí za volantem, kameru přebírá auto), jízda na koni (Horse)
## - počasí: mokro/sníh/náledí zmenší přilnavost podrážek, déšť a vítr promáčí a chladí (BodyState)
## - vizuál i kamera se interpolují mezi fyzikálními kroky → plynulý obraz při libovolném FPS
## - vstup čte jen ze struktury `input` (InputState) – plní ji LocalClient, v MP síť;
##   kameru má jen lokální hráč (`make_local()`), vzdálený hráč by ji neměl
class_name Player
extends CharacterBody3D

signal jumped
signal landed(impact: float)
signal game_event(kind: String, data: Dictionary)

## Třes obrazu (abstinence od cigaret, zima) – laditelné hodnoty. Amplitudy v radiánech (náklon pohledu).
const SHAKE_WITHDRAWAL_MIN := 0.6    # od jaké hodnoty `craving × addiction` třes začne
const SHAKE_WITHDRAWAL_AMP := 0.0009 # nejvyšší amplituda třesu z abstinence
const SHAKE_FIT_PERIOD := 60.0       # s – záchvat třesu se opakuje jednou za tuto dobu
const SHAKE_FIT_LEN := 5.0           # s – délka záchvatu
const SHAKE_COLD_MIN := 0.3          # od jaké úrovně prochladnutí (body.cold) se třese
const SHAKE_COLD_AMP := 0.003        # amplituda při plném prochladnutí
const SHAKE_COLD_MAX := 0.003        # pevný strop třesu zimou
const SHAKE_FREQ := 9.0              # rychlost chvění (vstup do šumu: _t × tato hodnota)

@export var walk_speed := 4.6
@export var sprint_speed := 8.4
@export var crouch_speed := 2.2
@export var ground_accel := 48.0
@export var ground_decel := 38.0
@export var turn_accel := 80.0
@export var air_accel := 11.0
@export var jump_velocity := 6.6
@export var gravity := 20.0
@export var fall_multiplier := 1.55
@export var low_jump_multiplier := 2.3
@export var coyote_time := 0.13
@export var jump_buffer_time := 0.14
@export var slide_boost := 1.8
@export var slide_friction := 3.2
@export var mouse_sensitivity := 0.0024
var shake_enabled := true       # třes obrazu zapnut (Esc → Nastavení → Třes obrazu)
var base_fov := 72.0             # základní zorné pole (Esc → Nastavení)

const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.1
const RADIUS := 0.30          # kapsle Ø 0,6 m – s rezervou projde dveřmi interiérů (0,8–0,9 m) a mezi nábytkem
const FRAGILE := ["pivo", "nealko", "vino_bile", "vino_cervene", "slivovice", "vodka", "rum", "becherovka", "voda"]

var id := 1                      # id hráče ve světě (World.players); lokální hráč = 1
var input := InputState.new()
var stamina := 1.0
var first_person := false
var yaw := 0.0
var pitch := -0.25
var spawn_point := Vector3.ZERO
var spawn_yaw := 0.0

var body: BodyState
var weather: Weather             # přiřazuje World.add_player – déšť/vítr na těle, kluzký povrch
var inventory := {}              # id → počet (cigarety = kusy)
var open_ml := {}                # id → zbývá ml v otevřené lahvi
var durability := {}             # id → zbývá použití aktuálního kusu nástroje (M0.2)
var equipped := ""               # předmět typu tool / weapon v ruce, "" = prázdné ruce (M0.4)
var overloaded := false          # nese víc než CARRY_KG: pomalejší chůze, žádný sprint
var money := 1500
var car: Car = null
var horse: Horse = null          # kůň, na kterém hráč jede (kameru a pohyb přebírá kůň)
var drone: Drone = null          # M6.1: dron, který hráč právě pilotuje (kameru přebírá dron)
var aircraft: Aircraft = null    # M6.3: letoun, ve kterém hráč sedí (kameru a pohyb přebírá letoun)
var controls_locked := false
var inside := ""                   # id interiéru, ve kterém hráč právě je (World.enter_interior), "" = venku
var busy := false                # probíhá konzumace / zvracení
var fallen := 0.0                # > 0: leží na zemi (s)
var heat := 0.0                  # teplo od ohně / kamen 0..1 (nastavuje FireManager; sušení a zahřátí v BodyState)
var shelter_min := 18.0          # nejnižší pocitová teplota pod střechou / uvnitř (°C; doma bez topení nižší, FireManager)
var license_suspended_until := -1.0   # zákaz řízení do (herní minuty)
var wanted_until := -1.0              # hledaný policií do (herní minuty)
var wade := 0.0                       # hloubka vody, ve které hráč stojí (m) – nastavuje Water
var scope_on := false                 # drží dalekohled (X) – nastavuje LocalClient
var scope := 0.0                      # 0..1 zapnutí dalekohledu (plynule), zužuje zorný úhel kamery
var outfit := {}                       # oblečení: slot → id předmětu (M2.3, `Wardrobe`); ukládá se
var bank := 0                          # M3.4: zůstatek na účtu (Moje banka, `Computer`); hotovost je `money`; ukládá SaveGame (klíč pc)
## Má na sobě kuklu (úkol Med) – včely nebodají. Od M2.3 je kukla kus oblečení (štítek `vcelar`); přiřazení ji navlékne / sundá.
var beekeeper_suit: bool:
	get:
		return Wardrobe.has_tag(outfit, "vcelar")
	set(v):
		Wardrobe.set_beekeeper(self, v)
# --- skateboard (M5.7): režim pohybu – deska pod nohama, `board_on`; jízdu řeší `_board_step`
const BOARD_PUSH := 1.5                 # m/s – přídavek rychlosti jedním odrazem (W)
const BOARD_PUSH_CD := 0.45             # s – minimální rozestup odrazů
const BOARD_MAX_FLAT := 6.0             # m/s – nejvyšší rychlost odrazem po rovině (z kopce víc)
const BOARD_DRAG := 0.35                # m/s² – valivý odpor na asfaltu
const BOARD_BRAKE := 7.0                # m/s² – brzda patou (S)
const BOARD_TURN := 1.9                 # rad/s – zatáčení (A/D) při plné rychlosti
const BOARD_G := 9.8                    # m/s² – gravitace pro jízdu z kopce
const BOARD_OLLIE_VY := 3.2             # m/s – vertikální rychlost ollie (~0,5 m)
const BOARD_OLLIE_PTS := 10             # body za čistý ollie (dopad rovně)
const BOARD_WOBBLE_V := 12.0            # m/s – od této rychlosti deska kmitá
const BOARD_FALL_V := 15.0              # m/s – nad touto rychlostí pád
const BOARD_WALL_V := 3.0               # m/s – náraz do zdi nad touto rychlostí = pád
var board_on := false                   # hráč stojí na skateboardu
var board_score := 0                    # body z aktuální jízdy (ollie)
var board_best := 0                     # rekord (ukládá SaveGame, klíč skate)
var _board_push_cd := 0.0
var _board_jump_prev := false
var _board_air := 0.0                   # s ve vzduchu od ollie (pro bodování dopadu)
var _board_node: Node3D

const SCOPE_FOV := 12.0               # zorný úhel dalekohledu (°)
const SCOPE_SENS := 0.22              # citlivost myši v dalekohledu (násobek)
# M2.8 míření se zbraní (pravé tlačítko): `Weapons` nastavuje `aim_on` / `aim_fov` / `aim_optic` / `aim_sway` / `weapon_status`
var aim_on := false                   # míří se zbraní v ruce
var aim_k := 0.0                      # 0..1 plynulé přiblížení kamery při míření
var aim_fov := 45.0                   # zorný úhel při míření (°; zbraň s optikou jde přes `scope` jako dalekohled)
var aim_optic := false                # zbraň s optikou: míření zapne přiblížení jako dalekohled
var aim_sway := Vector2.ZERO          # kolísání mušky (rad: x doleva, y nahoru) – přičítá se k pohledu kamery
var weapon_status := ""               # text o zásobníku / nabíjení pro HUD (Weapons)
const AIM_SENS := 0.6                 # citlivost myši při míření bez optiky (násobek)
const AIM_SPEED_MULT := 0.45          # rychlost chůze při míření

var _shape: CapsuleShape3D
var _col: CollisionShape3D
var _coyote := 0.0
var _jump_buffer := 0.0
var _stamina_lock := false
var _stamina_delay := 0.0
var _crouching := false
var _sliding := false
var _slide_time := 0.0
var _was_on_floor := true
var _prev_vy := 0.0
var _air_top_y := 0.0            # nejvyšší bod od posledního kontaktu se zemí (výška pádu)
const SAFE_FALL_HEIGHT := 6.0     # pád do 6 m je bez následků
var _void_fall_t := 0.0           # s propadávání beze dna (chybná pozice po výstupu z interiéru apod.)
const FALL_RECOVER_T := 1.2       # tak dlouho padat rychlostí FALL_RECOVER_VY bez zastavení → vrátit na povrch
const FALL_RECOVER_VY := -25.0    # m/s – běžný skok / seskok takhle rychle nepadá, jen opravdový propad terénem
var _prev_pos := Vector3.ZERO
var _cur_pos := Vector3.ZERO
var _visual_yaw := 0.0
var _land_dip := 0.0
var _bob := 0.0
var _zoom := 4.2
var _arm_len := 4.2
var _t := 0.0
var _noise := FastNoiseLite.new()
var _shake_noise := FastNoiseLite.new()   # hladký šum pro třes obrazu (abstinence, zima)
var _input_hist: Array = []
var _stumble_cool := 2.0
var _action := ""
var _action_item := ""
var _action_ml := 0.0
var _action_t := 0.0
var _action_len := 0.0
var _smoke_t := 0.0
var _wall_bump_cool := 0.0
var _exit_settle := 0             # fyzikální kroky po výstupu z vozidla, než se zapne kolize
var _say_label: Label3D           # co hráč řekl (T) – bublina nad hlavou, vidí ji ostatní
var _say_t := 0.0
var _floor_surf := "teren"        # povrch pod nohama (meta "surface" z kolize)
var _safe_pos := Vector3.INF      # poslední místo, kde hráč stál volně (podlaha, žádný dotyk zdi) – záchrana při zaseknutí (U)
var _safe_yaw := 0.0
var _roof := false                # je nad hráčem střecha / strop (raycast)
var _roof_t := 0.0
var _msg_wet := false             # hláška "jsi promoklý" už šla
var _msg_cold := false            # hláška "prochladl jsi" už šla

var visual: Humanoid
var rig: Node3D                  # kamera – jen lokální hráč
var arm: SpringArm3D
var camera: Camera3D


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 4 | 8 | 16
	floor_max_angle = deg_to_rad(46.0)
	floor_snap_length = 0.45
	floor_constant_speed = true
	floor_block_on_wall = true
	max_slides = 6
	safe_margin = 0.02
	_shape = CapsuleShape3D.new()
	_shape.radius = RADIUS
	_shape.height = STAND_HEIGHT
	_col = CollisionShape3D.new()
	_col.shape = _shape
	_col.position.y = STAND_HEIGHT * 0.5
	add_child(_col)
	_noise.frequency = 0.35
	_noise.seed = 122
	_shake_noise.seed = 77
	_shake_noise.frequency = 1.0

	body = BodyState.new()
	body.name = "Telo"
	add_child(body)
	body.vomited.connect(_on_vomit)
	body.injured.connect(func(a: float, r: String): game_event.emit("injured", {"amount": a, "reason": r}))

	visual = Humanoid.new()
	visual.hair = Color(0.3, 0.2, 0.12)
	visual.moustache = true
	visual.top_level = true
	Wardrobe.setup_player(self)       # výchozí oblečení (triko, džíny, polobotky = dřívější vzhled), izolace těla
	add_child(visual)
	_say_label = Label3D.new()
	_say_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_say_label.position = Vector3(0, 2.25, 0)
	_say_label.font_size = 40
	_say_label.outline_size = 10
	_say_label.modulate = Color(0.85, 1.0, 0.85)
	_say_label.width = 700.0
	_say_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_say_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM   # delší text roste nahoru
	_say_label.visible = false
	visual.add_child(_say_label)
	_prev_pos = global_position
	_cur_pos = global_position


## Kamera za hráčem / z očí – jen pro hráče, kterého ovládá tento počítač.
func make_local() -> void:
	if camera:
		return
	rig = Node3D.new()
	rig.top_level = true
	add_child(rig)
	arm = SpringArm3D.new()
	arm.collision_mask = 1
	arm.margin = 0.15
	var s := SphereShape3D.new()
	s.radius = 0.2
	arm.shape = s
	arm.add_excluded_object(get_rid())
	rig.add_child(arm)
	camera = Camera3D.new()
	camera.fov = 72.0
	camera.near = 0.08
	camera.far = 9000.0
	arm.add_child(camera)
	camera.current = true


func teleport(pos: Vector3, face_yaw: float, set_spawn := true) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	_air_top_y = pos.y
	_prev_pos = pos
	_cur_pos = pos
	yaw = face_yaw
	_visual_yaw = face_yaw + PI
	_safe_pos = pos
	_safe_yaw = face_yaw
	if set_spawn:
		spawn_point = pos
		spawn_yaw = face_yaw


## Nouzová pojistka (M0+): propadne-li hráč terénem (chybná pozice po výstupu z interiéru, díra v kolizi…),
## dlouhé volné pádění (FALL_RECOVER_T s) ho vrátí na skutečný povrch v jeho vodorovné poloze.
func _recover_from_void() -> void:
	var w := get_parent() as World
	if w == null or w.terrain == null:
		return
	if inside != "":
		# v interiéru je terén pod mapou – na povrch bychom hráče vyhodili pod / nad dům; vrátíme ho ke dveřím
		var it: Interior = w.interiors.get(inside)
		push_warning("Hráč %d propadl v interiéru '%s' (pozice %s, rychlost %s, interiér postaven: %s) – vracím ke dveřím." % [
			id, inside, str(global_position), str(velocity), str(it != null and is_instance_valid(it))])
		if it != null and is_instance_valid(it):
			teleport(it.inside_door, it.inside_yaw, false)
		else:
			w.exit_interior(id, false)        # interiér už neexistuje → ven před dveře
		w.notify(id, "show_message", ["Propadl ses podlahou – vrátil jsem tě ke dveřím.", 3.5])
		return
	var gy := w.terrain.height_at(global_position.x, global_position.z) + 0.3
	teleport(Vector3(global_position.x, gy, global_position.z), yaw, false)
	w.notify(id, "show_message", ["Propadl ses terénem – vrátil jsem tě zpátky na povrch.", 3.5])


## Nouzové vysvobození (klávesa U): přenese na poslední místo, kde hráč stál volně (na podlaze a bez dotyku
## se zdí – zachytává se ve fyzikálním kroku). Když tam teď překáží něco jiného, zkusí vchod interiéru,
## nakonec spawn (mimo interiér = nejdřív z něj odhlásit). Vrací hlášku pro HUD ("" = v autě / na koni).
func unstick() -> String:
	if car != null:
		return "V autě pomůže klávesa R (postavit vozidlo)."
	if aircraft != null:
		return "V letounu – nejdřív přistaň a vystup (F)."
	if horse != null:
		return "Na koni – kdyžtak sesedni (F)."
	var w := get_parent() as World
	var cands: Array = []           # [pozice, yaw, je venku mimo interiér]
	if _safe_pos != Vector3.INF and _safe_pos.distance_to(global_position) < 25.0:
		cands.append([_safe_pos, _safe_yaw, false])
	if inside != "" and w != null and w.interiors.has(inside):
		var it: Interior = w.interiors[inside]
		if it != null and is_instance_valid(it):
			cands.append([it.inside_door, it.inside_yaw, false])
	cands.append([spawn_point, spawn_yaw, true])
	var sh := CapsuleShape3D.new()
	sh.radius = RADIUS
	sh.height = STAND_HEIGHT
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sh
	q.collision_mask = 1 | 4 | 8 | 16
	q.exclude = [get_rid()]
	var space := get_world_3d().direct_space_state
	for cd in cands:
		var p3: Vector3 = cd[0]
		q.transform = Transform3D(Basis(), p3 + Vector3(0, STAND_HEIGHT * 0.5 + 0.05, 0))
		if not space.intersect_shape(q, 1).is_empty():
			continue
		if bool(cd[2]) and inside != "" and w != null:
			w.interior_clear(self)
		teleport(p3, float(cd[1]), false)
		return "Vysvobozeno ze zaseknutí – jsi zase na volném místě."
	return "Nevidím poblíž volné místo – zkus H (návrat domů)."


# ------------------------------------------------------------------ inventář a konzumace

## Nosnost (kg). Později podle dovednosti / kondice.
const CARRY_KG := 25.0
const OVERLOAD_SPEED_MULT := 0.6


## Celková hmotnost věcí v kapse (kg): součet hmotnost 1 ks × počet (otevřená lahev se počítá jako celá).
func carried_kg() -> float:
	var kg := 0.0
	for id in inventory:
		kg += ItemsDB.weight(id) * (int(inventory[id]) - (1 if Wardrobe.is_worn(outfit, id) else 0))   # navlečený kus nenosíš v kapse
	return kg


func _update_overload(warn: bool) -> void:
	var now := carried_kg() > CARRY_KG
	if now and not overloaded and warn:
		game_event.emit("overloaded", {})
	overloaded = now


## Přidá `n` kusů předmětu. Balení (předmět s polem `count` v katalogu, dnes krabička cigaret = 20 ks) se
## do inventáře rozbalí na jednotlivé kusy – nákup tedy dává `n × count` ks (A3-11: žádné skryté pravidlo
## jen pro jedno id, řídí to katalog).
func add_item(id: String, n := 1) -> void:
	n *= maxi(int(ItemsDB.info(id).get("count", 1)), 1) if ItemsDB.exists(id) else 1
	inventory[id] = int(inventory.get(id, 0)) + n
	_update_overload(true)


## Opotřebuje nástroj o `n` použití. Když se kus zničí, zmizí z inventáře a vrátí false.
func wear_tool(id: String, n := 1) -> bool:
	var max_d := int(ItemsDB.info(id).get("durability", 0)) if ItemsDB.exists(id) else 0
	if max_d <= 0 or item_count(id) <= 0:
		return true      # nemá životnost / nemáme ho
	var left := int(durability.get(id, max_d)) - n
	if left > 0:
		durability[id] = left
		return true
	durability.erase(id)
	remove_item(id)
	return false


func item_count(id: String) -> int:
	return int(inventory.get(id, 0))


## Počet napití, která zbývají (včetně otevřené lahve).
func sips_left(id: String) -> int:
	var info := Consumables.info(id)
	if info["type"] != "drink":
		return item_count(id)
	var sip: float = info["sip"]
	return int(float(open_ml.get(id, 0.0)) / sip + 0.01) + item_count(id) * int(float(info["ml"]) / sip + 0.01)


func remove_item(id: String, n := 1) -> bool:
	if item_count(id) < n:
		return false
	inventory[id] = item_count(id) - n
	if inventory[id] <= 0:
		inventory.erase(id)
		durability.erase(id)
	if id == equipped and item_count(id) <= 0:
		equip("")
	if ItemsDB.type_of(id) == "clothing" and item_count(id) <= 0:
		Wardrobe.refresh(self)          # ztracený / prodaný kus se svlékne
	_update_overload(false)
	return true


# ------------------------------------------------------------------ nástroj v ruce (M0.4)

## Nástroje a zbraně v inventáři v pořadí katalogu `ItemsDB` (rychlé sloty 1–5 = prvních pět).
func tool_ids() -> Array[String]:
	var out: Array[String] = []
	for id in ItemsDB.ITEMS:
		if item_count(id) > 0 and ItemsDB.type_of(id) in ["tool", "weapon"] and bool(ItemsDB.info(id).get("hold", true)):
			out.append(id)
	return out


## Vezme nástroj do ruky ("" = prázdné ruce). Vrací false, když ho hráč nemá.
func equip(id: String) -> bool:
	if id != "" and (item_count(id) <= 0 or not (id in tool_ids())):
		return false
	if id == equipped:
		return true
	equipped = id
	visual.set_tool(ToolModels.model_for(id) if id != "" else null)
	game_event.emit("equipped", {"id": id})
	return true


## Q: další nástroj v cyklu (prázdné ruce → 1. nástroj → … → prázdné ruce).
func equip_next() -> void:
	var list := tool_ids()
	if list.is_empty():
		equip("")
		return
	var i := list.find(equipped)      # -1 = prázdné ruce
	i += 1
	equip(list[i] if i < list.size() else "")


## 1–5: nástroj z rychlého slotu (stisk už drženého nástroje ho zase schová).
func equip_slot(n: int) -> void:
	var list := tool_ids()
	if n < 1 or n > 5 or n > list.size():
		return
	equip("" if list[n - 1] == equipped else list[n - 1])


## Text „Sekera (opotřebení 34/50)“ pro HUD; "" bez nástroje.
func equipped_text() -> String:
	if equipped == "":
		return ""
	if weapon_status != "":
		return weapon_status          # zbraň: zásobník a nabíjení (M2.8, `Weapons`)
	var max_d := int(ItemsDB.info(equipped).get("durability", 0))
	if max_d <= 0:
		return ItemsDB.name_of(equipped)
	var left := int(durability.get(equipped, max_d))
	return "%s (opotřebení %d/%d)" % [ItemsDB.info(equipped).get("short", equipped), max_d - left, max_d]


## Ubere výdrž (akce); po dobu akce se výdrž nedobíjí.
## Modifikátory rychlosti pohybu: zdroj (např. "vozik", "rameno") → {walk_k: násobek chůze a sprintu (výchozí 1),
## no_sprint: bool (sprint zakázán), jump: strop rychlosti výskoku}. Žádný zdroj nesahá na `walk_speed` /
## `sprint_speed` (zůstávají výchozími `@export` hodnotami), takže se modifikátory nemohou „zaseknout“
## ani se obnovit v opačném pořadí (A3-06). Zdroj modifikátor sám nastaví a po skončení smaže.
var speed_mods: Dictionary = {}


func set_speed_mod(source: String, mod: Dictionary) -> void:
	speed_mods[source] = mod


func clear_speed_mod(source: String) -> void:
	speed_mods.erase(source)


func has_speed_mod(source: String) -> bool:
	return speed_mods.has(source)


## Součin `walk_k` všech modifikátorů.
func speed_mod_k() -> float:
	var k := 1.0
	for src in speed_mods:
		k *= float((speed_mods[src] as Dictionary).get("walk_k", 1.0))
	return k


func sprint_blocked() -> bool:
	for src in speed_mods:
		if bool((speed_mods[src] as Dictionary).get("no_sprint", false)):
			return true
	return false


## Efektivní rychlost chůze (výchozí `walk_speed` × modifikátory).
func effective_walk() -> float:
	return walk_speed * speed_mod_k()


## Efektivní rychlost sprintu (s `no_sprint` je rovna chůzi).
func effective_sprint() -> float:
	return effective_walk() if sprint_blocked() else sprint_speed * speed_mod_k()


## Efektivní rychlost výskoku (nejnižší strop `jump` z modifikátorů).
func effective_jump() -> float:
	var j := jump_velocity
	for src in speed_mods:
		var m: Dictionary = speed_mods[src]
		if m.has("jump"):
			j = minf(j, float(m["jump"]))
	return j


func drain_stamina(v: float) -> void:
	stamina = maxf(stamina - v, 0.0)
	_stamina_delay = 0.9


func is_stamina_locked() -> bool:
	return _stamina_lock


## Použije předmět z inventáře (napije se / sní / zapálí si). Vrací false, když nejde.
func use_item(id: String) -> bool:
	if ItemsDB.hidden(id):
		return false     # M4.8: obsah pro dospělé vypnutý – předmět ve hře není
	if busy or car != null or horse != null or aircraft != null or drone_flying() or fallen > 0.0:
		return false
	var info := Consumables.info(id)
	match info["type"]:
		"drink":
			var sip: float = info["sip"]
			if float(open_ml.get(id, 0.0)) < sip - 0.5:
				if not remove_item(id):
					return false
				open_ml[id] = float(info["ml"])
				game_event.emit("opened", {"id": id})
			open_ml[id] = float(open_ml[id]) - sip
			if float(open_ml[id]) < 0.5:
				open_ml.erase(id)
			_begin("drink", id, sip)
		"food":
			if not remove_item(id):
				return false
			_begin("eat", id, 0.0)
		"smoke":
			if not remove_item(id):
				return false
			_begin("smoke", id, 0.0)
	return true


## M4.8: ruční úprava z ItemsDB.RECIPES (ubalení, pečení). Vrací false, když chybí některý vstup.
func craft(id: String, recipe: Dictionary) -> bool:
	if not craft_ok(id, recipe):
		return false
	var need: Dictionary = recipe["need"]
	remove_item(id, 1)
	for k in need:
		remove_item(String(k), int(need[k]))
	add_item(String(recipe["out"]), 1)
	return true


func craft_ok(id: String, recipe: Dictionary) -> bool:
	if item_count(id) < 1:
		return false
	var need: Dictionary = recipe["need"]
	for k in need:
		if item_count(String(k)) < int(need[k]):
			return false
	return true


## Vypije / sní něco, co mu někdo podal (hospoda, degustace) – bez inventáře.
func consume_served(id: String) -> void:
	var info := Consumables.info(id)
	if info["type"] == "food":
		_begin("eat", id, 0.0)
	else:
		_begin("drink", id, float(info["ml"]))


func _begin(act: String, id: String, ml: float) -> void:
	busy = true
	_action = act
	_action_item = id
	_action_ml = ml
	_action_t = 0.0
	match act:
		"drink":
			_action_len = clampf(ml / 500.0 * 3.0, 1.0, 3.2)
			visual.hold(PropModels.drink_model(id))
			visual.start_action("drink")
			game_event.emit("sfx", {"name": "gulp", "delay": 0.6})
		"eat":
			_action_len = 2.4
			visual.hold(PropModels.food_model(id))
			visual.start_action("eat")
			game_event.emit("sfx", {"name": "eat", "delay": 0.3})
		"smoke":
			_action_len = 1.0
			visual.start_action("smoke")
			_smoke_t = 14.0
			var thc_s := float(Consumables.info(id).get("thc", 0.0))   # M4.8: konopí = THC, ostatní = nikotin
			if thc_s > 0.0:
				body.smoke_thc(thc_s)
			else:
				body.smoke()
			game_event.emit("sfx", {"name": "lighter"})
			game_event.emit("smoked", {"id": id})


func _finish_action() -> void:
	match _action:
		"drink":
			var g := body.drink(_action_item, _action_ml)
			game_event.emit("drank", {"id": _action_item, "ml": _action_ml, "g": g})
			if g > 12.0 and randf() < 0.3:
				game_event.emit("sfx", {"name": "burp"})
		"eat":
			body.eat(_action_item)
			game_event.emit("ate", {"id": _action_item})
	if _action != "smoke":
		visual.stop_action()
	busy = false
	_action = ""


func _on_vomit() -> void:
	busy = true
	_action = "vomit"
	_action_t = 0.0
	_action_len = 2.2
	visual.start_action("vomit")
	game_event.emit("sfx", {"name": "vomit"})
	game_event.emit("vomited", {})


## Sražení autem / náraz: odhodí a srazí k zemi.
func knock(vel: Vector3, spd: float) -> void:
	if car != null or aircraft != null:
		return
	velocity = vel
	# zranění roste s kinetickou energií (~v²): 15 km/h ≈ 7, 30 km/h ≈ 28, 50 km/h ≈ 77
	body.hurt(0.4 * spd * spd, "srážka s autem")
	if spd < 5.0:
		fall(1.2, "srazilo tě auto")
	else:
		fall(3.0 + spd * 0.1, "srazilo tě auto")


## Pád na zem (zakopnutí, sražení). Lahve v batohu se můžou rozbít.
func fall(duration: float, reason: String) -> void:
	if horse != null:
		dismount_horse()
	if fallen > 0.0 or car != null or aircraft != null:
		return
	fallen = duration
	visual.pose = "lie"
	if busy and _action != "smoke":
		visual.stop_action()
		busy = false
		_action = ""
	game_event.emit("fell", {"reason": reason})
	# rozbité lahve
	var hs := Vector3(velocity.x, 0, velocity.z).length()
	for id in FRAGILE:
		if item_count(id) > 0 and randf() < clampf(0.25 + hs * 0.08, 0.0, 0.85):
			remove_item(id)
			game_event.emit("bottle_broken", {"id": id})
			break


# ------------------------------------------------------------------ skateboard (M5.7)

## Stoupnutí na skateboard (F, když hráč nic nejede). Deska zůstává v inventáři.
func board_mount() -> bool:
	if board_on or item_count("skateboard") <= 0 or car != null or horse != null or aircraft != null or busy or fallen > 0.0:
		return false
	board_on = true
	_board_air = 0.0
	_board_jump_prev = true                # Mezerník, kterým se stoupá, neudělá hned ollie
	_board_build()
	_board_node.visible = true
	visual.pose = "stand"
	return true


## Seskok (F). Při rychlosti nad 2 m/s hlídá volání (World) – tady jen sundání desky.
func board_dismount() -> void:
	board_on = false
	if _board_node:
		_board_node.visible = false
	velocity.x = 0.0
	velocity.z = 0.0


func _board_build() -> void:
	if _board_node != null:
		return
	_board_node = Node3D.new()
	_board_node.top_level = true
	add_child(_board_node)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.72, 0.52, 0.28)
	wood.roughness = 0.7
	var wheel := StandardMaterial3D.new()
	wheel.albedo_color = Color(0.93, 0.9, 0.82)
	wheel.roughness = 0.5
	var deck := MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(0.2, 0.015, 0.8)     # deska 80 × 20 cm (šířka 20 cm, délka 80 cm)
	deck.mesh = dm
	deck.material_override = wood
	deck.position = Vector3(0, 0.07, 0)
	_board_node.add_child(deck)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var w := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.03
			cm.bottom_radius = 0.03
			cm.height = 0.035
			w.mesh = cm
			w.material_override = wheel
			w.rotation_degrees = Vector3(0, 0, 90)
			w.position = Vector3(sx * 0.09, 0.03, sz * 0.27)
			_board_node.add_child(w)
	_board_node.visible = false


## Jízda: W = odraz, S = brzda, A/D = zatáčení, Mezerník = ollie, F = seskok (řeší World).
func _board_step(delta: float) -> void:
	var inp := _read_input()
	var move_in: Vector2 = inp[0]
	var jump_edge: bool = bool(inp[3]) and not _board_jump_prev
	_board_jump_prev = bool(inp[3])
	var on_floor := is_on_floor()
	_board_push_cd = maxf(_board_push_cd - delta, 0.0)
	# zatáčení podle rychlosti (stojící deska se netočí)
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var spd := hv.length()
	if not controls_locked and absf(move_in.x) > 0.05:
		yaw -= move_in.x * BOARD_TURN * clampf(spd / 2.5, 0.0, 1.0) * delta
	var fwd := Basis(Vector3.UP, yaw) * Vector3.FORWARD
	var right := Basis(Vector3.UP, yaw) * Vector3.RIGHT
	var s := hv.dot(fwd)                   # rychlost ve směru desky
	var lat := hv - fwd * s                # boční skluz se rychle utlumí (deska nejede do stran)
	lat = lat.move_toward(Vector3.ZERO, 8.0 * delta)
	var grip := _ground_traction()
	var acc := 0.0
	if on_floor:
		var n := get_floor_normal()
		var g_t := Vector3(0.0, -BOARD_G, 0.0) - n * Vector3(0.0, -BOARD_G, 0.0).dot(n)
		acc += g_t.dot(fwd)                # svah: z kopce zrychluje, do kopce zpomaluje
		var drag := BOARD_DRAG + (1.0 - grip) * 6.0    # mokro / tráva brzdí víc
		if absf(s) > 0.02:
			acc -= signf(s) * drag
		if move_in.y > 0.1:                # S = brzda patou
			acc -= (signf(s) * BOARD_BRAKE if absf(s) > 0.02 else 0.0)
		if move_in.y < -0.1 and _board_push_cd <= 0.0 and s < BOARD_MAX_FLAT:
			s += BOARD_PUSH * clampf(grip, 0.3, 1.0)
			_board_push_cd = BOARD_PUSH_CD
		s += acc * delta
		if absf(s) < 0.05 and absf(acc) < 0.5:
			s = 0.0
		# jednou za čas kmitne jen při vysoké rychlosti
		if absf(s) > BOARD_WOBBLE_V:
			lat += right * sin(_t * 14.0) * 1.6 * delta
		# jízda po nerovném povrchu (tráva, bahno, mokro): přepadneš dopředu
		if absf(s) > 2.5 and grip < 0.45:
			board_dismount()
			fall(1.2, "pad_skate")
			return
		velocity.y = minf(velocity.y, 0.0)
		_board_air = 0.0
	else:
		_board_air += delta
	if jump_edge and on_floor and fallen <= 0.0 and not busy:
		velocity.y = BOARD_OLLIE_VY
		_board_air = 0.0001
	elif not on_floor:
		velocity.y = maxf(velocity.y - gravity * delta, -55.0)
	if absf(s) > BOARD_FALL_V:
		board_dismount()
		fall(1.5, "pad_skate")
		return
	velocity.x = fwd.x * s + lat.x
	velocity.z = fwd.z * s + lat.z
	var was_air := _board_air
	var sprev := absf(s)
	_prev_vy = velocity.y
	move_and_slide()
	# náraz do zdi nebo obrubníku rychlostí = pád
	if is_on_wall() and sprev > BOARD_WALL_V:
		board_dismount()
		fall(1.5, "pad_skate")
		return
	# čistý ollie: dopad rovně, deska pod nohama (natočení dopadu do 25°)
	if not on_floor and is_on_floor() and was_air > 0.2:
		if get_floor_normal().angle_to(Vector3.UP) < deg_to_rad(25.0):
			board_score += BOARD_OLLIE_PTS
			board_best = maxi(board_best, board_score)
			game_event.emit("skate_trick", {"name": "ollie", "pts": BOARD_OLLIE_PTS, "score": board_score})
	_update_body(delta, absf(s))
	_board_node.global_transform = Transform3D(Basis(Vector3.UP, yaw), global_position)
	_prev_pos = global_position
	_cur_pos = global_position
	if is_on_floor():
		_air_top_y = global_position.y


# ------------------------------------------------------------------ auto

func enter_car(c: Car) -> void:
	car = c
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	_col.disabled = true
	if busy and _action != "smoke":
		visual.stop_action()
		busy = false
		_action = ""
	visual.top_level = false
	visual.reparent(c.vis, false)
	visual.position = c.seat_pos
	visual.rotation = Vector3.ZERO
	visual.ride = c.model.rider
	visual.pose = "ride"
	visual.speed = 0.0
	visual.on_floor = true
	visual.set_first_person(false)
	c.set_player_driver(self)


func exit_car() -> Vector3:
	var c := car
	var pos := _exit_spot(c)
	c.clear_driver()
	car = null
	visual.reparent(self, false)
	visual.top_level = true
	visual.pose = "stand"
	visual.set_first_person(first_person)
	# kolize až po dvou fyzikálních krocích: kinematické těleso se přesune až v kroku fyziky,
	# se zapnutou kolizí by jeho kapsle „prolétla“ z místa uvnitř auta ven a vystřelila auto
	# do země (auto propadlo terénem a srazilo hráče)
	_exit_settle = 2
	var cy := c.global_transform.basis.z
	teleport(pos, atan2(-cy.x, -cy.z), false)
	if camera:
		camera.current = true
	return pos


## Volné místo vedle vozidla: u dveří řidiče (vlevo), vpravo, za a před vozem, nakonec na střeše.
## Výška podle země pod bodem (svah, obrubník), kapsle nesmí zasahovat do zdi, auta ani věcí.
func _exit_spot(c: Car) -> Vector3:
	var space := get_world_3d().direct_space_state
	var hw := c.model.half_width
	var hl := c.model.length * 0.5
	var sh := CapsuleShape3D.new()
	sh.radius = RADIUS
	sh.height = STAND_HEIGHT
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sh
	q.collision_mask = 1 | 4 | 8 | 16
	q.exclude = [get_rid()]
	var cands: Array[Vector3] = [Vector3(hw + 0.55, 0, 0.1), Vector3(-hw - 0.55, 0, 0.1),
		Vector3(hw + 1.1, 0, 0.1), Vector3(-hw - 1.1, 0, 0.1), Vector3(0, 0, -hl - 0.7),
		Vector3(0, 0, hl + 0.7), Vector3(hw + 0.6, 0, -hl * 0.7), Vector3(-hw - 0.6, 0, hl * 0.7)]
	for lp in cands:
		var p := c.global_transform * lp
		var ray := PhysicsRayQueryParameters3D.create(p + Vector3(0, 2.5, 0), p - Vector3(0, 3.0, 0), 1)
		ray.exclude = [c.get_rid()]
		var hit := space.intersect_ray(ray)
		if hit.is_empty():
			continue
		p = hit["position"] + Vector3(0, 0.08, 0)
		if hit["position"].y > c.global_position.y + 1.2:
			continue         # vyvýšená hrana / zeď – tam ne
		q.transform = Transform3D(Basis(), p + Vector3(0, STAND_HEIGHT * 0.5 + 0.05, 0))
		if space.intersect_shape(q, 1).is_empty():
			return p
	return c.global_transform * Vector3(0, c.model.height + 0.3, 0)


# ------------------------------------------------------------------ letoun (M6.3)

## Nastoupení do letouna: postava sedne do sedačky, kolize a kameru přebírá stroj (vzor Car).
func enter_aircraft(a: Aircraft) -> void:
	aircraft = a
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	_col.disabled = true
	if busy and _action != "smoke":
		visual.stop_action()
		busy = false
		_action = ""
	visual.top_level = false
	visual.reparent(a.vis, false)
	visual.position = a.seat_pos
	visual.rotation = Vector3(0.0, PI, 0.0)        # Humanoid kouká do +Z, letouny letí do −Z (A2-05)
	visual.ride = a.rider                          # vlastní póza stroje (A2-08), ne zbytek z auta
	visual.pose = "ride"
	visual.speed = 0.0
	visual.on_floor = true
	visual.set_first_person(false)
	a.set_pilot(self)


## Vystoupení vedle stroje (jen když stojí na zemi – hlídá World.exit_aircraft). Vrací místo.
func exit_aircraft() -> Vector3:
	var a := aircraft
	a._xp_flush()                                  # dopíše XP za nalétané metry
	var pos := _aircraft_exit_spot(a)
	a.clear_pilot()
	aircraft = null
	visual.reparent(self, false)
	visual.top_level = true
	visual.rotation = Vector3.ZERO
	visual.ride = {}
	visual.pose = "stand"
	visual.set_first_person(first_person)
	_exit_settle = 2
	teleport(pos, a._yaw + PI * 0.5, false)
	if camera:
		camera.current = true
	return pos


## Volné místo vedle letouna (bok, předek, záď); výška podle terénu, kapsle nesmí jít do překážky.
func _aircraft_exit_spot(a: Aircraft) -> Vector3:
	var space := get_world_3d().direct_space_state
	var sh := CapsuleShape3D.new()
	sh.radius = RADIUS
	sh.height = STAND_HEIGHT
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sh
	q.collision_mask = 1 | 4 | 8 | 16
	q.exclude = [get_rid(), a.get_rid()]
	for lp in [Vector3(1.6, 0, 0), Vector3(-1.6, 0, 0), Vector3(0, 0, -2.2), Vector3(0, 0, 2.4)]:
		var p: Vector3 = a.global_transform * lp
		var w := get_parent() as World
		if w and w.terrain:
			p.y = w.terrain.height_at(p.x, p.z) + 0.08
		q.transform = Transform3D(Basis(), p + Vector3(0, STAND_HEIGHT * 0.5 + 0.05, 0))
		if space.intersect_shape(q, 1).is_empty():
			return p
	return a.global_position + Vector3(0, 2.0, 0)


## Letí letoun? (v autě-ekvivalentním smyslu „řídí se“ – pro HUD a stisky akcí)
func aircraft_flying() -> bool:
	return aircraft != null and not aircraft.on_ground


# ------------------------------------------------------------------ kůň

func mount_horse(h: Horse) -> void:
	horse = h
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	_col.disabled = true
	if busy and _action != "smoke":
		visual.stop_action()
		busy = false
		_action = ""
	visual.top_level = false
	visual.reparent(h.rider_mount_point(), false)
	visual.position = Vector3(0, -0.48, 0)
	visual.rotation = Vector3.ZERO
	visual.pose = "ride"
	visual.speed = 0.0
	visual.on_floor = true
	h.set_rider(self)


## Sesednutí vlevo od koně (nebo jinam, kde je místo). Vrací místo, kam hráč sesedl.
func dismount_horse() -> Vector3:
	var h := horse
	var pos := h.dismount_spot()
	h.clear_rider()
	horse = null
	visual.reparent(self, false)
	visual.top_level = true
	visual.pose = "stand"
	visual.set_first_person(first_person)
	_exit_settle = 2
	teleport(pos, h.yaw + PI, false)
	if camera:
		camera.current = true
	return pos


# ------------------------------------------------------------------ vstup (z InputState)

## Pilotuje dron? (drží vysílačku – nestojí/nepohne se, kameru a pohled má dron)
func drone_flying() -> bool:
	return drone != null and drone.flying()


## Pohled, přiblížení a přepnutí pohledu – mimo auto (v autě si je bere kamera auta, při letu dronu dron).
func _apply_look() -> void:
	if drone != null and drone.flying():
		return                            # look/zoom/V konzumuje Drone._read_sticks
	if aircraft != null:
		return                            # look/V konzumuje Aircraft._update_camera
	var rel := input.take_look()
	if rel != Vector2.ZERO:
		var sens := mouse_sensitivity * lerpf(1.0, SCOPE_SENS, scope) * lerpf(1.0, AIM_SENS, aim_k)
		yaw -= rel.x * sens
		pitch = clampf(pitch - rel.y * sens, -1.45, 1.35)
	var z := input.take_zoom()
	if z != 0.0:
		_zoom = clampf(_zoom + z, 1.6, 12.0)
	if input.take_toggle_view():
		first_person = not first_person
		visual.set_first_person(first_person)


func _read_input() -> Array:
	if controls_locked or fallen > 0.0 or _action == "vomit":
		return [Vector2.ZERO, false, false, false]
	return [input.move, input.sprint, input.crouch, input.jump_pressed]


# ------------------------------------------------------------------ fyzika

func _physics_process(delta: float) -> void:
	var __t0 := Tests.prof_t0()
	_physics_process_impl(delta)
	Tests.prof_add("player_phys", __t0)


func _physics_process_impl(delta: float) -> void:
	_t += delta
	if car != null or horse != null or aircraft != null:
		# poloha v autě / na koni / v letounu (vozidlo posouvá hráč jen následuje)
		var veh_pos := car.global_position if car else (horse.global_position if horse else aircraft.global_position)
		global_position = veh_pos + Vector3(0, 0.5, 0)
		_prev_pos = global_position
		_cur_pos = global_position
		_air_top_y = global_position.y
		_update_body(delta, 0.0)
		return
	if board_on:
		_board_step(delta)
		return
	if _exit_settle > 0:
		_exit_settle -= 1
		if _exit_settle == 0:
			collision_layer = 2
			collision_mask = 1 | 4 | 8 | 16
			_col.disabled = false
		_prev_pos = global_position
		_cur_pos = global_position
		_air_top_y = global_position.y
		_update_body(delta, 0.0)
		return
	# ovladač (pravá páčka)
	var look := input.look_axis
	if look.length() > 0.15 and not controls_locked:
		yaw -= look.x * 2.6 * delta
		pitch = clampf(pitch - look.y * 1.8 * delta, -1.45, 1.35)

	var p := body.promile()
	var d := body.drunk_level()
	# --- opilost: zpožděné reakce
	var inp := _read_input()
	var delay := clampf(p * 0.1, 0.0, 0.45)
	_input_hist.append([_t, inp])
	while _input_hist.size() > 1 and _t - _input_hist[1][0] >= delay:
		_input_hist.pop_front()
	var used: Array = _input_hist[0][1] if (_t - _input_hist[0][0] >= delay or delay <= 0.0) else [Vector2.ZERO, false, false, false]
	var move_in: Vector2 = used[0]
	var sprint_in: bool = used[1]
	var crouch_in: bool = used[2]
	if inp[3]:
		_jump_buffer = jump_buffer_time
	else:
		_jump_buffer = maxf(_jump_buffer - delta, 0.0)

	var wish := (Basis(Vector3.UP, yaw) * Vector3(move_in.x, 0.0, move_in.y))
	var on_floor := is_on_floor()
	_coyote = coyote_time if on_floor else maxf(_coyote - delta, 0.0)

	# --- ležení na zemi
	if fallen > 0.0:
		fallen -= delta
		if fallen <= 0.0:
			visual.pose = "stand"
	# --- přikrčení / skluz
	var hvel := Vector3(velocity.x, 0.0, velocity.z)
	var want_crouch := crouch_in
	if want_crouch and not _crouching and not _sliding:
		if on_floor and hvel.length() > 6.0:
			_sliding = true
			_slide_time = 0.0
			velocity += hvel.normalized() * slide_boost
		_crouching = true
	elif not want_crouch and (_crouching or _sliding) and _can_stand():
		_crouching = false
		_sliding = false
	if _sliding:
		_slide_time += delta
		if hvel.length() < 2.6 or _slide_time > 1.4 or not want_crouch:
			_sliding = false
	_set_height(CROUCH_HEIGHT if (_crouching or _sliding or fallen > 0.0) else STAND_HEIGHT, delta)

	# --- sprint a výdrž (obezita a kouření snižují)
	var smax := body.stamina_max()
	var sprinting := sprint_in and move_in.length() > 0.1 and not _crouching \
		and not _stamina_lock and move_in.y < 0.3 and not busy and not overloaded and not aim_on and not sprint_blocked()
	if sprinting and on_floor and hvel.length() > effective_walk():
		stamina = maxf(stamina - delta * 0.11 * body.stamina_drain_mult(), 0.0)
		_stamina_delay = 0.9
		if stamina <= 0.0:
			_stamina_lock = true
	else:
		_stamina_delay = maxf(_stamina_delay - delta, 0.0)
		if _stamina_delay <= 0.0:
			stamina = minf(stamina + delta * 0.2, smax)
		if _stamina_lock and stamina > 0.3 * smax:
			_stamina_lock = false
	stamina = minf(stamina, smax)

	var sm := body.speed_mult()
	if overloaded:
		sm *= OVERLOAD_SPEED_MULT
	if aim_on:
		sm *= AIM_SPEED_MULT
	var target_speed := effective_walk() * sm
	if sprinting:
		target_speed = effective_sprint() * sm
	elif _crouching:
		target_speed = crouch_speed
	if busy and _action != "smoke":
		target_speed = minf(target_speed, 1.6)
	if wade > 0.05:
		# brodění potokem / řekou: voda brzdí (po kolena ~ poloviční rychlost)
		target_speed *= lerpf(1.0, 0.4, clampf(wade / 0.6, 0.0, 1.0))
	var target := wish * target_speed

	# --- opilost: drift do stran a dopředu/dozadu, i ve stoje
	var drift := Vector3.ZERO
	if p > 0.35:
		var amp := (p - 0.35) * 1.05
		var right := Basis(Vector3.UP, yaw) * Vector3.RIGHT
		var fwd := Basis(Vector3.UP, yaw) * Vector3.FORWARD
		var moving := clampf(move_in.length(), 0.25, 1.0)
		drift = (right * _noise.get_noise_1d(_t * 9.0) * 1.6 + fwd * _noise.get_noise_1d(_t * 7.0 + 50.0) * 0.6) * amp * moving
		if fallen > 0.0:
			drift = Vector3.ZERO

	# --- horizontální pohyb
	if fallen > 0.0:
		hvel = hvel.move_toward(Vector3.ZERO, (6.0 if on_floor else 1.0) * delta)
	elif _sliding:
		var fn := get_floor_normal() if on_floor else Vector3.UP
		var downhill := Vector3(fn.x, 0.0, fn.z) * gravity * 0.9
		# na kluzkém povrchu (mokro, led, sníh) se skluz táhne dál
		hvel = hvel.move_toward(Vector3.ZERO, slide_friction * lerpf(1.0, _ground_traction(), 0.7) * delta) + downhill * delta
		hvel += wish * 2.0 * delta
	elif on_floor:
		# kluzký povrch (déšť, sníh, náledí, bahno): horší rozjezd, brzdění i zatáčení
		var traction := _ground_traction()
		var accel := ground_accel * (1.0 - d * 0.5) * traction
		if wish.length() < 0.05:
			accel = ground_decel * (1.0 - d * 0.6) * traction
		elif hvel.dot(target) < 0.0:
			accel = turn_accel * (1.0 - d * 0.6) * traction
		hvel = hvel.move_toward(target + drift, accel * delta)
	else:
		if wish.length() > 0.05:
			var along := hvel.dot(wish.normalized())
			var cap := maxf(target_speed, along)
			var nv := hvel + wish * air_accel * delta
			if nv.length() > cap and nv.length() > hvel.length():
				nv = nv.normalized() * maxf(hvel.length(), cap)
			hvel = nv
		hvel *= 1.0 - 0.08 * delta
	velocity.x = hvel.x
	velocity.z = hvel.z

	# --- gravitace
	if not on_floor:
		var g := gravity
		if velocity.y < 0.0:
			g *= fall_multiplier
		elif not input.jump:
			g *= low_jump_multiplier
		velocity.y = maxf(velocity.y - g * delta, -55.0)
	else:
		var fn := get_floor_normal()
		if fn.angle_to(Vector3.UP) > deg_to_rad(38.0):
			velocity += Vector3(fn.x, 0.0, fn.z).normalized() * gravity * 0.6 * delta

	# --- skok
	if _jump_buffer > 0.0 and _coyote > 0.0 and _can_stand() and fallen <= 0.0 and not busy:
		velocity.y = (effective_jump() + (0.6 if _sliding else 0.0)) * body.jump_mult()
		_jump_buffer = 0.0
		_coyote = 0.0
		_sliding = false
		_crouching = false
		jumped.emit()
		if p > 1.5 and randf() < (p - 1.5) * 0.35:
			_stumble_cool = 0.0   # opilý skok často končí pádem

	_prev_vy = velocity.y
	move_and_slide()

	# --- strkání do fyzikálních objektů
	_wall_bump_cool = maxf(_wall_bump_cool - delta, 0.0)
	_floor_surf = "teren"
	var wall_touch := false
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var bdy := c.get_collider()
		if absf(c.get_normal().y) < 0.5:
			wall_touch = true
		if c.get_normal().y > 0.6 and bdy is StaticBody3D:
			_floor_surf = bdy.get_meta("surface", "teren")   # povrch pod nohama (asfalt / šterk / budova…)
		if bdy is RigidBody3D:
			var push := -c.get_normal()
			push.y = maxf(push.y, 0.0) * 0.3
			var rel := maxf(Vector3(velocity.x, 0, velocity.z).length(), 1.0)
			bdy.apply_impulse(push * rel * 0.9, c.get_position() - bdy.global_position)
			if bdy.has_method("on_hit"):
				bdy.on_hit(rel * 0.8)
		elif absf(c.get_normal().y) < 0.4 and hvel.length() > 5.0 and _wall_bump_cool <= 0.0 and p > 1.0:
			# opilý náraz do zdi
			_wall_bump_cool = 1.5
			body.hurt(hvel.length() * 0.8, "náraz do zdi")
			if p > 1.6:
				fall(1.8, "narazil jsi do zdi")

	var now_floor := is_on_floor()
	if not now_floor:
		_air_top_y = maxf(_air_top_y, global_position.y)
	if now_floor and not _was_on_floor and _prev_vy < -2.0:
		var impact := -_prev_vy
		var drop := _air_top_y - global_position.y
		_land_dip = clampf(impact / 18.0, 0.0, 0.35)
		visual.land(impact)
		landed.emit(impact)
		# zranění jen podle skutečné výšky pádu (běžný skok ani seskok z bedny nebolí)
		if drop > SAFE_FALL_HEIGHT:
			body.hurt((drop - SAFE_FALL_HEIGHT) * 9.0, "pád z výšky")
			fall(1.5 + (drop - SAFE_FALL_HEIGHT) * 0.25, "tvrdý dopad")
		elif p > 1.4 and drop > 2.0 and randf() < (p - 1.2) * 0.4:
			fall(2.0, "opilý dopad")
	if now_floor:
		_air_top_y = global_position.y
	_was_on_floor = now_floor

	# poslední volné stání – cíl záchrany při zaseknutí (klávesa U, viz unstick)
	if now_floor and fallen <= 0.0 and not wall_touch and not _sliding:
		_safe_pos = global_position
		_safe_yaw = yaw

	# --- nouzová pojistka: propadnutí terénem (chybná pozice po výstupu z interiéru apod.)
	if not now_floor and velocity.y <= FALL_RECOVER_VY:
		_void_fall_t += delta
		if _void_fall_t > FALL_RECOVER_T:
			_recover_from_void()
			_void_fall_t = 0.0
	else:
		_void_fall_t = 0.0

	# --- zakopnutí
	_stumble_cool -= delta
	if p > 1.2 and on_floor and fallen <= 0.0 and _stumble_cool <= 0.0:
		var hs := hvel.length()
		var chance := (p - 1.2) * 0.06 * delta * (1.0 + hs * 0.35)
		if sprinting:
			chance *= 2.5
		if get_floor_normal().angle_to(Vector3.UP) > 0.25:
			chance *= 1.6
		if hs < 0.3 and p < 2.4:
			chance *= 0.2
		if (_stumble_cool < -30.0 and p > 2.0) or randf() < chance:
			_stumble_cool = 2.5
			if p > 1.7 or hs > 5.0:
				body.hurt(maxf(hs - 2.5, 0.0) * 1.5, "zakopnutí")
				fall(2.2 + p * 0.3, "zakopl jsi")
			else:
				velocity += (Basis(Vector3.UP, yaw) * Vector3.RIGHT) * randf_range(-2.5, 2.5)
				game_event.emit("stagger", {})

	_update_body(delta, hvel.length())
	_prev_pos = _cur_pos
	_cur_pos = global_position


## Přilnavost podrážek na povrchu pod nohama – stejná tabulka jako kola (Weather.SURF_GRIP přes
## Weather.grip_factor: suchý povrch = 1), zjemněná: chodec klouzává míň než pneumatika (mokrý asfalt ~0.78).
func _ground_traction() -> float:
	if weather == null or _roof:         # pod střechou / uvnitř budovy je sucho
		return 1.0
	return lerpf(1.0, weather.grip_factor(_floor_surf), 0.75)


## Je nad hráčem střecha / strop? Paprsek z hlavy nahoru; stromy nestačí, jen budovy.
func _check_roof() -> bool:
	var sp := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1.6, 0),
		global_position + Vector3(0, 26.0, 0), 1, [get_rid()])
	var hit := sp.intersect_ray(q)
	return not hit.is_empty() and hit["collider"].get_meta("surface", "") == "budova"


## Prahové hlášky do HUD (promoklý / prochladlý a zpátečka suchý / zahřátý).
func _weather_msgs() -> void:
	if body.wetness >= 0.55:
		if not _msg_wet:
			_msg_wet = true
			game_event.emit("soaked", {})
	elif _msg_wet and body.wetness <= 0.15:
		_msg_wet = false
		game_event.emit("dried", {})
	if body.cold >= 0.55:
		if not _msg_cold:
			_msg_cold = true
			game_event.emit("chilled", {})
	elif _msg_cold and body.cold <= 0.2:
		_msg_cold = false
		game_event.emit("warmed", {})


func _update_body(delta: float, hs: float) -> void:
	# výdej energie: chůze ~250 kcal/h, sprint ~700 kcal/h (herní hodiny)
	var act := 0.0
	if hs > 0.5:
		act = 250.0 if hs < 6.0 else 700.0
	# počasí na těle: déšť/sníh a vítr venku, uvnitř (v autě nebo pod střechou) sucho a teplo
	var env := {}
	if weather != null:
		_roof_t -= delta
		if _roof_t <= 0.0:
			_roof_t = 0.4
			_roof = _check_roof()
		var sheltered := car != null or _roof
		var rain := 0.0
		if not sheltered:
			if weather.is_raining():
				rain = weather.rain
			elif weather.is_snowing():
				rain = weather.rain * 0.35      # sněžení promáčí jen trochu
		env = {"rain": rain, "temp": weather.temp,
			"wind": 0.0 if sheltered else weather.wind, "in": sheltered,
			"heat": heat, "shelter_min": shelter_min}
		if wade > 0.2:
			body.wetness = maxf(body.wetness, minf(wade * 1.5, 1.0))
	body.update(delta * Clock.TIME_SCALE / 3600.0, act, env)
	_weather_msgs()
	# probíhající akce
	if _action != "":
		_action_t += delta
		if _action == "vomit":
			if _action_t > _action_len:
				visual.stop_action()
				busy = false
				_action = ""
		elif _action == "smoke":
			if _action_t > _action_len and busy:
				busy = false    # s cigaretou lze chodit
		elif _action_t > _action_len:
			_finish_action()
	if _smoke_t > 0.0:
		_smoke_t -= delta
		if _smoke_t <= 0.0 or car != null:
			_smoke_t = 0.0
			if _action == "smoke":
				_action = ""
			visual.stop_action()
			if body.tar > 25.0 and randf() < 0.5:
				game_event.emit("sfx", {"name": "cough"})


func _can_stand() -> bool:
	if _shape.height >= STAND_HEIGHT - 0.01:
		return true
	var q := PhysicsShapeQueryParameters3D.new()
	var s := CapsuleShape3D.new()
	s.radius = RADIUS * 0.9
	s.height = STAND_HEIGHT
	q.shape = s
	q.transform = Transform3D(Basis(), global_position + Vector3(0, STAND_HEIGHT * 0.5 + 0.05, 0))
	q.collision_mask = 1
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


func _set_height(hgt: float, delta: float) -> void:
	var nh := move_toward(_shape.height, hgt, delta * 5.0)
	if not is_equal_approx(nh, _shape.height):
		_shape.height = nh
		_col.position.y = nh * 0.5


func is_sprinting() -> bool:
	return Vector3(velocity.x, 0, velocity.z).length() > walk_speed + 0.8


# ------------------------------------------------------------------ vizuál a kamera

## Řekne něco nahlas – bublina nad hlavou (v 1. osobě ji vlastní kamera nevidí, HUD ukazuje rozhovor).
func say(text: String, dur := 4.0) -> void:
	_say_label.text = text
	_say_t = dur


func _process(delta: float) -> void:
	var __t0 := Tests.prof_t0()
	_process_impl(delta)
	Tests.prof_add("player", __t0)


func _process_impl(delta: float) -> void:
	if _say_t > 0.0:
		_say_t -= delta
	_say_label.visible = _say_t > 0.0 and not (camera != null and first_person and car == null)
	visual.drunk = body.drunk_level()
	visual.fat = body.fatness()
	if car != null:
		visual.speed = 0.0
		visual.pedal_angle = car.pedal_angle
		return
	if aircraft != null:
		visual.speed = aircraft.rider_speed()      # paramotor: pilot běží po zemi
		return
	if horse != null:
		visual.speed = 0.0
		return
	_apply_look()
	var f := Engine.get_physics_interpolation_fraction()
	var pos := _prev_pos.lerp(_cur_pos, f)
	var hspeed := Vector3(velocity.x, 0, velocity.z).length()

	visual.global_position = pos
	visual.speed = hspeed if is_on_floor() and fallen <= 0.0 else 0.0
	visual.on_floor = is_on_floor() or fallen > 0.0
	visual.vertical_speed = velocity.y
	visual.crouching = _crouching and fallen <= 0.0
	visual.sliding = _sliding
	var target_yaw := _visual_yaw
	if first_person:
		target_yaw = yaw + PI
	elif hspeed > 0.4 and fallen <= 0.0:
		target_yaw = atan2(velocity.x, velocity.z)
	_visual_yaw = lerp_angle(_visual_yaw, target_yaw, 1.0 - exp(-14.0 * delta))
	visual.rotation = Vector3(0, _visual_yaw, 0)
	if camera == null:
		return

	# --- kamera
	var d := body.drunk_level()
	_land_dip = move_toward(_land_dip, 0.0, delta * 1.4)
	if is_on_floor() and hspeed > 0.5:
		_bob += delta * hspeed * 1.9
	var eye := (_shape.height - 0.18) if first_person else (_shape.height * 0.82)
	if fallen > 0.0:
		eye = 0.35
	var bob_off := Vector3.ZERO
	if first_person:
		bob_off = Vector3(cos(_bob) * 0.03, absf(sin(_bob)) * 0.05, 0) * clampf(hspeed / 6.0, 0, 1) * (1.0 + d * 2.0)
	var dip := sin(_land_dip * PI / 0.35 * 0.5) * _land_dip
	rig.global_position = pos + Vector3(0, eye - dip, 0)
	# opilé potácení kamery
	var sway_roll := (sin(_t * 0.9) * 0.6 + sin(_t * 2.1 + 1.3) * 0.3) * 0.09 * d
	var sway_pitch := sin(_t * 0.7 + 0.4) * 0.05 * d
	var sway_yaw := sin(_t * 0.55) * 0.06 * d
	var craving := body.craving if body.ever_smoked else 0.0
	var withdrawal := craving * body.addiction   # jen fakticky závislá postava, ne po jedné cigaretě
	var shake := Vector3.ZERO
	if shake_enabled and not aim_on and not scope_on:
		var tremor := 0.0
		if withdrawal > SHAKE_WITHDRAWAL_MIN:   # abstinence: jen krátké „záchvaty“, mezi nimi klid
			var ph := fposmod(_t, SHAKE_FIT_PERIOD)
			if ph < SHAKE_FIT_LEN:
				var env := sin(PI * ph / SHAKE_FIT_LEN)
				tremor += SHAKE_WITHDRAWAL_AMP * env * env * (withdrawal - SHAKE_WITHDRAWAL_MIN) / (1.0 - SHAKE_WITHDRAWAL_MIN)
		if body.cold > SHAKE_COLD_MIN:          # zima: plynulý třes
			tremor += minf(SHAKE_COLD_AMP * (body.cold - SHAKE_COLD_MIN) / (1.0 - SHAKE_COLD_MIN), SHAKE_COLD_MAX)
		if tremor > 0.0:
			# hladký šum (ne bílý): jemné chvění o frekvenci SHAKE_FREQ, ne skákání každý snímek
			shake = Vector3(_shake_noise.get_noise_1d(_t * SHAKE_FREQ), _shake_noise.get_noise_1d(_t * SHAKE_FREQ + 313.0), 0.0) * tremor
	rig.rotation = Vector3(pitch + sway_pitch + shake.x + aim_sway.y, yaw + sway_yaw + shake.y + aim_sway.x, sway_roll)
	var want_len := 0.0 if first_person else _zoom
	_arm_len = lerpf(_arm_len, want_len, 1.0 - exp(-10.0 * delta))
	arm.spring_length = _arm_len
	arm.position = Vector3(0.0 if first_person else 0.35, 0, 0) + bob_off
	var fov := base_fov + d * 6.0 * sin(_t * 0.4)
	if hspeed > walk_speed + 0.8:
		fov += (hspeed - walk_speed) * 1.6
	if _sliding:
		fov += 4.0
	var optic_aim := aim_on and aim_optic        # puška s optikou: míření = dalekohled (M2.8)
	scope = move_toward(scope, 1.0 if (scope_on or optic_aim) and fallen <= 0.0 else 0.0, delta * 4.0)
	aim_k = move_toward(aim_k, 1.0 if aim_on and not aim_optic and fallen <= 0.0 else 0.0, delta * 6.0)
	var view_fov := lerpf(minf(fov, 90.0), aim_fov, aim_k)
	camera.fov = lerpf(camera.fov, lerpf(view_fov, SCOPE_FOV if not optic_aim else aim_fov, scope), 1.0 - exp(-8.0 * delta))
	visual.visible = first_person or arm.get_hit_length() > 0.7
	if first_person:
		visual.visible = true
	if scope > 0.5:
		visual.visible = false
