# UPGRADE PLÁN PRO STONE AND CLAY (Godot 4.3)

Tento dokument obsahuje kompletní, krok za krokem technický návod pro upgrade fyzikálního jádra, systému interiérů a AI. Je psán pro autonomní implementaci.

## 1. FYZIKÁLNÍ JÁDRO: Migrace na Godot Jolt

**Cíl:** Nahradit Godot Physics 4.3 výkonnějším Jolt fyzikálním enginem pro stabilnější vozidla, letadla a kolize s terénem při 21 800 stromech.

### 1.1 Instalace

- Stáhni godot-jolt release pro Godot 4.3 (soubor `godot-jolt_v0.13.0-stable_godot-4.3-windows.zip` nebo linux ekvivalent).
- Rozbal do kořene projektu tak, aby vznikla struktura:

```plain
/bin/
  jolt_physics.windows.template_debug.x86_64.dll
  jolt_physics.windows.template_release.x86_64.dll
/project.godot (upraveno)
```

- V `project.godot` přidej:

```ini
[physics]
3d/physics_engine="JoltPhysics3D"
```

- Nebo přes GUI: Project Settings → Physics → 3D → Physics Engine → JoltPhysics3D.

### 1.2 Úpravy kódu pro kompatibilitu

**Soubor: `scripts/flight/aircraft.gd`**

- Nahraď `extends RigidBody3D` za `extends RigidBody3D` (beze změny, Jolt je drop-in).
- Odstraň vlastní `_integrate_forces()` a nahraď ho Jolt verzí:

```gdscript
# STARÝ KÓD (odstranit):
# func _integrate_forces(state): ...

# NOVÝ KÓD:
func _ready():
    # Jolt používá jiný default pro continuous collision detection
    continuous_cd = true
    contact_monitor = true
    max_contacts_reported = 8
    
func _physics_process(delta):
    # Přesuň výpočet lift/drag sem místo _integrate_forces
    var velocity = linear_velocity
    var speed = velocity.length()
    # ... výpočet CL, CD podle Aircraft.SPECS ...
    apply_central_force(lift_vector + drag_vector + thrust_vector)
```

- **Důležité:** Jolt má jiný default pro `angular_damp`. Nastav v `_ready()`:

```gdscript
angular_damp = 0.5  # místo 0.0
linear_damp = 0.1   # místo 0.0
```

**Soubor: `scripts/car.gd`**

- Změň `VehicleBody3D` na `RigidBody3D` (Jolt nepodporuje Godot VehicleBody dobře).
- Implementuj vlastní raycast suspension:

```gdscript
@export var suspension_rest_length := 0.6
@export var suspension_stiffness := 35000.0
@export var suspension_damping := 4500.0

func _physics_process(delta):
    for wheel in wheels:  # Array[RayCast3D]
        if wheel.is_colliding():
            var compression = suspension_rest_length - wheel.get_collision_distance()
            var force = suspension_stiffness * compression - suspension_damping * compression_rate
            apply_force_at_position(wheel.global_transform.basis.y * force, wheel.global_position)
```

**Soubor: `scripts/world.gd`**

- Uprav `World.HIT_DAMAGE_K` konstanty – Jolt má přesnější kolize, takže zvýš práh pro poškození při nárazu zvěře o ~15 %.

### 1.3 Validace

- Spusť `--cartest` – pokud projede bez chyb, fyzika funguje.
- Spusť `--faunatest` – ověř, že se zvěř nechová jinak při kolizích s terénem.

## 2. INTERIÉRY: Integrace Qodot (TrenchBroom)

**Cíl:** Nahradit procedurální InteriorGen ručně navrženými mapami pro klíčové budovy (hospoda, úřad, potraviny), zachovat ale generování pro obyčejné domy.

### 2.1 Instalace Qodot

- Stáhni `qodot` z GitHub (release pro Godot 4.3).
- Kopíruj `addons/qodot` do `stone-and-clay/addons/`.
- Povol plugin v Project Settings → Plugins.

### 2.2 Vytvoření mapy v TrenchBroom

- Vytvoř novou mapu v TrenchBroom (Quake 1 formát).
- Použij textury z `assets/textures/interiors/` (vytvoř jednoduché 128x128 PNG textury pro zdi, podlahy).
- Entita `info_player_start` = spawn point hráče u dveří.
- Entita `func_detail` = nábytek (stoly, pult).
- Exportuj jako `hospoda_u_hriste.map` do `data/maps/`.

### 2.3 Integrace do InteriorStreamer

**Soubor: `scripts/interior_streamer.gd`**

- Přidej nový typ generování:

```gdscript
const GEN_KIND := {
    "qodot": 3,  # nový typ
    "procedural": 2,
    "none": 1
}
```

- Uprav `_build_interior()`:

```gdscript
func _build_interior(estate: Estate, kind: int) -> Node3D:
    match kind:
        GEN_KIND.qodot:
            return _build_qodot_interior(estate)
        GEN_KIND.procedural:
            return InteriorGen.generate(estate)
        _:
            return null

func _build_qodot_interior(estate: Estate) -> Node3D:
    var qodot_map := QodotMap.new()
    qodot_map.map_file = "res://data/maps/%s.map" % estate.map_name  # např. "hospoda"
    qodot_map.build()
    
    # Přesunutí pod mapu (stejně jako u procedural)
    qodot_map.global_position = Vector3(0, World.INTERIOR_BASE_Y, 0)
    
    # Přidání interakčních bodů (E)
    _add_interaction_points(qodot_map, estate)
    return qodot_map
```

### 2.4 Konverze souřadnic

- TrenchBroom používá Z-up, Godot Y-up. Qodot to řeší automaticky, ale ověř orientaci:
  - V TrenchBroom: `info_player_start` čelem ke dveřím (východ).
  - Ve hře: Po teleportu do interiéru musí hráč čelit dveřím ven.

### 2.5 Fallback

- Pokud `data/maps/<nazev>.map` neexistuje, fallback na InteriorGen:

```gdscript
if not FileAccess.file_exists(map_path):
    return InteriorGen.generate(estate)
```

## 3. AI: Implementace LimboAI pro vesničany

**Cíl:** Nahradit hardcoded chování ve `villager.gd` za Behavior Trees pro složitější denní rutiny.

### 3.1 Instalace LimboAI

- Stáhni `limboai` (GDExtension release pro Godot 4.3).
- Rozbal `addons/limboai` do projektu.
- Restartuj Godot (načte se GDExtension).

### 3.2 Vytvoření Behavior Tree pro vesničana

Vytvoř nový resource `res://ai/villager_routine.tres` (LimboBehaviorTree).

**Struktura stromu:**

```plain
Selector (root)
├── Sequence "Ranní rutina"
│   ├── Condition "Je mezi 6:00-8:00?"
│   ├── Action "Jdi na místo (zahrada)"
│   └── Action "Animace (kopání)"
├── Sequence "Práce"
│   ├── Condition "Je pracovní den?"
│   ├── Condition "Má zaměstnání?"
│   └── Action "Jdi do práce"
├── Sequence "Večerní hospoda"
│   ├── Condition "Je pátek/sobota?"
│   ├── Condition "Promile < 0.5?"
│   ├── Action "Jdi do hospody"
│   ├── Action "Sedni si ke stolu"
│   └── Action "Objednej pivo"
└── Fallback "Procházka"
    └── Action "Náhodná procházka po cestách"
```

### 3.3 Integrace do villager.gd

**Soubor: `scripts/villager.gd`**

```gdscript
extends CharacterBody3D

@export var behavior_tree: LimboBehaviorTree

var blackboard: LimboBlackboard

func _ready():
    blackboard = LimboBlackboard.new()
    blackboard.set_var("world", World)
    blackboard.set_var("self", self)
    blackboard.set_var("home", home_position)
    blackboard.set_var("workplace", workplace)
    
    behavior_tree.set_blackboard(blackboard)
    behavior_tree.start()

func _physics_process(delta):
    behavior_tree.tick(delta)
```

### 3.4 Custom Action nody

Vytvoř `scripts/ai/actions/go_to_place.gd`:

```gdscript
extends BTAction

@export var place_var: StringName = "target"

func _tick(delta: float) -> Status:
    var target_pos = blackboard.get_var(place_var)
    var villager = blackboard.get_var("self")
    
    villager.move_to(target_pos)
    
    if villager.global_position.distance_to(target_pos) < 1.0:
        return SUCCESS
    return RUNNING
```

### 3.5 Propojení s Persona

- V `persona.gd` přidej:

```gdscript
@export var daily_routine: LimboBehaviorTree
```

- Každý vesničan dostane vlastní instanci stromu s jinými parametry (hospodský jde do hospody v 18:00, úředník na úřad v 7:00).

## 4. STATE MANAGEMENT: Godot State Charts pro letadla

**Cíl:** Refaktorovat Aircraft stavy (taxi, let, stall, přistání) na přehledný stavový automat.

### 4.1 Instalace

- Stáhni `godot-state-charts` z GitHub.
- Kopíruj `addons/state_charts` do projektu.

### 4.2 Refaktor aircraft.gd

**Před:**

```gdscript
enum State { GROUND, FLIGHT, STALL, LANDING }
var state = State.GROUND
```

**Po:**

```gdscript
extends RigidBody3D

@export var state_chart: StateChart

# Stavy definujeme v editoru jako uzly:
# Aircraft (StateChart)
# ├── Ground (State)
# │   └── OnGround (State)
# ├── Flight (State)
# │   ├── Cruise (State)
# │   └── Stall (State)
# └── Landing (State)

func _ready():
    state_chart.set_initial_state("Ground")

func _on_speed_increased(speed):
    if speed > v_min and state_chart.is_in_state("Ground"):
        state_chart.send_event("takeoff")

func _on_stall_detected():
    state_chart.send_event("stall")
```

### 4.3 Výhody

- Každý stav má vlastní `_on_enter()` a `_on_exit()` – např. při vstupu do Stall zapnout varovný zvuk, při exit vypnout.
- Snadné přidání nového stavu (např. "Turbulence") bez úpravy hlavního kódu.

## 5. TERÉN: Optimalizace pomocí Terrain3D (Volitelné, pokročilé)

**Varování:** Tento krok je komplexní a měl by se dělat až po záloze. Alternativně ponechat vlastní terén.

### Postup integrace

1. Exportuj `terrain_height.bin` do výškové mapy PNG (16-bit grayscale).
2. V Terrain3D vytvoř nový terén, importuj výškovou mapu.
3. Nahraď `scripts/terrain.gd` za Terrain3D node.
4. Přepiš `shaders/terrain.gdshader` na Terrain3D shader (GLSL syntax se mírně liší).
5. Uprav `tools/water.py`, aby zapisoval do Terrain3D formátu místo `water_carve.bin`.

**Doporučení:** Pokud funguje současné řešení, nepřecházej – Terrain3D vyžaduje zásadní přepis toolchainu.

## 6. CHECKLIST PRO IMPLEMENTACI

### Fáze 1 (Základy)

- [x] Záloha projektu (git commit)
- [x] Instalace Jolt, přepnutí physics engine
- [x] Úprava `car.gd` (raycast suspension)
- [x] Úprava `aircraft.gd` (přesun fyziky do `_physics_process`)
- [x] Test `--cartest` a `--faunatest`

### Fáze 2 (Interiéry)

- [x] Instalace Qodot pluginu (FuncGodot 2025.1 – nástupce Qodotu pro Godot 4.x, `addons/func_godot`)
- [x] Vytvoření `hospoda.map` v TrenchBroom (ručně psaný Quake 1 `.map` v `data/maps/`, editovatelný v TrenchBroom)
- [x] Úprava `interior_streamer.gd` pro podporu Qodot (druh interiéru `qodot` přes `MapInteriors`, fallback na procedurální)
- [x] Test vstupu do hospody (E u dveří) (`--interiortest`)

### Fáze 3 (AI)

- [ ] Instalace LimboAI
- [ ] Vytvoření `villager_routine.tres`
- [ ] Implementace 3 základních action nodů (GoTo, Wait, Animate)
- [ ] Přiřazení stromu k 5 testovacím vesničanům

### Fáze 4 (Letadla)

- [ ] Instalace State Charts
- [ ] Refaktor `aircraft.gd` na stavový automat
- [ ] Test vzletu/přistání s paramotorem

### Fáze 5 (Dokumentace)

- [ ] Aktualizace `README.md` o nových závislostech
- [ ] Přidání `THIRD_PARTY.md` s licencemi (Jolt je MIT, Qodot MIT, LimboAI MIT)

## 7. RIZIKA A ŘEŠENÍ PROBLÉMŮ

| Problém | Příznak | Řešení |
|---|---|---|
| Jolt: Auto se propadá pod terén | `car.gd` spadne pod zem | Zvýšit `suspension_stiffness` o 20 %, nebo zapnout `continuous_cd` |
| Qodot: Špatné osy | Interiér je otočený o 90° | V TrenchBroom použít `info_player_start` s yaw=0, otočit v Godotu |
| LimboAI: Vesničan zamrzne | BT vrací FAILURE | Zkontrolovat blackboard proměnné (null check) |
| State Charts: Signál nedorazí | Letadlo nezareaguje na takeoff | Ověřit, že `state_chart` není null v `_ready()` |

## 8. DALŠÍ KROKY PO ÚSPĚŠNÉ IMPLEMENTACI

- **Multiplayer příprava:** Jolt je determinističtější než Godot Physics – lépe se synchronizuje pro MP.
- **Modding:** Qodot mapy (.map soubory) mohou být načítány z `user://mods/`, což umožní komunitě vytvářet vlastní interiéry.
- **Výkon:** Po Joltu měř FPS – měl by být o 20-40 % vyšší při jízdě autem (méně CPU na fyziku).

Tento plán lze zadat implementačnímu agentovi jako sekvenční úkoly. Každá fáze je nezávislá a lze ji otestovat samostatně před postupem dál.

---

# UPGRADE PLÁN PRO STONE AND CLAY – DÍL 2: VEGETACE, TERÉN A ZÁSTAVBA

Tento dokument navazuje na Díl 1 (fyzika, interiéry, AI) a řeší vizuální stránku světa: detailní vegetaci, ploty, zahrádky a strukturu krajiny. Cílem je přejít z "holé krajiny se stromy" na živou vesnickou krajinu s různorodou vegetací a oplocenými pozemky.

## 9. VEGETACE: Detailní systém rostlin

**Cíl:** Přidat keře, křoví, trávu vysokou, kopřivy, obilné pole s klasy a podrost v lese. Použít MultiMesh + shaderový vítr (kompatibilní s tvým `weather.gd`).

### 9.1 Datová struktura vegetace

Vytvoř `scripts/vegetation/vegetation_manager.gd`:

```gdscript
class_name VegetationManager
extends Node3D

# Typy vegetace podle biotopu
enum VegType {
    GRASS_TALL,      # vysoká tráva na loukách
    NETTLE,          # kopřivy u cest a na mýtinách
    BUSH_HAZEL,      # lískové keře v lese
    BUSH_BLACKTHORN, # trnky na okrajích polí
    CROP_WHEAT,      # pšenice na polích (z Fields.CROPS)
    WEED_FIELD,      # plevel v řádcích
    GARDEN_VEG       # zahrádky u domů (rajčata, cibule)
}

# Konfigurace pro MultiMesh
const VEG_CONFIG = {
    VegType.GRASS_TALL: {
        "mesh": "res://assets/models/vegetation/grass_tall.res",
        "density_per_m2": 0.8,
        "max_instances": 50000,
        "shader_param": "wind_strength"
    },
    VegType.BUSH_HAZEL: {
        "mesh": "res://assets/models/vegetation/bush_hazel.res", 
        "density_per_m2": 0.05,
        "max_instances": 5000,
        "shader_param": "wind_strength"
    }
    # ... doplň další
}

var multimeshes: Dictionary = {}  # VegType -> MultiMeshInstance3D
```

### 9.2 Generování vegetace z dat

**Soubor: `tools/vegetation.py`** (nový Python nástroj):

- Čti `data/surface.bin` (třídy povrchu) a `data/landuse.bin` (plodiny).
- Pro každý typ povrchu (les, louka, pole, zahrada) vygeneruj body:

```python
# Les: pod hustotou stromů (trees.bin) přidej keře a kapradí
# Louky: vysoká tráva, hustota podle Seasons.bloom
# Pole: řádky plodin (wheat) podle Fields.CROPS aktuální fáze
```

- Exportuj do `data/vegetation.bin` (formát: typ, x, y, z, rotace, měřítko, barva).

### 9.3 Vykreslení ve hře

Integrace do `map_loader.gd` nebo `world.gd`:

```gdscript
func _load_vegetation():
    var file = FileAccess.open("res://data/vegetation.bin", FileAccess.READ)
    while file.get_position() < file.get_length():
        var type = file.get_32()
        var pos = Vector3(file.get_float(), file.get_float(), file.get_float())
        var rot = file.get_float()
        var scale = file.get_float()
        
        if not multimeshes.has(type):
            _create_veg_multimesh(type)
        
        multimeshes[type].multimesh.set_instance_transform(
            multimeshes[type].multimesh.visible_instance_count,
            Transform3D(Basis.from_euler(Vector3(0, rot, 0)) * scale, pos)
        )
        multimeshes[type].multimesh.visible_instance_count += 1
```

### 9.4 Shader pro vítr

**Soubor: `shaders/vegetation.gdshader`:**

```glsl
shader_type spatial;
render_mode cull_disabled;

uniform float wind_strength = 1.0;
uniform float time_scale = 1.0;
uniform sampler2D wind_noise;

void vertex() {
    // Instance ID pro náhodnou fázi
    float instance_phase = float(INSTANCE_ID) * 0.618;
    
    // Vítr z globalní uniformy (napoj na Weather.wind_vector)
    vec2 wind_dir = vec2(1.0, 0.5); // TODO: propojit s weather.gd
    float wind_speed = 5.0;
    
    // Ohyb podle výšky vertexu (0 u země, 1 u špičky)
    float bend = UV.y * UV.y; 
    float wave = sin(TIME * time_scale + instance_phase + dot(WORLD_POSITION.xz, wind_dir) * 0.1);
    
    VERTEX.x += wave * wind_strength * bend * 0.2;
    VERTEX.z += wave * wind_strength * bend * 0.15;
}
```

Propojení s počasím v `vegetation_manager.gd`:

```gdscript
func _process(delta):
    var wind = Weather.wind_vector().length()
    for type in multimeshes:
        var material = multimeshes[type].material_override
        material.set_shader_parameter("wind_strength", clamp(wind / 10.0, 0.0, 2.0))
```

## 10. PLOTY A OHRADY (Fencing System)

**Cíl:** Automaticky generovat ploty kolem zahrad, pastvin a polí podle OSM dat nebo procedurálně kolem usedlostí.

### 10.1 Typy plotů

Vytvoř `scripts/structures/fence_manager.gd`:

```gdscript
enum FenceType {
    WIRE,           # ostnatý drát u polí
    WOODEN_SLAT,    # dřevěný latěný plot u zahrad
    WOODEN_POST,    # kůly s drátem (pastviny)
    STONE_WALL,     # kamenná zeď (mezi pozemky)
    HEDGE           # živý plot (z keřů)
}
```

### 10.2 Data pro ploty

**Varianta A – z OSM:**

- Uprav `tools/landuse.py`, aby exportoval i `barrier=fence` a `barrier=wall` z OSM do nového souboru `data/fences.json` (linie jako seznam bodů + typ).

**Varianta B – procedurální (doporučeno pro začátek):**

- V `estate.gd` přidej funkci `_generate_fences()`:
  - Kolem zahrady (Garden) vytvoř obdélník plotu typu WOODEN_SLAT.
  - Kolem výběhu (Paddock) WOODEN_POST.
  - U silnic (pokud je pole v Fields) přidej WIRE plot.

### 10.3 Vykreslení plotů (MultiMesh segmenty)

```gdscript
func _build_fence_line(points: PackedVector3Array, type: int):
    var scene = load("res://scenes/fence_%s.tscn" % FenceType.keys()[type].to_lower())
    var prototype = scene.instantiate()
    
    for i in range(points.size() - 1):
        var start = points[i]
        var end = points[i+1]
        var length = start.distance_to(end)
        var segments = int(length / 2.0)  # každé 2 metry
        
        for j in range(segments):
            var t = float(j) / segments
            var pos = start.lerp(end, t)
            var dir = (end - start).normalized()
            
            var instance = prototype.duplicate()
            instance.global_position = pos
            instance.look_at(pos + dir, Vector3.UP)
            add_child(instance)
```

### 10.4 Kolize

- Pro jednoduchost použij `StaticBody3D` s `BoxShape3D` pro každý segment (výška 1.2 m, tloušťka 0.1 m).
- Pro optimalizaci sloučit kolize do `StaticBody3D` s `ConcavePolygonShape3D` pro celou řadu plotu.

## 11. ZAHRÁDKY A DVOŘÍSTĚ (Garden Details)

**Cíl:** Vylepšit existující `garden.gd` o vizuální detaily: záhony s řádky, skleník, kompost, zahradní nábytek.

### 11.1 Struktura zahrady

Rozšiř `Garden` o nové uzly:

```plain
Garden (Node3D)
├── SoilMesh (MeshInstance3D) - tměná půda 12x8m
├── CropRows (Node3D) - instance rostlin z M2.4
├── Fence (Node3D) - z fence_manager
├── Greenhouse (Node3D) - volitelný skleník (sklo + kov)
├── Compost (Area3D) - hromada kompostu (interakce E = vzít hnůj)
└── Well (Node3D) - studna místo sudu (nebo vedle)
```

### 11.2 Vizualizace pěstování

V `garden.gd` uprav `_update_crop_visuals()`:

```gdscript
func _update_crop_visuals():
    for bed in garden_beds:
        var crop = CROPS[bed.crop_id]
        var growth = bed.growth_days / float(crop.days)
        
        # Změň měřítko rostliny podle růstu
        var plant_instance = bed.get_node("PlantInstance")
        plant_instance.scale = Vector3.ONE * lerp(0.1, 1.0, growth)
        
        # Přidej "plevel" pokud není zaplevelené
        if bed.weed > 0.5:
            plant_instance.get_node("Weed").visible = true
```

### 11.3 Interakce s okolím

- **Kompost:** E = "Vzít hnůj" (přidá do inventáře `hnuj`, použitelný jako hnojivo v M2.4).
- **Skleník:** Uvnitř lze pěstovat rajčata i v zimě (teplota +10°C, ignoruje mráz).
- **Studna:** Interakce E = "Nabrat vodu" (naplní konev bez nutnosti deště).

## 12. TERÉN: Detailní úpravy

**Cíl:** Přidat erozní rýhy, cestiční prašné cesty, louže po dešti a sněhové jazyky.

### 12.1 Eroze a hrby

Uprav `tools/export_map.py` (Blender skript):

- Po aplikaci DMR 5G přidej procedurální šum pro mikroreliéf:

```python
# Perlin noise s amplitudou 0.2m pro přirozenější terén
height += noise.noise_vector(x*0.1, y*0.1).z * 0.2
```

### 12.2 Cesty (polní cesty)

V `shaders/terrain.gdshader` přidej vrstvu pro polní cesty:

- Použij `data/surface.bin` (třída "track").
- Pro tyto plochy zobraz pískovou texturu s kolejemi (normal mapa s pruhy).

### 12.3 Louže a mokro

V `weather.gd` přidej `wetness_ground` (0-1):

- Když prší, zvyšuj `wetness`.
- V shaderu terénu míchej reflexivní povrch (roughness snížený) podle `wetness`.
- Vytvoř dekorativní `Decal` louže na silnicích při `wetness > 0.7`.

## 13. INTEGRAČNÍ CHECKLIST – DÍL 2

### Fáze 6 (Vegetace)

- [ ] Vytvořit `vegetation.py` exportér (čte `surface.bin` + `landuse.bin`)
- [ ] Vytvořit 5 základních modelů vegetace (`grass_tall`, `nettle`, `bush_hazel`, `wheat`, `weed`)
- [ ] Implementovat `VegetationManager` s MultiMesh
- [ ] Propojit vítr s `Weather.wind_vector()`
- [ ] Optimalizace: LOD pro vegetaci (zmizet nad 100m)

### Fáze 7 (Ploty)

- [x] Rozhodnout: OSM data vs procedurální → procedurální (varianta B)
- [x] Vytvořit modely plotů → místo `.tscn` scén procedurální geometrie přes `MeshKit` (5 typů vč. `stone_wall`)
- [x] Implementovat `FenceManager` s generováním kolem `Garden` a `Paddock` (`scripts/structures/fence_manager.gd`)
- [x] Přidat kolize → jedno `StaticBody3D` s `BoxShape3D` na úsek (ne `ConcavePolygonShape3D`)
- [x] Test: Kůň nesmí projít plotem, ale skrz branku ano (`--fencetest`, 22/22 OK)

### Fáze 8 (Zahrady)

- [x] Rozšířit `garden.gd` o vizuální stavy růstu (rostlina roste s `g/days`, plevel od `w>0.5`, zralé plody)
- [x] Přidat kompost (E → `hnuj`, zásoba `compost_left` 6 dávek, +1/den), studna (E + akce `naplnit_studna` → `konev_plna`), skleník 3×2 m (`gh_cell`, +10 °C, mráz nezabíjí)
- [x] Interakce E pro nové objekty (`interactables` + registrovaný cíl `studna`, akce `hnojit` s `hnuj` v ruce)
- [x] Uložení stavu zahrady do `save_game.gd` (klíč `garden_visuals`) – `--gardentest` 31/31 OK

### Fáze 9 (Terén)

- [ ] Upravit exportér pro mikroreliéf (opatrně, neměnit kolize)
- [ ] Shader terénu: mokré cesty, sněhové jazyky
- [ ] Louže jako dekorace (`Decal` nebo shader)

## 14. TECHNICKÉ POZNÁMKY PRO IMPLEMENTAČNÍHO AGENTA

### Výkon

- Vegetace používej pouze MultiMesh, nikdy jednotlivé `MeshInstance3D`.
- Ploty slučuj do velkých `StaticBody3D` (méně fyzických těles).
- Aktivuj/deaktivuj vegetaci podle vzdálenosti hráče (`VisibilityNotifier3D`).

### Kompatibilita

- Vegetace musí respektovat `Seasons.bloom` (květy jen v létě).
- Ploty se ukládají do save (pokud je hráč zničí nebo postaví nové).
- Zahrady se stěhují s domovem (`Garden.relocate` z M1.7) – ploty musí následovat.

### Assety

- Modely vegetace vytvoř v Blenderu (low-poly, max 50 tris).
- Textury použij z Poly Haven (CC0) nebo generuj procedurálně.
- Ploty: jednoduché UV mapování, PBR textury dřeva/kovu.

### Testování

- `--vegetationtest` – nový parametr pro test hustoty vegetace
- `--fencetest` – kontrola kolizí plotů
- `--gardentest` – růst plodin vizuálně

## 15. DOPORUČENÉ POŘADÍ IMPLEMENTACE

1. **Ploty** (nejrychlejší viditelný výsledek, izolovaný systém)
2. **Zahrady** (rozšíření stávajícího M2.4)
3. **Vegetace** (největší vizuální dopad, ale náročnější na výkon)
4. **Terén** (jemné doladění, až bude základ hotový)

Tímto způsobem získáš postupně živou vesnickou krajinu s oplocenými zahrádkami, detaily v interiéru zahrad a bohatou vegetací, která reaguje na počasí – vše kompatibilní s tvými stávajícími systémy (Estate, Weather, Seasons).
