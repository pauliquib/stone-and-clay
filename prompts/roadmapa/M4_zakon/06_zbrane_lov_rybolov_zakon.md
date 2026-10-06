# M4.6 – Zbraně, lov a rybolov podle zákona: doklady, hajný, rybářská stráž, kontroly

> Roadmapa „Život na vsi“ · **M4 Zákon a společnost** · krok 6/8
> Předpoklady: M2.7, M2.8, M2.9, M2.10, M4.1 (rozšířený `Permits`), M4.3 (`criminal_record`), **M4.4 (`World.witness_check`,
> společný registr nenahlášených činů – bez nich nezačínej)**, M3.4 (eTesty) · Navazují: V2
> Stav kódu ověřen po vlně 0 (commit `357f7eb`). Když grep ukáže něco jiného, věř kódu a rozdíl zapiš do logu.

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md`
2. `docs/VIZE_A_ROADMAPA.md` – kap. 4.2 „Lovecké zbraně“, „Kdo tě může chytit“, „Přeprava úlovku“ a kap. 4.4 „Zbraně, lov a rybolov“
3. `scripts/permits.gd` (po M4.1), `scripts/law.gd` (`criminal_record` z M4.3), `data/zakon.json`, `data/lov.json` (M2.9),
   `data/ryby.json` (M2.7)
4. `scripts/weapons.gd` (M2.8 – `_witness`, `_cooldown_ok`, ~ř. 730–860), `scripts/hunting.gd` (`is_legal_hunt` ~ř. 173,
   `doklad_puvod`, sražená zvěř ~ř. 304), `scripts/fishing.gd` (~ř. 587), `scripts/cargo.gd` (`cargo_seen`, kufr), `scripts/carcass.gd`
5. `scripts/police.gd` – kontrola (`_plan`, `_stopping`, `set_checkpoint`)
6. Myslivec = obsluha místa `chata` (Franta, `Place` keeper – grep `myslivec`); `scripts/npc.gd` / `villager.gd` – pohyb NPC po trase
7. `scripts/computer.gd` – `TESTS` (placeholdery `zbrojni`, `lovecky`, `rybarsky` **bez JSON**), `record_test`;
   `scripts/test_ui.gd` (formát, `pocet`, `prah_pct`); `World.cheat` – větev `"zbrojni"` (~ř. 3374)

## 0b. Co už v kódu je
- Legalita už se ptá na doklady přes `World.has_permit(id, kind, pos)`: `zbrojni` (weapons, hunting, nákup pušky
  ~ř. 2855), `lovecky_listek`, `povolenka_lov` (hunting), `rybarsky_listek`, `povolenka_rybolov` (fishing). Dnes je drží
  **jen cheat** F2 → Hráč „zbrojni“ (`_cheat_permits` zapne zbrojní + lovecký + povolenku najednou). Názvy druhů nech –
  M4.1 je přidal do `Permits.KINDS`, ty je jen začneš udělovat.
- eTesty `zbrojni`, `lovecky`, `rybarsky` jsou v `Computer.TESTS` s prázdnou cestou → vytvoř `data/testy/zbrojni.json`,
  `lovecky.json`, `rybarsky.json` (vlastní otázky, ne oficiální testy; `pocet`, `prah_pct`, `zdroj` + „ověřit“) a napoj
  výsledek v `record_test` (vzor `drony`).
- Svědci: po M4.4 `World.witness_check`; nenahlášené činy ve společném registru (ne `Law.hidden` ani jen `Forestry.unreported`).

## 1. Proč
Uzavírá lov a rybaření: **legální cesta** (doklady, kurzy, povolenky) a **nelegální cesta** s reálným
rizikem dopadení (hajný, rybářská stráž, policie, svědci). Rozhodnutí uživatele: pytláctví je záměrně
možné, ale zakázané a riskantní; hra nic nezakazuje, jen nese důsledky.

## 2. Co udělat
### 2.1 Doklady a jak je získat (vše orientačně, v datech „ověřit“)
| Doklad | Jak | Cena (orient.) | Podmínky |
|---|---|---|---|
| **Zbrojní oprávnění** (nový zákon o zbraních č. 90/2024 Sb. od 2026) | teorie eTest (PC, 30 vlastních otázek) + praktická zkouška na střelnici (M2.8 – 5 ran na 25 m, bezpečná manipulace) + lékařský posudek (návštěva lékaře – nabídka na úřadě „posudek“ 1 500 Kč) | ~4 000 Kč | čistý rejstřík trestů (`criminal_record`, M4.3), bezúhonnost; odebrání: trestný čin, alkohol se zbraní |
| **Lovecký lístek** | kurz myslivosti (u myslivce – 3 večery v chatě = 3 krátké úkoly: poznávání zvěře, bezpečnost, péče o revír) + zkouška (eTest) | ~5 000 Kč | – |
| **Povolenka k lovu** | od mysliveckého spolku (myslivec) na měsíc, určuje druhy a počty (1 srnec, 2 divočáci…) | 1 500 Kč / měsíc | lovecký lístek; hlášení úlovku (E u myslivce do 24 h → `doklad_puvod`) |
| **Rybářský lístek** | kurz + test (eTest 20 otázek) | ~1 000 Kč | – |
| **Povolenka k rybolovu** | rybářský spolek (nabídka v hospodě / na PC), roční, se **záznamem úlovků** (ponechané ryby se zapisují automaticky) | 1 800 Kč / rok | rybářský lístek |
Doklady uděluj přes `permits.grant(pid, kind, no, "", valid_until)` (povolenky s platností – `valid_until`), volání
`has_permit(...)` v M2.7–M2.9 se nemění. Cheat z M2.8 ponech jen v F2.

### 2.2 Hajný / myslivecká stráž (NPC)
- Nový `scripts/gamekeeper.gd` (`class_name Gamekeeper`; zaregistruj ho jako zdroj svědků `World.add_witness_source`): 1 hajný (smyšlené jméno, povaha přísná) – obchůzka lesů
  po trasách (lesní cesty z grafu / náhodné body `Fauna.random_point(..., "forest")`), **hlavně za šera a v noci**
  (18–23 h, 4–7 h), přes den u chaty / krmelce. Jezdí i terénním autem (pickup M1.6) mezi lesy.
- **Vnímání:** slyší výstřel (M2.8 – do 1 500 m → jde k místu výstřelu), vidí hráče se zbraní / úlovkem v lese
  (zrak jako `witness_check`), najde krvavou stopu / vývrhy / nenahlášené činy v okolí (společný registr z M4.4 – `pending_offenses` / `commit_pending`).
- **Kontrola:** přijde k hráči („Dobrý večer, myslivecká stráž. Doklady prosím.“) → zkontroluje zbraň, zbrojní
  oprávnění, lovecký lístek, povolenku, úlovek (legální?). Hráč může: **ukázat doklady**, **zapírat**, **utéct**
  (hajný volá policii, `wanted_until`; poznal-li hráče → přestupek i tak).
- Při pytláctví: zabavení zbraně (i luku/kuše) a úlovku, `commit_offense("pytlactvi")` (trestný čin → soud M4.3),
  ztráta zbrojního oprávnění a loveckého lístku, pověst −20, respekt `zemedelci` −20, karma −5.

### 2.3 Rybářská stráž
- 1 NPC, obchází rybníky a potoky (úseky z `Water`), hlavně o víkendech a ráno. Kontrola: rybářský lístek, povolenka,
  úlovky (míra, hájení z `data/ryby.json`). Bez dokladů → rybářské pytláctví (přestupek / trestný čin podle hodnoty),
  zabavení udice a úlovku.

### 2.4 Policie a svědci
- Policejní kontrola (`police.gd`): kromě řidičáku i **zbraň** (viditelná / v autě – náhodná prohlídka kufru při podezření:
  pověst nízká, krev na autě, noc u lesa) a **náklad v kufru** (M2.10) – zvěřina bez `doklad_puvod` → pytláctví.
- Nesení úlovku na rameni / na nosiči přes obec → `cargo_seen` (M2.10) → `witness_check` → vesničan může nahlásit
  (podle povahy; plachta na vozíku skryje).
- Srážka se zvěří (příroda 04): vzít si sraženou zvěř = pytláctví (přivlastnění) → hajný / svědek.

### 2.5 Ukládání
Doklady (platnosti), povolenka (limity, zapsané úlovky), stav hajného / stráže (pozice není nutná), zabavené věci.

## 3. Hotovo, když
- Všechny doklady jdou získat legální cestou; legální lov a rybolov prochází kontrolami bez problému.
- Hajný a rybářská stráž hlídkují, reagují na výstřely a stopy, kontrolují; pytláctví má plné důsledky
  (zabavení, soud, ztráta dokladů, pověst, respekt, karma); policie kontroluje zbraně a kufr.

## 4. Návrh checklistu ručních testů
1. Úřad / PC / myslivec: získej zbrojní oprávnění (eTest + střelnice + posudek), lovecký lístek, povolenku.
2. Legální lov srnce v době lovu → hlášení myslivci → doklad o původu; prodej v hospodě.
3. Hajný tě potká večer v lese → kontrola dokladů → „V pořádku, lovu zdar.“
4. Luk + zajíc večer → výstřel neslyší, ale hajný najde stopu / uvidí úlovek na rameni → zabavení, trestný čin.
5. Puška bez povolenky → výstřel → hajný přijde z dálky.
6. Uteč hajnému → policie hledá.
7. Úlovek v kufru bez dokladu, policejní kontrola v noci u lesa → prohlídka kufru → pytláctví.
8. Rybaření bez lístku → rybářská stráž → zabavení udice.
9. Legální rybolov: ponechaná štika pod mírou → přestupek.
10. F5/F9 → doklady a povolenky zůstanou.

## 5. Závěr
README (Systémy → Lov a rybolov – doklady, stráže), `data/zakon.json`, `data/testy/*`, VIZE odškrtnout, roadmapa README,
PROJECT_LOG, commit „M4.6 Zbraně, lov a rybolov podle zákona: …“, checklist a čekat.
