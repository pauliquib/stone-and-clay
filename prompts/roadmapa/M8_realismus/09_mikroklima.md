# M8.9 – Mikroklima: inverze, mrazové kotliny, údolní mlha, rosa a jinovatka

> Roadmapa **M8 Realistický svět** · krok 9/19 · vlna 4
> Předpoklady: **M8.2 (`Site`)**, **M8.7 (`SoilWater`)**, **M8.5 (obloha – pro mlhu a světlo)** · Navazují: M8.11, M8.12, M8.15, M8.16, M8.18
> Zavádí API: `Microclimate` / `World.micro` – `temp_at(pos)`, `humidity_at`, `dewpoint_at`, `fog_at`, `frost_at`, `dew_at`, `wind_chill_at`

## 0. Než začneš – přečti
1. `00_SPOLECNE.md`, `M8_realismus/00_PRINCIPY.md` (kap. 3, 8 – mikroklima)
2. `scripts/priroda/weather.gd` (celé API – teplota, mlha, vítr, oblačnost; **nic v Weather nepřepisuj**, Microclimate je vrstva nad ním)
3. `scripts/priroda/atmosphere.gd` – mlha (`FOG_*`), `scripts/local_client.gd` env (volumetric fog dnes vypnutý?) – `grep -n "fog" `
4. `scripts/body_state.gd` – kde čte teplotu (`grep -n "temp" scripts/body_state.gd`), `scripts/priroda/chimney_smoke.gd` (kouř při inverzi)
5. `scripts/eko/site.gd` (M8.2), `scripts/eko/soil_water.gd` (M8.7), `scripts/eko/wind_field.gd` (M8.4)

## 1. Proč
Počasí je dnes stejné všude. Ve skutečné krajině je za jasné bezvětrné noci **v údolí o 5–8 °C chladněji než na kopci** (studený vzduch stéká
dolů), ráno leží v údolí mlha a nad ní svítí slunce, na trávě je rosa nebo jinovatka, jižní stráň je odpoledne horká, v lese je v létě chladněji
a vlhčeji, v obci tepleji. Tohle hráč pocítí na těle (M8.16), uvidí v krajině a ovlivní to, kde mrzne (plodiny, květy ovocných stromů).

## 2. Co udělat
- **`scripts/eko/microclimate.gd`** (`class_name Microclimate`, `World.micro`, simulace): funkce bodu **bez vlastní mřížky stavu**
  (stav drží jen pár globálních čísel – síla inverze, výška vrstvy mlhy), takže je levná:
  - `temp_at(pos)` = `Weather.temp` (referenční 2 m na „průměrné“ výšce katastru) − 6,5 K/km × (výška − ref) + **inverze**:
    v noci za jasna (malá oblačnost) a slabého větru roste síla inverze `I` (K) podle radiační bilance (konstanta K/h, max ~8 K), ráno po
    východu slunce se rozpouští; ochlazení bodu = `I` × `Site.cold_pool` (kotlina) ; přes den **přehřátí jižních svahů** ∝ záření × (insol svahu −
    průměr) a **les** ve dne −1…−3 K, v noci +1 K; **obec** +0,5…+1,5 K (tepelný ostrov podle hustoty zástavby z `surface`); voda zjemňuje.
  - `humidity_at` (relativní vlhkost z vlhkosti vzduchu `Weather` + výpar z `SoilWater` u vody a v lese), `dewpoint_at` (Magnus).
  - `fog_at(pos)` 0..1: **radiační mlha** když teplota bodu ≤ rosný bod + 0,5 K v kotlinách a u vody (vrstva výšky `fog_top` nad dnem údolí, roste
    v noci, ráno klesá a rozpouští se od okrajů), **advekční / frontální** mlha z `Weather.fog` všude jako dnes.
  - `frost_at(pos)` (teplota ≤ 0 na zemi – přízemní mráz je o 2–3 K níž než 2 m za jasné noci), `dew_at(pos)` (rosa / jinovatka 0..1, ráno,
    mizí sluncem), `wind_chill_at(pos)` (vítr z `WindField` + teplota bodu), `snow_line` pro sníh vs. déšť podle výšky.
  - `eco_hour`: aktualizace `I`, `fog_top`; denní statistika min/max v kotlině vs. hřebeni do ladění.
- **Vizuál (klient, za přepínačem `micro`):**
  - **Údolní mlha jako vrstva:** výšková mlha v `Environment` (`fog_height`, `fog_height_density`) nastavená podle `fog_top` nad dnem údolí
    v okolí kamery; na Vysoké předvolbě `volumetric_fog` v Godot 4.3 jen kolem kamery s nízkým rozlišením (ověř cenu, jinak jen výšková mlha).
    Z kopce nad mlhou je vidět „moře mlhy“ v údolí (kombinace s M8.5 vzdušnou perspektivou).
  - **Rosa a jinovatka:** globální uniform `dew` / `hoarfrost` → terén a tráva lesklejší / bělavé (`terrain.gdshader`, `vegetation.gdshader`),
    na autě namrzlé sklo (jen pokud jde jednoduše přes existující `window_glass.gdshader` – jinak otevřený bod).
  - **Kouř z komínů při inverzi** se drží v nízké vrstvě a rozlévá (M1.3 `chimney_smoke.gd`: strop stoupání = výška inverze).
  - Tetelení vzduchu nad horkou silnicí v létě (jednoduchý post-proces jen nízko nad asfaltem – volitelné, Vysoké).
- **Napojení (fallbacky zachovat):**
  - `BodyState` chlad bere `micro.temp_at(hráč)` a `wind_chill_at` místo `Weather.temp` (jen výměna zdroje – zbytek udělá M8.16),
  - HUD teplota = teplota v místě hráče (s ikonou mlhy/mrazu); deník J → počasí: „V údolí ráno mrzlo, na kopci ne.“,
  - zamrzání vody (`water.gd`) podle teploty v místě nádrže, sníh vs. déšť podle výšky,
  - zvěř: srnci za mrazivé noci výš na svazích (jen váha v `Fauna` stanovištích, pokud je to jedna tabulka – jinak nechat M8.15).
- **Ladicí vrstvy** `teplota` (aktuální teplota bodu – barevná škála), `mlha`, `mraz`; měřicí scéna `les_rano_mlha` a `udoli_noc`.

## 3. Minimum
`Microclimate` s gradientem, inverzí a kotlinami, radiační mlha v údolí ve vizuálu (výšková mlha), rosa/jinovatka v shaderu, tělo a HUD
berou teplotu v místě, vrstva teploty v mapě.

## 4. Hotovo, když
- Za jasné bezvětrné zimní noci ukáže HUD na dně údolí o několik °C méně než na hřebeni; ráno je údolí v mlze a z kopce je vidět její horní okraj.
- Ráno je tráva orosená / ojíněná a během dopoledne oschne.

## 5. Návrh checklistu ručních testů
1. F2 → říjen, jasno, bezvětří, 5:30 → údolí v mlze, kopec nad mlhou na slunci (vyjít nahoru / dron).
2. HUD teplota na dně údolí vs. na hřebeni ve 4:00 → rozdíl 3–8 °C; v poledne téměř stejné.
3. Za větru nebo zataženo → inverze slabá, mlha v údolí není.
4. Ráno tráva lesklá (rosa) / bílá (jinovatka pod nulou), v 10:00 už ne.
5. Kouř z komínů za inverze → drží se nízko nad obcí.
6. Jižní stráň v létě odpoledne → tepleji než v lese.
7. Stát v kotlině za mrazu bez bundy → rychlejší prochladnutí než na kopci.
8. Mapa M → vrstva Teplota → kotliny modré v noci.
9. Přepínač Mikroklima vypnout → teplota všude stejná.
10. `--perfscene=les_rano_mlha` → ms GPU (cíl +≤ 0,5 ms na Střední bez volumetrické mlhy).

## 6. Závěr
`docs/SYSTEMS.md` (Mikroklima), PROJECT_LOG, `docs/testy_M8.md`, commit „M8.9 Mikroklima: …“.
