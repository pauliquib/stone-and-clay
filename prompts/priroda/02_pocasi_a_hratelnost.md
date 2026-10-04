# Příroda 02 – Počasí a hratelnost

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
Počasí dnes hlavně vypadá (obloha, déšť, sníh, mokro). Má ale mít vliv na hru – realisticky a čitelně.

## Co udělat
1. **Auta** (`car.gd`): přilnavost pneumatik podle `Weather.wetness`, `snow_cover` a teploty (mokro ~0,7,
   sníh ~0,35, náledí pod 0 °C po dešti ~0,15), delší brzdná dráha, stěrače (mesh + animace, klávesa),
   kapky na skle v pohledu z interiéru, zvuk deště na střeše auta (tlumený zvuk venku).
2. **AI doprava a policie**: v dešti, mlze a na sněhu jezdí pomaleji a dál od sebe; v mlze svítí.
3. **Hráč** (`body_state.gd`): promoknutí (déšť bez střechy nad hlavou – paprsek vzhůru) a prochladnutí
   (teplota, vítr, mokré oblečení) → výdrž, třes kamery, v hospodě / doma se osuší a zahřeje;
   kluzká chůze na sněhu a mokré trávě (menší trakce, delší brzdění), stopy ve sněhu.
4. **Kůň**: na náledí a v bahně klouže a zpomalí, v bouřce se plaší (hrom → skok stranou).
5. **Mlha** omezí vzdálenost, na kterou vidí zvěř i hráč; vítr nese pach (už je v `Animal._perceive`).
6. **HUD**: předpověď na zítřek v deníku (J) – jednoduše z `Weather.NEXT` a ročního období;
   ikona počasí vedle hodin.
7. Test `--weathertest`: projede všechny situace (`Weather.force`) a vypíše přilnavost a brzdnou dráhu auta.

## Hotovo, když
- Na mokru / sněhu auto znatelně déle brzdí, na náledí klouže; hráč v dešti promokne a v zimě prochladne.
- Vše laditelné v tabulkách (přilnavost podle povrchu a počasí na jednom místě).
