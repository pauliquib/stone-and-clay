# M5.11 – Doprava 2: řidiči v autech, nástup a výstup obyvatel

> Roadmapa „Život na vsi“ · **M5 Obec a volný čas** · krok 11/12 (doplněk od uživatele, 6. 10. 2026)
> Předpoklady: vlna 0 F2 (opravy AI řízení – `Car.reroute`, `_ai_carrot`, `Traffic._replan`), M1.6 (vozidla),
> M4.5 (prosba „Odvezeš mě?“ – tady se dodělá naplno) · Navazují: M5.5 (lidé jezdí na akce), M4.3 (odvoz k soudu), V2
> Proč zvlášť od M5.12 (osvětlení): jiné soubory (`car.gd`, `traffic.gd`, `villager.gd`, `humanoid.gd` vs. svět a obloha),
> obě části se vejdou do jednoho okna jen samostatně a jdou dělat souběžně.

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md` (kap. 5.5 – výkon: nic těžkého pro vzdálené objekty)
2. Poslední záznamy vlny 0 (F2 Doprava) v `PROJECT_LOG.md` – co se změnilo v AI řízení a otevřené body
3. `scripts/traffic.gd` (412 ř.) – `N_AI` 5, `N_PARKED` 14, `make_car`, `place_car`, `car_of`, `_respawn`, `_replan`, bublina u hráče
4. `scripts/car.gd` (1741 ř. – **nečti celý**): `seat_pos`, `driver_id`, `set_player_driver` / `clear_driver` (~ř. 625–660),
   `set_ai_route` (~668), `driver_door_world` (~798), `kinematic_step` (grep)
5. `scripts/player.gd` – `enter_car` (~ř. 624: `visual.position = c.seat_pos`, póza `ride`), `scripts/humanoid.gd` – `pose`,
   `ride` (~ř. 75–80, 698)
6. `scripts/flight/trike.gd` – **vzor spolujezdce**: vesničan se schová, v sedadle sedí jeho viditelná kopie (`_pax_vis`, ~ř. 148–170)
7. `scripts/villager.gd` – `BT_VILLAGERS` 5, `_home_pos`, pohyb po pěší síti (`WALK_KINDS`), `scripts/npc.gd`
8. `scripts/favors.gd` (M4.5) – prosba „Odvezeš mě?“ (háček pro tenhle krok)

## 1. Proč
AI auta dnes jezdí **bez řidiče** (prázdná kabina) a vesničané auta nepoužívají. Uživatel chce řidiče v autech a obyvatele,
kteří nastupují a vystupují – obec pak působí živě a hráč může svézt souseda.

## 2. Co udělat
### 2.1 Řidiči v AI autech
- Každé AI auto (`Traffic`, `N_AI`) a policejní auto dostane **viditelnou postavu řidiče**: lehký `Humanoid` (stejná
  stavebnice jako vesničané, náhodný vzhled ze seedu auta) v póze `ride`, pozice `car.seat_pos` (strana řidiče),
  ruce na volantu (cíle `ride` jako u hráče). Bez fyziky, bez AI – jen vizuál, rodič = karoserie.
- Výkon: postavu zobrazit jen do ~120 m (`visibility_range_end`), animace jen do ~40 m; auta mimo bublinu
  (`kinematic_step`) řidiče nepotřebují. Zaparkovaná auta (`N_PARKED`) jsou prázdná.
- Policejní auto: řidič v uniformě (barvy jako policista z `police.gd`), při zastavení vystoupí ten samý (dnes se policista
  objeví vedle auta – sjednoť, aby kabina pak byla prázdná).

### 2.2 Obyvatelé nastupují a vystupují
- **Zaparkovaná auta u domů vesničanů:** některá auta z `N_PARKED` patří konkrétnímu vesničanovi (vazba přes
  `Estate.pick_customer_house` / dům vesničana). Když vesničan „odjíždí“ (rutina – práce mimo obec, nákup ve městě, akce
  M5.5), dojde k autu, animace otevření dveří a nástupu (posadit se – póza `sit` → `ride`), auto se rozjede jako AI (trasa
  na okraj obce / k cíli), vesničan se skryje do kabiny jako řidič (2.1). Návrat: auto přijede, zaparkuje, řidič vystoupí
  (`driver_door_world`) a jde domů.
- Kdo jezdí: jen vesničané, kteří mají auto (tabulka / seed), pár jízd denně; BT vesničané (5) přes novou akci v BT
  (`ai/` – vzor existujících akcí; generátor `tools/gen_villager_bt.gd`), ostatní přes jednoduchý plán v `villager.gd`.
  Nezvyšuj `BT_VILLAGERS` (výkon – audit A4-04).
- Bezpečnost: AI auto s vesničanem respektuje vše z vlny 0 F2 (překážky, přeplánování); zaseknuté auto se vrátí na místo
  (teleport mimo dohled hráče) a vesničan se objeví u domu.

### 2.3 Spolujezdec v autě hráče („Odvezeš mě?“ – M4.5)
- Auto dostane `pax_pos` (místo spolujezdce – v `CarModel.MODELS` dopočti z `seat` zrcadlením X) a funkce
  `board_passenger(villager)` / `unboard_passenger()` po vzoru `Trike._pax_vis` (vesničan se schová, v sedadle viditelná
  kopie). Nastoupí, když hráč zastaví u něj a zmáčkne E („Svezu vás“), vystoupí v cíli prosby nebo na E.
- Prosba M4.5 „Odvezeš mě k lékaři / do hospody?“ přepni z fade-zjednodušení na skutečné svezení; řízení pod vlivem /
  nehoda se spolujezdcem → přátelství dolů, pověst (M4.4 `srazeni_chodce` / `nehoda_skoda`).
- Ukládání: vesničan ve voze se při uložení vrátí domů (neukládat rozjeté jízdy NPC).

### 2.4 Volitelně – autobus (jen když zbude kontext)
Linka 2–4× denně přes obec, zastávka (pokud ji zavedl M4.3, použij ji), vesničané nastupují / vystupují, hráč se může
svézt k okraji mapy (odvoz „do města“ = blackout + posun času – vzor soudu M4.3). Jinak otevřený bod.

## 3. Minimum
Řidiči v AI a policejních autech (vizuál, LOD), nástup / výstup aspoň u 3 vesničanů s vlastním autem, spolujezdec v autě
hráče pro prosbu M4.5.

## 4. Hotovo, když
- Žádné jedoucí AI auto nemá prázdnou kabinu; vesničané chodí k autům, odjíždějí a vrací se; soused se dá svézt; FPS
  v obci se citelně nezhorší.

## 5. Návrh checklistu ručních testů
1. Stůj u silnice v obci → projíždějící auta mají řidiče; policejní auto taky.
2. Policejní kontrola → policista vystoupí z kabiny, kabina pak prázdná.
3. Ráno u domu vesničana s autem → dojde k autu, nastoupí, odjede; odpoledne se vrátí a vystoupí.
4. Prosba „Odvezeš mě?“ (M4.5) → zastav u něj, E → sedí vedle tebe → doveď do cíle → vystoupí, odměna.
5. Nehoda se spolujezdcem → přátelství dolů.
6. F2 → Výkon / FPS v obci se 5 AI auty srovnatelné s dřívějškem.
7. F5/F9 během jízdy vesničana → po načtení je vesničan doma, nic nepadá.

## 6. Závěr
README (Systémy → Doprava), VIZE odškrtnout, roadmapa README, PROJECT_LOG, commit „M5.11 Doprava 2 – řidiči a spolujezdci: …“,
checklist a čekat.
