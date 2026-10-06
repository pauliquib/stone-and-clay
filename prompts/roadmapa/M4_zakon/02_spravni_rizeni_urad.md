# M4.2 – Správní řízení na úřadě: pokuty, splatnost, dluhy a exekuce, žádosti

> Roadmapa „Život na vsi“ · **M4 Zákon a společnost** · krok 2/8
> Předpoklady: M0.5, M4.1 (`Permits.revoke/restore`), M3.4 (banka, pošta), M1.5 (interiér úřadu)
> Navazují: M4.3 (peněžitý trest soudu = dluh), M4.4 (žádost o povolení ke kácení), **M4.7 (hypotéka používá `Debts`)**
> Stav kódu ověřen po vlně 0 (commit `357f7eb`). Když grep ukáže něco jiného, věř kódu a rozdíl zapiš do logu.

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md`
2. `docs/VIZE_A_ROADMAPA.md` – kap. 4.4
3. `scripts/law.gd` (celý, 107 ř.) + `data/zakon.json` (pole `misto`, `blokova`)
4. `scripts/world.gd` – výřezy: `commit_offense` (~ř. 1589), `_on_busted` (~1553), `skip_time` (~1664), `send_mail` (~1469)
5. `scripts/computer.gd` – `unpaid_fines`, `pay_fines` (~ř. 290–310), `withdraw_bank`, `send_mail`, `NOTICE_BOARD`;
   `scripts/computer_ui.gd` – stránka banky (grep `M4.2`)
6. `scripts/estate.gd` – `rent_debt` / `pay_rent_debt` (~ř. 496) – dnešní jediný „dluh“; `scripts/jobs.gd` – `pay_bank`, výplata
7. `scripts/place.gd` – `HOURS`, `WEEK_HOURS["urad"]`, `CLOSED_ON_HOLIDAY`; `scripts/local_client.gd` – `open_place_menu`
8. `scripts/interior_menu.gd` – objekt `"mailbox"` (~ř. 66); `scripts/interior_gen.gd` – schránky v bytovém domě (~ř. 416)
9. `scripts/save_game.gd` – klíč `law` (ř. ~138 a ~375)

## 1. Proč
Dnes se pokuta prostě strhne. Realita: část přestupků se řeší **na místě** (bloková pokuta), závažnější
**ve správním řízení** (příkaz poštou, lhůta, odpor, nezaplacení → exekuce). Úřad je navíc místo pro žádosti
(povolení ke kácení, pronájem pole, vrácení řidičáku).

## 2. Co už v kódu je
- `LawRecord.commit` (`law.gd`) **strhne pokutu hned** z hotovosti (`pl.money`), zbytek přičte do `unpaid_fines`.
  Pole `misto` (`na_miste` 10×, `spravni_rizeni` 38×, `soud` 6×) ani `blokova` (jen 2 řádky) **nikdo nečte**.
- `records` = `{t, id, pokuta, body, zaplaceno, trestny_cin}` (max `MAX_RECORDS` 200); ukládá se pod klíčem `law`
  (`to_dict`: `points`, `records`, `unpaid`, `last`, `decay`).
- `Computer.pay_fines(pid)` zaplatí z účtu **všechno najednou** a označí všechny záznamy jako zaplacené.
- Úřad má po vlně 0 úřední dny: `WEEK_HOURS["urad"]` Po a St 7–17, Út a Čt 8–14, Pá 8–12, víkend a svátky zavřeno;
  zavřené místo nenabízí služby (`World.place_shut`).
- **Schránka:** v bytovém domě je interiérový objekt `"mailbox"` („Poštovní schránky“ – jen hláška s letáky),
  na ulicích jsou rekvizity schránek (`Prop` / `PropModels.mailbox`). **U rodinného domu schránka není.**
- Dluh na nájmu: `Estate.rent_debt / pay_rent_debt` – samostatný mechanismus bez lhůt a exekuce.
- `_on_busted` dnes dělá najednou: pokutu, odtah auta, záchytku (nad 1 ‰) – M4.3 ho rozdělí; ty jen napoj platby.

## 3. Návrh
### 3.1 Společný mechanismus dluhů `scripts/debts.gd` (`class_name Debts`, jedna instance `World.debts`)
Zaveď ho tady – **M4.3 (peněžitý trest), M4.7 (hypotéka, splátky) a případně nájem ho jen použijí**.
- Položka: `{id, pid, kind ("pokuta" | "naklady_rizeni" | "trest" | "hypoteka" | "najem" …), text, kc, paid, due_jd,
  stage ("splatne" | "upominka" | "exekuce" | "zaplaceno"), creditor, ref (id záznamu v Law / smlouvě)}`.
- API: `add(pid, kind, kc, due_jd, text, ref := "") -> String`, `pay(pid, debt_id, kc, from := "cash" | "bank") -> int`,
  `list(pid, open_only := true)`, `total(pid)`, `daily(pid, jd)` (denní krok – volá World při změně dne / `skip_time`),
  `to_dict(pid)` / `from_dict(pid, d)` (nový klíč `debts` v `SaveGame`).
- **Denní krok:** po splatnosti → upomínka (+ náklady řízení, laditelné `REMINDER_FEE` 1 000 Kč, dopis), po
  `ENFORCE_DAYS` (30) → **exekuce**: stáhnout z účtu (`Computer.withdraw_bank`), pak srážka z výplaty (háček v `Jobs` –
  výplata se nejdřív pošle na dluh), exekutorské náklady (min. 3 000 Kč, orientačně), pověst −5; když nic není, „sepsání“
  věci: vozidlo hráče s nejvyšší bazarovou cenou (auta hráče = `Car.owner_id == id`, `traffic.car_of(id)`, `World.spawn_vehicle`; ověř grepem, jestli jich hráč může mít víc, a jak je ukládá `SaveGame`).
- `skip_time` přes měsíce (vězení M4.3, F2 → Datum) musí dluhy dohnat po dnech, ne jedním skokem; drž výkon (jen čísla).

### 3.2 Tok přestupku – přepis `LawRecord.commit` + `World.commit_offense`
- `commit` **přestane strhávat peníze**: jen zapíše záznam, body, zákaz a vrátí `misto`. Platbu řeší `World.commit_offense`:
  - `na_miste`: policista (nebo kdo přestupek zjistil) nabídne **blokovou pokutu** (`blokova`, jinak dolní mez `pokuta`)
    přes `notify(id, "open_menu", …)`: „Zaplatit hned“ (hotovost) / „Nesouhlasím – správní řízení“. Bez hotovosti →
    „bloková pokuta na místě nezaplacená“ = `Debts.add(…, splatnost 15 dní)` (složenka).
    Policejní toky, které zprávu tlumí (`quiet`), ať dostanou nabídku taky – ověř `_on_busted` a `breath_test`.
  - `spravni_rizeni`: za 1–3 herní dny přijde **příkaz** (`World.send_mail` + papírový dopis do schránky, viz 3.4)
    s pokutou z rozmezí (závažnost, opakování z `records`) + případný zákaz činnosti. Splatnost **15 dní**, do **8 dní**
    lze podat **odpor** (úřad / PC) → **ústní jednání** na úřadě v daný den a hodinu (jen v úředních dnech).
    Minihra argumentů: „přiznat a omluvit se“ −20 %, „zapírat“ bez důkazů 30 % šance na zastavení, jinak +20 %.
    Nepřijde → rozhodnutí v nepřítomnosti.
  - `soud`: jen záznam + událost pro M4.3 (dnes stejně jako teď – pokuta → `Debts`, dokud M4.3 nezavede soud).
- **Rozšíř `records`** o `{misto, stav ("na_miste" | "prikaz" | "odpor" | "jednani" | "pravomocne" | "zastaveno"),
  debt_id, spis (text), svedci: []}` – staré klíče zachovej (`_record_clean` v `jobs.gd` čte `trestny_cin`).
- **Migrace klíče `law`:** `from_dict` doplní chybějící pole; starý `unpaid` > 0 → jeden dluh „Nezaplacené pokuty (starší)“
  se splatností 15 dní od načtení, `unpaid_fines` pak počítej z `Debts` (nebo ho drž jako součet – hlavně ať
  `Computer.unpaid_fines` a stránka banky ukazují pravdu).
- `Computer.pay_fines` → platba **jednotlivých** dluhů (seznam se splatností), i trvalé „zaplatit vše“ ponech.

### 3.3 Úřad – nabídka (E u úřednice, jen v úředních hodinách)
„Zaplatit pokutu / dluh“ (seznam z `Debts`), „Podat odpor“, „Nahlédnout do spisu“ (text záznamu),
„Žádost o vrácení řidičského oprávnění“ (po uplynutí zákazu + přezkoušení v autoškole M4.1 → `permits.restore`,
poplatek), „Pronájem pole“ (M2.4 – už je, ponech), „Žádost o povolení ke kácení“ (připrav rámec – formulář, poplatek,
lhůta; dokončí M4.4), „Ohlášení chovu“ (M2.6 háček). Správní poplatky orientačně v datech (vydání ŘP 50 Kč,
přezkoušení 700 Kč – „ověřit“).

### 3.4 Schránka a dopisy
- **Byt:** objekt `"mailbox"` v přízemí bytového domu hráče (`interior_menu.gd`) → E = „Vybrat poštu“, když jsou dopisy
  (jinak dnešní hláška s letáky).
- **Rodinný dům:** nová schránka u dveří domova (`World.lot_door()` / dveře domova, `PropModels.mailbox` už existuje),
  stěhuje se s domovem (`World.apply_home`). E = vybrat poštu.
- Dopisy = `World.mail` záznamy s příznakem `paper: true` (nepřečtený papírový dopis), HUD upozornění „Ve schránce máš dopis“.

### 3.5 Deník
Deník J → „Úřední záznamy“: každá věc se stavem (na místě / příkaz / odpor / jednání / splatné do / zaplaceno / exekuce)
a otevřené dluhy z `Debts` (vč. nájmu, později hypotéky).

## 4. Minimum
`Debts` s upomínkou a exekucí z účtu, přepis `commit` (bez okamžitého stržení) s migrací save, bloková pokuta na místě,
příkaz poštou se lhůtou, placení jednotlivě na úřadě / PC, deník. Odpor + jednání, schránka u domu a sepsání věci můžou
do otevřených bodů.

## 5. Hotovo, když
- Přestupky se dělí na blokové a správní řízení; příkaz přijde poštou, platí se na úřadě nebo přes banku; odpor vede
  k jednání; nezaplacení k upomínce a exekuci; úřad vyřizuje vrácení řidičáku; `Debts` má API, které M4.3 a M4.7
  použijí bez úprav.

## 6. Návrh checklistu ručních testů
1. Rychlost v obci → policista: bloková pokuta → zaplatit hned (hotovost klesne).
2. Bez hotovosti → složenka v `Debts`, deník ukazuje splatnost.
3. Řízení pod vlivem (do 1 ‰) → za 1–3 dny dopis ve schránce + e-mail: příkaz, lhůta.
4. Podej odpor na úřadě → termín jednání (úřední den) → přijď → argument → výsledek.
5. Nech pokutu nezaplacenou 15 dní (F2 → Datum) → upomínka; +30 dní → exekuce z účtu.
6. Úřad v sobotu → zavřeno, nabídka se neotevře.
7. Po zákazu řízení: přezkoušení v autoškole → úřad → vrácení řidičáku.
8. Starý save s nezaplacenými pokutami → jeden dluh „starší“, banka ukazuje stejnou částku.
9. F5/F9 → řízení, lhůty, dluhy a dopisy zůstanou.

## 7. Závěr
README (Systémy → Úřad, Dluhy), `00_SPOLECNE.md` (mapa kódu – `Debts`), VIZE odškrtnout, roadmapa README, PROJECT_LOG,
commit „M4.2 Správní řízení: …“, checklist a čekat.
