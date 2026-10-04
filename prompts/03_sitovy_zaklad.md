# Úkol 03/10 – Síťový základ: host/join a pohyb hráčů (verze 0.3)

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
Dva a více hráčů se pohybují po stejné mapě a vidí se. Předpoklad: hotový úkol 02.

## Co udělat
1. **Autoload `net.gd`**: `host(port=7777, max=8)`, `join(ip, port)`, `leave()`, signály
   `player_joined/left`, `connected/failed`. `ENetMultiplayerPeer`. Singleplayer = host bez klientů
   (nebo `OfflineMultiplayerPeer`) – jedna kódová cesta.
2. **Handshake** (RPC hned po připojení): verze hry, hash `data/map.json`, jméno hráče.
   Neshoda → srozumitelné odmítnutí s důvodem.
3. **Spawn hráčů** přes `MultiplayerSpawner`; spawn u domu hráče s rozestupem.
4. **Pohyb:** autorita postavy = její klient (`set_multiplayer_authority`), synchronizace
   pozice/rotace/rychlosti/stavu animace 20 Hz (`MultiplayerSynchronizer`), vzdálení hráči jsou
   „puppet“ s interpolací (buffer 100 ms). Server kontroluje rychlost a teleporty (> 20 m) a
   případně vrátí pozici.
5. **Čas dne:** serverový, synchronizace 1×/10 s, klient extrapoluje; pauza v MP zakázaná.
6. **Jmenovky** nad hlavami ostatních hráčů, ostatní hráči na mapě (M).
7. Dočasné spuštění z příkazové řádky: `-- --host`, `-- --join=127.0.0.1`, `--name=…`.

## Test (připrav skript / postup pro uživatele – viz pravidla testování)
Skript (např. `tools/dev/mp_test.sh`), který spustí host + 2 klienty (headless nebo v oknech),
klienti se automaticky projdou po trase a na konci se vypíše rozdíl pozic viděných
na serveru a u ostatních klientů. Ověř i simulované zpoždění/ztrátu paketů (pokud to jde, jinak
aspoň odpojení a znovupřipojení).

## Hotovo, když (ověří uživatel podle checklistu)
- 3 instance na jednom stroji se vidí, pohyb je plynulý, odpojení nikoho neshodí.
- Chyba verze/mapy dá jasnou hlášku.
