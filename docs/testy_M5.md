# Checklisty ručních testů – M5 Obec a volný čas

## M5.9 – Rocková rádia (částečně)

Cheat: F2 → Hráč / Teleport. Ověř jen to, co je v kroku hotové.

1. Doma: zapni rádio (E) → v seznamu jsou ČRo stanice z `data/radia.json` beze změny (nové rockové stanice zatím nejsou).
2. Přepni na ČRo Radiožurnál → hraje (potřebuje internet a ffmpeg).
3. Odpoj internet → přepni stanici → hláška „Stanice nehraje“ (nebo po ~12 s ukončení), hra běží dál bez pádu.
4. Bez ffmpeg (pokud jde otestovat) → hláška „Internetové rádio potřebuje program ffmpeg“.
5. Hlasitost 8 v noci u stanice s vyšším `noise` → sousedé reagují (zvýšený hluk).
6. README → Právní zásady → Rádio: poznámka k nepřidaným stanicím je srozumitelná.

## M5.9 – Autorádio a vnitřní světlo v autě (body 5–6)

Cheat: F2 → Teleport (k autu) / Datum (noc, např. 23:00) / Hráč. Auto s kabinou (osobní auto, ne kolo / motorka / traktor).

1. Nasedni do auta (F) → za volantem zmáčkni **1** → hraje první předvolba (Rádio Kovadlina); hlášení s názvem stanice.
2. Předvolba **2** (Rádio Pohoda) → hraje klidná hudba; **0** → rádio vypnuto (hláška „vypnuto“).
3. Za volantem **Shift + kolečko** nahoru/dolů → hlasitost se mění (hláška „hlasitost x/10“); bez Shift kolečko kamera nepřibližuje.
4. Mimo auto (za hry) klávesy 1–5 pořád přepínají rychlé sloty opasku, 0 nic nedělá.
5. Hlasitě (hlasitost 10, Rádio Kovadlina) v noci jezdi obcí → sousedé si stěžují dřív než u tiché hudby.
6. Nastup v noci (Datum 23:00) → v kabině se rozsvítí teplé světlo; po ~10 s stojícího auta zhasne.
7. Stiskni **F4** → světlo svítí i po 10 s; F4 znovu → zhasne. Při rozjezdu se světlo vypne.
8. Ve dne (Datum 12:00) při nástupu světlo nesvítí; F4 ho přesto zapne ručně.
9. Ulož hru (F5), zapni rádio v autě na stanici, načti (F9) → rádio ve stejné stanici a hlasitosti.
