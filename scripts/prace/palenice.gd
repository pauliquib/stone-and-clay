## Pomocník v pálenici (M3.3) – pracoviště práce „Pomocník v pálenici“ (`data/prace.json` → `palenice_pomocnik`, Pálenice U Kotla,
## sezóna IX–XII – `mesice` práce, st–so 8–16, k výplatě lahev slivovice – `naturalie`). Jeden uzel ve `World` (`World.palenice`).
##
## Venku u pálenice stojí měděný kotel na zděném topeništi, soudky s kvasem a stůl s lahvemi (jen vzhled, bez značek).
## - **Kvas** (`palenice_kvas`, typ „akce“ `nalit_kvas`): u soudků vzít soudek na rameno (`vzit_sud` → náklad M2.10) a vylít ho do kotle.
## - **Kotel** (`palenice_kotel`, typ „modul“): minihra – LMB u topeniště přiloží poleno (`on_click` z `World.player_action("use_tool")`
##   před kontextovými akcemi; polena zapůjčí palič, vlastní se použijí dřív), teplota kotle stoupá a sama klesá; drž ji
##   v zeleném pásmu `T_GREEN` celkem `GOOD_S` s. Nad `T_BURN` se pálenka připaluje (hodnocení −).
## - **Lahve** (`palenice_lahve`, typ „akce“ `plnit_lahve`): naplnit lahve na stole.
## Stav se neukládá (teplota kotle je jen na směně).
class_name PalenicePrace
extends Node3D

const JOB_ID := "palenice_pomocnik"
const PLACE := "palenice"
const TASK_KVAS := "palenice_kvas"
const TASK_HEAT := "palenice_kotel"
const T_AMB := 15.0
const T_START := 62.0                # °C – kotel na začátku úkolu (palič už zatopil)
const T_GREEN := [88.0, 96.0]        # °C – destilace jde, jak má
const T_BURN := 100.0                # °C – připaluje se
const HEAT_PER_LOG := 9.0            # °C, které jedno poleno přidá (postupně, `FIRE_RATE`)
const FIRE_RATE := 3.0               # °C/s – jak rychle se žár z polen předává kotli
const COOL_K := 0.018                # chladnutí za s × (T − T_AMB)
const GOOD_S := 40.0                 # s v zeleném pásmu = úkol hotový (DOPLNIT: délka)
const BURN_PENALTY_S := 5.0          # každých tolik s nad `T_BURN` hodnocení −0,5
const FIRE_R := 2.2                  # m (vodorovně) od topeniště – odsud se přikládá
const COPPER := Color(0.72, 0.42, 0.22)
const BRICK := Color(0.55, 0.25, 0.18)

var world: World
var kotel_pos := Vector3.INF         # střed kotle (u země)
var fire_pos := Vector3.INF          # dvířka topeniště
var sudy_pos := Vector3.INF
var table_pos := Vector3.INF
var _face := 0.0
var _glow: MeshInstance3D
var _s := {}                         # pid → {t, fire, good, burn, fire_t, sudy_t}


func setup(w: World) -> void:
	world = w
	name = "Palenice_prace"
	var pl: Place = w.places.get(PLACE)
	if pl == null:
		return
	_face = float(pl.data.get("face_yaw", 0.0))
	var b := Basis(Vector3.UP, _face)
	kotel_pos = _ground(pl.door + b * Vector3(-3.2, 0, 3.0))
	fire_pos = kotel_pos + b * Vector3(0, 0.35, 0.75)
	sudy_pos = _ground(pl.door + b * Vector3(-5.6, 0, 1.2))
	table_pos = _ground(pl.door + b * Vector3(-0.9, 0, 3.6))
	_build()
	Jobs.set_provider("palenice_kotel", func(_w: World, _id: int, _j: Dictionary) -> Array:
		return [kotel_pos + Vector3(0.25, 1.5, 0), kotel_pos + Vector3(-0.25, 1.5, 0)])
	Jobs.set_provider("palenice_topeniste", func(_w: World, _id: int, _j: Dictionary) -> Array: return [fire_pos])
	Jobs.set_provider("palenice_lahve", func(_w: World, _id: int, _j: Dictionary) -> Array: return _bottle_points())
	Actions.set_handler("vzit_sud", func(id: int, _d: Dictionary, _a: Dictionary, ok: bool) -> void:
		if ok and world.cargo and world.cargo.shoulder_new(id, "sud"):
			world.notify(id, "show_message", ["Neseš soudek s kvasem (30 kg) – vylij ho do kotle (LMB na kotel).", 3.0]))
	Actions.set_handler("nalit_kvas", func(id: int, _d: Dictionary, _a: Dictionary, ok: bool) -> void:
		if ok and world.cargo:
			world.cargo.consume_carried(id)
			world.sound.emit(kotel_pos, "splash", 0.8, -4.0, 40.0))
	Actions.chain_target_check("nalit_kvas", func(_aim: Dictionary, id: int) -> String:
		return "" if world.cargo and world.cargo.carried_kind(id) == "sud" else "Nejdřív přines soudek s kvasem (u soudků vedle pálenice).")
	Actions.chain_target_check("vzit_sud", func(_aim: Dictionary, id: int) -> String:
		if world.cargo == null:
			return "Náklad není k dispozici."
		return "Už něco neseš." if world.cargo.carried_kind(id) != "" or world.cargo.hands_busy(id) else "")


func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, world.terrain.height_at(p.x, p.z), p.z)


func _bottle_points() -> Array:
	var b := Basis(Vector3.UP, _face)
	var out := []
	for i in 4:
		out.append(table_pos + b * Vector3(-0.45 + i * 0.3, 0.95, 0))
	return out


## Kotel na zděném topeništi s dvířky a komínkem, soudky, stůl s lahvemi (jeden draw call na skupinu).
func _build() -> void:
	var k := MeshKit.new()
	k.box(Vector3(0, 0.4, 0), Vector3(1.3, 0.8, 1.3), BRICK)
	k.box(Vector3(0, 0.35, 0.66), Vector3(0.4, 0.32, 0.02), Color(0.12, 0.12, 0.12))           # dvířka topeniště
	k.cylinder(Vector3(0, 1.2, 0), 0.5, 0.58, 0.8, COPPER, Vector3.ZERO, 16)
	k.sphere(Vector3(0, 1.62, 0), 0.42, COPPER, Vector3(1.0, 0.55, 1.0))
	k.cylinder(Vector3(0.45, 1.85, 0), 0.05, 0.05, 0.9, COPPER.darkened(0.1), Vector3(0, 0, -1.1), 8)   # přilba – trubka
	k.cylinder(Vector3(-0.5, 1.6, -0.5), 0.08, 0.08, 2.4, Color(0.25, 0.25, 0.27), Vector3.ZERO, 8)        # komínek
	var mi := MeshKit.mesh_instance(self, k.commit(MeshKit.vc_material(0.45, 0.5)), 160.0)
	mi.position = kotel_pos
	mi.rotation.y = _face
	var g := MeshKit.new()
	g.box(Vector3(0, 0.35, 0.675), Vector3(0.34, 0.26, 0.01), Color(1.0, 0.45, 0.1))
	_glow = MeshKit.mesh_instance(self, g.commit(MeshKit.vc_material(0.9, 0.0, 2.0)), 80.0)
	_glow.position = kotel_pos
	_glow.rotation.y = _face
	_glow.visible = false
	var ks := MeshKit.new()
	for i in 4:
		var x := -0.5 + (i % 2) * 0.5
		var y := 0.3 + (i / 2) * 0.62
		ks.cylinder(Vector3(x, y, 0), 0.2, 0.2, 0.6, Color(0.45, 0.3, 0.17), Vector3.ZERO, 12)
		ks.cylinder(Vector3(x, y, 0), 0.235, 0.235, 0.26, Color(0.5, 0.35, 0.2), Vector3.ZERO, 12)
	var ms := MeshKit.mesh_instance(self, ks.commit(MeshKit.vc_material(0.85)), 150.0)
	ms.position = sudy_pos
	ms.rotation.y = _face
	var kt := MeshKit.new()
	kt.box(Vector3(0, 0.85, 0), Vector3(1.4, 0.05, 0.6), Color(0.55, 0.4, 0.25))
	for sx in [-0.62, 0.62]:
		for sz in [-0.24, 0.24]:
			kt.box(Vector3(sx, 0.42, sz), Vector3(0.06, 0.84, 0.06), Color(0.45, 0.32, 0.2))
	for i in 4:
		kt.cylinder(Vector3(-0.45 + i * 0.3, 1.0, 0), 0.04, 0.04, 0.26, Color(0.85, 0.9, 0.88), Vector3.ZERO, 8)
		kt.cylinder(Vector3(-0.45 + i * 0.3, 1.16, 0), 0.015, 0.015, 0.08, Color(0.85, 0.9, 0.88), Vector3.ZERO, 6)
	var mt := MeshKit.mesh_instance(self, kt.commit(MeshKit.vc_material(0.5)), 120.0)
	mt.position = table_pos
	mt.rotation.y = _face


# ------------------------------------------------------------------ průběh

func _active(id: int, task: String) -> bool:
	var jb: Jobs = world.jobs.get(id)
	return jb != null and jb.on_shift(JOB_ID) and jb.task_id() == task


func _state(id: int) -> Dictionary:
	if not _s.has(id):
		_s[id] = {"t": T_START, "fire": 0.0, "good": 0.0, "burn": 0.0, "fire_t": {}, "sudy_t": {}, "shown": false}
	return _s[id]


func _near_fire(id: int) -> bool:
	var p: Player = world.players.get(id)
	if p == null or fire_pos == Vector3.INF:
		return false
	var d := fire_pos - p.global_position
	return Vector2(d.x, d.z).length() <= FIRE_R and absf(d.y) < 2.5


## LMB od hráče (volá `World.player_action("use_tool")` před kontextovými akcemi). True = klik patřil topeništi.
func on_click(id: int) -> bool:
	if not _active(id, TASK_HEAT) or not _near_fire(id):
		return false
	var p: Player = world.players.get(id)
	if not p.remove_item("polena", 1):
		world.notify(id, "show_message", ["Došla polena – požádej paliče (nový úkol) nebo přines vlastní.", 2.5])
		return true
	var jb: Jobs = world.jobs.get(id)
	if jb:
		jb.unlend("polena", 1)
	var s := _state(id)
	s["fire"] = float(s["fire"]) + HEAT_PER_LOG
	world.sound.emit(fire_pos, "thud", randf_range(1.2, 1.4), -8.0, 30.0)
	world.give_xp(id, "ohen", 1.0, "topení pod kotlem")
	return true


func _process(delta: float) -> void:
	if world == null or kotel_pos == Vector3.INF:
		return
	var glow := false
	for id_v in world.players:
		var id := int(id_v)
		var jb: Jobs = world.jobs.get(id)
		if jb == null or not jb.on_shift(JOB_ID):
			if _s.has(id):
				_reset(id)
			continue
		var s := _state(id)
		_targets(id, s)
		if _active(id, TASK_HEAT):
			_tick_heat(id, s, delta)
			glow = glow or float(s["t"]) > 50.0
		elif bool(s["shown"]):
			s["shown"] = false
			world.notify(id, "action_progress", ["", -1.0])
	if _glow:
		_glow.visible = glow


## Cíle, které registruje modul (ne Jobs): soudky při úkolu „Kvas“ s volnýma rukama, topeniště při úkolu „Kotel“.
func _targets(id: int, s: Dictionary) -> void:
	var want_sudy := _active(id, TASK_KVAS) and world.cargo != null and world.cargo.carried_kind(id) == ""
	s["sudy_t"] = _toggle_target(s["sudy_t"], want_sudy, sudy_pos + Vector3(0, 0.7, 0), "job_sudy", id)
	s["fire_t"] = _toggle_target(s["fire_t"], _active(id, TASK_HEAT), fire_pos, "job_topeniste", id)


func _toggle_target(t: Dictionary, want: bool, pos: Vector3, kind: String, id: int) -> Dictionary:
	if want and t.is_empty():
		t = {"pos": pos, "r": 1.3, "kind": kind, "data": {"pid": id, "job": JOB_ID}}
		world.register_target(t)
	elif not want and not t.is_empty():
		world.unregister_target(t)
		t = {}
	return t


## Teplota kotle: žár z přiložených polen ji zvedá, sama chladne; zelené pásmo počítá čas, přehřátí hodnocení.
func _tick_heat(id: int, s: Dictionary, delta: float) -> void:
	var t := float(s["t"])
	var add := minf(float(s["fire"]), FIRE_RATE * delta)
	s["fire"] = float(s["fire"]) - add
	t += add - COOL_K * (t - T_AMB) * delta
	s["t"] = t
	var green := t >= float(T_GREEN[0]) and t <= float(T_GREEN[1])
	if green:
		s["good"] = float(s["good"]) + delta
	if t > T_BURN:
		s["burn"] = float(s["burn"]) + delta
		if float(s["burn"]) >= BURN_PENALTY_S:
			s["burn"] = 0.0
			var jb: Jobs = world.jobs.get(id)
			if jb:
				jb.adjust_rating(-0.5)
			world.notify(id, "show_message", ["Palič: „Moc topíš, připaluje se to! Uber!“", 3.0])
	var p: Player = world.players.get(id)
	var near := p != null and p.global_position.distance_to(kotel_pos) < 12.0
	if near:
		s["shown"] = true
		var zone := "ZELENÁ – drž to" if green else ("přilož!" if t < float(T_GREEN[0]) else "moc horké!")
		world.notify(id, "action_progress", ["Kotel %d °C (zelená %d–%d °C) – %s · %d / %d s" % [roundi(t), roundi(float(T_GREEN[0])),
			roundi(float(T_GREEN[1])), zone, int(s["good"]), int(GOOD_S)], clampf(t / 110.0, 0.0, 1.0)])
	elif bool(s["shown"]):
		s["shown"] = false
		world.notify(id, "action_progress", ["", -1.0])
	if float(s["good"]) >= GOOD_S:
		s["good"] = 0.0
		world.notify(id, "action_progress", ["", -1.0])
		s["shown"] = false
		var jb2: Jobs = world.jobs.get(id)
		if jb2:
			jb2.progress(TASK_HEAT)


func _reset(id: int) -> void:
	var s: Dictionary = _s[id]
	for k in ["sudy_t", "fire_t"]:
		var t: Dictionary = s[k]
		if not t.is_empty():
			world.unregister_target(t)
	if bool(s["shown"]):
		world.notify(id, "action_progress", ["", -1.0])
	_s.erase(id)
