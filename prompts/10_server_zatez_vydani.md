# Úkol 10/10 – Dedikovaný server, zátěžový test a vydání (verze 1.0 kandidát)

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
Hra je připravená k hraní s kamarády přes internet. Předpoklad: úkoly 01–09.

## Co udělat
1. **Dedikovaný server:** `godot --headless --path . -- --server --port=7777 --world=<svět>
   --password=… --max=8`; bez renderu a textur (nenačítat vizuální meshe, jen kolize a data),
   konzolové příkazy (`status`, `kick`, `save`, `say`, `quit`), log do souboru.
   Skript `server.sh` + ukázková systemd služba v README.
2. **Zátěžový test:** „boti-klienti“ (headless klienti řízení skriptem – chodí, jezdí, nakupují,
   pijí), 8 současně. Změř: CPU/RAM serveru, ms na tick, kB/s na klienta, desynchronizace.
   Oprav úzká místa.
3. **Robustnost:** validace všech RPC na serveru (kdo volá, vzdálenost, rozsah hodnot, rate
   limit), odolnost proti náhodnému odpojení uprostřed jízdy/úkolu/nákupu.
4. **Hraní přes internet:** návod na přesměrování portu; prozkoumej a v logu doporuč řešení bez
   přesměrování (Steam Networking / GodotSteam, vlastní relay, WebRTC) – implementace jen pokud
   je jednoduchá.
5. **Export:** export presety Linux + Windows, ověř spuštění exportované verze (data v `data/`,
   textury), velikost balíčku.
6. **Lokalizace:** vytáhni texty UI do překladových souborů (CZ výchozí, EN) – nemusí být
   přeloženo vše, ale ať je infrastruktura.
7. **Dokumentace:** README (hraní v MP, server, porty), GAME_DESIGN (skutečný stav, kap. 7
   plán dál), `CHANGELOG.md`.

## Hotovo, když (ověří uživatel podle checklistu)
- 8 boti-klientů 30 min na dedikovaném serveru bez pádu a bez výrazné desynchronizace,
  čísla v logu.
- Exportovaná hra na Linuxu i Windows se připojí k dedikovanému serveru.
