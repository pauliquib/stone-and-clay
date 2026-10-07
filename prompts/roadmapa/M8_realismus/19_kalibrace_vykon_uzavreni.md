# M8.19 – Kalibrace na realitu, výkon a uzavření M8

> Roadmapa **M8 Realistický svět** · krok 19/19 · vlna 8 (poslední)
> Předpoklady: **M8.1–M8.18** + **čísla z `--perfscene` od uživatele** (`docs/testy_M8.md`) · Navazují: milník N (nástroje), V2 (multiplayer – jen nerozbít)

## 0. Než začneš – přečti
1. `00_SPOLECNE.md`, `M8_realismus/00_PRINCIPY.md` (celý – teď se kontroluje, že platí)
2. `docs/testy_M8.md` (výsledky ručních testů a měření od uživatele), záznamy M8.x v `PROJECT_LOG.md` (otevřené body)
3. `scripts/eko/*.gd` – jen hlavičky a tabulky konstant (`grep -n "^const" scripts/eko/*.gd`)
4. `scripts/game_settings.gd` (`PRESETS`, `realism`), `scripts/tests.gd` (`PERF_SCENES`)

## 1. Proč
17 modelů napsaných různými agenty je třeba **sladit s realitou a mezi sebou** (jedna teplota, jedna vlhkost, žádné dvojí počítání), dostat je do
výkonového rozpočtu GTX 1050 a dát hráči rozumné předvolby. Bez kalibrace bude svět „realistický podle kódu“, ne podle pozorování.

## 2. Co udělat
- **Kalibrační skript `tools/eco_calibrate.py`** (offline, bez hry): zreplikuj v Pythonu **jen klíčové rovnice** (GDD a fáze, kyblík vody, inverze, Dolbear,
  CN odtok) s konstantami **vytaženými z `.gd` souborů** (parsování `const`), proženi je **normálovým rokem** z `Seasons` (teploty, srážkové dny) a vypiš:
  data rašení / kvetení / zbarvení per druh, průtoky v roce (min/max/průměr), počet dní s inverzí a mlhou v údolí, typický rozdíl kotlina–hřeben, výnosy
  plodin v suchém a vlhkém roce, populace zvěře po 10 letech. Porovnej s **referenčními hodnotami** (tabulka v hlavičce skriptu se zdroji: fenologie ČHMÚ
  pro střední Moravu, hektarové výnosy ČSÚ pro okres, hustoty zvěře – vše „orientačně, ověřit“). Tam, kde se liší o víc než ~20 % / ~7 dní, uprav konstanty
  a zapiš změnu do logu (tabulka „před → po, proč“).
- **Konzistence API:** projdi kontrakt (00_PRINCIPY kap. 3) – teplota v bodě jen z `Microclimate`, vlhkost jen ze `SoilWater`, vítr jen z `WindField`, fáze jen
  z `Phenology`; najdi a odstraň zbylé přímé čtení `Weather.temp` / `wetness` tam, kde má být lokální hodnota (`grep -rn "weather.temp\|weather.wetness" scripts`)
  – s ohledem na fallback.
- **Výkon:** z čísel uživatele sestav tabulku scéna × předvolba (ms CPU / GPU, draw calls) proti rozpočtu (00_PRINCIPY kap. 6). Pro překročení: snížit dosah / hustotu
  na Střední, zdražené věci jen na Vysoké, víc časových plátků, sloučit MultiMeshe. Nastav **předvolby** `PRESETS` + `realism` výchozí hodnoty tak, aby Střední
  držela 60 FPS na GTX 1050 (podle čísel). Pokud uživatel čísla nedodal, **neodhaduj** – napiš do logu, co je potřeba změřit, a nastav konzervativně.
- **Nová hra a staré savy:** ověř čtením, že save z M7 (bez klíčů M8) se načte a všechny M8 systémy se rozběhnou (rozběh vody 60 dní, populace z výchozí hustoty,
  stromy z `tree_eco.bin`).
- **Dokumentace:** `docs/SYSTEMS.md` – kapitola „Realistický svět (M8)“ s diagramem závislostí systémů (Mermaid: stanoviště → voda / mikroklima → fenologie →
  plodiny / zvěř → …); README – přepínače Realismu, nové nástroje v tabulce (pořadí spouštění: `site.py` → `tree_species.py` → `treegen` → `vegetation.py --eco`);
  `GAME_DESIGN.md` – pilíř „Uvěřitelná simulace“ doplnit o přírodu; `docs/VIZE_A_ROADMAPA.md` – stav M8.
- **Uzavření:** záznam „Uzavření M8“ do `PROJECT_LOG.md` (stav kroků, co je částečně, otevřené body pro N / V2 – např. synchronizace eko-stavu v multiplayeru).

## 3. Minimum
Kalibrační skript s normálovým rokem a srovnáním s referencemi, úprava konstant s tabulkou změn, odstranění dvojího čtení globálního počasí, předvolby podle změřených čísel
(nebo seznam chybějících měření), dokumentace.

## 4. Hotovo, když
- Kalibrační výpis odpovídá referencím (rašení, výnosy, průtoky, populace) v toleranci; každý systém má v `docs/SYSTEMS.md` odstavec a závislosti v diagramu.
- Předvolba Střední drží rozpočet v měřicích scénách (podle čísel uživatele), nebo je jasně zapsáno, co změřit.

## 5. Návrh checklistu ručních testů
1. `python3 tools/eco_calibrate.py` → výpis srovnání (posílej uživateli k posouzení).
2. Nová hra → hodina hraní po vsi a lese bez chyb v konzoli (`push_warning` M8 systémů).
3. Starý save z M7 → načte se, příroda se rozběhne.
4. Všechny `--perfscene` na Střední → 60 FPS (zapsat čísla).
5. Nízká předvolba → hra jako před M8 (vizuálně), simulace běží.
6. Rok přeskočený po měsících (F2) → kalendář přírody bez skoků a chyb.
7. Přepínače Realismu po jednom vypnout → nic nespadne.

## 6. Závěr
README, `docs/SYSTEMS.md`, `GAME_DESIGN.md`, VIZE a roadmapa README odškrtnout, PROJECT_LOG, `docs/testy_M8.md`, commit „M8.19 Kalibrace a uzavření M8: …“.
