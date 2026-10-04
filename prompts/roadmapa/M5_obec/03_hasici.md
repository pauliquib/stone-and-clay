# M5.3 – Hasiči: zbrojnice, spolek SDH, výjezdy k požárům

> Roadmapa „Život na vsi“ · **M5 Obec a volný čas** · krok 3/9
> Předpoklady: M2.2 (oheň, `GrassFire`, `fire_report`), M2.3 (oblečení – zásahový oblek), M1.6 (vozidla), M0.6 (respekt `hasici`) · Navazují: M5.4 (hasičský sport), M5.5 (hasičský bál / soutěž jako událost)

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md` (kap. 3 – spolek se smyšleným názvem, bez znaků)
2. `docs/VIZE_A_ROADMAPA.md` – kap. 4.5 „Hasiči (16)“
3. `scripts/fire.gd` (M2.2) – `Fire`, `GrassFire`, událost `fire_report`
4. `scripts/car.gd` / katalog vozidel (M1.6) – jak přidat vozidlo (cisterna), `set_siren` (policejní maják – vzor), `_build_beacons`
5. `scripts/characters.gd` – postava bývalého hasiče (grep `hasic`), `scripts/dialog.gd` – téma `hasici`
6. `data/buildings.json` / `scripts/building_details.gd` (M1.2) – najdi vhodnou budovu pro zbrojnici (typ `public` / garáž u návsi)
7. `scripts/jobs.gd` (vzor členství, ale **bez mzdy**)

## 1. Proč
Uživatel: „přidat hasiče a hasičský sport“. Sbor dobrovolných hasičů je srdce vesnice: výjezdy, tréninky,
soutěže, bály. Propojí oheň (M2.2), respekt a události.

## 2. Co udělat
1. **Hasičská zbrojnice**: budova v obci (vyber z `buildings.json` garáž/veřejnou budovu u návsi, nebo postav procedurálně
   – garáž s vraty, věžička na sušení hadic, siréna na střeše), uvnitř (interiér M1.4 rámec – jednoduchý): cisterna, stojan
   se zásahovými obleky, klubovna se stolem a pohárem. Cedule **bez názvu obce a bez znaku** – neutrální
   „SDH“ se smyšleným přídomkem, např. „SDH Pod Kopcem“.
2. **Spolek:** velitel (NPC – využij postavu bývalého hasiče z `characters.gd` nebo novou), 5–8 členů z vesničanů
   (přiřaď podle povolání / témat). Členství: požádat velitele (respekt `hasici` ≥ 0, střízlivý), členský příspěvek
   200 Kč/rok. Schůze první pátek v měsíci 19:00 v klubovně (NPC se sejdou, krátký text, pivo – respekt +1 za účast).
   **Tréninky** každou středu 18:00 na hřišti (vazba na M5.4).
3. **Hasičská technika:** cisterna (nové vozidlo – velké, pomalé, skupina C – řidič jen velitel/NPC, nebo hráč s cheatem;
   **hráč jezdí jako posádka**: nastoupí dozadu, jízda s majákem a sirénou po trase NPC řidičem – použij AI řízení
   `set_ai_route`), přenosná stříkačka (PS 12 – pro M5.4), hadice, proudnice.
4. **Výjezd k požáru:**
   - Zdroje požárů: `fire_report` z M2.2 (tráva, nehlídaný oheň), náhodné události (hořící tráva u trati v suchém jaru,
     komín – jiskry ze sazí v zimě, auto po nehodě), volitelně stoh slámy v létě.
   - Siréna na zbrojnici (zvuk přes `World.sound`, slyšet v obci), člen spolku v obci dostane zprávu „Výjezd! Požár trávy
     u …“ → má 5 min dojít do zbrojnice (kompas), obléct zásahový oblek (šatna – oblečení M2.3 tag `hasic`), nastoupit.
   - Na místě: hadice z cisterny (jednoduché: hráč drží proudnici – nástroj, LMB = voda – částice vody, oblouk),
     hašení = snižování „plamene“ v buňkách `GrassFire` zasažených vodou; NPC hasiči hasí taky (jednoduše: stojí a „stříkají“
     – částice + snižují oheň v okruhu). Uhašeno → návrat.
   - Odměna: respekt `hasici` +5, pověst +3, XP `hasicina` 50–150; neúčast člena na výjezdu je v pořádku (dobrovolníci).
   - Bez zásahového obleku u ohně → `hurt` a hláška.
5. **Požár způsobený hráčem** (M2.2) – přijedou hasiči i bez hráče; hráč je původce → přestupek (už je), respekt `hasici` −5.

## 3. Minimum
Zbrojnice, spolek s členstvím, výjezd k požáru trávy (hráč jede s cisternou a hasí proudnicí).

## 4. Hotovo, když
- Hráč se stane členem SDH, chodí na schůze, na výjezd přijde siréna, jede s posádkou, hasí požár; výsledky se promítnou do respektu a XP.

## 5. Návrh checklistu ručních testů
1. Zbrojnice v obci: garáž, cisterna, klubovna; velitel → členství.
2. První pátek v měsíci 19:00 → schůze, respekt +1.
3. F2 → cheat „požár trávy“ (přidej) → siréna, zpráva, dojdi do zbrojnice do 5 min, oblek, nastup.
4. Jízda s majákem k požáru; proudnice → hašení, NPC hasí.
5. Bez obleku u plamenů → zranění.
6. Oheň z nedbalosti (M2.2) → hasiči přijedou, přestupek.
7. F5/F9 → členství zůstane.

## 6. Závěr
README (Systémy → Hasiči), VIZE odškrtnout, roadmapa README, PROJECT_LOG, deník AI, commit „M5.3 Hasiči: …“, checklist a čekat.
