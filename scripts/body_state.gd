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

const HEIGHT_M := 1.80
const OBESITY_GAIN := 6.0          # herní zrychlení tloustnutí
const KCAL_PER_KG := 7700.0
const BETA := 0.15                 # ‰ / h odbourávání (průměrný muž)
# --- počasí na těle (env z Player._update_body: rain 0..1, temp °C, wind m/s, in bool)
const WET_RAIN := 1.1              # /h – promočení při rain = 1 (liják)
const WET_DRY_IN := 0.7            # /h – schnutí pod střechou / uvnitř
const WET_DRY_OUT := 0.35          # /h – venku za sucha (škáluje teplotou a větrem)
const COLD_COMFORT := 13.0         # °C – pocitová teplota, od které tělo chladne
const CHILL_RATE := 0.016          # /h·°C – růst prochladnutí pod pohodlí
const WARM_RATE := 0.09            # /h·°C – zahřívání v teple
const HEAT_DRY_K := 3.0            # u ohně / kamen (heat = 1) se schne o tolik násobků rychleji navíc (celkem 4×)
const HEAT_WARM_C := 14.0          # °C, o které oheň (heat = 1) zvedne pocitovou teplotu
const SHELTER_MIN_C := 18.0        # výchozí nejnižší pocitová teplota pod střechou
# --- oblečení (M2.3; Wardrobe.refresh nastavuje `insulation` a `waterproof`)
const INSUL_BASE := 0.4            # izolace výchozího oblečení (triko + džíny + polobotky) – s ním platí COLD_COMFORT beze změny
const INSUL_COMFORT_C := 12.0      # °C, o které každá 1,0 izolace navíc posune pohodlí (tepleji oblečený snese větší mráz)
const INSUL_MAX := 1.5             # strop součtu izolace
const OVERHEAT_TEMP := 25.0        # °C – nad tuto teplotu v silném oblečení hrozí přehřátí
const OVERHEAT_INSUL := 0.8        # izolace, od které se přehřívá
const OVERHEAT_RATE := 0.6         # /h za (°C nad limit × izolace nad limit)
const OVERHEAT_STAMINA := 0.2      # o tolik přehřátí (1,0) snižuje maximální výdrž
# --- závislost na nikotinu (M.smoke)
const ADDICTION_DECAY_K := 0.0578  # /h – poločas klouzavého průměru kouření ~12 h
const ADDICTION_NORM := 80.0       # _smoke_rate odpovídající ustálené závislosti 1,0 (~2 krabičky/den)
const CRAVING_NICOTINE_MIN := 0.25 # mg – pod touto hladinou nikotinu chuť roste (po cigaretě ~4 h herních)
const CRAVING_RATE := 0.07         # /h – růst chuti (do plné chuti zhruba 14 h herních, tj. ~30 min reálně)
const CRAVING_BASE_CAP := 0.35     # strop chuti u nezávislé postavy; závislost ho zvedá až k 1,0
const CRAVING_SLEEP_K := 0.2       # násobek růstu chuti ve spánku (spící po ránu nevstává s 100% chutí)

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
	return clampf(0.68 - 0.006 * (bmi() - 24.0), 0.52, 0.72)


func promile() -> float:
	return body_alc / (widmark_r() * weight)


## Promile, kterých by hráč dosáhl, kdyby se vstřebalo vše ze žaludku (bez odbourání).
func promile_peak_estimate() -> float:
	var ff := food_factor()
	return (body_alc + stomach_alc * (1.0 - (0.05 + 0.15 * ff))) / (widmark_r() * weight)


func food_factor() -> float:
	return clampf(stomach_kcal / 600.0, 0.0, 1.0)


func elimination_rate() -> float:          # ‰ / h
	return BETA * (1.0 + 0.4 * food_factor())


## Hodin do střízlivosti (0,00 ‰).
func hours_to_sober() -> float:
	return promile_peak_estimate() / elimination_rate()


## 0 (střízlivý) … 1 (na mol) – řídí vizuální a pohybové efekty.
func drunk_level() -> float:
	var d := smoothstep(0.15, 3.0, promile())
	if nicotine > 0.3:
		d *= 0.88      # nikotin krátkodobě "zaostří"
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
	if b > 26.0:
		m -= (b - 26.0) * 0.025
	var p := promile()
	if p > 1.2:
		m -= (p - 1.2) * 0.12
	m -= cold * 0.08                     # prochladlý ujede míň
	return clampf(m, 0.45, 1.0)


func stamina_max() -> float:
	var m := 1.0 - minf(tar * 0.012, 0.45) - cold * 0.35 - overheat * OVERHEAT_STAMINA
	var b := bmi()
	if b > 27.0:
		m -= (b - 27.0) * 0.03
	return clampf(m, 0.25, 1.0)


func stamina_drain_mult() -> float:
	return 1.0 + maxf(bmi() - 26.0, 0.0) * 0.08 + minf(tar * 0.01, 0.4) + cold * 0.5 + overheat * 0.4


func jump_mult() -> float:
	return clampf(1.0 - maxf(bmi() - 27.0, 0.0) * 0.03, 0.6, 1.0)


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
	_add_energy(kcal * 0.4)             # sacharidy; kcal z ethanolu se připíšou při odbourání
	if info.get("caffeine", 0.0) > 0.0:
		caffeine = minf(caffeine + info["caffeine"], 1.5)
	if g > 0.0:
		drinks += 1
		# panák na lačný žaludek při vyšších promile zvedá žaludek
		if promile() > 1.4 and stomach_kcal < 150.0:
			nausea += 0.06 * g / 20.0
	return g


func eat(id: String) -> void:
	var kcal := float(Consumables.info(id)["kcal"])
	stomach_kcal += kcal
	total_kcal += kcal
	_add_energy(kcal)
	# přejedení v opilosti
	if stomach_kcal > 1600.0 and promile() > 1.0:
		nausea += 0.15


func smoke() -> void:
	nicotine += 1.1
	tar += 1.0
	ever_smoked = true
	cigarettes_smoked += 1
	craving = 0.0
	_smoke_rate += 1.0
	if promile() > 1.2:
		nausea += 0.08       # "točí se to"


## Zvracení – vyprázdní žaludek (včetně nevstřebaného alkoholu).
func vomit() -> void:
	stomach_alc *= 0.25
	stomach_kcal *= 0.2
	nausea = 0.0
	health = maxf(health - 2.0, 1.0)
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
		WET_DRY_OUT * (0.3 + clampf(env_temp / 22.0, 0.0, 1.3) + env_wind * 0.03)
	if env_rain > 0.02:
		wetness = minf(wetness + env_rain * WET_RAIN * (1.0 - clampf(waterproof, 0.0, 1.0)) * dt_h, 1.0)   # pláštěnka promáčení zpomalí
		if env_heat > 0.0:      # oheň promáčení zpomalí
			wetness = maxf(wetness - dry_base * HEAT_DRY_K * env_heat * dt_h, 0.0)
	else:
		wetness = maxf(wetness - dry_base * (1.0 + HEAT_DRY_K * env_heat) * dt_h, 0.0)
	# pocitová teplota: vítr a mokrý oděv ochlazují; uvnitř / pod střechou je teplo, u ohně teplo navíc
	var feels := env_temp - env_wind * (0.6 + wetness * 0.9) - wetness * 7.0 + env_heat * HEAT_WARM_C
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
		overheat = maxf(overheat - 0.5 * dt_h, 0.0)
	if not sleeping and cold > 0.85:
		hurt((cold - 0.85) * 9.0 * dt_h, "prochladnutí")
	var ff := food_factor()
	# --- vstřebávání ze žaludku (1. řád)
	var k_abs := 6.0 / (1.0 + stomach_kcal / 250.0)
	var absorbed := stomach_alc * (1.0 - exp(-k_abs * dt_h))
	stomach_alc -= absorbed
	var first_pass := 0.05 + 0.15 * ff
	body_alc += absorbed * (1.0 - first_pass)
	# --- odbourávání v játrech (≈ 0. řád, u nízkých hladin přechází do 1. řádu)
	var cap := elimination_rate() * widmark_r() * weight
	var elim := cap * body_alc / (body_alc + 1.5) * dt_h
	elim = minf(elim, body_alc)
	body_alc -= elim
	_add_energy((elim + absorbed * first_pass) * 7.0)
	# --- trávení
	stomach_kcal = maxf(stomach_kcal - 500.0 * dt_h, 0.0)
	# --- výdej energie (bazál ~1700 kcal/den + aktivita; spánek nižší)
	var burn := (60.0 if sleeping else 75.0) + activity_kcal_h
	weight = maxf(weight - burn * dt_h * OBESITY_GAIN / KCAL_PER_KG, 52.0)
	# --- nikotin, dehet, chuť
	nicotine *= exp(-dt_h * 0.35)
	tar = maxf(tar - dt_h * 0.04, 0.0)
	if ever_smoked and nicotine < CRAVING_NICOTINE_MIN:
		var cap := CRAVING_BASE_CAP + (1.0 - CRAVING_BASE_CAP) * addiction
		var grow := CRAVING_RATE * (CRAVING_SLEEP_K if sleeping else 1.0)
		if craving < cap:
			craving = minf(craving + dt_h * grow, cap)
	_smoke_rate *= exp(-dt_h * ADDICTION_DECAY_K)
	addiction = clampf(_smoke_rate / ADDICTION_NORM, 0.0, 1.0)
	caffeine = maxf(caffeine - dt_h * 0.25, 0.0)
	# --- nevolnost
	var p := promile()
	var rate := (p - _prev_promile) / dt_h
	_prev_promile = p
	_rise = lerpf(_rise, rate, clampf(dt_h * 8.0, 0.0, 1.0))
	if p > 1.3 and _rise > 0.8:
		nausea += dt_h * 0.9 * (_rise - 0.8)
	if p > 2.2:
		nausea += dt_h * (p - 2.2) * 0.8
	if p < 1.0 and stomach_kcal < 1600.0:
		nausea = maxf(nausea - dt_h * 0.5, 0.0)
	if nausea >= 1.0 and not sleeping:
		vomit()
	# --- otrava alkoholem
	if p > 3.0:
		hurt((p - 3.0) * 25.0 * dt_h, "otrava alkoholem")
	elif health < 100.0 and alive:
		health = minf(health + dt_h * (6.0 if sleeping else 1.5), 100.0)
	# --- ztráta vědomí (okno)
	_passout_cool = maxf(_passout_cool - dt_h, 0.0)
	if not sleeping and p > 3.0 and _passout_cool <= 0.0:
		var chance := (p - 3.0) * 0.9 * dt_h * (0.5 if caffeine > 0.3 else 1.0)
		if _rng.randf() < chance:
			_passout_cool = 1.0
			passed_out.emit()
