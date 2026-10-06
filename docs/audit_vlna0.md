# Audit vlny 0 (2026-10-06) – seznam chyb k opravě

Statický audit (čtení kódu, hra nespuštěna). ID: A1 svět/mapa/interiéry, A2 vozidla/doprava/létání,
A3 řemesla/tělo hráče, A4 práce/PC/zákon/NPC. Řádky platí ke commitu `1770152`.
Skupina = který opravný subagent nález řeší (F1–F5), „odloženo“ = jen zapsat do PROJECT_LOG.

## F1 – Létání M6 (`scripts/flight/*`, `player.gd` enter_aircraft, `tests.gd`, `world.gd` ground_height)
- **A2-01 kritická** `aircraft.gd:285-286` – po Jolt migraci (7e04cc7) `linear_damp=0.1` COMBINE + projektových 0.1
  = fiktivní odpor 0.2·v (paramotor ~290 N, trike ~1860 N při tahu 335 N) → nejde vzlétnout. Vrátit
  `custom_integrator=true` + `_integrate_forces` (vzor `dron.gd`), nebo DAMP_MODE_REPLACE s 0.
- **A2-02 kritická** `aircraft.gd:39-56` SPECS, 515, 575 – tah T0·(1−v/vmax) v trimu ~0; CD0 0.16/0.13 moc vysoké;
  jiná křivka tahu na zemi (skok při odlepení). CD0 odvodit z `glide`: CD0 = CL_trim/glide − CL²/(π·AR·e)
  (~0.035 / 0.03); jedna křivka T0·(1−0.5·(v/vmax)²). Test `tests.gd:1243-1268` zpřísnit: 10 s po odlepení AGL > 20 m.
- **A2-03 vysoká** `aircraft.gd:531-539`, `paramotor.gd:211-221` – na zemi rychlost ve směru nakloněného nosu → α≈0;
  rychlost na zemi vodorovně, náběh = pitch.
- **A2-04 vysoká** `aircraft.gd:595` – dosednutí bez hystereze (`v.y <= 1.0`); dát `v.y < -0.1`, `agl < gear_h-0.05`, ≥ 0.5 s od vzletu.
- **A2-05 vysoká** `player.gd:633` – pilot obráceně (Humanoid kouká +Z, letouny −Z) → `visual.rotation = (0, PI, 0)` u letounu.
- **A2-06 vysoká** `aircraft.gd:528/601` + meshe (`aircraft.gd:318-326`, `trike.gd:254-265`, `paramotor.gd:365-377`) –
  počátek tělesa na gy+gear_h, mesh postaven od y=0 → kola 0.55–0.85 m nad zemí. Mezivrstva vis posunutá o −gear_h (i seat_pos, kolize).
- **A2-07 střední** `aircraft.gd:710-715` – havárie o terén při banku/hrbolu; terén v `_on_body` ignorovat.
- **A2-08 střední** `player.gd:620-637`, seat_pos – `visual.ride` zůstává z posledního auta; každý stroj vlastní `rider` pózu, při výstupu `ride = {}`.
- **A2-09 střední** `paramotor.gd:440-457` – na zemi pilot visí 0.5 m nad trávou, položené křídlo svislá stěna.
- **A2-10 nízká/stř.** `trike.gd:315-324, 134-137` – rogalo plochý trojúhelník (trubky, kýl, prohnutí, oboustranné normály); spolujezdec neviditelný.
- **A2-11 střední** `aircraft.gd:476`, `world.gd:3069` – za okrajem terénu AGL z clampnutého okraje → `World.ground_height(x,z)` s `surroundings.height_at`.
- **A2-12 nízká** `aircraft.gd:493` – push u hranice letu: m/s přičítané jako zrychlení; na zemi ignorovat.
- **A2-13 nízká (UX)** `trike.gd:94-96`, `paramotor.gd:196` – trike výchozí obrácené řízení → intuitivní výchozí; Shift před nahozením křídla jen varování.
- **A4-08 (část)** `ul_bez_pojisteni` nikdo neuděluje → napojit na kontrolu pojištění v `trike.gd`.

## F2 – Doprava (`car.gd` AI část, `road_graph.gd`, `traffic.gd`, `police.gd`, `tools/clean_road_clashes.py`)
- **A2-14 kritická** `car.gd:1298, 1306-1310, 1378-1379` – bod trasy se odbaví jen do 3/7 m; při seříznutí rohu cíl zůstane za autem → kroužení/couvání. Odbavovat podle průmětu na úsek; necílit bod s local.z < 0.
- **A2-15 vysoká** `car.gd:1303-1310` – seříznutí ostré zatáčky; pure pursuit na interpolovaný bod L = clamp(0.6·v+3, 4, 14), brzdit podle poloměru.
- **A2-16 vysoká** `road_graph.gd:160-165, 171-183` – offset pruhu bez 1/cos(θ/2), `_cut_hairpins` maže lomy → mitre + zaoblení rohů.
- **A2-17 vysoká (data)** `tools/clean_road_clashes.py:40-44` – domy 0.8–2 m od osy silnice (32 míst, např. (344.7, 44.1), náves (116.2, 195.1)); test proti ose z `map.json` s bufferem, artefakty do `REMOVE_BUILDINGS`, regenerace `data/*.bin`.
- **A2-18 vysoká** `car.gd:1442` `_obstacle_ahead` – maska bez statiky → AI najede do domu; shape-cast na vrstvu 1 bez terénu.
- **A2-19 střední** `road_graph.gd:5`, `traffic.gd:271-281` – start/cíl tras na service větvích → jen průjezd.
- **A2-20 střední** `traffic.gd:318-321` – zaseknuté auto u hráče (< 60 m) stojí navždy → přeplánovat od aktuální pozice.
- **A2-21 střední** `police.gd:400-405` – přeplánování s ai_i = 0 → kličkování; přeskočit body za autem.
- **A2-22 nízká** `car.gd:1376` vs 1139 – sjednotit max. rejd. **A2-23 nízká** `car.gd:1315-1320` brzdná vzdálenost.

## F3 – Hráč a řemesla (`player.gd`, `body_state.gd`, `cargo.gd`, `hunting.gd`, `quests.gd`, `place.gd` cigarety, …)
- **A3-01 / A1-11 vysoká** `place.gd:14` – cigarety v hospodě → odebrat (rozhodnutí: jen obchod); text `quests.gd:330`.
- **A3-02 vysoká** `body_state.gd:329-333, 46-47` – chuť po ~15 min reálně; nové konstanty CRAVING_NICOTINE_MIN 0.25, CRAVING_RATE 0.07, strop 0.35+0.65·addiction, ADDICTION_NORM 80, ADDICTION_DECAY_K 0.0578.
- **A3-03 vysoká** `body_state.gd:329-331` + `skip_hours` – po spánku 100 % chuť → CRAVING_SLEEP_K 0.2.
- **A3-04 vysoká** `player.gd:1199-1203` – třes = bílý šum každý snímek; hladký šum, práh 0.6, amplituda 0.0009, „záchvaty“ ~5 s/60 s, ne při míření; nastavení `withdrawal_shake` (game_settings, pause_menu).
- **A3-05 střední** `player.gd:1204-1205` – třes zimou 13× silnější → stejná úprava, strop 0.003.
- **A3-06 / A2-24 vysoká** `cargo.gd:363-381, 863, 982-983`, `hunting.gd:674-737`, `quests.gd:862-878` – sprint po vozíku: absolutní snímky walk/sprint speed se obnovují v opačném pořadí (scénář vozík + Krmivo quest). `Player.speed_mods` (zdroj → modifikátor), efektivní rychlost v `player.gd:853-860`.
- **A3-07 střední** `cargo.gd:954, 986`, `hunting.gd:757-760` – výdrž obchází `drain_stamina`.
- **A3-08 střední** `save_game.gd:22-24` – `addiction`, `_smoke_rate` se neukládají.
- **A3-09 střední** `farm/farm.gd:358-366` – `_slaughter_go` bez is_instance_valid po await.
- **A3-10 nízká** `quests.gd:337-354` – úkol cigarety vyžaduje přesně ≥ 20 ks.
- **A3-11 nízká** `player.gd:308-310` – skrytá magie ×20 pro cigarety v add_item.
- **A3-13 nízká** `action_runner.gd:150-155`, fishing – `p.input` null guard.
- **A1-09 střední** `player.gd:233-240` `_recover_from_void` v interiéru → na `inside_door` / exit_interior + log.

## F4 – Svět, mapa, místa (`local_client.gd`, `hud.gd`, `world.gd`, `game_menu.gd`, `save_game.gd`, `place.gd` hodiny, interiéry)
- **A1-01 vysoká** `local_client.gd:333-340` – kolečko zoomuje kameru v menu/chatu.
- **A1-02 vysoká** `hud.gd:1535-1650, 2055-2118` – mapa M překresluje ~100 tis. bodů každý snímek → překreslit jen při změně, keš vrstev, ořez.
- **A1-03 vysoká** `hud.gd:1571-1582 vs 2086-2102` – silnice obcí 2×.
- **A1-04 střední** `world.gd:3006-3012` – `map_texture()` 1,34 mil. pixelů v GDScriptu (záškub při startu).
- **A1-05 + A4-01 vysoká** `world.gd:2786` `buy` bez `is_open`; `local_client.gd:591-596` zavřené místo nabízí práci/úkoly; obsluha venku 24/7 (`place.gd:185-199`).
- **A4-02 vysoká** `place.gd:87-95` – úřad otevřen o víkendu/svátcích → úřední dny (Po a St déle), CLOSED_ON_HOLIDAY.
- **A1-06** logika víkendových hodin obchodu je správná (příčina hlášení = A1-05/A4-01); do `hours_text()` přidat dny.
- **A1-07 střední** `game_menu.gd:208-237` – F2 Teleport do 5 okolních obcí.
- **A1-08 střední** `save_game.gd:217-224` – load uvnitř neexistujícího interiéru → spawn.
- **A1-10 střední** `world.gd:1251-1268` – propad po výstupu z obchodu: příčina nepotvrzena → raycast podlahy po výstupu + diagnostický log.
- **A1-12 nízká** mapa + menu současně. **A1-13 nízká** text „Stromy (21 800)“ (je 51 736). **A1-17 nízká** `exit_interior` odemkne controls_locked při menu. **A1-18 nízká** `_map_extent` keš. **A1-20 nízká** kontrolní raycast `inside_door`.
- **A4-06 střední** `world.gd:3399-3402` – víkendový dav duplikuje pojmenované postavy a míchá persony v save.
- **A4-09 střední** `world.gd:2627-2628` – hody/masopust v dialogu jinak než VillageEvents.

## F5 – NPC, zákon, obsah (`villager.gd`, `scripts/ai/*`, `dog.gd`, `npc.gd`, `computer*.gd`, `test_ui.gd`, `reputation.gd`, `data/zakon.json`, texty)
- **A4-03 střední** `villager.gd:420-426` – zaseknutí u plotu: replan vynuluje přeskočení → po 3 zaseknutích vzdát cíl.
- **A4-04 střední** `villager.gd:16-36`, `world.gd:829-833` – mapování povolání podřetězcem („hospodář“ → hospoda), `statek` vzniká později → workplace INF (počet BT vesničanů zatím neměnit – výkon).
- **A4-05 střední** `ai/villager_routine.tres` (gen `tools/gen_villager_bt.gd`), `ai/conditions/*` – chybí podmínka „místo otevřeno“, víkend/neděle (procházka, nákup), zahrada podle počasí, kmitání pivní větve.
- **A4-08 střední** `data/zakon.json` – 8 řádků `zakon:"?"` (doplnit zákon a § s „ověřit“), `rychlost_obec_20` název, duplicita `poskozeni_veci`/`poskozeni_cizi_veci`.
- **A4-10 nízká** eTesty: správná odpověď skoro vždy B → zamíchat odpovědi; `pocet` (losování) a `prah_pct` v TestUI.
- **A4-11 nízká** F2 Datum rozbije absolutní časy Jobs → reset po `set_date`.
- **A4-12 nízká** `villager.gd:278-287`, `dog.gd:91`, `npc.gd:109-117` – `player_world_pos` místo `global_position` (hráč v interiéru).
- **A4-13 nízká** `computer.gd:795` – drby z `nazev.to_lower()` → pole `drb` v zakon.json.
- **A4-14 nízká** `reputation.gd:47-56` – OFFENSE_KARMA nezná nová id → pole `karma` v zakon.json.
- **A4-16 střední (právní)** Zetor (`dialog.gd:97`, `characters.gd:30`), ÚCL (`computer_ui.gd`, `permits.gd`, `zakon.json:111`), souřadnice v `clock.gd:6`, „Velký Ořechov“ v `DALSI DOPLNKY.md:34` → smyšlené.

## Odloženo (zapsat do PROJECT_LOG, řešit později)
- A1-14 paměť terénu, A1-15 sloučení toků do dlaždic, A1-16 rozlišení minimapy, A1-19 mrtvý `villages.gd`, A3-12 keš úrovní.
- A4-07, A4-15 (stav řízení, „odebráno – přezkoušení“) → patří do M4.1 / M4.2.
- Rozdíly kód ↔ prompty M4 (API `Permits`, `witness_near` vs `witness_check`, `Law.hidden` vs `Forestry.unreported`,
  `criminal_record`, `SENTENCES`, druhy oprávnění `kaceni` vs `povoleni_kaceni`, chybějící `autoskola.json`) → úprava promptů M4 před startem M4.
