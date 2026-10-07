# M8.2 – Mapa stanovišť: terén, voda, oslunění a půda

> Roadmapa **M8 Realistický svět** · krok 2/19 · vlna 2
> Předpoklady: M8.1 · Navazují: M8.3, M8.7, M8.9, M8.11–M8.15 (zavádí API `Site` / `World.site`, `data/site.bin`)

## 0. Než začneš – přečti
1. `00_SPOLECNE.md`, `M8_realismus/00_PRINCIPY.md` (kap. 3, 7, 8)
2. `tools/vegetation.py` – hlavička a `load_surface` (vzor formátu a čtení `surface.bin`, `landuse.bin`, `terrain_height.bin`)
3. `tools/surface.py` hlavička (třídy povrchu), `tools/water.py` hlavička (formát `water.json`, koryta)
4. `scripts/terrain.gd` (`height_at`, mřížka 2 m, union mapa) a `scripts/surface_map.gd` (jak hra čte `surface.bin`)
5. `scripts/clock.gd` – `sun_enu`, `sun_elevation` (pro výpočet oslunění stejným modelem jako hra)

## 1. Proč
Dnes je krajina pro simulaci „plochá“: les je les, louka je louka. V realitě o všem rozhoduje **stanoviště** – údolní niva u potoka
je vlhká, chladná v noci a úrodná; jižní svah suchý a teplý; hřbet větrný a mělký. Tato mapa je základ, ze kterého M8 odvodí
druhy stromů, vlhkost půdy, mikroklima, plodiny i zvěř.

## 2. Co udělat
- **Offline nástroj `tools/site.py`** → `data/site.bin` (magic `SITE`, verze, `x0, z0, cell=4.0, w, h`, pak vrstvy jako `uint8`
  / `uint16` s lineárním převodem; měřítka v hlavičce). Vstupy jen lokální (`terrain_height.bin`, `water.json` / `water_carve.bin`,
  `surface.bin`, `landuse.bin`, `map.json`). Vrstvy:
  1. `elev` (m n. m. – z `map.json` posunu výšky, ověř), `slope` (°), `aspect` (° od **severu** přes `north_deg`)
  2. `flow_acc` (D8 akumulace, log) a **`twi` = ln(a / tan β)** (s ošetřením plochých míst – minimální sklon 0,5°)
  3. `dist_water` (m k toku / nádrži, `scipy.ndimage.distance_transform_edt`), `hand` (výška nad nejbližším tokem po směru odtoku – niva)
  4. `tpi` (topografická poloha: buňka − průměr okolí 100 m a 500 m → údolí / svah / hřbet), `wind_exp` (expozice větru z TPI a
     výšky nad okolím, 0..1, pro převládající západní proudění zvlášť)
  5. `insol` – **roční potenciální oslunění** (MJ/m²) a zvlášť **zimní** (prosinec–únor): integrace polohy slunce po 1 h pro 12 dnů
     roku přes sklon/orientaci + **zastínění terénem** (horizont ve 16 směrech, numpy, hrubší mřížka 16 m)
  6. `cold_pool` 0..1 – mrazová kotlina (záporné TPI, nízké `hand`, malá expozice větru)
  7. `soil` (třída 0–5) + `soil_depth` (cm) + `awc` (mm využitelné vody) + `ph` (×10) + `nutr` (0..1): **pravidla v tabulce na začátku
     nástroje**, ne v kódu: niva (`hand` < 2 m, u toku) → fluvizem, vlhká deprese (`twi` vysoké) → glej / pseudoglej (jíl, zamokření),
     prudký svah / hřbet (`slope` > 20°, TPI > 0) → ranker / litozem (mělká, skeletovitá), mírné svahy → kambizem / hnědozem
     (hluboká hlinitá), zástavba → antropozem; orná půda prohlubuje ornici. Šum (seed) pro přirozené hranice, ne „šachovnice“.
  8. Volitelně **BPEJ / půdní mapa od uživatele** (`--soils=soubor.geojson`): pokud je, přepíše třídu a AWC (převodní tabulka v nástroji).
- **Runtime `scripts/eko/site.gd`** (`class_name Site`, `World.site`): načte `site.bin` (mapování do `PackedByteArray`, ne slovníky),
  rychlé typované dotazy `elev(x,z)`, `slope`, `aspect`, `twi`, `dist_water`, `hand`, `tpi`, `wind_exp`, `insol`, `insol_winter`, `cold_pool`,
  `soil`, `soil_depth`, `awc`, `ph`, `nutr` + `at(x,z) -> Dictionary` (pro ladění). Bilineární interpolace jen u spojitých vrstev.
  **Fallback** bez souboru: odvoď z `Terrain` sklon a jinak vrať střední hodnoty (svět běží, jen „plochý“).
  Konstanty `SOIL_NAMES`, `SOIL_PROPS` (textura, únosnost pro M8.13, propustnost pro M8.7).
- **Ladicí vrstvy** (M8.1): `site_twi`, `site_soil`, `site_insol`, `site_cold`, `site_wind` s legendou.
- **Rozhovor (drobnost):** zemědělci / děda občas řeknou větu o půdě na místě („tady je jíl, po dešti se tu zabořit nechceš“) –
  `DialogThemes` téma podle `Site.soil` u hráče (2–4 věty na třídu).

## 3. Minimum
`tools/site.py` s vrstvami 1–3, 5 (bez zastínění), 6, 7; `Site` s dotazy a fallbackem; vrstvy `site_twi` a `site_soil` v mapě.

## 4. Hotovo, když
- Mapa M s vrstvou TWI ukáže síť údolnic shodnou s potoky; půdy dávají smysl (niva u řeky, mělké půdy na hřbetech).
- Statistika nástroje (podíl tříd půd, rozsah TWI, průměrné oslunění J vs. S svahu) je v logu a odpovídá realitě (jižní svah > severní).

## 5. Návrh checklistu ručních testů
1. `python3 tools/site.py` doběhne (čas a velikost výstupu v logu nástroje).
2. F2 → Příroda – ladění → TWI: modré linie v údolích, kde jsou potoky.
3. Vrstva Půda: u řeky jiná barva (niva) než na kopcích; obec = antropozem.
4. Vrstva Oslunění: jižní svahy světlejší než severní.
5. Vrstva Mrazové kotliny: dna údolí.
6. Stát na nivě u potoka a mluvit s dědou (T, téma půda) → věta o vlhké půdě.
7. Smazat `data/site.bin` → hra běží (fallback), vrstvy prázdné.

## 6. Závěr
README (tabulka nástrojů: `tools/site.py`, kdy spustit), `docs/SYSTEMS.md` (Stanoviště), PROJECT_LOG, `docs/testy_M8.md`, commit „M8.2 Mapa stanovišť: …“.
