# Úkol 02/10 – Refaktor architektury pro multiplayer (bez sítě)

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
Připravit kód na multiplayer tak, aby síť v úkolu 03 šla „jen zapojit“. Žádná síť zatím,
chování hry se nesmí změnit.

## Co udělat
1. Rozděl `main.gd` (~980 řádků) na:
   - **`world.gd`** – simulace světa (terén, mapa, čas, NPC, doprava, policie, předměty, místa,
     úkoly, ekonomika) – to, co v MP poběží na serveru;
   - **`local_client.gd`** – vše pro lokálního hráče (HUD, kamera, `drunk_fx`, zvuky, vstup,
     mapa M, nápověda).
2. Zaveď **seznam hráčů** místo jediné proměnné `player` (`world.players: Dictionary` id → Player,
   lokální hráč id 1). Všechna místa, kde NPC/policie/úkoly/předměty hledají „hráče“, přepiš na
   „nejbližší hráč“ / „konkrétní hráč“.
3. `emit_game_event(event, data)` doplň o `player_id`; `Quests` a `BodyState` mějte **per hráč**.
4. Oddělte **vstup od pohybu** v `player.gd` a `car.gd`: struktura `InputState` (pohyb, pohled,
   skok, sprint, …), kterou plní lokální vstup – později ji půjde plnit ze sítě.
5. Uprav testy v `tests.gd`, aby běžely nad novou strukturou.

## Hotovo, když (ověří uživatel podle checklistu)
- Všechny existující testy (`--testmove`, `--bottest`, `--drinktest`, `--questtest`, `--probe`)
  procházejí, snímek `--shot` vypadá stejně.
- Nikde v kódu nezůstal předpoklad „existuje právě jeden hráč“ (zkontroluj grep).
- V logu je stručná mapa nové architektury (kdo za co odpovídá).
