## M7.4 – Starostování: rozpočet obce, projekty s viditelnou změnou, zastupitelstvo a konce příběhu.
## Navazuje na `World.politics` (M7.1, `Politics.is_mayor`) a `World.campaign` (M7.2, `promises` = dluh slibů
## bez krytí). Jedna instance `World.mayor_office` – rozpočet, rozjednaný projekt a hotové projekty jsou
## OBECNÍ (globální, ne per hráč – obec má jeden rozpočet), korupce a konec příběhu jsou per hráč.
## Interakce: kancelář starosty = stejná přepážka úřadu jako M7.1/M7.2 (`urad.door`), nabídka se zobrazí
## jen zvolenému starostovi/starostce (`Politics.is_mayor`).
##
## - **Rozpočet** (`_monthly_step`, 1×/měsíc podle `Clock`): příjmy = daně (paušál) + státní dotace +
##   pronájem obecních pozemků (`World.katastr.parcel_owner == "obec"`, z M4.7 výkupu parcel obcí),
##   výdaje = běžná údržba + údržba hotových projektů. Zůstatek `treasury` (Kč).
## - **Projekty** (`PROJECTS`): cena, doba (dny), dopad na respekt jedné komunity (`Reputation.COMMUNITIES`)
##   a viditelná změna ve světě (`_apply_visual`) – nové lavičky, cedule, neutuchající veřejné osvětlení
##   (`MayorOffice.bright_village`, čte `priroda/street_lights.gd`), lepší silnice (`MayorOffice.road_grip_bonus`,
##   čte `car.gd._surface_grip`, statické proměnné bez vazby na konkrétní World – jednodušší než drátovat
##   referenci do `car.gd`). Jen jeden projekt najednou; hotový projekt splácí i jeden ze starých
##   nekrytých slibů kampaně (`Campaign.fulfill_promise`).
## - **Zastupitelstvo** (`COUNCIL_TOPICS`, nová agenda 1×/měsíc): 2–3 body, hlasování „po svém“ (ANO/NE),
##   výsledek s pravděpodobností podle popularity hráče (`Politics.popularity`) – zastupitelé loajálnější
##   popularitě hráče ho přehlasují méně.
## - **Sliby a klam**: nesplněné sliby (`Campaign.promises`) občas (drby) strhnou pověst, dokud nejsou
##   vyřešeny projektem. Úplatky od podnikatelů (anonymní, smyšlené – žádná reálná firma): přijetí dá peníze
##   a riziko odhalení (`World.commit_offense("korupce", …)`, `data/zakon.json` → soud M4.3).
## - **Konce příběhu** (`on_term_end`, voláno z `Campaign.resolve_election()` před přepsáním `Politics.mayor`):
##   „padlý starosta“ (odsouzení – `Politics.clean_record` false), „šedá eminence“ (brala úplatky, ale bez
##   odsouzení), „starosta proti své vůli“ (hodně nekrytých slibů a nízká popularita), „oblíbený starosta“
##   (znovuzvolení bez skandálu). Jen oznamovací scéna (`open_menu`) – hra pokračuje dál (noví voliči / nový
##   mandát řeší `Politics`/`Campaign` samy).
## Ukládání: `to_dict(pid)` / `from_dict(pid, d)`, klíč `mayor_office` v `SaveGame` (starý save bez klíče =
## čistý rozpočet, žádný projekt, žádná korupce).
class_name MayorOffice
extends RefCounted

## Laditelné hodnoty rozpočtu (Kč / herní měsíc).
const TAX_MESICNE_KC := 25000
const DOTACE_MESICNE_KC := 8000
const RENT_PARCELA_MESICNE_KC := 300
const UDRZBA_MESICNE_KC := 9000
const PROJEKT_UDRZBA_MESICNE_KC := 500
const START_TREASURY := 40000.0

const BRIBE_OFFER_CHANCE := 0.3        # šance na nabídku úplatku za měsíc (jen když je hráč starostou)
const BRIBE_KC := 20000
const BRIBE_REVEAL_P := 0.22
const PROMISE_POP_HIT_P := 0.25        # šance, že nevyřešený dluh slibů strhne pověst ten měsíc
const PROMISE_POP_HIT := -2.0
const PROMISE_DEBT_PROTI_VULI := 3     # od kolika nekrytých slibů hrozí konec „proti své vůli“

## Katalog projektů obce – cena, doba (dny), komunita + respekt při dokončení, popis, viditelná změna (`_apply_visual`).
const PROJECTS := {
	"silnice": {"name": "Oprava silnice", "cena": 180000, "dny": 30, "komunita": "zemedelci", "respekt": 8.0,
		"popis": "Méně výmolů, bezpečnější silnice v obci."},
	"lavicky": {"name": "Nové lavičky", "cena": 15000, "dny": 7, "komunita": "sousede", "respekt": 5.0,
		"popis": "Pár nových laviček na návsi."},
	"osvetleni": {"name": "Veřejné osvětlení celou noc", "cena": 40000, "dny": 14, "komunita": "sousede", "respekt": 6.0,
		"popis": "Lampy budou svítit celou noc, ne jen do půlnoci."},
	"zastavka": {"name": "Autobusová zastávka", "cena": 60000, "dny": 21, "komunita": "mladez", "respekt": 6.0,
		"popis": "Nový přístřešek se zastávkou místo holé tyče."},
	"hasicarna": {"name": "Vybavení hasičárny", "cena": 90000, "dny": 21, "komunita": "hasici", "respekt": 8.0,
		"popis": "Nová výbava pro sbor dobrovolných hasičů."},
}

## Agenda zastupitelstva – 2–3 body/měsíc, losují se z tohoto fondu (smyšlené, satira bez reálné obce).
const COUNCIL_TOPICS := [
	{"id": "prodej_pozemku", "text": "Prodat obecní pozemek sousedovi za výhodnou cenu?",
		"yes": "Schválit prodej", "no": "Zamítnout",
		"yes_effect": {"treasury": 15000, "respect": {"zemedelci": -3.0}}, "no_effect": {"respect": {"zemedelci": 2.0}}},
	{"id": "tancovacka", "text": "Povolit tancovačku v hospodě do rána?",
		"yes": "Povolit", "no": "Zamítnout",
		"yes_effect": {"respect": {"mladez": 5.0, "stamgasti": 3.0, "sousede": -2.0}}, "no_effect": {"respect": {"sousede": 1.0, "mladez": -2.0}}},
	{"id": "parkovani", "text": "Zakázat parkování na návsi?",
		"yes": "Zakázat", "no": "Nechat tak",
		"yes_effect": {"respect": {"sousede": 3.0}}, "no_effect": {"respect": {"sousede": -1.0}}},
	{"id": "dotace_hasici", "text": "Schválit mimořádnou dotaci sboru hasičů?",
		"yes": "Schválit (−5 000 Kč)", "no": "Zamítnout",
		"yes_effect": {"treasury": -5000, "respect": {"hasici": 6.0}}, "no_effect": {"respect": {"hasici": -3.0}}},
	{"id": "poplatky", "text": "Zvýšit místní poplatky?",
		"yes": "Zvýšit", "no": "Nechat tak",
		"yes_effect": {"treasury": 8000, "respect": {"sousede": -4.0}}, "no_effect": {}},
	{"id": "hriste_pronajem", "text": "Pronajmout fotbalové hřiště na soukromou akci?",
		"yes": "Pronajmout", "no": "Zamítnout",
		"yes_effect": {"treasury": 4000, "respect": {"fotbal": -3.0}}, "no_effect": {"respect": {"fotbal": 2.0}}},
]

## Konce příběhu – jen oznamovací text, hra pokračuje dál.
const ENDINGS := {
	"oblibeny": {"title": "Oblíbený starosta", "text":
		"Lidé tě znovu zvolili – vedl(a) jsi obec poctivě a bylo to vidět. Mandát pokračuje dál."},
	"sediva": {"title": "Šedá eminence", "text":
		"Nikdo na to nepřišel, ale ty víš, kolik „drobností“ jsi přijal(a). Obec funguje – ty víš svoje."},
	"padly": {"title": "Padlý starosta", "text":
		"Soud tě uznal vinným. Mandát skončil ostudou – drby o tobě poběží po vsi ještě dlouho."},
	"proti_vuli": {"title": "Starosta proti své vůli", "text":
		"Zůstal(a) jsi poctivý/á, ale staré sliby bez krytí tě dojely – rozpočet na dně, lidi nespokojení."},
}

## M7.4: lepší povrch po opravě silnice – čte `car.gd._surface_grip` (bez drátování reference do `World`).
static var road_grip_bonus := 0.0
## M7.4: po projektu „veřejné osvětlení“ lampy nešetří 0–4 h – čte `priroda/street_lights.gd`.
static var bright_village := false

var world: World
var treasury := START_TREASURY
var month_mark := -1                 # rok*12+měsíc posledního měsíčního kroku
var active_project := {}             # {} nebo {id, start_jd, end_jd, pid}
var done_projects: Array = []        # Array[String] – obecní, nezávislé na tom, kdo je teď starostou
var council_agenda: Array = []       # aktuální body zastupitelstva (vyprázdní se při novém měsíci)
var corrupt_count := {}              # pid -> int, přijaté úplatky za CELÝ aktuální mandát (reset na on_term_end)
var bribe_pending := {}              # pid -> bool, čeká nabídka úplatku
var endings := {}                    # pid -> posledně vyhodnocený konec příběhu ("" = žádný)
var _last_jd := -1


func setup(w: World) -> void:
	world = w
	road_grip_bonus = 0.0        # nová hra ve stejném běhu procesu (static var) = bez starých bonusů
	bright_village = false


# ------------------------------------------------------------------ denní / měsíční krok

func tick(jd: int) -> void:
	if jd == _last_jd:
		return
	_last_jd = jd
	var d := Clock.from_jdn(jd)
	var ym := int(d["year"]) * 12 + int(d["month"])
	if ym != month_mark:
		month_mark = ym
		_monthly_step()
	_check_project_done(jd)


func _monthly_step() -> void:
	var parcels_obec := 0
	if world.katastr:
		for v in world.katastr.parcel_owner.values():
			if String(v) == "obec":
				parcels_obec += 1
	var income := TAX_MESICNE_KC + DOTACE_MESICNE_KC + parcels_obec * RENT_PARCELA_MESICNE_KC
	var expense := UDRZBA_MESICNE_KC + done_projects.size() * PROJEKT_UDRZBA_MESICNE_KC
	treasury += float(income - expense)
	council_agenda = _roll_council()
	for id in world.players:
		if world.politics == null or not world.politics.is_mayor(id):
			continue
		world.notify(id, "show_message", ["Rozpočet obce: příjmy %s, výdaje %s, zůstatek %s." %
			[Bazaar.kc(income), Bazaar.kc(expense), Bazaar.kc(roundi(treasury))], 5.0])
		_maybe_promise_hit(id)
		_maybe_bribe_offer(id)


func _roll_council() -> Array:
	var pool: Array = COUNCIL_TOPICS.duplicate(true)
	pool.shuffle()
	var n := 2 + (1 if randf() < 0.5 else 0)
	return pool.slice(0, mini(n, pool.size()))


func _maybe_promise_hit(pid: int) -> void:
	if world.campaign == null:
		return
	var debt := int(world.campaign.promises.get(pid, 0))
	if debt <= 0 or randf() >= PROMISE_POP_HIT_P:
		return
	var rep: Reputation = world.reputations.get(pid)
	if rep:
		rep.change(PROMISE_POP_HIT, "nesplněný slib z kampaně vyšel najevo", "")
	world.notify(pid, "popup", ["Drby: lidé si všimli, že jsi neplnil(a) slib z kampaně.", 4.5])


func _maybe_bribe_offer(pid: int) -> void:
	if bool(bribe_pending.get(pid, false)):
		return
	if randf() < BRIBE_OFFER_CHANCE:
		bribe_pending[pid] = true
		world.notify(pid, "popup", ["Na úřadě tě čeká místní podnikatel s „nabídkou“ ke stavebnímu povolení.", 5.0])


# ------------------------------------------------------------------ interakce (kancelář starosty = u přepážky úřadu)

func interactables(id: int) -> Array:
	var out := []
	var pol: Politics = world.politics
	if pol == null or not pol.is_mayor(id):
		return out
	var p: Player = world.players.get(id)
	if p == null or p.inside != "":
		return out
	var urad: Place = world.places.get("urad")
	if urad == null or not urad.is_open(world.clock.hour()):
		return out
	out.append({"pos": urad.door, "r": 3.0, "kind": "custom",
		"text": "Kancelář starosty (rozpočet, projekty, zastupitelstvo)", "action": open_office.bind(id)})
	return out


func open_office(pid: int) -> void:
	var opts := []
	opts.append(["Rozpočet obce", _show_budget.bind(pid)])
	opts.append(["Projekty", _show_projects.bind(pid)])
	if not council_agenda.is_empty():
		opts.append(["Zastupitelstvo (%d bodů)" % council_agenda.size(), _show_council.bind(pid)])
	opts.append(["Sliby a klam", _show_story.bind(pid)])
	if bool(bribe_pending.get(pid, false)):
		opts.append(["Podnikatel s nabídkou", _show_bribe.bind(pid)])
	world.notify(pid, "open_menu", ["Kancelář starosty", "Co chceš řešit?", opts])


func _show_budget(pid: int) -> void:
	var txt := "Pokladna obce: %s\n\nHotové projekty: %d / %d\n" % [Bazaar.kc(roundi(treasury)), done_projects.size(), PROJECTS.size()]
	if not active_project.is_empty():
		var pr: Dictionary = PROJECTS[String(active_project["id"])]
		txt += "Rozjednaný projekt: %s (hotovo za %d dní)\n" % [String(pr["name"]), maxi(0, int(active_project["end_jd"]) - world.clock.jd())]
	else:
		txt += "Žádný projekt právě neběží.\n"
	world.notify(pid, "open_menu", ["Rozpočet obce", txt, []])


func _show_projects(pid: int) -> void:
	var opts := []
	for id in PROJECTS:
		var pr: Dictionary = PROJECTS[id]
		if id in done_projects:
			continue
		if not active_project.is_empty():
			opts.append(["(nejdřív dokonči rozjednaný projekt) %s" % String(pr["name"]), _busy_note.bind(pid)])
			continue
		opts.append(["Spustit: %s (%s, %d dní) – %s" % [String(pr["name"]), Bazaar.kc(int(pr["cena"])), int(pr["dny"]), String(pr["popis"])],
			_start_project.bind(pid, id)])
	if opts.is_empty():
		opts.append(["(všechny projekty hotové)", _busy_note.bind(pid)])
	world.notify(pid, "open_menu", ["Projekty obce", "Co se postaví?", opts])


func _busy_note(pid: int) -> void:
	world.notify(pid, "show_message", ["Nejdřív dokonči rozjednaný projekt, nebo už se postavilo všechno.", 3.0])


func _start_project(pid: int, id: String) -> void:
	if not active_project.is_empty() or id in done_projects or not PROJECTS.has(id):
		return
	var pr: Dictionary = PROJECTS[id]
	var cena := int(pr["cena"])
	if treasury < float(cena):
		world.notify(pid, "show_message", ["Na projekt „%s“ obec nemá (chybí %s)." % [String(pr["name"]), Bazaar.kc(cena - roundi(treasury))], 4.0])
		return
	treasury -= float(cena)
	active_project = {"id": id, "start_jd": world.clock.jd(), "end_jd": world.clock.jd() + int(pr["dny"]), "pid": pid}
	world.notify(pid, "show_message", ["Projekt „%s“ schválen, hotovo za %d dní." % [String(pr["name"]), int(pr["dny"])], 4.0])


func _check_project_done(jd: int) -> void:
	if active_project.is_empty():
		return
	if jd < int(active_project["end_jd"]):
		return
	var id := String(active_project["id"])
	var pid := int(active_project.get("pid", 1))
	active_project = {}
	done_projects.append(id)
	_apply_visual(id)
	_apply_rewards(pid, id)


func _apply_rewards(pid: int, id: String) -> void:
	var pr: Dictionary = PROJECTS[id]
	var rep: Reputation = world.reputations.get(pid)
	if rep:
		rep.change_respect(String(pr["komunita"]), float(pr["respekt"]), "projekt obce: %s" % String(pr["name"]))
	if world.campaign and int(world.campaign.promises.get(pid, 0)) > 0:
		world.campaign.fulfill_promise(pid, "Projekt „%s“ splnil jeden ze starých slibů." % String(pr["name"]))
	world.notify(pid, "popup", ["Projekt hotový: %s" % String(pr["name"]), 5.0])


## Viditelná změna ve světě – voláno při dokončení i při načtení uloženého stavu (`from_dict`), musí
## být bezpečné zavolat znovu po restartu hry (nespoléhá na nic, co se ukládá samo).
func _apply_visual(id: String) -> void:
	match id:
		"silnice":
			road_grip_bonus = 0.05
			_place_sign(world.place_pos("obchod") + Vector3(-3.0, 0, 2.0), 0.0, "Silnice opravena – obec")
		"osvetleni":
			bright_village = true
			_place_sign(world.place_pos("urad") + Vector3(3.2, 0, -2.0), 0.0, "Veřejné osvětlení celou noc")
		"lavicky":
			_spawn_benches()
		"zastavka":
			_spawn_bus_stop()
		"hasicarna":
			if world.hasici:
				_place_sign(world.hasici.door() + Vector3(2.0, 0, 0.0), 0.0, "Nové vybavení SDH – díky obci")


func _place_sign(pos: Vector3, yaw: float, text: String) -> void:
	if world.terrain:
		pos.y = world.terrain.height_at(pos.x, pos.z)
	var s := PropModels.road_sign(text, Color(0.2, 0.45, 0.25), Color(1, 1, 1))
	s.position = pos
	s.rotation.y = yaw
	world.add_child(s)


func _spawn_benches() -> void:
	var anchor := world.place_pos("urad")
	var offs: Array[Vector3] = [Vector3(2.6, 0, 1.4), Vector3(-2.6, 0, 1.6), Vector3(0.4, 0, 3.2)]
	for i in offs.size():
		var p: Vector3 = anchor + offs[i]
		if world.terrain:
			p.y = world.terrain.height_at(p.x, p.z) + 0.02
		var bench := Prop.make("lavicka", p, randf_range(0.0, TAU))
		bench.name = "ObecLavicka_M74_%d" % i
		world.add_child(bench)


func _spawn_bus_stop() -> void:
	var anchor := world.place_pos("hospoda")
	var p := anchor + Vector3(-5.0, 0, -3.0)
	if world.terrain:
		p.y = world.terrain.height_at(p.x, p.z) + 0.02
	var bench := Prop.make("lavicka", p, 0.0)
	bench.name = "Zastavka_lavicka_M74"
	world.add_child(bench)
	_place_sign(p + Vector3(0.0, 0, 0.9), 0.0, "Autobusová zastávka (obec)")


# ------------------------------------------------------------------ zastupitelstvo

func _show_council(pid: int) -> void:
	if council_agenda.is_empty():
		world.notify(pid, "open_menu", ["Zastupitelstvo", "Tento měsíc nejsou žádné body k hlasování.", []])
		return
	var opts := []
	for t in council_agenda:
		var td: Dictionary = t
		opts.append([String(td["text"]), _topic_menu.bind(pid, td)])
	world.notify(pid, "open_menu", ["Zastupitelstvo – body k hlasování", "Vyber bod:", opts])


func _topic_menu(pid: int, t: Dictionary) -> void:
	var opts := [
		[String(t.get("yes", "Schválit")), _vote.bind(pid, t, true)],
		[String(t.get("no", "Zamítnout")), _vote.bind(pid, t, false)],
	]
	world.notify(pid, "open_menu", [String(t["text"]), "Jak budeš hlasovat?", opts])


## Zastupitelé hlasují „podle vztahu k hráči“ – zjednodušeno na popularitu (`Politics.popularity`):
## vyšší popularita = větší šance, že zastupitelstvo hráče nepřehlasuje.
func _vote(pid: int, t: Dictionary, want_yes: bool) -> void:
	var pol: Politics = world.politics
	var pop := pol.popularity(pid) if pol else 30.0
	var loyal_chance := clampf(0.3 + pop / 150.0, 0.1, 0.9)
	var outcome_yes := want_yes if randf() < loyal_chance else not want_yes
	var eff: Dictionary = t.get("yes_effect" if outcome_yes else "no_effect", {})
	treasury += float(eff.get("treasury", 0))
	var rep: Reputation = world.reputations.get(pid)
	var resp: Dictionary = eff.get("respect", {})
	if rep:
		for comm in resp:
			rep.change_respect(String(comm), float(resp[comm]), "zastupitelstvo: %s" % String(t["text"]))
	var text := "Zastupitelstvo bod schválilo." if outcome_yes else "Zastupitelstvo bod zamítlo."
	if outcome_yes != want_yes:
		text += " (přehlasovali tě)"
	world.notify(pid, "popup", [text, 4.5])
	for i in council_agenda.size():
		if String((council_agenda[i] as Dictionary).get("id", "")) == String(t.get("id", "")):
			council_agenda.remove_at(i)
			break


# ------------------------------------------------------------------ sliby, klam, úplatky

func _show_story(pid: int) -> void:
	var pr := int(world.campaign.promises.get(pid, 0)) if world.campaign else 0
	var dc := float(world.politics.deceit.get(pid, 0.0)) if world.politics else 0.0
	var co := int(corrupt_count.get(pid, 0))
	var txt := "Nekryté sliby z kampaně: %d\n" % pr
	txt += "Skrytý klam: %.0f\n" % dc
	txt += "Přijaté úplatky za tento mandát: %d\n" % co
	txt += "\nProjekty splácí sliby jeden po druhém – nic jiného s nimi neuděláš."
	world.notify(pid, "open_menu", ["Sliby a klam", txt, []])


func _show_bribe(pid: int) -> void:
	var opts := [
		["Přijmout (%s)" % Bazaar.kc(BRIBE_KC), _bribe_accept.bind(pid)],
		["Odmítnout", _bribe_decline.bind(pid)],
		["Udat na policii (čisté svědomí)", _bribe_report.bind(pid)],
	]
	world.notify(pid, "open_menu", ["Podnikatel s nabídkou", "„Starosto, drobnost za to stavební povolení…“", opts])


func _bribe_accept(pid: int) -> void:
	bribe_pending[pid] = false
	var p: Player = world.players.get(pid)
	if p:
		p.money += BRIBE_KC
	corrupt_count[pid] = int(corrupt_count.get(pid, 0)) + 1
	if world.politics:
		world.politics.add_deceit(pid, 3.0)
	world.notify(pid, "show_message", ["Přijal(a) jsi úplatek %s. Riziko odhalení roste." % Bazaar.kc(BRIBE_KC), 4.0])
	if randf() < BRIBE_REVEAL_P:
		_scandal(pid)


func _bribe_decline(pid: int) -> void:
	bribe_pending[pid] = false
	var rep: Reputation = world.reputations.get(pid)
	if rep:
		rep.change_karma(1.0, "odmítnutí úplatku")
	world.notify(pid, "show_message", ["Nabídku jsi odmítl(a).", 3.0])


func _bribe_report(pid: int) -> void:
	bribe_pending[pid] = false
	var rep: Reputation = world.reputations.get(pid)
	if rep:
		rep.change_karma(3.0, "udání korupční nabídky")
		rep.change_respect("sousede", 2.0, "udal(a) korupční nabídku")
	world.notify(pid, "show_message", ["Nahlásil(a) jsi to. Podnikatel z úřadu zmizel.", 3.5])


func _scandal(pid: int) -> void:
	var rep: Reputation = world.reputations.get(pid)
	if rep:
		rep.change(-18.0, "Vyšlo najevo přijetí úplatku jako starosta/starostka.", "korupce")
	if world.politics:
		world.politics.add_deceit(pid, -25.0)
	world.commit_offense(pid, "korupce", {"severity": 0.5})
	world.notify(pid, "popup", ["Skandál! Vyšlo najevo, že jsi jako starosta/starostka brala úplatky.", 6.0])


# ------------------------------------------------------------------ konec mandátu (voláno z Campaign.resolve_election)

## `reelected` = výsledek PRÁVĚ vyhodnocených voleb pro tohoto hráče (viz `Campaign.resolve_election`,
## voláno, než se přepíše `Politics.mayor[pid]`, takže `pol.is_mayor(pid)` tu ještě znamená „byl(a) starostou“).
func on_term_end(pid: int, reelected: bool) -> void:
	var pol: Politics = world.politics
	var ending := ""
	if pol and not pol.clean_record(pid):
		ending = "padly"
	elif int(corrupt_count.get(pid, 0)) > 0:
		ending = "sediva"
	elif world.campaign and int(world.campaign.promises.get(pid, 0)) >= PROMISE_DEBT_PROTI_VULI and (pol == null or pol.popularity(pid) < 40.0):
		ending = "proti_vuli"
	elif reelected:
		ending = "oblibeny"
	if ending != "":
		endings[pid] = ending
		var e: Dictionary = ENDINGS.get(ending, {})
		world.notify(pid, "open_menu", [String(e.get("title", "Konec mandátu")), String(e.get("text", "")), []])
	corrupt_count[pid] = 0           # nový mandát = čistý štít (minulé skandály zůstávají v Law/Reputation)
	bribe_pending[pid] = false


# ------------------------------------------------------------------ deník (připojuje se do Politics.journal_bbcode)

func journal_section(pid: int) -> String:
	if world.politics == null or not world.politics.is_mayor(pid):
		var last := String(endings.get(pid, ""))
		if last == "":
			return ""
		var e: Dictionary = ENDINGS.get(last, {})
		return "\n[b]Starostování[/b]\n  %s: %s\n" % [String(e.get("title", "")), String(e.get("text", ""))]
	var s := "\n[b]Starostování[/b]\n"
	s += "  Pokladna obce: %s\n" % Bazaar.kc(roundi(treasury))
	if not active_project.is_empty():
		var pr: Dictionary = PROJECTS[String(active_project["id"])]
		s += "  Rozjednaný projekt: %s (hotovo za %d dní)\n" % [String(pr["name"]), maxi(0, int(active_project["end_jd"]) - world.clock.jd())]
	s += "  Hotové projekty: %s\n" % (", ".join(done_projects) if not done_projects.is_empty() else "žádné zatím")
	if not council_agenda.is_empty():
		s += "  Zastupitelstvo čeká na %d bodů (kancelář starosty na úřadě).\n" % council_agenda.size()
	if bool(bribe_pending.get(pid, false)):
		s += "  [color=#f96]Na úřadě čeká podnikatel s nabídkou.[/color]\n"
	return s


# ------------------------------------------------------------------ uložení

func to_dict(pid: int) -> Dictionary:
	return {"treasury": treasury, "active": active_project, "done": done_projects,
		"council_agenda": council_agenda, "corrupt": int(corrupt_count.get(pid, 0)),
		"bribe_pending": bool(bribe_pending.get(pid, false)), "ending": String(endings.get(pid, ""))}


func from_dict(pid: int, d: Dictionary) -> void:
	if d.is_empty():
		return
	treasury = float(d.get("treasury", treasury))
	active_project = d.get("active", {})
	done_projects = d.get("done", [])
	council_agenda = d.get("council_agenda", [])
	corrupt_count[pid] = int(d.get("corrupt", 0))
	bribe_pending[pid] = bool(d.get("bribe_pending", false))
	endings[pid] = String(d.get("ending", ""))
	for id in done_projects:
		if PROJECTS.has(String(id)):
			_apply_visual(String(id))
