## Louže na vozovkách po dešti (Fáze 9, plán §12.3): malá sada `Decal` uzlů rozmístěná
## na silnicích/cestách (uzly `RoadGraph` pro auta) v okolí hráče. Objevují se při
## `Weather.wetness > WET_MIN` a plynule mizí, jak povrch schne (`modulate.a`).
## Jen vzhled (klient, SeasonFx) – přilnavost mokré vozovky řeší `Weather.surface_grip`.
## M8.7: s vodní bilancí (`World.soil_water` aktivní) jen tam, kde je mokro lokálně: nasycená půda v prohlubni
## (TWI) nebo stékající voda (`SoilWater.puddle_at`), za deště hlavně v prohlubních; každá louže má vlastní
## viditelnost a vysychá postupně s půdou. Bez bilance = dřívější globální chování podle `wetness`.
## Headless-safe: bez rendereru se uzly jen vytvoří a schovají.
class_name Puddles
extends Node3D

## M8.D2c: chování = `static var` (F3 → Příroda/Louže, stopy), výchozí beze změny.
static var WET_MIN := 0.7     # od této vlhkosti se louže objevují
static var WET_FULL := 0.9    # plný kryt alphy
const COUNT := 9              # kolik louží se drží kolem hráče
static var RADIUS := 110.0    # dosah hledání uzlů vozovky (m)
static var SPACING := 14.0    # min. rozestup dvou louží (m)
static var RESP_DIST := 30.0  # posun hráče, při kterém se louže přerozdělí
static var FADE_STEP := 0.25  # nárust alphy za tick SeasonFx (~0,5 s) → fade ~2 s
const TEX_S := 64
static var LOCAL_MIN := 0.08  # M8.7: méně lokální vláhy = louže se tu nerozhodí
static var LOCAL_FADE := 0.04 # M8.7: posun alphy za tick (vysychání ~12 s, objevení ~6 s)
static var RAIN_FLAT := 0.3   # za deště: louže mimo prohlubně (× mokro z deště); v prohlubni 1

var world: World
var alpha := 0.0              # aktuální viditelnost louží 0..1 (čte i test)
var _pool: Array[Decal] = []
var _rng := RandomNumberGenerator.new()
var _anchor := Vector3(1e9, 0, 1e9)   # kam byly louže naposledy rozseté
var _alb: ImageTexture
var _orm: ImageTexture
var _sw: SoilWater = null     # M8.7: aktivní vodní bilance pro tento tick (null = globální chování)
var _rain_wet := 0.0          # M8.7: mokro z právě padajícího deště 0..1
var _alphas := PackedFloat32Array()
var _placed := 0              # M8.7: kolik louží z poolu je rozhozených
var _since_scatter := 0       # M8.7: ticků od posledního rozhození (doplnění, když hráč stojí)
static var RESCATTER_TICKS := 20   # M8.7: ~10 s – zkusit doplnit louže na místě (když jich je málo)


func setup(w: World) -> void:
	world = w
	_rng.seed = 1211
	_make_textures()
	for i in COUNT:
		var d := Decal.new()
		d.name = "Louze%d" % i
		d.texture_albedo = _alb
		d.texture_orm = _orm
		d.size = Vector3(1.4, 1.6, 2.4)
		d.upper_fade = 0.4
		d.lower_fade = 0.4
		d.visible = false
		d.modulate = Color(1, 1, 1, 0)
		add_child(d)
		_pool.append(d)


## Volá SeasonFx (~2× za sekundu): `pos` = poloha hráče/auta, `wetness` = Weather.wetness 0..1.
func update(pos: Vector3, wetness: float) -> void:
	var want := clampf((wetness - WET_MIN) / (WET_FULL - WET_MIN), 0.0, 1.0)
	var sw: SoilWater = world.soil_water if world != null else null
	_sw = sw if sw != null and sw.active() else null
	if _sw != null:
		_update_local(pos, want)
		return
	alpha = move_toward(alpha, want, FADE_STEP)
	if alpha <= 0.0:
		for d in _pool:
			if d.visible:
				d.visible = false
		return
	if pos.distance_to(_anchor) > RESP_DIST or not _pool[0].visible:
		_scatter(pos)
	for d in _pool:
		d.visible = true
		d.modulate.a = alpha


## M8.7: louže podle lokální vláhy – každá svou alphou, rozhodí se jen na mokrá místa.
func _update_local(pos: Vector3, rain_wet: float) -> void:
	_rain_wet = rain_wet
	if _alphas.size() != _pool.size():
		_alphas.resize(_pool.size())
	_since_scatter += 1
	if pos.distance_to(_anchor) > RESP_DIST or (_placed < COUNT / 2 and _since_scatter >= RESCATTER_TICKS):
		_scatter(pos)
	alpha = 0.0
	for k in _pool.size():
		var d := _pool[k]
		var tgt := _local_wet(d.position.x, d.position.z) if k < _placed else 0.0
		_alphas[k] = move_toward(_alphas[k], clampf(tgt, 0.0, 1.0), LOCAL_FADE)
		d.modulate.a = _alphas[k]
		d.visible = _alphas[k] > 0.01
		alpha = maxf(alpha, _alphas[k])


## M8.7: lokální vláha pro louži 0..1 (nasycená prohlubeň / stékající voda, za deště hlavně v prohlubních).
func _local_wet(x: float, z: float) -> float:
	if _sw == null:
		return 0.0
	return maxf(_sw.puddle_at(x, z), _rain_wet * (RAIN_FLAT + (1.0 - RAIN_FLAT) * _sw.hollow_at(x, z)))


## Rozhodí louže na náhodné uzly vozovky (RoadGraph.CAR_KINDS) v okolí hráče;
## orientuje je podél směru silnice, výška těsně nad vozovku (silnice se "drapuje" +0,1 m).
func _scatter(pos: Vector3) -> void:
	_anchor = pos
	_since_scatter = 0
	var cand: Array = []
	if world != null and world.graph != null:
		cand = world.graph.nodes_within(Vector2(pos.x, pos.z), RADIUS, RoadGraph.CAR_KINDS)
	cand.shuffle()
	var used: Array[Vector2] = []
	var placed := 0
	for i in cand:
		if placed >= _pool.size():
			break
		var n2: Vector2 = world.graph.nodes[i]
		var ok := true
		for u in used:
			if u.distance_to(n2) < SPACING:
				ok = false
				break
		if not ok:
			continue
		used.append(n2)
		var nb: Array = world.graph.adj[i]
		var dir := Vector2(0, 1) if nb.is_empty() else (world.graph.nodes[nb[0]] - n2).normalized()
		var side := Vector2(-dir.y, dir.x)
		var p := n2 + side * _rng.randf_range(-0.9, 0.9) + dir * _rng.randf_range(-2.0, 2.0)
		if world.terrain == null or not world.terrain.contains(p.x, p.y, 5.0):
			continue
		if _sw != null and _local_wet(p.x, p.y) < LOCAL_MIN:
			continue                         # M8.7: tady je sucho – louže jen na lokálně mokrých místech
		var d: Decal = _pool[placed]
		if _sw != null and _alphas.size() > placed:
			_alphas[placed] = 0.0            # nová louže naroste plynule
		placed += 1
		d.position = Vector3(p.x, world.terrain.height_at(p.x, p.y) + 0.14, p.y)
		d.rotation = Vector3(0, atan2(dir.x, dir.y) + _rng.randf_range(-0.2, 0.2), 0)
		d.size = Vector3(_rng.randf_range(1.0, 1.9), 1.6, _rng.randf_range(2.0, 3.6))
	_placed = placed
	for k in range(placed, _pool.size()):
		_pool[k].visible = false            # méně uzlů než louží – zbytek schovat
		if _alphas.size() > k:
			_alphas[k] = 0.0


## Textury louže: albedo – tmavá nepravidelná skvrna s měkkým okrajem (šum),
## ORM – uprostřed nízká roughness a vysoký metal (odraz oblohy), ke kraji běžný povrch.
func _make_textures() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 1211
	noise.frequency = 0.14
	var alb := Image.create(TEX_S, TEX_S, false, Image.FORMAT_RGBA8)
	var orm := Image.create(TEX_S, TEX_S, false, Image.FORMAT_RGB8)
	for y in TEX_S:
		for x in TEX_S:
			var p := Vector2(float(x), float(y)) / TEX_S * 2.0 - Vector2.ONE
			var edge := 0.62 + noise.get_noise_2d(float(x), float(y)) * 0.30
			var a := smoothstep(0.0, 1.0, clampf((edge - p.length()) / 0.28, 0.0, 1.0))
			alb.set_pixel(x, y, Color(0.04, 0.05, 0.06, a * 0.8))
			var t := clampf(p.length() / maxf(edge, 0.05), 0.0, 1.0)
			orm.set_pixel(x, y, Color(1.0, lerpf(0.05, 1.0, t * t), lerpf(0.9, 0.0, t)))
	_alb = ImageTexture.create_from_image(alb)
	_orm = ImageTexture.create_from_image(orm)


## Pro testy: kolik louží je právě viditelných.
func visible_count() -> int:
	var n := 0
	for d in _pool:
		if d.visible:
			n += 1
	return n
