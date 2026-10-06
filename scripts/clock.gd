## Herní čas a kalendář: 1 s reálného času = TIME_SCALE s herního času (30 → 1 herní hodina za 2 minuty).
## Řídí denní dobu (slunce, obloha, světla), fyziologii (odbourávání alkoholu, trávení), roční období
## (vegetace – Seasons, počasí – Weather) a aktivitu zvířat.
##
## Kalendář je skutečný: den 1 = `start_date` (výchozí dnešní datum systému, ladicí parametr --date=RRRR-MM-DD).
## Poloha slunce a měsíce se počítá astronomicky pro zeměpisnou polohu obce (`LAT` / `LON` níže, přibližná – fiktivní obec) a místní čas
## (SEČ / letní čas SELČ od poslední neděle v březnu do poslední neděle v říjnu) → délka dne, výška slunce
## a západ se mění s ročním obdobím.
class_name Clock
extends Node

const TIME_SCALE := 30.0
const LAT := 49.1                    # zeměpisná šířka obce (°) – přibližná
const LON := 17.7                    # zeměpisná délka (°) – přibližná

const MONTHS := ["ledna", "února", "března", "dubna", "května", "června", "července", "srpna", "září",
	"října", "listopadu", "prosince"]
const MONTHS_1 := ["leden", "únor", "březen", "duben", "květen", "červen", "červenec", "srpen", "září",
	"říjen", "listopad", "prosinec"]
const WEEKDAYS := ["po", "út", "st", "čt", "pá", "so", "ne"]

var minutes := 17.0 * 60.0 + 30.0   # herní minuty od půlnoci 1. dne
var paused := false
var speed := 1.0                    # násobič rychlosti času (herní menu: 0 pauza, 1 normál, 4, 20)
var start_jd := 0                   # juliánské číslo dne pro 1. herní den

var _sun_cache_min := -1.0
var _sun_cache := Vector3.UP
var _sync_rest := 0.0               # multiplayer (klient): kolik herních minut ještě dorovnat k času serveru
var _sync_left := 0.0               # … a za kolik s reálného času (0 = nedoháníme)


func _init() -> void:
	var d := Time.get_date_dict_from_system()
	set_start_date(int(d["year"]), int(d["month"]), int(d["day"]))


func _process(delta: float) -> void:
	if not paused:
		minutes += delta * TIME_SCALE * speed / 60.0
	if _sync_left > 0.0:
		_sync_step(delta)


# ------------------------------------------------------------------ síť (příprava na multiplayer)

## Rozdíl času serveru a klienta, do kterého se dorovnává plynule (herní minuty); větší = skok.
const SYNC_SMOOTH_MAX := 2.0
const SYNC_SMOOTH_S := 1.0           # za jak dlouho (s) se malý rozdíl dorovná

## Stav kalendáře pro klienty (server ho posílá po pár sekundách; klient si čas mezitím počítá sám).
func state() -> Dictionary:
	return {"minutes": minutes, "start_jd": start_jd, "speed": speed, "paused": paused}


## Klient převezme stav serveru. Rychlost a začátek kalendáře hned; `minutes` plynule, když je rozdíl
## menší než SYNC_SMOOTH_MAX herních minut (dohání se SYNC_SMOOTH_S s), jinak skokem.
func apply_state(s: Dictionary, interpolate := true) -> void:
	speed = float(s.get("speed", speed))
	paused = bool(s.get("paused", paused))
	var jd_new: int = int(s.get("start_jd", start_jd))
	if jd_new != start_jd:
		start_jd = jd_new
		_sun_cache_min = -1.0
	var target: float = float(s.get("minutes", minutes))
	var diff := target - minutes
	if interpolate and absf(diff) < SYNC_SMOOTH_MAX:
		_sync_rest = diff
		_sync_left = SYNC_SMOOTH_S
	else:
		minutes = target
		_sync_rest = 0.0
		_sync_left = 0.0
		_sun_cache_min = -1.0


func _sync_step(delta: float) -> void:
	var step := minf(delta, _sync_left)
	var part := _sync_rest * step / _sync_left
	minutes += part
	_sync_rest -= part
	_sync_left -= step
	if _sync_left <= 0.0:
		_sync_left = 0.0
		_sync_rest = 0.0


# ------------------------------------------------------------------ čas dne

func hour() -> float:
	return fmod(minutes / 60.0, 24.0)


func day() -> int:
	return int(minutes / 1440.0) + 1


func skip_hours(h: float) -> void:
	minutes += h * 60.0


func text() -> String:
	var m := int(minutes) % 1440
	return "%02d:%02d" % [m / 60, m % 60]


## 0 = noc, 1 = den – podle skutečné výšky slunce (plynulý přechod za občanského soumraku).
func daylight() -> float:
	return smoothstep(-7.0, 5.0, sun_elevation())


func is_night() -> bool:
	return daylight() < 0.35


# ------------------------------------------------------------------ kalendář

## Nastaví datum 1. herního dne (hodina zůstane).
func set_start_date(y: int, m: int, d: int) -> void:
	start_jd = jdn(y, m, d)
	_sun_cache_min = -1.0


## Nastaví dnešní datum (posune začátek kalendáře tak, aby dnešní herní den měl toto datum).
func set_date(y: int, m: int, d: int) -> void:
	start_jd = jdn(y, m, d) - (day() - 1)
	_sun_cache_min = -1.0


## Juliánské číslo dne (gregoriánský kalendář).
static func jdn(y: int, m: int, d: int) -> int:
	var a := (14 - m) / 12
	var yy := y + 4800 - a
	var mm := m + 12 * a - 3
	return d + (153 * mm + 2) / 5 + 365 * yy + yy / 4 - yy / 100 + yy / 400 - 32045


## Juliánské číslo → {year, month, day}.
static func from_jdn(j: int) -> Dictionary:
	var a := j + 32044
	var b := (4 * a + 3) / 146097
	var c := a - 146097 * b / 4
	var d := (4 * c + 3) / 1461
	var e := c - 1461 * d / 4
	var m := (5 * e + 2) / 153
	return {"day": e - (153 * m + 2) / 5 + 1, "month": m + 3 - 12 * (m / 10), "year": 100 * b + d - 4800 + m / 10}


func jd() -> int:
	return start_jd + day() - 1


func date() -> Dictionary:
	return from_jdn(jd())


func year() -> int:
	return date()["year"]


func month() -> int:
	return date()["month"]


## 0 = pondělí … 6 = neděle
func weekday() -> int:
	return jd() % 7


## Den v roce 1..366 (s desetinnou částí podle hodiny) – pro plynulé křivky ročních období.
func day_of_year() -> float:
	var d := date()
	return float(jd() - jdn(d["year"], 1, 1) + 1) + hour() / 24.0


## Meteorologické roční období podle měsíce: jaro (3–5), léto (6–8), podzim (9–11), zima (12–2).
func season() -> String:
	return ["zima", "zima", "jaro", "jaro", "jaro", "léto", "léto", "léto", "podzim", "podzim", "podzim", "zima"][month() - 1]


func date_text() -> String:
	var d := date()
	return "%s %d. %s %d" % [WEEKDAYS[weekday()], d["day"], MONTHS[d["month"] - 1], d["year"]]


## Státní svátek v ČR (název) nebo "".
func holiday() -> String:
	return holiday_on(jd())


## Státní svátek v den s juliánským číslem `j` (název) nebo "" – i pro jiné dny než dnešek (M3.1: zmeškané směny).
static func holiday_on(j: int) -> String:
	var d := from_jdn(j)
	var key := "%d.%d" % [d["day"], d["month"]]
	var fixed := {"1.1": "Nový rok, Den obnovy samostatného českého státu", "1.5": "Svátek práce",
		"8.5": "Den vítězství", "5.7": "Den slovanských věrozvěstů Cyrila a Metoděje",
		"6.7": "Den upálení mistra Jana Husa", "28.9": "Den české státnosti (sv. Václav)",
		"28.10": "Den vzniku samostatného československého státu",
		"17.11": "Den boje za svobodu a demokracii", "24.12": "Štědrý den", "25.12": "1. svátek vánoční",
		"26.12": "2. svátek vánoční"}
	if fixed.has(key):
		return fixed[key]
	var easter := easter_jdn(d["year"])
	if j == easter - 2:
		return "Velký pátek"
	if j == easter + 1:
		return "Velikonoční pondělí"
	return ""


## Velikonoční neděle (anonymní gregoriánský algoritmus).
static func easter_jdn(y: int) -> int:
	var a := y % 19
	var b := y / 100
	var c := y % 100
	var d := b / 4
	var e := b % 4
	var f := (b + 8) / 25
	var g := (b - f + 1) / 3
	var h := (19 * a + b - d - g + 15) % 30
	var i := c / 4
	var k := c % 4
	var l := (32 + 2 * e + 2 * i - h - k) % 7
	var m := (a + 11 * h + 22 * l) / 451
	var month_ := (h + l - 7 * m + 114) / 31
	var day_ := (h + l - 7 * m + 114) % 31 + 1
	return jdn(y, month_, day_)


## Posun místního času proti UTC: 1 (SEČ) nebo 2 (letní čas).
func utc_offset() -> int:
	var d := date()
	var y: int = d["year"]
	var j := jd()
	var mar_end := jdn(y, 3, 31)
	var oct_end := jdn(y, 10, 31)
	var dst_start := mar_end - (mar_end % 7 + 1) % 7     # poslední neděle v březnu (jd % 7 == 6 je neděle)
	var dst_end := oct_end - (oct_end % 7 + 1) % 7
	# přepíná se ve 2:00 / 3:00 – na hodinu přesně tu nezáleží
	return 2 if j >= dst_start and j < dst_end else 1


# ------------------------------------------------------------------ slunce a měsíc

## Směr ke slunci v místních souřadnicích (x = východ, y = sever, z = nahoru), jednotkový vektor.
## Algoritmus NOAA (přesnost ~0,1°). Výsledek se drží v mezipaměti na herní minutu.
func sun_enu() -> Vector3:
	if absf(minutes - _sun_cache_min) < 1.0:
		return _sun_cache
	_sun_cache_min = minutes
	var doy := day_of_year()
	var h := hour()
	var tz := float(utc_offset())
	var g := TAU / 365.0 * (doy - 1.0 + (h - tz - 12.0) / 24.0)
	var eqt := 229.18 * (0.000075 + 0.001868 * cos(g) - 0.032077 * sin(g) - 0.014615 * cos(2.0 * g) - 0.040849 * sin(2.0 * g))
	var decl := 0.006918 - 0.399912 * cos(g) + 0.070257 * sin(g) - 0.006758 * cos(2.0 * g) + 0.000907 * sin(2.0 * g) \
		- 0.002697 * cos(3.0 * g) + 0.00148 * sin(3.0 * g)
	var tst := h * 60.0 + eqt + 4.0 * LON - 60.0 * tz
	var ha := deg_to_rad(tst / 4.0 - 180.0)
	_sun_cache = _enu(decl, ha)
	return _sun_cache


static func _enu(decl: float, ha: float) -> Vector3:
	var lat := deg_to_rad(LAT)
	return Vector3(-cos(decl) * sin(ha),
		sin(decl) * cos(lat) - cos(decl) * cos(ha) * sin(lat),
		sin(decl) * sin(lat) + cos(decl) * cos(ha) * cos(lat)).normalized()


## Výška slunce nad obzorem (°).
func sun_elevation() -> float:
	return rad_to_deg(asin(clampf(sun_enu().z, -1.0, 1.0)))


## Fáze měsíce 0..1 (0 nov, 0,5 úplněk) – synodický měsíc od známého novu 6. 1. 2000.
func moon_phase() -> float:
	var days := float(jd()) + (hour() - utc_offset()) / 24.0 - 2451550.26
	return fposmod(days / 29.530589, 1.0)


## Osvětlená část měsíčního kotouče 0..1.
func moon_illumination() -> float:
	return (1.0 - cos(moon_phase() * TAU)) * 0.5


## Směr k měsíci (ENU, přibližně): měsíc „zaostává“ za sluncem o fázový úhel a jeho deklinace
## kolísá se sluncem opačně (úplněk v zimě vysoko, v létě nízko).
func moon_enu() -> Vector3:
	var s := sun_enu()
	var lat := deg_to_rad(LAT)
	# zpětný výpočet hodinového úhlu a deklinace slunce z vektoru
	var decl_s := asin(clampf(s.y * cos(lat) + s.z * sin(lat), -1.0, 1.0))
	var ha_s := atan2(-s.x, s.z * cos(lat) - s.y * sin(lat))
	var ph := moon_phase() * TAU
	var decl_m := decl_s * cos(ph)
	return _enu(decl_m, ha_s - ph)


## Převod směru ENU na směr ve světě hry (Godot: -Z hledí na azimut `north_deg` z map.json).
static func enu_to_world(v: Vector3, north_deg: float) -> Vector3:
	var bearing := atan2(v.x, v.y)                  # azimut od severu po směru hodin
	var yaw := deg_to_rad(north_deg) - bearing
	var hl := Vector2(v.x, v.y).length()
	return Vector3(-sin(yaw) * hl, v.z, -cos(yaw) * hl)
