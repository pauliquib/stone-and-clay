class_name FotbalHriste
extends Node3D
## Fotbalové hřiště u hospody (M5.6): travnatá plocha 90 × 55 m, čáry, branky se sítí, lavičky, tribuna pro 30 diváků,
## kabina, čtyři stožáry s reflektory (večer), ukazatel skóre a míč (RigidBody3D 0,43 kg, ø 22 cm).
## - střed hřiště = `VillageEvents.BONFIRE_POS` (orientační bod hřiště; hranice čarodějnic leží uprostřed)
## - míč: LMB s prázdnýma rukama a míčem do 1,1 m = kop (držení 0–1 s = síla, podržení = vysoký kop), běh s míčem = dribling
## - branka: míč za čarou (Area3D) → gól do té branky, míč se vrátí na střed po 2 s
## - kalendář: zápas je každou 2. neděli 15:00 v dubnu–červnu a v srpnu–říjnu (`match_day`, `MATCH_TEXT` → `village_events.register`)
## Zatím není: volná hra s NPC, penalty, trenér a tréninky, simulace zápasu s diváky (viz PROJECT_LOG – otevřené body).

const CENTER := Vector2(440.6, 198.6)     # střed hřiště (x, z) ve scéně
const LEN := 90.0                         # délka (osa x)
const WID := 55.0                         # šířka (osa z)
const GOAL_W := 7.32
const GOAL_H := 2.44
const GOAL_DEPTH := 2.0
const BALL_MASS := 0.43
const BALL_R := 0.11
const KICK_RANGE := 1.1
const KICK_MIN := 5.0                     # m/s při krátkém stisku
const KICK_MAX := 16.0                    # m/s při držení 1 s
const KICK_HOLD_S := 1.0
const RESET_DELAY := 2.0
const MATCH_TEXT := "Fotbalový zápas Hvozdnice – Polanka · 15 h · hřiště u hospody"
const TEAM_HOME := "Hvozdnice"
const TEAM_AWAY := "Polanka"
const LIGHT_NIGHT := 0.35                 # reflektory svítí, když je denní světlo pod tuto hodnotu
const GRASS := Color(0.27, 0.52, 0.2)
const LINE := Color(0.95, 0.95, 0.92)
const WOOD := Color(0.55, 0.4, 0.25)
const METAL := Color(0.8, 0.8, 0.82)

var world: World
var ball: RigidBody3D
var score := [0, 0]                       # [gólů do levé branky, gólů do pravé branky]
var _board: Label3D
var _lights: Array[OmniLight3D] = []
var _charge_pid := -1
var _charge_t := 0.0
var _reset_t := 0.0
var _lit := false
var _ball_start := Vector3.ZERO
var _ball_mat: StandardMaterial3D
var _base := 0.0                          # výška terénu ve středu hřiště


## Zápas: 2. neděle v dubnu–červnu a srpnu–říjnu (jd % 7 == 6 je neděle; 0 = pondělí).
static func match_day(jd: int) -> bool:
	if jd % 7 != 6:
		return false
	var d := Clock.from_jdn(jd)
	var m: int = d["month"]
	var day: int = d["day"]
	if not (m in [4, 5, 6, 8, 9, 10]):
		return false
	return (day - 1) / 7 + 1 == 2


func setup(w: World) -> void:
	world = w
	_base = _ground(CENTER.x, CENTER.y)
	_ball_start = Vector3(CENTER.x, _ground(CENTER.x, CENTER.y) + 0.5, CENTER.y)
	_build_grass()
	_build_lines()
	_build_goals()
	_build_furniture()
	_build_lights()
	_build_board()
	_build_ball()


# ------------------------------------------------------------------ pomocné

func _ground(x: float, z: float) -> float:
	return world.terrain.height_at(x, z)


## Vodorovná plocha vyrobená z mřížky, která kopíruje terén.
func _build_grass() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(GRASS)
	var nx := 18
	var nz := 11
	for i in range(nx):
		for j in range(nz):
			var x0 := -LEN / 2 + LEN * i / nx
			var x1 := -LEN / 2 + LEN * (i + 1) / nx
			var z0 := -WID / 2 + WID * j / nz
			var z1 := -WID / 2 + WID * (j + 1) / nz
			var a := _vtx(x0, z0)
			var b := _vtx(x1, z0)
			var c := _vtx(x1, z1)
			var d := _vtx(x0, z1)
			for v in [a, b, c, a, c, d]:
				st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Travnata_plocha"
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = GRASS
	mat.roughness = 0.95
	mi.material_override = mat
	add_child(mi)
	mi.position = _origin()


func _vtx(x: float, z: float) -> Vector3:
	return Vector3(x, _ground(CENTER.x + x, CENTER.y + z) - _base + 0.02, z)


## Počátek hřiště (střed na terénu); všechny lokální výšky jsou vůči němu.
func _origin() -> Vector3:
	return Vector3(CENTER.x, _base, CENTER.y)


func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, solid := false, rot_y := 0.0) -> void:
	var holder: Node3D = StaticBody3D.new() if solid else Node3D.new()
	holder.position = pos
	holder.rotation.y = rot_y
	parent.add_child(holder)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	holder.add_child(mi)
	if solid:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		holder.add_child(cs)


## Čára z a do bodu (vodorovně, v souřadnicích hřiště), nad terénem.
func _line(parent: Node3D, a: Vector2, b: Vector2) -> void:
	var d := b - a
	var mid := (a + b) / 2.0
	var y := _ground(CENTER.x + mid.x, CENTER.y + mid.y) - _ground(CENTER.x, CENTER.y) + 0.04
	_box(parent, Vector3(0.12, 0.02, d.length()), Vector3(mid.x, y, mid.y), LINE, false, atan2(d.x, d.y))


func _build_lines() -> void:
	var root := Node3D.new()
	root.name = "Cary"
	root.position = _origin()
	add_child(root)
	var hx := LEN / 2
	var hz := WID / 2
	_line(root, Vector2(-hx, -hz), Vector2(hx, -hz))
	_line(root, Vector2(hx, -hz), Vector2(hx, hz))
	_line(root, Vector2(hx, hz), Vector2(-hx, hz))
	_line(root, Vector2(-hx, hz), Vector2(-hx, -hz))
	_line(root, Vector2(0, -hz), Vector2(0, hz))
	# středový kruh (r 9,15 m) z krátkých úseček
	for i in range(24):
		var a0 := TAU * i / 24.0
		var a1 := TAU * (i + 1) / 24.0
		_line(root, Vector2(cos(a0), sin(a0)) * 9.15, Vector2(cos(a1), sin(a1)) * 9.15)
	# vápno a malé vápno na obou stranách
	for s in [-1.0, 1.0]:
		var px: float = s * hx
		_line(root, Vector2(px - s * 16.5, -20.15), Vector2(px - s * 16.5, 20.15))
		_line(root, Vector2(px - s * 16.5, -20.15), Vector2(px, -20.15))
		_line(root, Vector2(px - s * 16.5, 20.15), Vector2(px, 20.15))
		_line(root, Vector2(px - s * 5.5, -9.16), Vector2(px - s * 5.5, 9.16))
		_line(root, Vector2(px - s * 5.5, -9.16), Vector2(px, -9.16))
		_line(root, Vector2(px - s * 5.5, 9.16), Vector2(px, 9.16))
	# rohové praporky (tyčky)
	for c in [Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(hx, hz), Vector2(-hx, hz)]:
		_box(root, Vector3(0.06, 1.4, 0.06), Vector3(c.x, _ground(CENTER.x + c.x, CENTER.y + c.y) - _ground(CENTER.x, CENTER.y) + 0.7, c.y), Color(1.0, 0.85, 0.2), true)


func _build_goals() -> void:
	var root := Node3D.new()
	root.name = "Branky"
	root.position = _origin()
	add_child(root)
	var base := _ground(CENTER.x, CENTER.y) + 0.0
	for s in [-1.0, 1.0]:
		var gx: float = s * LEN / 2
		var yb := _ground(CENTER.x + gx, CENTER.y) - base
		var g := Node3D.new()
		g.name = "Branka_%d" % int(s)
		g.position = Vector3(gx, yb, 0)
		root.add_child(g)
		_box(g, Vector3(0.12, GOAL_H, 0.12), Vector3(0, GOAL_H / 2, -GOAL_W / 2), METAL, true)
		_box(g, Vector3(0.12, GOAL_H, 0.12), Vector3(0, GOAL_H / 2, GOAL_W / 2), METAL, true)
		_box(g, Vector3(0.12, 0.12, GOAL_W), Vector3(0, GOAL_H, 0), METAL, true)
		# síť: zadní stěna (ball se zastaví) a boky (vizuálně)
		_box(g, Vector3(0.05, GOAL_H, GOAL_W), Vector3(s * GOAL_DEPTH, GOAL_H / 2, 0), Color(0.95, 0.95, 0.95, 0.35), true)
		_box(g, Vector3(GOAL_DEPTH, GOAL_H, 0.05), Vector3(s * GOAL_DEPTH / 2, GOAL_H / 2, -GOAL_W / 2), Color(0.95, 0.95, 0.95, 0.35))
		_box(g, Vector3(GOAL_DEPTH, GOAL_H, 0.05), Vector3(s * GOAL_DEPTH / 2, GOAL_H / 2, GOAL_W / 2), Color(0.95, 0.95, 0.95, 0.35))
		_box(g, Vector3(GOAL_DEPTH, 0.05, GOAL_W), Vector3(s * GOAL_DEPTH / 2, GOAL_H, 0), Color(0.95, 0.95, 0.95, 0.35))
		# zóna gólu: těsně za čarou, uvnitř sítě
		var area := Area3D.new()
		area.name = "Zona_gólu_%d" % int(s)
		area.collision_layer = 0
		area.collision_mask = 8
		area.position = Vector3(s * (GOAL_DEPTH / 2 - 0.1), GOAL_H / 2, 0)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(GOAL_DEPTH - 0.2, GOAL_H, GOAL_W - 0.2)
		cs.shape = bs
		area.add_child(cs)
		g.add_child(area)
		area.body_entered.connect(_on_goal.bind(int(s)))


func _build_furniture() -> void:
	var root := Node3D.new()
	root.name = "Vybaveni_hriste"
	root.position = _origin()
	add_child(root)
	var gz := _ground(CENTER.x, CENTER.y + 33.0) - _ground(CENTER.x, CENTER.y)
	# tribuna pro 30 diváků: tři řady lavic na jižní straně (z = +33)
	for r in range(3):
		_box(root, Vector3(24.0, 0.45, 1.0), Vector3(0, gz + 0.3 + r * 0.45, 33.0 + r * 1.0), WOOD, true)
	# lavičky pro hráče u postranní čáry
	for x in [-14.0, 14.0]:
		_box(root, Vector3(4.0, 0.45, 0.8), Vector3(x, _ground(CENTER.x + x, CENTER.y - 29.5) - _ground(CENTER.x, CENTER.y) + 0.3, -29.5), WOOD, true)
	# kabina za severní brankou (budova bez interiéru)
	var kx := -LEN / 2 - 9.0
	var ky := _ground(CENTER.x + kx, CENTER.y - 15.0) - _ground(CENTER.x, CENTER.y)
	_box(root, Vector3(8.0, 3.2, 5.0), Vector3(kx, ky + 1.6, -15.0), Color(0.82, 0.78, 0.7), true)
	_box(root, Vector3(9.0, 0.3, 6.0), Vector3(kx, ky + 3.35, -15.0), Color(0.45, 0.25, 0.2), true)


func _build_lights() -> void:
	var root := Node3D.new()
	root.name = "Reflektory"
	root.position = _origin()
	add_child(root)
	for c in [Vector2(-LEN / 2 - 6, -WID / 2 - 6), Vector2(LEN / 2 + 6, -WID / 2 - 6), Vector2(LEN / 2 + 6, WID / 2 + 6), Vector2(-LEN / 2 - 6, WID / 2 + 6)]:
		var gy := _ground(CENTER.x + c.x, CENTER.y + c.y) - _ground(CENTER.x, CENTER.y)
		_box(root, Vector3(0.4, 15.0, 0.4), Vector3(c.x, gy + 7.5, c.y), METAL, true)
		var l := OmniLight3D.new()
		l.position = Vector3(c.x, gy + 15.0, c.y)
		l.omni_range = 40.0
		l.light_energy = 2.5
		l.light_color = Color(1.0, 0.96, 0.85)
		l.visible = false
		root.add_child(l)
		_lights.append(l)


func _build_board() -> void:
	_board = Label3D.new()
	_board.name = "Skore"
	_board.text = _score_text()
	_board.font_size = 96
	_board.pixel_size = 0.01
	_board.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_board.modulate = Color(1.0, 0.95, 0.6)
	_board.position = Vector3(CENTER.x, _ground(CENTER.x, CENTER.y + 30.0) + 6.0, CENTER.y + 30.0)
	add_child(_board)


func _build_ball() -> void:
	ball = RigidBody3D.new()
	ball.name = "Mic_fotbal"
	ball.collision_layer = 8
	ball.collision_mask = 1 | 2 | 4 | 8 | 16
	ball.mass = BALL_MASS
	ball.linear_damp = 0.35
	ball.angular_damp = 0.8
	ball.continuous_cd = true
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.55
	pm.friction = 0.6
	ball.physics_material_override = pm
	var sh := SphereShape3D.new()
	sh.radius = BALL_R
	var cs := CollisionShape3D.new()
	cs.shape = sh
	ball.add_child(cs)
	var sm := SphereMesh.new()
	sm.radius = BALL_R
	sm.height = BALL_R * 2.0
	var mi := MeshInstance3D.new()
	mi.mesh = sm
	_ball_mat = StandardMaterial3D.new()
	_ball_mat.albedo_color = Color(0.95, 0.95, 0.95)
	mi.material_override = _ball_mat
	ball.add_child(mi)
	add_child(ball)
	ball.global_position = _ball_start


func _score_text() -> String:
	return "%s %d : %d %s" % [TEAM_HOME, score[0], score[1], TEAM_AWAY] if score != [0, 0] else "Hřiště · volná hra"


# ------------------------------------------------------------------ smyčka

func _process(delta: float) -> void:
	if world == null:
		return
	var night: bool = world.clock != null and world.clock.daylight() < LIGHT_NIGHT
	if night != _lit:
		_lit = night
		for l in _lights:
			l.visible = night
	if _charge_pid >= 0:
		if Input.is_action_pressed("use_tool"):
			_charge_t = minf(_charge_t + delta, KICK_HOLD_S)
		else:
			_kick(_charge_pid, _charge_t)
			_charge_pid = -1
			_charge_t = 0.0
	if _reset_t > 0.0:
		_reset_t -= delta
		if _reset_t <= 0.0:
			_reset_ball()
	if ball and _out_of_bounds():
		_reset_ball()


func _physics_process(_delta: float) -> void:
	if world == null or ball == null:
		return
	# dribling: hráč běží s míčem a míč je u něj → míč lehce popostrčí ve směru pohybu
	for p in world.players.values():
		var pl: Player = p
		if not is_instance_valid(pl) or pl.equipped != "":
			continue
		var v := Vector3(pl.velocity.x, 0, pl.velocity.z)
		if v.length() < 1.5 or _horizontal_dist(pl.global_position, ball.global_position) > KICK_RANGE:
			continue
		var push := v.normalized() * 1.0
		var bv := Vector3(ball.linear_velocity.x, 0, ball.linear_velocity.z)
		if bv.length() < v.length():
			ball.apply_central_impulse(push * BALL_MASS)


## LMB s prázdnýma rukama a míčem v dosahu = začátek nabíjení kopu. Vrací false, když klik nepatří míči.
func on_click(id: int) -> bool:
	if ball == null or not world.players.has(id):
		return false
	var pl: Player = world.players[id]
	if pl.equipped != "" or _charge_pid >= 0:
		return false
	if _horizontal_dist(pl.global_position, ball.global_position) > KICK_RANGE:
		return false
	_charge_pid = id
	_charge_t = 0.0
	return true


func _kick(id: int, hold: float) -> void:
	if ball == null or not world.players.has(id):
		return
	var pl: Player = world.players[id]
	if _horizontal_dist(pl.global_position, ball.global_position) > KICK_RANGE + 0.4:
		return
	var fwd := -pl.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.001:
		return
	fwd = fwd.normalized()
	var power := lerpf(KICK_MIN, KICK_MAX, clampf(hold / KICK_HOLD_S, 0.0, 1.0))
	var lift := 0.25 if hold >= KICK_HOLD_S * 0.6 else 0.05     # držení = vysoký kop
	var dir := (fwd + Vector3.UP * lift).normalized()
	ball.linear_velocity = Vector3.ZERO
	ball.apply_central_impulse(dir * power * BALL_MASS)
	ball.angular_velocity = Vector3(fwd.z, 0, -fwd.x) * power * 0.5


func _on_goal(body: Node3D, side: int) -> void:
	if body != ball or _reset_t > 0.0:
		return
	# míč do branky vlevo (side −1) počítá pravá strana a naopak
	score[0 if side > 0 else 1] += 1
	_board.text = _score_text()
	_reset_t = RESET_DELAY


func _reset_ball() -> void:
	if ball == null:
		return
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	ball.global_position = _ball_start


func _out_of_bounds() -> bool:
	var p := ball.global_position
	var dx := absf(p.x - CENTER.x)
	var dz := absf(p.z - CENTER.y)
	return dx > LEN / 2 + 12.0 or dz > WID / 2 + 12.0 or p.y < _ground(p.x, p.z) - 3.0


static func _horizontal_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
