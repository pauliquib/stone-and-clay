# Vizuální validátor

Automatická kontrola, jestli svět „vypadá správně“ – bez člověka u monitoru (cloud, CI).

```
tools/vizual/run.sh [--out=logs/vizual/latest] [--quick] [--no-engine] [--res=WxH]
```

Výsledek: `<out>/report.html` (tabulky nálezů, náhledy pohledů s metrikami, galerie, před/po),
`report.json` (stav PASS/WARN/FAIL celkem i po vrstvách) a `contact_sheet.png`. Exit kód 1 při FAIL.
Minulý běh se přesune do `logs/vizual/prev` a snímky se s ním porovnají (SSIM, ΔE).

| Krok | Soubor | Výstup |
|---|---|---|
| 1 | `synth_world.py` – jen když chybí `data/terrain_height.bin` | `data/*.bin` |
| 2 | `validate_data.py` – data bez enginu | `data.json` |
| 3 | `validator.gd` přes `godot_xvfb.sh` (ne s `--no-engine`) | `geometry.json`, `views/`, `views.json`, `gallery/`, `gallery.json` |
| 4 | `validate_images.py` – metriky snímků | `images.json` |
| 5 | `report.py` – souhrn | `report.json`, `report.html`, `contact_sheet.png` |

Chybějící vstup vrstvy = SKIP (ne FAIL). Každý skript jde pustit i samostatně (`--out=…`, `--help`).

## Datová vrstva (`validate_data.py`)

Domy (`buildings.json`): pořadí výšek, výška zdí podle typu, sklon střechy, samoprotínání a překryvy půdorysů,
zásah do silnic (šířky podle `ROAD_W` z `tools/expand_buildings.py`), dveře na obvodu a směrem k cestě,
domy v rybnících a potocích, předměty a spawn. S `.bin` navíc: terén pod domy vs `ground_y`, špičky v terénu,
profil silnic (schody, podélný a příčný sklon), stromy a vegetace (v domě, na silnici, výška vs terén) a sítě
DBM1 (NaN, degenerované trojúhelníky, normály, barvy, spodní hrana zdí vs terén, štíty bez zdi pod sebou,
výška střechy vs `ridge_y`).

V JSON je jen `TOP_N` nejhorších nálezů na kontrolu a počty; souhrnné metriky (`*_ok_pct`) jsou v `summary`.
Prahy jsou konstanty na začátku skriptu.

## Obrazová vrstva (`validate_images.py`)

Pro každý PNG: histogram jasu, ořez v černé/bílé, expozice, sytost, odhad oblohy a horizontu, ploché
jednobarevné skvrny (chybějící textura), magenta, čistě černé plochy, izolované extrémní pixely (NaN/inf),
vysokofrekvenční šum a aliasing (energie u Nyquista). Prahy podle denní doby a počasí z `views.json`
(`time`, `weather`): noc smí být tmavá, sníh světlý. Další adresáře: `--dir=…`.
