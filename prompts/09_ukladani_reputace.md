# Úkol 09/10 – Ukládání hry a reputace

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
Postup přežije konec relace; ves si pamatuje, jak se hráč chová. Předpoklad: úkoly 02–08
(ukládání musí fungovat v SP i MP).

## Co udělat
1. **Uložení světa** (server): `user://saves/<svět>.json` – čas, auta (pozice, poškození,
   palivo), stav předmětů, škody, stav míst. Verze formátu + migrace.
2. **Uložení hráčů** na serveru podle jména/ID: pozice, peníze, inventář, úkoly (stav, postup),
   `BodyState` (hmotnost, zdraví, dehet…), reputace. Návrat hráče do světa = jeho postup.
3. **Kdy ukládat:** autosave každé 2–3 min, při odpojení hráče, při odchodu hostitele, ručně
   (Esc menu). Singleplayer: více slotů, v menu „Pokračovat“ / „Načíst“.
4. **Reputace** (0–100, start 50) per hráč:
   - roste: splněné úkoly, pozdravení NPC, pomoc, placení;
   - klesá: škody, srážky, pokuty, zvracení na veřejnosti, opilé řízení viděné svědky;
   - vliv: ceny ±20 %, dostupnost některých úkolů, reakce NPC (pozdrav vs. odvrácení),
     ochota obsluhy nalít opilému.
   Zobraz v deníku (J) s posledními změnami a důvody.
5. **Spánek doma** posune čas – v SP vždy, v MP jen když spí všichni.

## Test (připrav skript / postup pro uživatele – viz pravidla testování)
Uložit → ukončit → načíst: porovnat stav (skript porovná JSON před a po). V MP: hráč se odpojí,
připojí znovu a má svůj inventář a úkol.

## Aktualizuj
`GAME_DESIGN.md` kap. 4, 5 a 6.7.
