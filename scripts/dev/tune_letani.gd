## M8.D2a: menu pro vývojáře – kategorie **Létání**: společný letový model (`Aircraft` static var – aerodynamika,
## řízení, auto-trim, vzlet, podvozek, přistání, nárazy, turbulence), vlastnosti strojů (`Aircraft.SPECS` – letadlo,
## paramotor, trike), paramotor (`Paramotor`), rogalo / trike (`Trike`, dráha `Airfield`), dron (`Drone`,
## `DroneModel.MODELS`) a termika (`Thermals`). Úplný seznam konstant, které ovlivňují chování (ne vizuál, zvuk, HUD).
## Výchozí hodnoty se berou z kódu (`DevTune.tune` čte současnou hodnotu) – chování ve výchozím stavu beze změny.
extends RefCounted

const SPOL := "Létání/Společné"
const LET := "Létání/Letadlo"
const PG := "Létání/Paramotor"
const TRK := "Létání/Rogalo a trike"
const DRN := "Létání/Dron"
const TER := "Létání/Termika"

## Podskupina pro vlastnosti stroje podle modelu (`Aircraft.SPECS`).
const SPEC_GROUP := {"test_letoun": LET, "paramotor": PG, "trike": TRK}

## Vlastnosti stroje (`Aircraft.SPECS[model]`, živě – `spec` stroje je stejný slovník): [klíč, popisek, min, max,
## krok, jednotka, nápověda]. Rozsah je společný pro všechny stroje (trike je těžší a rychlejší než paramotor).
const SPEC_ROWS := [
	["kg", "Hmotnost – prázdný stroj", 5.0, 600.0, 1.0, "kg", "Bez pilota a paliva (vzletová = + pilot + palivo, u triku + spolujezdec)."],
	["S", "Křídlo – plocha", 3.0, 60.0, 0.1, "m²", "Vztlak i odpor rostou s plochou."],
	["AR", "Křídlo – štíhlost (poměr stran)", 1.0, 20.0, 0.1, "", "Indukovaný odpor = CL² / (π · AR · e)."],
	["e", "Křídlo – Oswaldův součinitel", 0.3, 1.0, 0.01, "", "Účinnost rozložení vztlaku (indukovaný odpor)."],
	["CL0", "Vztlak – CL při nulovém náběhu", 0.0, 1.5, 0.01, "", "Součinitel vztlaku profilu při α = 0."],
	["CL_A", "Vztlak – sklon křivky CL(α)", 0.5, 8.0, 0.05, "1/rad", "CL = CL0 + tohle · α (do kritického náběhu)."],
	["a_crit", "Vztlak – kritický náběh (přetažení)", 5.0, 35.0, 0.5, "°", "Nad tímto náběhem křídlo přetáhne."],
	["CD0", "Odpor – škodlivý odpor CD0", 0.0, 0.2, 0.001, "", "Odpor bez vztlaku (kalibrovaný na klouzavost stroje)."],
	["thrust", "Motor – statický tah", 0.0, 4000.0, 10.0, "N", "Tah na plný plyn ve stání (s rychlostí klesá)."],
	["v_min", "Rychlost – pádová (v_min)", 2.0, 40.0, 0.1, "m/s", "Rotace a odlepení se odvozují od ní, pod ní nos padá."],
	["v_trim", "Rychlost – cestovní (auto-trim)", 3.0, 60.0, 0.1, "m/s", "Rychlost, kterou auto-trim drží (bez motoru klouže, s plynem stoupá)."],
	["v_max", "Rychlost – maximální (tah k ní klesá)", 5.0, 80.0, 0.1, "m/s", "Tah = T0 · plyn · (1 − pokles · (v / v_max)²)."],
	["tank_l", "Palivo – nádrž", 1.0, 150.0, 0.5, "l", "Spotřeba = nádrž / výdrž; nová plná nádrž až u nového stroje."],
	["dojezd_min", "Palivo – výdrž na plný plyn", 5.0, 600.0, 1.0, "min", "Za kolik minut plného plynu se vyprázdní plná nádrž."],
	["gear_h", "Podvozek – výška počátku nad zemí", 0.2, 2.0, 0.01, "m", "Výška tělesa nad zemí (kola / nohy). Kolizní kvádr se posune až u nového stroje."],
	["roll_max", "Řízení – největší náklon", 0.1, 1.2, 0.01, "rad", "Náklon při plném A/D (zatáčka = g · tan φ / v)."],
]

## Společný letový model (`Aircraft` static var – platí pro letadlo, paramotor i trike):
## [vlastnost, id, popisek, min, max, krok, jednotka, nápověda].
const AIR_ROWS := [
	# vzduch a aerodynamika
	["RHO", "rho", "Vzduch – hustota", 0.5, 2.0, 0.005, "kg/m³", "Vztlak i odpor ∝ hustota (1,225 = hladina moře, 15 °C)."],
	["G", "g", "Vzduch – tíhové zrychlení letových strojů", 1.0, 30.0, 0.01, "m/s²", "Vlastní gravitace letového modelu (nezávislá na gravitaci světa)."],
	["CL_STALL", "cl_stall", "Vztlak – po přetažení (podíl CL_max)", 0.0, 1.0, 0.01, "×", ""],
	["NEG_A_CL", "neg_a_cl", "Vztlak – nejmenší CL při záporném náběhu", -1.0, 0.5, 0.01, "", "Spodní mez CL (záchrana padáku)."],
	["CL_MAX_ABS", "cl_max_abs", "Vztlak – strop CL ve vzduchu", 0.5, 6.0, 0.05, "", ""],
	["STALL_RECOVER_K", "stall_recover_k", "Přetažení – zotavení pod podílem a_crit", 0.1, 1.0, 0.01, "×", "Hystereze: přetažení končí pod tímto náběhem."],
	["STALL_NOSE_DROP", "stall_nose_drop", "Přetažení – nos padá pod dráhu o", 0.0, 0.5, 0.005, "rad", "Při přetažení a pod v_min."],
	["THRUST_DROP", "thrust_drop", "Motor – pokles tahu s rychlostí", 0.0, 1.5, 0.01, "", "Tah · (1 − tohle · (v / v_max)²)."],
	["THRUST_MIN", "thrust_min", "Motor – nejmenší podíl tahu", 0.0, 1.0, 0.01, "×", "Spodní mez poměru tahu (nad v_max)."],
	["THR_RESP", "thr_resp", "Motor – odezva tahu na plyn", 0.2, 20.0, 0.1, "1/s", "Jak rychle tah sleduje páku / klávesu."],
	["THR_BRAKE_CUT", "thr_brake_cut", "Motor – S ubírá plyn (letadlo)", 0.0, 1.0, 0.01, "×", ""],
	# řízení
	["ROLL_RATE", "roll_rate", "Řízení – rychlost náklonu", 0.1, 8.0, 0.05, "rad/s", "Jak rychle stroj dosáhne cílového náklonu."],
	["PITCH_RATE", "pitch_rate", "Řízení – rychlost klopení", 0.1, 6.0, 0.05, "rad/s", ""],
	["BANK_YAW_MAX", "bank_yaw_max", "Řízení – strop náklonu pro zatáčení", 0.1, 1.5, 0.01, "rad", "Zatáčka = g · tan(min(φ, tohle)) / v."],
	["PITCH_MIN", "pitch_min", "Řízení – nejnižší sklon nosu", -1.5, 0.0, 0.01, "rad", ""],
	["PITCH_MAX", "pitch_max", "Řízení – nejvyšší sklon nosu", 0.0, 1.5, 0.01, "rad", ""],
	["ELEV_PITCH", "elev_pitch", "Řízení – výchylka výškovkou", 0.0, 0.6, 0.005, "rad", "Mezerník / Ctrl (u triku W / S) přidá ke sklonu nosu."],
	# auto-trim
	["TRIM_ELEV_V", "trim_elev_v", "Auto-trim – výškovka posune cílovou rychlost o", 0.0, 0.9, 0.01, "× v_trim", ""],
	["TRIM_W", "trim_w", "Auto-trim – vlastní frekvence držáku rychlosti", 0.05, 2.0, 0.01, "rad/s", "Víc = rychlejší návrat k v_trim (houpání)."],
	["TRIM_ZETA", "trim_zeta", "Auto-trim – tlumení", 0.0, 3.0, 0.01, "", "1 = kriticky tlumené, méně = fugoidní houpání."],
	["TRIM_ALPHA_MIN", "trim_alpha_min", "Auto-trim – nejmenší náběh", -0.5, 0.0, 0.005, "rad", ""],
	["TRIM_BANK_COS_MIN", "trim_bank_cos_min", "Auto-trim – strop přídavku vztlaku v zatáčce", 0.1, 1.0, 0.01, "cos φ", "Vztlak / cos φ, nejvýš / tohle."],
	# vzlet
	["ROT_ALPHA_K", "rot_alpha_k", "Vzlet – náběh při rotaci (podíl a_crit)", 0.1, 1.0, 0.01, "×", "Zároveň strop náběhu auto-trimu."],
	["ROT_V_K", "rot_v_k", "Vzlet – rotace od podílu v_min", 0.3, 1.5, 0.01, "× v_min", ""],
	["LIFTOFF_V_K", "liftoff_v_k", "Vzlet – odlepení od podílu v_min", 0.3, 1.5, 0.01, "× v_min", "Navíc musí vztlak převážit tíhu."],
	["LIFTOFF_MIN_GS", "liftoff_min_gs", "Vzlet – odlepení až od pojezdové rychlosti", 0.0, 10.0, 0.1, "m/s", ""],
	["LIFTOFF_VY", "liftoff_vy", "Vzlet – svislá rychlost při odlepení", 0.0, 2.0, 0.01, "m/s", ""],
	# podvozek a pojíždění
	["MU_GRASS", "mu_grass", "Podvozek – valivý odpor na trávě", 0.0, 0.3, 0.001, "µ", "Letadlo a běh paramotoru (trike má vlastní)."],
	["MU_WET_K", "mu_wet_k", "Podvozek – mokrá tráva: odpor ×", 1.0, 3.0, 0.01, "×", ""],
	["MU_WET_GRIP", "mu_wet_grip", "Podvozek – mokro, když přilnavost terénu klesne pod", 0.0, 1.0, 0.01, "", ""],
	["BRAKE_DECEL", "brake_decel", "Podvozek – brzda kol (Mezerník)", 0.0, 12.0, 0.1, "m/s²", "Paramotor při běhu: × podíl brzdy běhu."],
	["GROUND_STEER", "ground_steer", "Podvozek – zatáčení na zemi", 0.0, 3.0, 0.01, "rad/s", "Příďové kolo / běh při plné rychlosti řízení."],
	["GROUND_STEER_V", "ground_steer_v", "Podvozek – plné zatáčení od rychlosti", 0.5, 20.0, 0.1, "m/s", ""],
	["GROUND_BANK", "ground_bank", "Podvozek – náklon při řízení na zemi", 0.0, 0.3, 0.005, "rad", ""],
	["GROUND_ATT_RATE", "ground_att_rate", "Podvozek – srovnání sklonu a náklonu na zemi", 0.2, 15.0, 0.1, "1/s", ""],
	["GROUND_SLOPE_MAX", "ground_slope_max", "Podvozek – strop sklonu terénu", 0.05, 1.0, 0.01, "tan", "Pro náběh a sklon stroje na zemi."],
	["GROUND_SLOPE_K", "ground_slope_k", "Podvozek – vliv sklonu na rozjezd", 0.0, 1.5, 0.01, "× g", "Rozjezd do kopce / z kopce."],
	# přistání
	["LAND_GRACE", "land_grace", "Přistání – po odlepení se dosednutí nepočítá", 0.0, 3.0, 0.05, "s", "Hystereze proti poskakování."],
	["LAND_VY", "land_vy", "Přistání – dosednutí jen při klesání rychleji než", -2.0, 0.0, 0.01, "m/s", "Vůči terénu (záporné = klesá)."],
	["LAND_GAP", "land_gap", "Přistání – dosednutí až pod výškou podvozku minus", 0.0, 0.5, 0.005, "m", ""],
	["HARD_LAND_VY", "hard_land_vy", "Přistání – tvrdé od klesání", 0.5, 10.0, 0.1, "m/s", "Poškození a zranění (paramotor s flarem ne)."],
	["CRASH_LAND_VY", "crash_land_vy", "Přistání – havárie od klesání", 1.0, 25.0, 0.1, "m/s", ""],
	["HARD_DMG_K", "hard_dmg_k", "Přistání – poškození na 1 m/s nad tvrdým", 0.0, 50.0, 0.5, "%", ""],
	["HARD_HURT_K", "hard_hurt_k", "Přistání – zranění na 1 m/s nad tvrdým", 0.0, 40.0, 0.5, "", ""],
	# nárazy a vrak
	["CRASH_SPD", "crash_spd", "Nárazy – havárie o překážku od rychlosti", 1.0, 30.0, 0.1, "m/s", "Strom, budova, prop, postava."],
	["BUMP_MIN_V", "bump_min_v", "Nárazy – dotek překážky se počítá od", 0.0, 10.0, 0.1, "m/s", ""],
	["BUMP_DMG_K", "bump_dmg_k", "Nárazy – poškození šrámem na 1 m/s", 0.0, 10.0, 0.1, "%", ""],
	["CRASH_HURT", "crash_hurt", "Nárazy – zranění pilota při havárii", 0.0, 100.0, 1.0, "", ""],
	["CRASH_SLIDE_K", "crash_slide_k", "Nárazy – vrak dojíždí s podílem rychlosti", 0.0, 1.0, 0.01, "×", "Po havárii při přistání."],
	["WRECK_FRICTION", "wreck_friction", "Nárazy – útlum dojezdu vraku po zemi", 0.0, 15.0, 0.1, "1/s", ""],
	# turbulence a vítr
	["TURB_BASE", "turb_base", "Turbulence – základ", 0.0, 2.0, 0.01, "m/s", "Přičítá se k větru (šum)."],
	["TURB_STORM", "turb_storm", "Turbulence – bouřka (× síla bouřky)", 0.0, 8.0, 0.05, "m/s", ""],
	["TURB_FOREST", "turb_forest", "Turbulence – nad lesem (× hustota lesa)", 0.0, 3.0, 0.01, "m/s", ""],
	["TURB_LEE", "turb_lee", "Turbulence – závětří kopce (× převýšení / vzdálenost)", 0.0, 40.0, 0.5, "m/s", ""],
	["TURB_LEE_DIST", "turb_lee_dist", "Turbulence – závětří: převýšení se měří proti větru na", 10.0, 300.0, 1.0, "m", ""],
	["TURB_LEE_AGL", "turb_lee_agl", "Turbulence – závětří působí jen pod výškou", 10.0, 800.0, 5.0, "m AGL", ""],
	["TURB_LEE_WIND", "turb_lee_wind", "Turbulence – závětří naplno od větru", 0.5, 20.0, 0.1, "m/s", ""],
	["TURB_XZ", "turb_xz", "Turbulence – velikost vírů vodorovně (frekvence)", 0.005, 0.3, 0.005, "1/m", "Víc = drobnější víry."],
	["TURB_Y", "turb_y", "Turbulence – velikost vírů svisle (frekvence)", 0.005, 0.5, 0.005, "1/m", ""],
	["TURB_T", "turb_t", "Turbulence – rychlost změn v čase", 0.0, 5.0, 0.05, "×", ""],
	["WIND_PROFILE_EXP", "wind_profile_exp", "Vítr – výškový profil (exponent, jen bez pole větru)", 0.0, 0.5, 0.005, "", "v(h) = v10 · (h / 10)^tohle; s M8.4 WindField se neuplatní."],
	# hmotnost
	["PILOT_KG", "pilot_kg", "Hmotnost – pilot", 30.0, 200.0, 0.5, "kg", ""],
	["FUEL_KG_L", "fuel_kg_l", "Hmotnost – hustota paliva", 0.5, 1.0, 0.01, "kg/l", ""],
	# opilost, pravidla
	["DRUNK_DELAY", "drunk_delay", "Opilý pilot – zpoždění vstupu na 1 ‰", 0.0, 0.5, 0.005, "s", ""],
	["DRUNK_DELAY_MAX", "drunk_delay_max", "Opilý pilot – zpoždění vstupu nejvýš", 0.0, 2.0, 0.01, "s", ""],
	["LAW_TICK", "law_tick", "Pravidla – kontrola létání pod vlivem každých", 0.5, 20.0, 0.1, "s", ""],
	["OFF_CD", "off_cd", "Pravidla – stejný přestupek znovu nejdřív po", 5.0, 600.0, 1.0, "s", "Paramotor a trike: × 1,5."],
	["XP_PER_M", "xp_per_m", "Dovednost – XP letectví za metr letu", 0.0, 0.2, 0.001, "XP/m", ""],
]

## Paramotor (`Paramotor` static var): [vlastnost, id, popisek, min, max, krok, jednotka, nápověda].
const PG_ROWS := [
	["RUN_ACC", "run_acc", "Rozběh – zrychlení nohama", 0.5, 12.0, 0.1, "m/s²", "W na zemi."],
	["RUN_MAX_V", "run_max_v", "Rozběh – nejvyšší rychlost běhu", 1.0, 15.0, 0.1, "m/s", ""],
	["RUN_BRAKE_K", "run_brake_k", "Rozběh – brzdění (podíl brzdy kol letounu)", 0.0, 2.0, 0.01, "×", "Mezerník při běhu."],
	["RUN_MIN_V", "run_min_v", "Nahození – potřebný čelní proud", 0.5, 12.0, 0.1, "m/s", "Rozběh + protivítr."],
	["INFLATE_T", "inflate_t", "Nahození – doba zvedání křídla", 0.2, 6.0, 0.05, "s", ""],
	["DEFLATE_K", "deflate_k", "Nahození – křídlo padá rychleji než stoupá", 0.1, 5.0, 0.05, "×", ""],
	["CROSS_MAX", "cross_max", "Nahození – největší boční vítr", 0.0, 10.0, 0.1, "m/s", ""],
	["WIND_SAFE", "wind_safe", "Nahození – silnější vítr křídlo vytrhne", 1.0, 25.0, 0.1, "m/s", ""],
	["FUMBLE_LOCK", "fumble_lock", "Nahození – po vytržení se sbíráš", 0.0, 6.0, 0.05, "s", ""],
	["FUMBLE_DMG", "fumble_dmg", "Nahození – poškození při vytržení", 0.0, 30.0, 0.5, "%", ""],
	["FUMBLE_HURT", "fumble_hurt", "Nahození – zranění při vytržení", 0.0, 40.0, 0.5, "", ""],
	["BRAKE_CD", "brake_cd", "Brzdy – odpor obou brzd naplno (S)", 0.0, 1.5, 0.01, "CD", ""],
	["SIDE_BRAKE_CD", "side_brake_cd", "Brzdy – odpor jednostranné brzdy (A/D)", 0.0, 0.6, 0.005, "CD", ""],
	["BRAKE_ELEV", "brake_elev", "Brzdy – obě brzdy zvedají nos", 0.0, 1.5, 0.01, "×", "Podíl zatažení výškovkou."],
	["BRAKE_THR_CUT", "brake_thr_cut", "Brzdy – obě brzdy ubírají plyn", 0.0, 1.0, 0.01, "×", ""],
	["DEEP_BRAKE", "deep_brake", "Brzdy – hluboký tah (propad) od", 0.3, 1.0, 0.01, "", ""],
	["SINK_STALL_T", "sink_stall_t", "Brzdy – hluboký tah do propadu po", 0.1, 3.0, 0.05, "s", ""],
	["EARS_CD", "ears_cd", "Uši – přídavný odpor (Ctrl)", 0.0, 1.0, 0.01, "CD", "Rychlejší klesání."],
	["TRIM_V", "trim_v", "Trimry – bonus k v_max", 0.0, 5.0, 0.05, "m/s", "Mezerník (povolené trimry)."],
	["TRIMS_RATE", "trims_rate", "Trimry – rychlost povolení / dotažení", 0.1, 5.0, 0.05, "1/s", ""],
	["COLLAPSE_TURB", "collapse_turb", "Zavření křídla – od turbulence", 0.0, 5.0, 0.05, "m/s", ""],
	["COLLAPSE_P", "collapse_p", "Zavření křídla – šance za s (× přebytek turbulence)", 0.0, 0.5, 0.005, "1/s", ""],
	["COLLAPSE_MIN", "collapse_min", "Zavření křídla – nejkratší", 0.1, 10.0, 0.1, "s", ""],
	["COLLAPSE_MAX", "collapse_max", "Zavření křídla – nejdelší", 0.1, 15.0, 0.1, "s", ""],
	["COLLAPSE_LIFT", "collapse_lift", "Zavření křídla – zbývající vztlak", 0.0, 1.0, 0.01, "×", ""],
	["COLLAPSE_BANK", "collapse_bank", "Zavření křídla – propad na stranu", 0.0, 1.5, 0.01, "rad", ""],
	["RECOVER_K", "recover_k", "Zavření křídla – zotavení opačnou brzdou", 0.0, 10.0, 0.1, "×", ""],
	["FLARE_AGL", "flare_agl", "Flare – okno nad zemí", 0.2, 5.0, 0.05, "m", "Obě brzdy v tomto okně = měkké dosednutí."],
	["FLARE_BRAKE", "flare_brake", "Flare – potřebný tah obou brzd", 0.1, 1.0, 0.01, "", ""],
	["FLARE_HARD_V", "flare_hard_v", "Flare – tvrdé doskočení od klesání", 0.5, 8.0, 0.05, "m/s", ""],
	["FLARE_HURT_K", "flare_hurt_k", "Flare – zranění na 1 m/s nad tvrdým", 0.0, 40.0, 0.5, "", ""],
	["PG_LAW_TICK", "law_tick", "Pravidla – kontrola přestupků každých", 0.5, 30.0, 0.5, "s", ""],
	["PG_LOW_ALT", "low_alt", "Pravidla – minimum nad obcí", 0.0, 600.0, 5.0, "m AGL", ""],
	["PG_PERSON_R", "person_r", "Pravidla – nad lidmi do vzdálenosti", 0.0, 150.0, 1.0, "m", ""],
]

## Rogalo / trike (`Trike` static var; dráha `Airfield`): [cíl, vlastnost, id, popisek, min, max, krok, jednotka, nápověda].
const TRK_ROWS := [
	["trike", "THR_RATE", "trike.thr_rate", "Motor – rychlost pojezdu páky plynu", 0.05, 3.0, 0.01, "1/s", "Shift / Ctrl (páka drží polohu)."],
	["trike", "MU_TRIKE", "trike.mu_grass", "Podvozek – valivý odpor tříkolky na trávě", 0.0, 0.3, 0.001, "µ", ""],
	["trike", "PAX_KG", "trike.pax_kg", "Hmotnost – spolujezdec", 0.0, 200.0, 0.5, "kg", ""],
	["trike", "UL_LAW_TICK", "trike.law_tick", "Pravidla – kontrola přestupků každých", 0.5, 30.0, 0.5, "s", ""],
	["trike", "UL_LOW_ALT", "trike.low_alt", "Pravidla – minimum nad obcí", 0.0, 600.0, 5.0, "m AGL", ""],
	["trike", "UL_PERSON_R", "trike.person_r", "Pravidla – nad lidmi do vzdálenosti", 0.0, 150.0, 1.0, "m", ""],
	["airfield", "RWY_HALF", "airfield.rwy_half", "Letiště – přistání na dráze do vzdálenosti od osy", 2.0, 60.0, 0.5, "m", "Mimo = přestupek „přistání mimo letiště“."],
]

## Dron (`Drone` static var): [vlastnost, id, popisek, min, max, krok, jednotka, nápověda].
const DRN_ROWS := [
	# let a odezva
	["ACCEL", "accel", "Let – odezva vrtulí (zrychlení)", 1.0, 60.0, 0.5, "m/s²", "Jak rychle dron dosáhne cílové rychlosti."],
	["ACCEL_RTH", "accel_rth", "Let – odezva při návratu domů", 1.0, 40.0, 0.5, "m/s²", ""],
	["STICK_YAW_RATE", "stick_yaw_rate", "Ovládání – otáčení páčkou ovladače", 0.2, 8.0, 0.05, "rad/s", ""],
	["STICK_PITCH_RATE", "stick_pitch_rate", "Ovládání – naklápění kamery páčkou", 0.2, 6.0, 0.05, "rad/s", ""],
	["DMG_SINK", "dmg_sink", "Let – poškozený klesá (na 1 %)", 0.0, 0.03, 0.0005, "m/s", ""],
	["MAX_ALT", "max_alt", "Let – strop (a přestupek nad)", 10.0, 500.0, 1.0, "m AGL", "Stoupání nad strop se odepře."],
	# vítr
	["WIND_FLY_K", "wind_fly_k", "Vítr – unášení v letu", 0.0, 2.0, 0.01, "× wind_k", ""],
	["WIND_START_K", "wind_start_k", "Vítr – unášení při vzletu", 0.0, 2.0, 0.01, "× wind_k", ""],
	["WIND_RTH_K", "wind_rth_k", "Vítr – unášení při návratu", 0.0, 2.0, 0.01, "× wind_k", ""],
	["WIND_LAND_K", "wind_land_k", "Vítr – unášení při přistání", 0.0, 2.0, 0.01, "× wind_k", ""],
	["GUST_K", "gust_k", "Vítr – nárazy kolem středního driftu", 0.0, 1.5, 0.01, "× wind_k", ""],
	["GUST_STEP", "gust_step", "Vítr – rychlost střídání nárazů", 0.0, 0.1, 0.001, "/krok", "Posun fáze nárazů za fyzikální krok."],
	# vzlet, návrat, přistání
	["TAKEOFF_H", "takeoff_h", "Vzlet – výška automatického vzletu", 0.5, 10.0, 0.1, "m", ""],
	["TAKEOFF_GAIN", "takeoff_gain", "Vzlet – stoupání × chybějící výška", 0.2, 10.0, 0.1, "1/s", ""],
	["TAKEOFF_VMAX", "takeoff_vmax", "Vzlet – nejrychlejší stoupání", 0.2, 8.0, 0.1, "m/s", ""],
	["RTH_ALT", "rth_alt", "Návrat – cestovní výška nad bodem vzletu", 2.0, 120.0, 0.5, "m", ""],
	["RTH_SPD_K", "rth_spd_k", "Návrat – podíl běžné rychlosti", 0.1, 1.5, 0.01, "×", ""],
	["RTH_VGAIN", "rth_vgain", "Návrat – srovnání výšky × odchylka", 0.1, 3.0, 0.05, "1/s", ""],
	["RTH_DESC_MAX", "rth_desc_max", "Návrat – nejrychlejší klesání na cestovní výšku", 0.2, 6.0, 0.1, "m/s", ""],
	["RTH_CLIMB_K", "rth_climb_k", "Návrat – podíl běžného stoupání", 0.1, 1.5, 0.01, "×", ""],
	["RTH_HOME_R", "rth_home_r", "Návrat – nad domovem začne klesat do", 0.5, 15.0, 0.1, "m", ""],
	["RTH_LAND_VS", "rth_land_vs", "Návrat – klesání nad domovem", 0.2, 6.0, 0.1, "m/s", ""],
	["LAND_AGL", "land_agl", "Přistání – dosednutí pod výškou", 0.05, 1.0, 0.01, "m", ""],
	["LAND_DESC_K", "land_desc_k", "Přistání – klesání × výška", 0.1, 3.0, 0.05, "1/s", ""],
	["LAND_VS_MIN", "land_vs_min", "Přistání – nejpomalejší klesání", 0.1, 3.0, 0.05, "m/s", ""],
	["LAND_VS_MAX", "land_vs_max", "Přistání – nejrychlejší klesání", 0.5, 15.0, 0.1, "m/s", ""],
	["LAND_NEAR_M", "land_near_m", "Přistání – F u pilota přistane do vzdálenosti", 0.5, 15.0, 0.1, "m", "Dál = návrat domů."],
	["PICKUP_R", "pickup_r", "Přistání – pilot blíž = rovnou do batohu", 0.0, 10.0, 0.1, "m", ""],
	# baterie a signál
	["BAT_WARN", "bat_warn", "Baterie – varování od", 0.0, 0.5, 0.01, "×", ""],
	["BAT_RTH", "bat_rth", "Baterie – automatický návrat od", 0.0, 0.3, 0.005, "×", ""],
	["DRAIN_SPORT", "drain_sport", "Baterie – spotřeba ve sportovním režimu", 1.0, 3.0, 0.01, "×", ""],
	["DRAIN_COLD", "drain_cold", "Baterie – spotřeba v mrazu", 1.0, 3.0, 0.01, "×", "Pod 0 °C."],
	["SIG_TICK", "sig_tick", "Signál – kontrola signálu a hranic každých", 0.05, 3.0, 0.05, "s", ""],
	# nárazy
	["CRASH_V", "crash_v", "Nárazy – nehoda od rychlosti", 0.5, 15.0, 0.1, "m/s", "Ve stromu nad tuto rychlost uvízne."],
	["BUMP_V", "bump_v", "Nárazy – ťuknutí od rychlosti", 0.0, 8.0, 0.05, "m/s", ""],
	["BUMP_DMG_K", "bump_dmg_k", "Nárazy – poškození ťuknutím na 1 m/s", 0.0, 10.0, 0.1, "%", ""],
	["DMG_PER_V", "dmg_per_v", "Nárazy – poškození nehodou na 1 m/s", 0.0, 40.0, 0.5, "%", ""],
	["CRASH_DMG", "crash_dmg", "Nárazy – od poškození nevzlétne (oprava)", 1.0, 100.0, 1.0, "%", ""],
	["STUCK_S", "stuck_s", "Nárazy – visí ve stromu", 0.5, 60.0, 0.5, "s", ""],
	["REST_V", "rest_v", "Nárazy – spadlý dron se uloží pod rychlostí", 0.1, 5.0, 0.05, "m/s", ""],
	["KNOCK_K", "knock_k", "Nárazy – do člověka: odhození (× rychlost)", 0.0, 2.0, 0.01, "×", ""],
	["KNOCK_UP", "knock_up", "Nárazy – do člověka: nadhození (× náraz)", 0.0, 1.0, 0.01, "×", ""],
	["KNOCK_MAX", "knock_max", "Nárazy – do člověka: strop síly", 0.0, 30.0, 0.5, "", ""],
	# zvěř
	["SCARE_S", "scare_s", "Zvěř – plašení bzučením každých", 0.1, 10.0, 0.1, "s", ""],
	["SCARE_R", "scare_r", "Zvěř – dosah plašení", 0.0, 200.0, 1.0, "m", ""],
	["SCARE_LOUD", "scare_loud", "Zvěř – hlasitost bzučení (jako výstřel)", 0.0, 30.0, 0.5, "", ""],
	# pravidla
	["LAW_S", "law_s", "Pravidla – kontrola přestupků každých", 0.1, 10.0, 0.1, "s", ""],
	["OFF_CD", "off_cd", "Pravidla – stejný přestupek znovu nejdřív po", 5.0, 900.0, 5.0, "s", ""],
	["VLOS_M", "vlos_m", "Pravidla – vizuální dohled", 50.0, 3000.0, 10.0, "m", ""],
	["VLOS_OFF_S", "vlos_off_s", "Pravidla – mimo dohled přestupek po", 1.0, 600.0, 1.0, "s", ""],
	["PERSON_R", "person_r", "Pravidla – nad lidmi do vzdálenosti", 0.0, 100.0, 0.5, "m", ""],
	["CROWD_S", "crowd_s", "Pravidla – nad lidmi přestupek po", 0.0, 30.0, 0.5, "s", ""],
	["PRIVACY_AGL", "privacy_agl", "Pravidla – soukromí pod výškou", 0.0, 120.0, 1.0, "m AGL", ""],
	["PRIVACY_S", "privacy_s", "Pravidla – soukromí: vrtění přestupek po", 1.0, 300.0, 1.0, "s", ""],
	["PRIVACY_V", "privacy_v", "Pravidla – soukromí: vrtění = pomaleji než", 0.0, 10.0, 0.1, "m/s", ""],
	["SETTLED_MIN", "settled_min", "Pravidla – zástavba od hustoty osídlení", 0.0, 1.0, 0.01, "", "Registrace, kvalifikace a soukromí se kontrolují jen v zástavbě."],
	["XP_PER_M", "xp_per_m", "Dovednost – XP letectví za metr letu", 0.0, 0.2, 0.001, "XP/m", ""],
]

## Modely dronu (`DroneModel.MODELS[model]`, živě – `spec` dronu je stejný slovník): [klíč, popisek, min, max, krok,
## jednotka, nápověda].
const DRN_MODEL_ROWS := [
	["kg", "Hmotnost (vzletová)", 0.1, 25.0, 0.01, "kg", "Hmotnost tělesa (pád, kolize)."],
	["spd", "Let – rychlost", 1.0, 40.0, 0.5, "m/s", ""],
	["sport", "Let – rychlost ve sportovním režimu", 1.0, 60.0, 0.5, "m/s", "Shift."],
	["climb", "Let – stoupání / klesání", 0.5, 15.0, 0.1, "m/s", "Mezerník / Ctrl."],
	["batt", "Baterie – výdrž", 30.0, 3600.0, 10.0, "s", "Reálné sekundy letu (sport a mráz zkracují)."],
	["range", "Signál – dosah s přímou viditelností", 50.0, 5000.0, 10.0, "m", ""],
	["range_nlos", "Signál – dosah za překážkou", 20.0, 2000.0, 10.0, "m", ""],
	["wind_k", "Vítr – citlivost na vítr", 0.0, 2.0, 0.01, "×", "Jak moc dron strhuje větrem."],
]

## Termika (`Thermals` static var; pole [min, max] po prvcích): [vlastnost, index (-1 = celé), id, popisek, min, max,
## krok, jednotka, nápověda].
const TER_ROWS := [
	["SEASON_M", 0, "season_from", "Sezóna – od měsíce", 1, 12, 1, "", ""],
	["SEASON_M", 1, "season_to", "Sezóna – do měsíce", 1, 12, 1, "", ""],
	["HOURS", 0, "hour_from", "Sezóna – denní okno od", 0.0, 24.0, 0.25, "h", ""],
	["HOURS", 1, "hour_to", "Sezóna – denní okno do", 0.0, 24.0, 0.25, "h", ""],
	["T_MIN", -1, "t_min", "Sezóna – nejnižší teplota vzduchu", -10.0, 40.0, 0.5, "°C", ""],
	["SPAWN_EVERY_MIN", -1, "spawn_every_min", "Vznik – pokus o novou bublinu každých", 0.5, 60.0, 0.5, "herní min", "± 40 %."],
	["MAX_BUBBLES", -1, "max_bubbles", "Vznik – nejvíc živých bublin", 0, 40, 1, "", ""],
	["SPAWN_DIST", 0, "spawn_dist_min", "Vznik – nejblíž od hráče", 0.0, 3000.0, 10.0, "m", ""],
	["SPAWN_DIST", 1, "spawn_dist_max", "Vznik – nejdál od hráče", 50.0, 5000.0, 10.0, "m", ""],
	["FOREST_MAX", -1, "forest_max", "Vznik – ne nad lesem hustším než", 0.0, 1.0, 0.01, "", ""],
	["LIFE_MIN", 0, "life_min", "Bublina – nejkratší život", 0.5, 60.0, 0.5, "herní min", ""],
	["LIFE_MIN", 1, "life_max", "Bublina – nejdelší život", 0.5, 120.0, 0.5, "herní min", ""],
	["RADIUS", 0, "radius_min", "Bublina – nejmenší poloměr", 5.0, 400.0, 1.0, "m", ""],
	["RADIUS", 1, "radius_max", "Bublina – největší poloměr", 5.0, 600.0, 1.0, "m", ""],
	["STRENGTH", 0, "strength_min", "Bublina – nejslabší stoupání v ose", 0.0, 6.0, 0.05, "m/s", ""],
	["STRENGTH", 1, "strength_max", "Bublina – nejsilnější stoupání v ose", 0.0, 10.0, 0.05, "m/s", "Také síla ladicí bubliny."],
	["DAY_FALLOFF", -1, "day_falloff", "Bublina – slabší na okraji denního okna o", 0.0, 1.0, 0.01, "×", "V poledne plná síla."],
	["TOP_AGL", 0, "top_min", "Bublina – nejnižší strop", 20.0, 2000.0, 10.0, "m AGL", ""],
	["TOP_AGL", 1, "top_max", "Bublina – nejvyšší strop", 20.0, 3000.0, 10.0, "m AGL", ""],
	["TOP_FADE", -1, "top_fade", "Bublina – stoupání slábne v horním podílu výšky", 0.01, 1.0, 0.01, "×", ""],
	["DRIFT_K", -1, "drift_k", "Bublina – táhne s větrem", 0.0, 2.0, 0.01, "× vítr", ""],
	["SINK_RING", -1, "sink_ring", "Klesání – prstenec kolem bubliny do", 1.05, 3.0, 0.01, "× poloměr", ""],
	["SINK_MS", -1, "sink_ms", "Klesání – v prstenci u okraje bubliny", 0.0, 2.0, 0.01, "m/s", ""],
	["STORM_LIFT", -1, "storm_lift", "Bouřka – největší stoupání / sestup", 0.0, 15.0, 0.1, "m/s", "Šum × síla bouřky."],
	["STORM_FROM", -1, "storm_from", "Bouřka – proudy od síly bouřky", 0.0, 1.0, 0.01, "", ""],
	["DEBUG_R", -1, "debug_r", "Ladění – pevná bublina nad hráčem (poloměr)", 0.0, 500.0, 5.0, "m", "> 0: stálá bublina nad hráčem 1 se silou „nejsilnější stoupání“, jiné nevznikají."],
]


static func register_all() -> void:
	# vlastnosti strojů (Aircraft.SPECS) – každý model ve své podskupině
	for m in SPEC_GROUP:
		var spec: Dictionary = Aircraft.SPECS[m]
		for r in SPEC_ROWS:
			if spec.has(r[0]):
				DevTune.tune(spec, r[0], "aircraft.%s.%s" % [m, String(r[0]).to_lower()], SPEC_GROUP[m], r[1],
					r[2], r[3], r[4], r[6], r[5])
	for r in AIR_ROWS:
		DevTune.tune(Aircraft, r[0], "aircraft." + String(r[1]), SPOL, r[2], r[3], r[4], r[5], r[7], r[6])
	for r in PG_ROWS:
		DevTune.tune(Paramotor, r[0], "paramotor." + String(r[1]), PG, r[2], r[3], r[4], r[5], r[7], r[6])
	for r in TRK_ROWS:
		var target: Script = Trike if r[0] == "trike" else Airfield
		DevTune.tune(target, r[1], r[2], TRK, r[3], r[4], r[5], r[6], r[8], r[7])
	for r in DRN_ROWS:
		DevTune.tune(Drone, r[0], "drone." + String(r[1]), DRN, r[2], r[3], r[4], r[5], r[7], r[6])
	for m in DroneModel.MODELS:
		var ds: Dictionary = DroneModel.MODELS[m]
		var dname := String(ds.get("name", m))
		for r in DRN_MODEL_ROWS:
			if ds.has(r[0]):
				DevTune.tune(ds, r[0], "drone.%s.%s" % [m, r[0]], DRN, "%s: %s" % [dname, r[1]], r[2], r[3], r[4],
					r[6], r[5])
	for r in TER_ROWS:
		var idx: int = r[1]
		var target: Variant = Thermals if idx < 0 else _thermal_range(String(r[0]))
		var prop: Variant = r[0] if idx < 0 else idx
		DevTune.tune(target, prop, "thermal." + String(r[2]), TER, r[3], r[4], r[5], r[6], r[8], r[7])


## Pole [min, max] termiky (`static var` – registr zapisuje přímo do prvku).
static func _thermal_range(prop: String) -> Array:
	match prop:
		"SEASON_M":
			return Thermals.SEASON_M
		"HOURS":
			return Thermals.HOURS
		"SPAWN_DIST":
			return Thermals.SPAWN_DIST
		"LIFE_MIN":
			return Thermals.LIFE_MIN
		"RADIUS":
			return Thermals.RADIUS
		"STRENGTH":
			return Thermals.STRENGTH
		"TOP_AGL":
			return Thermals.TOP_AGL
	push_error("tune_letani: neznámé pole termiky %s" % prop)
	return []
