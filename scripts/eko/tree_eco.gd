## Dřeviny a porosty (M8.3, `World.tree_eco`): druh, věk, vitalita, výška, výčetní tloušťka a porost každého
## stromu z `data/trees.bin` (index = pořadí v souboru, stejný jako `TreeManager`) + katalog `data/dreviny.json`.
## Podle čeho (00_PRINCIPY kap. 8 „Dřeviny“): Ellenbergovy indikační hodnoty × stanoviště (`Site`, M8.2),
## růst Chapman–Richards h(t) = H·(1−e^(−k·t))^p, alometrie Näslund h = 1,3 + d²/(a + b·d)², objem kmene
## π/4·d²·h·f (tvarové číslo). Přiřazení se počítá offline (`tools/tree_species.py` → `data/tree_eco.bin`),
## za běhu se jen čte – žádná simulace, žádný `_process`.
##
## **Fallback bez `tree_eco.bin`** (00_PRINCIPY kap. 3): druh z prototypu stromu (`FALLBACK_PROTO`), věk z výšky
## inverzí Chapman–Richards s vitalitou `FALLBACK_VIGOR`, zápoj a mapové vrstvy se dopočítají z polohy stromů.
## Zasazené stromy (M2.5, čísla od `TreeManager.DYN_BASE`) jdou stejnými dotazy – druh přes `PlantedTrees.ECO_IDS`.
##
## Navazující kroky čtou jen přes `World.tree_eco` s kontrolou `!= null`: M8.7 (`canopy_at` – intercepce),
## M8.8 (tvar podle druhu), M8.11 (fenologie – klíče `fenologie` v katalogu), M8.14, M8.15 (`species_near`).
class_name TreeEco
extends RefCounted

const PATH := "res://data/tree_eco.bin"
const CATALOG := "res://data/dreviny.json"
const REC := 12                         # velikost záznamu (shoda s tools/tree_species.py)
const NO_STAND := 0xFFFF
const FL_LES := 1
const FL_SOLITER := 2
const FL_ALEJ := 4
const FL_SAD := 8
const FL_OBEC := 16
const FL_OKRAJ := 32
const FL_LUH := 64

## Fallback bez dat: prototyp 0–5 → druh (0–2 listnáč, 3–5 jehličnan; stejně jako `PlantedTrees.SPECIES.protos`).
const FALLBACK_PROTO := ["buk", "dub_zimni", "lipa", "smrk", "borovice", "smrk"]
const FALLBACK_VIGOR := 0.7
const FALLBACK_CELL := 32.0             # m – mřížka dopočítaných vrstev bez dat
## Normalizace stanoviště pro vitalitu sazenic (shoda s tools/tree_species.py – mediány nad stromy mapy).
const TWI_MED := 6.5
const INSY_MED := 5233.0
const INSY_STD := 623.0
const ELEV_ABS0 := 330.0                # m n. m. počátku světa (odhad – ověřit; ELEV v site.bin je relativní)
const T_REF := 6.0
const T_REF_ELEV := 330.0
const T_LAPSE := 6.5                    # K/km
const SAPLING_CLOSURE := 0.2            # sazenice stojí většinou na volné ploše
## Přesnost odhadu věku podle úrovně dovednosti Dřevorubectví: [od úrovně, zaokrouhlení na roky].
const AGE_STEPS := [[1, 20], [10, 10], [25, 5], [40, 1]]
const INFO_DETAIL_LVL := 10             # od této úrovně „Prohlédnout strom“ ukáže i výšku, průměr a vitalitu
const INFO_PRICE_LVL := 20              # od této úrovně i objem a cenu dřeva
## Barvy ladicí vrstvy `druhy` (podle id druhu; neuvedené šedě).
const DEBUG_COLORS := {
	"smrk": Color(0.1, 0.35, 0.15), "jedle": Color(0.05, 0.25, 0.25), "borovice": Color(0.55, 0.6, 0.2),
	"modrin": Color(0.75, 0.75, 0.3), "buk": Color(0.85, 0.45, 0.1), "dub_zimni": Color(0.6, 0.35, 0.1),
	"dub_letni": Color(0.5, 0.28, 0.08), "habr": Color(0.9, 0.75, 0.35), "lipa": Color(0.7, 0.9, 0.4),
	"javor_klen": Color(0.95, 0.6, 0.6), "jasan": Color(0.55, 0.75, 0.7), "olse": Color(0.15, 0.45, 0.85),
	"vrba_bila": Color(0.45, 0.75, 0.95), "jiva": Color(0.6, 0.8, 0.95), "briza": Color(0.95, 0.95, 0.85),
	"topol": Color(0.35, 0.6, 0.95), "akat": Color(0.9, 0.9, 0.2), "tresen_ptaci": Color(0.85, 0.2, 0.3),
	"jablon": Color(0.95, 0.15, 0.15), "hrusen": Color(0.75, 0.85, 0.2), "svestka": Color(0.5, 0.15, 0.6),
	"tresen": Color(0.8, 0.05, 0.2), "orech": Color(0.45, 0.4, 0.25),
}

var world: World
var loaded := false                     # true = data z tree_eco.bin, false = fallback z prototypů
var count := 0
var ids: Array[String] = []             # index druhu v tree_eco.bin → id
var catalog := {}                       # id → slovník z dreviny.json
var order: Array[String] = []           # pořadí druhů v katalogu
var stands := 0

var _rec := PackedByteArray()
var _sp_map := PackedInt32Array()       # index druhu v souboru → index v `order` (katalog se mohl změnit)
var _grids := {}                        # kód → {x0, z0, cell, nx, nz, data: PackedByteArray}


func setup(w: World) -> void:
	world = w
	_load_catalog()
	if not _load_data():
		_build_fallback_grids()
	world.debug_layers["druhy"] = Callable(self, "_debug_species")
	world.debug_layers["vitalita"] = Callable(self, "_debug_vigor")


func _load_catalog() -> void:
	var txt := FileAccess.get_file_as_string(CATALOG)
	var j = JSON.parse_string(txt) if txt != "" else null
	if typeof(j) != TYPE_DICTIONARY:
		push_warning("TreeEco: chybí nebo je neplatný %s – druhy jen podle prototypu" % CATALOG)
		return
	for s in (j as Dictionary).get("druhy", []):
		var d: Dictionary = s
		var id := String(d.get("id", ""))
		if id == "":
			continue
		catalog[id] = d
		order.append(id)


func _load_data() -> bool:
	if not FileAccess.file_exists(PATH):
		push_warning("TreeEco: chybí %s (python3 tools/tree_species.py) – druhy z prototypů (fallback)" % PATH)
		return false
	var b := FileAccess.get_file_as_bytes(PATH)
	if b.size() < 24 or b.slice(0, 4).get_string_from_ascii() != "TECO" or b.decode_s32(12) != REC:
		push_warning("TreeEco: neznámý formát tree_eco.bin – fallback")
		return false
	var n := b.decode_s32(8)
	var ns := b.decode_s32(16)
	var off := 20
	ids.clear()
	_sp_map.resize(ns)
	for k in ns:
		var ln := b.decode_u8(off)
		var id := b.slice(off + 1, off + 1 + ln).get_string_from_ascii()
		ids.append(id)
		_sp_map[k] = order.find(id)
		off += 1 + ln
	stands = b.decode_s32(off)
	off += 4
	if off + n * REC > b.size():
		push_warning("TreeEco: tree_eco.bin je useknutý – fallback")
		return false
	_rec = b.slice(off, off + n * REC)
	off += n * REC
	var tm: TreeManager = world.trees
	if tm != null and tm.raw_count() > 0 and tm.raw_count() != n:
		push_warning("TreeEco: tree_eco.bin má %d stromů, trees.bin %d – přegeneruj tools/tree_species.py" % [n, tm.raw_count()])
		_rec = PackedByteArray()
		return false
	if off + 4 <= b.size():
		var ng := b.decode_s32(off)
		off += 4
		for g in ng:
			if off + 24 > b.size():
				break
			var code := b.slice(off, off + 4).get_string_from_ascii()
			var gx0 := b.decode_float(off + 4)
			var gz0 := b.decode_float(off + 8)
			var gc := b.decode_float(off + 12)
			var gnx := b.decode_s32(off + 16)
			var gnz := b.decode_s32(off + 20)
			off += 24
			if off + gnx * gnz > b.size():
				break
			_grids[code] = {"x0": gx0, "z0": gz0, "cell": gc, "nx": gnx, "nz": gnz, "data": b.slice(off, off + gnx * gnz)}
			off += gnx * gnz
	count = n
	loaded = true
	return true


# ------------------------------------------------------------------ dotazy na strom

func _planted_rec(i: int) -> Dictionary:
	var tm: TreeManager = world.trees if world != null else null
	if tm == null or tm.planted == null:
		return {}
	return tm.planted.recs.get(i, {})


## Id druhu stromu (`dreviny.json`), "" když strom neexistuje.
func species(i: int) -> String:
	if i >= TreeManager.DYN_BASE:
		var r := _planted_rec(i)
		return String(PlantedTrees.ECO_IDS.get(String(r.get("sp", "")), "")) if not r.is_empty() else ""
	if loaded and i >= 0 and i < count:
		var k := _rec.decode_u8(i * REC)
		var ci := _sp_map[k] if k < _sp_map.size() else -1
		return order[ci] if ci >= 0 else (ids[k] if k < ids.size() else "")
	var tm: TreeManager = world.trees if world != null else null
	if tm == null or not tm.has_tree(i):
		return ""
	return String(FALLBACK_PROTO[clampi(tm.proto_of(i), 0, FALLBACK_PROTO.size() - 1)])


## Katalogový záznam druhu (prázdný slovník, když druh v katalogu není).
func species_info(id: String) -> Dictionary:
	return catalog.get(id, {})


## Český název druhu stromu („Buk lesní“), nebo obecný podle prototypu.
func species_name(i: int) -> String:
	var info := species_info(species(i))
	if not info.is_empty():
		return String(info.get("nazev", "Strom"))
	var tm: TreeManager = world.trees if world != null else null
	return "Jehličnan" if tm != null and tm.is_conifer(i) else "Listnáč"


func flags(i: int) -> int:
	if loaded and i >= 0 and i < count:
		return _rec.decode_u8(i * REC + 3)
	return FL_SOLITER if i >= TreeManager.DYN_BASE else 0


## Vitalita 0..1 (vhodnost stanoviště × hloubka půdy × náhoda; u sazenice ze `Site` v místě výsadby).
func vigor(i: int) -> float:
	if i >= TreeManager.DYN_BASE:
		var r := _planted_rec(i)
		var v: float = r.get("vig", -1.0)
		if v < 0.0 and not r.is_empty():      # starý save bez vitality → dopočet ze stanoviště
			v = site_vigor(species(i), r["pos"])
			r["vig"] = v
		return v if v >= 0.0 else FALLBACK_VIGOR
	if loaded and i >= 0 and i < count:
		return _rec.decode_u8(i * REC + 2) / 255.0
	return FALLBACK_VIGOR


## Výška (m) – měření z trees.bin (u zasazených z růstu).
func height(i: int) -> float:
	if loaded and i >= 0 and i < count:
		return _rec.decode_half(i * REC + 4)
	var tm: TreeManager = world.trees if world != null else null
	return tm.height_of(i) if tm != null and tm.has_tree(i) else 0.0


## Věk v letech (u porostu jeden věk ± rozptyl; bez dat inverze Chapman–Richards z výšky).
func age(i: int) -> int:
	if i >= TreeManager.DYN_BASE:
		var r := _planted_rec(i)
		return maxi(1, int((float(r.get("age", 0.0)) * PlantedTrees.GROWTH_SPEEDUP) / 365.0) + 1) if not r.is_empty() else 0
	if loaded and i >= 0 and i < count:
		return _rec.decode_u8(i * REC + 1)
	return age_from_height(species(i), height(i), FALLBACK_VIGOR)


## Výčetní tloušťka (cm, ve 1,3 m).
func dbh(i: int) -> float:
	if loaded and i >= 0 and i < count:
		return _rec.decode_half(i * REC + 6)
	return dbh_from_height(species(i), height(i), i >= TreeManager.DYN_BASE)


## Číslo porostu, −1 mimo les (solitér, alej, sad, zasazený strom).
func stand_of(i: int) -> int:
	if loaded and i >= 0 and i < count:
		var s := _rec.decode_u16(i * REC + 8)
		return -1 if s == NO_STAND else s
	return -1


## Objem kmene s kůrou (m³): π/4 · d² · h · tvarové číslo.
func volume_m3(i: int) -> float:
	var d := dbh(i) / 100.0
	var f := float(species_info(species(i)).get("tvarove_cislo", 0.45))
	return PI * 0.25 * d * d * height(i) * f


## Cena dřeva stromu na pni (Kč) podle druhu a objemu.
func wood_value_kc(i: int) -> int:
	return int(roundf(volume_m3(i) * wood_kc_per_m3(species(i)) / 10.0) * 10.0)


func wood_kc_per_m3(id: String) -> float:
	var dr: Dictionary = species_info(id).get("drevo", {})
	return float(dr.get("cena", Forestry.WOOD_KC_PER_M3))


func is_fruit(i: int) -> bool:
	return String(species_info(species(i)).get("typ", "")) == "ovocny"


## Ovoce druhu: {"predmet": id předmětu, "barva": Color} nebo {}.
func fruit_of(id: String) -> Dictionary:
	var o: Dictionary = species_info(id).get("ovoce", {})
	if o.is_empty():
		return {}
	return {"predmet": String(o.get("predmet", "")), "barva": Color.html(String(o.get("barva", "#c02020")))}


# ------------------------------------------------------------------ modely (Chapman–Richards, Näslund, Ellenberg)

func _growth(id: String) -> Dictionary:
	return species_info(id).get("rust", {"H_max": 25.0, "k": 0.03, "p": 1.3, "doziti": 150})


## Věk z výšky – inverze h(t) = H·(1−e^(−k·t))^p se stanovištním H = H_max·(0,6 + 0,4·vitalita).
func age_from_height(id: String, h: float, vig: float) -> int:
	var g := _growth(id)
	var hs := float(g.get("H_max", 25.0)) * (0.6 + 0.4 * vig)
	var ratio := clampf(h / maxf(hs, 0.1), 0.02, 0.97)
	var p := maxf(float(g.get("p", 1.3)), 0.1)
	var k := maxf(float(g.get("k", 0.03)), 0.001)
	var t := -log(1.0 - pow(ratio, 1.0 / p)) / k
	return clampi(int(roundf(minf(t, float(g.get("doziti", 300))))), 1, 255)


## Výška v daném věku (Chapman–Richards) – pro M8.11 růst.
func height_at_age(id: String, years: float, vig: float) -> float:
	var g := _growth(id)
	var hs := float(g.get("H_max", 25.0)) * (0.6 + 0.4 * vig)
	return hs * pow(1.0 - exp(-float(g.get("k", 0.03)) * years), float(g.get("p", 1.3)))


## dbh (cm) z výšky – Näslund h = 1,3 + d²/(a + b·d)² → d = a·s / (1 − b·s), s = √(h − 1,3); solitér ×1,3.
func dbh_from_height(id: String, h: float, solitary := false) -> float:
	var nl: Array = species_info(id).get("naslund", [2.0, 0.16])
	var a := float(nl[0]) if nl.size() > 0 else 2.0
	var b := float(nl[1]) if nl.size() > 1 else 0.16
	var s := sqrt(maxf(h - 1.3, 0.05))
	var d := a * s / maxf(1.0 - b * s, 0.08)
	return clampf(d * (1.3 if solitary else 1.0), 1.0, 180.0)


## Vhodnost stanoviště 0..1 pro druh v bodě (Ellenberg × `Site`; stejné vzorce jako tools/tree_species.py).
## `closure` = zápoj 0..1 (sazenice na volné ploše ~0,2). Bez `Site` dat vrací střední hodnotu.
func site_suitability(id: String, pos: Vector3, closure := SAPLING_CLOSURE) -> float:
	var info := species_info(id)
	var st: Site = world.site if world != null else null
	if info.is_empty() or st == null or not st.loaded:
		return FALLBACK_VIGOR
	var e: Dictionary = info.get("ellenberg", {})
	var t: Dictionary = info.get("tolerance", {})
	var x := pos.x
	var z := pos.z
	var insy_z := (st.insol(x, z) - INSY_MED) / INSY_STD
	var ph := st.ph(x, z)
	if ph > 14.0:      # site.bin v1 ukládá pH × 10 (M8.2)
		ph /= 10.0
	var f := 5.0 + 0.55 * (st.twi(x, z) - TWI_MED) + (st.awc(x, z) - 120.0) / 80.0 - 0.6 * insy_z
	if st.hand(x, z) < 2.5 and st.dist_water(x, z) < 35.0:
		f += 2.5
	if st.soil(x, z) == Site.SOIL_GLEJ:
		f += 1.5
	f = clampf(f, 1.0, 9.0)
	var l := 7.0 - 2.0 * closure
	var r := clampf((ph - 3.5) * 2.2, 1.0, 9.0)
	var n := clampf(2.0 + 7.0 * st.nutr(x, z), 1.0, 9.0)
	var tt := clampf(T_REF - (st.elev(x, z) + ELEV_ABS0 - T_REF_ELEV) * T_LAPSE / 1000.0 * 1.6 + 1.1 * insy_z
		- 1.5 * st.cold_pool(x, z), 1.0, 9.0)
	var df := f - float(e.get("F", 5))
	var sf := 1.2 + 2.8 * float(t.get("zamokreni" if df > 0.0 else "sucho", 0.3))
	var dl := l - float(e.get("L", 5))
	var sl := (1.6 + 3.0 * float(t.get("stin", 0.3))) if dl < 0.0 else 3.5
	var dt := tt - float(e.get("T", 5))
	var sdt := (1.2 + 2.0 * float(t.get("mraz", 0.5))) if dt < 0.0 else (2.0 + 1.5 * float(t.get("sucho", 0.3)))
	var q := pow(df / sf, 2) + pow(dl / sl, 2) + pow(dt / sdt, 2) + pow((r - float(e.get("R", 6))) / 2.2, 2) \
		+ pow((n - float(e.get("N", 5))) / 2.4, 2)
	return exp(-0.5 * q)


## Vitalita sazenice v místě výsadby: √vhodnost × hloubka půdy (bez náhody – hráč vidí příčinu).
func site_vigor(id: String, pos: Vector3) -> float:
	var st: Site = world.site if world != null else null
	var depth := clampf(st.soil_depth(pos.x, pos.z) / 60.0, 0.5, 1.0) if st != null and st.loaded else 1.0
	return clampf(sqrt(site_suitability(id, pos)) * depth, 0.05, 1.0)


# ------------------------------------------------------------------ prostorové dotazy

func _grid_u8(code: String, x: float, z: float) -> int:
	var g: Dictionary = _grids.get(code, {})
	if g.is_empty():
		return -1
	var ix := int(floor((x - float(g["x0"])) / float(g["cell"])))
	var iz := int(floor((z - float(g["z0"])) / float(g["cell"])))
	if ix < 0 or iz < 0 or ix >= int(g["nx"]) or iz >= int(g["nz"]):
		return -1
	return (g["data"] as PackedByteArray)[iz * int(g["nx"]) + ix]


## Zápoj korun 0..1 v bodě (mřížka 16 m, s daty bilineárně) – pro M8.7 intercepci, M8.9 mikroklima, M8.14 podrost.
func canopy_at(x: float, z: float) -> float:
	var g: Dictionary = _grids.get("CANO", {})
	if g.is_empty():
		return 0.0
	var c := float(g["cell"])
	var fx := clampf((x - float(g["x0"])) / c - 0.5, 0.0, int(g["nx"]) - 1.001)
	var fz := clampf((z - float(g["z0"])) / c - 0.5, 0.0, int(g["nz"]) - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var nx := int(g["nx"])
	var d: PackedByteArray = g["data"]
	var tx := fx - ix
	var tz := fz - iz
	var v := lerpf(lerpf(d[iz * nx + ix], d[iz * nx + ix + 1], tx), lerpf(d[(iz + 1) * nx + ix], d[(iz + 1) * nx + ix + 1], tx), tz)
	return v / 255.0


## Podíly druhů stojících stromů v okruhu `r` m: {id: podíl 0..1} (součet 1; prázdné bez stromů).
func species_near(pos: Vector3, r: float) -> Dictionary:
	var out := {}
	var tm: TreeManager = world.trees if world != null else null
	if tm == null:
		return out
	var n := 0
	for i in tm.ids_near(pos, r):
		var id := species(i)
		if id == "":
			continue
		out[id] = int(out.get(id, 0)) + 1
		n += 1
	for k in out:
		out[k] = float(out[k]) / float(n)
	return out


## Váha místa pro houby druhu `kind` ("hrib", "kremenac") 0..1 podle dřevin v okolí (tabulka `houby` v katalogu).
func mushroom_weight(pos: Vector3, kind: String, r := 25.0) -> float:
	var sh := species_near(pos, r)
	var w := 0.0
	for id in sh:
		var hb: Dictionary = species_info(id).get("houby", {})
		w += float(sh[id]) * float(hb.get(kind, 0.0))
	return clampf(w, 0.0, 1.0)


# ------------------------------------------------------------------ texty

## Popis stromu pro hráče („Buk lesní, asi 80 let.“); přesnost věku a podrobnosti podle dovednosti Dřevorubectví.
func describe(i: int, lvl: int) -> String:
	var name := species_name(i)
	var step := 20
	for s in AGE_STEPS:
		if lvl >= int(s[0]):
			step = int(s[1])
	var a := age(i)
	var shown := a
	if step > 1 and a >= step:          # mladý strom se odhadne snadno, starý jen na `step` let
		shown = maxi(step, int(roundf(float(a) / step)) * step)
	var parts := ["%s, asi %d %s" % [name, shown, _years(shown)]]
	if lvl >= INFO_DETAIL_LVL:
		parts.append("výška %.0f m, průměr kmene %.0f cm" % [height(i), dbh(i)])
		var v := vigor(i)
		parts.append("vitalita " + ("výborná" if v > 0.8 else "dobrá" if v > 0.6 else "slabší" if v > 0.35 else "špatná"))
	if lvl >= INFO_PRICE_LVL:
		parts.append("dřevo ~%.2f m³ za ~%d Kč" % [volume_m3(i), wood_value_kc(i)])
	var f := flags(i)
	if f & FL_ALEJ:
		parts.append("strom v aleji")
	elif f & FL_LUH:
		parts.append("lužní stanoviště")
	return ", ".join(parts) + "."


static func _years(n: int) -> String:
	if n == 1:
		return "rok"
	if n >= 2 and n <= 4:
		return "roky"
	return "let"


# ------------------------------------------------------------------ ladicí vrstvy (F2 → Příroda – ladění)

func _debug_species(x: float, z: float) -> Color:
	var k := _grid_u8("DOMI", x, z)
	if k < 0 or k == 255:
		return Color(0.0, 0.0, 0.0, 0.0)
	var id := ""
	if loaded:
		var ci := _sp_map[k] if k < _sp_map.size() else -1
		id = order[ci] if ci >= 0 else ""
	elif k < order.size():
		id = order[k]
	var c: Color = DEBUG_COLORS.get(id, Color(0.6, 0.6, 0.6))
	c.a = 0.75
	return c


func _debug_vigor(x: float, z: float) -> Color:
	var v := _grid_u8("VIGO", x, z)
	if v <= 0:
		return Color(0.0, 0.0, 0.0, 0.0)
	var t := v / 255.0
	return Color(1.0 - t, 0.25 + 0.65 * t, 0.15, 0.7)


## Legenda vrstvy `druhy` (pro nápovědu / deník): [[název, Color], …] jen pro druhy z katalogu.
func debug_legend() -> Array:
	var out := []
	for id in order:
		out.append([String(catalog[id].get("nazev", id)), DEBUG_COLORS.get(id, Color(0.6, 0.6, 0.6))])
	return out


## Bez tree_eco.bin: zápoj (16 m), dominantní druh a vitalita (32 m) z poloh stromů v `TreeManager`.
func _build_fallback_grids() -> void:
	var tm: TreeManager = world.trees if world != null else null
	var st: Site = world.site if world != null else null
	if tm == null or tm.raw_count() == 0:
		return
	var x0 := st.x0 if st != null and st.loaded else -6150.0
	var z0 := st.z0 if st != null and st.loaded else -3950.0
	var ext_x := (st.nx * st.cell) if st != null and st.loaded else 11400.0
	var ext_z := (st.nz * st.cell) if st != null and st.loaded else 7600.0
	var cano_c := FALLBACK_CELL * 0.5
	var cnx := int(ceil(ext_x / cano_c))
	var cnz := int(ceil(ext_z / cano_c))
	var dnx := int(ceil(ext_x / FALLBACK_CELL))
	var dnz := int(ceil(ext_z / FALLBACK_CELL))
	var area := PackedFloat32Array()
	area.resize(cnx * cnz)
	var votes := {}                       # buňka → {index druhu: počet}
	for i in tm.raw_count():
		if not tm.has_tree(i):
			continue
		var p := tm.pos_of(i)
		var h := tm.height_of(i)
		var cx := clampi(int((p.x - x0) / cano_c), 0, cnx - 1)
		var cz := clampi(int((p.z - z0) / cano_c), 0, cnz - 1)
		var cr := clampf(0.3 * h, 1.5, 4.5)
		area[cz * cnx + cx] += PI * cr * cr * 1.6
		var dk := clampi(int((p.z - z0) / FALLBACK_CELL), 0, dnz - 1) * dnx + clampi(int((p.x - x0) / FALLBACK_CELL), 0, dnx - 1)
		var si := order.find(species(i))
		if si < 0:
			continue
		if not votes.has(dk):
			votes[dk] = {}
		var vd: Dictionary = votes[dk]
		vd[si] = int(vd.get(si, 0)) + 1
	var cano := PackedByteArray()
	cano.resize(cnx * cnz)
	for k in area.size():
		cano[k] = int(clampf(area[k] / (cano_c * cano_c), 0.0, 1.0) * 255.0)
	var domi := PackedByteArray()
	domi.resize(dnx * dnz)
	domi.fill(255)
	var vigo := PackedByteArray()
	vigo.resize(dnx * dnz)
	for dk in votes:
		var best := -1
		var bn := 0
		for si in votes[dk]:
			if int(votes[dk][si]) > bn:
				bn = int(votes[dk][si])
				best = int(si)
		domi[dk] = best
		vigo[dk] = int(FALLBACK_VIGOR * 255.0)
	_grids["CANO"] = {"x0": x0, "z0": z0, "cell": cano_c, "nx": cnx, "nz": cnz, "data": cano}
	_grids["DOMI"] = {"x0": x0, "z0": z0, "cell": FALLBACK_CELL, "nx": dnx, "nz": dnz, "data": domi}
	_grids["VIGO"] = {"x0": x0, "z0": z0, "cell": FALLBACK_CELL, "nx": dnx, "nz": dnz, "data": vigo}
