## Uživatelské nastavení hry (Esc → Nastavení) v `user://nastaveni.cfg`: citlivost a obrácení myši,
## zorné pole, hlasitost, celá obrazovka, vsync a počítadlo FPS. Platí pro chůzi, auto i koně
## (citlivost a obrácení se uplatní už v LocalClient při zápisu pohybu myši do InputState).
##
## Grafika (Esc → Nastavení → Grafika): předvolba Nízká / Střední / Vysoká / Ultra nebo Vlastní –
## rozlišení 3D a upscaling, vyhlazování, stíny slunce, dohlednost (násobí visibility_range všech modelů,
## i těch přidaných později – `node_added`), vegetace kolem hráče (květy, ovoce, listí), záře, SSAO, strop FPS.
class_name GameSettings
extends RefCounted

const PATH := "user://nastaveni.cfg"
const VSYNC_NAMES := ["Mailbox (doporučeno)", "Zapnuto (FIFO)", "Vypnuto"]
const VSYNC_MODES := [DisplayServer.VSYNC_MAILBOX, DisplayServer.VSYNC_ENABLED, DisplayServer.VSYNC_DISABLED]
## Vykreslovací backend Godotu – nejde přepnout za běhu, jen uložit pro příští spuštění
## (run.sh si tuhle hodnotu přečte a hru spustí s --rendering-method).
const RENDERER_NAMES := ["Forward+ (kvalitnější, potřebuje slušnou GPU)", "Mobile (rychlejší na slabé/integrované grafice)"]
const RENDERER_VALUES := ["forward_plus", "mobile"]

var mouse_sens := 1.0        # násobek výchozí citlivosti
var invert_y := false
var fov := 72.0              # základní zorné pole postavy (°)
var volume := 1.0            # hlavní hlasitost 0–1
var fullscreen := false
var vsync := 0               # index do VSYNC_MODES
var trike_intuitive := false # M6.5: arkádové řízení rogala hrazdou (W = nahoru); výchozí realistické obrácené
var show_fps := true
var vsync_from_args := false # --vsync / --novsync na příkazové řádce má přednost před uloženým nastavením
var maxfps_from_args := false
var renderer := "forward_plus"  # uloženo do nastaveni.cfg, čte ho run.sh (projeví se až po restartu hry)

# --- grafika (indexy do tabulek níž)
const PRESET_NAMES := ["Nízká", "Střední", "Vysoká", "Ultra", "Vlastní"]
const SCALES := [0.5, 0.67, 0.75, 0.85, 1.0]
const SCALE_NAMES := ["50 %", "67 %", "75 %", "85 %", "100 % (nativní)"]
const UPSCALE_NAMES := ["Bilineární", "FSR 1 (ostřejší)", "FSR 2 (nejkvalitnější, náročnější)"]
const AA_NAMES := ["Vypnuto", "FXAA (nejlevnější)", "MSAA 2×", "MSAA 4×", "TAA"]
const SHADOW_NAMES := ["Vypnuto", "Nízké", "Střední", "Vysoké", "Ultra"]
## stíny: [velikost mapy, 4 pásma?, dosah m, kvalita měkkých stínů 0–3]
const SHADOWS := [[0, false, 0.0, 0], [2048, false, 110.0, 0], [2048, true, 180.0, 1], [4096, true, 240.0, 2],
	[8192, true, 320.0, 3]]
const VIEWS := [0.6, 0.8, 1.0, 1.25]
const VIEW_NAMES := ["Krátká", "Střední", "Daleká", "Velmi daleká"]
const VEGS := [0.0, 0.5, 0.75, 1.0]
const VEG_NAMES := ["Vypnuto", "Málo", "Středně", "Plně"]
const FPS_CAPS := [0, 30, 60, 75, 120, 144]
const FPS_NAMES := ["Bez omezení", "30", "60", "75", "120", "144"]
## předvolby: scale, upscale, aa, shadows, view, veg, glow, ssao
const PRESETS := [
	{"scale": 0, "upscale": 1, "aa": 0, "shadows": 0, "view": 0, "veg": 0, "glow": false, "ssao": false},
	{"scale": 3, "upscale": 1, "aa": 1, "shadows": 2, "view": 1, "veg": 1, "glow": true, "ssao": false},
	{"scale": 4, "upscale": 0, "aa": 2, "shadows": 3, "view": 2, "veg": 3, "glow": true, "ssao": false},
	{"scale": 4, "upscale": 0, "aa": 3, "shadows": 4, "view": 3, "veg": 3, "glow": true, "ssao": true},
]
const GFX_KEYS := ["scale", "upscale", "aa", "shadows", "view", "veg", "glow", "ssao"]

var preset := 2
var gfx: Dictionary = PRESETS[2].duplicate()
var fps_cap := 0
var _view_applied := 1.0
var _atlas := -1                 # naposledy nastavená velikost mapy stínů (přealokace = záškub – jen při změně)
var _soft := -1
var _hooked := false


func load_file() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	mouse_sens = clampf(float(cf.get_value("ovladani", "citlivost", mouse_sens)), 0.2, 3.0)
	invert_y = bool(cf.get_value("ovladani", "obratit_y", invert_y))
	trike_intuitive = bool(cf.get_value("ovladani", "rogalo_intuitivni", trike_intuitive))
	fov = clampf(float(cf.get_value("obraz", "fov", fov)), 55.0, 95.0)
	fullscreen = bool(cf.get_value("obraz", "cela_obrazovka", fullscreen))
	vsync = clampi(int(cf.get_value("obraz", "vsync", vsync)), 0, VSYNC_MODES.size() - 1)
	show_fps = bool(cf.get_value("obraz", "fps", show_fps))
	volume = clampf(float(cf.get_value("zvuk", "hlasitost", volume)), 0.0, 1.0)
	preset = clampi(int(cf.get_value("grafika", "predvolba", preset)), 0, PRESET_NAMES.size() - 1)
	for k in GFX_KEYS:
		gfx[k] = cf.get_value("grafika", k, gfx[k])
	fps_cap = clampi(int(cf.get_value("grafika", "strop_fps", fps_cap)), 0, FPS_CAPS.size() - 1)
	renderer = String(cf.get_value("grafika", "renderer", renderer))
	if not RENDERER_VALUES.has(renderer):
		renderer = RENDERER_VALUES[0]


func save_file() -> void:
	var cf := ConfigFile.new()
	cf.set_value("ovladani", "citlivost", mouse_sens)
	cf.set_value("ovladani", "obratit_y", invert_y)
	cf.set_value("ovladani", "rogalo_intuitivni", trike_intuitive)
	cf.set_value("obraz", "fov", fov)
	cf.set_value("obraz", "cela_obrazovka", fullscreen)
	cf.set_value("obraz", "vsync", vsync)
	cf.set_value("obraz", "fps", show_fps)
	cf.set_value("zvuk", "hlasitost", volume)
	cf.set_value("grafika", "predvolba", preset)
	for k in GFX_KEYS:
		cf.set_value("grafika", k, gfx[k])
	cf.set_value("grafika", "strop_fps", fps_cap)
	cf.set_value("grafika", "renderer", renderer)
	cf.save(PATH)


## Uplatní vše, co nejde přes LocalClient (okno, vsync, zvuk, zorné pole, FPS).
func apply(client: Node) -> void:
	var win_mode := DisplayServer.window_get_mode()
	var is_full := win_mode == DisplayServer.WINDOW_MODE_FULLSCREEN or win_mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if fullscreen != is_full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	if not vsync_from_args and DisplayServer.window_get_vsync_mode() != VSYNC_MODES[vsync]:
		DisplayServer.window_set_vsync_mode(VSYNC_MODES[vsync])
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))
	AudioServer.set_bus_mute(0, volume <= 0.0)
	if client.player:
		client.player.base_fov = fov
	if client.hud:
		client.hud.show_fps = show_fps
	apply_graphics(client)


## Předvolba grafiky (0–3) → všechny volby; změna jednotlivé volby přepne na „Vlastní“ (4).
func set_preset(i: int) -> void:
	preset = i
	if i < PRESETS.size():
		gfx = PRESETS[i].duplicate()


func set_gfx(key: String, v) -> void:
	gfx[key] = v
	preset = PRESET_NAMES.size() - 1
	for i in PRESETS.size():
		if PRESETS[i] == gfx:
			preset = i


func apply_graphics(client: Node) -> void:
	var vp: Viewport = client.get_viewport()
	# rozlišení 3D a upscaling (HUD zůstává v plném rozlišení)
	var sc: float = SCALES[clampi(int(gfx["scale"]), 0, SCALES.size() - 1)]
	var up := clampi(int(gfx["upscale"]), 0, 2)
	vp.scaling_3d_scale = sc
	if sc >= 0.999:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	else:
		vp.scaling_3d_mode = [Viewport.SCALING_3D_MODE_BILINEAR, Viewport.SCALING_3D_MODE_FSR,
			Viewport.SCALING_3D_MODE_FSR2][up]
	# vyhlazování (FSR 2 má vlastní časové vyhlazování – TAA / MSAA by jen stály výkon)
	var aa := clampi(int(gfx["aa"]), 0, 4)
	var fsr2 := sc < 0.999 and up == 2
	vp.msaa_3d = Viewport.MSAA_DISABLED if fsr2 else [Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_2X,
		Viewport.MSAA_4X, Viewport.MSAA_DISABLED][aa]
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa == 1 and not fsr2 else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = aa == 4 and not fsr2
	# stíny slunce
	var sh: Array = SHADOWS[clampi(int(gfx["shadows"]), 0, SHADOWS.size() - 1)]
	var sun: DirectionalLight3D = client.sun
	if sun:
		sun.shadow_enabled = int(sh[0]) > 0
		if sun.shadow_enabled:
			if _atlas != int(sh[0]):
				_atlas = int(sh[0])
				RenderingServer.directional_shadow_atlas_set_size(_atlas, true)
			if _soft != int(sh[3]):
				_soft = int(sh[3])
				RenderingServer.directional_soft_shadow_filter_set_quality(_soft)
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if sh[1] \
				else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			sun.directional_shadow_max_distance = float(sh[2])
	# záře a stínování okolím
	var env: Environment = client.env
	if env:
		env.glow_enabled = bool(gfx["glow"])
		env.ssao_enabled = bool(gfx["ssao"])
	# vegetace kolem hráče
	var veg: float = VEGS[clampi(int(gfx["veg"]), 0, VEGS.size() - 1)]
	if client.season_fx and client.season_fx.flowers:
		client.season_fx.flowers.set_detail(veg)
		client.season_fx.decor.set_detail(veg)
	# strop FPS (--maxfps má přednost)
	if not maxfps_from_args:
		Engine.max_fps = FPS_CAPS[clampi(fps_cap, 0, FPS_CAPS.size() - 1)]
	# dohlednost
	var view: float = VIEWS[clampi(int(gfx["view"]), 0, VIEWS.size() - 1)]
	var tree: SceneTree = client.get_tree()
	if not _hooked:
		_hooked = true
		tree.node_added.connect(_on_node_added)
	if not is_equal_approx(view, _view_applied):
		_view_applied = view
		for n in tree.root.find_children("*", "GeometryInstance3D", true, false):
			_scale_range(n)


func _on_node_added(n: Node) -> void:
	if n is GeometryInstance3D and not is_equal_approx(_view_applied, 1.0):
		_scale_range.call_deferred(n)       # rozsah se často nastavuje až po add_child


## Vynásobí dohled modelu `_view_applied` (původní hodnoty si pamatuje v meta).
func _scale_range(n: Node) -> void:
	if not is_instance_valid(n) or n is Label3D:
		return
	var g := n as GeometryInstance3D
	if not g.has_meta("vr0"):
		if g.visibility_range_end <= 0.0:
			return
		g.set_meta("vr0", Vector4(g.visibility_range_begin, g.visibility_range_end,
			g.visibility_range_begin_margin, g.visibility_range_end_margin))
	var o: Vector4 = g.get_meta("vr0")
	g.visibility_range_begin = o.x * _view_applied
	g.visibility_range_end = o.y * _view_applied
	g.visibility_range_begin_margin = o.z * _view_applied
	g.visibility_range_end_margin = o.w * _view_applied


## Pohyb myši (px) upravený podle citlivosti a obrácení osy Y.
func look(rel: Vector2) -> Vector2:
	return Vector2(rel.x, -rel.y if invert_y else rel.y) * mouse_sens
