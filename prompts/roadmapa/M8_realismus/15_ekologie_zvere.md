# M8.15 – Ekologie a populace zvěře: stanoviště, potrava, denní a roční cyklus

> Roadmapa **M8 Realistický svět** · krok 15/19 · vlna 6
> Předpoklady: **M8.2 (`Site`)**, **M8.3 (druhy)**, **M8.11 (fenologie – žaludy, bukvice)**, M8.12 (plodiny – škody), M8.14 (kryt luk – použij, pokud je)
> Navazují: M8.18 · Zavádí API: `Habitat` / `World.habitat`

## 0. Než začneš – přečti
1. `00_SPOLECNE.md`, `M8_realismus/00_PRINCIPY.md` (kap. 3, 8 – zvěř), `ZVIRATA.md`
2. `scripts/fauna/fauna.gd` – mapa stanovišť, spawn, `forest_at`, `random_point`, počty (`grep -n "^const\|^func " scripts/fauna/fauna.gd`)
3. `scripts/fauna/animal_specs.gd` (aktivita, okrsky), `scripts/fauna/herd.gd`, `scripts/fauna/hunter.gd` (myslivec, krmelce, zimní stahování)
4. `scripts/hunting.gd` (úlovky → populace?), `data/lov.json` (doby lovu, plán?), `scripts/gamekeeper.gd`
5. `scripts/eko/site.gd`, `scripts/eko/tree_eco.gd`, `scripts/eko/phenology.gd`, `scripts/eko/crop_model.gd` (pokud je)

## 1. Proč
Zvěř dnes žije v „lese a na okrajích“ a počet je pevný. Skutečný srnec **ve dne leží v hustém krytu**, za soumraku vychází na pole s
ozimem nebo jetelem, v zimě se stahuje do závětří a ke krmelcům; divočáci jdou v semenném roce za žaludy a bukvicemi a jindy do kukuřice,
kde dělají škody; populace roste v létě (kolouši, selata) a klesá zimou a lovem. Myslivec, hajný a zemědělci na to reagují.

## 2. Co udělat
- **`scripts/eko/habitat.gd`** (`class_name Habitat`, `World.habitat`): mřížka **64 m** se skóre per druh (srnec, prase, zajíc; ptáci zvlášť jen jednoduše):
  - **kryt** (hustota a výška podrostu – mladé porosty a houštiny z `TreeEco` věku, vysoká tráva / kukuřice z M8.12/M8.14), **potrava** podle sezóny
    (pastva luk a ozimů, okus mladých stromků a keřů, **žaludy/bukvice** z `Phenology` `fruit` dubu a buku – **semenné roky** (mast years:
    deterministicky 1× za 3–6 let), kukuřice v mléčné zralosti pro prasata), **klid** (vzdálenost od silnic, domů, cest s provozem – `World.noise`
    a frekvence chůze z pěšin M8.14), **voda** (`dist_water`), **závětří a teplo v zimě** (`Site.wind_exp`, `insol_winter`), sníh (`SoilWater.snow_at`).
  - `suitability(species, pos, hour, doy) -> float`, `best_nearby(species, pos, radius, purpose) -> Vector3` (purpose: `"rest"`, `"feed"`, `"water"`),
    přepočet jen 1×/den (`eco_day`) a po skupinách buněk.
- **Pohyb podle cyklu (napoj na `animal.gd` / `herd.gd`, za přepínačem `habitat`):** cíle okrsku (dnes náhodné body v okrsku) vybírá `Habitat`:
  den → odpočinek v krytu, soumrak → přesun na pastvu (pole / louka u lesa), noc (prasata) → potrava, svítání → zpět do krytu. **Stezky (zvěřní
  ochozy):** spojnice krytu a pastvy se opakují → zapisují se do mapy pěšin (M8.14), na nich jsou častěji stopy.
- **Populace (simulace, `eco_day`):** pro každý druh a „honitbu“ (katastr rozdělit na 2–4 oblasti) stav: počet, věková / pohlavní struktura hrubě;
  **logistický růst** s kapacitou z `Habitat` (součet vhodnosti), **rozmnožování** (srnčí kolouši V–VI, selata III–V, zajíc víc vrhů), **zimní úmrtnost**
  (sníh, mráz, potrava; menší s krmelcem plněným myslivcem / hráčem), **lov** (úlovky hráče a myslivce z `hunting.gd` ubírají), **srážky s auty**.
  Spawnované jedince (dnešní počet kolem hráče) **odvozuj z hustoty populace** v oblasti a vhodnosti v okolí – hustota v číslech na 100 ha
  (orientačně srnec 10–30, prase podle roku 2–15 – „ověřit“), ne pevný počet.
- **Důsledky ve hře:**
  - **škody** – prasata rozryjí louku (vizuál: tmavá rozrytá místa v terénu u lesa, deformační mapa M8.13, pokud je – jinak decal), okus sazenic
    (M2.5 sazenice bez ochrany – už je; jen napojit pravděpodobnost na `Habitat`), škody na kukuřici zvyšují **reptání zemědělců** (respekt komunity /
    drby: „prasata zas rozryla louku u lesa“);
  - **myslivec** (`hunter.gd`): plánuje lov podle populace (víc prasat → víc nočních čekaných, úkol pro hráče „pomoz se škodami“ – jen háček / drb,
    úkoly dělá M7.3 systém), v zimě krmí;
  - **deník J → Příroda:** odhad stavu zvěře v honitbě (dovednost Myslivost zpřesní), semenný rok („letos je hodně žaludů“).
- Ladicí vrstvy `habitat_srnec`, `habitat_prase` (aktuální hodina), F2 → Příroda – ladění → „Populace“ (tabulka oblastí a druhů).
- Ukládání: populace per oblast a druh, semenný rok, škody (klíč `wildlife`).

## 3. Minimum
`Habitat` se skóre kryt/potrava/klid, denní cyklus odpočinek ↔ pastva řízený `Habitat`, populace s rozmnožováním, zimní úmrtností a lovem, počet spawnovaných
zvířat z hustoty, semenný rok pro prasata.

## 4. Hotovo, když
- Za soumraku jsou srnci na polích u lesa a ve dne je najdeš jen v houštinách; v zimě jsou u krmelců a v závětří.
- Po intenzivním lovu je zvěře méně a v dalších letech se populace obnovuje; v semenném roce jsou prasata v bučinách a doubravách.

## 5. Návrh checklistu ručních testů
1. Červen, 20:30 → okraj lesa u ozimu: srnci venku; 12:00 tamtéž nikdo.
2. Poledne v mladé houštině → zvedneš srnce z lože.
3. Leden se sněhem → srnci u krmelce a v závětří (jižní svahy).
4. F2 → Příroda – ladění → Populace: čísla po oblastech; ulovit 5 srnců → číslo klesne.
5. Přeskočit rok → populace zase vyšší (kolouši).
6. Semenný rok (F2 vynutit / najít v deníku) → prasata v bučině, rozrytá místa.
7. Drb vesničana o škodách prasat po rozrytí louky.
8. F5/F9 → populace a škody zůstanou.
9. `--perfscene=pole_leto` → ms procesu (cíl +≤ 0,3 ms).

## 6. Závěr
`ZVIRATA.md` (stanoviště, populace, tabulky), `docs/SYSTEMS.md`, PROJECT_LOG, `docs/testy_M8.md`, commit „M8.15 Ekologie zvěře: …“.
