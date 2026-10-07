# M4.3 – Soud a vězení

> Roadmapa „Život na vsi“ · **M4 Zákon a společnost** · krok 3/8
> Předpoklady: M0.5, M4.2 (`Debts`, dopisy do schránky, rozšířené `records`) · Navazují: M4.6 (pytláctví, nedovolené
> ozbrojování jako trestné činy, zbrojní průkaz jen s čistým rejstříkem), M3.1 (výpověď), M7.2 (odhalené podvody)
> Stav kódu ověřen po vlně 0 (commit `357f7eb`). Když grep ukáže něco jiného, věř kódu a rozdíl zapiš do logu.

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md`
2. `scripts/law.gd` (celý) + `data/zakon.json` (řádky s `"trestny_cin": true`, `"misto": "soud"` – 6 řádků)
3. `scripts/debts.gd` (M4.2) a záznam M4.2 v `PROJECT_LOG.md`
4. `scripts/world.gd` – výřezy: `_on_busted` (~ř. 1553), `commit_offense` (~1589), `skip_time` (~1664), `blackout` (~715),
   `teleport_player`, `wanted_until` (grep, ~ř. 2779)
5. `scripts/police.gd` – zadržení (`release`, `breath_test`, `start_chase`)
6. `scripts/jobs.gd` – `_record_clean` (~ř. 370), `on_event` `"busted"` / `"jailed"` (~ř. 1494)
7. `scripts/farm/farm.gd` (péče o zvířata, `tyrani_zvirat`), `scripts/garden.gd` (denní krok, `MAX_CATCHUP_DAYS`)
8. `scripts/save_game.gd` – klíč `law`

## 1. Proč
Trestné činy (řízení nad 1 ‰, řízení přes zákaz, pytláctví, nedovolené ozbrojování, ublížení na zdraví,
krádež ve velkém…) se v ČR řeší **soudně**. Hra to zjednoduší, ale důsledky budou citelné – včetně vězení,
které se promítne do celého života ve hře (práce, zvířata, zahrada, pověst).

## 2. Co už v kódu je
- **`Law.criminal_record` ani tabulka `SENTENCES` neexistují.** Trestné činy jsou záznamy `records[]` s `trestny_cin: true`
  (čte je `Jobs._record_clean` pro požadavek `rejstrik_cisty`). → Rejstřík trestů zaveď jako **pohled**:
  `LawRecord.criminal_record() -> Array` (záznamy s `trestny_cin` + `rozsudek`, viz 3.3), `_record_clean` přepni na něj.
  Tresty dej do `data/zakon.json` (sekce `tresty`), ne do kódu.
- `Jobs.on_event("jailed")` už dává výpověď („nástup do vězení“); `"busted"` taky. Událost `jailed` zatím nikdo neposílá.
- **`_on_busted` (world.gd) míchá dvě věci:** záchytku (poplatek, noc do rána, `skip_time`) a zadržení za přestupek /
  trestný čin (pokuta, body, odtah auta). Rozděl na `_sober_up_cell(id)` (záchytka) a `_detain(id, offense_res)`
  (zadržení → u trestného činu obvinění a předvolání). Řízení nad 1 ‰ (`alkohol_nad_1`, `trestny_cin: true`) pak dělá obojí.
- **Autobusová zastávka ve hře není** (jen zmínky v dialozích; grep `zastavk|bus_stop`). Pro „odvoz k soudu“ a návrat
  z vězení buď přidej zastávku jako místo (cedule + lavička u hlavní silnice na návsi, `World.places["zastavka"]`, F2 teleport),
  nebo použij úřad – rozhodni a zapiš. Autobus jako vozidlo neřeš (případně M5.11).
- `Player.wanted_until` existuje (pronásledování, `police.gd`); zatykač po nedostavení k soudu ho použije.
- **Výkon `skip_time` o měsíce:** `skip_time` posune `Clock` jedním skokem a `BodyState.skip_hours` – ostatní systémy
  (zahrada `MAX_CATCHUP_DAYS`, farma, `Debts.daily`, `Jobs`, nájem, sezónní předměty, počasí) dohánějí po dnech nebo vůbec.
  Vězení (měsíce až roky) **nesmí** projít stovky dní plné simulace najednou → napiš `World.skip_long(id, days)`, která
  spočte výsledky souhrnně (uschlá zahrada, uhynulá zvířata, dluhy po měsících, výpověď) a teprve pak posune hodiny.

## 3. Návrh
### 3.1 Tok trestného činu
1. Čin zjištěn → policie: zadržení (`_detain`) → „Byl jsi obviněn z …“, záznam ve stavu `obvineni`.
2. Za 3–7 herních dní **předvolání k soudu** (pošta + dopis do schránky, M4.2) na konkrétní den a hodinu. Soud = budova
   ve vedlejším městě **mimo mapu** (nejmenovat reálnou obec) → hráč musí být v daný čas na autobusové zastávce / u úřadu
   („odvoz k soudu“), pak `blackout` a posun času (jednání 4 herní hodiny).
3. **Jednání** (`open_menu` dialog): obžaloba přečte skutek (text ze spisu), hráč volí „Přiznat a litovat“ / „Mlčet“ /
   „Zapírat“ (+ „Vzít si obhájce“ za 5 000 Kč – lepší šance). Výsledek podle závažnosti, recidivy (`criminal_record`),
   pověsti, karmy (jen jako polehčující okolnosti), volby. Tresty (`zakon.json` → `tresty`, každé číslo „ověřit“):
   - peněžitý trest (10 000–200 000 Kč) → **`Debts.add(pid, "trest", …)`** (M4.2 – žádný nový platební kód),
   - **zákaz činnosti** (řízení 1–10 let → `permits.revoke("ridicsky", …)` + `license_suspended_until`; držení zbraně, lov →
     `revoke` u `zbrojni` / `lovecky_listek`),
   - **obecně prospěšné práce** (50–300 h – odpracovat úklidem obce: úkoly obecní údržby z M3.2 bez mzdy, lhůta 1 rok),
   - **podmínka** (1–3 roky; další trestný čin během podmínky → vězení),
   - **nepodmíněný trest** (3 měsíce – 3 roky) u těžkých / opakovaných činů.
   Nepřijde → rozhodnutí v nepřítomnosti (horší) + zatykač (`wanted_until` dlouhý, policie hráče při setkání zadrží).
4. Zápis rozsudku do záznamu (`rozsudek: {druh, delka, do_jd}`) → `criminal_record`, `Jobs` (`rejstrik_cisty`), M4.6.

### 3.2 Vězení (souhrnný časový skok)
- Nástup: `blackout`, text „Nastupuješ výkon trestu (8 měsíců).“ → `skip_long` (konstanta `PRISON_TIME_SCALE`,
  výchozí 1.0 = skutečná herní doba; uživatel může zkrátit). Emit `jailed` (Jobs → výpověď, rozdělané úkoly selžou).
- Souhrnné následky (každý systém dostane jednu funkci „uplynulo N dní bez hráče“):
  - **zvířata** (M2.6): bez péče část uhyne; soused s přátelstvím ≥ 60 se postará (M0.6),
  - **zahrada** zaroste plevelem, plodiny uschnou; **auto** stojí (vybitá baterie – nastartuje po zaplacení 1 800 Kč),
  - účet běží, `Debts` dohnat po měsících (exekuce pokračují), nájem bytu → dluh / výpověď z nájmu (rozhodni, zapiš),
  - pověst −20, karma +5 (odpykání), respekt komunit −10 (kromě `stamgasti` „slavný návrat“ +5 – humor bez zlehčování),
  - tělo: vystřízlivění, nikotin 0, hmotnost −3 kg.
- **Podmíněné propuštění** v polovině trestu při dobrém chování (šance podle karmy).
- Po propuštění: hráč u autobusové zastávky obce, text shrnutí (co se změnilo), pošta s přehledem. Vězení se nezobrazuje –
  jen zatemnění a text.

### 3.3 Ukládání
Obvinění, předvolání (datum, hodina), rozsudky v `records`, OPP (odpracováno / zbývá / lhůta), podmínka (do), zatykač.
Vše v klíči `law` (rozšíření z M4.2) s výchozími hodnotami pro starý save.

## 4. Minimum
`criminal_record` jako pohled, rozdělení `_on_busted`, předvolání + jednání s volbami, tresty peněžitý / zákaz / podmínka,
`skip_long` pro vězení se souhrnem (práce, zahrada, zvířata, dluhy). OPP a podmíněné propuštění můžou do otevřených bodů.

## 5. Hotovo, když
- Trestný čin vede k předvolání, jednání s volbami a rozsudku podle tabulky; OPP jdou odpracovat; vězení posune čas
  bez zamrznutí hry a má citelné následky; propuštění se shrnutím; vše se ukládá.

## 6. Návrh checklistu ručních testů
1. Řízení s 1,5 ‰ → záchytka do rána **a** obvinění → za pár dní předvolání (pošta + schránka).
2. Buď v určený čas na zastávce → jednání → „Přiznat“ → podmínka + zákaz řízení (P ukazuje odebráno).
3. Peněžitý trest → objeví se v dluzích (M4.2), zaplať na úřadě.
4. Během podmínky další trestný čin → vězení; hra nezamrzne; shrnutí (práce, zvířata, zahrada, auto, dluhy).
5. Nepřijď k soudu → rozhodnutí v nepřítomnosti, hledaný; policie tě zadrží.
6. OPP: odpracuj 10 h úklidem → zbývá méně.
7. Deník: rejstřík trestů; práce s `rejstrik_cisty` tě nevezme.
8. F5/F9 → předvolání / podmínka / OPP zůstanou.

## 7. Závěr
README, GAME_DESIGN, `data/zakon.json`, VIZE odškrtnout, roadmapa README, PROJECT_LOG, commit „M4.3 Soud a vězení: …“,
checklist a čekat.
