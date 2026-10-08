# M8 Realistický svět – pokračování po 8. 10. 2026

> Tento soubor je **prompt pro novou orchestrátorskou session** (Sonnet 5), která navazuje přesně
> tam, kde skončila předchozí session 8. 10. 2026. Zkopíruj obsah kapitoly „Co napsat nové session"
> jako první zprávu, nebo na tento soubor jen odkaž (`Přečti a navaž na
> prompts/roadmapa/M8_realismus/POKRACOVANI_8_10_2026.md`).

## Stav repozitáře

- `main` = `a7572bc` (pushnuto na `origin/main`, zůstal synchronní – **udržuj to tak**, viz incident níž).
- Hotové a sloučené: **M8.1** (základ, přepínače, eko-takt, `tools/launcher.sh`), **příprava BPEJ dat**
  (číselník bez geometrie, `docs/BPEJ.md`), **vlna 2** (M8.2 Mapa stanovišť, M8.5 Fyzikální obloha,
  M8.6 Pohyb člověka) + **oprava regrese výkonu** po vlně 2 (villager/humanoid – zbytečné alokace a
  60 Hz vzorkování sklonu terénu, opraveno na throttling ~10×/s).
- `prompts/roadmapa/README.md` a `docs/VIZE_A_ROADMAPA.md`: M8.1, M8.2, M8.5, M8.6 odškrtnuté `[x]`.
- Žádné rozpracované worktree/branch nezůstaly (uklizeno 8. 10. 2026 večer) – `git worktree list`
  má jen hlavní checkout. Jediná výjimka: `worktree-agent-ab3e235f90945feef` (branch, ne worktree) –
  **diverzní branch z BPEJ přípravy, NEMERGOVAT, klidně `git branch -D`** (bezpečně, soubory z ní
  jsou dávno ručně přenesené do main).

## Rozhodnutí uživatele platná pro celé M8 (neptat se znovu)

1. **Offline generátory** (`python3 tools/*.py`, `blender --background`) – agenti smí spustit a
   ověřit výstup. Hru a `--…test` nikdy nespouštějí (00_SPOLECNE kap. 2 bod 3).
2. **Testování po každé vlně** – ne až na konci M8.
3. **Výkon** – uživatel měří přes `tools/launcher.sh --perfscene=<jméno>`, výstup automaticky
   `logs/latest.log` (kompaktní, deduplikovaný – viz M8.1). Posílá log, orchestrátor ho čte sám.
4. **Půdní data (BPEJ)** – uživatel nemá a nedohledal se ani veřejný zdroj s geometrií pro tento
   katastr (geoportál SPÚ byl nedostupný, starý odkaz 404). M8.2 už vyřešeno fallbackem z terénu +
   landuse (česká taxonomie půd, bez reálných BPEJ kódů) – **hotovo, neřešit znovu**, jen `docs/BPEJ.md`
   nechat jako poznámku pro případ, že se zdroj v budoucnu obnoví.

## Naměřená výkonová kalibrace (pro M8.19, průběžně aktualizovat)

- Baseline (před M8, 8. 10. 2026 ráno): `ves_poledne` 26,8 fps/37,3 ms, `les_rano_mlha` 26,1/38,2,
  `udoli_noc` 28,6/34,9. HW uživatele: **NVIDIA Quadro M2200** (ne GTX 1050, podobná třída), log
  hlásí `Vulkan ... Forward Mobile`, **ne Forward+** jak počítá `00_SPOLECNE.md` – `project.godot`/
  `nastaveni.cfg` má `RENDERER_VALUES` přepínatelné mezi `forward_plus`/`mobile`
  (`scripts/game_settings.gd`), uživatel má zřejmě uloženo `mobile`. **Zjisti/ověř při M8.19**, jestli
  přepnutí na Forward+ dá rozumný FPS, nebo ne (SSAO hlásí, že potřebuje Forward+ a nefunguje).
  Rozpočet „0,5 ms CPU / 1,0 ms GPU navíc za krok" je nad tímto (přetíženým) základem, ne nad
  ideálním 60 fps.
- Po vlně 2 (M8.2+M8.5+M8.6) před opravou: `ves_poledne` 22,8 fps/44,0 ms – villager +27 %/instanci,
  humanoid +110 %/instanci (čekáno), car +18 %/instanci (nejspíš jen šum hustoty dopravy, car.gd se
  nezměnil). **Po opravě (`a7572bc`) čeká se na nové měření uživatele** – až dorazí, porovnej s
  26,8 fps/37,3 ms (cíl: blízko původní hodnotě, ne +6,7 ms).
- **Nové `--perfscene` zavedené dosud**: `ves_poledne`, `les_rano_mlha`, `udoli_noc`, `louka_vitr`,
  `pole_leto`, `dron_200m` (M8.1) + `zapad_slunce` (M8.5).

## Co dělat jako první v nové session

1. Počkej na výsledek měření `ves_poledne` po opravě regrese (pokud ještě nedorazil) – zapiš číslo
   do `docs/testy_M8.md` (má už oddíl k tomu z oprav 8. 10.). Pokud je to v pořádku (zpátky blízko
   26,8 fps/37,3 ms), pokračuj vlnou 3. Pokud ne, zadej další vyšetřovacího subagenta (stejný vzorec
   jako oprava z 8. 10. – `PROJECT_LOG.md` záznam „Oprava regrese výkonu po vlně 2 M8“ má celý postup).
2. Spusť **vlnu 3**: **M8.3** Dřeviny a porosty ∥ **M8.4** Pole větru ∥ **M8.7** Vodní bilance
   (tabulka vln v `00_START_M8.md`). Sdílené soubory podle tabulky: 8.3 `map_loader`/`tree_manager`;
   8.4 shadery vegetace + `atmosphere`; 8.7 `water.gd`, `weather.gd`, `car.gd` (grip). Slučovat v
   libovolném pořadí mezi sebou (nejsou v konfliktním pořadí jako 8.2→8.5→8.6), ale 8.3 a 8.7 obě
   potřebují `Site` z M8.2 (hotovo) a `TreeEco`/`dreviny.json`, které 8.3 teprve zavádí – pokud 8.7
   čte `TreeEco`, zkontroluj při zadávání, že 8.3 doběhlo dřív, nebo dej 8.7 fallback instrukci.

## Bezpečnostní pravidla zavedená 8. 10. 2026 (dodržuj do konce M8)

### 1. Diverzní worktree – ověřovat AŽ PO mergi, ne před ním

Jeden subagent (BPEJ příprava) skončil ve worktree na úplně jiné, staré historii repozitáře
(`origin/main` byl 107 commitů pozadu, protože lokální `main` nikdy nebyl pushnutý). **Oprava:**
`origin/main` je teď synchronní s lokálním `main` – **udržuj to tak, pushuj po každém sloučení vlny**.

Každý zadávaný subagent, který pracuje v `isolation: "worktree"`, musí mít v promptu:

```
1. `git merge --ff-only main` (main je teď na `<HASH>`).
2. `git merge-base --is-ancestor <HASH> HEAD && echo ANCESTOR_OK || echo ANCESTOR_MISSING`.
3. Pokud se nevypsalo `ANCESTOR_OK`, STOP – nic dalšího neuprav, nic nekomituj, jen nahlas a skonči.
4. Pokud OK, hned udělej drobnou úpravu (zápis do logu/scratch souboru), ať tě systém neuklidí jako
   prázdný worktree, kdyby bylo potřeba další STOP.
```

**Důležité:** kontrola ancestora se dělá **AŽ PO** `git merge --ff-only main`, nikdy před ním – před
mergem je úplně normální a čekané, že worktree má starší `main` (to je přesně to, co merge opravuje).
Kontrola PŘED mergem vždy spadne falešně positivně (stalo se to 3× 8. 10. 2026, než se pravidlo
opravilo) – neopakuj tu chybu.

### 2. Prázdný worktree se automaticky uklidí

Pokud subagent zastaví (např. kvůli STOPu z bodu 1) **bez jediné změny v souboru**, harness jeho
worktree automaticky zahodí – i při `SendMessage`/resume na stejného agenta už není kam se vrátit
(prostředí se změní na hlavní checkout `main`, bez izolace). **Řešení:** buď hned po úspěšné kontrole
udělat drobný zápis (viz bod 4 výše v promptu), nebo při resumu takového agenta rovnou založit **nový**
`Agent` (stejná instrukce, nový `agentId`) místo `SendMessage` na starý.

### 3. Konflikty při mergi vln (sdílené soubory: `PROJECT_LOG.md`, `README.md`, `docs/*.md`,
`prompts/roadmapa/README.md`, `docs/VIZE_A_ROADMAPA.md`, `scripts/game_settings.gd` řádek
`REALISM_ROWS`)

`git merge --no-ff` (ne `--ff-only`, pokud mezitím přibyl jiný commit) → konflikty → **ponech obě
části**, ale **zkontroluj, že `git diff` neduplikoval stejný checkbox/řádek s rozdílným stavem**
(stalo se 8. 10.: M8.5 a M8.6 vyšly v `docs/VIZE_A_ROADMAPA.md` i `prompts/roadmapa/README.md`
každé dvakrát, jednou `[ ]` a jednou `[x]`, kvůli slepému odstranění `<<<<<<<`/`=======`/`>>>>>>>`
markerů bez kontroly obsahu) – po odstranění markerů vždy `grep -c` na klíčový text, že vyšlo přesně
tolikrát, kolikrát má (ne 2×).

### 4. `scripts/world.gd` sdílený mezi paralelními kroky vlny

Dávej subagentům instrukci psát do něj **jen minimální hunky** (nová proměnná, pár řádků na konec
funkce) a slučovat ve **stejném pořadí, v jakém to řekneš subagentům** (orchestrátor si pořadí určí
předem a napíše ho do všech promptů té vlny shodně), ať se merge-conflicty v `world.gd` dají snadno
rozmotat (dosud to nebyl problém, protože agenti M8.1/8.2/8.5/8.6 psali do `world.gd` skutečně jen
minimálně – udrž tenhle disciplinovaný styl).

### 5. Výkonové regrese řešit hned, ne čekat na M8.19

Po vlně 2 našla kontrola výkonu reálnou regresi (ne jen čekaný nárůst z nového kroku) – zbytečné
alokace v hot loopu (`Gait.animate()`) a chybějící throttling (`Humanoid` vzorkoval terén 60×/s).
Uživatel potvrdil, že chce tyhle věci řešit **ihned po každé vlně**, ne nechat nastřádat do M8.19 –
drž se toho: po každém novém `--perfscene` měření porovnej čísla s **předchozí vlnou** (ne jen s
absolutním rozpočtem), a když nějaká kategorie v `PERF profiler` vyroste o desítky % **víc, než
odpovídá nové funkcionalitě**, zadej malého vyšetřovacího subagenta dřív, než spustíš další vlnu.

## Kde hledat detaily

- Plán vln, šablona zadání subagentům, tabulka sdílených souborů: `00_START_M8.md`.
- Společná API, jednotky, výkonový rozpočet, offline generátory: `00_PRINCIPY.md`.
- Testovací checklisty a naměřená čísla: `docs/testy_M8.md`.
- Historie kroků a otevřené body: poslední záznamy `PROJECT_LOG.md` (hledej „M8.1“, „BPEJ“, „M8.2“,
  „M8.5“, „M8.6“, „Oprava regrese výkonu“).
