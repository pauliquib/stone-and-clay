## M8.18 Zvuková krajina a drobný život: menu pro vývojáře (F3) – skupiny **Příroda/Zvuková krajina** (výběr zdrojů,
## pool hlasů, aktivita, Dolbearův zákon, útlum vegetací, ozvěna, šumění korun, deník, práce u domů – sekačka, hrábě,
## lopata), **Příroda/Zvuková krajina – druhy** (celá tabulka `data/zvuky_prirody.json`: hustota, hlasitost, dosah,
## intervaly, výšky, ladění, teploty, déšť, vítr, Dolbear, měsíce, časová okna, stanoviště) a **Zvěř/Hmyz a drobný
## život** (netopýři, světlušky, motýli, komáři, jepice – `SmallLife`). Úplný seznam `static var` ze `Soundscape`,
## `SmallLife`, nových konstant `Households` (zvuky práce) a `NatureLog.XP_FIRST`. Výchozí hodnoty = kód / data.
## Za snímek se registr nečte – `DevTune.tune` zapisuje do `static var` / slovníků katalogu (`Soundscape.data()`);
## změnu tabulky druhů převezme `Soundscape._on_tune` (znovu zkompiluje zdroje).
extends RefCounted

const SKUPINA := "Příroda/Zvuková krajina"
const SKUPINA_D := "Příroda/Zvuková krajina – druhy"
const SKUPINA_Z := "Zvěř/Hmyz a drobný život"
const MESICE := ["leden", "únor", "březen", "duben", "květen", "červen", "červenec", "srpen", "září", "říjen", "listopad", "prosinec"]


static func register_all() -> void:
	_rows(Soundscape, "sound.", SKUPINA, [
		["CELL", "cell", "Mřížka – velikost buňky emitorů", "m", "Rysy stanoviště se počítají na buňku. Změna vyprázdní smysl mezipaměti – projeví se po novém načtení.", 10.0, 120.0],
		["SCAN_R", "scan_r", "Mřížka – okruh buněk kolem posluchače", "m", "", 50.0, 600.0],
		["MAX_VOICES", "max_voices", "Výkon – současných 3D hlasů (pool)", "ks", "Platí po novém načtení světa.", 1.0, 48.0],
		["MAX_PER_SPECIES", "max_per_species", "Výběr – nejvýš hlasů jednoho druhu", "ks", "", 1.0, 16.0],
		["SELECT_S", "select_s", "Výkon – interval výběru zdrojů", "s", "", 0.1, 3.0],
		["CLASSIFY_PER_TICK", "classify_per_tick", "Výkon – nových buněk za výběr", "ks", "Rysy buňky (les, louka, voda…) se počítají jednou a drží v mezipaměti.", 1.0, 100.0],
		["CACHE_MAX", "cache_max", "Výkon – buněk v mezipaměti", "ks", "Po překročení se mezipaměť vyprázdní.", 500.0, 30000.0],
		["UNIT_SIZE", "unit_size", "Útlum – vzdálenost bez útlumu (unit_size)", "m", "Pro nové hlasy po novém načtení.", 1.0, 40.0],
		["FADE_IN_DB_S", "fade_in_db_s", "Prolínání – náběh hlasu", "dB/s", "", 1.0, 200.0],
		["FADE_OUT_DB_S", "fade_out_db_s", "Prolínání – doběh hlasu", "dB/s", "", 1.0, 200.0],
		["MASK_BASE_DB", "mask_base_db", "Výběr – práh odhadu hlasitosti u posluchače", "dB", "Tišší zdroje se nevybírají.", -80.0, 0.0],
		["WIND_MASK_DB", "wind_mask_db", "Výběr – vítr maskuje tiché zdroje", "dB/(m/s)", "", 0.0, 6.0],
		["RAMP_IN_MIN", "ramp_in_min", "Aktivita – náběh na začátku časového okna", "min", "", 0.0, 120.0],
		["RAMP_OUT_MIN", "ramp_out_min", "Aktivita – doběh na konci časového okna", "min", "", 0.0, 120.0],
		["RAIN_FULL", "rain_full", "Aktivita – déšť pro plný útlum (Weather.rain)", "×", "", 0.05, 1.0],
		["ACT_MIN", "act_min", "Aktivita – pod tím zdroj mlčí", "×", "", 0.0, 0.5],
		["INTERVAL_ACT_K", "interval_act_k", "Aktivita – interval volání / aktivita^k", "", "Nižší aktivita = řidší volání.", 0.0, 3.0],
		["DOLBEAR_A", "dolbear_a", "Cvrčci – Dolbear: cvrknutí/min na °C", "/min/°C", "Dolbearův zákon: N = A·T − B.", 0.0, 20.0],
		["DOLBEAR_B", "dolbear_b", "Cvrčci – Dolbear: odečet", "/min", "", 0.0, 100.0],
		["CHIRP_MIN", "chirp_min", "Cvrčci – pod tolika cvrknutími/min mlčí", "/min", "", 0.0, 60.0],
		["CHIRP_JITTER", "chirp_jitter", "Cvrčci – náhoda intervalu", "±×", "", 0.0, 0.5],
		["EDGE_K", "edge_k", "Stanoviště – okraj lesa = k·f·(1 − f)", "×", "", 0.0, 8.0],
		["WATER_R", "water_r", "Stanoviště – voda: dosah od toku / nádrže", "m", "", 5.0, 200.0],
		["POND_R", "pond_r", "Stanoviště – nádrž: dosah kolem rybníka", "m", "", 5.0, 200.0],
		["NIVA_HAND", "niva_hand", "Stanoviště – niva do výšky nad vodou (Site.hand)", "m", "", 0.5, 15.0],
		["VEG_LP_OPEN", "veg_lp_open", "Vegetace – mezní kmitočet bez lesa", "Hz", "", 2000.0, 20000.0],
		["VEG_LP_DENSE", "veg_lp_dense", "Vegetace – mezní kmitočet za hustým lesem", "Hz", "Hustý les tlumí výšky.", 200.0, 10000.0],
		["VEG_LP_DIST", "veg_lp_dist", "Vegetace – m hustého lesa do plného útlumu výšek", "m", "", 5.0, 400.0],
		["VEG_DB_100M", "veg_db_100m", "Vegetace – útlum navíc na 100 m lesa", "dB", "", 0.0, 30.0],
		["ECHO_TPI_M", "echo_tpi_m", "Ozvěna – údolí (Site.tpi pod okolím) pro plnou ozvěnu", "m", "", 1.0, 150.0],
		["ECHO_WET_MAX", "echo_wet_max", "Ozvěna – mokrý podíl v údolí", "×", "", 0.0, 1.0],
		["ECHO_FOREST_WET", "echo_forest_wet", "Ozvěna – dozvuk navíc v lese", "×", "", 0.0, 1.0],
		["ECHO_ROOM", "echo_room", "Ozvěna – velikost prostoru", "×", "", 0.0, 1.0],
		["ECHO_PREDELAY_MS", "echo_predelay_ms", "Ozvěna – zpoždění", "ms", "", 0.0, 500.0],
		["INDOOR_DB", "indoor_db", "Poslech – útlum v interiéru", "dB", "", -60.0, 0.0],
		["CAR_DB", "car_db", "Poslech – útlum v autě", "dB", "", -60.0, 0.0],
		["CANOPY_DB", "canopy_db", "Koruny – hlasitost šumění (plný les, ref. vítr)", "dB", "Listnáče šustí, jehličnany syčí (podíl z TreeEco).", -50.0, 10.0],
		["CANOPY_WIND_REF", "canopy_wind_ref", "Koruny – referenční vítr", "m/s", "", 1.0, 20.0],
		["CANOPY_GUST_K", "canopy_gust_k", "Koruny – vliv nárazu (WindField.gust_at)", "×", "", 0.0, 3.0],
		["CANOPY_WINTER_K", "canopy_winter_k", "Koruny – listnáče bez listí (× hlasitost)", "×", "Olistění z Phenology.foliage.", 0.0, 1.0],
		["CANOPY_SMOOTH", "canopy_smooth", "Koruny – vyhlazení hlasitosti", "/s", "", 0.1, 10.0],
		["HOUSE_R", "house_r", "Domy – pes a kohout do vzdálenosti", "m", "Od domácností (M8.17).", 50.0, 1500.0],
		["HEAR_LOG_R", "hear_log_r", "Deník – první uslyšení do vzdálenosti", "m", "", 5.0, 300.0],
		["HEAR_LOG_ACT", "hear_log_act", "Deník – první uslyšení od aktivity", "×", "", 0.0, 1.0],
	])
	_rows(NatureLog, "naturelog.", SKUPINA, [
		["XP_FIRST", "xp_first", "Deník – XP do Myslivosti za první pozorování / uslyšení", "XP", "", 0.0, 100.0],
	])
	_rows(Households, "village.", SKUPINA, [
		["RAKE_EVERY_S", "rake_every_s", "Práce u domů – interval tahů hrábí", "s", "Hrabání listí (říjen, listopad) – zvuk „rake“.", 0.2, 6.0],
		["SHOVEL_EVERY_S", "shovel_every_s", "Práce u domů – interval odhození sněhu", "s", "Zvuk „shovel“.", 0.2, 8.0],
		["RAKE_VOL", "rake_vol", "Práce u domů – hlasitost hrábí u zdroje", "dB", "", -40.0, 10.0],
		["SHOVEL_VOL", "shovel_vol", "Práce u domů – hlasitost lopaty u zdroje", "dB", "", -40.0, 10.0],
	])
	_species()
	_rows(SmallLife, "life.", SKUPINA_Z, [
		["TICK", "tick", "Výkon – výběr kotev a podmínek", "s", "", 0.2, 5.0],
		["LIFE_R", "life_r", "Okolí – kotvy do vzdálenosti od hráče", "m", "", 20.0, 200.0],
		["FADE_S", "fade_s", "Prolínání – objevení / zmizení", "s", "", 0.1, 10.0],
		["SEEN_R", "seen_r", "Deník – „viděno“ do vzdálenosti", "m", "", 2.0, 100.0],
		["LUX_FULL", "lux_full", "Jas – osvětlenost pro plné barvy", "lx", "", 100.0, 100000.0],
		["LIGHT_MIN", "light_min", "Jas – nejnižší jas barev", "×", "", 0.0, 1.0],
		["BAT_ANCHORS", "bat_anchors", "Netopýři – míst (kotev) najednou", "ks", "Platí po novém načtení.", 0.0, 10.0],
		["BAT_PER", "bat_per", "Netopýři – na místo", "ks", "Platí po novém načtení.", 1.0, 10.0],
		["BAT_SUN_MAX", "bat_sun_max", "Netopýři – létají, když je slunce pod", "°", "", -18.0, 10.0],
		["BAT_T_MIN", "bat_t_min", "Netopýři – nejnižší teplota", "°C", "", -5.0, 25.0],
		["BAT_WIND_MAX", "bat_wind_max", "Netopýři – nejvyšší vítr", "m/s", "", 0.0, 20.0],
		["BAT_RAIN_MAX", "bat_rain_max", "Netopýři – nejvyšší déšť", "×", "", 0.0, 1.0],
		["BAT_ROAM", "bat_roam", "Netopýři – poloměr letu", "m", "", 1.0, 40.0],
		["BAT_SPEED", "bat_speed", "Netopýři – rychlost cikcaku", "×", "", 0.1, 4.0],
		["BAT_HEIGHT", "bat_height", "Netopýři – výška nad zemí", "m", "", 0.5, 20.0],
		["BAT_VILLAGE_W", "bat_village_w", "Netopýři – váha obce (lampy) proti vodě", "×", "", 0.0, 1.0],
		["FF_ANCHORS", "ff_anchors", "Světlušky – míst najednou", "ks", "Platí po novém načtení.", 0.0, 10.0],
		["FF_PER", "ff_per", "Světlušky – na místo", "ks", "Platí po novém načtení.", 1.0, 80.0],
		["FF_DOY_A", "ff_doy_a", "Světlušky – od dne v roce", "den", "158 ≈ 7. června.", 100.0, 250.0],
		["FF_DOY_B", "ff_doy_b", "Světlušky – do dne v roce", "den", "196 ≈ 15. července.", 100.0, 250.0],
		["FF_SUN_MAX", "ff_sun_max", "Světlušky – jen když je slunce pod", "°", "", -18.0, 0.0],
		["FF_T_MIN", "ff_t_min", "Světlušky – nejnižší teplota", "°C", "Teplá noc.", 0.0, 30.0],
		["FF_WIND_MAX", "ff_wind_max", "Světlušky – nejvyšší vítr", "m/s", "", 0.0, 15.0],
		["FF_RAIN_MAX", "ff_rain_max", "Světlušky – nejvyšší déšť", "×", "", 0.0, 1.0],
		["FF_ROAM", "ff_roam", "Světlušky – poloměr plutí", "m", "", 0.5, 20.0],
		["FF_HEIGHT", "ff_height", "Světlušky – výška nad zemí", "m", "", 0.1, 5.0],
		["FF_GLOW", "ff_glow", "Světlušky – jas záblesku", "×", "", 0.0, 20.0],
		["FF_BLINK_HZ", "ff_blink_hz", "Světlušky – záblesků za sekundu", "Hz", "", 0.05, 3.0],
		["BF_ANCHORS", "bf_anchors", "Motýli – míst najednou", "ks", "Platí po novém načtení.", 0.0, 12.0],
		["BF_PER", "bf_per", "Motýli – na místo", "ks", "Platí po novém načtení.", 1.0, 12.0],
		["BF_MONTH_A", "bf_month_a", "Motýli – od měsíce", "měs.", "", 1.0, 12.0],
		["BF_MONTH_B", "bf_month_b", "Motýli – do měsíce", "měs.", "", 1.0, 12.0],
		["BF_SUN_MIN", "bf_sun_min", "Motýli – jen když je slunce nad", "°", "", -5.0, 60.0],
		["BF_T_MIN", "bf_t_min", "Motýli – nejnižší teplota", "°C", "", 0.0, 30.0],
		["BF_WIND_MAX", "bf_wind_max", "Motýli – nejvyšší vítr", "m/s", "", 0.0, 15.0],
		["BF_RAIN_MAX", "bf_rain_max", "Motýli – nejvyšší déšť", "×", "", 0.0, 1.0],
		["BF_BLOOM_MIN", "bf_bloom_min", "Motýli – nejmenší kvetení louky", "×", "Phenology.bees_bloom / Seasons.bloom.", 0.0, 1.0],
		["BF_ROAM", "bf_roam", "Motýli – poloměr poletování", "m", "", 0.5, 20.0],
		["BF_HEIGHT", "bf_height", "Motýli – výška nad zemí", "m", "", 0.1, 5.0],
		["BF_FLAP_HZ", "bf_flap_hz", "Motýli – mávání křídel", "Hz", "", 0.5, 30.0],
		["MQ_ANCHORS", "mq_anchors", "Komáři – rojů najednou", "ks", "Platí po novém načtení.", 0.0, 8.0],
		["MQ_PER", "mq_per", "Komáři – v roji", "ks", "Platí po novém načtení.", 1.0, 200.0],
		["MQ_MONTH_A", "mq_month_a", "Komáři – od měsíce", "měs.", "", 1.0, 12.0],
		["MQ_MONTH_B", "mq_month_b", "Komáři – do měsíce", "měs.", "", 1.0, 12.0],
		["MQ_SUN_MIN", "mq_sun_min", "Komáři – slunce nad (soumrak)", "°", "", -18.0, 20.0],
		["MQ_SUN_MAX", "mq_sun_max", "Komáři – slunce pod (soumrak)", "°", "", -18.0, 40.0],
		["MQ_T_MIN", "mq_t_min", "Komáři – nejnižší teplota", "°C", "", 0.0, 30.0],
		["MQ_WIND_MAX", "mq_wind_max", "Komáři – nejvyšší vítr", "m/s", "", 0.0, 10.0],
		["MQ_RAIN_MAX", "mq_rain_max", "Komáři – nejvyšší déšť", "×", "", 0.0, 1.0],
		["MQ_ROAM", "mq_roam", "Komáři – poloměr roje", "m", "", 0.1, 5.0],
		["MQ_HEIGHT", "mq_height", "Komáři – výška roje", "m", "", 0.2, 6.0],
		["MF_ANCHORS", "mf_anchors", "Jepice – rojů najednou", "ks", "Platí po novém načtení.", 0.0, 8.0],
		["MF_PER", "mf_per", "Jepice – v roji", "ks", "Platí po novém načtení.", 1.0, 80.0],
		["MF_DOY_A", "mf_doy_a", "Jepice – od dne v roce", "den", "125 ≈ 5. května.", 60.0, 250.0],
		["MF_DOY_B", "mf_doy_b", "Jepice – do dne v roce", "den", "", 60.0, 250.0],
		["MF_HOUR_A", "mf_hour_a", "Jepice – od hodiny", "h", "", 0.0, 24.0],
		["MF_HOUR_B", "mf_hour_b", "Jepice – do hodiny", "h", "", 0.0, 24.0],
		["MF_T_MIN", "mf_t_min", "Jepice – nejnižší teplota", "°C", "", 0.0, 30.0],
		["MF_WIND_MAX", "mf_wind_max", "Jepice – nejvyšší vítr", "m/s", "", 0.0, 15.0],
		["MF_RAIN_MAX", "mf_rain_max", "Jepice – nejvyšší déšť", "×", "", 0.0, 1.0],
		["MF_ROAM", "mf_roam", "Jepice – poloměr roje", "m", "", 0.1, 10.0],
		["MF_HEIGHT", "mf_height", "Jepice – výška tance nad zemí", "m", "", 0.1, 6.0],
	])


## Celá tabulka druhů (`data/zvuky_prirody.json`) – id `sound.src.<druh>.<klíč>`.
static func _species() -> void:
	var d := Soundscape.data()
	for e in d.get("zdroje", []):
		var z: Dictionary = e
		var id := String(z.get("id", ""))
		var nm := String(z.get("nazev", id))
		var pre := "sound.src.%s." % id
		for r in [["hustota", "hustota teritoria ve vhodné buňce", "×", 0.0, 1.0],
				["hlasitost", "hlasitost u zdroje", "dB", -40.0, 20.0],
				["dosah", "dosah", "m", 10.0, 2000.0],
				["t_min", "teplota – pod tím ticho", "°C", -30.0, 30.0],
				["t_plne", "teplota – plná aktivita od", "°C", -30.0, 35.0],
				["dest", "útlum deštěm", "×", 0.0, 1.0],
				["vitr", "vítr, při kterém už ticho", "m/s", 0.5, 40.0],
				["dolbear", "Dolbear – násobek rychlosti cvrkání", "×", 0.0, 3.0]]:
			if z.has(r[0]):
				DevTune.tune(z, r[0], pre + String(r[0]), SKUPINA_D, "%s – %s" % [nm, r[1]], float(r[3]), float(r[4]),
					_step(float(r[4]) - float(r[3])), "", String(r[2]))
		for r in [["interval", "interval volání", "s", 0.0, 300.0], ["vyska", "výška nad zemí", "m", 0.0, 150.0],
				["ladeni", "ladění (výška tónu)", "×", 0.3, 2.0]]:
			var arr: Array = z.get(r[0], [])
			for j in mini(arr.size(), 2):
				DevTune.tune(arr, j, "%s%s_%s" % [pre, r[0], "od" if j == 0 else "do"], SKUPINA_D,
					"%s – %s %s" % [nm, r[1], "od" if j == 0 else "do"], float(r[3]), float(r[4]), _step(float(r[4]) - float(r[3])), "", String(r[2]))
		var mo: Array = z.get("mesice", [])
		for j in mini(mo.size(), 12):
			DevTune.tune(mo, j, "%smonth_%02d" % [pre, j + 1], SKUPINA_D, "%s – aktivita v měsíci %s" % [nm, MESICE[j]], 0.0, 1.0, 0.01,
				"Sezóna zpěvu / hlasu.", "×")
		var ok: Array = z.get("okna", [])
		for j in ok.size():
			var w: Array = ok[j]
			if w.size() < 4:
				continue
			var kotva := String(w[0])
			var unit := "h" if kotva == "h" else "min"
			var kde: String = {"v": "od východu", "z": "od západu", "h": "hodina"}.get(kotva, kotva)
			var lo := 0.0 if kotva == "h" else -720.0
			var hi := 36.0 if kotva == "h" else 720.0
			DevTune.tune(w, 1, "%swin%d_od" % [pre, j], SKUPINA_D, "%s – okno %d začátek (%s)" % [nm, j + 1, kde], lo, hi,
				0.25 if kotva == "h" else 1.0, "", unit)
			DevTune.tune(w, 2, "%swin%d_do" % [pre, j], SKUPINA_D, "%s – okno %d konec (%s)" % [nm, j + 1, kde], lo, hi,
				0.25 if kotva == "h" else 1.0, "", unit)
			DevTune.tune(w, 3, "%swin%d_w" % [pre, j], SKUPINA_D, "%s – okno %d váha" % [nm, j + 1], 0.0, 1.0, 0.01, "", "×")
		var hb: Dictionary = z.get("stanoviste", {})
		for k in hb:
			DevTune.tune(hb, k, "%shab_%s" % [pre, String(k)], SKUPINA_D, "%s – stanoviště %s" % [nm, String(k)], 0.0, 1.0, 0.01,
				"Vhodnost buňky (rysy Soundscape).", "×")


## Řádky [vlastnost, id, popisek, jednotka, nápověda, min, max] → `DevTune.tune(target, …)` (typ podle výchozí hodnoty).
static func _rows(target: Variant, prefix: String, group: String, list: Array) -> void:
	for r in list:
		var v: Variant = (target as Object).get(String(r[0]))
		var step := 1.0
		if v is float:
			step = _step(float(v))
			if float(r[6]) - float(r[5]) <= 1.0:
				step = minf(step, 0.01)
		DevTune.tune(target, r[0], prefix + String(r[1]), group, String(r[2]), float(r[5]), float(r[6]), step, String(r[4]), String(r[3]))


static func _step(v: float) -> float:
	var a := absf(v)
	if a < 1.0e-9:
		return 0.01
	return maxf(pow(10.0, floorf(log(a) / log(10.0)) - 2.0), 1.0e-6)
