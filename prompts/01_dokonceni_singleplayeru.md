# Úkol 01/10 – Dokončení singleplayeru (verze 0.2)

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
Stabilní singleplayer jako základ, na který se bude stavět multiplayer.

## Co udělat
1. **Úkoly:** projdi všech 6 úkolů v `quests.gd` v reálné hře (`--questtest`, případně rozšiř test,
   aby prošel každý úkol od přijetí po odměnu i variantu selhání). Oprav nalezené chyby.
2. **AI doprava:** dořeš zpomalování AI auta za obecním úřadem (~t=50 s v testu), ověř dojezd celé
   trasy a že auta nezůstávají viset na křižovatkách.
3. **Noc a světla:** snímky ve 22:00 a 2:00 (lampy, světla aut, okna, měsíc) – ať je noc hratelná,
   ne černá.
4. **Výkon:** dnes ≈2 800 draw calls. Změř (Monitor/`Performance`), sniž pod ~1 500 (sloučení
   meshů budov/silnic po dlaždicích, MultiMesh pro opakované props, vzdálenostní skrývání NPC).
   Cíl 60 FPS ve vsi i při jízdě autem.
5. **README:** nové ovládání (auta, interakce, inventář Tab, deník J), systémy (fyziologie,
   policie, místa, úkoly).

## Hotovo, když (ověří uživatel podle checklistu)
- Všech 6 úkolů je prokazatelně splnitelných i selhatelných, test to ověří.
- FPS/draw calls před a po jsou zapsané v logu.
- README odpovídá hře.
