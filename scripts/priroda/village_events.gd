## Svátky a události v obci podle kalendáře (Clock): vánoční výzdoba, masopustní průvod, pálení čarodějnic,
## hody (posvícení) a Silvestr s ohňostrojem. Vytváří ho World (`village_events`), běží na straně světa.
##
## - `EVENTS` – tabulka událostí (název, hodiny, úprava otevírací doby míst) – laditelné hodnoty
## - datum každé události určuje `_active_at`; kontrola se opakuje každých `CHECK_S` s reálného času a hned po skoku
##   v datu (`refresh`, F2 → Datum)
## - dekorace a postavy vznikají jen když je událost aktivní a hráč je do `NEAR_R` m; jinak se zruší
## - M5.5: pravidelná taneční zábava (1. a 3. sobota, 20–3 h, hospoda pod širým nebem): pódium, kapela (4 postavy),
##   generovaná hudba (`RadioMusic`, střídá hraní a pauzy), tančící návštěvníci; nástěnka u úřadu (`_build_nastenka`)
## - API: `active()`, `is_active(id)`, `event_hours(klíč_místa, jd)` (Place.is_open), `names_text()` (HUD),
##   `upcoming(dny)` ([[jd, text]] pro plakát a web obce), `register(id, pravidlo, text)` (další akce kalendáře)
## Úkoly k událostem zatím nejsou (viz PROJECT_LOG – otevřené body).
class_name VillageEvents
extends Node3D

const CHECK_S := 5.0
const NEAR_R := 600.0
## Posvícení: n-tá neděle v měsíci (weekday 6 = neděle) a sobota před ní
const HODY_WEEKEND := {"month": 10, "nth": 3, "weekday": 6}
## Hranice čarodějnic: střed fotbalového hřiště u hospody (OSM leisure=pitch, souřadnice scény)
const BONFIRE_POS := Vector2(440.6, 198.6)
const BONFIRE_LIT_HOUR := 20.0
const BONFIRE_CROWD := 10
const MASOPUST_N := 9
const MASOPUST_SPEED := 1.1           # m/s
const MASOPUST_SPACING := 1.9         # m mezi maskami
const MASOPUST_OFFSET := 2.6          # m od osy silnice (auta jezdí blíž ose)
const FIREWORK_POOL := 6
const FIREWORK_COLORS := [Color(1.0, 0.25, 0.2), Color(1.0, 0.8, 0.2), Color(0.3, 0.6, 1.0), Color(0.4, 1.0, 0.45),
	Color(1.0, 0.45, 0.9), Color(1.0, 1.0, 1.0)]
const XMAS_COLORS := [Color(1.0, 0.2, 0.15), Color(1.0, 0.85, 0.3), Color(0.3, 0.6, 1.0), Color(0.4, 1.0, 0.4),
	Color(1.0, 0.95, 0.85)]
const MASKS := ["medved", "kobyla", "slameny", "kominik", "klaun"]   # neutrální masopustní masky
## Taneční zábava (M5.5): 1. a 3. sobota v měsíci, jen v uvedených měsících; hraje smyšlená kapela (podle dne)
const ZABAVA_WEEKDAY := 5                   # sobota (jd % 7; 0 = pondělí)
const ZABAVA_NTH := [1, 3]
const ZABAVA_MONTHS := [1, 2, 3, 4, 5, 9, 10, 11]
const ZABAVA_BANDS := ["Traktor Blues", "Zlatá Kovadlina", "Vesnický Expres", "Kulatá Šestka"]
const ZABAVA_VISITORS := 14
const ZABAVA_PLAY_S := 40.0                 # reálné sekundy hraní (~20 herních minut)
const ZABAVA_PAUSE_S := 20.0                # reálné sekundy pauzy mezi sety (~10 herních minut)
const ZABAVA_LIGHTS := [Color(1.0, 0.25, 0.3), Color(0.3, 0.6, 1.0), Color(1.0, 0.85, 0.3), Color(0.5, 1.0, 0.4)]
const NASTENKA_POS_DIST := [5.0, 7.0, 9.0]

## Události. hours = [od, do] hodin dne události (u silvestra řeší okno `_active_at`);
## place_hours = úprava otevírací doby míst v „dnech události“ (viz `_place_day`), 26 = 2:00.
const EVENTS := {
	"vanoce": {"name": "Vánoční čas", "hours": [0.0, 24.0], "place": "urad",
		"place_hours": {"hospoda": [10, 14], "obchod": [6, 12]}},     # Štědrý den
	"masopust": {"name": "Masopust", "hours": [10.0, 15.0], "place": "urad", "place_hours": {}},
	"carodejnice": {"name": "Pálení čarodějnic", "hours": [18.0, 24.0], "place": "", "place_hours": {}},
	"hody": {"name": "Hody", "hours": [0.0, 24.0], "place": "hospoda", "place_hours": {"hospoda": [10, 28]}},
	"silvestr": {"name": "Silvestr", "hours": [23.667, 24.667], "place": "urad", "place_hours": {"hospoda": [10, 27]}},
	"zabava": {"name": "Taneční zábava", "hours": [20.0, 27.0], "place": "hospoda", "place_hours": {"hospoda": [10, 27]}},
}

var world: World
var clock: Clock
var _t := 0.0
var _active: Array[String] = []
var _nodes := {}                      # id události → kořen dekorací
# vánoce
var _xmas_mat: StandardMaterial3D
var _xmas_lights: Array[OmniLight3D] = []
# masopust
var _path := PackedVector2Array()
var _walkers: Array = []
var _walk_d := 0.0
# čarodějnice
var _fire_parts: Array[GPUParticles3D] = []
var _fire_light: OmniLight3D
var _fire_seed := 0.0
# ohňostroj
var _fw_pool: Array[GPUParticles3D] = []
var _fw_light: OmniLight3D
var _fw_t := 1.0
var _fw_flash := 0.0
var _fw_center := Vector3.ZERO
# taneční zábava (M5.5)
var _zab_player: AudioStreamPlayer3D
var _zab_lights: Array[OmniLight3D] = []
var _zab_dancers: Array = []          # [Humanoid, fáze, základní natočení]
var _zab_band: Array[Humanoid] = []
var _zab_t := 0.0
var _zab_on := true                   # hraje (true) / pauza (false)
var _zab_clock := ZABAVA_PLAY_S
var _zab_name := ""
var _music_cache := {}                # "metal" → AudioStreamWAV
var _music_task := -1
var _music_res: AudioStreamWAV
# nástěnka a registrované akce kalendáře
var _board_label: Label3D
var _registered := {}                 # id → {"rule": Callable(jd) -> bool, "text": String}


func setup(w: World) -> void:
	world = w
	clock = w.clock
	refresh()
	_build_nastenka()


# ------------------------------------------------------------------ kalendář

## Ohňostroj a hody na posvícení: neděle „hodů“ v roce y (juliánské číslo dne).
static func hody_sunday(y: int) -> int:
	var mo: int = HODY_WEEKEND["month"]
	var wd: int = HODY_WEEKEND["weekday"]
	var nth: int = HODY_WEEKEND["nth"]
	var first := Clock.jdn(y, mo, 1)
	return first + posmod(wd - first % 7, 7) + 7 * (nth - 1)


## Je událost aktivní v daném dni a hodině?
func _active_at(id: String, jd: int, hour: float) -> bool:
	var d := Clock.from_jdn(jd)
	var y: int = d["year"]
	var m: int = d["month"]
	var day: int = d["day"]
	var hrs: Array = EVENTS[id]["hours"]
	match id:
		"vanoce":
			return m == 12 or (m == 1 and day <= 6)
		"masopust":
			return jd == Clock.easter_jdn(y) - 50 and hour >= hrs[0] and hour < hrs[1]
		"carodejnice":
			return m == 4 and day == 30 and hour >= hrs[0] and hour < hrs[1]
		"hody":
			var s := hody_sunday(y)
			return jd == s or jd == s - 1
		"silvestr":
			return (m == 12 and day == 31 and hour >= hrs[0]) or (m == 1 and day == 1 and hour < hrs[1] - 24.0)
		"zabava":
			return (zabava_day(jd) and hour >= hrs[0]) or (zabava_day(jd - 1) and hour < hrs[1] - 24.0)
	return false


## Taneční zábava (M5.5): 1. nebo 3. sobota v povoleném měsíci; v den hodů se nekoná (má vlastní zábavu).
static func zabava_day(jd: int) -> bool:
	if jd % 7 != ZABAVA_WEEKDAY:
		return false
	var d := Clock.from_jdn(jd)
	if not (int(d["month"]) in ZABAVA_MONTHS):
		return false
	var nth := (int(d["day"]) - 1) / 7 + 1
	if not (nth in ZABAVA_NTH):
		return false
	return jd != hody_sunday(int(d["year"])) - 1


## Jméno kapely na daný den (stejná kapela se opakuje podle data, ne náhodně).
static func band_for(jd: int) -> String:
	return ZABAVA_BANDS[posmod(jd / 7, ZABAVA_BANDS.size())]


## Registrace další akce kalendáře (plakát, web obce): `rule` = Callable(jd) -> bool, `text` = popis.
func register(id: String, rule: Callable, text: String) -> void:
	_registered[id] = {"rule": rule, "text": text}


## Nadcházející akce obce: [[jd, text]] na `days` dní od dneška (pro nástěnku a web obce).
func upcoming(days: int) -> Array:
	var out := []
	if clock == null:
		return out
	var jd0 := clock.jd()
	for j in range(jd0, jd0 + days + 1):
		if zabava_day(j):
			out.append([j, "Taneční zábava – hraje %s · 20 h · hospoda" % band_for(j)])
		for id in _registered:
			var r: Dictionary = _registered[id]
			if (r["rule"] as Callable).call(j):
				out.append([j, String(r["text"])])
	return out


## Platí úprava otevírací doby míst (`place_hours`) v tento den?
func _place_day(id: String, jd: int) -> bool:
	var d := Clock.from_jdn(jd)
	var m: int = d["month"]
	var day: int = d["day"]
	match id:
		"vanoce":
			return m == 12 and day == 24
		"hody":
			var s := hody_sunday(int(d["year"]))
			return jd == s or jd == s - 1
		"silvestr":
			return m == 12 and day == 31
		"zabava":
			return zabava_day(jd)
	return false


## Upravená otevírací doba místa v den `jd` ([od, do]; do > 24 = po půlnoci; prázdné = beze změny).
func event_hours(place_key: String, jd := -1) -> Array:
	if clock == null:
		return []
	var j: int = jd if jd >= 0 else clock.jd()
	for id in EVENTS:
		var ph: Dictionary = EVENTS[id]["place_hours"]
		if ph.has(place_key) and _place_day(id, j):
			return ph[place_key]
	return []


func active() -> Array[String]:
	return _active


func is_active(id: String) -> bool:
	return id in _active


## Text do HUD: státní svátek a probíhající události.
func names_text() -> String:
	var parts: Array[String] = []
	if clock:
		var h := clock.holiday()
		if h != "":
			parts.append(h)
	for id in _active:
		parts.append(String(EVENTS[id]["name"]))
	return " · ".join(parts)


# ------------------------------------------------------------------ smyčka

func _process(delta: float) -> void:
	if world == null or clock == null:
		return
	_t += delta
	if _t >= CHECK_S:
		_t = 0.0
		refresh()
	if _nodes.is_empty():
		return
	var night := 1.0 - clock.daylight()
	if _nodes.has("vanoce"):
		_xmas_mat.emission_energy_multiplier = lerpf(0.5, 3.2, night)
		for l in _xmas_lights:
			l.light_energy = night * 1.6
	if _nodes.has("masopust"):
		_update_procession(delta)
	if _nodes.has("carodejnice"):
		_update_bonfire(delta)
	if _nodes.has("silvestr"):
		_update_fireworks(delta)
	if _nodes.has("zabava"):
		_update_zabava(delta)


## Znovu vyhodnotí, které události běží, a postaví / zruší jejich dekorace.
func refresh() -> void:
	if world == null or clock == null:
		return
	var jd := clock.jd()
	var hour := clock.hour()
	_active.clear()
	for id in EVENTS:
		if _active_at(id, jd, hour):
			_active.append(id)
	for id in EVENTS:
		var want: bool = id in _active and _near(id)
		if want and not _nodes.has(id):
			_build(id)
		elif not want and _nodes.has(id):
			_destroy(id)
	_update_board()


func _center(id: String) -> Vector3:
	var pk: String = EVENTS[id]["place"]
	if pk != "" and world.places.has(pk):
		return world.places[pk].door
	return Vector3(BONFIRE_POS.x, world.terrain.height_at(BONFIRE_POS.x, BONFIRE_POS.y), BONFIRE_POS.y)


func _near(id: String) -> bool:
	return world.nearest_player_dist(_center(id)) < NEAR_R


func _build(id: String) -> void:
	var root := Node3D.new()
	root.name = "Udalost_" + id
	add_child(root)
	_nodes[id] = root
	match id:
		"vanoce":
			_build_vanoce(root)
		"masopust":
			_build_masopust(root)
		"carodejnice":
			_build_carodejnice(root)
		"hody":
			_build_hody(root)
		"silvestr":
			_build_silvestr(root)
		"zabava":
			_build_zabava(root)


func _destroy(id: String) -> void:
	var n: Node = _nodes[id]
	_nodes.erase(id)
	n.queue_free()
	match id:
		"zabava":
			_zab_player = null
			_zab_lights.clear()
			_zab_dancers.clear()
			_zab_band.clear()
		"vanoce":
			_xmas_lights.clear()
		"masopust":
			_walkers.clear()
		"carodejnice":
			_fire_parts.clear()
			_fire_light = null
		"silvestr":
			_fw_pool.clear()
			_fw_light = null


# ------------------------------------------------------------------ pomocné

## Zapíchne úsečku (tenký válec) mezi dva body do stavebnice.
func _seg(k: MeshKit, a: Vector3, b: Vector3, r: float, color: Color) -> void:
	var d := b - a
	if d.length() < 0.001:
		return
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = d.length()
	m.radial_segments = 5
	m.rings = 1
	k.add_prim(m, Transform3D(Basis(Quaternion(Vector3.UP, d.normalized())), (a + b) * 0.5), color)


func _glow_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.4
	m.emission_enabled = true
	m.emission = Color.WHITE
	m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	m.emission_energy_multiplier = 0.5
	return m


func _ground(x: float, z: float) -> Vector3:
	return Vector3(x, world.terrain.height_at(x, z), z)


## Volné místo před místem `key` (nejméně 6 m od silnice): zkouší vzdálenosti a boční posuny od dveří.
func _free_spot(key: String, dists: Array, lats: Array) -> Vector3:
	var pl: Place = world.places[key]
	var face: float = pl.data.get("face_yaw", 0.0)
	var b := Basis(Vector3.UP, face)
	for d in dists:
		for l in lats:
			var p := pl.door + b * Vector3(float(l), 0.0, float(d))
			if world.dist_to_roads(Vector2(p.x, p.z)) > 6.0:
				return _ground(p.x, p.z)
	var f := pl.door + b * Vector3(0.0, 0.0, 7.0)
	return _ground(f.x, f.z)


## Kulaté rozsvícené světýlko (emisní koule) do stavebnice.
func _bulb(k: MeshKit, p: Vector3, r: float, c: Color) -> void:
	k.sphere(p, r, c, Vector3.ONE, Vector3.ZERO, 6, 3)


# ------------------------------------------------------------------ taneční zábava (M5.5)

## Pódium na hospodě pod širým nebem: kapela (kytara, basa, bicí, klávesy), světla, reproduktor a parket s tančícími.
func _build_zabava(root: Node3D) -> void:
	var pl: Place = world.places["hospoda"]
	var face: float = pl.data.get("face_yaw", 0.0)
	var b := Basis(Vector3.UP, face)
	var base := _free_spot("hospoda", [11.0, 14.0, 9.0], [-8.0, 8.0, 0.0, -14.0, 14.0])
	var sp := base + b * Vector3(0.0, 0.0, -7.0)
	sp = _ground(sp.x, sp.z)
	var f := base - sp
	f.y = 0.0
	f = f.normalized()
	var yaw := atan2(-f.x, -f.z)                  # forward (−Z) kapely míří na parket
	var side := Basis(Vector3.UP, yaw) * Vector3.RIGHT
	var jd := clock.jd()
	var start := jd if zabava_day(jd) else jd - 1
	_zab_name = band_for(start)
	var rng := RandomNumberGenerator.new()
	rng.seed = start
	var wood := Color(0.42, 0.3, 0.18)
	var k := MeshKit.new()
	# parket a pódium (0,7 m nad terénem) se zadní stěnou
	k.box(base + Vector3(0, 0.02, 0), Vector3(6.0, 0.04, 6.0), Color(0.55, 0.36, 0.2), Vector3(0, yaw, 0))
	k.box(sp + Vector3(0, 0.35, 0), Vector3(7.0, 0.7, 4.0), wood, Vector3(0, yaw, 0))
	k.box(sp + Vector3(0, 2.1, 0) - f * 1.9, Vector3(7.4, 2.8, 0.2), Color(0.15, 0.12, 0.1), Vector3(0, yaw, 0))
	for s in [-3.6, 3.6]:
		k.cylinder(sp + side * float(s) + Vector3(0, 1.5, 0), 0.06, 0.06, 3.0, wood)
	# bicí: buben a činely za kapelou
	k.cylinder(sp + Vector3(0, 1.05, 0) - f * 0.6, 0.38, 0.38, 0.35, Color(0.8, 0.12, 0.12), Vector3.ZERO, 12)
	k.cylinder(sp + Vector3(0, 1.45, 0) - f * 0.6, 0.22, 0.22, 0.03, Color(0.85, 0.7, 0.3), Vector3.ZERO, 12)
	# klávesy (pultík)
	k.box(sp + side * 2.9 + Vector3(0, 1.0, 0), Vector3(0.9, 0.9, 0.5), Color(0.1, 0.1, 0.12), Vector3(0, yaw, 0))
	var mi := MeshKit.mesh_instance(root, k.commit(MeshKit.vc_material(0.9, 0.0, 0.0, false)), 300.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# nápis na zadní stěně
	var lb := Label3D.new()
	lb.text = "%s\nTANEČNÍ ZÁBAVA" % _zab_name
	lb.font_size = 64
	lb.pixel_size = 0.012
	lb.outline_size = 8
	lb.modulate = Color(1.0, 0.9, 0.5)
	lb.position = sp + Vector3(0, 2.6, 0) - f * 1.8
	lb.rotation.y = atan2(f.x, f.z)
	root.add_child(lb)
	# světla (barevné, blikají)
	_zab_lights.clear()
	for i in 3:
		var l := OmniLight3D.new()
		l.position = sp + side * float(i - 1) * 3.0 + Vector3(0, 3.4, 0) - f * 0.5
		l.omni_range = 18.0
		l.light_color = ZABAVA_LIGHTS[i]
		l.light_energy = 1.5
		root.add_child(l)
		_zab_lights.append(l)
	# reproduktor na pódiu (hudba se generuje ve vlákně, viz _start_music)
	_zab_player = AudioStreamPlayer3D.new()
	_zab_player.position = sp + Vector3(0, 1.2, 0)
	_zab_player.unit_size = 12.0
	_zab_player.max_distance = 350.0
	_zab_player.volume_db = -3.0
	root.add_child(_zab_player)
	_zab_on = true
	_zab_clock = ZABAVA_PLAY_S
	_zab_t = 0.0
	_start_music()
	# kapela: kytara, basa, bicí za kitem, klávesy u pultíku
	_zab_band.clear()
	var band_base := sp + Vector3(0, 0.7, 0)
	var shirts := [Color(0.15, 0.15, 0.18), Color(0.7, 0.1, 0.1), Color(0.2, 0.25, 0.4), Color(0.85, 0.8, 0.6)]
	for i in 4:
		var h := Humanoid.new()
		_dress(h, "", rng)
		h.shirt = shirts[i]
		h.pants = Color(0.12, 0.12, 0.15)
		h.hair_style = i % 4
		var p := band_base + side * (float(i) - 1.5) * 1.5 - f * 0.4 if i < 3 else band_base + side * 2.9
		h.position = p
		h.rotation.y = yaw
		root.add_child(h)
		_zab_band.append(h)
		if i < 2:
			var gn := Node3D.new()
			var gk := MeshKit.new()
			var body_c := Color(0.7, 0.2, 0.1) if i == 0 else Color(0.15, 0.15, 0.15)
			gk.box(Vector3(0, 0, 0), Vector3(0.14, 0.32, 0.05), body_c)
			gk.box(Vector3(0, 0.3, 0), Vector3(0.05, 0.4, 0.03), wood)
			MeshKit.mesh_instance(gn, gk.commit(MeshKit.vc_material(0.8, 0.0, 0.0, false)), 300.0)
			h.hold(gn)
	# návštěvníci: dvě třetiny tančí na parketu (kývají se k hudbě), zbytek stojí u stolů
	_zab_dancers.clear()
	var shirts_v := [Color(0.9, 0.3, 0.3), Color(0.25, 0.5, 0.85), Color(0.95, 0.95, 0.9), Color(0.3, 0.6, 0.35),
		Color(0.85, 0.7, 0.2)]
	for i in ZABAVA_VISITORS:
		var dancer := i % 3 != 0
		var p: Vector3
		if dancer:
			p = base + Vector3(rng.randf_range(-2.4, 2.4), 0.0, rng.randf_range(-2.4, 2.4))
		else:
			var a := TAU * float(i) / float(ZABAVA_VISITORS)
			p = base + Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(7.5, 12.0)
		p = _ground(p.x, p.z)
		var h := Humanoid.new()
		_dress(h, "", rng)
		h.shirt = shirts_v[rng.randi() % shirts_v.size()]
		h.vis_end = 220.0
		h.position = p
		var face_band := atan2(-(sp.x - p.x), -(sp.z - p.z))
		h.rotation.y = face_band
		root.add_child(h)
		if dancer:
			_zab_dancers.append([h, rng.randf() * TAU, face_band])


## Hudba zábavy: první pokus se generuje ve vlákně (WorkerThreadPool), pak se drží v cache.
func _start_music() -> void:
	if _zab_player == null or not is_instance_valid(_zab_player):
		return
	if not _music_cache.has("metal"):
		if _music_task < 0:
			_music_task = WorkerThreadPool.add_task(func(): _music_res = RadioMusic.make("metal"))
		return
	if _zab_player.stream == null:
		_zab_player.stream = _music_cache["metal"]
		_zab_player.stream_paused = not _zab_on
		_zab_player.play()


func _update_zabava(delta: float) -> void:
	_zab_t += delta
	_zab_clock -= delta
	if _zab_clock <= 0.0:
		_zab_on = not _zab_on
		_zab_clock = ZABAVA_PLAY_S if _zab_on else ZABAVA_PAUSE_S
		if _zab_player and is_instance_valid(_zab_player):
			_zab_player.stream_paused = not _zab_on
	if _music_task >= 0 and WorkerThreadPool.is_task_completed(_music_task):
		WorkerThreadPool.wait_for_task_completion(_music_task)
		_music_task = -1
		if _music_res:
			_music_cache["metal"] = _music_res
		_start_music()
	var col0 := int(_zab_t * 0.5)
	for i in _zab_lights.size():
		var l := _zab_lights[i]
		if not is_instance_valid(l):
			continue
		l.light_color = ZABAVA_LIGHTS[(col0 + i) % ZABAVA_LIGHTS.size()]
		var pulse := maxf(0.0, sin(_zab_t * 3.0 + float(i) * 2.1))
		l.light_energy = (1.0 + 1.2 * pulse) * (1.0 if _zab_on else 0.25)
	for e in _zab_dancers:
		var h: Humanoid = e[0]
		if is_instance_valid(h):
			h.rotation.y = float(e[2]) + sin(_zab_t * 2.2 + float(e[1])) * 0.35


# ------------------------------------------------------------------ nástěnka obce (M5.5)

## Nástěnka u obecního úřadu: nejbližší akce z `upcoming` (stálá, není vázaná na událost).
func _build_nastenka() -> void:
	if world == null or not world.places.has("urad"):
		return
	var p := _free_spot("urad", NASTENKA_POS_DIST, [-6.0, 6.0, 0.0])
	var f: Vector3 = world.places["urad"].door - p
	f.y = 0.0
	var root := Node3D.new()
	root.name = "Nastenka"
	root.position = p
	root.rotation.y = atan2(f.x, f.z)           # čelo (+Z) k úřadu
	add_child(root)
	var wood := Color(0.42, 0.3, 0.18)
	var k := MeshKit.new()
	k.cylinder(Vector3(-0.9, 0.9, 0.0), 0.05, 0.05, 1.8, wood)
	k.cylinder(Vector3(0.9, 0.9, 0.0), 0.05, 0.05, 1.8, wood)
	k.box(Vector3(0, 1.6, 0), Vector3(2.0, 1.3, 0.06), Color(0.72, 0.55, 0.35))
	MeshKit.mesh_instance(root, k.commit(MeshKit.vc_material(0.9, 0.0, 0.0, false)), 300.0)
	_board_label = Label3D.new()
	_board_label.position = Vector3(0, 1.6, 0.04)
	_board_label.pixel_size = 0.009
	_board_label.font_size = 28
	_board_label.modulate = Color(0.15, 0.12, 0.08)
	root.add_child(_board_label)
	_update_board()


func _update_board() -> void:
	if _board_label == null or not is_instance_valid(_board_label) or clock == null:
		return
	var lines := PackedStringArray(["NÁSTĚNKA OBCE"])
	var items := upcoming(14)
	if items.is_empty():
		lines.append("Zatím nic nevisí.")
	for i in mini(items.size(), 3):
		var e: Array = items[i]
		var d := Clock.from_jdn(int(e[0]))
		lines.append("%s %d. %d. – %s" % [["po", "út", "st", "čt", "pá", "so", "ne"][int(e[0]) % 7],
			int(d["day"]), int(d["month"]), String(e[1])])
	_board_label.text = "\n".join(lines)


# ------------------------------------------------------------------ Vánoce

func _build_vanoce(root: Node3D) -> void:
	_xmas_mat = _glow_material()
	_xmas_lights.clear()
	# --- stromek na návsi (u obecního úřadu)
	var base := _free_spot("urad", [7.0, 9.0, 11.0, 5.0], [0.0, 3.0, -3.0, 6.0, -6.0])
	var tree := Node3D.new()
	tree.position = base
	root.add_child(tree)
	var k := MeshKit.new()
	var green := Color(0.07, 0.26, 0.11)
	k.cylinder(Vector3(0, 0.4, 0), 0.13, 0.16, 0.8, Color(0.3, 0.2, 0.12), Vector3.ZERO, 8)
	var layers := [[1.7, 1.8, 1.75], [2.9, 1.7, 1.4], [4.0, 1.6, 1.1], [5.0, 1.4, 0.8]]   # výška středu, výška, poloměr základny
	for ly in layers:
		k.cylinder(Vector3(0, ly[0], 0), 0.05, ly[2], ly[1], green, Vector3.ZERO, 14)
	MeshKit.mesh_instance(tree, k.commit(MeshKit.vc_material(0.9)), 300.0)
	var g := MeshKit.new()
	for i in 64:
		var t := float(i) / 64.0
		var y := 1.0 + t * 4.2
		var r := lerpf(1.7, 0.2, t) * 0.97
		var a := t * TAU * 5.0
		_bulb(g, Vector3(cos(a) * r, y, sin(a) * r), 0.06, XMAS_COLORS[i % XMAS_COLORS.size()])
	_bulb(g, Vector3(0, 5.85, 0), 0.2, Color(1.0, 0.9, 0.35))
	var gi := MeshKit.mesh_instance(tree, g.commit(_xmas_mat), 300.0)
	gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 4.2, 0)
	lamp.light_color = Color(1.0, 0.82, 0.55)
	lamp.omni_range = 11.0
	lamp.light_energy = 0.0
	lamp.distance_fade_enabled = true
	lamp.distance_fade_begin = 80.0
	tree.add_child(lamp)
	_xmas_lights.append(lamp)
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.set_meta("surface", "budova")
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 1.1
	cyl.height = 4.0
	cs.shape = cyl
	cs.position.y = 2.0
	sb.add_child(cs)
	tree.add_child(sb)
	# --- řetězy světýlek na fasádách míst
	for key in ["hospoda", "obchod", "urad", "domov"]:
		if world.places.has(key):
			_facade_lights(root, world.places[key])


## Řetěz světýlek podél okapu nad dveřmi. Fasádu hledá paprsek od dveří proti průčelí (vodorovně ve výšce okapu);
## když nic netrefí, použije se pevný odstup 0,15 m před dveřmi. Výška okapu je pevná (2,6 m nad zemí u dveří) –
## výška budov v datech není, u vyšších domů je řetěz níže pod okapem.
func _facade_lights(root: Node3D, pl: Place) -> void:
	var face: float = pl.data.get("face_yaw", 0.0)
	var b := Basis(Vector3.UP, face)
	var front := b * Vector3(0, 0, 1)
	var right := b * Vector3(1, 0, 0)
	var y0 := pl.door.y + 2.6
	var from := Vector3(pl.door.x, y0, pl.door.z) + front * 3.0
	var to := Vector3(pl.door.x, y0, pl.door.z) - front * 3.0
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var origin := Vector3(pl.door.x, y0, pl.door.z) + front * 0.15
	var tangent := right
	if not hit.is_empty():
		var n: Vector3 = hit["normal"]
		n.y = 0.0
		if n.length() > 0.5:
			n = n.normalized()
			var hp: Vector3 = hit["position"]
			origin = Vector3(hp.x, y0, hp.z) + n * 0.12
			tangent = n.cross(Vector3.UP).normalized()
	var k := MeshKit.new()
	var wire := Color(0.05, 0.05, 0.05)
	var n_b := 16
	var prev := Vector3.ZERO
	for i in n_b + 1:
		var t := float(i) / n_b
		var p := origin + tangent * lerpf(-3.6, 3.6, t) - Vector3(0, 0.32 * 4.0 * t * (1.0 - t), 0)
		_bulb(k, p, 0.055, XMAS_COLORS[i % XMAS_COLORS.size()])
		if i > 0:
			_seg(k, prev, p, 0.008, wire)
		prev = p
	var mi := MeshKit.mesh_instance(root, k.commit(_xmas_mat), 220.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ------------------------------------------------------------------ Masopust

func _build_masopust(root: Node3D) -> void:
	var a: Place = world.places["urad"]
	var b: Place = world.places["hospoda"]
	_path = _make_path(Vector2(a.door.x, a.door.z), Vector2(b.door.x, b.door.z))
	_walkers.clear()
	_walk_d = 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	for i in MASOPUST_N:
		var w := Node3D.new()
		root.add_child(w)
		var h := Humanoid.new()
		var kind: String = MASKS[i % MASKS.size()]
		_dress(h, kind, rng)
		w.add_child(h)
		_mask(h, kind)
		_walkers.append([w, h])
	_update_procession(0.0)


## Trasa po silnicích od bodu a k bodu b (uzly grafu, posun ke krajnici), převzorkovaná po 1 m.
func _make_path(a: Vector2, b: Vector2) -> PackedVector2Array:
	var g: RoadGraph = world.graph
	var ids: PackedInt64Array = g.route(a, b)
	var pts := PackedVector2Array()
	pts.append(a)
	for k in ids.size():
		var p: Vector2 = g.nodes[ids[k]]
		var d := Vector2.ZERO
		if k < ids.size() - 1:
			d += (g.nodes[ids[k + 1]] - p).normalized()
		if k > 0:
			d += (p - g.nodes[ids[k - 1]]).normalized()
		d = d.normalized()
		pts.append(p + Vector2(-d.y, d.x) * MASOPUST_OFFSET)
	pts.append(b)
	var out := PackedVector2Array()
	for k in pts.size() - 1:
		var n := maxi(int(pts[k].distance_to(pts[k + 1])), 1)
		for j in n:
			out.append(pts[k].lerp(pts[k + 1], float(j) / n))
	out.append(pts[pts.size() - 1])
	return out


## Průvod jde tam a zpět: i-tá maska je o i·rozestup za vůdcem (na obratu se řada „otáčí“ postupně).
func _update_procession(delta: float) -> void:
	if _path.size() < 3:
		return
	_walk_d += MASOPUST_SPEED * delta
	var len_m := float(_path.size() - 1)
	for i in _walkers.size():
		var u := fposmod(_walk_d - i * MASOPUST_SPACING, 2.0 * len_m)
		var fwd := u < len_m
		var s := u if fwd else 2.0 * len_m - u
		var i0 := clampi(int(s), 0, _path.size() - 2)
		var p := _path[i0].lerp(_path[i0 + 1], s - i0)
		var dir := _path[i0 + 1] - _path[i0]
		if not fwd:
			dir = -dir
		var w: Node3D = _walkers[i][0]
		var h: Humanoid = _walkers[i][1]
		w.position = Vector3(p.x, world.terrain.height_at(p.x, p.y) + 0.03, p.y)
		h.rotation.y = lerp_angle(h.rotation.y, atan2(dir.x, dir.y), 0.2) if delta > 0.0 else atan2(dir.x, dir.y)
		h.speed = MASOPUST_SPEED
		h.on_floor = true


## Barvy a vlastnosti masky (před přidáním do stromu).
func _dress(h: Humanoid, kind: String, rng: RandomNumberGenerator) -> void:
	h.long_sleeves = true
	h.hair_style = rng.randi() % 4
	match kind:
		"medved":
			h.shirt = Color(0.33, 0.2, 0.1)
			h.pants = Color(0.3, 0.18, 0.09)
			h.hair = Color(0.3, 0.18, 0.09)
			h.fat = 0.5
		"kobyla":
			h.shirt = Color(0.9, 0.9, 0.85)
			h.pants = Color(0.88, 0.88, 0.82)
		"slameny":
			h.shirt = Color(0.85, 0.72, 0.35)
			h.pants = Color(0.82, 0.68, 0.32)
			h.hair = Color(0.85, 0.72, 0.35)
			h.fat = 0.3
		"kominik":
			h.shirt = Color(0.06, 0.06, 0.07)
			h.pants = Color(0.05, 0.05, 0.06)
			h.skin = Color(0.4, 0.33, 0.3)
		"klaun":
			h.shirt = Color(0.9, 0.2, 0.2)
			h.pants = Color(0.2, 0.35, 0.85)
			h.skin = Color(0.96, 0.92, 0.9)
			h.hair = Color(0.95, 0.5, 0.1)


## Maska / klobouk nasazená na hlavu (potřebuje postavu ve stromě – `head_node()`).
func _mask(h: Humanoid, kind: String) -> void:
	var head := h.head_node()
	if head == null:
		return
	var k := MeshKit.new()
	match kind:
		"medved":
			var fur := Color(0.32, 0.2, 0.1)
			k.sphere(Vector3(0, 0.13, -0.01), 0.14, fur, Vector3(1.0, 1.05, 1.05))
			for s in [-1.0, 1.0]:
				k.sphere(Vector3(0.09 * s, 0.25, 0.0), 0.04, fur.darkened(0.2))
				k.sphere(Vector3(0.045 * s, 0.155, 0.12), 0.012, Color(0.05, 0.04, 0.03), Vector3.ONE, Vector3.ZERO, 6, 4)
			k.sphere(Vector3(0, 0.095, 0.115), 0.055, Color(0.5, 0.36, 0.2), Vector3(1.0, 0.8, 1.2))
			k.sphere(Vector3(0, 0.11, 0.17), 0.02, Color(0.04, 0.03, 0.03), Vector3.ONE, Vector3.ZERO, 6, 4)
		"kobyla":
			var coat := Color(0.55, 0.4, 0.28)
			k.sphere(Vector3(0, 0.13, 0.0), 0.125, coat)
			k.box(Vector3(0, 0.12, 0.17), Vector3(0.12, 0.14, 0.28), coat, Vector3(0.28, 0, 0))
			k.box(Vector3(0, 0.055, 0.31), Vector3(0.1, 0.1, 0.1), Color(0.85, 0.76, 0.66), Vector3(0.28, 0, 0))
			for s in [-1.0, 1.0]:
				k.cylinder(Vector3(0.05 * s, 0.29, 0.0), 0.0, 0.028, 0.09, coat.darkened(0.15), Vector3.ZERO, 6)
			k.box(Vector3(0, 0.24, -0.06), Vector3(0.03, 0.17, 0.22), Color(0.1, 0.07, 0.05), Vector3(-0.25, 0, 0))
		"slameny":
			var straw := Color(0.86, 0.73, 0.36)
			k.sphere(Vector3(0, 0.13, 0.0), 0.13, straw.darkened(0.08))
			k.cylinder(Vector3(0, 0.3, 0), 0.09, 0.11, 0.12, straw, Vector3.ZERO, 12)
			k.cylinder(Vector3(0, 0.245, 0), 0.26, 0.26, 0.02, straw.darkened(0.1), Vector3.ZERO, 16)
		"kominik":
			var black := Color(0.05, 0.05, 0.06)
			k.cylinder(Vector3(0, 0.37, 0), 0.085, 0.09, 0.22, black, Vector3.ZERO, 12)
			k.cylinder(Vector3(0, 0.26, 0), 0.16, 0.16, 0.02, black, Vector3.ZERO, 16)
		"klaun":
			k.cylinder(Vector3(0, 0.37, 0), 0.0, 0.1, 0.24, Color(1.0, 0.85, 0.2), Vector3.ZERO, 12)
			k.sphere(Vector3(0, 0.115, 0.115), 0.03, Color(0.95, 0.1, 0.1), Vector3.ONE, Vector3.ZERO, 8, 5)
			for s in [-1.0, 1.0]:
				k.sphere(Vector3(0.105 * s, 0.17, -0.02), 0.06, Color(0.95, 0.5, 0.1))
	if not k.is_empty():
		MeshKit.mesh_instance(head, k.commit(MeshKit.vc_material(0.95)), 120.0)


# ------------------------------------------------------------------ Pálení čarodějnic

func _build_carodejnice(root: Node3D) -> void:
	var g := _ground(BONFIRE_POS.x, BONFIRE_POS.y)
	var fire := Node3D.new()
	fire.position = g
	root.add_child(fire)
	var k := MeshKit.new()
	var wood := Color(0.42, 0.28, 0.16)
	var rng := RandomNumberGenerator.new()
	rng.seed = 430
	# hranice: kužel z opřených polen a věnec ležících
	for i in 26:
		var a := float(i) / 26.0 * TAU + rng.randf() * 0.1
		var tilt := deg_to_rad(rng.randf_range(20.0, 30.0))
		var o := Vector3(cos(a), 0, sin(a))
		var axis := (Vector3.UP * cos(tilt) - o * sin(tilt)).normalized()
		var length := rng.randf_range(2.6, 3.4)
		var m := CylinderMesh.new()
		m.top_radius = 0.07
		m.bottom_radius = 0.1
		m.height = length
		m.radial_segments = 6
		m.rings = 1
		k.add_prim(m, Transform3D(Basis(Quaternion(Vector3.UP, axis)), o * 1.3 + axis * length * 0.5),
			wood.darkened(rng.randf() * 0.3))
	for i in 12:
		var a := float(i) / 12.0 * TAU
		var tang := Vector3(-sin(a), 0, cos(a))
		var m2 := CylinderMesh.new()
		m2.top_radius = 0.1
		m2.bottom_radius = 0.1
		m2.height = 1.4
		m2.radial_segments = 6
		m2.rings = 1
		k.add_prim(m2, Transform3D(Basis(Quaternion(Vector3.UP, tang)),
			Vector3(cos(a) * 1.15, 0.12 + (i % 2) * 0.22, sin(a) * 1.15)), wood.darkened(0.15))
	# kůl s čarodějnicí
	k.cylinder(Vector3(0, 2.0, 0), 0.05, 0.06, 4.0, wood.darkened(0.3), Vector3.ZERO, 8)
	k.cylinder(Vector3(0, 3.25, 0), 0.07, 0.3, 0.9, Color(0.14, 0.07, 0.2), Vector3.ZERO, 10)          # sukně
	k.box(Vector3(0, 3.75, 0), Vector3(0.9, 0.06, 0.06), Color(0.85, 0.72, 0.38))                        # ruce ze slámy
	k.sphere(Vector3(0, 3.85, 0), 0.13, Color(0.75, 0.8, 0.5))                                          # hlava
	k.cylinder(Vector3(0, 4.15, 0), 0.0, 0.17, 0.32, Color(0.05, 0.04, 0.06), Vector3.ZERO, 8)          # špičatý klobouk
	k.cylinder(Vector3(0, 3.98, 0), 0.3, 0.3, 0.02, Color(0.05, 0.04, 0.06), Vector3.ZERO, 12)
	k.capsule(Vector3(0.55, 3.55, 0), 0.03, 1.1, Color(0.5, 0.35, 0.2), Vector3(0, 0, 0.5))              # koště
	MeshKit.mesh_instance(fire, k.commit(MeshKit.vc_material(0.95)), 400.0)
	# plamen
	_fire_parts.clear()
	_fire_parts.append(_fire_particles(fire, 0.9, 130, Vector2(0.75, 0.75), 1.3, 1.8, 3.4,
		[Color(1.0, 0.95, 0.6, 0.9), Color(1.0, 0.5, 0.1, 0.7), Color(0.5, 0.1, 0.05, 0.0)]))
	_fire_parts.append(_fire_particles(fire, 0.7, 40, Vector2(0.09, 0.09), 1.8, 2.5, 6.0,
		[Color(1.0, 0.9, 0.4, 1.0), Color(1.0, 0.5, 0.1, 0.8), Color(1.0, 0.3, 0.05, 0.0)]))
	_fire_light = OmniLight3D.new()
	_fire_light.position = Vector3(0, 1.8, 0)
	_fire_light.light_color = Color(1.0, 0.55, 0.22)
	_fire_light.omni_range = 26.0
	_fire_light.light_energy = 0.0
	_fire_light.distance_fade_enabled = true
	_fire_light.distance_fade_begin = 150.0
	fire.add_child(_fire_light)
	# vesničané kolem
	for i in BONFIRE_CROWD:
		var a2 := float(i) / BONFIRE_CROWD * TAU + rng.randf() * 0.4
		var r := rng.randf_range(6.0, 9.0)
		var pos := _ground(g.x + cos(a2) * r, g.z + sin(a2) * r)
		var to := g - pos
		var prof: Dictionary = Characters.profile(i * 3 + 1)
		var col := Color.from_hsv(rng.randf(), 0.45, rng.randf_range(0.5, 0.85))
		var npc := Npc.make(Characters.first_name(prof), "", col, 600 + i, pos, atan2(to.x, to.z), world)
		root.add_child(npc)


## Částice ohně (M2.2: sdílený kód je ve `FireFx.particles`).
func _fire_particles(parent: Node3D, radius: float, amount: int, quad: Vector2, life: float, v_min: float, v_max: float,
		ramp: Array) -> GPUParticles3D:
	return FireFx.particles(parent, radius, amount, quad, life, v_min, v_max, ramp)


## Sdílený materiál měkkého svítícího kolečka (aditivní, billboard, barva z částic) – viz `FireFx`.
static func _soft_dot_material() -> StandardMaterial3D:
	return FireFx.soft_dot_material()


## Hranice hoří od BONFIRE_LIT_HOUR (půl hodiny se rozhoří), světlo mihotá.
func _update_bonfire(delta: float) -> void:
	_fire_seed += delta
	var grow := clampf((clock.hour() - BONFIRE_LIT_HOUR) / 0.5, 0.0, 1.0)
	for p in _fire_parts:
		p.emitting = grow > 0.0
		p.amount_ratio = maxf(grow, 0.05)
	if _fire_light:
		var fl := 0.8 + 0.25 * sin(_fire_seed * 13.0) + 0.15 * sin(_fire_seed * 31.0 + 1.7) + 0.1 * sin(_fire_seed * 7.3)
		_fire_light.light_energy = grow * 3.0 * fl


# ------------------------------------------------------------------ Hody

func _build_hody(root: Node3D) -> void:
	var pl: Place = world.places["hospoda"]
	var face: float = pl.data.get("face_yaw", 0.0)
	var b := Basis(Vector3.UP, face)
	var wood := Color(0.4, 0.28, 0.16)
	var a := pl.door + b * Vector3(7.0, 0.0, 4.5)
	var c := pl.door + b * Vector3(-10.5, 0.0, 4.5)
	a.y = world.terrain.height_at(a.x, a.z)
	c.y = world.terrain.height_at(c.x, c.z)
	var k := MeshKit.new()
	var top_a := a + Vector3(0, 4.8, 0)
	var top_c := c + Vector3(0, 4.8, 0)
	for pole in [a, c]:
		k.cylinder(pole + Vector3(0, 2.4, 0), 0.05, 0.07, 4.8, wood, Vector3.ZERO, 8)
	var flags := [Color(0.85, 0.15, 0.15), Color(0.95, 0.95, 0.95)]
	for i in 2:
		var pole: Vector3 = [a, c][i]
		k.box(pole + Vector3(0, 4.3, 0), Vector3(0.55, 0.9, 0.03), flags[i], Vector3(0, face, 0))
	# girlanda: lano s prověšením a barevné trojúhelníkové praporky
	var n_seg := 24
	var prev := top_a
	var cols := [Color(0.9, 0.15, 0.15), Color(0.95, 0.8, 0.2), Color(0.2, 0.45, 0.85), Color(0.95, 0.95, 0.95),
		Color(0.25, 0.65, 0.3)]
	var rope := Color(0.2, 0.15, 0.1)
	for i in range(1, n_seg + 1):
		var t := float(i) / n_seg
		var p := top_a.lerp(top_c, t) - Vector3(0, 0.7 * 4.0 * t * (1.0 - t), 0)
		_seg(k, prev, p, 0.012, rope)
		if i % 2 == 0 and i < n_seg:
			var tan_v := (top_c - top_a).normalized()
			var col: Color = cols[(i / 2) % cols.size()]
			k.tri(p - tan_v * 0.16, p + tan_v * 0.16, p - Vector3(0, 0.42, 0), col)
		prev = p
	var mi := MeshKit.mesh_instance(root, k.commit(MeshKit.vc_material(0.9, 0.0, 0.0, false)), 300.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ------------------------------------------------------------------ Silvestr

func _build_silvestr(root: Node3D) -> void:
	_fw_center = world.places["urad"].door
	_fw_pool.clear()
	for i in FIREWORK_POOL:
		var p := GPUParticles3D.new()
		p.amount = 150
		p.lifetime = 2.4
		p.one_shot = true
		p.explosiveness = 1.0
		p.emitting = false
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.visibility_aabb = AABB(Vector3(-50, -50, -50), Vector3(100, 100, 100))
		var m := ParticleProcessMaterial.new()
		m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
		m.direction = Vector3.UP
		m.spread = 180.0
		m.initial_velocity_min = 12.0
		m.initial_velocity_max = 22.0
		m.damping_min = 3.5
		m.damping_max = 5.0
		m.gravity = Vector3(0, -5.0, 0)
		m.scale_min = 0.5
		m.scale_max = 1.0
		var gr := Gradient.new()
		gr.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
		gr.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.85), Color(1, 1, 1, 0)])
		var gt := GradientTexture1D.new()
		gt.gradient = gr
		m.color_ramp = gt
		p.process_material = m
		var qm := QuadMesh.new()
		qm.size = Vector2(0.55, 0.55)
		qm.material = _soft_dot_material()
		p.draw_pass_1 = qm
		root.add_child(p)
		_fw_pool.append(p)
	_fw_light = OmniLight3D.new()
	_fw_light.omni_range = 260.0
	_fw_light.light_energy = 0.0
	_fw_light.shadow_enabled = false
	root.add_child(_fw_light)
	_fw_t = 1.5
	_fw_flash = 0.0


## Ohňostroj: mimo půlnoc jedna rána za pár sekund, kolem půlnoci (±5 herních minut) salvy.
func _update_fireworks(delta: float) -> void:
	_fw_flash = maxf(_fw_flash - delta * 2.5, 0.0)
	if _fw_light:
		_fw_light.light_energy = _fw_flash * 2.5
	_fw_t -= delta
	if _fw_t > 0.0:
		return
	var hr := clock.hour()
	var to_midnight := (hr - 24.0 if hr > 12.0 else hr) * 60.0     # minuty od půlnoci (− před, + po)
	var peak := absf(to_midnight) < 5.0
	_fw_t = randf_range(0.5, 1.1) if peak else randf_range(3.0, 6.0)
	for n in (3 if peak else 1):
		_launch_firework()


func _launch_firework() -> void:
	for p in _fw_pool:
		if p.emitting:
			continue
		var a := randf() * TAU
		var d := randf_range(10.0, 140.0)
		var gp := _ground(_fw_center.x + cos(a) * d, _fw_center.z + sin(a) * d)
		var pos := gp + Vector3(0, randf_range(40.0, 90.0), 0)
		var col: Color = FIREWORK_COLORS[randi() % FIREWORK_COLORS.size()]
		var m: ParticleProcessMaterial = p.process_material
		m.color = col
		m.initial_velocity_max = randf_range(16.0, 26.0)
		p.global_position = pos
		p.restart()
		p.emitting = true
		_fw_flash = 1.0
		_fw_light.global_position = pos
		_fw_light.light_color = col
		# rána dorazí se zpožděním podle vzdálenosti (zvuk ~ 340 m/s, přehnaně zkráceno)
		var pl_dist := world.nearest_player_dist(pos)
		var lag := clampf(pl_dist / 340.0, 0.15, 1.2)
		get_tree().create_timer(lag).timeout.connect(func(): world.sound.emit(gp, "crash", randf_range(0.45, 0.7), -4.0, 600.0))
		return
