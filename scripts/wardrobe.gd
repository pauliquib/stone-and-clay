## Oblečení hráče (M2.3): sloty, izolace, nepromokavost, štítky, převlékání a šatník.
##
## `Player.outfit` = {slot: id předmětu z `ItemsDB` typu `clothing`}; sloty `SLOTS`. Oblečení zůstává v inventáři
## (vlastníš ho), navlečený kus se nepočítá do nosnosti. Povinné sloty (`REQUIRED`) nejdou svléknout, jen vyměnit.
## Fyziologie: `BodyState.insulation` (součet `insul`, max 1,5) a `waterproof` (`waterproof()`), viz `refresh`.
## Vzhled: `Humanoid.apply_outfit` (přestavba dílů jen při změně). Štítky (`tags`) čte zákon / úkoly / dialogy:
## ochrana_pila (M2.1 `Forestry.has_gear`), reflexni, pracovni, slavnostni, hasic (M5.3), plavky (M5.2), vcelar (kukla).
## Převlékání mimo domov trvá `CHANGE_S` s (akce kneel), v autě / na koni nejde; v šatníku doma je okamžité (`HOME_CHANGE_S`).
class_name Wardrobe
extends RefCounted

const SLOTS := ["hlava", "trup", "bunda", "nohy", "boty", "ruce"]
const SLOT_NAMES := {"hlava": "Hlava", "trup": "Trup (triko, košile)", "bunda": "Bunda", "nohy": "Nohy",
	"boty": "Boty", "ruce": "Ruce"}
const REQUIRED := ["trup", "nohy", "boty"]
## Výchozí oblečení = to, co hráč měl před M2.3 (vzhled se nezmění).
const DEFAULT := {"trup": "triko_cervene", "nohy": "dziny_modre", "boty": "polobotky"}
## Váhy nepromokavosti: trup + bunda (lepší z nich), hlava (kapuce, klobouk), nohy a boty (lepší z nich). Součet = 1.
const WP_TORSO := 0.7
const WP_HEAD := 0.15
const WP_LEGS := 0.15
const CHANGE_S := 5.0          # trvání převlečení mimo domov (s)
const HOME_CHANGE_S := 0.0     # v šatníku doma je převlečení okamžité (DOPLNIT: prompt chce 5 s jen pro inventář)
## Reakce postav (M2.3): slavnostní oblečení na úřadě / při události v obci přidá postavě náladu (jednou za den na postavu).
const FORMAL_MOOD := 0.2       # DOPLNIT: prompt říká „+1 nálada“, Persona má rozsah −1..1, proto jen 0,2
const QUEST_ITEMS := ["kukla"] # předměty, které si hráč nekupuje ani neukládá (úkol Med je půjčí)

static var _mood_day := {}     # "id:postava" → herní den, kdy už slavnostní oblečení náladu přidalo


# ------------------------------------------------------------------ vlastnosti oblečení

static func default_outfit() -> Dictionary:
	return DEFAULT.duplicate()


static func slot_of(id: String) -> String:
	return String(ItemsDB.info(id).get("slot", "")) if ItemsDB.exists(id) and ItemsDB.type_of(id) == "clothing" else ""


static func _num(id: String, key: String) -> float:
	return float(ItemsDB.info(id).get(key, 0.0)) if ItemsDB.exists(id) else 0.0


## Součet tepelné izolace navlečených kusů (0..`BodyState.INSUL_MAX`).
static func insulation(outfit: Dictionary) -> float:
	var sum := 0.0
	for slot in outfit:
		sum += _num(String(outfit[slot]), "insul")
	return clampf(sum, 0.0, BodyState.INSUL_MAX)


## Nepromokavost 0..1: trup a bunda (lepší z nich) 70 %, hlava 15 %, nohy a boty (lepší z nich) 15 %.
static func waterproof(outfit: Dictionary) -> float:
	var torso := maxf(_num(String(outfit.get("trup", "")), "waterproof"), _num(String(outfit.get("bunda", "")), "waterproof"))
	var head := _num(String(outfit.get("hlava", "")), "waterproof")
	var legs := maxf(_num(String(outfit.get("nohy", "")), "waterproof"), _num(String(outfit.get("boty", "")), "waterproof"))
	return clampf(torso * WP_TORSO + head * WP_HEAD + legs * WP_LEGS, 0.0, 1.0)


## Všechny štítky navlečených kusů (bez opakování).
static func tags(outfit: Dictionary) -> Array:
	var out := []
	for slot in outfit:
		var id := String(outfit[slot])
		if not ItemsDB.exists(id):
			continue
		for t in ItemsDB.info(id).get("tags", []):
			if not out.has(t):
				out.append(t)
	return out


static func has_tag(outfit: Dictionary, tag: String) -> bool:
	return tags(outfit).has(tag)


## Má v daném slotu kus se štítkem `tag`?
static func slot_has_tag(outfit: Dictionary, slot: String, tag: String) -> bool:
	var id := String(outfit.get(slot, ""))
	return id != "" and ItemsDB.exists(id) and ItemsDB.info(id).get("tags", []).has(tag)


static func is_worn(outfit: Dictionary, id: String) -> bool:
	for slot in outfit:
		if String(outfit[slot]) == id:
			return true
	return false


## Ochranné pomůcky k pile / sekeře (M2.1): přilba i ochranné kalhoty se štítkem `ochrana_pila`.
static func has_saw_gear(outfit: Dictionary) -> bool:
	return slot_has_tag(outfit, "hlava", "ochrana_pila") and slot_has_tag(outfit, "nohy", "ochrana_pila")


## Vlastněné oblečení pro slot (z inventáře), řazené podle názvu; předměty úkolů se nabízejí také.
static func owned(p: Player, slot: String) -> Array[String]:
	var out: Array[String] = []
	for id in p.inventory:
		if slot_of(id) == slot and p.item_count(id) > 0:
			out.append(id)
	out.sort_custom(func(a: String, b: String): return ItemsDB.name_of(a) < ItemsDB.name_of(b))
	return out


# ------------------------------------------------------------------ stav hráče

## Při vzniku hráče: výchozí oblečení, vlastnictví, vzhled i fyziologie (volá `Player._ready`).
static func setup_player(p: Player) -> void:
	p.outfit = default_outfit()
	refresh(p)


## Zkontroluje oblečení (kus, který hráč nemá, se svlékne; povinný slot se doplní výchozím), přenese ho na vzhled
## a do `BodyState`. Levné – `Humanoid.apply_outfit` přestaví postavu jen při změně.
static func refresh(p: Player) -> void:
	for slot in p.outfit.keys():
		var id := String(p.outfit[slot])
		if slot not in SLOTS or slot_of(id) != slot or p.item_count(id) <= 0:
			p.outfit.erase(slot)
	for slot in REQUIRED:
		if not p.outfit.has(slot):
			var have := owned(p, slot)
			var pick := String(DEFAULT[slot])
			if not have.is_empty() and not have.has(pick):
				pick = have[0]
			if p.item_count(pick) <= 0:
				p.add_item(pick)
			p.outfit[slot] = pick
	if p.visual != null:
		p.visual.apply_outfit(p.outfit)
	if p.body != null:
		p.body.insulation = insulation(p.outfit)
		p.body.waterproof = waterproof(p.outfit)
	p._update_overload(false)


static func to_dict(p: Player) -> Dictionary:
	return p.outfit.duplicate()


## Načtení uložené pozice: starý save bez klíče = výchozí oblečení. Kukla z úkolu se nevrací (úkol se vrátí do nabídky).
static func restore(p: Player, d: Dictionary) -> void:
	p.outfit = {}
	for slot in d:
		var id := String(d[slot])
		if slot in SLOTS and slot_of(id) == slot and id not in QUEST_ITEMS:
			p.outfit[slot] = id
	for q in QUEST_ITEMS:
		p.inventory.erase(q)
	if p.outfit.is_empty():
		p.outfit = default_outfit()
	p.visual._outfit_sig = ""       # vynutí přestavbu (po načtení se nemusí shodovat s posledním použitým oblečením)
	refresh(p)


## Včelařská kukla (úkol Med, `Player.beekeeper_suit`): navlékne se na hlavu (původní pokrývka se vrátí), včely nebodají.
static func set_beekeeper(p: Player, on: bool) -> void:
	if on:
		if String(p.outfit.get("hlava", "")) == "kukla":
			return
		p.set_meta("prev_head", String(p.outfit.get("hlava", "")))
		if p.item_count("kukla") <= 0:
			p.add_item("kukla")
		p.outfit["hlava"] = "kukla"
		refresh(p)
		return
	var was := String(p.outfit.get("hlava", "")) == "kukla"
	if was:
		p.outfit.erase("hlava")
		var prev := String(p.get_meta("prev_head", ""))
		if prev != "" and p.item_count(prev) > 0:
			p.outfit["hlava"] = prev
	while p.item_count("kukla") > 0:
		p.remove_item("kukla")
	refresh(p)


# ------------------------------------------------------------------ převlékání

## Navlékne `item_id` do jeho slotu (nebo svlékne slot, když `item_id == ""`). Mimo šatník doma trvá `CHANGE_S` s
## (klek, HUD ukazuje průběh); v autě a na koni to nejde; přeruší se pádem, nástupem do vozidla.
static func change(world_node: Node, id: int, slot: String, item_id: String, instant := false) -> void:
	var world := world_node as World
	var p: Player = world.players.get(id) if world else null
	if p == null:
		return
	if item_id != "":
		slot = slot_of(item_id)
		if slot == "" or p.item_count(item_id) <= 0:
			return
	elif slot in REQUIRED:
		world.notify(id, "show_message", ["Tohle ze sebe jen tak nesundáš – vyber jiný kus.", 2.5])
		return
	if String(p.outfit.get(slot, "")) == item_id:
		return
	if p.car != null or p.horse != null:
		world.notify(id, "show_message", ["V autě ani na koni se nepřevlékneš.", 2.5])
		return
	if String(p.outfit.get("hlava", "")) == "kukla" and slot == "hlava":
		world.notify(id, "show_message", ["Kuklu ti půjčil včelař – sundáš ji, až úly dokončíš.", 3.0])
		return
	if p.has_meta("dressing"):
		return
	var secs := HOME_CHANGE_S if instant else CHANGE_S
	if secs > 0.0:
		p.set_meta("dressing", true)
		world.cancel_action(id)
		p.controls_locked = true
		p.visual.start_action("kneel")
		var t := 0.0
		var ok := true
		while t < secs:
			await world.get_tree().create_timer(0.25).timeout
			if not is_instance_valid(p) or p.car != null or p.horse != null or p.fallen > 0.0:
				ok = false
				break
			t += 0.25
			world.notify(id, "action_progress", ["Převlékáš se", t / secs])
		if is_instance_valid(p):
			p.remove_meta("dressing")
			p.controls_locked = false
			p.visual.stop_action()
		world.notify(id, "action_progress", ["", -1.0])
		if not ok:
			return
	if item_id == "":
		p.outfit.erase(slot)
	else:
		p.outfit[slot] = item_id
	refresh(p)
	var msg := "Sundáno: %s." % String(SLOT_NAMES[slot]).to_lower()
	if item_id != "":
		msg = "Oblečeno: %s." % ItemsDB.info(item_id)["short"]
	world.notify(id, "show_message", [msg, 2.0])
	world.emit_game_event(id, "outfit_changed", {"slot": slot, "item": item_id})


# ------------------------------------------------------------------ nabídky a texty

static func _fmt(v: float) -> String:
	return ("%d %%" % roundi(v * 100.0))


static func _item_line(id: String) -> String:
	var info := ItemsDB.info(id)
	var extra := []
	if float(info.get("insul", 0.0)) > 0.0:
		extra.append("teplo %s" % _fmt(float(info["insul"])))
	if float(info.get("waterproof", 0.0)) > 0.0:
		extra.append("nepromokavé %s" % _fmt(float(info["waterproof"])))
	if info.get("tags", []).has("ochrana_pila"):
		extra.append("ochrana k pile")
	return "%s%s" % [info["short"], "  (%s)" % ", ".join(extra) if not extra.is_empty() else ""]


## Přehled, co má hráč na sobě (klávesa I; bez převlékání).
static func overview_text(p: Player) -> String:
	var s := ""
	for slot in SLOTS:
		var id := String(p.outfit.get(slot, ""))
		s += "%s: %s\n" % [SLOT_NAMES[slot], _item_line(id) if id != "" else "–"]
	s += "\nTepelná izolace: %s (max. %s)   Nepromokavost: %s" % [_fmt(p.body.insulation), _fmt(BodyState.INSUL_MAX),
		_fmt(p.body.waterproof)]
	var tg := tags(p.outfit)
	var names := {"ochrana_pila": "ochrana k pile", "reflexni": "reflexní", "pracovni": "pracovní", "slavnostni": "slavnostní",
		"hasic": "hasičský", "plavky": "plavky", "vcelar": "včelař"}
	if not tg.is_empty():
		var tn := []
		for t in tg:
			tn.append(String(names.get(t, t)))
		s += "\nVýbava: " + ", ".join(tn)
	if p.body.overheat > 0.15:
		s += "\nPřehříváš se – na tohle vedro je oblečení moc teplé."
	return s


## Klávesa I (mimo domov jen prohlížení): přehled oblečení v nabídce.
static func show_overview(hud: Hud) -> void:
	var p: Player = hud.player
	hud.open_menu("Oblečení", overview_text(p) + "\n\nPřevléknout: doma v šatníku, jinde v inventáři (Tab → Obléct, trvá %d s)." % int(CHANGE_S), [])


## Šatník doma (`InteriorMenu`, objekt `wardrobe`): výběr slotu → výběr z vlastněného oblečení.
static func open_home_menu(client: Node) -> void:
	var p: Player = client.player
	var opts := []
	for slot in SLOTS:
		var id := String(p.outfit.get(slot, ""))
		opts.append(["%s: %s" % [SLOT_NAMES[slot], ItemsDB.info(id)["short"] if id != "" else "–"],
			func(): open_slot_menu(client, slot)])
	client.hud.open_menu("Šatní skříň", overview_text(p), opts)


static func open_slot_menu(client: Node, slot: String) -> void:
	var p: Player = client.player
	var opts := []
	var cur := String(p.outfit.get(slot, ""))
	for id in owned(p, slot):
		opts.append(["%s%s" % [_item_line(id), "  ✓" if id == cur else ""],
			func(): _home_change(client, slot, id), id != cur])
	if slot not in REQUIRED:
		opts.append(["Nic (sundat)", func(): _home_change(client, slot, ""), cur != ""])
	opts.append(["Zpět do skříně", func(): open_home_menu(client)])
	var text := "Vybíráš: %s. Co tu nemáš, koupíš v Potravinách (Textil, Pracovní)." % SLOT_NAMES[slot].to_lower()
	client.hud.open_menu("Šatník – " + SLOT_NAMES[slot].to_lower(), text, opts)


static func _home_change(client: Node, slot: String, id: String) -> void:
	await change(client.world, client.pid, slot, id, true)
	open_slot_menu(client, slot)


## Text řádku v inventáři (Tab): název, hodnoty a „na sobě“.
static func row_text(p: Player, id: String) -> String:
	return "%s%s" % [_item_line(id), "  · NA SOBĚ" if is_worn(p.outfit, id) else ""]


## Tlačítko „Obléct / Svléct“ do panelu detailu v inventáři (Tab, `Hud._show_item_detail`).
static func add_row_button(hud: Hud, row: Container, id: String) -> void:
	var p: Player = hud.player
	var slot := slot_of(id)
	var worn := is_worn(p.outfit, id)
	var b := Button.new()
	b.text = "Svléct" if worn else "Obléct"
	b.disabled = p.busy or p.car != null or p.horse != null or (worn and slot in REQUIRED) \
		or (worn and id in QUEST_ITEMS)
	b.pressed.connect(func():
		hud.close_menu()
		change(hud.game, p.id, slot, "" if worn else id))
	row.add_child(b)


# ------------------------------------------------------------------ reakce postav

## Volá `World.dialog_context`: slavnostní oblečení na úřadě / při události v obci potěší postavu (jednou denně).
static func on_talk(world: World, id: int, per: Persona, place: String) -> void:
	var p: Player = world.players.get(id)
	if p == null or per == null or not has_tag(p.outfit, "slavnostni"):
		return
	var festive := place == "urad" or (world.village_events != null and not world.village_events.active().is_empty())
	if not festive:
		return
	var key := "%d:%s" % [id, per.display_name()]
	var day := world.clock.day()
	if int(_mood_day.get(key, -1)) == day:
		return
	_mood_day[key] = day
	per.add_mood(id, FORMAL_MOOD, world.clock.minutes)
