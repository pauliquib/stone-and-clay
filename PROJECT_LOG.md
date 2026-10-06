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
