## Koupaliště na bývalé hasičské nádrži (M5.2) – umístění odvozeno z dat (log M5.2): potok č. 275 v `data/water.json`
## (vede od silnice do lesa, jihozápadně od obce), pás 10 m od osy toku. Nádrž 25 × 12 m, hloubka vody 1,5 m.
## Je to vlastní mesh NAD terénem (betonový lem, schůdky na krátké straně, vlastní kolize dna) – nezávisí na exportu
## terénu. Registruje se do `Water.ponds`, takže hloubka (`Water.info_at`) a brodění / plavání (`Player.wade`)
## fungují stejně jako u ostatních rybníků. Teplota vody: `water_temp` (sezóna + vzduch), čte ji `Water`.
class_name Koupaliste
extends Node3D

const CENTER := Vector2(173.0, -440.0)   # střed nádrže (x, z) – 10 m od osy potoka č. 275 (bod pts[150])
const AXIS_U := Vector2(0.179, -0.984)   # podél delší strany (tečna potoka v bodě)
const AXIS_V := Vector2(0.984, 0.179)    # napříč (kolmo na potok)
const HALF_L := 12.5                     # polovina délky 25 m (podél U)
const HALF_W := 6.0                      # polovina šířky 12 m (podél V)
const WALL_T := 0.4                      # tloušťka betonového lemu
const DEPTH := 1.5                       # hloubka vody nad terénem (m); rozsah 0,8–2,2
const WALL_BELOW := 1.0                  # lem sahá pod terén (aby nebyl vidět spodek)
const STEPS := 3                         # schůdky na krátké straně (-U)
const STEP_GAP := 1.5                    # půlšířka vstupu ve schůdcích (m, podél V)
const FLOOR_LIFT := 0.1                  # dno nad terénem (m)
const COL_CONCRETE := Color(0.74, 0.74, 0.71)
const COL_WATER := Color(0.22, 0.52, 0.58, 0.72)

var world: World
var terrain: Terrain
var water: Water
var ground := 0.0                        # výška terénu ve středu (m)
var level := 0.0                         # hladina vody (m)
var _rot := 0.0                          # natočení nádrže kolem osy Y


## Teplota vody (°C): pomalu sleduje sezónu (červenec ~22, květen ~15, zima ~8) a teplotu vzduchu (20 %).
## `doy` = den v roce (`Clock.day_of_year()`), `air` = teplota vzduchu (`Weather.temp`).
static func water_temp(doy: float, air: float) -> float:
	var w := (cos(TAU * (doy - 200.0) / 365.0) + 1.0) * 0.5
	var season := 8.0 + 14.0 * w * w
	return season * 0.8 + air * 0.2


## Postaví nádrž (volá se po `Water.build`, aby šla hladina i dno připojit k vodě).
func build(w: World, t: Terrain, wt: Water) -> void:
	world = w
	terrain = t
	water = wt
	ground = terrain.height_at(CENTER.x, CENTER.y)
	level = ground + DEPTH
	_rot = atan2(-AXIS_U.y, AXIS_U.x)
	var base := ground - WALL_BELOW
	var top := level + 0.1
	var inner_l := HALF_L - WALL_T
	var inner_w := HALF_W - WALL_T
	var mat := _mat(COL_CONCRETE)
	# dlouhé strany (podél U)
	_box(0.0, HALF_W - WALL_T * 0.5, 2.0 * HALF_L, WALL_T, base, top, mat)
	_box(0.0, -(HALF_W - WALL_T * 0.5), 2.0 * HALF_L, WALL_T, base, top, mat)
	# krátká strana u konce bez schůdků (+U)
	_box(HALF_L - WALL_T * 0.5, 0.0, WALL_T, 2.0 * HALF_W, base, top, mat)
	# krátká strana se schůdky (-U): dvě části lemu, mezi nimi vstup
	_box(-(HALF_L - WALL_T * 0.5), (STEP_GAP + HALF_W) * 0.5, WALL_T, HALF_W - STEP_GAP, base, top, mat)
	_box(-(HALF_L - WALL_T * 0.5), -(STEP_GAP + HALF_W) * 0.5, WALL_T, HALF_W - STEP_GAP, base, top, mat)
	# schůdky: každý další blíž k lemu je vyšší (výška do hladiny lemu)
	for i in STEPS:
		var k := STEPS - i                                  # vzdálenost od lemu v krocích
		var y1 := ground + (top - ground) * float(i + 1) / float(STEPS)
		var u_c := -HALF_L - (float(k) - 0.5) * 0.5
		_box(u_c, 0.0, 0.5, 2.0 * STEP_GAP, base, y1, mat)
	# dno (vlastní kolize – nezávisí na terénu)
	_box(0.0, 0.0, 2.0 * inner_l, 2.0 * inner_w, base, ground + FLOOR_LIFT, mat)
	# hladina
	var wm := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2.0 * inner_l, 2.0 * inner_w)
	wm.mesh = pm
	wm.material_override = _water_mat()
	wm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wm.position = Vector3(CENTER.x, level, CENTER.y)
	wm.rotation.y = _rot
	add_child(wm)
	# registrace do vody (brodění, plavání, hloubka v info_at)
	var poly := PackedVector2Array()
	for sg in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		poly.append(CENTER + AXIS_U * (sg.x * inner_l) + AXIS_V * (sg.y * inner_w))
	var r := Rect2(poly[0], Vector2.ZERO)
	for q in poly:
		r = r.expand(q)
	water.ponds.append({"name": "Koupaliště", "level": level, "poly": poly, "aabb": r.grow(1.0)})


## Hloubka vody v bodě nádrže (0 mimo nádrž) – pro HUD / plavčíka.
func depth_at(x: float, z: float) -> float:
	var d := water.info_at(x, z)
	return float(d["depth"]) if d["kind"] == "pond" else 0.0


## Krabice v lokálních souřadnicích nádrže: u (podél U), v (napříč), délka lu × lv, výška y0…y1.
func _box(u: float, v: float, lu: float, lv: float, y0: float, y1: float, mat: Material) -> void:
	var c := CENTER + AXIS_U * u + AXIS_V * v
	var bm := BoxMesh.new()
	bm.size = Vector3(lu, y1 - y0, lv)
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = mat
	var bs := BoxShape3D.new()
	bs.size = bm.size
	var cs := CollisionShape3D.new()
	cs.shape = bs
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = Vector3(c.x, (y0 + y1) * 0.5, c.y)
	body.rotation.y = _rot
	body.add_child(mi)
	body.add_child(cs)
	add_child(body)


func _mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.9
	return m


func _water_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = COL_WATER
	m.roughness = 0.15
	m.metallic_specular = 0.6
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m
