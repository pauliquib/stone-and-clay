## Střelnice u myslivecké chaty (M2.8): legální trénink luku, kuše a pušky. Stůl u střeleckého stanoviště, čtyři kruhové
## terče (15, 30, 50 m pro luk a kuši, 100 m pro pušku) se slaměnými balíky / valem za nimi a skóre posledních 5 ran.
##
## Umístění: směr střelby se vybere automaticky z 16 směrů od dveří chaty (svah za terči, málo lesa na dráze, mimo
## silnice a zástavbu, volný výhled bez zdi). DOPLNIT: `FIRING_YAW_DEG` (výchozí -1 = automaticky) – uživatel může směr
## určit ručně, až střelnici uvidí. Terče jsou statická tělesa (vrstva 1) s metadaty `range_target`; zásah vyhodnocuje
## `Weapons` (paprsek projektilu) a předá ho sem (`on_hit`). Skóre se ukládá jen za běhu (do konce hry se neukládá).
##
## Legální střelba: hráč stojí do `STAND_R` m od stolu a míří zhruba po dráze (`is_shooting_lane`) – tam se neuděluje
## `strelba_v_obci` (puška bez oprávnění je protizákonná i zde, kontroluje myslivec – viz `Weapons`).
class_name ShootingRange
extends Node3D

const FIRING_YAW_DEG := -1.0         # DOPLNIT: směr střelby ve stupních (0 = +Z, 90 = +X); -1 = automaticky podle terénu
const START_D := 16.0                # stůl stojí tolik m od dveří chaty
const STAND_R := 14.0                # do kolika m od stolu se střelba počítá jako střelnice
const LANE_DOT := 0.6                # min. cos úhlu mezi směrem výstřelu a dráhou (vodorovně)
const MARKS_MAX := 40                # tolik zásahů se na jednom terči drží (nejstarší mizí)
const SCORE_KEEP := 5
## Terče: [vzdálenost od stolu (m), boční posun (m), poloměr (m), střed nad zemí (m)]
const TARGETS := [[15.0, -3.0, 0.4, 1.2], [30.0, 3.0, 0.4, 1.2], [50.0, -3.0, 0.5, 1.3], [100.0, 3.0, 0.6, 1.4]]
const RING_COLORS := [Color(0.93, 0.93, 0.9), Color(0.1, 0.1, 0.12), Color(0.2, 0.4, 0.75), Color(0.85, 0.2, 0.18), Color(0.95, 0.85, 0.2)]
const STRAW := Color(0.78, 0.66, 0.3)
const EARTH := Color(0.36, 0.28, 0.18)
const WOOD := Color(0.42, 0.3, 0.17)

var world: World
var ok := false                      # střelnice se podařilo postavit
var table_pos := Vector3.ZERO
var lane := Vector3.FORWARD          # jednotkový vodorovný směr dráhy (od stolu k terčům)
var targets: Array = []              # [{body, pos, dist, radius, marks}]
var scores := {}                     # id hráče → [{score, dist, w}] (posledních SCORE_KEEP)

var _mark_mat: StandardMaterial3D


func setup(w: World) -> void:
	world = w
	name = "Strelnice"
	if not world.places.has("chata") or world.terrain == null:
		return
	if not _choose_layout():
		return
	_build()
	ok = true


# ------------------------------------------------------------------ umístění

## Vybere směr dráhy a polohu stolu. Bez dat / při chybě (žádný použitelný směr) vrací false a střelnice se nestaví.
func _choose_layout() -> bool:
	var door: Vector3 = world.places["chata"].door
	var dirs: Array = []
	if FIRING_YAW_DEG >= 0.0:
		var a0 := deg_to_rad(FIRING_YAW_DEG)
		dirs.append(Vector3(sin(a0), 0.0, cos(a0)))
	else:
		for k in 16:
			var a := TAU * float(k) / 16.0
			dirs.append(Vector3(sin(a), 0.0, cos(a)))
	var best := -INF
	var best_dir := Vector3.ZERO
	var len_total := START_D + float(TARGETS[TARGETS.size() - 1][0]) + 10.0
	for dir in dirs:
		var s := _score_dir(door, dir, len_total)
		if s > best:
			best = s
			best_dir = dir
	if best_dir == Vector3.ZERO or best < -40.0:
		return false
	lane = best_dir
	var f := door + lane * START_D
	table_pos = Vector3(f.x, world.terrain.height_at(f.x, f.z), f.z)
	return true


func _score_dir(door: Vector3, dir: Vector3, len_total: float) -> float:
	var t: Terrain = world.terrain
	var end := door + dir * len_total
	if not t.contains(end.x, end.z, 60.0) or not t.contains(door.x, door.z, 60.0):
		return -99.0
	var f := door + dir * START_D
	var h_f := t.height_at(f.x, f.z)
	var score := 0.0
	# svah za terči = přirozený zadní val; rovina / údolí horší
	var rise := t.height_at(end.x, end.z) - h_f
	score += clampf(rise, -5.0, 12.0) * 0.5
	# stůl i dráha nesmí být na prudkém svahu
	if absf(h_f - t.height_at(door.x, door.z)) > 6.0:
		score -= 12.0
	# les na dráze (stromy v cestě střelám), zástavba a silnice kolem
	var forest := 0.0
	var min_road := INF
	for i in 8:
		var q := door + dir * (START_D + len_total * float(i) / 7.0)
		if world.fauna != null:
			forest += world.fauna.forest_at(q.x, q.z) / 8.0
		min_road = minf(min_road, world.dist_to_roads(Vector2(q.x, q.z)))
	score -= forest * 8.0
	if min_road < 25.0:
		score -= 6.0
	if world.fauna != null:
		score -= world.fauna.settle_at(end.x, end.z) * 14.0
	# zeď chaty nebo strom těsně před stolem = bez výhledu
	if not world.line_clear(door + Vector3(0, 1.5, 0), f + Vector3(0, 1.5, 0)):
		score -= 50.0
	return score


# ------------------------------------------------------------------ stavba

func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, world.terrain.height_at(p.x, p.z), p.z)


func _build() -> void:
	_mark_mat = StandardMaterial3D.new()
	_mark_mat.albedo_color = Color(0.05, 0.05, 0.05)
	_mark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var right := lane.cross(Vector3.UP).normalized()
	_build_table(right)
	for i in TARGETS.size():
		var spec: Array = TARGETS[i]
		var p := _ground(table_pos + lane * float(spec[0]) + right * float(spec[1]))
		_build_target(i, p, float(spec[2]), float(spec[3]), float(spec[0]))
	# zadní val za nejvzdálenějším terčem (zachytí zbloudilé střely, ne šípy do lesa)
	var far: Array = TARGETS[TARGETS.size() - 1]
	var bp := _ground(table_pos + lane * (float(far[0]) + 7.0))
	_add_box(self, bp + Vector3(0, 1.6, 0), Vector3(22.0, 3.2, 3.0), EARTH, true, lane)


func _xf(pos: Vector3, dir: Vector3) -> Transform3D:
	return Transform3D(Basis.looking_at(dir, Vector3.UP), pos)


## Kvádr s barvou (jeden MeshInstance, volitelně statická kolize vrstvy 1) natočený podle `dir` (−Z = dir).
func _add_box(parent: Node3D, pos: Vector3, size: Vector3, col: Color, collide: bool, dir: Vector3) -> Node3D:
	var root: Node3D = StaticBody3D.new() if collide else Node3D.new()
	parent.add_child(root)
	root.global_transform = _xf(pos, dir)
	var k := MeshKit.new()
	k.box(Vector3.ZERO, size, col)
	MeshKit.mesh_instance(root, k.commit(MeshKit.vc_material(0.95, 0.0)), 400.0)
	if collide:
		var sb := root as StaticBody3D
		sb.collision_layer = 1
		sb.collision_mask = 0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		root.add_child(cs)
	return root


func _build_table(right: Vector3) -> void:
	var g := table_pos
	# stůl 1,6 × 0,7 m, výška 0,85 m, podél střelecké čáry
	var top := _add_box(self, g + Vector3(0, 0.85, 0), Vector3(1.6, 0.05, 0.7), WOOD, true, lane)
	top.name = "StolStrelnice"
	for sx in [-0.7, 0.7]:
		for sz in [-0.28, 0.28]:
			var lp := g + right * float(sx) + lane * float(sz)
			_add_box(self, lp + Vector3(0, 0.42, 0), Vector3(0.06, 0.84, 0.06), WOOD, false, lane)
	# cedule s pravidly
	var sign_p := g - lane * 1.6
	_add_box(self, sign_p + Vector3(0, 0.6, 0), Vector3(0.06, 1.2, 0.06), WOOD, false, lane)
	var board := _add_box(self, sign_p + Vector3(0, 1.3, 0), Vector3(0.9, 0.5, 0.04), Color(0.85, 0.82, 0.7), false, lane)
	var lbl := Label3D.new()
	lbl.text = "STŘELNICE\nPuška jen se zbrojním\noprávněním!"
	lbl.font_size = 26
	lbl.pixel_size = 0.0024
	lbl.modulate = Color(0.12, 0.1, 0.08)
	lbl.position = Vector3(0, 0, 0.025)
	lbl.visibility_range_end = 60.0
	board.add_child(lbl)


func _build_target(i: int, pos: Vector3, radius: float, center_h: float, dist: float) -> void:
	# stojan (dva sloupky) a slaměný balík za terčem (zachytí šíp / kulku)
	var right := lane.cross(Vector3.UP).normalized()
	_add_box(self, pos - right * radius * 0.6 + Vector3(0, center_h * 0.5, 0.0), Vector3(0.08, center_h, 0.08), WOOD, false, lane)
	_add_box(self, pos + right * radius * 0.6 + Vector3(0, center_h * 0.5, 0.0), Vector3(0.08, center_h, 0.08), WOOD, false, lane)
	_add_box(self, pos + lane * 0.6 + Vector3(0, center_h, 0), Vector3(radius * 2.6, radius * 2.6, 0.7), STRAW, true, lane)
	# vlastní terč – kruhy (válec podél osy Z, +Z tělesa míří ke střelci)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("range_target", i)
	add_child(body)
	body.global_transform = _xf(pos + Vector3(0, center_h, 0), lane)
	var k := MeshKit.new()
	for r in RING_COLORS.size():
		var rr := radius * (1.0 - 0.2 * float(r))
		k.cylinder(Vector3(0, 0, 0.004 * float(r)), rr, rr, 0.03, RING_COLORS[r], Vector3(PI / 2.0, 0, 0), 24)
	MeshKit.mesh_instance(body, k.commit(MeshKit.vc_material(0.9, 0.0)), 400.0)
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = 0.06
	cs.shape = cyl
	cs.rotation = Vector3(PI / 2.0, 0, 0)
	body.add_child(cs)
	var marks := Node3D.new()
	marks.name = "Zasahy"
	body.add_child(marks)
	targets.append({"body": body, "pos": pos + Vector3(0, center_h, 0), "dist": dist, "radius": radius, "marks": marks})


# ------------------------------------------------------------------ zásahy a skóre

## Je střelec na střelnici a míří po dráze? (vodorovně; výška se nehodnotí)
func is_shooting_lane(shooter: Vector3, dir: Vector3) -> bool:
	if not ok:
		return false
	if Vector2(shooter.x - table_pos.x, shooter.z - table_pos.z).length() > STAND_R:
		return false
	var h := Vector2(dir.x, dir.z)
	return h.length() > 0.01 and h.normalized().dot(Vector2(lane.x, lane.z)) >= LANE_DOT


## Terč `idx` zasažen v bodě `hit_pos` (světové souřadnice) projektilem zbraně `w`; vrací body 0–10 (0 = mimo kruhy).
func on_hit(id: int, idx: int, hit_pos: Vector3, w: String, shooter_pos: Vector3) -> int:
	if idx < 0 or idx >= targets.size():
		return 0
	var t: Dictionary = targets[idx]
	var body: Node3D = t["body"]
	var lp: Vector3 = body.to_local(hit_pos)
	var radius: float = t["radius"]
	var r := Vector2(lp.x, lp.y).length()
	var pts := clampi(10 - int(floorf(r / (radius / 10.0))), 0, 10)
	_add_mark(t, lp)
	var dist := Vector2(shooter_pos.x - hit_pos.x, shooter_pos.z - hit_pos.z).length()
	var list: Array = scores.get(id, [])
	list.append({"score": pts, "dist": dist, "w": w})
	while list.size() > SCORE_KEEP:
		list.pop_front()
	scores[id] = list
	var wname := String(Weapons.WEAPONS.get(w, {}).get("name", w))
	if pts > 0:
		world.notify(id, "show_message", ["Terč %d m: %d bodů (%s)" % [roundi(float(t["dist"])), pts, wname], 2.5])
		# XP Střelby: přesnost (body) × vzdálenost – na 100 m z pušky se vyplatí nejvíc
		var xp := (0.5 + 0.25 * float(pts)) * (1.0 + dist / 40.0)
		world.give_xp(id, "strelba", xp, "střelnice")
	else:
		world.notify(id, "show_message", ["Terč %d m: mimo kruhy." % roundi(float(t["dist"])), 2.0])
	return pts


func _add_mark(t: Dictionary, lp: Vector3) -> void:
	var marks: Node3D = t["marks"]
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.014
	sm.height = 0.028
	sm.radial_segments = 6
	sm.rings = 3
	sm.material = _mark_mat
	mi.mesh = sm
	mi.visibility_range_end = 120.0
	marks.add_child(mi)
	mi.position = Vector3(lp.x, lp.y, 0.05)
	if marks.get_child_count() > MARKS_MAX:
		marks.get_child(0).queue_free()


func interactables(id: int) -> Array:
	var out := []
	if not ok:
		return out
	var p: Player = world.players.get(id)
	if p == null or p.global_position.distance_to(table_pos) > 40.0:
		return out
	out.append({"pos": table_pos + Vector3(0, 0.9, 0), "r": 2.6, "kind": "custom",
		"text": "Střelnice – skóre posledních ran", "action": open_score_menu})
	return out


## Menu u stolu: posledních 5 ran, součet a průměr.
func open_score_menu(id: int) -> void:
	var list: Array = scores.get(id, [])
	var text := "Střelnice u myslivecké chaty. Terče 15, 30, 50 a 100 m (100 m jen pro pušku s optikou).\n"
	text += "Puška jen se zbrojním oprávněním, střílí se pouze po dráze od stolu.\n\n"
	if list.is_empty():
		text += "Zatím žádná rána."
	else:
		var sum := 0
		for i in list.size():
			var e: Dictionary = list[i]
			sum += int(e["score"])
			text += "%d. rána: %d bodů  (%d m, %s)\n" % [i + 1, int(e["score"]), roundi(float(e["dist"])),
				String(Weapons.WEAPONS.get(String(e["w"]), {}).get("name", e["w"]))]
		text += "\nSoučet %d, průměr %.1f." % [sum, float(sum) / float(list.size())]
	world.notify(id, "open_menu", ["Střelnice", text, [["Vynulovat skóre", _reset_scores.bind(id)]]])


func _reset_scores(id: int) -> void:
	scores.erase(id)
