# M8.1 – Základ realismu: přepínače, eko-takt, měřicí scény a ladicí vrstvy

> Roadmapa **M8 Realistický svět** · krok 1/19 · vlna 1
> Předpoklady: M0–M7 · Navazují: **všechny kroky M8** (zavádí API `World.realism`, `eco_hour`, `eco_day`, `Tests.perf_scene`, ladicí vrstvy mapy)

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md`, `prompts/roadmapa/M8_realismus/00_PRINCIPY.md` (celý – tenhle krok ho zakládá v kódu)
2. `scripts/game_settings.gd` (předvolby `PRESETS`, `gfx`, ukládání `nastaveni.cfg`) a `scripts/pause_menu.gd` (oddíly nastavení – `grep -n "_check(" `)
3. `scripts/world.gd` – kde se dnes dělá denní krok: `grep -n "clock.jd()\|advance_to\|_process_impl" scripts/world.gd`
4. `scripts/tests.gd` – `perf_test` (`grep -n "func perf_test" -A60`), `scripts/main.gd` (zpracování `--perf`)
5. `scripts/hud.gd` – mapa M: `grep -n "map_\|_draw_map\|func _map" scripts/hud.gd | head -40`; `scripts/game_menu.gd` (F2 oddíly)

## 1. Proč
M8 přidá ~17 simulačních a vizuálních systémů. Bez společného taktu by každý počítal po svém v `_process`, bez přepínačů
nepůjde najít, kdo zpomaluje hru, a bez měřicích scén nepůjde ověřit výkonový rozpočet (cíl 60 FPS na GTX 1050).

## 2. Co udělat
- **Přepínače:** `GameSettings.realism: Dictionary` se všemi klíči z 00_PRINCIPY kap. 5 (výchozí `true`, u grafiky podle předvolby),
  ukládání do sekce `[realismus]`, API `GameSettings.realism_on(key) -> bool`, signál `realism_changed(key, on)`.
  `World.realism` = odkaz na stejný slovník (server). Pauza → Nastavení → nový oddíl **„Realismus“**: zatím jen nadpis a vysvětlení;
  řádky přidávají kroky přes tabulku `REALISM_ROWS` (klíč, popisek, nápověda, cena) – data, ne větvení.
- **Eko-takt** (`scripts/eko/eco_clock.gd`, `class_name EcoClock`, instance `World.eco`): signály `eco_hour(dt_h: float)` a
  `eco_day(jd: int)` vysílané **jednou za herní hodinu / den** i při přeskoku času (spánek, F2, vězení – dohnat po krocích, max. 30 dní,
  pak jedním hrubým krokem s `dt_h` = zbytek). Pomocník `EcoClock.slice(items: int, per_frame: int, cb: Callable)` – rozloží
  práci přes snímky (časové plátky, rozpočet µs na snímek konstantou `SLICE_BUDGET_US = 2000`). Stávající denní logiku ve `world.gd`
  **nepřepisuj**, jen ji nech běžet vedle.
- **Měřicí scény:** `Tests.perf_scene(g, name)` + parametr `--perfscene=<jméno>[,sekund]`: teleport na pevné místo s pevným časem a počasím,
  kamera na pevný bod, pak stejné měření jako `perf_test` + výpis do `user://perf/<jméno>.csv` a souhrn na konzoli.
  Scény v tabulce `PERF_SCENES` (poloha, směr, datum a hodina, počasí, popis): `ves_poledne`, `les_rano_mlha`, `louka_vitr`,
  `udoli_noc`, `pole_leto`, `dron_200m`. Každý další krok smí scénu přidat. Návod do `docs/DEV.md` → „Ladicí parametry“.
- **Ladicí vrstvy mapy:** F2 → nový oddíl „Příroda – ladění“ s výběrem vrstvy; mapa M umí místo podkladu kreslit **barevnou mřížku**
  z callbacku `World.debug_layers[name] = Callable(x, z) -> Color` (vzorkování po 16–64 m podle zoomu, překreslení jen při změně).
  Zatím vrstva `realism_off` (prázdná) jako ukázka. Kroky M8 přidávají vlastní vrstvy (stanoviště, vlhkost, teplota, vítr, druhy…).
- **Složka `scripts/eko/`** s krátkým `README` komentářem v `eco_clock.gd` (co tam patří – 00_PRINCIPY kap. 9).
- **Ukládání:** `realism` je nastavení (cfg), ne save; `EcoClock` si do savu ukládá poslední zpracovaný `jd` a hodinu (klíč `eco`).

## 3. Minimum
`GameSettings.realism` + oddíl v Nastavení, `EcoClock` se signály a doháněním přeskoku času, `--perfscene` se 3 scénami, ladicí vrstva v mapě M.

## 4. Hotovo, když
- Spánek přes noc vyšle 8–10× `eco_hour` a 1× `eco_day` (ověřit čtením kódu + log `print` za ladicím přepínačem).
- `--perfscene=ves_poledne` doběhne a zapíše CSV; oddíl Realismus je v Nastavení; F2 přepne vrstvu na mapě.

## 5. Návrh checklistu ručních testů
1. Esc → Nastavení → „Realismus“ je vidět (zatím bez řádků / s vysvětlením).
2. `./run.sh --perfscene=ves_poledne` → po ~20 s výpis do konzole a soubor v `user://perf/`.
3. Totéž pro `les_rano_mlha` a `udoli_noc` – kamera stojí na stejném místě při opakování.
4. F2 → Příroda – ladění → vrstva → mapa M ukáže barevnou mřížku; vypnout → normální mapa.
5. Vyspat se doma → hra nezasekne (dohánění eko-taktu po snímcích).
6. F5 / F9 → po načtení se eko-takt nedohání znovu od začátku hry.

## 6. Závěr
README (přepínače, `--perfscene`), `docs/DEV.md`, `docs/SYSTEMS.md` (odstavec Eko-takt), PROJECT_LOG, `docs/testy_M8.md` (oddíl M8.1),
commit „M8.1 Základ realismu: …“.
