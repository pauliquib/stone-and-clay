# M2.10 – Náklad a přeprava (rameno, ve dvou, kufr, nosič motorky) + ruční vozík

> Roadmapa „Život na vsi“ · **M2 Řemesla a venkov** · krok 10/10
> Předpoklady: M0.4 (základ nákladu, G), M2.1 (špalky), M2.9 (`Carcass`), M1.6 (`kufr_l`, `nosic`) · Navazují: M4.6 (kontrola kufru, viditelnost úlovku), V2 (nesení ve dvou s druhým hráčem)

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md`
2. `docs/VIZE_A_ROADMAPA.md` – kap. 4.2 „Přeprava úlovku a ruční vozík (U3)“ (včetně **divočák jen ve dvou / autem / vozíkem**)
3. `scripts/player.gd` – `load_kind`, `load_kg` (M0.4), výpočet rychlosti a skoku, `is_sprinting`
4. `scripts/prop.gd` a v `world.gd` `_prop`, `_spawn_props` (fyzikální bedny a sudy u domu – **vzor tlačeného předmětu**)
5. `scripts/car.gd` – `setup`, `two_wheeler`, hmotnost (`mass`), `_balance` (jednostopá), kde je model (`CarModel`/`BikeModel`)
6. `scripts/humanoid.gd` – pózy paží, `hold`, IK paží (`_arm_ik`) – nesení na rameni / tlačení vozíku
7. `scripts/persona.gd` – `friendship` (M0.6), `scripts/villager.gd` – jak vesničan chodí / následuje (grep `follow|target`)

## 1. Proč
Zvěř, dřevo, úroda i materiál se nenosí v kapse. Uživatel stanovil: úlovek se nese **na rameni**, **v autě**,
**na nosiči vzadu na motorce**, nebo na **ručním vozíku** (nový předmět). **Divočák jen ve dvou, v autě, nebo
na ručním vozíku.** Stejný systém použijí špalky, pytle, materiál.

## 2. Návrh
### 2.1 Náklad jako data
`ItemsDB` / nová tabulka `CARGO` v `scripts/cargo.gd` (`class_name Cargo`): druh → `{kg, size: "small"|"medium"|"large",
shoulder: bool, two_person: bool, bike_rack: bool, visible_tag: "zverina"|"drevo"|"material"|...}`:
| Náklad | kg | Rameno | Ve dvou | Nosič motorky | Kufr | Vozík |
|---|---|---|---|---|---|---|
| zajíc | 4 | ano | – | ano | ano | ano |
| srnec | 18–25 | ano (pomalu) | ano | ano (horší ovládání) | ano | ano |
| divočák | 50–120 | **ne** | **ano** | **ne** | ano (auto) | ano |
| špalek | 15 | ano | – | ano | ano | ano |
| pytel (brambory, zrní) | 25 | ano | – | ano | ano | ano |
`Carcass` (M2.9) a další objekty ve světě dostanou `cargo_kind` a jdou zvednout **G**.

### 2.2 Na rameni (jeden hráč)
- G u objektu → hráč ho nese (objekt se připne k `Humanoid` – rameno, animace paže drží), `load_kg`.
- Pohyb: bez sprintu a skoku, rychlost `× clamp(1 − kg/60, 0.35, 0.9)`, výdrž ubývá (i při chůzi) úměrně kg,
  při výdrži 0 hráč náklad **upustí**. Opilý s nákladem → častější zakopnutí (existující potácení).
- **Viditelnost:** nesená zvěřina je dobře vidět – `World.visible_cargo(id)` vrací tag; vesničané / hajný / policie
  v dohledu (zrak – vzor `_witnesses` v `reputation.gd`) ji „vidí“ → M4.6 (teď jen `emit_game_event("cargo_seen", {...})`).
- G = položit (objekt znovu ve světě na zemi).

### 2.3 Ve dvou (divočák)
- Pomocník: vesničan s `friendship ≥ 40` (M0.6) nebo zaplacený (200 Kč) – E u vesničana → „Pomoz mi něco odnést“.
  Vesničan jde s hráčem (následování, jako pes/kůň – najdi vzor), u nákladu G → oba drží (vizuálně: náklad mezi
  nimi na tyči / za nohy, jednoduše: objekt mezi dvěma body rukou), pohyb **pomalý** (max 1,2 m/s), hráč určuje
  směr, vesničan kopíruje (držet vzdálenost 1,6 m). Pomocník odmítne, když ví, že jde o pytláctví a má přísnou povahu
  (`trait == "prisny"`) → a může to i nahlásit (šance). V2: druhý hráč místo NPC (háček `two_person_partner`).

### 2.4 V autě (kufr) a na nosiči motorky
- U auta s nákladem: G u zadní části → „Naložit do kufru“ (kapacita `kufr_l` → hmotnost / objem: zjednodušeně
  `kufr_l / 10` kg, pickup a dodávka velké; divočák se vejde jen do kombi / dodávky / pickupu). Náklad v kufru je
  **neviditelný** (policie může při kontrole prohledat – M4.6), hmotnost zvýší `mass` auta (horší brzdění).
  „Vyložit“ u auta → objekt vedle auta.
- Motorka (`nosic: true`): „Naložit na nosič“ jen `bike_rack` náklady; náklad je vidět, hmotnost zhorší ovládání
  (víc kmitá, delší brzdná dráha, v zatáčce hůř drží – přičti hmotnost a posuň těžiště dozadu v `_balance`).
  Kolo: jen malé (zajíc, pytel do 15 kg).
- Ukládání: náklad v kufru / na nosiči u vozidla.

### 2.5 Ruční vozík (nový objekt)
- Předmět `rucni_vozik` (koupit za 2 490 Kč – Potraviny, později stavebniny M5.1), po koupi stojí u domu hráče.
- Model (MeshKit): korba ~1,2 × 0,8 m, dvě kola ø 0,5 m, oj s madlem; `RigidBody3D` (~25 kg) se dvěma koly
  (jednoduše: `RigidBody3D` s nízkým třením ve směru jízdy – vzor `Prop`, nebo `VehicleBody3D` se 2 koly a opěrnou nohou).
- **Ovládání:** E u madla → hráč uchopí oj (ruce na madle – IK), vozík jede za hráčem (kloub / táhnutí silou k bodu za hráčem),
  otáčení po oblouku. E znovu = pustit (vozík stojí, na svahu **může ujet** – ruční brzda: pustit s „zabrzdit“ = podložené kolo).
  Tlačení do kopce: rychlost podle sklonu a hmotnosti (pomalu), výdrž. Z kopce vozík tlačí hráče (musí brzdit – S).
- Nakládání: G u vozíku s nákladem → na korbu (až ~200 kg: divočák, 6 špalků, 5 pytlů), objekty leží v korbě
  (připnuté, ne volná fyzika). **Plachta** (`plachta` z Potravin) → akce `zakryt` → náklad není vidět.
- Vozík na silnici: AI auta ho objíždějí jako překážku (je v `traffic` jako překážka? – najdi, jak se detekují popelnice).
- Ukládání: pozice vozíku, náklad, plachta.

## 3. Minimum
Rameno (zajíc, srnec, špalek), kufr auta, ruční vozík s nakládáním; divočák jen vozík / auto. Ve dvou a nosič mohou do otevřených bodů.

## 4. Hotovo, když
- Srnec jde dopravit domů na rameni, v kufru, na nosiči motorky a na vozíku; divočák jen ve dvou, v autě nebo na vozíku.
- Vozík jde tlačit / táhnout, na svahu ujede, nese i dřevo a úrodu, plachta skryje náklad; vše se ukládá.

## 5. Návrh checklistu ručních testů
1. Ulovený / F2-spawnutý srnec (přidej do F2 → Příroda „položit mrtvého srnce“ pro test): G → na rameni, pomalá chůze, bez sprintu.
2. Divočák: G → „Sám ho neuneseš.“
3. Vesničan s přátelstvím / za 200 Kč → nesete divočáka spolu, pomalu.
4. Srnec do kufru auta → není vidět; jízda – auto těžší.
5. Srnec na nosič Javoru → vidět vzadu, motorka se hůř ovládá.
6. Kup vozík; E → táhni ho; naložit 6 špalků; do kopce pomalu; pusť na svahu → ujede; zabrzdi.
7. Plachta na vozík → náklad schovaný.
8. F5/F9 → vozík a náklad v kufru zůstanou.

## 6. Závěr
README (Systémy → Náklad a vozík, Ovládání → G, E u vozíku), VIZE odškrtnout, roadmapa README, PROJECT_LOG,
deník AI, commit „M2.10 Náklad a ruční vozík: …“, checklist a čekat.
