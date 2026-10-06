## HUD: stav hráče (promile, fáze opilosti, žaludek, hmotnost/BMI, nikotin, zdraví, výdrž),
## hodiny a peníze, tachometr auta, aktivní úkol s podmínkami, kompas (k cíli úkolu nebo předmětu),
## zprávy, výzvy k interakci, nabídky míst (tlačítka), inventář (Tab), deník úkolů (J),
## nápověda (F1), rotující minimapa s kompasem (vpravo nahoře) a mapa katastru (M – kolečko přibližuje,
## tažení posouvá) z ortofota s místy, pověst v obci (Reputation), rozhovor na ulici
## (T / Enter – řádek pro psaní a záznam posledních replik). Panel úkolu ukazuje klávesa Z (QWERTZ; fyzicky Y).
## Patří LocalClient: zobrazuje stav lokálního hráče (`player`), svět čte z `game` (World).
class_name Hud
extends CanvasLayer

const COLORS := {"hrib": Color(0.75, 0.45, 0.2), "jablko": Color(0.9, 0.15, 0.1), "sipek": Color(0.85, 0.2, 0.2),
	"dukat": Color(1.0, 0.82, 0.2), "zalud": Color(1.0, 0.95, 0.5)}
const GIVER_WHERE := {"deda": "lavička dědy Vomáčky u jeho domu", "hospoda": "Hospoda U Hřiště", "urad": "Obecní úřad",
	"obchod": "Potraviny", "sklep": "Vinný sklep Jílka", "palenice": "Pálenice U Kotla", "chata": "Myslivecká chata",
	"vcelar": "včelnice u lesa"}
## Právní doložka (viz PRAVNI_DOPORUCENI.md) – úvodní obrazovka a nápověda F1.
const DISCLAIMER := "Tato hra je satirickým uměleckým dílem. Všechny postavy, události a vyobrazené soukromé objekty\n" \
	+ "jsou smyšlené. Jakákoliv podobnost se skutečnými osobami či konkrétními obydlími je čistě náhodná."
const CREDITS := "Geodata a ortofoto © ČÚZK (CC BY 4.0) · Mapová data © přispěvatelé OpenStreetMap (ODbL), vodní toky z DIBAVOD (VÚV TGM) · Textury Poly Haven (CC0)"
## Jednotný vzhled nabídek (F2, obchody, pauza…): lesní zelená jako doprovodná barva obce.
const ACCENT := Color(0.55, 0.85, 0.5)
const MENU_BG := Color(0.07, 0.08, 0.07, 0.95)
## Minimapa: velikost v px a světová šířka pohledu v metrech.
const MINI_SIZE := 240.0
const MINI_RANGE_M := 420.0
## Mapa (M): největší přiblížení kolečkem; 1 = celý katastr v okně.
const MAP_ZOOM_MAX := 16.0
## Vzhled silnic na mapě podle druhu (OSM highway → [barva, šířka px]).
const ROAD_STYLE := {
	"secondary": [Color(0.95, 0.8, 0.4), 3.5],
	"tertiary": [Color(0.92, 0.92, 0.88), 2.8],
	"residential": [Color(0.85, 0.85, 0.82), 2.0],
	"unclassified": [Color(0.85, 0.85, 0.82), 2.0],
	"service": [Color(0.72, 0.72, 0.7), 1.5],
	"track": [Color(0.6, 0.48, 0.32), 1.5],
	"path": [Color(0.55, 0.45, 0.32), 1.0],
	"footway": [Color(0.55, 0.45, 0.32), 1.0],
	"other": [Color(0.8, 0.8, 0.8), 2.0],
}

var player: Player               # lokální hráč
var items_root: Node
var meta: Dictionary
var game: Node                   # World
var totals := {}
var counts := {"hrib": 0, "jablko": 0, "sipek": 0, "dukat": 0, "zalud": 0, "lysohlavky": 0}
var score := 0
var menu_open := false
var show_fps := true              # počítadlo FPS (Esc → Nastavení)
var chat_open := false            # hráč právě píše, co řekne (T)

var _loading: Control
var _loading_label: Label
var _score: Label
var _stamina: ProgressBar
var _compass: Label
var _msg: Label
var _msg_t := 0.0
var _help: PanelContainer
var _help_t := 14.0
var _map: Control
var _map_view: Control            # podklad + značky mapy (M) – vlastní kreslení s přiblížením
var _map_img: Texture2D           # podklad mapy: ortofoto nebo třídy povrchu (World.map_texture)
var _map_pos: Label               # souřadnice hráče (hra i Blender) – pro úpravy mapy
var _map_zoom := 1.0              # přiblížení mapy (1 = celý katastr v okně)
var _map_center := Vector2.ZERO   # střed pohledu mapy ve světových souřadnicích (x, z)
var _map_drag := false            # hráč táhne mapu levým tlačítkem
var _mini: Control                # minimapa s kompasem (vpravo nahoře)
var _mini_t := 0.0                # minipauza mezi překresleními minimapy (ne každý frame – je drahá)
var _mini_built := false          # keš statických vrstev minimapy hotová?
var _mini_lines: Array = []       # [světové body (x,z), střed, ohraničující poloměr, barva, šířka]
var _mini_dir_w: Array = []       # šířky textů kompasu (kompas texty se nemění – shape jednou)
var _quest_pinned := false        # Z – panel úkolu přišpendlený (jinak skrytý)
var _cross: Label
var _scope: TextureRect          # tmavé okraje dalekohledu (X)
var _fps: Label
# stav
var _promile: Label
var _stage: Label
var _stats: Label
var _health: ProgressBar
var _stomach: ProgressBar
var _clock: Label
# auto
var _car_panel: PanelContainer
var _speed: Label
var _car_info: Label
var _rpm: ProgressBar
# M6.1 dron: OSD telemetrie (vlevo dole nad výdrží), řádek varování a záblesk spouště
var _drone_panel: PanelContainer
var _drone: Label
var _drone_warn: Label
var _flash: ColorRect
# úkol
var _quest_panel: PanelContainer
var _quest_label: RichTextLabel
# výzvy a bannery
var _prompt: Label
var _held: Label                 # „V ruce: Sekera (opotřebení 34/50)“ vpravo dole (M0.4)
var _act_label: Label            # název probíhající akce pod zaměřovačem
var _act_bar: ProgressBar        # průběh akce
var _banner: Label
var _banner_t := 0.0
var _popup: Label
var _popup_t := 0.0
# nabídky
var _menu: PanelContainer
var _menu_title: Label
var _menu_text: Label
var _menu_list: VBoxContainer
var _inv: PanelContainer
var _inv_head: Label
var _inv_list: VBoxContainer
var _inv_detail: PanelContainer
var _inv_detail_title: Label
var _inv_detail_text: Label
var _inv_detail_actions: VBoxContainer
var _inv_selected := ""           # id vybraného předmětu (klik na dlaždici) – akce zůstane v detailu
## Zkratka ikony dlaždice, chybí-li skutečná grafika (M – galerie miniatur): typ → 1–2 znaky.
const TYPE_GLYPH := {"drink": "PI", "food": "JI", "smoke": "CI", "gear": "VY", "tool": "NA", "weapon": "ZB",
	"ammo": "ST", "material": "MA", "seed": "SE", "clothing": "OB", "animal_product": "ŽI", "meat": "MA",
	"fish": "RY", "document": "DO", "collectible": "SB", "misc": "OS"}
var _journal: PanelContainer
var _journal_text: RichTextLabel
var _journal_skills := false      # deník otevřený klávesou K (jen dovednosti)
var _xp_label: Label              # plovoucí „+12 XP Řízení“ (M0.3)
var _xp_t := 0.0
var _xp_sum := {}                 # název dovednosti → XP nasčítané za poslední ~1 s
var _xp_info := {}                # název dovednosti → [úroveň, progress]
var _prev_p := 0.0
var _trend := 0.0
var _t := 0.0
# pověst a rozhovor
var _rep: Label
var _rep_msg: Label
var _rep_msg_t := 0.0
var _chat: LineEdit
var _chat_log: VBoxContainer
var _chat_lines: Array = []       # [Label, zbývá s]


## Titulky assetů s licencí CC BY z `data/credits.json` (generuje `tools/assets_check.py`); bez souboru "".
static func _extra_credits() -> String:
	var path := "res://data/credits.json"
	if not FileAccess.file_exists(path):
		return ""
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (data is Array):
		return ""
	var out := ""
	for r in data:
		if r is Dictionary:
			out += "\n%s – %s (%s)" % [r.get("nazev", "?"), r.get("autor", "?"), r.get("licence", "?")]
	return out


func _ready() -> void:
	layer = 5
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_score = _label(root, "", 16)
	_score.position = Vector2(20, 14)

	# ---------------- stav hráče (vlevo)
	var sp := _panel(root, Color(0, 0, 0, 0.42))
	sp.position = Vector2(16, 96)
	sp.custom_minimum_size = Vector2(270, 0)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 3)
	sp.add_child(sv)
	_clock = _label(sv, "", 18)
	_promile = _label(sv, "0,00 ‰", 38)
	_stage = _label(sv, "", 16)
	_stats = _label(sv, "", 14)
	_rep = _label(sv, "", 15)
	_rep_msg = _label(sv, "", 14)
	_rep_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rep_msg.custom_minimum_size = Vector2(250, 0)
	_rep_msg.visible = false
	_label(sv, "Zdraví", 13)
	_health = _bar(sv, Color(0.85, 0.25, 0.25), 250)
	_label(sv, "Žaludek (jídlo)", 13)
	_stomach = _bar(sv, Color(0.85, 0.65, 0.3), 250)

	_stamina = _bar(root, Color(0.45, 0.85, 0.4), 240)
	_stamina.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_stamina.offset_left = 20
	_stamina.offset_right = 260
	_stamina.offset_top = -34
	_stamina.offset_bottom = -22
	var stl := _label(root, "Výdrž", 14)
	stl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	stl.offset_left = 20
	stl.offset_top = -58

	_compass = _label(root, "", 20)
	_compass.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_compass.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_compass.offset_top = 14

	_banner = _label(root, "", 24)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.offset_top = 52
	_banner.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))

	_msg = _label(root, "", 28)
	_msg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_msg.offset_left = 300
	_msg.offset_right = -300
	_msg.offset_bottom = -320

	_popup = _label(root, "", 22)
	_popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_popup.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_popup.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_popup.offset_top = 260

	_xp_label = _label(root, "", 18)
	_xp_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_xp_label.offset_top = -210
	_xp_label.offset_bottom = -170
	_xp_label.add_theme_color_override("font_color", Color(0.75, 0.95, 1.0))
	_xp_label.visible = false

	_prompt = _label(root, "", 20)
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.offset_top = -120
	_prompt.offset_bottom = -90
	_prompt.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))

	_held = _label(root, "", 16)
	_held.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_held.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_held.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_held.offset_right = -20
	_held.offset_bottom = -16
	_held.add_theme_color_override("font_color", Color(0.9, 0.9, 0.8))

	_act_label = _label(root, "", 16)
	_act_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_act_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_act_label.offset_left = -150
	_act_label.offset_right = 150
	_act_label.offset_top = 46
	_act_label.offset_bottom = 70
	_act_label.visible = false
	_act_bar = _bar(root, Color(0.55, 0.85, 0.4), 200.0)
	_act_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_act_bar.offset_left = -100
	_act_bar.offset_right = 100
	_act_bar.offset_top = 74
	_act_bar.offset_bottom = 82
	_act_bar.visible = false

	# ---------------- rozhovor (vlevo dole nad výdrží)
	_chat_log = VBoxContainer.new()
	_chat_log.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_chat_log.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_chat_log.offset_left = 20
	_chat_log.offset_bottom = -110
	_chat_log.custom_minimum_size = Vector2(560, 0)
	_chat_log.add_theme_constant_override("separation", 2)
	_chat_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_chat_log)
	_chat = LineEdit.new()
	_chat.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_chat.offset_left = 320
	_chat.offset_right = -320
	_chat.offset_top = -80
	_chat.offset_bottom = -44
	_chat.placeholder_text = "Co řekneš? (Enter – říct, Esc – nic; víc !! nebo VELKÁ PÍSMENA = křik)"
	_chat.max_length = 160
	_chat.add_theme_font_size_override("font_size", 18)
	_chat.visible = false
	_chat.text_submitted.connect(_on_chat_submit)
	_chat.gui_input.connect(_on_chat_key)
	root.add_child(_chat)

	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.55, 0.62, 1.0])
	grad.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0.92), Color(0, 0, 0, 1)])
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill = GradientTexture2D.FILL_RADIAL
	gtex.fill_from = Vector2(0.5, 0.5)
	gtex.fill_to = Vector2(1.0, 0.5)
	gtex.width = 512
	gtex.height = 512
	_scope = TextureRect.new()
	_scope.texture = gtex
	_scope.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scope.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_scope.stretch_mode = TextureRect.STRETCH_SCALE
	_scope.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scope.visible = false
	root.add_child(_scope)
	_cross = _label(root, "+", 26)
	_cross.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cross.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cross.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	_fps = _label(root, "", 13)
	_fps.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_fps.offset_left = -110
	_fps.offset_top = MINI_SIZE + 24

	# ---------------- auto (vpravo dole)
	_car_panel = _panel(root, Color(0, 0, 0, 0.45))
	_car_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_car_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_car_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_car_panel.offset_right = -20
	_car_panel.offset_bottom = -20
	var cv := VBoxContainer.new()
	_car_panel.add_child(cv)
	_speed = _label(cv, "0 km/h", 40)
	_speed.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_rpm = _bar(cv, Color(0.95, 0.55, 0.2), 220)
	_car_info = _label(cv, "", 15)
	_car_panel.visible = false

	# ---------------- dron (M6.1): telemetrie vlevo dole nad výdrží
	_drone_panel = _panel(root, Color(0, 0, 0, 0.45))
	_drone_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_drone_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_drone_panel.offset_left = 20
	_drone_panel.offset_bottom = -175
	_drone = _label(_drone_panel, "", 15)
	_drone.add_theme_color_override("font_color", Color(0.75, 0.95, 1.0))
	_drone_panel.visible = false
	_drone_warn = _label(root, "", 15)
	_drone_warn.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_drone_warn.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_drone_warn.offset_left = 20
	_drone_warn.offset_bottom = -240
	_drone_warn.add_theme_color_override("font_color", Color(1.0, 0.55, 0.35))
	_drone_warn.visible = false
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.visible = false
	root.add_child(_flash)

	# ---------------- úkol (vpravo pod minimapou, zobrazuje klávesa Z)
	_quest_panel = _panel(root, Color(0, 0, 0, 0.42))
	_quest_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_quest_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_quest_panel.offset_right = -16
	_quest_panel.offset_top = MINI_SIZE + 52
	_quest_panel.custom_minimum_size = Vector2(380, 0)
	_quest_label = RichTextLabel.new()
	_quest_label.bbcode_enabled = true
	_quest_label.fit_content = true
	_quest_label.custom_minimum_size = Vector2(380, 0)
	_quest_label.scroll_active = false
	_quest_label.add_theme_font_size_override("normal_font_size", 15)
	_quest_label.add_theme_font_size_override("bold_font_size", 17)
	_quest_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_quest_panel.add_child(_quest_label)
	_quest_panel.visible = false

	# ---------------- nápověda
	_help = _panel(root, Color(0, 0, 0, 0.6))
	_help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_help.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_help.offset_right = -20
	_help.offset_bottom = -170
	var ht := _label(_help, "", 15)
	ht.text = "OVLÁDÁNÍ\n" \
		+ "WASD – chůze / řízení       myš – rozhlížení\n" \
		+ "Shift – sprint              Mezerník – skok / ruční brzda\n" \
		+ "Ctrl / C – přikrčení        V – 1. / 3. osoba (i v autě)\n" \
		+ "E – mluvit / objednat / koupit / nocleh\n" \
		+ "T / Enter – říct něco nahlas (odpoví lidé okolo)\n" \
		+ "F – nastoupit / vystoupit z auta, nasednout na koně\n" \
		+ "Tab – inventář (pít, jíst, kouřit, obléct)   I – oblečení\n" \
		+ "P – doklady (řidičák, skupiny, body, zákaz)\n" \
		+ "J – deník úkolů   K – dovednosti   M – mapa (kolečko – přiblížení,\n" \
		+ "    tažení – posun)   Z – zobrazit / skrýt panel úkolu   H – domů\n" \
		+ "L – světla   B – klakson   N – stěrače\n" \
		+ "R – postavit auto   U – vysvobodit ze zaseknutí\n" \
		+ "F1 – nápověda   F2 – herní menu   Esc – pauza a nabídka\n" \
		+ "F5 – rychle uložit   F9 – načíst (další pozice v F2)\n" \
		+ "Kůň: W jet, Shift rychleji, S pomaleji, Mezerník skok\n" \
		+ "G – náklad: zvednout / položit / naložit do auta či na vozík;\n" \
		+ "    jinak hvízdnutí na koně (do 300 m)   X (držet) – dalekohled\n" \
		+ "E u ručního vozíku – táhnout (znovu E: pustit / zabrzdit)\n" \
		+ "Q – další nástroj v ruce   1–5 – rychlý slot nástroje\n" \
		+ "levé tlačítko myši – použít nástroj / akce (výzva dole)\n" \
		+ "Zbraň v ruce: pravé tl. míření (Shift = zadržet dech),\n" \
		+ "levé tl. výstřel (luk: držet = natáhnout, pustit = vystřelit)\n" \
		+ "Rádio u domu (E): přiblížíš se a točíš knoflíky – metal\nv noci naštve sousedy (noční klid 22–6 h)\n\n" \
		+ "LETOUN (M6.3, F2 → Vozidla): W/S plyn, A/D překlápění,\n" \
		+ "    Mezerník zatáhnout / na zemi brzda, Ctrl přiklonit,\n" \
		+ "    V kamera, F nastoupit / vystoupit (jen na zemi)\n" \
		+ "DRON (inventář → detail → Vzlétnout): WASD let,\n" \
		+ "myš otáčení + kamera, Mezerník / Ctrl výška, Shift sport,\n" \
		+ "V pohled z dronu / za dronem, O nebo LMB fotka,\n" \
		+ "F přistát / návrat domů. Max 120 m, ne nad lidmi,\n" \
		+ "na dohled, ne špehovat sousedy – jinak pokuta.\n" \
		+ "Registrace a test A1/A3: počítač doma → Letectví – ÚVL.\n" \
		+ "PARAMOTOR (M6.4, inventář → detail → Připravit): čelem\n" \
		+ "    proti větru rozběh (W) → křídlo nahlas, Shift plyn,\n" \
		+ "    A/D brzdy do stran, S obě brzdy, Mezerník trimry,\n" \
		+ "    Ctrl uši; přistání = v ~1 m obě brzdy naplno, E sbalit.\n" \
		+ "    Průkaz + registrace + pojištění: PC → Letectví – ÚVL.\n" \
		+ "ROGALO / TRIKE (M6.5, polní letiště F2 → Teleport):\n" \
		+ "    Shift/Ctrl páka plynu (drží polohu); na zemi A/D\n" \
		+ "    příďové kolo + Mezerník brzda; ve vzduchu W nos\n" \
		+ "    nahoru, S dolů, A/D zatáčení (realistické řízení\n" \
		+ "    hrazdou: Esc → Nastavení). Přistát ~65 km/h\n" \
		+ "    proti větru na hlavní kola; jen na letišti, za dne,\n" \
		+ "    mimo mraky, ne nízko nad obcí/lidmi – jinak pokuta.\n" \
		+ "    Průkaz ULL (škola 75 000), registrace + pojištění:\n" \
		+ "    PC → Letectví – ÚVL. Spolujezdec = kamarád (E u triku).\n\n" \
		+ "Úkoly dávají lidé ve vsi (hospoda, úřad, obchod,\n" \
		+ "sklep, děda u domu). Pozor: v ČR se za volant\n" \
		+ "smí jen s 0,00 ‰! Lidé si pamatují, jak se chováš\n" \
		+ "(pověst vlevo) – dobré skutky i přestupky.\n\n" \
		+ "Satirická fikce – postavy, události a soukromé\n" \
		+ "objekty jsou smyšlené; podobnost se skutečnými\n" \
		+ "osobami či obydlími je čistě náhodná.\n" \
		+ "Zákony jsou ve hře zjednodušené – nejde o právní radu.\n" \
		+ CREDITS.replace(" · ", "\n") + _extra_credits()

	# ---------------- mapa (M): podklad + značky kreslí _draw_map_view, kolečko přibližuje
	_map = ColorRect.new()
	(_map as ColorRect).color = Color(0, 0, 0, 0.82)
	_map.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map.visible = false
	root.add_child(_map)
	_map_view = Control.new()
	_map_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_view.offset_left = 40
	_map_view.offset_top = 40
	_map_view.offset_right = -40
	_map_view.offset_bottom = -40
	_map_view.clip_contents = true
	_map_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_view.draw.connect(_draw_map_view_wrapped)
	_map.add_child(_map_view)
	var mt := _label(_map, "Katastr obce Dukelčic a okolí – ortofoto © ČÚZK    ● hráč   ■ domov   ◆ místa   ★ cíl úkolu   ▲ tvoje auto   ◇ okolní obce      kolečko – přiblížení · tažení – posun · M / Esc – zavřít", 16)
	mt.position = Vector2(46, 10)
	_map_pos = _label(_map, "", 14)
	_map_pos.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_map_pos.position = Vector2(46, -34)
	_map_pos.grow_vertical = Control.GROW_DIRECTION_BEGIN

	# ---------------- minimapa s kompasem (vpravo nahoře, skrytá při otevřené mapě)
	_mini = Control.new()
	_mini.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_mini.offset_left = -16 - MINI_SIZE
	_mini.offset_right = -16
	_mini.offset_top = 16
	_mini.offset_bottom = 16 + MINI_SIZE
	_mini.clip_contents = true
	_mini.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mini.visible = false                 # zapne se v _process, až existuje hráč
	_mini.draw.connect(_draw_minimap_wrapped)
	root.add_child(_mini)

	# ---------------- nabídka (obchod, hospoda, rozhovor, F2 herní menu)
	_menu = _menu_panel(root)
	_menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_menu.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_menu.grow_vertical = Control.GROW_DIRECTION_BOTH
	_menu.custom_minimum_size = Vector2(640, 0)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 8)
	_menu.add_child(mv)
	_menu_title = _label(mv, "", 24)
	_menu_title.add_theme_color_override("font_color", ACCENT)
	_menu_text = _label(mv, "", 16)
	_menu_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_menu_text.custom_minimum_size = Vector2(600, 0)
	var sep := HSeparator.new()
	var sep_style := StyleBoxLine.new()
	sep_style.color = Color(ACCENT, 0.35)
	sep.add_theme_stylebox_override("separator", sep_style)
	mv.add_child(sep)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(600, 380)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mv.add_child(scroll)
	_menu_list = VBoxContainer.new()
	_menu_list.add_theme_constant_override("separation", 3)
	_menu_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_menu_list)
	_menu.visible = false

	_inv = _menu_panel(root)
	_inv.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_inv.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_inv.grow_vertical = Control.GROW_DIRECTION_BOTH
	_inv.custom_minimum_size = Vector2(860, 560)
	var iv := VBoxContainer.new()
	_inv.add_child(iv)
	_inv_head = _label(iv, "INVENTÁŘ  (Tab – zavřít)", 20)
	_inv_head.add_theme_color_override("font_color", ACCENT)
	var ihb := HBoxContainer.new()
	ihb.add_theme_constant_override("separation", 16)
	iv.add_child(ihb)
	var iscroll := ScrollContainer.new()
	iscroll.custom_minimum_size = Vector2(560, 480)
	iscroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ihb.add_child(iscroll)
	_inv_list = VBoxContainer.new()
	_inv_list.add_theme_constant_override("separation", 10)
	_inv_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	iscroll.add_child(_inv_list)
	_inv_detail = _panel(ihb, Color(1, 1, 1, 0.04))
	_inv_detail.custom_minimum_size = Vector2(240, 480)
	_inv_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 6)
	_inv_detail.add_child(dv)
	_inv_detail_title = _label(dv, "", 18)
	_inv_detail_title.add_theme_color_override("font_color", Color(0.95, 0.9, 0.7))
	_inv_detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD
	_inv_detail_text = _label(dv, "Najeď myší na předmět,\nklikni pro detail a akci.", 15)
	_inv_detail_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	_inv_detail_text.modulate.a = 0.85
	_inv_detail_actions = VBoxContainer.new()
	_inv_detail_actions.add_theme_constant_override("separation", 4)
	dv.add_child(_inv_detail_actions)
	_inv.visible = false

	_journal = _menu_panel(root)
	_journal.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_journal.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_journal.grow_vertical = Control.GROW_DIRECTION_BOTH
	_journal.custom_minimum_size = Vector2(760, 520)
	_journal_text = RichTextLabel.new()
	_journal_text.bbcode_enabled = true
	_journal_text.custom_minimum_size = Vector2(740, 500)
	_journal_text.add_theme_font_size_override("normal_font_size", 16)
	_journal_text.add_theme_font_size_override("bold_font_size", 18)
	_journal.add_child(_journal_text)
	_journal.visible = false

	_loading = ColorRect.new()
	(_loading as ColorRect).color = Color(0.08, 0.1, 0.08)
	_loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_loading)
	_loading_label = _label(_loading, "KAMENÍ A JÍL\n\nNačítám mapu katastru…", 34)
	_loading_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var legal := _label(_loading, DISCLAIMER + "\n\n" + CREDITS, 15)
	legal.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	legal.offset_top = -110
	legal.offset_bottom = -24
	legal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	legal.modulate = Color(1, 1, 1, 0.75)


func set_loading(text: String) -> void:
	_loading_label.text = "KAMENÍ A JÍL\n\n" + text


func finish_loading() -> void:
	var tw := create_tween()
	tw.tween_property(_loading, "modulate:a", 0.0, 0.8)
	tw.tween_callback(_loading.hide)
	refresh_map_texture()
	show_message("Vítej v Dukelčicích!\nDěda Vomáčka u domu by něco potřeboval. Klikni do okna pro ovládání myší.", 6.0)
	_hook_obce_map()                     # okolní obce na hlavní mapě (druhý draw callback _map_view)


## Podklad mapy (M) i minimapy: mapa z tříd povrchu, nebo ortofoto, podle nastavení terénu (World.map_texture).
func refresh_map_texture() -> void:
	_map_img = game.map_texture()


func show_message(t: String, dur := 3.0) -> void:
	_msg.text = _strip_bbcode(t)
	_msg_t = dur


## Texty úkolů mají barevné značky pro panel úkolu – do prostého Labelu je nechceme.
static func _strip_bbcode(t: String) -> String:
	var re := RegEx.new()
	re.compile("\\[/?(color|b|i)[^\\]]*\\]")
	return re.sub(t, "", true)


func police_banner(t: String, dur := 4.0) -> void:
	_banner.text = t
	_banner_t = dur


func popup(t: String, dur := 5.0) -> void:
	_popup.text = t
	_popup_t = dur


## Telemetrie dronu (M6.1): LocalClient ji volá každý frame s `Drone.status()`; {} = panel schovat.
func drone(st: Dictionary) -> void:
	_drone_panel.visible = not st.is_empty()
	if st.is_empty():
		_drone_warn.visible = false
		return
	var f := float(st["bat"])
	var reg := String(st.get("reg", ""))
	var mode_cz: String = {"zemi": "ZEMĚ", "start": "VZLET", "let": "LET", "rth": "NÁVRAT",
		"pristat": "PŘISTÁNÍ", "spadl": "PÁD", "strom": "STROM"}.get(str(st["mode"]), str(st["mode"]).to_upper())
	_drone.text = "DRON %s%s · %s\nAGL %d m · %0.1f m/s · vzdálenost %d m\nBAT %d %%%s · SIG %d %% · fotek %d%s" % [
		st["model"], " (%s)" % reg if reg != "" else "", mode_cz,
		roundi(float(st["agl"])), float(st["spd"]), roundi(float(st["dist"])),
		roundi(f * 100.0), " !" if f <= Drone.BAT_WARN else "", roundi(float(st["sig"]) * 100.0),
		int(st["fotek"]), " · SPORT" if bool(st["sport"]) else ""]
	var w: Array = st["warns"]
	_drone_warn.text = "!! " + " · ".join(w)
	_drone_warn.visible = not w.is_empty()


## Záblesk spouště fotoaparátu dronu (M6.1, `World.drone_photo` → `LocalClient.drone_photo`).
func photo_flash() -> void:
	_flash.visible = true
	_flash.modulate.a = 0.85
	var tw := create_tween()
	tw.tween_property(_flash, "modulate:a", 0.0, 0.22)
	tw.tween_callback(func(): _flash.visible = false)


## Zisk XP (Skills.add_xp přes World.notify): plovoucí text pod zprávami; zisky stejné dovednosti
## v rámci ~1 s se sečtou, ať se nepřekrývají.
func skill_xp(skill_name: String, amount: float, lvl: int, progress: float, _why := "") -> void:
	_xp_sum[skill_name] = float(_xp_sum.get(skill_name, 0.0)) + amount
	_xp_info[skill_name] = [lvl, progress]
	_xp_t = 3.0
	var parts := []
	for k in _xp_sum:
		var inf: Array = _xp_info[k]
		parts.append("+%s XP %s  (úr. %d, %d %%)" % [_fmt_xp(_xp_sum[k]), k, inf[0], roundi(float(inf[1]) * 100.0)])
	_xp_label.text = "\n".join(parts)
	_xp_label.modulate.a = 1.0
	_xp_label.visible = true


static func _fmt_xp(v: float) -> String:
	return str(roundi(v)) if absf(v - roundf(v)) < 0.05 else ("%.1f" % v).replace(".", ",")


## Výzva u spodního okraje; `dim` = akce nejde (šedě, s důvodem).
func set_prompt(t: String, dim := false) -> void:
	_prompt.text = t
	_prompt.add_theme_color_override("font_color", Color(0.72, 0.72, 0.72) if dim else Color(1.0, 0.95, 0.6))


## Průběh kontextové akce (World.notify): p 0..1, záporné = skrýt.
func action_progress(title: String, p: float) -> void:
	var on := p >= 0.0
	_act_label.visible = on
	_act_bar.visible = on
	if on:
		_act_label.text = title
		_act_bar.value = p


func on_collected(item: Item) -> void:
	counts[item.kind] += 1
	score += int(ItemsDB.info(item.kind)["points"])
	var name: String = ItemsDB.info(item.kind)["short"]
	var extra := ""
	if item.kind == "dukat":
		extra = "  (+100 Kč)"
	elif item.kind in ["jablko", "hrib", "sipek", "lysohlavky"]:
		extra = "  → inventář"
	show_message("+%d  %s  (%d/%d)%s" % [int(ItemsDB.info(item.kind)["points"]), name, counts[item.kind], totals[item.kind], extra], 2.0)


# ------------------------------------------------------------------ úkoly

func quest_started(q) -> void:
	show_message("NOVÝ ÚKOL: %s\n%s" % [q.title, q.objective()], 5.0)


func quest_done(q, text: String, reward: int) -> void:
	show_message("✔ SPLNĚNO: %s\n%s\nOdměna %d Kč" % [q.title, text, reward], 8.0)


func quest_failed(q, reason: String) -> void:
	show_message("✘ NESPLNĚNO: %s\n%s\n(Zkusit znovu: %s – %s)" % [q.title, reason, q.giver_name,
		GIVER_WHERE.get(q.giver, "")], 8.0)


## Úkoly lokálního hráče.
func _quests() -> Quests:
	return game.quests_of(player.id) if player and game else null


func _quest_text() -> String:
	var q = _quests().active
	if q == null:
		var offers := []
		for oq in _quests().list:
			if oq.state in ["available", "failed"] and oq.can_start():
				var line := "%s – %s" % [oq.giver_name, GIVER_WHERE.get(oq.giver, "")]
				if not offers.has(line):        # jedna postava může nabízet víc úkolů
					offers.append(line)
		if offers.is_empty():
			return ""
		return "[b]Žádný úkol[/b]  [color=#aaa](J – deník, M – mapa ★)[/color]\nÚkoly nabízí:\n  [color=#ccc]• " \
			+ "\n  • ".join(offers) + "[/color]"
	var s := "[b]%s[/b]\n▸ %s" % [q.title, q.objective()]
	for r in q.rule_lines():
		s += "\n  [color=#9fd]• %s[/color]" % r
	return s


## Řádek směny (M3.1, `Jobs.hud_text`) nad panelem úkolu; "" = nic.
func _job_text() -> String:
	var jb: Jobs = game.jobs.get(player.id) if game and player else null
	return jb.hud_text() if jb else ""


## Dovednosti: název – úroveň – pruh postupu – XP do další úrovně (deník J i klávesa K).
func _skills_bbcode() -> String:
	var sk: Skills = game.skills.get(player.id)
	if sk == null:
		return ""
	var s := "[b]DOVEDNOSTI[/b]   (činnosti ve světě tě učí; úroveň 1–%d)\n[table=5]" % Skills.MAX_LEVEL
	for k in Skills.SKILLS:
		var pr := sk.progress(k)
		var filled := clampi(roundi(pr * 10.0), 0, 10)
		var next := "max." if sk.level(k) >= Skills.MAX_LEVEL else "do další %s XP" % _fmt_xp(sk.xp_to_next(k))
		s += "[cell][color=#%s]■[/color] %s   [/cell][cell][b]%d[/b]   [/cell][cell]%s%s[/cell][cell] %d %%   [/cell][cell]%s[/cell]" % [
			Skills.SKILLS[k][2].to_html(false), Skills.skill_name(k), sk.level(k),
			"▰".repeat(filled), "▱".repeat(10 - filled), roundi(pr * 100.0), next]
	return s + "[/table]\n"


## Oddíl „Úřední záznamy“ (M0.5): body, nezaplacené pokuty a posledních 10 záznamů z katalogu zákona.
func _law_bbcode() -> String:
	var lr: Law.LawRecord = game.law.get(player.id)
	if lr == null:
		return ""
	lr.refresh(game.clock.minutes)
	var lim := int(Law.setting("body_limit", 12.0))
	var s := "\n\n[b]ÚŘEDNÍ ZÁZNAMY[/b]   body [color=#%s]%d / %d[/color]" % ["f99" if lr.points >= lim - 4 else "ccc", lr.points, lim]
	var dluhy: int = game.debts.total(player.id) if game.debts else 0
	if dluhy > 0:
		s += "   dluhy a pokuty [color=#f66]%d Kč[/color]" % dluhy
	s += "\n"
	if game.debts:                          # M4.2: otevřené dluhy se stavem (splatné / upomínka / exekuce)
		for dl in game.debts.list(player.id):
			s += "• %s – [color=#f99]%s[/color] (%s)\n" % [dl["text"], Bazaar.kc(int(dl["kc"])),
				Debts.STAGE_NAMES.get(String(dl["stage"]), String(dl["stage"]))]
		for o in game.debts.orders(player.id):
			s += "• příkaz na cestě poštou – %s\n" % Bazaar.kc(int(o["kc"]))
	if lr.records.is_empty():
		return s + "Bez záznamu.\n"
	var last: Array = lr.records.slice(maxi(lr.records.size() - 10, 0))
	last.reverse()
	for e in last:
		var o := Law.offense(String(e["id"]))
		var t := float(e["t"])
		s += "  den %d, %02d:%02d  %s – %d Kč%s%s   [color=#999](%s)[/color]\n" % [int(t / 1440.0) + 1, int(fmod(t, 1440.0) / 60.0), int(fmod(t, 60.0)),
			o.get("nazev", e["id"]), int(e["pokuta"]), ", %d b." % int(e["body"]) if int(e["body"]) > 0 else "",
			", trestný čin" if e.get("trestny_cin", false) else "", Law.LawRecord._par(o)]
	return s


func _journal_bbcode() -> String:
	if _journal_skills:
		return "[color=#aaa](K – zavřít, J – deník úkolů)[/color]\n\n" + _skills_bbcode()
	var s := "[b]DENÍK ÚKOLŮ[/b]   (J – zavřít, K – dovednosti)\n\n"
	for q in _quests().list:
		if q.hidden and q.state == "available":
			continue        # úkoly, které nikdo nenabízí (vznikají událostí), se v deníku ukážou až po spuštění
		var st: String = {"available": "[color=#ccc]k dispozici[/color]", "active": "[color=#ff6]probíhá[/color]",
			"done": "[color=#6f6]splněno[/color]", "failed": "[color=#f66]nesplněno[/color]"}[q.state]
		s += "[b]%s[/b] – %s   (%s, %s)\n" % [q.title, st, q.giver_name, GIVER_WHERE.get(q.giver, "")]
		if q.state == "failed":
			s += "   %s\n" % q.fail_reason
		elif q.state == "done":
			s += "   %s\n" % q.result_text
		elif q.state == "active":
			s += "   ▸ %s\n" % q.objective()
		s += "\n"
	var jb: Jobs = game.jobs.get(player.id)
	if jb:
		s += jb.journal_bbcode() + "\n"          # M3.1: oddíl „Práce“
	s += _skills_bbcode()
	s += "\n[b]DOKLADY[/b]  (P – panel)\n" + _documents_text() + "\n"      # M4.1: oddíl „Doklady“
	var b: BodyState = player.body
	var w: Weather = game.weather
	if w:
		s += "\n[b]POČASÍ[/b]   %s %s" % [w.icon(), w.describe()]
		var f := w.forecast()
		if not f.is_empty():
			s += "   –   zítra: [color=#9cf]%s, nejtepleji %d °C[/color]" % [f["name"], f["temp"]]
		s += "\n\n"
	var nl = game.get("nature_log")
	if nl:
		s += nl.journal_text(player.id)
	s += "[b]STATISTIKA[/b]\nVypito celkem %.0f g alkoholu (%d nápojů), snědeno %d kcal, vykouřeno %d cigaret.\n" % [
		b.total_alc_g, b.drinks, int(b.total_kcal), b.cigarettes_smoked]
	s += "Hmotnost %.1f kg (BMI %.1f).  Peníze %d Kč." % [b.weight, b.bmi(), player.money]
	if game.computer:
		s += game.computer.journal_text(player.id)      # M3.4: účet, nepřečtená pošta, balíky
	var rep: Reputation = game.reputations.get(player.id)
	if rep:
		s += "\n\n[b]POVĚST V OBCI[/b]  [color=#%s]%+d – %s[/color]   (dobré skutky: %d)\n" % [
			rep.tier_color().to_html(false), roundi(rep.score), rep.tier_name(), rep.good_deeds]
		if rep.offenses.is_empty():
			s += "Rejstřík přestupků: čistý.\n"
		else:
			var offs := []
			for k in rep.offenses:
				offs.append("%s ×%d" % [k, rep.offenses[k]])
			s += "Rejstřík přestupků: [color=#f99]%s[/color]\n" % ", ".join(offs)
		var last: Array = rep.history.slice(maxi(rep.history.size() - 6, 0))
		last.reverse()
		for e in last:
			s += "  [color=#%s]%+d[/color] %s\n" % ["8f8" if float(e["delta"]) > 0.0 else "f88", roundi(float(e["delta"])), e["text"]]
		s += _relations_bbcode(rep)
	s += _law_bbcode()
	if _quests().active:
		s += "\n\n[color=#aaa]Rozdělaný úkol lze vzdát klávesou Backspace.[/color]"
	return s


## Deník, oddíl „Vztahy“ (M0.6): respekt komunit slovně, karma jen slovně, top 5 přátel.
func _relations_bbcode(rep: Reputation) -> String:
	var s := "\n[b]VZTAHY[/b]\n"
	for k in Reputation.COMMUNITIES:
		var v := rep.respect_of(k)
		s += "  %s: [color=#%s]%s[/color]\n" % [Reputation.community_name(k), Reputation.respect_color(v).to_html(false),
			Reputation.respect_word(v)]
	s += "Svědomí: [color=#%s]%s[/color]\n" % [rep.karma_color().to_html(false), rep.karma_word()]
	var friends := []
	var ps: Dictionary = game.personas()
	for key in ps:
		var f: float = ps[key].get_friendship(player.id)
		if f >= 5.0:
			friends.append([f, ps[key].display_name()])
	friends.sort_custom(func(a, b): return a[0] > b[0])
	if friends.is_empty():
		s += "Přátelé: zatím nikoho nemáš – povídej si slušně, kamarádství roste pomalu.\n"
	else:
		var names := []
		for i in mini(friends.size(), 5):
			names.append("%s (%s)" % [friends[i][1], "přítel" if friends[i][0] >= Persona.FRIEND_HIGH else "známý"])
		s += "Přátelé: %s\n" % ", ".join(names)
	return s


# ------------------------------------------------------------------ nabídky

## Otevře nabídku: options = [[text, Callable, enabled (volitelně)], …]
## Nadpis podkategorie (nekliknutelný, jen pro rozdělení dlouhé nabídky): GameMenu.hdr("Text").
func open_menu(title: String, text: String, options: Array) -> void:
	_close_panels()
	_menu_title.text = title
	_menu_text.text = text
	for c in _menu_list.get_children():
		c.queue_free()
	for o in options:
		if o.size() > 4 and o[4] == true:           # podnadpis kategorie
			if _menu_list.get_child_count() > 0:
				_menu_list.add_child(HSeparator.new())
			var h := _label(_menu_list, o[0], 15)
			h.add_theme_color_override("font_color", Color(ACCENT, 0.9))
			continue
		var b := Button.new()
		b.text = o[0]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 17)
		b.custom_minimum_size = Vector2(0, 34)
		b.disabled = o.size() > 2 and not o[2]
		_menu_button_style(b)
		if o.size() > 3 and o[3] is Color:          # M3.1: volitelná barva řádku (požadavky práce: splněné zeleně, nesplněné šedě)
			b.add_theme_color_override("font_color", o[3])
			b.add_theme_color_override("font_disabled_color", o[3])
		var cb: Callable = o[1]
		b.pressed.connect(func():
			close_menu()
			cb.call())
		_menu_list.add_child(b)
	var close := Button.new()
	close.text = "Odejít (Esc)"
	close.add_theme_font_size_override("font_size", 17)
	close.custom_minimum_size = Vector2(0, 34)
	_menu_button_style(close)
	close.pressed.connect(close_menu)
	_menu_list.add_child(HSeparator.new())
	_menu_list.add_child(close)
	_menu.visible = true
	_set_menu_mode(true)


func close_menu() -> void:
	_close_panels()
	_set_menu_mode(false)


func _close_panels() -> void:
	_menu.visible = false
	_inv.visible = false
	_journal.visible = false


func _set_menu_mode(on: bool) -> void:
	menu_open = on
	player.controls_locked = on
	_update_mouse_mode()


## Kurzor je viditelný u nabídek, rozhovoru i otevřené mapy (M); jinak zůstává zachycený.
func _update_mouse_mode() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if (menu_open or chat_open or _map.visible) \
		else Input.MOUSE_MODE_CAPTURED


## Doklady, které panel P ukazuje (i „nemáš“): kind → true.
const DOC_KINDS := ["ridicsky", "dron_a1a3", "pilot_pg_motor", "pilot_ul", "zbrojni", "lovecky_listek", "povolenka_lov",
	"rybarsky_listek", "povolenka_rybolov"]


## M4.1 panel dokladů (P): řidičák se skupinami, body a zákaz, drony, létací průkazy; budoucí doklady jako „nemáš“.
func open_documents() -> void:
	open_menu("Doklady (P)", _documents_text(), [])


## Text dokladů (prostý text – panel i deník). Čte `World.permits` a `World.law`.
func _documents_text() -> String:
	var rp: Permits = game.permits
	if rp == null or player == null:
		return "Doklady nejsou k dispozici."
	var pid := player.id
	var held := {}
	for d in rp.list(pid):
		held[d["kind"]] = d
	var s := ""
	var lr: Law.LawRecord = game.law.get(pid)
	if lr:
		s += "Body: %d / %d\n" % [lr.points, int(Law.setting("body_limit", 12.0))]
	var zakaz_min: float = player.license_suspended_until - game.clock.minutes
	if zakaz_min > 0.0:
		s += "Zákaz řízení ještě %d h\n" % int(zakaz_min / 60.0)
	s += "\n"
	for k in DOC_KINDS:
		var name: String = Permits.KINDS[k][0]
		if not held.has(k):
			s += "· %s – nemáš\n" % name
			continue
		var d: Dictionary = held[k]
		var line := "· %s" % name
		if String(d["no"]) != "":
			line += " (%s)" % d["no"]
		if not (d["subs"] as Array).is_empty():
			line += "\n    skupiny: %s" % ", ".join(PackedStringArray(d["subs"]))
		var vu := int(d.get("valid_until", -1))
		if vu >= 0:
			var left: int = vu - int(game.clock.jd())
			line += "\n    platí ještě %d dní" % left if left >= 0 else "\n    PROŠLÁ – koupit novou v chatě"
		var rv: Dictionary = d["revoked"]
		if not rv.is_empty():
			if bool(rv.get("retest", false)):
				line += "\n    ODEBRÁNO (%s) – nutné přezkoušení v autoškole" % String(rv.get("reason", ""))
			else:
				line += "\n    ZÁKAZ (%s) – ještě %d dní" % [String(rv.get("reason", "")),
					maxi(0, int(rv.get("until_jd", 0)) - game.clock.jd())]
		s += line + "\n"
	s += "\nŘidičák a skupiny: autoškola Volant (počítač doma, Letectví / eTesty)."
	return s


func toggle_inventory() -> void:
	if _inv.visible:
		close_menu()
		return
	_close_panels()
	_rebuild_inventory()
	_inv.visible = true
	_set_menu_mode(true)


## Galerie miniatur (M – profi vzhled jako v jiných hrách): mřížka dlaždic po skupinách,
## detaily a akce se zobrazí vpravo při najetí myší / kliknutí na dlaždici.
func _rebuild_inventory() -> void:
	for c in _inv_list.get_children():
		c.queue_free()
	_inv_selected = ""
	_show_item_detail("")
	var ids := player.inventory.keys()
	for id in player.open_ml.keys():
		if not ids.has(id):
			ids.append(id)
	var kg := player.carried_kg()
	_inv_head.text = "INVENTÁŘ  (Tab – zavřít)   ·   Neseš %s / %s kg" % [_fmt_kg(kg), _fmt_kg(Player.CARRY_KG)]
	_inv_head.add_theme_color_override("font_color", Color(1.0, 0.55, 0.3) if kg > Player.CARRY_KG else ACCENT)
	if ids.is_empty():
		_label(_inv_list, "Nic u sebe nemáš. Nakup v Potravinách nebo v hospodě.", 16)
	for group in ItemsDB.GROUP_ORDER:
		var grid: GridContainer = null
		for id in ids:
			if not ItemsDB.exists(id) or ItemsDB.group_of(id) != group:
				continue
			if grid == null:
				var gl := _label(_inv_list, group, 17)
				gl.add_theme_color_override("font_color", Color(0.95, 0.8, 0.4))
				grid = GridContainer.new()
				grid.columns = 6
				grid.add_theme_constant_override("h_separation", 8)
				grid.add_theme_constant_override("v_separation", 8)
				_inv_list.add_child(grid)
			_add_inventory_tile(grid, id)


func _fmt_kg(v: float) -> String:
	return ("%.1f" % v).replace(".", ",")


## Jedna dlaždice miniatury: barevná ikona (dle ItemsDB), počet kusů vpravo dole, zvýrazněný
## rámeček u oblečení, které má hráč právě na sobě.
func _add_inventory_tile(grid: GridContainer, id: String) -> void:
	var info := ItemsDB.info(id)
	var n := player.item_count(id)
	var col: Color = info.get("color", Color(0.4, 0.4, 0.4))
	var worn: bool = info["type"] == "clothing" and Wardrobe.is_worn(player.outfit, id)

	var tile := Button.new()
	tile.custom_minimum_size = Vector2(78, 78)
	tile.toggle_mode = false
	tile.focus_mode = Control.FOCUS_NONE
	tile.clip_text = false
	tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var bg := col.lerp(Color.BLACK, 0.55)
	var hover := col.lerp(Color.BLACK, 0.35)
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = hover if state != "normal" else bg
		sb.set_corner_radius_all(10)
		sb.set_border_width_all(2 if worn else 1)
		sb.border_color = ACCENT if worn else Color(1, 1, 1, 0.18)
		tile.add_theme_stylebox_override(state, sb)
	grid.add_child(tile)

	var glyph := Label.new()
	glyph.text = String(TYPE_GLYPH.get(info["type"], "??")) if info["short"].length() < 2 \
		else String(info["short"]).substr(0, 2).to_upper()
	glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph.add_theme_font_size_override("font_size", 20)
	var lum := col.r * 0.299 + col.g * 0.587 + col.b * 0.114
	glyph.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1) if lum > 0.6 else Color(0.95, 0.95, 0.95))
	tile.add_child(glyph)

	if n > 1:
		var qty := Label.new()
		qty.text = "×%d" % n
		qty.add_theme_font_size_override("font_size", 13)
		qty.add_theme_color_override("font_color", Color.WHITE)
		qty.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		qty.add_theme_constant_override("outline_size", 4)
		qty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(qty)
		qty.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_KEEP_SIZE, 3)

	if worn:
		var tag := Label.new()
		tag.text = "✓"
		tag.add_theme_font_size_override("font_size", 13)
		tag.add_theme_color_override("font_color", ACCENT)
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(tag)
		tag.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_KEEP_SIZE, 3)

	tile.mouse_entered.connect(func(): _show_item_detail(id))
	tile.mouse_exited.connect(func(): _show_item_detail(_inv_selected))
	tile.pressed.connect(func():
		_inv_selected = id
		_show_item_detail(id))


## Textový popis předmětu do pravého panelu (ml/abv/kcal/hmotnost/trvanlivost…).
func _item_stats_text(id: String) -> String:
	var info := ItemsDB.info(id)
	var n := player.item_count(id)
	var lines := ["Máš: ×%d" % n]
	if info["type"] == "drink":
		var open_ml: float = player.open_ml.get(id, 0.0)
		if open_ml > 0.0:
			lines.append("Otevřená: %d ml" % int(open_ml))
		if Consumables.is_alcohol(id):
			lines.append("%.1f %% alkoholu" % float(info["abv"]))
		lines.append("%d kcal" % int(info["kcal"]))
	elif info["type"] == "food":
		lines.append("%d kcal" % int(info["kcal"]))
	elif info["type"] == "smoke":
		lines.append("%d ks v krabičce" % int(info.get("count", 20)))
	elif info["type"] == "clothing":
		lines.append(Wardrobe.row_text(player, id))
	elif info.get("durability", 0) > 0:
		lines.append("Výdrž: %d" % int(info["durability"]))
	if DroneModel.is_drone(id) and game:
		lines.append(game.drone_state_text(player.id, id))
	if n > 0 and ItemsDB.weight(id) > 0.0:
		lines.append("Hmotnost: %s kg (celkem)" % _fmt_kg(ItemsDB.weight(id) * n))
	return "\n".join(lines)


## Zobrazí detail a akci k danému předmětu v pravém panelu; "" = prázdný stav.
func _show_item_detail(id: String) -> void:
	for c in _inv_detail_actions.get_children():
		c.queue_free()
	if id == "" or not ItemsDB.exists(id):
		_inv_detail_title.text = ""
		_inv_detail_text.text = "Najeď myší na předmět,\nklikni pro detail a akci."
		return
	var info := ItemsDB.info(id)
	_inv_detail_title.text = String(info["name"])
	_inv_detail_text.text = _item_stats_text(id)
	if info["type"] == "clothing":
		Wardrobe.add_row_button(self, _inv_detail_actions, id)      # M2.3: Obléct / Svléct (5 s)
		return
	for rec in ItemsDB.RECIPES.get(id, []):     # M4.8: ubalení / pečení (ItemsDB.RECIPES)
		var br := Button.new()
		br.text = String(rec["name"])
		br.disabled = not player.craft_ok(id, rec)
		_menu_button_style(br)
		br.pressed.connect(func():
			if player.craft(id, rec):
				show_message("Hotovo: %s." % ItemsDB.name_of(String(rec["out"])), 2.5)
				_rebuild_inventory()
				_show_item_detail(id))
		_inv_detail_actions.add_child(br)
	var actions := {"drink": "Napít se", "food": "Sníst", "smoke": "Zapálit si", "gear": "Rozložit a vyspat se"}
	var act: String = actions.get(info["type"], "")
	if id != "spacak" and info["type"] == "gear":
		act = ""
	if DroneModel.is_drone(id):
		# M6.1: start dronu z inventáře (podmínky kontroluje World.drone_launch_check)
		var chk: Dictionary = game.drone_launch_check(player.id, id, true)
		if not bool(chk["ok"]):
			_inv_detail_text.text += "\nVzlétnout nejde: %s" % chk["why"]
		var bd := Button.new()
		bd.text = "Vzlétnout"
		bd.disabled = not bool(chk["ok"])
		_menu_button_style(bd)
		bd.pressed.connect(func():
			close_menu()
			game.player_action(player.id, "drone_launch:" + id))
		_inv_detail_actions.add_child(bd)
		return
	if id in World.PG_ITEM_IDS:
		# M6.4: rozložení paramotoru na louce (podmínky hlídá World.pg_prepare_check)
		var chk2: Dictionary = game.pg_prepare_check(player.id)
		if not bool(chk2["ok"]):
			_inv_detail_text.text += "\nRozložit nejde: %s" % chk2["why"]
		var bp := Button.new()
		bp.text = "Připravit k letu (rozložit křídlo)"
		bp.disabled = not bool(chk2["ok"])
		_menu_button_style(bp)
		bp.pressed.connect(func():
			close_menu()
			game.player_action(player.id, "pg_prepare"))
		_inv_detail_actions.add_child(bp)
		return
	if act == "":
		return      # nové typy zatím bez akce – jen zobrazit
	var b := Button.new()
	b.text = act
	b.disabled = player.busy or player.car != null or player.horse != null
	_menu_button_style(b)
	if info["type"] == "gear":
		b.pressed.connect(func():
			close_menu()
			game.sleep_rough(player.id))
	else:
		b.pressed.connect(func():
			if player.use_item(id):
				close_menu())
	_inv_detail_actions.add_child(b)


func toggle_journal(skills_only := false) -> void:
	if _journal.visible and _journal_skills == skills_only:
		close_menu()
		return
	_close_panels()
	_journal_skills = skills_only
	_journal_text.text = _journal_bbcode()
	_journal.visible = true
	_set_menu_mode(true)


## Vstup mapy (M) před gui i _unhandled_input: kolečko přibližuje ke kurzoru, levé tlačítko táhne.
## Kdyby prošlo dál, klik by znovu zachytil myš a kolečko točilo kamerou (LocalClient).
func _input(event: InputEvent) -> void:
	if not _map.visible or (player != null and player.controls_locked):
		return     # nad mapou může být nabídka / pauza (controls_locked) – nechat jí vstup
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_map_zoom_at(1.3, event.position)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_map_zoom_at(1.0 / 1.3, event.position)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_map_drag = event.pressed
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _map_drag:
		_map_center -= event.relative / _map_ppm()
		_map_clamp()
		_map_view.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if player == null or _quests() == null or chat_open:
		return     # svět se ještě načítá / hráč píše
	if event.is_action_pressed("toggle_map"):
		_toggle_map()
	elif event.is_action_pressed("quest_panel"):
		_quest_pinned = not _quest_pinned
	elif event.is_action_pressed("toggle_help"):
		_help.visible = not _help.visible
		_help_t = 0.0
	elif event.is_action_pressed("inventory"):
		toggle_inventory()
	elif event.is_action_pressed("wardrobe"):
		if menu_open:
			close_menu()
		else:
			Wardrobe.show_overview(self)      # I – co mám na sobě (převlékání doma / v inventáři)
	elif event.is_action_pressed("documents"):
		if menu_open:
			close_menu()
		else:
			open_documents()                  # P – doklady a oprávnění (M4.1)
	elif event.is_action_pressed("journal"):
		toggle_journal()
	elif event.is_action_pressed("skills"):
		toggle_journal(true)
	elif menu_open and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close_menu()
		get_viewport().set_input_as_handled()
	elif _journal.visible and event is InputEventKey and event.pressed and event.keycode == KEY_BACKSPACE:
		_quests().abandon()
		_journal_text.text = _journal_bbcode()


# ------------------------------------------------------------------ rozhovor a pověst

## Otevře řádek pro psaní (T / Enter). Hráč stojí, dokud nedopíše.
func open_chat() -> void:
	if menu_open or chat_open:
		return
	chat_open = true
	player.controls_locked = true
	_chat.text = ""
	_chat.visible = true
	_chat.call_deferred("grab_focus")
	if game and game.has_method("hold_listeners"):
		game.hold_listeners(player.id)


func close_chat() -> void:
	chat_open = false
	_chat.visible = false
	_chat.release_focus()
	if not menu_open:
		player.controls_locked = false


func _on_chat_submit(t: String) -> void:
	close_chat()
	if t.strip_edges() != "":
		game.player_say(player.id, t)


func _on_chat_key(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		close_chat()
		_chat.accept_event()


## Replika do záznamu rozhovoru (vlevo dole): kdo, co, jestli je to hráč.
func chat_line(who: String, text: String, mine := false) -> void:
	var l := _label(_chat_log, (("%s: " % who) if who != "" else "") + text, 17)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(560, 0)
	var col := Color(1.0, 0.95, 0.8)
	if mine:
		col = Color(0.75, 1.0, 0.75)
	elif who == "":
		col = Color(0.8, 0.8, 0.8)
	l.add_theme_color_override("font_color", col)
	_chat_lines.append([l, 14.0])
	while _chat_lines.size() > 7:
		_chat_lines.pop_front()[0].queue_free()


## Změna pověsti (Reputation.change): krátká zpráva pod ukazatelem, při změně stupně i uprostřed.
func reputation_changed(delta: float, text: String, _score: float, tier_name: String, _col: Color, tier_changed: bool) -> void:
	if absf(delta) >= 0.5:
		_rep_msg.text = "%s%d  %s" % ["+" if delta > 0.0 else "", roundi(delta), text]
	else:
		_rep_msg.text = "%s  %s" % ["+" if delta > 0.0 else "−", text]
	_rep_msg.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6) if delta > 0.0 else Color(1.0, 0.55, 0.5))
	_rep_msg.visible = true
	_rep_msg_t = 6.0
	if tier_changed:
		show_message("Tvoje pověst v obci: %s" % tier_name, 4.0)


## Změna respektu komunity (Reputation.change_respect): krátká zpráva jako u pověsti. Karma se nehlásí.
func respect_changed(comm_name: String, delta: float, text: String) -> void:
	_rep_msg.text = "%s: %s%d – %s" % [comm_name, "+" if delta > 0.0 else "", roundi(delta), text]
	_rep_msg.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6) if delta > 0.0 else Color(1.0, 0.55, 0.5))
	_rep_msg.visible = true
	_rep_msg_t = 6.0


# ------------------------------------------------------------------ průběžná aktualizace

func _process(delta: float) -> void:
	var __t0 := Tests.prof_t0()
	_process_impl(delta)
	Tests.prof_add("hud", __t0)


func _process_impl(delta: float) -> void:
	if player == null:
		return
	_t += delta
	_fps.visible = show_fps
	_fps.text = "%d FPS" % Engine.get_frames_per_second()
	var b: BodyState = player.body
	var held_txt := player.equipped_text() if player.car == null and player.horse == null else ""
	_held.text = "V ruce: %s" % held_txt if held_txt != "" else ""
	_score.text = "Skóre %d   ·   Hřiby %d/%d  Jablka %d/%d  Dukáty %d/%d  Žaludy %d/%d" % [
		score, counts["hrib"], totals.get("hrib", 0), counts["jablko"], totals.get("jablko", 0),
		counts["dukat"], totals.get("dukat", 0), counts["zalud"], totals.get("zalud", 0)]
	# --- promile a stav
	var p := b.promile()
	_trend = lerpf(_trend, (p - _prev_p) / maxf(delta, 0.001), clampf(delta * 2.0, 0.0, 1.0))
	_prev_p = p
	var arrow := ""
	if _trend > 0.002:
		arrow = " ↑"
	elif _trend < -0.0005:
		arrow = " ↓"
	_promile.text = ("%.2f ‰" % p).replace(".", ",") + arrow
	_promile.add_theme_color_override("font_color", b.stage_color())
	var peak := b.promile_peak_estimate()
	var st := b.stage_name()
	if peak > p + 0.05:
		st += "  (ještě stoupne na ~%s ‰)" % ("%.2f" % peak).replace(".", ",")
	elif p > 0.01:
		var h := b.hours_to_sober()
		st += "  · střízlivý za %d h %02d min" % [int(h), int(h * 60.0) % 60]
	_stage.text = st
	_stage.add_theme_color_override("font_color", b.stage_color())
	var bmi := b.bmi()
	var bmi_t := "normální" if bmi < 25.0 else ("nadváha" if bmi < 30.0 else "obezita")
	var extra := "Hmotnost %.1f kg · BMI %.1f (%s)" % [b.weight, bmi, bmi_t]
	# M4.8: stav látek jen věcně (obsah pro dospělé; hodnoty jsou 0, když je volba vypnutá)
	if b.thc > 0.05:
		extra += "\nPod vlivem THC – %s" % ("slabé" if b.thc < 0.5 else ("střední" if b.thc < 1.2 else "silné"))
	if b.psilo > 0.05:
		extra += "\nPod vlivem psilocybinu – %s" % ("slabé" if b.psilo < 0.5 else ("střední" if b.psilo < 1.2 else "silné"))
	if b.ever_smoked:
		extra += "\nNikotin %.1f mg · chuť na cigaretu %d %%" % [b.nicotine, int(b.craving * 100.0)]
		if b.tar > 3.0:
			extra += "\nPlíce: výdrž −%d %%" % int(minf(b.tar * 1.2, 45.0))
		if b.addiction > 0.15:
			extra += "\nZávislost na nikotinu %d %%" % int(b.addiction * 100.0)
	if b.nausea > 0.25:
		extra += "\nNevolnost %d %%" % int(b.nausea * 100.0)
	if b.wetness > 0.15:
		extra += "\nOblečení promočené %d %%" % int(b.wetness * 100.0)
	if b.cold > 0.1:
		extra += "\nProchladnutí %d %%" % int(b.cold * 100.0)
	extra += "\nPeníze: %d Kč" % player.money
	var hh: Horse = player.horse
	if hh == null and game.fauna:
		var oh: Horse = game.fauna.horse_of(player.id)
		if oh and oh.global_position.distance_to(player.global_position) < 6.0:
			hh = oh
	if hh:
		extra += "\nKůň: %s" % hh.care_text()
	_stats.text = extra
	var rep: Reputation = game.reputations.get(player.id)
	if rep:
		_rep.text = "Pověst: %+d · %s" % [roundi(rep.score), rep.tier_name()]
		_rep.add_theme_color_override("font_color", rep.tier_color())
	if _rep_msg_t > 0.0:
		_rep_msg_t -= delta
		if _rep_msg_t <= 0.0:
			_rep_msg.visible = false
	for cl in _chat_lines.duplicate():
		cl[1] -= delta
		cl[0].modulate.a = clampf(cl[1] / 2.0, 0.0, 1.0)
		if cl[1] <= 0.0:
			cl[0].queue_free()
			_chat_lines.erase(cl)
	_health.value = b.health / 100.0
	_stomach.value = clampf(b.stomach_kcal / 1500.0, 0.0, 1.0)
	var clk: Clock = game.clock
	_clock.text = "%s   %s" % [clk.date_text(), clk.text()]
	var ve = game.get("village_events")
	if ve:
		var ev_names: String = ve.names_text()
		if ev_names != "":
			_clock.text += "\n" + ev_names
	if game.weather:
		_clock.text += "\n%s  %s" % [game.weather.icon(), game.weather.describe()]
	_stamina.max_value = 1.0
	_stamina.value = player.stamina
	_cross.visible = ((player.first_person or player.scope > 0.5 or player.aim_k > 0.5) and player.car == null \
		and not menu_open and not player.controls_locked) or (player.drone_flying() and not menu_open)   # M6.1: mířidlo i za letu
	_scope.visible = player.scope > 0.05
	_scope.modulate.a = clampf(player.scope, 0.0, 1.0)
	# --- auto
	var car := player.car
	_car_panel.visible = car != null
	if car:
		_speed.text = "%d km/h" % int(absf(car.speed) * 3.6)
		_rpm.value = clampf(car.rpm / float(car.model.spec["rpm_max"]), 0.0, 1.0)
		var g := "R" if car.gear == -1 else str(car.gear)
		if absf(car.speed) < 0.3 and car.throttle < 0.05:
			g = "N" if car.gear != -1 else "R"
		if car.model.kind == "bike":
			_car_info.text = "%s · šlapání %d/min\nPoškození %d %%%s" % [car.model.spec["name"], int(car.rpm) if car.throttle > 0.05 else 0,
				int(car.damage), "  · dynamo svítí" if car.lights_on else ""]
		else:
			_car_info.text = "%s · stupeň %s · %d ot/min\nPoškození %d %%%s%s%s" % [car.model.spec["name"], g, int(car.rpm),
				int(car.damage), "  · světla" if car.lights_on else "", "  · RUČNÍ BRZDA" if car.handbrake else "",
				"  · stěrače" if car.wipers_on else ""]
	# --- zprávy
	if _msg_t > 0.0:
		_msg_t -= delta
		_msg.modulate.a = clampf(_msg_t, 0.0, 1.0)
	if _banner_t > 0.0:
		_banner_t -= delta
		_banner.modulate.a = clampf(_banner_t, 0.0, 1.0)
	if _xp_t > 0.0:
		_xp_t -= delta
		_xp_label.modulate.a = clampf(_xp_t, 0.0, 1.0)
		if _xp_t <= 0.0:
			_xp_label.visible = false
			_xp_sum.clear()
			_xp_info.clear()
	if _popup_t > 0.0:
		_popup_t -= delta
		_popup.modulate.a = clampf(_popup_t, 0.0, 1.0)
	if _help_t > 0.0:
		_help_t -= delta
		if _help_t <= 0.0:
			_help.visible = false
	# --- úkol (panel jen po přišpendlení klávesou Z – jinak je vpravo nahoře minimapa)
	var qt := _quest_text()
	var jt := _job_text()               # M3.1: směna nahoře nad úkolem
	if jt != "":
		qt = jt + ("\n\n" + qt if qt != "" else "")
	_quest_panel.visible = _quest_pinned and qt != ""
	if qt != "" and _quest_label.text != qt:
		_quest_label.text = qt
	# --- kompas a minimapa
	_compass.text = _compass_text(p)
	_mini.visible = not _map.visible
	if _mini.visible:
		_mini_t -= delta
		if _mini_t <= 0.0:
			_mini_t = 0.12          # minimapa stačí ~8× za sekundu – plný překres je drahý
			_mini.queue_redraw()
	# --- mapa (M)
	if _map.visible:
		_map_tick -= delta
		if _map_dirty or _map_tick <= 0.0:       # A1-02: jen při změně pohledu a marker hráče ~4× za sekundu
			_map_dirty = false
			_map_tick = 0.25
			_map_view.queue_redraw()
			var gp: Vector3 = game.player_pos(player.id)
			_map_pos.text = "Poloha: hra x %.1f, z %.1f  ·  Blender x %.1f, y %.1f, z %.1f  (--pos=%d,%d)   ·   přiblížení ×%.1f" % [
				gp.x, gp.z, gp.x, -gp.z, gp.y, int(gp.x), int(gp.z), _map_zoom]


func _compass_text(p: float) -> String:
	var dirs := ["S", "SV", "V", "JV", "J", "JZ", "Z", "SZ"]
	var north := float(meta.get("north_angle_deg", 78.37))
	var yaw := player.yaw
	if player.car:
		var f := player.car.global_transform.basis.z
		yaw = atan2(-f.x, -f.z)
	elif player.aircraft:                             # M6.3: směr letu – letoun letí proti −Z
		var f := -player.aircraft.global_transform.basis.z
		yaw = atan2(-f.x, -f.z)
	var geo := fposmod(north - rad_to_deg(yaw), 360.0)
	# v opilosti se kompas "točí"
	if p > 1.3:
		geo = fposmod(geo + sin(_t * 0.7) * (p - 1.3) * 60.0, 360.0)
	var txt := "%s %03d°" % [dirs[int(round(geo / 45.0)) % 8], int(geo)]
	var target := Vector3.INF
	var what := ""
	if _quests().active:
		target = _quests().active.target()
		what = "cíl"
	if target == Vector3.INF and game.jobs.has(player.id):
		target = (game.jobs[player.id] as Jobs).target()      # M3.1: pracoviště / bod pracovního úkolu
		what = "práce"
	if target == Vector3.INF:
		var near := _nearest_item()
		if near:
			target = near.global_position
			what = ItemsDB.info(near.kind)["short"]
	if target != Vector3.INF:
		var from := player.global_position
		var to: Vector3 = target - from
		var ang := rad_to_deg(atan2(-to.x, -to.z)) - rad_to_deg(yaw)
		if p > 1.6:   # opilý si plete směry
			ang += sin(_t * 0.37) * (p - 1.6) * 90.0
		ang = wrapf(ang, -180.0, 180.0)
		var where := "před tebou"
		if absf(ang) > 157.5:
			where = "za tebou"
		elif ang > 112.5:
			where = "vlevo vzadu"
		elif ang > 67.5:
			where = "vlevo"
		elif ang > 22.5:
			where = "vlevo vpředu"
		elif ang < -112.5:
			where = "vpravo vzadu"
		elif ang < -67.5:
			where = "vpravo"
		elif ang < -22.5:
			where = "vpravo vpředu"
		var dist := "%d m" % int(to.length())
		if p > 2.3:
			dist = "?? m"
		txt += "      ·  %s: %s, %s" % [what, where, dist]
	return txt


func _nearest_item() -> Item:
	var best: Item = null
	var bd := INF
	for it in items_root.get_children():
		if it is Item and not it._taken and it.active:
			var d: float = it.global_position.distance_squared_to(player.global_position)
			if d < bd:
				bd = d
				best = it
	return best


# ------------------------------------------------------------------ mapa (M)

## Otevře / zavře velkou mapu. Při otevření se vycentruje na hráče v přiblížení na obec
## a uvolní kurzor (kolečko přibližuje, levé tlačítko táhne). Ovládání hráče běží dál.
func _toggle_map() -> void:
	_map.visible = not _map.visible
	_map_drag = false
	if _map.visible:
		if menu_open:
			close_menu()                                 # mapa je nad nabídkami, ty by jí překrývaly
		var gp := player.global_position
		_map_center = Vector2(gp.x, gp.z)
		_map_zoom = 2.0
		_map_clamp()
	_update_mouse_mode()
	_map_view.queue_redraw()
	_mini.queue_redraw()


## pixely na metr při aktuálním přiblížení (podklad = celý ortho_full)
func _map_ppm() -> float:
	var o: Dictionary = meta["ortho_full"]
	return minf(_map_view.size.x / float(o["size_x"]), _map_view.size.y / float(o["size_z"])) * _map_zoom


## Střed pohledu udrží uvnitř oblasti mapy: katastr + hranice okolních obcí (_map_extent).
func _map_clamp() -> void:
	var e := _map_extent()
	var half := _map_view.size * 0.5 / maxf(_map_ppm(), 0.001)
	var cmin := e.position + half
	var cmax := e.end - half
	_map_center.x = clampf(_map_center.x, minf(cmin.x, cmax.x), maxf(cmin.x, cmax.x))
	_map_center.y = clampf(_map_center.y, minf(cmin.y, cmax.y), maxf(cmin.y, cmax.y))


## Přiblížení kolečkem k bodu `at` (souřadnice viewportu) – bod pod kurzorem zůstane na místě.
func _map_zoom_at(factor: float, at: Vector2) -> void:
	var local := at - _map_view.global_position
	var c := _map_view.size * 0.5
	var under := _map_center + (local - c) / _map_ppm()
	_map_zoom = clampf(_map_zoom * factor, MAP_ZOOM_MIN, MAP_ZOOM_MAX)
	_map_center = under - (local - c) / _map_ppm()
	_map_clamp()
	_map_view.queue_redraw()


## svět (x, z) → bod v rámci _map_view
func _w2v(p: Vector3) -> Vector2:
	return _map_view.size * 0.5 + (Vector2(p.x, p.z) - _map_center) * _map_ppm()


## Keš statických vrstev mapy ve světových souřadnicích (A1-02): staví se jednou při prvním kreslení.
var _mc_ok := false
var _mc_boundary := PackedVector2Array()
var _mc_streams := []             # [PackedVector2Array, šířka px, Rect2]
var _mc_ponds := []               # [PackedVector2Array, Rect2]
var _mc_roads := []               # {line, aabb, col, w, name, mid}
var _map_dirty := true            # mapa se překreslí jen při změně (střed, zoom, okno) a 4× za sekundu (značky)
var _map_tick := 0.0


func _map_build_cache() -> void:
	if _mc_ok:
		return
	_mc_ok = true
	for q in meta["boundary"]:
		_mc_boundary.append(Vector2(q[0], q[1]))
	if _mc_boundary.size() > 0:
		_mc_boundary.append(_mc_boundary[0])
	if game.water:
		for st in game.water.streams:
			var line := PackedVector2Array()
			for q in st["pts"]:
				line.append(Vector2(q.x, q.z))
			if line.size() >= 2:
				_mc_streams.append([line, 2.5 if st["kind"] == "river" else 1.5, _pts_aabb(line)])
		for pd in game.water.ponds:
			var poly := PackedVector2Array()
			for q in pd["poly"]:
				poly.append(Vector2(q.x, q.y))
			if poly.size() >= 3:
				_mc_ponds.append([poly, _pts_aabb(poly)])
	for rd in meta.get("roads", []):
		var line := PackedVector2Array()
		for q in rd["pts"]:
			line.append(Vector2(q[0], q[1]))
		if line.size() >= 2:
			var st: Array = ROAD_STYLE.get(rd["kind"], ROAD_STYLE["other"])
			_mc_roads.append({"line": line, "aabb": _pts_aabb(line), "col": st[0], "w": st[1],
				"name": String(rd.get("name", "")), "mid": line[line.size() / 2]})


static func _pts_aabb(pts: PackedVector2Array) -> Rect2:
	var r := Rect2(pts[0], Vector2.ZERO)
	for v in pts:
		r = r.expand(v)
	return r


func _draw_map_view_wrapped() -> void:
	var __t0 := Tests.prof_t0()
	_draw_map_view()
	Tests.prof_add("hud_map", __t0)


func _draw_map_view() -> void:
	var qs := _quests()
	if qs == null:
		return
	var o: Dictionary = meta["ortho_full"]
	var ppm := _map_ppm()
	_map_view.draw_rect(Rect2(Vector2.ZERO, _map_view.size), Color(0, 0, 0, 0.4))
	if _map_img:
		_map_view.draw_texture_rect(_map_img,
			Rect2(_w2v(Vector3(float(o["x0"]), 0, float(o["z0"]))),
				Vector2(float(o["size_x"]), float(o["size_z"])) * ppm), false)
	var font := ThemeDB.fallback_font
	var p := player.body.promile()
	# A1-02: statické vrstvy (hranice, vody, silnice) jsou ve světových souřadnicích v keši a kreslí se
	# jednou transformací (draw_set_transform); ořez mimo výřez podle AABB každé čáry. Šířky se dělí ppm.
	_map_build_cache()
	var half := _map_view.size * 0.5 / maxf(ppm, 0.001)
	var vrect := Rect2(_map_center - half, half * 2.0).grow(30.0 / maxf(ppm, 0.001))
	var inv := 1.0 / maxf(ppm, 0.001)
	_map_view.draw_set_transform(_map_view.size * 0.5 - _map_center * ppm, 0.0, Vector2(ppm, ppm))
	# hranice katastru
	_map_view.draw_polyline(_mc_boundary, Color(1, 1, 1, 0.7), 2.0 * inv)
	# vodní toky a plochy
	for st in _mc_streams:
		if (st[2] as Rect2).intersects(vrect):
			_map_view.draw_polyline(st[0], Color(0.35, 0.65, 1.0, 0.85), float(st[1]) * inv)
	for pd in _mc_ponds:
		if (pd[1] as Rect2).intersects(vrect):
			_map_view.draw_colored_polygon(pd[0], Color(0.35, 0.65, 1.0, 0.8))
	# silnice: nejdřív tmavý lem (čitelnost na ortofotu), pak barva podle druhu
	var road_vis := []
	for rl in _mc_roads:
		if (rl["aabb"] as Rect2).intersects(vrect):
			road_vis.append(rl)
			_map_view.draw_polyline(rl["line"], Color(0, 0, 0, 0.45), (float(rl["w"]) + 1.8) * inv)
	for rl in road_vis:
		_map_view.draw_polyline(rl["line"], rl["col"], float(rl["w"]) * inv)
	_map_view.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for rl in road_vis:
		var rn: String = rl["name"]
		if rn != "":
			var rp := _w2v(Vector3(rl["mid"].x, 0, rl["mid"].y)) + Vector2(6, -6)
			if Rect2(Vector2.ZERO, _map_view.size).has_point(rp):
				_map_view.draw_string_outline(font, rp, rn, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 3, Color(0, 0, 0, 0.85))
				_map_view.draw_string(font, rp, rn, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, rl["col"])
	for it in items_root.get_children():
		if it is Item and not it._taken and it.active:
			_map_view.draw_circle(_w2v(it.global_position), 3.0 if it.kind != "zalud" else 6.0, COLORS[it.kind])
	for k in game.places:
		var pl: Place = game.places[k]
		var mp := _w2v(pl.door)
		if k == "domov":
			_map_view.draw_rect(Rect2(mp - Vector2(6, 6), Vector2(12, 12)), Color(0.2, 0.6, 1.0))
		else:
			var dia := PackedVector2Array([mp + Vector2(0, -7), mp + Vector2(7, 0), mp + Vector2(0, 7), mp + Vector2(-7, 0)])
			_map_view.draw_colored_polygon(dia, Color(1.0, 0.75, 0.3))
		var nm: String = pl.data["name"]
		# ★ = tady se dá vzít úkol
		if qs.active == null and not qs.available_at(k).is_empty():
			nm = "★ " + nm
		var np := mp + Vector2(9, 5)
		_map_view.draw_string_outline(font, np, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0, 0.9))
		_map_view.draw_string(font, np, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
	# děda Vomáčka na lavičce u svého domu (M1.7: už ne u domova hráče) – ★ když má úkol
	if game.npcs.has("deda") and qs.active == null and not qs.available_at("deda").is_empty():
		var dm := _w2v((game.npcs["deda"] as Node3D).global_position)
		_map_view.draw_circle(dm, 4.0, Color(1.0, 0.75, 0.3))
		_map_view.draw_string_outline(font, dm + Vector2(9, 5), "★ Děda Vomáčka", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0, 0.9))
		_map_view.draw_string(font, dm + Vector2(9, 5), "★ Děda Vomáčka", HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
	var my_car: Car = game.traffic.car_of(player.id)
	if my_car:
		var cp := _w2v(my_car.global_position)
		_map_view.draw_colored_polygon(PackedVector2Array([cp + Vector2(0, -8), cp + Vector2(6, 5), cp + Vector2(-6, 5)]),
			Color(1.0, 0.3, 0.9))
	if qs.active:
		var tg: Vector3 = qs.active.target()
		if tg != Vector3.INF:
			var tp := _w2v(tg)
			_map_view.draw_circle(tp, 10.0, Color(1, 1, 0.2, 0.5 + 0.5 * sin(_t * 5.0)))
			_map_view.draw_string_outline(font, tp + Vector2(12, -8), "★ cíl", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color(0, 0, 0, 0.9))
			_map_view.draw_string(font, tp + Vector2(12, -8), "★ cíl", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 0.3))
	if game.police.checkpoint_pos != Vector3.INF and game.police.checkpoint_seen.get(player.id, false):
		var kp := _w2v(game.police.checkpoint_pos)
		_map_view.draw_string_outline(font, kp, "POLICIE – kontrola", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0, 0.9))
		_map_view.draw_string(font, kp, "POLICIE – kontrola", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.5, 0.4))
	# opilý neví, kde je
	if p < 2.2:
		var pp := _w2v(player.global_position)
		var fwd := Vector2(-sin(player.yaw), -cos(player.yaw))
		_map_view.draw_circle(pp, 7.0, Color(1, 0.2, 0.2))
		_map_view.draw_line(pp, pp + fwd * 18.0, Color(1, 0.2, 0.2), 3.0)
	else:
		_map_view.draw_string(font, Vector2(0, _map_view.size.y * 0.5), "Mapa se ti rozmazává… nevíš, kde jsi.",
			HORIZONTAL_ALIGNMENT_CENTER, _map_view.size.x, 26, Color(1, 0.5, 0.4))
	# sever – šipka vpravo nahoře (mapa není natočená na sever, meta.north_angle_deg)
	var north := deg_to_rad(float(meta.get("north_angle_deg", 78.37)))
	var ndir := Vector2(-sin(north), -cos(north))
	var nc := Vector2(_map_view.size.x - 38.0, 50.0)
	_map_view.draw_line(nc - ndir * 13.0, nc + ndir * 13.0, Color(1, 1, 1, 0.8), 2.0)
	var side := Vector2(-ndir.y, ndir.x)
	_map_view.draw_colored_polygon(PackedVector2Array([nc + ndir * 18.0, nc + side * 5.0, nc - side * 5.0]), Color(1, 0.4, 0.3))
	var sp := nc + ndir * 24.0 + Vector2(-4, 4)
	_map_view.draw_string_outline(font, sp, "S", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 3, Color(0, 0, 0, 0.9))
	_map_view.draw_string(font, sp, "S", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 0.45, 0.35))
	# měřítko a přiblížení – vpravo dole
	var bar_m := 10.0
	for n in [10.0, 20.0, 50.0, 100.0, 200.0, 500.0, 1000.0, 2000.0]:
		if n * ppm <= 170.0:
			bar_m = n
	var bl := bar_m * ppm
	var bp := Vector2(_map_view.size.x - 20.0, _map_view.size.y - 18.0)
	_map_view.draw_line(bp - Vector2(bl, 0), bp, Color(1, 1, 1, 0.9), 2.0)
	_map_view.draw_line(bp - Vector2(bl, 5), bp - Vector2(bl, -5), Color(1, 1, 1, 0.9), 1.5)
	_map_view.draw_line(bp + Vector2(0, -5), bp + Vector2(0, 5), Color(1, 1, 1, 0.9), 1.5)
	var lab := "%d m" % int(bar_m) if bar_m < 1000.0 else "%d km" % int(bar_m / 1000.0)
	var lw := font.get_string_size(lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var lp := bp + Vector2(-bl - lw - 8.0, 4)
	_map_view.draw_string_outline(font, lp, lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 3, Color(0, 0, 0, 0.9))
	_map_view.draw_string(font, lp, lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
	var zp := Vector2(14, _map_view.size.y - 10.0)
	_map_view.draw_string(font, zp, "přiblížení ×%.1f" % _map_zoom, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.65))


# ------------------------------------------------------------------ minimapa (vpravo nahoře)

## Kruhová minimapa: podklad rotuje podle směru pohledu (nahoru = vpřed), na okraji kompas
## se světovými stranami (S = sever – pozor, mapa není natočená na sever: north_angle_deg).
func _draw_minimap_wrapped() -> void:
	var __t0 := Tests.prof_t0()
	_draw_minimap()
	Tests.prof_add("hud_minimap", __t0)


func _draw_minimap() -> void:
	var qs := _quests()
	if player == null or qs == null:
		return
	var c := _mini.size * 0.5
	var rad := c.x - 4.0
	var font := ThemeDB.fallback_font
	var p := player.body.promile()
	if p >= 2.2:                                  # opilý neví, kde je (jako velká mapa)
		_mini.draw_circle(c, rad, Color(0.03, 0.04, 0.03, 0.8))
		_mini.draw_arc(c, rad + 2.0, 0, TAU, 64, Color(ACCENT, 0.5), 3.0)
		_mini.draw_string(font, c + Vector2(-50, 5), "rozmazané…", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.5, 0.4))
		return
	# směr pohledu (pěšky / auto / letoun) – obsah se otočí tak, aby vpřed bylo nahoru
	var yaw := player.yaw
	if player.car:
		var cf := player.car.global_transform.basis.z
		yaw = atan2(-cf.x, -cf.z)
	elif player.aircraft:
		var af := -player.aircraft.global_transform.basis.z
		yaw = atan2(-af.x, -af.z)
	var rot := yaw
	var pp := player.global_position
	var p2 := Vector2(pp.x, pp.z)
	var k := 2.0 * rad / MINI_RANGE_M             # px na metr
	# podklad – výřez mapy kolem hráče, otočený o rot, oříznutý do kruhu (rohy zůstanou průhledné)
	if _map_img:
		var o: Dictionary = meta["ortho_full"]
		var sc := Vector2((pp.x - float(o["x0"])) / float(o["size_x"]) * _map_img.get_width(),
			(pp.z - float(o["z0"])) / float(o["size_z"]) * _map_img.get_height())
		var ss := Vector2(MINI_RANGE_M / float(o["size_x"]) * _map_img.get_width(),
			MINI_RANGE_M / float(o["size_z"]) * _map_img.get_height())
		var cpts := PackedVector2Array()
		var ccols := PackedColorArray()
		var cuvs := PackedVector2Array()
		var ts := Vector2(_map_img.get_width(), _map_img.get_height())
		for i in range(64):
			var v := Vector2(cos(TAU * i / 64.0), sin(TAU * i / 64.0)) * rad
			cpts.append(v)
			ccols.append(Color.WHITE)
			cuvs.append((sc - ss * 0.5 + (v + Vector2(rad, rad)) * (ss / (2.0 * rad))) / ts)
		_mini.draw_set_transform(c, rot, Vector2.ONE)
		_mini.draw_polygon(cpts, ccols, cuvs, _map_img)
		_mini.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		_mini.draw_circle(c, rad, Color(0.1, 0.14, 0.09, 0.85))
	var xf := func(wx: float, wz: float) -> Vector2:
		return c + (Vector2(wx, wz) - p2).rotated(rot) * k
	# statické vrstvy z keše – každá linie má ohraničující kouli, co je celá za kruhem, přeskočí se
	if not _mini_built:
		_build_mini_cache()
	var wr := MINI_RANGE_M * 0.5 + 40.0    # světový poloměr kruhu + rezerva na tloušťku čar
	for L in _mini_lines:
		if (L[1] - p2).length() > L[2] + wr:
			continue
		var line := PackedVector2Array()
		for q in L[0]:
			line.append(xf.call(q.x, q.y))
		for seg in _clip_circle_line(line, c, rad):
			_mini.draw_polyline(seg, L[3], L[4])
	if game.water:
		for pd in game.water.ponds:
			var poly := PackedVector2Array()
			for q in pd["poly"]:
				poly.append(xf.call(q.x, q.y))
			poly = _clip_circle_poly(poly, c, rad)
			if poly.size() >= 3:
				_mini.draw_colored_polygon(poly, Color(0.35, 0.65, 1.0, 0.85))
	for key in game.places:
		var pl: Place = game.places[key]
		var mp: Vector2 = xf.call(pl.door.x, pl.door.z)
		if mp.distance_to(c) > rad - 5.0:
			continue
		if key == "domov":
			_mini.draw_rect(Rect2(mp - Vector2(4, 4), Vector2(8, 8)), Color(0.2, 0.6, 1.0))
		else:
			_mini.draw_colored_polygon(PackedVector2Array([mp + Vector2(0, -4.5), mp + Vector2(4.5, 0),
				mp + Vector2(0, 4.5), mp + Vector2(-4.5, 0)]), Color(1.0, 0.75, 0.3, 0.9))
	for it in items_root.get_children():
		if it is Item and not it._taken and it.active:
			var ipos: Vector3 = it.global_position
			var idx: float = ipos.x - p2.x
			var idz: float = ipos.z - p2.y
			if idx * idx + idz * idz > wr * wr:     # mimo kruh – transformace ani tečka se nepočítá
				continue
			var ip: Vector2 = xf.call(ipos.x, ipos.z)
			if ip.distance_to(c) <= rad - 3.0:
				_mini.draw_circle(ip, 2.0, COLORS[it.kind])
	if qs.active:
		var tg: Vector3 = qs.active.target()
		if tg != Vector3.INF:
			var tp: Vector2 = xf.call(tg.x, tg.z)
			var d := tp - c
			if d.length() > rad - 8.0:              # cíl za okrajem – šipka směru na obvodu
				tp = c + d.normalized() * (rad - 8.0)
			_mini.draw_circle(tp, 5.0, Color(1, 1, 0.2, 0.55 + 0.45 * sin(_t * 5.0)))
	var my_car: Car = game.traffic.car_of(player.id)
	if my_car:
		var cp: Vector2 = xf.call(my_car.global_position.x, my_car.global_position.z)
		if cp.distance_to(c) <= rad - 6.0:
			var cd := Vector2(my_car.global_transform.basis.z.x, my_car.global_transform.basis.z.z).rotated(rot)
			var perp := Vector2(-cd.y, cd.x)
			_mini.draw_colored_polygon(PackedVector2Array([cp + cd * 6.0, cp - cd * 3.0 + perp * 3.5,
				cp - cd * 3.0 - perp * 3.5]), Color(1.0, 0.3, 0.9))
	if game.police.checkpoint_pos != Vector3.INF and game.police.checkpoint_seen.get(player.id, false):
		var kp: Vector2 = xf.call(game.police.checkpoint_pos.x, game.police.checkpoint_pos.z)
		if kp.distance_to(c) <= rad - 6.0:
			_mini.draw_circle(kp, 4.0, Color(1, 0.3, 0.3))
			_mini.draw_string(font, kp + Vector2(-3.5, 4), "P", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
	# hráč – šipka uprostřed, míří vždy nahoru
	_mini.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -10), c + Vector2(6.5, 8),
		c + Vector2(0, 4.5), c + Vector2(-6.5, 8)]), Color(1, 0.25, 0.2))
	_mini.draw_arc(c, 10.0, 0, TAU, 24, Color(1, 1, 1, 0.45), 1.5)
	# obvodový kroužek (rohy mimo kruh zůstávají průhledné – obsah je oříznutý geometricky)
	_mini.draw_arc(c, rad + 1.5, 0, TAU, 64, Color(ACCENT, 0.7), 2.5)
	# kompas – světové strany na okraji; S (sever) zvýrazněné
	var north := float(meta.get("north_angle_deg", 78.37))
	var yaw_d := rad_to_deg(yaw)
	if _mini_dir_w.is_empty():                   # šířky textů kompasu – shape jen jednou
		for a in [[0.0, "S", true], [45.0, "SV", false], [90.0, "V", true], [135.0, "JV", false],
			[180.0, "J", true], [225.0, "JZ", false], [270.0, "Z", true], [315.0, "SZ", false]]:
			var sz0 := 15 if a[2] else 11
			_mini_dir_w.append(font.get_string_size(a[1], HORIZONTAL_ALIGNMENT_LEFT, -1, sz0).x)
	var di := 0
	for a in [[0.0, "S", true], [45.0, "SV", false], [90.0, "V", true], [135.0, "JV", false],
		[180.0, "J", true], [225.0, "JZ", false], [270.0, "Z", true], [315.0, "SZ", false]]:
		var ang := deg_to_rad(north - a[0] - yaw_d)
		var pos := c + Vector2(-sin(ang), -cos(ang)) * (rad - 13.0)
		var sz := 15 if a[2] else 11
		var w: float = _mini_dir_w[di]
		di += 1
		var tp := pos + Vector2(-w * 0.5, sz * 0.35)
		var col := Color(1.0, 0.45, 0.35) if a[1] == "S" else Color(1, 1, 1, 0.9 if a[2] else 0.55)
		_mini.draw_string_outline(font, tp, a[1], HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 3, Color(0, 0, 0, 0.9))
		_mini.draw_string(font, tp, a[1], HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)
	# měřítko – uvnitř kruhu vlevo dole (rohy jsou průhledné, venku by viselo ve vzduchu)
	var bl := 50.0 * k
	var bp := c + Vector2(-rad * 0.62, rad * 0.66)
	_mini.draw_line(bp, bp + Vector2(bl, 0), Color(1, 1, 1, 0.7), 1.5)
	_mini.draw_string(font, bp + Vector2(bl + 5, 4), "50 m", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.7))


## Keš statických vrstev minimapy (hranice katastru, vodní toky, silnice) ve světových souřadnicích
## x/z + ohraničující kruh každé linie – překres pak může rychle přeskočit, co je celé mimo kruh.
func _build_mini_cache() -> void:
	_mini_built = true
	_mini_lines.clear()
	if meta.is_empty():
		return
	var add := func(pts: PackedVector2Array, col: Color, w: float) -> void:
		if pts.size() < 2:
			return
		var cc := Vector2.ZERO
		for p in pts:
			cc += p
		cc /= float(pts.size())
		var rr := 0.0
		for p in pts:
			rr = maxf(rr, cc.distance_to(p))
		_mini_lines.append([pts, cc, rr, col, w])
	var b := PackedVector2Array()
	for q in meta.get("boundary", []):
		b.append(Vector2(q[0], q[1]))
	if b.size() > 0:
		b.append(b[0])
	add.call(b, Color(1, 1, 1, 0.45), 1.5)
	if game.water:
		for st in game.water.streams:
			var line := PackedVector2Array()
			for q in st["pts"]:
				line.append(Vector2(q.x, q.z))
			add.call(line, Color(0.35, 0.65, 1.0, 0.9), 2.0 if st["kind"] == "river" else 1.2)
	for rd in meta.get("roads", []):
		var line := PackedVector2Array()
		for q in rd["pts"]:
			line.append(Vector2(q[0], q[1]))
		var st: Array = ROAD_STYLE.get(rd["kind"], ROAD_STYLE["other"])
		add.call(line, Color(st[0], 0.85), maxf(st[1] * 0.6, 1.0))


## Lomnou čáru `pts` ořízne na kruh (střed `cc`, poloměr `r`) – vrátí seznam souvislých úseků uvnitř.
func _clip_circle_line(pts: PackedVector2Array, cc: Vector2, r: float) -> Array:
	var segs := []
	var cur := PackedVector2Array()
	var r2 := r * r
	for i in range(pts.size() - 1):
		var a := pts[i] - cc
		var d := pts[i + 1] - pts[i]
		var lo := 0.0
		var hi := 1.0
		var A := d.dot(d)
		if A > 1e-9:
			var C := a.dot(a) - r2
			var ad := a.dot(d)
			var disc := 4.0 * (ad * ad - A * C)
			if disc > 0.0:
				var sq := sqrt(disc)
				lo = maxf(0.0, (-2.0 * ad - sq) / (2.0 * A))
				hi = minf(1.0, (-2.0 * ad + sq) / (2.0 * A))
			elif C > 0.0:
				hi = -1.0                           # úplně mimo kruh
		if hi <= lo:
			if cur.size() >= 2:
				segs.append(cur)
			cur = PackedVector2Array()
			continue
		var p0 := cc + a + d * lo
		var p1 := cc + a + d * hi
		if cur.is_empty() or cur[cur.size() - 1] != p0:
			if cur.size() >= 2:
				segs.append(cur)
			cur = PackedVector2Array([p0])
		cur.append(p1)
	if cur.size() >= 2:
		segs.append(cur)
	return segs


## Polygon ořízne na kruh (Sutherland–Hodgman proti 24úhelníku) – pro vodní plochy minimapy.
func _clip_circle_poly(poly: PackedVector2Array, cc: Vector2, r: float) -> PackedVector2Array:
	var out := poly
	const N := 24
	for i in range(N):
		if out.is_empty():
			break
		var e1 := cc + Vector2(cos(TAU * i / N), sin(TAU * i / N)) * r
		var e2 := cc + Vector2(cos(TAU * (i + 1) / N), sin(TAU * (i + 1) / N)) * r
		var edge := e2 - e1
		var nxt := PackedVector2Array()
		var s := out[out.size() - 1]
		var s_in := edge.cross(s - e1) >= 0.0
		for q in out:
			var q_in := edge.cross(q - e1) >= 0.0
			var den := edge.cross(q - s)
			if q_in != s_in and absf(den) > 1e-9:
				var f := edge.cross(e1 - s) / den
				nxt.append(s + (q - s) * clampf(f, 0.0, 1.0))
			if q_in:
				nxt.append(q)
			s = q
			s_in = q_in
		out = nxt
	return out


# ------------------------------------------------------------------ pomocné

func _label(parent: Node, text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _panel(parent: Node, bg: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(8)
	s.set_content_margin_all(12)
	p.add_theme_stylebox_override("panel", s)
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(p)
	return p


## Panel nabídek (F2, obchody, pauza…) – tenký zelený rámeček, zaoblené rohy, jednotné odsazení.
func _menu_panel(parent: Node) -> PanelContainer:
	var p := _panel(parent, MENU_BG)
	var s := p.get_theme_stylebox("panel") as StyleBoxFlat
	s.set_corner_radius_all(12)
	s.set_content_margin_all(20)
	s.set_border_width_all(1)
	s.border_color = Color(ACCENT, 0.4)
	return p


## Tlačítko nabídky – jemné podbarvení a zvýraznění při najetí myší / focusu.
func _menu_button_style(b: Button) -> void:
	var n := StyleBoxFlat.new()
	n.bg_color = Color(1, 1, 1, 0.03)
	n.set_corner_radius_all(6)
	n.content_margin_left = 10
	n.content_margin_right = 10
	n.content_margin_top = 6
	n.content_margin_bottom = 6
	var h := StyleBoxFlat.new()
	h.bg_color = Color(ACCENT, 0.18)
	h.set_corner_radius_all(6)
	h.content_margin_left = 10
	h.content_margin_right = 10
	h.content_margin_top = 6
	h.content_margin_bottom = 6
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.add_theme_stylebox_override("focus", h)
	b.add_theme_color_override("font_hover_color", Color.WHITE)


func _bar(parent: Node, col: Color, w: float) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.show_percentage = false
	pb.max_value = 1.0
	pb.custom_minimum_size = Vector2(w, 10)
	var fill := StyleBoxFlat.new()
	fill.bg_color = col
	fill.set_corner_radius_all(4)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.45)
	bg.set_corner_radius_all(4)
	pb.add_theme_stylebox_override("fill", fill)
	pb.add_theme_stylebox_override("background", bg)
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(pb)
	return pb


# ------------------------------------------------------------------ okolní obce na mapě (M)
# data/obce.json → World.obce (3D zástavbu staví scripts/villages.gd): na hlavní mapě se
# kreslí tečkovaná hranice katastru, tlumené obecní silnice a název u kotvy středu – mimo
# katastr, kam ortofoto nesahá. Pohled se smí roztáhnout i za katastr (_map_extent –
# pojí ho _map_clamp), kolečko oddálí až na MAP_ZOOM_MIN. Kreslí druhý draw callback na
# _map_view (_hook_obce_map z finish_loading), ať zůstane oddělené od obsahu mapy.

## Nejmenší přiblížení mapy (M) – na něm se najednou vejde katastr i všech 5 okolních obcí.
const MAP_ZOOM_MIN := 0.5
## Hranice katastru okolní obce na mapě – tlumená okrová, kreslí se tečkovaně.
const OBEC_BOUNDARY := Color(0.85, 0.78, 0.45, 0.7)
## Název obce na mapě – teplá bělavá, čitelná i na tmavém podkladu za katastrem.
const OBEC_NAME := Color(0.96, 0.89, 0.64)
## Obecní silnice na mapě – tlumenější provedení stylů hlavních silnic: druh → [barva, px].
const OBEC_ROAD_STYLE := {
	"secondary": [Color(0.82, 0.66, 0.35, 0.55), 2.0],
	"tertiary": [Color(0.78, 0.78, 0.74, 0.5), 1.7],
	"residential": [Color(0.72, 0.72, 0.7, 0.45), 1.3],
	"unclassified": [Color(0.72, 0.72, 0.7, 0.45), 1.3],
	"service": [Color(0.62, 0.62, 0.6, 0.4), 1.0],
	"track": [Color(0.55, 0.44, 0.3, 0.45), 1.0],
	"path": [Color(0.5, 0.42, 0.3, 0.4), 0.4],
	"footway": [Color(0.5, 0.42, 0.3, 0.4), 0.4],
	"other": [Color(0.68, 0.68, 0.68, 0.4), 1.2],
}
const OBEC_DASH := 7.0         # délka čárky hranice obce na mapě (px)
const OBEC_GAP := 4.5          # mezera mezi čárkami (px)

var _map_ext := Rect2()        # oblast, kterou smí pohled mapy pokrýt (katastr + okolní obce)
var _map_ext_ok := false       # _map_ext už je spočítané (obce se za běhu nemění)


## Napojí kreslení okolních obcí na hlavní mapu (M) – volá finish_loading.
## Obce kreslí druhý draw callback na _map_view (přepsaná mapa s přiblížením a tažením);
## starší podoba mapy (_map_tex/_map_overlay) je nemá – bez _map_view se nic nenapojí.
func _hook_obce_map() -> void:
	var mv: Variant = get("_map_view")
	if mv is Control and not (mv as Control).draw.is_connected(_draw_map_obce):
		(mv as Control).draw.connect(_draw_map_obce)


## Oblast, kterou smí pohled mapy (M) pokrýt: katastr (ortho_full) + hranice všech okolních
## obcí + malá rezerva, ať se na vesnice dá dozoomovat i dotažení – ale ne donekonečna.
func _map_extent() -> Rect2:
	if not _map_ext_ok:
		var o: Dictionary = meta["ortho_full"]
		_map_ext = Rect2(float(o["x0"]), float(o["z0"]), float(o["size_x"]), float(o["size_z"]))
		var w := game as World
		if w != null:
			for ob in w.obce:
				_map_ext = _map_ext.merge(w.obec_bounds(ob))
		_map_ext = _map_ext.grow(200.0)
		_map_ext_ok = w != null and not w.obce.is_empty()   # A1-18: keš až když jsou obce načtené
	return _map_ext


## Okolní obce na _map_view – druhý draw callback (napojený v _hook_obce_map až po načtení,
## kdy World.obce existuje). Svět → pohled přepočítává stejně jako _w2v; členy přepsané
## mapy čte přes get()/call(), ať skript projde i bez nich (starší podoba mapy).
func _draw_map_obce() -> void:
	var w := game as World
	var mv: Variant = get("_map_view")
	if w == null or w.obce.is_empty() or not (mv is Control):
		return
	var cv: Variant = get("_map_center")
	var pv: Variant = call("_map_ppm")
	if not (cv is Vector2) or pv == null:
		return
	if player != null and player.body.promile() >= 2.2:
		return                                   # opilý: mapa se rozmazává (jako _draw_map_view)
	var ppm := float(pv)
	var center: Vector2 = cv
	var canvas := mv as Control
	var w2v := func(p: Vector2) -> Vector2:
		return canvas.size * 0.5 + (p - center) * ppm
	var half := canvas.size * 0.5 / maxf(ppm, 0.001)
	var vrect := Rect2(center - half, half * 2.0).grow(200.0)   # pohled ve světě + rezerva
	var font := ThemeDB.fallback_font
	_obce_build_cache(w)
	var inv := 1.0 / maxf(ppm, 0.001)
	# hranice katastrů tečkovaně (čárkování v px = přepočet při změně přiblížení) + silnice z keše
	# (A1-03: jednou, ve světových souřadnicích, bez částí uvnitř domácího katastru) pod jednou transformací
	if not is_equal_approx(_obce_dash_ppm, ppm):
		_obce_dash_ppm = ppm
		_obce_dash.clear()
		for i in _obce_bounds_pts.size():
			_obce_dash[i] = _dash_segments(_obce_bounds_pts[i], OBEC_DASH * inv, OBEC_GAP * inv)
	canvas.draw_set_transform(canvas.size * 0.5 - center * ppm, 0.0, Vector2(ppm, ppm))
	for i in _obce_dash:
		if (_obce_bounds_rect[i] as Rect2).intersects(vrect):
			canvas.draw_multiline(_obce_dash[i], OBEC_BOUNDARY, 1.4 * inv)
	for kind in _obce_roads:
		var st: Array = OBEC_ROAD_STYLE[kind]
		for chunk in _obce_roads[kind]:
			if (chunk[1] as Rect2).intersects(vrect):
				canvas.draw_multiline(chunk[0], st[0], float(st[1]) * inv)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# názvy až nad silnicemi – kotva středu s ◇ značkou (symbol obce v mapě)
	for o in w.obce:
		if not w.obec_bounds(o).intersects(vrect):
			continue
		var c: Array = o.get("center", [])
		if c.size() < 2:
			continue
		var cp: Vector2 = w2v.call(Vector2(float(c[0]), float(c[1])))
		var d := 5.0
		canvas.draw_polyline(PackedVector2Array([cp + Vector2(0, -d), cp + Vector2(d, 0),
			cp + Vector2(0, d), cp + Vector2(-d, 0), cp + Vector2(0, -d)]), OBEC_BOUNDARY, 1.4)
		var nm := String(o.get("name", ""))
		if nm == "":
			continue
		var fs := 15
		var nw := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var np := cp + Vector2(-nw * 0.5, -12.0)
		canvas.draw_string_outline(font, np, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.9))
		canvas.draw_string(font, np, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, OBEC_NAME)
	# legenda symbolu obce – vlevo dole vedle údaje o přiblížení
	var lp := Vector2(120.0, canvas.size.y - 10.0)
	canvas.draw_string(font, lp, "◇ okolní obce", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, OBEC_NAME)


## Keš obcí na mapě (A1-03): hranice (polylines), silnice po druzích v dávkách po obcích (dvojice bodů
## pro draw_multiline) a AABB pro ořez. Silnice, jejichž oba body leží v domácím katastru, se
## vynechají – ty už kreslí hlavní vrstva mapy (meta.roads), jinak by se kreslily dvakrát.
var _obce_cache_ok := false
var _obce_bounds_pts := []        # PackedVector2Array hranice (uzavřená)
var _obce_bounds_rect := []       # Rect2 hranice
var _obce_dash := {}              # index → tečkované úseky při přiblížení _obce_dash_ppm
var _obce_dash_ppm := -1.0
var _obce_roads := {}             # druh → [[PackedVector2Array dvojice, Rect2], …]


func _obce_build_cache(w: World) -> void:
	if _obce_cache_ok:
		return
	_obce_cache_ok = true
	var home := PackedVector2Array()
	for q in meta.get("boundary", []):
		home.append(Vector2(q[0], q[1]))
	var home_rect := Rect2()
	if home.size() >= 3:
		home_rect = _pts_aabb(home)
	for o in w.obce:
		var bp := PackedVector2Array()
		for q in o.get("boundary", []):
			if q is Array and q.size() >= 2:
				bp.append(Vector2(float(q[0]), float(q[1])))
		if bp.size() >= 3:
			bp.append(bp[0])
			_obce_bounds_pts.append(bp)
			_obce_bounds_rect.append(w.obec_bounds(o).grow(10.0))
		var per_kind := {}
		for rd in o.get("roads", []):
			var kind := String(rd.get("kind", "other"))
			if not OBEC_ROAD_STYLE.has(kind):
				kind = "other"
			var pts: PackedVector2Array = per_kind.get(kind, PackedVector2Array())
			var prev := Vector2.ZERO
			var has_prev := false
			for q in rd.get("pts", []):
				if q is Array and q.size() >= 2:
					var v := Vector2(float(q[0]), float(q[1]))
					if has_prev:
						var in_home: bool = home.size() >= 3 and home_rect.has_point(v) and home_rect.has_point(prev) \
							and Geometry2D.is_point_in_polygon(v, home) and Geometry2D.is_point_in_polygon(prev, home)
						if not in_home:
							pts.append(prev)
							pts.append(v)
					prev = v
					has_prev = true
			per_kind[kind] = pts
		for kind in per_kind:
			var pts: PackedVector2Array = per_kind[kind]
			if pts.size() < 2:
				continue
			if not _obce_roads.has(kind):
				_obce_roads[kind] = []
			_obce_roads[kind].append([pts, _pts_aabb(pts)])


## Lomená čára (px) → dvojice bodů úseků pro draw_multiline = tečkovaná čára (hranice obcí).
## Vzor čárka/mezera pokračuje přes vrcholy, aby obrys působil souvisle.
static func _dash_segments(pts: PackedVector2Array, dash := OBEC_DASH, gap := OBEC_GAP) -> PackedVector2Array:
	var out := PackedVector2Array()
	var on := true
	var left := dash
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var seg := a.distance_to(b)
		if seg < 0.001:
			continue
		var u := (b - a) / seg
		var s := 0.0
		while s < seg:
			var step := minf(left, seg - s)
			if on:
				out.append(a + u * s)
				out.append(a + u * (s + step))
			s += step
			left -= step
			if left <= 0.001:
				on = not on
				left = dash if on else gap
	return out
