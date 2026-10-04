## Výčep v hospodě U Hřiště (M3.2) – minihra čepování pro práci „Výčepní“ (`data/prace.json` → `vycepni`, úkol `vycep_obsluha`).
## Jeden uzel ve `World` (`World.vycep`), vzniká v `World.add_player`; stav per hráč (`_s[pid]`).
##
## Průběh (jen na směně výčepní a při úkolu `TASK`):
## 1. Host (štamgast / páteční host, `Place.regulars` blízko pípy) si objedná – bublina „Dvě desítky!“ (`Npc.say`).
## 2. Hráč u pípy (`PIPA_R` m; uvnitř postaveného interiéru hospody `Interior.spots["pipa"]`, jinak výčepní stolek na
##    zahrádce) stiskne LMB (`World.player_action("use_tool")` → `on_click` dřív než kontextové akce) a drží: pruh plnění
##    (`action_progress`) roste rychlostí `FILL_RATE` ± náhoda. Puštění v zelené (`GREEN_LO`–`GREEN_HI`) = pivo s čepicí,
##    nad `GREEN_HI` = bez pěny (host bručí), pod `GREEN_LO` = málo (host nespokojen), `1,0` = přeteklo (ztráta, čepuj znovu).
## 3. Načepované pivo (tácek, `carry`) se donese hostovi: akce `donest_pivo` (LMB na hosta, cíl `job_host`). Host zaplatí
##    hostinskému a podle spokojenosti (kvalita × výřečnost) nechá spropitné hráči (`TIP_PER_BEER`); nespokojený nedá nic
##    a hodnocení v práci klesne. Každé doručení = krok úkolu (`Jobs`, akce bez `cile`). Kdo nechá hosta čekat `PATIENCE_S`,
##    naštve ho (hodnocení, respekt štamgastů).
## Inkaso a vracení drobných se nesimuluje (volitelné v zadání – otevřený bod). Pití v práci hlídá `Jobs` (napomenutí).
class_name Vycep
extends Node3D

const JOB_ID := "vycepni"
const TASK := "vycep_obsluha"
const PIPA_R := 2.0                  # m (vodorovně) od pípy – odsud se čepuje
const GUEST_R := 25.0                # m – hosté dál od pípy si neobjednávají
const FILL_RATE := [0.26, 0.36]      # plnění za s (náhodně na každý půllitr)
const GREEN_LO := 0.78
const GREEN_HI := 0.92
const ORDER_WAIT := [12.0, 30.0]     # s mezi objednávkami
const PATIENCE_S := 150.0            # s – host čeká na pivo, pak se naštve
const TIP_PER_BEER := 12.0           # Kč spropitného za perfektní pivo (× výřečnost)
const ORDERS := [["pivo10", "desítku", "desítky"], ["pivo_cepovane", "dvanáctku", "dvanáctky"]]
const QUALITY_TEXT := {1.0: "Pivo s čepicí – přesně tak!", 0.8: "Skoro bez pěny – ujde to.", 0.4: "Málo natočeno – host to uvidí."}

var world: World
var outdoor_pos := Vector3.INF      # výčepní stolek na zahrádce (pípa venku)
var _s := {}                         # pid → {order, carry, pour, wait, tips, pipa_t, host_t}


func setup(w: World) -> void:
	world = w
	name = "Vycep"
	var pl: Place = w.places.get("hospoda")
	if pl == null:
		return
	var face := float(pl.data.get("face_yaw", 0.0))
	var b := Basis(Vector3.UP, face)
	outdoor_pos = pl.door + b * Vector3(1.8, 0, 2.6)
	outdoor_pos.y = w.terrain.height_at(outdoor_pos.x, outdoor_pos.z)
	var k := MeshKit.new()
	k.box(Vector3(0, 0.5, 0), Vector3(1.0, 1.0, 0.55), Color(0.45, 0.3, 0.18))
	k.box(Vector3(0, 1.02, 0), Vector3(1.1, 0.05, 0.62), Color(0.6, 0.42, 0.26))
	k.cylinder(Vector3(0, 1.2, 0), 0.05, 0.05, 0.3, Color(0.8, 0.82, 0.85), Vector3.ZERO, 10)
	k.box(Vector3(0, 1.32, 0.1), Vector3(0.04, 0.04, 0.2), Color(0.8, 0.82, 0.85))
	var mi := MeshKit.mesh_instance(self, k.commit(MeshKit.vc_material(0.6, 0.2)), 120.0)
	mi.position = outdoor_pos
	mi.rotation.y = face
	Jobs.set_provider("vycep_kompas", func(_w: World, id: int, _j: Dictionary) -> Array: return _compass(id))
	Actions.set_handler("donest_pivo", _on_deliver)


func _state(id: int) -> Dictionary:
	if not _s.has(id):
		_s[id] = {"order": {}, "carry": [], "pour": {}, "wait": 5.0, "tips": 0, "pipa_t": {}, "host_t": {}}
	return _s[id]


## Pípa pro hráče: v postaveném interiéru hospody u pultu, jinak na zahrádce.
func pipa_pos(id: int) -> Vector3:
	var p: Player = world.players.get(id)
	var it: Interior = world.interiors.get("hospoda")
	if p and p.inside == "hospoda" and it and it.built and it.spots.has("pipa"):
		return (it.spots["pipa"] as Array)[0]
	return outdoor_pos + Vector3(0, 1.2, 0)


func _active(id: int) -> bool:
	var jb: Jobs = world.jobs.get(id)
	return jb != null and jb.on_shift(JOB_ID) and jb.task_id() == TASK


func _near_pipa(id: int) -> bool:
	var p: Player = world.players.get(id)
	if p == null:
		return false
	var d := pipa_pos(id) - p.global_position
	return Vector2(d.x, d.z).length() <= PIPA_R and absf(d.y) < 2.5


## Hosté, kteří sedí u stolů poblíž pípy (uvnitř nebo na zahrádce – schovaní pod zahrádkou se nepočítají).
func _guests(id: int) -> Array:
	var pl: Place = world.places.get("hospoda")
	var out := []
	if pl == null:
		return out
	var pp := pipa_pos(id)
	for n in pl.regulars:
		if is_instance_valid(n) and n.global_position.distance_to(pp) < GUEST_R and absf(n.global_position.y - pp.y) < 3.0:
			out.append(n)
	return out


# ------------------------------------------------------------------ vstup (LMB)

## LMB od hráče (volá `World.player_action("use_tool")` před kontextovými akcemi). True = klik patřil výčepu.
func on_click(id: int) -> bool:
	if not _active(id) or not _near_pipa(id):
		return false
	var s := _state(id)
	if not (s["pour"] as Dictionary).is_empty():
		return true
	var o: Dictionary = s["order"]
	if o.is_empty():
		world.notify(id, "show_message", ["Nikdo nic nechce – počkej na objednávku (bublina nad hostem).", 2.5])
		return true
	if (s["carry"] as Array).size() >= int(o["count"]):
		world.notify(id, "show_message", ["Na tácku je všechno – odnes pivo hostovi (LMB na hosta).", 2.5])
		return true
	s["pour"] = {"fill": 0.0, "t": 0.0, "rate": randf_range(float(FILL_RATE[0]), float(FILL_RATE[1]))}
	world.play_sfx(id, "hiss", 1.4, -8.0)
	return true


# ------------------------------------------------------------------ průběh

func _process(delta: float) -> void:
	if world == null:
		return
	for id_v in world.players:
		var id := int(id_v)
		if not _active(id):
			if _s.has(id):
				_reset(id)
			continue
		var s := _state(id)
		_update_pipa_target(id, s)
		if not (s["pour"] as Dictionary).is_empty():
			_tick_pour(id, s, delta)
		_tick_order(id, s, delta)


func _update_pipa_target(id: int, s: Dictionary) -> void:
	var t: Dictionary = s["pipa_t"]
	if t.is_empty():
		t = {"pos": pipa_pos(id), "r": 1.0, "kind": "job_pipa", "data": {"pid": id, "job": JOB_ID}}
		s["pipa_t"] = t
		world.register_target(t)
	else:
		t["pos"] = pipa_pos(id)


func _tick_pour(id: int, s: Dictionary, delta: float) -> void:
	var p: Player = world.players.get(id)
	var pr: Dictionary = s["pour"]
	if p == null or not _near_pipa(id):
		s["pour"] = {}
		world.notify(id, "action_progress", ["", -1.0])
		world.notify(id, "show_message", ["Odešel jsi od pípy – pivo nedotočené.", 2.0])
		return
	pr["t"] = float(pr["t"]) + delta
	var fill := float(pr["fill"])
	if p.input.reel:
		fill += float(pr["rate"]) * delta
		pr["fill"] = fill
		var zone := "ZELENÁ – pusť!" if fill >= GREEN_LO and fill <= GREEN_HI else ("ještě…" if fill < GREEN_LO else "už moc!")
		world.notify(id, "action_progress", ["Čepování %d %% (zelená %d–%d %%) – %s" % [roundi(fill * 100.0),
			roundi(GREEN_LO * 100.0), roundi(GREEN_HI * 100.0), zone], clampf(fill, 0.0, 1.0)])
		if fill >= 1.0:
			s["pour"] = {}
			world.notify(id, "action_progress", ["", -1.0])
			world.play_sfx(id, "splash", 1.3, -6.0)
			world.notify(id, "show_message", ["Přeteklo! Pivo teče po pultu – čepuj znovu.", 2.5])
			var jb: Jobs = world.jobs.get(id)
			if jb:
				jb.adjust_rating(-0.5)
		return
	if float(pr["t"]) < 0.15:
		return                       # klik a hned puštěné tlačítko – ještě nezačalo téct
	s["pour"] = {}
	world.notify(id, "action_progress", ["", -1.0])
	var q := 1.0 if fill >= GREEN_LO and fill <= GREEN_HI else (0.8 if fill > GREEN_HI else 0.4)
	(s["carry"] as Array).append(q)
	var o: Dictionary = s["order"]
	var left := int(o.get("count", 1)) - (s["carry"] as Array).size()
	world.play_sfx(id, "glass", 1.0, -6.0)
	world.notify(id, "show_message", ["%s %s" % [QUALITY_TEXT.get(q, ""),
		"Ještě %d." % left if left > 0 else "Odnes pivo hostovi (LMB na hosta)."], 3.0])


func _tick_order(id: int, s: Dictionary, delta: float) -> void:
	var o: Dictionary = s["order"]
	if o.is_empty():
		s["wait"] = float(s["wait"]) - delta
		if float(s["wait"]) > 0.0:
			return
		var guests := _guests(id)
		if guests.is_empty():
			s["wait"] = 5.0
			return
		var g: Npc = guests[randi() % guests.size()]
		var kind: Array = ORDERS[randi() % ORDERS.size()]
		var n := 1 if randf() < 0.55 else 2
		var text := ("Jednu %s!" % kind[1]) if n == 1 else ("Dvě %s!" % kind[2])
		s["order"] = {"guest": g, "item": kind[0], "count": n, "t": 0.0, "text": text}
		s["carry"] = []
		g.say(text, 6.0)
		world.notify(id, "show_message", ["%s: „%s“ (čepuj u pípy – drž LMB)" % [g.display_name, text], 4.0])
		return
	if not is_instance_valid(o["guest"]):
		_clear_order(id, s)            # páteční host odešel domů
		return
	var g2: Npc = o["guest"]
	o["t"] = float(o["t"]) + delta
	if fmod(float(o["t"]), 30.0) < delta:
		g2.say(String(o["text"]), 3.0)       # připomene se
	if float(o["t"]) > PATIENCE_S:
		g2.say("To se nedá vydržet, jdu si pro to sám!", 4.0)
		world.notify(id, "show_message", ["Host se nedočkal – hostinský si toho všiml.", 3.0])
		var jb: Jobs = world.jobs.get(id)
		if jb:
			jb.adjust_rating(-2.0)
		var rep: Reputation = world.reputations.get(id)
		if rep:
			rep.change_respect("stamgasti", -0.5, "pomalá obsluha")
		_clear_order(id, s)
		return
	# plný tácek → cíl u hosta (pozice se hýbe, když se hosté přesadí dovnitř / ven)
	var ht: Dictionary = s["host_t"]
	if (s["carry"] as Array).size() >= int(o["count"]):
		var pos := g2.global_position + Vector3(0, 0.9, 0)
		if ht.is_empty():
			ht = {"pos": pos, "r": 1.3, "kind": "job_host", "data": {"pid": id, "job": JOB_ID}}
			s["host_t"] = ht
			world.register_target(ht)
		else:
			ht["pos"] = pos


func _on_deliver(id: int, _def: Dictionary, _aim: Dictionary, ok: bool) -> void:
	if not ok or not _s.has(id):
		return
	var s := _state(id)
	var o: Dictionary = s["order"]
	var carry: Array = s["carry"]
	if o.is_empty() or carry.is_empty():
		return
	var q := 0.0
	for c in carry:
		q += float(c)
	q /= float(carry.size())
	var g: Npc = o["guest"] if is_instance_valid(o["guest"]) else null
	var jb: Jobs = world.jobs.get(id)
	var p: Player = world.players.get(id)
	var tip := 0
	if q >= 0.7:
		var sk: Skills = world.skills.get(id)
		var b := sk.bonus("vyrecnost") if sk else 0.0
		tip = roundi(TIP_PER_BEER * float(carry.size()) * q * (1.0 + b) * randf_range(0.6, 1.5))
		if p:
			p.money += tip
		s["tips"] = int(s["tips"]) + tip
		if g:
			g.say("Díky, to je čepice jak má být!" if q >= 0.95 else "Díky.", 3.5)
		if jb:
			jb.adjust_rating(0.5)
		var rep: Reputation = world.reputations.get(id)
		if rep:
			rep.change_respect("stamgasti", 0.2, "dobře načepované pivo")
		world.play_sfx(id, "cash")
		world.notify(id, "show_message", ["Host zaplatil hostinskému a nechal ti spropitné %d Kč (dnes celkem %d Kč)." % [tip, int(s["tips"])], 3.5])
	else:
		if g:
			g.say("Tohle má být pivo? Samá pěna a půl sklenice!", 4.0)
		if jb:
			jb.adjust_rating(-1.5)
		world.notify(id, "show_message", ["Host je nespokojený – spropitné nebude.", 3.0])
	world.emit_game_event(id, "job_tip", {"job": JOB_ID, "tip": tip, "quality": q, "count": carry.size()})
	_clear_order(id, s)


func _clear_order(id: int, s: Dictionary) -> void:
	var ht: Dictionary = s["host_t"]
	if not ht.is_empty():
		world.unregister_target(ht)
	s["host_t"] = {}
	s["order"] = {}
	s["carry"] = []
	s["wait"] = randf_range(float(ORDER_WAIT[0]), float(ORDER_WAIT[1]))


## Konec směny / jiný úkol: zruší objednávku, čepování a cíle.
func _reset(id: int) -> void:
	var s: Dictionary = _s[id]
	_clear_order(id, s)
	var pt: Dictionary = s["pipa_t"]
	if not pt.is_empty():
		world.unregister_target(pt)
	if not (s["pour"] as Dictionary).is_empty():
		world.notify(id, "action_progress", ["", -1.0])
	_s.erase(id)


## Kompas: s plným táckem k hostovi, jinak k pípě.
func _compass(id: int) -> Array:
	var s: Dictionary = _s.get(id, {})
	if not s.is_empty():
		var o: Dictionary = s["order"]
		if not o.is_empty() and (s["carry"] as Array).size() >= int(o["count"]) and is_instance_valid(o["guest"]):
			return [(o["guest"] as Npc).global_position]
	return [pipa_pos(id)]
