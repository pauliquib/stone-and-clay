## M8.D: menu pro vývojáře (F3, jen se zapnutým Režimem vývojáře v Esc → Nastavení) – živé ladění parametrů
## herních algoritmů z registru `DevTune`. Vlevo kategorie a podskupiny (dvě úrovně), vpravo řádky: název (nápověda
## v tooltipu), posuvník, číselné pole s jednotkou, ↺ výchozí; změněný řádek je zvýrazněný. Nahoře hledání (název,
## id, nápověda), dole Uložit (`user://ladeni.cfg`), Exportovat (`config.json`), Výchozí (skupina / vše) s potvrzením.
## Hra za otevřeného menu běží (účinek je vidět hned), jen myš patří menu; psaní do polí nevede postavu ani auto
## (`typing` čte `LocalClient`). Zavřené menu nic nepočítá (`set_process(false)`).
class_name DevMenu
extends CanvasLayer

const MAX_ROWS := 300                     # víc řádků najednou nestavět (hledání je zúží)
const CHANGED_COL := Color(1.0, 0.72, 0.3)
const NAME_W := 360.0

var client: Node                          # LocalClient
var is_open := false
var typing := false                       # fokus v textovém poli (hledání, číslo) – LocalClient nepouští vstup do hry
var _group := ""                          # vybraná kategorie („Vozidla“) nebo podskupina („Vozidla/Auto“)
var _root: Control
var _tree: Tree
var _search: LineEdit
var _rows_box: VBoxContainer
var _status: Label
var _bar: HBoxContainer
var _confirm_bar: HBoxContainer
var _confirm_label: Label
var _confirm_cb := Callable()
var _rows := {}                           # id → {name: Label, slider, spin, check, option, reset: Button}
var _search_t := -1.0                     # odklad přestavby při psaní hledání (s)
var _syncing := false


func _init(c: Node) -> void:
	client = c
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP     # klik vedle menu nezachytí myš pro rozhlížení
	add_child(_root)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Hud.MENU_BG, 0.9)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(14)
	sb.set_border_width_all(1)
	sb.border_color = Color(Hud.ACCENT, 0.4)
	panel.add_theme_stylebox_override("panel", sb)
	panel.anchor_left = 0.3
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 0.0
	panel.offset_top = 16.0
	panel.offset_right = -16.0
	panel.offset_bottom = -16.0
	_root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var title := _label(head, "Menu pro vývojáře – ladění parametrů", 22)
	title.add_theme_color_override("font_color", Hud.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(head, "Zavřít (F3 / Esc)", close)
	_search = LineEdit.new()
	_search.placeholder_text = "Hledat (název, id, nápověda) – např. „brz“ najde brzdy všech vozidel"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t: String): _search_t = 0.25)
	_search.text_submitted.connect(func(_t: String): _search.release_focus())   # Enter = zpět k řízení
	v.add_child(_search)
	var mid := HBoxContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 10)
	v.add_child(mid)
	_tree = Tree.new()
	_tree.custom_minimum_size = Vector2(230, 0)
	_tree.hide_root = true
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.item_selected.connect(_on_tree_pick)
	mid.add_child(_tree)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mid.add_child(scroll)
	_rows_box = VBoxContainer.new()
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.add_theme_constant_override("separation", 2)
	scroll.add_child(_rows_box)
	_status = _label(v, "", 14)
	_status.add_theme_color_override("font_color", Color(0.75, 0.9, 0.75))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bar = HBoxContainer.new()
	_bar.add_theme_constant_override("separation", 8)
	v.add_child(_bar)
	_button(_bar, "Uložit", _save)
	_button(_bar, "Exportovat do config.json", func(): _ask("Zapsat config.json s hodnotami odlišnými od výchozích v kódu?", _export))
	_button(_bar, "Výchozí (skupina)", func():
		if _group != "":
			_ask("Vrátit na výchozí celou skupinu „%s“?" % _group.replace("/", " → "), _reset_group_now))
	_button(_bar, "Výchozí (vše)", func(): _ask("Vrátit na výchozí úplně všechny parametry?", _reset_all_now))
	_button(_bar, "Ladicí vrstvy mapy…", func():
		close()
		client.game_menu.open_debug_layers())
	_confirm_bar = HBoxContainer.new()
	_confirm_bar.add_theme_constant_override("separation", 8)
	v.add_child(_confirm_bar)
	_confirm_label = _label(_confirm_bar, "", 16)
	_confirm_label.add_theme_color_override("font_color", CHANGED_COL)
	_confirm_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(_confirm_bar, "Ano", func():
		var cb := _confirm_cb
		_end_ask()
		if cb.is_valid():
			cb.call()
			_refresh_rows())
	_button(_confirm_bar, "Ne", _end_ask)
	_confirm_bar.visible = false
	_root.visible = false
	set_process(false)
	DevTune.hub().changed.connect(_on_param_changed)


# ------------------------------------------------------------------ otevření / zavření

func toggle() -> void:
	if is_open:
		close()
	else:
		open()


func open() -> void:
	if is_open or not client.settings.dev_mode:
		return
	is_open = true
	_root.visible = true
	set_process(true)
	DevTune.warn_unknown()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_tree()
	_refresh_rows()
	_set_status("Zaregistrováno %d parametrů. Hra běží – změna platí hned. Uložit = jen tento počítač, Export = nové výchozí do projektu." % DevTune.count())


func close() -> void:
	if not is_open:
		return
	is_open = false
	typing = false
	_end_ask()
	_root.visible = false
	set_process(false)
	var f := _root.get_viewport().gui_get_focus_owner()
	if f != null:
		f.release_focus()
	if client.pause_menu != null and client.pause_menu.is_open:
		return
	if client.radio_view != null and client.radio_view.active:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		client.hud._update_mouse_mode()


func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.physical_keycode == KEY_F3:
		if not client.settings.dev_mode or not client.ready_done or client.hud.chat_open:
			return
		if client.pause_menu != null and client.pause_menu.is_open:
			return
		toggle()
		get_viewport().set_input_as_handled()
	elif is_open and k.keycode == KEY_ESCAPE:
		if _confirm_bar.visible:
			_end_ask()
		else:
			close()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	# jen při otevřeném menu: fokus v textovém poli = psaní, myš patří menu
	var f := _root.get_viewport().gui_get_focus_owner()
	typing = f is LineEdit
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE and not client.hud.menu_open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _search_t >= 0.0:
		_search_t -= delta
		if _search_t < 0.0:
			_refresh_rows()


# ------------------------------------------------------------------ skupiny a řádky

func _build_tree() -> void:
	_tree.clear()
	var root := _tree.create_item()
	var first: TreeItem = null
	var sel: TreeItem = null
	for g in DevTune.groups():
		var cat: String = g[0]
		var ci := _tree.create_item(root)
		ci.set_text(0, "%s  (%d)" % [cat, DevTune.count(cat)])
		ci.set_metadata(0, cat)
		ci.set_custom_color(0, Hud.ACCENT)
		if first == null:
			first = ci
		if cat == _group:
			sel = ci
		for sub in g[1]:
			var full := "%s/%s" % [cat, sub]
			var si := _tree.create_item(ci)
			si.set_text(0, "%s  (%d)" % [sub, DevTune.count(full)])
			si.set_metadata(0, full)
			if full == _group:
				sel = si
	if sel == null:
		sel = first
	if sel != null:
		_group = String(sel.get_metadata(0))
		sel.select(0)


func _on_tree_pick() -> void:
	var it := _tree.get_selected()
	if it == null:
		return
	_group = String(it.get_metadata(0))
	if _search.text != "":
		_search.text = ""
	_refresh_rows()


func _refresh_rows() -> void:
	if not is_open:
		return
	for c in _rows_box.get_children():
		_rows_box.remove_child(c)
		c.queue_free()
	_rows.clear()
	var q := _search.text.strip_edges().to_lower()
	var ids: Array[String] = []
	if q != "":
		for id in DevTune.ids():
			var p := DevTune.info(id)
			var hay := ("%s %s %s %s" % [p["label"], id, p["group"], p["help"]]).to_lower()
			if hay.contains(q):
				ids.append(id)
	else:
		ids = DevTune.ids(_group)
	if ids.is_empty():
		_label(_rows_box, "Nic nenalezeno." if q != "" else "Ve skupině zatím nic není.", 16)
		return
	var last_group := ""
	var n := 0
	for id in ids:
		if n >= MAX_ROWS:
			_label(_rows_box, "… a dalších %d – zpřesni hledání nebo vyber podskupinu." % (ids.size() - n), 14)
			break
		var p := DevTune.info(id)
		if p["group"] != last_group and (q != "" or not String(_group).contains("/")):
			last_group = p["group"]
			var h := _label(_rows_box, String(last_group).replace("/", " → "), 15)
			h.add_theme_color_override("font_color", Color(Hud.ACCENT, 0.85))
		_add_row(p)
		n += 1


func _add_row(p: Dictionary) -> void:
	var id: String = p["id"]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_rows_box.add_child(row)
	var lbl := _label(row, String(p["label"]), 15)
	lbl.custom_minimum_size = Vector2(NAME_W, 0)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.clip_text = true
	lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	lbl.tooltip_text = _tooltip(p)
	var r := {"name": lbl}
	match String(p["kind"]):
		"bool":
			var cb := CheckBox.new()
			cb.button_pressed = bool(p["value"])
			cb.toggled.connect(func(on: bool): _user_set(id, on))
			row.add_child(cb)
			r["check"] = cb
		"choice":
			var ob := OptionButton.new()
			for o in p["options"]:
				ob.add_item(String(o))
			ob.selected = int(p["value"])
			ob.item_selected.connect(func(i: int): _user_set(id, i))
			row.add_child(ob)
			r["option"] = ob
		_:
			var s := HSlider.new()
			s.min_value = float(p["lo"])
			s.max_value = float(p["hi"])
			s.step = float(p["step"])
			s.allow_greater = true
			s.allow_lesser = true
			s.custom_minimum_size = Vector2(170, 0)
			s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			s.value = float(p["value"])
			s.value_changed.connect(func(x: float): _user_set(id, x))
			row.add_child(s)
			var sp := SpinBox.new()
			sp.min_value = float(p["lo"])
			sp.max_value = float(p["hi"])
			sp.step = float(p["step"])
			sp.allow_greater = true
			sp.allow_lesser = true
			sp.suffix = String(p["unit"])
			sp.custom_minimum_size = Vector2(130, 0)
			sp.value = float(p["value"])
			sp.value_changed.connect(func(x: float): _user_set(id, x))
			var le := sp.get_line_edit()
			le.text_submitted.connect(func(_t: String): le.release_focus())    # Enter = zpět k řízení
			row.add_child(sp)
			r["slider"] = s
			r["spin"] = sp
	var rb := Button.new()
	rb.text = "↺"
	rb.tooltip_text = "Výchozí: %s" % _fmt(p, p["base"])
	rb.pressed.connect(func(): DevTune.reset(id))
	row.add_child(rb)
	r["reset"] = rb
	_rows[id] = r
	_mark(id)


func _tooltip(p: Dictionary) -> String:
	var t := String(p["help"])
	if t != "":
		t += "\n"
	t += "id: %s\nvýchozí: %s" % [p["id"], _fmt(p, p["base"])]
	if p["base"] != p["default"]:
		t += " (z config.json; v kódu %s)" % _fmt(p, p["default"])
	return t


func _fmt(p: Dictionary, v: Variant) -> String:
	match String(p["kind"]):
		"bool":
			return "zapnuto" if bool(v) else "vypnuto"
		"choice":
			var opts: Array = p["options"]
			return String(opts[int(v)]) if int(v) < opts.size() else str(v)
		"int":
			return "%d %s" % [int(v), p["unit"]]
	return "%s %s" % [String.num(float(v), 4), p["unit"]]


func _user_set(id: String, v: Variant) -> void:
	if _syncing:
		return
	DevTune.set_value(id, v)


## Registr změnil hodnotu (posuvník, pole, ↺, výchozí skupiny, načtení) – srovnat řádek, když je vidět.
func _on_param_changed(id: String, v: Variant) -> void:
	if not is_open or not _rows.has(id):
		return
	var r: Dictionary = _rows[id]
	_syncing = true
	if r.has("slider"):
		(r["slider"] as HSlider).set_value_no_signal(float(v))
		(r["spin"] as SpinBox).set_value_no_signal(float(v))
	elif r.has("check"):
		(r["check"] as CheckBox).set_pressed_no_signal(bool(v))
	elif r.has("option"):
		(r["option"] as OptionButton).selected = int(v)
	_syncing = false
	_mark(id)


## Zvýraznění řádku změněného oproti výchozí hodnotě (a povolené ↺).
func _mark(id: String) -> void:
	var r: Dictionary = _rows[id]
	var ch := DevTune.is_changed(id)
	var lbl: Label = r["name"]
	if ch:
		lbl.add_theme_color_override("font_color", CHANGED_COL)
	else:
		lbl.remove_theme_color_override("font_color")
	(r["reset"] as Button).disabled = not ch


# ------------------------------------------------------------------ ukládání

func _save() -> void:
	if DevTune.save_user():
		_set_status("Uloženo do %s – po restartu hry hodnoty platí (jen tento počítač)." %
			ProjectSettings.globalize_path(DevTune.USER_PATH))
	else:
		_set_status("Uložení se nepovedlo (%s)." % DevTune.USER_PATH)


func _reset_group_now() -> void:
	DevTune.reset_group(_group)
	_set_status("Skupina „%s“ je zpět na výchozích hodnotách (neuložené – Uložit)." % _group.replace("/", " → "))


func _reset_all_now() -> void:
	DevTune.reset_all()
	_set_status("Všechny parametry jsou zpět na výchozích hodnotách (neuložené – Uložit).")


func _export() -> void:
	var path := DevTune.export_root()
	if path == "":
		_set_status("Export se nepovedl – do config.json nejde zapisovat.")
		return
	_set_status("Exportováno do %s (jen hodnoty odlišné od výchozích v kódu). Jsou to teď nové výchozí hodnoty." % path)
	_refresh_rows()


## Potvrzení v menu (žádný confirm()): dolní lišta se vymění za otázku Ano / Ne.
func _ask(text: String, cb: Callable) -> void:
	_confirm_label.text = text
	_confirm_cb = cb
	_bar.visible = false
	_confirm_bar.visible = true


func _end_ask() -> void:
	_confirm_cb = Callable()
	if _confirm_bar != null:
		_confirm_bar.visible = false
		_bar.visible = true


func _set_status(t: String) -> void:
	_status.text = t


# ------------------------------------------------------------------ stavební kousky (vzhled jako PauseMenu)

func _label(parent: Node, text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _button(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 16)
	b.custom_minimum_size = Vector2(0, 34)
	var n := StyleBoxFlat.new()
	n.bg_color = Color(1, 1, 1, 0.05)
	n.set_corner_radius_all(6)
	n.set_content_margin_all(6)
	var h := StyleBoxFlat.new()
	h.bg_color = Color(Hud.ACCENT, 0.2)
	h.set_corner_radius_all(6)
	h.set_content_margin_all(6)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.add_theme_stylebox_override("focus", h)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b
