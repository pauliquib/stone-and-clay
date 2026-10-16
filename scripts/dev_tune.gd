## M8.D: registr laditelných parametrů herních algoritmů („Menu pro vývojáře“, F3 v Režimu vývojáře).
##
## Statický registr (jako `GameSettings.realism_saved` / `MayorOffice.road_grip_bonus` – bez drátování referencí):
## každý parametr má `id` tečkově podle systému (`car.brake_decel`, `wind.gust_strength`), skupinu
## „Kategorie/Podskupina“ (dvouúrovňové menu, kategorie viz `CATEGORIES`), popisek, výchozí hodnotu z kódu,
## rozsah posuvníku, krok, nápovědu a jednotku. Typ se řídí výchozí hodnotou: `float` / `int` = posuvník
## + číselné pole, `bool` = zaškrtávátko, `Array` řetězců (+ volitelně int = výchozí index) = volba (hodnota = index).
##
## Pořadí hodnot při startu: výchozí v kódu → `res://config.json` (nové výchozí projektu, jde do gitu; v exportované
## hře i `config.json` vedle spustitelného souboru) → `user://ladeni.cfg` (Uložit v menu, jen tento počítač;
## automatické testy a snímky ho ignorují). Neznámé klíče v souborech se ignorují s varováním, chybějící = výchozí.
##
## **Výkon:** v hot cestách se registr nikdy nečte za snímek. Buď parametr rovnou propojíš s proměnnou
## (`tune(cíl, vlastnost, …)` – registr do ní zapíše při startu i při každé změně; cíl = objekt, skript se
## `static var`, Dictionary nebo Array), nebo si hodnotu držíš sám a obnovíš ji v handleru `hub().changed`.
## Registr sám nic nedělá za snímek, Režim vývojáře jen odemyká menu – vypnutý = nulová cena navíc.
##
## Kam registraci dát (souběžná práce víc agentů bez kolizí): `scripts/dev/tune_<kategorie>.gd` se
## `static func register_all()` – registr všechny takové soubory najde sám (`REGISTRARS_DIR`), žádný centrální
## seznam. Systém s instancí ve `World` smí `tune(self, …)` volat i sám ve své stavbě. Návod: `docs/DEV.md`.
class_name DevTune
extends RefCounted

## Změna hodnoty parametru (z menu, resetu, načtení). Připojuj přes `DevTune.hub().changed.connect(…)`.
signal changed(id: String, value: Variant)

## Pořadí hlavních kategorií v menu (kap. 3.3 zadání M8.D); neznámá kategorie se přidá na konec.
const CATEGORIES := ["Svět", "Vozidla", "Létání", "Člověk", "Činnosti", "Příroda", "Zvěř"]
const USER_PATH := "user://ladeni.cfg"
const USER_SECTION := "parametry"
const ROOT_PATH := "res://config.json"
const ROOT_NAME := "config.json"
const FILE_VERSION := 1
const REGISTRARS_DIR := "res://scripts/dev/"
const REGISTRAR_PREFIX := "tune_"


## Jeden parametr registru.
class Param:
	var id := ""
	var group := ""                  # "Kategorie/Podskupina"
	var label := ""
	var help := ""
	var unit := ""
	var kind := "float"              # float / int / bool / choice
	var options: Array = []          # popisky voleb (kind == "choice")
	var default: Variant             # výchozí hodnota v kódu
	var base: Variant                # výchozí po `config.json` (k ní vrací ↺, od ní se počítá „změněno“)
	var value: Variant               # aktuální hodnota
	var lo := 0.0
	var hi := 1.0
	var step := 0.01
	var links: Array = []            # [cíl (WeakRef | Dictionary | Array), vlastnost / klíč / index]


static var _hub: DevTune
static var _params := {}             # id → Param
static var _order: Array[String] = []
static var _root_vals := {}          # id → hodnota z config.json
static var _user_vals := {}          # id → hodnota z ladeni.cfg
static var _ready_done := false
static var _warned := false
static var export_note := ""         # kam naposledy zapsal export (pro hlášku v menu)


# ------------------------------------------------------------------ start

## Singleton se signálem `changed` (statické signály GDScript 4.3 nemá). Zavolá `ensure()`.
static func hub() -> DevTune:
	if _hub == null:
		_hub = DevTune.new()
	ensure()
	return _hub


## Jednou za běh: načte `config.json` a `ladeni.cfg` a spustí všechny `scripts/dev/tune_*.gd` (`register_all`).
## Volá ho `Main._ready` před stavbou světa; jinak se spustí sám při prvním dotazu.
static func ensure() -> void:
	if _ready_done:
		return
	_ready_done = true
	if _hub == null:
		_hub = DevTune.new()
	load_all()
	for path in _registrar_paths():
		var s: Script = load(path)
		if s == null:
			push_warning("DevTune: registraci %s nejde načíst" % path)
			continue
		s.call("register_all")
		# volitelný handler změn registrace (`static func on_changed(id, value)`) – připojí registr
		for m in s.get_script_method_list():
			if String(m.get("name", "")) == "on_changed":
				_hub.changed.connect(Callable(s, "on_changed"))
				break


static func _registrar_paths() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(REGISTRARS_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		var n := f.trim_suffix(".remap")           # exportovaná hra: soubory skriptů mají .remap / .gdc
		if n.ends_with(".gdc"):
			n = n.trim_suffix(".gdc") + ".gd"
		if n.begins_with(REGISTRAR_PREFIX) and n.ends_with(".gd") and not out.has(REGISTRARS_DIR + n):
			out.append(REGISTRARS_DIR + n)
	out.sort()
	return out


## Načte hodnoty ze souborů (bez registrace). `ladeni.cfg` jen mimo automatické běhy (--…test, --shot).
static func load_all() -> void:
	_root_vals.clear()
	_user_vals.clear()
	for path in _root_paths():
		_read_json(path)
	if not _automated():
		var cf := ConfigFile.new()
		if cf.load(USER_PATH) == OK and cf.has_section(USER_SECTION):
			for k in cf.get_section_keys(USER_SECTION):
				_user_vals[k] = cf.get_value(USER_SECTION, k)
	# parametry už zaregistrované (opakované načtení) – přepočítat
	for id in _order:
		var p: Param = _params[id]
		p.base = _coerce(p, _root_vals.get(id, p.default))
		_apply(p, _coerce(p, _user_vals.get(id, p.base)))


static func _root_paths() -> Array[String]:
	var out: Array[String] = [ROOT_PATH]
	if OS.has_feature("template"):                 # exportovaná hra: res:// jen pro čtení → vedle .exe
		out.append(OS.get_executable_path().get_base_dir().path_join(ROOT_NAME))
	return out


static func _read_json(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (data is Dictionary) or not (data.get("parametry") is Dictionary):
		push_warning("DevTune: %s nemá tvar {\"verze\": 1, \"parametry\": {…}} – ignoruji" % path)
		return
	var vals: Dictionary = data["parametry"]
	for k in vals:
		_root_vals[String(k)] = vals[k]


static func _automated() -> bool:
	for a in OS.get_cmdline_user_args():
		var k := a.trim_prefix("--").split("=", true, 1)[0]
		if k == "shot" or k.ends_with("test"):
			return true
	return false


# ------------------------------------------------------------------ registrace

## Zaregistruje parametr a vrátí jeho aktuální hodnotu (výchozí → config.json → ladeni.cfg).
## Opakovaná registrace stejného `id` nic nepřepíše (jen vrátí hodnotu) – stejné id ze dvou míst = chyba návrhu.
## Volba: `default` = Array popisků a volitelně int výchozího indexu (`["Nízká", "Střední", "Vysoká", 1]`).
static func register(id: String, group: String, label: String, default: Variant, lo := 0.0, hi := 1.0,
		step := 0.01, help := "", unit := "") -> Variant:
	ensure()
	if _params.has(id):
		return (_params[id] as Param).value
	var p := Param.new()
	p.id = id
	p.group = group
	p.label = label
	p.help = help
	p.unit = unit
	p.lo = lo
	p.hi = hi
	p.step = step
	match typeof(default):
		TYPE_BOOL:
			p.kind = "bool"
		TYPE_INT:
			p.kind = "int"
			p.step = maxf(roundf(step), 1.0)
		TYPE_ARRAY:
			p.kind = "choice"
			var idx := 0
			for o in default:
				if o is int:
					idx = o
				else:
					p.options.append(String(o))
			default = idx
			p.lo = 0.0
			p.hi = float(maxi(p.options.size() - 1, 0))
			p.step = 1.0
		_:
			p.kind = "float"
			default = float(default)
	p.default = default
	p.base = _coerce(p, _root_vals.get(id, default))
	p.value = _coerce(p, _user_vals.get(id, p.base))
	_params[id] = p
	_order.append(id)
	return p.value


## Zaregistruje parametr propojený s proměnnou: výchozí hodnota = současná hodnota `target[prop]` (dnešní
## konstanta – jediný zdroj výchozí hodnoty zůstává v kódu systému) a registr do ní zapíše aktuální hodnotu
## hned i při každé změně. `target`: objekt (instance, Tune objekt), skript (`Car` → `static var`), Dictionary
## nebo Array (`prop` = klíč / index). Už registrované `id` se jen propojí s dalším cílem (nová instance systému).
static func tune(target: Variant, prop: Variant, id: String, group: String, label: String, lo := 0.0, hi := 1.0,
		step := 0.01, help := "", unit := "") -> void:
	if not _params.has(id):
		var def: Variant = _read(target, prop)
		if def == null:
			push_error("DevTune.tune: %s nemá vlastnost / klíč %s (id %s)" % [str(target), str(prop), id])
			return
		register(id, group, label, def, lo, hi, step, help, unit)
	link(id, target, prop)


## Propojí už zaregistrovaný parametr s další proměnnou a hned do ní zapíše aktuální hodnotu.
static func link(id: String, target: Variant, prop: Variant) -> void:
	var p: Param = _params.get(id)
	if p == null:
		push_error("DevTune.link: neznámý parametr %s" % id)
		return
	var ref: Variant = target
	if target is Object:
		ref = weakref(target)
	p.links.append([ref, prop])
	_write(ref, prop, p.value)


static func _read(target: Variant, prop: Variant) -> Variant:
	if target is Dictionary:
		return (target as Dictionary).get(prop)
	if target is Array:
		var a: Array = target
		return a[int(prop)] if int(prop) >= 0 and int(prop) < a.size() else null
	if target is Object:
		return (target as Object).get(StringName(prop))
	return null


static func _write(ref: Variant, prop: Variant, v: Variant) -> bool:
	if ref is WeakRef:
		var o: Object = (ref as WeakRef).get_ref()
		if o == null:
			return false
		o.set(StringName(prop), v)
	elif ref is Dictionary:
		(ref as Dictionary)[prop] = v
	elif ref is Array:
		var a: Array = ref
		if int(prop) >= 0 and int(prop) < a.size():
			a[int(prop)] = v
	return true


static func _coerce(p: Param, v: Variant) -> Variant:
	match p.kind:
		"bool":
			return bool(v)
		"int":
			return int(roundf(float(v)))
		"choice":
			return clampi(int(roundf(float(v))), 0, maxi(p.options.size() - 1, 0))
	return float(v)


static func _same(p: Param, a: Variant, b: Variant) -> bool:
	if p.kind == "float":
		return is_equal_approx(float(a), float(b))
	return a == b


# ------------------------------------------------------------------ čtení a změny

static func has(id: String) -> bool:
	return _params.has(id)


## Aktuální hodnota (mimo hot cesty – za snímek čti svou proměnnou propojenou přes `tune` / `changed`).
static func value(id: String, fallback: Variant = null) -> Variant:
	ensure()
	var p: Param = _params.get(id)
	return p.value if p != null else fallback


static func set_value(id: String, v: Variant) -> void:
	var p: Param = _params.get(id)
	if p == null:
		push_warning("DevTune.set_value: neznámý parametr %s" % id)
		return
	var nv: Variant = _coerce(p, v)
	if _same(p, nv, p.value):
		return
	_apply(p, nv)


static func _apply(p: Param, nv: Variant) -> void:
	var changed_now := not _same(p, nv, p.value)
	p.value = nv
	var alive: Array = []
	for l in p.links:
		if _write(l[0], l[1], nv):
			alive.append(l)
	p.links = alive
	if changed_now and _hub != null:
		_hub.changed.emit(p.id, nv)


## Vrátí parametr na výchozí hodnotu (z kódu, případně z `config.json`).
static func reset(id: String) -> void:
	var p: Param = _params.get(id)
	if p != null:
		set_value(id, p.base)


## Výchozí pro celou kategorii („Vozidla“) nebo podskupinu („Vozidla/Auto“).
static func reset_group(group: String) -> void:
	for id in ids(group):
		reset(id)


static func reset_all() -> void:
	for id in _order:
		reset(id)


static func is_changed(id: String) -> bool:
	var p: Param = _params.get(id)
	return p != null and not _same(p, p.value, p.base)


## Liší se aktuální hodnota od výchozí v kódu (i kvůli config.json)? Pro systémy, které hodnotu uplatní
## jen při změně (Engine, PhysicsServer) – při startu stačí sáhnout na engine jen tehdy.
static func differs_from_code(id: String) -> bool:
	var p: Param = _params.get(id)
	return p != null and not _same(p, p.value, p.default)


## Parametr jako slovník pro menu: id, group, label, help, unit, kind, options, default, base, value, lo, hi, step.
static func info(id: String) -> Dictionary:
	var p: Param = _params.get(id)
	if p == null:
		return {}
	return {"id": p.id, "group": p.group, "label": p.label, "help": p.help, "unit": p.unit, "kind": p.kind,
		"options": p.options, "default": p.default, "base": p.base, "value": p.value, "lo": p.lo, "hi": p.hi,
		"step": p.step}


## Id parametrů v pořadí registrace; `group` = kategorie („Vozidla“) nebo podskupina („Vozidla/Auto“), "" = vše.
static func ids(group := "") -> Array[String]:
	ensure()
	var out: Array[String] = []
	for id in _order:
		var g: String = (_params[id] as Param).group
		if group == "" or g == group or g.begins_with(group + "/"):
			out.append(id)
	return out


## Strom skupin pro menu: [[kategorie, [podskupina, …]], …] v pořadí `CATEGORIES`, pak neznámé.
static func groups() -> Array:
	ensure()
	var subs := {}
	var cats: Array[String] = []
	for id in _order:
		var g: String = (_params[id] as Param).group
		var parts := g.split("/", true, 1)
		var cat: String = parts[0]
		var sub: String = parts[1] if parts.size() > 1 else ""
		if not subs.has(cat):
			subs[cat] = []
			cats.append(cat)
		if sub != "" and not (subs[cat] as Array).has(sub):
			(subs[cat] as Array).append(sub)
	var out: Array = []
	for c in CATEGORIES:
		if subs.has(c):
			out.append([c, subs[c]])
	for c in cats:
		if not CATEGORIES.has(c):
			out.append([c, subs[c]])
	return out


## Kolik parametrů je zaregistrováno ve skupině (bez argumentu celkem).
static func count(group := "") -> int:
	return ids(group).size()


## Varování na klíče ze souborů, které nikdo nezaregistroval (překlep, smazaný parametr) – jednou za běh.
## Volá menu při prvním otevření (to už jsou postavené i systémy, které registrují až ve své stavbě).
static func warn_unknown() -> void:
	if _warned:
		return
	_warned = true
	for k in _root_vals:
		if not _params.has(k):
			push_warning("DevTune: config.json – neznámý parametr %s (ignoruji)" % k)
	for k in _user_vals:
		if not _params.has(k):
			push_warning("DevTune: ladeni.cfg – neznámý parametr %s (ignoruji)" % k)


# ------------------------------------------------------------------ ukládání

## Uloží hodnoty odlišné od výchozích (po config.json) do `user://ladeni.cfg`. Neznámé klíče ze starého
## souboru zachová (parametr systému, který se tentokrát nezaregistroval).
static func save_user() -> bool:
	var cf := ConfigFile.new()
	for k in _user_vals:
		if not _params.has(k):
			cf.set_value(USER_SECTION, k, _user_vals[k])
	for id in _order:
		var p: Param = _params[id]
		if not _same(p, p.value, p.base):
			cf.set_value(USER_SECTION, id, p.value)
	_user_vals.clear()
	if cf.has_section(USER_SECTION):
		for k in cf.get_section_keys(USER_SECTION):
			_user_vals[k] = cf.get_value(USER_SECTION, k)
	return cf.save(USER_PATH) == OK


## Zapíše `config.json` (kořen projektu; v exportované hře vedle spustitelného souboru): jen hodnoty odlišné
## od výchozích v kódu, seřazené podle klíče. Aktuální hodnoty se tím stanou novými výchozími (↺, zvýraznění).
## Vrací cestu, kam zapsal, nebo "" při chybě.
static func export_root() -> String:
	var path := ROOT_PATH
	if OS.has_feature("template"):
		path = OS.get_executable_path().get_base_dir().path_join(ROOT_NAME)
	var vals := {}
	for k in _root_vals:
		if not _params.has(k):
			vals[k] = _root_vals[k]                    # parametr nezaregistrovaného systému nemazat
	for id in _order:
		var p: Param = _params[id]
		if not _same(p, p.value, p.default):
			vals[id] = p.value
	var keys := vals.keys()
	keys.sort()
	var sorted := {}
	for k in keys:
		sorted[k] = vals[k]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		export_note = ""
		return ""
	f.store_string(JSON.stringify({"verze": FILE_VERSION, "parametry": sorted}, "\t", true) + "\n")
	f.close()
	_root_vals = sorted
	for id in _order:
		var p: Param = _params[id]
		p.base = _coerce(p, _root_vals.get(id, p.default))
	export_note = ProjectSettings.globalize_path(path)
	return export_note
