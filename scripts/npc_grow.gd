## M4.8 obsah pro dospělé: zahrádkář Ladislav Hrubý pěstuje konopí na svém záhonu za chatou u lesa.
##
## - Jen při zapnuté volbě „Obsah pro dospělé“ (`ItemsDB.adult_on`). Vypnuto = žádný záhon, žádný růst, nic v dialogu.
## - Záhon je pozemek NPC: výsev v dubnu / květnu jednou za rok, sklizeň po `DAYS` dnech. Sklizeň je jen počet rostlin
##   v `state` – nic nejde do inventáře, nic se neprodává, hráč s ním nemá žádnou interakci.
## - Svědci: při výsevu se hráče v okruhu zeptá `World.witness_reported` (vidí a nahlásí). Následek: zabavení rostlin
##   z záhonu (`zabaveno`, rostliny 0, záhon zůstane prázdný). Pokuta NPC by vyžadovala jeho rejstřík zákona (otevřený bod).
## - Ukládání: klíč `npc_grow` na úrovni světa (starý save bez klíče = žádný záhon).
class_name NpcGrow
extends Node3D

const NPC_NAME := "Ladislav Hrubý"
const SOW_MONTHS := [4, 5]
const DAYS := 110.0                    # dny od výsevu do sklizně (jako `konopi` v Garden.CROPS)
const PLANTS_MIN := 4
const PLANTS_MAX := 8
const SEE_R := 25.0                    # m – dohled souseda na záhon
const CHECK_R := 150.0                 # m – hráči v tomto okruhu mohou čin zaznamenat
const PLOT_OFFSET := Vector3(0.0, 0.0, -9.0)   # m od dveří chaty – „za chatou“ (ladit)
const PLOT_SIZE := Vector2(3.0, 2.0)
const LEAF := Color(0.22, 0.5, 0.2)

var world: World
var state := {}                        # {"rok": int, "vysety": bool, "rostliny": int, "dny": float, "sklizeno": int, "nahlaseno": bool, "zabaveno": bool}
var _last_jd := -1
var _patch: Node3D


func setup(w: World) -> void:
	world = w
	_last_jd = -1


func _process(_delta: float) -> void:
	if world == null or world.clock == null:
		return
	var jd := world.clock.jd()
	if _last_jd < 0:
		_last_jd = jd
	elif jd != _last_jd:
		var dd := jd - _last_jd
		_last_jd = jd
		_advance(dd)
	_update_visual()


## Denní krok: jen při zapnuté volbě pro dospělé.
func _advance(dd: int) -> void:
	if not ItemsDB.adult_on:
		return
	var y := world.clock.year()
	if int(state.get("rok", -1)) != y:
		state = {"rok": y, "vysety": false, "rostliny": 0, "dny": 0.0, "sklizeno": 0, "nahlaseno": false, "zabaveno": false}
	if not bool(state["vysety"]):
		if world.clock.month() in SOW_MONTHS:
			_sow()          # první den v sezóně výsevu (jednou za rok)
		return
	if int(state["sklizeno"]) == 0 and float(state["dny"]) < DAYS:
		state["dny"] = float(state["dny"]) + float(dd)
		if float(state["dny"]) >= DAYS:
			state["sklizeno"] = int(state["rostliny"])     # sklizeň zůstává jen v datech


func _sow() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(world.clock.year()) + NPC_NAME)
	state["vysety"] = true
	state["rostliny"] = rng.randi_range(PLANTS_MIN, PLANTS_MAX)
	state["dny"] = 0.0
	state["zabaveno"] = false
	var pos := plot_pos()
	# svědci: kdo z hráčů záhon vidí a nahlásí (příznak, bez následků pro NPC – otevřený bod)
	for pid in world.players.keys():
		var p: Player = world.players[pid]
		if p == null or p.global_position.distance_to(pos) > CHECK_R:
			continue
		if world.witness_reported(int(pid), pos, "pestovani", SEE_R):
			state["nahlaseno"] = true
			state["zabaveno"] = true
			state["rostliny"] = 0       # následek: rostliny ze záhonu se zabaví
			world.notify(int(pid), "show_message", ["Na okraji lesa někdo nahlásil konopí na záhonu. Rostliny byly zabaveny.", 4.0])
			break


## Střed záhonu: za chatou u lesa (z dveří chaty), nebo nic, když chata není.
func plot_pos() -> Vector3:
	var ch: Place = world.places.get("chata") if world != null else null
	if ch == null:
		return Vector3.ZERO
	var p := ch.door + PLOT_OFFSET
	if world.terrain:
		p.y = world.terrain.height_at(p.x, p.z)
	return p


## Vizuál: zelený záhon s rostlinami jen při zapnuté volbě a po výsevu v letošním roce.
func _update_visual() -> void:
	var show := (ItemsDB.adult_on and bool(state.get("vysety", false)) and int(state.get("sklizeno", 0)) == 0
		and not bool(state.get("zabaveno", false)))
	if not show:
		if _patch:
			_patch.visible = false
		return
	if _patch == null:
		_patch = _build_patch()
		add_child(_patch)
	_patch.visible = true
	_patch.global_position = plot_pos()


func _build_patch() -> Node3D:
	var root := Node3D.new()
	var plate := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(PLOT_SIZE.x, 0.08, PLOT_SIZE.y)
	plate.mesh = box
	plate.position = Vector3(0, 0.04, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.27, 0.18, 0.11)
	plate.material_override = mat
	root.add_child(plate)
	var n := int(state.get("rostliny", PLANTS_MIN))
	for i in n:
		var st := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.02
		cyl.bottom_radius = 0.06
		cyl.height = 0.6
		st.mesh = cyl
		st.position = Vector3(-PLOT_SIZE.x * 0.4 + i * PLOT_SIZE.x * 0.8 / maxf(1.0, float(n - 1)), 0.4, 0.0)
		var lm := StandardMaterial3D.new()
		lm.albedo_color = LEAF
		st.material_override = lm
		root.add_child(st)
	return root


# ------------------------------------------------------------------ ukládání

func to_dict() -> Dictionary:
	return state.duplicate(true)


## Starý save bez klíče = žádný záhon.
func restore(d: Dictionary) -> void:
	state = d.duplicate(true)
	_last_jd = -1
