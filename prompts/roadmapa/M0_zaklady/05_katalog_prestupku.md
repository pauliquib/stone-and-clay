# M0.5 – Zákon jako data: katalog přestupků a bodový systém

> Roadmapa „Život na vsi“ · **M0 Základy** · krok 5/6
> Předpoklady: M0.2 · Navazují: M4 (řidičák, úřad, soud, zbraně), všechny kroky, které přidávají přestupky (kácení, oheň, lov, drony)

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md` (kap. 3 právní zásady)
2. `docs/VIZE_A_ROADMAPA.md` – kap. **3.4 Zákon jako data** a 4.4
3. `scripts/police.gd` – kde vznikají pokuty, zákaz řízení, záchytka (grep `pokut|fine|money|license|suspend|zachyt`)
4. `scripts/reputation.gd` – `on_event`, `offenses`, `change`
5. `scripts/world.gd` – `_on_busted`, `radio` / rušení klidu (grep `2000|pokuta`), `dialog` urážka policisty (grep `urážk|insult`)
6. `scripts/hud.gd` – `_journal_bbcode` (oddíl rejstříku přestupků)

## 1. Proč
Hra má simulovat život podle **českých zákonů**. Dnes jsou pokuty a tresty roztroušené natvrdo v kódu
(policie, rádio, urážky). Potřebujeme **jeden katalog**, ze kterého se berou částky, body, zákazy
a to, jestli jde o přestupek nebo trestný čin. Další kroky do něj jen přidají řádky.

## 2. Návrh
### 2.1 Data `data/zakon.json` (upravuje člověk)
```json
{
 "verze": 1,
 "overeno": "RRRR-MM-DD – ověřit aktuální znění před vydáním",
 "prestupky": {
  "alkohol_do_1": {"nazev": "Řízení pod vlivem alkoholu (do 1 ‰)", "zakon": "361/2000 Sb.", "par": "§ 125c odst. 1 písm. b)",
                   "pokuta": [2500, 20000], "body": 7, "zakaz_rizeni_mes": [12, 24], "trestny_cin": false, "misto": "spravni_rizeni"},
  "alkohol_nad_1": {"nazev": "Ohrožení pod vlivem návykové látky", "zakon": "40/2009 Sb.", "par": "§ 274",
                    "pokuta": [0, 0], "body": 7, "zakaz_rizeni_mes": [12, 120], "trestny_cin": true, "misto": "soud"},
  "rychlost_obec_20": {...}, "rizeni_pres_zakaz": {...}, "ujeti_policii": {...}, "ruseni_nocniho_klidu": {...},
  "urazka_uredni_osoby": {...}, "nehoda_skoda": {...}, "srazeni_chodce": {...}
 }
}
```
- Klíče: `nazev`, `zakon`, `par`, `pokuta` [min, max] Kč, `blokova` (max. na místě), `body` (bodový systém),
  `zakaz_rizeni_mes` [min, max], `trestny_cin`, `misto` (`na_miste` | `spravni_rizeni` | `soud`), `poznamka`.
- Hodnoty vezmi z toho, co hra už dnes používá (ať se chování nezmění), a doplň přibližně podle zákonů
  (361/2000 Sb. silniční provoz vč. bodového systému po novele 2024, 251/2016 Sb. přestupky, 40/2009 Sb.
  trestní zákoník). **Nevymýšlej paragrafy, které si nejsi jistý** – dej `"par": "?"` a poznámku „ověřit“.
  Do `overeno` napiš, že částky jsou orientační.

### 2.2 Kód `scripts/law.gd`, `class_name Law`
- Statické načtení katalogu (`static func load_catalog()`, cache), `static func offense(id) -> Dictionary`.
- Per hráč `LawRecord` (může být ve stejném souboru jako vnitřní třída, nebo `scripts/law_record.gd`):
  - `points := 0` (bodový systém; **12 bodů** = zákaz řízení 1 rok a přezkoušení – zatím jen zákaz),
    body se po 12 měsících bez přestupku odečítají (zjednodušeně: −4 za každý herní rok bez přestupku – laditelné),
  - `records: Array` – rejstřík `{t (herní minuty), id, pokuta, body, zaplaceno, trestny_cin}`,
  - `unpaid_fines` (součet), `func commit(id: String, data := {}) -> Dictionary` – zapíše přestupek, vybere
    pokutu (v rozmezí podle závažnosti: `data.severity` 0..1), přičte body, případně zákaz řízení
    (`player.license_suspended_until`), vrátí výsledek pro zprávu,
  - `to_dict / from_dict` – ukládání.
- `World.law[id]`, vytvořit v `add_player`, a `func commit_offense(id, offense_id, data := {})` – jediná brána:
  zapíše, pošle `emit_game_event(id, "offense", {...})` (na to reaguje pověst a úkoly), `notify` hráči.

### 2.3 Převést stávající tresty
Najdi všechna místa, kde se dnes ručně strhávají peníze za přestupek / dává zákaz (policie, rádio,
urážka policisty …) a převeď je na `World.commit_offense`. Výše pokut a zákazů se nesmí výrazně změnit.
Pověst (`Reputation.on_event`) nech reagovat jako dřív (nesmí se odečíst dvakrát – zkontroluj).

### 2.4 Deník J – oddíl „Úřední záznamy“
Body „5 / 12“, nezaplacené pokuty, posledních 10 záznamů (datum, název, pokuta, body, § zákona).
Do F1 doplň doložku: „Zákony jsou ve hře zjednodušené – nejde o právní radu.“

## 3. Mimo rozsah
Placení pokut na úřadě a exekuce (M4.2), soud (M4.3), nové přestupky (přidají jednotlivé kroky).

## 4. Hotovo, když
- Všechny dnešní tresty jdou přes `commit_offense` a katalog; chování hry je stejné, jen deník ukazuje § a body.
- Body se sčítají, 12 bodů = zákaz řízení; vše se ukládá.

## 5. Návrh checklistu ručních testů
1. Vypij 2 piva, jeď kolem policie (F2 → Teleport) → kontrola, pokuta jako dřív; J → Úřední záznamy: záznam s § a body.
2. Rádio doma na 10 v noci → policie, pokuta 2 000 Kč, záznam „rušení nočního klidu“.
3. Urážka policisty (T) → pokuta, záznam.
4. Opakuj přestupky do 12 bodů → zákaz řízení, hláška.
5. F5 / F9 → body a záznamy zůstanou; starý save → 0 bodů, nic nespadne.
6. Uprav v `data/zakon.json` pokutu → ve hře se projeví.

## 6. Závěr
README (Systémy → Zákon, Ladění → `data/zakon.json`), VIZE odškrtnout, roadmapa README, PROJECT_LOG,
deník AI, commit „M0.5 Katalog přestupků: …“, checklist a čekat.
