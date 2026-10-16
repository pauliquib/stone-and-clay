## M8.D2c: menu pro vývojáře – kategorie **Příroda**: počasí, roční doby, obloha a světlo, vítr, voda a půda,
## mikroklima, dřeviny a les, pole a louky, louže a stopy, kouř a ostatní. Úplný seznam konstant, které ovlivňují
## chování přírody (simulace, časování, prahy, vzorce) – ne čistě technické (buffery, indexy, cesty) ani offline data
## (`site.bin`, `tree_eco.bin`, treegen). Výchozí hodnoty se berou z kódu (`DevTune.tune` čte současnou `static var`
## / klíč slovníku) – chování ve výchozím stavu beze změny. Za snímek se registr nečte: systémy čtou své `static var`.
extends RefCounted

const POC := "Příroda/Počasí"
const POC_SIT := "Příroda/Počasí – situace a přechody"
const ROC := "Příroda/Roční doby"
const OBL := "Příroda/Obloha a světlo"
const VIT := "Příroda/Vítr"
const VOD := "Příroda/Voda a půda"
const MIK := "Příroda/Mikroklima"
const LES := "Příroda/Dřeviny a les"
const POL := "Příroda/Pole a louky"
const LOU := "Příroda/Louže, stopy"
const KOU := "Příroda/Kouř a ostatní"

## Podskupina, do které právě registrujeme (`_t` ji čte – kratší řádky registrace).
static var _g := ""


## Zaregistruje číselnou proměnnou (static var skriptu, klíč slovníku, index pole, vlastnost objektu).
## Rozsah posuvníku bez `lo` / `hi` = 0–3× výchozí (záporná výchozí: 3× výchozí … |výchozí|), krok podle řádu.
static func _t(target: Variant, prop: Variant, id: String, label: String, unit := "", help := "",
		lo := NAN, hi := NAN, step := NAN) -> void:
	var def: Variant = _cur(target, prop)
	if def == null:
		push_error("tune_priroda: %s nemá %s (id %s)" % [str(target), str(prop), id])
		return
	if def is bool:
		DevTune.tune(target, prop, id, _g, label, 0.0, 1.0, 1.0, help, unit)
		return
	var v := float(def)
	if is_nan(lo):
		lo = 0.0 if v >= 0.0 else v * 3.0
	if is_nan(hi):
		if def is int:
			hi = maxf(v * 3.0, 10.0)
		else:
			hi = absf(v) * 3.0 if absf(v) > 0.0 else 1.0
	if is_nan(step):
		if def is int:
			step = 1.0
		else:
			var m := maxf(absf(lo), absf(hi))
			step = pow(10.0, floorf(log(m) / log(10.0)) - 2.0) if m > 0.0 else 0.01
	DevTune.tune(target, prop, id, _g, label, lo, hi, step, help, unit)


static func _cur(target: Variant, prop: Variant) -> Variant:
	if target is Dictionary:
		return (target as Dictionary).get(prop)
	if target is Array:
		var a: Array = target
		return a[int(prop)] if int(prop) >= 0 and int(prop) < a.size() else null
	if target is Object:
		return (target as Object).get(StringName(prop))
	return null


static func register_all() -> void:
	_pocasi()
	_rocni_doby()
	_obloha()
	_vitr()
	_voda()
	_mikroklima()
	_dreviny()
	_pole()
	_louze()
	_kour()


## Změna v menu F3: systémy s předpočítanou mezipamětí si ji při nejbližší příležitosti přepočítají
## (jedno porovnání čítače za snímek / za hodinu – registr se za snímek nečte).
static func on_changed(id: String, _value: Variant) -> void:
	if id.begins_with("wind."):
		WindField.invalidate()
	elif id.begins_with("soil."):
		SoilWater.invalidate()
	elif id.begins_with("micro."):
		Microclimate.invalidate()
	elif id.begins_with("veg."):
		VegetationManager.invalidate()


# ------------------------------------------------------------------ Počasí (Weather)

static func _pocasi() -> void:
	var W = Weather
	_g = POC
	_t(W, "TAU_CLOUD", "weather.tau_cloud", "Náběh – oblačnost (časová konstanta)", "h", "Za jak dlouho se oblačnost přiblíží cíli situace (63 %).", 0.01, 5.0)
	_t(W, "TAU_RAIN", "weather.tau_rain", "Náběh – srážky (časová konstanta)", "h", "", 0.01, 3.0)
	_t(W, "TAU_FOG", "weather.tau_fog", "Náběh – mlha (časová konstanta)", "h", "", 0.01, 5.0)
	_t(W, "TAU_WIND", "weather.tau_wind", "Náběh – vítr (časová konstanta)", "h", "", 0.01, 3.0)
	_t(W, "TAU_TEMP", "weather.tau_temp", "Náběh – teplota (časová konstanta)", "h", "Setrvačnost teploty vzduchu vůči cíli.", 0.05, 6.0)
	_t(W, "SNOW_BELOW", "weather.snow_below_c", "Sníh – sněží pod teplotou", "°C", "Pod touto teplotou padá místo deště sníh (i hranice sněžení v mikroklimatu).", -5.0, 5.0, 0.1)
	_t(W, "RAIN_MM_H", "weather.rain_mm_h", "Srážky – úhrn při intenzitě 1", "mm/h", "Kolik mm/h odpovídá rain = 1 (čte i vodní bilance půdy).", 1.0, 80.0, 0.5)
	_t(W, "DROUGHT_TAU_H", "weather.drought_tau_h", "Sucho – sledování indexu z vodní bilance", "h", "Jak rychle se `drought` přiblíží indexu z vlhkosti půdy (M8.7).", 1.0, 240.0, 1.0)
	_t(W, "WARMUP_H", "weather.warmup_h", "Start – předsimulace počasí", "h", "Kolik hodin se nasimuluje při startu a po skoku v kalendáři (sníh, mokro).", 0.0, 240.0, 1.0)
	_t(W, "SHOWER_NOISE_FREQ", "weather.shower_noise_freq", "Přeháňky – četnost přestávek", "1/h", "Frekvence šumu přeháněk (0,9 ≈ přestávka zhruba po hodině).", 0.05, 5.0)
	_t(W, "ANOM_NOISE_FREQ", "weather.anom_noise_freq", "Odchylka – rychlost změn (šum)", "", "Frekvence šumu teplotní a větrné odchylky (mění se za několik dní).", 0.005, 0.5, 0.001)
	_t(W, "RAIN_MIN", "weather.rain_min", "Srážky – práh mokra a sněžení", "", "Slabší srážky nemočí, nesněží a nebrání osychání.", 0.0, 0.2, 0.001)
	_t(W, "SHOWER_ON_LO", "weather.shower_on_lo", "Přeháňky – práh přestávky (šum)", "", "Šum pod prahem = přestávka bez srážek.", -1.0, 1.0)
	_t(W, "SHOWER_ON_HI", "weather.shower_on_hi", "Přeháňky – práh plné přeháňky (šum)", "", "", -1.0, 1.0)
	_t(W, "SHOWER_GAP_CLOUD", "weather.shower_gap_cloud", "Přeháňky – oblačnost v přestávce", "×", "Násobek oblačnosti situace, když zrovna neprší.", 0.0, 1.0)
	_t(W, "SHOWER_WIND_BASE", "weather.shower_wind_base", "Přeháňky – vítr v přestávce", "×")
	_t(W, "SHOWER_WIND_GAIN", "weather.shower_wind_gain", "Přeháňky – přídavek větru při srážkách", "×")
	_t(W, "FOG_BURN_FROM_H", "weather.fog_burn_from_h", "Mlha – rozpouštění ve dne od", "h", "", 0.0, 24.0, 0.25)
	_t(W, "FOG_BURN_TO_H", "weather.fog_burn_to_h", "Mlha – rozpouštění ve dne do", "h", "", 0.0, 24.0, 0.25)
	_t(W, "FOG_BURN_BASE", "weather.fog_burn_base", "Mlha – podíl rozpuštěný v zimě", "", "", 0.0, 1.0)
	_t(W, "FOG_BURN_SUMMER", "weather.fog_burn_summer", "Mlha – přídavek rozpouštění v létě", "", "Násobí zeleň (vegetační sezónu).", 0.0, 1.0)
	_t(W, "HAZE_FOG", "weather.haze_fog", "Mlha – opar za jasných zimních rán", "", "Mlha při jasnu ráno a večer mimo vegetační sezónu.", 0.0, 1.0)
	_t(W, "HAZE_MORNING_H", "weather.haze_morning_h", "Mlha – opar ráno do", "h", "", 0.0, 24.0, 0.25)
	_t(W, "HAZE_EVENING_H", "weather.haze_evening_h", "Mlha – opar večer od", "h", "", 0.0, 24.0, 0.25)
	_t(W, "WIND_ANOM_BASE", "weather.wind_anom_base", "Vítr – základ kolísání", "×", "Vítr = vítr situace × (základ + rozkmit × šum).")
	_t(W, "WIND_ANOM_AMP", "weather.wind_anom_amp", "Vítr – rozkmit kolísání", "×")
	_t(W, "WIND_ANOM_RATE", "weather.wind_anom_rate", "Vítr – rychlost kolísání", "×")
	_t(W, "WIND_BEARING_MEAN", "weather.wind_bearing_mean", "Vítr – převládající směr (odkud)", "°", "250° = od západo-jihozápadu.", 0.0, 360.0, 1.0)
	_t(W, "WIND_BEARING_SWING", "weather.wind_bearing_swing", "Vítr – rozkmit směru", "±°", "", 0.0, 180.0, 1.0)
	_t(W, "WIND_BEARING_RATE", "weather.wind_bearing_rate", "Vítr – rychlost stáčení směru", "×")
	_t(W, "STORM_RATE_H", "weather.storm_rate_h", "Bouřka – nástup a odeznění", "1/h")
	_t(W, "LIGHTNING_STORM_MIN", "weather.lightning_storm_min", "Blesky – od síly bouřky", "", "", 0.0, 1.0)
	_t(W, "LIGHTNING_RAIN_MIN", "weather.lightning_rain_min", "Blesky – od intenzity srážek", "", "", 0.0, 1.0)
	_t(W, "LIGHTNING_GAP_MIN_S", "weather.lightning_gap_min_s", "Blesky – rozestup nejméně", "s", "Reálné sekundy (dělí se silou bouřky).")
	_t(W, "LIGHTNING_GAP_MAX_S", "weather.lightning_gap_max_s", "Blesky – rozestup nejvíc", "s")
	_t(W, "LIGHTNING_DIST_MIN", "weather.lightning_dist_min", "Blesky – vzdálenost úderu nejméně", "m")
	_t(W, "LIGHTNING_DIST_MAX", "weather.lightning_dist_max", "Blesky – vzdálenost úderu nejvíc", "m")
	_t(W, "RAIN_RECENT_GAIN", "weather.rain_recent_gain", "Vlhko z posledních dnů – přírůstek deštěm", "/h", "Za hodinu plného deště (hřiby).")
	_t(W, "RAIN_RECENT_DECAY_D", "weather.rain_recent_decay_d", "Vlhko z posledních dnů – úbytek", "/den")
	_t(W, "DROUGHT_BASE_D", "weather.drought_base_d", "Sucho – přírůstek bez deště", "/den", "Počítadlo sucha bez vodní bilance (a před ní).")
	_t(W, "DROUGHT_HOT_C", "weather.drought_hot_c", "Sucho – rychleji nad teplotou", "°C", "", 0.0, 40.0, 0.5)
	_t(W, "DROUGHT_HOT_D", "weather.drought_hot_d", "Sucho – přírůstek za °C nad prahem", "/den·°C")
	_t(W, "DROUGHT_RAIN", "weather.drought_rain", "Sucho – úbytek deštěm", "/h")
	_t(W, "FROST_HOLD_C", "weather.frost_hold_c", "Vynucený mráz – teplota nejvýš", "°C", "F2 → Počasí → sněžení / náledí.", -20.0, 5.0, 0.5)
	_t(W, "FORCED_FROST_C", "weather.forced_frost_c", "Vynucený mráz – teplota po vynucení", "°C", "", -20.0, 5.0, 0.5)
	_t(W, "SUN_FULL_ELEV", "weather.sun_full_elev", "Slunce – svítí naplno od výšky", "°", "Pro tání sněhu a osychání.", 1.0, 90.0, 1.0)
	_t(W, "SUN_CLOUD_DIM", "weather.sun_cloud_dim", "Slunce – oblačnost ubírá", "×", "", 0.0, 1.0)
	_t(W, "SNOW_ACCUM", "weather.snow_accum", "Sníh – přírůstek pokrývky", "/h", "Za hodinu plného sněžení (pokrývka 1 ≈ 10 cm).")
	_t(W, "MELT_ABOVE_C", "weather.melt_above_c", "Sníh – taje nad", "°C", "", -3.0, 5.0, 0.1)
	_t(W, "MELT_TEMP", "weather.melt_temp", "Sníh – tání teplem", "/h·°C")
	_t(W, "MELT_RAIN", "weather.melt_rain", "Sníh – tání deštěm", "/h")
	_t(W, "MELT_SUN", "weather.melt_sun", "Sníh – tání sluncem", "/h")
	_t(W, "MELT_WET_GAIN", "weather.melt_wet_gain", "Mokro – z tajícího sněhu", "× pokrývka")
	_t(W, "MELT_WET_MAX", "weather.melt_wet_max", "Mokro – z tajícího sněhu nejvýš", "", "", 0.0, 1.0)
	_t(W, "WET_RAIN", "weather.wet_rain", "Mokro – přírůstek deštěm", "/h")
	_t(W, "DRY_BASE", "weather.dry_base", "Mokro – osychání (základ)", "/h")
	_t(W, "DRY_TEMP", "weather.dry_temp", "Mokro – osychání teplem", "/h·°C")
	_t(W, "DRY_WIND", "weather.dry_wind", "Mokro – osychání větrem", "/h per m/s")
	_t(W, "DRY_SUN", "weather.dry_sun", "Mokro – osychání sluncem", "/h")
	_t(W, "DRY_FROZEN", "weather.dry_frozen", "Mokro – osychání pod nulou (podíl)", "×", "", 0.0, 1.0)
	_t(W, "TEMP_CLOUD_DAMP", "weather.temp_cloud_damp", "Teplota – oblačnost tlumí denní rozkmit", "×", "", 0.0, 1.0)
	_t(W, "TEMP_ANOM_C", "weather.temp_anom_c", "Teplota – dlouhodobá odchylka", "±°C", "Teplé a studené vlny proti měsíčnímu průměru.")
	_t(W, "TEMP_ANOM_RATE", "weather.temp_anom_rate", "Teplota – rychlost změny odchylky", "×")
	_t(W, "TEMP_MIN_H", "weather.temp_min_h", "Teplota – denní minimum v", "h", "", 0.0, 23.0, 0.25)
	_t(W, "TEMP_MAX_H", "weather.temp_max_h", "Teplota – denní maximum v", "h", "", 1.0, 23.5, 0.25)
	_t(W, "TEMP_RAIN_COOL", "weather.temp_rain_cool", "Teplota – ochlazení deštěm", "°C", "Při plném dešti.")
	_t(W, "TEMP_FOG_COOL", "weather.temp_fog_cool", "Teplota – ochlazení mlhou", "°C", "Při husté mlze.")
	_t(W, "FORECAST_TMAX_K", "weather.forecast_tmax_k", "Předpověď – maximum z rozkmitu", "×", "Odhad zítřejšího maxima = průměr + K × denní rozkmit.", 0.0, 1.0)
	_t(W, "MUD_WET", "weather.mud_wet", "Přilnavost – bláto na terénu od mokra", "", "Bez vodní bilance půdy (globální mokro).", 0.0, 1.0)
	_t(W, "ICE_FULL_WET", "weather.ice_full_wet", "Přilnavost – náledí naplno od mokra", "", "", 0.05, 1.0)
	# --- situace a přechody (Weather.TYPES / NEXT)
	_g = POC_SIT
	_t(W, "WET_DAYS_REF", "weather.wet_days_ref", "Přechody – srážkové dny pro váhu 1", "dní", "Váha deště a přeháněk = srážkové dny měsíce / tato hodnota.", 1.0, 30.0, 0.5)
	_t(W, "STORM_W", "weather.storm_w", "Přechody – váha bouřky", "×", "Násobí podíl bouřek měsíce (Seasons.STORM_SHARE).")
	_t(W, "STORM_DAY_MULT", "weather.storm_day_mult", "Přechody – bouřka odpoledne ×", "×")
	_t(W, "STORM_NIGHT_MULT", "weather.storm_night_mult", "Přechody – bouřka mimo odpoledne ×", "×")
	_t(W, "STORM_FROM_H", "weather.storm_from_h", "Přechody – bouřkové odpoledne od", "h", "", 0.0, 24.0, 0.25)
	_t(W, "STORM_TO_H", "weather.storm_to_h", "Přechody – bouřkové odpoledne do", "h", "", 0.0, 24.0, 0.25)
	_t(W, "FOG_W_BASE", "weather.fog_w_base", "Přechody – váha mlhy (zima)", "×", "Váha mlhy = zima − léto × zeleň.")
	_t(W, "FOG_W_SUMMER", "weather.fog_w_summer", "Přechody – mlha v létě ubývá o", "×")
	_t(W, "FOG_W_NIGHT", "weather.fog_w_night", "Přechody – mlha ráno a večer ×", "×")
	_t(W, "FOG_W_DAY", "weather.fog_w_day", "Přechody – mlha přes den ×", "×")
	_t(W, "FOG_W_MORNING_H", "weather.fog_w_morning_h", "Přechody – mlhové ráno do", "h", "", 0.0, 24.0, 0.25)
	_t(W, "FOG_W_EVENING_H", "weather.fog_w_evening_h", "Přechody – mlhový večer od", "h", "", 0.0, 24.0, 0.25)
	_t(W, "OVERCAST_W_WINTER", "weather.overcast_w_winter", "Přechody – zataženo v zimě (inverze)", "×", "Váha zataženo = hodnota − zeleň.")
	_t(W, "CLEAR_W_BASE", "weather.clear_w_base", "Přechody – jasno / polojasno (zima)", "×", "Váha = zima + léto × zeleň.")
	_t(W, "CLEAR_W_SUMMER", "weather.clear_w_summer", "Přechody – jasno / polojasno přídavek v létě", "×")
	var types: Dictionary = Weather.TYPES
	for k in types:
		var t: Dictionary = types[k]
		var nm: String = t["name"]
		_t(t, "cloud", "weather.type.%s.cloud" % k, "Situace %s – oblačnost" % nm, "", "Cíl oblačnosti 0..1.", 0.0, 1.0)
		_t(t, "rain", "weather.type.%s.rain" % k, "Situace %s – srážky" % nm, "", "Cíl intenzity srážek 0..1 (1 ≈ 25 mm/h).", 0.0, 1.0)
		_t(t, "fog", "weather.type.%s.fog" % k, "Situace %s – mlha" % nm, "", "Cíl mlhy 0..1.", 0.0, 1.0)
		_t(t, "wind", "weather.type.%s.wind" % k, "Situace %s – vítr" % nm, "m/s", "Cíl průměrného větru.", 0.0, 30.0, 0.1)
		var hr: Array = t["hours"]
		_t(hr, 0, "weather.type.%s.hours_min" % k, "Situace %s – trvání nejméně" % nm, "h", "", 0.1, 72.0, 0.1)
		_t(hr, 1, "weather.type.%s.hours_max" % k, "Situace %s – trvání nejvíc" % nm, "h", "", 0.1, 120.0, 0.1)
	var nxt: Dictionary = Weather.NEXT
	for a in nxt:
		var row: Dictionary = nxt[a]
		for b in row:
			_t(row, b, "weather.next.%s.%s" % [a, b], "Přechody – %s → %s (váha)" % [types[a]["name"], types[b]["name"]],
				"", "Relativní váha přechodu (dál ji násobí roční období a denní doba).", 0.0, 10.0, 0.1)


# ------------------------------------------------------------------ Roční doby (Seasons, SeasonFx)

const _MONTHS := ["leden", "únor", "březen", "duben", "květen", "červen", "červenec", "srpen", "září", "říjen",
	"listopad", "prosinec"]


## Křivka [den v roce, hodnota]: hodnota každého bodu a den vnitřních bodů (krajní 1 a 366 drží rok).
static func _curve(table: Array, key: String, area: String, help: String, hi := 1.0) -> void:
	for i in table.size():
		var pt: Array = table[i]
		var d0 := int(pt[0])
		_t(pt, 1, "season.%s.%d.value" % [key, i], "%s – bod %d: hodnota" % [area, i + 1], "",
			"%s Výchozí bod: den %d = %s." % [help, d0, str(pt[1])], 0.0, hi, 0.01)
		if i > 0 and i < table.size() - 1:
			_t(pt, 0, "season.%s.%d.day" % [key, i], "%s – bod %d: den v roce" % [area, i + 1], "den",
				"Den v roce bodu křivky (musí ležet mezi sousedními body). Výchozí %d." % d0, 1.0, 366.0, 1.0)


static func _rocni_doby() -> void:
	_g = ROC
	_curve(Seasons.FOLIAGE, "foliage", "Olistění", "Olistění listnáčů 0..1 (rašení, opad; stromy, stín, zachycení deště).")
	_curve(Seasons.AUTUMN, "autumn", "Podzimní zbarvení", "Podzimní barva listí 0..1.")
	_curve(Seasons.GREEN, "green", "Zeleň trávy a polí", "Svěžest trávy 0..1 (ovlivňuje i mlhu, výpar orné půdy a počasí).")
	_curve(Seasons.BLOOM, "bloom", "Kvetení", "Kvetení luk a sadů 0..1 (květy, včely).")
	for m in 12:
		var mn: String = _MONTHS[m]
		_t(Seasons.TEMP_MEAN, m, "season.temp_mean.%d" % (m + 1), "Klima – průměrná teplota: %s" % mn, "°C",
			"Měsíční normál (střed měsíce, mezi měsíci lineárně). Řídí počasí, výpar a mikroklima.", -15.0, 30.0, 0.1)
	for m in 12:
		_t(Seasons.TEMP_RANGE, m, "season.temp_range.%d" % (m + 1), "Klima – denní rozkmit teploty: %s" % _MONTHS[m],
			"°C", "Rozdíl denního maxima a minima za jasna.", 0.0, 25.0, 0.1)
	for m in 12:
		_t(Seasons.WET_DAYS, m, "season.wet_days.%d" % (m + 1), "Klima – srážkové dny: %s" % _MONTHS[m], "dní",
			"Dny se srážkami ≥ 1 mm – váha deště a přeháněk v přechodech počasí.", 0.0, 31.0, 1.0)
	for m in 12:
		_t(Seasons.STORM_SHARE, m, "season.storm_share.%d" % (m + 1), "Klima – podíl bouřek: %s" % _MONTHS[m], "",
			"Podíl bouřek na srážkových dnech.", 0.0, 1.0, 0.01)
	_t(Seasons, "SWALLOWS_FROM", "season.swallows_from", "Tažní ptáci – přílet (den v roce)", "den", "Vlaštovky u nás od…", 1.0, 366.0, 1.0)
	_t(Seasons, "SWALLOWS_TO", "season.swallows_to", "Tažní ptáci – odlet (den v roce)", "den", "", 1.0, 366.0, 1.0)
	_t(SeasonFx, "TICK_S", "season.fx_tick_s", "Sezónní efekty – obnova", "s", "Jak často se přepočítá kvetení, louže, ovoce a LOD vegetace.", 0.05, 5.0, 0.05)
	_t(SeasonFx, "SNOW_HIDES_BLOOM", "season.snow_hides_bloom", "Kvetení – sníh skryje květy", "× pokrývka",
		"Květy mizí pod sněhem (2 = při pokrývce 0,5 žádné). Platí pro terén i květy kolem hráče.", 0.0, 10.0, 0.1)
	DevTune.link("season.snow_hides_bloom", MeadowFlowers, "SNOW_HIDES_BLOOM")


# ------------------------------------------------------------------ Obloha a světlo (Atmosphere, SkyModel)

static func _obloha() -> void:
	var A = Atmosphere
	var S = Atmosphere.SkyModel
	_g = OBL
	_t(S, "SUN_LUX_ZENITH", "sky.sun_lux_zenith", "Světlo – slunce v zenitu (jasno)", "lx", "Přímá osvětlenost jasného poledne v zenitu (fyzikálně ~100 000 lx).", 10000.0, 200000.0, 500.0)
	_t(S, "SKY_LUX_CLEAR", "sky.sky_lux_clear", "Světlo – difuzní obloha za jasna", "lx", "", 1000.0, 60000.0, 100.0)
	_t(S, "SKY_LUX_OVERCAST", "sky.sky_lux_overcast", "Světlo – zatažená obloha", "lx", "", 500.0, 40000.0, 100.0)
	_t(S, "SKY_LUX_TWILIGHT", "sky.sky_lux_twilight", "Světlo – konec občanského soumraku (−6°)", "lx")
	_t(S, "SKY_LUX_NIGHT", "sky.sky_lux_night", "Světlo – konec nautického soumraku (−12°)", "lx", "", 0.00001, 0.01, 0.00001)
	_t(S, "MOON_LUX_FULL", "sky.moon_lux_full", "Světlo – úplněk vysoko", "lx")
	_t(S, "STARLIGHT_LUX", "sky.starlight_lux", "Světlo – hvězdná noc", "lx", "", 0.0, 0.01, 0.0001)
	_t(S, "LIGHT_POLLUTION_LUX", "sky.light_pollution_lux", "Světlo – světelný smog obce (plný)", "lx")
	_t(S, "EV_REF_LUX", "sky.ev_ref_lux", "Expozice – referenční osvětlenost EV100", "lx", "ISO 12232: EV100 = log2(lux / 2,5).", 0.5, 10.0, 0.1)
	_t(S, "TAU_CLEAR", "sky.tau_clear", "Obloha – optická hloubka jasného vzduchu", "", "Rayleigh + ozon; víc = slabší a červenější slunce nízko.", 0.0, 0.5, 0.005)
	_t(S, "TAU_HAZE", "sky.tau_haze", "Obloha – přídavek optické hloubky v oparu", "", "Mie rozptyl při plném oparu / mlze.", 0.0, 2.0, 0.01)
	_t(S, "TINT_R", "sky.tint_r", "Obloha – útlum červené (zčervenání slunce)", "×", "", 0.0, 3.0, 0.01)
	_t(S, "TINT_G", "sky.tint_g", "Obloha – útlum zelené", "×", "", 0.0, 3.0, 0.01)
	_t(S, "TINT_B", "sky.tint_b", "Obloha – útlum modré", "×", "", 0.0, 4.0, 0.01)
	_t(S, "CLOUD_DIRECT_MIN", "sky.cloud_direct_min", "Světlo – přímé slunce pod plnou oblačností", "", "", 0.0, 1.0)
	_t(S, "CLOUD_DIRECT_FROM", "sky.cloud_direct_from", "Světlo – mraky zakrývají slunce od", "", "", 0.0, 1.0)
	_t(S, "CLOUD_DIRECT_TO", "sky.cloud_direct_to", "Světlo – mraky zakryjí slunce úplně při", "", "", 0.0, 1.0)
	_t(S, "OVERCAST_SKY_FROM", "sky.overcast_sky_from", "Světlo – difuzní jas: zataženo od", "", "", 0.0, 1.0)
	_t(S, "OVERCAST_SKY_TO", "sky.overcast_sky_to", "Světlo – difuzní jas: zataženo naplno", "", "", 0.0, 1.0)
	_t(S, "HAZE_SKY_DIM", "sky.haze_sky_dim", "Světlo – opar tlumí difuzní jas", "", "", 0.0, 1.0)
	_t(S, "HORIZON_SUNSET", "sky.horizon_sunset", "Světlo – jas oblohy při západu", "× jasno", "")
	_t(S, "LUMINOUS_EFFICACY", "sky.luminous_efficacy", "Světlo – světelná účinnost slunce", "lm/W", "Převod lux → W/m² (fotosyntéza, tepelná bilance).", 50.0, 200.0, 1.0)
	_t(A, "SUN_ENERGY", "sky.sun_energy", "Světlo – síla slunce ve scéně", "", "Energie DirectionalLight při plném slunci.")
	_t(A, "MOON_ENERGY", "sky.moon_energy", "Světlo – síla měsíce ve scéně", "")
	_t(A, "EXPOSURE_MID_EV", "sky.exposure_mid_ev", "Expozice – kalibrace na jasné poledne", "EV100", "Nad touto EV je expozice 1,0; pod ní roste (oko se roztáhne).", 5.0, 20.0, 0.1)
	_t(A, "EXPOSURE_DARK_GAIN", "sky.exposure_dark_gain", "Expozice – zesílení ve tmě", "/EV")
	_t(A, "EXPOSURE_MAX_MULT", "sky.exposure_max_mult", "Expozice – nejvyšší násobek", "×", "", 1.0, 10.0, 0.05)
	_t(A, "ADAPT_RATE_LIGHT", "sky.adapt_rate_light", "Expozice – adaptace do světla", "EV/s")
	_t(A, "ADAPT_RATE_DARK", "sky.adapt_rate_dark", "Expozice – adaptace do tmy", "EV/s")
	_t(A, "INDOOR_REF_LUX", "sky.indoor_ref_lux", "Expozice – osvětlení uvnitř budov", "lx")
	_t(A, "EXPOSURE_OVERCAST", "sky.exposure_overcast", "Expozice – přídavek za zatažena", "×", "", 0.0, 1.0)
	_t(A, "PURKINJE_EV", "sky.purkinje_ev", "Expozice – Purkyňův posun: plná desaturace pod", "−EV100")
	_t(A, "PURKINJE_SAT", "sky.purkinje_sat", "Expozice – sytost barev v hluboké tmě", "", "", 0.0, 1.0)
	_t(A, "LEGACY_EXPOSURE_NIGHT", "sky.legacy_exposure_night", "Expozice – stará obloha: noc", "×", "Jen s vypnutým realismem „Obloha“.")
	_t(A, "LEGACY_EXPOSURE_OVERCAST", "sky.legacy_exposure_overcast", "Expozice – stará obloha: zataženo", "×", "Jen s vypnutým realismem „Obloha“.")
	_t(A, "INDOOR_FADE_RATE", "sky.indoor_fade_rate", "Světlo – přechod při vstupu do budovy", "1/s")
	_t(A, "WARM_ELEV", "sky.warm_elev", "Světlo – teplé světlo a mlha pod výškou slunce", "°", "", 1.0, 60.0, 0.5)
	_t(A, "OVERCAST_FROM", "sky.overcast_from", "Světlo – zataženo (stíny, měsíc) od oblačnosti", "", "", 0.0, 1.0)
	_t(A, "MOON_OVERCAST_DIM", "sky.moon_overcast_dim", "Světlo – zatažená obloha tlumí měsíc", "", "", 0.0, 1.0)
	_t(A, "SHADOW_OVERCAST_DIM", "sky.shadow_overcast_dim", "Světlo – zatažená obloha změkčí stíny", "", "", 0.0, 1.0)
	_t(A, "AMBIENT_NIGHT", "sky.ambient_night", "Světlo – prostředí v noci", "", "Ve dne 1.", 0.0, 1.0)
	_t(A, "AMBIENT_DARK_DIM", "sky.ambient_dark_dim", "Světlo – tmavé mraky ubírají prostředí", "", "", 0.0, 1.0)
	_t(A, "AMBIENT_INDOOR", "sky.ambient_indoor", "Světlo – prostředí uvnitř budov", "×", "", 0.0, 1.0)
	_t(A, "FLASH_AMBIENT", "sky.flash_ambient", "Blesky – záblesk rozsvítí okolí", "")
	_t(A, "FLASH_DECAY", "sky.flash_decay", "Blesky – dosvit záblesku", "1/s")
	_t(A, "FLASH_POWER_DIST", "sky.flash_power_dist", "Blesky – síla záblesku slábne na", "m")
	_t(A, "SOUND_SPEED", "sky.sound_speed", "Blesky – rychlost zvuku (zpoždění hromu)", "m/s", "", 100.0, 1000.0, 1.0)
	_t(A, "CLOUD_DARK_RAIN", "sky.cloud_dark_rain", "Obloha – ztmavnutí mraků deštěm", "×")
	_t(A, "CLOUD_DARK_STORM", "sky.cloud_dark_storm", "Obloha – ztmavnutí mraků bouřkou", "×")
	_t(A, "CLOUD_DRIFT", "sky.cloud_drift", "Obloha – rychlost tahu mraků po větru", "UV/m", "", 0.0, 0.002, 0.00001)
	_t(A, "LP_RATE", "sky.lp_rate", "Obloha – přechod světelného smogu", "1/s")
	_t(A, "HAZE_FOG", "sky.haze_fog", "Opar – z mlhy", "×", "Opar (Mie, barva slunce, difuzní jas) = mlha × tohle + déšť × …", 0.0, 2.0)
	_t(A, "HAZE_RAIN", "sky.haze_rain", "Opar – z deště", "×", "", 0.0, 2.0)
	_t(A, "FOG_BASE", "sky.fog_base", "Mlha – základní hustota (opar krajiny)", "1/m", "", 0.0, 0.002, 0.00001)
	_t(A, "FOG_MIST", "sky.fog_mist", "Mlha – hustota v husté mlze", "1/m", "Násobí se mlha² (Weather.fog).", 0.0, 0.05, 0.0001)
	_t(A, "FOG_RAIN", "sky.fog_rain", "Mlha – hustota v dešti", "1/m", "", 0.0, 0.01, 0.0001)
	_t(A, "HIGH_FROM_M", "sky.high_from_m", "Mlha – ve výšce řidne od", "m AGL")
	_t(A, "HIGH_TO_M", "sky.high_to_m", "Mlha – ve výšce řidne naplno", "m AGL")
	_t(A, "FOG_HIGH_THIN", "sky.fog_high_thin", "Mlha – zředění ve výšce", "", "", 0.0, 1.0)
	_t(A, "FOG_SKY_FOG", "sky.fog_sky_fog", "Mlha – zakrytí oblohy mlhou", "×", "", 0.0, 2.0)
	_t(A, "FOG_SKY_RAIN", "sky.fog_sky_rain", "Mlha – zakrytí oblohy deštěm", "×", "", 0.0, 2.0)
	_t(A, "FOG_SKY_HIGH", "sky.fog_sky_high", "Mlha – zakrytí oblohy ve výšce", "×", "", 0.0, 2.0)
	_t(A, "FOG_SKY_MAX", "sky.fog_sky_max", "Mlha – zakrytí oblohy nejvýš", "", "", 0.0, 1.0)
	_t(A, "AERIAL_LOW", "sky.aerial_low", "Mlha – vzdušná perspektiva u země", "", "", 0.0, 1.0)
	_t(A, "AERIAL_HIGH", "sky.aerial_high", "Mlha – vzdušná perspektiva ve výšce", "", "", 0.0, 1.0)
	_t(A, "TREE_FAR_HIGH", "sky.tree_far_high", "Dohled – stromy ve výšce dál", "×", "", 1.0, 6.0, 0.05)
	_t(A, "GRASS_SNOW_DIM", "sky.grass_snow_dim", "Sezóna – sníh ubírá zeleň trávy", "", "Shader grass_green.", 0.0, 1.0)
	_t(A, "WIND_STRENGTH_FULL", "sky.wind_strength_full", "Vítr – stará síla ohybu: plná při", "m/s", "Globální shader wind_strength = vítr / tato rychlost (stará cesta vegetace).", 1.0, 40.0, 0.5)
	_t(A, "LEAF_GUST_MS", "sky.leaf_gust_ms", "Vítr – listí padá naplno při nárazu", "m/s", "Náraz u kamery (WindField), padající listí a jehličí v bouřce.", 5.0, 50.0, 0.5)
	_t(A, "LEAF_STORM_FROM", "sky.leaf_storm_from", "Vítr – listí začne padat od podílu", "", "", 0.0, 1.0)
	_t(A, "LEAF_FOREST_BASE", "sky.leaf_forest_base", "Vítr – listí mimo les", "", "V lese 1.", 0.0, 1.0)
	_t(A, "WIND_SND_FOREST", "sky.wind_snd_forest", "Vítr – šum korun v lese hlasitější o", "×")


# ------------------------------------------------------------------ Vítr (WindField)

const _SURF := ["tráva", "orná půda", "sad", "les", "dvůr / zástavba", "břeh", "skála", "polní cesta"]


static func _vitr() -> void:
	var F = WindField
	_g = VIT
	_t(F, "GUST_GAIN", "wind.gust_strength", "Nárazy – síla", "×", "Náraz: u × (1 + síla · turbulence · (2g − 1)). Víc = stromy se v nárazech ohýbají víc, drak a dron víc cukají.")
	_t(F, "GUST_FREQ", "wind.gust_freq", "Nárazy – velikost chuchvalců (frekvence šumu)", "1/texel", "Menší = větší chuchvalce (0,045 ≈ 60–100 m). Textura nárazů se přegeneruje.", 0.005, 0.3, 0.001)
	_t(F, "GUST_OCTAVES", "wind.gust_octaves", "Nárazy – jemnost (oktávy šumu)", "", "", 1.0, 8.0, 1.0)
	_t(F, "GUST_FRACTAL_GAIN", "wind.gust_fractal_gain", "Nárazy – síla jemných vírů", "", "", 0.0, 1.0)
	_t(F, "GUST_MIN_MULT", "wind.gust_min_mult", "Nárazy – nejslabší okamžik", "×", "Náraz nikdy nezastaví vítr pod tento násobek.", 0.0, 1.0)
	_t(F, "GUST_ADVECT", "wind.gust_advect", "Nárazy – rychlost postupu krajinou", "× vítr", "Taylorova hypotéza: pole nárazů se posouvá střední rychlostí větru.")
	_t(F, "I_MIN", "wind.turb_min", "Turbulence – nad hladkým povrchem", "", "Intenzita turbulence (σ/u) nad loukou.", 0.0, 1.0)
	_t(F, "I_MAX", "wind.turb_max", "Turbulence – nad lesem a zástavbou", "", "", 0.0, 1.0)
	_t(F, "I_STORM", "wind.turb_storm", "Turbulence – přídavek za bouřky", "", "", 0.0, 0.5)
	_t(F, "LEE_GAIN", "wind.lee_gain", "Turbulence – v závětří hran a lesa", "×")
	_t(F, "LEE_SLOPE_K", "wind.lee_slope_k", "Turbulence – citlivost závětří na sklon", "×")
	_t(F, "Z0_REF", "wind.z0_ref", "Profil – drsnost referenční louky", "m", "K této drsnosti se vztahuje Weather.wind (10 m).", 0.001, 0.3, 0.001)
	_t(F, "REF_M", "wind.ref_m", "Profil – výška měření větru", "m", "", 1.0, 50.0, 0.5)
	_t(F, "BLEND_M", "wind.blend_m", "Profil – směšovací výška", "m", "Nad ní se drsnost povrchu „zapomene“ (log profil u(z) = u*/κ·ln(z/z0)).", 10.0, 300.0, 1.0)
	_t(F, "TOP_M", "wind.top_m", "Profil – strop mezní vrstvy", "m", "", 50.0, 1500.0, 5.0)
	_t(F, "TERRAIN_FADE_M", "wind.terrain_fade_m", "Terén – vliv slábne s výškou", "m", "Expozice a svah se ve výšce nad zemí vytrácí (e-násobně).")
	_t(F, "EXP_MIN", "wind.exp_min", "Terén – vítr v závětří", "×", "Násobek rychlosti při wind_exp = 0 (Site).", 0.0, 1.5)
	_t(F, "EXP_MAX", "wind.exp_max", "Terén – vítr na hřebeni", "×", "Násobek rychlosti při wind_exp = 1.", 0.5, 3.0)
	_t(F, "SLOPE_D", "wind.slope_d", "Terén – krok gradientu svahu", "m", "Hřbet, ne kamínek (orografický vzestup w = U·∇h).", 2.0, 100.0, 1.0)
	_t(F, "LEGACY_ALPHA", "wind.legacy_alpha", "Profil – vypnutý realismus: mocnina (h/10)^α", "", "", 0.0, 0.5)
	for c in WindField.Z0_BY_CLASS.size():
		_t(WindField.Z0_BY_CLASS, c, "wind.z0.%d" % c, "Drsnost povrchu – %s" % _SURF[c], "m", "z0 třídy povrchu (SurfaceMap): víc = pomalejší a turbulentnější vítr u země.", 0.0, 3.0, 0.005)
	_t(VegetationManager, "WIND_FULL_MS", "veg.wind_full_ms", "Ohyb vegetace – stará cesta: plný vítr", "m/s", "wind_strength materiálu = vítr / tato rychlost (bez realismu „wind“).", 1.0, 40.0, 0.5)
	_t(VegetationManager, "WIND_MAX", "veg.wind_max", "Ohyb vegetace – stará cesta: strop", "", "", 0.0, 5.0)
	var names := {VegetationManager.VegType.GRASS_TALL: "vysoká tráva", VegetationManager.VegType.NETTLE: "kopřivy",
		VegetationManager.VegType.BUSH_HAZEL: "líska", VegetationManager.VegType.BUSH_BLACKTHORN: "trnka",
		VegetationManager.VegType.CROP_WHEAT: "obilí", VegetationManager.VegType.WEED_FIELD: "plevel",
		VegetationManager.VegType.GARDEN_VEG: "zahrádky"}
	for typ in VegetationManager.VEG_CONFIG:
		var cfg: Dictionary = VegetationManager.VEG_CONFIG[typ]
		_t(cfg, "bend_k", "veg.bend_k.%d" % int(typ), "Ohyb vegetace – citlivost: %s" % String(names.get(typ, str(typ))), "×",
			"Uniform `bend_k` materiálu přízemní vegetace (keř < tráva). Projeví se do 0,2 s.", 0.0, 5.0)


# ------------------------------------------------------------------ Voda a půda (SoilWater, Water, Studanka)

const _CN_GROUPS := ["A", "B", "C", "D"]
const _SOILS := ["hnědozem", "ranker", "arenosol", "glej", "fluvizem", "antropozem"]
const _STREAMS := {"river": "řeka", "canal": "náhon", "stream": "potok", "ditch": "strouha", "drain": "meliorace"}


static func _voda() -> void:
	var S = SoilWater
	var stavba := " (stavba mřížky – po novém startu)"
	_g = VOD
	_t(S, "INTERCEPT_MM", "soil.intercept_mm", "Koruny – zachycení srážek (les, listí)", "mm", "Na srážkovou událost.")
	_t(S, "INTERCEPT_LEAFLESS", "soil.intercept_leafless", "Koruny – zachycení bez listí", "", "Podíl (jehličnany, větve).", 0.0, 1.0)
	_t(S, "DDF_MM", "soil.ddf_mm", "Sníh – tání (degree-day)", "mm/°C·den", "Sever, stín (literatura 3–5).")
	_t(S, "DDF_SOUTH_MM", "soil.ddf_south_mm", "Sníh – tání navíc na jižním svahu", "mm/°C·den")
	_t(S, "MELT_FOREST", "soil.melt_forest", "Sníh – v lese taje pomaleji", "×", "", 0.0, 1.5)
	_t(S, "RAIN_ON_SNOW", "soil.rain_on_snow", "Sníh – tání teplým deštěm", "mm/mm·°C")
	_t(S, "SNOW_DENSITY", "soil.snow_density", "Sníh – hustota", "", "Výška sněhu = vodní ekvivalent / hustota.", 0.05, 0.6)
	_t(S, "SNOW0_MM", "soil.snow0_mm", "Sníh – výchozí při pokrývce 1" + stavba, "mm v. e.")
	_t(S, "EVENT_GAP_H", "soil.event_gap_h", "Odtok – konec srážkové události po", "h", "SCS počítá po událostech.")
	_t(S, "EVENT_MIN_MM", "soil.event_min_mm", "Odtok – suchá hodina pod", "mm/h")
	_t(S, "SCS_LAMBDA", "soil.scs_lambda", "Odtok – počáteční ztráta Ia = λ·S", "", "TR-55: 0,2 (moderní kalibrace 0,05).", 0.0, 0.5)
	_t(S, "S_FROZEN_MM", "soil.s_frozen_mm", "Odtok – retence zamrzlé půdy", "mm", "Téměř vše odteče.")
	_t(S, "AMC_DRY", "soil.amc_dry", "Odtok – suchá půda (AMC I) do vlhkosti", "", "", 0.0, 1.0)
	_t(S, "AMC_MID", "soil.amc_mid", "Odtok – normální vlhkost (AMC II)", "", "", 0.0, 1.0)
	_t(S, "AMC_WET", "soil.amc_wet", "Odtok – nasycená půda (AMC III) od", "", "", 0.0, 1.0)
	_t(S, "HSG_A", "soil.hsg_a", "Odtok – skupina půdy A od propustnosti", "", "Hydrologická skupina podle propustnosti (A nejpropustnější).", 0.0, 1.0)
	_t(S, "HSG_B", "soil.hsg_b", "Odtok – skupina půdy B od propustnosti", "", "", 0.0, 1.0)
	_t(S, "HSG_C", "soil.hsg_c", "Odtok – skupina půdy C od propustnosti", "", "Níž skupina D.", 0.0, 1.0)
	_t(S, "FROST_RATE", "soil.frost_rate", "Mráz – zamrzání půdy", "/°C·h")
	_t(S, "THAW_RATE", "soil.thaw_rate", "Mráz – rozmrzání půdy", "/°C·h")
	_t(S, "SNOW_INSULATE_MM", "soil.snow_insulate_mm", "Mráz – sněhová peřina od", "mm v. e.")
	_t(S, "SNOW_INSULATE_K", "soil.snow_insulate_k", "Mráz – pod sněhem zamrzá jen", "×", "", 0.0, 1.0)
	_t(S, "HARG_C", "soil.harg_c", "Výpar – Hargreaves koeficient", "", "Často se kalibruje 0,0017–0,0030.", 0.0005, 0.006, 0.00005)
	_t(S, "HARG_T", "soil.harg_t", "Výpar – Hargreaves posun teploty", "°C", "", 0.0, 40.0, 0.1)
	_t(S, "PET_CLOUD_DAMP", "soil.pet_cloud_damp", "Výpar – oblačnost tlumí rozkmit", "×", "", 0.0, 1.0)
	_t(S, "ET_BETA_FRAC", "soil.et_beta_frac", "Výpar – stres suchem pod vlhkostí", "× AWC", "", 0.05, 1.0)
	_t(S, "ET_SNOW", "soil.et_snow", "Výpar – pod sněhem", "× PET", "", 0.0, 1.0)
	_t(S, "ET_SNOW_MM", "soil.et_snow_mm", "Výpar – „pod sněhem“ od", "mm v. e.")
	_t(S, "KC_FOREST", "soil.kc_forest", "Výpar – koeficient lesa", "")
	_t(S, "KC_ARABLE_BASE", "soil.kc_arable_base", "Výpar – orná půda mimo sezónu", "")
	_t(S, "KC_ARABLE_GREEN", "soil.kc_arable_green", "Výpar – orná půda: přídavek v sezóně", "× zeleň")
	for c in SoilWater.KC.size():
		if float(SoilWater.KC[c]) >= 0.0:
			_t(SoilWater.KC, c, "soil.kc.%d" % c, "Výpar – koeficient: %s" % _SURF[c], "", "Násobek potenciálního výparu podle povrchu.", 0.0, 2.0)
	_t(S, "INSOL_MEAN", "soil.insol_mean", "Výpar – průměrné oslunění" + stavba, "MJ/m²·rok", "", 1000.0, 9000.0, 10.0)
	_t(S, "ETF_MIN", "soil.etf_min", "Výpar – svah nejméně" + stavba, "× průměr", "", 0.0, 1.0)
	_t(S, "ETF_MAX", "soil.etf_max", "Výpar – svah nejvíc" + stavba, "× průměr", "", 1.0, 3.0)
	_t(S, "SOUTH_FROM", "soil.south_from", "Sníh – jižní svah od zimního oslunění" + stavba, "", "", 0.0, 1000.0, 5.0)
	_t(S, "SOUTH_SPAN", "soil.south_span", "Sníh – plně jižní o tolik výš" + stavba, "", "", 1.0, 1000.0, 5.0)
	_t(S, "DRAIN_FROM", "soil.drain_from", "Půda – prosakování od vlhkosti (polní kapacita)", "× AWC", "", 0.1, 1.0)
	_t(S, "K_DRAIN_H", "soil.k_drain_h", "Půda – rychlost prosakování", "1/h", "× propustnost.")
	_t(S, "GW_FRAC", "soil.gw_frac", "Půda – podíl do podzemní vody", "", "× (základ + propustnost).", 0.0, 1.0)
	_t(S, "GW_PERM_BASE", "soil.gw_perm_base", "Půda – podzemní voda: základ", "", "", 0.0, 2.0)
	_t(S, "AWC_MIN", "soil.awc_min", "Půda – nejmenší kapacita" + stavba, "mm")
	_t(S, "TWI_MED", "soil.twi_med", "Rozběh – medián TWI" + stavba, "", "", 0.0, 20.0, 0.1)
	_t(S, "TWI_K", "soil.twi_k", "Rozběh – vlhčí údolnice" + stavba, "/TWI")
	_t(S, "SPINUP_DAYS", "soil.spinup_days", "Rozběh – dní z klimatu" + stavba, "dní", "", 0.0, 365.0, 1.0)
	_t(S, "SPINUP_AWC", "soil.spinup_awc", "Rozběh – kapacita vzorové půdy" + stavba, "mm")
	_t(S, "SPINUP_KC", "soil.spinup_kc", "Rozběh – koeficient výparu" + stavba, "")
	_t(S, "SPINUP_W0", "soil.spinup_w0", "Rozběh – počáteční vlhkost" + stavba, "× AWC", "", 0.0, 1.0)
	_t(S, "SPINUP_RANGE_K", "soil.spinup_range_k", "Rozběh – denní rozkmit" + stavba, "× klima", "", 0.0, 2.0)
	_t(S, "SPINUP_FROST_P", "soil.spinup_frost_p", "Rozběh – srážky v mrazu do půdy" + stavba, "", "", 0.0, 1.0)
	_t(S, "MUD_FROM", "soil.mud_from", "Bláto – od vlhkosti", "× AWC", "Bláto = vlhkost × jílovitost × holá půda (přilnavost vozidel, chodců, koní).", 0.0, 1.0)
	_t(S, "MUD_FULL", "soil.mud_full", "Bláto – naplno při vlhkosti", "× AWC", "", 0.0, 1.0)
	_t(S, "MUD_FROST_DIM", "soil.mud_frost_dim", "Bláto – zamrzlá půda ubírá", "", "", 0.0, 1.0)
	_t(S, "BARE_FOREST", "soil.bare_forest", "Bláto – holá půda v lese", "", "", 0.0, 1.0)
	for c in SoilWater.BARE.size():
		_t(SoilWater.BARE, c, "soil.bare.%d" % c, "Bláto – holá půda: %s" % _SURF[c], "", "Podíl holé půdy / cesty (bláto) podle povrchu.", 0.0, 1.0)
	for c in SoilWater.CLAY.size():
		_t(SoilWater.CLAY, c, "soil.clay.%d" % c, "Bláto – jílovitost: %s" % _SOILS[c], "", "Lepivost bláta podle půdy.", 0.0, 1.5)
	for c in SoilWater.CN2.size():
		var row: Array = SoilWater.CN2[c]
		for gi in row.size():
			_t(row, gi, "soil.cn.%d.%d" % [c, gi], "Odtok – CN: %s, skupina %s" % [_SURF[c], _CN_GROUPS[gi]], "",
				"Curve Number (TR-55) pro AMC II – víc = víc odtoku. Přepočítá se při nejbližší hodině.", 1.0, 100.0, 1.0)
	_t(S, "PUDDLE_FROM", "soil.puddle_from", "Louže – nasycení od", "× AWC", "", 0.0, 1.0)
	_t(S, "RUNOFF_PUDDLE", "soil.runoff_puddle", "Louže – plné při odtoku", "mm/h")
	_t(S, "PUDDLE_FLAT", "soil.puddle_flat", "Louže – mimo prohlubně", "", "V prohlubni (TWI) 1.", 0.0, 1.0)
	_t(S, "PUDDLE_FROST_DIM", "soil.puddle_frost_dim", "Louže – zamrzlá půda ubírá", "", "", 0.0, 1.0)
	_t(S, "HOLLOW_FROM", "soil.hollow_from", "Louže – prohlubeň od TWI" + stavba, "", "", 0.0, 20.0, 0.1)
	_t(S, "HOLLOW_TO", "soil.hollow_to", "Louže – prohlubeň naplno od TWI" + stavba, "", "", 0.0, 25.0, 0.1)
	_t(S, "CLIMATE_DT_H", "soil.climate_dt_h", "Skok času – nad tolik hodin srážky z klimatu", "h")
	_t(S, "CLIMATE_CLOUD", "soil.climate_cloud", "Skok času – oblačnost z klimatu", "", "", 0.0, 1.0)
	for m in 12:
		_t(SoilWater.PRECIP_MM, m, "soil.precip_mm.%d" % (m + 1), "Klima – měsíční srážky: %s" % _MONTHS[m], "mm",
			"Rozběh a dlouhé skoky času.", 0.0, 250.0, 1.0)
	_t(S, "Q_SPEC", "soil.q_spec", "Toky – normál průtoku z povodí", "m³/s·m²", "4·10⁻⁹ = 4 l/s/km².", 0.0, 2.0e-8, 1.0e-10)
	_t(S, "MIN_AREA_M2", "soil.min_area_m2", "Toky – nejmenší povodí", "m²", "", 0.0, 2.0e6, 1000.0)
	for k in SoilWater.K_QUICK_H:
		_t(SoilWater.K_QUICK_H, k, "soil.k_quick_h.%s" % k, "Toky – rychlá nádrž: %s" % _STREAMS.get(k, k), "h", "Časová konstanta povrchového odtoku (lineární nádrž).", 0.5, 200.0, 0.5)
	for k in SoilWater.K_SLOW_H:
		_t(SoilWater.K_SLOW_H, k, "soil.k_slow_h.%s" % k, "Toky – podzemní nádrž: %s" % _STREAMS.get(k, k), "h", "Jak dlouho tok drží vodu v suchu.", 10.0, 6000.0, 5.0)
	for k in SoilWater.DEPTH_N:
		_t(SoilWater.DEPTH_N, k, "soil.depth_n.%s" % k, "Toky – normální hloubka: %s" % _STREAMS.get(k, k), "m", "", 0.02, 3.0, 0.01)
	for k in SoilWater.EXT_AREA_M2:
		_t(SoilWater.EXT_AREA_M2, k, "soil.ext_area_m2.%s" % k, "Toky – povodí za mapou: %s" % _STREAMS.get(k, k) + stavba, "m²", "", 0.0, 3.0e8, 1.0e5)
	_t(S, "EDGE_M", "soil.edge_m", "Toky – přítok zvenku u okraje do" + stavba, "m")
	_t(S, "JOIN_M", "soil.join_m", "Toky – soutok do vzdálenosti" + stavba, "m")
	_t(S, "RES0_LO", "soil.res0_lo", "Toky – výchozí zásoba v suchu" + stavba, "× normál")
	_t(S, "RES0_HI", "soil.res0_hi", "Toky – výchozí zásoba v mokru" + stavba, "× normál")
	_t(S, "LEVEL_MAX", "soil.level_max", "Toky – nejvyšší vzestup hladiny", "m", "Pás vody nevylézá z koryta.", 0.0, 2.0)
	_t(S, "LEVEL_EXP", "soil.level_exp", "Toky – měrná křivka (hladina ∝ Q^x)", "", "", 0.1, 1.0)
	_t(S, "DRY_REL", "soil.dry_rel", "Toky – malý potok vyschne pod", "× normál", "", 0.0, 1.0)
	_t(S, "TURB_FROM", "soil.turb_from", "Toky – kalení od průtoku", "× normál")
	_t(S, "TURB_FULL", "soil.turb_full", "Toky – plně kalná voda při", "× normál")
	_t(S, "TURB_TAU_H", "soil.turb_tau_h", "Toky – čištění vody", "h")
	_t(S, "DROUGHT_MOIST_REF", "soil.drought_moist_ref", "Sucho – vlhkost půdy, pod kterou roste", "", "Index sucha → Weather.drought (vyhláška sucha).", 0.0, 1.0)
	_t(S, "DROUGHT_MOIST_SPAN", "soil.drought_moist_span", "Sucho – plné o tolik níž", "", "", 0.01, 1.0)
	_t(S, "DROUGHT_FLOW_REF", "soil.drought_flow_ref", "Sucho – průtok, pod kterým roste", "× normál", "", 0.0, 2.0)
	_t(S, "DROUGHT_FLOW_SPAN", "soil.drought_flow_span", "Sucho – průtok: plné o tolik níž", "× normál", "", 0.01, 2.0)
	_t(S, "DROUGHT_MOIST_W", "soil.drought_moist_w", "Sucho – váha vlhkosti půdy", "", "Zbytek váhy mají průtoky.", 0.0, 1.0)
	# --- Water (hladiny, led, vlnky)
	var Wt = Water
	_t(Wt, "POND_FREEZE_C", "water.pond_freeze_c", "Led – rybník zamrzá pod −", "°C", "Teplota u vody (Microclimate.temp_valley).", -5.0, 10.0, 0.1)
	_t(Wt, "POND_FREEZE_SPAN", "water.pond_freeze_span", "Led – rybník úplně zamrzlý o tolik níž", "°C", "", 0.1, 20.0, 0.1)
	_t(Wt, "STREAM_FREEZE_C", "water.stream_freeze_c", "Led – potok zamrzá pod −", "°C", "", -5.0, 20.0, 0.1)
	_t(Wt, "STREAM_FREEZE_SPAN", "water.stream_freeze_span", "Led – potok úplně zamrzlý o tolik níž", "°C", "", 0.1, 20.0, 0.1)
	_t(Wt, "ICE_RATE_H", "water.ice_rate_h", "Led – rychlost zamrzání rybníka", "/h")
	_t(Wt, "ICE_FLOW_RATE_H", "water.ice_flow_rate_h", "Led – rychlost zamrzání potoka", "/h")
	_t(Wt, "WAVES_RAIN", "water.waves_rain", "Hladina – vlnky v dešti", "×")
	_t(Wt, "WAVES_WIND", "water.waves_wind", "Hladina – vlnky ve větru", "×")
	_t(Wt, "WAVES_WIND_FULL", "water.waves_wind_full", "Hladina – plný vítr pro vlnky", "m/s")
	_t(Wt, "STREAM_NEAR_M", "water.stream_near_m", "Toky – dotaz průtoku / hladiny do", "m")
	_t(Wt, "STREAM_VIS_S", "water.stream_vis_s", "Hladina – obnova vzhledu toků", "s", "", 0.1, 10.0, 0.1)
	_t(Wt, "STREAM_VIS_RATE", "water.stream_vis_rate", "Hladina – posun hladiny za obnovu", "m")
	_t(Wt, "TURB_VIS_RATE", "water.turb_vis_rate", "Hladina – přechod kalnosti za obnovu", "", "", 0.0, 1.0)
	_t(Wt, "FLOW_VIS_RATE", "water.flow_vis_rate", "Hladina – přechod rychlosti proudu za obnovu", "", "", 0.0, 1.0)
	for k in Water.FLOW_NOMINAL:
		_t(Water.FLOW_NOMINAL, k, "water.flow_nominal.%s" % k, "Toky – normální průtok bez bilance: %s" % _STREAMS.get(k, k), "m³/s", "Jen s vypnutým realismem vodní bilance.", 0.0, 10.0, 0.001)
	# --- studánka a tábor
	_t(Studanka, "FREEZE_TEMP", "spring.freeze_temp", "Studánka – zamrzá pod", "°C", "", -15.0, 5.0, 0.5)
	_t(Studanka, "SPRING_R", "spring.reach_m", "Studánka – dosah E", "m")
	_t(Studanka, "CHECK_S", "spring.check_s", "Studánka – kontrola tábora", "s", "", 0.2, 30.0, 0.1)
	_t(Studanka, "CAMP_EVENT_R", "spring.camp_r", "Tábor – stany a oheň zobrazit do", "m")
	_t(Studanka, "CAMP_MONTH", "spring.camp_month", "Tábor – měsíc", "", "", 1.0, 12.0, 1.0)
	_t(Studanka, "CAMP_LAST_DAY", "spring.camp_last_day", "Tábor – poslední den v měsíci", "", "", 1.0, 31.0, 1.0)


# ------------------------------------------------------------------ Mikroklima (Microclimate, MicroFx)

static func _mikroklima() -> void:
	var M = Microclimate
	var cache := " Mezipaměť míst se po změně zahodí."
	_g = MIK
	_t(M, "LAPSE_K_M", "micro.lapse_k_m", "Teplota – vertikální gradient", "K/m", "Standardní atmosféra −6,5 K/km.", 0.0, 0.02, 0.0001)
	_t(M, "INV_MAX_K", "micro.inversion_max_c", "Inverze – nejsilnější", "K", "Dno kotliny vs. střední výška za jasné bezvětrné noci.", 0.0, 20.0, 0.1)
	_t(M, "INV_RATE_K_H", "micro.inv_rate_k_h", "Inverze – nárůst za noc", "K/h")
	_t(M, "INV_MIX_H", "micro.inv_mix_h", "Inverze – rozmíchání větrem / mraky", "h")
	_t(M, "INV_BREAK_H", "micro.inv_break_h", "Inverze – rozpouštění sluncem", "h")
	_t(M, "INV_DEPTH_M", "micro.inv_depth_m", "Inverze – mocnost jezera studeného vzduchu", "m", "Výška nad dnem údolí (HAND).")
	_t(M, "W_LOW", "micro.w_low", "Inverze – podíl u dna údolí", "", "", 0.0, 1.0)
	_t(M, "W_POOL", "micro.w_pool", "Inverze – podíl v mrazové kotlině", "", "", 0.0, 1.0)
	_t(M, "BELT_K", "micro.belt_k", "Inverze – teplý svahový pás na hřbetu", "× I", "", 0.0, 1.0)
	_t(M, "TPI_RIDGE_M", "micro.tpi_ridge_m", "Inverze – hřbet od TPI", "m", cache)
	_t(M, "CALM_FROM_MS", "micro.calm_from_ms", "Inverze – plné vyzařování do větru", "m/s")
	_t(M, "CALM_TO_MS", "micro.calm_to_ms", "Inverze – vítr promíchá od", "m/s")
	_t(M, "CLEAR_FROM", "micro.clear_from", "Inverze – mraky tlumí vyzařování od", "", "", 0.0, 1.0)
	_t(M, "CLEAR_TO", "micro.clear_to", "Inverze – při oblačnosti nevzniká", "", "", 0.0, 1.0)
	_t(M, "INV_BUILD_ELEV_FROM", "micro.inv_build_elev_from", "Inverze – roste pod výškou slunce", "°", "", -18.0, 30.0, 0.5)
	_t(M, "INV_BUILD_ELEV_TO", "micro.inv_build_elev_to", "Inverze – přestává růst nad výškou slunce", "°", "", -18.0, 45.0, 0.5)
	_t(M, "INV_BREAK_ELEV_FROM", "micro.inv_break_elev_from", "Inverze – slunce rozpouští od výšky", "°", "", -10.0, 60.0, 0.5)
	_t(M, "INV_BREAK_ELEV_TO", "micro.inv_break_elev_to", "Inverze – slunce rozpouští naplno od", "°", "", 0.0, 90.0, 0.5)
	_t(M, "INV_BREAK_BASE", "micro.inv_break_base", "Inverze – rozpouštění i pod mraky", "", "Za jasna 1.", 0.0, 1.0)
	_t(M, "INV_FOREST_DAMP", "micro.inv_forest_damp", "Inverze – les tlumí", "", "", 0.0, 1.0)
	_t(M, "INV_URBAN_DAMP", "micro.inv_urban_damp", "Inverze – zástavba tlumí", "", "", 0.0, 1.0)
	_t(M, "POOL_DEPTH_M", "micro.pool_depth_m", "Inverze – profil údolí: kotlina do výšky", "m")
	_t(M, "POOL_K", "micro.pool_k", "Inverze – profil údolí: síla kotliny", "", "", 0.0, 1.0)
	_t(M, "RAIN_DRY_K", "micro.rain_dry_k", "Inverze – déšť ruší radiační noc", "×")
	_t(M, "NIGHT_ELEV_TO", "micro.night_elev_to", "Inverze – radiační noc slábne do výšky slunce", "°", "", 0.0, 45.0, 0.5)
	_t(M, "SUN_FULL_ELEV", "micro.sun_full_elev", "Slunce – ohřev naplno od výšky", "°", "", 1.0, 90.0, 0.5)
	_t(M, "SUN_CLOUD_K", "micro.sun_cloud_k", "Slunce – oblačnost ubírá ohřev", "", "", 0.0, 1.0)
	_t(M, "SOUTH_K", "micro.south_k", "Slunce – přehřátí jižního svahu", "K")
	_t(M, "INSOL_MEAN", "micro.insol_mean", "Slunce – průměrné oslunění katastru", "MJ/m²·rok", cache, 1000.0, 9000.0, 10.0)
	_t(M, "INSOL_SPAN", "micro.insol_span", "Slunce – rozdíl oslunění pro plné přehřátí", "MJ/m²·rok", cache, 50.0, 4000.0, 10.0)
	_t(M, "FOREST_DAY_K", "micro.forest_day_k", "Les – ve dne chladněji o", "K")
	_t(M, "FOREST_NIGHT_K", "micro.forest_night_k", "Les – za jasné noci tepleji o", "K")
	_t(M, "FOREST_CLASS_CANOPY", "micro.forest_class_canopy", "Les – třída „les“ = zápoj aspoň", "", cache, 0.0, 1.0)
	_t(M, "URBAN_DAY_K", "micro.urban_day_k", "Obec – tepelný ostrov ve dne", "K")
	_t(M, "URBAN_NIGHT_K", "micro.urban_night_k", "Obec – tepelný ostrov v noci", "K")
	_t(M, "URBAN_R_M", "micro.urban_r_m", "Obec – poloměr vzorku zástavby", "m", cache)
	_t(M, "WATER_NEAR_M", "micro.water_near_m", "Voda – zjemňuje výkyvy do vzdálenosti", "m", cache)
	_t(M, "WATER_DAMP", "micro.water_damp", "Voda – tlumí inverzi a přehřátí", "", "", 0.0, 1.0)
	_t(M, "GROUND_K", "micro.ground_k", "Přízemí – za jasné noci chladněji o", "K", "Tráva vs. 2 m.")
	_t(M, "GROUND_FOREST_DAMP", "micro.ground_forest_damp", "Přízemí – les tlumí ochlazení", "", "", 0.0, 1.0)
	_t(M, "CLOUD_RANGE_DAMP", "micro.cloud_range_damp", "Rosný bod – oblačnost tlumí rozkmit", "", "", 0.0, 1.0)
	_t(M, "DEP_K", "micro.dep_k", "Rosný bod – deficit v suchém vzduchu", "K")
	_t(M, "TD_OFFSET_K", "micro.td_offset_k", "Rosný bod – posun dolů", "K")
	_t(M, "MOIST_BASE", "micro.moist_base", "Rosný bod – vlhkost vzduchu: základ", "", "", 0.0, 1.0)
	_t(M, "MOIST_CLOUD", "micro.moist_cloud", "Rosný bod – vlhkost: × oblačnost", "")
	_t(M, "MOIST_RAIN", "micro.moist_rain", "Rosný bod – vlhkost: × déšť", "")
	_t(M, "MOIST_FOG", "micro.moist_fog", "Rosný bod – vlhkost: × mlha", "")
	_t(M, "MOIST_RECENT", "micro.moist_recent", "Rosný bod – vlhkost: × déšť posledních dní", "")
	_t(M, "MOIST_DROUGHT", "micro.moist_drought", "Rosný bod – vlhkost: − × sucho", "")
	_t(M, "TD_TAU_H", "micro.td_tau_h", "Rosný bod – změna vzduchové hmoty", "h")
	_t(M, "TMEAN_TAU_H", "micro.tmean_tau_h", "Teplota – klouzavý denní průměr", "h")
	_t(M, "TD_WATER_K", "micro.td_water_k", "Rosný bod – u vody výš o", "K")
	_t(M, "TD_FOREST_K", "micro.td_forest_k", "Rosný bod – v lese výš o", "K")
	_t(M, "TD_SOIL_K", "micro.td_soil_k", "Rosný bod – nad mokrou půdou", "K")
	_t(M, "FOG_MARGIN_K", "micro.fog_margin_k", "Mlha – vzniká do T ≤ Td +", "K")
	_t(M, "FOG_DENS_SPAN_K", "micro.fog_dens_span_k", "Mlha – plná hustota o tolik pod rosným bodem", "K", "", 0.1, 10.0)
	_t(M, "FOG_TAU_UP_H", "micro.fog_tau_up_h", "Mlha – vrstva roste", "h")
	_t(M, "FOG_TAU_DOWN_H", "micro.fog_tau_down_h", "Mlha – vrstva se rozpouští", "h")
	_t(M, "FOG_EDGE_M", "micro.fog_edge_m", "Mlha – měkký horní okraj", "m")
	_t(M, "FOG_SCAN_M", "micro.fog_scan_m", "Mlha – krok profilu údolí", "m", "Profil má 40 kroků (do 200 m při 5 m).", 1.0, 20.0, 0.5)
	_t(M, "DEW_RATE_H", "micro.dew_rate_h", "Rosa – přírůstek", "/h")
	_t(M, "DEW_SPAN_K", "micro.dew_span_k", "Rosa – plnou rychlostí o tolik pod Td", "K", "", 0.1, 10.0)
	_t(M, "DEW_RAIN_MIN", "micro.dew_rain_min", "Rosa – žádná při dešti nad", "", "", 0.0, 1.0)
	_t(M, "DEW_DRY_H", "micro.dew_dry_h", "Rosa – vysychání", "/h")
	_t(M, "DEW_DRY_BASE", "micro.dew_dry_base", "Rosa – vysychání: základ", "")
	_t(M, "DEW_DRY_SUN", "micro.dew_dry_sun", "Rosa – vysychání: × slunce²", "")
	_t(M, "DEW_DRY_WIND", "micro.dew_dry_wind", "Rosa – vysychání: × vítr", "/m/s")
	_t(M, "DEW_UPLAND", "micro.dew_upland", "Rosa – mimo údolí", "", "U dna 1.", 0.0, 1.0)
	_t(M, "DEW_FOREST_DAMP", "micro.dew_forest_damp", "Rosa – les ubírá", "", "", 0.0, 1.0)
	_t(M, "DEW_URBAN_DAMP", "micro.dew_urban_damp", "Rosa – zástavba ubírá", "", "", 0.0, 1.0)
	_t(M, "FROST_TAU_UP_H", "micro.frost_tau_up_h", "Mráz – hranice stoupá", "h")
	_t(M, "FROST_TAU_DOWN_H", "micro.frost_tau_down_h", "Mráz – hranice ráno klesá", "h")
	_t(M, "FROST_FROM_C", "micro.frost_from_c", "Mráz – přízemní mráz od teploty trávy", "°C", "", -5.0, 5.0, 0.1)
	_t(M, "FROST_FULL_C", "micro.frost_full_c", "Mráz – plný při teplotě trávy", "°C", "", -10.0, 3.0, 0.1)
	_t(M, "SNOW_BAND_K", "micro.snow_band_k", "Sněžení – přechod déšť / sníh ±", "K", "Kolem Weather.SNOW_BELOW podle teploty v místě.", 0.0, 5.0)
	_t(M, "SNAP_HOURS", "micro.snap_hours", "Rozběh – hodin po skoku času", "h", "", 1.0, 72.0, 1.0)
	var X = MicroFx
	_t(X, "FOG_H_DENS", "micro.fx_fog_h_dens", "Údolní mlha – hustota výškové mlhy", "1/m", "", 0.0, 0.5, 0.001)
	_t(X, "FOG_IN_DENS", "micro.fx_fog_in_dens", "Údolní mlha – hustota uvnitř vrstvy", "1/m", "Dohled ~200 m při 0,01.", 0.0, 0.1, 0.0005)
	_t(X, "INSIDE_BAND_M", "micro.fx_inside_band_m", "Údolní mlha – „uvnitř“ pod hranicí od", "m")
	_t(X, "ABOVE_BAND_M", "micro.fx_above_band_m", "Údolní mlha – přechod nad hranicí", "m")
	_t(X, "FLOOR_RATE", "micro.fx_floor_rate", "Údolní mlha – posun dna údolí pod kamerou", "m/s")
	_t(X, "FLOOR_SNAP_M", "micro.fx_floor_snap_m", "Údolní mlha – skok dna při rozdílu nad", "m")
	_t(X, "MIN_TOP_M", "micro.fx_min_top_m", "Údolní mlha – tenčí vrstva se nekreslí", "m")


# ------------------------------------------------------------------ Dřeviny a les (TreeEco, PlantedTrees)

static func _dreviny() -> void:
	var E = TreeEco
	var P = PlantedTrees
	_g = LES
	_t(E, "FALLBACK_VIGOR", "tree.fallback_vigor", "Dřeviny – vitalita bez dat", "", "Bez tree_eco.bin a bez stanoviště.", 0.0, 1.0)
	_t(E, "SAPLING_CLOSURE", "tree.sapling_closure", "Sazenice – zápoj místa výsadby", "", "Pro světelnou nároky (Ellenberg L).", 0.0, 1.0)
	_t(E, "HEIGHT_VIG_BASE", "tree.height_vig_base", "Růst – výška stromu při nulové vitalitě", "× H_max", "Stanovištní H = H_max × (základ + (1 − základ) × vitalita).", 0.0, 1.0)
	_t(E, "SOLITARY_DBH_K", "tree.solitary_dbh_k", "Růst – solitér má tlustší kmen", "×", "", 0.5, 3.0)
	_t(E, "SOIL_DEPTH_FULL_CM", "tree.soil_depth_full_cm", "Sazenice – plná vitalita od hloubky půdy", "cm")
	_t(E, "SOIL_DEPTH_MIN_F", "tree.soil_depth_min_f", "Sazenice – na mělké půdě nejméně", "×", "", 0.0, 1.0)
	_t(P, "GROWTH_SPEEDUP", "tree.growth_speedup", "Sazenice – zrychlení růstu", "×", "Herní roky jsou dlouhé – 6× rychleji než realita.", 0.1, 50.0, 0.1)
	_t(P, "START_SCALE", "tree.start_scale", "Sazenice – velikost čerstvé sazenice", "× dospělý", "", 0.01, 1.0)
	_t(P, "ESTABLISH_DAYS", "tree.establish_days", "Sazenice – ujmutí po", "dní", "Do té doby potřebuje vláhu.", 0.0, 365.0, 1.0)
	_t(P, "WATER_DAYS", "tree.water_days", "Sazenice – vláha po zalití", "dní")
	_t(P, "RAIN_DAYS", "tree.rain_days", "Sazenice – vláha po dešti", "dní")
	_t(P, "DRY_DAMAGE", "tree.dry_damage", "Sazenice – ztráta zdraví za suchý den", "", "", 0.0, 1.0)
	_t(P, "HEAL_WET", "tree.heal_wet", "Sazenice – zotavení za den s vláhou", "", "", 0.0, 1.0)
	_t(P, "HEAL_SLOW", "tree.heal_slow", "Sazenice – zotavení ujatého stromu", "", "", 0.0, 1.0)
	_t(P, "DRY_GROWTH", "tree.dry_growth", "Sazenice – růst v suchu", "×", "", 0.0, 1.0)
	_t(P, "HEALTH_GROWTH_MIN", "tree.health_growth_min", "Sazenice – růst při nulovém zdraví", "×", "", 0.0, 1.0)
	_t(P, "SKIP_RAIN_BASE", "tree.skip_rain_base", "Sazenice – šance deště za přeskočený den", "", "Spánek, skok času: základ + K × vlhko posledních dní.", 0.0, 1.0)
	_t(P, "SKIP_RAIN_K", "tree.skip_rain_k", "Sazenice – šance deště: × vlhko", "", "", 0.0, 1.0)
	_t(P, "BROWSE_R", "tree.browse_r", "Okus – srnec do vzdálenosti", "m")
	_t(P, "BROWSE_P", "tree.browse_p", "Okus – šance za den", "", "", 0.0, 1.0)
	_t(P, "BROWSE_DAMAGE", "tree.browse_damage", "Okus – ztráta zdraví", "", "", 0.0, 1.0)
	_t(P, "BROWSE_MAX_S", "tree.browse_max_s", "Okus – jen sazenice menší než", "× dospělý", "", 0.0, 1.0)
	_t(P, "GUARD_OUTGROWN", "tree.guard_outgrown", "Ochranný obal – chrání do velikosti", "× dospělý", "", 0.0, 1.0)
	_t(P, "COLLIDE_MIN_H", "tree.collide_min_h", "Sazenice – pevný kmen od výšky", "m")
	_t(P, "FRUIT_MIN_S", "tree.fruit_min_s", "Ovoce – plodí od velikosti", "× dospělý", "", 0.0, 1.0)
	_t(P, "FRUIT_CAP", "tree.fruit_cap", "Ovoce – plodů na dospělém stromě", "ks", "", 0.0, 50.0, 1.0)
	_t(P, "MIN_TREE_DIST", "tree.min_tree_dist", "Výsadba – od jiného stromu aspoň", "m")
	_t(P, "MIN_BUILDING_DIST", "tree.min_building_dist", "Výsadba – od zdi aspoň", "m")
	_t(P, "MIN_ROAD_DIST", "tree.min_road_dist", "Výsadba – od silnice aspoň", "m")
	_t(PlantedTrees.VIGOR_GROWTH, 0, "tree.vigor_growth_min", "Sazenice – růst na nevhodném stanovišti", "×", "Růst × lerp(min, max, vitalita stanoviště).", 0.0, 2.0)
	_t(PlantedTrees.VIGOR_GROWTH, 1, "tree.vigor_growth_max", "Sazenice – růst na ideálním stanovišti", "×", "", 0.0, 3.0)
	for sp in PlantedTrees.SPECIES_ORDER:
		var spec: Dictionary = PlantedTrees.SPECIES[sp]
		var nm: String = spec["name"]
		_t(spec, "years", "tree.species.%s.years" % sp, "Sazenice %s – roky do dospělosti" % nm, "let", "Před zrychlením růstu.", 0.5, 40.0, 0.5)
		_t(spec, "h", "tree.species.%s.h" % sp, "Sazenice %s – výška dospělého" % nm, "m", "", 1.0, 40.0, 0.5)


# ------------------------------------------------------------------ Pole a louky (Fields, MeadowFlowers, Garden)

static func _pole() -> void:
	_g = POL
	for k in Fields.CROPS:
		var c: Dictionary = Fields.CROPS[k]
		_t(c, "weight", "field.crop.%s.weight" % k, "Osevní postup – váha: %s" % String(c["name"]), "",
			"Relativní podíl polí s touto plodinou (plodina pole je dána číslem pole a rokem).", 0.0, 1.0, 0.01)
	_t(Fields, "DATE_SPREAD", "field.date_spread", "Pole – posun termínů mezi poli", "± dní", "Žně, setí a orba se u každého pole posunou.", 0.0, 30.0, 1.0)
	_t(Fields, "SOW_FROM_DOY", "field.sow_from_doy", "Pole – ozimy se zelenají od", "den", "", 200.0, 366.0, 1.0)
	_t(Fields, "SOW_TO_DOY", "field.sow_to_doy", "Pole – ozimy zelené naplno", "den", "", 200.0, 366.0, 1.0)
	_t(MeadowFlowers.DENSITY, 2, "meadow.density_meadow", "Květy – hustota na loukách", "", "Podíl buněk 1,7 m s květem při plném kvetení.", 0.0, 1.0)
	_t(MeadowFlowers.DENSITY, 3, "meadow.density_orchard", "Květy – hustota v sadech", "", "", 0.0, 1.0)
	_t(MeadowFlowers.DENSITY, 4, "meadow.density_garden", "Květy – hustota v zahrádkách", "", "", 0.0, 1.0)
	_t(MeadowFlowers, "SETTLE_MAX", "meadow.settle_max", "Květy – ne v husté zástavbě nad", "", "", 0.0, 1.0)
	_t(MeadowFlowers, "ROAD_HALF", "meadow.road_half", "Květy – pás bez květů kolem cest", "m")
	_t(MeadowFlowers, "BLOOM_MIN", "meadow.bloom_min", "Květy – žádné při kvetení pod", "", "", 0.0, 1.0)
	var G = Garden
	_t(G, "MOIST_WATER", "garden.moist_water", "Zahrada – vláha po zalití", "dní")
	_t(G, "MOIST_RAIN", "garden.moist_rain", "Zahrada – vláha po dešti", "dní")
	_t(G, "DRY_GROWTH", "garden.dry_growth", "Zahrada – růst v suchu", "×", "", 0.0, 1.0)
	_t(G, "WEED_WET", "garden.weed_wet", "Zahrada – plevel za den (vlhko)", "")
	_t(G, "WEED_DRY", "garden.weed_dry", "Zahrada – plevel za den (sucho)", "")
	_t(G, "WEED_GROWTH_K", "garden.weed_growth_k", "Zahrada – plevel ubere růstu", "", "Při 100 % plevele.", 0.0, 1.0)
	_t(G, "WILT_DAMAGE", "garden.wilt_damage", "Zahrada – vadnutí: ztráta zdraví za den", "", "", 0.0, 1.0)
	_t(G, "HEAL_WET", "garden.heal_wet", "Zahrada – zotavení za den s vláhou", "", "", 0.0, 1.0)
	_t(G, "OVER_PENALTY", "garden.over_penalty", "Zahrada – přezrálá úroda: ztráta za den", "")
	_t(G, "OVER_MAX", "garden.over_max", "Zahrada – přezrálá úroda: ztráta nejvýš", "", "", 0.0, 1.0)
	_t(G, "COLD_GROWTH", "garden.cold_growth", "Zahrada – růst zimních plodin v chladu", "", "", 0.0, 1.0)
	_t(G, "COLD_BELOW_C", "garden.cold_below_c", "Zahrada – chlad pod", "°C", "Pod touto teplotou rostou jen zimní plodiny (česnek).", -5.0, 15.0, 0.5)
	_t(G, "GROW_BASE_C", "garden.grow_base_c", "Zahrada – růst: základní teplota", "°C", "Růst = (t − základ) / rozpětí.", -5.0, 15.0, 0.5)
	_t(G, "GROW_SPAN_C", "garden.grow_span_c", "Zahrada – růst: rozpětí do plného", "°C", "", 1.0, 40.0, 0.5)
	_t(G, "GROW_MIN_F", "garden.grow_min_f", "Zahrada – růst nejméně (nad chladem)", "", "", 0.0, 1.0)
	_t(G, "NIGHT_DROP", "garden.night_drop", "Zahrada – ranní minimum níž o", "°C")
	_t(G, "DAY_WARM", "garden.day_warm", "Zahrada – průměr dne výš než noc o", "°C")
	_t(G, "RAIN_SKIP_BASE", "garden.rain_skip_base", "Zahrada – šance deště za přeskočený den", "", "", 0.0, 1.0)
	_t(G, "RAIN_SKIP_K", "garden.rain_skip_k", "Zahrada – šance deště: × vlhko", "", "", 0.0, 1.0)
	_t(G, "GH_BONUS", "garden.gh_bonus", "Skleník – tepleji o", "°C")
	_t(G, "FERT_K", "garden.fert_k", "Hnojení – zrychlení růstu", "", "Při plném pohnojení.", 0.0, 2.0)
	_t(G, "FERT_DECAY", "garden.fert_decay", "Hnojení – úbytek za den", "", "", 0.0, 1.0)
	for k in Garden.CROP_ORDER:
		var c: Dictionary = Garden.CROPS[k]
		var nm: String = c["name"]
		_t(c, "days", "garden.crop.%s.days" % k, "Plodina %s – dní do zralosti" % nm, "dní", "Růstové dny při plném růstu.", 5.0, 400.0, 1.0)
		_t(c, "water_need", "garden.crop.%s.water_need" % k, "Plodina %s – snese dní bez vláhy" % nm, "dní", "", 0.0, 30.0, 1.0)
		_t(c, "frost_kill", "garden.crop.%s.frost_kill" % k, "Plodina %s – zmrzne pod" % nm, "°C", "", -30.0, 10.0, 0.5)
		_t(c, "min_temp", "garden.crop.%s.min_temp" % k, "Plodina %s – neroste pod" % nm, "°C", "", -20.0, 20.0, 0.5)


# ------------------------------------------------------------------ Louže, stopy (Puddles, Tracks)

static func _louze() -> void:
	var P = Puddles
	_g = LOU
	_t(P, "WET_MIN", "puddle.wet_min", "Louže – objeví se od mokra", "", "Bez vodní bilance (globální Weather.wetness).", 0.0, 1.0)
	_t(P, "WET_FULL", "puddle.wet_full", "Louže – naplno při mokru", "", "", 0.0, 1.0)
	_t(P, "LOCAL_MIN", "puddle.local_min", "Louže – lokální vláha nejméně", "", "S vodní bilancí: sušší místo louži nedostane.", 0.0, 1.0)
	_t(P, "RAIN_FLAT", "puddle.rain_flat", "Louže – za deště mimo prohlubně", "", "V prohlubni 1.", 0.0, 1.0)
	_t(P, "FADE_STEP", "puddle.fade_step", "Louže – objevení / zmizení (globálně) za tick", "", "Tick ~0,5 s.", 0.0, 1.0)
	_t(P, "LOCAL_FADE", "puddle.local_fade", "Louže – vysychání (lokálně) za tick", "", "", 0.0, 1.0)
	_t(P, "RADIUS", "puddle.radius", "Louže – hledání vozovky do", "m")
	_t(P, "SPACING", "puddle.spacing", "Louže – rozestup aspoň", "m")
	_t(P, "RESP_DIST", "puddle.resp_dist", "Louže – přerozdělit po posunu o", "m")
	_t(P, "RESCATTER_TICKS", "puddle.rescatter_ticks", "Louže – doplnit na místě po", "ticků", "", 1.0, 200.0, 1.0)
	var T = Tracks
	_t(T, "SNOW_MIN", "tracks.snow_min", "Stopy – zapisují se od sněhu", "", "Čte i zvěř a kůň.", 0.0, 1.0)
	_t(T, "SNOW_HIDE", "tracks.snow_hide", "Stopy – zmizí pod sněhem", "", "Sníh roztál.", 0.0, 1.0)
	_t(T, "FADE_S", "tracks.fade_s", "Stopy – blednutí na konci života", "s")
	var tn := {"boot": "člověk", "hoof": "kůň", "deer": "srnec", "boar": "divočák", "hare": "zajíc"}
	for k in Tracks.KINDS:
		_t(Tracks.KINDS[k], "life", "tracks.%s.life" % k, "Stopy – životnost: %s" % String(tn.get(k, k)), "s", "Reálné sekundy, než stopa zavane.", 5.0, 3600.0, 5.0)


# ------------------------------------------------------------------ Kouř a ostatní (ChimneySmoke, VillageEvents)

static func _kour() -> void:
	var R: Dictionary = ChimneySmoke.SmokeRules
	_g = KOU
	var pc: Array = R["p_curve"]
	for i in pc.size():
		var pt: Array = pc[i]
		_t(pt, 0, "smoke.p_curve.%d.temp" % i, "Kouř – topení, bod %d: teplota" % (i + 1), "°C",
			"Křivka [teplota → pravděpodobnost, že dům topí], řazená od nejteplejší.", -30.0, 30.0, 0.5)
		_t(pt, 1, "smoke.p_curve.%d.p" % i, "Kouř – topení, bod %d: pravděpodobnost" % (i + 1), "", "", 0.0, 1.0)
	var tn := {"morning": "ráno", "evening": "večer", "night": "noc"}
	for k in ["morning", "evening", "night"]:
		var a: Array = R[k]
		var nm: String = tn[k]
		_t(a, 0, "smoke.%s.from" % k, "Kouř – %s od" % nm, "h", "", 0.0, 24.0, 0.5)
		_t(a, 1, "smoke.%s.to" % k, "Kouř – %s do" % nm, "h", "", 0.0, 24.0, 0.5)
		_t(a, 2, "smoke.%s.mult" % k, "Kouř – %s násobek topení" % nm, "×", "", 0.0, 3.0)
	_t(R, "gale", "smoke.gale", "Kouř – vichr trhá kouř od", "m/s")
	_t(R, "fog_inversion", "smoke.fog_inversion", "Kouř – mlha = inverze od", "", "", 0.0, 1.0)
	_t(R, "frost_calm_temp", "smoke.frost_calm_temp", "Kouř – ranní inverze pod teplotou", "°C", "", -15.0, 10.0, 0.5)
	_t(R, "frost_calm_wind", "smoke.frost_calm_wind", "Kouř – ranní inverze do větru", "m/s")
	_t(R, "life", "smoke.life", "Kouř – životnost částice", "s")
	_t(R, "inversion_k", "smoke.inversion_k", "Kouř – drží se nízko od síly inverze", "K", "Microclimate.inversion().", 0.0, 10.0)
	var C = ChimneySmoke
	_t(C, "BUOYANCY", "smoke.buoyancy", "Kouř – vztlak", "m/s²")
	_t(C, "BUOY_WIND_DAMP", "smoke.buoy_wind_damp", "Kouř – vztlak ve vichru ubude", "", "", 0.0, 1.0)
	_t(C, "WIND_DRIFT", "smoke.wind_drift", "Kouř – unášení větrem", "× vítr")
	_t(C, "INV_WIND_DRIFT", "smoke.inv_wind_drift", "Kouř – unášení při inverzi", "× vítr")
	_t(C, "INV_FROM_H", "smoke.inv_from_h", "Kouř – ranní inverze od", "h", "", 0.0, 24.0, 0.5)
	_t(C, "INV_TO_H", "smoke.inv_to_h", "Kouř – ranní inverze do", "h", "", 0.0, 24.0, 0.5)
	_t(C, "INV_LIFE_K", "smoke.inv_life_k", "Kouř – při inverzi vydrží déle", "×")
	_t(C, "RAIN_LIFE_K", "smoke.rain_life_k", "Kouř – déšť zkracuje život", "", "", 0.0, 1.0)
	_t(C, "WIND_LIFE_K", "smoke.wind_life_k", "Kouř – vichr zkracuje život", "", "", 0.0, 1.0)
	var V = VillageEvents
	_t(V, "NEAR_R", "events.near_r", "Události – dekorace a postavy do", "m")
	_t(V, "BONFIRE_LIT_HOUR", "events.bonfire_lit_hour", "Čarodějnice – hranice hoří od", "h", "", 0.0, 24.0, 0.25)
	_t(V, "BONFIRE_CROWD", "events.bonfire_crowd", "Čarodějnice – lidí u ohně", "", "", 0.0, 40.0, 1.0)
	_t(V, "MASOPUST_N", "events.masopust_n", "Masopust – masek v průvodu", "", "", 0.0, 30.0, 1.0)
	_t(V, "MASOPUST_SPEED", "events.masopust_speed", "Masopust – rychlost průvodu", "m/s")
	_t(V, "MASOPUST_SPACING", "events.masopust_spacing", "Masopust – rozestup masek", "m")
	_t(V, "MASOPUST_OFFSET", "events.masopust_offset", "Masopust – od osy silnice", "m")
	_t(V, "ZABAVA_VISITORS", "events.zabava_visitors", "Zábava – návštěvníků", "", "", 0.0, 50.0, 1.0)
	_t(V, "ZABAVA_PLAY_S", "events.zabava_play_s", "Zábava – kapela hraje", "s", "Reálné sekundy.")
	_t(V, "ZABAVA_PAUSE_S", "events.zabava_pause_s", "Zábava – pauza mezi sety", "s", "Reálné sekundy.")
	for k in VillageEvents.EVENTS:
		var e: Dictionary = VillageEvents.EVENTS[k]
		var hr: Array = e["hours"]
		_t(hr, 0, "events.%s.from_h" % k, "Události – %s od" % String(e["name"]), "h", "Hodina dne (nad 24 = po půlnoci).", 0.0, 30.0, 0.25)
		_t(hr, 1, "events.%s.to_h" % k, "Události – %s do" % String(e["name"]), "h", "", 0.0, 30.0, 0.25)
