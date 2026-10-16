## M8.13: menu pro vývojáře – terramechanika (bláto, zaboření, koleje). Úplný seznam laditelných konstant kroku:
## půdy (Bekker / Mohr–Coulomb po půdních třídách), stav půdy, sníh, kolo (`Terramech`), auto v blátě (`Car.TM_*`),
## pneumatiky podle druhu vozidla (`Car.TUNES[druh].tm_*`), ruční vozík, chodec, kůň a koleje (`RutMap`).
## Výchozí hodnoty se berou z kódu (`DevTune.tune` čte současnou hodnotu) – chování ve výchozím stavu beze změny.
## Za snímek se registr nečte: Terramech / Car / RutMap čtou své `static var`, pneu se přepočítá v `Car._apply_tune`
## (id `<druh>.tm_*`), shader kolejí v `RutMap._on_tune` (id `ruts.*`).
extends RefCounted

const G_VEH := "Vozidla/Terén a bláto"
const G_FOOT := "Člověk/Pohyb hráče"
const G_HORSE := "Zvěř/Hospodářská zvířata"
const G_RUTS := "Příroda/Louže, stopy"

## Půdní třídy (pořadí `Site.SOIL_*`) – kód do id a název do popisku.
const SOILS := [["hnedozem", "hnědozem"], ["ranker", "ranker / litozem"], ["arenosol", "arenosol (písek)"],
	["glej", "pseudoglej / glej"], ["fluvizem", "fluvizem (niva)"], ["antropozem", "antropozem (obec)"]]

## Tabulky půd: [pole Terramech, kód id, popisek, min, max, krok, jednotka, nápověda].
const SOIL_ROWS := [
	["N_DRY", "n_dry", "exponent n – sucho", 0.1, 2.0, 0.01, "", "Bekker: p = k·z^n. Menší n = půda se pod tlakem boří prudčeji."],
	["N_WET", "n_wet", "exponent n – rozmáčeno", 0.1, 2.0, 0.01, "", ""],
	["KC_DRY", "kc_dry", "k_c (soudržnost) – sucho", 0.0, 200.0, 0.1, "kN/m^(n+1)", "Bekker: kohezní modul deformace (dělí se šířkou stopy)."],
	["KC_WET", "kc_wet", "k_c (soudržnost) – rozmáčeno", 0.0, 50.0, 0.05, "kN/m^(n+1)", ""],
	["KPHI_DRY", "kphi_dry", "k_φ (tření) – sucho", 10.0, 40000.0, 10.0, "kN/m^(n+2)", "Bekker: třecí modul deformace – hlavní „tuhost“ půdy."],
	["KPHI_WET", "kphi_wet", "k_φ (tření) – rozmáčeno", 1.0, 5000.0, 1.0, "kN/m^(n+2)", "Malé = bořivé bláto."],
	["C_DRY", "c_dry", "soudržnost c – sucho", 0.0, 50.0, 0.1, "kPa", "Mohr–Coulomb: H = A·c + W·tan φ (tažná síla)."],
	["C_WET", "c_wet", "soudržnost c – rozmáčeno", 0.0, 30.0, 0.1, "kPa", ""],
	["PHI_DRY", "phi_dry", "úhel vnitřního tření φ – sucho", 0.0, 45.0, 0.5, "°", "Větší = lepší záběr pneumatiky."],
	["PHI_WET", "phi_wet", "úhel vnitřního tření φ – rozmáčeno", 0.0, 45.0, 0.5, "°", "Jílovité bláto ~5–10°."],
]

## Skaláry Terramech: [vlastnost, id, skupina, popisek, min, max, krok, jednotka, nápověda].
const TM_ROWS := [
	["WET_FROM", "wet_from", G_VEH, "Půda – měkne od vlhkosti", 0.0, 1.0, 0.01, "× AWC", "SoilWater.moisture_at, od které půda začíná měknout."],
	["WET_FULL", "wet_full", G_VEH, "Půda – plně rozmáčená při vlhkosti", 0.1, 1.5, 0.01, "× AWC", ""],
	["MUD_W", "mud_w", G_VEH, "Půda – váha bláta (mud_at)", 0.0, 3.0, 0.01, "×", "Rozmáčenost = max(vlhkost, bláto × tohle)."],
	["FROZEN_K", "frozen_k", G_VEH, "Půda – zamrzlá: tuhost ×", 0.0, 200.0, 0.5, "×", "Tuhost × (1 + tohle × zamrznutí SoilWater.frost)."],
	["FALLBACK_SOIL", "fallback_soil", G_VEH, "Půda – třída bez dat site.bin", 0, 5, 1, "", "0 hnědozem, 1 ranker, 2 arenosol, 3 glej, 4 fluvizem, 5 antropozem."],
	["SNOW_N", "snow_n", G_VEH, "Sníh – exponent n", 0.5, 3.0, 0.01, "", "Wong: sníh."],
	["SNOW_KC", "snow_kc", G_VEH, "Sníh – k_c", 0.0, 30.0, 0.05, "kN/m^(n+1)", ""],
	["SNOW_KPHI", "snow_kphi", G_VEH, "Sníh – k_φ", 1.0, 1000.0, 1.0, "kN/m^(n+2)", ""],
	["SNOW_C", "snow_c", G_VEH, "Sníh – soudržnost c", 0.0, 10.0, 0.01, "kPa", ""],
	["SNOW_PHI", "snow_phi", G_VEH, "Sníh – úhel tření φ", 0.0, 45.0, 0.5, "°", ""],
	["SNOW_COMPACT", "snow_compact", G_VEH, "Sníh – slehne se nejvýš na podíl výšky", 0.0, 1.0, 0.01, "×", "Zaboření do sněhu ≤ výška sněhu × tohle."],
	["SNOW_MIN_M", "snow_min_m", G_VEH, "Sníh – počítá se od výšky", 0.0, 0.3, 0.005, "m", ""],
	["SINK_MAX_R", "sink_max_r", G_VEH, "Kolo – nejhlubší zaboření", 0.1, 2.0, 0.01, "× poloměr", "Pak sedí na podvozku."],
	["SHEAR_AREA_K", "shear_area_k", G_VEH, "Kolo – plocha smyku ×", 0.1, 5.0, 0.05, "×", "Násobí plochu stopy v A·c (tažná síla)."],
	["CART_KPA", "cart_kpa", G_VEH, "Vozík – tlak úzkého kola na zem", 20.0, 1000.0, 5.0, "kPa", ""],
	["CART_B", "cart_b", G_VEH, "Vozík – šířka kola", 0.01, 0.3, 0.005, "m", ""],
	["CART_R", "cart_r", G_VEH, "Vozík – poloměr kola", 0.05, 0.6, 0.01, "m", ""],
	["CART_SLOW_K", "cart_slow_k", G_VEH, "Vozík – zpomalení chůze × odpor", 0.0, 5.0, 0.05, "×", "Chůze × (1 − odpor/tíha × tohle)."],
	["CART_SLOW_MIN", "cart_slow_min", G_VEH, "Vozík – v blátě nejpomaleji", 0.05, 1.0, 0.01, "×", ""],
	["PROBE_DT", "probe_dt", G_FOOT, "Bláto – chodec / kůň / vozík čte půdu jednou za", 0.05, 2.0, 0.05, "s", "Throttling dotazů na Site a SoilWater."],
	["FOOT_KPA", "foot_kpa", G_FOOT, "Bláto – tlak podrážky", 5.0, 100.0, 0.5, "kPa", "~80 kg na 0,03 m²."],
	["FOOT_B", "foot_b", G_FOOT, "Bláto – šířka stopy boty", 0.03, 0.3, 0.005, "m", ""],
	["FOOT_SLOW_K", "foot_slow_k", G_FOOT, "Bláto – zpomalení × zaboření", 0.0, 20.0, 0.1, "1/m", "Rychlost × (1 − zaboření × tohle)."],
	["FOOT_SLOW_MIN", "foot_slow_min", G_FOOT, "Bláto – nejpomaleji", 0.1, 1.0, 0.01, "×", ""],
	["SQUELCH_SINK", "squelch_sink", G_FOOT, "Bláto – čvachtá od zaboření", 0.0, 0.2, 0.001, "m", "Zvuk kroku v blátě."],
	["HOOF_KPA", "hoof_kpa", G_HORSE, "Kůň – bláto: tlak kopyta", 20.0, 600.0, 5.0, "kPa", ""],
	["HOOF_B", "hoof_b", G_HORSE, "Kůň – bláto: šířka kopyta", 0.03, 0.3, 0.005, "m", ""],
	["HOOF_SLOW_K", "hoof_slow_k", G_HORSE, "Kůň – bláto: zpomalení × zaboření", 0.0, 20.0, 0.1, "1/m", ""],
	["HOOF_SLOW_MIN", "hoof_slow_min", G_HORSE, "Kůň – bláto: nejpomaleji", 0.1, 1.0, 0.01, "×", ""],
]

## Auto v blátě (`Car.TM_*`): [vlastnost, id, popisek, min, max, krok, jednotka, nápověda].
const CAR_ROWS := [
	["TM_DT", "dt", "Bláto – auto čte půdu jednou za", 0.05, 2.0, 0.05, "s", ""],
	["TM_AI_R", "ai_r", "Bláto – AI auta počítají do vzdálenosti", 0.0, 400.0, 5.0, "m", "LOD: dál od hráče bez terramechaniky."],
	["TM_SINK_RATE", "sink_rate", "Bláto – rychlost dosednutí kola do zaboření", 0.1, 30.0, 0.1, "1/s", ""],
	["TM_DIG_RATE", "dig_rate", "Bláto – vyhrabávání prokluzem", 0.0, 0.5, 0.005, "m/s", "Při plném prokluzu."],
	["TM_DIG_MAX_R", "dig_max_r", "Bláto – nejhlubší vyhrabaná díra", 0.0, 1.5, 0.01, "× poloměr", ""],
	["TM_DIG_RECOVER", "dig_recover", "Bláto – vyjetí z díry jízdou", 0.0, 1.0, 0.005, "m/m", "Kolik díry zarovná metr odvalení."],
	["TM_ROCK_K", "rock_k", "Bláto – kývání: změna směru zarovná díru", 0.0, 1.0, 0.01, "×", ""],
	["TM_SPIN_V", "spin_v", "Bláto – protáčení kola (vizuál)", 0.0, 30.0, 0.5, "m/s", ""],
	["TM_SIDE_K", "side_k", "Bláto – boční přilnavost ≤ tažná síla ×", 0.1, 3.0, 0.05, "×", ""],
	["TM_STUCK_S", "stuck_s", "Bláto – hláška „Zapadl jsi“ po", 0.5, 20.0, 0.5, "s", ""],
	["TM_STUCK_V", "stuck_v", "Bláto – „na místě“ pod rychlostí", 0.05, 3.0, 0.05, "m/s", ""],
	["TM_PUSH_N", "push_n", "Bláto – síla tlačení hráčem", 0.0, 6000.0, 50.0, "N", ""],
	["TM_PUSH_UNDIG", "push_undig", "Bláto – tlačení zarovná díru", 0.0, 0.5, 0.005, "m/s", ""],
	["TM_RUT_STEP", "rut_step", "Koleje – zápis po", 0.05, 2.0, 0.05, "m", ""],
	["TM_RUT_MIN", "rut_min", "Koleje – od zaboření", 0.0, 0.1, 0.001, "m", ""],
	["TM_RUT_K", "rut_k", "Koleje – hloubka × zaboření", 0.0, 3.0, 0.05, "×", ""],
	["TM_RUT_COMPACT", "rut_compact", "Koleje – ulehlá půda ve vyjeté koleji", 0.0, 1.0, 0.01, "×", "Zaboření − hloubka koleje × tohle."],
]

## Pneumatiky podle druhu (`Car.Tune`): [vlastnost, popisek, min, max, krok, jednotka, nápověda].
const KIND_ROWS := [
	["tm_tire_w", "šířka pneumatiky", 0.02, 0.8, 0.005, "m", "Model ji přepíše klíčem `tire_w`."],
	["tm_tire_kpa", "tlak pneumatiky na zem", 20.0, 600.0, 5.0, "kPa", "≈ huštění + tuhost kostry; model: `tire_kpa`."],
	["tm_lug", "dezén: tažná síla ×", 0.3, 4.0, 0.05, "×", "Traktor: drapáky; model: `lug`."],
]
const KINDS := [["car", "Auto"], ["tractor", "Traktor"], ["moto", "Motorka"], ["bike", "Kolo"]]

## Koleje (`RutMap`): [vlastnost, id, popisek, min, max, krok, jednotka, nápověda].
const RUT_ROWS := [
	["FADE_DRY_H", "fade_dry_h", "Koleje v blátě – mizení za sucha", 0.0, 0.02, 0.0001, "1/h", "Sucho koleje ztvrdí – zůstanou dny."],
	["FADE_RAIN_H", "fade_rain_h", "Koleje v blátě – mizení při plném dešti", 0.0, 0.3, 0.001, "1/h", ""],
	["FADE_WET_H", "fade_wet_h", "Koleje v blátě – mizení v rozmáčené půdě", 0.0, 0.1, 0.0005, "1/h", ""],
	["FADE_FROZEN", "fade_frozen", "Koleje v blátě – zamrzlá půda: mizení ×", 0.0, 1.0, 0.01, "×", ""],
	["FADE_APPLY", "fade_apply", "Koleje v blátě – mizení se zapíše pod", 0.5, 1.0, 0.005, "×", "Technicky: kdy se násobek aplikuje na obraz dlaždice."],
	["FADE_DROP", "fade_drop", "Koleje v blátě – dlaždice se smaže pod", 0.0, 0.5, 0.005, "×", ""],
	["FORGET_DAYS", "forget_days", "Koleje v blátě – zapomenout po", 1, 365, 1, "dní", ""],
	["SAVE_MAX_KB", "save_max_kb", "Koleje v blátě – strop v savu", 64, 16384, 64, "kB", ""],
	["MAX_DEPTH", "max_depth", "Koleje v blátě – nejhlubší kolej", 0.02, 1.0, 0.01, "m", ""],
	["MAX_LOADED", "max_loaded", "Koleje v blátě – dlaždic v paměti", 9, 200, 1, "", "128 kB / dlaždice."],
	["UPLOAD_S", "upload_s", "Koleje v blátě – nahrání textury nejvýš po", 0.02, 2.0, 0.01, "s", ""],
	["RUT_DARK", "dark", "Koleje v blátě – ztmavení", 0.0, 1.0, 0.01, "", "Shader terénu."],
	["RUT_NORMAL", "normal", "Koleje v blátě – svahy koleje (normála)", 0.0, 3.0, 0.05, "", ""],
	["RUT_PUDDLE", "puddle", "Koleje v blátě – louže v kolejích za mokra", 0.0, 2.0, 0.05, "", ""],
	["RUT_VIS_M", "vis_m", "Koleje v blátě – kreslit do vzdálenosti", 10.0, 400.0, 5.0, "m", ""],
]


static func register_all() -> void:
	var tabs := {"N_DRY": Terramech.N_DRY, "N_WET": Terramech.N_WET, "KC_DRY": Terramech.KC_DRY,
		"KC_WET": Terramech.KC_WET, "KPHI_DRY": Terramech.KPHI_DRY, "KPHI_WET": Terramech.KPHI_WET,
		"C_DRY": Terramech.C_DRY, "C_WET": Terramech.C_WET, "PHI_DRY": Terramech.PHI_DRY, "PHI_WET": Terramech.PHI_WET}
	for r in SOIL_ROWS:
		var arr: Array = tabs[r[0]]
		for i in SOILS.size():
			DevTune.tune(arr, i, "terramech.%s.%s" % [r[1], SOILS[i][0]], G_VEH,
				"Půda %s – %s" % [SOILS[i][1], r[2]], r[3], r[4], r[5], r[7], r[6])
	for r in TM_ROWS:
		DevTune.tune(Terramech, r[0], "terramech." + String(r[1]), r[2], r[3], r[4], r[5], r[6], r[8], r[7])
	for r in CAR_ROWS:
		DevTune.tune(Car, r[0], "car_tm." + String(r[1]), G_VEH, r[2], r[3], r[4], r[5], r[7], r[6])
	for k in KINDS:
		var t: Object = Car.TUNES[k[0]]
		for r in KIND_ROWS:
			DevTune.tune(t, r[0], "%s.%s" % [k[0], r[0]], G_VEH, "%s – %s" % [k[1], r[1]], r[2], r[3], r[4], r[6], r[5])
	for r in RUT_ROWS:
		DevTune.tune(RutMap, r[0], "ruts." + String(r[1]), G_RUTS, r[2], r[3], r[4], r[5], r[7], r[6])
