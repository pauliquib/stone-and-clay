# M3.1 – Systém zaměstnání

> Roadmapa „Život na vsi“ · **M3 Práce a počítače** · krok 1/4
> Předpoklady: M0.3 (dovednosti), M0.4 (akce), M0.5 (rejstřík), M0.6 (respekt) · Navazují: M3.2, M3.3 (konkrétní práce), M3.4 (portál práce na PC), M4.3 (vězení → výpověď)

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md`
2. `docs/VIZE_A_ROADMAPA.md` – kap. 4.3 „Zaměstnání (11)“
3. `scripts/quests.gd` (hlavička + `Quest` třída / struktura úkolu – grep `class Quest|func start|func check|steps`) – **vzor**: kroky, cíle na mapě, podmínky, odměny
4. `scripts/hud.gd` – `quest_started`, `_quest_text`, kompas / značka cíle (`beacon` v `local_client.gd`)
5. `scripts/world.gd` – `skip_time`, `rest`, `sleep`, `_on_busted` (zadržení), `emit_game_event`
6. `scripts/clock.gd` – `hour()`, `weekday()`, `holiday()`
7. `scripts/skills.gd`, `scripts/law.gd`, `scripts/reputation.gd` (respekt), `scripts/body_state.gd` (`promile()`)
8. `scripts/estate.gd` (M1.7 – domov, byt, **nájem a dluh** `rent_overdue`) a záznamy M1.7, M1.8 v `PROJECT_LOG.md`
   (interiéry všech budov se staví jen zblízka – pracoviště uvnitř budovy musí počítat se streamováním)

## 1. Proč
Uživatel chce **různá zaměstnání**. Práce je stabilní legální příjem, trénuje dovednosti a dává respekt;
zároveň má pravidla (docházka, střízlivost), jejichž porušení vede k výpovědi.

## 2. Návrh
### 2.1 Katalog `data/prace.json` (upravuje člověk)
```json
{"farma": {
  "nazev": "Pomocník na farmě", "zamestnavatel": "Statek Na Kopci (smyšlený)", "misto": "statek",
  "pozadavky": {"dovednosti": {"chovatelstvi": 3}, "ridicak": "", "obleceni_tag": "pracovni", "rejstrik_cisty": false,
                "povest_min": -20, "respekt": {"zemedelci": 0}},
  "smeny": [{"dny": [1,2,3,4,5], "od": 6.0, "do": 14.0}],
  "mzda_hod": 160, "vyplata": "tyden",
  "ukoly": ["farma_krmeni", "farma_seno", "farma_dojeni"],
  "dovednosti_xp": {"chovatelstvi": 1.0, "zahradnictvi": 0.5},
  "respekt": "zemedelci"
}}
```
- Mzdy realistické pro region (hrubá mzda / hod 150–250 Kč; výplata čistá – zjednodušeně −15 % daň a pojištění,
  text „čistá mzda (zjednodušeno)“).

### 2.2 Kód `scripts/jobs.gd` (`class_name Jobs extends Node`, per hráč `World.jobs[id]`)
- `current := ""` (id práce), `hired_day`, `warnings := 0`, `attendance := []` (poslední 20 směn: včas / pozdě / absence / opilý),
  `earned_unpaid := 0`, `rating := 50` (0–100).
- `can_apply(job_id) -> Dictionary {ok, reasons}` (podle požadavků), `apply(job_id)` (pohovor: krátký dialog v nabídce
  místa; šance podle `vyrecnost` a pověsti), `quit()`.
- **Směna:** v čase směny musí být hráč do 15 min od začátku v okruhu 30 m od místa práce → „Začal jsi směnu“
  (jinak pozdní příchod; > 60 min = absence). Během směny dostává **pracovní úkoly** (malé kroky z `ukoly` – každý
  je krátká posloupnost kontextových akcí M0.4 nebo „dojdi / přines / odvez“), HUD ukazuje „Směna 6:00–14:00, úkol:
  Nakrmit slepice“. Za hodiny ve směně (přítomnost v areálu + plnění úkolů) roste výdělek.
- **Porušení:** příchod s promile > 0,2 → varování (+ vedoucí pošle domů), opakovaně → výpověď; odchod ze směny
  bez dokončení → absence; 3 varování → výpověď. Zadržení policií / vězení (M4.3) → výpověď. Hodnocení ovlivní
  prémii (0–20 %) a doporučení (respekt).
- **Výplata:** týdně v pátek po směně nebo na účet (M3.4 bankovnictví – zatím hotově u zaměstnavatele).
  Hráč od M1.7 bydlí v nájemním bytě (1 200 Kč / 7 dní): když má dluh na nájmu, nabídni při výplatě „Zaplatit
  dluh na nájmu“ (přes API `Estate`, ne vlastní evidenci); práce je hlavní cesta, jak nájem utáhnout.
- **Volno:** svátky (`Clock.holiday()`), víkend dle směn.
- Ukládání `to_dict/from_dict`.

### 2.3 UI
- Nabídka zaměstnavatele (E u vedoucího / místa): „Hledáte pracovníky?“ → seznam prací s požadavky (splněné zeleně,
  nesplněné šedě s důvodem) → „Ucházet se“.
- Deník J: oddíl „Práce“ – zaměstnání, směny, docházka, varování, hodnocení, výdělek.
- HUD: během směny malý řádek nahoře.

- **Domov:** žádné „dům hráče“ – cesta domů, spánek před směnou atd. jen přes `Estate` / `World.home_door()`.

## 3. Mimo rozsah
Konkrétní práce a jejich místa (M3.2, M3.3) – tady jen **jedna testovací práce** „Pomocník v hospodě“ (úklid stolů =
akce na stolech v interiéru hospody M1.5, nebo před hospodou, pokud interiér není) pro ověření celého systému.

## 4. Hotovo, když
- Jde se ucházet o testovací práci, chodit na směny, plnit úkoly, dostat výplatu; pozdní příchod, opilost
  a absence vedou k varování a výpovědi; deník ukazuje přehled; vše se ukládá.

## 5. Návrh checklistu ručních testů
1. Hospoda → „Hledáte pracovníky?“ → Pomocník v hospodě → požadavky → přijat.
2. Druhý den přijď včas → „Začal jsi směnu“, HUD úkol; ukliď stoly → výdělek roste.
3. Přijď o hodinu později → absence / varování v deníku.
4. Přijď po 3 pivech → poslán domů, varování.
5. 3 varování → výpověď.
6. Pátek → výplata; J → Práce.
7. F5/F9 → zaměstnání a docházka zůstanou.

## 6. Závěr
README (Systémy → Práce), GAME_DESIGN, VIZE odškrtnout, roadmapa README, PROJECT_LOG, deník AI,
commit „M3.1 Systém zaměstnání: …“, checklist a čekat.
