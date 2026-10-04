# Úkol 05/10 – Auta v multiplayeru

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
Hráči mohou řídit, vozit se spolu a bourat. Předpoklad: úkoly 03–04.

## Co udělat
1. **Autorita řidiče:** při nástupu na místo řidiče `set_multiplayer_authority(řidič)`, fyzika
   `VehicleBody3D` běží u něj; ostatní (a server) interpolují + extrapolují podle rychlosti.
   Synchronizace 20 Hz: transform, lineární/úhlová rychlost, natočení a otáčky kol, rychlostní
   stupeň, světla, blinkry, brzdová světla, klakson (RPC).
2. **Prázdné auto** = autorita server, synchronizace jen v pohybu.
3. **Předání autority** bez skoku (při výstupu řidiče, odpojení řidiče – auto zabrzdí a zůstane).
4. **Spolujezdci:** až 5 míst dle modelu auta; interakce „nastoupit“ vybere nejbližší volné dveře.
   Spolujezdec: rozhlížení, rádio/okno (pokud existuje), přesednout za volant jen když auto stojí.
   Postavy sedí správně (animace sezení z `humanoid.gd`).
5. **Poškození:** řidič hlásí kolize serveru (síla, bod), server rozhoduje o poškození a
   rozesílá deformaci všem; zranění posádky podle síly nárazu.
6. **Srážka auta s hráčem/NPC** řešená na serveru (hlášení od řidiče + kontrola), `pvp_damage`
   respektováno.
7. AI auta a policejní auta zatím zůstávají serverová (síťově je dořeší úkol 06), ale ať se
   s auty hráčů fyzikálně nepřekrývají.

## Test (připrav skript / postup pro uživatele – viz pravidla testování)
Automatizovaný: host + klient, klient nastoupí, projede trasu, zastaví, host přistoupí jako
spolujezdec, výměna řidiče, náraz do zdi – porovnej stav poškození na všech instancích.

## Hotovo, když (ověří uživatel podle checklistu)
- Jízda cizího auta se u ostatních jeví plynule (i při 100 km/h), poškození je všude stejné.
