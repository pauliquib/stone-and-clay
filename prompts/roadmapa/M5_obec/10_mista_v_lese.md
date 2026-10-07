# M5.10 – Místa v lese: studánka, skautský tábor, MTB bikepark

> Roadmapa „Život na vsi“ · **M5 Obec a volný čas** · krok 10/12 (doplněk od uživatele, 6. 10. 2026)
> Předpoklady: M0.3 (dovednosti), M2.2 (oheň – táborák), M1.6 (vozidla – kolo `bike_model.gd`), M5.5 (kalendář akcí –
> tábor jako událost; bez M5.5 jen pevné termíny) · Navazují: M7.3 (vedlejší úkoly – ztracený skaut, závod), V2
> **Tři malé celky – každý jde dokončit samostatně;** při nedostatku kontextu udělej 1 a 2 a bikepark nech na další session.

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md` (kap. 3 – smyšlené názvy spolků, žádné reálné logo skautské organizace)
2. `scripts/fauna/fauna.gd` – `forest_at`, `random_point(..., "forest")`, `trees_near`; `scripts/water.gd` – `info_at`,
   `nearest_stream`
3. `scripts/road_graph.gd` – druhy cest (`data/map.json`: `track` 594, `path` 149, `footway` 146, `cycleway` 2)
4. `scripts/bike_model.gd` + `scripts/car_model.gd` (`MODELS["…kolo…"]`, `kind: "bike"`, `skupina_rp: ""`), `scripts/car.gd` –
   jízda na kole (grep `bike`)
5. `scripts/fire_manager.gd` (ohniště, `opekat`), `scripts/priroda/village_events.gd` (`EVENTS`, `register` z M5.5)
6. `scripts/skills.gd` – `SKILLS` (cyklistika tam není), `scripts/mesh_kit.gd` (modely), `scripts/prop.gd` / `prop_models.gd`
7. `scripts/body_state.gd` – pití / žízeň (grep `drink`), `scripts/garden.gd` – konev a plnění vodou (`naplnit`)

## 1. Proč
Les je dnes hlavně dřevo, zvěř a houby. Uživatel chce místa, kam se chodí: **studánku**, **skautský tábor** a **bikepark
pro horská kola**. Dávají smysl procházkám, kolu a letním událostem.

## 2. Co udělat
### 2.1 Studánka
- Poloha: OSM data hry pramen (`natural=spring`) **nemají** (ověř grepem `spring` v `data/*.json`). Vyber místo
  deterministicky: les (`forest_at > 0.6`) u svahu poblíž potoka (`Water.nearest_stream` do ~80 m) a lesní cesty
  (`track` / `path` do ~40 m), ne v obci. Souřadnice zapiš do logu – uživatel může místo upravit konstantou.
- Model (MeshKit): kamenná / dřevěná stříška, žlábek, malá nádržka, cedulka s vymyšleným jménem („Studánka U Jelena“),
  hrnek na řetízku. Zvuk tekoucí vody (procedurální, `sfx.gd` / `nature_sfx.gd`).
- E = napít se (žízeň / výdrž – `BodyState`, pokud žízeň neexistuje, jen malé osvěžení výdrže), naplnit konev / láhev
  (napoj na `naplnit` z M2.4 – voda ze studánky je legální i za sucha z M4.4). V zimě zamrzlá (podle `Weather.temp`).
- Drobnost: úklid listí ze studánky (dobrý skutek – karma +0,5 1× za týden, M4.5 `EVENT_EFFECTS`).

### 2.2 Skautský tábor (léto)
- Louka / mýtina v lese nebo na jeho okraji (`Fauna.random_point` + volná plocha bez stromů, rovný terén), ne v obci.
- **Stálé:** tábořiště se stožárem, ohništěm (FireManager ohniště), lavicemi z kulatiny a cedulí smyšleného oddílu
  („oddíl Lesní Sovy“ – žádné reálné skautské symboly ani logo).
- **Událost** (kalendář M5.5 – `VillageEvents.register("tabor", …)`, 2 týdny v červenci): podsadové stany (MeshKit),
  6–10 NPC dětí a 2 vedoucí (`Humanoid`, smyšlená jména, nepojmenovávat po reálných lidech), denní program (nástup,
  hry na louce – pobíhání, večer táborák se zpěvem – generovaná hudba `RadioMusic`), noční klid od 22 h.
- Hráč: rozhovor s vedoucím (T), malé prosby (dovézt dřevo, opravit stožár, najít zatoulaného táborníka – vzor `Favors`
  z M4.5, pokud je; jinak jednoduchý úkol v `quests.gd`), karma / respekt komunity. Hluk u tábora v noci (motorka, rádio) →
  stížnost (model hluku z M4.4).
- Výkon: NPC tábora jen když je hráč do ~300 m; jinak jen data.

### 2.3 MTB bikepark
- **Horské kolo:** nový model v `CarModel.MODELS` (`kind: "bike"`, smyšlený název „Bobr MTB“), prodej v Bazárku / eŠuplíku
  (M3.4) nebo ve Stavebninách (M5.1). Odpružení / větší grip v terénu (`Weather.surface_grip` „teren“ – kolo do terénu
  lepší než silniční „Favorín“), ladění v tabulce modelu.
- **Trasa:** ve svahu v lese (vyber místo s převýšením 30–80 m podél `track` / `path`), vytýčená páskou / kolíky, start a cíl
  s cedulí („Bikepark Hřebínek“ – smyšlené). Překážky jako **statické rekvizity na terénu** (výšková mřížka se nemění):
  skokánky (dřevěné rampy – vzor U-rampa M5.8 / skate), klopené zatáčky z kulatiny, lávky; kolize vrstva 1.
- **Minihra:** časovka start → cíl (kontrolní body jako u úkolů s trasou), nejlepší čas v deníku, pád při skoku s velkou
  rychlostí / náklonem (zranění malé – `BodyState.hurt`), denní žebříček NPC časů (vymyšlené přezdívky).
- Nová dovednost **`cyklistika`** v `Skills.SKILLS` (XP za jízdu po trati a skoky; vyšší úroveň = stabilnější dopad);
  ověř, že přidání dovednosti nerozbije uložené `skills` (výchozí 0 XP).
- Zákon / slušnost: jízda na kole mimo cesty v lese je zjednodušeně tolerovaná, ale ničení mladých stromků (M2.5) → přestupek
  `poskozeni_cizi_veci` (svědek – M4.4).

## 3. Minimum
Studánka (model, napít se, naplnit konev) a skautský tábor (stálé tábořiště + letní událost s NPC a táborákem).
Bikepark do otevřených bodů s vybraným místem.

## 4. Hotovo, když
- Studánka je v lese u potoka, dá se z ní pít a nabrat vodu; v zimě zamrzne.
- V červenci stojí skautský tábor s programem a táborákem; hráč může pomoct.
- Horské kolo jde koupit a v bikeparku se jezdí časovka se skoky a dovedností cyklistika.

## 5. Návrh checklistu ručních testů
1. F2 → Teleport (nová položka „Studánka“) → studánka, zvuk vody; E → napít, naplnit konev.
2. F2 → Datum leden → studánka zamrzlá.
3. F2 → Datum 15. 7. → tábor: stany, děti, vedoucí; večer táborák se zpěvem; T s vedoucím → prosba.
4. Noc u tábora s motorkou / rádiem → stížnost.
5. Bazárek / obchod → horské kolo; jízda lesem drží lépe než „Favorín“.
6. Bikepark: start → cíl, čas v deníku; skok → XP cyklistika; prudký dopad → pád.
7. F5/F9 → nejlepší čas, kolo a stav tábora zůstanou.

## 6. Závěr
README (Systémy → Les: studánka, tábor, bikepark; F2 teleport), VIZE odškrtnout, roadmapa README, PROJECT_LOG,
commit „M5.10 Místa v lese: …“, checklist a čekat.
