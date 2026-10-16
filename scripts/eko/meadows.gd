## Louky, seč, pastva a sukcese (M8.14, `World.meadows`, přepínač realismu `ground_veg`).
##
## Podle čeho (00_PRINCIPY kap. 8): výška porostu roste podle sumy teplot nad `GDD_BASE_C` (denní průměr z hodinových
## teplot `Weather` přes `eco_hour`, po skoku času klimatický normál `CropModel.clim_temp`) × vláha půdy (`SoilWater`,
## M8.7) × logistické nasycení k plné výšce typu louky: dh = GROW_M_PER_GDD · GDD · f(vláha) · (1 − h / H_MAX).
## Mimo vegetační dobu porost slehne k `H_WINTER`. Seč nastaví h = `H_CUT`; pastva (výběh koně, ohrada statku) drží
## h ≤ `GRAZE_H`. Sukcese: louka neposekaná 2+ roky → trnky a šípky (keře kreslí `GroundVegFx`), 5+ let → náletové
## břízy a borovice (`PlantedTrees` – stejná mechanika jako sazenice hráče, vlastník −1).
##
## Mřížka `CELL` = 16 m přes rozsah `Fields` (landuse); buňka je louka, když v ní převládá tráva (`SurfaceMap` třída 0)
## nebo louka z OSM (`Fields` třída 2). Typ louky podle stanoviště (`Site`, M8.2): **vlhká** (TWI vysoké / blízko vody /
## glej, fluvizem), **suchá** (jižní oslunění a mělká půda nebo strmý jižní svah), **ruderální** (zástavba – `Fauna.settle_at`),
## jinak **mezofilní**. Hospodaření po „parcelách“ `PLOT_M`: seno 2× ročně (červen, srpen), u obce 3× (obecní / zahrady),
## ostatní tráva 1× v létě; část parcel je opuštěná (nikdo je neseče) → sukcese. Data dne `CUT_*_DOY` ± `CUT_SPREAD_D`.
##
## Za běhu: inicializace mřížky po řádcích přes `EcoClock.slice` (žádný zásek při startu), denní krok po kouscích
## (`CELLS_PER_FRAME`); výstup pro klienta = `image` (R8, relativní výška 0..1, mimo louky 255) + `gen` (čítač změn) –
## `GroundVegFx` ho nahraje do globálního `meadow_h` (shader trávy: posekaná louka nízká a zelenější).
## API: `height_at(pos)`, `rel_at(x, z)`, `info_at(x, z)`, `mow_at(pos, r)` (údržba, hráč), `cut_days_at(x, z)` (seno),
## `shrub_at(i)` (sukcese), `debug_color(x, z)` (F2 → mapa M, vrstva „louky“). Uložení `to_dict` / `restore` (klíč `meadows`).
class_name Meadows
extends RefCounted

const CELL := 16.0
const KIND_MESIC := 0
const KIND_WET := 1
const KIND_DRY := 2
const KIND_RUDERAL := 3
const KIND_NAMES := ["mezofilní louka", "vlhká louka", "suchá stráň", "ruderální porost"]
const MGMT_HAY := 0                     # louka na seno (OSM meadow) – 2× ročně
const MGMT_VILLAGE := 1                 # tráva u obce – 3× ročně
const MGMT_NONE := 2                    # ostatní tráva (meze, úhory) – 1× v létě, často opuštěná
const MGMT_NAMES := ["seno 2× ročně", "u obce 3× ročně", "občas / neudržovaná"]
const SAVE_VER := 1

## --- laditelné (F3 → Příroda/Louky a podrost, scripts/dev/tune_m8_14.gd) ---
static var H_MAX := [0.75, 0.95, 0.40, 0.90]   # m – plná výška porostu podle typu (mezofilní, vlhká, suchá, ruderální)
static var H_CUT := 0.07                # m – strniště po seči
static var H_WINTER := 0.15             # m – slehlý porost v zimě
static var GROW_M_PER_GDD := 0.0018     # m růstu na 1 °C·den (při nulové výšce a plné vláze)
static var GDD_BASE_C := 5.0            # °C – základ sumy teplot
static var WINTER_SETTLE := 0.012       # podíl rozdílu k H_WINTER za den mimo vegetační dobu
static var SEASON_FROM_DOY := 80        # vegetační doba (mimo ni porost neroste a slehává)
static var SEASON_TO_DOY := 300
static var MOIST_LO := 0.15             # vláha půdy, pod kterou louka skoro neroste
static var MOIST_HI := 0.5              # … nad kterou roste naplno
static var MOIST_MIN_F := 0.2           # růst v suchu (×)
static var REGROW_TAU_D := 28.0         # d – odhad dorůstání po skoku času (analyticky, místo denních kroků)
static var TWI_WET := 10.0              # TWI nad tímto = vlhká louka
static var DIST_WATER_WET := 15.0       # m – blíž k vodě = vlhká
static var TWI_WET_SOIL := 8.0          # glej / fluvizem (oglejená, nivní půda) je vlhká od tohoto TWI
static var INSOL_DRY_Z := 0.5           # oslunění (z-skóre vůči katastru) nad tímto + mělká půda = suchá stráň
static var SOIL_DRY_CM := 60.0          # cm – mělčí půda je „mělká“ (v katastru 54–110 cm)
static var SLOPE_DRY_DEG := 8.0         # svah nad tímto je na jihu suchý i s hlubší půdou
static var SETTLE_RUDERAL := 0.35       # zástavba v okolí nad tímto = ruderální porost
static var SETTLE_VILLAGE := 0.15       # … nad tímto = obecní tráva (seč 3× ročně)
static var PLOT_M := 64.0               # m – „parcela“ se seče najednou
static var CUT_HAY_DOY := [166.0, 228.0]          # seno: červen, srpen
static var CUT_VILLAGE_DOY := [140.0, 190.0, 240.0]
static var CUT_OTHER_DOY := [200.0]
static var CUT_SPREAD_D := 9.0          # ± dní mezi parcelami
static var CUT_LATE_D := 20             # seč se dožene nejvýš tolik dní po termínu (jinak se vynechá)
static var MOW_MIN_H := 0.2             # m – nižší porost se neseče
static var P_ABANDON := [0.06, 0.0, 0.45]         # podíl opuštěných parcel podle hospodaření (nikdo je neseče)
static var P_MOW_YEAR := [0.95, 1.0, 0.6]         # šance, že se parcela v daném roce seče
static var GRAZE_H := 0.12              # m – pastva drží porost nízko
static var SHRUB_YEARS := 2             # od tolika let bez seče keře (trnka, šípek)
static var SHRUB_FULL_YEARS := 7        # … plná hustota keřů
static var TREE_YEARS := 5              # od tolika let bez seče nálet stromů
static var P_SEEDLING := 0.05           # šance náletového stromu na buňku a rok
static var MAX_SEEDLINGS := 300         # strop náletových stromů (výkon PlantedTrees)
static var SEEDLING_SIZE := 0.55        # velikost náletu při vzniku (0,15 sazenice … 1 dospělý) – nad hranicí okusu
static var INIT_ROWS_PER_FRAME := 3
static var CELLS_PER_FRAME := 700
static var FLOWER_MIN_REL := 0.45       # MeadowFlowers: květy jen nad touto relativní výškou (posekaná louka nekvete)

var world: World
var inited := false
var x0 := 0.0
var z0 := 0.0
var nx := 0
var nz := 0
var cell_of := PackedInt32Array()       # index mřížky → index louky (−1 = není louka)
var gi := PackedInt32Array()            # louka → index mřížky
var kind := PackedByteArray()
var mgmt := PackedByteArray()
var h := PackedFloat32Array()           # m – výška porostu
var cut_jd := PackedInt32Array()        # den poslední seče / spasení (−1 = nikdy)
var yu := PackedByteArray()             # roky bez seče
var grazed := PackedByteArray()         # 1 = buňka je ve výběhu / ohradě (pastva; přepočet denně, neukládá se)
var image: Image                        # R8 nx × nz – relativní výška (GroundVegFx → meadow_h)
var gen := 0                            # zvýší se po každé změně image
var seedlings := 0                      # náletových stromů vysázeno
var stats := {}                         # typ louky → počet buněk (log, F2)
var _img_data := PackedByteArray()
var _init_row := 0
var _last_jd := -1
var _year := 0
var _acc := CropModel.DayAcc.new()
var _day := {}                          # vstupy právě počítaného dne
var _graze := {}                        # index louky → true (pastva, přepočet každý den)
var _pending := {}                      # uložení čekající na dokončení inicializace
var _step_busy := false
var _insol_mu := 5233.0
var _insol_sd := 623.0


func setup(w: World) -> void:
	world = w
	var f: Fields = w.fields
	var sm: SurfaceMap = w.surface
	if f != null and f.loaded:
		x0 = f.x0
		z0 = f.z0
		nx = int(ceil(f.nx * f.cell / CELL))
		nz = int(ceil(f.nz * f.cell / CELL))
	elif sm != null and sm.loaded:
		x0 = sm.x0
		z0 = sm.z0
		nx = int(ceil(sm.nx * sm.cell / CELL))
		nz = int(ceil(sm.nz * sm.cell / CELL))
	else:
		push_warning("Meadows: bez landuse.bin i surface.bin – louky se nesimulují")
		return
	cell_of.resize(nx * nz)
	cell_of.fill(-1)
	_img_data.resize(nx * nz)
	_img_data.fill(255)
	image = Image.create_from_data(nx, nz, false, Image.FORMAT_R8, _img_data)
	w.eco_hour.connect(_on_eco_hour)
	w.eco_day.connect(_on_eco_day)
	if w.eco != null:
		w.eco.slice(nz, INIT_ROWS_PER_FRAME, _init_row_cb)
	else:
		for r in nz:
			_init_row_cb(r)


func enabled() -> bool:
	return world != null and world.realism_on("ground_veg")


## Typ louky podle stanoviště v bodě (Site, M8.2) – fallback mezofilní.
func _kind_for(x: float, z: float) -> int:
	if world.fauna != null and world.fauna.settle_at(x, z) > SETTLE_RUDERAL:
		return KIND_RUDERAL
	var s: Site = world.site
	if s == null:
		return KIND_MESIC
	var soil := s.soil(x, z)
	var twi := s.twi(x, z)
	if twi >= TWI_WET or s.dist_water(x, z) < DIST_WATER_WET \
			or ((soil == Site.SOIL_GLEJ or soil == Site.SOIL_FLUVIZEM) and twi >= TWI_WET_SOIL):
		return KIND_WET
	var iz := (s.insol(x, z) - _insol_mu) / maxf(_insol_sd, 1.0)
	if iz > INSOL_DRY_Z and (s.soil_depth(x, z) < SOIL_DRY_CM or s.slope(x, z) > SLOPE_DRY_DEG or soil == Site.SOIL_RANKER):
		return KIND_DRY
	return KIND_MESIC


func _init_row_cb(r: int) -> void:
	var f: Fields = world.fields
	var sm: SurfaceMap = world.surface
	var cz := z0 + (r + 0.5) * CELL
	for c in nx:
		var cx := x0 + (c + 0.5) * CELL
		var grass := 0
		var lu_meadow := 0
		var blocked := 0
		for k in 4:
			var sx := cx + (-0.25 if k % 2 == 0 else 0.25) * CELL
			var szz := cz + (-0.25 if k < 2 else 0.25) * CELL
			if sm != null and sm.loaded:
				var sc := sm.class_at(sx, szz)
				if sc == SurfaceMap.GRASS:
					grass += 1
				elif sc == SurfaceMap.FOREST or sc == SurfaceMap.YARD or sc == SurfaceMap.ARABLE:
					blocked += 1
			if f != null and f.loaded and f.class_at(sx, szz) == 2:
				lu_meadow += 1
		if lu_meadow < 2 and (grass < 2 or blocked > 2):
			continue
		var i := gi.size()
		cell_of[r * nx + c] = i
		gi.append(r * nx + c)
		var kd := _kind_for(cx, cz)
		kind.append(kd)
		var mg := MGMT_HAY if lu_meadow >= 2 else MGMT_NONE
		if world.fauna != null and world.fauna.settle_at(cx, cz) > SETTLE_VILLAGE:
			mg = MGMT_VILLAGE
		mgmt.append(mg)
		h.append(H_WINTER)
		cut_jd.append(-1)
		yu.append(0)
		grazed.append(0)
		stats[kd] = int(stats.get(kd, 0)) + 1
	if r == nz - 1:
		_finish_init()


func _finish_init() -> void:
	inited = true
	var jd := world.clock.jd() if world.clock != null else 0
	_year = int(Clock.from_jdn(jd)["year"])
	if not _pending.is_empty():
		_apply_restore(_pending)
		_pending = {}
	if _last_jd < 0:
		_coarse(jd, true)                 # první start: porost podle data (dorůstání od jara / poslední seče)
	else:
		_write_image_all()
	_last_jd = jd
	print("Meadows: %d buněk louky (%s)" % [gi.size(), _stats_text()])


func _stats_text() -> String:
	var parts: Array[String] = []
	for k in KIND_NAMES.size():
		parts.append("%s %d" % [KIND_NAMES[k], int(stats.get(k, 0))])
	return ", ".join(parts)


# ------------------------------------------------------------------ hospodaření (deterministicky po parcelách)

func _plot_hash(i: int, salt: int) -> int:
	var g := gi[i]
	var px := floori((x0 + (g % nx + 0.5) * CELL) / PLOT_M)
	var pz := floori((z0 + (g / nx + 0.5) * CELL) / PLOT_M)
	return Fields._hash(px * 92821 + salt, pz * 68917 + salt * 7)


func abandoned(i: int) -> bool:
	return float(_plot_hash(i, 17) % 1000) / 1000.0 < float(P_ABANDON[mgmt[i]])


func mown_in_year(i: int, year: int) -> bool:
	if abandoned(i):
		return false
	return float(_plot_hash(i, year) % 1000) / 1000.0 < float(P_MOW_YEAR[mgmt[i]])


func _cut_doys(i: int) -> Array:
	match int(mgmt[i]):
		MGMT_HAY:
			return CUT_HAY_DOY
		MGMT_VILLAGE:
			return CUT_VILLAGE_DOY
	return CUT_OTHER_DOY


## Den v roce `k`-té seče parcely v roce `year` (± rozptyl parcely).
func cut_doy(i: int, k: int, year: int) -> int:
	var ds: Array = _cut_doys(i)
	var sp := float(_plot_hash(i, year * 3 + k + 101) % 1000) / 1000.0 * 2.0 - 1.0
	return clampi(int(roundf(float(ds[k]) + sp * CUT_SPREAD_D)), 1, 365)


# ------------------------------------------------------------------ denní krok

func _on_eco_hour(dt_h: float) -> void:
	if dt_h > 1.5 or world.weather == null:
		return
	_acc.add(world.weather.temp, 0.0, dt_h)


func _on_eco_day(jd: int) -> void:
	if not inited or _step_busy or gi.is_empty():
		return                             # předchozí krok ještě běží po kouscích – den se přičte příště (gap)
	var gap := jd - _last_jd if _last_jd >= 0 else 999   # −1 = po změně data → hrubý krok
	if gap <= 0 or gap > 3:
		_coarse(jd, false)
		_last_jd = jd
		_acc.reset()
		return
	var d := Clock.from_jdn(jd - 1)
	var year: int = d["year"]
	var turn := year != _year
	var old_year := _year
	_year = year
	var doy := jd - 1 - Clock.jdn(year, 1, 1) + 1
	var t := CropModel.clim_temp(float(doy))
	if _acc.valid():
		t = _acc.mean()
	_acc.reset()
	_day = {"jd": jd - 1, "doy": doy, "year": year, "gdd": maxf(t - GDD_BASE_C, 0.0) * float(gap),
		"y0": Clock.jdn(year, 1, 1), "turn": turn, "old_year": old_year}
	_find_grazing()
	_last_jd = jd
	_step_busy = true
	var chunks := int(ceil(float(gi.size()) / float(CELLS_PER_FRAME)))
	if world.eco != null and chunks > 0:
		world.eco.slice(chunks, 1, _step_chunk)
	else:
		for c in chunks:
			_step_chunk(c)


func _find_grazing() -> void:
	for i in _graze:
		grazed[i] = 0
	_graze.clear()
	var pens: Array = [world.paddock, world.statek.pen if world.statek != null else null]
	for pen in pens:
		if pen == null or not is_instance_valid(pen) or not pen.has_method("contains") or not ("center" in pen):
			continue
		var c: Vector3 = pen.center
		var r := 40.0
		var c0 := clampi(floori((c.x - r - x0) / CELL), 0, nx - 1)
		var c1 := clampi(floori((c.x + r - x0) / CELL), 0, nx - 1)
		var r0 := clampi(floori((c.z - r - z0) / CELL), 0, nz - 1)
		var r1 := clampi(floori((c.z + r - z0) / CELL), 0, nz - 1)
		for rr in range(r0, r1 + 1):
			for cc in range(c0, c1 + 1):
				var i := cell_of[rr * nx + cc]
				if i >= 0 and bool(pen.call("contains", Vector3(x0 + (cc + 0.5) * CELL, c.y, z0 + (rr + 0.5) * CELL))):
					_graze[i] = true
					grazed[i] = 1


func _step_chunk(c: int) -> void:
	var a := c * CELLS_PER_FRAME
	var b := mini(a + CELLS_PER_FRAME, gi.size())
	var doy: int = _day["doy"]
	var jd: int = _day["jd"]
	var year: int = _day["year"]
	var y0: int = _day["y0"]
	var gdd: float = _day["gdd"]
	var season := doy >= SEASON_FROM_DOY and doy <= SEASON_TO_DOY
	var sw: SoilWater = world.soil_water
	var sw_on := sw != null and sw.active()
	var turn: bool = _day["turn"]
	var old_year: int = _day["old_year"]
	for i in range(a, b):
		if turn:
			for y in range(old_year, year):
				_year_cell(i, y, false)
		var hm: float = H_MAX[kind[i]]
		var hh := h[i]
		if season and gdd > 0.0:
			var mf := 0.8
			if sw_on:
				var g := gi[i]
				var m := sw.moisture_at(x0 + (g % nx + 0.5) * CELL, z0 + (g / nx + 0.5) * CELL)
				mf = lerpf(MOIST_MIN_F, 1.0, clampf((m - MOIST_LO) / maxf(MOIST_HI - MOIST_LO, 0.01), 0.0, 1.0))
			hh += GROW_M_PER_GDD * gdd * mf * maxf(1.0 - hh / hm, 0.0)
		elif not season and hh > H_WINTER:
			hh -= (hh - H_WINTER) * WINTER_SETTLE
		if _graze.has(i):
			if hh > GRAZE_H:
				hh = GRAZE_H                 # pastva (roky bez seče se nepočítají – viz _year_cell)
		elif mown_in_year(i, year):
			var ds: Array = _cut_doys(i)
			for k in ds.size():
				var cj := y0 + cut_doy(i, k, year) - 1
				if jd >= cj and cut_jd[i] < cj and jd - cj <= CUT_LATE_D and hh > MOW_MIN_H:
					hh = H_CUT
					cut_jd[i] = jd
					break
		h[i] = hh
		_img_data[gi[i]] = int(clampf(hh / hm, 0.0, 1.0) * 255.0)
	if b >= gi.size():
		_step_busy = false
		_commit_image()
		_flush_pending()


## Konec roku `y` v buňce `i`: roky bez seče (+ při skoku času podle plánu parcel `planned`) a nálet stromů.
func _year_cell(i: int, y: int, planned: bool) -> void:
	var cut := cut_jd[i] >= Clock.jdn(y, 1, 1) or (planned and mown_in_year(i, y)) or grazed[i] != 0
	yu[i] = 0 if cut else mini(int(yu[i]) + 1, 250)
	if int(yu[i]) >= TREE_YEARS:
		_seed_tree(i, y + 1)


## Náletový strom v buňce `i` (šance P_SEEDLING za rok, deterministicky podle buňky a roku).
func _seed_tree(i: int, year: int) -> void:
	if seedlings >= MAX_SEEDLINGS or world.trees == null or world.trees.planted == null:
		return
	var hv := Fields._hash(gi[i] * 31 + 5, year * 17 + 3)
	if float(hv % 10000) / 10000.0 >= P_SEEDLING:
		return
	var g := gi[i]
	var x := x0 + (g % nx + 0.15 + 0.7 * float((hv / 10000) % 100) / 100.0) * CELL
	var z := z0 + (g / nx + 0.15 + 0.7 * float((hv / 1000000) % 100) / 100.0) * CELL
	var sp := "briza"
	if kind[i] == KIND_DRY or (world.site != null and world.site.soil(x, z) == Site.SOIL_ARENOSOL):
		sp = "borovice"
	if not PlantedTrees.SPECIES.has(sp):
		return
	var pt: PlantedTrees = world.trees.planted
	var spec: Dictionary = PlantedTrees.SPECIES[sp]
	var frac := clampf((SEEDLING_SIZE - PlantedTrees.START_SCALE) / (1.0 - PlantedTrees.START_SCALE), 0.0, 1.0)
	var age := frac * float(spec["years"]) * 365.0 / maxf(PlantedTrees.GROWTH_SPEEDUP, 0.01)
	var id := pt.plant(sp, Vector3(x, 0.0, z), -1, age)
	var rec: Dictionary = pt.recs.get(id, {})
	if not rec.is_empty():
		rec["cal"] = PlantedTrees.ESTABLISH_DAYS + 1      # nálet je ujatý (žádná zálivka, žádná odměna)
		rec["rewarded"] = true
	seedlings += 1


## Hrubý krok po skoku času (F2 datum, dlouhý spánek, první start): roky bez seče se přehrají podle plánu parcel,
## výška porostu se odhadne analyticky (dorůstání od jara / od poslední seče s časovou konstantou REGROW_TAU_D).
## Po kouscích přes EcoClock (CELLS_PER_FRAME buněk za snímek).
func _coarse(jd: int, first: bool) -> void:
	if gi.is_empty():
		return
	var d := Clock.from_jdn(jd)
	var year: int = d["year"]
	var y0 := Clock.jdn(year, 1, 1)
	_day = {"jd": jd, "year": year, "y0": y0, "doy": jd - y0 + 1, "from_year": year if first else _year}
	_year = year
	_find_grazing()
	_step_busy = true
	var chunks := int(ceil(float(gi.size()) / float(CELLS_PER_FRAME)))
	if world.eco != null and chunks > 0:
		world.eco.slice(chunks, 1, _coarse_chunk)
	else:
		for c in chunks:
			_coarse_chunk(c)
		_step_busy = false


func _coarse_chunk(c: int) -> void:
	var a := c * CELLS_PER_FRAME
	var b := mini(a + CELLS_PER_FRAME, gi.size())
	var jd: int = _day["jd"]
	var year: int = _day["year"]
	var y0: int = _day["y0"]
	var doy: int = _day["doy"]
	var from_year: int = _day["from_year"]
	for i in range(a, b):
		for y in range(from_year, year):
			_year_cell(i, y, true)
		# poslední plánovaná seč do dneška (letos, jinak loni)
		var last := cut_jd[i] if cut_jd[i] <= jd else -1
		for yy in [year - 1, year]:
			if not mown_in_year(i, yy):
				continue
			var ys := Clock.jdn(yy, 1, 1)
			var ds: Array = _cut_doys(i)
			for k in ds.size():
				var cj := ys + cut_doy(i, k, yy) - 1
				if cj <= jd and cj > last:
					last = cj
		cut_jd[i] = last
		h[i] = _h_estimate(i, jd, doy, y0, last)
		_img_data[gi[i]] = int(clampf(h[i] / float(H_MAX[kind[i]]), 0.0, 1.0) * 255.0)
	if b >= gi.size():
		_step_busy = false
		_commit_image()
		_flush_pending()


func _h_estimate(i: int, jd: int, doy: int, y0: int, last_cut: int) -> float:
	var hm: float = H_MAX[kind[i]]
	if doy < SEASON_FROM_DOY or doy > SEASON_TO_DOY:
		return H_WINTER if last_cut < y0 + SEASON_TO_DOY - 365 else minf(hm, H_WINTER)
	var start := y0 + SEASON_FROM_DOY - 1
	var base := H_WINTER
	if last_cut >= start:
		start = last_cut
		base = H_CUT
	var days := float(jd - start)
	var hh := base + (hm - base) * (1.0 - exp(-days / maxf(REGROW_TAU_D, 1.0)))
	return minf(hh, GRAZE_H) if _graze.has(i) else hh


func _write_image_all() -> void:
	for i in gi.size():
		_img_data[gi[i]] = int(clampf(h[i] / float(H_MAX[kind[i]]), 0.0, 1.0) * 255.0)
	_commit_image()


func _commit_image() -> void:
	if image == null:
		return
	image.set_data(nx, nz, false, Image.FORMAT_R8, _img_data)
	gen += 1


## Změna data (F2 → Datum, i zpět v čase): hrubý krok k novému dni (eko-takt zpět nedohání).
func on_date_set() -> void:
	if not inited or world.clock == null:
		return
	if _step_busy:
		_last_jd = -1                      # rozpracovaný krok doběhne, příští eco_day udělá hrubý krok
		return
	var jd := world.clock.jd()
	_coarse(jd, false)
	_last_jd = jd
	_acc.reset()


# ------------------------------------------------------------------ dotazy a zásahy

func index_at(x: float, z: float) -> int:
	if nx <= 0:
		return -1
	var c := floori((x - x0) / CELL)
	var r := floori((z - z0) / CELL)
	if c < 0 or r < 0 or c >= nx or r >= nz:
		return -1
	return cell_of[r * nx + c]


## Výška porostu louky (m) v bodě; mimo louku −1.
func height_at(pos: Vector3) -> float:
	var i := index_at(pos.x, pos.z)
	return h[i] if inited and i >= 0 else -1.0


## Relativní výška 0..1 (1 = neposekaná / mimo louku).
func rel_at(x: float, z: float) -> float:
	var i := index_at(x, z)
	if not inited or i < 0 or not enabled():
		return 1.0
	return clampf(h[i] / float(H_MAX[kind[i]]), 0.0, 1.0)


## Dní od poslední seče (−1 = nikdy / mimo louku).
func cut_days_at(x: float, z: float) -> int:
	var i := index_at(x, z)
	if not inited or i < 0 or cut_jd[i] < 0 or world.clock == null:
		return -1
	return world.clock.jd() - cut_jd[i]


## Hustota keřů sukcese 0..1 v buňce louky `i`.
func shrub_of(i: int) -> float:
	var y := int(yu[i])
	if y < SHRUB_YEARS:
		return 0.0
	return clampf(float(y - SHRUB_YEARS + 1) / float(maxi(SHRUB_FULL_YEARS - SHRUB_YEARS + 1, 1)), 0.0, 1.0)


## Posekat louku v okruhu `r` m kolem `pos` (obecní údržba, kosa / sekačka hráče). Vrací počet buněk.
func mow_at(pos: Vector3, r: float) -> int:
	if not inited:
		return 0
	var n := 0
	var jd := world.clock.jd() if world.clock != null else 0
	var c0 := clampi(floori((pos.x - r - x0) / CELL), 0, nx - 1)
	var c1 := clampi(floori((pos.x + r - x0) / CELL), 0, nx - 1)
	var r0 := clampi(floori((pos.z - r - z0) / CELL), 0, nz - 1)
	var r1 := clampi(floori((pos.z + r - z0) / CELL), 0, nz - 1)
	for rr in range(r0, r1 + 1):
		for cc in range(c0, c1 + 1):
			var i := cell_of[rr * nx + cc]
			if i < 0:
				continue
			var dx := x0 + (cc + 0.5) * CELL - pos.x
			var dz := z0 + (rr + 0.5) * CELL - pos.z
			if dx * dx + dz * dz > (r + CELL * 0.5) * (r + CELL * 0.5):
				continue
			h[i] = minf(h[i], H_CUT)
			cut_jd[i] = jd
			_img_data[gi[i]] = int(clampf(h[i] / float(H_MAX[kind[i]]), 0.0, 1.0) * 255.0)
			n += 1
	if n > 0:
		_commit_image()
	return n


## Popis louky v bodě (F2, ladění): typ, hospodaření, výška, dny od seče, roky bez seče.
func info_at(x: float, z: float) -> Dictionary:
	var i := index_at(x, z)
	if not inited or i < 0:
		return {}
	return {"kind": KIND_NAMES[kind[i]], "mgmt": MGMT_NAMES[mgmt[i]], "abandoned": abandoned(i), "h": h[i],
		"cut_days": cut_days_at(x, z), "years_uncut": int(yu[i])}


## Vrstva mapy (F2 → Příroda – ladění): barva typu louky, jas = výška porostu, červeně opuštěné parcely.
func debug_color(x: float, z: float) -> Color:
	var i := index_at(x, z)
	if not inited or i < 0:
		return Color(0, 0, 0, 0)
	var cols := [Color(0.45, 0.7, 0.3), Color(0.2, 0.5, 0.75), Color(0.85, 0.75, 0.3), Color(0.6, 0.45, 0.6)]
	var c: Color = cols[kind[i]]
	c = c.darkened(0.6 * (1.0 - clampf(h[i] / float(H_MAX[kind[i]]), 0.0, 1.0)))
	if int(yu[i]) >= SHRUB_YEARS:
		c = c.lerp(Color(0.8, 0.2, 0.15), 0.6)
	c.a = 0.75
	return c


# ------------------------------------------------------------------ uložení

## Klíč `meadows`: výška (u8, cm/0,5), den seče (relativně k dnešku, i32) a roky bez seče, ZSTD + base64.
func to_dict() -> Dictionary:
	if not inited:
		return _pending.duplicate()
	var hb := PackedByteArray()
	hb.resize(gi.size())
	for i in gi.size():
		hb[i] = clampi(int(roundf(h[i] * 200.0)), 0, 255)
	var cb := cut_jd.to_byte_array()
	return {"v": SAVE_VER, "n": gi.size(), "nx": nx, "nz": nz, "jd": _last_jd, "year": _year, "seed": seedlings,
		"h": Marshalls.raw_to_base64(hb.compress(FileAccess.COMPRESSION_ZSTD)),
		"c": Marshalls.raw_to_base64(cb.compress(FileAccess.COMPRESSION_ZSTD)), "cl": cb.size(),
		"y": Marshalls.raw_to_base64(yu.compress(FileAccess.COMPRESSION_ZSTD))}


## Starý save bez klíče = louky podle data (hrubý odhad). Neshodná mřížka (jiná data) → ignorovat.
func restore(d: Dictionary) -> void:
	if d.is_empty():
		return
	if not inited or _step_busy:
		_pending = d                       # použije se po dokončení inicializace / rozpracovaného kroku
		return
	_apply_restore(d)
	_write_image_all()


func _flush_pending() -> void:
	if _pending.is_empty():
		return
	_apply_restore(_pending)
	_pending = {}
	_write_image_all()


func _apply_restore(d: Dictionary) -> void:
	if int(d.get("v", 0)) != SAVE_VER or int(d.get("n", -1)) != gi.size() or int(d.get("nx", 0)) != nx \
			or int(d.get("nz", 0)) != nz:
		return
	var n := gi.size()
	var hb := Marshalls.base64_to_raw(String(d.get("h", ""))).decompress(n, FileAccess.COMPRESSION_ZSTD)
	var cb := Marshalls.base64_to_raw(String(d.get("c", ""))).decompress(int(d.get("cl", n * 4)), FileAccess.COMPRESSION_ZSTD)
	var yb := Marshalls.base64_to_raw(String(d.get("y", ""))).decompress(n, FileAccess.COMPRESSION_ZSTD)
	if hb.size() != n or cb.size() != n * 4 or yb.size() != n:
		return
	for i in n:
		h[i] = float(hb[i]) / 200.0
	cut_jd = cb.to_int32_array()
	yu = yb
	seedlings = int(d.get("seed", 0))
	_year = int(d.get("year", _year))
	_last_jd = int(d.get("jd", _last_jd))
