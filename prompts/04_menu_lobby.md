# Úkol 04/10 – Hlavní menu, lobby, připojení a odpojení

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
Hráč se do multiplayeru dostane z UI, ne z příkazové řádky. Předpoklad: úkol 03.

## Co udělat
1. **Hlavní menu** (nová scéna, stejný vizuální styl jako HUD): Hrát sám · Hostovat ·
   Připojit · Nastavení · Konec. Mapa se načítá až po volbě (nebo na pozadí s indikátorem).
2. **Hostovat:** jméno serveru, heslo (volitelné), max. hráčů (2–8), pravidla
   (`pvp_damage` vyp./zap.), port.
3. **Připojit:** IP:port + seznam **LAN serverů** (UDP broadcast/odpověď, jméno, počet hráčů,
   ping). Zadání hesla. Poslední IP pamatovat (`user://settings.cfg`).
4. **Profil hráče:** jméno, jednoduchý vzhled postavy (barva oblečení, účes, pokud to
   `humanoid.gd` umožní) – přenáší se v handshaku.
5. **Seznam hráčů** ve hře (drž Tab nebo jiná volná klávesa – zkontroluj kolize s ovládáním):
   jméno, ping.
6. **Odpojení:** hlášky „X se připojil/odešel“; odchod hostitele → návrat do menu s hláškou;
   pád spojení → pokus o znovupřipojení / návrat do menu.
7. Esc menu ve hře: Pokračovat · Nastavení · Odpojit · Konec.

## Hotovo, když (ověří uživatel podle checklistu)
- Celý tok menu → host → připojení druhé instance → hra → odpojení → menu funguje bez restartu.
- Parametry z úkolu 03 (`--host`, `--join`) dál fungují pro testy.
