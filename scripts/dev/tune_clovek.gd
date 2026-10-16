## M8.D2b: menu pro vývojáře – kategorie **Člověk**: pohyb hráče (chůze, sprint, skok, skluz, plavání, pád, skateboard),
## tělo (`BodyState`: výdrž, hlad, chlad, mokro, zranění, opilost), chůze a postoj (`Gait`, `Humanoid`), NPC a vesničané
## (`Villager`, `Npc`, `NpcGrow`) a pes (`Dog`). Úplný seznam konstant, které ovlivňují chování (ne vzhled, texty, zvuk).
## Výchozí hodnoty se berou z kódu (`DevTune.tune` čte současnou `static var`) – chování ve výchozím stavu beze změny.
## Za snímek systémy čtou jen své `static var` (Humanoid / Gait / Villager jsou nejdražší skripty – žádný registr).
extends RefCounted

const POHYB := "Člověk/Pohyb hráče"
const TELO := "Člověk/Tělo"
const CHUZE := "Člověk/Chůze a postoj"
const NPC := "Člověk/NPC a vesničané"
const PES := "Člověk/Pes"


## Zaregistruje řádky tabulky: [vlastnost, id, popisek, jednotka, nápověda, (min, max)]. Bez min/max se rozsah
## posuvníku odvodí z výchozí hodnoty (0 … 3×, záporné zrcadlově), krok podle řádu hodnoty.
static func rows(target: Variant, prefix: String, group: String, list: Array) -> void:
	for r in list:
		var v: Variant = target.get(r[0]) if target is Object else (target as Dictionary).get(r[0])
		var lo := 0.0
		var hi := 1.0
		if r.size() > 6:
			lo = float(r[5])
			hi = float(r[6])
		else:
			var fv := float(v)
			if fv > 0.0:
				hi = fv * 3.0
			elif fv < 0.0:
				lo = fv * 3.0
				hi = 0.0
			if v is int:
				hi = maxf(hi, float(v) + 5.0)
		DevTune.tune(target, r[0], prefix + String(r[1]), group, String(r[2]), lo, hi, step_for(v), String(r[4]),
			String(r[3]))


## Krok posuvníku podle řádu výchozí hodnoty (4,6 → 0,01; 0,0009 → 0,00001; 1800 → 10).
static func step_for(v: Variant) -> float:
	if v is int:
		return 1.0
	var a := absf(float(v))
	if a < 1.0e-9:
		return 0.01
	return maxf(pow(10.0, floorf(log(a) / log(10.0)) - 2.0), 1.0e-6)


static func register_all() -> void:
	_pohyb()
	_telo()
	_chuze()
	_npc()
	_pes()


# ------------------------------------------------------------------ Pohyb hráče (`Player`)

static func _pohyb() -> void:
	rows(Player, "player.", POHYB, [
		# rychlosti a zrychlení
		["walk_speed", "walk_speed", "Rychlost – chůze", "m/s", "Cílová rychlost chůze (× tělo, náklad, modifikátory)."],
		["sprint_speed", "sprint_speed", "Rychlost – sprint", "m/s", "Shift; stojí výdrž."],
		["crouch_speed", "crouch_speed", "Rychlost – v přikrčení", "m/s", ""],
		["ground_accel", "ground_accel", "Zrychlení – rozjezd na zemi", "m/s²", "× přilnavost povrchu."],
		["ground_decel", "ground_decel", "Zrychlení – brzdění na zemi (bez vstupu)", "m/s²", ""],
		["turn_accel", "turn_accel", "Zrychlení – obrat proti směru pohybu", "m/s²", ""],
		["air_accel", "air_accel", "Zrychlení – řízení ve vzduchu", "m/s²", ""],
		["AIR_DRAG", "air_drag", "Zrychlení – odpor vzduchu ve skoku", "1/s", ""],
		["WALK_GRIP_MIX", "walk_grip_mix", "Přilnavost – podrážky na mokru / ledu", "×",
			"Kolik ze snížené přilnavosti povrchu (Svět → Povrchy) dostane chodec: 0 = vůbec, 1 = jako pneu.", 0.0, 1.0],
		["WALK_FLOOR_ANGLE", "floor_angle_deg", "Svah – nejstrmější schůdný", "°",
			"Strmější plocha není podlaha. Projeví se po startu hry / seskoku ze skateboardu.", 10.0, 89.0],
		["STEEP_DEG", "steep_deg", "Svah – sjíždění od sklonu", "°", "", 5.0, 89.0],
		["STEEP_SLIDE_K", "steep_slide_k", "Svah – zrychlení sjíždění", "× g", ""],
		["BUSY_SPEED", "busy_speed", "Rychlost – při pití / jídle nejvýš", "m/s", ""],
		["AIM_SPEED_MULT", "aim_speed_mult", "Rychlost – při míření zbraní", "×", "", 0.0, 1.0],
		["CARRY_KG", "carry_kg", "Náklad – nosnost v kapsách", "kg", "Víc = přetížený (pomalejší, bez sprintu)."],
		["OVERLOAD_SPEED_MULT", "overload_speed_mult", "Náklad – rychlost při přetížení", "×", "", 0.0, 1.0],
		# skok a gravitace
		["jump_velocity", "jump_velocity", "Skok – rychlost výskoku", "m/s", "× tělo (obezita)."],
		["gravity", "gravity", "Skok – gravitace hráče", "m/s²", "Vlastní gravitace postavy (Svět → Gravitace je pro předměty)."],
		["fall_multiplier", "fall_multiplier", "Skok – těžší pád (sestup)", "×", "Násobek gravitace při padání."],
		["low_jump_multiplier", "low_jump_multiplier", "Skok – krátký skok (puštěný Mezerník)", "×", ""],
		["coyote_time", "coyote_time", "Skok – coyote time (po sejití z hrany)", "s", ""],
		["jump_buffer_time", "jump_buffer_time", "Skok – předstih stisku (jump buffer)", "s", ""],
		["TERMINAL_VY", "terminal_vy", "Pád – nejvyšší rychlost pádu", "m/s", ""],
		# skluz a přikrčení
		["slide_boost", "slide_boost", "Skluz – přídavek rychlosti na začátku", "m/s", ""],
		["slide_friction", "slide_friction", "Skluz – tření", "m/s²", ""],
		["SLIDE_MIN_V", "slide_min_v", "Skluz – od rychlosti", "m/s", "Přikrčení ze sprintu nad touto rychlostí = skluz."],
		["SLIDE_END_V", "slide_end_v", "Skluz – končí pod rychlostí", "m/s", ""],
		["SLIDE_MAX_S", "slide_max_s", "Skluz – nejdelší", "s", ""],
		["SLIDE_DOWNHILL", "slide_downhill", "Skluz – zrychlení z kopce", "× g", ""],
		["SLIDE_GRIP_MIX", "slide_grip_mix", "Skluz – kluzký povrch ho prodlouží", "×", "", 0.0, 1.0],
		["SLIDE_STEER", "slide_steer", "Skluz – řízení", "m/s²", ""],
		["SLIDE_JUMP_BONUS", "slide_jump_bonus", "Skluz – vyšší výskok ze skluzu", "m/s", ""],
		["STAND_HEIGHT", "stand_height", "Postava – výška kapsle ve stoje", "m", "", 1.2, 2.4],
		["CROUCH_HEIGHT", "crouch_height", "Postava – výška kapsle v přikrčení", "m", "", 0.6, 1.8],
		["CROUCH_RATE", "crouch_rate", "Postava – rychlost přikrčení / vstávání", "m/s", ""],
		# výdrž
		["STAMINA_SPRINT_DRAIN", "stamina_drain", "Výdrž – úbytek při sprintu", "1/s", "× tělo (obezita, kouření, chlad)."],
		["STAMINA_REGEN", "stamina_regen", "Výdrž – obnova", "1/s", ""],
		["STAMINA_REGEN_DELAY", "stamina_regen_delay", "Výdrž – prodleva před obnovou", "s", ""],
		["STAMINA_UNLOCK", "stamina_unlock", "Výdrž – sprint znovu od", "× max.", "Vyčerpaný hráč smí sprintovat až od tohoto podílu.", 0.0, 1.0],
		["SPRINT_DETECT", "sprint_detect", "Výdrž – „sprintuje“ nad chůzí o", "m/s", "Pro dovednosti, zvuky a svědky."],
		# voda
		["SWIM_DEPTH", "swim_depth", "Plavání – od hloubky", "m", ""],
		["SWIM_SPEED", "swim_speed", "Plavání – rychlost", "m/s", ""],
		["SWIM_SPRINT", "swim_sprint", "Plavání – rychlé (Shift)", "m/s", ""],
		["SWIM_SPRINT_DRAIN", "swim_sprint_drain", "Plavání – úbytek výdrže při rychlém", "1/s", ""],
		["SWIM_VY", "swim_vy", "Plavání – svislá rychlost (nahoru / potopit)", "m/s", ""],
		["SWIM_VY_ACCEL", "swim_vy_accel", "Plavání – změna svislé rychlosti", "m/s²", ""],
		["BREATH_MAX", "breath_max", "Plavání – dech pod hladinou", "s", ""],
		["BREATH_REGEN", "breath_regen", "Plavání – obnova dechu", "s/s", ""],
		["HEAD_H", "head_h", "Plavání – výška hlavy nad nohama", "m", "Pod hladinou ubývá dech.", 0.8, 2.2],
		["DROWN_DPS", "drown_dps", "Plavání – topení: ztráta zdraví", "HP/s", ""],
		["WADE_SLOW_DEPTH", "wade_slow_depth", "Brodění – hloubka nejsilnějšího brzdění", "m", ""],
		["WADE_SLOW_MIN", "wade_slow_min", "Brodění – rychlost v plné hloubce", "×", "", 0.0, 1.0],
		["WADE_WET_FROM", "wade_wet_from", "Brodění – promáčí od hloubky", "m", ""],
		["WADE_WET_K", "wade_wet_k", "Brodění – promoknutí = hloubka ×", "×", ""],
		# pád, nárazy, strkání
		["SAFE_FALL_HEIGHT", "safe_fall_h", "Pád – bezpečná výška", "m", ""],
		["FALL_HURT_PER_M", "fall_hurt_per_m", "Pád – zranění za metr nad bezpečnou výškou", "HP/m", ""],
		["FALL_DOWN_S", "fall_down_s", "Pád – ležení po tvrdém dopadu", "s", ""],
		["FALL_DOWN_PER_M", "fall_down_per_m", "Pád – ležení navíc za metr", "s/m", ""],
		["KNOCK_HURT_K", "knock_hurt_k", "Sražení autem – zranění = k × v²", "HP·s²/m²", ""],
		["KNOCK_LIGHT_V", "knock_light_v", "Sražení autem – lehké pod rychlostí", "m/s", ""],
		["KNOCK_LIGHT_S", "knock_light_s", "Sražení autem – ležení po lehkém", "s", ""],
		["KNOCK_FALL_S", "knock_fall_s", "Sražení autem – ležení", "s", ""],
		["KNOCK_FALL_PER_V", "knock_fall_per_v", "Sražení autem – ležení navíc za m/s", "s·s/m", ""],
		["FALLEN_DECEL", "fallen_decel", "Pád – ležící dobrzdí na zemi", "m/s²", ""],
		["FALLEN_AIR_DECEL", "fallen_air_decel", "Pád – ležící ve vzduchu", "m/s²", ""],
		["BOTTLE_BREAK_P", "bottle_break_p", "Pád – šance rozbití lahve", "", "", 0.0, 1.0],
		["BOTTLE_BREAK_PER_V", "bottle_break_per_v", "Pád – rozbití lahve navíc za m/s", "1/(m/s)", ""],
		["BOTTLE_BREAK_MAX", "bottle_break_max", "Pád – strop šance rozbití lahve", "", "", 0.0, 1.0],
		["PUSH_K", "push_k", "Strkání – impulz do předmětu", "× v", ""],
		["PUSH_UP_K", "push_up_k", "Strkání – svislá složka", "×", ""],
		["PUSH_HIT_K", "push_hit_k", "Strkání – síla nárazu (rozbití, zvuk)", "× v", ""],
		# opilost v pohybu
		["DRUNK_DELAY_K", "drunk_delay_k", "Opilost – zpoždění reakcí na 1 ‰", "s/‰", ""],
		["DRUNK_DELAY_MAX", "drunk_delay_max", "Opilost – strop zpoždění reakcí", "s", ""],
		["DRUNK_DRIFT_FROM", "drunk_drift_from", "Opilost – drift do stran od", "‰", ""],
		["DRUNK_DRIFT_K", "drunk_drift_k", "Opilost – síla driftu na ‰", "×", ""],
		["DRUNK_DRIFT_SIDE", "drunk_drift_side", "Opilost – drift do stran", "m/s", ""],
		["DRUNK_DRIFT_FWD", "drunk_drift_fwd", "Opilost – drift dopředu / dozadu", "m/s", ""],
		["DRUNK_ACCEL_LOSS", "drunk_accel_loss", "Opilost – horší rozjezd", "×", "Při plné opilosti (drunk_level 1).", 0.0, 1.0],
		["DRUNK_BRAKE_LOSS", "drunk_brake_loss", "Opilost – horší brzdění a obrat", "×", "", 0.0, 1.0],
		["DRUNK_JUMP_FALL_FROM", "drunk_jump_fall_from", "Opilost – pád po skoku od", "‰", ""],
		["DRUNK_JUMP_FALL_K", "drunk_jump_fall_k", "Opilost – šance pádu po skoku na ‰", "1/‰", ""],
		["DRUNK_LAND_PROMILE", "drunk_land_promile", "Opilost – pád po dopadu od", "‰", ""],
		["DRUNK_LAND_DROP", "drunk_land_drop", "Opilost – pád po dopadu z výšky od", "m", ""],
		["DRUNK_LAND_BASE", "drunk_land_base", "Opilost – pád po dopadu: základ šance", "‰", ""],
		["DRUNK_LAND_K", "drunk_land_k", "Opilost – pád po dopadu: šance na ‰", "1/‰", ""],
		["DRUNK_LAND_S", "drunk_land_s", "Opilost – ležení po opilém dopadu", "s", ""],
		["WALL_BUMP_V", "wall_bump_v", "Opilost – náraz do zdi od rychlosti", "m/s", ""],
		["WALL_BUMP_PROMILE", "wall_bump_promile", "Opilost – náraz do zdi od", "‰", ""],
		["WALL_BUMP_CD", "wall_bump_cd", "Opilost – rozestup nárazů do zdi", "s", ""],
		["WALL_BUMP_HURT", "wall_bump_hurt", "Opilost – zranění nárazem za m/s", "HP·s/m", ""],
		["WALL_BUMP_FALL_PROMILE", "wall_bump_fall_promile", "Opilost – po nárazu upadne od", "‰", ""],
		["WALL_BUMP_FALL_S", "wall_bump_fall_s", "Opilost – ležení po nárazu", "s", ""],
		["STUMBLE_PROMILE", "stumble_promile", "Zakopnutí – od opilosti", "‰", ""],
		["STUMBLE_RATE", "stumble_rate", "Zakopnutí – šance za s na ‰", "1/(s·‰)", ""],
		["STUMBLE_SPEED_K", "stumble_speed_k", "Zakopnutí – navíc za m/s rychlosti", "×", ""],
		["STUMBLE_SPRINT_K", "stumble_sprint_k", "Zakopnutí – při sprintu", "×", ""],
		["STUMBLE_SLOPE", "stumble_slope", "Zakopnutí – svah od sklonu", "rad", ""],
		["STUMBLE_SLOPE_K", "stumble_slope_k", "Zakopnutí – na svahu", "×", ""],
		["STUMBLE_IDLE_K", "stumble_idle_k", "Zakopnutí – ve stoje", "×", "", 0.0, 1.0],
		["STUMBLE_IDLE_PROMILE", "stumble_idle_promile", "Zakopnutí – ve stoje naplno od", "‰", ""],
		["STUMBLE_FORCE_S", "stumble_force_s", "Zakopnutí – nejdéle bez zakopnutí (silná opilost)", "s", ""],
		["STUMBLE_FORCE_PROMILE", "stumble_force_promile", "Zakopnutí – silná opilost od", "‰", ""],
		["STUMBLE_CD", "stumble_cd", "Zakopnutí – rozestup", "s", ""],
		["STUMBLE_FALL_PROMILE", "stumble_fall_promile", "Zakopnutí – pádem končí od", "‰", ""],
		["STUMBLE_FALL_V", "stumble_fall_v", "Zakopnutí – pádem končí od rychlosti", "m/s", ""],
		["STUMBLE_HURT_FROM", "stumble_hurt_from", "Zakopnutí – zranění od rychlosti", "m/s", ""],
		["STUMBLE_HURT_K", "stumble_hurt_k", "Zakopnutí – zranění za m/s", "HP·s/m", ""],
		["STUMBLE_FALL_S", "stumble_fall_s", "Zakopnutí – ležení", "s", ""],
		["STUMBLE_FALL_PER_PROMILE", "stumble_fall_per_promile", "Zakopnutí – ležení navíc za ‰", "s/‰", ""],
		["STAGGER_V", "stagger_v", "Zakopnutí – boční zavrávorání", "m/s", ""],
		# energie z pohybu (výdej kcal do těla)
		["KCAL_WALK", "kcal_walk", "Výdej – chůze", "kcal/h", "Herní hodiny; spaluje tělo (hmotnost)."],
		["KCAL_SPRINT", "kcal_sprint", "Výdej – běh", "kcal/h", ""],
		["KCAL_MOVE_V", "kcal_move_v", "Výdej – chůze od rychlosti", "m/s", ""],
		["KCAL_RUN_V", "kcal_run_v", "Výdej – běh od rychlosti", "m/s", ""],
		["SNOW_WET_K", "snow_wet_k", "Počasí – sněžení promáčí", "× déšť", "", 0.0, 1.0],
		# skateboard
		["BOARD_PUSH", "board_push", "Skateboard – odraz (přídavek rychlosti)", "m/s", ""],
		["BOARD_PUSH_CD", "board_push_cd", "Skateboard – rozestup odrazů", "s", ""],
		["BOARD_PUSH_GRIP_MIN", "board_push_grip_min", "Skateboard – nejmenší účinnost odrazu na kluzkém", "×", "", 0.0, 1.0],
		["BOARD_MAX_FLAT", "board_max_flat", "Skateboard – nejvyšší rychlost odrazem", "m/s", ""],
		["BOARD_DRAG", "board_drag", "Skateboard – valivý odpor", "m/s²", ""],
		["BOARD_ROUGH_DRAG", "board_rough_drag", "Skateboard – odpor navíc na nerovném", "m/s²", "× (1 − přilnavost)."],
		["BOARD_BRAKE", "board_brake", "Skateboard – brzda patou", "m/s²", ""],
		["BOARD_TURN", "board_turn", "Skateboard – zatáčení", "rad/s", ""],
		["BOARD_TURN_FULL_V", "board_turn_full_v", "Skateboard – zatáčí naplno od rychlosti", "m/s", ""],
		["BOARD_SIDE_DAMP", "board_side_damp", "Skateboard – útlum bočního skluzu", "m/s²", ""],
		["BOARD_G", "board_g", "Skateboard – gravitace z kopce", "m/s²", ""],
		["BOARD_OLLIE_VY", "board_ollie_vy", "Skateboard – výskok ollie", "m/s", ""],
		["BOARD_OLLIE_PTS", "board_ollie_pts", "Skateboard – body za ollie", "b", ""],
		["BOARD_LAND_DEG", "board_land_deg", "Skateboard – čistý dopad do náklonu", "°", "", 0.0, 90.0],
		["BOARD_TRICK_AIR_S", "board_trick_air_s", "Skateboard – ollie se počítá od doby ve vzduchu", "s", ""],
		["BOARD_WOBBLE_V", "board_wobble_v", "Skateboard – kmitání od rychlosti", "m/s", ""],
		["BOARD_WOBBLE_HZ", "board_wobble_hz", "Skateboard – kmitání: frekvence", "rad/s", ""],
		["BOARD_WOBBLE_AMP", "board_wobble_amp", "Skateboard – kmitání: síla", "m/s²", ""],
		["BOARD_FALL_V", "board_fall_v", "Skateboard – pád nad rychlostí", "m/s", ""],
		["BOARD_WALL_V", "board_wall_v", "Skateboard – náraz do zdi = pád od", "m/s", ""],
		["BOARD_ROUGH_FALL_V", "board_rough_fall_v", "Skateboard – přepadnutí na nerovném od", "m/s", ""],
		["BOARD_ROUGH_FALL_GRIP", "board_rough_fall_grip", "Skateboard – nerovný povrch pod přilnavostí", "", "", 0.0, 1.0],
		["BOARD_TRIP_S", "board_trip_s", "Skateboard – ležení po přepadnutí", "s", ""],
		["BOARD_CRASH_S", "board_crash_s", "Skateboard – ležení po pádu z rychlosti", "s", ""],
		["BOARD_FLOOR_ANGLE", "board_floor_deg", "Skateboard – nejstrmější „podlaha“ (U-rampa)", "°", "Projeví se při dalším naskočení.", 10.0, 89.0],
	])


# ------------------------------------------------------------------ Tělo (`BodyState`)

static func _telo() -> void:
	rows(BodyState, "body.", TELO, [
		# postava a energie
		["HEIGHT_M", "height_m", "Postava – výška (pro BMI)", "m", "", 1.4, 2.2],
		["OBESITY_GAIN", "obesity_gain", "Hmotnost – herní zrychlení tloustnutí", "×", ""],
		["KCAL_PER_KG", "kcal_per_kg", "Hmotnost – kcal na 1 kg tuku", "kcal/kg", ""],
		["WEIGHT_MIN", "weight_min", "Hmotnost – nejnižší", "kg", ""],
		["FOOD_FULL_KCAL", "food_full_kcal", "Hlad – plný žaludek", "kcal", ""],
		["DIGEST_KCAL_H", "digest_kcal_h", "Hlad – trávení", "kcal/h", ""],
		["BMR_KCAL_H", "bmr_kcal_h", "Hlad – bazální výdej (bdělost)", "kcal/h", ""],
		["BMR_SLEEP_KCAL_H", "bmr_sleep_kcal_h", "Hlad – bazální výdej ve spánku", "kcal/h", ""],
		["OVEREAT_KCAL", "overeat_kcal", "Hlad – přejedení od", "kcal", ""],
		["OVEREAT_PROMILE", "overeat_promile", "Hlad – přejedení v opilosti od", "‰", ""],
		["OVEREAT_NAUSEA", "overeat_nausea", "Hlad – nevolnost z přejedení", "", "", 0.0, 1.0],
		# výdrž a rychlost podle těla
		["SPEED_BMI_FROM", "speed_bmi_from", "Rychlost – obezita zpomaluje od BMI", "BMI", ""],
		["SPEED_BMI_K", "speed_bmi_k", "Rychlost – zpomalení na 1 BMI", "×", ""],
		["SPEED_DRUNK_FROM", "speed_drunk_from", "Rychlost – opilost zpomaluje od", "‰", ""],
		["SPEED_DRUNK_K", "speed_drunk_k", "Rychlost – zpomalení na ‰", "×", ""],
		["SPEED_COLD_K", "speed_cold_k", "Rychlost – zpomalení při plném prochladnutí", "×", "", 0.0, 1.0],
		["SPEED_MIN", "speed_min", "Rychlost – nejpomalejší", "×", "", 0.0, 1.0],
		["STAM_TAR_K", "stam_tar_k", "Výdrž – ztráta max. výdrže na cigaretu dehtu", "×", ""],
		["STAM_TAR_MAX", "stam_tar_max", "Výdrž – strop ztráty dehtem", "×", "", 0.0, 1.0],
		["STAM_COLD_K", "stam_cold_k", "Výdrž – ztráta při plném prochladnutí", "×", "", 0.0, 1.0],
		["STAM_BMI_FROM", "stam_bmi_from", "Výdrž – obezita snižuje od BMI", "BMI", ""],
		["STAM_BMI_K", "stam_bmi_k", "Výdrž – ztráta na 1 BMI", "×", ""],
		["STAM_MIN", "stam_min", "Výdrž – nejnižší maximum", "×", "", 0.0, 1.0],
		["OVERHEAT_STAMINA", "overheat_stamina", "Výdrž – ztráta při plném přehřátí", "×", "", 0.0, 1.0],
		["DRAIN_BMI_FROM", "drain_bmi_from", "Únava – obezita zrychluje od BMI", "BMI", ""],
		["DRAIN_BMI_K", "drain_bmi_k", "Únava – zrychlení na 1 BMI", "×", ""],
		["DRAIN_TAR_K", "drain_tar_k", "Únava – zrychlení na cigaretu dehtu", "×", ""],
		["DRAIN_TAR_MAX", "drain_tar_max", "Únava – strop zrychlení dehtem", "×", ""],
		["DRAIN_COLD_K", "drain_cold_k", "Únava – zrychlení při plném prochladnutí", "×", ""],
		["DRAIN_HEAT_K", "drain_heat_k", "Únava – zrychlení při plném přehřátí", "×", ""],
		["JUMP_BMI_FROM", "jump_bmi_from", "Skok – obezita snižuje od BMI", "BMI", ""],
		["JUMP_BMI_K", "jump_bmi_k", "Skok – ztráta na 1 BMI", "×", ""],
		["JUMP_MIN", "jump_min", "Skok – nejnižší násobek", "×", "", 0.0, 1.0],
		# mokro, chlad, teplo
		["WET_RAIN", "wet_rain", "Mokro – promáčení v lijáku", "1/h", ""],
		["WET_DRY_IN", "wet_dry_in", "Mokro – schnutí uvnitř", "1/h", ""],
		["WET_DRY_OUT", "wet_dry_out", "Mokro – schnutí venku", "1/h", "× teplota a vítr."],
		["DRY_BASE_K", "dry_base_k", "Mokro – schnutí venku: základ", "×", ""],
		["DRY_TEMP_C", "dry_temp_c", "Mokro – teplota plného schnutí", "°C", ""],
		["DRY_TEMP_MAX", "dry_temp_max", "Mokro – strop příspěvku teploty", "×", ""],
		["DRY_WIND_K", "dry_wind_k", "Mokro – příspěvek větru ke schnutí", "×/(m/s)", ""],
		["HEAT_DRY_K", "heat_dry_k", "Mokro – sušení u ohně navíc", "×", ""],
		["COLD_COMFORT", "cold_comfort", "Chlad – pocitová teplota pohodlí", "°C", "Pod ní tělo chladne (v základním oblečení).", -10.0, 30.0],
		["CHILL_RATE", "chill_rate", "Chlad – prochládání", "1/(h·°C)", ""],
		["WARM_RATE", "warm_rate", "Chlad – zahřívání", "1/(h·°C)", ""],
		["WINDCHILL_K", "windchill_k", "Chlad – vítr ochlazuje (suchý oděv)", "°C/(m/s)", ""],
		["WINDCHILL_WET_K", "windchill_wet_k", "Chlad – vítr ochlazuje navíc (promoklý)", "°C/(m/s)", ""],
		["WET_CHILL_C", "wet_chill_c", "Chlad – promoklý oděv ochlazuje", "°C", ""],
		["HEAT_WARM_C", "heat_warm_c", "Chlad – oheň zvedne pocitovou teplotu", "°C", ""],
		["SHELTER_MIN_C", "shelter_min_c", "Chlad – nejnižší pocitová teplota pod střechou", "°C", "", -10.0, 30.0],
		["INSUL_BASE", "insul_base", "Chlad – izolace základního oblečení", "", ""],
		["INSUL_COMFORT_C", "insul_comfort_c", "Chlad – posun pohodlí na 1,0 izolace", "°C", ""],
		["INSUL_MAX", "insul_max", "Chlad – strop izolace", "", ""],
		["COLD_HURT_FROM", "cold_hurt_from", "Chlad – zdraví ubývá od prochladnutí", "", "", 0.0, 1.0],
		["COLD_HURT_K", "cold_hurt_k", "Chlad – ztráta zdraví", "HP/h", ""],
		["OVERHEAT_TEMP", "overheat_temp", "Přehřátí – od teploty", "°C", "", 0.0, 45.0],
		["OVERHEAT_INSUL", "overheat_insul", "Přehřátí – od izolace oblečení", "", ""],
		["OVERHEAT_RATE", "overheat_rate", "Přehřátí – růst", "1/(h·°C)", ""],
		["OVERHEAT_DECAY", "overheat_decay", "Přehřátí – ústup", "1/h", ""],
		# zranění a hojení
		["HEAL_H", "heal_h", "Zranění – hojení v bdělosti", "HP/h", ""],
		["HEAL_SLEEP_H", "heal_sleep_h", "Zranění – hojení ve spánku", "HP/h", ""],
		["VOMIT_HP", "vomit_hp", "Zranění – zvracení", "HP", ""],
		# opilost (alkohol)
		["BETA", "beta", "Opilost – odbourávání alkoholu", "‰/h", "Průměrný muž 0,15 ‰/h."],
		["ELIM_FOOD_K", "elim_food_k", "Opilost – jídlo zrychlí odbourávání až o", "×", ""],
		["ELIM_KM", "elim_km", "Opilost – odbourávání 1. řádu pod", "g", ""],
		["ABSORB_RATE", "absorb_rate", "Opilost – vstřebávání nalačno", "1/h", ""],
		["ABSORB_FOOD_KCAL", "absorb_food_kcal", "Opilost – jídlo zpomalí vstřebávání na půl při", "kcal", ""],
		["FIRST_PASS_BASE", "first_pass_base", "Opilost – odbouráno v žaludku nalačno", "", "", 0.0, 1.0],
		["FIRST_PASS_FOOD", "first_pass_food", "Opilost – odbouráno v žaludku navíc s jídlem", "", "", 0.0, 1.0],
		["ETHANOL_KCAL_G", "ethanol_kcal_g", "Opilost – energie z alkoholu", "kcal/g", ""],
		["WIDMARK_BASE", "widmark_base", "Opilost – Widmarkův faktor", "", "Podíl vody v těle při BMI 24.", 0.3, 1.0],
		["WIDMARK_BMI_K", "widmark_bmi_k", "Opilost – Widmark: pokles na 1 BMI", "", ""],
		["WIDMARK_BMI_REF", "widmark_bmi_ref", "Opilost – Widmark: BMI základu", "BMI", ""],
		["WIDMARK_MIN", "widmark_min", "Opilost – Widmark: nejméně", "", "", 0.3, 1.0],
		["WIDMARK_MAX", "widmark_max", "Opilost – Widmark: nejvíc", "", "", 0.3, 1.0],
		["DRUNK_FROM", "drunk_from", "Opilost – znát od", "‰", ""],
		["DRUNK_FULL", "drunk_full", "Opilost – naplno při", "‰", ""],
		["DRINK_KCAL_K", "drink_kcal_k", "Opilost – kcal nápoje ze sacharidů", "", "", 0.0, 1.0],
		["DRINK_NAUSEA_PROMILE", "drink_nausea_promile", "Nevolnost – panák nalačno od", "‰", ""],
		["DRINK_NAUSEA_EMPTY_KCAL", "drink_nausea_empty_kcal", "Nevolnost – „lačný“ žaludek pod", "kcal", ""],
		["DRINK_NAUSEA_K", "drink_nausea_k", "Nevolnost – z panáku nalačno na 20 g", "", ""],
		["NAUSEA_RISE_PROMILE", "nausea_rise_promile", "Nevolnost – rychlé pití od", "‰", ""],
		["NAUSEA_RISE_RATE", "nausea_rise_rate", "Nevolnost – „rychlé pití“ nad", "‰/h", ""],
		["NAUSEA_RISE_K", "nausea_rise_k", "Nevolnost – z rychlého pití", "1/h na ‰/h", ""],
		["NAUSEA_HIGH_PROMILE", "nausea_high_promile", "Nevolnost – roste sama od", "‰", ""],
		["NAUSEA_HIGH_K", "nausea_high_k", "Nevolnost – růst nad prahem", "1/(h·‰)", ""],
		["NAUSEA_CALM_PROMILE", "nausea_calm_promile", "Nevolnost – ustupuje pod", "‰", ""],
		["NAUSEA_RECOVER", "nausea_recover", "Nevolnost – ústup", "1/h", ""],
		["VOMIT_ALC_KEEP", "vomit_alc_keep", "Nevolnost – po zvracení zůstane alkoholu", "", "", 0.0, 1.0],
		["VOMIT_FOOD_KEEP", "vomit_food_keep", "Nevolnost – po zvracení zůstane jídla", "", "", 0.0, 1.0],
		["POISON_PROMILE", "poison_promile", "Otrava alkoholem – od", "‰", ""],
		["POISON_HP", "poison_hp", "Otrava alkoholem – ztráta zdraví", "HP/(h·‰)", ""],
		["PASSOUT_PROMILE", "passout_promile", "Okno – hrozí od", "‰", ""],
		["PASSOUT_K", "passout_k", "Okno – šance za hodinu na ‰", "1/(h·‰)", ""],
		["PASSOUT_CAFFEINE_K", "passout_caffeine_k", "Okno – s kofeinem", "×", "", 0.0, 1.0],
		["PASSOUT_CD_H", "passout_cd_h", "Okno – nejkratší rozestup", "h", ""],
	])


# ------------------------------------------------------------------ Chůze a postoj (`Gait`, `Humanoid`)

static func _chuze() -> void:
	rows(Gait, "gait.", CHUZE, [
		["DUTY_WALK", "duty_walk", "Chůze – podíl stojné fáze", "", "", 0.3, 0.9],
		["DUTY_RUN", "duty_run", "Běh – podíl stojné fáze", "", "Zbytek = letová fáze.", 0.1, 0.7],
		["RUN_SPEED", "run_speed", "Běh – práh chůze → běh", "m/s", ""],
		["RUN_SPAN", "run_span", "Běh – šířka přechodu", "m/s", ""],
		["STEP_K", "step_k", "Chůze – kadence (dynamická podobnost)", "", ""],
		["RUN_K", "run_k", "Běh – kadence", "", ""],
		["CADENCE_G", "cadence_g", "Chůze – „g“ kadence", "m/s²", "Kadence ∝ √(g / délka nohy)."],
		["LIFT_WALK", "lift_walk", "Chůze – zdvih chodidla ve švihu", "", ""],
		["LIFT_RUN", "lift_run", "Běh – zdvih chodidla ve švihu", "", ""],
		["STEP_AMP_MAX", "step_amp_max", "Chůze – největší rozkmit stehna", "rad", ""],
		["KNEE_BASE", "knee_base", "Chůze – pokrčení kolene ve stoje", "rad", ""],
		["KNEE_LIFT_K", "knee_lift_k", "Chůze – ohnutí kolene ve švihu", "", ""],
		["KNEE_RUN_K", "knee_run_k", "Běh – ohnutí kolene ve švihu navíc", "", ""],
		["ARM_SWING_K", "arm_swing_k", "Chůze – protipohyb paží", "×", ""],
		["PELVIS_SHIFT", "pelvis_shift", "Chůze – boční posun pánve", "m", ""],
		["PELVIS_BOB", "pelvis_bob", "Chůze – svislý pohup pánve", "m", ""],
		["MOVE_BLEND", "move_blend", "Chůze – náběh / útlum při rozchodu a zastavení", "1/s", ""],
		["TURN_SHUFFLE_MIN_RATE", "turn_shuffle_min_rate", "Otočka – přešlapování od rychlosti otáčení", "rad/s", ""],
		["TURN_BLEND", "turn_blend", "Otočka – náběh přešlapování", "1/s", ""],
		["SHUFFLE_SPEED_K", "shuffle_speed_k", "Otočka – rychlost přešlapování na rad/s", "m", ""],
		["SHUFFLE_V_MIN", "shuffle_v_min", "Otočka – nejpomalejší přešlapování", "m/s", ""],
		["SHUFFLE_V_MAX", "shuffle_v_max", "Otočka – nejrychlejší přešlapování", "m/s", ""],
		["LOAD_MAX_KG", "load_max_kg", "Náklad – plné shrbení při", "kg", ""],
		["LOAD_LEAN_K", "load_lean_k", "Náklad – předklon na kg", "rad/kg", ""],
		["LOAD_STEP_K", "load_step_k", "Náklad – zkrácení kroku", "", "", 0.0, 1.0],
		["TIRED_LEAN_K", "tired_lean_k", "Únava – shrbení při vyčerpané výdrži", "rad", ""],
		["TIRED_CADENCE_K", "tired_cadence_k", "Únava – zpomalení kadence", "", "", 0.0, 1.0],
		["TIRED_ARM_K", "tired_arm_k", "Únava – menší rozkmit paží", "", "", 0.0, 1.0],
	])
	rows(Humanoid, "humanoid.", CHUZE, [
		["LAND_IMPACT", "land_impact", "Dopad – plné propružení při", "m/s", ""],
		["LAND_RECOVER", "land_recover", "Dopad – návrat z propružení", "1/s", ""],
		["LAND_DIP", "land_dip", "Dopad – pokles pánve", "m", ""],
		["HIPS_STAND", "hips_stand", "Postoj – výška pánve ve stoje", "m", "", 0.5, 1.4],
		["CROUCH_DROP", "crouch_drop", "Postoj – pokles pánve v přikrčení", "m", ""],
		["CROUCH_LEAN", "crouch_lean", "Postoj – předklon v přikrčení", "rad", ""],
		["SLIDE_LEAN", "slide_lean", "Postoj – záklon ve skluzu", "rad", ""],
		["CROUCH_BLEND", "crouch_blend", "Postoj – přechod do přikrčení", "1/s", ""],
		["SIT_BLEND", "sit_blend", "Postoj – přechod do sedu / jízdy", "1/s", ""],
		["LIE_BLEND", "lie_blend", "Postoj – přechod do lehu", "1/s", ""],
		["WAVE_BLEND", "wave_blend", "Postoj – zvednutí ruky k mávání", "1/s", ""],
		["ACT_BLEND", "act_blend", "Postoj – náběh akce rukou", "1/s", ""],
		["ELBOW_BASE", "elbow_base", "Chůze – ohnutí loktů", "rad", ""],
		["ELBOW_RUN", "elbow_run", "Běh – ohnutí loktů navíc", "rad", ""],
		["LEAN_RUN", "lean_run", "Běh – předklon", "rad", ""],
		["LEAN_MOVE", "lean_move", "Chůze – předklon", "rad", ""],
		["SLOPE_ROLL_MAX", "slope_roll_max", "Svah – náklon pánve napříč svahem nejvýš", "rad", ""],
		["SLOPE_LEAN_MAX", "slope_lean_max", "Svah – náklon trupu do kopce nejvýš", "rad", ""],
		["SWAY_RATE", "sway_rate", "Opilost – rychlost potácení: základ", "", ""],
		["SWAY_DRUNK_RATE", "sway_drunk_rate", "Opilost – rychlost potácení navíc", "", ""],
		["DRUNK_ROLL", "drunk_roll", "Opilost – boční potácení trupu", "rad", ""],
		["DRUNK_HEAD_ROLL", "drunk_head_roll", "Opilost – kývání hlavy", "rad", ""],
		["DRUNK_ARM_OUT", "drunk_arm_out", "Opilost – ruce od těla", "rad", ""],
		["DRUNK_LEAN", "drunk_lean", "Opilost – předklon", "rad", ""],
		["COLD_ARMS_IN", "cold_arms_in", "Chlad – ruce k tělu", "rad", ""],
		["SHIVER_HZ", "shiver_hz", "Chlad – třes: frekvence", "rad/s", ""],
		["SHIVER_AMP", "shiver_amp", "Chlad – třes: amplituda", "rad", ""],
		["SHIVER_LEAN", "shiver_lean", "Chlad – předklon z třesu", "×", ""],
		["OLD_RUN_FROM", "old_run_from", "Stará animace – běh od", "m/s", "Animace bez Gait (Esc → Nastavení → realismus chůze vypnutý)."],
		["OLD_RUN_SPAN", "old_run_span", "Stará animace – přechod chůze → běh", "m/s", ""],
		["OLD_MOVE_V", "old_move_v", "Stará animace – plný rozkmit od", "m/s", "I ohnutí loktů s Gait."],
		["OLD_PHASE_K", "old_phase_k", "Stará animace – fáze kroku", "rad/m", ""],
		["OLD_PHASE_RUN", "old_phase_run", "Stará animace – delší krok při běhu", "rad/m", ""],
		["OLD_AMP_WALK", "old_amp_walk", "Stará animace – rozkmit nohou", "rad", ""],
		["OLD_KNEE", "old_knee", "Stará animace – ohnutí kolene", "rad", ""],
		["OLD_KNEE_RUN", "old_knee_run", "Stará animace – ohnutí kolene při běhu", "rad", ""],
		["OLD_ARM_K", "old_arm_k", "Stará animace – protipohyb paží", "×", ""],
		["OLD_BOB", "old_bob", "Stará animace – pohup pánve", "m", ""],
	])


# ------------------------------------------------------------------ NPC a vesničané

static func _npc() -> void:
	rows(Villager, "villager.", NPC, [
		["PHYSICS_RANGE", "physics_range", "Vesničan – plná fyzika do", "m", "Dál kinematicky po terénu (levné)."],
		["DEEP_K", "deep_k", "Vesničan – hluboký spánek za", "× bublina", "Násobek simulační bubliny; za ní schovaný, chůze ~2 Hz."],
		["SLEEP_STEP", "sleep_step", "Vesničan – krok hlubokého spánku", "s", ""],
		["GRAVITY", "gravity", "Vesničan – gravitace", "m/s²", ""],
		["WALK_ACCEL", "walk_accel", "Vesničan – rozjezd a brzdění", "m/s²", ""],
		["WALK_TURN", "walk_turn", "Vesničan – natáčení do směru chůze", "1/s", ""],
		["SPEED_DEFAULT", "speed_default", "Vesničan – tempo bez profilu", "m/s", "Projeví se u nově vytvořených (nová hra)."],
		["SPEED_JITTER", "speed_jitter", "Vesničan – náhodná odchylka tempa", "±", "Nově vytvoření.", 0.0, 0.5],
		["SIDE_MIN", "side_min", "Vesničan – odstup od osy silnice: nejméně", "m", "Nově vytvoření."],
		["SIDE_MAX", "side_max", "Vesničan – odstup od osy silnice: nejvíc", "m", "Nově vytvoření."],
		["PATH_SIDE_K", "path_side_k", "Vesničan – odstup na pěšině", "×", ""],
		["ARRIVE_R", "arrive_r", "Vesničan – dosažení bodu trasy", "m", ""],
		["ARRIVE_LAST_R", "arrive_last_r", "Vesničan – dosažení cíle z rutiny (BT)", "m", "Musí být menší než „arrive“ v uzlech BT (1,5+)."],
		["TARGET_TOL", "target_tol", "Vesničan – stejný cíl BT do", "m", ""],
		["PAUSE_P", "pause_p", "Vesničan – šance zastavení na křižovatce", "", "", 0.0, 1.0],
		["PAUSE_MIN", "pause_min", "Vesničan – zastavení: nejkratší", "s", ""],
		["PAUSE_MAX", "pause_max", "Vesničan – zastavení: nejdelší", "s", ""],
		["STUCK_V", "stuck_v", "Vesničan – zaseknutý pod rychlostí", "m/s", ""],
		["STUCK_S", "stuck_s", "Vesničan – zaseknutí, než se otočí", "s", ""],
		["BT_STUCK_MAX", "bt_stuck_max", "Vesničan – cíl BT vzdá po zaseknutích", "×", ""],
		["BT_GIVEUP_S", "bt_giveup_s", "Vesničan – vzdaný cíl BT nezkouší", "s", ""],
		["AVOID_R", "avoid_r", "Vesničan – neprojde skrz hráče do", "m", ""],
		["GREET_R", "greet_r", "Hovor – pozdraví hráče do", "m", ""],
		["GREET_S", "greet_s", "Hovor – délka pozdravu", "s", ""],
		["GREET_CD", "greet_cd", "Hovor – znovu pozdraví za", "s", ""],
		["WAVE_S", "wave_s", "Hovor – mává na začátku repliky", "s", ""],
		["TALK_TURN", "talk_turn", "Hovor – otočení k hráči", "1/s", ""],
		["WAIT_R", "wait_r", "Hovor – čeká na odpověď do", "m", ""],
		["WAIT_TURN", "wait_turn", "Hovor – otočení při čekání", "1/s", ""],
		["SAY_BASE_S", "say_base_s", "Hovor – délka repliky: základ", "s", ""],
		["SAY_CHARS_PER_S", "say_chars_per_s", "Hovor – rychlost čtení", "znaků/s", ""],
		["SAY_MIN_S", "say_min_s", "Hovor – replika nejkratší", "s", ""],
		["SAY_MAX_S", "say_max_s", "Hovor – replika nejdelší", "s", ""],
		["SAY_CD", "say_cd", "Hovor – po replice nezdraví", "s", ""],
		["FLEE_SPEED", "flee_speed", "Útěk před střelbou – rychlost", "m/s", ""],
		["FLEE_ACCEL", "flee_accel", "Útěk před střelbou – rozběh", "m/s²", ""],
		["FLEE_TURN", "flee_turn", "Útěk před střelbou – otočení", "1/s", ""],
		["KNOCK_S", "knock_s", "Sražení autem – ležení", "s", ""],
		["KNOCK_PER_V", "knock_per_v", "Sražení autem – ležení navíc za m/s", "s·s/m", ""],
		["KNOCK_DECEL", "knock_decel", "Sražení autem – dobrzdění", "m/s²", ""],
		["PROMILE_DECAY", "promile_decay", "Opilost vesničana – vystřízlivění", "‰/s", "Reálné sekundy (zjednodušené)."],
		["DRUNK_FULL_PROMILE", "drunk_full_promile", "Opilost vesničana – plné potácení při", "‰", ""],
		["GARDEN_D", "garden_d", "Rutina – zahrada před domem", "m", "Projeví se při dalším naplnění cílů rutiny."],
	])
	rows(Npc, "npc.", NPC, [
		["FACE_R", "face_r", "Stojící NPC – otočí se k hráči do", "m", "Hostinský, prodavačka, štamgast…"],
		["TURN", "turn", "Stojící NPC – rychlost otáčení", "1/s", ""],
		["WAVE_S", "wave_s", "Stojící NPC – mává na konci repliky", "s", ""],
	])
	rows(NpcGrow, "npc_grow.", NPC, [
		["DAYS", "days", "Zahrádkář – dny od výsevu do sklizně", "dny", "Obsah pro dospělé (konopí za chatou)."],
		["PLANTS_MIN", "plants_min", "Zahrádkář – rostlin nejméně", "ks", ""],
		["PLANTS_MAX", "plants_max", "Zahrádkář – rostlin nejvíc", "ks", ""],
		["SEE_R", "see_r", "Zahrádkář – dohled souseda na záhon", "m", ""],
		["CHECK_R", "check_r", "Zahrádkář – hráči, kteří mohou čin nahlásit, do", "m", ""],
	])


# ------------------------------------------------------------------ Pes (`Dog`)

static func _pes() -> void:
	rows(Dog, "dog.", PES, [
		["NOTICE_R", "notice_r", "Pes – všimne si hráče do", "m", ""],
		["BARK_S", "bark_s", "Pes – štěkání", "s", ""],
		["WANDER_SPEED", "wander_speed", "Pes – toulání: rychlost", "m/s", ""],
		["ROAM_MIN", "roam_min", "Pes – toulání od domu: nejméně", "m", ""],
		["ROAM_MAX", "roam_max", "Pes – toulání od domu: nejvíc", "m", ""],
		["WAIT_MIN", "wait_min", "Pes – postání: nejkratší", "s", ""],
		["WAIT_MAX", "wait_max", "Pes – postání: nejdelší", "s", ""],
		["ARRIVE_R", "arrive_r", "Pes – dosažení cíle toulání", "m", ""],
		["FOLLOW_GAP", "follow_gap", "Pes – drží se od hráče", "m", ""],
		["FOLLOW_STOP", "follow_stop", "Pes – dohánění počítá od", "m", ""],
		["FOLLOW_K", "follow_k", "Pes – rychlost dohánění na metr", "1/s", ""],
		["FOLLOW_MIN", "follow_min", "Pes – dohánění: nejpomalejší", "m/s", ""],
		["FOLLOW_MAX", "follow_max", "Pes – dohánění: nejrychlejší běh", "m/s", ""],
		["LOSE_R", "lose_r", "Pes – vzdá to, když je hráč dál než", "m", ""],
		["HOME_MAX", "home_max", "Pes – nejdál od domu", "m", ""],
		["HOME_SPEED", "home_speed", "Pes – návrat domů: rychlost", "m/s", ""],
		["HOME_ARRIVE", "home_arrive", "Pes – doma do", "m", ""],
		["REFOLLOW_R", "refollow_r", "Pes – cestou domů se přidá k hráči do", "m", ""],
		["REFOLLOW_HOME", "refollow_home", "Pes – …jen do vzdálenosti od domu", "m", ""],
		["ACCEL", "accel", "Pes – rozběh a brzdění", "m/s²", ""],
		["JUMP_VY", "jump_vy", "Pes – přeskok překážky", "m/s", ""],
		["JUMP_MIN_V", "jump_min_v", "Pes – skáče od rychlosti", "m/s", ""],
		["GRAVITY", "gravity", "Pes – gravitace", "m/s²", ""],
		["TURN", "turn", "Pes – natáčení do směru běhu", "1/s", ""],
		["FACE_TURN", "face_turn", "Pes – otočení k hráči ve stoje", "1/s", ""],
		["STRIDE_K", "stride_k", "Pes – kadence nohou", "rad/m", ""],
		["GALLOP_V", "gallop_v", "Pes – cval od rychlosti", "m/s", ""],
		["PHYSICS_RANGE", "physics_range", "Pes – plná fyzika do", "m", ""],
		["DEEP_K", "deep_k", "Pes – hluboký spánek za", "× bublina", ""],
		["SLEEP_STEP", "sleep_step", "Pes – krok hlubokého spánku", "s", ""],
	])
