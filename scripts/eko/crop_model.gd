## M8.12 Plodiny podle růstového modelu (00_PRINCIPY kap. 8: zjednodušený WOFOST / „light use efficiency“).
##
## Statické funkce + tabulka `data/plodiny.json` (zahradní i polní plodiny). Stav **jedné rostliny / buňky záhonu /
## pole** je malý slovník (ukládá se do savu tak, jak je):
##   `k` plodina, `y` rok sklizně, `sow` den výsevu (den v roce), `st` fáze (`ST_*`), `gdd` suma teplot od výsevu,
##   `bm` biomasa (g sušiny / m²), `lai` index listové plochy, `ws` / `ts` dnešní stres vody / teploty (1 = žádný),
##   `wa` klouzavý průměr stresu vody (barva pole), `yp` potenciál výnosu 0..1 (stres při kvetení, horko),
##   `dd` dní silného sucha za sebou, `dm` dní od dozrání, `dead` 0 žije / 1 mráz / 2 sucho, `harv` den sklizně (−1).
##
## Model (denní krok `step_day`):
##   - **fáze podle GDD** se základem plodiny (`tbase`): klíčí → roste → kvete → dozrává → zralé → přezrálé;
##     sucho po odkvětu vývoj zrychlí (`DROUGHT_ACCEL` – v suchém létě se žne dřív);
##   - **přírůstek biomasy = RUE × PAR × (1 − e^(−k·LAI)) × min(stres vody, stres teploty) × světlo** (stín, plevel);
##     LAI = SLA × listová část biomasy (do `lai_max`), po odkvětu listy stárnou (`LAI_SENESCE_D`);
##   - **stres vody** z vlhkosti půdy 0..1 (`SoilWater.moisture_at`): pod `DRY_FROM_M` × nárok klesá k `WILT_M`,
##     nad `WET_FROM_M` zamokření citlivých plodin; **mráz** pod `mraz` zabije (ozimy přežijí), **horko** nad `horko`
##     při kvetení sníží potenciál výnosu;
##   - **výnos** = sklizňový index × biomasa × potenciál (g/m²) → počet kusů / kg vůči **klimatickému normálu** (`clim`:
##     stejný model s normálovými teplotami `Seasons.TEMP_MEAN`, zářením z oblačnosti a vlhkou půdou).
## Záření: hodinově `Atmosphere.SkyModel.global_horizontal_irradiance_wm2` (M8.5) v `DayAcc`, fallback Ångström
## z extraterestrického záření (`SoilWater.extraterrestrial_mj`) a oblačnosti. Vstupy dodává volající (zahrada, pole) –
## model sám na svět nesahá, takže je levný a deterministický. Hodnoty „odhad – ověřit“ (viz `data/plodiny.json`).
class_name CropModel
extends RefCounted

const PATH := "res://data/plodiny.json"

const ST_GERM := 0
const ST_VEG := 1
const ST_FLOWER := 2
const ST_FILL := 3
const ST_RIPE := 4
const ST_OVER := 5
const STAGE_NAMES := ["klíčí", "roste", "kvete", "dozrává", "zralé", "přezrálé"]
## [jednotné, množné] – „Brambory kvetou“, „Mrkev roste“ (fáze 2 může přepsat `faze2` v datech).
const STAGE_VERBS := [["klíčí", "klíčí"], ["roste", "rostou"], ["kvete", "kvetou"], ["dozrává", "dozrávají"],
	["je zralá", "jsou zralé"], ["přezrává", "přezrávají"]]
const CLIM_DAYS := 400                   # klimatický normál: nejdelší sezóna (ozimy od září do srpna)

## M8.12: laditelné (F3 → Příroda/Plodiny a zahrada) – `static var`, výchozí = kalibrace na normál.
static var PAR_FRAC := 0.5               # podíl PAR v globálním záření
static var BM0_GM2 := 3.0                # g/m² – biomasa při vzejití (osivo / sadba)
static var LEAF_FRAC := 0.5              # podíl biomasy v listech do odkvětu (LAI = SLA × listy)
static var SLA_M2_G := 0.02              # m² listů na g listové sušiny
static var LAI_SENESCE_D := 0.03         # podíl LAI, který po odkvětu denně zestárne
static var WILT_M := 0.0                 # vlhkost půdy (podíl AWC) – bod vadnutí, růst 0 (AWC už je nad bodem vadnutí; M8.19: 0,12 → 0)
static var DRY_FROM_M := 0.35            # pod touto vlhkostí (× nárok plodiny) začíná stres suchem
static var WET_FROM_M := 0.9             # nad touto vlhkostí zamokření u citlivých plodin
static var WATERLOG_K := 0.6             # zamokření při plně nasycené půdě ubere tolik růstu
static var TMAX_C := 38.0                # °C – denní průměr, při kterém růst ustane (horní mez teplotního stresu)
static var HEAT_SPAN_C := 6.0            # °C – horko nad prahem plodiny: plná ztráta za den o tolik výš
static var HEAT_LOSS_D := 0.08           # ztráta potenciálu výnosu za den plného horka při kvetení
static var FLOWER_STRESS_D := 0.03       # ztráta potenciálu za den plného stresu (voda / teplota) při kvetení
static var FILL_STRESS_D := 0.01         # … při dozrávání
static var YP_MIN := 0.15                # potenciál výnosu nejméně
static var DROUGHT_ACCEL := 0.6          # sucho po odkvětu zrychlí vývoj (× (1 − stres vody))
static var DEAD_WS := 0.08               # stres vody pod tímto = „úplné sucho“ (počítá se do `sucho_dni`)
static var FROST_SENSITIVE_C := -1.5     # plodiny s `mraz` ≥ tomuto zmrznou i přízemním mrazem (frost_at)
static var FROST_KILL_AT := 0.75         # Microclimate.frost_at, při kterém přízemní mráz zabije citlivé plodiny
static var WA_RATE := 0.15               # klouzavý průměr stresu vody (barva pole) – váha dnešního dne
static var CLIM_MOIST := 0.3             # klimatický normál: vlhkost půdy (M8.19: 0,6 → 0,3 – běžný rok ≈ normál, `tools/eco_calibrate.py`)
static var CLIM_CLOUD := 0.6             # klimatický normál: oblačnost (M8.19: 0,5 → 0,6 = průměr herního počasí)
static var ANGSTROM_A := 0.25            # Ångström: záření = Ra × (A + B × (1 − oblačnost))
static var ANGSTROM_B := 0.5
static var DAY_MIN_HOURS := 12           # DayAcc: tolik hodinových vzorků, aby se den počítal ze skutečného počasí

static var _specs := {}
static var _loaded := false
static var _clim := {}                   # klíč plodiny → normál (viz `clim`)
static var gen := 0                      # zvýší se při změně parametrů (F3) – odběratelé si přepočítají odvozené hodnoty


## Denní souhrn z hodinových vzorků (teplota, záření) – zahrada má jeden na záhon, pole jeden společný.
class DayAcc:
	var n := 0
	var tsum := 0.0
	var tmin := INF
	var tmax := -INF
	var rad_j := 0.0                     # J/m² globálního záření za den

	func add(t: float, ghi_wm2: float, dt_h: float) -> void:
		n += 1
		tsum += t
		tmin = minf(tmin, t)
		tmax = maxf(tmax, t)
		rad_j += maxf(ghi_wm2, 0.0) * 3600.0 * dt_h

	func valid() -> bool:
		return n >= CropModel.DAY_MIN_HOURS

	func mean() -> float:
		return tsum / float(n) if n > 0 else 0.0

	func rad_mj() -> float:
		return rad_j * 1e-6

	func reset() -> void:
		n = 0
		tsum = 0.0
		tmin = INF
		tmax = -INF
		rad_j = 0.0


# ------------------------------------------------------------------ data

static func _load() -> void:
	_loaded = true
	_specs.clear()
	if not FileAccess.file_exists(PATH):
		push_warning("CropModel: chybí %s" % PATH)
		return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not (d is Dictionary):
		push_warning("CropModel: %s nejde přečíst" % PATH)
		return
	for grp in ["zahrada", "pole"]:
		var g: Dictionary = (d as Dictionary).get(grp, {})
		for k in g:
			var sp: Dictionary = g[k]
			sp["skupina"] = grp
			_specs[String(k)] = sp


## Všechny plodiny (klíč → slovník z `data/plodiny.json`). Slovníky jsou sdílené – F3 je ladí přímo.
static func specs() -> Dictionary:
	if not _loaded:
		_load()
	return _specs


static func spec(key: String) -> Dictionary:
	return specs().get(key, {})


static func has(key: String) -> bool:
	return specs().has(key)


## Plodina se modeluje (ne `kalendar`)?
static func modeled(key: String) -> bool:
	var sp := spec(key)
	return not sp.is_empty() and not bool(sp.get("kalendar", false))


## Změna parametrů v F3: zahodit normály, odběratelé si přepočítají odvozené hodnoty (`gen`).
static func invalidate() -> void:
	_clim.clear()
	gen += 1


static func gdd_at(sp: Dictionary, i: int) -> float:
	var g: Array = sp.get("gdd", [100, 600, 900, 1200])
	return float(g[clampi(i, 0, g.size() - 1)])


# ------------------------------------------------------------------ stav a krok

static func new_state(key: String, sow_doy: float, year: int) -> Dictionary:
	return {"k": key, "y": year, "sow": sow_doy, "st": ST_GERM, "gdd": 0.0, "bm": 0.0, "lai": 0.0, "ws": 1.0, "ts": 1.0,
		"wa": 1.0, "yp": 1.0, "dd": 0, "dm": 0, "dead": 0, "harv": -1}


## Fáze podle sumy teplot a dní od dozrání.
static func stage_of(sp: Dictionary, gdd: float, dm: int) -> int:
	if gdd < gdd_at(sp, 0):
		return ST_GERM
	if gdd < gdd_at(sp, 1):
		return ST_VEG
	if gdd < gdd_at(sp, 2):
		return ST_FLOWER
	if gdd < gdd_at(sp, 3):
		return ST_FILL
	return ST_OVER if dm > int(sp.get("prezrale", 20)) else ST_RIPE


## Stres vody 0..1 (1 = žádný) z vlhkosti půdy 0..1 (vůči AWC).
static func water_stress(sp: Dictionary, moist: float) -> float:
	var from := DRY_FROM_M * float(sp.get("voda", 1.0))
	var ws := clampf((moist - WILT_M) / maxf(from - WILT_M, 0.01), 0.0, 1.0)
	if bool(sp.get("zamok", false)) and moist > WET_FROM_M:
		ws *= 1.0 - WATERLOG_K * clampf((moist - WET_FROM_M) / maxf(1.0 - WET_FROM_M, 0.01), 0.0, 1.0)
	return ws


## Teplotní stres 0..1 z denního průměru: 0 pod základem, 1 v optimu, 0 u `TMAX_C`.
static func temp_stress(sp: Dictionary, t: float) -> float:
	var base := float(sp.get("tbase", 5.0))
	var topt: Array = sp.get("topt", [base + 10.0, 25.0])
	var lo := float(topt[0])
	var hi := float(topt[1])
	if t <= base or t >= TMAX_C:
		return 0.0
	if t < lo:
		return (t - base) / maxf(lo - base, 0.1)
	if t > hi:
		return 1.0 - (t - hi) / maxf(TMAX_C - hi, 0.1)
	return 1.0


## Zmrzne rostlina? Vzduch pod `mraz`, nebo u citlivých plodin přízemní mráz (`frost` = Microclimate.frost_at, −1 = neznámý).
## Klíčící semeno v zemi mráz nezabije – sazenici (`sadba`, rajčata) ano.
static func frost_kills(sp: Dictionary, s: Dictionary, t_min: float, frost := -1.0) -> bool:
	if int(s.get("dead", 0)) != 0 or int(s.get("harv", -1)) >= 0:
		return false
	if int(s.get("st", 0)) == ST_GERM and not bool(sp.get("sadba", false)):
		return false
	var kill := float(sp.get("mraz", -2.0))
	if t_min < kill:
		return true
	return kill >= FROST_SENSITIVE_C and frost >= FROST_KILL_AT


## Jeden den růstu. `light` = podíl světla (1 − stín) × (1 − plevel), `growth_mul` = hnojení apod.
## Vrací `dead` (0 žije, 1 mráz, 2 sucho).
static func step_day(s: Dictionary, sp: Dictionary, t_mean: float, t_min: float, t_max: float, rad_mj: float,
		moist: float, light := 1.0, growth_mul := 1.0) -> int:
	if int(s.get("dead", 0)) != 0 or int(s.get("harv", -1)) >= 0:
		return int(s.get("dead", 0))
	if frost_kills(sp, s, t_min):
		s["dead"] = 1
		return 1
	var base := float(sp.get("tbase", 5.0))
	var cap := float(sp.get("tcap", 30.0))
	var st := int(s.get("st", ST_GERM))
	var ws := water_stress(sp, moist)
	var ts := temp_stress(sp, t_mean)
	s["ws"] = ws
	s["ts"] = ts
	s["wa"] = lerpf(float(s.get("wa", 1.0)), ws, WA_RATE)
	# vývoj (GDD); po odkvětu sucho dozrávání urychlí
	var dg := clampf(t_mean, base, cap) - base
	if st >= ST_FLOWER and st < ST_RIPE:
		dg *= 1.0 + DROUGHT_ACCEL * (1.0 - ws)
	var gdd := float(s.get("gdd", 0.0)) + dg
	s["gdd"] = gdd
	if st >= ST_RIPE:
		s["dm"] = int(s.get("dm", 0)) + 1
	var nst := stage_of(sp, gdd, int(s.get("dm", 0)))
	if st == ST_GERM and nst > ST_GERM:
		s["bm"] = BM0_GM2
	s["st"] = nst
	if nst == ST_GERM:
		return 0
	# úplné sucho dlouho = uschne (klíčící semeno v zemi vydrží)
	if ws < DEAD_WS and nst < ST_RIPE:
		s["dd"] = int(s.get("dd", 0)) + 1
		if int(s["dd"]) > int(sp.get("sucho_dni", 14)):
			s["dead"] = 2
			return 2
	else:
		s["dd"] = 0
	if nst >= ST_RIPE:
		return 0
	# biomasa: RUE × PAR × zachycené světlo × stres
	var bm := float(s.get("bm", BM0_GM2))
	var lai := float(s.get("lai", 0.0))
	var intercept := 1.0 - exp(-float(sp.get("k", 0.6)) * lai)
	var par := rad_mj * PAR_FRAC * clampf(light, 0.0, 1.0)
	var dbm := float(sp.get("rue", 2.5)) * par * maxf(intercept, 0.01) * minf(ws, ts) * maxf(growth_mul, 0.0)
	bm += dbm
	s["bm"] = bm
	if nst < ST_FILL:
		lai = minf(float(sp.get("lai_max", 4.0)), maxf(lai, SLA_M2_G * LEAF_FRAC * bm))
	else:
		lai *= 1.0 - LAI_SENESCE_D
	s["lai"] = lai
	# potenciál výnosu: stres při kvetení / dozrávání, horko při kvetení
	var yp := float(s.get("yp", 1.0))
	var stress := 1.0 - minf(ws, ts)
	if nst == ST_FLOWER:
		yp -= FLOWER_STRESS_D * stress
		var heat := float(sp.get("horko", 32.0))
		if t_max > heat:
			yp -= HEAT_LOSS_D * clampf((t_max - heat) / HEAT_SPAN_C, 0.0, 1.0)
	elif nst == ST_FILL:
		yp -= FILL_STRESS_D * stress
	s["yp"] = maxf(yp, YP_MIN)
	return 0


## Výnos (g sušiny úrody / m²) = sklizňový index × biomasa × potenciál.
static func yield_g_m2(s: Dictionary, sp: Dictionary) -> float:
	if int(s.get("dead", 0)) != 0:
		return 0.0
	return float(sp.get("hi", 0.5)) * float(s.get("bm", 0.0)) * float(s.get("yp", 1.0))


## Výnos vůči normálu (1 = běžný rok; 0,4 = slabý, 1,3 = výborný).
static func yield_ratio(s: Dictionary, sp: Dictionary, key: String) -> float:
	var c := clim(key)
	var ref: float = c.get("yield", 0.0)
	return yield_g_m2(s, sp) / ref if ref > 0.0 else 1.0


## Výnos, jaký by byl při sklizni, kdyby zbytek sezóny proběhl normálně: biomasa vůči normálu ve stejné fázi × potenciál.
static func yield_forecast_ratio(s: Dictionary, sp: Dictionary, key: String) -> float:
	if int(s.get("dead", 0)) != 0:
		return 0.0
	return clampf(vigor(s, key), 0.0, 1.6) * float(s.get("yp", 1.0))


## Vzrůst: biomasa vůči normálu při stejné sumě teplot (1 = jako obvykle, 0,5 = zakrslé).
static func vigor(s: Dictionary, key: String) -> float:
	if int(s.get("st", 0)) == ST_GERM:
		return 1.0
	var c := clim(key)
	var gd: PackedFloat32Array = c.get("gdd", PackedFloat32Array())
	if gd.is_empty():
		return 1.0
	var i := clim_index_for_gdd(c, float(s.get("gdd", 0.0)))
	var bmc: PackedFloat32Array = c["bm"]
	var ref := bmc[i]
	return float(s.get("bm", 0.0)) / ref if ref > 1.0 else 1.0


## Výška porostu jako podíl dospělé výšky (roste do odkvětu, × vzrůst).
static func height_frac(s: Dictionary, sp: Dictionary, key: String) -> float:
	if int(s.get("dead", 0)) != 0 or int(s.get("harv", -1)) >= 0:
		return 0.0
	var st := int(s.get("st", 0))
	if st == ST_GERM:
		return 0.0
	var dev := clampf(float(s.get("gdd", 0.0)) / maxf(gdd_at(sp, 1), 1.0), 0.0, 1.0)
	return smoothstep(0.0, 1.0, dev) * clampf(vigor(s, key), 0.4, 1.15)


## Věta pro hráče: „Brambory kvetou, půda je suchá.“
static func status_text(s: Dictionary, sp: Dictionary, moist: float) -> String:
	var nm := String(sp.get("nazev", "Plodina"))
	var pl := 1 if bool(sp.get("mn", false)) else 0
	var st := int(s.get("st", 0))
	if int(s.get("dead", 0)) == 1:
		return "%s %s." % [nm, "zmrzla" if pl == 0 else "zmrzly"]
	if int(s.get("dead", 0)) == 2:
		return "%s %s." % [nm, "uschla" if pl == 0 else "uschly"]
	var verb: String = STAGE_VERBS[st][pl]
	if st == ST_FLOWER and sp.has("faze2"):
		verb = String(sp["faze2"][pl])
	if st >= ST_RIPE:
		return "%s – %s, sklidit." % [nm, STAGE_NAMES[st]]
	return "%s %s, %s." % [nm, verb, soil_text(moist)]


static func soil_text(moist: float) -> String:
	if moist < 0.22:
		return "půda je vyprahlá"
	if moist < 0.4:
		return "půda je suchá"
	if moist < 0.8:
		return "půda je vlhká"
	return "půda je rozmočená"


# ------------------------------------------------------------------ klimatický normál

## Normálová teplota (denní průměr a rozkmit) a záření pro den v roce.
static func clim_temp(doy: float) -> float:
	return Seasons.monthly(Seasons.TEMP_MEAN, doy)


static func clim_range(doy: float) -> float:
	return Seasons.monthly(Seasons.TEMP_RANGE, doy) * 0.8


## Denní globální záření (MJ/m²) podle Ångströma z extraterestrického záření a oblačnosti.
static func clim_rad_mj(doy: float, cloud: float) -> float:
	return SoilWater.extraterrestrial_mj(doy) * (ANGSTROM_A + ANGSTROM_B * (1.0 - clampf(cloud, 0.0, 1.0)))


## Normál plodiny: denní řady `gdd`, `bm`, `lai`, `yp` od výsevu (střed `seti`), `mat` = index dozrání, `yield` g/m².
## Počítá se jednou (na požádání), ~400 kroků na plodinu.
static func clim(key: String) -> Dictionary:
	if _clim.has(key):
		return _clim[key]
	var sp := spec(key)
	var out := {"gdd": PackedFloat32Array(), "bm": PackedFloat32Array(), "lai": PackedFloat32Array(),
		"yp": PackedFloat32Array(), "mat": CLIM_DAYS - 1, "yield": 0.0, "sow": 100.0}
	if sp.is_empty():
		_clim[key] = out
		return out
	var seti: Array = sp.get("seti", [100, 110])
	var sow := (float(seti[0]) + float(seti[1])) * 0.5
	out["sow"] = sow
	var s := new_state(key, sow, 0)
	var gd: PackedFloat32Array = out["gdd"]
	var bm: PackedFloat32Array = out["bm"]
	var la: PackedFloat32Array = out["lai"]
	var yp: PackedFloat32Array = out["yp"]
	gd.resize(CLIM_DAYS)
	bm.resize(CLIM_DAYS)
	la.resize(CLIM_DAYS)
	yp.resize(CLIM_DAYS)
	var mat := -1
	for i in CLIM_DAYS:
		var doy := fposmod(sow + float(i) - 1.0, 365.0) + 1.0
		var t := clim_temp(doy)
		var r := clim_range(doy)
		if mat < 0:
			step_day(s, sp, t, t - r * 0.5, t + r * 0.5, clim_rad_mj(doy, CLIM_CLOUD), CLIM_MOIST)
			s["dead"] = 0                # normál nemrzne (jarní mrazík na vzcházejících by normál rozbil)
			if int(s["st"]) >= ST_RIPE:
				mat = i
				out["yield"] = yield_g_m2(s, sp)
		gd[i] = float(s["gdd"])
		bm[i] = float(s["bm"])
		la[i] = float(s["lai"])
		yp[i] = float(s["yp"])
	out["mat"] = mat if mat >= 0 else CLIM_DAYS - 1
	if mat < 0:
		out["yield"] = yield_g_m2(s, sp)
	out["gdd"] = gd
	out["bm"] = bm
	out["lai"] = la
	out["yp"] = yp
	_clim[key] = out
	return out


## Index dne normálu, kdy suma teplot dosáhne `gdd` (binární hledání).
static func clim_index_for_gdd(c: Dictionary, gdd: float) -> int:
	var gd: PackedFloat32Array = c["gdd"]
	var lo := 0
	var hi := gd.size() - 1
	if hi < 0:
		return 0
	while lo < hi:
		var mid := (lo + hi) >> 1
		if gd[mid] < gdd:
			lo = mid + 1
		else:
			hi = mid
	return lo


## Stav podle normálu `idx` dní po výsevu (start hry uprostřed sezóny, starý save bez stavu modelu).
static func clim_state(key: String, sow_doy: float, year: int, idx: int) -> Dictionary:
	var s := new_state(key, sow_doy, year)
	var c := clim(key)
	var gd: PackedFloat32Array = c["gdd"]
	if gd.is_empty() or idx < 0:
		return s
	var i := clampi(idx, 0, gd.size() - 1)
	var sp := spec(key)
	s["gdd"] = gd[i]
	s["bm"] = (c["bm"] as PackedFloat32Array)[i]
	s["lai"] = (c["lai"] as PackedFloat32Array)[i]
	s["yp"] = (c["yp"] as PackedFloat32Array)[i]
	s["dm"] = maxi(0, i - int(c["mat"]))
	s["st"] = stage_of(sp, gd[i], int(s["dm"]))
	return s


## Hodinové globální záření (W/m²) z oblohy M8.5 – fallback 0 bez hodin.
static func ghi_now(w: World) -> float:
	if w == null or w.clock == null:
		return 0.0
	var wt: Weather = w.weather
	var cloud := wt.cloud if wt != null else 0.3
	var haze := clampf(wt.fog * 0.25 + wt.rain * 0.4, 0.0, 1.0) if wt != null else 0.0
	return Atmosphere.SkyModel.global_horizontal_irradiance_wm2(w.clock.sun_elevation(), cloud, haze)
