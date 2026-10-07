# M8.11 – Fenologie a růst: každý druh podle svého kalendáře, stromy rostou v letech

> Roadmapa **M8 Realistický svět** · krok 11/19 · vlna 5
> Předpoklady: **M8.3 (druhy)**, **M8.9 (`Microclimate`)**, M8.8 (varianty podle věku – použij, pokud jsou) · Navazují: M8.12, M8.14, M8.15, M8.18
> Zavádí API: `Phenology` / `World.phenology` – `gdd(year_day)`, `phase(species, pos) -> Dictionary`, `foliage(species, pos)`, `autumn(...)`, `bloom(...)`

## 0. Než začneš – přečti
1. `00_SPOLECNE.md`, `M8_realismus/00_PRINCIPY.md` (kap. 3, 4 – `INSTANCE_CUSTOM.a`, kap. 8 – fenologie)
2. `scripts/priroda/seasons.gd` (tabulky `FOLIAGE`, `AUTUMN`, `GREEN`, `BLOOM` podle dne v roce – **zůstanou jako fallback**)
3. `scripts/priroda/season_fx.gd` (kdo nastavuje globální `foliage`, `autumn`, `grass_green`), `shaders/tree.gdshader`
4. `scripts/planted_trees.gd` (růst sazenic, `GROWTH_SPEEDUP`, zálivka, uschnutí), `scripts/priroda/tree_decor.gd` (ovoce, listí na zemi)
5. `data/dreviny.json`, `scripts/eko/tree_eco.gd` (M8.3), `scripts/eko/microclimate.gd` (M8.9)

## 1. Proč
Dnes všechny listnáče raší ve stejný den roku a barví se naráz, bez ohledu na to, jestli bylo teplé nebo studené jaro. Ve skutečnosti
**bříza a vrba raší první, dub a jasan poslední**, v teplé kotlině o týden dřív, na hřebeni později; teplé jaro posune vše dopředu, pozdní
mráz spálí květy jabloní a pak nejsou jablka. Stromy navíc za roky rostou – les se mění.

## 2. Co udělat
- **`scripts/eko/phenology.gd`** (`class_name Phenology`, `World.phenology`): denní krok (`eco_day`):
  - **sumy efektivních teplot GDD** (základ 5 °C, z denního průměru teploty `Weather` – nebo `Microclimate` na referenčním místě) od 1. 1.,
    **chlazení** (dny < 5 °C od listopadu – ovocné dřeviny potřebují zimu), fotoperioda z `Clock` (podzim spouští zbarvení délka dne + chlad);
  - prahy fází per druh v `data/dreviny.json` (`fenologie`: `rasi_gdd`, `kvete_gdd`, `plne_olisteni_gdd`, `zbarveni_den` + `zbarveni_chlad`,
    `opad_dni`) – kalibrace na fenologické fáze ČHMÚ pro střední Moravu (uveď zdroj / „odhad – ověřit“);
  - **posun v prostoru:** místo má vlastní „teplotní posun“ z `Microclimate` (kotlina, jižní svah, výška) → fáze se počítá jako GDD + posun × dny;
  - `phase(species, pos)`: `foliage` 0..1, `autumn` 0..1, `bloom` 0..1, `fruit` 0..1 (zrání), `frost_damage` (pozdní mráz v době květu → méně plodů);
  - **rok v paměti:** historie roku (data fází, extrémy) do deníku J → Příroda („Letos jabloně kvetly 24. 4., pozdní mráz 2. 5. spálil květy v údolí“).
- **Vizuál stromů (klient):** `INSTANCE_CUSTOM.a` = **fenologický posun druhu a místa** zakódovaný 0..1 (sestaví `build_trees` z `TreeEco` + `Site`),
  `tree.gdshader` počítá `foliage`/`autumn` z globálního „fenologického času“ (`pheno_t`, uniform) − posun → každý druh a místo jinak;
  barvy jara, léta a podzimu z `dreviny.json` (bříza žlutá, javor červenooranžový, buk měděný, dub hnědý, modřín zlátne a **opadává** – jediný
  jehličnan). Kvetení ovocných stromů (bílé / růžové body v koruně) a třešní / trnek na jaře.
- **Růst v letech (`eco_day` v novém roce + `TreeEco`):** každý strom stárne o rok; výška a dbh přírůstek podle Chapman–Richards a **ročního
  stresu** (sucho z `SoilWater` v létě, poškození mrazem) – `TreeEco` drží delta k `tree_eco.bin` v savu (jen změněné, kompaktně). Přechod věkové
  třídy → jiná varianta meshe (M8.8) nebo měřítko instance. **Zasazené stromy** (M2.5) přejdou na stejný model (vitalita ze `Site`, zálivka a
  sucho z `SoilWater`), `GROWTH_SPEEDUP` zůstane jako volba hratelnosti.
- **Úmrtnost a obnova (jemně):** velmi staré / slabé stromy občas odumřou (suchý strom bez listí – „souška“, hajný ji později pokácí jako práci),
  na pasekách po kácení (M2.1) se za pár let objeví zmlazení (malé stromky z `planted_trees` mechaniky, druh podle okolí).
- **Napojení:** `TreeDecor` ovoce podle `fruit` a `frost_damage` (méně jablek po mrazu), padané listí podle opadu druhu, včely (`apiary.gd`) podle
  `bloom` okolních druhů a luk, zvěř: žaludy a bukvice (M8.15 použije `fruit` dubu a buku + semenné roky).
- Fallback: přepínač `phenology` vypnutý → `Seasons` tabulky jako dnes.
- Ladicí vrstva `fenologie` (fáze dominantního druhu v buňce) a F2 → Příroda – ladění → „Fenologický kalendář“ (tabulka druh → datum rašení letos).

## 3. Minimum
GDD a prahy fází per druh, posun podle místa, shader barví a olisťuje stromy podle druhu (`INSTANCE_CUSTOM.a`), pozdní mráz sníží úrodu ovoce,
roční růst a stárnutí stromů v savu.

## 4. Hotovo, když
- Na jaře je les „strakatý“ – břízy a vrby zelené, duby ještě holé; v údolní kotlině se raší jinak než na teplém svahu.
- Teplé jaro (F2 vynucená teplota) posune rašení dopředu; mráz v době květu sníží počet jablek.

## 5. Návrh checklistu ručních testů
1. F2 → 20. 4., les → břízy zelené, duby holé, buky raší.
2. F2 → 15. 10. → javory červené, břízy žluté, smrky zelené, modříny zlaté.
3. 10. 11. → modříny opadané, duby ještě hnědé.
4. F2 → vynutit teplé jaro (teplota +5 °C) a přeskočit do dubna → rašení dřív než v kroku 1.
5. Sad v době květu + noc s mrazem (F2) → deník J → zmínka o mrazu; v září méně jablek.
6. Přeskočit 5 let → zasazené stromy vyrostly, les o kus vyšší (porovnat výšku stromu dalekohledem).
7. Paseka po kácení po 3 letech → zmlazení.
8. Přepínač Fenologie vypnout → starý jednotný kalendář.

## 6. Závěr
`docs/SYSTEMS.md` (Fenologie a růst), PROJECT_LOG, `docs/testy_M8.md`, commit „M8.11 Fenologie a růst: …“.
