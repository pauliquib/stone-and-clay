# Stone & Clay – game map version (MVP)

An open-world MVP in **Godot 4.3**, built on a map of the whole cadastral area of the village of Dukelčice
(`mapa_okoli.blend` – DMR 5G terrain, buildings with heights from DMP 1G, roads from OSM, ~21,800 trees;
the terrain colour is procedural, the ČÚZK orthophoto is only available as a toggle).

> *“This game is a satirical work of art. All characters, events and depicted private objects are fictional.
> Any resemblance to real persons or specific dwellings is purely coincidental.”*

*Public snapshot — development happens in a private repository; the commit history is squashed here.*

## Screenshots

| Aerial view of Dukelčice (drone) | Dialogue with an NPC on the village green |
|---|---|
| ![Aerial view](docs/screenshots/dron-ves.png) | ![Dialogue with an NPC](docs/screenshots/dialog-kvetoslava.png) |

| Javor 250 Kývačka motorbike at dusk | Distillery interior |
|---|---|
| ![Javor 250](docs/screenshots/javor-kyvacka.png) | ![Distillery](docs/screenshots/palenice.png) |

| Radio with stations |
|---|
| ![Radio](docs/screenshots/radio.png) |

## Running

```bash
./run.sh            # or: godot --path stone-and-clay
```

The first launch imports the textures (~30 s). Loading the world takes ~2 s.

## About the game

**Dukelčice** is an open-world life simulator set in a Czech village, on a faithful 3D map of a real
cadastre. The player moves freely on foot, by car, on horseback and in the air (drone, aeroplane,
paraglider, microlight). They complete small village tasks and live with the consequences: alcohol in the
blood, police checks, a damaged car. Under a simple, kindly humorous surface runs a believable simulation:
physiology, weather and seasons, traffic and police, economy, work, wildlife and hunting, farming,
gardening and dozens of other systems.

Vision, pillars and game loop: [`GAME_DESIGN.md`](GAME_DESIGN.md).
Full technical breakdown of all implemented systems: [`docs/SYSTEMS.md`](docs/SYSTEMS.md).

## Controls

| Key | On foot | In a car |
|---|---|---|
| WASD / arrows | walk | W throttle, S brake / reverse, A/D steer |
| Mouse | look around (click into the window) | look around with the camera |
| Shift | sprint (stamina) | – |
| Space | jump (hold for higher) | handbrake |
| Ctrl / C | crouch; slide while sprinting | – |
| V | 1st ↔ 3rd person | camera behind the car ↔ from inside |
| Mouse wheel | camera distance | – |
| E | interact (places, doors, NPCs, sleeping…) | – |
| T / Enter | say something out loud (the nearest or addressed character replies) | also |
| F5 / F9 | quick save / load position | also |
| F | get into a car / onto a bike, motorbike, horse | get out / dismount |
| L / B / N / R | – | lights / horn / wipers / flip the vehicle |
| G | pick up / load cargo, or whistle for the horse | – |
| X (hold) | binoculars | – |
| Q, 1–5 | choose / switch the tool in hand | – |
| LMB | context action (collect, fish, shoot…) | – |
| RMB (hold) | aim the weapon in hand | – |
| Tab / I / J / K / M / H | inventory / clothing / quest log / skills / map / home | |
| U | get unstuck | – |
| F1 / Esc / F2 | help / pause and settings / game menu (time, weather, teleport…) | |

A game controller works too. Controls for the horse, drone, aeroplane, paraglider and microlight
(start-up procedures, landing, licences) are in [`docs/CONTROLS.md`](docs/CONTROLS.md).

## Documentation

- [`GAME_DESIGN.md`](GAME_DESIGN.md) – vision, pillars, game loop, target parameters
- [`docs/SYSTEMS.md`](docs/SYSTEMS.md) – full technical breakdown of all game systems (physiology, economy, law, wildlife, work, aviation…)
- [`docs/CONTROLS.md`](docs/CONTROLS.md) – controls for the horse, drone, aeroplane, paraglider, trike
- [`docs/DEV.md`](docs/DEV.md) – how the game map is made from geodata, debug/test launch parameters, code architecture (preparation for multiplayer)

### Guides

- [`BLENDER_UPRAVY.md`](BLENDER_UPRAVY.md) – manual map edits in Blender (buildings, roads, trees, terrain, textures) and export to the game
- [`VLASTNI_VOZIDLA.md`](VLASTNI_VOZIDLA.md) – new cars (procedural or from your own `.glb` model), wheels and motorbikes
- [`ASSETS.md`](ASSETS.md) – legal assets from the internet: where to look, licence checklist, import, the `assets/LICENSES.md` register, `tools/assets_check.py`
- [`ZVIRATA.md`](ZVIRATA.md) – editing animals, birds, weather and seasons (tables, preview with `zoo.gd`)

## Data licences

Geodata © ČÚZK (CC BY 4.0), OSM © OpenStreetMap contributors (ODbL), textures and HDRIs Poly Haven (CC0).
The ČÚZK orthophoto is not used by default (only via F2 → Terrain; the files `textures/ortho_*.jpg` are kept for now).
All external assets (models, textures, sounds, music) are listed in the register `assets/LICENSES.md` + `assets/licenses.json`.
`python3 tools/assets_check.py` flags unregistered files and disallowed licences, and generates `data/credits.json`
(CC BY credits are shown in the F1 help). Loading in code: `AssetLib.load_model / load_sound / has` (`scripts/asset_lib.gd`).

## Legal principles for content

A summary from [`PRAVNI_DOPORUCENI.md`](PRAVNI_DOPORUCENI.md) (in Czech) – it applies to all new content:

- **Data sources:** only ČÚZK (DMR/DMP, orthophoto – CC BY 4.0) and OSM (ODbL). Nothing from Google Maps / Earth /
  Street View or Bing. Sources are listed in `data/map.json` (`license`), on the splash screen and in the F1 help
  (`Hud.CREDITS`).
- **No real identifiers:** all house numbers in the game are fictional (`Estate` – numbered from the village green using a seed,
  nothing from RÚIAN / ČÚZK; the real number of the player's original house is never shown). Number plates have a generic look
  with no municipality sign, there are no names on mailboxes and bells, and no views into private yards or windows. Number plates
  are generated with the letter Q, which Czech plates do not use (`Traffic.plate()`).
- **Characters:** only fictional names, no likenesses and no hints at real residents of the village. Villagers have invented,
  rather humorous names and generic jobs; new names must not match real residents, and texts must not mention real neighbouring
  villages, companies or authorities.
- **Brands:** instead of trademarks, fictional or parody names are used (cars Oktávka / Fábička / Stodvacka, the Javor motorbike,
  the Favorín bike, Bylinkovka, Hořká; fictional businesses Hospoda U Hřiště, Pálenice U Kotla…).
- **Municipal symbols:** the village coat of arms and flag are not used in the game.
- **Radio:** the game's own stations are fictional and the music is generated. The internet stations in `data/radia.json`
  are only links to public Czech Radio streams, which the game plays for the player like an ordinary internet radio
  (it neither records nor redistributes anything, and there are no logos). Station names are trademarks of their operator – before
  publishing the game widely, empty `radia.json` or get permission.
- **Disclaimer:** the splash screen, the F1 help and the start of this README (`Hud.DISCLAIMER`).
