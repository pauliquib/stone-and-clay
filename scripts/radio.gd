## Rádio doma (stolek u vchodu domova – M1.7 `World.apply_home`, uvnitř na komodě): staré lampové rádio – stanice, hlasitost 0–10 a sousedé.
##
## Ovládání knoflíky (RadioView – přiblížení na rádio, E): levý knoflík = vypínač a hlasitost (`knob` 0–1,
## pod KNOB_OFF cvakne a vypne), pravý = ladění (`dial` 0–1 → ručička na skleněné stupnici). Stanice leží
## na stupnici rovnoměrně (`station_pos`); do DIAL_TOL od stanice hraje (a po chvilce klidu se naladí –
## ať se při točení nespouští ffmpeg u každé stanice), mezi stanicemi šumí. Lampy se po zapnutí ~2 s nahřívají.
##
## Stanice:
##   – smyšlené, hudba generovaná ve hře (RadioMusic): „Rádio Kovadlina“ (metal), „Rádio Pohoda“ (klidná hudba)
##   – internetové rozhlasové stanice ze souboru data/radia.json (veřejné streamy – přehrávají se jen
##     u hráče, hra je nešíří dál). Dekóduje je program ffmpeg (OS.execute_with_pipe → PCM → AudioStreamGenerator);
##     bez ffmpeg nebo bez internetu stanice nehraje a hra to oznámí.
##
## Sousedé: hlasitost × „hlučnost“ stanice (metal 1,0 · klidná hudba 0,3 · mluvené slovo 0,3…) = hluk.
## Nad únosnou mez (v noci 22–6 h, noční klid, je mez nízká a zlost roste 3× rychleji) roste zlost
## sousedů 0–100: nejdřív si stěžují (bublina vesničana / dědy, zpráva), pak trpí pověst
## („rušení klidu“), v noci nakonec zavolají policii (pokuta, rádio se ztlumí). Příjemná tichá hudba
## přes den naopak dědu Vomáčku potěší. Zlost bez hluku postupně vyprchá.
## Stav (stanice, hlasitost, zlost) se ukládá (SaveGame). Rádio vlastní ten hráč, který ho naposledy ovládal.
class_name Radio
extends Node3D

const BUILTIN := [
	{"id": "metal", "name": "Rádio Kovadlina", "genre": "metal", "noise": 1.0},
	{"id": "pohoda", "name": "Rádio Pohoda", "genre": "klidná hudba", "noise": 0.3},
]
const NIGHT_FROM := 22.0
const NIGHT_TO := 6.0
const PCM_RATE := 22050
const KNOB_OFF := 0.05                 # levý knoflík pod touto polohou = vypnuto (cvaknutí)
const DIAL_TOL := 0.02                 # jak přesně se musí naladit (část stupnice)
const DIAL_W := 0.2                    # půl šířky stupnice (m) – ručička jede v x ∈ ⟨−DIAL_W, DIAL_W⟩
const KNOB_VOL_POS := Vector3(-0.2, 0.795, 0.12)    # poloha knoflíků (lokálně, přední stěna)
const KNOB_TUNE_POS := Vector3(0.2, 0.795, 0.12)
const KNOB_R := 0.029

static var _music_cache := {}          # id → AudioStreamWAV (vyrobená hudba)
static var _hiss_wav: AudioStreamWAV   # šum mezi stanicemi (vyrobený jednou)

var world: World
var car_mode := false                  # M5.9: autorádio ve vozidle – bez modelu lampového rádia a bez štítků na stupnici
var stations: Array = []               # BUILTIN + data/radia.json
var station := ""                      # id stanice, "" = vypnuto
var volume := 5                        # 0..10
var owner_id := 1
var anger := 0.0                       # zlost sousedů 0..100
var status := ""                       # „ladím…“, chyba streamu
var power := false                     # vypínač (levý knoflík)
var dial := 0.5                        # poloha ladění 0..1 (pravý knoflík, ručička)
var knob := 0.0                        # poloha levého knoflíku 0..1 (vypnuto pod KNOB_OFF)

var _player: AudioStreamPlayer3D
var _task := -1                        # WorkerThreadPool úloha výroby hudby
var _task_id := ""
var _task_result: AudioStreamWAV
var _last_min := -1.0
var _complain_cool := 0.0              # herní minuty
var _rep_cool := 0.0
var _police_cool := 0.0
var _praise_day := -1
var _said := 0                          # kolik stížností už zaznělo v této vlně (0..2)
var _label: Label3D
var _hiss: AudioStreamPlayer3D
var _warm := 0.0                        # nahřátí lamp 0..1
var _pending := ""                     # stanice, na kterou se naladí po chvilce klidu
var _pending_t := -1.0
var _knob_vol: Node3D
var _knob_tune: Node3D
var _needle: Node3D
var _glass_mat: StandardMaterial3D
var _eye_mat: StandardMaterial3D

# internetový stream
var _proc := {}
var _thread: Thread
var _mutex := Mutex.new()
var _pcm := PackedFloat32Array()
var _reading := false
var _gen_pb: AudioStreamGeneratorPlayback
var _stream_wait := 0.0


static func make(w: World, pos: Vector3, yaw: float) -> Radio:
	var r := Radio.new()
	r.world = w
	r.name = "Radio"
	r.position = pos
	r.rotation.y = yaw
	return r


func _ready() -> void:
	stations = BUILTIN.duplicate(true)
	if FileAccess.file_exists("res://data/radia.json"):
		var extra = JSON.parse_string(FileAccess.get_file_as_string("res://data/radia.json"))
		if extra is Array:
			for s in extra:
				if s is Dictionary and s.has("url") and s.has("name"):
					stations.append({"id": "net:" + String(s["url"]), "name": String(s["name"]), "url": String(s["url"]),
						"genre": String(s.get("genre", "internetové rádio")), "noise": float(s.get("noise", 0.5))})
	if not car_mode:
		_build_model()
	_player = AudioStreamPlayer3D.new()
	_player.attenuation_filter_cutoff_hz = 7000.0
	_player.position = Vector3(0, 0.95, 0) if not car_mode else Vector3.ZERO
	add_child(_player)
	_hiss = AudioStreamPlayer3D.new()
	_hiss.attenuation_filter_cutoff_hz = 7000.0
	_hiss.position = _player.position
	_hiss.stream = _hiss_stream()
	add_child(_hiss)
	_apply_volume()
	if not car_mode:
		_build_dial_labels()
	_update_label()


func _build_model() -> void:
	var k := MeshKit.new()
	var wood := Color(0.45, 0.3, 0.17)
	# zahradní stolek
	k.box(Vector3(0, 0.72, 0), Vector3(0.9, 0.05, 0.6), wood)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			k.box(Vector3(0.38 * sx, 0.35, 0.24 * sz), Vector3(0.05, 0.7, 0.05), wood.darkened(0.25))
	# lampové rádio: dřevěná skříň se zaoblenými horními rohy, látkový reproduktor se zlatými lištami,
	# skleněná stupnice s ručičkou, magické oko, dva knoflíky (vlastní uzly – otáčejí se)
	var veneer := Color(0.42, 0.23, 0.11)
	k.box(Vector3(0, 0.905, 0), Vector3(0.56, 0.32, 0.24), veneer)
	k.box(Vector3(0, 1.085, 0), Vector3(0.48, 0.04, 0.24), veneer)
	for sx in [-1.0, 1.0]:
		k.cylinder(Vector3(0.24 * sx, 1.065, 0), 0.04, 0.04, 0.24, veneer, Vector3(PI / 2, 0, 0))
	k.box(Vector3(0, 0.752, 0.002), Vector3(0.58, 0.016, 0.25), Color(0.16, 0.09, 0.05))     # sokl
	k.box(Vector3(0, 1.0, 0.1205), Vector3(0.48, 0.15, 0.003), veneer.lightened(0.15))       # rám reproduktoru
	k.box(Vector3(0, 1.0, 0.122), Vector3(0.45, 0.13, 0.003), Color(0.6, 0.48, 0.32))        # potahová látka
	for x in [-0.15, -0.075, 0.075, 0.15]:
		k.box(Vector3(x, 1.0, 0.1245), Vector3(0.007, 0.13, 0.004), Color(0.8, 0.64, 0.3))
	k.box(Vector3(0, 0.855, 0.1205), Vector3(0.47, 0.09, 0.003), Color(0.8, 0.64, 0.3))      # zlatý rámeček stupnice
	k.box(Vector3(0, 0.855, 0.1236), Vector3(2 * DIAL_W, 0.0015, 0.001), Color(0.3, 0.2, 0.1)) # linka stupnice
	for i in 21:                                                                             # dílky
		var x := lerpf(-DIAL_W, DIAL_W, i / 20.0)
		k.box(Vector3(x, 0.855, 0.1236), Vector3(0.0012, 0.008 if i % 5 == 0 else 0.004, 0.001), Color(0.3, 0.2, 0.1))
	for sx in [-1.0, 1.0]:                                                                   # objímky knoflíků
		k.cylinder(Vector3(0.2 * sx, 0.795, 0.1215), 0.036, 0.036, 0.003, Color(0.8, 0.64, 0.3), Vector3(PI / 2, 0, 0), 24)
	MeshKit.mesh_instance(self, k.commit(MeshKit.vc_material(0.35, 0.0, 0.0, false)), 150.0)
	# skleněná stupnice – za tmy svítí, když je rádio zapnuté
	_glass_mat = StandardMaterial3D.new()
	_glass_mat.albedo_color = Color(0.93, 0.86, 0.66)
	_glass_mat.roughness = 0.15
	_glass_mat.emission_enabled = true
	_glass_mat.emission = Color(1.0, 0.72, 0.35)
	_glass_mat.emission_energy_multiplier = 0.0
	var glass := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.44, 0.075, 0.003)
	glass.mesh = gm
	glass.material_override = _glass_mat
	glass.position = Vector3(0, 0.855, 0.122)
	glass.visibility_range_end = 60.0
	add_child(glass)
	# magické oko (zelená ladicí výbojka) nad reproduktorem
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.albedo_color = Color(0.05, 0.12, 0.06)
	_eye_mat.emission_enabled = true
	_eye_mat.emission = Color(0.3, 1.0, 0.45)
	_eye_mat.emission_energy_multiplier = 0.0
	var eye := MeshInstance3D.new()
	var em := CylinderMesh.new()
	em.top_radius = 0.013
	em.bottom_radius = 0.013
	em.height = 0.008
	eye.mesh = em
	eye.material_override = _eye_mat
	eye.rotation.x = PI / 2
	eye.position = Vector3(0, 1.085, 0.122)
	eye.visibility_range_end = 60.0
	add_child(eye)
	# ručička stupnice
	var nk := MeshKit.new()
	nk.box(Vector3(0, 0, 0), Vector3(0.003, 0.068, 0.002), Color(0.75, 0.08, 0.05))
	_needle = MeshKit.mesh_instance(self, nk.commit(MeshKit.vc_material(0.5)), 40.0)
	_needle.position = Vector3(0, 0.855, 0.1245)
	# knoflíky z bakelitu s rýhováním a bílou ryskou
	var kk := MeshKit.new()
	var bakelit := Color(0.13, 0.08, 0.05)
	kk.cylinder(Vector3(0, 0, 0.012), 0.026, KNOB_R, 0.024, bakelit, Vector3(PI / 2, 0, 0), 24)
	kk.cylinder(Vector3(0, 0, 0.0245), 0.02, 0.023, 0.003, bakelit.lightened(0.12), Vector3(PI / 2, 0, 0), 24)
	for i in 18:
		var a := TAU * i / 18.0
		kk.box(Vector3(cos(a), sin(a), 0) * 0.0275 + Vector3(0, 0, 0.011), Vector3(0.004, 0.004, 0.02), bakelit, Vector3(0, 0, a))
	kk.box(Vector3(0, 0.013, 0.0265), Vector3(0.0035, 0.014, 0.002), Color(0.92, 0.88, 0.78))
	var knob_mesh := kk.commit(MeshKit.vc_material(0.3))
	_knob_vol = Node3D.new()
	_knob_vol.position = KNOB_VOL_POS
	add_child(_knob_vol)
	MeshKit.mesh_instance(_knob_vol, knob_mesh, 40.0)
	_knob_tune = Node3D.new()
	_knob_tune.position = KNOB_TUNE_POS
	add_child(_knob_tune)
	MeshKit.mesh_instance(_knob_tune, knob_mesh, 40.0)
	_update_visuals()
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.set_meta("surface", "budova")
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.9, 1.1, 0.6)
	cs.shape = bs
	cs.position = Vector3(0, 0.55, 0)
	sb.add_child(cs)
	add_child(sb)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 26
	_label.outline_size = 8
	_label.position = Vector3(0, 1.6, 0)
	_label.modulate = Color(0.8, 0.95, 1.0)
	_label.visibility_range_end = 20.0
	add_child(_label)


# ------------------------------------------------------------------ ovládání (akce hráče přes World)

func station_info(id := "") -> Dictionary:
	var sid := station if id == "" else id
	for s in stations:
		if s["id"] == sid:
			return s
	return {}


func is_on() -> bool:
	return power


func describe() -> String:
	if not power:
		return "vypnuto"
	if station == "":
		return "šum mezi stanicemi · hlasitost %d/10" % volume
	var s := station_info()
	return "%s (%s) · hlasitost %d/10%s" % [s.get("name", "?"), s.get("genre", ""), volume,
		"" if status == "" else " · " + status]


## Poloha stanice `i` na stupnici (0..1) – rovnoměrně s okraji.
func station_pos(i: int) -> float:
	return 0.5 if stations.size() < 2 else lerpf(0.06, 0.94, float(i) / (stations.size() - 1))


## [index nejbližší stanice, vzdálenost na stupnici] k poloze ladění `x`.
func nearest_station(x: float) -> Array:
	var best := -1
	var bd := INF
	for i in stations.size():
		var d := absf(station_pos(i) - x)
		if d < bd:
			bd = d
			best = i
	return [best, bd]


func _knob_for(v: int) -> float:
	return lerpf(KNOB_OFF + 0.02, 1.0, v / 10.0)


## Naladit stanici ("" = vypnout) – nabídka rádia a načtení hry; ručička skočí na stanici.
func tune(pid: int, id: String) -> void:
	owner_id = pid
	if id == "":
		power = false
		knob = 0.0
	else:
		for i in stations.size():
			if stations[i]["id"] == id:
				dial = station_pos(i)
				power = true
				if knob < KNOB_OFF:
					knob = _knob_for(volume)
	_retune(true)


func set_volume(pid: int, v: int) -> void:
	owner_id = pid
	volume = clampi(v, 0, 10)
	if power:
		knob = _knob_for(volume)
	_apply_volume()
	_update_label()


## Levý knoflík (0..1): pod KNOB_OFF vypnuto, výš zapnuto a hlasitost 0–10.
func turn_volume(pid: int, k: float) -> void:
	owner_id = pid
	knob = clampf(k, 0.0, 1.0)
	var was := power
	power = knob >= KNOB_OFF
	if power:
		volume = clampi(roundi(remap(knob, KNOB_OFF + 0.02, 1.0, 0.0, 10.0)), 0, 10)
	_apply_volume()
	if power != was:
		world.play_sfx(pid, "pickup")          # cvaknutí vypínače
		_retune(true)
	_update_label()


## Pravý knoflík: ladění 0..1. U stanice se naladí po chvilce klidu, mezi stanicemi šumí.
func turn_dial(pid: int, x: float) -> void:
	owner_id = pid
	dial = clampf(x, 0.0, 1.0)
	_retune(false)


func _retune(immediate: bool) -> void:
	var target := ""
	if power:
		var n := nearest_station(dial)
		if n[0] >= 0 and float(n[1]) <= DIAL_TOL:
			target = stations[n[0]]["id"]
	if target == station:
		_pending_t = -1.0
		_update_label()
		return
	if immediate or target == "":
		_pending_t = -1.0
		_switch(target)
	elif _pending != target or _pending_t < 0.0:
		_pending = target
		_pending_t = 0.35
	if station != "" and target != station:
		_switch("")                             # odladěno ze stanice → hned šum


func _switch(id: String) -> void:
	_stop_all()
	station = id
	if id != "":
		var s := station_info(id)
		if s.is_empty():
			station = ""
		elif s.has("url"):
			_start_stream(String(s["url"]))
		else:
			_start_music(id)
	_update_label()


func _apply_volume() -> void:
	if _player == null:
		return
	# 0 = ztlumeno; 10 ≈ +6 dB a slyšet přes půl vsi (hlasitost v dB počítá _update_audio)
	for p in [_player, _hiss]:
		p.unit_size = 2.0 + volume * 0.9
		p.max_distance = 15.0 + volume * 11.0


## Každý snímek: nahřívání lamp, míchání hudby a šumu podle přesnosti naladění.
func _update_audio(delta: float) -> void:
	_warm = move_toward(_warm, 1.0 if power else 0.0, delta * (0.45 if power else 2.5))
	if _pending_t >= 0.0:
		_pending_t -= delta
		if _pending_t < 0.0:
			_switch(_pending)
	var h := 0.0                                # šum 0..1
	if power:
		var d := float(nearest_station(dial)[1])
		h = clampf((d - 0.004) / (DIAL_TOL * 1.5), 0.0, 1.0)
		if station == "" or status != "":
			h = maxf(h, 0.35)
	var base := -80.0 if volume == 0 else -24.0 + volume * 3.0
	_player.volume_db = base + linear_to_db(maxf(_warm * (1.0 - 0.85 * h), 0.0001))
	var hl := _warm * h * 0.55
	if hl > 0.005 and volume > 0:
		_hiss.volume_db = base + linear_to_db(hl)
		if not _hiss.playing:
			_hiss.play(randf() * 0.9)
	elif _hiss.playing:
		_hiss.stop()
	if _eye_mat:
		# magické oko se při přesném naladění rozzáří
		_eye_mat.emission_energy_multiplier = _warm * (0.6 + 1.6 * (1.0 - h))


func _update_visuals() -> void:
	if _needle == null:
		return
	_needle.position.x = lerpf(-DIAL_W, DIAL_W, dial)
	_knob_vol.rotation.z = deg_to_rad(135.0) - knob * deg_to_rad(270.0)
	_knob_tune.rotation.z = -dial * TAU * 3.0
	_glass_mat.emission_energy_multiplier = _warm * 0.9


## Názvy stanic na skleněné stupnici (střídavě nad a pod linkou).
func _build_dial_labels() -> void:
	for i in stations.size():
		var l := Label3D.new()
		var n := String(stations[i]["name"])
		for pre in ["ČRo ", "Rádio ", "Radio "]:
			n = n.trim_prefix(pre)
		l.text = n
		l.font_size = 48
		l.pixel_size = 0.0002
		l.outline_size = 0
		l.modulate = Color(0.3, 0.17, 0.08)
		l.shaded = false
		l.double_sided = false
		l.visibility_range_end = 6.0
		l.position = Vector3(lerpf(-DIAL_W, DIAL_W, station_pos(i)), 0.855 + (0.02 if i % 2 == 0 else -0.02), 0.1238)
		add_child(l)


## Šum mezi stanicemi: 1 s smyčka – filtrovaný šum s občasným praskáním.
static func _hiss_stream() -> AudioStreamWAV:
	if _hiss_wav:
		return _hiss_wav
	var n := PCM_RATE
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 221
	for i in n:
		var w := rng.randf_range(-1.0, 1.0)
		lp = lerpf(lp, w, 0.35)
		var v := lp * 0.55 + w * 0.15
		if rng.randf() < 0.0006:
			v += rng.randf_range(-0.9, 0.9)      # prasknutí
		v *= 0.85 + 0.15 * sin(TAU * 3.0 * i / n)    # mírné vlnění
		data.encode_s16(i * 2, clampi(int(v * 32767.0), -32768, 32767))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = PCM_RATE
	s.stereo = false
	s.data = data
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_end = n
	_hiss_wav = s
	return s


func _update_label() -> void:
	if _label == null:
		return
	if not power:
		_label.text = "Rádio (vypnuto)"
	elif station == "":
		_label.text = "Rádio: šum · hlasitost %d" % volume
	else:
		_label.text = "Rádio: %s · hlasitost %d%s" % [station_info().get("name", ""), volume, "" if status == "" else "\n" + status]


func _stop_all() -> void:
	status = ""
	if _player:
		_player.stop()
		_player.stream = null
	_stop_stream()


# ------------------------------------------------------------------ smyšlené stanice (vyrobená hudba)

func _start_music(id: String) -> void:
	if _music_cache.has(id):
		_player.stream = _music_cache[id]
		_player.play(randf() * 10.0)
		return
	status = "ladím…"
	if _task >= 0:
		return          # už se něco vyrábí – dokončí se v _process a pustí se, co je naladěné
	_task_id = id
	_task_result = null
	_task = WorkerThreadPool.add_task(func(): _task_result = RadioMusic.make(id))


func _poll_task() -> void:
	if _task < 0 or not WorkerThreadPool.is_task_completed(_task):
		return
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	if _task_result:
		_music_cache[_task_id] = _task_result
	if station == _task_id:
		status = ""
		_start_music(station)
		_update_label()
	elif station != "" and not station_info().has("url") and not _music_cache.has(station):
		_start_music(station)      # mezitím se přeladilo na jinou vyráběnou stanici


# ------------------------------------------------------------------ internetové stanice (ffmpeg)

func _start_stream(url: String) -> void:
	status = "ladím…"
	if not OS.has_method("execute_with_pipe"):
		status = "tahle verze Godotu neumí stream"
		return
	_proc = OS.call("execute_with_pipe", "ffmpeg", PackedStringArray(["-nostdin", "-loglevel", "error",
		"-reconnect", "1", "-reconnect_streamed", "1", "-reconnect_delay_max", "5",
		"-i", url, "-vn", "-ac", "1", "-ar", str(PCM_RATE), "-f", "f32le", "pipe:1"]))
	if _proc.is_empty() or not _proc.has("stdio"):
		status = "chybí ffmpeg"
		world.notify(owner_id, "show_message", ["Internetové rádio potřebuje program ffmpeg (sudo dnf install ffmpeg).", 5.0])
		_proc = {}
		return
	_mutex.lock()
	_pcm = PackedFloat32Array()
	_mutex.unlock()
	_reading = true
	_stream_wait = 0.0
	_thread = Thread.new()
	_thread.start(_reader.bind(_proc["stdio"]))
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = PCM_RATE
	gen.buffer_length = 0.6
	_player.stream = gen
	_gen_pb = null


## Vlákno: čte PCM (float32 mono) z roury ffmpeg do vyrovnávací paměti (max. ~6 s).
func _reader(pipe: FileAccess) -> void:
	while _reading:
		var buf := pipe.get_buffer(PCM_RATE / 10 * 4)
		if buf.is_empty():
			break
		var f := buf.to_float32_array()
		_mutex.lock()
		_pcm.append_array(f)
		if _pcm.size() > PCM_RATE * 6:
			_pcm = _pcm.slice(_pcm.size() - PCM_RATE * 3)
		_mutex.unlock()
	_reading = false


func _stop_stream() -> void:
	_reading = false
	if not _proc.is_empty():
		OS.kill(int(_proc.get("pid", 0)))
	if _thread:
		_thread.wait_to_finish()
		_thread = null
	_proc = {}
	_gen_pb = null


func _pump_stream(delta: float) -> void:
	if _proc.is_empty():
		return
	_mutex.lock()
	var have := _pcm.size()
	_mutex.unlock()
	if _gen_pb == null:
		_stream_wait += delta
		if have >= PCM_RATE * 0.8:          # předvyrovnání ~0,8 s
			_player.play()
			_gen_pb = _player.get_stream_playback()
			status = ""
			_update_label()
		elif _stream_wait > 12.0 or (not _reading and have == 0):
			status = "stanice nehraje (internet?)"
			_update_label()
			_stop_stream()
		return
	var n := mini(_gen_pb.get_frames_available(), have)
	if n <= 0:
		return
	_mutex.lock()
	var chunk := _pcm.slice(0, n)
	_pcm = _pcm.slice(n)
	_mutex.unlock()
	var frames := PackedVector2Array()
	frames.resize(n)
	for i in n:
		frames[i] = Vector2(chunk[i], chunk[i])
	_gen_pb.push_buffer(frames)
	if not _reading and have - n <= 0:
		status = "spojení přerušeno"
		_update_label()
		_stop_stream()


func _exit_tree() -> void:
	_stop_stream()
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


# ------------------------------------------------------------------ sousedé

func is_night() -> bool:
	var h := world.clock.hour()
	return h >= NIGHT_FROM or h < NIGHT_TO


## Hluk 0..1 (hlasitost × hlučnost stanice); když rádio ještě ladí / nehraje, je ticho.
func loudness() -> float:
	if not power or volume == 0 or _warm < 0.5:
		return 0.0
	if station == "" or status != "":
		return volume / 10.0 * 0.4             # hlasitý šum lidi taky ruší
	return volume / 10.0 * float(station_info().get("noise", 0.5))


## Do jaké vzdálenosti je rádio slyšet (m) – kdo je blíž, reaguje.
func audible_r() -> float:
	return 0.0 if loudness() <= 0.0 else 8.0 + volume * 6.0


func _process(delta: float) -> void:
	var __t0 := Tests.prof_t0()
	_process_impl(delta)
	Tests.prof_add("radio", __t0)


func _process_impl(delta: float) -> void:
	_poll_task()
	_pump_stream(delta)
	_update_audio(delta)
	_update_visuals()
	if world == null or not world.ready_done:
		return
	var now: float = world.clock.minutes
	if _last_min < 0.0:
		_last_min = now
	var dm := clampf(now - _last_min, 0.0, 24.0 * 60.0)     # herní minuty (i přes spánek)
	if dm < 0.5:
		return
	_last_min = now
	_complain_cool = maxf(_complain_cool - dm, 0.0)
	_rep_cool = maxf(_rep_cool - dm, 0.0)
	_police_cool = maxf(_police_cool - dm, 0.0)
	var night := is_night()
	var loud := loudness()
	var limit := 0.12 if night else 0.42
	if loud > limit:
		anger = minf(anger + (loud - limit) * 6.0 * (3.0 if night else 1.0) * dm, 100.0)
	else:
		anger = maxf(anger - dm * (0.6 if loud < limit * 0.5 else 0.25), 0.0)
		if anger < 15.0:
			_said = 0
	_consequences(night, loud)
	_praise(night, loud, dm)


func _consequences(night: bool, loud: float) -> void:
	if loud <= 0.0:
		return
	var rep: Reputation = world.reputations.get(owner_id)
	# 1) stížnosti
	if (anger >= 25.0 and _said == 0) or (anger >= 50.0 and _said == 1):
		if _complain_cool <= 0.0:
			_said += 1
			_complain_cool = 20.0
			var lines_day := ["Ztlumte to rádio, sousede! Tady se nedá žít!", "Co to je za randál?! Uši mi krvácí!",
				"Hej, vy tam! To je hudba nebo porucha na traktoru?", "Tohle že je muzika? Ztište to, prosím vás!"]
			var lines_night := ["Je noc! Noční klid, sakra! Vypněte to!", "Děti nám spí! Ztlumte to, nebo volám policajty!",
				"Ve dvě ráno metal?! Zítra jdu do práce!"]
			var line: String = (lines_night if night else lines_day).pick_random()
			if not _npc_say(line):
				world.notify(owner_id, "show_message", ["Soused přes plot: „%s“" % line, 4.0])
			_mood_all(-0.08)
	# 2) pověst – „rušil sousedy“
	if anger >= 60.0 and _rep_cool <= 0.0 and rep:
		_rep_cool = 90.0
		if night:
			rep.change(-5.0, "rušil sousedy v noci hlasitou hudbou", "rušení nočního klidu")
		else:
			rep.change(-3.0, "rušil sousedy hlasitou hudbou", "rušení klidu")
		_mood_all(-0.15)
	# 3) v noci policie: pokuta a rádio se ztlumí
	if night and anger >= 85.0 and _police_cool <= 0.0:
		_police_cool = 180.0
		var res: Dictionary = world.commit_offense(owner_id, "ruseni_nocniho_klidu", {"quiet": true})
		var fine := int(res.get("fine", 2000))
		if rep:
			rep.change(-6.0, "sousedi na něj zavolali policii (rušení nočního klidu)", "rušení nočního klidu")
		world.notify(owner_id, "police_banner", ["Sousedi zavolali policii: rušení nočního klidu – pokuta %d Kč. Rádio ztlumeno." % fine, 6.0])
		world.play_sfx(owner_id, "whistle")
		set_volume(owner_id, mini(volume, 2))
		anger = 40.0


## Tichá příjemná hudba přes den: děda (a kolemjdoucí) si pochvalují; jednou za den malé plus v pověsti.
func _praise(night: bool, loud: float, dm: float) -> void:
	if night or loud <= 0.0 or loud > 0.3 or anger > 10.0:
		return
	var deda: Npc = world.npcs.get("deda")
	if deda == null or deda.global_position.distance_to(global_position) > audible_r():
		return
	var per: Persona = deda.get("persona")
	if per:
		per.add_mood(owner_id, 0.004 * dm, world.clock.minutes)
	var day := world.clock.day()
	if _praise_day != day and randf() < 0.02 * dm:
		_praise_day = day
		deda.say(["To je pěkná muzika, synku. Taková se dneska už nehraje.", "Hezky to hraje. Jen to nech, aspoň se mi líp podřimuje.",
			"Tohle poslouchala moje nebožka. Pěkný…"].pick_random(), 5.0)
		var rep: Reputation = world.reputations.get(owner_id)
		if rep:
			rep.change(1.0, "potěšil dědu Vomáčku příjemnou muzikou")


## Stížnost vysloví postava v doslechu (děda nebo nejbližší vesničan). Vrací false, když nikdo není poblíž.
func _npc_say(line: String) -> bool:
	var r := audible_r()
	var best = null                # Npc nebo Villager (obě mají say)
	var bd := r
	var deda: Npc = world.npcs.get("deda")
	if deda and deda.global_position.distance_to(global_position) < bd:
		best = deda
		bd = deda.global_position.distance_to(global_position)
	for v in world.bots_root.get_children():
		if v is Villager and not v.is_knocked():
			var d: float = v.global_position.distance_to(global_position)
			if d < bd:
				bd = d
				best = v
	if best == null:
		return false
	best.say(line, 5.0)
	var p: Player = world.players.get(owner_id)
	if p and p.global_position.distance_to(best.global_position) > 30.0:
		world.notify(owner_id, "show_message", ["%s si stěžuje na tvoje rádio: „%s“" % [
			best.get("persona").display_name() if best.get("persona") else "Soused", line], 4.0])
	return true


func _mood_all(d: float) -> void:
	var r := audible_r()
	for v in world.bots_root.get_children():
		if v is Villager and v.global_position.distance_to(global_position) < r:
			v.persona.add_mood(owner_id, d, world.clock.minutes)
	var deda: Npc = world.npcs.get("deda")
	if deda and deda.get("persona"):
		deda.get("persona").add_mood(owner_id, d, world.clock.minutes)


# ------------------------------------------------------------------ uložení

func to_dict() -> Dictionary:
	return {"station": station, "volume": volume, "anger": anger, "owner": owner_id, "power": power, "dial": dial,
		"knob": knob}


func from_dict(d: Dictionary) -> void:
	volume = clampi(int(d.get("volume", 5)), 0, 10)
	anger = float(d.get("anger", 0.0))
	owner_id = int(d.get("owner", owner_id))
	_apply_volume()
	var st := String(d.get("station", ""))
	if station_info(st).is_empty():
		st = ""
	tune(owner_id, st)
	if d.has("dial"):                      # poloha knoflíků (i vypnuté / mezi stanicemi)
		power = bool(d["power"])
		dial = clampf(float(d["dial"]), 0.0, 1.0)
		knob = clampf(float(d.get("knob", _knob_for(volume) if power else 0.0)), 0.0, 1.0)
		_retune(true)
	_warm = 1.0 if power else 0.0
	_last_min = world.clock.minutes
