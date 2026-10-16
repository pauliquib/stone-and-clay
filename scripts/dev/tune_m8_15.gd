## M8.15 Ekologie a populace zvěře – menu pro vývojáře (F3 → Zvěř/Stanoviště, Zvěř/Populace a škody).
## Úplný seznam laditelných hodnot kroku: `Habitat` (mřížka, klid, kryt, potrava, plodiny, semenné roky, populace po druzích,
## škody, setkání, pohyb), nové konstanty `Animal` (denní cyklus podle Habitat, výška „vysoké trávy“) a `Fauna.HAB_SPAWN_SUIT`.
## Výchozí = hodnoty z kódu (chování beze změny); za snímek se registr nečte – systémy čtou své `static var` / pole.
## Statické vrstvy (stromy v buňce: TREE_R, TREES_MAX, YOUNG_AGE, DENSE_TREES) se projeví po novém startu, ostatní při
## příštím denním přepočtu (eco_day) nebo hned (dotazy zvěře).
extends RefCounted

const G_HAB := "Zvěř/Stanoviště"
const G_POP := "Zvěř/Populace a škody"
const SPN := ["srnec", "prase", "zajíc"]
const SPID := ["srnec", "prase", "zajic"]


static func _t(grp: String, target: Variant, prop: Variant, id: String, label: String, unit := "", help := "",
		lo := NAN, hi := NAN, step := NAN) -> void:
	var def: Variant = _cur(target, prop)
	if def == null:
		push_error("tune_m8_15: %s nemá %s (id %s)" % [str(target), str(prop), id])
		return
	if def is bool:
		DevTune.tune(target, prop, id, grp, label, 0.0, 1.0, 1.0, help, unit)
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
	DevTune.tune(target, prop, id, grp, label, lo, hi, step, help, unit)


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
	_mrizka()
	_kryt_potrava()
	_plodiny()
	_semenne_roky()
	_populace()
	_skody_setkani()
	_zver()


# ------------------------------------------------------------------ mřížka, klid

static func _mrizka() -> void:
	var H = Habitat
	var g := G_HAB
	_t(g, H, "STATIC_PER_FRAME", "habitat.static_per_frame", "Mřížka – statických buněk za snímek", "", "Stavba vrstev po startu (stromy v buňce).", 1.0, 200.0)
	_t(g, H, "DAY_PER_FRAME", "habitat.day_per_frame", "Mřížka – buněk denního přepočtu za snímek", "", "Výkon: víc = rychlejší přepočet, dražší snímek.", 1.0, 500.0)
	_t(g, H, "TREE_R", "habitat.tree_r", "Mřížka – stromy buňky v okruhu", "m", "Po novém startu.", 10.0, 90.0, 1.0)
	_t(g, H, "TREES_MAX", "habitat.trees_max", "Mřížka – nejvýš stromů na buňku", "", "Víc = krok přes. Po novém startu.", 10.0, 600.0)
	_t(g, H, "YOUNG_AGE", "habitat.young_age", "Kryt – mladý porost (houština) do věku", "let", "Po novém startu.", 1.0, 80.0)
	_t(g, H, "DENSE_TREES", "habitat.dense_trees", "Kryt – plně zarostlé od počtu stromů v okruhu", "", "Po novém startu.", 5.0, 150.0, 1.0)
	_t(g, H, "Q_SETTLE", "habitat.q_settle", "Klid – postih za zástavbu", "×", "Klid = 1 − zástavba × tohle − silnice × … − rušení × …")
	_t(g, H, "Q_ROAD", "habitat.q_road", "Klid – postih za silnici", "×")
	_t(g, H, "Q_DISTURB", "habitat.q_disturb", "Klid – postih za rušení (výstřely, lov)", "×")
	_t(g, H, "DISTURB_DECAY", "habitat.disturb_decay", "Klid – rušení za den ×", "", "Jak rychle zvěř zapomene na střelbu.", 0.0, 1.0)
	_t(g, H, "DISTURB_SHOT", "habitat.disturb_shot", "Klid – úlovek / výstřel přidá rušení", "", "Buňka; sousedé polovinu.", 0.0, 1.0)


# ------------------------------------------------------------------ kryt a potrava

static func _kryt_potrava() -> void:
	var H = Habitat
	var g := G_HAB
	_t(g, H, "COVER_FOREST_BASE", "habitat.cover_forest_base", "Kryt – les bez podrostu", "", "", 0.0, 1.0)
	_t(g, H, "COVER_THICKET", "habitat.cover_thicket", "Kryt – + houština × tohle", "", "Mladé porosty z TreeEco (věk).", 0.0, 1.0)
	_t(g, H, "COVER_CONIFER_WINTER", "habitat.cover_conifer_winter", "Kryt – v zimě + jehličnany × tohle", "", "", 0.0, 1.0)
	_t(g, H, "COVER_CROP_FULL_M", "habitat.cover_crop_full_m", "Kryt – porost pole plný od výšky", "m", "Výška z modelu plodin M8.12.", 0.2, 3.0)
	_t(g, H, "COVER_CROP_MAX", "habitat.cover_crop_max", "Kryt – vysoké obilí / kukuřice nejvýš", "", "", 0.0, 1.0)
	_t(g, H, "COVER_GRASS_FULL_M", "habitat.cover_grass_full_m", "Kryt – tráva louky plná od výšky", "m", "M8.14 / tabulka měsíců.", 0.1, 2.0)
	_t(g, H, "COVER_GRASS_MAX", "habitat.cover_grass_max", "Kryt – tráva louky nejvýš", "", "", 0.0, 1.0)
	_t(g, H, "SHELTER_WINTER", "habitat.shelter_winter", "Kryt – zimní váha závětří a oslunění", "", "Odpočinek × (1 − tohle + tohle × závětří).", 0.0, 1.0)
	_t(g, H, "COLD_POOL_PEN", "habitat.cold_pool_pen", "Kryt – za mrazu postih mrazové kotliny", "", "Srnci výš na svazích (inverze M8.9).", 0.0, 1.5)
	_t(g, H, "FROST_FROM_C", "habitat.frost_from_c", "Kryt – mráz od teploty", "°C", "", -20.0, 5.0, 0.5)
	_t(g, H, "EDGE_FEED_K", "habitat.edge_feed_k", "Potrava – srnec: bonus pastvy u lesa", "×", "× (1 + okraj × tohle).")
	_t(g, H, "OPEN_FEED_FOREST", "habitat.open_feed_forest", "Potrava – zajíc: × (1 − les × tohle)", "", "", 0.0, 1.0)
	for m in 12:
		_t(g, Habitat.GRASS_MONTH, m, "habitat.grass_month_%d" % (m + 1), "Potrava – pastva louky, měsíc %d" % (m + 1), "", "", 0.0, 1.0)
	_t(g, H, "BROWSE_SRNEC", "habitat.browse_srnec", "Potrava – okus houštin (srnec)", "", "", 0.0, 1.0)
	_t(g, H, "BROWSE_WINTER_K", "habitat.browse_winter_k", "Potrava – okus v zimě ×", "×")
	_t(g, H, "ROOT_BASE", "habitat.root_base", "Potrava – prase: rytí v lese (základ)", "", "", 0.0, 1.0)
	_t(g, H, "ROOT_MOIST", "habitat.root_moist", "Potrava – prase: + vlhkost půdy ×", "", "", 0.0, 1.0)
	_t(g, H, "MAST_FEED", "habitat.mast_feed", "Potrava – prase: žaludy a bukvice ×", "", "", 0.0, 2.0)
	_t(g, H, "MAST_FEED_SRNEC", "habitat.mast_feed_srnec", "Potrava – srnec: žaludy ×", "", "", 0.0, 1.0)
	_t(g, H, "ROOT_MEADOW", "habitat.root_meadow", "Potrava – prase: rytí louky u lesa ×", "", "", 0.0, 1.0)
	_t(g, H, "FEEDER_R", "habitat.feeder_r", "Potrava – krmelec v zimě přitahuje do", "m", "", 20.0, 600.0, 5.0)
	_t(g, H, "FEEDER_FEED", "habitat.feeder_feed", "Potrava – pastva u aktivního krmelce", "", "", 0.0, 1.0)
	_t(g, H, "SNOW_FOOD_M", "habitat.snow_food_m", "Potrava – sníh, pod kterým je nedostupná", "m", "", 0.05, 1.5)
	_t(g, H, "SNOW_FOOD_MIN", "habitat.snow_food_min", "Potrava – sníh ubere nejvýš 1 − tohle", "", "", 0.0, 1.0)
	_t(g, H, "WATER_R", "habitat.water_r", "Voda – dál než tolik = 0", "m", "Účel „water“ v best_nearby.", 20.0, 1500.0, 10.0)
	for m in 12:
		_t(g, Habitat.GRASS_H_MONTH, m, "habitat.grass_h_month_%d" % (m + 1), "Vysoká tráva – louka bez M8.14, měsíc %d" % (m + 1), "m", "", 0.0, 1.5)


# ------------------------------------------------------------------ plodiny (potrava na poli)

static func _plodiny() -> void:
	var g := G_HAB
	for key in Habitat.CROP_GREEN:
		var arr: Array = Habitat.CROP_GREEN[key]
		for s in 3:
			_t(g, arr, s, "habitat.crop_green.%s.%s" % [key, SPID[s]], "Pole – %s zelené: potrava (%s)" % [Fields.crop_name(key), SPN[s]], "", "", 0.0, 1.0)
	for key in Habitat.CROP_GRAIN:
		var arr: Array = Habitat.CROP_GRAIN[key]
		for s in 3:
			_t(g, arr, s, "habitat.crop_grain.%s.%s" % [key, SPID[s]], "Pole – %s v zrnu: potrava (%s)" % [Fields.crop_name(key), SPN[s]], "", "Mléčná zralost a dál.", 0.0, 1.0)
	for s in 3:
		_t(g, Habitat.STUBBLE_FOOD, s, "habitat.stubble_food.%s" % SPID[s], "Pole – strniště / po sklizni: potrava (%s)" % SPN[s], "", "", 0.0, 1.0)


# ------------------------------------------------------------------ semenné roky

static func _semenne_roky() -> void:
	var H = Habitat
	var g := G_POP
	_t(g, H, "MAST_MIN_GAP", "habitat.mast_min_gap", "Semenný rok – mezera nejméně", "let", "Deterministicky 1× za MIN … MIN + SPAN − 1 let.", 1.0, 10.0)
	_t(g, H, "MAST_GAP_SPAN", "habitat.mast_gap_span", "Semenný rok – rozptyl mezery", "let", "", 1.0, 10.0)
	_t(g, H, "MAST_POOR", "habitat.mast_poor", "Semenný rok – úroda rok po něm", "", "", 0.0, 1.0)
	_t(g, H, "MAST_NORMAL", "habitat.mast_normal", "Semenný rok – běžná úroda", "", "", 0.0, 1.0)
	_t(g, H, "MAST_JITTER", "habitat.mast_jitter", "Semenný rok – rozptyl běžné úrody ±", "", "", 0.0, 0.5)
	_t(g, H, "MAST_FROM_DOY", "habitat.mast_from_doy", "Žaludy – padají od dne roku (bez fenologie)", "den", "", 180.0, 320.0, 1.0)
	_t(g, H, "MAST_EAT_D", "habitat.mast_eat_d", "Žaludy – zásoba ubývá za den", "", "", 0.0, 0.1, 0.001)
	_t(g, H, "MAST_SPROUT_DOY", "habitat.mast_sprout_doy", "Žaludy – zbytky vyklíčí ode dne roku", "den", "", 60.0, 200.0, 1.0)


# ------------------------------------------------------------------ populace po druzích

static func _populace() -> void:
	var H = Habitat
	var g := G_POP
	for s in 3:
		var n: String = SPN[s]
		var i: String = SPID[s]
		_t(g, Habitat.DENS_MAX, s, "habitat.dens_max.%s" % i, "Populace – %s: hustota při HSI 1" % n, "ks/100 ha", "Kapacita K = Σ HSI × tohle (ověřit pro ČR).", 0.0, 150.0, 0.5)
		_t(g, Habitat.INIT_FILL, s, "habitat.init_fill.%s" % i, "Populace – %s: start (podíl K)" % n, "", "Nová hra / starý save.", 0.0, 1.5)
		_t(g, Habitat.FEMALE_SHARE, s, "habitat.female_share.%s" % i, "Populace – %s: podíl samic" % n, "", "", 0.0, 1.0)
		_t(g, Habitat.LITTER, s, "habitat.litter.%s" % i, "Populace – %s: mláďat na samici a rok" % n, "", "", 0.0, 15.0, 0.1)
		var bw: Array = Habitat.BIRTH_DOY[s]
		_t(g, bw, 0, "habitat.birth_from.%s" % i, "Populace – %s: rození od dne roku" % n, "den", "", 1.0, 365.0, 1.0)
		_t(g, bw, 1, "habitat.birth_to.%s" % i, "Populace – %s: rození do dne roku" % n, "den", "", 1.0, 365.0, 1.0)
		_t(g, Habitat.MORT_BASE, s, "habitat.mort_base.%s" % i, "Populace – %s: přirozená úmrtnost za rok" % n, "", "", 0.0, 1.0)
		_t(g, Habitat.MORT_WINTER, s, "habitat.mort_winter.%s" % i, "Populace – %s: navíc za tvrdou zimu" % n, "", "", 0.0, 1.0)
		_t(g, Habitat.CULL_QUOTA, s, "habitat.cull_quota.%s" % i, "Populace – %s: plán lovu myslivců (podíl za rok)" % n, "", "Rozložený do měsíců lovu.", 0.0, 1.5)
		_t(g, Habitat.ROAD_MORT, s, "habitat.road_mort.%s" % i, "Populace – %s: srážky s auty za rok" % n, "", "× silnice v honitbě.", 0.0, 0.5)
		_t(g, Habitat.GROUP_MEAN, s, "habitat.group_mean.%s" % i, "Setkání – %s: průměrná skupina" % n, "ks", "", 0.5, 15.0, 0.1)
		_t(g, Habitat.DENS_REF, s, "habitat.dens_ref.%s" % i, "Setkání – %s: referenční hustota (váha druhu)" % n, "ks/100 ha", "", 0.5, 60.0, 0.5)
	_t(g, H, "MAST_BIRTH_K", "habitat.mast_birth_k", "Populace – prase: vliv loňských žaludů na vrh", "", "Vrh × (1 − k + k × 2 × žaludy loni).", 0.0, 1.0)
	_t(g, H, "MORT_CROWD", "habitat.mort_crowd", "Populace – nad kapacitou úmrtnost ×", "", "(n − K) / K × tohle za rok.", 0.0, 3.0)
	_t(g, H, "FEEDER_RELIEF", "habitat.feeder_relief", "Populace – krmelec ubere zimní úmrtnost", "", "Srnec, zajíc; honitba s aktivním krmelcem.", 0.0, 1.0)
	_t(g, H, "MAST_RELIEF", "habitat.mast_relief", "Populace – žaludy uberou zimní úmrtnost prasat", "", "", 0.0, 1.0)
	_t(g, H, "WINTER_SNOW_M", "habitat.winter_snow_m", "Zima – sníh pro plnou tvrdost", "m", "Tvrdost = sníh × 0,6 + mráz × 0,4.", 0.05, 1.5)
	_t(g, H, "WINTER_COLD_C", "habitat.winter_cold_c", "Zima – mráz pro plnou tvrdost", "°C pod 0", "", 1.0, 30.0, 0.5)
	_t(g, H, "CULL_PRASE_REF", "habitat.cull_prase_ref", "Populace – prase: hustota pro běžný plán lovu", "ks/100 ha", "Víc prasat → víc nočních čekaných (0,5–2×).", 0.5, 30.0, 0.5)


# ------------------------------------------------------------------ škody, setkání, pohyb

static func _skody_setkani() -> void:
	var H = Habitat
	var g := G_POP
	_t(g, H, "ROOT_P", "habitat.root_p", "Škody – rozrytí louky u lesa (šance za den a buňku)", "", "× hustota prasat / referenční.", 0.0, 0.5, 0.001)
	_t(g, H, "ROOT_DAYS", "habitat.root_days", "Škody – rozrytá louka zaroste za", "dní", "", 1.0, 200.0)
	_t(g, H, "DAMAGE_RUMOR", "habitat.damage_rumor", "Škody – drb od počtu škod (14 dní)", "", "", 1.0, 30.0, 1.0)
	_t(g, H, "CORN_DAMAGE_K", "habitat.corn_damage_k", "Škody – kukuřice: škoda za den a buňku", "", "", 0.0, 0.2, 0.001)
	_t(g, H, "BAIT_DAMAGE", "habitat.bait_damage", "Škody – myslivci vnadí prasata od počtu škod", "", "Noční čekaná u posedu.", 1.0, 30.0, 1.0)
	_t(g, H, "RESPECT_HELP", "habitat.respect_help", "Škody – respekt zemědělců za úlovek prasete", "", "Legální, v honitbě se škodami.", 0.0, 10.0, 0.1)
	_t(g, H, "SPAWN_K", "habitat.spawn_k", "Setkání – šance skupiny = očekávané skupiny × tohle", "")
	_t(g, H, "SPAWN_P_MIN", "habitat.spawn_p_min", "Setkání – nejmenší šance", "", "", 0.0, 1.0)
	_t(g, H, "SPAWN_R", "habitat.spawn_r", "Setkání – okolí pro očekávaný počet", "m", "", 50.0, 600.0, 5.0)
	_t(g, H, "BEST_JITTER", "habitat.best_jitter", "Pohyb – náhoda při výběru cíle", "", "Ať nejdou všichni do jedné buňky.", 0.0, 1.0)
	_t(g, H, "BEST_DIST_PEN", "habitat.best_dist_pen", "Pohyb – postih vzdálenosti cíle", "", "", 0.0, 1.0)
	_t(g, H, "BEST_R_MAX", "habitat.best_r_max", "Pohyb – cíl nejdál", "m", "", 64.0, 1500.0, 16.0)
	_t(g, H, "TRAIL_ADD", "habitat.trail_add", "Ochozy – průchod přidá", "", "Spojnice lože ↔ pastva.", 0.0, 1.0)
	_t(g, H, "TRAIL_DECAY", "habitat.trail_decay", "Ochozy – za den ×", "", "", 0.0, 1.0)
	_t(g, H, "BROWSE_PRESSURE_K", "habitat.browse_pressure_k", "Okus sazenic – tlak z populace srnců ×", "", "× hustota / ref. × HSI místa.", 0.0, 2.0)


# ------------------------------------------------------------------ zvěř (Animal, Fauna)

static func _zver() -> void:
	var g := G_HAB
	_t(g, Animal, "HAB_REST_OK", "animal.hab_rest_ok", "Denní cyklus – lehne si, když je kryt aspoň", "", "Jinak jde do lepšího krytu v okrsku (Habitat).", 0.0, 1.0)
	_t(g, Animal, "HAB_FEED_OK", "animal.hab_feed_ok", "Denní cyklus – při aktivitě pastva pod tolik → jinam", "", "Soumrak: přesun na pole u lesa.", 0.0, 1.0)
	_t(g, Animal, "TALL_VEG_MIN_M", "animal.tall_veg_min_m", "Vysoká tráva – porost od výšky", "m", "Srnec v ní skáče odrazovými skoky (M8.10).", 0.1, 2.0)
	_t(g, Fauna, "HAB_SPAWN_SUIT", "fauna.hab_spawn_suit", "Setkání – nová skupina jen při vhodnosti aspoň", "", "Prvních 8 pokusů o místo.", 0.0, 1.0)
