# Stone & Clay – herní verze mapy (MVP)

Open-world MVP v **Godot 4.3** nad mapou celého katastru obce Dukelčic
(`mapa_okoli.blend` – terén DMR 5G, budovy s výškami z DMP 1G, silnice z OSM, ~21 800 stromů;
barva terénu je procedurální, ortofoto ČÚZK jen na přepnutí).

> *„Tato hra je satirickým uměleckým dílem. Všechny postavy, události a vyobrazené soukromé objekty
> jsou smyšlené. Jakákoliv podobnost se skutečnými osobami či konkrétními obydlími je čistě náhodná.“*

*Veřejný snapshot — vývoj probíhá v privátním repozitáři, historie commitů je zde squashnutá.*

## Screenshoty

| Letecký pohled na Dukelčice (dron) | Dialog s NPC na návsi |
|---|---|
| ![Letecký pohled](docs/screenshots/dron-ves.png) | ![Dialog s NPC](docs/screenshots/dialog-kvetoslava.png) |

| Motorka Javor 250 Kývačka za soumraku | Interiér pálenice |
|---|---|
| ![Javor 250](docs/screenshots/javor-kyvacka.png) | ![Pálenice](docs/screenshots/palenice.png) |

| Rádio se stanicemi |
|---|
| ![Rádio](docs/screenshots/radio.png) |

## Spuštění

```bash
./run.sh            # nebo: godot --path stone-and-clay
```

První spuštění naimportuje textury (~30 s). Načtení světa trvá ~2 s.

## O hře

**Dukelčice** je open-world simulátor života na české vesnici na věrné 3D mapě skutečného
katastru. Hráč se volně pohybuje pěšky, autem, na koni i ve vzduchu (dron, letadlo, paramotor,
motorové rogalo), plní drobné vesnické úkoly a nese si jejich následky – alkohol v krvi, policejní
kontroly, poškozené auto. Pod jednoduchým, laskavě humorným povrchem běží uvěřitelná simulace:
fyziologie, počasí a roční doby, doprava a policie, ekonomika, práce, zvěř a lov, hospodářství,
zahrada a desítky dalších systémů.

Vize, pilíře a herní smyčka: [`GAME_DESIGN.md`](GAME_DESIGN.md).
Úplný technický rozpis všech implementovaných systémů: [`docs/SYSTEMS.md`](docs/SYSTEMS.md).

## Ovládání

| klávesa | pěšky | v autě |
|---|---|---|
| WASD / šipky | chůze | W plyn, S brzda / couvání, A/D řízení |
| myš | rozhlížení (klikni do okna) | rozhlížení kamerou |
| Shift | sprint (výdrž) | – |
| Mezerník | skok (delší stisk = výš) | ruční brzda |
| Ctrl / C | přikrčení, ve sprintu skluz | – |
| V | 1. ↔ 3. osoba | kamera za autem ↔ z interiéru |
| kolečko myši | vzdálenost kamery | – |
| E | interakce (místa, dveře, NPC, nocleh…) | – |
| T / Enter | říct něco nahlas (nejbližší/oslovená postava odpoví) | také |
| F5 / F9 | rychlé uložení / načtení pozice | také |
| F | nastoupit do auta / na kolo, motorku, koně | vystoupit / sesednout |
| L / B / N / R | – | světla / klakson / stěrače / postavit vozidlo |
| G | zvednout/naložit náklad, nebo hvízdnout na koně | – |
| X (držet) | dalekohled | – |
| Q, 1–5 | vybrat / přepnout nástroj v ruce | – |
| LMB | kontextová akce (sběr, rybaření, střelba…) | – |
| RMB (držet) | míření se zbraní v ruce | – |
| Tab / I / J / K / M / H | inventář / oblečení / deník úkolů / dovednosti / mapa / domů | |
| U | vysvobození ze zaseknutí | – |
| F1 / Esc / F2 | nápověda / pauza a nastavení / herní menu (čas, počasí, teleport…) | |

Funguje i herní ovladač. Ovládání koně, dronu, letadla, paramotoru a motorového rogala
(startovní procedury, přistání, licence) je v [`docs/CONTROLS.md`](docs/CONTROLS.md).

## Dokumentace

- [`GAME_DESIGN.md`](GAME_DESIGN.md) – vize, pilíře, herní smyčka, cílové parametry
- [`docs/SYSTEMS.md`](docs/SYSTEMS.md) – úplný technický rozpis všech herních systémů (fyziologie, ekonomika, zákon, zvěř, práce, letectví…)
- [`docs/CONTROLS.md`](docs/CONTROLS.md) – ovládání koně, dronu, letadla, paramotoru, trikeu
- [`docs/DEV.md`](docs/DEV.md) – jak vzniká herní mapa z geodat, ladicí/testovací parametry spouštění, architektura kódu (příprava na multiplayer)

### Návody

- [`BLENDER_UPRAVY.md`](BLENDER_UPRAVY.md) – ruční úpravy mapy v Blenderu (budovy, silnice, stromy, terén, textury) a export do hry
- [`VLASTNI_VOZIDLA.md`](VLASTNI_VOZIDLA.md) – nová auta (procedurálně i z vlastního `.glb` modelu), kola a motorky
- [`ASSETY.md`](ASSETY.md) – legální assety z internetu: kde hledat, checklist licencí, import, registr `assets/LICENSES.md`, `tools/assets_check.py`
- [`ZVIRATA.md`](ZVIRATA.md) – úprava zvířat, ptáků, počasí a ročních období (tabulky, náhled `zoo.gd`)

## Licence dat

Geodata © ČÚZK (CC BY 4.0), OSM © přispěvatelé OpenStreetMap (ODbL), textury a HDRI Poly Haven (CC0).
Ortofoto ČÚZK se ve výchozím stavu nepoužívá (jen na přepnutí F2 → Terén, soubory `textures/ortho_*.jpg` zatím zůstávají).
Všechny externí assety (modely, textury, zvuky, hudba) jsou v registru `assets/LICENSES.md` + `assets/licenses.json`;
`python3 tools/assets_check.py` hlídá neevidované soubory a nepovolené licence a generuje `data/credits.json`
(titulky CC BY se ukážou v nápovědě F1). Načítání v kódu: `AssetLib.load_model / load_sound / has` (`scripts/asset_lib.gd`).

## Právní zásady obsahu

Shrnutí z [`PRAVNI_DOPORUCENI.md`](PRAVNI_DOPORUCENI.md) – platí pro všechen nový obsah:

- **Zdroje dat:** jen ČÚZK (DMR/DMP, ortofoto – CC BY 4.0) a OSM (ODbL). Nic z Google Maps / Earth /
  Street View ani z Bingu. Uvedení zdrojů je v `data/map.json` (`license`), na úvodní obrazovce a v nápovědě F1
  (`Hud.CREDITS`).
- **Žádné reálné identifikátory:** všechna čísla popisná ve hře jsou smyšlená (`Estate` – číslování od návsi ze seedu, nic
  z RÚIAN / ČÚZK; skutečné číslo původního domu hráče se nezobrazí), cedulky s číslem mají obecný vzhled bez znaku obce,
  žádná jména na schránkách a zvoncích, žádné průhledy do soukromých dvorů a oken. SPZ se generují
  s písmenem Q, které se v českých SPZ nevydává (`Traffic.plate()`).
- **Postavy:** jen smyšlená jména, žádné podobizny ani narážky na skutečné obyvatele obce. Vesničané
  mají vymyšlená, spíš humorná jména a obecná povolání; nová jména nesmí odpovídat
  skutečným obyvatelům a texty nesmí zmiňovat skutečné sousední obce, firmy ani úřady.
- **Značky:** místo ochranných známek se používají smyšlené nebo parodické názvy (auta Oktávka / Fábička /
  Stodvacka, motorka Javor, kolo Favorín, Bylinkovka, Hořká; smyšlené podniky Hospoda U Hřiště, Pálenice U Kotla…).
- **Obecní symboly:** znak a prapor obce se ve hře nepoužívají.
- **Rádio:** vlastní stanice ve hře jsou smyšlené a hudba je generovaná. Internetové stanice v `data/radia.json`
  jsou jen odkazy na veřejné streamy Českého rozhlasu, které hra přehrává u hráče jako běžný internetový
  přijímač (nic nenahrává ani nešíří, žádná loga). Názvy stanic jsou ochranné známky provozovatele – před
  veřejným šířením hry je vhodné `radia.json` vyprázdnit, nebo si vyžádat souhlas.
- **Doložka:** úvodní obrazovka, nápověda F1 a začátek tohoto README (`Hud.DISCLAIMER`).
