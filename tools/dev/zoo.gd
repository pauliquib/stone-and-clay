## Zoo – náhled všech modelů zvířat pro úpravy (AnimalSpecs, Bird.SPECIES). Spuštění:
##   godot --path . --script res://tools/dev/zoo.gd -- --out=zoo.png [--anim=stand|walk|trot|canter|gallop|graze|lie|alert|situp|root]
##        [--only=srnec,kun] [--cam=x,y,z] [--look=x,y,z] [--wait=s] [--slope=stupně]
##   godot --path . --script res://tools/dev/zoo.gd -- --series=adresář   (8 snímků: pózy, chody, detaily)
## --slope nakloní zem a zapne IK chodidel, --anim=situp posed „panáček“ zajíce, --anim=root rytí.
## Bez --out zůstane okno otevřené (myš: nic, jen se kouká; Esc zavře).
## V řadě: srnec (srna), srnec (samec), srnec v zimní srsti, divočák (bachyně), kňour, sele, zajíc,
## kůň se sedlem a jezdcem; nad nimi ptáci (vrána, šedá vrána, kos, kosice, vlaštovka, káně).
extends SceneTree

var args := {}
var rigs: Array = []
var anim := "walk"
var t := 0.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	anim = args.get("anim", "walk")
	await process_frame
	var root3d := Node3D.new()
	root.add_child(root3d)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.72, 0.86)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.66, 0.72)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root3d.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.shadow_enabled = true
	root3d.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.36, 0.42, 0.28)
	ground.material_override = gm
	root3d.add_child(ground)
	# --slope=stupně: nakloní zem a zapne IK chodidel (výška terénu = z * tan)
	var slope := deg_to_rad(float(args.get("slope", "0")))
	ground.rotation.x = slope

	var only: PackedStringArray = String(args.get("only", "")).split(",", false)
	var defs := [
		["srnec", {"male": false}, "Srna"],
		["srnec", {"male": true}, "Srnec"],
		["srnec", {"male": false, "winter": true}, "Srna – zimní srst"],
		["divocak", {"male": false}, "Bachyně"],
		["divocak", {"male": true}, "Kňour"],
		["sele", {}, "Sele"],
		["zajic", {}, "Zajíc"],
		["kun", {}, "Kůň"],
	]
	var x := -9.0
	for d in defs:
		if not only.is_empty() and not (d[0] in only):
			continue
		var spec := AnimalSpecs.get_spec(d[0])
		var rig := QuadrupedModel.build(spec, d[1])
		rig.position = Vector3(x, 0, 0)
		if slope != 0.0:
			rig.ground_fn = func(px: float, pz: float) -> float: return -pz * tan(slope)
		rig.rotation.y = 0.6
		root3d.add_child(rig)
		rigs.append(rig)
		_label(root3d, d[2], Vector3(x, float(spec["withers"]) + 0.6, 0))
		if spec.get("tack", false):
			_rider(rig)
		x += maxf(float(spec["length"]) * 1.6, 1.4) + 0.6
	# ptáci na bidýlku a v letu
	var bx := -6.0
	for id in Bird.SPECIES:
		if not only.is_empty() and not (id in only):
			continue
		for fly in [false, true]:
			var b := Bird.new()
			b.species = id
			b.spec = Bird.SPECIES[id]
			b.position = Vector3(bx, 2.5 if fly else 1.2, -3.0)
			b.state = "fly" if fly else "perch"
			b.yaw = 0.8
			root3d.add_child(b)
			bx += float(Bird.SPECIES[id]["span"]) + 0.6
		_label(root3d, Bird.SPECIES[id]["name"], Vector3(bx - float(Bird.SPECIES[id]["span"]) - 0.9, 3.4, -3.0))
	var cam := Camera3D.new()
	root3d.add_child(cam)
	var cp := _vec(args.get("cam", "0,4.5,12"))
	var lk := _vec(args.get("look", "0,0.8,0"))
	cam.look_at_from_position(cp, lk)
	cam.current = true
	if args.has("series"):
		# celá série snímků v jednom běhu: --series=adresář
		var dir: String = args["series"]
		var shots := [["stand", "0,4.5,13", "0,0.8,0"], ["walk", "0,4.5,13", "0,0.8,0"], ["gallop", "0,4.5,13", "0,0.8,0"],
			["graze", "0,4.5,13", "0,0.8,0"], ["lie", "0,4.5,13", "0,0.8,0"],
			["walk", "-4,1.6,4.5", "-6.5,0.6,0"], ["trot", "3,2.4,5.5", "5.5,1.3,0"], ["stand", "-0.5,2.4,4.5", "-0.5,1.9,-3"]]
		var names := ["stoji", "krok", "trysk", "pastva", "lezi", "detail_srnci", "detail_kun", "ptaci"]
		for i in shots.size():
			anim = shots[i][0]
			for r in rigs:
				(r as QuadrupedRig).graze = 0.0
				(r as QuadrupedRig).lie = 0.0
			cam.look_at_from_position(_vec(shots[i][1]), _vec(shots[i][2]))
			await create_timer(1.3).timeout
			root.get_viewport().get_texture().get_image().save_png("%s/zoo_%s.png" % [dir, names[i]])
		print("ZOO série uložena do ", dir)
		quit()
	elif args.has("out"):
		await create_timer(float(args.get("wait", "2.5"))).timeout
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(args["out"])
		print("ZOO saved ", args["out"])
		quit()


func _process(delta: float) -> bool:
	t += delta
	for r in rigs:
		var rig: QuadrupedRig = r
		var g: Dictionary = rig.spec["gaits"]
		match anim:
			"walk": rig.speed = float(g["walk"]) * 0.8
			"trot": rig.speed = (float(g["walk"]) + float(g["trot"])) * 0.5
			"canter": rig.speed = (float(g["trot"]) + float(g["canter"])) * 0.5
			"gallop": rig.speed = float(g["gallop"]) * 0.8
			"graze": rig.graze = 1.0
			"lie": rig.lie = 1.0
			"alert": rig.alert = 1.0
			"situp": rig.sit = 1.0
			"root":
				rig.graze = 1.0
				rig.rooting = true
			_: rig.speed = 0.0
		rig.animate(delta)
	if Input.is_key_pressed(KEY_ESCAPE):
		quit()
	return false


func _rider(rig: QuadrupedRig) -> void:
	var h := Humanoid.new()
	h.shirt = Color(0.85, 0.25, 0.18)
	h.pants = Color(0.16, 0.22, 0.36)
	rig.saddle.add_child(h)
	h.pose = "ride"
	var st: Vector3 = rig.ride["stirrup"]
	var hands: Vector3 = rig.ride["hands"]
	var hips := 0.5
	h.position = Vector3(0, -hips + 0.02, -0.02)
	var drop := st.y - (h.position.y + hips - 0.03)
	var spread := atan2(st.x - 0.093, -drop)
	var reach := Vector2(st.x - 0.093, drop).length()
	var fy := hips - 0.03 - reach
	h.ride = {"hips": hips, "lean": 0.15, "spread": spread, "hands": [hands - h.position],
		"feet": [Vector3(0, fy, st.z - h.position.z), Vector3(0, fy, st.z - h.position.z)]}


func _label(parent: Node3D, text: String, pos: Vector3) -> void:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 36
	l.outline_size = 8
	parent.add_child(l)


func _vec(s: String) -> Vector3:
	var p := s.split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2]))
