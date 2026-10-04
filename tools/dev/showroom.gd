## Vývojový showroom: auta a postavy pro kontrolu modelů. Spuštění:
##   godot --path . --script res://tools/dev/showroom.gd -- --out=/tmp/x.png [--cam=x,y,z] [--look=x,y,z]
extends SceneTree

var args := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	await process_frame
	var root3d := Node3D.new()
	root.add_child(root3d)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.6, 0.7, 0.85)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.65, 0.7)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root3d.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	sun.shadow_enabled = true
	root3d.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.35, 0.36, 0.34)
	ground.material_override = gm
	root3d.add_child(ground)
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(60, 1, 60)
	cs.shape = bs
	cs.position.y = -0.5
	sb.add_child(cs)
	root3d.add_child(sb)
	var models := ["octavia", "fabia", "sedan120", "van"]
	var colors := [Color(0.7, 0.08, 0.06), Color(0.15, 0.3, 0.6), Color(0.85, 0.8, 0.6), Color(0.9, 0.9, 0.9)]
	for i in models.size():
		var c := Car.new()
		c.setup(models[i], colors[i], i == 3 and false, "4Z%d 12%d4" % [i, i])
		c.position = Vector3(-7.5 + i * 5.0, 0.1, 0)
		c.rotation.y = 0.5
		root3d.add_child(c)
	var pc := Car.new()
	pc.setup("octavia", Color(0.9, 0.92, 0.95), true, "POLICIE")
	pc.position = Vector3(0, 0.1, 7)
	pc.rotation.y = -2.2
	root3d.add_child(pc)
	var outfits := ["", "police", "hunter", "bartender", "shopkeeper", ""]
	for i in 6:
		var h := Humanoid.new()
		h.outfit = outfits[i]
		h.female = i == 4
		h.hair_style = [0, 3, 1, 1, 2, 0][i]
		h.moustache = i in [0, 3]
		h.beard = i == 2
		h.shirt = [Color(0.85, 0.25, 0.18), Color(0.12, 0.15, 0.3), Color(0.25, 0.32, 0.2), Color(0.95, 0.95, 0.95),
			Color(0.8, 0.4, 0.5), Color(0.3, 0.5, 0.3)][i]
		h.position = Vector3(-4.0 + i * 1.2, 0, 4.5)
		h.rotation.y = PI * 0.9
		root3d.add_child(h)
		if i == 5:
			h.fat = 1.0
			h.drunk = 1.0
		if i == 0:
			h.hold(PropModels.drink_model("pivo"))
			h.start_action("drink")
	var cam := Camera3D.new()
	var cp: PackedStringArray = args.get("cam", "0,3.2,13").split(",")
	var lp: PackedStringArray = args.get("look", "0,0.8,2").split(",")
	cam.position = Vector3(float(cp[0]), float(cp[1]), float(cp[2]))
	root3d.add_child(cam)
	cam.look_at(Vector3(float(lp[0]), float(lp[1]), float(lp[2])))
	cam.fov = float(args.get("fov", "60"))
	cam.current = true
	await create_timer(float(args.get("wait", "2.0"))).timeout
	var img := root.get_texture().get_image()
	img.save_png(args.get("out", "/tmp/showroom.png"))
	print("saved")
	quit()
