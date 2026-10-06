## Pauzovací nabídka (Esc): klasická hráčská nabídka – Pokračovat, Uložit, Načíst, Nastavení, Ovládání,
## herní menu (F2), Hlavní menu (zatím není) a Ukončit hru. V singleplayeru pozastaví celou hru
## (`get_tree().paused` – svět, fyzika, zvuky, čas); v MP (víc hráčů ve World) svět běží dál a jen
## se zamkne ovládání. Sama běží i za pauzy (PROCESS_MODE_ALWAYS). Při ztrátě fokusu okna se otevře sama.
class_name PauseMenu
extends CanvasLayer

var client: Node                 # LocalClient
var settings: GameSettings
var is_open := false
var _page := "main"
var _dim: ColorRect
var _title: Label
var _info: Label
var _list: VBoxContainer
var _status: Label


func _init(c: Node) -> void:
	client = c
	settings = c.settings
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.55)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.add_child(center)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Hud.MENU_BG
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(24)
	sb.set_border_width_all(1)
	sb.border_color = Color(Hud.ACCENT, 0.4)
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(520, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	_title = _label(v, "", 30)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_color_override("font_color", Hud.ACCENT)
	_info = _label(v, "", 15)
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_sep())
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(500, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)
	_list.resized.connect(func(): scroll.custom_minimum_size.y = minf(_list.size.y, 560.0))
	_status = _label(v, "", 15)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7))
	_dim.visible = false


# ------------------------------------------------------------------ otevření / zavření

## Singleplayer = jen jeden hráč ve světě → smí se pozastavit celý svět.
func _can_pause() -> bool:
	return client.world.players.size() <= 1


func open() -> void:
	if is_open:
		return
	is_open = true
	_dim.visible = true
	if _can_pause():
		get_tree().paused = true
	client.player.controls_locked = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_status.text = ""
	_show_main()


func close() -> void:
	if not is_open:
		return
	if _page in ["settings", "graphics"]:
		settings.save_file()
	is_open = false
	_dim.visible = false
	get_tree().paused = false
	if client.radio_view.active:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE     # zpět u rádia (pauza při ztrátě fokusu)
	elif not client.hud.menu_open:
		client.player.controls_locked = false
		client.hud._update_mouse_mode()                 # může být otevřená mapa → viditelný kurzor


func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if _page == "main":
			close()
		else:
			_back()


func _notification(what: int) -> void:
	# okno ztratilo fokus (Alt+Tab) → pauza, ať hráč po návratu nenajde postavu v příkopu
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and not is_open and client.ready_done \
			and client.player != null and not client.hud.chat_open and _can_pause() and not client.is_automated():
		open()


func _back() -> void:
	var from := _page
	if from in ["settings", "graphics"]:
		settings.save_file()
	_status.text = ""
	if from == "graphics":
		_show_settings()
	else:
		_show_main()


# ------------------------------------------------------------------ stránky

func _clear(title: String, info: String) -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_title.text = title
	_info.text = info


func _button(text: String, cb: Callable, enabled := true) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	b.add_theme_font_size_override("font_size", 19)
	b.custom_minimum_size = Vector2(0, 40)
	var n := StyleBoxFlat.new()
	n.bg_color = Color(1, 1, 1, 0.04)
	n.set_corner_radius_all(6)
	var h := StyleBoxFlat.new()
	h.bg_color = Color(Hud.ACCENT, 0.2)
	h.set_corner_radius_all(6)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.add_theme_stylebox_override("focus", h)
	b.pressed.connect(cb)
	_list.add_child(b)
	return b


## Podnadpis kategorie v hlavní stránce pauzy (nekliknutelný).
func _header(text: String) -> void:
	if _list.get_child_count() > 0:
		_list.add_child(_sep())
	var l := _label(_list, text, 14)
	l.add_theme_color_override("font_color", Color(Hud.ACCENT, 0.85))


func _sep() -> HSeparator:
	var s := HSeparator.new()
	var st := StyleBoxLine.new()
	st.color = Color(Hud.ACCENT, 0.35)
	s.add_theme_stylebox_override("separator", st)
	return s


func _focus_first() -> void:
	for c in _list.get_children():
		if c is Button and not c.disabled:
			c.grab_focus.call_deferred()
			return


func _show_main() -> void:
	_page = "main"
	var c: Clock = client.world.clock
	var info := "%s   %s   ·   %s" % [c.date_text(), c.text(), client.world.weather.describe()]
	info += "\n" + ("Hra je pozastavená." if _can_pause() else "Multiplayer – svět běží dál.")
	_clear("PAUZA", info)
	_button("Pokračovat", close)
	_header("Hra")
	_button("Nová hra…", _show_new_game)
	_button("Uložit hru…", _show_save)
	_button("Načíst hru…", _show_load)
	_button("Herní menu (F2)…", func():
		close()
		client.game_menu.open_main())
	_header("Nastavení")
	_button("Nastavení…", _show_settings)
	_button("Ovládání…", _show_controls)
	_header("Systém")
	_button("Hlavní menu  (připravujeme)", func(): pass, false)
	_button("Ukončit hru…", _show_quit)
	_focus_first()


func _show_save() -> void:
	_page = "save"
	_clear("Uložit hru", "Uložená pozice přepíše, co v ní bylo. F5 = rychlé uložení kdykoli ve hře.")
	for slot in ["1", "2", "3", "rychly"]:
		var d := SaveGame.describe(slot)
		_button("%s  –  %s" % [SaveGame.SLOT_NAMES[slot], d if d != "" else "prázdná"], _save.bind(slot))
	_button("← Zpět", _back)
	_focus_first()


func _save(slot: String) -> void:
	if SaveGame.save(client.world, client.pid, slot):
		_show_save()
		_status.text = "Uloženo: %s" % SaveGame.SLOT_NAMES[slot]
	else:
		_status.text = "Uložení se nepovedlo."


func _show_load() -> void:
	_page = "load"
	_clear("Načíst hru", "Neuložený postup od posledního uložení se ztratí.")
	var any := false
	for slot in SaveGame.SLOTS:
		var d := SaveGame.describe(slot)
		if d != "":
			any = true
			_button("%s  –  %s" % [SaveGame.SLOT_NAMES[slot], d], _load.bind(slot))
	if not any:
		_label(_list, "Zatím žádná uložená pozice.", 16)
	_button("← Zpět", _back)
	_focus_first()


func _load(slot: String) -> void:
	close()
	client.load_game(slot)


func _show_new_game() -> void:
	_page = "newgame"
	_clear("Nová hra", "Svět se postaví znovu od začátku – nový los bydlení (bytový dům), čistý hráč i obec.\n" +
		"Neuložený postup se ztratí; uložené pozice zůstávají.")
	_button("Uložit (rychlá pozice) a začít znovu", _new_game.bind(true))
	_button("Začít znovu bez uložení", _new_game.bind(false))
	_button("← Zpět", _back)
	_focus_first()


## Reload scény postaví svět znovu (nový los bydlení, čistý stav). `Main.FRESH_START` vypne --load a ladicí parametry.
func _new_game(with_save: bool) -> void:
	if with_save:
		SaveGame.save(client.world, client.pid, "rychly")
	get_tree().paused = false
	Main.FRESH_START = true
	get_tree().reload_current_scene()


func _show_quit() -> void:
	_page = "quit"
	_clear("Ukončit hru?", "Neuložený postup od posledního uložení se ztratí.")
	_button("Uložit (rychlá pozice) a ukončit", func():
		SaveGame.save(client.world, client.pid, "rychly")
		get_tree().quit())
	_button("Ukončit bez uložení", func(): get_tree().quit())
	_button("← Zpět do hry", _back)
	_focus_first()


func _show_controls() -> void:
	_page = "controls"
	_clear("Ovládání", "")
	var t := _label(_list, "", 16)
	t.text = "\n".join([
		"WASD – chůze / řízení            myš – rozhlížení",
		"Shift – sprint                   Mezerník – skok / ruční brzda",
		"Ctrl / C – přikrčení             V – 1. / 3. osoba (i v autě)",
		"kolečko myši – vzdálenost kamery",
		"E – mluvit / objednat / koupit / nocleh",
		"T / Enter – říct něco nahlas",
		"F – nastoupit / vystoupit, nasednout na koně",
		"Tab / I – inventář       J – deník úkolů       M – mapa",
		"L – světla   B – klakson   N – stěrače   R – postavit auto",
		"H – domů     G – hvízdnutí na koně     X (držet) – dalekohled",
		"Q – další nástroj   1–5 – rychlý slot   levé tlačítko myši – použít nástroj / akce",
		"F1 – nápověda   F2 – herní menu   Esc – pauza",
		"F5 – rychle uložit   F9 – načíst rychlé uložení",
		"",
		"Motorové rogalo (trike): Shift/Ctrl – páka plynu (drží polohu)",
		"  na zemi A/D – příďové kolo, Mezerník – brzda kol",
		"  ve vzduchu HRAZDA (realisticky obrácená): S – nos nahoru/zpomalit,",
		"  W – klesat/zrychlit, A/D – zatáčka obráceně (A = doprava)",
		"  Esc → Nastavení → „Intuitivní řízení rogala“ = arkádově (W nahoru, A vlevo)",
		"",
		"Ovladač: levá páčka pohyb, pravá páčka rozhlížení.",
	])
	_button("← Zpět", _back)
	_focus_first()


func _show_settings() -> void:
	_page = "settings"
	_clear("Nastavení", "Změny platí hned a uloží se.")
	_header("Grafika")
	_button("Grafika a výkon…  (teď: %s)" % GameSettings.PRESET_NAMES[settings.preset], _show_graphics)
	_check("Celá obrazovka", settings.fullscreen, func(on): settings.fullscreen = on)
	_header("Ovládání")
	_slider("Citlivost myši", 0.2, 3.0, 0.05, settings.mouse_sens, func(x): settings.mouse_sens = x, "%.2f×")
	_check("Obrátit osu Y myši", settings.invert_y, func(on): settings.invert_y = on)
	_check("Intuitivní řízení rogala (W = nos nahoru; výchozí realistické obrácené)", settings.trike_intuitive,
		func(on): settings.trike_intuitive = on)
	_slider("Zorné pole (FOV)", 55.0, 95.0, 1.0, settings.fov, func(x): settings.fov = x, "%d°")
	_header("Zvuk")
	_slider("Hlasitost", 0.0, 1.0, 0.05, settings.volume, func(x): settings.volume = x, "", true)
	_header("Výkon")
	var row := _row("Vertikální synchronizace")
	var ob := OptionButton.new()
	for n in GameSettings.VSYNC_NAMES:
		ob.add_item(n)
	ob.selected = settings.vsync
	ob.disabled = settings.vsync_from_args
	ob.item_selected.connect(func(i):
		settings.vsync = i
		settings.apply(client))
	row.add_child(ob)
	if settings.vsync_from_args:
		_label(_list, "   (vsync je teď dán parametrem --vsync / --novsync)", 13)
	_check("Ukazovat FPS", settings.show_fps, func(on): settings.show_fps = on)
	_button("← Zpět", _back)
	_focus_first()


func _show_graphics() -> void:
	_page = "graphics"
	_clear("Grafika a výkon", "Když se hra seká, sniž nejdřív stíny, dohlednost a rozlišení 3D.\n" +
		"Předvolba nastaví vše najednou; změna jednotlivé volby ji přepne na Vlastní.")
	var pick_preset := func(i: int) -> void:
		settings.set_preset(i)
		settings.apply_graphics(client)
		_refresh_preset_label()
	_option("Předvolba", GameSettings.PRESET_NAMES.slice(0, 4), mini(settings.preset, 3), pick_preset, settings.preset == 4)
	_header("Vykreslovací backend")
	_option("Renderer", GameSettings.RENDERER_NAMES, GameSettings.RENDERER_VALUES.find(settings.renderer), func(i):
		settings.renderer = GameSettings.RENDERER_VALUES[i]
		settings.save_file())
	_label(_list, "   Projeví se až po restartu hry (zavřít a znovu spustit).", 13)
	_header("Rozlišení a kvalita obrazu")
	_gfx_option("Rozlišení 3D", GameSettings.SCALE_NAMES, "scale")
	_gfx_option("Zvětšení obrazu", GameSettings.UPSCALE_NAMES, "upscale")
	_gfx_option("Vyhlazování hran", GameSettings.AA_NAMES, "aa")
	_header("Barvy")
	_option("Podání barev světa", GameSettings.COLOR_NAMES, settings.color_mode, func(i):
		settings.color_mode = i
		settings.apply_graphics(client))
	_header("Scéna")
	_gfx_option("Stíny", GameSettings.SHADOW_NAMES, "shadows")
	_gfx_option("Dohlednost", GameSettings.VIEW_NAMES, "view")
	_gfx_option("Vegetace (květy, ovoce, listí)", GameSettings.VEG_NAMES, "veg")
	_gfx_option("Aktivita světa (NPC, zvířata, doprava)", GameSettings.SIM_NAMES, "sim")
	_check("Záře (bloom)", bool(settings.gfx["glow"]), func(on):
		settings.set_gfx("glow", on)
		_refresh_preset_label())
	_check("Stínování okolím (SSAO, náročné)", bool(settings.gfx["ssao"]), func(on):
		settings.set_gfx("ssao", on)
		_refresh_preset_label())
	_header("Výkon")
	_option("Strop FPS", GameSettings.FPS_NAMES, settings.fps_cap, func(i):
		settings.fps_cap = i
		settings.apply_graphics(client))
	if settings.maxfps_from_args:
		_label(_list, "   (strop FPS je teď dán parametrem --maxfps)", 13)
	_button("← Zpět", _back)
	_focus_first()


## Rozbalovací volba grafiky `key` (index do tabulky v GameSettings).
func _gfx_option(text: String, names: Array, key: String) -> void:
	_option(text, names, int(settings.gfx[key]), func(i):
		settings.set_gfx(key, i)
		settings.apply_graphics(client)
		_refresh_preset_label())


func _option(text: String, names: Array, sel: int, cb: Callable, custom := false) -> OptionButton:
	var row := _row(text)
	var ob := OptionButton.new()
	for n in names:
		ob.add_item(n)
	if custom:
		ob.add_item("Vlastní")
		sel = names.size()
	ob.selected = sel
	ob.custom_minimum_size = Vector2(230, 0)
	ob.item_selected.connect(cb)
	row.add_child(ob)
	return ob


## Po změně jednotlivé volby ukáže v řádku Předvolba „Vlastní“ (nebo předvolbu, která zase sedí).
func _refresh_preset_label() -> void:
	_show_graphics.call_deferred()


func _row(text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	_list.add_child(row)
	var l := _label(row, text, 17)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return row


func _slider(text: String, lo: float, hi: float, step: float, val: float, setter: Callable, fmt: String,
		percent := false) -> void:
	var row := _row(text)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = val
	s.custom_minimum_size = Vector2(200, 0)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(s)
	var vl := _label(row, "", 16)
	vl.custom_minimum_size = Vector2(64, 0)
	var show_val := func(x: float): vl.text = ("%d %%" % roundi(x * 100.0)) if percent else (fmt % x)
	show_val.call(val)
	s.value_changed.connect(func(x: float):
		setter.call(x)
		show_val.call(x)
		settings.apply(client))


func _check(text: String, on: bool, setter: Callable) -> void:
	var cb := CheckButton.new()
	cb.text = text
	cb.button_pressed = on
	cb.add_theme_font_size_override("font_size", 17)
	cb.toggled.connect(func(x: bool):
		setter.call(x)
		settings.apply(client))
	_list.add_child(cb)


func _label(parent: Node, text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l
