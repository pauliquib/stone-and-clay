## M8.18 Zvuková krajina (klient, přepínač `soundscape`): ambientní „emitory“ krajiny kolem posluchače.
##
## Kolem kamery mřížka buněk `CELL` m v okruhu `SCAN_R`; každá buňka má jednou spočtené rysy stanoviště
## (les, okraj lesa, louka, pole, obec, voda, nádrž, niva, podíl jehličnanů – z `Fauna.forest_at/settle_at`, `TreeEco`,
## `Fields`, `Meadows`, `Site.dist_water/hand`, rybníků `Water.ponds`). Zdroje (`data/zvuky_prirody.json`) mají
## aktivitu podle **měsíce, minut od východu / západu slunce** (NOAA jako `Clock.sun_enu`), teploty
## (`World.micro.temp_at`), deště a větru; ve vhodné buňce je teritorium s pravděpodobností `hustota` (stabilní hash),
## takže kos zpívá pořád ze stejné zahrady. Výběr 2×/s (`SELECT_S`): odhad hlasitosti u posluchače (vzdálenost, útlum
## vegetací, maskování větrem) → nejvýš `MAX_VOICES` současných `AudioStreamPlayer3D` (pool, plynulé prolínání,
## nejvýš `MAX_PER_SPECIES` hlasů jednoho druhu) + 2 ambientní 2D vrstvy (šumění korun: listnáče šustí, jehličnany syčí,
## podle `WindField` a olistění z `Phenology`).
## - **Cvrčci a kobylky:** Dolbearův zákon – cvrknutí/min = `DOLBEAR_A` · T − `DOLBEAR_B` (T z `Microclimate.temp_at`
##   v místě zdroje) → za tepla cvrkají rychleji.
## - **Pes a kohout** od domácností (M8.17 `World.households`: pes, slepice).
## - **Realita zvuku:** útlum vzdáleností (3D přehrávač), útlum výšek vegetací (low-pass podle lesa na spojnici –
##   odhad z rysů buněk, bez paprsků), ozvěna v údolí (bus „Priroda“ s `AudioEffectReverb`, mokrý podíl podle `Site.tpi`),
##   vítr maskuje tiché zdroje; v interiéru / v autě se bus ztlumí.
## - **Deník:** první uslyšení druhu (`denik`) do `ZVIRATA`/`NatureLog.hear` (do `HEAR_LOG_R` m).
## Výkon: syntéza zvuků ve vlákně `WorkerThreadPool` při startu (`NatureSfx.synth` → PCM), výběr zdrojů 2×/s
## (bez alokací v `_process` – předalokovaná pole), `_process` jen časuje volání 16 hlasů a prolínání.
## Zdroj modelu: 00_PRINCIPY kap. 8 (ptačí chorál podle druhu, měsíce a minut od východu; Dolbear 1897; žáby na jaře).
class_name Soundscape
extends Node3D

const DATA_PATH := "res://data/zvuky_prirody.json"
const BUS := "Priroda"
## Rysy buňky (index v PackedFloat32Array): stanoviště 0..7 (pořadí = HAB_KEYS), pak podíl jehličnanů, výška terénu.
const HAB_KEYS := ["les", "okraj", "louka", "pole", "obec", "voda", "nadrz", "niva"]
const F_CONIF := 8
const F_Y := 9
const F_N := 10
const TYP_CALL := 0
const TYP_LOOP := 1
const TYP_CHIRP := 2

## M8.D: laditelné (F3 → Příroda/Zvuková krajina), výchozí = chování kroku.
static var CELL := 40.0                 # m – buňka mřížky emitorů
static var SCAN_R := 200.0              # m – okruh buněk kolem posluchače
static var MAX_VOICES := 16             # současných 3D hlasů (pool; změna platí po novém načtení)
static var MAX_PER_SPECIES := 4         # nejvýš hlasů jednoho druhu najednou (pestrost)
static var SELECT_S := 0.5              # s – výběr zdrojů
static var CLASSIFY_PER_TICK := 16      # nových buněk za výběr (rysy se počítají jednou a drží v mezipaměti)
static var CACHE_MAX := 6000            # buněk v mezipaměti, pak se vyprázdní
static var UNIT_SIZE := 10.0            # m – vzdálenost bez útlumu (AudioStreamPlayer3D.unit_size)
static var FADE_IN_DB_S := 30.0         # dB/s – náběh hlasu
static var FADE_OUT_DB_S := 40.0        # dB/s – doběh hlasu
static var MASK_BASE_DB := -34.0        # dB – zdroje s odhadem u posluchače pod touto hranicí se nevybírají
static var WIND_MASK_DB := 1.6          # dB maskování na 1 m/s větru
static var RAMP_IN_MIN := 15.0          # min – náběh aktivity na začátku okna
static var RAMP_OUT_MIN := 30.0         # min – doběh aktivity na konci okna
static var RAIN_FULL := 0.6             # Weather.rain, při kterém platí plný útlum deštěm
static var ACT_MIN := 0.03              # pod touto aktivitou zdroj mlčí
static var INTERVAL_ACT_K := 1.0        # interval volání / max(aktivita, 0,2) ^ k
static var DOLBEAR_A := 7.0             # cvrknutí/min na °C
static var DOLBEAR_B := 30.0            # cvrknutí/min (odečet)
static var CHIRP_MIN := 15.0            # cvrknutí/min – pod tím cvrček mlčí
static var CHIRP_JITTER := 0.06         # ± podíl náhody intervalu cvrkání
static var EDGE_K := 4.0                # okraj lesa = EDGE_K · f · (1 − f)
static var WATER_R := 40.0              # m – rys „voda“ klesá do této vzdálenosti od toku / nádrže
static var POND_R := 35.0               # m – rys „nádrž“ kolem rybníka
static var NIVA_HAND := 3.0             # m nad vodou – niva
static var VEG_LP_OPEN := 16000.0       # Hz – mezní kmitočet bez vegetace
static var VEG_LP_DENSE := 1500.0       # Hz – mezní kmitočet za hustým lesem
static var VEG_LP_DIST := 80.0          # m hustého lesa na spojnici do plného útlumu výšek
static var VEG_DB_100M := 6.0           # dB navíc na 100 m hustého lesa
static var ECHO_TPI_M := 25.0           # m pod okolím (Site.tpi) = plná ozvěna
static var ECHO_WET_MAX := 0.32         # mokrý podíl dozvuku v údolí
static var ECHO_FOREST_WET := 0.08      # dozvuk navíc v lese
static var ECHO_ROOM := 0.8             # velikost „místnosti“ dozvuku
static var ECHO_PREDELAY_MS := 140.0    # ms – zpoždění ozvěny
static var INDOOR_DB := -20.0           # dB busu v interiéru
static var CAR_DB := -12.0              # dB busu v autě
static var CANOPY_DB := -16.0           # dB šumění korun při plném lese a referenčním větru
static var CANOPY_WIND_REF := 6.0       # m/s – referenční vítr pro šumění
static var CANOPY_GUST_K := 0.8         # vliv nárazu (WindField.gust_at) na šumění
static var CANOPY_WINTER_K := 0.3       # listnáče bez listí šustí méně (× hlasitost)
static var CANOPY_SMOOTH := 1.5         # /s – vyhlazení hlasitosti vrstev
static var HOUSE_R := 450.0             # m – domácnosti (pes, kohout) v tomto okruhu
static var HEAR_LOG_R := 70.0           # m – první uslyšení do deníku do této vzdálenosti
static var HEAR_LOG_ACT := 0.25         # … a od této aktivity

static var _data := {}

## Zkompilovaný zdroj (z JSON; při změně v F3 se znovu zkompiluje).
class Src:
	var id := ""
	var name := ""
	var snd := ""
	var typ := 0
	var variants := 1
	var keys := PackedStringArray()     # klíče variant v cache NatureSfx
	var months := PackedFloat32Array()
	var win := PackedFloat32Array()     # po 4: kotva (0 v, 1 z, 2 h), od, do, váha
	var hab := PackedFloat32Array()     # 8 vah stanoviště
	var density := 0.3
	var vol := 0.0
	var range_m := 200.0
	var int_a := 8.0
	var int_b := 20.0
	var h_a := 3.0
	var h_b := 10.0
	var p_a := 1.0
	var p_b := 1.0
	var t_min := -5.0
	var t_full := 3.0
	var rain := 0.6
	var wind_max := 14.0
	var dolbear := 1.0
	var house := ""
	var bloom := false
	var journal := false

class Voice:
	var p: AudioStreamPlayer3D
	var key := -1                       # klíč teritoria (−1 = volný)
	var src := -1
	var base_db := 0.0
	var fade_db := -80.0
	var out := false                    # doznívá
	var next_t := 0.0
	var pitch := 1.0
	var variant := 0
	var temp := 15.0
	var started := false

var world: World
var client: Node
var srcs: Array[Src] = []
var voices: Array[Voice] = []
var _act := PackedFloat32Array()
var _active := PackedInt32Array()
var _cells := {}                        # Vector2i → PackedFloat32Array(F_N)
var _pond_c := PackedVector2Array()     # středy rybníků
var _pond_r := PackedFloat32Array()     # poloměr (polovina úhlopříčky AABB)
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _sel_t := 0.0
var _now := 0.0
var _bus := -1
var _wet := -1.0
var _bus_db := 0.0
var _rustle: AudioStreamPlayer
var _hiss: AudioStreamPlayer
var _rustle_db := -80.0
var _hiss_db := -80.0
var _rustle_target := -80.0
var _hiss_target := -80.0
var _sun_jd := -1
var _rise := 360.0
var _set := 1200.0
var _on := false
# výběr – předalokovaná pole (bez alokací za běhu)
var _top_n := 0
var _top_score := PackedFloat32Array()
var _top_src := PackedInt32Array()
var _top_key := PackedInt64Array()
var _top_pos := PackedVector3Array()
var _top_lp := PackedFloat32Array()
var _top_veg := PackedFloat32Array()
# syntéza ve vlákně
var _task := -1
var _mutex := Mutex.new()
var _done: Array = []
var _abort := false
var _warm_left := 0


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.get_file_as_string(DATA_PATH)
		var d = JSON.parse_string(f) if f != "" else null
		_data = d if d is Dictionary else {"zdroje": []}
	return _data


func setup(w: World, c: Node) -> void:
	world = w
	client = c
	name = "ZvukovaKrajina"
	_rng.seed = 1818
	_compile()
	_make_bus()
	_make_pool()
	_index_ponds()
	_start_synth()
	if DevTune.hub() != null:
		DevTune.hub().changed.connect(_on_tune)


func _on_tune(id: String, _v: Variant) -> void:
	if id.begins_with("sound.src."):
		_compile()


func enabled() -> bool:
	return world != null and world.realism_on("soundscape")


# ------------------------------------------------------------------ data

func _compile() -> void:
	srcs.clear()
	for e in data().get("zdroje", []):
		var d: Dictionary = e
		var s := Src.new()
		s.id = String(d.get("id", ""))
		s.name = String(d.get("nazev", s.id))
		s.snd = String(d.get("zvuk", ""))
		var typ := String(d.get("typ", "vola"))
		s.typ = TYP_LOOP if typ == "smycka" else (TYP_CHIRP if typ == "cvrcek" else TYP_CALL)
		s.variants = maxi(int(d.get("varianty", 1)), 1) if NatureSfx.SYNTH_LOOPED.has(s.snd) else 1
		for v in s.variants:
			s.keys.append(NatureSfx.variant_key(s.snd, v))
		var mo: Array = d.get("mesice", [])
		s.months.resize(12)
		for i in 12:
			s.months[i] = float(mo[i]) if i < mo.size() else 0.0
		for wnd in d.get("okna", []):
			var wa: Array = wnd
			if wa.size() < 4:
				continue
			var an := String(wa[0])
			s.win.append(0.0 if an == "v" else (1.0 if an == "z" else 2.0))
			s.win.append(float(wa[1]))
			s.win.append(float(wa[2]))
			s.win.append(float(wa[3]))
		var hb: Dictionary = d.get("stanoviste", {})
		s.hab.resize(HAB_KEYS.size())
		for i in HAB_KEYS.size():
			s.hab[i] = float(hb.get(HAB_KEYS[i], 0.0))
		s.density = float(d.get("hustota", 0.3))
		s.vol = float(d.get("hlasitost", 0.0))
		s.range_m = float(d.get("dosah", 200.0))
		var iv: Array = d.get("interval", [8, 20])
		s.int_a = float(iv[0])
		s.int_b = maxf(float(iv[1]), s.int_a)
		var hv: Array = d.get("vyska", [3, 10])
		s.h_a = float(hv[0])
		s.h_b = float(hv[1])
		var pv: Array = d.get("ladeni", [1, 1])
		s.p_a = float(pv[0])
		s.p_b = float(pv[1])
		s.t_min = float(d.get("t_min", -5.0))
		s.t_full = float(d.get("t_plne", 3.0))
		s.rain = float(d.get("dest", 0.6))
		s.wind_max = maxf(float(d.get("vitr", 14.0)), 0.5)
		s.dolbear = float(d.get("dolbear", 1.0))
		s.house = String(d.get("domy", ""))
		s.bloom = bool(d.get("kvet", false))
		s.journal = bool(d.get("denik", false))
		srcs.append(s)
		if not NatureSfx.SYNTH_LOOPED.has(s.snd):
			NatureSfx.get_stream(s.snd)          # staré zvuky (kos, vrána, káně) – malé, hned
	_act.resize(srcs.size())
	_act.fill(0.0)


func _make_bus() -> void:
	_bus = AudioServer.get_bus_index(BUS)
	if _bus < 0:
		AudioServer.add_bus()
		_bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(_bus, BUS)
		AudioServer.set_bus_send(_bus, "Master")
		var rv := AudioEffectReverb.new()
		rv.room_size = ECHO_ROOM
		rv.damping = 0.5
		rv.predelay_msec = ECHO_PREDELAY_MS
		rv.predelay_feedback = 0.35
		rv.dry = 1.0
		rv.wet = 0.0
		AudioServer.add_bus_effect(_bus, rv)


func _make_pool() -> void:
	for i in MAX_VOICES:
		var v := Voice.new()
		var p := AudioStreamPlayer3D.new()
		p.unit_size = UNIT_SIZE
		p.max_distance = 600.0
		p.bus = BUS
		p.volume_db = -80.0
		p.attenuation_filter_cutoff_hz = VEG_LP_OPEN
		p.top_level = true
		add_child(p)
		v.p = p
		voices.append(v)
	_top_score.resize(MAX_VOICES)
	_top_src.resize(MAX_VOICES)
	_top_key.resize(MAX_VOICES)
	_top_pos.resize(MAX_VOICES)
	_top_lp.resize(MAX_VOICES)
	_top_veg.resize(MAX_VOICES)
	_rustle = _layer("canopy_rustle")
	_hiss = _layer("canopy_hiss")


func _layer(snd: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = BUS
	p.volume_db = -80.0
	p.set_meta("snd", snd)
	add_child(p)
	return p


func _index_ponds() -> void:
	var wa: Water = world.water if world != null else null
	if wa == null:
		return
	for pd in wa.ponds:
		var r: Rect2 = pd["aabb"]
		_pond_c.append(r.get_center())
		_pond_r.append(r.size.length() * 0.5)


## Syntéza všech variant ve vlákně (bez záseku); hotová PCM data přebírá `_take_done` při výběru.
func _start_synth() -> void:
	var jobs: Array = []
	var seen := {}
	for s in srcs:
		if not NatureSfx.SYNTH_LOOPED.has(s.snd):
			continue
		for v in s.variants:
			var k := NatureSfx.variant_key(s.snd, v)
			if not seen.has(k) and not NatureSfx.has_stream(k):
				seen[k] = true
				jobs.append([s.snd, v, k, bool(NatureSfx.SYNTH_LOOPED[s.snd])])
	for snd in ["canopy_rustle", "canopy_hiss"]:
		if not NatureSfx.has_stream(snd):
			jobs.append([snd, 0, snd, true])
	_warm_left = jobs.size()
	if jobs.is_empty():
		return
	_task = WorkerThreadPool.add_task(_synth_jobs.bind(jobs), false, "Soundscape: syntéza zvuků")


func _synth_jobs(jobs: Array) -> void:
	for j in jobs:
		if _abort:
			return
		var pcm := NatureSfx.pcm16(NatureSfx.synth(String(j[0]), int(j[1])))
		_mutex.lock()
		_done.append([j[2], pcm, j[3]])
		_mutex.unlock()


func _take_done() -> void:
	if _warm_left <= 0:
		return
	_mutex.lock()
	for d in _done:
		NatureSfx.put_pcm(String(d[0]), d[1], bool(d[2]))
		_warm_left -= 1
	_done.clear()
	_mutex.unlock()
	if _warm_left <= 0 and _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


func _exit_tree() -> void:
	_abort = true
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


# ------------------------------------------------------------------ čas a slunce

## Východ a západ slunce dne (minuty místního času) – NOAA jako `Clock.sun_enu`, drží se na den.
func _sun_times(c: Clock) -> void:
	var j := c.jd()
	if j == _sun_jd:
		return
	_sun_jd = j
	var doy := c.day_of_year()
	var tz := float(c.utc_offset())
	var g := TAU / 365.0 * (doy - 1.0)
	var eqt := 229.18 * (0.000075 + 0.001868 * cos(g) - 0.032077 * sin(g) - 0.014615 * cos(2.0 * g) - 0.040849 * sin(2.0 * g))
	var decl := 0.006918 - 0.399912 * cos(g) + 0.070257 * sin(g) - 0.006758 * cos(2.0 * g) + 0.000907 * sin(2.0 * g) \
		- 0.002697 * cos(3.0 * g) + 0.00148 * sin(3.0 * g)
	var lat := deg_to_rad(Clock.LAT)
	var ch := cos(deg_to_rad(90.833)) / (cos(lat) * cos(decl)) - tan(lat) * tan(decl)
	var ha := rad_to_deg(acos(clampf(ch, -1.0, 1.0)))
	var noon := 720.0 - 4.0 * Clock.LON - eqt + 60.0 * tz
	_rise = noon - 4.0 * ha
	_set = noon + 4.0 * ha


## Minuty od východu / západu slunce (−720..720) – pro F2 a ladění.
func minutes_from_sunrise() -> float:
	return _wrap(fposmod(world.clock.minutes, 1440.0) - _rise) if world != null else 0.0


static func _wrap(m: float) -> float:
	return fposmod(m + 720.0, 1440.0) - 720.0


func _window(s: Src, mday: float) -> float:
	var best := 0.0
	var i := 0
	while i + 3 < s.win.size():
		var an := s.win[i]
		var od := s.win[i + 1]
		var do_ := s.win[i + 2]
		var x := 0.0
		var ri := RAMP_IN_MIN
		var ro := RAMP_OUT_MIN
		if an < 0.5:
			x = _wrap(mday - _rise)
		elif an < 1.5:
			x = _wrap(mday - _set)
		else:
			x = mday / 60.0
			if x < od:
				x += 24.0
			ri /= 60.0
			ro /= 60.0
		if x >= od and x <= do_:
			var f := minf(clampf((x - od) / maxf(ri, 0.001), 0.0, 1.0), clampf((do_ - x) / maxf(ro, 0.001), 0.0, 1.0))
			best = maxf(best, f * s.win[i + 3])
		i += 4
	return best


# ------------------------------------------------------------------ rysy buněk

## Rysy buňky (PackedFloat32Array F_N) nebo prázdné pole, když ještě nejsou spočtené.
func cell_feat(c: Vector2i) -> PackedFloat32Array:
	return _cells.get(c, PackedFloat32Array())


func _classify(c: Vector2i) -> PackedFloat32Array:
	var x := (c.x + 0.5) * CELL
	var z := (c.y + 0.5) * CELL
	var f := PackedFloat32Array()
	f.resize(F_N)
	var fa: Fauna = world.fauna
	var te: TreeEco = world.tree_eco
	var forest := 0.0
	var settle := 0.0
	if fa != null:
		forest = fa.forest_at(x, z)
		settle = fa.settle_at(x, z)
	if te != null:
		forest = maxf(forest, te.canopy_at(x, z))
	forest = clampf(forest, 0.0, 1.0)
	var field := 1.0 if world.fields != null and world.fields.field_at(x, z) > 0 else 0.0
	var meadow := 0.0
	var mw: Meadows = world.meadows
	if mw != null and mw.index_at(x, z) >= 0:
		meadow = 1.0
	else:
		meadow = (1.0 - forest) * (1.0 - settle) * (1.0 - field) * 0.6
	var dw := 9999.0
	var hand := 50.0
	var st: Site = world.site
	if st != null:
		dw = st.dist_water(x, z)
		hand = st.hand(x, z)
	var pond := 0.0
	for i in _pond_c.size():
		var d := _pond_c[i].distance_to(Vector2(x, z)) - _pond_r[i]
		pond = maxf(pond, 1.0 - clampf(d / POND_R, 0.0, 1.0))
	if dw > 9000.0 and world.water != null:
		var ns: Array = world.water.nearest_stream(Vector3(x, 0.0, z), WATER_R)
		if not ns.is_empty():
			dw = Vector2((ns[0] as Vector3).x, (ns[0] as Vector3).z).distance_to(Vector2(x, z))
	var water := maxf(1.0 - clampf(dw / WATER_R, 0.0, 1.0), pond)
	f[0] = forest
	f[1] = clampf(EDGE_K * forest * (1.0 - forest), 0.0, 1.0)
	f[2] = meadow
	f[3] = field
	f[4] = settle
	f[5] = water
	f[6] = pond
	f[7] = forest * (1.0 - clampf(hand / NIVA_HAND, 0.0, 1.0)) if st != null else 0.0
	var conif := 0.0
	if te != null and forest > 0.15:
		var sn := te.species_near(Vector3(x, 0.0, z), CELL * 0.6)
		for id in sn:
			if String(te.species_info(String(id)).get("typ", "")) == "jehlicnan":
				conif += float(sn[id])
	f[F_CONIF] = conif
	f[F_Y] = world.terrain.height_at(x, z) if world.terrain != null else 0.0
	return f


# ------------------------------------------------------------------ hlavní smyčka

func _process(delta: float) -> void:
	if world == null:
		return
	var __t0 := Tests.prof_t0()
	_now += delta
	var on := enabled()
	if on != _on:
		_on = on
		if not on:
			_silence_all()
	_sel_t -= delta
	if _sel_t <= 0.0:
		_sel_t = SELECT_S
		_take_done()
		if _on:
			_select()
	if _on:
		_run_voices(delta)
		_run_layers(delta)
	Tests.prof_add("soundscape", __t0)


func _silence_all() -> void:
	for v in voices:
		v.p.stop()
		v.key = -1
		v.src = -1
		v.out = false
		v.fade_db = -80.0
	_rustle.stop()
	_hiss.stop()
	_rustle_db = -80.0
	_hiss_db = -80.0


func _listener() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		return cam.global_position
	var p: Player = client.get("player") if client != null else null
	return p.global_position if p != null else Vector3.ZERO


func _wind_now(_pos: Vector3) -> float:
	var wf: WindField = world.wind_field
	if wf != null and wf.enabled():
		return wf.speed()
	return world.weather.wind if world.weather != null else 2.0


func _temp_at(pos: Vector3) -> float:
	var mc: Microclimate = world.micro
	if mc != null:
		return mc.temp_at(pos)
	return world.weather.temp if world.weather != null else 12.0


## Výběr zdrojů (2×/s): aktivita druhů → kandidáti z buněk a domácností → nejhlasitější do poolu.
func _select() -> void:
	var c: Clock = world.clock
	if c == null:
		return
	_sun_times(c)
	var L := _listener()
	var mday := fposmod(c.minutes, 1440.0)
	var month := clampi(c.month(), 1, 12)
	var T := _temp_at(L)
	var rain := clampf((world.weather.rain if world.weather != null else 0.0) / RAIN_FULL, 0.0, 1.0)
	var wind := _wind_now(L)
	var bloom := -1.0
	_active.clear()
	for i in srcs.size():
		var s := srcs[i]
		var a := s.months[month - 1]
		if a > 0.0:
			a *= _window(s, mday)
		if a > 0.0:
			if s.t_full > s.t_min:
				a *= clampf((T - s.t_min) / (s.t_full - s.t_min), 0.0, 1.0)
			a *= 1.0 - s.rain * rain
			a *= clampf(1.0 - wind / s.wind_max, 0.0, 1.0)
		if a > 0.0 and s.bloom:
			if bloom < 0.0:
				bloom = _bloom(L, c)
			a *= bloom
		if a > 0.0 and s.typ == TYP_CHIRP and DOLBEAR_A * T - DOLBEAR_B < CHIRP_MIN:
			a = 0.0
		_act[i] = a
		if a >= ACT_MIN:
			_active.append(i)
	var mask := MASK_BASE_DB + WIND_MASK_DB * wind
	_top_n = 0
	if not _active.is_empty():
		_scan_cells(L, mask)
		_scan_houses(L, mask)
	_assign(L)
	_update_bus(L)
	_update_layers(L, wind)


func _bloom(L: Vector3, c: Clock) -> float:
	var ph: Phenology = world.phenology
	if ph != null:
		return ph.bees_bloom(L)
	return Seasons.bloom(c.day_of_year())


func _scan_cells(L: Vector3, mask: float) -> void:
	var r := int(ceil(SCAN_R / CELL))
	var c0 := Vector2i(floori(L.x / CELL), floori(L.z / CELL))
	var budget := CLASSIFY_PER_TICK
	if _cells.size() > CACHE_MAX:
		_cells.clear()
	var lf := _forest_near(c0)
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			if dx * dx + dz * dz > r * r:
				continue
			var cc := c0 + Vector2i(dx, dz)
			var f: PackedFloat32Array = _cells.get(cc, PackedFloat32Array())
			if f.is_empty():
				if budget <= 0:
					continue
				budget -= 1
				f = _classify(cc)
				_cells[cc] = f
			for k in _active.size():
				var si := _active[k]
				var s := srcs[si]
				if s.house != "":
					continue
				var w := 0.0
				for h in HAB_KEYS.size():
					w = maxf(w, s.hab[h] * f[h])
				if w <= 0.02:
					continue
				var hsh := _hash01(cc.x, cc.y, si)
				if hsh > s.density * w:
					continue
				var ox := (_hash01(cc.x, cc.y, si + 97) - 0.5) * (CELL - 8.0)
				var oz := (_hash01(cc.x, cc.y, si + 193) - 0.5) * (CELL - 8.0)
				var hy := lerpf(s.h_a, s.h_b, _hash01(cc.x, cc.y, si + 389))
				var pos := Vector3((cc.x + 0.5) * CELL + ox, f[F_Y] + hy, (cc.y + 0.5) * CELL + oz)
				_candidate(si, (cc.x * 73856093) ^ (cc.y * 19349663) ^ (si * 83492791), pos, L, mask, w, (lf + f[0]) * 0.5)


func _scan_houses(L: Vector3, mask: float) -> void:
	var hs: Households = world.households
	if hs == null or not hs.built:
		return
	for k in _active.size():
		var si := _active[k]
		var s := srcs[si]
		if s.house == "":
			continue
		var flag := "dog" if s.house == "pes" else "hens"
		for i in hs.hh.size():
			var house: Dictionary = hs.hh[i]
			if not bool(house.get(flag, false)):
				continue
			var pos: Vector3 = house["pos"]
			if absf(pos.x - L.x) > HOUSE_R or absf(pos.z - L.z) > HOUSE_R:
				continue
			if _hash01(i, 7, si) > s.density:
				continue
			_candidate(si, 1000000007 + i * 131 + si, pos + Vector3(0.0, lerpf(s.h_a, s.h_b, 0.5), 0.0), L, mask, 1.0, 0.0)


## Zařadí kandidáta do žebříčku nejhlasitějších (insertion, nejvýš MAX_VOICES, nejvýš MAX_PER_SPECIES druhu).
func _candidate(si: int, key: int, pos: Vector3, L: Vector3, mask: float, w: float, forest: float) -> void:
	var s := srcs[si]
	var d := pos.distance_to(L)
	if d > s.range_m:
		return
	var veg := clampf(forest, 0.0, 1.0)
	var veg_db := VEG_DB_100M * veg * d / 100.0
	var score := s.vol + 20.0 * log(UNIT_SIZE / maxf(d, 1.0)) / log(10.0) + 10.0 * log(maxf(_act[si] * w, 0.001)) / log(10.0) - veg_db
	if score < mask:
		return
	var n := _top_n
	var same := 0
	var worst_same := -1
	for i in n:
		if _top_src[i] == si:
			same += 1
			worst_same = i
	if same >= MAX_PER_SPECIES:
		if score <= _top_score[worst_same]:
			return
		_remove_top(worst_same)
		n = _top_n
	if n >= _top_score.size():
		if score <= _top_score[n - 1]:
			return
		n -= 1
	var at := n
	while at > 0 and _top_score[at - 1] < score:
		at -= 1
	var j := n
	while j > at:
		_top_score[j] = _top_score[j - 1]
		_top_src[j] = _top_src[j - 1]
		_top_key[j] = _top_key[j - 1]
		_top_pos[j] = _top_pos[j - 1]
		_top_lp[j] = _top_lp[j - 1]
		_top_veg[j] = _top_veg[j - 1]
		j -= 1
	_top_score[at] = score
	_top_src[at] = si
	_top_key[at] = key
	_top_pos[at] = pos
	_top_lp[at] = lerpf(VEG_LP_OPEN, VEG_LP_DENSE, clampf(veg * d / VEG_LP_DIST, 0.0, 1.0))
	_top_veg[at] = veg_db
	_top_n = n + 1


func _remove_top(i: int) -> void:
	for j in range(i, _top_n - 1):
		_top_score[j] = _top_score[j + 1]
		_top_src[j] = _top_src[j + 1]
		_top_key[j] = _top_key[j + 1]
		_top_pos[j] = _top_pos[j + 1]
		_top_lp[j] = _top_lp[j + 1]
		_top_veg[j] = _top_veg[j + 1]
	_top_n -= 1


## Les kolem posluchače (3×3 buňky) – průměr s lesem buňky zdroje = odhad vegetace na spojnici.
func _forest_near(c0: Vector2i) -> float:
	var s := 0.0
	var n := 0
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var f: PackedFloat32Array = _cells.get(c0 + Vector2i(dx, dz), PackedFloat32Array())
			if not f.is_empty():
				s += f[0]
				n += 1
	if n == 0:
		return world.fauna.forest_at(c0.x * CELL, c0.y * CELL) if world.fauna != null else 0.0
	return s / n


## Hlasy: ponechá ty, jejichž teritorium zůstalo v žebříčku; ostatní doznívají; nová teritoria dostanou volné hlasy.
func _assign(L: Vector3) -> void:
	for v in voices:
		if v.key < 0:
			continue
		var found := -1
		for i in _top_n:
			if _top_key[i] == v.key:
				found = i
				break
		if found < 0:
			v.out = true
			continue
		v.out = false
		_apply_voice(v, found)
		_top_key[found] = -1               # obsazeno
	for i in _top_n:
		if _top_key[i] == -1:
			continue
		var free: Voice = null
		for v in voices:
			if v.key < 0:
				free = v
				break
		if free == null:
			break
		var s := srcs[_top_src[i]]
		free.key = _top_key[i]
		free.src = _top_src[i]
		free.out = false
		free.started = false
		free.fade_db = -60.0
		var h := _hash01(int(_top_pos[i].x), int(_top_pos[i].z), free.src + 11)
		free.pitch = lerpf(s.p_a, s.p_b, h)
		free.variant = int(h * 997.0) % s.variants
		free.p.global_position = _top_pos[i]
		free.next_t = _now + _rng.randf_range(0.0, maxf(s.int_a, 1.0))
		_apply_voice(free, i)


func _apply_voice(v: Voice, i: int) -> void:
	var s := srcs[v.src]
	v.base_db = s.vol + 10.0 * log(maxf(_act[v.src], 0.001)) / log(10.0) * 0.5 - _top_veg[i]
	v.p.attenuation_filter_cutoff_hz = _top_lp[i]
	v.p.max_distance = s.range_m
	if s.typ == TYP_CHIRP:
		v.temp = _temp_at(v.p.global_position)


func _run_voices(delta: float) -> void:
	for v in voices:
		if v.key < 0:
			continue
		var s := srcs[v.src]
		if v.out:
			v.fade_db -= FADE_OUT_DB_S * delta
			if v.fade_db <= -60.0:
				v.p.stop()
				v.key = -1
				v.src = -1
				v.out = false
				continue
		else:
			v.fade_db = minf(v.fade_db + FADE_IN_DB_S * delta, 0.0)
		v.p.volume_db = v.base_db + v.fade_db
		if v.out:
			continue
		var key: String = s.keys[v.variant]
		if s.typ == TYP_LOOP:
			if not v.started and NatureSfx.has_stream(key):
				v.p.stream = NatureSfx.get_variant(s.snd, v.variant)
				v.p.pitch_scale = v.pitch
				v.p.play(_rng.randf() * 2.0)
				v.started = true
				_heard(v, s)
			continue
		if _now < v.next_t:
			continue
		if not NatureSfx.has_stream(key):
			v.next_t = _now + 1.0
			continue
		if v.p.stream != NatureSfx.get_variant(s.snd, v.variant):
			v.p.stream = NatureSfx.get_variant(s.snd, v.variant)
		v.p.pitch_scale = v.pitch
		v.p.play()
		if s.typ == TYP_CHIRP:
			var cpm := maxf((DOLBEAR_A * v.temp - DOLBEAR_B) * s.dolbear, CHIRP_MIN * 0.5)
			v.next_t = _now + 60.0 / cpm * (1.0 + _rng.randf_range(-CHIRP_JITTER, CHIRP_JITTER))
		else:
			var a := maxf(_act[v.src], 0.2)
			v.next_t = _now + _rng.randf_range(s.int_a, s.int_b) / pow(a, INTERVAL_ACT_K)
		if not v.started:
			v.started = true
			_heard(v, s)


## První uslyšení druhu → deník pozorování (blízko a za dostatečné aktivity).
func _heard(v: Voice, s: Src) -> void:
	if not s.journal or world.nature_log == null or _act[v.src] < HEAR_LOG_ACT:
		return
	var p: Player = client.get("player") if client != null else null
	if p == null or p.car != null or p.inside != "":
		return
	if p.global_position.distance_to(v.p.global_position) > HEAR_LOG_R:
		return
	world.nature_log.hear(p, s.id, s.name)


# ------------------------------------------------------------------ bus, ozvěna, šumění korun

func _update_bus(L: Vector3) -> void:
	if _bus < 0:
		return
	var p: Player = client.get("player") if client != null else null
	var db := 0.0
	if p != null:
		if p.inside != "":
			db = INDOOR_DB
		elif p.car != null:
			db = CAR_DB
	if absf(db - _bus_db) > 0.1:
		_bus_db = db
		AudioServer.set_bus_volume_db(_bus, db)
	var tpi := world.site.tpi(L.x, L.z) if world.site != null else 0.0
	var c0 := Vector2i(floori(L.x / CELL), floori(L.z / CELL))
	var wet := clampf(-tpi / ECHO_TPI_M, 0.0, 1.0) * ECHO_WET_MAX + _forest_near(c0) * ECHO_FOREST_WET
	if absf(wet - _wet) > 0.01 and AudioServer.get_bus_effect_count(_bus) > 0:
		_wet = wet
		var rv := AudioServer.get_bus_effect(_bus, 0) as AudioEffectReverb
		if rv != null:
			rv.wet = wet
			rv.room_size = ECHO_ROOM
			rv.predelay_msec = ECHO_PREDELAY_MS


func _update_layers(L: Vector3, wind: float) -> void:
	var c0 := Vector2i(floori(L.x / CELL), floori(L.z / CELL))
	var forest := _forest_near(c0)
	var conif := 0.0
	var n := 0
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var f: PackedFloat32Array = _cells.get(c0 + Vector2i(dx, dz), PackedFloat32Array())
			if not f.is_empty():
				conif += f[F_CONIF]
				n += 1
	conif = conif / n if n > 0 else 0.3
	var gust := 0.5
	var wf: WindField = world.wind_field
	if wf != null and wf.enabled():
		gust = wf.gust_at(L)
	var k := clampf(wind / CANOPY_WIND_REF * (1.0 + CANOPY_GUST_K * (gust - 0.5)), 0.0, 1.6)
	var leaf := 1.0
	var ph: Phenology = world.phenology
	if ph != null:
		leaf = lerpf(CANOPY_WINTER_K, 1.0, ph.foliage("buk", L))
	else:
		var m := world.clock.month()
		leaf = 1.0 if m >= 5 and m <= 10 else CANOPY_WINTER_K
	_rustle_target = CANOPY_DB + 20.0 * log(maxf(forest * (1.0 - conif) * leaf * k, 0.0001)) / log(10.0)
	_hiss_target = CANOPY_DB + 20.0 * log(maxf(forest * conif * k, 0.0001)) / log(10.0)


func _run_layers(delta: float) -> void:
	var a := clampf(CANOPY_SMOOTH * delta, 0.0, 1.0)
	_rustle_db = lerpf(_rustle_db, _rustle_target, a)
	_hiss_db = lerpf(_hiss_db, _hiss_target, a)
	_layer_run(_rustle, _rustle_db)
	_layer_run(_hiss, _hiss_db)


func _layer_run(p: AudioStreamPlayer, db: float) -> void:
	if db < -55.0:
		if p.playing:
			p.stop()
		return
	p.volume_db = db
	if not p.playing:
		var snd := String(p.get_meta("snd"))
		if not NatureSfx.has_stream(snd):
			return
		p.stream = NatureSfx.get_stream(snd)
		p.play(_rng.randf() * 3.0)


# ------------------------------------------------------------------ pomocné

static func _hash01(a: int, b: int, c: int) -> float:
	var h := (a * 73856093) ^ (b * 19349663) ^ (c * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFFFF) / 16777216.0


## Text pro F2 / ladění: aktivní zdroje a hlasy.
func debug_text() -> String:
	var t := "Zvuková krajina: východ %02d:%02d, západ %02d:%02d, od východu %+.0f min\n" % [
		int(_rise / 60.0), int(fposmod(_rise, 60.0)), int(_set / 60.0), int(fposmod(_set, 60.0)), minutes_from_sunrise()]
	for i in _active:
		t += "  %s %.2f\n" % [srcs[i].name, _act[i]]
	var n := 0
	for v in voices:
		if v.key >= 0:
			n += 1
	return t + "  hlasů: %d / %d\n" % [n, voices.size()]
