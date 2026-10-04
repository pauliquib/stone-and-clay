## Pomocné funkce pro nápoje, jídlo a cigarety. Data jsou v `ItemsDB` (M0.2); `ITEMS` je jen alias.
## Spacák – type "gear", používá se z inventáře, nespotřebuje se.
## Nápoje: objem balení (ml), porce na jedno napití (ml), obsah alkoholu (obj. %), cena.
## Jídlo: kcal (dle běžných nutričních tabulek), sytost.
class_name Consumables
extends RefCounted

const ETHANOL_DENSITY := 0.789   # g/ml

## Alias na jednotný katalog `ItemsDB.ITEMS` (M0.2).
const ITEMS := ItemsDB.ITEMS


static func info(id: String) -> Dictionary:
	return ItemsDB.info(id)


## Gramy čistého alkoholu v `ml` nápoje.
static func ethanol_g(id: String, ml: float) -> float:
	return ml * float(ITEMS[id].get("abv", 0.0)) / 100.0 * ETHANOL_DENSITY


static func is_alcohol(id: String) -> bool:
	return float(ITEMS[id].get("abv", 0.0)) > 0.0


static func fmt_price(kc: int) -> String:
	return "%d Kč" % kc
