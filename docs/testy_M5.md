# Checklisty ručních testů – M5 Obec a volný čas

## M5.9 – Rocková rádia (částečně)

Cheat: F2 → Hráč / Teleport. Ověř jen to, co je v kroku hotové.

1. Doma: zapni rádio (E) → v seznamu jsou ČRo stanice z `data/radia.json` beze změny (nové rockové stanice zatím nejsou).
2. Přepni na ČRo Radiožurnál → hraje (potřebuje internet a ffmpeg).
3. Odpoj internet → přepni stanici → hláška „Stanice nehraje“ (nebo po ~12 s ukončení), hra běží dál bez pádu.
4. Bez ffmpeg (pokud jde otestovat) → hláška „Internetové rádio potřebuje program ffmpeg“.
5. Hlasitost 8 v noci u stanice s vyšším `noise` → sousedé reagují (zvýšený hluk).
6. README → Právní zásady → Rádio: poznámka k nepřidaným stanicím je srozumitelná.
