# M5.9 – Česká rocková rádia (Rock Radio, Radio Beat)

> Roadmapa „Život na vsi“ · **M5 Obec a volný čas** · krok 9/9 · **malý krok, lze kdykoli po M0**
> Předpoklady: žádné · Navazují: autorádio (volitelně)

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md` (kap. 3 – rádio: jen odkazy na veřejné streamy, žádná loga)
2. `docs/VIZE_A_ROADMAPA.md` – kap. 2.1 (rádia) a 4.5 „Rocková rádia (19)“
3. `data/radia.json` (5 stanic ČRo – formát `name`, `url`, `genre`, `noise`)
4. `scripts/radio.gd` (482 ř.) – načtení `radia.json`, přehrávání přes **ffmpeg** (grep `ffmpeg|stream|url`), chyby bez internetu
5. `README.md` → „Rádio doma“ a „Právní zásady obsahu“ (odstavec Rádio)

## 1. Proč
Uživatel chce reálná česká rocková rádia: **Rock Radio** a **Radio Beat** (případně **Rock Zone**). Radio Skyrock
se nepřidává (francouzské, rap). Smyšlené *Rádio Kovadlina* (metal) zůstává.

## 2. Co udělat
1. **Najdi veřejné adresy streamů** (smíš použít vyhledávání na webu – WebSearch/WebFetch – jen pro zjištění URL):
   oficiální přímé streamy (MP3 / AAC) z webů stanic nebo jejich přehrávačů. Upřednostni `https`, MP3 128 kb/s.
   Nepoužívej neoficiální agregátory, pokud oficiální stream existuje. U každé URL zapiš do `PROJECT_LOG.md`, odkud je.
   **Nespouštěj ffmpeg ani hru** – ověření přehrání udělá uživatel.
2. Přidej do `data/radia.json` (zachovej formát, `genre` česky, `noise` 0,6–0,8 – rock je hlučný → dřív rozzlobí sousedy):
   ```json
   {"name": "Rock Radio", "url": "<ověřená URL>", "genre": "rock", "noise": 0.75},
   {"name": "Radio Beat", "url": "<ověřená URL>", "genre": "klasický rock", "noise": 0.7}
   ```
   (+ „Rock Zone“, pokud najdeš stabilní oficiální stream.)
3. `radio.gd`: zkontroluj, že nový žánr / vyšší `noise` funguje (sousedé, policie v noci) a že neplatná URL nevyhodí chybu
   (jen hláška „Stanice nehraje“). Pokud hráč **nemá internet**, stanice se v nabídce ukážou s poznámkou „(internet)“ – ověř.
4. **Právní poznámka** v README (Právní zásady → Rádio): názvy stanic jsou ochranné známky provozovatelů; hra jen přehrává
   veřejný stream u hráče jako běžný přijímač, nic nenahrává ani nešíří, žádná loga; **před veřejným vydáním hry vyžádat
   souhlas stanic nebo seznam vyprázdnit** (stejně jako u ČRo).
5. Volitelně **autorádio**: v autě klávesa (volná – ověř registr kláves, např. **O**) přepíná stanice (stejný seznam,
   hlasitost se promítá do hluku – jízda obcí v noci s hlasitým rockem → sousedé / policie). Pokud se nevejde, otevřený bod.

## 3. Hotovo, když
- V rádiu doma jsou Rock Radio a Radio Beat (a případně Rock Zone) s ověřenými URL z oficiálních zdrojů; bez internetu nic nepadá;
  README má právní poznámku.

## 4. Návrh checklistu ručních testů
1. `./run.sh` → doma rádio (E) → v seznamu Rock Radio, Radio Beat.
2. Přepni na Rock Radio → hraje (potřebuje internet a ffmpeg).
3. Radio Beat → hraje.
4. Hlasitost 8 v noci → sousedé si stěžují dřív než u ČRo Vltava.
5. Odpoj internet → stanice „nehraje“, hra běží dál.
6. (Pokud hotovo) V autě O → autorádio.

## 5. Závěr
README, VIZE odškrtnout, roadmapa README, PROJECT_LOG (zdroje URL), deník AI, commit „M5.9 Rocková rádia: …“, checklist a čekat.
