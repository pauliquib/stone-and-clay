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
