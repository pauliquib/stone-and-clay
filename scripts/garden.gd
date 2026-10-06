## Zahrada a pole (M2.4), jeden uzel ve `World` (`World.garden`).
##
## - **Plocha** (`Plot`): mřížka záhonů 1 × 1 m. „zahrada“ = 12 × 8 m u domova hráče 1 (nájemník bytu ji má pronajatou
##   blízko bydliště, vlastník domu je na své; stěhuje se s domovem přes `World.apply_home` → `relocate`).
##   Místo hledá `_find_spot` podobně jako výběh koně (mezi domem
##   a zahradou rezerva `RAMP_SIZE` pro U-rampu M5.8); když nic nevyjde, zkouší menší plochy a volnější podmínky
##   (`SPOT_STAGES`) a nakonec vezme nejlepší nalezené místo – zahrada se založí vždy. „pole“ = pronajatá plocha 10 × 10 m na orné půdě
##   z OSM (`Fields.class_at == 1`), pronájem na úřadě (`RENT_KC` Kč na `RENT_DAYS` dní, služba `pronajem_pole`).
## - **Stav záhonu** (slovník v `Plot.cells`, klíč = Vector2i; chybí = tráva): `s` (ZRYTO / ZASETO / ZRALE), `c` (plodina z `CROPS`),
##   `g` (nasbíraný růst v „růstových dnech“), `dry` (dny sucha za sebou), `m` (dny zbývající vláhy), `w` (plevel 0..1),
##   `h` (zdraví 0..1), `o` (dny po dozrání), `f` (hnojivo 0..1 – akce `hnojit`, klesá `FERT_DECAY` za den).
## - **Výbava zahrady** (Fáze 8, §11 plánu; jen plocha „zahrada“, stěhuje se s ní – pozice se počítají z `Plot`):
##   sud s kohoutkem (cíl `kohoutek`), **studna** (cíl `studna` = akce `naplnit_studna` + E „nabrat vodu“),
##   **kompost** (E „vzít hnůj“ → předmět `hnuj`, zásoba `compost_left` se doplňuje 1/den do `COMPOST_MAX`),
##   **skleník** 3 × 2 m v zadním pravém rohu (`GH_SIZE`; záhony pod ním mají `GH_BONUS` = +10 °C a mráz je
##   nezabíjí – `gh_cell`). Plot okolo staví `FenceManager`, ne tento uzel.
## - **Cyklus** (akce z `Actions.DEFS`, cíl `zahon`, záhon určuje `aim_cell` z pohledu hráče): `ryt` (lopata / motyka) → `sit` (semena
##   z kapsy, jen ve `sow_months`) → `zalevat` (konev z kohoutku / vody: `naplnit`, `naplnit_kohoutek`) / `plet` → `sklidit` →
##   záhon zpět „zryto“. `zahon_info` = prohlídka záhonu.
## - **Růst**: jeden krok za herní den (změna `Clock.jd()`, při spánku a skoku času se dožene po dnech, nejvýš `MAX_CATCHUP_DAYS`).
##   Přírůstek = teplotní faktor × vláha × (1 − plevel/2); bez vláhy víc než `water_need` dní plodina vadne a ztrácí zdraví; mráz pod
##   `frost_kill` plodinu zničí (kontrola průběžně i při denním kroku). Výnos podle zdraví, plevele, doby po dozrání a Zahradničení.
## - **Ukládání**: `to_dict` / `restore` (klíč `garden` v `SaveGame`): záhony, pronájem pole, zvolená semena, náplň konve.
## API pro další kroky: `plot_at(pos)` / `in_plot(pos, margin)` (M2.5: nesázet stromy do záhonů), `CROPS[..]["feed"]` a klíč
## `feed` u úrody v `ItemsDB` (M2.6: krmivo), `cells_of_crop(item)`, signál-událost `harvest` {crop, item, n} přes `World.emit_game_event`.
class_name Garden
extends Node3D

# ------------------------------------------------------------------ laditelné hodnoty

const GARDEN_SIZE := Vector2i(12, 8)     # m (šířka × hloubka) – DOPLNIT: skutečný tvar zahrady u usedlosti
const RAMP_SIZE := Vector2(8.0, 6.0)     # m – DOPLNIT: rezerva mezi domem a zahradou pro U-rampu (M5.8), zatím prázdná
const FIELD_SIZE := Vector2i(10, 10)     # m – záhony na pronajatém poli (velkoplošná orba traktorem = otevřený bod)
const RENT_KC := 1500                    # Kč za rok – DOPLNIT: cena pronájmu pole
const RENT_DAYS := 365
const KONOPI_LEGAL := 3                  # M4.8: rostlin konopí bez přestupku (40/2009 Sb. po novele – NEOVĚŘENO, viz zakon.json)
const SPOT_R0 := 8.0                     # hledání místa zahrady: od … do (m od dveří)
const SPOT_R1 := 70.0
const SPOT_TRIES := 320
const SPOT_MAX_DH := 1.4                 # největší převýšení plochy zahrady (m)
const SPOT_ROAD_GAP := 2.5
## Když se plná zahrada (s rezervou pro rampu) nevejde: další pokusy [velikost záhonů, rezerva rampy, nejdál m od dveří,
## odstup od silnice m, stromy jen uvnitř plochy (true) / i v okolí]. Poslední záchrana = nejlepší kandidát bez kontroly kolizí.
const SPOT_STAGES := [[Vector2i(12, 8), 0.0, 90.0, 1.5, true], [Vector2i(10, 6), 0.0, 120.0, 1.0, true],
	[Vector2i(8, 5), 0.0, 160.0, 0.5, true], [Vector2i(6, 4), 0.0, 220.0, 0.5, true]]
const FIELD_R0 := 40.0                   # hledání pole: od … do (m od dveří)
const FIELD_R1 := 1600.0
const FIELD_MAX_DH := 2.0
const CAN_CHARGES := 8                   # kolik záhonů zalije jedna plná konev
const MOIST_WATER := 2.0                 # dní vláhy po zalití
const MOIST_RAIN := 3.0                  # dní vláhy po dešti
const DRY_GROWTH := 0.35                 # násobek růstu v suchu
const WEED_WET := 0.08                   # přírůstek plevele za den (vlhko) …
const WEED_DRY := 0.04                   # … a v suchu
const WEED_GROWTH_K := 0.5               # plevel 100 % ubere tolik růstu
const WILT_DAMAGE := 0.15                # ztráta zdraví za den vadnutí
const HEAL_WET := 0.1                    # zotavení zdraví za den s vláhou
const OVER_PENALTY := 0.02               # ztráta kvality úrody za den po dozrání (nejvýš OVER_MAX)
const OVER_MAX := 0.6
const COLD_GROWTH := 0.3                 # růst „zimních“ plodin (česnek) v chladu
const NIGHT_DROP := 3.0                  # °C – denní krok mimo noc počítá s ranním minimem o tolik nižším
const MAX_CATCHUP_DAYS := 400
const AIM_RANGE := 4.0
const CHECK_S := 1.0                     # jak často kontrolovat mráz / déšť (s)
const RAIN_SKIP_BASE := 0.12             # šance deště za přeskočený den = základ + K × vlhko posledních dní
const RAIN_SKIP_K := 0.35
const DIG_MOD := {"lopata": 1.0, "motyka": 0.7}   # násobek doby rytí podle nástroje
const ROMAN := ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII"]
# ---- Fáze 8: výbava zahrady (§11 plánu)
const GH_SIZE := Vector2i(3, 2)      # skleník (m = záhony) v zadním pravém rohu zahrady
const GH_BONUS := 10.0               # °C navíc uvnitř skleníku (mráz pod ním nezabíjí)
const GH_WALL_H := 1.9               # výška skleníku u okapu (m)
const GH_RIDGE_H := 2.45             # výška hřebene střechy (m)
const COMPOST_MAX := 6               # dávek hnoje v kompostu; doplňuje se 1 za herní den
const FERT_MAX := 1.0                # plné pohnojení záhonu (klíč `f`)
const FERT_K := 0.4                  # +40 % růstu při plném hnojení
const FERT_DECAY := 0.1              # úbytek hnojiva za den (účinek ~10 dní)

## Plodiny. sow_months = měsíce výsevu, days = růstové dny do zralosti (při plném růstu), water_need = kolik dní bez vláhy snese,
## frost_kill = pod touto teplotou (°C) zmrzne, yield = [min, max] kusů, xp = XP Zahradničení za sklizeň, feed = hodnota jako krmivo (M2.6),
## cold_ok = roste i v chladu (česnek), min_temp = pod ní neroste vůbec, h = výška dospělé rostliny (m), wid/lean = tvar listů.
const CROPS := {
	"brambory": {"name": "Brambory", "item": "brambory", "seed": "semena_brambory", "sow_months": [4, 5], "days": 100,
		"water_need": 3, "frost_kill": -1.0, "yield": [6, 12], "xp": 12.0, "feed": 1.0, "min_temp": 5.0,
		"leaf": Color(0.26, 0.5, 0.2), "ripe": Color(0.55, 0.55, 0.25), "h": 0.5, "wid": 0.11, "lean": 0.18},
	"mrkev": {"name": "Mrkev", "item": "mrkev", "seed": "semena_mrkev", "sow_months": [4, 5, 6], "days": 80,
		"water_need": 3, "frost_kill": -6.0, "yield": [8, 16], "xp": 8.0, "feed": 1.0, "min_temp": 5.0,
		"leaf": Color(0.3, 0.58, 0.22), "ripe": Color(0.35, 0.62, 0.22), "h": 0.3, "wid": 0.05, "lean": 0.08},
	"cibule": {"name": "Cibule", "item": "cibule", "seed": "semena_cibule", "sow_months": [3, 4], "days": 90,
		"water_need": 3, "frost_kill": -6.0, "yield": [6, 12], "xp": 8.0, "feed": 0.0, "min_temp": 4.0,
		"leaf": Color(0.35, 0.62, 0.25), "ripe": Color(0.7, 0.62, 0.25), "h": 0.4, "wid": 0.035, "lean": 0.04},
	"salat": {"name": "Salát", "item": "salat", "seed": "semena_salat", "sow_months": [4, 5, 6, 7, 8], "days": 45,
		"water_need": 1, "frost_kill": -3.0, "yield": [2, 4], "xp": 6.0, "feed": 0.6, "min_temp": 5.0,
		"leaf": Color(0.42, 0.72, 0.28), "ripe": Color(0.5, 0.78, 0.3), "h": 0.18, "wid": 0.14, "lean": 0.16},
	"rajcata": {"name": "Rajčata", "item": "rajce", "seed": "semena_rajcata", "sow_months": [5], "days": 90,
		"water_need": 2, "frost_kill": 0.0, "yield": [8, 16], "xp": 14.0, "feed": 0.0, "min_temp": 8.0,
		"leaf": Color(0.24, 0.5, 0.18), "ripe": Color(0.24, 0.5, 0.18), "h": 0.9, "wid": 0.12, "lean": 0.14},
	"dyne": {"name": "Dýně", "item": "dyne", "seed": "semena_dyne", "sow_months": [5], "days": 120,
		"water_need": 2, "frost_kill": 0.0, "yield": [2, 4], "xp": 16.0, "feed": 1.5, "min_temp": 8.0,
		"leaf": Color(0.28, 0.5, 0.2), "ripe": Color(0.4, 0.5, 0.2), "h": 0.3, "wid": 0.2, "lean": 0.3},
	"cesnek": {"name": "Česnek", "item": "cesnek", "seed": "semena_cesnek", "sow_months": [10, 11], "days": 160,
		"water_need": 5, "frost_kill": -22.0, "yield": [4, 8], "xp": 10.0, "feed": 0.0, "min_temp": -8.0, "cold_ok": true,
		"leaf": Color(0.4, 0.62, 0.28), "ripe": Color(0.75, 0.68, 0.3), "h": 0.45, "wid": 0.03, "lean": 0.05},
	# M4.8: obsah pro dospělé (jen při zapnuté volbě, viz crop_visible)
	"tabak": {"name": "Tabák", "item": "tabak_list", "seed": "tabak_semena", "sow_months": [4, 5], "days": 90,
		"water_need": 3, "frost_kill": -2.0, "yield": [6, 12], "xp": 8.0, "feed": 0.0, "min_temp": 8.0, "adult": true,
		"fresh": "tabak_cerstvy",
		"leaf": Color(0.3, 0.55, 0.22), "ripe": Color(0.45, 0.5, 0.2), "h": 0.9, "wid": 0.1, "lean": 0.15},
	"konopi": {"name": "Konopí", "item": "konopi_susene", "seed": "konopi_semena", "sow_months": [4, 5], "days": 110,
		"water_need": 3, "frost_kill": -2.0, "yield": [4, 8], "xp": 10.0, "feed": 0.0, "min_temp": 8.0, "adult": true,
		"fresh": "konopi_cerstve",
		"leaf": Color(0.22, 0.5, 0.2), "ripe": Color(0.4, 0.5, 0.22), "h": 1.6, "wid": 0.06, "lean": 0.1},
}
const SUSENI_DAYS := 14.0                # M4.8 sušák: čerstvá sklizeň tabáku / konopí schne tolik dní (ladit)
const CROP_ORDER := ["brambory", "mrkev", "cibule", "salat", "rajcata", "dyne", "cesnek", "tabak", "konopi"]

## Plodina je k dispozici (není dospělý obsah, nebo je volba zapnutá).
static func crop_visible(k: String) -> bool:
	return CROPS.has(k) and (not bool(CROPS[k].get("adult", false)) or ItemsDB.adult_on)


const S_ZRYTO := 1
const S_ZASETO := 2
const S_ZRALE := 3

const SOIL_DRY := Color(0.32, 0.22, 0.14)
const SOIL_WET := Color(0.2, 0.14, 0.09)
const RIDGE := Color(0.27, 0.18, 0.11)
const WOOD := Color(0.42, 0.3, 0.18)
const STEEL := Color(0.62, 0.64, 0.68)      # kov (klika studny, hrábě …)
const WEED := Color(0.42, 0.68, 0.2)
const WILTED := Color(0.62, 0.52, 0.22)


## Plocha záhonů (zahrada / pole). Souřadnice záhonu = Vector2i(i, j), i doprava (podél `right`), j od domu (podél `fwd`).
class Plot:
	extends RefCounted
	var key := "zahrada"
	var title := "Zahrada"
	var center := Vector3.ZERO
	var yaw := 0.0
	var w := 12
	var d := 8
	var cells := {}
	var mi: MeshInstance3D
	var dirty := true
	var sign_pos := Vector3.ZERO

	func right() -> Vector3:
		return Vector3(cos(yaw), 0.0, -sin(yaw))

	func fwd() -> Vector3:
		return Vector3(sin(yaw), 0.0, cos(yaw))

	## Bod na rovině plochy (bez výšky) z místních souřadnic (m od středu).
	func local_pos(lx: float, lz: float) -> Vector3:
		return center + right() * lx + fwd() * lz

	func cell_center(c: Vector2i) -> Vector3:
		return local_pos(float(c.x) + 0.5 - float(w) * 0.5, float(c.y) + 0.5 - float(d) * 0.5)

	## Záhon pod bodem, nebo Vector2i(-1, -1) mimo plochu (`margin` = přesah v m).
	func cell_at(pos: Vector3, margin := 0.0) -> Vector2i:
		var rel := pos - center
		var lx := rel.dot(right()) + float(w) * 0.5
		var lz := rel.dot(fwd()) + float(d) * 0.5
		if lx < -margin or lz < -margin or lx >= float(w) + margin or lz >= float(d) + margin:
			return Vector2i(-1, -1)
		return Vector2i(clampi(floori(lx), 0, w - 1), clampi(floori(lz), 0, d - 1))


var world: World
var ok := false                          # zahrada u domu se podařilo umístit
var plots: Array = []                    # Plot
var ramp_center := Vector3.ZERO          # rezerva pro U-rampu (M5.8) mezi domem a zahradou
var ramp_yaw := 0.0
var rent_until := -1                     # Clock.jd() do kdy je pole pronajaté (−1 = nepronajato)
var sow_pick := {}                       # id hráče → klíč plodiny, kterou chce sít
var can_left := {}                       # id hráče → kolik záhonů ještě zalije plná konev

var _last_jd := -1
var _rained_today := false
var _chk := 0.0
var _rebuild_t := 0.0
var _tap := {}                           # cíl „kohoutek“ (sud s vodou u zahrady)
var _studna := {}                        # cíl „studna“ u zahrady (Fáze 8)
var compost_left := COMPOST_MAX          # dávek hnoje v kompostu (doplňuje se 1/den, ukládá se)
var gh_built := true                     # skleník je součást zahrady (výchozí true; starý save bez klíče = stojí)

static var _glass_mat: StandardMaterial3D   # sdílené poloprůhledné „sklo“ skleníku


func setup(w: World) -> void:
	world = w
	name = "Zahrada"
	Actions.set_handler("ryt", _on_dig)
	Actions.set_handler("sit", _on_sow)
	Actions.set_handler("zalevat", _on_water)
	Actions.set_handler("sklidit", _on_harvest)
	Actions.set_handler("plet", _on_weed)
	Actions.set_handler("hnojit", _on_fertilize)
	Actions.set_handler("naplnit", _on_fill)
	Actions.set_handler("naplnit_kohoutek", _on_fill)
	Actions.set_handler("naplnit_studna", _on_fill)
	Actions.set_handler("zahon_info", _on_info)
	Actions.set_target_check("ryt", _check_dig)
	Actions.set_target_check("sit", _check_sow)
	Actions.set_target_check("zalevat", _check_water)
	Actions.set_target_check("sklidit", _check_harvest)
	Actions.set_target_check("plet", _check_weed)
	Actions.set_target_check("hnojit", _check_fertilize)
	Actions.set_target_check("naplnit", _check_fill)
	Actions.set_target_check("naplnit_kohoutek", _check_fill)
	Actions.set_target_check("naplnit_studna", _check_fill)
	Actions.set_time_mod("ryt", _mod_dig)
	_last_jd = w.clock.jd() if w.clock else -1
	if not w.places.has("domov"):
		return
	relocate()


## (Pře)hledá volné místo pro zahradu u domova hráče 1 a záhony tam položí / přestěhuje. Volá `setup` a
## `World.apply_home` při každé změně domova (nájem v bytě, načtení savu, M4.7 koupě). Místo je vždy bez
## kolizí (silnice, budovy, rekvizity, stromy, výběh, parkování; `SPOT_STAGES` zkouší menší plochy dál
## od domu, `_last_resort` je poslední pojistka). Stav záhonů (`cells` = lokální indexy) přesun přežije,
## buňky mimo nový rozměr se zahodí.
func relocate() -> void:
	var a: Dictionary = world.home_grounds()
	var door: Vector3 = a["door"]
	var park: Vector3 = a["park"]
	var face: Vector2 = a["face"]
	var size := GARDEN_SIZE
	var ramp := RAMP_SIZE.y
	var fp := Vector2(float(GARDEN_SIZE.x), float(GARDEN_SIZE.y) + RAMP_SIZE.y)
	var sp: Array = _find_spot(door, park, face, fp, SPOT_R1, SPOT_ROAD_GAP, false, 2214)   # 2214 = jen seed
	if sp.is_empty():
		for st in SPOT_STAGES:
			var gs: Vector2i = st[0]
			var rr: float = st[1]
			sp = _find_spot(door, park, face, Vector2(float(gs.x), float(gs.y) + rr), float(st[2]), float(st[3]), bool(st[4]), 2215)
			if not sp.is_empty():
				size = gs
				ramp = rr
				break
	if sp.is_empty():
		var smallest: Array = SPOT_STAGES[SPOT_STAGES.size() - 1]
		size = smallest[0]
		ramp = 0.0
		sp = _last_resort(door, face, Vector2(float(size.x), float(size.y)))
		push_warning("Zahrada u domova: volné místo bez překážek nenalezeno – záhony %d × %d m na nejlepším místě." % [size.x, size.y])
	elif size != GARDEN_SIZE:
		print("Zahrada u domova: plná plocha se nevešla – záhony %d × %d m." % [size.x, size.y])
	var c: Vector3 = sp[0]
	var yw: float = sp[1]
	var fwd := Vector3(sin(yw), 0.0, cos(yw))
	ramp_yaw = yw
	ramp_center = c - fwd * (float(size.y) * 0.5)
	ramp_center.y = _ground(ramp_center)
	var gc := c + fwd * (ramp * 0.5)
	gc.y = _ground(gc)
	var pl := plot_by_key("zahrada")
	if pl == null:
		_add_plot("zahrada", "Zahrada", gc, yw, size.x, size.y)
	else:
		# přestěhovat: mesh se přestaví přes dirty, cíl „kohoutek“ se přesune se záhonem (v `_tap` je ten samý slovník)
		pl.center = gc
		pl.yaw = yw
		pl.w = size.x
		pl.d = size.y
		pl.sign_pos = pl.local_pos(-float(pl.w) * 0.5 - 0.4, -float(pl.d) * 0.5 - 0.2)
		pl.sign_pos.y = _ground(pl.sign_pos)
		pl.dirty = true
		if not _tap.is_empty():
			_tap["pos"] = pl.sign_pos + pl.right() * -1.0 + Vector3(0, 0.6, 0)
		if not _studna.is_empty():
			_studna["pos"] = _well_pos(pl) + Vector3(0, 0.7, 0)
		for k in pl.cells.keys():
			if k.x >= pl.w or k.y >= pl.d:
				pl.cells.erase(k)
	ok = true


# ------------------------------------------------------------------ umístění

func _ground(p: Vector3) -> float:
	return world.terrain.height_at(p.x, p.z) if world.terrain else p.y


## Volné místo pro plochu `size` (šířka × hloubka) kolem dveří `door` (od SPOT_R0 do `r1` m): bez silnice (`road_gap` m navíc
## k půlúhlopříčce), budov, rekvizit, stromů (`trees_inside` = jen stromy uvnitř plochy), výběhu koně a parkoviště `park`.
## Vrací [střed, yaw (směr od domu)] nebo [].
func _find_spot(door: Vector3, park: Vector3, face_from: Vector2, size: Vector2, r1: float, road_gap: float,
		trees_inside: bool, seed_: int) -> Array:
	var space := world.get_world_3d().direct_space_state
	var bx := BoxShape3D.new()
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = bx
	q.collision_mask = 1 | 8 | 16
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var diag := size.length() * 0.5
	var tree_r := minf(size.x, size.y) * 0.5 if trees_inside else diag
	var pad = world.paddock
	for i in SPOT_TRIES:
		var a := rng.randf() * TAU
		var r := lerpf(SPOT_R0, r1, float(i) / SPOT_TRIES)
		var x := door.x + cos(a) * r
		var z := door.z + sin(a) * r
		if world.dist_to_roads(Vector2(x, z)) < diag + road_gap:
			continue
		if Vector2(x, z).distance_to(Vector2(park.x, park.z)) < diag + 3.0:
			continue
		if pad != null and pad.ok and Vector2(x, z).distance_to(Vector2(pad.center.x, pad.center.z)) < diag + pad.half.length() + 1.5:
			continue
		if world.trees != null and world.trees.nearest_tree(Vector3(x, 0.0, z), tree_r) >= 0:
			continue
		var away := Vector2(x, z) - face_from
		var yw := atan2(away.x, away.y)
		var fwd := Vector3(sin(yw), 0, cos(yw))
		var right := Vector3(cos(yw), 0, -sin(yw))
		var ok_ := true
		var hmin := INF
		var hmax := -INF
		for sx in [-1.0, 0.0, 1.0]:
			for sz_ in [-1.0, 0.0, 1.0]:
				var pp: Vector3 = Vector3(x, 0, z) + right * (size.x * 0.5 * float(sx)) + fwd * (size.y * 0.5 * float(sz_))
				var h: float = world.terrain.height_at(pp.x, pp.z)
				hmin = minf(hmin, h)
				hmax = maxf(hmax, h)
				var ray := PhysicsRayQueryParameters3D.create(Vector3(pp.x, h + 40.0, pp.z), Vector3(pp.x, h - 3.0, pp.z), 1)
				var hit := space.intersect_ray(ray)
				if hit.is_empty() or (hit["collider"] as Node).get_meta("surface", "") != "teren":
					ok_ = false
					break
			if not ok_:
				break
		if not ok_ or hmax - hmin > SPOT_MAX_DH:
			continue
		bx.size = Vector3(size.x + 0.6, 2.0, size.y + 0.6)
		q.transform = Transform3D(Basis(Vector3.UP, yw), Vector3(x, hmax + 0.2 + 1.0, z))
		if space.intersect_shape(q, 1).is_empty():
			return [Vector3(x, world.terrain.height_at(x, z), z), yw]
	return []


## Poslední záchrana (M1.7 – zahrada se musí založit vždy): nejrovnější místo 10–120 m od dveří mimo silnici, pod jehož
## středem je terén (ne střecha); kolize s rekvizitami a stromy se nekontrolují. Bez takového místa 12 m před dveřmi.
func _last_resort(door: Vector3, face_from: Vector2, size: Vector2) -> Array:
	var space := world.get_world_3d().direct_space_state
	var rng := RandomNumberGenerator.new()
	rng.seed = 2216
	var best := []
	var best_score := INF
	var diag := size.length() * 0.5
	for i in 200:
		var a := rng.randf() * TAU
		var r := lerpf(10.0, 120.0, float(i) / 200.0)
		var x := door.x + cos(a) * r
		var z := door.z + sin(a) * r
		if world.dist_to_roads(Vector2(x, z)) < diag + 0.5:
			continue
		var h: float = world.terrain.height_at(x, z)
		var ray := PhysicsRayQueryParameters3D.create(Vector3(x, h + 40.0, z), Vector3(x, h - 3.0, z), 1)
		var hit := space.intersect_ray(ray)
		if hit.is_empty() or (hit["collider"] as Node).get_meta("surface", "") != "teren":
			continue
		var dh := 0.0
		for o in [Vector2(diag, 0.0), Vector2(-diag, 0.0), Vector2(0.0, diag), Vector2(0.0, -diag)]:
			var ov: Vector2 = o
			dh = maxf(dh, absf(world.terrain.height_at(x + ov.x, z + ov.y) - h))
		var score := dh * 10.0 + r * 0.05
		if score < best_score:
			var away := Vector2(x, z) - face_from
			best_score = score
			best = [Vector3(x, h, z), atan2(away.x, away.y)]
	if best.is_empty():
		var away2 := Vector2(door.x, door.z) - face_from
		var yw := atan2(away2.x, away2.y) if away2.length() > 0.1 else 0.0
		var p := door + Vector3(sin(yw), 0.0, cos(yw)) * 12.0
		p.y = world.terrain.height_at(p.x, p.z)
		best = [p, yw]
	return best


## Nejbližší plocha orné půdy (`Fields.class_at == 1`) pro pole `FIELD_SIZE`: [střed] nebo [] (bez dat `landuse.bin` nic).
func _find_field_spot(door: Vector3) -> Array:
	if world.fields == null or not world.fields.loaded:
		return []
	var hx := float(FIELD_SIZE.x) * 0.5
	var hz := float(FIELD_SIZE.y) * 0.5
	var r := FIELD_R0
	while r <= FIELD_R1:
		var n := maxi(12, int(TAU * r / 25.0))
		for k in n:
			var a := TAU * float(k) / float(n)
			var x := door.x + cos(a) * r
			var z := door.z + sin(a) * r
			var good := true
			var hmin := INF
			var hmax := -INF
			for sx in [-1.0, 0.0, 1.0]:
				for sz in [-1.0, 0.0, 1.0]:
					var px := x + hx * float(sx)
					var pz := z + hz * float(sz)
					if world.fields.class_at(px, pz) != 1:
						good = false
						break
					var h: float = world.terrain.height_at(px, pz)
					hmin = minf(hmin, h)
					hmax = maxf(hmax, h)
				if not good:
					break
			if good and hmax - hmin <= FIELD_MAX_DH and world.dist_to_roads(Vector2(x, z)) > 9.0:
				return [Vector3(x, world.terrain.height_at(x, z), z)]
		r += 20.0
	return []


# ------------------------------------------------------------------ plochy

func _add_plot(key: String, title: String, center: Vector3, yaw: float, w: int, d: int) -> Plot:
	var pl := Plot.new()
	pl.key = key
	pl.title = title
	pl.center = center
	pl.yaw = yaw
	pl.w = w
	pl.d = d
	pl.sign_pos = pl.local_pos(-float(w) * 0.5 - 0.4, -float(d) * 0.5 - 0.2)
	pl.sign_pos.y = _ground(pl.sign_pos)
	pl.mi = MeshInstance3D.new()
	pl.mi.name = "Zahony_" + key
	pl.mi.visibility_range_end = 220.0
	add_child(pl.mi)
	plots.append(pl)
	if key == "zahrada":
		_tap = {"pos": pl.sign_pos + pl.right() * -1.0 + Vector3(0, 0.6, 0), "r": 1.6, "kind": "kohoutek"}
		world.register_target(_tap)
		_studna = {"pos": _well_pos(pl) + Vector3(0, 0.7, 0), "r": 1.6, "kind": "studna"}   # Fáze 8
		world.register_target(_studna)
	if world.fences:
		world.fences.rebuild()      # nová plocha = nový obvodový plot (Fáze 7)
	return pl


func _remove_plot(pl: Plot) -> void:
	if is_instance_valid(pl.mi):
		pl.mi.queue_free()
	plots.erase(pl)
	if world.fences:
		world.fences.rebuild()      # plot zaniklé plochy (vypršelý pronájem) zrušit


func plot_by_key(key: String) -> Plot:
	for pl in plots:
		if (pl as Plot).key == key:
			return pl
	return null


## Plocha, do jejíhož obdélníku (s přesahem `margin` m) bod patří, jinak null. Pro M2.5: nesázet stromy do záhonů.
func plot_at(pos: Vector3, margin := 0.0) -> Plot:
	for pl in plots:
		if (pl as Plot).cell_at(pos, margin) != Vector2i(-1, -1):
			return pl
	return null


func in_plot(pos: Vector3, margin := 0.0) -> bool:
	return plot_at(pos, margin) != null


# ------------------------------------------------------------------ výbava zahrady (Fáze 8)

## Střed hromady kompostu – venku za levým zadním rohem zahrady (mimo plot i záhony).
func _compost_pos(pl: Plot) -> Vector3:
	var p := pl.local_pos(-float(pl.w) * 0.5 - 0.9, float(pl.d) * 0.5 + 0.9)
	p.y = _ground(p)
	return p


## Střed studny – venku před pravým předním rohem zahrady (mimo plot, naproti sudu s kohoutkem).
func _well_pos(pl: Plot) -> Vector3:
	var p := pl.local_pos(float(pl.w) * 0.5 + 0.9, -float(pl.d) * 0.5 - 0.9)
	p.y = _ground(p)
	return p


## Záhony pod skleníkem (indexy buněk): pravý zadní roh plochy `GH_SIZE` (u menší zahrady se přiřizne k okraji).
func _gh_rect(pl: Plot) -> Rect2i:
	return Rect2i(maxi(0, pl.w - GH_SIZE.x), maxi(0, pl.d - GH_SIZE.y), mini(GH_SIZE.x, pl.w), mini(GH_SIZE.y, pl.d))


## Je záhon `k` pod skleníkem? (jen plocha „zahrada“, skleník stojí `gh_built`)
func gh_cell(pl: Plot, k: Vector2i) -> bool:
	return gh_built and pl.key == "zahrada" and _gh_rect(pl).has_point(k)


## Obdélník skleníku v lokálních m plochy (střed plochy = 0,0; x doprava, y od domu).
func _gh_lrect(pl: Plot) -> Rect2:
	var r := _gh_rect(pl)
	return Rect2(float(r.position.x) - float(pl.w) * 0.5, float(r.position.y) - float(pl.d) * 0.5,
		float(r.size.x), float(r.size.y))


## Střed skleníku (světové souřadnice na zemi).
func _gh_center(pl: Plot) -> Vector3:
	var r := _gh_lrect(pl)
	var p := pl.local_pos(r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.5)
	p.y = _ground(p)
	return p


## Kolik záhonů má aktuálně zasetou / zralou plodinu s úrodou `item` (např. „brambory“).
func cells_of_crop(item: String) -> int:
	var n := 0
	for pl in plots:
		for c in (pl as Plot).cells.values():
			if int(c["s"]) >= S_ZASETO and String(CROPS[c["c"]]["item"]) == item:
				n += 1
	return n


func field_rented() -> bool:
	return plot_by_key("pole") != null


# ------------------------------------------------------------------ zaměřování

## Záhon, na který hráč míří (M0.4 `ActionRunner.aim_point`): {kind: "zahon", pos, plot, cell} nebo {}.
func aim_cell(p: Player, dir: Vector3, origin: Vector3) -> Dictionary:
	if plots.is_empty():
		return {}
	var near := false
	for pl in plots:
		if (pl as Plot).center.distance_to(p.global_position) < 22.0:
			near = true
			break
	if not near:
		return {}
	var space := p.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * AIM_RANGE, 1)
	q.exclude = [p.get_rid()]
	var hit := space.intersect_ray(q)
	var pos: Vector3
	if hit.is_empty():
		if dir.y > -0.15:
			return {}
		pos = origin + dir * AIM_RANGE
	else:
		pos = hit["position"]
	for pl in plots:
		var c: Vector2i = (pl as Plot).cell_at(pos)
		if c != Vector2i(-1, -1):
			var cp: Vector3 = (pl as Plot).cell_center(c)
			cp.y = _ground(cp)
			return {"kind": "zahon", "pos": cp, "plot": pl, "cell": c}
	return {}


func _cell_of(aim: Dictionary) -> Dictionary:
	var pl: Plot = aim.get("plot")
	var c: Vector2i = aim.get("cell", Vector2i(-1, -1))
	if pl == null or not plots.has(pl):
		return {}
	return pl.cells.get(c, {})


# ------------------------------------------------------------------ pomocné

func _player(id: int) -> Player:
	return world.players.get(id)


func _msg(id: int, text: String, secs := 2.5) -> void:
	world.notify(id, "show_message", [text, secs])


static func months_text(months: Array) -> String:
	if months.is_empty():
		return "-"
	var contiguous := true
	for i in range(1, months.size()):
		if int(months[i]) != int(months[i - 1]) + 1:
			contiguous = false
	if contiguous and months.size() > 1:
		return "%s–%s" % [ROMAN[int(months[0]) - 1], ROMAN[int(months[months.size() - 1]) - 1]]
	var out := []
	for m in months:
		out.append(ROMAN[int(m) - 1])
	return ", ".join(out)


func _crop_name(key: String) -> String:
	return String(CROPS[key]["name"]) if CROPS.has(key) else key


## Kterou plodinu bude hráč sít: zvolenou v nabídce cedule (když má semena), jinak první, kterou lze sít teď, jinak první s semeny; "" bez semen.
func pick_crop(id: int) -> String:
	var p := _player(id)
	if p == null:
		return ""
	var want: String = sow_pick.get(id, "")
	if want != "" and CROPS.has(want) and p.item_count(String(CROPS[want]["seed"])) > 0:
		return want
	var month := world.clock.month()
	var first := ""
	for k in CROP_ORDER:
		if not crop_visible(k) or p.item_count(String(CROPS[k]["seed"])) <= 0:
			continue
		if first == "":
			first = k
		if month in CROPS[k]["sow_months"]:
			return k
	return first


func growth_percent(cell: Dictionary) -> int:
	if not CROPS.has(cell.get("c", "")):
		return 0
	return clampi(roundi(float(cell.get("g", 0.0)) / float(CROPS[cell["c"]]["days"]) * 100.0), 0, 100)


func _wilting(cell: Dictionary) -> bool:
	return int(cell["s"]) == S_ZASETO and int(cell.get("dry", 0)) > int(CROPS[cell["c"]]["water_need"])


func cell_text(cell: Dictionary, gh := false) -> String:
	if cell.is_empty():
		return "Tráva – dá se ryt (lopata nebo motyka)." + (" (ve skleníku)" if gh else "")
	var weeds := " · plevel %d %%" % roundi(float(cell.get("w", 0.0)) * 100.0)
	var fert := " · hnojivo" if float(cell.get("f", 0.0)) > 0.0 else ""
	var ghs := " · skleník" if gh else ""
	match int(cell["s"]):
		S_ZRYTO:
			return "Zryto, čeká na semena%s%s%s." % [weeds, fert, ghs]
		S_ZASETO:
			var wet := "vlhko" if float(cell.get("m", 0.0)) > 0.0 else "sucho"
			if _wilting(cell):
				wet = "VADNE"
			return "%s – %d %% · %s%s%s%s · zdraví %d %%" % [_crop_name(cell["c"]), growth_percent(cell), wet, weeds, fert, ghs,
				roundi(float(cell.get("h", 1.0)) * 100.0)]
		S_ZRALE:
			return "%s – ZRALÉ, sklidit%s%s." % [_crop_name(cell["c"]), weeds, ghs]
	return ""


# ------------------------------------------------------------------ akce: kontroly cíle

func _check_dig(aim: Dictionary, _id: int) -> String:
	var pl: Plot = aim.get("plot")
	if pl == null:
		return "Tady nejde ryt."
	var c := _cell_of(aim)
	if c.is_empty():
		return ""
	return "Tady už je zryto." if int(c["s"]) == S_ZRYTO else "Tady něco roste."


func _check_sow(aim: Dictionary, id: int) -> String:
	var c := _cell_of(aim)
	if c.is_empty():
		return "Nejdřív záhon zryj (lopata / motyka)."
	if int(c["s"]) != S_ZRYTO:
		return "Tady už něco roste."
	var crop := pick_crop(id)
	if crop == "":
		return "Nemáš žádná semena (Potraviny)."
	var months: Array = CROPS[crop]["sow_months"]
	if not (world.clock.month() in months):
		return "Teď se nesází (%s: %s)." % [_crop_name(crop), months_text(months)]
	return ""


func _check_water(aim: Dictionary, id: int) -> String:
	var c := _cell_of(aim)
	if c.is_empty() or int(c["s"]) == S_ZRYTO:
		return "Není co zalévat."
	if int(c["s"]) == S_ZRALE:
		return "Zralé se nezalévá."
	if float(c.get("m", 0.0)) >= MOIST_WATER:
		return "Půda je ještě vlhká."
	if int(can_left.get(id, CAN_CHARGES)) <= 0:
		return "Konev je prázdná."
	return ""


func _check_harvest(aim: Dictionary, _id: int) -> String:
	var c := _cell_of(aim)
	if c.is_empty() or int(c["s"]) == S_ZRYTO:
		return "Není co sklízet."
	if int(c["s"]) == S_ZASETO:
		return "Ještě nedozrálo (%d %%)." % growth_percent(c)
	return ""


func _check_weed(aim: Dictionary, _id: int) -> String:
	var c := _cell_of(aim)
	if c.is_empty() or float(c.get("w", 0.0)) < 0.1:
		return "Tady není co plít."
	return ""


## Hnojit jde na zrytý i rostoucí záhon (ne na zralý, ne dvakrát za sebou); hnůj se bere z kompostu u zahrady.
func _check_fertilize(aim: Dictionary, _id: int) -> String:
	var c := _cell_of(aim)
	if c.is_empty():
		return "Nejdřív záhon zryj (lopata / motyka)."
	if int(c["s"]) == S_ZRALE:
		return "Zralé už nehnoj."
	if float(c.get("f", 0.0)) >= FERT_MAX:
		return "Záhon už je pohnojený."
	return ""


func _check_fill(_aim: Dictionary, _id: int) -> String:
	return ""


func _mod_dig(_aim: Dictionary, tool_id: String) -> float:
	return float(DIG_MOD.get(tool_id, 1.0))


# ------------------------------------------------------------------ akce: výsledky

func _on_dig(id: int, _def: Dictionary, aim: Dictionary, ok_: bool) -> void:
	if not ok_:
		return
	var pl: Plot = aim.get("plot")
	if pl == null or not plots.has(pl) or pl.cells.has(aim["cell"]):
		return
	pl.cells[aim["cell"]] = {"s": S_ZRYTO, "w": 0.0, "h": 1.0}
	pl.dirty = true
	world.play_sfx(id, "step", 0.6, -2.0)


## Počet zasetých / rostoucích rostlin plodiny `crop` ve všech záhonech (M4.8: limit konopí).
func _count_crop(crop: String) -> int:
	var n := 0
	for pl in plots:
		for cell in (pl as Plot).cells.values():
			if String((cell as Dictionary).get("c", "")) == crop:
				n += 1
	return n


func _on_sow(id: int, _def: Dictionary, aim: Dictionary, ok_: bool) -> void:
	var p := _player(id)
	var c := _cell_of(aim)
	if p == null or not ok_ or c.is_empty() or int(c["s"]) != S_ZRYTO:
		return
	var crop := pick_crop(id)
	if crop == "" or not p.remove_item(String(CROPS[crop]["seed"]), 1):
		return
	# M4.8: konopí nad zákonný počet rostlin je vidět na zahradě → svědci (soused, drbna, policie) mohou nahlásit
	if crop == "konopi" and _count_crop("konopi") + 1 > KONOPI_LEGAL \
			and world.witness_reported(id, p.global_position, "pestovani", 25.0):
		world.commit_offense(id, "nedovolene_pestovani", {})
	var pl: Plot = aim["plot"]
	pl.cells[aim["cell"]] = {"s": S_ZASETO, "c": crop, "g": 0.0, "dry": 0, "m": 0.0, "w": float(c.get("w", 0.0)), "h": 1.0, "o": 0,
		"f": float(c.get("f", 0.0))}        # hnojivo v zrytém záhonu výsev přežije – kbelík hnoje nepřijde nazmar
	pl.dirty = true
	world.give_xp(id, "zahradnictvi", 3.0, "sit")
	_msg(id, "Zaseto: %s. Nezapomeň zalévat." % _crop_name(crop), 2.5)


func _on_water(id: int, _def: Dictionary, aim: Dictionary, ok_: bool) -> void:
	var p := _player(id)
	var c := _cell_of(aim)
	if p == null or not ok_ or c.is_empty():
		return
	c["m"] = MOIST_WATER
	c["dry"] = 0
	(aim["plot"] as Plot).dirty = true
	can_left[id] = int(can_left.get(id, CAN_CHARGES)) - 1
	if int(can_left[id]) <= 0:
		_swap_can(p, "konev_plna", "konev")
		_msg(id, "Konev je prázdná – naplň ji u kohoutku (sud u zahrady) nebo u vody.", 3.0)


func _on_harvest(id: int, _def: Dictionary, aim: Dictionary, ok_: bool) -> void:
	var p := _player(id)
	var c := _cell_of(aim)
	if p == null or not ok_ or c.is_empty() or int(c["s"]) != S_ZRALE:
		return
	var crop: String = c["c"]
	var spec: Dictionary = CROPS[crop]
	var sk: Skills = world.skills.get(id)
	var bonus := sk.bonus("zahradnictvi") if sk else 0.0
	var over := minf(OVER_MAX, float(c.get("o", 0)) * OVER_PENALTY)
	var q := float(c.get("h", 1.0)) * (1.0 - 0.35 * float(c.get("w", 0.0))) * (1.0 - over) * (0.85 + 0.3 * bonus)
	q = clampf(q + randf_range(-0.1, 0.1), 0.05, 1.0)
	var yl: Array = spec["yield"]
	var n := maxi(1, roundi(lerpf(float(yl[0]), float(yl[1]), q)))
	var item := String(spec["item"])
	if spec.has("fresh"):
		# M4.8 sušák: čerstvá sklizeň se suší, suchý předmět vznikne později (Vyhlasky.add_batch)
		item = String(spec["fresh"])
		if world.vyhlasky:
			world.vyhlasky.add_batch(id, n, item, String(spec["item"]), SUSENI_DAYS)
	p.add_item(item, n)
	var pl: Plot = aim["plot"]
	pl.cells[aim["cell"]] = {"s": S_ZRYTO, "w": float(c.get("w", 0.0)) * 0.5, "h": 1.0, "f": float(c.get("f", 0.0))}
	pl.dirty = true
	world.give_xp(id, "zahradnictvi", float(spec["xp"]) * (0.5 + 0.5 * q), "sklidit")
	_msg(id, "Sklizeno: %d× %s." % [n, ItemsDB.name_of(item)], 3.0)
	world.emit_game_event(id, "harvest", {"crop": crop, "item": item, "n": n})


func _on_weed(id: int, _def: Dictionary, aim: Dictionary, ok_: bool) -> void:
	var c := _cell_of(aim)
	if not ok_ or c.is_empty():
		return
	c["w"] = 0.0
	(aim["plot"] as Plot).dirty = true
	_msg(id, "Vyplito.", 1.5)


## Pohnojení záhonu: spotřebuje 1× předmět `hnuj` (z kompostu u zahrady), nastaví hnojivo `f` na plné.
func _on_fertilize(id: int, _def: Dictionary, aim: Dictionary, ok_: bool) -> void:
	var p := _player(id)
	var c := _cell_of(aim)
	if p == null or not ok_ or c.is_empty() or float(c.get("f", 0.0)) >= FERT_MAX:
		return
	if not p.remove_item("hnuj", 1):
		return
	c["f"] = FERT_MAX
	(aim["plot"] as Plot).dirty = true
	world.give_xp(id, "zahradnictvi", 2.0, "hnojit")
	_msg(id, "Pohnojeno – poroste asi o %d %% rychleji (~10 dní)." % roundi(FERT_K * 100.0), 2.5)


func _on_info(id: int, _def: Dictionary, aim: Dictionary, _ok: bool) -> void:
	var pl: Plot = aim.get("plot")
	_msg(id, cell_text(_cell_of(aim), pl != null and gh_cell(pl, aim.get("cell", Vector2i(-1, -1)))), 4.0)


func _on_fill(id: int, _def: Dictionary, _aim: Dictionary, ok_: bool) -> void:
	var p := _player(id)
	if p == null or not ok_:
		return
	if _swap_can(p, "konev", "konev_plna"):
		can_left[id] = CAN_CHARGES
		_msg(id, "Konev je plná (zalije %d záhonů)." % CAN_CHARGES, 2.5)


## Je v konvi ještě voda? (M2.5: sdílená s podlivkou zasazených stromů `PlantedTrees`.)
func can_water(id: int) -> bool:
	return int(can_left.get(id, CAN_CHARGES)) > 0


## Spotřebuje `n` dávek plné konve; když dojde, vymění ji za prázdnou. false = konev už byla prázdná.
func spend_can(id: int, p: Player, n: int) -> bool:
	if not can_water(id):
		return false
	can_left[id] = maxi(0, int(can_left.get(id, CAN_CHARGES)) - n)
	if int(can_left[id]) <= 0:
		_swap_can(p, "konev_plna", "konev")
	return true


## Vymění konev v inventáři (prázdná ↔ plná), přenese opotřebení a v ruce drží novou. Vrací true, když se povedlo.
func _swap_can(p: Player, from_id: String, to_id: String) -> bool:
	if p.item_count(from_id) <= 0:
		return false
	var held := p.equipped == from_id
	var dur = p.durability.get(from_id)
	p.remove_item(from_id, 1)
	p.add_item(to_id, 1)
	if dur != null:
		p.durability[to_id] = int(dur)
	if held:
		p.equip(to_id)
	return true


# ------------------------------------------------------------------ interakce (E) – cedule zahrady / pole

func interactables(id: int) -> Array:
	var p: Player = world.players.get(id)
	if p == null or p.inside != "":
		return []
	var out := []
	for pl in plots:
		var q: Plot = pl
		if q.sign_pos.distance_to(p.global_position) > 30.0:
			continue
		out.append({"pos": q.sign_pos + Vector3(0, 0.6, 0), "r": 2.4, "kind": "custom",
			"text": "%s – záhony, semena, konev" % q.title, "action": open_sign_menu.bind(q)})
	# ---- výbava zahrady (Fáze 8): kompost, studna a skleník jen u domácí plochy
	var gz := plot_by_key("zahrada")
	if gz != null and gz.center.distance_to(p.global_position) < 40.0:
		var wp := _well_pos(gz)
		if wp.distance_to(p.global_position) <= 30.0:
			out.append({"pos": wp + Vector3(0, 0.9, 0), "r": 2.6, "kind": "custom",
				"text": "Studna – nabrat vodu do konve", "action": _on_well})
		var cp := _compost_pos(gz)
		if cp.distance_to(p.global_position) <= 30.0:
			out.append({"pos": cp + Vector3(0, 0.5, 0), "r": 2.6, "kind": "custom",
				"text": "Kompost – vzít hnůj (zbývá %d)" % compost_left, "action": _on_compost})
		if gh_built:
			var gp := _gh_center(gz)
			if gp.distance_to(p.global_position) <= 30.0:
				out.append({"pos": gp + Vector3(0, 1.2, 0), "r": 3.4, "kind": "custom",
					"text": "Skleník", "action": _on_gh_info})
	return out


## E u studny: naplní prázdnou konev z kapsy (stejný efekt jako akce `naplnit_studna`, ale bez míření).
func _on_well(id: int) -> void:
	var p := _player(id)
	if p == null:
		return
	if _swap_can(p, "konev", "konev_plna"):
		can_left[id] = CAN_CHARGES
		world.play_sfx(id, "splash", 1.1, -6.0)
		_msg(id, "Nabral jsi vodu ze studny – konev je plná (zalije %d záhonů)." % CAN_CHARGES, 3.0)
	elif p.item_count("konev_plna") > 0:
		_msg(id, "Konev už máš plnou.", 2.0)
	else:
		_msg(id, "Potřebuješ konev (koupíš v Potravinách).", 2.5)


## E u kompostu: vezme 1× `hnuj` do kapsy (zásoba `compost_left`, doplňuje se 1 za herní den).
func _on_compost(id: int) -> void:
	var p := _player(id)
	if p == null:
		return
	if compost_left <= 0:
		_msg(id, "Kompost je vybraný – další hnůj uzraje do zítřka.", 2.5)
		return
	compost_left -= 1
	p.add_item("hnuj", 1)
	world.play_sfx(id, "step", 0.6, -3.0)
	var pl := plot_by_key("zahrada")
	if pl != null:
		pl.dirty = true            # hromada v bedně se viditelně zmenší
	_msg(id, "Nabral jsi kbelík hnoje (v kompostu zbývá %d). Hnoj jím záhony (míř na záhon, LMB)." % compost_left, 3.5)


## E u skleníku: jen informace, co umí.
func _on_gh_info(id: int) -> void:
	var pl := plot_by_key("zahrada")
	var n := 0
	if pl != null:
		var r := _gh_rect(pl)
		n = int(r.size.x * r.size.y)
	_msg(id, "Skleník %d × %d m (%d záhonů): uvnitř je o %d °C tepleji a rostliny tu přežijí mráz, který venku zabije úrodu." % [
		GH_SIZE.x, GH_SIZE.y, n, roundi(GH_BONUS)], 4.5)


func open_sign_menu(id: int, pl: Plot) -> void:
	var p := _player(id)
	if p == null or not plots.has(pl):
		return
	var seeds := 0
	var sown := 0
	var ripe := 0
	var dug := 0
	for c in pl.cells.values():
		match int(c["s"]):
			S_ZRYTO:
				dug += 1
			S_ZASETO:
				sown += 1
			S_ZRALE:
				ripe += 1
	var text := "%s %d × %d m. Zryto prázdných: %d, roste: %d, zralých: %d." % [pl.title, pl.w, pl.d, dug, sown, ripe]
	if pl.key == "pole" and rent_until >= 0:
		text += "\nPronájem platí ještě %d dní." % maxi(0, rent_until - world.clock.jd())
	text += "\nRytí: lopata / motyka (Q), setí: semena v kapse (LMB na zrytý záhon), zálivka: plná konev, sklizeň: prázdné ruce."
	var cur := pick_crop(id)
	if cur != "":
		text += "\nZvolená plodina: %s (%s)." % [_crop_name(cur), months_text(CROPS[cur]["sow_months"])]
	var opts := []
	for k in CROP_ORDER:
		var seed_id := String(CROPS[k]["seed"])
		var n := p.item_count(seed_id)
		if n <= 0 or not crop_visible(k):
			continue
		seeds += 1
		opts.append(["Sít: %s (máš %d; sází se %s)" % [_crop_name(k), n, months_text(CROPS[k]["sow_months"])], pick_seed.bind(id, k)])
	if seeds == 0:
		text += "\nNemáš semena – koupíš je v Potravinách."
	opts.append(["Naplnit konev z kohoutku", fill_can_direct.bind(id), p.item_count("konev") > 0])
	world.notify(id, "open_menu", [pl.title, text, opts])


func pick_seed(id: int, crop: String) -> void:
	sow_pick[id] = crop
	_msg(id, "Budeš sít: %s." % _crop_name(crop), 2.0)


func fill_can_direct(id: int) -> void:
	var p := _player(id)
	if p == null:
		return
	if _swap_can(p, "konev", "konev_plna"):
		can_left[id] = CAN_CHARGES
		_msg(id, "Konev je plná (zalije %d záhonů)." % CAN_CHARGES, 2.5)


# ------------------------------------------------------------------ služba na úřadě: pronájem pole

## Režim „service“ v `Place.OFFERS` (voláno z `World.buy`): `pronajem_pole`.
func service(id: int, item_id: String, base_price: int) -> void:
	var p := _player(id)
	if p == null or item_id != "pronajem_pole":
		return
	var jd := world.clock.jd()
	if field_rented():
		_msg(id, "Pole už máš pronajaté (ještě %d dní)." % maxi(0, rent_until - jd), 3.0)
		return
	var price := world.price_for(id, base_price)
	if p.money < price:
		_msg(id, "Nemáš dost peněz.", 2.0)
		return
	var home: Place = world.places["domov"]
	var sp := _find_field_spot(home.door)
	if sp.is_empty():
		_msg(id, "„Volné pole teď obec nemá.“ (v datech chybí orná půda v okolí)", 3.5)
		return
	p.money -= price
	world.play_sfx(id, "cash")
	var c: Vector3 = sp[0]
	rent_until = jd + RENT_DAYS
	_add_plot("pole", "Pronajaté pole", c, 0.0, FIELD_SIZE.x, FIELD_SIZE.y)
	var dist := roundi(home.door.distance_to(c))
	_msg(id, "Pole pronajato na rok (%d Kč). Leží %d m %s od domu – označuje ho cedule na rohu." % [price,
		dist, world.bearing_text(home.door, c)], 5.0)
	world.emit_game_event(id, "field_rented", {"pos": c})


# ------------------------------------------------------------------ růst (denní krok)

func _process(delta: float) -> void:
	if world == null or world.clock == null:
		return
	_rebuild_t -= delta
	if _rebuild_t <= 0.0:
		_rebuild_t = 0.25
		for pl in plots:
			if (pl as Plot).dirty:
				_rebuild(pl)
	_chk -= delta
	if _chk > 0.0:
		return
	_chk = CHECK_S
	if plots.is_empty():
		_last_jd = world.clock.jd()
		return
	var w: Weather = world.weather
	if w != null and w.is_raining():
		_rained_today = true
	var jd := world.clock.jd()
	if _last_jd < 0:
		_last_jd = jd
	elif jd != _last_jd:
		if jd > _last_jd:
			_advance_days(mini(jd - _last_jd, MAX_CATCHUP_DAYS))
		_last_jd = jd
		_rained_today = false
	_check_frost(w.temp if w != null else 10.0)


func _teplota() -> float:
	return world.weather.temp if world.weather != null else 12.0


## Zmrzlé plodiny (kontrola teploty průběžně). Vrací počet zničených záhonů.
## Záhony pod skleníkem mají `GH_BONUS` navíc – mráz, co venku zabije, skleník ustojí (Fáze 8).
func _check_frost(t: float) -> int:
	var killed := 0
	for pl in plots:
		var q: Plot = pl
		for k in q.cells.keys():
			var c: Dictionary = q.cells[k]
			var tc := t + (GH_BONUS if gh_cell(q, k) else 0.0)
			if int(c["s"]) >= S_ZASETO and tc < float(CROPS[c["c"]]["frost_kill"]):
				q.cells[k] = {"s": S_ZRYTO, "w": float(c.get("w", 0.0)), "h": 1.0, "f": float(c.get("f", 0.0))}
				q.dirty = true
				killed += 1
	if killed > 0:
		_notify_all("Mráz (%d °C) zničil úrodu na %d záhonech." % [roundi(t), killed], 5.0)
	return killed


func _notify_all(text: String, secs: float) -> void:
	for id in world.players.keys():
		_msg(int(id), text, secs)


## Posune růst o `n` herních dnů (spánek, skok času). První den se počítá se skutečným deštěm, přeskočené dny náhodně podle vlhka.
func _advance_days(n: int) -> void:
	var w: Weather = world.weather
	var t := _teplota()
	var hour := world.clock.hour()
	var day_t := t + (3.0 if hour < 9.0 or hour > 19.0 else 0.0)     # průměr dne je teplejší než noc
	var min_t := t - (NIGHT_DROP if hour >= 9.0 else 0.0)
	var raining_now := w != null and w.is_raining()
	var recent := w.rain_recent if w != null else 0.0
	var died := 0
	for i in n:
		var rained := (i == 0 and (_rained_today or raining_now)) or (i > 0 and randf() < RAIN_SKIP_BASE + RAIN_SKIP_K * recent)
		for pl in plots:
			died += _grow_plot(pl, day_t, min_t if (n > 1 or hour >= 9.0) else t, rained)
	if died > 0:
		_notify_all("Na záhonech uschlo %d rostlin (sucho)." % died, 4.0)
	# kompost zraje: 1 dávka hnoje za herní den (Fáze 8)
	if n > 0 and compost_left < COMPOST_MAX:
		compost_left = mini(COMPOST_MAX, compost_left + n)
	# vypršelý pronájem pole
	var pole := plot_by_key("pole")
	if pole != null and rent_until >= 0 and world.clock.jd() > rent_until:
		_remove_plot(pole)
		rent_until = -1
		_notify_all("Pronájem pole skončil, záhony na poli propadly obci.", 5.0)


func _temp_factor(spec: Dictionary, t: float) -> float:
	if t < float(spec["min_temp"]):
		return 0.0
	if t < 5.0:
		return COLD_GROWTH if bool(spec.get("cold_ok", false)) else 0.0
	return clampf((t - 3.0) / 12.0, 0.35, 1.0)


## Denní krok jedné plochy; vrací počet uschlých rostlin. Záhony pod skleníkem počítají s teplotou
## o `GH_BONUS` vyšší (frost_kill i min_temp se efektivně posunou o −10 °C – Fáze 8).
func _grow_plot(pl: Plot, day_t: float, min_t: float, rained: bool) -> int:
	var died := 0
	for k in pl.cells.keys():
		var c: Dictionary = pl.cells[k]
		var s := int(c["s"])
		var gh := gh_cell(pl, k)
		var d_t := day_t + (GH_BONUS if gh else 0.0)
		var m_t := min_t + (GH_BONUS if gh else 0.0)
		# plevel roste na každém zrytém i osetém záhonu
		var wet := false
		if s >= S_ZASETO:
			var spec: Dictionary = CROPS[c["c"]]
			if m_t < float(spec["frost_kill"]):
				pl.cells[k] = {"s": S_ZRYTO, "w": float(c.get("w", 0.0)), "h": 1.0, "f": float(c.get("f", 0.0))}
				pl.dirty = true
				continue
			if rained:
				c["m"] = maxf(float(c.get("m", 0.0)), MOIST_RAIN)
			wet = float(c.get("m", 0.0)) > 0.0
			if wet:
				c["m"] = float(c["m"]) - 1.0
				c["dry"] = 0
				c["h"] = minf(1.0, float(c.get("h", 1.0)) + HEAL_WET)
			else:
				c["dry"] = int(c.get("dry", 0)) + 1
				if int(c["dry"]) > int(spec["water_need"]):
					c["h"] = float(c.get("h", 1.0)) - WILT_DAMAGE
			if float(c["h"]) <= 0.0:
				pl.cells[k] = {"s": S_ZRYTO, "w": float(c.get("w", 0.0)), "h": 1.0, "f": float(c.get("f", 0.0))}
				pl.dirty = true
				died += 1
				continue
			if s == S_ZASETO:
				var f := _temp_factor(spec, d_t)
				if not wet:
					f *= DRY_GROWTH
				f *= 1.0 - WEED_GROWTH_K * float(c.get("w", 0.0))
				f *= 1.0 + FERT_K * float(c.get("f", 0.0))      # hnojivo z kompostu urychluje růst
				c["g"] = float(c.get("g", 0.0)) + f
				if float(c["g"]) >= float(spec["days"]):
					c["s"] = S_ZRALE
			else:
				c["o"] = int(c.get("o", 0)) + 1
		elif rained:
			wet = true
		# hnojivo se vyplavuje / spotřebovává (~FERT_DECAY za den na každém záhonu)
		if float(c.get("f", 0.0)) > 0.0:
			c["f"] = maxf(0.0, float(c.get("f", 0.0)) - FERT_DECAY)
		var wk := (WEED_WET if (wet or rained) else WEED_DRY) * randf_range(0.5, 1.5)
		c["w"] = minf(1.0, float(c.get("w", 0.0)) + wk)
		pl.dirty = true
	return died


# ------------------------------------------------------------------ vzhled

func _rebuild(pl: Plot) -> void:
	pl.dirty = false
	if not is_instance_valid(pl.mi):
		return
	var mk := MeshKit.new()
	_build_frame(mk, pl)
	for k in pl.cells.keys():
		_build_cell(mk, pl, k, pl.cells[k])
	var mesh := mk.commit(MeshKit.vc_material(0.95, 0.0, 0.0, false))
	if pl.key == "zahrada" and gh_built:
		var gk := MeshKit.new()
		_build_greenhouse_glass(gk, pl)
		if not gk.is_empty():
			gk.commit(glass_material(), mesh)       # druhý povrch = poloprůhledné sklo
	pl.mi.mesh = mesh


## Poloprůhledný materiál skla skleníku (sdílený, vertexové barvy nepoužívá – sklo je jednolité).
static func glass_material() -> StandardMaterial3D:
	if _glass_mat == null:
		_glass_mat = StandardMaterial3D.new()
		_glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glass_mat.albedo_color = Color(0.72, 0.86, 0.9, 0.22)
		_glass_mat.roughness = 0.12
		_glass_mat.metallic = 0.15
		_glass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _glass_mat


func _lifted(pl: Plot, lx: float, lz: float, up: float) -> Vector3:
	var p := pl.local_pos(lx, lz)
	p.y = _ground(p) + up
	return p


func _flat(mk: MeshKit, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	var base := mk.verts.size()
	for p in [a, b, c, d]:
		mk.verts.append(p)
		mk.norms.append(Vector3.UP)
		mk.cols.append(col)
	mk.idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])


## Rohové kůly plochy, cedule a (u zahrady) sud s vodou a kohoutkem + výbava Fáze 8:
## studna, kompost a kostra skleníku (sklo doplňuje `_build_greenhouse_glass` jako druhý povrch meshe).
func _build_frame(mk: MeshKit, pl: Plot) -> void:
	var hw := float(pl.w) * 0.5
	var hd := float(pl.d) * 0.5
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var p := _lifted(pl, hw * float(sx), hd * float(sz), 0.0)
			mk.box(p + Vector3(0, 0.35, 0), Vector3(0.08, 0.7, 0.08), WOOD, Vector3(0, pl.yaw, 0))
	var s := pl.sign_pos
	mk.box(s + Vector3(0, 0.55, 0), Vector3(0.07, 1.1, 0.07), WOOD, Vector3(0, pl.yaw, 0))
	mk.box(s + Vector3(0, 0.95, 0) + pl.right() * 0.0, Vector3(0.55, 0.28, 0.04), Color(0.72, 0.6, 0.38), Vector3(0, pl.yaw, 0))
	if pl.key == "zahrada":
		var b := s + pl.right() * -1.0
		b.y = _ground(b)
		mk.cylinder(b + Vector3(0, 0.42, 0), 0.3, 0.34, 0.84, Color(0.2, 0.35, 0.55), Vector3.ZERO, 10)
		mk.box(b + Vector3(0, 0.6, 0) + pl.fwd() * 0.3, Vector3(0.05, 0.05, 0.16), Color(0.7, 0.7, 0.72), Vector3(0, pl.yaw, 0))
		_build_well(mk, pl)
		_build_compost(mk, pl)
		if gh_built:
			_build_greenhouse_frame(mk, pl)


## Studna u zahrady (Fáze 8): kamenný prstenec s vodou, dva sloupky, sedlová stříška a vratkolo s kbelíkem.
func _build_well(mk: MeshKit, pl: Plot) -> void:
	var bp := _well_pos(pl)
	var yaw := pl.yaw
	var STONE := Color(0.55, 0.53, 0.5)
	mk.cylinder(bp + Vector3(0, 0.42, 0), 0.5, 0.56, 0.84, STONE, Vector3.ZERO, 12)
	mk.cylinder(bp + Vector3(0, 0.87, 0), 0.57, 0.53, 0.1, STONE.lightened(0.12), Vector3.ZERO, 12)      # okraj zdí
	mk.cylinder(bp + Vector3(0, 0.8, 0), 0.42, 0.42, 0.06, Color(0.05, 0.08, 0.1), Vector3.ZERO, 12)      # voda ve tmě
	for sx in [-0.52, 0.52]:
		mk.box(bp + pl.right() * sx + Vector3(0, 1.1, 0), Vector3(0.09, 1.7, 0.09), WOOD, Vector3(0, yaw, 0))
	# vratkolo mezi sloupky + klikou; provaz dolů do studny s kbelíkem
	mk.cylinder(bp + Vector3(0, 1.35, 0), 0.05, 0.05, 1.1, WOOD.darkened(0.15), Vector3(0, yaw, PI / 2), 8)
	mk.box(bp + pl.right() * 0.56 + Vector3(0, 1.28, 0) + pl.fwd() * 0.14, Vector3(0.03, 0.03, 0.3), STEEL, Vector3(0, yaw, 0))
	mk.cylinder(bp + Vector3(0, 1.05, 0), 0.012, 0.012, 0.55, Color(0.55, 0.45, 0.3), Vector3.ZERO, 6)
	mk.box(bp + Vector3(0, 0.75, 0), Vector3(0.16, 0.14, 0.16), Color(0.4, 0.42, 0.45), Vector3(0, yaw, 0))
	# sedlová stříška (dvě nakloněné krytiny po stranách hřebene podél fwd)
	for sz in [1.0, -1.0]:
		mk.box(bp + pl.fwd() * (0.34 * sz) + Vector3(0, 1.92, 0), Vector3(1.5, 0.05, 0.85),
			Color(0.5, 0.22, 0.12), Vector3(0.55 * sz, yaw, 0))


## Kompost u zahrady (Fáze 8): otevřená dřevěná bedna s hromadou, jejíž výška kopíruje zásobu `compost_left`.
func _build_compost(mk: MeshKit, pl: Plot) -> void:
	var bp := _compost_pos(pl)
	var yaw := pl.yaw
	var bedna := Color(0.34, 0.25, 0.15)
	for i in 4:
		var y := 0.13 + float(i) * 0.17
		mk.box(bp + pl.fwd() * 0.52 + Vector3(0, y, 0), Vector3(1.16, 0.1, 0.04), bedna, Vector3(0, yaw, 0))       # zadní stěna
		for sx in [-0.56, 0.56]:
			mk.box(bp + pl.right() * sx + Vector3(0, y, 0), Vector3(0.04, 0.1, 1.04), bedna, Vector3(0, yaw, 0))  # boky
	for sx in [-0.56, 0.56]:
		for sz in [-0.5, 0.5]:
			mk.box(bp + pl.right() * sx + pl.fwd() * sz + Vector3(0, 0.38, 0), Vector3(0.07, 0.76, 0.07),
				bedna.darkened(0.15), Vector3(0, yaw, 0))
	if compost_left > 0:
		var fill := 0.3 + 0.55 * float(compost_left) / float(COMPOST_MAX)
		var hromada := Color(0.16, 0.11, 0.07)
		mk.sphere(bp + Vector3(0, fill * 0.35, 0), 0.55, hromada, Vector3(1.0, fill, 0.85), Vector3(0, yaw, 0), 9, 5)
		mk.sphere(bp + pl.right() * 0.18 + pl.fwd() * -0.12 + Vector3(0, fill * 0.5, 0), 0.3,
			hromada.lightened(0.18), Vector3(1.2, fill, 1.0), Vector3(0, yaw, 0), 7, 4)
		# suchá sláma / listí na hromadě
		for i in mini(3, compost_left):
			mk.box(bp + pl.right() * (0.2 * float(i) - 0.2) + pl.fwd() * (0.15 - 0.1 * float(i)) + Vector3(0, fill * 0.62, 0),
				Vector3(0.16, 0.02, 0.1), Color(0.5, 0.42, 0.2), Vector3(0, yaw + float(i), 0))


## Kostra skleníku (Fáze 8): lakované kovové sloupky, rámy a hřeben nad záhony `_gh_rect`.
func _build_greenhouse_frame(mk: MeshKit, pl: Plot) -> void:
	var r := _gh_lrect(pl)
	var FRAME := Color(0.3, 0.45, 0.32)
	var x0 := r.position.x
	var z0 := r.position.y
	var x1 := x0 + r.size.x
	var z1 := z0 + r.size.y
	var zm := (z0 + z1) * 0.5
	var inset := 0.06
	x0 += inset
	x1 -= inset
	z0 += inset
	z1 -= inset
	for cv in [Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)]:
		var bp := _lifted(pl, cv.x, cv.y, 0.0)
		mk.box(bp + Vector3(0, GH_WALL_H * 0.5, 0), Vector3(0.07, GH_WALL_H, 0.07), FRAME, Vector3(0, pl.yaw, 0))
	# rámy u země a pod okapem (4 strany)
	for y in [0.08, GH_WALL_H]:
		for e in [[Vector2(x0, z0), Vector2(x1, z0)], [Vector2(x1, z1), Vector2(x0, z1)],
				[Vector2(x0, z1), Vector2(x0, z0)], [Vector2(x1, z0), Vector2(x1, z1)]]:
			var a: Vector2 = e[0]
			var b2: Vector2 = e[1]
			var pa := _lifted(pl, a.x, a.y, y)
			var pb := _lifted(pl, b2.x, b2.y, y)
			var d := pb - pa
			mk.box((pa + pb) * 0.5, Vector3(0.05, 0.06, d.length()), FRAME,
				Vector3(-asin(clampf(d.y / maxf(d.length(), 0.01), -1.0, 1.0)), atan2(d.x, d.z), 0.0))
	# hřeben střechy + krokve na stranách štítů
	var ra := _lifted(pl, x0, zm, GH_RIDGE_H)
	var rb := _lifted(pl, x1, zm, GH_RIDGE_H)
	var dr := rb - ra
	mk.box((ra + rb) * 0.5, Vector3(0.06, 0.06, dr.length()), FRAME, Vector3(0.0, atan2(dr.x, dr.z), 0.0))
	for x in [x0, x1]:
		for z in [z0, z1]:
			var pa2 := _lifted(pl, x, z, GH_WALL_H)
			var pb2 := _lifted(pl, x, zm, GH_RIDGE_H)
			var d2 := pb2 - pa2
			mk.box((pa2 + pb2) * 0.5, Vector3(0.04, 0.04, d2.length()), FRAME,
				Vector3(-asin(clampf(d2.y / maxf(d2.length(), 0.01), -1.0, 1.0)), atan2(d2.x, d2.z), 0.0))


## Sklo skleníku do vlastního MeshKitu → druhý povrch meshe záhonů s průhledným materiálem.
## Stěny do výšky okapu, štítové trojúhelníky a dvě sedlové střešní roviny; ve přední stěně (k domu) vchod.
func _build_greenhouse_glass(gk: MeshKit, pl: Plot) -> void:
	var r := _gh_lrect(pl)
	var GLASS := Color(1, 1, 1)
	var x0 := r.position.x + 0.06
	var z0 := r.position.y + 0.06
	var x1 := r.position.x + r.size.x - 0.06
	var z1 := r.position.y + r.size.y - 0.06
	var zm := (z0 + z1) * 0.5
	var xm := (x0 + x1) * 0.5
	var dw := 0.48                            # polovina šířky vchodu
	# přední stěna (−z, k domu) se vstupem 0,96 m: boční panely + překlad nad dveřmi
	gk.quad(_lifted(pl, x0, z0, 0.0), _lifted(pl, xm - dw, z0, 0.0), _lifted(pl, xm - dw, z0, GH_WALL_H),
		_lifted(pl, x0, z0, GH_WALL_H), GLASS)
	gk.quad(_lifted(pl, xm + dw, z0, 0.0), _lifted(pl, x1, z0, 0.0), _lifted(pl, x1, z0, GH_WALL_H),
		_lifted(pl, xm + dw, z0, GH_WALL_H), GLASS)
	gk.quad(_lifted(pl, xm - dw, z0, GH_WALL_H - 0.35), _lifted(pl, xm + dw, z0, GH_WALL_H - 0.35),
		_lifted(pl, xm + dw, z0, GH_WALL_H), _lifted(pl, xm - dw, z0, GH_WALL_H), GLASS)
	# zadní a boční stěny
	gk.quad(_lifted(pl, x0, z1, 0.0), _lifted(pl, x1, z1, 0.0), _lifted(pl, x1, z1, GH_WALL_H),
		_lifted(pl, x0, z1, GH_WALL_H), GLASS)
	gk.quad(_lifted(pl, x0, z0, 0.0), _lifted(pl, x0, z1, 0.0), _lifted(pl, x0, z1, GH_WALL_H),
		_lifted(pl, x0, z0, GH_WALL_H), GLASS)
	gk.quad(_lifted(pl, x1, z1, 0.0), _lifted(pl, x1, z0, 0.0), _lifted(pl, x1, z0, GH_WALL_H),
		_lifted(pl, x1, z1, GH_WALL_H), GLASS)
	# štíty (trojúhelníky na stranách x0/x1)
	gk.tri(_lifted(pl, x0, z0, GH_WALL_H), _lifted(pl, x0, z1, GH_WALL_H), _lifted(pl, x0, zm, GH_RIDGE_H), GLASS)
	gk.tri(_lifted(pl, x1, z1, GH_WALL_H), _lifted(pl, x1, z0, GH_WALL_H), _lifted(pl, x1, zm, GH_RIDGE_H), GLASS)
	# sedlová střecha (dvě roviny k hřebeni)
	gk.quad(_lifted(pl, x0, z0, GH_WALL_H), _lifted(pl, x1, z0, GH_WALL_H), _lifted(pl, x1, zm, GH_RIDGE_H),
		_lifted(pl, x0, zm, GH_RIDGE_H), GLASS)
	gk.quad(_lifted(pl, x1, z1, GH_WALL_H), _lifted(pl, x0, z1, GH_WALL_H), _lifted(pl, x0, zm, GH_RIDGE_H),
		_lifted(pl, x1, zm, GH_RIDGE_H), GLASS)


func _build_cell(mk: MeshKit, pl: Plot, k: Vector2i, cell: Dictionary) -> void:
	var lx := float(k.x) + 0.5 - float(pl.w) * 0.5
	var lz := float(k.y) + 0.5 - float(pl.d) * 0.5
	var hs := 0.46
	var moist := float(cell.get("m", 0.0)) > 0.0
	var soil := SOIL_WET if moist else SOIL_DRY
	_flat(mk, _lifted(pl, lx - hs, lz - hs, 0.05), _lifted(pl, lx + hs, lz - hs, 0.05),
		_lifted(pl, lx + hs, lz + hs, 0.05), _lifted(pl, lx - hs, lz + hs, 0.05), soil)
	var cp := pl.local_pos(lx, lz)
	cp.y = _ground(cp)
	for off in [-0.22, 0.22]:
		mk.box(cp + pl.fwd() * float(off) + Vector3(0, 0.07, 0), Vector3(0.84, 0.07, 0.2), RIDGE if not moist else RIDGE.darkened(0.25),
			Vector3(0, pl.yaw, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(k.x, k.y, int(pl.center.x)))
	if int(cell["s"]) >= S_ZASETO:
		_build_plant(mk, pl, cp, cell, rng)
	# plevel: hustota ~ w (výška ~0,1–0,22 m); od w > 0,5 je záhon viditelně zaplevelený (vyšší, světlejší trsy)
	var weeds := float(cell.get("w", 0.0))
	var heavy := weeds > 0.5
	for i in int(weeds * (10.0 if heavy else 7.0)):
		var wp := cp + pl.right() * rng.randf_range(-0.4, 0.4) + pl.fwd() * rng.randf_range(-0.4, 0.4)
		_blade(mk, wp + Vector3(0, 0.06, 0), rng.randf() * TAU, rng.randf_range(0.1, 0.3 if heavy else 0.22), 0.05, 0.05,
			WEED.lightened(0.15) if heavy else WEED)


## Stéblo / list jako trojúhelník ze základny `p` (`ang` = směr sklonu, `h` výška, `wid` šířka, `lean` vychýlení špičky).
func _blade(mk: MeshKit, p: Vector3, ang: float, h: float, wid: float, lean: float, col: Color) -> void:
	var dir := Vector3(cos(ang), 0.0, sin(ang))
	var side := Vector3(-dir.z, 0.0, dir.x) * wid * 0.5
	var tip := p + Vector3(0, h, 0) + dir * lean
	mk.tri(p - side, p + side, tip, col)
	mk.tri(p + side, p - side, tip, col.darkened(0.15))


func _build_plant(mk: MeshKit, pl: Plot, cp: Vector3, cell: Dictionary, rng: RandomNumberGenerator) -> void:
	var crop: String = cell["c"]
	var spec: Dictionary = CROPS[crop]
	var ripe := int(cell["s"]) == S_ZRALE
	var f := 1.0 if ripe else clampf(float(cell.get("g", 0.0)) / float(spec["days"]), 0.0, 1.0)
	var wilt := clampf(float(int(cell.get("dry", 0)) - int(spec["water_need"])) / 2.0, 0.0, 1.0) if not ripe else 0.0
	var col: Color = (spec["ripe"] if ripe else spec["leaf"]) as Color
	col = col.lerp(WILTED, wilt)
	var full_h := float(spec["h"])
	var h := lerpf(0.05, full_h, smoothstep(0.0, 1.0, f)) * (1.0 - 0.4 * wilt)
	var nb := 3 + int(f * 7.0)
	var wid := float(spec["wid"]) * lerpf(0.5, 1.0, f)
	var lean := float(spec["lean"]) * lerpf(0.5, 1.0, f) * (1.0 + wilt)
	var base := cp + Vector3(0, 0.08, 0)
	if crop == "rajcata" and f > 0.25:
		mk.box(base + Vector3(0, 0.45, 0), Vector3(0.035, 0.9, 0.035), WOOD)
	for i in nb:
		var ang := TAU * float(i) / float(nb) + rng.randf() * 0.5
		var off := Vector3(cos(ang), 0, sin(ang)) * rng.randf_range(0.0, 0.16)
		_blade(mk, base + off, ang, h * rng.randf_range(0.7, 1.0), wid, lean * rng.randf_range(0.6, 1.2), col)
	if not ripe:
		return
	match crop:
		"rajcata":
			for i in 5:
				mk.sphere(base + Vector3(rng.randf_range(-0.15, 0.15), rng.randf_range(0.25, 0.7), rng.randf_range(-0.15, 0.15)),
					0.055, Color(0.85, 0.12, 0.08), Vector3.ONE, Vector3.ZERO, 7, 4)
		"dyne":
			mk.sphere(base + Vector3(0.1, 0.12, 0.05), 0.17, Color(0.92, 0.5, 0.1), Vector3(1, 0.8, 1), Vector3.ZERO, 9, 5)
		"mrkev":
			for i in 4:
				mk.cylinder(base + Vector3(rng.randf_range(-0.25, 0.25), 0.0, rng.randf_range(-0.25, 0.25)), 0.03, 0.04, 0.03,
					Color(0.92, 0.5, 0.1), Vector3.ZERO, 5)
		"cibule":
			for i in 3:
				mk.sphere(base + Vector3(rng.randf_range(-0.2, 0.2), 0.0, rng.randf_range(-0.2, 0.2)), 0.05,
					Color(0.85, 0.7, 0.4), Vector3(1, 0.8, 1), Vector3.ZERO, 6, 4)
		"brambory":
			for i in 3:
				mk.sphere(base + Vector3(rng.randf_range(-0.2, 0.2), 0.32, rng.randf_range(-0.2, 0.2)), 0.03,
					Color(0.95, 0.95, 0.9), Vector3.ONE, Vector3.ZERO, 5, 3)


# ------------------------------------------------------------------ ukládání

func to_dict() -> Dictionary:
	var ps := []
	for pl in plots:
		var q: Plot = pl
		var cs := []
		for k in q.cells:
			var c: Dictionary = q.cells[k]
			cs.append({"i": k.x, "j": k.y, "s": int(c["s"]), "c": String(c.get("c", "")), "g": snappedf(float(c.get("g", 0.0)), 0.01),
				"dry": int(c.get("dry", 0)), "m": snappedf(float(c.get("m", 0.0)), 0.1), "w": snappedf(float(c.get("w", 0.0)), 0.01),
				"h": snappedf(float(c.get("h", 1.0)), 0.01), "o": int(c.get("o", 0)), "f": snappedf(float(c.get("f", 0.0)), 0.01)})
		ps.append({"key": q.key, "cx": snappedf(q.center.x, 0.01), "cz": snappedf(q.center.z, 0.01), "yaw": snappedf(q.yaw, 0.001),
			"w": q.w, "d": q.d, "cells": cs})
	var picks := {}
	for id in sow_pick:
		picks[str(id)] = sow_pick[id]
	var cans := {}
	for id in can_left:
		cans[str(id)] = int(can_left[id])
	return {"plots": ps, "rent_until": rent_until, "sow_pick": picks, "can_left": cans}


## Starý save bez klíče `garden` = prázdná zahrada, žádné pole.
func restore(d: Dictionary) -> void:
	for pl in plots.duplicate():
		if (pl as Plot).key == "pole":
			_remove_plot(pl)
		else:
			(pl as Plot).cells.clear()
			(pl as Plot).dirty = true
	rent_until = int(d.get("rent_until", -1))
	sow_pick.clear()
	for k in d.get("sow_pick", {}):
		sow_pick[int(k)] = String(d["sow_pick"][k])
	can_left.clear()
	for k in d.get("can_left", {}):
		can_left[int(k)] = int(d["can_left"][k])
	for e in d.get("plots", []):
		var key := String(e.get("key", ""))
		var pl: Plot = plot_by_key(key)
		if pl == null:
			if key != "pole" or rent_until < 0:
				continue
			pl = _add_plot("pole", "Pronajaté pole", Vector3(float(e.get("cx", 0.0)), 0.0, float(e.get("cz", 0.0))),
				float(e.get("yaw", 0.0)), int(e.get("w", FIELD_SIZE.x)), int(e.get("d", FIELD_SIZE.y)))
			pl.center.y = _ground(pl.center)
		for ce in e.get("cells", []):
			var k := Vector2i(int(ce.get("i", 0)), int(ce.get("j", 0)))
			if k.x < 0 or k.y < 0 or k.x >= pl.w or k.y >= pl.d:
				continue
			var st := int(ce.get("s", S_ZRYTO))
			var crop := String(ce.get("c", ""))
			if st >= S_ZASETO and not CROPS.has(crop):
				st = S_ZRYTO
			pl.cells[k] = {"s": st, "c": crop, "g": float(ce.get("g", 0.0)), "dry": int(ce.get("dry", 0)), "m": float(ce.get("m", 0.0)),
				"w": float(ce.get("w", 0.0)), "h": float(ce.get("h", 1.0)), "o": int(ce.get("o", 0)), "f": float(ce.get("f", 0.0))}
		pl.dirty = true
	_last_jd = -1
	_rained_today = false


## Stav výbavy zahrady (Fáze 8) – ukládá se separovaně pod klíčem `garden_visuals` v `SaveGame`:
## zásoba kompostu a jestli stojí skleník (buňky skleníku se počítají z `_gh_rect`, neukládají se).
func visuals_to_dict() -> Dictionary:
	return {"compost": compost_left, "gh": gh_built}


## Starý save bez klíče `garden_visuals` = plný kompost a postavený skleník (výchozí stav).
func visuals_restore(d: Dictionary) -> void:
	compost_left = clampi(int(d.get("compost", COMPOST_MAX)), 0, COMPOST_MAX)
	gh_built = bool(d.get("gh", true))
	var pl := plot_by_key("zahrada")
	if pl != null:
		pl.dirty = true            # přestaví se skleník i hromada kompostu podle načteného stavu
