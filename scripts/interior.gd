## Interiér budovy (M1.4): oddělený prostor daleko mimo mapu a pod terénem (`World.INTERIOR_BASE`, mřížka 60 m),
## do kterého se hráč přesune po vstupu do domu. Interiéry jsou VYMYŠLENÉ (reálné vnitřky domů neznáme).
## Kolize i strop jsou statické tělo s metou surface = "budova" → Player._check_roof (déšť) funguje beze změny.
##
## Použití: `Interior.make(world, id, kind, origin)` → `add_child` → `build()`. Podtřída / nový `kind` přepíše
## `build()` (M1.5: hospoda, obchod, úřad…) a poskládá místnost pomocnými metodami:
##   `wall_line`, `solid`, `deco`, `window`, `lamp`, `add_object`, `exit_door`.
## Interaktivní místa (`objects`) se nabízejí v `World.interactables` jen tomu, kdo je uvnitř (`active`):
## `{pos, r, kind: "interior_obj", key, text, interior}`; obsluhu klávesy E dělá `InteriorMenu.open`.
##
## M1.8: stavba po krocích (`begin_build` + `build_step` jednou za snímek řídí `InteriorStreamer`, `build()` = vše naráz);
## každý krok (místnost) se sloučí do vlastního meshe (`flush_mesh`). Generované druhy `gen_house`, `gen_flats`, `gen_hall`
## skládá `InteriorGen` z půdorysu nemovitosti (`estate_id`, seed = id budovy).
class_name Interior
extends Node3D

const HEIGHT := 2.6                     # světlá výška místnosti (m)
const DOOR_H := 2.05                    # výška dveřního otvoru
const WALL_COL := Color(0.86, 0.82, 0.72)
const DARK := Color(0.12, 0.11, 0.1)
const WOOD := Color(0.5, 0.36, 0.22)
const WOOD_DARK := Color(0.32, 0.22, 0.14)
const WHITE := Color(0.9, 0.9, 0.88)

var id := ""
var kind := ""
var title := ""
var world: World
var active := false                     # hráč je právě uvnitř (světla, interakce)
var inside_door := Vector3.ZERO         # kam se hráč objeví po vstupu (globální)
var inside_yaw := 0.0
var objects: Array[Dictionary] = []     # {pos (globální), r, key, text}
var radio_spot := Vector3.INF           # kam se přesune rádio, když je hráč uvnitř (globální), INF = nikam
var radio_yaw := 0.0
var place_key := ""                     # klíč místa (Place), pokud jde o veřejnou budovu (M1.5); "" = domov
var keeper_spot := Vector3.INF          # kde stojí obsluha, když je hráč uvnitř (globální), INF = nikde
var keeper_yaw := 0.0
var seats := {}                         # skupina ("reg", "fri") → [[globální pozice, yaw], …] – sedadla štamgastů / hostů
var flat := false                       # domov je byt (M1.7): radiátor místo kamen, bez topení dřevem
var estate_id := 0                      # M1.8: nemovitost (Estate) generovaného interiéru, 0 = domov / veřejná budova
var ceil_h := HEIGHT                    # M1.8: světlá výška (hala stodoly je vyšší)
var spots := {}                         # M1.8: pojmenovaná místa uvnitř → [globální pozice, yaw] (patra schodiště, dveře bytů, stůl)
var resident: Npc                       # M1.8: obyvatel cizího domu (sedí u stolu, když je doma), null = nikdo
var built := false                      # M1.8: stavba dokončena

var _close_t := 0.0                     # odpočet do vyhození po zavírací době

var _kit := MeshKit.new()
var _body: StaticBody3D
var _win_mat: StandardMaterial3D
var _lamps: Array[Dictionary] = []      # {light, bulb (MeshInstance3D nebo null)}
var _bulb_mat: StandardMaterial3D
var _t := 0.0
var _steps: Array = []                  # M1.8: kroky stavby (Callable), jeden na snímek
var _step_i := 0
var _begun := false


static func make(w: World, id_: String, kind_: String, origin: Vector3) -> Interior:
	var it := Interior.new()
	it.world = w
	it.id = id_
	it.kind = kind_
	it.name = "Interier_" + id_
	it.position = origin
	return it


## Vnější dveře: [pozice na zemi před domem, yaw hráče (od domu)]. Čerpá z BuildingDetails (dveře modelu),
## bez dat z `pois.json` (bod `door_x/z` a `face_yaw` místa se stejným klíčem jako `id`).
func outside_spot() -> Array:
	return world.interior_exit(id)


## Postaví celý interiér naráz (domov po změně bytu / domu, načtení hry uvnitř, vstup do nedostavěného interiéru).
func build() -> void:
	if not _begun:
		begin_build()
	while not build_step():
		pass


## Začátek stavby (M1.8): kolizní tělo, materiály a seznam kroků podle druhu. Pak `build_step()` do vrácení true.
func begin_build() -> void:
	built = false
	_begun = true
	_body = StaticBody3D.new()
	_body.name = "Kolize"
	_body.set_meta("surface", "budova")
	add_child(_body)
	_win_mat = StandardMaterial3D.new()
	_win_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_win_mat.albedo_color = Color(0.7, 0.8, 0.95)
	_bulb_mat = StandardMaterial3D.new()
	_bulb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bulb_mat.albedo_color = Color(1.0, 0.95, 0.75)
	_step_i = 0
	_steps = []
	match kind:
		"domov":
			_steps.append(_build_home)
		"hospoda", "obchod", "urad", "palenice", "sklep", "chata":        # M1.5 – viz PublicInteriors
			place_key = kind
			_steps.append(func() -> void: PublicInteriors.build(self, kind))
		"gen_house", "gen_flats", "gen_hall":                              # M1.8 – viz InteriorGen
			_steps.append_array(InteriorGen.steps(self))
		_:
			push_warning("Interiér %s: neznámý druh „%s“" % [id, kind])
	visible = false           # zobrazí se jen s hráčem uvnitř (ušetří vykreslování)


## Jeden krok stavby (místnost) + sloučení jeho geometrie do meshe. Vrací true, když je interiér hotový.
func build_step() -> bool:
	if built:
		return true
	if _step_i < _steps.size():
		(_steps[_step_i] as Callable).call()
		flush_mesh()
		_step_i += 1
	if _step_i < _steps.size():
		return false
	built = true
	_steps = []
	_update_light(true)
	visible = active
	return true


## Dosavadní geometrii ze stavebnice sloučí do jednoho MeshInstance (jeden draw call na místnost), bez stínů.
func flush_mesh() -> void:
	if _kit.is_empty():
		return
	var mi := MeshKit.mesh_instance(self, _kit.commit(MeshKit.vc_material(0.9)))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_kit.clear()


## Domov (M1.7): titulek podle nemovitosti a varianta bytu / rodinného domu (při změně se interiér postaví znovu).
func set_home(title_: String, flat_: bool) -> void:
	title = title_
	if flat_ == flat:
		return
	flat = flat_
	rebuild()


## Postaví interiér znovu (smaže geometrii, kolize, světla a interaktivní místa). Titulek zůstává.
func rebuild() -> void:
	var was := active
	for c in get_children():
		remove_child(c)
		c.queue_free()
	objects.clear()
	_lamps.clear()
	seats.clear()
	spots.clear()
	resident = null
	radio_spot = Vector3.INF
	_kit = MeshKit.new()
	_steps = []
	_begun = false
	build()
	if was:
		set_active(true)


func set_active(on: bool) -> void:
	active = on
	visible = on
	if on:
		_update_light(true)


func _process(delta: float) -> void:
	if not active:
		return
	_t -= delta
	if _t <= 0.0:
		_t = 0.5
		_update_light(false)
		_check_open(0.5)


## Interaktivní objekty pro World.interactables (jen když je hráč uvnitř).
func interactables() -> Array:
	var out := []
	if not active:
		return out
	for o in objects:
		var d := o.duplicate()
		d["kind"] = "interior_obj"
		d["interior"] = id
		out.append(d)
	return out


## Zavírací doba veřejné budovy: obsluha upozorní a po ~6 s hráče vyvede ven (dveře se zamknou).
func _check_open(dt: float) -> void:
	if place_key == "" or world == null or world.clock == null:
		return
	var pl: Place = world.places.get(place_key)
	if pl == null or pl.is_open(world.clock.hour()):
		_close_t = 0.0
		return
	var first := _close_t == 0.0
	_close_t += dt
	for pid in world.players:
		var p: Player = world.players[pid]
		if p.inside != id:
			continue
		if first:
			if pl.keeper:
				pl.keeper.say("Zavíráme, pěkný večer!", 5.0)
			world.notify(pid, "show_message", ["Zavírací doba – obsluha tě žene ven.", 3.0])
		elif _close_t > 6.0:
			world.exit_interior(pid)


## Poloha obsluhy uvnitř (lokální souřadnice) – Place.set_inside ji přesune za pult.
func set_keeper(local_pos: Vector3, yaw := 0.0) -> void:
	keeper_spot = to_global(local_pos)
	keeper_yaw = yaw


## Sedadlo pro štamgasta ("reg") / pátečního hosta ("fri") – lokální pozice sedáku, yaw = kam se dívá.
func add_seat(group: String, local_pos: Vector3, yaw: float) -> void:
	if not seats.has(group):
		seats[group] = []
	(seats[group] as Array).append([to_global(local_pos), yaw])


func add_object(local_pos: Vector3, r: float, key: String, text: String) -> void:
	objects.append({"pos": to_global(local_pos), "r": r, "key": key, "text": text})


# ------------------------------------------------------------------ stavební pomůcky (lokální souřadnice)

## Kvádr s viditelným povrchem a (volitelně) kolizí. `c` = střed, `s` = rozměry.
func solid(c: Vector3, s: Vector3, col: Color, collide := true, rot_y := 0.0) -> void:
	_kit.box(c, s, col, Vector3(0, rot_y, 0))
	if collide:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = s
		cs.shape = sh
		cs.position = c
		cs.rotation.y = rot_y
		_body.add_child(cs)


## Dekorace bez kolize.
func deco(c: Vector3, s: Vector3, col: Color, rot_y := 0.0) -> void:
	solid(c, s, col, false, rot_y)


## Dekorace s libovolným natočením (Eulerovy úhly).
func deco_rot(c: Vector3, s: Vector3, col: Color, rot: Vector3) -> void:
	_kit.box(c, s, col, rot)


## Válec s natočením (např. ležatý sud: rot = (0, 0, PI/2) → osa podél X).
func cyl_rot(c: Vector3, r: float, h: float, col: Color, rot: Vector3) -> void:
	_kit.cylinder(c, r, r, h, col, rot, 14)


## Komolý kužel (kupole kotle apod.): poloměr nahoře / dole, výška.
func deco_cone(c: Vector3, r_top: float, r_bottom: float, h: float, col: Color) -> void:
	_kit.cylinder(c, r_top, r_bottom, h, col, Vector3.ZERO, 14)


## Jen kolize (neviditelná) – pro tvary složené z dekorací.
func collider(c: Vector3, s: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = s
	cs.shape = sh
	cs.position = c
	_body.add_child(cs)


## Popisek (např. „WC“, cedule) na stěně; `normal_yaw` = kam plocha svítí (0 = k +Z, PI = k −Z, PI/2 = k +X).
func label(c: Vector3, text: String, normal_yaw := 0.0, px := 0.004, col := Color(1, 0.95, 0.8)) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 48
	l.pixel_size = px
	l.outline_size = 4
	l.modulate = col
	l.position = c
	l.rotation.y = normal_yaw
	l.double_sided = false
	add_child(l)


func deco_cyl(c: Vector3, r: float, h: float, col: Color) -> void:
	_kit.cylinder(c, r, r, h, col, Vector3.ZERO, 12)


## Stěna rovnoběžná s osou X (`along_x`, na z = fixed) nebo Z (na x = fixed), od `a` do `b`, s otvory
## `doors` = [[střed, šířka], …] (nad otvorem nadpraží). Tloušťka `thick` je symetricky kolem osy.
## `y0` (M1.8) = výška podlahy podlaží (schodiště bytového domu), výška stěny `ceil_h`.
func wall_line(along_x: bool, fixed: float, a: float, b: float, thick: float, doors: Array, col := WALL_COL,
		y0 := 0.0) -> void:
	var cuts := doors.duplicate()
	cuts.sort_custom(func(p, q): return p[0] < q[0])
	var t := a
	for d in cuts:
		var d0: float = d[0] - d[1] * 0.5
		var d1: float = d[0] + d[1] * 0.5
		if d0 > t:
			_wall_seg(along_x, fixed, t, d0, y0, y0 + ceil_h, thick, col)
		_wall_seg(along_x, fixed, d0, d1, y0 + DOOR_H, y0 + ceil_h, thick, col)
		t = d1
	if b > t:
		_wall_seg(along_x, fixed, t, b, y0, y0 + ceil_h, thick, col)


func _wall_seg(along_x: bool, fixed: float, t0: float, t1: float, y0: float, y1: float, thick: float, col: Color) -> void:
	var len_ := t1 - t0
	var cy := (y0 + y1) * 0.5
	var mid := (t0 + t1) * 0.5
	if along_x:
		solid(Vector3(mid, cy, fixed), Vector3(len_, y1 - y0, thick), col)
	else:
		solid(Vector3(fixed, cy, mid), Vector3(thick, y1 - y0, len_), col)


## Podlaha místnosti (jen vzhled) – obdélník x0..x1, z0..z1.
func floor_patch(x0: float, x1: float, z0: float, z1: float, col: Color) -> void:
	deco(Vector3((x0 + x1) * 0.5, 0.005, (z0 + z1) * 0.5), Vector3(x1 - x0, 0.012, z1 - z0), col)


## Okno ve stěně: `side` "N" (z−), "S" (z+), "W" (x−), "E" (x+) obvodové stěny, `pos` podél stěny, `wall` = poloha
## vnitřní plochy stěny (± půlka místnosti). Sklo je svítící plocha (den světlá, noc tmavá), rám s křížem.
func window(side: String, pos: float, wall: float, y := 1.5, w := 1.0, h := 1.1) -> void:
	var q := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(w, h)
	q.mesh = quad
	q.material_override = _win_mat
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var n := Vector3.ZERO            # směr do místnosti
	match side:
		"N": n = Vector3(0, 0, 1)
		"S": n = Vector3(0, 0, -1)
		"W": n = Vector3(1, 0, 0)
		"E": n = Vector3(-1, 0, 0)
	var horiz := side == "N" or side == "S"
	var c := Vector3(pos, y, wall) if horiz else Vector3(wall, y, pos)
	q.position = c + n * 0.012
	q.rotation.y = atan2(n.x, n.z)
	add_child(q)
	var f := 0.05
	var col := Color(0.93, 0.93, 0.9)
	var cc := c + n * 0.03
	if horiz:
		deco(cc + Vector3(0, h * 0.5, 0), Vector3(w + f * 2, f, 0.05), col)
		deco(cc - Vector3(0, h * 0.5, 0), Vector3(w + f * 2, f, 0.05), col)
		deco(cc + Vector3(w * 0.5, 0, 0), Vector3(f, h, 0.05), col)
		deco(cc - Vector3(w * 0.5, 0, 0), Vector3(f, h, 0.05), col)
		deco(cc, Vector3(0.03, h, 0.05), col)
		deco(cc, Vector3(w, 0.03, 0.05), col)
	else:
		deco(cc + Vector3(0, h * 0.5, 0), Vector3(0.05, f, w + f * 2), col)
		deco(cc - Vector3(0, h * 0.5, 0), Vector3(0.05, f, w + f * 2), col)
		deco(cc + Vector3(0, 0, w * 0.5), Vector3(0.05, h, f), col)
		deco(cc - Vector3(0, 0, w * 0.5), Vector3(0.05, h, f), col)
		deco(cc, Vector3(0.05, h, 0.03), col)
		deco(cc, Vector3(0.05, 0.03, w), col)


## Stropní světlo místnosti (teplé večer, slabé denní světlo přes den) + žárovka.
func lamp(local_pos: Vector3, range_ := 6.0, bulb := true) -> void:
	var l := OmniLight3D.new()
	l.position = local_pos
	l.omni_range = range_
	l.omni_attenuation = 1.3
	l.shadow_enabled = false
	add_child(l)
	var mi: MeshInstance3D = null
	if bulb:
		mi = MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.06
		sm.height = 0.12
		mi.mesh = sm
		mi.material_override = _bulb_mat
		mi.position = local_pos + Vector3(0, 0.02, 0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	_lamps.append({"light": l, "bulb": mi})


## Vnitřní strana vchodových dveří v jižní stěně (`z` = poloha vnitřní plochy): dveřní křídlo s kolizí (vyplňuje otvor),
## klika, rohožka; objekt „exit“ a místo, kam hráč vstoupí.
func exit_door(x: float, z: float, width := 0.9) -> void:
	solid(Vector3(x, 1.0, z + 0.06), Vector3(width, 2.0, 0.14), Color(0.42, 0.27, 0.15))
	deco(Vector3(x + width * 0.35, 1.0, z - 0.03), Vector3(0.03, 0.03, 0.09), Color(0.75, 0.7, 0.4))
	deco(Vector3(x, 0.012, z - 0.5), Vector3(0.75, 0.02, 0.5), Color(0.35, 0.18, 0.15))
	add_object(Vector3(x, 0.0, z - 0.6), 1.5, "exit", "Vyjít ven")
	inside_door = to_global(Vector3(x, 0.1, z - 1.0))
	inside_yaw = 0.0          # pohled do místnosti (−Z), dveře za zády


## Podlaha, strop a obvodové kolize kolem obdélníku o půlrozměrech (hx, hz). Stěny se přidávají zvlášť.
func shell(hx: float, hz: float) -> void:
	solid(Vector3(0, -0.15, 0), Vector3(hx * 2 + 1.2, 0.3, hz * 2 + 1.2), Color(0.45, 0.33, 0.2))
	solid(Vector3(0, ceil_h + 0.15, 0), Vector3(hx * 2 + 1.2, 0.3, hz * 2 + 1.2), Color(0.92, 0.9, 0.85))


# ------------------------------------------------------------------ světlo podle denní doby

func _update_light(force: bool) -> void:
	if world == null or world.clock == null:
		return
	var day := world.clock.daylight()
	var cloud := world.weather.cloud if world.weather else 0.3
	var sky := Color(0.02, 0.03, 0.06).lerp(Color(0.78, 0.88, 1.0) * (1.0 - cloud * 0.25), day)
	sky.a = 1.0
	_win_mat.albedo_color = sky
	var night := 1.0 - day
	var col := Color(1.0, 0.86, 0.62).lerp(Color(1.0, 0.97, 0.9), day)
	var energy := 0.35 + 0.95 * night           # přes den jen slabé světlo z oken, večer lampy
	for d in _lamps:
		var l: OmniLight3D = d["light"]
		l.light_color = col
		l.light_energy = energy
	_bulb_mat.albedo_color = Color(0.45, 0.42, 0.35).lerp(Color(1.0, 0.95, 0.75), clampf(night * 1.4, 0.0, 1.0))


# ------------------------------------------------------------------ domov (vymyšlený půdorys 9 × 7 m)
#
#            N (z−)                    Místnosti (x od západu, z od severu; podlaha y = 0):
#   +-----------+------------------+   ložnice   x −4,5..−1,5  z −3,5..0,5   postel 1,6×2, skříň, noční stolek
#   | ložnice   |  kuchyň          |   předsíň   x −4,5..−1,5  z 0,5..3,5     dveře ven (jih), věšák, boty
#   |           |                  |   kuchyň    x −1,5..4,5   z −3,5..−0,5   linka 0,9 m, sporák, lednička, stůl
#   +--  ---    |------------------|   obývák    x −1,5..4,5   z −0,5..3,5    gauč, stolek, kamna, komoda s rádiem, PC
#   | předsíň   |  obývák          |
#   +--[dveře]--+------------------+
#            S (z+)

## `flat` (M1.7): byt 2+1 v bytovém domě – místo kamen na dřevo radiátor ústředního topení (bez „stove“), jinak stejný
## půdorys (ložnice, kuchyň, obývák, předsíň). Titulek nastavuje `World.apply_home` přes `set_home`.
func _build_home() -> void:
	if title == "":
		title = "Doma"
	shell(4.5, 3.5)
	# --- podlahy místností
	floor_patch(-4.5, -1.5, -3.5, 0.5, Color(0.58, 0.42, 0.26))       # ložnice: dřevo
	floor_patch(-4.5, -1.5, 0.5, 3.5, Color(0.5, 0.5, 0.48))          # předsíň: dlažba
	floor_patch(-1.5, 4.5, -3.5, -0.5, Color(0.72, 0.66, 0.55))       # kuchyň: dlaždice
	floor_patch(-1.5, 4.5, -0.5, 3.5, Color(0.55, 0.4, 0.25))         # obývák: dřevo
	# --- stěny: obvod (otvor pro vchod v jižní stěně) a příčky
	wall_line(true, -3.6, -4.7, 4.7, 0.2, [])
	wall_line(true, 3.6, -4.7, 4.7, 0.2, [[-3.2, 0.9]])
	wall_line(false, -4.6, -3.5, 3.5, 0.2, [])
	wall_line(false, 4.6, -3.5, 3.5, 0.2, [])
	wall_line(false, -1.5, -3.5, 3.5, 0.12, [[-1.45, 0.9], [2.05, 0.9]])   # ložnice ↔ kuchyň, předsíň ↔ obývák
	wall_line(true, 0.5, -4.5, -1.5, 0.12, [])                            # ložnice | předsíň
	# --- vchod
	exit_door(-3.2, 3.5)
	# předsíň: věšák s bundami, botník
	deco(Vector3(-4.46, 1.75, 2.1), Vector3(0.04, 0.08, 1.0), WOOD_DARK)
	deco(Vector3(-4.38, 1.25, 1.8), Vector3(0.14, 0.95, 0.32), Color(0.25, 0.3, 0.4))
	deco(Vector3(-4.38, 1.3, 2.3), Vector3(0.14, 0.85, 0.3), Color(0.45, 0.3, 0.2))
	solid(Vector3(-4.3, 0.3, 1.0), Vector3(0.36, 0.6, 0.9), WOOD)
	deco(Vector3(-4.3, 0.63, 0.8), Vector3(0.22, 0.08, 0.1), Color(0.12, 0.1, 0.1))
	deco(Vector3(-4.3, 0.63, 1.1), Vector3(0.22, 0.08, 0.1), Color(0.3, 0.2, 0.12))
	# ložnice: postel 1,6 × 2 m (hlavou k severní stěně), noční stolek, šatní skříň
	solid(Vector3(-3.0, 0.25, -2.5), Vector3(1.6, 0.5, 2.0), WOOD_DARK)
	deco(Vector3(-3.0, 0.56, -2.4), Vector3(1.5, 0.14, 1.85), Color(0.85, 0.85, 0.9))
	deco(Vector3(-3.0, 0.66, -1.95), Vector3(1.5, 0.05, 1.0), Color(0.3, 0.42, 0.6))
	deco(Vector3(-3.3, 0.68, -3.2), Vector3(0.5, 0.14, 0.3), Color(0.95, 0.95, 0.95))
	deco(Vector3(-2.7, 0.68, -3.2), Vector3(0.5, 0.14, 0.3), Color(0.95, 0.95, 0.95))
	solid(Vector3(-1.85, 0.25, -3.25), Vector3(0.4, 0.5, 0.4), WOOD)
	deco(Vector3(-1.85, 0.55, -3.25), Vector3(0.12, 0.1, 0.12), Color(0.8, 0.7, 0.4))
	solid(Vector3(-4.2, 1.0, -0.9), Vector3(0.6, 2.0, 1.2), Color(0.55, 0.4, 0.26))
	deco(Vector3(-3.89, 1.0, -0.9), Vector3(0.02, 1.9, 0.02), DARK)
	deco(Vector3(-2.0, 0.008, -0.7), Vector3(0.9, 0.016, 0.6), Color(0.6, 0.3, 0.25))   # kobereček
	# kuchyň: linka 0,9 m u severní stěny (dřez, sporák, kávovar, lednička), horní skříňky, stůl s židlemi
	solid(Vector3(-0.65, 0.45, -3.2), Vector3(1.6, 0.9, 0.6), Color(0.85, 0.82, 0.75))
	deco(Vector3(-0.65, 0.91, -3.2), Vector3(1.6, 0.03, 0.62), Color(0.35, 0.35, 0.38))
	deco(Vector3(-0.65, 0.925, -3.2), Vector3(0.5, 0.02, 0.38), Color(0.6, 0.62, 0.65))          # dřez
	deco(Vector3(-0.65, 1.05, -3.42), Vector3(0.03, 0.25, 0.03), Color(0.75, 0.75, 0.78))         # kohoutek
	solid(Vector3(0.45, 0.45, -3.2), Vector3(0.6, 0.9, 0.6), Color(0.88, 0.88, 0.86))
	for i in 4:
		deco_cyl(Vector3(0.45 + (0.13 if i % 2 == 0 else -0.13), 0.915, -3.2 + (0.13 if i < 2 else -0.13)), 0.07, 0.015, DARK)
	solid(Vector3(1.55, 0.45, -3.2), Vector3(1.6, 0.9, 0.6), Color(0.85, 0.82, 0.75))
	deco(Vector3(1.55, 0.91, -3.2), Vector3(1.6, 0.03, 0.62), Color(0.35, 0.35, 0.38))
	deco(Vector3(1.8, 1.06, -3.3), Vector3(0.2, 0.28, 0.25), DARK)                                # kávovar
	deco(Vector3(1.8, 0.98, -3.13), Vector3(0.08, 0.06, 0.08), Color(0.9, 0.9, 0.9))
	solid(Vector3(2.75, 0.9, -3.175), Vector3(0.65, 1.8, 0.65), WHITE)                             # lednička
	deco(Vector3(2.75, 1.05, -2.85), Vector3(0.6, 0.015, 0.02), Color(0.5, 0.5, 0.5))
	deco(Vector3(2.5, 1.3, -2.84), Vector3(0.025, 0.4, 0.03), Color(0.6, 0.6, 0.62))
	deco(Vector3(0.6, 1.75, -3.34), Vector3(3.0, 0.7, 0.32), Color(0.8, 0.75, 0.65))              # horní skříňky
	solid(Vector3(3.0, 0.375, -1.7), Vector3(1.2, 0.75, 0.8), Color(0.6, 0.45, 0.28))              # stůl
	for zc in [-2.35, -1.05]:
		var dir := 1.0 if zc < -1.7 else -1.0
		solid(Vector3(3.0, 0.225, zc), Vector3(0.42, 0.45, 0.42), WOOD)
		deco(Vector3(3.0, 0.7, zc - dir * 0.19), Vector3(0.42, 0.5, 0.05), WOOD)
	# obývák: gauč u jižní stěny, konferenční stolek, kamna, komoda s rádiem, stůl s PC, lampa
	solid(Vector3(1.2, 0.225, 3.05), Vector3(2.0, 0.45, 0.85), Color(0.35, 0.4, 0.5))
	deco(Vector3(1.2, 0.65, 3.4), Vector3(2.0, 0.45, 0.18), Color(0.3, 0.35, 0.45))
	deco(Vector3(0.2, 0.55, 3.05), Vector3(0.14, 0.2, 0.85), Color(0.3, 0.35, 0.45))
	deco(Vector3(2.2, 0.55, 3.05), Vector3(0.14, 0.2, 0.85), Color(0.3, 0.35, 0.45))
	solid(Vector3(1.2, 0.225, 1.7), Vector3(1.1, 0.45, 0.6), WOOD)
	deco(Vector3(1.2, 0.014, 1.9), Vector3(2.2, 0.012, 1.7), Color(0.45, 0.2, 0.2))                  # koberec
	if flat:
		# byt: radiátor ústředního topení pod oknem východní stěny (žebra), termostatická hlavice
		deco(Vector3(4.44, 0.45, 1.9), Vector3(0.08, 0.55, 1.0), WHITE)
		for k in 8:
			deco(Vector3(4.39, 0.45, 1.46 + k * 0.125), Vector3(0.03, 0.5, 0.04), Color(0.82, 0.82, 0.8))
		deco_cyl(Vector3(4.42, 0.8, 2.47), 0.03, 0.08, Color(0.85, 0.85, 0.85))
	else:
		solid(Vector3(4.1, 0.5, 0.9), Vector3(0.7, 1.0, 0.7), Color(0.17, 0.17, 0.18))                  # kamna na dřevo
		deco(Vector3(3.74, 0.55, 0.9), Vector3(0.02, 0.35, 0.3), Color(0.9, 0.5, 0.15))
		deco_cyl(Vector3(4.15, 1.8, 0.9), 0.08, 1.6, Color(0.14, 0.14, 0.15))                            # roura ke stropu
		deco(Vector3(4.2, 0.2, 1.55), Vector3(0.5, 0.4, 0.4), Color(0.4, 0.28, 0.16))                    # koš na dřevo
	solid(Vector3(4.15, 0.4, 3.0), Vector3(0.6, 0.8, 1.0), WOOD_DARK)                                # komoda
	radio_spot = to_global(Vector3(4.15, 0.8, 3.0))
	radio_yaw = -PI * 0.5
	solid(Vector3(-1.05, 0.375, 0.6), Vector3(0.7, 0.75, 1.4), Color(0.6, 0.5, 0.38))                # pracovní stůl
	deco(Vector3(-1.3, 1.0, 0.6), Vector3(0.05, 0.36, 0.56), DARK)                                   # monitor
	deco(Vector3(-1.3, 0.79, 0.6), Vector3(0.16, 0.05, 0.2), DARK)
	deco(Vector3(-0.98, 0.77, 0.6), Vector3(0.18, 0.02, 0.45), Color(0.2, 0.2, 0.22))                # klávesnice
	deco(Vector3(-0.35, 0.225, 0.6), Vector3(0.42, 0.45, 0.42), Color(0.2, 0.2, 0.25))               # židle (M3.4: bez kolize – sedí se na ni u PC)
	deco(Vector3(-0.15, 0.7, 0.6), Vector3(0.05, 0.5, 0.4), Color(0.2, 0.2, 0.25))
	deco_cyl(Vector3(-0.5, 0.8, 3.15), 0.02, 1.6, DARK)                                              # stojací lampa
	deco_cyl(Vector3(-0.5, 0.01, 3.15), 0.18, 0.02, DARK)
	deco_cyl(Vector3(-0.5, 1.55, 3.15), 0.15, 0.24, Color(0.95, 0.88, 0.7))
	# okna
	window("N", -3.0, -3.5)
	window("N", -0.65, -3.5, 1.5, 1.0, 1.0)
	window("N", 3.6, -3.5)
	window("W", -2.4, -4.5)
	window("E", 1.9, 4.5)
	window("S", 1.2, 3.5, 1.5, 1.1, 1.0)
	# světla (ložnice, předsíň, kuchyň, obývák) + stojací lampa
	lamp(Vector3(-3.0, 2.45, -1.5), 5.0)
	lamp(Vector3(-3.0, 2.45, 2.0), 4.5)
	lamp(Vector3(1.5, 2.45, -2.0), 6.0)
	lamp(Vector3(1.5, 2.45, 1.8), 6.5)
	lamp(Vector3(-0.5, 1.5, 3.15), 3.5, false)
	# interaktivní místa (E)
	add_object(Vector3(-2.2, 0.0, -1.1), 1.9, "bed", "Postel (spánek, odpočinek)")
	add_object(Vector3(-3.6, 0.0, -0.9), 1.6, "wardrobe", "Šatní skříň")
	add_object(Vector3(2.75, 0.0, -2.4), 1.5, "fridge", "Lednička")
	add_object(Vector3(1.7, 0.0, -2.6), 1.3, "coffee", "Uvařit kafe")
	add_object(Vector3(-0.65, 0.0, -2.6), 1.2, "sink", "Dřez")
	if not flat:
		add_object(Vector3(3.3, 0.0, 0.9), 1.5, "stove", "Kamna na dřevo")
	add_object(Vector3(-0.5, 0.0, 0.6), 1.5, "pc", "Počítač (e-shop, banka, pošta, práce…)")
	spots["pc_seat"] = [to_global(Vector3(-0.3, -0.05, 0.6)), rotation.y + PI * 0.5]   # M3.4: židle u PC, čelem k monitoru (−X)
