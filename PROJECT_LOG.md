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

## 2026-10-06 – Vlna 0d – F3 Hráč a řemesla

### Hotovo (staticky ověřeno čtením kódu – ruční test čeká)
- **A3-01 / A1-11**: cigarety odebrány z `Place.OFFERS["hospoda"]` (jen Potraviny); text úkolu „Cigarety pro dědu“ upraven.
- **A3-10**: úkol přijme i načatou krabičku (`CigaretyQuest.CIGS_NEEDED` = 15 ks, tolik se dědovi odevzdá).
- **A3-02 / A3-03**: `BodyState` – `ADDICTION_NORM` 80, `ADDICTION_DECAY_K` 0,0578 (poločas 12 h), `CRAVING_NICOTINE_MIN`
  0,25, `CRAVING_RATE` 0,07, strop chuti `CRAVING_BASE_CAP` + závislost, `CRAVING_SLEEP_K` 0,2 (spánek).
- **A3-08**: `addiction` a `_smoke_rate` v `SaveGame.BODY_KEYS`; starý save bez klíče = 0.
- **A3-04 / A3-05**: třes obrazu = hladký šum (`_shake_noise`), práh abstinence 0,6, amplituda 0,0009, záchvaty 5 s / 60 s,
  zima plynule se stropem 0,003, ne při míření / dalekohledu; nastavení „Třes obrazu“ (`GameSettings.withdrawal_shake`,
  cfg `obraz/tres`, přepínač v `pause_menu.gd`, použito přes `Player.shake_enabled`).
- **A3-06 / A2-24**: `Player.speed_mods` + `set_speed_mod / clear_speed_mod / effective_walk / effective_sprint / effective_jump`;
  `walk_speed` / `sprint_speed` / `jump_velocity` se už nikde nepřepisují. Převedeno: `Cargo` (rameno, vozík), `Hunting`
  (zvěř na rameni), `Quests` Krmivo. `no_sprint` blokuje sprint a tím i jeho výdrž.
- **A3-07**: výdrž nákladu přes `Player.drain_stamina` (cargo ×2, hunting).
- **A1-09**: `_recover_from_void` v interiéru vrací ke dveřím interiéru (nebo `exit_interior`) + `push_warning` s diagnostikou.
- **A3-09**: `Farm._slaughter_go` kontroluje `is_instance_valid(p / a)` po `await`.
- **A3-11**: `Player.add_item` rozbaluje balení podle pole `count` v katalogu, ne podle id „cigarety“.
- **A3-13**: guard `p.input != null` v `ActionRunner` a `Fishing`.

### Otevřené body
- Čeká na ruční test uživatele (checklist v odpovědi).
- A3-12 (keš úrovní) odloženo podle auditu. Cigarety dál nabízí i obchod v `OFFERS["obchod"]` za 165 Kč.
- Stará uložená pozice s neseným nákladem: modifikátor se po načtení neobnovuje (náklad se při načtení zahazuje / pouští jako dřív).

## 2026-10-06 – Vlna 0d: F4 Svět a mapa

### Hotovo (staticky ověřeno čtením kódu – ruční test čeká)
- **A1-01** kolečko nezoomuje kameru v menu / chatu / mapě (`LocalClient._unhandled_input`).
- **A1-02, A1-03, A1-18** mapa M (`hud.gd`): překresluje se jen při změně (zoom, tažení, otevření) a marker hráče
  + popisek polohy ~4× za s (`_map_dirty`, `_map_tick`). Statické vrstvy (hranice, vody, silnice) v keši ve světových
  souřadnicích (`_map_build_cache`), kreslí se jednou `draw_set_transform`, šířky čar = px / ppm, ořez podle AABB čar
  mimo výřez. Obce (`_obce_build_cache`): silnice po druzích v dávkách, segmenty uvnitř domácího katastru se
  vynechají (už je kreslí hlavní vrstva), tečkované hranice se přepočítají jen při změně zoomu. Zoom ke kurzoru,
  tažení a minimapa beze změny. `_map_ext_ok` se nastaví až když jsou obce načtené.
- **A1-04** `SurfaceMap.make_map_image`: výšky se vzorkují jednou do mřížky (1× místo 3× `height_at` na pixel),
  barvy se zapisují přímo do bajtů, stejný vzhled (krok 8 m).
- **A1-05 + A4-01** `World.place_shut` hlídá `buy` i `sell_items`; `open_place_menu` zavřenému místu neukazuje
  práci, úkoly ani zboží (jen „Zavřeno, otevřeno …“). Výplata a výpověď jsou skryté taky (zaměstnavatel tam není,
  výplata zůstává nasbíraná / jde na účet, výpověď jde příště). Obsluha mimo otevírací dobu zmizí (`HIDDEN_OFFSET`),
  `Place._process` ji přerozdělí každé 4 s; zahrádka hospody se bez otevřeno nepoužije.
- **A4-02 + A1-06** úřední dny (`WEEK_HOURS["urad"]`: Po a St 7–17, Út a Čt 8–14, Pá 8–12, So a Ne zavřeno,
  svátky zavřeno přes `CLOSED_ON_HOLIDAY`), `hours_text()` vypisuje i výjimky podle dne. `tests.gd::_reset` přeskočí
  víkendy a svátky (úkoly přes úřad); pronájem pole v testu volá `Garden.service` přímo, tedy beze změny.
- **A1-07** F2 → Teleport: sekce „Okolní obce“ (`teleport_target("obec:<id>")` – okolní obce nemají terén ani kolize,
  proto se hráč postaví na nejbližší okraj katastru čelem k obci).
- **A1-08** načtení uložené pozice v neexistujícím interiéru → výstup ke dveřím místa / default spawn + varování v logu.
- **A1-10, A1-17, A1-20** `exit_interior`: výška bodu výstupu se ověří raycastem na statiku (`_ground_y`), odchylka od
  uloženého / terénu se tiskne do logu (`exit_interior[...]`); `controls_locked` se vrací na původní hodnotu (menu
  zůstane zamčené). Vstup do interiéru: kontrolní raycast pod `inside_door` (`_check_floor`, jen varování).
- **A1-13** text načítání „Stromy (51 736)“.
- **A4-06** víkendoví hosté mají obecné jméno „Výletník / Výletnice“ (ne kopii pojmenované postavy) a neukládají se
  (`personas()` je přeskakuje, indexy `v%d` se nemíchají).
- **A4-09** dialog bere masopust a hody z `VillageEvents.is_active`.

### Otevřené body
- Čeká na ruční test uživatele (checklist v odpovědi).
- Příčina propadu po odchodu z obchodu (A1-10) není potvrzena – raycast je jen záplata, log `exit_interior[...]`
  ukáže, jestli uložený bod nesedí s terénem / podlahou.
- Odložené z auditu: A1-14, A1-15, A1-16, A1-19, A3-12 (viz `docs/audit_vlna0.md`).
- Pracovní úkoly na zavřeném místě se od dveří nenabízejí – kdyby směna přesáhla zavírací dobu, bude potřeba výjimka.

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

## 2026-10-06 – Vlna 0d – F2 Doprava

### Hotovo (staticky ověřeno čtením kódu – ruční test čeká)
- **A2-14** `car.gd`: bod trasy se odbaví, až auto překročí rovinu rohu (osa lomu, na rovině kolmice;
  `_ai_advance` / `_ai_passed`), nebo je blíž než `AI_PASS_R` 2,5 m – při seříznutí rohu už cíl nezůstane
  za autem. Cíl se počítá od průmětu auta na jetý úsek dopředu (`_ai_carrot`), nikdy na bod za autem.
- **A2-15** pure pursuit na interpolovaný bod L = clamp(0,6·v + 3, 4, 14) m (`AI_LOOK_*`), za ostrým lomem
  (> `AI_SHARP`) se zbytek L půlí; brzdění podle poloměru zatáčky – boční zrychlení 2–3,5 m/s² podle poloměru
  (dřív podle úhlu lomu, po zaoblení rohů by nesedělo).
- **A2-23** rychlost oblouku musí být dosažena už v tečném bodě (ne ve vrcholu lomu), s reakční rezervou
  `AI_REACT` 0,4 s a plánovaným zpomalením `AI_BRAKE` 2,5 m/s².
- **A2-22** AI přepočítává úhel řízení stejným vzorcem jako řízení hráče (`_max_steer_at` – `steer_hi` /
  `steer_v` z modelu, kolo zvlášť); fyzika hráčova řízení beze změny.
- **A2-18** `_obstacle_ahead` hledá i statickou překážku: druhý průchod kvádrem (vrstva 1, střed 1,3 m nad pruhem,
  šířka 1,5 × half_width) – zásah terénu / asfaltu / štěrku (`AI_GROUND`, meta `surface`) se vyřadí z dotazu
  a úsek se zkusí znovu (`_cast_path`). Dům / strom / plot v pruhu → auto zastaví a po 4 s objede protisměrem;
  délka objíždění nově v metrech (`AI_PASS_LEN` 20 m), ne 4 body (body v zaoblení jsou hustší).
- **A2-16** `road_graph.gd`: `lane_points` nejdřív zaoblí lomy osy ostřejší než ~35° kvadratickou Bézierovou
  křivkou (`_round_corners`, `ROUND_*`; dřív `_cut_hairpins` lomy > 125° mazal a trasa sekla přes zahrady),
  pak posune pruh o offset (`LANE_OFFSET`) s mitre korekcí 1/cos(θ/2) (max 2×, `LANE_MITRE_MAX`).
- **A2-19** `RoadGraph.END_KINDS` (bez service): `Traffic._respawn` volí start i cíl jen na nich (traktor
  `TRACTOR_END_KINDS`), stejně cíl / vzdálený start policejní hlídky (`Police._new_patrol_route`).
- **A2-20** `Traffic._replan`: zaseknuté (`STUCK_S`), dojeté nebo dlouho zablokované (`BLOCKED_S`) auto do 60 m
  od hráče dostane novou trasu z místa, kde stojí (bez teleportu), nejvýš jednou za `REPLAN_COOL_S` 15 s.
- **A2-21** `Car.reroute(points)` – nová trasa za jízdy s odbavením bodů za autem; používá ji policejní
  pronásledování (přeplánování každých 1,5 s), hlídka u hráče a `_replan`.
- **A2-17 data** `tools/clean_road_clashes.py`: nové pravidlo – půdorys budovy proti **ose** silnic z `map.json`
  (pás `AXIS_BUF`: residential / unclassified / living_street 2,0 m, secondary / tertiary 2,6 m, service 0,75 m
  bez posledních 4 m – vjezdy), vyřadí se při zásahu ≥ 1 m² (`AXIS_MIN_M2`; dotyk rohem ne). Místa (`poi`)
  a dům hráče z `buildings.json` se jen vypíšou. Stromy blíž ose než `TREE_AXIS_BUF` (1,7 / 2,3 m). Výpis
  „blízko osy (ponechána)“ k ruční kontrole; vyřazené záznamy zmizí i z `buildings.json` (tentokrát žádný).
  Výsledek nad `data/orig` (vstupy z hlavního checkoutu, výstup před změnou bajtově shodný se stávajícími daty):
  budov 4453 → vyřazeno 125 (dřív 123): navíc **(3319,3; −851,4)** 292 m² (1,0 m od osy residential)
  a **(4033,2; −3180,9)** 332 m² (1,2 m od osy residential); strom **(−2681,8; 2028,4)** 0,9 m od osy.
  Ve hře 4330 → 4328 budov, 51 670 → 51 669 stromů. Nová `walls.bin`, `roofs.bin`, `trees.bin` (ignorované
  v gitu) leží ve worktree `data/` – do hlavního checkoutu je kopíruje uživatel.
- Zjištění k auditu A2-17: příklady (344,7; 44,1) a náves (116,2; 195,1) jsou body **osy service cest** u jejich
  slepého konce (vjezd do dvora) – domy tam stojí 0,6–1,2 m od konce vjezdu, ne v průjezdné silnici. Řeší je
  A2-19 (trasy na service nezačínají ani nekončí); budovy se nemažou. Většina „blízkých“ domů (0,8–2 m) už
  byla vyřazena pravidlem vozovky; buildings.json obsahuje ~13 záznamů bez geometrie (staré DMP kůlny apod.).
- Dokumentace: `docs/DEV.md` (pravidlo osy), `docs/SYSTEMS.md` (Doprava).

### Otevřené body
- Čeká na ruční test uživatele (checklist v odpovědi) – hlavně ostré zatáčky (259; 241), (19; −28), (172; 508)
  a trasa `--cartest` + `--aionly` (360, 240) → (20, −10).
- Vlásenky na „Y“ odbočkách: zaoblení je omezené délkou sousedních úseků (≤ 45 %), takže poloměr bývá jen
  1,5–3 m – auto je projede široce / s couváním. Lepší by bylo plánovat odbočku jinou větví (A* s penalizací lomu).
- Statická překážka zastaví auto i u falešného zásahu (např. sloupek / plot na kraji pruhu) – po 4 s objíždí,
  u hráče po 40 s přeplánuje. Pokud by AI stála „před ničím“, zúžit kvádr (`half_width * 1.5`) nebo zvednout
  `AI_STATIC_LIFT`.
- `kinematic_step` (vzdálená auta mimo bublinu, WIP) odbavuje body dál po 7 m – mimo dohled hráče, nechal jsem.
- 35 budov „blízko osy“ pod prahem (seznam vypisuje nástroj) – případné ruční vyřazení přes `REMOVE_BUILDINGS`.

## 2026-10-06 – Vlna 0d – F1 Létání

### Hotovo (staticky ověřeno čtením kódu + výpočtem – ruční test čeká)
- **A2-01 fyzika pod Joltem**: `Aircraft` zpět na `custom_integrator = true` + `_integrate_forces` (vzor
  `Drone`) – Jolt nepřičítá tlumení ani gravitaci (dřív linear_damp 0,1 COMBINE = fiktivní odpor 0,2·m·v,
  u triku ~1,9 kN). Pojistka DAMP_MODE_REPLACE 0. Krok počítá do pracovních `_xf` / `_v` (podtřídy taky),
  na konci zapíše body state. Zvoleno místo samotného REPLACE 0, protože orientaci a rychlost stejně
  nastavujeme sami a zápis přes state je atomický (žádný teleport `global_transform` mimo krok fyziky).
- **A2-02 kalibrace** (`Aircraft.SPECS`): CD0 = CL_trim/glide − CL_trim²/(π·AR·e), CL_trim = 2·m·g/(ρ·S·v_trim²)
  při plné nádrži → paramotor 0,036, trike 0,048, test_letoun 0,022 (v_trim 13, v_min 9, v_max 18 – staré
  v_trim 11 chtělo náběh 9,7°). Jedna křivka tahu T0·plyn·(1 − 0,5·(v/v_max)²) na zemi i ve vzduchu
  (`_thrust`). Trike tah 1 800 → 1 400 N (stoupání 5,4 m/s sólo / 3,9 se spolujezdcem místo 7,8).
  Auto-trim = tlumený držák rychlosti v_trim (`_trim_alpha`: γ̇ = (ω²·Δv + 2ζω·v̇)/g, L = m·(g·cos γ/cos φ + v·γ̇)
  − T·sin α, ω 0,5, ζ 0,8; Mezerník / Ctrl posune cíl ±30 %) – dřív pevný náběh 4° → po odlepení propad.
- **Ověření výpočtem** (stejné rovnice jako kód, krok 1/60 s, bez větru, plný plyn, plná nádrž):

  | stroj | odlepení | 10 s po odlepení | ustálené stoupání | klouzání bez motoru |
  |---|---|---|---|---|
  | test_letoun 156 kg | 3,1 s, 11,3 m/s | 32 m AGL | 3,4 m/s při 13 m/s | 13 m/s, 1:9,3 (spec 9) |
  | paramotor 121 kg | 2,3 s, 8,8 m/s (wing_up) | 26 m AGL | 2,7 m/s při 10,5 m/s | 10,5 m/s, 1:7,1 (spec 7) |
  | trike 321 kg | 6,0 s, 19,3 m/s (69 km/h) | 41 m AGL | 5,4 m/s při 25 m/s | 25 m/s, 1:8,2 (spec 8) |
  | trike + spolujezdec 401 kg | 8,9 s, 21,5 m/s (77 km/h) | 31 m AGL | 3,9 m/s | 1:8,7 |

  Rovnováha v trimu: L = W při v_trim (paramotor CL 0,73 / α 3,5°, trike CL 0,55 / α 2,5°, letoun CL 0,59 / α 4,9°);
  přebytek tahu T(v_trim) − W/glide = 298 N / 669 N / 392 N → sin γ = 0,25 / 0,21 / 0,26.
- **A2-03** na zemi rychlost vodorovně, náběh = pitch − sklon (`_ground_aero`), rotace na 0,6·a_crit od 0,9·v_min
  vůči vzduchu; valivý odpor ze zatížení zmenšeného o vztlak, aerodynamický odpor i na zemi; vzlet podle rychlosti
  vůči vzduchu (protivítr pomáhá). Palivo hlídá i tah na zemi.
- **A2-04** dosednutí s hysterezí: pod gear_h − 5 cm, klesání vůči terénu < −0,1 m/s, ≥ 0,5 s po odlepení; jinak
  stroj nad terénem jen podržíme. Náraz do svahu = rychlost klesání vůči terénu (tvrdé přistání / havárie).
- **A2-05 / A2-08** `Player.enter_aircraft`: postava otočená o 180°, `visual.ride = a.rider` (vlastní póza každého
  stroje přes `Aircraft.rider_pose`), výstup `ride = {}`, rotace 0. Kamera z kabiny `eye_pos`.
- **A2-06** `vis` posunutý o −gear_h (`_vis_xf`) → modely stojí koly / nohama na zemi; kolizní kvádr 0,25 m nad zemí.
- **A2-07** terén nekoliduje (`add_collision_exception_with(TerrainBody)`; zem analyticky), `_on_body` terén ignoruje
  → bank / hrbol není havárie a okrajové zdi katastru nebrzdí let nad okolím. Vrak dojede analyticky (`_wreck_step`).
- **A2-09** paramotor: na zemi pilot stojí (seat 0, póza stand, běží – `rider_speed`), ve vzduchu sedí v sedačce;
  křídlo s čepem v karabinách leží naplocho za pilotem, nahazuje se obloukem, nahoře kyvadlo; po dosednutí plynule padá.
  Nový model: sedačka, motor s nádrží, klec vrtule z trubek, profilované křídlo s 14 barevnými komorami, šňůry A/C.
- **A2-10** trike: nový vozík (kapotáž, sedadla, stupačky, stožár + přední vzpěra, motor), rogalo s náběžnými
  trubkami, kýlem, kingpostem, prohnutím a zkrutem, horní + spodní plocha s vlastními normálami, A-rám s hrazdou
  a lanky. Spolujezdec viditelný (`Trike._pax_vis` – Humanoid se vzhledem vesničana, vlastní póza). Vysazení po
  přistání `call_deferred` (běží z fyzikálního kroku). Test letoun: hornoplošník s gondolou, tlačnou vrtulí, ocasem.
- **A2-11** `World.ground_height(x, z)` (terén uvnitř, `Surroundings.height_at` venku); používá ho letový model,
  `flight_bounds` (AGL), turbulence, uložení i přestupky.
- **A2-12** `flight_bounds.push` se přičítá k větru (m/s proudění), na zemi se neuplatní.
- **A2-13** trike výchozí intuitivní řízení (W nahoru, A vlevo); Nastavení → „Realistické řízení rogala hrazdou“
  (`GameSettings.trike_realistic`, klíč `rogalo_realisticke`; starý `rogalo_intuitivni` se ignoruje, takže i staré
  nastavení začne intuitivně). Paramotor: Shift před nahozeným křídlem jen varuje (`_shift_warn`), žádný pád.
  Příďové kolo se vizuálně točí na správnou stranu. Nové klávesy žádné.
- **A4-08 (část)** `Trike._law_ul` uděluje `ul_bez_pojisteni` (pojištění `ul_pojisteni`), HUD varování.
- `tests.gd --flighttest`: nová kontrola „10 s po odlepení AGL > 20 m“ (nespuštěno).
- Dokumentace: `docs/CONTROLS.md`, `docs/SYSTEMS.md`.

### Otevřené body
- Čeká na ruční test uživatele (checklist v odpovědi) a `--flighttest` (spouští jen uživatel).
- **Nápověda F1 v `hud.gd`** pořád popisuje trike jako „obráceně: S nos nahoru…“ – hud.gd měnil jiný agent;
  opravit text na výchozí intuitivní (W nahoru, A vlevo; realistické v Nastavení).
- A4-16 (Zetor, ÚCL, souřadnice v `clock.gd`, „Velký Ořechov“) je v auditu v oddílu F1, ale do F1 opravy nebyl
  zadán – nechán pro jiný krok.
- Auto-trim drží rychlost i v zatáčce (víc vztlaku /cos φ) – při velkém náklonu a malém tahu stroj ztrácí výšku;
  laditelné `TRIM_W`, `TRIM_ZETA`, `TRIM_ELEV_V`, `ROT_ALPHA_K` nahoře v `aircraft.gd`.
- Paramotor ve vzduchu: celý vizuál (pilot + křídlo) se klopí o pitch (pár stupňů) – realisticky by visel pilot svisle.

## 2026-10-06 – Vlna 0: ruční test uživatele

### Hotovo
- Uživatel prošel `docs/testy_vlna0.md` (0b, F1–F5 + otevřené body): **vše OK**.
- Po sloučení opraveny chyby překladu (`14a1c58`: duplicitní `cap` v body_state, závorka v game_menu, typy
  `player_world_pos`) a nápověda triku (`4612e71`). Kontrola `godot --check-only` všech skriptů bez chyby.

### Další krok
- Úprava promptů M4 podle `docs/audit_vlna0.md` (oddíl Odloženo) a nápadů z `DALSI DOPLNKY.md`, pak M4 po vlnách.

## 2026-10-06 – M4.1 Řidičská oprávnění a autoškola

### Hotovo (staticky ověřeno čtením kódu a kontrolou překladu – ruční test čeká)
- **Co**:
  - `scripts/permits.gd`: `ridicsky` (skupiny `sub`, `valid_until`, `revoked`), `has(pid, kind, sub)` se zahrnutím (`ZAHRNUJE`: B→AM, A→A2/A1, A2→A1), `revoke / restore / is_revoked / subs / list`, `describe` ukazuje skupiny a odebrání. Nová hra: B + AM. Starý save bez klíče `ridicsky` → B + AM + A (migrace v `from_dict`). Přidány druhy M4.6 do `KINDS`.
  - `scripts/world.gd`: `license_check(id, car)`, hláška při nasednutí bez skupiny, `_auto_jizda_end` (výcvikové jízdy), autoškola (`auto_enroll`, `auto_theory_passed`, `_auto_try_finish`), 12 bodů → `permits.revoke(…, retest=true)` v `commit_offense`.
  - `scripts/police.gd`: `_plan` / `_ticket` – vozidlo bez skupiny → přestupek `rizeni_bez_opravneni`.
  - `scripts/computer.gd` + `computer_ui.gd`: stránka „Autoškola Volant“ (kurzy A1/A2/A/T/AM, přezkoušení skupiny B), eTest `autoskola` (`TESTS` s cestou), stav kurzu `auto_skola` v `to_dict/from_dict` (starý save = bez kurzu).
  - `data/testy/autoskola.json` (26 vlastních otázek, losuje se 20, práh 85 %), `data/zakon.json` řádek `rizeni_bez_opravneni`.
  - `scripts/jobs.gd` `can_apply`: `pozadavky.ridicak` kontroluje `Permits` se skupinou + zákaz.
  - Panel **P** (akce `documents`, `physical_keycode` 80) v `hud.gd` (`open_documents`, `_documents_text`), oddíl „Doklady“ v deníku J, řádek v F1.
- **Laditelné hodnoty**: `World.AUTO_KURZ_KC`, `AUTO_PREZKOUSENI_KC`, `AUTO_JIZD_NUTNE` (3), `AUTO_JIZDA_MIN_M` (300), `AUTO_CIL_M` (30).
- **Ukládání**: klíč `auto_skola` v `computer` (výchozí hodnoty při načítání); `permits` beze změny klíče.
- **Kontrola překladu**: `godot --check-only` na všechny změněné `.gd` – výstup prázdný.

### Otevřené body
- Zkouška s komisařem (chyby: rychlost > 50 v obci, STOP, srážka) – zatím jen 3 výcvikové jízdy s kontrolou místa nástupu/výstupu (rychlost se nekontroluje).
- Odtažení auta domů po přestupku `rizeni_bez_opravneni` – zatím jen pokuta a body.
- Opakované jednání do 2 let (trestný čin § 337 TZ) – neřešeno.
- Sekce `ridicska_opravneni` v `data/zakon.json` (věkové limity, zahrnutí skupin) – zatím jen konstanta `Permits.ZAHRNUJE`.
- Přezkoušení po 12 bodech je zjednodušené (stejný kurz jako nová zkouška, skupina B); M4.2 doplní žádost na úřadě.
- `valid_until` v `Permits` je zatím připravený, nepoužívá se.
- Pořadí teorie/jízd: jízdy se počítají i před teorií; dokončení vyžaduje obojí.

## 2026-10-06 – M4.5 Dobré skutky a přátelství (prosby, dárek, oblíbené)

### Hotovo (staticky ověřeno čtením kódu a kontrolou `godot --check-only` – ruční test čeká)
- **Co**: nový `scripts/favors.gd` (`class_name Favors`, `World.favors`): každý herní den 2–4 vesničané (ze všech 28,
  seed podle dne) nabízí prosbu ze šablon `FAVORS` (zahrada, sníh, nákup); přijetí, plnění přes `emit_game_event`
  (`harvest`, `snow_volunteer`, `gift_given` s typem jídla), odměna (přátelství +15, respekt +3, pověst +2, karma +1),
  nesplněný slib přátelství −10; výhody přátelství ≥ 40 / ≥ 60 (texty v nabídce). Ukládání klíč `favors`
  (starý save = žádné prosby).
- **Co**: `persona.gd` – `likes()` (odvozeno z povolání a koníčku), `dislikes()` (přísné / plaché: tvrdý alkohol),
  `gift_mult()`; `world.gd` – `give_to_npc` násobí přátelství (oblíbené ×2, neoblíbené −1), vesničan má E nabídku
  (`kind "favor"`), `emit_game_event` předává události `Favors`.
- **Kde**: `local_client.gd` `open_favor_menu` (Promluvit / Přijmout prosbu / Dát dárek z inventáře + přátelství a výhody).
- **Ukládání**: `save_game.gd` klíč `favors` (výchozí prázdný při načítání).

### Otevřené body
- Šablona **„Najdi mi ztracenou věc“** a spontánní dobré skutky (vrácení peněženky, úklid odpadků, pomoc při nehodě)
  nejsou – prompt je v minimu jen částečně, zbytek zapsat do M4.5b nebo navázat.
- Dialogové téma „potřebujete pomoct?“ (T) není; prosby se přijímají přes nabídku E.
- Výhody ≥ 40 / ≥ 60 jsou zatím jen text v nabídce; skutečný efekt (`witness_check` z M4.4, varování před kontrolou
  `Police.set_checkpoint`, nošení M2.10, půjčení nářadí) čeká na M4.4 / M5.11.
- Prosby plní „zahrada“ a „sníh“ jakákoli sklizeň / úklid, nerozlišují zadavatele.
- README.md (Ovládání / Systémy) a `docs/CONTROLS.md` zatím nemají nový text E u vesničana – doplnit.
- Čeká na ruční test uživatele (checklist v `docs/testy_M4.md`, oddíl M4.5).

## 2026-10-06 – M4.2 Správní řízení na úřadě, dluhy a exekuce

### Hotovo (staticky ověřeno čtením kódu a kontrolou `godot --check-only` – ruční test čeká)
- **Co**: nový `scripts/debts.gd` (`class_name Debts`, `World.debts`): společná evidence dluhů per hráč – položky
  `{id, kind, text, kc, paid, due_jd, stage, upominka_jd, creditor, ref}`, stavy splatné / upomínka / exekuce / zaplaceno.
  Upomínka po splatnosti (+`REMINDER_FEE` 1 000 Kč, e-mail), exekuce po `ENFORCE_DAYS` 30: strhne z účtu, +`ENFORCE_COST`
  3 000 Kč náklady, pověst −5. Denní krok `advance_to(jd)` z `World._process_impl` i po `skip_time` (po dnech).
- **Co**: `law.gd` `LawRecord.commit` už **nestrhává** pokutu (jen záznam, body, zákaz; `misto` v návratu).
  `World.commit_offense` platí podle `misto`: `na_miste` = bloková pokuta hned z hotovosti, bez hotovosti složenka
  v `Debts` (15 dní); `spravni_rizeni` = příkaz přijde poštou za 1–3 dny (pak dluh se splatností 15 dní); `soud` = dluh
  rovnou. `_on_busted` hlásí, zda je zaplaceno, nebo se příkaz pošle poštou.
- **Co**: úřad – E u úřednice v úředních hodinách „Zaplatit pokuty a dluhy z hotovosti“ (`World.pay_debts_office`).
  Počítač: Banka → Pokuty = seznam dluhů se stavem a splatností, „Zaplatit z účtu“ platí přes `Debts.pay(…, "bank")`.
  Deník J → Úřední záznamy: součet dluhů, otevřené dluhy se stavem, příkazy na cestě.
- **Ukládání**: `save_game.gd` klíč `debts` (per hráč). Migrace: starý `law.unpaid` > 0 → jeden dluh „Nezaplacené
  pokuty (starší)“ se splatností 15 dní od načtení; po načtení `Debts.reset_clock` (nedohání dny z doby uložení).
- **Opraveno proti zadání**: `Computer.unpaid_fines` a deník čtou dluhy z `Debts` (ne z `LawRecord`), takže banka
  a HUD ukazují stejnou částku.

### Otevřené body
- Odpor (8 dní), ústní jednání na úřadě a minihra argumentů – nejsou.
- Papírový dopis do schránky (byt `mailbox`, schránka u rodinného domu) – nejsou; příkaz jde jen e-mailem.
- Bloková pokuta bez volby „Nesouhlasím – správní řízení“ (zatím vždy hotovost, jinak složenka).
- Exekuce: srážka z výplaty (háček v `Jobs`) a „sepsání věci“ vozidla nejsou; strhává se jen z účtu.
- Nahlédnutí do spisu, žádosti na úřadě (vrácení řidičáku, kácení, ohlášení chovu) – nejsou.
- `Debts.pay` a `list` jsou připravené pro M4.3 (trest soudu) a M4.7 (hypotéka, splátky) – zatím se nevolají.
- Čeká na ruční test uživatele (checklist v `docs/testy_M4.md`, oddíl M4.2).

## 2026-10-06 – M4.4 část A: svědci (`witness_check`), nenahlášené činy, oživené řádky

### Hotovo (staticky ověřeno čtením kódu a kontrolou `godot --check-only` – ruční test čeká)
- **Co**: `World.witness_check(id, pos, kind, see_r, hear_r)` (`world.gd`, sekce „svědci (M4.4)“) → kandidáti
  `{node, name, persona, sees, hears, reports}`: vesničané, obsluhy míst, policejní hlídka + zdroje z
  `World.add_witness_source(Callable)` (háček pro M4.6). Vidí: vzdálenost ≤ `see_r` × světlo (den 1 / šero 0,5 /
  noc 0,25) × mlha, zorný kužel ±80°. Slyší: ≤ `hear_r` bez kuželu. Nahlásí: `Weapons.CALL_P` podle povahy,
  přítel ≥ 60 → 5 %, policie vždy. Zkratky `witness_seen` (vidí) a `witness_reported` (nahlásí).
- **Co**: převedeno na jednotný svědek: `Forestry.witness_near` (tenký obal, nově s `id`), `Weapons._witness(id, …)`
  (4 místa), `Cargo._seen_tick` (`witness_seen`), `FireManager._check_law`, `Hunting` (střelba, úlovek), `Fishing`
  (2 místa, s `id`), `Reputation._witnesses` (počítá jen `sees`; npcs loop vypuštěn – keepers jsou v `places`),
  `World.drone_witnessed` (vesničané/obsluhy přes `witness_seen`; hlídka 400 m a kontrola 200 m zůstávají).
- **Co**: nenahlášené činy přesunuty do společného `World.unreported` (`add_unreported`, `pending_offenses`,
  `commit_pending`); `Forestry.pending_offenses / commit_pending` jsou obaly, `Forestry._check_law` píše přes
  `world.add_unreported`. Limit 50 položek na hráče. Nově i nehoda bez svědka (`Police.report_crash`).
- **Co**: oživené řádky `data/zakon.json`: `nehoda_skoda` (2 000–20 000 Kč, 2 body) a `srazeni_chodce` (10 000–40 000 Kč,
  4 body) – uděluje `police.gd` (`report_crash` / `report_hit_person`); `ujeti_policii` má pokutu a body, ale zatím
  se neuděluje. Nové řádky (bez háčku, zatím neudělují): `kradez_uroda`, `vstup_na_cizi_pozemek`,
  `jizda_na_koni_opily`, `chuze_opily_po_silnici`. Všechny s `drb`, `karma`, `par`, „ověřit“.
- **Ukládání**: per-hráč klíč `unreported` na úrovni záznamu hráče (`save_game.gd`); migrace: chybí-li, vezme se
  `forestry.unreported` ze starého save; `forestry` už tento klíč nezapisuje.
- **Kontrola**: `godot --import` (výstup jen šum addonů limboai / state_charts / func_godot bez chyb ve skriptech
  hry, rc 0) a `--check-only` na všech 11 změněných `.gd` – výstup prázdný.

### Otevřené body
- **Část B (vyhlášky: pálení větví, sucho, hluk a nedělní klid) – čeká na vlnu 4.** Úřední deska, vyhlášky,
  vlhkost větví, `Weather.drought`, `World.noise` nejsou.
- Povolení ke kácení (3.2: žádost na úřadě, značka stromu, `permits.grant` s vazbou na strom) – nedělané, navazuje na
  úřad z M4.2; `has_permit(id, "kaceni", pos)` zatím kontroluje jen pozici zóny.
- Raycast na zdi (vrstva 1) v `witness_check` není – dotaz do fyziky mimo fyzikální krok by nebyl bezpečný;
  dohled tedy neblokují budovy.
- `drbna` roznáší drb bez úředního záznamu – zatím jen jako běžný svědek s vyšší šancí nahlášení.
- Hajný a stráže (M4.6) – háček `add_witness_source` je, zdroj zatím není zaregistrován.
- Dohled za šera / v noci snižuje i svědky dronu (dřív pevných 150 m) – záměrné, ale ověřit při hře.
- `ujeti_policii` (konec honičky útěkem v `_end_chase`) a ostatní nové řádky zatím nemají háček (rozlišit útěk).
- `ruseni_nocniho_klidu` rozšířit na motorovou pilu / střelbu / hudbu z auta – nedělané (část B, hluk).
- Nenahlášené činy nejsou ve hře vidět (jen v uložené pozici a v registru) – hajný / policie je později odhalí (M4.6).
- Čeká na ruční test uživatele (checklist v `docs/testy_M4.md`, oddíl M4.4 část A).
## 2026-10-06 – M4.3 Soud a vězení

### Hotovo (staticky ověřeno čtením kódu a kontrolou `godot --check-only` – ruční test čeká)
- **Co**: nový `scripts/court.gd` (`class_name Court`, `World.court`): případ per hráč `{id, oid, name, par, drb, pokuta_max, t,
  stav, summon_jd, trial_jd, obhajce}`. Tok: obvinění (`misto` „soud“ z `World.commit_offense` → `Court.open_case`, žádná
  okamžitá pokuta) → předvolání poštou 3–7 dní od obvinění (`SUMMON_DAYS`), jednání 2 dny po předvolání ve 9:00, příchod
  = hráč do 40 m od dveří úřadu (`ATTEND_RADIUS`, dočasně místo zastávky), okno 2 h → jinak rozhodnutí v nepřítomnosti
  (pokuta ×1,5, zatykač 30 dní přes `wanted_until`, nepodmíněný trest se vykoná až po zadržení).
- **Co**: jednání = menu „Soud“: Přiznat a litovat (+2) / Mlčet (0) / Zapírat (−1) / obhájce 5 000 Kč (+1, `SCORE_*`).
  Skóre dále: recidiva −1 za trest (max −3), pověst ±1 (≥ 30 / ≤ −30), karma ≥ 30 +1. Rozsudek: skóre ≥ 4 podmínka + nižší
  pokuta; 2–3 pokuta + OPP + zákaz řízení (jen dopravní činy); 0–1 pokuta + OPP, u těžkého činu / recidivy nepodmíněný;
  < 0 pokuta ×1,3, u těžkého nepodmíněný, jinak podmínka. Těžký = nejvyšší pokuta z katalogu ≥ 30 000 Kč nebo ≥ 2 předchozí tresty.
  Po jednání 4 h (zatemnění + `skip_time`).
- **Co**: tresty v `data/zakon.json` → `tresty` (rozmezí peněz, OPP, podmínka, zákaz, nepodmíněný trest, měřítko vězení;
  vše „ověřit“). Peněžitý trest → `Debts.add(…, "trest", …)`; `Debts.FINE_KINDS` rozšířeno o „trest“ (platí se na úřadě).
  Zákaz řízení → `Permits.revoke("ridicsky", …, until_jd)`. Podmínka → `Court._probation` (porušení = nový nepodmíněný
  trest na podmíněnou délku). Rozsudek se zapíše do záznamu `records[]` klíčem `rozsudek {druh, delka, do_jd, volba}`.
- **Co**: `law.gd` `LawRecord.criminal_record()` = pohled na záznamy s `trestny_cin` a `rozsudek`; `Jobs._record_clean`
  na něj přepnut (čistý rejstřík se počítá až po rozsudku).
- **Co**: `world.gd` – `_on_busted` rozdělen: záchytka do `_sober_up_cell(id, text)`; u trestného činu (misto „soud“)
  hlášení o obvinění místo pokuty. `World.skip_long(id, days)`: jeden skok času, pověst −20, karma +5, respekt komunit
  −10 (štamgasti +5), dluhy dohnány po dnech, tělo dohnáno max 72 h, událost `jailed` (výpověď z práce).
  Vězení: zatemnění, `skip_long`, teleport k úřadu, pošta se shrnutím.
- **Ukládání**: `save_game.gd` klíč `court` (per hráč), starý save bez klíče = žádné případy.

### Otevřené body
- Autobusová zastávka ve hře není – „odvoz k soudu“ a návrat z vězení jsou dočasně u dveří úřadu (`World.places["urad"]`).
  Doplnit zastávku jako místo (cedule + lavička) a autobus, pak přepnout `Court._at_court`.
- OPP: jen evidence (`Court._opp`: hodiny, lhůta 1 rok). Odpracování úklidem obce (M3.2 úkoly bez mzdy) a přeměna
  nesplněných OPP na trest chybí.
- Podmíněné propuštění v polovině trestu chybí; nepřítomnost → nepodmíněný trest se nevykoná (chybí zatčení policií).
- `World.skip_long`: zahrada a zvířata se dohánějí jen samy s limitem `MAX_CATCHUP_DAYS` (400 / 60) – chybí souhrnný
  úhyn zvířat a uschnutí zahrady; auto (baterie), nájem bytu, nikotin a hmotnost zatím neřeší; tělo jen 72 h.
- Rejstřík trestů není v deníku J / P (`hud.gd` nemá pid); jen data v `Court.status_lines(pid)` a poštou.
- Zákaz řízení po rozsudku: konec zákazu přes `until_jd` v Permits bez přezkoušení (ověřit v ruční hře).
- Háček pro M4.4 (svědci) a M4.6 (pytláctví, nedovolené ozbrojování jako trestné činy) – katalog už `misto: soud`, přes Court projde.
- Čeká na ruční test uživatele (checklist v `docs/testy_M4.md`, oddíl M4.3).

## 2026-10-06 – M4.4 část B: vyhlášky, pálení větví, sucho (částečně)

### Hotovo (staticky ověřeno čtením kódu a kontrolou `godot --check-only` – ruční test čeká)
- **Co**: nový `scripts/vyhlasky.gd` (`class_name Vyhlasky`, `World.vyhlasky`): platnost vyhlášek z katalogu, dávky
  čerstvých větví (`add_fresh`, sušení ~30 dní, za sucha rychleji, za deště pomaleji → `vetve`), `on_fuel` (kouř
  z čerstvých větví → `paleni_mokreho_odpadu`; suché větve za zákazu pálení / sucha mimo dům → `poruseni_vyhlasky_obce`),
  svědek kouře přes `witness_reported` (dohled 200 m), jinak `add_unreported`.
- **Co**: `data/zakon.json` – klíč `vyhlasky` (zakaz_paleni 7–8, sucho od 0,6, nedelni_klid trvale) a přestupky
  `paleni_mokreho_odpadu`, `poruseni_vyhlasky_obce` (s `drb`, `karma`, „ověřit“).
- **Co**: `Forestry._on_lop` dává `vetve_cerstve` (nová položka v `ItemsDB`, hoří 3 min/kus, kouří); `FireManager.add_fuel`
  volá `on_fuel`, nabídka u ohně nabízí i čerstvé větve; `fire.gd` `WOOD_MIN`.
- **Co**: `Weather.drought` (0..1; roste ~0,04/den + 0,01/°C nad 20 °C, klesá deštěm), ve `state()`, uložené v `weather`.
- **Co**: úřední deska (`computer_ui`) = `Computer.NOTICE_BOARD` + platné vyhlášky z `world.vyhlasky.board_lines()`.
- **Ukládání**: klíč `vyhlasky` v záznamu hráče (`{"cerstve": [{n, dny}]}`), výchozí prázdno; `weather.drought` výchozí 0.
- **Kontrola**: `godot --import` (výstup jen chybějící textury addonů, žádná chyba skriptu hry) a `--check-only` na všech
  9 změněných `.gd` (`vyhlasky`, `forestry`, `fire_manager`, `fire`, `items_db`, `weather`, `save_game`, `world`,
  `computer_ui`) – výstup prázdný.

### Otevřené body
- **Hromada klestí** („Složit větve na hromadu“, objekt ve světě) není: sušení běží na dávkách v kapse; dávka nesleduje
  konkrétní kusy (po použití se odečítá od kapsy jen zhruba).
- **Zákaz zalévání z vodovodu**: vodovodní zdroj ve hře není; `Vyhlasky.zalevani_zakazano()` zatím nikdo nevolá.
  Studna a sud s dešťovkou se nemají omezovat (zatím bez háčku).
- **Sucho**: zákaz ohňů mimo pozemek platí jen pro přiložení větví, ne pro zapálení nového ohně; `GrassFire` se za sucha
  zatím nezrychluje; NPC o suchu nemluví (`dialog_themes.gd`).
- **Hluk a nedělní klid**: sdílený `World.noise` (vytažení z `radio.gd`) není, sekačka neexistuje, `nedelni_klid` je
  jen text na desce bez mechaniky.
- **Velké pálení hromady** (povinnost ohlásit hasičům, háček M5.3) není.
- Vyhlášení / zrušení vyhlášky přes poštu a do drbů není.
- Povolení ke kácení (část A, 3.2) stále nedělané.
- Nenahlášený kouř odhalí hajný / policie až později (zatím jen registr `unreported`).
- Čeká na ruční test uživatele (checklist v `docs/testy_M4.md`, oddíl M4.4 část B).

## 2026-10-06 – M4.4 část B doplnění: hluk a nedělní klid (částečně)

### Hotovo (staticky ověřeno – `godot --import` a `--check-only` na `noise_registry`, `world`, `forestry` – výstup prázdný)
- **Co**: nový `scripts/noise_registry.gd` (`class_name NoiseRegistry`; název `Noise` koliduje s nativní třídou Godotu),
  instance `World.noise`. Registr `KINDS`: `motorova_pila` (300 m), `sekacka`, `krovinorez` (nedělní klid), `hudba_auto`,
  `vystrel` (noční klid). `offense_for(kind)` podle času: neděle / svátek (`Clock.weekday()==6` nebo `holiday()`) a hodina
  v `zakazane_hodiny` → `poruseni_nedelniho_klidu`; noc 22–6 h → `ruseni_nocniho_klidu`. `emit(id, kind, pos)` projde
  `World.witness_check(…, hear_r)`: nahlášeno → `commit_offense` + popup; nikdo → `add_unreported` (odhalí hajný / policie);
  sousedé, kteří slyšeli a nenahlásili, ztrácejí náladu (`Persona.add_mood`). Cooldown 60 herních min. na (hráč, přestupek).
- **Co**: `Forestry` sound smyčka (`_process` kácení, jen motorová pila) volá `world.noise.emit` → hluk pily na neděli / svátek
  8–20 h je přestupek. Neměnil jsem existující svědky kácení (`witness_near`) – jde o druhý, doplňkový kanál.
- **Co**: `data/zakon.json` – `vyhlasky.nedelni_klid`: místo `povolene_hodiny` [10,12] nově `zakazane_hodiny` [8,20] (zákaz
  v neděli a o svátcích 8–20 h; roadmapa psala „dopoledních/odpoledních hodinách“ – ověřit OZV). Přestupek
  `poruseni_nedelniho_klidu` (nový řádek, všechna povinná pole, „ověřit“); `ruseni_nocniho_klidu` rozšířen o hudbu z auta,
  výstřel, motorovou pilu v `drb` / `poznamka`.
- **Ukládání**: žádný nový stav – cooldown je jen v paměti (po načtení se může přestupek znovu zapsat). Starý save bez změn.
- **Nezměněno**: `radio.gd` si má vlastní model hluku (sdílený `World.noise` s ním zatím nesdílí; vytažení je otevřený bod).

### Otevřené body
- **Zalévání z vodovodu** (kohoutek u domu): ve hře není vodovodní zdroj; `Vyhlasky.zalevani_zakazano()` zatím nikdo nevolá.
  Samostatný malý krok (interaktivní bod `custom` u domu → `zalevani` → `poruseni_vyhlasky_obce`, když platí `zalevani_zakazano`).
- **Hromada klestí** („Složit větve na hromadu“): velký objekt ve světě, zůstává otevřený (sušení běží na dávkách v kapse).
- **Sekačka** neexistuje (roadmapa M4.4 / M3.2); v registru je připravená, nikdo ji zatím nevolá. **Hudba z auta** a **výstřel**
  jsou v registru bez volajícího (zbraně mají vlastní zákon v `Weapons` / M4.6).
- **Radio** (`radio.gd`) si drží vlastní model; přesun na `World.noise` až se bude dělat M5.9 (autorádio).
- **Sousedé** nenahlášený hluk nerozšiřují do drbů ani do úřední desky; vyhlášky poštou a v drbech zůstávají otevřené.
- **Noční klid** se zatím vyhodnocuje jen pro registrované činnosti (dnes žádná, viz výše).
- Čeká na ruční test uživatele (checklist v `docs/testy_M4.md`, oddíl „M4.9b – M4.4 B doplnění“).

## 2026-10-06 – M4.7 Katastr: koupě a prodej nemovitostí

### Hotovo (staticky ověřeno čtením kódu a kontrolou `godot --check-only` – ruční test čeká)
- **Co**: nový `scripts/katastr.gd` (`class_name Katastr`, `World.katastr`): parcely z `Fields.class_at` na mřížce 100 m
  uvnitř domácího katastru (`meta.boundary` z `data/map.json`, mimo okolní obce), smyšlená čísla parcel, třídy orná / louka /
  sad / zahrádky s cenami za m² (tabulka `PARCEL_KC_M2`); domy = rodinné domy z `Estate` (ne usedlost, ne domov, ne byty).
- **Co**: `World.in_home_cadastre(pos)`; inzeráty se mění po týdnech (deterministický výběr `hash([id, týden])`).
- **Co**: kupní smlouva = platba ceny + poplatek 1 500 Kč hned, vklad do katastru za 20 herních dní (`pending`, pošta
  „Vklad proveden“). Prodej parcely obci hned za 60 %. Nabídka vlastního domu kupci: kupec se ozve za 3–20 dní podle ceny,
  peníze v hotovosti. Domov jde nabídnout jen po odstěhování. „Nastavit jako domov“ = `Estate.set_home` + `World.apply_home`.
- **Co**: `Estate.set_estate_owner` nastavuje vlastnictví budov; `local_client.gd` → `open_katastr_menu()` z nabídky úřadu
  (jen když je úřad otevřen).
- **Ukládání**: globální klíč `katastr` v `save_game.gd` (`houses`, `parcels`, `pending`), výchozí prázdno; starý save bez klíče
  se načte (nikdo nic nevlastní).
- **Kontrola**: `godot --import` (výstup jen chybějící textury addonů) a `--check-only` na `katastr`, `world`, `save_game`,
  `local_client` – výstup prázdný.

### Otevřené body
- Hypotéka (splátky přes `Debts`, zástava, exekuce zpět za 70 %) není; pronájem domu (nájemník) není.
- Vlastnictví nemá zatím vliv na kácení, sklizeň ani chov (`Forestry.zone_at`, `Garden`); cizí pozemek = přestupek (M4.4) není.
- Cedule „Na prodej“ u domů a polí, téma v rozhovoru, zvýraznění parcely na mapě M nejsou.
- Vklad a prodej nejdou zrušit; prodej domu jen hotovostí; nepřihlašuje se k bance.
- Parcely jsou mřížka 1 ha bez ohledu na hranice pozemků a budovy; neřeší se překryv s budovami.
- Výkup obcí a nabídka kupci nemají vliv na pověst / vztahy s vesničany (M7).
- Čeká na ruční test uživatele (checklist v `docs/testy_M4.md`, oddíl M4.7).
## 2026-10-06 – M4.6 Zbraně, lov a rybolov podle zákona (část: doklady, hajný, rybářská stráž)

### Hotovo (staticky ověřeno čtením kódu a kontrolou `godot --import` + `--check-only` na všech změněných `.gd` – výstup prázdný; ruční test čeká)
- **Co**: nový `scripts/gamekeeper.gd` (`class_name Gamekeeper`, Node3D, procedurální kapsle): dvě instance – `World.gamekeeper`
  (myslivecký hajný, obchůzka po lesích kolem chaty, `Fauna.random_point(..., "forest")`, výstřel `gunshot` / `poaching` slyší do
  1 500 m s šancí 70 % a jde na místo činu na 240 s) a `World.rybar_straz` (rybářská stráž, obchůzka jen so/ne 5–12 h).
  Kontrola: hráč do 15 m s podezřelým stavem (hajný: zbraň nebo nelegální úlovek na rameni / u těla; stráž: rybaření), cooldown 90 min.
  Menu: „Ukázat doklady“ (přestupek `pytlactvi` / `rybarske_pytlactvi`, u pušky bez zbrojního `police_check` = zabavení),
  „Zapírat“ (stejné přestupky), „Utéct“ (`wanted_until` +120 min, policejní hláška).
- **Co**: svědci přes `World.add_witness_source` (`witness_candidates`, jen na službě); role `hajny` v `witness_check` hlásí vždy
  (vedle `policie`).
- **Co**: doklady u myslivecké chaty (`interactables` u dveří chaty, `World.interactables`): kurzy zbrojní 4 000 Kč, lovecký 5 000 Kč,
  rybářský 1 000 Kč (zaplacení → `_kurz[pid][druh]`), povolenka k lovu 1 500 Kč / 30 dní (vyžaduje lovecký lístek), povolenka k rybolovu
  1 800 Kč / 365 dní (vyžaduje rybářský lístek). Ladicí hodnoty v `Gamekeeper.PRICES`, `POV_DAYS`.
- **Co**: eTesty `zbrojni`, `lovecky`, `rybarsky` → `data/testy/zbrojni.json`, `lovecky.json`, `rybarsky.json` (8 vlastních otázek,
  `prah_pct` 75, „ověřit“). `Computer.record_test` volá `World.gamekeeper.test_passed(pid, id)` → doklad se vydá **jen po zaplaceném kurzu**.
- **Co**: `permits.gd` – `has()` respektuje `valid_until` (prošlá povolenka neplatí), nová `renew(pid, kind, until_jd, no)`.
- **Ukládání**: klíč `gamekeeper` (`{"kurz": {...}}`) v `save_game.gd`, výchozí prázdno při načtení starého save; doklady a platnost
  už ukládá `permits`.
- **Úpravy sdílených souborů** (malé, jen vlastní řádky): `world.gd` (deklarace, vytvoření + `add_witness_source`, role `hajny`,
  `emit_game_event` → `gamekeeper.on_event`, `interactables`), `save_game.gd`, `computer.gd` (TESTS cesty + háček), `permits.gd`.
- **Dokumentace**: `docs/testy_M4.md` (oddíl M4.6, 10 bodů), odškrtnuto v `docs/VIZE_A_ROADMAPA.md` a `prompts/roadmapa/README.md`
  (s poznámkou „částečně“).

### Otevřené body
- **Kontrola kufru policií** (`police.gd`: prohlídka kufru, náklad bez `doklad_puvod`, zbraň viditelná) – nedělané.
- **Rybářská stráž**: obchůzka je po okolí chaty, ne po úsecích vody (`Water`); zabavení udice a úlovku nedělané.
- **Hajný**: bez zabavení luku/kuše a bez zápisu pověsti −20 / respektu `zemedelci` −20 (jen přes `commit_offense` z `data/zakon.json`).
  Pachatel bez úlovku a bez výstřelu (jen zbraň) se kontroluje jen přes zbraň.
- **Zbrojní průkaz**: střelnice (praktická zkouška) a lékařský posudek nejsou; doklad = kurz + eTest.
- **Povolenky** nejsou v panelu P (`hud.gd` `DOC_KINDS` jen základní doklady – hud.gd patří M4.7, nechal jsem ho být).
- **Vizuál**: NPC je zatím jednoduchá procedurální kapsle (ne `Humanoid`); bez animací a bez raycastu na zdi při vidění.
- **Čeká na ruční test uživatele** (checklist v `docs/testy_M4.md`, oddíl M4.6).

## 2026-10-06 – M4.8 Návykové látky (obsah pro dospělé; částečně)

### Hotovo (staticky ověřeno: `godot --import` + `--check-only` na každý změněný skript, bez chyb; ruční test čeká)
- **Co – brána obsahu**: `GameSettings.adult_content` (`nastaveni.cfg`, sekce `obsah`, klíč `dospeli`, výchozí vypnuto),
  zaškrtávátko v `pause_menu.gd` (`_set_adult` → `ItemsDB.adult_on`), `World.adult_ok()`. `ItemsDB.hidden(id)` skryje
  předměty s `adult: true` (`exists`, `by_type`, `use_item`, řádky obchodu v `local_client._shop_item_row`, eŠuplík přes
  `computer.gd` eŠuplík přeskakuje skryté položky z OFFERS).
- **Co – předměty** (`items_db.gd`, oddíl M4.8): `tabak_semena`, `tabak_susene` (typ `smoke`, 1 cigareta, nikotin),
  `konopi_semena` (průmyslová odrůda, nízké THC), `konopi_kvety` (typ `smoke`, klíč `thc`), `lysohlavky` (typ `food`, klíč `psilo`).
- **Co – zahrada** (`garden.gd`): plodiny `tabak` (výsev IV–V, 90 dní) a `konopi` (IV–V, 110 dní) v `CROPS` s `adult: true`,
  `crop_visible(k)` filtruje výsev a nabídku cedule. Při výsevu konopí `World.witness_reported(…, "pestovani", 25 m)` →
  `commit_offense(id, "nedovolene_pestovani")`.
- **Co – obchod** (`place.gd`): `tabak_semena` 45 Kč, `konopi_semena` 60 Kč v Potravinách (jen při volbě). Cigarety zůstávají jen v Potravinách.
- **Co – tělo** (`body_state.gd`): `thc` a `psilo` (poločas 1,5 h / 3 h, `THC_SPEED` = zpomalení v `speed_mult`, nevolnost
  při vysoké hladině), `smoke_thc()`, `dose_psilo()` (volá `eat()` přes klíč `psilo`). `player._begin` volí `smoke_thc`
  u položek s `thc`, jinak nikotin. Uložení: `save_game.gd` BODY_KEYS `thc`, `psilo` (starý save → 0).
- **Co – HUD** (`hud.gd`): řádek „Pod vlivem THC – …“ / „psilocybinu – …“ v přehledu těla.
- **Co – zákon** (`data/zakon.json`, `prestupky`): `nedovolene_pestovani`, `prechovavani_navykove_latky`,
  `rizeni_pod_vlivem_navykove_latky` – čísla s poznámkou „NEOVĚŘENO – ověřit“.
- **Zdroj právního stavu (ověřeno WebSearch 2026-10-06, sekundární zdroje, neověřeno v úředním znění)**: novela
  207/2025 Sb. (účinnost 1. 1. 2026) mění 40/2009 Sb.: držení doma do 100 g sušiny legální, 100–200 g přestupek, nad 200 g trestný
  čin; mimo domov do 25 g legální, 25–50 g přestupek, nad 50 g trestný čin; pěstování do 3 rostlin legální (THC > 1 %),
  4–5 rostlin přestupek, nad 5 trestný čin. Zdroje: energozrouti.cz (článek „Pravidla pro pěstování konopí se od letoška
  změnila“), cnn.iprima.cz („Konopí už není trestný čin… přehled změn od roku 2026“). Úřední znění ještě neověřeno.
- **Dokumentace**: `docs/testy_M4.md` (oddíl M4.8, 10 bodů), `README.md` (doložka „Obsah pro dospělé“).

### Otevřené body (M4.8 zůstává `[ ]`)
- **Sušák** (objekt v kůlně / na půdě, vlhkost, plíseň) chybí: sušený tabák a konopí se dostanou přímo ze sklizně.
- **Ubalení** (akce „ubalit“ z papírků) chybí; konopí jako jedlá varianta (pečení) chybí.
- **Lysohlávky – sběr** (sezónní předmět v lese, vzor `hrib`, riziko záměny s jedovatou houbou, dovednost) chybí: ve hře se nedají sehnat.
- **Držení konopí při prohlídce** (M4.6 kufr/kapsy) a **test na drogy** v `police.gd` (`breath_test`) nejsou napojené;
  `rizeni_pod_vlivem_navykove_latky` je jen v datech.
- **Efekty obrazu** psilocybinu (`DrunkFx`, nové uniformy v `drunk.gdshader`, vypínatelné) nejsou; HUD ukazuje jen stav.
- **Zákonná čísla** nejsou ověřena v úředním znění; `poznamka` v `zakon.json` to říká.
- **Dluhy a pokuta** za `nedovolene_pestovani` jdou přes `commit_offense` (místo úřad); zatím neověřeno hrou.
- Prodej látek NPC záměrně neimplementován (hra nenabádá).

### Změněné soubory
`scripts/game_settings.gd`, `scripts/pause_menu.gd`, `scripts/items_db.gd`, `scripts/garden.gd`, `scripts/place.gd`,
`scripts/local_client.gd`, `scripts/body_state.gd`, `scripts/player.gd`, `scripts/save_game.gd`, `scripts/world.gd`,
`scripts/hud.gd`, `scripts/computer.gd`, `data/zakon.json`, `docs/testy_M4.md`, `README.md`, `PROJECT_LOG.md`.

### Čeká na ruční test uživatele (checklist v `docs/testy_M4.md`, oddíl M4.8).

## 2026-10-06 – Uzavření M4 Zákon a společnost (k závěrečné kontrole)

### Stav kroků
- Hotovo: M4.1 řidičák a autoškola, M4.2 správní řízení a dluhy, M4.3 soud a vězení, M4.5 dobré skutky a přátelství, M4.7 katastr.
- Částečně (zůstávají `[ ]`): M4.4 (část A svědci hotová, část B vyhlášky jen částečně – chybí hluk, nedělní klid, zalévání z vodovodu, hromada klestí), M4.6 (chybí kontrola kufru policií, zabavení udice, střelnice a posudek), M4.8 (chybí sušák a ubalování, sběr lysohlávek, test na drogy v policii, efekty psilocybinu; čísla zákona neověřena v úředním znění).

### Kontrola
- `godot --import` rc 0, `--check-only` nad všemi 153 skripty v `scripts/`: bez chyb.
- Ruční testy zatím neproběhly. Checklist po krocích je v `docs/testy_M4.md`; uživatel testuje až po celé M4.

### Otevřené body (souhrn)
- Viz oddíly „Otevřené body“ u jednotlivých kroků výše. Pro závěrečnou kontrolu Opus 5.5 hlavně: sloučení `world.gd` a `save_game.gd` (ruční úpravy v několika vlnách), napojení `Court` / `Debts` / `witness_check` a klíče v savu.

## 2026-10-06 – Závěrečná kontrola M4 (Opus 5.5)

### Hotovo (kontrola překladu + čtení kódu – ruční test čeká)
- **Rozsah:** `git diff 23deab2..HEAD -- scripts data` (~2 900 řádků, 38 souborů): Permits, Law, Debts, Court, witness_check,
  Favors, Vyhlasky, Katastr, Gamekeeper, M4.8 a úpravy ve sdílených souborech. Existence a podpisy volaných funkcí ověřeny grepem.
- **`data/zakon.json`:** všech 64 řádků má `nazev, zakon, par, pokuta, misto, trestny_cin, poznamka, drb, karma` (doplněny
  `drb`/`karma` u 6 řádků `ul_*` z vlny 0); každé doslovné `commit_offense("…")` i id z proměnných (hajný, vyhlášky, policie,
  záchytka) míří na existující řádek; `misto` jen `na_miste` / `spravni_rizeni` / `soud`.
- **Opravené chyby:**
  - M4.8 řádky měly `misto: "urad"` → `commit_offense` je poslal **k soudu** (větev `_`). Data → `spravni_rizeni`;
    `commit_offense` nově volá Court jen při `misto == "soud"`, neznámé `misto` = správní řízení.
  - `Permits`: zákaz řízení od soudu (`revoke` s `until_jd`, bez přezkoušení) **nikdy neskončil** → `_active_revoke`
    (po `until_jd` neplatí; odebrání za 12 bodů s přezkoušením trvá do autoškoly). `license_check`, `auto_enroll` a panel P
    rozlišují zákaz a přezkoušení (během soudního zákazu se nedá platit „přezkoušení“).
  - `Court`: podmínka nevypršela (každý pozdější čin = porušení) → kontrola `do_jd` + mazání v `tick`; `from_dict` vkládal
    prázdné `{}` → deník „Podmínka do 0“ / „OPP zbývá 0 h“; jednání se zavřeným menu zůstalo navždy „u soudu“ → rozsudek
    v nepřítomnosti po 15:00 / dalším dni; dvojí volba během zatemnění → stav `porada`.
  - `SaveGame`: starý save bez `debts` nechal dluhy z hrané pozice → `from_dict` vždy; `thc` / `psilo` se před načtením nulují.
  - `Vyhlasky`: nenahlášený kouř ukládal `pos` jako Vector3 (JSON → řetězec) → pole `[x, y, z]`; vlastní pozemek = usedlost
    i dveře domova (byt, koupený dům).
  - `Forestry`: odvětvení dávalo jen čerstvé větve a jiný zdroj suchých není → podpal nešel ~30 dní. `LOP_DRY_SHARE` = ⅓ suchých.
  - `Police.report_crash`: každý náraz (i pád z kola na silnici) před svědkem = pokuta za nehodu → bez přestupku u
    `silnice/cesta/terén`, prodleva `CRASH_CD_MIN` 60 herních minut.
  - `Garden`: hlášení konopí už od 1. rostliny, ač data říkají „do 3 legální“ → `KONOPI_LEGAL` = 3.
  - `Katastr`: inzeráty mohly nabídnout budovu statku (vlastník v Estate) → filtr `owner_of`.
  - `Gamekeeper`: menu přes `cl.hud` (porušení toku zpráv) → `World.notify(id, "open_menu", …)`.
  - Panel P: povolenky k lovu / rybolovu s platností (otevřený bod M4.6), soudní zákaz s počtem dní.
- **Ukládání:** všechny nové klíče (`debts`, `court`, `favors`, `gamekeeper`, `katastr`, `unreported`, `vyhlasky`,
  `weather.drought`, `computer.auto_skola`, `body.thc/psilo`, `permits` s migrací B+AM+A) se ukládají i načítají
  s výchozí hodnotou; starý save (před M4) projde – migrace `law.unpaid_fines` → jeden dluh, `forestry.unreported` → společný registr.
- **Právní zásady:** nové texty bez reálných jmen, značek a obcí (úřady, soud, spolky, autoškola „smyšlené“);
  M4.8 jen za volbou „Obsah pro dospělé“ (výchozí vypnuto, `ItemsDB.hidden` v obchodě, eŠuplíku i inventáři).
- Checklist regresí: `docs/testy_M4.md` → „Závěrečná kontrola M4 – opravené chyby“.

### Otevřené body (beze změny, k M4.9)
- M4.4 B (hluk, nedělní klid, zalévání z vodovodu, hromada klestí), M4.6 (kufr, zabavení udice, střelnice, posudek),
  M4.8 (sušák, sběr lysohlávek, test na drogy, efekty obrazu; čísla zákona NEOVĚŘENO).
- Rozsudek v nepřítomnosti s nepodmíněným trestem se nevykoná (chybí zatčení); OPP jen evidence.
- `witness_check` bez raycastu (zdi nebrání dohledu); hajný = kapsle bez animací.
- `Jobs`: rejstřík čistý i během obvinění (záměr M4.3); výpověď z práce při vězení přes událost `jailed`.

## 2026-10-06 – M4.6 doplnění (kufr policií, udice u rybářské stráže, zkouška střelbou, lékařský posudek)

### Hotovo (staticky ověřeno čtením kódu a kontrolou `godot --import` + `--check-only` na `cargo.gd`, `police.gd`, `gamekeeper.gd` – výstup prázdný; ruční test čeká)
- **Co (kufr policií)**: `police.gd` `_trunk_search(pl)` – při zastavení v autě řidiče s šancí `TRUNK_CHECK_P` (0,35, ladit): zbraň mimo ruku bez zbrojního oprávnění → `World.weapons.police_check` (zabavení, přestupek `nedovolene_ozbrojovani` přes zákon); nelegální úlovek (`Carcass.legal == false`) v kufru → `commit_offense("pytlactvi")`. Nález jde do banneru. Zjednodušení: zbraň se „v kufru“ počítá jako zbraň v inventáři mimo ruku (hra zatím neumí zbraň do kufru uložit).
- **Co (cargo)**: `cargo.gd` `vehicle_items(car)` – čtení nákladu v kufru / na ložné ploše (kopie seznamu).
- **Co (udice u stráže)**: `gamekeeper.gd` – rybářská stráž při zjištění rybaření bez lístku a povolenky hned zabaví udici (`Fishing.ROD_TOOLS`) a ryby (tabulka druhů → `item`) z inventáře, ukončí relaci (`Fishing.cancel`), zapíše přestupek `rybarske_pytlactvi` (rejstřík, deník J → Zákon) a událost `item_seized`. Menu se u stráže už neotevírá (bez volby hráče, „Nechat být“ nelze obejít). Hajný se chová beze změny.
- **Co (posudek)**: `gamekeeper.gd` `_posudek` – lékařský posudek 1 500 Kč (`POSUDEK_PRICE`, orientačně, ověřit) v menu chaty; uložen do `_kurz[id]["posudek"]` (klíč `gamekeeper` už existuje). Zbrojní kurz bez posudku nejde.
- **Co (střelnice)**: `_shot_test` – alternativa k eTestu: po zaplaceném kurzu a posudku se posuzuje posledních 5 ran na střelnici u chaty (`ShootingRange.scores`); aspoň 4 rány s ≥ 5 body → doklad `zbrojni`. Konstanty `SHOT_RUN`, `SHOT_MIN_PTS`, `SHOT_NEED`.
- **Ukládání**: žádný nový klíč v `save_game.gd` (posudek a zkouška jsou v existujícím klíči `gamekeeper`, zabavení a kufr nejsou stav). Starý save se načte beze změny.
- **Dokumentace**: `docs/testy_M4.md` (oddíl „M4.9a – M4.6 doplnění“, 10 bodů), `docs/VIZE_A_ROADMAPA.md` a `prompts/roadmapa/README.md` – M4.6 zůstává `[ ]` s přesným popisem zbytku.

### Otevřené body
- **Hajný**: bez zabavení luku / kuše a bez pověsti −20 / respektu `zemedelci` −20 (jen přes `commit_offense`).
- **Rybářská stráž**: obchůzka je kolem chaty, ne podél úseků vody (`Water`).
- **Panel P**: povolenky k lovu / rybolovu se v panelu P ještě neukazují (`hud.gd`, patří M4.7).
- **Zbraň v kufru**: hra zatím neumí uložit zbraň do kufru; policie ji zabaví jen z inventáře mimo ruku.
- **Lékařský posudek**: zjednodušeně v chatě (v roadmapě je u úřadu jako „posudek“) – čísla ověřit.
- **Čeká na ruční test uživatele** (checklist v `docs/testy_M4.md`, oddíl „M4.9a – M4.6 doplnění“).

## 2026-10-06 – M4.8 zbytek a zahrádkář Ladislav (obsah pro dospělé; zůstává `[ ]`)
- **Zahrádkář** (`scripts/npc_grow.gd`, `NpcGrow`, `World.npc_grow`): záhon za chatou (`Place "chata"` door + offset),
  výsev IV–V jednou za rok, 110 dní, sklizeň jen jako počet rostlin v `state` (nic do inventáře). Vizuál jen při zapnuté
  volbě. Svědci přes `World.witness_reported(…, "pestovani", 25)`, hláška hráči; následky pro NPC zatím nejsou.
  Klíč `npc_grow` v `save_game.gd` (starý save = žádný záhon). Profil Ladislava: `hobby_adult` (jedna věta, `dialog.gd`).
- **Sušák**: čerstvá sklizeň tabáku / konopí (`tabak_cerstvy`, `konopi_cerstve`) → po `SUSENI_DAYS` = 14 dnech suchý předmět
  přes `Vyhlasky.add_batch` (stejná logika jako větve). Zjednodušeně: bez objektu sušáku, bez vlhkosti a plísně.
- **Test na drogy** (`police.gd`, `_drug_test`): při dechové kontrole s šancí `DRUG_TEST_P` 0,6; pozitivní při THC ≥ 0,5
  nebo psilocybinu ≥ 0,3 (zástupné hodnoty, ladit) → `rizeni_pod_vlivem_navykove_latky`. Jen při zapnuté volbě.
- **Držení v kufru**: `_trunk_search` → při konopí / tabáku / lysohlávkách v inventáři `prechovavani_navykove_latky`
  (zjednodušeně: nezkoumá množství vůči zákonu).
- **Obraz psilocybinu**: `DrunkFx` přidá jemné vlnění přes stávající uniform `drunk` (max. 0,5), jen při zapnuté volbě.
  Samostatný přepínač efektů ve Nastavení zatím není.
- **Kontrola překladu**: `godot --headless --path . --import` (exit 0) a `--check-only` na všechny změněné `.gd` – bez chyb.
- **Zdroje právního stavu**: nic nového neověřeno v úředním znění; čísla v `data/zakon.json` zůstávají „NEOVĚŘENO“.

### Otevřené body (M4.8 zůstává `[ ]`)
- **Ubalení** (akce „ubalit“ z papírků z Potravin) chybí; jedlá varianta konopí chybí.
- **Lysohlávky – sběr** v lese (sezónní předmět, vzor `hrib` v `World.SEASON_ITEMS`, placement v `meta["items"]`,
  riziko záměny, dovednost) chybí; ve hře se nedají sehnat.
- **Efekty obrazu**: samostatný přepínač „Efekty obrazu“ ve Nastavení chybí (teď jen vázané na volbu pro dospělé).
- **Zahrádkář – následky**: nahlášení nemá pro Ladislava žádný důsledek (přestupek / pokuta / zabavení rostlin).
- **Sušák** bez objektu a bez vlhkosti / plísně (zjednodušeno).
- **Zákonná čísla** nejsou ověřena v úředním znění (`poznamka` v `zakon.json`).
- **Čeká na ruční test uživatele**: `docs/testy_M4.md`, oddíl „M4.9c – M4.8 a zahrádkář“.

## 2026-10-06 – M4.9 Dokončení částí M4 (uzavření)

- Sloučeno do `main`: M4.4 B doplnění (`849273f`, hluk a nedělní klid), M4.6 doplnění (`6540889`, kufr policie, zabavení udice,
  posudek a zkouška střelbou), M4.8 zbytek a zahrádkář Ladislav (`1fe35a8`, konopí na záhonu jen za volbou pro dospělé, sušák,
  test na drogy, držení v kufru, obraz psilocybinu).
- Cheat menu (F2 → Hráč → „Cheat: libovolný předmět z katalogu…“), skryté adult položky se nabízejí jen při zapnuté volbě (`13ef33b`).
- Kontrola překladu všech 155 skriptů: `godot --import` rc 0, `--check-only` bez chyb.
- Stav milníků: M4.1, M4.2, M4.3, M4.5, M4.7 hotové. M4.4, M4.6, M4.8 zůstávají `[ ]` s přesným zbytkem (viz výše a oddíly v `docs/testy_M4.md`).
- Otevřené body: zalévání z vodovodu (není vodovodní zdroj), hromada klestí, sekačka, ubalení, sběr lysohlávek, samostatný přepínač efektů obrazu,
  následky nahlášení u zahrádkáře, zákonná čísla NEOVĚŘENO, hajný bez zabavení luku/kuše.
- Ruční testy: podle `docs/testy_M4.md` (všechny oddíly M4.1–M4.9c). Regresní oddíl „Závěrečná kontrola M4“ na konci.

## 2026-10-06 – Kontrola zákonných čísel M4

- `data/zakon.json`: u všech 65 přestupků v `prestupky` a u bloku `tresty` je `poznamka` označena `NEOVĚŘENO` a obsahuje "Ověřit aktuální znění" (u tří drogových položek s uvedeným sekundárním zdrojem zůstává jejich původní zdroj). Nic dalšího se nemění (hodnoty, paragrafy, logika).
- Kontrola `commit_offense`: všechna literální id ve `scripts/` existují v `zakon.json`; dynamicky skládaná id (`_offense`, `_law_offense`, `_smoke`, `commit_pending`, `police._recent`) pocházejí z literálů, které také existují.
- Nesrovnalosti k ruční opravě (nebyly měněny): položky `pg_noc`, `pg_mraky`, `ul_noc`, `ul_mraky`, `ul_pristani_mimo`, `ul_bez_pojisteni` mají `par` jen "ověřit" (chybí §); `strelba_v_obci` a `zbran_pod_vlivem` mají "ověřit číslo § v novém zákoně o zbraních"; `vyhlasky` (`sucho`) nemá poznámku. Horní klíče (`body_limit`, `zakaz_za_body_h`, `body_odpocet` …) nemají vlastní poznámku, kryje je `overeno`. Položky `alkohol_do_1`, `ruseni_nocniho_klidu` aj. mají zákon+§ bez ověření.
- Kontrola překladu se netýká (měněn jen JSON, žádný .gd).
## 2026-10-06 – M4.4 B zbytek: hromada klestí (zalévání z vodovodu zapsáno jako otevřený bod)

### Hotovo (staticky ověřeno čtením kódu a `godot --check-only` – ruční test čeká)
- **Co**: nový `scripts/klesti.gd` (`class_name Klesti`, `World.klesti`, instance v inicializaci `World` vedle `vyhlasky`):
  hromada klestí 3 m vpravo od dveří domu (jen vlastník domu, `Estate.owns_house`), cíl `klesti_hromada` (`World.register_target`,
  `data.pid`), vizuál z `MeshKit` (suché tmavé, čerstvé světlé). Vzniká líně z `_process` (každé 2 s pro hráče ve `World.players`).
- **Co**: akce `slozit_vetve` (čerstvé `vetve_cerstve` i suché `vetve` z kapsy na hromadu; čerstvé schnou `Vyhlasky.DRY_DAYS`,
  za sucha rychleji, za deště pomaleji – stejné ladění jako `Vyhlasky`) a `vzit_vetve` (max. `Klesti.MAX_TAKE` = 20 suchých do kapsy)
  v `actions.gd` (`DEFS`), handlery a kontroly cíle v `klesti.gd`.
- **Co**: ukládání klíč `klesti` (`{cerstve: [{n, dny}], suche}`) v `save_game.gd` (výchozí prázdno); poloha se odvozuje z domu.
- **Kontrola**: `godot --import` a `--check-only` na `klesti`, `actions`, `world`, `save_game` – výstup prázdný.

### Otevřené body
- **Zalévání z vodovodu** (kohoutek u domu): neřešeno – ve hře není vodovodní zdroj a přidání interaktivního bodu u domu + napojení
  na `Vyhlasky.zalevani_zakazano()` je samostatný malý krok (`poruseni_vyhlasky_obce`, svědek soused). Zatím bez háčku.
- **Hromada u bytu**: byt nemá pozemek, hromada tam není (cíl jen pro `owns_house`).
- **Dávky ve `Vyhlasky`**: fresh dávka v kapse po odložení na hromadu zůstane v `Vyhlasky.batches` a při zrání převede jen
  kusy, které hráč právě nese (jako dnes) – drobné časové zkreslení, když hráč mezitím nasbírá nové čerstvé větve.
- **Hromada nehoří sama**: zapálení celé hromady a hlídání velkého pálení (háček M5.3) zůstává otevřené.
- **Sekačka, hudba z auta, výstřel** v registru hluku bez volajícího (zbytek části B, mimo tento krok).
- Čeká na ruční test uživatele (checklist v `docs/testy_M4.md`, oddíl „M4.4 B zbytek – hromada klestí“).
## 2026-10-06 – M4.6 zbytek (hajný zabavuje luk a kuši, rybářská stráž hlídá úseky vody; zůstává `[ ]`)

### Hotovo (staticky ověřeno čtením kódu a kontrolou `godot --import` + `--check-only` na `scripts/gamekeeper.gd` – výstup prázdný; ruční test čeká)
- **Co – hajný, luk a kuše**: `Gamekeeper._issues` (role `hajny`): při nelegálním úlovku u hráče, který má v inventáři luk nebo kuši
  (`_bows`, konstanta `BOWS`), se přestupek `pytlactvi` nahradí přestupkem `pytlactvi_luk_kuse` (jen jeden zápis) a luk / kuše se
  zabaví přes `_apply` (`remove_item`, položka `zabavit`). Bez úlovku se luk nezabavuje, nelegální není sám o sobě.
- **Co – pověst a respekt**: `Gamekeeper._bow_seized` (volá se z `_apply` jen při skutečném zabavení luku / kuše hajným) – `Reputation.change(-20)`
  a `Reputation.change_respect("zemedelci", -20)`; ladicí hodnota `BOW_REP`. Přestupek zůstává přes `World.commit_offense` (karma, rejstřík).
- **Co – rybářská stráž, úseky vody**: `Gamekeeper._pick_patrol` u role `straz` volá nové `_water_point()` – náhodný bod na
  `World.water.streams` do `WATER_PATROL_R` (1 200 m) od chaty (`WATER_TRIES` pokusů); když žádný není, stará obchůzka.
  Kontrola a zabavení udice / úlovku zůstává stejná jako dřív (`_issues`, `_apply`).
- **Úprava**: `_apply` volá `world.fishing.cancel(id)` jen když hráč skutečně rybaří (`sessions.has(id)`), aby zabavení luku nic nerušilo.

### Otevřené body
- **Panel P u povolenek**: povolenky nejsou v `hud.gd` `DOC_KINDS` (hud.gd patří M4.7) – nechat otevřené.
- **Zbraň v kufru**: policejní kontrola kufru (`police.gd`) s puškou / nelegálním úlovkem – nechat otevřené (viz předchozí záznam M4.6 doplnění).
- **Stráž a rybníky**: obchůzka jde jen po potocích a řece (`streams`), rybníky (`ponds`) a `Water.info_at` se v obchůzce nepoužívají.
- **Hajný**: zabavení luku bez úlovku (jen držení luku v lese) se nevyvolává; bez zápisu do rejstříku za pouhé nošení luku.
- **Čeká na ruční test uživatele** (checklist v `docs/testy_M4.md`, oddíl M4.6 zbytek).

### Změněné soubory
`scripts/gamekeeper.gd`, `docs/testy_M4.md`, `PROJECT_LOG.md`.
## 2026-10-06 – M4.8 zbytek (ubalení, jedlé konopí, lysohlávky, efekty obrazu, zabavení na záhonu; zůstává `[ ]`)
- **Ubalení a pečení** (`items_db.gd` `ItemsDB.RECIPES`, `player.gd` `craft` / `craft_ok`, tlačítka v detailu předmětu v `hud.gd`):
  papírky (`papirky`, Potraviny, `adult`) + sušený tabák `tabak_list` → cigareta `tabak_susene` (1 ks, nikotin přes `smoke()`);
  papírky + sušené konopí `konopi_susene` → joint `konopi_kvety` (THC). Jedlá varianta: konopí + rohlík → `konopne_pecivo`
  (`thc_eat` 0,8; nástup se zpožděním 1 h – `BodyState._thc_later`, neukládá se → otevřený bod).
- **Sušák přepsán na materiály**: `garden.gd` CROPS `tabak.item = tabak_list`, `konopi.item = konopi_susene` (sušák dává suroviny na ubalení, ne hotový předmět).
- **Lysohlávky (sběr)**: `world.gd` `SEASON_ITEMS["lysohlavky"]` (doy 244–320, regrow 10), `_add_lysohlavky` (každý 4. hřib, seed 1704, na konec `meta["items"]`
  jako šípky), `_item_present` vrací false při vypnuté volbě (předmět existuje, ale je neaktivní; přepnutí se projeví při nejbližším `refresh_season_items`).
  `_houba_druh`: záměna s muchomůrkou `LYSOHLAVKY_ZAMENA_P` 0,3, klesá s dovedností `myslivost` (×0,2 při úrovni 20); správný nález = +4 XP.
  Muchomůrka (`muchomurka`, `toxic` 1,0) při snědení: nevolnost + zdraví (`BodyState.MUSHROOM_TOXIC_HP` 12). Vizuál v `item.gd`, počítadlo v `hud.gd`.
  Dovednost: zvolena existující `myslivost` (ne nová „houbaření“, aby se při vypnuté volbě neobjevil řádek v deníku).
- **Efekty obrazu**: `game_settings.gd` `image_fx` (klíč `obraz/efekty`, výchozí zapnuto), `DrunkFx.enabled` (static), `pause_menu.gd` `_set_image_fx`;
  `DrunkFx._process` při vypnutí jen skryje ColorRect. Nezávisle na `adult_content`; psilocybinový příspěvek zůstává za volbou pro dospělé.
- **Zahrádkář – následek**: `npc_grow.gd` `_sow`: nahlášení svědkem → `zabaveno = true`, `rostliny = 0` (záhon prázdný, bez vizuálu rostlin).
  Pokuta NPC zvolena nebyla (NPC nemá rejstřík zákona). Klíč `zabaveno` v `state` (starý save = false).
- **Police**: `_drugs_carried` počítá i `konopi_susene`, `tabak_list`, `konopne_pecivo`.
- **Dokumentace**: `docs/testy_M4.md` – oddíl „M4.8 zbytek“ (10 bodů).
- **Kontrola překladu**: `godot --headless --path . --import` a `--check-only` na každý změněný .gd (viz výsledek v hlášení).

### Otevřené body (M4.8 zůstává `[ ]`)
- Zpožděné THC z pečiva se neukládá do savu (při F5/F9 ztraceno). Doplnit klíč v `save_game.gd` a převod.
- Zákonná čísla (`nedovolene_pestovani`, `prechovavani_navykove_latky`, `rizeni_pod_vlivem_navykove_latky`) pořád NEOVĚŘENO v úředním znění.
- Sušák bez objektu sušáku a bez vlhkosti / plísně (zjednodušeno).
- Pokuta NPC zahrádkáři nezavedena (zabavení místo ní).
- README (Systémy / Nastavení / Ovládání: „Efekty obrazu“) a `docs/VIZE_A_ROADMAPA.md` neaktualizovány – zadání mělo „nic dalšího neměnit“.
- Ubalení a pečení jsou okamžité (bez animace a bez oven / kamen).
- Čeká na ruční test uživatele: `docs/testy_M4.md`, oddíl „M4.8 zbytek“.

## 2026-10-06 – Vlna 0 M4 sloučena do main (dokončení zbytků)

- Sloučeno: M4.4 B zbytek (`4011f90`), M4.6 zbytek (`d56eeae`), M4.8 zbytek (`145fd20`), kontrola zákonných čísel (`4b4fca1`).
- Konflikty jen v `PROJECT_LOG.md` a `docs/testy_M4.md` (ponechány obě části).
- Kontrola překladu nad celým `main`: `godot --import` rc 0, `--check-only` na všech `scripts/*.gd` bez chyb.
- M4.4, M4.6, M4.8 zůstávají `[ ]` s otevřenými body (vodovod, panel P u povolenek, zbraň v kufru, ubalení / sušák bez objektu,
  zákonná čísla NEOVĚŘENO). Ruční test čeká spolu s M5 (uživatel testuje až po celé M5).

## 2026-10-06 – M5.9 Rocková rádia (částečně; zůstává `[ ]`)

### Hotovo (staticky ověřeno čtením kódu – ruční test čeká)
- **Co**: `README.md` → Právní zásady → Rádio: doplněna poznámka, že další stanice (Rock Radio, Radio Beat, Rock Zone) se
  zatím nepřidávají, dokud nebude souhlas provozovatelů nebo jiné ověřené řešení. `data/radia.json` a `scripts/radio.gd` beze změny.
- **Ověřeno čtením**: `radio.gd` `_ready()` načítá jen záznamy s `url` a `name`; `genre` a `noise` mají výchozí hodnoty;
  stanice bez funkční URL nespadne, `_start_stream` jen spustí ffmpeg, a když stream nejde, `_pump_stream` po ~12 s přehrávání
  ukončí (bez výjimky). Chybějící ffmpeg hlásí `world.notify` (existující hláška).

### Otevřené body
- **Nově přidané stanice nejsou.** Zadání zakazuje reálné názvy rádií a smyšlená stanice nemá veřejný stream, takže Rock Radio,
  Radio Beat ani Rock Zone nebyly zapsány do `data/radia.json`, ani nebylo dohledáno jejich URL. Rozhodnutí: uživatel buď
  povolí reálné názvy s ověřenými URL (a souhlas / právní poznámka), nebo se stanice nahradí smyšlenými s vlastním zdrojem zvuku.
- Stávající záznamy ČRo v `data/radia.json` zůstávají beze změny (mimo tento krok); k rozhodnutí podle právní poznámky.
- **Autorádio (bod 5 zadání) nezpracováno** – sdílení `Radio.stations` / přehrávání do `car.gd`, ovládání 1–5 / 0, hlasitost,
  hluk v noci, ukládání stavu auta. Vyžaduje samostatné okno (`radio.gd` 757 ř., `car.gd` ~1600 ř., ověření kláves v `local_client.gd`).
- **Vnitřní světlo v autě (bod 6 zadání) nezpracováno** – `OmniLight3D` v kabině, dveře `World.enter_car` / `exit_car`, ruční klávesa `car_lights`.
- Nesahalo se do `world.gd` ani `save_game.gd` (žádný nový stav ukládán).
- Ruční test: rádio doma (ČRo stanice) a chování bez internetu – čeká na uživatele (checklist v `docs/testy_M5.md`).
- Kontrola překladu: `godot --import` (viz odpověď subagenta); žádné změněné `.gd`, `--check-only` tedy nebyl potřeba.
## 2026-10-06 – M5.7 Skateboard s animacemi (část: jízda, ollie, pády, uložení)

### Hotovo (staticky ověřeno kontrolou překladu – ruční test čeká)
- **Co**: skateboard jako režim pohybu hráče (`Player.board_on`, B varianta z promptu), nová položka `skateboard` (typ `gear`, 1 890 Kč, 2,5 kg) v `items_db.gd`.
- **Ovládání**: F (když hráč nic nejede a má desku v inventáři) = stoupnout; znovu F = seskok (jen při rychlosti pod 2 m/s, jinak hláška). W = odraz (+1,5 m/s, do 6 m/s po rovině, z kopce víc), S = brzda patou, A/D = zatáčení podle rychlosti, Mezerník = ollie (vertikální 3,2 m/s). Klávesy beze změny registru (F, W/S/A/D, Mezerník jsou obsazené už dřív).
- **Fyzika** (`player.gd`: `_board_step`, `board_mount`, `board_dismount`, `_board_build`): jízda z kopce přes složku tíhové síly na svahu, valivý odpor a horší brzdění na mokru / trávě (`_ground_traction`), boční skluz se utlumí, nad 12 m/s kmitání, nad 15 m/s pád (`fall(1.5, "pad_skate")`), náraz do zdi nad 3 m/s pád, přepadnutí dopředu na nekluzkém povrchu při rychlosti nad 2,5 m/s.
- **Skóre**: čistý ollie (dopad rovně, svah do 25°) +10 b., `board_score` / rekord `board_best`; signál `game_event` „skate_trick“ (kind `skate_trick`, data `name`, `pts`, `score`).
- **Model**: procedurální deska 80 × 20 cm se čtyřmi kolečky (BoxMesh / CylinderMesh), `top_level`, sleduje nohy hráče.
- **Uložení** (`save_game.gd`): klíč `skate` = `{best}`, výchozí 0 při načtení starého savu. Stav „na desce“ se po načtení nezachovává (hráč jde pěšky).
- **World** (`world.gd`, `player_action("car_enter")`): větev seskoku / stoupnutí před existující větví pro koně, auto a letoun (stoupnutí jen tehdy, když žádné vozidlo ani kůň v dosahu).

### Otevřené body
- Triky kickflip, shove-it, manual, grind a 180 nejsou (jen ollie); skóre se zatím nezobrazuje v HUD (jen signál `skate_trick`).
- Animace hráče na desce (odraz, balanc paží, póza na desce, IK nohou na desce) nejsou – hráč stojí normálně, deska je pod ním.
- Deska ležící ve světě (F u ležícího prkna, položení před sebe) není – deska zůstává v inventáři.
- Dovednost `skateboarding` (M0.3) v kódu není, takže XP se nepřipisuje. Stížnosti sousedů (hluk v noci, jízda mezi lidmi) nejsou.
- Nákup v e-shopu / stavebninách (M3.4 / M5.1) není napojen; test přes F2 → Hráč.
- README (Systémy → Skateboard, Ovládání), `docs/VIZE_A_ROADMAPA.md` a `prompts/roadmapa/README.md` neaktualizovány (ponecháno pro společný commit / kolizi s M5.9).
- Čeká na ruční test uživatele: `docs/testy_M5.md`, oddíl „M5.7“.

## 2026-10-06 – M5.9 Autorádio a vnitřní světlo v autě (body 5–6 kroku; zůstává `[ ]` kvůli rockovým stanicím)

### Hotovo (staticky ověřeno čtením kódu + kontrola překladu – ruční test čeká)
- **Co – autorádio**: `radio.gd` má nový příznak `car_mode` (bez modelu lampového rádia, bez štítků na stupnici, zvuk
  z palubní desky). Stejná třída `Radio` (stejné stanice `stations`, ffmpeg stream, šum, hudba, zlost sousedů)
  – auto nemá vlastní kopii logiky. `car.gd`: `ensure_radio(w)` vytvoří rádio až při nástupu do auta s kabinou
  (ne kolo, motorka, traktor – `two_wheeler`, `model.kind`, `builder == "tractor"`); uzel `AutoRadio` na palubní desce.
- **Ovládání za volantem** (`local_client.gd` → `World.player_action` → `Car.car_action`): **1–5** = předvolby
  (první pět stanic seznamu), **0** = vypnout, **Shift + kolečko** = hlasitost ±1. Klávesy 1–5 jsou za volantem
  předvolby (jinak rychlé sloty opasku beze změny). Mimo auto zůstává kolečko kamery a 0 nedělá nic.
- **Co – vnitřní světlo**: `car.gd` `OmniLight3D` „VnitrniSvetlo“ (teplá barva, dosah 4 m, bez stínů), vzniká až při
  prvním použití. `World.enter_car` / `exit_car`: za šera a v noci (`clock.daylight() < 0.5`, tj. slunce pod ~−1°)
  se rozsvítí na `Car.CABIN_DOOR_S` = 10 s. Ruční přepnutí **F4** (`car_cabin_light`, `toggle_cabin_light`):
  zůstane svítit, dokud ji hráč nevypne nebo nerozjede auto (> 3 m/s, i ruční světlo zhasne).
- **Uložení**: `save_game.gd` – u vozidla nový klíč `radio` (jen pokud auto rádio má); při načtení se rádio vytvoří
  a `Radio.from_dict`. Starý save bez klíče = bez rádia. `SaveGame.VERSION` beze změny.
- **Kontrola překladu**: `godot --headless --path . --import` (rc 0) a `--check-only` na `radio.gd`, `car.gd`,
  `world.gd`, `local_client.gd`, `save_game.gd` – výstup prázdný.

### Otevřené body
- **Rockové stanice** dál nejsou přidány (čeká na rozhodnutí uživatele – viz předchozí záznam M5.9).
- **Dokumentace**: README → Ovládání (F4, 0–5 za volantem, Shift+kolečko), nápověda F1 (`hud.gd`) a registr kláves
  (`00_SPOLECNE` kap. 5.7: F4 a 0 zabrány) zatím nejsou upraveny – nebylo součástí zadání „nic dalšího neměň“.
- Vnitřní světlo a rádio se nezobrazují na jiných vozidlech (AI traffic, cizí hráči) – auto rádio vzniká jen u auta, které
  hráč řídil. Hlasitost autorádia při jízdě obcí v noci je napojena na stávající model hluku (`_consequences`), ruční test chybí.
- Hlášky o ovládání po nástupu (`enter_car`) nerozšířeny o nové klávesy; checklist v `docs/testy_M5.md`.
- Nepouští se ffmpeg ani hra; test přehrávání v autě a noční hluk ověří uživatel.

## 2026-10-06 – M5.12 Pouliční osvětlení a světelný smog

### Hotovo (staticky ověřeno čtením kódu – ruční test čeká)
- **Co**: nový klientský `scripts/priroda/street_lights.gd` (`StreetLights`, vzniká v `LocalClient.attach` po `World.build()`):
  - lampy podél silnic v obci (`residential`, `tertiary`, `unclassified`, `living_street`; `service` a `track` ne), ~35 m,
    střídavě po stranách, deterministicky (seed 12), mimo křižovatky (`JUNCTION_GAP` 9 m) a mimo ostatní silnice
    (`World.dist_to_roads`), max. 320 lamp; model `PropModels.street_lamp()` v MultiMesh, bez stínů a bez kolize
    (rozhodnutí: lampy jsou jen vizuál, žádná kolize).
  - svítící hlavice: MultiMesh s jasem v instance custom data, shader `EMISSION = barva * jas * 5` (vidět z dálky).
  - pool `OmniLight3D` (16 kusů, bez stínů) jen u nejbližších svítících lamp k kameře do 620 m; počet podle předvolby
    `GameSettings.preset`: 0 → 0, 1 → 8, 2–3 → 16.
  - rozsvícení při `Clock.is_night()`, zhasnutí za svítání; přechod 3 s reálného času, každá lampa s náhodným zpožděním
    0–20 s; úsporný režim 0–4 h: každá lichá lampa zhasnutá (konstanty `NIGHT_SAVE_FROM/TO`).
  - index světelného smogu `pollution` (Gaussova jádra σ 170 m kolem kamery z jasu lamp, normalizováno k návsi = 1).
- **Obloha**: `shaders/sky.gdshader` – uniform `light_pollution`: vyšší práh hvězd a slabší hvězdy, teplý opar při
  horizontu v noci, nasvícení zataženého neba zespodu. `scripts/priroda/atmosphere.gd` – `light_pollution` (cíl) se
  plynule přebírá (`_lp`, 0,4 za s).
- **Napojení**: `scripts/local_client.gd` – var `street_lights`, vytvoření v `attach`, předání `pollution` do `Atmosphere`
  v `_update_daylight`. `world.gd` a `save_game.gd` beze změny (stav lamp plyne z hodin a seedu, nic se neukládá).
- **Kontrola překladu**: `godot --headless --path . --import` (rc 0; první pokus s limitem 300 s vypršel, druhý s 900 s
  prošel) a `--check-only` na `street_lights.gd`, `atmosphere.gd`, `local_client.gd` – výstup prázdný.

### Otevřené body
- **Rozbitá lampa** (zásah zbraní / kamenem, `Prop.damaged`, svědek M4.4, oprava obcí za pár dní) není hotová.
- **Světelný smog**: nezapočítávají se svítící okna domů; příspěvek okolních obcí (`World.obce`, nad obcemi světlý
  opar na horizontu) není; Mléčná dráha (pás hvězd) není.
- **F2 → Počasí** přepínač „Světelný smog ×0 / ×1 / ×2“ není; grafická volba počtu světel je jen podle předvolby.
- **Drb / hláška vesničana** o Mléčné dráze není.
- **Dokumentace**: README (Systémy → Svět / noc, Ladicí parametry), nápověda, VIZE a `prompts/roadmapa/README.md` nejsou
  upraveny (zadání: neměnit `prompts/roadmapa/README.md` a `docs/VIZE_A_ROADMAPA.md`).
- Výkon na návsi v noci (FPS) změřit ručně; lampy jsou bez LOD kromě `visibility_range_end`.
