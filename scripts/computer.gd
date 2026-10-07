## Počítač doma (M3.4) – logika „internetu“ na vsi, jeden uzel ve `World` (`World.computer`), stav per hráč.
## Obrazovku kreslí klient (`ComputerUI`, E u stolu s PC v domově); tady jsou data a pravidla (v MP poběží na serveru).
##
## - **Moje banka:** účet `Player.bank` (hotovost dál `Player.money`), pohyby účtu, **trvalý příkaz na nájem** (`Estate._rent_check`
##   nejdřív zkusí `pay_rent` z účtu), placení nezaplacených pokut z `Law.LawRecord.unpaid_fines`, výplata z práce na účet
##   (`Jobs.pay_bank`, přepínač u zaměstnavatele / v bance). Hotovost ↔ účet jen u **bankomatu** (objekt u Potravin a u úřadu).
## - **eŠuplík** (e-shop): zboží z `Place.OFFERS["obchod"]` (režim „buy“, bez jídla, pití a tabáku – `ESHOP_SKIP_TYPES`) za cenu
##   o `ESHOP_DISCOUNT` nižší, doprava `SHIPPING_KC`; platba z účtu nebo na dobírku (hotově při převzetí, `COD_KC` navíc).
##   Objednávky `World.orders[pid]` – balík dorazí za 1–2 herní dny (`DELIVERY_DAYS`) po `DELIVERY_HOUR` ke dveřím domova
##   (u bytového domu k vchodu), E u balíku = vybrat.
## - **Bazárek:** stejná nabídka jako bazar u silnice (`Bazaar.offers`), koupě z účtu, prodej vlastního vozidla z bazaru odkudkoli
##   (peníze na účet, kupec si vůz odveze); inzeráty na zvířata jen pro čtení (koupě u cedule hospodářství, M2.6).
## - **Práce v kraji:** nabídky z `data/prace.json` s požadavky; „Odpovědět na inzerát“ = pozvánka na pohovor (`Jobs.invite`) –
##   zaměstnavatel pak v nabídce místa nabídne pohovor s lepší šancí.
## - **Pošta:** `World.mail[pid]` – `World.send_mail(id, from, subject, body)` pro všechny systémy (objednávky, pozvánky, pokuty,
##   upomínky nájmu, akce v obci – háček M5.5, zprávy od dědy).
## - **Web obce** (neutrální název, bez znaku obce): kalendář akcí (`VillageEvents` + státní svátky), otevírací doby míst, drby
##   (anonymní diskuse z událostí a `Reputation.last_offense_text`), úřední deska (`NOTICE_BOARD` – háčky M4.4, M4.7, M7).
## - **eTesty:** rámec cvičných testů (`TESTS`, otázky v `data/testy/<id>.json`, obrazovka `TestUI`); výsledek = událost `etest_done`.
## Události (`World.emit_game_event`): `eshop_order`, `parcel_picked`, `bank_atm`, `fines_paid`, `job_ad_answered`, `etest_done`,
## `pc_game_won`. Zprávy hráči jen přes `World.notify`; akce vrací text výsledku pro stavový řádek obrazovky PC.
## Ukládání `to_dict(pid)` / `from_dict(pid, d)` – klíč `pc` v `SaveGame` (účet, pohyby, pošta, objednávky, drby, testy).
class_name Computer
extends Node3D

# ------------------------------------------------------------------ laditelné hodnoty

const ESHOP_DISCOUNT := 0.05          # e-shop je o 5 % levnější než Potraviny
const SHIPPING_KC := 89               # doprava za objednávku
const COD_KC := 39                    # příplatek za dobírku
const DELIVERY_DAYS := [1, 2]         # balík dorazí za 1–2 herní dny
const DELIVERY_HOUR := 9.0            # … v den doručení od 9:00
const ESHOP_SKIP_TYPES := ["drink", "food", "smoke"]   # potraviny se po síti neposílají
const ESHOP_EXCLUDE := ["rucni_vozik"]                  # velké věci jen v obchodě (vozík se přistavuje, M2.10)
const ESHOP_FIRST_SECTION := "Vybavení a nářadí"        # položky před prvním záhlavím v OFFERS
const MAIL_MAX := 60
const BANK_LOG_MAX := 40
const GOSSIP_MAX := 14
const ORDERS_KEEP := 12               # vyzvednuté objednávky v historii
const ATM_SPOTS := {"obchod": Vector3(2.1, 0.0, 0.6), "urad": Vector3(1.9, 0.0, 0.6)}   # vůči dveřím (osy podle face_yaw místa)
const ATM_R := 2.0
const ATM_AMOUNTS := [200, 500, 1000, 2000, 5000]
const PARCEL_R := 2.2
const TICK_S := 2.0
const DEDA_EVERY_DAYS := 5            # děda píše zhruba jednou za tolik dní
const EVENT_MAIL_DAYS := 3            # pozvánka na akci v obci tolik dní předem (háček M5.5)
const START_BANK := 0                 # nová hra: prázdný účet (peníze jsou v hotovosti)

## Cvičné testy (eTesty): id → [název, soubor s otázkami nebo "" = připravujeme, krok roadmapy].
const TESTS := {
	"pravidla_cvicny": ["Pravidla silničního provozu – cvičný", "res://data/testy/pravidla_cvicny.json", ""],
	"autoskola": ["Autoškola – teorie řidičáku (cvičný)", "res://data/testy/autoskola.json", ""],
	"zbrojni": ["Zbrojní průkaz", "res://data/testy/zbrojni.json", ""],
	"lovecky": ["Lovecký lístek", "res://data/testy/lovecky.json", ""],
	"rybarsky": ["Rybářský lístek", "res://data/testy/rybarsky.json", ""],
	"drony": ["Dron A1/A3 – pilot v otevřené kategorii", "res://data/testy/drony.json", ""],
	"paramotor": ["Létací škola – teorie paramotoru", "res://data/testy/paramotor.json", ""],
	"ul": ["Létací škola – teorie ultralehkého (rogalo)", "res://data/testy/ul.json", ""],
}

## Úřední deska webu obce (vymyšlená oznámení). Klíč `krok` = který krok roadmapy oznámení oživí.
const NOTICE_BOARD := [
	["Pronájem obecního pole", "Obec pronajímá pole na rok za 1 500 Kč. Zájemci na obecním úřadě (úřední hodiny 7–17 h).", "M2.4"],
	["Povolení ke kácení dřevin", "Žádosti o povolení ke kácení mimo les přijímá obecní úřad. (Připravujeme.)", "M4.4"],
	["Prodej a pronájem nemovitostí", "Inzeráty obecních bytů a domů zde brzy zveřejníme. (Připravujeme.)", "M4.7"],
	["Volby do zastupitelstva", "Termín voleb, kandidáti a rozpočet obce – podrobnosti u přepážky úřadu.", ""],
	["Svoz odpadu", "Popelnice se vyvážejí ve čtvrtek. Bioodpad patří do hnědých nádob, ne do potoka!", ""],
]

## Drby z herních událostí (anonymní, „prý“). %s = doplněk (název přestupku, práce…).
const GOSSIP_EVENTS := {
	"offense": ["Prý zase někdo %s. Kam ten svět spěje…", "Včera prý někdo %s. Policajti ho měli jak na talíři.",
		"Nechci nic říkat, ale někdo prý %s. Jméno si domyslete."],
	"busted": ["Policajti prý zase někoho odchytli u silnice. Kdo to asi byl?", "Prý nějakého chytli s promile. Zase!"],
	"job_hired": ["Slyšel jsem, že u %s mají nového. Uvidíme, jak dlouho vydrží.", "Tak prý dělá u %s někdo nový. Snad nebude líný."],
	"job_fired": ["Prý někoho vyhodili z práce. Ráno nevstal, no.", "U %s prý někoho poslali domů nadobro."],
	"rent_overdue": ["Někdo z bytovky prý zase nezaplatil nájem. Majitel zuří.", "Nájem se platí, ne slibuje! Víte, o kom mluvím."],
	"snow_volunteer": ["Někdo nám ráno odházel sníh u zastávky. Díky, dobrá duše!"],
	"fines_paid": ["Prý někdo zaplatil všechny pokuty najednou. To se hned tak nevidí."],
	"drone_crash": ["Někomu prý spadl dron – slyšeli jste to řinčení? Majitel prý poletí další.", "Prý zase něco bzučelo a spadlo do zahrady. Drony, povídám, drony!"],
	"drone_registered": ["Někdo tu prý registroval drona u ÚVL. Už se asi chystá špehovat sousedy."],
}
## Výplň diskuse, když se nic neděje (výběr podle dne).
const GOSSIP_FILLER := [
	"Kdo zase nechal otevřenou branku u hřiště? Pes mi utekl až k rybníku.",
	"Prodám kočárek, skoro nepoužitý. Zn.: dvojčata nečekaná.",
	"V hospodě prý budou mít nový sud. Starý nikdo nevypil, tak ho vypijí štamgasti.",
	"Autobus zase nejel. Nebo jel a já ho neviděl. Každopádně jsem šel pěšky.",
	"Kdo mi sebral hrábě u plotu, ať je vrátí. Vím, že to byl soused. Který, to nevím.",
	"Hledám dobrovolníky na brigádu u hřiště. Pivo zajištěno, práce taky.",
	"Na návsi prý viděli lišku. Nebo psa. Prostě něco zrzavého.",
	"Děkujeme obci za opravenou lavičku. Vydržela celý den.",
	"Kdo ví, kdy bude zase posvícení? Ptám se pro kamaráda.",
	"Internet zase vypadl, když pršelo. Píšu z mobilu u kapličky.",
]
## Zprávy od dědy (humor). [předmět, text]
const DEDA_MAILS := [
	["Jak se píše e-mail", "Ahoj sousede,\nvnuk mi to tady nastavil, tak zkouším, jestli to chodí. JESTLI TO ČTEŠ, ZAMÁVEJ Z OKNA.\nDěda"],
	["Rajčata", "Letos mi rajčata sežraly slimáci. Neměl bys pivo? Nalévá se do misky, slimák se utopí šťastný.\nDěda"],
	["Důležité!!!", "Na internetu psali, že když se pije slivovice na lačno, prodlouží se život. Nebo zkrátí. Už nevím. Ověř to.\nDěda"],
	["Pes", "Můj pes zase utekl k hospodě. Kdybys ho viděl, pošli ho domů. On to zná.\nDěda"],
	["Počasí", "Kosti mě bolí, bude pršet. Na počítači psali, že bude slunečno. Uvidíme, kdo vyhraje.\nDěda"],
	["Zahrádka", "Kdybys chtěl brigádu na zahradách u sousedů, stav se za mnou na lavičce. Platí na ruku a nikdo se neptá.\nDěda"],
]

# ------------------------------------------------------------------ stav

var world: World
var st := {}                         # pid → {bank_log, standing_rent, order_no, gossip, tests, games_won, deda_jd, event_mailed, fines_seen}
var _atms: Array = []                # [{pos, place}]
var _parcels := {}                   # "pid:no" → Node3D
var _parcel_mesh: ArrayMesh
var _catalog: Array = []             # [[sekce, [[id, cena]]]] – z Place.OFFERS
var _t := 0.0
var _quiet := false                  # uvítací pošta bez hlášek v HUD


func setup(w: World) -> void:
	world = w
	name = "Pocitac"
	_parcel_mesh = _make_parcel_mesh()
	for key in ATM_SPOTS:
		var pl: Place = w.places.get(key)
		if pl == null:
			continue
		var b := Basis(Vector3.UP, float(pl.data.get("face_yaw", 0.0)))
		var p: Vector3 = pl.door + b * (ATM_SPOTS[key] as Vector3)
		p.y = w.terrain.height_at(p.x, p.z)
		_build_atm(p, float(pl.data.get("face_yaw", 0.0)))
		_atms.append({"pos": p, "place": key})


## Nový hráč (World.add_player): prázdný účet, uvítací pošta. Načtení hry to přepíše (`from_dict`).
func add_player(pid: int) -> void:
	if st.has(pid):
		return
	st[pid] = _fresh()
	world.mail[pid] = []
	world.orders[pid] = []
	var p: Player = world.players.get(pid)
	if p:
		p.bank = START_BANK
	_welcome(pid)


func _fresh() -> Dictionary:
	return {"bank_log": [], "standing_rent": false, "order_no": 1001, "gossip": [], "tests": {}, "games_won": 0,
		"deda_jd": world.clock.jd() if world.clock else 0, "event_mailed": {},
		"pg_skola": {"zaplaceno": false, "teorie": false, "lety": 0},   # M6.4 létací škola paramotoru
		"ul_skola": {"zaplaceno": false, "teorie": false, "lety": 0}}   # M6.5 létací škola UL (rogalo)


func _welcome(pid: int) -> void:
	_quiet = true
	send_mail(pid, "Moje banka", "Vítejte v internetovém bankovnictví",
		"Dobrý den,\nváš účet je založen. Hotovost vložíte a vyberete v bankomatu u Potravin nebo u obecního úřadu.\n" +
		"Tip: nastavte si trvalý příkaz na nájem, ať nedlužíte.\nVaše Moje banka (smyšlená banka)")
	send_mail(pid, "eŠuplík", "Nakupujte z pohodlí domova",
		"Oblečení, nářadí, semena i udice až ke dveřím! O %d %% levněji než v obchodě, doprava %d Kč.\nVáš eŠuplík" % [
		roundi(ESHOP_DISCOUNT * 100.0), SHIPPING_KC])
	var d: Array = DEDA_MAILS[0]
	send_mail(pid, "Děda Vomáčka", String(d[0]), String(d[1]))
	_quiet = false


func _s(pid: int) -> Dictionary:
	if not st.has(pid):
		st[pid] = _fresh()
	if not world.mail.has(pid):
		world.mail[pid] = []
	if not world.orders.has(pid):
		world.orders[pid] = []
	return st[pid]


# ------------------------------------------------------------------ pošta

## Pošle e-mail hráči (volá i `World.send_mail`). Nový e-mail = krátká zpráva v HUD.
func send_mail(pid: int, sender: String, subject: String, body: String) -> void:
	_s(pid)
	var box: Array = world.mail[pid]
	box.append({"t": world.clock.minutes if world.clock else 0.0, "from": sender, "subject": subject, "body": body, "read": false})
	if box.size() > MAIL_MAX:
		world.mail[pid] = box.slice(box.size() - MAIL_MAX)
	if world.ready_done and not _quiet:
		world.notify(pid, "show_message", ["Nový e-mail: %s – „%s“ (počítač doma)" % [sender, subject], 3.0])


func mails(pid: int) -> Array:
	_s(pid)
	return world.mail[pid]


func unread(pid: int) -> int:
	var n := 0
	for m in mails(pid):
		if not bool(m.get("read", false)):
			n += 1
	return n


func mark_read(pid: int, i: int) -> void:
	var box := mails(pid)
	if i >= 0 and i < box.size():
		box[i]["read"] = true


func delete_read(pid: int) -> int:
	var keep := []
	var box := mails(pid)
	for m in box:
		if not bool(m.get("read", false)):
			keep.append(m)
	var n := box.size() - keep.size()
	world.mail[pid] = keep
	return n


# ------------------------------------------------------------------ banka

func _player(pid: int) -> Player:
	return world.players.get(pid)


func _log(pid: int, text: String, kc: int) -> void:
	var lg: Array = _s(pid)["bank_log"]
	lg.append({"t": world.clock.minutes, "text": text, "kc": kc})
	if lg.size() > BANK_LOG_MAX:
		_s(pid)["bank_log"] = lg.slice(lg.size() - BANK_LOG_MAX)


## Připíše na účet (mzda z práce, prodej v Bazárku, vklad).
func deposit(pid: int, kc: int, text: String) -> void:
	var p := _player(pid)
	if p == null or kc <= 0:
		return
	p.bank += kc
	_log(pid, text, kc)


## Strhne z účtu; false = málo peněz na účtu.
func withdraw_bank(pid: int, kc: int, text: String) -> bool:
	var p := _player(pid)
	if p == null or kc < 0 or p.bank < kc:
		return false
	p.bank -= kc
	_log(pid, text, -kc)
	return true


func bank_log(pid: int) -> Array:
	return _s(pid)["bank_log"]


func standing_rent(pid: int) -> bool:
	return bool(_s(pid).get("standing_rent", false))


## Trvalý příkaz na nájem: zapnutím se hned zaplatí i dluh (když je na účtu dost).
func set_standing_rent(pid: int, on: bool) -> String:
	_s(pid)["standing_rent"] = on
	if not on:
		return "Trvalý příkaz na nájem zrušen – nájem se zase strhává z hotovosti."
	var est: Estate = world.estate
	var msg := "Trvalý příkaz na nájem nastaven – nájem se platí z účtu."
	if est and est.rent_debt(pid) > 0:
		var debt := est.rent_debt(pid)
		if pay_rent(pid, debt, "Dluh na nájmu"):
			est.homes[pid]["debt"] = 0
			world.emit_game_event(pid, "rent_paid", {"kc": debt, "ucet": true})
			msg += " Dluh %s zaplacen." % Bazaar.kc(debt)
		else:
			msg += " Na dluh %s na účtu nestačí." % Bazaar.kc(debt)
	return msg


## Nájem z účtu (volá `Estate._rent_check`, jen s trvalým příkazem). true = zaplaceno.
func pay_rent(pid: int, due: int, what := "Nájem") -> bool:
	if not standing_rent(pid) or due <= 0:
		return false
	var label := world.home_label(pid)
	if not withdraw_bank(pid, due, "%s – %s (trvalý příkaz)" % [what, label]):
		return false
	world.play_sfx(pid, "cash")
	world.notify(pid, "show_message", ["%s (%s): %s z účtu (trvalý příkaz)." % [what, label, Bazaar.kc(due)], 4.0])
	return true


## Nezaplacené pokuty a dluhy z `World.debts` (M4.2). Vrací Kč.
func unpaid_fines(pid: int) -> int:
	return world.debts.total(pid, Debts.FINE_KINDS) if world.debts else 0


## Zaplatí všechny otevřené pokuty z účtu, od nejstarší (M4.2: jednotlivé dluhy v `Debts`).
func pay_fines(pid: int) -> String:
	var due := unpaid_fines(pid)
	if due <= 0:
		return "Žádné nezaplacené pokuty."
	if world.players[pid].bank < due:
		return "Na účtu nemáš dost peněz (pokuty %s)." % Bazaar.kc(due)
	for dl in world.debts.list(pid):
		if Debts.FINE_KINDS.has(dl["kind"]):
			world.debts.pay(pid, String(dl["id"]), int(dl["kc"]), "bank")
	world.play_sfx(pid, "cash")
	world.emit_game_event(pid, "fines_paid", {"kc": due})
	send_mail(pid, "Správní orgán (smyšlený)", "Potvrzení o zaplacení pokut", "Přijali jsme platbu %s. Děkujeme.\n(Zjednodušená herní simulace.)" % Bazaar.kc(due))
	return "Pokuty zaplaceny: %s." % Bazaar.kc(due)


## Bankomat: menu hotovost ↔ účet (E u bankomatu).
func atm_menu(pid: int) -> void:
	var p := _player(pid)
	if p == null:
		return
	var opts := []
	for a in ATM_AMOUNTS:
		opts.append(["Vybrat %s" % Bazaar.kc(a), atm_withdraw.bind(pid, a), p.bank >= a])
	opts.append(["Vybrat vše (%s)" % Bazaar.kc(p.bank), atm_withdraw.bind(pid, p.bank), p.bank > 0])
	for a in [500, 1000, 2000]:
		opts.append(["Vložit %s" % Bazaar.kc(a), atm_deposit.bind(pid, a), p.money >= a])
	opts.append(["Vložit všechnu hotovost (%s)" % Bazaar.kc(p.money), atm_deposit.bind(pid, p.money), p.money > 0])
	world.notify(pid, "open_menu", ["Bankomat – Moje banka", "Na účtu: %s   Hotovost: %s\nVýběr i vklad zdarma. (Smyšlená banka.)" % [
		Bazaar.kc(p.bank), Bazaar.kc(p.money)], opts])


func atm_withdraw(pid: int, kc: int) -> void:
	var p := _player(pid)
	if p == null or kc <= 0 or not withdraw_bank(pid, kc, "Výběr z bankomatu"):
		world.notify(pid, "show_message", ["Na účtu není dost peněz.", 2.5])
		return
	p.money += kc
	world.play_sfx(pid, "cash")
	world.notify(pid, "show_message", ["Vybráno %s. Na účtu zbývá %s." % [Bazaar.kc(kc), Bazaar.kc(p.bank)], 3.0])
	world.emit_game_event(pid, "bank_atm", {"kc": -kc})


func atm_deposit(pid: int, kc: int) -> void:
	var p := _player(pid)
	if p == null or kc <= 0 or p.money < kc:
		world.notify(pid, "show_message", ["Tolik hotovosti nemáš.", 2.5])
		return
	p.money -= kc
	deposit(pid, kc, "Vklad v bankomatu")
	world.play_sfx(pid, "cash")
	world.notify(pid, "show_message", ["Vloženo %s. Na účtu je %s." % [Bazaar.kc(kc), Bazaar.kc(p.bank)], 3.0])
	world.emit_game_event(pid, "bank_atm", {"kc": kc})


# ------------------------------------------------------------------ eŠuplík (e-shop)

## Katalog: [[sekce, [[id, cena v e-shopu]]]] z nabídky Potravin (bez potravin, pití, tabáku a výkupu).
func catalog() -> Array:
	if not _catalog.is_empty():
		return _catalog
	var sec := ESHOP_FIRST_SECTION
	var rows := []
	var out := []
	for o in Place.OFFERS.get("obchod", []):
		var id := String(o[0])
		var mode := String(o[2])
		if mode != "header" and ItemsDB.hidden(id):
			continue     # M4.8: obsah pro dospělé vypnutý – semena nejsou ani v eŠuplíku
		if mode == "header":
			if not rows.is_empty():
				out.append([sec, rows])
			sec = id
			rows = []
			continue
		if mode != "buy" or not ItemsDB.exists(id) or id in ESHOP_EXCLUDE or ItemsDB.type_of(id) in ESHOP_SKIP_TYPES:
			continue
		rows.append([id, eshop_price(int(o[1]))])
	if not rows.is_empty():
		out.append([sec, rows])
	_catalog = out
	return _catalog


static func eshop_price(base: int) -> int:
	return maxi(roundi(float(base) * (1.0 - ESHOP_DISCOUNT)), 1)


func price_of(id: String) -> int:
	for s in catalog():
		for r in s[1]:
			if String(r[0]) == id:
				return int(r[1])
	return -1


## Součet košíku {id: počet} bez dopravy.
func cart_total(cart: Dictionary) -> int:
	var sum := 0
	for id in cart:
		var pr := price_of(String(id))
		if pr > 0:
			sum += pr * int(cart[id])
	return sum


## Objedná košík. `cod` = dobírka (platí se hotově při převzetí). Vrací text výsledku.
func order(pid: int, cart: Dictionary, cod: bool) -> String:
	var p := _player(pid)
	if p == null or cart.is_empty():
		return "Košík je prázdný."
	var items := {}
	for id in cart:
		var need := String(Weapons.PERMIT_ITEMS.get(String(id), ""))
		if need != "" and not world.has_permit(pid, need, p.global_position):
			return "%s se bez zbrojního oprávnění neprodává ani po síti." % ItemsDB.name_of(String(id))
		if price_of(String(id)) > 0 and int(cart[id]) > 0:
			items[String(id)] = int(cart[id])
	if items.is_empty():
		return "Košík je prázdný."
	var total := cart_total(items) + SHIPPING_KC + (COD_KC if cod else 0)
	var s := _s(pid)
	var no := int(s["order_no"])
	if not cod and not withdraw_bank(pid, total, "eŠuplík – objednávka č. %d" % no):
		return "Na účtu nemáš dost peněz (%s, máš %s). Vlož hotovost v bankomatu, nebo zvol dobírku." % [Bazaar.kc(total), Bazaar.kc(p.bank)]
	s["order_no"] = no + 1
	var days: int = randi_range(int(DELIVERY_DAYS[0]), int(DELIVERY_DAYS[1]))
	var o := {"no": no, "items": items, "total": total, "cod": cod, "jd": world.clock.jd() + days, "state": "cesta",
		"t": world.clock.minutes}
	(world.orders[pid] as Array).append(o)
	var lines := []
	for id in items:
		lines.append("  %d× %s" % [int(items[id]), ItemsDB.name_of(String(id))])
	send_mail(pid, "eŠuplík", "Potvrzení objednávky č. %d" % no, "Děkujeme za objednávku!\n%s\nDoprava %s%s\nCelkem %s – %s.\nDoručíme %s ke dveřím (%s).\nVáš eŠuplík" % [
		"\n".join(lines), Bazaar.kc(SHIPPING_KC), ", dobírka %s" % Bazaar.kc(COD_KC) if cod else "", Bazaar.kc(total),
		"zaplatíte hotově při převzetí" if cod else "zaplaceno z účtu", _day_text(int(o["jd"])), world.home_label(pid)])
	world.play_sfx(pid, "cash")
	world.emit_game_event(pid, "eshop_order", {"no": no, "total": total, "cod": cod})
	return "Objednáno (č. %d, %s). Balík dorazí %s po %d:00 ke dveřím domova." % [no, Bazaar.kc(total), _day_text(int(o["jd"])),
		int(DELIVERY_HOUR)]


func orders(pid: int) -> Array:
	_s(pid)
	return world.orders[pid]


func _day_text(jd: int) -> String:
	var diff := jd - world.clock.jd()
	if diff == 0:
		return "dnes"
	if diff == 1:
		return "zítra"
	if diff == 2:
		return "pozítří"
	var d := Clock.from_jdn(jd)
	return "%d. %d." % [int(d["day"]), int(d["month"])]


func _deliver_due(pid: int) -> void:
	var jd := world.clock.jd()
	var h := world.clock.hour()
	for o in orders(pid):
		if String(o["state"]) != "cesta":
			continue
		if jd > int(o["jd"]) or (jd == int(o["jd"]) and h >= DELIVERY_HOUR):
			o["state"] = "doruceno"
			_spawn_parcel(pid, o)
			send_mail(pid, "Doručovací služba (smyšlená)", "Balík č. %d doručen" % int(o["no"]),
				"Váš balík leží u dveří (%s). %s\nNebyli jste doma, tak jsme ho nechali u vchodu. Snad ho nikdo nevezme." % [
				world.home_label(pid), "Dobírka %s se platí při převzetí." % Bazaar.kc(int(o["total"])) if bool(o["cod"]) else ""])
			world.notify(pid, "show_message", ["Balík z eŠuplíku leží u dveří domova (%s)." % world.home_label(pid), 4.0])


## Ladění (F2 → Hráč): objednávky na cestě doručit hned. Vrací počet.
func deliver_now(pid: int) -> int:
	var n := 0
	for o in orders(pid):
		if String(o["state"]) == "cesta":
			o["jd"] = world.clock.jd() - 1
			n += 1
	_deliver_due(pid)
	return n


## Místo pro balík u dveří domova (u bytového domu u vchodu), `i` = pořadí (balíky vedle sebe).
func _parcel_pos(pid: int, i: int) -> Vector3:
	var door := Vector3.INF
	var nrm := Vector3(0, 0, 1)
	var est: Estate = world.estate
	if est:
		var inf := est.info(est.home_estate(pid))
		door = inf.get("door", Vector3.INF)
		nrm = inf.get("normal", nrm)
	if door == Vector3.INF:
		door = (world.places["domov"] as Place).door
	nrm.y = 0.0
	nrm = nrm.normalized() if nrm.length() > 0.01 else Vector3(0, 0, 1)
	var side := nrm.cross(Vector3.UP)
	var p := door + nrm * 1.1 + side * (0.9 + 0.55 * i)
	p.y = world.terrain.height_at(p.x, p.z)
	return p


func _spawn_parcel(pid: int, o: Dictionary) -> void:
	var key := "%d:%d" % [pid, int(o["no"])]
	if _parcels.has(key):
		return
	var n := Node3D.new()
	n.name = "Balik_%d" % int(o["no"])
	add_child(n)
	MeshKit.mesh_instance(n, _parcel_mesh, 80.0)
	n.global_position = _parcel_pos(pid, _parcels.size() % 4)
	n.rotation.y = randf() * TAU
	_parcels[key] = n


func _make_parcel_mesh() -> ArrayMesh:
	var k := MeshKit.new()
	k.box(Vector3(0, 0.17, 0), Vector3(0.5, 0.34, 0.38), Color(0.72, 0.55, 0.33))
	k.box(Vector3(0, 0.345, 0), Vector3(0.52, 0.012, 0.07), Color(0.85, 0.8, 0.6))      # lepicí páska
	k.box(Vector3(0.12, 0.346, 0.1), Vector3(0.16, 0.01, 0.1), Color(0.95, 0.95, 0.95))  # štítek
	return k.commit(MeshKit.vc_material(0.9))


## E u balíku: převzít (dobírka hotově), věci do inventáře.
func pick_parcel(pid: int, no: int) -> void:
	var p := _player(pid)
	if p == null:
		return
	for o in orders(pid):
		if int(o["no"]) != no or String(o["state"]) != "doruceno":
			continue
		if bool(o["cod"]):
			if p.money < int(o["total"]):
				world.notify(pid, "show_message", ["Dobírka %s – tolik hotovosti nemáš (bankomat u Potravin)." % Bazaar.kc(int(o["total"])), 3.5])
				return
			p.money -= int(o["total"])
			world.play_sfx(pid, "cash")
		var items: Dictionary = o["items"]
		var names := []
		for id in items:
			p.add_item(String(id), int(items[id]))
			names.append("%d× %s" % [int(items[id]), ItemsDB.name_of(String(id))])
		o["state"] = "vyzvednuto"
		var key := "%d:%d" % [pid, no]
		var n: Node3D = _parcels.get(key)
		if n and is_instance_valid(n):
			n.queue_free()
		_parcels.erase(key)
		world.notify(pid, "show_message", ["Balík č. %d: %s" % [no, ", ".join(names)], 4.0])
		world.emit_game_event(pid, "parcel_picked", {"no": no})
		_trim_orders(pid)
		return


func _trim_orders(pid: int) -> void:
	var arr: Array = orders(pid)
	var done := 0
	for o in arr:
		if String(o["state"]) == "vyzvednuto":
			done += 1
	while done > ORDERS_KEEP:
		for i in arr.size():
			if String(arr[i]["state"]) == "vyzvednuto":
				arr.remove_at(i)
				done -= 1
				break


# ------------------------------------------------------------------ Bazárek

## Koupě vozidla z nabídky bazaru (platba z účtu, přistaví se domů).
func bazaar_buy(pid: int, key: String) -> String:
	var bz: Bazaar = world.bazaar
	if bz == null or not bz.ok:
		return "Bazárek je mimo provoz."
	var o := bz._offer(key)
	if o.is_empty() or bool(o["sold"]):
		return "Inzerát už neplatí – vozidlo je prodané."
	if not withdraw_bank(pid, int(o["price"]), "Bazárek – %s" % o["name"]):
		return "Na účtu nemáš dost peněz (%s)." % Bazaar.kc(int(o["price"]))
	bz.sold[key] = true
	bz.deliver(pid, o["id"], o["paint"], o["plate"], int(o["year"]), int(o["price"]), float(o["damage"]))
	world.play_sfx(pid, "cash")
	send_mail(pid, "Bazárek", "Kupní smlouva – %s" % o["name"], "Gratulujeme ke koupi (%s, %d, %s). Vozidlo vám přistavíme k domovu (%s).\nBazárek" % [
		o["name"], int(o["year"]), Bazaar.kc(int(o["price"])), world.home_label(pid)])
	return "Koupeno: %s za %s. Stojí u domova (%s)." % [o["name"], Bazaar.kc(int(o["price"])), world.home_label(pid)]


## Vozidla z bazaru, která jdou prodat po síti (kdekoli, jen ne s hráčem za volantem).
func bazaar_sellable(pid: int) -> Array:
	var p := _player(pid)
	var out := []
	if world.traffic == null or p == null:
		return out
	for c in world.traffic.vehicles_of(pid):
		if c.bazaar_price > 0 and c != p.car:
			out.append(c)
	return out


func bazaar_sell(pid: int, c: Car) -> String:
	var bz: Bazaar = world.bazaar
	var p := _player(pid)
	if bz == null or p == null or c == null or not is_instance_valid(c) or c.bazaar_price <= 0 or p.car == c:
		return "Tohle vozidlo prodat nejde."
	var v := bz.sell_value(c)
	var nm := String(c.model.spec.get("name", c.model_id))
	world.traffic.player_vehicles[pid].erase(c)
	c.detach_trailer()
	c.queue_free()
	deposit(pid, v, "Bazárek – prodej %s" % nm)
	return "Prodáno: %s za %s (na účet). Kupec si vůz odveze." % [nm, Bazaar.kc(v)]


## Inzeráty na zvířata (jen čtení; koupě u cedule hospodářství, M2.6). Seed podle týdne.
func animal_ads() -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = 911 + world.clock.jd() / 7
	var out := []
	for sp in FarmSpecs.ORDER:
		if r.randf() < 0.55:
			var inf := FarmSpecs.info(String(sp))
			var young := r.randf() < 0.6
			var pr := int(inf.get("price_young" if young else "price_adult", 0))
			out.append("Prodám %s (%s) – %s. Zn.: jen do dobrých rukou." % [String(inf.get("name", sp)).to_lower(),
				"mládě" if young else "dospělé", Bazaar.kc(roundi(pr * r.randf_range(0.9, 1.15) / 10.0) * 10)])
	return out


# ------------------------------------------------------------------ Práce v kraji

## „Odpovědět na inzerát“: pozvánka na pohovor u zaměstnavatele (Jobs.invite) a e-mail.
func answer_ad(pid: int, job_id: String) -> String:
	var jb: Jobs = world.jobs.get(pid)
	if jb == null:
		return "Práce teď nejde hledat."
	var j := Jobs.job(job_id)
	if j.is_empty():
		return "Inzerát už neplatí."
	var err := jb.invite(job_id)
	if err != "":
		return err
	var misto := String(j.get("misto", ""))
	var pl: Place = world.places.get(misto)
	var where := String(pl.data.get("name", misto)) if pl else ("lavička dědy Vomáčky" if misto == "deda" else misto)
	send_mail(pid, String(j.get("zamestnavatel", "Zaměstnavatel")), "Pozvánka na pohovor – %s" % j.get("nazev", job_id),
		"Dobrý den,\nděkujeme za odpověď na inzerát. Zastavte se do %d dnů za %s (%s) – stačí říct, že jdete na pohovor.\n%s" % [
		Jobs.INVITE_DAYS, j.get("vedouci", "vedoucím"), where, j.get("zamestnavatel", "")])
	world.emit_game_event(pid, "job_ad_answered", {"job": job_id})
	return "Odpověď odeslána – pozvánka na pohovor přišla e-mailem. Zajdi za %s (%s)." % [j.get("vedouci", "vedoucím"), where]


# ------------------------------------------------------------------ web obce

## Kalendář: [[jd, text]] – akce v obci (VillageEvents) a státní svátky na `days` dní dopředu.
func calendar(days := 60) -> Array:
	var out := []
	var jd0 := world.clock.jd()
	var y := world.clock.year()
	for yy in [y, y + 1]:
		var cand := [
			[Clock.jdn(yy, 12, 24), "Vánoce – rozsvícený strom na návsi, Štědrý den (hospoda 10–14 h)"],
			[Clock.easter_jdn(yy) - 50, "Masopust – průvod masek vsí (10–15 h)"],
			[Clock.jdn(yy, 4, 30), "Pálení čarodějnic (od 18 h)"],
			[VillageEvents.hody_sunday(yy) - 1, "Hody – sobota, zábava v hospodě do rána"],
			[VillageEvents.hody_sunday(yy), "Hody – neděle"],
			[Clock.jdn(yy, 12, 31), "Silvestr – ohňostroj o půlnoci"],
		]
		for c in cand:
			var j := int(c[0])
			if j >= jd0 and j <= jd0 + days:
				out.append([j, String(c[1])])
	for j in range(jd0, jd0 + mini(days, 45) + 1):
		var h := Clock.holiday_on(j)
		if h != "":
			out.append([j, "Státní svátek: %s (Potraviny zavřeno)" % h])
	if world.village_events:
		out.append_array(world.village_events.upcoming(days))   # M5.5: taneční zábavy a registrované akce
	out.sort_custom(func(a, b): return int(a[0]) < int(b[0]))
	return out


func date_text(jd: int) -> String:
	var d := Clock.from_jdn(jd)
	return "%s %d. %d." % [String(Clock.WEEKDAYS[jd % 7]), int(d["day"]), int(d["month"])]


## Otevírací doby dnes: [[název, text]].
func opening_hours() -> Array:
	var out := []
	for k in ["obchod", "stavebniny", "hospoda", "urad", "palenice", "sklep", "chata", "statek"]:
		var pl: Place = world.places.get(k)
		if pl:
			out.append([String(pl.data.get("name", k)), pl.hours_text(), pl.is_open(world.clock.hour())])
	return out


## Diskuse (drby): nejnovější nahoře – z událostí, z posledního přestupku (Reputation) a výplň podle dne.
func gossip(pid: int) -> Array:
	var out := []
	var g: Array = _s(pid)["gossip"]
	for i in range(g.size() - 1, -1, -1):
		out.append(g[i])
	var rep: Reputation = world.reputations.get(pid)
	if rep and rep.last_offense_text != "" and world.clock.minutes - rep.last_offense_min < 4320.0:
		out.insert(0, {"t": rep.last_offense_min, "text": "Povídá se, že prý „%s“. Kdo to byl, víme všichni, ale nikdo nic neřekne." % rep.last_offense_text,
			"who": "anonym"})
	var r := RandomNumberGenerator.new()
	r.seed = world.clock.jd() * 31 + 7
	var fill := GOSSIP_FILLER.duplicate()
	for i in 3:
		var k := r.randi_range(0, fill.size() - 1)
		out.append({"t": -1.0, "text": String(fill[k]), "who": _nick(r)})
		fill.remove_at(k)
	return out


static func _nick(r: RandomNumberGenerator) -> String:
	var nicks := ["Soused123", "Zahrádkář", "BabičkaNaNetu", "Anonym", "StarýHasič", "Rybář_ze_vsi", "Maminka3", "Pozorovatel"]
	return String(nicks[r.randi_range(0, nicks.size() - 1)])


func _add_gossip(pid: int, text: String) -> void:
	var g: Array = _s(pid)["gossip"]
	var r := RandomNumberGenerator.new()
	r.seed = int(world.clock.minutes) + g.size()
	g.append({"t": world.clock.minutes, "text": text, "who": _nick(r)})
	if g.size() > GOSSIP_MAX:
		_s(pid)["gossip"] = g.slice(g.size() - GOSSIP_MAX)


# ------------------------------------------------------------------ eTesty a hry

## Otázky testu z `data/testy/<id>.json` ({} = není / připravujeme).
static func load_test(id: String) -> Dictionary:
	var t: Array = TESTS.get(id, [])
	if t.is_empty() or String(t[1]) == "" or not FileAccess.file_exists(String(t[1])):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(String(t[1])))
	return d if d is Dictionary else {}


func record_test(pid: int, id: String, score: int, total: int, passed: bool) -> void:
	var tests: Dictionary = _s(pid)["tests"]
	var e: Dictionary = tests.get(id, {"best": 0, "n": 0, "last": 0, "total": total})
	e["best"] = maxi(int(e.get("best", 0)), score)
	e["last"] = score
	e["total"] = total
	e["n"] = int(e.get("n", 0)) + 1
	tests[id] = e
	world.emit_game_event(pid, "etest_done", {"test": id, "score": score, "total": total, "passed": passed})
	if id == "drony" and passed:      # M6.1: složený test = osvědčení A1/A3 (ÚVL)
		world.drone_pass_test(pid)
	if id == "paramotor" and passed:  # M6.4: složená teorie létací školy paramotoru
		world.pg_theory_passed(pid)
	if id == "ul" and passed:         # M6.5: složená teorie létací školy UL (rogalo)
		world.ul_theory_passed(pid)
	if id == "autoskola" and passed:  # M4.1: složená teorie autoškoly (řidičák = teorie + výcvikové jízdy)
		world.auto_theory_passed(pid)
	if (id == "zbrojni" or id == "lovecky" or id == "rybarsky") and passed and world.gamekeeper:
		world.gamekeeper.test_passed(pid, id)   # M4.6: doklad u myslivce (po zaplaceném kurzu v chatě)


func test_stats(pid: int, id: String) -> Dictionary:
	return (_s(pid)["tests"] as Dictionary).get(id, {})


## Stav výcviku létací školy paramotoru (M6.4): {zaplaceno, teorie, lety}. Ukládá se se `st`.
func pg_school(pid: int) -> Dictionary:
	var s := _s(pid)
	if not s.has("pg_skola"):
		s["pg_skola"] = {"zaplaceno": false, "teorie": false, "lety": 0}
	return s["pg_skola"]


## Stav kurzu autoškoly (M4.1): {zaplaceno, skupina, teorie, jizdy, retest}. Ukládá se se `st`.
func auto_school(pid: int) -> Dictionary:
	var s := _s(pid)
	if not s.has("auto_skola"):
		s["auto_skola"] = {"zaplaceno": false, "skupina": "", "teorie": false, "jizdy": 0, "retest": false}
	return s["auto_skola"]


## Stav výcviku UL školy (M6.5): {zaplaceno, teorie, lety}. Ukládá se se `st`.
func ul_school(pid: int) -> Dictionary:
	var s := _s(pid)
	if not s.has("ul_skola"):
		s["ul_skola"] = {"zaplaceno": false, "teorie": false, "lety": 0}
	return s["ul_skola"]


func game_won(pid: int) -> void:
	_s(pid)["games_won"] = int(_s(pid).get("games_won", 0)) + 1
	world.emit_game_event(pid, "pc_game_won", {"game": "miny"})


func games_won(pid: int) -> int:
	return int(_s(pid).get("games_won", 0))


# ------------------------------------------------------------------ události a čas

## Herní události hráče (World.emit_game_event): drby, výzvy k zaplacení pokuty, upomínky.
func on_event(pid: int, kind: String, data: Dictionary) -> void:
	if not st.has(pid):
		return
	var r := RandomNumberGenerator.new()
	r.seed = int(world.clock.minutes) * 13 + kind.hash()
	var texts: Array = GOSSIP_EVENTS.get(kind, [])
	match kind:
		"offense":
			var o := Law.offense(String(data.get("id", "")))
			var what := String(o.get("drb", String(o.get("nazev", "něco provedl")).to_lower()))   # A4-13: věta do drbů z dat
			if not texts.is_empty():
				_add_gossip(pid, String(texts[r.randi_range(0, texts.size() - 1)]) % what)
			var due_kc := unpaid_fines(pid)
			if due_kc > 0 and String(o.get("misto", "")) != "na_miste":
				send_mail(pid, "Správní orgán (smyšlený)", "Výzva k zaplacení pokuty",
					"Za přestupek „%s“ (%s) evidujeme nezaplacenou pokutu. Celkem k úhradě: %s.\nZaplatit můžete v internetovém bankovnictví (Moje banka → Pokuty) nebo na úřadě.\n(Zjednodušená herní simulace – ověřit aktuální znění zákonů.)" % [
					o.get("nazev", ""), Law.LawRecord._par(o), Bazaar.kc(due_kc)])
		"job_hired", "job_fired":
			var j := Jobs.job(String(data.get("job", "")))
			var emp := String(j.get("zamestnavatel", "nich"))
			if not texts.is_empty():
				var t := String(texts[r.randi_range(0, texts.size() - 1)])
				_add_gossip(pid, t % emp if t.contains("%s") else t)
			if kind == "job_hired":
				send_mail(pid, emp, "Pracovní smlouva – %s" % j.get("nazev", ""),
					"Vítejte v týmu! Směny: %s. Mzda %d Kč/h hrubého.\nVýplatu můžeme posílat na účet – řekněte vedoucímu.\n%s" % [
					Jobs.shifts_text(j), int(j.get("mzda_hod", 0)), emp])
		"rent_overdue":
			if not texts.is_empty():
				_add_gossip(pid, String(texts[r.randi_range(0, texts.size() - 1)]))
			send_mail(pid, "Majitel bytu", "Upomínka – nájem", "Dlužíte na nájmu %s. Nastavte si trvalý příkaz (Moje banka), ať se to neopakuje." % Bazaar.kc(int(data.get("debt", 0))))
		"busted", "snow_volunteer", "fines_paid", "drone_crash", "drone_registered":
			if not texts.is_empty():
				_add_gossip(pid, String(texts[r.randi_range(0, texts.size() - 1)]))


func _process(delta: float) -> void:
	if world == null or world.clock == null or not world.ready_done:
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = TICK_S
	for pid in st:
		_deliver_due(int(pid))
		_daily_mail(int(pid))


## Denní pošta: děda (humor) a pozvánky na akce v obci (háček M5.5 – pozvánky podle vztahů).
func _daily_mail(pid: int) -> void:
	var s := _s(pid)
	var jd := world.clock.jd()
	if world.clock.hour() >= 8.0 and jd - int(s.get("deda_jd", jd)) >= DEDA_EVERY_DAYS:
		s["deda_jd"] = jd
		var d: Array = DEDA_MAILS[posmod(jd / DEDA_EVERY_DAYS, DEDA_MAILS.size())]
		send_mail(pid, "Děda Vomáčka", String(d[0]), String(d[1]))
	var mailed: Dictionary = s["event_mailed"]
	for c in calendar(EVENT_MAIL_DAYS):
		var key := "%d:%s" % [int(c[0]), String(c[1]).get_slice(" –", 0)]
		if String(c[1]).begins_with("Státní svátek") or mailed.has(key):
			continue
		mailed[key] = jd
		send_mail(pid, "Obecní web", "Pozvánka: %s" % String(c[1]).get_slice(" –", 0),
			"Srdečně zveme na akci „%s“ – %s. Více v kalendáři na obecním webu.\nZa obec (neutrální podpis)" % [c[1], date_text(int(c[0]))])
	for k in mailed.keys():
		if int(mailed[k]) < jd - 30:
			mailed.erase(k)


# ------------------------------------------------------------------ svět: bankomaty, balíky

func interactables(pid: int) -> Array:
	var p := _player(pid)
	var out := []
	if p == null or p.inside != "":
		return out
	for a in _atms:
		out.append({"pos": (a["pos"] as Vector3) + Vector3(0, 1.0, 0), "r": ATM_R, "kind": "custom", "text": "Bankomat (Moje banka)",
			"action": atm_menu})
	for o in orders(pid):
		if String(o["state"]) != "doruceno":
			continue
		var n: Node3D = _parcels.get("%d:%d" % [pid, int(o["no"])])
		if n and is_instance_valid(n):
			var no := int(o["no"])
			out.append({"pos": n.global_position + Vector3(0, 0.5, 0), "r": PARCEL_R, "kind": "custom",
				"text": "Balík z eŠuplíku č. %d – vybrat%s" % [no, " (dobírka %s)" % Bazaar.kc(int(o["total"])) if bool(o["cod"]) else ""],
				"action": func(id: int): pick_parcel(id, no)})
	return out


func _build_atm(pos: Vector3, face: float) -> void:
	var n := Node3D.new()
	n.name = "Bankomat"
	add_child(n)
	var k := MeshKit.new()
	k.box(Vector3(0, 0.8, 0), Vector3(0.7, 1.6, 0.5), Color(0.25, 0.3, 0.38))              # skříň
	k.box(Vector3(0, 1.72, 0.02), Vector3(0.74, 0.24, 0.56), Color(0.15, 0.45, 0.3))       # zelený štít (bez loga)
	k.box(Vector3(0, 1.22, 0.255), Vector3(0.36, 0.26, 0.02), Color(0.2, 0.55, 0.75))      # displej
	k.box(Vector3(0, 0.98, 0.27), Vector3(0.3, 0.14, 0.06), Color(0.55, 0.55, 0.58), Vector3(-0.4, 0, 0))   # klávesnice
	k.box(Vector3(0.22, 1.0, 0.26), Vector3(0.12, 0.02, 0.02), Color(0.05, 0.05, 0.05))    # otvor na kartu
	k.box(Vector3(0, 0.78, 0.26), Vector3(0.34, 0.03, 0.02), Color(0.05, 0.05, 0.05))      # výdej bankovek
	MeshKit.mesh_instance(n, k.commit(MeshKit.vc_material(0.5, 0.2)), 150.0)
	var lb := Label3D.new()
	lb.text = "BANKOMAT"
	lb.font_size = 40
	lb.pixel_size = 0.004
	lb.position = Vector3(0, 1.72, 0.305)
	lb.modulate = Color(0.95, 0.95, 0.9)
	lb.visibility_range_end = 40.0
	n.add_child(lb)
	n.global_position = pos
	n.rotation.y = face


# ------------------------------------------------------------------ deník a ukládání

## Řádek do deníku J (statistika).
func journal_text(pid: int) -> String:
	var p := _player(pid)
	if p == null:
		return ""
	var s := "  Na účtu %s." % Bazaar.kc(p.bank)
	var n := unread(pid)
	if n > 0:
		s += "  Nepřečtené e-maily: %d (počítač doma)." % n
	var waiting := 0
	for o in orders(pid):
		if String(o["state"]) != "vyzvednuto":
			waiting += 1
	if waiting > 0:
		s += "  Objednávky na cestě / u dveří: %d." % waiting
	return s


func to_dict(pid: int) -> Dictionary:
	var p := _player(pid)
	var s := _s(pid)
	return {"bank": p.bank if p else 0, "bank_log": s["bank_log"], "standing_rent": s["standing_rent"], "order_no": s["order_no"],
		"gossip": s["gossip"], "tests": s["tests"], "games_won": s["games_won"], "deda_jd": s["deda_jd"],
		"event_mailed": s["event_mailed"], "mail": world.mail.get(pid, []), "orders": world.orders.get(pid, []),
		"pg_skola": pg_school(pid), "ul_skola": ul_school(pid), "auto_skola": auto_school(pid)}


## Načtení (starý save bez klíče `pc` = prázdný účet, uvítací pošta, žádné objednávky).
func from_dict(pid: int, d: Dictionary) -> void:
	for key in _parcels.keys():
		if String(key).begins_with("%d:" % pid):
			var n: Node3D = _parcels[key]
			if is_instance_valid(n):
				n.queue_free()
			_parcels.erase(key)
	st[pid] = _fresh()
	world.mail[pid] = []
	world.orders[pid] = []
	var p := _player(pid)
	if d.is_empty():
		if p:
			p.bank = START_BANK
		_welcome(pid)
		return
	if p:
		p.bank = int(d.get("bank", START_BANK))
	var s: Dictionary = st[pid]
	s["bank_log"] = (d.get("bank_log", []) as Array).duplicate(true)
	s["standing_rent"] = bool(d.get("standing_rent", false))
	s["order_no"] = int(d.get("order_no", 1001))
	s["gossip"] = (d.get("gossip", []) as Array).duplicate(true)
	s["tests"] = (d.get("tests", {}) as Dictionary).duplicate(true)
	s["games_won"] = int(d.get("games_won", 0))
	s["deda_jd"] = int(d.get("deda_jd", world.clock.jd()))
	s["event_mailed"] = (d.get("event_mailed", {}) as Dictionary).duplicate(true)
	var sk: Dictionary = d.get("pg_skola", {})          # M6.4: starý save bez klíče = žádný výcvik
	s["pg_skola"] = {"zaplaceno": bool(sk.get("zaplaceno", false)), "teorie": bool(sk.get("teorie", false)),
		"lety": int(sk.get("lety", 0))}
	var au: Dictionary = d.get("auto_skola", {})        # M4.1: starý save bez klíče = žádný kurz autoškoly
	s["auto_skola"] = {"zaplaceno": bool(au.get("zaplaceno", false)), "skupina": String(au.get("skupina", "")),
		"teorie": bool(au.get("teorie", false)), "jizdy": int(au.get("jizdy", 0)), "retest": bool(au.get("retest", false))}
	var su: Dictionary = d.get("ul_skola", {})          # M6.5: starý save bez klíče = žádný výcvik
	s["ul_skola"] = {"zaplaceno": bool(su.get("zaplaceno", false)), "teorie": bool(su.get("teorie", false)),
		"lety": int(su.get("lety", 0))}
	for m in d.get("mail", []):
		var md: Dictionary = m
		(world.mail[pid] as Array).append({"t": float(md.get("t", 0.0)), "from": String(md.get("from", "")),
			"subject": String(md.get("subject", "")), "body": String(md.get("body", "")), "read": bool(md.get("read", false))})
	for o in d.get("orders", []):
		var od: Dictionary = o
		var items := {}
		var its: Dictionary = od.get("items", {})
		for id in its:
			if ItemsDB.exists(String(id)):
				items[String(id)] = int(its[id])
		var e := {"no": int(od.get("no", 0)), "items": items, "total": int(od.get("total", 0)), "cod": bool(od.get("cod", false)),
			"jd": int(od.get("jd", 0)), "state": String(od.get("state", "cesta")), "t": float(od.get("t", 0.0))}
		(world.orders[pid] as Array).append(e)
		if e["state"] == "doruceno":
			_spawn_parcel(pid, e)
