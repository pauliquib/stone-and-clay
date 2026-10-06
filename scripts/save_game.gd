## Uložení a načtení hry (singleplayer): pozice ve hře do souborů `user://saves/<slot>.json`.
## Sloty: "rychly" (F5 / F9), "auto" (po každém vyspání), "1"–"3" (herní menu F2 → Uložit / načíst).
##
## Ukládá se: čas a kalendář, počasí, hráč (poloha, pohled, peníze, inventář, zákaz řízení, pátrání, výdrž),
## tělo (alkohol, jídlo, nikotin, hmotnost, zdraví, statistika), jeho vozidla (poloha, poškození, jestli
## v nějakém sedí) a kůň, oblečení (M2.3), úkoly (stav; rozdělaný úkol se vrátí do nabídky), pověst a přestupky,
## pokácené stromy s pařezy, padlé kmeny a špalky (M2.1), sebrané předměty a skóre, nálady a známosti postav (Persona),
## domov hráče (M1.7, klíč `estate`: nemovitost, byt, nájem, dluh), zaměstnání (M3.1, klíč `jobs`), obecní údržba (M3.2, klíč `udrzba`),
## lesní dělník (M3.3, klíč `les`: vyznačené stromy, hromada dřeva), počítač (M3.4, klíč `pc`: účet, pohyby, trvalý příkaz,
## pošta, objednávky a balíky, drby, výsledky eTestů).
## Verze 2 (M1.7): domov je nemovitost z registru `Estate`. Uložení verze 1 (dům hráče s pevným číslem) se převede:
## hráč vlastní usedlost (`Estate.migrate_legacy`), zahrada a výběh zůstanou, kde byly.
## Nahrává se do běžícího světa (bez restartu scény). `--load=slot` načte pozici hned po startu.
class_name SaveGame
extends RefCounted

const DIR := "user://saves"
const VERSION := 2
const SLOTS := ["rychly", "auto", "1", "2", "3"]
const SLOT_NAMES := {"rychly": "Rychlé uložení (F5)", "auto": "Automaticky (po spánku)", "1": "Pozice 1",
	"2": "Pozice 2", "3": "Pozice 3"}
const BODY_KEYS := ["weight", "stomach_alc", "body_alc", "stomach_kcal", "nicotine", "tar", "craving", "ever_smoked",
	"caffeine", "nausea", "health", "alive", "total_alc_g", "total_kcal", "cigarettes_smoked", "drinks",
	"wetness", "cold", "addiction", "_smoke_rate"]


static func path(slot: String) -> String:
	return "%s/%s.json" % [DIR, slot]


static func exists(slot: String) -> bool:
	return FileAccess.file_exists(path(slot))


## Krátký popis uložené pozice pro nabídku („12. října 2026 18:40 · uloženo 29. 9. 14:02“) nebo "".
static func describe(slot: String) -> String:
	var d := _read(slot)
	return String(d.get("label", "")) if not d.is_empty() else ""


static func _read(slot: String) -> Dictionary:
	if not exists(slot):
		return {}
	var txt := FileAccess.get_file_as_string(path(slot))
	var d = JSON.parse_string(txt)
	return d if d is Dictionary else {}


static func _v3(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func _to_v3(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2])) if a is Array and a.size() >= 3 else Vector3.ZERO


# ====================================================================== uložení

## Uloží pozici hráče `id` (a jeho klienta – skóre sběru) do slotu. Vrací true, když se povedlo.
static func save(world: World, id: int, slot: String) -> bool:
	var p: Player = world.players.get(id)
	if p == null:
		return false
	DirAccess.make_dir_recursive_absolute(DIR)
	var c := world.clock
	var d := {"version": VERSION}
	var sys := Time.get_datetime_dict_from_system()
	d["label"] = "%s %s · uloženo %d. %d. %02d:%02d" % [c.date_text(), c.text(), int(sys["day"]), int(sys["month"]),
		int(sys["hour"]), int(sys["minute"])]
	d["clock"] = {"minutes": c.minutes, "start_jd": c.start_jd, "speed": c.speed}
	var w := world.weather
	var ws := w.state()
	ws["kind_left_h"] = w.kind_left_h
	ws["forced"] = w.forced
	d["weather"] = ws
	# --- hráč
	var veh := world.traffic.vehicles_of(id)
	d["player"] = {"pos": _v3(p.global_position), "yaw": p.yaw, "pitch": p.pitch, "money": p.money,
		"inventory": p.inventory, "open_ml": p.open_ml, "durability": p.durability, "equipped": p.equipped, "license_until": p.license_suspended_until,
		"wanted_until": p.wanted_until, "stamina": p.stamina, "spawn": _v3(p.spawn_point), "spawn_yaw": p.spawn_yaw,
		"first_person": p.first_person, "inside": p.inside, "vehicle": veh.find(p.car) if p.car else -1, "on_horse": p.horse != null,
		"outfit": Wardrobe.to_dict(p)}
	var body := {}
	for k in BODY_KEYS:
		body[k] = p.body.get(k)
	d["body"] = body
	var vs := []
	for v in veh:
		var ve := {"model": v.model_id, "pos": _v3(v.global_position), "yaw": v.global_rotation.y, "damage": v.damage,
			"lights": v.lights_on}
		if world.cargo:
			var vc := world.cargo.vehicle_to_dict(v)          # náklad v kufru / na ložné ploše / na nosiči (M2.10)
			if not vc.is_empty():
				ve["cargo"] = vc
		if v.bazaar_price > 0:        # koupené v bazaru (M1.6) – při načtení se vytvoří znovu
			ve["bazaar"] = {"price": v.bazaar_price, "year": v.bazaar_year, "paint": [v.paint.r, v.paint.g, v.paint.b], "plate": v.plate}
		vs.append(ve)
	d["vehicles"] = vs
	if world.bazaar:
		d["bazaar"] = world.bazaar.to_dict()
	if world.forestry:
		d["forestry"] = world.forestry.to_dict(id)     # pokácené stromy, padlé kmeny, špalky (M2.1)
	d["unreported"] = world.unreported.get(id, [])     # nenahlášené činy, společný registr (M4.4)
	if world.vyhlasky:
		d["vyhlasky"] = world.vyhlasky.to_dict(id)     # čerstvé větve v sušení (M4.4 část B)
	if world.fire_mgr:
		d["fire"] = world.fire_mgr.to_dict()           # ohniště (i vyhaslá), stav kamen doma (M2.2)
	if world.garden:
		d["garden"] = world.garden.to_dict()           # záhony, pronájem pole, zvolená semena, náplň konve (M2.4)
		d["garden_visuals"] = world.garden.visuals_to_dict()   # kompost + skleník (Fáze 8)
	if world.fences:
		d["fences"] = world.fences.to_dict()           # hráčem postavené úseky plotů (Fáze 7; procedurální se přegenerují)
	if world.farm:
		d["farm"] = world.farm.to_dict()               # hospodářská zvířata, branka, čekající vejce (M2.6)
	if world.udrzba:
		d["udrzba"] = world.udrzba.to_dict()           # posekaná tráva, listí, odklizený sníh, lavička, odpadky (M3.2)
	if world.les:
		d["les"] = world.les.to_dict()                 # vyznačené stromy a hromada dřeva lesního dělníka (M3.3)
	if world.hunting:
		d["hunting"] = world.hunting.to_dict()         # ulovená těla, nelegální zvěřina bez dokladu (M2.9)
	if world.cargo:
		d["cargo"] = world.cargo.to_dict()             # ruční vozíky s nákladem a plachtou, pytle, špalek z ramene (M2.10; náklad aut je u vozidla)
	var h: Horse = world.fauna.horse_of(id) if world.fauna else null
	if h:
		d["horse"] = {"pos": _v3(h.global_position), "yaw": h.yaw}
	# --- úkoly, pověst, předměty, postavy
	var qs := []
	var q: Quests = world.quests_of(id)
	if q:
		for qq in q.list:
			qs.append({"id": qq.id, "state": qq.state, "fail_reason": qq.fail_reason, "result_text": qq.result_text})
	d["quests"] = qs
	var rep: Reputation = world.reputations.get(id)
	if rep:
		d["reputation"] = rep.to_dict()
	var sk: Skills = world.skills.get(id)
	if sk:
		d["skills"] = sk.to_dict()
	var lr: Law.LawRecord = world.law.get(id)
	if lr:
		d["law"] = lr.to_dict()
	if world.debts:
		d["debts"] = world.debts.to_dict(id)           # dluhy, příkazy na cestě, upomínky, exekuce (M4.2)
	if world.court:
		d["court"] = world.court.to_dict(id)           # obvinění, předvolání, rozsudky, podmínka, OPP (M4.3)
	var jb: Jobs = world.jobs.get(id)
	if jb:
		d["jobs"] = jb.to_dict()                       # zaměstnání, docházka, napomenutí, nevyplacená mzda, rozdělaná směna (M3.1)
	if world.computer:
		d["pc"] = world.computer.to_dict(id)           # účet, pohyby, trvalý příkaz, pošta, objednávky, drby, eTesty (M3.4)
	if world.nature_log:
		d["nature_log"] = world.nature_log.get_log(id)
	d["items_collected"] = world.collected_items()
	var cl = world.clients.get(id)
	if cl:
		d["hud"] = {"counts": cl.hud.counts, "score": cl.hud.score}
	var ps := {}
	for key in world.personas():
		ps[key] = world.personas()[key].to_dict()
	d["personas"] = ps
	if world.radio:
		d["radio"] = world.radio.to_dict()
	if world.estate:
		d["estate"] = world.estate.to_dict(id)          # domov: nemovitost, byt, nájem (M1.7)
	if world.katastr:
		d["katastr"] = world.katastr.to_dict()          # M4.7: vlastnictví domů a parcel, vklady a prodeje (globální)
	d["drones"] = world.drones_to_dict(id)              # M6.1: flotila (baterie, poškození) + dron zaparkovaný ve světě
	d["aircrafts"] = world.aircrafts_to_dict(id)        # M6.3: letouny (pozice, yaw, palivo, dmg) + „sedí ve stroji“
	if world.permits:
		d["permits"] = world.permits.to_dict(id)        # M6.1: registrace ÚVL, osvědčení A1/A3 (později doklady M4.6)
	if world.favors:
		d["favors"] = world.favors.to_dict(id)          # M4.5: prosby vesničanů (nabídky, slib, splněno / zklamáno)
	var f := FileAccess.open(path(slot), FileAccess.WRITE)
	if f == null:
		push_warning("Uložení se nepovedlo: %s (%s)" % [path(slot), error_string(FileAccess.get_open_error())])
		return false
	f.store_string(JSON.stringify(d, "\t"))
	f.close()
	return true


# ====================================================================== načtení

## Načte slot do běžícího světa pro hráče `id`. Vrací true, když se povedlo.
static func load_slot(world: World, id: int, slot: String) -> bool:
	var d := _read(slot)
	var p: Player = world.players.get(id)
	if d.is_empty() or p == null:
		return false
	if int(d.get("version", 0)) > VERSION:
		push_warning("Uložená pozice %s je z novější verze hry." % slot)
	# --- nejdřív z vozidla / z koně a pryč z policejní kontroly
	world.police.release(p)
	if p.car:
		world.exit_car(id)
	if p.horse:
		world.dismount_horse(id)
	p.controls_locked = false
	p.fallen = 0.0
	p.visual.pose = "stand"
	# --- čas a počasí
	var c := world.clock
	var cd: Dictionary = d.get("clock", {})
	c.minutes = float(cd.get("minutes", c.minutes))
	c.start_jd = int(cd.get("start_jd", c.start_jd))
	c.speed = float(cd.get("speed", 1.0))
	c._sun_cache_min = -1.0
	var wd: Dictionary = d.get("weather", {})
	var w := world.weather
	if wd.has("kind") and Weather.TYPES.has(wd["kind"]):
		w._set_kind(String(wd["kind"]))
	for k in ["cloud", "rain", "fog", "wind", "wind_bearing", "temp", "snow_cover", "wetness", "storm", "kind_left_h", "drought"]:
		if wd.has(k):
			w.set(k, float(wd[k]))
	w.forced = bool(wd.get("forced", false))
	w._last_min = c.minutes
	# --- hráč
	var pd: Dictionary = d.get("player", {})
	world.interior_clear(p)                      # z případného interiéru pryč (rádio zpět na zahradu)
	if world.estate:                             # M1.7: domov – dřív než se hráč postaví dovnitř (interiér bytu / domu)
		if d.has("estate"):
			world.estate.from_dict(id, d["estate"])
		else:
			world.estate.migrate_legacy(id)      # verze 1: vlastní dům (usedlost) místo pevného čísla
		world.apply_home(id)
	if world.katastr:                            # M4.7: starý save bez klíče = nikdo nic nevlastní, nic se neprodává
		world.katastr.from_dict(d.get("katastr", {}))
	p.teleport(_to_v3(pd.get("pos")) + Vector3(0, 0.1, 0), float(pd.get("yaw", 0.0)), false)
	var inside_id := String(pd.get("inside", ""))          # starý save bez klíče = venku
	if inside_id != "" and world.ensure_interior(inside_id):  # M1.8: interiér se staví až teď (zblízka / při načtení)
		if world.interior_streamer:
			world.interior_streamer.grant_invite(id, inside_id)   # uložený uvnitř cizího domu = byl pozván
		world.interior_mark(p, inside_id)
		var it_in: Interior = world.interiors.get(inside_id)
		if it_in and p.global_position.distance_to(it_in.global_position) > 50.0:
			p.teleport(it_in.inside_door, it_in.inside_yaw, false)   # jiná data budov → jiný slot: ke vchodu
	elif inside_id != "":
		# A1-08: uložený interiér už neexistuje (jiná data budov / místo zmizelo) – pozice pod mapou by znamenala
		# propad; hráč se postaví ke dveřím místa, nebo na bezpečný spawn
		var ex: Array = world.interior_exit(inside_id)
		p.teleport((ex[0] as Vector3) + Vector3(0, 0.3, 0), float(ex[1]), false)
		push_warning("SaveGame: interiér „%s“ z pozice neexistuje – hráč postaven ven" % inside_id)
	p.pitch = float(pd.get("pitch", -0.25))
	p.spawn_point = _to_v3(pd.get("spawn")) if pd.has("spawn") else p.spawn_point
	p.spawn_yaw = float(pd.get("spawn_yaw", p.spawn_yaw))
	p.money = int(pd.get("money", p.money))
	p.inventory = {}
	var inv: Dictionary = pd.get("inventory", {})
	for k in inv:
		if ItemsDB.exists(k):
			p.inventory[k] = int(inv[k])
	p.open_ml = {}
	var om: Dictionary = pd.get("open_ml", {})
	for k in om:
		if ItemsDB.exists(k):
			p.open_ml[k] = float(om[k])
	Wardrobe.restore(p, pd.get("outfit", {}))      # M2.3: starý save bez klíče = výchozí oblečení
	p.overloaded = p.carried_kg() > Player.CARRY_KG
	p.durability = {}
	var dur: Dictionary = pd.get("durability", {})
	for k in dur:
		if ItemsDB.exists(k):
			p.durability[k] = int(dur[k])
	p.equipped = ""                              # nástroj v ruce (M0.4); starý save bez klíče = prázdné ruce
	p.visual.set_tool(null)
	p.equip(String(pd.get("equipped", "")))
	world.cancel_action(id)
	p.license_suspended_until = float(pd.get("license_until", -1.0))
	p.wanted_until = float(pd.get("wanted_until", -1.0))
	p.stamina = float(pd.get("stamina", 1.0))
	if bool(pd.get("first_person", false)) != p.first_person:
		p.first_person = bool(pd.get("first_person", false))
		p.visual.set_first_person(p.first_person)
	var bd: Dictionary = d.get("body", {})
	p.body.addiction = 0.0        # starý save bez závislosti = 0
	p.body._smoke_rate = 0.0
	for k in bd:
		if not k in BODY_KEYS:
			continue
		match typeof(p.body.get(k)):
			TYPE_INT: p.body.set(k, int(bd[k]))
			TYPE_BOOL: p.body.set(k, bool(bd[k]))
			_: p.body.set(k, float(bd[k]))
	# --- vozidla: základní (podle pořadí a modelu – vozidla přistavená z menu F2 se neukládají znovu) a koupená
	# v bazaru (M1.6; stávající se odstraní a vytvoří se znovu z uložených záznamů)
	var vs: Array = d.get("vehicles", [])
	if world.bazaar and d.has("bazaar"):
		world.bazaar.from_dict(d["bazaar"])
	for v in world.traffic.vehicles_of(id).duplicate():
		if v.bazaar_price > 0:
			if v == p.car:
				world.exit_car(id)
			world.traffic.player_vehicles[id].erase(v)
			v.detach_trailer()
			v.queue_free()
	var veh := world.traffic.vehicles_of(id)
	var mapped := {}                     # index záznamu v `vs` → skutečné vozidlo (pro „sedí ve vozidle“)
	var base_idx: Array = []
	for i in vs.size():
		if not (vs[i] as Dictionary).has("bazaar"):
			base_idx.append(i)
	for k in mini(base_idx.size(), veh.size()):
		var vd: Dictionary = vs[base_idx[k]]
		var v: Car = veh[k]
		if v.model_id != String(vd.get("model", "")):
			continue
		mapped[base_idx[k]] = v
		var vp := _to_v3(vd.get("pos"))
		world.traffic.place_car(v, Vector2(vp.x, vp.z), float(vd.get("yaw", 0.0)))
		var dmg := float(vd.get("damage", 0.0))
		if dmg <= 0.0:
			v.repair()
		else:
			v.damage = dmg
		if bool(vd.get("lights", false)) != v.lights_on:
			v.toggle_lights()
	if world.bazaar:
		for i in vs.size():
			var vd: Dictionary = vs[i]
			var bz: Dictionary = vd.get("bazaar", {})
			var mid := String(vd.get("model", ""))
			if bz.is_empty() or not CarModel.MODELS.has(mid):
				continue
			var pc: Array = bz.get("paint", [0.5, 0.5, 0.5])
			var vp2 := _to_v3(vd.get("pos"))
			var nc := world.bazaar.deliver(id, mid, Color(float(pc[0]), float(pc[1]), float(pc[2])), String(bz.get("plate", "")),
				int(bz.get("year", 2000)), int(bz.get("price", 1)), float(vd.get("damage", 0.0)), [vp2, float(vd.get("yaw", 0.0))])
			if bool(vd.get("lights", false)) != nc.lights_on:
				nc.toggle_lights()
			mapped[i] = nc
	if world.forestry:
		world.forestry.restore(d.get("forestry", {}), id)   # starý save bez klíče = žádný pokácený strom
	# M4.4: nenahlášené činy; starý save je měl v klíči `forestry` → migrace (výchozí = prázdno)
	var nr = d.get("unreported", (d.get("forestry", {}) as Dictionary).get("unreported", []))
	world.unreported[id] = (nr as Array).duplicate(true)
	if world.vyhlasky:
		world.vyhlasky.restore(id, d.get("vyhlasky", {}))   # starý save bez klíče = žádné čerstvé větve
	if world.fire_mgr:
		world.fire_mgr.restore(d.get("fire", {}))            # starý save bez klíče = žádná ohniště, studená kamna
	if world.garden:
		world.garden.restore(d.get("garden", {}))            # starý save bez klíče = prázdná zahrada, žádné pole
		world.garden.visuals_restore(d.get("garden_visuals", {}))   # starý save = kompost plný, skleník stojí (Fáze 8)
	if world.fences:
		world.fences.restore(d.get("fences", {}))            # starý save bez klíče = žádné hráčské ploty (Fáze 7)
	if world.farm:
		world.farm.restore(d.get("farm", {}))                # starý save bez klíče = prázdné hospodářství
	if world.udrzba:
		world.udrzba.restore(d.get("udrzba", {}))            # starý save bez klíče = vše neposekané, bez odpadků (M3.2)
	if world.les:
		world.les.restore(d.get("les", {}))                  # starý save bez klíče = nic vyznačeno, prázdná hromada (M3.3)
	if world.hunting:
		world.hunting.restore(d.get("hunting", {}))          # starý save bez klíče = žádná těla ani nelegální maso (M2.9)
	if world.cargo:
		world.cargo.restore(d.get("cargo", {}))              # starý save bez klíče = žádný vozík, pytle ani náklad (M2.10); až po Hunting.restore
		for vi in mapped:
			world.cargo.vehicle_restore(mapped[vi], (vs[vi] as Dictionary).get("cargo", []))
	var h: Horse = world.fauna.horse_of(id) if world.fauna else null
	if h and d.has("horse"):
		var hp := _to_v3(d["horse"].get("pos"))
		hp.y = world.terrain.height_at(hp.x, hp.z) + 0.2
		h.global_position = hp
		h.velocity = Vector3.ZERO
		h.tether = hp
		h.yaw = float(d["horse"].get("yaw", 0.0))
	# --- úkoly: rozdělaný se zruší (vrátí do nabídky), ostatní dostanou uložený stav
	var q: Quests = world.quests_of(id)
	if q:
		if q.active:
			q.active.state = "available"
			q.active.cleanup()
			q.active = null
		var saved := {}
		for e in d.get("quests", []):
			saved[String(e.get("id", ""))] = e
		for qq in q.list:
			var e: Dictionary = saved.get(qq.id, {})
			var st := String(e.get("state", "available"))
			qq.state = "available" if st == "active" or st == "" else st
			qq.fail_reason = String(e.get("fail_reason", ""))
			qq.result_text = String(e.get("result_text", ""))
			qq.rules = {}
			qq.deadline = -1.0
		q.hit_report = {}
		q.changed.emit()
	var rep: Reputation = world.reputations.get(id)
	if rep and d.has("reputation"):
		rep.from_dict(d["reputation"])
	var sk: Skills = world.skills.get(id)
	if sk:
		sk.from_dict(d.get("skills", {}))      # starý save bez klíče = všechny dovednosti na 1
	var lr: Law.LawRecord = world.law.get(id)
	if lr:
		lr.from_dict(d.get("law", {}))         # starý save bez klíče = 0 bodů, prázdný rejstřík
	if world.court:
		world.court.from_dict(id, d.get("court", {}))   # starý save bez klíče = žádné případy (M4.3)
	if world.debts:
		if d.has("debts"):
			world.debts.from_dict(id, d["debts"])
		if lr and lr.unpaid_fines > 0:         # M4.2 migrace: starý save – nezaplacené pokuty → jeden dluh
			world.debts.add(id, "pokuta", lr.unpaid_fines, world.clock.jd() + Debts.DUE_DAYS,
				"Nezaplacené pokuty (starší)")
			lr.unpaid_fines = 0
		world.debts.reset_clock(world.clock.jd())
	var jb: Jobs = world.jobs.get(id)
	if jb:
		jb.from_dict(d.get("jobs", {}))        # starý save bez klíče = bez zaměstnání (M3.1)
	if world.computer:
		world.computer.from_dict(id, d.get("pc", {}))   # starý save bez klíče = prázdný účet, uvítací pošta (M3.4)
	if world.nature_log:
		world.nature_log.set_log(id, d.get("nature_log", {}))     # starý save bez klíče = prázdný deník
	world.restore_items(d.get("items_collected", []))
	world.drones_from_dict(id, d.get("drones", {}))       # M6.1: starý save bez klíče = žádné drony
	world.aircrafts_from_dict(id, d.get("aircrafts", {})) # M6.3: starý save bez klíče = žádné letouny
	if world.permits:
		world.permits.from_dict(id, d.get("permits", {})) # M6.1: starý save bez klíče = žádná oprávnění
	if world.favors:
		world.favors.from_dict(id, d.get("favors", {}))   # M4.5: starý save bez klíče = žádné prosby
	var cl = world.clients.get(id)
	if cl and d.has("hud"):
		var hc: Dictionary = d["hud"].get("counts", {})
		for k in cl.hud.counts:
			cl.hud.counts[k] = int(hc.get(k, 0))
		cl.hud.score = int(d["hud"].get("score", 0))
	var ps: Dictionary = d.get("personas", {})
	var mine := world.personas()
	for key in ps:
		if mine.has(key):
			mine[key].from_dict(ps[key], c.minutes)
	if world.radio and d.has("radio"):
		world.radio.from_dict(d["radio"])
	# --- zpátky do vozidla / na koně, v němž hráč seděl
	var vi := int(pd.get("vehicle", -1))
	if vi >= 0 and mapped.has(vi):
		world.enter_car(id, mapped[vi])
	elif bool(pd.get("on_horse", false)) and h and h.rider == null:
		world.mount_horse(id, h)
	return true
