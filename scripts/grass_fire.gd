## Požár trávy (M2.2): rozšiřující se kruh ohně po louce / v lese. Vznikne, když nehlídaný oheň v suchu přeskočí na trávu
## (`FireManager`). Roste do `MAX_R`, hoří `BURN_MIN` herních minut, pak dohoří. Hráč ho může hasit (akce `hasit`,
## cíl `grassfire`: lopatou v ruce nebo vodou z kapsy) – každé hašení zmenší poloměr a když zbude málo, oheň zhasne.
## Kdo stojí uvnitř kruhu, hoří (`BURN_DPS`). Hasiči (M5.3) se napojí na herní událost `fire_report`.
## Neukládá se (přechodný jev).
class_name GrassFire
extends Node3D

const MAX_R := 30.0                # m – největší poloměr
const BURN_MIN := 20.0             # herní minuty od vzniku do dohoření (DOPLNIT: 1 herní min = 2 s, laditelné)
const GROW_MIN := 8.0              # herní minuty, za které oheň dorostne do plné velikosti
const START_R := 1.5
const SUPPRESS_K := 0.55           # jedno hašení zmenší poloměr na tolik
const OUT_R := 1.8                 # pod tímto poloměrem oheň zhasne
const BURN_DPS := 4.0              # zranění za sekundu uvnitř kruhu
const MAX_EMITTERS := 14
const ACTIVE_R := 260.0

var world: World
var radius := START_R
var peak_r := START_R
var age := 0.0                     # herní minuty
var owner_id := -1
var suppressed := false            # hráč ho hasil
var finished := false
var target := {}

var _emitters: Array = []          # GPUParticles3D
var _light: OmniLight3D
var _t := 0.0
var _snd := 0.5
var _scale := 1.0                  # poloměr, na který jsou rozmístěné emitory


static func make(w: World, pos: Vector3, by: int) -> GrassFire:
	var g := GrassFire.new()
	g.world = w
	g.name = "PozarTravy"
	g.position = pos
	g.owner_id = by
	w.add_child(g)
	g._build()
	g.target = {"pos": pos + Vector3(0, 0.4, 0), "r": g.radius, "kind": "grassfire", "node": g}
	w.register_target(g.target)
	return g


func _build() -> void:
	_light = OmniLight3D.new()
	_light.position = Vector3(0, 1.5, 0)
	_light.light_color = Color(1.0, 0.5, 0.18)
	_light.light_energy = 0.0
	_light.omni_range = 14.0
	_light.shadow_enabled = false
	_light.distance_fade_enabled = true
	_light.distance_fade_begin = 200.0
	add_child(_light)
	_sync_emitters()


func _exit_tree() -> void:
	if world != null and not target.is_empty():
		world.unregister_target(target)


func _ground(x: float, z: float) -> float:
	return world.terrain.height_at(x, z) if world and world.terrain else position.y


## Rozmístí plameny po kruhu (víc emitorů s růstem poloměru), výška podle terénu.
func _sync_emitters() -> void:
	var want := clampi(int(radius * 0.7) + 2, 2, MAX_EMITTERS)
	while _emitters.size() < want:
		var holder := Node3D.new()
		add_child(holder)
		var fx := FireFx.make(holder, 2.2, true, 0.0)      # bez vlastního světla (jedno společné níže)
		holder.set_meta("fx", fx)
		_emitters.append(holder)
	for i in _emitters.size():
		var h: Node3D = _emitters[i]
		var a := float(i) * 2.399963            # zlatý úhel – rovnoměrné pokrytí
		var rr := radius * sqrt((float(i) + 0.5) / float(_emitters.size())) * 0.9
		var wx := global_position.x + cos(a) * rr
		var wz := global_position.z + sin(a) * rr
		h.global_position = Vector3(wx, _ground(wx, wz), wz)
		var fx: Dictionary = h.get_meta("fx")
		for key in ["flame", "sparks", "smoke"]:
			var p: GPUParticles3D = fx.get(key)
			if p:
				p.emitting = not finished
	if target.has("r"):
		target["r"] = radius
	_light.omni_range = clampf(radius * 1.6 + 8.0, 10.0, 60.0)


## Posune čas o `dm` herních minut. Vrací true, když oheň dohořel.
func advance(dm: float) -> bool:
	if finished:
		return true
	age += dm
	var k := clampf(age / GROW_MIN, 0.0, 1.0)
	var full := MAX_R * (0.5 + 0.5 * k)              # plná velikost roste s věkem
	if not suppressed:
		radius = maxf(radius, lerpf(START_R, full, k))
	peak_r = maxf(peak_r, radius)
	if age >= BURN_MIN or radius < OUT_R:
		finish()
		return true
	if absf(radius - _scale) > 1.0:
		_scale = radius
		_sync_emitters()
	return false


## Hráč hasí: poloměr se zmenší; když zbude málo, oheň zhasne.
func suppress() -> void:
	suppressed = true
	radius *= SUPPRESS_K
	target["r"] = radius
	if radius < OUT_R:
		finish()
	else:
		_sync_emitters()


func finish() -> void:
	if finished:
		return
	finished = true
	for h in _emitters:
		var fx: Dictionary = h.get_meta("fx")
		for key in ["flame", "sparks", "smoke"]:
			var p: GPUParticles3D = fx.get(key)
			if p:
				p.emitting = false
	_light.light_energy = 0.0
	if world:
		world.unregister_target(target)
		target = {}
	get_tree().create_timer(6.0).timeout.connect(queue_free)


func in_fire(p: Vector3) -> bool:
	return not finished and Vector2(p.x - global_position.x, p.z - global_position.z).length() < radius


func _process(delta: float) -> void:
	if finished or world == null:
		return
	_t += delta
	var pl := world.nearest_player(global_position)
	var near := pl != null and pl.global_position.distance_to(global_position) < ACTIVE_R
	_light.visible = near
	if near:
		_light.light_energy = FireFx.flicker(_t, 2.5 + radius * 0.12)
		_snd -= delta
		if _snd <= 0.0:
			_snd = randf_range(0.15, 0.6)
			world.sound.emit(global_position, "crackle", randf_range(0.6, 1.1), -4.0, radius + 45.0)
	# popálení
	for id in world.players:
		var p: Player = world.players[id]
		if p.car == null and p.inside == "" and in_fire(p.global_position):
			p.body.hurt(BURN_DPS * delta, "popálení v požáru")
			if int(id) in world.clients and randf() < delta * 1.2:
				world.notify(int(id), "show_message", ["Hoříš! Uteč z ohně!", 1.5])
