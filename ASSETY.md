# Assety z internetu – legálně a s evidencí

Registr: [`assets/LICENSES.md`](assets/LICENSES.md) (a strojová kopie `assets/licenses.json`).
Do hry patří **jen CC0 / public domain a CC BY (s uvedením autora)**, viz README → „Právní zásady obsahu“.

## Kde hledat
- **Modely a textury:** Poly Haven, ambientCG, Kenney, Quaternius (CC0); Poly Pizza, Sketchfab
  (filtr *Downloadable* + licence CC0 / CC BY).
- **Zvuky a hudba:** Freesound (filtr CC0 / CC BY), OpenGameArt (CC0 / CC-BY / OGA-BY).
- **Licenci kontroluj u každého souboru zvlášť** – balík může mít smíšené licence. Nejasné = nepoužít.

## Checklist před použitím
1. Licence dovoluje **komerční šíření a úpravy**? (Ne: NC, ND, „personal use“, bez licence.)
2. Nutné uvést autora (CC BY)? → záznam se objeví v titulcích automaticky.
3. Je na modelu **logo, SPZ, nápis značky, obecní symbol**? → odstranit v Blenderu (odbrandování).
4. Stáhni i licenční text / stránku autora do `assets/licenses/` (název podle `id`).

## Import do Godotu
- Modely `.glb`; **měřítko 1 j = 1 m**, **−Z dopředu**, počátek na zemi (u auta uprostřed mezi koly).
- LOD: velké / hustě rozmístěné věci `visibility_range_end`; nízký počet trojúhelníků.
- Kolize: jednoduchý tvar (kvádr / válec), ne trimesh z vizuálního modelu.
- Materiály: vertex colors nebo PBR textury (2k max.).
- Zvuky `.ogg`, 44,1 kHz, **mono** pro 3D zvuky (stereo jen hudba a ambient).
- Složky: `assets/models/<kategorie>/<nazev>/`, `assets/textures/<nazev>/`, `assets/sounds/<kategorie>/`, `assets/music/`.

## Zápis a kontrola
1. Přidej řádek do tabulky v `assets/LICENSES.md` **a** objekt do `assets/licenses.json`
   (klíče: `id, soubory, nazev, autor, zdroj, licence, stazeno, upravy, pouziti`; `soubory` relativně k `assets/`;
   `licence` jedna z `CC0, PD, CC-BY-3.0, CC-BY-4.0, OGA-BY, royalty-free-game`).
2. Spusť `python3 tools/assets_check.py` – ohlásí neevidované soubory a nepovolené licence
   a vygeneruje `data/credits.json`, který hra ukáže v nápovědě F1.
3. V kódu načítej přes `AssetLib.load_model("models/zvirata/liska/liska.glb")` / `AssetLib.load_sound(...)`;
   `null` = asset chybí → použij procedurální náhradu (hra musí jít i bez assetu).

## Textury terénu (M1.1) – ke stažení
Terén se ve výchozím stavu kreslí procedurálně; dlaždicové textury ho zkrášlí. **Agent je nestahuje** – dodá je uživatel.
Stáhni z Poly Haven (CC0), **rozlišení 1k, jen Diffuse (JPG)**, ulož jako `assets/textures/terrain/<název>_diff_1k.jpg`
(přesné názvy a použití: `SURFACE_TEXTURES` v `scripts/terrain.gd`; kdyby název na Poly Haven neexistoval, vyber podobnou
a soubor přejmenuj / uprav konstantu):

| soubor | Poly Haven | třída povrchu |
|---|---|---|
| `leafy_grass_diff_1k.jpg` | leafy_grass | tráva / louka, sady |
| `brown_mud_dry_diff_1k.jpg` | brown_mud_dry | orná půda (a hlína na svazích) |
| `forest_ground_04_diff_1k.jpg` | forest_ground_04 | les – podrost |
| `gravelly_sand_diff_1k.jpg` | gravelly_sand | dvůr / zástavba, polní cesty |
| `brown_mud_leaves_01_diff_1k.jpg` | brown_mud_leaves_01 | břeh / mokřad |
| `rocky_terrain_02_diff_1k.jpg` | rocky_terrain_02 | skála / strmý svah (triplanárně) |

Po stažení zapiš každou do `assets/LICENSES.md` + `licenses.json` (id `ph-<název>`) a spusť `tools/assets_check.py`.
Chybějící soubor nevadí – shader použije plochou barvu třídy + šum.
