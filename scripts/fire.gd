## Ohniště a táborák (M2.2): kruh kamenů, polena, plameny, kouř a světlo. Jeden uzel = jedno ohniště.
##
## Stavy: hoří (`fuel` > 0 herních minut) → žhavé uhlíky (`ember` > 0, 20 min) → vyhaslé (kamenný kruh zůstane a jde znovu zapálit).
## Palivo: poleno +25 min, větve +8 min; déšť ubírá rychleji (`RAIN_K`). Čas nepočítá uzel – posouvá ho `FireManager`
## podle hodin světa (`advance`), takže spánek a přeskok času oheň spolehlivě dopálí.
## Teplo pro hráče: `heat_at(pos)` (0..1) – čte `FireManager` a předává do `Player.heat` → `BodyState` (sušení, zahřátí).
## Ohně mimo dosah hráče (`ACTIVE_R`) nemají částice ani světlo (jen data).
class_name Fire
extends Node3D

const WOOD_MIN := {"polena": 25.0, "vetve": 8.0}     # herní minuty hoření na 1 kus
const MAX_FUEL := 300.0                              # herní minuty (strop přikládání)
const EMBER_MIN := 20.0                              # doba žhavých uhlíků po dohoření
const RAIN_K := 2.0                                  # déšť (0..1) zrychlí hoření až na 3×
const HEAT_R_FULL := 1.5                             # m – plné teplo
const HEAT_R := 3.0                                  # m – teplo končí
const ACTIVE_R := 130.0                              # m – vizuál (částice, světlo, zvuk) jen do této vzdálenosti
const RING_R := 0.55

var world: World
var fuel := 0.0                       # herní minuty hoření
var ember := 0.0                      # herní minuty žhavých uhlíků
var owner_id := -1                    # kdo oheň rozdělal (přestupek, požár)
var illegal := false                  # rozdělaný v lese / do 50 m od okraje (zákon o lesích)
var reported := false                 # přestupek už byl uplatněn
var spread_done := false              # už jednou přeskočil na trávu
var lit_at := -1.0                    # herní minuty zapálení (statistika)
var target := {}                      # cíl registrovaný ve World (kind "fire")

var _parts := {}
var _logs: MeshInstance3D
var _ash: MeshInstance3D
var _t := 0.0
var _snd := 1.0
var _active := false
var _last_state := -1


## Vytvoří ohniště na zemi v bodě `pos` (kamenný kruh, nehoří).
static func make(w: World, pos: Vector3) -> Fire:
	var f := Fire.new()
	f.world = w
	f.name = "Ohen"
	f.position = pos
	f._t = randf() * 10.0
	w.add_child(f)
	f._build()
	f.target = {"pos": pos + Vector3(0, 0.3, 0), "r": 0.9, "kind": "fire", "node": f}
	w.register_target(f.target)
	return f


func _build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(position.x * 7.0) ^ int(position.z * 13.0)
	# kamenný kruh
	var k := MeshKit.new()
	for i in 9:
		var a := float(i) / 9.0 * TAU + rng.randf() * 0.2
		var g := 0.42 + rng.randf() * 0.16
		k.sphere(Vector3(cos(a) * RING_R, 0.07, sin(a) * RING_R), 0.12 + rng.randf() * 0.04,
			Color(g, g * 0.98, g * 0.94), Vector3(1.0, 0.7, 1.0), Vector3(0, rng.randf() * TAU, 0), 8, 5)
	MeshKit.mesh_instance(self, k.commit(MeshKit.vc_material(0.95)), 150.0)
	# popel uvnitř kruhu
	var ka := MeshKit.new()
	ka.cylinder(Vector3(0, 0.015, 0), RING_R * 0.85, RING_R * 0.85, 0.03, Color(0.12, 0.1, 0.09), Vector3.ZERO, 12)
	_ash = MeshKit.mesh_instance(self, ka.commit(MeshKit.vc_material(1.0)), 100.0)
	# polena (kolébka ze čtyř kmenů)
	var kl := MeshKit.new()
	for i in 4:
		var yaw := float(i) / 4.0 * PI + rng.randf() * 0.25
		kl.cylinder(Vector3(0, 0.11 + (i % 2) * 0.09, 0), 0.05, 0.055, 0.75, Color(0.4, 0.27, 0.15).darkened(rng.randf() * 0.3),
			Vector3(0, yaw, PI * 0.5), 6)
	_logs = MeshKit.mesh_instance(self, kl.commit(MeshKit.vc_material(0.95)), 100.0)
	_parts = FireFx.make(self, 1.0, true, 9.0)
	_refresh()


func _exit_tree() -> void:
	if world != null and not target.is_empty():
		world.unregister_target(target)


# ------------------------------------------------------------------ stav

func is_burning() -> bool:
	return fuel > 0.0


func is_hot() -> bool:
	return fuel > 0.0 or ember > 0.0


## 0 = vyhaslé, 1 = žhavé uhlíky, 2 = hoří.
func state() -> int:
	return 2 if fuel > 0.0 else (1 if ember > 0.0 else 0)


## Zapálí ohniště s počátečním palivem `minutes` (herní minuty).
func ignite(minutes: float, by: int) -> void:
	fuel = clampf(minutes, 1.0, MAX_FUEL)
	ember = 0.0
	owner_id = by
	lit_at = world.clock.minutes if world and world.clock else 0.0
	_refresh()


## Přiloží předmět (`polena` / `vetve`); vrací false, když nejde o palivo nebo je oheň plný.
func add_fuel(item: String) -> bool:
	if not WOOD_MIN.has(item) or fuel >= MAX_FUEL - 1.0:
		return false
	fuel = minf(fuel + float(WOOD_MIN[item]), MAX_FUEL)
	ember = 0.0
	if lit_at < 0.0 and world and world.clock:
		lit_at = world.clock.minutes
	_refresh()
	return true


func extinguish() -> void:
	fuel = 0.0
	ember = 0.0
	_refresh()
	if world:
		world.sound.emit(global_position, "hiss", randf_range(0.9, 1.1), 0.0, 40.0)


## Posune čas o `dm` herních minut; `rain` 0..1 = déšť dopadající na oheň (pod střechou 0).
func advance(dm: float, rain: float) -> void:
	if dm <= 0.0 or not is_hot():
		return
	var rate := 1.0 + RAIN_K * clampf(rain, 0.0, 1.0)
	if fuel > 0.0:
		fuel -= dm * rate
		if fuel <= 0.0:
			var extra := -fuel / rate
			fuel = 0.0
			ember = maxf(EMBER_MIN - extra, 0.0)
	elif ember > 0.0:
		ember = maxf(ember - dm * rate, 0.0)
	if state() != _last_state:
		_refresh()


## Teplo pro postavu na místě `p` (0..1): plné do `HEAT_R_FULL`, k nule do `HEAT_R`; uhlíky hřejí slaběji.
func heat_at(p: Vector3) -> float:
	if not is_hot() or absf(p.y - global_position.y) > 2.5:
		return 0.0
	var d := Vector2(p.x - global_position.x, p.z - global_position.z).length()
	var k := 1.0 if fuel > 0.0 else 0.4
	return k * clampf((HEAT_R - d) / (HEAT_R - HEAT_R_FULL), 0.0, 1.0)


# ------------------------------------------------------------------ vizuál

## Zapíná / vypíná vizuál podle vzdálenosti od hráče (volá manažer).
func set_active(on: bool) -> void:
	if on == _active:
		return
	_active = on
	_refresh()


func _refresh() -> void:
	_last_state = state()
	if _logs:
		_logs.visible = fuel > 4.0
	if _ash:
		_ash.visible = _last_state != 2
	var burning := _active and fuel > 0.0
	var hot := _active and is_hot()
	for key in ["flame", "sparks"]:
		var p: GPUParticles3D = _parts.get(key)
		if p:
			p.emitting = burning
	var sm: GPUParticles3D = _parts.get("smoke")
	if sm:
		sm.emitting = hot
	var l: OmniLight3D = _parts.get("light")
	if l:
		l.visible = hot
	set_process(_active)


func _process(delta: float) -> void:
	if not _active:
		return
	_t += delta
	var big := clampf(0.3 + fuel / 70.0, 0.3, 1.0)
	for key in ["flame", "sparks"]:
		var p: GPUParticles3D = _parts.get(key)
		if p and fuel > 0.0:
			p.amount_ratio = big
	var l: OmniLight3D = _parts.get("light")
	if l:
		if fuel > 0.0:
			l.light_energy = FireFx.flicker(_t, 1.6 * big)
			l.light_color = Color(1.0, 0.55, 0.22)
		elif ember > 0.0:
			l.light_energy = 0.35 + 0.1 * sin(_t * 3.0)
			l.light_color = Color(1.0, 0.25, 0.08)
	if fuel > 0.0 and world != null:
		_snd -= delta
		if _snd <= 0.0:
			_snd = randf_range(0.35, 1.5)
			world.sound.emit(global_position, "crackle", randf_range(0.7, 1.3), -8.0, 24.0)


# ------------------------------------------------------------------ ukládání

func to_dict() -> Dictionary:
	return {"pos": [snappedf(position.x, 0.01), snappedf(position.y, 0.01), snappedf(position.z, 0.01)],
		"fuel": snappedf(fuel, 0.1), "ember": snappedf(ember, 0.1), "owner": owner_id, "illegal": illegal,
		"reported": reported, "spread": spread_done}


func from_dict(d: Dictionary) -> void:
	fuel = float(d.get("fuel", 0.0))
	ember = float(d.get("ember", 0.0))
	owner_id = int(d.get("owner", -1))
	illegal = bool(d.get("illegal", false))
	reported = bool(d.get("reported", false))
	spread_done = bool(d.get("spread", false))
	_refresh()
