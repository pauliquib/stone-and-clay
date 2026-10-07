## Hospodářská zvířata (M2.6), jeden uzel ve `World` (`World.farm`). Vlastní výběh `Pen` se třemi
## přístřešky (kurník, chlívek, přístřešek), v nich žijí koupená zvířata (`FarmAnimal`).
##
## Ovládání je přes cedulu u branky (E) → `open_sign_menu` → menu pro každý přístřešek (`_shelter_menu`):
## koupě mláděte / dospělého, krmení (krmivo z kapsy podle druhu, `FarmSpecs.accepts_feed`), napojení
## (společná napáječka, zdarma jako u koně), sběr vajec, dojení (kýbl), stříhání (nůžky, jen ovce
## v sezóně), pohlazení, přivedení zatoulaného zvířete a porážka (nůž; prase navíc pomocník / řezník).
##
## **Růst po dnech** (stejný vzor jako `Garden._advance_days` / `PlantedTrees`): hlad a žízeň klesají,
## pasoucí se druhy (koza, ovce, kráva) se mimo zimu částečně sytí samy; dlouhé zanedbání (`starve_h`)
## sníží karmu a se šancí založí přestupek `tyrani_zvirat`, bez jídla/vody zvíře nakonec uhyne. Produkty
## (vejce, mléko) se hromadí do sebrání; slepice se na jaře (kohout + ≥ 3 slepice) můžou rozmnožit.
##
## Porážka: `_slaughter_go` ztmaví obrazovku 2 s (`World.blackout`, stejně jako mdloby) a dá maso podle
## hmotnosti a zdraví zvířete; prase navíc sádlo, jitrnice, tlačenka a "zabijačka" zvedne respekt sousedů.
##
## Ukládání: `to_dict` / `restore` (klíč `farm` v `SaveGame`) – zvířata (druh, pohlaví, věk, stavy,
## poloha), branka, čekající vejce.
class_name Farm
extends Node3D

const MAX_ANIMALS := 24
const CHECK_S := 1.0
const MAX_CATCHUP_DAYS := 60
const BUTCHER_PRICE := 800           # Kč za řezníka, když není přítel na pomoc se zabijačkou
const HELPER_FRIEND := 40.0          # potřebné přátelství (Persona) pro pomoc souseda zdarma
const STARVE_NEGLECT_H := 48.0       # od kolika hodin hladu / žízně jde o zanedbání (M4.4 háček)
const NEGLECT_KARMA := -2.0
const NEGLECT_OFFENSE_P := 0.2       # šance na přestupek za den zanedbání (sousedé / veterina si všimnou)
const BREED_CHANCE := 0.05           # šance na vyvedení kuřat za jarní den
const BREED_MONTHS := [3, 4, 5]
const BREED_MIN_HENS := 3
const FLOCK_CAP := 20                # nejvýš tolik slepic + kuřat dohromady (proti nekonečnému množení)
const SHELTER_SPECIES := {"kurnik": ["slepice", "kralik"], "chlivek": ["prase"], "pristresek": ["koza", "ovce", "krava"]}
const SHELTER_TITLE := {"kurnik": "Kurník – slepice, králíci", "chlivek": "Chlívek – prase",
	"pristresek": "Přístřešek – koza, ovce, kráva"}

var world: World
var pen: Pen
var animals: Array[FarmAnimal] = []
var eggs_ready := 0
var next_uid := 1

var _last_jd := -1
var _chk := 0.0


func setup(w: World) -> void:
	world = w
	name = "Hospodarstvi"
	pen = Pen.new()
	pen.name = "Vybeh_hospodarstvi"
	add_child(pen)
	pen.setup(w)
	_last_jd = w.clock.jd() if w.clock else -1


func _spawn(species: String, sex_: String, age: float) -> FarmAnimal:
	var a := FarmAnimal.new()
	add_child(a)
	a.setup(self, next_uid, species, sex_, age)
	next_uid += 1
	animals.append(a)
	return a


func _group(kind: String) -> Array:
	var out := []
	for a in animals:
		if String(FarmSpecs.info(a.species).get("shelter", "")) == kind:
			out.append(a)
	return out


func _notify_all(text: String) -> void:
	for id in world.players.keys():
		world.notify(int(id), "show_message", [text, 4.0])


# ------------------------------------------------------------------ interakce (E) – cedule u branky

func interactables(id: int) -> Array:
	var out := []
	if pen == null or not pen.ok:
		return out
	var p: Player = world.players.get(id)
	if p == null:
		return out
	if pen.sign_pos.distance_to(p.global_position) < 30.0:
		out.append({"pos": pen.sign_pos + Vector3(0, 0.6, 0), "r": 2.6, "kind": "custom",
			"text": "Hospodářství – koupě, krmení, branka", "action": open_sign_menu})
	return out


func open_sign_menu(id: int) -> void:
	var p: Player = world.players.get(id)
	if p == null:
		return
	var lot := world.estate.lot_label() if world.estate else "bez čísla"
	var text := "Hospodářství u usedlosti %s. Branka je %s. Čeká na sebrání: %d vajec." % [lot,
		"otevřená (zvířata mohou utéct)" if pen.gate_open else "zavřená", eggs_ready]
	if not _may_buy(id):
		text += "\nNové zvíře si pořídíš, až budeš mít vlastní dům (teď bydlíš v nájmu)."
	var opts := [
		["Kurník (%d ks)" % _group("kurnik").size(), _shelter_menu.bind(id, "kurnik")],
		["Chlívek (%d ks)" % _group("chlivek").size(), _shelter_menu.bind(id, "chlivek")],
		["Přístřešek (%d ks)" % _group("pristresek").size(), _shelter_menu.bind(id, "pristresek")],
		["Branka: %s" % ("zavřít" if pen.gate_open else "otevřít"), _toggle_gate.bind(id)],
	]
	world.notify(id, "open_menu", ["Hospodářství", text, opts])


func _toggle_gate(id: int) -> void:
	pen.gate_open = not pen.gate_open
	world.notify(id, "show_message", ["Branka je teď %s." % ("otevřená" if pen.gate_open else "zavřená"), 2.5])


# ------------------------------------------------------------------ menu přístřešku

func _shelter_menu(id: int, kind: String) -> void:
	var p: Player = world.players.get(id)
	if p == null:
		return
	var group := _group(kind)
	var counts := {}
	for a in group:
		var sp: FarmAnimal = a
		counts[sp.species] = int(counts.get(sp.species, 0)) + 1
	var lines := []
	for sp_id in (SHELTER_SPECIES[kind] as Array):
		if counts.has(sp_id):
			lines.append("%s: %d ks" % [FarmSpecs.info(sp_id)["name"], counts[sp_id]])
	var text := "%s.\n%s" % [SHELTER_TITLE[kind], "\n".join(lines) if not lines.is_empty() else "Zatím žádná zvířata."]
	var opts := []
	for sp_id in (SHELTER_SPECIES[kind] as Array):
		var spec := FarmSpecs.info(sp_id)
		opts.append(["Koupit mládě: %s (%d Kč)" % [spec["name"], int(spec["price_young"])],
			_buy.bind(id, sp_id, false), animals.size() < MAX_ANIMALS])
		opts.append(["Koupit dospělé: %s (%d Kč)" % [spec["name"], int(spec["price_adult"])],
			_buy.bind(id, sp_id, true), animals.size() < MAX_ANIMALS])
	if not group.is_empty():
		opts.append(["Nakrmit (vybrat krmivo z kapsy)", _feed_menu.bind(id, kind)])
		opts.append(["Napojit (napáječka)", _water_group.bind(id, kind)])
	if kind == "kurnik" and eggs_ready > 0:
		opts.append(["Sebrat vejce (%d)" % eggs_ready, _collect_eggs.bind(id)])
	for a in group:
		var fa: FarmAnimal = a
		if fa.escaped:
			opts.append(["Přivést zpět: %s" % fa.display_name(), _lead.bind(id, fa)])
			continue
		opts.append(["Pohladit: %s" % fa.display_name(), _pet.bind(id, fa)])
		var spec2 := FarmSpecs.info(fa.species)
		if fa.is_adult() and String(spec2.get("product", "")) == "mleko" and fa.milk_l >= 1.0:
			opts.append(["Podojit: %s (%d l čeká)" % [fa.display_name(), int(fa.milk_l)], _milk.bind(id, fa), p.item_count("kbelik") > 0])
		if fa.is_adult() and String(spec2.get("product", "")) == "vlna" and world.clock.month() in (spec2.get("wool_months", []) as Array) \
				and fa.shear_year != world.clock.year():
			opts.append(["Ostříhat: %s" % fa.display_name(), _shear.bind(id, fa), p.item_count("nuzky") > 0])
		if fa.is_adult():
			opts.append(["Porazit: %s" % fa.display_name(), _slaughter_confirm.bind(id, fa), p.item_count("nuz") > 0])
	world.notify(id, "open_menu", [SHELTER_TITLE[kind], text, opts])


## Koupě zvířat jen s vlastním domem (M1.7 – nájemník bytu ne; koupě domu M4.7). Staré uložení = vlastní dům.
func _may_buy(id: int) -> bool:
	return world.estate == null or world.estate.owns_house(id)


func _buy(id: int, species: String, adult: bool) -> void:
	var p: Player = world.players.get(id)
	if p == null or not pen.ok:
		return
	if animals.size() >= MAX_ANIMALS:
		world.notify(id, "show_message", ["Výběh je plný.", 2.5])
		return
	if not _may_buy(id):
		world.notify(id, "show_message", ["Hospodářská zvířata jen s vlastním domem – v nájemním bytě je chovat nemůžeš.", 3.5])
		return
	var spec := FarmSpecs.info(species)
	var price := int(spec.get("price_adult" if adult else "price_young", 0))
	var final_price := world.price_for(id, price)
	if p.money < final_price:
		world.notify(id, "show_message", ["Nemáš dost peněz.", 2.0])
		return
	p.money -= final_price
	world.play_sfx(id, "cash")
	var sex_ := "f" if randf() < 0.65 else "m"
	var age := float(spec.get("grow_days", 60.0)) if adult else 0.0
	var a := _spawn(species, sex_, age)
	world.notify(id, "show_message", ["Koupeno: %s (%s)." % [FarmSpecs.display_name(species, a.sex),
		"dospělé" if adult else "mládě"], 3.0])
	world.emit_game_event(id, "farm_bought", {"species": species, "adult": adult})


# ------------------------------------------------------------------ péče

func _feed_menu(id: int, kind: String) -> void:
	var p: Player = world.players.get(id)
	if p == null:
		return
	var group := _group(kind)
	var items := {}
	for a in group:
		var fa: FarmAnimal = a
		for it in ItemsDB.ITEMS.keys():
			if FarmSpecs.accepts_feed(fa.species, it):
				items[it] = true
	var opts := []
	for it in items.keys():
		var n := p.item_count(it)
		if n > 0:
			opts.append(["%s (máš %d)" % [ItemsDB.name_of(it), n], _feed_apply.bind(id, kind, it)])
	if opts.is_empty():
		world.notify(id, "show_message", ["Nemáš vhodné krmivo (Potraviny → Hospodářství, nebo zelenina ze zahrady).", 3.5])
		return
	world.notify(id, "open_menu", ["Krmení", "Vyber krmivo z kapsy:", opts])


func _feed_apply(id: int, kind: String, item_id: String) -> void:
	var p: Player = world.players.get(id)
	if p == null:
		return
	var fed := 0
	for a in _group(kind):
		var fa: FarmAnimal = a
		if fa.hunger >= 0.95 or not FarmSpecs.accepts_feed(fa.species, item_id):
			continue
		if not p.remove_item(item_id, 1):
			break
		fa.hunger = 1.0
		fa.starve_h = 0.0
		if fa.escaped:
			fa.lead_back()
		fed += 1
	if fed > 0:
		world.give_xp(id, "chovatelstvi", 1.5 * float(fed), "krmeni")
		world.notify(id, "show_message", ["Nakrmeno: %d zvířat." % fed, 2.5])
	else:
		world.notify(id, "show_message", ["Není koho krmit (nebo jsou už nasycená).", 2.5])


func _water_group(id: int, kind: String) -> void:
	var n := 0
	for a in _group(kind):
		var fa: FarmAnimal = a
		if fa.thirst < 0.95:
			fa.thirst = 1.0
			n += 1
	world.notify(id, "show_message", ["Napojeno: %d zvířat." % n if n > 0 else "Zvířata mají dost pití.", 2.5])


func _collect_eggs(id: int) -> void:
	var p: Player = world.players.get(id)
	if p == null or eggs_ready <= 0:
		return
	p.add_item("vejce", eggs_ready)
	world.give_xp(id, "chovatelstvi", 1.0, "vejce")
	world.notify(id, "show_message", ["Sebráno vajec: %d." % eggs_ready, 2.5])
	eggs_ready = 0


func _milk(id: int, a: FarmAnimal) -> void:
	var p: Player = world.players.get(id)
	if p == null or not is_instance_valid(a):
		return
	if p.item_count("kbelik") <= 0:
		world.notify(id, "show_message", ["Potřebuješ kbelík na dojení (Potraviny → Hospodářství).", 2.5])
		return
	var n := int(floor(a.milk_l))
	if n <= 0:
		world.notify(id, "show_message", ["Zatím nic nenadojilo.", 2.0])
		return
	p.add_item("mleko", n)
	a.milk_l -= float(n)
	world.give_xp(id, "chovatelstvi", 2.0 * float(n), "dojeni")
	world.notify(id, "show_message", ["Nadojeno: %d l mléka." % n, 3.0])


func _shear(id: int, a: FarmAnimal) -> void:
	var p: Player = world.players.get(id)
	if p == null or not is_instance_valid(a):
		return
	if p.item_count("nuzky") <= 0:
		world.notify(id, "show_message", ["Potřebuješ nůžky na stříhání ovcí.", 2.5])
		return
	a.shear_year = world.clock.year()
	p.add_item("vlna", 2)
	world.give_xp(id, "chovatelstvi", 10.0, "strihani")
	world.notify(id, "show_message", ["Ostříháno: %s – 2× vlna." % a.display_name(), 3.0])


func _pet(id: int, a: FarmAnimal) -> void:
	if not is_instance_valid(a):
		return
	a.happiness = minf(1.0, a.happiness + 0.1)
	world.give_xp(id, "chovatelstvi", 0.5, "pohlazeni")
	world.notify(id, "show_message", ["Pohladil jsi: %s." % a.display_name(), 1.5])


func _lead(id: int, a: FarmAnimal) -> void:
	var p: Player = world.players.get(id)
	if p == null or not is_instance_valid(a):
		return
	p.controls_locked = true
	world.notify(id, "show_message", ["Vedeš zvíře zpátky do výběhu…", 2.0])
	await get_tree().create_timer(2.0).timeout
	if is_instance_valid(p):
		p.controls_locked = false
	if is_instance_valid(a):
		a.lead_back()
		world.notify(id, "show_message", ["%s je zpátky ve výběhu." % a.display_name(), 2.5])


# ------------------------------------------------------------------ porážka (M2.6 – legální cesta k masu)

func _best_friend(id: int) -> Array:
	var best_name := "nikdo"
	var best := 0.0
	for per in world.personas().values():
		var f: float = (per as Persona).get_friendship(id)
		if f > best:
			best = f
			best_name = (per as Persona).display_name()
	return [best_name, best]


func _slaughter_confirm(id: int, a: FarmAnimal) -> void:
	var p: Player = world.players.get(id)
	if p == null or not is_instance_valid(a):
		return
	if p.item_count("nuz") <= 0:
		world.notify(id, "show_message", ["Potřebuješ řeznický nůž.", 2.5])
		return
	var spec := FarmSpecs.info(a.species)
	if not bool(spec.get("helper_needed", false)):
		_slaughter_go(id, a, false)
		return
	var helper := _best_friend(id)
	var opts := [
		["Pomůže soused %s zdarma (přátelství %d)" % [String(helper[0]), int(helper[1])],
			_slaughter_go.bind(id, a, true), float(helper[1]) >= HELPER_FRIEND],
		["Zaplatit řezníkovi (%d Kč)" % BUTCHER_PRICE, _slaughter_go.bind(id, a, false), p.money >= BUTCHER_PRICE],
	]
	world.notify(id, "open_menu", ["Zabijačka", "Na prase je potřeba pomocník (přítel ≥ %d) nebo řezník." % int(HELPER_FRIEND), opts])


func _slaughter_go(id: int, a: FarmAnimal, free_helper: bool) -> void:
	var p: Player = world.players.get(id)
	if p == null or not is_instance_valid(a):
		return
	var spec := FarmSpecs.info(a.species)
	if bool(spec.get("helper_needed", false)) and not free_helper:
		if p.money < BUTCHER_PRICE:
			world.notify(id, "show_message", ["Nemáš na řezníka dost peněz.", 2.5])
			return
		p.money -= BUTCHER_PRICE
		world.play_sfx(id, "cash")
	var a_name := a.display_name()
	var species := a.species
	p.controls_locked = true
	await world.blackout(id, 2.0)
	if is_instance_valid(p):
		p.controls_locked = false
	if not is_instance_valid(p) or not is_instance_valid(a):     # za dobu zatemnění mohl hráč odejít nebo zvíře zmizet (A3-09)
		return
	var kg_r: Array = spec["meat_kg"]
	var kg := roundi(lerpf(float(kg_r[0]), float(kg_r[1]), 0.4 + 0.6 * a.health))
	p.add_item(String(spec["meat_item"]), maxi(1, kg))
	var extra := "%d× %s" % [kg, ItemsDB.name_of(String(spec["meat_item"]))]
	if spec.has("fat_item"):
		var fat_r: Array = spec["fat_kg"]
		var fkg := roundi(lerpf(float(fat_r[0]), float(fat_r[1]), 0.4 + 0.6 * a.health))
		p.add_item(String(spec["fat_item"]), maxi(1, fkg))
		extra += ", %d× %s" % [fkg, ItemsDB.name_of(String(spec["fat_item"]))]
	if species == "prase":
		p.add_item("jitrnice", 3)
		p.add_item("tlacenka", 2)
		extra += ", jitrnice, tlačenka"
		for pid in world.players.keys():
			var rep: Reputation = world.reputations.get(pid)
			if rep:
				rep.change_respect("sousede", 5.0, "zabijačka")
				rep.change_karma(2.0, "zabijačka – sdílené maso se sousedy")
		world.notify(id, "show_message", ["Zabijačka hotová – přišli sousedé pomoct. Získáno: %s." % extra, 6.0])
	else:
		world.notify(id, "show_message", ["Poraženo: %s. Získáno: %s." % [a_name, extra], 5.0])
	world.give_xp(id, "chovatelstvi", float(spec.get("xp", 5.0)) * 3.0, "porazit")
	animals.erase(a)
	a.queue_free()


# ------------------------------------------------------------------ růst, produkty, zanedbání (denní krok)

func _process(delta: float) -> void:
	if world == null or world.clock == null or pen == null or not pen.ok:
		return
	_chk -= delta
	if _chk > 0.0:
		return
	_chk = CHECK_S
	var jd := world.clock.jd()
	if _last_jd < 0:
		_last_jd = jd
		return
	if jd != _last_jd:
		if jd > _last_jd:
			_advance_days(mini(jd - _last_jd, MAX_CATCHUP_DAYS))
		_last_jd = jd


func _advance_days(n: int) -> void:
	var winter := world.clock.month() in [12, 1, 2]
	var died: Array = []
	for i in n:
		for a in animals.duplicate():
			var fa: FarmAnimal = a
			if not is_instance_valid(fa):
				continue
			_day_tick(fa, winter, died)
		_breed_check(winter)
	for a in died:
		var fa: FarmAnimal = a
		_notify_all("Zvíře (%s) uhynulo – zanedbaná péče." % fa.display_name())
		animals.erase(fa)
		fa.queue_free()


func _day_tick(fa: FarmAnimal, winter: bool, died: Array) -> void:
	if fa.health <= 0.0 or died.has(fa):
		return         # už uhynulo v tomto doháněném úseku dnů (F2 skok data, dlouhý spánek) – nepočítat dvakrát
	var spec := FarmSpecs.info(fa.species)
	fa.age_days += 1.0
	fa.scale = Vector3.ONE * fa.age_scale()
	var hd: float = float(spec.get("hunger_day", 0.4))
	if bool(spec.get("graze", false)) and not winter:
		hd *= 0.15         # pasoucí se zvíře se přes den mimo zimu částečně sytí samo
	fa.hunger = clampf(fa.hunger - hd, 0.0, 1.0)
	fa.thirst = clampf(fa.thirst - float(spec.get("thirst_day", 0.4)), 0.0, 1.0)
	if fa.hunger <= 0.0 or fa.thirst <= 0.0:
		fa.starve_h += 24.0
		fa.health = clampf(fa.health - 0.12, 0.0, 1.0)
	else:
		fa.starve_h = 0.0
		fa.health = clampf(fa.health + 0.04, 0.0, 1.0)
	if fa.starve_h >= STARVE_NEGLECT_H:
		for pid in world.players.keys():
			var rep: Reputation = world.reputations.get(pid)
			if rep:
				rep.change_karma(NEGLECT_KARMA, "zanedbané zvíře (%s)" % fa.display_name())
			if randf() < NEGLECT_OFFENSE_P:
				world.commit_offense(int(pid), "tyrani_zvirat", {"severity": 0.3})
	if fa.health <= 0.0:
		died.append(fa)
		return
	var prod := String(spec.get("product", ""))
	if prod == "vejce" and fa.sex == "f" and fa.is_adult():
		var chance: float = float(spec.get("product_chance", 0.7))
		if winter:
			chance *= float(spec.get("winter_mult", 1.0))
		if fa.hunger < 0.3 or fa.thirst < 0.3:
			chance *= 0.4
		if randf() < chance:
			eggs_ready += 1
	elif prod == "mleko" and fa.is_adult() and (not bool(spec.get("milk_female_only", true)) or fa.sex == "f"):
		var amr: Array = spec.get("product_amount", [1.0, 1.0])
		var amt := randf_range(float(amr[0]), float(amr[1]))
		if winter:
			amt *= float(spec.get("winter_mult", 1.0))
		if fa.hunger < 0.3:
			amt *= 0.5
		fa.milk_l = minf(fa.milk_l + amt, float(amr[1]) * 2.0)


func _breed_check(winter: bool) -> void:
	if winter or animals.size() >= FLOCK_CAP or not (world.clock.month() in BREED_MONTHS):
		return
	var hens := 0
	var rooster := false
	for a in animals:
		var fa: FarmAnimal = a
		if fa.species == "slepice" and fa.is_adult():
			if fa.sex == "f":
				hens += 1
			else:
				rooster = true
	if hens >= BREED_MIN_HENS and rooster and randf() < BREED_CHANCE:
		var n := randi_range(3, 6)
		for i in n:
			if animals.size() >= FLOCK_CAP:
				break
			_spawn("slepice", "f" if randf() < 0.5 else "m", 0.0)
		_notify_all("Kvočna vyvedla kuřata (%d ks)." % n)


# ------------------------------------------------------------------ ukládání

func to_dict() -> Dictionary:
	var arr := []
	for a in animals:
		arr.append((a as FarmAnimal).to_dict())
	return {"animals": arr, "next_uid": next_uid, "eggs": eggs_ready, "gate_open": pen.gate_open if pen else false}


## Starý save bez klíče `farm` = prázdné hospodářství.
func restore(d: Dictionary) -> void:
	for a in animals.duplicate():
		var fa: FarmAnimal = a
		animals.erase(fa)
		fa.queue_free()
	next_uid = int(d.get("next_uid", 1))
	eggs_ready = int(d.get("eggs", 0))
	if pen != null and pen.ok:
		pen.gate_open = bool(d.get("gate_open", false))
	for e in d.get("animals", []):
		var sp := String(e.get("sp", ""))
		if not FarmSpecs.DATA.has(sp):
			continue
		var a := _spawn(sp, String(e.get("sex", "f")), float(e.get("age", 0.0)))
		a.from_dict(e)
	_last_jd = -1
