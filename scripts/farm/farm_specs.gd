## Hospodářská zvířata (M2.6) – ekonomika a péče na JEDNOM místě (ceny, krmivo, produkty, maso).
## Vzhled a pohyb bere `FarmAnimal` z `AnimalSpecs` (klíč `model`) nebo z vlastního jednoduchého
## modelu slepice (`model == "bird"`); tahle tabulka se stará jen o chov.
##
## Klíče: name (samice / obecně), name_m (jen slepice: kohout), model, shelter (kurnik/chlivek/pristresek –
## `Pen.shelter_pos`), price_young / price_adult (Kč), grow_days (věk dospělosti ve dnech), feeds (krmivo
## z `ItemsDB` navíc ke každé položce s kladným klíčem `feed`, M2.4 zelenina), graze (true = pasoucí se
## druh pomalu sytí sám přes den mimo zimu, i bez krmení), hunger_day / thirst_day (úbytek sytosti /
## napojení za den bez krmení), product ("vejce" / "mleko" / "vlna" / "" bez produktu), product_amount
## [min, max] (ks vajec za den u slepice, litrů mléka za den u kozy/krávy), product_chance (slepice: šance
## snesení za den), winter_mult (méně v zimě), wool_months (jen ovce), meat_item + meat_kg [min, max],
## fat_item + fat_kg (jen prase, sádlo), xp (chovatelství za péči), helper_needed (jen prase – zabijačka
## chce pomocníka nebo řezníka), breeds (jen slepice – kohout + slepice → kuřata na jaře).
class_name FarmSpecs
extends RefCounted

const DATA := {
	"slepice": {
		"name": "Slepice", "name_m": "Kohout", "model": "bird", "shelter": "kurnik",
		"price_young": 120, "price_adult": 250, "grow_days": 60,
		"feeds": ["zrni"], "graze": false, "hunger_day": 0.5, "thirst_day": 0.6,
		"product": "vejce", "product_amount": [0, 1], "product_chance": 0.75, "winter_mult": 0.4,
		"meat_item": "maso_drubez", "meat_kg": [1.2, 1.8], "xp": 3.0, "breeds": true,
	},
	"kralik": {
		"name": "Králík", "model": "kralik", "shelter": "kurnik",
		"price_young": 150, "price_adult": 300, "grow_days": 90,
		"feeds": ["seno"], "graze": false, "hunger_day": 0.55, "thirst_day": 0.5,
		"product": "", "meat_item": "maso_kralici", "meat_kg": [1.0, 1.8], "xp": 3.0,
	},
	"prase": {
		"name": "Prase", "model": "prase_farm", "shelter": "chlivek",
		"price_young": 1500, "price_adult": 6000, "grow_days": 180,
		"feeds": ["granule", "brambory"], "graze": false, "hunger_day": 0.8, "thirst_day": 0.7,
		"product": "", "meat_item": "maso_veprove", "meat_kg": [45.0, 70.0],
		"fat_item": "sadlo", "fat_kg": [8.0, 15.0], "xp": 8.0, "helper_needed": true,
	},
	"koza": {
		"name": "Koza", "model": "koza", "shelter": "pristresek",
		"price_young": 1800, "price_adult": 3500, "grow_days": 150,
		"feeds": ["seno"], "graze": true, "hunger_day": 0.35, "thirst_day": 0.4,
		"product": "mleko", "product_amount": [1.0, 2.0], "winter_mult": 0.5, "milk_female_only": true,
		"meat_item": "maso_kozi", "meat_kg": [18.0, 25.0], "xp": 6.0,
	},
	"ovce": {
		"name": "Ovce", "model": "ovce", "shelter": "pristresek",
		"price_young": 2000, "price_adult": 4000, "grow_days": 150,
		"feeds": ["seno"], "graze": true, "hunger_day": 0.3, "thirst_day": 0.4,
		"product": "vlna", "wool_months": [5, 6],
		"meat_item": "maso_skopove", "meat_kg": [20.0, 30.0], "xp": 6.0,
	},
	"krava": {
		"name": "Kráva", "model": "krava", "shelter": "pristresek",
		"price_young": 15000, "price_adult": 30000, "grow_days": 365,
		"feeds": ["seno"], "graze": true, "hunger_day": 0.2, "thirst_day": 0.3,
		"product": "mleko", "product_amount": [10.0, 15.0], "winter_mult": 0.6, "milk_female_only": true,
		"meat_item": "maso_hovezi", "meat_kg": [180.0, 250.0], "xp": 12.0,
	},
}
## Pořadí v nabídce (cedule u výběhu).
const ORDER := ["slepice", "kralik", "prase", "koza", "ovce", "krava"]
const YOUNG_SCALE := 0.4      # vizuální měřítko mláděte (roste lineárně do 1.0 v `grow_days`)


static func info(species: String) -> Dictionary:
	return DATA.get(species, {}) as Dictionary


static func display_name(species: String, sex: String) -> String:
	var d := info(species)
	if sex == "m" and d.has("name_m"):
		return String(d["name_m"])
	return String(d.get("name", species))


## Krmivo, které daný druh přijme: vlastní seznam (`feeds`) + libovolná položka s kladným `feed` v `ItemsDB`
## (M2.4 zelenina – brambory, mrkev, salát, dýně).
static func accepts_feed(species: String, item_id: String) -> bool:
	var d := info(species)
	if item_id in (d.get("feeds", []) as Array):
		return true
	return ItemsDB.exists(item_id) and float(ItemsDB.info(item_id).get("feed", 0.0)) > 0.0


static func is_adult(species: String, age_days: float) -> bool:
	return age_days >= float(info(species).get("grow_days", 60.0))
