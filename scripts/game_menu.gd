## Herní menu (F2) – nastavení světa a pomůcky pro hraní i testování:
## roční období a datum, denní doba, rychlost času, počasí, přistavení vozidla / koně, teleport
## (místa v obci, ke zvěři, k včelám, do lesa), hráč (vystřízlivět, uzdravit, peníze) a uložení / načtení
## pozice (SaveGame: rychlá, automatická po spánku a tři pojmenované pozice).
## Menu je jen u klienta; změny světa dělá přes metody World (set_date, set_weather, spawn_vehicle…).
class_name GameMenu
extends RefCounted

const SEASONS := [
	["Jaro – 20. dubna (rašení, kvetení, vlaštovky)", 4, 20],
	["Léto – 15. července (bouřky, selata, hmyz)", 7, 15],
	["Podzim – 12. října (barevné listí, mlhy)", 10, 12],
	["Zima – 20. ledna (holé stromy, mráz, sníh)", 1, 20],
]
const TIMES := [3.0, 5.0, 7.0, 10.0, 12.0, 15.0, 18.0, 20.0, 22.0, 0.0]

var client: Node                     # LocalClient
var world: World
var pid := 1


## Položka menu podle oprávnění: bez něj šedá s poznámkou (Hud.open_menu bere 3. prvek jako „povoleno“).
## Singleplayer: `World.can_change_world` / `can_teleport` vždy true → menu vypadá jako dřív.
## V MP (až bude net.gd) jen hostitel, resp. podle nastavení lobby; server žádost musí ověřit znovu.
func _opt(label: String, cb: Callable, allowed: bool) -> Array:
	return [label if allowed else label + "  (jen hostitel)", cb, allowed]


## Podnadpis kategorie v dlouhé nabídce (Hud.open_menu jej pozná podle 5. prvku).
static func hdr(text: String) -> Array:
	return [text, Callable(), true, null, true]


func _init(c: Node) -> void:
	client = c
	world = c.world
	pid = c.pid


func _hud() -> Hud:
	return client.hud


func toggle() -> void:
	if _hud().menu_open:
		_hud().close_menu()
	else:
		open_main()


func open_main() -> void:
	var c := world.clock
	var text := "%s   %s   ·   %s\nRoční období: %s%s" % [c.date_text(), c.text(), world.weather.describe(), c.season(),
		("   ·   " + c.holiday()) if c.holiday() != "" else ""]
	var speed := "pauza" if c.speed == 0.0 else ("normální" if c.speed == 1.0 else "%d×" % int(c.speed))
	var may_world := world.can_change_world(pid)
	var may_tp := world.can_teleport(pid)
	_hud().open_menu("Herní menu", text, [
		hdr("Hra"),
		["Nová hra (nový svět, jiný los bydlení)…", _new_game],
		["Uložit / načíst hru…", open_saves],
		_opt("Hráč…", open_player, may_tp),
		hdr("Svět"),
		_opt("Roční období a datum…", open_dates, may_world),
		_opt("Denní doba…", open_times, may_world),
		_opt("Rychlost času (teď: %s)…" % speed, open_speed, may_world),
		_opt("Počasí…", open_weather, may_world),
		["Terén: %s" % ("ortofoto" if world.terrain.use_ortho else "procedurální"), _toggle_ortho],
		hdr("Pohyb a příroda"),
		_opt("Vozidla a kůň…", open_vehicles, may_tp),
		_opt("Teleport…", open_teleport, may_tp),
		["Příroda – kde je zvěř…", open_nature],
		["Příroda – ladění…", open_debug_layers],
	])


## Přepne barvu terénu (ortofoto ↔ procedurální povrch) i podklad minimapy.
func _toggle_ortho() -> void:
	world.set_terrain_ortho(not world.terrain.use_ortho)
	_hud().refresh_map_texture()
	_hud().show_message("Terén: %s" % ("ortofoto" if world.terrain.use_ortho else "procedurální povrch"), 2.0)
	open_main()


## Nová hra: potvrzení a reload scény – `Main.FRESH_START` vypne i ladicí parametry z příkazové řádky (--load…).
func _new_game() -> void:
	_hud().open_menu("Nová hra", "Svět se postaví znovu od začátku – nový los bydlení, čistý hráč i obec.\n" +
		"Neuložený postup se zahodí; uložené pozice zůstávají.", [
		["Začít novou hru", _new_game_go],
		["← Zpět", open_main],
	])


func _new_game_go() -> void:
	Main.FRESH_START = true
	client.get_tree().reload_current_scene()


func open_saves() -> void:
	var opts := []
	for slot in ["1", "2", "3"]:
		var d := SaveGame.describe(slot)
		opts.append(["Uložit do: %s%s" % [SaveGame.SLOT_NAMES[slot], ("  (přepíše: %s)" % d) if d != "" else "  (prázdná)"],
			Callable(client, "save_game").bind(slot)])
	for slot in SaveGame.SLOTS:
		var d := SaveGame.describe(slot)
		if d != "":
			opts.append(["Načíst: %s – %s" % [SaveGame.SLOT_NAMES[slot], d], Callable(client, "load_game").bind(slot)])
	opts.append(["← Zpět", open_main])
	_hud().open_menu("Uložit / načíst", "F5 = rychlé uložení, F9 = načíst rychlé uložení. Po každém vyspání se hra uloží sama.\n" +
		"Rozdělaný úkol se po načtení vrátí do nabídky (vezmi si ho znovu).", opts)


func open_dates() -> void:
	var y := world.clock.year()
	var opts := [hdr("Roční období")]
	for s in SEASONS:
		opts.append([s[0], _set_date.bind(y, s[1], s[2])])
	opts.append(hdr("Konkrétní měsíc"))
	for m in 12:
		opts.append(["%s (15. %s)" % [Clock.MONTHS_1[m].capitalize(), Clock.MONTHS[m]], _set_date.bind(y, m + 1, 15)])
	opts.append(hdr("Posun"))
	var today := Time.get_date_dict_from_system()
	opts.append(["Dnešní datum", _set_date.bind(int(today["year"]), int(today["month"]), int(today["day"]))])
	opts.append(["+1 den", _shift_days.bind(1)])
	opts.append(["+7 dní", _shift_days.bind(7)])
	opts.append(["← Zpět", open_main])
	_hud().open_menu("Roční období a datum", "Stromy, tráva, teploty a počasí se přepočítají hned.\n" +
		"Zimní srst, parůžky a selata se projeví po novém spuštění hry.", opts)


func _set_date(y: int, m: int, d: int) -> void:
	world.set_date(y, m, d)
	_hud().show_message("Datum: %s" % world.clock.date_text(), 2.5)


func _shift_days(n: int) -> void:
	var d := Clock.from_jdn(world.clock.jd() + n)
	_set_date(d["year"], d["month"], d["day"])


func open_times() -> void:
	var opts := []
	for h in TIMES:
		opts.append(["%02d:00" % int(h), _set_time.bind(h)])
	opts.append(["+1 hodina", _set_time.bind(-1.0)])
	opts.append(["← Zpět", open_main])
	var el := world.clock.sun_elevation()
	_hud().open_menu("Denní doba", "Slunce je %d° %s obzorem." % [absi(roundi(el)), "nad" if el >= 0.0 else "pod"], opts)


func _set_time(h: float) -> void:
	if h < 0.0:
		h = fmod(world.clock.hour() + 1.0, 24.0)
	world.set_time(h)
	_hud().show_message("Čas: %s" % world.clock.text(), 2.0)


func open_speed() -> void:
	_hud().open_menu("Rychlost času", "Normálně uběhne herní hodina za 2 minuty.", [
		["Pauza (čas stojí)", world.set_time_speed.bind(0.0)],
		["Normální", world.set_time_speed.bind(1.0)],
		["4× rychleji (hodina za 30 s)", world.set_time_speed.bind(4.0)],
		["20× rychleji (den za 2,4 min)", world.set_time_speed.bind(20.0)],
		["← Zpět", open_main],
	])


func open_weather() -> void:
	var opts := [hdr("Typ počasí"), ["Automaticky (podle ročního období)", _weather.bind("auto")]]
	for k in Weather.TYPES:
		opts.append([Weather.TYPES[k]["name"], _weather.bind(k)])
	opts.append(["Sněžení", _weather.bind("snih")])
	opts.append(["Náledí", _weather.bind("naledi")])
	opts.append(hdr("Teplota"))
	for t in [-10.0, 0.0, 10.0, 20.0]:
		opts.append(["Teplota %+d °C" % int(t), _temperature.bind(t)])
	opts.append(["Teplota podle klimatu", _temperature.bind(NAN)])
	opts.append(["← Zpět", open_main])
	var w := world.weather
	_hud().open_menu("Počasí", "Teď: %s%s\nVynucené počasí se samo nemění, dokud nezvolíš Automaticky." % [w.describe(),
		"  (vynucené)" if w.forced else ""], opts)


func _temperature(t: float) -> void:
	world.set_temperature(t)
	_hud().show_message("Teplota: %s" % ("podle klimatu" if is_nan(t) else "%+d °C" % int(t)), 2.0)


func _weather(kind: String) -> void:
	world.set_weather(kind)
	_hud().show_message("Počasí: %s" % world.weather.describe(), 2.0)


func open_vehicles() -> void:
	var opts := []
	for id in CarModel.MODELS:
		var name_: String = CarModel.MODELS[id].get("name", id)
		opts.append(["Přistavit: %s" % name_, world.spawn_vehicle.bind(pid, id)])
	opts.append(["Přistavit: Testovací letoun (M6.3)", world.spawn_aircraft.bind(pid, "test_letoun")])
	opts.append(["Přistavit: Paramotor – rozložený (M6.4)", world.spawn_aircraft.bind(pid, "paramotor")])
	opts.append(["Přistavit: Motorové rogalo (M6.5)", world.spawn_aircraft.bind(pid, "trike")])
	opts.append(["Přistavit moje auto", world.summon_car.bind(pid)])
	opts.append(["Přivolat mého koně", world.summon_horse.bind(pid)])
	opts.append(["← Zpět", open_main])
	_hud().open_menu("Vozidla a kůň", "Vozidlo se objeví vedle tebe a patří ti (F – nastoupit).", opts)


func open_teleport() -> void:
	var opts := [hdr("Domov"),
		["Domů (%s)" % world.home_label(pid), _tp.bind("domov")],
		["Domov – uvnitř", world.teleport_inside.bind(pid, "domov")],
		hdr("Místa v obci")]
	for k in world.places:
		if k != "domov":
			opts.append([String(world.places[k].data["name"]), _tp.bind(k)])
	if world.bazaar and world.bazaar.ok:
		opts.append(["K bazaru vozidel (cedule)", world.teleport_player.bind(pid, world.bazaar.pos + Vector3(0, 0, 4.0), 0.0)])
	if world.airfield and world.airfield.ok:
		opts.append(["Na letiště (polní dráha, M6.5)", _tp.bind("letiste")])
	if not world.obce.is_empty():
		opts.append(hdr("Okolní obce (na okraj katastru, pohled z dálky)"))
		for o in world.obce:
			opts.append([String(o.get("name", "obec")), _tp.bind("obec:" + String(o.get("id", o.get("name", ""))))])
	opts.append(hdr("Zvěř a příroda"))
	opts.append(["Ke srncům", _tp.bind("zver:srnec")])
	opts.append(["K divočákům", _tp.bind("zver:divocak")])
	opts.append(["K zajíci", _tp.bind("zver:zajic")])
	opts.append(["K včelám", _tp.bind("vcely")])
	opts.append(["K mraveništi", _tp.bind("mraveniste")])
	opts.append(["Ke krmelci", _tp.bind("krmelec")])
	opts.append(["K posedu", _tp.bind("posed")])
	opts.append(["K výběhu koně (u usedlosti)", _tp.bind("vybeh")])
	opts.append(["Ke včelaři", _tp.bind("vcelar")])
	opts.append(hdr("Mimo obec"))
	opts.append(["Do lesa", _tp.bind("les")])
	opts.append(["Na pole", _tp.bind("pole")])
	opts.append(hdr("Ladění"))
	opts.append(["Volná kamera ~500 m nad hráčem (kontrola okolí mapy, M6.2)", Callable(client, "toggle_freecam")])
	opts.append(["← Zpět", open_main])
	_hud().open_menu("Teleport", "Autem se přesuneš i s autem, z koně sesedneš. Ke zvěři tě to dá ~30 m od ní.\n" +
		"Volná kamera slouží ke kontrole krajiny za okrajem mapy – hráč zůstane stát, V nebo tahle položka ji vypne.", opts)


## Kde je zvěř a ptáci (pomůcka pro ruční test) + vynucené vygenerování zvěře / hejna u hráče.
func open_nature() -> void:
	var p: Player = world.players.get(pid)
	var text := ""
	var opts := []
	if p != null and world.fauna != null:
		var pos: Vector3 = p.global_position
		var live := []
		for a in world.fauna.animals:
			if is_instance_valid(a) and not a.dead:
				live.append([pos.distance_to(a.global_position), a])
		live.sort_custom(func(x, y): return x[0] < y[0])
		var n300 := 0
		for e in live:
			if float(e[0]) < 300.0:
				n300 += 1
		text = "Živých zvířat do 300 m: %d (celkem ve světě %d)\n" % [n300, live.size()]
		for i in mini(3, live.size()):
			var an: Animal = live[i][1]
			text += "· %s – %d m, %s, stav: %s\n" % [an.spec["name"], int(live[i][0]), _compass(pos, an.global_position), an.state]
		var fl: BirdFlock = null
		var fd := INF
		for f in world.fauna.root_birds.get_children():
			var d: float = pos.distance_to(f.spot)
			if d < fd:
				fd = d
				fl = f
		if fl != null:
			text += "Nejbližší hejno: %s – %d m, %s, režim: %s" % [Bird.SPECIES[fl.species]["name"], int(fd), _compass(pos, fl.spot), fl.mode]
		else:
			text += "Žádné hejno ptáků."
	var may_spawn := world.can_change_world(pid)
	opts.append(hdr("Ladění (test)"))
	opts.append(_opt("Vygenerovat zvěř u mě", _nature_spawn.bind(false), may_spawn))
	opts.append(_opt("Přiletí hejno ptáků", _nature_spawn.bind(true), may_spawn))
	opts.append(_opt("Položit mrtvého srnce (test nákladu, M2.10)", _cargo_debug.bind("srnec"), may_spawn))
	opts.append(_opt("Položit mrtvého divočáka (test nákladu, M2.10)", _cargo_debug.bind("divocak"), may_spawn))
	opts.append(["Obnovit přehled", open_nature])
	opts.append(["← Zpět", open_main])
	_hud().open_menu("Příroda – kde je zvěř", text, opts)


## M8.1: F2 → Příroda – ladění – vybere barevnou mřížku pro mapu M (`World.debug_layers`), ať
## se model (stanoviště, vlhkost, teplota, vítr, druhy…) jde zkontrolovat okem bez debuggeru.
## Popisek vrstvy: `DEBUG_LAYER_LABELS` (M8.1 jen „realism_off“; další kroky M8 svůj klíč doplní).
const DEBUG_LAYER_LABELS := {"realism_off": "Ukázka (prázdná vrstva, M8.1)"}


func open_debug_layers() -> void:
	var opts := [hdr("Vrstva na mapě M")]
	opts.append(["Vypnuto" + ("  (teď aktivní)" if _hud().map_debug_layer == "" else ""),
		Callable(_hud(), "set_debug_layer").bind("")])
	for key in world.debug_layers:
		var label: String = DEBUG_LAYER_LABELS.get(key, key)
		if _hud().map_debug_layer == key:
			label += "  (teď aktivní)"
		opts.append([label, Callable(_hud(), "set_debug_layer").bind(key)])
	opts.append(["← Zpět", open_main])
	_hud().open_menu("Příroda – ladění", "Vybraná vrstva se kreslí na mapě (M) místo podkladu – " +
		"barevná mřížka po 16–64 m podle přiblížení. Každý krok M8 přidá svou vrstvu.", opts)


## Testovací náklad před hráče (M2.10): srnec, divocak, spalek, pytel, vozik.
func _cargo_debug(what: String) -> void:
	_hud().show_message(world.cargo.debug(pid, what) if world.cargo else "Náklad není k dispozici.", 3.5)


func _job_debug(what: String) -> void:
	var jb: Jobs = world.jobs.get(pid)
	_hud().show_message(jb.debug(what) if jb else "Zaměstnání není k dispozici.", 3.5)


## M3.2: výběr práce z katalogu (přijetí bez pohovoru a požadavků).
func _job_pick() -> void:
	var opts := []
	var all := Jobs.all_jobs()
	for id in all:
		var j: Dictionary = all[id]
		opts.append(["%s – %s (%s)" % [j.get("nazev", id), j.get("zamestnavatel", ""), Jobs.shifts_text(j)], _job_debug.bind("hire:" + String(id))])
	opts.append(["← Zpět", open_player])
	_hud().open_menu("Práce – přijmout", "Přijetí hned, bez pohovoru (ladění).", opts)


func _nature_spawn(birds: bool) -> void:
	_hud().show_message(world.fauna_spawn_near(pid, birds), 4.0)


## Světová strana bodu `to` vůči `from` (S = −Z, V = +X).
func _compass(from: Vector3, to: Vector3) -> String:
	var a := fposmod(rad_to_deg(atan2(to.x - from.x, -(to.z - from.z))), 360.0)
	return ["S", "SV", "V", "JV", "J", "JZ", "Z", "SZ"][int(round(a / 45.0)) % 8]


func _tp(what: String) -> void:
	var t := world.teleport_target(pid, what)
	if t.is_empty():
		_hud().show_message("Nic takového teď ve světě není.", 2.0)
		return
	world.teleport_player(pid, t[0], t[1])


## Cheat (test): libovolný předmět z katalogu, po skupinách podle typu. Obsah pro dospělé se řídí volbou
## v Nastavení (`ItemsDB.hidden`), takže skrytý předmět se v cheatu nenabídne.
func open_cheat_items() -> void:
	var groups := {}
	for id in ItemsDB.ITEMS.keys():
		if ItemsDB.hidden(id):
			continue
		var t := ItemsDB.type_of(id)
		if not groups.has(t):
			groups[t] = []
		(groups[t] as Array).append(id)
	var opts := []
	var types := groups.keys()
	types.sort()
	for t in types:
		opts.append([_type_label(t) + " (%d)" % (groups[t] as Array).size(), _cheat_group.bind(String(t))])
	opts.append(["← Zpět", open_player])
	_hud().open_menu("Cheat – předměty", "Vyber skupinu. Kliknutím na předmět dostaneš 1 kus (u skladových víc podle velikosti).", opts)


func _cheat_group(t: String) -> void:
	var ids := []
	for id in ItemsDB.ITEMS.keys():
		if ItemsDB.type_of(id) == t and not ItemsDB.hidden(id):
			ids.append(id)
	ids.sort_custom(func(a, b): return ItemsDB.name_of(a) < ItemsDB.name_of(b))
	var opts := []
	for id in ids:
		opts.append([ItemsDB.name_of(id), _cheat_give.bind(String(id))])
	opts.append(["← Skupiny", open_cheat_items])
	_hud().open_menu("Cheat – %s" % _type_label(t), "", opts)


func _cheat_give(id: String) -> void:
	var p: Player = world.players.get(pid)
	if p == null:
		return
	p.add_item(id, 1)
	world.notify(pid, "show_message", ["Cheat: %s" % ItemsDB.name_of(id), 2.5])


func _type_label(t: String) -> String:
	return String(t) if t != "" else "ostatní"


func open_player() -> void:
	_hud().open_menu("Hráč", "", [
		hdr("Stav a peníze"),
		["Vystřízlivět (0,00 ‰)", world.cheat.bind(pid, "sober")],
		["Uzdravit a doplnit výdrž", world.cheat.bind(pid, "heal")],
		["+5 000 Kč", world.cheat.bind(pid, "money")],
		["Počítač: +5 000 Kč na účet, balíky doručit hned (M3.4)", world.cheat.bind(pid, "ucet")],
		["+1 000 XP Řízení", world.cheat.bind(pid, "xp_rizeni")],
		hdr("Vybavení"),
		["Nástroje do inventáře", world.cheat.bind(pid, "nastroje")],
		["Zbraně: luk, kuše, šípy (M2.8)", world.cheat.bind(pid, "zbrane")],
		["Zbrojní oprávnění zap / vyp + puška (M2.8)", world.cheat.bind(pid, "zbrojni")],
		["Drony + registrace ÚVL + A1/A3 (M6.1)", world.cheat.bind(pid, "drony")],
		["Cheat: libovolný předmět z katalogu…", open_cheat_items],
		hdr("Práce"),
		["Přijmout hned – vybrat práci (M3.1/M3.2)", _job_pick],
		["Splnit požadavky (výřečnost 3, dřevorubectví 8, zahradničení 5, pracovní boty, střízlivost) (M3.2/M3.3)", _job_debug.bind("req")],
		["5 min před směnu + k pracovišti / zakázka hned + k zákazníkovi (M3.1/M3.3)", _job_debug.bind("shift")],
		["Výplata připravená (M3.1)", _job_debug.bind("pay")],
		["Napomenutí (M3.1)", _job_debug.bind("warn")],
		hdr("Náklad (test, M2.10)"),
		["Položit špalek", _cargo_debug.bind("spalek")],
		["Položit pytel 25 kg", _cargo_debug.bind("pytel")],
		["Postavit ruční vozík", _cargo_debug.bind("vozik")],
		["← Zpět", open_main],
	])
