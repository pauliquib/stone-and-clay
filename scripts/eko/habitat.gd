## M8.15 Ekologie a populace zvěře (`World.habitat`, přepínač realismu `habitat`, 00_PRINCIPY kap. 3).
##
## Podle čeho: **index vhodnosti stanoviště (HSI)** z krytu, potravy a klidu (US FWS HSI modely, zjednodušeně),
## denní cyklus aktivity (lože ve dne v krytu, soumrak na pastvě), **logistický růst populace s kapacitou** K = Σ HSI × hustota
## (srnec 10–30 ks / 100 ha, prase 2–15 podle semenného roku, zajíc 5–30 – orientačně, ověřit), pulz rozmnožování, zimní
## úmrtnost podle sněhu, mrazu a krmelců, lov (hráč + plán myslivců) a srážky s auty. Semenné roky dubu a buku (mast years)
## deterministicky 1× za 3–6 let.
##
## Mřížka `CELL` (64 m) přes celý terén:
##  - **statické vrstvy** (jednou po startu, po kouscích `EcoClock.slice`): les / okraj / zástavba / silnice (z `Fauna`), stromy v buňce
##    (`TreeManager.ids_near` + `TreeEco` – mladé porosty = houštiny, podíl dubu a buku = žaludy a bukvice, jehličnany = zimní kryt),
##    zápoj (`TreeEco.canopy_at`), voda, závětří a zimní oslunění, mrazová kotlina (`Site`), pole a louky (`Fields.class_at`);
##  - **denní vrstvy** (`World.eco_day`, po kouscích): pro srnce, prase a zajíce skóre **odpočinku** (kryt × klid × zimní závětří)
##    a **pastvy** (louky a ozimy, okus, žaludy/bukvice, kukuřice v mléčné zralosti, krmelce v zimě, sníh ubírá), plus HSI pro kapacitu.
##
## API (kontrakt pro M8.18 a zvěř): `active()`, `suitability(druh, pos, hodina, doy)`, `best_nearby(druh, pos, poloměr, účel)`
## („rest“ / „feed“ / „water“), `rest_at`, `feed_at`, `density(druh, pos)` (ks / 100 ha), `spawn_roll`, `pick_weight`,
## `on_death(druh, pos, příčina, …)`, `disturb(pos, síla)`, `note_trail(a, b)`, `trail_at`, `grass_height_at`, `mast_now()`,
## `browse_pressure(pos)`, `bait_active()`, `rumor()`, `journal_text(pid)`, `population_text()`, `to_dict/restore` (klíč `wildlife`).
## Fallback (vypnuto / mřížka ještě není): `active()` = false → zvěř se chová jako dřív (Fauna.score, pevné okrsky).
class_name Habitat
extends RefCounted

const CELL := 64.0
const CELL_HA := CELL * CELL / 10000.0
const SP := ["srnec", "divocak", "zajic"]          # index druhu v mřížkách (sele = divocak)
const AREAS := 4                                    # honitby: kvadranty mřížky
const AREA_NAMES := ["Honitba I", "Honitba II", "Honitba III", "Honitba IV"]
const MAST_IDS := ["dub_zimni", "dub_letni", "buk"]
const CONIFER_IDS := ["smrk", "borovice", "jedle", "modrin"]
const ROOT_MAX := 48                                # nejvýš tolik rozrytých míst najednou (vizuál)
const SAVE_V := 1

## --- laditelné (F3 → Zvěř/Stanoviště a populace, `scripts/dev/tune_m8_15.gd`) – výchozí = návrh M8.15
# mřížka a takt
static var STATIC_PER_FRAME := 48       # buněk statické mřížky za snímek (stromy v buňce)
static var DAY_PER_FRAME := 32          # buněk denního přepočtu za snímek
static var TREE_R := 40.0               # m – stromy buňky se hledají v tomto okruhu od středu
static var TREES_MAX := 160             # nejvýš tolik stromů na buňku (víc = krok přes)
static var YOUNG_AGE := 25              # let – mladý porost (houština, okus)
static var DENSE_TREES := 40.0          # stromů v okruhu TREE_R = plně zarostlé
# klid
static var Q_SETTLE := 1.6              # klid − zástavba × tohle
static var Q_ROAD := 0.45               # klid − silnice × tohle
static var Q_DISTURB := 0.6             # klid − rušení (výstřely, lov) × tohle
static var DISTURB_DECAY := 0.85        # rušení × tohle za den
static var DISTURB_SHOT := 0.6          # výstřel / úlovek přidá tolik (buňka, sousedé polovinu)
# kryt
static var COVER_FOREST_BASE := 0.4     # kryt lesa bez podrostu
static var COVER_THICKET := 0.6         # + houština (mladý porost) × tohle
static var COVER_CONIFER_WINTER := 0.5  # v zimě + jehličnany × tohle
static var COVER_CROP_FULL_M := 1.2     # m – porost pole od této výšky = plný kryt
static var COVER_CROP_MAX := 0.85       # kryt ve vysokém obilí / kukuřici nejvýš
static var COVER_GRASS_FULL_M := 0.7    # m – tráva louky = kryt od této výšky
static var COVER_GRASS_MAX := 0.5
static var SHELTER_WINTER := 0.45       # v zimě odpočinek × (1 − tohle + tohle × závětří)
static var COLD_POOL_PEN := 0.5         # za mrazu − mrazová kotlina × tohle (srnci výš na svazích, inverze M8.9)
static var FROST_FROM_C := -3.0         # °C – od této teploty (průměr dne) platí postih kotliny
static var EDGE_FEED_K := 0.6           # pastva u lesa: × (1 + okraj × tohle) (srnec)
static var OPEN_FEED_FOREST := 0.8      # zajíc: pastva × (1 − les × tohle)
# potrava
static var GRASS_MONTH := [0.15, 0.15, 0.3, 0.75, 1.0, 0.9, 0.7, 0.65, 0.6, 0.5, 0.3, 0.2]   # pastva louky po měsících
static var BROWSE_SRNEC := 0.55         # okus mladých stromků a keřů (srnec, les × houština)
static var BROWSE_WINTER_K := 1.3       # v zimě okus × tohle
static var ROOT_BASE := 0.3             # prase: rytí v lese (základ)
static var ROOT_MOIST := 0.4            # + vlhkost půdy × tohle
static var MAST_FEED := 1.0             # prase: žaludy a bukvice × tohle
static var MAST_FEED_SRNEC := 0.35      # srnec si žaludy také vezme
static var ROOT_MEADOW := 0.55          # prase: rytí na louce u lesa (okraj × vlhkost × tohle)
static var FEEDER_R := 160.0            # m – krmelec v zimě přitahuje do této vzdálenosti
static var FEEDER_FEED := 0.9           # pastva u aktivního krmelce
static var SNOW_FOOD_M := 0.4           # m sněhu = potrava pod ním nedostupná (lineárně)
static var SNOW_FOOD_MIN := 0.25        # … nejvýš ubere 1 − tohle
static var WATER_R := 300.0             # m – voda dál = 0
# potrava na poli: plodina → [srnec, prase, zajíc] (zelená / zrno / strniště)
static var CROP_GREEN := {"psenice": [0.9, 0.1, 0.9], "jecmen": [0.6, 0.1, 0.7], "repka": [0.9, 0.05, 0.8],
	"kukurice": [0.2, 0.3, 0.3], "slunecnice": [0.3, 0.4, 0.4], "picniny": [1.0, 0.3, 1.0]}
static var CROP_GRAIN := {"psenice": [0.3, 0.6, 0.4], "jecmen": [0.3, 0.5, 0.4], "repka": [0.2, 0.2, 0.2],
	"kukurice": [0.3, 1.0, 0.3], "slunecnice": [0.2, 0.7, 0.3], "picniny": [1.0, 0.3, 1.0]}
static var STUBBLE_FOOD := [0.3, 0.35, 0.4]
# semenné roky
static var MAST_MIN_GAP := 3            # let mezi semennými roky nejméně …
static var MAST_GAP_SPAN := 4           # … + 0..tohle−1 (3–6 let)
static var MAST_POOR := 0.1             # úroda žaludů rok po semenném roce
static var MAST_NORMAL := 0.3           # běžný rok (± MAST_JITTER)
static var MAST_JITTER := 0.15
static var MAST_FROM_DOY := 245.0       # od tohoto dne padají žaludy a bukvice (bez fenologie)
static var MAST_EAT_D := 0.012          # zásoba žaludů ubývá za den (sežráno, sníh, klíčení)
static var MAST_SPROUT_DOY := 140.0     # od tohoto dne zbytky vyklíčily (zásoba 0)
# populace (ks / 100 ha při HSI = 1)
static var DENS_MAX := [50.0, 20.0, 40.0]
static var INIT_FILL := [0.5, 0.5, 0.6]         # start: podíl kapacity
static var FEMALE_SHARE := [0.55, 0.45, 0.5]
static var LITTER := [1.7, 5.0, 3.5]            # mláďat na samici a rok (zajíc: součet vrhů po přežití)
static var BIRTH_DOY := [[130.0, 180.0], [60.0, 150.0], [70.0, 260.0]]   # srnčata V–VI, selata III–V, zajíci III–IX
static var MAST_BIRTH_K := 0.5                  # prase: vrh × (1 − tohle + tohle × 2 × žaludy loni)
static var MORT_BASE := [0.10, 0.15, 0.45]      # přirozená úmrtnost za rok
static var MORT_WINTER := [0.15, 0.10, 0.10]    # navíc za tvrdou zimu (sníh, mráz)
static var MORT_CROWD := 0.5                    # nad kapacitou: (n − K) / K × tohle za rok
static var FEEDER_RELIEF := 0.6                 # krmelec v honitbě ubere zimní úmrtnosti (srnec, zajíc) až tolik
static var MAST_RELIEF := 0.6                   # žaludy ubírají zimní úmrtnost prasat až o tolik
static var WINTER_SNOW_M := 0.3                 # m sněhu = plná tvrdost zimy (×0,6)
static var WINTER_COLD_C := 10.0                # °C pod nulou = plná tvrdost (×0,4)
static var CULL_QUOTA := [0.30, 0.6, 0.10]      # plán myslivců: podíl stavu za rok
static var CULL_MONTHS := [[5, 6, 7, 8, 9, 10, 11, 12], [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12], [11, 12]]
static var CULL_PRASE_REF := 5.0                # ks / 100 ha – víc prasat → víc nočních čekaných (plán × hustota / tohle, 0,5–2)
static var ROAD_MORT := [0.05, 0.02, 0.08]      # srážky s auty za rok × silnice v honitbě (podíl buněk × 5)
# škody prasat
static var ROOT_P := 0.06               # šance rozrytí louky u lesa za den a buňku (× hustota / CULL_PRASE_REF)
static var ROOT_DAYS := 40              # dnů, než rozrytá louka zaroste
static var DAMAGE_RUMOR := 3.0          # škod za týden v honitbě → drb
static var CORN_DAMAGE_K := 0.02        # škoda na kukuřici za den a buňku × pastva prasat
static var BAIT_DAMAGE := 2.0           # škod za týden → myslivec vnadí prasata k posedu (noční čekaná)
static var RESPECT_HELP := 1.0          # respekt zemědělců za legální úlovek prasete při škodách
# setkání u hráče
static var SPAWN_K := 0.9               # šance skupiny = očekávané skupiny v okolí × tohle
static var SPAWN_P_MIN := 0.12
static var SPAWN_R := 220.0             # m – okolí pro očekávaný počet
static var GROUP_MEAN := [2.5, 5.0, 1.0]
static var DENS_REF := [15.0, 5.0, 12.0]   # referenční hustota (váha druhu při výběru)
# pohyb
static var BEST_JITTER := 0.25          # výběr cíle: + náhoda do tolika (ať nejdou všichni do jedné buňky)
static var BEST_DIST_PEN := 0.25        # − vzdálenost / poloměr × tohle
static var BEST_R_MAX := 640.0          # m – nejdál hledá cíl
static var TRAIL_ADD := 0.15            # ochoz: průchod přidá tolik do buněk na spojnici
static var TRAIL_DECAY := 0.97          # ochoz × tohle za den
# vysoká tráva (bez M8.14)
static var GRASS_H_MONTH := [0.05, 0.05, 0.1, 0.25, 0.55, 0.7, 0.35, 0.4, 0.35, 0.2, 0.1, 0.05]
static var BROWSE_PRESSURE_K := 0.25    # okus sazenic: šance = hustota srnců / ref × vhodnost × tohle

var world: World
var ready_static := false
var nx := 0
var nz := 0
var x0 := 0.0
var z0 := 0.0
# statické vrstvy (index buňky iz * nx + ix)
var s_valid := PackedByteArray()
var s_forest := PackedFloat32Array()
var s_edge := PackedFloat32Array()
var s_settle := PackedFloat32Array()
var s_road := PackedFloat32Array()
var s_thicket := PackedFloat32Array()
var s_mast := PackedFloat32Array()
var s_conif := PackedFloat32Array()
var s_water := PackedFloat32Array()
var s_shelter := PackedFloat32Array()
var s_cold := PackedFloat32Array()
var s_arable := PackedFloat32Array()
var s_meadow := PackedFloat32Array()
var s_field := PackedInt32Array()
var s_area := PackedByteArray()
var _insw := PackedFloat32Array()
var _wexp := PackedFloat32Array()
# denní vrstvy (3 druhy × buňky)
var d_rest := PackedFloat32Array()
var d_feed := PackedFloat32Array()
var d_hsi := PackedFloat32Array()
var d_disturb := PackedFloat32Array()
var d_trail := PackedFloat32Array()
var day_done_jd := -1
var _pass_running := false
var _k_acc := PackedFloat32Array()       # AREAS × 3 – součet HSI v průchodu
var _snow_acc := PackedFloat32Array()    # AREAS – průměrný sníh v průchodu
var _cells_area := PackedFloat32Array()  # AREAS – počet buněk
var _feeder_area := PackedFloat32Array() # AREAS – krmelec v honitbě (0/1)
var _road_acc := PackedFloat32Array()    # AREAS – průměrná „silničnost“ buněk honitby (statická)
var _insw_sum := 0.0
var _insw_n := 0
var _insw_mean := 150.0
# kontext denního průchodu
var _p_doy := 1.0
var _p_month := 1
var _p_year := 2026
var _p_winter := false
var _p_frost := false
var _p_mast := 0.0
var _p_feeders: Array[Vector3] = []
var _p_jd := 0
var _cf := PackedFloat32Array([0.0, 0.0, 0.0])
var _ch := 0.0
# populace a stav
var pop := []                          # AREAS × 3 slovníků {n, young, k, lov, auto, zima, plan}
var pop_ready := false
var last_pop_jd := -1
var mast_store := 0.0                  # žaludy a bukvice na zemi 0..1
var mast_force_year := -1              # F2: vynucený semenný rok
var damage := []                       # AREAS × [jd škody…] (posledních 14 dní)
var corn_damage := PackedFloat32Array()
var rooted: Array = []                 # [x, z, jd, poloměr]
var rooted_ver := 0
var _rumor := ""
var _rumor_jd := -1
var _event_jd := -1
var _mast_cache_y := -99999
var _mast_cache_v := 0.0


func setup(w: World) -> void:
	world = w
	var f: Fauna = w.fauna
	if f == null or w.terrain == null:
		return
	x0 = f.gx0
	z0 = f.gz0
	nx = int(ceil(f.nx * Fauna.CELL / CELL))
	nz = int(ceil(f.nz * Fauna.CELL / CELL))
	var n := nx * nz
	# Packed pole jsou hodnotové typy – každé zvlášť (smyčka by měnila kopie)
	s_forest.resize(n)
	s_edge.resize(n)
	s_settle.resize(n)
	s_road.resize(n)
	s_thicket.resize(n)
	s_mast.resize(n)
	s_conif.resize(n)
	s_water.resize(n)
	s_shelter.resize(n)
	s_cold.resize(n)
	s_arable.resize(n)
	s_meadow.resize(n)
	_insw.resize(n)
	_wexp.resize(n)
	d_disturb.resize(n)
	d_trail.resize(n)
	s_valid.resize(n)
	s_area.resize(n)
	s_field.resize(n)
	d_rest.resize(n * 3)
	d_feed.resize(n * 3)
	d_hsi.resize(n * 3)
	_k_acc.resize(AREAS * 3)
	_snow_acc.resize(AREAS)
	_cells_area.resize(AREAS)
	_feeder_area.resize(AREAS)
	_road_acc.resize(AREAS)
	corn_damage.resize(AREAS)
	_init_pop()
	w.eco_day.connect(_on_eco_day)
	if w.eco != null:
		w.eco.slice(n, STATIC_PER_FRAME, _static_cell)


func _init_pop() -> void:
	pop.clear()
	damage.clear()
	for a in AREAS:
		var row := []
		for s in 3:
			row.append({"n": 0.0, "young": 0.0, "k": 0.0, "lov": 0, "auto": 0, "zima": 0.0, "plan": 0.0, "hrac": 0})
		pop.append(row)
		damage.append([])


## Zapnuto (přepínač `habitat`) a statická mřížka je hotová.
func active() -> bool:
	return ready_static and world != null and world.realism_on("habitat")


static func sp_index(species: String) -> int:
	match species:
		"srnec": return 0
		"divocak", "sele": return 1
		"zajic": return 2
	return -1


func _ci(x: float, z: float) -> int:
	var ix := int(floor((x - x0) / CELL))
	var iz := int(floor((z - z0) / CELL))
	if ix < 0 or iz < 0 or ix >= nx or iz >= nz:
		return -1
	return iz * nx + ix


func _cx(i: int) -> float:
	return x0 + (float(i % nx) + 0.5) * CELL


func _cz(i: int) -> float:
	return z0 + (float(i / nx) + 0.5) * CELL


# ------------------------------------------------------------------ statická mřížka (jednou, po kouscích)

func _static_cell(i: int) -> void:
	var x := _cx(i)
	var z := _cz(i)
	var f: Fauna = world.fauna
	var ix := i % nx
	var iz := i / nx
	s_area[i] = (1 if ix >= nx / 2 else 0) + (2 if iz >= nz / 2 else 0)
	if not world.terrain.contains(x, z, 30.0):
		s_valid[i] = 0
		if i == nx * nz - 1:
			_static_done()
		return
	s_valid[i] = 1
	var fo := 0.0
	var st := 0.0
	var rd := 0.0
	for k in 4:
		var sx := x + (-16.0 if k % 2 == 0 else 16.0)
		var sz := z + (-16.0 if k < 2 else 16.0)
		fo += f.forest_at(sx, sz)
		st += f.settle_at(sx, sz)
		rd += f.road_at(sx, sz)
	s_forest[i] = fo * 0.25
	s_settle[i] = st * 0.25
	s_road[i] = rd * 0.25
	s_edge[i] = clampf(f.score("edge", x, z), 0.0, 1.0)
	# stromy v buňce: houštiny, žaludy / bukvice, jehličnany
	var thick := 0.0
	var mast := 0.0
	var conif := 0.0
	var te: TreeEco = world.tree_eco
	if world.trees != null and s_forest[i] > 0.05:
		var ids: PackedInt32Array = world.trees.ids_near(Vector3(x, 0.0, z), TREE_R)
		var cnt := ids.size()
		if cnt > 0:
			var step := maxi(1, cnt / maxi(TREES_MAX, 1))
			var seen := 0
			var young := 0
			var nm := 0
			var nc := 0
			var j := 0
			while j < cnt:
				var ti := ids[j]
				j += step
				seen += 1
				var sid := te.species(ti) if te != null else ""
				if sid in MAST_IDS:
					nm += 1
				elif sid in CONIFER_IDS:
					nc += 1
				if te != null and te.age(ti) <= YOUNG_AGE:
					young += 1
			var dense := clampf(float(cnt) / DENSE_TREES, 0.0, 1.0)
			if seen > 0:
				thick = float(young) / seen * dense
				mast = float(nm) / seen * dense
				conif = float(nc) / seen * dense
	s_thicket[i] = thick
	s_mast[i] = mast
	s_conif[i] = conif
	# stanoviště (Site má vlastní fallback hodnoty)
	var site: Site = world.site
	if site != null:
		s_water[i] = clampf(1.0 - site.dist_water(x, z) / WATER_R, 0.0, 1.0)
		_wexp[i] = site.wind_exp(x, z)
		_insw[i] = site.insol_winter(x, z)
		s_cold[i] = site.cold_pool(x, z)
	else:
		_wexp[i] = 0.5
		_insw[i] = 150.0
	# pole a louky
	var fl: Fields = world.fields
	var ar := 0.0
	var me := 0.0
	if fl != null and fl.loaded:
		for k in 4:
			var sx := x + (-16.0 if k % 2 == 0 else 16.0)
			var sz := z + (-16.0 if k < 2 else 16.0)
			var c := fl.class_at(sx, sz)
			if c == 1:
				ar += 0.25
			elif c == 2:
				me += 0.25
		s_field[i] = fl.field_at(x, z)
	s_arable[i] = ar
	s_meadow[i] = me
	_insw_sum += _insw[i]
	_insw_n += 1
	_cells_area[s_area[i]] += 1.0
	_road_acc[s_area[i]] += s_road[i]
	if i == nx * nz - 1:
		_static_done()


## Konec statického průchodu: jen souhrny honiteb (žádná smyčka přes celou mřížku v jednom snímku).
## Závětří (`s_shelter`) se dopočítá v denním průchodu, až je znám průměr zimního oslunění.
func _static_done() -> void:
	_insw_mean = _insw_sum / maxf(float(_insw_n), 1.0)
	for a in AREAS:
		_road_acc[a] = _road_acc[a] / maxf(_cells_area[a], 1.0)
	ready_static = true
	_start_pass()


# ------------------------------------------------------------------ denní přepočet (po kouscích)

func _on_eco_day(jd: int) -> void:
	if world == null:
		return
	_mast_day()
	_pop_step(jd)
	_decay_day(jd)
	if ready_static and not _pass_running:
		_start_pass()


func _start_pass() -> void:
	if world.eco == null or world.clock == null:
		return
	var c: Clock = world.clock
	_p_doy = c.day_of_year()
	_p_month = c.month()
	_p_year = c.year()
	_p_jd = c.jd()
	var wt: Weather = world.weather
	var snow_now := wt.snow_cover if wt != null else 0.0
	_p_winter = _p_month == 12 or _p_month <= 2 or snow_now > 0.3
	_p_frost = wt != null and wt.temp < FROST_FROM_C
	_p_mast = mast_store
	_p_feeders.clear()
	var hu: Hunter = world.hunter
	for a in AREAS:
		_feeder_area[a] = 0.0
		for s in 3:
			_k_acc[a * 3 + s] = 0.0
		_snow_acc[a] = 0.0
	if hu != null:
		for fi in hu.feeders.size():
			if hu.feeder_active(fi):
				_p_feeders.append(hu.feeders[fi])
				var ci := _ci(hu.feeders[fi].x, hu.feeders[fi].z)
				if ci >= 0:
					_feeder_area[s_area[ci]] = 1.0
	_pass_running = true
	world.eco.slice(nx * nz, DAY_PER_FRAME, _day_cell)


func _snow_at(x: float, z: float) -> float:
	if world.soil_water != null:
		return world.soil_water.snow_at(x, z)
	return world.weather.snow_cover * 0.1 if world.weather != null else 0.0


## Výška trávy louky (m): M8.14 (`World.meadows`, je-li), jinak hrubě podle měsíce.
func grass_height_at(x: float, z: float) -> float:
	var mw = world.get("meadows") if world != null else null
	if mw != null:
		if mw.has_method("height_at"):
			return float(mw.call("height_at", x, z))
		if mw.has_method("grass_height_at"):
			return float(mw.call("grass_height_at", x, z))
	var m := world.clock.month() if world != null and world.clock != null else 6
	return float(GRASS_H_MONTH[clampi(m - 1, 0, 11)])


## Potrava a kryt na poli buňky → `_cf` (srnec, prase, zajíc) a `_ch` (výška porostu, m).
func _crop(i: int, x: float, z: float) -> void:
	_cf[0] = 0.0
	_cf[1] = 0.0
	_cf[2] = 0.0
	_ch = 0.0
	var fl: Fields = world.fields
	var fid := s_field[i]
	if fl == null or fid <= 0:
		return
	var key := ""
	var grain := false
	var stubble := false
	var info: Dictionary = fl.field_info(fid)
	if not info.is_empty():
		key = String(info.get("k", ""))
		var st := int(info.get("st", 0))
		if int(info.get("harv", -1)) >= 0:
			stubble = true
		grain = st >= CropModel.ST_FILL
		_ch = fl.crop_height_at(Vector3(x, 0.0, z))
	else:
		key = fl.crop_at(x, z, _p_year)
		var cereal := key == "psenice" or key == "jecmen" or key == "repka"
		if cereal:
			grain = _p_month == 6 or _p_month == 7
			stubble = _p_month == 8 or _p_month == 9
			_ch = 0.9 if _p_month >= 5 and _p_month <= 7 else (0.3 if _p_month == 4 else 0.0)
		elif key == "kukurice" or key == "slunecnice":
			grain = _p_month >= 8 and _p_month <= 10
			stubble = _p_month >= 11 or _p_month <= 3
			_ch = 2.2 if _p_month >= 7 and _p_month <= 10 else (0.8 if _p_month == 6 else 0.0)
		else:
			_ch = 0.4 if _p_month >= 5 and _p_month <= 9 else 0.1
	var tab: Array = STUBBLE_FOOD
	if not stubble:
		tab = (CROP_GRAIN if grain else CROP_GREEN).get(key, STUBBLE_FOOD)
	for s in 3:
		_cf[s] = float(tab[s])


func _day_cell(i: int) -> void:
	# denní útlum rušení a ochozů (po kouscích s průchodem, ne celá mřížka v jednom snímku)
	if d_disturb[i] > 0.001:
		d_disturb[i] *= DISTURB_DECAY
	if d_trail[i] > 0.001:
		d_trail[i] *= TRAIL_DECAY
	if s_valid[i] == 1:
		_eval_cell(i)
	if i == nx * nz - 1:
		_pass_done()


func _eval_cell(i: int) -> void:
	var x := _cx(i)
	var z := _cz(i)
	var a := int(s_area[i])
	var fo := s_forest[i]
	var ins := clampf((_insw[i] / maxf(_insw_mean, 1.0) - 0.6) / 0.8, 0.0, 1.0)
	s_shelter[i] = (1.0 - clampf(_wexp[i], 0.0, 1.0)) * 0.6 + ins * 0.4
	var snow := _snow_at(x, z)
	_snow_acc[a] += snow
	var snow_k := 1.0 - clampf(snow / maxf(SNOW_FOOD_M, 0.01), 0.0, 1.0 - SNOW_FOOD_MIN)
	var quiet := clampf(1.0 - s_settle[i] * Q_SETTLE - s_road[i] * Q_ROAD - d_disturb[i] * Q_DISTURB, 0.0, 1.0)
	_crop(i, x, z)
	var grass := float(GRASS_MONTH[clampi(_p_month - 1, 0, 11)])
	var gh := grass_height_at(x, z) if s_meadow[i] > 0.0 else 0.0
	var moist := world.soil_water.moisture_at(x, z) if world.soil_water != null else 0.5
	# krmelec v zimě
	var feeder := 0.0
	if not _p_feeders.is_empty():
		for fp in _p_feeders:
			var d := Vector2(fp.x - x, fp.z - z).length()
			if d < FEEDER_R:
				feeder = maxf(feeder, 1.0 - d / FEEDER_R)
	# kryt
	var forest_cover := fo * (COVER_FOREST_BASE + COVER_THICKET * s_thicket[i] + (COVER_CONIFER_WINTER * s_conif[i] if _p_winter else 0.0))
	var crop_cover := s_arable[i] * clampf(_ch / maxf(COVER_CROP_FULL_M, 0.1), 0.0, 1.0) * COVER_CROP_MAX
	var grass_cover := s_meadow[i] * clampf(gh / maxf(COVER_GRASS_FULL_M, 0.1), 0.0, 1.0) * COVER_GRASS_MAX
	var winter_k := (1.0 - SHELTER_WINTER + SHELTER_WINTER * s_shelter[i]) if _p_winter else 1.0
	var cold_pen := COLD_POOL_PEN * s_cold[i] if _p_frost else 0.0
	var mast_here := s_mast[i] * _p_mast
	# --- srnec
	var browse := fo * s_thicket[i] * BROWSE_SRNEC * (BROWSE_WINTER_K if _p_winter else 1.0)
	var feed0 := maxf(maxf(s_meadow[i] * grass, s_arable[i] * _cf[0]), maxf(browse, mast_here * MAST_FEED_SRNEC))
	feed0 = feed0 * (1.0 + s_edge[i] * EDGE_FEED_K) * snow_k
	if _p_winter:
		feed0 = maxf(feed0, feeder * FEEDER_FEED)
	var rest0 := maxf(forest_cover, maxf(crop_cover, grass_cover)) * winter_k - cold_pen
	_put(0, i, a, rest0 * quiet, feed0 * sqrt(quiet))
	# --- prase
	var root := fo * (ROOT_BASE + ROOT_MOIST * moist)
	var feed1 := maxf(maxf(root, mast_here * MAST_FEED), maxf(s_arable[i] * _cf[1], s_meadow[i] * s_edge[i] * moist * ROOT_MEADOW))
	feed1 *= lerpf(1.0, snow_k, 0.5)       # prase rozhrabe i sníh
	var rest1 := maxf(fo * (0.5 + 0.5 * maxf(s_thicket[i], s_conif[i])), crop_cover * 1.05) * winter_k - cold_pen * 0.5
	_put(1, i, a, rest1 * quiet, feed1 * sqrt(quiet))
	# --- zajíc (otevřená krajina, pelech v poli / na louce)
	var open := 1.0 - fo * OPEN_FEED_FOREST
	var feed2 := (s_arable[i] * _cf[2] + s_meadow[i] * grass * 0.8) * open * snow_k
	if _p_winter:
		feed2 = maxf(feed2, feeder * FEEDER_FEED * 0.5)
	var rest2 := (s_arable[i] + s_meadow[i]) * (0.5 + 0.5 * clampf(maxf(_ch, gh) / 0.4, 0.0, 1.0)) * open * winter_k
	_put(2, i, a, rest2 * quiet, feed2 * sqrt(quiet))
	# škody prasat: rozrytá louka u lesa, kukuřice v mléčné zralosti
	if pop_ready:
		var dens := _area_density(a, 1)
		var pr := clampf(dens / maxf(CULL_PRASE_REF, 0.1), 0.0, 3.0)
		if s_meadow[i] > 0.0 and s_edge[i] > 0.3 and moist > 0.25:
			var r := _hash01(i, _p_jd, 7)
			if r < ROOT_P * pr * s_meadow[i] * s_edge[i]:
				_add_rooting(x + (_hash01(i, _p_jd, 11) - 0.5) * CELL * 0.8, z + (_hash01(i, _p_jd, 13) - 0.5) * CELL * 0.8, a)
		if s_arable[i] > 0.0 and _cf[1] >= 0.9:
			corn_damage[a] += CORN_DAMAGE_K * pr * s_arable[i]


func _put(s: int, i: int, a: int, rest: float, feed: float) -> void:
	var k := i * 3 + s
	d_rest[k] = clampf(rest, 0.0, 1.0)
	d_feed[k] = clampf(feed, 0.0, 1.0)
	var h := 0.5 * (d_rest[k] + d_feed[k])
	d_hsi[k] = h
	_k_acc[a * 3 + s] += h


func _pass_done() -> void:
	_pass_running = false
	day_done_jd = _p_jd
	for a in AREAS:
		for s in 3:
			var p: Dictionary = pop[a][s]
			p["k"] = _k_acc[a * 3 + s] * CELL_HA * float(DENS_MAX[s]) / 100.0
	if not pop_ready:
		for a in AREAS:
			for s in 3:
				var p: Dictionary = pop[a][s]
				p["n"] = float(p["k"]) * float(INIT_FILL[s])
		pop_ready = true
		last_pop_jd = _p_jd
	# drby o škodách, vnadění
	if corn_damage.size() == AREAS:
		for a in AREAS:
			if corn_damage[a] >= 1.0:
				var arr: Array = damage[a]
				arr.append(_p_jd)
				corn_damage[a] -= 1.0
	_update_rumor()


# ------------------------------------------------------------------ semenné roky

## Úroda žaludů a bukvic roku `y` (0..1): semenný rok 1× za 3–6 let (deterministicky), rok po něm chudý.
func mast_year(y: int) -> float:
	if y == mast_force_year:
		return 1.0
	if y == _mast_cache_y:
		return _mast_cache_v
	var v := MAST_NORMAL + (_hash01(y, 17, 3) - 0.5) * 2.0 * MAST_JITTER
	if is_mast_year(y):
		v = 1.0
	elif is_mast_year(y - 1) or y - 1 == mast_force_year:
		v = MAST_POOR
	_mast_cache_y = y
	_mast_cache_v = v
	return v


func is_mast_year(y: int) -> bool:
	if y == mast_force_year:
		return true
	var m := 1990 + int(_hash01(1990, 5, 1) * MAST_MIN_GAP)
	while m < y:
		m += MAST_MIN_GAP + int(_hash01(m, 9, 2) * maxi(MAST_GAP_SPAN, 1))
	return m == y


## Žaludy a bukvice na zemi teď (0..1) – denní krok: padají od září (fenologie dubu a buku), přes zimu ubývají.
func mast_now() -> float:
	return mast_store


func _mast_day() -> void:
	var c: Clock = world.clock
	if c == null:
		return
	var doy := c.day_of_year()
	var y := c.year()
	if doy >= MAST_SPROUT_DOY and doy < MAST_FROM_DOY - 30.0:
		mast_store = 0.0
		return
	var ripe := 0.0
	var ph: Phenology = world.phenology
	if ph != null and ph.enabled():
		var ref := Vector3(x0 + nx * CELL * 0.5, 0.0, z0 + nz * CELL * 0.5)
		for sid in MAST_IDS:
			ripe = maxf(ripe, ph.fruit(sid, ref))
	elif doy >= MAST_FROM_DOY:
		ripe = clampf((doy - MAST_FROM_DOY) / 30.0, 0.0, 1.0)
	if doy >= MAST_FROM_DOY - 30.0:
		mast_store = maxf(mast_store, mast_year(y) * ripe)
	mast_store = maxf(mast_store * (1.0 - MAST_EAT_D), 0.0)


# ------------------------------------------------------------------ populace (denní krok)

func _area_density(a: int, s: int) -> float:
	var ha := _cells_area[a] * CELL_HA
	if ha <= 0.0 or pop.is_empty():
		return 0.0
	return float(pop[a][s]["n"]) / ha * 100.0


func _pop_step(jd: int) -> void:
	if not pop_ready:
		return
	if jd < last_pop_jd:            # datum posunuté zpět (F2) – populace zůstane, počítá se od nového dne
		last_pop_jd = jd
		return
	var days := clampi(jd - last_pop_jd, 0, 3660)
	if days == 0:
		return
	var temp := world.weather.temp if world.weather != null else 5.0
	for k in days:
		var dj := last_pop_jd + 1 + k
		var dt := Clock.from_jdn(dj)
		var y := int(dt["year"])
		var mo := int(dt["month"])
		var doy := float(dj - Clock.jdn(y, 1, 1) + 1)
		var winter := mo == 12 or mo <= 2
		for a in AREAS:
			var snow := _snow_acc[a] / maxf(_cells_area[a], 1.0) if k == days - 1 or days == 1 else (0.1 if winter else 0.0)
			var hard := 0.0
			if winter:
				hard = clampf(snow / maxf(WINTER_SNOW_M, 0.01), 0.0, 1.0) * 0.6 + clampf(-temp / maxf(WINTER_COLD_C, 0.1), 0.0, 1.0) * 0.4
			for s in 3:
				var p: Dictionary = pop[a][s]
				var n: float = p["n"]
				var kk := maxf(float(p["k"]), 0.5)
				if doy <= 1.5:
					p["young"] = 0.0           # loňská mláďata dospěla
					p["lov"] = 0
					p["auto"] = 0
					p["zima"] = 0.0
					p["hrac"] = 0
					p["plan"] = 0.0
				# rozmnožování (pulz v okně)
				var bw: Array = BIRTH_DOY[s]
				if doy >= float(bw[0]) and doy <= float(bw[1]):
					var litter := float(LITTER[s])
					if s == 1:
						litter *= 1.0 - MAST_BIRTH_K + MAST_BIRTH_K * 2.0 * mast_year(y - 1)
					var born := n * float(FEMALE_SHARE[s]) * litter * maxf(0.0, 1.0 - n / kk) / maxf(float(bw[1]) - float(bw[0]) + 1.0, 1.0)
					n += born
					p["young"] = float(p["young"]) + born
				# úmrtnost
				var mort := float(MORT_BASE[s]) / 365.0
				if n > kk:
					mort += (n - kk) / kk * MORT_CROWD / 365.0
				if winter and hard > 0.0:
					var relief := 0.0
					if s == 1:
						relief = MAST_RELIEF * mast_store
					else:
						relief = FEEDER_RELIEF * _feeder_area[a]
					var wm := float(MORT_WINTER[s]) / 90.0 * hard * (1.0 - clampf(relief, 0.0, 1.0))
					mort += wm
					p["zima"] = float(p["zima"]) + n * wm
				var road_k := clampf(_road_share(a) * 5.0, 0.0, 2.0)
				var auto := n * float(ROAD_MORT[s]) / 365.0 * road_k
				# plán myslivců (podíl stavu za rok, rozložený do měsíců lovu)
				var cull := 0.0
				var cm: Array = CULL_MONTHS[s]
				if mo in cm:
					var q := float(CULL_QUOTA[s])
					if s == 1:
						q *= clampf(_area_density(a, 1) / maxf(CULL_PRASE_REF, 0.1), 0.5, 2.0)
					cull = n * q / maxf(float(cm.size()) * 30.4, 1.0)
				p["plan"] = float(p["plan"]) + cull
				n = maxf(n - n * mort - auto - cull, 0.0)
				p["n"] = n
				p["young"] = minf(float(p["young"]), n)
	last_pop_jd = jd


func _road_share(a: int) -> float:
	return _road_acc[a]


func _decay_day(jd: int) -> void:
	var changed := false
	for k in range(rooted.size() - 1, -1, -1):
		if jd - int(rooted[k][2]) > ROOT_DAYS:
			rooted.remove_at(k)
			changed = true
	for a in damage.size():
		var arr: Array = damage[a]
		while not arr.is_empty() and jd - int(arr[0]) > 14:
			arr.remove_at(0)
	if changed:
		rooted_ver += 1


## Úmrtí kusu (lov hráče, srážka s autem): ubere z populace honitby. `cause` "lov" / "auto".
func on_death(species: String, pos: Vector3, cause: String, pid := 0, legal := false) -> void:
	var s := sp_index(species)
	var i := _ci(pos.x, pos.z)
	if s < 0 or i < 0 or pop.is_empty():
		return
	var a := int(s_area[i])
	var p: Dictionary = pop[a][s]
	p["n"] = maxf(float(p["n"]) - 1.0, 0.0)
	if cause == "auto":
		p["auto"] = int(p["auto"]) + 1
	else:
		p["lov"] = int(p["lov"]) + 1
		p["hrac"] = int(p["hrac"]) + 1
		disturb(pos, DISTURB_SHOT)
		# pomoc se škodami: legální úlovek prasete v honitbě se škodami → zemědělci to ocení
		if s == 1 and legal and pid > 0 and (damage[a] as Array).size() >= int(DAMAGE_RUMOR):
			var rep: Reputation = world.reputations.get(pid)
			if rep != null:
				rep.change_respect("zemedelci", RESPECT_HELP, "pomoc se škodami od prasat")


## Rušení (výstřel, lov) – zvěř se místu pár dní vyhýbá (klid buňky klesne).
func disturb(pos: Vector3, amount: float) -> void:
	var i := _ci(pos.x, pos.z)
	if i < 0:
		return
	d_disturb[i] = minf(d_disturb[i] + amount, 1.0)
	for o in [-1, 1, -nx, nx]:
		var j: int = i + int(o)
		if j >= 0 and j < d_disturb.size():
			d_disturb[j] = minf(d_disturb[j] + amount * 0.5, 1.0)


func _add_rooting(x: float, z: float, a: int) -> void:
	rooted.append([x, z, _p_jd, 1.0 + _hash01(int(x), int(z), 3) * 1.2])
	while rooted.size() > ROOT_MAX:
		rooted.remove_at(0)
	(damage[a] as Array).append(_p_jd)
	rooted_ver += 1


# ------------------------------------------------------------------ dotazy pro zvěř

## Vhodnost místa pro druh v hodinu `hour` (aktivní → pastva, jinak odpočinek). `doy` pro API (sezóna je v denním přepočtu).
func suitability(species: String, pos: Vector3, hour: float, _doy := -1.0) -> float:
	var s := sp_index(species)
	var i := _ci(pos.x, pos.z)
	if s < 0 or i < 0 or not ready_static or s_valid[i] == 0:
		return 0.0
	var on := AnimalSpecs.is_active(AnimalSpecs.get_spec(SP[s]), hour)
	return d_feed[i * 3 + s] if on else d_rest[i * 3 + s]


func rest_at(species: String, pos: Vector3) -> float:
	var s := sp_index(species)
	var i := _ci(pos.x, pos.z)
	return d_rest[i * 3 + s] if s >= 0 and i >= 0 else 0.0


func feed_at(species: String, pos: Vector3) -> float:
	var s := sp_index(species)
	var i := _ci(pos.x, pos.z)
	return d_feed[i * 3 + s] if s >= 0 and i >= 0 else 0.0


## Nejlepší bod pro účel `purpose` ("rest" / "feed" / "water") do `radius` m od `pos`; INF = nic (fallback na Fauna).
func best_nearby(species: String, pos: Vector3, radius: float, purpose: String, rng: RandomNumberGenerator = null) -> Vector3:
	var s := sp_index(species)
	if s < 0 or not ready_static:
		return Vector3.INF
	var r := minf(radius, BEST_R_MAX)
	var cr := int(ceil(r / CELL))
	var cix := int(floor((pos.x - x0) / CELL))
	var ciz := int(floor((pos.z - z0) / CELL))
	var best := -1
	var bs := -INF
	for dz in range(-cr, cr + 1):
		var iz := ciz + dz
		if iz < 0 or iz >= nz:
			continue
		for dx in range(-cr, cr + 1):
			var ix := cix + dx
			if ix < 0 or ix >= nx:
				continue
			var d := Vector2(dx, dz).length() * CELL
			if d > r:
				continue
			var i := iz * nx + ix
			if s_valid[i] == 0:
				continue
			var v := 0.0
			match purpose:
				"rest": v = d_rest[i * 3 + s]
				"feed": v = d_feed[i * 3 + s]
				_: v = s_water[i]
			v -= d / maxf(r, 1.0) * BEST_DIST_PEN
			if rng != null:
				v += rng.randf() * BEST_JITTER
			if v > bs:
				bs = v
				best = i
	if best < 0:
		return Vector3.INF
	var ox := (rng.randf() - 0.5) * CELL * 0.7 if rng != null else 0.0
	var oz := (rng.randf() - 0.5) * CELL * 0.7 if rng != null else 0.0
	var x := _cx(best) + ox
	var z := _cz(best) + oz
	return Vector3(x, world.terrain.height_at(x, z), z)


## Hustota druhu v honitbě bodu (ks / 100 ha); −1 = populace ještě není.
func density(species: String, pos: Vector3) -> float:
	var s := sp_index(species)
	var i := _ci(pos.x, pos.z)
	if s < 0 or i < 0 or not pop_ready:
		return -1.0
	return _area_density(int(s_area[i]), s)


## Váha druhu při výběru setkání (hustota vůči referenci × vhodnost okolí teď).
func pick_weight(species: String, pos: Vector3) -> float:
	var s := sp_index(species)
	var dn := density(species, pos)
	if s < 0 or dn < 0.0:
		return 1.0
	var h := world.clock.hour() if world.clock != null else 12.0
	return clampf(dn / maxf(float(DENS_REF[s]), 0.1), 0.05, 3.0) * (0.3 + suitability(species, pos, h))


## Má se u hráče objevit skupina druhu? Očekávaný počet skupin v okolí z hustoty a vhodnosti; deterministicky
## pro buňku, den a dvouhodinovku (opakovaný sken na stejném místě dá stejnou odpověď).
func spawn_roll(species: String, pos: Vector3) -> bool:
	var s := sp_index(species)
	var dn := density(species, pos)
	var i := _ci(pos.x, pos.z)
	if s < 0 or dn < 0.0 or i < 0:
		return true
	var area_ha := PI * SPAWN_R * SPAWN_R / 10000.0
	var mean_hsi := _mean_hsi(s, int(s_area[i]))
	var local := clampf(d_hsi[i * 3 + s] / maxf(mean_hsi, 0.05), 0.2, 3.0)
	var groups := dn / 100.0 * area_ha * local / maxf(float(GROUP_MEAN[s]), 0.5)
	var p := clampf(groups * SPAWN_K, SPAWN_P_MIN, 1.0)
	var h := int(world.clock.hour() / 2.0) if world.clock != null else 0
	return _hash01(i * 3 + s, world.clock.jd() * 12 + h if world.clock != null else 0, 21) < p


## Průměrné HSI druhu v honitbě (z kapacity posledního hotového průchodu).
func _mean_hsi(s: int, a: int) -> float:
	var ha := _cells_area[a] * CELL_HA
	if ha <= 0.0:
		return 0.3
	return float(pop[a][s]["k"]) * 100.0 / (maxf(float(DENS_MAX[s]), 0.1) * ha)


## Zvěřní ochoz: přesun z krytu na pastvu a zpět – buňky na spojnici se „prošlapávají“ (`trail_at`).
func note_trail(a: Vector3, b: Vector3) -> void:
	if not ready_static:
		return
	var d := Vector2(b.x - a.x, b.z - a.z).length()
	var steps := clampi(int(d / (CELL * 0.5)), 1, 40)
	var last := -1
	for k in steps + 1:
		var p := a.lerp(b, float(k) / steps)
		var i := _ci(p.x, p.z)
		if i >= 0 and i != last:
			d_trail[i] = minf(d_trail[i] + TRAIL_ADD, 1.0)
			last = i


func trail_at(x: float, z: float) -> float:
	var i := _ci(x, z)
	return d_trail[i] if i >= 0 else 0.0


## Okus sazenic (M2.5): šance za den podle hustoty srnců v honitbě a vhodnosti místa (−1 = bez dat → staré chování).
func browse_pressure(pos: Vector3) -> float:
	if not active():
		return -1.0
	var dn := density("srnec", pos)
	if dn < 0.0:
		return -1.0
	var i := _ci(pos.x, pos.z)
	var hs := d_hsi[i * 3] if i >= 0 else 0.0
	return clampf(dn / maxf(float(DENS_REF[0]), 0.1) * hs * BROWSE_PRESSURE_K, 0.0, 1.0)


## Myslivci vnadí prasata k posedu (noční čekaná), když jsou v některé honitbě škody.
func bait_active() -> bool:
	if not active():
		return false
	for a in damage.size():
		if (damage[a] as Array).size() >= int(BAIT_DAMAGE):
			return true
	return false


# ------------------------------------------------------------------ texty (drby, deník, F2)

func _update_rumor() -> void:
	var worst := -1
	var wn := 0
	for a in damage.size():
		var n := (damage[a] as Array).size()
		if n > wn:
			wn = n
			worst = a
	if worst < 0 or wn < int(DAMAGE_RUMOR):
		_rumor = ""
		return
	var texts := ["Prasata zas rozryla louku u lesa. Vypadá to tam jak po orbě.",
		"Divočáci prý zase řádili v kukuřici. Zemědělci nadávají na myslivce.",
		"Myslivci prý budou sedět po nocích na čekané, prasat je letos jak much."]
	if is_mast_year(_p_year) or mast_store > 0.6:
		texts.append("Letos je v lese žaludů, že se po nich dá klouzat. Prasata budou tlustá.")
	_rumor = String(texts[_p_jd % texts.size()])
	_rumor_jd = _p_jd
	if _event_jd < 0 or _p_jd - _event_jd >= 7:
		_event_jd = _p_jd
		for pid in world.players:
			world.emit_game_event(int(pid), "wildlife_damage", {"area": worst, "n": wn, "text": _rumor})   # háček M7.3 (úkol „pomoz se škodami“)


## Drb vesničana o zvěři ("" = nic zajímavého).
func rumor() -> String:
	if not active():
		return ""
	if _rumor != "":
		return _rumor
	if mast_store > 0.5:
		return "Letos je hodně žaludů a bukvic. Prasata se ani nemusí chodit do polí."
	return ""


static func _round_to(v: float, step: int) -> int:
	return int(round(v / step)) * step


## Deník J → Příroda: odhad stavu zvěře (přesnost podle Myslivosti) a semenný rok.
func journal_text(pid: int) -> String:
	if not active() or not pop_ready:
		return ""
	var lvl := 1
	var sk: Skills = world.skills.get(pid)
	if sk != null:
		lvl = sk.level("myslivost")
	var step := 50 if lvl < 5 else (20 if lvl < 15 else (10 if lvl < 30 else 5))
	var tot := [0.0, 0.0, 0.0]
	for a in AREAS:
		for s in 3:
			tot[s] += float(pop[a][s]["n"])
	var txt := "\n[b]Zvěř v honitbách[/b] (odhad, přesnost podle Myslivosti)\n"
	txt += "Srnčí asi %d, černá zvěř asi %d, zajíci asi %d kusů.\n" % [maxi(_round_to(tot[0], step), 0), maxi(_round_to(tot[1], step), 0), maxi(_round_to(tot[2], step), 0)]
	var y: int = world.clock.year() if world.clock != null else 2026
	if is_mast_year(y):
		txt += "Letos je semenný rok – hodně žaludů a bukvic, prasata se drží v doubravách a bučinách.\n"
	elif mast_year(y) <= MAST_POOR + 0.01:
		txt += "Po loňském semenném roce jsou duby a buky letos skoupé.\n"
	if bait_active():
		txt += "Prasata dělají škody – myslivci drží noční čekané u posedu.\n"
	return txt


## F2 → Příroda – ladění → Populace: tabulka honiteb a druhů.
func population_text() -> String:
	if not ready_static:
		return "Mřížka stanovišť se ještě počítá (pár sekund po startu)."
	if not pop_ready:
		return "Populace se založí po prvním denním přepočtu stanovišť."
	var names := ["Srnec", "Prase", "Zajíc"]
	var t := "Populace zvěře (ks; K = kapacita z HSI; hustota na 100 ha)\n"
	for a in AREAS:
		var ha := _cells_area[a] * CELL_HA
		t += "\n%s (%d ha, krmelec: %s, škod za 14 dní: %d)\n" % [AREA_NAMES[a], int(ha), "ano" if _feeder_area[a] > 0.0 else "ne", (damage[a] as Array).size()]
		for s in 3:
			var p: Dictionary = pop[a][s]
			t += "  %s: %.0f (K %.0f, %.1f/100 ha, mláďata %.0f) – lov hráč %d, plán %.0f, auta %d, zima %.1f\n" % [names[s], float(p["n"]),
				float(p["k"]), _area_density(a, s), float(p["young"]), int(p["hrac"]), float(p["plan"]), int(p["auto"]), float(p["zima"])]
	var y: int = world.clock.year() if world.clock != null else 2026
	t += "\nŽaludy/bukvice: letos %.2f%s, na zemi %.2f. Rozrytých míst: %d." % [mast_year(y), " (semenný rok)" if is_mast_year(y) else "", mast_store, rooted.size()]
	return t


## F2: vynutí letos semenný rok (znovu = zrušit).
func toggle_mast_year() -> String:
	var y: int = world.clock.year()
	mast_force_year = -1 if mast_force_year == y else y
	_mast_cache_y = -99999
	_mast_day()
	return "Semenný rok %d: %s." % [y, "vynucen" if mast_force_year == y else "podle cyklu"]


# ------------------------------------------------------------------ ladicí vrstvy (mapa M)

func debug_srnec(x: float, z: float) -> Color:
	return _debug(0, x, z, Color(0.2, 0.85, 0.25))


func debug_prase(x: float, z: float) -> Color:
	return _debug(1, x, z, Color(0.55, 0.3, 0.12))


func _debug(s: int, x: float, z: float, col: Color) -> Color:
	if not ready_static:
		return Color(0, 0, 0, 0)
	var v := suitability(SP[s], Vector3(x, 0.0, z), world.clock.hour())
	if v <= 0.02:
		return Color(0, 0, 0, 0)
	return Color(col.r, col.g, col.b, 0.1 + 0.6 * v)


# ------------------------------------------------------------------ ukládání (klíč `wildlife`)

func to_dict() -> Dictionary:
	var p := []
	for a in pop.size():
		var row := []
		for s in 3:
			row.append((pop[a][s] as Dictionary).duplicate())
		p.append(row)
	return {"v": SAVE_V, "pop": p, "ready": pop_ready, "last": last_pop_jd, "mast": mast_store, "mast_force": mast_force_year,
		"damage": damage.duplicate(true), "rooted": rooted.duplicate(true)}


func restore(d: Dictionary) -> void:
	if d.is_empty():
		# starý save bez klíče: populace se založí z kapacity po příštím přepočtu (kapacita K zůstává)
		for a in pop.size():
			for s in 3:
				var p0: Dictionary = pop[a][s]
				for k in p0:
					if k != "k":
						p0[k] = 0 if p0[k] is int else 0.0
			(damage[a] as Array).clear()
		pop_ready = false
		mast_store = 0.0
		mast_force_year = -1
		_mast_cache_y = -99999
		rooted.clear()
		rooted_ver += 1
		if ready_static and not _pass_running:
			_start_pass()
		return
	var p: Array = d.get("pop", [])
	if p.size() == AREAS:
		for a in AREAS:
			var row: Array = p[a]
			for s in mini(row.size(), 3):
				var src: Dictionary = row[s]
				for k in (pop[a][s] as Dictionary):
					if src.has(k):
						pop[a][s][k] = src[k]
		pop_ready = bool(d.get("ready", false))
	last_pop_jd = int(d.get("last", -1))
	if world != null and world.clock != null and (last_pop_jd < 0 or last_pop_jd > world.clock.jd()):
		last_pop_jd = world.clock.jd()
	mast_store = float(d.get("mast", 0.0))
	mast_force_year = int(d.get("mast_force", -1))
	_mast_cache_y = -99999
	var dm: Array = d.get("damage", [])
	if dm.size() == AREAS:
		damage = dm.duplicate(true)
	rooted = (d.get("rooted", []) as Array).duplicate(true)
	rooted_ver += 1


static func _hash01(a: int, b: int, c: int) -> float:
	var h := (a * 73856093) ^ (b * 19349663) ^ (c * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFFFF) / 16777216.0
