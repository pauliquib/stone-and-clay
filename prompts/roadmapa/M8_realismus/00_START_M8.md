# Start M8 – Realistický svět (transformační upgrade) – zadání pro novou session (orchestrátor, Sonnet 5)

Spusť až po uzavření M7. Model nastav **před spuštěním**, aby ho zdědili i subagenti:

```bash
CLAUDE_CODE_SUBAGENT_MODEL=claude-sonnet-5 claude --model claude-sonnet-5
```

---

Pokračujeme na hře Stone & Clay. M0–M7 jsou hotové, **multiplayer (V2) se neřeší**. Začíná milník **M8 Realistický svět** –
transformační upgrade, který postupně nahradí „kulisy“ propojenými zjednodušenými fyzikálními a ekologickými modely
(stanoviště, voda, vítr, světlo, mikroklima → rostliny, stromy, plodiny, zvěř → člověk a život vesnice).
Pracuješ jako **orchestrátor**: rozplánuješ vlny, necháš si plán schválit a práci zadáváš subagentům tak, aby si nepřekáželi
a aby sis **nezahltil kontextové okno**.

## Pravidla orchestrátora (šetři kontext)
- **Sám kód nepiš a velké soubory nečti.** Čteš jen: tento soubor, `00_SPOLECNE.md`, `M8_realismus/00_PRINCIPY.md` (kap. 3 a 6 pozorně),
  oddíl M8 v `prompts/roadmapa/README.md`, poslední 3 záznamy `PROJECT_LOG.md` a **shrnutí subagentů**. Prompty kroků nečti celé –
  stačí hlavička (předpoklady) a „Minimum“.
- Každý krok = **jeden subagent** (`Agent`, `isolation: "worktree"`). **Parametr `model` nezadávej** – zdědí Sonnet 5.
- Subagent vrací **max. 25 řádků**: hotovo / změněné soubory / **zavedená nebo použitá API z 00_PRINCIPY kap. 3** / otevřené body /
  kontrola překladu / co má uživatel změřit (`--perfscene`) / hash commitu.
- Nedoběhnutý krok → **nový** subagent „pokračuj podle otevřených bodů v PROJECT_LOG.md (záznam M8.X)“. Sám nedodělávej.
- Po každé vlně **krátká zpráva uživateli** (3–5 řádků).

## Nejdřív přečti (nic jiného)
1. `prompts/roadmapa/00_SPOLECNE.md` (pravidla, mapa kódu, kontrola překladu kap. 6).
2. `prompts/roadmapa/M8_realismus/00_PRINCIPY.md` (API mezi kroky, rozpočet výkonu, offline generátory).
3. `prompts/roadmapa/README.md` – oddíl M8.
4. Poslední 3 záznamy `PROJECT_LOG.md`.

## Než zadáš první vlnu – zeptej se uživatele (jedním `AskUserQuestion`)
1. **Offline generátory:** smí subagenti spouštět `python3 tools/*.py` a `blender --background` (ne hru) a ověřit výstup? (00_PRINCIPY kap. 7)
2. **Testování:** po každé vlně (doporučeno – M8 je velká a vizuální, výkonové regrese je lepší chytit brzy), nebo až na konci?
3. **Měření výkonu:** pošle uživatel po vlně výsledky `--perfscene=…` na svém PC (GTX 1050-třída)? Bez nich se výkon ladí naslepo.
4. **Půdní data:** má uživatel BPEJ / půdní mapu katastru (shapefile / GeoJSON)? Pokud ne, M8.2 odvodí půdu z terénu a landuse.

## Plán vln (navrhni uživateli, uprav jen s odůvodněním)

| Vlna | Kroky souběžně | Proč | Sdílené soubory – pořadí slučování |
|---|---|---|---|
| 1 | **M8.1** Základ (přepínače, eko-takt, měřicí scény) | všechno ostatní na tom stojí | `world.gd`, `game_settings.gd`, `pause_menu.gd`, `tests.gd` |
| 2 | **M8.2** Mapa stanovišť ∥ **M8.5** Obloha a světlo ∥ **M8.6** Pohyb člověka | nezávislé oblasti (data terénu / atmosféra / postava) | `world.gd` jen řádky instancí; slučuj 8.2 → 8.5 → 8.6 |
| 3 | **M8.3** Dřeviny a porosty ∥ **M8.4** Pole větru ∥ **M8.7** Vodní bilance | 8.3 a 8.7 potřebují `Site`; 8.4 je samostatné | 8.3 `map_loader`/`tree_manager`; 8.4 shadery vegetace + `atmosphere`; 8.7 `water.gd`, `weather.gd`, `car.gd` (grip) |
| 4 | **M8.8** Generátor stromů ∥ **M8.9** Mikroklima ∥ **M8.10** Lokomoce zvířat a let ptáků | 8.8 potřebuje druhy (8.3) a konvenci barev (8.4); 8.9 `Site` + voda + obloha | 8.8 `map_loader`, `tree.gdshader`; 8.9 `atmosphere`, `body_state` jen čte; 8.10 `fauna/` |
| 5 | **M8.11** Fenologie a růst ∥ **M8.12** Plodiny a zahrada ∥ **M8.13** Terramechanika ∥ **M8.16** Tělo 2 | potřebují mikroklima a vodu | 8.11 `tree.gdshader`, `seasons.gd`, `planted_trees.gd`; 8.12 `fields.gd`, `garden.gd`; 8.13 `car.gd`, `terrain.gdshader`; 8.16 `body_state.gd` – slučuj 8.11 → 8.12 → 8.13 → 8.16 |
| 6 | **M8.14** Přízemní vegetace a louky ∥ **M8.15** Ekologie zvěře ∥ **M8.17** Život vesnice | 8.14 potřebuje vítr, vodu, druhy; 8.15 fenologii (žaludy, bukvice) | 8.14 `vegetation/`, `tools/vegetation.py`; 8.15 `fauna/fauna.gd`; 8.17 `villager.gd`, `ai/` |
| 7 | **M8.18** Zvuková krajina a drobný život | potřebuje mikroklima, fenologii, zvěř | `nature_sfx.gd`, `bird_flock.gd` |
| 8 | **M8.19** Kalibrace, výkon a uzavření | po všech; s čísly od uživatele | celý projekt |

Vlna smí běžet, i když předchozí krok má otevřené body – pokud je API z 00_PRINCIPY kap. 3 hotové aspoň s fallbackem.
Když API chybí, krok čeká (nepřeskakuj závislost).

## Zadání pro subagenta (šablona)

> Pracuješ na hře Stone & Clay v izolovaném worktree. **První krok:** `git merge --ff-only main`.
> Přečti `prompts/roadmapa/00_SPOLECNE.md`, pak `prompts/roadmapa/M8_realismus/00_PRINCIPY.md` a proveď
> `prompts/roadmapa/M8_realismus/XX_….md`.
> Offline generátory: <smíš spustit a ověřit / jen napsat> (rozhodnutí uživatele).
> Šetři kontext: velké soubory (`world.gd`, `hud.gd`, `car.gd`, `player.gd`, `humanoid.gd`, `animal.gd`) nečti celé – `grep -n` a výřezy.
> Sdílené soubory v této vlně: … – do nich jen **minimální hunky** (nové řádky / funkce na konec), nic nepřejmenovávej.
> Hru ani testy nespouštěj; povinná je kontrola překladu (00_SPOLECNE kap. 6) – výstup musí být prázdný.
> Na konci: záznam do `PROJECT_LOG.md`, checklist ručních testů (max. 10 bodů) + **co změřit** (`--perfscene=…`, očekávání) do vlastního
> oddílu `docs/testy_M8.md`, `docs/SYSTEMS.md` a README doplnit, odškrtnout jen při splnění „Hotovo, když“, **commit** ve worktree
> (česky, styl historie, zakončit řádkem `Co-Authored-By` podle systémové připomínky).
> **Odpověď mně: max. 25 řádků** podle pravidel orchestrátora.

## Po každé vlně (orchestrátor)
1. Slouč větve do `main` v pořadí z tabulky (konflikty v `PROJECT_LOG.md` / `README.md` / `docs/*.md` = ponech obě části).
2. Kontrola překladu nad celým `main` (kap. 6, každý změněný `.gd` zvlášť); chyby po sloučení opraví malý subagent.
3. Ověř grepem, že API, která vlna slíbila (00_PRINCIPY kap. 3), ve `main` opravdu jsou (`grep -n "class_name Site" scripts -r` …).
4. Commit sloučení, zpráva uživateli. Pokud uživatel testuje po vlnách: počkej na výsledky a chyby zadej subagentovi **před** další vlnou.

## Na konci M8 (povinné)
1. Odškrtni kroky v `prompts/roadmapa/README.md` a `docs/VIZE_A_ROADMAPA.md`, záznam „Uzavření M8“ do `PROJECT_LOG.md`.
2. **Vyzvi uživatele, ať přepne model na Opus 5.5** a zadá: *„Proveď závěrečnou kontrolu M8 podle
   `prompts/roadmapa/M8_realismus/00_START_M8.md`, oddíl Závěrečná kontrola.“*

---

## Závěrečná kontrola M8 (pro Opus 5.5)
1. Kontrola překladu všech skriptů – výstup prázdný.
2. **Kontrakt API** (00_PRINCIPY kap. 3): každé API existuje, má fallback, uživatelé ho volají přes `World.<x>` s kontrolou `null`;
   žádné dvě implementace téhož (např. dvě teploty v bodě, dva výpočty vlhkosti).
3. **Deterministika:** v `scripts/eko/` žádné `randf()` / `randi()` bez seedovaného `RandomNumberGenerator`.
4. **Přepínače:** každý klíč z 00_PRINCIPY kap. 5 je v Nastavení a po vypnutí se hra chová jako před M8 (čti větve kódu).
5. **Výkon:** projdi `eco_hour` / `eco_day` a `_process` nových systémů – nic nepočítá celý katastr v jednom snímku; MultiMesh / LOD
   u všeho opakovaného. Porovnej čísla od uživatele (`docs/testy_M8.md`) s rozpočtem 00_PRINCIPY kap. 6.
6. Ukládání (nové klíče s výchozí hodnotou, save z M7 se načte), právní zásady, žádné cizí assety bez registru.
7. Oprav nalezené chyby, doplň `docs/testy_M8.md`, commit, předej uživateli finální checklist ručních testů a tabulku výkonu.
