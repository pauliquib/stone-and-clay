## Zákon jako data (M0.5): katalog přestupků `data/zakon.json` + rejstřík a body jednoho hráče (LawRecord).
## Všechny pokuty, body a zákazy řízení jdou přes `World.commit_offense(id, offense_id, data)` → `LawRecord.commit`.
## Další kroky do katalogu jen přidávají řádky. Částky jsou orientační a zjednodušené – nejde o právní radu.
class_name Law
extends RefCounted

const PATH := "res://data/zakon.json"
const MAX_RECORDS := 200

## Přejmenovaná id přestupků (staré uložené pozice / rejstříky) → dnešní id.
const ALIASES := {"rychlost_obec_20": "rychlost_obec"}

static var _cache := {}

## Načte (a uloží do cache) celý katalog; při chybě prázdný slovník.
static func load_catalog() -> Dictionary:
	if _cache.is_empty():
		var txt := FileAccess.get_file_as_string(PATH)
		var d = JSON.parse_string(txt) if txt != "" else null
		_cache = d if d is Dictionary else {"prestupky": {}}
	return _cache


static func offense(id: String) -> Dictionary:
	return (load_catalog().get("prestupky", {}) as Dictionary).get(ALIASES.get(id, id), {})


static func setting(key: String, def: float) -> float:
	return float(load_catalog().get(key, def))


static func _lerp_range(r, sev: float) -> float:
	if not (r is Array) or r.size() < 2:
		return 0.0
	return lerpf(float(r[0]), float(r[1]), clampf(sev, 0.0, 1.0))


## Rejstřík a body jednoho hráče.
class LawRecord:
	extends RefCounted
	var points := 0
	var records: Array = []          # {t, id, pokuta, body, zaplaceno, trestny_cin}
	var unpaid_fines := 0            # součet nezaplacených zbytků pokut (placení řeší M4.2)
	var last_offense_t := -1.0       # herní minuty posledního přestupku s body
	var _decay_t := 0.0              # odkdy se počítá odpočet bodů

	## Body se po roce (herním) bez přestupku snižují o `body_odpocet`.
	func refresh(now: float) -> void:
		if points <= 0:
			_decay_t = now
			return
		var year := Law.setting("body_odpocet_rok_min", 525600.0)
		var base := maxf(last_offense_t, _decay_t)
		var n := int(floor((now - base) / year))
		if n > 0:
			points = maxi(points - n * int(Law.setting("body_odpocet", 4.0)), 0)
			_decay_t = base + n * year

	## Zapíše přestupek. data: severity 0..1 (rozmezí pokuty / zákazu), player (Player – peníze a zákaz řízení).
	## Vrací {ok, id, name, par, fine, paid, points, total_points, ban_h, points_ban, criminal, text}.
	func commit(id: String, data: Dictionary, now: float) -> Dictionary:
		var o := Law.offense(id)
		if o.is_empty():
			return {"ok": false, "id": id}
		refresh(now)
		var sev := float(data.get("severity", 0.0))
		var fine := int(roundf(Law._lerp_range(o.get("pokuta"), sev) / 10.0) * 10.0)
		var pts := int(o.get("body", 0))
		var ban_h := Law._lerp_range(o.get("zakaz_rizeni_h"), sev)
		var pl = data.get("player")
		var paid := fine
		if pl != null:
			paid = mini(fine, int(pl.money))
			pl.money -= paid
		unpaid_fines += fine - paid
		points += pts
		if pts > 0:
			last_offense_t = now
			_decay_t = now
		var points_ban := false
		if points >= int(Law.setting("body_limit", 12.0)):
			points_ban = true
			ban_h = maxf(ban_h, Law.setting("zakaz_za_body_h", 8760.0))
			points = 0
		if pl != null and ban_h > 0.0:
			pl.license_suspended_until = maxf(pl.license_suspended_until, now + ban_h * 60.0)
		var crim := bool(o.get("trestny_cin", false))
		records.append({"t": now, "id": id, "pokuta": fine, "body": pts, "zaplaceno": paid >= fine, "trestny_cin": crim})
		if records.size() > Law.MAX_RECORDS:
			records = records.slice(records.size() - Law.MAX_RECORDS)
		return {"ok": true, "id": id, "name": String(o.get("nazev", id)), "par": _par(o), "fine": fine, "paid": paid,
			"points": pts, "total_points": points, "ban_h": ban_h, "points_ban": points_ban, "criminal": crim}

	static func _par(o: Dictionary) -> String:
		var z := String(o.get("zakon", "?"))
		var p := String(o.get("par", "?"))
		return "%s %s" % [p, z] if p != "?" or z != "?" else "?"

	func to_dict() -> Dictionary:
		return {"points": points, "records": records, "unpaid": unpaid_fines, "last": last_offense_t, "decay": _decay_t}

	func from_dict(d: Dictionary) -> void:
		points = int(d.get("points", 0))
		records = (d.get("records", []) as Array).duplicate(true)
		unpaid_fines = int(d.get("unpaid", 0))
		last_offense_t = float(d.get("last", -1.0))
		_decay_t = float(d.get("decay", 0.0))
