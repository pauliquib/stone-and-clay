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
