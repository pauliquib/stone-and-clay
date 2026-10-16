## M8.D2d: menu pro vývojáře – kategorie **Zvěř**: lokomoce a rig čtyřnožců (QuadrupedRig, Animal), parametry
## jednotlivých druhů (AnimalSpecs – podskupina na druh), smysly a útěk, ptáci a let (Bird, FlightModel), hejna
## a murmurace (BirdFlock, Murmuration, Herd), hospodářská zvířata (kůň, výběh, farma) a ostatní (rozmístění zvěře,
## mraveniště, včely, myslivec, hajný, postřelení a srážky). Úplný seznam konstant, které ovlivňují chování.
##
## Výchozí hodnoty se berou z kódu (`DevTune.tune` čte současnou `static var` / položku slovníku) – chování ve výchozím
## stavu beze změny. Za snímek se registr nečte: systémy čtou své `static var`, druhy sdílenou kopii
## `AnimalSpecs.LIVE` / `Bird.SPECIES` / `FlightModel.SPECIES` / `FarmSpecs.DATA`. Odvozená data (Froudovy prahy rigu,
## rychlosti chodů koně, pádová rychlost ptáka) se přepočítají po změně přes `AnimalSpecs.tune_gen` / `FlightModel.tune_gen`
## (`on_changed` níž) – porovnání celého čísla za snímek, žádné alokace.
extends RefCounted

const POHYB := "Zvěř/Pohyb a rig"
const SMYSLY := "Zvěř/Smysly a útěk"
const PTACI := "Zvěř/Ptáci a let"
const HEJNA := "Zvěř/Hejna a murmurace"
const FARMA := "Zvěř/Hospodářská zvířata"
const OSTATNI := "Zvěř/Ostatní"
const DRUH := "Zvěř/Druh – "            # + jméno druhu (podskupina na druh)

const RESTART := " Projeví se až u nově vzniklých (nebo po novém startu světa)."

## Druhy čtyřnožců: divoká zvěř (pohyb + smysly), kůň (pohyb pod jezdcem), chov (jen tělo a pohyb rigu).
const WILD := ["srnec", "divocak", "sele", "zajic"]
const RIDE := ["kun"]
const FARM_MODELS := ["prase_farm", "koza", "ovce", "krava", "kralik"]
const GAIT_NAMES := {"walk": "krok", "trot": "klus", "canter": "cval", "gallop": "trysk / skoky"}
const LEG_NAMES := ["LP", "PP", "LZ", "PZ"]
const SEG_NAMES := ["stehno", "holeň", "spěnka"]


static func register_all() -> void:
	_rig()
	_animal_move()
	_senses()
	for id in WILD + RIDE + FARM_MODELS:
		_species(id)
	_birds()
	_flocks()
	_farm()
	_other()


## Zvěř/Ptáci, rig a kůň přepočítají odvozená data po změně parametru (registr připojí tuto funkci sám).
static func on_changed(id: String, _v: Variant) -> void:
	if id.begins_with("animal.") or id.begins_with("rig.") or id.begins_with("horse."):
		AnimalSpecs.tune_gen += 1
	elif id.begins_with("bird.") or id.begins_with("bird_aero.") or id.begins_with("bird_flight."):
		FlightModel.tune_gen += 1


# ------------------------------------------------------------------ pomocné

## Řádky: [vlastnost / klíč / index, id (bez předpony), popisek, jednotka, nápověda, (min, max, krok)].
## Bez rozsahu: 0 … 3× výchozí (záporné 3× … 0), krok podle řádu hodnoty, celé číslo krok 1.
static func _reg(target: Variant, prefix: String, group: String, rows: Array) -> void:
	for r: Array in rows:
		var v: Variant = _val(target, r[0])
		if v == null:
			push_error("tune_zver: %s nemá %s" % [prefix, str(r[0])])
			continue
		var rg: Array = [r[5], r[6], r[7]] if r.size() >= 8 else _range(v)
		var help: String = r[4] if r.size() >= 5 else ""
		DevTune.tune(target, r[0], prefix + String(r[1]), group, r[2], float(rg[0]), float(rg[1]), float(rg[2]), help, r[3])


static func _val(target: Variant, prop: Variant) -> Variant:
	if target is Dictionary:
		return (target as Dictionary).get(prop)
	if target is Array:
		var a: Array = target
		return a[int(prop)] if int(prop) >= 0 and int(prop) < a.size() else null
	if target is Object:
		return (target as Object).get(StringName(prop))
	return null


static func _range(v: Variant) -> Array:
	if v is bool:
		return [0.0, 1.0, 1.0]
	if v is int:
		var iv := int(v)
		if iv < 0:
			return [float(iv) * 3.0, 0.0, 1.0]
		return [0.0, float(maxi(iv * 3, iv + 10)), 1.0]
	var f := float(v)
	var a := absf(f)
	if a < 1e-9:
		return [0.0, 1.0, 0.01]
	var step := pow(10.0, floorf(log(a) / log(10.0)) - 2.0)
	if f > 0.0:
		return [0.0, f * 3.0, step]
	return [f * 3.0, 0.0, step]


# ------------------------------------------------------------------ Pohyb a rig

static func _rig() -> void:
	_reg(QuadrupedRig, "rig.", POHYB, [
		["G", "g", "Rig – tíhové zrychlení (Froude, kmitočet kroku, náklon)", "m/s²", "Jen pro chody a animaci; fyziku zvířete řídí „Pohyb – gravitace“."],
		["SECONDARY_R", "secondary_r", "Rig – páteř, dech a pružiny uší do vzdálenosti", "m", "Dál od kamery zjednodušený pohyb (výkon)."],
		["LOD_CHECK_S", "lod_check_s", "Rig – detail podle kamery se přepočítá jednou za", "s"],
		["IK_RESAMPLE_S", "ik_resample_s", "IK chodidel – rovina terénu se měří jednou za", "s"],
		["IK_BLEND", "ik_blend", "IK chodidel – vyhlazení nápravy", "1/s"],
		["GAIT_BLEND", "gait_blend", "Chody – prolínání posunů fází, střídy a kmitočtu", "1/s"],
		["STYLE_BLEND", "style_blend", "Chody – prolínání stylu pohupu (krok/klus ↔ cval)", "1/s"],
		["OLD_HYST_UP", "old_hyst_up", "Chody – starý výběr (bez realismu): nahoru nad mez ×", "×", "Platí jen s vypnutým přepínačem realismu „animal_gait“.", 1.0, 1.5, 0.01],
		["OLD_HYST_DN", "old_hyst_dn", "Chody – starý výběr (bez realismu): dolů pod mez ×", "×", "", 0.5, 1.0, 0.01],
		["OLD_LEAN_K", "old_lean_k", "Náklon – do zatáčky (bez realismu)", "×"],
		["FREQ_LO", "freq_lo", "Kroky – kmitočet na dolní mezi rychlosti chodu", "×"],
		["FREQ_HI", "freq_hi", "Kroky – kmitočet na horní mezi rychlosti chodu", "×"],
		["MOVE_BLEND", "move_blend", "Kroky – náběh a doběh pohybu nohou", "1/s"],
		["AMP_MAX", "amp_max", "Kroky – největší rozkmit nohy", "rad"],
		["LIFT_BASE", "lift_base", "Kroky – zvednutí nohy při přenosu (ve stání)", "", "Podíl ohnutí nohy (fold) při přenosu."],
		["LIFT_PER_V", "lift_per_v", "Kroky – zvednutí nohy + na m/s", "1/(m/s)"],
		["LIFT_MAX", "lift_max", "Kroky – zvednutí nohy nejvýš", ""],
		["TURN_STEP_V", "turn_step_v", "Přešlapování – při otáčení pod rychlostí", "m/s"],
		["TURN_STEP_RATE", "turn_step_rate", "Přešlapování – od rychlosti otáčení", "rad/s"],
		["TURN_STEP_K", "turn_step_k", "Přešlapování – rychlost nohou na rad/s otáčení", "m/s na rad/s"],
		["TURN_STEP_MIN", "turn_step_min", "Přešlapování – nejpomaleji", "m/s"],
		["TURN_STEP_MAX", "turn_step_max", "Přešlapování – nejrychleji", "m/s"],
		["ROCK_BASE", "rock_base", "Trup – houpání ve cvalu", "rad"],
		["ROCK_BOUND", "rock_bound", "Trup – houpání ve skocích (zajíc)", "rad"],
		["ROCK_PHASE", "rock_phase", "Trup – fázový posun houpání vůči kroku", "rad"],
		["TROT_BOB_K", "trot_bob_k", "Trup – pohup v klusu navíc", "×"],
		["CANTER_BOB_K", "canter_bob_k", "Trup – pohup ve cvalu (× pohup druhu)", "×"],
		["BRAKE_DECEL", "brake_decel", "Brzdění – plné vyklonění při zpomalení", "m/s²"],
		["BRAKE_FROM_V", "brake_from_v", "Brzdění – plné vyklonění až z rychlosti", "m/s"],
		["BRAKE_BLEND", "brake_blend", "Brzdění – náběh postoje", "1/s"],
		["BRAKE_PITCH", "brake_pitch", "Brzdění – předek nahoru", "rad"],
		["BRAKE_FRONT_S", "brake_front_s", "Brzdění – přední nohy proti", "rad"],
		["BRAKE_HIND_S", "brake_hind_s", "Brzdění – zadní nohy pod tělo", "rad"],
		["ACC_BLEND", "acc_blend", "Rozjezd – vyhlazení zrychlení (zvednutí předku)", "1/s"],
		["SURGE_MAX", "surge_max", "Rozjezd – strop zvednutí předku", "rad"],
		["AIR_PITCH_K", "air_pitch_k", "Skok – trup sleduje dráhu skoku (podíl)", ""],
		["AIR_FOLD", "air_fold", "Skok – ohnutí nohou ve vzduchu", ""],
		["LIE_FRONT_END", "lie_front_end", "Lehání – přední nohy do podílu", "", "Lehá předními v okně 0 … tohle.", 0.0, 1.0, 0.01],
		["LIE_HIND_START", "lie_hind_start", "Lehání – zadní nohy od podílu", "", "", 0.0, 1.0, 0.01],
		["RISE_LATE_START", "rise_late_start", "Vstávání – druhá dvojice nohou od podílu", "", "", 0.0, 1.0, 0.01],
		["RISE_EARLY_END", "rise_early_end", "Vstávání – předními (kůň): zadní do podílu", "", "", 0.0, 1.0, 0.01],
		["SIT_PITCH", "sit_pitch", "Sed na zadních – sklon trupu", "rad", "", -1.6, 0.0, 0.01],
		["SIT_PITCH_W", "sit_pitch_w", "Sed na zadních – váha sklonu", "", "", 0.0, 1.0, 0.01],
		["SIT_LIFT", "sit_lift", "Sed na zadních – zvednutí trupu (× výška ramene)", "×"],
		["SIT_BACK", "sit_back", "Sed na zadních – posun trupu dozadu (× délka)", "×"],
		["SIT_FOLD", "sit_fold", "Sed na zadních – přední nohy ohnuté", ""],
		["SIT_NECK", "sit_neck", "Sed na zadních – krk vyrovná trup", "rad"],
		["CROUCH_H", "crouch_h", "Přikrčení – výška trupu mezi stojem a lehem", "", "", 0.0, 1.0, 0.01],
		["CROUCH_FOLD", "crouch_fold", "Přikrčení – ohnutí nohou", ""],
		["CROUCH_NECK", "crouch_neck", "Přikrčení – krk", "rad"],
		["DEAD_ROLL", "dead_roll", "Uhynulé – leží na boku (náklon)", "rad"],
		["DEAD_NECK", "dead_neck", "Uhynulé – krk", "rad"],
		["BEND_MAX", "bend_max", "Páteř – největší boční ohyb", "rad"],
		["BEND_BLEND", "bend_blend", "Páteř – náběh ohybu", "1/s"],
		["BEND_V_MIN", "bend_v_min", "Páteř – ohyb × (tohle + v × k), nejméně", ""],
		["BEND_V_K", "bend_v_k", "Páteř – ohyb roste s rychlostí", "1/(m/s)"],
		["BEND_V_MAX", "bend_v_max", "Páteř – ohyb × nejvýš", ""],
		["BEND_BODY", "bend_body", "Páteř – podíl ohybu do trupu", ""],
		["BEND_NECK", "bend_neck", "Páteř – podíl ohybu do krku", ""],
		["BEND_TAIL", "bend_tail", "Páteř – podíl ohybu do ocasu", ""],
		["FLEX_PHASE", "flex_phase", "Páteř – fáze největší flexe ve cvalu", "", "", 0.0, 1.0, 0.01],
		["ACC_Y_BLEND", "acc_y_blend", "Pružiny – vyhlazení svislého zrychlení trupu", "1/s"],
		["SPRING_DT", "spring_dt", "Pružiny – nejdelší krok integrace", "s"],
		["SPRING_CLAMP", "spring_clamp", "Pružiny – nejdál od cíle", "rad"],
		["BREATH_MAX_V", "breath_max_v", "Dech – viditelný pod rychlostí", "m/s"],
		["PUFF_SPEED", "puff_speed", "Dech – zadýchá se nad rychlostí", "m/s"],
		["PUFF_UP", "puff_up", "Dech – jak rychle se zadýchá", "1/s"],
		["PUFF_DOWN", "puff_down", "Dech – jak rychle se vydýchá", "1/s"],
		["PUFF_RATE_K", "puff_rate_k", "Dech – zadýchaný: kmitočet navíc", "×"],
		["PUFF_AMP_K", "puff_amp_k", "Dech – zadýchaný: rozšíření boků navíc", "×"],
		["BREATH_Y", "breath_y", "Dech – podíl rozšíření do výšky", ""],
		["FOOTFALL_MIN_V", "footfall_min_v", "Dopady – zvuk a stopa kopyta od rychlosti", "m/s"],
		["NOD_AMP", "nod_amp", "Hlava – kývání v kroku", "rad"],
		["NOD_ROCK", "nod_rock", "Hlava – kývání ve cvalu (× houpání)", "×"],
		["NOD_HEAD", "nod_head", "Hlava – podíl kývání do hlavy", ""],
		["ROOT_HZ", "root_hz", "Hlava – rytí: rychlost kývání rypákem", "rad/s"],
		["ROOT_AMP", "root_amp", "Hlava – rytí: rozkmit", "rad"],
		["ALERT_NECK", "alert_neck", "Hlava – pozor: krk nahoru", "rad"],
		["ALERT_HEAD", "alert_head", "Hlava – pozor: hlava nahoru", "rad"],
		["GRAZE_HEAD", "graze_head", "Hlava – pastva: hlava dolů", "rad"],
		["LIE_NECK", "lie_neck", "Hlava – vleže krk × tohle", "×"],
		["LIE_NECK_W", "lie_neck_w", "Hlava – vleže váha", ""],
		["LOOK_MAX", "look_max", "Hlava – nejvíc otočená", "rad"],
		["LOOK_NECK", "look_neck", "Hlava – podíl otočení do krku", ""],
		["LOOK_HEAD", "look_head", "Hlava – podíl otočení do hlavy", ""],
		["EAR_TWITCH", "ear_twitch", "Uši – škubnutí", "rad"],
		["EAR_TWITCH_DECAY", "ear_twitch_decay", "Uši – návrat po škubnutí", "rad/s"],
		["LISTEN_BLEND", "listen_blend", "Uši – natočení ke zvuku (náběh)", "1/s"],
		["LISTEN_EAR", "listen_ear", "Uši – poslouchá: dopředu", "rad"],
		["EAR_SIDE_K", "ear_side_k", "Uši – ucho na straně zvuku víc o", "×"],
		["ALERT_EAR", "alert_ear", "Uši – pozor: nastražené", "rad"],
		["CROUCH_EAR", "crouch_ear", "Uši – přikrčený: přitisknuté", "rad"],
		["CROUCH_EAR_Z", "crouch_ear_z", "Uši – přikrčený: k hlavě (podíl)", ""],
		["TAIL_HZ", "tail_hz", "Ocas – švihání", "rad/s"],
		["TAIL_HZ_V", "tail_hz_v", "Ocas – švihání + na m/s", "rad/s na m/s"],
		["TAIL_UP_FROM", "tail_up_from", "Ocas – nahoru od rychlosti", "m/s"],
		["TAIL_UP_RANGE", "tail_up_range", "Ocas – naplno nahoru o tolik rychleji", "m/s"],
		["TAIL_BOB", "tail_bob", "Ocas – pomalé pohupování", "rad"],
		["TAIL_SWISH", "tail_swish", "Ocas – švihání do stran", "rad"],
		["TAIL_SWISH_UP", "tail_swish_up", "Ocas – vztyčený švihá méně o podíl", ""],
		["FLEE_BLEND", "flee_blend", "Útěk – náběh (ocas, zrcátko)", "1/s"],
		["FLARE_BLEND", "flare_blend", "Útěk – rozevření zrcátka", "1/s"],
	])
	_reg(QuadrupedRig.EAR_TWITCH_EVERY, "rig.", POHYB, [
		[0, "ear_twitch_every_min", "Uši – škubnutí jednou za (od)", "s"],
		[1, "ear_twitch_every_max", "Uši – škubnutí jednou za (do)", "s"],
	])
	for i in 3:
		_reg(QuadrupedRig.IK_W, "rig.", POHYB, [[i, "ik_w_%d" % i, "IK chodidel – váha nápravy: %s" % SEG_NAMES[i], "", "", 0.0, 2.0, 0.01]])
	for g in ["walk", "trot", "canter", "gallop", "bound"]:
		var gd: Dictionary = QuadrupedRig.GAITS[g]
		var nm: String = GAIT_NAMES.get(g, "skoky (zajíc)") if g != "bound" else "skoky (zajíc)"
		_reg(gd, "rig.gait_%s_" % g, POHYB, [
			["duty", "duty", "Chody – %s: podíl stojné fáze (střída)" % nm, "", "Jak dlouho je noha na zemi (podíl cyklu).", 0.05, 0.95, 0.01],
			["k", "k", "Chody – %s: kmitočet (× √(g/L)/π)" % nm, "×"],
		])
		for i in 4:
			_reg(gd["off"], "rig.gait_%s_" % g, POHYB, [[i, "off_%d" % i, "Chody – %s: posun fáze nohy %s" % [nm, LEG_NAMES[i]], "", "", 0.0, 1.0, 0.01]])


static func _animal_move() -> void:
	_reg(Animal, "animal.", POHYB, [
		["GRAVITY", "gravity", "Pohyb – gravitace (skoky, pád)", "m/s²", "Jako hráč (projekt má 20 m/s²)."],
		["FULL_R", "full_r", "LOD – plná fyzika a AI do vzdálenosti", "m"],
		["NEAR_R", "near_r", "LOD – zjednodušený pohyb (bez kolizí) do", "m"],
		["LOD_CHECK_S", "lod_check_s", "LOD – přepočet jednou za", "s"],
		["FAR_THINK_S", "far_think_s", "LOD – daleko přemýšlí jednou za", "s"],
		["THINK_FULL_S", "think_full_s", "LOD – rozhodování blízko jednou za", "s"],
		["THINK_NEAR_S", "think_near_s", "LOD – rozhodování v NEAR jednou za", "s"],
		["NEAR_ANIM_S", "near_anim_s", "LOD – animace v NEAR jednou za", "s"],
		["PUPPET_DELAY", "puppet_delay", "Síť – loutka pozadu o", "s"],
		["PUPPET_EXTRAP", "puppet_extrap", "Síť – odhad dopředu nejvýš", "s"],
		["AVOID_DECAY", "avoid_decay", "Pohyb – návrat po obcházení", "rad/s"],
		["TURN_SLOW_MIN", "turn_slow_min", "Pohyb – při ostrém úhlu rychlost nejméně ×", "", "", 0.0, 1.0, 0.01],
		["SLOPE_SLOW_FROM", "slope_slow_from", "Pohyb – do kopce zpomalí od podílu max. svahu", "", "", 0.05, 0.95, 0.01],
		["SLOPE_AVOID_S", "slope_avoid_s", "Pohyb – před příliš prudkým svahem uhne na", "s"],
		["PROBE_S", "probe_s", "Překážky – paprsky jednou za", "s"],
		["PROBE_MIN_V", "probe_min_v", "Překážky – hledá od rychlosti", "m/s"],
		["PROBE_H", "probe_h", "Překážky – paprsek ve výšce kohoutku ×", "×"],
		["PROBE_REACH_K", "probe_reach_k", "Překážky – dosah paprsku = rychlost ×", "s"],
		["PROBE_REACH_MIN", "probe_reach_min", "Překážky – dosah nejméně", "m"],
		["PROBE_REACH_MAX", "probe_reach_max", "Překážky – dosah nejvíc", "m"],
		["PROBE_SIDE_A", "probe_side_a", "Překážky – obchází o úhel", "rad"],
		["PROBE_WIDE_A", "probe_wide_a", "Překážky – nebo o širší úhel", "rad"],
		["PROBE_AVOID_S", "probe_avoid_s", "Překážky – obcházení drží", "s"],
		["JUMP_MIN_V", "jump_min_v", "Skok – přes překážku od rychlosti", "m/s"],
		["JUMP_CLEAR", "jump_clear", "Skok – nad překážkou volno o", "m"],
		["JUMP_H_K", "jump_h_k", "Skok – výška = výška druhu ×", "×"],
		["JUMP_H_ADD", "jump_h_add", "Skok – výška + tolik", "m"],
		["PRONK_V", "pronk_v", "Odrazové skoky – od rychlosti cval ×", "×"],
		["PRONK_TALL_V", "pronk_tall_v", "Odrazové skoky – ve vysoké trávě od cval ×", "×"],
		["PRONK_H_K", "pronk_h_k", "Odrazové skoky – výška = pronk ×", "×"],
		["PRONK_H_ADD", "pronk_h_add", "Odrazové skoky – výška + tolik", "m"],
		["TALL_VEG_CHECK_S", "tall_veg_check_s", "Odrazové skoky – vysoká tráva se zjišťuje jednou za", "s"],
		["STUCK_V", "stuck_v", "Zaseknutí – hlídá se od rychlosti", "m/s"],
		["STUCK_FRAC", "stuck_frac", "Zaseknutí – posun pod podíl rychlosti", "", "", 0.0, 1.0, 0.01],
		["STUCK_S", "stuck_s", "Zaseknutí – jiný směr po", "s"],
		["STUCK_HOLD", "stuck_hold", "Zaseknutí – úhyb drží", "s"],
		["STUCK_SLOW", "stuck_slow", "Zaseknutí – rychlost ×", "", "", 0.0, 1.0, 0.01],
		["ANIM_BLEND", "anim_blend", "Vzhled – prolínání pastvy, pozornosti, lehání", "1/s"],
		["LIE_BLEND_K", "lie_blend_k", "Vzhled – lehání pomaleji ×", "×"],
		["ALERT_FLEE_V", "alert_flee_v", "Vzhled – v útěku pod rychlostí hlava nahoru", "m/s"],
		["AIR_V", "air_v", "Vzhled – svislá rychlost = plně ve skoku", "m/s"],
		# pastva a přesuny
		["BAD_RAIN", "bad_rain", "Pastva – nečas: déšť nad", "", "", 0.0, 1.0, 0.01],
		["BAD_WIND", "bad_wind", "Pastva – nečas: vítr nad", "m/s"],
		["REST_MIN_S", "rest_min_s", "Pastva – odpočívá aspoň", "s"],
		["FOLLOW_REST_R", "follow_rest_r", "Pastva – člen u ležícího vůdce si lehne do", "m"],
		["FOLLOW_GAP", "follow_gap", "Pastva – člen jde za vůdcem dál než", "m"],
		["FOLLOW_K", "follow_k", "Pastva – dohánění = vzdálenost ×", "1/s"],
		["FOLLOW_MIN_K", "follow_min_k", "Pastva – dohánění nejméně krok ×", "×"],
		["FOLLOW_MAX_K", "follow_max_k", "Pastva – dohánění nejvíc klus ×", "×"],
		["SHELTER_AFTER_S", "shelter_after_s", "Pastva – mimo dobu aktivity do úkrytu po", "s"],
		["SHELTER_BAD_S", "shelter_bad_s", "Pastva – v nečase do úkrytu po", "s"],
		["SHELTER_SCORE", "shelter_score", "Pastva – úkryt = skóre stanoviště nad", "", "", 0.0, 1.0, 0.01],
		["SHELTER_R", "shelter_r", "Pastva – úkryt hledá do", "m"],
		["MOVE_CHANCE", "move_chance", "Pastva – šance přesunu jinam v okrsku", "", "", 0.0, 1.0, 0.01],
		["HOME_RETURN_K", "home_return_k", "Pastva – vrací se dál než okrsek ×", "×"],
		["HOME_WANDER_K", "home_wander_k", "Pastva – nový cíl do okrsek ×", "×"],
		["STEP_ANGLE", "step_angle", "Pastva – pár kroků: odchylka směru", "rad"],
		["ARRIVE_R", "arrive_r", "Pastva – cíl dosažen blíž než", "m"],
		["LONG_MOVE_D", "long_move_d", "Pastva – delší přesun od", "m"],
		["LONG_MOVE_K", "long_move_k", "Pastva – delší přesun rychleji ×", "×"],
	])
	_pair(Animal.PRONK_EVERY, "animal.pronk_every", POHYB, "Odrazové skoky – mezi skoky", "s")
	_pair(Animal.PRONK_TALL_EVERY, "animal.pronk_tall_every", POHYB, "Odrazové skoky – ve vysoké trávě mezi skoky", "s")
	_pair(Animal.STUCK_TURN, "animal.stuck_turn", POHYB, "Zaseknutí – úhel úhybu", "rad")
	_pair(Animal.GRAZE_HOLD, "animal.graze_hold", POHYB, "Pastva – pase se na místě", "s")
	_pair(Animal.STEP_DIST, "animal.step_dist", POHYB, "Pastva – pár kroků", "m")
	_reg(Herd, "herd.", POHYB, [
		["SLOT_SIDE", "slot_side", "Skupina – člen do strany od vůdce", "m"],
		["SLOT_SIDE_ROW", "slot_side_row", "Skupina – + do strany za každou řadu", "m"],
		["SLOT_BACK", "slot_back", "Skupina – řady za vůdcem po", "m"],
	])


## Dvojice [od, do] v poli (dřív inline `randf_range(a, b)`).
static func _pair(arr: Array, id: String, group: String, label: String, unit: String) -> void:
	_reg(arr, "", group, [
		[0, id + "_min", label + " (od)", unit],
		[1, id + "_max", label + " (do)", unit],
	])


# ------------------------------------------------------------------ Smysly a útěk

static func _senses() -> void:
	_reg(Animal, "animal.", SMYSLY, [
		["NIGHT_SIGHT", "night_sight", "Zrak – v noci ×", "", "", 0.0, 1.0, 0.01],
		["FOG_SIGHT", "fog_sight", "Zrak – v husté mlze ×", "", "", 0.0, 1.0, 0.01],
		["COVER_SIGHT", "cover_sight", "Zrak – člověk v lese ×", "", "", 0.0, 1.0, 0.01],
		["CROUCH_SIGHT", "crouch_sight", "Zrak – přikrčený člověk ×", "", "", 0.0, 1.0, 0.01],
		["STAND_HEIGHT_M", "stand_height_m", "Zrak – hráč na posedu výš než", "m"],
		["STAND_SIGHT_K", "stand_sight_k", "Zrak a čich – hráč na posedu ×", "", "", 0.0, 1.0, 0.01],
		["CAR_SIGHT", "car_sight", "Zrak – auto ×", "×"],
		["HORSE_SIGHT", "horse_sight", "Zrak – jezdec na koni ×", "×", "Koně se zvěř tolik nebojí."],
		["CAR_HEAR_BASE", "car_hear_base", "Sluch – auto: základ ×", "×"],
		["CAR_HEAR_V", "car_hear_v", "Sluch – auto: + v / tohle", "m/s"],
		["CAR_HEAR_MAX", "car_hear_max", "Sluch – auto: příspěvek rychlosti nejvýš", "×"],
		["HORSE_HEAR_V", "horse_hear_v", "Sluch – kůň: × v / tohle", "m/s"],
		["HORSE_HEAR_MIN", "horse_hear_min", "Sluch – kůň: nejméně ×", "×"],
		["HORSE_HEAR_MAX", "horse_hear_max", "Sluch – kůň: nejvíc ×", "×"],
		["STEP_HEAR_FROM", "step_hear_from", "Sluch – kroky člověka od rychlosti", "m/s"],
		["STEP_HEAR_RANGE", "step_hear_range", "Sluch – kroky naplno o tolik rychleji", "m/s"],
		["STEP_HEAR_MAX", "step_hear_max", "Sluch – kroky nejvýš ×", "×"],
		["SMELL_WIND_MIN", "smell_wind_min", "Čich – jen při větru nad", "m/s"],
		["SMELL_CONE", "smell_cone", "Čich – vítr od člověka (kosinus odchylky nad)", "", "", -1.0, 1.0, 0.01],
		["SMELL_K", "smell_k", "Čich – po větru cítí na zrak ×", "×"],
		["AWARE_BASE", "aware_base", "Pozornost – nárůst za s (základ)", "1/s"],
		["AWARE_NEAR", "aware_near", "Pozornost – nárůst zblízka navíc", "1/s"],
		["AWARE_DECAY", "aware_decay", "Pozornost – pokles, když hrozbu nevnímá", "1/s"],
		["AWARE_DECAY_NONE", "aware_decay_none", "Pozornost – pokles bez hráče", "1/s"],
		["STILL_V", "still_v", "Návyk – člověk pomalejší je „nehybný“", "m/s"],
		["CALM_K", "calm_k", "Návyk – nárůst × (1 − klid druhu × tohle)", "", "", 0.0, 1.0, 0.01],
		["HABIT_CAP", "habit_cap", "Návyk – pozornost nejvýš", "", "", 0.0, 1.0, 0.01],
		["LISTEN_AWARE", "listen_aware", "Uši – ke zdroji zvuku od pozornosti", "", "", 0.0, 1.0, 0.01],
		["APPROACH_V", "approach_v", "Hrozba – „přibližuje se“ rychleji než", "m/s"],
		["FREEZE_AWARE", "freeze_aware", "Útěk – zajíc strne od pozornosti", "", "", 0.0, 1.0, 0.01],
		["FREEZE_CALM_AWARE", "freeze_calm_aware", "Útěk – strnulý zajíc se uklidní pod", "", "", 0.0, 1.0, 0.01],
		["FREEZE_MAX_S", "freeze_max_s", "Útěk – zajíc strne nejdéle", "s"],
		["FLEE_AWARE", "flee_aware", "Útěk – při pozornosti nad", "", "", 0.0, 1.0, 0.01],
		["FLEE_PANIC_K", "flee_panic_k", "Útěk – vždy blíž než úniková vzdálenost ×", "", "", 0.0, 1.0, 0.01],
		["FLEE_MIN_S", "flee_min_s", "Útěk – trvá aspoň", "s"],
		["FLEE_SPRINT_K", "flee_sprint_k", "Útěk – plný trysk blíž než úniková ×", "×"],
		["CAR_PANIC_V", "car_panic_v", "Útěk – před autem tryskem od rychlosti auta", "m/s"],
		["HERD_ALARM_S", "herd_alarm_s", "Útěk – vyplaší stádo na", "s"],
		["CAR_FLIGHT_V", "car_flight_v", "Úniková vzdálenost – auto: × v / tohle", "m/s"],
		["CAR_FLIGHT_MIN", "car_flight_min", "Úniková vzdálenost – auto: nejméně ×", "×"],
		["CAR_FLIGHT_MAX", "car_flight_max", "Úniková vzdálenost – auto: nejvíc ×", "×"],
		["HORSE_FLIGHT", "horse_flight", "Úniková vzdálenost – jezdec na koni ×", "×"],
		["ALERT_AWARE", "alert_aware", "Pozor – od pozornosti", "", "", 0.0, 1.0, 0.01],
		["ALERT_R_APPROACH", "alert_r_approach", "Pozor – hrozba se blíží: do úniková ×", "×"],
		["ALERT_R_STILL", "alert_r_still", "Pozor – hrozba stojí: do úniková ×", "×"],
		["ALERT_CALM_S", "alert_calm_s", "Pozor – uklidní se po", "s"],
		["CALM_AWARE", "calm_aware", "Pozor – pozornost po uklidnění nejvýš", "", "", 0.0, 1.0, 0.01],
		["ALERT_COOLDOWN_S", "alert_cooldown_s", "Pozor – pak si hrozby nevšímá", "s"],
		["ALERT_END_AWARE", "alert_end_aware", "Pozor – zpět k pastvě pod pozorností", "", "", 0.0, 1.0, 0.01],
		["LOOK_BACK_R", "look_back_r", "Pozor – při pastvě se ohlíží blíž než úniková ×", "×"],
		["LOOK_RATE", "look_rate", "Pozor – otáčení hlavy k člověku", "rad/s"],
		["ZIG_R", "zig_r", "Kličky – zajíc kličkuje blíž než", "m"],
		["ZIG_HOLD", "zig_hold", "Kličky – klička drží", "s"],
		["FLEE_FAN", "flee_fan", "Směr útěku – rozestup zkoušených směrů", "rad"],
		["FLEE_PROBE", "flee_probe", "Směr útěku – posuzuje na vzdálenost", "m"],
		["FLEE_AWAY_W", "flee_away_w", "Směr útěku – váha „pryč od hrozby“", ""],
		["FLEE_FOREST_W", "flee_forest_w", "Směr útěku – váha „do lesa“", ""],
		["FLEE_EDGE_PEN", "flee_edge_pen", "Směr útěku – postih mimo mapu", ""],
		["FLEE_SLOPE_PEN", "flee_slope_pen", "Směr útěku – postih za prudký svah", ""],
		["CHARGE_R", "charge_r", "Útok bachyně – blíž než", "m"],
		["CHARGE_MAX_S", "charge_max_s", "Útok bachyně – nejdéle", "s"],
		["CHARGE_GIVEUP_R", "charge_giveup_r", "Útok bachyně – vzdá dál než", "m"],
		["CHARGE_SPEED_K", "charge_speed_k", "Útok bachyně – rychlost = cval ×", "×"],
		["CHARGE_HIT_R", "charge_hit_r", "Útok bachyně – zásah blíž než", "m"],
		["ATTACK_PUSH", "attack_push", "Útok bachyně – odhození", "m/s"],
		["ATTACK_LIFT", "attack_lift", "Útok bachyně – nadhození", "m/s"],
		["ATTACK_KNOCK_S", "attack_knock_s", "Útok bachyně – člověk leží", "s"],
		["ATTACK_DMG", "attack_dmg", "Útok bachyně – zranění", ""],
	])
	_pair(Animal.ZIG_EVERY, "animal.zig_every", SMYSLY, "Kličky – klička jednou za", "s")
	_pair(Animal.ZIG_ANGLE, "animal.zig_angle", SMYSLY, "Kličky – úhel", "rad")
	_pair(Animal.ALERT_HOLD, "animal.alert_hold", SMYSLY, "Pozor – trvá", "s")


# ------------------------------------------------------------------ Druhy

## Klíče druhu (AnimalSpecs) podle toho, co je čte: rig (všechny druhy), pohyb divoké zvěře / koně, smysly.
const SP_RIG := [
	["step_k", "Kroky – kmitočet ×", "×", "Menší zvíře = rychlejší kroky."],
	["bob", "Trup – pohup v chůzi", "m", ""],
	["froude_hyst", "Chody – hystereze prahů", "", "Dolů o chod až pod práh × (1 − tohle)."],
	["lean_k", "Náklon – do zatáčky (× atan(v·ω/g))", "×", ""],
	["surge_pitch", "Rozjezd – zvednutí předku", "rad na m/s²", ""],
	["head_stab", "Hlava – stabilizace (0 jede s trupem, 1 drží)", "", ""],
	["neck_reach", "Hlava – natažení krku při pastvě (× délka)", "×", ""],
	["ear_turn", "Uši – natočení ke zvuku", "rad", ""],
	["ear_flop", "Uši – plandání při pohupu", "rad na m/s²", ""],
	["tail_flop", "Ocas – plandání při pohupu", "rad na m/s²", ""],
	["run_head_low", "Hlava – níž v klusu a cvalu", "rad", "Divočák „buldozer“."],
	["tail_up", "Ocas – vztyčení při útěku", "rad", ""],
	["graze_angle", "Pastva – sklopení krku", "rad", ""],
]
const SP_RIG_ARR := [
	["froude", 0, "froude_trot", "Chody – Froude krok → klus", "", "Fr = v² / (g·L), L = výška ramene."],
	["froude", 1, "froude_canter", "Chody – Froude klus → cval", "", ""],
	["froude", 2, "froude_gallop", "Chody – Froude cval → trysk", "", ""],
	["spine", 0, "spine_lat", "Páteř – boční ohyb v zatáčce", "rad na rad/s", ""],
	["spine", 1, "spine_flex", "Páteř – flexe ve cvalu (× délka trupu)", "×", ""],
	["breath", 0, "breath_hz", "Dech – kmitočet v klidu", "Hz", ""],
	["breath", 1, "breath_amp", "Dech – rozšíření boků", "", ""],
	["ear_spring", 0, "ear_hz", "Uši – vlastní kmitočet pružiny", "Hz", ""],
	["ear_spring", 1, "ear_zeta", "Uši – útlum pružiny ζ", "", ""],
	["tail_spring", 0, "tail_hz", "Ocas – vlastní kmitočet pružiny", "Hz", ""],
	["tail_spring", 1, "tail_zeta", "Ocas – útlum pružiny ζ", "", ""],
]
const SP_MOVE := [
	["accel", "Pohyb – největší zrychlení", "m/s²", ""],
	["brake", "Pohyb – největší zpomalení", "m/s²", ""],
	["turn", "Pohyb – otáčení na místě", "rad/s", ""],
	["lat_acc", "Pohyb – boční zrychlení v zatáčce", "m/s²", "Určuje poloměr zatáčky v rychlosti."],
	["jump", "Skok – přeskočí výšku", "m", "0 = neskáče."],
	["max_slope", "Pohyb – nejprudší svah", "°", "Kolize (floor_max_angle) jen u nově vzniklých."],
]
const SP_WILD := [
	["mass", "Tělo – hmotnost", "kg", "Srážka s autem, energie k usmrcení střelou."],
	["pronk", "Odrazové skoky – výška při útěku", "m", "0 = neskáče (srnec 0,95)."],
	["pronk_tall", "Odrazové skoky – ve vysoké trávě ×", "×", ""],
	["sight", "Smysly – zrak (chodící člověk ve dne)", "m", ""],
	["hearing", "Smysly – sluch (běžící člověk; auto × 2)", "m", ""],
	["flight", "Smysly – úniková vzdálenost", "m", "Blíž nenechá člověka přijít."],
	["safe", "Smysly – po útěku klid ve vzdálenosti", "m", ""],
	["flee_speed", "Smysly – běžná rychlost útěku", "m/s", "Plný trysk jen zblízka / před autem."],
	["calm", "Smysly – klid (návyk na nehybného člověka)", "", ""],
	["home_range", "Pastva – poloměr okrsku", "m", ""],
]


static func _species(id: String) -> void:
	var spec := AnimalSpecs.get_spec(id)
	var group := DRUH + String(spec.get("name", id))
	var pre := "animal.%s." % id
	var wild := id in WILD
	var ride := id in RIDE
	if not spec.has("tail_up"):
		spec["tail_up"] = 0.9                     # rig čte spec.get("tail_up", 0.9) – stejná hodnota
	var gaits: Dictionary = spec["gaits"]
	for g in ["walk", "trot", "canter", "gallop"]:
		_reg(gaits, pre, group, [[g, "gait_" + g, "Chody – %s: horní mez rychlosti" % GAIT_NAMES[g], "m/s",
			"Horní hranice rychlosti chodu (starý výběr chodu, rychlosti útěku a pastvy, koně pod jezdcem)."]])
	for r in SP_RIG:
		if r[0] == "run_head_low" and float(spec.get("run_head_low", 0.0)) <= 0.0 and not wild:
			continue
		_reg(spec, pre, group, [[r[0], r[0], r[1], r[2], r[3]]])
	for r in SP_RIG_ARR:
		_reg(spec[r[0]], pre, group, [[r[1], r[2], r[3], r[4], r[5]]])
	var rf: Array = spec.get("rump_flare", [])
	if rf.size() >= 3:
		_reg(rf, pre, group, [[2, "rump_flare", "Útěk – zrcátko se rozevře (zvětšení)", "×"]])
	for side in ["front", "hind"]:
		for j in 3:
			_reg(spec[side + "_fold"], pre, group, [[j, "%s_fold_%d" % [side, j],
				"Kroky – ohnutí %s nohy při přenosu: %s" % ["přední" if side == "front" else "zadní", SEG_NAMES[j]],
				"rad", "", -3.0, 3.0, 0.01]])
	if wild or ride:
		for r in SP_MOVE:
			_reg(spec, pre, group, [[r[0], r[0], r[1], r[2], r[3]]])
	if wild:
		for r in SP_WILD:
			_reg(spec, pre, group, [[r[0], r[0], r[1], r[2], r[3]]])
		_reg(spec["group"], pre, group, [
			[0, "group_min", "Skupina – velikost od", "ks", RESTART.strip_edges()],
			[1, "group_max", "Skupina – velikost do", "ks", RESTART.strip_edges()],
		])


# ------------------------------------------------------------------ Ptáci a let

static func _birds() -> void:
	_reg(FlightModel, "bird_flight.", PTACI, [
		["RHO", "rho", "Let – hustota vzduchu", "kg/m³"],
		["G", "g", "Let – tíhové zrychlení", "m/s²"],
		["AIR_SAMPLE_S", "air_sample_s", "Let – vítr, termika a terén se zjišťují jednou za", "s"],
		["WIND_CAP", "wind_cap", "Let – vítr se počítá nejvýš do podílu cestovní rychlosti", "", "", 0.0, 2.0, 0.01],
		["TAKEOFF_S", "takeoff_s", "Vzlet – silná mávnutí po dobu", "s"],
		["TAKEOFF_THRUST", "takeoff_thrust", "Vzlet – tah ×", "×"],
		["TAKEOFF_CLIMB", "takeoff_climb", "Vzlet – stoupá aspoň stoupání ×", "×"],
		["STALL_MARGIN", "stall_margin", "Let – pod pádovou rychlostí × tohle musí mávat", "×", "", 1.0, 2.0, 0.01],
		["SINK_SLOW_V", "sink_slow_v", "Klouzání – klesavost roste pod v_pád ×", "×"],
		["SINK_SLOW_K", "sink_slow_k", "Klouzání – nárůst klesavosti", "×"],
		["TURN_GAIN", "turn_gain", "Zatáčení – úhlová rychlost = odchylka kurzu ×", "1/s", "Platí i pro starý let bez letového modelu."],
		["BANK_BLEND", "bank_blend", "Zatáčení – náběh náklonu", "1/s"],
		["DIVE_K", "dive_k", "Let – nejprudší klesání = stoupání ×", "×"],
		["CLEAR_CLIMB", "clear_climb", "Let – nízko nad terénem stoupá aspoň", "rad"],
		["GROUND_CLEAR", "ground_clear", "Let – drží se nad terénem aspoň", "m"],
		["MIN_AGL", "min_agl", "Let – nejníž nad terénem", "m"],
		["MIN_SPEED", "min_speed", "Let – nejmenší rychlost", "m/s"],
		["SPEED_GAIN", "speed_gain", "Mávání – tah dohání chtěnou rychlost", "1/s"],
		["PITCH_BLEND", "pitch_blend", "Let – náběh sklonu dráhy", "1/s"],
		["FLAP_CLIMB", "flap_climb", "Mávání – při stoupání strmějším než", "rad"],
		["FLAP_SLOW_K", "flap_slow_k", "Mávání – pod chtěnou rychlostí ×", "×", "", 0.0, 1.0, 0.01],
		["SOAR_SLOW_K", "soar_slow_k", "Plachtění – mává pod chtěnou rychlostí ×", "×", "", 0.0, 1.0, 0.01],
		["SOAR_FLAP_LIFT", "soar_flap_lift", "Plachtění – mává, když ho nenese ani", "m/s"],
		["SOAR_FLAP_AGL", "soar_flap_agl", "Plachtění – … a je níž než", "m"],
		["SOAR_CEIL_FADE", "soar_ceil_fade", "Plachtění – termika slábne pod stropem kroužení o", "m"],
		["BOID_FAR", "boid_far", "Hejno – posun od hejna dál od cíle než", "m"],
		["FLARE_DECEL", "flare_decel", "Přistání – brzdění klapkou", "m/s²"],
		["FLARE_MIN", "flare_min", "Přistání – manévr nejpozději od", "m"],
		["FLARE_ADD", "flare_add", "Přistání – vzdálenost klapky = brzdná dráha +", "m"],
		["FLARE_HOLD_K", "flare_hold_k", "Přistání – rozjetý manévr drží do vzdálenosti ×", "×"],
		["FLARE_RATE", "flare_rate", "Přistání – vztyčení klapky", "1/s"],
		["FLARE_TURN", "flare_turn", "Přistání – natáčení a vyrovnání", "1/s"],
		["LAND_SPEED_K", "land_speed_k", "Přistání – dosedací rychlost = v_pád ×", "×"],
		["LAND_REACH", "land_reach", "Přistání – dosedne blíž než", "m"],
		["INTO_WIND_MIN", "into_wind_min", "Přistání – proti větru od", "m/s"],
		["INTO_WIND_RANGE", "into_wind_range", "Přistání – proti větru naplno o", "m/s"],
		["INTO_WIND_MAX", "into_wind_max", "Přistání – proti větru nejvýš podíl", "", "", 0.0, 1.0, 0.01],
	])
	_reg(Bird, "bird.", PTACI, [
		["REST_LOOK", "rest_look", "Bidýlko – pootočení hlavy nejvýš", "rad"],
		["PREEN_TIME", "preen_time", "Bidýlko – probírání peří trvá", "s"],
		["PREEN_P", "preen_p", "Bidýlko – šance probírání peří", "", "", 0.0, 1.0, 0.01],
		["PREEN_PITCH", "preen_pitch", "Bidýlko – hlava k boku při probírání", "rad"],
		["HEAD_BLEND", "head_blend", "Bidýlko – otáčení hlavy", "1/s"],
		["FLAP_AMP", "flap_amp", "Křídla – rozkmit mávání", "rad"],
		["FLAP_AMP_SOAR", "flap_amp_soar", "Křídla – rozkmit mávání káně", "rad"],
		["TAKEOFF_FLAP_HZ", "takeoff_flap_hz", "Křídla – vzlet: kmitočet navíc", "×"],
		["TAKEOFF_FLAP_AMP", "takeoff_flap_amp", "Křídla – vzlet: rozkmit navíc", "×"],
		["FLARE_FLAP_HZ", "flare_flap_hz", "Křídla – přistání: kmitočet navíc", "×"],
		["FLARE_FLAP_AMP", "flare_flap_amp", "Křídla – přistání: rozkmit méně o", "", "", 0.0, 1.0, 0.01],
		["GLIDE_DIHEDRAL", "glide_dihedral", "Křídla – vzepětí v klouzání", "rad"],
		["GLIDE_DIHEDRAL_SOAR", "glide_dihedral_soar", "Křídla – vzepětí káně", "rad"],
		["FOLD_RATE_FLY", "fold_rate_fly", "Křídla – skládání za letu (kos)", "1/s"],
		["FOLD_RATE", "fold_rate", "Křídla – skládání po přistání", "1/s"],
		["BOUND_FOLD", "bound_fold", "Křídla – kos: složení mezi mávnutími", "", "", 0.0, 1.0, 0.01],
		["GLIDE_BLEND", "glide_blend", "Křídla – přechod do klouzání", "1/s"],
		["FLICK_DECAY", "flick_decay", "Ocas – návrat po škubnutí", "1/s"],
		["PECK_DECAY", "peck_decay", "Zem – návrat po klovnutí", "1/s"],
		["HOP_S", "hop_s", "Zem – délka skoku (kos)", "s"],
		["HOP_SPEED", "hop_speed", "Zem – skok dopředu", "m/s"],
		["HOP_YAW", "hop_yaw", "Zem – odchylka směru skoku", "rad"],
		["WALK_TURN", "walk_turn", "Zem – otáčení při chůzi", "1/s"],
		["G", "g_old", "Starý let – tíhové zrychlení", "m/s²", "Jen s vypnutým přepínačem realismu „animal_gait“."],
		["OLD_THRUST", "old_thrust", "Starý let – tah mávání", "m/s²", "Jen s vypnutým přepínačem realismu."],
		["OLD_DRAG_K", "old_drag_k", "Starý let – odpor × (v / cestovní)²", "×"],
		["OLD_CLEAR", "old_clear", "Starý let – nad terénem aspoň", "m"],
		["OLD_SOAR_K", "old_soar_k", "Starý let – káně: stoupavý proud dohání rychlost", "1/s"],
	])
	_pair(Bird.REST_LOOK_EVERY, "bird.rest_look_every", PTACI, "Bidýlko – pootočení hlavy jednou za", "s")
	_pair(Bird.FLICK_EVERY, "bird.flick_every", PTACI, "Ocas – kos škubne ocasem jednou za", "s")
	_pair(Bird.PECK_EVERY, "bird.peck_every", PTACI, "Zem – klovnutí jednou za", "s")
	_pair(Bird.HOP_EVERY, "bird.hop_every", PTACI, "Zem – kos poskočí jednou za", "s")
	for id in Bird.SPECIES:
		var s: Dictionary = Bird.SPECIES[id]
		var nm := String(s["name"]).get_slice(" ", 0)
		var pre := "bird.%s." % id
		_reg(s, pre, PTACI, [
			["cruise", "cruise", "%s – cestovní rychlost" % nm, "m/s", "Odpor letového modelu se ladí tak, aby klouzavost platila při této rychlosti."],
			["max_speed", "max_speed", "%s – největší rychlost" % nm, "m/s"],
			["flap_hz", "flap_hz", "%s – kmitočet mávání" % nm, "Hz"],
			["bank", "bank", "%s – největší náklon" % nm, "rad", "Úhlová rychlost zatáčky = g·tan(náklon)/v."],
			["climb", "climb", "%s – největší stoupání" % nm, "rad"],
		])
		if float(s.get("walk_speed", 0.0)) > 0.0:
			_reg(s, pre, PTACI, [["walk_speed", "walk_speed", "%s – chůze po zemi" % nm, "m/s"]])
		var a: Dictionary = FlightModel.SPECIES.get(id, {})
		if a.is_empty():
			continue
		var pa := "bird_aero.%s." % id
		_reg(a, pa, PTACI, [
			["mass", "mass", "%s – aerodynamika: hmotnost" % nm, "kg"],
			["area", "area", "%s – aerodynamika: plocha křídel" % nm, "m²"],
			["cl_max", "cl_max", "%s – aerodynamika: C_L max" % nm, "", "Pádová rychlost √(2·m·g / (ρ·S·C_L))."],
			["ld", "ld", "%s – aerodynamika: klouzavost L/D" % nm, ""],
			["thrust", "thrust", "%s – aerodynamika: tah mávání" % nm, "m/s²"],
		])
		_reg(a["flap"], pa, PTACI, [
			[0, "flap_min", "%s – úsek mávání (od)" % nm, "s"],
			[1, "flap_max", "%s – úsek mávání (do)" % nm, "s"],
		])
		_reg(a["glide"], pa, PTACI, [
			[0, "glide_min", "%s – úsek klouzání (od)" % nm, "s"],
			[1, "glide_max", "%s – úsek klouzání (do)" % nm, "s"],
		])


# ------------------------------------------------------------------ Hejna a murmurace

static func _flocks() -> void:
	_reg(BirdFlock, "flock.", HEJNA, [
		["SIM_R", "sim_r", "Hejna – simulace do vzdálenosti od hráče", "m"],
		["CROW_PERCH_CHANCE", "crow_perch_chance", "Vrány – šance přesunu na bidýlka", "", "", 0.0, 1.0, 0.01],
		["CROW_WINTER_ADD", "crow_winter_add", "Vrány – v zimě víc v hejnu o", "ks", RESTART.strip_edges()],
		["CROW_NIGHT_DAY", "crow_night_day", "Vrány – nocovat při denním světle pod", "", "", 0.0, 1.0, 0.01],
		["ROOST_R", "roost_r", "Vrány – nocoviště do", "m"],
		["SCATTER_R", "scatter_r", "Vrány – vyplašené hledají stromy do", "m"],
		["FIELD_R", "field_r", "Vrány – návrat na pole do", "m"],
		["CROW_SPREAD", "crow_spread", "Vrány – rozptyl po poli", "m"],
		["CROW_WANDER_P", "crow_wander_p", "Vrány – nové místo na poli (šance za s)", "1/s"],
		["PERCH_R_CROW", "perch_r_crow", "Vrány – bidýlka do", "m"],
		["KOS_SPREAD", "kos_spread", "Kos – rozptyl po zahradě", "m"],
		["KOS_WANDER_P", "kos_wander_p", "Kos – nové místo (šance za s)", "1/s"],
		["KOS_GARDEN_R", "kos_garden_r", "Kos – návrat na zahradu do", "m"],
		["KOS_LEAVE_R", "kos_leave_r", "Kos – neslétne, je-li hráč blíž než", "m"],
		["PERCH_R_KOS", "perch_r_kos", "Kos – bidýlka do", "m"],
		["SING_MORNING_H", "sing_morning_h", "Kos – zpívá ráno do", "h", "", 0.0, 24.0, 0.25],
		["SING_EVENING_H", "sing_evening_h", "Kos – zpívá večer od", "h", "", 0.0, 24.0, 0.25],
		["SING_P", "sing_p", "Kos – zpěv z bidýlka (šance za s)", "1/s"],
		["SWALLOW_DAY", "swallow_day", "Vlaštovky – létají při denním světle nad", "", "", 0.0, 1.0, 0.01],
		["SWALLOW_LOW_CLOUD", "swallow_low_cloud", "Vlaštovky – nízko při oblačnosti nad", "", "", 0.0, 1.0, 0.01],
		["SWALLOW_LOW_RAIN", "swallow_low_rain", "Vlaštovky – nízko při dešti nad", "", "", 0.0, 1.0, 0.01],
		["SWALLOW_RETARGET_P", "swallow_retarget_p", "Vlaštovky – nový cíl lovu (šance za s)", "1/s"],
		["RIDGE_R", "ridge_r", "Vlaštovky – hřeben střechy do", "m"],
		["BUZZARD_REST_EVERY", "buzzard_rest_every", "Káně – kostka na slétnutí jednou za", "s"],
		["BUZZARD_REST_CHANCE", "buzzard_rest_chance", "Káně – šance slétnout na strom", "", "", 0.0, 1.0, 0.01],
		["BUZZARD_THERMAL_R", "buzzard_thermal_r", "Káně – bublinu termiky hledá do", "m"],
		["BUZZARD_WEAK_LIFT", "buzzard_weak_lift", "Káně – slabá termika mimo bubliny", "m/s"],
		["BUZZARD_CEIL", "buzzard_ceil", "Káně – strop kroužení nad terénem", "m"],
		["THERMAL_DAY", "thermal_day", "Káně – krouží při denním světle nad", "", "", 0.0, 1.0, 0.01],
		["THERMAL_CLOUD", "thermal_cloud", "Káně – krouží při oblačnosti pod", "", "", 0.0, 1.0, 0.01],
		["THERMAL_RAIN", "thermal_rain", "Káně – krouží při dešti pod", "", "", 0.0, 1.0, 0.01],
		["SOAR_R", "soar_r", "Káně – poloměr kroužení", "m"],
		["SOAR_WANDER", "soar_wander", "Káně – střed kroužení putuje do", "m"],
		["SOAR_ALT", "soar_alt", "Káně – výška kroužení (bez bubliny)", "m"],
		["SOAR_ALT_VAR", "soar_alt_var", "Káně – kolísání výšky", "m"],
		["SOAR_BUBBLE_K", "soar_bubble_k", "Káně – v bublině kruh = poloměr bubliny ×", "×"],
		["SOAR_R_MIN", "soar_r_min", "Káně – kruh v bublině nejméně", "m"],
		["SOAR_R_MAX", "soar_r_max", "Káně – kruh v bublině nejvíc", "m"],
		["SOAR_SPEED", "soar_speed", "Káně – rychlost kroužení", "m/s"],
		["PERCH_R_KANE", "perch_r_kane", "Káně – stromy do", "m"],
		["RELOCATE_AWAY", "relocate_away", "Bidýlka – nové aspoň tak daleko od hráče", "m"],
		["CAR_SCARE_K", "car_scare_k", "Vyrušení – auto z dosahu ×", "×"],
		["APPROACH_D", "approach_d", "Přistání – zpomalí blíž než", "m"],
		["APPROACH_K", "approach_k", "Přistání – na cestovní ×", "×"],
		["LAND_TIMEOUT", "land_timeout", "Přistání – po tolika s letu přistane hned", "s"],
		["BOID_S", "boid_s", "Boidy – přepočet jednou za", "s"],
		["BOID_SEP_R", "boid_sep_r", "Boidy – oddělení blíž než", "m"],
		["BOID_MAX", "boid_max", "Boidy – největší posun cíle", "m"],
	])
	_reg(BirdFlock.BOID_K, "flock.", HEJNA, [
		[0, "boid_sep_k", "Boidy – váha oddělení", ""],
		[1, "boid_ali_k", "Boidy – váha zarovnání", ""],
		[2, "boid_coh_k", "Boidy – váha soudržnosti", ""],
	])
	_reg(BirdFlock.SCARE_GROUND, "flock.scare_ground_", HEJNA, [
		["vrana", "vrana", "Vyrušení – vrány na zemi do", "m"],
		["kos", "kos", "Vyrušení – kos na zemi do", "m"],
	])
	_reg(BirdFlock.SCARE_PERCH, "flock.scare_perch_", HEJNA, [
		["vrana", "vrana", "Vyrušení – vrány na bidýlku do", "m"],
		["kos", "kos", "Vyrušení – kos na bidýlku do", "m"],
		["vlastovka", "vlastovka", "Vyrušení – vlaštovky na hřebeni do", "m"],
		["kane", "kane", "Vyrušení – káně na stromě do", "m"],
	])
	_pair(BirdFlock.CROW_GROUND, "flock.crow_ground", HEJNA, "Vrány – procházka po poli", "s")
	_pair(BirdFlock.CROW_STAY, "flock.crow_stay", HEJNA, "Vrány – posedí na bidýlku", "s")
	_pair(BirdFlock.CROW_N, "flock.crow_n", HEJNA, "Vrány – v hejnu (nová hejna)", "ks")
	_pair(BirdFlock.BLACKBIRD_CYCLE, "flock.blackbird_cycle", HEJNA, "Kos – zem ↔ bidýlko", "s")
	_pair(BirdFlock.SWALLOW_HUNT, "flock.swallow_hunt", HEJNA, "Vlaštovky – lov", "s")
	_pair(BirdFlock.SWALLOW_SIT, "flock.swallow_sit", HEJNA, "Vlaštovky – sedí na hřebeni", "s")
	_pair(BirdFlock.SWALLOW_N, "flock.swallow_n", HEJNA, "Vlaštovky – v hejnu (nová hejna)", "ks")
	_pair(BirdFlock.SWALLOW_R, "flock.swallow_r", HEJNA, "Vlaštovky – loví v okruhu", "m")
	_pair(BirdFlock.SWALLOW_LOW, "flock.swallow_low", HEJNA, "Vlaštovky – před deštěm nad zemí", "m")
	_pair(BirdFlock.SWALLOW_HIGH, "flock.swallow_high", HEJNA, "Vlaštovky – za pěkna nad zemí", "m")
	_pair(BirdFlock.SWALLOW_SPEED, "flock.swallow_speed", HEJNA, "Vlaštovky – rychlost lovu", "m/s")
	_pair(BirdFlock.BUZZARD_STAY, "flock.buzzard_stay", HEJNA, "Káně – posedí na stromě", "s")
	_reg(Murmuration, "murmur.", HEJNA, [
		["SUN_EL_MIN", "sun_el_min", "Murmurace – slunce nad (pod tím sestoupí na nocoviště)", "°", "", -20.0, 20.0, 0.5],
		["SUN_EL_MAX", "sun_el_max", "Murmurace – slunce pod (začátek večera)", "°", "", -20.0, 30.0, 0.5],
		["CHANCE_DAYS", "chance_days", "Murmurace – hejno ve (n−1) z n večerů", "", "", 1.0, 10.0, 1.0],
		["MIN_BIRDS", "min_birds", "Murmurace – ptáků nejméně", "ks", RESTART.strip_edges()],
		["MAX_BIRDS", "max_birds", "Murmurace – ptáků nejvíc", "ks", RESTART.strip_edges()],
		["SPAWN_DIST_MIN", "spawn_dist_min", "Murmurace – vznikne od hráče nejblíž", "m"],
		["SPAWN_DIST_MAX", "spawn_dist_max", "Murmurace – vznikne od hráče nejdál", "m"],
		["SIM_R", "sim_r", "Murmurace – simulace do", "m"],
		["GONE_R", "gone_r", "Murmurace – zmizí dál než", "m"],
		["WIND_MAX", "wind_max", "Murmurace – jen při větru do", "m/s"],
		["ALT_MIN", "alt_min", "Murmurace – výška oblaku od", "m"],
		["ALT_MAX", "alt_max", "Murmurace – výška oblaku do", "m"],
		["WANDER_R", "wander_r", "Murmurace – střed oblaku bloudí do", "m"],
		["SPEED_MIN", "speed_min", "Murmurace – rychlost špačka od", "m/s"],
		["SPEED_MAX", "speed_max", "Murmurace – rychlost špačka do", "m/s"],
		["NEIGH", "neigh", "Murmurace – topologičtí sousedé", "ks", "", 1.0, 20.0, 1.0],
		["NEIGH_R", "neigh_r", "Murmurace – soused blíž než", "m"],
		["SEP_R", "sep_r", "Murmurace – oddělení blíž než", "m"],
		["W_SEP", "w_sep", "Murmurace – váha oddělení", ""],
		["W_ALI", "w_ali", "Murmurace – váha zarovnání", ""],
		["W_COH", "w_coh", "Murmurace – váha soudržnosti", ""],
		["W_HOME", "w_home", "Murmurace – přitažlivost ke středu oblaku", "1/s²"],
		["W_ALT", "w_alt", "Murmurace – přitažlivost k výšce oblaku", "1/s²"],
		["HAWK_EVERY_MIN", "hawk_every_min", "Murmurace – dravec jednou za (od)", "s"],
		["HAWK_EVERY_MAX", "hawk_every_max", "Murmurace – dravec jednou za (do)", "s"],
		["HAWK_R", "hawk_r", "Murmurace – strach z dravce do", "m"],
		["W_HAWK", "w_hawk", "Murmurace – síla úhybu před dravcem", ""],
		["HAWK_START_D", "hawk_start_d", "Murmurace – dravec nalétává z", "m"],
		["HAWK_SPEED", "hawk_speed", "Murmurace – rychlost dravce", "m/s"],
		["HAWK_S", "hawk_s", "Murmurace – průlet dravce", "s"],
		["ROOST_S", "roost_s", "Murmurace – sestup na nocoviště", "s"],
		["ROOST_SLOW_K", "roost_slow_k", "Murmurace – při sestupu nejmenší rychlost ×", "", "", 0.0, 1.0, 0.01],
		["FLAP_HZ", "flap_hz", "Murmurace – kmitočet mávání", "Hz", RESTART.strip_edges()],
	])


# ------------------------------------------------------------------ Hospodářská zvířata

static func _farm() -> void:
	_reg(Horse, "horse.", FARMA, [
		["GRAVITY", "gravity", "Kůň – gravitace (skok, pád)", "m/s²"],
		["SPOT_TURN", "spot_turn", "Kůň – otáčení na místě", "rad/s"],
		["SLOPE_SLOW_FROM", "slope_slow_from", "Kůň – do kopce zpomalí od podílu max. svahu", "", "", 0.05, 0.95, 0.01],
		["REFUSE_S", "refuse_s", "Kůň – odmítnutí svahu znovu nejdřív po", "s"],
		["HORSE_SLIP", "horse_slip", "Kůň – kopyto cítí podíl kluzkosti povrchu", "", "", 0.0, 1.0, 0.01],
		["SLIP_SLOW", "slip_slow", "Kůň – na kluzku nejvýš chod ×", "", "", 0.0, 1.0, 0.01],
		["DRIFT_GRIP", "drift_grip", "Kůň – boční smyk pod přilnavostí", "", "", 0.0, 1.0, 0.01],
		["DRIFT_K", "drift_k", "Kůň – síla bočního smyku", "×"],
		["STAMINA_GALLOP", "stamina_gallop", "Výdrž – úbytek v trysku", "1/s"],
		["STAMINA_CANTER", "stamina_canter", "Výdrž – úbytek ve cvalu", "1/s"],
		["STAMINA_REST", "stamina_rest", "Výdrž – obnova v kroku", "1/s"],
		["REST_STAND_K", "rest_stand_k", "Výdrž – ve stoje obnova ×", "×"],
		["SPRINT_MIN_STAMINA", "sprint_min_stamina", "Výdrž – trysk jen nad", "", "", 0.0, 1.0, 0.01],
		["EXHAUST", "exhaust", "Výdrž – pod tolik z trysku do cvalu", "", "", 0.0, 1.0, 0.01],
		["EXHAUST_RESET", "exhaust_reset", "Výdrž – hláška o vyčerpání znovu nad", "", "", 0.0, 1.0, 0.01],
		["JUMP_MIN_V", "jump_min_v", "Kůň – skok od rychlosti", "m/s"],
		["JUMP_H_ADD", "jump_h_add", "Kůň – skok = výška druhu +", "m"],
		["BACK_DELAY", "back_delay", "Kůň – couvá po držení S", "s"],
		["BACK_SPEED", "back_speed", "Kůň – rychlost couvání", "m/s"],
		["CRASH_V", "crash_v", "Náraz – prudké zastavení od rychlosti", "m/s"],
		["CRASH_STOP", "crash_stop", "Náraz – ubere podíl rychlosti", "", "", 0.0, 1.0, 0.01],
		["FALL_V", "fall_v", "Náraz – jezdec spadne od rychlosti", "m/s"],
		["FALL_DRUNK_V", "fall_drunk_v", "Náraz – opilý jezdec spadne od", "m/s"],
		["FALL_THROW", "fall_throw", "Náraz – odhození jezdce × rychlost", "×"],
		["FALL_DMG_K", "fall_dmg_k", "Náraz – zranění = rychlost ×", "×"],
		["STARTLE_R", "startle_r", "Hrom – poleká se do vzdálenosti blesku", "m"],
		["SOUND_SPEED", "sound_speed", "Hrom – rychlost zvuku (zpoždění)", "m/s"],
		["SPOOK_S", "spook_s", "Hrom – hlava nahoře po polekání", "s"],
		["SPOOK_DECAY", "spook_decay", "Hrom – doznívání úskoku", "m/s²"],
		["DRUNK_SLOW", "drunk_slow", "Opilý jezdec – kůň zpomalí nad", "‰"],
		["DRUNK_REFUSE", "drunk_refuse", "Opilý jezdec – kůň nevyjde nad", "‰"],
		["DRUNK_FALL_K", "drunk_fall_k", "Opilý jezdec – šance pádu za s × ‰²", "1/s"],
		["DRUNK_WOBBLE", "drunk_wobble", "Opilý jezdec – rozkmit otěží", ""],
		["WHISTLE_R", "whistle_r", "Přivolání – slyší hvízdnutí do", "m"],
		["CALL_TRAB_D", "call_trab_d", "Přivolání – klusá dál než", "m"],
		["CALL_CANTER_D", "call_canter_d", "Přivolání – cválá dál než", "m"],
		["CALL_STOP_D", "call_stop_d", "Přivolání – zastaví u hráče", "m"],
		["CALL_MAX_S", "call_max_s", "Přivolání – vzdá po", "s"],
		["CALL_WAIT_S", "call_wait_s", "Přivolání – počká u hráče", "s"],
		["CALL_CANTER_STAMINA", "call_canter_stamina", "Přivolání – cválá jen s výdrží nad", "", "", 0.0, 1.0, 0.01],
		["IDLE_WALK_K", "idle_walk_k", "Bez jezdce – popochází krokem ×", "×"],
		["FED_DECAY", "fed_decay", "Péče – ubývání sytosti", "1/s"],
		["WATER_DECAY", "water_decay", "Péče – ubývání napojení", "1/s"],
		["NEEDY_BELOW", "needy_below", "Péče – hladový / žíznivý pod", "", "", 0.0, 1.0, 0.01],
		["REGEN_FED_K", "regen_fed_k", "Péče – obnova výdrže × (1 + tohle × sytost)", ""],
		["NEEDY_REGEN", "needy_regen", "Péče – hladový: obnova ×", "×"],
		["FEED_AMOUNT", "feed_amount", "Péče – nakrmení přidá", "", "", 0.0, 1.0, 0.01],
		["WATER_AMOUNT", "water_amount", "Péče – napojení přidá", "", "", 0.0, 1.0, 0.01],
		["GROOM_BONUS_S", "groom_bonus_s", "Péče – bonus po vyčesání trvá", "s"],
		["GROOM_REGEN", "groom_regen", "Péče – vyčesaný: obnova ×", "×"],
		["GRAZE_BLEND", "graze_blend", "Vzhled – sklopení hlavy k pastvě", "1/s"],
		["RIDER_ALERT", "rider_alert", "Vzhled – s jezdcem hlava výš", "", "", 0.0, 1.0, 0.01],
		["AIR_V", "air_v", "Vzhled – svislá rychlost = plně ve skoku", "m/s"],
		["LEAN_WALK", "lean_walk", "Jezdec – předklon v kroku", "rad"],
		["LEAN_TROT", "lean_trot", "Jezdec – předklon v klusu", "rad"],
		["LEAN_CANTER", "lean_canter", "Jezdec – předklon ve cvalu", "rad"],
		["LEAN_GALLOP", "lean_gallop", "Jezdec – předklon v trysku", "rad"],
		["POST_TROT", "post_trot", "Jezdec – vysedání v klusu", "m"],
		["POST_CANTER", "post_canter", "Jezdec – sed nad sedlem ve cvalu", "m"],
		["POST_CANTER_SWING", "post_canter_swing", "Jezdec – houpání ve cvalu", "m"],
		["POST_GALLOP", "post_gallop", "Jezdec – lehký sed v trysku", "m"],
	])
	var gn := ["krok", "klus", "cval", "trysk"]
	for i in 4:
		_reg(Horse.GAIT_V_K, "horse.", FARMA, [[i, "gait_v_k_%d" % i, "Kůň – rychlost chodu %s pod jezdcem (× horní mez druhu)" % gn[i], "×", "", 0.3, 1.2, 0.01]])
	_pair(Horse.SPOOK_V, "horse.spook_v", FARMA, "Hrom – úskok stranou", "m/s")
	_pair(Horse.IDLE_EVERY, "horse.idle_every", FARMA, "Bez jezdce – popojde jednou za", "s")
	_pair(Horse.IDLE_STEP, "horse.idle_step", FARMA, "Bez jezdce – popojde o", "m")
	_reg(Paddock, "paddock.", FARMA, [
		["CARE_R", "care_r", "Výběh – krmit a napájet blíž ke žlabu než", "m"],
		["GROOM_S", "groom_s", "Výběh – čištění koně trvá", "s"],
	])
	_reg(Farm, "farm.", FARMA, [
		["MAX_ANIMALS", "max_animals", "Farma – nejvíc zvířat ve výběhu", "ks"],
		["MAX_CATCHUP_DAYS", "max_catchup_days", "Farma – dohání nejvýš dní", "dní"],
		["HELPER_FRIEND", "helper_friend", "Zabijačka – pomoc souseda od přátelství", ""],
		["STARVE_NEGLECT_H", "starve_neglect_h", "Zanedbání – od hodin hladu / žízně", "h"],
		["NEGLECT_KARMA", "neglect_karma", "Zanedbání – karma za den", ""],
		["NEGLECT_OFFENSE_P", "neglect_offense_p", "Zanedbání – šance přestupku za den", "", "", 0.0, 1.0, 0.01],
		["BREED_CHANCE", "breed_chance", "Množení – šance na kuřata za jarní den", "", "", 0.0, 1.0, 0.01],
		["BREED_MIN_HENS", "breed_min_hens", "Množení – aspoň slepic (+ kohout)", "ks"],
		["FLOCK_CAP", "flock_cap", "Množení – nejvýš slepic a kuřat", "ks"],
		["GRAZE_SELF_K", "graze_self_k", "Hlad – pasoucí se mimo zimu: úbytek ×", "", "", 0.0, 1.0, 0.01],
		["STARVE_HEALTH", "starve_health", "Zdraví – hladové ztratí za den", "", "", 0.0, 1.0, 0.01],
		["HEAL_DAY", "heal_day", "Zdraví – nasycené se uzdraví za den", "", "", 0.0, 1.0, 0.01],
		["LOW_FEED", "low_feed", "Produkty – méně při sytosti pod", "", "", 0.0, 1.0, 0.01],
		["LOW_EGG_K", "low_egg_k", "Produkty – hladová slepice: vejce ×", "", "", 0.0, 1.0, 0.01],
		["LOW_MILK_K", "low_milk_k", "Produkty – hladová dojnice: mléko ×", "", "", 0.0, 1.0, 0.01],
		["MILK_CAP_K", "milk_cap_k", "Produkty – nesebrané mléko nejvýš denní max. ×", "×"],
		["MEAT_HEALTH_MIN", "meat_health_min", "Porážka – maso při nulovém zdraví (podíl rozsahu)", "", "", 0.0, 1.0, 0.01],
	])
	_pair(Farm.CHICKS, "farm.chicks", FARMA, "Množení – kuřat ze snůšky", "ks")
	_reg(FarmAnimal, "farm_animal.", FARMA, [
		["WANDER_SPEED", "wander_speed", "Výběh – chůze zvířat", "m/s"],
		["TURN_RATE", "turn_rate", "Výběh – otáčení", "rad/s"],
		["ACCEL", "accel", "Výběh – rozchod a zastavení", "m/s²"],
		["ARRIVE_R", "arrive_r", "Výběh – místo dosaženo blíž než", "m"],
		["ESCAPE_CHECK_S", "escape_check_s", "Útěk z výběhu – kontrola jednou za", "s"],
		["ESCAPE_CHANCE", "escape_chance", "Útěk z výběhu – šance u otevřené branky", "", "", 0.0, 1.0, 0.01],
		["ESCAPE_GATE_R", "escape_gate_r", "Útěk z výběhu – jen blíž k brance než", "m"],
		["ESCAPE_ROAM_R", "escape_roam_r", "Útěk z výběhu – zatoulané se drží do", "m"],
	])
	_pair(FarmAnimal.WAIT, "farm_animal.wait", FARMA, "Výběh – postojí", "s")
	_reg(FarmSpecs, "farm.", FARMA, [["YOUNG_SCALE", "young_scale", "Chov – velikost mláděte (roste do dospělosti)", "×", "", 0.1, 1.0, 0.01]])
	for sp in FarmSpecs.ORDER:
		var d: Dictionary = FarmSpecs.DATA[sp]
		var nm := String(d.get("name", sp))
		var pre := "farm.%s." % sp
		_reg(d, pre, FARMA, [
			["hunger_day", "hunger_day", "%s – úbytek sytosti za den" % nm, "", "", 0.0, 1.0, 0.01],
			["thirst_day", "thirst_day", "%s – úbytek napojení za den" % nm, "", "", 0.0, 1.0, 0.01],
			["grow_days", "grow_days", "%s – dospělost ve věku" % nm, "dní"],
		])
		if d.has("product_chance"):
			_reg(d, pre, FARMA, [["product_chance", "product_chance", "%s – šance snesení za den" % nm, "", "", 0.0, 1.0, 0.01]])
		if d.has("winter_mult"):
			_reg(d, pre, FARMA, [["winter_mult", "winter_mult", "%s – v zimě produkty ×" % nm, "", "", 0.0, 1.0, 0.01]])
		if d.has("product_amount"):
			_reg(d["product_amount"], pre, FARMA, [
				[0, "product_min", "%s – produkt za den (od)" % nm, "ks / l"],
				[1, "product_max", "%s – produkt za den (do)" % nm, "ks / l"],
			])
		if d.has("meat_kg"):
			_reg(d["meat_kg"], pre, FARMA, [
				[0, "meat_min", "%s – maso při porážce (od)" % nm, "kg"],
				[1, "meat_max", "%s – maso při porážce (do)" % nm, "kg"],
			])
		if d.has("fat_kg"):
			_reg(d["fat_kg"], pre, FARMA, [
				[0, "fat_min", "%s – sádlo (od)" % nm, "kg"],
				[1, "fat_max", "%s – sádlo (do)" % nm, "kg"],
			])


# ------------------------------------------------------------------ Ostatní

static func _other() -> void:
	_reg(Animal, "animal.", OSTATNI, [
		["KILL_HEAD_J", "kill_head_j", "Postřelení – energie k usmrcení: hlava", "J", "Pro srnce 24 kg; těžší × (m / 24)^0,6."],
		["KILL_HEART_J", "kill_heart_j", "Postřelení – energie k usmrcení: komora", "J"],
		["KILL_REF_KG", "kill_ref_kg", "Postřelení – energie platí pro hmotnost", "kg"],
		["KILL_MASS_EXP", "kill_mass_exp", "Postřelení – exponent hmotnosti", ""],
		["WOUND_RISE_M", "wound_rise_m", "Postřelení – zalehlé se zvedne při přiblížení na", "m"],
		["WOUND_RISE_P", "wound_rise_p", "Postřelení – šance, že se zvedne", "", "", 0.0, 1.0, 0.01],
		["WOUND_RISES_MAX", "wound_rises_max", "Postřelení – zvedne se nejvýš", "×"],
		["WOUND_FLEE_K", "wound_flee_k", "Postřelení – do břicha běží útěkem ×", "×"],
		["SHOT_PANIC_S", "shot_panic_s", "Postřelení – zvíře a stádo prchá", "s"],
		["LIMP_S", "limp_s", "Postřelení – noha: kulhá", "s"],
		["LIMP_SPEED_K", "limp_speed_k", "Postřelení – noha: rychlost ×", "", "", 0.0, 1.0, 0.01],
		["LIMP_BLOOD_S", "limp_blood_s", "Postřelení – noha: krvavá stopa prvních", "s"],
		["BLOOD_STEP_M", "blood_step_m", "Postřelení – krvavá kapka každých", "m"],
		["KNOCK_KILL_V", "knock_kill_v", "Srážka s autem – usmrtí od rychlosti", "m/s"],
		["KNOCK_SMALL_KG", "knock_small_kg", "Srážka s autem – malé zvíře pod", "kg"],
		["KNOCK_SMALL_V", "knock_small_v", "Srážka s autem – malé usmrtí od", "m/s"],
		["KNOCK_MASS_REF", "knock_mass_ref", "Srážka s autem – odhození × (tohle / hmotnost)", "kg"],
		["KNOCK_MIN", "knock_min", "Srážka s autem – odhození nejméně ×", "×"],
		["KNOCK_MAX", "knock_max", "Srážka s autem – odhození nejvíc ×", "×"],
		["KNOCK_ALARM_S", "knock_alarm_s", "Srážka s autem – sražené vyplaší stádo na", "s"],
		["KNOCK_SCARE_S", "knock_scare_s", "Srážka s autem – odhozené vyplaší stádo na", "s"],
		["DEAD_FRICTION", "dead_friction", "Uhynulé – tělo dojede (zpomalení)", "m/s²"],
		["DEAD_BLEND", "dead_blend", "Uhynulé – pád na bok", "1/s"],
		["CORPSE_S", "corpse_s", "Uhynulé – bez myslivce zmizí po", "s"],
	])
	_pair(Animal.WOUND_RUN_HEART_M, "animal.wound_run_heart_m", OSTATNI, "Postřelení – srdce: ještě uběhne", "m")
	_pair(Animal.WOUND_RUN_BELLY_M, "animal.wound_run_belly_m", OSTATNI, "Postřelení – břicho: uteče", "m")
	_pair(Animal.WOUND_LIE_MIN, "animal.wound_lie_min", OSTATNI, "Postřelení – zalehlé zhyne za", "herní min")
	_pair(Animal.WOUND_RISE_RUN_M, "animal.wound_rise_run_m", OSTATNI, "Postřelení – zvednuté uteče", "m")
	_reg(Fauna, "fauna.", OSTATNI, [
		["APIARIES", "apiaries", "Rozmístění – včelnic", "ks", RESTART.strip_edges()],
		["ANTHILLS", "anthills", "Rozmístění – mravenišť", "ks", RESTART.strip_edges()],
		["CROW_FLOCKS", "crow_flocks", "Rozmístění – hejn vran", "ks", RESTART.strip_edges()],
		["BLACKBIRDS", "blackbirds", "Rozmístění – kosů", "ks", RESTART.strip_edges()],
		["SWALLOW_FLOCKS", "swallow_flocks", "Rozmístění – hejn vlaštovek", "ks", RESTART.strip_edges()],
		["BUZZARDS", "buzzards", "Rozmístění – kání", "ks", RESTART.strip_edges()],
		["ENCOUNTER_T", "encounter_t", "Setkání – sken okolí hráčů jednou za", "s"],
		["ENCOUNTER_R", "encounter_r", "Setkání – zvěř už v okruhu", "m"],
		["ENCOUNTER_NEAR", "encounter_near", "Setkání – stačí tolik kusů v okruhu", "ks"],
		["SPAWN_MIN", "spawn_min", "Setkání – nová skupina od hráče nejblíž", "m"],
		["SPAWN_MAX", "spawn_max", "Setkání – nová skupina nejdál", "m"],
		["HABITAT_MIN", "habitat_min", "Setkání – nejmenší skóre stanoviště", "", "", -1.0, 1.0, 0.01],
		["VIEW_HALF_ANGLE", "view_half_angle", "Setkání – zorný kužel hráče (±)", "°"],
		["VIEW_CLEAR", "view_clear", "Setkání – ne před očima blíž než", "m"],
		["BIRD_CHANCE", "bird_chance", "Setkání – šance hejna při skenu", "", "", 0.0, 1.0, 0.01],
		["TRANSIENT_MAX", "transient_max", "Setkání – nejvíc skupin kvůli hráčům", "ks"],
		["TRANSIENT_GONE", "transient_gone", "Setkání – zmizí dál od hráčů než", "m"],
		["VILLAGE_SETTLE", "village_settle", "Setkání – vesnice = zástavba nad", "", "", 0.0, 1.0, 0.01],
		["SITE_R", "site_r", "Setkání – místo se dolaďuje v okruhu", "m"],
		["SITE_SCORE", "site_score", "Setkání – nejmenší skóre místa", "", "", -1.0, 1.0, 0.01],
		["FORCE_MIN", "force_min", "Setkání (F2) – nejblíž", "m"],
		["FORCE_MAX", "force_max", "Setkání (F2) – nejdál", "m"],
		["FLOCK_EXIST_R", "flock_exist_r", "Setkání – hejno jen bez jiného do", "m"],
		["FLOCK_MIN", "flock_min", "Setkání – hejno nejblíž", "m"],
		["FLOCK_NEAR_MIN", "flock_near_min", "Setkání – hejno ve vesnici / F2 nejblíž", "m"],
		["FLOCK_MAX", "flock_max", "Setkání – hejno nejdál", "m"],
		["FLOCK_VILLAGE_MAX", "flock_village_max", "Setkání – hejno ve vesnici nejdál", "m"],
		["FLOCK_FORCE_MAX", "flock_force_max", "Setkání – hejno F2 nejdál", "m"],
		["HERD_SPREAD", "herd_spread", "Skupiny – členové do vzdálenosti od středu", "m"],
		["LONER_MALE_P", "loner_male_p", "Skupiny – samotářský divočák je kňour (šance)", "", "", 0.0, 1.0, 0.01],
		["PERCH_NORMAL_Y", "perch_normal_y", "Bidýlka – plocha nejméně tak vodorovná (normála y)", "", "", 0.0, 1.0, 0.01],
		["RIDGE_STEP", "ridge_step", "Bidýlka – paprsky hřebene od zásahu", "m"],
		["RANDOM_JITTER", "random_jitter", "Stanoviště – náhoda k skóre do", ""],
		["SC_FOREST_SETTLE", "sc_forest_settle", "Stanoviště – les: postih zástavby", ""],
		["SC_FOREST_ROAD", "sc_forest_road", "Stanoviště – les: postih silnice", ""],
		["SC_EDGE_WIDE", "sc_edge_wide", "Stanoviště – okraj: les v okolí ×", ""],
		["SC_EDGE_FOREST", "sc_edge_forest", "Stanoviště – okraj: méně v hustém lese ×", ""],
		["SC_EDGE_SETTLE", "sc_edge_settle", "Stanoviště – okraj: postih zástavby", ""],
		["SC_EDGE_ROAD", "sc_edge_road", "Stanoviště – okraj: postih silnice", ""],
		["SC_FIELD_WIDE", "sc_field_wide", "Stanoviště – pole: méně u lesa ×", ""],
		["SC_FIELD_SETTLE", "sc_field_settle", "Stanoviště – pole: postih zástavby", ""],
		["SC_FIELD_ROAD", "sc_field_road", "Stanoviště – pole: postih silnice", ""],
		["SC_GARDEN_SETTLE", "sc_garden_settle", "Stanoviště – zahrada: zástavba ×", ""],
		["SC_GARDEN_CORE", "sc_garden_core", "Stanoviště – zahrada: ne střed vesnice ×", ""],
		["SC_GARDEN_CORE_OFF", "sc_garden_core_off", "Stanoviště – zahrada: střed vesnice od", ""],
		["SC_GARDEN_FOREST", "sc_garden_forest", "Stanoviště – zahrada: méně v lese ×", ""],
		["SC_MEADOW_WIDE", "sc_meadow_wide", "Stanoviště – louka: les v okolí ×", ""],
		["SC_MEADOW_SETTLE", "sc_meadow_settle", "Stanoviště – louka: postih zástavby", ""],
	])
	_pair(Fauna.NEAR_RING, "fauna.near_ring", OSTATNI, "Setkání – ve vesnici hledá stanoviště", "m")
	_pair(Fauna.WINTER_GROUP_ADD, "fauna.winter_group_add", OSTATNI, "Skupiny – srnci v zimě navíc", "ks")
	_pair(Fauna.PIGLETS, "fauna.piglets", OSTATNI, "Skupiny – selat u bachyně", "ks")
	var sp_names := {"srnec": "srnci", "divocak": "divočáci", "zajic": "zajíci"}
	for sp in Fauna.POPULATION:
		_reg(Fauna.POPULATION[sp], "fauna.pop_%s_" % sp, OSTATNI, [
			[0, "groups", "Rozmístění – %s: skupin" % sp_names.get(sp, sp), "ks", RESTART.strip_edges()],
			[1, "spacing", "Rozmístění – %s: rozestup skupin" % sp_names.get(sp, sp), "m", RESTART.strip_edges()],
		])
	var hab_names := {"forest": "les", "edge": "okraj lesa", "field": "pole", "meadow": "louka", "garden": "zahrada"}
	for hab in Fauna.ENCOUNTER_SPECIES:
		var opts: Array = Fauna.ENCOUNTER_SPECIES[hab]
		for o: Array in opts:
			_reg(o, "fauna.enc_%s_" % hab, OSTATNI, [[1, String(o[0]),
				"Setkání – %s: váha druhu %s" % [hab_names.get(hab, hab), String(o[0])], "", "Váhy se sčítají k 1 (zbytek = první druh).", 0.0, 1.0, 0.01]])
	_reg(AntHill, "anthill.", OSTATNI, [
		["ANT_SPEED", "ant_speed", "Mravenci – rychlost", "m/s"],
		["ACTIVE_TEMP", "active_temp", "Mravenci – venku nad teplotou", "°C", "", -10.0, 30.0, 0.5],
		["ACTIVE_SNOW", "active_snow", "Mravenci – venku pod sněhem", "", "", 0.0, 1.0, 0.01],
		["SIM_R", "sim_r", "Mravenci – hýbou se do vzdálenosti", "m"],
		["BITE_MARGIN", "bite_margin", "Mravenci – kousnou na kupě (poloměr +)", "m"],
		["BITE_S", "bite_s", "Mravenci – kousnutí jednou za", "s"],
		["BITE_DMG", "bite_dmg", "Mravenci – zranění za kousnutí", ""],
	])
	_reg(Apiary, "apiary.", OSTATNI, [
		["FORAGE_R", "forage_r", "Včely – květy do vzdálenosti", "m", RESTART.strip_edges()],
		["BEE_SPEED", "bee_speed", "Včely – rychlost letu", "m/s"],
		["SIM_R", "sim_r", "Včely – simulace do", "m"],
		["ACT_DAY_K", "act_day_k", "Včely – aktivita: denní světlo ×", ""],
		["ACT_DAY_OFF", "act_day_off", "Včely – aktivita: − tolik", ""],
		["ACT_TEMP_MIN", "act_temp_min", "Včely – vylétají od teploty", "°C", "", -5.0, 30.0, 0.5],
		["ACT_TEMP_RANGE", "act_temp_range", "Včely – naplno o tolik °C výš", "°C"],
		["ACT_RAIN_LO", "act_rain_lo", "Včely – déšť: útlum od", "", "", 0.0, 1.0, 0.01],
		["ACT_RAIN_HI", "act_rain_hi", "Včely – déšť: úplně do", "", "", 0.0, 1.0, 0.01],
		["ACT_WIND_LO", "act_wind_lo", "Včely – vítr: útlum od", "m/s"],
		["ACT_WIND_HI", "act_wind_hi", "Včely – vítr: úplně do", "m/s"],
		["ACT_BLOOM_K", "act_bloom_k", "Včely – kvetení ×", ""],
		["ACT_BLOOM_OFF", "act_bloom_off", "Včely – kvetení + tolik", ""],
		["WOBBLE", "wobble", "Včely – kličkování letu", "m/s"],
		["STEER_BLEND", "steer_blend", "Včely – zatáčení k cíli", "1/s"],
		["ANGRY_N", "angry_n", "Rozzlobené včely – nejvíc najednou", "ks"],
		["ATTACK_SPEED", "attack_speed", "Rozzlobené včely – rychlost", "m/s"],
		["ATTACK_BLEND", "attack_blend", "Rozzlobené včely – zatáčení", "1/s"],
		["STING_R", "sting_r", "Rozzlobené včely – bodne blíž než", "m"],
		["STING_RATE", "sting_rate", "Rozzlobené včely – šance bodnutí za s", "1/s"],
		["STING_DMG", "sting_dmg", "Rozzlobené včely – zranění bodnutím", ""],
		["DISTURB_R", "disturb_r", "Rozzlobené včely – u česna blíž než", "m"],
		["DISTURB_S", "disturb_s", "Rozzlobené včely – déle než", "s"],
		["DISTURB_DECAY", "disturb_decay", "Rozzlobené včely – rozrušení opadá ×", "×"],
		["ANGRY_S", "angry_s", "Rozzlobené včely – zlobí se", "s"],
		["ANGRY_GIVEUP_R", "angry_giveup_r", "Rozzlobené včely – vzdají dál než", "m"],
		["REINFORCE_P", "reinforce_p", "Rozzlobené včely – posila z úlu (šance za snímek)", "", "", 0.0, 1.0, 0.01],
	])
	_pair(Apiary.HIVE_WAIT, "apiary.hive_wait", OSTATNI, "Včely – čekání v úlu", "s")
	_pair(Apiary.FLOWER_WAIT, "apiary.flower_wait", OSTATNI, "Včely – na květu", "s")
	_pair(Apiary.HOME_WAIT, "apiary.home_wait", OSTATNI, "Včely – po návratu v úlu (÷ aktivita)", "s")
	_pair(Apiary.STING_COOL, "apiary.sting_cool", OSTATNI, "Rozzlobené včely – mezi bodnutími", "s")
	_reg(Hunter, "hunter.", OSTATNI, [
		["FEEDER_R", "feeder_r", "Krmelec – táhne zvěř z okruhu", "m"],
		["FEEDER_SNOW", "feeder_snow", "Krmelec – i mimo zimu při sněhu nad", "", "", 0.0, 1.0, 0.01],
		["FEEDER_FULL_H", "feeder_full_h", "Krmelec – naplněný táhne zvěř", "h"],
		["FEED_FROM", "feed_from", "Krmelec – zvěř k němu od hodiny", "h", "", 0.0, 24.0, 0.25],
		["FEED_TO", "feed_to", "Krmelec – do hodiny", "h", "", 0.0, 24.0, 0.25],
		["FEEDER_TICK", "feeder_tick", "Krmelec – přepočet jednou za", "s"],
		["FEEDER_HOME_SPREAD", "feeder_home_spread", "Krmelec – domov skupiny s rozptylem", "m"],
		["FEEDER_GO_R", "feeder_go_r", "Krmelec – vůdce vyrazí dál než", "m"],
		["FEEDER_GO_SPREAD", "feeder_go_spread", "Krmelec – cíl s rozptylem", "m"],
		["PICKUP_WAIT_S", "pickup_wait_s", "Myslivec – dorazí pro sraženou zvěř za", "s"],
		["PICKUP_FROM_D", "pickup_from_d", "Myslivec – přichází z", "m"],
		["PICKUP_LOAD_S", "pickup_load_s", "Myslivec – nakládá", "s"],
		["PICKUP_QUIET_D", "pickup_quiet_d", "Myslivec – odveze bez procházky dál od hráče než", "m"],
		["WALK_SPEED", "walk_speed", "Myslivec – chůze", "m/s"],
		["SMOKE_S", "smoke_s", "Včelař – okuřování úlů trvá", "s"],
	])
	_reg(Gamekeeper, "gamekeeper.", OSTATNI, [
		["WALK_SPEED", "walk_speed", "Hajný – obchůzka", "m/s"],
		["RUN_SPEED", "run_speed", "Hajný – k místu činu", "m/s"],
		["PATROL_R", "patrol_r", "Hajný – okruh obchůzky", "m"],
		["WATER_PATROL_R", "water_patrol_r", "Rybářská stráž – úseky vody do", "m"],
		["ARRIVE_R", "arrive_r", "Hajný – cíl obchůzky blíž než", "m"],
		["HEAR_SHOT_R", "hear_shot_r", "Hajný – slyší výstřel do", "m"],
		["HEAR_P", "hear_p", "Hajný – šance, že vyrazí", "", "", 0.0, 1.0, 0.01],
		["INVESTIGATE_S", "investigate_s", "Hajný – hledá místo činu", "s"],
		["CONTROL_R", "control_r", "Hajný – kontrola dokladů do", "m"],
		["CHECK_CD_MIN", "check_cd_min", "Hajný – téhož hráče znovu po", "herní min"],
		["CARCASS_NEAR_R", "carcass_near_r", "Hajný – úlovek u hráče do", "m"],
	])
