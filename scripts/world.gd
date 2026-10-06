## Svět Dukelčic – simulace, která v multiplayeru poběží na serveru (hostiteli):
## terén a mapa (kolize), čas, hráči (`players`: id → Player), jejich úkoly (`quests`: id → Quests),
## vesničané, psi, místa a jejich obsluha, doprava, policie, sběratelské předměty, fyzikální věci,
## ekonomika (nákupy, pokuty, odměny) a pravidla (nehody, zadržení, okno, nemocnice, spánek),
## potoky a rybníky (Water), rádio doma a rušení sousedů (Radio),
## kalendář a počasí (Clock, Weather), fauna (Fauna: zvěř, ptáci, hmyz, koně hráčů), pověst hráčů
## (`reputations`: id → Reputation), rozhovory (player_say → Dialog), noclehy (SleepSpot) a uložené pozice (SaveGame).
##
## Nic tu nečte klávesnici ani nekreslí HUD. Hráčům se posílají jen zprávy:
##   notify(id, metoda_hud, argumenty)  → HUD hráče (show_message, popup, police_banner, quest_*…)
##   play_sfx(id, zvuk)                 → zvuk jen pro daného hráče
##   signál `sound(pos, …)`             → zvuk ve světě (uslyší ho klienti v dosahu)
##   emit_game_event(id, druh, data)    → úkoly hráče + prezentace u jeho klienta
## Lokální klient se registruje přes register_client(); v MP (úkol 03) se tyto cesty nahradí RPC.
## Akce hráčů (nastoupit, koupit, vyspat se…) jsou metody s id hráče – klient je jen volá.
class_name World
extends Node3D

signal loading(text: String)
signal sound(pos: Vector3, name: String, pitch: float, vol: float, max_dist: float)

const N_VILLAGERS := 28
const N_DOGS := 7
## Víkend (so, ne) ve dne: o tolik víc vesničanů venku (podíl z N_VILLAGERS) – přibývají a ubývají za běhu, mimo zrak hráče
const WEEKEND_CROWD := 0.3
const WEEKEND_HOURS := [9.0, 18.0]
const CROWD_CHECK_S := 3.0
## Sezónní předměty: od–do = den v roce (od 1. dne včetně do „do“ výhradně, přes Nový rok když od > do),
## regrow = po kolika dnech od sběru znovu vyroste (jen v sezóně). Hřiby navíc rostou hlavně po dešti:
## hřib se objeví, když Weather.rain_recent + HRIB_DRY >= jeho pevný práh 0..1.
const SEASON_ITEMS := {
	"hrib": {"from": 182, "to": 305, "regrow": 3},       # červenec–říjen
	"jablko": {"from": 213, "to": 305, "regrow": 5},     # srpen–říjen
	"sipek": {"from": 305, "to": 60, "regrow": 7},       # listopad–únor
}
const HRIB_DRY := 0.25
## Srážka auta se zvěří: poškození auta v % = HIT_DAMAGE_K × hmotnost (kg) × rychlost² (m/s)² – zajíc ~2 %,
## srnec při 70 km/h ~15 %, divočák při 50 km/h ~28 %. Kůň (550 kg) je nižší a pružnější → násobek HIT_HORSE_K.
## Jolt (2024): přesnější kolize → práh poškození ~+15 % v rychlosti → K = 0,0022 / 1,15² ≈ 0,00166.
const HIT_DAMAGE_K := 0.00166
const HIT_HORSE_K := 0.35
## Zvíře těžší než HIT_INJURY_MASS zraní řidiče při rychlosti nad HIT_INJURY_SPEED (m/s ≈ 47 km/h).
const HIT_INJURY_MASS := 40.0
const HIT_INJURY_SPEED := 13.0
const HIT_INJURY_K := 1.6
const SEASON_CHECK_S := 4.0
# M6.2 letové hranice (rozhodnutí uživatele): létající prostředky (dron, M6.3+ letouny) smí
# max. FLY_LIMIT_M za obdélník katastru – v pásmu FLY_WARN_M před ní měkké odpuzení (protivítr)
# + varování; strop FLY_CEIL_AGL nad terénem. Chodec a auto drží dál Terrain._add_bounds.
const FLY_LIMIT_M := 2000.0      # vodorovná hranice letu za hranicí katastru (m)
const FLY_WARN_M := 400.0        # šířka pásma varování / protivětru před hranicí (m)
const FLY_PUSH_MS := 18.0        # max. rychlost odpuzujícího „větru“ u hranice (m/s)
const FLY_CEIL_AGL := 1500.0     # strop letu nad terénem (m AGL)
const FLY_CEIL_PUSH := 6.0       # jak rychle stroj tlačí dolů nad stropem (m/s)

var args := {}
var meta: Dictionary
var obce: Array = []             # okolní obce z data/obce.json (id, name, center, radius, boundary, roads…)
var _obec_bounds := {}           # id obce → Rect2 hranice katastru – počítá obec_bounds() jednou (mapa, obec_at)
var terrain: Terrain
var water: Water                 # potoky, řeka, rybníky (OSM / DIBAVOD)
var radio: Radio                 # rádio doma (u vchodu domova, uvnitř na komodě) – hudba a sousedi
var interiors := {}              # id → Interior (M1.4): oddělené prostory pod mapou, viz enter_interior; M1.8: jen postavené
var interior_streamer: InteriorStreamer   # M1.8: stavba interiérů zblízka (nejvýš 3), generované interiéry všech budov
var _exit_cache := {}            # id interiéru → [poloha před dveřmi, yaw] (počítá se jednou)
var _radio_home := {}            # původní {pos, yaw} rádia venku (když je hráč uvnitř, stojí v interiéru)
var clock: Clock
var weather: Weather
var fauna: Fauna
var graph: RoadGraph
var traffic: Traffic
var police: Police
var items_root: Node3D
var bots_root: Node3D
var places := {}
var npcs := {}
var item_totals := {}            # druh předmětu → počet ve světě
var players := {}                # id → Player
var quests := {}                 # id → Quests (úkoly každého hráče zvlášť)
var reputations := {}            # id → Reputation (pověst a přestupky každého hráče)
var skills := {}                 # id → Skills (dovednosti a XP každého hráče, M0.3)
var talk_recent := {}            # id → {druh herní události → herní minuty}: nedávné události pro rozhovor (DialogData.RECENT_MAP)
var law := {}                    # id → Law.LawRecord (rejstřík přestupků a body, M0.5)
var jobs := {}                   # id → Jobs (zaměstnání, směny, docházka, výplata – M3.1, data/prace.json)
var favors: Favors               # prosby vesničanů a dobré skutky (M4.5), stav per hráč
var debts: Debts                 # dluhy a pokuty (M4.2): bloková složenka, příkaz poštou, upomínka, exekuce; stav per hráč
var action_runner: ActionRunner  # výběr cíle a průběh kontextových akcí (M0.4)
var sleep_spots: Array[SleepSpot] = []
var clients := {}                # id → LocalClient (jen hráči na tomto počítači)
var ready_done := false
## Simulační bublina kolem nejbližšího hráče (m) – za její hranicí přejdou vesničané, psi, NPC
## a AI auta do levného režimu (kinematika ~2 Hz, schovaný vizuál) nebo zamraznou. Nastavuje
## GameSettings dle volby „Aktivita světa“ (GameSettings.SIMS: 250–900 m).
var sim_radius := 320.0
var _blackout := {}              # id → true: hráč právě „nevidí“ (okno, spánek, záchytka)
var _cheat_permits := {}         # id → {druh oprávnění: true} – jen ladicí cheat (F2 → Hráč), dokud nejsou doklady (M4.6)
var _auto_start := {}            # id → Vector3 místo nástupu do auta (výcvikové jízdy autoškoly, M4.1)
# M6.1 drony: `drones[pid]` = aktivní dron ve světě (letí / leží / visí ve stromě); `drone_states[pid][model]`
# = trvalý stav flotily (baterie a poškození se drží i v inventáři). `permits` = registry oprávnění
# (registrace provozovatele ÚVL, osvědčení A1/A3). Akce z klienta přes `player_action`
# ("drone_launch:<model>", "car_enter" = přistát/návrat, "drone_photo" = fotka), HUD telemetrie z `Drone.status()`.
var drones := {}                # pid → Drone (uzel ve světě, vč. zaparkovaného)
var drone_states := {}          # pid → {model: {"bat": sekundy letu, "dmg": 0..100}}
var aircrafts := {}             # M6.3: pid → [Aircraft] – letouny hráče ve světě (jen na katastru)
var thermals: Thermals          # M6.3: stoupavé bubliny (pole/sídla, poledne, léto) + bouřkové proudy
var permits: Permits            # registry oprávnění (Permits.KINDS) – ÚVL i budoucí doklady (M4.6)
var _item_nodes := {}            # pořadí předmětu v map.json → Item (dokud ho nikdo nesebral)
var _collected := {}             # pořadí předmětu → true: už sebraný (ukládá se)
var _collected_jd := {}          # pořadí předmětu → juliánský den sběru (znovuvyrůstání sezónních předmětů)
var surface: SurfaceMap          # maska povrchu terénu (data/surface.bin) – procedurální materiály, minimapa
var surroundings: Surroundings   # M6.2: levná krajina za katastrem (bez kolizí, bez dat fallback prstenec)
var villages: Villages           # vizuální zástavba 5 okolních vesnic (data/obce.json; jen pohled z dálky)
var building_details: BuildingDetails   # okna, dveře, vrata a komíny budov (data/buildings.json; null bez dat)
var estate: Estate               # registr nemovitostí (M1.7): čísla popisná, cedulky, domov = vlastnictví / nájem bytu
var fields: Fields               # pole a louky (data/landuse.bin) – barvy polí kreslí terén podle kalendáře
var vegetation: VegetationManager   # Fáze 9: trsy, kopřivy, keře, obilné řádky, plevel (data/vegetation.bin)
var village_events: VillageEvents   # svátky a události v obci (výzdoba, průvod, oheň, ohňostroj)
var hunter: Hunter               # myslivec, krmelce, posed, sběr uhynulé zvěře, včelař
var paddock: Paddock             # výběh pro koně u usedlosti (Estate.lot_id; ohrada, žlab, napáječka)
var bazaar: Bazaar               # bazar vozidel u silnice (M1.6): nabídka na týden, koupě, výkup
var airfield: Airfield           # M6.5: polní letiště – trávníková dráha, větrný rukáv, hangár triku
var trees: TreeManager           # stromy za běhu (M2.1): index instancí, pokácené stromy, pařezy
var forestry: Forestry           # kácení a zpracování dřeva (M2.1): pád stromu, kmeny, špalky, zákon
var unreported := {}             # M4.4: id hráče → [{...}] činy, které nikdo neviděl (sdílený registr, viz `add_unreported`)
var witness_sources: Array[Callable] = []   # M4.4/M4.6: další zdroje svědků (hajný, stráže) – `add_witness_source`
var fire_mgr: FireManager        # oheň a topení (M2.2): ohniště, opékání, zákon u lesa, požár trávy, kamna doma
var garden: Garden             # zahrada u domu a pronajaté pole (M2.4): záhony, růst podle dnů, sklizeň
var fences: FenceManager       # ploty a ohrady (Fáze 7): obvody výběhu, zahrady a pole + hráčské úseky
var farm: Farm                   # hospodářská zvířata u usedlosti (M2.6): výběh, kurník, chlívek, přístřešek
var fishing: Fishing             # rybaření (M2.7): nahození, záběr, zdolávání, úlovek, zákon (háčky)
var weapons: Weapons             # zbraně a střelba (M2.8): luk, kuše, puška, balistika, střelnice u chaty, zákon o zbraních
var cargo: Cargo                # náklad a přeprava (M2.10): rameno, kufr, nosič, ruční vozík (G, E u vozíku)
var statek: Statek               # M3.2: Statek Na Kopci – pracoviště pomocníka na farmě (místo „statek“, výběh, stodola, záhony)
var udrzba: ObecniUdrzba         # M3.2: obecní údržba – zóny trávy, listí a sněhu, lavička, odpadky (i dobrovolné odklízení sněhu)
var vycep: Vycep                 # M3.2: čepování v hospodě (minihra výčepního)
var les: LesniPrace              # M3.3: lesní dělník – paseka u chaty, vyznačené stromy, hromada dřeva
var obchod: ProdavacPrace        # M3.3: prodavač/ka v Potravinách – pokladna, bedny do regálu, pečivo
var zahradnik: ZahradnikPrace    # M3.3: zahradník u sousedů – zakázky na zahradách (od dědy)
var palenice: PalenicePrace      # M3.3: pomocník v pálenici – kvas, topení pod kotlem (minihra), lahve
var computer: Computer           # M3.4: počítač doma – banka, e-shop s balíky, bazar, práce, pošta, web obce, eTesty; bankomaty
var mail := {}                   # M3.4: id → [{t, from, subject, body, read}] – e-maily (World.send_mail)
var orders := {}                 # M3.4: id → [{no, items, total, cod, jd, state}] – objednávky z e-shopu (den doručení)
var hunting: Hunting             # lov zvěře (M2.9): zásah, postřelení, krvavá stopa, úlovek (Carcass), vyvrhnutí, pytláctví, překupník
var fires: Array = []            # ohniště (Fire) – hořící, žhavé i vyhaslé kamenné kruhy
var grass_fires: Array = []      # probíhající požáry trávy (GrassFire)
var tracks: Tracks               # stopy ve sněhu (hráč, kůň, zvěř)
var nature_log: NatureLog        # deník pozorování přírody (první setkání s každým druhem)
var _bot_nodes: Array = []       # uzly grafu, kde se rozmisťují vesničané
var _extra_villagers: Array = [] # víkendoví vesničané navíc
var _season_t := 2.0
var _crowd_t := 5.0


## Čas, kalendář a počasí – musí existovat dřív, než klient postaví oblohu.
## --time=hh (hodina), --date=RRRR-MM-DD (datum 1. dne, výchozí dnešek), --weather=druh (Weather.TYPES, snih)
func init_clock() -> void:
	clock = Clock.new()
	clock.name = "Cas"
	add_child(clock)
	if args.has("time"):
		clock.minutes = float(args["time"]) * 60.0
	if args.has("date"):
		var ymd: PackedStringArray = String(args["date"]).split("-")
		if ymd.size() == 3:
			clock.set_start_date(int(ymd[0]), int(ymd[1]), int(ymd[2]))
	weather = Weather.new()
	weather.name = "Pocasi"
	add_child(weather)
	weather.setup(clock, 78.37, String(args.get("weather", "")))


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Načte a postaví svět (bez hráčů). Průběh hlásí signálem `loading`.
func build() -> void:
	await _frames(2)
	meta = JSON.parse_string(FileAccess.get_file_as_string("res://data/map.json"))
	weather.north_deg = float(meta.get("north_angle_deg", 78.37))
	obce = _load_obce()            # okolní obce pro mapu (HUD) a „nacházíš se v X"; 3D zástavbu staví Villages

	loading.emit("Terén (DMR 5G, 2 m) a povrch…")
	await _frames(1)
	terrain = Terrain.new()
	terrain.name = "Teren"
	add_child(terrain)
	terrain.build(meta)
	surface = SurfaceMap.new()
	if surface.load_data():
		terrain.set_surface(surface.make_texture(), surface.rect())
	fields = Fields.new()
	if fields.load_data():
		terrain.set_landuse(fields.make_texture(), fields.rect())
		terrain.set_field_lut(ImageTexture.create_from_image(fields.lut_image(clock.day_of_year(), clock.year())))
	surroundings = Surroundings.new()        # M6.2: krajina za katastrem (jen vzhled, bez kolizí)
	surroundings.name = "Okoli"
	add_child(surroundings)
	surroundings.setup(terrain)
	villages = Villages.new()                # zástavba okolních obcí (jen vzhled; potřebuje mřížku okolí)
	villages.name = "Vesnice"
	add_child(villages)
	villages.setup(surroundings, terrain)
	if not villages.stats.is_empty():        # ladění: kolik budov se v které obci postavilo
		var _vs := []
		for k in villages.stats:
			_vs.append(("%s skipped (detailní mapa)" % k) if villages.stats[k].get("skipped", false)
				else "%s %d budov" % [k, int(villages.stats[k]["buildings"])])
		print("Okolní obce (villages.stats): %s" % ", ".join(_vs))

	loading.emit("Budovy a cesty…")
	await _frames(1)
	var map_root := Node3D.new()
	map_root.name = "Mapa"
	add_child(map_root)
	var m_wall := MapLoader.tinted_material("beige_wall_001", 3.0, 1.0, 0.78 / 0.273, true, Color.WHITE, 0.9)
	var m_roof := MapLoader.tinted_material("clay_roof_tiles_02", 2.5, 1.0, 0.92 / 0.129, true, Color.WHITE, 0.8)
	var m_asph := MapLoader.tinted_material("asphalt_02", 3.0, 0.0, 1.0, false, Color.WHITE, 0.5)
	var m_grav := MapLoader.tinted_material("gravel_road", 2.0, 0.85, 0.92 / 0.115, false,
		Color(0.55, 0.52, 0.47).linear_to_srgb(), 0.7)
	m_asph.set_shader_parameter("snow_amount", 0.35)   # silnice se prohrnují
	m_grav.set_shader_parameter("snow_amount", 0.8)
	m_asph.set_shader_parameter("wet_boost", 1.6)      # Fáze 9: mokrý asfalt znatelně lesklejší (§12.3)
	m_grav.set_shader_parameter("wet_boost", 1.25)
	# zdi/střechy mají konečný dohled – dosah dost velký, aby domy byly vidět i při Dohlednosti
	# „Krátká“ (násobič 0.6 → reálně ~960/1020 m); dláždice se mimo dosah skipují po chunkách.
	# Dohled se měří od středu dlaždice 256 m (MapLoader.load_chunks posouvá uzel do středu AABB –
	# prolínání FADE_SELF by jinak počítalo od spawnu a za ~1,3 km od domu by mapa zmizela, vlna 0b)
	MapLoader.add_chunks(map_root, "Budovy_steny", MapLoader.load_chunks("res://data/walls.bin", m_wall), true, 1600.0, "budova")
	MapLoader.add_chunks(map_root, "Budovy_strechy", MapLoader.load_chunks("res://data/roofs.bin", m_roof), true, 1700.0, "budova")
	MapLoader.add_chunks(map_root, "Silnice", MapLoader.load_chunks("res://data/asphalt.bin", m_asph, terrain, 0.1), true, 1800.0, "asfalt")
	MapLoader.add_chunks(map_root, "Cesty", MapLoader.load_chunks("res://data/gravel.bin", m_grav, terrain, 0.09), true, 1400.0, "sterk")

	loading.emit("Potoky a rybníky…")
	await _frames(1)
	water = Water.new()
	water.name = "Voda"
	water.load_data()
	add_child(water)
	water.build(self, terrain)

	loading.emit("Stromy (51 736)…")
	await _frames(1)
	trees = TreeManager.new()
	add_child(trees)
	trees.setup(self, terrain)
	MapLoader.build_trees(map_root, water.drop_trees, terrain, trees)

	loading.emit("Vegetace…")
	await _frames(1)
	vegetation = VegetationManager.new()   # Fáze 9: detailní vegetace (trsy, keře, obilí; data/vegetation.bin)
	add_child(vegetation)
	vegetation.setup(self)

	loading.emit("Hráč, vesničané, předměty, auta…")
	await _frames(1)
	_spawn_items()
	_spawn_bots()
	_spawn_props()
	_spawn_places()
	if BuildingDetails.available():
		loading.emit("Okna, dveře a komíny…")
		await _frames(1)
		building_details = BuildingDetails.new()
		building_details.name = "Fasady"
		add_child(building_details)
		await building_details.setup(self)
	_spawn_interiors()
	estate = Estate.new()          # M1.7: po místech, fasádách a interiérech (čte dveře budov a místo „domov“)
	add_child(estate)
	estate.setup(self)
	interior_streamer.add_estates(estate)     # M1.8: generované interiéry budov s dveřmi (stavějí se až zblízka)
	if npcs.has("deda") and (npcs["deda"] as Npc).persona:
		(npcs["deda"] as Npc).persona.profile["job"] = "důchodce, soused z %s" % estate.deda_label()
	traffic = Traffic.new()
	traffic.name = "Doprava"
	add_child(traffic)
	traffic.setup(graph, terrain, self)
	police = Police.new()
	police.name = "Policie"
	add_child(police)
	police.setup(traffic, graph, terrain, self, clock)
	police.busted.connect(_on_busted)
	police.escaped.connect(func(pid: int): emit_game_event(pid, "escaped_police", {}))

	loading.emit("Zvěř, ptáci a hmyz…")
	await _frames(1)
	fauna = Fauna.new()
	fauna.name = "Fauna"
	add_child(fauna)
	fauna.setup(self)
	_set_forest_fallback()
	thermals = Thermals.new()          # M6.3: termika potřebuje terén, vodu, les i počasí
	thermals.name = "Termika"
	add_child(thermals)
	thermals.setup(self)
	village_events = VillageEvents.new()
	village_events.name = "Udalosti"
	add_child(village_events)
	village_events.setup(self)
	tracks = Tracks.new()
	tracks.name = "Stopy"
	add_child(tracks)
	tracks.setup(self)
	hunter = Hunter.new()
	hunter.name = "Myslivost"
	add_child(hunter)
	hunter.setup(self)
	bazaar = Bazaar.new()
	bazaar.name = "Bazar"
	add_child(bazaar)
	bazaar.setup(self)
	airfield = Airfield.new()          # M6.5: polní dráha, rukáv, hangár (jen terén, žádná AI)
	airfield.name = "Letiste"
	add_child(airfield)
	airfield.setup(self)
	nature_log = NatureLog.new()
	nature_log.name = "Pozorovani"
	add_child(nature_log)
	nature_log.setup(self)
	forestry = Forestry.new()
	add_child(forestry)
	forestry.setup(self)
	fire_mgr = FireManager.new()
	add_child(fire_mgr)
	fire_mgr.setup(self)
	apply_home(1)                  # M1.7: domov místního hráče (nová hra = nájemní byt) – před default_spawn a add_player


## Spustí provoz (zaparkovaná a AI auta, hlídka) – až jsou ve světě hráči (auta se rozmístí kolem nich).
func start() -> void:
	var avoid := []
	for k in places:
		avoid.append(Vector2(places[k].park.x, places[k].park.z))
	traffic.spawn_parked(avoid)
	traffic.spawn_ai()
	police.spawn_patrol()
	_spawn_sleep_spots()
	for c in traffic.get_children():
		if c is Car:
			_connect_car(c)
	ready_done = true


# ------------------------------------------------------------------ hráči

## Výchozí místo pro nového hráče: před vchodem domova (M1.7: bytový dům), bez registru před domem z map.json.
## Vrací [pozice, yaw].
func default_spawn() -> Array:
	if estate != null and places.has("domov"):
		var ex := interior_exit("domov")
		return [(ex[0] as Vector3) + Vector3(0, 0.2, 0), float(ex[1])]
	var sp: Dictionary = meta["spawn"]
	var x := float(sp["x"])
	var z := float(sp["z"])
	var d := Vector2(float(sp["look_x"]) - x, float(sp["look_z"]) - z)
	return [Vector3(x, terrain.height_at(x, z) + 0.2, z), atan2(-d.x, -d.y)]


## Přidá hráče do světa: postava, jeho úkoly, jeho auto u domu hráče, napojení událostí.
func add_player(id: int, pos: Vector3, yaw: float) -> Player:
	var p := Player.new()
	p.id = id
	p.name = "Hrac" if id == 1 else "Hrac_%d" % id
	p.weather = weather
	add_child(p)
	p.teleport(pos, yaw)
	players[id] = p
	p.game_event.connect(func(kind: String, data: Dictionary): emit_game_event(id, kind, data))
	p.body.passed_out.connect(_on_passed_out.bind(id))
	p.body.knocked_out.connect(_on_knocked_out.bind(id))
	var q := Quests.new()
	q.name = "Ukoly" if id == 1 else "Ukoly_%d" % id
	add_child(q)
	q.setup(self, p)
	quests[id] = q
	var rep := Reputation.new()
	rep.name = "Povest" if id == 1 else "Povest_%d" % id
	add_child(rep)
	rep.setup(self, p)
	reputations[id] = rep
	if action_runner == null:
		action_runner = ActionRunner.new(self)
		add_child(action_runner)
	var sk := Skills.new()
	sk.name = "Dovednosti" if id == 1 else "Dovednosti_%d" % id
	add_child(sk)
	sk.setup(self, p)
	skills[id] = sk
	law[id] = Law.LawRecord.new()
	var jb := Jobs.new()
	jb.name = "Prace" if id == 1 else "Prace_%d" % id
	add_child(jb)
	jb.setup(self, p)
	jobs[id] = jb
	if estate:
		estate.ensure_home(id)     # nový hráč: nájemní byt (staré uložení to při načtení přepíše – SaveGame)
	var home: Place = places["domov"]
	var side := Vector3.ZERO if id == 1 else Basis(Vector3.UP, home.park_yaw) * Vector3(4.0 * (id - 1), 0, 0)
	var c := traffic.spawn_player_car(id, Vector2(home.park.x + side.x, home.park.z + side.z), home.park_yaw)
	var bikes := traffic.spawn_player_bikes(id, Vector2(home.park.x + side.x, home.park.z + side.z), home.park_yaw)
	if ready_done:
		_connect_car(c)
		for b in bikes:
			_connect_car(b)
	# kůň hráče se pase kousek od domu
	if paddock == null:
		paddock = Paddock.new()
		paddock.name = "Vybeh"
		add_child(paddock)
		paddock.setup(self)
	var hs: Array = paddock.horse_spot(id) if paddock.ok else _horse_spot(home_grounds()["door"], id)
	fauna.spawn_horse(id, hs[0], hs[1])
	if garden == null:            # zahrada za domem (M2.4) – až po výběhu, aby se nepřekrývaly
		garden = Garden.new()
		add_child(garden)
		garden.setup(self)
	if farm == null:              # hospodářství (M2.6) – až po výběhu koně a zahradě, aby se nepřekrývaly
		farm = Farm.new()
		add_child(farm)
		farm.setup(self)
	if fishing == null:           # rybaření (M2.7) – jen logika, žádná plocha ve světě
		fishing = Fishing.new()
		add_child(fishing)
		fishing.setup(self)
	if weapons == null:           # zbraně a střelba (M2.8) – logika; střelnici postaví Weapons po načtení světa
		weapons = Weapons.new()
		add_child(weapons)
		weapons.setup(self)
	if hunting == null:           # lov zvěře (M2.9) – logika; těla a krvavé kapky jsou děti tohoto uzlu
		hunting = Hunting.new()
		add_child(hunting)
		hunting.setup(self)
	if cargo == null:             # náklad a ruční vozík (M2.10) – po lovu (nese zvěř) a lesnictví (špalky)
		cargo = Cargo.new()
		add_child(cargo)
		cargo.setup(self)
	if statek == null:            # M3.2 práce: statek až po hospodářství hráče (výběhy se nepřekrývají), údržba a výčep
		statek = Statek.new()
		add_child(statek)
		statek.setup_statek(self)
	if udrzba == null:
		udrzba = ObecniUdrzba.new()
		add_child(udrzba)
		udrzba.setup(self)
	if vycep == null:
		vycep = Vycep.new()
		add_child(vycep)
		vycep.setup(self)
	if les == null:               # M3.3 další práce: les, Potraviny, zahradník (zakázky)
		les = LesniPrace.new()
		add_child(les)
		les.setup(self)
	if obchod == null:
		obchod = ProdavacPrace.new()
		add_child(obchod)
		obchod.setup(self)
	if zahradnik == null:
		zahradnik = ZahradnikPrace.new()
		add_child(zahradnik)
		zahradnik.setup(self)
	if palenice == null:
		palenice = PalenicePrace.new()
		add_child(palenice)
		palenice.setup(self)
	if computer == null:          # M3.4: počítač doma (banka, e-shop, pošta…) a bankomaty u Potravin a úřadu
		computer = Computer.new()
		add_child(computer)
		computer.setup(self)
	computer.add_player(id)
	if permits == null:           # M6.1: registry oprávnění (ÚVL registrace, A1/A3…; doklady M4.6 použijí stejně)
		permits = Permits.new()
		add_child(permits)
		permits.setup(self)
	permits.add_player(id)
	if favors == null:            # M4.5: prosby vesničanů (jedna instance, stav per hráč)
		favors = Favors.new()
		favors.setup(self)
	if debts == null:             # M4.2: dluhy (jedna instance, stav per hráč; denní krok v _process_impl)
		debts = Debts.new()
		add_child(debts)
		debts.setup(self)
	if fences == null:            # ploty a ohrady (Fáze 7) – až PO výběhu, zahradě i statku: sondy `_find_spot`
		fences = FenceManager.new()   # hledají jejich místa kolizním kvádrem a na hotový plot by narazily
		add_child(fences)
		fences.setup(self)
	drone_states[id] = {}
	aircrafts[id] = []                 # M6.3: letouny hráče (naplní načtení save / F2)
	return p


## Volné rovné místo pro koně u domova. Vrací [poloha, natočení] – kůň stojí hlavou od domu.
func _horse_spot(door: Vector3, id: int) -> Array:
	var sp := _ground_spot(door, home_grounds()["face"], 122 + id, Vector3(1.2, 1.4, 2.8), 6.0, 5.0)
	return sp if not sp.is_empty() else [door + Vector3(8, 0, 0), 0.0]


## Volné rovné místo na terénu kolem `around` (od `r0` m dál): ne na silnici (`road_gap` m od osy), ne v domě
## ani pod střechou, ne u auta; kvádr `size` (šířka, výška, délka) se nesmí ničeho dotknout.
## Vrací [poloha, natočení od bodu `face_from`] nebo [], když nic nenajde.
## Pozor: dotaz na tvar s konkávní kolizí budov nepozná bod uvnitř domu, proto se kontroluje paprskem
## shora (musí nejdřív trefit terén).
func _ground_spot(around: Vector3, face_from: Vector2, seed_: int, size: Vector3, r0: float, road_gap: float) -> Array:
	var space := get_world_3d().direct_space_state
	var bx := BoxShape3D.new()
	bx.size = size
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = bx
	q.collision_mask = 1 | 8 | 16
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	for i in 80:
		var a := rng.randf() * TAU
		var r := r0 + i * 0.3
		var x := around.x + cos(a) * r
		var z := around.z + sin(a) * r
		var y := terrain.height_at(x, z)
		if absf(terrain.height_at(x + 1.5, z) - y) > 0.5 or absf(terrain.height_at(x, z + 1.5) - y) > 0.5:
			continue
		if dist_to_roads(Vector2(x, z)) < road_gap:
			continue
		var away := Vector2(x, z) - face_from
		var yaw := atan2(away.x, away.y)
		var fwd := Vector3(sin(yaw), 0, cos(yaw))
		var side := fwd.cross(Vector3.UP)
		var ok := true
		for o in [Vector3.ZERO, fwd * size.z * 0.5, -fwd * size.z * 0.5, side * size.x * 0.67, -side * size.x * 0.67]:
			var pp: Vector3 = Vector3(x, y, z) + o
			var ray := PhysicsRayQueryParameters3D.create(pp + Vector3(0, 40, 0), pp - Vector3(0, 3, 0), 1)
			var hit := space.intersect_ray(ray)
			if hit.is_empty() or (hit["collider"] as Node).get_meta("surface", "") != "teren":
				ok = false
				break
		if not ok:
			continue
		q.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(x, y + size.y * 0.5 + 0.3, z))
		if space.intersect_shape(q, 1).is_empty():
			return [Vector3(x, y, z), yaw]
	return []


## Odebere hráče (odpojení v MP). Jeho auto zůstane stát.
func remove_player(id: int) -> void:
	var p: Player = players.get(id)
	if p == null:
		return
	if p.car:
		p.exit_car()
	if p.horse:
		p.dismount_horse()
	if p.aircraft:
		p.exit_aircraft()              # M6.3: letoun zůstane zaparkovaný ve světě
	if action_runner:
		action_runner.cancel(id)
	players.erase(id)
	clients.erase(id)
	if quests.has(id):
		quests[id].queue_free()
		quests.erase(id)
	if reputations.has(id):
		reputations[id].queue_free()
		reputations.erase(id)
	if skills.has(id):
		skills[id].queue_free()
		skills.erase(id)
	law.erase(id)
	if jobs.has(id):
		jobs[id]._clear_targets()
		jobs[id].queue_free()
		jobs.erase(id)
	drone_release_all(id)         # M6.1: dron i jeho stav zůstanou (inventář hráče zaniká s ním)
	drone_states.erase(id)
	p.queue_free()


func register_client(id: int, client: Node) -> void:
	clients[id] = client


func quests_of(id: int) -> Quests:
	return quests.get(id)


## Nejbližší hráč k bodu (nebo null, když ve světě nikdo není).
func nearest_player(pos: Vector3) -> Player:
	var best: Player = null
	var bd := INF
	for p in players.values():
		var d: float = player_world_pos(p).distance_squared_to(pos)
		if d < bd:
			bd = d
			best = p
	return best


func nearest_player_dist(pos: Vector3) -> float:
	var p := nearest_player(pos)
	return player_world_pos(p).distance_to(pos) if p else INF


## Poloha hráče „ve světě“ pro AI (zvěř, doprava, policie, počasí): uvnitř budovy (interiér je pod mapou)
## místo pozice v interiéru vrací vnější dveře domu, ať se okolí chová, jako by hráč stál u dveří.
func player_world_pos(p: Player) -> Vector3:
	if p.inside != "" and interiors.has(p.inside):
		return interior_exit(p.inside)[0]
	return p.global_position


## Bod, kolem kterého se rozmisťují auta / hlídka: i-tý hráč (cyklicky), bez hráčů výchozí spawn.
func player_anchor(i: int) -> Vector3:
	if players.is_empty():
		var sp: Dictionary = meta["spawn"]
		return Vector3(float(sp["x"]), 0, float(sp["z"]))
	var ids := players.keys()
	ids.sort()
	return player_world_pos(players[ids[i % ids.size()]])


# ------------------------------------------------------------------ okolní obce (data/obce.json)

## Okolní obce (tools/obce.py → data/obce.json): pole dictů s id / name (fiktivní) / center / radius /
## boundary / roads / buildings / water / forest ve světových souřadnicích (x, z). Chybí-li soubor
## nebo má jiný formát → prázdné pole + varování (hra běží dál, jen bez obcí na mapě a ve světě).
static func _load_obce() -> Array:
	if not FileAccess.file_exists(Villages.DATA_PATH):
		push_warning("World: chybí %s – okolní obce bez dat (tools/obce.py)" % Villages.DATA_PATH)
		return []
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(Villages.DATA_PATH))
	if data is Dictionary and data.get("obce") is Array:
		return data["obce"]
	push_warning("World: neznámý formát %s" % Villages.DATA_PATH)
	return []


## Ohraničující obdélník katastru obce (svět x, z) z `boundary`; bez něj center ± radius.
## Výsledek se drží v `_obec_bounds` – používá obec_at() i mapa v HUD pro ořez kreslení.
func obec_bounds(o: Dictionary) -> Rect2:
	var id := String(o.get("id", o.get("name", "")))
	if _obec_bounds.has(id):
		return _obec_bounds[id]
	var r := Rect2()
	var first := true
	for q in o.get("boundary", []):
		if q is Array and q.size() >= 2:
			var p := Vector2(float(q[0]), float(q[1]))
			r = Rect2(p, Vector2.ZERO) if first else r.expand(p)
			first = false
	if first:
		var c: Array = o.get("center", [0.0, 0.0])
		var rr := float(o.get("radius", 500.0))
		r = Rect2(Vector2(float(c[0]), float(c[1])) - Vector2(rr, rr), Vector2(2.0 * rr, 2.0 * rr))
	_obec_bounds[id] = r
	return r


## Obec, v jejímž katastru bod (x, z) leží – pro budoucí „nacházíš se v X". Pravdivá
## příslušnost je polygon hranice (radius v datech je jen ekvivalentní plochy – jeho kružnice
## sousedům přesahuje i nedosahuje), při případných překryvech hranic vítězí nejbližší střed.
## Mimo všechny katastry → {}. Levné: 5 obcí, test v polygonu jen při zásahu obdélníku (obec_bounds).
func obec_at(pos: Vector3) -> Dictionary:
	var p := Vector2(pos.x, pos.z)
	var best: Dictionary = {}
	var bd := INF
	for o in obce:
		if not obec_bounds(o).has_point(p):
			continue
		var poly := PackedVector2Array()
		for q in o.get("boundary", []):
			if q is Array and q.size() >= 2:
				poly.append(Vector2(float(q[0]), float(q[1])))
		if poly.size() < 3 or not Geometry2D.is_point_in_polygon(p, poly):
			continue
		var c: Array = o.get("center", [])
		var d := p.distance_to(Vector2(float(c[0]), float(c[1]))) if c.size() >= 2 else 0.0
		if d < bd:
			bd = d
			best = o
	return best


# ------------------------------------------------------------------ zprávy klientům

## Kontextové akce (M0.4) – tenké obálky nad `ActionRunner`, ať je volají ostatní systémy jako `World.…`.
func register_target(t: Dictionary) -> void:
	if action_runner:
		action_runner.register_target(t)


func unregister_target(t: Dictionary) -> void:
	if action_runner:
		action_runner.unregister_target(t)


func targets_near(id: int, r: float) -> Array:
	return action_runner.targets_near(id, r) if action_runner else []


## Kam hráč míří: {kind: "ground" / "water" / druh cíle, pos, …} nebo {}.
func aim_point(id: int) -> Dictionary:
	return action_runner.aim_point(id) if action_runner else {}


func start_action(id: int, action_id: String, target: Dictionary) -> bool:
	return action_runner.start(id, action_id, target) if action_runner else false


func cancel_action(id: int, msg := "") -> void:
	if action_runner:
		action_runner.cancel(id, msg)


## Zavolá metodu HUD hráče `id` (show_message, popup, police_banner, quest_started…).
func notify(id: int, method: String, margs: Array) -> void:
	var cl = clients.get(id)
	if cl:
		cl.hud.callv(method, margs)


func play_sfx(id: int, name_: String, pitch := 1.0, vol := 0.0) -> void:
	var cl = clients.get(id)
	if cl:
		cl.play_sfx(name_, pitch, vol)


## Tmavá obrazovka (okno, spánek) – u hráče efekt, tady jen čekání na „probuzení“.
func blackout(id: int, dur: float) -> void:
	_blackout[id] = true
	var cl = clients.get(id)
	if cl:
		cl.blackout_fx(dur)
	await get_tree().create_timer(dur * 0.7).timeout
	_blackout.erase(id)


# ------------------------------------------------------------------ spawn

func _spawn_items() -> void:
	items_root = Node3D.new()
	items_root.name = "Predmety"
	add_child(items_root)
	var items: Array = meta["items"]
	_add_hips(items)
	for i in items.size():
		_spawn_item(i)
		item_totals[items[i]["type"]] = item_totals.get(items[i]["type"], 0) + 1


## i-tý předmět z map.json (i po načtení uložené pozice, když ho hráč mezitím sebral).
func _spawn_item(i: int) -> void:
	var it: Dictionary = meta["items"][i]
	var x := float(it["x"])
	var z := float(it["z"])
	var item := Item.new()
	item.setup(it["type"], Vector3(x, terrain.height_at(x, z), z))
	item.set_meta("idx", i)
	item.set_active(_item_present(i, String(it["type"]), int(clock.day_of_year()), weather.rain_recent))
	item.collected.connect(_on_collected)
	items_root.add_child(item)
	_item_nodes[i] = item


## Pořadí sebraných předmětů (pro uložení).
func collected_items() -> Array:
	return _collected.keys()


## Po načtení: sebrané předměty zmizí, nesebrané se vrátí na místo.
func restore_items(collected: Array) -> void:
	var want := {}
	for i in collected:
		want[int(i)] = true
	for i in (meta["items"] as Array).size():
		var node = _item_nodes.get(i)
		var alive: bool = is_instance_valid(node) and not node._taken
		if want.has(i) and alive:
			node._taken = true
			node.queue_free()
			_item_nodes.erase(i)
		elif not want.has(i) and not alive:
			_spawn_item(i)
	_collected = want
	_collected_jd.clear()
	for i in want:
		_collected_jd[i] = clock.jd()


func _on_collected(item: Item, by: Player) -> void:
	_collected[int(item.get_meta("idx", -1))] = true
	_collected_jd[int(item.get_meta("idx", -1))] = clock.jd()
	_item_nodes.erase(int(item.get_meta("idx", -1)))
	match item.kind:
		"dukat":
			by.money += 100
		"jablko", "hrib", "sipek":
			by.add_item(item.kind)
	emit_game_event(by.id, "collected", {"item": item, "kind": item.kind})


## Šípky (sezónní předmět listopad–únor) nejsou v map.json: rozmístí se deterministicky u jabloní
## a u části hřibových míst (okraje lesů) a přidají se na konec `meta["items"]` – pořadí starých předmětů
## (a tedy uložené hry) zůstává stejné.
func _add_hips(items: Array) -> void:
	for it in items:
		if it["type"] == "sipek":
			return
	var rng := RandomNumberGenerator.new()
	rng.seed = 1703
	var extra := []
	var n_hrib := 0
	for it in items:
		var kind: String = it["type"]
		if kind == "hrib":
			n_hrib += 1
			if n_hrib % 3 != 0:
				continue
		elif kind != "jablko":
			continue
		var a := rng.randf() * TAU
		var d := rng.randf_range(2.5, 7.0)
		var x := float(it["x"]) + cos(a) * d
		var z := float(it["z"]) + sin(a) * d
		if terrain.contains(x, z, 30.0):
			extra.append({"type": "sipek", "x": snappedf(x, 0.01), "z": snappedf(z, 0.01)})
	items.append_array(extra)


func _spawn_bots() -> void:
	graph = RoadGraph.new()
	graph.build(meta["roads"])
	var h: Dictionary = meta["domov_hrace"]
	var home := Vector2(h["x"], h["z"])
	var rng := RandomNumberGenerator.new()
	rng.seed = 122
	var cand := graph.nodes_within(home, 650.0, ["residential", "tertiary", "unclassified", "service",
		"living_street", "secondary", "footway", "path"])
	if cand.is_empty():
		cand = graph.nodes_within(home, 1500.0)
	bots_root = Node3D.new()
	bots_root.name = "Boti"
	add_child(bots_root)
	_bot_nodes = cand
	for i in N_VILLAGERS:
		var v := Villager.new()
		# Fáze 3 (LimboAI): prvních `Villager.BT_VILLAGERS` vesničanů řídí behavior strom denních rutin
		v.setup(graph, terrain, self, cand[rng.randi() % cand.size()], 1000 + i, Characters.profile(i),
			i < Villager.BT_VILLAGERS)
		bots_root.add_child(v)
	for i in N_DOGS:
		var n: Vector2 = graph.nodes[cand[rng.randi() % cand.size()]]
		var a := rng.randf() * TAU
		var p := n + Vector2(cos(a), sin(a)) * 6.0
		if i == 0:   # jeden pes rovnou u domu hráče
			p = Vector2(float(meta["spawn"]["x"]) + 3.0, float(meta["spawn"]["z"]) + 2.0)
		var dog := Dog.new()
		dog.setup(terrain, self, Vector3(p.x, terrain.height_at(p.x, p.y), p.y), 2000 + i)
		bots_root.add_child(dog)


## Fyzikální předměty: u domu míč, bedny, sudy; u silnic v obci popelnice a schránky.
func _spawn_props() -> void:
	var sp: Dictionary = meta["spawn"]
	var base := Vector3(float(sp["x"]), 0, float(sp["z"]))
	var fwd := Vector3(float(sp["look_x"]) - base.x, 0, float(sp["look_z"]) - base.z).normalized()
	var right := fwd.cross(Vector3.UP)
	var defs := [
		["ball", base + right * 3.0 + fwd * 2.0],
		["crate", base - right * 3.5 + fwd * 1.0], ["crate", base - right * 3.5 + fwd * 2.0],
		["crate", base - right * 3.5 + fwd * 1.5 + Vector3(0, 0.85, 0)],
		["barrel", base + right * 4.0 - fwd * 1.5], ["barrel", base + right * 4.8 - fwd * 0.6],
	]
	for d in defs:
		var p: Vector3 = d[1]
		p.y += terrain.height_at(p.x, p.z) + 0.6
		add_child(_prop(d[0], p))
	# popelnice a schránky podél silnic v obci
	var root := Node3D.new()
	root.name = "Vybaveni_ulic"
	add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var cand := graph.nodes_within(Traffic.VILLAGE_CENTER, 480.0, ["residential", "tertiary", "unclassified", "service"])
	var used: Array[Vector2] = []
	for i in cand:
		if used.size() >= 70:
			break
		if rng.randf() > 0.35:
			continue
		var nb: Array = graph.adj[i]
		if nb.is_empty():
			continue
		var dir := (graph.nodes[nb[0]] - graph.nodes[i]).normalized()
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var kind := graph.kinds[i]
		var off := 4.4 if kind in ["tertiary", "secondary"] else 3.6
		var p := graph.nodes[i] + Vector2(-dir.y, dir.x) * off * side
		# ne na křižovatce – kolmice od jedné silnice by padla doprostřed druhé
		var ok := nb.size() <= 2 and dist_to_roads(p) > off - 0.3
		for u in used:
			if u.distance_to(p) < 18.0:
				ok = false
				break
		if not ok:
			continue
		used.append(p)
		var y := terrain.height_at(p.x, p.y)
		var k := "popelnice" if rng.randf() < 0.75 else "schranka"
		var pr := Prop.make(k, Vector3(p.x, y + 0.02, p.y), atan2(dir.x, dir.y) + (PI / 2 if side > 0 else -PI / 2))
		pr.damaged.connect(_on_prop_damaged)
		root.add_child(pr)


## Vzdálenost bodu od nejbližší osy silnice (pro auta) v okolí 40 m.
func dist_to_roads(p: Vector2) -> float:
	var best := INF
	for i in graph.nodes_within(p, 40.0, RoadGraph.CAR_KINDS):
		for j in graph.adj[i]:
			if graph.edge(i, j) in RoadGraph.CAR_KINDS:
				var q := Geometry2D.get_closest_point_to_segment(p, graph.nodes[i], graph.nodes[j])
				best = minf(best, q.distance_to(p))
	return best


func _on_prop_damaged(prop: Prop, what: String) -> void:
	# hlásí se jen škody způsobené hráčem (pěšky nebo jeho autem) – tomu, kdo byl nejblíž
	var pos := prop.global_position
	for p in players.values():
		var by_player: bool = p.global_position.distance_to(pos) < 6.0
		if p.car and p.car.global_position.distance_to(pos) < 8.0:
			by_player = true
		if by_player:
			emit_game_event(p.id, "prop_damaged", {"what": what})
			return


func _prop(kind: String, pos: Vector3) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.collision_layer = 8
	rb.collision_mask = 1 | 2 | 4 | 8 | 16
	rb.position = pos
	rb.continuous_cd = true
	var shape: Shape3D
	var mesh: Mesh
	var mat := StandardMaterial3D.new()
	var pm := PhysicsMaterial.new()
	match kind:
		"ball":
			var s := SphereShape3D.new()
			s.radius = 0.22
			shape = s
			var m := SphereMesh.new()
			m.radius = 0.22
			m.height = 0.44
			mesh = m
			rb.mass = 0.45
			pm.bounce = 0.65
			pm.friction = 0.6
			mat.albedo_color = Color(0.95, 0.95, 0.95)
			rb.angular_damp = 0.8
		"crate":
			var s := BoxShape3D.new()
			s.size = Vector3(0.8, 0.8, 0.8)
			shape = s
			var m := BoxMesh.new()
			m.size = s.size
			mesh = m
			rb.mass = 18.0
			pm.friction = 0.8
			mat.albedo_color = Color(0.6, 0.42, 0.22)
		"barrel":
			var s := CylinderShape3D.new()
			s.radius = 0.3
			s.height = 0.9
			shape = s
			var m := CylinderMesh.new()
			m.top_radius = 0.3
			m.bottom_radius = 0.3
			m.height = 0.9
			mesh = m
			rb.mass = 12.0
			pm.friction = 0.7
			mat.albedo_color = Color(0.3, 0.45, 0.6)
			mat.metallic = 0.4
			mat.roughness = 0.5
	rb.physics_material_override = pm
	var cs := CollisionShape3D.new()
	cs.shape = shape
	rb.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	rb.add_child(mi)
	return rb


func _spawn_places() -> void:
	var pois: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/pois.json"))
	var root := Node3D.new()
	root.name = "Mista"
	add_child(root)
	for k in pois:
		var pl := Place.new()
		pl.setup(k, pois[k], terrain, self)
		root.add_child(pl)
		places[k] = pl
		if pl.keeper:
			npcs[k] = pl.keeper
	if places["hospoda"].regulars.size() > 0:
		npcs["pepa"] = places["hospoda"].regulars[0]
	# děda Vomáčka na lavičce kousek od usedlosti (místo „domov“ je teď ještě na původním bodu z pois.json;
	# jeho dům = nejbližší rodinný dům k lavičce, Estate.deda_id – číslo doplní build po sestavení registru)
	var home: Place = places["domov"]
	var dp := home.door + Vector3(-3.0, 0, 5.5)
	dp.y = terrain.height_at(dp.x, dp.z)
	var bench := Prop.make("lavicka", dp + Vector3(0, 0.02, -0.25), 0.0)
	root.add_child(bench)
	var deda := Npc.make("Děda Vomáčka", "", Color(0.45, 0.4, 0.3), 9, dp + Vector3(0, 0, -0.05), 0.0, self, true)
	deda.visual.hair_style = 1
	deda.visual.moustache = true
	deda.visual.hat = true
	deda.persona = Persona.make({"name": "Děda Vomáčka", "trait": "moudry", "job": "důchodce, soused od vedle",
		"age": 84, "hobby": "Kouřím od čtrnácti a pořád tu jsem.", "topics": ["kun", "pole", "traktor", "motorka"]})
	deda.role = "deda"
	root.add_child(deda)
	npcs["deda"] = deda
	# rádio na zahradním stolku vedle dveří domova (M1.7: apply_home ho přesune k vchodu domova hráče)
	var rp := home.door + Vector3(0.3, 0, 2.3)
	rp.y = terrain.height_at(rp.x, rp.z) + 0.02
	radio = Radio.make(self, rp, home.data.get("face_yaw", 0.0))
	root.add_child(radio)


# ------------------------------------------------------------------ interiéry (M1.4)

## Základ prostoru interiérů: daleko za katastrem (mimo potoky, terén se tam jen „natáhne“) a 400 m pod zemí;
## i-tý interiér stojí o 60 m dál v ose X.
const INTERIOR_BASE := Vector3(12000, -400, 12000)
const INTERIOR_STEP := 60.0


## M1.8: nic se nestaví předem – domov a veřejné budovy M1.5 (stálé sloty 0–6) i generované interiéry staví
## `InteriorStreamer`, až když je hráč u dveří (nebo uvnitř / při načtení hry `ensure_interior`).
func _spawn_interiors() -> void:
	var root := Node3D.new()
	root.name = "Interiery"
	add_child(root)
	interior_streamer = InteriorStreamer.new()
	add_child(interior_streamer)
	interior_streamer.setup(self, root)


## Interiér `iid` postavený a připravený (postaví ho hned, když chybí). false = takový interiér neexistuje.
func ensure_interior(iid: String) -> bool:
	if interior_streamer:
		return interior_streamer.ensure(iid)
	return interiors.has(iid)


## Dveře modelu budovy domova hráče 1 (BuildingDetails přes Estate) nebo Vector3.INF, když data budov chybí.
func home_door() -> Vector3:
	if building_details == null:
		return Vector3.INF
	var bid := estate.home_estate(1) if estate else building_details.building_of_home()
	return building_details.door_of(bid) if bid > 0 else Vector3.INF


## Id budovy domova hráče `id` (Estate; bez registru původní dům z dat budov).
func home_building(id: int) -> int:
	if estate:
		return estate.home_estate(id)
	return building_details.building_of_home() if building_details else 0


## „byt 5 v č. p. 48“ / „č. p. 48“ – pro texty úkolů, nabídek a rozhovorů.
func home_label(id: int) -> String:
	return estate.home_label(id) if estate else "domov"


func deda_label() -> String:
	return estate.deda_label() if estate else "vedle"


## Dveře usedlosti (původní dům hráče z podkladů): hospodářství, včelař a překupník se měří odsud,
## ať zůstanou na svém místě, i když hráč bydlí jinde (M1.7). Zahrada a výběh koně jsou u domova – `home_grounds`.
func lot_door() -> Vector3:
	if estate:
		return estate.lot_door()
	return (places["domov"] as Place).door if places.has("domov") else Vector3.ZERO


func lot_park() -> Vector3:
	if estate:
		return estate.lot_park()
	return (places["domov"] as Place).park if places.has("domov") else Vector3.ZERO


## Kotva pro zahradu a výběh koně u domova hráče 1 (stěhuje se s domovem – M1.7 nájemní byt, M4.7 koupě):
## {door: dveře domova, face: střed budovy domova (Vector2 – směr „od domu“), park: parkování u domova}.
## Bez registru nemovitostí: usedlost (původní dům z podkladů).
func home_grounds() -> Dictionary:
	var door := lot_door()
	var park := lot_park()
	var face := Vector2(door.x, door.z)
	var hc: Dictionary = meta.get("domov_hrace", {})
	if hc.has("x"):
		face = Vector2(float(hc["x"]), float(hc["z"]))
	if estate and places.has("domov"):
		var d: Vector3 = estate.home_door(1)
		if d != Vector3.INF:
			door = d
		var c = estate.info(estate.home_estate(1)).get("center", Vector2.ZERO)
		if c is Vector2 and c != Vector2.ZERO:
			face = c
		park = (places["domov"] as Place).park
	return {"door": door, "face": face, "park": park}


## Přesune místo „domov“ (dveře a interakce E, parkování, rádio u vchodu, interiér: byt / dům, titulek) k nemovitosti,
## kterou hráč `pid` vlastní / má pronajatou (M1.7). Volá build (nová hra), SaveGame (načtení) a M4.7 (koupě).
## DOPLNIT (MP): místo „domov“ je jedno – přesouvá se jen pro místního hráče (id 1).
func apply_home(pid: int) -> void:
	if estate == null or not places.has("domov") or pid != 1:
		return
	var home: Place = places["domov"]
	var eid := estate.home_estate(pid)
	var title := "Domov – " + estate.home_label(pid)
	var rp := Vector3.ZERO
	var face := 0.0
	if eid == estate.lot_id and not estate.lot_data().is_empty():
		# usedlost: původní body z pois.json (interakce E, parkování, rádio jako dřív)
		var ld: Dictionary = estate.lot_data()
		face = float(ld.get("face_yaw", 0.0))
		var dz := estate.lot_door()
		var pk := estate.lot_park()
		home.relocate(dz, pk, float(ld.get("park_yaw", 0.0)), face, title)
		rp = dz + Vector3(0.3, 0, 2.3)
	else:
		var e := estate.info(eid)
		var d: Vector3 = e.get("door", Vector3.INF)
		if d == Vector3.INF:
			d = home.door
		var n: Vector3 = e.get("normal", Vector3(0, 0, 1))
		n.y = 0.0
		n = n.normalized() if n.length() > 0.01 else Vector3(0, 0, 1)
		face = atan2(n.x, n.z)
		var along := Vector3(n.z, 0.0, -n.x)
		# parkování: volné rovné místo kousek před vchodem (smí být u silnice), jinak 7 m před dveřmi
		var park := d + n * 7.0
		var park_yaw := face + PI * 0.5
		var sp := _ground_spot(d + n * 5.0, Vector2(d.x, d.z), 4801 + pid, Vector3(2.2, 1.6, 4.8), 1.5, 0.0)
		if not sp.is_empty():
			park = sp[0]
			park_yaw = float(sp[1])
		park.y = terrain.height_at(park.x, park.z)
		home.relocate(d, park, park_yaw, face, title)
		rp = d + n * 1.6 - along * 1.4
	_exit_cache.erase("domov")
	if radio:
		rp.y = terrain.height_at(rp.x, rp.z) + 0.02
		if _radio_home.is_empty():
			radio.position = rp
			radio.rotation.y = face
		else:
			_radio_home = {"pos": rp, "yaw": face}
	if interior_streamer:
		interior_streamer.set_home(estate.home_title(pid), estate.is_flat(pid))
	# zahrada a výběh koně se přestěhují k domovu (při prvním volání z build ještě nejsou – vytvoří se v add_player);
	# obvodové ploty (Fáze 7) se před hledáním místa zahodí – jinak by jejich kolize blokovala sondu `_find_spot` –
	# a po relocate se postaví znovu na nové pozici
	if fences:
		fences.clear_auto()
	if paddock:
		paddock.relocate()
	if garden:
		garden.relocate()
	if fences:
		fences.rebuild()


## Kam hráč vyjde z interiéru `iid`: [poloha na zemi ~1 m před dveřmi, yaw od domu]. Dveře modelu z BuildingDetails,
## bez nich bod `door_x/z` a `face_yaw` z pois.json (DOPLNIT: dveře modelu usedlosti leží ~6 m od bodu z pois.json).
func interior_exit(iid: String) -> Array:
	if not _exit_cache.has(iid):
		_exit_cache[iid] = _compute_exit(iid)
	return _exit_cache[iid]


func _compute_exit(iid: String) -> Array:
	if iid.begins_with("b:") and estate:             # M1.8: generovaný interiér – dveře nemovitosti
		var e := estate.info(int(iid.substr(2)))
		var d: Vector3 = e.get("door", Vector3.INF)
		if d != Vector3.INF:
			var nn: Vector3 = e.get("normal", Vector3(0, 0, 1))
			nn.y = 0.0
			nn = nn.normalized() if nn.length() > 0.01 else Vector3(0, 0, 1)
			var ep := d + nn * 1.0
			ep.y = terrain.height_at(ep.x, ep.z)
			return [ep, atan2(-nn.x, -nn.z)]
	var pl: Place = places.get(iid)
	if building_details != null:
		var bid := home_building(1) if iid == "domov" else building_details.building_of_place(iid)
		var di := building_details.door_info(bid) if bid > 0 else {}
		if not di.is_empty():
			var n: Vector3 = di["normal"]
			n.y = 0.0
			n = n.normalized() if n.length() > 0.01 else Vector3(0, 0, 1)
			var pos: Vector3 = di["pos"] + n * 1.0
			pos.y = terrain.height_at(pos.x, pos.z)
			return [pos, atan2(-n.x, -n.z)]
	if pl == null:
		var sp: Array = default_spawn()
		return [sp[0], sp[1]]
	var face := float(pl.data.get("face_yaw", 0.0))
	var pos2 := pl.door + Vector3(sin(face), 0, cos(face)) * 1.5
	pos2.y = terrain.height_at(pos2.x, pos2.z)
	return [pos2, face + PI]


## Hráč vstoupí do interiéru `iid` (E u dveří → „Vejít dovnitř“). `fade` = krátké ztmavení (0,3 s), bez něj okamžitě.
func enter_interior(id: int, iid: String, fade := true, force := false) -> void:
	var pl: Player = players.get(id)
	if pl == null or _blackout.has(id) or pl.inside != "":
		return
	if interior_streamer and not force:
		iid = interior_streamer.entry_for(id, iid)      # M1.8: byt → nejdřív chodba bytového domu
	if pl.car or pl.horse or pl.aircraft:
		notify(id, "show_message", ["Nejdřív vystup / sesedni.", 2.0])
		return
	if not force and not _may_enter(id, iid):
		return
	if not ensure_interior(iid):                         # M1.8: postavený zblízka; když ještě ne, dostaví se hned
		return
	var it: Interior = interiors.get(iid)
	var was_locked := pl.controls_locked             # A1-17: zámek od otevřeného menu / panelu neodemykat
	if fade:
		pl.controls_locked = true
		blackout(id, 0.6)
		await get_tree().create_timer(0.25).timeout
		play_sfx(id, "door")
	interior_mark(pl, iid)
	pl.teleport(it.inside_door, it.inside_yaw, false)
	pl.controls_locked = was_locked
	emit_game_event(id, "entered_interior", {"id": iid})
	_check_floor(it.inside_door, "vstup do „%s“" % iid)


## Veřejná budova: zamčeno mimo otevírací dobu, postrach vsi obsluha nepustí (M1.5). Domov a debug (`force`) vždy.
func _may_enter(id: int, iid: String) -> bool:
	if iid.begins_with("b:"):
		return interior_streamer.may_enter(id, iid) if interior_streamer else false
	var pl: Place = places.get(iid)
	if pl == null or iid == "domov":
		return true
	if not pl.is_open(clock.hour()):
		notify(id, "show_message", ["Zamčeno. Otevřeno %s." % pl.hours_text(), 2.5])
		return false
	var r: Reputation = reputations.get(id)
	if r and r.refused_at(iid):
		if pl.keeper:
			pl.keeper.say("Tebe tu nechci vidět!", 3.0)
		notify(id, "show_message", ["Obsluha tě nepustí dál – špatná pověst (%s)." % r.tier_name(), 3.0])
		return false
	return true


## Výška pevné země pod bodem `pos` (raycast na statiku, vrstva 1, shora dolů); bez zásahu `fallback`.
## Zásah zahodíme, je-li výrazně nad / pod očekávaným terénem (střecha, převis) – pak platí terén.
func _ground_y(pos: Vector3, fallback: float) -> float:
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space == null:
		return fallback
	var q := PhysicsRayQueryParameters3D.create(Vector3(pos.x, maxf(pos.y, fallback) + 1.5, pos.z),
		Vector3(pos.x, minf(pos.y, fallback) - 3.0, pos.z), 1)
	var hit := space.intersect_ray(q)
	if hit.is_empty() or (hit["normal"] as Vector3).y < 0.5:
		return fallback
	var hy: float = (hit["position"] as Vector3).y
	return hy if absf(hy - fallback) < 1.2 else fallback


## A1-20: po vstupu do interiéru zkontroluje, že pod bodem `pos` je podlaha; jinak jen zapíše varování do logu.
## Čeká jeden fyzikální snímek – kolize čerstvě postaveného interiéru se do prostoru zapisují až v něm.
func _check_floor(pos: Vector3, tag: String) -> void:
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.6, 0), pos + Vector3(0, -3.0, 0), 1)
	if space.intersect_ray(q).is_empty():
		push_warning("World: %s – pod bodem y=%.2f není podlaha (kontrolní raycast)" % [tag, pos.y])


## Hráč vyjde ven před dveře (otočený od domu).
func exit_interior(id: int, fade := true) -> void:
	var pl: Player = players.get(id)
	if pl == null or pl.inside == "" or _blackout.has(id):
		return
	var iid := pl.inside
	if interior_streamer and interior_streamer.exit_to_stairs(id, iid, fade):
		return                                       # M1.8: z bytu do chodby bytového domu
	var was_locked := pl.controls_locked             # A1-17: když je otevřené menu (zámek od něj), po výstupu se neodemyká
	if fade:
		pl.controls_locked = true
		blackout(id, 0.6)
		await get_tree().create_timer(0.25).timeout
		play_sfx(id, "door")
	var spot := interior_exit(iid)
	interior_clear(pl)
	# A1-10: propad po odchodu z obchodu (příčina nepotvrzena) – výška se ověří raycastem na statiku
	# (podlaha / práh / terén) a rozdíl proti terénu se zapíše do logu
	var ep: Vector3 = spot[0]
	var ty := terrain.height_at(ep.x, ep.z)
	var gy := _ground_y(ep, ty)
	if absf(gy - ep.y) > 0.3 or absf(ty - ep.y) > 0.3:
		print("exit_interior[%s]: uložený bod y=%.2f, terén y=%.2f, raycast y=%.2f → použito %.2f" % [iid, ep.y, ty, gy, gy])
	ep.y = gy
	pl.teleport(ep + Vector3(0, 0.3, 0), spot[1], false)
	pl.controls_locked = was_locked
	emit_game_event(id, "exited_interior", {"id": iid})


## Poznačí, že hráč je v interiéru (světla, interakce) a přesune do něj rádio (jedna instance). Volá i SaveGame.
func interior_mark(pl: Player, iid: String) -> void:
	var it: Interior = interiors.get(iid)
	if it == null:
		return
	if pl.inside != "" and pl.inside != iid:
		interior_clear(pl)
	pl.inside = iid
	it.set_active(true)
	if interior_streamer:
		interior_streamer.on_enter(pl, iid)             # M1.8: obyvatel cizího domu u stolu
	if places.has(iid):
		(places[iid] as Place).set_inside(true, it)       # obsluha a štamgasti přejdou dovnitř (M1.5)
	if radio and it.radio_spot != Vector3.INF:
		if _radio_home.is_empty():
			_radio_home = {"pos": radio.position, "yaw": radio.rotation.y}
		radio.position = it.radio_spot
		radio.rotation.y = it.radio_yaw


## Hráč už není v interiéru (odchod, teleport, respawn, načtení hry): vypne světla a vrátí rádio na zahradu.
func interior_clear(pl: Player) -> void:
	if pl.inside == "":
		return
	var it: Interior = interiors.get(pl.inside)
	if it:
		it.set_active(false)
	if places.has(pl.inside):
		(places[pl.inside] as Place).set_inside(false, it)
	pl.inside = ""
	if radio and not _radio_home.is_empty():
		radio.position = _radio_home["pos"]
		radio.rotation.y = _radio_home["yaw"]
		_radio_home = {}


## Ladicí teleport (F2): rovnou dovnitř, i z auta / z koně.
func teleport_inside(id: int, iid: String) -> void:
	var pl: Player = players.get(id)
	if pl == null or not ensure_interior(iid):
		return
	if pl.car:
		exit_car(id)
	if pl.horse:
		dismount_horse(id)
	if pl.aircraft:
		exit_aircraft(id)
	interior_clear(pl)
	enter_interior(id, iid, false, true)


## Provizorní noclehy: seník za hospodou, palanda u Myslivecké chaty (volné rovné místo kousek od dveří).
func _spawn_sleep_spots() -> void:
	var root := Node3D.new()
	root.name = "Noclehy"
	add_child(root)
	for d in [["hospoda", "senik", Vector3(2.6, 2.2, 3.0), 9.0], ["chata", "palanda", Vector3(2.0, 2.3, 3.0), 7.0]]:
		if not places.has(d[0]):
			continue
		var door: Vector3 = places[d[0]].door
		var sp := _ground_spot(door, Vector2(door.x, door.z), 221 + sleep_spots.size(), d[2], d[3], 4.5)   # 221 = jen seed
		if sp.is_empty():
			push_warning("Nocleh u %s: nenašlo se volné místo" % d[0])
			continue
		var s := SleepSpot.make(d[1], sp[0], sp[1])
		root.add_child(s)
		sleep_spots.append(s)


func _connect_car(c: Car) -> void:
	if c.has_meta("world_connected"):
		return
	c.set_meta("world_connected", true)
	c.crashed.connect(func(impact: float, what: String, other: Object): _on_car_crash(c, impact, what, other))
	c.hit_person.connect(func(who: Node, spd: float): _on_hit_person(c, who, spd))


# ------------------------------------------------------------------ API pro úkoly

## Poloha hráče (v autě poloha auta).
func player_pos(id: int) -> Vector3:
	var p: Player = players[id]
	return p.car.global_position if p.car else player_world_pos(p)   # uvnitř budovy vnější dveře (M1.4)


func place_pos(key: String) -> Vector3:
	if key == "deda" or key == "pepa":
		return npcs[key].global_position
	return places[key].door


func place_park(key: String) -> Vector3:
	return places[key].park


## NPC něco řekne (bublina vidí všichni), hráč `id` to dostane i jako text v HUD.
func npc_say(id: int, key: String, text: String) -> void:
	var k := key
	if key in ["hospoda"] and npcs.has("pepa"):
		k = "pepa"
	if npcs.has(k):
		npcs[k].say(text, 4.5)
	notify(id, "popup", ["„%s“" % text, 4.0])


func move_player_car_to(id: int, key: String) -> void:
	var pl: Place = places[key]
	var c := traffic.car_of(id)
	if c == null or players[id].car == c:
		return
	traffic.place_car(c, Vector2(pl.park.x, pl.park.z), pl.park_yaw)


## Silniční kontrola zhruba v polovině nejkratší trasy autem mezi dvěma místy (na hlavní silnici).
func setup_checkpoint_on_route(a: String, b: String) -> void:
	var pa: Vector3 = places[a].park
	var pb: Vector3 = places[b].park
	var ids := graph.route(Vector2(pa.x, pa.z), Vector2(pb.x, pb.z))
	var best := -1
	var bd := INF
	for k in range(1, ids.size() - 1):
		var e := graph.edge(ids[k], ids[k + 1])
		if e in ["tertiary", "secondary"]:
			var d := absf(float(k) / ids.size() - 0.55)
			if d < bd:
				bd = d
				best = k
	if best < 0:
		best = ids.size() / 2
	if ids.size() > 2:
		police.set_checkpoint(graph.nodes[ids[best]])


# ------------------------------------------------------------------ události

## Herní událost hráče `id`: jeho klient ji zobrazí (zvuk, zpráva, efekt), jeho úkoly ji vyhodnotí.
func emit_game_event(id: int, kind: String, data: Dictionary) -> void:
	if DialogData.RECENT_MAP.has(kind):
		if not talk_recent.has(id):
			talk_recent[id] = {}
		talk_recent[id][kind] = clock.minutes
	var cl = clients.get(id)
	if cl:
		cl.on_game_event(kind, data)
	var q: Quests = quests.get(id)
	if q:
		q.on_event(kind, data)
	var r: Reputation = reputations.get(id)
	if r:
		r.on_event(kind, data)
	var sk: Skills = skills.get(id)
	if sk:
		sk.on_event(kind, data)
	if favors:
		favors.on_event(id, kind, data)     # M4.5: splněné prosby (sklizeň, sníh, dárek jídla)
	var jb: Jobs = jobs.get(id)
	if jb:
		jb.on_event(kind, data)      # M3.1: úkoly směny (action_done), pití v práci, zadržení → výpověď
	if computer:
		computer.on_event(id, kind, data)   # M3.4: drby na webu obce, výzvy k zaplacení pokuty, upomínky e-mailem


## Pošle hráči e-mail (M3.4, čte se na počítači doma – Pošta). Pro práci, zákon, události v obci, obchody…
func send_mail(id: int, sender: String, subject: String, body: String) -> void:
	if computer:
		computer.send_mail(id, sender, subject, body)


## Dá hráči XP do dovednosti (volají ostatní systémy – akce, řemesla, práce). `why` = krátký popis pro HUD.
func give_xp(id: int, skill: String, amount: float, why := "") -> void:
	var sk: Skills = skills.get(id)
	if sk:
		sk.add_xp(skill, amount, why)


func _on_car_crash(c: Car, impact: float, what: String, other: Object) -> void:
	if impact > 3.0:
		sound.emit(c.global_position, "crash", randf_range(0.8, 1.1), clampf(impact - 8.0, -10.0, 6.0), 120.0)
	var drv: Player = players.get(c.driver_id) if c.driver_id != 0 else null
	if drv == null:
		# někdo narazil do auta, které řídí hráč?
		var oc := other as Car
		if oc and oc.driver_id != 0 and players.has(oc.driver_id):
			emit_game_event(oc.driver_id, "car_crash", {"impact": impact, "what": "auto", "car": oc})
		return
	if what in ["silnice", "cesta", "terén"] and impact < 6.0:
		return
	if c.two_wheeler and impact > 4.5:
		# pád z kola / motorky: jezdec přeletí přes řídítka
		var v := c.linear_velocity
		notify(drv.id, "police_banner", ["Spadl jsi z %s!" % ("kola" if c.model.kind == "bike" else "motorky"), 3.0])
		emit_game_event(drv.id, "car_crash", {"impact": impact, "what": what, "car": c})
		police.report_crash(c.global_position, what, drv)
		exit_car(drv.id)
		drv.knock(v * 0.6 + Vector3.UP * 2.5, impact * 0.9)
		return
	notify(drv.id, "police_banner", ["Náraz: %s (%d km/h) – poškození auta %d %%" % [what, int(impact * 3.6), int(c.damage)], 3.0])
	emit_game_event(drv.id, "car_crash", {"impact": impact, "what": what, "car": c})
	police.report_crash(c.global_position, what, drv)
	# zranění řidiče při tvrdém nárazu (bez airbagu ve staré 120 horší)
	if impact > 7.0:
		drv.body.hurt((impact - 7.0) * (3.0 if c.model_id == "sedan120" else 1.8), "náraz autem")


func _on_hit_person(c: Car, who: Node, spd: float) -> void:
	var drv: Player = players.get(c.driver_id) if c.driver_id != 0 else null
	if who is Animal or who is Horse:
		# srážka se zvěří (nebo s koněm) – bez policie; poškození auta, zranění řidiče, povinnost nahlásit myslivcům
		if drv:
			var is_horse := who is Horse
			var what := "koně" if is_horse else String((who as Animal).spec["name"]).to_lower()
			var mass: float = 550.0 if is_horse else float((who as Animal).spec["mass"])
			var species: String = "kun" if is_horse else (who as Animal).species
			var dmg := clampf(HIT_DAMAGE_K * mass * spd * spd * (HIT_HORSE_K if is_horse else 1.0), 0.0, 100.0)
			c.damage = minf(c.damage + dmg, 100.0)
			var text := "Srazil jsi: %s (%d km/h)! Poškození auta +%d %% (celkem %d %%)" % [what, int(spd * 3.6), roundi(dmg),
				roundi(c.damage)]
			if mass >= HIT_INJURY_MASS and spd > HIT_INJURY_SPEED:
				drv.body.hurt((spd - HIT_INJURY_SPEED) * HIT_INJURY_K * mass / 85.0, "srážka se zvěří")
				text += "\nNáraz tě zranil."
			notify(drv.id, "police_banner", [text, 4.5])
			_hit_animal_followup(drv.id, who, species, spd, dmg)
		return
	if drv:
		notify(drv.id, "police_banner", ["SRAZIL JSI ČLOVĚKA!", 4.0])
		emit_game_event(drv.id, "hit_person", {"speed": spd})
		police.report_hit_person(c.global_position, drv)


## Až zvíře po nárazu dopadne: uhynulé tělo zůstane ležet (do vyzvednutí myslivcem) a hráči vznikne
## povinnost srážku nahlásit (Quests.register_hit → úkol „Srážka se zvěří“).
func _hit_animal_followup(id: int, who: Node, species: String, spd: float, dmg: float) -> void:
	var pos := (who as Node3D).global_position
	await get_tree().create_timer(0.2).timeout
	var animal: Animal = null
	var dead := false
	if is_instance_valid(who):
		pos = (who as Node3D).global_position
		if who is Animal:
			animal = who as Animal
			dead = animal.dead
			if dead:
				animal.keep_corpse = true
	emit_game_event(id, "hit_animal", {"species": species, "speed": spd, "pos": pos, "animal": animal, "dead": dead,
		"damage": dmg})


func _on_busted(id: int, p: float, reason: String) -> void:
	var pl: Player = players.get(id)
	if pl == null:
		return
	var oid := "alkohol_nad_1" if p >= 1.0 else "alkohol_do_1"
	if reason.begins_with("řízení přes zákaz"):
		oid = "rizeni_pres_zakaz"
	var res := commit_offense(id, oid, {"severity": 1.0 if p >= 1.0 else 0.0, "quiet": true})
	var text := "ZADRŽEN POLICIÍ\n%s\nPokuta %d Kč (%s), zákaz řízení %d h.\n%s" % [
		reason, res.get("fine", 0), "zaplaceno %d Kč" % res.get("paid", 0) if int(res.get("paid", 0)) > 0 else "příkaz k úhradě přijde poštou",
		int(res.get("ban_h", 0.0)), "Kůň zůstal u cesty." if pl.horse else "Auto odtaženo domů."]
	if int(res.get("points", 0)) > 0:
		text += "\n+%d bodů (celkem %d / %d)." % [res["points"], res["total_points"], int(Law.setting("body_limit", 12.0))]
	if res.get("points_ban", false):
		text += "\nDosáhl jsi 12 bodů – zákaz řízení na rok."
	# úkoly se o zadržení dozví hned – dřív než se auto odtáhne domů (jinak by „Autem z hospody“ uspěl)
	emit_game_event(id, "busted", {"promile": p, "reason": reason})
	if pl.car:
		exit_car(id)
	elif pl.horse:
		dismount_horse(id)
	move_player_car_to(id, "domov")
	if p >= 1.0:
		var zr := commit_offense(id, "zachytka", {"quiet": true})
		text += "\nNoc strávíš na záchytce (+%s Kč)." % _thousands(int(zr.get("fine", 0)))
		await blackout(id, 2.0)
		var h := fmod(31.0 - clock.hour(), 24.0)
		skip_time(id, maxf(h, 1.0), true)
		var home: Place = places["domov"]
		interior_clear(pl)
		pl.teleport(home.door + Vector3(0, 0.3, 0), pl.yaw, false)
	notify(id, "show_message", [text, 9.0])


## Jediná brána pro tresty (M0.5): zapíše přestupek do rejstříku (Law.LawRecord), vybere pokutu, přičte body,
## případně dá zákaz řízení a pošle událost „offense“. data: severity 0..1, quiet (bez zprávy o bodech).
## M4.2 – platba podle `misto` z katalogu: na_miste = bloková pokuta hned z hotovosti (jinak složenka v `debts`),
## spravni_rizeni = příkaz poštou za 1–3 dny (pak dluh se splatností), soud = dluh rovnou (do M4.3).
func commit_offense(id: int, offense_id: String, data := {}) -> Dictionary:
	var lr: Law.LawRecord = law.get(id)
	var pl: Player = players.get(id)
	if lr == null or pl == null:
		return {"ok": false, "id": offense_id}
	var d: Dictionary = data.duplicate()
	d["player"] = pl
	var res := lr.commit(offense_id, d, clock.minutes)
	if not res.get("ok", false):
		return res
	var fine: int = int(res["fine"])
	var jd := clock.jd()
	var rec: Dictionary = lr.records[-1] if not lr.records.is_empty() else {}
	match String(res.get("misto", "na_miste")):
		"na_miste":
			if fine > 0 and pl.money >= fine:
				pl.money -= fine
				res["paid"] = fine
				rec["zaplaceno"] = true
				rec["stav"] = "zaplaceno"
				play_sfx(id, "cash")
			elif fine > 0:
				debts.add(id, "pokuta", fine, jd + Debts.DUE_DAYS, "%s (bloková pokuta)" % res["name"], offense_id)
				rec["stav"] = "splatne"
		"spravni_rizeni":
			if fine > 0:
				debts.queue_order(id, fine, jd, "%s (%s)" % [res["name"], res["par"]], offense_id)
				rec["stav"] = "prikaz"
		_:
			if fine > 0:
				debts.add(id, "pokuta", fine, jd + Debts.DUE_DAYS, "%s (soud – zjednodušeně)" % res["name"], offense_id)
				rec["stav"] = "splatne"
	emit_game_event(id, "offense", {"id": offense_id, "fine": res["fine"], "points": res["points"],
		"criminal": res["criminal"]})
	if res.get("points_ban", false) and permits:   # M4.1: 12 bodů → řidičák odebrán, nutné přezkoušení
		var ban_jd: int = clock.jd() + int(ceil(Law.setting("zakaz_za_body_h", 8760.0) / 24.0))
		permits.revoke(id, "ridicsky", "12 bodů", ban_jd, true)
	if not data.get("quiet", false):
		if res["points_ban"]:
			notify(id, "popup", ["12 bodů – zákaz řízení na rok! Řidičák se odebírá – nutné přezkoušení v autoškole.", 5.0])
		elif int(res["points"]) > 0:
			notify(id, "show_message", ["%s: +%d bodů (celkem %d / %d)" % [res["name"], res["points"],
				res["total_points"], int(Law.setting("body_limit", 12.0))], 4.0])
	return res


## M4.2 úřad: zaplatí otevřené pokuty a dluhy z hotovosti (od nejstarší). Vrací zaplacenou částku.
func pay_debts_office(id: int) -> int:
	var due := debts.total(id, Debts.FINE_KINDS)
	if due <= 0:
		notify(id, "show_message", ["Na úřadě nemáš žádné nezaplacené pokuty.", 2.5])
		return 0
	var paid := debts.pay_fines_cash(id)
	if paid > 0:
		play_sfx(id, "cash")
	var left := debts.total(id, Debts.FINE_KINDS)
	notify(id, "show_message", ["Na úřadě zaplaceno %s. Zbývá k úhradě: %s." % [Bazaar.kc(paid), Bazaar.kc(left)], 4.0])
	return paid


static func _thousands(n: int) -> String:
	var s := str(n)
	return s.substr(0, s.length() - 3) + " " + s.substr(s.length() - 3) if s.length() > 3 else s


func _on_passed_out(id: int) -> void:
	var pl: Player = players.get(id)
	if pl == null or _blackout.has(id):
		return
	emit_game_event(id, "passed_out", {})
	notify(id, "show_message", ["…okno…", 3.0])
	if pl.car:
		pl.car.input_locked = true
	elif pl.aircraft:
		if pl.aircraft.on_ground:
			exit_aircraft(id)          # M6.3: usne na zemi – vysadí se; ve vzduchu ho necháme letět
		else:
			pl.aircraft.throttle = 0.0 # opilý pilot omdlel za letu: stroj bez tahu klouže dolů
	else:
		pl.fall(4.0, "upadl jsi do bezvědomí")
	await blackout(id, 2.5)
	skip_time(id, 2.5, true)
	if pl.car:
		pl.car.input_locked = false
	notify(id, "show_message", ["Probral ses o 2,5 hodiny později… Kde to jsem?", 5.0])


func _on_knocked_out(reason: String, id: int) -> void:
	var pl: Player = players.get(id)
	if pl == null:
		return
	emit_game_event(id, "knocked_out", {"reason": reason})
	if pl.car:
		exit_car(id)
	elif pl.horse:
		dismount_horse(id)
	elif pl.aircraft:
		if pl.aircraft.on_ground:
			exit_aircraft(id)          # na zemi: vysadit; ve vzduchu stroj doletí / havaruje sám
	await blackout(id, 2.0)
	skip_time(id, 12.0, true)
	pl.body.heal_full()
	pl.body.health = 60.0
	pl.money = maxi(pl.money - 3000, 0)
	var home: Place = places["domov"]
	interior_clear(pl)
	pl.teleport(home.door + Vector3(0, 0.3, 0), pl.yaw, false)
	pl.fallen = 0.0
	pl.visual.pose = "stand"
	notify(id, "show_message", ["Probudil ses v nemocnici (%s).\nLéčení 3 000 Kč. Pustili tě domů." % reason, 8.0])


## Posun času (spánek, okno). Hráč `id` spí, ostatní hráči ten čas prožijí vzhůru.
## (V multiplayeru se čas posouvat nebude – viz GAME_DESIGN 6.5; řeší úkol 03+.)
func skip_time(id: int, hours: float, sleeping: bool) -> void:
	clock.skip_hours(hours)
	if debts:
		debts.advance_to(clock.jd())   # M4.2: dluhy dohnat po dnech (ne jedním skokem)
	for p in players.values():
		p.body.skip_hours(hours, sleeping and p.id == id)
	var pl: Player = players.get(id)
	if pl:
		pl.stamina = pl.body.stamina_max()


# ------------------------------------------------------------------ akce hráčů

## Akce z klávesnice hráče: car_enter (F), car_lights (L), car_wipers (N), car_horn (B),
## car_reset (R), whistle (G – hvízdnutí na koně), respawn (H), unstuck (U – vysvobození ze zaseknutí),
## equip_next (Q), equip_slot_1..5 (1–5),
## use_tool (levé tlačítko myši – spustí kontextovou akci, viz ActionRunner). Dalekohled (X, držet) řeší přímo Player.scope_on.
func player_action(id: int, action: String) -> void:
	var p: Player = players.get(id)
	if p == null:
		return
	# M6.1 drony: start z inventáře, fotka; při letu jen letové akce (F = přistát/návrat).
	if action.begins_with("drone_launch:"):
		drone_launch(id, action.get_slice(":", 1))
		return
	if action == "drone_photo":
		drone_photo(id)
		return
	if action == "pg_prepare":                  # M6.4: rozložit paramotor na louce (inventář → detail)
		pg_prepare(id)
		return
	if p.drone != null and p.drone.flying():
		if action == "car_enter":
			p.drone.request_land()
		return                              # ostatní akce při pilotování neplatí (E, nástroje, equip, respawn…)
	match action:
		"car_enter":
			if p.horse:
				if absf(p.horse.speed) < 1.5:
					dismount_horse(id)
				else:
					notify(id, "show_message", ["Nejdřív koně zastav (S).", 1.5])
				return
			if p.aircraft:             # M6.3: vystoupit jen na zemi a v klidu
				if p.aircraft.on_ground and p.aircraft.speed < 2.0:
					exit_aircraft(id)
				elif not p.aircraft.on_ground:
					notify(id, "show_message", ["Ve vzduchu nevystupuj – nejdřív přistaň.", 2.0])
				else:
					notify(id, "show_message", ["Nejdřív letoun zastav.", 1.5])
				return
			var h := nearest_mountable_horse(id)
			var hc := nearest_enterable_car(id) if p.car == null else null
			var ac := nearest_enterable_aircraft(id) if p.aircraft == null else null
			if ac and (hc == null or ac.global_position.distance_to(p.global_position) < hc.global_position.distance_to(p.global_position)) \
					and (h == null or ac.global_position.distance_to(p.global_position) < h.global_position.distance_to(p.global_position)):
				enter_aircraft(id, ac)
				return
			if h and (hc == null or h.global_position.distance_to(p.global_position) < hc.global_position.distance_to(p.global_position)):
				mount_horse(id, h)
				return
			if p.car:
				if absf(p.car.speed) < 2.0:
					exit_car(id)
				else:
					notify(id, "show_message", ["Za jízdy nevystupuj!", 1.5])
			else:
				var c := nearest_enterable_car(id)
				if c:
					enter_car(id, c)
		"car_lights":
			if p.car:
				p.car.toggle_lights()
		"car_wipers":
			if p.car and not p.car.two_wheeler:
				p.car.toggle_wipers()
		"car_horn":
			if p.car:
				p.car.honk()
		"car_reset":
			if p.car and (p.car.global_transform.basis.y.y < 0.6 or absf(p.car.speed) < 1.0):
				p.car.reset_upright()
		"whistle":
			if cargo and cargo.on_g(id):          # G: zvednout / položit / naložit náklad (M2.10; zvěř M2.9), jinak hvízdnutí na koně
				return
			_whistle(p)
		"equip_next":
			p.equip_next()
		"equip_slot_1", "equip_slot_2", "equip_slot_3", "equip_slot_4", "equip_slot_5":
			p.equip_slot(int(action.right(1)))
		"use_tool":
			if weapons and weapons.on_click(id):        # zbraň v ruce: luk natáhnout, kuši / pušku vystřelit (M2.8)
				return
			if fishing and fishing.on_click(id):       # nahozená udice: stáhnout / zaseknout (M2.7)
				return
			if vycep and vycep.on_click(id):           # výčepní u pípy: čepování držením LMB (M3.2)
				return
			if palenice and palenice.on_click(id):     # pomocník v pálenici: přiložit poleno pod kotel (M3.3)
				return
			var h := action_runner.hint(id) if action_runner else {}
			if not h.is_empty():
				action_runner.start(id, h["action"], h["aim"])
		"respawn":
			if p.horse:
				dismount_horse(id)
			if p.aircraft:
				if p.aircraft.on_ground:
					exit_aircraft(id)
				else:
					return             # ve vzduchu respawn nejde – doleť / dostaň se na zem
			if p.car == null:
				interior_clear(p)
				p.teleport(p.spawn_point, p.spawn_yaw)
		"unstuck":
			var msg := p.unstick()
			if msg != "":
				notify(id, "show_message", [msg, 3.0])


## Je mezi dvěma body volno (statická kolize vrstvy 1 – terén, budovy, stromy)?
func line_clear(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Tag nákladu, který je na hráči / jeho vozíku / nosiči vidět („zverina“, „drevo“, „material“), jinak „“ (M2.10; M4.6: hajný, policie).
func visible_cargo(id: int) -> String:
	return cargo.visible_tag(id) if cargo else ""


## Hvízdnutí na koně (G): kůň do Horse.WHISTLE_R bez jezdce přiklusá po zemi k hráči.
func _whistle(p: Player) -> void:
	if p.car or p.horse or p.fallen > 0.0 or p.busy or fauna == null:
		return
	play_sfx(p.id, "whistle", 1.35, -6.0)
	var h := fauna.horse_of(p.id)
	if h == null:
		return
	if h.rider != null:
		notify(p.id, "show_message", ["Na tvém koni už někdo sedí.", 2.0])
	elif h.call_to(p):
		notify(p.id, "show_message", ["Kůň zvedl hlavu a přichází k tobě.", 2.5])
	else:
		notify(p.id, "show_message", ["Kůň tě neslyší – je dál než %d m." % int(Horse.WHISTLE_R), 3.0])


## Nejbližší vlastní vozidlo hráče (auto do 4 m, kolo / motorka do 2,6 m), když na něm nikdo nesedí.
func nearest_enterable_car(id: int) -> Car:
	var pp: Vector3 = players[id].global_position
	var best: Car = null
	for v in traffic.vehicles_of(id):
		var reach: float = 4.0 if not v.two_wheeler else 2.6
		if v.driver_id == 0 and v.global_position.distance_to(pp) < reach and \
				(best == null or v.global_position.distance_to(pp) < best.global_position.distance_to(pp)):
			best = v
	return best


func enter_car(id: int, c: Car) -> void:
	var p: Player = players[id]
	if not police.license_ok(p):
		notify(id, "show_message", ["Máš zákaz řízení ještě %d h. Když tě chytí, bude hůř…" % int(
			(p.license_suspended_until - clock.minutes) / 60.0), 3.0])
	if p.busy:
		return
	var lc := license_check(id, c)            # M4.1: vozidlo vyžaduje skupinu řidičáku (jde to, ale je to přestupek)
	if not lc["ok"]:
		notify(id, "show_message", ["Na tohle nemáš řidičák (skupina %s, %s)." % [lc["group"], lc["reason"]], 4.0])
	p.enter_car(c)
	_auto_start[id] = p.global_position       # M4.1: nástup – případná výcviková jízda autoškoly
	play_sfx(id, "door")
	if c.model.kind == "bike":
		notify(id, "show_message", ["%s – W šlapat, S brzda (stojíš: couvání), A/D řízení, B zvonek, L dynamo, F sesednout" % c.model.spec["name"], 4.0])
	elif c.model.kind == "moto":
		notify(id, "show_message", ["%s – W plyn, S brzda, A/D řízení, Mezerník zadní brzda, B klakson, F sesednout" % c.model.spec["name"], 4.0])
	elif c.model.spec.has("name"):
		notify(id, "show_message", ["%s – W plyn, S brzda/couvání, A/D řízení, Mezerník ruční brzda, F vystoupit" % c.model.spec["name"], 4.0])
	if p.body.promile() >= 0.01:
		notify(id, "police_banner", ["Pozor: řídíš s %s ‰! V ČR platí nulová tolerance." % ("%.2f" % p.body.promile()).replace(".", ","), 5.0])
	if clock.is_night() and not c.lights_on:
		c.toggle_lights()
	emit_game_event(id, "entered_car", {"car": c})


## Nejbližší kůň do 3 m, na kterém nikdo nesedí. Bere VŠECHNY koně ve `fauna.horses` (i koně jiného hráče
## bez jezdce – cizí kůň jde půjčit); v MP se vlastnictví (`Horse.owner_id`) k nasednutí nehlídá.
## Jezdec převezme autoritu nad pohybem koně (`Horse.authority`, viz Horse).
func nearest_mountable_horse(id: int) -> Horse:
	if fauna == null:
		return null
	var p: Player = players[id]
	if p.car or p.horse or p.fallen > 0.0 or p.busy:
		return null
	var best: Horse = null
	var bd := 3.0
	for h in fauna.horses.values():
		var d: float = h.global_position.distance_to(p.global_position)
		if h.rider == null and d < bd:
			bd = d
			best = h
	return best


func mount_horse(id: int, h: Horse) -> void:
	var p: Player = players[id]
	p.mount_horse(h)
	notify(id, "show_message", ["Kůň – W jet, Shift pobídnout (krok → klus → cval → trysk), S zpomalit / couvat, A/D otěže, Mezerník skok, F sesednout", 5.0])
	if p.body.promile() >= 0.3:
		notify(id, "police_banner", ["I jezdec na koni je účastník provozu – s %s ‰ opatrně!" % ("%.2f" % p.body.promile()).replace(".", ","), 4.0])
	emit_game_event(id, "mounted_horse", {"horse": h})


func dismount_horse(id: int) -> void:
	var p: Player = players[id]
	if p.horse == null:
		return
	p.dismount_horse()
	emit_game_event(id, "dismounted_horse", {})


func exit_car(id: int) -> void:
	var p: Player = players[id]
	var c: Car = p.car
	var out := p.exit_car()
	play_sfx(id, "door")
	emit_game_event(id, "exited_car", {})
	_auto_jizda_end(id, c, out)


# ------------------------------------------------------------------ letouny (M6.3)

## Postaví letoun `model_id` (Aircraft.SPECS) na volném místě u hráče; patří mu (F = nastoupit).
func spawn_aircraft(id: int, model_id: String) -> void:
	var p: Player = players.get(id)
	if p == null or not Aircraft.SPECS.has(model_id):
		return
	var fwd := Vector3(-sin(p.yaw), 0.0, -cos(p.yaw))
	var pos := p.global_position + fwd * 7.0
	pos.y = terrain.height_at(pos.x, pos.z) + float(Aircraft.SPECS[model_id]["gear_h"])
	var space := get_world_3d().direct_space_state
	var sh := BoxShape3D.new()
	sh.size = Vector3(3.0, 2.4, 4.0)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sh
	q.collision_mask = 1 | 8
	q.transform = Transform3D(Basis(Vector3.UP, p.yaw), pos + Vector3(0, 1.2, 0))
	if not space.intersect_shape(q, 1).is_empty():
		notify(id, "show_message", ["Není tu místo na letoun – jdi na volnou louku.", 3.0])
		return
	var a := Aircraft.make(model_id)                # M6.4: továrna (paramotor = Paramotor)
	a.name = "Letoun_%d_%d" % [id, randi() % 10000]
	add_child(a)
	a.setup(self, id, model_id)
	a.park(pos, p.yaw)
	aircrafts.get_or_add(id, []).append(a)
	notify(id, "show_message", ["Přistaven: %s – nastup klávesou F." % a.spec.get("name", model_id), 3.5])
	emit_game_event(id, "aircraft_spawned", {"model": model_id})


## Nejbližší letoun hráče do 5 m bez pilota (jen na zemi – ve vzduchu se nenastupuje).
func nearest_enterable_aircraft(id: int) -> Aircraft:
	var p: Player = players.get(id)
	if p == null:
		return null
	var best: Aircraft = null
	for a in aircrafts.get(id, []):
		if not is_instance_valid(a) or a.pilot != null or not a.on_ground or a.dmg >= 100.0:
			continue
		var d: float = a.global_position.distance_to(p.global_position)
		if d < 5.0 and (best == null or d < best.global_position.distance_to(p.global_position)):
			best = a
	return best


func enter_aircraft(id: int, a: Aircraft) -> void:
	var p: Player = players[id]
	if p.busy or p.fallen > 0.0 or p.controls_locked:
		return
	if a.dmg >= 100.0:
		notify(id, "show_message", ["Stroj je zničený havárií – tohle už neletí.", 3.0])
		return
	p.enter_aircraft(a)
	play_sfx(id, "door")
	if a is Paramotor:
		notify(id, "show_message", ["%s – navlékáš nosiče: čelem PROTI VĚTRU rozběh (W) nahodí křídlo, " % a.spec.get("name", a.model)
			+ "pak plyn (Shift). Ve vzduchu A/D brzdy, S obě, Mezerník trimry, Ctrl uši.", 7.0])
	elif a is Trike:
		notify(id, "show_message", [(a as Trike).controls_hint(), 8.0])
	else:
		notify(id, "show_message", ["%s – W plyn, A/D překlápění, Mezerník zatáhnout / na zemi brzda, " % a.spec.get("name", a.model)
			+ "Ctrl přiklonit, V kamera, F vystoupit (na zemi)", 6.0])
	if p.body.promile() >= 0.01:
		notify(id, "police_banner", ["Pilotuješ s %s ‰! Pro piloty platí nulová tolerance (49/1997 Sb.)." % (
			"%.2f" % p.body.promile()).replace(".", ","), 5.0])
	emit_game_event(id, "entered_aircraft", {"aircraft": a})


func exit_aircraft(id: int) -> void:
	var p: Player = players.get(id)
	if p == null or p.aircraft == null:
		return
	p.exit_aircraft()
	play_sfx(id, "door")
	emit_game_event(id, "exited_aircraft", {})


## Letouny hráče (živé uzly; prázdné = žádný).
func aircrafts_of(id: int) -> Array:
	var out: Array = []
	for a in aircrafts.get(id, []):
		if is_instance_valid(a):
			out.append(a)
	return out


## Uložení: seznam {model, pos, yaw, fuel, dmg} + index stroje, ve kterém pilot sedí (nebo -1).
func aircrafts_to_dict(id: int) -> Dictionary:
	var list := []
	var seat := -1
	var p: Player = players.get(id)
	for a in aircrafts_of(id):
		if p and p.aircraft == a:
			seat = list.size()
		list.append(a.save_dict())
	return {"list": list, "seat": seat}


## Načtení (starý save bez klíče = žádné letouny). Předtím zruší současné uzly.
func aircrafts_from_dict(id: int, d: Dictionary) -> void:
	for a in aircrafts.get(id, []):
		if is_instance_valid(a):
			if a.pilot:
				var pl: Player = a.pilot
				a.clear_pilot()
				pl.aircraft = null
			a.queue_free()
	aircrafts[id] = []
	for rec in d.get("list", []):
		var m := String(rec.get("model", ""))
		if not Aircraft.SPECS.has(m):
			continue
		var pos: Array = rec.get("pos", [0, 0, 0])
		var a := Aircraft.make(m)                     # M6.4: továrna (paramotor = Paramotor)
		a.name = "Letoun_%d_%d" % [id, randi() % 10000]
		add_child(a)
		a.setup(self, id, m)
		if a is Paramotor:
			a.pg_item = String(rec.get("pg_item", "paramotor"))
		a.park(Vector3(float(pos[0]), float(pos[1]), float(pos[2])), float(rec.get("yaw", 0.0)))
		a.fuel_l = clampf(float(rec.get("fuel", float(a.spec["tank_l"]))), 0.0, float(a.spec["tank_l"]))
		a.dmg = float(rec.get("dmg", 0.0))
		aircrafts[id].append(a)
	var seat := int(d.get("seat", -1))
	var p: Player = players.get(id)
	if seat >= 0 and seat < aircrafts[id].size() and p != null:
		enter_aircraft(id, aircrafts[id][seat])


# ------------------------------------------------------------------ paramotor (M6.4)

const PG_ITEM_IDS := ["paramotor", "paramotor_ojety"]   # položky inventáře = sbalený stroj (25 kg)
const PG_PREP_DIST := 3.0                                # jak daleko před hráčem se stroj rozloží
const PG_PREP_SLOPE := 0.176                             # tan(10°) – max. sklon louky pro start
const PG_PREP_TREES_R := 30.0                            # kontrolovaný pás před startem (±)
const PG_PREP_TREES_D := 25.0                            # střed pásu před hráčem (→ zásah ~50 m)
const PG_VILLAGE_R := 350.0                              # „obec“ = do této vzdálenosti od dveří místa
const PG_NOISE_R := 800.0                                # svědek hluku motoru (vodorovně)
const PG_SCHOOL_KC := 35000                              # létací škola (teorie + 5 výcvikových letů)
const PG_TRAIN_FLIGHTS := 5                              # povinné výcvikové vzlety s instruktorem
const PG_REG_KC := 500                                   # registrace stroje u ÚVL
const PG_INSURANCE_KC := 1200                            # pojištění odpovědnosti (rok, zjednodušeně)


## Který paramotor nese hráč v batohu (nový před ojetým); "" = žádný.
func pg_carried_item(p: Player) -> String:
	for it in PG_ITEM_IDS:
		if p.item_count(it) > 0:
			return it
	return ""


## Podmínky rozložení (louka, sklon <10°, bez stromů 50 m před sebou, venku) → {ok, why}.
func pg_prepare_check(id: int) -> Dictionary:
	var p: Player = players.get(id)
	if p == null:
		return {"ok": false, "why": "?"}
	if pg_carried_item(p) == "":
		return {"ok": false, "why": "paramotor nemáš v batohu"}
	if p.inside != "":
		return {"ok": false, "why": "uvnitř budovy křídlo nerozložíš"}
	if p.car or p.horse or p.aircraft or p.busy or p.fallen > 0.0:
		return {"ok": false, "why": "teď to nejde (vozidlo / akce / pád)"}
	var fwd := Vector3(-sin(p.yaw), 0.0, -cos(p.yaw))
	var pos := p.global_position + fwd * PG_PREP_DIST
	var side := Vector3(-fwd.z, 0.0, fwd.x)
	# sklon: nejvyšší rozdíl výšek v okolí musí být pod tan(10°)
	var h0 := terrain.height_at(pos.x, pos.z)
	for o in [fwd * 4.0, -fwd * 4.0, side * 4.0, -side * 4.0]:
		if absf(terrain.height_at(pos.x + o.x, pos.z + o.z) - h0) / 4.0 > PG_PREP_SLOPE:
			return {"ok": false, "why": "příliš velký sklon – najdi rovnou louku (< 10°)"}
	# stromy v dráze startu (~50 m před sebou)
	if fauna and not fauna.trees_near(pos + fwd * PG_PREP_TREES_D, PG_PREP_TREES_R, 8).is_empty():
		return {"ok": false, "why": "stromy v dráze startu – potřebuješ ~50 m volno před sebou"}
	return {"ok": true, "why": ""}


## „Připravit paramotor“ (inventář → detail → Připravit k letu): sbalený stroj z batohu
## se položí před hráče s křídlem rozloženým za nosiči; F = navléct nosiče.
func pg_prepare(id: int) -> void:
	var chk := pg_prepare_check(id)
	var p: Player = players.get(id)
	if not bool(chk["ok"]):
		notify(id, "show_message", ["Nejde rozložit: %s" % chk["why"], 3.5])
		return
	var item := pg_carried_item(p)
	var fwd := Vector3(-sin(p.yaw), 0.0, -cos(p.yaw))
	var pos := p.global_position + fwd * PG_PREP_DIST
	pos.y = terrain.height_at(pos.x, pos.z) + float(Aircraft.SPECS["paramotor"]["gear_h"])
	var a := Aircraft.make("paramotor") as Paramotor
	a.name = "Paramotor_%d_%d" % [id, randi() % 10000]
	add_child(a)
	a.setup(self, id, "paramotor")
	a.pg_item = item
	a.park(pos, p.yaw)
	p.remove_item(item)
	aircrafts.get_or_add(id, []).append(a)
	play_sfx(id, "pickup")
	notify(id, "show_message", ["Křídlo je rozložené za nosiči. Navlékni je (F), otoč se čelem proti větru a rozběhni (W).", 5.5])
	emit_game_event(id, "pg_prepared", {})


## Sbalení křídla po přistání zpět do batohu (E u ležícího stroje, ~půlminutová práce zjednodušená).
func paramotor_pack(id: int, a: Paramotor) -> void:
	var p: Player = players.get(id)
	if p == null or a == null or not is_instance_valid(a) or a.pilot != null or not a.on_ground:
		return
	if a.global_position.distance_to(p.global_position) > 4.0:
		return
	for pid2 in aircrafts:
		(aircrafts[pid2] as Array).erase(a)
	p.add_item(a.pg_item)
	a.queue_free()
	play_sfx(id, "pickup")
	notify(id, "show_message", ["Křídlo složené a zabalené – paramotor je zpátky v batohu (25 kg).", 3.5])
	emit_game_event(id, "pg_packed", {})


## Interakce E: „Složit křídlo“ u vlastního ležícího paramotoru (rozloženého / po přistání).
func paramotor_interactables(pid: int) -> Array:
	var p: Player = players.get(pid)
	var out := []
	if p == null or p.inside != "":
		return out
	for a in aircrafts_of(pid):
		if a is Paramotor and a.pilot == null and a.on_ground and a.dmg < 100.0:
			var aa: Paramotor = a
			out.append({"pos": a.global_position + Vector3(0, 0.5, 0), "r": 3.5, "kind": "custom",
				"text": "Složit křídlo a sbalit paramotor",
				"action": func(id2: int): paramotor_pack(id2, aa)})
	return out


## Svědek hluku paramotoru: vesničané do ~800 m, obsluhy do ~500 m, hlídka do ~800 m, hráči ~500 m.
## (Motor slyšíš daleko – vzor `drone_witnessed` s větším dosahem.)
func pg_noise_witnessed(pos: Vector3) -> bool:
	var p2 := Vector2(pos.x, pos.z)
	if bots_root:
		for v in bots_root.get_children():
			if v is Villager and Vector2(v.global_position.x, v.global_position.z).distance_to(p2) < PG_NOISE_R:
				return true
	for k in places:
		var pl: Place = places[k]
		if pl.keeper != null and is_instance_valid(pl.keeper) \
				and Vector2(pl.keeper.global_position.x, pl.keeper.global_position.z).distance_to(p2) < 500.0:
			return true
	if police and police.patrol != null and is_instance_valid(police.patrol) \
			and Vector2(police.patrol.global_position.x, police.patrol.global_position.z).distance_to(p2) < PG_NOISE_R:
		return true
	for pid in players:
		var pl2: Player = players[pid]
		if pl2 and pl2.aircraft == null \
				and Vector2(player_world_pos(pl2).x, player_world_pos(pl2).z).distance_to(p2) < 500.0:
			return true
	return false


## „Nad obcí“ ~ horizontální dosah jakéhokoli místa (dveří Place) – zjednodušení zástavby.
func pg_over_village(pos: Vector3) -> bool:
	var p2 := Vector2(pos.x, pos.z)
	for k in places:
		var d: Vector3 = (places[k] as Place).door
		if Vector2(d.x, d.z).distance_to(p2) < PG_VILLAGE_R:
			return true
	return false


# ---- létací škola, registrace a pojištění (účet vede Computer.pg_school, doklady Permits) ----

## Zápis do létací školy: 35 000 Kč z účtu. Výuka = teorie (eTest „paramotor“) + 5 výcvikových vzletů.
func pg_enroll(id: int) -> String:
	if computer == null:
		return "Síť je nedostupná."
	var s: Dictionary = computer.pg_school(id)
	if has_permit(id, "pilot_pg_motor", Vector3.ZERO):
		return "Pilotní průkaz paramotoru už máš vydaný."
	if bool(s.get("zaplaceno", false)):
		return "Výcvik už máš zaplacený – slož teorii (eTest „paramotor“) a naleť 5 výcvikových vzletů."
	if not computer.withdraw_bank(id, PG_SCHOOL_KC, "Létací škola – výcvik paramotor"):
		return "Na účtu nemáš %s. Vlož hotovost v bankomatu." % Bazaar.kc(PG_SCHOOL_KC)
	s["zaplaceno"] = true
	emit_game_event(id, "pg_school_enrolled", {})
	return "Zaplaceno %s – výcvik běží. Teorie: eTest „paramotor“ (tady na PC). " % Bazaar.kc(PG_SCHOOL_KC) + \
		"Praxe: každý vzlet s rozloženým paramotorem počítá instruktor rádiem (%d×)." % PG_TRAIN_FLIGHTS


## Složená teorie (volá `Computer.record_test` při úspěšném eTestu „paramotor“).
func pg_theory_passed(id: int) -> void:
	if computer:
		(computer.pg_school(id) as Dictionary)["teorie"] = true
	_pg_try_grant(id)


## Vzlet paramotoru – počítá se jako výcvikový let, když je zaplacená škola (instruktor „rádiem“).
func pg_training_takeoff(id: int) -> void:
	if computer == null:
		return
	var s: Dictionary = computer.pg_school(id)
	if not bool(s.get("zaplaceno", false)) or has_permit(id, "pilot_pg_motor", Vector3.ZERO):
		return
	var lety := int(s.get("lety", 0))
	if lety >= PG_TRAIN_FLIGHTS:
		return
	lety += 1
	s["lety"] = lety
	var radio := ["Instruktor (rádio): „Pěkný rozběh, křídlo drží! Drž rychlost a brzdy povolené.“",
		"Instruktor (rádio): „Let %d/%d – hlídej vítr a výšku nad obcí (min. 150 m).“" % [lety, PG_TRAIN_FLIGHTS],
		"Instruktor (rádio): „Kroužit v termice umíš – se staženým plynem zkus stoupat.“",
		"Instruktor (rádio): „Přistávej proti větru, ve výšce ~1 m obě brzdy naplno.“",
		"Instruktor (rádio): „Poslední výcvikový let – po přistání se stav u školy.“"]
	notify(id, "show_message", [radio[mini(lety - 1, radio.size() - 1)], 5.0])
	_pg_try_grant(id)


## Splněné podmínky → vydání průkazu `pilot_pg_motor` (smyšlené evidenční číslo).
func _pg_try_grant(id: int) -> void:
	if computer == null or permits == null:
		return
	var s: Dictionary = computer.pg_school(id)
	if not bool(s.get("zaplaceno", false)) or not bool(s.get("teorie", false)) \
			or int(s.get("lety", 0)) < PG_TRAIN_FLIGHTS:
		return
	if has_permit(id, "pilot_pg_motor", Vector3.ZERO):
		return
	var no := "PLA-Q%04d" % randi_range(0, 9999)
	permits.grant(id, "pilot_pg_motor", no)
	send_mail(id, "Létací škola – ÚVL", "Pilotní průkaz paramotoru",
		"Gratulujeme!\nSložil jsi teorii a odletěl %d výcvikových letů.\nVydán průkaz: %s\nNezapomeň stroj registrovat a pojistit (Letectví – ÚVL)." % [
		PG_TRAIN_FLIGHTS, no])
	emit_game_event(id, "pg_license_granted", {"no": no})
	notify(id, "popup", ["Pilotní průkaz paramotoru vydán (%s)!" % no, 6.0])


## Registrace stroje (poznávací značka na křídle – smyšlená): 500 Kč z účtu.
func pg_register(id: int) -> String:
	if computer == null or permits == null:
		return "Síť je nedostupná."
	if has_permit(id, "pg_registrace", Vector3.ZERO):
		return "Stroj už je registrovaný: %s." % permits.number(id, "pg_registrace")
	if not computer.withdraw_bank(id, PG_REG_KC, "ÚVL – registrace paramotoru"):
		return "Na účtu nemáš %s. Vlož hotovost v bankomatu." % Bazaar.kc(PG_REG_KC)
	var no := "OK-Q%04d" % randi_range(0, 9999)
	permits.grant(id, "pg_registrace", no)
	emit_game_event(id, "pg_registered", {"no": no})
	return "Registrováno – poznávací značka %s se vyznačí na křídle." % no


## Pojištění odpovědnosti (roční, zjednodušené – bez doby trvání): 1 200 Kč z účtu.
func pg_insure(id: int) -> String:
	if computer == null or permits == null:
		return "Síť je nedostupná."
	if has_permit(id, "pg_pojisteni", Vector3.ZERO):
		return "Pojištění je aktivní (%s)." % permits.number(id, "pg_pojisteni")
	if not computer.withdraw_bank(id, PG_INSURANCE_KC, "Pojištění paramotoru – roční"):
		return "Na účtu nemáš %s. Vlož hotovost v bankomatu." % Bazaar.kc(PG_INSURANCE_KC)
	permits.grant(id, "pg_pojisteni", "POJ-%d" % (world_day_serial()))
	emit_game_event(id, "pg_insured", {})
	return "Pojištěno – odpovědnost z provozu paramotoru na rok."


# ------------------------------------------------------------------ motorové rogalo / UL (M6.5)

const UL_SCHOOL_KC := 75000                              # UL létací škola (eTest + 10 letů s instruktorem)
const UL_TRAIN_FLIGHTS := 10                             # povinné výcvikové vzlety triku
const UL_REG_KC := 1500                                  # registrace UL stroje u ÚVL
const UL_INSURANCE_KC := 3000                            # pojištění odpovědnosti UL (rok, zjednodušeně)
const UL_TRIKE_KC := 350000                              # ojeté rogalo z inzerátu u hangáru
const UL_PAX_FRIEND := 60.0                              # min. přátelství pro „vyhlídkový let“
const UL_PAX_R := 14.0                                   # m – jak blízko musí být vesničan u triku


## Stav UL výcviku hráče (stejná struktura jako `Computer.pg_school`).
func ul_school(id: int) -> Dictionary:
	return computer.ul_school(id) if computer else {}


## Zápis do UL létací školy: 75 000 Kč z účtu (teorie eTest „ul“ + 10 letů s instruktorem).
func ul_enroll(id: int) -> String:
	if computer == null:
		return "Síť je nedostupná."
	var s: Dictionary = computer.ul_school(id)
	if has_permit(id, "pilot_ul", Vector3.ZERO):
		return "Pilotní průkaz UL už máš vydaný."
	if bool(s.get("zaplaceno", false)):
		return "Výcvik už máš zaplacený – slož teorii (eTest „ultralehké“) a naleť %d letů s instruktorem." % UL_TRAIN_FLIGHTS
	if not computer.withdraw_bank(id, UL_SCHOOL_KC, "Létací škola – výcvik UL (rogalo)"):
		return "Na účtu nemáš %s. Vlož hotovost v bankomatu." % Bazaar.kc(UL_SCHOOL_KC)
	s["zaplaceno"] = true
	emit_game_event(id, "ul_school_enrolled", {})
	return "Zaplaceno %s – výcvik UL běží. Teorie: eTest „ultralehké“ (tady na PC). " % Bazaar.kc(UL_SCHOOL_KC) + \
		"Praxe: každý vzlet triku počítá instruktor z letiště rádiem (%d×)." % UL_TRAIN_FLIGHTS


## Složená teorie (volá `Computer.record_test` při úspěšném eTestu „ultralehké“).
func ul_theory_passed(id: int) -> void:
	if computer:
		(computer.ul_school(id) as Dictionary)["teorie"] = true
	_ul_try_grant(id)


## Vzlet triku – počítá se jako výcvikový let, když je zaplacená škola (instruktor „rádiem“).
func ul_training_takeoff(id: int) -> void:
	if computer == null:
		return
	var s: Dictionary = computer.ul_school(id)
	if not bool(s.get("zaplaceno", false)) or has_permit(id, "pilot_ul", Vector3.ZERO):
		return
	var lety := int(s.get("lety", 0))
	if lety >= UL_TRAIN_FLIGHTS:
		return
	lety += 1
	s["lety"] = lety
	var radio := ["Instruktor (rádio): „Pěkný rozjezd, drž dráhu příďovým kolem a pak lehce od sebe.“",
		"Instruktor (rádio): „Let %d/%d – pamatuj: hrazda od sebe = nahoru a zpomalit.“" % [lety, UL_TRAIN_FLIGHTS],
		"Instruktor (rádio): „Zatáčky hrazdou jsou obráceně – hrazdu doleva = půjdeš doprava.“",
		"Instruktor (rádio): „Přistávej proti větru ~65 km/h a dosedni na hlavní kola.“",
		"Instruktor (rádio): „Za dne a mimo mraky – jinak přestupek. A nízko nad obcí nelítáme!“"]
	notify(id, "show_message", [radio[mini(lety - 1, radio.size() - 1)], 5.0])
	_ul_try_grant(id)


## Splněné podmínky → vydání průkazu `pilot_ul` (smyšlené evidenční číslo).
func _ul_try_grant(id: int) -> void:
	if computer == null or permits == null:
		return
	var s: Dictionary = computer.ul_school(id)
	if not bool(s.get("zaplaceno", false)) or not bool(s.get("teorie", false)) \
			or int(s.get("lety", 0)) < UL_TRAIN_FLIGHTS:
		return
	if has_permit(id, "pilot_ul", Vector3.ZERO):
		return
	var no := "ULA-Q%04d" % randi_range(0, 9999)
	permits.grant(id, "pilot_ul", no)
	send_mail(id, "Létací škola – ÚVL", "Pilotní průkaz UL (rogalo)",
		"Gratulujeme!\nSložil jsi teorii a odletěl %d výcvikových letů na rogalu.\nVydán průkaz: %s\nNezapomeň stroj registrovat a pojistit (Letectví – ÚVL)." % [
		UL_TRAIN_FLIGHTS, no])
	emit_game_event(id, "ul_license_granted", {"no": no})
	notify(id, "popup", ["Pilotní průkaz UL vydán (%s)!" % no, 6.0])


## Registrace UL stroje (poznávací značka – smyšlená): 1 500 Kč z účtu.
func ul_register(id: int) -> String:
	if computer == null or permits == null:
		return "Síť je nedostupná."
	if has_permit(id, "ul_registrace", Vector3.ZERO):
		return "Stroj už je registrovaný: %s." % permits.number(id, "ul_registrace")
	if not computer.withdraw_bank(id, UL_REG_KC, "ÚVL – registrace UL stroje"):
		return "Na účtu nemáš %s. Vlož hotovost v bankomatu." % Bazaar.kc(UL_REG_KC)
	var no := "OK-Q%04d" % randi_range(0, 9999)
	permits.grant(id, "ul_registrace", no)
	emit_game_event(id, "ul_registered", {"no": no})
	return "Registrováno – poznávací značka %s se vyznačí na vozíku." % no


## Pojištění odpovědnosti UL (roční, zjednodušené): 3 000 Kč z účtu.
func ul_insure(id: int) -> String:
	if computer == null or permits == null:
		return "Síť je nedostupná."
	if has_permit(id, "ul_pojisteni", Vector3.ZERO):
		return "Pojištění je aktivní (%s)." % permits.number(id, "ul_pojisteni")
	if not computer.withdraw_bank(id, UL_INSURANCE_KC, "Pojištění UL – roční"):
		return "Na účtu nemáš %s. Vlož hotovost v bankomatu." % Bazaar.kc(UL_INSURANCE_KC)
	permits.grant(id, "ul_pojisteni", "POJ-%d" % world_day_serial())
	emit_game_event(id, "ul_insured", {})
	return "Pojištěno – odpovědnost z provozu UL na rok."


## Koupě ojetého triku z inzerátu u hangáru (hotovost, stroj se postaví před hangár).
func ul_buy_trike(id: int) -> void:
	var p: Player = players.get(id)
	if p == null or airfield == null:
		return
	if p.money < UL_TRIKE_KC:
		notify(id, "show_message", ["Ojeté rogalo stojí %s v hotovosti – tolik u sebe nemáš." % Bazaar.kc(UL_TRIKE_KC), 4.0])
		return
	p.money -= UL_TRIKE_KC
	var at: Array = airfield.trike_spawn()
	var a := Aircraft.make("trike")
	a.name = "Trike_%d_%d" % [id, randi() % 10000]
	add_child(a)
	a.setup(self, id, "trike")
	a.dmg = randf_range(3.0, 15.0)                                # ojetý – drobné opotřebení
	a.park((at[0] as Vector3) + Vector3(0, float(a.spec["gear_h"]), 0), float(at[1]))
	aircrafts.get_or_add(id, []).append(a)
	play_sfx(id, "cash")
	notify(id, "show_message", ["Koupeno: %s za %s – stojí před hangárem. Nastup F (průkaz + registrace na PC → Letectví)." % [
		a.spec.get("name", "rogalo"), Bazaar.kc(UL_TRIKE_KC)], 6.0])
	emit_game_event(id, "trike_bought", {"kc": UL_TRIKE_KC})


## Interakce u triku: nastoupení spolujezdce (vesničan s přátelstvím ≥ 60 v dosahu)
## a jeho vysazení po pojezdu/letu. Vrací položky pro `interactables`.
func trike_interactables(id: int) -> Array:
	var p: Player = players.get(id)
	var out := []
	if p == null or p.inside != "":
		return out
	for a in aircrafts_of(id):
		var t := a as Trike
		if t == null or not t.on_ground or t.speed > 2.0 or t.dmg >= 100.0:
			continue
		if t.global_position.distance_to(p.global_position) > 20.0:
			continue
		if t.passenger() != null:
			var tt := t
			out.append({"pos": t.global_position + Vector3(0, 1.0, 0), "r": 8.0, "kind": "custom",
				"text": "Vysadit spolujezdce (%s)" % t.passenger().persona.display_name(),
				"action": func(_id: int): tt._pax_off()})
			continue
		# nejbližší ochotný vesničan u stroje (přátelství ≥ 60)
		var best: Villager = null
		var bd := INF
		for v in bots_root.get_children():
			if not (v is Villager) or v.persona == null:
				continue
			if v.persona.get_friendship(id) < UL_PAX_FRIEND:
				continue
			var dd: float = v.global_position.distance_to(t.global_position)
			if dd < UL_PAX_R and dd < bd:
				bd = dd
				best = v
		if best != null:
			var vv := best
			var tt2 := t
			out.append({"pos": best.global_position + Vector3(0, 1.2, 0), "r": 3.0, "kind": "custom",
				"text": "Vyvézt na vyhlídkový let: %s" % best.persona.display_name(),
				"action": func(_id: int): tt2.board_passenger(vv)})
	return out


## Pomocné smyšlené číslo dokladu (den + náhoda).
func world_day_serial() -> int:
	return (clock.jd() % 100) * 100 + randi_range(0, 99) if clock else randi_range(0, 9999)


## Co je u hráče k interakci (E): místa, děda, Pepa, vesničané, policista.
func interactables(id: int) -> Array:
	var p: Player = players[id]
	var out := []
	for k in places:
		var pl: Place = places[k]
		out.append({"pos": pl.door, "r": 3.2, "kind": "place", "key": k, "text": pl.data["name"]})
	if p.inside == "":
		var hd := home_door()
		if hd != Vector3.INF and hd.distance_to(places["domov"].door) > 2.0:
			out.append({"pos": hd, "r": 2.4, "kind": "place", "key": "domov", "text": "Vchod domů"})
		if interior_streamer:
			out.append_array(interior_streamer.door_interactables(id))   # M1.8: dveře ostatních budov
	elif interiors.has(p.inside):
		out.append_array(interiors[p.inside].interactables())
	out.append({"pos": npcs["deda"].global_position, "r": 2.6, "kind": "place", "key": "deda", "text": "Děda Vomáčka"})
	if npcs.has("pepa"):
		out.append({"pos": npcs["pepa"].global_position, "r": 2.6, "kind": "place", "key": "hospoda", "text": "Pepa (štamgast)"})
	for v in bots_root.get_children():
		if v is Villager and v.global_position.distance_squared_to(p.global_position) < 9.0:
			out.append({"pos": v.global_position, "r": 2.4, "kind": "favor", "node": v,
				"text": "%s (drby)   [E] promluvit, prosby, dárek" % v.persona.display_name()})
	for s in sleep_spots:
		out.append({"pos": s.global_position, "r": 3.0, "kind": "sleep", "key": s.kind, "node": s, "text": "Nocleh: " + s.title()})
	if radio:
		out.append({"pos": radio.global_position, "r": 1.8, "kind": "radio", "text": "Rádio – %s" % radio.describe()})
	if police.checkpoint_cop and is_instance_valid(police.checkpoint_cop):
		out.append({"pos": police.checkpoint_cop.global_position, "r": 2.5, "kind": "cop", "text": "Policista"})
	if hunter:
		out.append_array(hunter.interactables(id))
	if paddock:
		out.append_array(paddock.interactables(id))
	if bazaar:
		out.append_array(bazaar.interactables(id))
	if fire_mgr:
		out.append_array(fire_mgr.interactables(id))
	if garden:
		out.append_array(garden.interactables(id))
	if farm:
		out.append_array(farm.interactables(id))
	if weapons:
		out.append_array(weapons.interactables(id))     # sebrání šípů, skóre na střelnici (M2.8)
	if hunting:
		out.append_array(hunting.interactables(id))     # ulovená zvěř (vyvrhnout / zpracovat / nést), překupník (M2.9)
	if cargo:
		out.append_array(cargo.interactables(id))       # ruční vozík, vyložení z auta (M2.10)
	if computer:
		out.append_array(computer.interactables(id))    # bankomaty, balíky z e-shopu u dveří (M3.4)
	out.append_array(drone_interactables(id))          # M6.1: sebrání zaparkovaného / rozbitého dronu
	out.append_array(paramotor_interactables(id))      # M6.4: složení křídla paramotoru
	if airfield:
		out.append_array(airfield.interactables(id))   # M6.5: inzerát na ojeté rogalo u hangáru
	out.append_array(trike_interactables(id))          # M6.5: vyhlídkový let / vysazení spolujezdce
	return out


func find_interact(id: int) -> Dictionary:
	var p: Player = players[id]
	if p.car or p.aircraft or p.fallen > 0.0 or (p.drone != null and p.drone.flying()):
		return {}
	var best := {}
	var bd := INF
	for it in interactables(id):
		var d: float = (it["pos"] as Vector3).distance_to(p.global_position)
		if d < float(it["r"]) and d < bd:
			bd = d
			best = it
	return best


## Rozhovor s vesničanem / policistou (místa otevírají nabídku u klienta).
func talk(id: int, it: Dictionary) -> void:
	match it["kind"]:
		"villager":
			var t: String = it["node"].talk()
			if t.contains("policajti"):
				police.checkpoint_seen[id] = true
		"cop":
			var p: float = players[id].body.promile()
			police.checkpoint_cop.say("Dobrý večer. Pěšky můžete, jen opatrně." if p > 0.2 else "Dobrý večer, šťastnou cestu.")


# ------------------------------------------------------------------ rozhovory (T – hráč něco řekne na ulici)

const DIRS := ["na sever", "na severovýchod", "na východ", "na jihovýchod", "na jih", "na jihozápad", "na západ",
	"na severozápad"]


## Světová strana z bodu `from` k bodu `to` („na jihovýchod“).
func bearing_text(from: Vector3, to: Vector3) -> String:
	var d := to - from
	var geo := fposmod(float(meta.get("north_angle_deg", 78.37)) - rad_to_deg(atan2(-d.x, -d.z)), 360.0)
	return DIRS[int(round(geo / 45.0)) % 8]


## Všechny postavy s osobností: klíč (pro uložení) → Persona. Vesničané "v<i>", obsluha a děda "npc:<klíč>",
## štamgasti "reg:<místo>:<i>".
func personas() -> Dictionary:
	var out := {}
	var i := 0
	for v in bots_root.get_children():
		if v is Villager:
			if v in _extra_villagers:
				continue            # A4-06: víkendoví hosté se neukládají (přibývají a mizí, indexy by míchaly persony)
			out["v%d" % i] = v.persona
			i += 1
	for k in npcs:
		if is_instance_valid(npcs[k]) and npcs[k].persona:
			out["npc:" + k] = npcs[k].persona
	for k in places:
		var regs: Array = places[k].regulars
		for j in regs.size():
			if regs[j].persona:
				out["reg:%s:%d" % [k, j]] = regs[j].persona
	return out


## Kdo hráče uslyší: vesničané a postavy do `r` m, seřazení od nejbližšího.
func listeners(id: int, r: float) -> Array:
	var pos := player_pos(id)
	var seen := {}
	var cand := []
	for v in bots_root.get_children():
		if v is Villager and not v.is_knocked():
			cand.append(v)
	for k in npcs:
		cand.append(npcs[k])
	for k in places:
		cand.append_array(places[k].regulars)
	if police:
		for c in [police.checkpoint_cop, police._stop_cop]:
			if c != null and is_instance_valid(c):
				cand.append(c)
	var out := []
	for n in cand:
		if not is_instance_valid(n) or seen.has(n.get_instance_id()) or n.get("persona") == null:
			continue
		seen[n.get_instance_id()] = true
		if n.global_position.distance_to(pos) < r:
			out.append(n)
	out.sort_custom(func(a, b): return a.global_position.distance_squared_to(pos) < b.global_position.distance_squared_to(pos))
	return out


## Hráč otevřel řádek na promluvu (T) – ať vesničané poblíž chvíli postojí, než dopíše a odešle.
func hold_listeners(id: int, dur := 20.0) -> void:
	for w in listeners(id, 11.0):
		if w is Villager:
			w.wait_for_reply(dur)


## Kontext pro Dialog: kdo mluví, jak se na hráče dívá, stav hráče a světa (viz Dialog – popis ctx).
func dialog_context(id: int, speaker: Node) -> Dictionary:
	var per: Persona = speaker.get("persona")
	var ctx := {"persona": per, "pid": id, "role": String(speaker.get("role")) if speaker is Npc else "villager",
		"place": String(speaker.get("place")) if speaker is Npc else ""}
	var p: Player = players.get(id)
	if p == null or per == null:
		return ctx
	var rep: Reputation = reputations.get(id)
	var score := rep.score if rep else 0.0
	var mood := per.get_mood(id, clock.minutes)
	ctx["mood"] = mood
	ctx["met"] = per.met.has(id)
	ctx["rep"] = score
	ctx["tier"] = rep.tier_key() if rep else "neutral"
	ctx["tier_name"] = rep.tier_name() if rep else ""
	var comm := Reputation.community_of(per)
	var resp := rep.respect_of(comm) if rep else 0.0
	var friend := per.get_friendship(id)
	ctx["community"] = comm
	ctx["respect"] = resp
	ctx["friendship"] = friend
	# respekt komunity a přátelství přidávají vřelost (a naopak; přátelství jen kladně)
	ctx["attitude"] = clampf(Dialog.attitude(score, mood, String(per.profile.get("trait", "pratelsky"))) + resp * 0.2 + friend * 0.25,
		-100.0, 100.0)
	ctx["promile"] = p.body.promile()
	ctx["in_car"] = p.car != null
	ctx["outfit_tags"] = Wardrobe.tags(p.outfit)          # M2.3: reakce postav na oblečení (plavky, slavnostní)
	Wardrobe.on_talk(self, id, per, String(ctx["place"]))
	ctx["hour"] = clock.hour()
	ctx["time_text"] = clock.text()
	ctx["weather"] = weather.describe()
	ctx["raining"] = weather.is_raining()
	ctx["snowing"] = weather.is_snowing()
	ctx["temp"] = weather.temp
	var from: Vector3 = (speaker as Node3D).global_position
	var pls := {}
	for k in places:
		var pl: Place = places[k]
		pls[k] = {"name": pl.data["name"], "open": pl.is_open(clock.hour()), "hours": pl.hours_text(),
			"dir": bearing_text(from, pl.door), "dist": from.distance_to(pl.door)}
	if npcs.has("deda"):
		pls["deda"] = {"name": "Děda Vomáčka", "open": true, "hours": "", "dir": bearing_text(from, npcs["deda"].global_position),
			"dist": from.distance_to(npcs["deda"].global_position)}
	ctx["places"] = pls
	if estate:                    # M1.7: domov hráče pro texty ({home}, {deda_home}, {lot} v Dialog._fill_ext)
		ctx["home_label"] = estate.home_label(id)
		ctx["home_where"] = estate.home_where(id)
		ctx["home_no"] = estate.number_of(estate.home_estate(id))
		ctx["home_flat"] = estate.is_flat(id)
		ctx["deda_label"] = estate.deda_label()
		ctx["lot_label"] = estate.lot_label()
	ctx["police_cp"] = police.checkpoint_pos != Vector3.INF
	if ctx["police_cp"]:
		ctx["police_dir"] = "směrem " + bearing_text(from, police.checkpoint_pos)
	var q: Quests = quests.get(id)
	var offers := []
	if q:
		ctx["quest_active"] = q.active.title if q.active else ""
		for qq in q.list:
			if qq.state in ["available", "failed"] and qq.can_start():
				offers.append("%s (%s)" % [qq.giver_name, Hud.GIVER_WHERE.get(qq.giver, "")])
	ctx["quest_offers"] = offers
	if rep and clock.minutes - rep.last_offense_min < 3.0 * 1440.0:
		ctx["last_offense"] = rep.last_offense_text
	_talk_context(ctx, id, p)
	return ctx


## Doplní kontext rozhovoru o data pro rozšířený rozhovor (Dialog + DialogData / DialogThemes): čas, období, svátky,
## počasí, peníze, co hráč nese a jeho nedávné události (`talk_recent`).
func _talk_context(ctx: Dictionary, id: int, p: Player) -> void:
	ctx["now_min"] = clock.minutes
	ctx["day"] = clock.day()
	ctx["season"] = clock.season()
	ctx["weekday"] = clock.weekday()
	ctx["holiday"] = clock.holiday()
	ctx["fog"] = weather.fog
	ctx["wind"] = weather.wind
	ctx["snow_cover"] = weather.snow_cover
	ctx["cloud"] = weather.cloud
	ctx["daylight"] = clock.daylight()
	ctx["money"] = p.money
	var d := clock.date()
	var m: int = d["month"]
	var dd: int = d["day"]
	var ev := []
	if m == 12 and dd >= 20 and dd <= 26:
		ev.append("event_vanoce")
	if (m == 12 and dd == 31) or (m == 1 and dd == 1):
		ev.append("event_silvestr")
	if m == 4 and dd == 30:
		ev.append("event_carodejnice")
	# A4-09: masopust a hody podle VillageEvents (jediný zdroj pravdy – dialog „ví“ o nich jen když se opravdu konají)
	if village_events:
		if village_events.is_active("masopust"):
			ev.append("event_masopust")
		if village_events.is_active("hody"):
			ev.append("event_hody")
	ctx["events"] = ev
	var carry := []
	var eq := p.equipped
	if eq.begins_with("udice"):
		carry.append("carry_rod")
	elif eq in ["puska", "luk", "kuse"]:
		carry.append("carry_gun")
	elif eq.begins_with("sekera") or eq == "motorova_pila":
		carry.append("carry_axe")
	for k in p.inventory:
		if int(p.inventory[k]) <= 0 or not ItemsDB.exists(k):
			continue
		var inf := ItemsDB.info(k)
		match String(inf.get("type", "")):
			"fish": carry.append("carry_fish")
			"seed": carry.append("carry_seeds")
			"meat": carry.append("carry_game")
			"food":
				if inf.has("feed"):
					carry.append("carry_veg")
			"drink":
				if String(k).begins_with("pivo"):
					carry.append("carry_beer")
		if k == "polena":
			carry.append("carry_wood")
	if cargo and cargo.hands_busy(id):
		var own: Dictionary = cargo._own.get(id, {})
		var ent: Dictionary = own.get("e", {})
		if ent.get("c") != null:
			carry.append("carry_game")
		elif String(ent.get("kind", "")).contains("spal"):
			carry.append("carry_wood")
	ctx["carry"] = carry
	ctx["recent"] = talk_recent.get(id, {})


## Hráč něco řekl nahlas (T). Uslyší to postavy v okolí (křik – víc vykřičníků nebo VELKÁ PÍSMENA – dál);
## odpoví ta nejbližší, nebo ta, kterou hráč oslovil jménem. Urážky a vyhrůžky slyší i ostatní.
func player_say(id: int, raw: String) -> void:
	var p: Player = players.get(id)
	if p == null:
		return
	var text := raw.strip_edges().substr(0, 160)
	if text == "":
		return
	var shout := text.ends_with("!!") or (text.length() >= 4 and text.to_upper() == text and text.to_lower() != text)
	var shown := Dialog.slur(text, p.body.promile())
	p.say(shown, clampf(2.0 + shown.length() / 14.0, 3.0, 8.0))
	notify(id, "chat_line", ["Ty", shown, true])
	var who := listeners(id, 26.0 if shout else 11.0)
	if who.is_empty():
		notify(id, "chat_line", ["", "(Tvůj křik se nese prázdnou ulicí.)" if shout else "(Nikdo poblíž tě neslyší.)", false])
		return
	var target: Node3D = who[0]
	var nt := Dialog.norm(text)
	for w in who:
		var fn := Dialog.norm(w.persona.first_name()).strip_edges()
		if fn.length() >= 3 and nt.contains(" " + fn):
			target = w
			break
	var ctx := dialog_context(id, target)
	ctx["shout"] = shout
	var r := Dialog.respond(text, ctx)
	await get_tree().create_timer(0.8).timeout
	if not is_instance_valid(target) or not players.has(id):
		return
	_apply_reply(id, target, r)
	# svědci urážky / vyhrůžky
	if r["intent"] in ["insult", "threat"]:
		for w in who:
			if w != target and is_instance_valid(w):
				await get_tree().create_timer(1.2).timeout
				if is_instance_valid(w) and players.has(id):
					var line := Dialog.witness(dialog_context(id, w), r["intent"])
					w.say(line, 3.5)
					w.persona.add_mood(id, -0.15, clock.minutes)
					notify(id, "chat_line", [w.persona.display_name(), line, false])
				break


## Odpověď postavy: bublina, zápis do rozhovoru v HUD, nálada, pověst, pokuta, přivolání policie.
func _apply_reply(id: int, target: Node3D, r: Dictionary) -> void:
	var per: Persona = target.get("persona")
	var txt: String = r["text"]
	target.say(txt, clampf(2.0 + txt.length() / 14.0, 3.5, 9.0))
	per.add_mood(id, float(r["mood"]), clock.minutes)
	per.met[id] = true
	notify(id, "chat_line", [per.display_name(), txt, false])
	var p: Player = players[id]
	var rep: Reputation = reputations.get(id)
	if rep and float(r["rep"]) != 0.0:
		var d := per.allow_rep(id, clock.day(), float(r["rep"]))
		var off := ""
		match String(r["intent"]):
			"insult": off = "urážka policisty" if target.get("role") == "cop" else "sprosté urážky"
			"threat": off = "vyhrožování"
		if d != 0.0:
			rep.change(d, String(r["rep_text"]), off)
	if rep:
		var intent := String(r["intent"])
		rep.on_chat(per, intent in Skills.CHAT_INTENTS, intent in ["insult", "threat"], target.get("role") == "cop")
	if r.get("police_hint", false):
		police.checkpoint_seen[id] = true
	var fine := int(r.get("fine", 0))
	if fine > 0:
		var res := commit_offense(id, "vyhruzka_uredni_osobe" if String(r["intent"]) == "threat" else "urazka_uredni_osoby",
			{"quiet": true})
		notify(id, "police_banner", ["Pokuta na místě %d Kč (zaplaceno %d Kč)" % [res.get("fine", fine), res.get("paid", 0)], 4.0])
		play_sfx(id, "cash")
	if r.get("call_police", false):
		p.wanted_until = maxf(p.wanted_until, clock.minutes + 120.0)
		notify(id, "police_banner", ["%s volá policii! Hlídka po tobě jde." % per.display_name(), 4.0])
	emit_game_event(id, "chat", {"intent": r["intent"], "to": per.display_name()})


## Dárek postavě (M0.6, zatím jen háček bez UI – tlačítko „Dát“ dodá M4.5): předmět přejde k postavě,
## roste přátelství (podle ceny předmětu) a nálada. Vrací true, když se předání povedlo.
func give_to_npc(id: int, npc: Node, item_id: String) -> bool:
	var p: Player = players.get(id)
	var per: Persona = npc.get("persona") if npc else null
	if p == null or per == null or not ItemsDB.exists(item_id) or not p.remove_item(item_id, 1):
		return false
	var price := float(ItemsDB.info(item_id).get("price", 0))
	var d := Persona.FRIEND_GIFT * clampf(1.0 + price / 200.0, 1.0, 3.0) * per.gift_mult(item_id)   # M4.5: oblíbené ×2, neoblíbené mírné mínus
	per.add_friendship(id, d, clock.minutes, clock.day(), true)
	per.add_mood(id, 0.3, clock.minutes)
	notify(id, "show_message", ["%s: „Děkuju, to je od tebe hezké.“" % per.first_name(), 3.0])
	var rep: Reputation = reputations.get(id)
	if rep:
		rep.change_karma(0.5, "dárek")
	emit_game_event(id, "gift_given", {"to": per.display_name(), "item": item_id})
	return true


func accept_quest(id: int, q) -> void:
	quests[id].accept(q)


func use_item(id: int, item_id: String) -> bool:
	return players[id].use_item(item_id)


## Něco podaného k snědku / vypití (lednička doma) – zdarma.
func serve(id: int, item_id: String) -> void:
	players[id].consume_served(item_id)


func vomit(id: int) -> void:
	players[id].body.vomit()


## Cena u pultu po započtení pověsti (vážený občan sleva, postrach vsi přirážka).
func price_for(id: int, base: int) -> int:
	var r: Reputation = reputations.get(id)
	return roundi(base * (r.price_mult() if r else 1.0))


## A1-05: je místo `place` zavřené? Když ano, hráč dostane zprávu a obchodní akce se zruší.
## Prázdný klíč, „domov“ a neznámá místa se nehlídají.
func place_shut(id: int, place: String) -> bool:
	if place == "" or place == "domov" or not places.has(place):
		return false
	var pl: Place = places[place]
	if pl.is_open(clock.hour()):
		return false
	notify(id, "show_message", ["Zavřeno, otevřeno %s." % pl.hours_text(), 2.5])
	return true


func buy(id: int, item_id: String, base_price: int, mode: String, place := "") -> void:
	var p: Player = players[id]
	if place_shut(id, place):
		return
	if mode == "sell":
		sell_items(id, item_id, base_price, place)
		return
	if mode == "service":         # služba na úřadě (M2.4: pronájem pole)
		if garden:
			garden.service(id, item_id, base_price)
		return
	var r: Reputation = reputations.get(id)
	if r and place != "" and r.refused_at(place):
		notify(id, "show_message", ["„Tobě nic neprodám. Po tom, cos ve vsi vyváděl…“", 3.0])
		return
	var need_permit := String(Weapons.PERMIT_ITEMS.get(item_id, ""))
	if need_permit != "" and not has_permit(id, need_permit, p.global_position):
		# M2.8: puška a náboje jen se zbrojním oprávněním (průkaz vydá M4.6; zatím jen cheat F2 → Hráč)
		notify(id, "show_message", ["„Bez zbrojního oprávnění vám ji neprodám.“", 3.5])
		return
	var price := price_for(id, base_price)
	if p.money < price:
		notify(id, "show_message", ["Nemáš dost peněz.", 2.0])
		return
	if mode == "serve" and p.busy:
		notify(id, "show_message", ["Nejdřív dopij / dojez.", 2.0])
		return
	p.money -= price
	play_sfx(id, "cash")
	if mode == "serve":
		p.consume_served(item_id)
	else:
		p.add_item(item_id)
		notify(id, "show_message", ["Koupeno: %s" % Consumables.info(item_id)["short"], 2.0])
		if item_id == "rucni_vozik" and cargo:
			cargo.deliver_cart(id)      # M2.10: vozík (předmět ve světě) stojí po koupi u domu


## Výkup (M2.1, režim „sell“ v `Place.OFFERS`): prodá všechny kusy `item_id` z inventáře za `unit_price` Kč / ks.
func sell_items(id: int, item_id: String, unit_price: int, place := "") -> void:
	var p: Player = players.get(id)
	if p == null or place_shut(id, place):
		return
	if hunting and Hunting.is_venison(item_id) and hunting.sell_venison(id, item_id, unit_price, place):
		return                    # M2.9: zvěřina jen legální a s dokladem o původu (nelegální u překupníka)
	if item_id == "ryba_kapr" and place == "hospoda" and clock.month() == 12:
		unit_price *= 2           # M2.7: hostinský koupí kapra na Vánoce dráž (prosinec ×2)
	var n := p.item_count(item_id)
	if n <= 0:
		notify(id, "show_message", ["Nemáš co prodat.", 2.0])
		return
	p.remove_item(item_id, n)
	p.money += n * unit_price
	play_sfx(id, "cash")
	notify(id, "show_message", ["Prodáno: %d× %s za %d Kč." % [n, ItemsDB.name_of(item_id), n * unit_price], 3.0])


## Povolení úřadu (M4.4 / M4.6): `kind` = "kaceni", "zbrojni" (zbrojní oprávnění), "rybarsky_listek", "povolenka_rybolov"…
## `pos` = místo. Zatím nikdo žádné nemá (háček pro kácení M2.1, rybaření M2.7, zbraně M2.8), jen ladicí cheat
## `cheat(id, "zbrojni")` (F2 → Hráč) – doklady, lístky a jejich platnost doplní M4.6.
# ------------------------------------------------------------------ řidičák a autoškola (M4.1)

const AUTO_KURZ_KC := {"AM": 3000, "A1": 8900, "A2": 9900, "A": 7900, "T": 6900, "B": 12000}   # orientačně
const AUTO_PREZKOUSENI_KC := 2500         # přezkoušení po odebrání za 12 bodů (skupina B)
const AUTO_JIZD_NUTNE := 3                # výcvikové jízdy s instruktorem (každá = odjezd od úřadu a návrat)
const AUTO_JIZDA_MIN_M := 300.0           # nástup musí být aspoň tak daleko od úřadu
const AUTO_CIL_M := 30.0                  # výstup musí být nejvýš tak daleko od dveří úřadu

## Stav kurzu autoškoly hráče (computer.gd `auto_skola`): {zaplaceno, skupina, teorie, jizdy, retest}.
func auto_school(id: int) -> Dictionary:
	return computer.auto_school(id) if computer else {}


## Kontrola řidičáku pro vozidlo: {ok, group, reason}. Kolo / vozidlo bez skupiny = v pořádku.
func license_check(id: int, c: Car) -> Dictionary:
	var grp := String(c.model.spec.get("skupina_rp", "")) if c and c.model else ""
	if grp == "" or permits == null or permits.has(id, "ridicsky", grp):
		return {"ok": true, "group": grp, "reason": ""}
	var why := "odebraný řidičák, nutné přezkoušení" if not permits.is_revoked(id, "ridicsky").is_empty() \
		else "chybí skupina"
	return {"ok": false, "group": grp, "reason": why}


## Zápis do autoškoly (kurz skupiny z AUTO_KURZ_KC; po odebrání za 12 bodů přezkoušení skupiny B).
func auto_enroll(id: int, skupina: String) -> String:
	if computer == null or permits == null:
		return "Síť je nedostupná."
	var s := auto_school(id)
	if bool(s.get("zaplaceno", false)):
		return "Kurz už máš zaplacený (skupina %s) – slož teorii a %d výcvikové jízdy." % [s["skupina"], AUTO_JIZD_NUTNE]
	var odebrano := not permits.is_revoked(id, "ridicsky").is_empty()
	var retest := odebrano
	var grp := "B" if retest else skupina
	if retest and clock.minutes < float(_license_suspended_until(id)):
		return "Zákaz řízení ještě běží – přezkoušení až po něm."
	if not retest and permits.has(id, "ridicsky", grp):
		return "Skupinu %s už máš." % grp
	var cena: int = AUTO_PREZKOUSENI_KC if retest else int(AUTO_KURZ_KC.get(grp, 0))
	if cena <= 0:
		return "Tuhle skupinu autoškola nenabízí."
	var nazev := "Autoškola – přezkoušení" if retest else "Autoškola – kurz %s" % grp
	if not computer.withdraw_bank(id, cena, nazev):
		return "Na účtu nemáš %s. Vlož hotovost v bankomatu." % Bazaar.kc(cena)
	s["zaplaceno"] = true
	s["skupina"] = grp
	s["teorie"] = false
	s["jizdy"] = 0
	s["retest"] = retest
	emit_game_event(id, "auto_school_enrolled", {"skupina": grp})
	return "Zaplaceno %s. Teorie: eTest „autoskola“ (tady na PC). Praxe: %d výcvikové jízdy – nasedni do vozidla " % [
		Bazaar.kc(cena), AUTO_JIZD_NUTNE] + "skupiny %s, odjeď aspoň %d m od úřadu a vrať se k jeho dveřím." % [grp, int(AUTO_JIZDA_MIN_M)]


func _license_suspended_until(id: int) -> float:
	return players[id].license_suspended_until if players.has(id) else -1.0


## Složená teorie (volá `Computer.record_test` u eTestu „autoskola“).
func auto_theory_passed(id: int) -> void:
	var s := auto_school(id)
	if not bool(s.get("zaplaceno", false)):
		return
	s["teorie"] = true
	_auto_try_finish(id)


## Výcviková jízda: nástup v dálce od úřadu, výstup u úřadu (instruktor hodnotí rádiem).
func _auto_jizda_end(id: int, c: Car, out: Vector3) -> void:
	if not _auto_start.has(id):
		return
	var start: Vector3 = _auto_start[id]
	_auto_start.erase(id)
	var s := auto_school(id)
	if not bool(s.get("zaplaceno", false)) or c == null or c.model == null:
		return
	var grp := String(c.model.spec.get("skupina_rp", ""))
	if grp == "" or not Permits.skupina_kryje(String(s["skupina"]), grp):
		return
	var door: Vector3 = places["urad"].door
	if Vector2(start.x - door.x, start.z - door.z).length() < AUTO_JIZDA_MIN_M:
		notify(id, "show_message", ["Instruktor (rádio): „Tohle je krátká jízda, odjeď dál od úřadu.“", 4.0])
		return
	if Vector2(out.x - door.x, out.z - door.z).length() > AUTO_CIL_M:
		notify(id, "show_message", ["Instruktor (rádio): „Vrať se k úřadu, tam končí výcvik.“", 4.0])
		return
	s["jizdy"] = int(s.get("jizdy", 0)) + 1
	notify(id, "show_message", ["Instruktor: „Jízda %d/%d – hezky. Hlídej 50 v obci a STOP značky.“" % [
		s["jizdy"], AUTO_JIZD_NUTNE], 5.0])
	_auto_try_finish(id)


## Splněno (teorie + všechny jízdy) → řidičák se skupinou, nebo po odebrání obnovení.
func _auto_try_finish(id: int) -> void:
	var s := auto_school(id)
	if not bool(s.get("zaplaceno", false)) or not bool(s.get("teorie", false)) \
			or int(s.get("jizdy", 0)) < AUTO_JIZD_NUTNE or permits == null:
		return
	var grp := String(s["skupina"])
	var retest := bool(s.get("retest", false))
	if retest:
		permits.restore(id, "ridicsky")
	else:
		permits.grant(id, "ridicsky", "RP-%04d" % id, grp)
	s["zaplaceno"] = false
	s["teorie"] = false
	s["jizdy"] = 0
	s["retest"] = false
	var text := "Přezkoušení složeno – řidičský průkaz je znovu platný." if retest \
		else "Složil(a) jsi zkoušku – skupina %s je v průkazu." % grp
	send_mail(id, "Autoškola Volant (smyšlená)", "Výsledek zkoušky", "Gratulujeme!\n%s" % text)
	if skills.has(id):
		(skills[id] as Skills).add_xp("rizeni", 100.0, "autoškola")
	if reputations.has(id):
		reputations[id].change(1.0, "Složená zkouška z řízení")
	emit_game_event(id, "auto_license_granted", {"skupina": grp, "retest": retest})
	notify(id, "popup", ["Řidičský průkaz: %s" % text, 6.0])


func has_permit(id: int, kind: String, _pos: Vector3) -> bool:
	if kind == "kaceni" and les and les.work_permit(id, _pos):
		return true               # M3.3: lesní dělník na směně kácí vyznačené stromy
	if permits and permits.has(id, kind):
		return true               # M6.1: registrace dronu / osvědčení A1/A3 (Permits; doklady M4.6 stejně)
	return bool((_cheat_permits.get(id, {}) as Dictionary).get(kind, false))


## Je lov tady a teď legální? {ok: bool, reasons: Array} (M2.9, viz `Hunting.is_legal_hunt`): luk a kuše nikdy, puška jen se
## zbrojním oprávněním + loveckým lístkem + povolenkou (`has_permit`), v době lovu druhu, ne v noci (kromě divočáka), ne v obci, ne z auta.
func is_legal_hunt(id: int, weapon: String, species: String, pos: Vector3, male := true) -> Dictionary:
	if hunting == null:
		return {"ok": false, "reasons": ["Lov není k dispozici."]}
	return hunting.is_legal_hunt(id, weapon, species, pos, male)


## Id budovy domova, jehož komín má kouřit, protože se doma topí v kamnech (M2.2); 0 = nekouří vynuceně (i v bytě).
func home_chimney_id() -> int:
	return fire_mgr.home_chimney_id() if fire_mgr else 0


## Vyspat se do 7:00 ráno. `where` = "domov" (postel doma), nebo druh provizorního noclehu
## (SleepSpot.KINDS: senik, palanda, spacak) – tam se spí hůř a v mrazu je zima.
func sleep(id: int, where := "domov") -> void:
	var h := fmod(31.0 - clock.hour(), 24.0)
	if h < 1.0:
		h = 8.0
	rest(id, h, where)


## Odpočinek / spánek `hours` herních hodin na místě `where` (viz sleep). Po spánku se hra uloží (slot „auto“).
func rest(id: int, hours: float, where := "domov") -> void:
	var pl: Player = players.get(id)
	if pl == null or _blackout.has(id):
		return
	if pl.car or pl.horse or pl.aircraft:
		notify(id, "show_message", ["Nejdřív vystup / sesedni.", 2.0])
		return
	var bag: SleepSpot = null
	if where == "spacak":
		# spacák se rozloží na místě (jen na dobu spánku)
		bag = SleepSpot.make("spacak", pl.global_position, pl.yaw)
		add_child(bag)
	pl.controls_locked = true
	if where != "domov":
		pl.visual.pose = "lie"
	# M1.7: byt má ústřední topení (radiátor) – zima jen v nevytopeném rodinném domě
	var home_cold := where == "domov" and weather.temp < 5.0 and not (estate != null and estate.is_flat(id)) \
		and not (fire_mgr != null and fire_mgr.home_heated_for(hours))
	await blackout(id, 2.0)
	skip_time(id, hours, true)
	if bag:
		bag.queue_free()
	# počasí během spánku na těle: v posteli doma sucho a teplo, venku se spí jak to jde
	match where:
		"domov":
			pl.body.wetness = 0.0
			pl.body.cold = 0.0
			if home_cold:         # M2.2: nevytopený dům při mrazu – prochladnutí a horší odpočinek (mírně)
				pl.body.cold = clampf((5.0 - weather.temp) * FireManager.HOME_COLD_PER_DEG, 0.05, FireManager.HOME_COLD_MAX)
		"spacak":
			if weather.is_raining():
				pl.body.wetness = 1.0
			if weather.temp < 3.0:
				pl.body.cold = maxf(pl.body.cold, 0.6)
		_:                                        # seník, palanda – pod střechou, ale venku
			pl.body.wetness = maxf(pl.body.wetness - 0.6, 0.0)
			pl.body.cold = maxf(pl.body.cold, 0.35) if weather.temp < 5.0 else 0.0
	pl.visual.pose = "stand"
	pl.controls_locked = false
	var heal := 30.0 if where == "domov" else float(SleepSpot.KINDS[where][1])
	heal *= clampf(hours / 8.0, 0.25, 1.0)
	if home_cold:
		heal -= FireManager.HOME_COLD_HEAL
	var msg := ("Dobré ráno! Je %s." if hours >= 5.0 else "Probudil ses. Je %s.") % clock.text()
	if home_cold:
		msg += "\nV nevytopeném domě byla zima – příště zatop v kamnech."
	if where != "domov":
		msg += {"senik": "\nSeno píchá a voní – záda bolí, ale noc jsi přečkal.",
			"palanda": "\nNa palandě to šlo. Myslivec ti ráno kývl na pozdrav.",
			"spacak": "\nNoc pod širákem. Rosa na spacáku, ptáci řvou."}[where]
		var t := weather.temp
		if t < 3.0 and where != "palanda":
			heal -= 10.0
			msg += "\nByla zima jak v psírně%s." % (" – promrzl jsi" if t < -3.0 else "")
			if t < -3.0:
				pl.body.hurt(12.0, "podchlazení")
		if weather.is_raining() and where == "spacak":
			heal -= 8.0
			msg += "\nPršelo – jsi promoklý na kost."
	pl.body.health = clampf(pl.body.health + heal, 1.0, 100.0)
	var p := pl.body.promile()
	if p >= 0.01:
		msg += "\nPozor: pořád máš %s ‰ – zbytkový alkohol! Za volant ještě ne." % ("%.2f" % p).replace(".", ",")
	else:
		msg += "\nMáš 0,00 ‰."
	notify(id, "show_message", [msg, 7.0])
	emit_game_event(id, "slept", {"where": where, "hours": hours})
	autosave(id)


## Spacák (inventář): přespat kdekoli venku – ne na silnici, ne v obci u domů pod okny.
func sleep_rough(id: int) -> void:
	var pl: Player = players.get(id)
	if pl == null or pl.item_count("spacak") <= 0:
		return
	var pos := pl.global_position
	if dist_to_roads(Vector2(pos.x, pos.z)) < 3.5:
		notify(id, "show_message", ["Na silnici spát nebudeš – odejdi kousek stranou.", 2.5])
		return
	for k in places:
		if places[k].door.distance_to(pos) < 8.0 and k != "chata":
			notify(id, "show_message", ["Tady přede dveřmi ne. Najdi si klidné místo venku.", 2.5])
			return
	sleep(id, "spacak")


## Rádio doma: naladit stanici ("" = vypnout) / nastavit hlasitost 0–10.
func radio_tune(id: int, station_id: String) -> void:
	if radio:
		radio.tune(id, station_id)


func radio_volume(id: int, v: int) -> void:
	if radio:
		radio.set_volume(id, v)


## Knoflíky rádia (RadioView): levý – vypínač a hlasitost 0..1, pravý – ladění 0..1.
func radio_knob(id: int, k: float) -> void:
	if radio:
		radio.turn_volume(id, k)


func radio_dial(id: int, x: float) -> void:
	if radio:
		radio.turn_dial(id, x)


## Fallback terénu bez data/surface.bin: hustota lesa z mapy stanovišť zvěře (mřížka 32 m) jako textura pro shader.
func _set_forest_fallback() -> void:
	if surface != null and surface.loaded:
		return
	var f := fauna.forest
	if f.size() != fauna.nx * fauna.nz or f.is_empty():
		return
	var bytes := PackedByteArray()
	bytes.resize(f.size())
	for i in f.size():
		bytes[i] = int(clampf(f[i], 0.0, 1.0) * 255.0)
	var img := Image.create_from_data(fauna.nx, fauna.nz, false, Image.FORMAT_R8, bytes)
	terrain.set_forest_density(ImageTexture.create_from_image(img),
		Vector4(fauna.gx0, fauna.gz0, fauna.nx * Fauna.CELL, fauna.nz * Fauna.CELL))


## Barva terénu: ortofoto (true) nebo procedurální povrch (false, výchozí). Přepíná F2 → Terén.
func set_terrain_ortho(on: bool) -> void:
	if terrain:
		terrain.set_ortho(on)


## Podklad minimapy: ortofoto, nebo (výchozí) mapa z tříd povrchu (surface.bin, jinak z polí a lesa).
func map_texture() -> Texture2D:
	if terrain == null or terrain.use_ortho:
		return load(meta["ortho_full"]["file"])
	var o: Dictionary = meta["ortho_full"]
	var area := Rect2(float(o["x0"]), float(o["z0"]), float(o["size_x"]), float(o["size_z"]))
	return ImageTexture.create_from_image(SurfaceMap.make_map_image(surface, area, 8.0, terrain, fields, fauna))


func autosave(id: int) -> void:
	if SaveGame.save(self, id, "auto"):
		notify(id, "popup", ["Hra uložena (automaticky po spánku).", 2.5])


func repair_car(id: int) -> void:
	var c := traffic.car_of(id)
	if c == null or players[id].money < 2500:
		return
	players[id].money -= 2500
	c.repair()
	notify(id, "show_message", ["Auto je jako nové.", 2.5])
	emit_game_event(id, "car_repaired", {})     # XP Kutilství (Skills.EVENT_XP)


# ------------------------------------------------------------------ herní menu (nastavení světa)
# Volá je herní menu klienta (GameMenu, F2). V multiplayeru je smí jen hostitel – řeší úkol 03+.

## Smí hráč `id` měnit svět (datum, čas, rychlost času, počasí)? Singleplayer: vždy. V multiplayeru
## (až bude `net.gd`) jen hostitel; zamýšlené napojení: `return id == host_id`. Čte ho GameMenu (položky
## bez oprávnění jsou šedé) a měl by ho hlídat i server před provedením požadavku.
func can_change_world(_id: int) -> bool:
	return true


## Smí hráč `id` teleportovat, přistavit vozidlo / koně a používat cheaty (peníze, léčení, střízlivost)?
## Singleplayer: vždy. V multiplayeru jen hostitel, případně kdokoli podle nastavení lobby `allow_cheats`.
func can_teleport(_id: int) -> bool:
	return true


## Výška země pro letouny (A2-11): uvnitř katastru terén, za ním hrubé okolí `Surroundings`
## (Terrain.height_at by za okrajem vracel sevřený okraj → špatné AGL, přistání „ve vzduchu“).
func ground_height(x: float, z: float) -> float:
	if terrain == null:
		return 0.0
	if terrain.contains(x, z, 4.0) or surroundings == null or surroundings.nx < 2:
		return terrain.height_at(x, z)
	return surroundings.height_at(x, z)


## M6.2 – letové hranice pro létající prostředky (dron; M6.3+ letouny se napojí stejně).
## Vrací Dictionary:
##   "ok"    – uvnitř povolené oblasti (katastr + FLY_LIMIT_M) a pod stropem FLY_CEIL_AGL,
##   "warn"  – v pásmu varování (posledních FLY_WARN_M před hranicí) nebo nad stropem,
##   "push"  – Vector3 „protivětru“ (m/s) mířícího zpět do mapy / dolů – přičíst k cílové
##             rychlosti stroje (měkké odpuzení; u hranice dosáhne FLY_PUSH_MS),
##   "out"   – kolik metrů za obdélníkem katastru (0 = uvnitř),
##   "agl"   – výška nad terénem (m).
## Chodec a auto se tohoto netýká – jejich zeď dělá Terrain._add_bounds.
func flight_bounds(pos: Vector3) -> Dictionary:
	var out := 0.0
	var agl := pos.y
	var push := Vector3.ZERO
	if terrain != null:
		var xa := terrain.x0 + 4.0
		var xb := terrain.x0 + (terrain.w - 1) * terrain.spacing - 4.0
		var za := terrain.z0 + 4.0
		var zb := terrain.z0 + (terrain.h - 1) * terrain.spacing - 4.0
		var dx := pos.x - clampf(pos.x, xa, xb)
		var dz := pos.z - clampf(pos.z, za, zb)
		out = Vector2(dx, dz).length()
		if out > 0.0:
			var k := clampf((out - (FLY_LIMIT_M - FLY_WARN_M)) / FLY_WARN_M, 0.0, 1.0)
			push = Vector3(-dx, 0.0, -dz) / out * FLY_PUSH_MS * k
		agl = pos.y - ground_height(pos.x, pos.z)
	var over_ceil := agl > FLY_CEIL_AGL
	if over_ceil:
		push.y = -minf(FLY_CEIL_PUSH + (agl - FLY_CEIL_AGL) * 0.1, FLY_PUSH_MS)
	var warn := (out > FLY_LIMIT_M - FLY_WARN_M) or over_ceil
	return {"ok": out < FLY_LIMIT_M, "warn": warn, "push": push, "out": out, "agl": agl}


## Datum (rok, měsíc, den) – počasí se přepočítá pro nové roční období.
func set_date(y: int, m: int, d: int) -> void:
	clock.set_date(y, m, d)
	weather.reset()
	refresh_season_items()
	if village_events:
		village_events.refresh()
	if hunter:
		hunter.refresh()


## Denní doba (h) v rámci dnešního dne.
func set_time(h: float) -> void:
	clock.minutes = float(clock.day() - 1) * 1440.0 + h * 60.0
	weather._last_min = clock.minutes


func set_time_speed(mul: float) -> void:
	clock.speed = mul


## Počasí: druh z Weather.TYPES nebo "snih"; "auto" = zase podle simulace.
func set_weather(kind: String) -> void:
	if kind == "auto":
		weather.unforce()
	else:
		weather.force(kind)


## Ladění: pevná teplota vzduchu °C (NAN = zpět podle klimatu). Ovlivní i sněžení / déšť.
func set_temperature(t: float) -> void:
	weather.forced_temp = t
	if not is_nan(t):
		weather.temp = t


## Nové vozidlo vedle hráče (patří mu – jde do něj nastoupit klávesou F).
func spawn_vehicle(id: int, model_id: String) -> void:
	var p: Player = players[id]
	var paint := Color.from_hsv(randf(), 0.6, 0.7)
	var c := traffic.make_car(model_id, paint)
	c.owner_id = id
	var spot := traffic.free_spot(Vector2(p.global_position.x, p.global_position.z), p.yaw + PI, Vector3(2.0, 1.4, 4.8))
	traffic.place_car(c, Vector2(spot.x, spot.y), spot.z)
	traffic.player_vehicles[id].append(c)
	_connect_car(c)
	notify(id, "show_message", ["Přistaveno: %s – nastup klávesou F." % c.model.spec.get("name", model_id), 3.0])


## Vlastní auto hráče přistavit k němu.
func summon_car(id: int) -> void:
	var c := traffic.car_of(id)
	var p: Player = players[id]
	if c == null or p.car == c:
		return
	var spot := traffic.free_spot(Vector2(p.global_position.x, p.global_position.z), p.yaw + PI, Vector3(2.0, 1.4, 4.8))
	traffic.place_car(c, Vector2(spot.x, spot.y), spot.z)


## Kůň hráče přiběhne k němu (objeví se vedle).
func summon_horse(id: int) -> void:
	var h := fauna.horse_of(id)
	var p: Player = players[id]
	if h == null or h.rider:
		return
	var a := p.yaw + PI * 0.5
	var pos := p.global_position + Vector3(sin(a), 0, cos(a)) * 3.0
	pos.y = terrain.height_at(pos.x, pos.z) + 0.2
	h.global_position = pos
	h.velocity = Vector3.ZERO
	h.tether = pos
	h.yaw = p.yaw + PI


## Teleport hráče (i s autem / z koně sesedne). `pos` = bod na zemi.
func teleport_player(id: int, pos: Vector3, yaw: float) -> void:
	var p: Player = players[id]
	if p.horse:
		dismount_horse(id)
	if p.aircraft:
		exit_aircraft(id)              # M6.3: letoun zůstane stát, kde přistál
	interior_clear(p)
	pos.y = terrain.height_at(pos.x, pos.z)
	if p.car:
		traffic.place_car(p.car, Vector2(pos.x, pos.z), yaw + PI)
		return
	p.teleport(pos + Vector3(0, 0.3, 0), yaw, false)


## Místo pro teleport: klíč místa (Place), "zver:<druh>", "vcely", "mraveniste", "les", "pole",
## "krmelec", "posed", "vybeh" (kůň u domu), "vcelar". Vrací [poloha, yaw] nebo [] když nic takového není.
func teleport_target(id: int, what: String) -> Array:
	var p: Player = players[id]
	var from := p.global_position
	if what == "letiste" and airfield and airfield.ok:
		return airfield.teleport_spot()
	if what.begins_with("obec:"):
		# A1-07: střed okolní obce (všech 5 leží uvnitř union mřížky terénu); kdyby obec ležela mimo
		# mřížku, hráč se postaví na nejbližší okraj terénu čelem k ní
		var oid := what.substr(5)
		for o in obce:
			if String(o.get("id", o.get("name", ""))) != oid:
				continue
			var c: Array = o.get("center", [])
			if c.size() < 2 or terrain == null:
				return []
			var tgt := Vector2(float(c[0]), float(c[1]))
			var xa := terrain.x0 + 12.0
			var xb := terrain.x0 + (terrain.w - 1) * terrain.spacing - 12.0
			var za := terrain.z0 + 12.0
			var zb := terrain.z0 + (terrain.h - 1) * terrain.spacing - 12.0
			var edge := Vector2(clampf(tgt.x, xa, xb), clampf(tgt.y, za, zb))
			var dir := tgt - edge
			var yaw_o := atan2(-dir.x, -dir.y) if dir.length() > 1.0 else 0.0
			return [Vector3(edge.x, 0.0, edge.y), yaw_o]
		return []
	if what in ["krmelec", "posed", "vybeh", "vcelar"]:
		var spot := Vector3.INF
		if what == "krmelec" and hunter and not hunter.feeders.is_empty():
			spot = hunter.feeders[0]
		elif what == "posed" and hunter:
			spot = hunter.stand
		elif what == "vybeh" and paddock and paddock.ok:
			spot = paddock.to_world(0.0, -paddock.half.y - 4.0)
		elif what == "vcelar" and hunter:
			spot = hunter.beekeeper_pos()
		if spot == Vector3.INF:
			return []
		var out_ := spot + Vector3(5.0, 0.0, 5.0)
		if what == "vybeh":
			out_ = spot
		var look := (paddock.center if what == "vybeh" else spot) - out_
		return [out_, atan2(-look.x, -look.z) if look.length() > 0.5 else 0.0]
	if places.has(what):
		var pl: Place = places[what]
		var tp := pl.park - pl.door
		tp.y = 0.0
		var at0 := pl.door + (tp.normalized() * 1.5 if tp.length() > 0.5 else Vector3.ZERO)
		return [at0, atan2(tp.x, tp.z) if tp.length() > 0.5 else 0.0]
	var best: Node3D = null
	var bd := INF
	var cands: Array = []
	if what.begins_with("zver:"):
		var sp := what.substr(5)
		for a in fauna.animals:
			if is_instance_valid(a) and a.species == sp and not a.dead:
				cands.append(a)
	elif what == "vcely" or what == "mraveniste":
		for n in fauna.root_insects.get_children():
			if (what == "vcely" and n is Apiary) or (what == "mraveniste" and n is AntHill):
				cands.append(n)
	elif what == "les" or what == "pole":
		var pt := fauna.random_point(from, 1200.0, "forest" if what == "les" else "field", fauna.rng, 30)
		return [pt, randf() * TAU]
	for n in cands:
		var d: float = n.global_position.distance_to(from)
		if d < bd and d > 50.0:
			bd = d
			best = n
	if best == null and not cands.is_empty():
		best = cands[0]
	if best == null:
		return []
	# kousek od cíle, natočený k němu – u zvěře těsně za únikovou vzdáleností druhu,
	# ať si hráče všimne a zůstane v pozoru (hlava nahoru, viditelné), místo aby hned zdrhlo
	var off := 30.0 if what.begins_with("zver:") else 4.0
	if what.begins_with("zver:") and best is Animal:
		off = float((best as Animal).spec["flight"]) + 12.0
	var dir := (from - best.global_position)
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.1 else Vector3(1, 0, 0)
	var at := best.global_position + dir * off
	return [at, atan2(dir.x, dir.z)]


## Ruční test přírody (menu F2): vynucená zvěř / hejno ptáků u hráče `id`. Vrací text pro hlášku.
func fauna_spawn_near(id: int, birds := false) -> String:
	if not players.has(id) or fauna == null:
		return "Hráč nebo příroda není k dispozici."
	var p: Player = players[id]
	if birds:
		return fauna.spawn_flock_near(p.global_position, p)
	return fauna.spawn_encounter_near(p.global_position, p)


## Hráč: vystřízlivět, uzdravit, peníze.
func cheat(id: int, what: String) -> void:
	var p: Player = players[id]
	match what:
		"sober":
			p.body.body_alc = 0.0
			p.body.stomach_alc = 0.0
		"heal":
			p.body.heal_full()
			p.stamina = p.body.stamina_max()
		"money":
			p.money += 5000
		"ucet":                       # M3.4: ladění počítače – peníze na účet, objednávky doručit hned
			if computer:
				computer.deposit(id, 5000, "Ladění (F2)")
				var n := computer.deliver_now(id)
				notify(id, "show_message", ["+5 000 Kč na účet; balíků na cestě doručeno hned: %d." % n, 3.5])
		"xp_rizeni":
			give_xp(id, "rizeni", 1000.0, "cheat")
		"nastroje":
			for t in ["sekera", "lopata", "motyka", "konev", "udice", "nuz"]:
				p.add_item(t)
			for t in ["semena_brambory", "semena_mrkev", "semena_cibule", "semena_salat", "semena_rajcata", "semena_dyne", "semena_cesnek"]:
				p.add_item(t, 6)          # M2.4: ladění zahrady
			for t in ["navnada_zizaly", "navnada_testo", "navnada_kukurice"]:
				p.add_item(t, 6)          # M2.7: ladění rybaření
			p.add_item("podberak")
			notify(id, "show_message", ["Máš sekeru, lopatu, motyku, konev, udici, návnady, podběrák a semena (Q = do ruky).", 3.0])
		"zbrane":
			# M2.8: luk, kuše a střelivo (puška jen přes „zbrojni“)
			for t in ["luk", "kuse"]:
				if p.item_count(t) <= 0:
					p.add_item(t)
			p.add_item("sipy", 20)
			p.add_item("sipky_kuse", 20)
			notify(id, "show_message", ["Máš luk, kuši a po 20 šípech / šipkách (Q = do ruky, pravé tl. míření, levé výstřel).", 4.0])
		"drony":
			# M6.1: drony do inventáře + registrace a A1/A3 oprávnění (ladění)
			for m in DroneModel.ids():
				if p.item_count(m) <= 0:
					p.add_item(m)
			if permits:
				if not permits.has(id, "dron_provozovatel"):
					permits.grant(id, "dron_provozovatel", "CZ-DB-%04d" % id)
				if not permits.has(id, "dron_a1a3"):
					permits.grant(id, "dron_a1a3", "A1A3-%04d" % id)
			notify(id, "show_message", ["Máš drony, náhradní baterii, registraci ÚVL i osvědčení A1/A3 (Tab → Vzlétnout).", 4.0])
			p.add_item("dron_baterie")
		"zbrojni":
			# M2.8: přepíná ladicí zbrojní oprávnění (has_permit "zbrojni"); po zapnutí dá pušku a náboje
			var perm: Dictionary = _cheat_permits.get(id, {})
			perm["zbrojni"] = not bool(perm.get("zbrojni", false))
			perm["lovecky_listek"] = perm["zbrojni"]          # M2.9: legální lov = zbrojní + lovecký lístek + povolenka (ladicí cheat, doklady M4.6)
			perm["povolenka_lov"] = perm["zbrojni"]
			_cheat_permits[id] = perm
			if perm["zbrojni"]:
				if p.item_count("puska") <= 0:
					p.add_item("puska")
				p.add_item("naboje", 20)
				notify(id, "show_message", ["Zbrojní oprávnění, lovecký lístek a povolenka ZAPNUTY – máš pušku a 20 nábojů (legální lov).", 4.0])
			else:
				notify(id, "show_message", ["Zbrojní oprávnění, lovecký lístek a povolenka VYPNUTY (puška v inventáři zůstala).", 4.0])


# ------------------------------------------------------------------ smyčka

func _process(_delta: float) -> void:
	var __t0 := Tests.prof_t0()
	_process_impl(_delta)
	Tests.prof_add("world", __t0)


func _process_impl(_delta: float) -> void:
	if not ready_done:
		return
	# policie – silniční kontrolu hráč uvidí, až je blízko
	if police.checkpoint_pos != Vector3.INF:
		for id in players:
			if player_pos(id).distance_to(police.checkpoint_pos) < 120.0:
				police.checkpoint_seen[id] = true

	if clock and debts:           # M4.2: denní krok dluhů (upomínky, exekuce, doručení příkazů)
		debts.advance_to(clock.jd())
	_season_t -= _delta
	if _season_t <= 0.0:
		_season_t = SEASON_CHECK_S
		refresh_season_items()
	_crowd_t -= _delta
	if _crowd_t <= 0.0:
		_crowd_t = CROWD_CHECK_S
		_crowd_tick()


# ------------------------------------------------------------------ sezónní předměty

## Je druh předmětu v sezóně v daném dni roku?
static func in_season(kind: String, doy: int) -> bool:
	if not SEASON_ITEMS.has(kind):
		return true
	var f: int = SEASON_ITEMS[kind]["from"]
	var t: int = SEASON_ITEMS[kind]["to"]
	return (doy >= f and doy < t) if f <= t else (doy >= f or doy < t)


## Je i-tý předmět právě k mání (sezóna, u hřibů navíc vlhko z posledních dnů)?
func _item_present(i: int, kind: String, doy: int, rain_recent: float) -> bool:
	if not in_season(kind, doy):
		return false
	if kind == "hrib":
		var thr: float = float((i * 2654435761 + 12345) % 1000) / 1000.0
		return rain_recent + HRIB_DRY >= thr
	return true


## Sezónní předměty: mimo sezónu jsou skryté a nesbíratelné, sebrané po `regrow` dnech znovu vyrostou.
## Volá se každých pár sekund a hned po změně data (F2).
func refresh_season_items() -> void:
	if items_root == null or clock == null or meta.is_empty():
		return
	var doy := int(clock.day_of_year())
	var jd := clock.jd()
	var rain: float = weather.rain_recent if weather else 0.0
	var items: Array = meta["items"]
	for i in _collected.keys():
		var kind: String = items[i]["type"]
		if not SEASON_ITEMS.has(kind):
			continue
		var since: int = jd - int(_collected_jd.get(i, jd))
		if since < 0:
			_collected_jd[i] = jd      # datum se posunulo zpět
			continue
		if since >= int(SEASON_ITEMS[kind]["regrow"]) and in_season(kind, doy):
			_collected.erase(i)
			_collected_jd.erase(i)
			_spawn_item(i)
	for i in _item_nodes:
		var node = _item_nodes[i]
		if is_instance_valid(node) and not node._taken:
			node.set_active(_item_present(i, String(items[i]["type"]), doy, rain))


# ------------------------------------------------------------------ víkend: víc lidí venku

## Profil víkendového hosta (A4-06): vzhled a řeč podle náhodného vesničana, ale bez jeho jména – jinak by
## ve vsi chodili dva stejní pojmenovaní lidé. Jméno je obecné; host se neukládá (viz `personas()`).
func _weekend_guest_profile(rng: RandomNumberGenerator) -> Dictionary:
	var prof: Dictionary = Characters.profile(rng.randi() % Characters.count()).duplicate(true)
	var female: bool = bool((prof.get("look", {}) as Dictionary).get("female", false))
	prof["name"] = "Výletnice" if female else "Výletník"
	prof["job"] = "návštěvník na víkend"
	prof["hobby"] = "O víkendu se jezdím na vesnici zotavit z města."
	prof["topics"] = ["pocasi", "pivo", "drby"]
	return prof


## Víkend ve dne přibude ~30 % vesničanů (jeden za kontrolu, mimo dohled hráčů); jinak zase ubývají.
func _crowd_tick() -> void:
	if bots_root == null or _bot_nodes.is_empty() or clock == null:
		return
	var h := clock.hour()
	var want := 0
	if clock.weekday() >= 5 and h >= WEEKEND_HOURS[0] and h < WEEKEND_HOURS[1]:
		want = roundi(N_VILLAGERS * WEEKEND_CROWD)
	_extra_villagers = _extra_villagers.filter(func(v): return is_instance_valid(v))
	if _extra_villagers.size() < want:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		for tries in 8:
			var nid: int = _bot_nodes[rng.randi() % _bot_nodes.size()]
			var np: Vector2 = graph.nodes[nid]
			var pos := Vector3(np.x, terrain.height_at(np.x, np.y), np.y)
			if nearest_player_dist(pos) < 70.0:
				continue
			var v := Villager.new()
			v.setup(graph, terrain, self, nid, 3000 + rng.randi() % 100000, _weekend_guest_profile(rng))
			bots_root.add_child(v)
			_extra_villagers.append(v)
			break
	elif _extra_villagers.size() > want:
		for v in _extra_villagers:
			if nearest_player_dist(v.global_position) > 60.0:
				_extra_villagers.erase(v)
				v.queue_free()
				break


# ------------------------------------------------------------------ drony (M6.1)
# Autorita: `drones[pid]` = dron hráče ve světě (letí / leží / visí / padá), `drone_states[pid][model]`
# = trvalý stav flotily {bat, dmg} (drží se i v inventáři mezi lety). Registrace a kvalifikace přes
# `permits` (`dron_provozovatel`, `dron_a1a3`) – vyřizuje se na počítači doma (vesnet://letectvi/),
# test A1/A3 je eTest `drony` (`Computer.record_test` → `drone_pass_test`). Klient spouští akce přes
# `player_action` a místní interactables; let, fyziku a legální kontroly dělá uzel `Drone`.

## Trvalý záznam stavu dronu daného modelu u hráče (vytvoří se při prvním dotazu).
func _drone_rec(pid: int, model: String) -> Dictionary:
	var st: Dictionary = drone_states.get(pid, {})
	if not st.has(model):
		st[model] = {"bat": float(DroneModel.spec(model)["batt"]), "dmg": 0.0}
		drone_states[pid] = st
	return st[model]


## Řádek do inventáře / obrazovek: baterie a poškození dronu daného modelu.
func drone_state_text(pid: int, model: String) -> String:
	var r := _drone_rec(pid, model)
	var sp := DroneModel.spec(model)
	var t := "Baterie %d %% · Poškození %d %%" % [roundi(float(r["bat"]) / float(sp["batt"]) * 100.0), roundi(float(r["dmg"]))]
	if float(r["dmg"]) >= Drone.CRASH_DMG:
		t += " – OPRAVIT u počítače!"
	return t


## Podmínky vzletu: {ok, why} – používá HUD (šedé tlačítko) i `drone_launch`.
func drone_launch_check(pid: int, model: String, in_menu := false) -> Dictionary:
	var p: Player = players.get(pid)
	var no := ""
	if not DroneModel.is_drone(model):
		no = "Tohle není dron."
	elif p == null:
		no = "Hráč není ve světě."
	elif p.drone != null:
		no = "Už jeden dron řídíš."
	elif p.item_count(model) <= 0:
		no = "Dron nemáš v batohu."
	elif p.controls_locked and not in_menu:      # zámek od otevřeného inventáře se při kliknutí na Vzlétnout uvolní
		no = "Právě nemáš volné ruce."
	elif drones.has(pid):
		var d2: Drone = drones[pid]
		no = "Dron už je ve světě%s." % (" – nejdřív ho seber" if d2 and not d2.flying() else "")
	elif p.car or p.horse or p.aircraft:
		no = "Nejdřív vystup z auta / sesedni z koně / z letouna."
	elif p.inside != "":
		no = "V interiéru nevzlétneš – jdi ven."
	elif p.busy:
		no = "Nejdřív dojez / dopij."
	elif p.fallen > 0.0:
		no = "Ležíš na zemi."
	elif float(_drone_rec(pid, model)["dmg"]) >= Drone.CRASH_DMG:
		no = "Dron je rozbitý – oprav ho na počítači doma (Letectví – ÚVL)."
	elif float(_drone_rec(pid, model)["bat"]) < 60.0:
		no = "Skoro prázdná baterie – nabij na počítači doma nebo vem náhradní."
	return {"ok": no == "", "why": no}


## Start dronu z batohu: postaví ho před hráče, připoutá pilota (kamera jen u lokálního), vzlet na ~2 m.
func drone_launch(pid: int, model: String) -> void:
	var chk := drone_launch_check(pid, model)
	if not chk["ok"]:
		notify(pid, "show_message", ["Nevzlétneš: %s" % chk["why"], 3.5])
		return
	var p: Player = players[pid]
	var fwd := Vector3(-sin(p.yaw), 0.0, -cos(p.yaw))
	var pos := p.global_position + fwd * 1.4
	pos.y = terrain.height_at(pos.x, pos.z) + 0.08
	var space := get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.3, 0), pos + Vector3(0, 2.4, 0), 1)
	if not space.intersect_ray(ray).is_empty():
		notify(pid, "show_message", ["Nad dronem je překážka – uhněte se na volné místo.", 3.0])
		return
	var sp := DroneModel.spec(model)
	var rec := _drone_rec(pid, model)
	var d := Drone.new()
	d.name = "Dron_%d" % pid
	add_child(d)
	d.setup(self, pid, model)
	d.park(pos, p.yaw)
	d.bat_s = float(rec["bat"])
	d.dmg = float(rec["dmg"])
	if p.item_count("dron_baterie") > 0 and d.bat_s < float(sp["batt"]) * 0.85:
		p.remove_item("dron_baterie")
		d.bat_s = float(sp["batt"])
		notify(pid, "show_message", ["Vyměněná baterie – plná.", 2.5])
	p.remove_item(model)
	drones[pid] = d
	d.take_off(p)
	var w := []
	if not has_permit(pid, "dron_provozovatel", pos):
		w.append("bez registrace provozovatele")
	if bool(sp["needs_a1a3"]) and not has_permit(pid, "dron_a1a3", pos):
		w.append("bez osvědčení A1/A3")
	if not w.is_empty():
		notify(pid, "police_banner", ["Letíš %s – vyřiď si to na počítači (Letectví – ÚVL), když tě uvidí, je pokuta!" % ", ".join(w), 6.0])
	emit_game_event(pid, "drone_takeoff", {"model": model})


## Sebrání dronu ze země zpět do batohu (E u ležícího dronu, i po přistání / havárii).
func drone_pickup(pid: int) -> void:
	var p: Player = players.get(pid)
	var d: Drone = drones.get(pid)
	if p == null or d == null or d.flying() or d.global_position.distance_to(p.global_position) > 2.6:
		return
	var st := d.to_inventory()          # odpoutá pilota, vrátí {bat, dmg}
	var rec := _drone_rec(pid, d.model)
	rec["bat"] = st["bat"]
	rec["dmg"] = st["dmg"]
	p.add_item(d.model)
	drones.erase(pid)
	d.queue_free()
	play_sfx(pid, "pickup")
	notify(pid, "show_message", ["Sebral jsi %s – baterie %d %%, poškození %d %%." % [
		DroneModel.spec(d.model)["name"], roundi(float(rec["bat"]) / float(DroneModel.spec(d.model)["batt"]) * 100.0),
		roundi(float(rec["dmg"]))], 3.0])
	emit_game_event(pid, "drone_pickup", {"model": d.model})


## Interakce E: sebrání vlastního zaparkovaného / rozbitého dronu (+ cizí drony v MP jen identifikace).
func drone_interactables(pid: int) -> Array:
	var p: Player = players.get(pid)
	var out := []
	if p == null or p.inside != "":
		return out
	for pid2 in drones.keys():
		var d: Drone = drones[pid2]
		if d == null or not is_instance_valid(d) or d.flying():
			continue
		if pid2 == pid:
			var sp := DroneModel.spec(d.model)
			out.append({"pos": d.global_position + Vector3(0, 0.4, 0), "r": 2.3, "kind": "custom",
				"text": "Sebrat %s (baterie %d %%)" % [sp["name"], roundi(d.bat_frac() * 100.0)],
				"action": func(id2: int): drone_pickup(id2)})
		elif d.global_position.distance_to(p.global_position) < 2.3:
			out.append({"pos": d.global_position + Vector3(0, 0.4, 0), "r": 2.3, "kind": "custom",
				"text": "Cizí dron (%s)" % DroneModel.spec(d.model)["name"],
				"action": func(id2: int): notify(id2, "show_message", ["Není tvůj – zavolej majiteli.", 2.5])})
	return out


## Fotka z dronu (O nebo LMB za letu): klient stáhne snímek obrazovky, questy/eventy to slyší.
func drone_photo(pid: int) -> void:
	var p: Player = players.get(pid)
	var d: Drone = drones.get(pid)
	if p == null or d == null or not d.flying() or d.pilot != p:
		return
	d.photo_t += 1
	play_sfx(pid, "shutter", 1.0, -2.0)
	emit_game_event(pid, "drone_photo", {"n": d.photo_t, "alt": d.agl()})
	var cl = clients.get(pid)
	if cl and cl.has_method("drone_photo"):
		cl.drone_photo()


## Odpoutání a zničení uzlu dronu (odpojení hráče, před načtením save). Nevrací stav do inventáře.
func drone_release_all(pid: int) -> void:
	var d: Drone = drones.get(pid)
	if d:
		d.release()
		d.queue_free()
		drones.erase(pid)


## Nabíjení na počítači doma (vesnet://letectvi/): baterie se nabije do plna. Vrací text výsledku.
func drone_charge(pid: int, model: String) -> String:
	var p: Player = players.get(pid)
	if p == null:
		return ""
	if p.inside == "":
		return "Nabíječka je doma u počítače – pojď dovnitř."
	if p.item_count(model) <= 0 and not (drones.has(pid) and (drones[pid] as Drone).model == model):
		return "Dron %s tu nemáš." % DroneModel.spec(model)["name"]
	var rec := _drone_rec(pid, model)
	rec["bat"] = float(DroneModel.spec(model)["batt"])
	return "Baterie nabitá na 100 %."


## Oprava dronu po havárii (PC → Letectví): platba z účtu, případně hotově. Vrací text výsledku.
func drone_repair(pid: int, model: String) -> String:
	var p: Player = players.get(pid)
	if p == null:
		return ""
	var rec := _drone_rec(pid, model)
	var dmg: float = rec["dmg"]
	if dmg <= 0.0:
		return "Není co opravovat."
	var cost: int = int(DroneModel.spec(model)["repair"])
	if p.bank >= cost:
		p.bank -= cost
	elif p.money >= cost:
		p.money -= cost
	else:
		return "Oprava stojí %s – tolik nemáš (účet ani hotovost)." % Bazaar.kc(cost)
	rec["dmg"] = 0.0
	emit_game_event(pid, "drone_repaired", {"model": model})
	return "Opraveno za %s – dron je jako nový." % Bazaar.kc(cost)


## Registrace provozovatele na ÚVL (zdarma, okamžité). Vrací text pro stavový řádek.
func drone_register(pid: int) -> String:
	if permits == null:
		return "Síť je nedostupná."
	if permits.has(pid, "dron_provozovatel"):
		return "Už jsi registrovaný: %s." % permits.number(pid, "dron_provozovatel")
	var no := "CZ-DB-%04d" % pid
	permits.grant(pid, "dron_provozovatel", no)
	send_mail(pid, "ÚVL – portál bezpilotních letů", "Registrace provozovatele potvrzena",
		"Dobrý den,\nvaše registrace provozovatele UAS byla přijata.\nRegistrační číslo: [b]%s[/b] – vyznačte ho na dronu.\n\n" % no +
		"Připomínky: dron s kamerou = povinná registrace; nad 250 g test A1/A3; max. 120 m; ne nad lidmi; " +
		"dohled (VLOS); soukromí na cizích pozemcích.\n(Zjednodušená herní simulace.)")
	notify(pid, "show_message", ["Registrace přijata: %s (potvrzení přišlo e-mailem)." % no, 4.0])
	emit_game_event(pid, "drone_registered", {"no": no})
	return "Registrováno: %s" % no


## Složený eTest „drony“ (A1/A3) – volá `Computer.record_test` při úspěchu. Vrací text výsledku.
func drone_pass_test(pid: int) -> String:
	if permits == null:
		return ""
	if permits.has(pid, "dron_a1a3"):
		return "Osvědčení A1/A3 už máš."
	var no := "A1A3-%04d" % pid
	permits.grant(pid, "dron_a1a3", no)
	send_mail(pid, "ÚVL – portál bezpilotních letů", "Osvědčení A1/A3 vystaveno",
		"Gratulujeme – online test jsi složil.\nOsvědčení: [b]%s[/b] (otevřená podkategorie A1/A3).\n" % no +
		"Teď smíš legálně létat i s drony nad 250 g – 120 m a pravidla stále platí.\n(Zjednodušená herní simulace.)")
	notify(pid, "police_banner", ["Osvědčení A1/A3 vystaveno: %s" % no, 4.0])
	emit_game_event(pid, "drone_a1a3", {"no": no})
	return "Osvědčení %s vystaveno" % no


## Stav flotily pro obrazovku Letectví – ÚVL: [{model, name, bat(0..1), dmg, v_ruce, ve_svete}].
func drone_fleet(pid: int) -> Array:
	var p: Player = players.get(pid)
	var out := []
	for m in DroneModel.ids():
		var rec := _drone_rec(pid, m)
		var in_inv := p != null and p.item_count(m) > 0
		var in_world: bool = drones.has(pid) and (drones[pid] as Drone).model == m
		if not in_inv and not in_world and float(rec["bat"]) >= float(DroneModel.spec(m)["batt"]) and float(rec["dmg"]) <= 0.0:
			continue            # nikdy neměl – neukazovat
		out.append({"model": m, "name": DroneModel.spec(m)["name"], "bat": float(rec["bat"]) / float(DroneModel.spec(m)["batt"]),
			"dmg": float(rec["dmg"]), "v_ruce": in_inv, "ve_svete": in_world})
	return out


## Uložení: {fleet: {model: {bat, dmg}}, world: {model, pos, yaw, bat, dmg}|null}.
func drones_to_dict(pid: int) -> Dictionary:
	var fleet := {}
	for m in drone_states.get(pid, {}):
		var r: Dictionary = drone_states[pid][m]
		fleet[m] = {"bat": float(r["bat"]), "dmg": float(r["dmg"])}
	var w: Variant = null
	var d: Drone = drones.get(pid)
	if d:
		w = d.save_dict()
		if d.mode != "zemi":      # save ve vzduchu / ve stromu = jako by přistál pod sebou
			var pos: Array = w["pos"]
			pos[1] = terrain.height_at(float(pos[0]), float(pos[2])) + 0.08
			w["pos"] = pos
		fleet[d.model] = {"bat": float(w["bat"]), "dmg": float(w["dmg"])}   # živý stav uzlu přepíše zastaralý záznam
	return {"fleet": fleet, "world": w}


## Načtení (starý save bez klíče = žádné drony). Nejprv zruší současné uzly.
func drones_from_dict(pid: int, d: Dictionary) -> void:
	drone_release_all(pid)
	drone_states[pid] = {}
	for m in d.get("fleet", {}):
		if not DroneModel.is_drone(String(m)):
			continue
		var r: Dictionary = d["fleet"][m]
		drone_states[pid][String(m)] = {"bat": float(r.get("bat", DroneModel.spec(String(m))["batt"])),
			"dmg": float(r.get("dmg", 0.0))}
	var w = d.get("world", null)
	if w is Dictionary and DroneModel.is_drone(String(w.get("model", ""))):
		var pos: Array = w.get("pos", [0, 0, 0])
		var dr := Drone.new()
		dr.name = "Dron_%d" % pid
		add_child(dr)
		dr.setup(self, pid, String(w["model"]))
		dr.park(Vector3(float(pos[0]), float(pos[1]), float(pos[2])), float(w.get("yaw", 0.0)))
		dr.bat_s = float(w.get("bat", DroneModel.spec(dr.model)["batt"]))
		dr.dmg = float(w.get("dmg", 0.0))
		drones[pid] = dr


# ------------------------------------------------------------------ svědci (M4.4)

## Jednotný systém svědků (M4.4): `witness_check` vrací kandidáty, kteří čin vidí nebo slyší, a zda ho nahlásí.
## Zkratky `witness_seen` (někdo vidí) a `witness_reported` (někdo nahlásí). Další zdroje (hajný, stráže – M4.6)
## přidá `add_witness_source(fn)`, `fn(id, pos, see_r, hear_r) -> Array` vrací kandidáty `{node, name, persona, role}`.
const WITNESS_CONE_COS := 0.17           # cos 80° – NPC vidí zhruba do přední poloviny (±80°)
const WITNESS_FOG_K := 0.6               # plná mlha sníží dohled o tolik (podíl)
const WITNESS_FRIEND_MIN := 60.0         # přátelství, od kterého skoro nikdy nenahlásí
const WITNESS_FRIEND_P := 0.05           # šance nahlášení u přítele
const WITNESS_DEFAULT_P := 0.4           # šance nahlášení, když povaha není v Weapons.CALL_P
const UNREPORTED_MAX := 50               # nenahlášených činů na hráče (nejstarší se zahazují)


## Dohled podle denní doby (den 1,0 / šero 0,5 / noc 0,25) × mlha.
func _witness_light() -> float:
	var f := 1.0
	if clock:
		var d := clock.daylight()
		f = 1.0 if d >= 0.8 else (0.5 if d >= 0.35 else 0.25)
	if weather:
		f *= 1.0 - WITNESS_FOG_K * clampf(weather.fog, 0.0, 1.0)
	return f


## Kdo čin uvidí / uslyší. Vrací [{node, name, persona, sees, hears, reports}] jen pro ty, kdo vidí nebo slyší.
## Vidí: vzdálenost ≤ see_r × světlo a zorný kužel (NPC zhruba dopředu). Slyší: ≤ hear_r, bez kuželu.
## Nahlásí: podle povahy (`Weapons.CALL_P`), přítele (≥ 60) skoro nikdy; policejní hlídka vždy.
## Zatím bez raycastu na zdi (dotaz do fyziky mimo fyzikální krok není bezpečný) – viz otevřené body.
func witness_check(id: int, pos: Vector3, kind: String, see_r: float, hear_r := 0.0) -> Array:
	var cands: Array = []
	if bots_root:
		for v in bots_root.get_children():
			if v is Villager:
				var vp: Persona = (v as Villager).persona
				cands.append({"node": v, "name": vp.display_name() if vp else "vesničan", "persona": vp, "role": "vesnice"})
	for k in places:
		var pl: Place = places[k]
		if pl.keeper != null and is_instance_valid(pl.keeper) and not pl.player_inside:
			cands.append({"node": pl.keeper, "name": "obsluha (%s)" % String(k), "persona": pl.keeper.persona, "role": "obsluha"})
	if police and police.patrol != null and is_instance_valid(police.patrol):
		cands.append({"node": police.patrol, "name": "policejní hlídka", "persona": null, "role": "policie"})
	for src in witness_sources:
		if src.is_valid():
			cands.append_array(src.call(id, pos, see_r, hear_r))
	var light := _witness_light()
	var out: Array = []
	for c in cands:
		var n: Node3D = c.get("node")
		if n == null or not is_instance_valid(n):
			continue
		var to := pos - n.global_position
		var sees := false
		if to.length() <= see_r * light:
			var f2 := Vector2(-n.global_transform.basis.z.x, -n.global_transform.basis.z.z)
			var t2 := Vector2(to.x, to.z)
			sees = t2.length() < 1.0 or f2.length() < 0.01 or f2.normalized().dot(t2.normalized()) >= WITNESS_CONE_COS
		var hears := to.length() <= hear_r
		if not sees and not hears:
			continue
		var persona: Persona = c.get("persona")
		var reports := false
		if String(c.get("role", "")) == "policie":
			reports = true
		else:
			var p := WITNESS_DEFAULT_P
			if persona:
				p = float(Weapons.CALL_P.get(String(persona.profile.get("trait", "")), WITNESS_DEFAULT_P))
				if persona.get_friendship(id) >= WITNESS_FRIEND_MIN:
					p = WITNESS_FRIEND_P
			reports = randf() < p
		out.append({"node": n, "name": String(c.get("name", "")), "persona": persona, "sees": sees, "hears": hears, "reports": reports})
	return out


## Někdo čin vidí (kandidát se `sees`).
func witness_seen(id: int, pos: Vector3, kind: String, see_r: float, hear_r := 0.0) -> bool:
	for w in witness_check(id, pos, kind, see_r, hear_r):
		if w["sees"]:
			return true
	return false


## Někdo čin nahlásí (kandidát se `reports`) – vede k přestupku hned, jinak zůstane nenahlášený.
func witness_reported(id: int, pos: Vector3, kind: String, see_r: float, hear_r := 0.0) -> bool:
	for w in witness_check(id, pos, kind, see_r, hear_r):
		if w["reports"]:
			return true
	return false


## Přidá zdroj svědků (M4.6: hajný, stráže). `fn(id, pos, see_r, hear_r) -> Array` vrací kandidáty ve tvaru výše.
func add_witness_source(fn: Callable) -> void:
	if not witness_sources.has(fn):
		witness_sources.append(fn)


## Zapíše nenahlášený čin hráče (zjistí ho později hajný / policie přes `pending_offenses`).
func add_unreported(id: int, entry: Dictionary) -> void:
	var list: Array = unreported.get(id, [])
	list.append(entry)
	if list.size() > UNREPORTED_MAX:
		list = list.slice(list.size() - UNREPORTED_MAX)
	unreported[id] = list


## Nenahlášené činy hráče (položky jako v `Forestry._check_law`).
func pending_offenses(id: int) -> Array:
	return unreported.get(id, [])


## Uplatní nenahlášený čin `idx` (zjištěn): zapíše přestupky přes `commit_offense` a čin odstraní.
func commit_pending(id: int, idx: int) -> void:
	var list: Array = unreported.get(id, [])
	if idx < 0 or idx >= list.size():
		return
	var e: Dictionary = list[idx]
	list.remove_at(idx)
	unreported[id] = list
	for oid in e.get("offenses", []):
		commit_offense(id, String(oid), {"severity": float(e.get("severity", 0.0))})


## Svědek, kdo dronu uvidí/uslyší (vesničané, obsluhy míst, hlídka, jiní hráči) do ~150 m vodorovně.
## Využívá `Drone._offense` – přestupek se píše jen když dron někoho upoutal. `ignore_pid` = vlastní pilot
## (letí sám u sebe – sám sebe za svědka nepočítá, jinak by přestupek padl vždy).
func drone_witnessed(pos: Vector3, ignore_pid := -1) -> bool:
	var p2 := Vector2(pos.x, pos.z)
	if witness_seen(ignore_pid, pos, "dron", 150.0):     # vesničané a obsluhy míst (M4.4 witness_check)
		return true
	if police and police.patrol != null and is_instance_valid(police.patrol) \
			and Vector2(police.patrol.global_position.x, police.patrol.global_position.z).distance_to(p2) < 400.0:
		return true
	if police and police.checkpoint_cop != null and is_instance_valid(police.checkpoint_cop) \
			and Vector2(police.checkpoint_cop.global_position.x, police.checkpoint_cop.global_position.z).distance_to(p2) < 200.0:
		return true
	for pid in players:
		if pid == ignore_pid:
			continue
		var pl2: Player = players[pid]
		if pl2 and Vector2(player_world_pos(pl2).x, player_world_pos(pl2).z).distance_to(p2) < 150.0:
			return true
	return false


## Je pod dronem osoba do `r` m vodorovně (vlastní pilot se nepočítá – nad sebe nelétá zlovolně)?
func drone_person_under(pos: Vector3, r: float) -> bool:
	var p2 := Vector2(pos.x, pos.z)
	if bots_root:
		for v in bots_root.get_children():
			if v is Villager and Vector2(v.global_position.x, v.global_position.z).distance_to(p2) < r:
				return true
	for k in places:
		var pl: Place = places[k]
		if pl.keeper != null and is_instance_valid(pl.keeper) and not pl.player_inside \
				and Vector2(pl.keeper.global_position.x, pl.keeper.global_position.z).distance_to(p2) < r:
			return true
	if police and police.checkpoint_cop != null and is_instance_valid(police.checkpoint_cop) \
			and Vector2(police.checkpoint_cop.global_position.x, police.checkpoint_cop.global_position.z).distance_to(p2) < r:
		return true
	for pid in players:
		var pl2: Player = players[pid]
		if pl2 and not (drones.has(pid) and drones[pid] is Drone and (drones[pid] as Drone).pilot == pl2) \
				and Vector2(player_world_pos(pl2).x, player_world_pos(pl2).z).distance_to(p2) < r:
			return true
	return false
