## Fyziologie hráče – simulátor účinků alkoholu, jídla a cigaret.
##
## Alkohol (Widmarkův model se vstřebáváním):
##   žaludek → (vstřebávání, k_abs ~ 6/h nalačno, s plným žaludkem až 4× pomaleji) → tělo
##   promile = alkohol v těle [g] / (r · hmotnost [kg]),  r ≈ 0,68 (u obezity nižší – tuk vodu neváže)
##   odbourávání ~0,15 ‰/h (jídlo v žaludku ho zrychlí až o 40 %, část alkoholu se odbourá už v žaludku)
## Jídlo: kcal do žaludku → trávení ~500 kcal/h → energetická bilance → hmotnost / BMI
##   (herní zrychlení: 1 kg tuku ≈ 7700 kcal / OBESITY_GAIN).
## Cigarety: nikotin (poločas ~2 h), chuť na cigaretu, dehet v plicích snižuje výdrž.
##   Závislost (`addiction`) je klouzavý průměr kouření (poločas 12 h): příležitostný
##   kuřák (1–2 denně) zůstává hluboko pod 0,1, těžký kuřák (2 krabičky/den, tj. 40 ks)
##   se ustálí kolem 1,0. Třes z abstinence se odvíjí od `craving * addiction`, takže
##   viditelně třese jen u fakticky závislé postavy a vždy zůstává hratelný (malá amplituda).
## Vše běží v herním čase (Clock.TIME_SCALE herních sekund za 1 s reálného času).
class_name BodyState
extends Node

signal vomited
signal passed_out
signal injured(amount: float, reason: String)
signal knocked_out(reason: String)

static var HEIGHT_M := 1.80
static var OBESITY_GAIN := 6.0          # herní zrychlení tloustnutí
static var KCAL_PER_KG := 7700.0
static var BETA := 0.15                 # ‰ / h odbourávání (průměrný muž)
# --- počasí na těle (env z Player._update_body: rain 0..1, temp °C, wind m/s, in bool)
static var WET_RAIN := 1.1              # /h – promočení při rain = 1 (liják)
static var WET_DRY_IN := 0.7            # /h – schnutí pod střechou / uvnitř
static var WET_DRY_OUT := 0.35          # /h – venku za sucha (škáluje teplotou a větrem)
static var COLD_COMFORT := 13.0         # °C – pocitová teplota, od které tělo chladne
static var CHILL_RATE := 0.016          # /h·°C – růst prochladnutí pod pohodlí
static var WARM_RATE := 0.09            # /h·°C – zahřívání v teple
static var HEAT_DRY_K := 3.0            # u ohně / kamen (heat = 1) se schne o tolik násobků rychleji navíc (celkem 4×)
static var HEAT_WARM_C := 14.0          # °C, o které oheň (heat = 1) zvedne pocitovou teplotu
static var SHELTER_MIN_C := 18.0        # výchozí nejnižší pocitová teplota pod střechou
# --- oblečení (M2.3; Wardrobe.refresh nastavuje `insulation` a `waterproof`)
static var INSUL_BASE := 0.4            # izolace výchozího oblečení (triko + džíny + polobotky) – s ním platí COLD_COMFORT beze změny
static var INSUL_COMFORT_C := 12.0      # °C, o které každá 1,0 izolace navíc posune pohodlí (tepleji oblečený snese větší mráz)
static var INSUL_MAX := 1.5             # strop součtu izolace
static var OVERHEAT_TEMP := 25.0        # °C – nad tuto teplotu v silném oblečení hrozí přehřátí
static var OVERHEAT_INSUL := 0.8        # izolace, od které se přehřívá
static var OVERHEAT_RATE := 0.6         # /h za (°C nad limit × izolace nad limit)
static var OVERHEAT_STAMINA := 0.2      # o tolik přehřátí (1,0) snižuje maximální výdrž
# --- M4.8 návykové látky (jen při „Obsah pro dospělé“): THC (konopí) a psilocybin (lysohlávky) – mírné, nepříjemné efekty
static var THC_HALF_H := 1.5            # h – poločas THC v krvi (kouření: rychlý nástup, krátké)
static var EDIBLE_THC_DELAY_H := 1.0  # h – nástup THC po snědení (pomalejší než kouření)
static var MUSHROOM_TOXIC_HP := 12.0    # zdraví ztracené při otravě muchomůrkou (× síla jedu) – ladit
static var PSILO_HALF_H := 3.0          # h – poločas psilocybinu (snědení: pomalý nástup, déle)
static var THC_SPEED := 0.12            # zpomalení reakce (speed_mult) na 1,0 THC
static var THC_NAUSEA := 0.02           # nevolnost za hodinu nad THC 1,5
static var PSILO_NAUSEA := 0.03         # nevolnost za hodinu při psilocybinu (1,0)
# --- závislost na nikotinu (M.smoke)
static var ADDICTION_DECAY_K := 0.0578  # /h – poločas klouzavého průměru kouření ~12 h
static var ADDICTION_NORM := 80.0       # _smoke_rate odpovídající ustálené závislosti 1,0 (~2 krabičky/den)
static var CRAVING_NICOTINE_MIN := 0.25 # mg – pod touto hladinou nikotinu chuť roste (po cigaretě ~4 h herních)
static var CRAVING_RATE := 0.07         # /h – růst chuti (do plné chuti zhruba 14 h herních, tj. ~30 min reálně)
static var CRAVING_BASE_CAP := 0.35     # strop chuti u nezávislé postavy; závislost ho zvedá až k 1,0
static var CRAVING_SLEEP_K := 0.2       # násobek růstu chuti ve spánku (spící po ránu nevstává s 100% chutí)

## M8.D2b: čísla, která dřív byla přímo ve vzorcích – laditelné v menu F3 (Člověk / Tělo, Činnosti / Návykové
## látky). Výchozí hodnoty = původní čísla (chování beze změny).
static var WIDMARK_BASE := 0.68            # Widmarkův faktor při BMI 24
static var WIDMARK_BMI_K := 0.006          # pokles faktoru na 1 BMI navíc
static var WIDMARK_BMI_REF := 24.0         # BMI, při kterém platí základ
static var WIDMARK_MIN := 0.52
static var WIDMARK_MAX := 0.72
static var FIRST_PASS_BASE := 0.05         # podíl alkoholu odbouraný už v žaludku nalačno
static var FIRST_PASS_FOOD := 0.15         # + s plným žaludkem
static var FOOD_FULL_KCAL := 600.0         # kcal v žaludku = „plný žaludek“ (food_factor 1)
static var ELIM_FOOD_K := 0.4              # jídlo zrychlí odbourávání až o tolik
static var ELIM_KM := 1.5                  # g – pod touto hladinou odbourávání přechází do 1. řádu
static var ABSORB_RATE := 6.0              # /h – vstřebávání ze žaludku nalačno
static var ABSORB_FOOD_KCAL := 250.0       # kcal v žaludku, které vstřebávání zpomalí na polovinu
static var ETHANOL_KCAL_G := 7.0           # kcal z 1 g odbouraného alkoholu
static var DRUNK_FROM := 0.15              # ‰ – od kdy je opilost znát (drunk_level 0)
static var DRUNK_FULL := 3.0               # ‰ – opilost naplno (drunk_level 1)
static var NICOTINE_FOCUS_MIN := 0.3       # mg – nad touto hladinou nikotin krátce „zaostří“
static var NICOTINE_FOCUS_K := 0.88        # × opilost s nikotinem
static var SPEED_BMI_FROM := 26.0          # BMI – od kdy obezita zpomaluje
static var SPEED_BMI_K := 0.025            # zpomalení na 1 BMI navíc
static var SPEED_DRUNK_FROM := 1.2         # ‰ – od kdy opilost zpomaluje
static var SPEED_DRUNK_K := 0.12           # zpomalení na ‰
static var SPEED_COLD_K := 0.08            # zpomalení při plném prochladnutí
static var SPEED_MIN := 0.45               # nejpomalejší (× rychlost)
static var STAM_TAR_K := 0.012             # ztráta max. výdrže na 1 cigaretu dehtu
static var STAM_TAR_MAX := 0.45            # strop ztráty výdrže dehtem
static var STAM_COLD_K := 0.35             # ztráta max. výdrže při plném prochladnutí
static var STAM_BMI_FROM := 27.0           # BMI – od kdy obezita snižuje výdrž
static var STAM_BMI_K := 0.03              # ztráta výdrže na 1 BMI navíc
static var STAM_MIN := 0.25                # nejnižší max. výdrž
static var DRAIN_BMI_FROM := 26.0          # BMI – od kdy obezita zrychluje únavu
static var DRAIN_BMI_K := 0.08             # zrychlení únavy na 1 BMI navíc
static var DRAIN_TAR_K := 0.01             # zrychlení únavy na 1 cigaretu dehtu
static var DRAIN_TAR_MAX := 0.4
static var DRAIN_COLD_K := 0.5             # zrychlení únavy při plném prochladnutí
static var DRAIN_HEAT_K := 0.4             # zrychlení únavy při plném přehřátí
static var JUMP_BMI_FROM := 27.0           # BMI – od kdy obezita snižuje skok
static var JUMP_BMI_K := 0.03
static var JUMP_MIN := 0.6                 # nejnižší násobek skoku
static var DRINK_KCAL_K := 0.4             # podíl kcal nápoje ze sacharidů (zbytek z alkoholu při odbourání)
static var CAFFEINE_MAX := 1.5
static var DRINK_NAUSEA_PROMILE := 1.4     # ‰ – panák na lačno nad touto hladinou zvedá žaludek
static var DRINK_NAUSEA_EMPTY_KCAL := 150.0  # kcal – „lačný“ žaludek
static var DRINK_NAUSEA_K := 0.06          # nevolnost na 20 g alkoholu
static var TOXIC_NAUSEA := 0.5             # nevolnost z jedovaté houby (× síla jedu)
static var OVEREAT_KCAL := 1600.0          # kcal v žaludku = přejedení
static var OVEREAT_PROMILE := 1.0          # ‰ – přejedení v opilosti zvedá žaludek
static var OVEREAT_NAUSEA := 0.15
static var NICOTINE_PER_CIG := 1.1         # mg nikotinu za cigaretu
static var SMOKE_NAUSEA_PROMILE := 1.2     # ‰ – cigareta v opilosti „točí“
static var SMOKE_NAUSEA := 0.08
static var THC_STRONG := 1.5               # THC nad touto hladinou = nevolnost
static var THC_STRONG_NAUSEA := 0.05       # nevolnost ze silné dávky konopí
static var PSILO_NAUSEA_FROM := 0.3        # psilocybin nad touto hladinou = nevolnost
static var VOMIT_ALC_KEEP := 0.25          # podíl alkoholu, který po zvracení zůstane v žaludku
static var VOMIT_FOOD_KEEP := 0.2          # podíl jídla, který zůstane
static var VOMIT_HP := 2.0                 # zdraví za zvracení
static var DRY_BASE_K := 0.3               # schnutí venku – základ (× WET_DRY_OUT)
static var DRY_TEMP_C := 22.0              # °C, při kterých teplota přidá plné schnutí
static var DRY_TEMP_MAX := 1.3             # strop příspěvku teploty
static var DRY_WIND_K := 0.03              # příspěvek větru na m/s
static var WINDCHILL_K := 0.6              # °C ochlazení na m/s větru (suchý oděv)
static var WINDCHILL_WET_K := 0.9          # + °C na m/s při promoklém oděvu
static var WET_CHILL_C := 7.0              # °C ochlazení promoklým oděvem
static var OVERHEAT_DECAY := 0.5           # /h – ústup přehřátí
static var COLD_HURT_FROM := 0.85          # prochladnutí, od kterého ubývá zdraví
static var COLD_HURT_K := 9.0              # zdraví za hodinu na jednotku nad prahem
static var DIGEST_KCAL_H := 500.0          # kcal/h – trávení
static var BMR_KCAL_H := 75.0              # kcal/h – bazální výdej v bdělosti
static var BMR_SLEEP_KCAL_H := 60.0        # kcal/h – ve spánku
static var WEIGHT_MIN := 52.0              # kg – nejnižší hmotnost
static var NICOTINE_DECAY := 0.35          # /h – odbourávání nikotinu (poločas ~2 h)
static var TAR_DECAY := 0.04               # cigaret dehtu za hodinu z plic
static var CAFFEINE_DECAY := 0.25          # /h
static var NAUSEA_RISE_PROMILE := 1.3      # ‰ – rychlé pití nad touto hladinou dělá nevolno
static var NAUSEA_RISE_RATE := 0.8         # ‰/h – „rychlé pití“
static var NAUSEA_RISE_K := 0.9            # nevolnost za hodinu na ‰/h nad prahem
static var NAUSEA_HIGH_PROMILE := 2.2      # ‰ – nad touto hladinou nevolnost roste sama
static var NAUSEA_HIGH_K := 0.8
static var NAUSEA_CALM_PROMILE := 1.0      # ‰ – pod touto hladinou nevolnost ustupuje
static var NAUSEA_RECOVER := 0.5           # /h
static var POISON_PROMILE := 3.0           # ‰ – otrava alkoholem
static var POISON_HP := 25.0               # zdraví za hodinu na ‰ nad prahem
static var HEAL_H := 1.5                   # zdraví za hodinu (bdělost)
static var HEAL_SLEEP_H := 6.0             # zdraví za hodinu ve spánku
static var PASSOUT_PROMILE := 3.0          # ‰ – od kdy hrozí okno
static var PASSOUT_K := 0.9                # šance okna za hodinu na ‰ nad prahem
static var PASSOUT_CAFFEINE_K := 0.5       # × šance s kofeinem
static var PASSOUT_CD_H := 1.0             # h – nejkratší rozestup oken

var weight := 82.0                 # kg
var stomach_alc := 0.0             # g ethanolu v žaludku
var body_alc := 0.0                # g ethanolu v těle (krev + tkáně)
var stomach_kcal := 0.0            # jídlo v žaludku (kcal)
var nicotine := 0.0                # mg v krvi
var tar := 0.0                     # "dehet" v plicích (počet cigaret, pomalu klesá)
var craving := 0.0                 # 0..1 chuť na cigaretu
var ever_smoked := false
var addiction := 0.0               # 0..1 skutečná závislost (klouzavý průměr kouření, ne jen poslední cigareta)
var _smoke_rate := 0.0             # interní akumulátor pro `addiction` (viz ADDICTION_NORM)
var thc := 0.0                     # M4.8: THC v krvi (0..~2), konopí; výchozí 0 = starý save bez klíče
var _thc_later: Array = []          # M4.8: snědené THC, které ještě nezačalo působit [zbývá h, síla] (neukládá se)
var psilo := 0.0                   # M4.8: psilocybin (0..~2), lysohlávky; výchozí 0
var caffeine := 0.0                # 0..1
var nausea := 0.0                  # 0..1 → zvracení
var health := 100.0
var alive := true
var total_alc_g := 0.0             # statistika za hru
var total_kcal := 0.0
var cigarettes_smoked := 0
var drinks := 0
var wetness := 0.0                 # promoknutí oblečení 0..1 (déšť, brodění)
var cold := 0.0                    # prochladnutí těla 0..1 (vítr + mráz + mokrý)
var insulation := INSUL_BASE       # tepelná izolace oblečení (součet `insul`, max INSUL_MAX; M2.3)
var waterproof := 0.0              # nepromokavost oblečení 0..1 (váženě trup + bunda, hlava, nohy + boty)
var overheat := 0.0                # přehřátí v létě v zimním oblečení 0..1 (menší výdrž)

var _prev_promile := 0.0
var _rise := 0.0                   # ‰/h, vyhlazené
var _passout_cool := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


# ------------------------------------------------------------------ odvozené hodnoty

func bmi() -> float:
	return weight / (HEIGHT_M * HEIGHT_M)


## Widmarkův faktor – podíl vody v těle; obézní člověk má vyšší promile při stejné dávce.
func widmark_r() -> float:
	return clampf(WIDMARK_BASE - WIDMARK_BMI_K * (bmi() - WIDMARK_BMI_REF), WIDMARK_MIN, WIDMARK_MAX)


func promile() -> float:
	return body_alc / (widmark_r() * weight)


## Promile, kterých by hráč dosáhl, kdyby se vstřebalo vše ze žaludku (bez odbourání).
func promile_peak_estimate() -> float:
	var ff := food_factor()
	return (body_alc + stomach_alc * (1.0 - (FIRST_PASS_BASE + FIRST_PASS_FOOD * ff))) / (widmark_r() * weight)


func food_factor() -> float:
	return clampf(stomach_kcal / FOOD_FULL_KCAL, 0.0, 1.0)


func elimination_rate() -> float:          # ‰ / h
	return BETA * (1.0 + ELIM_FOOD_K * food_factor())


## Hodin do střízlivosti (0,00 ‰).
func hours_to_sober() -> float:
	return promile_peak_estimate() / elimination_rate()


## 0 (střízlivý) … 1 (na mol) – řídí vizuální a pohybové efekty.
func drunk_level() -> float:
	var d := smoothstep(DRUNK_FROM, DRUNK_FULL, promile())
	if nicotine > NICOTINE_FOCUS_MIN:
		d *= NICOTINE_FOCUS_K      # nikotin krátkodobě "zaostří"
	return d


func stage_name() -> String:
	var p := promile()
	if p < 0.05:
		return "střízlivý"
	elif p < 0.5:
		return "mírně ovlivněný"
	elif p < 1.0:
		return "podnapilý"
	elif p < 1.5:
		return "opilý"
	elif p < 2.5:
		return "silně opilý"
	elif p < 3.5:
		return "těžká opilost"
	return "otrava alkoholem!"


func stage_color() -> Color:
	var p := promile()
	if p < 0.05:
		return Color(0.55, 0.95, 0.55)
	elif p < 0.5:
		return Color(0.85, 0.95, 0.45)
	elif p < 1.5:
		return Color(1.0, 0.8, 0.3)
	elif p < 2.5:
		return Color(1.0, 0.5, 0.2)
	return Color(1.0, 0.25, 0.25)


func speed_mult() -> float:
	var m := 1.0
	var b := bmi()
	if b > SPEED_BMI_FROM:
		m -= (b - SPEED_BMI_FROM) * SPEED_BMI_K
	var p := promile()
	if p > SPEED_DRUNK_FROM:
		m -= (p - SPEED_DRUNK_FROM) * SPEED_DRUNK_K
	m -= cold * SPEED_COLD_K                     # prochladlý ujede míň
	m -= clampf(thc, 0.0, 1.5) * THC_SPEED   # M4.8: THC zpomaluje reakce
	return clampf(m, SPEED_MIN, 1.0)


func stamina_max() -> float:
	var m := 1.0 - minf(tar * STAM_TAR_K, STAM_TAR_MAX) - cold * STAM_COLD_K - overheat * OVERHEAT_STAMINA
	var b := bmi()
	if b > STAM_BMI_FROM:
		m -= (b - STAM_BMI_FROM) * STAM_BMI_K
	return clampf(m, STAM_MIN, 1.0)


func stamina_drain_mult() -> float:
	return 1.0 + maxf(bmi() - DRAIN_BMI_FROM, 0.0) * DRAIN_BMI_K + minf(tar * DRAIN_TAR_K, DRAIN_TAR_MAX) + cold * DRAIN_COLD_K + overheat * DRAIN_HEAT_K


func jump_mult() -> float:
	return clampf(1.0 - maxf(bmi() - JUMP_BMI_FROM, 0.0) * JUMP_BMI_K, JUMP_MIN, 1.0)


## 0..1 – jak moc je postava při těle (pro vizuál).
func fatness() -> float:
	return clampf((bmi() - 23.0) / 14.0, 0.0, 1.0)


# ------------------------------------------------------------------ konzumace

## Vypije `ml` nápoje `id`. Vrací gramy alkoholu.
func drink(id: String, ml: float) -> float:
	var g := Consumables.ethanol_g(id, ml)
	stomach_alc += g
	total_alc_g += g
	var info := Consumables.info(id)
	var kcal := float(info.get("kcal", 0)) * ml / float(info.get("ml", ml))
	_add_energy(kcal * DRINK_KCAL_K)             # sacharidy; kcal z ethanolu se připíšou při odbourání
	if info.get("caffeine", 0.0) > 0.0:
		caffeine = minf(caffeine + info["caffeine"], CAFFEINE_MAX)
	if g > 0.0:
		drinks += 1
		# panák na lačný žaludek při vyšších promile zvedá žaludek
		if promile() > DRINK_NAUSEA_PROMILE and stomach_kcal < DRINK_NAUSEA_EMPTY_KCAL:
			nausea += DRINK_NAUSEA_K * g / 20.0
	return g


func eat(id: String) -> void:
	var kcal := float(Consumables.info(id)["kcal"])
	dose_psilo(float(Consumables.info(id).get("psilo", 0.0)))   # M4.8: lysohlávky (0 u běžného jídla)
	var te := float(Consumables.info(id).get("thc_eat", 0.0))   # M4.8: konopné pečivo – THC nastoupí až po EDIBLE_THC_DELAY_H
	if te > 0.0:
		_thc_later.append([EDIBLE_THC_DELAY_H, te])
	var tox := float(Consumables.info(id).get("toxic", 0.0))     # M4.8: muchomůrka – otrava (nevolnost, zdraví)
	if tox > 0.0:
		nausea = minf(nausea + TOXIC_NAUSEA * tox, 1.0)
		hurt(MUSHROOM_TOXIC_HP * tox, "otrava houbou")
	stomach_kcal += kcal
	total_kcal += kcal
	_add_energy(kcal)
	# přejedení v opilosti
	if stomach_kcal > OVEREAT_KCAL and promile() > OVEREAT_PROMILE:
		nausea += OVEREAT_NAUSEA


func smoke() -> void:
	nicotine += NICOTINE_PER_CIG
	tar += 1.0
	ever_smoked = true
	cigarettes_smoked += 1
	craving = 0.0
	_smoke_rate += 1.0
	if promile() > SMOKE_NAUSEA_PROMILE:
		nausea += SMOKE_NAUSEA       # "točí se to"


## Zvracení – vyprázdní žaludek (včetně nevstřebaného alkoholu).
func vomit() -> void:
	stomach_alc *= VOMIT_ALC_KEEP
	stomach_kcal *= VOMIT_FOOD_KEEP
	nausea = 0.0
	health = maxf(health - VOMIT_HP, 1.0)
	vomited.emit()


func hurt(amount: float, reason: String) -> void:
	if amount <= 0.0 or not alive:
		return
	health = maxf(health - amount, 0.0)
	injured.emit(amount, reason)
	if health <= 0.0:
		alive = false
		knocked_out.emit(reason)


func heal_full() -> void:
	health = 100.0
	alive = true


## Uplynulý čas (např. spánek) – přepočítá vše najednou po krocích.
func skip_hours(hours: float, sleeping := true) -> void:
	var steps := int(ceil(hours * 12.0))
	for i in steps:
		_step(hours / steps, 0.0, sleeping, {})


## M4.8: vykouření konopí (THC). Tabák jde přes `smoke()`; zde jen stav THC, bez nikotinu a závislosti.
func smoke_thc(strength: float) -> void:
	thc += strength
	if thc > THC_STRONG:
		nausea += THC_STRONG_NAUSEA       # silná dávka = nevolnost (ne odměna)


## M4.8: snědení lysohlávek (psilocybin). Efekty obrazu jsou zatím jen HUD stav (viz otevřené body).
func dose_psilo(strength: float) -> void:
	psilo += strength


func _add_energy(kcal: float) -> void:
	weight += kcal * OBESITY_GAIN / KCAL_PER_KG


# ------------------------------------------------------------------ simulace

## `dt_h` – uplynulé herní hodiny, `activity` – spálené kcal/h navíc (chůze, sprint).
## env: počasí na těle – rain 0..1 (srážky dopadající na postavu), temp °C, wind m/s,
## in = pod střechou / uvnitř (schnutí a zahřátí), heat 0..1 = teplo od ohně / kamen (M2.2: sušení 4×, zahřátí),
## shelter_min = nejnižší pocitová teplota uvnitř (výchozí 18 °C, doma bez topení nižší). Doplňuje Player._update_body.
func update(dt_h: float, activity_kcal_h: float, env := {}) -> void:
	_step(dt_h, activity_kcal_h, false, env)


func _step(dt_h: float, activity_kcal_h: float, sleeping: bool, env := {}) -> void:
	if dt_h <= 0.0:
		return
	# --- počasí na těle: promoknutí oblečení a prochladnutí
	var env_rain: float = env.get("rain", 0.0)
	var env_temp: float = env.get("temp", 15.0)
	var env_wind: float = env.get("wind", 0.0)
	var env_in: bool = env.get("in", false) or sleeping
	var env_heat: float = clampf(env.get("heat", 0.0), 0.0, 1.0)
	var shelter_c: float = env.get("shelter_min", SHELTER_MIN_C)
	var dry_base := WET_DRY_IN if env_in else \
		WET_DRY_OUT * (DRY_BASE_K + clampf(env_temp / DRY_TEMP_C, 0.0, DRY_TEMP_MAX) + env_wind * DRY_WIND_K)
	if env_rain > 0.02:
		wetness = minf(wetness + env_rain * WET_RAIN * (1.0 - clampf(waterproof, 0.0, 1.0)) * dt_h, 1.0)   # pláštěnka promáčení zpomalí
		if env_heat > 0.0:      # oheň promáčení zpomalí
			wetness = maxf(wetness - dry_base * HEAT_DRY_K * env_heat * dt_h, 0.0)
	else:
		wetness = maxf(wetness - dry_base * (1.0 + HEAT_DRY_K * env_heat) * dt_h, 0.0)
	# pocitová teplota: vítr a mokrý oděv ochlazují; uvnitř / pod střechou je teplo, u ohně teplo navíc
	var feels := env_temp - env_wind * (WINDCHILL_K + wetness * WINDCHILL_WET_K) - wetness * WET_CHILL_C + env_heat * HEAT_WARM_C
	if env_in:
		feels = maxf(feels, shelter_c)
	var comfort := COLD_COMFORT - (clampf(insulation, 0.0, INSUL_MAX) - INSUL_BASE) * INSUL_COMFORT_C   # teplé oblečení posune pohodlí dolů
	var chlad := comfort - feels
	if chlad > 0.0:
		cold = minf(cold + chlad * CHILL_RATE * dt_h, 1.0)
	else:
		cold = maxf(cold + chlad * WARM_RATE * dt_h, 0.0)
	# přehřátí: silné oblečení za horka venku
	if not env_in and env_temp > OVERHEAT_TEMP and insulation > OVERHEAT_INSUL:
		overheat = minf(overheat + (env_temp - OVERHEAT_TEMP) * (insulation - OVERHEAT_INSUL) * OVERHEAT_RATE * dt_h, 1.0)
	else:
		overheat = maxf(overheat - OVERHEAT_DECAY * dt_h, 0.0)
	if not sleeping and cold > COLD_HURT_FROM:
		hurt((cold - COLD_HURT_FROM) * COLD_HURT_K * dt_h, "prochladnutí")
	var ff := food_factor()
	# --- vstřebávání ze žaludku (1. řád)
	var k_abs := ABSORB_RATE / (1.0 + stomach_kcal / ABSORB_FOOD_KCAL)
	var absorbed := stomach_alc * (1.0 - exp(-k_abs * dt_h))
	stomach_alc -= absorbed
	var first_pass := FIRST_PASS_BASE + FIRST_PASS_FOOD * ff
	body_alc += absorbed * (1.0 - first_pass)
	# --- odbourávání v játrech (≈ 0. řád, u nízkých hladin přechází do 1. řádu)
	var cap := elimination_rate() * widmark_r() * weight
	var elim := cap * body_alc / (body_alc + ELIM_KM) * dt_h
	elim = minf(elim, body_alc)
	body_alc -= elim
	_add_energy((elim + absorbed * first_pass) * ETHANOL_KCAL_G)
	# --- trávení
	stomach_kcal = maxf(stomach_kcal - DIGEST_KCAL_H * dt_h, 0.0)
	# --- výdej energie (bazál ~1700 kcal/den + aktivita; spánek nižší)
	var burn := (BMR_SLEEP_KCAL_H if sleeping else BMR_KCAL_H) + activity_kcal_h
	weight = maxf(weight - burn * dt_h * OBESITY_GAIN / KCAL_PER_KG, WEIGHT_MIN)
	# --- nikotin, dehet, chuť
	nicotine *= exp(-dt_h * NICOTINE_DECAY)
	tar = maxf(tar - dt_h * TAR_DECAY, 0.0)
	if ever_smoked and nicotine < CRAVING_NICOTINE_MIN:
		var crave_cap := CRAVING_BASE_CAP + (1.0 - CRAVING_BASE_CAP) * addiction
		var grow := CRAVING_RATE * (CRAVING_SLEEP_K if sleeping else 1.0)
		if craving < crave_cap:
			craving = minf(craving + dt_h * grow, crave_cap)
	_smoke_rate *= exp(-dt_h * ADDICTION_DECAY_K)
	addiction = clampf(_smoke_rate / ADDICTION_NORM, 0.0, 1.0)
	caffeine = maxf(caffeine - dt_h * CAFFEINE_DECAY, 0.0)
	# --- M4.8: THC a psilocybin odeznívají; při vyšší hladině nevolnost (žádné bonusy)
	var keep := []
	for e in _thc_later:
		e[0] = float(e[0]) - dt_h
		if float(e[0]) <= 0.0:
			thc += float(e[1])
		else:
			keep.append(e)
	_thc_later = keep
	thc *= exp(-dt_h * log(2.0) / THC_HALF_H)
	psilo *= exp(-dt_h * log(2.0) / PSILO_HALF_H)
	if thc > THC_STRONG:
		nausea = minf(nausea + THC_NAUSEA * dt_h, 1.0)
	if psilo > PSILO_NAUSEA_FROM:
		nausea = minf(nausea + PSILO_NAUSEA * psilo * dt_h, 1.0)
	# --- nevolnost
	var p := promile()
	var rate := (p - _prev_promile) / dt_h
	_prev_promile = p
	_rise = lerpf(_rise, rate, clampf(dt_h * 8.0, 0.0, 1.0))
	if p > NAUSEA_RISE_PROMILE and _rise > NAUSEA_RISE_RATE:
		nausea += dt_h * NAUSEA_RISE_K * (_rise - NAUSEA_RISE_RATE)
	if p > NAUSEA_HIGH_PROMILE:
		nausea += dt_h * (p - NAUSEA_HIGH_PROMILE) * NAUSEA_HIGH_K
	if p < NAUSEA_CALM_PROMILE and stomach_kcal < OVEREAT_KCAL:
		nausea = maxf(nausea - dt_h * NAUSEA_RECOVER, 0.0)
	if nausea >= 1.0 and not sleeping:
		vomit()
	# --- otrava alkoholem
	if p > POISON_PROMILE:
		hurt((p - POISON_PROMILE) * POISON_HP * dt_h, "otrava alkoholem")
	elif health < 100.0 and alive:
		health = minf(health + dt_h * (HEAL_SLEEP_H if sleeping else HEAL_H), 100.0)
	# --- ztráta vědomí (okno)
	_passout_cool = maxf(_passout_cool - dt_h, 0.0)
	if not sleeping and p > PASSOUT_PROMILE and _passout_cool <= 0.0:
		var chance := (p - PASSOUT_PROMILE) * PASSOUT_K * dt_h * (PASSOUT_CAFFEINE_K if caffeine > 0.3 else 1.0)
		if _rng.randf() < chance:
			_passout_cool = PASSOUT_CD_H
			passed_out.emit()
