## Lovecké zbraně a střelba (M2.8), jeden uzel ve `World` (`World.weapons`): luk, kuše, puška.
##
## Ovládání: Q / 1–5 zbraň do ruky, **pravé tlačítko** = mířit (kamera se přiblíží, puška s optikou jako dalekohled, chůze
## zpomalí, Shift při míření = zadržet dech 3 s), **levé tlačítko** = výstřel. Luk: držet LMB = natahovat (síla podle doby,
## 1,2 s = plná), pustit = výstřel. Kuše: výstřel, pak 4 s napínání. Puška: zásobník 3 náboje, 1,5 s mezi ranami, přebíjení 4 s.
##
## Kolísání mušky (`Player.aim_sway`, kamera se s ním kývá): výdrž (po sprintu víc), opilost, chlad, dovednost Střelba
## (méně), pohyb, dlouho natažený luk, zadržený dech (málo) a ztracený dech po něm (víc).
##
## Balistika: projektil jde po krocích fyzikálního snímku jako paprsek (ne RigidBody – výkon): gravitace, odpor, vítr
## (`Weather.wind_vector`, hodně šíp, kulka skoro vůbec). Šíp a šipka mají malý viditelný mesh; kulka jen dopad. Směr
## výstřelu vede z oka k bodu, na který míří střed obrazovky (paralaxa kamery za zády).
## Zásah: terén / strom / zeď (šíp se zapíchne na 2 min a jde sebrat klávesou E), terč střelnice (`ShootingRange`),
## člověk (`ublizeni_na_zdravi`, pád, útěk, pátrání policie), auto / zvíře v ohradě / pes / kůň (`poskozeni_veci`), zvěř
## (událost `shot_hit` {target, part, energy, …}; smrt a úlovek řeší `Hunting`, M2.9).
##
## Zákon (`data/zakon.json`; všechno přes `World.commit_offense`, svědek = `Forestry.witness_near`): puška bez zbrojního
## oprávnění (`World.has_permit(id, "zbrojni", pos)`, zatím jen cheat – doklady M4.6), střelba v obci / do 100 m od silnice,
## zbraň pod vlivem, zásah člověka, poškození věci. Puška v ruce ve vsi vesničany vyděsí (mohou volat policii); policejní
## kontrola (`police_check`) bez oprávnění zbraň zabaví.
class_name Weapons
extends Node3D

const G := 9.81
const MASK := 1 | 4 | 8 | 16                  # statika (terén, budovy, stromy), vesničané + zvěř, rekvizity, auta
const MAX_DT := 0.05
const LIFE_S := 10.0                           # nejdéle letí projektil (s)
const MAX_RANGE_M := 1800.0
const STUCK_LIFE_S := 120.0                    # zapíchnutý šíp zůstane 2 min
const STUCK_MAX := 80
const STICK_MIN_SPEED := 8.0                   # pomalejší šíp jen spadne (nezapíchne se)
const PICKUP_R := 1.9
const BREATH_S := 3.0                          # jak dlouho jde zadržet dech
const WINDED_S := 2.5                          # po vydechnutí je muška horší
const MIN_DRAW_S := 0.3                        # kratší natažení luku = šíp zůstává
const OVERDRAW_S := 4.0                        # tolik s po plném natažení se ruka unaví úplně
const WILD_R := 400.0                          # do kolika m výstřel z pušky zvěř splaší
const VILLAGE_R := 30.0                        # do kolika m vesničana vyděsí puška v ruce
const OFFENSE_CD_MIN := {"strelba_v_obci": 10.0, "zbran_pod_vlivem": 15.0, "nedovolene_ozbrojovani": 30.0,
	"policie_kontrola_zbrane": 120.0}
const SHOW_CD_S := 30.0                        # jeden vesničan se leknout stejné zbraně nejvýš jednou za tolik s
const CHECK_S := 1.5                           # jak často (s) se kontroluje pěší se zbraní (vesnice, policie)

## Zbraně: id předmětu → parametry. Nabití a výkon jsou laditelné tady (DOPLNIT: hodnoty orientační, dle zadání).
##   kind   arrow (šíp/šipka, viditelný) / bullet (kulka)    draw_s  natahování (luk)    cycle_s  napnutí po ráně (kuše)
##   shot_cd / reload_s / mag  pauza mezi ranami, přebíjení, zásobník    v0  úsťová rychlost m/s    range  účinný dostřel m
##   noise  slyšet do m    fov  zorný úhel míření    optic  míření = dalekohled    sway  základní kolísání mušky (rad)
##   mass kg  drag 1/s  wind_k  vítr → zrychlení    spread  rozptyl (rad)    permit  potřebné oprávnění ("" = volně)
const WEAPONS := {
	"luk": {"name": "Luk", "ammo": "sipy", "kind": "arrow", "draw_s": 1.2, "cycle_s": 0.0, "shot_cd": 0.4, "reload_s": 0.0,
		"mag": 1, "v0": 60.0, "range": 30.0, "noise": 25.0, "fov": 45.0, "optic": false, "sway": 0.0075,
		"mass": 0.025, "drag": 0.04, "wind_k": 0.35, "spread": 0.004, "firearm": false, "permit": "",
		"len": 0.75, "snd": "bow_shot"},
	"kuse": {"name": "Kuše", "ammo": "sipky_kuse", "kind": "arrow", "draw_s": 0.0, "cycle_s": 4.0, "shot_cd": 0.0, "reload_s": 0.0,
		"mag": 1, "v0": 100.0, "range": 45.0, "noise": 30.0, "fov": 45.0, "optic": false, "sway": 0.0045,
		"mass": 0.03, "drag": 0.03, "wind_k": 0.25, "spread": 0.0025, "firearm": false, "permit": "",
		"len": 0.4, "snd": "bow_shot"},
	"puska": {"name": "Puška", "ammo": "naboje", "kind": "bullet", "draw_s": 0.0, "cycle_s": 0.0, "shot_cd": 1.5, "reload_s": 4.0,
		"mag": 3, "v0": 800.0, "range": 200.0, "noise": 1500.0, "fov": 9.0, "optic": true, "sway": 0.0022,
		"mass": 0.011, "drag": 0.25, "wind_k": 0.05, "spread": 0.0006, "firearm": true, "permit": "zbrojni",
		"len": 0.0, "snd": "gunshot"},
}
## Zboží, které obchod prodá jen s oprávněním: id předmětu → druh oprávnění (`World.has_permit`).
const PERMIT_ITEMS := {"puska": "zbrojni", "naboje": "zbrojni"}
## Hlášky vesničanů při pohledu na zbraň / střelbu.
const SCARED_LINES := ["Pane, schovejte to!", "Jéžišmarjá, co to má bejt?!", "Ježiši, nemíř na mě!", "Zbláznil ses? Odlož to!",
	"To je zbraň! Volám někoho!", "Do zástavby se nestřílí!"]
## Šance, že vesničan po leknutí zavolá policii, podle povahy (Persona.profile["trait"]).
const CALL_P := {"prisny": 0.6, "drbna": 0.7, "plachy": 0.5, "bruclavy": 0.4, "moudry": 0.35, "mlady": 0.3,
	"pratelsky": 0.25, "veselak": 0.2}

var world: World
var range_: ShootingRange
var states := {}                     # id hráče → stav zbraně (natažení, pauzy, zásobník, dech)
var projectiles: Array = []          # letící {w, kind, pos, vel, t, id, start, node, mass}
var arrows: Array = []               # zapíchnuté {node, ammo, pos, t}
var _range_tried := false
var _check_t := 0.0
var _scared := {}                    # instance id vesničana → čas (s) posledního leknutí
var _last_off := {}                  # "id:přestupek" → herní minuty posledního zápisu (aby to nesypalo při každé ráně)


func setup(w: World) -> void:
	world = w
	name = "Zbrane"


# ------------------------------------------------------------------ pomocné (statické, pro ostatní kroky)

static func is_weapon(id: String) -> bool:
	return WEAPONS.has(id)


## Zóna zásahu zvířete z bodu v souřadnicích modelu (+Z hlava, +Y nahoru, počátek = země pod středem trupu; `spec` =
## slovník z `AnimalSpecs`). Vrací "hlava" | "srdce_plice" | "bricho" | "noha". M2.9 to zapojí do zranění a úlovku.
static func hit_zone(local_point: Vector3, spec: Dictionary) -> String:
	var h := float(spec.get("withers", 0.7))
	var l := float(spec.get("length", 1.0))
	if local_point.y < 0.38 * h:
		return "noha"
	if local_point.z > 0.42 * l and local_point.y > 0.72 * h:
		return "hlava"
	if local_point.z > -0.12 * l and local_point.z < 0.42 * l and local_point.y > 0.42 * h:
		return "srdce_plice"
	return "bricho"


## Totéž pro uzel zvířete (`Animal`, `Horse`…) a bod ve světových souřadnicích.
static func zone_of(animal: Node3D, world_point: Vector3) -> String:
	var spec = animal.get("spec")
	return hit_zone(animal.to_local(world_point), spec if spec is Dictionary else {})


## Model šípu (hrot míří do −Z, opeření vzadu). `bolt` = šipka do kuše (tmavá).
static func arrow_model(length := 0.75, bolt := false) -> Node3D:
	var k := MeshKit.new()
	var shaft := Color(0.3, 0.3, 0.32) if bolt else Color(0.72, 0.6, 0.38)
	k.cylinder(Vector3.ZERO, 0.005, 0.005, length, shaft, Vector3(PI / 2.0, 0, 0), 5)
	k.box(Vector3(0, 0, -length * 0.5), Vector3(0.012, 0.012, 0.045), ToolModels.STEEL)
	var fl := Color(0.85, 0.2, 0.15)
	k.box(Vector3(0, 0, length * 0.5 - 0.05), Vector3(0.002, 0.04, 0.09), fl)
	k.box(Vector3(0, 0, length * 0.5 - 0.05), Vector3(0.04, 0.002, 0.09), fl)
	var root := Node3D.new()
	MeshKit.mesh_instance(root, k.commit(MeshKit.vc_material(0.7, 0.0)), 250.0)
	return root


# ------------------------------------------------------------------ stav a smyčka

func _player(id: int) -> Player:
	return world.players.get(id) as Player


func _state(id: int) -> Dictionary:
	if not states.has(id):
		states[id] = {"w": "", "draw": 0.0, "drawing": false, "cd": 0.0, "cd_len": 1.0, "reload": false, "mag": {},
			"breath": BREATH_S, "winded": 0.0, "t": randf() * 10.0, "bar": false, "amp": 0.0}
	return states[id]


func _can_handle(p: Player) -> bool:
	return p.car == null and p.horse == null and not p.busy and p.fallen <= 0.0 and not p.controls_locked and p.inside == ""


func _msg(id: int, text: String, dur := 2.5) -> void:
	world.notify(id, "show_message", [text, dur])


func _now_min() -> float:
	return world.clock.minutes


func _physics_process(delta: float) -> void:
	if world == null or not world.ready_done:
		return
	if not _range_tried:
		_range_tried = true
		range_ = ShootingRange.new()
		add_child(range_)
		range_.setup(world)
	var dt := minf(delta, MAX_DT)
	for id in world.players.keys():
		var p := _player(id)
		if p != null:
			_tick_player(id, p, dt)
	_step_projectiles(dt)
	_tick_arrows(dt)
	_check_t -= dt
	if _check_t <= 0.0:
		_check_t = CHECK_S
		for id in world.players.keys():
			var p2 := _player(id)
			if p2 != null:
				_village_check(id, p2)
				_police_foot_check(id, p2)


## Při změně zbraně v ruce: uklidit míření, natažení a stavový text.
func _on_equip_change(id: int, p: Player, s: Dictionary, w: String) -> void:
	s["w"] = w
	s["drawing"] = false
	s["draw"] = 0.0
	s["cd"] = 0.0
	s["reload"] = false
	p.aim_on = false
	p.aim_sway = Vector2.ZERO
	p.weapon_status = ""
	if p.visual != null and p.visual.action == "aim":
		p.visual.stop_action()
	_bar(id, s, "", -1.0)


func _bar(id: int, s: Dictionary, title: String, v: float) -> void:
	if v < 0.0:
		if bool(s["bar"]):
			s["bar"] = false
			world.notify(id, "action_progress", ["", -1.0])
		return
	s["bar"] = true
	world.notify(id, "action_progress", [title, clampf(v, 0.0, 1.0)])


func _tick_player(id: int, p: Player, dt: float) -> void:
	var s := _state(id)
	var w: String = p.equipped if WEAPONS.has(p.equipped) else ""
	if w != String(s["w"]):
		_on_equip_change(id, p, s, w)
	if w == "":
		return
	var spec: Dictionary = WEAPONS[w]
	s["t"] = float(s["t"]) + dt
	s["cd"] = maxf(float(s["cd"]) - dt, 0.0)
	var can := _can_handle(p)
	if not can and bool(s["drawing"]):
		s["drawing"] = false
		s["draw"] = 0.0
		_bar(id, s, "", -1.0)
	# --- míření
	var aiming := can and p.input.aim
	p.aim_on = aiming
	p.aim_fov = float(spec["fov"])
	p.aim_optic = bool(spec["optic"])
	if aiming and p.visual.action != "aim":
		if world.action_runner and world.action_runner.is_running(id):
			world.cancel_action(id)
		if p.visual.action == "":
			p.visual.start_action("aim")
	elif not aiming and p.visual.action == "aim":
		p.visual.stop_action()
	# --- dech
	var hold := aiming and p.input.sprint and float(s["winded"]) <= 0.0 and float(s["breath"]) > 0.0
	if hold:
		s["breath"] = float(s["breath"]) - dt
		if float(s["breath"]) <= 0.0:
			s["winded"] = WINDED_S
	else:
		s["breath"] = minf(float(s["breath"]) + dt * 0.5, BREATH_S)
		s["winded"] = maxf(float(s["winded"]) - dt, 0.0)
	# --- kolísání mušky
	var amp := _sway_amp(id, p, s, spec, hold)
	s["amp"] = amp
	var t := float(s["t"])
	var sw := Vector2(sin(t * 1.7) + 0.5 * sin(t * 4.3 + 1.0), cos(t * 1.3) + 0.5 * sin(t * 3.1 + 2.0)) * (amp / 1.5)
	p.aim_sway = p.aim_sway.lerp(sw if aiming else Vector2.ZERO, 1.0 - exp(-10.0 * dt))
	# --- zbraň podle druhu
	if float(spec["draw_s"]) > 0.0:
		_tick_bow(id, p, s, spec, w, dt)
	elif float(spec["cycle_s"]) > 0.0:
		if float(s["cd"]) > 0.0:
			_bar(id, s, "Napínám tětivu…", 1.0 - float(s["cd"]) / float(s["cd_len"]))
		else:
			_bar(id, s, "", -1.0)
	else:
		_tick_rifle(id, p, s, spec, w)
	p.weapon_status = _status_text(p, s, spec, w, hold)


func _sway_amp(id: int, p: Player, s: Dictionary, spec: Dictionary, hold: bool) -> float:
	var a := float(spec["sway"])
	a *= 1.0 + 4.0 * p.body.drunk_level()                          # opilost – hodně
	a *= 1.0 + 2.0 * clampf(p.body.cold, 0.0, 1.0)                 # chlad
	var st := clampf(p.stamina / maxf(p.body.stamina_max(), 0.1), 0.0, 1.0)
	a *= 1.0 + 1.5 * (1.0 - st)                                    # výdrž – po sprintu víc
	var sk: Skills = world.skills.get(id)
	if sk:
		a *= lerpf(1.0, 0.5, sk.bonus("strelba"))                  # dovednost Střelba – méně
	a *= 1.0 + Vector2(p.velocity.x, p.velocity.z).length() * 0.35
	if p.visual != null and p.visual.crouching:
		a *= 0.7
	if hold:
		a *= 0.25
	elif float(s["winded"]) > 0.0:
		a *= 1.6
	if bool(s["drawing"]):
		var over := (float(s["draw"]) - float(spec["draw_s"])) / OVERDRAW_S
		a *= 1.0 + 1.5 * clampf(over, 0.0, 1.0)                    # dlouho natažený luk se třese
	return a


func _ammo_short(ammo: String) -> String:
	return String(ItemsDB.info(ammo).get("short", ammo))


func _status_text(p: Player, s: Dictionary, spec: Dictionary, w: String, hold: bool) -> String:
	var ammo := String(spec["ammo"])
	var n := p.item_count(ammo)
	var txt := "%s · %s: %d" % [String(spec["name"]), _ammo_short(ammo), n]
	if bool(spec["firearm"]):
		var mags: Dictionary = s["mag"]
		txt = "%s · zásobník %d/%d · %s: %d" % [String(spec["name"]), int(mags.get(w, int(spec["mag"]))), int(spec["mag"]),
			_ammo_short(ammo), n]
		if bool(s["reload"]):
			txt += " · přebíjím"
	elif bool(s["drawing"]):
		txt += " · natažený %d %%" % roundi(clampf(float(s["draw"]) / float(spec["draw_s"]), 0.0, 1.0) * 100.0)
	elif float(spec["cycle_s"]) > 0.0 and float(s["cd"]) > 0.0:
		txt += " · napínám"
	if hold:
		txt += " · zadržený dech"
	if n <= 0:
		txt += " (došlo!)"
	if p.aim_on:
		txt += _wind_text(p)
	return txt


## Šipka směru větru vůči pohledu hráče při míření (M2.9; zvěř cítí člověka po větru, vítr snáší i střelu). Vítr pod 0,5 m/s = bezvětří.
func _wind_text(p: Player) -> String:
	var w: Weather = world.weather
	if w == null:
		return ""
	if w.wind < 0.5:
		return " · bezvětří"
	var wv := w.wind_vector()
	var fwd := Basis(Vector3.UP, p.yaw) * Vector3.FORWARD
	var right := Basis(Vector3.UP, p.yaw) * Vector3.RIGHT
	var ang := atan2(wv.dot(right), wv.dot(fwd))
	var arrows := ["↑", "↗", "→", "↘", "↓", "↙", "←", "↖"]
	var i := posmod(roundi(ang / (TAU / 8.0)), 8)
	return " · vítr %s %.0f m/s" % [arrows[i], w.wind]


# ------------------------------------------------------------------ vstup (LMB)

## Levé tlačítko (stisk) se zbraní v ruce: luk začne natahovat, kuše a puška vystřelí. Vrací true, když zbraň klik převzala
## (pak se nespouští kontextová akce ani rybaření).
func on_click(id: int) -> bool:
	var p := _player(id)
	if p == null or not WEAPONS.has(p.equipped):
		return false
	if not _can_handle(p):
		return true
	var s := _state(id)
	var w := p.equipped
	var spec: Dictionary = WEAPONS[w]
	if float(s["cd"]) > 0.0 or bool(s["drawing"]):
		return true
	var ammo := String(spec["ammo"])
	if p.item_count(ammo) <= 0:
		_msg(id, "Nemáš střelivo: %s." % ItemsDB.name_of(ammo), 2.0)
		return true
	if float(spec["draw_s"]) > 0.0:
		s["drawing"] = true
		s["draw"] = 0.0
		return true
	if bool(spec["firearm"]):
		var mags: Dictionary = s["mag"]
		if int(mags.get(w, int(spec["mag"]))) <= 0:
			_start_reload(id, s, spec)
			return true
	_fire(id, p, s, w, spec, 1.0)
	if float(spec["cycle_s"]) > 0.0:
		s["cd"] = float(spec["cycle_s"])
		s["cd_len"] = float(spec["cycle_s"])
	elif bool(spec["firearm"]):
		s["cd"] = float(spec["shot_cd"])
		s["cd_len"] = float(spec["shot_cd"])
	return true


func _start_reload(id: int, s: Dictionary, spec: Dictionary) -> void:
	var p := _player(id)
	if p == null or p.item_count(String(spec["ammo"])) <= 0:
		_msg(id, "Došly náboje.", 2.0)
		return
	s["reload"] = true
	s["cd"] = float(spec["reload_s"])
	s["cd_len"] = float(spec["reload_s"])


func _tick_rifle(id: int, p: Player, s: Dictionary, spec: Dictionary, w: String) -> void:
	var mags: Dictionary = s["mag"]
	var cur := int(mags.get(w, int(spec["mag"])))
	if bool(s["reload"]):
		_bar(id, s, "Přebíjím…", 1.0 - float(s["cd"]) / maxf(float(s["cd_len"]), 0.01))
		if float(s["cd"]) <= 0.0:
			s["reload"] = false
			mags[w] = mini(int(spec["mag"]), p.item_count(String(spec["ammo"])))
			_bar(id, s, "", -1.0)
			_msg(id, "Přebito.", 1.5)
		return
	_bar(id, s, "", -1.0)
	# prázdný zásobník: po ráně se přebíjí samo
	if cur <= 0 and float(s["cd"]) <= 0.0 and p.item_count(String(spec["ammo"])) > 0:
		_start_reload(id, s, spec)


func _tick_bow(id: int, p: Player, s: Dictionary, spec: Dictionary, w: String, dt: float) -> void:
	if not bool(s["drawing"]):
		_bar(id, s, "", -1.0)
		return
	s["draw"] = float(s["draw"]) + dt
	var full := float(spec["draw_s"])
	_bar(id, s, "Natažení luku", float(s["draw"]) / full)
	if p.input.reel:
		return
	# pustit = výstřel
	s["drawing"] = false
	_bar(id, s, "", -1.0)
	var d := float(s["draw"])
	s["draw"] = 0.0
	if d < MIN_DRAW_S:
		_msg(id, "Slabé natažení – šíp zůstává.", 1.5)
		return
	if p.item_count(String(spec["ammo"])) <= 0:
		return
	var power := clampf(d / full, 0.0, 1.0)
	if d > full + OVERDRAW_S:
		power *= 0.75
		_msg(id, "Ruka se ti třese, natáhl jsi moc dlouho.", 2.0)
	_fire(id, p, s, w, spec, power)
	s["cd"] = float(spec["shot_cd"])
	s["cd_len"] = float(spec["shot_cd"])


# ------------------------------------------------------------------ výstřel

## Směr výstřelu z oka `origin`: k bodu, na který míří střed obrazovky (paprsek z kamery), jinak podle pohledu hráče.
func _aim_dir(p: Player, origin: Vector3) -> Vector3:
	var fallback := Vector3.FORWARD
	if world.action_runner:
		fallback = world.action_runner.aim_dir(p)
	var cam := p.camera
	if cam == null or not cam.is_inside_tree():
		return fallback
	var cf := -cam.global_transform.basis.z
	var co := cam.global_position
	var q := PhysicsRayQueryParameters3D.create(co, co + cf * 400.0, MASK)
	q.exclude = [p.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var target := co + cf * 400.0
	if not hit.is_empty() and co.distance_to(hit["position"]) > 2.5:
		target = hit["position"]
	var d := (target - origin).normalized()
	return d if d.dot(cf) > 0.5 else cf


func _spread(dir: Vector3, ang: float) -> Vector3:
	if ang <= 0.0:
		return dir
	var up := Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT
	var b := Basis.looking_at(dir, up)
	var a := randf() * TAU
	var r := sqrt(randf()) * ang
	return (b * Vector3(sin(a) * r, cos(a) * r, -1.0)).normalized()


func _fire(id: int, p: Player, s: Dictionary, w: String, spec: Dictionary, power: float) -> void:
	var ammo := String(spec["ammo"])
	if not p.remove_item(ammo):
		return
	if bool(spec["firearm"]):
		var mags: Dictionary = s["mag"]
		mags[w] = maxi(int(mags.get(w, int(spec["mag"]))) - 1, 0)
	var origin := p.global_position + Vector3(0, 1.5, 0)
	if p.rig != null:
		origin = p.rig.global_position
	var dir := _aim_dir(p, origin)
	var spread := float(spec["spread"])
	if not p.aim_on:
		spread += float(s.get("amp", 0.0)) * 4.0                   # bez míření se střílí „od boku“ – velký rozptyl
	dir = _spread(dir, spread)
	var v0 := float(spec["v0"])
	if float(spec["draw_s"]) > 0.0:
		v0 *= lerpf(0.35, 1.0, power)                              # slabě natažený luk = pomalý šíp
	var pr := {"w": w, "kind": String(spec["kind"]), "pos": origin, "vel": dir * v0, "t": 0.0, "id": id,
		"start": origin, "node": null, "mass": float(spec["mass"])}
	if String(spec["kind"]) == "arrow":
		var node := arrow_model(float(spec["len"]), w == "kuse")
		add_child(node)
		_orient(node, origin, dir)
		pr["node"] = node
	projectiles.append(pr)
	world.sound.emit(origin, String(spec["snd"]), randf_range(0.93, 1.07), 0.0, float(spec["noise"]))
	if bool(spec["firearm"]):
		p.pitch = clampf(p.pitch + 0.02, -1.45, 1.35)              # zpětný ráz
		p.aim_sway += Vector2(randf_range(-0.004, 0.004), 0.012)
	_alarm_wildlife(origin, minf(float(spec["noise"]), WILD_R))
	world.emit_game_event(id, "gunshot", {"pos": origin, "weapon": w, "noise": float(spec["noise"]), "dir": dir})
	_law_on_shot(id, p, spec, origin, dir)


func _orient(node: Node3D, pos: Vector3, dir: Vector3) -> void:
	var up := Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT
	node.global_transform = Transform3D(Basis.looking_at(dir, up), pos)


## Výstřel / šum splaší zvěř do `radius` m (`Animal.hear_shot`: zvíře i celé stádo prchá od zdroje).
func _alarm_wildlife(pos: Vector3, radius: float) -> void:
	if world.fauna == null or radius <= 0.0:
		return
	for a in world.fauna.animals:
		if is_instance_valid(a) and a.global_position.distance_to(pos) < radius:
			a.hear_shot(pos, 20.0)


# ------------------------------------------------------------------ balistika

func _step_projectiles(dt: float) -> void:
	if projectiles.is_empty():
		return
	var wind := Vector3.ZERO
	if world.weather != null:
		wind = world.weather.wind_vector()
	var space := get_world_3d().direct_space_state
	var ter: Terrain = world.terrain
	for i in range(projectiles.size() - 1, -1, -1):
		var pr: Dictionary = projectiles[i]
		var spec: Dictionary = WEAPONS[String(pr["w"])]
		var vel: Vector3 = pr["vel"]
		vel += (Vector3(0, -G, 0) + wind * float(spec["wind_k"]) - vel * float(spec["drag"])) * dt
		var a: Vector3 = pr["pos"]
		var b := a + vel * dt
		pr["vel"] = vel
		pr["t"] = float(pr["t"]) + dt
		var hit := {}
		var q := PhysicsRayQueryParameters3D.create(a, b, MASK)
		var shooter := _player(int(pr["id"]))
		if shooter != null:
			q.exclude = [shooter.get_rid()]
		var rh := space.intersect_ray(q)
		if not rh.is_empty():
			hit = rh
		elif ter != null and ter.contains(b.x, b.z, 0.0) and b.y <= ter.height_at(b.x, b.z):
			# vzdálený terén bez kolize: zásah podle výšky (průsečík úsečky s terénem lineárně)
			var ha := a.y - ter.height_at(a.x, a.z)
			var hb := b.y - ter.height_at(b.x, b.z)
			var f := clampf(ha / maxf(ha - hb, 0.0001), 0.0, 1.0)
			var hp := a.lerp(b, f)
			hit = {"position": Vector3(hp.x, ter.height_at(hp.x, hp.z), hp.z), "normal": Vector3.UP, "collider": null}
		if hit.is_empty():
			var fa := _farm_hit(a, b)
			if fa != null:
				hit = {"position": fa.global_position + Vector3(0, 0.45, 0), "normal": Vector3.UP, "collider": fa}
		if not hit.is_empty():
			_on_hit(pr, hit)
			_free_projectile(pr)
			projectiles.remove_at(i)
			continue
		pr["pos"] = b
		var node = pr["node"]
		if node != null and is_instance_valid(node):
			_orient(node, b, vel.normalized())
		if float(pr["t"]) > LIFE_S or b.distance_to(pr["start"]) > MAX_RANGE_M or b.y < -80.0:
			_free_projectile(pr)
			projectiles.remove_at(i)


func _free_projectile(pr: Dictionary) -> void:
	var node = pr["node"]
	if node != null and is_instance_valid(node):
		(node as Node).queue_free()
	pr["node"] = null


## Zvíře z vlastního hospodářství (nemá kolizi) na dráze úsečky a–b? (koule 0,6 m kolem trupu)
func _farm_hit(a: Vector3, b: Vector3) -> FarmAnimal:
	if world.farm == null:
		return null
	for fa in world.farm.animals:
		if not is_instance_valid(fa):
			continue
		var c: Vector3 = fa.global_position + Vector3(0, 0.45, 0)
		if Geometry3D.get_closest_point_to_segment(c, a, b).distance_to(c) < 0.6:
			return fa
	return null


func _energy(pr: Dictionary) -> float:
	return 0.5 * float(pr["mass"]) * (pr["vel"] as Vector3).length_squared()


func _on_hit(pr: Dictionary, hit: Dictionary) -> void:
	var col = hit.get("collider")
	var pos: Vector3 = hit["position"]
	var arrow := String(pr["kind"]) == "arrow"
	if col is StaticBody3D and (col as Node).has_meta("range_target"):
		_hit_range(pr, hit, col)
		if arrow:
			_stick(pr, pos)
		world.sound.emit(pos, "arrow_hit", randf_range(0.9, 1.1), -4.0, 80.0)
	elif col is Villager or col is Npc:
		_hit_person(pr, hit, col)
	elif col is Animal:
		_hit_animal(pr, hit, col)
	elif col is FarmAnimal or col is Dog or col is Horse:
		_hit_creature(pr, hit, col)
	elif col is Car:
		_hit_car(pr, hit, col)
	else:
		# terén, strom, zeď, rekvizita: šíp se zapíchne (2 min, jde sebrat), kulka jen udeří
		world.sound.emit(pos, "arrow_hit", randf_range(0.9, 1.1), -4.0 if arrow else 0.0, 80.0)
		if arrow:
			_stick(pr, pos)
	if col != null and not (col is StaticBody3D):
		world.sound.emit(pos, "arrow_hit", randf_range(0.9, 1.1), -6.0, 60.0)


func _hit_range(pr: Dictionary, hit: Dictionary, col: Node) -> void:
	if range_ == null:
		return
	var id := int(pr["id"])
	range_.on_hit(id, int(col.get_meta("range_target")), hit["position"], String(pr["w"]), pr["start"])
	world.emit_game_event(id, "range_hit", {"weapon": String(pr["w"]), "pos": hit["position"]})


func _info(pr: Dictionary, hit: Dictionary, kind: String, target: Object) -> Dictionary:
	var pos: Vector3 = hit["position"]
	return {"kind": kind, "target": target, "energy": _energy(pr), "pos": pos, "weapon": String(pr["w"]),
		"dist": pos.distance_to(pr["start"]), "dir": (pr["vel"] as Vector3).normalized(), "part": "telo"}


## Zvěř: událost `shot_hit` {kind "animal", target, species, part, energy, pos, weapon, dist, dir} – smrt a úlovek řeší `Hunting.animal_shot` (M2.9).
func _hit_animal(pr: Dictionary, hit: Dictionary, an: Animal) -> void:
	var d := _info(pr, hit, "animal", an)
	d["part"] = zone_of(an, hit["position"])
	d["species"] = an.species
	world.emit_game_event(int(pr["id"]), "shot_hit", d)
	if world.hunting:
		world.hunting.animal_shot(int(pr["id"]), d)    # M2.9: smrt / postřelení, legalita, pytláctví (luk a kuše = vždy)
	an.hear_shot(pr["start"], 25.0)


## Pes, kůň, zvíře z hospodářství: poškození cizí věci se svědkem; zvíře z hospodářství se zraní (nezabije – to řeší Farm).
func _hit_creature(pr: Dictionary, hit: Dictionary, target: Node) -> void:
	var id := int(pr["id"])
	var kind := "dog"
	if target is FarmAnimal:
		kind = "farm_animal"
		var fa := target as FarmAnimal
		fa.health = maxf(fa.health - 0.5, 0.05)
	elif target is Horse:
		kind = "horse"
	world.emit_game_event(id, "shot_hit", _info(pr, hit, kind, target))
	if _witness(id, hit["position"], 60.0):
		world.commit_offense(id, "poskozeni_veci", {"severity": clampf(_energy(pr) / 1500.0, 0.1, 1.0)})
		_msg(id, "Někdo tě viděl, jak střílíš do zvířete!", 3.5)


func _hit_car(pr: Dictionary, hit: Dictionary, car: Car) -> void:
	var id := int(pr["id"])
	world.emit_game_event(id, "shot_hit", _info(pr, hit, "car", car))
	if _witness(id, hit["position"], 80.0):
		world.commit_offense(id, "poskozeni_veci", {"severity": clampf(_energy(pr) / 1500.0, 0.2, 1.0)})
		_msg(id, "Postřelil jsi cizí auto – někdo tě viděl!", 3.0)


## Člověk: pád (vesničan), útěk okolních, trestný čin, pověst, pátrání policie (hledaný pěšky 8 h).
func _hit_person(pr: Dictionary, hit: Dictionary, who: Node) -> void:
	var id := int(pr["id"])
	var p := _player(id)
	var energy := _energy(pr)
	var pos: Vector3 = hit["position"]
	world.emit_game_event(id, "shot_hit", _info(pr, hit, "person", who))
	var dir := (pr["vel"] as Vector3).normalized()
	if who is Villager:
		(who as Villager).knock(Vector3(dir.x, 0.0, dir.z) * 2.5, 3.0)
	elif who is Npc:
		(who as Npc).say("Au! Zbláznil ses?!", 3.0)
	world.commit_offense(id, "ublizeni_na_zdravi", {"severity": clampf(energy / 2000.0, 0.2, 1.0)})
	var rep: Reputation = world.reputations.get(id)
	if rep:
		rep.change(-30.0, "postřelil člověka", "ublížení na zdraví")
	if p != null:
		p.wanted_until = maxf(p.wanted_until, _now_min() + 480.0)
	world.notify(id, "popup", ["Zasáhl jsi člověka! Policie po tobě jde.", 5.0])
	_scare_villagers(pos, 45.0, id, false, who)


# ------------------------------------------------------------------ zapíchnuté šípy

func _stick(pr: Dictionary, pos: Vector3) -> void:
	var spec: Dictionary = WEAPONS[String(pr["w"])]
	var vel: Vector3 = pr["vel"]
	var dir := vel.normalized()
	var alen := float(spec["len"])
	var node := arrow_model(alen, String(pr["w"]) == "kuse")
	add_child(node)
	if vel.length() >= STICK_MIN_SPEED:
		# zapíchnutý: hrot 12 cm pod povrchem
		_orient(node, pos + dir * 0.12 - dir * alen * 0.5, dir)
	else:
		# jen dopadl: leží na zemi
		var flat := Vector3(dir.x, 0.0, dir.z)
		flat = flat.normalized() if flat.length() > 0.01 else Vector3.FORWARD
		_orient(node, pos + Vector3(0, 0.03, 0) - flat * alen * 0.4, Vector3(flat.x, -0.05, flat.z).normalized())
	arrows.append({"node": node, "ammo": String(spec["ammo"]), "pos": pos, "t": STUCK_LIFE_S})
	while arrows.size() > STUCK_MAX:
		var old: Dictionary = arrows.pop_front()
		if is_instance_valid(old["node"]):
			(old["node"] as Node).queue_free()


func _tick_arrows(dt: float) -> void:
	for i in range(arrows.size() - 1, -1, -1):
		var a: Dictionary = arrows[i]
		a["t"] = float(a["t"]) - dt
		if float(a["t"]) <= 0.0 or not is_instance_valid(a["node"]):
			if is_instance_valid(a["node"]):
				(a["node"] as Node).queue_free()
			arrows.remove_at(i)


## Položky pro klávesu E: sebrání zapíchnutého šípu / šipky a skóre na střelnici.
func interactables(id: int) -> Array:
	var out := []
	var p := _player(id)
	if p == null:
		return out
	for a in arrows:
		if (a["pos"] as Vector3).distance_to(p.global_position) < 6.0:
			out.append({"pos": (a["pos"] as Vector3) + Vector3(0, 0.3, 0), "r": PICKUP_R, "kind": "custom",
				"text": "Sebrat %s" % ("šipku" if String(a["ammo"]) == "sipky_kuse" else "šíp"), "action": _pickup.bind(a)})
	if range_ != null:
		out.append_array(range_.interactables(id))
	return out


func _pickup(id: int, a: Dictionary) -> void:
	var p := _player(id)
	if p == null or not arrows.has(a):
		return
	arrows.erase(a)
	if is_instance_valid(a["node"]):
		(a["node"] as Node).queue_free()
	p.add_item(String(a["ammo"]))
	world.play_sfx(id, "pickup")
	_msg(id, "Sebráno: %s" % ItemsDB.name_of(String(a["ammo"])), 1.5)


# ------------------------------------------------------------------ zákon

## Nahlásí čin někdo poblíž `pos` (`World.witness_check`: vesničan, obsluha, hlídka) do `r` m?
func _witness(id: int, pos: Vector3, r: float) -> bool:
	return world.witness_reported(id, pos, "zbran", r, r)


func _cooldown_ok(id: int, offense: String) -> bool:
	var key := "%d:%s" % [id, offense]
	var now := _now_min()
	if now - float(_last_off.get(key, -1.0e9)) < float(OFFENSE_CD_MIN.get(offense, 10.0)):
		return false
	_last_off[key] = now
	return true


## Vzdálenost bodu od nejbližší osy silnice pro auta v okruhu `r` m (INF, když žádná).
func _road_dist(p2: Vector2, r: float) -> float:
	var g := world.graph
	if g == null:
		return INF
	var best := INF
	for i in g.nodes_within(p2, r, RoadGraph.CAR_KINDS):
		for j in g.adj[i]:
			if g.edge(i, j) in RoadGraph.CAR_KINDS:
				var q := Geometry2D.get_closest_point_to_segment(p2, g.nodes[i], g.nodes[j])
				best = minf(best, q.distance_to(p2))
	return best


## Kdo a proč výstřel postihne (volá `_fire`).
func _law_on_shot(id: int, p: Player, spec: Dictionary, pos: Vector3, dir: Vector3) -> void:
	var firearm := bool(spec["firearm"])
	var noise := float(spec["noise"])
	var hear := minf(noise, 350.0) if firearm else noise          # kdo výstřel uslyší a pozná, co to bylo
	var witness := _witness(id, pos, hear)
	var in_range := range_ != null and range_.is_shooting_lane(p.global_position, dir)
	# 1) zbraň bez oprávnění (puška): na střelnici ji hlídá myslivec, jinde stačí svědek
	var need := String(spec["permit"])
	if need != "" and not world.has_permit(id, need, pos):
		if in_range and _keeper_near("chata", 150.0, p):
			_seize(id, p, "puska", "chata")
		elif witness and _cooldown_ok(id, "nedovolene_ozbrojovani"):
			world.commit_offense(id, "nedovolene_ozbrojovani", {"severity": 0.4})
			_msg(id, "Někdo tě viděl střílet z pušky bez zbrojního oprávnění!", 4.0)
	# 2) zbraň pod vlivem (každý výstřel s promile > 0 se svědkem)
	var pm := p.body.promile()
	if pm > 0.0 and witness and _cooldown_ok(id, "zbran_pod_vlivem"):
		world.commit_offense(id, "zbran_pod_vlivem", {"severity": clampf(pm / 2.0, 0.0, 1.0)})
		_msg(id, "Střílíš pod vlivem alkoholu – někdo tě viděl!", 4.0)
	# 3) střelba v obci / do 100 m od silnice a domu (mimo střelnici)
	if in_range:
		return
	var settled := world.fauna != null and world.fauna.settle_at(pos.x, pos.z) > 0.5
	if settled or _road_dist(Vector2(pos.x, pos.z), 100.0) < 100.0:
		_scare_villagers(pos, minf(hear, 120.0), id, true, null)
		if witness and _cooldown_ok(id, "strelba_v_obci"):
			world.commit_offense(id, "strelba_v_obci", {"severity": 0.6 if firearm else 0.2})
			_msg(id, "Střelba v obci / u silnice – někdo tě viděl!", 4.0)


func _keeper_near(place_key: String, r: float, p: Player) -> bool:
	var pl: Place = world.places.get(place_key)
	return pl != null and pl.keeper != null and is_instance_valid(pl.keeper) and not pl.player_inside \
		and pl.keeper.global_position.distance_to(p.global_position) < r


## Myslivec / policie zabaví pušku (bez oprávnění): pokuta a záznam přes zákon, pověst, zpráva. Vrací true.
func _seize(id: int, p: Player, w: String, by: String) -> bool:
	var n := p.item_count(w)
	if n <= 0:
		return false
	p.remove_item(w, n)
	var res := world.commit_offense(id, "nedovolene_ozbrojovani", {"severity": 0.5, "quiet": true})
	var rep: Reputation = world.reputations.get(id)
	if rep:
		rep.change(-12.0, "zbraň bez zbrojního oprávnění", "nedovolené ozbrojování")
	if by == "chata":
		world.npc_say(id, "chata", "Bez zbrojního oprávnění tu střílet nebudeš! Pušku ti beru.")
	world.notify(id, "popup", ["ZBRAŇ ZABAVENA – puška bez zbrojního oprávnění.\nPokuta %d Kč, záznam v rejstříku." % int(res.get("fine", 0)), 6.0])
	world.emit_game_event(id, "weapon_seized", {"weapon": w, "by": by})
	return true


## Policejní kontrola (dechová zkouška, silniční kontrola, hlídka): puška v inventáři bez oprávnění se zabaví.
## Vrací true, když se něco zabavilo. `_context` jen pro ladění.
func police_check(id: int, _context := "") -> bool:
	var p := _player(id)
	if p == null:
		return false
	if p.item_count("puska") > 0 and not world.has_permit(id, "zbrojni", p.global_position):
		return _seize(id, p, "puska", "policie")
	return false


## Policejní hlídka u pěšího s nelegální puškou (nebo se zbraní pod vlivem): kontrola nejvýš jednou za 2 herní hodiny.
func _police_foot_check(id: int, p: Player) -> void:
	if p.car != null or p.horse != null or world.police == null:
		return
	var patrol = world.police.patrol
	if patrol == null or not is_instance_valid(patrol):
		return
	if patrol.global_position.distance_to(p.global_position) > 28.0:
		return
	var illegal := p.item_count("puska") > 0 and not world.has_permit(id, "zbrojni", p.global_position)
	var drunk_armed := WEAPONS.has(p.equipped) and p.body.promile() > 0.0
	if not illegal and not drunk_armed:
		return
	if not world.line_clear(patrol.global_position + Vector3(0, 1.3, 0), p.global_position + Vector3(0, 1.0, 0)):
		return
	if not _cooldown_ok(id, "policie_kontrola_zbrane"):
		return
	if illegal:
		police_check(id, "hlidka")
	else:
		world.commit_offense(id, "zbran_pod_vlivem", {"severity": clampf(p.body.promile() / 2.0, 0.0, 1.0)})
		world.notify(id, "police_banner", ["Policie: se zbraní v ruce pod vlivem alkoholu!", 4.0])


## Vesničané se zbraní v ruce / při míření: lekají se, utíkají, mohou volat policii. Jen v zástavbě a jen pěšky.
func _village_check(id: int, p: Player) -> void:
	if p.car != null or p.horse != null or p.inside != "":
		return
	var armed := p.equipped == "puska" or (WEAPONS.has(p.equipped) and p.aim_on)
	if not armed or world.fauna == null or world.fauna.settle_at(p.global_position.x, p.global_position.z) <= 0.5:
		return
	_scare_villagers(p.global_position, VILLAGE_R, id, true, null)
	# zbraň pod vlivem i bez výstřelu (svědek nablízku)
	if p.body.promile() > 0.0 and _witness(id, p.global_position, 30.0) and _cooldown_ok(id, "zbran_pod_vlivem"):
		world.commit_offense(id, "zbran_pod_vlivem", {"severity": clampf(p.body.promile() / 2.0, 0.0, 1.0)})
		_msg(id, "Někdo tě viděl se zbraní pod vlivem alkoholu!", 3.5)


## Vesničané do `radius` m se leknou: hláška, útěk; `allow_call` = někdo z nich může zavolat policii (hledaný pěšky 2 h).
func _scare_villagers(pos: Vector3, radius: float, id: int, allow_call: bool, except: Node) -> void:
	if world.bots_root == null:
		return
	var p := _player(id)
	var now := Time.get_ticks_msec() / 1000.0
	var called := false
	for v in world.bots_root.get_children():
		if not (v is Villager) or v == except:
			continue
		var vv := v as Villager
		if vv.global_position.distance_to(pos) > radius or vv.is_knocked():
			continue
		var key := vv.get_instance_id()
		if now - float(_scared.get(key, -1.0e9)) < SHOW_CD_S:
			continue
		_scared[key] = now
		vv.say(SCARED_LINES[randi() % SCARED_LINES.size()], 3.0)
		vv.flee_from(pos, 8.0)
		if allow_call and not called and p != null and vv.persona != null:
			var trait_key := String(vv.persona.profile.get("trait", ""))
			if randf() < float(CALL_P.get(trait_key, 0.4)):
				called = true
				p.wanted_until = maxf(p.wanted_until, _now_min() + 120.0)
				world.notify(id, "police_banner", ["%s volá policii! Hlídka po tobě jde." % vv.persona.display_name(), 4.0])
