# 00 – Společný kontext pro všechny prompty roadmapy „Život na vsi“

> Tento soubor čte **každý** prompt ze složky `prompts/roadmapa/` jako první.
> Obsahuje pravidla práce, mapu kódu a konvence, aby agent v novém kontextovém okně nemusel
> procházet celý projekt. Když se tu něco ukáže jako zastaralé, oprav to (je to živý dokument).

---

## 1. O projektu v kostce

- **Hra:** *Stone & Clay* – open-world simulátor života na české vesnici, Godot **4.3**, GDScript,
  Forward+.
- **Svět:** celý katastr obce (~5,2 × 4,6 km) bez načítacích obrazovek. Terén DMR 5G (ČÚZK), budovy,
  silnice a vodní toky z OSM, ~21 800 stromů. Souřadnice: **metry**, Y nahoru, počátek u domu hráče;
  `data/map.json` (meta, `x0`, `z0`), místa v `data/pois.json` (dveře `door_x/z`, parkování `park_x/z`).
- **Cíl nové etapy:** viz `docs/VIZE_A_ROADMAPA.md` – dovednosti ve stylu RuneScape
  (činnosti ve světě: dřevo, oheň, rybaření, lov, zahrada, chov…), práce, zákony ČR, pověst / respekt /
  karma, obecní život, létání. **Singleplayer.** Multiplayer až ve verzi 2 (složka `V2_multiplayer/`).
- **Už hotové:** vše z `README.md` → „Systémy“ + série `prompts/priroda/01–04` (zvěř, ptáci, hmyz, kůň,
  počasí, roční období, pole z OSM, svátky, myslivec a krmelec, stopy ve sněhu, stáj koně).
  Série `priroda/05` a staré `prompts/03–10` (síť) patří do verze 2.

## 2. Pravidla práce (povinná)

1. **Jazyk:** česky – komentáře, texty UI, log, dokumentace. Drž styl okolního kódu (tabulátory,
   `##` doc-komentáře nad třídou a funkcemi, typované proměnné, konstanty VELKÝM písmem nahoře).
2. **Laditelné hodnoty** patří do tabulek / konstant nahoře v souboru (vzor: `AnimalSpecs`,
   `Weather.TYPES`, `Place.OFFERS`, `Consumables.ITEMS`). Katalogy obsahu = data, ne větvení v kódu.
3. **Testování dělá výhradně uživatel.** Hru, testy ani simulace (`godot …`, `run.sh`, `--questtest`,
   `--shot`, `--faunatest`, headless běhy, `--import`) **nikdy nespouštěj**, pokud tě k tomu uživatel
   výslovně nepověří. Ověřuj čtením kódu. Testovací parametry, které úkol chce, napiš, ale nespouštěj.
   **Jediná povolená výjimka (od 6. 10. 2026): kontrola překladu** – viz kap. 6 (`--import` + `--check-only`).
4. **Na konci úkolu** (v tomto pořadí):
   1. statická kontrola (viz kap. 6),
   2. aktualizuj `README.md` (Systémy / Ovládání / Ladicí parametry) a jiné dotčené návody,
   3. odškrtni krok v `docs/VIZE_A_ROADMAPA.md` (`[ ]` → `[x]`) a v `prompts/roadmapa/README.md`,
   4. záznam do `PROJECT_LOG.md` (v kořeni repozitáře, formát kap. 7),
   5. (deník efektivity AI se nevede – `CLAUDE.md` v repozitáři není; krok vynech),
   6. commit (jen tvoje změny – viz bod 8),
   7. vypiš uživateli **checklist ručních testů (max. 10 bodů)**: co spustit, kam ve hře jít
      (F2 → Teleport / Datum / Počasí / Hráč), co udělat, co má být vidět. Pak **skonči a čekej**.
5. Když uživatel pošle výsledky testů, oprav nahlášené chyby, doplň log a commitni.
6. **Singleplayer nesmí přestat fungovat.** Staré uložené pozice se musí dát načíst (kap. 5.6).
7. **Rozsah:** drž se kroku. Co nestihneš nebo nepatří do kroku, zapiš do „Otevřené body“ v logu.
   Když je úkol na jedno okno příliš velký, dokonči část „Minimum“ z promptu a zbytek nech v logu.
8. **Commity:** v repozitáři může pracovat i jiná session. Commituj jen své soubory; u sdílených souborů
   jen své hunky (`git add -p` neumíš → `git diff soubor > /tmp/p.patch`, uprav patch, `git apply --cached`).
   Zprávu commitu piš česky ve stylu historie („M0.2 Jednotný katalog předmětů: …“).
9. **Kontext šetři:** velké soubory (`world.gd` ~3750 ř., `hud.gd` ~2150, `jobs.gd` ~1740, `car.gd` ~1600, `player.gd` ~1230)
   nečti celé – najdi místo přes `grep -n` a čti výřez (`Read` s `offset/limit`).

## 3. Právní zásady obsahu (platí pro všechno nové)

Podrobně `PRAVNI_DOPORUCENI.md` a README → „Právní zásady obsahu“.
- Domov hráče (od M1.7) = nemovitost z `Estate` (`World.estate`: `home_of(pid)`, `home_label(pid)` → „byt 5 v č. p. 48“),
  místo „domov“ (`World.places["domov"]`) se k ní přesouvá (`World.apply_home`). Čísla popisná jsou **smyšlená** (seed,
  číslování od návsi) – nikdy z RÚIAN / ČÚZK. Původní dům z podkladů (`meta.domov_hrace`, dřív pevné „č. 221“) je usedlost
  (`Estate.lot_id`, `World.lot_door()`) se zahradou, výběhem a hospodářstvím. Skutečné číslo se ve hře nesmí zobrazit;
  v textech nepiš pevné číslo, dosazuj `World.home_label(id)` / `{home}` v rozhovoru.
- Žádná reálná jména, SPZ (generují se s písmenem Q), loga, ochranné známky, obecní znak ani prapor.
  Podniky, spolky, kapely, auta: **smyšlené / parodické názvy**. Sousední obce se v herních textech nejmenují.
- Interiéry jsou vymyšlené; okna nesmí dávat průhled do reálných soukromých prostor.
- **Assety z internetu:** jen CC0 / public domain, nebo CC BY (s uvedením autora). Zakázáno: CC BY-NC,
  CC BY-ND, „personal use“, bez licence, ripy z her, Google/Bing 3D. Každý asset zapsat do
  `assets/LICENSES.md` (zavádí krok M0.1). Modely skutečných aut **odbrandovat**.
  Agent nestahuje nic z internetu, pokud to prompt výslovně nechce – jinak připraví místo
  a návod, asset dodá uživatel.
- **Zákony ČR** jsou zjednodušené; u každého čísla (pokuta, body, lhůta) v datech uveď zákon a §
  a poznámku „ověřit aktuální znění“. Do nápovědy patří doložka „zjednodušená herní simulace“.

## 4. Mapa kódu (`scripts/`)

| Soubor / třída | Co dělá | Důležité API |
|---|---|---|
| `main.gd` | start: vytvoří `World` + `LocalClient`, ladicí parametry | `--load=slot`, `--date=`, `--weather=` |
| `world.gd` `World` | simulace (v MP server): terén, čas, hráči, místa, NPC, doprava, policie, předměty, pravidla | `players[id]`, `quests[id]`, `reputations[id]`, `places[key]`, `npcs`, `clock`, `weather`, `fauna`, `water`, `fields`, `village_events`; `notify(id, metoda_hud, [args])`, `play_sfx(id, …)`, signál `sound(pos, name, pitch, vol, max_dist)`, `emit_game_event(id, kind, data)`, `player_action(id, action)`, `interactables(id)`, `find_interact(id)`, `buy(id, item, cena, mode, place)`, `price_for`, `skip_time`, `teleport_player`, `spawn_vehicle`, `cheat` |
| `local_client.gd` `LocalClient` | vstup → `InputState`, klávesy → akce `World`, HUD, kamera, zvuky, nabídky míst | `_unhandled_input`, `_interact()`, `open_place_menu(key)`, `on_game_event(kind, data)`, `save_game/load_game` |
| `input_state.gd` `InputState` | vstup jednoho hráče (pohyb, pohled, skok…) | čte `Player`, `Car`, `Horse` |
| `player.gd` `Player` | CharacterBody3D hráče: pohyb, výdrž, inventář, akce, auto/kůň | `inventory` (id→počet), `money`, `add_item/remove_item/item_count/use_item`, `body: BodyState`, `car`, `horse`, `busy`, `controls_locked`, `license_suspended_until`, `wanted_until`, `wade`, `scope_on`, `say()`, signál `game_event` |
| `body_state.gd` `BodyState` | fyziologie: alkohol, jídlo, nikotin, zdraví, `wetness`, `cold` | `drink`, `eat`, `hurt`, `heal_full`, `skip_hours`, `stamina_max`, `speed_mult` |
| `consumables.gd` `Consumables` | katalog jídla, pití, cigaret, vybavení (`ITEMS`) | typy `drink/food/smoke/gear` |
| `item.gd` `Item` | sběratelské předměty ve světě (hřib, jablko, šípek, dukát, zlatý žalud) | `INFO`, `setup`, `set_active` |
| `hud.gd` `Hud` | UI: zprávy, nabídky, inventář (Tab), deník (J), mapa (M), pověst | `show_message(t, dur)`, `popup(t, dur)`, `police_banner`, `open_menu(title, text, options)`, `close_menu`, `toggle_inventory`, `_journal_bbcode()`, `DISCLAIMER`, `CREDITS` |
| `game_menu.gd` `GameMenu` | F2: datum, čas, počasí, vozidla, teleport, hráč, uložení | `open_main`, `open_teleport`, `open_player` |
| `place.gd` `Place` | místa (hospoda, Potraviny, pálenice, sklep, úřad, chata, domov): nabídky, otevírací doby, obsluha | `OFFERS`, `HOURS`, `WEEK_HOURS`, `KEEPERS`, `is_open(h)` |
| `quests.gd` `Quests` | úkoly jednoho hráče, podmínky, události | `on_event(kind, data)`, `accept`, `available_at(place)` |
| `reputation.gd` `Reputation` | pověst −100…100, přestupky, stupně | `change(delta, text, offense)`, `on_event`, `to_dict/from_dict`, `price_mult`, `police_extra` |
| `persona.gd`, `characters.gd` | smyšlené postavy (28 vesničanů), povaha, nálada, známost | `Persona.make({...})` |
| `dialog.gd` | rozhovor volným textem (T), klíčová slova, témata | `WORDS`, `TOPICS` |
| `villager.gd`, `npc.gd`, `dog.gd` | vesničané, obsluha, psi | reagují na `World.nearest_player` |
| `humanoid.gd` `Humanoid` | procedurální postava (hráč i NPC), oblečení, animace, IK | `hold(node)` (předmět do pravé ruky), `start_action(a)`, `stop_action()`, `_leg_ik`, `_arm_ik` |
| `mesh_kit.gd` `MeshKit` | stavebnice procedurálních modelů (box, cylinder, lathe, loft → jeden ArrayMesh) | `box`, `cylinder`, `sphere`, `capsule`, `lathe`, `loft`, `commit(mat)` |
| `prop_models.gd`, `prop.gd` | modely drobností; fyzikální rekvizity (popelnice, lavička, míč, bedny) | `Prop.damaged` |
| `car.gd` `Car`, `car_model.gd`, `bike_model.gd` | auta, kolo, motorka (VehicleBody3D), procedurální karoserie, `.glb` modely | `CarModel.MODELS`, `two_wheeler`, `set_player_driver`, `repair`, návod `VLASTNI_VOZIDLA.md` |
| `traffic.gd`, `road_graph.gd`, `police.gd` | AI doprava, graf silnic z OSM, policie (hlídka, kontroly, dechovka) | `Traffic.plate()`, `police.license_ok(p)` |
| `terrain.gd` `Terrain` + `shaders/terrain.gdshader` | výšková mřížka 2 m, LOD dlaždice, ortofoto, pole | `height_at(x, z)`, `contains`, `set_landuse`, `set_field_lut` |
| `surroundings.gd` `Surroundings` + `shaders/surroundings.gdshader` (M6.2) | hrubá krajina za katastrem (data od `tools/surroundings.py`), fallback bez dat | `setup(terrain)`, `height_at(x, z)`; `World.flight_bounds(pos)` → `{ok, warn, push, out, agl}`, konstanty `World.FLY_*` |
| `map_loader.gd` `MapLoader` | budovy, střechy, cesty (chunky), stromy (MultiMesh s LOD) | `load_chunks`, `build_trees(parent, skip, terrain)` |
| `water.gd` `Water` | potoky, rybníky, zamrzání, brodění | `info_at(x, z)`, `nearest_stream` |
| `clock.gd` `Clock` | čas (1 h = 2 min), kalendář, slunce, svátky | `hour()`, `day()`, `jd()`, `month()`, `weekday()`, `season()`, `holiday()`, `is_night()` |
| `priroda/weather.gd` `Weather` | počasí | `temp`, `rain`, `wind`, `wind_vector()`, `snow_cover`, `wetness`, `fog`, `is_raining()`, `forecast()`, `surface_grip(surf)` |
| `priroda/fields.gd` `Fields`, `season_fx.gd`, `tree_decor.gd` | pole z `data/landuse.bin`, plodiny podle kalendáře, ovoce | `Fields.CROPS` |
| `priroda/village_events.gd` `VillageEvents` | svátky a události (Vánoce, masopust, čarodějnice, hody, Silvestr) | `EVENTS`, `is_active(id)`, `event_hours` |
| `fauna/*` | zvěř (`animal.gd`, `animal_specs.gd`, `herd.gd`), ptáci, hmyz, kůň (`horse.gd`), `fauna.gd` (mapa stanovišť) | `Fauna.forest_at`, `random_point`, `trees_near`; návod `ZVIRATA.md` |
| `radio.gd`, `radio_music.gd` | rádio doma, stanice z `data/radia.json` | |
| `sleep_spot.gd`, `save_game.gd` | noclehy; ukládání `user://saves/*.json` | `SaveGame.VERSION`, `save()`, `load()` |
| `estate.gd` `Estate` (M1.7) | registr nemovitostí: smyšlená čísla popisná, cedulky, domov = vlastnictví / nájem bytu, nájem | `World.estate`, `home_of(pid)`, `home_label(pid)`, `owns_house(pid)`, `is_flat(pid)`, `lot_door()`, `set_home()`, `World.apply_home(pid)`, `rent_debt(pid)`, `pay_rent_debt(pid)` (M3.1) |
| `debts.gd` `Debts` (M4.2) | společná evidence dluhů (pokuty, upomínka +1 000 Kč, exekuce z účtu po 30 dnech, příkazy poštou), stav per hráč | `World.debts`: `add(pid, kind, kc, due_jd, text, ref)`, `queue_order`, `pay(pid, id, kc, "cash"/"bank")`, `list`, `total(pid, kinds)`, `advance_to(jd)` (denní krok), `to_dict/from_dict` (klíč `debts`); `World.pay_debts_office(id)` |
| `law.gd` `Law` (M0.5), `permits.gd` `Permits` (M6.1), `police.gd` | zákon jako data (`data/zakon.json` – řádky s `drb`, `karma`, `misto`), rejstřík a body per hráč, doklady, policie | `World.commit_offense(id, oid, data)`, `World.law[id]` (`LawRecord`: `records`, `points`, `unpaid_fines`), `World.permits` (jedna instance: `has(pid, kind, sub := "")`, `grant(pid, kind, no, sub)`, `revoke / restore / list / subs`, `KINDS` – nový druh vždy do `KINDS`; řidičák `ridicsky` má skupiny), `World.license_check(id, car)` (skupina vozidla, M4.1), `World.auto_enroll / auto_school` (autoškola), `World.has_permit(id, kind, pos)` (les.work_permit + Permits + cheat), svědci dnes `Forestry.witness_near(pos, r)` (M4.4 → `World.witness_check`), nenahlášené činy `Forestry.unreported` (M4.4 sjednotí), `Police.license_ok(p)` = jen zákaz řízení |
| `jobs.gd` `Jobs` (M3.1) + `data/prace.json` | zaměstnání per hráč: katalog prací a pracovních úkolů, pohovor, směny a docházka, napomenutí → výpověď, výplata, deník J → Práce | `World.jobs[id]`, `current`, `can_apply(job)`, `apply(job)`, `quit()`, `fire(reason)`, `place_options(place)` (přes `Quests.place_options`), `Jobs.set_provider(jméno, Callable(world, pid, job) -> Array[Vector3])`, `Jobs.job/task_def/jobs_at/shifts_on`, `target()`, `hud_text()`, `journal_bbcode()`; události `job_*`, `shift_started/done`; typy úkolů `akce` / `dojdi` |
| `prace/statek.gd` `Statek`, `prace/udrzba.gd` `ObecniUdrzba`, `prace/vycep.gd` `Vycep` (M3.2) | pracoviště prvních tří prací: statek (dědí `Farm`, místo „statek“, výběh, stodola), obecní údržba (zóny trávy / listí / sněhu, lavička, odpadky), čepování | `World.statek / udrzba / vycep`, poskytovatelé `statek_*`, `udrzba_*`, `vycep_kompas`; `Estate.set_estate_owner / owner_of / pick_farmstead`; `Pen.setup_at`; `FarmAnimal.hold`; Jobs: `on_shift`, `task_id`, `lend` / `unlend`, `adjust_rating`, `own_target`, `task_ok`, klíče úkolů `mesice`, `snih_min/max`, `zapujcit`, `r_cile`, `kompas` |
| `prace/les.gd` `LesniPrace`, `prace/obchod.gd` `ProdavacPrace`, `prace/zahradnik.gd` `ZahradnikPrace`, `prace/palenice.gd` `PalenicePrace` (M3.3) | lesní dělník (paseka u chaty, vyznačené stromy, hromada), prodavač/ka (pokladna – minihra s mincemi, bedny do regálu, pečivo), zahradník u sousedů (zakázky od dědy, dočasná zóna u domu zákazníka), pálenice (kvas, topení – minihra teploty, lahve) | `World.les / obchod / zahradnik / palenice`; Jobs: typ úkolu `modul` + `progress(task, n)`, `hodiny`, varianty směn `smeny[].nazev` + `smeny_volba` (`shift_pick`), zakázky `druh: "zakazka"` + `set_contract_maker` / `take_contract` / `contract()`, `set_event_hook(job, Callable)`, práce `mesice`, `naturalie`; `Actions.chain_target_check`; `Cargo.shoulder_new / carried_kind / consume_carried` (náklad `bedna`, `sud`); `Estate.pick_customer_house`; události `job_contract`, `job_contract_done`, `job_contract_failed`, `log_lopped`, `log_cut` |
| `computer.gd` `Computer`, `computer_ui.gd` `ComputerUI`, `test_ui.gd` `TestUI` (M3.4) | počítač doma (E u PC v domově): banka (účet, trvalý příkaz na nájem, pokuty, výplata na účet), bankomaty u Potravin a úřadu, e-shop eŠuplík s balíky ke dveřím, Bazárek, Práce v kraji (pozvánky na pohovor), web obce (kalendář, otevírací doby, úřední deska, drby), pošta, eTesty (`data/testy/<id>.json`), Miny | `World.computer`, `Player.bank`, `World.mail[id]`, `World.orders[id]`, **`World.send_mail(id, od, předmět, text)`**, `Computer.deposit / withdraw_bank / pay_rent / pay_fines / order / answer_ad / calendar / gossip / record_test`, `Computer.TESTS`, `NOTICE_BOARD` (háčky M4.4, M4.7, M7), `GOSSIP_EVENTS`; `Jobs.pay_bank`, `Jobs.invite(job)`; `ComputerUI.open_for(client)`, `Interior.spots["pc_seat"]`; události `eshop_order`, `parcel_picked`, `bank_atm`, `fines_paid`, `job_ad_answered`, `etest_done` (M4.1 / M4.6), `pc_game_won` |
| `interior.gd` `Interior`, `public_interiors.gd`, `interior_gen.gd` `InteriorGen`, `interior_streamer.gd` `InteriorStreamer` (M1.4–M1.8) | interiéry pod mapou: stavebnice místností, veřejné budovy, generované z půdorysu (dům, bytový dům, hala); stavba jen zblízka (max. 3), vstup dveřmi, cizí domy zamčené s klepáním | `World.interiors` (jen postavené), `World.ensure_interior(iid)`, `enter_interior` / `exit_interior`, `interior_mark` / `interior_clear`, id `"b:<estate id>"`, `InteriorStreamer.access / knock / resident_of`, `Interior.spots`, objekty → `InteriorMenu` |
| `sfx.gd`, `priroda/nature_sfx.gd` | procedurální zvuky | |
| `tests.gd` | automatické testy (spouští jen uživatel) | `--questtest` … |

**Tok zpráv (příprava na multiplayer – dodržuj):** logika ve `World` (nebo v uzlu, který World vlastní),
hráč se identifikuje `id`. Zprávy hráči jen přes `World.notify(id, "metoda_hud", [..])`, zvuk v místě přes
signál `World.sound`, herní události přes `World.emit_game_event(id, kind, data)` – ty dostanou klient
(`on_game_event`), úkoly (`Quests.on_event`) a pověst (`Reputation.on_event`). Nové systémy (dovednosti,
zákon, respekt…) se na `emit_game_event` napojí stejně. **Nevolej HUD přímo ze světa.**

## 5. Konvence pro nové systémy

1. **Nový globální systém** = nový soubor s `class_name`, instanci vlastní `World` (per hráč jako
   `World.reputations[id]`). `run.sh` sám obnoví seznam tříd, když je nový skript (nic nespouštěj).
2. **Nová data** do `data/*.json`, když je bude upravovat člověk; jinak `const` slovník v kódu.
3. **Modely:** přednostně procedurálně přes `MeshKit` (styl hry – barvy vrcholů, jeden draw call),
   nebo `.glb` v `models/` + záznam v `assets/LICENSES.md`. Měřítko 1 j = 1 m, −Z dopředu.
4. **Fyzikální vrstvy:** 1 statika (terén, budovy), 8 rekvizity (viz `Fauna.PERCH_MASK`); ověř
   grepem `collision_layer` v souboru, který rozšiřuješ.
5. **Výkon:** nic těžkého v `_process` pro stovky objektů; daleko od hráče (> ~150 m) bez fyziky,
   jen data; MultiMesh pro opakované objekty; LOD / `visibility_range_end`.
6. **Ukládání:** každý nový stav přidej do `save_game.gd` (klíč s výchozí hodnotou při načítání –
   `d.get("klic", výchozí)`), aby šly načíst staré pozice. `SaveGame.VERSION` zvyšuj jen při
   nekompatibilní změně a přidej převod.
7. **Klávesy – registr** (před přiřazením nové ověř `project.godot [input]` a README → Ovládání):

| Obsazeno | Rezervováno pro roadmapu |
|---|---|
| WASD, myš, Shift, Mezerník, Ctrl/C, V, kolečko, E, T/Enter, F, L, B, N, R, H, U (vyproštění), X (dalekohled), O (fotka dronem – jen za letu), **Z** (fyzicky Y – panel úkolu), Tab, J, M, F1, F2, F5, F9, Esc, Backspace (deník), **P** (panel dokladů, M4.1), hvízdnutí na koně (viz `project.godot`; **G je sdílené s nákladem**, M2.10) | **Q** = nástroj / zbraň do ruky (cyklus), **1–5** = rychlé sloty opasku, **levé tlačítko myši** = použít nástroj / vystřelit (pěšky), **pravé tlačítko** = mířit, **G** = zvednout / položit / naložit náklad (**sdílená klávesa**: `Cargo.on_g` nejdřív zkusí náklad v dosahu nebo nesený, jinak hvízdnutí na koně – `World.player_action("whistle")`), **K** = dovednosti (záložka deníku), **I** = oblečení / šatník (mimo domov jen prohlížení), **F3, F4, F6–F8, 6–0** = volné (pozor na QWERTZ – `physical_keycode`) |

8. **Nápověda:** každá nová klávesa do F1 (`hud.gd`, text nápovědy) a do README → Ovládání.
9. **Deník J:** nové přehledy (dovednosti, doklady, respekt, práce…) jako oddíly v `Hud._journal_bbcode()`.

## 6. Statická kontrola před commitem (místo spuštění hry)

- **Povinná kontrola překladu (uživatel povolil):** po dokončení změn spusť
  ```bash
  timeout 300 godot --headless --path . --import >/dev/null 2>&1
  for f in $(git diff --name-only HEAD -- '*.gd') <nové .gd soubory>; do
    timeout 60 godot --headless --path . --check-only --script res://$f 2>&1 | grep -E "SCRIPT ERROR|ERROR:"
  done
  ```
  Výstup musí být prázdný. Hlášky „Could not resolve…“ / „Cannot infer the type…“ jsou často jen následek
  chyby v jiném skriptu – oprav první skutečnou příčinu a zkontroluj znovu. Hru samotnou ani testy (`--…test`)
  nespouštěj. (Ve vlně 0 tahle kontrola odhalila 3 chyby, kvůli kterým hra nešla spustit: duplicitní
  proměnná ve funkci, nespárovaná závorka, `:=` s hodnotou bez typu z proměnné typu `Node`.)
- `grep -n` na každou nově volanou funkci / proměnnou – existuje a má správné parametry?
- Nový `class_name` nekoliduje s existujícím (`grep -rn "class_name X" scripts`).
- **Názvy metod a proměnných nesmí kolidovat s nativními členy** `Node` / `Node3D` / `Object` (`set_owner`, `owner`, `name`,
  `get_parent`, `set_process`, `position`, `visible`, `get_index`, `duplicate`…). Varování „overrides a method from native
  class“ se v projektu bere jako **chyba** → nepřeloží se celá hra (jen modrá plocha). Viz oprava `8a90966`.
- Typované GDScript 4.3: hodnoty z `Dictionary.get()` jsou Variant → přiřazuj do typované proměnné
  (`var x: float = d.get("x", 0.0)`), ne `:=`. Žádný ternární `?:`, jen `a if c else b`.
- Signály připojené jednou (ne v `_process`), `is_instance_valid` u uzlů, které mohou zmizet.
- Ukládání: nový klíč se ukládá i načítá; starý save bez klíče nespadne.
- Texty česky s diakritikou, žádná reálná jména / značky.

## 7. Formát záznamu v `PROJECT_LOG.md`

```markdown
## RRRR-MM-DD – M0.2 Jednotný katalog předmětů

### Hotovo (staticky ověřeno čtením kódu – ruční test čeká)
- **Co**: soubory, třídy, klíčová API, laditelné tabulky …

### Otevřené body
- Čeká na ruční test uživatele (checklist v odpovědi).
- Co se nestihlo / co navazuje …
```

## 8. Kde hledat víc
- Vize a roadmapa: `docs/VIZE_A_ROADMAPA.md` (kap. 3 jádro mechanik, kap. 4 moduly).
- Původní poznámky: `docs/požadavky.md`.
- Herní dokument: `GAME_DESIGN.md`. Návody: `BLENDER_UPRAVY.md`, `VLASTNI_VOZIDLA.md`, `ZVIRATA.md`.
- Historie a otevřené body předchozích kroků: konec `PROJECT_LOG.md` (čti poslední 2–3 záznamy).
