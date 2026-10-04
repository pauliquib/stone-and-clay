# Příroda 01 – Ladění modelů a animací zvířat

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
Zvířata už ve hře jsou (procedurální modely z `AnimalSpecs`, animace `QuadrupedRig`), ale první verze
se ladila jen dvěma snímky. Doladit vzhled a pohyb tak, aby zvířata vypadala věrohodně zblízka i zdálky.

## Co udělat
1. Nech si od uživatele poslat připomínky ke vzhledu (nebo si udělej 1 sérii snímků `zoo.gd --series`).
   Typicky: proporce hlavy divočáka, postoj zajíce (dlouhé zadní běhy, sed), srnec (štíhlý krk, výrazné
   zrcátko), kůň (hříva, kopyta, šíje), barvy srsti (sRGB), přechod nohou do trupu.
2. Nohy na svahu: dnes jsou nohy svislé vůči trupu, trup se naklání se svahem. Přidej jednoduchou IK
   chodidel – paprsek dolů pod každé kopyto a zkrácení / prodloužení nohy (skládání článků), ať kopyta
   nestojí ve vzduchu ani v zemi na nerovném terénu.
3. Plynulé přechody: lehnutí / vstávání (nejdřív přední, pak zadní nohy u srnce a koně; kůň vstává
   předníma), otočení na místě (přešlapování), zastavení z trysku (zadní nohy pod tělo).
4. Srnčí skoky při útěku (vysoké oblouky přes překážky i bez nich, „odrazové“ skoky), zajíc – sed na
   zadních a „panáček“ při rozhlížení, divočák – rytí s viditelným odhrnutím hlíny (drobné částice).
5. Ptáci: kos – ocas se při dopadu zvedne, vrána – kráčivá chůze s kýváním hlavy, vlaštovka – rychlé
   klouzavé úseky, káně – roztažené „prsty“ letek na koncích křídel.
6. Výkon: změř `--shot` na místě s hejnem vran a srnci (draw calls, FPS); když je zvířat hodně vidět,
   slouč meshe končetin do jednoho MultiMesh / skinned meshe nebo přidej LOD (dálka = 1 mesh bez nohou).

## Hotovo, když (ověří uživatel)
- V zoo i ve hře zvířata zblízka nemají díry, protínání, plovoucí kopyta; chody vypadají přirozeně.
- FPS u domu hráče a u hejna vran se proti stavu před úkolem nezhorší o víc než 5 %.
