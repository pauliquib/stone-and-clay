# Vývojářská dokumentace

> Generování herní mapy z geodat, ladicí/testovací parametry spouštění a architektura kódu (příprava na multiplayer).
> Přehled funkcí hry je v [`SYSTEMS.md`](SYSTEMS.md), vize a design v [`GAME_DESIGN.md`](../GAME_DESIGN.md).

## Jak vzniká herní mapa

```
mapa_okoli.blend
   │  tools/domov_hrace.py      – dům hráče stejnou metodou jako ostatní budovy (půdorys OSM/RÚIAN,
   │                           tvar a výška střechy fitem na DMP 1G, barva střechy z ortofota)
   ▼  tools/export_map.py    – (Blender, headless)
blend/mapa.blend   herní verze mapy: model domu odebrán, jednoduchý dům hráče přidán,
                                terén pod bývalým modelem vrácen na DMR 5G
data/*.bin, data/map.json       geometrie a metadata pro Godot
textures/                       PBR textury (Poly Haven) + ortofoto (jen pro porovnání, ve hře se ve výchozím stavu nepoužívá)
```

Regenerace dat (z kořene repozitáře):

```bash
python3 tools/domov_hrace.py
blender --background --python-exit-code 1 --python tools/export_map.py
rm -rf data/orig && python3 tools/clean_road_clashes.py
python3 tools/pois.py
python3 tools/water.py      # vždy až po exportu – čte terrain_height.bin, silnice a trees.bin
```

`water.py` čte vodní toky z `geodata/pbf/zlinsky-latest.osm.pbf` (pyosmium) a zapisuje `data/water.json`
(osy toků s hladinou, nádrže, stromy stojící ve vodě) a `data/water_carve.bin` (DBW1: změněné body výškové
mřížky – index, nová výška, normála RGB8; `Terrain` je aplikuje při načtení na vzhled i kolizi). Původní
`terrain_*.bin` zůstávají beze změny.

`clean_road_clashes.py` vyřadí chybně umístěné budovy a stromy, které stojí ve vozovce (síť silnic
sedí na ortofotu, tyto objekty ne); originály nechá v `data/orig/`. Ruční úpravy v Blenderu
patří do kolekcí `HRA_*` (viz `BLENDER_UPRAVY.md`), exportér je přidá.

Krajina za okrajem katastru (M6.2, pro pohled z výšky – dron, později paraglide): `tools/surroundings.py`
stáhne z ČÚZK DMR 5G (ImageServer, stejný zdroj jako mapa – © ČÚZK CC BY 4.0) nízkorozlišenou výškovou
mřížku okolí (katastr + ~2,5 km na každou stranu, krok 25 m) → `data/surround_height.bin` a z OSM
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
dráha auta za všech situací + expozice těla. `--date=RRRR-MM-DD` datum 1. dne,
`--weather=druh` vynucené počasí (`jasno`, `polojasno`, `oblacno`, `zatazeno`, `mlha`, `prehanky`, `dest`,
`bourka`, `snih`). Náhled modelů zvířat: `godot --path . --script res://tools/dev/zoo.gd -- --series=adresář`.

Letové hranice (M6.2, platí pro dron a budoucí letouny M6.3+ – napojení přes `World.flight_bounds(pos)`
→ `{ok, warn, push, out, agl}`): strop `World.FLY_CEIL_AGL` = 1 500 m nad terénem (měkké odepření –
tlačí dolů), vodorovná hranice `World.FLY_LIMIT_M` = 2 km za obdélníkem katastru – v pásmu
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
(`SurfaceMap.make_map_image`). F2 → „Terén: …“ přepne na ortofoto a zpět.

Fasády (M1.2): `python3 tools/buildings.py` (jen standardní knihovna) sloučí podklady `data/buildings_3d*.json` (půdorys OSM,
výšky okapu a hřebene z DMP 1G, tvar střechy), `tools/out/domov_hrace.json` a `data/pois.json` do `data/buildings.json`
(typ budovy, plocha, hřeben, `poi`, `home`, bod dveří u nejbližší silnice). Generátor `scripts/building_details.gd`
z něj skládá okna, dveře, vrata a komíny; sklo řeší `shaders/window_glass.gdshader` (jeden uniform `lit_frac` pro noční svícení).

Poznámka: po přidání skriptu s novým `class_name` je třeba obnovit seznam tříd
(`godot --headless --path . --import`, dělá to i `run.sh`), jinak Godot hlásí „Could not find type …“.
Testy spuštěné přímo přes `godot` bez okna (`--headless`) vypisují při pití/jídle `Parameter "m" is null`
(bez rendereru) – na výsledek to nemá vliv.

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

