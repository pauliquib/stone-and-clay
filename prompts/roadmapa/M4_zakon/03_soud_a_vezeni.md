# M4.3 – Soud a vězení

> Roadmapa „Život na vsi“ · **M4 Zákon a společnost** · krok 3/6
> Předpoklady: M0.5, M4.2 · Navazují: M4.6 (pytláctví, nedovolené ozbrojování jako trestné činy), M3.1 (výpověď)

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md`
2. `scripts/law.gd` + `data/zakon.json` (záznamy s `trestny_cin: true`)
3. `scripts/world.gd` – `_on_busted` (záchytka), `skip_time`, `blackout`, `teleport_player`
4. `scripts/police.gd` – zadržení (grep `busted|zadrz|arrest`)
5. `scripts/jobs.gd` (M3.1), `scripts/farm/*` (M2.6 – zvířata bez péče), `scripts/garden.gd` (M2.4)
6. `scripts/computer_ui.gd` – `send_mail` (předvolání)

## 1. Proč
Trestné činy (řízení nad 1 ‰, řízení přes zákaz, pytláctví, nedovolené ozbrojování, ublížení na zdraví,
krádež ve velkém…) se v ČR řeší **soudně**. Hra to zjednoduší, ale důsledky budou citelné – včetně vězení,
které se promítne do celého života ve hře (práce, zvířata, zahrada, pověst).

## 2. Návrh
### 2.1 Tok trestného činu
1. Čin zjištěn → policie: zadržení (už existuje – záchytka / cela do rána) → „Byl jsi obviněn z …“.
2. Za 3–7 herních dní **předvolání k soudu** (pošta + dopis) na konkrétní den a hodinu. Soud = budova ve vedlejším
   městě **mimo mapu** → přejezd se neřeší: hráč musí být v daný čas u autobusové zastávky / na úřadě („odvoz k soudu“),
   pak ztmavení a přesun v čase (celé jednání trvá 4 herní hodiny).
3. **Jednání** (UI dialog): obžaloba přečte skutek (text z rejstříku), hráč volí: „Přiznat a litovat“ / „Mlčet“ / „Zapírat“
   (+ „Vzít si obhájce“ za 5 000 Kč – lepší šance). Výsledek podle: závažnosti, recidivy (rejstřík), pověsti, karmy
   (M0.6 – soud „cítí“ karmu jen nepřímo: polehčující okolnosti), volby. Tresty (tabulka `SENTENCES` v `data/zakon.json`):
   - peněžitý trest (10 000–200 000 Kč),
   - **zákaz činnosti** (řízení 1–10 let, držení zbraně, lovu),
   - **obecně prospěšné práce** (50–300 hodin – odpracovat úklidem obce: znovu použij úkoly obecní údržby z M3.2
     bez mzdy, lhůta 1 rok),
   - **podmínka** (1–3 roky; další trestný čin během podmínky → vězení),
   - **nepodmíněný trest** (vězení 3 měsíce – 3 roky) – u těžkých / opakovaných činů.
   Nepřijde → rozhodnutí v nepřítomnosti (horší) + zatykač (`wanted_until`).
4. Zápis do **rejstříku trestů** (`Law.criminal_record`) → vliv na práci (M3.1 `rejstrik_cisty`), zbrojní oprávnění (M4.6).

### 2.2 Vězení (časový skok s následky)
- Nástup: ztmavení, text „Nastupuješ výkon trestu (8 měsíců).“ → `World.skip_time` o celou dobu (**volitelně zkrácenou**:
  konstanta `PRISON_TIME_SCALE` – výchozí 1.0 = skutečná herní doba; uživatel může zkrátit), během toho:
  - práce → výpověď, rozdělané úkoly selžou,
  - **zvířata** (M2.6): pokud se o ně nikdo nestará → část uhyne / sousedé (přátelství ≥ 60) se postarají (M0.6),
  - **zahrada** zaroste plevelem, plodiny uschnou, **auto** stojí (baterie vybitá – nejde nastartovat, dokud nezaplatíš
    výměnu 1 800 Kč / nepůjčíš kabely),
  - hotovost zabavena? ne – zůstává; účet běží; exekuce pokračují,
  - pověst −20, karma se **zlepší** o 5 (odpykání), respekt komunit −10 (kromě `stamgasti`, kde „slavný návrat“ +5 – humor),
  - tělo: vystřízlivění, nikotin 0 (pokud nekouřil…), hmotnost −3 kg.
- **Podmíněné propuštění** v polovině trestu při dobrém chování (náhodná šance podle karmy).
- Po propuštění: hráč u autobusové zastávky obce, text shrnutí (co se změnilo), pošta s přehledem.
- **Zobrazení vězení:** jen shrnutí (text + pár obrázků-scén z MeshKit? ne – stačí text a zatemnění). Humor bez zlehčování.

### 2.3 Ukládání
Obvinění, předvolání (datum), rozsudky, OPP (odpracováno / zbývá), podmínka (do), rejstřík.

## 3. Hotovo, když
- Trestný čin vede k předvolání, jednání s volbami a rozsudku podle tabulky; OPP jdou odpracovat; vězení posune čas
  a má citelné následky; propuštění se shrnutím; vše se ukládá.

## 4. Návrh checklistu ručních testů
1. Řízení s 1,5 ‰ → zadržení → za pár dní předvolání (pošta + schránka).
2. Buď v určený čas na zastávce → jednání → „Přiznat“ → podmínka + zákaz řízení.
3. Během podmínky další trestný čin → vězení; sleduj shrnutí (práce, zvířata, zahrada, auto).
4. Nepřijď k soudu → rozhodnutí v nepřítomnosti, hledaný.
5. OPP: odpracuj 10 h úklidem → zbývá méně.
6. Deník: rejstřík trestů.
7. F5/F9 → předvolání / podmínka zůstanou.

## 5. Závěr
README, GAME_DESIGN, `data/zakon.json`, VIZE odškrtnout, roadmapa README, PROJECT_LOG, deník AI, commit „M4.3 Soud a vězení: …“, checklist a čekat.
