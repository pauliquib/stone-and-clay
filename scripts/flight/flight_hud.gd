## Letecký panel (M6.3): přístroje při pilotování `Aircraft` – výška MSL/AGL, IAS,
## zemská rychlost, variometr (m/s) s tónovým pípáním v termice, kompas (kurz),
## palivo, šipka větru a výstraha přetáčení / hranice letu. Vzor droního OSD:
## `LocalClient` volá `update(st, delta)` každý frame; {} panel schová.
## Pipání variometru zní jen při stoupání (častější + vyšší tón = silnější termika).
class_name FlightHud
extends Node

const BEEP_MIN := 0.12             # nejkratší odstup pipů (s) při silném stoupání
const BEEP_BASE := 0.55            # odstup pipů při slabém stoupání (s)
const BEEP_VS := 0.4               # od této svislanky (m/s) vario pípá
const FUEL_RED := 0.15             # podíl nádrže – červené varování

var _panel: PanelContainer
var _main: Label
var _warn: Label
var _vario_p: AudioStreamPlayer    # nepolohový tón variometru (jen u pilota)
var _beep_t := 0.0
var _sfx: Sfx


## Postaví ovládací prvky pod HUD (CanvasLayer) a připraví zvuk variometru.
func setup(hud: Hud, sfx: Sfx) -> void:
	_sfx = sfx
	var root := Control.new()
	root.name = "LetovePristroje"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(root)
	_panel = PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0.5)
	s.set_corner_radius_all(8)
	s.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", s)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.offset_left = 20
	_panel.offset_bottom = -175        # stejný slot jako droní OSD (letadlo i dron zároveň neletí)
	root.add_child(_panel)
	_main = Label.new()
	_main.add_theme_font_size_override("font_size", 15)
	_main.add_theme_color_override("font_color", Color(0.8, 0.95, 1.0))
	_panel.add_child(_main)
	_panel.visible = false
	_warn = Label.new()
	_warn.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_warn.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_warn.offset_left = 20
	_warn.offset_bottom = -252
	_warn.add_theme_font_size_override("font_size", 15)
	_warn.add_theme_color_override("font_color", Color(1.0, 0.55, 0.35))
	root.add_child(_warn)
	_warn.visible = false
	_vario_p = AudioStreamPlayer.new()
	_vario_p.stream = Sfx.vario_beep()
	_vario_p.volume_db = -14.0
	add_child(_vario_p)


## Aktualizace z `Aircraft.status()`; `delta` řídí periodu pípání variometru.
func update(st: Dictionary, delta: float) -> void:
	_panel.visible = not st.is_empty()
	if st.is_empty():
		_warn.visible = false
		return
	var vs := float(st["vs"])
	var wind: Dictionary = st.get("wind", {"dir": 0.0, "ms": 0.0})
	# šipka větru relativně ke kurzu: odkud vane → kam fouká vůči nosu
	var rel := wrapf(float(wind["dir"]) - float(st["hdg"]), -180.0, 180.0)
	var arrows := ["↓", "↙", "←", "↖", "↑", "↗", "→", "↘"]
	var arrow: String = arrows[int(round((rel + 180.0) / 45.0)) % 8]
	_main.text = "%s\nALT %d m · AGL %d m\nIAS %d km/h · GS %d km/h\nVARIO %+.1f m/s\nKURZ %03d° · VÍTR %s %.0f m/s\nPALIVO %.1f / %.0f l · plyn %d %%" % [
		st["model"], roundi(float(st["alt"])), roundi(float(st["agl"])),
		roundi(float(st["ias"]) * 3.6), roundi(float(st["gs"]) * 3.6), vs,
		roundi(float(st["hdg"])), arrow, float(wind["ms"]),
		float(st["fuel"]), float(st["fuel_max"]), roundi(float(st["thr"]) * 100.0)]
	var warns: Array = st.get("warns", [])
	_warn.text = "!! " + " · ".join(warns)
	_warn.visible = not warns.is_empty()
	# variometr pípá jen za stoupání; frekvence a výška tónu rostou se stoupáním
	if vs > BEEP_VS:
		_beep_t -= delta
		if _beep_t <= 0.0:
			_beep_t = maxf(BEEP_MIN, BEEP_BASE - vs * 0.12)
			_vario_p.pitch_scale = 0.9 + minf(vs * 0.25, 0.8)
			_vario_p.play()
	else:
		_beep_t = 0.0
