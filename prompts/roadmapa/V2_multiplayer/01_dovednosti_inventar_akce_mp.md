# V2.01 – Dovednosti, inventář, nástroje, akce a náklad přes síť

> Verze 2 · **Multiplayer** · krok 1
> Předpoklady: `prompts/03–07` (síťový základ, lobby, auta, NPC, předměty a ekonomika) · Navazují: V2.02–V2.05

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md`, `V2_multiplayer/README.md`, `GAME_DESIGN.md` kap. 6
2. Síťová vrstva z úkolů 03–07 (grep `class_name Net|rpc|MultiplayerSynchronizer` – najdi hlavní soubor sítě a jak se dělá request → server → notify)
3. `scripts/skills.gd`, `scripts/items_db.gd`, `scripts/player.gd` (`inventory`, `equipped`, `durability`, `load_kind`),
   `scripts/actions.gd` (+ `ActionRunner`), `scripts/cargo.gd` (vozík, kufr)
4. Seznam rizik z V2.00 v `PROJECT_LOG.md`

## 1. Cíl
Základy RuneScape mechanik fungují pro více hráčů: server je autorita nad XP, inventářem, opotřebením a výsledkem
akcí; ostatní hráči vidí, co kdo drží a dělá.

## 2. Co udělat
1. **Dovednosti:** `Skills` per hráč na serveru; `skill_xp` a level-up → RPC vlastníkovi; ostatním jen level-up efekt
   (bublina / zvuk u hráče).
2. **Inventář a nástroje:** `equipped` se replikuje všem (model v ruce), změna = request → server ověří vlastnictví.
   Opotřebení na serveru. Předání věci jinému hráči (už z `07` – rozšířit na nástroje, zbraně, doklady **ne** – doklady jsou osobní).
3. **Kontextové akce:** klient pošle `request_action(action_id, target_ref)`; server ověří (vzdálenost ≤ 3 m, nástroj, úroveň,
   výdrž z `BodyState` serveru, cíl existuje a není obsazený jiným hráčem), spustí časovač, rozešle „hráč X dělá akci Y“ (animace
   u všech), na konci výsledek. Přerušení pohybem hlásí klient, server kontroluje posun > 0,5 m.
4. **Cíle akcí** (`register_target`) jsou serverové; klient dostává jen ty v oblasti zájmu.
5. **Náklad:** nesení (rameno) – stav hráče replikovaný (vizuál nákladu), položení / zvednutí = request.
   **Ruční vozík:** autorita u hráče, který ho táhne (jako řidič auta), jinak server (klid). Náklad na vozíku a plachta replikované.
   **Kufr / nosič** – obsah na serveru, vizuál nosiče všem.
6. **Nesení ve dvou** (M2.10) – připrav: druhý hráč jako partner místo NPC (request „pomoz nést“ → potvrzení druhého hráče) –
   plná verze ve V2.04.

## 3. Hotovo, když
- Dva hráči: každý má vlastní XP a inventář; vidí nástroj v ruce druhého a jeho akce; nemůžou současně zpracovat stejný cíl;
  vozík a náklad jsou synchronní.

## 4. Návrh checklistu (2 klienti na jednom PC – postup z úkolu 03)
1. Host + klient; oba vezmou různé nástroje (Q) → vidí je u sebe navzájem.
2. Oba natrhají trávu → XP jen tomu, kdo akci dělal.
3. Oba míří na stejný cíl → jen jeden začne, druhý hláška „Tohle už dělá …“.
4. Hráč A táhne vozík se špalky, B jde vedle → plynulý pohyb u B.
5. A předá B sekeru → B ji má, opotřebení zachované.
6. Odpojení B uprostřed akce → akce se zruší, nic se neduplikuje.

## 5. Závěr
README / GDD (MP), PROJECT_LOG, deník AI, commit „V2.01 Dovednosti, inventář a akce v MP: …“, checklist a čekat.
