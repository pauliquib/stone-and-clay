# M8.12 – Plodiny a zahrada podle růstového modelu (voda, teplo, světlo)

> Roadmapa **M8 Realistický svět** · krok 12/19 · vlna 5
> Předpoklady: **M8.7 (`SoilWater`)**, **M8.9 (`Microclimate`)**, M8.5 (záření – použij, pokud je), M8.11 (GDD – použij `Phenology.gdd`, pokud je)
> Navazují: M8.14 (louky), M8.15 (škody zvěří), M7/M3 ekonomika

## 0. Než začneš – přečti
1. `00_SPOLECNE.md`, `M8_realismus/00_PRINCIPY.md` (kap. 8 – plodiny)
2. `scripts/garden.gd` – hlavička, `CROPS`, stav záhonu (`Plot.cells`), denní růst a zálivka (`grep -n "^const\|^func " scripts/garden.gd`)
3. `scripts/priroda/fields.gd` – `CROPS` (barvy po dnech roku, žně ~205. den), `crop_of`, `lut_image`; `tools/vegetation.py` (obilné řádky)
4. `scripts/prace/statek.gd` (farma – sklizeň jako práce?), `scripts/items_db.gd` (`grep -n "seed\|semin\|sklizen" scripts/items_db.gd | head`)
5. `scripts/eko/soil_water.gd`, `scripts/eko/microclimate.gd`, `scripts/eko/phenology.gd` (pokud je)

## 1. Proč
Zahrada a pole dnes rostou podle kalendáře: zasazeno → za N dní zralé, ať prší nebo ne (kromě zálivky). Ve skutečnosti rozhoduje **teplo
(sumy teplot), voda v půdě a světlo**: v suchém roce je úroda malá, mráz spálí rajčata, ve stínu stromu salát vybíhá, na jílu je jiná sezóna než
na písku. Hráč-zahradník a zemědělec má číst krajinu a počasí.

## 2. Co udělat
- **`scripts/eko/crop_model.gd`** (`class_name CropModel`, statické funkce + tabulka): pro **jednu rostlinu / buňku záhonu / pole** stav
  `{stage, gdd, biomass, lai, water_stress, heat_stress, frost_kill, yield_potential}`:
  - **fáze podle GDD** (základ podle plodiny – kukuřice 10 °C, pšenice 0–5 °C, rajče 10 °C): klíčení → vegetativní → kvetení → zrání → zralé → přezrálé;
  - **přírůstek biomasy = RUE × zachycené záření (1 − e^(−k·LAI)) × min(stres vody, stres teploty)** (light use efficiency, WOFOST-lite);
    záření z `Atmosphere.global_horizontal_irradiance_wm2` (fallback z oblačnosti a dne), **stín** stromů a budov v místě záhonu (paprsky ke slunci
    jednou za den v poledne a ráno/odpoledne – jen pro záhon u hráče);
  - **stres vody** z `SoilWater.moisture_at` (pod 0,35 roste, nad 0,9 zamokření u citlivých plodin), **mráz** z `Microclimate.frost_at` (citlivé plodiny
    zmrznou pod 0 °C, ozimy přežijí), **horko** (> 32 °C omezí kvetení);
  - **výnos** = sklizňový index × biomasa → počet kusů / kg (zaokrouhlit na herní předměty).
  - Tabulka `data/plodiny.json`: zahradní (brambory, mrkev, salát, rajče, okurka, cibule, česnek, dýně, fazole, jahody…) a polní (pšenice ozimá,
    ječmen jarní, řepka, kukuřice, slunečnice, jetel) – základ GDD, GDD fází, RUE, k, sklizňový index, mrazuvzdornost, nároky na vodu, setí od–do.
    Hodnoty „odhad – ověřit“ s poznámkou.
- **Zahrada (`garden.gd`, za přepínačem `crops`):** záhon místo časovače používá `CropModel` v `eco_day` (+ `eco_hour` pro mráz v noci).
  Zálivka přidá vodu do `SoilWater` buňky záhonu (malý lokální kyblík záhonu navíc, aby záhon nesdílel 32 m buňku s celou loukou).
  Vzhled rostliny podle `stage` a `lai` (dnešní meshe: měřítko + barva; vadnutí = žlutější a svěšené), sklizeň podle výnosu.
  Hláška při pohledu na záhon: „Brambory kvetou, půda je suchá.“ (Zahradničení úroveň → přesnější odhad výnosu).
- **Pole (`fields.gd`):** každé pole (id) dostane stav plodiny v `eco_day` (hrubě – 1 bod na pole v jeho středu s průměrem `Site`/`SoilWater`),
  **barva pole a výška obilí** z `stage` a stresu místo pevné tabulky dní (v suchém roce dřív žloutne, žně dřív); výnos pole → cena / výkup
  (napojení na statek / práci jen hodnotou, ne novou mechanikou). Plodina podle osevního postupu `crop_of` beze změny (determinismus s `vegetation.py`).
- **Žně a polní práce v kalendáři** podle zralosti (traktůrek M1.6 jezdí, když je pole zralé, ne pevný den) – jen pokud jde jednou podmínkou.
- **Rok v deníku J → Příroda:** „Letošní úroda: suchý červen, brambory slabé, obilí sklizeno 12. 7.“.
- Ukládání: stav záhonů (rozšířit `Plot.cells` o klíče s výchozí hodnotou) a polí (`fields_eco`).

## 3. Minimum
`CropModel` s GDD fázemi, RUE růstem, stresem vody a mrazem, `data/plodiny.json` (8 zahradních + 4 polní), zahrada a pole na něm, ukládání.

## 4. Hotovo, když
- Stejné brambory zasazené v suchém a ve vlhkém roce dají viditelně jiný výnos; mráz v květnu zničí rajčata venku.
- Pole v suchém létě zežloutne a žne se dřív.

## 5. Návrh checklistu ručních testů
1. Zasadit brambory v dubnu, nezalévat, F2 → sucho (vynutit jasno) → v srpnu malá úroda.
2. Totéž se zálivkou → větší úroda.
3. Rajčata venku a noc s mrazem v květnu → zmrzlá.
4. Salát ve stínu stromu vs. na slunci → jiná rychlost.
5. Pohled na záhon → hláška o fázi a vlhkosti.
6. Pole s pšenicí v suchém roce → dřív žluté, traktor sklízí dřív.
7. Deník J → Příroda → shrnutí úrody.
8. F5/F9 → stav záhonu i fáze zůstanou.
9. Přepínač Plodiny vypnout → původní časovač.

## 6. Závěr
`docs/SYSTEMS.md` (Plodiny a zahrada), README, PROJECT_LOG, `docs/testy_M8.md`, commit „M8.12 Plodiny podle růstového modelu: …“.
