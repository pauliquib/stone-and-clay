## M8.19B Výkon, předvolby a uzavření M8: menu pro vývojáře (F3) – skupina **Létání/Hranice letu** (`World.FLY_*`:
## vodorovná hranice letu za katastrem, pásmo varování a protivětru, strop nad terénem). Výchozí hodnoty = kód
## (`static var` ve `world.gd`). `World.flight_bounds` čte proměnné přímo – registr se za snímek nečte.
## Detail přírody podle předvolby (`GameSettings.ECO_LEVELS`) je nastavení hráče (Esc → Nastavení → Grafika), ne ladicí
## parametr – proto tu není.
extends RefCounted

const SKUPINA := "Létání/Hranice letu"


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
