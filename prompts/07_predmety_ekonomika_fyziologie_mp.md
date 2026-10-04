# Úkol 07/10 – Předměty, inventář, ekonomika a fyziologie přes síť

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
Vše, co má hodnotu nebo mění stav hráče, rozhoduje server. Předpoklad: úkoly 03–06.

## Co udělat
1. **Předměty ve světě** (hřiby, jablka, dukáty, zlaté žaludy, lahve, props u domu): spawn na
   serveru, sebrání = žádost klienta → server ověří vzdálenost a dostupnost → potvrdí / odmítne.
   Kdo dřív přijde. Denní obnova podle serverového času.
2. **Inventář a peníze** per hráč na serveru, klient dostává změny RPC. Předání věci/peněz
   jinému hráči (interakce „dát“ – lahev, cigaretu, peníze).
3. **Nákupy v místech** (`place.gd`): otevírací doby, ceny, platba – vše serverově.
4. **Fyziologie:** `BodyState` každého hráče běží na serveru; vlastník dostává detail 2 Hz
   (‰, zdraví, nikotin, nevolnost…), ostatní jen stupeň opilosti a akce (kvůli animacím –
   potácení, zvracení, kouření, ležení).
5. **Akce s animací** (pití, jídlo, kouření, zvracení, bezvědomí, přípitek) se přehrávají
   u všech klientů.
6. **Bezvědomí/smrt** v MP: probuzení doma se ztrátou části peněz, bez pauzy světa.
7. Rozbití lahve, pád, zranění – serverově, efekty na klientech.

## Test (připrav skript / postup pro uživatele – viz pravidla testování)
Dva klienti běží ke stejnému hřibu – sebere ho jen jeden. Nákup v hospodě, předání piva druhému
hráči, vypití – ‰ roste jen tomu, kdo pil, a je stejné na serveru i v HUD.
