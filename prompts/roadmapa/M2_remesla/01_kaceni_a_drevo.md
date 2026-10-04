# M2.1 – Kácení stromů a zpracování dřeva

> Roadmapa „Život na vsi“ · **M2 Řemesla a venkov** · krok 1/10
> Předpoklady: M0.2, M0.3, M0.4, M0.5 · Navazují: M2.2 (oheň – polena), M2.5 (sázení), M2.10 (odvoz dřeva), M3.3 (práce v lese), M4.4 (přestupky)

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md`
2. `docs/VIZE_A_ROADMAPA.md` – kap. 4.2 „Kácení“
3. `scripts/map_loader.gd` – `build_trees` (ř. ~176–262): formát `trees.bin` (hlavička 8 B, pak 11 × float32 na strom:
   `x, y, z, rot, sx, sy, sz, r, g, b, proto`; proto 0–2 listnáče, 3+ jehličnany), MultiMesh buňky
   „near“ (128 m, jen listnáče) a „far“ (256 m), kolize kmenů = `CylinderShape3D` v `StaticBody3D` na buňku 256 m, `skip` = indexy, které se nestaví
4. `scripts/world.gd` ř. ~150 (`MapLoader.build_trees(map_root, water.drop_trees, terrain)`)
5. `scripts/fauna/fauna.gd` – `trees_near`, `forest_at`, `settle_at` (les vs. zástavba)
6. `scripts/actions.gd`, `scripts/tool_models.gd`, `scripts/skills.gd`, `scripts/law.gd` + `data/zakon.json` (M0.4, M0.3, M0.5)
7. `scripts/priroda/tree_decor.gd` (ovoce v korunách – po pokácení nesmí viset ve vzduchu)

## 1. Proč
Kácení je základní RuneScape činnost: dřevo → polena → oheň, topení, stavby, prodej. Zároveň je to
první činnost, kde záleží na **zákoně** (kde smíš kácet).

## 2. Co udělat
### 2.1 Mapa stromů za běhu
- Uprav `MapLoader.build_trees`, aby vracel/uložil **index**: pro každý strom `i` → `{near_mmi, near_idx,
  far_mmi, far_idx, shape: CollisionShape3D}`. Nový uzel `scripts/tree_manager.gd` (`class_name TreeManager`,
  vlastní ho `World` jako `World.trees`) drží tuto mapu + data stromů (pozice, výška, proto, druh listnáč/jehličnan).
- `TreeManager.hide_tree(i)`: instance ve všech MultiMeshích → nulové měřítko (`set_instance_transform`),
  kolizní tvar `disabled = true`. `felled := {}` (index → herní den pokácení), ukládá se (`save_game.gd`);
  po načtení `hide_tree` pro všechny. `nearest_tree(pos, r) -> int`.
- `TreeDecor` (ovoce) i `Fauna.trees_near` musí pokácené stromy vynechat (přidej filtr `World.trees.is_felled(i)`).

### 2.2 Činnost kácení (registrace do `Actions`)
- Cíl `tree` – `TreeManager` dodá nejbližší strom do 2,5 m od hráče před ním.
- Akce `pokacet` (nástroj `sekera_stara|sekera|motorova_pila`), čas podle průměru kmene (`sx`) a nástroje
  (stará sekera ×1,6, sekera ×1, pila ×0,35), dovednost `drevorubectvi`, úrovně: stará sekera 1, sekera 5,
  pila 20 (+ ochranné oblečení z M2.3 – zatím jen hláška „Bez ochranných pomůcek riskuješ úraz.“ a vyšší šance na zranění `BodyState.hurt`).
- **Pád stromu:** po dokončení se instance skryje a vznikne `RigidBody3D` kmen (procedurální válec + koruna
  z MeshKit, nebo zmenšená kopie proto meshe) nakloněný **ve směru od hráče**, padá fyzikálně (~3 s), zvuk praskání
  a dopadu (`World.sound`), prach / listí částice. Kdo stojí v cestě (hráč, NPC, auto), dostane zásah
  (hráč `hurt`, auto poškození). Zůstane **pařez** (malý válec se statickou kolizí).
- Padlý kmen je cíl `log`: akce `odvetvit` (→ `klesti` × n) a `rozrezat` (→ `spalek` × podle délky; pilou rychleji).
  Špalek je cíl pro `stipat` (sekera, → `polena` × 4). Špalky a polena jsou předměty (hmotnost – špalek 15 kg:
  nese se jako náklad G, ne do kapsy – použij náklad z M0.4, pokud je; jinak do inventáře s hmotností).
- XP: kácení podle velikosti (20–80), odvětvení 5, řezání 8, štípání 3.
- Kmen po 3 herních dnech bez zpracování zmizí (nebo zůstane – ukládá se jen pozice kmene, stačí zjednodušit:
  při uložení se nezpracovaný kmen převede na hromadu špalků na místě).

### 2.3 Zákon (vlastnictví a povolení) – napoj na `World.commit_offense`
- **Kde smíš:** vlastní pozemek = zahrada domu hráče (poloměr ~35 m od `places["domov"].door`, laditelné),
  v zástavbě (`Fauna.settle_at > 0.5`) jde o **cizí zahradu** → přestupek poškození cizí věci + krádež dřeva,
  v lese (`forest_at > 0.5`) bez povolení → krádež dřeva (malá hodnota přestupek, velký strom / víc stromů
  trestný čin – součet hodnoty dřeva za den > 10 000 Kč). Kolem silnic (`dist_to_roads < 8`) – ohrožení provozu.
- **Svědci:** přestupek se zjistí, jen když to někdo vidí nebo slyší (motorová pila je slyšet do 300 m, sekera do 120 m) –
  vesničan / myslivec / policie v dosahu → `commit_offense` hned; jinak šance, že to zjistí hajný později
  (háček pro M4.6 – ulož „nenahlášený čin“ se jménem druhu a pozicí).
- Do `data/zakon.json` přidej: `kaceni_bez_povoleni` (114/1992 Sb., § 8 – orientačně), `kradez_dreva` (251/2016 Sb.
  § 50 / trestní zákoník § 205 nad limit – `par` s „ověřit“).
- Povolení ke kácení (úřad) přijde v M4.4 – teď jen háček `World.has_permit(id, "kaceni", pos)` vracející false.
- Karma: kácení v cizím −2, na vlastním 0.

### 2.4 Prodej a obchody
- Potraviny: sirky, zapalovač; nový stánek „Železářství“ zatím v Potravinách (do M5.1 stavebnin): `sekera_stara` 390 Kč,
  `sekera` 1 290 Kč, `motorova_pila` 6 900 Kč (zatím bez paliva).
- Výkup dřeva: pálenice kupuje polena (palivo pod kotel) 30 Kč/ks – přidej režim „sell“ do nabídky místa (pokud
  neexistuje, přidej obecně do `Place` – prodej z inventáře za cenu).

## 3. Minimum
2.1 + kácení a pařez + štípání na polena + přestupek podle místa (bez svědků – vždy).

## 4. Hotovo, když
- Strom jde pokácet, padá fyzikálně, zůstane pařez; kmen jde zpracovat na polena; vše se ukládá.
- Kácení mimo vlastní zahradu je přestupek (se svědkem hned), na zahradě ne.

## 5. Návrh checklistu ručních testů
1. F2 → Hráč → peníze; kup sekeru; na zahradě u domu hráče LMB na strom → průběh, strom padá od tebe, pařez.
2. Stoupni si do směru pádu → zásah (zdraví dolů).
3. Kmen: odvětvit, rozřezat (sekerou pomalu), špalek rozštípat → polena v Tab; +XP Dřevorubectví.
4. F5, F9 → strom je pořád pokácený, pařez stojí, ovoce ve vzduchu nevisí.
5. V lese s motorovou pilou blízko myslivce / vesničana → přestupek, J → Úřední záznamy.
6. V lese daleko od lidí sekerou → bez okamžitého trestu (zapsaný „nenahlášený čin“ – vidět v logu/ladění).
7. Pálenice → prodej polen.
8. FPS po pokácení 10 stromů beze změny.

## 6. Závěr
README (Systémy → Dřevo), `data/zakon.json`, VIZE odškrtnout, roadmapa README, PROJECT_LOG, deník AI,
commit „M2.1 Kácení a dřevo: …“, checklist a čekat.
