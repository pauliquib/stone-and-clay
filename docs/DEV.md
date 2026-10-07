# Vývojářská dokumentace

> Generování herní mapy z geodat, ladicí/testovací parametry spouštění a architektura kódu (příprava na multiplayer).
> Přehled funkcí hry je v [`SYSTEMS.md`](SYSTEMS.md), vize a design v [`GAME_DESIGN.md`](../GAME_DESIGN.md).

## Jak vzniká herní mapa

```
blend/mapa_okoli.blend
   │  tools/domov_hrace.py      – dům hráče stejnou metodou jako ostatní budovy (půdorys OSM/RÚIAN,
   │                           tvar a výška střechy fitem na DMP 1G, barva střechy z ortofota)
   ▼  tools/export_map.py    – (Blender, headless)
blend/mapa.blend   herní verze mapy: model domu odebrán, jednoduchý dům hráče přidán,
                                terén pod bývalým modelem vrácen na DMR 5G
data/*.bin, data/map.json       geometrie a metadata pro Godot
textures/                       PBR textury (Poly Haven) + ortofoto (jen pro porovnání, ve hře se ve výchozím stavu nepoužívá)
```

Pipeline, která `blend/mapa_okoli.blend` vytvořila z otevřených dat (ČÚZK, OSM, Poly Haven),
je součástí repozitáře: skripty v `pipeline/scripts/` (`run_all.sh` spustí fáze 1–13 headless),
mezidata v `pipeline/data/`, stažené PBR textury/HDRI v `pipeline/assets/`, kontrolní rendery
a logy v `pipeline/renders/` a `pipeline/logs/`. Velká geodata ČÚZK (rastry DMR/DMP, ortofoto,
OSM .pbf) leží v `geodata/` – všechny tyto velké adresáře jsou mimo git. Vstupní model domu
`blend/Doubravy_3D.blend` (~726 MB) se do repa nedává.

Regenerace dat (z kořene repozitáře):

```bash
python3 tools/domov_hrace.py
blender --background --python-exit-code 1 --python tools/export_map.py
rm -rf data/orig && python3 tools/clean_road_clashes.py
python3 tools/pois.py
python3 tools/water.py      # vždy až po exportu – čte terrain_height.bin, silnice a trees.bin
python3 tools/vegetation.py # po exportu i water.py – čte surface/landuse/trees.bin, výškovou mřížku
                            # + water_carve.bin, vozovky a map.json → data/vegetation.bin (není v gitu)
```

`water.py` čte vodní toky z `geodata/pbf/zlinsky-latest.osm.pbf` (pyosmium) a zapisuje `data/water.json`
(osy toků s hladinou, nádrže, stromy stojící ve vodě) a `data/water_carve.bin` (DBW1: změněné body výškové
mřížky – index, nová výška, normála RGB8; `Terrain` je aplikuje při načtení na vzhled i kolizi). Původní
`terrain_*.bin` zůstávají beze změny.

`clean_road_clashes.py` vyřadí chybně umístěné budovy a stromy, které stojí ve vozovce (síť silnic
sedí na ortofotu, tyto objekty ne); originály nechá v `data/orig/`. Navíc (vlna 0d) měří budovy proti
**ose** silnic z `data/map.json`: dům, jehož půdorys zasahuje ≥ 1 m² do pásu `AXIS_BUF` (residential /
unclassified 2,0 m, secondary / tertiary 2,6 m, service jen 0,75 m bez posledních 4 m – vjezdy), se vyřadí;
místa (`poi`) a dům hráče se jen vypíšou. Stromy blíž ose než `TREE_AXIS_BUF` taky. Výpis „blízko osy
(ponechána)“ = budovy pod prahem k ruční kontrole. Vyřazené záznamy zmizí i z `data/buildings.json`
(id vypíše – doplnit do `EXCLUDE` v `tools/buildings.py`). Ruční úpravy v Blenderu
patří do kolekcí `HRA_*` (viz `BLENDER_UPRAVY.md`), exportér je přidá.

### Rozšíření detailní mapy na okolní obce (union mřížka)

Detailní terén pokrývá ~11,3 × 7,5 km (mřížka 5675 × 3772 bodů, krok 2 m) přes katastr
Dukelčic i katastry všech 5 okolních obcí. Stará mřížka 2626 × 2302 zůstává bajtově
zachována jako blok v nové mřížce (offset col +1381, row +768 – fázově sladěná 2 m buňka),
nové území se generuje čistě v Pythonu (bez Blenderu) ze stejných zdrojů:

```bash
python3 tools/fetch_geodata_union.py    # ČÚZK DMR5G/DMP1G + ortofoto pro union bbox (download;
                                        # po pásech ~2048 px – reálný limit ImageServeru ~8 Mpx)
python3 tools/fetch_osm_union.py        # OSM extrakt union bbox z geodata/pbf (offline, pyosmium;
                                        # + place_names z celého kraji pro hygienický filtr názvů)
python3 tools/expand_map.py             # terrain_*.bin, trees.bin (staré instance verbatim),
                                        # map.json (roads z union extraktu), ortho_full.jpg
python3 tools/expand_buildings.py       # += walls/roofs/asphalt/gravel.bin (budovy + silniční
                                        #   pásy mimo katastr; dedup osm_id + překryv půdorysu)
python3 tools/water.py                  # přegenerovat – čte novou mřížku z map.json
python3 tools/landuse.py                #   „ (rastry 4 m zarovnané na union mřížku)
python3 tools/surface.py                #   „
python3 tools/surroundings.py           #   „ (preferuje geodata_meta_union.json + dtm_union_scene.npy;
                                        #     --no-download pro offline přegenerování masky)
python3 tools/vegetation.py             # body vegetace (zůstávají uvnitř katastru z map.json boundary)
python3 tools/clean_road_clashes.py     # budovy/stromy ve vozovce i na novém území
```

Fetch nástroje jsou idempotentní (přepisují `geodata/*_union_*` a `pipeline/data/*union*`);
`expand_map.py`/`expand_buildings.py` si před přepsáním udělají snapshot do
`pipeline/data/pre_expand/` resp. `pre_b3/` a reportují švy/překryvy. Dekorativní zástavba
`Villages` se pro obec s katastrem celým uvnitř detailní mřížky přeskakuje
(`stats[id].skipped`) – zástavbu tam drží fyzické budovy exportu; obce mimo detail se
kreslí jako dosud.

Krajina za okrajem detailního terénu (M6.2, pro pohled z výšky – dron, později paraglide):
`tools/surroundings.py` stáhne z ČÚZK DMR 5G (ImageServer, stejný zdroj jako mapa – © ČÚZK CC BY 4.0)
nízkorozlišenou výškovou mřížku okolí (obdélník z `map.json` height – po rozšíření ~11,3 × 7,5 km –
+ ~2,5 km na každou stranu, krok 25 m → ~16 × 12 km) → `data/surround_height.bin` a z OSM
(`geodata/pbf/zlinsky-latest.osm.pbf`) hrubou masku povrchu (les / pole / louka / zástavba / voda)
→ `data/surround_surface.bin`. Oba .bin nejsou v gitu.

```bash
python3 tools/surroundings.py               # stáhne DMR ČÚZK + maska z OSM
python3 tools/surroundings.py --no-download # jen přegenerovat masku / navázání
```

Kreslí je `scripts/surroundings.gd` (`Surroundings`, uzel „Okoli“ ve World): LOD dlaždice ~2 km,
výšky ve vertex shaderu (`shaders/surroundings.gdshader`), paleta tříd jako `terrain.gdshader`,
oblast katastru zapuštěná pod detailní terén (žádný šev), les jako tmavší povrch + MultiMesh kuželů
do 4 km, bez kolizí a stínů. Bez dat vznikne plochá zvlněná krajina ve výšce okraje (fallback).

Okolní obce: `python3 tools/obce.py` čte z OSM
(`geodata/pbf/zlinsky-latest.osm.pbf`) 5 katastrů v okolí domova – hranice polygonu, půdorysy
budov, silnice, vodní a lesní plochy → `data/obce.json` (v gitu; názvy obcí jsou fiktivní –
PRAVNI_DOPORUCENI.md). Dekorativní 3D zástavbu z ní staví `scripts/villages.gd` (`Villages`,
uzel „Vesnice“ ve World po `surroundings.setup`) jen pro obec **mimo** detailní mřížku:
půdorysy tažené do zdí se sedlovou/valbovou střechou, MeshInstance3D bez kolizí a stínů.
Po rozšíření mapy (union) leží všech 5 obcí v detailu → jejich fyzická zástavba pochází
z `walls/roofs.bin` a vrstva Villages je přeskočená (`stats[id].skipped`; viz výše).
`World.obce` drží pole dat pro mapu (popisky, hranice a silnice obcí kreslí HUD na mapě M;
rozsah pohledu = katastr + obce) a `World.obec_at(pos)` vrátí obec, v jejímž katastru bod
leží (test v polygonu hranice; radius je jen ekvivalentní plocha, při překryvech vítězí
nejbližší střed; mimo katastry `{}`). Katastry obcí se počítají i do zón „v obci“ –
limit 50 km/h, svědci a hlídka policie (`Traffic.in_village`). Bez souboru jen warning
a hra běží dál.

Formáty: `terrain_height.bin` (float32, řádky od severu, 2 m), `terrain_collision.bin`
(výšky / 2 pro HeightMapShape3D škálovaný ×2), `terrain_normal.bin` (RGB8),
`walls/roofs/asphalt/gravel.bin` (DBM1: trojúhelníky po dlaždicích 256 m – pozice,
normála, barva `tint`), `tree_protos.bin` (DBT1), `trees.bin` (DBI1: x, y, z, rotY,
sx, výška, sz, barva, prototyp). Souřadnice Godotu: X = x, Y = z, Z = −y scény Blenderu.

## Ladicí parametry

`godot --path . -- --shot=snimek.png [--view=fp] [--pos=x,z] [--yaw=°] [--pitch=°] [--zoom=m] [--time=h] [--top=m] [--map] [--novsync]`
(`--vsync=off|fifo` jiný režim vsync – výchozí je mailbox, `--maxfps=n` strop snímků/s; `run.sh` na Waylandu
spouští nativní Wayland místo XWayland – kvůli zasekávání obrazu při nehybné myši, vypnout `DUKELČICE_X11=1`)
uloží snímek a skončí (`--top=70` = pohled shora na čtverec 70 m, střed `--pos`); `--testmove` projede
chůzi/sprint/skok/skluz, `--bottest` pohyb botů, `--drinktest` křivky promile, `--cartest [--aionly]`
zrychlení/brzdění a AI jízdu hospoda → domov, `--exittest` výstup z auta (poloha, zdraví, stav auta),
`--drive[=id]` start ve vozidle (`kolo`, `jawa` nebo libovolný model z `CarModel.MODELS`), `--questtest [--stopshot=x.png]` všech 6 úkolů
(selhání i splnění přes skutečné nabídky a jízdu), `--traffictest [--dur=s]` provoz – hlásí auta, která visí,
`--faunatest [--shotdir=adr]` zvěř (pastva → útěk) a jízda na koni, `--naturesynctest` loopback přípravy přírody
na multiplayer (snímky zvěře a hejn do klientské Fauny, odchylky poloh, velikost snímku, Clock / Weather round-trip; 60 s, pak skončí),
`--weathertest` přilnavost a brzdná
dráha auta za všech situací + expozice těla. Testy upgrade plánu (`docs/UPGRADE_PLAN.md`,
vše v `scripts/tests.gd`): `--interiortest` mapový interiér hospody přes FuncGodot (vstup/výstup,
fallback na procedurální), `--villagertest` behavior strom vesničana přes LimboAI (blackboard,
větve denní rutiny, chůze za cílem), `--flighttest` stavový automat letouna přes
godot-state-charts (vzlet z dráhy, přetažení/zotavení, dosazení), `--fencetest` kolize plotů
a průchod brankou (i koněm), `--gardentest` růst plodin, kompost → hnůj → hnojení, studna
a skleník + save klíč `garden_visuals`, `--vegetationtest` `vegetation.bin` (VEG1), chunky
MultiMeshů a LOD, `--terraintest` mikroreliéf vs. kolize, wetness → shader a louže,
`--obcetest [--shot=obce.png]` okolní obce (5 fiktivních, `World.obce`, `obec_at`,
`Villages.stats`; `--shot` uloží snímek hlavní mapy oddálené na celé okolí s popisky).
`--date=RRRR-MM-DD` datum 1. dne,
`--weather=druh` vynucené počasí (`jasno`, `polojasno`, `oblacno`, `zatazeno`, `mlha`, `prehanky`, `dest`,
`bourka`, `snih`). Náhled modelů zvířat: `godot --path . --script res://tools/dev/zoo.gd -- --series=adresář`.

**M8.1 – měřicí scény a eko-takt:** `--perfscene=<jméno>[,sekund]` (`Tests.PERF_SCENES`: `ves_poledne`,
`les_rano_mlha`, `louka_vitr`, `udoli_noc`, `pole_leto`, `dron_200m`) teleportuje na pevné místo s pevným
časem/počasím/kamerou a změří výkon stejně jako `--perf` (výchozí 20 s) → souhrn na konzoli +
`user://perf/<jméno>.csv`. Každý krok M8 smí do `PERF_SCENES` přidat vlastní scénu. `World.eco_hour(dt_h)` /
`World.eco_day(jd)` (`World.eco` = `EcoClock`, `scripts/eko/eco_clock.gd`) je jediný zdroj hodinového/denního
kroku pro simulace M8 – nový krok se připojí přes `World.eco_hour.connect(...)`, nepočítá si vlastní „jednou
za hodinu“ v `_process`. `World.realism` (= `GameSettings.realism`, Esc → Nastavení → „Realismus (M8)“)
přepíná jednotlivé kroky M8 za běhu; klíče a kontrakt API mezi kroky M8 jsou v
`prompts/roadmapa/M8_realismus/00_PRINCIPY.md` kap. 3 a 5. Ladicí vrstvy mapy (F2 → „Příroda – ladění“,
`World.debug_layers`) kreslí stav modelu (stanoviště, vlhkost, teplota, vítr, druhy…) jako barevnou mřížku
na mapě M, bez debuggeru.

**Launcher pro ruční testování / měření (`tools/launcher.sh`, M8.1):** `tools/launcher.sh [parametry hry…]`
spustí `./run.sh` s danými parametry (např. `--perfscene=ves_poledne`), zachytí stdout/stderr a zapíše
kompaktní log do `logs/m8_perf_<datum_čas>.log` (+ `logs/latest.log`, oba mimo git) – tři oddíly (PERF
souhrn, chyby/varování, ostatní výstup), opakující se hlášky deduplikované („N× stejná hláška“). Hodí se,
když uživatel po hraní/měření jen pošle soubor z `logs/`, místo ručního přepisování čísel z konzole.
`tools/launcher.sh --help` vypíše nápovědu bez spouštění hry.

Letové hranice (M6.2, platí pro dron a budoucí letouny M6.3+ – napojení přes `World.flight_bounds(pos)`
→ `{ok, warn, push, out, agl}`): strop `World.FLY_CEIL_AGL` = 1 500 m nad terénem (měkké odepření –
tlačí dolů), vodorovná hranice `World.FLY_LIMIT_M` = 2 km za obdélníkem detailního terénu – v pásmu
`World.FLY_WARN_M` (400 m) před ní měkké odpuzení protivětrem (`World.FLY_PUSH_MS`) a varování
„Dál už nelétej – opouštíš oblast“, za hranicí návrat domů. Chodce a auta drží stále neviditelné
zdi `Terrain._add_bounds`. Kontrola okolí z výšky: F2 → Teleport → Ladění → „Volná kamera ~500 m
nad hráčem“ (WASD let, myš pohled, Mezerník/Ctrl výška, Shift rychle, V zpět). Mlha se nad ~150 m
AGL ředí (`Atmosphere`) a dohled dalekých stromů se násobí (`MapLoader.set_tree_far_mult`).

Data polí: `python3 tools/landuse.py` (OSM z `geodata/pbf/zlinsky-latest.osm.pbf`, potřebuje `osmium`, `numpy`,
`Pillow`) vytvoří `data/landuse.bin`. Krok 03 (pole, sezónní předměty, události) ladí tabulky `Fields.CROPS`,
`World.SEASON_ITEMS`, `VillageEvents.EVENTS`, `Place.WEEK_HOURS`; datum se přepíná v F2 → Datum.

Terén bez ortofota (M1.1): barvu terénu skládá `shaders/terrain.gdshader` z tříd povrchu (tráva, orná půda, sad,
les, dvůr, břeh, skála podle sklonu, polní cesta) s prolínáním hranic a sezónou (`grass_green`, sníh, mokro, pole
z `landuse.bin`). Maska povrchu: `python3 tools/surface.py` (stejné závislosti jako `landuse.py`) vytvoří `data/surface.bin`
(magic `SURF`, rastr 4 m, 1 B na buňku; laditelné konstanty `FOREST_MIN`, `BUILDING_R`, `WATER_R`, `TRACK_W`). Bez něj shader
odvodí třídy z `landuse.bin` a hustoty lesa. Dlaždicové textury (Poly Haven, CC0, 1k) patří do `assets/textures/terrain/`,
seznam je v `ASSETY.md`; když chybí, použije se procedurální barva a šum. Minimapa (M) se kreslí z tříd povrchu
(`SurfaceMap.make_map_image`). F2 → „Terén: …“ přepne na ortofoto a zpět. `export_map.py` přidává do vizuální
výškové mřížky mikroreliéf (erozní šum ±0,2 m; kolizní mřížka zůstává čisté DMR – projeví se až po dalším
exportu mapy). Za mokro v shaderu jsou navíc polní cesty a koleje s wet-boost reflexí (sdílený `wet_boost`
s `tinted_triplanar.gdshader` na vozovkách) a sněhové jazyky po severních svazích; louže kreslí
`scripts/priroda/puddles.gd` (Decal) při `wetness > 0,7`.

Fasády (M1.2): `python3 tools/buildings.py` (jen standardní knihovna) sloučí podklady `data/buildings_3d*.json` (půdorys OSM,
výšky okapu a hřebene z DMP 1G, tvar střechy), `tools/out/domov_hrace.json` a `data/pois.json` do `data/buildings.json`
(typ budovy, plocha, hřeben, `poi`, `home`, bod dveří u nejbližší silnice). Generátor `scripts/building_details.gd`
z něj skládá okna, dveře, vrata a komíny; sklo řeší `shaders/window_glass.gdshader` (jeden uniform `lit_frac` pro noční svícení).

Add-ony (`addons/`, licence v `THIRD_PARTY.md`): Godot Jolt (GDExtension, fyzika místo Godot Physics),
FuncGodot (editor plugin – staví interiéry z Quake `.map` v `data/maps/`; `scripts/map_interiors.gd`,
chybí-li mapa/addon → fallback na procedurální `InteriorGen`), LimboAI (GDExtension – behavior strom
`ai/villager_routine.tres` + GDScript tasky `scripts/ai/{actions,conditions}/` připnuté k `Villager`),
godot-state-charts (editor plugin – stavový automat letouna v `aircraft.gd`). Jejich generované soubory
jsou v gitu a přegenerovávají se ručně: `python3 tools/gen_hospoda_map.py` → `data/maps/hospoda.map`
(hospoda 10 × 8 m, editovatelná i v TrenchBroomu), `python3 tools/gen_interior_textures.py` →
`assets/textures/interiors/*.png` (Pillow), `godot --headless --path . --script tools/gen_villager_bt.gd`
→ `ai/villager_routine.tres`, `godot --headless --path . --script tools/gen_vegetation_meshes.gd` →
`assets/models/vegetation/*.res` (low-poly, UV.y = poměrná výška pro ohýbání větrem).

Vegetace (Fáze 9): `python3 tools/vegetation.py [--year=RRRR]` rozmístí deterministicky (SEED) body
vegetace z `surface.bin`, `landuse.bin` (obilné řádky jen na polích, jejichž `Fields.crop_of` dává
obilninu pro daný rok), `trees.bin` (podrost pod koruny), výškové mřížky + `water_carve.bin`, masek
vozovek a obvodu z `map.json` → `data/vegetation.bin` (VEG1, typ/pozice/rotace/měřítko/tint/pole;
soubor není v gitu – spustit ručně, při změně roku znovu). Kreslí `scripts/vegetation/vegetation_manager.gd`:
MultiMesh chunky s LOD podle vzdálenosti, `wind_strength` z `Weather` → `shaders/vegetation.gdshader`,
`detail=0` vegetaci skryje.

Poznámka: po přidání skriptu s novým `class_name` je třeba obnovit seznam tříd
(`godot --headless --path . --import`, dělá to i `run.sh`), jinak Godot hlásí „Could not find type …“.
Testy spuštěné přímo přes `godot` bez okna (`--headless`) vypisují při pití/jídle `Parameter "m" is null`
(bez rendereru) – na výsledek to nemá vliv.

Laditelné konstanty hráče a řemesel (bez spouštění): třes obrazu `Player.SHAKE_*`, závislost a chuť na cigaretu
`BodyState.ADDICTION_*` / `CRAVING_*`, modifikátory rychlosti `Player.speed_mods` (`set_speed_mod` / `clear_speed_mod`;
zdroje `Cargo.MOD_OWN`, `Cargo.MOD_CART`, `Hunting.MOD_CARRY`, `Quests` Krmivo). Cigarety se prodávají jen v Potravinách.

## Architektura (příprava na multiplayer)

| Skript | Za co odpovídá |
|---|---|
| `main.gd` | tenký start: vytvoří `World` a `LocalClient`, přidá hráče id 1, spustí ladicí parametry / testy |
| `world.gd` (`World`) | simulace – v MP server: terén, mapa, čas, `players` (id → Player), `quests` (id → Quests), boti, místa, doprava, policie, předměty, ekonomika a pravidla (nehody, zadržení, okno, spánek); akce hráčů jako metody s id (`enter_car`, `buy`, `sleep`, `player_action`…) |
| `local_client.gd` (`LocalClient`) | lokální hráč: vstup → `InputState`, klávesy E/F/L/B/R/H → akce `World`, HUD a nabídky míst, kamera, `DrunkFx`, zvuky, obloha/světlo, značka cíle, snímky |
| `input_state.gd` (`InputState`) | vstup jednoho hráče (pohyb, řízení, pohled, skok, sprint, přikrčení) – čte ho `Player` i `Car`; v MP se bude plnit ze sítě |
| `quests.gd` | úkoly **jednoho** hráče (každý hráč vlastní uzel a instance úkolů) |
| `police.gd` | pronásleduje / kontroluje konkrétního hráče; zákaz řízení a pátrání má každý hráč (`Player.license_suspended_until`, `wanted_until`) |
| `traffic.gd` | auto každého hráče (`car_of(id)`), AI auta se rozmisťují kolem hráčů |
| `villager.gd`, `dog.gd`, `npc.gd` | reagují na nejbližšího hráče (`World.nearest_player`) |
| `characters.gd`, `persona.gd`, `dialog.gd` | smyšlené postavy, jejich paměť vůči hráčům, odpovědi na volný text (`World.player_say`, `dialog_context`) |
| `reputation.gd` | pověst **jednoho** hráče (`World.reputations[id]`), vyhodnocuje události z `emit_game_event` |
| `save_game.gd` | uložení / načtení pozice do běžícího světa (singleplayer) |

Svět posílá hráči zprávy jen přes `World.notify(id, metoda_hud, …)`, `play_sfx(id, …)`, signál `sound`
(zvuk v místě) a `emit_game_event(id, druh, data)` (úkoly hráče + prezentace u jeho klienta) – tato
místa se v úkolu 03 nahradí RPC.

