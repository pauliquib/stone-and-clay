# M6.2 – Krajina za okrajem mapy (pohled z výšky) a hranice letu

> Roadmapa „Život na vsi“ · **M6 Létání** · krok 2/5
> Předpoklady: M1.1 (procedurální materiály terénu) · Navazují: M6.3–M6.5 (létání výš a dál)

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md` (kap. 3 – zdroje dat jen ČÚZK / OSM)
2. `docs/VIZE_A_ROADMAPA.md` – kap. 4.6 „Technicky“ a otevřená otázka „jak vysoko a jak daleko“ (kap. 7) –
   pokud není rozhodnuto, **zeptej se** uživatele (výchozí návrh: strop 1 500 m nad terénem, hranice 2 km za katastrem)
3. `scripts/terrain.gd` (celý) – LOD dlaždice, `_add_bounds` (neviditelné zdi na okraji mapy), `contains`
4. `tools/export_map.py` a `README.md` → „Jak vzniká herní mapa“ (odkud je DMR 5G, jaký je rozsah)
5. `scripts/priroda/atmosphere.gd` – mlha, obloha (horizont), `shaders/sky.gdshader`
6. `scripts/map_loader.gd` – `TREE_FAR_RANGE` (jak daleko jsou vidět stromy)

## 1. Proč
Z dronu, paraglidu a rogala je vidět daleko – a mapa končí na hranici katastru (5,2 × 4,6 km). Bez úpravy
by byl vidět „okraj světa“. Potřebujeme levnou krajinu okolí a rozumnou hranici letu.

## 2. Co udělat
1. **Data okolí** – nový nástroj `tools/surroundings.py` (**napiš, nespouštěj**): z DMR 4G/5G ČÚZK (nebo z hrubšího
   výškového modelu, který projekt už má – zjisti v `export_map.py` / `geodata/`) vytvoří **nízkorozlišenou výškovou mřížku**
   okolí ~10 × 10 km (za okrajem katastru ~2,5 km na každou stranu, případně víc) s krokem **20–30 m** → `data/surround_height.bin`
   (formát jako `terrain_height.bin` + hlavička s x0, z0, krok, nx, nz). Dále hrubou masku povrchu (les / pole / louka /
   zástavba / voda) z OSM ve stejném kroku → `data/surround_surface.bin`. Popiš v README, co je potřeba stáhnout (dlaždice
   DMR z ČÚZK – odkaz na open data) a jak nástroj spustit.
2. **Vykreslení okolí** – `scripts/surroundings.gd` (`class_name Surroundings`): jedna nebo několik velkých LOD dlaždic
   (mřížka 64×64 quadů na dlaždici 2 km), výšky ve vertex shaderu (vzor `terrain.gdshader`), barvy podle masky (sdílená
   paleta s M1.1), **vynechat oblast katastru** (díra – aby se nepřekrývalo s detailním terénem; okraj zapustit o 1–2 m pod detail).
   Bez kolizí. Les jako **tmavší texturovaný povrch + levné „boule“** (bez stromů, nebo MultiMesh velmi hrubých kuželů jen
   do 4 km). Obce v okolí jako skvrny zástavby (žádná jména, žádné detaily).
   Když `data/surround_height.bin` neexistuje → fallback: plochý „prstenec“ ve výšce průměru okraje s mlhou (aby hra fungovala).
3. **Mlha a horizont:** vzdušná perspektiva (`Environment` fog – výšková a vzdálenostní) nastavit tak, aby okolí za ~6–8 km
   splynulo s oblohou; při létání (výška > 150 m) zvýšit dohled (plynule).
4. **Hranice letu:** pro létající prostředky (dron, M6.3+) – nad hranicí katastru + N km měkké odpuzení (vítr proti, varování
   „Dál už nelétej – opouštíš oblast“), strop výšky (ze zadání). Chodec / auto – stávající `_add_bounds` beze změny.
5. **Výkon:** okolí max. ~100 draw callů, žádné stíny, nízká hustota; LOD stromů v katastru (`TREE_FAR_RANGE`) případně
   prodloužit, když je hráč vysoko (parametr).

## 3. Minimum
Fallback prstenec + mlha + hranice letu; nástroj `surroundings.py` napsaný (uživatel spustí později).

## 4. Hotovo, když
- Z výšky 300–1 000 m nad obcí není vidět okraj světa; okolní krajina navazuje na katastr (výškově i barevně) a mizí v mlze;
  létající prostředky mají hranici; chodec a auto beze změny; FPS v pořádku.

## 5. Návrh checklistu ručních testů
1. (Po spuštění nástroje) `python3 tools/surroundings.py` → `data/surround_*.bin`, výpis rozsahu.
2. Dron (M6.1) nebo F2 cheat „kamera 500 m nad obcí“ (přidej volný let kamery do F2 pro test) → okolí za katastrem, bez díry a švů.
3. Navázání na okraji katastru: žádný schod / mezera.
4. Mlha: vzdálené kopce splývají s oblohou; v mlhavém počasí dohled menší.
5. Let k hranici → varování a vítr proti.
6. FPS nahoře i dole podobné jako dřív.

## 6. Závěr
README (Jak vzniká mapa – okolí, Licence dat), VIZE odškrtnout (a vyřešenou otázku), roadmapa README, PROJECT_LOG, deník AI,
commit „M6.2 Krajina za okrajem mapy: …“, checklist a čekat.
