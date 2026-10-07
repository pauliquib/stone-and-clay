# M8.18 – Zvuková krajina a drobný život (ptačí chorál, hmyz, žáby, netopýři, světlušky)

> Roadmapa **M8 Realistický svět** · krok 18/19 · vlna 7
> Předpoklady: **M8.9 (mikroklima)**, **M8.11 (fenologie)**, **M8.15 (habitat)**, M8.5 (soumrak), M8.4 (vítr), M8.7 (voda) · Navazují: M8.19

## 0. Než začneš – přečti
1. `00_SPOLECNE.md`, `M8_realismus/00_PRINCIPY.md` (kap. 8 – zvuk)
2. `scripts/priroda/nature_sfx.gd` (procedurální zvuky – cache, `player3d`), `scripts/sfx.gd` (`RATE`, generátory)
3. `scripts/fauna/bird_flock.gd` (kos zpívá za svítání – hlavička), `scripts/fauna/apiary.gd`, `scripts/fauna/ant_hill.gd` (hmyz)
4. `scripts/priroda/atmosphere.gd` – zvuk větru a deště (`_wind_snd`, `_rain_snd`), `scripts/water.gd` (šumění potoka)
5. `scripts/priroda/nature_log.gd` (deník pozorování přírody – nové druhy), `scripts/eko/microclimate.gd`, `scripts/eko/phenology.gd`, `scripts/eko/habitat.gd`

## 1. Proč
Krajina se pozná se zavřenýma očima: jarní ráno v lese je plné ptáků (kos, drozd, pěnkava, sýkora – každý jinak a v jiný čas po svítání),
v květnu kuká kukačka, v červnu večer cvrkají cvrčci (tím rychleji, čím je tepleji), u rybníka kvákají žáby, nad vodou loví netopýři, v létě
bzučí louka a v zimě je ticho, jen vrány a sýkory. Dnes je zvuk přírody pár izolovaných hlasů.

## 2. Co udělat
- **Ambientní „emitory“ krajiny (`scripts/priroda/soundscape.gd`, klient, za přepínačem `soundscape`):** kolem posluchače mřížka buněk (~40 m, okruh ~200 m),
  každá buňka podle stanoviště (`surface`, `Site`, `TreeEco` druhy, voda) a času má **seznam aktivních zdrojů** s hlasitostí; přehrává se jen N nejbližších /
  nejhlasitějších (max. ~16 současných `AudioStreamPlayer3D` + 2 ambientní 2D vrstvy), plynulé prolínání. Zdroje se vybírají podle:
  - **ptačí chorál:** tabulka druhů (`data/zvuky_prirody.json`: kos, drozd zpěvný, pěnkava, sýkora koňadra, červenka, budníček, strakapoud (bubnování), holub hřivnáč,
    kukačka, skřivan nad polem, žluva v lužním lese, sova / puštík v noci, káně křik) – **měsíce, minuty od východu / západu slunce** (`Clock` + M8.5), stanoviště,
    teplota (pod −5 °C méně), déšť / vítr potlačí. Procedurální syntéza každého druhu (charakteristický motiv – frekvenční obálky, trylky, opakování; ne
    nahrávky) v `nature_sfx.gd` stylu, varianty ze seedu;
  - **hmyz:** cvrčci a kobylky na loukách v létě večer a v noci – **Dolbearův zákon** (cvrknutí/min ≈ 7 × T(°C) − 30, z `Microclimate.temp_at`), bzučení
    louky ve dne (včely z `apiary` + `Phenology.bloom`), komáři u vody za soumraku;
  - **obojživelníci:** žáby a ropuchy u nádrží a tůní – březen–květen (tah ropuch, kvákání skokanů), večer, teplota > 8 °C;
  - **krajina:** šumění korun podle `WindField.gust_at` a druhu (smrk syčí, topol šustí – jen barva šumu), potok podle průtoku (M8.7), vzdálený pes / kohout ráno
    z domácností (M8.17), vzdálený vlak / silnice (jen pokud v datech) – ne.
- **Vizuální drobný život (MultiMesh / částice jen u hráče):** **netopýři** za soumraku nad vodou a u lamp (rychlý cikcak), **světlušky** v červnu v teplé noci na okraji
  lesa (blikající body), **motýli** nad kvetoucí loukou ve dne (bělásci, babočky – jednoduché křídlící quady), **komáří roj** nad vodou, **jepice** nad potokem
  (květen). Každé za fenologií a počasím (déšť / vítr / chlad je zruší).
- **Deník pozorování přírody (`nature_log.gd`):** nové druhy „uslyšené“ (kukačka, puštík, skřivan…) a viděné (netopýr, světluška, motýl) s datem – první
  setkání; dovednost Myslivost / nová drobná „Přírodovědec“ (jen pokud dovednosti jdou rozšířit tabulkou – jinak XP do Myslivosti).
- **Realita zvuku:** útlum vzdáleností a **útlum vegetací** (v hustém lese tlumí výšky – low-pass podle hustoty stromů mezi zdrojem a posluchačem, odhad z `TreeEco`
  bez paprsků), **ozvěna** v údolí (reverb bus podle `Site.tpi` u posluchače), vítr maskuje tiché zdroje.
- **Výkon:** syntéza zvuků do cache při startu po kouscích; výběr zdrojů 2×/s; ≤ 0,2 ms CPU průměr.

## 3. Minimum
Soundscape s výběrem zdrojů podle stanoviště a času, ptačí chorál (6+ druhů) podle minut od východu a měsíce, cvrčci podle Dolbearova zákona, žáby u vody na jaře,
netopýři a světlušky, zápis do deníku pozorování.

## 4. Hotovo, když
- Květnové ráno v lese zní jinak než lednové poledne i letní večer na louce; cvrčci za tepla cvrkají rychleji.
- Za soumraku nad rybníkem létají netopýři, v červnu na okraji lesa blikají světlušky.

## 5. Návrh checklistu ručních testů
1. 10. 5. ve 4:45 v lese → postupně nastupují ptáci (kos první), kukačka z dálky.
2. 15. 1. v poledne v lese → ticho, sýkory a vrány.
3. 20. 7. ve 21:30 na louce, 25 °C → rychlé cvrkání; F2 teplota 15 °C → pomalejší.
4. Duben večer u rybníka → žáby.
5. Soumrak u rybníka / lampy → netopýři.
6. Červen 22:30 okraj lesa, teplo → světlušky.
7. Louka v poledne v červnu → motýli, bzučení.
8. Hustý les → vzdálené zvuky tlumené; údolí → ozvěna.
9. Deník J → Pozorování přírody → nové druhy.
10. `--perfscene=les_rano_mlha` → ms (cíl +≤ 0,2 ms CPU).

## 6. Závěr
`ZVIRATA.md` (zvuky a drobný život – tabulky), `docs/SYSTEMS.md`, PROJECT_LOG, `docs/testy_M8.md`, commit „M8.18 Zvuková krajina a drobný život: …“.
