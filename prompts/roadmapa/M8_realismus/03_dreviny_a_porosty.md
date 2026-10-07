# M8.3 – Druhy dřevin a porosty podle stanoviště

> Roadmapa **M8 Realistický svět** · krok 3/19 · vlna 3
> Předpoklady: M8.1, **M8.2 (`Site`)** · Navazují: M8.8 (generátor tvarů), M8.11 (fenologie a růst), M8.14, M8.15
> Zavádí API: `data/dreviny.json`, `TreeEco` / `World.tree_eco`, `data/tree_eco.bin`

## 0. Než začneš – přečti
1. `00_SPOLECNE.md`, `M8_realismus/00_PRINCIPY.md` (kap. 3, 8)
2. `scripts/tree_manager.gd` (hlavička – formát `trees.bin`, číslování stromů = pořadí v souboru) a `scripts/map_loader.gd` `build_trees`
   (`grep -n "func build_trees" -A90`) – 6 prototypů (0–2 listnáč, 3–5 jehličnan), barva koruny z ortofota
3. `scripts/planted_trees.gd` hlavička (druhy sazenic M2.5), `scripts/forestry.gd` (`grep -n "^const\|^func "` – kácení, objem, zóny)
4. `scripts/priroda/tree_decor.gd` (ovoce v sadech – jak dnes pozná ovocný strom), `scripts/fauna/fauna.gd` (`trees_near`, `forest_at`)
5. `docs/VIZE_A_ROADMAPA.md` kap. 4.8 (nápad E13 – původ tohoto kroku)

## 1. Proč
~51 700 stromů v mapě nemá druh – jen „listnáč / jehličnan“ a barvu z ortofota. Les tak nemá skladbu (bučina, smrčina, lužní les
s olšemi u potoka, dubohabřina na jižním svahu), houby, zvěř ani dřevo nemohou záviset na druhu a strom vypadá všude stejně.

## 2. Co udělat
- **Katalog `data/dreviny.json`** (~16–20 druhů střední Moravy, 250–450 m n. m.): dub zimní/letní, buk, habr, lípa, javor klen,
  jasan, olše lepkavá, vrba bílá/jíva, bříza, třešeň ptačí, akát, topol, smrk, borovice lesní, modřín, jedle + ovocné (jabloň,
  hrušeň, švestka, třešeň, ořešák). Pro každý: `typ` (listnáč / jehličnan / ovocný), **Ellenberg** `L, F, R, N, T` (1–9),
  tolerance (`zamokreni`, `sucho`, `stin`, `mráz`), růst (Chapman–Richards `H_max`, `k`, `p`; `dbh_k` pro alometrii), dožití,
  tvar koruny (poměr šířka/výška, hustota, „prototyp“ 0–5 pro dnešní meshe), barvy (jaro, léto, podzim – pro M8.11), fenologie
  (GDD rašení, kvetení, zbarvení – vyplní M8.11, teď jen klíče), dřevo (hustota kg/m³, výhřevnost, cena Kč/m³ – pro `forestry`).
  U čísel uveď zdroj / poznámku „odhad – ověřit“.
- **Offline přiřazení `tools/tree_species.py`** → `data/tree_eco.bin` (magic `TECO`, verze, N = počet v `trees.bin`; na strom:
  `u8 druh, u8 věk_tříd, u8 vitalita (0–255), u8 flags, f16 výška, f16 dbh`). Postup:
  1. **Vhodnost** druhu v buňce z `site.bin`: světlo (okraj / zápoj podle hustoty stromů v okolí), vlhkost (TWI, `hand`, AWC), živiny,
     pH, teplota (oslunění + výška) → skóre podle Ellenbergových hodnot (gaussovská odchylka od optima, tolerance zúží / rozšíří).
  2. **Omezení dnešní geometrií**: jehličnatý prototyp (3–5) → jen jehličnany, listnatý → jen listnáče; ovocné jen v sadech a zahradách
     (`surface` třída 2) a u cest (aleje).
  3. **Porosty, ne náhoda:** les se dělí na porosty (shluky přes šum + oblasti s podobným stanovištěm, 0,5–5 ha), porost má 1–3 hlavní
     druhy podle hospodaření (smrkové monokultury na části kopců – realita českých lesů – a smíšené listnaté v údolích), uvnitř porostu
     **jeden věk ± rozptyl**; samotné stromy v polích a u cest mají vlastní druh i věk.
  4. **Barva z ortofota** jako jemná nápověda (tmavá → jehličnan / buk, světlá → bříza, akát), ne jako rozhodnutí.
  5. **Vitalita** 0..1 = vhodnost stanoviště × hloubka půdy × náhoda; **výška a dbh** z věku a vitality (Chapman–Richards, Näslund),
     omezené měřítkem instance v `trees.bin` (stávající velikost je realita z DMP – ber ji jako měření, ne jako výsledek).
- **Runtime `scripts/eko/tree_eco.gd`** (`class_name TreeEco`, `World.tree_eco`): načte `tree_eco.bin`, API `species(i) -> String`,
  `species_info(id) -> Dictionary`, `age(i)`, `vigor(i)`, `height(i)`, `dbh(i)`, `volume_m3(i)` (objemová rovnice / tvarové číslo),
  `stand_of(i)`, `species_near(pos, r) -> Dictionary` (podíly druhů – pro houby, zvěř, podrost). Fallback bez souboru: odvozeno z prototypu.
- **Napojení hned teď (malé, viditelné):**
  - `Forestry` / kácení: objem a cena dřeva podle druhu a dbh; polena mají druh (buk hoří lépe než smrk – `fire.gd` výhřevnost, jen pokud
    jde o jeden řádek; jinak otevřený bod).
  - Hlášky: dalekohled / pohled na strom zblízka (E na kmen) → „Buk lesní, asi 80 let“ (s dovedností Dřevorubectví přesnější věk).
  - `TreeDecor`: ovoce jen na ovocných druzích (dnes podle sadu), typ ovoce podle druhu.
  - Houby (`World.SEASON_ITEMS` hřiby): váha míst podle druhu – hřib smrkový pod smrky, křemenáč pod břízou (jen tabulka vah).
  - Zasazené stromy (M2.5) dostanou druh z katalogu (sazenice → id druhu) a vitalitu ze `Site` v místě výsadby.
- **Ladicí vrstva** `druhy` (dominantní druh v buňce 32 m, legenda) a `vitalita`.

## 3. Minimum
`dreviny.json` (aspoň 12 druhů), `tools/tree_species.py` s vhodností, porosty a věkem, `TreeEco` s API a fallbackem, objem a cena dřeva při kácení
podle druhu, vrstva `druhy` v mapě.

## 4. Hotovo, když
- Mapa druhů ukazuje souvislé porosty: olše a vrby podél potoků, buk a smrk na severních svazích, dub a habr na jižních, ovocné v sadech.
- Pokácený buk dá jiný objem a cenu než stejně vysoký smrk; strom zblízka ukáže druh a přibližný věk.

## 5. Návrh checklistu ručních testů
1. `python3 tools/tree_species.py` → statistika podílů druhů (smrk, buk, dub… v %) v logu – dává smysl pro moravskou pahorkatinu?
2. F2 → Příroda – ladění → Druhy: porosty, ne „sůl a pepř“.
3. Teleport k potoku → E na strom → „Olše lepkavá“.
4. Les na severním svahu → E → buk / smrk; jižní svah → dub / habr.
5. Pokácet strom (M2.1) → zpráva s druhem, objemem a cenou.
6. Sad v září → jablka jen na jabloních, švestky na švestkách.
7. Zasadit buk na jílovou nivu vs. na hlinitý svah → F2 → info o sazenici ukáže jinou vitalitu.

## 6. Závěr
README (nástroj), `docs/SYSTEMS.md` (Dřeviny a porosty), `ZVIRATA.md`/`BLENDER_UPRAVY.md` jen pokud se jich týká, PROJECT_LOG, `docs/testy_M8.md`,
commit „M8.3 Dřeviny a porosty: …“.
