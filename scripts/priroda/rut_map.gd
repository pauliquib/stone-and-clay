## Koleje a stopy v blátě (M8.13, `World.ruts`): trvalá **deformační mapa** hloubky (m) v okolí hráče.
##
## Svět je rozdělený na dlaždice `TILE_M` = 64 m po `TILE_PX` = 256 px (0,25 m/px, `Image.FORMAT_RH`). Dlaždice vzniká,
## až do ní kolo / bota / kopyto poprvé zapíše (`stamp`), drží se v paměti (nejvýš `MAX_LOADED`), vzdálené se komprimují
## (ZSTD) a ukládají do savu (jen dlaždice se stopami, nejvýš `SAVE_MAX_KB`, starší než `FORGET_DAYS` se zapomenou).
## Shader terénu (`terrain.gdshader`, `rut_*`) čte okno 3 × 3 dlaždic kolem hráče jako **kruhový buffer** (textura 768²
## s opakováním, slot dlaždice = index mod 3 – při přejezdu hranice se přepíšou jen 3 sloty, jeden za snímek) →
## tmavší, mokrá, vyjetá stopa (posun normál, louže v hlubších kolejích za mokra). Textura se nahrává jen po změně,
## nejvýš po `UPLOAD_S`.
##
## Mizení (přes `World.eco_hour`): hloubka × exp(−dt_h · (FADE_DRY_H + FADE_RAIN_H · déšť + FADE_WET_H · vlhkost)) –
## déšť koleje rozmáčí a zarovná, sucho je ztvrdí (zůstanou dny), zamrzlá půda je drží (× FADE_FROZEN). Násobek se
## na obraz dlaždice aplikuje líně (`Image.adjust_bcs`, ~1 ms / dlaždice, jedna za snímek), až klesne pod FADE_APPLY.
class_name RutMap
extends Node

const TILE_M := 64.0
const TILE_PX := 256
const PX_M := TILE_M / TILE_PX          # 0,25 m na pixel
const WIN_T := 3                        # okno shaderu: 3 × 3 dlaždice
const WIN_PX := TILE_PX * WIN_T
const NONE := Vector2i(-99999, -99999)

static var FADE_DRY_H := 0.0006         # mizení za suchého počasí (1/h) – ~1,4 % za den
static var FADE_RAIN_H := 0.03          # + při plném dešti (1/h) – den lijáku ≈ zarovná
static var FADE_WET_H := 0.004          # + rozmáčená půda (1/h × vlhkost nad WET_FROM)
static var FADE_FROZEN := 0.1           # zamrzlá půda: mizení × tohle
static var FADE_APPLY := 0.97           # násobek se aplikuje na obraz, až klesne pod tohle
static var FADE_DROP := 0.03            # pod tímto násobkem se dlaždice smaže (stopy zmizely)
static var FORGET_DAYS := 60            # dlaždice bez nové stopy déle než tohle (dny) se zapomene
static var SAVE_MAX_KB := 2048          # strop dat kolejí v savu (kB)
static var MAX_DEPTH := 0.3             # nejhlubší zapsaná kolej (m)
static var MAX_LOADED := 24             # dlaždic v paměti (nekomprimovaných, 128 kB / ks)
static var UPLOAD_S := 0.25             # nejčastější nahrání textury do GPU (s)
static var RUT_DARK := 0.55             # shader: ztmavení v koleji
static var RUT_NORMAL := 0.6            # shader: síla posunu normál (svahy koleje)
static var RUT_PUDDLE := 1.0            # shader: louže v hlubších kolejích za mokra
static var RUT_VIS_M := 120.0           # shader: koleje se kreslí do této vzdálenosti od kamery (m)

var world: World
var _tiles := {}                        # Vector2i → Image (načtené)
var _packed := {}                       # Vector2i → PackedByteArray (ZSTD, uložené / odložené)
var _touch := {}                        # Vector2i → jd poslední stopy
var _fade := {}                         # Vector2i → čekající násobek hloubky (1 = nic)
var _fade_scan := true                  # M8.19B: má smysl procházet dlaždice (po hodinovém kroku / načtení), jinak ne každý snímek
var _win: Image
var _tex: ImageTexture
var _slot := []                         # 9 slotů okna → Vector2i dlaždice, kterou drží (NONE = prázdný)
var _center := NONE
var _blit_q: Array[int] = []            # sloty okna k přepsání
var _dirty := false
var _upload_t := 0.0
var _evict_t := 0.0
var _mat: ShaderMaterial
var _empty: Image


func setup(w: World) -> void:
	world = w
	Terramech.bind(w)
	_win = Image.create(WIN_PX, WIN_PX, false, Image.FORMAT_RH)
	_tex = ImageTexture.create_from_image(_win)
	_empty = Image.create(TILE_PX, TILE_PX, false, Image.FORMAT_RH)
	_slot.resize(WIN_T * WIN_T)
	_slot.fill(NONE)
	if w.terrain != null:
		_mat = w.terrain.material
	if _mat != null:
		_mat.set_shader_parameter("rut_tex", _tex)
		_mat.set_shader_parameter("rut_rect", Vector4.ZERO)
		apply_shader_params()
	w.eco_hour.connect(_on_eco_hour)
	DevTune.hub().changed.connect(_on_tune)


func _on_tune(id: String, _v: Variant) -> void:
	if id.begins_with("ruts."):
		apply_shader_params()


func apply_shader_params() -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("rut_dark", RUT_DARK)
	_mat.set_shader_parameter("rut_normal", RUT_NORMAL)
	_mat.set_shader_parameter("rut_puddle", RUT_PUDDLE)
	_mat.set_shader_parameter("rut_vis", RUT_VIS_M)


func enabled() -> bool:
	return Terramech.enabled()


# ------------------------------------------------------------------ zápis / čtení

## Otisk: kruh o poloměru `half_w` (m) s hloubkou `depth` (m) uprostřed, k okraji mělčí; hloubka = max(stávající, nová).
func stamp(pos: Vector3, half_w: float, depth: float) -> void:
	if depth <= 0.002 or not enabled():
		return
	depth = minf(depth, MAX_DEPTH)
	var gx := floori(pos.x / PX_M)
	var gz := floori(pos.z / PX_M)
	var r := maxi(ceili(half_w / PX_M - 0.5), 0)
	var r2 := float((r + 1) * (r + 1))
	var day := world.clock.jd() if world != null and world.clock != null else 0
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var q := float(dx * dx + dz * dz)
			if q > r2:
				continue
			var d := depth * (1.0 - 0.5 * q / r2)
			_write(gx + dx, gz + dz, d, day)


func _write(px: int, pz: int, d: float, day: int) -> void:
	var t := Vector2i(floori(float(px) / TILE_PX), floori(float(pz) / TILE_PX))
	var img := _tile(t, true)
	var lx := px - t.x * TILE_PX
	var lz := pz - t.y * TILE_PX
	if img.get_pixel(lx, lz).r >= d:
		return
	img.set_pixel(lx, lz, Color(d, 0.0, 0.0))
	_touch[t] = day
	var s := _slot_of(t)
	if _slot[s] == t:
		_win.set_pixel((s % WIN_T) * TILE_PX + lx, (s / WIN_T) * TILE_PX + lz, Color(d, 0.0, 0.0))
		_dirty = true


## Hloubka koleje v bodě (m) – jen načtené dlaždice (volat s throttlingem).
func depth_at(pos: Vector3) -> float:
	var px := floori(pos.x / PX_M)
	var pz := floori(pos.z / PX_M)
	var t := Vector2i(floori(float(px) / TILE_PX), floori(float(pz) / TILE_PX))
	var img: Image = _tiles.get(t)
	if img == null:
		return 0.0
	return img.get_pixel(px - t.x * TILE_PX, pz - t.y * TILE_PX).r * float(_fade.get(t, 1.0))


func _slot_of(t: Vector2i) -> int:
	return posmod(t.y, WIN_T) * WIN_T + posmod(t.x, WIN_T)


## Načtená dlaždice (z komprimovaných dat, nebo nová prázdná při `create`).
func _tile(t: Vector2i, create: bool) -> Image:
	var img: Image = _tiles.get(t)
	if img != null:
		return img
	if _packed.has(t):
		var raw: PackedByteArray = (_packed[t] as PackedByteArray).decompress(TILE_PX * TILE_PX * 2, FileAccess.COMPRESSION_ZSTD)
		_packed.erase(t)
		if raw.size() == TILE_PX * TILE_PX * 2:
			img = Image.create_from_data(TILE_PX, TILE_PX, false, Image.FORMAT_RH, raw)
	if img == null:
		if not create:
			return null
		img = Image.create(TILE_PX, TILE_PX, false, Image.FORMAT_RH)
		_fade[t] = 1.0
	else:
		var f: float = _fade.get(t, 1.0)
		if f < 0.999:
			img.adjust_bcs(f, 1.0, 1.0)
			_fade[t] = 1.0
	_tiles[t] = img
	return img


# ------------------------------------------------------------------ snímek: okno shaderu, mizení, nahrání

func _process(delta: float) -> void:
	if world == null or _mat == null:
		return
	var p := _focus_player()
	if p == null:
		return
	Terramech.focus = p.car.global_position if p.car != null else p.global_position
	if not enabled():
		if _center != NONE:
			_center = NONE
			_mat.set_shader_parameter("rut_rect", Vector4.ZERO)
		return
	var c := Vector2i(floori(Terramech.focus.x / TILE_M), floori(Terramech.focus.z / TILE_M))
	if c != _center:
		_center = c
		for oz in range(-1, 2):
			for ox in range(-1, 2):
				var t := c + Vector2i(ox, oz)
				var s := _slot_of(t)
				if _slot[s] != t and not _blit_q.has(s):
					_blit_q.append(s)
		_mat.set_shader_parameter("rut_rect", Vector4((c.x - 1) * TILE_M, (c.y - 1) * TILE_M, TILE_M * WIN_T, TILE_M * WIN_T))
	if not _blit_q.is_empty():
		_blit_slot(_blit_q.pop_front())
	else:
		_fade_one()
	_upload_t -= delta
	if _dirty and _upload_t <= 0.0:
		_upload_t = UPLOAD_S
		_dirty = false
		_tex.update(_win)
	_evict_t -= delta
	if _evict_t <= 0.0:
		_evict_t = 2.0
		_evict()


func _focus_player() -> Player:
	for id in world.players:
		return world.players[id]
	return null


## Slot okna dostane dlaždici, která do něj podle středu patří (nebo nulu).
func _blit_slot(s: int) -> void:
	var sx := s % WIN_T
	var sz := s / WIN_T
	# dlaždice v okně kolem středu, která padne do slotu s
	var t := NONE
	for oz in range(-1, 2):
		for ox in range(-1, 2):
			var tt := _center + Vector2i(ox, oz)
			if _slot_of(tt) == s:
				t = tt
	_slot[s] = t
	var img: Image = _tile(t, false) if t != NONE else null
	_win.blit_rect(img if img != null else _empty, Rect2i(0, 0, TILE_PX, TILE_PX), Vector2i(sx * TILE_PX, sz * TILE_PX))
	_dirty = true


## Jedna načtená dlaždice s nahromaděným mizením → aplikovat na obraz (a do okna).
func _fade_one() -> void:
	if not _fade_scan:
		return
	for t in _tiles:
		var f: float = _fade.get(t, 1.0)
		if f >= FADE_APPLY:
			continue
		if f < FADE_DROP:
			_drop(t)
			return
		(_tiles[t] as Image).adjust_bcs(f, 1.0, 1.0)
		_fade[t] = 1.0
		var s := _slot_of(t)
		if _slot[s] == t and not _blit_q.has(s):
			_blit_q.append(s)
		return
	_fade_scan = false                     # nic nečeká – do dalšího hodinového kroku se dlaždice neprocházejí


func _drop(t: Vector2i) -> void:
	_tiles.erase(t)
	_packed.erase(t)
	_touch.erase(t)
	_fade.erase(t)
	var s := _slot_of(t)
	if _slot[s] == t and not _blit_q.has(s):
		_blit_q.append(s)


## Vzdálené dlaždice nad MAX_LOADED → komprimovat.
func _evict() -> void:
	if _tiles.size() <= MAX_LOADED:
		return
	var far := NONE
	var far_d := -1
	for t in _tiles:
		var d: int = maxi(absi(t.x - _center.x), absi(t.y - _center.y))
		if d > 1 and d > far_d:
			far_d = d
			far = t
	if far != NONE:
		_packed[far] = (_tiles[far] as Image).get_data().compress(FileAccess.COMPRESSION_ZSTD)
		_tiles.erase(far)


# ------------------------------------------------------------------ mizení (eco_hour)

func _on_eco_hour(dt_h: float) -> void:
	var wt := world.weather
	var rain := wt.rain if wt != null and wt.is_raining() else 0.0
	var sw: SoilWater = world.soil_water
	var frost := sw.frost if sw != null and sw.active() else 0.0
	var today := world.clock.jd() if world.clock != null else 0
	var gone: Array[Vector2i] = []
	_fade_scan = true
	for t in _touch:
		var cx := (float(t.x) + 0.5) * TILE_M
		var cz := (float(t.y) + 0.5) * TILE_M
		var moist := sw.moisture_at(cx, cz) if sw != null else 0.5
		var rate := FADE_DRY_H + FADE_RAIN_H * rain + FADE_WET_H * maxf(moist - Terramech.WET_FROM, 0.0) / maxf(1.0 - Terramech.WET_FROM, 0.01)
		rate *= lerpf(1.0, FADE_FROZEN, frost)
		var f: float = float(_fade.get(t, 1.0)) * exp(-dt_h * rate)
		_fade[t] = f
		if (f < FADE_DROP and not _tiles.has(t)) or today - int(_touch[t]) > FORGET_DAYS:
			gone.append(t)
	for t in gone:
		_drop(t)


# ------------------------------------------------------------------ ukládání

func to_dict() -> Dictionary:
	var rows: Array = []
	for t in _touch:
		var data: PackedByteArray
		if _tiles.has(t):
			data = (_tiles[t] as Image).get_data().compress(FileAccess.COMPRESSION_ZSTD)
		elif _packed.has(t):
			data = _packed[t]
		else:
			continue
		rows.append([int(_touch[t]), t, data])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) > int(b[0]))
	var out: Array = []
	var total := 0
	for r in rows:
		var data: PackedByteArray = r[2]
		total += data.size()
		if total > SAVE_MAX_KB * 1024:
			break
		var t: Vector2i = r[1]
		out.append({"x": t.x, "z": t.y, "jd": int(r[0]), "f": float(_fade.get(t, 1.0)),
			"d": Marshalls.raw_to_base64(data)})
	return {"v": 1, "tiles": out}


func restore(d: Dictionary) -> void:
	_tiles.clear()
	_packed.clear()
	_touch.clear()
	_fade.clear()
	for e in d.get("tiles", []):
		if not (e is Dictionary):
			continue
		var t := Vector2i(int(e.get("x", 0)), int(e.get("z", 0)))
		_packed[t] = Marshalls.base64_to_raw(String(e.get("d", "")))
		_touch[t] = int(e.get("jd", 0))
		_fade[t] = float(e.get("f", 1.0))
	_fade_scan = true
	_slot.fill(NONE)
	_center = NONE
	_blit_q.clear()


## Ladicí vrstva „unosnost“ (F2 → Příroda – ladění).
func debug_bearing(x: float, z: float) -> Color:
	return Terramech.debug_bearing(x, z)
