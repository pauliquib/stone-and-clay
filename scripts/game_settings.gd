## Uživatelské nastavení hry (Esc → Nastavení) v `user://nastaveni.cfg`: citlivost a obrácení myši,
## zorné pole, hlasitost, celá obrazovka, vsync a počítadlo FPS. Platí pro chůzi, auto i koně
## (citlivost a obrácení se uplatní už v LocalClient při zápisu pohybu myši do InputState).
##
## Grafika (Esc → Nastavení → Grafika): předvolba Nízká / Střední / Vysoká / Ultra nebo Vlastní –
## rozlišení 3D a upscaling, vyhlazování, stíny slunce, dohlednost (násobí visibility_range všech modelů,
## i těch přidaných později – `node_added`), vegetace kolem hráče (květy, ovoce, listí), záře, SSAO, strop FPS.
## Podání barev světa (tonemapping, sytost, kontrast) stojí mimo předvolby – je to věc vkusu, tak přepnutí
## předvolby nezhasne oblíbené barvy (stejně jako renderer a strop FPS).
class_name GameSettings
extends RefCounted

## M8.1: přepínače realismu – jeden slovník se čte i zapisuje z `World.realism` (stejná instance,
## `Main._ready` dá `world.realism = client.settings.realism`), aby šlo zapnout/vypnout každý krok
## M8 zvlášť (Esc → Nastavení → Realismus) bez zásahu do kódu. Klíč = krok (00_PRINCIPY kap. 5),
## hodnota `bool` (grafické kroky mají výchozí stav podle předvolby – nastaví si ho jejich vlastní krok).
## Řádky v menu (popisek, nápověda, odhad cfeny) přidává `REALISM_ROWS` – každý krok M8 svůj.
signal realism_changed(key: String, on: bool)

const REALISM_KEYS := ["site", "species", "wind", "sky", "gait", "soil_water", "treegen", "micro",
	"animal_gait", "phenology", "crops", "terramech", "ground_veg", "habitat", "thermo", "village_life", "soundscape"]
## Řádky menu Realismus: [klíč, popisek, nápověda, odhad cena (text)] – prázdné, dokud ho nenaplní krok,
## který přepínač zavádí (data, ne větvení v `pause_menu.gd`).
const REALISM_ROWS: Array = [
	["sky", "Fyzikální obloha a expozice", "Obloha a slunce v luxech (Rayleigh/Mie), adaptace oka, pás Venuše při soumraku. Vypnuto = stará ruční obloha.", "≤ 0,8 ms GPU"],
	["gait", "Pohyb člověka", "Fázová chůze/běh, chodidla na terénu, kymácení pánve (M8.6)", "~0,05 ms/postava"],
	["thermo", "Tělo: teplo, žízeň, spánek", "Tepelná bilance těla (námaha hřeje, mokro a vítr chladí, slunce, oheň), žízeň, ospalost a mikrospánek, zranění pádem podle výšky (M8.16); vypnuto = staré „pocitové“ prochladnutí", "~0,02 ms"],
	["species", "Dřeviny a porosty", "Druh, věk a vitalita stromů podle stanoviště: cena dřeva při kácení, „Prohlédnout strom“, ovoce jen na ovocných druzích (M8.3). Vypnuto = staré chování.", "≈ 0 ms (data offline)"],
	["wind", "Pole větru", "Nárazy běžící krajinou, závětří a hřebeny, ohyb stromů po úrovních, vlny přes obilí; létání, kouř a čich zvěře podle větru v místě (M8.4). Vypnuto = jedno číslo a sinusovka.", "≤ 0,3 ms GPU"],
	["animal_gait", "Lokomoce zvířat a let ptáků", "Chody podle Froudova čísla s plynulými přechody, ohyb páteře, uši a ocas jako pružiny (uši ke zvuku), skoky srnce v obilí; ptáci mávají / kloužou / plachtí v termice, přistávají s brzděním, létají proti větru; podzimní hejna špačků (M8.10). Vypnuto = dřívější pohyb.", "~0,1–0,3 ms CPU"],
	["soil_water", "Vodní bilance", "Vlhkost půdy, tání sněhu, odtok, potoky stoupají a kalní po bouřce, v suchu vysychají; bláto a louže podle místa (M8.7). Vypnuto = jedno globální mokro.", "~0,1 ms CPU"],
	["treegen", "Generované stromy", "Tvar stromu podle druhu, věku a vitality (kužel smrku, kopule buku, bílá bříza), listí a kůra z atlasu, impostory v dálce (M8.8). Projeví se po novém načtení světa. Vypnuto = 6 původních modelů.", "≈ jako dřív (ověřit --perfscene)"],
	["crops", "Plodiny podle počasí", "Zahrada a pole rostou podle sum teplot, vody v půdě a světla (stín): v suchu slabá úroda, mráz spálí rajčata, v teplém suchém létě se žne dřív; zálivka plní záhon (M8.12). Vypnuto = růstové dny a kalendář polí.", "~0,05 ms CPU"],
	["micro", "Mikroklima", "Za jasné bezvětrné noci studený vzduch v údolích a kotlinách, ranní údolní mlha, rosa a jinovatka, teplé jižní svahy, chladný les, teplejší obec; HUD a tělo berou teplotu v místě (M8.9). Vypnuto = teplota všude stejná.", "~0,05 ms CPU, mlha ≈ 0 ms GPU"],
	["phenology", "Fenologie a růst stromů", "Každý druh raší, kvete a barví se podle sumy teplot letošního roku a místa (bříza dřív než dub, kotlina jinak než jižní svah), pozdní mráz spálí květy a ubere ovoce, stromy rostou v letech (M8.11). Vypnuto = jednotný kalendář Seasons.", "≈ 0 ms CPU (denní krok), ≤ 0,1 ms GPU"],
	["ground_veg", "Louky, seč a interaktivní tráva", "Louka podle stanoviště (vlhká v nivě, suchá na stráni), sedláci sečou 2× ročně (nízká tráva, řádky sena a balíky), neposekané louky zarůstají keři a náletem; tráva a obilí se rozhrnují kolem hráče, zvířat a kol a za opakovanou chůzí zůstane pěšina (M8.14). Vypnuto = tráva všude stejná a nehybná.", "~0,05 ms CPU, ≤ 0,6 ms GPU"],
	["habitat", "Stanoviště a populace zvěře", "Srnci ve dne leží v houštinách a za soumraku vycházejí na pole u lesa, v zimě v závětří a u krmelců; prasata v semenném roce v bučinách a doubravách, jindy v kukuřici; počet zvěře roste mláďaty a klesá zimou, lovem a auty, prasata ryjí louky (M8.15). Vypnuto = zvěř podle starých stanovišť a pevných okrsků.", "~0,05 ms CPU (denní přepočet po kouscích)"],
	["village_life", "Život vesnice", "Domácnosti s plánem dne: kuchyně se rozsvěcují ráno a ložnice před spaním, komíny kouří podle topení a toho, kdo je doma, o víkendu se štípe dřevo a seká tráva (ne v neděli), sousedé si pomáhají a hádají, drby z událostí se šíří od hospody (M8.17). Vypnuto = okna a komíny podle pravděpodobnosti, vesničané se jen procházejí.", "~0,05 ms CPU (hodinový krok po kouscích)"],
	["soundscape", "Zvuková krajina a drobný život", "Ptačí chorál podle druhu, měsíce a minut od východu slunce (kos první, kukačka v květnu, puštík v noci), cvrčci tím rychleji, čím je tepleji, žáby u rybníků na jaře, šumění korun podle větru a druhu, ozvěna v údolí; netopýři za soumraku, světlušky v červnu, motýli nad kvetoucí loukou (M8.18). Vypnuto = jen staré hlasy zvířat.", "≤ 0,2 ms CPU (výběr zdrojů 2×/s, 16 hlasů)"],
	["terramech", "Bláto a koleje", "Kola, boty a kopyta se boří do měkké půdy podle druhu půdy a vlhkosti: auto na rozmáčené louce zapadne, traktor projede a nechá koleje, které mizí deštěm; chůze blátem je pomalejší (M8.13). Vypnuto = přilnavost jen z počasí.", "~0,05 ms CPU (hráčovo vozidlo), ≈ 0,1 ms GPU"],
]

var realism: Dictionary = {}

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
var trike_realistic := false # M6.5 / vlna 0d: realistické obrácené řízení rogala hrazdou; výchozí intuitivní (W = nahoru, A = vlevo)
var show_fps := true
var withdrawal_shake := true # třes obrazu při abstinenci a zimě (Esc → Nastavení → Třes obrazu)
var image_fx := true        # M4.8: Efekty obrazu (opilost, látky, zranění) – nezávisle na obsahu pro dospělé; ovládá DrunkFx
var adult_content := false   # M4.8: obsah pro dospělé (návykové látky) – výchozí vypnuto; vypnuto = obsah ve hře není (Esc → Nastavení)
var vsync_from_args := false # --vsync / --novsync na příkazové řádce má přednost před uloženým nastavením
var maxfps_from_args := false
var renderer := "forward_plus"  # uloženo do nastaveni.cfg, čte ho run.sh (projeví se až po restartu hry)
var dev_mode := false        # M8.D: Režim vývojáře – odemyká menu F3 (ladění parametrů, DevTune); výchozí vypnuto

# --- grafika (indexy do tabulek níž)
const PRESET_NAMES := ["Nízká", "Střední", "Vysoká", "Ultra", "Vlastní"]
const SCALES := [0.5, 0.67, 0.75, 0.85, 1.0]
const SCALE_NAMES := ["50 %", "67 %", "75 %", "85 %", "100 % (nativní)"]
const UPSCALE_NAMES := ["Bilineární", "FSR 1 (ostřejší)", "FSR 2 (nejkvalitnější, náročnější)"]
const AA_NAMES := ["Vypnuto", "FXAA (nejlevnější)", "MSAA 2×", "MSAA 4×", "TAA"]
const SHADOW_NAMES := ["Vypnuto", "Nízké", "Střední", "Vysoké", "Ultra"]
## stíny: [velikost mapy, 4 pásma?, dosah m, kvalita měkkých stínů 0–3]. Prolínání pásem (blend_splits) jen se 4 pásmy.
## Optimalizace GPU (17. 10. 2026): Střední 4 pásma / 180 m / měkké 1 → 2 pásma / 120 m / tvrdé – na vsi kreslí stínový
## průchod každou postavu (~12 dílů), auto a buňku stromů LOD1 znovu v každém pásmu, kam zasáhne; 2 pásma a kratší dosah
## ≈ polovina stínových draw callů.
const SHADOWS := [[0, false, 0.0, 0], [2048, false, 110.0, 0], [2048, false, 120.0, 0], [4096, true, 240.0, 2],
	[8192, true, 320.0, 3]]
## Optimalizace GPU (17. 10. 2026): práh LOD meshů (`Viewport.mesh_lod_threshold`, výchozí Godot 1) podle dohlednosti –
## vyšší = dřív hrubší LOD u importovaných modelů s automatickými LOD (.glb); meshe skládané v kódu LOD nemají.
const MESH_LODS := [4.0, 2.0, 1.0, 1.0]
## F3 → Svět/Vykreslování (tune_m8_19.gd): násobek dosahu stínů slunce a práh LOD navíc k předvolbě (1 = beze změny).
static var SHADOW_DIST_K := 1.0
static var MESH_LOD_K := 1.0
## Verze tabulky PRESETS: uložené nastavení se starší verzí a pojmenovanou předvolbou (ne Vlastní) se při načtení
## přepíše novými hodnotami předvolby (jinak by hráč na „Střední“ dál měl staré drahé hodnoty z nastaveni.cfg).
const PRESETS_VER := 2
const VIEWS := [0.6, 0.8, 1.0, 1.25]
const VIEW_NAMES := ["Krátká", "Střední", "Daleká", "Velmi daleká"]
const VEGS := [0.0, 0.5, 0.75, 1.0]
const VEG_NAMES := ["Vypnuto", "Málo", "Středně", "Plně"]
## aktivita světa: poloměr plné simulace okolo hráče (NPC, zvířata, doprava)
const SIMS := [250.0, 400.0, 600.0, 900.0]
const SIM_NAMES := ["Malá", "Střední", "Velká", "Maximální"]
const FPS_CAPS := [0, 30, 60, 75, 120, 144]
const FPS_NAMES := ["Bez omezení", "30", "60", "75", "120", "144"]
## M8.19B: detail přírody M8 (gfx klíč "eco") – jen vzhled a zvuk u klienta; simulace (voda, mikroklima, fenologie,
## plodiny, populace, domácnosti…) běží na všech úrovních stejně. Konzervativně (čísla z --perfscene po M8 zatím nejsou,
## viz docs/testy_M8.md → Plán testování): Nízký = vzhled jako před M8, Střední střídmě, plné jen Vysoký / Ultra.
const ECO_NAMES := ["Nízký (vzhled jako před M8)", "Střední (střídmě)", "Vysoký (plný)", "Ultra (delší LOD stromů)"]
## lod0 = násobek dosahu LOD0 generovaných stromů (TreeGen.L0_END 55 m), trample = interaktivní tráva (sešlapání),
## life = hustota drobného života (0 = nekreslí se), voices = nejvýš současných hlasů zvukové krajiny (pool 16),
## sound_r = násobek okruhu výběru zdrojů (SCAN_R 200 m), fog_layer = údolní mlha jako vrstva (M8.9),
## sky = fyzikální obloha (přepínač realismu „sky“ – nastaví se jen při volbě předvolby / detailu, ne při každém startu).
## lod1 = násobek hranice LOD1 → impostor (TreeGen.L1_END 170 m) – optimalizace GPU 17. 10. 2026 (Střední lod0 0,75 → 0,6,
## lod1 1,0 → 0,8: buňky LOD1 do ~154 m místo ~188 m = ~⅔ plochy).
const ECO_LEVELS := [
	{"lod0": 0.5, "lod1": 0.75, "trample": false, "life": 0.0, "voices": 6, "sound_r": 0.6, "fog_layer": false, "sky": false},
	{"lod0": 0.6, "lod1": 0.8, "trample": false, "life": 0.5, "voices": 10, "sound_r": 0.8, "fog_layer": true, "sky": true},
	{"lod0": 1.0, "lod1": 1.0, "trample": true, "life": 1.0, "voices": 16, "sound_r": 1.0, "fog_layer": true, "sky": true},
	{"lod0": 1.3, "lod1": 1.15, "trample": true, "life": 1.0, "voices": 16, "sound_r": 1.0, "fog_layer": true, "sky": true},
]
## předvolby: scale, upscale, aa, shadows, view, veg, sim, glow, ssao, eco (M8.19B)
## Optimalizace GPU (17. 10. 2026, PRESETS_VER 2): Střední mířena na 16,6 ms na GTX 1050 – rozlišení 3D 85 → 75 % (FSR 1),
## bez záře, stíny Střední = 2 pásma / 120 m / tvrdé, kratší LOD stromů (ECO_LEVELS[1]). Vysoká / Ultra beze změny.
const PRESETS := [
	{"scale": 0, "upscale": 1, "aa": 0, "shadows": 0, "view": 0, "veg": 0, "sim": 0, "glow": false, "ssao": false, "eco": 0},
	{"scale": 2, "upscale": 1, "aa": 1, "shadows": 2, "view": 1, "veg": 1, "sim": 1, "glow": false, "ssao": false, "eco": 1},
	{"scale": 4, "upscale": 0, "aa": 2, "shadows": 3, "view": 2, "veg": 3, "sim": 2, "glow": true, "ssao": false, "eco": 2},
	{"scale": 4, "upscale": 0, "aa": 3, "shadows": 4, "view": 3, "veg": 3, "sim": 3, "glow": true, "ssao": true, "eco": 3},
]
const GFX_KEYS := ["scale", "upscale", "aa", "shadows", "view", "veg", "sim", "glow", "ssao", "eco"]
## podání barev: [tonemapper, sytost, kontrast, bílá (tonemap_white)] – Přirozené odpovídá původnímu
## vzhledu (LocalClient.build_environment); sytější režimy jedou přes ACES (víc kontrastu a nasycení
## než Filmic; AgX je až od Godotu 4.4)
const COLOR_NAMES := ["Přirozené", "Syté (truecolor)", "Živé"]
const COLORS := [
	[Environment.TONE_MAPPER_FILMIC, 1.08, 1.0, 6.0],
	[Environment.TONE_MAPPER_ACES, 1.18, 1.05, 6.0],
	[Environment.TONE_MAPPER_ACES, 1.32, 1.1, 4.5],
]

var preset := 2
var gfx: Dictionary = PRESETS[2].duplicate()
var fps_cap := 0
var color_mode := 0
var _view_applied := 1.0
var _atlas := -1                 # naposledy nastavená velikost mapy stínů (přealokace = záškub – jen při změně)
var _soft := -1
var _hooked := false
static var _live: GameSettings = null   # F3 (tune_m8_19.gd): kdo naposledy aplikoval grafiku – pro `reapply_live()`
static var _live_client: WeakRef = null


func _init() -> void:
	for k in REALISM_KEYS:        # M8.1: výchozí zapnuto; grafický krok si svůj klíč podle předvolby doladí sám
		realism[k] = true


## Zapnuto, i když to krok, který klíč zavádí, ještě není hotový (fallback, 00_PRINCIPY kap. 3).
func realism_on(key: String) -> bool:
	return bool(realism.get(key, true))


func set_realism(key: String, on: bool) -> void:
	if bool(realism.get(key, true)) == on:
		return
	realism[key] = on
	realism_changed.emit(key, on)


func load_file() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	mouse_sens = clampf(float(cf.get_value("ovladani", "citlivost", mouse_sens)), 0.2, 3.0)
	invert_y = bool(cf.get_value("ovladani", "obratit_y", invert_y))
	trike_realistic = bool(cf.get_value("ovladani", "rogalo_realisticke", trike_realistic))   # starý klíč rogalo_intuitivni se ignoruje
	fov = clampf(float(cf.get_value("obraz", "fov", fov)), 55.0, 95.0)
	fullscreen = bool(cf.get_value("obraz", "cela_obrazovka", fullscreen))
	vsync = clampi(int(cf.get_value("obraz", "vsync", vsync)), 0, VSYNC_MODES.size() - 1)
	show_fps = bool(cf.get_value("obraz", "fps", show_fps))
	withdrawal_shake = bool(cf.get_value("obraz", "tres", withdrawal_shake))
	image_fx = bool(cf.get_value("obraz", "efekty", image_fx))
	DrunkFx.enabled = image_fx     # M4.8: DrunkFx ví, jestli kreslit efekty
	adult_content = bool(cf.get_value("obsah", "dospeli", adult_content))
	ItemsDB.adult_on = adult_content     # M4.8: katalog hned ví, jestli je obsah pro dospělé zapnutý
	volume = clampf(float(cf.get_value("zvuk", "hlasitost", volume)), 0.0, 1.0)
	preset = clampi(int(cf.get_value("grafika", "predvolba", preset)), 0, PRESET_NAMES.size() - 1)
	if preset < PRESETS.size():
		gfx = PRESETS[preset].duplicate()      # M8.19B: chybějící klíč (starý cfg bez "eco") → hodnota uložené předvolby
	# optimalizace GPU 17. 10. 2026: pojmenovaná předvolba ze starší tabulky → nové hodnoty předvolby (cfg se nečte)
	var old_presets := int(cf.get_value("grafika", "verze_predvoleb", 1)) < PRESETS_VER and preset < PRESETS.size()
	if not old_presets:
		for k in GFX_KEYS:
			gfx[k] = cf.get_value("grafika", k, gfx[k])
	fps_cap = clampi(int(cf.get_value("grafika", "strop_fps", fps_cap)), 0, FPS_CAPS.size() - 1)
	color_mode = clampi(int(cf.get_value("grafika", "barvy", color_mode)), 0, COLORS.size() - 1)
	renderer = String(cf.get_value("grafika", "renderer", renderer))
	if not RENDERER_VALUES.has(renderer):
		renderer = RENDERER_VALUES[0]
	for k in REALISM_KEYS:        # M8.1: přepínače realismu (sekce [realismus]); starý cfg bez klíče = výchozí true
		realism[k] = bool(cf.get_value("realismus", k, realism.get(k, true)))
	dev_mode = bool(cf.get_value("vyvojar", "rezim", dev_mode))     # M8.D


func save_file() -> void:
	var cf := ConfigFile.new()
	cf.set_value("ovladani", "citlivost", mouse_sens)
	cf.set_value("ovladani", "obratit_y", invert_y)
	cf.set_value("ovladani", "rogalo_realisticke", trike_realistic)
	cf.set_value("obraz", "fov", fov)
	cf.set_value("obraz", "cela_obrazovka", fullscreen)
	cf.set_value("obraz", "vsync", vsync)
	cf.set_value("obraz", "fps", show_fps)
	cf.set_value("obraz", "tres", withdrawal_shake)
	cf.set_value("obraz", "efekty", image_fx)
	cf.set_value("obsah", "dospeli", adult_content)
	cf.set_value("zvuk", "hlasitost", volume)
	cf.set_value("grafika", "predvolba", preset)
	cf.set_value("grafika", "verze_predvoleb", PRESETS_VER)
	for k in GFX_KEYS:
		cf.set_value("grafika", k, gfx[k])
	cf.set_value("grafika", "strop_fps", fps_cap)
	cf.set_value("grafika", "barvy", color_mode)
	cf.set_value("grafika", "renderer", renderer)
	for k in REALISM_KEYS:
		cf.set_value("realismus", k, bool(realism.get(k, true)))
	cf.set_value("vyvojar", "rezim", dev_mode)
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
		client.player.shake_enabled = withdrawal_shake
	if client.hud:
		client.hud.show_fps = show_fps
	apply_graphics(client)


## Předvolba grafiky (0–3) → všechny volby; změna jednotlivé volby přepne na „Vlastní“ (4).
func set_preset(i: int) -> void:
	preset = i
	if i < PRESETS.size():
		gfx = PRESETS[i].duplicate()
		_eco_realism()


func set_gfx(key: String, v) -> void:
	gfx[key] = v
	preset = PRESET_NAMES.size() - 1
	for i in PRESETS.size():
		if PRESETS[i] == gfx:
			preset = i
	if key == "eco":
		_eco_realism()


## M8.19B: úroveň detailu přírody (index do ECO_LEVELS).
func eco_level() -> Dictionary:
	return ECO_LEVELS[clampi(int(gfx.get("eco", 2)), 0, ECO_LEVELS.size() - 1)]


## M8.19B: grafické přepínače realismu, které určuje předvolba (00_PRINCIPY kap. 5) – jen při výslovné volbě
## předvolby / detailu přírody, aby start hry nepřepisoval, co si hráč vypnul / zapnul v Realismu ručně.
func _eco_realism() -> void:
	set_realism("sky", bool(eco_level()["sky"]))


## M8.19B: detail přírody do běžících systémů klienta (stromy LOD0, interaktivní tráva, drobný život, zvuková krajina,
## údolní mlha). Systém, který ještě neexistuje, si hodnotu vezme při dalším `apply_graphics` (start, změna v Nastavení).
func _apply_eco(client: Node) -> void:
	var lv := eco_level()
	if MapLoader.tree_gen != null:
		MapLoader.tree_gen.set_lod_scales(float(lv["lod0"]), float(lv.get("lod1", 1.0)))
	if client.world and client.world.vegetation and client.world.vegetation.fx:
		client.world.vegetation.fx.interactive = bool(lv["trample"])
	var ss: Soundscape = client.get("soundscape")
	if ss:
		ss.set_detail(int(lv["voices"]), float(lv["sound_r"]))
	var sl: SmallLife = client.get("small_life")
	if sl:
		sl.density = float(lv["life"])
	MicroFx.layer_on = bool(lv["fog_layer"])


func apply_graphics(client: Node) -> void:
	_live = self
	_live_client = weakref(client)
	# kvalita vzhledu pro shadery (global `gfx_quality` 0–3 = detail přírody): dražší efekty jen od Vysoké (≥ 2),
	# Nízká a Střední zůstávají na původní ceně
	RenderingServer.global_shader_parameter_set("gfx_quality", float(clampi(int(gfx.get("eco", 2)), 0, 3)))
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
			sun.directional_shadow_blend_splits = bool(sh[1])     # prolínání pásem = druhé čtení mapy na pixel
			sun.directional_shadow_max_distance = float(sh[2]) * SHADOW_DIST_K
	# záře a stínování okolím
	var env: Environment = client.env
	if env:
		env.glow_enabled = bool(gfx["glow"])
		env.ssao_enabled = bool(gfx["ssao"])
		var cc: Array = COLORS[clampi(color_mode, 0, COLORS.size() - 1)]
		env.tonemap_mode = cc[0]
		env.adjustment_saturation = cc[1]
		env.adjustment_contrast = cc[2]
		env.tonemap_white = cc[3]
	# vegetace kolem hráče
	var veg: float = VEGS[clampi(int(gfx["veg"]), 0, VEGS.size() - 1)]
	if client.season_fx and client.season_fx.flowers:
		client.season_fx.flowers.set_detail(veg)
		client.season_fx.decor.set_detail(veg)
	if client.world and client.world.vegetation:   # Fáze 9: statická vegetace – 0 = vypnuto
		client.world.vegetation.set_detail(veg)
	_apply_eco(client)                              # M8.19B: detail přírody M8
	# aktivita světa – poloměr plné simulace NPC/fauny/dopravy okolo hráče
	if client.world:
		client.world.sim_radius = SIMS[clampi(int(gfx.get("sim", 2)), 0, SIMS.size() - 1)]
	# strop FPS (--maxfps má přednost)
	if not maxfps_from_args:
		Engine.max_fps = FPS_CAPS[clampi(fps_cap, 0, FPS_CAPS.size() - 1)]
	# dohlednost
	var view: float = VIEWS[clampi(int(gfx["view"]), 0, VIEWS.size() - 1)]
	vp.mesh_lod_threshold = float(MESH_LODS[clampi(int(gfx["view"]), 0, MESH_LODS.size() - 1)]) * MESH_LOD_K
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


## F3 (tune_m8_19.gd): znovu uplatní grafiku po změně SHADOW_DIST_K / MESH_LOD_K (nic, dokud hra grafiku nenastavila).
static func reapply_live() -> void:
	if _live == null or _live_client == null:
		return
	var c: Node = _live_client.get_ref()
	if c != null and is_instance_valid(c) and c.is_inside_tree():
		_live.apply_graphics(c)


## Pohyb myši (px) upravený podle citlivosti a obrácení osy Y.
func look(rel: Vector2) -> Vector2:
	return Vector2(rel.x, -rel.y if invert_y else rel.y) * mouse_sens


## M8.8: přepínač realismu přímo z nastavení na disku – pro věci, které se staví už při načtení světa (`World.build`
## běží dřív, než klient načte nastavení v `LocalClient.attach`). Automatické testy a snímky (`args`) mají výchozí true.
static func realism_saved(key: String, args := {}) -> bool:
	var ov: Dictionary = realism_args(args)          # M8.19B: --realism=klíč:off má přednost (měření)
	if ov.has(key):
		return bool(ov[key])
	for k in args:
		if k == "shot" or String(k).ends_with("test"):
			return true
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return true
	return bool(cf.get_value("realismus", key, true))


## M8.19B: přepínače realismu z příkazové řádky pro měření – `--realism=micro:off,soundscape:off` (on / off; bez
## dvojtečky = on). Platí jen pro tento běh; do `nastaveni.cfg` se zapíšou, jen když hráč v Nastavení něco uloží.
static func realism_args(args: Dictionary) -> Dictionary:
	var out := {}
	if not args.has("realism"):
		return out
	for part in String(args["realism"]).split(",", false):
		var kv := part.strip_edges().split(":", true, 1)
		if kv[0] != "":
			out[kv[0]] = kv.size() < 2 or kv[1] != "off"
	return out


## M8.19B: `--preset=nizka|stredni|vysoka|ultra` (nebo 0–3) → index předvolby; −1 = parametr není / neznámý.
static func preset_arg(args: Dictionary) -> int:
	if not args.has("preset"):
		return -1
	var v := String(args["preset"]).to_lower()
	var names := ["nizka", "stredni", "vysoka", "ultra"]
	if names.has(v):
		return names.find(v)
	if v.is_valid_int():
		return clampi(int(v), 0, PRESETS.size() - 1)
	return -1
