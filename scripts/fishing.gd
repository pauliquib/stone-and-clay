## Rybaření (M2.7), jeden uzel ve `World` (`World.fishing`). Minihra na udici u potoků a rybníků:
##
##   1. **Nahození** je běžná kontextová akce `nahodit` (`Actions.DEFS`, LMB na vodu s udicí v ruce a návnadou v kapse;
##      dosah s udicí `ActionRunner.ROD_RANGE` 8 m). Po skončení akce handler `_on_cast` založí relaci hráče
##      (`sessions[id]`): splávek na hladině s kroužky a vlasec od špičky prutu.
##   2. **Čekání na záběr** (5–90 s): doba = `WAIT_MEAN_S` / šance; šance = místo × denní doba × počasí × sezóna ×
##      návnada × úroveň Rybaření (`bite_factor`, všechny činitele jsou v konstantách níž). Splávek jemně poskakuje,
##      při záběru se ponoří a zní šplouchnutí. LMB během čekání vlasec stáhne (návnada se vrátí).
##   3. **Záseck:** do `STRIKE_WINDOW_S` (1,2 s) od ponoření stisknout LMB, jinak ryba návnadu sní.
##   4. **Zdolávání:** napětí vlasce 0..1 (pruh v HUD přes `action_progress`): LMB drží = navíjí (napětí roste), pustit =
##      povolí, ryba občas „zabere“ (skok napětí). Přes 1 vlasec praskne (ztráta návnady, udice se víc opotřebuje).
##      Ryba se přitahuje jen v zelené zóně `GREEN_LO`–`GREEN_HI`; pod ní se vzdaluje. Délka boje 5–40 s podle velikosti.
##      Větší ryba (> `NET_CM`) bez podběráku v kapse se s šancí utrhne těsně u břehu.
##   5. **Úlovek:** druh, cm a kg z `data/ryby.json` (`FISH`), hláška „Kapr obecný 48 cm, 2,1 kg“, XP Rybaření podle
##      velikosti, menu ponechat / pustit (pustit: karma +0,5 u malých a hájených ryb).
##
## Zákon (háčky pro M4.6): ponechání ryby pod lovnou mírou nebo v době hájení = přestupek `rybolov_mira_hajeni`;
## rybaření bez `World.has_permit(id, "rybarsky_listek"|"povolenka_rybolov", pos)` = `rybarske_pytlactvi`; obojí se
## zjistí jen tehdy, když je poblíž svědek (`Forestry.witness_near`), zatím bez rybářské stráže.
##
## Žížaly: akce `kopat_zizaly` (lopata / motyka, vlastní pozemek u domu, po dešti víc kusů).
## Data: `data/ryby.json` (bez souboru se použije malá vestavěná tabulka `FALLBACK_SPECIES`).
class_name Fishing
extends Node3D

const PATH := "res://data/ryby.json"
const ROD_TOOLS := ["udice", "udice_lepsi"]
const BAITS := ["navnada_zizaly", "navnada_kukurice", "navnada_testo"]   # v tomto pořadí se bere z kapsy
const MIN_CAST_M := 1.5              # blíž než tolik metrů od hráče nahodit nejde
const MIN_DEPTH := 0.3               # nejmenší hloubka vody v místě dopadu (m)
const FROZEN := 0.6                  # zamrznutí (Water.ice / ice_flow), od kterého nejde nahodit
const WAIT_MIN_S := 5.0
const WAIT_MAX_S := 90.0
const WAIT_MEAN_S := 40.0            # průměrná doba čekání při šanci 1
const STRIKE_WINDOW_S := 1.2
const LEAVE_M := 14.0                # dál od splávku se vlasec sám stáhne
const TENSION_START := 0.3
const GREEN_LO := 0.4
const GREEN_HI := 0.8
const REEL_RATE := 0.45              # růst napětí za s při navíjení
const SLACK_RATE := 0.35             # pokles napětí za s při povolení
const SURGE_S := 0.35                # délka jednoho „záběru“ ryby
const SLIP_K := 0.35                 # o kolik rychleji se ryba vzdaluje pod zelenou zónou (× rychlost přitahování)
const FIGHT_MIN_S := 5.0
const FIGHT_MAX_S := 40.0
const NET_CM := 40.0                 # větší ryby bez podběráku častěji utečou
const NET_LOSS_P := 0.3
const WITNESS_R := 45.0              # do kolika m svědek vidí rybáře
const FINE_COOLDOWN_MIN := 120.0     # herní minuty mezi dvěma pokutami za pytláctví (ať to nesype při každém hodu)
const ROD_BETTER_BITE := 1.15
const ROD_BETTER_REEL := 0.85
const DEFAULT_NADRZ_M2 := 20000.0
## Činitel místa podle druhu vody (`Water.info_at()["kind"]`).
const PLACE_MULT := {"pond": 1.0, "river": 0.9, "canal": 0.8, "stream": 0.8, "ditch": 0.6, "drain": 0.6}
## Činitel sezóny podle měsíce (leden … prosinec): zima ×0,3.
const MONTH_MULT := [0.3, 0.3, 0.7, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.7, 0.3]

## Vestavěná záloha, kdyby chyběl / byl poškozený `data/ryby.json`.
const FALLBACK_SPECIES := {
	"kapr": {"nazev": "Kapr obecný", "item": "ryba_kapr", "voda": ["rybnik", "nadrz"], "min_cm": 25, "max_cm": 80,
		"koef": 1.9e-5, "lovna_miera": 40, "hajeni": null, "noc_only": false, "vaha": 3.0, "cena": 120},
	"plotice": {"nazev": "Plotice obecná", "item": "ryba_plotice", "voda": ["rybnik", "nadrz", "reka", "potok"], "min_cm": 8,
		"max_cm": 30, "koef": 1.2e-5, "lovna_miera": 0, "hajeni": null, "noc_only": false, "vaha": 4.0, "cena": 25},
	"pstruh": {"nazev": "Pstruh obecný", "item": "ryba_pstruh", "voda": ["potok"], "min_cm": 12, "max_cm": 50,
		"koef": 1.0e-5, "lovna_miera": 25, "hajeni": [9, 1, 4, 15], "noc_only": false, "vaha": 5.0, "cena": 90},
}
const FALLBACK_BAITS := {"navnada_zizaly": {"faktor": 1.0, "druhy": {}}}

static var _data := {}

var world: World
var sessions := {}                   # id hráče → relace lovu (viz `_new_session`)
var pending := {}                    # id hráče → čerstvý úlovek čekající na „ponechat / pustit“
var _last_fine := {}                 # id hráče → herní minuty poslední pokuty za pytláctví
var _bob_mat: StandardMaterial3D
var _stub_mat: StandardMaterial3D
var _ring_mat: StandardMaterial3D
var _line_mat: StandardMaterial3D


## Načte (a uloží do cache) tabulku ryb a návnad; při chybě vestavěná záloha.
static func data() -> Dictionary:
	if _data.is_empty():
		var d = null
		if FileAccess.file_exists(PATH):
			var txt := FileAccess.get_file_as_string(PATH)
			d = JSON.parse_string(txt) if txt != "" else null
		if d is Dictionary and d.get("druhy") is Dictionary and not (d["druhy"] as Dictionary).is_empty():
			_data = d
		else:
			push_warning("Chybí nebo je vadné data/ryby.json – použita vestavěná tabulka ryb.")
			_data = {"druhy": FALLBACK_SPECIES, "navnady": FALLBACK_BAITS, "voda_nadrz_min_m2": DEFAULT_NADRZ_M2}
	return _data


static func species_table() -> Dictionary:
	return data().get("druhy", {})


## Je dané datum v době hájení druhu? Interval `hajeni` = [měsíc od, den od, měsíc do, den do], může přesahovat přes Nový rok.
static func in_closed_season(sp: Dictionary, month: int, day: int) -> bool:
	var h = sp.get("hajeni")
	if not (h is Array) or (h as Array).size() < 4:
		return false
	var a := int(h[0]) * 100 + int(h[1])
	var b := int(h[2]) * 100 + int(h[3])
	var n := month * 100 + day
	if a <= b:
		return n >= a and n <= b
	return n >= a or n <= b


## Hmotnost ryby v kg z délky (kg = koef × cm³).
static func weight_kg(sp: Dictionary, cm: float) -> float:
	return float(sp.get("koef", 1.5e-5)) * cm * cm * cm


static func fmt_kg(kg: float) -> String:
	var t := "%.2f" % kg if kg < 1.0 else "%.1f" % kg
	return t.replace(".", ",")


func setup(w: World) -> void:
	world = w
	name = "Rybareni"
	Actions.set_handler("nahodit", _on_cast)
	Actions.set_target_check("nahodit", _check_cast)
	Actions.set_handler("kopat_zizaly", _on_dig_worms)
	Actions.set_target_check("kopat_zizaly", _check_dig_worms)
	_bob_mat = StandardMaterial3D.new()
	_bob_mat.albedo_color = Color(0.9, 0.12, 0.1)
	_stub_mat = StandardMaterial3D.new()
	_stub_mat.albedo_color = Color(0.96, 0.96, 0.92)
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.albedo_color = Color(1, 1, 1, 0.5)
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_line_mat = StandardMaterial3D.new()
	_line_mat.albedo_color = Color(0.85, 0.85, 0.8)
	_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


# ------------------------------------------------------------------ voda, návnada, šance

func _player(id: int) -> Player:
	return world.players.get(id) as Player


func _msg(id: int, text: String, dur := 3.0) -> void:
	world.notify(id, "show_message", [text, dur])


## Značky vody pro tabulku ryb: "rybnik" (+ "nadrz" u velké plochy), "reka", "potok".
func water_tags(info: Dictionary, pos: Vector3) -> Array:
	match String(info.get("kind", "")):
		"pond":
			var tags := ["rybnik"]
			if _pond_area(pos) >= float(data().get("voda_nadrz_min_m2", DEFAULT_NADRZ_M2)):
				tags.append("nadrz")          # DOPLNIT: hranice plochy nádrže (výchozí 20 000 m²) – v datech nejsou názvy
			return tags
		"river", "canal":
			return ["reka"]
		_:
			return ["potok"]


## Plocha rybníka (m²), v němž leží bod; 0, když to není rybník.
func _pond_area(pos: Vector3) -> float:
	if world.water == null:
		return 0.0
	var p := Vector2(pos.x, pos.z)
	for pd in world.water.ponds:
		if (pd["aabb"] as Rect2).has_point(p) and Geometry2D.is_point_in_polygon(p, pd["poly"]):
			var poly: PackedVector2Array = pd["poly"]
			var a := 0.0
			for i in poly.size():
				var q := poly[(i + 1) % poly.size()]
				a += poly[i].x * q.y - q.x * poly[i].y
			return absf(a) * 0.5
	return 0.0


func is_frozen(info: Dictionary) -> bool:
	if world.water == null:
		return false
	var ice: float = world.water.ice if String(info.get("kind", "")) == "pond" else world.water.ice_flow
	return ice > FROZEN


func bait_of(p: Player) -> String:
	for b in BAITS:
		if p.item_count(b) > 0:
			return b
	return ""


## Druhy, které tady a teď mohou zabrat: {id druhu: váha}. V noci jen `noc_only` druhy (úhoř, sumec), ve dne ne.
func candidates(tags: Array, bait: String) -> Dictionary:
	var out := {}
	var night := world.clock.is_night()
	var baits: Dictionary = data().get("navnady", {})
	var pref: Dictionary = (baits.get(bait, {}) as Dictionary).get("druhy", {})
	for sid in species_table():
		var sp: Dictionary = species_table()[sid]
		if bool(sp.get("noc_only", false)) != night:
			continue               # v noci jen noční druhy (úhoř, sumec), ve dne jen ostatní
		var ok := false
		for t in sp.get("voda", []):
			if t in tags:
				ok = true
		if not ok:
			continue
		out[sid] = float(sp.get("vaha", 1.0)) * float(pref.get(sid, 1.0))
	return out


## Činitel šance na záběr a jeho části (pro ladění / hlášky): {f, misto, doba, pocasi, sezona, navnada, uroven}.
func bite_factor(id: int, kind: String, bait: String, rod: String) -> Dictionary:
	var place: float = PLACE_MULT.get(kind, 0.8)
	var h: float = world.clock.hour()
	var day := 1.0
	if world.clock.is_night():
		day = 0.8
	elif (h >= 5.0 and h < 9.0) or (h >= 17.0 and h < 21.0):
		day = 1.5              # ráno a večer
	elif h >= 11.0 and h < 15.0:
		day = 0.7              # poledne
	var wth := 1.0
	var w = world.weather
	if w != null:
		if w.kind in ["zatazeno", "prehanky", "dest"]:
			wth = 1.2          # zataženo / před deštěm
		elif w.kind == "oblacno":
			wth = 1.1
		elif w.kind == "bourka":
			wth = 0.5
		elif w.temp > 25.0 and w.kind in ["jasno", "polojasno"]:
			wth = 0.7          # jasno a horko
		if w.wind > 8.0:
			wth *= 0.8
	var season: float = MONTH_MULT[clampi(world.clock.month() - 1, 0, 11)]
	var baits: Dictionary = data().get("navnady", {})
	var bf := float((baits.get(bait, {}) as Dictionary).get("faktor", 1.0))
	var sk: Skills = world.skills.get(id)
	var lvl := 1.0 + 0.5 * (sk.bonus("rybareni") if sk else 0.0)
	if rod == "udice_lepsi":
		lvl *= ROD_BETTER_BITE
	return {"f": place * day * wth * season * bf * lvl, "misto": place, "doba": day, "pocasi": wth,
		"sezona": season, "navnada": bf, "uroven": lvl}


# ------------------------------------------------------------------ nahození (akce `nahodit`)

func _check_cast(aim: Dictionary, id: int) -> String:
	var p := _player(id)
	if p == null:
		return "Teď ne."
	if sessions.has(id):
		return _status_reason(id)
	var info: Dictionary = aim.get("data", {})
	if float(info.get("depth", 0.0)) < MIN_DEPTH:
		return "Tady je moc mělko."
	if is_frozen(info):
		return "Voda je zamrzlá."
	var pos: Vector3 = aim["pos"]
	if Vector2(pos.x - p.global_position.x, pos.z - p.global_position.z).length() < MIN_CAST_M:
		return "Moc blízko – nahoď dál od sebe."
	var bait := bait_of(p)
	if bait == "":
		return "Chybí návnada (žížaly, těstíčko, kukuřice)."
	if candidates(water_tags(info, pos), bait).is_empty():
		return "Tady teď nic nebere."
	return ""


## Text stavu relace – zobrazí se v nápovědě u spodního okraje (přes `target_reason`), dokud hráč míří na vodu.
func _status_reason(id: int) -> String:
	var s: Dictionary = sessions.get(id, {})
	match String(s.get("state", "")):
		"wait":
			return "Čekáš na záběr – [LMB] stáhnout vlasec"
		"bite":
			return "ZÁBĚR! [LMB] zaseknout!"
		"fight":
			return "Zdolávání – drž [LMB] = navíjet, pusť = povolit"
	return "Udice je nahozená."


func _on_cast(id: int, _def: Dictionary, aim: Dictionary, ok: bool) -> void:
	var p := _player(id)
	if p == null or not ok or sessions.has(id):
		return
	_resolve_pending(id)
	var info: Dictionary = aim.get("data", {})
	var bait := bait_of(p)
	if bait == "" or not p.remove_item(bait):
		_msg(id, "Chybí návnada.", 2.0)
		return
	var pos: Vector3 = aim["pos"]
	pos.y = float(info.get("level", pos.y))
	var s := _new_session(id, p, pos, info, bait)
	sessions[id] = s
	world.play_sfx(id, "splash", randf_range(0.9, 1.1), -4.0)
	world.sound.emit(pos, "splash", randf_range(0.9, 1.1), -6.0, 60.0)
	_msg(id, "Nahozeno. Čekej na záběr (LMB = stáhnout vlasec).", 3.0)
	_poach_check(id, s)


func _new_session(id: int, p: Player, pos: Vector3, info: Dictionary, bait: String) -> Dictionary:
	var kind := String(info.get("kind", ""))
	var f := bite_factor(id, kind, bait, p.equipped)
	var wait := clampf(WAIT_MEAN_S / maxf(float(f["f"]), 0.05) * randf_range(0.15, 1.8), WAIT_MIN_S, WAIT_MAX_S)
	var s := {"state": "wait", "pos": pos, "start": pos, "kind": kind, "tags": water_tags(info, pos), "bait": bait,
		"rod": p.equipped, "t": wait, "bite_left": 0.0, "nibble_t": randf_range(2.0, 6.0), "nibble": 0.0, "age": 0.0,
		"cast_m": maxf(Vector2(pos.x - p.global_position.x, pos.z - p.global_position.z).length(), 1.0),
		"species": "", "cm": 0.0, "kg": 0.0, "dist": 1.0, "tension": TENSION_START, "fight_len": 10.0, "frac": 0.0,
		"surge_in": 1.5, "surge_left": 0.0, "surge_str": 0.2, "fined": false}
	_make_visual(s)
	return s


# ------------------------------------------------------------------ vstup hráče

## LMB od hráče (volá `World.player_action("use_tool")` jako první). Vrací true, když kliknutí patřilo rybaření.
func on_click(id: int) -> bool:
	var s: Dictionary = sessions.get(id, {})
	if s.is_empty():
		return false
	match String(s["state"]):
		"wait":
			_end(id, "Vlasec stažen, návnada zůstala.", true)
		"bite":
			_hook(id, s)
		_:
			pass              # při zdolávání se navíjí podržením, klik nic nedělá
	return true


func cancel(id: int, msg := "") -> void:
	if sessions.has(id):
		var bait_back := String(sessions[id]["state"]) == "wait"
		_end(id, msg, bait_back)


func _hook(id: int, s: Dictionary) -> void:
	var sp: Dictionary = species_table().get(String(s["species"]), {})
	var mn := float(sp.get("min_cm", 10.0))
	var mx := float(sp.get("max_cm", 40.0))
	var frac := clampf((float(s["cm"]) - mn) / maxf(mx - mn, 1.0), 0.0, 1.0)
	var sk: Skills = world.skills.get(id)
	var b := sk.bonus("rybareni") if sk else 0.0
	s["state"] = "fight"
	s["frac"] = frac
	s["fight_len"] = lerpf(FIGHT_MIN_S, FIGHT_MAX_S, pow(frac, 0.8)) * randf_range(0.85, 1.15)
	s["surge_str"] = (0.15 + 0.25 * frac) * (1.0 - 0.35 * b)
	s["surge_in"] = randf_range(1.0, 2.5)
	s["surge_left"] = 0.0
	s["dist"] = 1.0
	s["tension"] = TENSION_START
	_msg(id, "Zaseknuto! Drž LMB = navíjet, pusť = povolit (napětí udrž v zelené).", 3.5)
	_poach_check(id, s)


# ------------------------------------------------------------------ průběh

func _process(delta: float) -> void:
	for id in sessions.keys():
		_tick(int(id), delta)


func _tick(id: int, delta: float) -> void:
	var s: Dictionary = sessions[id]
	var p := _player(id)
	if p == null:
		_end(id, "", false)
		return
	if p.car != null or p.horse != null or p.fallen > 0.0 or p.controls_locked:
		_end(id, "Vlasec stažen.", String(s["state"]) == "wait")
		return
	if p.equipped != String(s["rod"]):
		_end(id, "Odložil jsi udici – vlasec stažen.", String(s["state"]) == "wait")
		return
	var pos: Vector3 = s["pos"]
	if Vector2(pos.x - p.global_position.x, pos.z - p.global_position.z).length() > LEAVE_M:
		_end(id, "Odešel jsi daleko – vlasec stažen.", String(s["state"]) == "wait")
		return
	s["age"] = float(s["age"]) + delta
	match String(s["state"]):
		"wait":
			_tick_wait(id, s, delta)
		"bite":
			s["bite_left"] = float(s["bite_left"]) - delta
			if float(s["bite_left"]) <= 0.0:
				_end(id, "Ryba sežrala návnadu.", false)
				return
		"fight":
			if not _tick_fight(id, s, p, delta):
				return
	if sessions.has(id):
		_update_visual(s, p)


func _tick_wait(id: int, s: Dictionary, delta: float) -> void:
	s["nibble_t"] = float(s["nibble_t"]) - delta
	if float(s["nibble_t"]) <= 0.0:
		s["nibble"] = 1.0               # falešné klepnutí – jen vizuální
		s["nibble_t"] = randf_range(3.0, 9.0)
	s["nibble"] = maxf(float(s["nibble"]) - delta * 1.6, 0.0)
	s["t"] = float(s["t"]) - delta
	if float(s["t"]) > 0.0:
		return
	var cand := candidates(s["tags"], String(s["bait"]))
	if cand.is_empty():
		_end(id, "Teď tu už nic nebere.", true)
		return
	var sid := _pick_weighted(cand)
	var sp: Dictionary = species_table()[sid]
	var sk: Skills = world.skills.get(id)
	var b := sk.bonus("rybareni") if sk else 0.0
	var mn := float(sp.get("min_cm", 10.0))
	var mx := float(sp.get("max_cm", 40.0))
	if String(s["kind"]) in ["ditch", "drain"]:
		mx = maxf(mn + 1.0, mx * 0.6)          # malé příkopy = malé kusy
	var expo := maxf(2.2 - 0.9 * b - (0.4 if String(s["rod"]) == "udice_lepsi" else 0.0), 0.8)
	var cm := roundf(lerpf(mn, mx, pow(randf(), expo)))
	s["species"] = sid
	s["cm"] = cm
	s["kg"] = snappedf(weight_kg(sp, cm), 0.01)
	s["state"] = "bite"
	s["bite_left"] = STRIKE_WINDOW_S
	world.play_sfx(id, "splash", randf_range(1.0, 1.25), -2.0)
	_msg(id, "ZÁBĚR! Zasekni (LMB)!", 1.6)


func _pick_weighted(w: Dictionary) -> String:
	var total := 0.0
	for k in w:
		total += float(w[k])
	var r := randf() * total
	for k in w:
		r -= float(w[k])
		if r <= 0.0:
			return String(k)
	return String(w.keys()[0])


## Jeden krok zdolávání. Vrací false, když boj skončil (relace zrušena).
func _tick_fight(id: int, s: Dictionary, p: Player, delta: float) -> bool:
	var sk: Skills = world.skills.get(id)
	var b := sk.bonus("rybareni") if sk else 0.0
	var reel := p.input.reel
	var rate := REEL_RATE if reel else -SLACK_RATE
	if reel and String(s["rod"]) == "udice_lepsi":
		rate *= ROD_BETTER_REEL
	# záběr ryby: krátký skok napětí
	if float(s["surge_left"]) > 0.0:
		s["surge_left"] = float(s["surge_left"]) - delta
		rate += float(s["surge_str"]) / SURGE_S
	else:
		s["surge_in"] = float(s["surge_in"]) - delta
		if float(s["surge_in"]) <= 0.0:
			s["surge_left"] = SURGE_S
			s["surge_in"] = randf_range(1.5, 4.0) * (1.0 + 0.3 * b)
	var t := clampf(float(s["tension"]) + rate * delta, 0.0, 1.2)
	s["tension"] = t
	var step := delta / maxf(float(s["fight_len"]), 1.0)
	if t > 1.0:
		_snap(id, s, p)
		return false
	elif t >= GREEN_LO and t <= GREEN_HI:
		s["dist"] = float(s["dist"]) - step
	elif t < GREEN_LO:
		s["dist"] = float(s["dist"]) + step * SLIP_K
	var dist := float(s["dist"])
	var zone := "OK" if t >= GREEN_LO and t <= GREEN_HI else ("povol (pusť LMB)!" if t > GREEN_HI else "navíjej (drž LMB)")
	world.notify(id, "action_progress", ["Napětí vlasce %d %% – %s · ryba %d m" % [roundi(t * 100.0), zone,
		ceili(maxf(dist, 0.0) * float(s["cast_m"]))], clampf(t, 0.0, 1.0)])
	if dist >= 1.0:
		_end(id, "Ryba se ti vzdálila a vyklouzla z háčku.", false)
		return false
	if dist <= 0.0:
		_land(id, s, p)
		return false
	return true


func _snap(id: int, s: Dictionary, p: Player) -> void:
	if not p.wear_tool(String(s["rod"]), 3):
		_msg(id, "%s se rozlomila." % ItemsDB.name_of(String(s["rod"])), 3.0)
	_end(id, "Vlasec praskl! Ryba je pryč i s návnadou.", false)


func _land(id: int, s: Dictionary, p: Player) -> void:
	var cm := float(s["cm"])
	if cm > NET_CM and p.item_count("podberak") <= 0:
		var sk: Skills = world.skills.get(id)
		var b := sk.bonus("rybareni") if sk else 0.0
		if randf() < NET_LOSS_P * (1.0 - 0.5 * b):
			_end(id, "Velká ryba se těsně u břehu utrhla – podběrák by pomohl.", false)
			return
	var sid := String(s["species"])
	var sp: Dictionary = species_table().get(sid, {})
	var kg := float(s["kg"])
	if not p.wear_tool(String(s["rod"]), 1):
		_msg(id, "%s se rozlomila." % ItemsDB.name_of(String(s["rod"])), 3.0)
	var xp := minf(6.0 + kg * 8.0 + cm * 0.2, 150.0)
	world.give_xp(id, "rybareni", xp, "úlovek")
	world.emit_game_event(id, "fish_caught", {"species": sid, "cm": cm, "kg": kg})
	var name_ := String(sp.get("nazev", sid))
	var text := "%s %d cm, %s kg" % [name_, roundi(cm), fmt_kg(kg)]
	var warn := _warn_text(sp, cm)
	pending[id] = {"species": sid, "cm": cm, "kg": kg}
	var pos: Vector3 = s["pos"]
	_end(id, "", false)
	world.play_sfx(id, "success")
	_msg(id, "Úlovek: %s" % text, 4.0)
	var opts := [["Ponechat (do inventáře)", _keep.bind(id)], ["Pustit zpět do vody", _release.bind(id)]]
	world.notify(id, "open_menu", ["Úlovek", "%s.%s" % [text, warn], opts])
	pending[id]["pos"] = pos


func _warn_text(sp: Dictionary, cm: float) -> String:
	var parts := []
	var miera := float(sp.get("lovna_miera", 0.0))
	if miera > 0.0 and cm < miera:
		parts.append("pod lovnou mírou %d cm" % roundi(miera))
	if in_closed_season(sp, world.clock.month(), int(world.clock.date()["day"])):
		parts.append("v době hájení")
	return "" if parts.is_empty() else "\nPozor: %s – ponechat ji je přestupek, když to někdo uvidí." % ", ".join(parts)


# ------------------------------------------------------------------ ponechat / pustit

func _resolve_pending(id: int) -> void:
	if pending.has(id):
		_keep(id)              # menu zavřené Esc bez volby = úlovek se ponechá


func _keep(id: int) -> void:
	var c: Dictionary = pending.get(id, {})
	if c.is_empty():
		return
	pending.erase(id)
	var p := _player(id)
	if p == null:
		return
	var sid := String(c["species"])
	var sp: Dictionary = species_table().get(sid, {})
	var item := String(sp.get("item", ""))
	if item == "" or not ItemsDB.exists(item):
		_msg(id, "Tuhle rybu nemáš kam dát.", 2.0)
		return
	p.add_item(item)
	_msg(id, "Ponecháno: %s %d cm." % [String(sp.get("nazev", sid)), roundi(float(c["cm"]))], 3.0)
	var miera := float(sp.get("lovna_miera", 0.0))
	var bad := (miera > 0.0 and float(c["cm"]) < miera) or in_closed_season(sp, world.clock.month(), int(world.clock.date()["day"]))
	if bad and world.forestry != null and world.forestry.witness_near(p.global_position, WITNESS_R):
		world.commit_offense(id, "rybolov_mira_hajeni", {"severity": randf_range(0.0, 0.6)})
		_msg(id, "Někdo tě viděl – ryba pod mírou / v hájení!", 4.0)


func _release(id: int) -> void:
	var c: Dictionary = pending.get(id, {})
	if c.is_empty():
		return
	pending.erase(id)
	var sp: Dictionary = species_table().get(String(c["species"]), {})
	var miera := float(sp.get("lovna_miera", 0.0))
	var protect := (miera > 0.0 and float(c["cm"]) < miera) or in_closed_season(sp, world.clock.month(), int(world.clock.date()["day"]))
	var rep: Reputation = world.reputations.get(id)
	if protect and rep:
		rep.change_karma(0.5, "pustil malou / hájenou rybu")
	_msg(id, "Pustil jsi %s zpátky do vody." % String(sp.get("nazev", "rybu")).to_lower(), 2.5)
	var pos: Vector3 = c.get("pos", Vector3.ZERO)
	if pos != Vector3.ZERO:
		world.sound.emit(pos, "splash", randf_range(0.9, 1.1), -8.0, 40.0)


# ------------------------------------------------------------------ zákon (háčky pro M4.6)

## Rybaření bez lístku a povolenky je pytláctví – zjistí se jen před svědkem (vesničan, obsluha, hlídka).
func _poach_check(id: int, s: Dictionary) -> void:
	if bool(s["fined"]):
		return
	var pos: Vector3 = s["pos"]
	if world.has_permit(id, "rybarsky_listek", pos) and world.has_permit(id, "povolenka_rybolov", pos):
		return
	var p := _player(id)
	if p == null or world.forestry == null or not world.forestry.witness_near(p.global_position, WITNESS_R):
		return
	var now: float = world.clock.minutes
	if now - float(_last_fine.get(id, -1.0e9)) < FINE_COOLDOWN_MIN:
		return
	s["fined"] = true
	_last_fine[id] = now
	world.commit_offense(id, "rybarske_pytlactvi", {"severity": randf_range(0.0, 0.5)})
	_msg(id, "Někdo tě vidí rybařit bez lístku a povolenky!", 4.0)


# ------------------------------------------------------------------ žížaly (akce `kopat_zizaly`)

func _check_dig_worms(aim: Dictionary, id: int) -> String:
	var pos: Vector3 = aim["pos"]
	if world.forestry == null or world.forestry.zone_at(pos, id) != "own":      # M1.7: nájemník jen na pronajaté zahradě
		return "Žížaly kopej na vlastní zahradě."
	return ""


func _on_dig_worms(id: int, _def: Dictionary, _aim: Dictionary, ok: bool) -> void:
	var p := _player(id)
	if p == null or not ok:
		return
	var n := randi_range(3, 6)
	var w = world.weather
	if w != null and maxf(float(w.rain_recent), float(w.wetness)) > 0.4:
		n += randi_range(1, 3)            # po dešti je žížal víc
	p.add_item("navnada_zizaly", n)
	_msg(id, "Vykopáno %d× žížaly." % n, 2.5)


# ------------------------------------------------------------------ úklid relace, vizuál

func _end(id: int, msg: String, bait_back: bool) -> void:
	var s: Dictionary = sessions.get(id, {})
	if s.is_empty():
		return
	sessions.erase(id)
	for k in ["bobber", "line", "ring"]:
		var n = s.get(k)
		if n != null and is_instance_valid(n):
			(n as Node).queue_free()
	var p := _player(id)
	if p != null and bait_back and String(s["bait"]) != "":
		p.add_item(String(s["bait"]))
	world.notify(id, "action_progress", ["", -1.0])
	if msg != "":
		_msg(id, msg, 3.0)


func _make_visual(s: Dictionary) -> void:
	var bob := Node3D.new()
	bob.name = "Splavek"
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.035
	sm.height = 0.07
	sm.radial_segments = 10
	sm.rings = 5
	ball.mesh = sm
	ball.material_override = _bob_mat
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bob.add_child(ball)
	var stub := MeshInstance3D.new()
	var cm_ := CylinderMesh.new()
	cm_.top_radius = 0.005
	cm_.bottom_radius = 0.007
	cm_.height = 0.14
	cm_.radial_segments = 6
	stub.mesh = cm_
	stub.position = Vector3(0, 0.08, 0)
	stub.material_override = _stub_mat
	stub.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bob.add_child(stub)
	add_child(bob)
	bob.global_position = s["pos"]
	s["bobber"] = bob
	var ring := MeshInstance3D.new()
	ring.name = "KrouzkyNaHladine"
	var tm := TorusMesh.new()
	tm.inner_radius = 0.09
	tm.outer_radius = 0.1
	tm.rings = 20
	tm.ring_segments = 4
	ring.mesh = tm
	ring.scale = Vector3(1, 0.05, 1)
	ring.material_override = _ring_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	ring.global_position = s["pos"]
	s["ring"] = ring
	var line := MeshInstance3D.new()
	line.name = "Vlasec"
	line.mesh = ImmediateMesh.new()
	line.top_level = true
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(line)
	s["line"] = line


## Splávek se kolébá, při záběru se ponoří, při zdolávání se přibližuje; vlasec vede od špičky prutu.
func _update_visual(s: Dictionary, p: Player) -> void:
	var bob: Node3D = s.get("bobber")
	var ring: MeshInstance3D = s.get("ring")
	var line: MeshInstance3D = s.get("line")
	if bob == null or not is_instance_valid(bob):
		return
	var age := float(s["age"])
	var start: Vector3 = s["start"]
	var pos: Vector3 = start
	var dip := 0.0
	match String(s["state"]):
		"wait":
			dip = -0.008 * sin(age * 2.4) - 0.03 * float(s["nibble"])
		"bite":
			dip = -0.07
		"fight":
			var near := Vector3(p.global_position.x, start.y, p.global_position.z)
			var dir := near.direction_to(start)
			near += dir * 1.6
			pos = near.lerp(start, clampf(float(s["dist"]), 0.0, 1.0))
			dip = -0.02 + 0.015 * sin(age * 14.0)
	s["pos"] = pos
	bob.global_position = pos + Vector3(0, dip, 0)
	if ring != null and is_instance_valid(ring):
		var ph := fmod(age, 1.6) / 1.6
		var sc := lerpf(0.4, 2.2, ph) * (1.6 if String(s["state"]) != "wait" else 1.0)
		ring.scale = Vector3(sc, 0.05, sc)
		ring.global_position = pos + Vector3(0, 0.01, 0)
		_ring_mat.albedo_color.a = 0.5 * (1.0 - ph)
	if line != null and is_instance_valid(line):
		var tip := p.global_position + Basis(Vector3.UP, p.yaw) * Vector3(0.3, 1.9, -1.4)
		var im: ImmediateMesh = line.mesh
		im.clear_surfaces()
		im.surface_begin(Mesh.PRIMITIVE_LINES, _line_mat)
		im.surface_add_vertex(tip)
		im.surface_add_vertex(bob.global_position + Vector3(0, 0.12, 0))
		im.surface_end()
