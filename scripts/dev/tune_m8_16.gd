## M8.16 Tělo 2: menu pro vývojáře (F3) – skupina **Člověk / Tělo – teplo a energie**: tepelná bilance (MET, konvekce
## s větrem, odpařování, záření, vedení, izolace v clo), teplota jádra → prochladnutí / přehřátí, voda v těle (žízeň,
## diuréza z alkoholu), spánkový dluh a mikrospánek, zranění pádem. Úplný seznam nových `static var` z `BodyState`
## (starší konstanty těla registruje `tune_clovek.gd` – tady se neopakují). Výchozí hodnoty = kód (chování beze změny).
## Za snímek se registr nečte – `DevTune.tune` zapisuje přímo do `static var` / slovníku `ACTION_MET`.
extends RefCounted

const SKUPINA := "Člověk/Tělo – teplo a energie"


static func register_all() -> void:
	_rows([
		["THERMO_STEP_S", "thermo_step_s", "Teplo – reálného času mezi kroky bilance (4×/s)", "s", "reálného času mezi kroky bilance (4×/s)", 0.0, 1.0],
		["THERMO_MAX_DT_H", "thermo_max_dt_h", "Teplo – nejdelší vnitřní krok (spánek / přeskok času se dělí)", "h", "nejdelší vnitřní krok (spánek / přeskok času se dělí)", 0.0, 1.0],
		["BODY_AREA_M2", "body_area_m2", "Teplo – povrch těla (DuBois, 82 kg / 180 cm)", "m²", "povrch těla (DuBois, 82 kg / 180 cm)", 0.0, 5.7],
		["MET_W_M2", "met_w_m2", "Teplo – 1 MET = 58,2 W/m²", "m²", "1 MET = 58,2 W/m²", 0.0, 174.6],
		["HEAT_CAP_WH_K", "heat_cap_wh_k", "Teplo – efektivní tepelná kapacita (jádro + část slupky)", "Wh/K", "efektivní tepelná kapacita (jádro + část slupky)", 0.0, 180.0],
		["T_CORE_NORMAL", "t_core_normal", "Teplo – normální teplota jádra", "°C", "normální teplota jádra", 27.0, 47.0],
		["T_CORE_MIN", "t_core_min", "Teplo – nejnižší teplota jádra (strop modelu)", "°C", "nejnižší teplota jádra (strop modelu)", 20.0, 40.0],
		["T_CORE_MAX", "t_core_max", "Teplo – nejvyšší teplota jádra (strop modelu)", "°C", "nejvyšší teplota jádra (strop modelu)", 31.5, 51.5],
		["T_SKIN_NEUTRAL", "t_skin_neutral", "Teplo – kůže při jádru 37 °C", "°C", "kůže při jádru 37 °C", 23.7, 43.7],
		["VASO_K", "vaso_k", "Teplo – kůže na °C jádra (vazokonstrikce / vazodilatace)", "K/K", "kůže na °C jádra (vazokonstrikce / vazodilatace)", 0.0, 12.0],
		["T_SKIN_MIN", "t_skin_min", "Teplo – nejnižší teplota kůže", "°C", "nejnižší teplota kůže", 16.0, 36.0],
		["T_SKIN_MAX", "t_skin_max", "Teplo – nejvyšší teplota kůže", "°C", "nejvyšší teplota kůže", 26.0, 46.0],
		["SHIVER_FROM", "shiver_from", "Teplo – práh jádra – začíná třes", "°C", "práh jádra – začíná třes", 26.8, 46.8],
		["SHIVER_W_K", "shiver_w_k", "Teplo – třes – W na °C pod prahem", "W/K", "třes – W na °C pod prahem", 0.0, 750.0],
		["SHIVER_MAX_W", "shiver_max_w", "Teplo – třes – nejvyšší výkon", "W", "třes – nejvyšší výkon", 0.0, 1050.0],
		["SWEAT_FROM", "sweat_from", "Teplo – práh jádra – začíná pocení", "°C", "práh jádra – začíná pocení", 27.1, 47.1],
		["SWEAT_W_K", "sweat_w_k", "Teplo – pocení – W odparu na °C nad prahem (požadavek)", "W/K", "pocení – W odparu na °C nad prahem (požadavek)", 0.0, 1200.0],
		["EVAP_CLO_K", "evap_clo_k", "Teplo – výparného odporu na 1 clo (Lewisův vztah, i_m ≈ 0,45)", "m²·kPa/W", "výparného odporu na 1 clo (Lewisův vztah, i_m ≈ 0,45)", 0.0, 1.0],
		["LEWIS_K", "lewis_k", "Teplo – Lewisův poměr", "K/kPa", "Lewisův poměr", 0.0, 49.5],
		["INSENSIBLE_W", "insensible_w", "Teplo – neznatelný odpar kůží", "W", "neznatelný odpar kůží", 0.0, 45.0],
		["CLO_PER_INSUL", "clo_per_insul", "Teplo – clo na 1,0 herní izolace", "clo", "clo na 1,0 herní izolace (`INSUL_BASE` 0,4 = triko + džíny ≈ 0,6 clo)", 0.0, 4.5],
		["SLEEP_CLO", "sleep_clo", "Teplo – clo v posteli / ve spacáku", "clo", "clo v posteli / ve spacáku", 0.0, 7.5],
		["WET_CLO_LOSS", "wet_clo_loss", "Teplo – mokré oblečení ztrácí tolik izolace (×wetness)", "×", "mokré oblečení ztrácí tolik izolace (×wetness)", 0.0, 1.95],
		["VENT_FROM", "vent_from", "Teplo – práh jádra – hráč se „rozepne“ (izolace klesá)", "°C", "práh jádra – hráč se „rozepne“ (izolace klesá)", 27.2, 47.2],
		["VENT_RANGE", "vent_range", "Teplo – rozsah, ve kterém se rozepne naplno", "°C", "rozsah, ve kterém se rozepne naplno", 0.0, 2.4],
		["VENT_MAX", "vent_max", "Teplo – nejvýš tolik izolace ubere rozepnutí", "×", "nejvýš tolik izolace ubere rozepnutí", 0.0, 1.5],
		["WIND_BODY_K", "wind_body_k", "Teplo – vítr ve výšce těla / vítr v 10 m (logaritmický profil)", "×", "vítr ve výšce těla / vítr v 10 m (logaritmický profil)", 0.0, 2.1],
		["WALK_AIR_K", "walk_air_k", "Teplo – podíl rychlosti chůze, který působí jako vítr", "×", "podíl rychlosti chůze, který působí jako vítr", 0.0, 1.8],
		["AIR_MIN_MS", "air_min_ms", "Teplo – volná konvekce v bezvětří", "m/s", "volná konvekce v bezvětří", 0.0, 1.0],
		["WIND_CLO_K", "wind_clo_k", "Teplo – stlačení izolace větrem na m/s (bez větruodolné vrstvy)", "×/(m/s)", "stlačení izolace větrem na m/s (bez větruodolné vrstvy)", 0.0, 1.0],
		["WIND_CLO_MAX", "wind_clo_max", "Teplo – nejvýš tolik izolace vítr ubere", "×", "nejvýš tolik izolace vítr ubere", 0.0, 1.5],
		["HC_BASE", "hc_base", "Teplo – přestup tepla konvekcí v klidu", "W/m²K", "přestup tepla konvekcí v klidu", 0.0, 9.0],
		["HC_WIND_K", "hc_wind_k", "Teplo – na √(m/s)", "W/m²K", "na √(m/s)", 0.0, 24.9],
		["HR_W_M2K", "hr_w_m2k", "Teplo – sálání (lineárně)", "W/m²K", "sálání (lineárně)", 0.0, 14.1],
		["FCL_K", "fcl_k", "Teplo – zvětšení povrchu oděvem na 1 clo", "×", "zvětšení povrchu oděvem na 1 clo", 0.0, 1.0],
		["WATER_HC", "water_hc", "Teplo – navíc při úplném ponoření (voda odvádí teplo ~25× víc)", "W/m²K", "navíc při úplném ponoření (voda odvádí teplo ~25× víc)", 0.0, 600.0],
		["IMMERSE_DEPTH", "immerse_depth", "Teplo – hloubka, ve které je tělo ponořené celé", "m", "hloubka, ve které je tělo ponořené celé", 0.0, 3.9],
		["SUN_AREA_M2", "sun_area_m2", "Teplo – efektivní plocha osvětlená sluncem", "m²", "efektivní plocha osvětlená sluncem", 0.0, 1.05],
		["SUN_ABSORB", "sun_absorb", "Teplo – pohltivost oděvu / kůže", "×", "pohltivost oděvu / kůže", 0.0, 2.1],
		["CANOPY_SHADE", "canopy_shade", "Teplo – stín plného zápoje korun", "×", "stín plného zápoje korun", 0.0, 2.55],
		["NIGHT_SKY_W", "night_sky_w", "Teplo – ztráta sáláním do jasné noční oblohy", "W", "ztráta sáláním do jasné noční oblohy", 0.0, 120.0],
		["FIRE_W", "fire_w", "Teplo – teplo od ohně / kamen při heat = 1", "W", "teplo od ohně / kamen při heat = 1", 0.0, 1200.0],
		["ROOF_WARM_K", "roof_warm_k", "Teplo – pod střechou venku", "×", "pod střechou venku (zastávka, kůlna) se vzduch přiblíží tolik k `shelter_min`", 0.0, 1.0],
		["COND_SIT_M2", "cond_sit_m2", "Teplo – styk se zemí v podřepu / vkleče", "m²", "styk se zemí v podřepu / vkleče", 0.0, 1.0],
		["COND_LIE_M2", "cond_lie_m2", "Teplo – vleže", "m²", "vleže", 0.0, 1.5],
		["COND_R_BASE", "cond_r_base", "Teplo – odpor styku bez oděvu", "m²K/W", "odpor styku bez oděvu", 0.0, 1.0],
		["COND_SNOW_K", "cond_snow_k", "Teplo – sníh / mokrá zem vede víc", "×", "sníh / mokrá zem vede víc", 0.0, 4.5],
		["RESP_LAT_K", "resp_lat_k", "Teplo – dýchání – latentní ztráta (ISO 7730)", "×", "dýchání – latentní ztráta (ISO 7730)", 0.0, 1.0],
		["RESP_LAT_PA", "resp_lat_pa", "Teplo – kPa", "kPa", "kPa", 0.0, 17.61],
		["RESP_CONV_K", "resp_conv_k", "Teplo – dýchání – citelná ztráta", "×", "dýchání – citelná ztráta", 0.0, 1.0],
		["RESP_T", "resp_t", "Teplo – vydechovaného vzduchu", "°C", "vydechovaného vzduchu", 24.0, 44.0],
		["WET_EVAP_W", "wet_evap_w", "Teplo – odpar z plně mokrého oděvu při sytostním deficitu 1 kPa", "W", "odpar z plně mokrého oděvu při sytostním deficitu 1 kPa", 0.0, 180.0],
		["MET_SLEEP", "met_sleep", "Činnost (MET) – spánek", "MET", "spánek", 0.0, 2.7],
		["MET_STAND", "met_stand", "Činnost (MET) – stání", "MET", "stání", 0.0, 3.6],
		["MET_SEATED", "met_seated", "Činnost (MET) – v autě, v letadle", "MET", "v autě, v letadle", 0.0, 3.9],
		["MET_HORSE", "met_horse", "Činnost (MET) – jízda na koni", "MET", "jízda na koni", 0.0, 6.6],
		["MET_WALK_BASE", "met_walk_base", "Činnost (MET) – chůze: základ + k × rychlost (1,4 m/s ≈ 3,5 MET)", "MET", "chůze: základ + k × rychlost (1,4 m/s ≈ 3,5 MET)", 0.0, 4.5],
		["MET_WALK_PER_MS", "met_walk_per_ms", "Činnost (MET) – chůze – MET na m/s rychlosti", "MET/(m/s)", "chůze – MET na m/s rychlosti", 0.0, 4.2],
		["MET_MOVE_V", "met_move_v", "Činnost (MET) – od této rychlosti se počítá chůze", "m/s", "od této rychlosti se počítá chůze", 0.0, 1.0],
		["MET_RUN", "met_run", "Činnost (MET) – běh (sprint)", "MET", "běh (sprint)", 0.0, 24.0],
		["MET_RUN_V", "met_run_v", "Činnost (MET) – od této rychlosti běh", "m/s", "od této rychlosti běh", 0.0, 13.5],
		["MET_SWIM", "met_swim", "Činnost (MET) – plavání", "MET", "plavání", 0.0, 21.0],
		["MET_CLIMB_PER_MS", "met_climb_per_ms", "Činnost (MET) – MET na m/s stoupání (82 kg × g × v / účinnost 0,25)", "MET/(m/s)", "MET na m/s stoupání (82 kg × g × v / účinnost 0,25)", 0.0, 75.0],
		["MET_DESCENT_K", "met_descent_k", "Činnost (MET) – z kopce se ušetří jen část", "×", "z kopce se ušetří jen část", 0.0, 1.0],
		["MET_LOAD_PER_KG", "met_load_per_kg", "Činnost (MET) – MET na kg nákladu při chůzi (20–50 kg → +1–2,5)", "MET/kg", "MET na kg nákladu při chůzi (20–50 kg → +1–2,5)", 0.0, 1.0],
		["MET_LOAD_STAND_K", "met_load_stand_k", "Činnost (MET) – podíl při stání", "×", "podíl při stání", 0.0, 1.0],
		["MET_MAX", "met_max", "Činnost (MET) – strop MET", "MET", "strop MET", 0.0, 36.0],
		["COLD_CORE_FROM", "cold_core_from", "Teplota jádra – práh jádra – od kdy roste prochladnutí", "°C", "práh jádra – od kdy roste prochladnutí", 26.5, 46.5],
		["COLD_CORE_FULL", "cold_core_full", "Teplota jádra – plné prochladnutí (podchlazení)", "°C", "plné prochladnutí (podchlazení)", 25.0, 45.0],
		["HEAT_CORE_FROM", "heat_core_from", "Teplota jádra – od kdy roste přehřátí", "°C", "od kdy roste přehřátí", 27.6, 47.6],
		["HEAT_CORE_FULL", "heat_core_full", "Teplota jádra – plné přehřátí", "°C", "plné přehřátí", 29.0, 49.0],
		["LATENT_WH_L", "latent_wh_l", "Voda – na litr odpařené vody", "Wh/l", "na litr odpařené vody", 0.0, 2040.0],
		["SWEAT_DRIP_K", "sweat_drip_k", "Voda – vyprodukovaný pot / odpařený pot", "×", "vyprodukovaný pot / odpařený pot", 0.0, 3.9],
		["SWEAT_WET_PER_L", "sweat_wet_per_l", "Voda – neodpařený pot (l) promáčí oděv o tolik", "×/l", "neodpařený pot (l) promáčí oděv o tolik", 0.0, 1.8],
		["URINE_L_H", "urine_l_h", "Voda – moč při normální hydrataci", "l/h", "moč při normální hydrataci", 0.0, 1.0],
		["URINE_HYDR_L", "urine_hydr_l", "Voda – ledviny šetří při deficitu (lineárně)", "l", "ledviny šetří při deficitu (lineárně)", 0.0, 3.0],
		["URINE_MIN_K", "urine_min_k", "Voda – moč – nejnižší násobek při deficitu", "×", "moč – nejnižší násobek při deficitu", 0.0, 1.0],
		["HYDR_MAX_L", "hydr_max_l", "Voda – přebytek nad optimum se vyloučí", "l", "přebytek nad optimum se vyloučí", 0.0, 1.5],
		["HYDR_MIN_L", "hydr_min_l", "Voda – nejhlubší deficit vody", "l", "nejhlubší deficit vody", -15.0, 0.0],
		["THIRST_FROM_L", "thirst_from_l", "Voda – deficitu – začíná žízeň", "l", "deficitu – začíná žízeň", 0.0, 1.5],
		["THIRST_FULL_L", "thirst_full_l", "Voda – (~3 % hmotnosti) – silná žízeň / dehydratace", "l", "(~3 % hmotnosti) – silná žízeň / dehydratace", 0.0, 7.5],
		["DIURESIS_L_G", "diuresis_l_g", "Voda – moči navíc na 1 g odbouraného alkoholu", "l/g", "moči navíc na 1 g odbouraného alkoholu (pivo hydratuje méně, kořalka odvodní)", 0.0, 1.0],
		["FOOD_WATER_L_KCAL", "food_water_l_kcal", "Voda – vody z jídla na kcal", "l/kcal", "vody z jídla na kcal", 0.0, 1.0],
		["STAM_THIRST_K", "stam_thirst_k", "Voda – ztráta max. výdrže při plné žízni", "×", "ztráta max. výdrže při plné žízni", 0.0, 1.0],
		["DRAIN_THIRST_K", "drain_thirst_k", "Voda – zrychlení únavy při plné žízni", "×", "zrychlení únavy při plné žízni", 0.0, 1.2],
		["HEADACHE_FROM", "headache_from", "Voda – žízeň, od které bolí hlava (mírný efekt obrazu)", "×", "žízeň, od které bolí hlava (mírný efekt obrazu)", 0.0, 1.8],
		["HEADACHE_FX", "headache_fx", "Voda – efekt obrazu (jako opilost) při plné dehydrataci", "×", "efekt obrazu (jako opilost) při plné dehydrataci", 0.0, 1.0],
		["DEHYDR_HP_H", "dehydr_hp_h", "Voda – zdraví za hodinu při plné dehydrataci", "HP/h", "zdraví za hodinu při plné dehydrataci", 0.0, 6.0],
		["STREAM_NAUSEA_CHANCE", "stream_nausea_chance", "Voda – šance nevolnosti po vodě z potoka", "×", "šance nevolnosti po vodě z potoka", 0.0, 1.0],
		["STREAM_NAUSEA", "stream_nausea", "Voda – nevolnost po vodě z potoka (síla)", "×", "nevolnost po vodě z potoka (síla)", 0.0, 1.05],
		["SLEEP_DEBT_RATE", "sleep_debt_rate", "Spánek – dluhu za hodinu bdění", "h/h", "dluhu za hodinu bdění", 0.0, 3.0],
		["SLEEP_RECOVER", "sleep_recover", "Spánek – dluhu smazaných hodinou spánku", "h/h", "dluhu smazaných hodinou spánku", 0.0, 6.0],
		["SLEEP_DEBT_MAX", "sleep_debt_max", "Spánek – strop spánkového dluhu", "h", "strop spánkového dluhu", 0.0, 144.0],
		["DROWSY_FROM_H", "drowsy_from_h", "Spánek – bdění – začíná ospalost", "h", "bdění – začíná ospalost", 0.0, 48.0],
		["DROWSY_FULL_H", "drowsy_full_h", "Spánek – plná ospalost", "h", "plná ospalost", 0.0, 90.0],
		["CAFFEINE_AWAKE_K", "caffeine_awake_k", "Spánek – kofein (1,0) ubere tolik ospalosti", "×", "kofein (1,0) ubere tolik ospalosti", 0.0, 1.8],
		["DROWSY_FX", "drowsy_fx", "Spánek – ospalost (1,0) = tolik „opilosti“ (reakce, efekt obrazu)", "×", "ospalost (1,0) = tolik „opilosti“ (reakce, efekt obrazu)", 0.0, 1.0],
		["STAM_DROWSY_K", "stam_drowsy_k", "Spánek – ztráta max. výdrže při plné ospalosti", "×", "ztráta max. výdrže při plné ospalosti", 0.0, 1.0],
		["MICROSLEEP_FROM", "microsleep_from", "Spánek – ospalost, od které hrozí mikrospánek", "×", "ospalost, od které hrozí mikrospánek", 0.0, 1.5],
		["MICROSLEEP_PER_H", "microsleep_per_h", "Spánek – mikrospánků za herní hodinu při plné ospalosti", "/h", "mikrospánků za herní hodinu při plné ospalosti", 0.0, 12.0],
		["MICROSLEEP_S", "microsleep_s", "Spánek – reálného času – zatmění obrazu", "s", "reálného času – zatmění obrazu", 0.0, 3.6],
		["FALL_G", "fall_g", "Pád – tíhové zrychlení pro rychlost dopadu", "m/s²", "tíhové zrychlení pro rychlost dopadu", 0.0, 29.43],
		["FALL_PAIN_V", "fall_pain_v", "Pád – (≈ 2 m) – bolest a krátké kulhání", "m/s", "(≈ 2 m) – bolest a krátké kulhání", 0.0, 18.0],
		["FALL_INJURY_V", "fall_injury_v", "Pád – (≈ 4 m) – zranění", "m/s", "(≈ 4 m) – zranění", 0.0, 27.0],
		["FALL_SEVERE_V", "fall_severe_v", "Pád – (≈ 9 m) – vážné zranění", "m/s", "(≈ 9 m) – vážné zranění", 0.0, 39.0],
		["FALL_KO_V", "fall_ko_v", "Pád – (≈ 11,5 m) – bezvědomí (probuzení v nemocnici)", "m/s", "(≈ 11,5 m) – bezvědomí (probuzení v nemocnici)", 0.0, 45.0],
		["FALL_PAIN_HP_V", "fall_pain_hp_v", "Pád – zdraví na m/s nad prahem bolesti", "HP/(m/s)", "zdraví na m/s nad prahem bolesti", 0.0, 6.0],
		["FALL_INJ_HP", "fall_inj_hp", "Pád – zdraví při zranění", "HP", "zdraví při zranění", 0.0, 30.0],
		["FALL_INJ_HP_V", "fall_inj_hp_v", "Pád – + na m/s nad prahem zranění", "HP/(m/s)", "+ na m/s nad prahem zranění", 0.0, 18.0],
		["FALL_SEVERE_HP", "fall_severe_hp", "Pád – zdraví při vážném zranění", "HP", "zdraví při vážném zranění", 0.0, 135.0],
		["FALL_DOWN_INJ_S", "fall_down_inj_s", "Pád – ležení po zranění", "s", "ležení po zranění", 0.0, 7.5],
		["FALL_DOWN_SEVERE_S", "fall_down_severe_s", "Pád – ležení po vážném zranění", "s", "ležení po vážném zranění", 0.0, 18.0],
		["LIMP_H_PER_V", "limp_h_per_v", "Pád – kulhání na m/s nad prahem bolesti", "h/(m/s)", "kulhání na m/s nad prahem bolesti", 0.0, 1.5],
		["LIMP_INJ_H", "limp_inj_h", "Pád – kulhání po zranění", "h", "kulhání po zranění", 0.0, 18.0],
		["LIMP_MAX_H", "limp_max_h", "Pád – nejdelší kulhání", "h", "nejdelší kulhání", 0.0, 144.0],
		["LIMP_WALK_K", "limp_walk_k", "Pád – rychlost chůze při kulhání", "×", "rychlost chůze při kulhání", 0.0, 2.1],
		["PAIN_DECAY", "pain_decay", "Pád – ústup bolesti", "/h", "ústup bolesti", 0.0, 1.0],
		["SOFT_SNOW_K", "soft_snow_k", "Pád – sníh (snow_cover 1) pohltí tolik rychlosti dopadu", "×", "sníh (snow_cover 1) pohltí tolik rychlosti dopadu", 0.0, 1.05],
		["SOFT_WATER_K", "soft_water_k", "Pád – hluboká voda pohltí tolik", "×", "hluboká voda pohltí tolik", 0.0, 2.1],
		["SOFT_WATER_DEPTH", "soft_water_depth", "Pád – voda „hluboká“ pro dopad", "m", "voda „hluboká“ pro dopad", 0.0, 3.6],
	])
	# MET podle pózy činnosti (`Humanoid.action` z `Actions.DEFS.anim`) – slovník, klíč = póza
	var names := {"chop": "sekání / kácení / štípání", "dig": "rytí / kopání", "kneel": "práce vkleče (oheň, sběr)",
		"pour": "zalévání / lití", "cast": "nahazování udice", "aim": "míření"}
	for k in BodyState.ACTION_MET:
		DevTune.tune(BodyState.ACTION_MET, k, "body.thermo.action_met.%s" % k, SKUPINA,
			"Činnost (MET) – %s" % String(names.get(k, k)), 1.0, 12.0, 0.1,
			"Metabolický výdej při póze „%s“ (nahradí stání, pokud je vyšší). Sekání dřeva ~6, rytí ~5." % k, "MET")


## Řádky [vlastnost, id, popisek, jednotka, nápověda, min, max] → `DevTune.tune(BodyState, …)`.
static func _rows(list: Array) -> void:
	var target: Variant = BodyState
	for r in list:
		var v := float(target.get(String(r[0])))
		DevTune.tune(target, r[0], "body.thermo." + String(r[1]), SKUPINA, String(r[2]), float(r[5]), float(r[6]),
			_step(v), String(r[4]), String(r[3]))


## Krok posuvníku podle řádu výchozí hodnoty.
static func _step(v: float) -> float:
	var a := absf(v)
	if a < 1.0e-9:
		return 0.01
	return maxf(pow(10.0, floorf(log(a) / log(10.0)) - 2.0), 1.0e-6)
