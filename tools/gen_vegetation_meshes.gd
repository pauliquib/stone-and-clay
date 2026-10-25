## Generátor low-poly modelů vegetace (Fáze 9 – §9): ukládá ArrayMesh do `assets/models/vegetation/*.res`.
## Patka v počátku (y = 0), UV.y = poměrná výška vrcholu (0 u země, 1 na špičce) – shader `shaders/vegetation.gdshader`
## podle ní ohýbá rostlinu větrem.
##
## 2026-10: všechny modely staví `GroundVegMeshes` (scripts/vegetation/ground_veg_meshes.gd) – geometrická stébla
## a listy, karty listí / kapradí / květů s procedurálním výřezem ve shaderu, barvy vrcholů podle 00_PRINCIPY kap. 4
## (albedo z `VegetationManager.VEG_CONFIG`). Bez .res je hra postaví sama (stejný deterministický kód); .res jen
## zrychlí načtení. Louční květ (`meadow_flower`) si `MeadowFlowers` staví vždy sám.
##
## Spuštění:  godot --headless --path . --script tools/gen_vegetation_meshes.gd
## Po změně tvarů v GroundVegMeshes znovu spustit a .res commitnout (jinak hra načte staré tvary).
extends SceneTree

const OUT := "res://assets/models/vegetation/"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for id in GroundVegMeshes.IDS:
		if String(id) == "meadow_flower":
			continue
		var m := GroundVegMeshes.build(String(id))
		var err := ResourceSaver.save(m, OUT + String(id) + ".res")
		print("  %s.res: %d tris → %s" % [id, m.surface_get_array_index_len(0) / 3 if m.get_surface_count() > 0 else 0,
			error_string(err)])
	print("gen_vegetation_meshes: hotovo → %s" % OUT)
	quit(0)
