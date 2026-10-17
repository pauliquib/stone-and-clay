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

## M8.D: laditelné (F3 → Svět → Eko-takt) – `static var`, výchozí beze změny.
static var SLICE_BUDGET_US := 2000     # 00_PRINCIPY kap. 6: max. ~2 ms práce EcoClock za snímek i ve špičce
## Optimalizace CPU (17. 10. 2026): strop jen pro práce ze `slice()` (stavba mřížky luk, stanovišť…) v rámci
## SLICE_BUDGET_US – během hraní se staví pomaleji, ale snímek zatíží míň (F3 → Svět/Eko-takt, `tune_m8_19.gd`).
static var JOB_BUDGET_US := 1000
static var MAX_CATCHUP_DAYS := 30      # delší dluh (dlouhé vězení…) → jeden hrubý krok místo stovek signálů

var world: World
var _last_hidx := -1              # poslední dohnaná "hodina" = jd * 24 + floor(hour); -1 = neinicializováno
var _last_day := -1
var _jobs: Array[Dictionary] = [] # fronta prací ze `slice()`: {idx, items, per_frame, cb, prof}
var _rr := 0                      # oprava výkonu po M8: kterou prací začít (střídání, žádné hladovění)


func _init(w: World) -> void:
	world = w


## Zavolej jednou za snímek (`World._process_impl`). Nerozkládá vlastní práci (to dělají odběratelé
## signálů), jen hlídá, kolik celých herních hodin/dní uběhlo, a dožene to po krocích.
## Oprava výkonu po M8: hodiny i práce ze `slice()` sdílí **jeden** časový rozpočet `SLICE_BUDGET_US` za snímek
## (dřív měly každá svůj a práce kontrolovaly čas jen mezi sebou → kus 700 buněk luk = desítky ms).
func tick() -> void:
	var clock: Clock = world.clock
	if clock == null:
		return
	var t0 := Time.get_ticks_usec()
	var hidx := clock.jd() * 24 + int(floor(clock.hour()))
	if _last_hidx < 0:
		_last_hidx = hidx
		_last_day = clock.jd()
		return
	var diff := hidx - _last_hidx
	if diff > 0:
		var pt := Tests.prof_t0()
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
			while _last_hidx < hidx:
				_last_hidx += 1
				world.eco_hour.emit(1.0)
				var emitted_day := int(_last_hidx / 24)
				if emitted_day != _last_day:
					_last_day = emitted_day
					world.eco_day.emit(_last_day)
				if Time.get_ticks_usec() - t0 > SLICE_BUDGET_US:
					break        # zbytek dluhu dožene příští snímky (žádný zásek hry)
		Tests.prof_add("world_eco_signals", pt)
	_drain_jobs(t0)


## Zaregistruje práci po `items` kusech (budoucí kroky M8 – mřížka stanovišť, vítr, strom po stromu…).
## `cb` se zavolá postupně pro 0..items-1, bez přeskoků. Za snímek nejvýš `per_frame` kusů **a** jen dokud
## nevyprší společný časový rozpočet `SLICE_BUDGET_US` (čas se kontroluje po každém kusu – jeden kus má být
## ≲ 0,3 ms). `tag` = jméno pro profiler (`PERF world_job_<tag>`), prázdné = jméno metody `cb`.
func slice(items: int, per_frame: int, cb: Callable, tag := "") -> void:
	if items <= 0:
		return
	if tag == "":
		tag = String(cb.get_method())
	_jobs.append({"idx": 0, "items": items, "per_frame": maxi(per_frame, 1), "cb": cb, "prof": "world_job_" + tag})


## Rozběhnuté práce ze `slice()` (pro ladění / testy).
func jobs_pending() -> int:
	return _jobs.size()


## Práce ze `slice()` v tomto snímku: dokud zbývá rozpočet (od `t0` = začátek `tick`, tj. včetně hodinových
## signálů), střídavě po pracích – každý snímek začíná další prací v pořadí (`_rr`), ať dlouhá práce (stavba
## mřížky luk) nezablokuje hodinový plán domácností. Aspoň jeden kus za snímek proběhne vždy (žádné uváznutí).
func _drain_jobs(t0: int) -> void:
	if _jobs.is_empty():
		return
	var order: Array[Dictionary] = []
	var nj := _jobs.size()
	_rr = (_rr + 1) % nj
	for q in nj:
		order.append(_jobs[(_rr + q) % nj])
	var done_any := false
	var did := 0
	# konec rozpočtu: celkový (od začátku tick, včetně hodinových signálů) i jen pro práce (JOB_BUDGET_US)
	var t_end := mini(t0 + SLICE_BUDGET_US, Time.get_ticks_usec() + JOB_BUDGET_US)
	for job in order:
		if did > 0 and Time.get_ticks_usec() > t_end:
			break
		var pt := Tests.prof_t0()
		var cb: Callable = job["cb"]
		var idx: int = job["idx"]
		var items: int = job["items"]
		var cap: int = mini(idx + int(job["per_frame"]), items)
		while idx < cap:
			cb.call(idx)
			idx += 1
			did += 1
			if Time.get_ticks_usec() > t_end:
				break
		job["idx"] = idx
		if idx >= items:
			job["done"] = true
			done_any = true
		Tests.prof_add(String(job["prof"]), pt)
	if done_any:
		var keep: Array[Dictionary] = []
		for job in _jobs:              # i práce přidané během snímku (cb může volat slice) zůstanou
			if not job.has("done"):
				keep.append(job)
		_jobs = keep


## Ukládání (save klíč `eco`, 00_SPOLECNE kap. 5.6): jen poslední dohnaný bod, žádný dluh se
## nenese mezi uloženími – po načtení se eko-takt rozjede od aktuálního času bez dohánění.
func to_dict() -> Dictionary:
	return {"last_hidx": _last_hidx}


func restore(d: Dictionary) -> void:
	_last_hidx = int(d.get("last_hidx", -1))
	_last_day = int(_last_hidx / 24) if _last_hidx >= 0 else -1
