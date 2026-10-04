# M3.4 – Počítač doma: e-shop, bazar, práce, banka, web obce, e-testy

> Roadmapa „Život na vsi“ · **M3 Práce a počítače** · krok 4/4
> Předpoklady: M1.4 (stůl s PC v domově), M3.1 (práce), M1.6 (bazar) · Navazují: M4.1 (e-test autoškoly), M4.2 (platba pokut), M4.6 (e-testy lovecké / rybářské, povolenky), M5.5 (pozvánky na události), M6.1 (test pro drony)

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md`
2. `docs/VIZE_A_ROADMAPA.md` – kap. 4.3 „Počítače (13)“
3. `scripts/hud.gd` – `open_menu`, `_menu`, `_set_menu_mode` (jak se staví UI panely kódem), `_journal` (RichTextLabel)
4. `scripts/interior.gd` + domov (M1.4; od M1.7 byt v bytovém domě – `scripts/estate.gd`, `World.home_door()`) – objekt PC
   (pokud byt PC nemá, přidej stůl s PC do interiéru bytu i usedlosti)
5. `scripts/jobs.gd` (M3.1), bazar z M1.6 (grep `bazar`), `scripts/law.gd` (nezaplacené pokuty)
6. `scripts/priroda/village_events.gd` – `EVENTS`, `names_text` (kalendář akcí pro web obce)
7. `scripts/world.gd` – `buy`, peníze hráče

## 1. Proč
Uživatel chce počítače. PC je **brána** k věcem, které se na vsi dnes dělají přes internet: nákupy, bazar,
hledání práce, bankovnictví, úřad, testy – a zdroj humoru (drby na webu obce).

## 2. Návrh
### 2.1 Obrazovka PC
- E u stolu s PC → hráč si sedne (póza sezení), kamera se přiblíží k monitoru (nebo rovnou UI přes celou obrazovku),
  myš se uvolní. Nový `scripts/computer_ui.gd` (`class_name ComputerUI extends Control`): stylizovaný „starý OS“
  (šedé okno, modrý pruh s titulkem, ikony na ploše: „Prohlížeč“, „Pošta“, „Banka“, „Hry“), Esc = zavřít.
- Vše **česky** a **smyšlené** (žádné reálné weby, loga a názvy firem). Prohlížeč má záložky / oblíbené:

| Web (smyšlený) | Funkce |
|---|---|
| **eŠuplík** (e-shop) | nákup: oblečení (M2.3), nástroje, semena, sazenice, vybavení (udice, luk…), díly; **doručení balíkem** za 1–2 herní dny ke dveřím domova (`Estate` – u bytového domu do schránky / k vchodu; balík – objekt, E = vybrat) |
| **Bazárek** | bazar vozidel z M1.6 (stejná nabídka, prodej vlastního vozidla), inzeráty na zvířata (M2.6) |
| **Práce v kraji** | nabídky prací z `data/prace.json` s požadavky; „Odpovědět na inzerát“ = pozvání na pohovor (zaměstnavatel v nabídce místa pak nabídne přijetí) |
| **Moje banka** | účet: zůstatek, pohyby, **trvalý příkaz na nájem bytu** (`Estate` – dluh a upomínky z M1.7); hotovost ↔ účet jen u bankomatu (nový objekt u obchodu / úřadu); výplata z práce na účet (přepínač v práci); platba pokut (M4.2 – teď zobrazit nezaplacené pokuty z `Law` a zaplatit) |
| **Web obce** (neutrální název, **bez znaku obce**) | kalendář akcí (`VillageEvents` + budoucí M5.5), otevírací doby míst, **drby** (anonymní „diskuse“ – generované z `Reputation.last_offense_text` a událostí: „Prý zase někdo jezdil v noci opilý…“), úřední deska (pronájem pole M2.4, povolení ke kácení M4.4; později inzeráty nemovitostí M4.7 a volby M7 – nech háček) |
| **Pošta** (e-mail) | zprávy: potvrzení objednávek, pozvánky na pohovor, výzvy k zaplacení pokuty, pozvánky na akce (M5.5), zpráva od dědy (humor) |
| **eTesty** | cvičné testy (autoškola, zbrojní, lovecké, rybářské, drony) – **jen rámec**: `TestUI` s otázkami z `data/testy/<druh>.json` (otázka, 3 odpovědi, správná); teď jeden ukázkový test „Pravidla silničního provozu – cvičný“ s 10 obecnými otázkami (vlastní formulace, **nekopírovat** oficiální testy) |
| **Hry** | jedna jednoduchá minihra (Miny / Had / Pasiáns – napiš vlastní, malou) |

### 2.2 Data a stav
- `Player.bank := 0` (účet), `World.mail[id]` (seznam zpráv), `World.orders[id]` (objednávky s dnem doručení),
  vše ukládat.
- `World.send_mail(id, from, subject, body)` – ostatní systémy (práce, zákon, události) posílají poštu tudy.
- Nákup v e-shopu: ceny jako v obchodě −5 %, doprava 89 Kč, platba z účtu.

## 3. Minimum
PC UI s prohlížečem: e-shop s doručením, práce, banka (zůstatek + pokuty), web obce s drby, pošta. eTesty a Hry jako rámec.

## 4. Hotovo, když
- U PC v domově jde nakoupit s doručením, prohlížet a prodávat v bazaru, najít práci, platit, číst drby a poštu; vše se ukládá.

## 5. Návrh checklistu ručních testů
1. Domov → PC → E → plocha „starého OS“; Esc zavře.
2. eŠuplík → kup pláštěnku a semena → druhý den balík u dveří, E vybrat.
3. Bazárek → nabídka vozidel, koupě / prodej.
4. Práce v kraji → odpověz na inzerát → u zaměstnavatele nabídka přijetí.
5. Banka → pokuta z dřívějška → zaplatit, zmizí z deníku; bankomat u obchodu → vybrat hotovost.
6. Web obce → akce (hody, Vánoce…), drby o tvých přestupcích.
7. Pošta → potvrzení objednávky, pozvánka.
8. eTesty → cvičný test 10 otázek, výsledek.
9. F5/F9 → pošta, objednávky, účet zůstanou.

## 6. Závěr
README (Systémy → Počítač), VIZE odškrtnout, roadmapa README, PROJECT_LOG, deník AI, commit „M3.4 Počítač: …“, checklist a čekat.
