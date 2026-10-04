# Příroda 04 – Zvěř a hráč, myslivost, péče o koně

## Kontext (přečti nejdřív)
Pracuješ na hře **Dukelčice** – Godot 4.3, GDScript, složka `` v repozitáři „domov hráče“.
Než začneš, přečti:
- `ZVIRATA.md` – kde jsou tabulky zvířat, počasí a ročních období a jak se upravují,
- `README.md` (Systémy, Ovládání, Ladicí parametry) a konec `PROJECT_LOG.md`
  (záznam „Příroda: zvěř, ptáci, hmyz, kůň, počasí, roční období“ a novější),
- `prompts/priroda/README.md` – přehled navazujících úkolů.

Obecná pravidla:
- Piš česky (komentáře, UI, log), drž styl okolního kódu. Hodnoty, které půjde ladit, dej do tabulek /
  konstant nahoře v souboru (jako `AnimalSpecs`, `Weather.TYPES`), ať je uživatel snadno upraví.
- **Testování dělá výhradně uživatel:** hru, testy ani simulace (`--faunatest`, `tools/dev/zoo.gd`,
  `--shot`, `godot --headless …`) **nikdy nespouštěj**, pokud tě k tomu uživatel výslovně nepověří;
  co jde, ověř čtením kódu. Na konci zapiš log, commitni a vypiš uživateli **checklist ručních testů (max. 10 bodů)**
  – co spustit, kam jít (herní menu F2 → Teleport / Datum / Počasí), co udělat, co má být vidět – a čekej.
- Když uživatel pošle výsledky, oprav nahlášené chyby, doplň log a commitni.
- Singleplayer nesmí přestat fungovat. Commituj jen své soubory / změny (v repozitáři může pracovat
  i jiná session – `git add -p` neumíš, použij `git diff … > patch` + `git apply --cached` na své hunky).
- Na konci: záznam do `PROJECT_LOG.md` (datum, hotovo, otevřené body), aktualizuj `README.md` / `ZVIRATA.md`.

## Cíl
Propojit faunu s hrou: následky, úkoly a péče – bez násilí na zvířatech jako hlavní náplně.

## Co udělat
1. **Srážka se zvěří** (`World._on_hit_person` → `hit_animal`): poškození auta podle hmotnosti zvířete
   a rychlosti (srnec vs. divočák), zranění řidiče; povinnost nahlásit (Myslivecká chata / telefon)
   – úkol „Srážka se zvěří“ (nahlásit do hodiny, jinak pokuta). Mrtvé zvíře leží u silnice, myslivec
   (NPC) pro něj přijede.
2. **Myslivec** na posedu a u krmelce (v zimě přikrmuje – zvěř se u krmelce shromažďuje), rozhovor
   a úkoly: sčítání zvěře (dalekohled – klávesa, přiblížení kamery), odnést krmivo, najít shoz
   (shozené parůžky srnce v březnu – sběratelský předmět).
3. **Stopy ve sněhu** (decaly) za zvířaty i hráčem – dle `Weather.snow_cover`.
4. **Kůň**: stáj u domu hráče (výběh s ohradou – kolize), krmení a napájení (výdrž se obnovuje rychleji),
   čištění, přivolání hvízdnutím (klávesa – kůň přiklusá, pokud je do ~300 m), jízda opilého jezdce
   (jezdec na zvířeti je účastník provozu – policie může zastavit a dát dýchnout; kůň opilého sám
   zpomalí / nevyjde), druhý jezdec za sedlem (MP).
5. **Včely**: včelař (NPC) u včelnice – úkol vytočit med, kukla a kouřák (bez bodnutí).
6. Deník (J): „Pozorování přírody“ – první setkání s každým druhem (zajíc, srnec, divočák, vrána, kos,
   vlaštovka, káně, včely, mravenci) se zapíše s datem.

## Hotovo, když
- Srážka se srncem autem má následky a navazující úkol; myslivec a krmelec fungují.
- Kůň má výběh, jde přivolat a nakrmit; opilý jezdec řeší policii stejně jako řidič.
