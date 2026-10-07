# Checklisty ručních testů – M6.1 Dron

> `./run.sh` před testem (obnoví seznam tříd – nové `Drone`, `DroneModel`, `Permits`).
> Cheat: F2 → Hráč → „Drony + registrace ÚVL + A1/A3 (M6.1)" dá oba drony, náhradní baterii a doklady.

## Základní let
1. F2 → Hráč → cheat drony → Tab → detail „Dron Ptáček Mini" → **Vzlétnout**: dron se objeví ~1,4 m
   před hráčem, vysílačka v ruce, automatický vzlet na ~2 m, OSD vlevo dole (AGL, m/s, vzdálenost,
   BAT, SIG, fotek). Bzučení slyšet.
2. WASD + myš: dron letí, natáčí se za pohledem, kamera naklání (FPV); V = pohled za dronem;
   kolečko mění FOV; Shift = sport (rychlejší, OSD ukáže SPORT). Mezerník / Ctrl = stoupat / klesat.
   Hráč stojí na místě (nezalétá, nehybe se).
3. F poblíž (< 3,5 m) = přistání přímo u hráče → dron mizí zpět do batohu, ovládání zpět,
   zpráva se stavem. F ve větší vzdálenosti = „Návrat domů" (RTH) – dron přeletí nad místo startu
   (žlutá H značka) a přistane; F v RTH = zrušit návrat.
4. O / LMB za letu = fotka: záblesk, cvalknutí, hláška „Fotka uložena: dron_jN_fMM.png" –
   soubor v `user://fotky_dron/`. E sebrání zaparkovaného dronu (letěl-li daleko, přistane tam
   a zpráva „seber ho (E)").

## Pravidla a přestupky (svědek = lidé do ~150 m, hlídka 400 m)
5. **Bez registrace**: nová postava bez cheatů / kup dron v Potravinách (Drony a technika, 7 990 Kč),
   vzleť v obci → banner „letíš bez registrace…", po chvilce se svědkem přestupek `dron_bez_registrace`
   (deník J → Úřední záznamy). Stejně vypadne `dron_vyska_120` (stoupej přes 120 m – dron odepře další
   stoupání, OSD „NAD 120 m – PŘESTUPEK!", se svědkem pokuta), `dron_nad_lidmi` (vrtěj ~3 s do 25 m nad
   vesničanem), `dron_mimo_dohled` (odleť > 500 m / za budovu na 60 s – zprvu RTH na ztrátu signálu
   ~1500 m volno / ~400 m za překážkou), `narusovani_soukromi_dron` (vrtěj > 30 s pod 30 m nad cizí
   zahradou v zástavbě).
6. **Registrace a A1/A3**: počítač doma → Letectví – ÚVL → „Registrovat provozovatele (zdarma)" →
   evidenční číslo CZ-DB-…, potvrzovací e-mail v Poště; „Složit test A1/A3" → 10 otázek, práh 8 →
   po složení osvědčení A1A3-… + e-mail. Velký dron (Pro XL) pak letí bez přestupku
   `dron_bez_kvalifikace`; bez něj se svědkem pokuta. V deníku / na stránce flotila s % baterie
   a % poškození.

## Baterie, poškození, nárazy
7. Baterie: sport (Shift) a mráz (F2 → Počasí → Teplota −10) vybíjejí rychleji; na 15 % banner
   „baterie 15 %!", na 5 % automatický RTH, na 0 % dron padá (rotory ztuhnou, volný pád).
   Nabíjení: dron v batohu → PC → Letectví – ÚVL → „Nabít baterii" = 100 %; se skoro vybitou
   baterií v dronu a náhradní v batohu se při startu baterie sama vymění.
8. Nárazy: pomalý ťuk (< ~4 m/s) do zdi = jen cuknutí + poškrábání; rychlý let do zdi / stromu =
   havárie (volný pád, hláška, drb na obecním webu); do koruny stromu = visí 6 s, pak spadne;
   do vesničana = knock + přestupek `dron_zraneni` + havárie. Rozbitý dron (poškození ≥ 55 %)
   sebrat E → Vzlétnout šedé („oprav ho na počítači") → oprava na PC za 1 500 / 4 500 Kč.

## Okolí a persistence
9. Zvěř: přeleť nízko přes srnce / králíka do ~45 m → uteče (plaší ho bzučení). Na kraj katastru
   dron nesmí – zahájí RTH „kraj katastru". Dron zaparkovaný / rozbitý zůstane ve světě viditelný.
10. F5 za letu → F9: hráč nestojí „ve vzduchu ovládání" – dron stojí zaparkovaný pod pozicí, kde
    letěl, flotila drží baterii a poškození, registrace a A1/A3 zůstávají. Save před M6.1 se načte
    bez dronů a bez oprávnění (žádná chyba).
