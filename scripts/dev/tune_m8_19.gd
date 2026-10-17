## M8.19B Výkon, předvolby a uzavření M8: menu pro vývojáře (F3) – skupina **Létání/Hranice letu** (`World.FLY_*`:
## vodorovná hranice letu za katastrem, pásmo varování a protivětru, strop nad terénem). Výchozí hodnoty = kód
## (`static var` ve `world.gd`). `World.flight_bounds` čte proměnné přímo – registr se za snímek nečte.
## Detail přírody podle předvolby (`GameSettings.ECO_LEVELS`) je nastavení hráče (Esc → Nastavení → Grafika), ne ladicí
## parametr – proto tu není.
## Oprava výkonu po M8 (17. 10. 2026): velikosti kusů a stropy kusů za snímek pro práce přes `EcoClock.slice`
## (stavba mřížky luk, vodní bilance). Celkový časový rozpočet je `eco.slice_budget_us` (tune_svet.gd, Svět/Eko-takt).
## Optimalizace GPU a předvolby (17. 10. 2026): skupina **Svět/Vykreslování** – hranice LOD generovaných stromů, dosah
## vegetace, dosah stínů slunce a práh LOD meshů (násobky navíc k předvolbě; výchozí = kód, vzhled beze změny).
extends RefCounted

const SKUPINA := "Létání/Hranice letu"
const LOUKY := "Příroda/Louky a podrost"
const VODA := "Příroda/Voda a půda"
const VYKRES := "Svět/Vykreslování"
const GPU_IDS := ["render.tree_l0_end", "render.tree_l1_end", "render.veg_range_k", "render.shadow_dist_k",
	"render.mesh_lod_k"]


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
	_vykreslovani()


## Optimalizace GPU (17. 10. 2026): parametry vykreslování; změna se uplatní hned (`on_changed`).
static func _vykreslovani() -> void:
	DevTune.tune(TreeGen, "L0_END", "render.tree_l0_end", VYKRES, "Stromy – hranice LOD0 (plný model)",
		10.0, 165.0, 1.0, "Do této vzdálenosti se kreslí plný model generovaného stromu (× „lod0“ z detailu přírody " +
		"v předvolbě: Nízký 0,5, Střední 0,6, Vysoký 1, Ultra 1,3). Menší = levnější les zblízka.", "m")
	DevTune.tune(TreeGen, "L1_END", "render.tree_l1_end", VYKRES, "Stromy – hranice LOD1 → impostor",
		60.0, 400.0, 5.0, "Dál než tohle (× „lod1“ z předvolby: 0,75 / 0,8 / 1 / 1,15) je strom jen impostor (2 trojúhelníky). " +
		"Menší = méně buněk LOD1 kolem kamery a méně stínových draw callů.", "m")
	DevTune.tune(VegetationManager, "RANGE_K", "render.veg_range_k", VYKRES, "Vegetace – násobek dosahu",
		0.0, 3.0, 0.05, "Násobí dosah chunků trávy, kopřiv, keřů, obilí… navíc k volbě Vegetace v předvolbě (Střední 0,5).", "×")
	DevTune.tune(GameSettings, "SHADOW_DIST_K", "render.shadow_dist_k", VYKRES, "Stíny – násobek dosahu stínů slunce",
		0.2, 3.0, 0.05, "Násobí dosah stínů z předvolby (Střední 120 m, Vysoká 240 m). Kratší = méně objektů ve stínovém průchodu.", "×")
	DevTune.tune(GameSettings, "MESH_LOD_K", "render.mesh_lod_k", VYKRES, "LOD meshů – násobek prahu",
		0.0, 8.0, 0.1, "Násobí Viewport.mesh_lod_threshold z dohlednosti (Krátká 4, Střední 2, Daleká 1). Vyšší = dřív hrubší " +
		"LOD u importovaných modelů (.glb); meshe skládané v kódu LOD nemají.", "×")
	for id in GPU_IDS:
		if DevTune.differs_from_code(id):
			on_changed(id, DevTune.value(id))


## Změna v F3 (a při startu, když se hodnota z config.json / ladeni.cfg liší od kódu).
static func on_changed(id: String, _value: Variant) -> void:
	match id:
		"render.tree_l0_end", "render.tree_l1_end":
			if MapLoader.tree_gen != null:
				MapLoader.tree_gen.refresh_bands()
		"render.veg_range_k":
			VegetationManager._gen += 1
		"render.shadow_dist_k", "render.mesh_lod_k":
			GameSettings.reapply_live()
