class_name Debts
extends Node

## Společná evidence dluhů hráčů (M4.2): pokuty (bloková složenka, příkaz poštou, soud), upomínky,
## exekuce z účtu. Jedna instance `World.debts`, stav per hráč. M4.3 (peněžitý trest) a M4.7 (hypotéka,
## splátky) přidávají položky přes `add` a platby řeší přes `pay` – API se nemění.
## Denní krok `advance_to(jd)` volá World při změně dne i po `skip_time` (dohání po dnech).

## Kč: poplatek za upomínku (přičte se k dluhu)
const REMINDER_FEE := 1000
## dní od upomínky do exekuce
const ENFORCE_DAYS := 30
## Kč: exekutorské náklady (orientačně, ověřit)
const ENFORCE_COST := 3000
## pověst za exekuci
const ENFORCE_REP := -5.0
## splatnost od vystavení (dny)
const DUE_DAYS := 15
## doručení příkazu správního řízení (dny od přestupku, rozmezí)
const ORDER_DELAY := [1, 3]
## druhy dluhů, které počítá a platí „Zaplatit pokuty“ (Computer, úřad)
const FINE_KINDS := ["pokuta", "naklady_rizeni"]
const STAGE_NAMES := {"splatne": "splatné", "upominka": "upomínka", "exekuce": "exekuce", "zaplaceno": "zaplaceno"}
const SENDER := "Správní orgán (smyšlený)"

var world: World
var _debts := {}      # pid → Array[Dictionary] {id, pid, kind, text, kc, paid, due_jd, stage, upominka_jd, creditor, ref}
var _orders := {}     # pid → Array[Dictionary] {deliver_jd, kc, text, ref} – příkazy na cestě poštou
var _seq := {}        # pid → počet vytvořených položek (kvůli unikátnímu id)
var _last_jd := -1


func setup(w: World) -> void:
	world = w


func _ensure(pid: int) -> void:
	if not _debts.has(pid):
		_debts[pid] = []
	if not _orders.has(pid):
		_orders[pid] = []


## Přidá dluh. Vrací id položky.
func add(pid: int, kind: String, kc: int, due_jd: int, text: String, ref := "") -> String:
	_ensure(pid)
	var n: int = int(_seq.get(pid, 0)) + 1
	_seq[pid] = n
	var did := "%d-%d" % [pid, n]
	(_debts[pid] as Array).append({"id": did, "pid": pid, "kind": kind, "text": text, "kc": maxi(kc, 0), "paid": false,
		"due_jd": due_jd, "stage": "splatne", "upominka_jd": -1, "creditor": SENDER, "ref": ref})
	return did


## Zařadí příkaz správního řízení: doručí se poštou za 1–3 dny a teprve pak vznikne dluh (splatnost 15 dní).
func queue_order(pid: int, kc: int, jd: int, text: String, ref := "") -> void:
	_ensure(pid)
	var delay := randi_range(int(ORDER_DELAY[0]), int(ORDER_DELAY[1]))
	(_orders[pid] as Array).append({"deliver_jd": jd + delay, "kc": kc, "text": text, "ref": ref})


## Platba části / celého dluhu. from: "cash" (hotovost) nebo "bank" (účet, `Computer.withdraw_bank`).
## Vrací zaplacenou částku (Kč).
func pay(pid: int, debt_id: String, kc: int, from := "cash") -> int:
	var d := find(pid, debt_id)
	var pl: Player = world.players.get(pid) if world else null
	if d.is_empty() or pl == null or d["paid"]:
		return 0
	var amt := mini(mini(kc, int(d["kc"])), pl.money if from == "cash" else pl.bank)
	if amt <= 0:
		return 0
	if from == "cash":
		pl.money -= amt
	else:
		if not world.computer or not world.computer.withdraw_bank(pid, amt, "Úhrada: %s" % d["text"]):
			return 0
	d["kc"] = int(d["kc"]) - amt
	if int(d["kc"]) <= 0:
		_close(d)
	return amt


func _close(d: Dictionary) -> void:
	d["kc"] = 0
	d["paid"] = true
	d["stage"] = "zaplaceno"


func find(pid: int, debt_id: String) -> Dictionary:
	for d in _debts.get(pid, []):
		if String(d["id"]) == debt_id:
			return d
	return {}


## Otevřené dluhy (seřazené podle splatnosti); open_only = false vrátí i zaplacené.
func list(pid: int, open_only := true) -> Array:
	var out := []
	for d in _debts.get(pid, []):
		if not open_only or not d["paid"]:
			out.append(d)
	out.sort_custom(func(a, b): return int(a["due_jd"]) < int(b["due_jd"]))
	return out


func orders(pid: int) -> Array:
	return (_orders.get(pid, []) as Array).duplicate()


## Součet otevřených dluhů (Kč); kinds prázdné = všechny druhy.
func total(pid: int, kinds: Array = []) -> int:
	var sum := 0
	for d in _debts.get(pid, []):
		if d["paid"]:
			continue
		if kinds.is_empty() or kinds.has(d["kind"]):
			sum += int(d["kc"])
	return sum


## Denní krok: dožene všechny dny od posledního volání až do `jd` (po dnech, i po skoku přes měsíce).
func advance_to(jd: int) -> void:
	if world == null:
		return
	if _last_jd < 0 or jd < _last_jd:
		_last_jd = jd
		return
	while _last_jd < jd:
		_last_jd += 1
		_step(_last_jd)


## Po načtení uloženého stavu: nedohánět dny z doby před uložením.
func reset_clock(jd: int) -> void:
	_last_jd = jd


func _step(jd: int) -> void:
	for pid in _orders.keys():
		var rest := []
		for o in _orders[pid]:
			if int(o["deliver_jd"]) <= jd:
				add(pid, "pokuta", int(o["kc"]), jd + DUE_DAYS, String(o["text"]), String(o.get("ref", "")))
				_notify_mail(pid, "Příkaz k úhradě pokuty",
					"Správní orgán vydal příkaz k úhradě: %s.\nČástka: %s. Splatnost %d dní od doručení.\n(Zjednodušená herní simulace – ověřit aktuální znění zákonů.)" % [
					o["text"], Bazaar.kc(int(o["kc"])), DUE_DAYS])
			else:
				rest.append(o)
		_orders[pid] = rest
	for pid in _debts.keys():
		for d in _debts[pid]:
			if d["paid"]:
				continue
			if d["stage"] == "splatne" and jd > int(d["due_jd"]):
				d["stage"] = "upominka"
				d["upominka_jd"] = jd
				d["kc"] = int(d["kc"]) + REMINDER_FEE
				_notify_mail(pid, "Upomínka k úhradě",
					"Dluh „%s“ nebyl uhrazen včas. Účtován poplatek za upomínku %s.\nCelkem k úhradě: %s. Pokud nezaplatíte do %d dní, bude zahájena exekuce." % [
					d["text"], Bazaar.kc(REMINDER_FEE), Bazaar.kc(int(d["kc"])), ENFORCE_DAYS])
			elif d["stage"] == "upominka" and jd >= int(d["upominka_jd"]) + ENFORCE_DAYS:
				d["stage"] = "exekuce"
				d["kc"] = int(d["kc"]) + ENFORCE_COST
				_notify_mail(pid, "Exekuční příkaz",
					"Dluh „%s“ je v exekuci. Exekutorské náklady %s. Částka se strhává z účtu." % [d["text"], Bazaar.kc(ENFORCE_COST)])
				if world.reputations.has(pid):
					world.reputations[pid].change(ENFORCE_REP, "exekuce: %s" % d["text"])
			if d["stage"] == "exekuce":
				_enforce(pid, d)


## Exekuce: strhne co jde z účtu (výplatu na dluh zatím neřeší – otevřený bod).
func _enforce(pid: int, d: Dictionary) -> void:
	var pl: Player = world.players.get(pid)
	if pl == null or world.computer == null:
		return
	var amt := mini(int(d["kc"]), pl.bank)
	if amt > 0 and world.computer.withdraw_bank(pid, amt, "Exekuce: %s" % d["text"]):
		d["kc"] = int(d["kc"]) - amt
		if int(d["kc"]) <= 0:
			_close(d)


func _notify_mail(pid: int, subject: String, body: String) -> void:
	if world:
		world.send_mail(pid, SENDER, subject, body)


## Zaplatí otevřené pokuty z hotovosti, od nejstarší. Vrací zaplacenou částku.
func pay_fines_cash(pid: int) -> int:
	var paid := 0
	for d in list(pid):
		if not FINE_KINDS.has(d["kind"]):
			continue
		paid += pay(pid, String(d["id"]), int(d["kc"]), "cash")
	return paid


func to_dict(pid: int) -> Dictionary:
	_ensure(pid)
	return {"items": (_debts[pid] as Array).duplicate(true), "orders": (_orders[pid] as Array).duplicate(true),
		"seq": int(_seq.get(pid, 0))}


func from_dict(pid: int, d: Dictionary) -> void:
	_debts[pid] = (d.get("items", []) as Array).duplicate(true)
	_orders[pid] = (d.get("orders", []) as Array).duplicate(true)
	_seq[pid] = int(d.get("seq", (_debts[pid] as Array).size()))
