# M4.6 – Zbraně, lov a rybolov podle zákona: doklady, hajný, rybářská stráž, kontroly

> Roadmapa „Život na vsi“ · **M4 Zákon a společnost** · krok 6/6
> Předpoklady: M2.7, M2.8, M2.9, M2.10, M4.1 (`Permits`), M4.3, M4.4 (`witness_check`), M3.4 (eTesty) · Navazují: V2

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md`
2. `docs/VIZE_A_ROADMAPA.md` – kap. 4.2 „Lovecké zbraně“, „Kdo tě může chytit“, „Přeprava úlovku“ a kap. 4.4 „Zbraně, lov a rybolov“
3. `scripts/permits.gd`, `scripts/law.gd`, `data/zakon.json`, `data/lov.json` (M2.9), `data/ryby.json` (M2.7)
4. `scripts/weapons.gd` (M2.8), `scripts/cargo.gd` (M2.10 – `visible_cargo`, kufr), `Carcass` (M2.9)
5. `scripts/police.gd` – kontrola (grep `checkpoint|kontrol|inspect`)
6. Myslivec z přírody 04 (grep `myslivec`) – vzor NPC v lese; `scripts/villager.gd` / `npc.gd` – pohyb NPC po trase
7. `scripts/computer_ui.gd` – eTesty

## 1. Proč
Uzavírá lov a rybaření: **legální cesta** (doklady, kurzy, povolenky) a **nelegální cesta** s reálným
rizikem dopadení (hajný, rybářská stráž, policie, svědci). Rozhodnutí uživatele: pytláctví je záměrně
možné, ale zakázané a riskantní; hra nic nezakazuje, jen nese důsledky.

## 2. Co udělat
### 2.1 Doklady a jak je získat (vše orientačně, v datech „ověřit“)
| Doklad | Jak | Cena (orient.) | Podmínky |
|---|---|---|---|
| **Zbrojní oprávnění** (nový zákon o zbraních č. 90/2024 Sb. od 2026) | teorie eTest (PC, 30 vlastních otázek) + praktická zkouška na střelnici (M2.8 – 5 ran na 25 m, bezpečná manipulace) + lékařský posudek (návštěva lékaře – nabídka na úřadě „posudek“ 1 500 Kč) | ~4 000 Kč | čistý rejstřík trestů (M4.3), bezúhonnost; odebrání: trestný čin, alkohol se zbraní |
| **Lovecký lístek** | kurz myslivosti (u myslivce – 3 večery v chatě = 3 krátké úkoly: poznávání zvěře, bezpečnost, péče o revír) + zkouška (eTest) | ~5 000 Kč | – |
| **Povolenka k lovu** | od mysliveckého spolku (myslivec) na měsíc, určuje druhy a počty (1 srnec, 2 divočáci…) | 1 500 Kč / měsíc | lovecký lístek; hlášení úlovku (E u myslivce do 24 h → `doklad_puvod`) |
| **Rybářský lístek** | kurz + test (eTest 20 otázek) | ~1 000 Kč | – |
| **Povolenka k rybolovu** | rybářský spolek (nabídka v hospodě / na PC), roční, se **záznamem úlovků** (ponechané ryby se zapisují automaticky) | 1 800 Kč / rok | rybářský lístek |
Nahraď všechny háčky `has_permit(...)` z M2.7–M2.9 skutečnými doklady (`Permits`). Test: cheat z M2.8 ponech jen v F2.

### 2.2 Hajný / myslivecká stráž (NPC)
- Nový `scripts/gamekeeper.gd` (`class_name Gamekeeper`): 1 hajný (smyšlené jméno, povaha přísná) – obchůzka lesů
  po trasách (lesní cesty z grafu / náhodné body `Fauna.random_point(..., "forest")`), **hlavně za šera a v noci**
  (18–23 h, 4–7 h), přes den u chaty / krmelce. Jezdí i terénním autem (pickup M1.6) mezi lesy.
- **Vnímání:** slyší výstřel (M2.8 – do 1 500 m → jde k místu výstřelu), vidí hráče se zbraní / úlovkem v lese
  (zrak jako `witness_check`), najde krvavou stopu / vývrhy / nahlášené „nenahlášené činy“ (M4.4 `Law.hidden`) v okolí.
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
PROJECT_LOG, deník AI, commit „M4.6 Zbraně, lov a rybolov podle zákona: …“, checklist a čekat.
