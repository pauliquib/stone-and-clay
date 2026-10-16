## M8.D2b: menu pro vývojáře – kategorie **Činnosti**: rybaření (`Fishing`), lov a balistika (`Weapons`, `Hunting`,
## `ShootingRange`), oheň a požáry (`Fire`, `FireManager`, `GrassFire`), těžba a řemesla (`Forestry`, `Klesti`, `Skills`)
## a návykové látky a efekty (`BodyState` – nikotin, THC, psilocybin; `Player` – délky pití / jídla / kouření;
## `Consumables`, `DrunkFx`). Úplný seznam konstant, které ovlivňují chování (ne texty, vzhled, zvuk).
## Výchozí hodnoty se berou z kódu (`DevTune.tune` čte současnou hodnotu) – chování ve výchozím stavu beze změny.
## Data v `data/ryby.json` a `data/lov.json` (druhy ryb a zvěře, doby lovu, výnosy) se tu neladí – jsou to data, ne kód.
extends RefCounted

const RYB := "Činnosti/Rybaření"
const LOV := "Činnosti/Lov a balistika"
const OHEN := "Činnosti/Oheň a požáry"
const TEZ := "Činnosti/Těžba a řemesla"
const NAV := "Činnosti/Návykové látky a efekty"

## Názvy pro popisky slovníků (klíč → český název).
const WEAPON_NAMES := {"luk": "Luk", "kuse": "Kuše", "puska": "Puška"}
const TOOL_NAMES := {"sekera_stara": "stará sekera", "sekera": "sekera", "motorova_pila": "motorová pila"}
const MONTHS := ["leden", "únor", "březen", "duben", "květen", "červen", "červenec", "srpen", "září", "říjen",
	"listopad", "prosinec"]
const WATER_NAMES := {"pond": "rybník", "river": "řeka", "canal": "kanál", "stream": "potok", "ditch": "příkop",
	"drain": "strouha"}
const TRAIT_NAMES := {"prisny": "přísný", "drbna": "drbna", "plachy": "plachý", "bruclavy": "bručoun", "moudry": "moudrý",
	"mlady": "mladý", "pratelsky": "přátelský", "veselak": "veselák"}
## Parametry zbraní (`Weapons.WEAPONS[id]`): [klíč, popisek, jednotka, nápověda]. Název, střelivo, zvuk, délka
## šípu a zorný úhel míření (kamera) se neladí.
const WEAPON_KEYS := [
	["draw_s", "natažení na plnou sílu", "s", "Luk: doba držení LMB do plné síly."],
	["cycle_s", "napnutí tětivy po ráně", "s", "Kuše."],
	["shot_cd", "pauza mezi ranami", "s", ""],
	["reload_s", "přebíjení", "s", ""],
	["mag", "zásobník", "ran", ""],
	["v0", "úsťová rychlost", "m/s", ""],
	["noise", "slyšet do", "m", "Kdo výstřel uslyší (zvěř, lidé, zákon)."],
	["sway", "základní kolísání mušky", "rad", ""],
	["mass", "hmotnost střely", "kg", "Energie zásahu = ½ m v²."],
	["drag", "odpor vzduchu střely", "1/s", ""],
	["wind_k", "vítr unáší střelu", "×", ""],
	["spread", "rozptyl", "rad", ""],
]


## Zaregistruje řádky tabulky: [vlastnost / klíč / index, id, popisek, jednotka, nápověda, (min, max)]. Cíl: skript se
## `static var`, Dictionary nebo Array. Bez min/max se rozsah odvodí z výchozí hodnoty (0 … 3×), krok podle řádu.
static func rows(target: Variant, prefix: String, group: String, list: Array) -> void:
	for r in list:
		_row(target, r[0], prefix + String(r[1]), group, String(r[2]), String(r[3]), String(r[4]),
			r[5] if r.size() > 6 else null, r[6] if r.size() > 6 else null)


static func _row(target: Variant, prop: Variant, id: String, group: String, label: String, unit: String, help: String,
		lo_v: Variant = null, hi_v: Variant = null) -> void:
	var v: Variant = null
	if target is Object:
		v = (target as Object).get(String(prop))
	elif target is Dictionary:
		v = (target as Dictionary).get(prop)
	elif target is Array:
		v = (target as Array)[int(prop)]
	if v == null:
		push_error("tune_cinnosti: %s nemá %s" % [str(target), str(prop)])
		return
	var lo := 0.0
	var hi := 1.0
	if lo_v != null:
		lo = float(lo_v)
		hi = float(hi_v)
	else:
		var fv := float(v)
		if fv > 0.0:
			hi = fv * 3.0
		elif fv < 0.0:
			lo = fv * 3.0
			hi = 0.0
		if v is int:
			hi = maxf(hi, float(v) + 5.0)
	DevTune.tune(target, prop, id, group, label, lo, hi, _step(v), help, unit)


static func _step(v: Variant) -> float:
	if v is int:
		return 1.0
	var a := absf(float(v))
	if a < 1.0e-9:
		return 0.01
	return maxf(pow(10.0, floorf(log(a) / log(10.0)) - 2.0), 1.0e-6)


static func register_all() -> void:
	_rybareni()
	_lov()
	_ohen()
	_tezba()
	_navykove()


# ------------------------------------------------------------------ Rybaření (`Fishing`)

static func _rybareni() -> void:
	rows(Fishing, "fishing.", RYB, [
		["MIN_CAST_M", "min_cast_m", "Nahození – nejblíž od hráče", "m", ""],
		["MIN_DEPTH", "min_depth", "Nahození – nejmenší hloubka vody", "m", ""],
		["FROZEN", "frozen", "Nahození – zamrznutí, od kterého nejde", "", "Water.ice / ice_flow.", 0.0, 1.0],
		["LEAVE_M", "leave_m", "Nahození – dál od splávku se vlasec stáhne", "m", ""],
		["WAIT_MEAN_S", "wait_mean_s", "Záběr – průměrná doba čekání (šance 1)", "s", ""],
		["WAIT_MIN_S", "wait_min_s", "Záběr – nejkratší čekání", "s", ""],
		["WAIT_MAX_S", "wait_max_s", "Záběr – nejdelší čekání", "s", ""],
		["WAIT_RAND_MIN", "wait_rand_min", "Záběr – náhoda čekání: nejméně", "× průměr", ""],
		["WAIT_RAND_MAX", "wait_rand_max", "Záběr – náhoda čekání: nejvíc", "× průměr", ""],
		["STRIKE_WINDOW_S", "strike_window_s", "Záběr – čas na zaseknutí", "s", ""],
		["BITE_NIGHT", "bite_night", "Záběr – v noci", "×", ""],
		["BITE_DAWN_DUSK", "bite_dawn_dusk", "Záběr – ráno a večer", "×", "5–9 h a 17–21 h."],
		["BITE_NOON", "bite_noon", "Záběr – poledne", "×", "11–15 h."],
		["BITE_OVERCAST", "bite_overcast", "Záběr – zataženo / déšť", "×", ""],
		["BITE_CLOUDY", "bite_cloudy", "Záběr – oblačno", "×", ""],
		["BITE_STORM", "bite_storm", "Záběr – bouřka", "×", ""],
		["BITE_HOT", "bite_hot", "Záběr – jasno a horko", "×", ""],
		["BITE_HOT_C", "bite_hot_c", "Záběr – „horko“ od", "°C", "", 10.0, 40.0],
		["BITE_WIND", "bite_wind", "Záběr – silný vítr od", "m/s", ""],
		["BITE_WIND_K", "bite_wind_k", "Záběr – při silném větru", "×", ""],
		["BITE_SKILL_K", "bite_skill_k", "Záběr – dovednost Rybaření přidá až", "+×", ""],
		["ROD_BETTER_BITE", "rod_better_bite", "Záběr – lepší udice", "×", ""],
		["TENSION_START", "tension_start", "Zdolávání – počáteční napětí vlasce", "", "", 0.0, 1.0],
		["GREEN_LO", "green_lo", "Zdolávání – zelená zóna od", "", "", 0.0, 1.0],
		["GREEN_HI", "green_hi", "Zdolávání – zelená zóna do", "", "", 0.0, 1.0],
		["TENSION_MAX", "tension_max", "Zdolávání – strop napětí", "", "Nad 1,0 vlasec praskne."],
		["REEL_RATE", "reel_rate", "Zdolávání – růst napětí při navíjení", "1/s", ""],
		["SLACK_RATE", "slack_rate", "Zdolávání – pokles napětí při povolení", "1/s", ""],
		["ROD_BETTER_REEL", "rod_better_reel", "Zdolávání – lepší udice: napětí při navíjení", "×", ""],
		["SURGE_S", "surge_s", "Zdolávání – délka záběru ryby", "s", ""],
		["SURGE_BASE", "surge_base", "Zdolávání – síla záběru malé ryby", "", ""],
		["SURGE_SIZE_K", "surge_size_k", "Zdolávání – síla záběru navíc u největší", "", ""],
		["SURGE_SKILL_K", "surge_skill_k", "Zdolávání – dovednost zmenší záběry o", "×", "", 0.0, 1.0],
		["SURGE_GAP_MIN", "surge_gap_min", "Zdolávání – mezera mezi záběry: nejkratší", "s", ""],
		["SURGE_GAP_MAX", "surge_gap_max", "Zdolávání – mezera mezi záběry: nejdelší", "s", ""],
		["SURGE_GAP_SKILL_K", "surge_gap_skill_k", "Zdolávání – dovednost prodlouží mezery o", "×", ""],
		["SLIP_K", "slip_k", "Zdolávání – ryba se vzdaluje pod zelenou", "×", ""],
		["FIGHT_MIN_S", "fight_min_s", "Zdolávání – nejkratší (malá ryba)", "s", ""],
		["FIGHT_MAX_S", "fight_max_s", "Zdolávání – nejdelší (největší ryba)", "s", ""],
		["FIGHT_SIZE_EXPO", "fight_size_expo", "Zdolávání – délka podle velikosti (mocnina)", "", ""],
		["SNAP_WEAR", "snap_wear", "Zdolávání – opotřebení udice při prasknutí", "použití", ""],
		["NET_CM", "net_cm", "Podběrák – potřeba od délky", "cm", ""],
		["NET_LOSS_P", "net_loss_p", "Podběrák – šance ztráty bez něj", "", "", 0.0, 1.0],
		["NET_SKILL_K", "net_skill_k", "Podběrák – dovednost zmenší ztrátu o", "×", "", 0.0, 1.0],
		["SIZE_EXPO", "size_expo", "Velikost – rozdělení délky (víc = víc malých)", "", ""],
		["SIZE_SKILL_K", "size_skill_k", "Velikost – dovednost posune k větším", "", ""],
		["SIZE_ROD_K", "size_rod_k", "Velikost – lepší udice posune k větším", "", ""],
		["SIZE_EXPO_MIN", "size_expo_min", "Velikost – nejmenší mocnina", "", ""],
		["DITCH_SIZE_K", "ditch_size_k", "Velikost – příkop / strouha: největší kus", "×", "", 0.0, 1.0],
		["XP_BASE", "xp_base", "XP – úlovek: základ", "XP", ""],
		["XP_PER_KG", "xp_per_kg", "XP – za kg", "XP/kg", ""],
		["XP_PER_CM", "xp_per_cm", "XP – za cm", "XP/cm", ""],
		["XP_MAX", "xp_max", "XP – strop za úlovek", "XP", ""],
		["WITNESS_R", "witness_r", "Zákon – svědek vidí rybáře do", "m", ""],
		["FINE_COOLDOWN_MIN", "fine_cooldown_min", "Zákon – rozestup pokut za pytláctví", "herní min", ""],
	])
	for k in Fishing.PLACE_MULT:
		_row(Fishing.PLACE_MULT, k, "fishing.place_" + String(k), RYB, "Záběr – místo: %s" % WATER_NAMES.get(k, k), "×", "")
	for i in Fishing.MONTH_MULT.size():
		_row(Fishing.MONTH_MULT, i, "fishing.month_%02d" % (i + 1), RYB, "Záběr – sezóna: %s" % MONTHS[i], "×", "")


# ------------------------------------------------------------------ Lov a balistika

static func _lov() -> void:
	for w in Weapons.WEAPONS:
		var spec: Dictionary = Weapons.WEAPONS[w]
		for r in WEAPON_KEYS:
			# nulová hodnota = zbraň tuto mechaniku nemá (luk nemá přebíjení, kuše natahování…) – neladí se
			if spec.has(r[0]) and float(spec[r[0]]) != 0.0:
				_row(spec, r[0], "weapon.%s.%s" % [w, r[0]], LOV, "%s – %s" % [WEAPON_NAMES.get(w, w), r[1]], r[2], r[3])
	rows(Weapons, "weapons.", LOV, [
		["G", "g", "Balistika – gravitace střel", "m/s²", ""],
		["LIFE_S", "life_s", "Balistika – nejdéle letí střela", "s", ""],
		["MAX_RANGE_M", "max_range_m", "Balistika – nejdál letí střela", "m", ""],
		["STICK_MIN_SPEED", "stick_min_speed", "Balistika – šíp se zapíchne od rychlosti", "m/s", ""],
		["STUCK_LIFE_S", "stuck_life_s", "Balistika – zapíchnutý šíp vydrží", "s", ""],
		["PICKUP_R", "pickup_r", "Balistika – dosah sebrání šípu", "m", ""],
		["DRAW_MIN_V", "draw_min_v", "Luk – slabé natažení: úsťová rychlost", "×", "", 0.0, 1.0],
		["MIN_DRAW_S", "min_draw_s", "Luk – nejkratší natažení (jinak šíp zůstane)", "s", ""],
		["OVERDRAW_S", "overdraw_s", "Luk – ruka se unaví po natažení za", "s", ""],
		["OVERDRAW_POWER", "overdraw_power", "Luk – síla po přetažení", "×", "", 0.0, 1.0],
		["HIP_SPREAD_K", "hip_spread_k", "Míření – rozptyl od boku (× kolísání)", "×", ""],
		["BREATH_S", "breath_s", "Míření – zadržení dechu nejdéle", "s", ""],
		["BREATH_REGEN", "breath_regen", "Míření – obnova dechu", "s/s", ""],
		["WINDED_S", "winded_s", "Míření – horší muška po vydechnutí", "s", ""],
		["SWAY_DRUNK_K", "sway_drunk_k", "Muška – kolísání v opilosti", "+×", ""],
		["SWAY_COLD_K", "sway_cold_k", "Muška – kolísání v zimě", "+×", ""],
		["SWAY_TIRED_K", "sway_tired_k", "Muška – kolísání po sprintu", "+×", ""],
		["SWAY_SKILL_MIN", "sway_skill_min", "Muška – nejlepší dovednost Střelba", "×", "", 0.0, 1.0],
		["SWAY_MOVE_K", "sway_move_k", "Muška – kolísání za m/s pohybu", "+×", ""],
		["SWAY_CROUCH_K", "sway_crouch_k", "Muška – v přikrčení", "×", "", 0.0, 1.0],
		["SWAY_HOLD_K", "sway_hold_k", "Muška – se zadrženým dechem", "×", "", 0.0, 1.0],
		["SWAY_WINDED_K", "sway_winded_k", "Muška – po vydechnutí", "×", ""],
		["SWAY_OVERDRAW_K", "sway_overdraw_k", "Muška – dlouho natažený luk", "+×", ""],
		["SWAY_FOLLOW", "sway_follow", "Muška – jak rychle sleduje kolísání", "1/s", ""],
		["RECOIL_PITCH", "recoil_pitch", "Puška – zpětný ráz (zvednutí pohledu)", "rad", ""],
		["RECOIL_SWAY", "recoil_sway", "Puška – kopnutí mušky nahoru", "rad", ""],
		["RECOIL_SWAY_SIDE", "recoil_sway_side", "Puška – kopnutí mušky do stran", "rad", ""],
		["WILD_R", "wild_r", "Výstřel – splaší zvěř do", "m", ""],
		["VILLAGE_R", "village_r", "Zbraň v ruce – vyděsí vesničany do", "m", ""],
		["SHOW_CD_S", "show_cd_s", "Zbraň v ruce – vesničan se lekne nejvýš jednou za", "s", ""],
		["CHECK_S", "check_s", "Zbraň v ruce – kontrola vesnice a policie každých", "s", ""],
	])
	for k in Weapons.OFFENSE_CD_MIN:
		_row(Weapons.OFFENSE_CD_MIN, k, "weapons.offense_cd_" + String(k), LOV,
			"Zákon – rozestup záznamů: %s" % String(k).replace("_", " "), "herní min", "")
	for k in Weapons.CALL_P:
		_row(Weapons.CALL_P, k, "weapons.call_p_" + String(k), LOV, "Svědci – zavolá policii: %s" % TRAIT_NAMES.get(k, k),
			"", "Šance, že vesničan této povahy po leknutí / přestupku zavolá policii (i jiné přestupky).", 0.0, 1.0)
	rows(Hunting, "hunting.", LOV, [
		["INTERACT_R", "interact_r", "Úlovek – dosah nabídky u těla", "m", ""],
		["LIFT_R", "lift_r", "Úlovek – dosah zvednutí na rameno", "m", ""],
		["FOUND_R", "found_r", "Úlovek – dohledání postřeleného zvířete do", "m", ""],
		["NEAR_CARCASS_R", "near_carcass_r", "Úlovek – hráč „u svého úlovku“ do", "m", ""],
		["GONE_FAR_R", "gone_far_r", "Úlovek – mizí, jen když je hráč dál než", "m", ""],
		["GUT_TIME_K", "gut_time_k", "Vyvrhnutí – doba (× tabulka)", "×", ""],
		["GUT_FULL_KG", "gut_full_kg", "Vyvrhnutí – nejdelší u živé váhy", "kg", ""],
		["GUT_SKILL_K", "gut_skill_k", "Vyvrhnutí – dovednost zkrátí o", "×", "", 0.0, 1.0],
		["GUT_BLACKOUT_S", "gut_blackout_s", "Vyvrhnutí – zatmění obrazu", "s", ""],
		["CARRY_MAX_KG", "carry_max_kg", "Nesení – nejvíc na rameno", "kg", ""],
		["CARRY_SLOW_KG", "carry_slow_kg", "Nesení – zpomalení (kg do nulové rychlosti)", "kg", ""],
		["CARRY_SLOW_MIN", "carry_slow_min", "Nesení – nejpomalejší chůze", "×", "", 0.0, 1.0],
		["CARRY_SLOW_MAX", "carry_slow_max", "Nesení – nejrychlejší chůze", "×", "", 0.0, 1.0],
		["CARRY_STAMINA_K", "carry_stamina_k", "Nesení – úbytek výdrže", "1/s", "Na CARRY_STAMINA_KG."],
		["CARRY_STAMINA_KG", "carry_stamina_kg", "Nesení – úbytek výdrže platí na", "kg", ""],
		["BLOOD_LIFE_MIN", "blood_life_min", "Krev – stopa vydrží", "herní min", ""],
		["BLOOD_RAIN_K", "blood_rain_k", "Krev – v dešti mizí rychleji", "×", ""],
		["BLOOD_RAIN_FROM", "blood_rain_from", "Krev – déšť od", "", "", 0.0, 1.0],
		["ROADKILL_R", "roadkill_r", "Sražená zvěř – přivlastnění do", "m", ""],
		["PICK_ROADKILL_R", "pick_roadkill_r", "Sražená zvěř – dosah sebrání", "m", ""],
		["SEE_CARCASS_R", "see_carcass_r", "Zákon – vesničan uvidí nelegální úlovek do", "m", ""],
		["SHOT_WITNESS_DEFAULT_R", "shot_witness_default_r", "Zákon – svědek výstřelu (jiná zbraň) do", "m", ""],
		["DOC_COVER_PCS", "doc_cover_pcs", "Zákon – jeden doklad o původu kryje", "ks", ""],
		["KARMA_POACH", "karma_poach", "Karma – za nelegální kus", "", ""],
		["KARMA_UNFOUND", "karma_unfound", "Karma – nedohledané postřelené zvíře", "", ""],
		["KARMA_NEIGHBOR", "karma_neighbor", "Karma – prodej sousedům bez otázek", "", ""],
		["RESPECT_NEIGHBOR", "respect_neighbor", "Respekt – štamgasti za prodej sousedům", "", ""],
		["XP_KILL", "xp_kill", "XP – úlovek", "XP", ""],
		["XP_PROCESS_MIN", "xp_process_min", "XP – zpracování zvěřiny: nejméně", "XP", ""],
		["XP_PROCESS_MAX", "xp_process_max", "XP – zpracování zvěřiny: nejvíc", "XP", ""],
		["TICK_S", "tick_s", "Simulace – krok kazení a hlídání úlovků", "s", ""],
	])
	for k in Hunting.SHOT_WITNESS_R:
		_row(Hunting.SHOT_WITNESS_R, k, "hunting.shot_witness_" + String(k), LOV,
			"Zákon – svědek výstřelu (%s) do" % WEAPON_NAMES.get(k, k), "m", "")
	rows(ShootingRange, "range.", LOV, [
		["STAND_R", "stand_r", "Střelnice – počítá se do vzdálenosti od stolu", "m", ""],
		["LANE_DOT", "lane_dot", "Střelnice – směr výstřelu (cos úhlu k dráze)", "", "", 0.0, 1.0],
		["XP_BASE", "xp_base", "Střelnice – XP za zásah: základ", "XP", ""],
		["XP_PER_PT", "xp_per_pt", "Střelnice – XP za bod", "XP", ""],
		["XP_DIST_M", "xp_dist_m", "Střelnice – XP dvojnásobné na vzdálenost", "m", ""],
	])


# ------------------------------------------------------------------ Oheň a požáry

static func _ohen() -> void:
	for k in Fire.WOOD_MIN:
		_row(Fire.WOOD_MIN, k, "fire.wood_min_" + String(k), OHEN, "Ohniště – hoření kusu: %s" % ItemsDB.name_of(String(k)),
			"herní min", "")
	rows(Fire, "fire.", OHEN, [
		["MAX_FUEL", "max_fuel", "Ohniště – strop přikládání", "herní min", ""],
		["EMBER_MIN", "ember_min", "Ohniště – žhavé uhlíky po dohoření", "herní min", ""],
		["RAIN_K", "rain_k", "Ohniště – déšť zrychlí hoření až o", "+×", ""],
		["HEAT_R_FULL", "heat_r_full", "Ohniště – plné teplo do", "m", ""],
		["HEAT_R", "heat_r", "Ohniště – teplo končí v", "m", ""],
		["HEAT_DY", "heat_dy", "Ohniště – teplo do výškového rozdílu", "m", ""],
		["EMBER_HEAT", "ember_heat", "Ohniště – teplo uhlíků", "×", "", 0.0, 1.0],
	])
	rows(FireManager, "fires.", OHEN, [
		["IGNITE_BASE", "ignite_base", "Zapálení – základní šance", "", "", 0.0, 1.0],
		["IGNITE_RAIN", "ignite_rain", "Zapálení – déšť / sněžení", "", "", -1.0, 0.0],
		["IGNITE_WIND", "ignite_wind", "Zapálení – silný vítr", "", "", -1.0, 0.0],
		["IGNITE_WET", "ignite_wet", "Zapálení – mokré dřevo", "", "", -1.0, 0.0],
		["IGNITE_LIGHTER", "ignite_lighter", "Zapálení – zapalovač navíc", "", "", 0.0, 0.5],
		["IGNITE_SKILL", "ignite_skill", "Zapálení – nejlepší dovednost navíc", "", "", 0.0, 0.5],
		["IGNITE_MIN", "ignite_min", "Zapálení – nejnižší šance", "", "", 0.0, 1.0],
		["IGNITE_MAX", "ignite_max", "Zapálení – nejvyšší šance", "", "", 0.0, 1.0],
		["WIND_HARD", "wind_hard", "Zapálení – silný vítr od", "m/s", ""],
		["WET_HARD", "wet_hard", "Zapálení – mokré dřevo od vlhkosti", "", "", 0.0, 1.0],
		["SNOW_RAIN_K", "snow_rain_k", "Oheň – sněžení hasí jen z části", "× déšť", "", 0.0, 1.0],
		["MIN_GAP", "min_gap", "Oheň – nejmenší odstup ohnišť", "m", ""],
		["WATER_EXTINGUISH_K", "water_extinguish_k", "Hašení – s vodou (× doba)", "×", "", 0.0, 1.0],
		["UNATTENDED_R", "unattended_r", "Požár – oheň je nehlídaný dál od hráče", "m", ""],
		["SPREAD_P_MIN", "spread_p_min", "Požár – šance přeskoku na trávu", "1/herní min", "Jen v létě, za sucha a větru."],
		["SPREAD_WIND", "spread_wind", "Požár – přeskok od větru", "m/s", ""],
		["SPREAD_WIND_REF", "spread_wind_ref", "Požár – vítr, pro který platí šance", "m/s", ""],
		["SPREAD_WIND_MIN_K", "spread_wind_min_k", "Požár – násobek větrem: nejméně", "×", ""],
		["SPREAD_WIND_MAX_K", "spread_wind_max_k", "Požár – násobek větrem: nejvíc", "×", ""],
		["SPREAD_OFFSET", "spread_offset", "Požár – tráva chytne od ohniště", "m", ""],
		["DRY_RAIN_RECENT", "dry_rain_recent", "Požár – „sucho“ pod nedávným deštěm", "", "", 0.0, 1.0],
		["OFFENSE_MIN_R", "offense_min_r", "Zákon – požár je přestupek od poloměru", "m", ""],
		["FOREST_BUFFER", "forest_buffer", "Zákon – oheň do vzdálenosti od lesa", "m", ""],
		["WITNESS_R", "witness_r", "Zákon – svědek ohně do", "m", ""],
		["SMOKE_SEEN_PER_H", "smoke_seen_per_h", "Zákon – odhalení kouře za hodinu", "", "", 0.0, 1.0],
		["KARMA_ILLEGAL", "karma_illegal", "Karma – oheň u lesa", "", ""],
		["REP_SEEN", "rep_seen", "Pověst – viděný oheň u lesa", "", ""],
		["KARMA_FIRE", "karma_fire", "Karma – způsobený požár", "", ""],
		["XP_LIGHT", "xp_light", "XP – zapálení", "XP", ""],
		["XP_LIGHT_FAIL", "xp_light_fail", "XP – nepovedené zapálení", "XP", ""],
		["STOVE_LOGS", "stove_logs", "Kamna – polen na přiložení", "ks", ""],
		["STOVE_LOAD_MIN", "stove_load_min", "Kamna – hoření jednoho přiložení", "herní min", ""],
		["STOVE_MAX_MIN", "stove_max_min", "Kamna – strop", "herní min", ""],
		["XP_STOVE_FRESH", "xp_stove_fresh", "Kamna – XP za zatopení", "XP", ""],
		["XP_STOVE_ADD", "xp_stove_add", "Kamna – XP za přiložení", "XP", ""],
		["STOVE_HEAT", "stove_heat", "Domov – teplo kamen (sušení)", "", "", 0.0, 1.0],
		["RADIATOR_HEAT_K", "radiator_heat_k", "Domov – radiátor suší (× kamna)", "×", "", 0.0, 2.0],
		["HOME_HEATED_TEMP", "home_heated_temp", "Domov – pocitová teplota s topením", "°C", "", 5.0, 35.0],
		["HOME_UNHEATED_OFFSET", "home_unheated_offset", "Domov – bez topení: venku +", "°C", ""],
		["HOME_UNHEATED_MIN", "home_unheated_min", "Domov – bez topení: nejméně", "°C", "", -20.0, 20.0],
		["HOME_UNHEATED_MAX", "home_unheated_max", "Domov – bez topení: nejvíc", "°C", "", 0.0, 30.0],
		["SHELTER_DEFAULT", "shelter_default", "Uvnitř – nejnižší pocitová teplota (mimo domov)", "°C", "", 0.0, 30.0],
		["HOME_COLD_MAX", "home_cold_max", "Domov – prochladnutí po noci nejvýš", "", "", 0.0, 1.0],
		["HOME_COLD_PER_DEG", "home_cold_per_deg", "Domov – prochladnutí za °C pod 5 °C", "1/°C", ""],
		["HOME_COLD_HEAL", "home_cold_heal", "Domov – horší odpočinek v zimě", "HP", ""],
		["SOUP_PORTIONS", "soup_portions", "Kamna – porcí polévky", "ks", ""],
		["SOUP_XP", "soup_xp", "Kamna – XP za polévku", "XP", ""],
	])
	rows(GrassFire, "grass_fire.", OHEN, [
		["MAX_R", "max_r", "Požár trávy – největší poloměr", "m", ""],
		["START_R", "start_r", "Požár trávy – počáteční poloměr", "m", ""],
		["START_SIZE_K", "start_size_k", "Požár trávy – zpočátku míří k podílu největšího", "", "", 0.0, 1.0],
		["GROW_MIN", "grow_min", "Požár trávy – doroste za", "herní min", ""],
		["BURN_MIN", "burn_min", "Požár trávy – dohoří za", "herní min", ""],
		["SUPPRESS_K", "suppress_k", "Požár trávy – jedno hašení zmenší na", "×", "", 0.0, 1.0],
		["OUT_R", "out_r", "Požár trávy – zhasne pod poloměrem", "m", ""],
		["BURN_DPS", "burn_dps", "Požár trávy – popálení", "HP/s", ""],
	])


# ------------------------------------------------------------------ Těžba a řemesla

static func _tezba() -> void:
	rows(Forestry, "forestry.", TEZ, [
		["FELL_TIME_BASE", "fell_time_base", "Kácení – doba: základ", "×", ""],
		["FELL_TIME_H", "fell_time_h", "Kácení – doba: výška pro +1 × základ", "m", ""],
		["FELL_SCALE_MIN", "fell_scale_min", "Kácení – velikost stromu nejméně", "×", ""],
		["FELL_SCALE_MAX", "fell_scale_max", "Kácení – velikost stromu nejvíc", "×", ""],
		["FELL_MIN_S", "fell_min_s", "Pád stromu – nejkratší doba", "s", ""],
		["FELL_PER_M", "fell_per_m", "Pád stromu – navíc za metr výšky", "s/m", ""],
		["FALL_JITTER", "fall_jitter", "Pád stromu – odchylka směru", "rad", ""],
		["HIT_R", "hit_r", "Pád stromu – zasáhne člověka do", "m", ""],
		["HIT_CAR_R", "hit_car_r", "Pád stromu – zasáhne auto do", "m", ""],
		["HIT_FULL_H", "hit_full_h", "Pád stromu – největší zranění od výšky", "m", ""],
		["HIT_FALL_S", "hit_fall_s", "Pád stromu – ležení po zásahu", "s", ""],
		["HIT_CAR_K", "hit_car_k", "Pád stromu – poškození auta (× zranění)", "×", ""],
		["HIT_KNOCK_V", "hit_knock_v", "Pád stromu – odhození vesničana", "m/s", ""],
		["LOP_REF_LEN", "lop_ref_len", "Odvětvení – základní délka kmene", "m", ""],
		["LOP_K_MIN", "lop_k_min", "Odvětvení – doba nejméně", "×", ""],
		["LOP_K_MAX", "lop_k_max", "Odvětvení – doba nejvíc", "×", ""],
		["LOP_DRY_SHARE", "lop_dry_share", "Odvětvení – podíl suchých větví", "", "", 0.0, 1.0],
		["CUT_REF_LEN", "cut_ref_len", "Rozřezání – základní délka kmene", "m", ""],
		["CUT_REF_R", "cut_ref_r", "Rozřezání – základní poloměr", "m", ""],
		["CUT_K_MIN", "cut_k_min", "Rozřezání – doba nejméně", "×", ""],
		["CUT_K_MAX", "cut_k_max", "Rozřezání – doba nejvíc", "×", ""],
		["TRUNK_USE", "trunk_use", "Kmen – použitelný podíl výšky", "", "", 0.0, 1.0],
		["SPALEK_LEN", "spalek_len", "Kmen – délka špalku", "m", ""],
		["POLENA_PER_SPALEK", "polena_per_spalek", "Štípání – polen ze špalku", "ks", ""],
		["VOL_FORM_K", "vol_form_k", "Kmen – tvarový činitel objemu", "", "", 0.0, 1.0],
		["HURT_SAW_MIN", "hurt_saw_min", "Úraz – motorová pila bez pomůcek: nejméně", "HP", ""],
		["HURT_SAW_MAX", "hurt_saw_max", "Úraz – motorová pila bez pomůcek: nejvíc", "HP", ""],
		["HURT_AXE_MIN", "hurt_axe_min", "Úraz – sekera bez pomůcek: nejméně", "HP", ""],
		["HURT_AXE_MAX", "hurt_axe_max", "Úraz – sekera bez pomůcek: nejvíc", "HP", ""],
		["XP_VOLUME_FULL", "xp_volume_full", "XP – kácení: maximum od objemu", "m³", ""],
		["OWN_GARDEN_R", "own_garden_r", "Zákon – vlastní pozemek do vzdálenosti od dveří", "m", ""],
		["RENTED_MARGIN", "rented_margin", "Zákon – okraj pronajaté zahrady", "m", ""],
		["ROAD_R", "road_r", "Zákon – ohrožení provozu do vzdálenosti od silnice", "m", ""],
		["HEAR_AXE", "hear_axe", "Zákon – sekeru je slyšet do", "m", ""],
		["HEAR_SAW", "hear_saw", "Zákon – motorovou pilu je slyšet do", "m", ""],
		["WOOD_KC_PER_M3", "wood_kc_per_m3", "Zákon – cena dřeva", "Kč/m³", ""],
		["CRIME_VALUE_KC", "crime_value_kc", "Zákon – trestný čin od hodnoty za den", "Kč", ""],
		["SEVERITY_VALUE_KC", "severity_value_kc", "Zákon – nejtěžší přestupek od hodnoty", "Kč", ""],
		["KARMA_UNSEEN", "karma_unseen", "Karma – kácení v cizím bez svědků", "", ""],
	])
	for i in Forestry.XP_FELL.size():
		_row(Forestry.XP_FELL, i, "forestry.xp_fell_%s" % ["min", "max"][i], TEZ,
			"XP – kácení: %s strom" % ["malý", "velký"][i], "XP", "")
	for i in Forestry.HIT_DAMAGE.size():
		_row(Forestry.HIT_DAMAGE, i, "forestry.hit_damage_%s" % ["min", "max"][i], TEZ,
			"Pád stromu – zranění: %s strom" % ["malý", "velký"][i], "HP", "")
	var tool_tables := [[Forestry.FELL_TOOL_K, "fell_k", "Kácení – doba"], [Forestry.LOP_TOOL_K, "lop_k", "Odvětvení – doba"],
		[Forestry.CUT_TOOL_K, "cut_k", "Rozřezání – doba"], [Forestry.SPLIT_TOOL_K, "split_k", "Štípání – doba"],
		[Forestry.HURT_NO_GEAR, "hurt_p", "Úraz – šance bez pomůcek"]]
	for t in tool_tables:
		var d: Dictionary = t[0]
		for k in d:
			_row(d, k, "forestry.%s_%s" % [t[1], k], TEZ, "%s: %s" % [t[2], TOOL_NAMES.get(k, k)],
				"" if t[1] == "hurt_p" else "×", "", 0.0, 1.0 if t[1] == "hurt_p" else 3.0 * float(d[k]))
	rows(Klesti, "klesti.", TEZ, [
		["DRY_DROUGHT_K", "dry_drought_k", "Klestí – sucho zrychlí schnutí", "×", ""],
		["DRY_RAIN_K", "dry_rain_k", "Klestí – déšť zpomalí schnutí", "×", "", 0.0, 1.0],
		["MAX_TAKE", "max_take", "Klestí – nejvíc větví najednou", "ks", ""],
	])
	rows(Skills, "skills.", TEZ, [
		["BASE", "base", "Dovednosti – XP křivka: základ", "XP", "XP pro úroveň L = BASE × (GROWTH^(L−1) − 1) / (GROWTH − 1)."],
		["GROWTH", "growth", "Dovednosti – XP křivka: růst", "×", "", 1.01, 1.5],
		["CHAT_XP", "chat_xp", "Výřečnost – XP za slušnou větu", "XP", ""],
		["CHAT_COOLDOWN_S", "chat_cooldown_s", "Výřečnost – rozestup odměněných vět", "s", ""],
		["DRIVE_M_PER_XP", "drive_m_per_xp", "Řízení – metrů na 1 XP", "m", ""],
		["DRIVE_MAX_PROMILE", "drive_max_promile", "Řízení – XP jen do", "‰", ""],
		["DRIVE_MIN_SPEED", "drive_min_speed", "Řízení – XP od rychlosti", "m/s", ""],
		["CRASH_IMPACT", "crash_impact", "Řízení – nehoda od síly nárazu", "", ""],
		["CRASH_PAUSE_S", "crash_pause_s", "Řízení – po nehodě bez XP", "s", ""],
		["SPRINT_XP_PER_S", "sprint_xp_per_s", "Kondice – XP za sekundu sprintu", "XP/s", ""],
	])
	for k in Skills.HORSE_XP_PER_S:
		_row(Skills.HORSE_XP_PER_S, k, "skills.horse_xp_%d" % int(k), TEZ,
			"Jezdectví – XP za sekundu: %s" % ["", "krok", "klus", "cval", "trysk"][clampi(int(k), 0, 4)], "XP/s", "")
	for k in Skills.EVENT_XP:
		var e: Array = Skills.EVENT_XP[k]
		_row(e, 1, "skills.event_xp_" + String(k), TEZ, "XP za událost: %s (%s)" % [String(k).replace("_", " "), String(e[0])],
			"XP", "")


# ------------------------------------------------------------------ Návykové látky a efekty

static func _navykove() -> void:
	rows(Player, "player.", NAV, [
		["DRINK_S_PER_500ML", "drink_s_per_500ml", "Pití – doba na půl litru", "s", ""],
		["DRINK_MIN_S", "drink_min_s", "Pití – nejkratší napití", "s", ""],
		["DRINK_MAX_S", "drink_max_s", "Pití – nejdelší napití", "s", ""],
		["EAT_S", "eat_s", "Jídlo – doba", "s", ""],
		["SMOKE_LIGHT_S", "smoke_light_s", "Kouření – zapálení (pak se dá chodit)", "s", ""],
		["SMOKE_S", "smoke_s", "Kouření – doba cigarety", "s", ""],
		["VOMIT_S", "vomit_s", "Zvracení – doba", "s", ""],
	])
	rows(BodyState, "body.", NAV, [
		["NICOTINE_PER_CIG", "nicotine_per_cig", "Nikotin – za cigaretu", "mg", ""],
		["NICOTINE_DECAY", "nicotine_decay", "Nikotin – odbourávání", "1/h", "Poločas ~2 h."],
		["NICOTINE_FOCUS_MIN", "nicotine_focus_min", "Nikotin – „zaostří“ opilost od", "mg", ""],
		["NICOTINE_FOCUS_K", "nicotine_focus_k", "Nikotin – opilost s nikotinem", "×", "", 0.0, 1.0],
		["TAR_DECAY", "tar_decay", "Kouření – dehet z plic", "cig/h", ""],
		["SMOKE_NAUSEA_PROMILE", "smoke_nausea_promile", "Kouření – v opilosti dělá nevolno od", "‰", ""],
		["SMOKE_NAUSEA", "smoke_nausea", "Kouření – nevolnost v opilosti", "", ""],
		["CRAVING_NICOTINE_MIN", "craving_nicotine_min", "Chuť na cigaretu – roste pod nikotinem", "mg", ""],
		["CRAVING_RATE", "craving_rate", "Chuť na cigaretu – růst", "1/h", ""],
		["CRAVING_BASE_CAP", "craving_base_cap", "Chuť na cigaretu – strop bez závislosti", "", "", 0.0, 1.0],
		["CRAVING_SLEEP_K", "craving_sleep_k", "Chuť na cigaretu – ve spánku", "×", "", 0.0, 1.0],
		["ADDICTION_DECAY_K", "addiction_decay_k", "Závislost – útlum průměru kouření", "1/h", "Poločas ~12 h."],
		["ADDICTION_NORM", "addiction_norm", "Závislost – plná při průměru kouření", "", "~2 krabičky denně."],
		["CAFFEINE_MAX", "caffeine_max", "Kofein – strop", "", ""],
		["CAFFEINE_DECAY", "caffeine_decay", "Kofein – odbourávání", "1/h", ""],
		["THC_HALF_H", "thc_half_h", "Konopí – poločas THC", "h", ""],
		["EDIBLE_THC_DELAY_H", "edible_thc_delay_h", "Konopí – nástup po snědení", "h", ""],
		["THC_SPEED", "thc_speed", "Konopí – zpomalení reakcí na 1,0 THC", "×", "", 0.0, 1.0],
		["THC_STRONG", "thc_strong", "Konopí – nevolnost nad hladinou", "", ""],
		["THC_STRONG_NAUSEA", "thc_strong_nausea", "Konopí – nevolnost ze silné dávky", "", ""],
		["THC_NAUSEA", "thc_nausea", "Konopí – nevolnost za hodinu nad hladinou", "1/h", ""],
		["PSILO_HALF_H", "psilo_half_h", "Lysohlávky – poločas psilocybinu", "h", ""],
		["PSILO_NAUSEA", "psilo_nausea", "Lysohlávky – nevolnost za hodinu", "1/h", ""],
		["PSILO_NAUSEA_FROM", "psilo_nausea_from", "Lysohlávky – nevolnost od hladiny", "", ""],
		["MUSHROOM_TOXIC_HP", "mushroom_toxic_hp", "Muchomůrka – ztráta zdraví (× síla jedu)", "HP", ""],
		["TOXIC_NAUSEA", "toxic_nausea", "Muchomůrka – nevolnost (× síla jedu)", "", ""],
	])
	rows(Consumables, "consumables.", NAV, [
		["ETHANOL_DENSITY", "ethanol_density", "Alkohol – hustota ethanolu", "g/ml", "Gramy alkoholu = ml × obj. % × hustota."],
	])
	rows(DrunkFx, "drunk_fx.", NAV, [
		["DOUBLE_FROM", "double_from", "Efekty – dvojité vidění od", "‰", ""],
		["DOUBLE_FULL", "double_full", "Efekty – dvojité vidění naplno", "‰", ""],
		["BLUR_FROM", "blur_from", "Efekty – rozmazání od", "‰", ""],
		["BLUR_FULL", "blur_full", "Efekty – rozmazání naplno", "‰", ""],
		["TUNNEL_FROM", "tunnel_from", "Efekty – tunelové vidění od", "‰", ""],
		["TUNNEL_FULL", "tunnel_full", "Efekty – tunelové vidění naplno", "‰", ""],
		["TUNNEL_MAX", "tunnel_max", "Efekty – nejsilnější tunelové vidění", "", "", 0.0, 1.0],
		["NAUSEA_FX_FROM", "nausea_fx_from", "Efekty – houpání obrazu od nevolnosti", "", "", 0.0, 0.99],
		["PSILO_WAVE_K", "psilo_wave_k", "Efekty – vlnění na 1,0 psilocybinu", "", ""],
		["PSILO_WAVE_MAX", "psilo_wave_max", "Efekty – strop vlnění z psilocybinu", "", "", 0.0, 1.0],
		["HURT_FLASH_HP", "hurt_flash_hp", "Efekty – plný záblesk při zranění", "HP", ""],
		["HURT_FADE", "hurt_fade", "Efekty – odeznění záblesku", "1/s", ""],
	])
