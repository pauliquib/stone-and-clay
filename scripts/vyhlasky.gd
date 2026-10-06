## Obecně závazné vyhlášky obce (M4.4 část B) a suché / čerstvé větve. Jeden uzel ve `World` (`World.vyhlasky`).
##
## - Vyhlášky jsou data v `data/zakon.json` → klíč `vyhlasky` (zákaz pálení v zadaných měsících, sucho, nedělní klid).
##   Platné se ukážou na úřední desce (`board_lines`, čte je `computer_ui`).
## - Větve: odvětvení dává `vetve_cerstve` a zapíše dávku (`add_fresh`). Dávka po ~30 dnech (rychleji za sucha, pomaleji
##   za deště) přejde na suché `vetve` (`_tick`). Zjednodušení: dávka nesleduje konkrétní kusy, jen počet v kapse.
##   Hromada klestí jako objekt ve světě zatím není (otevřený bod).
## - Pálení: přiložení větví do ohně → `on_fuel`. Čerstvé větve = hustý kouř (`paleni_mokreho_odpadu`). Suché větve za
##   zákazu pálení nebo sucha mimo vlastní pozemek = `poruseni_vyhlasky_obce`. Svědek kouře (`witness_reported`) →
##   přestupek hned, jinak nenahlášený čin (`World.add_unreported`, odhalí hajný / policie).
## - Zákaz zalévání z vodovodu (`zalevani_zakazano`) zatím nemá háček – vodovodní zdroj ve hře není (otevřený bod).
## - Ukládání: klíč `vyhlasky` v záznamu hráče (dávky čerstvých větví); `Weather.drought` má klíč v `weather`.
class_name Vyhlasky
extends Node

# ------------------------------------------------------------------ laditelné hodnoty

const TICK_MIN := 60.0                 # herní minuty mezi průchody sušení
const DRY_DAYS := 30.0                 # dny, za které čerstvé větve proschnou (ladit)
const DRY_DROUGHT_K := 1.5             # × rychlost schnutí při suchu (Weather.drought = 1)
const DRY_RAIN_K := 0.4                # × rychlost schnutí při dešti (Weather.rain_recent = 1)
const MAX_BATCHES := 20                # nejvíc dávek čerstvých větví na hráče
const SMOKE_R := 200.0                 # m – dohled kouře od ohně
const SMOKE_SEV := 0.3                 # závažnost přestupku za kouř / pálení
const HOME_R := 30.0                   # m od dveří domu – vlastní pozemek (oheň tu zákaz nepostihuje)
const SUCHO_OD := 0.6                  # Weather.drought od této hodnoty platí vyhláška sucha
const FRESH_ITEM := "vetve_cerstve"
const DRY_ITEM := "vetve"

var world: World
var batches := {}                      # id hráče → [{n: int, dny: float}] dávky čerstvých větví
var _last_min := -1.0


func setup(w: World) -> void:
	world = w


## Vyhlášky z katalogu `data/zakon.json` (klíč `vyhlasky`).
static func catalog() -> Array:
	return Law.load_catalog().get("vyhlasky", []) as Array


func _vyhlaska(id: String) -> Dictionary:
	for v in catalog():
		var d: Dictionary = v
		if String(d.get("id", "")) == id:
			return d
	return {}


# ------------------------------------------------------------------ stav vyhlášek

## Zákaz pálení platí v měsíci z katalogu (`mesice`).
func zakaz_paleni() -> bool:
	if world == null or world.clock == null:
		return false
	var m := world.clock.month()
	for x in _vyhlaska("zakaz_paleni").get("mesice", []):
		if int(x) == m:
			return true
	return false


## Sucho: `Weather.drought` nad prahem → vyhláška sucha.
func sucho_aktivni() -> bool:
	return world != null and world.weather != null and world.weather.drought >= SUCHO_OD


## Zákaz zalévání a napouštění z vodovodu (za sucha). Háček zatím nikdo nevolá – vodovodní zdroj ve hře není.
func zalevani_zakazano() -> bool:
	return sucho_aktivni()


func _platna(id: String) -> bool:
	match id:
		"zakaz_paleni":
			return zakaz_paleni()
		"sucho":
			return sucho_aktivni()
	return bool(_vyhlaska(id).get("trvale", false))


## Řádky pro úřední desku: [název, text, „vyhláška“] – jen platné vyhlášky.
func board_lines() -> Array:
	var out := []
	for v in catalog():
		var d: Dictionary = v
		if _platna(String(d.get("id", ""))):
			out.append([String(d.get("nazev", "")), String(d.get("text", "")), "vyhláška"])
	return out


# ------------------------------------------------------------------ čerstvé větve

## Odvětvení: `n` čerstvých větví hráče `id` (dávka začne schnout).
func add_fresh(id: int, n: int) -> void:
	if n <= 0:
		return
	var list: Array = batches.get(id, [])
	list.append({"n": n, "dny": 0.0})
	if list.size() > MAX_BATCHES:
		list = list.slice(list.size() - MAX_BATCHES)
	batches[id] = list


func _process(_delta: float) -> void:
	if world == null or world.clock == null:
		return
	var m := world.clock.minutes
	if _last_min < 0.0 or m < _last_min:
		_last_min = m                  # první průchod nebo skok v kalendáři
		return
	if m - _last_min >= TICK_MIN:
		_tick(m - _last_min)
		_last_min = m


func _tick(dt_min: float) -> void:
	var rate := 1.0
	if world.weather:
		rate *= 1.0 + (DRY_DROUGHT_K - 1.0) * clampf(world.weather.drought, 0.0, 1.0)
		rate *= lerpf(1.0, DRY_RAIN_K, clampf(world.weather.rain_recent, 0.0, 1.0))
	var dd := dt_min / 1440.0 * rate
	for pid in batches.keys():
		var p: Player = world.players.get(pid)
		var keep := []
		for b in batches[pid]:
			var bd: Dictionary = b
			bd["dny"] = float(bd.get("dny", 0.0)) + dd
			if float(bd["dny"]) < DRY_DAYS:
				keep.append(bd)
				continue
			# dávka proschla: kusy, které hráč ještě nese, se změní na suché větve
			if p != null:
				var have := mini(int(bd.get("n", 0)), p.item_count(FRESH_ITEM))
				if have > 0:
					p.remove_item(FRESH_ITEM, have)
					p.add_item(DRY_ITEM, have)
		batches[pid] = keep


# ------------------------------------------------------------------ pálení

## Přiložení větví do ohně (volá `FireManager.add_fuel` po úspěšném přiložení).
func on_fuel(id: int, f: Node3D, item: String) -> void:
	if item != FRESH_ITEM and item != DRY_ITEM:
		return
	var pos := f.global_position
	if item == FRESH_ITEM:
		_smoke(id, pos, "paleni_mokreho_odpadu")
	if (zakaz_paleni() or sucho_aktivni()) and world.lot_door().distance_to(pos) > HOME_R:
		_smoke(id, pos, "poruseni_vyhlasky_obce")


## Kouř z ohně: svědek ho nahlásí → přestupek hned; nikdo → nenahlášený čin (odhalí hajný / policie).
func _smoke(id: int, pos: Vector3, offense: String) -> void:
	if world.witness_reported(id, pos, "kour", SMOKE_R, SMOKE_R):
		world.commit_offense(id, offense, {"severity": SMOKE_SEV})
		world.notify(id, "popup", ["Někdo tě viděl a nahlásil kouř z ohně.", 3.5])
		return
	world.add_unreported(id, {"kind": offense, "offenses": [offense], "pos": pos, "t": world.clock.minutes,
		"value": 0.0, "severity": SMOKE_SEV, "tool": "oheň", "discover_p": 0.3})
	world.notify(id, "show_message", ["Kouř z ohně je vidět z dálky. Zatím si toho nikdo nevšiml.", 3.0])


# ------------------------------------------------------------------ ukládání

## Dávky čerstvých větví hráče `id` (klíč `vyhlasky` v záznamu hráče).
func to_dict(id: int) -> Dictionary:
	return {"cerstve": (batches.get(id, []) as Array).duplicate(true)}


## Starý save bez klíče = žádné čerstvé větve.
func restore(id: int, d: Dictionary) -> void:
	batches[id] = (d.get("cerstve", []) as Array).duplicate(true)
