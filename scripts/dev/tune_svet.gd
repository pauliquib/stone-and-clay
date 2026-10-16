## M8.D: menu pro vývojáře – kategorie **Svět** (gravitace, fyzikální kroky, rychlost simulace a herního času,
## eko-takt, přilnavost povrchů). Registr najde soubor sám (`DevTune.REGISTRARS_DIR`), volá `register_all()`.
## Výchozí hodnoty se berou z kódu (`DevTune.tune` čte současnou `static var`) – chování ve výchozím stavu beze změny.
extends RefCounted

const FYZ := "Svět/Fyzika"
const CAS := "Svět/Čas"
const EKO := "Svět/Eko-takt"
const POV := "Svět/Povrchy a přilnavost"


static func register_all() -> void:
	# --- fyzika světa (Engine / PhysicsServer – nastaví se jen při změně, výchozí stav nesahá na nic)
	DevTune.register("world.gravity", FYZ, "Gravitace světa (rekvizity, vozík, zvířata, předměty)",
		float(ProjectSettings.get_setting("physics/3d/default_gravity", 20.0)), 1.0, 40.0, 0.1,
		"Gravitace fyzikálního prostoru (RigidBody). Projekt má 20 m/s² kvůli pocitu z chůze; hráč má vlastní " +
		"(Člověk), vozidla jezdí s „Gravitací vozidel“ (gravity_scale se přepočítá).", "m/s²")
	DevTune.tune(Car, "VEH_G", "vehicle.gravity", FYZ, "Gravitace vozidel", 1.0, 30.0, 0.01,
		"Skutečné g pro auta, motorky a kola (pružení, odpory, náklon). Reálně 9,81.", "m/s²")
	DevTune.register("world.physics_hz", FYZ, "Fyzikální kroky za sekundu", int(Engine.physics_ticks_per_second),
		20, 240, 1, "Engine.physics_ticks_per_second – víc = přesnější vozidla a kolize, dražší CPU.", "Hz")
	DevTune.register("world.max_physics_steps", FYZ, "Nejvíc fyzikálních kroků za snímek",
		int(Engine.max_physics_steps_per_frame), 1, 32, 1,
		"Když snímek trvá dlouho, fyzika dožene nejvýš tolik kroků (pak se svět zpomalí místo zamrznutí).", "")
	DevTune.register("world.time_scale", FYZ, "Rychlost simulace (zpomalený / zrychlený svět)", 1.0, 0.05, 4.0, 0.05,
		"Engine.time_scale – zpomalí nebo zrychlí úplně všechno (fyziku, animace, čas). 1 = normál.", "×")
	# --- čas
	DevTune.tune(Clock, "TIME_SCALE", "world.clock_scale", CAS, "Rychlost herního času", 1.0, 600.0, 1.0,
		"Herních sekund za 1 s reálného času (30 = herní hodina za 2 minuty, den za 48 minut). Násobí se ještě " +
		"rychlostí času z F2.", "×")
	# --- eko-takt (M8.1)
	DevTune.tune(EcoClock, "SLICE_BUDGET_US", "eco.slice_budget_us", EKO, "Rozpočet eko-taktu za snímek",
		200, 20000, 100, "Kolik času smí EcoClock za snímek dohánět hodiny a krájet práce (slice).", "µs")
	DevTune.tune(EcoClock, "MAX_CATCHUP_DAYS", "eco.max_catchup_days", EKO, "Dohánění po hodinách nejvýš",
		1, 365, 1, "Delší skok času (vězení, spánek) se dožene jedním hrubým krokem místo hodinových signálů.", "dní")
	# --- povrchy a přilnavost (Weather – čte auto, chodec i kůň)
	DevTune.tune(Weather.SURF_GRIP, "asfalt", "surface.grip_asfalt", POV, "Přilnavost – suchý asfalt", 0.1, 2.0, 0.01,
		"Násobek tření pneu / podrážek / kopyt na suchém asfaltu.", "×")
	DevTune.tune(Weather.SURF_GRIP, "sterk", "surface.grip_sterk", POV, "Přilnavost – štěrk a polní cesta", 0.1, 2.0, 0.01,
		"Násobek tření na štěrku (vůči suchému asfaltu).", "×")
	DevTune.tune(Weather.SURF_GRIP, "teren", "surface.grip_teren", POV, "Přilnavost – terén (tráva, hlína)", 0.1, 2.0, 0.01,
		"Násobek tření mimo cesty.", "×")
	DevTune.tune(Weather, "GRIP_WET", "surface.grip_wet", POV, "Přilnavost – mokrá vozovka", 0.05, 1.0, 0.01,
		"Násobek při úplně mokrém povrchu (wetness = 1).", "×")
	DevTune.tune(Weather, "GRIP_SNOW", "surface.grip_snow", POV, "Přilnavost – uježděný sníh", 0.05, 1.0, 0.01,
		"Strop přilnavosti při plné sněhové pokrývce.", "×")
	DevTune.tune(Weather, "GRIP_ICE", "surface.grip_ice", POV, "Přilnavost – náledí", 0.02, 1.0, 0.01,
		"Strop přilnavosti na náledí (mokro pod nulou).", "×")
	DevTune.tune(Weather, "GRIP_MUD", "surface.grip_mud", POV, "Přilnavost – bláto", 0.05, 1.0, 0.01,
		"Strop přilnavosti rozmočené hlíny (terén, polní cesty).", "×")
	DevTune.tune(Weather, "ICE_WET", "surface.ice_wet", POV, "Náledí od vlhkosti povrchu", 0.0, 1.0, 0.01,
		"Kolik mokra (wetness) pod nulou stačí k náledí.", "")
	DevTune.tune(Weather, "MUD_STERK", "surface.mud_sterk", POV, "Bláto na štěrkové cestě (podíl z půdy)", 0.0, 1.0, 0.01,
		"Polní / štěrková cesta bere bláto z vlhkosti okolní půdy jen z části (M8.7).", "×")
	for id in ["world.gravity", "world.physics_hz", "world.max_physics_steps", "world.time_scale"]:
		if DevTune.differs_from_code(id):
			on_changed(id, DevTune.value(id))      # hodnota z config.json / ladeni.cfg


## Volitelná funkce registrace: registr ji sám připojí na `DevTune.changed` (statické funkce se nedají
## spolehlivě připojit zevnitř vlastního skriptu). Tady jen nastavení Engine / PhysicsServer.
static func on_changed(id: String, v: Variant) -> void:
	match id:
		"world.gravity":
			var tree := Engine.get_main_loop() as SceneTree
			if tree != null and tree.root != null and tree.root.world_3d != null:
				PhysicsServer3D.area_set_param(tree.root.world_3d.space, PhysicsServer3D.AREA_PARAM_GRAVITY, float(v))
		"world.physics_hz":
			Engine.physics_ticks_per_second = int(v)
		"world.max_physics_steps":
			Engine.max_physics_steps_per_frame = int(v)
		"world.time_scale":
			Engine.time_scale = float(v)
