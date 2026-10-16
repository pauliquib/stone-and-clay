## M8.14 Přízemní vegetace – klientská část (vzhled; simulace je `Meadows` a `Footpaths` ve `World`):
##
## 1. **Interaktivní tráva** (přepínač realismu `ground_veg`): zdroje sešlapání kolem kamery – hráč, vesničané, psi,
##    zvěř, kola aut (živé zdroje) + stopa za chodci (bod po `TRAIL_STEP_M`, síla lineárně klesá za `RELAX_S` ≈ 30 s,
##    tráva se pomalu narovná). Zdroje jdou do malé textury `trample_src` (`SRC_N` × 1, RGBA32F: x, z, poloměr, síla),
##    nahrává se jednou za `UPDATE_FRAMES` snímky; shader trávy / obilí (`ground_veg.gdshaderinc`) sklopí stébla od zdroje.
##    Místo rastru 512² se nekreslí nic na GPU – jen ~0,8 kB upload; za snímek žádné alokace (předalokované pole, seznam
##    chodců se obnovuje 1× za `AGENTS_REFRESH_S`).
## 2. **Výška louky** – `Meadows.image` → globální `meadow_h` (+ `meadow_origin`, `meadow_size`), nahrání jen po změně
##    (`Meadows.gen`, denně).
## 3. **Sukcese a seno** v okolí hráče (MultiMesh, přestavba po posunu o `REBUILD_M` nebo po denním kroku luk):
##    keře na loukách bez seče 2+ roky (trnka a šípek, materiál z `VegetationManager` – vítr, sníh, sezóna), řádky sena
##    `HAY_ROW_DAYS` dní po seči, pak balíky do `HAY_BALE_DAYS`.
class_name GroundVegFx
extends Node3D

const SRC_N := 48                       # = GV_TRAMPLE_MAX v shaders/include/ground_veg.gdshaderinc
const LIVE_MAX := 16                    # nejvýš živých zdrojů (zbytek = stopa)
const TRAIL_N := SRC_N - LIVE_MAX

## --- laditelné (F3 → Příroda/Louky a podrost) ---
static var RELAX_S := 30.0              # s – stopa se narovná (síla zdroje 1 → 0)
static var TRAIL_STEP_M := 0.9          # m – bod stopy po tolika metrech chůze
static var TRAIL_K := 0.85              # síla stopy hned za chodcem (×)
static var R_PERSON := 0.55             # m – poloměr sešlapání člověkem
static var R_ANIMAL := 0.45             # m – pes, srnec (velká zvěř × 1,5 podle druhu se neřeší)
static var R_HORSE := 0.8               # m – kůň s jezdcem
static var R_WHEEL := 0.55              # m – kolo auta / traktoru
static var WHEEL_X := 0.8               # m – rozchod / 2
static var WHEEL_Z := 1.35              # m – rozvor / 2
static var AGENT_R := 40.0              # m od kamery – dál se zdroje nesbírají (= trample_range)
static var TRAMPLE_BEND := 0.9          # shader: síla sklopení (globální trample_bend)
static var UPDATE_FRAMES := 2           # textura zdrojů 1× za tolik snímků
static var AGENTS_REFRESH_S := 1.0
static var REBUILD_M := 30.0            # m – posun hráče, po kterém se přestaví keře a seno
static var SHRUB_R := 200.0             # m – okruh keřů sukcese
static var SHRUBS_PER_CELL := 4.0       # keřů na buňku louky (16 m) při plné hustotě
static var SHRUB_SCALE := [0.7, 1.4]
static var ROSEHIP_SHARE := 0.4         # podíl šípků mezi keři sukcese
static var HAY_R := 160.0               # m – okruh sena
static var HAY_ROW_DAYS := 4            # dní po seči leží řádky
static var HAY_BALE_DAYS := 12          # … pak balíky do tohoto dne
static var BALE_P := 0.5                # šance balíku na buňku

var world: World
var veg: VegetationManager
var _img: Image
var _tex: ImageTexture
var _frame := 0
var _agents: Array = []               # Node3D (netypované – uzel mohl mezitím zaniknout)
var _agents_t := 0.0
var _last_drop := {}                    # instance id → Vector2
var _trail := PackedFloat32Array()      # TRAIL_N × [x, z, r, t0]
var _trail_head := 0
var _time := 0.0
var _on := false
var _meadow_tex: ImageTexture
var _meadow_gen := -1
var _rebuild_pos := Vector3(1e9, 0, 1e9)
var _rebuild_gen := -1
var _shrub_mm: Array[MultiMesh] = []    # [trnka, šípek]
var _hay_mm: MultiMesh
var _bale_mm: MultiMesh
var _nodes: Array[MultiMeshInstance3D] = []


func setup(w: World, v: VegetationManager) -> void:
	world = w
	veg = v
	name = "PrizemniVegetace"
	top_level = true
	_img = Image.create(SRC_N, 1, false, Image.FORMAT_RGBAF)
	_tex = ImageTexture.create_from_image(_img)
	_trail.resize(TRAIL_N * 4)
	_trail.fill(0.0)
	for k in TRAIL_N:
		_trail[k * 4 + 3] = -1e9
	RenderingServer.global_shader_parameter_set("trample_src", _tex)
	RenderingServer.global_shader_parameter_set("trample_n", 0.0)
	apply_shader_params()
	# keře sukcese (trnka, šípek) se stejným materiálem jako statická vegetace (vítr, sníh, sezóna)
	for typ in [VegetationManager.VegType.BUSH_BLACKTHORN, VegetationManager.VegType.ROSEHIP]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = VegetationManager.mesh_of(typ)
		mm.instance_count = 0
		_shrub_mm.append(mm)
		_add_mmi(mm, veg.material_for(typ) if veg != null else null)
	var straw := StandardMaterial3D.new()
	straw.albedo_color = Color(0.72, 0.66, 0.36)
	straw.roughness = 0.95
	_hay_mm = MultiMesh.new()
	_hay_mm.transform_format = MultiMesh.TRANSFORM_3D
	var row := BoxMesh.new()
	row.size = Vector3(0.7, 0.28, 2.1)
	row.material = straw
	_hay_mm.mesh = row
	_add_mmi(_hay_mm, null)
	_bale_mm = MultiMesh.new()
	_bale_mm.transform_format = MultiMesh.TRANSFORM_3D
	var bale := CylinderMesh.new()
	bale.top_radius = 0.62
	bale.bottom_radius = 0.62
	bale.height = 1.2
	bale.radial_segments = 10
	bale.material = straw
	_bale_mm.mesh = bale
	_add_mmi(_bale_mm, null)


func _add_mmi(mm: MultiMesh, mat: Material) -> void:
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if mat != null:
		mmi.material_override = mat
	mmi.custom_aabb = AABB(Vector3(-1e5, -500.0, -1e5), Vector3(2e5, 4000.0, 2e5))
	add_child(mmi)
	_nodes.append(mmi)


## Globální parametry shaderu z laditelných hodnot (po změně v F3).
func apply_shader_params() -> void:
	RenderingServer.global_shader_parameter_set("trample_bend", TRAMPLE_BEND)
	RenderingServer.global_shader_parameter_set("trample_range", AGENT_R)


func enabled() -> bool:
	return world != null and world.realism_on("ground_veg") and (veg == null or veg.detail > 0.0)


func _process(delta: float) -> void:
	var __t0 := Tests.prof_t0()
	_process_impl(delta)
	Tests.prof_add("groundveg", __t0)


func _process_impl(delta: float) -> void:
	if world == null:
		return
	_time += delta
	var on := enabled()
	if on != _on:
		_on = on
		for n in _nodes:
			n.visible = on
		if not on:
			RenderingServer.global_shader_parameter_set("trample_n", 0.0)
			RenderingServer.global_shader_parameter_set("meadow_size", Vector2.ZERO)
			_meadow_gen = -1
		_rebuild_gen = -1
	if not on:
		return
	_update_meadow_tex()
	_agents_t -= delta
	if _agents_t <= 0.0:
		_agents_t = AGENTS_REFRESH_S
		_refresh_agents()
	_frame += 1
	if _frame % maxi(UPDATE_FRAMES, 1) == 0:
		_update_sources()
	var p := _focus()
	if p != null:
		var pos := p.global_position
		var m: Meadows = world.meadows
		var g := m.gen if m != null else 0
		if g != _rebuild_gen or Vector2(pos.x - _rebuild_pos.x, pos.z - _rebuild_pos.z).length() > REBUILD_M:
			_rebuild_gen = g
			_rebuild_pos = pos
			_rebuild_patch(pos)


func _focus() -> Player:
	for id in world.players:
		return world.players[id]
	return null


# ------------------------------------------------------------------ výška louky (meadow_h)

func _update_meadow_tex() -> void:
	var m: Meadows = world.meadows
	if m == null or not m.inited or m.image == null or m.gen == _meadow_gen:
		return
	_meadow_gen = m.gen
	if _meadow_tex == null or _meadow_tex.get_width() != m.image.get_width():
		_meadow_tex = ImageTexture.create_from_image(m.image)
		RenderingServer.global_shader_parameter_set("meadow_h", _meadow_tex)
	else:
		_meadow_tex.update(m.image)
	RenderingServer.global_shader_parameter_set("meadow_origin", Vector2(m.x0, m.z0))
	RenderingServer.global_shader_parameter_set("meadow_size", Vector2(m.nx * Meadows.CELL, m.nz * Meadows.CELL))


# ------------------------------------------------------------------ sešlapání

func _refresh_agents() -> void:
	_agents.clear()
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	var c := cam.global_position
	var r2 := AGENT_R * AGENT_R
	if world.bots_root != null:
		for n in world.bots_root.get_children():
			var b := n as Node3D
			if b != null and b.visible and c.distance_squared_to(b.global_position) < r2 * 2.0:
				_agents.append(b)
	if world.fauna != null:
		for a in world.fauna.animals:
			var an := a as Node3D
			if an != null and is_instance_valid(an) and an.visible and c.distance_squared_to(an.global_position) < r2 * 2.0:
				_agents.append(an)
	if world.traffic != null:
		for car in world.traffic.ai_cars:
			if is_instance_valid(car) and c.distance_squared_to(car.global_position) < r2 * 2.0:
				_agents.append(car)
	if _last_drop.size() > 256:
		_last_drop.clear()


func _drop_trail(n: Node3D, r: float) -> void:
	var p := n.global_position
	var id := n.get_instance_id()
	var q := Vector2(p.x, p.z)
	var last: Vector2 = _last_drop.get(id, Vector2(1e9, 1e9))
	var d := q.distance_to(last)
	if d < TRAIL_STEP_M:
		return
	_last_drop[id] = q
	if d > 8.0:
		return                             # teleport / první vzorek – bez stopy
	var o := _trail_head * 4
	_trail[o] = p.x
	_trail[o + 1] = p.z
	_trail[o + 2] = r
	_trail[o + 3] = _time
	_trail_head = (_trail_head + 1) % TRAIL_N


func _put(i: int, x: float, z: float, r: float, s: float) -> int:
	if i >= SRC_N:
		return i
	_img.set_pixel(i, 0, Color(x, z, r, s))
	return i + 1


func _update_sources() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var c := cam.global_position
	var r2 := AGENT_R * AGENT_R
	var n := 0
	var p := _focus()
	if p != null:
		if p.car != null:
			n = _wheels(n, p.car)
		elif p.horse != null:
			n = _put(n, p.horse.global_position.x, p.horse.global_position.z, R_HORSE, 1.0)
			_drop_trail(p.horse, R_HORSE)
		else:
			n = _put(n, p.global_position.x, p.global_position.z, R_PERSON, 1.0)
			_drop_trail(p, R_PERSON)
	for a0 in _agents:
		if n >= LIVE_MAX:
			break
		if not is_instance_valid(a0):
			continue
		var a := a0 as Node3D
		if a == null or c.distance_squared_to(a.global_position) > r2:
			continue
		if a is Car:
			n = _wheels(n, a as Car)
		else:
			var r := R_PERSON if a is Villager else R_ANIMAL
			n = _put(n, a.global_position.x, a.global_position.z, r, 1.0)
			_drop_trail(a, r)
	# stopa: síla lineárně klesá za RELAX_S
	for k in TRAIL_N:
		if n >= SRC_N:
			break
		var o := k * 4
		var age := _time - _trail[o + 3]
		if age < 0.0 or age > RELAX_S:
			continue
		var s := TRAIL_K * (1.0 - age / maxf(RELAX_S, 0.1))
		if s < 0.02:
			continue
		var dx := _trail[o] - c.x
		var dz := _trail[o + 1] - c.z
		if dx * dx + dz * dz > r2:
			continue
		n = _put(n, _trail[o], _trail[o + 1], _trail[o + 2], s)
	_tex.update(_img)
	RenderingServer.global_shader_parameter_set("trample_n", float(n))


func _wheels(n: int, car: Car) -> int:
	var t := car.global_transform
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var w := t * Vector3(sx * WHEEL_X, 0.0, sz * WHEEL_Z)
			n = _put(n, w.x, w.z, R_WHEEL, 1.0)
	return n


# ------------------------------------------------------------------ keře sukcese, seno

func _rebuild_patch(pos: Vector3) -> void:
	var m: Meadows = world.meadows
	var t: Terrain = world.terrain
	if m == null or not m.inited or t == null:
		for mm in _shrub_mm:
			mm.instance_count = 0
		_hay_mm.instance_count = 0
		_bale_mm.instance_count = 0
		return
	var shrubs: Array = [[], []]
	var hay: Array[Transform3D] = []
	var bales: Array[Transform3D] = []
	var rr := maxf(SHRUB_R, HAY_R)
	var c0 := clampi(floori((pos.x - rr - m.x0) / Meadows.CELL), 0, m.nx - 1)
	var c1 := clampi(floori((pos.x + rr - m.x0) / Meadows.CELL), 0, m.nx - 1)
	var r0 := clampi(floori((pos.z - rr - m.z0) / Meadows.CELL), 0, m.nz - 1)
	var r1 := clampi(floori((pos.z + rr - m.z0) / Meadows.CELL), 0, m.nz - 1)
	var today := world.clock.jd() if world.clock != null else 0
	for r in range(r0, r1 + 1):
		for cc in range(c0, c1 + 1):
			var i := m.cell_of[r * m.nx + cc]
			if i < 0:
				continue
			var cx := m.x0 + (cc + 0.5) * Meadows.CELL
			var cz := m.z0 + (r + 0.5) * Meadows.CELL
			var d2 := (cx - pos.x) * (cx - pos.x) + (cz - pos.z) * (cz - pos.z)
			var hv := Fields._hash(cc * 7 + 13, r * 11 + 5)
			# keře sukcese
			var dens := m.shrub_of(i)
			if dens > 0.0 and d2 < SHRUB_R * SHRUB_R:
				var want := dens * SHRUBS_PER_CELL
				var cnt := int(want) + (1 if float(hv % 1000) / 1000.0 < want - floorf(want) else 0)
				for k in cnt:
					var h2 := Fields._hash(hv + k * 7919, k * 31 + 1)
					var x := cx + (float(h2 % 1000) / 1000.0 - 0.5) * Meadows.CELL * 0.9
					var z := cz + (float((h2 / 1000) % 1000) / 1000.0 - 0.5) * Meadows.CELL * 0.9
					var sc := lerpf(float(SHRUB_SCALE[0]), float(SHRUB_SCALE[1]), float((h2 / 7) % 100) / 100.0) * lerpf(0.6, 1.0, dens)
					var b := Basis(Vector3.UP, float(h2 % 628) / 100.0).scaled(Vector3.ONE * sc)
					var which := 1 if float((h2 / 13) % 100) / 100.0 < ROSEHIP_SHARE else 0
					(shrubs[which] as Array).append(Transform3D(b, Vector3(x, t.height_at(x, z) - 0.05, z)))
			# seno po seči
			if d2 > HAY_R * HAY_R or m.cut_jd[i] < 0 or int(m.mgmt[i]) == Meadows.MGMT_NONE or m.grazed[i] != 0:
				continue
			var days := today - m.cut_jd[i]
			if days < 0 or days > HAY_BALE_DAYS:
				continue
			var along_x := Fields._hash(floori(cx / Meadows.PLOT_M), floori(cz / Meadows.PLOT_M)) % 2 == 0
			if days <= HAY_ROW_DAYS:
				for row in 2:
					var off := (float(row) - 0.5) * Meadows.CELL * 0.5
					for sgm in 7:
						var u := (float(sgm) - 3.0) * 2.1
						var x := cx + (u if along_x else off)
						var z := cz + (off if along_x else u)
						var yaw := PI * 0.5 if along_x else 0.0
						hay.append(Transform3D(Basis(Vector3.UP, yaw), Vector3(x, t.height_at(x, z) + 0.06, z)))
			elif float((hv / 100) % 100) / 100.0 < BALE_P:
				var x := cx + (float(hv % 7) - 3.0)
				var z := cz + (float((hv / 7) % 7) - 3.0)
				var b := Basis(Vector3.FORWARD, PI * 0.5).rotated(Vector3.UP, float(hv % 314) / 100.0)
				bales.append(Transform3D(b, Vector3(x, t.height_at(x, z) + 0.55, z)))
	for k in 2:
		var arr: Array = shrubs[k]
		var mm := _shrub_mm[k]
		mm.instance_count = arr.size()
		for j in arr.size():
			mm.set_instance_transform(j, arr[j])
			mm.set_instance_custom_data(j, Color(0.9, 1.0, 0.85, 0.0))
	_hay_mm.instance_count = hay.size()
	for j in hay.size():
		_hay_mm.set_instance_transform(j, hay[j])
	_bale_mm.instance_count = bales.size()
	for j in bales.size():
		_bale_mm.set_instance_transform(j, bales[j])
