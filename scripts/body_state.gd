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

## M8.16 Tělo 2: tepelná bilance (přepínač realismu „thermo“; vypnuto = stará pravidla „pocitové teploty“ výše).
## Model (00_PRINCIPY kap. 8, zjednodušeně ISO 7730 / Fanger, Gagge): S = M − C(konvekce+záření přes oděv v clo)
## − E(dech, pocení, odpar z mokrého oděvu) + slunce + oheň − vedení do země; S / tepelná kapacita = změna teploty jádra.
## Kůže sleduje jádro (vazokonstrikce), pod 36,8 °C třes, nad 37,1 °C pocení (omezené vlhkostí vzduchu a oděvem).
## Vítr se počítá jen jednou – vlastní konvekce z `Microclimate.wind_speed_at` (ne `wind_chill_at`). Krok 4×/s reálně.
## Laditelné v F3 → Člověk / Tělo – teplo a energie (`scripts/dev/tune_m8_16.gd`).
static var THERMO_STEP_S := 0.25           # s reálného času mezi kroky bilance (4×/s)
static var THERMO_MAX_DT_H := 0.02         # h – nejdelší vnitřní krok (spánek / přeskok času se dělí)
static var BODY_AREA_M2 := 1.9             # povrch těla (DuBois, 82 kg / 180 cm)
static var MET_W_M2 := 58.2                # 1 MET = 58,2 W/m²
static var HEAT_CAP_WH_K := 60.0           # Wh/K – efektivní tepelná kapacita (jádro + část slupky)
static var T_CORE_NORMAL := 37.0
static var T_CORE_MIN := 30.0
static var T_CORE_MAX := 41.5
static var T_SKIN_NEUTRAL := 33.7          # °C – kůže při jádru 37 °C
static var VASO_K := 4.0                   # °C kůže na °C jádra (vazokonstrikce / vazodilatace)
static var T_SKIN_MIN := 26.0
static var T_SKIN_MAX := 36.0
static var SHIVER_FROM := 36.8             # °C jádra – začíná třes
static var SHIVER_W_K := 250.0             # W na °C pod prahem
static var SHIVER_MAX_W := 350.0
static var SWEAT_FROM := 37.1              # °C jádra – začíná pocení
static var SWEAT_W_K := 400.0              # W odparu na °C nad prahem (požadavek)
static var EVAP_CLO_K := 0.021             # m²·kPa/W výparného odporu na 1 clo (Lewisův vztah, i_m ≈ 0,45)
static var LEWIS_K := 16.5                 # K/kPa – Lewisův poměr
static var INSENSIBLE_W := 15.0            # W – neznatelný odpar kůží
static var CLO_PER_INSUL := 1.5            # clo na 1,0 herní izolace (`INSUL_BASE` 0,4 = triko + džíny ≈ 0,6 clo)
static var SLEEP_CLO := 2.5                # clo v posteli / ve spacáku
static var WET_CLO_LOSS := 0.65            # mokré oblečení ztrácí tolik izolace (×wetness)
static var VENT_FROM := 37.2               # °C jádra – hráč se „rozepne“ (izolace klesá)
static var VENT_RANGE := 0.8               # °C – rozsah, ve kterém se rozepne naplno
static var VENT_MAX := 0.5                 # nejvýš tolik izolace ubere rozepnutí
static var WIND_BODY_K := 0.7              # vítr ve výšce těla / vítr v 10 m (logaritmický profil)
static var WALK_AIR_K := 0.6               # podíl rychlosti chůze, který působí jako vítr
static var AIR_MIN_MS := 0.1               # m/s – volná konvekce v bezvětří
static var WIND_CLO_K := 0.04              # stlačení izolace větrem na m/s (bez větruodolné vrstvy)
static var WIND_CLO_MAX := 0.5             # nejvýš tolik izolace vítr ubere
static var HC_BASE := 3.0                  # W/m²K – přestup tepla konvekcí v klidu
static var HC_WIND_K := 8.3                # W/m²K na √(m/s)
static var HR_W_M2K := 4.7                 # W/m²K – sálání (lineárně)
static var FCL_K := 0.15                   # zvětšení povrchu oděvem na 1 clo
static var WATER_HC := 200.0               # W/m²K navíc při úplném ponoření (voda odvádí teplo ~25× víc)
static var IMMERSE_DEPTH := 1.3            # m – hloubka, ve které je tělo ponořené celé
static var SUN_AREA_M2 := 0.35             # efektivní plocha osvětlená sluncem
static var SUN_ABSORB := 0.7               # pohltivost oděvu / kůže
static var CANOPY_SHADE := 0.85            # stín plného zápoje korun
static var NIGHT_SKY_W := 40.0             # W – ztráta sáláním do jasné noční oblohy
static var FIRE_W := 400.0                 # W – teplo od ohně / kamen při heat = 1
static var ROOF_WARM_K := 0.25             # pod střechou venku (zastávka, kůlna) se vzduch přiblíží tolik k `shelter_min`
static var COND_SIT_M2 := 0.15             # m² – styk se zemí v podřepu / vkleče
static var COND_LIE_M2 := 0.5              # m² – vleže
static var COND_R_BASE := 0.05             # m²K/W – odpor styku bez oděvu
static var COND_SNOW_K := 1.5              # sníh / mokrá zem vede víc
static var RESP_LAT_K := 0.0173            # dýchání – latentní ztráta (ISO 7730)
static var RESP_LAT_PA := 5.87             # kPa
static var RESP_CONV_K := 0.0014           # dýchání – citelná ztráta
static var RESP_T := 34.0                  # °C vydechovaného vzduchu
static var WET_EVAP_W := 60.0              # W – odpar z plně mokrého oděvu při sytostním deficitu 1 kPa
# --- metabolismus podle činnosti (MET)
static var MET_SLEEP := 0.9
static var MET_STAND := 1.2
static var MET_SEATED := 1.3               # v autě, v letadle
static var MET_HORSE := 2.2                # jízda na koni
static var MET_WALK_BASE := 1.5            # chůze: základ + k × rychlost (1,4 m/s ≈ 3,5 MET)
static var MET_WALK_PER_MS := 1.4
static var MET_MOVE_V := 0.3               # m/s – od této rychlosti se počítá chůze
static var MET_RUN := 8.0                  # běh (sprint)
static var MET_RUN_V := 4.5                # m/s – od této rychlosti běh
static var MET_SWIM := 7.0
static var MET_CLIMB_PER_MS := 25.0        # MET na m/s stoupání (82 kg × g × v / účinnost 0,25)
static var MET_DESCENT_K := 0.3            # z kopce se ušetří jen část
static var MET_LOAD_PER_KG := 0.05         # MET na kg nákladu při chůzi (20–50 kg → +1–2,5)
static var MET_LOAD_STAND_K := 0.3         # podíl při stání
static var MET_MAX := 12.0
## MET podle pózy činnosti (`Humanoid.action` / anim z `Actions.DEFS`) – nahradí stání, pokud je vyšší.
static var ACTION_MET := {"chop": 6.0, "dig": 5.0, "kneel": 2.0, "pour": 2.5, "cast": 2.0, "aim": 1.5}
# --- mapování teploty jádra na stav (API `cold` / `overheat` zůstává)
static var COLD_CORE_FROM := 36.5          # °C jádra – od kdy roste prochladnutí
static var COLD_CORE_FULL := 35.0          # °C – plné prochladnutí (podchlazení)
static var HEAT_CORE_FROM := 37.6          # °C – od kdy roste přehřátí
static var HEAT_CORE_FULL := 39.0          # °C – plné přehřátí
# --- voda v těle (hydration = litry vůči optimu; záporně = deficit)
static var LATENT_WH_L := 680.0            # Wh na litr odpařené vody
static var SWEAT_DRIP_K := 1.3             # vyprodukovaný pot / odpařený pot
static var SWEAT_WET_PER_L := 0.6          # neodpařený pot (l) promáčí oděv o tolik
static var URINE_L_H := 0.055              # l/h – moč při normální hydrataci
static var URINE_HYDR_L := 1.0             # l – ledviny šetří při deficitu (lineárně)
static var URINE_MIN_K := 0.3
static var HYDR_MAX_L := 0.5               # přebytek nad optimum se vyloučí
static var HYDR_MIN_L := -5.0
static var THIRST_FROM_L := 0.5            # l deficitu – začíná žízeň
static var THIRST_FULL_L := 2.5            # l (~3 % hmotnosti) – silná žízeň / dehydratace
static var DIURESIS_L_G := 0.01            # l moči navíc na 1 g odbouraného alkoholu (pivo hydratuje méně, kořalka odvodní)
static var FOOD_WATER_L_KCAL := 0.0004     # l vody z jídla na kcal
static var STAM_THIRST_K := 0.25           # ztráta max. výdrže při plné žízni
static var DRAIN_THIRST_K := 0.4           # zrychlení únavy při plné žízni
static var HEADACHE_FROM := 0.6            # žízeň, od které bolí hlava (mírný efekt obrazu)
static var HEADACHE_FX := 0.12             # efekt obrazu (jako opilost) při plné dehydrataci
static var DEHYDR_HP_H := 2.0              # zdraví za hodinu při plné dehydrataci
static var STREAM_NAUSEA_CHANCE := 0.08    # šance nevolnosti po vodě z potoka
static var STREAM_NAUSEA := 0.35
# --- spánek a ospalost
static var SLEEP_DEBT_RATE := 1.0          # h dluhu za hodinu bdění
static var SLEEP_RECOVER := 2.0            # h dluhu smazaných hodinou spánku
static var SLEEP_DEBT_MAX := 48.0
static var DROWSY_FROM_H := 16.0           # h bdění – začíná ospalost
static var DROWSY_FULL_H := 30.0           # h – plná ospalost
static var CAFFEINE_AWAKE_K := 0.6         # kofein (1,0) ubere tolik ospalosti
static var DROWSY_FX := 0.3                # ospalost (1,0) = tolik „opilosti“ (reakce, efekt obrazu)
static var STAM_DROWSY_K := 0.15
static var MICROSLEEP_FROM := 0.5          # ospalost, od které hrozí mikrospánek
static var MICROSLEEP_PER_H := 4.0         # mikrospánků za herní hodinu při plné ospalosti
static var MICROSLEEP_S := 1.2             # s reálného času – zatmění obrazu
# --- pád z výšky (rychlost dopadu přepočtená z výšky pádu: v = √(2·g·h))
static var FALL_G := 9.81
static var FALL_PAIN_V := 6.0              # m/s (≈ 2 m) – bolest a krátké kulhání
static var FALL_INJURY_V := 9.0            # m/s (≈ 4 m) – zranění
static var FALL_SEVERE_V := 13.0           # m/s (≈ 9 m) – vážné zranění
static var FALL_KO_V := 15.0               # m/s (≈ 11,5 m) – bezvědomí (probuzení v nemocnici)
static var FALL_PAIN_HP_V := 2.0           # zdraví na m/s nad prahem bolesti
static var FALL_INJ_HP := 10.0             # zdraví při zranění
static var FALL_INJ_HP_V := 6.0            # + na m/s nad prahem zranění
static var FALL_SEVERE_HP := 45.0
static var FALL_DOWN_INJ_S := 2.5          # s ležení po zranění
static var FALL_DOWN_SEVERE_S := 6.0
static var LIMP_H_PER_V := 0.5             # h kulhání na m/s nad prahem bolesti
static var LIMP_INJ_H := 6.0               # h kulhání po zranění
static var LIMP_MAX_H := 48.0
static var LIMP_WALK_K := 0.7              # rychlost chůze při kulhání
static var PAIN_DECAY := 0.3               # /h – ústup bolesti
static var SOFT_SNOW_K := 0.35             # sníh (snow_cover 1) pohltí tolik rychlosti dopadu
static var SOFT_WATER_K := 0.7             # hluboká voda pohltí tolik
static var SOFT_WATER_DEPTH := 1.2         # m – voda „hluboká“ pro dopad

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
# --- M8.16 (ukládá se: t_core, hydration, sleep_debt, limp_h, pain)
var thermo := true                 # přepínač realismu „thermo“ (obnovuje se 4×/s z `World.realism_on`)
var t_core := 37.0                 # °C – teplota jádra
var hydration := 0.0               # l vůči optimu (záporně = deficit → žízeň)
var sleep_debt := 0.0              # h bdění „nesplacené“ spánkem
var limp_h := 0.0                  # h kulhání po pádu
var pain := 0.0                    # 0..1 bolest po pádu (ubývá)
var _thermo_acc_h := 0.0
var _heat_w := 0.0                 # W – poslední bilance (deník: „prochladneš za…“)
var _met := 1.2                    # poslední MET (F2 / deník)
var _wind_body := 0.0              # m/s – poslední vítr na těle (deník)
var _thirst := 0.0                 # 0..1 (odvozeno 4×/s)
var _drowsy := 0.0                 # 0..1
var _fatigue_fx := 0.0             # „opilost“ z ospalosti a bolesti hlavy
var _microsleep_s := 0.0
var _limp_on := false

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
	if thermo and _fatigue_fx > d:
		d = _fatigue_fx            # M8.16: ospalost / bolest hlava z dehydratace – reakce a obraz jako mírná opilost
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
	if thermo:
		m -= _thirst * STAM_THIRST_K + _drowsy * STAM_DROWSY_K     # M8.16
	var b := bmi()
	if b > STAM_BMI_FROM:
		m -= (b - STAM_BMI_FROM) * STAM_BMI_K
	return clampf(m, STAM_MIN, 1.0)


func stamina_drain_mult() -> float:
	return 1.0 + maxf(bmi() - DRAIN_BMI_FROM, 0.0) * DRAIN_BMI_K + minf(tar * DRAIN_TAR_K, DRAIN_TAR_MAX) + cold * DRAIN_COLD_K + overheat * DRAIN_HEAT_K \
		+ (_thirst * DRAIN_THIRST_K if thermo else 0.0)


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
	_add_water(Consumables.water_l(id, ml))      # M8.16: voda z nápoje (alkohol pak odvodní při odbourání)
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
	_add_water(kcal * FOOD_WATER_L_KCAL)         # M8.16: voda z jídla
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
	# M8.16: tepelná bilance (4×/s reálně, ve spánku / při přeskoku času každý krok); vypnuto = stará pravidla
	_thermo_acc_h += dt_h
	if _microsleep_s > 0.0:
		_microsleep_s -= dt_h * 3600.0 / maxf(Clock.TIME_SCALE, 0.001)
	if sleeping or _thermo_acc_h >= THERMO_STEP_S * Clock.TIME_SCALE / 3600.0:
		var acc := _thermo_acc_h
		_thermo_acc_h = 0.0
		_refresh_thermo_switch()
		if thermo:
			var __t0 := Tests.prof_t0()
			_thermo_step(acc, sleeping, env_in, env_temp, env_wind, env_heat, shelter_c)
			Tests.prof_add("body_thermo", __t0)
	if not thermo:
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
	hydration = maxf(hydration - elim * DIURESIS_L_G, HYDR_MIN_L)   # M8.16: alkohol zvyšuje diurézu
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


# ------------------------------------------------------------------ M8.16 Tělo 2: teplo, voda, spánek, pád

## Přepínač realismu „thermo“ (World.realism_on) – bez světa (testy, NPC) zůstává zapnuto.
func _refresh_thermo_switch() -> void:
	var p := get_parent() as Player
	if p == null:
		return
	var w := p.get_parent() as World
	if w != null:
		var on := w.realism_on("thermo")
		if on != thermo:
			thermo = on
			if not on:
				_set_limp(p, false)
				_fatigue_fx = 0.0


## Nasycený tlak vodní páry (kPa, Magnus–Tetens).
static func _psat_kpa(t: float) -> float:
	return 0.6108 * exp(17.27 * t / (t + 237.3))


## Jeden krok bilance za `dt_h` herních hodin (dělí se na vnitřní kroky ≤ THERMO_MAX_DT_H). Prostředí: `env`
## od `Player._update_body` (teplota z `Microclimate.temp_at`, vítr z `wind_speed_at`, déšť, střecha, oheň);
## činnost, náklad, slunce, stín, vlhkost a sníh si krok dočte z hráče a světa (4×/s, žádné alokace).
func _thermo_step(dt_h: float, sleeping: bool, env_in: bool, t_air: float, wind10: float, heat: float,
		shelter_c: float) -> void:
	var p := get_parent() as Player
	var w: World = null
	if p != null:
		w = p.get_parent() as World
	var full_in := sleeping or p == null or p.inside != "" or p.car != null or p.aircraft != null
	if env_in:
		if full_in:
			t_air = maxf(t_air, shelter_c)
		elif shelter_c > t_air:
			t_air += (shelter_c - t_air) * ROOF_WARM_K    # střecha venku: jen závětří a trochu tepla
	# --- metabolismus (MET) podle činnosti
	var met := MET_SLEEP if sleeping else MET_STAND
	var hs := 0.0
	var immerse := 0.0
	var contact := 0.0
	if p != null and not sleeping:
		hs = Vector2(p.velocity.x, p.velocity.z).length()
		if p.car != null or p.aircraft != null:
			met = MET_SEATED
			hs = 0.0
		elif p.horse != null:
			met = MET_HORSE
		elif p.wade > Player.SWIM_DEPTH:
			met = MET_SWIM
		else:
			var load_kg := p.carried_kg()
			if w != null and w.cargo != null:
				load_kg += w.cargo.carried_kg(p.id)
			if hs > MET_MOVE_V:
				met = MET_RUN if hs > MET_RUN_V else MET_WALK_BASE + MET_WALK_PER_MS * hs
				met += load_kg * MET_LOAD_PER_KG
				if p.is_on_floor():
					var vy := p.velocity.y
					met += vy * MET_CLIMB_PER_MS * (1.0 if vy > 0.0 else MET_DESCENT_K)
			else:
				met += load_kg * MET_LOAD_PER_KG * MET_LOAD_STAND_K
			if p.visual != null:
				met = maxf(met, float(ACTION_MET.get(p.visual.action, 0.0)))
			if p.fallen > 0.0:
				contact = COND_LIE_M2
			elif p._crouching or (p.visual != null and p.visual.action == "kneel"):
				contact = COND_SIT_M2
		immerse = clampf(p.wade / IMMERSE_DEPTH, 0.0, 1.0)
	met = clampf(met, MET_SLEEP, MET_MAX)
	_met = met
	# --- prostředí dočtené ze světa (jen venku)
	var rh := 0.7
	var ghi := 0.0
	var night_sky := 0.0
	var snow := 0.0
	if w != null and p != null:
		if w.micro != null:
			rh = w.micro.humidity_at(p.global_position)
		if w.weather != null:
			snow = w.weather.snow_cover
		if not env_in and w.clock != null and w.weather != null:
			var elev := w.clock.sun_elevation()
			if elev > 0.0:
				ghi = Atmosphere.SkyModel.global_horizontal_irradiance_wm2(elev, w.weather.cloud,
					clampf(w.weather.fog, 0.0, 1.0))
				if w.tree_eco != null:
					ghi *= 1.0 - w.tree_eco.canopy_at(p.global_position.x, p.global_position.z) * CANOPY_SHADE
			else:
				night_sky = 1.0 - clampf(w.weather.cloud, 0.0, 1.0)
	if full_in:
		contact = 0.0
	# --- oblečení v clo (mokré a větrem stlačené izoluje hůř; nepromokavá vrstva = větruodolná)
	var clo0 := SLEEP_CLO if sleeping else clampf(insulation, 0.0, INSUL_MAX) * CLO_PER_INSUL
	var v_air := wind10 * WIND_BODY_K + hs * WALK_AIR_K + AIR_MIN_MS
	_wind_body = v_air
	var hc := HC_BASE + HC_WIND_K * sqrt(v_air) + WATER_HC * immerse
	var pa := rh * _psat_kpa(t_air)
	var vpd := clampf(_psat_kpa(t_air) - pa, 0.1, 2.0)
	var t_ground := minf(t_air, 0.0) if snow > 0.3 else t_air
	var area := BODY_AREA_M2
	var n := maxi(int(ceil(dt_h / THERMO_MAX_DT_H)), 1)
	var h := dt_h / n
	var water_l := 0.0
	var wet_add := 0.0
	var q := 0.0
	for i in n:
		var clo := clo0 * (1.0 - wetness * WET_CLO_LOSS)
		if not sleeping:
			clo *= 1.0 - clampf((t_core - VENT_FROM) / VENT_RANGE, 0.0, 1.0) * VENT_MAX
		clo *= 1.0 - minf(WIND_CLO_K * minf(v_air, 15.0), WIND_CLO_MAX) * (1.0 - clampf(waterproof, 0.0, 1.0))
		var fcl := 1.0 + FCL_K * clo
		var r := clo * 0.155 + 1.0 / (fcl * (hc + HR_W_M2K))
		var t_sk := clampf(T_SKIN_NEUTRAL + (t_core - T_CORE_NORMAL) * VASO_K, T_SKIN_MIN, T_SKIN_MAX)
		var m := met * MET_W_M2 * area + minf(maxf(SHIVER_FROM - t_core, 0.0) * SHIVER_W_K, SHIVER_MAX_W)
		var c := area * (t_sk - t_air) / r
		var resp_lat := RESP_LAT_K * m * maxf(RESP_LAT_PA - pa, 0.0)
		var resp := resp_lat + RESP_CONV_K * m * (RESP_T - t_air)
		var e_req := maxf(t_core - SWEAT_FROM, 0.0) * SWEAT_W_K
		var e_max := area * maxf(_psat_kpa(t_sk) - pa, 0.2) / (EVAP_CLO_K * clo + 1.0 / (LEWIS_K * fcl * hc))
		var e_sw := minf(e_req, e_max)
		var e_wet := WET_EVAP_W * wetness * vpd * (1.0 + 0.3 * sqrt(v_air))
		var cond := 0.0
		if contact > 0.0:
			cond = contact * (t_sk - t_ground) / (clo * 0.155 + COND_R_BASE)
			if snow > 0.3 or wetness > 0.5:
				cond *= COND_SNOW_K
		q = m - c - resp - e_sw - e_wet - INSENSIBLE_W - cond + ghi * SUN_AREA_M2 * SUN_ABSORB \
			+ heat * FIRE_W - night_sky * NIGHT_SKY_W
		t_core = clampf(t_core + q / HEAT_CAP_WH_K * h, T_CORE_MIN, T_CORE_MAX)
		water_l += (e_sw * SWEAT_DRIP_K + resp_lat + INSENSIBLE_W) / LATENT_WH_L * h
		if e_req > e_max:
			wet_add += (e_req - e_max) / LATENT_WH_L * h * SWEAT_WET_PER_L
	_heat_w = q
	wetness = minf(wetness + wet_add, 1.0)
	# --- stav pro ostatní systémy (API `cold` / `overheat` beze změny)
	cold = clampf((COLD_CORE_FROM - t_core) / (COLD_CORE_FROM - COLD_CORE_FULL), 0.0, 1.0)
	overheat = clampf((t_core - HEAT_CORE_FROM) / (HEAT_CORE_FULL - HEAT_CORE_FROM), 0.0, 1.0)
	# --- voda v těle
	var urine := URINE_L_H * clampf(1.0 + hydration / URINE_HYDR_L, URINE_MIN_K, 2.0) * dt_h
	hydration = clampf(hydration - water_l - urine, HYDR_MIN_L, HYDR_MAX_L)
	_thirst = clampf((-hydration - THIRST_FROM_L) / (THIRST_FULL_L - THIRST_FROM_L), 0.0, 1.0)
	if _thirst >= 1.0 and not sleeping:
		hurt(DEHYDR_HP_H * dt_h, "dehydratace")
	# --- spánek
	if sleeping:
		sleep_debt = maxf(sleep_debt - SLEEP_RECOVER * dt_h, 0.0)
	else:
		sleep_debt = minf(sleep_debt + SLEEP_DEBT_RATE * dt_h, SLEEP_DEBT_MAX)
	_drowsy = smoothstep(DROWSY_FROM_H, DROWSY_FULL_H, sleep_debt) * (1.0 - clampf(caffeine, 0.0, 1.0) * CAFFEINE_AWAKE_K)
	_fatigue_fx = maxf(_drowsy * DROWSY_FX, smoothstep(HEADACHE_FROM, 1.0, _thirst) * HEADACHE_FX)
	if not sleeping and _drowsy > MICROSLEEP_FROM and _microsleep_s <= 0.0:
		var ch := MICROSLEEP_PER_H * (_drowsy - MICROSLEEP_FROM) / (1.0 - MICROSLEEP_FROM) * dt_h
		if _rng.randf() < ch:
			_microsleep_s = MICROSLEEP_S
	# --- zranění pádem: kulhání a bolest ubývají
	limp_h = maxf(limp_h - dt_h, 0.0)
	pain = maxf(pain - PAIN_DECAY * dt_h, 0.0)
	if p != null:
		_set_limp(p, limp_h > 0.0)


func _set_limp(p: Player, on: bool) -> void:
	if on == _limp_on:
		return
	_limp_on = on
	if on:
		p.set_speed_mod("zraneni_pad", {"walk_k": LIMP_WALK_K, "no_sprint": true})
	else:
		p.clear_speed_mod("zraneni_pad")


func _add_water(l: float) -> void:
	hydration = clampf(hydration + l, HYDR_MIN_L, HYDR_MAX_L)


## Napít se vody ze zdroje (studánka, kohoutek, potok). `source` „potok“ = malé riziko nevolnosti.
func drink_water(ml: float, source := "") -> void:
	_add_water(ml / 1000.0)
	if source == "potok" and _rng.randf() < STREAM_NAUSEA_CHANCE:
		nausea = minf(nausea + STREAM_NAUSEA, 1.0)


## 0..1 – mikrospánek právě teď (zatmění obrazu v `DrunkFx`).
func microsleep_fx() -> float:
	return 1.0 if thermo and _microsleep_s > 0.0 else 0.0


func thirst() -> float:
	return _thirst if thermo else 0.0


func drowsiness() -> float:
	return _drowsy if thermo else 0.0


## Dopad z výšky `drop_m` (m): rychlost dopadu v = √(2·g·h), sníh (`snow` 0..1) a hluboká voda (`wade_m`) ji tlumí.
## Vrací sekundy ležení (> 0 = zranění), 0 = jen bolest a kulhání, −1 = nic.
func fall_landing(drop_m: float, snow: float, wade_m: float) -> float:
	if drop_m <= 0.0:
		return -1.0
	var v := sqrt(2.0 * FALL_G * drop_m)
	v *= 1.0 - clampf(snow, 0.0, 1.0) * SOFT_SNOW_K
	v *= 1.0 - clampf(wade_m / SOFT_WATER_DEPTH, 0.0, 1.0) * SOFT_WATER_K
	if v < FALL_PAIN_V:
		return -1.0
	pain = minf(pain + clampf((v - FALL_PAIN_V) / (FALL_SEVERE_V - FALL_PAIN_V), 0.2, 1.0), 1.0)
	if v < FALL_INJURY_V:
		limp_h = minf(limp_h + (v - FALL_PAIN_V) * LIMP_H_PER_V, LIMP_MAX_H)
		_set_limp_now()
		hurt((v - FALL_PAIN_V) * FALL_PAIN_HP_V, "pád z výšky")
		return 0.0
	limp_h = minf(limp_h + LIMP_INJ_H + (v - FALL_INJURY_V) * LIMP_H_PER_V, LIMP_MAX_H)
	_set_limp_now()
	if v >= FALL_KO_V:
		hurt(health, "pád z výšky")              # bezvědomí → probuzení v nemocnici (knocked_out)
		return FALL_DOWN_SEVERE_S
	if v >= FALL_SEVERE_V:
		hurt(FALL_SEVERE_HP, "pád z výšky")
		return FALL_DOWN_SEVERE_S
	hurt(FALL_INJ_HP + (v - FALL_INJURY_V) * FALL_INJ_HP_V, "pád z výšky")
	return FALL_DOWN_INJ_S


func _set_limp_now() -> void:
	var p := get_parent() as Player
	if p != null:
		_set_limp(p, limp_h > 0.0)


## Starý save bez `t_core`: jádro odvozené z uloženého prochladnutí (ať se stav po načtení neskokově nezmění).
func core_from_cold() -> void:
	if cold > 0.0:
		t_core = COLD_CORE_FROM - cold * (COLD_CORE_FROM - COLD_CORE_FULL)
	else:
		t_core = T_CORE_NORMAL


## Krátký stav pro HUD (prázdný = není co hlásit). Čísla jádra se na HUD neukazují (jen F2 ladění).
func status_text() -> String:
	if not thermo:
		return ""
	var s := ""
	if cold > 0.25:
		s += " · zima" if cold < 0.6 else " · silná zima"
	if overheat > 0.25:
		s += " · horko" if overheat < 0.6 else " · hrozí úpal"
	if _thirst > 0.05:
		s += " · žízeň" if _thirst < 0.6 else " · silná žízeň"
	if _drowsy > 0.1:
		s += " · ospalost" if _drowsy < 0.6 else " · padáš únavou"
	if limp_h > 0.0:
		s += " · zranění (kulháš)"
	elif pain > 0.2:
		s += " · bolest"
	return s.substr(3)


## Oddíl deníku J → Zdraví: srozumitelné věty místo čísel.
func journal_health() -> String:
	if not thermo:
		return ""
	var s := "[b]ZDRAVÍ[/b]\n"
	var lines := 0
	var cooling := _heat_w < -20.0 and t_core > COLD_CORE_FULL
	if cooling:
		var hrs := (t_core - COLD_CORE_FULL) / (-_heat_w / HEAT_CAP_WH_K)
		var when := ""
		if hrs < 0.25:
			when = "za chvíli"
		elif hrs < 0.75:
			when = "za půl hodiny"
		elif hrs < 1.5:
			when = "za hodinu"
		elif hrs < 4.0:
			when = "za pár hodin"
		if when != "":
			var why := "Je ti zima"
			if wetness > 0.4 and _wind_body > 2.0:
				why = "Jsi promoklý a fouká"
			elif wetness > 0.4:
				why = "Jsi promoklý"
			elif _wind_body > 3.0:
				why = "Fouká"
			elif _met < 1.6:
				why = "Stojíš bez hnutí"
			s += "%s – v tomhle oblečení prochladneš %s.\n" % [why, when]
			lines += 1
	if cold > 0.6:
		s += "Jsi podchlazený a třeseš se. Hned do tepla, k ohni nebo se převleč do suchého.\n"
		lines += 1
	elif cold > 0.25 and not cooling:
		s += "Je ti zima, ale už se zahříváš.\n"
		lines += 1
	if overheat > 0.5:
		s += "Je ti horko k padnutí – zpomal, svlékni bundu, napij se a jdi do stínu.\n"
		lines += 1
	elif overheat > 0.2:
		s += "Potíš se, je ti horko.\n"
		lines += 1
	if _thirst > 0.6:
		s += "Máš velkou žízeň a bolí tě hlava. Napij se vody – pivo ani kořalka žízeň neuhasí.\n"
		lines += 1
	elif _thirst > 0.05:
		s += "Máš žízeň.\n"
		lines += 1
	if _drowsy > 0.6:
		s += "Padáš únavou – za volantem hrozí mikrospánek. Vyspi se (kafe pomůže jen na chvíli).\n"
		lines += 1
	elif _drowsy > 0.1:
		s += "Jsi ospalý.\n"
		lines += 1
	if limp_h > 0.0:
		s += "Po pádu kulháš a bolí tě to (ještě asi %d h).\n" % maxi(int(ceil(limp_h)), 1)
		lines += 1
	if lines == 0:
		s += "Cítíš se dobře.\n"
	return s + "\n"


## Ladicí řádek (F2 → Hráč): čísla jádra a bilance.
func debug_text() -> String:
	return "Jádro %.2f °C · bilance %+.0f W · %.1f MET · voda %+.2f l · bdění %.1f h · vítr na těle %.1f m/s" % [
		t_core, _heat_w, _met, hydration, sleep_debt, _wind_body]
