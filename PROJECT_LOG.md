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
