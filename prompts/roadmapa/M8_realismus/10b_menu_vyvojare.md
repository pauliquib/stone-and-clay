# M8.D – Menu pro vývojáře (F3): živé ladění parametrů her­ních algoritmů

> Roadmapa **M8 Realistický svět** · vložený krok mezi vlnou 4 a 5 (požadavek uživatele 16. 10. 2026)
> Předpoklady: M8.1–M8.10 sloučené v `main` · Navazují: **všechny další kroky M8** (vlny 5–8 registrují své parametry), M8.19 (kalibrace)
> Zavádí API: `DevTune` (registr laditelných parametrů) – viz 00_PRINCIPY kap. 10

## 0. Než začneš – přečti
1. `00_SPOLECNE.md`, `M8_realismus/00_PRINCIPY.md` (kap. 3, 5, 6, 9, 10)
2. `scripts/game_settings.gd` (ukládání `user://nastaveni.cfg`, `REALISM_ROWS` – vzor „data, ne větvení“), `scripts/pause_menu.gd`
   (`_show_settings`, `_slider`, `_check`, `_option` – vzhled a stavební funkce řádků), `scripts/hud.gd` (`open_menu`, vzhled panelu – jen `grep -n`)
3. `scripts/game_menu.gd` – `open_debug_layers` (F2 → Příroda – ladění; zůstává, jen z menu vývojáře odkaz)
4. Vozidla: `scripts/car.gd` (auto, motorka, kolo? – `grep -n "^const\|^var .*:=\|kind\|bike\|moto" scripts/car.gd | head -80`), `scripts/bike_model.gd`,
   `scripts/flight/`, `scripts/dron.gd`, `scripts/hand_cart.gd`
5. Systémy M8: `scripts/eko/` (site, tree_eco, wind_field, soil_water, microclimate…), `scripts/gait.gd`, `scripts/fauna/quadruped_rig.gd`,
   `scripts/fauna/flight_model.gd`, `scripts/priroda/atmosphere.gd` (SkyModel/expozice)

## 1. Proč
Uživatel chce ladit fyziku a algoritmy hry ve hře, bez přepisování kódu: jak auto zatáčí a brzdí, jak se chová motorka a kolo,
jak silné jsou nárazy větru, o kolik je v údolí chladněji, jak rychle schne půda… Vyladěná čísla chce **uložit jako nastavení hry**
a předat je zpět do projektu (kořenový `config.json`), aby se staly novými výchozími hodnotami.

## 2. Rozhodnutí uživatele (neptat se znovu)
- Obsah: **jen živé ladění parametrů** (posuvníky / přepínače / volby). Profiler, ovládání světa a sondy se **nedělají** (nechtěl).
- Otevření: **F3**, ale jen když je zapnutý **„Režim vývojáře“** (Esc → Nastavení, výchozí **vypnuto**, ukládá se do `nastaveni.cfg`).
  Bez režimu F3 nic nedělá a menu se v nápovědě neukazuje.
- Ukládání: **Uložit** → `user://ladeni.cfg` (přežije restart, jen tento počítač); **Exportovat** → **`res://config.json` v kořeni projektu**
  (nové výchozí hodnoty, jdou do gitu). Pořadí načtení při startu: výchozí hodnota v kódu → `res://config.json` → `user://ladeni.cfg`.
  V exportované hře je `res://` jen pro čtení → Export zapíše vedle spustitelného souboru (`OS.get_executable_path().get_base_dir()`)
  a hlášku, kam; načítání zkouší obě místa.

## 3. Návrh
### 3.1 Registr `DevTune` (`scripts/dev_tune.gd`, instance `World.dev_tune` nebo statický registr – zvol podle toho, jak je udělané `GameSettings`)
- `register(id: String, group: String, label: String, default: Variant, lo := 0.0, hi := 1.0, step := 0.01, help := "", unit := "")`
  – `id` tečkově podle systému (`car.engine_force`, `bike.lean_max_deg`, `wind.gust_strength`, `micro.inversion_max_c`).
  Typ podle `default`: `float`/`int` = posuvník + číselné pole, `bool` = zaškrtávátko, `Array` řetězců s indexem = volba.
- `value(id) -> Variant`, signál `changed(id, value)`; `reset(id)`, `reset_group(group)`, `save_user()`, `export_root()`, `load_all()`.
- **Výkon:** v hot cestách se `DevTune` **nikdy nečte za snímek**. Systém si hodnotu drží v členské proměnné a obnoví ji
  v handleru `changed` (nebo jednou při `_ready`/stavbě). Vypnutý režim vývojáře = žádné náklady navíc.
- Neznámé klíče v `config.json` / `ladeni.cfg` se ignorují (s varováním do logu), chybějící = výchozí hodnota z kódu.
- `config.json`: `{"verze": 1, "parametry": {"car.engine_force": 4200.0, …}}` – exportují se **jen hodnoty odlišné od výchozích v kódu**,
  seřazené podle klíče (čitelný diff v gitu).

### 3.2 Menu (F3, nový `scripts/dev_menu.gd`)
- Vzhled jako ostatní nabídky (`Hud` panel / stavební funkce z `pause_menu.gd` – neduplikuj, vytáhni sdílené, nebo volej).
- Levý sloupec skupiny (dvouúrovňově: kategorie z 3.3 → podskupiny), vpravo řádky skupiny se jménem, posuvníkem, hodnotou s jednotkou, nápovědou (tooltip) a tlačítkem „↺“ (výchozí).
  Hledací pole nad seznamem (filtr podle textu). Řádek změněný oproti výchozí hodnotě je zvýrazněný.
- Dole: **Uložit**, **Exportovat do config.json**, **Výchozí (skupina)**, **Výchozí (vše)** – s potvrzením v menu (žádné `confirm()`).
- Hra za otevřeného menu **běží** (ať je vidět účinek – např. auto jede), jen se zamkne ovládání postavy/vozidla myší; zavření F3 / Esc.
- Odkaz „Ladicí vrstvy mapy…“ na existující `open_debug_layers` (F2 zůstává beze změny).

### 3.3 Co zaregistrovat – **dlouhý, úplný seznam** („fyzikální funkce světa“)
Upřesnění uživatele (16. 10. 2026): menu je od toho, aby **všechny možné funkce šly doladit k dokonalosti** – má to být **dlouhý seznam
nastavení rozdělený do kategorií**, ovládající „jakoby fyzikální funkce světa“. Ne výběr 3–8 koeficientů, ale **každá konstanta,
která ovlivňuje chování světa** (fyzika, simulace, AI, animace, časování), kromě čistě technických (velikost bufferu, indexy, cesty k souborům)
a offline dat (`site.bin`, `tree_eco.bin`, treegen – ty se za běhu neladí). V projektu je řádově 800+ `const` – počítej se stovkami parametrů.

Kategorie (hlavní → podskupiny) – menu je dvouúrovňové:
- **Svět:** gravitace, rychlost času / délka dne, eko-takt, fyzikální kroky (co jde za běhu).
- **Vozidla:** Auto · Motorka · Kolo · Ruční vozík · (traktor/další, pokud existují) – motor/točivý moment, převody, brzdy, max. rychlost,
  řízení (úhel, rychlost, citlivost podle rychlosti), přilnavost, odpružení, hmotnost/těžiště, aerodynamický odpor, náklon u jednostopých, šlapání.
- **Létání:** Letadlo · Rogalo/trike · Paramotor · Dron · Termika.
- **Člověk:** Pohyb hráče (rychlosti, skok, zrychlení, tření, plavání) · Tělo (výdrž, hlad, chlad, únava) · Chůze a postoj (Gait) · NPC a vesničané · Pes.
- **Činnosti:** Rybaření · Lov a balistika · Oheň a požáry · Těžba/řemesla (co je fyzika/časování).
- **Příroda:** Počasí · Roční doby · Obloha a světlo · Vítr · Voda a půda · Mikroklima · Dřeviny a les · Pole a louky · Louže, stopy.
- **Zvěř:** Pohyb a rig · Smysly a útěk · Ptáci a let · Hejna a murmurace · Hospodářská zvířata.

### 3.4 Rozdělení práce (orchestrátor)
- **M8.D1** (jeden subagent): `DevTune` + menu F3 + Režim vývojáře + ukládání/export + kategorie **Svět** a **Vozidla** kompletně.
- **M8.D2** (čtyři subagenti souběžně, až po sloučení D1, každý jen své soubory): **a)** Létání · **b)** Člověk + Činnosti ·
  **c)** Příroda · **d)** Zvěř. Registrace patří do souboru systému (nebo jednoho `scripts/dev/tune_<kategorie>.gd` na kategorii),
  nikdy do sdíleného centrálního seznamu – ať paralelní agenti nekolidují.
- Převod: `const X := 4200.0` → registrovaný parametr se **stejnou výchozí hodnotou** (chování při výchozím stavu musí zůstat beze změny).
  Pokud konstantu používá víc souborů, čtou ji z jednoho místa. Konstanty použité v `const` výrazech / velikostech polí nech být.

## 4. Hotovo, když
- Zapnu Režim vývojáře, F3 → skupina Auto → zvednu sílu motoru → auto hned zrychluje víc; „↺“ vrátí výchozí.
- Uložit → restart → hodnota drží. Exportovat → v kořeni projektu je `config.json` jen se změněnými hodnotami; po smazání
  `user://ladeni.cfg` se hodnota načte z `config.json`.
- Bez Režimu vývojáře F3 nic nedělá a výkon je stejný jako před krokem.

## 5. Návrh checklistu ručních testů
1. Esc → Nastavení → Režim vývojáře zapnout; F3 otevře menu, F3/Esc zavře.
2. Auto: síla motoru, brzdy, řízení, přilnavost – změna je cítit hned při jízdě.
3. Motorka a kolo: max. náklon, stabilita – změna znát.
4. Vítr / mikroklima: zvednout sílu nárazů → stromy se ohýbají víc; zvýšit max. inverzi → HUD v údolí ukáže větší rozdíl.
5. Hledání „brz“ najde brzdy všech vozidel.
6. Uložit, restart, hodnoty drží. Export → `config.json` v kořeni, obsahuje jen změněné.
7. Výchozí (vše) → vše zpět, zvýraznění zmizí.
8. Režim vývojáře vypnout → F3 nic, nápověda F1 ho nezmiňuje.

## 6. Dokumentace
README (F3, Režim vývojáře, `config.json`), `docs/DEV.md` (jak zaregistrovat parametr – 5 řádků s příkladem), `docs/SYSTEMS.md`,
PROJECT_LOG, oddíl `## M8.D` v `docs/testy_M8.md`, řádek M8.D v `prompts/roadmapa/README.md` a `docs/VIZE_A_ROADMAPA.md`.
