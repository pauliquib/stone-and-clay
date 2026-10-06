class_name HasiciSport
extends Node3D
## Hasičský sport (M5.4): základna požárního útoku u hřiště – mašina, káď, dva nástřikové terče 90 m od základny.
## Pokus = pět až šest fází za sebou (sání, motor, hadice B, rozdělovač, plnění, proudy). Hráč hraje svou roli
## (QTE: E v pruhu na ukazateli, LMB u plynu, u proudaře běh 70 m a míření), ostatní role běží NPC časy podle „formy“.
## Čas = skutečné sekundy od výstřelu do naplnění obou terčů; chyby přidávají zdržení, rozpojená hadice = N.P.
##
## - trénink: středa 18–19 h u základny (člen SDH), kdykoli opakovaně; forma (počet tréninků) zkracuje časy NPC
## - soutěž: první sobota v červnu, NPC družstva z `data/hasicsky_sport.json`, pořadí v tabulce, vítěz → respekt + pověst
## - ladicí hodnoty v `data/hasicsky_sport.json` (fáze, pokuty, pruh, míření, tým); datum soutěže je konstanta níže
## - napojení: `World.hasici_sport` (vytvoří World za zbrojnicí), `World.use_tool` → `on_click`, `World.interactables`,
##   `save_game.gd` (klíč `hasicsport`), kalendář soutěže se hlásí do `VillageEvents.register`

const DATA_PATH := "res://data/hasicsky_sport.json"
const NAME_BASE := "SDH Pod Kopcem"
const BASE_DX := -57.0            # m od středu hřiště k západu (základna 12 m za čárou)
const PLAY_R := 4.0               # m od základny – hraní a nabídka
const SOUTEZ_MESIC := 6           # soutěž: první sobota v červnu
const SOUTEZ_DEN_MAX := 7
const SOUTEZ_TEXT := "Hasičská soutěž SDH Pod Kopcem · požární útok · 10 h · u hřiště"
const FORMA_MAX := 20
const XP_SKILL := "hasicina"
const KONDICE_SKILL := "kondice"
const ROLES := ["stojnik", "kos", "savice1", "savice2", "becko", "rozdelovac", "proudar_l", "proudar_r"]
const ROLE_NAMES := {"stojnik": "strojník", "kos": "koš", "savice1": "savice 1", "savice2": "savice 2",
	"becko": "béčko", "rozdelovac": "rozdělovač", "proudar_l": "proudař levý", "proudar_r": "proudař pravý"}
## Fáze: klíč, role v dané fázi (prázdné = automatická fáze)
const STAGES := [
	["sani", ["kos", "savice1", "savice2"]],
	["motor", ["stojnik"]],
	["hadice", ["becko"]],
	["rozdelovac", ["rozdelovac"]],
	["plneni", []],
	["proudy", ["proudar_l", "proudar_r"]],
]
const STAGE_NAMES := {"sani": "sání a savice", "motor": "motor a plyn", "hadice": "hadice B",
	"rozdelovac": "rozdělovač", "plneni": "plnění hadic", "proudy": "proudy na terče"}
const BAR_N := 20
const BOARD_Y := 3.2
const COL_BASE := Color(0.5, 0.5, 0.52)
const COL_PUMP := Color(0.8, 0.12, 0.1)
const COL_TANK := Color(0.2, 0.4, 0.75)
const COL_TERC := Color(0.92, 0.9, 0.82)
const COL_POST := Color(0.45, 0.32, 0.2)

var world: World
var _base := Vector3.ZERO
var _cfg := {}
var _rng := RandomNumberGenerator.new()
var _run := {}                    # aktivní pokus, {} = volno
var _stages: Array = []           # fáze aktivního pokusu: [{key, roles, player, npc, base}]
var _si := 0
var _pid := -1
var _form := {}                   # id → počet tréninků (forma)
var _best := {}                   # id → nejlepší platný čas (s)
var _soutez_jd := {}              # id → jd poslední účasti v soutěži
var _record := 0.0                # rekord sboru (s), 0 = zatím žádný
var _board: Label3D
var _bar: Label3D
var _terc_lbl := {}               # role → Label3D (stav terče)
var _terc_light := {}             # role → OmniLight3D
var _terc_fill := {}              # role → 0..1 (vizuál)


func setup(w: World) -> void:
	world = w
	_rng.randomize()
	_cfg = _load_cfg()
	_base = Vector3(FotbalHriste.CENTER.x + BASE_DX, 0.0, FotbalHriste.CENTER.y)
	_base.y = w.terrain.height_at(_base.x, _base.z)
	position = _base
	_build()
	if w.village_events:
		w.village_events.register("hasici_soutez", Callable(HasiciSport, "soutez_day"), SOUTEZ_TEXT)


static func _load_cfg() -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if d is Dictionary:
		return d
	push_warning("Hasičský sport: chybí nebo je vadný %s." % DATA_PATH)
	return {}


func _f(key: String, def: float) -> float:
	return float(_cfg.get(key, def))


## Soutěž: první sobota v červnu (jd % 7 == 5 je sobota, viz Clock.weekday).
static func soutez_day(jd: int) -> bool:
	var d := Clock.from_jdn(jd)
	return int(d["month"]) == SOUTEZ_MESIC and jd % 7 == 5 and int(d["day"]) <= SOUTEZ_DEN_MAX


# ------------------------------------------------------------------ stavba

func _ground(x: float, z: float) -> float:
	return world.terrain.height_at(x, z)


func _terc_local(role: String) -> Vector3:
	var z := -_f("terce_z", 4.0) if role == "proudar_l" else _f("terce_z", 4.0)
	var x := -_f("terce_m", 90.0)
	var wy := _ground(_base.x + x, _base.z + z)
	return Vector3(x, wy - _base.y + 1.6, z)


func _build() -> void:
	var kit := MeshKit.new()
	kit.box(Vector3(0.0, 0.05, 0.0), Vector3(2.4, 0.1, 2.4), COL_BASE)               # podložka 2 × 2 m
	kit.box(Vector3(-0.9, 0.55, 0.0), Vector3(1.3, 0.9, 0.7), COL_PUMP)              # mašina PS 12
	kit.cylinder(Vector3(1.4, 0.4, 0.0), 0.9, 0.9, 0.8, COL_TANK)                    # káď 1 000 l
	for role in ["proudar_l", "proudar_r"]:
		var lp := _terc_local(role)
		kit.box(Vector3(lp.x, 0.8, lp.z), Vector3(0.1, 0.12, 0.12), COL_POST)
		kit.box(Vector3(lp.x, lp.y, lp.z), Vector3(0.12, 1.6, 0.9), COL_TERC)         # terč (kolmo k základně)
	MeshKit.mesh_instance(self, kit.commit(MeshKit.vc_material(0.85, 0.0, 0.0, false)))
	for role in ["proudar_l", "proudar_r"]:
		var lp := _terc_local(role)
		var li := OmniLight3D.new()
		li.position = lp + Vector3(0.6, 1.4, 0.0)
		li.omni_range = 6.0
		li.light_color = Color(0.4, 1.0, 0.5)
		li.light_energy = 0.0
		add_child(li)
		_terc_light[role] = li
		_terc_fill[role] = 0.0
		var tl := Label3D.new()
		tl.text = "0 %"
		tl.position = lp + Vector3(0.0, 1.3, 0.0)
		tl.pixel_size = 0.01
		tl.font_size = 32
		add_child(tl)
		_terc_lbl[role] = tl
	_board = Label3D.new()
	_board.position = Vector3(0.0, BOARD_Y, 0.0)
	_board.pixel_size = 0.012
	_board.font_size = 36
	_board.modulate = Color(0.95, 0.95, 0.9)
	_board.outline_size = 8
	add_child(_board)
	_bar = Label3D.new()
	_bar.position = Vector3(0.0, BOARD_Y - 0.6, 0.0)
	_bar.pixel_size = 0.012
	_bar.font_size = 36
	_bar.modulate = Color(1.0, 0.95, 0.6)
	_bar.outline_size = 8
	add_child(_bar)
	_update_board()


# ------------------------------------------------------------------ nabídka a členové

func interactables(id: int) -> Array:
	var out: Array = []
	if world == null or world.hasici == null:
		return out
	var p: Player = world.players.get(id)
	if p == null or p.inside != "" or p.car != null:
		return out
	if _hdist(p.global_position, _base) > PLAY_R:
		return out
	var at := _base + Vector3(0.0, 0.3, 0.0)
	if _run.is_empty():
		out.append({"pos": at, "r": 3.0, "kind": "custom",
			"text": "Požární útok – hasičský sport (trénink, soutěž)", "action": _menu})
	elif _pid == id and _player_stage() and not _player_stage_done() and _stage_key() != "proudy" \
			and not (_stage_key() == "motor" and int(_run["phase"]) == 1):
		out.append({"pos": at, "r": 3.0, "kind": "custom",
			"text": "E – %s" % _hint(), "action": _press})
	return out


func _menu(id: int) -> void:
	var opts: Array = []
	var text := "Trénink: středa 18–19 h. Soutěž: první sobota v červnu. Hraje se na čas, v roli podle výběru."
	var m := world.hasici
	if m == null or not m.is_member(id):
		text = "Požární útok je jen pro členy SDH (zbrojnice u úřadu).\n" + text
		opts.append(["Zavřít", func(): pass])
		world.notify(id, "open_menu", ["Hasičský sport", text, opts])
		return
	var jd: int = world.clock.jd()
	text += "\nOsobní rekord: %s · rekord sboru: %s" % [_fmt_t(float(_best.get(id, 0.0))), _fmt_t(_record)]
	if _is_training_now():
		for role in ROLES:
			opts.append(["Trénink – hrát %s" % ROLE_NAMES[role], _start.bind(id, role, "trenink")])
	else:
		text += "\nTrénink teď neprobíhá (středa 18–19 h)."
	if soutez_day(jd):
		if int(_soutez_jd.get(id, -1)) == jd:
			text += "\nSoutěž: dnes jsi už jel(a)."
		else:
			for role in ROLES:
				opts.append(["Soutěž – hrát %s" % ROLE_NAMES[role], _start.bind(id, role, "soutez")])
	opts.append(["Zavřít", func(): pass])
	world.notify(id, "open_menu", ["Hasičský sport – %s" % NAME_BASE, text, opts])



func _is_training_now() -> bool:
	var tr: Dictionary = _cfg.get("trenink", {})
	var hrs: Array = tr.get("hodiny", [18.0, 19.0])
	var h: float = world.clock.hour()
	return world.clock.weekday() == int(tr.get("den", 2)) and h >= float(hrs[0]) and h < float(hrs[1])


func _msg(id: int, text: String, dur := 4.0) -> void:
	world.notify(id, "show_message", [text, dur])


# ------------------------------------------------------------------ start pokusu

func _start(id: int, role: String, mode: String) -> void:
	if not _run.is_empty():
		_msg(id, "Pokus už běží.")
		return
	var p: Player = world.players.get(id)
	if p == null:
		return
	var jd: int = world.clock.jd()
	if mode == "soutez" and int(_soutez_jd.get(id, -1)) == jd:
		_msg(id, "Soutěž jsi dnes už absolvoval(a).")
		return
	_pid = id
	_si = 0
	_stages = _make_stages(id, role)
	_run = {"role": role, "mode": mode, "t": 0.0, "fault": "", "pressure": 1.0, "left": 0.0,
		"player_done": true, "qte_t": 0.0, "phase": 0, "tries": 0, "dist": 0.0, "pen": 0.0}
	_msg(id, "Výstřel! Start – hraješ: %s (%s)." % [ROLE_NAMES[role], "soutěž" if mode == "soutez" else "trénink"], 4.0)
	_enter_stage()


func _make_stages(id: int, role: String) -> Array:
	var out: Array = []
	var st: Dictionary = _cfg.get("faze_s", {})
	var mult := maxf(_f("forma_min", 0.75), 1.0 - _f("forma_krok", 0.03) * float(_form.get(id, 0)))
	var rozptyl := _f("rozptyl", 0.1)
	for pair in STAGES:
		var key: String = pair[0]
		var roles: Array = pair[1]
		var base := float(st.get(key, 2.0))
		var npc := 0.0
		for r in roles:
			if r != role:
				npc = maxf(npc, base * mult * _rng.randf_range(1.0 - rozptyl, 1.0 + rozptyl))
		out.append({"key": key, "roles": roles, "player": role in roles, "npc": npc, "base": base})
	return out


func _enter_stage() -> void:
	if _si >= _stages.size():
		_finish()
		return
	var s: Dictionary = _stages[_si]
	if s["key"] == "plneni":
		s["npc"] = float(s["base"]) / maxf(float(_run["pressure"]), 0.1)
	_run["left"] = float(s["npc"])
	_run["player_done"] = not bool(s["player"])
	_run["qte_t"] = 0.0
	_run["phase"] = 0
	_run["tries"] = 0
	if bool(s["player"]):
		_msg(_pid, _prompt(String(s["key"])), 5.0)


func _prompt(key: String) -> String:
	match key:
		"motor":
			return "Strojníku: E v pruhu na ukazateli – nastartuj motor (%d pokusy)." % int(_f("start_pokusy", 3))
		"proudy":
			return "Proudaři: běž aspoň %d m k terči a mír proudnicí (%.1f s)." % [int(_f("dobeh_m", 70.0)), _f("mireni_s", 2.5)]
	return "E v pruhu na ukazateli – %s." % STAGE_NAMES.get(key, "")


func _hint() -> String:
	return _prompt(_stage_key()).split(".")[0] if _stage_key() != "" else ""


# ------------------------------------------------------------------ průběh

func _process(delta: float) -> void:
	if world == null:
		return
	if not _run.is_empty():
		_tick_run(delta)
	_update_board()


func _tick_run(delta: float) -> void:
	_run["t"] = float(_run["t"]) + delta
	var p: Player = world.players.get(_pid)
	if p == null:
		_end_run("odpojen")
		return
	var cur := _hdist(p.global_position, _base)
	_run["dist"] = maxf(float(_run["dist"]), cur)
	var is_proudar := String(_run["role"]).begins_with("proudar")
	var limit := _f("odchod_proudar_m", 120.0) if is_proudar else _f("odchod_m", 30.0)
	if cur > limit:
		_msg(_pid, "Odešel jsi od stroje – pokus je zrušen (N.P.).", 4.0)
		_run["fault"] = "odchod od stroje"
		_end_run("odchod")
		return
	var s: Dictionary = _stages[_si]
	if bool(s["player"]) and not bool(_run["player_done"]):
		if s["key"] == "motor" and int(_run["phase"]) == 0:
			_run["qte_t"] = float(_run["qte_t"]) + delta
			if float(_run["qte_t"]) > _f("timeout_s", 6.0):
				_add_pen(_f("timeout_pen_s", 3.0), "Motor se nerozbíhá – čas ubíhá.")
				_run["phase"] = 1
				_run["qte_t"] = 0.0
		elif s["key"] == "proudy":
			_aim(delta, p)
		elif s["key"] != "motor":
			_run["qte_t"] = float(_run["qte_t"]) + delta
			if float(_run["qte_t"]) > _f("timeout_s", 6.0):
				_add_pen(_f("timeout_pen_s", 3.0), "Pozdě – zdržení.")
				_run["player_done"] = true
		if s["key"] == "motor" and int(_run["phase"]) == 1 and not bool(_run["player_done"]):
			_run["qte_t"] = float(_run["qte_t"]) + delta
			if float(_run["qte_t"]) > _f("timeout_s", 6.0):
				_add_pen(_f("timeout_pen_s", 3.0), "Plyn zůstal nevyužitý – tlak klesá.")
				_run["pressure"] = _f("tlak_pomalu", 0.8)
				_run["player_done"] = true
	var left := float(_run["left"])
	if left > 0.0:
		_run["left"] = left - delta
	if s["key"] == "proudy":
		var tot := float(s["npc"])
		var npc_fill := 1.0 if tot <= 0.0 else clampf(1.0 - float(_run["left"]) / tot, 0.0, 1.0)
		for r in s["roles"]:
			if r != _run["role"]:
				_set_fill(r, npc_fill)
	if float(_run["left"]) <= 0.0 and bool(_run["player_done"]):
		_si += 1
		_enter_stage()


func _add_pen(sec: float, text: String) -> void:
	_run["left"] = float(_run["left"]) + sec
	_run["pen"] = float(_run["pen"]) + sec
	_msg(_pid, text, 3.0)


func _player_stage() -> bool:
	return not _run.is_empty() and bool(_stages[_si]["player"])


func _player_stage_done() -> bool:
	return _run.is_empty() or bool(_run["player_done"])


func _stage_key() -> String:
	if _run.is_empty() or _si >= _stages.size():
		return ""
	return String(_stages[_si]["key"])


## Pulz ukazatele 0..1 (sinus, perioda z dat).
func _pulse() -> float:
	if _run.is_empty():
		return 0.5
	return 0.5 + 0.5 * sin(TAU * float(_run["t"]) / maxf(_f("perioda_s", 1.2), 0.1))


func _press(id: int) -> void:
	if _run.is_empty() or id != _pid or not _player_stage() or _player_stage_done():
		return
	var key := _stage_key()
	var v := _pulse()
	var pruh := _f("pruh", 0.85)
	var tol := _f("pruh_tol", 0.1)
	if key == "motor" and int(_run["phase"]) == 0:
		if absf(v - pruh) <= tol:
			_run["phase"] = 1
			_run["qte_t"] = 0.0
			_msg(_pid, "Motor naskočil. Teď plyn: LMB v zelené zóně.", 4.0)
		else:
			_run["tries"] = int(_run["tries"]) + 1
			if int(_run["tries"]) >= int(_f("start_pokusy", 3)):
				_add_pen(_f("start_pokus_pen_s", 0.8), "Studený motor – naskočil až napotřetí.")
				_run["phase"] = 1
				_run["qte_t"] = 0.0
			else:
				_add_pen(_f("start_pokus_pen_s", 0.8), "Motor nenaskočil (%d/%d)." % [int(_run["tries"]), int(_f("start_pokusy", 3))])
		return
	if key == "motor" or key == "proudy":
		return
	if absf(v - pruh) <= tol:
		_msg(_pid, "V pruhu – %s je hotové." % STAGE_NAMES.get(key, ""), 3.0)
		_run["player_done"] = true
	else:
		_add_pen(_f("pokus_pen_s", 1.5), "Mimo pruh – zdržení.")
		_run["player_done"] = true


## LMB: plyn u strojníka (fáze 2 motoru). Vrací true, když akci spotřeboval.
func on_click(id: int) -> bool:
	if _run.is_empty() or id != _pid or not _player_stage() or _player_stage_done():
		return false
	if _stage_key() != "motor" or int(_run["phase"]) != 1:
		return false
	var v := _pulse()
	var stred := _f("plyn_stred", 0.5)
	var tol := _f("plyn_tol", 0.12)
	var cerv := _f("plyn_cervena", 0.9)
	if absf(v - stred) <= tol:
		_run["pressure"] = 1.0
		_run["player_done"] = true
		_msg(_pid, "Zelená zóna – tlak 100 %.", 3.0)
	elif v >= cerv or v <= 1.0 - cerv:
		_run["fault"] = "rozpojená hadice (příliš plynu)"
		_run["pressure"] = _f("tlak_pomalu", 0.8)
		_run["player_done"] = true
		_msg(_pid, "Moc plynu – hadice se rozpojila! Pokus je N.P.", 4.0)
	else:
		_run["pressure"] = _f("tlak_pomalu", 0.8)
		_add_pen(_f("pomalu_pen_s", 1.0), "Mimo zónu – slabší tlak.")
		_run["player_done"] = true
	return true


## Proudař: po doběhu 70 m míří proudnicí na svůj terč; plní se jen při míření.
func _aim(delta: float, p: Player) -> void:
	var role := String(_run["role"])
	if float(_run["dist"]) < _f("dobeh_m", 70.0):
		return
	var cam := p.camera
	if cam == null:
		return
	var target := to_global(_terc_local(role))
	var dir := (target - cam.global_position).normalized()
	var fwd := -cam.global_transform.basis.z
	if fwd.dot(dir) >= _f("mireni_cos", 0.96):
		var f := minf(1.0, float(_terc_fill.get(role, 0.0)) + delta / maxf(_f("mireni_s", 2.5), 0.1))
		_set_fill(role, f)
		if f >= 1.0:
			_run["player_done"] = true
			_msg(_pid, "Terč je plný!", 3.0)


func _set_fill(role: String, f: float) -> void:
	_terc_fill[role] = clampf(f, 0.0, 1.0)
	var li: OmniLight3D = _terc_light.get(role)
	if li:
		li.light_energy = 2.5 if f >= 1.0 else 0.0
	var tl: Label3D = _terc_lbl.get(role)
	if tl:
		tl.text = "%d %%" % int(round(clampf(f, 0.0, 1.0) * 100.0))


# ------------------------------------------------------------------ konec pokusu

func _end_run(_why: String) -> void:
	_finish()


func _finish() -> void:
	var pid := _pid
	var t := float(_run.get("t", 0.0))
	var fault := String(_run.get("fault", ""))
	var mode := String(_run.get("mode", "trenink"))
	var valid := fault == ""
	var rep: Reputation = world.reputations.get(pid)
	var sk: Skills = world.skills.get(pid)
	var jd: int = world.clock.jd()
	var text := ""
	if valid:
		var new_rec := false
		if _record <= 0.0 or t < _record:
			_record = t
			new_rec = true
		var best := float(_best.get(pid, 0.0))
		var own := best <= 0.0 or t < best
		if own:
			_best[pid] = t
		_form[pid] = mini(FORMA_MAX, int(_form.get(pid, 0)) + 1)
		var xr: Array = _cfg.get("xp_hasicina", [10.0, 30.0])
		if sk:
			sk.add_xp(XP_SKILL, _rng.randf_range(float(xr[0]), float(xr[1])), "požární útok")
			sk.add_xp(KONDICE_SKILL, _f("xp_kondice", 10.0), "požární útok")
		if mode == "trenink" and rep:
			rep.change_respect("hasici", _f("trenink_respekt", 0.5), "trénink požárního útoku")
		text = "Čas: %s" % _fmt_t(t)
		if new_rec:
			text += " · Nový rekord sboru!"
		elif own:
			text += " · Osobní rekord."
	else:
		text = "N.P. – %s (čas %s)" % [fault, _fmt_t(t)]
	if mode == "soutez":
		_soutez_jd[pid] = jd
		var rows := _competition_rows(pid, t, valid)
		var lines := ""
		var i := 1
		var my_rank := 0
		for row in rows:
			if row[1] == "Ty":
				my_rank = i
			lines += "%d. %s – %s\n" % [i, row[1], row[2]]
			i += 1
		if my_rank == 1 and valid and rep:
			rep.change_respect("hasici", _f("soutez_respekt", 10.0), "vítěz soutěže SDH")
			rep.change(_f("soutez_povest", 5.0), "vítěz hasičské soutěže")
			lines += "Vítězství! Pohár jde do klubovny."
		world.notify(pid, "open_menu", ["Výsledková tabule – hasičská soutěž",
			"Kategorie muži (smyšlená soutěž)\n" + lines, [["Zavřít", func(): pass]]])
	else:
		_msg(pid, text, 6.0)
	_run = {}
	_stages = []
	_si = 0
	_pid = -1
	for role in _terc_fill.keys():
		_set_fill(role, 0.0)


## Výsledky soutěže: [čas, název, text času]; hráč je řádek „Ty“ (N.P. je na konci).
func _competition_rows(_pid_row: int, t: float, valid: bool) -> Array:
	var rows: Array = []
	var base_total := 0.0
	var st: Dictionary = _cfg.get("faze_s", {})
	for k in st.keys():
		base_total += float(st[k])
	var rozptyl := _f("tym_rozptyl", 0.04)
	for tym in _cfg.get("tymy", []):
		var forma := float(tym.get("forma", 1.0))
		var tt := base_total * forma * _rng.randf_range(1.0 - rozptyl, 1.0 + rozptyl)
		rows.append([tt, String(tym.get("nazev", "SDH")), _fmt_t(tt)])
	if valid:
		rows.append([t, "Ty", _fmt_t(t)])
	else:
		rows.append([9999.0, "Ty", "N.P."])
	rows.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	return rows


static func _fmt_t(t: float) -> String:
	if t <= 0.0:
		return "–"
	return "%.1f s" % t


func _update_board() -> void:
	if _board == null:
		return
	if _run.is_empty():
		_board.text = "%s · požární útok\nRekord sboru: %s" % [NAME_BASE, _fmt_t(_record)]
		_bar.text = ""
		return
	_board.text = "%s · %s\n%s · %s" % [ROLE_NAMES.get(String(_run["role"]), ""),
		STAGE_NAMES.get(_stage_key(), ""), _fmt_t(float(_run["t"])),
		"N.P." if String(_run["fault"]) != "" else "běží"]
	_bar.text = _bar_text()


func _bar_text() -> String:
	var v := _pulse()
	var lo := -1.0
	var hi := -1.0
	if _player_stage() and not _player_stage_done():
		var key := _stage_key()
		if key == "motor" and int(_run["phase"]) == 1:
			lo = _f("plyn_stred", 0.5) - _f("plyn_tol", 0.12)
			hi = _f("plyn_stred", 0.5) + _f("plyn_tol", 0.12)
		elif key != "proudy":
			lo = _f("pruh", 0.85) - _f("pruh_tol", 0.1)
			hi = _f("pruh", 0.85) + _f("pruh_tol", 0.1)
	var s := ""
	for i in range(BAR_N + 1):
		var u := float(i) / float(BAR_N)
		var ch := "-"
		if lo >= 0.0 and u >= lo and u <= hi:
			ch = "="
		if absf(u - v) < 0.5 / float(BAR_N):
			ch = "O"
		s += ch
	return "[" + s + "]"


# ------------------------------------------------------------------ ukládání

func _hdist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func to_dict(id: int) -> Dictionary:
	return {"forma": int(_form.get(id, 0)), "best": float(_best.get(id, 0.0)),
		"soutez_jd": int(_soutez_jd.get(id, -1)), "rekord": _record}


func from_dict(id: int, d: Dictionary) -> void:
	_form[id] = clampi(int(d.get("forma", 0)), 0, FORMA_MAX)
	_best[id] = float(d.get("best", 0.0))
	_soutez_jd[id] = int(d.get("soutez_jd", -1))
	var r := float(d.get("rekord", 0.0))
	if r > 0.0 and (_record <= 0.0 or r < _record):
		_record = r
