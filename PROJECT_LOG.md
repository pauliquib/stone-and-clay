# PROJECT_LOG – Stone & Clay

Deník práce na roadmapě (`prompts/roadmapa/`). Formát záznamu: `prompts/roadmapa/00_SPOLECNE.md` kap. 7.
Starší historie (M0–M3, M6) se do veřejného snapshotu nepřenesla – stav je v `docs/testy_M*.md`,
`docs/SYSTEMS.md` a v roadmapě (`prompts/roadmapa/README.md`).

## 2026-10-06 – Vlna 0: stabilizace před M4

### Hotovo
- Rozpracovaná práce (rozšíření mapy na 5 obcí, simulační bublina, mapa M se zoomem, minimapa, perf test)
  uložena jako commit `d1e4c32` „WIP…“ – obsahuje známou chybu: objekty daleko od spawnu se nezobrazují.
- Klávesa **P** zůstává pro doklady (M4.1); panel úkolu přesunut na **Z** (fyzicky Y, QWERTZ).
- `00_SPOLECNE.md`: aktuální velikosti souborů, registr kláves, krok „deník AI“ zrušen (`CLAUDE.md` v repu není).

### Plán vlny 0
- 0b: oprava dohledu vzdálených objektů a kontrola výkonových změn z WIP commitu.
- 0c: statický audit (svět a interiéry; vozidla, doprava a létání M6; řemesla M2; práce, PC a zákon M0/M3).
- 0d: opravy podle schváleného seznamu chyb → ruční test uživatele → teprve pak M4.

### Otevřené body (hlášení uživatele)
- M6: modely letadel vypadají špatně, postava někdy sedí obráceně, ovládání letu nefunguje, nejde vzlétnout.
- Ze hry 30. 9.: propad do nekonečna po odchodu z obchodu; zoom kamery v menu; příliš tvrdá závislost na
  cigaretách (třes obrazu); cigarety prodávat **jen v obchodě**; víkendová otevírací doba obchodu; po tažení
  ručního vozíku nejde sprint; PRIORITNĚ doprava – dům zasahující do silnice, ostré zatáčky.
- Rozhodnutí uživatele: M4.8 návykové látky ano – s volbou „obsah pro dospělé“, hra k trestné činnosti nenabádá.

## 2026-10-06 – Vlna 0b: oprava dohledu vzdálených objektů

### Hotovo (staticky ověřeno čtením kódu a zdrojáku Godot 4.3 – ruční test čeká)
- **Příčina „za spawnem nic není“**: WIP `d1e4c32` přidal dlaždicím mapy (`MapLoader.add_chunks` – zdi, střechy,
  silnice, cesty) `visibility_range_fade_mode = FADE_SELF`. Godot 4.3 ořezává dohled podle středu AABB instance
  (`renderer_scene_cull.cpp`: `vd.position = transformed_aabb.get_center()`), ale **prolínání FADE_SELF počítá
  z počátku uzlu** (`render_forward_clustered.cpp:864`: `inst->transform.origin.distance_to(cam)`). Dlaždice měly
  uzel v počátku světa (dům hráče) a geometrii v absolutních souřadnicích → jakmile byla kamera dál než
  ~dohled (1,4–1,8 km × násobič Dohlednosti) od spawnu, všechny budovy a cesty na celé mapě zprůhledněly na 0.
- **Oprava**: `MapLoader.load_chunks` posune vrcholy do lokálních souřadnic středu AABB dlaždice a vrací `origin`;
  `add_chunks` na něj posadí MeshInstance3D i kolizní těleso. Ořez i prolínání se teď měří od dlaždice,
  dohled (výkon) zůstává. Shader `tinted_triplanar` počítá ve světových souřadnicích (MODEL_MATRIX) – beze změny vzhledu.
- **Stejná třída chyb jinde** (dohled od středu AABB velkého meshe): vodní toky jsou 1 mesh na tok (po union
  mapě i km dlouhé) → `Water._vis_end` = VIS_RANGE + ½ vodorovné úhlopříčky; ploty (`FenceManager` – jeden mesh
  všech plotů včetně vzdáleného pole) obdobně; stopy ve sněhu (`Tracks` – kruhový buffer s volnými instancemi
  v (0, −5000, 0), AABB uprostřed ničeho) → dohled zrušen (max. ~600 drobných instancí).
- Zkontrolováno bez nálezu: terén (custom_aabb lokální, uzel v rohu dlaždice), krajina za okrajem, stromy
  (MultiMesh po buňkách 128/256 m), vegetace (vlastní LOD podle AABB buňky), okolní obce (bez dohledu),
  detaily budov (dlaždice 256 m), GameSettings násobič, data DBM1 (dlaždice ≤ 320 m, pokrývají celou union mřížku).
  Simulační bublina schovává jen NPC/vesničany/psy (vizuál) a uspává auta – nic z mapy.
- Drobnosti z WIP: komentář `perf_test` odkazoval na neexistující `World.apply_perf_flags` / `--perfnpc`;
  komentář `World.sim_radius` uváděl neexistující volbu „0 = bez omezení“.

### Otevřené body
- Čeká na ruční test uživatele (checklist v odpovědi).
- Prolínání FADE_SELF u dlaždic kreslí okraj dohledu průhledně (transparentní průchod) – kdyby dělalo
  artefakty se stíny / řazením, stačí v `add_chunks` vrátit FADE_DISABLED (ořez zůstane správný).
- Výkon velké mapy se nově měří přes `--perf` (spouští jen uživatel).

## 2026-10-06 – Vlna 0d – F5 NPC, zákon, obsah

### Hotovo (staticky ověřeno čtením kódu – ruční test čeká)
- **A4-03 zaseknutí vesničana**: po `BT_STUCK_MAX` (3) zaseknutích cestou za cílem z BT `Villager` cíl vzdá
  (`clear_target`, `_bt_giveup_pos` / `BT_GIVEUP_S` = 90 s); `move_to` vrací `bool` a vzdaný cíl odmítá,
  `go_to_place.gd` pak vrátí FAILURE (strom zkusí jinou větev, místo věčného RUNNING).
- **A4-04 povolání → pracoviště**: `JOB_PLACE` se páruje po SLOVECH (kmen na začátku slova), ne podřetězcem
  (`hospodsk` → hospoda, `hospodář` → statek), `JOB_EXCLUDE` (býval-, soused-, okresn-) povolání zneplatní.
  `_bt_fill_vars` doplňuje pracoviště zvlášť (`_bt_work_ok`) – znovu zkouší, dokud místo (statek) nevznikne;
  do blackboardu přibyly `workplace_key` (String) a `shop`. `BT_VILLAGERS` beze změny (5).
- **A4-05 behavior strom**: nové tasky `conditions/place_open.gd` (`Place.is_open`), `is_free_day.gd`,
  `garden_weather.gd` (sezóna jaro–podzim, bez deště, bez sněhu, ≥ 3 °C), `not_done_today.gd` + `actions/mark_day.gd`.
  Větve: zahrada jen za vhodného počasí; práce jen když je pracoviště otevřeno; nová větev „Víkendový nákup“
  (so / ne / svátek 9–18 h, otevřený obchod, 1× denně); hospoda jen otevřená + nová větev „Posezení u stolu“
  (kdo má promile ≥ 0,5, sedí u stolu a nechodí pryč a zpět = konec kmitání). Víkend/neděle jinak = procházka.
  **`ai/villager_routine.tres` byl upraven RUČNĚ shodně s `tools/gen_villager_bt.gd` (generátor se nespouštěl)**;
  ids sub-resource jsou jiná než by dal generátor, struktura a hodnoty stejné. Při příštím spuštění generátoru se přepíše ekvivalentním výstupem.
- **A4-12**: `Villager`, `Dog`, `Npc` používají `World.player_world_pos` (hráč v interiéru = dveře domu); navazuje na simulační bublinu.
- **A4-08 zakon.json**: doplněn zákon a § (s „ověřit“) u zachytka, rušení nočního klidu, urážka a vyhrožování úřední osobě,
  nenahlášená srážka, ujetí policii, srážení chodce, nehoda, střelba v obci, zbraň pod vlivem (čísla § jsou nejisté – ověřit
  aktuální znění); `rychlost_obec_20` → `rychlost_obec` („limit 50 km/h“; `police.gd`, prompt M0.5, alias `Law.ALIASES` pro staré
  rejstříky); duplicita `poskozeni_veci` / `poskozeni_cizi_veci`: zůstávají dvě id (různé situace, různé kódy volající), ale
  mají shodný právní základ (251/2016 § 50, u větší škody § 228 TZ) a rozlišené názvy. `ul_bez_pojisteni` a ostatní `ul_*` dělá agent létání.
- **A4-13 / A4-14**: pole `drb` (věta do drbů) a `karma` v každém přestupku; `Computer.on_event` bere `drb`,
  `Reputation` bere `Law.offense(id).karma` (`OFFENSE_KARMA` zůstalo prázdné jako přepis). `ul_*` bez polí → starý fallback.
- **A4-10 eTesty**: `TestUI` míchá odpovědi (správná se přesune s textem), umí `pocet` (losování z banku) a `prah_pct`; pevný `prah` funguje dál (ořezán na počet otázek).
- **A4-11**: `Jobs` sleduje změnu `Clock.start_jd` (F2 Datum, bez zásahu do `world.gd`) → `_on_date_changed`: rozpracovaná směna /
  zakázka se zruší bez postihu, `resolved` se vymaže, `hired_jd` a pozvánky se posunou.
- **A4-16 obsah**: Zetor → „starý traktor“ (`dialog.gd`, `characters.gd`); ÚCL → smyšlený „ÚVL – Úřad pro vzdušné lety“ (`zakon.json`, `permits.gd`,
  `computer_ui.gd`, `computer.gd`, `data/testy/*`, `game_menu.gd`, `items_db.gd`, `dron.gd`, docs); `clock.gd` bez názvu obce a přesných souřadnic
  (LAT/LON zaokrouhleny na 49,1 / 17,7); `DALSI DOPLNKY.md`: „Velký Oříškov“ (fiktivní obec z `data/obce.json`).

### Otevřené body
- Čeká na ruční test uživatele (checklist v odpovědi).
- **ÚCL zbývá** v souborech jiných agentů (nesáhl jsem): `world.gd` (maily, účtování, hlášky), `hud.gd` (nápověda), `place.gd` (komentáře), `flight/paramotor.gd`;
  po sloučení stačí `sed -i 's/ÚCL/ÚVL/g'` na tyto soubory (stejný text, nesklonná zkratka).
- Čísla § v `zakon.json` u nově doplněných řádků jsou orientační – skutečně ověřit.
- Bez změny: A4-06, A4-07, A4-09, A4-15 (jiná skupina / odloženo).
