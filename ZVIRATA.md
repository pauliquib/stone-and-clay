# Zvířata, počasí a roční období – jak je upravit

Všechno je procedurální (žádné soubory modelů) a řízené **tabulkami na jednom místě**. Úprava = změnit
čísla, uložit, spustit náhled nebo hru. Po přidání nového souboru s `class_name` spusť jednou
`godot --headless --path . --import` (dělá to i `run.sh`).

## Náhled modelů (zoo)

```bash
godot --path . --script res://tools/dev/zoo.gd                       # okno, animace chůze
godot --path . --script res://tools/dev/zoo.gd -- --anim=gallop       # stand, walk, trot, canter, gallop, graze, lie, alert, situp, root
godot --path . --script res://tools/dev/zoo.gd -- --only=kun --cam=3,2.4,5 --look=0,1.2,0
godot --path . --script res://tools/dev/zoo.gd -- --slope=15          # nakloněná zem – IK chodidel
godot --path . --script res://tools/dev/zoo.gd -- --series=/tmp/zoo  # 8 snímků (pózy, chody, detaily) a konec
```

Ve hře: **F2 → Teleport → Ke srncům / K divočákům / K zajíci / K včelám / K mraveništi**.
**F2 → Příroda – kde je zvěř…**: počet živých zvířat do 300 m, nejbližší 3 (druh, vzdálenost, světová strana, stav),
nejbližší hejno ptáků (druh, vzdálenost, režim) + volby „Vygenerovat zvěř u mě“ (60–110 m mimo zorný kužel,
bez ohledu na limity) a „Přiletí hejno ptáků“ (40–120 m).

## Čtyřnožci – `scripts/fauna/animal_specs.gd`

Tabulka `SPECIES` (srnec, divočák, sele, zajíc, kůň); co druh neuvede, bere se z `DEFAULT`
(a u selete z `"base": "divocak"`). Souřadnice: počátek na zemi pod trupem, +Z dopředu, metry, radiány.

| Klíč | Význam |
|---|---|
| `length`, `withers`, `croup` | délka trupu, výška v kohoutku a na zádi |
| `chest`, `belly`, `hips` | poloměry trupu [do šířky, do výšky] – hruď, břicho, pánev (trup je „loft“ elips) |
| `neck` | [délka, poloměr u trupu, úhel od vodorovné]; `neck_top_r` poloměr u hlavy |
| `head` | [délka, poloměr lebky, poloměr čenichu, sklon hlavy dolů vůči krku] |
| `ears`, `tail` | [délka, šířka/poloměr, rozevření / sklon] |
| `front_seg`, `hind_seg` | poměry délek 3 článků nohy – skutečné délky se dopočítají, aby noha dosáhla na zem |
| `front_rest`, `hind_rest` | klidové úhly článků od svislice (+ = konec článku dopředu) – postoj |
| `front_fold`, `hind_fold` | ohnutí článků při přenosu nohy (krok) |
| `front_lie`, `hind_lie` | úhly nohou vleže |
| `coat`, `belly_col`, `dark`, `rump`, `stripes`, … | barvy (sRGB); `rump` zrcátko, `stripes` pruhy selat, `winter_coat` zimní srst |
| `antlers`, `tusks`, `mane`, `tail_hair`, `blaze`, `tack` | parůžky, kly, hříva, žíně, lysina, sedlo s uzdečkou |
| `mass`, `accel`, `brake` | hmotnost, max. zrychlení a zpomalení (m/s²) |
| `gaits` | horní hranice rychlosti chodů krok / klus / cval / trysk (m/s); `gallop_kind`: `gallop` nebo `bound` (skoky) |
| `turn`, `lat_acc` | otáčení na místě (rad/s), max. boční zrychlení → poloměr zatáčky v rychlosti |
| `jump`, `pronk`, `max_slope` | výška skoku (m), odrazové skoky při útěku (srnec), nejprudší svah (°) |
| `rise_front_first` | vstává předníma (kůň; jinak zadníma), lehá vždy předními |
| `step_k`, `bob` | kmitočet kroků (menší zvíře víc), pohupování trupu |
| `behaviour`, `habitat`, `group` | chování (`grazer`, `rooter`, `hare`), stanoviště (`forest`, `edge`, `field`), velikost skupiny |
| `sight`, `hearing`, `flight`, `safe` | na kolik m vidí / slyší člověka, úniková vzdálenost, kde se uklidní |
| `flee_speed`, `calm` | běžná rychlost útěku (m/s; plný trysk `gallop` jen zblízka / před autem), 0..1 jak si zvykne na nehybného člověka dál než `flight` |
| `active`, `home_range`, `sounds` | hodiny aktivity [od, do, …], okrsek (m), zvuky z `priroda/nature_sfx.gd` |

Stavba modelu je v `quadruped_model.gd`, animace chodů v `quadruped_rig.gd` (tabulka `GAITS`: posuny
fází nohou a podíl stojné fáze; `IK_W` váhy nápravy IK na články, `ik_max` max. náprsa, `ground_fn`
funkce výšky terénu, `sit` posed na zadních), chování v `animal.gd`, kůň v `horse.gd` (`STAMINA_*`,
ovládání). IK chodidel běží jen u zvířat do 110 m (LOD FULL), animace zvířat na 110–260 m jede ~10×/s.

**Nový druh:** přidej položku do `SPECIES` (např. `"liska": {...}`) a do `Fauna.POPULATION` v
`fauna.gd` (`"liska": [počet skupin, rozestup m]`). Do zoo ho přidáš v `tools/dev/zoo.gd` (seznam `defs`).

## Počty a rozmístění – `scripts/fauna/fauna.gd`

`POPULATION`, `APIARIES`, `ANTHILLS`, `CROW_FLOCKS`, `BLACKBIRDS`, `SWALLOW_FLOCKS`, `BUZZARDS`.
Mapa stanovišť (buňky 32 m) se staví z `data/trees.bin` (les), `data/roofs.bin` (zástavba) a silnic;
`score(stanoviště, x, z)` říká, jak je místo vhodné (`forest`, `edge`, `field`, `garden`, `meadow`).

**Setkání u hráče:** `_encounter_scan` (každých `ENCOUNTER_T` s) zjistí stanoviště, kde hráč stojí,
a když v okruhu `ENCOUNTER_R` není dost živé zvěře (`ENCOUNTER_NEAR`), vygeneruje mu skupinu
`SPAWN_MIN`–`SPAWN_MAX` (70–170 m) daleko (`ENCOUNTER_SPECIES` = stanoviště → pravděpodobnosti druhů,
`FLOCK_HAB`/`ENCOUNTER_BIRDS` = hejna ptáků, klíč `village` = kos, vlaštovka, vrána). Nejmenší skóre
stanoviště je `HABITAT_MIN`. Ve vesnici (žádné vhodné stanoviště) se zvěř hledá v prstenci `NEAR_RING`
(90–250 m, `_habitat_near`), takže ji jde vidět z okraje vesnice. Blíž než `VIEW_CLEAR` (120 m) se
nová skupina ani hejno neobjeví v zorném kuželu hráče (`VIEW_HALF_ANGLE` ±40°, směr z `player.yaw`);
nově vytvořená zvěř má `aware = 0`. Ptáci: `BIRD_CHANCE` (0,5) na sken. Takové skupiny (`Herd.transient`)
i hejna po odchodu všech hráčů na `TRANSIENT_GONE` m zmizí; strop je `TRANSIENT_MAX`.

**Klidná zvěř:** útěk je rychlostí `flee_speed`, plný `gallop` jen když je hrozba blíž než ~0,6 `flight`
nebo jede auto > 8 m/s. Zvěř začne utíkat, až když je hrozba blíž než `flight` a zároveň `aware > 0,45`
nebo blíž než ½ `flight`. Nehybný člověk dál než `flight` zvíře pozornost zvedne nejvýš na 0,7 (`calm`);
v pozoru (`alert`) se zvíře po 8 s bez přibližování uklidní (`_calm_t`, 30 s pak nereaguje) a při pastvě
se jen občas ohlédne. Pastva trvá 20–60 s, přesuny krokem (< 60 m) nebo 1,5× krokem.

## Ptáci – `scripts/fauna/bird.gd`, `bird_flock.gd`

`Bird.SPECIES`: délka, rozpětí, barvy (u kosa samice, u vrány šedá forma), cestovní a max. rychlost,
kmitočet mávání, max. náklon a stoupání, pohyb po zemi (`walk`/`hop`/`none`), úniková vzdálenost,
`fingers` (roztažené „prsty“ letek na špičce – káně, vrána). Chování hejn (kdy vzlétnou, kam letí,
zpěv, sezóna vlaštovek) je v `bird_flock.gd` po druzích (časy posedávání v konstantách nahoře:
`CROW_*`, `BLACKBIRD_CYCLE`, `SWALLOW_HUNT/SIT`, `BUZZARD_*`, dosahy vyrušení `SCARE_GROUND/PERCH`).

**Bidýlka:** `Fauna.perch_spots(střed, poloměr, n, min_h, podíl_střech, min_strom)` vrací `Vector4(x, y, z, kind)`,
kind 0 = vršek koruny (`trees_near`), kind 1 = střecha / předmět (paprsek shora dolů, maska statika + rekvizity,
`normal.y > 0,45`, hřeben = nejvyšší z pěti zásahů; max 24 paprsků na volání, volat jen z `_physics_process`).
`Fauna.ridge_row(střed, poloměr, n)` dá řadu bidýlek 0,15–0,25 m od sebe podél hřebene (vlaštovky).
Na střeše pták stojí na nohách (`Bird.perch_off` = 0,28 délky, na stromě 0,05 m); na bidýlku otáčí hlavou
(`REST_LOOK`) a občas si probere peří. Hráč blíž než `SCARE_PERCH` → hejno přeletí na jiné bidýlko.

## Hmyz – `apiary.gd`, `ant_hill.gd`

Konstanty nahoře: počet včel, dolet, rychlost, kolik jich útočí; počet mravenců, rychlost, zvětšení.

## Počasí a roční období

- `scripts/priroda/weather.gd` – `TYPES` (oblačnost, déšť, mlha, vítr, trvání), `NEXT` (přechody), časové
  konstanty, `SNOW_BELOW`. **Přilnavost a hratelnost**: `SURF_GRIP` (suchá přilnavost povrchů) a
  `GRIP_WET / GRIP_SNOW / GRIP_ICE / GRIP_MUD / ICE_WET` – jedna tabulka pro auto, chodce i koně
  (`surface_grip` pro auto; chodec a kůň berou `grip_factor` = poměr k suchému povrchu); `forecast()` =
  předpověď na zítřek pro deník J; `force("snih" / "naledi")` drží mráz, dokud je počasí vynucené.
- `scripts/priroda/chimney_smoke.gd` – kouř z komínů (M1.3), tabulka `SmokeRules` (klient, čte `Weather.temp / wind / fog / rain`):
  | teplota | 16 °C+ | 12 | 8 | 3 | 0 | −5 a méně |
  |---|---|---|---|---|---|---|
  | dům topí | 3 % | 15 % | 35 % | 65 % | 85 % | 100 % |
  Denní chod ×1,2 (5–9, 16–22 h), ×0,7 (23–4 h); `POOL` 24 emitorů, `NEAR_R` 350 m; vítr `gale` 6 m/s, inverze `fog_inversion` 0,4.
  Ladění teploty: `Weather.forced_temp` (F2 → Počasí → Teplota; `auto` ji zruší).
- `scripts/priroda/seasons.gd` – křivky po dnech v roce (`FOLIAGE`, `AUTUMN`, `GREEN`, `BLOOM`) a klima po
  měsících (`TEMP_MEAN`, `TEMP_RANGE`, `WET_DAYS`, `STORM_SHARE`).
- `scripts/priroda/atmosphere.gd` – síla slunce a měsíce, hustota mlhy, počty kapek a vloček.
- Hratelnost mimo přírodu: auto (`car.gd` – brzdění, AI opatrnost `AI_SLOW/AI_GAP`, stěrače, déšť na
  střeše), chodec (`player.gd` – kluzká chůze `_ground_traction`, stopy ve sněhu v `local_client.gd`),
  kůň (`fauna/horse.gd` – `HORSE_SLIP`, polekání hromem `STARTLE_R`), dohled v mlze (`fauna/animal.gd`
  `_perceive`, `police.gd` `_see_r`), promoknutí a prochladnutí (`body_state.gd` – `wetness`, `cold`).
  Diagnostika: `--weathertest` v `tests.gd`.
- `shaders/sky.gdshader` – barvy oblohy, mraky; `shaders/tree.gdshader`, `terrain.gdshader`,
  `tinted_triplanar.gdshader` – podzimní barvy, sníh, mokro (globální parametry v `project.godot`).
- **Krajina a život v obci podle kalendáře** (krok 03): `scripts/priroda/fields.gd` – tabulka `Fields.CROPS`
  (barvy plodin po dnech roku, váhy osevního postupu, `DATE_SPREAD`), data `data/landuse.bin` z `tools/landuse.py`;
  `meadow_flowers.gd` (`DENSITY`, `PALETTE`, `RADIUS`), `tree_decor.gd` (`FRUIT`, `LEAVES`, `CROWN_*`);
  `World.SEASON_ITEMS` (hřib / jablko / šípek: sezóna, znovuvyrůstání) a `HRIB_DRY`; `Weather.rain_recent`;
  `village_events.gd` – `VillageEvents.EVENTS` (svátky, hodiny, úprava otevírací doby), `BONFIRE_POS`, `HODY_WEEKEND`.
- `scripts/clock.gd` – zeměpisná poloha (`LAT`, `LON`), rychlost času (`TIME_SCALE`).


## Zvěř a hráč – myslivec, krmelec, stopy, péče o koně (krok Příroda 04)

Všechny laditelné hodnoty jsou konstanty nahoře v souboru.

| Co | Soubor | Konstanty |
|---|---|---|
| Poškození auta a zranění při srážce se zvěří | `world.gd` | `HIT_DAMAGE_K` (0,0022 % na kg·(m/s)²: zajíc ~2 %, srnec 70 km/h ~20 %, divočák 50 km/h ~37 %), `HIT_HORSE_K`, `HIT_INJURY_MASS/SPEED/K` |
| Lhůta a pokuta za nenahlášení srážky | `quests.gd` (`Quests`) | `HIT_REPORT_MIN` (60 herních min), `HIT_FINE` (2 000 Kč), `HIT_REWARD` |
| Krmelce, posed, sběr zvěře, parůžky, včelař | `fauna/hunter.gd` | `FEEDERS`, `FEEDER_R` (600 m), `FEEDER_MONTHS`, `FEEDER_SNOW`, `FEED_FROM/TO` (16–8 h), `FEED_SPECIES`, `PICKUP_*`, `ANTLER_R`, `BEEKEEPER_*` |
| Stopy ve sněhu | `priroda/tracks.gd` | `KINDS` (počet, životnost, barva a tvar stopy: boot, hoof, deer, boar, hare), `SNOW_MIN` |
| Péče o koně, přivolání, opilý jezdec | `fauna/horse.gd` | `WHISTLE_R` (300 m), `CALL_*`, `FED_DECAY`, `WATER_DECAY`, `NEEDY_BELOW`, `REGEN_FED_K`, `FEED_AMOUNT`, `GROOM_*`, `DRUNK_SLOW` (0,5 ‰), `DRUNK_REFUSE` (1,5 ‰), `DRUNK_FALL_K` |
| Výběh, žlab, napáječka | `fauna/paddock.gd` | `SIZES`, `GATE_W`, `FENCE_H`, `CARE_R` |
| Pozorování přírody | `priroda/nature_log.gd` | `SPECIES`, `VIEW_R/HALF`, `SCOPE_R/HALF`, `BEES_R`, `ANTS_R` |
| Dalekohled | `player.gd` | `SCOPE_FOV` (12°), `SCOPE_SENS` |

**Krmelec.** V zimě se u každé srnčí skupiny do 600 m od krmelce přepíše `Animal.home` na místo u krmelce (původní
hodnota je v `meta("home0")` a vrací se mimo sezónu). Vůdce skupiny za soumraku a v noci sám zamíří ke krmelci
(`Hunter._feeder_tick`, každých 15 s). Seno v krmelci je vidět jen, když krmelec táhne zvěř.

**Stopy.** `Animal._on_footfall` / `Horse._on_footfall` / `LocalClient._snow_footprint` volají `World.tracks.add(druh, poloha, yaw)`;
stopy se zapisují jen při `Weather.snow_cover > 0,15` a zvěř je stopuje jen v LOD FULL (do 110 m). Nový druh stopy = nový záznam v `KINDS`.

**Kůň.** Sytost a napojení (0..1) ubývají v reálném čase; nakrmený kůň obnovuje výdrž ×(1 + 0,8 × sytost), hladový / žíznivý
×0,6 a nejde do trysku, vyčesaný ×1,25 po dobu 4 min. Hvízdnutí (G) → `Horse.call_to`: po zemi (krok / klus / cval podle
vzdálenosti), ze zavřeného výběhu brankou (`Paddock.gate_in/out`).


## Hospodářská zvířata – výběh, kurník, chlívek, přístřešek (krok M2.6)

Vlastní systém vedle divoké zvěře a koně (`World.farm`, `scripts/farm/*.gd`), ale čtyřnožci sdílí `QuadrupedModel` /
`QuadrupedRig` se zvěří beze změny – nové druhy jsou jen řádky v `AnimalSpecs.SPECIES` (`prase_farm`, `koza`, `ovce`,
`krava`, `kralik`). Chování (bloudění po výběhu, hlad, produkty) je jednodušší než u `Animal` – zvíře je ochočené,
neutíká před hráčem, jen se v noci / dešti stáhne do přístřešku a při otevřené brance má malou šanci se zatoulat.

| Co | Soubor | Konstanty / klíče |
|---|---|---|
| Výběh (20 × 15 m), branka, tři přístřešky, napáječka | `farm/pen.gd` (`Pen`) | `SIZES`, `GATE_W`, `FENCE_H`; `shelter_pos` / `feed_pos` po druzích (`kurnik`, `chlivek`, `pristresek`) |
| Ekonomika a péče (ceny, krmivo, produkty, maso) | `farm/farm_specs.gd` (`FarmSpecs`) | `DATA` (6 druhů), `accepts_feed`, `YOUNG_SCALE` |
| Jedno zvíře: stav, bloudění, model | `farm/farm_animal.gd` (`FarmAnimal`) | `WANDER_SPEED`, `ESCAPE_CHANCE`, `_build_bird` (vlastní model slepice) |
| Menu, denní krok, porážka | `farm/farm.gd` (`Farm`) | `MAX_ANIMALS`, `STARVE_NEGLECT_H`, `BREED_CHANCE`, `BUTCHER_PRICE`, `HELPER_FRIEND` |

**Nový druh:** čtyřnožec = přidej řádek do `AnimalSpecs.SPECIES` (rozměry, barvy) a do `FarmSpecs.DATA` (ceny, krmivo,
produkt, maso) + `FarmSpecs.ORDER`; do zoo (`tools/dev/zoo.gd`) přidáš stejně jako u divoké zvěře. Slepice je výjimka –
model staví `FarmAnimal._build_bird` napřímo z `MeshKit` (ne `Bird`, ten je stavěný na létání).

**Péče a produkty.** Hlad a žízeň (0..1) klesají jednou za herní den (`Farm._day_tick`, stejný vzor doháněných dnů jako
`Garden._advance_days`); pasoucí se druhy (`FarmSpecs.graze`: koza, ovce, kráva) se mimo zimu sytí částečně samy.
Vejce (slepice) a mléko (koza, kráva) se hromadí do sebrání / podojení; vlna (ovce) jde ostříhat jednou ročně v sezóně
(`wool_months`). Dlouhé zanedbání (`starve_h ≥ STARVE_NEGLECT_H`) sníží karmu a se šancí `NEGLECT_OFFENSE_P` založí
přestupek `tyrani_zvirat` (`data/zakon.json`); bez jídla/vody zvíře nakonec uhyne. Otevřená branka (`Pen.gate_open`) dá
zvířeti u ní malou šanci utéct (`FarmAnimal.escaped`) – vrátí se nakrmením nebo vedením (`Farm._lead`).

**Porážka.** `Farm._slaughter_go` ztmaví obrazovku na 2 s (`World.blackout`, stejně jako mdloby) a dá maso podle
hmotnosti (`FarmSpecs.meat_kg`) a zdraví zvířete; prase navíc potřebuje pomocníka (přítel ≥ `HELPER_FRIEND`) nebo
řezníka za `BUTCHER_PRICE` Kč, dá sádlo, jitrnici a tlačenku a zvedne respekt komunity `sousede`.


## Lov zvěře – zásah, postřelení, úlovek (krok M2.9)

Zvěř (`Animal`) po zásahu střelou (`Animal.shot(zóna, energie, odkud, info)`, volá `Hunting.animal_shot`) reaguje podle zóny z `Weapons.hit_zone`:
- **hlava** a **srdce_plice** s energií ≥ práh (`KILL_HEAD_J` 40 J, `KILL_HEART_J` 75 J pro 24 kg, těžší zvíře × (hm. / 24)^0,6) – zvíře padne (hlava na místě, komora po
  20–60 m běhu); slabší zásah uspěje s pravděpodobností energie / práh, jinak je zvíře postřelené do břicha;
- **bricho** – `wound = "bricho"`: uteče 200–600 m (`WOUND_RUN_BELLY_M`), zalehne (`wound_lie`, stav `rest`) a po 60–180 herních minutách zhyne; při přiblížení hráče
  na 15 m se s 50 % zvedne a uteče dál (nejvýš 2×);
- **noha** – `wound = "noha"`, kulhá 15 min (`LIMP_S`, rychlost útěku × 0,55), krvavá stopa prvních 2 min; po zahojení bez dohledání karma −5.

Postřelené zvíře je pod kontrolou `Animal._wound_think` (běží před běžným `_perceive`); vynechává vnímání, prchá od místa rány přes `_flee_dir`. Krvavé kapky
(`Hunting.add_blood`) padají každých 2,5 m po trase, i ve vzdáleném LOD (interpolace mezi kroky). Mrtvé tělo zůstává (`keep_corpse`), `Hunting` ho eviduje jako
`Carcass`. **Posed:** `Animal._perceive` zkrátí zrak a čich na 60 %, když je hráč víc než 3 m nad terénem (`STAND_HEIGHT_M`, `STAND_SIGHT_K`). Laditelné
konstanty jsou nahoře v `animal.gd` (KILL_*, WOUND_*, LIMP_*, BLOOD_STEP_M) a v `data/lov.json` (doby lovu, výtěžnost, zkáza).

## Příroda v multiplayeru – příprava (krok Příroda 05, bez skutečné sítě)

Síťová vrstva (`net.gd`, ENet, RPC) ještě neexistuje. Tento krok jen připravil rozhraní, takže až vznikne, stačí
snímky posílat přes RPC. Všechno je za přepínači, které jsou ve hře pro jednoho hráče vypnuté (`authority = true`
všude), takže singleplayer se chová beze změny. Ověření: `godot --path . -- --naturesynctest` (loopback, spouští uživatel).

### Hotové API
| Co | Kde | Poznámka |
|---|---|---|
| kalendář | `Clock.state()` / `apply_state(s, interpolate := true)` | `minutes`, `start_jd`, `speed`, `paused`; rozdíl < 2 herní min se dorovná plynule za 1 s, jinak skok |
| počasí | `Weather.state()` / `apply_state(s)`, `authority` | stav + `forced`, `rain_recent`; klient (`authority = false`) nesimuluje, jen se k poslednímu stavu blíží ~2 s, bez náhodných blesků |
| blesk | signál `Weather.lightning(pos)`, `Weather.remote_lightning(pos)` | server pošle RPC ze signálu, klient zavolá `remote_lightning` (stejný efekt jako lokální blesk: záblesk, hrom, polekaný kůň) |
| oprávnění | `World.can_change_world(id)`, `World.can_teleport(id)` | SP vždy `true`; `GameMenu` je použije, jinak položka šedá „(jen hostitel)“; v MP `id == host` / `allow_cheats` |
| zvěř | `Animal.net_id`, `Animal.authority`, `Animal.net_record()`, `puppet_push()` | id přiděluje `Fauna._new_net_id()` (zvěř i hejna), kůň má id hráče (`Kun_%d`) |
| snímek zvěře | `Fauna.snapshot(center, radius := 400)`, `snapshot_for(player)`, `pack_snapshot` / `unpack_snapshot` | záznam `[net_id, druh, x, y, z (dm), yaw (1/1024), rychlost (dm/s), stav (Animal.STATES), příznaky]` |
| klient zvěře | `Fauna.setup_client(world)`, `apply_snapshot(arr, now_s)`, `puppets` | neznámé id → `_spawn_puppet`; kdo chybí > `PUPPET_GONE` (3 s), zmizí; loutka je `Animal` s `authority = false` bez kolizí |
| hejna | `BirdFlock.flock_state()` / `apply_flock_state(s)`, `Fauna.flock_snapshot` / `apply_flock_snapshot` | stav při změně režimu / `spot` a 1× za ~1 s; klient hejno vyrobí ze seedu a domova a létá sám |
| včely | `Apiary.authority` | bodnutí (`_sting`) jen s autoritou, včely a mravenci jsou čistě klientský efekt |
| kůň | `Horse.authority`, `net_owner`, `net_state()` / `apply_net_state(s, now_s)`, `validate_remote(s, dt)` | autoritu má klient jezdce; server kontroluje rychlost (≤ cval × `REMOTE_SPEED_K` 1,25) a skok polohy (> `REMOTE_TELEPORT` 20 m) |

Metody se jmenují `net_state` / `apply_net_state`, protože `Horse.state` je už proměnná.

### Jak to napojit na `net.gd` (návrh)
| Data | Směr | Frekvence | Kanál |
|---|---|---|---|
| `Fauna.snapshot_for(hráč)` (`pack_snapshot`) | server → klient | 10 Hz | unreliable (ztracený snímek nevadí) |
| `Fauna.flock_snapshot` | server → klient | při změně + 1 Hz | reliable (řídké, malé) |
| `Clock.state()` + `Weather.state()` | server → všichni | každé ~2 s a hned po změně (menu F2, změna `kind`) | reliable |
| blesk `Weather.lightning` → `remote_lightning(pos)` | server → všichni | při události | reliable |
| `Horse.net_state()` | klient jezdce → server → ostatní | 20 Hz | unreliable; server volá `validate_remote`, při zamítnutí pošle jezdci opravu polohy |
| sražení zvířete, útok divočáka, bodnutí včely | jen server | – | výsledek jde klientovi jako událost (`emit_game_event`) |

Oblast zájmu je 400 m (`Fauna.INTEREST_R`; hejna 500 m). Klient nepočítá AI zvěře, hejna jen letí ze seedu. Na klientovi
`Fauna.setup_client` nahradí `Fauna.setup` (bez mapy stanovišť a bez vlastní zvěře).

### LOD s více hráči
`Animal._update_lod` bere `World.nearest_player_dist`, které prochází všechny `world.players` – zvíře je tedy FULL (fyzika, AI ×4/s,
IK chodidel, kolize), kdykoli je do 110 m od kteréhokoli hráče, NEAR do 260 m, jinak FAR (1× za 1,5 s bez kolizí). Totéž platí pro
hejna (`BirdFlock` simuluje do 450 m od nejbližšího hráče) a `Fauna._encounter_for` běží pro každého hráče zvlášť.
Loutka na klientovi používá stejné pravidlo vůči lokálním hráčům klienta.

### Odhad zátěže (4 hráči v různých koutech katastru, ~10 km²)
- Trvalá populace z `POPULATION`: 13 skupin srnců (1–4 ks, v zimě +1–4) + 5 skupin divočáků (3–8 ks, od března do srpna +3–6 selat)
  + 18 zajíců ≈ **100–115 zvířat** (v zimě ~ +30 srnců), hustota ~11 ks/km².
- Kruh FULL má 0,038 km², tedy z trvalé populace 0,4 zvířete na hráče. Skutečně jich je víc, protože `_encounter_for` hráči zajistí
  aspoň `ENCOUNTER_NEAR` (2) živá zvířata do `ENCOUNTER_R` (220 m), nejvýš `TRANSIENT_MAX` (10) vygenerovaných skupin celkem
  (~2,5 ks na skupinu). **Typicky 1–4 zvířata ve FULL na hráče, ~4–16 celkem; nejhorší případ** (rodina divočáků 8 + 6 selat u jednoho
  hráče) ~15 na hráče, ~40 při čtyřech. NEAR (110–260 m) zhruba čtyřnásobek.
- Ve snímku (400 m, 0,5 km²) je ~5–12 zvířat na hráče (plus do 25 z vygenerovaných skupin). Zploštěný záznam má 36 B, jako Array
  celých čísel ~80 B, tedy **~0,4 kB (packed) až ~1 kB (Array) na snímek, 4–10 kB/s na hráče při 10 Hz**; čtyři hráči ~16–40 kB/s
  směrem od serveru (horní odhad při plném překrytí oblastí). Skutečná čísla vypíše `--naturesynctest`.
- Server nese FULL fyziku všech zvířat u všech hráčů (~15–40 `move_and_slide` + 4× za s AI), klient jen interpolaci a animaci.

### Zbývá po síťovém základu
- Skutečné RPC podle tabulky výše, propojení `Fauna.setup_client` do `LocalClient` (dnes `World.build` staví celou přírodu i na klientu)
  a vypnutí lokálních rozhodnutí (`Weather.authority`, `Fauna.authority`, `BirdFlock.authority`, `Apiary.authority` na klientu).
- Zátěžový test: 4 hráči v různých koutech katastru, počet zvířat ve FULL, provoz v kB/s, čas serveru na snímek.
- Druhý jezdec za sedlem, nasedání na koně jiného hráče přes autoritu (přepnutí `Horse.authority` / `net_owner` při nasednutí a sesednutí),
  zvuky a stopy koně jiného hráče na klientu.
- Loutky si nepřenášejí barevný odstín (`tint` se odvozuje z `net_id`), individuální bidýlka ptáků se přibližují kolem `spot` serveru.
