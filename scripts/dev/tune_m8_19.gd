## M8.19B Výkon, předvolby a uzavření M8: menu pro vývojáře (F3) – skupina **Létání/Hranice letu** (`World.FLY_*`:
## vodorovná hranice letu za katastrem, pásmo varování a protivětru, strop nad terénem). Výchozí hodnoty = kód
## (`static var` ve `world.gd`). `World.flight_bounds` čte proměnné přímo – registr se za snímek nečte.
## Detail přírody podle předvolby (`GameSettings.ECO_LEVELS`) je nastavení hráče (Esc → Nastavení → Grafika), ne ladicí
## parametr – proto tu není.
## Oprava výkonu po M8 (17. 10. 2026): velikosti kusů a stropy kusů za snímek pro práce přes `EcoClock.slice`
## (stavba mřížky luk, vodní bilance). Celkový časový rozpočet je `eco.slice_budget_us` (tune_svet.gd, Svět/Eko-takt).
extends RefCounted

const SKUPINA := "Létání/Hranice letu"
const LOUKY := "Příroda/Louky a podrost"
const VODA := "Příroda/Voda a půda"


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
