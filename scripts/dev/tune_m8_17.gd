## M8.17 Život vesnice: menu pro vývojáře (F3) – skupiny **Člověk/Život vesnice** (domácnosti, rozvrh, topení, povinnosti,
## vztahy, drby, zvuky, postavy) a **Člověk/Život vesnice – činnosti** (potřeby a činnosti z `data/potreby.json`:
## růst potřeb, okna hodin, základ užitku, násobky povahy, počasí, složení domácností, zdroje tepla, vybavení).
## Úplný seznam `static var` z `Households` + `Villager.BT_VILLAGERS`, kouř z domů (`ChimneySmoke.HOUSE_*`) a dělení
## oken na místnosti (`BuildingDetails.ROOM_SPLIT_*`). Výchozí hodnoty = kód / data (chování beze změny). Za snímek se
## registr nečte – `DevTune.tune` zapisuje přímo do `static var` / slovníků katalogu (`Households.data()`).
extends RefCounted

const SKUPINA := "Člověk/Život vesnice"
const SKUPINA_C := "Člověk/Život vesnice – činnosti"


static func register_all() -> void:
	_rows(Households, "village.", SKUPINA, [
		["INHABITED", "inhabited", "Domy – podíl obydlených rodinných domů", "×", "Zbytek domů je prázdný (tmavá okna, studený komín). Platí po novém načtení světa.", 0.0, 1.0],
		["FLAT_INHABITED", "flat_inhabited", "Domy – podíl obydlených bytů v bytovém domě", "×", "Platí po novém načtení světa.", 0.0, 1.0],
		["HOUR_SLICE", "hour_slice", "Výkon – domácností za snímek v hodinovém kroku", "ks", "Hodinový plán se rozkládá do snímků (EcoClock.slice).", 1.0, 64.0],
		["JITTER", "jitter", "Plán – náhodná složka užitku", "±×", "Deterministická (seed dům, člen, hodina) – aby se všichni nerozhodli stejně.", 0.0, 0.5],
		["DUTY_K", "duty_k", "Plán – váha povinností domu proti potřebám", "×", "Topení, dřevo, sekání, sníh, zahrada, nákup.", 0.0, 3.0],
		["NEED_MAX", "need_max", "Plán – strop potřeby", "", "Potřeba (jídlo, společnost…) neroste nad tuto hodnotu.", 0.5, 4.0],
		["WAKE_WORKER", "wake_worker", "Rozvrh – vstávání pracujícího (pracovní den)", "h", "", 3.0, 10.0],
		["WAKE_ADULT", "wake_adult", "Rozvrh – vstávání dospělého", "h", "", 3.0, 11.0],
		["WAKE_SENIOR", "wake_senior", "Rozvrh – vstávání seniora", "h", "", 3.0, 11.0],
		["WAKE_CHILD", "wake_child", "Rozvrh – vstávání dítěte", "h", "", 3.0, 11.0],
		["WAKE_JITTER", "wake_jitter", "Rozvrh – rozptyl vstávání mezi lidmi", "h", "", 0.0, 3.0],
		["WEEKEND_LATE", "weekend_late", "Rozvrh – o víkendu vstávají později o", "h", "Ulehají později o 60 % této hodnoty.", 0.0, 4.0],
		["SLEEP_ADULT", "sleep_adult", "Rozvrh – ulehání dospělého", "h", "Nad 24 = po půlnoci.", 19.0, 27.0],
		["SLEEP_SENIOR", "sleep_senior", "Rozvrh – ulehání seniora", "h", "", 18.0, 26.0],
		["SLEEP_CHILD", "sleep_child", "Rozvrh – ulehání dítěte", "h", "", 18.0, 24.0],
		["SLEEP_JITTER", "sleep_jitter", "Rozvrh – rozptyl ulehání mezi lidmi", "h", "", 0.0, 3.0],
		["NIGHT_OWL_H", "night_owl_h", "Rozvrh – povaha mladý / veselá kopa chodí spát později o", "h", "", 0.0, 4.0],
		["MORNING_KITCHEN_H", "morning_kitchen_h", "Okna – po vstávání svítí kuchyň (snídaně)", "h", "Ráno v zimě se v obci rozsvěcují kuchyně.", 0.0, 3.0],
		["BED_BEFORE_H", "bed_before_h", "Okna – před spaním svítí ložnice", "h", "", 0.0, 2.0],
		["BED_AFTER_H", "bed_after_h", "Okna – po probuzení svítí ložnice", "h", "", 0.0, 1.0],
		["COMMUTE_P", "commute_p", "Práce – dospělý bez místní práce dojíždí", "×", "Dojíždějící je v pracovní den 6:30–15:30 pryč (dům prázdný).", 0.0, 1.0],
		["LOCAL_JOB_P", "local_job_p", "Práce – neviditelný dospělý pracuje v obci", "×", "Úřad, obchod, hospoda, statek. Platí po novém načtení světa.", 0.0, 1.0],
		["HEAT_BASE_C", "heat_base_c", "Topení – venkovní teplota, pod kterou se topí", "°C", "Potřeba tepla = (základ − T u domu) / rozsah; T z Microclimate.", 5.0, 25.0],
		["HEAT_RANGE_C", "heat_range_c", "Topení – rozsah do plné potřeby tepla", "K", "", 5.0, 50.0],
		["FIRE_DECAY_H", "fire_decay_h", "Topení – pokles ohně v kamnech bez přiložení", "/h", "", 0.0, 1.0],
		["STOKE_FIRE", "stoke_fire", "Topení – síla ohně po přiložení (strop)", "×", "Ráno po vstávání a po návratu domů – silnější kouř z komína.", 0.0, 2.0],
		["STOKE_DEMAND_K", "stoke_demand_k", "Topení – přiložení × potřeba tepla", "×", "", 0.0, 4.0],
		["NIGHT_FIRE", "night_fire", "Topení – v noci kamna dohořívají (× potřeba)", "×", "", 0.0, 1.0],
		["NIGHT_KEEP_P", "night_keep_p", "Topení – podíl kamen, ve kterých se přes noc udržuje oheň", "×", "Ostatní v noci vyhasnou – ráno začne kouřit víc komínů.", 0.0, 1.0],
		["MORNING_SMOKE_H", "morning_smoke_h", "Topení – ranní zatápění (silnější kouř) trvá", "h", "", 0.0, 4.0],
		["GAS_SMOKE", "gas_smoke", "Topení – plynový kotel: vlečka × potřeba tepla", "×", "", 0.0, 1.0],
		["GAS_NIGHT_K", "gas_night_k", "Topení – útlum plynového kotle v noci", "×", "", 0.0, 1.0],
		["WOOD_BURN_H", "wood_burn_h", "Dřevo – spotřeba při plném ohni", "prms/h", "~10–14 prms za topnou sezónu.", 0.0, 0.03],
		["WOOD_START", "wood_start", "Dřevo – zásoba na začátku (při stavbě domácnosti)", "prms", "", 0.0, 30.0],
		["WOOD_TARGET", "wood_target", "Dřevo – do zimy chtějí mít naštípáno", "prms", "Pod touto zásobou od srpna do listopadu štípou (víkend víc).", 0.0, 30.0],
		["WOOD_LOW", "wood_low", "Dřevo – pod tím „nemají dřevo“ (drb, štípou i v zimě)", "prms", "", 0.0, 10.0],
		["WOOD_CHOP_H", "wood_chop_h", "Dřevo – naštípáno za hodinu", "prms/h", "", 0.0, 3.0],
		["CHOP_MAX_H_DAY", "chop_max_h_day", "Dřevo – nejvýš hodin štípání za den", "h", "", 0.0, 12.0],
		["FOOD_USE_D", "food_use_d", "Nákup – úbytek zásoby jídla za den", "/den", "× (0,5 + 0,5 × počet členů).", 0.0, 1.0],
		["FOOD_SHOP", "food_shop", "Nákup – nákup přidá zásoby", "×", "", 0.0, 1.0],
		["FOOD_LOW", "food_low", "Nákup – pod touto zásobou jdou nakoupit", "×", "", 0.0, 1.0],
		["MOW_EVERY_D", "mow_every_d", "Sekání – tráva se seká po", "dní", "", 1.0, 30.0],
		["MOW_GDD", "mow_gdd", "Sekání – tráva roste na seč od sumy teplot", "°C·den", "Phenology.gdd (základ 5 °C); bez fenologie podle měsíce.", 0.0, 600.0],
		["GARDEN_GDD", "garden_gdd", "Zahrada – práce na zahradě od sumy teplot", "°C·den", "", 0.0, 400.0],
		["RAKE_EVERY_D", "rake_every_d", "Listí – hrabe se po (říjen, listopad)", "dní", "", 1.0, 30.0],
		["SNOW_MIN", "snow_min", "Sníh – odhazuje se od pokryvu", "×", "Weather.snow_cover 1 ≈ 10 cm.", 0.0, 1.0],
		["SENIOR_SNOW_K", "senior_snow_k", "Sníh – osamělý senior se do sněhu pustí jen z", "×", "Jinak čeká na pomoc souseda (drb „pomoc_snih“).", 0.0, 1.0],
		["DUTY_SNOW", "duty_snow", "Povinnost – odhazování sněhu", "×", "", 0.0, 4.0],
		["DUTY_MOW", "duty_mow", "Povinnost – sekání trávy", "×", "", 0.0, 4.0],
		["DUTY_WOOD", "duty_wood", "Povinnost – štípání dřeva do zásoby", "×", "", 0.0, 4.0],
		["DUTY_WOOD_LOW", "duty_wood_low", "Povinnost – štípání, když dřevo dochází", "×", "", 0.0, 4.0],
		["DUTY_GARDEN", "duty_garden", "Povinnost – zahrada", "×", "", 0.0, 4.0],
		["DUTY_RAKE", "duty_rake", "Povinnost – hrabání listí", "×", "", 0.0, 4.0],
		["DUTY_SHOP", "duty_shop", "Povinnost – nákup", "×", "", 0.0, 4.0],
		["WET_MAX", "wet_max", "Sekání – nad touto mokrostí půdy se neseká ani nehrabe", "×", "Weather.wetness_ground.", 0.0, 1.0],
		["NEIGHBOURS", "neighbours", "Vztahy – počet sousedů (nejbližší domácnosti)", "ks", "Platí po novém načtení světa.", 0.0, 12.0],
		["NEIGHBOUR_R", "neighbour_r", "Vztahy – soused nejdál", "m", "Platí po novém načtení světa.", 10.0, 400.0],
		["RELATIVE_P", "relative_p", "Vztahy – domácnost má v obci příbuzné", "×", "Platí po novém načtení světa.", 0.0, 1.0],
		["REL_MIN", "rel_min", "Vztahy – počáteční vztah sousedů od", "", "Seed podle dvojice domů. Platí po novém načtení světa.", -1.0, 1.0],
		["REL_MAX", "rel_max", "Vztahy – počáteční vztah sousedů do", "", "Platí po novém načtení světa.", -1.0, 1.0],
		["REL_RELATIVE", "rel_relative", "Vztahy – vztah s příbuznými", "", "Platí po novém načtení světa.", -1.0, 1.0],
		["RIVAL_BELOW", "rival_below", "Vztahy – pod tímto vztahem rivalové (spory)", "", "", -1.0, 1.0],
		["FRIEND_ABOVE", "friend_above", "Vztahy – nad tímto vztahem pomáhají a navštěvují se", "", "", -1.0, 1.0],
		["REL_HELP", "rel_help", "Vztahy – pomoc zlepší vztah o", "", "", 0.0, 0.5],
		["REL_FIGHT", "rel_fight", "Vztahy – spor změní vztah o", "", "", -0.5, 0.0],
		["REL_VISIT", "rel_visit", "Vztahy – návštěva zlepší vztah o", "", "", 0.0, 0.3],
		["P_FIGHT_NOISE", "p_fight_noise", "Události – spor, když rival seká (za hodinu)", "×", "", 0.0, 1.0],
		["P_FIGHT_DOG", "p_fight_dog", "Události – spor kvůli psovi (za den, rivalové)", "×", "", 0.0, 0.2],
		["P_LEND", "p_lend", "Události – půjčka nářadí (za den, přátelé)", "×", "", 0.0, 0.3],
		["P_VISIT_GOSSIP", "p_visit_gossip", "Události – návštěva se stane drbem (× 0,2 za hodinu)", "×", "", 0.0, 1.0],
		["P_PUB_GOSSIP", "p_pub_gossip", "Události – pozdní hospoda (po 22 h) se stane drbem", "×", "", 0.0, 1.0],
		["P_GARDEN_GOSSIP", "p_garden_gossip", "Události – zahrada „jak ze škatulky“ (za hodinu práce)", "×", "", 0.0, 0.2],
		["P_NO_WOOD", "p_no_wood", "Události – došlé dřevo v topné sezóně se stane drbem", "×", "", 0.0, 1.0],
		["P_SNOW_HELP", "p_snow_help", "Události – soused pomůže osamělému seniorovi se sněhem (za den)", "×", "", 0.0, 1.0],
		["EVENTS_PER_DAY", "events_per_day", "Drby – nejvýš nových drbů mezi domácnostmi za den", "ks", "", 0.0, 30.0],
		["SPREAD_PUB", "spread_pub", "Drby – předání v hospodě (za hodinu)", "×", "", 0.0, 1.0],
		["SPREAD_VISIT", "spread_visit", "Drby – předání na návštěvě", "×", "", 0.0, 1.0],
		["SPREAD_STREET", "spread_street", "Drby – předání na ulici / v obchodě se sousedem", "×", "", 0.0, 1.0],
		["SPREAD_HUB", "spread_hub", "Drby – hospodský a prodavač(ka) řeknou drb z hospody", "×", "Šance pro postavy bez domácnosti (obsluha míst).", 0.0, 1.0],
		["GOSSIP_MAX", "gossip_max", "Drby – paměť (nejnovějších)", "ks", "", 1.0, 200.0],
		["GOSSIP_DAYS", "gossip_days", "Drby – zapomenou se po", "dní", "", 1.0, 90.0],
		["TELL_MIN_DAYS", "tell_min_days", "Drby – vypráví se drby staré aspoň", "dní", "0 = i dnešní.", 0.0, 7.0],
		["TELL_P", "tell_p", "Drby – šance, že vesničan řekne skutečný drb", "×", "Jinak staré obecné hlášky.", 0.0, 1.0],
		["WITNESS_R", "witness_r", "Drby – činy hráče vidí domácnosti do", "m", "Bez svědků se drb rodí v hospodě.", 0.0, 600.0],
		["SOUND_R", "sound_r", "Zvuky – štípání a sekačku je slyšet do", "m", "", 10.0, 500.0],
		["SOUND_NEAR_S", "sound_near_s", "Zvuky – obnova seznamu blízkých domů", "s", "", 0.5, 10.0],
		["CHOP_EVERY_S", "chop_every_s", "Zvuky – interval úderů sekery", "s", "", 0.3, 6.0],
		["MOW_EVERY_S", "mow_every_s", "Zvuky – interval „zabručení“ sekačky", "s", "", 0.1, 3.0],
		["CHOP_VOL", "chop_vol", "Zvuky – hlasitost štípání u zdroje", "dB", "", -30.0, 10.0],
		["MOW_VOL", "mow_vol", "Zvuky – hlasitost sekačky u zdroje", "dB", "", -30.0, 10.0],
		["SOUND_ATTEN", "sound_atten", "Zvuky – útlum se vzdáleností", "dB/m", "", 0.0, 0.5],
		["MOW_PITCH", "mow_pitch", "Zvuky – výška (ladění) zvuku sekačky", "×", "Sekačka má od M8.18 vlastní zvuk „mower“ (NatureSfx); 1 = původní výška.", 0.1, 2.0],
		["HIDE_INSIDE", "hide_inside", "Postavy – doma se schovají do domu (bez fyziky)", "", "Spánek, jídlo, odpočinek, návštěva.", 0.0, 1.0],
		["SNAP_DEEP", "snap_deep", "Postavy – za simulační bublinou se přesunou rovnou na místo", "", "", 0.0, 1.0],
		["DRESS_WARM_C", "dress_warm_c", "Postavy – pod touto teplotou větrovka", "°C", "Teplota u domu (Microclimate).", -10.0, 30.0],
		["DRESS_COLD_C", "dress_cold_c", "Postavy – pod touto teplotou bunda, čepice, rukavice", "°C", "", -20.0, 20.0],
	])
	DevTune.tune(Villager, "BT_VILLAGERS", "village.bt_villagers", SKUPINA, "Postavy – kolik prvních vesničanů řídí behavior strom",
		0.0, 28.0, 1.0, "Ostatní vede plán domácnosti. Platí po novém načtení světa (BT pro všechny až po měření ves_poledne).", "ks")
	DevTune.tune(Villager, "ENTER_NEAR_R", "village.enter_near_r", SKUPINA, "Postavy – zaseknutý u dveří blíž než tohle zajde dovnitř",
		0.0, 15.0, 0.1, "Plot nebo schod u domu nesmí vesničana nechat stát venku.", "m")
	DevTune.tune(ChimneySmoke, "HOUSE_MIN_HEAT", "village.smoke_min_heat", SKUPINA, "Komín – od této síly ohně domu kouří",
		0.0, 1.0, 0.01, "Households.chimney_heat (0 netopí … 1 přiloženo).", "×")
	DevTune.tune(ChimneySmoke, "HOUSE_HEAT_K", "village.smoke_heat_k", SKUPINA, "Komín – váha síly ohně v hustotě kouře",
		0.0, 1.0, 0.01, "0 = hustota jen podle teploty jako dřív.", "×")
	for k in 3:
		DevTune.tune(BuildingDetails.ROOM_SPLIT_1, k, "village.room_split_1.%d" % k, SKUPINA,
			"Okna – přízemní dům: mez místnosti %d (kuchyň / obývák / ložnice)" % k, 0.0, 1.0, 0.01,
			"Podíl oken (podle náhodného čísla okna) do dané místnosti; zbytek ostatní. Platí po novém načtení světa.", "×")
	for k in 2:
		DevTune.tune(BuildingDetails.ROOM_SPLIT_GROUND, k, "village.room_split_ground.%d" % k, SKUPINA,
			"Okna – přízemí patrového domu: mez místnosti %d (kuchyň / obývák)" % k, 0.0, 1.0, 0.01,
			"Zbytek ostatní. Platí po novém načtení světa.", "×")
	DevTune.tune(BuildingDetails, "ROOM_SPLIT_UPPER", "village.room_split_upper", SKUPINA, "Okna – patro: podíl ložnic",
		0.0, 1.0, 0.01, "Zbytek ostatní. Platí po novém načtení světa.", "×")
	_catalog()


## Katalog `data/potreby.json` – slovníky se ladí na místě (Households čte stejné objekty).
static func _catalog() -> void:
	var d := Households.data()
	var pot: Dictionary = d.get("potreby", {})
	for k in pot:
		if String(k).begins_with("_"):
			continue
		DevTune.tune(pot, k, "village.need.%s" % k, SKUPINA_C, "Potřeba – růst „%s“ za hodinu bdění" % k, 0.0, 0.5, 0.005,
			"0 = nikdy nenaléhá, 1 = za hodinu naléhavá.", "/h")
	var poc: Dictionary = d.get("pocasi", {})
	var poc_lab := {"dest": "déšť – násobek venkovních činností", "snezi": "sněžení – násobek", "mraz_c": "mráz – mez",
		"mraz": "mráz – násobek", "vedro_c": "vedro – mez (poledne)", "vedro": "vedro – násobek"}
	for k in poc:
		if String(k).begins_with("_"):
			continue
		var c := String(k).ends_with("_c")
		DevTune.tune(poc, k, "village.weather.%s" % k, SKUPINA_C, "Počasí – %s" % String(poc_lab.get(k, k)),
			-30.0 if c else 0.0, 40.0 if c else 1.0, 0.1 if c else 0.01, "Užitek venkovní činnosti × násobek.", "°C" if c else "×")
	var acts: Dictionary = d.get("cinnosti", {})
	for id in acts:
		if String(id).begins_with("_"):
			continue
		var a: Dictionary = acts[id]
		var nm := String(a.get("nazev", id))
		if not a.has("zaklad"):
			a["zaklad"] = 0.0
		DevTune.tune(a, "zaklad", "village.act.%s.base" % id, SKUPINA_C, "Činnost %s – základ užitku" % nm, 0.0, 3.0, 0.01,
			"Přičte se k Σ potřeba × uspokojení (práce a škola = povinnost 1,6).", "")
		var pn: Dictionary = a.get("potreby", {})
		for k in pn:
			DevTune.tune(pn, k, "village.act.%s.need.%s" % [id, k], SKUPINA_C, "Činnost %s – uspokojí „%s“" % [nm, k], 0.0, 2.0, 0.01,
				"O kolik za hodinu sníží potřebu (a tolik váží v užitku).", "")
		for w in ["hodiny", "hodiny2"]:
			var hw: Array = a.get(w, [])
			for j in hw.size():
				DevTune.tune(hw, j, "village.act.%s.%s.%d" % [id, w, j], SKUPINA_C,
					"Činnost %s – %s %s" % [nm, "okno" if w == "hodiny" else "2. okno", "od" if j == 0 else "do"], 0.0, 24.0, 0.25,
					"Mimo okno hodin má činnost užitek 0.", "h")
		var pv: Dictionary = a.get("povaha", {})
		for k in pv:
			DevTune.tune(pv, k, "village.act.%s.trait.%s" % [id, k], SKUPINA_C, "Činnost %s – povaha %s" % [nm, Characters.trait_name(k)],
				0.0, 3.0, 0.05, "Násobek užitku podle povahy.", "×")
		var dk: Dictionary = a.get("dny_k", {})
		for k in dk:
			DevTune.tune(dk, k, "village.act.%s.days.%s" % [id, k], SKUPINA_C, "Činnost %s – násobek o víkendu" % nm, 0.0, 5.0, 0.05, "", "×")
		if a.has("pes"):
			DevTune.tune(a, "pes", "village.act.%s.dog" % id, SKUPINA_C, "Činnost %s – násobek se psem" % nm, 0.0, 4.0, 0.05, "", "×")
		var mes: Dictionary = a.get("mesice", {})
		for k in mes:
			DevTune.tune(mes, k, "village.act.%s.month.%s" % [id, k], SKUPINA_C, "Činnost %s – násobek v měsíci %s" % [nm, k],
				0.0, 3.0, 0.05, "Sezóna (jaro zahrada, léto seč, podzim dřevo a listí).", "×")
	var comp: Array = d.get("slozeni", {}).get("varianty", [])
	for v in comp:
		DevTune.tune(v, 1, "village.comp.%s" % String(v[0]), SKUPINA_C, "Složení – váha „%s“" % String(v[0]), 0.0, 2.0, 0.01,
			"Domácnosti bez postav s modelem. Platí po novém načtení světa.", "")
	for sec in ["teplo", "vybava"]:
		var t: Dictionary = d.get(sec, {})
		for k in t:
			if String(k).begins_with("_"):
				continue
			DevTune.tune(t, k, "village.%s.%s" % [sec, k], SKUPINA_C, "%s – %s" % ["Zdroj tepla" if sec == "teplo" else "Vybavení", k],
				0.0, 1.5, 0.01, "Váha / pravděpodobnost při stavbě domácnosti. Platí po novém načtení světa.", "")


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
