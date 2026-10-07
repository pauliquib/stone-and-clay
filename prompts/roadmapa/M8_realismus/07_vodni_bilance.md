# M8.7 – Vodní bilance: vlhkost půdy, odtok, potoky a bláto

> Roadmapa **M8 Realistický svět** · krok 7/19 · vlna 3
> Předpoklady: M8.1, **M8.2 (`Site`: TWI, AWC, půda)** · Navazují: M8.9, M8.11, M8.12, M8.13, M8.14
> Zavádí API: `SoilWater` / `World.soil_water`, `Water.flow_at(x,z)`, `Water.level_at(x,z)`, `SoilWater.mud_at(x,z)`

## 0. Než začneš – přečti
1. `00_SPOLECNE.md`, `M8_realismus/00_PRINCIPY.md` (kap. 3, 6, 8 – voda)
2. `scripts/priroda/weather.gd` – `rain`, `wetness`, `rain_recent`, `drought`, `snow_cover`, `temp` (`grep -n "wetness\|drought\|rain_recent\|snow_cover" `)
3. `scripts/water.gd` (hlavička, `info_at`, `_process_impl`, tabulka `FLOW`), `shaders/water.gdshader`
4. `scripts/priroda/puddles.gd` (louže dnes podle globální `wetness`), `scripts/car.gd` `_surface_grip` (`grep -n "func _surface_grip" -A15`)
5. `scripts/garden.gd` – zálivka (`grep -n "water\|zaliv" scripts/garden.gd | head -20`), `scripts/studanka.gd`, `scripts/vyhlasky.gd` (sucho)

## 1. Proč
Dnes je „mokro“ jedno číslo pro celý svět: po dešti je mokrá i hřebenová stráň, potok teče pořád stejně a v suchu se nic nemění.
V realitě voda **teče z kopců do údolí**: niva je podmáčená ještě týden po dešti, potok po bouřce zkalní a vystoupá, v létě v suchu skoro
vyschne, na jaře taje sníh a polní cesta se změní v bláto. Na vlhkosti půdy pak závisí plodiny, stromy, houby, louže i auta.

## 2. Co udělat
- **`scripts/eko/soil_water.gd`** (`class_name SoilWater`, `World.soil_water`): mřížka **32 m** přes katastr (z `Site` zprůměrované AWC,
  propustnost, TWI, sklon), v každé buňce **kyblík** (bucket) `w` mm (0..AWC) a sněhová pokrývka `swe` mm vodního ekvivalentu.
  Integrace v `eco_hour` (časové plátky přes `EcoClock.slice`):
  1. srážka z `Weather.rain` (`RAIN_MM_H`) → sníh pod `SNOW_BELOW` jinak voda; **zachycení v korunách** v lese (2–4 mm, z `TreeEco` zápoje / `surface`),
  2. tání sněhu **degree-day** (3–5 mm/°C/den, víc na jižních svazích podle `Site.insol_winter`),
  3. **infiltrace vs. povrchový odtok – SCS Curve Number** (CN podle půdy, landuse a nasycení; zamrzlá půda → téměř vše odtéká),
  4. **výpar Hargreaves** (teplota, denní rozkmit, extraterestrické záření z šířky a dne; les víc, holé pole méně; omezený vlhkostí `w/AWC`),
  5. přetok nad AWC → **podpovrchový odtok** po svahu do níže položených buněk (směr z D8 na hrubé mřížce, předpočítat při načtení),
  6. odtok z buněk sousedících s tokem → **přítok do úseku toku**.
  `moisture_at(x,z)` 0..1 (= w/AWC, bilineárně), `mud_at(x,z)` 0..1 (vlhkost × jílovitost × holá půda / cesta), `snow_at(x,z)` (výška sněhu m).
  **Rozběh:** při nové hře / starém savu bez klíče „roztoč“ bilanci 60 dnů zpět z klimatu `Seasons` (rychle, hrubě po dnech), ať svět nezačíná suchý.
- **Toky – lineární nádrž:** každý úsek toku v `water.json` (nebo skupina úseků podle povodí) má zásobu `S`, odtok `Q = S/k` (k = 6–48 h podle velikosti),
  základní odtok z podzemní vody (pomalá nádrž). `Water.flow_at(x,z)` (m³/s) a `Water.level_at(x,z)` (relativní hladina vůči normálu).
  Vizuál (klient): hladina potoka zvedá / snižuje pás vody (`water.gdshader` uniform posunu, max. ±0,4 m, ne mimo koryto), **kalnost**
  (barva) po přívalu, rychlost proudění v shaderu podle průtoku; v suchu u malých potoků **vyschlé koryto** (hladina pod dnem → schovat).
  Šumění potoka (`nearest_stream` zvuk) hlasitější při vyšším průtoku. Brodění (`info_at` hloubka) podle hladiny.
- **Napojení (každé za přepínačem `soil_water`, fallback dnešní globální chování):**
  - `Weather.surface_grip("teren")` / `car._surface_grip` → bláto z `mud_at` v místě kola (ne globální `wetness`),
  - **louže** (`puddles.gd`) jen tam, kde je mokro lokálně (a v prohlubních – TWI), vysychají postupně,
  - terénní shader: tmavší mokrá hlína podle `moisture` (hrubá textura 32 m nahraná jako `ImageTexture` přes katastr, aktualizace 1× za herní hodinu),
  - `Weather.drought` a vyhláška sucha (M4.4) z průměrné vlhkosti půdy + průtoku (místo čistého počítadla bez deště) – zachovej API,
  - hřiby (`rain_recent`) z lokální vlhkosti v lese, zahrada: záhon vysychá podle `SoilWater` v místě (zálivka přidá mm do buňky záhonu).
  - Studánka (M5.10) v dlouhém suchu teče slabě.
- **Ladicí vrstvy** `vlhkost`, `snih`, `odtok` (aktuální povrchový odtok) a v F2 → Příroda – ladění „Průtoky“ (tabulka hlavních toků Q a hladina).
- Ukládání: mřížka `w`, `swe`, zásoby toků (klíč `soil_water`, kompaktně – `PackedFloat32Array` → base64).

## 3. Minimum
Kyblíkový model s CN odtokem, výparem a táním na mřížce 32 m, lineární nádrže toků s hladinou a kalností, bláto pro auta z lokální vlhkosti,
louže jen lokálně, ukládání a rozběh.

## 4. Hotovo, když
- Po bouřce potok viditelně vystoupá a zkalní a za 1–3 herní dny se vrátí; niva zůstane mokrá déle než svah.
- V suchém létě je malý potok téměř bez vody; auto na polní cestě v nivě po dešti klouže víc než na kopci.

## 5. Návrh checklistu ručních testů
1. F2 → Počasí → Bouřka na 2 h → potok u obce vystoupá a je hnědý; zvuk hlasitější.
2. Přeskočit 3 dny jasna → hladina zpět, voda čistá.
3. Mapa M → vrstva Vlhkost po dešti: údolí modrá, hřebeny světlé; po týdnu sucha zesvětlá.
4. Auto po dešti: polní cesta v nivě → smyk; stejná cesta na kopci → lépe.
5. Louže jen v nížinách / na cestách, ne všude.
6. Zima: sníh na jižním svahu taje dřív než na severním.
7. F2 → datum červenec, 3 týdny bez deště → malý potok vyschlý, vyhláška sucha.
8. Zalít záhon → vrstva vlhkosti v buňce záhonu stoupne.
9. F5/F9 → hladiny a vlhkost zůstanou.
10. `--perfscene=pole_leto` → ms procesu (cíl +≤ 0,3 ms průměr).

## 6. Závěr
`docs/SYSTEMS.md` (Voda v krajině), README, PROJECT_LOG, `docs/testy_M8.md`, commit „M8.7 Vodní bilance: …“.
