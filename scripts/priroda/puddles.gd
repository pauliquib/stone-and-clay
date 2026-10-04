## Louže na vozovkách po dešti (Fáze 9, plán §12.3): malá sada `Decal` uzlů rozmístěná
## na silnicích/cestách (uzly `RoadGraph` pro auta) v okolí hráče. Objevují se při
## `Weather.wetness > WET_MIN` a plynule mizí, jak povrch schne (`modulate.a`).
## Jen vzhled (klient, SeasonFx) – přilnavost mokré vozovky řeší `Weather.surface_grip`.
## Headless-safe: bez rendereru se uzly jen vytvoří a schovají.
class_name Puddles
extends Node3D

const WET_MIN := 0.7          # od této vlhkosti se louže objevují
const WET_FULL := 0.9         # plný kryt alphy
const COUNT := 9              # kolik louží se drží kolem hráče
const RADIUS := 110.0         # dosah hledání uzlů vozovky (m)
const SPACING := 14.0         # min. rozestup dvou louží (m)
const RESP_DIST := 30.0       # posun hráče, při kterém se louže přerozdělí
const FADE_STEP := 0.25       # nárust alphy za tick SeasonFx (~0,5 s) → fade ~2 s
const TEX_S := 64

var world: World
var alpha := 0.0              # aktuální viditelnost louží 0..1 (čte i test)
var _pool: Array[Decal] = []
var _rng := RandomNumberGenerator.new()
var _anchor := Vector3(1e9, 0, 1e9)   # kam byly louže naposledy rozseté
var _alb: ImageTexture
var _orm: ImageTexture


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


## Rozhodí louže na náhodné uzly vozovky (RoadGraph.CAR_KINDS) v okolí hráče;
## orientuje je podél směru silnice, výška těsně nad vozovku (silnice se "drapuje" +0,1 m).
func _scatter(pos: Vector3) -> void:
	_anchor = pos
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
		var d: Decal = _pool[placed]
		placed += 1
		d.position = Vector3(p.x, world.terrain.height_at(p.x, p.y) + 0.14, p.y)
		d.rotation = Vector3(0, atan2(dir.x, dir.y) + _rng.randf_range(-0.2, 0.2), 0)
		d.size = Vector3(_rng.randf_range(1.0, 1.9), 1.6, _rng.randf_range(2.0, 3.6))
	for k in range(placed, _pool.size()):
		_pool[k].visible = false            # méně uzlů než louží – zbytek schovat


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
