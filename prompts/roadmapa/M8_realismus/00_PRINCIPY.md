# M8 – Principy realistického světa (čte každý krok M8 hned po `00_SPOLECNE.md`)

> Transformační upgrade: svět se z „kulis, které vypadají jako příroda“ mění na **soustavu propojených zjednodušených
> fyzikálních a ekologických modelů**. Krajina (terén, voda, slunce, vítr) určuje, **co kde roste a žije**, a to,
> co roste a žije, se v čase mění podle **počasí a hráče**. Tento soubor drží společná API, jednotky a pravidla,
> aby kroky M8 do sebe zapadly, i když je dělají různí agenti v různých oknech.

---

## 1. Filozofie: „věrohodný model, ne vědecká simulace“

1. **Model musí být jednodušší než realita, ale ne libovolný.** Každý model má v hlavičce souboru jednu větu
   „podle čeho“ (vzorec / zdroj z kap. 8) a tabulku laditelných konstant. Žádná magická čísla v kódu.
2. **Příčina → důsledek, který hráč vidí.** Každý krok musí mít aspoň jeden jev, který si hráč všimne bez vysvětlení
   (údolí ráno v mlze, buk raší o týden později než lípa, po bouřce teče potok kalně a výš, srnci za soumraku na poli).
3. **Data předpočítat offline, za běhu jen dohledávat a pomalu integrovat.** Vše, co závisí jen na terénu, se počítá
   v `tools/*.py` do `data/*.bin` (jednou). Za běhu se jen čte z mřížky a integruje po herních dnech / hodinách.
4. **Deterministicky.** Stejný seed a stejná data → stejný svět (multiplayer V2 i reprodukovatelné chyby).
   Náhoda jen přes `RandomNumberGenerator` se seedem z polohy / id / dne, nikdy `randf()` v simulaci.
5. **Simulace = server, vzhled = klient** (00_SPOLECNE kap. 4 „Tok zpráv“). Ekologie, voda, mikroklima, populace
   a růst běží ve `World` (do budoucna server). Shadery, částice, zvuk a animace jsou klientské a čtou jen stav.
6. **Každá novinka jde vypnout** (kap. 5) a bez ní hra běží jako dřív. Žádný krok nesmí rozbít staré uložení.
7. **Nic z internetu.** Modely, textury listů a kůry, zvuky: procedurálně (Python / Pillow / numpy / Blender headless /
   `MeshKit`) nebo dodá uživatel s licencí (00_SPOLECNE kap. 3). Reálná data jen ta, co už v `data/` jsou (DMR, OSM).

## 2. Jednotky a souřadnice
- **SI**: metry, sekundy, kg, m/s, °C (teplota vzduchu 2 m nad zemí), mm srážek, W/m² záření, lux pro osvětlení,
  Pa pro tlak. V kódu suffix u konstant, když nejde o základní jednotku (`_MM`, `_KPA`, `_LUX`, `_H`, `_DAYS`).
- Svět: metry, Y nahoru, počátek u domu hráče (`data/map.json` `x0`, `z0`); sever je `north_deg` (78,37°) – **azimut
  a orientace svahů vždy přes `north_deg`**, nikdy „−Z = sever“.
- Čas: `Clock` (1 herní h = 2 min reálně). Simulace se integruje v **herních hodinách** (`dt_h`) a **dnech** (`jd`).
  Zeměpisná šířka 49,14° s. š. (`Clock`).

## 3. Společná API mezi kroky (kontrakt – kdo zavádí, kdo používá)

| API (třída, instance ve `World`) | Zavádí | Používají | Podstata |
|---|---|---|---|
| `World.realism: Dictionary`, `GameSettings.realism` | M8.1 | všichni | přepínače kroků (kap. 5) |
| signál `World.eco_hour(dt_h)`, `World.eco_day(jd)` | M8.1 | všichni simulační | jeden zdroj hodinového / denního kroku (rozložený do snímků) |
| `Tests.perf_scene(name)` + `--perfscene=` | M8.1 | všichni | měřicí scény (kap. 6) |
| `Site` → `World.site` (`data/site.bin`, mřížka 4 m) | M8.2 | 8.3, 8.7, 8.9, 8.11–8.15 | stanoviště: výška, sklon, orientace, TWI, vzdálenost k vodě, půda, hloubka půdy, AWC, oslunění, mrazová kotlina, expozice větru |
| `TreeEco` → `World.tree_eco` (`data/tree_eco.bin`, index = pořadí v `trees.bin`) | M8.3 | 8.8, 8.11, 8.14, 8.15 | druh, věk, vitalita, výška, výčetní tloušťka, korunový zápoj |
| `data/dreviny.json` | M8.3 | 8.8, 8.11, 8.15 | katalog druhů (nároky, růst, fenologie, barvy) |
| `WindField` → `World.wind_field`; shader globals `wind_dir`, `wind_speed`, `wind_gust`, `wind_time` | M8.4 | 8.8, 8.9, 8.10, 8.14, 8.16, 8.18 + letadla, dron, kouř | vítr v bodě s nárazy a závětřím |
| konvence **barev vrcholů vegetace** (kap. 4) | M8.4 | 8.8, 8.14 | ohyb ve větru po úrovních |
| `SkyModel` (v `Atmosphere`), `Atmosphere.exposure_ev`, `sun_illuminance_lux()` | M8.5 | 8.9, 8.12, 8.16, 8.18 | fyzikální obloha, světlo, expozice |
| `Gait` (v `humanoid.gd` / nový `gait.gd`) | M8.6 | 8.16, 8.17 | fázový cyklus chůze, IK chodidel, náklon |
| `SoilWater` → `World.soil_water` (mřížka 32 m) + `Water.flow_at / level_at` | M8.7 | 8.9, 8.11, 8.12, 8.13, 8.14, 8.15 | vlhkost půdy 0..1 (vůči AWC), odtok, průtok a hladina toků |
| `Microclimate` → `World.micro` | M8.9 | 8.11, 8.12, 8.15, 8.16, 8.18 | `temp_at(pos)`, `fog_at`, `frost_at`, `dew_at`, `snow_at`, `wind_chill_at` |
| `Phenology` → `World.phenology` | M8.11 | 8.12, 8.14, 8.15, 8.18 | sumy teplot (GDD), fáze druhů, `phase(species)` |
| `Habitat` → `World.habitat` | M8.15 | 8.18 | vhodnost stanoviště pro zvěř, potrava, kryt |

**Pravidlo pro API:** krok, který API zavádí, ho napíše **s fallbackem** (bez dat / vypnuto vrací rozumnou hodnotu
z dnešního kódu – např. `Microclimate.temp_at` vrací `Weather.temp`). Krok, který API používá, ho volá **jen přes
`World.<instance>` a s kontrolou `!= null`**, aby šel dělat i dřív, než je zavádějící krok sloučen (pak dočasně fallback).

## 4. Konvence barev vrcholů vegetace (ohyb ve větru, M8.4 → M8.8, M8.14)
| Kanál | Význam |
|---|---|
| `COLOR.r` | ohebnost / úroveň větve: 0 = kmen u země (nehybný) … 1 = konec tenké větve |
| `COLOR.g` | fáze větve (hash 0..1) – sousední větve nekmitají spolu |
| `COLOR.b` | váha třepetání listů (0 = dřevo, 1 = list) |
| `COLOR.a` | okluze uvnitř koruny (0 tmavé jádro … 1 okraj) |

Barva povrchu (listí, kůra) **nesmí** jít do barev vrcholů – patří do textury / uniformu / `INSTANCE_CUSTOM`.
`INSTANCE_CUSTOM` u stromů: `rgb` = odstín koruny (jako dnes), `a` = **fenologický posun druhu** (M8.11) zakódovaný 0..1.

## 5. Přepínače a předvolby
- `GameSettings.realism` (sekce `[realismus]` v `nastaveni.cfg`), klíč = krok (`"site"`, `"species"`, `"wind"`, `"sky"`,
  `"gait"`, `"soil_water"`, `"treegen"`, `"micro"`, `"animal_gait"`, `"phenology"`, `"crops"`, `"terramech"`,
  `"ground_veg"`, `"habitat"`, `"thermo"`, `"village_life"`, `"soundscape"`), hodnota `bool` (nebo úroveň 0–3 u grafiky).
- Předvolba grafiky (`GameSettings.PRESETS`) určuje výchozí stav **grafických** novinek (obloha, tráva, impostory, mlha);
  **simulační** novinky jsou zapnuté vždy, pokud nejsou výkonově drahé (pak mají vlastní úroveň detailu).
- Pauza → Nastavení → nový oddíl **„Realismus“**: přepínač u každého kroku s jednou větou, co dělá, a odhadem ceny.

## 6. Výkonový rozpočet (cíl hry: 60 FPS na GTX 1050, 1080p, předvolba „Střední“)
- Snímek 16,6 ms. **Každý krok M8 smí přidat nejvýš 0,5 ms CPU (průměr) a 1,0 ms GPU** na předvolbě Střední; víc jen
  na Vysoké / Ultra. Hodinové a denní simulace se **rozkládají do snímků** (časové plátky přes `eco_hour` / `eco_day`,
  max. ~2 ms na snímek i ve špičce, nikdy celý katastr v jednom snímku).
- Paměť: nové mřížky ≤ 64 MB celkem (mřížka 4 m přes union mapu ~2 800 × 1 900 buněk → `uint8`/`float16`, ne `float64`).
- **Měření:** agent hru nespouští, ale každý krok **přidá měřicí scénu** (`Tests.perf_scene`, M8.1) a do logu zapíše,
  co má uživatel změřit (`--perfscene=<jméno>`) a jaký výsledek se čeká. Uživatel pošle čísla; regrese se řeší v M8.19.
- Daleko od hráče (> `World.sim_radius`, dnes 320 m) se nic nekreslí ani neanimuje navíc; simulace běží hrubě (jen data).

## 7. Offline generátory a co smí agent spouštět
- 00_SPOLECNE kap. 2 bod 3 platí: **hru ani testy nespouštěj**.
- **Výjimka pro M8 (jen pokud ji uživatel povolil na startu M8 – orchestrátor se ptá):** agent smí spustit
  **offline generátor dat** (`python3 tools/<x>.py`, `blender --background --python tools/<x>.py`), protože to není hra:
  ověří, že doběhne, a vypíše statistiku (počty, rozsahy hodnot, histogram). Výstup `data/*.bin` se **necommituje**
  (`.gitignore`); README → tabulka nástrojů musí říct, kdy ho uživatel pustí. Bez povolení agent generátor jen napíše.
- Python nástroje: jen `numpy`, `scipy`, `Pillow` (jsou nainstalované) + standardní knihovna; Blender 5.2 headless
  jen tam, kde to krok výslovně říká. Každý nástroj: deterministický seed, `--help`, hlavička s formátem výstupu
  (vzor `tools/vegetation.py`), binární formát s magic + verzí.

## 8. Zdroje modelů (podle čeho – citovat v hlavičce souboru)
| Oblast | Model / zdroj (zjednodušeně) |
|---|---|
| Stanoviště | D8 tok / akumulace, **TWI = ln(a / tan β)** (Beven & Kirkby 1979); oslunění z polohy slunce (`Clock.sun_enu`) a sklonu/orientace; TPI pro expozici větru a mrazové kotliny |
| Půda | třídy podle české taxonomie zjednodušeně (hnědozem/kambizem, ranker/litozem, arenosol, pseudoglej/glej, fluvizem, antropozem); **AWC** v mm podle textury a hloubky; volitelně BPEJ (uživatel dodá) |
| Dřeviny | Ellenbergovy indikační hodnoty (světlo, vlhkost, živiny, reakce, teplota); lesní vegetační stupně ČR; růst **Chapman–Richards** `h(t) = H·(1−e^(−k·t))^p`; alometrie výška–tloušťka (Näslund) |
| Generování stromů | **space colonization** (Runions et al. 2007) pro listnáče, **přeslenový růst** pro jehličnany, parametry ve stylu Weber & Penn 1995; LOD + **oktaedrické impostory** |
| Vítr | logaritmický profil `u(z) = u*/κ · ln(z/z0)`; nárazy jako posouvaný šum (Taylorova hypotéza „zamrzlé turbulence“); hierarchický ohyb (kmen → větev → list) jako tlumený oscilátor |
| Obloha a světlo | Rayleigh + Mie rozptyl, ozon (zjednodušeně Hillaire 2020 / Bruneton); osvětlení v luxech (jasné poledne ~100 000 lx, zataženo ~10 000 lx, občanský soumrak ~3 lx, úplněk ~0,25 lx); EV expozice |
| Voda | „kyblíkový“ model půdní vody (bucket), odtok **SCS Curve Number**, výpar **Hargreaves** (z teploty a extraterestrického záření), lineární nádrž pro průtok toku, tání sněhu **degree-day** (3–5 mm/°C/den) |
| Mikroklima | vertikální gradient −6,5 K/km; noční radiační ochlazování a stékání studeného vzduchu do kotlin (podle TPI a oblačnosti/větru); rosný bod z vlhkosti (Magnusův vzorec); radiační mlha za jasné bezvětrné noci u vody a v údolí |
| Fenologie | **GDD** se základem 5 °C (u ovocných a obilí podle druhu), chlazení v zimě (chill hours); kalibrace na fenologické fáze ČHMÚ pro střední Moravu |
| Plodiny | zjednodušený WOFOST / „light use efficiency“: přírůstek = RUE × zachycené záření × stres(voda, teplota); fáze podle GDD |
| Terramechanika | Bekker / Wong zjednodušeně: zaboření podle únosnosti (vlhkost × textura), odpor valení, prokluz; trvalé koleje |
| Zvěř | vhodnost stanoviště (HSI) z krytu, potravy, klidu; denní cyklus aktivity; logistický růst populace s kapacitou; hustoty pro ČR (srnec, prase) ověřit |
| Lokomoce | Hildebrandovy chody (fázové posuny nohou pro krok, klus, cval), duty factor; boidy (Reynolds 1987) pro hejna |
| Člověk – pohyb | fázový cyklus chůze (stojná ~60 % / švihová ~40 %), délka kroku ∝ rychlost a výška, IK chodidel na terénu, těžiště nad opěrnou bází |
| Člověk – tělo | tepelná bilance: metabolické teplo (MET podle činnosti) − ztráty (konvekce s větrem, odpařování, záření) s izolací oděvu v **clo**; pocitová teplota (wind chill, heat index); hydratace a energie (kcal) |
| Zvuk | ptačí chorál podle druhu, měsíce a minut od východu slunce; cvrčci podle teploty (**Dolbearův zákon**); žáby u vody na jaře |

## 9. Jak psát kód kroků M8
- Drž 00_SPOLECNE (česky, typované GDScript 4.3, konstanty nahoře, data místo větvení, kontrola překladu).
- Nový simulační systém = vlastní soubor v `scripts/eko/` (nová složka pro M8 simulace) s `class_name`, instance ve `World`;
  vizuál v `scripts/priroda/` nebo `scripts/vegetation/`; shadery v `shaders/`.
- **`world.gd` jen minimálně:** vytvoření instance, předání závislostí, připojení na `eco_hour` / `eco_day`, klíč do savu
  (00_SPOLECNE kap. 5.6). Logika patří do vlastního souboru.
- Laditelné tabulky do `data/<x>.json`, pokud je bude ladit člověk (druhy dřevin, plodiny, zvěř), jinak `const`.
- Ladicí výstup: F2 → nový oddíl **„Příroda – ladění“** (vrstvy mapy M: stanoviště, vlhkost, teplota, vítr, druhy) – každý
  krok přidá svou vrstvu, aby šel model zkontrolovat okem bez debuggeru.
- Na konci kroku do `docs/SYSTEMS.md` nový / doplněný odstavec (jako ostatní systémy) a do README tabulka nástrojů / přepínače.
