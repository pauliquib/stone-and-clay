# Příroda 05 – Zvěř, počasí a kalendář v multiplayeru

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

Navazuje na hlavní úkoly `prompts/03_sitovy_zaklad.md` a `06_npc_doprava_policie_mp.md` – zadávej až po nich.

## Cíl
Příroda musí být pro všechny hráče stejná: počasí, čas, zvířata i koně simuluje server.

## Co udělat
1. **Kalendář a počasí**: server posílá `Clock.minutes`, `start_jd`, `speed` a `Weather.state()` (pár čísel
   po ~2 s, při změně hned); klient interpoluje. Herní menu F2 (`GameMenu`) v MP: datum, čas a počasí
   smí měnit jen hostitel; teleport a přistavení vozidla jen když to hostitel povolí (nastavení lobby).
   Blesky (`Weather.lightning`) jako RPC s polohou.
2. **Zvěř**: `Animal` běží na serveru; klientům jde poloha, yaw, rychlost a stav (graze / flee / rest…)
   v oblasti zájmu 400 m; animaci (`QuadrupedRig`) počítá klient z rychlosti. LOD `Animal._update_lod`
   podle nejbližšího hráče už je – ověř s více hráči.
3. **Ptáci a hmyz**: hejna stačí deterministicky ze seedu + stav hejna (mode, spot) – klient simuluje let
   sám; včely a mravenci jsou čistě klientské efekty, jen „rozzlobené včely“ a bodnutí řeší server.
4. **Koně**: každý hráč má svého; jezdec má autoritu nad pohybem koně (jako řidič nad autem – úkol 05),
   server kontroluje rychlost; cizí kůň jde půjčit (`World.nearest_mountable_horse`).
5. Zátěžový test: 4 hráči v různých koutech katastru – počet aktivních zvířat v plném LOD a provoz.

## Hotovo, když
- Dva hráči vidí stejné počasí, čas, stejná zvířata na stejných místech a stejné blesky.
- Jízda na koni a útěk zvěře vypadají u druhého hráče plynule.
