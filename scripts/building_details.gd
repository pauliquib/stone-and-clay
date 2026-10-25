## Fasády budov: okna (rám, parapet, neprůhledné sklo se záclonou, občas okenice), dveře se schodem, vrata
## u garáží a stodol a komíny na střechách domů. Vše jen vizuál, bez kolizí.
##
## Data: `data/buildings.json` (nástroj `tools/buildings.py`; půdorys, výšky okapu a hřebene, typ, místo, dveře).
## Bez souboru se nic nevytvoří (`BuildingDetails.available()`), hra běží beze změny.
## Geometrie se skládá přes `MeshKit` do jednoho meshe na dlaždici 256 m (rámy, dveře, komíny) + druhého meshe
## se skly (shader `window_glass.gdshader`). Noční svícení řeší shader: jediný uniform `lit_frac` (podíl svítících
## oken) se přepočte jednou za herní půlhodinu – žádné uzly na okno, žádná přestavba meshe.
## M8.17 Život vesnice: každé okno nese v UV2 index budovy a místnost (kuchyň / obývák / ložnice / ostatní);
## textura `house_lit` (RGBA = místnosti, texel = budova) se plní z domácností (`Households.window_rooms`) –
## svítí jen tam, kde někdo je (kuchyň ráno, obývák večer, ložnice před spaním). Budovy bez domácností a vypnutý
## přepínač `village_life` = stará křivka `LIT_CURVE` (v textuře / uniform `lit_frac`).
## Okna jsou vždy neprůhledná (žádný průhled do interiérů, viz právní zásady obsahu).
##
## API pro další kroky:
##   `chimneys_near(pos, r)` → [{id, pos (střed vrcholu komína = výstup kouře), base_y}]   (M1.3 kouř)
##   `door_of(building_id)` → Vector3 (na fasádě u terénu, `Vector3.INF` když budova dveře nemá)   (M1.4 interiéry)
##   `door_info(building_id)` → {pos, normal (ven z domu), yaw, width, kind: "door" | "gate"}
##   `building_of_place(key)` → id budovy místa z pois.json (0 = nenalezeno);  `building_of_home()` → původní dům hráče
##   z podkladů (usedlost; domov hráče teď určuje `Estate`, M1.7);  `buildings()` → id → připravená data (registr `Estate`)
class_name BuildingDetails
extends Node3D

const DATA_PATH := "res://data/buildings.json"
const POIS_PATH := "res://data/pois.json"
const TILE := 256.0
const VIS_END := 450.0            # m – dál se okna, dveře a komíny nekreslí
const GRID_CELL := 32.0
const MIN_EDGE := 2.5             # m – kratší stěna nemá okna
const WIN_MARGIN := 0.7           # m – odstup okna od rohu budovy
const FLOOR_H := 2.9              # m – výška podlaží (parapet 2. patra = parapet + FLOOR_H)
const FLOOR2_MIN_WALL := 5.5      # m – stěna (okap nad terénem) od které se dělá druhé podlaží
const DOOR_W := 0.9
const DOOR_H := 2.0
const DOOR_STEP := 0.15           # m – výška schodu
const POI_DOOR_MAX := 12.0        # m – nejdál od půdorysu smí být bod dveří z pois.json, aby se použil

## Pravidla podle typu budovy (laditelné). win: full | one (jedno okno s pravděpodobností p) | none.
## door: "door" (dveře 0,9 × 2,0 m + schod) | "gate" (vrata gate = [šířka, výška]) | "" (nic).
const RULES := {
	"house": {"win": "full", "door": "door", "chimney": true, "sill": 0.9, "wh": [1.2, 1.4], "ww": [1.0, 1.2],
		"spacing": 2.9, "floors": true, "shutters": 0.25},
	"public": {"win": "full", "door": "door", "chimney": false, "sill": 0.9, "wh": [1.2, 1.4], "ww": [1.0, 1.2],
		"spacing": 3.2, "floors": true, "shutters": 0.0},
	"church": {"win": "full", "door": "door", "chimney": false, "sill": 2.2, "wh": [1.9, 2.2], "ww": [0.9, 1.0],
		"spacing": 4.5, "floors": false, "shutters": 0.0},
	"hall": {"win": "one", "p": 0.6, "door": "gate", "gate": [3.2, 2.8], "chimney": false, "sill": 2.0,
		"wh": [0.8, 1.0], "ww": [1.0, 1.2], "spacing": 4.0, "floors": false, "shutters": 0.0},
	"garage": {"win": "none", "door": "gate", "gate": [2.5, 2.1], "chimney": false, "shutters": 0.0},
	"barn": {"win": "none", "door": "gate", "gate": [3.2, 2.8], "chimney": false, "shutters": 0.0},
	"shed": {"win": "one", "p": 0.5, "door": "", "chimney": false, "sill": 1.1, "wh": [0.5, 0.6],
		"ww": [0.6, 0.75], "spacing": 3.0, "floors": false, "shutters": 0.0},
}

## Podíl svítících oken podle hodiny (lineární interpolace) – večer 17–22 h víc, v noci málo, ráno 5–7 některá.
## Denní světlo (slunce nad obzorem) svícení ještě vynásobí.   # DOPLNIT: výchozí odhad, doladit podle pocitu
const LIT_CURVE := [[0.0, 0.05], [2.0, 0.02], [4.5, 0.02], [5.5, 0.10], [6.5, 0.22], [7.5, 0.10], [8.5, 0.0],
	[15.5, 0.0], [16.5, 0.06], [17.5, 0.30], [19.0, 0.50], [20.5, 0.55], [22.0, 0.35], [23.0, 0.15], [24.0, 0.05]]
const LIGHT_CHECK_S := 1.0
const LIT_TEX_W := 64                    # M8.17: šířka textury svícení budov (texel = budova)
## M8.17: místnost okna podle náhodného čísla okna (COLOR.b): přízemí jednopodlažního domu [kuchyň, obývák, ložnice] meze,
## přízemí patrového [kuchyň, obývák] (zbytek ostatní), patro = ložnice (zbytek ostatní).
static var ROOM_SPLIT_1 := [0.3, 0.6, 0.85]
static var ROOM_SPLIT_GROUND := [0.4, 0.85]
static var ROOM_SPLIT_UPPER := 0.8

const FRAME_COLORS := [Color(0.86, 0.86, 0.84), Color(0.30, 0.19, 0.11), Color(0.38, 0.39, 0.41)]
const FRAME_ALPHA := [1.0, 0.6, 0.3]                     # ↔ větev v shaderu window_glass
const FRAME_WEIGHTS := [0.6, 0.3, 0.1]                    # bílá / hnědá / šedá
const SHUTTER_COLORS := [Color(0.25, 0.42, 0.28), Color(0.36, 0.22, 0.12)]
const DOOR_COLORS := [Color(0.28, 0.17, 0.10), Color(0.16, 0.30, 0.20), Color(0.16, 0.22, 0.36), Color(0.45, 0.10, 0.08)]
const SILL_COLOR := Color(0.72, 0.72, 0.70)
const STEP_COLOR := Color(0.50, 0.50, 0.48)
const GATE_COLORS := [Color(0.72, 0.72, 0.70), Color(0.35, 0.22, 0.12), Color(0.30, 0.38, 0.30)]
const BRICK := Color(0.42, 0.20, 0.15)
const CAP := Color(0.30, 0.30, 0.31)
const CHIMNEY_PLASTER := Color(0.62, 0.60, 0.56)
## Šambrány (omítkové orámování oken starších domů) a okapové svody.
const SURROUND_COLORS := [Color(0.84, 0.82, 0.77), Color(0.74, 0.70, 0.62), Color(0.62, 0.60, 0.57)]
const PIPE_COLORS := [Color(0.56, 0.58, 0.60), Color(0.56, 0.58, 0.60), Color(0.28, 0.18, 0.12), Color(0.22, 0.22, 0.23)]
const PIPE_R := 0.045             # m – polovina průřezu svodu
const DOOR_MIN_H := 1.75          # m – nižší dveře se nekreslí (stěna u terénu moc nízká)

## Geometrie jedné dlaždice 256 m (přímo měněná pole – žádné kopírování polí při přidávání).
class Tile extends RefCounted:
	var kit := MeshKit.new()
	var gv := PackedVector3Array()
	var gn := PackedVector3Array()
	var gc := PackedColorArray()
	var guv := PackedVector2Array()
	var guv2 := PackedVector2Array()     # M8.17: (index budovy, místnost) pro texturu svícení


var _world: World
var _terrain: Terrain
var _buildings := {}          # id → Dictionary (připravená data)
var _polys := {}              # id → PackedVector2Array
var _boxes := {}              # id → Rect2
var _grid := {}               # Vector2i → Array[id] (hledání sousedních budov)
var _doors := {}              # id → {pos, normal, yaw, width, kind}
var _place_building := {}     # klíč místa → id budovy
var _home_id := 0
var _chimneys: Array = []
var _glass_mat: ShaderMaterial
var _last_slot := -99999
var _light_t := 0.0
var _light_ids := PackedInt64Array()     # M8.17: index svícení → id budovy
var _light_idx := {}                     # id budovy → index
var _lit_img: Image
var _lit_tex: ImageTexture
var _lit_bytes := PackedByteArray()
var _room_buf := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _hh_ver := -1
var loaded := false


## Existují data budov? (Bez nich se generátor nevytváří.)
static func available() -> bool:
	return FileAccess.file_exists(DATA_PATH)


## Načte data a postaví fasády. Volá se `await`; po dávkách čeká na snímek, ať načítací obrazovka žije.
func setup(w: World) -> void:
	_world = w
	_terrain = w.terrain
	if not available():
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not (data is Array):
		return
	var pois := {}
	if FileAccess.file_exists(POIS_PATH):
		var pj = JSON.parse_string(FileAccess.get_file_as_string(POIS_PATH))
		if pj is Dictionary:
			pois = pj
	for d in data:
		if d is Dictionary:
			_prepare(d, pois)
	_glass_mat = ShaderMaterial.new()
	_glass_mat.shader = load("res://shaders/window_glass.gdshader")
	var tiles := {}
	var n := 0
	for id in _buildings:
		_build_one(_buildings[id], tiles)
		n += 1
		if n % 60 == 0:
			await get_tree().process_frame
	_commit_tiles(tiles)
	_make_lit_texture()
	loaded = true
	_update_lights(true)


func _process(delta: float) -> void:
	if not loaded:
		return
	_light_t -= delta
	if _light_t > 0.0:
		return
	_light_t = LIGHT_CHECK_S
	_update_lights(false)


# ------------------------------------------------------------------ API

## Komíny do vzdálenosti `r` (vodorovně) od `pos`. `pos` v záznamu = střed vrcholu komína (odtud stoupá kouř).
func chimneys_near(pos: Vector3, r: float) -> Array:
	var out := []
	var r2 := r * r
	for c in _chimneys:
		var p: Vector3 = c["pos"]
		var dx := p.x - pos.x
		var dz := p.z - pos.z
		if dx * dx + dz * dz <= r2:
			out.append(c)
	return out


## Dveře (u vrat střed vrat) budovy na fasádě u terénu; `Vector3.INF`, když budova dveře nemá.
func door_of(building_id: int) -> Vector3:
	if not _doors.has(building_id):
		return Vector3.INF
	return _doors[building_id]["pos"]


func door_info(building_id: int) -> Dictionary:
	return _doors.get(building_id, {})


## Id budovy místa z pois.json (hospoda, obchod, …); 0 = nenalezeno.
func building_of_place(key: String) -> int:
	return int(_place_building.get(key, 0))


## Id budovy s příznakem `home` v datech (původní dům hráče z podkladů = usedlost, viz `Estate.lot_id`). Domov hráče
## (byt / dům, který vlastní) vrací `Estate.home_estate(pid)`.
func building_of_home() -> int:
	return _home_id


## Připravená data všech budov: id → {id, type, area, poly, eave, ridge, ground, known, poi, home, …} (jen ke čtení).
func buildings() -> Dictionary:
	return _buildings


## Podíl svítících oken v dané hodině (bez vlivu slunce).
static func lit_fraction(h: float) -> float:
	for i in range(1, LIT_CURVE.size()):
		var a: Array = LIT_CURVE[i - 1]
		var b: Array = LIT_CURVE[i]
		if h <= float(b[0]):
			var t := (h - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.001)
			return lerpf(float(a[1]), float(b[1]), t)
	return float(LIT_CURVE[LIT_CURVE.size() - 1][1])


# ------------------------------------------------------------------ příprava dat

func _prepare(d: Dictionary, pois: Dictionary) -> void:
	var poly := PackedVector2Array()
	for p in d.get("poly", []):
		poly.append(Vector2(float(p[0]), float(p[1])))
	if poly.size() < 3:
		return
	var id := int(d.get("id", 0))
	if id == 0 or _buildings.has(id):
		return
	var poi_v = d.get("poi")
	var poi: String = "" if poi_v == null else str(poi_v)
	var home := bool(d.get("home", false))
	var key := poi if poi != "" else ("domov" if home else "")
	var b := {
		"id": id, "type": str(d.get("type", "house")), "area": float(d.get("area", 0.0)), "poly": poly,
		"eave": float(d.get("eave_y", 0.0)), "ridge": float(d.get("ridge_y", 0.0)),
		"ground": float(d.get("ground_y", d.get("eave_y", 0.0))),     # M1.7: počet podlaží (Estate)
		"known": d.has("eave_y") and d.has("ridge_y"),
		"shape": str(d.get("shape", "flat")), "poi": poi, "home": home,
		"has_door": false, "door": Vector2.ZERO, "ridge_half": float(d.get("ridge_half", 0.0)),
		"ridge_c": Vector2.ZERO, "ridge_dir": Vector2(1, 0),
	}
	var rc = d.get("ridge_c")
	if rc is Array and rc.size() == 2:
		b["ridge_c"] = Vector2(float(rc[0]), float(rc[1]))
	var rd = d.get("ridge_dir")
	if rd is Array and rd.size() == 2:
		b["ridge_dir"] = Vector2(float(rd[0]), float(rd[1]))
	var dr = d.get("door")
	if dr is Array and dr.size() == 2:
		b["has_door"] = true
		b["door"] = Vector2(float(dr[0]), float(dr[1]))
	# dveře míst a domova sedí s interakcí E (bod dveří z pois.json)
	if key != "" and pois.has(key):
		var pd: Dictionary = pois[key]
		if pd.has("door_x") and pd.has("door_z"):
			b["has_door"] = true
			b["door"] = Vector2(float(pd["door_x"]), float(pd["door_z"]))
			b["door_forced"] = true
		_place_building[key] = id
	if home:
		_home_id = id
	_buildings[id] = b
	_polys[id] = poly
	var bb := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		bb = bb.expand(p)
	_boxes[id] = bb.grow(0.5)
	for cx in range(floori(bb.position.x / GRID_CELL), floori(bb.end.x / GRID_CELL) + 1):
		for cz in range(floori(bb.position.y / GRID_CELL), floori(bb.end.y / GRID_CELL) + 1):
			var k := Vector2i(cx, cz)
			if not _grid.has(k):
				_grid[k] = []
			_grid[k].append(id)


## Leží bod uvnitř jiné budovy než `id`? (Okno na společné zdi by bylo uvnitř sousedního domu.)
func _inside_other(p: Vector2, id: int) -> bool:
	var k := Vector2i(floori(p.x / GRID_CELL), floori(p.y / GRID_CELL))
	for oid_v in _grid.get(k, []):
		var oid: int = oid_v
		if oid == id:
			continue
		var bb: Rect2 = _boxes[oid]
		if bb.has_point(p) and Geometry2D.is_point_in_polygon(p, _polys[oid]):
			return true
	return false


# ------------------------------------------------------------------ generování

func _tile_of(tiles: Dictionary, p: Vector2) -> Tile:
	var k := Vector2i(floori(p.x / TILE), floori(p.y / TILE))
	if not tiles.has(k):
		tiles[k] = Tile.new()
	return tiles[k]


func _build_one(b: Dictionary, tiles: Dictionary) -> void:
	var poly: PackedVector2Array = b["poly"]
	var id: int = b["id"]
	var rule: Dictionary = RULES.get(b["type"], RULES["house"])
	var rng := RandomNumberGenerator.new()
	rng.seed = id * 7919 + 13
	var edges := _edges(poly)
	if edges.is_empty():
		return
	# vzhled budovy podle seedu
	var fi := _pick_weighted(FRAME_WEIGHTS, rng.randf())
	var look := {
		"frame": FRAME_COLORS[fi], "alpha": FRAME_ALPHA[fi],
		"shutter": SHUTTER_COLORS[rng.randi() % SHUTTER_COLORS.size()],
		"has_shutters": rng.randf() < float(rule.get("shutters", 0.0)),
		"door": DOOR_COLORS[rng.randi() % DOOR_COLORS.size()],
		"gate": GATE_COLORS[rng.randi() % GATE_COLORS.size()],
	}
	# vlna E: další detaily z vlastního generátoru (původní posloupnost `rng` – rozmístění oken – zůstává)
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = id * 104729 + 71
	var btype: String = b["type"]
	look["surround"] = btype == "house" and rng2.randf() < 0.45
	look["surround_col"] = SURROUND_COLORS[rng2.randi() % SURROUND_COLORS.size()]
	look["pipe"] = PIPE_COLORS[rng2.randi() % PIPE_COLORS.size()]
	look["plastered_chimney"] = rng2.randf() < 0.45

	# dveře / vrata
	var door_edge := -1
	var door_t := 0.0
	var kind: String = rule.get("door", "")
	if kind != "":
		var dw := DOOR_W
		if kind == "gate":
			dw = float(rule["gate"][0])
		var pick := _pick_door_edge(b, edges, dw)
		door_edge = pick[0]
		door_t = pick[1]
		if door_edge >= 0:
			door_t = _emit_door(tiles, b, edges[door_edge], door_t, kind, rule, look)
			if door_t < 0.0:
				door_edge = -1          # stěna u terénu moc nízká – dveře se vynechaly

	# okna
	var mode: String = rule.get("win", "none")
	if mode != "none":
		var cands := []
		var ww_r: Array = rule["ww"]
		var spacing: float = rule["spacing"]
		for ei in edges.size():
			var e: Dictionary = edges[ei]
			var elen: float = e["len"]
			if elen < MIN_EDGE:
				continue
			var usable := elen - 2.0 * WIN_MARGIN
			var cnt := maxi(1, roundi(usable / spacing))
			var step := usable / float(cnt)
			for k in cnt:
				var t := WIN_MARGIN + step * (float(k) + 0.5) + rng.randf_range(-0.12, 0.12) * step
				if ei == door_edge and absf(t - door_t) < 0.5 * (DOOR_W if kind == "door" else float(rule.get("gate", [3.0])[0])) + 0.5 * float(ww_r[1]) + 0.35:
					continue
				var op: Vector2 = e["o"]
				var up_: Vector2 = e["u"]
				var nn: Vector2 = e["n"]
				var p2 := op + up_ * t
				if _inside_other(p2 + nn * 0.4, id):
					continue
				cands.append([ei, t])
		var chosen := []
		if mode == "full":
			chosen = cands
		elif not cands.is_empty() and rng.randf() < float(rule.get("p", 0.5)):
			chosen = [cands[rng.randi() % cands.size()]]
		for c in chosen:
			var e2: Dictionary = edges[int(c[0])]
			var wh := rng.randf_range(float(rule["wh"][0]), float(rule["wh"][1]))
			var ww := rng.randf_range(float(ww_r[0]), float(ww_r[1]))
			var two: bool = rule.get("floors", false)
			_emit_window(tiles, b, e2, float(c[1]), float(rule["sill"]), 0, ww, wh, look, rng, two)
			if two:
				_emit_window(tiles, b, e2, float(c[1]), float(rule["sill"]) + FLOOR_H, 1, ww, wh, look, rng, two)

	# komín
	if rule.get("chimney", false):
		_emit_chimneys(tiles, b, rng, look)

	# okapové svody u domů a veřejných budov
	if btype == "house" or btype == "public":
		_emit_downpipes(tiles, b, edges, door_edge, door_t, kind, rule, look)


static func _pick_weighted(weights: Array, r: float) -> int:
	var acc := 0.0
	for i in weights.size():
		acc += float(weights[i])
		if r < acc:
			return i
	return weights.size() - 1


## Hrany půlorysu s vnější normálou `n`, směrem `u` (doprava při pohledu zvenku) a počátkem `o` (levý konec).
func _edges(poly: PackedVector2Array) -> Array:
	var out := []
	var n := poly.size()
	for i in n:
		var a := poly[i]
		var c := poly[(i + 1) % n]
		var d := c - a
		var elen := d.length()
		if elen < 0.5:
			continue
		var dir := d / elen
		var nrm := Vector2(dir.y, -dir.x)
		if Geometry2D.is_point_in_polygon((a + c) * 0.5 + nrm * 0.15, poly):
			nrm = -nrm
		var u := Vector2(nrm.y, -nrm.x)        # UP × n v rovině x, z
		var o := a if u.dot(dir) >= 0.0 else c
		out.append({"o": o, "u": u, "n": nrm, "len": elen})
	return out


## Hrana pro dveře a poloha na ní: nejblíž bodu dveří z dat (silnice / místo), jinak nejdelší stěna.
## Vrací [index hrany nebo −1, t].
func _pick_door_edge(b: Dictionary, edges: Array, width: float) -> Array:
	var need := width + 0.8
	var best := -1
	var best_score := INF
	var best_t := 0.0
	var forced: bool = b.get("door_forced", false)
	for ei in edges.size():
		var e: Dictionary = edges[ei]
		var elen: float = e["len"]
		if elen < need:
			continue
		var op: Vector2 = e["o"]
		var up_: Vector2 = e["u"]
		var t := elen * 0.5
		var score := -elen      # bez dat: nejdelší stěna
		if b["has_door"]:
			var target: Vector2 = b["door"]
			t = clampf((target - op).dot(up_), need * 0.5, elen - need * 0.5)
			var dist := (op + up_ * t).distance_to(target)
			score = dist - 0.05 * elen
			if not forced and elen < 3.0 + width:
				score += 4.0    # u dveří od silnice preferuj delší stěnu
		if score < best_score:
			best_score = score
			best = ei
			best_t = t
	if best >= 0 and b["has_door"] and forced and best_score > POI_DOOR_MAX:
		# bod z pois.json je moc daleko od půdorysu – ber nejdelší stěnu
		var longest := -1
		var ll := 0.0
		for ei in edges.size():
			if float(edges[ei]["len"]) > ll and float(edges[ei]["len"]) >= need:
				ll = edges[ei]["len"]
				longest = ei
		return [longest, ll * 0.5]
	return [best, best_t]


func _frame_of(e: Dictionary) -> Array:
	var nrm: Vector2 = e["n"]
	var u: Vector2 = e["u"]
	return [Vector3(nrm.x, 0.0, nrm.y), Vector3(u.x, 0.0, u.y)]


func _emit_window(tiles: Dictionary, b: Dictionary, e: Dictionary, t: float, sill: float, floor_i: int,
		ww: float, wh_in: float, look: Dictionary, rng: RandomNumberGenerator, two := false) -> void:
	var op: Vector2 = e["o"]
	var up_: Vector2 = e["u"]
	var p2 := op + up_ * t
	var gy := _terrain.height_at(p2.x, p2.y)
	var eave: float = b["eave"]
	var wh := wh_in
	if b["known"]:
		if floor_i > 0 and eave - gy < FLOOR2_MIN_WALL:
			return
		wh = minf(wh, eave - 0.2 - (gy + sill))
		if wh < 0.6 or (floor_i > 0 and wh < wh_in * 0.8):
			return
	var fr := _frame_of(e)
	var n3: Vector3 = fr[0]
	var u3: Vector3 = fr[1]
	var tile := _tile_of(tiles, p2)
	var kit: MeshKit = tile.kit
	var y0 := gy + sill
	var c3 := Vector3(p2.x, y0 + wh * 0.5, p2.y)
	var frame_col: Color = look["frame"]
	if look.get("surround", false):
		# šambrána: plochý omítkový rám 15 cm kolem okna, 2,4 cm před zdí (pod rámem i parapetem)
		var top := minf(wh * 0.5 + 0.15, eave - 0.03 - c3.y) if b["known"] else wh * 0.5 + 0.15
		var bot := wh * 0.5 + 0.17
		var cs := Vector3(c3.x, c3.y + (top - bot) * 0.5, c3.z)
		_box(kit, cs + n3 * 0.012, u3 * (ww * 0.5 + 0.15), Vector3.UP * ((top + bot) * 0.5), n3 * 0.012,
			look["surround_col"])
	# rám (přední strana 6,5 cm od zdi), parapet, sklo o 0,3 cm před rámem
	_box(kit, c3 + n3 * 0.03, u3 * (ww * 0.5 + 0.07), Vector3.UP * (wh * 0.5 + 0.07), n3 * 0.035, frame_col)
	_box(kit, Vector3(p2.x, y0 - 0.035, p2.y) + n3 * 0.06, u3 * (ww * 0.5 + 0.12), Vector3.UP * 0.035,
		n3 * 0.07, SILL_COLOR)
	if look["has_shutters"]:
		var sc: Color = look["shutter"]
		for s in [-1.0, 1.0]:
			_box(kit, c3 + n3 * 0.03 + u3 * (float(s) * (ww * 0.5 + 0.07 + 0.24)), u3 * 0.24,
				Vector3.UP * (wh * 0.5 + 0.07), n3 * 0.025, sc)
	var gp := c3 + n3 * 0.068
	var hu := u3 * (ww * 0.5)
	var hy := Vector3.UP * (wh * 0.5)
	var col := Color(rng.randf(), rng.randf(), rng.randf(), float(look["alpha"]))
	var bl := gp - hu - hy
	var tl := gp - hu + hy
	var tr := gp + hu + hy
	var br := gp + hu - hy
	_glass_quad(tile, bl, tl, tr, br, n3, col, Vector2(float(_light_index(int(b["id"]))), float(_room_of(col.b, floor_i, two))))


## M8.17: index budovy v textuře svícení (přidělí se při stavbě oken).
func _light_index(id: int) -> int:
	if _light_idx.has(id):
		return _light_idx[id]
	var i := _light_ids.size()
	_light_ids.append(id)
	_light_idx[id] = i
	return i


## M8.17: místnost okna (0 kuchyň, 1 obývák, 2 ložnice, 3 ostatní) – deterministicky z náhodného čísla okna.
static func _room_of(r: float, floor_i: int, two: bool) -> int:
	if floor_i > 0:
		return 2 if r < ROOM_SPLIT_UPPER else 3
	if two:
		if r < float(ROOM_SPLIT_GROUND[0]):
			return 0
		return 1 if r < float(ROOM_SPLIT_GROUND[1]) else 3
	for k in 3:
		if r < float(ROOM_SPLIT_1[k]):
			return k
	return 3


func _glass_quad(tile: Tile, bl: Vector3, tl: Vector3, tr: Vector3, br: Vector3, nrm: Vector3, col: Color,
		uv2 := Vector2(-1.0, 0.0)) -> void:
	# trojúhelníky ve směru hodinových ručiček při pohledu zvenku (jako MeshKit.quad)
	tile.gv.append_array(PackedVector3Array([bl, tl, tr, bl, tr, br]))
	tile.guv.append_array(PackedVector2Array([Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(0, 0),
		Vector2(1, 1), Vector2(1, 0)]))
	for _i in 6:
		tile.gn.append(nrm)
		tile.gc.append(col)
		tile.guv2.append(uv2)


## Dveře / vrata na stěně `e` v poloze `t`. Vrací skutečnou polohu na stěně, nebo −1, když se nevešly.
## Dveře nesmí přesáhnout okap (validátor: vrata 2,8 m o 0,32 m nad okapem): nejdřív se zkusí posunout po stěně
## k nižšímu terénu, pak se sníží (nejvýš na okap − 0,1 m), a pod DOOR_MIN_H se vynechají.
func _emit_door(tiles: Dictionary, b: Dictionary, e: Dictionary, t: float, kind: String, rule: Dictionary,
		look: Dictionary) -> float:
	var op: Vector2 = e["o"]
	var up_: Vector2 = e["u"]
	var nrm: Vector2 = e["n"]
	var w := DOOR_W
	var h := DOOR_H
	if kind == "gate":
		w = float(rule["gate"][0])
		h = float(rule["gate"][1])
	var base := DOOR_STEP if kind == "door" else 0.02
	var top_extra := 0.12 if kind == "door" else 0.0     # zárubeň nad dveřmi
	var p2 := op + up_ * t
	var gy := _terrain.height_at(p2.x, p2.y)
	if b["known"]:
		var eave: float = b["eave"]
		var room := eave - 0.1 - base - top_extra       # nejvyšší přípustná výška dveří nad terénem
		if gy + h > room:
			var elen: float = e["len"]
			var lo := minf(w * 0.5 + 0.4, elen * 0.5)
			var hi := maxf(elen - w * 0.5 - 0.4, lo)
			var best_t := t
			var best_d := INF
			var low_t := t
			var low_g := gy
			for i in 33:
				var tt := lerpf(lo, hi, float(i) / 32.0)
				var q := op + up_ * tt
				var g := _terrain.height_at(q.x, q.y)
				if g < low_g:
					low_g = g
					low_t = tt
				if g + h <= room and absf(tt - t) < best_d:
					best_d = absf(tt - t)
					best_t = tt
			if best_d < INF:
				t = best_t
			else:
				t = low_t
				h = room - low_g
				if h < (DOOR_MIN_H if kind == "door" else 1.9):
					return -1.0
			p2 = op + up_ * t
			gy = _terrain.height_at(p2.x, p2.y)
			h = minf(h, room - gy)
	var fr := _frame_of(e)
	var n3: Vector3 = fr[0]
	var u3: Vector3 = fr[1]
	var tile := _tile_of(tiles, p2)
	var kit: MeshKit = tile.kit
	if kind == "gate":
		var gcol: Color = look["gate"]
		var c := Vector3(p2.x, gy + h * 0.5 + 0.02, p2.y)
		_box(kit, c + n3 * 0.04, u3 * (w * 0.5), Vector3.UP * (h * 0.5), n3 * 0.04, gcol)
		for f in [0.3, 0.62]:
			_box(kit, Vector3(p2.x, gy + 0.02 + h * float(f), p2.y) + n3 * 0.085, u3 * (w * 0.5),
				Vector3.UP * 0.035, n3 * 0.015, gcol.darkened(0.35))
		# svislé dělení křídel a zárubeň
		_box(kit, Vector3(p2.x, gy + 0.02 + h * 0.5, p2.y) + n3 * 0.085, u3 * 0.02, Vector3.UP * (h * 0.5),
			n3 * 0.012, gcol.darkened(0.45))
		_box(kit, Vector3(p2.x, gy + h * 0.5 + 0.04, p2.y) + n3 * 0.025, u3 * (w * 0.5 + 0.08),
			Vector3.UP * (h * 0.5 + 0.02), n3 * 0.025, gcol.darkened(0.25))
	else:
		var y_base := gy + DOOR_STEP
		var fcol: Color = look["frame"]
		var dcol: Color = look["door"]
		_box(kit, Vector3(p2.x, y_base + (h + 0.12) * 0.5, p2.y) + n3 * 0.03, u3 * (w * 0.5 + 0.1),
			Vector3.UP * ((h + 0.12) * 0.5), n3 * 0.03, fcol)
		_box(kit, Vector3(p2.x, y_base + h * 0.5, p2.y) + n3 * 0.055, u3 * (w * 0.5), Vector3.UP * (h * 0.5),
			n3 * 0.02, dcol)
		# kazetové výplně (dvě vystouplé desky) – dveře nejsou plochý obdélník
		for fy in [0.27, 0.7]:
			var ph := h * (0.3 if fy < 0.5 else 0.36)
			_box(kit, Vector3(p2.x, y_base + h * float(fy), p2.y) + n3 * 0.078, u3 * (w * 0.5 - 0.12),
				Vector3.UP * (ph * 0.5), n3 * 0.006, dcol.lightened(0.06))
		_box(kit, Vector3(p2.x, y_base + 1.0, p2.y) + n3 * 0.09 + u3 * (w * 0.5 - 0.14), u3 * 0.03,
			Vector3.UP * 0.07, n3 * 0.02, Color(0.6, 0.5, 0.2))
		# schod (spodek hluboko pod terénem, ať nevisí na svahu)
		_box(kit, Vector3(p2.x, gy + DOOR_STEP - 0.25, p2.y) + n3 * 0.28, u3 * (w * 0.5 + 0.25), Vector3.UP * 0.25,
			n3 * 0.3, STEP_COLOR)
	var id: int = b["id"]
	_doors[id] = {"pos": Vector3(p2.x, gy, p2.y), "normal": n3, "yaw": atan2(nrm.x, nrm.y), "width": w,
		"kind": kind, "height": h}
	return t


## Okapové svody: dvě svislé trubky u rohů okapové stěny (u sedlové střechy stěna rovnoběžná s hřebenem),
## od terénu pod přesah střechy, dole s výtokovým kolenem. Ne u stěn sousedících s jinou budovou a u dveří.
func _emit_downpipes(tiles: Dictionary, b: Dictionary, edges: Array, door_edge: int, door_t: float, kind: String,
		rule: Dictionary, look: Dictionary) -> void:
	if not b["known"]:
		return
	var eave: float = b["eave"]
	var rdir: Vector2 = b["ridge_dir"]
	var gable: bool = b["shape"] != "flat" and b["shape"] != "hipped" and rdir.length() > 0.5
	var best := -1
	var bl := 0.0
	for ei in edges.size():
		var e: Dictionary = edges[ei]
		var u: Vector2 = e["u"]
		if gable and absf(u.dot(rdir.normalized())) < 0.9:
			continue
		if float(e["len"]) > bl:
			bl = e["len"]
			best = ei
	if best < 0 or bl < 3.0:
		return
	var e2: Dictionary = edges[best]
	var op: Vector2 = e2["o"]
	var up_: Vector2 = e2["u"]
	var nn: Vector2 = e2["n"]
	var fr := _frame_of(e2)
	var n3: Vector3 = fr[0]
	var u3: Vector3 = fr[1]
	var col: Color = look["pipe"]
	var dw := DOOR_W if kind == "door" else float(rule.get("gate", [3.0])[0])
	for tt in [0.2, bl - 0.2]:
		if best == door_edge and absf(float(tt) - door_t) < dw * 0.5 + 0.35:
			continue
		var p2 := op + up_ * float(tt)
		if _inside_other(p2 + nn * 0.35, int(b["id"])):
			continue
		var gy := _terrain.height_at(p2.x, p2.y)
		var y1 := eave - 0.05
		if y1 - gy < 1.5:
			continue
		var c := Vector3(p2.x, 0.0, p2.y) + n3 * (PIPE_R + 0.035)
		var tile := _tile_of(tiles, p2)
		var y0 := gy + 0.28
		_box(tile.kit, Vector3(c.x, (y0 + y1) * 0.5, c.z), u3 * PIPE_R, Vector3.UP * ((y1 - y0) * 0.5),
			n3 * PIPE_R, col)
		# výtokové koleno (šikmo od zdi) a objímky
		var bend := Basis(u3, -0.6)
		_box(tile.kit, Vector3(c.x, gy + 0.17, c.z) + n3 * 0.07, u3 * PIPE_R, bend * (Vector3.UP * 0.13),
			bend * (n3 * PIPE_R), col)
		var yk := y0 + 0.6
		while yk < y1 - 0.3:
			_box(tile.kit, Vector3(c.x, yk, c.z), u3 * (PIPE_R + 0.008), Vector3.UP * 0.012,
				n3 * (PIPE_R + 0.008), col.darkened(0.3))
			yk += 1.8


func _emit_chimneys(tiles: Dictionary, b: Dictionary, rng: RandomNumberGenerator, look: Dictionary = {}) -> void:
	var shape: String = b["shape"]
	var ridge: float = b["ridge"]
	var eave: float = b["eave"]
	if not b["known"] or shape == "flat" or ridge - eave < 0.8:
		return
	var poly: PackedVector2Array = b["poly"]
	var half: float = b["ridge_half"]
	var rc: Vector2 = b["ridge_c"]
	var rdir: Vector2 = b["ridge_dir"]
	var count := 2 if (float(b["area"]) > 220.0 and half > 4.0) else 1
	var sign_0 := 1.0 if rng.randf() < 0.5 else -1.0
	for k in count:
		var off := 0.0
		if half > 0.6:
			if count == 2:
				off = (sign_0 if k == 0 else -sign_0) * rng.randf_range(0.25, 0.6) * half
			else:
				off = sign_0 * rng.randf_range(0.0, 0.6) * half
		var p2 := rc + rdir * off
		if not Geometry2D.is_point_in_polygon(p2, poly):
			p2 = rc
			if not Geometry2D.is_point_in_polygon(p2, poly):
				continue
		var top := ridge + rng.randf_range(0.7, 1.2)
		var base_y := ridge - 0.9
		var d3 := Vector3(rdir.x, 0.0, rdir.y).normalized()
		var s3 := Vector3(-d3.z, 0.0, d3.x)
		var tile := _tile_of(tiles, p2)
		var kit: MeshKit = tile.kit
		var c := Vector3(p2.x, (top + base_y) * 0.5, p2.y)
		var plastered: bool = look.get("plastered_chimney", false)
		_box(kit, c, d3 * 0.28, Vector3.UP * ((top - base_y) * 0.5), s3 * 0.28, CHIMNEY_PLASTER if plastered else BRICK)
		# římsa pod hlavou komína a krycí deska
		_box(kit, Vector3(p2.x, top - 0.12, p2.y), d3 * 0.32, Vector3.UP * 0.04, s3 * 0.32,
			CHIMNEY_PLASTER.darkened(0.1) if plastered else BRICK.darkened(0.15))
		_box(kit, Vector3(p2.x, top + 0.05, p2.y), d3 * 0.36, Vector3.UP * 0.06, s3 * 0.36, CAP)
		_chimneys.append({"id": b["id"], "pos": Vector3(p2.x, top + 0.11, p2.y), "base_y": base_y})


## Kvádr se středem `c` a poloosami `ax`, `ay`, `az` (bez zadní stěny a spodku – přilehlé ke zdi / terénu).
static func _box(kit: MeshKit, c: Vector3, ax: Vector3, ay: Vector3, az: Vector3, col: Color) -> void:
	var faces := [[ax, ay, az], [-ax, ay, az], [ay, az, ax], [az, ax, ay]]
	for f in faces:
		var nrm: Vector3 = f[0]
		var p: Vector3 = f[1]
		var q: Vector3 = f[2]
		var m := c + nrm
		var a := m - p - q
		var b := m - p + q
		var cc := m + p + q
		var d := m + p - q
		var n := (cc - a).cross(b - a)
		if n.dot(nrm) >= 0.0:
			kit.quad(a, b, cc, d, col)
		else:
			kit.quad(d, cc, b, a, col)


func _commit_tiles(tiles: Dictionary) -> void:
	for k in tiles:
		var t: Tile = tiles[k]
		if not t.kit.is_empty():
			var mi := MeshKit.mesh_instance(self, t.kit.commit(MeshKit.vc_material(0.85)), VIS_END)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if not t.gv.is_empty():
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = t.gv
			arr[Mesh.ARRAY_NORMAL] = t.gn
			arr[Mesh.ARRAY_COLOR] = t.gc
			arr[Mesh.ARRAY_TEX_UV] = t.guv
			arr[Mesh.ARRAY_TEX_UV2] = t.guv2
			var m := ArrayMesh.new()
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			m.surface_set_material(0, _glass_mat)
			var gi := MeshKit.mesh_instance(self, m, VIS_END)
			gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ------------------------------------------------------------------ noční svícení

## Přepočte podíl svítících oken (jednou za herní půlhodinu; `force` = hned).
func _update_lights(force: bool) -> void:
	if _world == null or _world.clock == null or _glass_mat == null:
		return
	var clock: Clock = _world.clock
	var slot := clock.day() * 48 + int(floor(clock.hour() * 2.0))
	var hs: Households = _world.households
	var house_on := hs != null and hs.enabled() and _lit_tex != null
	var ver := hs.version if house_on else -1
	if slot == _last_slot and ver == _hh_ver and not force:
		return
	_last_slot = slot
	_hh_ver = ver
	var dark := 1.0 - smoothstep(0.5, 1.0, clock.daylight())
	_glass_mat.set_shader_parameter("lit_frac", lit_fraction(clock.hour()) * dark)
	_glass_mat.set_shader_parameter("dark", dark)
	_glass_mat.set_shader_parameter("house_mode", 1.0 if house_on else 0.0)
	if house_on:
		_fill_house_lights(hs, clock.hour())
	_glass_mat.set_shader_parameter("slot", float(slot % 4096))


## M8.17: textura svícení budov (RGBA8, texel = budova, kanály = místnosti).
func _make_lit_texture() -> void:
	var n := maxi(_light_ids.size(), 1)
	var hgt := int(ceil(float(n) / float(LIT_TEX_W)))
	_lit_bytes.resize(LIT_TEX_W * hgt * 4)
	_lit_bytes.fill(0)
	_lit_img = Image.create_from_data(LIT_TEX_W, hgt, false, Image.FORMAT_RGBA8, _lit_bytes)
	_lit_tex = ImageTexture.create_from_image(_lit_img)
	_glass_mat.set_shader_parameter("house_lit", _lit_tex)
	_glass_mat.set_shader_parameter("house_w", LIT_TEX_W)


## M8.17: naplní texturu svícení – domácnosti podle obsazenosti místností, ostatní budovy podle křivky `LIT_CURVE`.
## Jednou za herní půlhodinu a po hodinovém kroku domácností (~300 budov, žádná práce za snímek).
func _fill_house_lights(hs: Households, h: float) -> void:
	var g := int(clampf(lit_fraction(h), 0.0, 1.0) * 255.0)
	for i in _light_ids.size():
		var o := i * 4
		if hs.window_rooms(int(_light_ids[i]), h, _room_buf):
			_lit_bytes[o] = int(_room_buf[0] * 255.0)
			_lit_bytes[o + 1] = int(_room_buf[1] * 255.0)
			_lit_bytes[o + 2] = int(_room_buf[2] * 255.0)
			_lit_bytes[o + 3] = int(_room_buf[3] * 255.0)
		else:
			_lit_bytes[o] = g
			_lit_bytes[o + 1] = g
			_lit_bytes[o + 2] = g
			_lit_bytes[o + 3] = g
	_lit_img.set_data(LIT_TEX_W, _lit_img.get_height(), false, Image.FORMAT_RGBA8, _lit_bytes)
	_lit_tex.update(_lit_img)
