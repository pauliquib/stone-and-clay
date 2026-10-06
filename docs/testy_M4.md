# Testy M4 – ruční checklisty

## M4.5 – Dobré skutky a přátelství (prosby vesničanů, dárek, oblíbené)

Spouští jen uživatel. Stav: staticky ověřeno (kontrola překladu), ruční test čeká.

1. Jdi k vesničanům v obci (blízko postavy, do ~3 m) a stiskni **E** – nabídka ukáže přátelství a případnou prosbu.
2. Najdi vesničana s prosbou („★ Přijmout“), přijmi ji. Ostatní prosby téhož dne by měly být u jiných lidí.
3. Prosba „zahrada“: sklidit na zahradě 2× (zmínka v deníku / hlášce „Prosba splněna“). Prosba „sníh“: dobrovolný úklid sněhu (`snow_volunteer`).
4. Prosba „nákup“: měj v inventáři jídlo (např. rohlík), E u vesničana → „Dát: …“ → hláška „Prosba splněna“, přátelství a pověst nahoru.
5. Nesplň přijatou prosbu a přejdi do dalšího herního dne → hláška „Zklamals mě“, přátelství klesne o 10.
6. E u vesničana → „Dát: …“ s oblíbeným předmětem (povolání / koníček s pivem, vínem, zahrádkou…) → výrazně větší přátelství než u jiného předmětu.
7. Přátelství ≥ 40 se v nabídce ukáže jako „Výhody: pomůže s nošením…“, ≥ 60 navíc „nenahlásí drobný přestupek…“ (zatím jen text, efekt čeká na M4.4).
8. Starý save (bez klíče `favors`) se musí načíst bez chyby; prosby mají být prázdné.
9. F5 → F9 (uložit / načíst) uprostřed dne: nabídky a stav přijatých proseb zůstanou.
10. Deník J / F1 – zkontroluj, že se nic nerozbilo (E u vesničanů stále otevírá rozhovor přes „Promluvit“).
