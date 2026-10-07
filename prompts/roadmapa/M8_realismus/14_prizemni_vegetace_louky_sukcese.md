# M8.14 – Přízemní vegetace: louky podle stanoviště, seč, sukcese a interaktivní tráva

> Roadmapa **M8 Realistický svět** · krok 14/19 · vlna 6
> Předpoklady: **M8.2 (`Site`)**, **M8.3 (druhy – podrost podle koruny)**, **M8.4 (vítr)**, **M8.7 (vlhkost)**, M8.11 (fenologie – použij, pokud je)
> Navazují: M8.15 (potrava a kryt zvěře), M8.18 (hmyz na loukách)

## 0. Než začneš – přečti
1. `00_SPOLECNE.md`, `M8_realismus/00_PRINCIPY.md` (kap. 4, 6)
2. `tools/vegetation.py` (celý – typy, hustoty, `TARGET`, `SLOPE_MAX`, formát `VEG1`), `scripts/vegetation/vegetation_manager.gd` (LOD, chunky, vítr)
3. `shaders/vegetation.gdshader` (po M8.4), `scripts/priroda/meadow_flowers.gd` (květy u hráče), `shaders/terrain.gdshader` (`grass_green`, `meadow_bloom`)
4. `scripts/prace/udrzba.gd` (obecní údržba – sekání trávy, zóny), `scripts/noise_registry.gd` (hluk sekačky), `scripts/fauna/paddock.gd` (pastva)
5. `scripts/eko/site.gd`, `scripts/eko/tree_eco.gd`, `scripts/eko/soil_water.gd`

## 1. Proč
Louka je dnes stejná všude: trsy trávy a květy podle jedné křivky. Skutečná louka je **vlhká s pcháči a kohoutkem v nivě, suchá se šalvějí
a mateřídouškou na jižní stráni**, po seči je nízká a za měsíc znovu kvete, neposekaná za pár let zaroste trnkami a pak břízami, pod bukem
je holá hrabanka a pod smrkem jehličí. A když jde člověk vysokou trávou, tráva se rozhrnuje a zůstává za ním pěšina.

## 2. Co udělat
- **Typy porostu podle stanoviště (`tools/vegetation.py`, za `--eco` přepínačem ve verzi formátu `VEG2`; `VEG1` dál funguje):**
  - typ louky z `site.bin`: **vlhká** (TWI vysoké, niva), **mezofilní** (běžná), **suchá / stepní** (jižní svah, mělká půda), **ruderální** (u cest, obce),
    **lesní podrost** podle dominantního druhu z `tree_eco.bin` (buk → hrabanka a málo bylin, smrk → jehličí, mech, borůvky; dub/habr → bohatý
    jarní podrost – sasanky, dymnivky; olše → kopřivy, devětsil u potoka) – nové typy instancí (`HERB_WET`, `HERB_DRY`, `FERN`, `BILBERRY`,
    `MOSS`, `SPRING_FLOWERS`…) s low-poly modely v `tools/gen_vegetation_meshes.gd` (vzor dnešních), **barvy vrcholů podle 00_PRINCIPY kap. 4**;
  - hustoty a měřítka podle vlhkosti a světla (pod korunou méně), `TARGET` rozpočet zachovat (± nové typy, celkem ≤ `MAX_CAP` + 30 %).
- **Seč a pastva (simulace, `scripts/eko/meadows.gd`, `World.meadows`):** louky jako plochy (z `landuse`) s výškou porostu `h` (m) a datem poslední seče;
  růst `h` podle GDD (M8.11 / fallback `Seasons.GREEN`) a vlhkosti (M8.7); **seč** – NPC zemědělci sečou louky 2× ročně (červen a srpen, víc u obce),
  obecní údržba (M3.2) a hráč (sekačka / kosa – nástroj, pokud existuje; jinak otevřený bod) sečou zóny; **seno** v řádcích → sušení → balíky
  (vizuál + předmět, napojení na krmení koně / farmu jen hodnotou); pastva v ohradách drží nízký porost.
  Vizuál: shader trávy čte výšku porostu z hrubé textury louky (`meadow_h`, aktualizace 1×/den) → posekaná louka nízká a zelenější, květy
  (`meadow_flowers`) jen na neposekaných.
- **Sukcese (pomalá, `eco_day` v novém roce):** louka neposekaná 2+ roky → přibývají trnky a šípky (keře), 5+ let → náletové břízy a borovice
  (nové malé stromy přes mechaniku `planted_trees`, druh podle okolí a stanoviště); pole ponechané ladem → plevel → louka. Hráč to uvidí na
  dlouhé hře (a přeskokem let) – „krajina, o kterou se nikdo nestará, zarůstá“.
- **Interaktivní tráva (klient, za přepínačem `ground_veg`):** textura „sešlapání“ kolem kamery (512² na 64 m, posouvaná), do níž zapisují
  hráč, NPC, zvířata a kola (poloha + poloměr); shader trávy/obilí se v místě **ohne od zdroje** a pomalu se narovnává (relaxace ~30 s).
  **Pěšiny:** opakovaný průchod (hráč, vesničané po stejné trase, zvěř na stezkách z M8.15) zapisuje do trvalé mapy sešlapání (hrubší, 1 m/px, jen
  okolí trvalých tras) → nižší a řidší tráva, v terénu prošlapaná hlína; bez chůze zaroste za týdny.
- **Rosa a jinovatka** z M8.9 na trávě (uniform), **vlny ve větru** z M8.4 – jen ověřit, že nové typy je mají.
- **Výkon:** nové typy v rámci dnešního LOD; sešlapávací textura 1 render pass / 2 snímky; měřicí scéna `louka_vitr` a `pole_leto`.
- Ukládání: stav luk (výška, seč, roky bez seče), mapa pěšin (komprimovaně).

## 3. Minimum
Typy louky a lesního podrostu podle stanoviště a druhu stromu v `vegetation.py`, seč (NPC 2× ročně) s nízkou trávou po seči, interaktivní ohyb trávy kolem hráče,
pěšiny z opakované chůze.

## 4. Hotovo, když
- Louka v nivě vypadá jinak než suchá stráň; pod bukem je holo, pod smrkem jehličí a borůvčí.
- Po seči je louka nízká a za měsíc dorůstá; vysoká tráva se kolem hráče rozhrnuje a za ním zůstává stopa.

## 5. Návrh checklistu ručních testů
1. `python3 tools/vegetation.py --eco` → statistika typů v logu.
2. Niva u potoka vs. jižní stráň → jiné rostliny a barvy.
3. Bučina vs. smrčina → podrost odpovídá.
4. F2 → 20. 6. → NPC seče louku u obce (nebo je posekaná), řádky sena.
5. 20. 7. → posekaná louka dorůstá, květy jinde.
6. Chůze vysokou trávou (3. osoba) → tráva se ohýbá od hráče a pomalu narovnává.
7. Chodit 10× stejnou trasou → pěšina; týden nechodit → zaroste.
8. Přeskočit 6 let (F2) na neposekané louce za obcí → trnky, náletové břízy.
9. `--perfscene=louka_vitr` → ms GPU (cíl +≤ 0,6 ms).

## 6. Závěr
README (nástroj, `--eco`), `docs/SYSTEMS.md` (Přízemní vegetace, seč, sukcese), PROJECT_LOG, `docs/testy_M8.md`, commit „M8.14 Přízemní vegetace: …“.
