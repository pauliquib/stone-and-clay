# M8.17 – Život vesnice: domácnosti, potřeby a vztahy mezi obyvateli

> Roadmapa **M8 Realistický svět** · krok 17/19 · vlna 6
> Předpoklady: M8.1 (M8.6 chůze, M8.9 teplota, M8.11/M8.12 sezónní práce, M8.16 tělo – použij, co je) · Navazují: M8.18, M7 (popularita – jen čte)

## 0. Než začneš – přečti
1. `00_SPOLECNE.md`, `M8_realismus/00_PRINCIPY.md` (kap. 1, 6, 9)
2. `scripts/villager.gd` (hlavička, `JOB_PLACE`, `BT_VILLAGERS`, `use_bt`, `PHYSICS_RANGE`, spánek za bublinou), `ai/villager_routine.tres`,
   `scripts/ai/` (tasky LimboAI), `tools/gen_villager_bt.gd`
3. `scripts/persona.gd`, `scripts/characters.gd` (postavy, povahy, povolání), `scripts/estate.gd` (`resident_of`, domácnosti, obydlené domy ~70 %)
4. `scripts/interior_streamer.gd` (`resident_of`, kdo je doma podle hodiny), `scripts/building_details.gd` (svícení oken), `scripts/priroda/chimney_smoke.gd` (M1.3 – kdo topí)
5. `scripts/dialog_data.gd` / `dialog_themes.gd` (drby), `scripts/favors.gd` (M4.5), `scripts/reputation.gd` (komunity)

## 1. Proč
Vesnice dnes „hraje divadlo“ pro hráče: 28 vesničanů chodí, pár jich má denní rutinu, okna svítí a komíny kouří náhodně podle pravděpodobnosti.
Skutečná ves je **síť domácností**: v domě bydlí rodina, ráno se rozsvítí kuchyň a zatopí se, děda jde se psem, v sobotu se seká tráva a štípe dřevo
na zimu, sousedé si pomáhají a hádají se, drby se šíří od hospody. Cíl: aby se svět choval stejně, i když se hráč nedívá.

## 2. Co udělat
- **Domácnosti (`scripts/eko/households.gd`, `World.households`):** z `Estate` obydlených domů (~70 %) vygeneruj **deterministicky** domácnosti (seed = id
  budovy): složení (senior/pár/rodina s dětmi/jednotlivec), členové = existující postavy z `Characters` (28 přiřadit k domům podle jejich dnešního domova /
  povolání) + **„neviditelní“ obyvatelé** (jen data, bez modelu – ať má každý dům život i bez 28 postav); zdroj tepla (kamna na dřevo / plyn / elektřina –
  podle stáří a typu domu), zahrada (ano/ne), auto, zvířata (pes, slepice).
- **Potřeby a plán dne (utility AI, data v `data/potreby.json`):** pro členy domácnosti potřeby **spánek, jídlo, práce, hygiena, společnost, odpočinek,
  povinnosti domu** (topení, zahrada, sekání, dřevo, sníh, nákup); činnost = nejvyšší užitek podle potřeby × času × počasí (`Microclimate` / `Weather`) ×
  sezóny (M8.11/M8.12: jaro zahrada, léto seč, podzim dřevo a sklizeň, zima sníh) × povahy (`Persona`). **Postavy s modelem** dostanou cíle do dnešního BT /
  pohybu (`move_to`), neviditelní jen „virtuálně“ (stav domu).
- **Dům jako stav:** obsazenost (kdo je doma), **svícení oken podle obsazenosti a místnosti** (kuchyň ráno, obývák večer, ložnice před spaním – napoj
  `BuildingDetails` – svítí jen tam, kde někdo je), **komín** podle zdroje tepla a skutečné potřeby (teplota v místě z `Microclimate`, kdo je doma, ráno přiložit
  → silnější kouř, `chimney_smoke.gd` dostane intenzitu z domu místo pravděpodobnosti), zvuky (štípání dřeva, sekačka – `World.noise` s nedělním klidem M4.4).
- **Vztahy NPC ↔ NPC:** matice vztahů mezi domácnostmi (sousedé, příbuzní, rivalové; deterministicky + vývoj): pomoc (půjčení nářadí, odklízení sněhu u
  seniora), spory (hluk, mez, pes), návštěvy, hospoda jako uzel; události zapisuje do **paměti drbů** – drby se šíří sítí (kdo s kým mluví) a hráč je slyší
  v rozhovoru (T / E u vesničana) jako dnes, jen s pravdivým obsahem z událostí (*„Novákovi už zase nemají dřevo a je listopad.“*). Činy hráče se šíří stejně
  (napoj `emit_game_event` → paměť drbů; M7 popularita jen čte).
- **LOD simulace:** vesničané v bublině (`World.sim_radius`) plně; mimo ni **plán dne po hodinách** (`eco_hour`) bez pohybu – jen „kde je“; neviditelní obyvatelé
  vždy jen data. Rozpočet ≤ 0,3 ms průměr.
- **Zapnout BT pro všechny postavy s modelem** (dnes `BT_VILLAGERS = 5`) – pokud výkon dovolí (měřicí scéna `ves_poledne`), jinak zapsat limit do logu.
- Ladicí vrstva `obyvatele` (obsazenost domů a činnost) a F2 → Příroda – ladění → „Domácnosti“ (výpis domu: kdo, co dělá, potřeby).
- Ukládání: vztahy (změny proti seedu), paměť drbů (posledních N), stav domů (zásoba dřeva…).

## 3. Minimum
Domácnosti z `Estate` se složením a zdrojem tepla, plán dne podle potřeb a sezóny pro postavy s modelem, okna a komíny podle obsazenosti a teploty, drby z událostí
šířené mezi postavami.

## 4. Hotovo, když
- V 6:30 v zimě se v obci rozsvěcují kuchyně a začne kouřit víc komínů; v noci svítí jen pár oken; o víkendu na podzim je slyšet štípání dřeva.
- Vesničan řekne drb o skutečné události (hráčově nebo jiné domácnosti), která se stala před pár dny.

## 5. Návrh checklistu ručních testů
1. Leden 6:00 → 7:00 → okna kuchyní se rozsvěcují, komíny kouří víc.
2. 23:30 → svítí málo oken; komíny slabě.
3. Sobota v říjnu dopoledne → štípání dřeva u domů (zvuk), někdo hrabe listí.
4. Neděle → sekačka nikde (nedělní klid).
5. Způsobit událost (např. srazit srnce, M2.9) → za 1–2 dny o tom mluví vesničan na druhém konci obce.
6. F2 → Příroda – ladění → Domácnosti → vybraný dům: kdo bydlí, co dělá.
7. Sníh → senior má odklizeno od souseda (pomoc).
8. F5/F9 → stav domů a drby zůstanou.
9. `--perfscene=ves_poledne` → ms procesu (cíl +≤ 0,3 ms).

## 6. Závěr
`docs/SYSTEMS.md` (Život vesnice), README, PROJECT_LOG, `docs/testy_M8.md`, commit „M8.17 Život vesnice: …“.
