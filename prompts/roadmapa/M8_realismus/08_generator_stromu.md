# M8.8 – Generátor stromů: tvary podle druhu, věku a vitality (offline) + LOD a impostory

> Roadmapa **M8 Realistický svět** · krok 8/19 · vlna 4
> Předpoklady: **M8.3 (druhy, `TreeEco`)**, **M8.4 (konvence barev vrcholů, `wind.gdshaderinc`)** · Navazují: M8.11 (růst mění variantu), M8.19
> Dodržuje: 00_PRINCIPY kap. 4 (barvy vrcholů), kap. 7 (offline generátory)

## 0. Než začneš – přečti
1. `00_SPOLECNE.md`, `M8_realismus/00_PRINCIPY.md` (kap. 4, 6, 7, 8 – generování stromů)
2. `scripts/map_loader.gd` – `build_trees`, `_proto_mesh`, `_low_dec_mesh`, `_mmi`, konstanty `TREE_CELL`, `TREE_FAR_CELL`, `DEC_FULL_RANGE`,
   `TREE_FAR_RANGE` (formát `tree_protos.bin` DBT1 – čti `_proto_mesh`)
3. `tools/export_map.py` – jak vznikají prototypy z Blenderu (`grep -n "proto" tools/export_map.py`)
4. `shaders/tree.gdshader` (po M8.4 s `wind_bend`), `scripts/planted_trees.gd` (sdílí `shared_protos`), `scripts/tree_manager.gd` (kácení – indexy MultiMesh)
5. `data/dreviny.json` (M8.3), `scripts/eko/tree_eco.gd`
6. `tools/gen_vegetation_meshes.gd` – vzor offline generátoru meshů v projektu

## 1. Proč
Všech ~51 700 stromů je dnes 6 tvarů (3 listnaté, 3 jehličnaté). S druhy (M8.3) a vitalitou má mít buk hladký šedý kmen a hustou kopuli,
dub křivé větve a nepravidelnou korunu, bříza bílou kůru a převislé větvičky, smrk kužel s přesleny, borovice holý kmen a deštník nahoře,
strom na mělké půdě zakrslý a křivý, v nivě vysoký a rovný. Žádný hotový nástroj tohle nepropojí – generátor je náš.

## 2. Co udělat
- **Offline generátor `tools/treegen/`** (Python + numpy, deterministický; **bez Blenderu**, ať běží všude – Blender headless jen volitelně
  pro náhled `--preview` do PNG):
  - **Listnáče – space colonization** (Runions et al. 2007): body „pupenů“ v obálce koruny podle druhu (kopule, vejčitá, nepravidelná,
    převislá), iterace růstu s délkou segmentu, úhlem a tropismy (geotropismus, fototropismus vzhůru, gravitace u převislých), **pipe model**
    pro tloušťky (r_rodič² = Σ r_děti²), apikální dominance podle druhu.
  - **Jehličnany – přeslenový model:** kmen s přesleny po ročních přírůstcích, větve 1. řádu s úhlem a délkou podle výšky (kužel smrku,
    vyvětvený kmen borovice se zploštělou korunou, modřín řídký), větve 2. řádu krátké.
  - **Parametry z `data/dreviny.json`** (nové klíče `tvar`: obálka, úhly, délky, tropismy, ohebnost) + vstupy **věk** a **vitalita**:
    nízká vitalita → kratší přírůstky, víc odumřelých větví, kroucení (gnarl), řidší listí, nižší koruna; vysoká → rovný kmen, hustá symetrická koruna.
  - **Mesh:** větve jako zobecněné válce (segmenty podle LOD), **listí jako karty** (quady s alpha texturou trsů listů) rozložené na koncových
    větvích, jehličnany „větvičkové“ karty; **barvy vrcholů podle 00_PRINCIPY kap. 4** (r ohebnost od kmene, g fáze větve, b list, a okluze –
    okluze z hloubky v koruně).
  - **Textury procedurálně (Pillow/numpy):** atlas listů pro každý druh (silueta tvaru listu – dub laločnatý, buk vejčitý, bříza trojúhelníkovitá,
    javor dlanitý; jehličí), kůra (buk hladký šedý, dub brázditý, bříza bílá s černými pásky, borovice šupinatá oranžová nahoře) – 512² na druh,
    jeden atlas.
  - **LOD:** LOD0 (do ~60 m), LOD1 (zjednodušené větve, větší karty, ~25 % trojúhelníků), **impostor** (oktaedrický nebo aspoň 8 pohledů
    vypečených do atlasu – barva + normála, se stejnou fenologickou barvou v shaderu) pro dálku.
  - **Varianty:** na druh 3 vitalita × 2 věkové třídy (mladý / dospělý), staré stromy = dospělý s měřítkem. Rozpočet trojúhelníků:
    LOD0 listnáč ≤ 6 000, jehličnan ≤ 4 000; celkem souborů ≤ 40 MB. Výstup `data/tree_species_protos.bin` (nový formát `DBT2`: hlavička,
    seznam variant `druh, vitalita, věk, lod`, meshe, atlasy jako PNG v `assets/textures/trees/` se záznamem v `assets/LICENSES.md` – vlastní výroba).
- **Hra – `build_trees` za přepínačem `treegen`:** pro každý strom vybrat variantu podle `TreeEco` (druh, vitalita, věk) → skupiny MultiMesh
  po buňkách jako dnes (stejné indexy pro `TreeManager`/kácení – **zachovej `meta` záznamy a mapování indexů**, jinak se rozbije kácení a uložené
  pokácené stromy). Dálka: impostory místo `_low_dec_mesh`. Bez `tree_species_protos.bin` nebo s vypnutým přepínačem = dnešních 6 prototypů.
- **`tree.gdshader`:** alpha scissor pro karty listů (+ alpha to coverage, je-li MSAA), barva listí z atlasu × odstín instance × fenologie
  (M8.11 doplní posun přes `INSTANCE_CUSTOM.a`), **translucence** (BACKLIGHT) proti slunci, kůra z atlasu podle druhu (UV), `wind_bend` z M8.4
  s barvami vrcholů, sníh na horních plochách (jako dnes), podzim po chomáčích (jako dnes).
- **Zasazené stromy (M2.5)** použijí stejné varianty podle druhu a věku sazenice (mladý → dospělý s růstem).
- **Výkon:** draw calls ≤ dnes × 2 (víc variant = víc MultiMeshů – sdružuj druhy se stejným materiálem do atlasu, jeden materiál pro všechny
  listy); měřicí scény `les_rano_mlha`, `dron_200m`. Pokud rozpočet nevychází, sniž počet variant (třeba 2 vitality) a zapiš do logu.

## 3. Minimum
Generátor pro 8 druhů (buk, dub, habr, bříza, olše, smrk, borovice, jabloň) × 2 vitality × 1 věk, LOD0 + LOD1 + jednoduchý billboard,
atlas listů a kůry, integrace do `build_trees` se zachováním indexů pro kácení, přepínač zpět.

## 4. Hotovo, když
- Les z dronu ukazuje rozpoznatelné druhy (kužely smrků, kopule buků, bílé kmeny bříz); strom na mělkém hřbetu je menší a křivější než v nivě.
- Kácení a uložené pokácené stromy fungují stejně jako před krokem.

## 5. Návrh checklistu ručních testů
1. `python3 tools/treegen/treegen.py --preview` → PNG náhledy druhů (porovnat s fotkami – poznáš druh?).
2. Ve hře les zblízka → listy jako karty se siluetou, kůra podle druhu.
3. Dron 200 m nad lesem → impostory v dálce, bez „blikání“ při přepnutí LOD.
4. Hřeben vs. niva → velikost a tvar stromů se liší.
5. Pokácet strom → padá správný strom, pařez; F5/F9 → zůstává pokácený.
6. Podzim → barvení po chomáčích funguje i na nových stromech; zima → sníh na větvích.
7. Vítr → ohyb po úrovních (kmen / větve / listy).
8. Přepínač Generované stromy vypnout → původní stromy.
9. `--perfscene=les_rano_mlha`, `dron_200m` → ms GPU a draw calls (cíl: GPU +≤ 1 ms na Střední).

## 6. Závěr
README (nástroj `tools/treegen`, kdy spustit), `BLENDER_UPRAVY.md` (stromy už nejsou jen z Blenderu – poznámka), `docs/SYSTEMS.md`, PROJECT_LOG,
`docs/testy_M8.md`, commit „M8.8 Generátor stromů: …“.
