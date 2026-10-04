# M1.1 – Terén bez satelitního snímku (procedurální materiály)

> Roadmapa „Život na vsi“ · **M1 Živý svět** · krok 1/6
> Předpoklady: M0.1 (textury evidovat v registru) · Navazují: M1.2 (budovy), M6.2 (terén za okrajem mapy)

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md`
2. `docs/VIZE_A_ROADMAPA.md` – kap. 4.1 „Terén bez satelitu“
3. `shaders/terrain.gdshader` (celý, ~100 ř.) a `scripts/terrain.gd` (celý, 236 ř.)
4. `tools/landuse.py` (docstring – formát `data/landuse.bin`, třídy 0–4) a `scripts/priroda/fields.gd` (jak se nastavuje `landuse_tex`)
5. `scripts/map_loader.gd` – `build_trees` (odkud jsou pozice stromů) a `scripts/fauna/fauna.gd` – `_build_habitat`, `forest_at` (hustota lesa z `trees.bin` v mřížce 32 m – **tu můžeš znovu použít**)
6. `scripts/world.gd` řádky ~120–150 (materiály silnic a cest `asphalt.bin`, `gravel.bin`)
7. `README.md` → „Jak vzniká herní mapa“ a „Licence dat“

## 1. Proč
Uživatel chce terén **bez satelitního snímku** (ortofota). Důvody: vzhled jako hra (ne rozmazaná fotka),
žádné reálné detaily soukromých dvorů (soukromí – viz právní zásady), méně licenčních závazků.
Tvar terénu (DMR 5G) zůstává.

## 2. Současný stav
- Barva terénu = `ortho_full` / `ortho_core` (ČÚZK) + šum detailu + úprava „zelené hnědnou“ podle
  `grass_green` + pole z `landuse_tex` + sníh a mokro (globální uniformy).
- Třídy povrchu, které máme: `landuse.bin` (orná půda, louka, sad, zahrádky), silnice / cesty jsou vlastní
  meshe nad terénem, les lze odvodit z hustoty stromů, voda z `water.json` (koryta vyhloubená), budovy z `roofs.bin`.

## 3. Co udělat
1. **Maska povrchu** – nový nástroj `tools/surface.py` (vzor `tools/landuse.py`, stejný rastr 4 m, zarovnání
   na `x0, z0` z `data/map.json`) → `data/surface.bin` (magic `SURF`, verze 1, 1 B na buňku), třídy:
   `0 tráva/louka (výchozí)`, `1 orná půda`, `2 sad/zahrada`, `3 les (podrost, jehličí, listí)`,
   `4 zástavba/dvůr (udusaná hlína, dlažba)`, `5 břeh/mokřad`, `6 skála/strmý svah (dopočte shader)`,
   `7 polní cesta (OSM track bez vlastního meshe)`.
   Zdroje: `landuse.bin` (1, 2, louky), `trees.bin` / hustota stromů (3 – práh laditelný), OSM `landuse=residential`
   a okolí budov do 8 m (4), `water.json` ± 3 m od osy (5), OSM `highway=track|path` bez meshe (7).
   Nástroj napiš a popiš v README; **nespouštěj** – uživatel ho spustí a výsledný `data/surface.bin` commitne.
   Do doby, než soubor existuje, musí shader umět fallback (viz 3).
2. **Textury:** potřebujeme dlaždicové textury (albedo + normála, případně roughness) pro trávu, hlínu/ornici,
   lesní podrost, udusanou hlínu/štěrk, bahno a skálu. Přednostně **CC0 z Poly Haven / ambientCG** –
   do `textures/` (styl stávajících `*_diff_2k.jpg`). **Nestahuj je sám** – napiš do `ASSETY.md` / logu
   přesný seznam (název textury na Poly Haven, rozlišení 1k–2k) a v kódu použij `AssetLib.has` →
   když chybí, použij procedurální barvu + šum (`detail_noise`). Evidence v `assets/LICENSES.md`.
3. **Shader** `shaders/terrain.gdshader`:
   - nový `uniform sampler2D surface_tex` + `surface_rect` (vzor `landuse_tex`), textura se vzorkuje
     triplanárně jen na strmých svazích (skála), jinak planárně (world XZ, měřítko 3–6 m),
   - **prolínání** tříd: hranice buněk 4 m rozbít šumem (jako u polí) a smíchat 2 nejbližší třídy,
   - svah z normály: nad ~35° skála / hlína, nad ~20° méně trávy,
   - variace barvy velkým šumem (skvrny sušší / sytější trávy), mikro-detail zblízka jako dnes,
   - zachovat: pole z `field_lut`, `grass_green` (sezóna – teď na **třídě tráva/louka**, ne na zelenosti fota),
     `snow_cover`, `wetness`, `meadow_bloom`,
   - **přepínač** `uniform bool use_ortho = false` – ortofoto zůstane dostupné pro porovnání
     (F2 → nový řádek „Terén: ortofoto / procedurální“ – přes `World` / `Terrain.set_ortho(on)`),
   - fallback: když `surface_tex` chybí, třída = z `landuse_tex` + hustota lesa (pokud je dostupná jako textura)
     + výchozí tráva.
4. **Vzdálené LOD:** v LOD 3 (32 m) jen barva třídy bez textur (výkon).
5. **Minimapa M** dnes možná používá ortofoto – ověř (`hud.gd _draw_map`, grep `ortho`). Pokud ano,
   přidej variantu vykreslenou z `surface.bin` (barvy tříd), aby šlo ortofoto odstranit úplně.
6. **Dokumentace:** README (Jak vzniká mapa, Licence dat – ortofoto se ve výchozím stavu nepoužívá),
   `BLENDER_UPRAVY.md` pokud zmiňuje ortofoto jako texturu terénu. **Soubory ortofota nemaž** – smazání
   až po schválení uživatelem (zapiš jako otevřený bod).

## 4. Mimo rozsah
Travní stébla / 3D tráva (lze později), okraj mapy (M6.2).

## 5. Minimum
Shader s procedurálními barvami podle `landuse_tex` + hustoty lesa + svahu, přepínač ortofoto, bez `surface.py`.

## 6. Hotovo, když
- Ve výchozím stavu není ortofoto vidět; louky, pole, les, zástavba, břehy a svahy mají odlišný vzhled,
  hranice nejsou čtverečkované, roční období a sníh fungují.
- F2 přepne na ortofoto a zpět. Minimapa funguje bez ortofota.

## 7. Návrh checklistu ručních testů
1. (Pokud existuje nástroj) `python3 tools/surface.py` → vznikne `data/surface.bin`, výpis tříd v %.
2. `./run.sh` → u domu: tráva, dvůr, cesta; žádné fotografické skvrny aut / střech na zemi.
3. F2 → Teleport → do lesa: lesní podrost; na pole: pole s plodinou podle data.
4. Strmý svah u potoka → skála / hlína; břeh potoka vlhký.
5. F2 → Roční období: leden (sníh), červenec, říjen – rozdíly jsou vidět.
6. F2 → Terén: ortofoto → vzhled jako dřív; zpět → procedurální.
7. M (mapa) → čitelná mapa i bez ortofota.
8. Výkon: FPS podobné jako dřív (F1 / FPS na HUD).

## 8. Závěr
VIZE odškrtnout M1.1, roadmapa README, PROJECT_LOG (seznam textur ke stažení, otevřený bod „smazat ortofoto
po schválení“), deník AI, commit „M1.1 Terén bez ortofota: …“, checklist a čekat.
