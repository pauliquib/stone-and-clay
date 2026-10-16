## Pěšiny z opakované chůze (M8.14, `World.footpaths`, přepínač realismu `ground_veg`): trvalá mapa **opotřebení**
## porostu 0..1 v rastru 1 m/px. Podle čeho: každý průchod (hráč, vesničan, pes, zvěř, kůň) přičte k pixelu
## `WEAR_STEP` (nasycení k 1), porost zarůstá exponenciálně s časovou konstantou `REGROW_DAYS` (bez chůze za týdny
## zmizí). Kumulace × zarůstání = na trase, kudy se chodí denně, vznikne prošlapaná hlína; kudy jednou, nic.
##
## Dlaždice `TILE_M` = 64 m po 64 px (`Image.FORMAT_R8`, 4 kB) vznikají až zápisem a drží se v paměti (nejvýš
## `MAX_TILES`, nejdéle nepoužité se zapomenou). Shadery (terén – hlína, tráva – nižší a řidší) čtou okno 3 × 3 dlaždic
## kolem hráče jako **kruhový buffer** v globálním `path_tex` (stejná technika jako `RutMap`, M8.13): při přejezdu hranice
## dlaždice se přepíšou jen nové sloty, jeden za snímek; textura se nahrává jen po změně, nejvýš po `UPLOAD_S`.
## Pozice se nesbírají z cizích skriptů – vlastní vzorkování po `SAMPLE_S` (hráči, `World.bots_root`, zvěř v okolí).
## Uložení `to_dict` / `restore` (klíč `footpaths`, jen dlaždice s opotřebením, ZSTD + base64, ≤ `SAVE_MAX_KB`).
class_name Footpaths
extends Node

const TILE_M := 64.0
const TILE_PX := 64
const PX_M := TILE_M / TILE_PX          # 1 m na pixel
const WIN_T := 3
const WIN_PX := TILE_PX * WIN_T
const NONE := Vector2i(-99999, -99999)

## --- laditelné (F3 → Příroda/Louky a podrost) ---
static var WEAR_STEP := 0.07            # přírůstek opotřebení za jeden krok přes pixel (~10 průchodů = pěšina)
static var WEAR_ANIMAL := 0.5           # zvěř a psi šlapou slaběji (×)
static var REGROW_DAYS := 9.0           # d – časová konstanta zarůstání (e-násobně)
static var STEP_M := 0.8                # m – vzorek trasy (kratší pohyb se nepočítá)
static var JUMP_M := 8.0                # m – delší skok mezi vzorky = teleport / spánek (nepíše se)
static var SAMPLE_S := 0.4              # s – jak často se berou polohy chodců
static var AGENT_R := 320.0             # m – chodci dál od hráče se nesledují (00_PRINCIPY kap. 6)
static var FADE_APPLY := 0.95           # zarůstání se na obraz dlaždice aplikuje, až násobek klesne pod tohle
static var FORGET_DAYS := 60            # dlaždice bez zápisu déle než tohle se zapomene
static var MAX_TILES := 900             # strop dlaždic v paměti (3,6 MB)
static var SAVE_MAX_KB := 768
static var UPLOAD_S := 0.5
static var PATH_K := 1.0                # shader: síla projevu pěšin (globální path_k)

var world: World
var _tiles := {}                        # Vector2i → Image (R8)
var _touch := {}                        # Vector2i → jd posledního zápisu
var _fade := {}                         # Vector2i → čekající násobek (1 = nic)
var _last := {}                         # instance id chodce → Vector2 posledního vzorku
var _win: Image
var _tex: ImageTexture
var _empty: Image
var _slot := []
var _center := NONE
var _blit_q: Array[int] = []
var _dirty := false
var _upload_t := 0.0
var _sample_t := 0.0
var _on := false


func setup(w: World) -> void:
	world = w
	name = "Footpaths"
	_win = Image.create(WIN_PX, WIN_PX, false, Image.FORMAT_R8)
	_tex = ImageTexture.create_from_image(_win)
	_empty = Image.create(TILE_PX, TILE_PX, false, Image.FORMAT_R8)
	_slot.resize(WIN_T * WIN_T)
	_slot.fill(NONE)
	RenderingServer.global_shader_parameter_set("path_tex", _tex)
	RenderingServer.global_shader_parameter_set("path_size", 0.0)
	RenderingServer.global_shader_parameter_set("path_k", PATH_K)
	w.eco_day.connect(_on_eco_day)


func enabled() -> bool:
	return world != null and world.realism_on("ground_veg")


## Laditelné hodnoty shaderu (po změně v F3).
func apply_shader_params() -> void:
	RenderingServer.global_shader_parameter_set("path_k", PATH_K)


# ------------------------------------------------------------------ zápis / čtení

## Krok chodce v bodě (síla `k` × WEAR_STEP).
func step_at(pos: Vector3, k := 1.0) -> void:
	var px := floori(pos.x / PX_M)
	var pz := floori(pos.z / PX_M)
	var t := Vector2i(floori(float(px) / TILE_PX), floori(float(pz) / TILE_PX))
	var img := _tile(t, true)
	var lx := px - t.x * TILE_PX
	var lz := pz - t.y * TILE_PX
	var f: float = _fade.get(t, 1.0)
	var v := img.get_pixel(lx, lz).r * f
	v = minf(v + WEAR_STEP * k * (1.0 - v * 0.5), 1.0) / maxf(f, 0.001)   # obraz drží hodnotu před čekajícím zarůstáním
	img.set_pixel(lx, lz, Color(minf(v, 1.0), 0.0, 0.0))
	_touch[t] = world.clock.jd() if world.clock != null else 0
	var s := _slot_of(t)
	if _slot[s] == t:
		_win.set_pixel((s % WIN_T) * TILE_PX + lx, (s / WIN_T) * TILE_PX + lz, Color(minf(v * f, 1.0), 0.0, 0.0))
		_dirty = true


## Opotřebení 0..1 v bodě (pro zvěř M8.15 – stezky, M8.17).
func wear_at(pos: Vector3) -> float:
	var px := floori(pos.x / PX_M)
	var pz := floori(pos.z / PX_M)
	var t := Vector2i(floori(float(px) / TILE_PX), floori(float(pz) / TILE_PX))
	var img: Image = _tiles.get(t)
	if img == null:
		return 0.0
	return img.get_pixel(px - t.x * TILE_PX, pz - t.y * TILE_PX).r * float(_fade.get(t, 1.0))


func _slot_of(t: Vector2i) -> int:
	return posmod(t.y, WIN_T) * WIN_T + posmod(t.x, WIN_T)


func _tile(t: Vector2i, create: bool) -> Image:
	var img: Image = _tiles.get(t)
	if img != null or not create:
		return img
	if _tiles.size() >= MAX_TILES:
		_forget_oldest()
	img = Image.create(TILE_PX, TILE_PX, false, Image.FORMAT_R8)
	_tiles[t] = img
	_fade[t] = 1.0
	return img


func _forget_oldest() -> void:
	var old := NONE
	var old_jd := 1 << 30
	for t in _touch:
		if int(_touch[t]) < old_jd:
			old_jd = int(_touch[t])
			old = t
	if old != NONE:
		_drop(old)


# ------------------------------------------------------------------ snímek: vzorkování chodců, okno shaderu

func _process(delta: float) -> void:
	if world == null:
		return
	var on := enabled()
	if on != _on:
		_on = on
		if not on:
			_center = NONE
			RenderingServer.global_shader_parameter_set("path_size", 0.0)
	if not on:
		return
	var p := _focus_player()
	if p == null:
		return
	var fp := p.global_position
	_sample_t -= delta
	if _sample_t <= 0.0:
		_sample_t = SAMPLE_S
		_sample(fp)
	var c := Vector2i(floori(fp.x / TILE_M), floori(fp.z / TILE_M))
	if c != _center:
		_center = c
		for oz in range(-1, 2):
			for ox in range(-1, 2):
				var s := _slot_of(c + Vector2i(ox, oz))
				if _slot[s] != c + Vector2i(ox, oz) and not _blit_q.has(s):
					_blit_q.append(s)
		RenderingServer.global_shader_parameter_set("path_origin", Vector2((c.x - 1) * TILE_M, (c.y - 1) * TILE_M))
		RenderingServer.global_shader_parameter_set("path_size", TILE_M * WIN_T)
	if not _blit_q.is_empty():
		_blit_slot(_blit_q.pop_front())
	else:
		_fade_one()
	_upload_t -= delta
	if _dirty and _upload_t <= 0.0:
		_upload_t = UPLOAD_S
		_dirty = false
		_tex.update(_win)


func _focus_player() -> Player:
	for id in world.players:
		return world.players[id]
	return null


## Polohy chodců → kroky (pohyb aspoň STEP_M od posledního vzorku, ne skok).
func _sample(fp: Vector3) -> void:
	var r2 := AGENT_R * AGENT_R
	for id in world.players:
		var pl: Player = world.players[id]
		if pl != null and pl.car == null:
			_track(pl, 1.0)
	if world.bots_root != null:
		for n in world.bots_root.get_children():
			var b := n as Node3D
			if b != null and b.visible and fp.distance_squared_to(b.global_position) < r2:
				_track(b, WEAR_ANIMAL if b is Dog else 1.0)
	if world.fauna != null:
		var ar := minf(AGENT_R, 150.0)
		for a in world.fauna.animals:
			var an := a as Node3D
			if an != null and is_instance_valid(an) and fp.distance_squared_to(an.global_position) < ar * ar:
				_track(an, WEAR_ANIMAL)


func _track(n: Node3D, k: float) -> void:
	var id := n.get_instance_id()
	var p := n.global_position
	var q := Vector2(p.x, p.z)
	if not _last.has(id):
		_last[id] = q
		return
	var d := q.distance_to(_last[id])
	if d < STEP_M:
		return
	_last[id] = q
	if d > JUMP_M:
		return
	step_at(p, k)


func _blit_slot(s: int) -> void:
	var t := NONE
	for oz in range(-1, 2):
		for ox in range(-1, 2):
			var tt := _center + Vector2i(ox, oz)
			if _slot_of(tt) == s:
				t = tt
	_slot[s] = t
	var img: Image = _tiles.get(t) if t != NONE else null
	if img != null and float(_fade.get(t, 1.0)) < 0.999:
		img.adjust_bcs(float(_fade[t]), 1.0, 1.0)
		_fade[t] = 1.0
	_win.blit_rect(img if img != null else _empty, Rect2i(0, 0, TILE_PX, TILE_PX), Vector2i((s % WIN_T) * TILE_PX, (s / WIN_T) * TILE_PX))
	_dirty = true


## Jedna dlaždice s nahromaděným zarůstáním → aplikovat na obraz (a do okna).
func _fade_one() -> void:
	for t in _fade:
		var f: float = _fade[t]
		if f >= FADE_APPLY:
			continue
		var img: Image = _tiles.get(t)
		if img != null:
			img.adjust_bcs(f, 1.0, 1.0)
		_fade[t] = 1.0
		var s := _slot_of(t)
		if _slot[s] == t and not _blit_q.has(s):
			_blit_q.append(s)
		return


func _drop(t: Vector2i) -> void:
	_tiles.erase(t)
	_touch.erase(t)
	_fade.erase(t)
	var s := _slot_of(t)
	if _slot[s] == t and not _blit_q.has(s):
		_blit_q.append(s)


## Zarůstání: násobek exp(−dny / REGROW_DAYS) (zima: pomaleji – porost neroste).
func _on_eco_day(jd: int) -> void:
	var month := int(Clock.from_jdn(jd)["month"])
	var k := 0.3 if month <= 2 or month >= 12 else 1.0
	var f := exp(-k / maxf(REGROW_DAYS, 0.1))
	_last.clear()                          # chodci, kteří zmizeli, se zapomenou (první vzorek dne jen založí polohu)
	var gone: Array[Vector2i] = []
	for t in _fade:
		_fade[t] = float(_fade[t]) * f
		if jd - int(_touch.get(t, jd)) > FORGET_DAYS:
			gone.append(t)
	for t in gone:
		_drop(t)


# ------------------------------------------------------------------ ukládání

func to_dict() -> Dictionary:
	var rows: Array = []
	for t in _tiles:
		rows.append([int(_touch.get(t, 0)), t])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) > int(b[0]))
	var out: Array = []
	var total := 0
	for r in rows:
		var t: Vector2i = r[1]
		var img: Image = _tiles[t]
		var data := img.get_data().compress(FileAccess.COMPRESSION_ZSTD)
		total += data.size()
		if total > SAVE_MAX_KB * 1024:
			break
		out.append({"x": t.x, "z": t.y, "jd": int(r[0]), "f": float(_fade.get(t, 1.0)), "d": Marshalls.raw_to_base64(data)})
	return {"v": 1, "tiles": out}


## Starý save bez klíče = žádné pěšiny.
func restore(d: Dictionary) -> void:
	_tiles.clear()
	_touch.clear()
	_fade.clear()
	_last.clear()
	for e in d.get("tiles", []):
		if not (e is Dictionary):
			continue
		var raw := Marshalls.base64_to_raw(String(e.get("d", ""))).decompress(TILE_PX * TILE_PX, FileAccess.COMPRESSION_ZSTD)
		if raw.size() != TILE_PX * TILE_PX:
			continue
		var t := Vector2i(int(e.get("x", 0)), int(e.get("z", 0)))
		_tiles[t] = Image.create_from_data(TILE_PX, TILE_PX, false, Image.FORMAT_R8, raw)
		_touch[t] = int(e.get("jd", 0))
		_fade[t] = float(e.get("f", 1.0))
	_slot.fill(NONE)
	_center = NONE
	_blit_q.clear()


## Ladicí vrstva „pesiny“ (F2 → mapa): opotřebení jako hnědá.
func debug_color(x: float, z: float) -> Color:
	var w := wear_at(Vector3(x, 0.0, z))
	if w < 0.02:
		return Color(0, 0, 0, 0)
	return Color(0.55, 0.38, 0.2, clampf(w, 0.2, 0.9))
