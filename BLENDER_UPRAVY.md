# Ruční úpravy mapy a 3D modelů v Blenderu

Návod, jak v Blenderu (ověřeno na verzi 5.2 LTS) vylepšovat herní mapu Dukelčic – budovy, silnice,
stromy, terén i vzhled – a jak změny dostat do hry. Vlastní auta, kola a motorky popisuje
[`VLASTNI_VOZIDLA.md`](VLASTNI_VOZIDLA.md).

---

## 1. Co je kde – „zdroj pravdy“ pro každou část mapy

Hra **nečte `.blend` přímo**. Skript `tools/export_map.py` otevře zdrojovou scénu, vytáhne z ní
geometrii a zapíše binární data do `data/`. Co se exportuje a odkud:

| Část hry | Odkud se bere | Jak upravit |
|---|---|---|
| **Terén** (výšky, kolize) | `geodata/dtm_full_scene.npy` (DMR 5G, mřížka 2 m) | **ne v Blenderu** – kap. 6 |
| Barva terénu | procedurální povrch (`shaders/terrain.gdshader`, maska `data/surface.bin` z `tools/surface.py`); ortofoto `textures/ortho_*.jpg` jen na přepnutí | editor obrázků (kap. 8) |
| **Stěny budov** | objekty `OKOLI_Budovy_steny`, `OKOLI_FULL_Budovy_steny`, `OKOLI_DumDomov_steny` + kolekce **`HRA_Steny`** | Blender – kap. 4.1–4.3 |
| **Střechy** | `OKOLI_Budovy_strechy`, `OKOLI_FULL_Budovy_strechy`, `OKOLI_DumDomov_strecha` + **`HRA_Strechy`** | Blender |
| **Asfalt / štěrkové cesty** (povrch) | `OKOLI_Komunikace_asfalt`/`_strk` (+ `OKOLI_FULL_…`) + **`HRA_Asfalt`**, **`HRA_Strk`** | Blender – kap. 4.4 |
| Trasy AI aut, vesničanů a psů | `pipeline/data/okoli_full_local.geojson` (čáry OSM) | GIS / textový editor – kap. 4.4 |
| **Stromy** | instance v `OKOLI_Vegetace`, `OKOLI_FULL_Vegetace` + **`HRA_Stromy`** | Blender – kap. 4.5 |
| Odstranění budov / stromů | kolekce **`HRA_Smazat`** (kvádry) | Blender – kap. 4.3 |
| Dům hráče | `tools/domov_hrace.py` (půdorys + střecha fitem na DMP) | Python, nebo přes `HRA_*` |
| Místa (hospoda, obchod…) | `tools/pois.py` → `data/pois.json` | Python / JSON – kap. 7 |
| Auta, postavy, psi, bedny, sudy | procedurálně v GDScriptu (`car_model.gd`, `humanoid.gd`, `prop_models.gd`) | kód, vlastní modely viz VLASTNI_VOZIDLA.md |

Materiály Blenderu se do hry **nepřenášejí**. Hra má pro každou kategorii jednu texturu
(stěny = omítka, střechy = tašky, asfalt, štěrk) a barvu bere z atributu barvy **`tint`**
na síti (kap. 5). UV mapy nejsou potřeba – textury se promítají „krabicově“ (triplanar).

Kolekce `HRA_*` jsou určené právě pro ruční úpravy: exportér je nechá ve scéně a přidá do hry.
Nemusíš tak zasahovat do obřích spojených meshů `OKOLI_*` (desítky tisíc budov v jednom objektu).

---

## 2. Příprava

1. **Zálohuj zdrojovou scénu.** Soubory `.blend` nejsou v gitu.
   ```bash
   cp blend/mapa_okoli.blend blend/mapa_okoli_zaloha_$(date +%F).blend
   ```
2. **Upravuj vždy `blend/mapa_okoli.blend`** (složka `blend/` v kořeni repozitáře).
   `blend/mapa.blend` je jen výstup exportu – při každém exportu se přepíše
   a úpravy v něm by zmizely.
3. Scéna je velká (celý katastr, ~21 800 stromů). Pro plynulou práci:
   - v Outlineru vypni oko (viewport) u `OKOLI_FULL_Vegetace` a `OKOLI_Vegetace`, když stromy nepotřebuješ,
   - pracuj ve **Solid** zobrazení, ne v Material Preview / Rendered,
   - k místu úprav se přesuň přes `View → Frame Selected` (Numpad .) na vybraném objektu,
     nebo 3D kurzorem (kap. 3).
4. Jednotky: 1 BU = 1 m, osa Z nahoru. Scéna **není natočená k severu** (vychází z původní scény domu hráče),
   úhel severu je `north_angle_deg` v `data/map.json` – orientuj se raději podle ortofota na terénu.

---

## 3. Jak najít místo ze hry v Blenderu

Ve hře otevři mapu **M** – dole je řádek *Poloha: hra x …, z … · Blender x …, y …, z …*.
Převod je jednoduchý:

| | X | Y | Z |
|---|---|---|---|
| **Godot (hra)** | x | výška | z |
| **Blender** | x | **−z** ze hry | výška |

V Blenderu: `N` → panel *View* → *3D Cursor* → zadej Location X, Y (a Z = výška), pak
`View → Align View → Center View to Cursor`, případně `Shift+C` a přiblížit.

Opačně – místo z Blenderu ve hře: vyfoť ho shora
```bash
./run.sh -- --shot=/tmp/misto.png --pos=<Blender x>,<−Blender y> --top=70
```
(`--top=70` = pohled shora na čtverec 70 m, `--pos` bez `--top` tě na místo postaví).

---

## 4. Recepty

### 4.1 Nová budova

1. V Outlineru pravým na *Scene Collection* → **New Collection**, pojmenuj přesně **`HRA_Steny`**;
   stejně **`HRA_Strechy`**. (Stačí jednou, další budovy dávej do stejných kolekcí.)
2. Aktivní kolekce `HRA_Steny` → `Shift+A → Mesh → Cube`. V Edit Mode (`Tab`) tvaruj stěny –
   půdorys klidně podle ortofota (zapni viewport terénu `OKOLI_Teren_DMR5G`, má ortofoto).
   - Spodní hranu dej **na terén nebo mírně pod něj**. Exportér svislé stěny, které končí do 0,6 m
     nad terénem, sám prodlouží o 1 m dolů, aby nikde nevisely nad zemí.
   - Horní a spodní plochu kvádru stěn můžeš smazat (strop nikdo nevidí), ale nevadí.
3. Střechu modeluj jako **samostatný objekt** v `HRA_Strechy` (jiná textura – tašky). Přesah střechy
   ~0,4 m; tloušťku modelovat nemusíš, stačí plochy s normálami ven (nahoru).
4. **Normály ven:** v překryvech zapni *Face Orientation* – vnější strany musí být modré.
   Oprava: Edit Mode → `A` → `Shift+N` (Recalculate Outside).
5. **Modifikátory aplikuj** (`Ctrl+A → Apply → All Modifiers` / *Visual Geometry to Mesh*) – exportér
   čte základní síť bez modifikátorů. Transformace (posun, rotace, měřítko) aplikovat nemusíš.
6. Barvu nastav atributem `tint` (kap. 5). Bez něj je budova bílá = textura v původní barvě.

Kolize vzniká automaticky – hráč i auta do budovy narazí.

> Pozor: `tools/clean_road_clashes.py` (spouští se po exportu) vyřadí budovy, které **stojí na silnici**
> (vozovka pokrývá velkou část půdorysu). Když budova po exportu chybí, zasahuje do asfaltu/cesty.

### 4.2 Úprava existující budovy

Budovy z mapy jsou spojené v několika velkých objektech (`OKOLI_Budovy_steny` / `_strechy` pro jádro obce,
`OKOLI_FULL_…` pro zbytek katastru).

- **Malá úprava** (výška, tvar střechy): vyber objekt → Edit Mode → najeď myší na budovu → `L`
  (vybere souvislou část = jednu budovu) → upravuj. Stěny a střecha jsou ve dvou různých objektech.
- **Předělání od základu:** budovu smaž přes `HRA_Smazat` (4.3) a postav znovu v `HRA_Steny/HRA_Strechy`.
  Tohle je bezpečnější – obří mesh nerozbiješ a úprava je oddělená.
- Detailní model domu hráče (`podkladový model`) ve hře není – exportér ho nahrazuje zjednodušeným
  domem z `tools/domov_hrace.py`. Chceš-li detailnější dům hráče, smaž ho kvádrem v `HRA_Smazat`
  a namodeluj v `HRA_Steny`/`HRA_Strechy` (okna, komín, přístavky jako tvary stěn; barvy přes `tint`).

### 4.3 Odstranění budovy nebo stromu (`HRA_Smazat`)

1. Vytvoř kolekci **`HRA_Smazat`**, v ní `Shift+A → Mesh → Cube`.
2. Kvádr roztáhni (`S`, `S Z`…) tak, aby obepínal budovu **od země až nad střechu** (smaže se každý
   trojúhelník stěn/střech, jehož střed je uvnitř, a každý strom, jehož pata je uvnitř). Kvádr může
   být natočený (`R Z`).
3. Kvádry nijak nevadí ve scéně – samotné se do hry neexportují.

### 4.4 Silnice a cesty

- Povrch nové silnice modeluj jako plochý pás (`Plane`, extruduj hrany podél osy cesty, šířka ~5–6 m)
  v kolekci **`HRA_Asfalt`** (asfalt) nebo **`HRA_Strk`** (polní / štěrková cesta).
- Výška pásu **nemusí přesně sedět** – hra silnice „přilepí“ na terén (10 cm nad něj).
  Exportér navíc pod silnicemi mírně sníží terénní mřížku, aby jím terén neprostrkoval.
- Silnice je kolize s povrchem „asfalt“/„štěrk“ → auta na ní mají správnou přilnavost.
- **AI auta, vesničané a psi** jezdí/chodí po grafu cest z `pipeline/data/okoli_full_local.geojson`
  (čáry `highway` z OSM), ne po meshi. Aby po nové silnici jezdila i AI, přidej do souboru
  `Feature` s `"properties": {"kind": "highway", "highway": "residential", "name": "…"}` a
  `"geometry": {"type": "LineString", "coordinates": [[x, y], …]}` v **Blender souřadnicích** (x, y).
  Nejpohodlněji v QGIS (vrstvu otevřeš přímo), nebo ručně v textovém editoru – body opíšeš
  z Blenderu (N-panel → Item → Location vybraného vrcholu).

### 4.5 Stromy

Stromy jsou **instance kolekcí** (Empty s *Instance → Collection*) šesti prototypů
`OKOLI_Strom_dec_0…2` (listnaté) a `OKOLI_Strom_con_0…2` (jehličnaté) z `OKOLI_StromyKnihovna`.

1. Vytvoř kolekci **`HRA_Stromy`**.
2. Vyber existující strom (Empty v `OKOLI_Vegetace`), `Alt+D` (duplikát instance), `M` → přesuň do `HRA_Stromy`.
3. Posuň ho (`G`), otoč (`R Z`), měřítko: **X/Y = šířka koruny, Z = výška** (1 = výška prototypu).
4. Barva koruny = *Object Properties → Viewport Display → Color* (RGB, alfa ignorována).
5. Výšku (Z) neřeš – strom se ve hře posadí na terén.

Nové prototypy stromů (jiný tvar) exportér zatím nezná – umí jen těch šest.

---

## 5. Barvy – atribut `tint`

Ve hře je výsledná barva = textura kategorie × `tint`. Bílá (1, 1, 1) = textura beze změny.

1. Objekt → *Object Data Properties* (zelený trojúhelník) → **Color Attributes** → `+`,
   jméno **`tint`**, Domain **Face Corner**, Data Type **Color** (nebo Byte Color).
2. Přepni do **Vertex Paint** (`Ctrl+Tab`), zapni *Face selection masking* (ikona kostičky
   v hlavičce), v Edit Mode vyber plochy, zpět do Vertex Paint, zvol barvu a `Shift+K` (Set Color).
3. Rozumné hodnoty: fasády světlé pastelové (0,85–0,95), střechy cihlové (0,75, 0,35, 0,25) nebo
   šedé (0,45) – textura je sama o sobě tmavší, přesvícení nehrozí.

Hodnoty se exportují lineárně – co vidíš ve viewportu v *Attribute* barvě, to zhruba dostaneš.

---

## 6. Terén (výšky)

Terén ve hře **není mesh z Blenderu**. Výšky i kolize se berou z mřížky
`geodata/dtm_full_scene.npy` (float, řádky od severu, krok 2 m), mesh `OKOLI_Teren_DMR5G` v Blenderu
je jen její zobrazení. Úprava terénu v Blenderu se tedy ve hře neprojeví.

Když potřebuješ terén změnit (srovnat plochu pod novou stavbou, násep, rybník), uprav mřížku Pythonem
(vždy nad zálohou):

```python
# terrain_edit.py – srovná obdélník (Blender souřadnice) na zadanou výšku (vůči scéně)
import json, numpy as np
meta = json.load(open("pipeline/data/geodata_meta_full.json"))
X0, Y1, RES = meta["grid_x0"], meta["grid_y1"], meta["dem_res"]
H_ref = json.load(open("pipeline/data/terrain_ref.json"))["H_ref"]
hm = np.load("geodata/dtm_full_scene.npy")               # absolutní výšky (m n. m.)
x_min, x_max, y_min, y_max = 100.0, 130.0, -260.0, -230.0  # obdélník v Blenderu
target = 1.5                                              # výška ve scéně (Blender Z)
c0, c1 = int((x_min - X0) / RES), int((x_max - X0) / RES) + 1
r0, r1 = int((Y1 - y_max) / RES), int((Y1 - y_min) / RES) + 1
hm[r0:r1, c0:c1] = target + H_ref
np.save("geodata/dtm_full_scene.npy", hm)
```
```bash
cp geodata/dtm_full_scene.npy geodata/dtm_full_scene_zaloha.npy   # nejdřív záloha!
python3 terrain_edit.py
```
Pak normální export (kap. 9). Mesh terénu v Blenderu zůstane starý (jen vizuálně), hra dostane nový.
Ostré hrany mezi upravenou a okolní plochou změkči přechodem (např. lineární rampou 5–10 m).

---

## 7. Místa pro úkoly

Hospoda, obchod, pálenice, sklep, chata, úřad a domov jsou v `data/pois.json` (generuje `tools/pois.py`
ze skutečných budov): `x, z` střed budovy, `door_x/z` kde stojí obsluha a kam se chodí,
`park_x/z/yaw` parkovací místo, `face_yaw` natočení. Souřadnice jsou **herní** (z = −y Blenderu).
Drobný posun dveří / parkoviště stačí přepsat v JSON; nové místo vyžaduje i úpravu `scripts/place.gd`
(nabídka, otevírací doba, obsluha).

---

## 8. Vzhled – textury, ortofoto

- PBR textury (Poly Haven, 2k) jsou v `textures/`: `beige_wall_001_*` (stěny),
  `clay_roof_tiles_02_*` (střechy), `asphalt_02_*`, `gravel_road_*`, `bark_brown_02_*`.
  Vyměníš-li soubory **se stejnými jmény** (diff / nor_gl / rough), hra je použije. Měřítko textury
  (metry na opakování) a sytost jsou v `scripts/world.gd` (`MapLoader.tinted_material(...)`).
- Terén ve hře už ve výchozím stavu **není** z ortofota, ale z tříd povrchu (`data/surface.bin`, viz README). Ortofoto
  zůstává pro porovnání (F2 → Terén). `textures/ortho_core.jpg` (jádro obce) a `ortho_full.jpg` (celý katastr).
  Jde je retušovat v GIMPu (např. odstranit auta, stíny), rozměry a georeference nesmí změnit.

---

## 9. Export do hry

Z kořene repozitáře:

```bash
# 1) jen když jsi měnil tools/domov_hrace.py (dům hráče)
python3 tools/domov_hrace.py
# 2) export mapy (Blender bez okna, trvá několik minut)
blender --background --python-exit-code 1 --python tools/export_map.py
# 3) vyřazení budov a stromů stojících v silnici (musí se smazat staré originály)
rm -rf data/orig && python3 tools/clean_road_clashes.py
# 4) hra
run.sh
```

Ve výpisu exportu zkontroluj řádky `HRA_Steny: N objects added`, `HRA_Smazat: … removed`,
`WROTE trees.bin: … trees`. Když export spadne na neexistujícím objektu, přejmenoval se některý
objekt `OKOLI_*` – jména z tabulky v kap. 1 nesmíš měnit.

Rychlá kontrola bez hraní: `./run.sh -- --shot=/tmp/check.png --pos=x,z --top=80`.

---

## 10. Pasti a doporučení

- **Neměň jména** objektů a kolekcí `OKOLI_*`. Vlastní kolekce na nejvyšší úrovni scény, které
  nezačínají `OKOLI` ani `HRA_`, exportér **smaže** (tak odstraňuje detailní model domu) –
  ve zdrojovém souboru zůstanou, jen se neexportují.
- **Počet polygonů:** celá mapa se kreslí najednou po dlaždicích 256 m. Budova do ~500 trojúhelníků je
  v pohodě; detailní ozdoby (římsy, okenní rámy po stovkách) raději vynech nebo dělej jen u domu hráče.
- **Normály** (Face Orientation modře ven) – obrácené plochy jsou ve hře neviditelné.
- **Modifikátory** (Mirror, Array, Solidify, Bevel…) před exportem aplikuj.
- **Stěny a střecha** vždy ve správné kolekci – liší se texturou i barvou.
- Jedna úprava = jeden export + jeden test ve hře. Při větších změnách si dělej průběžné zálohy `.blend`.
- Budovy mimo katastr (za hranicí terénu) budou viset ve vzduchu – terénní mřížka tam končí.

## 11. Co by šlo dál (zatím nepodporováno)

- vlastní materiály/textury pro jednotlivé budovy (dnes 1 textura na kategorii + `tint`),
- detailní rekvizity z Blenderu (ploty, lavičky, sloupy) jako glTF scény rozmístěné po mapě –
  mechanismus by byl stejný jako u vlastních vozidel (`.glb` v `models/`),
- terénní úpravy přímo v Blenderu (sochání meshe → zpětný převod do mřížky),
- nové prototypy stromů a keřů.
