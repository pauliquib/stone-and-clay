## U-rampa na mýtince severovýchodně od obce (M5.8) – hotová od začátku (rozhodnutí uživatele), ne stavba z materiálu.
## Umístění odvozeno z dat (log M5.8): střed náves = dveře úřadu, bod 186 m od náves, 18° od směru SV, nejbližší budova /
## silnice / voda 12,8 m, bez stromů v půdorysu (`trees.bin`), třída povrchu 4 (dvůr / zahrada, `surface.bin`).
## Konstrukce: překližka a trámky na betonových patkách, které sahají do terénu; terén se nevyrovnává, podlaha je nad
## nejvyšším bodem půdorysu, takže rampa nevisí. Kolize: ConcavePolygonShape3D z meshe přechodů a bočních stěn
## (oboustranná), plošiny jako boxy. Povrch má meta surface = "rampa" (jízdu řeší `Player._board_step`).
class_name URampa
extends Node3D

const CENTER := Vector2(-52.0, 118.0)       # střed rampy (x, z) ve světě – viz log M5.8
const YAW_DEG := 112.9                      # osa Z = směr jízdy, podél vrstevnice; osa X napříč (po spádu)
const W := 4.8                              # šířka napříč (m, rozteč bočních stěn)
const WALL_H := 1.5                         # výška copingu nad podlahou (m)
const R := 2.4                              # poloměr přechodu (m)
const FLAT := 2.4                           # rovný střed (m)
const DECK_D := 1.2                         # hloubka plošiny za copingem (m)
const U_TOP := 3.425                        # vodorovný průmět přechodu ke copingu: FLAT/2 + sqrt(R² − (R − WALL_H)²)
const Z_END := 4.625                        # U_TOP + DECK_D – vnější hrana plošiny
const RAIL_H := 0.9                         # výška zábradlí nad plošinou (m)
const PAD := 0.5                            # půdorys betonové patky (m)
const PAD_TOP := -0.3                       # horní hrana patek (m, lokálně – pod podlahou)
const POST_X := 2.0                         # osa sloupků (m, od středu)
const RIB_Z := [-3.2, -1.6, 0.0, 1.6, 3.2]  # trámky pod povrchem (lokální z)
const LADDER_Z := 4.0                       # žebřík na boku (+X) u plošiny
const SURF_N := 80                          # vzorků profilu přechodu na polovinu
const COL_PLY := Color(0.80, 0.64, 0.42)    # překližka
const COL_BEAM := Color(0.56, 0.41, 0.26)   # trámky, sloupky, žebřík
const COL_CONC := Color(0.74, 0.74, 0.71)   # beton (patky)
const COL_STEEL := Color(0.72, 0.74, 0.76)  # coping, zábradlí

var world: World
var terrain: Terrain
var base_y := 0.0                           # světová výška podlahy (m)
var kit := MeshKit.new()
var _ax := Vector2.RIGHT                    # světový směr lokální osy X (napříč)
var _az := Vector2.DOWN                     # světový směr lokální osy Z (směr jízdy)
var _col_faces := PackedVector3Array()      # trojúhelníky kolize (povrch + boční stěny)


## Profil riding povrchu: výška nad podlahou v místě `u` (osa Z). Rovný střed, kruhový přechod, plošina ve výši copingu.
static func _prof(u: float) -> float:
	var a := absf(u)
	if a <= FLAT * 0.5:
		return 0.0
	if a <= U_TOP:
		var d := a - FLAT * 0.5
		return R - sqrt(maxf(R * R - d * d, 0.0))
	return WALL_H


## Sklon profilu (dy/du) – pro normálu plochy (směr „dovnitř“ mísy).
static func _dprof(u: float) -> float:
	return (_prof(u + 0.02) - _prof(u - 0.02)) / 0.04


## Postaví rampu (volá se po `Terrain`, výška terénu se bere z něj).
func build(w: World, t: Terrain) -> void:
	world = w
	terrain = t
	var yaw := deg_to_rad(YAW_DEG)
	_ax = Vector2(cos(yaw), -sin(yaw))
	_az = Vector2(sin(yaw), cos(yaw))
	# podlaha nad nejvyšším bodem půdorysu (vzorkování terénu pod rampou)
	var top_g := -1.0e9
	for i in 7:
		for j in 9:
			var lx := lerpf(-W * 0.5 - 0.3, W * 0.5 + 0.3, float(i) / 6.0)
			var lz := lerpf(-Z_END - 0.3, Z_END + 0.3, float(j) / 8.0)
			var p := _world_xz(lx, lz)
			top_g = maxf(top_g, terrain.height_at(p.x, p.y))
	base_y = top_g + 0.15
	position = Vector3(CENTER.x, base_y, CENTER.y)
	rotation.y = yaw
	_build_surface()
	_build_frame()
	_build_decks()
	_build_ladder()
	_build_collision()
	MeshKit.mesh_instance(self, kit.commit(MeshKit.vc_material(0.85, 0.0, 0.0, false)))


## Světová souřadnice (x, z) bodu v lokálních souřadnicích rampy.
func _world_xz(lx: float, lz: float) -> Vector2:
	return Vector2(CENTER.x, CENTER.y) + _ax * lx + _az * lz


## Výška terénu pod lokálním bodem, lokálně (záporná = terén pod podlahou).
func _ground_local(lx: float, lz: float) -> float:
	var p := _world_xz(lx, lz)
	return terrain.height_at(p.x, p.y) - base_y


## Trojúhelník s normálou do směru `hint` (vizuál bez ohledu na pořadí; kolize je oboustranná).
func _face(a: Vector3, b: Vector3, c: Vector3, hint: Vector3, col: Color, coll := true) -> void:
	var bb := b
	var cc := c
	if (cc - a).cross(bb - a).dot(hint) < 0.0:
		bb = c
		cc = b
	kit.tri(a, bb, cc, col)
	if coll:
		_col_faces.append(a)
		_col_faces.append(bb)
		_col_faces.append(cc)


## Riding povrch (podlaha + oba přechody) a boční stěny podle profilu, včetně kolize.
func _build_surface() -> void:
	var rz: Array = []
	for i in SURF_N + 1:
		rz.append(lerpf(-U_TOP, U_TOP, float(i) / float(SURF_N)))
	for i in SURF_N:
		var z0: float = rz[i]
		var z1: float = rz[i + 1]
		var y0 := _prof(z0)
		var y1 := _prof(z1)
		var hint := Vector3(0.0, 1.0, -_dprof((z0 + z1) * 0.5)).normalized()
		var a := Vector3(-W * 0.5, y0, z0)
		var b := Vector3(W * 0.5, y0, z0)
		var c := Vector3(W * 0.5, y1, z1)
		var d := Vector3(-W * 0.5, y1, z1)
		_face(a, b, c, hint, COL_PLY)
		_face(a, c, d, hint, COL_PLY)
	# boční stěny: pásy od profilu dolů (včetně plošin na koncích)
	var pz: Array = [-Z_END]
	pz.append_array(rz)
	pz.append(Z_END)
	for s in [-1.0, 1.0]:
		var x: float = s * W * 0.5
		var hint := Vector3(s, 0.0, 0.0)
		for k in range(pz.size() - 1):
			var za: float = pz[k]
			var zb: float = pz[k + 1]
			var p1 := Vector3(x, _prof(za), za)
			var p2 := Vector3(x, _prof(zb), zb)
			var p3 := Vector3(x, -0.25, zb)
			var p4 := Vector3(x, -0.25, za)
			_face(p1, p2, p3, hint, COL_PLY)
			_face(p1, p3, p4, hint, COL_PLY)
	# coping (kovová trubka ø 6 cm) na hraně obou přechodů
	for s in [-1.0, 1.0]:
		kit.cylinder(Vector3(0.0, WALL_H, s * U_TOP), 0.03, 0.03, W, COL_STEEL, Vector3(0.0, 0.0, PI * 0.5), 8)


## Trámky pod povrchem a sloupky na betonových patkách.
func _build_frame() -> void:
	for zr in RIB_Z:
		var zf: float = zr
		kit.box(Vector3(0.0, _prof(zf) - 0.16, zf), Vector3(W - 0.5, 0.12, 0.1), COL_BEAM)
		_post(zf, _prof(zf) - 0.22)
	for s in [-1.0, 1.0]:
		_post(float(s) * (Z_END - 0.15), WALL_H - 0.08)


## Dva sloupky (s patkami) na příčném pásu `z` – patka sahá od pod terénu po PAD_TOP.
func _post(z: float, top_y: float) -> void:
	for s in [-1.0, 1.0]:
		var x: float = float(s) * POST_X
		var ground := _ground_local(x, z)
		var bot := minf(ground, PAD_TOP) - 0.4
		kit.box(Vector3(x, (bot + PAD_TOP) * 0.5, z), Vector3(PAD, PAD_TOP - bot, PAD), COL_CONC)
		kit.box(Vector3(x, (PAD_TOP + top_y) * 0.5, z), Vector3(0.12, top_y - PAD_TOP, 0.12), COL_BEAM)


## Plošiny za copingem (dřevo, kolize), zábradlí na vnější hraně.
func _build_decks() -> void:
	for s in [-1.0, 1.0]:
		var zc: float = float(s) * (U_TOP + DECK_D * 0.5)
		var size := Vector3(W, 0.08, DECK_D)
		kit.box(Vector3(0.0, WALL_H - 0.04, zc), size, COL_PLY)
		_static_box(Vector3(0.0, WALL_H - 0.04, zc), size)
		var zr: float = float(s) * (Z_END - 0.05)
		kit.cylinder(Vector3(0.0, WALL_H + RAIL_H, zr), 0.02, 0.02, W, COL_STEEL, Vector3(0.0, 0.0, PI * 0.5), 8)
		for x in [-W * 0.5 + 0.1, 0.0, W * 0.5 - 0.1]:
			kit.cylinder(Vector3(float(x), WALL_H + RAIL_H * 0.5, zr), 0.025, 0.025, RAIL_H, COL_STEEL, Vector3.ZERO, 8)


## Žebřík z terénu na plošinu (strana +X, u plošiny).
func _build_ladder() -> void:
	var xl := W * 0.5 + 0.35
	var top := WALL_H
	var bot := minf(_ground_local(xl, LADDER_Z), top - 0.5)
	var h := top - bot
	for s in [-1.0, 1.0]:
		kit.box(Vector3(xl + float(s) * 0.22, (top + bot) * 0.5, LADDER_Z), Vector3(0.05, h, 0.05), COL_BEAM)
	var n := int(h / 0.3)
	for k in n:
		var y := bot + 0.15 + 0.3 * float(k)
		kit.box(Vector3(xl, y, LADDER_Z), Vector3(0.44, 0.03, 0.04), COL_BEAM)


## Kolize povrchu z trojúhelníků (oboustranná, aby šlo jet i na zadní stranu plochy) a plošin.
func _build_collision() -> void:
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(_col_faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	_add_body(cs, Vector3.ZERO)


## Plochá krabice v lokálních souřadnicích (plošina).
func _static_box(c: Vector3, size: Vector3) -> void:
	var bs := BoxShape3D.new()
	bs.size = size
	var cs := CollisionShape3D.new()
	cs.shape = bs
	_add_body(cs, c)


func _add_body(cs: CollisionShape3D, c: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "rampa")
	body.position = c
	body.add_child(cs)
	add_child(body)
