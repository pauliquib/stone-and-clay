# Vlastní vozidla ve hře Dukelčice

Jak přidat nové auto (procedurálně nebo z vlastního 3D modelu z Blenderu), jak ho vyladit
a jak přidat další kolo či motorku. Úpravy mapy popisuje [`BLENDER_UPRAVY.md`](BLENDER_UPRAVY.md).

---

## 1. Jak vozidla fungují

| Soubor | Co dělá |
|---|---|
| `scripts/car_model.gd` (`CarModel`) | **katalog vozidel** `MODELS` (rozměry, motor, převodovka, světla) + stavba modelu auta |
| `scripts/bike_model.gd` (`BikeModel`) | model kola a motorky (rám, vidlice, kliky, drátová kola) |
| `scripts/car.gd` (`Car`) | fyzika (`VehicleBody3D`: 4 paprsková kola s pružením), motor, převodovka, brzdy, nárazy, AI řidič, kamera, světla, zvuk |
| `scripts/traffic.gd` (`Traffic`) | kdo jakým vozidlem jezdí: auto a kola hráče, zaparkovaná a AI auta |
| `scripts/humanoid.gd` | póza řidiče / jezdce (ruce na volantu, nohy na pedálech – IK) |

Každé vozidlo je záznam v `CarModel.MODELS` pod krátkým **id** (`"octavia"`, `"fabia"`, `"sedan120"`,
`"van"`, `"kolo"`, `"jawa"`). Typ určuje klíč `kind`:

- `"car"` (výchozí) – auto: karoserie z klíčových řezů (varianta A) nebo z `.glb` modelu (varianta B),
- `"bike"` – kolo (šlape se, bez motoru), `"moto"` – motorka. Jednostopá vozidla mají fyzikálně
  4 kola na úzkém rozchodu + stabilizaci náklonu, vidět jsou 2 kola uprostřed a vozidlo se naklání do zatáček.
  Výjimka: motorky s `lean_max` > 0 (`armadka`, `krosak`) jedou na **reálné jednostopé fyzice** – jen
  dvě kola v ose, podvozek se fyzikálně překlápí do náklonu a stabilitu drží náklonový regulátor
  v `Car._balance` (gyroskopická složka roste s rychlostí, cílový náklon je omezený přilnavostí
  atan(mu) i počasím).

Souřadnice vozidla (Godot): **+Z dopředu, +X doleva (strana řidiče), Y nahoru**, počátek na zemi
uprostřed rozvoru. Vše v metrech.

---

## 2. Varianta A – procedurální auto (bez Blenderu, nejrychlejší)

Karoserie se „nafoukne“ z příčných řezů. Zkopíruj v `CarModel.MODELS` podobné auto a uprav čísla:

```gdscript
"trabant": {
	"name": "Trabant 601", "wb": 2.02, "track": 1.2, "wheel_r": 0.28, "mass": 720.0,
	"power_kw": 19.0, "torque": 54.0, "rpm_max": 4200.0, "gears": [4.08, 2.32, 1.52, 1.03],
	"final": 4.33, "drag": 0.42, "fwd": true,
	"keys": [
		# [z, y_spodek, y_linie_oken, y_střecha, půlšířka_spodek, půlšířka_linie, půlšířka_střecha, skleník, zóna]
		[-1.75, 0.38, 0.8, 0.82, 0.7, 0.74, 0.7, 0.0, 0],
		[-1.68, 0.28, 0.85, 0.87, 0.74, 0.76, 0.72, 0.0, 0],
		[-1.1, 0.27, 0.86, 1.36, 0.75, 0.76, 0.6, 1.0, 2],
		[-0.9, 0.27, 0.86, 1.4, 0.75, 0.76, 0.62, 1.0, 1],
		[0.45, 0.27, 0.86, 1.4, 0.75, 0.76, 0.63, 1.0, 1],
		[0.6, 0.27, 0.86, 1.36, 0.75, 0.76, 0.64, 1.0, 2],
		[1.05, 0.27, 0.84, 0.88, 0.75, 0.76, 0.7, 1.0, 2],
		[1.15, 0.28, 0.83, 0.85, 0.75, 0.75, 0.7, 0.0, 0],
		[1.62, 0.3, 0.76, 0.77, 0.72, 0.73, 0.68, 0.0, 0],
		[1.72, 0.4, 0.66, 0.67, 0.64, 0.66, 0.6, 0.0, 0],
	],
	"b_pillars": [-0.2], "head_z": 1.64, "head_y": 0.64, "tail_z": -1.7, "tail_y": 0.74,
},
```

**Klíčové řezy** (`keys`) jdou od zadku (nejmenší `z`) dopředu. Mezi řezy se lineárně interpoluje.
- `y_spodek` – spodní hrana karoserie (podběhy kol se vyříznou samy podle `wb` a `wheel_r`),
- `y_linie_oken` – hrana, kde končí plech a začínají okna (u kapoty/kufru = horní plocha),
- `y_střecha` – nejvyšší bod řezu (u kapoty jen o pár cm víc než linie oken),
- tři půlšířky – dole, na linii oken, na střeše (auto se zužuje nahoru),
- `skleník` 0 = kapota / kufr (plech), 1 = kabina (okna),
- `zóna` 0 plech, 1 boční okna, 2 čelní / zadní sklo.
- `b_pillars` – polohy `z` sloupků mezi bočními okny, `head_*` / `tail_*` – světla (z, výška).

**Jízdní vlastnosti:**

| klíč | význam | tip |
|---|---|---|
| `mass` | hmotnost (kg) | lehčí = svižnější, víc se odráží při nárazu |
| `wb`, `track`, `wheel_r` | rozvor, rozchod, poloměr kola (m) | určují polohu kol i podběhů |
| `torque` | max. točivý moment motoru (Nm) | síla na kole = moment × převod × stálý převod × 0,9 / `wheel_r` |
| `rpm_max` | omezovač otáček | křivka momentu: 55 % při volnoběhu, 100 % ve středu, 72 % u omezovače |
| `gears`, `final` | převodové stupně, stálý převod | automat řadí sám; méně stupňů = delší rozjezd |
| `drag` | odpor vzduchu (N/(m/s)²) | max. rychlost je tam, kde síla motoru = `drag` × v² |
| `fwd` | pohon předních kol | `false`/chybí = zadní (kromě Octavie a Fabie) |
| `power_kw`, `name` | jen informace (HUD) | |

Pružení, přilnavost a těžiště jsou v `car.gd` → `_ready()` (`suspension_stiffness`, `wheel_friction_slip`,
`center_of_mass`; jiné těžiště pro jedno vozidlo dáš klíčem `"com_y"`).

---

## 2b. Katalogová pole (M1.6)

Ke každému záznamu patří (kromě fyziky):

| klíč | význam |
|---|---|
| `kategorie` | osobní / dodávka / pickup / traktor / motorka / skútr / moped / kolo |
| `skupina_rp` | řidičské oprávnění (`AM`, `A1`, `A2`, `A`, `B`, `T`) – využije M4.1, zatím se nevynucuje |
| `cena`, `rok` | bazarová cena (Kč, 0 = nenabízí se) a základní rok výroby; bazar rok i cenu náhodně mění |
| `kufr_l` | objem kufru v litrech (M2.10: `Car.trunk_liters()`) |
| `nosic` | zadní nosič (jednostopá; `Car.has_rack()`) |
| `tazne_kg`, `hitch` | nosnost tažného zařízení a jeho místo (lokálně); `Car.attach_trailer(tělo, hmotnost)` |
| `bed` | ložná plocha pickupu: `{"c": střed podlahy, "size": šířka × výška × délka}`; `Car.cargo_bed()` |
| `boxy`, `single_row` | dodávková kabina (zasklení bez zadního okna, těžiště výš, tužší pružení); jen jedna řada sedadel |
| `builder` | zvláštní stavitel modelu: `"tractor"` (`TractorModel`), u jednostopých `"jawa"`, `"moped"`, `"scooter"`, `"bicycle"`, `"armadka"` (vojenská), `"krosak"` (kroska) |
| `susp`, `ai_vmax`, `tire_w` | tuhost pružení, strop rychlosti AI (m/s), šířka pneumatiky jednostopého |
| `grip`, `stab` | násobič přilnavosti pneu (výchozí 1,0) a tuhost samovyvažování jednostopého (výchozí 1,0) |
| `steer_v`, `steer_hi`, `steer_rate` | útlum řízení s rychlostí: rychlost dosažení minima (m/s), minimální vytočení (rad), rychlost náběhu řízení |
| `lean_max`, `lean_yaw` | jednostopá fyzika (motorky): `lean_max`>0 přepne vozidlo na 2 kola v ose a fyzikální náklon; `lean_max` = max. cílový náklon (rad, navíc omezený atan(mu) přilnavosti i počasím), `lean_yaw` = síla yaw momentu z náklonu (camber thrust, cílí na rovnovážnou zatáčku g·tan(roll)/v) |
| `lean_steer`, `countersteer` | svod řízení – přední kolo se samo skládá do náklonu (rad řízení na rad náklonu, ~0,28) a protizatáčení – krátký opačný kop řídítek při náhlé změně vstupu (s, ~0,02) |
| `glb` | cesta k vlastnímu modelu (`res://assets/models/vozidla/….glb`); použije se, jen když soubor existuje a je naimportovaný, jinak zůstává procedurální model |

Modely z `.glb` dodej do `assets/models/vozidla/` (doporučené CC0 zdroje: Kenney Car Kit, Quaternius Cars),
odbranduj (bez log a značek), zapiš do `assets/LICENSES.md` a nastav `glb`. Postup exportu viz níže (varianta B).

---

## 3. Varianta B – vlastní model z Blenderu (.glb)

Karoserie je tvůj model, kola jsou procedurální (nebo taky vlastní), fyzika z `MODELS`.

### 3.1 Modelování v Blenderu

1. **Měřítko 1:1 v metrech** (délka Octavie 4,7 m). Po modelování `Ctrl+A → All Transforms`.
2. **Orientace:** předek auta směrem k **−Y** Blenderu (v pohledu *Front*, `Numpad 1`, vidíš masku),
   strana řidiče (levá) = **+X**, střecha nahoru (+Z).
3. **Počátek (origin)** = bod na zemi uprostřed mezi přední a zadní nápravou, uprostřed šířky.
   (3D kurzor na [0, 0, 0], model posuň tak, aby kola stála na rovině Z = 0.)
4. **Bez kol** – kola přidá hra. Nech prázdné podběhy. Středy kol musí být v:
   `X = ±track/2`, `Y = ∓wb/2` (přední náprava Y = −wb/2), `Z = wheel_r`.
5. Materiály: *Principled BSDF* (barva, metalíza, drsnost, textury, průhlednost skel) – glTF je přenese.
   Svítící plochy světel nech normální – hra dá na místa `head_*` / `tail_*` vlastní svítící body.
6. Rozumná složitost: do ~30 000 trojúhelníků, textury do 2k.
7. Interiér stačí jednoduchý (sedadla, palubní deska, volant) – je vidět z pohledu řidiče (`V`).

### 3.2 Export

`File → Export → glTF 2.0`:
- *Format*: **glTF Binary (.glb)**
- *Include*: **Selected Objects** (vyber karoserii a interiér, ne kola)
- *Transform*: **+Y Up** (výchozí – Blender Z nahoru se převede na Y hry)
- *Data → Mesh*: **Apply Modifiers**
- ulož do **`models/trabant.glb`** (složku vytvoř)

Vlastní kolo (volitelné): samostatný `.glb` s jedním kolem, **střed kola v počátku, osa otáčení = osa X**
Blenderu, např. `models/trabant_kolo.glb`. Hra použije první mesh ze souboru pro všechna 4 kola.

### 3.3 Záznam v katalogu

Do `CarModel.MODELS` (souřadnice **hry**: Godot `x = x_B`, `y = z_B`, `z = −y_B`):

```gdscript
"trabant": {
	"name": "Trabant 601", "scene": "res://models/trabant.glb",
	# "wheel_scene": "res://models/trabant_kolo.glb",
	"wb": 2.02, "track": 1.2, "wheel_r": 0.28, "mass": 720.0,
	"power_kw": 19.0, "torque": 54.0, "rpm_max": 4200.0, "gears": [4.08, 2.32, 1.52, 1.03],
	"final": 4.33, "drag": 0.42, "fwd": true,
	"head_z": 1.64, "head_y": 0.64, "tail_z": -1.7, "tail_y": 0.74,
	"seat": Vector3(0.33, 0.1, -0.3),            # řidič – viz níže
	"steering_wheel": Vector3(0.33, 0.92, 0.12), # střed volantu
	"floor_y": 0.33,                             # výška podlahy u pedálů
},
```

- **`seat`**: `x` = střed sedadla řidiče (kladné = vlevo), `y` = **výška horní plochy sedáku − 0,46**,
  `z` = střed sedáku (Godot z = −Y z Blenderu). Postava se posadí tak, aby pánev byla na sedáku,
  ruce dosáhnou na `steering_wheel` a chodidla na pedály 0,78 m před sedákem ve výšce `floor_y`.
- Rozměry a kolize (kvádr podle obálky modelu se zvednutým spodkem) se spočítají samy.
- SPZ si namodeluj přímo do karoserie (u vlastních modelů hra štítky nekreslí).
- Deformace karoserie při nárazu u vlastních modelů není (poškození, kouř a výkon motoru fungují).

### 3.4 Import a zkouška

```bash
cd stone-and-clay
./run.sh -- --drive=trabant
```
`run.sh` pozná nový soubor v `models/` a nechá ho Godot naimportovat (nebo ručně:
`godot --headless --path . --import`). `--drive=<id>` přistaví vozidlo vedle auta hráče a posadí tě do něj.

Kontrola: auto stojí koly na zemi (ne ve vzduchu, ne zabořené), kola jsou v podbězích, postava sedí
za volantem, nohy nekoukají pod podlahou, světla (`L`) svítí z míst světlometů, brzdová světla při `S`.
Když auto „plave“ nebo je zabořené, posuň model v Blenderu ve Z (počátek = země).

---

## 4. Kde se vozidlo ve hře objeví

- **Auto hráče:** `traffic.gd` → `spawn_player_car()` – změň `make_car("octavia", barva, …)` na svoje id.
- **Kola a motorky hráče:** `spawn_player_bikes()` – seznam `[id, barva, jméno uzlu]`.
- **Zaparkovaná a AI auta:** `Traffic.AI_WEIGHTS` / `Traffic.PARKED_WEIGHTS` – slovníky `id → váha` (vyšší váha = častěji);
  traktor řeší `Traffic._update_tractor` (sezóna, okresky), rychlostní strop vozidla dává klíč `ai_vmax` (m/s).
- **Bazar:** `bazaar.gd` nabízí každý model s `cena > 0`; nový model se tam objeví sám.
- **Policie:** `police.gd` (`make_car("octavia", …, true, "POLICIE")`) – policejní polepy a majáky
  se staví jen na procedurálních autech (varianta A).

---

## 5. Nové kolo nebo motorka

Jednostopá vozidla staví `BikeModel` z kódu. Nové id s jiným nastavením:

```gdscript
"cz175": {
	"kind": "moto", "builder": "jawa", "name": "ČZ 175", "wb": 1.3, "track": 0.66, "wheel_r": 0.31,
	"mass": 215.0, "power_kw": 8.0, "torque": 15.0, "rpm_max": 5500.0, "gears": [3.0, 1.8, 1.3, 1.0],
	"final": 6.4, "drag": 0.33, "com_y": 0.42, "snd_pitch": 1.7,
	"head_z": 0.64, "head_y": 1.01, "tail_z": -0.93, "tail_y": 0.64, "hull": [0.34, 0.3, 1.05, 1.0],
},
```

Klíče navíc: `builder` – která funkce v `bike_model.gd` model postaví (`"bicycle"`, `"jawa"`, `"moped"`,
`"scooter"`, `"armadka"` nebo `"krosak"`),
`hull` – kolizní kvádr `[půlšířka, spodek, půldélka, vršek]`, `com_y` – výška těžiště (fyzika),
`snd_pitch` – výška zvuku motoru. Pro kolo (`"kind": "bike"`) místo motoru: `push` (síla šlapání, N)
a `vmax` (max. rychlost šlapáním, m/s).

Jiný vzhled = nová funkce v `bike_model.gd`: zkopíruj `_jawa()` (nebo `_bicycle()`), uprav tvary
(`tube()` = trubka mezi dvěma body, `fender()` = blatník, `kp` = díly v barvě laku, `kt` = chrom/guma/kůže,
`kf` = vidlice a řídítka, která se natáčejí), a přidej větev do `match` na začátku `BikeModel.build()`.
Na konci funkce nastav `m.seat` a `m.rider` (kyčle, předklon, úchop řídítek, stupačky / kliky) –
postava pak na vozidle sedí správně.

---

## 6. Pasti

- Model otočený o 180° (jezdí pozpátku) → předek musí mířit k **−Y** Blenderu.
- Model 100× větší / menší → měřítko v metrech, aplikované transformace.
- Nové `.glb` bez importu → Godot hlásí, že soubor nelze načíst; spusť `run.sh` nebo `--import`.
- Obálka modelu určuje kolizi: dlouhá anténa nebo tažné zařízení ji zvětší (auto „narazí“ dřív).
- `id` musí být unikátní; `"name"` se zobrazuje v HUD a ve zprávě po nastoupení.
- Hodně výkonné lehké auto se převrací – zvyš `mass` nebo sniž těžiště (`com_y`).
