## Mikroklima (M8.9, `World.micro`): teplota, vlhkost, rosný bod, mlha, mráz, rosa a jinovatka v bodě.
##
## Podle čeho (00_PRINCIPY kap. 8 „Mikroklima“): vertikální gradient −6,5 K/km (standardní atmosféra ICAO);
## za jasné bezvětrné noci radiační ochlazování buduje přízemní inverzi (síla `I` v K, max. `INV_MAX_K`),
## studený vzduch stéká do mrazových kotlin (`Site.cold_pool`) a ke dnu údolí (`Site.hand` = výška nad
## nejbližší vodou, „jezero studeného vzduchu“ hluboké `INV_DEPTH_M`); ráno ji slunce rozpustí. Rosný bod
## Magnusovým vzorcem (Alduchov & Eskridge 1996: a = 17,62, b = 243,12 °C). Radiační mlha tam, kde teplota
## klesne k rosnému bodu (vrstva do výšky `fog_top_m()` nad dnem údolí); rosa / jinovatka, když přízemní
## teplota (za jasné noci o `GROUND_K` níž než ve 2 m) klesne pod rosný bod. Pocitová teplota JAG/TI
## (Environment Canada 2001, vítr v km/h v 10 m).
##
## Vrstva **nad** `Weather` (nic v něm nemění): `Weather.temp` = teplota 2 m nad zemí na střední výšce katastru.
## **Bez vlastní mřížky stavu** – stav je pár globálních čísel (síla inverze, rosný bod vzduchové hmoty, výška
## a hustota mlžné vrstvy, rosa, mrazová hranice). Krok jednou za herní hodinu přes `World.eco_hour` počítá
## hodnoty na **konec** příští hodiny a dotazy mezi nimi lineárně prolínají (v HUD nic neskáče). Skok času
## (F2, spánek, načtení) se dožene levným „rozběhem“ 18 hodinových kroků s dnešním počasím.
## Dotazy v bodě (`temp_at`…) nealokují: statické vlastnosti místa (výška, HAND, kotlina, hřbet, jižní svah,
## les, zástavba, voda) se čtou ze `Site` / `TreeEco` / `SurfaceMap` jednou na buňku `CACHE_CELL` m do malé
## mezipaměti (`CACHE_N` slotů), počasí a slunce jednou za snímek.
##
## Fallback (00_PRINCIPY kap. 3): přepínač `micro` vypnutý → `temp_at` = `Weather.temp`, `fog_at` =
## `Weather.fog`, mráz jen z globální teploty, rosa 0 (jako dřív – teplota všude stejná). Bez `site.bin` se
## počítá jen výškový gradient (inverze nemá kde stékat).
class_name Microclimate
extends RefCounted

# --- laditelné konstanty (ladění M8.19)
const LAPSE_K_M := 0.0065             # K/m – vertikální gradient (−6,5 K/km)
const INV_MAX_K := 7.0                # K – nejsilnější přízemní inverze (dno kotliny vs. střední výška)
const INV_RATE_K_H := 1.5             # K/h – nárůst inverze za jasné bezvětrné noci (zpomaluje se k maximu)
const INV_MIX_H := 1.5                # h – rozmíchání inverze větrem / oblačností / deštěm (časová konstanta)
const INV_BREAK_H := 1.2              # h – rozpouštění inverze sluncem (při výšce slunce ≥ 30°)
const INV_DEPTH_M := 50.0             # m – mocnost „jezera“ studeného vzduchu nad dnem údolí (HAND)
const W_LOW := 0.65                   # podíl inverze podle výšky nad vodou (HAND = 0 → plně)
const W_POOL := 0.6                   # podíl inverze v mrazové kotlině (Site.cold_pool = 1)
const BELT_K := 0.15                  # teplý svahový pás: hřbet nad inverzí je o I × BELT_K tepleji
const TPI_RIDGE_M := 30.0             # TPI (m), od kterého je místo „hřbet“
const CALM_FROM_MS := 1.5             # m/s – do této rychlosti větru plné radiační ochlazování
const CALM_TO_MS := 5.0               # m/s – od této rychlosti vítr vrstvu promíchá (žádná inverze)
const CLEAR_FROM := 0.25              # oblačnost, od které ubývá vyzařování
const CLEAR_TO := 0.85                # … a při které už inverze nevzniká
const SOUTH_K := 3.0                  # K – přehřátí jižního svahu proti průměru (plné slunce)
const INSOL_MEAN := 5150.0            # MJ/m²/rok – průměrné Site.insol katastru (tools/site.py)
const INSOL_SPAN := 900.0             # MJ/m²/rok – rozdíl insol pro plné přehřátí / ochlazení svahu
const FOREST_DAY_K := 2.5             # K – v olistěném lese ve dne chladněji
const FOREST_NIGHT_K := 1.0           # K – v lese za jasné noci tepleji (koruny brání vyzařování)
const URBAN_DAY_K := 0.5              # K – tepelný ostrov obce ve dne
const URBAN_NIGHT_K := 1.5            # K – … za jasné bezvětrné noci
const URBAN_R_M := 30.0               # m – poloměr vzorku zástavby (SurfaceMap.YARD)
const WATER_NEAR_M := 80.0            # m – do této vzdálenosti od vody voda zjemňuje výkyvy a vlhčí vzduch
const WATER_DAMP := 0.15              # o kolik voda tlumí inverzi a přehřátí
const GROUND_K := 3.0                 # K – o kolik je přízemní teplota (tráva) za jasné noci níž než ve 2 m
const DEP_K := 3.5                    # K – deficit rosného bodu pod očekávaným minimem v suchém vzduchu
const TD_TAU_H := 6.0                 # h – jak rychle se rosný bod vzduchové hmoty mění
const TMEAN_TAU_H := 24.0             # h – klouzavý průměr teploty (denní střed)
const TD_WATER_K := 1.0               # K – vyšší rosný bod u vody
const TD_FOREST_K := 0.7              # K – … v lese (transpirace)
const TD_SOIL_K := 1.5                # K – … nad mokrou půdou (SoilWater, vlhkost − 0,5)
const FOG_MARGIN_K := 0.5             # K – mlha, když teplota ≤ rosný bod + tohle
const FOG_TAU_UP_H := 1.5             # h – mlžná vrstva roste
const FOG_TAU_DOWN_H := 1.0           # h – … a ráno se rozpouští (od okrajů – horní hranice klesá)
const FOG_EDGE_M := 8.0               # m – měkký horní okraj vrstvy (fog_at)
const FOG_SCAN_M := 5.0               # m – krok hledání horní hranice mlhy / mrazu v profilu údolí
const FOG_SCAN_N := 40                # kroků (do 200 m nad dnem)
const DEW_RATE_H := 0.35              # rosa přibývá za hodinu (plná kondenzace)
const DEW_DRY_H := 0.6                # rosa ubývá za hodinu (× (0,1 + 3 · slunce² + 0,05 · vítr))
const FROST_TAU_UP_H := 0.5           # h – mrazová hranice stoupá (ochlazování)
const FROST_TAU_DOWN_H := 1.0         # h – … a ráno klesá (jinovatka taje zespodu nahoru jen pomalu)
const NO_FROST_M := -20.0             # frost_top_m(): na dně údolí nemrzne (hranice pod dnem)
const ALL_FROST_M := 220.0            # frost_top_m(): mrzne i na hřebenech (nad profilem)
const SNAP_HOURS := 18                # rozběh po skoku času: kolik hodin zpět se nasimuluje
const MAGNUS_A := 17.62
const MAGNUS_B := 243.12
const HUD_MS := 500                   # ms – jak často se přepočítá řádek počasí v HUD
## Výchozí reprezentativní body katastru, když nejde vzorkovat `Site` (statistika `data/site.bin`, 10/2026).
const DEF_REF_ELEV := 0.6             # m – střední výška (svět Y)
const DEF_VALLEY_ELEV := -65.0        # m – medián dna kotlin (cold_pool > 0,5)
const DEF_RIDGE_ELEV := 37.0          # m – medián hřbetů (TPI > 15 m)
const DEF_RIDGE_HAND := 48.0          # m – HAND hřbetů
const STATS_STRIDE := 48              # buněk Site mezi vzorky při statistice (jednou při načtení)
const CACHE_N := 32                   # slotů mezipaměti vlastností místa (mocnina 2)
const CACHE_CELL := 8.0               # m – buňka mezipaměti

# indexy prolínaného stavu (hodnota na začátku `_a` a na konci `_b` hodiny)
const S_INV := 0                      # K síla inverze
const S_FOG_TOP := 1                  # m – horní hranice radiační mlhy nad dnem údolí (0 = není)
const S_FOG_DENS := 2                 # 0..1 hustota mlžné vrstvy
const S_DEW := 3                      # 0..1 rosa / jinovatka na trávě (louka v údolí)
const S_FROST_TOP := 4                # m – do jaké výšky nad dnem údolí je zem zmrzlá (jinovatka)
const NV := 5
const _NP := 8                        # vlastností na slot: elev, hand, cold, ridge, south, forest, urban, near

var world: World
var weather: Weather
var clock: Clock
var site: Site
var td_air := 5.0                     # °C – rosný bod vzduchové hmoty (referenční výška)
var t_mean := 10.0                    # °C – klouzavý denní průměr Weather.temp
var ref_elev := DEF_REF_ELEV
var valley_elev := DEF_VALLEY_ELEV
var ridge_elev := DEF_RIDGE_ELEV
var ridge_hand := DEF_RIDGE_HAND
## Denní statistika do deníku a ladění: nejnižší noční teplota v kotlině a na hřebeni (poslední noc).
var night_min_valley := NAN
var night_min_ridge := NAN
var _nmin_v := INF
var _nmin_r := INF
var _stats_day := -1

var _a := PackedFloat32Array()
var _b := PackedFloat32Array()
var _t_a := -1.0e12                   # herní minuty, ke kterým patří `_a`
var _ck := PackedInt64Array()
var _cv := PackedFloat32Array()
# prostředí jednou za snímek
var _e_frame := -1
var _e_on := false
var _e_tref := 10.0
var _e_sunf := 0.0                    # 0..1 ohřev sluncem (výška × oblačnost)
var _e_nightc := 0.0                  # 0..1 radiační noc (jasno × bezvětří × sucho × noc)
var _e_fol := 1.0
var _e_frac := 0.0
var _hud_ms := -100000
var _hud_pos := Vector3(1.0e9, 0.0, 0.0)
var _hud_txt := ""


func setup(w: World) -> void:
	world = w
	weather = w.weather
	clock = w.clock
	site = w.site
	_a.resize(NV)
	_b.resize(NV)
	_a.fill(0.0)
	_b.fill(0.0)
	_a[S_FROST_TOP] = NO_FROST_M
	_b[S_FROST_TOP] = NO_FROST_M
	_ck.resize(CACHE_N)
	_ck.fill(-1)
	_cv.resize(CACHE_N * _NP)
	_site_stats()
	w.eco_hour.connect(_on_eco_hour)
	w.debug_layers["teplota"] = Callable(self, "debug_temp")
	w.debug_layers["mlha"] = Callable(self, "debug_fog")
	w.debug_layers["mraz"] = Callable(self, "debug_frost")


## Reprezentativní výšky katastru (střed, dno kotlin, hřbety) – jednou při načtení, hrubě (~2 300 bodů).
func _site_stats() -> void:
	if site == null or not site.loaded:
		return
	var sum := 0.0
	var cnt := 0
	var ve := PackedFloat32Array()
	var re := PackedFloat32Array()
	var rh := PackedFloat32Array()
	var iz := 0
	while iz < site.nz:
		var ix := 0
		while ix < site.nx:
			var x := site.x0 + (ix + 0.5) * site.cell
			var z := site.z0 + (iz + 0.5) * site.cell
			var e := site.elev(x, z)
			sum += e
			cnt += 1
			if site.cold_pool(x, z) > 0.5:
				ve.append(e)
			if site.tpi(x, z) > 15.0:
				re.append(e)
				rh.append(site.hand(x, z))
			ix += STATS_STRIDE
		iz += STATS_STRIDE
	if cnt > 0:
		ref_elev = sum / cnt
	if ve.size() > 4:
		ve.sort()
		valley_elev = ve[ve.size() / 2]
	if re.size() > 4:
		re.sort()
		rh.sort()
		ridge_elev = re[re.size() / 2]
		ridge_hand = rh[rh.size() / 2]


## Zapnuto (přepínač `micro`) a je z čeho počítat.
func enabled() -> bool:
	return weather != null and clock != null and (world == null or world.realism_on("micro"))


# ------------------------------------------------------------------ hodinový krok

func _on_eco_hour(_dt_h: float) -> void:
	if weather == null or clock == null:
		return
	var el := clock.minutes - _t_a
	if el < 0.0 or el > 150.0:
		_snap()
	elif el >= 30.0:
		_a = _b.duplicate()
		_t_a = clock.minutes
		_step(_a, _b, 1.0, clock.minutes + 30.0, weather.temp, weather.cloud, weather.wind, weather.rain, true)
	# jinak: dohánění skoku – víc eco_hour v jednom snímku, čas se nepohnul (rozběh už proběhl)


## Rozběh po skoku času / načtení: SNAP_HOURS hodinových kroků s dnešní oblačností a větrem a teplotou
## z klimatu (denní chod), pak jeden krok na příští hodinu. O(SNAP_HOURS) – jen po skoku času.
func _snap() -> void:
	var now := clock.minutes
	var doy := clock.day_of_year()
	var tm := Seasons.monthly(Seasons.TEMP_MEAN, doy)
	var rngc := Seasons.monthly(Seasons.TEMP_RANGE, doy) * (1.0 - 0.6 * weather.cloud)
	var off := weather.temp - (tm + 0.5 * rngc * _diurnal(clock.hour()))   # dnešní odchylka od klimatu
	t_mean = tm + off
	td_air = _td_target(weather.cloud, weather.rain)
	var s := PackedFloat32Array()
	s.resize(NV)
	s.fill(0.0)
	s[S_FROST_TOP] = NO_FROST_M
	var nxt := PackedFloat32Array()
	nxt.resize(NV)
	for k in SNAP_HOURS:
		var m := now - (SNAP_HOURS - k) * 60.0 + 30.0
		var h := fposmod(m / 60.0, 24.0)
		var tr := tm + off + 0.5 * rngc * _diurnal(h)
		_step(s, nxt, 1.0, m, tr, weather.cloud, weather.wind, weather.rain, false)
		s = nxt.duplicate()
	_a = s
	_b = s.duplicate()
	_t_a = now
	_step(_a, _b, 1.0, now + 30.0, weather.temp, weather.cloud, weather.wind, weather.rain, false)


## Denní chod teploty jako `Weather._temp_target` (−1 před východem slunce … +1 v 15 h).
func _diurnal(h: float) -> float:
	if h >= 6.0 and h <= 15.0:
		return -cos(PI * (h - 6.0) / 9.0)
	return cos(PI * fposmod(h - 15.0, 24.0) / 15.0)


## Rosný bod, ke kterému se vzduchová hmota blíží: očekávané noční minimum − deficit podle vlhkosti situace.
func _td_target(cloud: float, rain: float) -> float:
	var doy := clock.day_of_year()
	var rngc := Seasons.monthly(Seasons.TEMP_RANGE, doy) * (1.0 - 0.6 * cloud)
	var moist := clampf(0.35 + 0.35 * cloud + 0.8 * rain + 0.4 * weather.fog + 0.3 * weather.rain_recent
		- 0.35 * weather.drought, 0.0, 1.0)
	return t_mean - 0.5 * rngc - DEP_K * (1.0 - moist) - 0.3


## Jeden krok stavu `src` → `dst` o `dt` hodin; `m` = herní minuta středu kroku (poloha slunce).
func _step(src: PackedFloat32Array, dst: PackedFloat32Array, dt: float, m: float, t_ref: float, cloud: float,
		wind: float, rain: float, track: bool) -> void:
	var elev := _sun_elev_at(m)
	var clear := 1.0 - smoothstep(CLEAR_FROM, CLEAR_TO, cloud)
	var calm := 1.0 - smoothstep(CALM_FROM_MS, CALM_TO_MS, wind)
	var dry := 1.0 - clampf(rain * 4.0, 0.0, 1.0)
	var nightc := clear * calm * dry * (1.0 - smoothstep(0.0, 12.0, elev))
	var sunf := clampf(elev / 45.0, 0.0, 1.0) * (1.0 - 0.75 * cloud)
	# vzduchová hmota
	t_mean = lerpf(t_mean, t_ref, 1.0 - exp(-dt / TMEAN_TAU_H))
	td_air = minf(lerpf(td_air, _td_target(cloud, rain), 1.0 - exp(-dt / TD_TAU_H)), t_ref)
	# inverze: radiační ochlazování (noc, jasno, bezvětří) − promíchání − rozpouštění sluncem
	var inv := src[S_INV]
	var build := INV_RATE_K_H * clear * calm * dry * (1.0 - smoothstep(-2.0, 8.0, elev)) * (1.0 - inv / INV_MAX_K)
	var decay := (1.0 - clear * calm * dry) / INV_MIX_H + smoothstep(5.0, 30.0, elev) * (0.3 + 0.7 * clear) / INV_BREAK_H
	inv = clampf(inv + build * dt - inv * (1.0 - exp(-decay * dt)), 0.0, INV_MAX_K)
	dst[S_INV] = inv
	# profil údolí: horní hranice mlhy (T ≤ Td + okraj) a zmrzlé země (Tg ≤ 0) od dna nahoru
	var fog_t := 0.0
	var frost_t := NO_FROST_M
	var fog_dens_t := 0.0
	var fog_ok := true                                # vrstva souvislá ode dna nahoru
	var frost_ok := true
	for i in FOG_SCAN_N + 1:
		var hh := i * FOG_SCAN_M
		var cold := clampf(1.0 - hh / 15.0, 0.0, 1.0) * 0.8
		var near := 1.0 if hh < 5.0 else 0.0
		var ta := _t_model(valley_elev + hh, hh, cold, 0.0, 0.0, 0.0, 0.0, near, t_ref, inv, sunf, nightc)
		var td := td_air + TD_WATER_K * near
		var tg := ta - GROUND_K * nightc
		if i == 0:
			fog_dens_t = clampf((td + FOG_MARGIN_K - ta) / 2.0, 0.0, 1.0) * calm * dry
		if fog_ok:
			if ta <= td + FOG_MARGIN_K:
				fog_t = maxf(hh, 1.0)
			else:
				fog_ok = false
		if frost_ok:
			if tg <= 0.0:
				frost_t = ALL_FROST_M if i == FOG_SCAN_N else hh
			else:
				frost_ok = false
		if not fog_ok and not frost_ok:
			break
	if fog_dens_t <= 0.0:
		fog_t = 0.0
	var top := src[S_FOG_TOP]
	dst[S_FOG_TOP] = lerpf(top, fog_t, 1.0 - exp(-dt / (FOG_TAU_UP_H if fog_t > top else FOG_TAU_DOWN_H)))
	var dens := src[S_FOG_DENS]
	dst[S_FOG_DENS] = lerpf(dens, fog_dens_t, 1.0 - exp(-dt / (FOG_TAU_UP_H if fog_dens_t > dens else FOG_TAU_DOWN_H)))
	if dst[S_FOG_TOP] < 0.5:
		dst[S_FOG_DENS] = minf(dst[S_FOG_DENS], dst[S_FOG_TOP] * 2.0)
	# mrazová hranice (jinovatka): stoupá rychle, ráno klesá pomaleji (taje postupně)
	var ft := src[S_FROST_TOP]
	dst[S_FROST_TOP] = lerpf(ft, frost_t, 1.0 - exp(-dt / (FROST_TAU_UP_H if frost_t > ft else FROST_TAU_DOWN_H)))
	# rosa na louce v údolí (10 m nad dnem): kondenzace pod rosným bodem, vysychá sluncem, větrem, teplem
	var ta10 := _t_model(valley_elev + 10.0, 10.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, t_ref, inv, sunf, nightc)
	var tg10 := ta10 - GROUND_K * nightc
	var dew := src[S_DEW]
	if rain > 0.05:
		dew = 0.0                                     # za deště je mokro z deště (Weather.wetness), ne rosa
	elif tg10 < td_air:
		dew = minf(dew + DEW_RATE_H * clampf((td_air - tg10) / 2.0, 0.0, 1.0) * dt, 1.0)
	else:
		var dry_r := DEW_DRY_H * (0.1 + 3.0 * sunf * sunf + 0.05 * wind) * clampf((tg10 - td_air) / 2.0 + 0.3, 0.3, 1.0)
		dew = maxf(dew - dry_r * dt, 0.0)
	dst[S_DEW] = dew
	if track:
		_track_stats(t_ref, inv, sunf, nightc)


## Noční minima v kotlině a na hřebeni (deník J). Noc se uzavře v poledne.
func _track_stats(t_ref: float, inv: float, sunf: float, nightc: float) -> void:
	var tv := _t_model(valley_elev, 0.0, 0.8, 0.0, 0.0, 0.0, 0.0, 1.0, t_ref, inv, sunf, nightc)
	var tr := _t_model(ridge_elev, ridge_hand, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, t_ref, inv, sunf, nightc)
	var h := clock.hour()
	if h >= 12.0 and clock.jd() != _stats_day:
		_stats_day = clock.jd()
		if _nmin_v < INF:
			night_min_valley = _nmin_v
			night_min_ridge = _nmin_r
		_nmin_v = INF
		_nmin_r = INF
	if h >= 18.0 or h < 11.0:
		_nmin_v = minf(_nmin_v, tv)
		_nmin_r = minf(_nmin_r, tr)


## Výška slunce (°) v herní minutě `m` – zjednodušeně (deklinace Cooper 1969, pravé poledne ~ 12 h + DST),
## jen pro hodinový krok a rozběh; přesná poloha pro vzhled je `Clock.sun_enu`.
func _sun_elev_at(m: float) -> float:
	var doy := clock.day_of_year() + (m - clock.minutes) / 1440.0
	var h := fposmod(m / 60.0, 24.0)
	var decl := deg_to_rad(23.44) * sin(TAU * (284.0 + doy) / 365.0)
	var noon := 12.0 + float(clock.utc_offset()) - Clock.LON / 15.0
	var ha := deg_to_rad(15.0 * (h - noon))
	var lat := deg_to_rad(Clock.LAT)
	return rad_to_deg(asin(clampf(sin(lat) * sin(decl) + cos(lat) * cos(decl) * cos(ha), -1.0, 1.0)))


# ------------------------------------------------------------------ model bodu

## Teplota vzduchu 2 m nad zemí v místě se zadanými vlastnostmi.
func _t_model(elev: float, hand: float, cold: float, ridge: float, south: float, forest: float, urban: float,
		near: float, t_ref: float, inv: float, sunf: float, nightc: float) -> float:
	var low := clampf(1.0 - hand / INV_DEPTH_M, 0.0, 1.0)
	var v := clampf(W_LOW * low + W_POOL * cold, 0.0, 1.0) * (1.0 - 0.5 * forest) * (1.0 - 0.5 * urban) \
		* (1.0 - WATER_DAMP * near)
	var t := t_ref - LAPSE_K_M * (elev - ref_elev)
	t -= inv * v
	t += inv * BELT_K * ridge * (1.0 - low)
	t += SOUTH_K * sunf * south * (1.0 - WATER_DAMP * near)
	t += -FOREST_DAY_K * sunf * forest * _e_fol + FOREST_NIGHT_K * nightc * forest
	t += urban * lerpf(URBAN_DAY_K, URBAN_NIGHT_K, nightc)
	return t


## Počasí, slunce a prolínání stavu – jednou za snímek (dotazy pak jen počítají).
func _env() -> void:
	var f := Engine.get_process_frames()
	if f == _e_frame:
		return
	_e_frame = f
	_e_on = enabled()
	if weather == null or clock == null:
		return
	var el := clock.minutes - _t_a
	if el < 0.0 or el > 150.0:
		_snap()
		el = 0.0
	_e_frac = clampf(el / 60.0, 0.0, 1.0)
	_e_tref = weather.temp
	var elev := clock.sun_elevation()
	var clear := 1.0 - smoothstep(CLEAR_FROM, CLEAR_TO, weather.cloud)
	var calm := 1.0 - smoothstep(CALM_FROM_MS, CALM_TO_MS, weather.wind)
	var dry := 1.0 - clampf(weather.rain * 4.0, 0.0, 1.0)
	_e_nightc = clear * calm * dry * (1.0 - smoothstep(0.0, 12.0, elev))
	_e_sunf = clampf(elev / 45.0, 0.0, 1.0) * (1.0 - 0.75 * weather.cloud)
	_e_fol = Seasons.foliage(clock.day_of_year())


func _sv(i: int) -> float:
	return lerpf(_a[i], _b[i], _e_frac)


## Index první vlastnosti místa v `_cv` (buňka CACHE_CELL m); prázdný / cizí slot se dopočítá.
func _slot(x: float, z: float) -> int:
	var ix := floori(x / CACHE_CELL)
	var iz := floori(z / CACHE_CELL)
	var key := (ix + 1048576) * 2097152 + (iz + 1048576)
	var s := ((ix * 73856093) ^ (iz * 19349663)) & (CACHE_N - 1)
	if _ck[s] != key:
		_ck[s] = key
		_fill(s * _NP, (ix + 0.5) * CACHE_CELL, (iz + 0.5) * CACHE_CELL)
	return s * _NP


func _fill(i: int, x: float, z: float) -> void:
	if site != null and site.loaded:
		_cv[i] = site.elev(x, z)
		_cv[i + 1] = site.hand(x, z)
		_cv[i + 2] = site.cold_pool(x, z)
		_cv[i + 3] = clampf(site.tpi(x, z) / TPI_RIDGE_M, 0.0, 1.0)
		_cv[i + 4] = clampf((site.insol(x, z) - INSOL_MEAN) / INSOL_SPAN, -1.0, 1.0)
		_cv[i + 7] = clampf(1.0 - site.dist_water(x, z) / WATER_NEAR_M, 0.0, 1.0)
	else:
		_cv[i] = world.terrain.height_at(x, z) if world != null and world.terrain != null else ref_elev
		_cv[i + 1] = INV_DEPTH_M * 2.0              # bez stanovišť není kam stékat → žádná inverze v bodě
		_cv[i + 2] = 0.0
		_cv[i + 3] = 0.0
		_cv[i + 4] = 0.0
		_cv[i + 7] = 0.0
	var forest := 0.0
	var sm: SurfaceMap = world.surface if world != null else null
	if world != null and world.tree_eco != null:
		forest = world.tree_eco.canopy_at(x, z)
	if sm != null and sm.class_at(x, z) == SurfaceMap.FOREST:
		forest = maxf(forest, 0.8)
	_cv[i + 5] = clampf(forest, 0.0, 1.0)
	var urban := 0.0
	if sm != null:
		for k in 5:                                   # střed + 4 body na kříži ve vzdálenosti URBAN_R_M
			var ox := URBAN_R_M * (1.0 if k == 1 else (-1.0 if k == 2 else 0.0))
			var oz := URBAN_R_M * (1.0 if k == 3 else (-1.0 if k == 4 else 0.0))
			if sm.class_at(x + ox, z + oz) == SurfaceMap.YARD:
				urban += 0.2
	_cv[i + 6] = urban


func _t_slot(i: int) -> float:
	return _t_model(_cv[i], _cv[i + 1], _cv[i + 2], _cv[i + 3], _cv[i + 4], _cv[i + 5], _cv[i + 6], _cv[i + 7],
		_e_tref, _sv(S_INV), _e_sunf, _e_nightc)


func _td_slot(i: int, x: float, z: float) -> float:
	var td := td_air + TD_WATER_K * _cv[i + 7] + TD_FOREST_K * _cv[i + 5]
	var sw: SoilWater = world.soil_water if world != null else null
	if sw != null and sw.active():
		td += TD_SOIL_K * (sw.moisture_at(x, z) - 0.5)
	return td


static func _es(t: float) -> float:
	return 6.112 * exp(MAGNUS_A * t / (MAGNUS_B + t))


# ------------------------------------------------------------------ API (00_PRINCIPY kap. 3)

## Teplota vzduchu 2 m nad zemí v bodě (°C). Vypnuto = `Weather.temp`.
func temp_at(pos: Vector3) -> float:
	if weather == null:
		return 12.0
	_env()
	if not _e_on:
		return weather.temp
	return _t_slot(_slot(pos.x, pos.z))


## Přízemní teplota (tráva, povrch) – za jasné bezvětrné noci o `GROUND_K` níž než ve 2 m.
func ground_temp_at(pos: Vector3) -> float:
	if weather == null:
		return 12.0
	_env()
	if not _e_on:
		return weather.temp
	var i := _slot(pos.x, pos.z)
	return _t_slot(i) - GROUND_K * _e_nightc * (1.0 - 0.7 * _cv[i + 5])


## Rosný bod v bodě (°C, Magnus) – nejvýš teplota vzduchu (přebytek zkondenzuje do mlhy / rosy).
func dewpoint_at(pos: Vector3) -> float:
	if weather == null:
		return 5.0
	_env()
	if not _e_on:
		return minf(td_air, weather.temp)
	var i := _slot(pos.x, pos.z)
	return minf(_td_slot(i, pos.x, pos.z), _t_slot(i))


## Relativní vlhkost 0..1 v bodě (Magnus: e(Td) / e(T)).
func humidity_at(pos: Vector3) -> float:
	if weather == null:
		return 0.7
	_env()
	var t := temp_at(pos)
	return clampf(_es(dewpoint_at(pos)) / _es(t), 0.05, 1.0)


## Mlha 0..1 v bodě: radiační vrstva ode dna údolí do `fog_top_m()` (podle Site.hand) a advekční /
## frontální `Weather.fog` všude. Vypnuto = `Weather.fog`.
func fog_at(pos: Vector3) -> float:
	if weather == null:
		return 0.0
	_env()
	if not _e_on:
		return weather.fog
	var top := _sv(S_FOG_TOP)
	if top < 0.5:
		return weather.fog
	var i := _slot(pos.x, pos.z)
	var rad := _sv(S_FOG_DENS) * (1.0 - smoothstep(top - FOG_EDGE_M, top + 2.0, _cv[i + 1]))
	return maxf(rad, weather.fog)


## Přízemní mráz 0..1 (0,5 ≈ tráva na 0 °C, 1 = −1,5 °C a míň) – květy, plodiny, jinovatka.
func frost_at(pos: Vector3) -> float:
	return smoothstep(1.0, -1.5, ground_temp_at(pos))


## Rosa / jinovatka na trávě 0..1 (ráno, mizí sluncem). Vypnuto = 0 (jako dřív).
func dew_at(pos: Vector3) -> float:
	if weather == null:
		return 0.0
	_env()
	if not _e_on:
		return 0.0
	var i := _slot(pos.x, pos.z)
	var low := clampf(1.0 - _cv[i + 1] / INV_DEPTH_M, 0.0, 1.0)
	return clampf(_sv(S_DEW) * (0.6 + 0.4 * low) * (1.0 - 0.8 * _cv[i + 5]) * (1.0 - 0.7 * _cv[i + 6]), 0.0, 1.0)


## Je rosa v bodě zmrzlá (jinovatka)? 0..1 podle přízemní teploty.
func hoarfrost_at(pos: Vector3) -> float:
	return dew_at(pos) * frost_at(pos)


## Podíl srážek, které v bodě padají jako sníh (0 déšť … 1 sníh) – sněžení vs. déšť podle výšky.
func snow_at(pos: Vector3) -> float:
	if weather == null:
		return 0.0
	return smoothstep(Weather.SNOW_BELOW + 1.0, Weather.SNOW_BELOW - 1.0, temp_at(pos))


## Výška (svět Y), nad kterou srážky padají jako sníh (za srážek inverze není → jen gradient).
func snow_line_y() -> float:
	if weather == null:
		return 0.0
	return ref_elev + (weather.temp - Weather.SNOW_BELOW) / LAPSE_K_M


## Rychlost větru 10 m nad zemí v bodě (m/s) – z `WindField` (závětří, hřebeny), jinak `Weather.wind`.
func wind_speed_at(pos: Vector3) -> float:
	if weather == null:
		return 0.0
	if world != null and world.wind_field != null:
		var v := world.wind_field.wind_at(pos, 10.0)
		return Vector2(v.x, v.z).length()
	return weather.wind


## Pocitová teplota (°C, JAG/TI): platí pro T ≤ 10 °C a vítr > 4,8 km/h, jinak teplota vzduchu.
func wind_chill_at(pos: Vector3) -> float:
	var t := temp_at(pos)
	var v := wind_speed_at(pos) * 3.6
	if t > 10.0 or v <= 4.8:
		return t
	var vp := pow(v, 0.16)
	return 13.12 + 0.6215 * t - 11.37 * vp + 0.3965 * t * vp


## Síla přízemní inverze (K) – kouř z komínů, ladění.
func inversion() -> float:
	_env()
	return _sv(S_INV) if _e_on else 0.0


## Horní hranice radiační mlhy nad dnem údolí (m; 0 = mlha není).
func fog_top_m() -> float:
	_env()
	return _sv(S_FOG_TOP) if _e_on else 0.0


## Hustota mlžné vrstvy 0..1.
func fog_layer() -> float:
	_env()
	return _sv(S_FOG_DENS) if _e_on else 0.0


## Do jaké výšky nad dnem údolí je zem zmrzlá (m); `NO_FROST_M` = na dně nemrzne, `ALL_FROST_M` = všude.
func frost_top_m() -> float:
	_env()
	return _sv(S_FROST_TOP) if _e_on else NO_FROST_M


## Rosa na louce v údolí 0..1 (globální stav – pro shader `micro_dew`).
func dew_amount() -> float:
	_env()
	return _sv(S_DEW) if _e_on else 0.0


## Výška dna údolí pod bodem (svět Y = výška − HAND); NAN bez stanovišť.
func floor_y_at(x: float, z: float) -> float:
	if site == null or not site.loaded:
		return NAN
	return site.elev(x, z) - site.hand(x, z)


## Teplota u vodních nádrží (dno údolí, u vody) – zamrzání rybníků a potoků (`Water`).
func temp_valley() -> float:
	if weather == null:
		return 12.0
	_env()
	if not _e_on:
		return weather.temp
	return _t_model(valley_elev, 0.0, 0.5, 0.0, 0.0, 0.0, 0.0, 1.0, _e_tref, _sv(S_INV), _e_sunf, _e_nightc)


## Teplota na typickém hřbetu katastru.
func temp_ridge() -> float:
	if weather == null:
		return 12.0
	_env()
	if not _e_on:
		return weather.temp
	return _t_model(ridge_elev, ridge_hand, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, _e_tref, _sv(S_INV), _e_sunf, _e_nightc)


# ------------------------------------------------------------------ HUD a deník

## Řádek počasí do HUD s teplotou v místě hráče a ikonou mlhy / mrazu (přepočet nejvýš po `HUD_MS`).
func hud_line(pos: Vector3) -> String:
	if weather == null:
		return ""
	var now := Time.get_ticks_msec()
	if now - _hud_ms < HUD_MS and pos.distance_squared_to(_hud_pos) < 16.0:
		return _hud_txt
	_hud_ms = now
	_hud_pos = pos
	var txt := weather.describe()
	var ic := weather.icon()
	_env()
	if _e_on:
		var t := roundi(temp_at(pos))
		txt = txt.replace("%d °C" % roundi(weather.temp), "%d °C" % t)
		if fog_at(pos) > 0.35 and weather.fog < 0.35:
			ic += "≡"
			txt += " · mlha v údolí"
		var d := dew_at(pos)
		if frost_at(pos) > 0.5:
			ic += "❄" if ic.find("❄") < 0 else ""
			txt += " · jinovatka" if d > 0.25 else " · přízemní mráz"
		elif d > 0.3:
			txt += " · rosa"
	_hud_txt = "%s  %s" % [ic, txt]
	return _hud_txt


## Věta do deníku J (oddíl Počasí): rozdíl mezi kotlinou a hřbetem minulou noc.
func journal_line() -> String:
	if not enabled() or is_nan(night_min_valley) or is_nan(night_min_ridge):
		return ""
	var v := roundi(night_min_valley)
	var r := roundi(night_min_ridge)
	if night_min_valley < 0.0 and night_min_ridge >= 0.0:
		return "V údolí v noci mrzlo (%d °C), na kopci ne (%d °C)." % [v, r]
	if night_min_ridge - night_min_valley >= 3.0:
		return "V noci se v údolí držel studený vzduch: dole %d °C, na kopci %d °C." % [v, r]
	return "Noc: v údolí %d °C, na kopci %d °C." % [v, r]


# ------------------------------------------------------------------ ladění (F2 → Příroda – ladění)

## Vrstva „teplota“: odchylka od Weather.temp – kotliny modré, teplé svahy a obec červené.
func debug_temp(x: float, z: float) -> Color:
	if weather == null or not enabled():
		return Color(0, 0, 0, 0)
	var d := temp_at(Vector3(x, 0.0, z)) - weather.temp
	var k := clampf(absf(d) / 6.0, 0.0, 1.0)
	if d < 0.0:
		return Color(0.15, 0.35, 1.0, 0.1 + 0.6 * k)
	return Color(1.0, 0.35, 0.1, 0.1 + 0.6 * k)


func debug_fog(x: float, z: float) -> Color:
	if weather == null or not enabled():
		return Color(0, 0, 0, 0)
	var f := fog_at(Vector3(x, 0.0, z))
	return Color(0.92, 0.94, 0.97, f * 0.85) if f > 0.02 else Color(0, 0, 0, 0)


func debug_frost(x: float, z: float) -> Color:
	if weather == null or not enabled():
		return Color(0, 0, 0, 0)
	var f := frost_at(Vector3(x, 0.0, z))
	return Color(0.55, 0.85, 1.0, f * 0.8) if f > 0.02 else Color(0, 0, 0, 0)


## Text do F2 → Příroda – ladění.
func debug_text() -> String:
	return "Inverze %.1f K · mlha do %.0f m (hustota %.2f) · mráz do %s · rosa %.2f · Td %.1f °C\nÚdolí %.1f °C, hřbet %.1f °C (ref. %.1f °C)" % [
		inversion(), fog_top_m(), fog_layer(),
		"–" if frost_top_m() <= NO_FROST_M + 1.0 else "%.0f m" % frost_top_m(), dew_amount(), td_air,
		temp_valley(), temp_ridge(), weather.temp if weather else 0.0]


# ------------------------------------------------------------------ ukládání (klíč `micro`)

func to_dict() -> Dictionary:
	return {"a": Array(_a), "b": Array(_b), "t_a": _t_a, "td": td_air, "tm": t_mean,     # NAN do JSON nejde → 9999
		"nv": 9999.0 if is_nan(night_min_valley) else night_min_valley,
		"nr": 9999.0 if is_nan(night_min_ridge) else night_min_ridge}


## Starý save bez klíče → první dotaz / eco_hour udělá rozběh (`_snap`).
func restore(d: Dictionary) -> void:
	var a: Array = d.get("a", [])
	var b: Array = d.get("b", [])
	if a.size() != NV or b.size() != NV:
		_t_a = -1.0e12
		return
	for i in NV:
		_a[i] = float(a[i])
		_b[i] = float(b[i])
	_t_a = float(d.get("t_a", -1.0e12))
	td_air = float(d.get("td", td_air))
	t_mean = float(d.get("tm", t_mean))
	var nv := float(d.get("nv", 9999.0))
	var nr := float(d.get("nr", 9999.0))
	night_min_valley = NAN if nv > 9000.0 else nv
	night_min_ridge = NAN if nr > 9000.0 else nr
