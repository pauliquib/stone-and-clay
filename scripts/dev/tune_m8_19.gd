## M8.19B Výkon, předvolby a uzavření M8: menu pro vývojáře (F3) – skupina **Létání/Hranice letu** (`World.FLY_*`:
## vodorovná hranice letu za katastrem, pásmo varování a protivětru, strop nad terénem). Výchozí hodnoty = kód
## (`static var` ve `world.gd`). `World.flight_bounds` čte proměnné přímo – registr se za snímek nečte.
## Detail přírody podle předvolby (`GameSettings.ECO_LEVELS`) je nastavení hráče (Esc → Nastavení → Grafika), ne ladicí
## parametr – proto tu není.
## Oprava výkonu po M8 (17. 10. 2026): velikosti kusů a stropy kusů za snímek pro práce přes `EcoClock.slice`
## (stavba mřížky luk, vodní bilance). Celkový časový rozpočet je `eco.slice_budget_us` (tune_svet.gd, Svět/Eko-takt).
## Optimalizace CPU (17. 10. 2026): LOD vozidel (Vozidla/LOD), LOD postav (Člověk/LOD postav), strop prací EcoClock.
extends RefCounted

const SKUPINA := "Létání/Hranice letu"
const LOUKY := "Příroda/Louky a podrost"
const VODA := "Příroda/Voda a půda"
const LOD_VEH := "Vozidla/LOD"
const LOD_LIDE := "Člověk/LOD postav"
const EKO := "Svět/Eko-takt"


static func register_all() -> void:
	DevTune.tune(World, "FLY_LIMIT_M", "world.fly_limit_m", SKUPINA, "Hranice – vodorovně za katastrem",
		200.0, 6000.0, 10.0, "Dron a letouny smí nejvýš tolik metrů za obdélník katastru (pak návrat / odpuzení).", "m")
	DevTune.tune(World, "FLY_WARN_M", "world.fly_warn_m", SKUPINA, "Hranice – pásmo varování a protivětru",
		0.0, 1500.0, 10.0, "Šířka pásma před hranicí, kde stroj tlačí „protivítr“ a HUD varuje.", "m")
	DevTune.tune(World, "FLY_PUSH_MS", "world.fly_push_ms", SKUPINA, "Hranice – rychlost odpuzení u hranice",
		0.0, 50.0, 0.5, "Rychlost odpuzujícího větru na samé hranici (lineárně od začátku pásma).", "m/s")
	DevTune.tune(World, "FLY_CEIL_AGL", "world.fly_ceil_agl", SKUPINA, "Strop – výška nad terénem",
		100.0, 4000.0, 10.0, "Nad touto výškou nad terénem stroj tlačí dolů a HUD varuje.", "m AGL")
	DevTune.tune(World, "FLY_CEIL_PUSH", "world.fly_ceil_push", SKUPINA, "Strop – rychlost stlačení dolů",
		0.0, 30.0, 0.1, "Základ rychlosti tlačení dolů nad stropem (+ 0,1 m/s na každý metr navíc, nejvýš rychlost odpuzení).", "m/s")
	# --- oprava výkonu po M8: kusy prací EcoClock (výchozí = kód, chování simulace stejné, jen rozložení do snímků)
	DevTune.tune(Meadows, "INIT_SEG", "meadows.init_seg", LOUKY, "Louky – stavba mřížky: buněk na kus",
		4, 710, 4, "Po každém kusu EcoClock kontroluje časový rozpočet snímku. Větší kus = rychlejší stavba, delší snímek. " +
		"Platí od příští stavby mřížky (nový start).", "buněk")
	DevTune.tune(Meadows, "STEP_CHUNK", "meadows.step_chunk", LOUKY, "Louky – denní krok: buněk na kus",
		8, 2000, 8, "Kus denního / hrubého kroku luk mezi kontrolami rozpočtu EcoClock (~5 µs na buňku). Platí od dalšího kroku.", "buněk")
	DevTune.tune(SoilWater, "INIT_PER_FRAME", "soil_water.init_per_frame", VODA, "Vodní bilance – stavba: kusů za snímek",
		1, 64, 1, "Strop kusů (po 16 buňkách, ~0,35 ms) stavby mřížky za snímek; víc nedovolí rozpočet EcoClock.", "kusů")
	DevTune.tune(SoilWater, "D8_PER_FRAME", "soil_water.d8_per_frame", VODA, "Vodní bilance – spádnice: kusů za snímek",
		1, 64, 1, "Strop kusů (po 40 buňkách) výpočtu spádnic D8 za snímek.", "kusů")
	DevTune.tune(SoilWater, "OUTLET_PER_FRAME", "soil_water.outlet_per_frame", VODA, "Vodní bilance – ústí do toků: kusů za snímek",
		1, 64, 1, "Strop kusů (po 80 buňkách) hledání toku, do kterého buňka ústí, za snímek.", "kusů")
	# --- optimalizace CPU (17. 10. 2026): LOD aut, vesničanů a animace postav; výchozí = kód
	DevTune.tune(Car, "KIN_LOD_R", "car_lod.kin_r", LOD_VEH, "AI auto – kinematika od vzdálenosti",
		20.0, 1000.0, 5.0, "Dál od hráče jede AI auto po trase bez fyziky kol (viditelně, plán rychlosti a překážky jako AI). " +
		"Nad simulační bublinou (320 m) = staré chování (kinematika jen za bublinou).", "m")
	DevTune.tune(Car, "KIN_LOD_HYST", "car_lod.kin_hyst", LOD_VEH, "AI auto – návrat do fyziky (× vzdálenost)",
		0.3, 1.0, 0.05, "Plná fyzika se zapne až pod vzdáleností kinematiky × tohle (hystereze proti přepínání).", "×")
	DevTune.tune(Car, "KIN_PLAN_DT", "car_lod.kin_plan_dt", LOD_VEH, "AI auto – kinematika: plán a překážky po",
		0.05, 1.0, 0.05, "Jak často kinematické auto přepočítá rychlost podle zatáček a hledá překážku v pruhu.", "s")
	DevTune.tune(Car, "KIN_ACCEL", "car_lod.kin_accel", LOD_VEH, "AI auto – kinematika: rozjezd",
		0.5, 6.0, 0.1, "Zrychlení kinematického auta (brzdí plánovaným zpomalením AI × 1,6).", "m/s²")
	DevTune.tune(Car, "REST_FREEZE_S", "car_lod.rest_freeze_s", LOD_VEH, "Stojící vozidlo – zamrazit po klidu",
		0.0, 30.0, 0.5, "Vozidlo bez řidiče v klidu tak dlouho zamrzne (kolize zůstává, kola a zvuky stojí). 0 = nikdy.", "s")
	DevTune.tune(Car, "REST_V", "car_lod.rest_v", LOD_VEH, "Stojící vozidlo – práh klidu",
		0.01, 0.5, 0.01, "Rychlost i otáčení pod tímto prahem = vozidlo stojí v klidu.", "m/s")
	DevTune.tune(Car, "REST_WAKE_M", "car_lod.rest_wake_m", LOD_VEH, "Stojící vozidlo – probudit, když přijede auto",
		4.0, 60.0, 1.0, "Zamrzlé vozidlo se probudí, když se k němu přiblíží vozidlo s řidičem (+ 0,8 s jeho jízdy).", "m")
	DevTune.tune(Villager, "LOD_NEAR_R", "villager_lod.near_r", LOD_LIDE, "Vesničan – plná frekvence do",
		5.0, 320.0, 5.0, "Blíž k hráči se vesničan počítá každý fyzikální krok (60 Hz).", "m")
	DevTune.tune(Villager, "LOD_MID_N", "villager_lod.mid_n", LOD_LIDE, "Vesničan – střední pásmo: každý N-tý krok",
		1, 8, 1, "Od plné frekvence do dosahu fyziky (160 m): krok jednou za N fyzikálních kroků (3 = 20 Hz).", "kroků")
	DevTune.tune(Villager, "LOD_FAR_N", "villager_lod.far_n", LOD_LIDE, "Vesničan – za dosahem fyziky: každý N-tý krok",
		1, 12, 1, "Kinematika po terénu (a střední pásmo za bublinou): krok jednou za N fyzikálních kroků.", "kroků")
	DevTune.tune(Villager, "LOD_BEHIND_N", "villager_lod.behind_n", LOD_LIDE, "Vesničan – za kamerou: aspoň každý N-tý krok",
		1, 12, 1, "Jen při jednom hráči: vesničan za kamerou (dál než polovina plné frekvence) se počítá nejvýš tak často.", "kroků")
	DevTune.tune(Humanoid, "LOD_FULL_R", "humanoid_lod.full_r", LOD_LIDE, "Animace postavy – každý snímek do",
		5.0, 200.0, 5.0, "Blíž ke kameře se animace postavy počítá každý snímek.", "m")
	DevTune.tune(Humanoid, "LOD_MID_R", "humanoid_lod.mid_r", LOD_LIDE, "Animace postavy – střední pásmo do",
		10.0, 400.0, 5.0, "Do této vzdálenosti od kamery každý N-tý snímek (střední), dál vzdálený N.", "m")
	DevTune.tune(Humanoid, "LOD_MID_N", "humanoid_lod.mid_n", LOD_LIDE, "Animace postavy – střední: každý N-tý snímek",
		1, 8, 1, "", "snímků")
	DevTune.tune(Humanoid, "LOD_FAR_N", "humanoid_lod.far_n", LOD_LIDE, "Animace postavy – daleko: každý N-tý snímek",
		1, 12, 1, "", "snímků")
	DevTune.tune(Humanoid, "LOD_BEHIND_N", "humanoid_lod.behind_n", LOD_LIDE, "Animace postavy – za kamerou: každý N-tý snímek",
		1, 20, 1, "Postava za kamerou (dál než plná frekvence) – mimo zorné pole stačí zřídka.", "snímků")
	DevTune.tune(Humanoid, "LOD_GAIT_R", "humanoid_lod.gait_r", LOD_LIDE, "Animace postavy – Gait do",
		5.0, 400.0, 5.0, "Dál od kamery jednoduchá animace chůze místo fázového cyklu Gait (bez vzorkování svahu).", "m")
	DevTune.tune(EcoClock, "JOB_BUDGET_US", "eco.job_budget_us", EKO, "Rozpočet prací (stavba mřížek) za snímek",
		100, 4000, 100, "Strop času za snímek jen pro práce EcoClock.slice (stavba luk, stanovišť, vodní bilance) uvnitř " +
		"celkového rozpočtu eko-taktu. Menší = plynulejší hra, stavba trvá déle.", "µs")
