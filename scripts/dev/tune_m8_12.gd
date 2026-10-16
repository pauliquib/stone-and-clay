## M8.12 Plodiny a zahrada podle růstového modelu – menu pro vývojáře (F3 → Příroda/Plodiny a zahrada).
## Úplný seznam laditelných hodnot kroku: `CropModel` (růst, stres, mráz, normál), `Fields` (denní krok polí, barva,
## deník), `Garden` (zálivka, kyblík záhonu, stín, odhad výnosu) a parametry každé plodiny z `data/plodiny.json`
## (cíl = slovník plodiny / pole GDD). Id `garden.*` registrovaná v `tune_priroda.gd` (M8.D2c) se tu neopakují.
## Výchozí = hodnoty z kódu / dat (chování beze změny); za snímek se registr nečte – systémy čtou své `static var`
## a slovníky, normál plodin (`CropModel.clim`) se po změně přepočítá (`on_changed` → `CropModel.invalidate`).
extends RefCounted

const GRP := "Příroda/Plodiny a zahrada"


static func _t(target: Variant, prop: Variant, id: String, label: String, unit := "", help := "",
		lo := NAN, hi := NAN, step := NAN) -> void:
	var def: Variant = _cur(target, prop)
	if def == null:
		push_error("tune_m8_12: %s nemá %s (id %s)" % [str(target), str(prop), id])
		return
	if def is bool:
		DevTune.tune(target, prop, id, GRP, label, 0.0, 1.0, 1.0, help, unit)
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
	DevTune.tune(target, prop, id, GRP, label, lo, hi, step, help, unit)


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
	_model()
	_pole()
	_zahrada()
	_plodiny()


# ------------------------------------------------------------------ CropModel (WOFOST-lite)

static func _model() -> void:
	var C = CropModel
	_t(C, "PAR_FRAC", "crop.par_frac", "Plodiny – podíl PAR v záření", "", "Fotosynteticky aktivní část globálního záření.", 0.3, 0.6)
	_t(C, "BM0_GM2", "crop.bm0_gm2", "Plodiny – biomasa při vzejití", "g/m²", "Startovní sušina (osivo / sadba).", 0.1, 20.0)
	_t(C, "LEAF_FRAC", "crop.leaf_frac", "Plodiny – podíl listů v biomase", "", "LAI = SLA × listy (do odkvětu).", 0.1, 0.9)
	_t(C, "SLA_M2_G", "crop.sla_m2_g", "Plodiny – listová plocha na gram (SLA)", "m²/g", "", 0.005, 0.05, 0.001)
	_t(C, "LAI_SENESCE_D", "crop.lai_senesce_d", "Plodiny – stárnutí listů po odkvětu", "/den", "Podíl LAI, který denně ubude.", 0.0, 0.2, 0.001)
	_t(C, "WILT_M", "crop.wilt_m", "Stres vody – bod vadnutí (vlhkost půdy)", "", "Pod touto vlhkostí (podíl AWC) růst 0.", 0.0, 0.4)
	_t(C, "DRY_FROM_M", "crop.dry_from_m", "Stres vody – sucho od vlhkosti", "", "× nárok plodiny `voda`. Zadání: 0,35.", 0.1, 0.8)
	_t(C, "WET_FROM_M", "crop.wet_from_m", "Stres vody – zamokření od vlhkosti", "", "Jen plodiny `zamok`.", 0.6, 1.0)
	_t(C, "WATERLOG_K", "crop.waterlog_k", "Stres vody – zamokření ubere růstu", "", "Při plně nasycené půdě.", 0.0, 1.0)
	_t(C, "TMAX_C", "crop.tmax_c", "Teplota – růst ustane při průměru", "°C", "Horní mez teplotního stresu.", 25.0, 50.0, 0.5)
	_t(C, "HEAT_SPAN_C", "crop.heat_span_c", "Horko – plná ztráta o tolik nad prahem", "°C", "Práh = `horko` plodiny (denní maximum).", 1.0, 15.0, 0.5)
	_t(C, "HEAT_LOSS_D", "crop.heat_loss_d", "Horko – ztráta potenciálu za den při kvetení", "/den", "", 0.0, 0.3, 0.005)
	_t(C, "FLOWER_STRESS_D", "crop.flower_stress_d", "Stres při kvetení – ztráta potenciálu za den", "/den", "Při plném stresu vody / teploty.", 0.0, 0.2, 0.005)
	_t(C, "FILL_STRESS_D", "crop.fill_stress_d", "Stres při dozrávání – ztráta potenciálu za den", "/den", "", 0.0, 0.1, 0.001)
	_t(C, "YP_MIN", "crop.yp_min", "Potenciál výnosu – nejméně", "", "", 0.0, 1.0)
	_t(C, "DROUGHT_ACCEL", "crop.drought_accel", "Sucho po odkvětu – zrychlení dozrávání", "×", "GDD × (1 + tohle × (1 − stres vody)) – v suchu se žne dřív.", 0.0, 2.0)
	_t(C, "DEAD_WS", "crop.dead_ws", "Sucho – „úplné“ pod stresem vody", "", "Dny pod tímto se počítají do `sucho_dni` plodiny (pak uschne).", 0.0, 0.5)
	_t(C, "FROST_SENSITIVE_C", "crop.frost_sensitive_c", "Mráz – citlivé plodiny (mráz ≥)", "°C", "Tyto zmrznou i přízemním mrazem (Microclimate.frost_at).", -10.0, 5.0, 0.5)
	_t(C, "FROST_KILL_AT", "crop.frost_kill_at", "Mráz – přízemní mráz zabije od", "", "Microclimate.frost_at: 0,5 ≈ tráva 0 °C, 1 ≈ −1,5 °C.", 0.0, 1.0)
	_t(C, "WA_RATE", "crop.wa_rate", "Pole – klouzavý stres vody (váha dne)", "", "Pro barvu (žloutnutí suchem).", 0.01, 1.0)
	_t(C, "CLIM_MOIST", "crop.clim_moist", "Normál – vlhkost půdy", "", "Klimatický normál, vůči kterému se měří výnos (1 = běžný rok).", 0.2, 1.0)
	_t(C, "CLIM_CLOUD", "crop.clim_cloud", "Normál – oblačnost", "", "Záření normálu (a fallback bez hodinových vzorků).", 0.0, 1.0)
	_t(C, "ANGSTROM_A", "crop.angstrom_a", "Záření – Ångström A", "", "Záření = Ra × (A + B × (1 − oblačnost)).", 0.0, 0.6)
	_t(C, "ANGSTROM_B", "crop.angstrom_b", "Záření – Ångström B", "", "", 0.0, 1.0)
	_t(C, "DAY_MIN_HOURS", "crop.day_min_hours", "Den – nejméně hodinových vzorků", "h", "Méně = den se počítá z normálu (skok času).", 1.0, 24.0, 1.0)


# ------------------------------------------------------------------ Fields (pole)

static func _pole() -> void:
	var F = Fields
	_t(F, "FIELDS_PER_FRAME", "field.eco_per_frame", "Pole – denní krok: polí za snímek", "", "255 polí po kouscích (EcoClock.slice).", 1.0, 255.0, 1.0)
	_t(F, "HARVEST_DELAY_MAX_D", "field.harvest_delay_max_d", "Pole – sklizeň nejvýš dní po dozrání", "dní", "Podle čísla pole; za deště se nežne.", 0.0, 30.0, 1.0)
	_t(F, "DRY_YELLOW_K", "field.dry_yellow_k", "Pole – žloutnutí suchem (síla)", "", "Přimíchání slámové barvy při plném stresu.", 0.0, 1.0)
	_t(F, "DRY_YELLOW_FROM", "field.dry_yellow_from", "Pole – žloutnutí od stresu vody pod", "", "", 0.0, 1.0)
	_t(F, "SHORT_MAX", "field.short_max", "Pole – zakrslé obilí nejvýš nižší o", "", "Podíl výšky (shader vegetace).", 0.0, 0.95)
	_t(F, "MOIST_DRY_MONTH", "field.moist_dry_month", "Deník úrody – suchý měsíc pod vlhkostí", "", "", 0.0, 1.0)
	_t(F, "MOIST_WET_MONTH", "field.moist_wet_month", "Deník úrody – mokrý měsíc nad vlhkostí", "", "", 0.0, 1.0)
	_t(F, "RATIO_WEAK", "field.ratio_weak", "Deník úrody – slabá pod podílem normálu", "", "", 0.0, 1.0)
	_t(F, "RATIO_RICH", "field.ratio_rich", "Deník úrody – bohatá nad podílem normálu", "", "", 1.0, 3.0)


# ------------------------------------------------------------------ Garden (zahrada, M8.12 část)

static func _zahrada() -> void:
	var G = Garden
	_t(G, "WATER_MM", "garden.water_mm", "Zálivka – vody na záhon", "mm", "1 mm na 1 m² = 1 litr.", 1.0, 60.0, 0.5)
	_t(G, "BED_AWC_MM", "garden.bed_awc_mm", "Zálivka – kyblík záhonu", "mm", "Vlastní zásoba vody záhonu navíc k půdní buňce 32 m.", 10.0, 200.0, 1.0)
	_t(G, "GH_SOIL_MOIST", "garden.gh_soil_moist", "Skleník – vlhkost půdy bez zálivky", "", "Pod sklo neprší.", 0.0, 1.0)
	_t(G, "ET_COVER_MIN", "garden.et_cover_min", "Zálivka – výpar holé půdy", "×", "Podíl Hargreavesova výparu; listy ho zvedají k 1.", 0.0, 1.0)
	_t(G, "WATER_FULL", "garden.water_full", "Zálivka – „ještě vlhká“ nad", "", "Nad touto vlhkostí záhonu zalévat nejde.", 0.3, 1.0)
	_t(G, "MOIST_VISUAL", "garden.moist_visual", "Záhon – vypadá mokrý nad", "", "Tmavší hlína; i plevel roste rychleji.", 0.0, 1.0)
	_t(G, "WILT_WS", "garden.wilt_ws", "Záhon – vadne pod stresem vody", "", "Žlutší a svěšené listy, hláška „VADNE“.", 0.0, 1.0)
	_t(G, "YIELD_NORMAL_Q", "garden.yield_normal_q", "Úroda – v normálním roce × horní mez", "", "Počet kusů = horní mez × tohle × výnos/normál × kvalita.", 0.1, 1.5)
	_t(G, "ESTIMATE_ERR", "garden.estimate_err", "Úroda – chyba odhadu bez dovednosti", "±", "× (1 − bonus Zahradničení).", 0.0, 1.0)
	_t(G, "SHADE_PLAYER_R", "garden.shade_player_r", "Stín – jen záhony u hráče do", "m", "", 50.0, 1000.0, 10.0)
	_t(G, "SHADE_TREE_R", "garden.shade_tree_r", "Stín – stromy do vzdálenosti", "m", "", 5.0, 80.0, 1.0)
	_t(G, "CROWN_H_K", "garden.crown_h_k", "Stín – střed koruny × výška stromu", "", "", 0.2, 1.0)
	_t(G, "CROWN_R_K", "garden.crown_r_k", "Stín – poloměr koruny × výška stromu", "", "", 0.05, 0.6)
	_t(G, "CROWN_OPACITY", "garden.crown_opacity", "Stín – koruna zastíní", "", "1 = úplně (bez průsvitu).", 0.0, 1.0)
	_t(G, "SHADE_RAY_M", "garden.shade_ray_m", "Stín – délka paprsku (budovy, terén)", "m", "", 5.0, 200.0, 1.0)
	var smp: Array = Garden.SHADE_SAMPLES
	var nm := ["ráno", "poledne", "odpoledne"]
	for i in smp.size():
		_t(smp[i], 0, "garden.shade_sample_%d_h" % i, "Stín – vzorek %s: hodina" % nm[i], "h", "Pravý sluneční čas.", 5.0, 20.0, 0.5)
		_t(smp[i], 1, "garden.shade_sample_%d_w" % i, "Stín – vzorek %s: váha" % nm[i], "", "", 0.0, 1.0)
	for k in Garden.CROP_ORDER:
		var c: Dictionary = Garden.CROPS[k]
		var yl: Array = c["yield"]
		_t(yl, 0, "garden.crop.%s.yield_min" % k, "Úroda %s – kusů nejméně (bez modelu)" % String(c["name"]), "ks", "Časovač (přepínač Plodiny vypnutý).", 0.0, 60.0, 1.0)
		_t(yl, 1, "garden.crop.%s.yield_max" % k, "Úroda %s – kusů horní mez" % String(c["name"]), "ks", "Model: × YIELD_NORMAL_Q × výnos/normál.", 1.0, 80.0, 1.0)


# ------------------------------------------------------------------ plodiny z data/plodiny.json

static func _plodiny() -> void:
	var specs := CropModel.specs()
	for k in specs:
		var sp: Dictionary = specs[k]
		var nm := String(sp.get("nazev", k))
		var p := "crop.%s." % k
		_t(sp, "tbase", p + "tbase", "%s – základ sum teplot" % nm, "°C", "Pod ním neroste, GDD = průměr − základ.", -5.0, 20.0, 0.5)
		_t(sp, "tcap", p + "tcap", "%s – strop průměru pro GDD" % nm, "°C", "", 10.0, 40.0, 0.5)
		var topt: Array = sp.get("topt", [])
		if topt.size() == 2:
			_t(topt, 0, p + "topt_lo", "%s – optimum teploty od" % nm, "°C", "Denní průměr.", -5.0, 35.0, 0.5)
			_t(topt, 1, p + "topt_hi", "%s – optimum teploty do" % nm, "°C", "", 0.0, 40.0, 0.5)
		var gdd: Array = sp.get("gdd", [])
		var faze := ["vzejde", "kvete", "dozrává", "zralé"]
		for i in mini(gdd.size(), 4):
			_t(gdd, i, p + "gdd_%d" % i, "%s – GDD: %s" % [nm, faze[i]], "°C·den", "Suma teplot od výsevu (kalibrace na normál a kalendář polí).", 0.0, 4000.0, 5.0)
		_t(sp, "rue", p + "rue", "%s – RUE" % nm, "g/MJ", "Sušina na MJ zachyceného PAR.", 0.5, 6.0, 0.05)
		_t(sp, "k", p + "k", "%s – extinkce porostu k" % nm, "", "Zachycené světlo = 1 − e^(−k·LAI).", 0.2, 1.2)
		_t(sp, "lai_max", p + "lai_max", "%s – LAI nejvýš" % nm, "m²/m²", "", 0.5, 10.0, 0.1)
		_t(sp, "hi", p + "hi", "%s – sklizňový index" % nm, "", "Podíl sušiny, který je úroda.", 0.05, 1.0)
		_t(sp, "mraz", p + "mraz", "%s – zmrzne pod" % nm, "°C", "Ozimy přezimují; ≥ citlivý práh = i přízemní mráz.", -30.0, 5.0, 0.5)
		_t(sp, "voda", p + "voda", "%s – nárok na vodu" % nm, "×", "× práh sucha.", 0.3, 2.0)
		_t(sp, "horko", p + "horko", "%s – horko při kvetení od" % nm, "°C", "Denní maximum.", 20.0, 45.0, 0.5)
		_t(sp, "sucho_dni", p + "sucho_dni", "%s – přežije dní úplného sucha" % nm, "dní", "", 1.0, 60.0, 1.0)
		_t(sp, "vyska", p + "vyska", "%s – výška dospělého porostu" % nm, "m", "Zvěř (crop_height_at), kryt, vzhled.", 0.05, 4.0, 0.05)
		_t(sp, "prezrale", p + "prezrale", "%s – přezraje za dní" % nm, "dní", "", 1.0, 90.0, 1.0)
		var seti: Array = sp.get("seti", [])
		if seti.size() == 2:
			_t(seti, 0, p + "seti_od", "%s – výsev od (den v roce)" % nm, "den", "Pole: výsev v rozmezí; normál: střed.", 1.0, 366.0, 1.0)
			_t(seti, 1, p + "seti_do", "%s – výsev do (den v roce)" % nm, "den", "", 1.0, 366.0, 1.0)
		if sp.has("zne_doy"):
			_t(sp, "zne_doy", p + "zne_doy", "%s – strniště v kalendáři barev od" % nm, "den", "Den kalendáře Fields.CROPS po žních.", 1.0, 366.0, 1.0)


## Změna parametru plodiny: normál (`CropModel.clim`) se přepočítá při nejbližším použití.
static func on_changed(id: String, _value: Variant) -> void:
	if id.begins_with("crop."):
		CropModel.invalidate()
