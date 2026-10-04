## Roční období u klienta – pole, květy a sezónní výzdoba stromů (vedle Atmosphere, která řídí trávu a listí):
## - denně (a hned po skoku v datu, F2 → Datum) přepočítá tabulku barev polí `Fields.lut_image` pro terénní shader
##   a nastaví `meadow_bloom` (květy na loukách v shaderu),
## - vede MeadowFlowers (květy kolem hráče) a TreeDecor (ovoce v korunách, padané listí).
## Vše je jen vzhled – simulaci (sezónní předměty, události) drží World.
class_name SeasonFx
extends Node

const TICK_S := 0.5

var world: World
var player: Player
var flowers: MeadowFlowers
var decor: TreeDecor
var _lut: ImageTexture
var _jd := -1
var _t := 0.0


func setup(w: World, p: Player) -> void:
	world = w
	player = p
	flowers = MeadowFlowers.new()
	flowers.name = "Kvety"
	add_child(flowers)
	flowers.setup(w)
	decor = TreeDecor.new()
	decor.name = "OvoceListi"
	add_child(decor)
	decor.setup(w)
	_t = 0.0


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0 or world == null or world.clock == null or world.terrain == null:
		return
	_t = TICK_S
	var clock: Clock = world.clock
	var doy := clock.day_of_year()
	var jd := clock.jd()
	var snow: float = world.weather.snow_cover if world.weather else 0.0
	if jd != _jd:
		_jd = jd
		_update_lut(doy, clock.year())
	world.terrain.set_meadow_bloom(Seasons.bloom(doy) * (1.0 - clampf(snow * 2.0, 0.0, 1.0)))
	var pos := player.car.global_position if player.car else player.global_position
	flowers.update(pos, doy, snow, jd)
	decor.update(pos, doy, snow, jd)


func _update_lut(doy: float, year: int) -> void:
	var f: Fields = world.fields
	if f == null or not f.loaded:
		return
	var img := f.lut_image(doy, year)
	if _lut == null:
		_lut = ImageTexture.create_from_image(img)
		world.terrain.set_field_lut(_lut)
	else:
		_lut.update(img)
