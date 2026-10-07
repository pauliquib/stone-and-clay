## M7.2 – Kampaň a volby: poctivě (mítink, letáky, plnění přání obce), nebo nečestně (úplatek, pomluva,
## zfalšované podpisy petice) – obojí s rizikem. Navazuje na `World.politics` (M7.1): popularita se nepočítá
## tady přímo – poctivé nástroje zvyšují doopravdy pověst / respekt / přátelství (`Reputation`), ze kterých
## čte `Politics.popularity()`; nečestné nástroje jen skrytý klam (`Politics.deceit`, `Politics.add_deceit`,
## dosud prázdný háček z M7.1). Riziko odhalení: povaha postavy (kdo úplatek přijal / pomluvu uslyšel, to
## roznese dál), svědci (`World.witness_reported`) a náhoda z karmy (`Reputation.luck`). Odhalení = skandál:
## ztráta pověsti, `World.commit_offense` (podplácení voličů / volební podvod, `data/zakon.json`, trestné
## činy → soud M4.3 → odsouzení vyřadí z kandidatury přes `Politics.clean_record`).
## Volební den: `resolve_election()` (voláno z `Politics.tick()`, když vyprší `election_jd`) simuluje hlas
## každé postavy (`Characters`) podle popularity hráče a soupeřů s šumem, vyhlásí výsledek. Výhra navazuje
## na M7.4 (`Politics.mayor`); prohra = nová kandidatura (doplňovací volby) za 120 dní.
## Jedna instance `World.campaign`. Ukládání: `to_dict(pid)` / `from_dict(pid, d)`, klíč "campaign"
## v `SaveGame` (starý save bez klíče = čistý start kampaně).
class_name Campaign
extends RefCounted

## Kolik různých poštovních schránek (Prop kind "schranka", `World.street_mailboxes`) je třeba obejít za den.
const MAILBOXES_NEEDED := 10
const BRIBE_KC := 150
const MEETING_RESPECT := 3.0
const LEAFLET_RESPECT := 0.3
const WISH_TASK_RESPECT := 4.0        # M3.2 úkol obecní údržby (lavička, úklid) splněný během kampaně
const SLANDER_POP_HIT := 6.0
const FORGE_REVEAL_P := 0.3
## Šance, že postava úplatek / pomluvu někomu řekne dál (povaha rozhoduje – drbna a přísný skoro jistě).
const TELL_CHANCE := {"drbna": 0.85, "prisny": 0.7, "_": 0.4, "veselak": 0.3, "plachy": 0.25, "moudry": 0.6}

var world: World
var meeting_topics := {}     # pid → Array[String] id přání probraných na mítinku (bez opakování)
var mailbox_jd := {}         # pid → int (den, pro reset „dnes obešité schránky“)
var mailboxes := {}          # pid → Array[int] (index schránky v `World.street_mailboxes`)
var forge_jd := {}           # pid → int (den posledního zfalšovaného podpisu – 1×/den)
var bribed := {}             # pid → Array[String] (jména postav, co úplatek přijaly – bez opakování)
var slander_jd := {}         # pid → int (den poslední pomluvy – 1×/den)
var promises := {}           # pid → int (sliby bez krytí – „dluh slibů“, vyřeší M7.4)
var story := {}              # pid → Array[String] (deník „Příběh kampaně“, posledních 12 záznamů)
var result := {}             # pid → "" / "vitez" / "prohra" (poslední vyhodnocené volby)


func setup(w: World) -> void:
	world = w


func _log(pid: int, text: String) -> void:
	var a: Array = story.get(pid, [])
	a.append(text)
	if a.size() > 12:
		a.pop_front()
	story[pid] = a


## M7.4: splacení jednoho nekrytého slibu z kampaně (volá `MayorOffice` po dokončení projektu obce).
func fulfill_promise(pid: int, text: String) -> void:
	var pr := int(promises.get(pid, 0))
	if pr <= 0:
		return
	promises[pid] = pr - 1
	_log(pid, text)


# ------------------------------------------------------------------ poctivě: mítink, letáky, úkoly

## Nabídka na mítink v sále hospody (M1.5 / M5.5): probere jedno z aktuálních přání obce (`Politics.wishes`).
func open_meeting(pid: int) -> void:
	var pol: Politics = world.politics
	if pol == null:
		return
	var done: Array = meeting_topics.get(pid, [])
	var pool := []
	for w in pol.wishes:
		if not (String(w.get("id", "")) in done):
			pool.append(w)
	if pool.is_empty():
		world.notify(pid, "show_message", ["Mítink: přání obce jsi už probral(a) všechna. Zkus letáky.", 4.0])
		return
	var opts := []
	for w in pool:
		var wid := String(w["id"])
		var text := String(w["text"])
		opts.append(["Poctivě slíbit: %s" % text, _take_wish.bind(pid, wid, text, false)])
		opts.append(["Slíbit bez krytí (rychlejší, ale „dluh slibů“): %s" % text, _take_wish.bind(pid, wid, text, true)])
	world.notify(pid, "open_menu", ["Mítink v sále hospody", "O čem budeš mluvit s lidmi?", opts])


func _take_wish(pid: int, wid: String, text: String, false_promise: bool) -> void:
	var pol: Politics = world.politics
	var done: Array = meeting_topics.get(pid, [])
	done.append(wid)
	meeting_topics[pid] = done
	if false_promise:
		if pol:
			pol.add_deceit(pid, 5.0)
		promises[pid] = int(promises.get(pid, 0)) + 1
		_log(pid, "Mítink: slib bez krytí – „%s“. Potlesk, ale bude to třeba jednou splnit." % text)
		world.notify(pid, "show_message", ["Slib bez krytí vzbudil nadšení (skrytý klam +).", 4.0])
	else:
		var rep: Reputation = world.reputations.get(pid)
		if rep:
			rep.change_respect("sousede", MEETING_RESPECT, "mítink: slib %s" % text)
		_log(pid, "Mítink: reálný slib – „%s“ (respekt obce +)." % text)
		world.notify(pid, "show_message", ["Mítink: lidi zajímá „%s“. Potlesk (respekt +)." % text, 4.5])


## Hození letáku do poštovní schránky (`World.street_mailboxes`, index `idx`) – malý, ale reálný nárůst podpory.
func deliver_leaflet(pid: int, idx: int) -> void:
	var jd := world.clock.jd()
	if int(mailbox_jd.get(pid, -1)) != jd:
		mailboxes[pid] = []
		mailbox_jd[pid] = jd
	var done: Array = mailboxes.get(pid, [])
	if idx in done:
		return
	done.append(idx)
	mailboxes[pid] = done
	var rep: Reputation = world.reputations.get(pid)
	if rep:
		rep.change_respect("sousede", LEAFLET_RESPECT, "leták do schránky")
	world.notify(pid, "show_message", ["Leták ve schránce (%d/%d dnes)." % [done.size(), MAILBOXES_NEEDED], 2.5])
	if done.size() >= MAILBOXES_NEEDED:
		_log(pid, "Roznos letáků: dnes obešel(a) %d schránek v ulici." % done.size())


## Splnění úkolu obecní údržby (lavička, úklid – M3.2) během kampaně = plnění přání obce „na vlastní kůži“.
func on_event(pid: int, kind: String, data: Dictionary) -> void:
	if kind == "job_task_done" and String(data.get("job", "")) == "udrzba":
		var rep: Reputation = world.reputations.get(pid)
		if rep:
			rep.change_respect("sousede", WISH_TASK_RESPECT, "splnil přání obce při kampani")
		_log(pid, "Plnění přání obce: úkol obecní údržby hotový, lidi si toho všimli.")


# ------------------------------------------------------------------ nečestně: úplatek, pomluva, podvod

## Nabídka úplatku postavě (rozhovor T: „dám ti stovku, když mě budeš volit“ → intent „bribe“, `World._apply_reply`).
func try_bribe(pid: int, per: Persona, attitude: float) -> Dictionary:
	if per == null:
		return {"text": ""}
	var p: Player = world.players.get(pid)
	if p == null or p.money < BRIBE_KC:
		return {"text": "Na úplatek nemáš ani %s." % Bazaar.kc(BRIBE_KC)}
	var trait_ := String(per.profile.get("trait", ""))
	var chance := 0.75 if attitude >= 0.0 else 0.35
	if trait_ == "prisny":
		chance *= 0.4
	if not (randf() < chance):
		return {"text": "Úplatky neberu. Styď se, že to zkoušíš."}
	p.money -= BRIBE_KC
	var pol: Politics = world.politics
	if pol:
		pol.add_deceit(pid, 4.0)
	var key := String(per.profile.get("name", per.display_name()))
	var mine: Array = bribed.get(pid, [])
	if not (key in mine):
		mine.append(key)
		bribed[pid] = mine
	_log(pid, "Úplatek %s pro %s – hlas slíbený, ale riskuješ odhalení." % [Bazaar.kc(BRIBE_KC), per.first_name()])
	if randf() < _reveal_chance(pid, float(TELL_CHANCE.get(trait_, TELL_CHANCE["_"])), true):
		_scandal(pid, "podplaceni_volicu", "Vyšlo najevo, že jsi podplácel voliče.")
	return {"text": "Dobře, tu %s vezmu. Budeš mít hlas." % Bazaar.kc(BRIBE_KC)}


## Pomluva o protikandidátovi (rozhovor T → intent „slander“): šíří se drby, při důvěře postavy klesá
## opravdová popularita protikandidáta; odhalení je velký pád (skandál + volební podvod).
func try_slander(pid: int, per: Persona, attitude: float) -> Dictionary:
	if per == null:
		return {"text": ""}
	var pol: Politics = world.politics
	if pol == null:
		return {"text": ""}
	var jd := world.clock.jd()
	if int(slander_jd.get(pid, -1)) == jd:
		return {"text": "To už jsi dneska roztrousil(a). Lidi mluví jen o jedné fámě za den."}
	slander_jd[pid] = jd
	var trait_ := String(per.profile.get("trait", ""))
	var believes := attitude >= -20.0 and trait_ != "moudry"
	if believes:
		pol.opponent_pop = clampf(pol.opponent_pop - SLANDER_POP_HIT, Politics.OPPONENT_POP_MIN, Politics.OPPONENT_POP_MAX)
		pol.add_deceit(pid, 3.0)
		_log(pid, "Fáma o %s se roznesla po vsi." % Politics.OPPONENT_NAME)
	if randf() < _reveal_chance(pid, float(TELL_CHANCE.get(trait_, TELL_CHANCE["_"])), true):
		_scandal(pid, "volebni_podvod", "Vyšlo najevo, že jsi šířil(a) lživé pomluvy o protikandidátovi.")
	return {"text": "To se musí roznést po vsi." if believes else "To si nekup, tomu nevěřím."}


## Zfalšovaný podpis pod petici (úřad, 1× denně) – obchází `Politics.sign_petition` (žádná postava nic nepodepsala).
func forge_signature(pid: int) -> void:
	var pol: Politics = world.politics
	if pol == null:
		return
	var jd := world.clock.jd()
	if int(forge_jd.get(pid, -1)) == jd:
		world.notify(pid, "show_message", ["Dnes už jsi jeden podpis přimaloval(a). Na úřadě si toho jinak všimnou.", 3.5])
		return
	forge_jd[pid] = jd
	pol.signatures[pid] = pol.signatures_of(pid) + 1
	pol.add_deceit(pid, 2.0)
	_log(pid, "Podpis pod petici sis přimaloval(a) sám(a) – riziko, že si toho na úřadě všimnou.")
	world.notify(pid, "show_message", ["Podpis (přimalovaný) – petice %d/%d." % [pol.signatures_of(pid), pol.signatures_needed()], 3.0])
	if randf() < _reveal_chance(pid, FORGE_REVEAL_P, false):
		_scandal(pid, "volebni_podvod", "Vyšlo najevo, že jsi zfalšoval(a) podpisy petice.")


## Šance na odhalení: povahová ochota mluvit (nebo úřední audit u podvodu) − štěstí z karmy (`Reputation.luck`),
## zvýšená, když to navíc vidí / uslyší svědek (`World.witness_reported`).
func _reveal_chance(pid: int, base: float, witness: bool) -> float:
	var rep: Reputation = world.reputations.get(pid)
	var luck := rep.luck() if rep else 0.0
	var c := clampf(base - luck, 0.05, 0.97)
	var p: Player = world.players.get(pid)
	if witness and p and world.witness_reported(pid, p.global_position, "kampan", 14.0, 10.0):
		c = clampf(c + 0.25, 0.05, 0.99)
	return c


## Skandál: pád pověsti, skrytý klam se obrátí proti hráči, přestupek / trestný čin (`World.commit_offense`
## → případně soud M4.3 → odsouzení vyřadí z kandidatury přes `Politics.clean_record`).
func _scandal(pid: int, offense_id: String, text: String) -> void:
	var pol: Politics = world.politics
	if pol:
		pol.add_deceit(pid, -20.0)
	var rep: Reputation = world.reputations.get(pid)
	if rep:
		rep.change(-15.0, text, offense_id)
	world.commit_offense(pid, offense_id, {"severity": 0.4})
	_log(pid, "SKANDÁL: %s" % text)
	world.notify(pid, "popup", ["Skandál! %s" % text, 6.0])


# ------------------------------------------------------------------ interakce ve světě

func interactables(id: int) -> Array:
	var out := []
	var p: Player = world.players.get(id)
	if p == null or p.inside != "":
		return out
	var pol: Politics = world.politics
	if pol == null:
		return out
	var hospoda: Place = world.places.get("hospoda")
	if hospoda and hospoda.is_open(world.clock.hour()):
		out.append({"pos": hospoda.door, "r": 3.0, "kind": "custom", "text": "Mítink kampaně (v sále)", "action": open_meeting})
	var urad: Place = world.places.get("urad")
	if urad and urad.is_open(world.clock.hour()) and int(forge_jd.get(id, -1)) != world.clock.jd():
		out.append({"pos": urad.door, "r": 3.0, "kind": "custom", "text": "Přimalovat podpis na petici (podvod)", "action": forge_signature})
	var jd := world.clock.jd()
	if int(mailbox_jd.get(id, -1)) != jd:
		mailboxes[id] = []
		mailbox_jd[id] = jd
	var done: Array = mailboxes.get(id, [])
	if done.size() < MAILBOXES_NEEDED:
		for i in world.street_mailboxes.size():
			if i in done:
				continue
			out.append({"pos": world.street_mailboxes[i], "r": 2.2, "kind": "custom",
				"text": "Hodit leták do schránky (%d/%d dnes)" % [done.size(), MAILBOXES_NEEDED], "action": deliver_leaflet.bind(i)})
	return out


# ------------------------------------------------------------------ volební den

## Simulace hlasování všech postav (`Characters`) podle popularity hráče a soupeřů (s šumem na hlas).
func _simulate_votes(my: float, rivals: Dictionary) -> Dictionary:
	var counts := {"hrac": 0}
	for k in rivals:
		counts[k] = 0
	var total_r := 0.0
	for k in rivals:
		total_r += float(rivals[k])
	for _i in Characters.count():
		var roll := randf() * 100.0
		if roll < my:
			counts["hrac"] = int(counts["hrac"]) + 1
			continue
		var r2 := randf() * maxf(total_r, 1.0)
		var acc := 0.0
		var picked: String = String(rivals.keys()[0]) if not rivals.is_empty() else "hrac"
		for k in rivals:
			acc += float(rivals[k])
			if r2 <= acc:
				picked = k
				break
		counts[picked] = int(counts.get(picked, 0)) + 1
	return counts


## Vyhodnocení volebního dne (voláno z `Politics.tick()`, když `jd` přesáhne `election_jd`). Nastaví nový
## termín sama (výhra = další celé období, prohra = doplňovací volby za 120 dní podle kroku M7.2).
func resolve_election() -> void:
	var pol: Politics = world.politics
	if pol == null:
		return
	for pid in world.players:
		var my := pol.popularity(pid)
		var rivals := {Politics.OPPONENT_NAME: pol.opponent_pop}
		for c in pol.candidates:
			rivals[String(c["name"])] = float(c["pop"])
		var counts := _simulate_votes(my, rivals)
		var mine := int(counts.get("hrac", 0))
		var best_name := ""
		var best_n := -1
		for k in counts:
			if k != "hrac" and int(counts[k]) > best_n:
				best_n = int(counts[k])
				best_name = k
		var win := mine > best_n
		if mine == best_n:
			win = randf() < 0.5
		var lines := "Výsledky hlasování na úřadě:\n  Ty: %d hlasů\n" % mine
		for k in counts:
			if k != "hrac":
				lines += "  %s: %d hlasů\n" % [k, int(counts[k])]
		if pol.is_mayor(pid) and world.mayor_office:   # M7.4: konec právě končícího mandátu (dřív, než se přepíše mayor[pid])
			world.mayor_office.on_term_end(pid, win)
		pol.mayor[pid] = win
		if win:
			lines += "\nZvítězil(a) jsi! Zastupitelstvo tě zvolilo starostou/starostkou obce."
			_log(pid, "VOLBY: vyhráno (%d : %d)!" % [mine, best_n])
		else:
			lines += "\nProhra proti %s (%d : %d). Další (doplňovací) volby za 120 dní." % [best_name, best_n, mine]
			_log(pid, "VOLBY: prohra proti %s (%d : %d)." % [best_name, best_n, mine])
		world.notify(pid, "open_menu", ["Vyhlášení výsledků voleb (náves)", lines, []])
		result[pid] = "vitez" if win else "prohra"
		meeting_topics[pid] = []
		mailboxes[pid] = []
		bribed[pid] = []
		pol.election_jd = world.clock.jd() + (pol.term_days if win else 120)
		if not win:
			pol.reroll_for_new_term()


# ------------------------------------------------------------------ deník (připojuje se do `Politics.journal_bbcode`)

func journal_section(pid: int) -> String:
	var s := "\n[b]Příběh kampaně[/b]\n"
	var a: Array = story.get(pid, [])
	if a.is_empty():
		s += "  (zatím žádné záznamy – zajdi na mítink, roznes letáky…)\n"
	else:
		for t in a:
			s += "  • %s\n" % t
	var pr := int(promises.get(pid, 0))
	if pr > 0:
		s += "  Dluh slibů bez krytí: %d (vyřeší se, až budeš starostou/starostkou)\n" % pr
	return s


# ------------------------------------------------------------------ uložení

func to_dict(pid: int) -> Dictionary:
	return {"meeting": meeting_topics.get(pid, []), "promises": int(promises.get(pid, 0)),
		"bribed": bribed.get(pid, []), "story": story.get(pid, []), "result": String(result.get(pid, ""))}


func from_dict(pid: int, d: Dictionary) -> void:
	if d.is_empty():
		return
	meeting_topics[pid] = d.get("meeting", [])
	promises[pid] = int(d.get("promises", 0))
	bribed[pid] = d.get("bribed", [])
	story[pid] = d.get("story", [])
	result[pid] = String(d.get("result", ""))
