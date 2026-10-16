## M8.8 Streamování blízkých LOD generovaných stromů (`TreeGen`): MultiMeshe LOD0 / LOD1 existují jen pro buňky
## 128 m kolem kamery (dřív ~10 000 trvalých MultiMeshů po celé mapě). Přesné přepnutí LOD po stromech dělá shader
## (pásmo vzdálenosti + dither, `shaders/include/tree_gen.gdshaderinc`); tady se jen hlídá, které buňky mají geometrii.
##
## Výkon (00_PRINCIPY kap. 6): kontrola buněk jednou za CHECK_S, stavba MultiMeshů rozložená do snímků (BUILD_MS na
## snímek, nejbližší buňky první). Pokácené stromy (`TreeManager.felled`) se při stavbě buňky rovnou skryjí; za běhu je
## skrývá `TreeManager._set_visible` přes sdílený slovník `near_mm` ([nkey, varianta] → [MultiMesh LOD1, LOD0]).
class_name TreeLodStreamer
extends Node3D

const CHECK_S := 0.25                 # s – jak často přepočítat potřebné buňky
const BUILD_MS := 1.0                 # ms – rozpočet stavby za snímek
const MARGIN := 12.0                  # m – buňka se staví o kus dřív, než do ní pásmo LOD zasáhne
const HYST := 40.0                    # m – buňka se ruší až o tolik dál (bez cukání na hranici)

var gen: TreeGen
var mgr: TreeManager
## [nkey, varianta] → [MultiMesh LOD1 | null, MultiMesh LOD0 | null] – sdílí TreeManager (index pro kácení).
var near_mm := {}

var _groups := {}                     # [nkey, varianta] → [Array[Transform3D], Array[Color], PackedInt32Array id]
var _cell_vars := {}                  # nkey → Array variant v buňce
var _cell_y := {}                     # nkey → Vector2(min y, max y) stromů (vzdálenost kamery ve 3D – dron)
var _built := {}                      # Vector3i(nkey.x, nkey.y, lod) → Array[MultiMeshInstance3D]
var _queue: Array = []                # [Vector3i, vzdálenost] k postavení (seřazeno)
var _t := 0.0


func setup(g: TreeGen, m: TreeManager) -> void:
	gen = g
	mgr = m


## Zařadí strom do buňky (volá TreeGen.build při načtení); vrací index instance v MultiMeshi buňky a varianty.
func add_tree(nkey: Vector2i, vi: int, i: int, xf: Transform3D, col: Color) -> int:
	var key := [nkey, vi]
	if not _groups.has(key):
		_groups[key] = [[], [], PackedInt32Array()]
		near_mm[key] = [null, null]
		if not _cell_vars.has(nkey):
			_cell_vars[nkey] = []
		(_cell_vars[nkey] as Array).append(vi)
	var g: Array = _groups[key]
	(g[0] as Array).append(xf)
	(g[1] as Array).append(col)
	var ids: PackedInt32Array = g[2]
	ids.append(i)
	g[2] = ids
	var y := xf.origin.y
	var cy: Vector2 = _cell_y.get(nkey, Vector2(y, y))
	_cell_y[nkey] = Vector2(minf(cy.x, y), maxf(cy.y, y + xf.basis.y.length()))
	return ids.size() - 1


## M8.11: růst v letech – přeškáluje uloženou transformaci stromu (pro buňky postavené později).
func scale_tree(nkey: Vector2i, vi: int, idx: int, sb: Basis) -> void:
	var g: Array = _groups.get([nkey, vi], [])
	if g.is_empty():
		return
	var xfs: Array = g[0]
	if idx < 0 or idx >= xfs.size():
		return
	var xf: Transform3D = xfs[idx]
	xfs[idx] = Transform3D(xf.basis * sb, xf.origin)


func _process(delta: float) -> void:
	_t -= delta
	if _t <= 0.0:
		_t = CHECK_S
		_update_sets()
	if _queue.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	while not _queue.is_empty() and Time.get_ticks_usec() - t0 < BUILD_MS * 1000.0:
		var it: Array = _queue.pop_front()
		_build(it[0])


func _cam_pos() -> Variant:
	var vp := get_viewport()
	if vp == null:
		return null
	var cam := vp.get_camera_3d()
	if cam == null:
		return null
	return cam.global_position


## Vzdálenost kamery od kvádru buňky (xz obdélník × rozsah výšek stromů).
func _cell_dist(c: Vector3, nkey: Vector2i) -> float:
	var s := MapLoader.TREE_CELL
	var x0 := nkey.x * s
	var z0 := nkey.y * s
	var dx := maxf(maxf(x0 - c.x, c.x - (x0 + s)), 0.0)
	var dz := maxf(maxf(z0 - c.z, c.z - (z0 + s)), 0.0)
	var yr: Vector2 = _cell_y.get(nkey, Vector2(c.y, c.y))
	var dy := maxf(maxf(yr.x - c.y, c.y - yr.y), 0.0)
	return sqrt(dx * dx + dy * dy + dz * dz)


func _update_sets() -> void:
	var cp: Variant = _cam_pos()
	if cp == null:
		return
	var c: Vector3 = cp
	var reach := [TreeGen.L1_END + TreeGen.LOD_FADE + MARGIN, gen.l0_end() + TreeGen.LOD_FADE + MARGIN]   # M8.19B: LOD0 podle předvolby
	# zrušit vzdálené
	for bk in _built.keys():
		var b: Vector3i = bk
		if _cell_dist(c, Vector2i(b.x, b.y)) > float(reach[b.z]) + HYST:
			_free(b)
	# naplánovat chybějící (nejbližší první)
	_queue.clear()
	var r: float = reach[0]
	var s := MapLoader.TREE_CELL
	for cx in range(floori((c.x - r) / s), floori((c.x + r) / s) + 1):
		for cz in range(floori((c.z - r) / s), floori((c.z + r) / s) + 1):
			var nkey := Vector2i(cx, cz)
			if not _cell_vars.has(nkey):
				continue
			var dist := _cell_dist(c, nkey)
			for lod in 2:
				var bk := Vector3i(cx, cz, lod)
				if dist <= float(reach[lod]) and not _built.has(bk):
					_queue.append([bk, dist])
	_queue.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) < float(b[1]))


## LOD slot v `near_mm`: 0 = LOD1, 1 = LOD0 (index 0 je pro TreeManager „hlavní“ blízký MultiMesh).
func _build(bk: Vector3i) -> void:
	if _built.has(bk):
		return
	var nkey := Vector2i(bk.x, bk.y)
	var lod := bk.z
	var list: Array = []
	for vi in _cell_vars.get(nkey, []):
		var key := [nkey, int(vi)]
		var g: Array = _groups[key]
		var xfs: Array = g[0]
		var cols: Array = g[1]
		var ids: PackedInt32Array = g[2]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = gen.lod_mesh(int(vi), lod)
		mm.instance_count = xfs.size()
		for k in xfs.size():
			var xf: Transform3D = xfs[k]
			if mgr != null and mgr.is_felled(ids[k]):
				xf = Transform3D(Basis.from_scale(Vector3.ONE * TreeManager.HIDE_SCALE), xf.origin)
			mm.set_instance_transform(k, xf)
			mm.set_instance_custom_data(k, cols[k])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		add_child(mmi)
		list.append(mmi)
		var slots: Array = near_mm[key]
		slots[1 - lod] = mm
	_built[bk] = list


func _free(bk: Vector3i) -> void:
	var nkey := Vector2i(bk.x, bk.y)
	for vi in _cell_vars.get(nkey, []):
		var slots: Array = near_mm.get([nkey, int(vi)], [])
		if slots.size() == 2:
			slots[1 - bk.z] = null
	for mmi in _built[bk]:
		if is_instance_valid(mmi):
			(mmi as Node).queue_free()
	_built.erase(bk)
