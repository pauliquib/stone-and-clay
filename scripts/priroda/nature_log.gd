## Deník pozorování přírody (klávesa J): první setkání hráče s každým druhem se zapíše s herním datem.
##
## Druhy: zajíc, srnec, divočák (sele se počítá jako divočák), vrána, kos, vlaštovka, káně, včely, mravenci.
## Pozorování = druh je do VIEW_R m a v zorném kuželu ±VIEW_HALF° (směr pohledu `Player.yaw`, na koni směr koně),
## nebo v dalekohledu (X) do SCOPE_R m v úzkém kuželu; mezi hráčem a zvířetem nesmí být překážka (paprsek).
## Včely se počítají u včelnice do BEES_R m, když právě létají; mravenci u mraveniště do ANTS_R m.
## Z auta se nepozoruje. Kontrola běží 1× za TICK s. Uložení: `get_log` / `set_log` (SaveGame, klíč „nature_log“,
## chybějící klíč = prázdný deník).
class_name NatureLog
extends Node

## [klíč druhu, název pro deník]
const SPECIES := [
	["zajic", "Zajíc polní"], ["srnec", "Srnec obecný"], ["divocak", "Prase divoké"], ["vrana", "Vrána"],
	["kos", "Kos černý"], ["vlastovka", "Vlaštovka obecná"], ["kane", "Káně lesní"], ["vcely", "Včela medonosná"],
	["mravenci", "Mravenec lesní"],
]
const VIEW_R := 60.0
const VIEW_HALF := 35.0
const SCOPE_R := 250.0
const SCOPE_HALF := 7.0
const BEES_R := 15.0
const ANTS_R := 5.0
const TICK := 0.5

var world: World
var logs := {}                    # id hráče → {klíč druhu: datum prvního pozorování}
var _t := 0.0


func setup(w: World) -> void:
	world = w


func get_log(id: int) -> Dictionary:
	var l: Dictionary = logs.get(id, {})
	return l.duplicate()


func set_log(id: int, data) -> void:
	logs[id] = (data as Dictionary).duplicate() if data is Dictionary else {}


func count(id: int) -> int:
	var l: Dictionary = logs.get(id, {})
	return l.size()


func name_of(key: String) -> String:
	for e in SPECIES:
		if e[0] == key:
			return e[1]
	return key


## Oddíl deníku J (BBCode).
func journal_text(id: int) -> String:
	var l: Dictionary = logs.get(id, {})
	var s := "\n[b]POZOROVÁNÍ PŘÍRODY[/b]   (%d/%d)\n" % [l.size(), SPECIES.size()]
	for e in SPECIES:
		if l.has(e[0]):
			s += "  [color=#9f9]✔[/color] %s – poprvé %s\n" % [e[1], l[e[0]]]
		else:
			s += "  [color=#888]○ ??? – zatím nespatřeno[/color]\n"
	return s + "\n"


func _process(delta: float) -> void:
	if world == null or world.fauna == null:
		return
	_t += delta
	if _t < TICK:
		return
	_t = 0.0
	for p in world.players.values():
		_check(p)


func _seen(eye: Vector3, fwd: Vector3, pt: Vector3, scoped: bool) -> bool:
	var to := pt - eye
	var d := to.length()
	if d > (SCOPE_R if scoped else VIEW_R):
		return false
	if d > 0.5 and fwd.dot(to / d) < cos(deg_to_rad(SCOPE_HALF if scoped else VIEW_HALF)):
		return false
	return world.line_clear(eye, pt)


func _check(p: Player) -> void:
	if p.car != null or p.fallen > 0.0:
		return
	var l: Dictionary = logs.get(p.id, {})
	if l.size() >= SPECIES.size():
		return
	var scoped := p.scope > 0.6 and p.camera != null
	var eye: Vector3 = p.camera.global_position if scoped else p.global_position + Vector3(0, 1.5, 0)
	var fwd := Vector3(-sin(p.yaw), 0.0, -cos(p.yaw))
	if scoped:
		fwd = -p.camera.global_transform.basis.z
	var fa: Fauna = world.fauna
	# --- zvěř
	for a in fa.animals:
		if not is_instance_valid(a) or a.dead:
			continue
		var key: String = "divocak" if a.species == "sele" else String(a.species)
		if l.has(key) or a.global_position.distance_to(p.global_position) > (SCOPE_R if scoped else VIEW_R):
			continue
		if _seen(eye, fwd, a.global_position + Vector3(0, 0.7, 0), scoped):
			observe(p, key)
	# --- ptáci
	for flock in fa.root_birds.get_children():
		if not (flock is BirdFlock):
			continue
		var bkey := String((flock as BirdFlock).species)
		if l.has(bkey) or bkey == "":
			continue
		for b in (flock as BirdFlock).birds:
			if is_instance_valid(b) and _seen(eye, fwd, (b as Node3D).global_position, scoped):
				observe(p, bkey)
				break
	# --- hmyz
	for n in fa.root_insects.get_children():
		if n is Apiary and not l.has("vcely"):
			var ap := n as Apiary
			for h in ap.hives:
				if h.distance_to(p.global_position) < BEES_R and ap._activity() > 0.05:
					observe(p, "vcely")
					break
		elif n is AntHill and not l.has("mravenci"):
			if (n as AntHill).global_position.distance_to(p.global_position) < ANTS_R:
				observe(p, "mravenci")


## První pozorování druhu: zapíše se datum, hráč dostane zprávu.
func observe(p: Player, key: String) -> void:
	var l: Dictionary = logs.get(p.id, {})
	if l.has(key):
		return
	l[key] = world.clock.date_text()
	logs[p.id] = l
	world.notify(p.id, "show_message", ["Nové pozorování: %s  (%d/%d)  – zapsáno do deníku [J]" % [name_of(key), l.size(), SPECIES.size()], 4.0])
	world.emit_game_event(p.id, "sfx", {"name": "pickup"})
	world.emit_game_event(p.id, "nature_seen", {"species": key})
