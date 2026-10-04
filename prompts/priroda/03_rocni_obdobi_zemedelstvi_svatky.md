# Příroda 03 – Roční období: pole, sezónní předměty, svátky v obci

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
Roční období už mění stromy, trávu, sníh a teploty. Doplnit, aby se měnila i krajina a život v obci.

## Co udělat
1. **Pole**: rozliš pole v ortofotu (maska z barvy nebo z OSM landuse – `tools/export_map.py`) a podle
   kalendáře je kresli: podzimní orba (hnědá), ozim (zelená), obilí (zlaté v červenci), strniště po
   žních, řepka (žlutá v květnu), kukuřice (vysoká v září). Traktor / kombajn na poli v sezóně (AI vozidlo
   po poli, ne po silnici) – volitelně.
2. **Louky a zahrady**: květy v trávě na jaře (MultiMesh drobných květů v okolí hráče), ovoce na stromech
   v zahradách v létě / na podzim (jablka jako předmět už existují – vázat na měsíc), padané listí.
3. **Sezónní předměty** (`item.gd`, `world._spawn_items`): hřiby hlavně po dešti od července do října,
   jablka srpen–říjen, v zimě místo nich např. šípky; předměty se obnovují podle počasí.
4. **Svátky a události** (`Clock.holiday()` už je): vánoční výzdoba (světýlka na domech, stromek na návsi,
   sníh), masopust (průvod masek po obci – vesničané v kostýmech), pálení čarodějnic 30. 4. (hranice
   a oheň u hřiště), hody / posvícení, Silvestr (ohňostroj o půlnoci). Místa a NPC na to reagují
   (hospoda déle otevřeno, jiné nabídky, úkoly).
5. **Den v týdnu**: v neděli zavřený obchod, v pátek plná hospoda, víkend víc lidí venku.

## Hotovo, když
- Přes F2 → Roční období je vidět rozdíl mezi dubnem, červencem, říjnem a lednem i na polích a v obci.
- Na Štědrý den, 30. 4. a 31. 12. je v obci odpovídající výzdoba / událost.
