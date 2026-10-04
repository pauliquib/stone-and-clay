# M1.2 – Okna, dveře a komíny na budovách

> Roadmapa „Život na vsi“ · **M1 Živý svět** · krok 2/6
> Předpoklady: žádné (M1.1 doporučeno) · Navazují: M1.3 (kouř z komínů), M1.4–M1.5 (interiéry – dveře)

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md` (kap. 3 – soukromí: žádné průhledy do reálných domů)
2. `docs/VIZE_A_ROADMAPA.md` – kap. 4.1 „Budovy“
3. `tools/export_map.py` – jak vznikají `data/walls.bin` a `data/roofs.bin` (grep `walls`, `roofs`, `def `) – **jsou to spojené meshe po dlaždicích 256 m, bez informace o jednotlivých domech**
4. `scripts/map_loader.gd` – `load_chunks`, `add_chunks`; `scripts/world.gd` ~ř. 125–145 (materiály stěn / střech)
5. `tools/landuse.py` – vzor, jak se v Pythonu čte OSM (`geodata/pbf/zlinsky-latest.osm.pbf`, `osmium`) a převádí do souřadnic hry
6. `scripts/priroda/village_events.gd` – `_facade_lights` (vzor: jak se dnes hledá fasáda paprskem)
7. `scripts/mesh_kit.gd` (API)

## 1. Proč
Budovy jsou dnes „krabice“ se střechou – bez oken, dveří a komínů. Chceme uvěřitelnou vesnici:
okna (v noci některá svítí), dveře, komíny (z nich v M1.3 půjde kouř). **Styl obecný**, žádná kopie
skutečných fasád; okna neprůhledná (sklo s odrazem / záclonou), nikdy průhled do interiéru.

## 2. Co udělat
1. **Data budov** – nový nástroj `tools/buildings.py` → `data/buildings.json`:
   pro každou budovu z OSM (`building=*`) v katastru: `id`, půdorys (polygon v souřadnicích hry –
   stejná transformace jako v `landuse.py`/`export_map.py`), výška stěn (odvoď z `walls.bin` – nejvyšší
   vrchol uvnitř půdorysu – nebo z dat, která už export má; zjisti grepem v `export_map.py`), typ
   (`house`, `garage`, `shed`, `barn`, `church`, `public`…), plocha. Budovy, které hra už má jako místa
   (`data/pois.json` – `osm_id`), označ `poi: klíč`. Dům hráče (`meta["domov_hrace"]`) označ `home: true`.
   **Nástroj napiš a nespouštěj** (uživatel spustí a commitne JSON). Kód hry musí bez souboru fungovat (nic nepřidá).
2. **Generátor fasád** `scripts/building_details.gd` (`class_name BuildingDetails extends Node3D`):
   - pro každou stěnu (hranu půdorysu) delší než ~2,5 m rozmísti okna po ~2,6–3,2 m (šířka 1,0–1,2 m,
     výška 1,2–1,4 m, parapet 0,9 m nad podlahou), u vyšších budov druhé podlaží; malé budovy (garáž,
     kůlna < 25 m²) jen jedno okénko nebo žádné; na delší straně k silnici (nejbližší bod `World.dist_to_roads`)
     **dveře** (0,9 × 2,0 m) + schod; u garáží vrata.
   - okno = rám (MeshKit box, bílá / hnědá / zelená okenice náhodně podle seed = id budovy), sklo tmavé
     s mírným leskem (sdílený materiál), záclona (světlý pruh v horní třetině) – **neprůhledné**,
   - **komín**: na domech (`house`) 1 komín na střeše – pozice nad středem hřebene posunutá, výška podle střechy
     (paprsek shora na `roofs.bin`, vrstva 1 – najdi výšku střechy v daném bodě); ulož `chimney_pos` pro M1.3,
   - všechno přes `MeshKit` do **jednoho meshe na dlaždici 256 m** (málo draw callů), `visibility_range_end`
     ~ 450 m, stín jen zblízka,
   - **noční svícení oken:** druhá sada quadů s emisním materiálem; které okno svítí, určí seed + čas
     (večer 17–22 h víc, noc málo, ráno 5–7 některá); přepočet každé herní půlhodiny, bez per-okno uzlů
     (MultiMesh s instance custom data nebo 2 meshe „svítí/nesvítí“ na dlaždici – vyber jednodušší),
   - API: `func chimneys_near(pos: Vector3, r: float) -> Array` (pro M1.3), `func door_of(building_id) -> Vector3` (pro M1.4).
3. **Zapojení:** `World` vytvoří `BuildingDetails` po načtení mapy, jen když `data/buildings.json` existuje.
   Budovy míst (`pois`) a domov: dveře na pozici `door_x/z` z `pois.json` (ať sedí s interakcí E).
4. **Kolize:** okna a komíny bez kolizí (jen vizuál), dveře zatím bez funkce.

## 3. Mimo rozsah
Kouř (M1.3), otevírání dveří a interiéry (M1.4), textury fasád (zůstává stávající materiál stěn).

## 4. Hotovo, když
- Domy mají okna, dveře a komíny, garáže vrata, kůlny málo oken; žádný průhled; v noci část oken svítí.
- Bez `data/buildings.json` hra funguje beze změny. FPS se výrazně nezhorší.

## 5. Návrh checklistu ručních testů
1. `python3 tools/buildings.py` → `data/buildings.json`, výpis počtu budov podle typu.
2. `./run.sh` → u domu hráče a v obci: okna, dveře k silnici, komíny na domech.
3. Přibliž se k oknu → sklo neprůhledné, záclona.
4. F2 → Denní doba 20:00 → část oken svítí; 03:00 → skoro žádná; 06:00 → některá.
5. Hospoda, Potraviny: dveře tam, kde je interakce E.
6. Garáž / kůlna → vrata / okénko, žádný komín.
7. FPS v obci podobné jako dřív.

## 6. Závěr
README (Systémy → Budovy, „Jak vzniká mapa“ – nový nástroj), VIZE odškrtnout, roadmapa README, PROJECT_LOG,
deník AI, commit „M1.2 Okna, dveře, komíny: …“, checklist a čekat.
