# M0.2 – Jednotný katalog předmětů a inventář

> Roadmapa „Život na vsi“ · **M0 Základy** · krok 2/6
> Předpoklady: M0.1 (nepovinně) · Navazují: M0.3 (XP za předměty), M0.4 (nástroje), celé M2–M6

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md`
2. `docs/VIZE_A_ROADMAPA.md` – kap. **3.2 Předměty, inventář a řemeslo**
3. `scripts/consumables.gd` (celý, 92 ř.), `scripts/item.gd` (celý, 162 ř.)
4. `scripts/player.gd` – jen `add_item`, `item_count`, `sips_left`, `remove_item`, `use_item`, `consume_served`, `_begin`, `_finish_action` (grep `func add_item`, čti ~110 řádků)
5. `scripts/hud.gd` – `toggle_inventory`, `_rebuild_inventory` (grep, ~50 ř.)
6. `scripts/save_game.gd` – jak se ukládá `inventory`, `open_ml`, skóre sběru (grep `inventory`)
7. `scripts/world.gd` – `use_item`, `serve`, `buy`, `_on_collected` (grep); `scripts/place.gd` – `OFFERS`

## 1. Proč
Dnes existují dva oddělené katalogy: `Consumables.ITEMS` (jídlo, pití, cigarety, spacák) a `Item.INFO`
(sběratelské předměty – body do skóre). Nové mechaniky (nástroje, dřevo, semena, maso, oblečení,
doklady, zbraně, střelivo…) potřebují **jeden katalog** s typy a vlastnostmi, jinak se každý krok
bude rozrůstat vlastní cestou.

## 2. Návrh
Nový soubor `scripts/items_db.gd`, `class_name ItemsDB` (RefCounted, jen statická data a funkce):

```gdscript
const TYPES := ["drink", "food", "smoke", "gear", "tool", "weapon", "ammo", "material", "seed",
	"clothing", "animal_product", "meat", "fish", "document", "collectible", "misc"]

## id → vlastnosti. Povinné: name, type. Volitelné: short, price, kg (hmotnost 1 ks), stack (max. v jednom
## slotu; 1 = nestackuje), durability (použití do zničení; nástroje), perishable_h (zkazí se za herní hodiny),
## skill_req ({"drevorubectvi": 5}), points (skóre sběru), icon_color, + klíče z Consumables (ml, sip, abv, kcal…)
const ITEMS := { ... }

static func info(id: String) -> Dictionary
static func name_of(id: String) -> String
static func type_of(id: String) -> String
static func weight(id: String) -> float
static func is_stackable(id: String) -> bool
static func exists(id: String) -> bool
static func by_type(t: String) -> Array[String]
```

- `ITEMS` vznikne **sloučením**: všechny položky `Consumables.ITEMS` (ponech jim všechny klíče, doplň
  `type` pokud chybí, `kg`) + `Item.INFO` (typ `collectible`, `points`). Aby se nerozbil stávající kód,
  `Consumables.ITEMS` a `Item.INFO` **zůstanou jako aliasy** (`const ITEMS := ItemsDB.ITEMS` nebo
  funkce, které čtou z `ItemsDB`) – ověř grepem všechna použití (`Consumables.ITEMS`, `Item.INFO`)
  a převeď je na `ItemsDB`, kde je to jednoduché.
- Hmotnost: nápoje podle objemu (0,5 l ≈ 0,8 kg s lahví), jídlo 0,1–0,5 kg, spacák 1,5 kg.
- Přidej už teď (jen data, bez logiky) položky, které použijí další kroky – ať je katalog kompletní:
  `sekera_stara`, `sekera`, `motorova_pila`, `sirky`, `zapalovac`, `polena`, `klesti`, `spalek`,
  `lopata`, `motyka`, `konev`, `semena_*` (brambory, mrkev, cibule, salát), `sazenice_jablon`,
  `udice`, `navnada_zizaly`, `luk`, `kuse`, `puska`, `sipy`, `sipky_kuse`, `naboje`, `plachta`,
  `rucni_vozik` (typ `gear` – předmět ve světě, ne v kapse), dokladové `ridicsky_prukaz` atd. se přidají v M4.
  U zbraní jen `type`, `price`, `kg`, žádná logika.

## 3. Inventář hráče
- `Player.inventory` zůstává `id → počet` (kvůli ukládání a kompatibilitě), přidej:
  - `const CARRY_KG := 25.0` (nosnost; později podle dovednosti / kondice),
  - `func carried_kg() -> float` (součet `ItemsDB.weight × počet`),
  - v `add_item` kontrola přetížení: nad nosnost se předmět **přidá**, ale hráč je přetížený →
    `speed_mult` pohybu × 0,6 a nemůže sprintovat (napoj v `_physics_process`, najdi výpočet rychlosti
    grepem `speed_mult`), hláška „Neseš moc – zpomalíš.“ přes `World.notify`.
  - opotřebení nástrojů: `var durability := {}` (id → zbývá použití pro **aktuální kus**); funkce
    `wear_tool(id, n := 1) -> bool` (při 0 kus zmizí, vrací false když zmizel). Ukládat v `save_game.gd`.
- **Inventář Tab (`hud.gd`):** seskupit podle typu (nadpisy „Jídlo a pití“, „Nástroje“, „Materiál“…),
  u každé položky počet a hmotnost, nahoře „Neseš 12,4 / 25 kg“. Akce zůstávají (napít, sníst,
  zapálit si, rozložit spacák). Nové typy zatím bez akce (jen zobrazit).

## 4. Mimo rozsah
Použití nástrojů (M0.4), obchody s novým zbožím (přidávají jednotlivé kroky), vozík jako objekt (M2.10).

## 5. Minimum (kdyby nestačil kontext)
`ItemsDB` se sloučenými daty + aliasy + hmotnost a nosnost. Seskupení v Tab může počkat.

## 6. Hotovo, když
- Veškerý kód čte předměty z `ItemsDB` (nebo z aliasu), hra se chová stejně: nákupy, pití, jídlo,
  cigarety, spacák, sběr hřibů / dukátů / zlatých žaludů, skóre.
- Stará uložená pozice se načte (inventář, otevřené lahve).
- Tab ukazuje hmotnost a skupiny; přetížení zpomalí.

## 7. Návrh checklistu ručních testů
1. `./run.sh` → Tab: inventář seskupený, nahoře hmotnost.
2. Potraviny: kup pivo a rohlík → přibudou, hmotnost vzroste; vypij / sněz → funguje jako dřív.
3. F2 → Hráč → peníze; kup 10× slivovici → nad 25 kg hláška a pomalejší chůze, sprint nejde.
4. Seber hřib a dukát → skóre roste jako dřív.
5. F9 načti starou pozici (před touto změnou) → inventář a otevřené lahve sedí.
6. Spacák: koupit, Tab → rozložit, vyspat se.

## 8. Závěr
README (Systémy → Předměty, nosnost), VIZE odškrtnout, roadmapa README, PROJECT_LOG, deník AI, commit
„M0.2 Katalog předmětů: …“, checklist a čekat.
