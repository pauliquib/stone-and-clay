## Vodní bilance krajiny (M8.7, `World.soil_water`): vlhkost půdy, sníh, povrchový odtok, potoky a bláto.
##
## Podle čeho (00_PRINCIPY kap. 8 „Voda“): kyblíkový model půdní vody (bucket, kapacita = AWC ze `Site`),
## povrchový odtok **SCS Curve Number** (USDA-NRCS TR-55, CN podle hydrologické skupiny půdy a povrchu,
## úprava podle předchozí vlhkosti AMC I/II/III), výpar **Hargreaves & Samani 1985** s extraterestrickým
## zářením podle FAO-56 (rov. 21), tání sněhu **degree-day** (3–5 mm/°C/den), toky jako **lineární nádrže**
## (rychlá povrchová + pomalá podzemní, `Q = S / k`).
##
## Mřížka `CELL` = 32 m přes rozsah `Site` (bez `site.bin` přes terén). Každá buňka má kyblík `w` (mm, 0..AWC)
## a sníh `swe` (mm vodního ekvivalentu). Integrace jen přes `World.eco_hour`: hodiny se sčítají do zásobníku
## srážek / teplot a jeden „průchod“ mřížkou běží po kouscích přes `EcoClock.slice` (`CHUNK_STEP` buněk za snímek,
## nikdy celý katastr v jednom snímku); po průchodu se jednou krokem posunou toky (426 úseků z `water.json`).
## Přebytek nad AWC odtéká podpovrchově po spádnici (D8 na hrubé mřížce, předpočítáno při načtení) do nižší
## buňky; buňky u toku ho předají toku. Povrchový odtok jde rovnou do toku, do kterého buňka po spádnici ústí.
##
## Dotazy pro ostatní (bez alokací, bilineárně): `moisture_at` 0..1 (= w/AWC), `mud_at` 0..1 (vlhkost × jílovitost ×
## holá půda / cesta), `snow_at` (výška sněhu m), `puddle_at` 0..1 (louže), `runoff_at` (mm/h). Toky:
## `st_q` (m³/s), `st_qn` (normál), `st_level` (m vůči normálu), `st_turb` (kalnost 0..1), `st_dry` (vyschlé koryto) –
## čte je `Water.flow_at / level_at` a vizuál hladiny. Fallback (přepínač `soil_water` vypnutý / mřížka se ještě
## staví): `active()` = false a volající padají na dnešní globální chování (`Weather.wetness`).
##
## Zachycení srážek v korunách bere zápoj z `World.tree_eco.canopy_at(x, z)` (M8.3); bez něj z `SurfaceMap` /
## `Fauna.forest_at` (třída les).
class_name SoilWater
extends RefCounted

# ------------------------------------------------------------------ laditelné konstanty

const CELL := 32.0                     # m – hrubá mřížka bilance
const CELL_AREA := CELL * CELL         # m²
const CHUNK_STEP := 48                 # buněk za snímek při hodinovém průchodu (~0,3–0,4 ms; průchod ~30 s z 2 min hodiny)
const CHUNK_INIT := 64                 # buněk za snímek při stavbě mřížky (čte Site + SurfaceMap)
const CHUNK_D8 := 160                  # buněk za snímek při výpočtu spádnic
const CHUNK_OUTLET := 320              # buněk za snímek při hledání toku, do kterého buňka ústí
const STREAMS_PER_FRAME := 24          # úseků toků za snímek při značení koryt do mřížky
const MAX_WALK := 4000                 # nejdelší cesta po spádnici (ochrana proti cyklu)

const LAT_DEG := 49.14                 # zeměpisná šířka (Clock) – extraterestrické záření
const CLIMATE_DT_H := 24.0             # delší krok (dohánění) než tohle → srážky a teplota z klimatu, ne z okamžiku
## Měsíční srážky (mm, střední Morava ~550 mm/rok, normál 1991–2020 zjednodušeně) – rozběh a dlouhé skoky času.
const PRECIP_MM := [26.0, 24.0, 29.0, 35.0, 62.0, 72.0, 80.0, 64.0, 48.0, 36.0, 35.0, 30.0]

const INTERCEPT_MM := 3.0              # zachycení v korunách za srážkovou událost (les, plné olistění)
const INTERCEPT_LEAFLESS := 0.4        # podíl zachycení bez listí (jehličnany, větve)
const DDF_MM := 3.0                    # tání sněhu mm/°C/den (sever, stín)
const DDF_SOUTH_MM := 2.0              # + na jižních svazích (Site.insol_winter)
const MELT_FOREST := 0.7               # v lese taje pomaleji (× DDF)
const RAIN_ON_SNOW := 0.0125           # mm tání na mm deště a °C (teplý déšť do sněhu)
const SNOW_DENSITY := 0.25             # hustota sněhu → výška = swe / 1000 / hustota
const EVENT_GAP_H := 6.0               # hodin bez deště = konec srážkové události (SCS počítá po událostech)
const EVENT_MIN_MM := 0.1              # méně za hodinu = suchá hodina
const S_FROZEN_MM := 8.0               # retence zamrzlé půdy (téměř vše odteče)
const FROST_RATE := 0.012              # zamrzání půdy na °C·h mrazu
const THAW_RATE := 0.02                # tání půdy na °C·h nad nulou
const SNOW_INSULATE_MM := 30.0         # víc sněhu (průměr) = půda pod ním rozmrzá
const ET_BETA_FRAC := 0.5              # pod touto vlhkostí (× AWC) výpar klesá úměrně (stres suchem)
const ET_SNOW := 0.1                   # výpar pod sněhem (× PET)
const INSOL_MEAN := 5200.0             # MJ/m²/rok – průměr Site.insol (výpar svahu = insol / průměr)
const DRAIN_FROM := 0.75               # od této vlhkosti (× AWC) voda pomalu prosakuje dál (polní kapacita)
const K_DRAIN_H := 0.006               # rychlost prosakování (1/h × propustnost)
const GW_FRAC := 0.35                  # podíl prosáklé vody do podzemní (pomalé) nádrže toku (× 0,5 + propustnost)
const TWI_MED := 6.7                   # medián TWI (site.bin) – rozběh: vlhčí údolnice
const TWI_K := 0.06                    # + vlhkost na 1 TWI nad mediánem (rozběh)
const SPINUP_DAYS := 60                # 00/M8.7: „roztočení“ bilance z klimatu
const SPINUP_AWC := 130.0
const SPINUP_KC := 0.85

## Třídy povrchu (`SurfaceMap`: tráva, orná, sad, les, dvůr, břeh, skála, polní cesta).
## CN pro hydrologické skupiny A/B/C/D (TR-55, zjednodušeně).
const CN2 := [
	[39.0, 61.0, 74.0, 80.0],          # tráva / louka
	[67.0, 78.0, 85.0, 89.0],          # orná půda
	[43.0, 65.0, 76.0, 82.0],          # sad / zahrada
	[30.0, 55.0, 70.0, 77.0],          # les
	[77.0, 85.0, 90.0, 92.0],          # zástavba / dvůr
	[60.0, 72.0, 82.0, 88.0],          # břeh / mokřad
	[85.0, 90.0, 93.0, 95.0],          # skála
	[72.0, 82.0, 87.0, 89.0],          # polní cesta
]
## Koeficient výparu podle povrchu (orná: -1 = podle sezóny `Seasons.green`).
const KC := [0.9, -1.0, 0.95, 1.1, 0.35, 1.1, 0.15, 0.4]
## Holá půda / cesta (bláto) 0..1 podle povrchu.
const BARE := [0.45, 1.0, 0.55, 0.6, 0.5, 1.0, 0.05, 1.0]
const BARE_FOREST := 0.6
## Jílovitost (lepivost bláta) podle půdní třídy `Site.SOIL_*`.
const CLAY := [0.75, 0.35, 0.2, 1.0, 0.9, 0.6]
const MUD_FROM := 0.55                 # vlhkost (× AWC), od které je bláto
const MUD_FULL := 0.95
const PUDDLE_FROM := 0.8               # vlhkost, od které stojí v prohlubních louže
const RUNOFF_PUDDLE := 2.0             # mm/h povrchového odtoku = plné louže

# toky – lineární nádrže
const Q_SPEC := 4.0e-9                 # m³/s na m² povodí (4 l/s/km² – normál průtoku)
const MIN_AREA_M2 := 2.0e5             # nejmenší povodí (normál malých strouh)
const K_QUICK_H := {"river": 30.0, "canal": 20.0, "stream": 10.0, "ditch": 6.0, "drain": 6.0}
## Podzemní (pomalá) nádrž – malé potoky se v suchu vyprázdní za 2–3 týdny, řeka drží měsíce.
const K_SLOW_H := {"river": 1500.0, "canal": 900.0, "stream": 300.0, "ditch": 150.0, "drain": 150.0}
const DEPTH_N := {"river": 0.6, "canal": 0.4, "stream": 0.25, "ditch": 0.15, "drain": 0.15}
## Povodí nad katastrem pro toky, které do mapy přitékají zvenku (začátek u okraje mřížky).
const EXT_AREA_M2 := {"river": 6.0e7, "canal": 5.0e6, "stream": 3.0e6}
const EDGE_M := 200.0
const JOIN_M := 40.0                   # konec úseku blíž než tohle k jinému toku = vlévá se do něj
const LEVEL_MAX := 0.4                 # m – nejvyšší vzestup hladiny (pás vody nevylézá z koryta)
const LEVEL_EXP := 0.4                 # hladina ∝ Q^0,4 (měrná křivka koryta, zjednodušeně)
const DRY_REL := 0.12                  # Q / normál pod tímhle = malý potok (téměř) vyschl
const TURB_FROM := 1.6                 # Q / normál, od kterého voda kalní
const TURB_FULL := 4.0
const TURB_TAU_H := 14.0               # jak rychle se voda vyčistí (h)

# ------------------------------------------------------------------ stav

var world: World
var site: Site
var surface: SurfaceMap
var water: Water
var ready := false                     # mřížka i topologie toků postavené
var gx0 := 0.0
var gz0 := 0.0
var nx := 0
var nz := 0
var n := 0

# buňky (PackedFloat32Array = žádné alokace v průchodu)
var w := PackedFloat32Array()          # mm vody v půdě
var swe := PackedFloat32Array()        # mm vodního ekvivalentu sněhu
var awc := PackedFloat32Array()        # mm kapacita
var mud := PackedFloat32Array()        # 0..1
var runoff := PackedFloat32Array()     # mm/h povrchového odtoku v posledním průchodu
var _inflow := PackedFloat32Array()    # mm podpovrchového přítoku od vyšších buněk (spotřebuje se při průchodu)
var _s1 := PackedFloat32Array()        # retence S (mm) pro AMC I / II / III
var _s2 := PackedFloat32Array()
var _s3 := PackedFloat32Array()
var _perm := PackedFloat32Array()
var _etf := PackedFloat32Array()       # výpar svahu (oslunění / průměr)
var _south := PackedFloat32Array()     # 0..1 jižní svah (tání)
var _forest := PackedFloat32Array()    # 0..1 zápoj lesa (zachycení, výpar, tání)
var _mudk := PackedFloat32Array()      # jílovitost × holá půda
var _twin := PackedFloat32Array()      # TWI 0..1 (louže v prohlubních)
var _cls := PackedByteArray()          # třída povrchu (bez lesa)
var _d8 := PackedInt32Array()          # nižší sousední buňka (-1 = žádná)
var _scell := PackedInt32Array()       # úsek toku v buňce (-1 = žádný)
var _outlet := PackedInt32Array()      # tok, do kterého buňka po spádnici ústí (-1 = bezodtoké)
var _elev := PackedFloat32Array()      # jen pro stavbu (pak se uvolní)
var _disw := PackedFloat32Array()      # jen pro stavbu
var _stamp := PackedInt32Array()       # jen pro stavbu (hledání cyklů)
var _path := PackedInt32Array()        # jen pro stavbu (cesta po spádnici)
## Vrstvy `Site` pro stavbu: [data, u16?, scale, offset] – čtení přímo z bajtů (nejbližší buňka 4 m),
## bez slovníku a bilineáru na každý dotaz (stavba 84 tis. buněk musí být levná).
var _lays: Array = []
const LAY_CODES := ["AWC_", "TWI_", "SOIL", "INSW", "INSY", "ELEV", "DISW"]
const LAY_DEFAULTS := [120.0, TWI_MED, 0.0, 360.0, INSOL_MEAN, 0.0, 9999.0]

# toky (index = pořadí v Water.streams)
var m := 0
var st_q := PackedFloat32Array()       # průtok m³/s (i s přítokem z horních úseků)
var st_qn := PackedFloat32Array()      # normál m³/s
var st_level := PackedFloat32Array()   # m vůči normální hladině
var st_turb := PackedFloat32Array()    # kalnost 0..1
var st_dry := PackedByteArray()        # 1 = vyschlé koryto
var _sq := PackedFloat32Array()        # m³ rychlá nádrž
var _ss := PackedFloat32Array()        # m³ pomalá (podzemní) nádrž
var _qn_own := PackedFloat32Array()
var _kq := PackedFloat32Array()
var _ks := PackedFloat32Array()
var _depth := PackedFloat32Array()
var _is_river := PackedByteArray()
var _area_loc := PackedFloat32Array()  # m² vlastního povodí (buňky v mapě)
var _area_ext := PackedFloat32Array()  # m² povodí za okrajem mapy
var _down := PackedInt32Array()        # úsek, do kterého se vlévá (-1 = opouští mapu)
var _order := PackedInt32Array()       # pořadí výpočtu (od pramenů k ústí)
var _in_q := PackedFloat32Array()      # m³ přítoku do rychlé nádrže za průchod
var _in_s := PackedFloat32Array()      # m³ do pomalé
var _thru := PackedFloat32Array()      # m³/s z horních úseků (pomocné)

# zásobník forcingu (sčítá eco_hour, spotřebuje průchod)
var _acc_h := 0.0
var _acc_rain := 0.0
var _acc_snow := 0.0
var _acc_temp_h := 0.0
var _acc_cloud_h := 0.0
var _acc_event0 := 0.0
var _event_p := 0.0                    # mm deště v probíhající srážkové události
var _dry_h := 99.0
var frost := 0.0                       # zamrzlá půda 0..1 (globálně)
var _m0 := 0.6                         # rozběhová vlhkost (z klimatu)

# probíhající průchod
var _sweeping := false
var _f_dt := 1.0
var _f_rain := 0.0
var _f_snow := 0.0
var _f_temp := 10.0
var _f_pet := 0.0
var _f_event0 := 0.0
var _f_frost := 0.0
var _f_fol := 1.0
var _kc_now := PackedFloat32Array()
var _sum_m := 0.0
var _sum_q := 0.0
var _sum_out := 0.0
var _sum_swe := 0.0
var _cnt := 0

# souhrn posledního průchodu (drought, ladění)
var mean_moist := 0.6
var mean_swe := 0.0
var mean_flow_rel := 1.0
var _pending := {}                     # uložený stav, který čeká na dostavění mřížky


# ------------------------------------------------------------------ stavba

func setup(wd: World) -> void:
	world = wd
	site = wd.site
	surface = wd.surface
	water = wd.water
	if site != null and site.loaded:
		gx0 = site.x0
		gz0 = site.z0
		nx = ceili(site.nx * site.cell / CELL)
		nz = ceili(site.nz * site.cell / CELL)
	elif wd.terrain != null:
		gx0 = wd.terrain.x0
		gz0 = wd.terrain.z0
		nx = ceili((wd.terrain.w - 1) * wd.terrain.spacing / CELL)
		nz = ceili((wd.terrain.h - 1) * wd.terrain.spacing / CELL)
	n = nx * nz
	if n <= 0 or wd.eco == null:
		return
	w.resize(n)
	swe.resize(n)
	awc.resize(n)
	mud.resize(n)
	runoff.resize(n)
	_inflow.resize(n)
	_s1.resize(n)
	_s2.resize(n)
	_s3.resize(n)
	_perm.resize(n)
	_etf.resize(n)
	_south.resize(n)
	_forest.resize(n)
	_mudk.resize(n)
	_twin.resize(n)
	_elev.resize(n)
	_disw.resize(n)
	_cls.resize(n)
	_d8.resize(n)
	_scell.resize(n)
	_scell.fill(-1)
	_outlet.resize(n)
	_outlet.fill(-2)
	_kc_now.resize(8)
	for code in LAY_CODES:
		# Site nemá veřejný přístup k surovým vrstvám – čteme je jen pro jednorázovou stavbu mřížky.
		var l: Dictionary = site._layers.get(code, {}) if site != null and site.loaded else {}
		_lays.append([] if l.is_empty() else [l["data"], int(l["dtype"]) == 1, float(l["scale"]), float(l["offset"])])
	_m0 = _spinup_m0()
	m = water.streams.size() if water != null else 0
	st_q.resize(m)
	st_qn.resize(m)
	st_level.resize(m)
	st_turb.resize(m)
	_sq.resize(m)
	_ss.resize(m)
	_qn_own.resize(m)
	_kq.resize(m)
	_ks.resize(m)
	_depth.resize(m)
	_area_loc.resize(m)
	_area_ext.resize(m)
	_in_q.resize(m)
	_in_s.resize(m)
	_thru.resize(m)
	st_dry.resize(m)
	_is_river.resize(m)
	_down.resize(m)
	_down.fill(-1)
	wd.eco_hour.connect(_on_eco_hour)
	wd.eco.slice(ceili(float(n) / CHUNK_INIT), 1, _init_chunk)


## Zapnuto a postaveno – jinak volající padají na dnešní globální chování.
func active() -> bool:
	return ready and (world == null or world.realism_on("soil_water"))


## Rozběh (00/M8.7): jeden reprezentativní kyblík 60 dnů zpět z klimatu (po dnech, hrubě) → výchozí
## relativní vlhkost; buňky ji pak dostanou posunutou podle TWI (údolnice vlhčí).
func _spinup_m0() -> float:
	var doy := 180.0
	if world != null and world.clock != null:
		doy = world.clock.day_of_year()
	var ww := SPINUP_AWC * 0.75
	for d in SPINUP_DAYS:
		var dd := fposmod(doy - SPINUP_DAYS + d - 1.0, 365.0) + 1.0
		var month := clampi(int((dd - 1.0) / 30.42), 0, 11)
		var p: float = float(PRECIP_MM[month]) / 30.42
		var t := Seasons.monthly(Seasons.TEMP_MEAN, dd)
		var tr := Seasons.monthly(Seasons.TEMP_RANGE, dd) * 0.75
		var pet := hargreaves_mm_day(t, tr, dd)
		if t < 0.0:
			p *= 0.3                                     # v mrazu leží sníh, do půdy jde jen část
		var beta := minf(ww / (ET_BETA_FRAC * SPINUP_AWC), 1.0)
		ww = clampf(ww + p - pet * SPINUP_KC * beta, 0.0, SPINUP_AWC)
	return clampf(ww / SPINUP_AWC, 0.1, 1.0)


## Hargreaves & Samani (1985): PET mm/den z průměrné teploty, denního rozkmitu a extraterestrického záření.
static func hargreaves_mm_day(t_mean: float, t_range: float, doy: float) -> float:
	return maxf(0.0023 * 0.408 * extraterrestrial_mj(doy) * (t_mean + 17.8) * sqrt(maxf(t_range, 0.0)), 0.0)


## FAO-56 rov. 21: extraterestrické záření Ra (MJ/m²/den) pro šířku `LAT_DEG` a den v roce.
static func extraterrestrial_mj(doy: float) -> float:
	var phi := deg_to_rad(LAT_DEG)
	var dr := 1.0 + 0.033 * cos(TAU * doy / 365.0)
	var dec := 0.409 * sin(TAU * doy / 365.0 - 1.39)
	var ws := acos(clampf(-tan(phi) * tan(dec), -1.0, 1.0))
	return 24.0 * 60.0 / PI * 0.082 * dr * (ws * sin(phi) * sin(dec) + cos(phi) * cos(dec) * sin(ws))


func _cell_x(i: int) -> float:
	return gx0 + (float(i % nx) + 0.5) * CELL


func _cell_z(i: int) -> float:
	return gz0 + (float(i / nx) + 0.5) * CELL


## Hodnota vrstvy `k` (`LAY_CODES`) v buňce `site.bin` (nejbližší, bez interpolace).
func _lay(k: int, sidx: int) -> float:
	var l: Array = _lays[k]
	if l.is_empty():
		return LAY_DEFAULTS[k]
	var d: PackedByteArray = l[0]
	var raw := float(d.decode_u16(sidx * 2)) if l[1] else float(d[sidx])
	return float(l[3]) + raw * float(l[2])


## Fáze 1: parametry buněk ze `Site` (AWC, TWI, půda, oslunění, sklon) a `SurfaceMap` (povrch, les).
func _init_chunk(c: int) -> void:
	var t0 := Tests.prof_t0()
	var te: TreeEco = world.tree_eco     # M8.3: zápoj korun 0..1 (mřížka 16 m); null = fallback z povrchu
	var has_te := te != null
	var has_site := site != null and site.loaded
	var snow0 := world.weather.snow_cover if world.weather != null else 0.0
	var i0 := c * CHUNK_INIT
	var i1 := mini(i0 + CHUNK_INIT, n)
	for i in range(i0, i1):
		var x := _cell_x(i)
		var z := _cell_z(i)
		var a := 120.0
		var twi := TWI_MED
		var soil := Site.SOIL_HNEDOZEM
		var insw := 360.0
		var insy := INSOL_MEAN
		var el := 0.0
		var dw := 9999.0
		if has_site:
			var sidx := clampi(int((z - site.z0) / site.cell), 0, site.nz - 1) * site.nx \
				+ clampi(int((x - site.x0) / site.cell), 0, site.nx - 1)
			a = _lay(0, sidx)
			twi = _lay(1, sidx)
			soil = int(_lay(2, sidx))
			insw = _lay(3, sidx)
			insy = _lay(4, sidx)
			el = _lay(5, sidx)
			dw = _lay(6, sidx)
		elif world.terrain != null:
			el = world.terrain.height_at(x, z)
		a = maxf(a, 20.0)
		# povrch: 4 vzorky po 16 m – podíl lesa a převládající ne-lesní třída
		var fo := 0.0
		var cls := SurfaceMap.GRASS
		var got := false
		if surface != null and surface.loaded:
			for k in 4:
				var sx := x + (-8.0 if k % 2 == 0 else 8.0)
				var sz := z + (-8.0 if k < 2 else 8.0)
				var sc := surface.class_at(sx, sz)
				if sc == SurfaceMap.FOREST:
					fo += 0.25
				elif not got:
					cls = sc
					got = true
		elif world.fauna != null:
			fo = clampf(world.fauna.forest_at(x, z), 0.0, 1.0)
		if has_te:
			fo = clampf(te.canopy_at(x, z), 0.0, 1.0)
		cls = clampi(cls, 0, 7)
		var props: Dictionary = Site.SOIL_PROPS.get(soil, Site.SOIL_PROPS[Site.SOIL_HNEDOZEM])
		var perm: float = props["perm"]
		var grp := 0 if perm >= 0.7 else (1 if perm >= 0.45 else (2 if perm >= 0.3 else 3))
		var cn_open: float = CN2[cls][grp]
		var cn_for: float = CN2[SurfaceMap.FOREST][grp]
		var cn := lerpf(cn_open, cn_for, fo)
		_s2[i] = 25400.0 / cn - 254.0
		var cn1 := cn / (2.281 - 0.01281 * cn)
		var cn3 := minf(cn / (0.427 + 0.00573 * cn), 99.0)
		_s1[i] = 25400.0 / cn1 - 254.0
		_s3[i] = 25400.0 / cn3 - 254.0
		_perm[i] = perm
		awc[i] = a
		_etf[i] = clampf(insy / INSOL_MEAN, 0.6, 1.3)
		_south[i] = clampf((insw - 250.0) / 300.0, 0.0, 1.0)
		_forest[i] = fo
		_cls[i] = cls
		var clay: float = CLAY[clampi(soil, 0, CLAY.size() - 1)]
		_mudk[i] = clay * lerpf(float(BARE[cls]), BARE_FOREST, fo)
		_twin[i] = smoothstep(5.0, 11.0, twi)
		_elev[i] = el
		_disw[i] = dw
		var m_i := clampf(_m0 + TWI_K * (twi - TWI_MED), 0.05, 1.0)
		w[i] = a * m_i
		swe[i] = snow0 * 30.0 * (1.0 - 0.5 * _south[i]) if snow0 > 0.02 else 0.0
		mud[i] = smoothstep(MUD_FROM, MUD_FULL, m_i) * _mudk[i]
	Tests.prof_add("soil_water", t0)
	if i1 >= n:
		world.eco.slice(ceili(float(m) / STREAMS_PER_FRAME), 1, _mark_streams_chunk)
		if m == 0:
			world.eco.slice(ceili(float(n) / CHUNK_D8), 1, _d8_chunk)


## Fáze 2: koryta toků do mřížky (buňka, kterou tok protéká, patří toku).
func _mark_streams_chunk(c: int) -> void:
	var s0 := c * STREAMS_PER_FRAME
	var s1 := mini(s0 + STREAMS_PER_FRAME, m)
	for si in range(s0, s1):
		var st: Dictionary = water.streams[si]
		var pts: PackedVector3Array = st["pts"]
		var kind := String(st["kind"])
		_kq[si] = float(K_QUICK_H.get(kind, 10.0))
		_ks[si] = float(K_SLOW_H.get(kind, 300.0))
		_depth[si] = float(DEPTH_N.get(kind, 0.25))
		_is_river[si] = 1 if kind == "river" else 0
		for k in pts.size() - 1:
			var a := pts[k]
			var b := pts[k + 1]
			var steps := maxi(ceili(Vector2(b.x - a.x, b.z - a.z).length() / 8.0), 1)
			for j in steps + 1:
				var t := float(j) / steps
				var ix := floori((lerpf(a.x, b.x, t) - gx0) / CELL)
				var iz := floori((lerpf(a.z, b.z, t) - gz0) / CELL)
				if ix < 0 or iz < 0 or ix >= nx or iz >= nz:
					continue
				var ci := iz * nx + ix
				if _scell[ci] < 0:
					_scell[ci] = si
	if s1 >= m:
		world.eco.slice(ceili(float(n) / CHUNK_D8), 1, _d8_chunk)


## Fáze 3: spádnice D8 (nejstrmější pokles mezi 8 sousedy); bezodtoké buňky (díry hrubé mřížky)
## se pošlou k sousedovi blíž k vodě (`Site.dist_water`).
func _d8_chunk(c: int) -> void:
	var i0 := c * CHUNK_D8
	var i1 := mini(i0 + CHUNK_D8, n)
	for i in range(i0, i1):
		_d8[i] = -1
		if _scell[i] >= 0:
			continue
		var ix := i % nx
		var iz := i / nx
		var e0 := _elev[i]
		var best := -1
		var best_s := 0.0
		var alt := -1
		var alt_d := _disw[i]
		for dz in range(-1, 2):
			var jz := iz + dz
			if jz < 0 or jz >= nz:
				continue
			for dx in range(-1, 2):
				if dx == 0 and dz == 0:
					continue
				var jx := ix + dx
				if jx < 0 or jx >= nx:
					continue
				var j := jz * nx + jx
				var s := (e0 - _elev[j]) / (1.41421 if dx != 0 and dz != 0 else 1.0)
				if s > best_s:
					best_s = s
					best = j
				if _disw[j] < alt_d:
					alt_d = _disw[j]
					alt = j
		_d8[i] = best if best >= 0 else alt
	if i1 >= n:
		_stamp.resize(n)
		_stamp.fill(-1)
		_path.resize(MAX_WALK)
		world.eco.slice(ceili(float(n) / CHUNK_OUTLET), 1, _outlet_chunk)


## Fáze 4: do kterého toku buňka po spádnici ústí (s pamětí – každá buňka se projde jednou).
func _outlet_chunk(c: int) -> void:
	var i0 := c * CHUNK_OUTLET
	var i1 := mini(i0 + CHUNK_OUTLET, n)
	for i in range(i0, i1):
		if _outlet[i] != -2:
			continue
		var plen := 0
		var j := i
		var res := -1
		while true:
			if _outlet[j] != -2:
				res = _outlet[j]
				break
			if _stamp[j] == i or plen >= MAX_WALK:
				res = -1                            # cyklus / moc dlouhá cesta → bezodtoké
				break
			_stamp[j] = i
			_path[plen] = j
			plen += 1
			if _scell[j] >= 0:
				res = _scell[j]
				break
			var r := _d8[j]
			if r < 0:
				res = -1
				break
			j = r
		for k in plen:
			_outlet[_path[k]] = res
			if res >= 0:
				_area_loc[res] += CELL_AREA
	if i1 >= n:
		_finish_topology()


## Fáze 5: kam se který úsek vlévá, povodí, normál průtoku, výchozí zásoby nádrží.
func _finish_topology() -> void:
	_elev = PackedFloat32Array()
	_disw = PackedFloat32Array()
	_stamp = PackedInt32Array()
	_path = PackedInt32Array()
	_lays = []
	var x_max := gx0 + nx * CELL
	var z_max := gz0 + nz * CELL
	for si in m:
		var st: Dictionary = water.streams[si]
		var pts: PackedVector3Array = st["pts"]
		if pts.size() < 2:
			continue
		var down_first := pts[0].y < pts[pts.size() - 1].y     # hladina klesá po proudu
		var e := pts[0] if down_first else pts[pts.size() - 1]
		var u := pts[pts.size() - 1] if down_first else pts[0]
		# přítok zvenku: pramen úseku u okraje mapy
		if u.x - gx0 < EDGE_M or x_max - u.x < EDGE_M or u.z - gz0 < EDGE_M or z_max - u.z < EDGE_M:
			_area_ext[si] = float(EXT_AREA_M2.get(String(st["kind"]), 0.0))
		# vlévá se do nejbližšího jiného úseku u konce
		var best := -1
		var bd := JOIN_M
		var key := Vector2i(floori(e.x / Water.CELL), floori(e.z / Water.CELL))
		var p := Vector2(e.x, e.z)
		for ent in water._cells.get(key, []):
			var s2: int = ent[0]
			if s2 == si:
				continue
			var p2: PackedVector3Array = water.streams[s2]["pts"]
			var a := p2[ent[1]]
			var b := p2[ent[1] + 1]
			var a2 := Vector2(a.x, a.z)
			var ab := Vector2(b.x, b.z) - a2
			var t := clampf((p - a2).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
			var d := p.distance_to(a2 + ab * t)
			if d < bd and lerpf(a.y, b.y, t) <= e.y + 0.5:
				bd = d
				best = s2
		_down[si] = best
	# pořadí od pramenů: počet kroků k ústí (cykly se přeruší)
	var hops := PackedInt32Array()
	hops.resize(m)
	for si in m:
		var h := 0
		var j := _down[si]
		while j >= 0 and h <= m:
			h += 1
			j = _down[j]
		if h > m:
			_down[si] = -1                          # cyklus v datech
			h = 0
		hops[si] = h
	var idx := []
	for si in m:
		idx.append(si)
	idx.sort_custom(func(a, b): return hops[a] > hops[b])
	_order.resize(m)
	for k in m:
		_order[k] = idx[k]
	# povodí a normál
	var tot := PackedFloat32Array()
	tot.resize(m)
	for k in m:
		var si := _order[k]
		var own := _area_loc[si] + _area_ext[si]
		_qn_own[si] = Q_SPEC * maxf(own, MIN_AREA_M2)
		tot[si] += own
		if _down[si] >= 0:
			tot[_down[si]] += tot[si]
	for si in m:
		st_qn[si] = Q_SPEC * maxf(tot[si], MIN_AREA_M2)
	# výchozí zásoby z rozběhové vlhkosti
	var rel0 := lerpf(0.15, 1.3, _m0)
	for si in m:
		_ss[si] = rel0 * _qn_own[si] * 0.8 * _ks[si] * 3600.0
		_sq[si] = rel0 * _qn_own[si] * 0.2 * _kq[si] * 3600.0
		st_turb[si] = 0.0
	ready = true
	_route_streams(0.0)
	if not _pending.is_empty():
		_apply(_pending)
		_pending = {}


# ------------------------------------------------------------------ hodinový krok

func _on_eco_hour(dt_h: float) -> void:
	if not active():
		_acc_h = 0.0
		_acc_rain = 0.0
		_acc_snow = 0.0
		_acc_temp_h = 0.0
		_acc_cloud_h = 0.0
		return
	var wt: Weather = world.weather
	if wt == null or world.clock == null:
		return
	var p := 0.0
	var temp := wt.temp
	var cloud := wt.cloud
	if dt_h > CLIMATE_DT_H:
		# dlouhý skok času (vězení, F2 → datum): klima místo okamžitého počasí
		var doy := world.clock.day_of_year()
		var month := clampi(int((doy - 1.0) / 30.42), 0, 11)
		p = float(PRECIP_MM[month]) / 30.42 * dt_h / 24.0
		temp = Seasons.monthly(Seasons.TEMP_MEAN, doy)
		cloud = 0.6
	else:
		p = wt.rain * Weather.RAIN_MM_H * dt_h
	if _acc_h <= 0.0:
		_acc_event0 = _event_p
	if temp < Weather.SNOW_BELOW:
		_acc_snow += p
	else:
		_acc_rain += p
	_acc_h += dt_h
	_acc_temp_h += temp * dt_h
	_acc_cloud_h += cloud * dt_h
	if p > EVENT_MIN_MM * dt_h:
		_event_p += p
		_dry_h = 0.0
	else:
		_dry_h += dt_h
		if _dry_h >= EVENT_GAP_H:
			_event_p = 0.0
	# zamrzlá půda (globálně): mráz ji zamrazí, teplo a sněhová peřina rozmrazí
	if temp < 0.0:
		frost += -temp * FROST_RATE * dt_h * (0.3 if mean_swe > SNOW_INSULATE_MM else 1.0)
	else:
		frost -= temp * THAW_RATE * dt_h
	frost = clampf(frost, 0.0, 1.0)
	if not _sweeping:
		_start_sweep()


func _start_sweep() -> void:
	if _acc_h <= 0.0:
		return
	var doy := world.clock.day_of_year()
	_f_dt = _acc_h
	_f_rain = _acc_rain
	_f_snow = _acc_snow
	_f_temp = _acc_temp_h / _acc_h
	var cloud := _acc_cloud_h / _acc_h
	var tr := Seasons.monthly(Seasons.TEMP_RANGE, doy) * (1.0 - 0.6 * cloud)
	_f_pet = hargreaves_mm_day(_f_temp, tr, doy) * _f_dt / 24.0
	_f_event0 = _acc_event0
	_f_frost = frost
	var fol := Seasons.foliage(doy)
	_f_fol = lerpf(INTERCEPT_LEAFLESS, 1.0, fol)
	for c in 8:
		var kc: float = KC[c]
		_kc_now[c] = 0.3 + 0.8 * Seasons.green(doy) if kc < 0.0 else kc
	_acc_h = 0.0
	_acc_rain = 0.0
	_acc_snow = 0.0
	_acc_temp_h = 0.0
	_acc_cloud_h = 0.0
	_in_q.fill(0.0)
	_in_s.fill(0.0)
	_sum_m = 0.0
	_sum_q = 0.0
	_sum_out = 0.0
	_sum_swe = 0.0
	_cnt = 0
	_sweeping = true
	world.eco.slice(ceili(float(n) / CHUNK_STEP), 1, _step_chunk)


static func _scs(p: float, s: float) -> float:
	var ia := 0.2 * s
	if p <= ia:
		return 0.0
	return (p - ia) * (p - ia) / (p + 0.8 * s)


## Jeden kus průchodu: kyblík každé buňky o `_f_dt` hodin (bez alokací).
func _step_chunk(c: int) -> void:
	var t0 := Tests.prof_t0()
	var i0 := c * CHUNK_STEP
	var i1 := mini(i0 + CHUNK_STEP, n)
	var dt := _f_dt
	for i in range(i0, i1):
		var a := awc[i]
		var fo := _forest[i]
		var p_r := _f_rain
		var p_s := _f_snow
		# 1. zachycení v korunách (kapacita se plní od začátku události)
		if fo > 0.0 and p_r + p_s > 0.0:
			var free := maxf(INTERCEPT_MM * fo * _f_fol - _f_event0, 0.0)
			var ic := minf(p_r, free)
			p_r -= ic
			p_s -= minf(p_s, free - ic)
		# 2. sníh a tání (degree-day, jižní svah rychleji, les pomaleji)
		var sw := swe[i] + p_s
		var melt := 0.0
		if sw > 0.0 and _f_temp > 0.0:
			var ddf := (DDF_MM + DDF_SOUTH_MM * _south[i]) * lerpf(1.0, MELT_FOREST, fo)
			melt = minf(sw, ddf * _f_temp * dt / 24.0 + RAIN_ON_SNOW * p_r * _f_temp)
			sw -= melt
		swe[i] = sw
		var p_in := p_r + melt
		# 3. SCS-CN: retence podle předchozí vlhkosti (AMC), zamrzlá půda skoro nepropouští
		var wi := w[i]
		var mi := wi / a
		var s := lerpf(_s1[i], _s2[i], smoothstep(0.15, 0.5, mi)) if mi < 0.5 else lerpf(_s2[i], _s3[i], smoothstep(0.5, 0.95, mi))
		s = lerpf(s, S_FROZEN_MM, _f_frost)
		var q := 0.0
		if p_in > 0.0:
			q = clampf(_scs(_f_event0 + p_in, s) - _scs(_f_event0, s), 0.0, p_in)
		wi += p_in - q + _inflow[i]
		_inflow[i] = 0.0
		# 4. výpar (Hargreaves × plodina/les × oslunění svahu × stres suchem)
		var ck: int = _cls[i]
		var kc := lerpf(_kc_now[ck], 1.1, fo)
		var et := _f_pet * kc * _etf[i] * minf(wi / (ET_BETA_FRAC * a), 1.0)
		if sw > 5.0:
			et *= ET_SNOW
		wi = maxf(wi - et, 0.0)
		# 5. přetok nad AWC a pomalé prosakování nad polní kapacitou
		var out := 0.0
		if wi > a:
			out = wi - a
			wi = a
		var thr := DRAIN_FROM * a
		if wi > thr:
			var d := minf((wi - thr) * K_DRAIN_H * _perm[i] * dt, wi - thr)
			wi -= d
			out += d
		w[i] = wi
		var rech := out * GW_FRAC * (0.5 + _perm[i])
		var inter := out - rech
		# 6. kam voda teče: buňka u toku → do toku, jinak podpovrchově po spádnici
		var sc := _scell[i]
		if sc >= 0:
			_in_q[sc] += (q + inter) * CELL_AREA * 0.001
			_in_s[sc] += rech * CELL_AREA * 0.001
		else:
			var ol := _outlet[i]
			if ol >= 0:
				_in_q[ol] += q * CELL_AREA * 0.001
				_in_s[ol] += rech * CELL_AREA * 0.001
			var r := _d8[i]
			if r >= 0:
				_inflow[r] += inter
		mi = wi / a
		runoff[i] = q / dt
		mud[i] = smoothstep(MUD_FROM, MUD_FULL, mi) * _mudk[i] * (1.0 - 0.8 * _f_frost)
		_sum_m += mi
		_sum_q += q
		_sum_out += out
		_sum_swe += sw
		_cnt += 1
	Tests.prof_add("soil_water", t0)
	if i1 >= n:
		_finish_sweep()


func _finish_sweep() -> void:
	var cnt := maxf(float(_cnt), 1.0)
	mean_moist = _sum_m / cnt
	mean_swe = _sum_swe / cnt
	# povodí za okrajem mapy reaguje jako průměr katastru
	var q_mm := _sum_q / cnt
	var out_mm := _sum_out / cnt
	for si in m:
		var ae := _area_ext[si]
		if ae > 0.0:
			_in_q[si] += ae * (q_mm + out_mm * (1.0 - GW_FRAC)) * 0.001
			_in_s[si] += ae * out_mm * GW_FRAC * 0.001
	_route_streams(_f_dt)
	_sweeping = false
	if not _pending.is_empty():
		_apply(_pending)
		_pending = {}
	if _acc_h > 0.0 and active():
		_start_sweep()                           # mezitím uběhly další hodiny (skok času)


## Lineární nádrže toků o `dt` hodin a průtok po proudu (od pramenů k ústí, přítok z horních úseků
## projde rovnou – zpoždění dělají jen nádrže vlastního povodí).
func _route_streams(dt: float) -> void:
	_thru.fill(0.0)
	var sum_rel := 0.0
	var cnt := 0
	for k in m:
		var si := _order[k]
		var q_own := 0.0
		if dt > 0.0:
			var sq := _sq[si] + _in_q[si]
			var ss := _ss[si] + _in_s[si]
			var oq := sq * (1.0 - exp(-dt / _kq[si]))
			var os := ss * (1.0 - exp(-dt / _ks[si]))
			_sq[si] = sq - oq
			_ss[si] = ss - os
			q_own = (oq + os) / (dt * 3600.0)
		else:
			q_own = _sq[si] / (_kq[si] * 3600.0) + _ss[si] / (_ks[si] * 3600.0)
		var qt := q_own + _thru[si]
		st_q[si] = qt
		if _down[si] >= 0:
			_thru[_down[si]] += qt
		var qn := maxf(st_qn[si], 1e-6)
		var rel := qt / qn
		var dn := _depth[si]
		var lv := dn * (pow(maxf(rel, 0.0), LEVEL_EXP) - 1.0)
		var dry := rel < DRY_REL and _is_river[si] == 0
		st_dry[si] = 1 if dry else 0
		st_level[si] = clampf(lv, -dn * (0.6 if _is_river[si] == 1 else 1.0) - 0.05, LEVEL_MAX)
		if dt > 0.0:          # dt = 0 (stavba, načtení) kalnost nemění
			st_turb[si] = maxf(smoothstep(TURB_FROM, TURB_FULL, rel), st_turb[si] * exp(-dt / TURB_TAU_H))
		sum_rel += minf(rel, 3.0)
		cnt += 1
	mean_flow_rel = sum_rel / maxf(float(cnt), 1.0)


# ------------------------------------------------------------------ dotazy (bez alokací)

func _bil(arr: PackedFloat32Array, x: float, z: float) -> float:
	var fx := clampf((x - gx0) / CELL - 0.5, 0.0, nx - 1.001)
	var fz := clampf((z - gz0) / CELL - 0.5, 0.0, nz - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * nx + ix
	var i1 := 1 if ix + 1 < nx else 0
	var j1 := nx if iz + 1 < nz else 0
	return lerpf(lerpf(arr[i], arr[i + i1], tx), lerpf(arr[i + j1], arr[i + j1 + i1], tx), tz)


func _idx(x: float, z: float) -> int:
	var ix := clampi(floori((x - gx0) / CELL), 0, nx - 1)
	var iz := clampi(floori((z - gz0) / CELL), 0, nz - 1)
	return iz * nx + ix


## Vlhkost půdy 0..1 (w / AWC). Fallback: z počasí (déšť posledních dnů, sucho).
func moisture_at(x: float, z: float) -> float:
	if not active():
		var wt: Weather = world.weather if world != null else null
		if wt == null:
			return 0.5
		return clampf(0.45 + 0.5 * wt.rain_recent - 0.35 * wt.drought, 0.0, 1.0)
	var i := _idx(x, z)
	return clampf(w[i] / awc[i], 0.0, 1.0)


## Bláto 0..1 (vlhkost × jílovitost × holá půda / cesta). Fallback: globální `Weather.wetness` (> 0,45).
func mud_at(x: float, z: float) -> float:
	if not active():
		var wt: Weather = world.weather if world != null else null
		return wt.wetness if wt != null and wt.wetness > 0.45 else 0.0
	return clampf(_bil(mud, x, z), 0.0, 1.0)


## Výška sněhu (m). Fallback: `Weather.snow_cover` (1 ≈ 10 cm).
func snow_at(x: float, z: float) -> float:
	if not active():
		return world.weather.snow_cover * 0.1 if world != null and world.weather != null else 0.0
	return _bil(swe, x, z) * 0.001 / SNOW_DENSITY


## Povrchový odtok (mm/h) v posledním průchodu.
func runoff_at(x: float, z: float) -> float:
	if not active():
		return 0.0
	return _bil(runoff, x, z)


## Louže 0..1: nasycená půda v prohlubni (TWI) nebo voda, která právě stéká po povrchu.
func puddle_at(x: float, z: float) -> float:
	if not active():
		return 0.0
	var i := _idx(x, z)
	var mi := w[i] / awc[i]
	var v := smoothstep(PUDDLE_FROM, 1.0, mi) * (0.35 + 0.65 * _twin[i]) + runoff[i] / RUNOFF_PUDDLE
	return clampf(v * (1.0 - 0.8 * frost), 0.0, 1.0)


## TWI 0..1 v bodě (louže se drží v prohlubních).
func hollow_at(x: float, z: float) -> float:
	if n <= 0 or _twin.size() != n:
		return 0.5
	return _twin[_idx(x, z)]


## Zálivka / rozlitá voda: přidá `mm` na plochu `area_m2` (záhon, konev) – do buňky 32 m se rozpočítá
## poměrem ploch. Vrací novou vlhkost buňky 0..1.
func add_water(x: float, z: float, mm: float, area_m2 := CELL_AREA) -> float:
	if not ready:
		return 0.0
	var i := _idx(x, z)
	w[i] = clampf(w[i] + mm * clampf(area_m2 / CELL_AREA, 0.0, 1.0), 0.0, awc[i])
	return w[i] / awc[i]


## Index sucha 0..1 pro `Weather.drought` (vyhláška sucha M4.4): průměrná vlhkost půdy + průtoky.
func drought_index() -> float:
	var dm := clampf((0.5 - mean_moist) / 0.3, 0.0, 1.0)
	var dq := clampf((0.8 - mean_flow_rel) / 0.6, 0.0, 1.0)
	return clampf(dm * 0.6 + dq * 0.4, 0.0, 1.0)


# ------------------------------------------------------------------ ladění (F2 → Příroda – ladění)

func debug_moist(x: float, z: float) -> Color:
	if not active():
		return Color(0, 0, 0, 0)
	var v := moisture_at(x, z)
	return Color(lerpf(0.85, 0.05, v), lerpf(0.75, 0.3, v), lerpf(0.45, 0.95, v), 0.6)


func debug_snow(x: float, z: float) -> Color:
	if not active():
		return Color(0, 0, 0, 0)
	var v := clampf(snow_at(x, z) / 0.3, 0.0, 1.0)
	return Color(0.95, 0.97, 1.0, v * 0.8) if v > 0.01 else Color(0, 0, 0, 0)


func debug_runoff(x: float, z: float) -> Color:
	if not active():
		return Color(0, 0, 0, 0)
	var v := clampf(runoff_at(x, z) / 3.0, 0.0, 1.0)
	return Color(0.9, lerpf(0.8, 0.15, v), 0.1, v * 0.85) if v > 0.005 else Color(0, 0, 0, 0)


## Tabulka hlavních toků pro F2 → Příroda – ladění → Průtoky.
func flows_text() -> String:
	if not ready:
		return "Vodní bilance se ještě staví (mřížka 32 m) – zkus to za chvíli."
	var best := {}                              # jméno → úsek s největším normálem (nejníž po proudu)
	for si in m:
		var nm := String(water.streams[si]["name"])
		if nm == "":
			nm = "(bezejmenné strouhy)"
		if not best.has(nm) or st_qn[si] > st_qn[int(best[nm])]:
			best[nm] = si
	var lines := PackedStringArray()
	lines.append("Vlhkost půdy průměr %d %% · sníh %d mm v. e. · zamrzlá půda %d %% · sucho %d %%%s" % [
		roundi(mean_moist * 100.0), roundi(mean_swe), roundi(frost * 100.0), roundi(drought_index() * 100.0),
		"" if active() else " · (vypnuto – Realismus)"])
	for nm in best:
		var si: int = best[nm]
		lines.append("%s: Q %.3f m³/s (normál %.3f) · hladina %+.2f m · kalnost %d %%%s" % [
			nm, st_q[si], st_qn[si], st_level[si], roundi(st_turb[si] * 100.0), " · VYSCHLÉ" if st_dry[si] == 1 else ""])
	return "\n".join(lines)


# ------------------------------------------------------------------ ukládání (klíč `soil_water`)

func to_dict() -> Dictionary:
	if not ready:
		return {}
	var wq := PackedByteArray()
	wq.resize(n)
	var sq := PackedByteArray()
	sq.resize(n)
	for i in n:
		wq[i] = clampi(roundi(w[i] / awc[i] * 255.0), 0, 255)
		sq[i] = clampi(roundi(swe[i] * 0.5), 0, 255)     # po 2 mm, max 510 mm
	return {"v": 1, "nx": nx, "nz": nz, "m": m,
		"w": Marshalls.raw_to_base64(wq), "swe": Marshalls.raw_to_base64(sq),
		"sq": Marshalls.raw_to_base64(_sq.to_byte_array()), "ss": Marshalls.raw_to_base64(_ss.to_byte_array()),
		"turb": Marshalls.raw_to_base64(st_turb.to_byte_array()),
		"frost": frost, "event": _event_p, "dry_h": _dry_h}


## Starý save bez klíče = rozběh z klimatu (nic se nemění). Mřížka se ještě staví → počká na dostavění.
func restore(d: Dictionary) -> void:
	if d.is_empty():
		return
	if not ready or _sweeping:
		_pending = d
		return
	_apply(d)


func _apply(d: Dictionary) -> void:
	if int(d.get("nx", 0)) != nx or int(d.get("nz", 0)) != nz:
		return                                   # jiná mřížka (nová data) – zůstane rozběh
	var wq := Marshalls.base64_to_raw(String(d.get("w", "")))
	var sq := Marshalls.base64_to_raw(String(d.get("swe", "")))
	if wq.size() == n:
		for i in n:
			w[i] = float(wq[i]) / 255.0 * awc[i]
			mud[i] = smoothstep(MUD_FROM, MUD_FULL, w[i] / awc[i]) * _mudk[i]
	if sq.size() == n:
		for i in n:
			swe[i] = float(sq[i]) * 2.0
	if int(d.get("m", -1)) == m:
		var a := Marshalls.base64_to_raw(String(d.get("sq", ""))).to_float32_array()
		var b := Marshalls.base64_to_raw(String(d.get("ss", ""))).to_float32_array()
		var t := Marshalls.base64_to_raw(String(d.get("turb", ""))).to_float32_array()
		if a.size() == m and b.size() == m:
			_sq = a
			_ss = b
		if t.size() == m:
			st_turb = t
	frost = float(d.get("frost", 0.0))
	_event_p = float(d.get("event", 0.0))
	_dry_h = float(d.get("dry_h", 99.0))
	_route_streams(0.0)
