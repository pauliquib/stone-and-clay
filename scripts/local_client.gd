## Lokální klient – vše, co patří hráči u tohoto počítače (v MP poběží u každého hráče zvlášť):
## vstup (klávesnice, myš, ovladač → InputState hráče; akce E/F/L/B/R/H/U → World; T/Enter rozhovor;
## F5/F9 rychlé uložení / načtení – SaveGame), HUD a nabídky míst a noclehů, kamera (Player.make_local, kamera auta), obrazovkové efekty (DrunkFx, okno), zvuky,
## obloha, světlo, počasí a roční období (Atmosphere), značka cíle úkolu, mapa (M) a nápověda (F1) v HUD,
## snímky obrazovky.
## Stav světa jen čte z `world`; měnit ho smí jen přes akce World (enter_car, buy, sleep…).
class_name LocalClient
extends Node

var world: World
var args := {}
var player: Player               # hráč ovládaný tímto klientem
var pid := 0
var hud: Hud
var sfx: Sfx
var fx: DrunkFx
var env: Environment
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var atmosphere: Atmosphere
var chimney_smoke: ChimneySmoke   # kouř z komínů podle teploty (M1.3)
var season_fx: SeasonFx           # pole podle kalendáře, květy v trávě, ovoce a padané listí
var game_menu: GameMenu          # F2 – roční období, čas, počasí, vozidla, teleport
var pause_menu: PauseMenu        # Esc – pauza, uložit / načíst, nastavení, ovládání, ukončit
var radio_view: RadioView        # E u rádia – přiblížení a točení knoflíky
var settings := GameSettings.new()
var beacon: Node3D
var ready_done := false
var _beacon_mat: StandardMaterial3D
var _step_dist := 0.0
var _brook: AudioStreamPlayer3D   # šumění nejbližšího potoka
var _water_t := 0.0
var _water_name := ""
var _track_side := 1.0            # střídavě levá / pravá noha (stopy ve sněhu kreslí World.tracks)
# M6.2: ladicí volná kamera (F2 → Teleport → Ladění) – kontrola krajiny za katastrem z výšky.
var flight_hud: FlightHud           # M6.3: letové přístroje (vlastní panel pod Hud, vzor droního OSD)
var freecam: Camera3D
var _fc_prev_cam: Camera3D        # kamera aktivní před volnou kamerou (hráč / auto / dron)
const FREECAM_SPEED := 60.0       # rychlost letu volné kamery (m/s)
const FREECAM_SPRINT := 240.0     # se Shift
const FREECAM_ALT := 500.0        # startovní výška nad hráčem (m)


func _ready() -> void:
	# vstup se musí zapsat do InputState dřív, než ho hráč / auto ve fyzikálním kroku přečte
	process_physics_priority = -100
	hud = Hud.new()
	hud.game = world
	add_child(hud)
	sfx = Sfx.new()
	add_child(sfx)
	flight_hud = FlightHud.new()       # M6.3: přístroje letouna (ALT/AGL/IAS/vario + pípání termiky)
	flight_hud.name = "LetovePristroje"
	add_child(flight_hud)
	flight_hud.setup(hud, sfx)


## Připojí klienta k hráči ve světě: kamera, HUD, efekty, zvuky, registrace ve World.
func attach(p: Player) -> void:
	player = p
	pid = p.id
	p.make_local()
	hud.meta = world.meta
	atmosphere.north_deg = float(world.meta.get("north_angle_deg", 78.37))
	hud.items_root = world.items_root
	hud.totals = world.item_totals
	hud.player = p
	fx = DrunkFx.new()
	fx.body = p.body
	add_child(fx)
	_make_beacon()
	world.register_client(pid, self)
	game_menu = GameMenu.new(self)
	# uživatelské nastavení (automatické testy a snímky jedou s výchozím, ať jsou výsledky stejné)
	settings.vsync_from_args = args.has("vsync") or args.has("novsync")
	settings.maxfps_from_args = args.has("maxfps")
	if not is_automated():
		settings.load_file()
	radio_view = RadioView.new(self)
	radio_view.name = "RadioZblizka"
	add_child(radio_view)
	pause_menu = PauseMenu.new(self)
	pause_menu.name = "Pauza"
	add_child(pause_menu)
	season_fx = SeasonFx.new()
	season_fx.name = "Sezona"
	add_child(season_fx)
	season_fx.setup(world, p)
	chimney_smoke = ChimneySmoke.new()
	chimney_smoke.name = "KourZKominu"
	add_child(chimney_smoke)
	chimney_smoke.setup(world, p)
	settings.apply(self)               # po SeasonFx (vegetace) a se světem hotovým (dohlednost)
	world.sound.connect(_on_world_sound)
	p.jumped.connect(func(): sfx.play("jump", randf_range(0.95, 1.08), -4.0))
	p.landed.connect(func(impact: float): sfx.play("land", randf_range(0.8, 1.0), clampf(impact - 8.0, -8.0, 4.0)))
	# ladicí parametry pohledu
	if args.has("pitch"):
		p.pitch = deg_to_rad(float(args["pitch"]))
	if args.get("view", "") == "fp":
		p.first_person = true
		p.visual.set_first_person(true)
	if args.has("zoom"):
		p._zoom = float(args["zoom"])
		p._arm_len = p._zoom


## Běh bez hráče u klávesnice (--shot, --…test) – bez uloženého nastavení a bez pauzy při ztrátě fokusu.
func is_automated() -> bool:
	for k in args:
		if k == "shot" or String(k).ends_with("test"):
			return true
	return false


func play_sfx(name_: String, pitch := 1.0, vol := 0.0) -> void:
	sfx.play(name_, pitch, vol)


func _on_world_sound(pos: Vector3, name_: String, pitch: float, vol: float, max_dist: float) -> void:
	if player and player.global_position.distance_to(pos) < max_dist:
		sfx.play(name_, pitch, vol)


func blackout_fx(dur: float) -> void:
	var tw := create_tween()
	tw.tween_property(fx, "blackout", 1.0, dur * 0.4)
	tw.tween_interval(dur * 0.3)
	tw.tween_property(fx, "blackout", 0.0, dur * 0.3)


# ------------------------------------------------------------------ prostředí a denní doba

func build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.8, 0.9)
	env.fog_density = 0.00022
	env.fog_aerial_perspective = 0.5
	env.fog_sky_affect = 0.0
	env.glow_enabled = true
	env.glow_intensity = 0.25
	env.glow_bloom = 0.02
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.name = "Slunce"
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 240.0
	sun.directional_shadow_blend_splits = true
	sun.shadow_blur = 1.2
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.name = "Mesic"
	moon.rotation_degrees = Vector3(-55, 140, 0)
	moon.light_color = Color(0.55, 0.65, 0.9)
	moon.light_energy = 0.0
	moon.shadow_enabled = false
	add_child(moon)
	# obloha (Sky), slunce, měsíc, počasí a roční období řídí Atmosphere
	atmosphere = Atmosphere.new()
	atmosphere.name = "Atmosfera"
	add_child(atmosphere)
	atmosphere.setup(world.clock, world.weather, env, sun, moon, 78.37, world.terrain)


func _update_daylight(delta: float) -> void:
	atmosphere.indoor = player.inside != ""
	atmosphere.update(delta)


func _make_beacon() -> void:
	beacon = Node3D.new()
	beacon.name = "CilUkolu"
	add_child(beacon)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.9
	cm.bottom_radius = 0.9
	cm.height = 60.0
	cm.cap_top = false
	cm.cap_bottom = false
	mi.mesh = cm
	mi.position.y = 30.0
	_beacon_mat = StandardMaterial3D.new()
	_beacon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beacon_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beacon_mat.albedo_color = Color(0.35, 0.75, 1.0, 0.25)
	_beacon_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beacon_mat.disable_fog = true
	mi.material_override = _beacon_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beacon.add_child(mi)
	beacon.visible = false


# ------------------------------------------------------------------ události hráče (prezentace)

## Zobrazení herní události lokálního hráče (logiku – úkoly – řeší World).
func on_game_event(kind: String, data: Dictionary) -> void:
	match kind:
		"sfx":
			if data.has("delay"):
				get_tree().create_timer(float(data["delay"])).timeout.connect(func(): sfx.play(data["name"]))
			else:
				sfx.play(data["name"], randf_range(0.95, 1.05))
		"collected":
			var item: Item = data["item"]
			hud.on_collected(item)
			sfx.play("pickup_big" if item.kind == "zalud" else "pickup", randf_range(0.97, 1.05))
		"drank":
			var id: String = data["id"]
			var info := Consumables.info(id)
			var b := player.body
			if Consumables.is_alcohol(id):
				hud.popup("%s (%d ml, %.0f g alkoholu)\nTeď %s ‰ · po vstřebání ~%s ‰ · %s" % [info["short"], int(data["ml"]),
					float(data["g"]), ("%.2f" % b.promile()).replace(".", ","),
					("%.2f" % b.promile_peak_estimate()).replace(".", ","), b.stage_name()], 6.0)
			elif info.get("caffeine", 0.0) > 0.0:
				hud.popup("Káva tě trochu probere, ale promile nesnižuje (%s ‰)." % ("%.2f" % b.promile()).replace(".", ","), 5.0)
			else:
				hud.popup("%s – osvěžení (%s ‰)" % [info["short"], ("%.2f" % b.promile()).replace(".", ",")], 3.0)
		"ate":
			var info := Consumables.info(data["id"])
			hud.popup("%s (%d kcal) – jídlo zpomalí vstřebávání a urychlí odbourávání alkoholu.\nHmotnost %.1f kg" % [
				info["short"], int(info["kcal"]), player.body.weight], 5.0)
		"overloaded":
			hud.show_message("Neseš moc – zpomalíš.", 3.0)
		"smoked":
			hud.popup("Cigareta: nikotin tě na chvíli uklidní, ale plíce trpí (výdrž ↓).", 4.0)
		"vomited":
			hud.show_message("Blééé… Pozvracel ses. Žaludek je prázdný.", 3.0)
		"fell":
			hud.show_message("Au! %s." % String(data["reason"]).capitalize(), 2.5)
			sfx.play("land", 0.7, 2.0)
		"injured":
			fx.flash_hurt(float(data["amount"]))
			if float(data["amount"]) >= 2.0:
				sfx.play("hurt", randf_range(0.9, 1.1))
		"bottle_broken":
			hud.show_message("Cink! Rozbila se ti lahev: %s" % Consumables.info(data["id"])["short"], 3.0)
			sfx.play("glass")
		"prop_damaged":
			hud.police_banner("Poškodil jsi %s!" % data["what"], 3.0)
		"bee_sting":
			hud.show_message("Au! Bodla tě včela.", 1.5)
			sfx.play("hurt", randf_range(1.3, 1.5), -4.0)
		"ant_bite":
			hud.show_message("Stojíš na mraveništi – mravenci ti lezou do bot!", 2.0)
		"animal_attack":
			hud.police_banner("Napadla tě bachyně – chránila selata!", 3.5)
		"mounted_horse", "dismounted_horse":
			sfx.play("step", 0.8, -2.0)
		"soaked":
			hud.show_message("Jsi promočený – osuš se pod střechou nebo v teple, jinak prochladneš.", 4.0)
		"dried":
			hud.show_message("Oblečení uschlo.", 2.5)
		"chilled":
			hud.show_message("Prochladl jsi a třeseš se – zahřej se v teple, jinak ti to dolítne na zdraví!", 4.5)
		"warmed":
			hud.show_message("Už ti je zase teple.", 2.5)


# ------------------------------------------------------------------ vstup

## Každý fyzikální krok: klávesnice / ovladač → InputState lokálního hráče.
func _physics_process(_delta: float) -> void:
	if player == null:
		return
	var inp := player.input
	if hud.chat_open:
		# píše se – klávesy WASD / mezerník nesmí řídit postavu, auto ani koně
		inp.move = Vector2.ZERO
		inp.throttle = 0.0
		inp.brake = 0.0
		inp.steer = 0.0
		inp.jump = false
		inp.jump_pressed = false
		inp.sprint = false
		inp.crouch = false
		inp.reel = false
		inp.aim = false
		player.scope_on = false
		world.cancel_action(pid)
		return
	inp.move = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	inp.throttle = Input.get_action_strength("move_forward")
	inp.brake = Input.get_action_strength("move_back")
	inp.steer = Input.get_action_strength("move_left") - Input.get_action_strength("move_right")
	inp.jump = Input.is_action_pressed("jump")
	inp.jump_pressed = Input.is_action_just_pressed("jump")
	inp.sprint = Input.is_action_pressed("sprint")
	inp.crouch = Input.is_action_pressed("crouch")
	inp.reel = Input.is_action_pressed("use_tool") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED   # rybaření: navíjení
	# míření se zbraní (M2.8): pravé tlačítko myši drženo; s otevřenou nabídkou / bez zachycené myši ne
	inp.aim = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
		and not hud.menu_open
	inp.look_axis = Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	# dalekohled (X, držet) – jen pěšky, ne při konzumaci, při letu dronu a s otevřenou nabídkou ne
	player.scope_on = Input.is_action_pressed("binoculars") and player.car == null and player.horse == null \
		and player.drone == null and player.aircraft == null and not player.busy and not hud.menu_open


func _unhandled_input(event: InputEvent) -> void:
	if player == null:
		return
	var inp := player.input
	var was_captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED   # klik, který myš teprve zachytí, nespouští akci
	# --- pohled a myš (pěšky i v autě; kdo pohyb použije, rozhodne hráč / auto)
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			if freecam:
				# M6.2: volná kamera se točí přímo (Player by jinak look delta spotřeboval)
				var r := settings.look(event.relative)
				freecam.rotation.y -= r.x * player.mouse_sensitivity
				freecam.rotation.x = clampf(freecam.rotation.x - r.y * player.mouse_sensitivity, -1.55, 1.55)
			else:
				inp.add_look(settings.look(event.relative))
	elif event is InputEventMouseButton and event.pressed:
		if player.car == null and not hud._map.visible:      # s otevřenou mapou myš ovládá mapu (Hud._input)
			if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not player.controls_locked:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
				inp.add_zoom(-0.5)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				inp.add_zoom(0.5)
	elif event.is_action_pressed("toggle_view"):
		if freecam:
			_stop_freecam()                                  # M6.2: V = zpět k hráči
		else:
			inp.press_toggle_view()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		# otevřenou nabídku / rozhovor zavírá Esc v Hud (dostane ho dřív); jinak pauza
		if ready_done and not hud.menu_open and not hud.chat_open:
			if hud._map.visible:
				hud._toggle_map()                      # Esc nejdřív zavře mapu
			else:
				pause_menu.open()
			get_viewport().set_input_as_handled()
			return
	if not ready_done or hud.chat_open:
		return
	# --- herní menu (F2) – otevře / zavře i přes jinou nabídku; F5 / F9 rychlé uložení / načtení
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F2:
				game_menu.toggle()
				get_viewport().set_input_as_handled()
				return
			KEY_F5:
				save_game("rychly")
				get_viewport().set_input_as_handled()
				return
			KEY_F9:
				load_game("rychly")
				get_viewport().set_input_as_handled()
				return
	# --- akce (E, F, L, B, R, H), rozhovor (T / Enter)
	if hud.menu_open:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_T, KEY_ENTER, KEY_KP_ENTER]:
		hud.open_chat()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact"):
		_interact()
	elif event.is_action_pressed("car_enter"):
		world.player_action(pid, "car_enter")
	elif event.is_action_pressed("car_lights"):
		world.player_action(pid, "car_lights")
	elif event.is_action_pressed("car_wipers"):
		world.player_action(pid, "car_wipers")
	elif event.is_action_pressed("car_horn"):
		world.player_action(pid, "car_horn")
	elif event.is_action_pressed("car_reset"):
		world.player_action(pid, "car_reset")
	elif event.is_action_pressed("respawn"):
		world.player_action(pid, "respawn")
	elif event.is_action_pressed("unstuck"):
		world.player_action(pid, "unstuck")
	elif event.is_action_pressed("whistle"):
		world.player_action(pid, "whistle")
	elif event.is_action_pressed("equip_next"):
		world.player_action(pid, "equip_next")
	elif event.is_action_pressed("drone_photo"):
		world.player_action(pid, "drone_photo")        # M6.1: O = fotka z dronu (za letu)
	elif event.is_action_pressed("use_tool"):
		if player.drone != null and player.drone.flying():
			world.player_action(pid, "drone_photo")    # M6.1: i levé tlačítko fotí za letu
		elif was_captured and freecam == null and player.car == null and player.horse == null and player.aircraft == null:
			world.player_action(pid, "use_tool")
	else:
		for n in range(1, 6):
			if event.is_action_pressed("equip_slot_%d" % n):
				world.player_action(pid, "equip_slot_%d" % n)
				break


func _interact() -> void:
	var it := world.find_interact(pid)
	if it.is_empty():
		return
	if it["kind"] == "place":
		open_place_menu(it["key"])
	elif it["kind"] == "interior_obj":
		InteriorMenu.open(self, it)
	elif it["kind"] == "sleep":
		open_sleep_menu(it["node"])
	elif it["kind"] == "radio":
		radio_view.open()
	elif it["kind"] == "custom":
		(it["action"] as Callable).call(pid)     # krmelec, žlab, včelař, parůžky… (Hunter / Paddock)
	else:
		world.talk(pid, it)


## Nabídka postavy mimo Place (včelař): akce rozdělaného úkolu a úkoly, které postava nabízí.
func open_giver_menu(key: String, title: String, text: String) -> void:
	var q: Quests = world.quests_of(pid)
	var opts := []
	for o in q.place_options(key):
		opts.append(["★ " + o[0], o[1]])
	for qq in q.available_at(key):
		opts.append(["★ Úkol: %s%s" % [qq.title, "  (znovu)" if qq.state == "failed" else ""], func(): _offer_quest(qq)])
	hud.open_menu(title, text, opts)


## Fotka z dronu (World.drone_photo): snímek viewportu do user://fotky_dron/, záblesk a cvalnutí spouště.
func drone_photo() -> void:
	if player == null or player.drone == null:
		return
	var d := player.drone
	var img := get_viewport().get_texture().get_image()      # snímek ještě před zábleskem
	var dir := "user://fotky_dron"
	DirAccess.make_dir_recursive_absolute(dir)
	var name_ := "dron_j%d_f%02d.png" % [world.clock.jd(), d.photo_t]
	img.save_png("%s/%s" % [dir, name_])
	hud.photo_flash()
	sfx.play("shutter", 1.1, -3.0)
	hud.show_message("Fotka uložena: %s (%d m)" % [name_, roundi(d.agl())], 2.5)


## Volná kamera (M6.2, F2 → Teleport → Ladění): kamera ~500 m nad hráčem, volný let
## (hráč zůstane stát – jen pro kontrolu okolí mapy z výšky). V nebo znovu v menu = zpět.
func toggle_freecam() -> void:
	if freecam == null:
		_start_freecam()
	else:
		_stop_freecam()


func _start_freecam() -> void:
	if player == null:
		return
	freecam = Camera3D.new()
	freecam.name = "VolnaKamera"
	freecam.far = 20000.0
	add_child(freecam)
	var c := player.global_position
	var gy := world.terrain.height_at(c.x, c.z) if world.terrain else c.y
	freecam.global_position = Vector3(c.x, gy + FREECAM_ALT, c.z)
	freecam.rotation = Vector3(deg_to_rad(-70.0), player.yaw + PI, 0.0)
	_fc_prev_cam = get_viewport().get_camera_3d()
	freecam.current = true
	player.controls_locked = true
	hud.show_message("Volná kamera: WASD let, myš pohled, Mezerník/Ctrl výška, Shift rychle, V zpět k hráči.", 5.0)


func _stop_freecam() -> void:
	if freecam:
		freecam.queue_free()
		freecam = null
	if player != null:
		player.controls_locked = false
	if is_instance_valid(_fc_prev_cam):
		_fc_prev_cam.current = true
	elif player != null and player.camera:
		player.camera.current = true
	_fc_prev_cam = null


## Let volné kamery (pohyb sdílí s hráčem – ten je controls_locked; pohled točí _unhandled_input).
func _update_freecam(delta: float) -> void:
	var inp := player.input
	var mv: Vector2 = inp.move
	var dir := freecam.global_transform.basis * Vector3(mv.x, 0.0, mv.y)
	var up := (1.0 if inp.jump else 0.0) - (1.0 if inp.crouch else 0.0)
	var spd := FREECAM_SPRINT if inp.sprint else FREECAM_SPEED
	var step := dir + Vector3.UP * up
	if step.length() > 0.01:
		freecam.global_position += step.normalized() * spd * delta


## Provizorní nocleh (seník, palanda): přečkat noc, zdřímnout si, počkat do večera.
func open_sleep_menu(spot: SleepSpot) -> void:
	var h := world.clock.hour()
	var opts := [["Přečkat noc (spát do 7:00)", world.sleep.bind(pid, spot.kind)],
		["Zdřímnout si (2 hodiny)", world.rest.bind(pid, 2.0, spot.kind)]]
	if h >= 7.0 and h < 17.0:
		opts.append(["Odpočívat do večera (18:00)", world.rest.bind(pid, 18.0 - h, spot.kind)])
	var t := world.weather.temp
	var text: String = SleepSpot.KINDS[spot.kind][2]
	text += "\nJe %s, %s. Promile %s ‰." % [world.clock.text(), world.weather.describe(),
		("%.2f" % player.body.promile()).replace(".", ",")]
	if t < 3.0 and spot.kind != "palanda":
		text += "\nBude zima – spánek tě tolik nespraví."
	hud.open_menu(spot.title(), text, opts)


## Rádio: stanice (▶ = hraje), hlasitost ±1, vypnout. Po každé volbě se nabídka otevře znovu.
func open_radio_menu() -> void:
	var r: Radio = world.radio
	if r == null:
		return
	var opts := []
	for s in r.stations:
		var mark := "▶ " if r.station == s["id"] else "    "
		opts.append(["%s%s – %s" % [mark, s["name"], s["genre"]], _radio_do.bind(world.radio_tune.bind(pid, s["id"]))])
	opts.append(["Hlasitěji (+)   [%s]" % _vol_bar(r.volume), _radio_do.bind(world.radio_volume.bind(pid, r.volume + 1)),
		r.volume < 10])
	opts.append(["Tišeji (−)", _radio_do.bind(world.radio_volume.bind(pid, r.volume - 1)), r.volume > 0])
	if r.is_on():
		opts.append(["Vypnout rádio", _radio_do.bind(world.radio_tune.bind(pid, ""))])
	var text := "Hraje: %s" % r.describe()
	var h := world.clock.hour()
	if r.is_night():
		text += "\nJe %s – noční klid (22–6 h). Sousedi teď snesou jen tichou hudbu." % world.clock.text()
	var a := r.anger
	if a >= 60.0:
		text += "\nSousedi zuří! (%d %%)" % roundi(a)
	elif a >= 25.0:
		text += "\nSousedi začínají být nervózní (%d %%)." % roundi(a)
	elif r.is_on() and r.loudness() > 0.0 and r.loudness() <= 0.3 and not r.is_night() and h >= 8.0:
		text += "\nPříjemná hudba – sousedům nevadí."
	hud.open_menu("Rádio", text, opts)


## Akce rádia a znovu otevřít jeho nabídku (tlačítko nabídku zavírá).
func _radio_do(action: Callable) -> void:
	action.call()
	open_radio_menu.call_deferred()


static func _vol_bar(v: int) -> String:
	return "■".repeat(v) + "□".repeat(10 - v) + " %d" % v


# ------------------------------------------------------------------ uložení / načtení

func save_game(slot: String) -> void:
	if SaveGame.save(world, pid, slot):
		hud.show_message("Uloženo: %s\n%s" % [SaveGame.SLOT_NAMES.get(slot, slot), SaveGame.describe(slot)], 3.0)
		sfx.play("pickup")
	else:
		hud.show_message("Uložení se nepovedlo.", 3.0)


func load_game(slot: String) -> void:
	if not SaveGame.exists(slot):
		hud.show_message("Pozice „%s“ ještě není uložená (F5 = rychlé uložení)." % SaveGame.SLOT_NAMES.get(slot, slot), 3.0)
		return
	if hud.menu_open:
		hud.close_menu()
	if SaveGame.load_slot(world, pid, slot):
		fx.blackout = 0.0
		hud.show_message("Načteno: %s\n%s" % [SaveGame.SLOT_NAMES.get(slot, slot), SaveGame.describe(slot)], 3.5)
	else:
		hud.show_message("Pozici se nepodařilo načíst.", 3.0)


# ------------------------------------------------------------------ nabídky míst

## Nabídka místa: úkoly, akce úkolů, zboží (podle otevírací doby), doma spánek a lednička.
## Tlačítka volají akce World s id hráče.
func open_place_menu(key: String) -> void:
	var q: Quests = world.quests_of(pid)
	var opts := []
	for o in q.place_options(key):
		opts.append(["★ " + o[0], o[1]])
	for qq in q.available_at(key):
		opts.append(["★ Úkol: %s%s" % [qq.title, "  (znovu)" if qq.state == "failed" else ""], func(): _offer_quest(qq)])
	var title := ""
	var text := ""
	var p := player.body.promile()
	if key == "deda":
		title = "Děda Vomáčka"
		text = "„Pojď sem, synku, sedni si.“" if p < 1.0 else "„Ty jsi zase z hospody, co? Za mých mladých let…“"
		if player.item_count("cigarety") > 0 and q.active == null:
			opts.append(["Zapálit si s dědou", func(): world.use_item(pid, "cigarety")])
		hud.open_menu(title, text, opts)
		return
	var pl: Place = world.places[key]
	title = pl.data["name"]
	var open := pl.is_open(world.clock.hour())
	var rep: Reputation = world.reputations.get(pid)
	match key:
		"domov":
			title = world.estate.home_title(pid) if world.estate else "Doma"
			text = "Peníze: %d Kč. Promile: %s ‰." % [player.money, ("%.2f" % p).replace(".", ",")]
			if world.estate:
				text += "\n" + world.estate.rent_text(pid)          # M1.7: nájem bytu / vlastní dům
			opts.insert(0, ["Vejít dovnitř", func(): world.enter_interior(pid, "domov")])   # M1.4; ostatní položky zůstaly kvůli zvyku
			opts.append(["Vyspat se (do 7:00 ráno)", func(): world.sleep(pid)])
			if world.radio:
				opts.append(["Rádio… (%s)" % world.radio.describe(), open_radio_menu])
			opts.append(["Lednička: rohlíky (zdarma)", func(): world.serve(pid, "rohlik")])
			opts.append(["Lednička: chleba se sádlem (zdarma)", func(): world.serve(pid, "chleba_sadlo")])
			opts.append(["Sklenice vody", func(): world.serve(pid, "voda")])
			opts.append(["Uvařit si kafe", func(): world.serve(pid, "kava")])
			if player.body.stomach_alc > 3.0:
				opts.append(["Záchod – vyzvracet se (vyprázdní žaludek)", func(): world.vomit(pid)])
			var my_car := world.traffic.car_of(pid)
			if my_car and my_car.damage > 0.5 and my_car.global_position.distance_to(pl.park) < 20.0:
				opts.append(["Opravit auto v garáži (2 500 Kč)", func(): world.repair_car(pid), player.money >= 2500])
		_:
			var keeper := pl.keeper.display_name if pl.keeper else ""
			text = "%s · otevřeno %s · máš %d Kč" % [keeper, pl.hours_text(), player.money]
			if not open:
				text += "\nZAVŘENO – dveře jsou zamčené."
			elif key == "hospoda" and p > 2.5:
				text += "\n„Ty už máš dost, jdi domů!“ (hostinský ti nenalije)"
			if rep and rep.refused_at(key):
				text += "\n„Tobě nic nedám. Po tom, cos ve vsi vyváděl, ať tě tu nevidím!“ (pověst: %s)" % rep.tier_name()
				open = false
			elif rep and rep.price_mult() != 1.0:
				if rep.price_mult() < 1.0:
					text += "\nPro vážené sousedy sleva 10 %."
				else:
					text += "\nCeny pro tebe o %d %% vyšší – kvůli tvé pověsti." % roundi((rep.price_mult() - 1.0) * 100.0)
			if open:
				var sections := _offer_sections(key)
				if sections.size() > 1:     # víc kategorií (M2.3+): rozbalovací nabídka místo jedné dlouhé
					for s in sections:
						opts.append(["▸ %s (%d)" % [s[0], (s[1] as Array).size()], _open_shop_section.bind(key, s[0], s[1])])
				else:
					for o in Place.OFFERS.get(key, []):
						if o[2] == "header":
							continue
						var row: Array = _shop_item_row(key, o)
						if not row.is_empty():
							opts.append(row)
			# M1.5: dovnitř (zamčeno mimo otevírací dobu / pro postrach vsi řeší World._may_enter); nabídku od dveří jsme nechali
			if open and player.inside == "" and world.interiors.has(key):
				opts.insert(0, ["Vejít dovnitř", func(): world.enter_interior(pid, key)])
	hud.open_menu(title, text, opts)


## Rozdělí `Place.OFFERS[key]` na kategorie podle záhlaví ("header", M2.3): [[název, [nabídky]], …].
## Položky před prvním záhlavím tvoří úvodní kategorii `SHOP_DEFAULT_SECTION`. Míst s jednou kategorií
## se rozbalovací nabídka netýká – zůstává jeden plochý seznam jako dřív.
const SHOP_DEFAULT_SECTION := "Běžná nabídka"

func _offer_sections(key: String) -> Array:
	var sections := []
	var cur_name := SHOP_DEFAULT_SECTION
	var cur := []
	for o in Place.OFFERS.get(key, []):
		if o[2] == "header":
			if not cur.is_empty():
				sections.append([cur_name, cur])
			cur_name = o[0]
			cur = []
		else:
			cur.append(o)
	if not cur.is_empty():
		sections.append([cur_name, cur])
	return sections


## Jeden řádek nabídky (koupě / natočení / výkup) pro Hud.open_menu, nebo [], má-li se přeskočit
## (podnapilému hospoda alkohol nenalije).
func _shop_item_row(key: String, o: Array) -> Array:
	var id: String = o[0]
	var base: int = o[1]
	var mode: String = o[2]
	var info := Consumables.info(id)
	if key == "hospoda" and player.body.promile() > 2.5 and Consumables.is_alcohol(id):
		return []
	if mode == "sell":      # výkup z inventáře (M2.1): cena za kus, prodají se všechny kusy
		var have := player.item_count(id)
		return ["Prodat: %s – %d Kč / ks (máš %d)" % [info["short"], base, have],
			world.sell_items.bind(pid, id, base, key), have > 0]
	var price := world.price_for(pid, base)
	var label := "%s – %d Kč%s" % [info["name"], price, "  (s sebou)" if mode == "buy" else ""]
	if Consumables.is_alcohol(id) and mode == "serve":
		label += "  ≈ +%.2f ‰" % (Consumables.ethanol_g(id, float(info["ml"])) / (player.body.widmark_r() * player.body.weight))
	return [label, world.buy.bind(pid, id, base, mode, key), player.money >= price]


## Rozbalená kategorie nabídky místa (M2.3+): jen její položky + „← Zpět“ do hlavní nabídky místa.
func _open_shop_section(key: String, section_name: String, items: Array) -> void:
	var pl: Place = world.places[key]
	var opts := []
	for o in items:
		var row: Array = _shop_item_row(key, o)
		if not row.is_empty():
			opts.append(row)
	opts.append(["← Zpět do nabídky", func(): open_place_menu(key)])
	var keeper := pl.keeper.display_name if pl.keeper else ""
	var text := "%s · otevřeno %s · máš %d Kč" % [keeper, pl.hours_text(), player.money]
	hud.open_menu("%s – %s" % [pl.data["name"], section_name], text, opts)


func _offer_quest(q) -> void:
	hud.open_menu(q.title, "%s:\n„%s“" % [q.giver_name, q.intro], [
		["Přijmout úkol", func(): world.accept_quest(pid, q)],
	])


# ------------------------------------------------------------------ smyčka

func _process(delta: float) -> void:
	var __t0 := Tests.prof_t0()
	_process_impl(delta)
	Tests.prof_add("client", __t0)


func _process_impl(delta: float) -> void:
	if player == null or not ready_done:
		return
	_update_daylight(delta)
	if freecam:
		_update_freecam(delta)
	# kroky
	var hs := Vector3(player.velocity.x, 0, player.velocity.z).length()
	if player.car == null and player.is_on_floor() and hs > 0.8 and player.fallen <= 0.0:
		_step_dist += hs * delta
		var stride := 1.7 if hs > 6.0 else 1.25
		if _step_dist > stride:
			_step_dist = 0.0
			if player.wade > 0.03:
				sfx.play("splash", randf_range(0.85, 1.15), -4.0 + clampf(player.wade * 8.0, 0.0, 4.0))
			elif world.weather and world.weather.snow_cover > 0.15:
				sfx.play("step", randf_range(0.6, 0.75), -4.0)   # krupání sněhu
				_snow_footprint()
			else:
				sfx.play("step", randf_range(0.85, 1.15), -6.0)
	_update_water_sound(delta)
	# telemetrie dronu (M6.1): panel OSD – Drone.status() → Hud.drone; za letu jen letové tipy
	if player.drone != null:
		hud.drone(player.drone.status())
	else:
		hud.drone({})
	# telemetrie letouna (M6.3): Aircraft.status() → FlightHud panel + variometr pípá v termice
	if player.aircraft != null:
		flight_hud.update(player.aircraft.status(), delta)
	else:
		flight_hud.update({}, delta)
	if freecam:
		hud.set_prompt("[Volná kamera] WASD let · myš pohled · Mezerník/Ctrl výška · Shift rychle · V zpět k hráči")
	elif player.drone != null and player.drone.flying():
		hud.set_prompt("WASD let · myš otáčení · Mezerník stoupat · Ctrl klesat · Shift sport · V pohled · O / LMB fotka · F přistát / návrat")
	elif player.aircraft != null:
		hud.set_prompt("W/S plyn · A/D překlápění · Mezerník zatáhnout / brzda na zemi · Ctrl přiklonit · V pohled · F vystoupit (na zemi)")
	# výzva k interakci
	elif not hud.menu_open and not radio_view.active:
		var it := world.find_interact(pid)
		var prompt := ""
		if not it.is_empty():
			prompt = "[E] %s" % it["text"]
		var near_v: Car = world.nearest_enterable_car(pid) if player.car == null else null
		if near_v:
			prompt += ("   " if prompt != "" else "") + ("[F] Nastoupit do auta" if not near_v.two_wheeler else
				"[F] Nasednout: %s" % near_v.model.spec["name"])
		elif player.car:
			prompt = ("[F] Vystoupit" if not player.car.two_wheeler else "[F] Sesednout") if absf(player.car.speed) < 2.0 else ""
		var h := player.horse
		if h:
			prompt = "Kůň: %s · %d km/h · výdrž %d %% · %s   [Shift] rychleji  [S] pomaleji  [Mezerník] skok%s" % [
				h.gait_name(), roundi(absf(h.speed) * 3.6), roundi(h.stamina * 100.0), h.care_text(),
				"  [F] sesednout" if absf(h.speed) < 1.5 else ""]
		elif player.car == null and world.nearest_mountable_horse(pid):
			prompt += ("   " if prompt != "" else "") + "[F] Nasednout na koně"
		elif player.car == null and player.horse == null and player.aircraft == null:
			var na := world.nearest_enterable_aircraft(pid)
			if na:
				prompt += ("   " if prompt != "" else "") + "[F] Nastoupit: %s" % na.spec.get("name", "letoun")
		# kontextová akce nástroje / rukou (M0.4): [LMB] Natrhat trávu (Zahradničení 1), šedě s důvodem, když nejde
		var dim := false
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			world.cancel_action(pid)        # Esc / pauza / uvolněná myš akci přeruší
		if player.car == null and player.horse == null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			var ah := world.action_runner.hint(pid) if world.action_runner else {}
			if not ah.is_empty():
				if ah["reason"] == "":
					prompt += ("   " if prompt != "" else "") + "[LMB] %s" % ah["text"]
				else:
					prompt += ("   " if prompt != "" else "") + "%s – %s" % [ah["text"], ah["reason"]]
					dim = prompt.begins_with(String(ah["text"]))
		hud.set_prompt(prompt, dim)
	else:
		hud.set_prompt("")
		world.cancel_action(pid)
	# značka cíle úkolu – v opilosti ji "nevidíš"
	var tg := Vector3.INF
	var q: Quests = world.quests_of(pid)
	if q and q.active:
		tg = q.active.target()
	beacon.visible = tg != Vector3.INF
	if beacon.visible:
		beacon.global_position = tg
		var p := player.body.promile()
		_beacon_mat.albedo_color.a = 0.25 * (1.0 - smoothstep(1.2, 2.2, p))


## Šumění nejbližšího potoka (3D zvuk se přesouvá na nejbližší bod toku) a jméno toku při brodění.
func _update_water_sound(delta: float) -> void:
	_water_t -= delta
	if _water_t > 0.0 or world.water == null:
		return
	_water_t = 0.4
	if _brook == null:
		_brook = AudioStreamPlayer3D.new()
		_brook.stream = NatureSfx.get_stream("brook")
		_brook.max_distance = 45.0
		_brook.unit_size = 5.0
		_brook.attenuation_filter_cutoff_hz = 6000.0
		add_child(_brook)
	var pos := player.global_position
	var near := world.water.nearest_stream(pos, 40.0) if world.water.ice_flow < 0.8 else []
	if near.is_empty():
		if _brook.playing:
			_brook.stop()
	else:
		_brook.global_position = near[0]
		_brook.volume_db = {"river": 2.0, "stream": -2.0}.get(near[1], -8.0)
		if not _brook.playing:
			_brook.play()
	if player.wade > 0.05:
		var nm: String = world.water.info_at(pos.x, pos.z)["name"]
		if nm != "" and nm != _water_name:
			hud.show_message("Brodíš se: %s" % nm, 2.5)
		_water_name = nm
	elif player.wade <= 0.0:
		_water_name = ""


## Otisk podrážky ve sněhu – kreslí ho společný správce stop (`World.tracks`, stejně jako stopy zvěře a koně).
func _snow_footprint() -> void:
	var w: Weather = world.weather
	if w == null or w.snow_cover < 0.15 or player.car != null or world.tracks == null:
		return
	# střídavě levá / pravá noha, otisk ve směru chůze
	_track_side = -_track_side
	var vel := Vector3(player.velocity.x, 0, player.velocity.z)
	var st_yaw := atan2(vel.x, vel.z) if vel.length() > 0.2 else player.yaw + PI
	var at := player.global_position + Vector3(cos(st_yaw), 0, -sin(st_yaw)) * 0.13 * _track_side
	world.tracks.add("boot", at, st_yaw)


# ------------------------------------------------------------------ snímky

## Uloží snímek obrazovky (`--shot=cesta.png`, volitelně `--top=m` pohled shora) a ukončí hru.
func screenshot() -> void:
	if args.has("top"):
		# pohled shora (ortogonální), --top=šířka záběru v m, střed = --pos
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = float(args["top"])
		cam.far = 2000.0
		add_child(cam)
		var c := player.global_position
		cam.global_transform = Transform3D(Basis.from_euler(Vector3(-PI / 2, 0, 0)), c + Vector3(0, 400, 0))
		cam.current = true
		hud.visible = false
	await get_tree().create_timer(float(args.get("wait", "4"))).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(args["shot"])
	print("SHOT saved ", args["shot"], "  FPS ", Engine.get_frames_per_second(),
		"  draw calls ", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"  primitives ", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"  objects ", Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	get_tree().quit()
