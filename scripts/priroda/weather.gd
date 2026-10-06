## Počasí – simulace ve světě (v multiplayeru na serveru; klientům stačí poslat pár čísel ze `state()`).
##
## Počasí je řetěz „situací“ (jasno, polojasno, oblačno, zataženo, mlha, přeháňky, déšť, bouřka), každá
## trvá několik herních hodin a pak přejde do jiné podle tabulky NEXT. Pravděpodobnosti upravuje roční
## období (Seasons: srážkové dny, podíl bouřek) a denní doba (mlha ráno, bouřky odpoledne).
## Spojité veličiny (oblačnost, déšť, mlha, vítr, teplota) se k cílům situace blíží plynule; z nich
## vyplývá sněhová pokrývka a mokrý povrch. Při teplotě pod ~1 °C padá místo deště sníh.
##
## Úpravy: tabulky TYPES a NEXT níže; klima po měsících je v Seasons.
## Ladicí parametr --weather=dest (jasno, polojasno, oblacno, zatazeno, mlha, prehanky, dest, bourka, snih)
class_name Weather
extends Node

signal kind_changed(kind: String)
## Blesk: poloha ve světě (klienti bliknou oblohou a se zpožděním vzdálenost / 343 m/s zahřmí).
signal lightning(pos: Vector3)

## cloud: oblačnost 0..1, rain: intenzita srážek 0..1 (1 ≈ 25 mm/h), fog: mlha 0..1, wind: m/s,
## hours: [min, max] trvání situace (herní hodiny), showers: srážky přerušované, storm: blesky.
const TYPES := {
	"jasno": {"name": "Jasno", "cloud": 0.04, "rain": 0.0, "fog": 0.0, "wind": 2.0, "hours": [6.0, 30.0]},
	"polojasno": {"name": "Polojasno", "cloud": 0.35, "rain": 0.0, "fog": 0.0, "wind": 3.0, "hours": [4.0, 18.0]},
	"oblacno": {"name": "Oblačno", "cloud": 0.7, "rain": 0.0, "fog": 0.0, "wind": 4.0, "hours": [3.0, 14.0]},
	"zatazeno": {"name": "Zataženo", "cloud": 0.97, "rain": 0.0, "fog": 0.1, "wind": 3.5, "hours": [3.0, 16.0]},
	"mlha": {"name": "Mlha", "cloud": 0.85, "rain": 0.0, "fog": 1.0, "wind": 0.6, "hours": [2.0, 8.0]},
	"prehanky": {"name": "Přeháňky", "cloud": 0.72, "rain": 0.45, "fog": 0.0, "wind": 5.5, "hours": [2.0, 8.0], "showers": true},
	"dest": {"name": "Déšť", "cloud": 1.0, "rain": 0.4, "fog": 0.25, "wind": 4.5, "hours": [2.0, 12.0]},
	"bourka": {"name": "Bouřka", "cloud": 1.0, "rain": 0.95, "fog": 0.1, "wind": 12.0, "hours": [0.7, 2.5], "storm": true, "showers": true},
}
## Přechody mezi situacemi (relativní váhy, dál je násobí roční období a denní doba).
const NEXT := {
	"jasno": {"jasno": 2.0, "polojasno": 5.0, "mlha": 1.0},
	"polojasno": {"jasno": 3.0, "polojasno": 1.0, "oblacno": 4.0, "prehanky": 1.0, "bourka": 1.0},
	"oblacno": {"polojasno": 3.0, "zatazeno": 3.0, "prehanky": 2.0, "dest": 1.5, "bourka": 1.0},
	"zatazeno": {"oblacno": 3.0, "dest": 4.0, "mlha": 1.0, "zatazeno": 1.0},
	"mlha": {"polojasno": 3.0, "zatazeno": 3.0, "jasno": 1.0},
	"prehanky": {"oblacno": 3.0, "polojasno": 2.0, "dest": 1.0},
	"dest": {"zatazeno": 3.0, "oblacno": 2.0, "prehanky": 2.0},
	"bourka": {"prehanky": 2.0, "oblacno": 3.0, "polojasno": 2.0},
}
## Časové konstanty přiblížení k cíli (herní hodiny).
const TAU_CLOUD := 0.8
const TAU_RAIN := 0.25
const TAU_FOG := 0.7
const TAU_WIND := 0.4
const TAU_TEMP := 1.2
const SNOW_BELOW := 0.8                # °C – pod touto teplotou sněží
const RAIN_MM_H := 25.0                # rain = 1 odpovídá lijáku 25 mm/h

## Přilnavost povrchu podle počasí – jediná tabulka, čte ji auto (pneu), chodec (podrážky) i kůň
## (kopyta); každý ji u sebe zjemní svým podílem klouzavosti. Hodnoty = násobek suchého asfaltu.
const SURF_GRIP := {"asfalt": 1.0, "sterk": 0.78, "teren": 0.68}
const GRIP_WET := 0.7                  # mokrá vozovka (wetness = 1)
const GRIP_SNOW := 0.35                # uježděný sníh (snow_cover = 1)
const GRIP_ICE := 0.15                 # náledí (wetness pod nulou)
const GRIP_MUD := 0.5                  # rozmočená hlína na terénu (wetness = 1)
const ICE_WET := 0.25                  # kolik wetness stačí k náledí

var clock: Clock
var north_deg := 78.37
var rng := RandomNumberGenerator.new()

var kind := "polojasno"
var kind_left_h := 6.0                 # zbývá herních hodin situace
var forced := false                    # --weather: situace se nemění
var forced_frost := false              # vynucené sněžení / náledí: teplota se drží pod nulou
var forced_temp := NAN                 # ladění (F2 → Počasí → Teplota): pevná teplota °C, NAN = podle klimatu

# --- stav (to posílá server klientům)
var cloud := 0.3
var rain := 0.0                        # intenzita srážek (déšť i sníh)
var fog := 0.0
var wind := 2.0                        # m/s
var wind_bearing := 250.0              # odkud vane (° od severu) – převládá západní proudění
var temp := 12.0                       # °C (2 m nad zemí)
var snow_cover := 0.0                  # sníh na zemi 0..1 (1 ≈ 10 cm a víc)
var wetness := 0.0                     # mokrý povrch 0..1
var storm := 0.0                       # síla bouřky 0..1 (blesky)
var rain_recent := 0.0                 # vlhko z posledních dnů 0..1 (roste deštěm, klesá ~0,5 za den) – hřiby

## Autorita nad počasím: true = simuluje se tady (singleplayer, server). Klient v multiplayeru ji vypne
## (`authority = false`): počasí si nevyvíjí samo (ani náhodné blesky), jen plynule doháhá stav ze serveru
## (`apply_state`), blesky přijdou zvenku (`remote_lightning`).
var authority := true

const REMOTE_SMOOTH_S := 2.0           # za jak dlouho (s) klient dorovná nový stav ze serveru
## Spojité veličiny stavu, které klient interpoluje (jména shodná s vlastnostmi i s klíči `state()`).
const STATE_FLOATS := ["cloud", "rain", "fog", "wind", "temp", "snow_cover", "wetness", "storm", "rain_recent"]

var _remote := {}                      # poslední stav ze serveru (klient)
var _last_min := -1.0
var _noise := FastNoiseLite.new()
var _anom_noise := FastNoiseLite.new()
var _lightning_t := 5.0


func setup(c: Clock, north: float, forced_kind := "") -> void:
	clock = c
	north_deg = north
	var d := c.date()
	rng.seed = int(d["year"]) * 1000 + int(d["month"]) * 40 + int(d["day"])
	_noise.seed = rng.randi()
	_noise.frequency = 0.9               # přeháňky: přestávky ~po hodině
	_anom_noise.seed = rng.randi()
	_anom_noise.frequency = 0.08          # teplotní odchylka se mění za několik dní
	_warm_up()
	if forced_kind != "":
		force(forced_kind)
	_last_min = clock.minutes


## Nasimuluje předchozí 3 dny, aby na začátku odpovídala sněhová pokrývka, mokro a situace.
func _warm_up() -> void:
	var save := clock.minutes
	clock.minutes = save - 72.0 * 60.0
	kind = _pick_next("polojasno")
	kind_left_h = rng.randf_range(2.0, 10.0)
	temp = _temp_target()
	_last_min = clock.minutes
	while clock.minutes < save:
		clock.minutes = minf(clock.minutes + 20.0, save)
		_advance()
	clock.minutes = save


## Vynutí situaci (ladění, příkaz): hodnoty skočí přímo na cíl a situace se sama nezmění.
## "snih" = sněžení (zataženo + srážky při mrazu), "naledi" = zataženo, mrzne a povrch je mokrý
## (test přilnavosti; mráz se drží, dokud je počasí vynucené).
func force(k: String) -> void:
	var snow := k == "snih"
	var ice := k == "naledi"
	if snow:
		k = "dest"
	elif ice:
		k = "zatazeno"
	if not TYPES.has(k):
		push_warning("Neznámé počasí: %s" % k)
		return
	forced = true
	forced_frost = snow or ice
	_set_kind(k)
	var t: Dictionary = TYPES[k]
	cloud = t["cloud"]
	rain = t["rain"]
	fog = t["fog"]
	wind = t["wind"]
	storm = 1.0 if t.get("storm", false) else 0.0
	if snow:
		temp = -3.0
		snow_cover = maxf(snow_cover, 0.6)
	elif ice:
		temp = -3.0
		wetness = 0.8
	elif rain > 0.0:
		wetness = 0.8


func unforce() -> void:
	forced = false
	forced_frost = false
	forced_temp = NAN


## Po skoku v kalendáři (herní menu): znovu nasimulovat poslední 3 dny (sníh, mokro, situace).
func reset() -> void:
	forced = false
	forced_frost = false
	forced_temp = NAN
	snow_cover = 0.0
	wetness = 0.0
	rain_recent = 0.0
	_warm_up()
	_last_min = clock.minutes


# ------------------------------------------------------------------ smyčka

func _process(delta: float) -> void:
	var __t0 := Tests.prof_t0()
	_process_impl(delta)
	Tests.prof_add("weather", __t0)


func _process_impl(delta: float) -> void:
	if clock == null:
		return
	if not authority:
		_remote_step(delta)
		return
	# herní čas může skočit (spánek, okno) – simulace po krocích max. 20 herních minut
	var guard := 0
	while clock.minutes - _last_min > 20.0 and guard < 400:
		var target := clock.minutes
		clock.minutes = _last_min + 20.0
		_advance()
		clock.minutes = target
		guard += 1
	if guard >= 400:
		_last_min = clock.minutes
	_advance()
	# blesky – v reálném čase (bouřka je vidět a slyšet, i když herní čas běží 30×)
	if storm > 0.3 and rain > 0.4:
		_lightning_t -= delta * storm
		if _lightning_t <= 0.0:
			_lightning_t = rng.randf_range(4.0, 22.0)
			_strike()


func _advance() -> void:
	var dt_h := (clock.minutes - _last_min) / 60.0
	_last_min = clock.minutes
	if dt_h <= 0.0:
		return
	if not forced:
		kind_left_h -= dt_h
		if kind_left_h <= 0.0:
			_set_kind(_pick_next(kind))
	var t: Dictionary = TYPES[kind]
	var h := clock.hour()
	var doy := clock.day_of_year()
	# cíle
	var c_t: float = t["cloud"]
	var r_t: float = t["rain"]
	var f_t: float = t["fog"]
	var w_t: float = t["wind"]
	if t.get("showers", false):
		# přeháňky: srážky jen z části času, mezi nimi se protrhá oblačnost
		var n := _noise.get_noise_1d(clock.minutes / 60.0)
		var on := smoothstep(-0.05, 0.25, n)
		r_t *= on
		c_t = lerpf(c_t * 0.7, 1.0, on)
		w_t *= 0.6 + on * 0.8
	# mlha se ve dne rozpouští (víc v létě, když svítí slunce)
	if f_t > 0.0 and kind == "mlha":
		f_t *= 1.0 - smoothstep(9.0, 13.0, h) * (0.3 + Seasons.green(doy) * 0.5)
	# mírná mlha / opar za jasných podzimních a zimních rán
	if kind in ["jasno", "polojasno"] and (h < 9.0 or h > 21.0):
		f_t = maxf(f_t, 0.25 * (1.0 - Seasons.green(doy)))
	var k := 1.0 - exp(-dt_h / TAU_CLOUD)
	cloud = lerpf(cloud, c_t, k)
	rain = lerpf(rain, r_t, 1.0 - exp(-dt_h / TAU_RAIN))
	if rain < 0.005 and r_t == 0.0:
		rain = 0.0
	fog = lerpf(fog, f_t, 1.0 - exp(-dt_h / TAU_FOG))
	wind = lerpf(wind, w_t * (0.8 + 0.4 * _anom_noise.get_noise_1d(clock.minutes / 60.0 * 3.0 + 50.0)),
		1.0 - exp(-dt_h / TAU_WIND))
	wind_bearing = fposmod(250.0 + _anom_noise.get_noise_1d(clock.minutes / 60.0 * 0.5 + 200.0) * 120.0, 360.0)
	storm = move_toward(storm, 1.0 if t.get("storm", false) else 0.0, dt_h * 2.0)
	rain_recent = clampf(rain_recent + rain * dt_h * 0.25 - dt_h / 24.0 * 0.5, 0.0, 1.0)
	temp = lerpf(temp, _temp_target(), 1.0 - exp(-dt_h / TAU_TEMP))
	if forced and forced_frost:
		temp = minf(temp, -2.0)
	if not is_nan(forced_temp):
		temp = forced_temp
	# sníh a mokro
	var sun := clampf(clock.sun_elevation() / 40.0, 0.0, 1.0) * (1.0 - cloud * 0.7)
	if rain > 0.02 and temp < SNOW_BELOW:
		snow_cover = minf(snow_cover + rain * dt_h * 0.35, 1.0)
	elif snow_cover > 0.0 and temp > 0.3:
		var melt := (0.015 * temp + 0.25 * rain + 0.06 * sun) * dt_h
		snow_cover = maxf(snow_cover - melt, 0.0)
		wetness = maxf(wetness, minf(snow_cover * 3.0, 0.7))
	if rain > 0.02 and temp >= SNOW_BELOW:
		wetness = minf(wetness + rain * dt_h * 4.0, 1.0)
	else:
		var dry := (0.05 + 0.012 * maxf(temp, 0.0) + 0.02 * wind + 0.25 * sun) * dt_h
		wetness = maxf(wetness - dry * (0.35 if temp < 0.0 else 1.0), 0.0)


## Teplota, ke které se vzduch blíží: měsíční průměr + dlouhodobá odchylka + denní chod
## (minimum před východem slunce, maximum ve 15 h; oblačnost rozkmit tlumí, déšť ochlazuje).
func _temp_target() -> float:
	var doy := clock.day_of_year()
	var base := Seasons.monthly(Seasons.TEMP_MEAN, doy)
	var rng_c := Seasons.monthly(Seasons.TEMP_RANGE, doy) * (1.0 - 0.6 * cloud)
	var anomaly := _anom_noise.get_noise_1d(clock.minutes / 1440.0 * 3.0) * 5.0
	var h := clock.hour()
	var f: float
	if h >= 6.0 and h <= 15.0:
		f = -cos(PI * (h - 6.0) / 9.0)
	else:
		f = cos(PI * fposmod(h - 15.0, 24.0) / 15.0)
	return base + anomaly + 0.5 * rng_c * f - 2.5 * rain - 1.0 * fog


func _set_kind(k: String) -> void:
	var changed := k != kind
	kind = k
	var hr: Array = TYPES[k]["hours"]
	kind_left_h = rng.randf_range(hr[0], hr[1])
	if changed:
		kind_changed.emit(k)


## Váhy možných pokračování situace `from` pro den v roce `doy` a hodinu `h` (klima + denní doba).
## Čte ji `_pick_next` (náhodná volba) i `forecast` (nejpravděpodobnější výsledek).
func _weights(from: String, doy: float, h: float) -> Dictionary:
	var wet := Seasons.monthly(Seasons.WET_DAYS, doy) / 8.0
	var storm_share := Seasons.monthly(Seasons.STORM_SHARE, doy)
	var green := Seasons.green(doy)
	var opts: Dictionary = NEXT.get(from, {})
	var ws := {}
	for k in opts:
		var w: float = opts[k]
		match k:
			"dest", "prehanky":
				w *= wet
			"bourka":
				w *= storm_share * 8.0 * (1.6 if h > 11.0 and h < 20.0 else 0.3)
			"mlha":
				w *= (2.5 - green * 2.0) * (1.5 if h < 9.0 or h > 19.0 else 0.3)
			"zatazeno":
				w *= 2.0 - green      # zimní inverze
			"jasno", "polojasno":
				w *= 0.6 + green * 0.6
		ws[k] = maxf(w, 0.0)
	return ws


func _pick_next(from: String) -> String:
	var ws := _weights(from, clock.day_of_year(), clock.hour())
	var total := 0.0
	for k in ws:
		total += float(ws[k])
	if total <= 0.0:
		return "oblacno"
	var r := rng.randf() * total
	for k in ws:
		r -= float(ws[k])
		if r <= 0.0:
			return k
	return from


func _strike() -> void:
	var w := get_parent()
	var center := Vector3.ZERO
	if w and w.has_method("player_anchor"):
		center = w.player_anchor(rng.randi() % 8)
	var a := rng.randf() * TAU
	var d := rng.randf_range(250.0, 4000.0)
	lightning.emit(center + Vector3(cos(a) * d, 0, sin(a) * d))


# ------------------------------------------------------------------ dotazy

func kind_name() -> String:
	if is_snowing():
		return "Sněžení" if rain > 0.15 else "Slabé sněžení"
	if rain > 0.02 and kind in ["zatazeno", "oblacno", "polojasno", "jasno", "mlha"]:
		return "Doznívající déšť"
	return TYPES[kind]["name"]


func is_raining() -> bool:
	return rain > 0.03 and temp >= SNOW_BELOW


func is_snowing() -> bool:
	return rain > 0.03 and temp < SNOW_BELOW


## Mokro povrchu 0..1 (plán §12.3 „wetness_ground“) – alias ke `wetness`, terénní shader
## jej čte přes globální uniform `wetness` (nastavuje Atmosphere), louže přes Puddles.
func wetness_ground() -> float:
	return wetness


## Srážky v mm/h.
func precip_mm_h() -> float:
	return rain * RAIN_MM_H


## Směr, kam vítr fouká, ve světě hry (vodorovný jednotkový vektor) × rychlost (m/s).
func wind_vector() -> Vector3:
	var to_bearing := deg_to_rad(wind_bearing + 180.0)
	var v := Clock.enu_to_world(Vector3(sin(to_bearing), cos(to_bearing), 0.0), north_deg)
	return Vector3(v.x, 0.0, v.z).normalized() * wind


## Jednoznaková ikona situace do HUD (u hodin i v deníku).
func icon() -> String:
	if is_snowing():
		return "❄"
	match kind:
		"jasno": return "☀"
		"polojasno": return "⛅"
		"oblacno": return "☁"
		"zatazeno": return "☁"
		"mlha": return "≡"
		"prehanky", "dest": return "☂"
		"bourka": return "⚡"
	return ""


## Krátký popis do HUD: "Déšť · 8 °C".
func describe() -> String:
	var t := "%s · %d °C" % [kind_name(), roundi(temp)]
	if wind > 8.0:
		t += " · silný vítr"
	if snow_cover > 0.15:
		t += " · sníh %d cm" % roundi(snow_cover * 10.0)
	return t


## Jednoduchá předpověď na zítřek (deník J): nejpravděpodobnější situace kolem poledne zítra
## z tabulky přechodů a odhad denního maxima podle klimatu. Vrací {kind, name, temp}.
func forecast() -> Dictionary:
	if clock == null:
		return {}
	var doy := clock.day_of_year() + 1.0
	if doy > 365.0:
		doy -= 365.0
	var ws := _weights(kind, doy, 13.0)
	var best := kind
	var bw := -1.0
	for k in ws:
		if float(ws[k]) > bw:
			bw = float(ws[k])
			best = k
	var tmax := Seasons.monthly(Seasons.TEMP_MEAN, doy) + Seasons.monthly(Seasons.TEMP_RANGE, doy) * 0.35
	var name_: String = TYPES[best]["name"]
	if TYPES[best].get("rain", 0.0) > 0.0 and tmax <= SNOW_BELOW + 1.0:
		name_ = "Sněžení"
	return {"kind": best, "name": name_, "temp": roundi(tmax)}


## Přilnavost povrchu `surf` ("asfalt" / "sterk" / "teren", jiné = 0.9) za aktuálního počasí.
## Mokro zmnoží, sníh a náledí stanoví strop; na terénu navíc bahno.
func surface_grip(surf: String) -> float:
	var g: float = SURF_GRIP.get(surf, 0.9)
	if surf == "teren" and wetness > 0.45:
		g = minf(g, lerpf(1.0, GRIP_MUD, wetness))   # rozmočená hlína
	g *= lerpf(1.0, GRIP_WET, wetness)
	if snow_cover > 0.02:
		g = minf(g, lerpf(1.0, GRIP_SNOW, snow_cover))
	if temp < 0.0 and wetness > ICE_WET:
		g = minf(g, lerpf(1.0, GRIP_ICE, clampf(wetness / 0.7, 0.0, 1.0)))
	return g


## Kolik ze „suché“ přilnavosti povrchu `surf` počasí ubralo (1 = sucho, 0.5 = poloviční).
## Pro chodce a koně: sama tráva / hlína jim neklouže, jen mokro, bahno, sníh a led (auto bere rovnou surface_grip).
func grip_factor(surf: String) -> float:
	return clampf(surface_grip(surf) / maxf(float(SURF_GRIP.get(surf, 0.9)), 0.1), 0.0, 1.0)


## Stav pro klienty (v MP stačí posílat po pár sekundách a hned při změně situace).
func state() -> Dictionary:
	return {"kind": kind, "cloud": cloud, "rain": rain, "fog": fog, "wind": wind, "wind_bearing": wind_bearing,
		"temp": temp, "snow_cover": snow_cover, "wetness": wetness, "storm": storm,
		"forced": forced, "rain_recent": rain_recent}


## Klient převezme stav ze serveru: situace (`kind`) hned, spojité veličiny se k němu blíží plynule
## (REMOTE_SMOOTH_S). Při prvním stavu (a při velkém skoku, např. po změně data) skočí rovnou.
func apply_state(s: Dictionary) -> void:
	var first := _remote.is_empty()
	_remote = s.duplicate()
	forced = bool(s.get("forced", false))
	var k: String = String(s.get("kind", kind))
	if TYPES.has(k) and k != kind:
		kind = k
		kind_changed.emit(k)
	if first:
		_snap_to_remote()


func _snap_to_remote() -> void:
	for key in STATE_FLOATS:
		if _remote.has(key):
			set(key, float(_remote[key]))
	if _remote.has("wind_bearing"):
		wind_bearing = float(_remote["wind_bearing"])


## Klientská smyčka (jen `authority == false`): žádný vlastní vývoj, jen dorovnání ke stavu serveru.
func _remote_step(delta: float) -> void:
	if _remote.is_empty():
		return
	var k := 1.0 - exp(-delta / (REMOTE_SMOOTH_S * 0.35))    # ~95 % za REMOTE_SMOOTH_S
	for key in STATE_FLOATS:
		if _remote.has(key):
			var cur: float = float(get(key))
			set(key, lerpf(cur, float(_remote[key]), k))
	if _remote.has("wind_bearing"):
		wind_bearing = lerp_angle(deg_to_rad(wind_bearing), deg_to_rad(float(_remote["wind_bearing"])), k) * 180.0 / PI
		wind_bearing = fposmod(wind_bearing, 360.0)


## Blesk ze serveru (RPC s polohou): na klientu vyvolá stejný efekt jako lokální blesk (záblesk,
## hrom se zpožděním, polekaný kůň), jen bez náhody. Server posílá RPC ze svého signálu `lightning`.
func remote_lightning(pos: Vector3) -> void:
	lightning.emit(pos)
