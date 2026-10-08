## Mapa stanovišť (M8.2, `World.site`): terén (výška, sklon, orientace), vlhkost (TWI, vzdálenost
## k vodě, HAND), poloha v reliéfu (TPI, expozice větru, mrazová kotlina), oslunění a půda.
## Toto je *stanoviště*, ne vzhled – navazující kroky M8 (dřeviny 8.3, půdní voda 8.7, mikroklima 8.9,
## fenologie/plodiny/habitat 8.11–8.15) z něj odvozují, co kde roste a žije (00_PRINCIPY kap. 3).
##
## Čte `data/site.bin` (`tools/site.py`), mřížka `cell` = 4 m, self-popisný formát (viz hlavička
## nástroje) – nové vrstvy lze přidat beze změny této třídy. Bilineární interpolace u spojitých
## vrstev; `soil` je kategorie → nejbližší sousední buňka (žádné „mezitřídy").
##
## **Fallback bez souboru** (00_PRINCIPY kap. 3 – krok, co API zavádí, ho dá i bez dat): `elev`/
## `slope`/`aspect` se dopočítají z `Terrain.height_at` (konečné diference), zbytek vrátí rozumné
## střední hodnoty – svět běží dál, jen „plochý" (žádné TWI/půdní rozlišení).
class_name Site
extends RefCounted

const PATH := "res://data/site.bin"
const HEADER := 32
const LAYER_HDR := 16

## Půdní třídy (shoda s `tools/site.py` SOIL_RULES – BPEJ geometrie pro katastr není k dispozici,
## docs/BPEJ.md; fallback z terénu + landuse podle české taxonomie).
const SOIL_HNEDOZEM := 0
const SOIL_RANKER := 1
const SOIL_ARENOSOL := 2
const SOIL_GLEJ := 3
const SOIL_FLUVIZEM := 4
const SOIL_ANTROPOZEM := 5
const SOIL_NAMES := ["hnědozem / kambizem", "ranker / litozem", "arenosol", "pseudoglej / glej",
	"fluvizem", "antropozem"]
## Orientační vlastnosti třídy (únosnost 0..1 pro M8.13 terramechaniku, propustnost 0..1 pro M8.7
## půdní vodu – vyšší = rychlejší odtok/méně drží vodu) – zjednodušeně, bez BPEJ čísel.
const SOIL_PROPS := {
	SOIL_HNEDOZEM: {"bearing": 0.65, "perm": 0.45},
	SOIL_RANKER: {"bearing": 0.8, "perm": 0.6},
	SOIL_ARENOSOL: {"bearing": 0.55, "perm": 0.8},
	SOIL_GLEJ: {"bearing": 0.3, "perm": 0.2},
	SOIL_FLUVIZEM: {"bearing": 0.45, "perm": 0.4},
	SOIL_ANTROPOZEM: {"bearing": 0.7, "perm": 0.35},
}

var loaded := false
var terrain: Terrain              # fallback bez site.bin
var x0 := 0.0
var z0 := 0.0
var cell := 4.0
var nx := 0
var nz := 0
var _layers := {}                 # kód (String, 4 znaky) → {dtype:int, scale:float, offset:float, data:PackedByteArray}


func setup(t: Terrain) -> void:
	terrain = t
	load_data()


## Načte `data/site.bin`. Vrací false (fallback), když soubor chybí nebo je neplatný.
func load_data() -> bool:
	if not FileAccess.file_exists(PATH):
		push_warning("Site: chybí %s (tools/site.py) – stanoviště se dopočítá z terénu (fallback)" % PATH)
		return false
	var b := FileAccess.get_file_as_bytes(PATH)
	if b.size() < HEADER or b.slice(0, 4).get_string_from_ascii() != "SITE":
		push_warning("Site: neznámý formát site.bin")
		return false
	x0 = b.decode_float(8)
	z0 = b.decode_float(12)
	cell = b.decode_float(16)
	nx = b.decode_s32(20)
	nz = b.decode_s32(24)
	var nlayers := b.decode_s32(28)
	if nx <= 0 or nz <= 0 or nlayers <= 0:
		push_warning("Site: site.bin má neplatnou mřížku")
		return false
	var off := HEADER
	var cell_count := nx * nz
	var entries := []
	for i in nlayers:
		if off + LAYER_HDR > b.size():
			push_warning("Site: site.bin je useknutý (hlavička vrstev)")
			return false
		var code := b.slice(off, off + 4).get_string_from_ascii()
		var dtype := b.decode_u8(off + 4)
		var scale := b.decode_float(off + 8)
		var offset := b.decode_float(off + 12)
		entries.append([code, dtype, scale, offset])
		off += LAYER_HDR
	for e in entries:
		var bytes_per := 2 if e[1] == 1 else 1
		var size := cell_count * bytes_per
		if off + size > b.size():
			push_warning("Site: site.bin je useknutý (data vrstvy %s)" % String(e[0]))
			return false
		_layers[e[0]] = {"dtype": e[1], "scale": e[2], "offset": e[3], "data": b.slice(off, off + size)}
		off += size
	loaded = true
	return true


func _ix_fx(x: float, z: float) -> Vector2:
	return Vector2(clampf((x - x0) / cell, 0.0, nx - 1.001), clampf((z - z0) / cell, 0.0, nz - 1.001))


func _raw_at(code: String, ix: int, iz: int) -> float:
	var l: Dictionary = _layers[code]
	var idx := iz * nx + ix
	var data: PackedByteArray = l["data"]
	if l["dtype"] == 1:
		return float(data.decode_u16(idx * 2))
	return float(data[idx])


## Spojitá vrstva s bilineární interpolací. `default_val` se vrátí bez dat (fallback volajícího).
func _sample(code: String, x: float, z: float, default_val: float) -> float:
	if not loaded or not _layers.has(code):
		return default_val
	var l: Dictionary = _layers[code]
	var fxz := _ix_fx(x, z)
	var ix0 := int(fxz.x)
	var iz0 := int(fxz.y)
	var ix1 := mini(ix0 + 1, nx - 1)
	var iz1 := mini(iz0 + 1, nz - 1)
	var tx := fxz.x - ix0
	var tz := fxz.y - iz0
	var v00 := _raw_at(code, ix0, iz0)
	var v10 := _raw_at(code, ix1, iz0)
	var v01 := _raw_at(code, ix0, iz1)
	var v11 := _raw_at(code, ix1, iz1)
	var raw := lerpf(lerpf(v00, v10, tx), lerpf(v01, v11, tx), tz)
	return float(l["offset"]) + raw * float(l["scale"])


## Kategorická vrstva – nejbližší buňka, žádná interpolace mezi třídami.
func _sample_nearest(code: String, x: float, z: float, default_val: int) -> int:
	if not loaded or not _layers.has(code):
		return default_val
	var fxz := _ix_fx(x, z)
	return int(_raw_at(code, int(round(fxz.x)), int(round(fxz.y))))


## Terénní fallback konečnými diferencemi (bez site.bin) – jen elev/slope/aspect, zbytek je plochý.
func _fallback_slope_aspect(x: float, z: float, north_deg: float) -> Dictionary:
	if terrain == null:
		return {"elev": 300.0, "slope": 0.0, "aspect": 0.0}
	var d := 2.0
	var h0 := terrain.height_at(x, z)
	var hx := terrain.height_at(x + d, z)
	var hz := terrain.height_at(x, z + d)
	var gx := (hx - h0) / d
	var gz := (hz - h0) / d
	var slope_deg := rad_to_deg(atan(sqrt(gx * gx + gz * gz)))
	var hl := sqrt(gx * gx + gz * gz)
	var aspect_deg := 0.0
	if hl > 1.0e-6:
		var yaw := atan2(gx / hl, gz / hl)       # = atan2(-(-gx)/hl, -(-gz)/hl), spádnice dolů
		aspect_deg = fposmod(north_deg - rad_to_deg(yaw), 360.0)
	return {"elev": h0, "slope": slope_deg, "aspect": aspect_deg}


func elev(x: float, z: float) -> float:
	if loaded:
		return _sample("ELEV", x, z, 300.0)
	return _fallback_slope_aspect(x, z, 78.37)["elev"]


## Sklon (°). Bez dat: dopočet z `Terrain` konečnými diferencemi.
func slope(x: float, z: float) -> float:
	if loaded:
		return _sample("SLOP", x, z, 0.0)
	return _fallback_slope_aspect(x, z, 78.37)["slope"]


## Orientace svahu (° od severu, azimut směru spádnice po svahu dolů – stejná konvence jako
## `Clock.enu_to_world`/`north_deg`). Bez dat: dopočet z `Terrain`.
func aspect(x: float, z: float) -> float:
	if loaded:
		return _sample("ASPE", x, z, 0.0)
	return _fallback_slope_aspect(x, z, 78.37)["aspect"]


## Topografický vlhkostní index (Beven & Kirkby 1979) – vyšší = vlhčí údolnice/depresy.
func twi(x: float, z: float) -> float:
	return _sample("TWI_", x, z, 6.0)


## Vzdálenost k nejbližšímu toku/nádrži (m).
func dist_water(x: float, z: float) -> float:
	return _sample("DISW", x, z, 9999.0)


## Výška nad nejbližší vodou po (zjednodušeném) odtoku – niva má nízké HAND (m).
func hand(x: float, z: float) -> float:
	return _sample("HAND", x, z, 50.0)


## Topografická poloha (buňka − průměr okolí 500 m): záporné = údolí, kladné = hřbet (m).
func tpi(x: float, z: float) -> float:
	return _sample("TPI_", x, z, 0.0)


## Expozice větru 0..1 (z TPI a orientace vůči převládajícímu západnímu proudění).
func wind_exp(x: float, z: float) -> float:
	return _sample("WEXP", x, z, 0.5)


## Potenciální oslunění za rok (MJ/m²), clear-sky model bez zastínění terénem (Minimum M8.2).
func insol(x: float, z: float) -> float:
	return _sample("INSY", x, z, 4000.0)


## Potenciální oslunění v zimě (prosinec–únor, MJ/m²).
func insol_winter(x: float, z: float) -> float:
	return _sample("INSW", x, z, 150.0)


## Mrazová kotlina 0..1 (záporné TPI, nízké HAND, malá expozice větru).
func cold_pool(x: float, z: float) -> float:
	return _sample("CPOL", x, z, 0.0)


## Půdní třída (`SOIL_*`) – kategorická, nejbližší buňka.
func soil(x: float, z: float) -> int:
	return _sample_nearest("SOIL", x, z, SOIL_HNEDOZEM)


## Hloubka půdy (cm).
func soil_depth(x: float, z: float) -> float:
	return _sample("SDEP", x, z, 50.0)


## Využitelná vodní kapacita (mm) – kolik vody půda v daném profilu zadrží (M8.7 vstup).
func awc(x: float, z: float) -> float:
	return _sample("AWC_", x, z, 120.0)


## pH půdy (skutečná hodnota, ne ×10 jako v souboru).
func ph(x: float, z: float) -> float:
	return _sample("PH__", x, z, 6.0)


## Živiny 0..1 (zjednodušeně, bez BPEJ).
func nutr(x: float, z: float) -> float:
	return _sample("NUTR", x, z, 0.5)


## Vše najednou pro ladění (F2 → Příroda – ladění, deník…).
func at(x: float, z: float) -> Dictionary:
	var s := soil(x, z)
	return {
		"elev": elev(x, z), "slope": slope(x, z), "aspect": aspect(x, z), "twi": twi(x, z),
		"dist_water": dist_water(x, z), "hand": hand(x, z), "tpi": tpi(x, z), "wind_exp": wind_exp(x, z),
		"insol": insol(x, z), "insol_winter": insol_winter(x, z), "cold_pool": cold_pool(x, z),
		"soil": s, "soil_name": SOIL_NAMES[s] if s >= 0 and s < SOIL_NAMES.size() else "?",
		"soil_depth": soil_depth(x, z), "awc": awc(x, z), "ph": ph(x, z), "nutr": nutr(x, z),
	}
