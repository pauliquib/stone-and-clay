## Přiblížení na rádio (E u rádia): kamera plynule najede před přední stěnu lampového rádia a hráč
## točí knoflíky myší – najet na knoflík (ruka), držet levé tlačítko a táhnout (doprava / nahoru = po
## směru hodin, Shift = jemně), nebo kolečkem nad knoflíkem. Levý knoflík = vypínač a hlasitost,
## pravý = ladění (ručička na stupnici; mezi stanicemi šum). Klávesy: A/D (←/→) ladění, W/S (↑/↓)
## hlasitost. Odchod: Esc, E nebo pravé tlačítko. Změny jdou přes akce World (radio_knob / radio_dial).
class_name RadioView
extends Node

const EYE := Vector3(0.0, 0.93, 0.5)        # poloha kamery vůči rádiu (lokálně – před přední stěnou)
const LOOK := Vector3(0.0, 0.9, 0.12)
const FOV := 42.0
const FLY := 0.7                             # doba najetí / odjetí kamery (s)

var client: Node                             # LocalClient
var active := false                          # hráč stojí u rádia (i během najíždění / odjíždění)
var _cam: Camera3D
var _tw: Tween
var _leaving := false
var _hover := ""                             # "vol" / "tune" / ""
var _drag := ""
var _drag_screen := Vector2.ZERO
var _layer: CanvasLayer
var _info: Label
var _help: Label


func _init(c: Node) -> void:
	client = c


func _ready() -> void:
	_cam = Camera3D.new()
	_cam.near = 0.03
	_cam.far = 9000.0
	add_child(_cam)
	_layer = CanvasLayer.new()
	_layer.layer = 5
	_layer.visible = false
	add_child(_layer)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.offset_bottom = -24
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(box)
	_info = _mk_label(box, 20)
	_help = _mk_label(box, 15)
	_help.modulate = Color(0.85, 0.85, 0.85)
	_help.text = "Levý knoflík: vypínač a hlasitost     Pravý knoflík: ladění\n" \
		+ "najeď na knoflík a táhni myší (Shift = jemně) nebo toč kolečkem · A/D ladění · W/S hlasitost\n" \
		+ "Esc / E / pravé tlačítko – odejít"


func _mk_label(parent: Node, size: int) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _radio() -> Radio:
	return client.world.radio


# ------------------------------------------------------------------ najetí / odjetí

func open() -> void:
	var r := _radio()
	var p: Player = client.player
	if active or r == null or p == null or p.camera == null:
		return
	active = true
	_leaving = false
	p.controls_locked = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var target := r.global_transform * Transform3D(Basis(), EYE)
	target = target.looking_at(r.to_global(LOOK), Vector3.UP)
	_fly(p.camera.global_transform, p.camera.fov, target, FOV)
	_cam.current = true
	_layer.visible = true


func close() -> void:
	if not active or _leaving:
		return
	_leaving = true
	_end_drag()
	_set_hover("")
	_layer.visible = false
	var p: Player = client.player
	_fly(_cam.global_transform, _cam.fov, p.camera.global_transform, p.camera.fov)
	_tw.finished.connect(func():
		p.camera.current = true
		active = false
		_leaving = false
		if not client.hud.menu_open and not (client.pause_menu and client.pause_menu.is_open):
			p.controls_locked = false
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)


func _fly(from: Transform3D, from_fov: float, to: Transform3D, to_fov: float) -> void:
	if _tw:
		_tw.kill()
	_cam.global_transform = from
	_cam.fov = from_fov
	var step := func(t: float) -> void:
		_cam.global_transform = from.interpolate_with(to, t)
		_cam.fov = lerpf(from_fov, to_fov, t)
	_tw = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tw.tween_method(step, 0.0, 1.0, FLY)


# ------------------------------------------------------------------ knoflíky

## Knoflík pod kurzorem ("vol" / "tune" / "") – podle průmětu středu a poloměru knoflíku na obrazovku.
func _knob_at(pos: Vector2) -> String:
	var r := _radio()
	for k in ["vol", "tune"]:
		var c: Vector3 = r.to_global(Radio.KNOB_VOL_POS if k == "vol" else Radio.KNOB_TUNE_POS) \
			+ r.global_transform.basis.z * 0.015
		if _cam.is_position_behind(c):
			continue
		var sc := _cam.unproject_position(c)
		var edge := _cam.unproject_position(c + r.global_transform.basis.x * Radio.KNOB_R)
		if pos.distance_to(sc) <= maxf(sc.distance_to(edge) * 1.35, 10.0):
			return k
	return ""


func _set_hover(k: String) -> void:
	if k == _hover:
		return
	_hover = k
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if k != "" else Input.CURSOR_ARROW)


## Otočení knoflíku o `amount` (kladně = po směru hodin).
func _turn(k: String, amount: float) -> void:
	var r := _radio()
	if k == "vol":
		client.world.radio_knob(client.pid, r.knob + amount * 0.0035)
	elif k == "tune":
		client.world.radio_dial(client.pid, r.dial + amount * 0.0006)


func _end_drag() -> void:
	if _drag == "":
		return
	_drag = ""
	# během tažení je kurzor zachycený (knoflík jde točit bez konce) – vrátit ho na knoflík
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Input.warp_mouse(_drag_screen)


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if _leaving:
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		if _drag != "":
			var fine := 0.25 if Input.is_key_pressed(KEY_SHIFT) else 1.0
			_turn(_drag, (event.relative.x - event.relative.y) * fine)
		else:
			_set_hover(_knob_at(event.position))
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and _hover != "":
				_drag = _hover
				_drag_screen = event.position
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			elif not event.pressed:
				_end_drag()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var k := _hover if _hover != "" else _knob_at(event.position)
			var step := 8.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -8.0
			if k == "tune":
				step *= 0.5 if Input.is_key_pressed(KEY_SHIFT) else 1.5
			_turn(k, step)
		elif event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			close()
	elif event is InputEventKey:
		var kc: int = event.keycode
		if kc in [KEY_F1, KEY_F5, KEY_F9]:
			return                                # nápověda a ukládání jdou i u rádia
		if event.pressed and not event.echo and kc in [KEY_ESCAPE, KEY_E]:
			close()
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not active or _leaving:
		return
	var r := _radio()
	if r == null:
		return
	# klávesy: A/D (←/→) ladění, W/S (↑/↓) hlasitost – plynule, dokud se drží
	var fine := 0.3 if Input.is_key_pressed(KEY_SHIFT) else 1.0
	var tune := float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) \
		- float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT))
	var vol := float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)) \
		- float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN))
	if tune != 0.0:
		_turn("tune", tune * 160.0 * fine * delta)
	if vol != 0.0:
		_turn("vol", vol * 90.0 * fine * delta)
	_info.text = _info_text(r)


func _info_text(r: Radio) -> String:
	var t := r.describe().capitalize() if not r.is_on() else r.describe()
	if r.is_on() and r.station == "":
		var n := r.nearest_station(r.dial)
		if n[0] >= 0 and float(n[1]) < Radio.DIAL_TOL * 3.0:
			t += "  ·  blízko: %s" % r.stations[n[0]]["name"]
	if r.is_night():
		t += "\nNoční klid (22–6 h) – sousedi teď snesou jen tichou hudbu."
	if r.anger >= 60.0:
		t += "\nSousedi zuří! (%d %%)" % roundi(r.anger)
	elif r.anger >= 25.0:
		t += "\nSousedi začínají být nervózní (%d %%)." % roundi(r.anger)
	return t
