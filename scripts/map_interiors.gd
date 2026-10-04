## Mapové interiéry (Fáze 2 upgrade plánu): ručně navržené mapy ve formátu Quake 1 `.map`
## v `data/maps/<místo>.map` (např. hospoda), stavěné za běhu addonem FuncGodot (`addons/func_godot`,
## nástupce Qodotu pro Godot 4.x). Používají se pro veřejné budovy, jejichž nemovitost má `place`
## (interiér je pevný slot v `InteriorStreamer.FIXED`); kde mapa nebo addon chybí, padá se zpět
## na procedurální `PublicInteriors` – hra funguje i bez addonu.
##
## Geometrie a kolize dělá `FuncGodotMap` (worldspawn / func_detail → `StaticBody3D` s konkávní
## kolizí; tělesům se doplní meta `surface = "budova"`, aby fungoval `Player._check_roof`).
## Herní obsah mapy se řídí point entitami s `targetname` (vyrobené jako `Marker3D`):
##   spawn (info_player_start), exit (E „Vyjít ven“), seat_<skupina>_<i> (sedadla `add_seat`),
##   keeper (obsluha `set_keeper`), bar (E „place:<místo>“ – nabídka obsluhy), pipa (`spots["pipa"]`,
##   M3.2 čepování), stul_<i> (`spots["stul:<i>"]`, M3.1 „Uklidit stoly“), lamp_<i> (světlo `lamp`).
## Stavba běží v krocích `Interior.build_step` jako procedurální interiéry: 1. krok geometrie mapy,
## 2. krok značky + okna.
## API: `addon_ok()`, `map_path(místo)`, `has_map(místo)`, `steps(it)`.
class_name MapInteriors
extends RefCounted

const MAP_DIR := "res://data/maps"
const TEXTURE_DIR := "res://assets/textures/interiors"        # textury mapy podle jména stěny
const MAP_SCRIPT := "res://addons/func_godot/src/map/func_godot_map.gd"
const SETTINGS_SCRIPT := "res://addons/func_godot/src/map/func_godot_map_settings.gd"
const FGD_SCRIPT := "res://addons/func_godot/src/fgd/func_godot_fgd_file.gd"
const POINT_SCRIPT := "res://addons/func_godot/src/fgd/func_godot_fgd_point_class.gd"
const BASE_FGD := "res://addons/func_godot/fgd/func_godot_fgd.tres"
## Point entity, ze kterých se stávají herní značky (class → Marker3D).
const MARKERS := ["info_player_start", "sc_exit", "sc_seat", "sc_keeper", "sc_bar", "sc_pipa", "sc_stul", "sc_lamp"]


## Addon FuncGodot je k dispozici (skript mapy jde načíst). GDScript třídy se nekontrolují přes
## `ClassDB.class_exists` (vrací jen engine třídy) – spolehlivá je existence a načtení skriptu.
static func addon_ok() -> bool:
	return ResourceLoader.exists(MAP_SCRIPT) and load(MAP_SCRIPT) != null


static func map_path(place: String) -> String:
	return "%s/%s.map" % [MAP_DIR, place]


## Veřejné místo má mapový interiér: existuje .map a addon je nainstalovaný.
## V exportu leží vedle `.import` (FuncGodot import plugin → QuakeMapFile), source .map tam nemusí být.
static func has_map(place: String) -> bool:
	return addon_ok() and (FileAccess.file_exists(map_path(place))
		or FileAccess.file_exists(map_path(place) + ".import"))


## Kroky stavby pro `Interior.begin_build` – bez mapy / addonu procedurální stavba jako dřív.
static func steps(it: Interior) -> Array:
	if not has_map(it.id):
		push_warning("MapInteriors: „%s“ – chybí .map nebo addon FuncGodot, stavím procedurálně" % it.id)
		return [func() -> void: PublicInteriors.build(it, it.id)]
	return [func() -> void: _geometry(it), func() -> void: _markers(it)]


# ------------------------------------------------------------------ krok 1: geometrie z .map

## Nastavení mapy: měřítko 32 qu = 1 m, textury z `TEXTURE_DIR`, vlastnosti entit ze `targetname`,
## vyrobené materiály neukládat na disk (běh hry). FGD = výchozí definice addonu + naše značky.
static func _settings() -> Resource:
	var s: Resource = load(SETTINGS_SCRIPT).new()
	s.inverse_scale_factor = 32.0
	s.base_texture_dir = TEXTURE_DIR
	s.save_generated_materials = false
	s.entity_name_property = "targetname"
	s.entity_fgd = _fgd()
	return s


static func _fgd() -> Resource:
	var fgd: Resource = load(FGD_SCRIPT).new()
	var base: Resource = load(BASE_FGD)
	if base != null:
		for d in base.entity_definitions:
			var dd: Resource = d.duplicate()
			# occludery malých interiérů nemají smysl (a v headless režimu plodí chyby)
			if "build_occlusion" in dd:
				dd.build_occlusion = false
			fgd.entity_definitions.append(dd)
	var pt: Script = load(POINT_SCRIPT)
	for cn in MARKERS:
		var d: Resource = pt.new()
		d.classname = cn
		d.node_class = "Marker3D"
		d.name_property = "targetname"
		fgd.entity_definitions.append(d)
	return fgd


## Instancuje `FuncGodotMap` (dynamicky – bez addonu se sem kód nedostane), postaví .map
## a doplní meta povrchům a vypnutí stínů (interiéry stíny nevrhají, viz `Interior.flush_mesh`).
## Stavba běží synchronně (`block_until_complete` + `should_set_owners = false` + `verify_and_build`)
## – vejde se do jednoho kroku `Interior.build_step`. Kdyby .map nešla postavit (poškozená apod.),
## interiér se dostaví procedurálně, aby hra neskončila s prázdnou místností.
static func _geometry(it: Interior) -> void:
	var scr: Script = load(MAP_SCRIPT)
	if scr == null:
		return
	var map: Node3D = scr.new()
	map.name = "Mapa"
	map.local_map_file = map_path(it.id)
	map.map_settings = _settings()
	it.add_child(map)
	map.block_until_complete = true        # mezikroky buildu bez čekání na snímek (jeden build_step)
	map.should_set_owners = false          # runtime stavba – vlastníky neřešíme
	map.verify_and_build()
	if map.find_children("*", "MeshInstance3D", true, false).is_empty():
		push_warning("MapInteriors: „%s.map“ se nepodařilo postavit – procedurální interiér" % it.id)
		it.remove_child(map)
		map.queue_free()
		PublicInteriors.build(it, it.id)
		return
	for b in map.find_children("*", "StaticBody3D", true, false):
		(b as StaticBody3D).set_meta("surface", "budova")
	for m in map.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ------------------------------------------------------------------ krok 2: značky a doplňky

## Přečte Marker3D značky z postavené mapy a převede je na herní obsah interiéru (E-objekty,
## sedadla, obsluha, pracovní `spots`, lampy) + okna jako u procedurálních interiérů.
static func _markers(it: Interior) -> void:
	var map := it.get_node_or_null("Mapa")
	if map == null:
		return
	var pl: Place = it.world.places.get(it.id) if it.world else null
	if pl:
		it.title = String(pl.data.get("name", it.id))
	var kn := "Obsluha"
	if pl and pl.keeper:
		kn = pl.keeper.display_name
	var seat_pos := {}                # skupina → {index: [pozice, yaw]} – pořadí podle indexu z targetname
	var lamps := 0
	for n in map.get_children():
		if not n is Node3D or not String(n.name).begins_with("entity_"):
			continue
		var mid := String(n.name).substr(7)
		var p := (n as Node3D).position
		var yaw := wrapf((n as Node3D).rotation.y, -PI, PI)   # angle 180 → yaw 2π ≈ 0 – držet rozsah ±π
		if mid == "spawn":                                            # info_player_start u dveří
			it.inside_door = it.to_global(p)
			it.inside_yaw = yaw
		elif mid == "exit":
			it.add_object(p, 1.5, "exit", "Vyjít ven")
		elif mid.begins_with("seat_"):                                # seat_<skupina>_<index>
			var pt2 := mid.split("_")
			if pt2.size() >= 3:
				if not seat_pos.has(pt2[1]):
					seat_pos[pt2[1]] = {}
				seat_pos[pt2[1]][int(pt2[2])] = [p, yaw]
		elif mid == "keeper":
			it.set_keeper(p, yaw)
		elif mid == "bar":
			it.add_object(p, 2.6, "place:%s" % it.id, "%s – %s" % [kn, "výčep" if it.id == "hospoda" else "pult"])
		elif mid == "pipa":
			it.spots["pipa"] = [it.to_global(p), yaw]
		elif mid.begins_with("stul_"):
			it.spots["stul:%s" % mid.split("_")[1]] = [it.to_global(p), yaw]
		elif mid.begins_with("lamp_"):
			it.lamp(p, 5.5)
			lamps += 1
	for g in seat_pos:                                                # sedadla v pořadí indexů
		var idx: Array = seat_pos[g].keys()
		idx.sort()
		for i in idx:
			it.add_seat(g, seat_pos[g][i][0], seat_pos[g][i][1])
	# pojistky pro mapu bez značek – hráč a E-východ nesmí zůstat na počátku interiéru
	if it.inside_door == Vector3.ZERO:
		it.inside_door = it.to_global(Vector3(0.0, 0.1, 2.5))
		it.inside_yaw = 0.0
	var has_exit := false
	for o in it.objects:
		if String(o["key"]) == "exit":
			has_exit = true
	if not has_exit:
		it.add_object(Vector3(0.0, 0.0, 3.4), 1.5, "exit", "Vyjít ven")
	if lamps == 0:
		it.lamp(Vector3(0.0, 2.4, 0.0), 6.5)
	# okna (sklo jako u procedurální hospody; stěny mapy: z −4 / +4, x −5 / +5)
	it.window("S", -3.0, 4.0)
	it.window("S", 3.0, 4.0)
	it.window("W", -1.5, -5.0)
	it.window("W", 1.5, -5.0)
	it.window("N", -2.0, -4.0)
