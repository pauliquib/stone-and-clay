# Úkol 08/10 – Úkoly v multiplayeru, party, chat a emoty (verze 0.5)

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
Kooperace podle GAME_DESIGN kap. 6.5. Předpoklad: úkoly 03–07.

## Co udělat
1. **Úkoly per hráč** na serveru; `emit_game_event` z klientů chodí jako RPC na server,
   který ho vyhodnotí pro správného hráče (a jeho partu).
2. **Party:** pozvat hráče (interakce nebo seznam hráčů), přijmout/odmítnout, opustit.
   Společný aktivní úkol: sdílený postup, podmínky platí pro všechny členy (porušení kýmkoli
   = selhání), odměna každému. Zobrazení party v HUD a na mapě.
3. **„Mejdan na chatě“** jako skupinový úkol – odměna roste s počtem přítomných členů party.
4. Zvaž 1–2 nové **kooperativní úkoly** (např. „Odvoz z hospody“ – střízlivý řidič odveze
   opilého kamaráda domů; „Nákup na mejdan“ – rozdělený nákup). Navrhni, implementuj alespoň jeden.
5. **Textový chat** (Enter): všem / partě, historie, krátké mizení; filtr délky a spamu.
6. **Emoty** (kolečko nebo číselné klávesy – ověř kolize s ovládáním): mávnout, ukázat směr,
   přípitek. Přípitek dvou hráčů blízko sebe = společná interakce (malý bonus reputace/nálady).
7. Odpojení hráče: jeho úkol se pozastaví, v partě se úkol přenese na ostatní.

## Test (připrav skript / postup pro uživatele – viz pravidla testování)
Automatizovaný průchod „Autem z hospody“ a „Mejdan na chatě“ ve dvou hráčích včetně selhání
kvůli porušení podmínky druhým hráčem.

## Aktualizuj
`GAME_DESIGN.md` kap. 5.3 a 6.5 podle skutečného stavu.
