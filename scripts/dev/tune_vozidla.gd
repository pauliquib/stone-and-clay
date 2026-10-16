## M8.D: menu pro vývojáře – kategorie **Vozidla**: auto, traktor, motorka, kolo (sdílené parametry fyziky podle druhu,
## `Car.TUNES`), vlastnosti jednotlivých modelů (`CarModel.live_spec`), AI řidič a společné věci (`Car` static var),
## ruční vozík (`HandCart`, `Cargo`). Úplný seznam konstant, které ovlivňují chování vozidel (ne zvuk, světla, vizuál).
## Výchozí hodnoty se berou z kódu (`DevTune.tune` čte současnou hodnotu) – chování ve výchozím stavu beze změny.
extends RefCounted

## Podskupina menu podle druhu (`Car._tune_kind`).
const KIND_GROUP := {"car": "Vozidla/Auto", "tractor": "Vozidla/Traktor", "moto": "Vozidla/Motorka", "bike": "Vozidla/Kolo"}
## Podskupina pro vlastnosti modelů podle druhu.
const MODEL_GROUP := {"car": "Vozidla/Auto – modely", "tractor": "Vozidla/Traktor", "moto": "Vozidla/Motorka – modely",
	"bike": "Vozidla/Kolo"}
const KIND_CODE := {"car": "c", "tractor": "t", "moto": "m", "bike": "b"}

## Sdílené parametry druhu (vlastnosti `Car.Tune`): [vlastnost, popisek, min, max, krok, jednotka, druhy (c auto,
## t traktor, m motorka, b kolo), nápověda]. Popisek začíná oblastí (Brzdy –, Motor –…), ať hledání „brz“ najde všechno.
const TUNE_ROWS := [
	# pružení a karoserie
	["susp_k", "Pružení – tuhost pružiny za kolo", 2000.0, 150000.0, 100.0, "N/m", "ctmb", "Při relativní tuhosti modelu 26 (násobí se „Pružení – tuhost modelu“)."],
	["susp_c", "Pružení – tlumení za kolo", 200.0, 30000.0, 50.0, "N·s/m", "ctmb", "Tlumič při relativní tuhosti modelu 26."],
	["susp_rest", "Pružení – klidová délka", 0.02, 0.5, 0.01, "m", "ctmb", "Délka pružení kolo–náprava v klidu (světlá výška)."],
	["susp_travel", "Pružení – zdvih / doraz", 0.05, 1.0, 0.01, "m", "ctmb", "Jak daleko kolo propruží a jak hluboko sleduje prohlubně."],
	["susp_rebound", "Pružení – odskok tlumí víc než stlačení", 0.5, 4.0, 0.05, "×", "ctmb", "Poměr tlumení při roztahování vůči stlačování."],
	["susp_fmax_g", "Pružení – strop síly pružiny", 0.5, 10.0, 0.1, "× m·g", "ctmb", "Nejvyšší síla jednoho kola (proti katapultu při doskoku)."],
	["susp_droop_g", "Pružení – tah visícího kola", 0.0, 1.0, 0.01, "× m·g", "ctmb", "Kolo na dorazu drží karoserii u země."],
	["track1_stiff", "Pružení – jednostopá: tuhost ×", 0.5, 5.0, 0.05, "×", "m", "Motorky s fyzikálním náklonem mají jen 2 kola v ose → tužší pružení."],
	["track1_damp", "Pružení – jednostopá: tlumení ×", 0.5, 5.0, 0.05, "×", "m", "Totéž pro tlumič."],
	["com_z", "Karoserie – těžiště dopředu", -0.5, 0.5, 0.01, "m", "ct", "Posun těžiště k přední nápravě (výška těžiště je u modelu)."],
	["ang_damp", "Karoserie – útlum otáčení", 0.0, 5.0, 0.05, "", "ctmb", "Útlum rotace tělesa (víc = klidnější při skocích a smyku)."],
	["body_friction", "Karoserie – tření o zem a zdi", 0.0, 2.0, 0.01, "", "ctmb", "Tření karoserie (po převrácení, při nárazu do zdi)."],
	["body_bounce", "Karoserie – odraz při nárazu", 0.0, 1.0, 0.01, "", "ctmb", "Pružnost karoserie při nárazu."],
	["roll_res", "Odpor – valivý odpor", 0.0, 0.1, 0.001, "× m·g", "ctmb", "Valivý odpor pneu (vzdušný odpor je u modelu)."],
	# motor a převodovka
	["idle_rpm", "Motor – volnoběh", 300.0, 2000.0, 10.0, "ot/min", "ctm", ""],
	["tq_low_x", "Motor – momentová křivka: náběh do (podíl max. otáček)", 0.05, 0.9, 0.01, "", "ctm", "Pod tímto podílem otáček moment roste."],
	["tq_low_f", "Motor – momentová křivka: moment ve volnoběhu", 0.0, 1.0, 0.01, "×", "ctm", "Podíl max. momentu v nejnižších otáčkách."],
	["tq_high_x", "Motor – momentová křivka: pokles od (podíl max. otáček)", 0.1, 0.99, 0.01, "", "ctm", "Nad tímto podílem otáček moment klesá."],
	["tq_high_f", "Motor – momentová křivka: moment v max. otáčkách", 0.0, 1.5, 0.01, "×", "ctm", ""],
	["limiter_over", "Motor – omezovač nad max. otáčky", 0.0, 2000.0, 10.0, "ot/min", "ctm", ""],
	["rpm_follow", "Motor – jak rychle otáčky sledují kola", 1.0, 60.0, 0.5, "1/s", "ctm", ""],
	["driveline_eff", "Motor – účinnost převodů", 0.3, 1.0, 0.01, "", "ctm", "Kolik momentu motoru dojde na kola."],
	["dmg_power_from", "Motor – poškození: ztráta výkonu od", 0.0, 100.0, 1.0, "%", "ctm", ""],
	["dmg_power_loss", "Motor – poškození: nejvyšší ztráta výkonu", 0.0, 1.0, 0.01, "×", "ctm", ""],
	["engine_brake", "Motor – brzdění motorem", 0.0, 5.0, 0.05, "m/s²", "ctm", "Zpomalení bez plynu."],
	["clutch_rpm", "Spojka – prokluz pod otáčkami", 300.0, 4000.0, 10.0, "ot/min", "ctm", "Rozjezd: pod těmito otáčkami motoru spojka prokluzuje."],
	["launch_rpm", "Spojka – otáčky při rozjezdu na plný plyn", 500.0, 8000.0, 10.0, "ot/min", "ctm", ""],
	["rev_ratio", "Převodovka – převod zpátečky", 0.5, 10.0, 0.05, "", "ctm", "Násobí se stálým převodem modelu."],
	["up_rpm", "Převodovka – řazení nahoru při malém plynu", 500.0, 10000.0, 10.0, "ot/min", "ctm", ""],
	["up_frac", "Převodovka – řazení nahoru při plném plynu", 0.3, 1.1, 0.01, "× max. ot.", "ctm", ""],
	["up_min_v", "Převodovka – nahoru až od rychlosti", 0.0, 10.0, 0.1, "m/s", "ctm", ""],
	["down_rpm", "Převodovka – podřazení pod otáčkami", 300.0, 6000.0, 10.0, "ot/min", "ctm", ""],
	["kick_thr", "Převodovka – kickdown od plynu", 0.0, 1.0, 0.01, "", "ctm", ""],
	["kick_frac", "Převodovka – kickdown jen když nižší stupeň nepřetočí", 0.3, 1.0, 0.01, "× max. ot.", "ctm", ""],
	["kick_rpm_frac", "Převodovka – kickdown pod otáčkami", 0.1, 1.0, 0.01, "× max. ot.", "ctm", ""],
	["shift_up_s", "Převodovka – prodleva řazení nahoru", 0.0, 2.0, 0.01, "s", "ctm", "Bez tahu během řazení."],
	["shift_down_s", "Převodovka – prodleva podřazení", 0.0, 2.0, 0.01, "s", "ctm", ""],
	# brzdy
	["brake_decel", "Brzdy – zpomalení při plné brzdě", 1.0, 25.0, 0.1, "m/s²", "ctmb", "Brzdná síla na kolo = hmotnost × tohle / 4 (omezená přilnavostí)."],
	["hand_decel", "Brzdy – ruční brzda (zadní kola)", 0.0, 25.0, 0.1, "m/s²", "ctmb", ""],
	["hand_grip", "Brzdy – ruční brzda: boční přilnavost zadních kol", 0.0, 1.0, 0.01, "×", "ctmb", "Menší = snáz smyk zádí."],
	["brake_hold_v", "Brzdy – drží na místě pod rychlostí", 0.0, 1.0, 0.01, "m/s", "ctmb", ""],
	# přilnavost
	["tire_mu", "Přilnavost – tření pneu", 0.1, 3.0, 0.01, "µ", "ctmb", "Základ; násobí se povrchem (Svět → Povrchy) a přilnavostí modelu."],
	["xfer_v", "Přilnavost – přenos zatížení naplno od rychlosti", 0.5, 40.0, 0.5, "m/s", "m", ""],
	["xfer_brake_f", "Přilnavost – brzda přitíží přední kolo", 0.0, 1.0, 0.01, "+×", "m", ""],
	["xfer_brake_r", "Přilnavost – brzda odlehčí zadní kolo", 0.0, 1.0, 0.01, "−×", "m", ""],
	["xfer_thr_f", "Přilnavost – plyn odlehčí přední kolo", 0.0, 1.0, 0.01, "−×", "m", ""],
	["xfer_thr_r", "Přilnavost – plyn přitíží zadní kolo", 0.0, 1.0, 0.01, "+×", "m", ""],
	# řízení
	["steer_lock", "Řízení – rejd ve stání", 0.1, 1.2, 0.01, "rad", "ctmb", "Největší natočení kol při nulové rychlosti (s rychlostí klesá k „rejdu v rychlosti“ modelu)."],
	["steer_clamp", "Řízení – mez natočení kol", 0.1, 1.2, 0.01, "rad", "ctm", ""],
	["steer_in_rate", "Řízení – rychlost natáčení volantu", 0.5, 20.0, 0.1, "1/s", "ctmb", "Jak rychle hráč točí volantem / řídítky."],
	["steer_out_rate", "Řízení – rychlost vracení volantu", 0.5, 20.0, 0.1, "1/s", "ctmb", ""],
	["rev_engage_v", "Řízení – brzda zařadí zpátečku pod rychlostí", 0.0, 3.0, 0.05, "m/s", "ctmb", ""],
	# náklon a vyvažování
	["bal_kp", "Náklon – vyvažování: tuhost", 0.0, 60.0, 0.5, "", "mb", "Jak silně se jezdec drží ve svislé poloze / v cílovém náklonu."],
	["bal_kd", "Náklon – vyvažování: tlumení", 0.0, 20.0, 0.1, "", "mb", ""],
	["cargo_stab_kg", "Náklon – náklad na nosiči: plná ztráta stability při", 5.0, 300.0, 1.0, "kg", "mb", ""],
	["cargo_stab_max", "Náklon – náklad na nosiči: nejvyšší ztráta stability", 0.0, 1.0, 0.01, "×", "mb", ""],
	["cargo_com_kg", "Náklon – náklad posune těžiště o krok na", 5.0, 200.0, 1.0, "kg", "mb", ""],
	["cargo_com_step", "Náklon – posun těžiště nákladem (krok)", 0.0, 0.5, 0.01, "m", "mb", ""],
	["cargo_com_max", "Náklon – posun těžiště nákladem nejvýš (kroků)", 0.0, 5.0, 0.1, "", "mb", ""],
	["gyro_min", "Náklon – gyroskopický efekt ve stání", 0.0, 2.0, 0.01, "×", "m", "Samovyvažování kol pomalu (roste s rychlostí)."],
	["gyro_v", "Náklon – plný gyroskopický efekt od", 1.0, 60.0, 0.5, "m/s", "m", ""],
	["park_gyro", "Náklon – zaparkovaná na stojánku: stabilita", 0.0, 10.0, 0.1, "×", "m", ""],
	["lean_from_v", "Náklon – do zatáčky od rychlosti", 0.0, 15.0, 0.1, "m/s", "m", "Pomaleji se motorka nenaklání."],
	["lean_full_dv", "Náklon – plný náklon o tolik rychleji", 0.5, 40.0, 0.5, "m/s", "m", ""],
	["lean_mu_cap", "Náklon – strop tření pro mez náklonu", 0.2, 3.0, 0.05, "µ", "m", "Mez náklonu = atan(µ) – na ledu se motorka nakloní míň."],
	["yaw_max", "Náklon – nejprudší zatáčení z náklonu", 0.1, 5.0, 0.05, "rad/s", "m", ""],
	["camber_v", "Náklon – zatáčení náklonem (camber) od rychlosti", 0.0, 10.0, 0.1, "m/s", "m", ""],
	["stand_lean", "Náklon – na stojánku", 0.0, 0.5, 0.01, "rad", "mb", ""],
	["lean_vis_rate", "Náklon – rychlost vizuálního náklonu", 0.5, 30.0, 0.5, "1/s", "mb", ""],
	["lean_vis_max", "Náklon – největší vizuální náklon (bez fyz. náklonu)", 0.0, 1.4, 0.01, "rad", "mb", "Kolo a motorky bez fyzikálního náklonu se nakloní jen vizuálně."],
	# šlapání
	["pedal_ratio", "Šlapání – převod (kola : kliky)", 0.5, 6.0, 0.05, "", "b", "Otáčky klik = otáčky kola / tohle."],
	["vmax_fade", "Šlapání – síla slábne před max. rychlostí o", 0.1, 10.0, 0.1, "m/s", "b", ""],
	["back_push", "Šlapání – tlačení dozadu (podíl síly)", 0.0, 1.0, 0.01, "×", "b", ""],
	["back_vmax", "Šlapání – tlačení dozadu do rychlosti", 0.0, 5.0, 0.05, "m/s", "b", ""],
	["pedal_dmg", "Šlapání – poškození: síla × (1 − poškození / tohle)", 100.0, 1000.0, 10.0, "%", "b", ""],
]

## Vlastnosti modelu (`CarModel.live_spec(id)`): [klíč, popisek, min, max, krok, jednotka, druhy, náhradní hodnota
## (když ji model nemá – stejná jako v kódu `Car`; "" = model ji musí mít), nápověda].
const MODEL_ROWS := [
	["mass", "Hmotnost", 30.0, 6000.0, 5.0, "kg", "ctmb", "", "Bez nákladu."],
	["torque", "Motor – max. moment", 1.0, 1000.0, 1.0, "N·m", "ctm", "", ""],
	["rpm_max", "Motor – max. otáčky", 500.0, 16000.0, 50.0, "ot/min", "ctm", "", ""],
	["final", "Převodovka – stálý převod", 0.5, 30.0, 0.05, "", "ctm", "", "Násobí převod každého stupně."],
	["drag", "Odpor – vzdušný odpor", 0.0, 3.0, 0.01, "N/(m/s)²", "ctmb", "", "Síla = tohle × v²."],
	["grip", "Přilnavost – pneu modelu", 0.2, 3.0, 0.01, "×", "ctmb", 1.0, ""],
	["com_y", "Karoserie – výška těžiště", 0.1, 1.5, 0.01, "m", "ctmb", "com_y", ""],
	["susp", "Pružení – tuhost modelu (relativní)", 5.0, 80.0, 0.5, "", "ctmb", "susp", "26 = výchozí auto, tuhost i tlumení × (tohle / 26)."],
	["steer_hi", "Řízení – rejd v rychlosti", 0.005, 0.6, 0.005, "rad", "ctmb", "steer_hi", "Natočení kol při rychlosti „Řízení – rejd klesá do“."],
	["steer_v", "Řízení – rejd klesá do rychlosti", 1.0, 80.0, 0.5, "m/s", "ctmb", "steer_v", ""],
	["steer_rate", "Řízení – rychlost natáčení kol", 0.2, 10.0, 0.1, "rad/s", "ctmb", "steer_rate", ""],
	["stab", "Náklon – stabilita jezdce", 0.0, 5.0, 0.05, "×", "mb", 1.0, "Násobí vyvažování."],
	["lean_max", "Náklon – největší náklon", 0.05, 1.2, 0.01, "rad", "L", "", "Jen motorky s fyzikálním náklonem."],
	["lean_yaw", "Náklon – zatáčení z náklonu (camber)", 0.0, 5.0, 0.05, "", "L", 0.9, ""],
	["lean_steer", "Náklon – svod řízení (trail)", 0.0, 2.0, 0.01, "", "L", 0.28, "Přední kolo se samo stáčí do náklonu."],
	["countersteer", "Náklon – protizatáčení", 0.0, 0.2, 0.005, "", "L", 0.02, "Náhlý vstup krátce vychýlí řídítka opačně."],
	["push", "Šlapání – síla", 10.0, 2000.0, 5.0, "N", "b", "", ""],
	["vmax", "Šlapání – max. rychlost", 1.0, 30.0, 0.1, "m/s", "b", "", ""],
	["ai_vmax", "AI – nejvyšší rychlost v provozu", 1.0, 60.0, 0.5, "m/s", "t", 99.0, "Rychlostní strop AI řidiče (traktor ~27 km/h)."],
]

## AI řidič (`Car` static var): [vlastnost, id, popisek, min, max, krok, jednotka, nápověda].
const AI_ROWS := [
	["AI_SLOW", "slow", "Počasí – zpomalení v dešti / mlze / sněhu", 0.0, 0.95, 0.01, "×", "Při plné nepohodě jede o tolik pomaleji."],
	["AI_GAP", "gap", "Počasí – delší rozestup", 0.0, 3.0, 0.05, "×", "O kolik dál hledá překážku za nepohody."],
	["AI_SLIP_ALAT", "slip_alat", "Počasí – menší boční zrychlení v zatáčce na kluzku", 0.0, 3.0, 0.05, "m/s²", ""],
	["AI_SLIP_GAP", "slip_gap", "Počasí – větší mezera za překážkou na kluzku", 0.0, 15.0, 0.1, "m", ""],
	["AI_LOOK_K", "look_k", "Řízení – cílový bod: m za každý m/s", 0.0, 3.0, 0.05, "s", "Pure pursuit: cíl L = k·v + základ, omezený min/max."],
	["AI_LOOK_BASE", "look_base", "Řízení – cílový bod: základ", 0.0, 20.0, 0.1, "m", ""],
	["AI_LOOK_MIN", "look_min", "Řízení – cílový bod: nejblíž", 1.0, 30.0, 0.1, "m", ""],
	["AI_LOOK_MAX", "look_max", "Řízení – cílový bod: nejdál", 2.0, 60.0, 0.5, "m", ""],
	["AI_STEER_RATE", "steer_rate", "Řízení – rychlost otáčení volantem", 0.5, 30.0, 0.1, "1/s", ""],
	["AI_SHARP", "sharp", "Trasa – ostrá zatáčka od úhlu lomu", 0.1, 3.0, 0.01, "rad", "Za ostrým lomem se cílový bod zkracuje (neseřízne roh)."],
	["AI_PASS_R", "pass_r", "Trasa – bod trasy odbaven blíž než", 0.5, 15.0, 0.1, "m", ""],
	["AI_KIN_PASS", "kin_pass", "Trasa – vzdálené (uspané) auto odbaví bod na", 1.0, 30.0, 0.5, "m", ""],
	["AI_HORIZON", "horizon", "Rychlost – plánuje zatáčky dopředu na", 10.0, 300.0, 5.0, "m", ""],
	["AI_ALAT_MIN", "alat_min", "Rychlost – boční zrychlení ve vlásence", 0.5, 10.0, 0.1, "m/s²", ""],
	["AI_ALAT_MAX", "alat_max", "Rychlost – boční zrychlení v široké zatáčce", 0.5, 12.0, 0.1, "m/s²", ""],
	["AI_ALAT_R", "alat_r", "Rychlost – široká zatáčka o tolik větší poloměr než vlásenka (4 m)", 1.0, 200.0, 1.0, "m", ""],
	["AI_BRAKE", "brake", "Rychlost – plánované zpomalení před zatáčkou", 0.5, 10.0, 0.1, "m/s²", ""],
	["AI_REACT", "react", "Rychlost – reakční rezerva", 0.0, 3.0, 0.05, "s", "Brzdí o tolik dřív."],
	["AI_VMIN", "vmin", "Rychlost – nejnižší plánovaná na trase", 0.0, 10.0, 0.1, "m/s", ""],
	["AI_CHASE_K", "chase_k", "Rychlost – policie: rychlost × vzdálenost cíle", 0.05, 5.0, 0.05, "1/s", ""],
	["AI_THR_K", "thr_k", "Regulátor – plyn na 1 m/s chybějící rychlosti", 0.01, 3.0, 0.01, "", ""],
	["AI_BRK_K", "brk_k", "Regulátor – brzda na 1 m/s přebytku", 0.01, 3.0, 0.01, "", ""],
	["AI_CRUISE_THR", "cruise_thr", "Regulátor – plyn při udržování rychlosti", 0.0, 1.0, 0.01, "", ""],
	["AI_SEE_BASE", "see_base", "Překážky – dohled: základ", 0.0, 30.0, 0.5, "m", ""],
	["AI_SEE_K", "see_k", "Překážky – dohled: m za každý m/s", 0.0, 5.0, 0.05, "s", ""],
	["AI_OBST_DT", "obst_dt", "Překážky – hledá každých", 0.02, 1.0, 0.01, "s", "Častěji = dražší (dotazy fyziky)."],
	["AI_STATIC_LIFT", "static_lift", "Překážky – výška hledání statiky nad pruhem", 0.3, 4.0, 0.05, "m", "Nad hrboly terénu, ale v úrovni zdí."],
	["AI_STOP_GAP", "stop_gap", "Překážky – zastaví před překážkou", 0.0, 15.0, 0.1, "m", ""],
	["AI_FOLLOW_K", "follow_k", "Překážky – rychlost × zbytek mezery", 0.05, 3.0, 0.05, "1/s", ""],
	["AI_HONK_S", "honk_s", "Překážky – troubí po stání", 0.5, 30.0, 0.5, "s", ""],
	["AI_PASS_WAIT", "pass_wait", "Objíždění – po stání za překážkou", 0.5, 30.0, 0.5, "s", ""],
	["AI_PASS_LEN", "pass_len", "Objíždění – délka objíždění", 5.0, 100.0, 1.0, "m", ""],
	["AI_PASS_OFFSET", "pass_offset", "Objíždění – boční posun", 0.5, 6.0, 0.1, "m", ""],
	["AI_OFFSET_RATE", "offset_rate", "Objíždění – rychlost vybočení", 0.1, 10.0, 0.1, "m/s", ""],
	["AI_PASS_V", "pass_v", "Objíždění – rychlost", 0.5, 20.0, 0.5, "m/s", ""],
	["AI_STUCK_S", "stuck_s", "Zaseknutí – vycouvá po", 0.5, 20.0, 0.1, "s", ""],
	["AI_REVERSE_S", "reverse_s", "Zaseknutí – couvá", 0.2, 10.0, 0.1, "s", ""],
]

## Společné pro všechna vozidla (`Car` static var): [vlastnost, id, popisek, min, max, krok, jednotka, nápověda].
const COMMON_ROWS := [
	["FLIP_UP", "flip_up", "Převrácení – auto leží, když osa nahoru míří míň než", -1.0, 1.0, 0.01, "", "Kosinus náklonu."],
	["FLIP_S", "flip_s", "Převrácení – AI auto se samo postaví po", 0.5, 60.0, 0.5, "s", ""],
	["CRASH_DV", "crash_dv", "Nárazy – náraz od změny rychlosti za krok", 0.3, 20.0, 0.1, "m/s", ""],
	["CRASH_VERT", "crash_vert", "Nárazy – svislá složka (doskoky) se počítá z", 0.0, 1.0, 0.01, "×", ""],
	["CRASH_COOL", "crash_cool", "Nárazy – mezi dvěma nárazy aspoň", 0.0, 3.0, 0.05, "s", ""],
	["CRASH_DMG_FROM", "crash_dmg_from", "Nárazy – poškození od nárazu", 0.0, 20.0, 0.1, "m/s", ""],
	["CRASH_DMG_K", "crash_dmg_k", "Nárazy – poškození na 1 m/s nárazu", 0.0, 50.0, 0.1, "%", ""],
	["CRASH_DMG_MAX", "crash_dmg_max", "Nárazy – nejvíc poškození z jednoho nárazu", 0.0, 100.0, 1.0, "%", ""],
	["CRASH_UNDERBODY", "crash_underbody", "Nárazy – dopad na podvozek poškodí z", 0.0, 1.0, 0.01, "×", ""],
	["SMOKE_DAMAGE", "smoke_damage", "Nárazy – motor kouří od poškození", 0.0, 100.0, 1.0, "%", ""],
	["DEFORM_K", "deform_k", "Nárazy – promáčknutí na 1 m/s", 0.0, 0.1, 0.001, "m", ""],
	["DEFORM_MAX", "deform_max", "Nárazy – nejhlubší promáčknutí", 0.0, 1.0, 0.01, "m", ""],
	["HIT_V", "hit_v", "Srážka s člověkem – od rychlosti směrem k němu", 0.5, 20.0, 0.1, "m/s", ""],
	["HIT_COOL", "hit_cool", "Srážka s člověkem – stejný člověk znovu po", 0.1, 20.0, 0.1, "s", ""],
	["KNOCK_K", "knock_k", "Srážka s člověkem – odhození (podíl rychlosti auta)", 0.0, 3.0, 0.05, "×", ""],
	["KNOCK_UP", "knock_up", "Srážka s člověkem – vyhození nahoru", 0.0, 3.0, 0.05, "×", ""],
	["DRUNK_DELAY_K", "drunk_delay_k", "Opilý řidič – zpoždění reakce na 1 ‰", 0.0, 1.0, 0.01, "s", ""],
	["DRUNK_DELAY_MAX", "drunk_delay_max", "Opilý řidič – zpoždění reakce nejvýš", 0.0, 3.0, 0.05, "s", ""],
	["DRUNK_WOBBLE_K", "drunk_wobble_k", "Opilý řidič – rozkmit volantu na 1 ‰", 0.0, 2.0, 0.01, "", ""],
	["DRUNK_WOBBLE_MAX", "drunk_wobble_max", "Opilý řidič – rozkmit volantu nejvýš", 0.0, 2.0, 0.01, "", ""],
	["DRUNK_OVER_K", "drunk_over_k", "Opilý řidič – přehnané korekce na 1 ‰", 0.0, 2.0, 0.01, "", ""],
	["MICROSLEEP_PROMILE", "microsleep_promile", "Opilý řidič – mikrospánek od", 0.0, 5.0, 0.05, "‰", ""],
	["MICROSLEEP_P", "microsleep_p", "Opilý řidič – pravděpodobnost mikrospánku", 0.0, 1.0, 0.01, "", ""],
]

## Ruční vozík (`HandCart`, tažení `Cargo`): [cíl, vlastnost, id, popisek, min, max, krok, jednotka, nápověda].
const CART_ROWS := [
	["cart", "EMPTY_KG", "empty_kg", "Hmotnost prázdného vozíku", 1.0, 200.0, 0.5, "kg", ""],
	["cart", "CAPACITY_KG", "capacity_kg", "Nosnost korby", 10.0, 2000.0, 5.0, "kg", ""],
	["cart", "FREE_DAMP", "free_damp", "Útlum puštěného vozíku", 0.0, 10.0, 0.05, "", "Malý = na svahu ujede, velký = hned stojí."],
	["cart", "ANG_DAMP", "ang_damp", "Útlum otáčení", 0.0, 20.0, 0.1, "", ""],
	["cart", "SKID_FRICTION", "skid_friction", "Tření kluzné podložky (místo kol)", 0.0, 2.0, 0.01, "", ""],
	["cart", "COM_Y", "com_y", "Výška těžiště", 0.0, 1.5, 0.01, "m", ""],
	["cart", "SIDE_GRIP", "side_grip", "Kola nejdou bokem (rušení skluzu)", 0.0, 60.0, 0.5, "1/s", ""],
	["cart", "ROLL_KP", "roll_kp", "Proti překlopení – tuhost", 0.0, 60.0, 0.5, "", ""],
	["cart", "ROLL_KD", "roll_kd", "Proti překlopení – tlumení", 0.0, 20.0, 0.1, "", ""],
	["cart", "HOLD_DIST", "hold_dist", "Tažení – madlo od hráče", 0.1, 3.0, 0.05, "m", ""],
	["cart", "PULL_ACC", "pull_acc", "Tažení – pružina: zrychlení na 1 m", 0.5, 60.0, 0.5, "m/s²", ""],
	["cart", "PULL_DAMP", "pull_damp", "Tažení – tlumení pružiny", 0.0, 30.0, 0.1, "1/s", ""],
	["cart", "PULL_MAX_ACC", "pull_max_acc", "Tažení – nejvyšší zrychlení", 0.5, 60.0, 0.5, "m/s²", ""],
	["cart", "CLOSE_DAMP", "close_damp", "Tažení – blízko hráče jen tlumení ×", 0.0, 5.0, 0.05, "×", ""],
	["cargo", "GRIP_LOST_R", "grip_lost_r", "Tažení – oj vyklouzne z ruky na", 1.0, 10.0, 0.1, "m", ""],
	["cargo", "CART_SPEED_KG", "speed_kg", "Chůze s vozíkem – rychlost × (1 − kg / tohle)", 50.0, 2000.0, 5.0, "kg", ""],
	["cargo", "CART_SPEED_MIN", "speed_min", "Chůze s vozíkem – nejpomaleji", 0.05, 1.0, 0.01, "×", ""],
	["cargo", "CART_SPEED_MAX", "speed_max", "Chůze s vozíkem – nejrychleji", 0.1, 1.5, 0.01, "×", ""],
	["cargo", "CART_GRADE_K", "grade_k", "Chůze s vozíkem – do kopce zpomalení na stoupání", 0.0, 10.0, 0.1, "", ""],
	["cargo", "CART_GRADE_KG", "grade_kg", "Chůze s vozíkem – do kopce + kg / tohle", 10.0, 1000.0, 5.0, "kg", ""],
	["cargo", "CART_GRADE_MIN", "grade_min", "Chůze s vozíkem – do kopce nejpomaleji", 0.05, 1.0, 0.01, "×", ""],
	["cargo", "CART_STAMINA_K", "stamina_k", "Výdrž – úbytek při tažení (× kg / 60)", 0.0, 0.5, 0.005, "/s", ""],
	["cargo", "CART_STAMINA_GRADE", "stamina_grade", "Výdrž – do kopce × (1 + tohle × stoupání)", 0.0, 30.0, 0.5, "", ""],
]


static func register_all() -> void:
	for kind in ["car", "tractor", "moto", "bike"]:
		var t: Object = Car.TUNES[kind]
		var code: String = KIND_CODE[kind]
		for r in TUNE_ROWS:
			if String(r[6]).contains(code):
				DevTune.tune(t, r[0], "%s.%s" % [kind, r[0]], KIND_GROUP[kind], r[1], r[2], r[3], r[4], r[7], r[5])
	for id in CarModel.MODELS:
		_register_model(id)
	for r in AI_ROWS:
		DevTune.tune(Car, r[0], "car_ai." + String(r[1]), "Vozidla/AI řidič", r[2], r[3], r[4], r[5], r[7], r[6])
	for r in COMMON_ROWS:
		DevTune.tune(Car, r[0], "vehicle." + String(r[1]), "Vozidla/Společné", r[2], r[3], r[4], r[5], r[7], r[6])
	for r in CART_ROWS:
		var target: Script = HandCart if r[0] == "cart" else Cargo
		DevTune.tune(target, r[1], "cart." + String(r[2]), "Vozidla/Ruční vozík", r[3], r[4], r[5], r[6], r[8], r[7])


## Druh modelu jako `Car._tune_kind` (bez stavby modelu).
static func _kind_of(spec: Dictionary) -> String:
	var k := String(spec.get("kind", "car"))
	if k == "car" and String(spec.get("builder", "")) == "tractor":
		return "tractor"
	return k


## Náhradní hodnota klíče, který model nemá – přesně jako `spec.get(klíč, …)` v `Car`.
static func _fallback(key: String, spec: Dictionary, kind: String) -> float:
	var boxy := bool(spec.get("boxy", false))
	match key:
		"com_y":
			return 0.62 if boxy else 0.48
		"susp":
			return 30.0 if boxy else 26.0
		"steer_hi":
			return 0.12 if kind == "bike" else 0.09
		"steer_v":
			return 12.0 if kind == "bike" else 33.0
		"steer_rate":
			return 2.6 if kind == "bike" else 2.2
	return 0.0


static func _register_model(id: String) -> void:
	var spec := CarModel.live_spec(id)
	var kind := _kind_of(spec)
	var code: String = KIND_CODE.get(kind, "c")
	var lean := float(spec.get("lean_max", 0.0)) > 0.0
	var group: String = MODEL_GROUP.get(kind, "Vozidla/Auto – modely")
	var name := String(spec.get("name", id))
	for r in MODEL_ROWS:
		var kinds := String(r[6])
		if kinds == "L":
			if not lean:
				continue
		elif not kinds.contains(code):
			continue
		var key: String = r[0]
		if not spec.has(key):
			var fb: Variant = r[7]
			if fb is String:
				if fb == "":
					continue                    # model hodnotu nemá a kód ji bez ní nečte
				fb = _fallback(key, spec, kind)
			spec[key] = float(fb)               # stejná hodnota, jakou by Car vzal z `spec.get(klíč, …)`
		DevTune.tune(spec, key, "model.%s.%s" % [id, key], group, "%s: %s" % [name, r[1]], r[2], r[3], r[4], r[8], r[5])
	if code != "b" and spec.get("gears") is Array:
		var gears: Array = spec["gears"]
		for i in gears.size():
			DevTune.tune(gears, i, "model.%s.gear%d" % [id, i + 1], group, "%s: Převodovka – %d. stupeň" % [name, i + 1],
				0.1, 8.0, 0.01, "Převodový poměr stupně (× stálý převod).", "")
