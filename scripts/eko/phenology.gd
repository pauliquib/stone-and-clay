## Fenologie a růst stromů (M8.11, `World.phenology`): každý druh dřeviny podle svého kalendáře a stromy rostou v letech.
## Podle čeho (00_PRINCIPY kap. 8 „Fenologie“):
## - **sumy efektivních teplot GDD** se základem `BASE_C` (5 °C) z denního průměru teploty od 1. 1. (`Weather.temp` vzorkovaná
##   po herních hodinách přes `eco_hour`; přeskočené dny z klimatického normálu `Seasons.TEMP_MEAN` + `YEAR_ANOMALY_K`),
## - **zimní chlad** (dny s průměrem < 5 °C od 1. 11.): ovocné dřeviny a buk bez dost zimy raší později (`chlad_dni`),
## - **podzim**: zbarvení spouští chlad (K·den pod `AUT_BASE_C` od 1. 8.) + délka dne (`zbarveni_den` – fotoperioda jako
##   den v roce), opad listí trvá `opad_dni`,
## - **posun v prostoru**: místo má teplotní posun (K) ze stanoviště (`Site`: výška × gradient `Microclimate.LAPSE_K_M`, oslunění
##   svahu, mrazová kotlina) → fáze se počítá jako GDD + posun × počet teplých dnů (na podzim obráceně s chladem),
## - **pozdní mráz** v době květu (a krátce po něm) spálí květy → `frost_damage` → méně ovoce (`TreeDecor`, zasazené stromy),
## - **růst v letech**: na Nový rok každý strom zestárne o rok, výška podle Chapman–Richards (`TreeEco.height_at_age`)
##   × roční faktor stresu (sucho z `SoilWater` v létě, mráz) – drží se jen počet let a stres po letech (save kompaktně),
##   vzhled stromů se po kouscích přeškáluje (`EcoClock.slice` → `TreeManager.regrow`).
## Prahy druhů v `data/dreviny.json` → `fenologie` (kalibrace na průměrná data fází pro střední Moravu, odhad – ověřit v M8.19).
##
## Vzhled: `INSTANCE_CUSTOM.a` stromu = kód druhu a pásma posunu místa (`instance_alpha`), shadery `tree` / `tree_impostor`
## čtou denní tabulku `pheno_lut` (globální uniform, 16 × 32) → každý druh a místo raší, kvete a barví se jinak.
##
## **Fallback** (00_PRINCIPY kap. 3): přepínač realismu `phenology` vypnutý nebo chybí katalog → `phase()` vrací dnešní
## `Seasons` křivky, `pheno_on` = 0 (shadery jako dřív), růst stojí. Volající čtou jen přes `World.phenology` s kontrolou `null`.
class_name Phenology
extends RefCounted

const BINS := 7                       # pásma teplotního posunu místa −3 … +3 K (shader: sloupce 0–6)
const REF_BIN := 3                    # pásmo „bez posunu“ (deník, kalendář)
const LUT_W := 16
const LUT_H := 32                     # nejvýš 32 druhů (řádky tabulky)
const COL_AUT := 8
const COL_SPR := 9
const COL_BLOOM := 10
const COL_FLAGS := 11
const SPINUP_MAX_DAYS := 400          # delší skok času = rozběh roku znovu z klimatu (+ roky růstu)
const STRESS_HISTORY := 300           # nejvýš tolik let stresu v savu
## Druhy, které se píšou do deníku J (rok v paměti) a do kalendáře nahoře.
const JOURNAL_SPECIES := ["briza", "vrba_bila", "modrin", "habr", "buk", "dub_zimni", "jasan", "tresen", "jablon", "lipa"]

## M8.11: laditelné (F3 → Příroda/Fenologie a růst, `scripts/dev/tune_m8_11.gd`) – výchozí = kalibrace kroku.
static var BASE_C := 5.0              # °C – základ GDD
static var CHILL_BELOW_C := 5.0       # °C – den s průměrem pod tímto je „chladný“ (zimní chlad od 1. 11.)
static var CHILL_FROM_DOY := 305      # den v roce, od kterého se počítá zimní chlad (1. 11.)
static var CHILL_PENALTY := 0.6       # bez zimního chladu se práh rašení zvýší až o tolik (× rasi_gdd)
static var AUT_BASE_C := 12.0         # °C – podzimní chlad = součet (tohle − průměr) od AUT_FROM_DOY
static var AUT_FROM_DOY := 213        # den v roce, od kterého se sčítá podzimní chlad (1. 8.)
static var PHOTO_KD := 2.0            # K·den za každý den po `zbarveni_den` (krátký den tlačí na zbarvení i v teplém podzimu)
static var AUT_SPAN_KD := 45.0        # K·den od začátku zbarvení do plně zbarvené koruny
static var FALL_FROM := 0.5           # opad začne při tomto podílu zbarvení
static var OPAD_KD_PER_DAY := 5.0     # K·den na den opadu (převod `opad_dni` na podzimní chlad)
static var AUT_SHIFT_K := 1.0         # váha teplotního posunu místa na podzim (chladné místo se barví dřív)
static var SPRING_MIN_SPAN_GDD := 30.0  # nejkratší rašení → plné olistění (GDD)
static var FLUSH_FADE_GDD := 250.0    # jarní přírůst jehličnanů bledne do zeleně za tolik GDD po plném olistění
static var BLOOM_HALF_GDD := 40.0     # kvetení: půlšířka (GDD) kolem `kvete_gdd`
static var FROST_KILL_C := -1.7       # °C – od této noční teploty mráz poškozuje květy
static var FROST_SPAN_K := 2.5        # K pod prahem = květy zničené úplně
static var FROST_FRUITLET_GDD := 80.0 # po odkvětu jsou plůdky citlivé ještě tolik GDD (citlivost klesá)
static var FROST_VALLEY_K := 3.0      # bez mikroklimatu: v údolí je noc o tolik chladnější než ve 2 m referenčně
static var FROST_RIDGE_K := 1.0       # … na svahu nad inverzí o tolik teplejší
static var FROST_EVENT_MIN := 0.15    # poškození, od kterého se mráz zapíše do deníku
static var SHIFT_MAX_K := 3.0         # K – nejvyšší teplotní posun místa (obě strany)
static var SHIFT_SOUTH_K := 1.2       # K – jižní svah (plné oslunění navíc) proti průměru – průměr dne, ne poledne
static var SHIFT_POOL_K := 1.0        # K – mrazová kotlina (Site.cold_pool = 1) je v průměru dne chladnější
static var YEAR_ANOMALY_K := 0.0      # K – odchylka roku pro dny z klimatu (rozběh, přeskočené dny; F2 → kalendář)
static var SAMPLES_MIN := 12          # hodinových vzorků teploty, aby den platil (jinak klima)
static var DROUGHT_STRESS_K := 0.6    # úbytek ročního přírůstku při plném letním suchu
static var FROST_STRESS_K := 0.2      # … při plném poškození pozdním mrazem
static var GROWTH_MIN := 0.3          # roční přírůstek nikdy pod tento podíl
static var SUMMER_FROM_DOY := 152     # léto pro sucho (1. 6.)
static var SUMMER_TO_DOY := 243       # … do 31. 8.
static var REGROW_PER_FRAME := 150    # stromů za snímek při přeškálování vzhledu po Novém roce (EcoClock.slice)
static var BEES_MEADOW_W := 0.7       # včely: váha kvetení luk (Seasons.BLOOM)
static var BEES_TREE_W := 0.6         # … a kvetoucích dřevin v okolí úlu
static var BEES_R := 150.0            # m – okruh dřevin pro včely

static var _sp: Array[Dictionary] = []    # parametry druhů (pořadí = katalog dreviny.json)
static var _sp_idx := {}                  # id → index
static var _sp_loaded := false
static var _gen := 0                      # čítač změn z F3 (`invalidate`) – tabulka se přepočítá v hodinovém kroku

var world: World
var year := 0                         # rok, ke kterému patří akumulátory
var last_jd := -1                     # poslední zpracovaný (celý) den
var cur_doy := 1                      # den v roce posledního zpracovaného dne
var gdd_sum := 0.0                    # GDD (BASE_C) od 1. 1.
var warm_days := 0                    # dny s průměrem nad BASE_C od 1. 1.
var chill_days := 0                   # zimní chlad (dny < CHILL_BELOW_C od 1. 11.)
var aut_chill := 0.0                  # podzimní chlad (K·den pod AUT_BASE_C od 1. 8.)
var aut_cool_days := 0                # dny pod AUT_BASE_C od 1. 8.
var tmean := PackedFloat32Array()     # průměrná teplota dne (index = den v roce)
var frost := PackedFloat32Array()     # poškození mrazem 0..1 (druh × BINS)
var hist := {}                        # id druhu → {"r": den rašení, "k": den květu, "z": den zbarvení} (pásmo REF_BIN)
var events: Array[String] = []        # letošní zápisy (pozdní mráz…)
var last_year: Array[String] = []     # loňský rok v paměti (deník)
var growth_years := 0                 # kolik let stromy vyrostly od stavu v tree_eco.bin / trees.bin
var growth_stress := PackedFloat32Array()   # stres po letech 0..1

var _drought_sum := 0.0
var _drought_n := 0
var _frost_year := 0.0
var _h_sum := 0.0
var _h_n := 0
var _h_min := 99.0
var _hv_min := 99.0
var _hr_min := 99.0
var _lut_img: Image
var _lut_tex: ImageTexture
var _on_state := -1
var _regrow_pending := false
var _regrow_busy := false
var _gen_seen := 0
var _bloom_cache := {}                # Vector2i(128 m) → kvetení dřevin v okolí (maže se denně)
# výstup `_calc` (bez alokací)
var _o_fol := 1.0
var _o_aut := 0.0
var _o_bloom := 0.0
var _o_fruit := 0.0
var _o_flush := 0.0


func setup(w: World) -> void:
	world = w
	ensure_species()
	tmean.resize(367)
	frost.resize(maxi(_sp.size(), 1) * BINS)
	_lut_img = Image.create(LUT_W, LUT_H, false, Image.FORMAT_RGBA8)
	_fill_lut_static()
	_lut_tex = ImageTexture.create_from_image(_lut_img)
	RenderingServer.global_shader_parameter_set("pheno_lut", _lut_tex)
	world.eco_hour.connect(_on_eco_hour)
	world.eco_day.connect(_on_eco_day)
	world.debug_layers["fenologie"] = Callable(self, "debug_layer")
	if world.clock != null:
		_spin_up(world.clock.jd() - 1)
	_update_lut()


## Zapnuto (přepínač realismu `phenology`) a jsou data druhů.
func enabled() -> bool:
	return world != null and not _sp.is_empty() and world.realism_on("phenology")


# ------------------------------------------------------------------ katalog druhů (statický – čte ho i stavba stromů)

static func ensure_species() -> void:
	if _sp_loaded:
		return
	_sp_loaded = true
	var txt := FileAccess.get_file_as_string(TreeEco.CATALOG)
	var j = JSON.parse_string(txt) if txt != "" else null
	if typeof(j) != TYPE_DICTIONARY:
		push_warning("Phenology: chybí %s – fenologie jen podle Seasons (fallback)" % TreeEco.CATALOG)
		return
	for s in (j as Dictionary).get("druhy", []):
		var d: Dictionary = s
		var id := String(d.get("id", ""))
		if id == "" or _sp.size() >= LUT_H:
			continue
		var f: Dictionary = d.get("fenologie", {}) if d.get("fenologie") is Dictionary else {}
		var b: Dictionary = d.get("barvy", {}) if d.get("barvy") is Dictionary else {}
		var conifer := String(d.get("typ", "")) == "jehlicnan"
		var p := {
			"id": id, "name": String(d.get("nazev", id)),
			"ever": bool(f.get("stalezeleny", false)),
			"rasi": _num(f, "rasi_gdd", 120.0), "plne": _num(f, "plne_olisteni_gdd", 260.0),
			"kvete": _num(f, "kvete_gdd", -1.0), "zden": _num(f, "zbarveni_den", 275.0),
			"zchlad": _num(f, "zbarveni_chlad", -1.0 if conifer else 36.0), "opad": _num(f, "opad_dni", 25.0),
			"chlad": _num(f, "chlad_dni", 0.0), "zrani": _num(f, "zrani_gdd", 0.0),
			"fruit": String(d.get("typ", "")) == "ovocny" or d.has("ovoce"),
			"bloom_col": String(f.get("kvet_barva", "")),
			"aut_col": Color.html(String(b.get("podzim", "#b5652a"))),
			"spr_col": Color.html(String(b.get("jaro", "#8fae4a"))),
		}
		if bool(p["ever"]):
			p["zchlad"] = -1.0
		_sp_idx[id] = _sp.size()
		_sp.append(p)


static func _num(d: Dictionary, k: String, def: float) -> float:
	var v: Variant = d.get(k)
	return float(v) if v is float or v is int else def


## Index druhu v tabulce (−1 neznámý).
static func species_index(id: String) -> int:
	ensure_species()
	return int(_sp_idx.get(id, -1))


## Teplotní posun místa (K) proti referenci: výška (gradient), oslunění svahu, mrazová kotlina. Bez `Site` dat 0 (kromě výšky).
static func site_shift_k(site: Site, pos: Vector3) -> float:
	if site == null:
		return 0.0
	var s := -Microclimate.LAPSE_K_M * (site.elev(pos.x, pos.z) - Microclimate.DEF_REF_ELEV)
	if site.loaded:
		s += SHIFT_SOUTH_K * clampf((site.insol(pos.x, pos.z) - Microclimate.INSOL_MEAN) / maxf(Microclimate.INSOL_SPAN, 1.0), -1.0, 1.0)
		s -= SHIFT_POOL_K * site.cold_pool(pos.x, pos.z)
	return clampf(s, -SHIFT_MAX_K, SHIFT_MAX_K)


## Kód pro `INSTANCE_CUSTOM.a` stromu (druh × 8 + pásmo posunu + 0,5) / 256; 1,0 = bez fenologie (neznámý druh).
static func instance_alpha(species_id: String, pos: Vector3, site: Site) -> float:
	var si := species_index(species_id)
	if si < 0 or si >= LUT_H:
		return 1.0
	var b := clampi(roundi(site_shift_k(site, pos)) + REF_BIN, 0, BINS - 1)
	return (float(si * 8 + b) + 0.5) / 256.0


# ------------------------------------------------------------------ denní krok

## F3: parametr změněn → přepočet tabulky pro shadery v nejbližší herní hodině.
static func invalidate() -> void:
	_gen += 1


func _on_eco_hour(dt_h: float) -> void:
	if enabled() != (_on_state == 1) or _gen != _gen_seen:
		_gen_seen = _gen
		_update_lut()                     # přepínač realismu nebo ladění změněno
	if dt_h > 1.5 or world.weather == null:
		return                            # hrubý krok po dlouhém skoku – den se dopočítá z klimatu
	var t := world.weather.temp
	_h_sum += t
	_h_n += 1
	_h_min = minf(_h_min, t)
	var m: Microclimate = world.micro
	if m != null and m.enabled():
		_hv_min = minf(_hv_min, m.temp_valley())
		_hr_min = minf(_hr_min, m.temp_ridge())
	else:
		_hv_min = minf(_hv_min, t - FROST_VALLEY_K)
		_hr_min = minf(_hr_min, t + FROST_RIDGE_K)


func _on_eco_day(jd: int) -> void:
	_catch_up(jd - 1)
	_h_sum = 0.0
	_h_n = 0
	_h_min = 99.0
	_hv_min = 99.0
	_hr_min = 99.0
	_update_lut()
	_maybe_regrow()


## Změna data (F2 → Datum): rok se rozběhne znovu z klimatu (dopředu o roky = roky růstu).
func on_date_set() -> void:
	if world == null or world.clock == null:
		return
	_catch_up(world.clock.jd() - 1, true)
	_update_lut()
	_maybe_regrow()


## Dopočítá dny do `to_jd` (včetně). Zpět v čase jen po změně data v F2 (`back`) – eko-takt po skoku dohání hodiny
## dnů, které už jsou spočtené z klimatu, ty se přeskočí.
func _catch_up(to_jd: int, back := false) -> void:
	if last_jd >= 0 and to_jd <= last_jd and not (back and to_jd < last_jd):
		return
	if last_jd < 0 or to_jd < last_jd or to_jd - last_jd > SPINUP_MAX_DAYS:
		if last_jd >= 0 and to_jd > last_jd and enabled():
			var ny := int(Clock.from_jdn(to_jd)["year"]) - year
			for k in maxi(ny, 0):
				_grow_year(_mean_stress())
		_spin_up(to_jd)
		return
	for j in range(last_jd + 1, to_jd + 1):
		var d := Clock.from_jdn(j)
		var y := int(d["year"])
		var doy := j - Clock.jdn(y, 1, 1) + 1
		var real := j == to_jd and _h_n >= SAMPLES_MIN
		var t := _h_sum / float(_h_n) if real else _clim(doy, true)
		_day(y, doy, t, _hv_min if real else NAN, _hr_min if real else NAN, true)
	last_jd = to_jd


## Rozběh roku z klimatu: od 1. 11. předloňska (zimní chlad) do `to_jd` (bez růstu a bez mrazů).
func _spin_up(to_jd: int) -> void:
	var y := int(Clock.from_jdn(to_jd)["year"])
	var start := Clock.jdn(y - 1, 11, 1)
	year = 0
	for j in range(start, to_jd + 1):
		var d := Clock.from_jdn(j)
		var yy := int(d["year"])
		var doy := j - Clock.jdn(yy, 1, 1) + 1
		_day(yy, doy, _clim(doy, false), NAN, NAN, false)
	last_jd = to_jd


## Průměrná teplota dne z klimatického normálu (+ odchylka roku; při dohánění i vynucená teplota z F2).
func _clim(doy: int, catchup: bool) -> float:
	if catchup and world != null and world.weather != null and not is_nan(world.weather.forced_temp):
		return world.weather.forced_temp
	return Seasons.monthly(Seasons.TEMP_MEAN, float(doy)) + YEAR_ANOMALY_K


func _day(y: int, doy: int, t: float, tmin_v: float, tmin_r: float, grow: bool) -> void:
	if y != year:
		_new_year(y, grow)
	cur_doy = doy
	gdd_sum += maxf(0.0, t - BASE_C)
	if t > BASE_C:
		warm_days += 1
	if doy == 182:
		chill_days = 0
	if (doy >= CHILL_FROM_DOY or doy < 182) and t < CHILL_BELOW_C:
		chill_days += 1
	if doy >= AUT_FROM_DOY:
		aut_chill += maxf(0.0, AUT_BASE_C - t)
		if t < AUT_BASE_C:
			aut_cool_days += 1
	if doy >= 0 and doy < tmean.size():
		tmean[doy] = t
	if doy >= SUMMER_FROM_DOY and doy <= SUMMER_TO_DOY:
		var sw: SoilWater = world.soil_water if world != null else null
		if sw != null and sw.active():
			_drought_sum += sw.drought_index()
		elif world != null and world.weather != null:
			_drought_sum += world.weather.drought
		_drought_n += 1
	if not is_nan(tmin_v) and enabled():
		_frost_check(doy, tmin_v, tmin_r)
	_hist_check(doy)


func _new_year(y: int, grow: bool) -> void:
	if grow and year > 0 and y == year + 1 and enabled():
		_grow_year(_year_stress())
	if year > 0 and grow:
		last_year = _year_lines(year)
	year = y
	gdd_sum = 0.0
	warm_days = 0
	aut_chill = 0.0
	aut_cool_days = 0
	tmean.fill(0.0)
	frost.fill(0.0)
	hist.clear()
	events.clear()
	_drought_sum = 0.0
	_drought_n = 0
	_frost_year = 0.0


func _year_stress() -> float:
	var dr := _drought_sum / float(_drought_n) if _drought_n > 0 else 0.0
	return clampf(DROUGHT_STRESS_K * dr + FROST_STRESS_K * _frost_year, 0.0, 1.0 - GROWTH_MIN)


func _mean_stress() -> float:
	if growth_stress.is_empty():
		return 0.1
	var s := 0.0
	for v in growth_stress:
		s += v
	return s / float(growth_stress.size())


## Roční krok růstu (Nový rok): +1 rok všem stromům, faktor přírůstku = 1 − průměrný stres.
func _grow_year(stress: float) -> void:
	growth_years += 1
	growth_stress.append(stress)
	if growth_stress.size() > STRESS_HISTORY:
		growth_stress = growth_stress.slice(growth_stress.size() - STRESS_HISTORY)
	_apply_growth()
	_regrow_pending = true


func _apply_growth() -> void:
	var te: TreeEco = world.tree_eco if world != null else null
	if te != null:
		te.set_growth(growth_years, 1.0 - _mean_stress() if growth_years > 0 else 1.0)


func _maybe_regrow() -> void:
	if not _regrow_pending or _regrow_busy or world == null or world.eco == null or world.trees == null:
		return
	_regrow_pending = false
	_regrow_busy = true
	var n := world.trees.raw_count()
	if n <= 0:
		_regrow_busy = false
		return
	world.eco.slice(n + 1, REGROW_PER_FRAME, _regrow_one.bind(n))


func _regrow_one(i: int, n: int) -> void:
	if i >= n:
		_regrow_busy = false
		return
	var tm: TreeManager = world.trees
	var te: TreeEco = world.tree_eco
	if tm == null or te == null or not tm.has_tree(i):
		return
	tm.regrow(i, te.growth_factor(i))


# ------------------------------------------------------------------ fáze

## Fáze druhu `si` při teplotním posunu `shift` (K) → `_o_*` (bez alokací).
func _calc(si: int, shift: float) -> void:
	var p: Dictionary = _sp[si]
	var gs := maxf(0.0, gdd_sum + shift * float(warm_days))
	var rasi: float = p["rasi"]
	var chl: float = p["chlad"]
	if chl > 0.0:
		rasi *= 1.0 + CHILL_PENALTY * clampf(1.0 - float(chill_days) / chl, 0.0, 1.0)
	var span := maxf(float(p["plne"]) - float(p["rasi"]), SPRING_MIN_SPAN_GDD)
	var spring := clampf((gs - rasi) / span, 0.0, 1.0)
	spring = spring * spring * (3.0 - 2.0 * spring)
	_o_flush = 0.0
	if bool(p["ever"]):
		_o_fol = 1.0
		_o_aut = 0.0
		_o_flush = spring * (1.0 - clampf((gs - rasi - span) / maxf(FLUSH_FADE_GDD, 1.0), 0.0, 1.0))
	else:
		var aut := 0.0
		var fall := 0.0
		var thr: float = p["zchlad"]
		if thr >= 0.0:
			var dd := aut_chill - shift * AUT_SHIFT_K * float(aut_cool_days) + PHOTO_KD * maxf(0.0, float(cur_doy) - float(p["zden"]))
			aut = clampf((dd - thr) / maxf(AUT_SPAN_KD, 1.0), 0.0, 1.0)
			fall = clampf((dd - thr - AUT_SPAN_KD * FALL_FROM) / maxf(float(p["opad"]) * OPAD_KD_PER_DAY, 1.0), 0.0, 1.0)
		_o_fol = spring * (1.0 - fall)
		_o_aut = aut
	var kv: float = p["kvete"]
	_o_bloom = clampf(1.0 - absf(gs - kv) / maxf(BLOOM_HALF_GDD, 1.0), 0.0, 1.0) if kv > 0.0 else 0.0
	var zr: float = p["zrani"]
	_o_fruit = clampf((gs - kv) / zr, 0.0, 1.0) if zr > 0.0 and kv > 0.0 else 0.0


## Fallback bez fenologie: dnešní křivky `Seasons` podle dne v roce.
func _fallback(si: int) -> void:
	var doy := world.clock.day_of_year() if world != null and world.clock != null else 180.0
	var ever := si >= 0 and bool(_sp[si]["ever"])
	_o_fol = 1.0 if ever else Seasons.foliage(doy)
	_o_aut = 0.0 if ever else Seasons.autumn(doy)
	_o_bloom = Seasons.bloom(doy) if si < 0 or float(_sp[si]["kvete"]) > 0.0 else 0.0
	_o_fruit = Seasons.curve(TreeDecor.FRUIT, doy) if si < 0 or float(_sp[si]["zrani"]) > 0.0 else 0.0
	_o_flush = 0.0


func _eval(species: String, pos: Vector3) -> float:
	var si := int(_sp_idx.get(species, -1))
	if not enabled() or si < 0:
		_fallback(si)
		return 0.0
	var sh := site_shift_k(world.site, pos)
	_calc(si, sh)
	return frost[si * BINS + clampi(roundi(sh) + REF_BIN, 0, BINS - 1)]


## Fáze druhu v místě: {foliage, autumn, bloom, fruit (zrání 0..1), frost_damage (0..1), flush (přírůst jehličnanů)}.
func phase(species: String, pos: Vector3) -> Dictionary:
	var fd := _eval(species, pos)
	return {"foliage": _o_fol, "autumn": _o_aut, "bloom": _o_bloom, "fruit": _o_fruit, "frost_damage": fd, "flush": _o_flush}


func foliage(species: String, pos: Vector3) -> float:
	_eval(species, pos)
	return _o_fol


func autumn(species: String, pos: Vector3) -> float:
	_eval(species, pos)
	return _o_aut


func bloom(species: String, pos: Vector3) -> float:
	_eval(species, pos)
	return _o_bloom


func fruit(species: String, pos: Vector3) -> float:
	_eval(species, pos)
	return _o_fruit


## Poškození květů / plůdků pozdním mrazem 0..1 (0 bez fenologie).
func frost_damage(species: String, pos: Vector3) -> float:
	return _eval(species, pos)


## Úroda ovoce 0..1 proti běžnému roku (1 − poškození mrazem; bez fenologie 1).
func crop_factor(species: String, pos: Vector3) -> float:
	return 1.0 - _eval(species, pos)


## Kvetení dřevin v okolí 0..1 (vážené podíly druhů z `TreeEco.species_near`) – včely, zvuková krajina.
func bloom_near(pos: Vector3, r: float) -> float:
	var te: TreeEco = world.tree_eco if world != null else null
	if te == null or not enabled():
		return Seasons.bloom(world.clock.day_of_year()) if world != null and world.clock != null else 0.0
	var sn := te.species_near(pos, r)
	var b := 0.0
	for id in sn:
		b += float(sn[id]) * bloom(String(id), pos)
	return clampf(b, 0.0, 1.0)


## Kvetení pro včely (`Apiary`): louky (Seasons) + kvetoucí dřeviny v okolí; výsledek na buňku 128 m drží do dalšího dne.
func bees_bloom(pos: Vector3) -> float:
	var doy := world.clock.day_of_year() if world != null and world.clock != null else 120.0
	var meadow := Seasons.bloom(doy)
	if not enabled():
		return meadow
	var key := Vector2i(floori(pos.x / 128.0), floori(pos.z / 128.0))
	if not _bloom_cache.has(key):
		_bloom_cache[key] = bloom_near(pos, BEES_R)
	return clampf(meadow * BEES_MEADOW_W + float(_bloom_cache[key]) * BEES_TREE_W, 0.0, 1.0)


## Suma efektivních teplot od 1. 1. do dne v roce `year_day` (−1 = dnes) se základem `base` (°C). Dny po dnešku
## z klimatického normálu. Bez fenologie (vypnuto) z klimatu.
func gdd(year_day := -1, base := BASE_C) -> float:
	var to := cur_doy if year_day < 0 else year_day
	if not enabled():
		var s0 := 0.0
		for d in range(1, to + 1):
			s0 += maxf(0.0, Seasons.monthly(Seasons.TEMP_MEAN, float(d)) - base)
		return s0
	if year_day < 0 and is_equal_approx(base, BASE_C):
		return gdd_sum
	var s := 0.0
	for d in range(1, to + 1):
		var t: float = tmean[d] if d <= cur_doy and d < tmean.size() else Seasons.monthly(Seasons.TEMP_MEAN, float(d)) + YEAR_ANOMALY_K
		s += maxf(0.0, t - base)
	return s


## Průměrná teplota posledního celého dne (°C).
func temp_mean_day() -> float:
	return tmean[cur_doy] if cur_doy >= 0 and cur_doy < tmean.size() else 10.0


## Teplotní posun místa (K).
func shift_at(pos: Vector3) -> float:
	return site_shift_k(world.site if world != null else null, pos)


## Délka dne (h) pro den v roce na 49,14° s. š. (fotoperioda – jen pro výpis v kalendáři).
static func day_length_h(doy: float) -> float:
	var decl := deg_to_rad(23.44) * sin(TAU * (284.0 + doy) / 365.0)
	var lat := deg_to_rad(49.14)
	var c := clampf(-tan(lat) * tan(decl), -1.0, 1.0)
	return 24.0 / PI * acos(c)


# ------------------------------------------------------------------ mráz, deník

func _frost_check(doy: int, tmin_v: float, tmin_r: float) -> void:
	var worst := 0.0
	var hit_bins := 0
	var hit_low := false
	var names: Array[String] = []
	for si in _sp.size():
		var p: Dictionary = _sp[si]
		var kv: float = p["kvete"]
		if kv <= 0.0 or not (bool(p["fruit"]) or String(p["bloom_col"]) != ""):
			continue
		var hit := false
		for b in BINS:
			var tmin := lerpf(tmin_v, tmin_r, float(b) / float(BINS - 1))
			if tmin > FROST_KILL_C:
				continue
			var gs := maxf(0.0, gdd_sum + float(b - REF_BIN) * float(warm_days))
			var x := gs - kv
			var sens := 0.0
			if x >= -BLOOM_HALF_GDD and x <= 0.0:
				sens = 1.0 + x / maxf(BLOOM_HALF_GDD, 1.0) * 0.5
			elif x > 0.0:
				sens = clampf(1.0 - x / maxf(FROST_FRUITLET_GDD + BLOOM_HALF_GDD, 1.0), 0.0, 1.0)
			if sens <= 0.0:
				continue
			var t01 := clampf((FROST_KILL_C - tmin) / maxf(FROST_SPAN_K, 0.1), 0.0, 1.0)
			var dmg := t01 * sens
			var k := si * BINS + b
			frost[k] = 1.0 - (1.0 - frost[k]) * (1.0 - dmg)
			if dmg >= FROST_EVENT_MIN:
				hit = true
				worst = maxf(worst, dmg)
				hit_bins = maxi(hit_bins, b + 1)
				if b <= REF_BIN - 1:
					hit_low = true
		if hit and bool(p["fruit"]) and names.size() < 3:
			names.append(_plural(String(p["id"]), String(p["name"])))
	_frost_year = maxf(_frost_year, worst)
	if worst >= FROST_EVENT_MIN and not names.is_empty():
		var where := "všude" if hit_bins >= BINS else ("v údolí" if hit_low and hit_bins <= REF_BIN else "v údolí i na svazích")
		events.append("Pozdní mráz %s (%.0f °C) spálil květy (%s) %s." % [_date(doy), minf(tmin_v, tmin_r), ", ".join(names), where])
		if events.size() > 8:
			events.remove_at(0)


func _hist_check(doy: int) -> void:
	for id in JOURNAL_SPECIES:
		var si := int(_sp_idx.get(id, -1))
		if si < 0:
			continue
		var h: Dictionary = hist.get(id, {})
		if h.size() >= 3:
			continue
		_calc(si, 0.0)
		var p: Dictionary = _sp[si]
		if not h.has("r") and ((not bool(p["ever"]) and _o_fol > 0.08) or (bool(p["ever"]) and _o_flush > 0.08)):
			h["r"] = doy
		if not h.has("k") and _o_bloom > 0.6:
			h["k"] = doy
		if not h.has("z") and _o_aut > 0.15:
			h["z"] = doy
		if not hist.has(id):
			hist[id] = h


static func _plural(id: String, name: String) -> String:
	const P := {"jablon": "jabloně", "hrusen": "hrušně", "svestka": "švestky", "tresen": "třešně", "tresen_ptaci": "třešně",
		"orech": "ořešáky"}
	return String(P.get(id, name.to_lower()))


func _date(doy: int) -> String:
	var y := year if year > 0 else 2026
	var d := Clock.from_jdn(Clock.jdn(y, 1, 1) + doy - 1)
	return "%d. %d." % [int(d["day"]), int(d["month"])]


func _year_lines(y: int) -> Array[String]:
	var out: Array[String] = []
	var parts: Array[String] = []
	for id in JOURNAL_SPECIES:
		var h: Dictionary = hist.get(id, {})
		if h.is_empty():
			continue
		var si := int(_sp_idx.get(id, -1))
		var s := String(_sp[si]["name"]).get_slice(" ", 0)
		var bits: Array[String] = []
		if h.has("r"):
			bits.append("raší " + _date(int(h["r"])))
		if h.has("k") and String(_sp[si]["bloom_col"]) != "":
			bits.append("kvete " + _date(int(h["k"])))
		if h.has("z"):
			bits.append("barví se " + _date(int(h["z"])))
		if not bits.is_empty():
			parts.append("%s %s" % [s, ", ".join(bits)])
	if not parts.is_empty():
		out.append("%d: %s." % [y, "; ".join(parts)])
	for e in events:
		out.append(e)
	return out


## Deník J → oddíl „Rok v přírodě“ (letošní fáze, pozdní mráz, loňský rok, růst lesa).
func journal_text() -> String:
	if not enabled():
		return ""
	var s := "\n[b]ROK V PŘÍRODĚ[/b]   (suma teplot letos %d °C·den)\n" % roundi(gdd_sum)
	for l in _year_lines(year):
		s += "  " + l + "\n"
	if not last_year.is_empty():
		s += "  [color=#999]Loni – " + " ".join(last_year) + "[/color]\n"
	if growth_years > 0:
		s += "  Les od začátku hry o %d let starší (přírůstek %d %% běžného).\n" % [growth_years, roundi((1.0 - _mean_stress()) * 100.0)]
	return s


## F2 → Příroda – ladění → Fenologický kalendář: druh → rašení / květ / zbarvení letos (pásmo bez posunu) + stav dnes.
func calendar_text() -> String:
	var s := "Rok %d, den %d (%s), délka dne %.1f h. GDD (5 °C) %d, teplých dnů %d, zimní chlad %d dnů, podzimní chlad %d K·den.\n" % [
		year, cur_doy, _date(cur_doy), day_length_h(float(cur_doy)), roundi(gdd_sum), warm_days, chill_days, roundi(aut_chill)]
	s += "Odchylka roku (dny z klimatu): %+.1f K. Fenologie %s.\n\n" % [YEAR_ANOMALY_K, "zapnutá" if enabled() else "VYPNUTÁ (Seasons)"]
	s += "DRUH – raší / kvete / barví se  ·  dnes olistění, zbarvení, květ, mráz (údolí / svah)\n"
	for si in _sp.size():
		var p: Dictionary = _sp[si]
		var id := String(p["id"])
		var h: Dictionary = hist.get(id, {})
		_calc(si, 0.0)
		var fol := _o_fol
		var aut := _o_aut
		var bl := _o_bloom
		var rd := _date(int(h["r"])) if h.has("r") else "GDD %d/%d" % [roundi(gdd_sum), roundi(float(p["rasi"]))]
		var kd := _date(int(h["k"])) if h.has("k") else ("–" if float(p["kvete"]) <= 0.0 else "GDD %d/%d" % [roundi(gdd_sum), roundi(float(p["kvete"]))])
		var zd := _date(int(h["z"])) if h.has("z") else ("–" if float(p["zchlad"]) < 0.0 else "zatím ne")
		s += "%s – %s / %s / %s  ·  %d %%, %d %%, %d %%, mráz %d / %d %%\n" % [p["name"], rd, kd, zd,
			roundi(fol * 100.0), roundi(aut * 100.0), roundi(bl * 100.0),
			roundi(frost[si * BINS] * 100.0), roundi(frost[si * BINS + BINS - 1] * 100.0)]
	if not events.is_empty():
		s += "\n" + "\n".join(events)
	return s


## F2 → kalendář: odchylka roku (K) pro dny z klimatu → rok se rozběhne znovu (např. +5 K = teplé jaro).
func set_anomaly(k: float) -> void:
	YEAR_ANOMALY_K = k
	if world != null and world.clock != null:
		last_jd = -1
		_spin_up(world.clock.jd() - 1)
		_update_lut()


# ------------------------------------------------------------------ tabulka pro shader

func _fill_lut_static() -> void:
	_lut_img.fill(Color(0, 0, 0, 0))
	for si in _sp.size():
		var p: Dictionary = _sp[si]
		_lut_img.set_pixel(COL_AUT, si, p["aut_col"])
		_lut_img.set_pixel(COL_SPR, si, p["spr_col"])
		var bc := String(p["bloom_col"])
		if bc != "":
			var c := Color.html(bc)
			_lut_img.set_pixel(COL_BLOOM, si, Color(c.r, c.g, c.b, 1.0))
		_lut_img.set_pixel(COL_FLAGS, si, Color(1.0 if bool(p["ever"]) else 0.0, 1.0, 0.0, 1.0))


func _update_lut() -> void:
	var on := enabled()
	_on_state = 1 if on else 0
	RenderingServer.global_shader_parameter_set("pheno_on", 1.0 if on else 0.0)
	_bloom_cache.clear()
	if not on or _lut_img == null:
		return
	for si in _sp.size():
		for b in BINS:
			_calc(si, float(b - REF_BIN))
			_lut_img.set_pixel(b, si, Color(_o_fol, _o_aut, _o_bloom, _o_flush))
	_lut_tex.update(_lut_img)


# ------------------------------------------------------------------ ladicí vrstva

const DEBUG_R := 24.0

## Vrstva `fenologie` (F2 → Příroda – ladění): fáze dominantního druhu v buňce – zelená = olistění, oranžová = podzim,
## růžová = květ, hnědá = holé, šedá = bez stromů.
func debug_layer(x: float, z: float) -> Color:
	var te: TreeEco = world.tree_eco if world != null else null
	if te == null:
		return Color(0, 0, 0, 0)
	var pos := Vector3(x, 0.0, z)
	var sn := te.species_near(pos, DEBUG_R)
	var best := ""
	var bv := 0.0
	for id in sn:
		if float(sn[id]) > bv:
			bv = float(sn[id])
			best = String(id)
	if best == "":
		return Color(0, 0, 0, 0)
	var ph := phase(best, pos)
	var c := Color(0.45, 0.32, 0.18).lerp(Color(0.2, 0.75, 0.15), float(ph["foliage"]))
	c = c.lerp(Color(1.0, 0.55, 0.05), float(ph["autumn"]) * float(ph["foliage"]))
	c = c.lerp(Color(1.0, 0.6, 0.85), float(ph["bloom"]) * 0.8)
	return Color(c.r, c.g, c.b, 0.65)


# ------------------------------------------------------------------ ukládání (klíč `phenology`)

func to_dict() -> Dictionary:
	var fr := []
	for v in frost:
		fr.append(snappedf(v, 0.01))
	var tm := []
	for d in range(1, cur_doy + 1):
		tm.append(snappedf(tmean[d], 0.1))
	var gs := []
	for v in growth_stress:
		gs.append(snappedf(v, 0.01))
	return {"year": year, "last_jd": last_jd, "doy": cur_doy, "gdd": gdd_sum, "warm": warm_days, "chill": chill_days,
		"aut": aut_chill, "aut_n": aut_cool_days, "tmean": tm, "frost": fr, "hist": hist.duplicate(true),
		"events": Array(events), "last_year": Array(last_year), "grow_years": growth_years, "stress": gs,
		"dr_sum": _drought_sum, "dr_n": _drought_n, "frost_y": _frost_year}


func restore(d: Dictionary) -> void:
	if d.is_empty():
		# starý save bez klíče: rok se rozběhne z klimatu, stromy beze změny (růst od teď)
		growth_years = 0
		growth_stress = PackedFloat32Array()
		_apply_growth()
		_regrow_pending = true            # strom zpět na velikost z dat, pokud v téhle hře už rostl
		last_jd = -1
		if world != null and world.clock != null:
			_spin_up(world.clock.jd() - 1)
		_update_lut()
		_maybe_regrow()
		return
	year = int(d.get("year", 0))
	last_jd = int(d.get("last_jd", -1))
	cur_doy = int(d.get("doy", 1))
	gdd_sum = float(d.get("gdd", 0.0))
	warm_days = int(d.get("warm", 0))
	chill_days = int(d.get("chill", 0))
	aut_chill = float(d.get("aut", 0.0))
	aut_cool_days = int(d.get("aut_n", 0))
	tmean.fill(0.0)
	var tm: Array = d.get("tmean", [])
	for k in mini(tm.size(), tmean.size() - 1):
		tmean[k + 1] = float(tm[k])
	frost.fill(0.0)
	var fr: Array = d.get("frost", [])
	for k in mini(fr.size(), frost.size()):
		frost[k] = float(fr[k])
	hist = (d.get("hist", {}) as Dictionary).duplicate(true)
	events.clear()
	for e in d.get("events", []):
		events.append(String(e))
	last_year.clear()
	for e in d.get("last_year", []):
		last_year.append(String(e))
	growth_years = int(d.get("grow_years", 0))
	growth_stress = PackedFloat32Array()
	for v in d.get("stress", []):
		growth_stress.append(float(v))
	_drought_sum = float(d.get("dr_sum", 0.0))
	_drought_n = int(d.get("dr_n", 0))
	_frost_year = float(d.get("frost_y", 0.0))
	_apply_growth()
	_regrow_pending = true                # vzhled stromů podle uložených let růstu (po kouscích)
	if world != null and world.clock != null:
		_catch_up(world.clock.jd() - 1)
	_update_lut()
	_maybe_regrow()
