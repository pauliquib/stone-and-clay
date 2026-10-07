## `scripts/eko/` – nová složka pro simulační systémy M8 „Realistický svět“ (00_PRINCIPY kap. 9):
## věci, co počítají stav krajiny / ekosystému ve `World` (server), ne jejich vzhled (ten je
## v `scripts/priroda/` nebo `scripts/vegetation/`, shadery v `shaders/`).
##
## `EcoClock` (M8.1, instance `World.eco`) je **jediný zdroj** hodinového a denního kroku pro
## všechny modely M8 – nic z M8 nesmí počítat svoje „jednou za herní hodinu“ samo v `_process`.
## Vysílá signály přímo na `World` (`World.eco_hour(dt_h)`, `World.eco_day(jd)`), aby se odběratelé
## z kontraktu (00_PRINCIPY kap. 3) připojovali jako `World.eco_hour.connect(...)`.
##
## Při normálním běhu emituje `eco_hour(1.0)` přesně jednou za celou herní hodinu. Při skoku času
## (spánek, F2, vězení) dožene zameškané hodiny **po krocích rozložených do snímků** (časový
## rozpočet `SLICE_BUDGET_US` na snímek – nikdy celý dluh v jednom snímku); skok delší než
## `MAX_CATCHUP_DAYS` dní se místo stovek jednotlivých signálů dožene jedním hrubým krokem
## s `dt_h` = zbytek hodin (00_PRINCIPY kap. 6).
##
## `slice(items, per_frame, cb)` je obecný pomocník pro budoucí kroky M8: zavolá `cb(i)` pro
## `i` 0..items-1, po nejvýš `per_frame` kusech za snímek (a v rámci stejného časového rozpočtu
## jako dohánění hodin), ať žádný krok nepočítá celý katastr v jednom snímku.
class_name EcoClock
extends RefCounted

const SLICE_BUDGET_US := 2000     # 00_PRINCIPY kap. 6: max. ~2 ms práce EcoClock za snímek i ve špičce
const MAX_CATCHUP_DAYS := 30      # delší dluh (dlouhé vězení…) → jeden hrubý krok místo stovek signálů

var world: World
var _last_hidx := -1              # poslední dohnaná "hodina" = jd * 24 + floor(hour); -1 = neinicializováno
var _last_day := -1
var _jobs: Array[Dictionary] = [] # fronta prací ze `slice()`: {idx, items, per_frame, cb}


func _init(w: World) -> void:
	world = w


## Zavolej jednou za snímek (`World._process_impl`). Nerozkládá vlastní práci (to dělají odběratelé
## signálů), jen hlídá, kolik celých herních hodin/dní uběhlo, a dožene to po krocích.
func tick() -> void:
	var clock: Clock = world.clock
	if clock == null:
		return
	var hidx := clock.jd() * 24 + int(floor(clock.hour()))
	if _last_hidx < 0:
		_last_hidx = hidx
		_last_day = clock.jd()
		return
	var diff := hidx - _last_hidx
	if diff > 0:
		if diff > MAX_CATCHUP_DAYS * 24:
			# moc velký skok (dlouhé vězení apod.) – jeden hrubý krok, ne stovky jednotlivých signálů
			var dt_h := float(diff)
			_last_hidx = hidx
			world.eco_hour.emit(dt_h)
			var day := clock.jd()
			if day != _last_day:
				_last_day = day
				world.eco_day.emit(day)
		else:
			var t0 := Time.get_ticks_usec()
			while _last_hidx < hidx:
				_last_hidx += 1
				world.eco_hour.emit(1.0)
				var emitted_day := int(_last_hidx / 24)
				if emitted_day != _last_day:
					_last_day = emitted_day
					world.eco_day.emit(_last_day)
				if Time.get_ticks_usec() - t0 > SLICE_BUDGET_US:
					break        # zbytek dluhu dožene příští snímky (žádný zásek hry)
	_drain_jobs()


## Zaregistruje práci po `items` kusech, rozloženou po nejvýš `per_frame` za snímek (budoucí kroky
## M8 – mřížka stanovišť, vítr, strom po stromu…). `cb` se zavolá postupně pro 0..items-1, bez přeskoků.
func slice(items: int, per_frame: int, cb: Callable) -> void:
	if items <= 0:
		return
	_jobs.append({"idx": 0, "items": items, "per_frame": maxi(per_frame, 1), "cb": cb})


func _drain_jobs() -> void:
	if _jobs.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	while not _jobs.is_empty():
		var job: Dictionary = _jobs[0]
		var remain: int = int(job["items"]) - int(job["idx"])
		var n: int = mini(int(job["per_frame"]), remain)
		var cb: Callable = job["cb"]
		for k in n:
			cb.call(int(job["idx"]) + k)
		job["idx"] = int(job["idx"]) + n
		if int(job["idx"]) >= int(job["items"]):
			_jobs.pop_front()
		if Time.get_ticks_usec() - t0 > SLICE_BUDGET_US:
			break


## Ukládání (save klíč `eco`, 00_SPOLECNE kap. 5.6): jen poslední dohnaný bod, žádný dluh se
## nenese mezi uloženími – po načtení se eko-takt rozjede od aktuálního času bez dohánění.
func to_dict() -> Dictionary:
	return {"last_hidx": _last_hidx}


func restore(d: Dictionary) -> void:
	_last_hidx = int(d.get("last_hidx", -1))
	_last_day = int(_last_hidx / 24) if _last_hidx >= 0 else -1
