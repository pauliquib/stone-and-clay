# Úkol 06/10 – NPC, doprava a policie přes síť + oblast zájmu (verze 0.4)

## Kontext (přečti nejdřív)
Pracuješ na hře **Dukelčice** – Godot 4.3, GDScript, složka `` v repozitáři
„domov hráče“. Než začneš, přečti:
- `GAME_DESIGN.md` – herní dokument (hlavně kap. 5 pravidla a kap. 6 multiplayer),
- `README.md` – ovládání, data, ladicí parametry (`--shot`, `--testmove`, …),
- konec `PROJECT_LOG.md` (poslední 2–3 záznamy) – co udělaly předchozí úkoly,
- `prompts/README.md` – přehled všech 10 úkolů, ať víš, co je mimo rozsah.

Obecná pravidla:
- Piš česky (komentáře, UI, log), drž styl okolního kódu.
- **Testování – dělá výhradně uživatel, naplno se věnuj programování:**
  - Hru, testy ani simulace (`godot …`, `run.sh`, `--questtest`, `--shot`, headless běhy…)
    **nikdy nespouštěj**, pokud k tomu tě uživatel výslovně nepověří. Co jde ověřit čtením kódu,
    ověř čtením.
  - Testovací skripty a parametry, které úkol požaduje, napiš, ale nespouštěj je – slouží uživateli.
  - Po dokončení programování: zapiš log, commitni a vypiš uživateli **checklist ručních testů
    (max. 10 bodů)** – u každého co spustit / kam ve hře jít, co udělat a co má být vidět.
    Pak skonči a počkej na výsledky.
  - Když uživatel pošle výsledky, oprav nahlášené chyby (opět bez vlastního dlouhého testování),
    doplň log a commitni. Když něco nejde ověřit, napiš to.
- Singleplayer nesmí přestat fungovat.
- Na konci: doplň záznam do `PROJECT_LOG.md` (datum, co je hotovo, otevřené body),
  aktualizuj `README.md`/`GAME_DESIGN.md` pokud se mění ovládání nebo návrh, a commitni.

## Cíl
Živý svět je stejný pro všechny hráče a síť ani server se nezahltí. Předpoklad: úkoly 03–05.

## Co udělat
1. **Simulace jen na serveru:** vesničané, psi, obsluha míst, AI doprava, policie. Klienti je
   jen zobrazují (interpolace 10 Hz: pozice, směr, animace, pozdrav/štěkání přes RPC).
2. **Oblast zájmu 400 m:** filtr viditelnosti `MultiplayerSynchronizer` (a spawneru) podle
   vzdálenosti od hráče klienta; mimo okruh se objekty klientovi despawnou.
3. **LOD simulace na serveru:** plná fyzika v okolí *libovolného* hráče, jinde zjednodušený pohyb
   po grafu (rozšiř dnešní „boti bez fyziky daleko od hráče“ na více hráčů).
4. **Reakce na hráče:** NPC zdraví/otáčí se na nejbližšího hráče, psi běží za nejbližším.
5. **Policie:** hlídka a pronásledování cílí na konkrétního hráče-řidiče; dechová zkouška měří
   jeho ‰ (serverový `BodyState`), pokuty a zabavení auta jdou jemu. Spolujezdci = svědci.
6. **Měření provozu:** vypisuj kB/s na klienta (in/out) a počet synchronizovaných objektů;
   cíl ≤ 60 kB/s na klienta při 8 hráčích.

## Test (připrav skript / postup pro uživatele – viz pravidla testování)
Host + 3 klienti rozmístění daleko od sebe (ves, les, chata) + 1 u hostitele; ověř, že každý vidí
jen své okolí, NPC se nechovají různě na různých klientech a policie zastaví správného hráče.

## Hotovo, když (ověří uživatel podle checklistu)
- Naměřený síťový provoz a výkon serveru (ms/snímek) jsou v logu.
