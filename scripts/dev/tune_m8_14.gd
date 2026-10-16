## M8.14 Přízemní vegetace – menu pro vývojáře (F3). Úplný seznam laditelných hodnot kroku:
## - **Příroda/Louky a podrost**: `Meadows` (růst porostu, typy luk podle stanoviště, termíny a pravděpodobnosti seče,
##   pastva, sukcese a nálet), `Footpaths` (pěšiny – opotřebení, zarůstání, vzorkování), `GroundVegFx` (sešlapání trávy,
##   keře sukcese, seno) a `VegetationManager.REACT` (jak který typ reaguje na seč, pěšiny a sešlapání) + dosah LOD nových typů.
## - **Příroda/Vítr – ohyb vegetace**: síla ohybu stromů a trávy (dřív `const` v `shaders/include/wind.gdshaderinc`) jako
##   globální parametry shaderů `wind_k_*` – výchozí = `project.godot [shader_globals]` = původní čísla (vzhled beze změny).
## Citlivost typů na vítr `veg.bend_k.*` registruje `tune_priroda.gd` (M8.D2c, i pro nové typy) – tady se neopakuje.
## Za snímek se registr nečte: systémy čtou své `static var`; globální parametry shaderů a materiály vegetace se nastaví
## v `on_changed` (a při startu, když se hodnota z config.json / ladeni.cfg liší od kódu).
extends RefCounted

const LOUKY := "Příroda/Louky a podrost"
const VITR := "Příroda/Vítr – ohyb vegetace"

## Globální parametry shaderů ohybu: [jméno globálu, výchozí (= project.godot), popisek, nápověda, max].
const WIND_GLOBALS := [
	["wind_k_f_ref", 400.0, "Ohyb – v² pro plnou sílu", "Síla větru F = v² / tohle (400 = 20 m/s). Menší = vegetace se ohýbá víc už při slabém větru.", 1600.0],
	["wind_k_gust", 0.6, "Strom – zesílení nárazem", "Okamžitá rychlost v koruně = v · (1 + k · (2·náraz − 1)).", 2.0],
	["wind_k_trunk", 0.045, "Strom – průhyb kmene ∝ F", "Statický průhyb kmene po větru (× výška × (y/H)²).", 0.2],
	["wind_k_trunk_calm", 0.004, "Strom – pohupování kmene za klidu", "", 0.03],
	["wind_k_sway", 0.35, "Strom – kmit kolem průhybu", "Amplituda kmitu kmene vlastní frekvencí (× průhyb).", 1.5],
	["wind_k_freq", 5.0, "Strom – vlastní frekvence (Hz·m)", "f0 = k / výška (omezeno 0,12–1,5 Hz): vyšší strom kmitá pomaleji.", 15.0],
	["wind_k_side", 0.006, "Strom – příčný kmit ∝ F", "Kývání kolmo na vítr.", 0.05],
	["wind_k_side_calm", 0.0015, "Strom – příčný kmit za klidu", "", 0.01],
	["wind_k_branch", 0.12, "Větve – kmit ∝ F", "Ohebné větve (barva vrcholu r) kmitají rychleji než kmen.", 0.5],
	["wind_k_branch_calm", 0.012, "Větve – kmit za klidu", "", 0.06],
	["wind_k_leaf", 0.025, "Listy – třepetání ∝ F", "Vysokofrekvenční třepetání listů (barva vrcholu b).", 0.12],
	["wind_k_leaf_calm", 0.004, "Listy – třepetání za klidu", "", 0.03],
	["wind_k_grass", 0.55, "Tráva – ohyb ∝ F", "Ohyb stébla od kořene (× výška × citlivost typu bend_k).", 2.0],
	["wind_k_grass_calm", 0.04, "Tráva – pohupování za klidu", "", 0.2],
	["wind_k_grass_gust", 0.7, "Tráva – zesílení nárazem", "", 2.0],
	["wind_k_grass_fmax", 1.6, "Tráva – strop síly", "Silnější vítr už trávu neohne víc (F se ořízne).", 4.0],
	["wind_k_flutter0", 0.03, "Tráva – třepetání za bezvětří", "", 0.2],
	["wind_k_flutter", 0.06, "Tráva – třepetání ve větru", "", 0.3],
	["wind_k_wave_len", 7.0, "Tráva – délka vlny po větru", "Vlny („honami“) přes louku a obilí – vzdálenost hřebenů (m).", 30.0],
	["wind_k_wave_speed", 0.7, "Tráva – rychlost vlny (× vítr)", "", 2.0],
]

const TYPE_NAMES := {0: "vysoká tráva", 1: "kopřivy", 2: "líska", 3: "trnka", 4: "obilí", 5: "plevel", 6: "zahrádky",
	7: "vlhká louka", 8: "suchá stráň", 9: "kapradí", 10: "borůvčí", 11: "mech", 12: "jarní byliny", 13: "hrabanka / jehličí",
	14: "devětsil", 15: "šípek (sukcese)"}


static var _grp := LOUKY                # skupina, do které `_t` právě registruje


static func _t(target: Variant, prop: Variant, id: String, label: String, unit := "", help := "",
		lo := NAN, hi := NAN, step := NAN) -> void:
	var def: Variant = _cur(target, prop)
	if def == null:
		push_error("tune_m8_14: %s nemá %s (id %s)" % [str(target), str(prop), id])
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
	DevTune.tune(target, prop, id, _grp, label, lo, hi, step, help, unit)


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
	_grp = LOUKY
	_louky()
	_pesiny()
	_sesl()
	_reakce()
	_vitr()
	for id in ["trample.bend", "trample.agent_r", "paths.k"]:
		if DevTune.differs_from_code(id):
			on_changed(id, DevTune.value(id))


# ------------------------------------------------------------------ Meadows

static func _louky() -> void:
	var M = Meadows
	var kinds := ["mezofilní", "vlhká", "suchá stráň", "ruderální"]
	for k in 4:
		_t(Meadows.H_MAX, k, "meadows.h_max.%d" % k, "Louka – plná výška porostu: %s" % kinds[k], "m",
			"Výška neposekaného porostu v létě (logistické nasycení růstu).", 0.05, 2.0, 0.01)
	_t(M, "H_CUT", "meadows.h_cut", "Seč – výška strniště", "m", "Porost po seči / posekání kosou.", 0.0, 0.4, 0.01)
	_t(M, "H_WINTER", "meadows.h_winter", "Louka – slehlý porost v zimě", "m", "", 0.0, 0.6, 0.01)
	_t(M, "GROW_M_PER_GDD", "meadows.grow_m_per_gdd", "Louka – růst na 1 °C·den", "m/°C·d",
		"dh = k · GDD · vláha · (1 − h/H). 0,0018 ≈ za měsíc po seči zase ~0,4 m.", 0.0, 0.01, 0.0001)
	_t(M, "GDD_BASE_C", "meadows.gdd_base_c", "Louka – základ sumy teplot", "°C", "", 0.0, 12.0, 0.5)
	_t(M, "WINTER_SETTLE", "meadows.winter_settle", "Louka – slehávání mimo vegetační dobu", "/den", "", 0.0, 0.1, 0.001)
	_t(M, "SEASON_FROM_DOY", "meadows.season_from", "Louka – vegetační doba od dne", "den", "", 1, 200, 1)
	_t(M, "SEASON_TO_DOY", "meadows.season_to", "Louka – vegetační doba do dne", "den", "", 150, 365, 1)
	_t(M, "MOIST_LO", "meadows.moist_lo", "Louka – vláha, pod kterou skoro neroste", "", "Vlhkost půdy SoilWater 0..1.", 0.0, 1.0, 0.01)
	_t(M, "MOIST_HI", "meadows.moist_hi", "Louka – vláha pro plný růst", "", "", 0.0, 1.0, 0.01)
	_t(M, "MOIST_MIN_F", "meadows.moist_min_f", "Louka – růst v suchu", "×", "", 0.0, 1.0, 0.01)
	_t(M, "REGROW_TAU_D", "meadows.regrow_tau_d", "Louka – dorůstání po skoku času (časová konstanta)", "d",
		"Jen odhad po přeskoku data / dlouhém spánku (analyticky místo denních kroků).", 3.0, 120.0, 1.0)
	_t(M, "TWI_WET", "meadows.twi_wet", "Typ louky – vlhká od TWI", "", "Musí sedět s tools/vegetation.py (--eco) – vzhled typů je offline.", 4.0, 20.0, 0.1)
	_t(M, "TWI_WET_SOIL", "meadows.twi_wet_soil", "Typ louky – glej / fluvizem vlhká od TWI", "", "", 3.0, 20.0, 0.1)
	_t(M, "DIST_WATER_WET", "meadows.dist_water_wet", "Typ louky – vlhká blíž k vodě než", "m", "", 0.0, 200.0, 1.0)
	_t(M, "INSOL_DRY_Z", "meadows.insol_dry_z", "Typ louky – suchá od oslunění (z-skóre)", "σ", "", -1.0, 3.0, 0.05)
	_t(M, "SOIL_DRY_CM", "meadows.soil_dry_cm", "Typ louky – mělká půda pod", "cm", "", 0.0, 150.0, 1.0)
	_t(M, "SLOPE_DRY_DEG", "meadows.slope_dry_deg", "Typ louky – suchý svah nad", "°", "", 0.0, 45.0, 0.5)
	_t(M, "SETTLE_RUDERAL", "meadows.settle_ruderal", "Typ louky – ruderální od hustoty zástavby", "", "", 0.0, 1.0, 0.01)
	_t(M, "SETTLE_VILLAGE", "meadows.settle_village", "Seč – obecní tráva (3× ročně) od hustoty zástavby", "", "", 0.0, 1.0, 0.01)
	_t(M, "PLOT_M", "meadows.plot_m", "Seč – velikost parcely (seče se najednou)", "m", "", 16.0, 256.0, 16.0)
	_t(Meadows.CUT_HAY_DOY, 0, "meadows.cut_hay_1", "Seč – seno: 1. seč (den v roce)", "den", "166 = 15. 6.", 100.0, 250.0, 1.0)
	_t(Meadows.CUT_HAY_DOY, 1, "meadows.cut_hay_2", "Seč – seno: 2. seč (otava)", "den", "228 = 16. 8.", 150.0, 300.0, 1.0)
	for k in 3:
		_t(Meadows.CUT_VILLAGE_DOY, k, "meadows.cut_village_%d" % (k + 1), "Seč – u obce: %d. seč" % (k + 1), "den", "", 90.0, 300.0, 1.0)
	_t(Meadows.CUT_OTHER_DOY, 0, "meadows.cut_other", "Seč – ostatní tráva (meze, úhory)", "den", "", 120.0, 300.0, 1.0)
	_t(M, "CUT_SPREAD_D", "meadows.cut_spread_d", "Seč – rozptyl termínu mezi parcelami", "± dní", "", 0.0, 30.0, 0.5)
	_t(M, "CUT_LATE_D", "meadows.cut_late_d", "Seč – dohnat nejvýš dní po termínu", "dní", "", 0, 60, 1)
	_t(M, "MOW_MIN_H", "meadows.mow_min_h", "Seč – neseče se porost nižší než", "m", "", 0.0, 1.0, 0.01)
	var mg := ["seno", "u obce", "ostatní tráva"]
	for k in 3:
		_t(Meadows.P_ABANDON, k, "meadows.p_abandon.%d" % k, "Sukcese – opuštěné parcely: %s" % mg[k], "",
			"Podíl parcel, které nikdo neseče (zarůstají).", 0.0, 1.0, 0.01)
		_t(Meadows.P_MOW_YEAR, k, "meadows.p_mow_year.%d" % k, "Seč – šance seče v roce: %s" % mg[k], "", "", 0.0, 1.0, 0.01)
	_t(M, "GRAZE_H", "meadows.graze_h", "Pastva – výška porostu ve výběhu", "m", "", 0.0, 0.5, 0.01)
	_t(M, "SHRUB_YEARS", "meadows.shrub_years", "Sukcese – keře od let bez seče", "let", "", 1, 20, 1)
	_t(M, "SHRUB_FULL_YEARS", "meadows.shrub_full_years", "Sukcese – plná hustota keřů po letech", "let", "", 2, 40, 1)
	_t(M, "TREE_YEARS", "meadows.tree_years", "Sukcese – nálet stromů od let bez seče", "let", "", 1, 40, 1)
	_t(M, "P_SEEDLING", "meadows.p_seedling", "Sukcese – šance náletového stromu (buňka 16 m, rok)", "", "", 0.0, 1.0, 0.005)
	_t(M, "MAX_SEEDLINGS", "meadows.max_seedlings", "Sukcese – strop náletových stromů", "ks", "Výkon PlantedTrees (denní krok všech stromů).", 0, 3000, 10)
	_t(M, "SEEDLING_SIZE", "meadows.seedling_size", "Sukcese – velikost náletu při vzniku", "", "0,15 sazenice … 1 dospělý; nad 0,5 ho srnci neokusují.", 0.15, 1.0, 0.01)
	_t(M, "INIT_ROWS_PER_FRAME", "meadows.init_rows_per_frame", "Louky – inicializace: řádků mřížky za snímek", "", "", 1, 50, 1)
	_t(M, "CELLS_PER_FRAME", "meadows.cells_per_frame", "Louky – denní krok: buněk za snímek", "", "", 50, 5000, 50)
	_t(M, "FLOWER_MIN_REL", "meadows.flower_min_rel", "Květy – jen na louce vyšší než (podíl plné výšky)", "", "Posekaná louka nekvete.", 0.0, 1.0, 0.01)


# ------------------------------------------------------------------ Footpaths

static func _pesiny() -> void:
	var F = Footpaths
	_t(F, "WEAR_STEP", "paths.wear_step", "Pěšiny – opotřebení za krok", "", "~10 průchodů stejnou trasou = pěšina.", 0.0, 0.5, 0.005)
	_t(F, "WEAR_ANIMAL", "paths.wear_animal", "Pěšiny – zvěř a psi šlapou (×)", "×", "", 0.0, 2.0, 0.05)
	_t(F, "REGROW_DAYS", "paths.regrow_days", "Pěšiny – zarůstání (časová konstanta)", "d", "Bez chůze za ~3× tolik dní pěšina zmizí.", 0.5, 120.0, 0.5)
	_t(F, "STEP_M", "paths.step_m", "Pěšiny – vzorek trasy po", "m", "", 0.2, 5.0, 0.1)
	_t(F, "JUMP_M", "paths.jump_m", "Pěšiny – skok delší než tohle se nepíše", "m", "Teleport, spánek, hluboký spánek NPC.", 2.0, 50.0, 0.5)
	_t(F, "SAMPLE_S", "paths.sample_s", "Pěšiny – vzorkování chodců po", "s", "", 0.05, 3.0, 0.05)
	_t(F, "AGENT_R", "paths.agent_r", "Pěšiny – sledovat chodce do", "m", "", 20.0, 1000.0, 10.0)
	_t(F, "FADE_APPLY", "paths.fade_apply", "Pěšiny – zarůstání aplikovat pod násobkem", "", "Technika – jak často se přepisuje obraz dlaždice.", 0.5, 0.999, 0.005)
	_t(F, "FORGET_DAYS", "paths.forget_days", "Pěšiny – zapomenout dlaždici po dnech bez chůze", "dní", "", 5, 400, 1)
	_t(F, "MAX_TILES", "paths.max_tiles", "Pěšiny – strop dlaždic v paměti", "ks", "4 kB / dlaždice 64 × 64 m.", 50, 5000, 10)
	_t(F, "SAVE_MAX_KB", "paths.save_max_kb", "Pěšiny – strop dat v uložení", "kB", "", 32, 8192, 32)
	_t(F, "UPLOAD_S", "paths.upload_s", "Pěšiny – nahrání textury nejčastěji po", "s", "", 0.05, 5.0, 0.05)
	_t(F, "PATH_K", "paths.k", "Pěšiny – síla projevu ve shaderu", "×", "Globální path_k (terén – hlína, tráva – nižší a řidší).", 0.0, 3.0, 0.05)


# ------------------------------------------------------------------ GroundVegFx (sešlapání, keře, seno)

static func _sesl() -> void:
	var G = GroundVegFx
	_t(G, "RELAX_S", "trample.relax_s", "Sešlapání – narovnání stopy za", "s", "Síla bodu stopy klesá lineárně k nule.", 1.0, 180.0, 1.0)
	_t(G, "TRAIL_STEP_M", "trample.trail_step_m", "Sešlapání – bod stopy po", "m", "", 0.2, 5.0, 0.1)
	_t(G, "TRAIL_K", "trample.trail_k", "Sešlapání – síla stopy hned za chodcem", "×", "", 0.0, 1.0, 0.01)
	_t(G, "R_PERSON", "trample.r_person", "Sešlapání – poloměr člověka", "m", "", 0.1, 2.0, 0.05)
	_t(G, "R_ANIMAL", "trample.r_animal", "Sešlapání – poloměr psa a zvěře", "m", "", 0.1, 2.0, 0.05)
	_t(G, "R_HORSE", "trample.r_horse", "Sešlapání – poloměr koně", "m", "", 0.1, 3.0, 0.05)
	_t(G, "R_WHEEL", "trample.r_wheel", "Sešlapání – poloměr kola", "m", "", 0.1, 2.0, 0.05)
	_t(G, "WHEEL_X", "trample.wheel_x", "Sešlapání – polovina rozchodu kol", "m", "", 0.3, 2.0, 0.05)
	_t(G, "WHEEL_Z", "trample.wheel_z", "Sešlapání – polovina rozvoru kol", "m", "", 0.5, 4.0, 0.05)
	_t(G, "AGENT_R", "trample.agent_r", "Sešlapání – dosah od kamery", "m", "Zdroje dál se nesbírají a shader dál nepočítá (globální trample_range).", 5.0, 120.0, 1.0)
	_t(G, "TRAMPLE_BEND", "trample.bend", "Sešlapání – síla sklopení stébel", "×", "Globální trample_bend (úhel ∝ tlak zdrojů, strop ~77°).", 0.0, 3.0, 0.05)
	_t(G, "UPDATE_FRAMES", "trample.update_frames", "Sešlapání – textura zdrojů 1× za snímků", "", "", 1, 10, 1)
	_t(G, "AGENTS_REFRESH_S", "trample.agents_refresh_s", "Sešlapání – seznam chodců obnovit po", "s", "", 0.1, 5.0, 0.1)
	_t(G, "REBUILD_M", "groundfx.rebuild_m", "Keře a seno – přestavba po posunu hráče", "m", "", 5.0, 200.0, 1.0)
	_t(G, "SHRUB_R", "groundfx.shrub_r", "Sukcese – okruh keřů kolem hráče", "m", "", 30.0, 600.0, 10.0)
	_t(G, "SHRUBS_PER_CELL", "groundfx.shrubs_per_cell", "Sukcese – keřů na buňku 16 m (plná hustota)", "ks", "", 0.0, 20.0, 0.5)
	_t(GroundVegFx.SHRUB_SCALE, 0, "groundfx.shrub_scale_min", "Sukcese – měřítko keře min", "×", "", 0.1, 3.0, 0.05)
	_t(GroundVegFx.SHRUB_SCALE, 1, "groundfx.shrub_scale_max", "Sukcese – měřítko keře max", "×", "", 0.1, 3.0, 0.05)
	_t(G, "ROSEHIP_SHARE", "groundfx.rosehip_share", "Sukcese – podíl šípků (zbytek trnky)", "", "", 0.0, 1.0, 0.01)
	_t(G, "HAY_R", "groundfx.hay_r", "Seno – okruh kolem hráče", "m", "", 20.0, 500.0, 10.0)
	_t(G, "HAY_ROW_DAYS", "groundfx.hay_row_days", "Seno – řádky leží dní po seči", "dní", "", 0, 30, 1)
	_t(G, "HAY_BALE_DAYS", "groundfx.hay_bale_days", "Seno – balíky do dne po seči", "dní", "", 0, 90, 1)
	_t(G, "BALE_P", "groundfx.bale_p", "Seno – šance balíku na buňku 16 m", "", "", 0.0, 1.0, 0.01)


# ------------------------------------------------------------------ VegetationManager: reakce typů, dosah nových typů

static func _reakce() -> void:
	for typ in VegetationManager.REACT:
		var re: Dictionary = VegetationManager.REACT[typ]
		var nm: String = TYPE_NAMES.get(int(typ), str(typ))
		_t(re, "mow", "groundveg.mow.%d" % int(typ), "Reakce na seč – %s" % nm, "×", "1 = výška podle porostu louky (meadow_h).", 0.0, 1.0, 0.05)
		_t(re, "path", "groundveg.path.%d" % int(typ), "Reakce na pěšinu – %s" % nm, "×", "1 = na pěšině nižší a řidší.", 0.0, 2.0, 0.05)
		_t(re, "trample", "groundveg.trample.%d" % int(typ), "Citlivost na sešlapání – %s" % nm, "×", "", 0.0, 2.0, 0.05)
	for typ in VegetationManager.VEG_CONFIG:
		if int(typ) < VegetationManager.VegType.HERB_WET:
			continue                         # staré typy: dosah je technika LOD (beze změny M8.D2c)
		var cfg: Dictionary = VegetationManager.VEG_CONFIG[typ]
		_t(cfg, "view_range", "groundveg.view_range.%d" % int(typ), "Dosah LOD – %s (stavba)" % String(TYPE_NAMES.get(int(typ), str(typ))),
			"m", "Projeví se po novém načtení světa.", 10.0, 400.0, 5.0)


# ------------------------------------------------------------------ vítr – globální parametry shaderů

static func _vitr() -> void:
	for row in WIND_GLOBALS:
		var id := "windbend.%s" % String(row[0]).trim_prefix("wind_k_")
		var def := float(row[1])
		DevTune.register(id, VITR, String(row[2]), def, 0.0, float(row[4]), maxf(float(row[4]) / 400.0, 0.0001),
			String(row[3]) + " Globální parametr shaderu %s (stromy i tráva)." % String(row[0]), "")
		if DevTune.differs_from_code(id):
			on_changed(id, DevTune.value(id))


## Změna v menu F3 (registr připojí sám): globální parametry shaderů a materiály vegetace.
static func on_changed(id: String, v: Variant) -> void:
	if id.begins_with("windbend."):
		RenderingServer.global_shader_parameter_set("wind_k_" + id.trim_prefix("windbend."), float(v))
	elif id == "trample.bend":
		RenderingServer.global_shader_parameter_set("trample_bend", float(v))
	elif id == "trample.agent_r":
		RenderingServer.global_shader_parameter_set("trample_range", float(v))
	elif id == "paths.k":
		RenderingServer.global_shader_parameter_set("path_k", float(v))
	elif id.begins_with("groundveg."):
		VegetationManager.invalidate()
