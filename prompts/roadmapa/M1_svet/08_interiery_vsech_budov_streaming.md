# M1.8 – Interiéry všech používaných budov se streamováním

> Roadmapa „Život na vsi“ · **M1 Živý svět** · krok 8/8 (doplněk od uživatele)
> Předpoklady: M1.4, M1.5, M1.7 · Navazují: M4.7 (prohlídka domu před koupí), M3 (práce uvnitř), M7 (úřad, kampaň)
> Otevřená otázka z M1.5 („ostatní domy zamčené, nebo generované?“) se tímto rozhoduje: **generované**.

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md`
2. `scripts/interior.gd` (celý) a `scripts/public_interiors.gd` – jak se interiér staví, aktivuje (`set_active`)
   a jak se do něj vstupuje (`interior_clear`, `entered_interior` / `exited_interior` ve `world.gd`)
3. `scripts/building_details.gd` – dveře a okna na fasádě (`door_info`), aby dveře interiéru seděly s fasádou
4. `scripts/estate.gd` z M1.7 (typy budov, byty, vlastník)
5. Záznamy M1.4, M1.5 a M1.7 v `PROJECT_LOG.md`

## 1. Proč
Uživatel chce, aby **všechny používané budovy měly interiér a vcházelo se dveřmi**, ale aby se interiér
**stavěl jen, když je hráč velmi blízko nebo uvnitř** (výkon – v obci jsou stovky budov).

## 2. Co udělat
- **Generátor interiéru z půdorysu** (`scripts/interior_gen.gd`): z obrysu budovy a typu (`Estate`) vytvoří
  místnosti procedurálně přes MeshKit / `Interior` stavebnice: rodinný dům (chodba, kuchyň, obývák, ložnice,
  koupelna – dveře jako dekor), bytový dům (schodiště + dveře bytů; dovnitř jen do vlastního / otevřeného bytu),
  hospodářská budova (stodola, dílna, garáž – prázdná hala s nářadím). Seed = id budovy → vždy stejný interiér.
- **Streamování:** správce `InteriorStreamer` drží nejvýš 2–3 postavené interiéry: stavět, když je hráč
  **do ~8 m od dveří** (rozložit stavbu do více snímků, žádné záseky), rušit, když se vzdálí > 25 m a není uvnitř.
  Veřejné interiéry z M1.5 zapojit do stejného správce (dnes se staví předem – ověř a sjednoť).
- **Vstup dveřmi:** E u dveří → otevře se (animace dveří nebo jen průchod), uvnitř stejný systém jako domov.
  Zamčeno: cizí dům bez pozvání → „Zamčeno“ (+ zaklepat: postava otevře podle nálady / přátelství, hák pro M4.5);
  vloupání zatím **ne** (případně jen hák pro přestupek z M0.5 do M4.4).
- **Obyvatelé:** v cizím domě může být vesničan (z `Characters`) – když je doma, sedí u stolu; když hráč
  vejde bez pozvání, reaguje (odkaz na zákon: porušování domovní svobody – jen hák).
- **Výkon:** žádné stínové světlo navíc (jedno OmniLight bez stínů na místnost), sloučené meshe po místnostech,
  kolize jen stěny + velký nábytek. Změř a zapiš (F2 → FPS před / po u návsi).

## 3. Minimum
Generované interiéry rodinného domu a bytového domu (schodiště + vlastní byt), streamování s rozloženou stavbou,
zamčené cizí domy s klepáním.

## 4. Hotovo, když
- Do každé budovy, která má v `Estate` dveře, jde přijít ke dveřím; vlastní / veřejné / pozvané se otevřou.
- Chůze obcí nezpůsobí záseky; v paměti jsou nejvýš 3 interiéry najednou.

## 5. Návrh checklistu ručních testů
1. Dojít k vlastnímu bytu → E → schodiště → dveře bytu → byt z M1.7.
2. Cizí dům → E → „Zamčeno“; zaklepat → vesničan otevře / neotevře.
3. Projít celou náves tam a zpět → bez záseků, FPS jako dřív (F2).
4. Hospoda / Potraviny (M1.5) → vše funguje jako dřív.
5. Stodola / garáž u domu → hala s nářadím.
6. Uvnitř cizího domu (pozván) → sednout ke stolu, odejít dveřmi.
7. Uložit uvnitř a načíst → hráč je uvnitř správné budovy.

## 6. Závěr
README, VIZE a roadmapa README odškrtnout (i otázku M1.5 v tabulce rozhodnutí), PROJECT_LOG, deník AI,
commit „M1.8 Interiéry všech budov: …“, checklist a čekat.
