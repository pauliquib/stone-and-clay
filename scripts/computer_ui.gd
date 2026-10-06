## Obrazovka počítače doma (M3.4) – klient: stylizovaný „starý OS“ přes celou obrazovku (tyrkysová plocha, šedé okno s modrým
## pruhem, ikony Prohlížeč / Pošta / Banka / Hry, hlavní panel s hodinami). Otevírá se E u stolu s PC v domově
## (`InteriorMenu` → `ComputerUI.open_for(client)`), hráč si sedne na židli (`Interior.spots["pc_seat"]`), Esc = vypnout.
## Všechno je smyšlené (weby, banka, e-shop – žádné skutečné značky a adresy; adresy mají smyšlené schéma „vesnet://“).
## Logiku a data drží server (`World.computer` – `Computer`); obrazovka jen volá jeho API s id hráče a výsledek ukáže
## ve stavovém řádku dole. Prohlížeč: eŠuplík, Bazárek, Práce v kraji, Moje banka, Obecní web, eTesty (`TestUI`).
## Hry: Miny (vlastní malá implementace, `MINES_*`).
class_name ComputerUI
extends Control

const DESK_BG := Color(0.0, 0.45, 0.47)
const WIN_BG := Color(0.77, 0.77, 0.75)
const TITLE_BG := Color(0.04, 0.14, 0.52)
const PAGE_BG := Color(0.98, 0.98, 0.96)
const BAR_BG := Color(0.72, 0.72, 0.7)
const TEXT := Color(0.08, 0.08, 0.1)
const DIM := Color(0.35, 0.35, 0.38)
const OK_COL := Color(0.1, 0.5, 0.15)
const BAD_COL := Color(0.7, 0.12, 0.1)
const FONT := 15
const MINES_W := 9
const MINES_H := 9
const MINES_N := 10
const MINE_COLORS := [Color(0.1, 0.2, 0.8), Color(0.1, 0.5, 0.1), Color(0.8, 0.1, 0.1), Color(0.1, 0.1, 0.5),
	Color(0.5, 0.1, 0.1), Color(0.1, 0.5, 0.5), Color(0.1, 0.1, 0.1), Color(0.4, 0.4, 0.4)]
## Záložky prohlížeče: [stránka, název, smyšlená adresa]
const SITES := [["eshop", "eŠuplík", "vesnet://esuplik/"], ["bazar", "Bazárek", "vesnet://bazarek/"],
	["prace", "Práce v kraji", "vesnet://prace-v-kraji/"], ["banka", "Moje banka", "vesnet://moje-banka/"],
	["obec", "Obecní web", "vesnet://obec/"], ["etesty", "eTesty", "vesnet://etesty/"],
	["letectvi", "Letectví – ÚVL", "vesnet://letectvi/"],
	["autoskola", "Autoškola Volant", "vesnet://autoskola-volant/"]]

var client: Node
var world: World
var hud: Hud
var player: Player
var pid := 0
var _window: PanelContainer
var _win_title: Label
var _nav: VBoxContainer
var _bookmarks: HBoxContainer
var _address: Label
var _scroll: ScrollContainer
var _body: VBoxContainer
var _status: Label
var _clock_lbl: Label
var _page := ""
var _cart := {}                    # id předmětu → počet (košík eŠuplíku, jen na obrazovce)
var _cod := false
var _eshop_sec := 0
var _mail_i := -1
var _clock_t := 0.0
# miny
var _mines: Array = []
var _opened: Array = []
var _flags: Array = []
var _mine_btns: Array = []
var _mines_state := ""              # "", "hra", "vyhra", "prohra"
var _mines_first := true
var _mines_info: Label


## Otevře počítač pro lokálního hráče (uzel se vytvoří jednou pod HUD).
static func open_for(cl: Node) -> void:
	var h: Hud = cl.hud
	var ui: ComputerUI = h.get_node_or_null("Pocitac")
	if ui == null:
		ui = ComputerUI.new()
		ui.name = "Pocitac"
		h.add_child(ui)
		ui._build(cl)
	ui.open()


func _build(cl: Node) -> void:
	client = cl
	world = cl.world
	hud = cl.hud
	player = cl.player
	pid = cl.pid
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = DESK_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# ikony na ploše
	var icons := VBoxContainer.new()
	icons.position = Vector2(18, 18)
	icons.add_theme_constant_override("separation", 14)
	add_child(icons)
	_desk_icon(icons, "Prohlížeč", Color(0.25, 0.55, 0.95), func(): _open_browser("eshop"))
	_desk_icon(icons, "Pošta", Color(0.95, 0.85, 0.3), _open_mail)
	_desk_icon(icons, "Banka", Color(0.3, 0.7, 0.4), func(): _open_browser("banka"))
	_desk_icon(icons, "Hry", Color(0.85, 0.35, 0.35), _open_games)
	# hlavní panel
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", _box(BAR_BG, 2, Color(0.95, 0.95, 0.95)))
	bar.anchor_left = 0.0
	bar.anchor_right = 1.0
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_top = -38
	add_child(bar)
	var bh := HBoxContainer.new()
	bar.add_child(bh)
	var start := _btn(bh, "Start – plocha", _close_window)
	start.add_theme_font_size_override("font_size", 15)
	_status = _label(bh, "", 14)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.clip_text = true
	_clock_lbl = _label(bh, "", 14)
	_btn(bh, "Vypnout (Esc)", close)
	# okno
	_window = PanelContainer.new()
	_window.add_theme_stylebox_override("panel", _box(WIN_BG, 3, Color(0.95, 0.95, 0.95)))
	_window.anchor_right = 1.0
	_window.anchor_bottom = 1.0
	_window.offset_left = 180
	_window.offset_top = 16
	_window.offset_right = -24
	_window.offset_bottom = -50
	add_child(_window)
	var wv := VBoxContainer.new()
	_window.add_child(wv)
	var tb := PanelContainer.new()
	tb.add_theme_stylebox_override("panel", _box(TITLE_BG, 0, TITLE_BG))
	wv.add_child(tb)
	var th := HBoxContainer.new()
	tb.add_child(th)
	_win_title = _label(th, "", 16)
	_win_title.add_theme_color_override("font_color", Color.WHITE)
	_win_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn(th, " X ", _close_window)
	_nav = VBoxContainer.new()
	wv.add_child(_nav)
	_bookmarks = HBoxContainer.new()
	_nav.add_child(_bookmarks)
	for s in SITES:
		var page := String(s[0])
		_btn(_bookmarks, String(s[1]), func(): _show(page))
	var ah := HBoxContainer.new()
	_nav.add_child(ah)
	_label(ah, "Adresa:", 14)
	var addr_bg := PanelContainer.new()
	addr_bg.add_theme_stylebox_override("panel", _box(Color.WHITE, 1, DIM))
	addr_bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ah.add_child(addr_bg)
	_address = _label(addr_bg, "", 14)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	wv.add_child(_scroll)
	var page_bg := PanelContainer.new()
	page_bg.add_theme_stylebox_override("panel", _box(PAGE_BG, 1, DIM, 14))
	page_bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_bg.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_child(page_bg)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 6)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_bg.add_child(_body)
	_window.visible = false


# ------------------------------------------------------------------ otevření / zavření

func open() -> void:
	if player.car != null or player.busy or player.fallen > 0.0:
		return
	hud.close_menu()
	visible = true
	hud.menu_open = true
	player.controls_locked = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var it: Interior = world.interiors.get(player.inside)
	if it and it.spots.has("pc_seat"):
		var sp: Array = it.spots["pc_seat"]
		player.teleport(sp[0] as Vector3, float(sp[1]), false)
	player.visual.pose = "sit"
	_close_window()
	var n: int = world.computer.unread(pid) if world.computer else 0
	_say("Počítač naběhl. %s" % ("Máš %d nepřečtených e-mailů." % n if n > 0 else "Žádná nová pošta."))
	_update_clock()


func close() -> void:
	if not visible:
		return
	visible = false
	hud.menu_open = false
	player.controls_locked = false
	player.visual.pose = "stand"
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey:
		if event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			close()
		get_viewport().set_input_as_handled()      # klávesy nejdou do hry (mapa, deník, pauza…), jen do obrazovky PC


func _process(delta: float) -> void:
	if not visible:
		return
	_clock_t -= delta
	if _clock_t <= 0.0:
		_clock_t = 1.0
		_update_clock()


func _update_clock() -> void:
	if world.clock:
		_clock_lbl.text = "  %s  %s  " % [world.clock.date_text(), world.clock.text()]


func _say(t: String) -> void:
	_status.text = "  " + t


func _close_window() -> void:
	_window.visible = false
	_page = ""


func _open_browser(page: String) -> void:
	_window.visible = true
	_nav.visible = true
	_show(page)


func _open_mail() -> void:
	_window.visible = true
	_nav.visible = false
	_mail_i = -1
	_show("posta")


func _open_games() -> void:
	_window.visible = true
	_nav.visible = false
	_show("hry")


## Smaže obsah stránky (skryje a uvolní – volá se i z tlačítka, které tím samo zmizí).
func _clear_body() -> void:
	for c in _body.get_children():
		c.visible = false
		c.queue_free()


## Překreslí stránku `page` (a nastaví titulek okna a adresu).
func _show(page: String) -> void:
	_page = page
	_clear_body()
	var title := page
	for s in SITES:
		if String(s[0]) == page:
			title = String(s[1])
			_address.text = " " + String(s[2])
	var pc: Computer = world.computer
	if pc == null:
		_text("Síť je nedostupná.")
		return
	match page:
		"eshop":
			_p_eshop(pc)
		"bazar":
			_p_bazar(pc)
		"prace":
			_p_prace(pc)
		"banka":
			_p_banka(pc)
		"obec":
			_p_obec(pc)
		"etesty":
			_p_etesty(pc)
		"letectvi":
			_p_letectvi()
		"autoskola":
			title = "Autoškola Volant"
			_p_autoskola()
		"posta":
			title = "Pošta"
			_p_posta(pc)
		"hry":
			title = "Hry – Miny"
			_p_miny(pc)
	_win_title.text = "  %s%s" % [title, " – Prohlížeč" if _nav.visible else ""]
	_scroll.scroll_vertical = 0


# ------------------------------------------------------------------ eŠuplík

func _p_eshop(pc: Computer) -> void:
	_h1("eŠuplík – všechno do šuplíku")
	_text("Ceny o %d %% nižší než v obchodě · doprava %s · doručíme za 1–2 dny ke dveřím domova (%s). Na účtu %s, v hotovosti %s." % [
		roundi(Computer.ESHOP_DISCOUNT * 100.0), Bazaar.kc(Computer.SHIPPING_KC), world.home_label(pid), Bazaar.kc(player.bank),
		Bazaar.kc(player.money)], DIM)
	var cat := pc.catalog()
	if cat.is_empty():
		_text("Sklad je prázdný.")
		return
	_eshop_sec = clampi(_eshop_sec, 0, cat.size() - 1)
	var tabs := HFlowContainer.new()
	_body.add_child(tabs)
	for i in cat.size():
		var idx := i
		var b := _btn(tabs, String(cat[i][0]), func():
			_eshop_sec = idx
			_show("eshop"))
		b.disabled = i == _eshop_sec
	_h2(String(cat[_eshop_sec][0]))
	for r in cat[_eshop_sec][1]:
		var id := String(r[0])
		var row := _row()
		var l := _label(row, ItemsDB.name_of(id), FONT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_label(row, Bazaar.kc(int(r[1])), FONT)
		var n := int(_cart.get(id, 0))
		_btn(row, "Do košíku%s" % (" (%d)" % n if n > 0 else ""), func():
			_cart[id] = int(_cart.get(id, 0)) + 1
			_say("Přidáno do košíku: %s." % ItemsDB.name_of(id))
			_show("eshop"))
	_h2("Košík")
	if _cart.is_empty():
		_text("Košík je prázdný.", DIM)
	else:
		for id in _cart.keys():
			var iid := String(id)
			var row := _row()
			var l := _label(row, "%d× %s" % [int(_cart[id]), ItemsDB.name_of(iid)], FONT)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_label(row, Bazaar.kc(pc.price_of(iid) * int(_cart[id])), FONT)
			_btn(row, " − ", func():
				_cart[iid] = int(_cart.get(iid, 0)) - 1
				if int(_cart[iid]) <= 0:
					_cart.erase(iid)
				_show("eshop"))
		var total := pc.cart_total(_cart) + Computer.SHIPPING_KC + (Computer.COD_KC if _cod else 0)
		var cb := CheckBox.new()
		cb.text = "Dobírka – zaplatím hotově při převzetí (+%s)" % Bazaar.kc(Computer.COD_KC)
		cb.button_pressed = _cod
		cb.add_theme_color_override("font_color", TEXT)
		cb.add_theme_color_override("font_pressed_color", TEXT)
		cb.add_theme_color_override("font_hover_color", TEXT)
		cb.toggled.connect(func(on: bool):
			_cod = on
			_show("eshop"))
		_body.add_child(cb)
		_text("[b]Celkem %s[/b] (zboží %s + doprava %s%s) – %s." % [Bazaar.kc(total), Bazaar.kc(pc.cart_total(_cart)),
			Bazaar.kc(Computer.SHIPPING_KC), " + dobírka %s" % Bazaar.kc(Computer.COD_KC) if _cod else "",
			"platíš při převzetí" if _cod else "zaplatí se z účtu"])
		var row2 := _row()
		_btn(row2, "Objednat", func():
			var res := pc.order(pid, _cart, _cod)
			if res.begins_with("Objednáno"):
				_cart.clear()
			_say(res)
			_show("eshop"))
		_btn(row2, "Vysypat košík", func():
			_cart.clear()
			_show("eshop"))
	_h2("Moje objednávky")
	var ords: Array = pc.orders(pid)
	if ords.is_empty():
		_text("Zatím nic.", DIM)
	for i in range(ords.size() - 1, -1, -1):
		var o: Dictionary = ords[i]
		var names := []
		for id in o["items"]:
			names.append("%d× %s" % [int(o["items"][id]), ItemsDB.name_of(String(id))])
		var stt := {"cesta": "na cestě – dorazí %s" % pc._day_text(int(o["jd"])), "doruceno": "[color=#1a7f2a]leží u dveří – E vybrat[/color]",
			"vyzvednuto": "vyzvednuto"}
		_text("č. %d · %s · %s%s · %s" % [int(o["no"]), ", ".join(names), Bazaar.kc(int(o["total"])), " (dobírka)" if bool(o["cod"]) else "",
			stt.get(String(o["state"]), String(o["state"]))])


# ------------------------------------------------------------------ Bazárek

func _p_bazar(pc: Computer) -> void:
	_h1("Bazárek – auta, motorky a všechno, co jezdí")
	var bz: Bazaar = world.bazaar
	if bz == null or not bz.ok:
		_text("Bazárek je mimo provoz.")
		return
	_text("Stejná nabídka jako bazar u silnice, platba z účtu (máš %s). Vozidlo přistavíme k domovu (%s). Nabídka se mění každý týden." % [
		Bazaar.kc(player.bank), world.home_label(pid)], DIM)
	var any := false
	for o in bz.offers():
		if bool(o["sold"]):
			continue
		any = true
		var key := String(o["key"])
		var c := CarModel.catalog(String(o["id"]))
		var row := _row()
		var l := _label(row, "%s, r. v. %d · poškození %d %% · ŘP %s" % [o["name"], int(o["year"]), int(o["damage"]), c.get("skupina_rp", "?")], FONT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_label(row, Bazaar.kc(int(o["price"])), FONT)
		var b := _btn(row, "Koupit", func():
			_say(pc.bazaar_buy(pid, key))
			_show("bazar"))
		b.disabled = player.bank < int(o["price"])
	if not any:
		_text("Tento týden je vyprodáno. Zkus to příští týden.", DIM)
	_h2("Prodat moje vozidlo")
	_text("Vykoupíme vozidla koupená v bazaru za %d %% ceny podle poškození – kdekoli stojí, kupec si je odveze. Peníze přijdou na účet." % roundi(Bazaar.SELL_RATIO * 100.0), DIM)
	var mine := pc.bazaar_sellable(pid)
	if mine.is_empty():
		_text("Nemáš nic k prodeji (rodinná vozidla – Oktávka, kolo, Javor – se neprodávají).", DIM)
	for car in mine:
		var cc: Car = car
		var row := _row()
		var l := _label(row, "%s (poškození %d %%)" % [cc.model.spec.get("name", cc.model_id), roundi(cc.damage)], FONT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_label(row, Bazaar.kc(bz.sell_value(cc)), FONT)
		_btn(row, "Prodat", func():
			_say(pc.bazaar_sell(pid, cc))
			_show("bazar"))
	_h2("Inzeráty – zvířata")
	for t in pc.animal_ads():
		_text("• " + String(t))
	_text("Zvířata si pořídíš u cedule hospodářství u usedlosti (jen s vlastním domem).", DIM)


# ------------------------------------------------------------------ Práce v kraji

func _p_prace(pc: Computer) -> void:
	_h1("Práce v kraji – brigády a zaměstnání")
	var jb: Jobs = world.jobs.get(pid)
	if jb == null:
		_text("Portál je mimo provoz.")
		return
	if jb.current != "":
		var j := Jobs.job(jb.current)
		_text("Teď pracuješ jako [b]%s[/b] (%s). Výplata: %s." % [j.get("nazev", ""), j.get("zamestnavatel", ""),
			"na účet" if jb.pay_bank else "hotově u zaměstnavatele"])
		if not Jobs.is_contract(j):
			var row := _row()
			_btn(row, "Posílat výplatu %s" % ("hotově" if jb.pay_bank else "na účet"), func():
				jb.set_pay_bank(not jb.pay_bank)
				_say("Výplata: %s." % ("na účet" if jb.pay_bank else "hotově"))
				_show("prace"))
	_text("Odpověz na inzerát – přijde pozvánka na pohovor (platí %d dní). Pak zajdi za vedoucím, na pohovoru máš lepší šanci." % Jobs.INVITE_DAYS, DIM)
	for id in Jobs.all_jobs():
		var jid := String(id)
		var j := Jobs.job(jid)
		_h2("%s – %s" % [j.get("nazev", jid), j.get("zamestnavatel", "")])
		var pay := "%d Kč/h hrubého" % int(j.get("mzda_hod", 0))
		if Jobs.is_contract(j):
			var od: Array = (j.get("zakazka", {}) as Dictionary).get("odmena", [0, 0])
			pay = "%d–%d Kč za zakázku" % [int(od[0]) if not od.is_empty() else 0, int(od[-1]) if not od.is_empty() else 0]
		_text("%s · %s · vedoucí %s" % [pay, Jobs.shifts_text(j), j.get("vedouci", "?")], DIM)
		if String(j.get("popis", "")) != "":
			_text(String(j["popis"]))
		var chk := jb.can_apply(jid)
		for c in chk["checks"]:
			_text("[color=#%s]%s %s[/color]" % ["1a7f2a" if c[1] else "8a8a8a", "✔" if c[1] else "✘", c[0]])
		var row := _row()
		var inv := int(jb.invited.get(jid, -1)) >= world.clock.jd()
		var b := _btn(row, "Odpovědět na inzerát", func():
			_say(pc.answer_ad(pid, jid))
			_show("prace"))
		b.disabled = jb.current == jid or inv
		if jb.current == jid:
			_label(row, "  – tady pracuješ", 14)
		elif inv:
			_label(row, "  – pozvánka na pohovor platí", 14).add_theme_color_override("font_color", OK_COL)
		elif not chk["ok"]:
			_label(row, "  – zatím nesplňuješ vše (pohovor jen se splněnými požadavky)", 14).add_theme_color_override("font_color", DIM)


# ------------------------------------------------------------------ Moje banka

func _p_banka(pc: Computer) -> void:
	_h1("Moje banka – internetové bankovnictví")
	_text("[b]Zůstatek na účtu: %s[/b]      Hotovost u sebe: %s" % [Bazaar.kc(player.bank), Bazaar.kc(player.money)])
	_text("Hotovost vložíš a vybereš jen v bankomatu – u Potravin a u obecního úřadu. (Smyšlená banka.)", DIM)
	_h2("Trvalý příkaz – nájem")
	var est: Estate = world.estate
	if est and bool(est.home_of(pid).get("rent", false)):
		_text(est.rent_text(pid))
		var on := pc.standing_rent(pid)
		var row := _row()
		_label(row, "Trvalý příkaz: %s  " % ("ZAPNUTÝ – nájem se platí z účtu" if on else "vypnutý – nájem se strhává z hotovosti"), FONT)
		_btn(row, "Zrušit" if on else "Nastavit", func():
			_say(pc.set_standing_rent(pid, not on))
			_show("banka"))
	else:
		_text("Bydlíš ve vlastním – nájem neplatíš.", DIM)
	_h2("Pokuty a dluhy")
	var due := pc.unpaid_fines(pid)
	if due <= 0:
		_text("Žádné nezaplacené pokuty.", DIM)
	else:
		for dl in world.debts.list(pid):
			_text("• %s – %s (splatnost %s, stav: %s)" % [dl["text"], Bazaar.kc(int(dl["kc"])),
				_jd_text(int(dl["due_jd"])),
				Debts.STAGE_NAMES.get(String(dl["stage"]), String(dl["stage"]))])
		var row := _row()
		_label(row, "Nezaplaceno celkem: %s  " % Bazaar.kc(due), FONT).add_theme_color_override("font_color", BAD_COL)
		var b := _btn(row, "Zaplatit z účtu", func():
			_say(pc.pay_fines(pid))
			_show("banka"))
		b.disabled = player.bank <= 0
		_text("Zaplatit jde i na úřadě (hotovost). Při nezaplacení: upomínka (+%s), po %d dnech exekuce z účtu." % [Bazaar.kc(Debts.REMINDER_FEE), Debts.ENFORCE_DAYS], DIM)
	var jb: Jobs = world.jobs.get(pid)
	if jb and jb.current != "" and not Jobs.is_contract(Jobs.job(jb.current)):
		_h2("Výplata z práce")
		var row3 := _row()
		_label(row3, "%s: výplata %s  " % [jb.title(), "na účet" if jb.pay_bank else "hotově u zaměstnavatele"], FONT)
		_btn(row3, "Přepnout na %s" % ("hotovost" if jb.pay_bank else "účet"), func():
			jb.set_pay_bank(not jb.pay_bank)
			_show("banka"))
	_h2("Pohyby na účtu")
	var lg: Array = pc.bank_log(pid)
	if lg.is_empty():
		_text("Zatím žádné pohyby.", DIM)
	var shown := 0
	for i in range(lg.size() - 1, -1, -1):
		var e: Dictionary = lg[i]
		var kc := int(e["kc"])
		_text("den %d, %s   [color=#%s]%s%s[/color]   %s" % [int(float(e["t"]) / 1440.0) + 1, _hm(float(e["t"])),
			"1a7f2a" if kc > 0 else "b3261e", "+" if kc > 0 else "", Bazaar.kc(kc), e["text"]])
		shown += 1
		if shown >= 20:
			break


# ------------------------------------------------------------------ Obecní web

func _p_obec(pc: Computer) -> void:
	_h1("Obecní web – Zprávy z návsi")
	_text("Neoficiální informační stránka obce. (Vymyšlené – bez znaku a symbolů obce.)", DIM)
	_h2("Kalendář akcí")
	var cal := pc.calendar(60)
	if cal.is_empty():
		_text("V nejbližších dvou měsících nic neplánujeme. Zajděte aspoň do hospody.", DIM)
	for c in cal:
		_text("• [b]%s[/b] – %s" % [pc.date_text(int(c[0])), c[1]])
	if world.village_events and world.village_events.names_text() != "":
		_text("Právě probíhá: [b]%s[/b]" % world.village_events.names_text(), OK_COL)
	_h2("Otevírací doby dnes")
	for h in pc.opening_hours():
		_text("• %s: %s%s" % [h[0], h[1], "  [color=#1a7f2a](teď otevřeno)[/color]" if h[2] else "  [color=#8a8a8a](teď zavřeno)[/color]"])
	_h2("Úřední deska")
	for n in Computer.NOTICE_BOARD + (world.vyhlasky.board_lines() if world.vyhlasky else []):
		_text("• [b]%s[/b] – %s" % [n[0], n[1]])
	_h2("Diskuse – co se povídá")
	_text("Příspěvky jsou anonymní, obec za ně neodpovídá.", DIM)
	for g in pc.gossip(pid):
		var t := float(g.get("t", -1.0))
		_text("[b]%s[/b]%s: %s" % [g.get("who", "anonym"), (" (den %d)" % (int(t / 1440.0) + 1)) if t >= 0.0 else "", g["text"]])


# ------------------------------------------------------------------ eTesty

func _p_etesty(pc: Computer) -> void:
	_h1("eTesty – cvičné testy nanečisto")
	_text("Zjednodušená herní simulace. Otázky jsou vlastní formulace, ne oficiální testy.", DIM)
	for id in Computer.TESTS:
		var tid := String(id)
		var t: Array = Computer.TESTS[id]
		var row := _row()
		var l := _label(row, String(t[0]), FONT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var stt := pc.test_stats(pid, tid)
		if not stt.is_empty():
			_label(row, "nejlépe %d / %d (pokusů %d)  " % [int(stt["best"]), int(stt["total"]), int(stt["n"])], 14)
		if String(t[1]) == "":
			_label(row, "připravujeme (%s)" % t[2], 14).add_theme_color_override("font_color", DIM)
		else:
			_btn(row, "Spustit", func(): _run_test(tid))


func _run_test(tid: String) -> void:
	var d := Computer.load_test(tid)
	if d.is_empty():
		_say("Test se nepodařilo načíst.")
		return
	_clear_body()
	_h1(String(d.get("nazev", tid)))
	_text(String(d.get("popis", "")), DIM)
	var tu := TestUI.new()
	_body.add_child(tu)
	tu.setup(d)
	tu.finished.connect(func(score: int, total: int, passed: bool):
		world.computer.record_test(pid, tid, score, total, passed)
		_say("Test: %d / %d – %s." % [score, total, "prošel jsi" if passed else "neprošel jsi"]))
	var row := _row()
	_btn(row, "← Zpět na eTesty", func(): _show("etesty"))


# ------------------------------------------------------------------ Letectví – ÚVL (M6.1)

## Portál bezpilotních letů (smyšlený ÚVL): registrace provozovatele, osvědčení A1/A3 (eTest „drony“),
## flotila dronů (baterie, poškození), nabíjení a opravy. Pravidla ve hře: max 120 m, ne nad lidmi,
## VLOS 500 m, soukromí nad cizími pozemky – zjednodušená simulace, ne právní rada.
## M4.1 autoškola: kurz skupiny (platba z účtu), teorie (eTest „autoskola“), výcvikové jízdy, přezkoušení po 12 bodech.
func _p_autoskola() -> void:
	_h1("Autoškola Volant (smyšlená)")
	_text("Smyšlená autoškola obce. Zjednodušená herní simulace pravidel (361/2000 Sb.) – nejde o právní radu ani oficiální zkoušku.", DIM)
	var rp: Permits = world.permits
	var skupiny := ", ".join(PackedStringArray(rp.subs(pid, "ridicsky")))
	_text("Tvoje skupiny řidičáku: [b]%s[/b]" % (skupiny if skupiny != "" else "žádné"), OK_COL if skupiny != "" else DIM)
	var odebrano := not rp.is_revoked(pid, "ridicsky").is_empty()
	if odebrano:
		_text("Řidičák je [b]odebrán[/b] (12 bodů) – nutné přezkoušení. Po zákazu řízení složíš teorii a jízdy znovu.", BAD_COL)
	var s: Dictionary = world.auto_school(pid)
	if not bool(s.get("zaplaceno", false)):
		_h2("Kurzy")
		for g in World.AUTO_KURZ_KC:
			if g == "B":
				continue
			var gg: String = g
			_btn(_row(), "Kurz skupiny %s (%s z účtu)" % [gg, Bazaar.kc(int(World.AUTO_KURZ_KC[gg]))], func():
				_say(world.auto_enroll(pid, gg))
				_show("autoskola"))
		if odebrano:
			_btn(_row(), "Přezkoušení – skupina B (%s z účtu)" % Bazaar.kc(World.AUTO_PREZKOUSENI_KC), func():
				_say(world.auto_enroll(pid, "B"))
				_show("autoskola"))
	else:
		_h2("Výcvik – skupina %s" % String(s.get("skupina", "")))
		var teorie := bool(s.get("teorie", false))
		var jizdy := int(s.get("jizdy", 0))
		_text("• Teorie: %s" % ("[b]složeno[/b]" if teorie else "nesloženo – slož eTest „autoskola“"), OK_COL if teorie else TEXT)
		if not teorie:
			_btn(_row(), "Složit teorii (eTest autoškola)", func(): _run_test("autoskola"))
		_text("• Výcvikové jízdy: [b]%d / %d[/b] – nasedni do vozidla skupiny %s, odjeď aspoň %d m od úřadu " % [
			jizdy, World.AUTO_JIZD_NUTNE, String(s.get("skupina", "")), int(World.AUTO_JIZDA_MIN_M)] +
			"a vrať se k jeho dveřím (instruktor hodnotí rádiem).")


func _p_letectvi() -> void:
	_h1("Letectví – portál bezpilotních letů")
	_text("Smyšlený portál Úřadu pro vzdušné lety (ÚVL) pro registraci a kvalifikaci pilotů UAS. Zjednodušená herní simulace pravidel " +
		"(EU 2019/947, ÚVL) – nejde o právní radu ani oficiální stránky.", DIM)
	# --- registrace provozovatele
	_h2("Registrace provozovatele (zdarma, okamžitá)")
	if world.permits == null:
		_text("Síť je nedostupná.")
		return
	if world.has_permit(pid, "dron_provozovatel", player.global_position):
		_text("[b]Registrován[/b] – registrační číslo [b]%s[/b] (vyznač na dronu). Každý dron s kamerou ho potřebuje." % world.permits.number(pid, "dron_provozovatel"), OK_COL)
	else:
		_text("Dron s kamerou se provozuje jen s registrací provozovatele. Bez ní hrozí pokuta, když tě při letu někdo uvidí.")
		_btn(_row(), "Registrovat provozovatele (zdarma)", func():
			_say(world.drone_register(pid))
			_show("letectvi"))
	# --- osvědčení A1/A3
	_h2("Osvědčení pilota A1/A3 (drony nad 250 g)")
	if world.has_permit(pid, "dron_a1a3", player.global_position):
		_text("[b]Vystaveno[/b] – osvědčení [b]%s[/b]. Smíš létat i s drony nad 250 g (120 m a pravidla stále platí)." % world.permits.number(pid, "dron_a1a3"), OK_COL)
	else:
		_text("Pro drony nad 250 g (např. Dron Ptáček Pro XL) je potřeba online test A1/A3 – 10 otázek, úspěch od 8 správných.")
		_btn(_row(), "Složit test A1/A3 (eTesty)", func(): _run_test("drony"))
	# --- flotila
	_h2("Moje drony")
	var fleet: Array = world.drone_fleet(pid)
	if fleet.is_empty():
		_text("Zatím žádný dron – koupíš ho v Potravinách nebo v eŠuplíku (sekce Drony a technika).", DIM)
	for d in fleet:
		var m := String(d["model"])
		var row := _row()
		var where := "ve světě" if bool(d["ve_svete"]) else ("v batohu" if bool(d["v_ruce"]) else "–")
		var l := _label(row, "%s (%s) · baterie %d %% · poškození %d %%" % [d["name"], where,
			roundi(float(d["bat"]) * 100.0), roundi(float(d["dmg"]))], FONT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var bc := _btn(row, "Nabít baterii", func():
			_say(world.drone_charge(pid, m))
			_show("letectvi"))
		bc.disabled = float(d["bat"]) >= 0.999
		var br := _btn(row, "Opravit (%s)" % Bazaar.kc(int(DroneModel.spec(m)["repair"])), func():
			_say(world.drone_repair(pid, m))
			_show("letectvi"))
		br.disabled = float(d["dmg"]) <= 0.0
	_text("Start drona: inventář (Tab) → detail dronu → Vzlétnout. Nabíjení jen tady u počítače (nabíječka je u stolu); " +
		"náhradní baterie se vymění sama při startu, když je ta v dronu pod ~85 %.", DIM)
	# --- M6.4 paramotor: létací škola, registrace, pojištění
	_h2("Létací škola – motorový paraglide (paramotor)")
	if world.has_permit(pid, "pilot_pg_motor", player.global_position):
		_text("[b]Pilotní průkaz vydán[/b] – evidenční číslo [b]%s[/b]. Přesto platí: min. 150 m nad obcí, " % world.permits.number(pid, "pilot_pg_motor") +
			"ne nad lidmi, ne v noci, ne v mracích.", OK_COL)
	else:
		var sk: Dictionary = world.computer.pg_school(pid)
		if not bool(sk.get("zaplaceno", false)):
			_text("Paramotor = sportovní létající zařízení – k pilotování potřebuješ pilotní průkaz z létací školy " +
				"(teorie + %d výcvikových vzletů s instruktorem rádiem). Cena výcviku %s." % [World.PG_TRAIN_FLIGHTS, Bazaar.kc(World.PG_SCHOOL_KC)])
			_btn(_row(), "Zapsat se do létací školy (%s z účtu)" % Bazaar.kc(World.PG_SCHOOL_KC), func():
				_say(world.pg_enroll(pid))
				_show("letectvi"))
		else:
			var teorie := bool(sk.get("teorie", false))
			var lety := int(sk.get("lety", 0))
			_text("Výcvik zaplacen. Postup:")
			_text("• Teorie: %s" % ("[b]složeno[/b]" if teorie else "nesloženo – slož eTest „paramotor“"))
			if not teorie:
				_btn(_row(), "Složit teorii (eTest paramotor)", func(): _run_test("paramotor"))
			_text("• Výcvikové vzlety s instruktorem: [b]%d / %d[/b] – každý vzlet rozloženého paramotoru se počítá sám." % [lety, World.PG_TRAIN_FLIGHTS])
	_h2("Můj paramotor – registrace a pojištění")
	if world.has_permit(pid, "pg_registrace", player.global_position):
		_text("Registrován – poznávací značka [b]%s[/b] (vyznač na křídle)." % world.permits.number(pid, "pg_registrace"), OK_COL)
	else:
		_btn(_row(), "Registrovat stroj (%s)" % Bazaar.kc(World.PG_REG_KC), func():
			_say(world.pg_register(pid))
			_show("letectvi"))
	if world.has_permit(pid, "pg_pojisteni", player.global_position):
		_text("Pojištění odpovědnosti aktivní (%s)." % world.permits.number(pid, "pg_pojisteni"), OK_COL)
	else:
		_btn(_row(), "Pojistit odpovědnost (%s / rok)" % Bazaar.kc(World.PG_INSURANCE_KC), func():
			_say(world.pg_insure(pid))
			_show("letectvi"))
	_text("Paramotor koupíš v obchodě nebo v eŠuplíku (nový ~180 000 Kč, ojetý ~90 000 Kč). Start: inventář (Tab) → " +
		"detail → Připravit k letu – potřebuješ rovnou louku bez stromů (~50 m volno).", DIM)
	# --- M6.5 motorové rogalo / ultralehké: škola 75 000, teorie + 10 letů, registrace + pojištění
	_h2("Létací škola – ultralehké (motorové rogalo)")
	if world.has_permit(pid, "pilot_ul", player.global_position):
		_text("[b]Pilotní průkaz UL vydán[/b] – evidenční číslo [b]%s[/b]. Platí: jen z letiště, min. 150 m nad obcí, " % world.permits.number(pid, "pilot_ul") +
			"ne nad lidmi, ne v noci, ne v mracích.", OK_COL)
	else:
		var su: Dictionary = world.computer.ul_school(pid)
		if not bool(su.get("zaplaceno", false)):
			_text("Rogalo (motorizovaný závěsný kluzák) je ultralehké letadlo – potřebuješ pilotní průkaz ULL " +
				"(teorie + %d výcvikových letů s instruktorem). Výcvik stojí %s z účtu." % [
				World.UL_TRAIN_FLIGHTS, Bazaar.kc(World.UL_SCHOOL_KC)])
			_btn(_row(), "Zapsat se do školy UL (%s z účtu)" % Bazaar.kc(World.UL_SCHOOL_KC), func():
				_say(world.ul_enroll(pid))
				_show("letectvi"))
		else:
			var teorie_u := bool(su.get("teorie", false))
			var lety_u := int(su.get("lety", 0))
			_text("Výcvik zaplacen. Postup:")
			_text("• Teorie: %s" % ("[b]složeno[/b]" if teorie_u else "nesloženo – slož eTest „ultralehké“"))
			if not teorie_u:
				_btn(_row(), "Složit teorii (eTest ultralehké)", func(): _run_test("ul"))
			_text("• Výcvikové lety s instruktorem: [b]%d / %d[/b] – každý vzlet triku se počítá sám (rádio z letiště)." % [
				lety_u, World.UL_TRAIN_FLIGHTS])
	_h2("Můj stroj UL – registrace a pojištění")
	if world.has_permit(pid, "ul_registrace", player.global_position):
		_text("Registrován – poznávací značka [b]%s[/b] (vyznač na vozíku)." % world.permits.number(pid, "ul_registrace"), OK_COL)
	else:
		_btn(_row(), "Registrovat stroj (%s)" % Bazaar.kc(World.UL_REG_KC), func():
			_say(world.ul_register(pid))
			_show("letectvi"))
	if world.has_permit(pid, "ul_pojisteni", player.global_position):
		_text("Pojištění odpovědnosti aktivní (%s)." % world.permits.number(pid, "ul_pojisteni"), OK_COL)
	else:
		_btn(_row(), "Pojistit odpovědnost (%s / rok)" % Bazaar.kc(World.UL_INSURANCE_KC), func():
			_say(world.ul_insure(pid))
			_show("letectvi"))
	_text("Ojeté rogalo (%s hotově) se prodává na inzerát u hangáru polního letiště pod vesnicí (dráha ~270 m). " % Bazaar.kc(World.UL_TRIKE_KC) +
		"Létá se jen z letiště; ovládání hrazdou je obrácené – viz F1 nápověda.", DIM)
	_h2("Připomenutí pravidel (zjednodušeně)")
	for t in ["Let nejvýše 120 m nad zemí (AGL) – výš je přestupek, dron stoupání sám odepře.",
		"Ne nad lidmi – pod dronem nesmí být osoba do ~25 m.",
		"Dron drž vizuálně na dohled (VLOS, ~500 m) a v dosahu signálu – jinak se sám vrací domů.",
		"Nízko a dlouho nad cizím pozemkem = narušování soukromí.",
		"Přestupky se zapisují jen když drona někdo uvidí nebo uslyší (~150 m v obci)."]:
		_text("• " + t)


# ------------------------------------------------------------------ Pošta

func _p_posta(pc: Computer) -> void:
	var box: Array = pc.mails(pid)
	if _mail_i >= 0 and _mail_i < box.size():
		pc.mark_read(pid, _mail_i)
		var m: Dictionary = box[_mail_i]
		_btn(_row(), "← Zpět na doručenou poštu", func():
			_mail_i = -1
			_show("posta"))
		_h1(String(m["subject"]))
		_text("Od: [b]%s[/b]   ·   den %d, %s" % [m["from"], int(float(m["t"]) / 1440.0) + 1, _hm(float(m["t"]))], DIM)
		_text(String(m["body"]))
		return
	_h1("Doručená pošta (%d, nepřečtených %d)" % [box.size(), pc.unread(pid)])
	var row0 := _row()
	_btn(row0, "Smazat přečtené", func():
		_say("Smazáno e-mailů: %d." % pc.delete_read(pid))
		_show("posta"))
	if box.is_empty():
		_text("Schránka je prázdná.", DIM)
	for i in range(box.size() - 1, -1, -1):
		var m: Dictionary = box[i]
		var idx := i
		var unread := not bool(m.get("read", false))
		var b := _btn(_body, "%s  %s – %s   (den %d, %s)" % ["●" if unread else "  ", m["from"], m["subject"], int(float(m["t"]) / 1440.0) + 1,
			_hm(float(m["t"]))], func():
			_mail_i = idx
			_show("posta"))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if unread:
			b.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))


# ------------------------------------------------------------------ Hry: Miny

func _p_miny(pc: Computer) -> void:
	_h1("Miny")
	_text("Levé tlačítko = odkrýt, pravé = vlaječka. Najdi všech %d min. Vyhráno her: %d." % [MINES_N, pc.games_won(pid)], DIM)
	if _mines_state == "":
		_mines_new()
	_mines_info = _label(_body, "", 16)
	var grid := GridContainer.new()
	grid.columns = MINES_W
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	_body.add_child(grid)
	_mine_btns = []
	for i in MINES_W * MINES_H:
		var b := Button.new()
		b.custom_minimum_size = Vector2(34, 34)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 17)
		b.gui_input.connect(_mine_click.bind(i))
		grid.add_child(b)
		_mine_btns.append(b)
	_btn(_row(), "Nová hra", func():
		_mines_new()
		_show("hry"))
	_mines_draw()


func _mines_new() -> void:
	_mines = []
	_opened = []
	_flags = []
	for i in MINES_W * MINES_H:
		_mines.append(false)
		_opened.append(false)
		_flags.append(false)
	_mines_state = "hra"
	_mines_first = true


func _mines_place(safe: int) -> void:
	var free := []
	for i in MINES_W * MINES_H:
		if i != safe and not (i in _nbrs(safe)):
			free.append(i)
	free.shuffle()
	for k in mini(MINES_N, free.size()):
		_mines[int(free[k])] = true


func _nbrs(i: int) -> Array:
	var out := []
	var x := i % MINES_W
	var y := i / MINES_W
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var nx: int = x + dx
			var ny: int = y + dy
			if nx >= 0 and nx < MINES_W and ny >= 0 and ny < MINES_H:
				out.append(ny * MINES_W + nx)
	return out


func _count(i: int) -> int:
	var n := 0
	for j in _nbrs(i):
		if _mines[j]:
			n += 1
	return n


func _mine_click(event: InputEvent, i: int) -> void:
	if _mines_state != "hra" or not (event is InputEventMouseButton) or not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if not _opened[i]:
			_flags[i] = not _flags[i]
	elif event.button_index == MOUSE_BUTTON_LEFT:
		if _flags[i] or _opened[i]:
			return
		if _mines_first:
			_mines_first = false
			_mines_place(i)
		if _mines[i]:
			_mines_state = "prohra"
		else:
			_reveal(i)
			var closed := 0
			for k in _opened.size():
				if not _opened[k]:
					closed += 1
			if closed == MINES_N:
				_mines_state = "vyhra"
				world.computer.game_won(pid)
				_say("Miny: vyhráno! Tohle by děda nedal.")
	else:
		return
	_mines_draw()


func _reveal(i: int) -> void:
	var stack := [i]
	while not stack.is_empty():
		var k: int = stack.pop_back()
		if _opened[k] or _flags[k]:
			continue
		_opened[k] = true
		if _count(k) == 0:
			for j in _nbrs(k):
				if not _opened[j] and not _mines[j]:
					stack.append(j)


func _mines_draw() -> void:
	var left := MINES_N
	for i in _flags.size():
		if _flags[i]:
			left -= 1
	match _mines_state:
		"vyhra":
			_mines_info.text = "Vyhrál jsi!"
		"prohra":
			_mines_info.text = "Bum! Šlápl jsi na minu. Zkus novou hru."
		_:
			_mines_info.text = "Zbývá min: %d" % left
	for i in _mine_btns.size():
		var b: Button = _mine_btns[i]
		b.remove_theme_color_override("font_color")
		b.remove_theme_color_override("font_disabled_color")
		if _opened[i]:
			var n := _count(i)
			b.text = str(n) if n > 0 else ""
			b.disabled = true
			if n > 0:
				b.add_theme_color_override("font_disabled_color", MINE_COLORS[n - 1].lightened(0.35))
		elif _mines_state == "prohra" and _mines[i]:
			b.text = "*"
			b.disabled = true
			b.add_theme_color_override("font_disabled_color", Color(1.0, 0.3, 0.2))
		else:
			b.text = "P" if _flags[i] else ""
			b.disabled = false
			if _flags[i]:
				b.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3))


# ------------------------------------------------------------------ stavebnice UI

static func _box(bg: Color, border: int, border_col: Color, pad := 4) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(border)
	sb.border_color = border_col
	sb.set_content_margin_all(pad)
	return sb


func _label(parent: Node, text: String, fsize: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", TEXT)
	parent.add_child(l)
	return l


func _btn(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 14)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _row() -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 8)
	_body.add_child(r)
	return r


func _text(bb: String, col := TEXT) -> RichTextLabel:
	var t := RichTextLabel.new()
	t.bbcode_enabled = true
	t.fit_content = true
	t.scroll_active = false
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.add_theme_color_override("default_color", col)
	t.add_theme_font_size_override("normal_font_size", FONT)
	t.add_theme_font_size_override("bold_font_size", FONT)
	t.text = bb
	_body.add_child(t)
	return t


func _h1(t: String) -> void:
	var l := _label(_body, t, 22)
	l.add_theme_color_override("font_color", TITLE_BG)


func _h2(t: String) -> void:
	var sep := HSeparator.new()
	_body.add_child(sep)
	var l := _label(_body, t, 18)
	l.add_theme_color_override("font_color", Color(0.15, 0.2, 0.35))


func _desk_icon(parent: Node, caption: String, col: Color, cb: Callable) -> void:
	var img := Image.create(44, 36, false, Image.FORMAT_RGBA8)
	img.fill(col)
	for x in 44:
		img.set_pixel(x, 0, col.lightened(0.5))
		img.set_pixel(x, 35, col.darkened(0.5))
	for y in 36:
		img.set_pixel(0, y, col.lightened(0.5))
		img.set_pixel(43, y, col.darkened(0.5))
	var b := Button.new()
	b.text = caption
	b.icon = ImageTexture.create_from_image(img)
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(150, 46)
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.pressed.connect(cb)
	parent.add_child(b)


static func _hm(t: float) -> String:
	var m := int(fmod(t, 1440.0))
	return "%02d:%02d" % [m / 60, m % 60]


## Datum splatnosti z juliánského dne (M4.2 – pokuty a dluhy).
func _jd_text(j: int) -> String:
	var d := Clock.from_jdn(j)
	return "%d. %d. %d" % [int(d["day"]), int(d["month"]), int(d["year"])]
