class_name AssetLib
extends RefCounted
## Bezpečné načítání externích assetů (modely, zvuky) z `res://assets/`. Hra musí jít i bez assetu:
## když soubor chybí, funkce vrátí `null` (+ varování) a volající použije procedurální náhradu.
## Každý asset musí být v `assets/LICENSES.md` + `assets/licenses.json` (viz `ASSETY.md`).

const ROOT := "res://assets/"


## Úplná cesta: relativní cesta se doplní o `res://assets/`.
static func _full(path: String) -> String:
	return path if path.begins_with("res://") else ROOT + path


## Existuje asset (i po exportu, kdy je v `.import` / `.remap`)?
static func has(path: String) -> bool:
	return ResourceLoader.exists(_full(path))


## Načte `.glb` / `.gltf` a vrátí novou instanci kořene (`Node3D`), nebo `null`.
static func load_model(path: String) -> Node3D:
	var p := _full(path)
	if not ResourceLoader.exists(p):
		push_warning("AssetLib: model nenalezen: %s" % p)
		return null
	var res: Resource = load(p)
	if res is PackedScene:
		var inst: Node = (res as PackedScene).instantiate()
		if inst is Node3D:
			return inst as Node3D
		if inst != null:
			inst.queue_free()
	push_warning("AssetLib: soubor není 3D scéna: %s" % p)
	return null


## Načte zvuk (`.ogg` / `.wav` / `.mp3`) nebo vrátí `null`.
static func load_sound(path: String) -> AudioStream:
	var p := _full(path)
	if not ResourceLoader.exists(p):
		push_warning("AssetLib: zvuk nenalezen: %s" % p)
		return null
	var res: Resource = load(p)
	if res is AudioStream:
		return res as AudioStream
	push_warning("AssetLib: soubor není zvuk: %s" % p)
	return null
