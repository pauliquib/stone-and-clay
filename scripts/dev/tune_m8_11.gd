## M8.11 Fenologie a růst – menu pro vývojáře (F3, 00_PRINCIPY kap. 10): úplný seznam laditelných konstant kroku
## (`Phenology` static var, `PlantedTrees.SOIL_WET_MIN`). Výchozí hodnoty se berou z kódu (`DevTune.tune` čte současnou
## `static var`) – chování ve výchozím stavu beze změny. Za snímek se registr nečte; změna se projeví při dalším denním kroku
## (tabulka pro shadery se přepočítá hned – `on_changed`).
extends RefCounted

const FEN := "Příroda/Fenologie"
const RUST := "Příroda/Růst stromů"

static var _g := ""


## Zaregistruje číselnou static var. Rozsah bez `lo` / `hi` = 0–3× výchozí (záporná: 3× výchozí … |výchozí|).
static func _t(target: Variant, prop: String, id: String, label: String, unit := "", help := "",
		lo := NAN, hi := NAN, step := NAN) -> void:
	var def: Variant = (target as Object).get(StringName(prop))
	if def == null:
		push_error("tune_m8_11: %s nemá %s (id %s)" % [str(target), prop, id])
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


static func register_all() -> void:
	_fenologie()
	_rust()


## Změna v F3: tabulka fází pro shadery stromů se přepočítá při nejbližší herní hodině (jinak až další den).
static func on_changed(id: String, _value: Variant) -> void:
	if id.begins_with("pheno."):
		Phenology.invalidate()


static func _fenologie() -> void:
	var P := Phenology
	_g = FEN
	_t(P, "BASE_C", "pheno.base_c", "GDD – základní teplota", "°C",
		"Suma efektivních teplot = Σ max(0, průměr dne − tohle) od 1. 1. Prahy druhů v dreviny.json jsou k 5 °C.", -5.0, 10.0, 0.5)
	_t(P, "CHILL_BELOW_C", "pheno.chill_below_c", "Zimní chlad – den pod teplotou", "°C",
		"Den s průměrem pod touto teplotou se počítá do zimního chladu (od 1. 11.).", -5.0, 10.0, 0.5)
	_t(P, "CHILL_FROM_DOY", "pheno.chill_from_doy", "Zimní chlad – od dne v roce", "den",
		"Od kterého dne v roce se sčítá zimní chlad (305 = 1. 11.).", 244.0, 366.0, 1.0)
	_t(P, "CHILL_PENALTY", "pheno.chill_penalty", "Zimní chlad – zpoždění rašení bez zimy", "×",
		"Když druh nedostal `chlad_dni` chladných dnů, práh rašení se zvýší až o tento násobek.", 0.0, 2.0, 0.05)
	_t(P, "AUT_BASE_C", "pheno.aut_base_c", "Podzim – základ chladu", "°C",
		"Podzimní chlad = Σ (tohle − průměr dne) od AUT_FROM_DOY; spouští zbarvení listí.", 5.0, 20.0, 0.5)
	_t(P, "AUT_FROM_DOY", "pheno.aut_from_doy", "Podzim – chlad od dne v roce", "den",
		"Od kterého dne se sčítá podzimní chlad (213 = 1. 8.).", 152.0, 300.0, 1.0)
	_t(P, "PHOTO_KD", "pheno.photo_kd", "Podzim – fotoperioda (krátký den)", "K·den/den",
		"Za každý den po `zbarveni_den` druhu se k chladu přičte tolik – zbarvení přijde i v teplém podzimu.", 0.0, 10.0, 0.1)
	_t(P, "AUT_SPAN_KD", "pheno.aut_span_kd", "Podzim – od začátku po plné zbarvení", "K·den",
		"Kolik podzimního chladu trvá, než je koruna plně zbarvená.", 5.0, 150.0, 1.0)
	_t(P, "FALL_FROM", "pheno.fall_from", "Podzim – opad začíná při zbarvení", "podíl",
		"Při jakém podílu zbarvení začne listí opadávat.", 0.0, 1.0, 0.05)
	_t(P, "OPAD_KD_PER_DAY", "pheno.opad_kd_per_day", "Podzim – převod dnů opadu", "K·den/den",
		"`opad_dni` druhu × tohle = podzimní chlad, za který listí opadá (typický říjnový den ~5).", 1.0, 15.0, 0.5)
	_t(P, "AUT_SHIFT_K", "pheno.aut_shift_k", "Podzim – vliv posunu místa", "×",
		"Chladné místo (kotlina) nasbírá podzimní chlad dřív – teplotní posun místa × tohle × chladné dny.", 0.0, 3.0, 0.05)
	_t(P, "SPRING_MIN_SPAN_GDD", "pheno.spring_min_span_gdd", "Jaro – nejkratší rašení", "GDD",
		"Nejmenší rozdíl GDD mezi rašením a plným olistěním.", 5.0, 200.0, 5.0)
	_t(P, "FLUSH_FADE_GDD", "pheno.flush_fade_gdd", "Jaro – přírůst jehličnanů bledne", "GDD",
		"Světlé jarní výhony smrku / borovice / jedle splynou se zelení za tolik GDD po plném olistění.", 20.0, 800.0, 10.0)
	_t(P, "BLOOM_HALF_GDD", "pheno.bloom_half_gdd", "Květ – půlšířka kvetení", "GDD",
		"Kvetení trvá ± tolik GDD kolem `kvete_gdd` druhu (v dubnu ~ týden).", 5.0, 150.0, 1.0)
	_t(P, "FROST_KILL_C", "pheno.frost_kill_c", "Mráz – práh poškození květů", "°C",
		"Od této noční teploty mráz poškozuje květy a plůdky (jabloň v plném květu ~ −2 °C).", -6.0, 2.0, 0.1)
	_t(P, "FROST_SPAN_K", "pheno.frost_span_k", "Mráz – pod prahem úplná ztráta", "K",
		"O tolik pod prahem jsou květy zničené úplně (mezi tím lineárně).", 0.5, 8.0, 0.1)
	_t(P, "FROST_FRUITLET_GDD", "pheno.frost_fruitlet_gdd", "Mráz – citlivost plůdků po odkvětu", "GDD",
		"Po odkvětu jsou plůdky citlivé ještě tolik GDD (citlivost klesá k nule).", 0.0, 300.0, 5.0)
	_t(P, "FROST_VALLEY_K", "pheno.frost_valley_k", "Mráz – bez mikroklimatu: údolí chladnější", "K",
		"S vypnutým mikroklimatem je noční minimum v nejchladnějším pásmu o tolik níž než referenční.", 0.0, 8.0, 0.1)
	_t(P, "FROST_RIDGE_K", "pheno.frost_ridge_k", "Mráz – bez mikroklimatu: svah teplejší", "K",
		"… a v nejteplejším pásmu (svah nad inverzí) o tolik výš.", 0.0, 5.0, 0.1)
	_t(P, "FROST_EVENT_MIN", "pheno.frost_event_min", "Mráz – zápis do deníku od poškození", "podíl",
		"Od jakého poškození se pozdní mráz zapíše do deníku J.", 0.0, 1.0, 0.01)
	_t(P, "SHIFT_MAX_K", "pheno.shift_max_k", "Místo – nejvyšší teplotní posun", "K",
		"Omezení teplotního posunu místa (obě strany). Shader má pásma −3…+3 K.", 0.0, 6.0, 0.1)
	_t(P, "SHIFT_SOUTH_K", "pheno.shift_south_k", "Místo – jižní svah teplejší", "K",
		"Průměr dne: plně osluněný svah (Site.insol o INSOL_SPAN nad průměrem) je o tolik teplejší.", 0.0, 4.0, 0.1)
	_t(P, "SHIFT_POOL_K", "pheno.shift_pool_k", "Místo – mrazová kotlina chladnější", "K",
		"Průměr dne: kotlina (Site.cold_pool = 1) je o tolik chladnější – raší později.", 0.0, 4.0, 0.1)
	_t(P, "YEAR_ANOMALY_K", "pheno.year_anomaly_k", "Rok – odchylka teploty dnů z klimatu", "K",
		"Přičte se k normálu u dnů, které se nesimulovaly (rozběh, dlouhý skok času). F2 → kalendář ji nastaví a rok rozběhne znovu.", -8.0, 8.0, 0.5)
	_t(P, "SAMPLES_MIN", "pheno.samples_min", "Rok – hodinových vzorků na platný den", "",
		"Méně vzorků teploty za den (skok času) = den z klimatu.", 1.0, 24.0, 1.0)
	_t(P, "BEES_MEADOW_W", "pheno.bees_meadow_w", "Včely – váha kvetení luk", "×",
		"Aktivita včel: kvetení luk (Seasons.BLOOM) × tohle + kvetoucí dřeviny × váha dřevin.", 0.0, 2.0, 0.05)
	_t(P, "BEES_TREE_W", "pheno.bees_tree_w", "Včely – váha kvetoucích dřevin", "×",
		"Kvetoucí ovocné stromy, akáty, lípy… v okolí úlu.", 0.0, 2.0, 0.05)
	_t(P, "BEES_R", "pheno.bees_r", "Včely – okruh dřevin", "m", "Dřeviny v tomto okruhu od úlu.", 20.0, 500.0, 5.0)


static func _rust() -> void:
	var P := Phenology
	_g = RUST
	_t(P, "DROUGHT_STRESS_K", "pheno.drought_stress_k", "Růst – úbytek přírůstku v suchu", "podíl",
		"Při plném letním suchu (SoilWater.drought_index = 1 od června do srpna) se roční přírůstek zmenší o tolik.", 0.0, 1.0, 0.05)
	_t(P, "FROST_STRESS_K", "pheno.frost_stress_k", "Růst – úbytek přírůstku po mrazu", "podíl",
		"Při plném poškození pozdním mrazem se roční přírůstek zmenší o tolik.", 0.0, 1.0, 0.05)
	_t(P, "GROWTH_MIN", "pheno.growth_min", "Růst – nejmenší roční přírůstek", "podíl",
		"Roční přírůstek nikdy neklesne pod tento podíl běžného.", 0.0, 1.0, 0.05)
	_t(P, "SUMMER_FROM_DOY", "pheno.summer_from_doy", "Růst – léto (sucho) od dne", "den",
		"Od kterého dne v roce se průměruje sucho pro roční přírůstek (152 = 1. 6.).", 60.0, 250.0, 1.0)
	_t(P, "SUMMER_TO_DOY", "pheno.summer_to_doy", "Růst – léto (sucho) do dne", "den",
		"Do kterého dne (243 = 31. 8.).", 120.0, 330.0, 1.0)
	_t(P, "REGROW_PER_FRAME", "pheno.regrow_per_frame", "Růst – stromů za snímek při přeškálování", "",
		"Po Novém roce / načtení se vzhled stromů zvětší po kouscích (výkon: víc = rychleji, ale delší snímek).", 10.0, 2000.0, 10.0)
	_t(PlantedTrees, "SOIL_WET_MIN", "planted.soil_wet_min", "Sazenice – vlhká půda = vláha", "podíl",
		"Zasazený strom má vodu i bez zálivky, když je vlhkost půdy (SoilWater, 0..1 vůči AWC) aspoň tolik.", 0.0, 1.0, 0.01)
