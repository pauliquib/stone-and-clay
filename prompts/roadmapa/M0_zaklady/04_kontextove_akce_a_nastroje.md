# M0.4 – Kontextové akce, nástroje v ruce a náklad (základ)

> Roadmapa „Život na vsi“ · **M0 Základy** · krok 4/6
> Předpoklady: M0.2, M0.3 · Navazují: M2.1 kácení, M2.2 oheň, M2.4 zahrada, M2.6 chov, M2.7 rybaření, M2.8 zbraně, M2.10 náklad, M3 práce

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md` (hlavně registr kláves v kap. 5)
2. `docs/VIZE_A_ROADMAPA.md` – kap. **3.3 Kontextové akce**
3. `scripts/world.gd` – `interactables`, `find_interact`, `player_action`, `give_xp` (z M0.3)
4. `scripts/local_client.gd` – `_unhandled_input`, `_interact`, `_process` (kde se nastavuje `hud.set_prompt`)
5. `scripts/player.gd` – `_begin`, `_finish_action`, `busy`, `controls_locked`, výpočet rychlosti (grep `speed_mult`)
6. `scripts/humanoid.gd` – `hold`, `start_action`, `stop_action`, animace paží (`_process`, grep `action ==`)
7. `scripts/items_db.gd` (z M0.2) – typy `tool`, `weapon`

## 1. Proč
Kácení, oheň, rytí záhonu, dojení, rybaření, stavění, práce – vše je stejný vzorec: **hráč drží nástroj,
míří na cíl, spustí akci, akce chvíli trvá (průběh), stojí výdrž, dá XP, může selhat, může být přestupkem.**
Uděláme to jednou a pořádně, další kroky jen dodají „cíle“ a „akce“.

## 2. Návrh
### 2.1 Nástroj v ruce
- `Player.equipped := ""` (id předmětu typu `tool`/`weapon` z inventáře, "" = prázdné ruce).
- **Q** = cyklus mezi nástroji v inventáři (+ prázdné ruce), **1–5** = rychlé sloty (pořadí podle
  prvního sebrání; stačí jednoduché: sloty = prvních 5 nástrojů v inventáři seřazených podle `ItemsDB`).
  Přidej akce do `project.godot` (input map) a obsluhu do `LocalClient._unhandled_input` → `World.player_action(id, "equip_next")` / `"equip_slot_1"` …
- Vizuál: `visual.hold(model)` – procedurální model nástroje z nové `scripts/tool_models.gd`
  (`class_name ToolModels`, statické funkce přes `MeshKit`: `axe()`, `saw()`, `shovel()`, `hoe()`,
  `watering_can()`, `rod()`, `bow()`, `crossbow()`, `rifle()`, `matches()`; jednoduché tvary, barvy vrcholů,
  realistické rozměry). Když existuje `.glb` (M0.1 `AssetLib`), použij ho.
- HUD: malý ukazatel vpravo dole „V ruce: Sekera (opotřebení 34/50)“.

### 2.2 Cíle akcí
Nový soubor `scripts/actions.gd`, `class_name Actions extends RefCounted` – **registr akcí**:

```gdscript
## id akce → definice
## target: druh cíle ("tree", "ground", "fire_spot", "animal", "water", "any", …)
## tool: potřebný předmět nebo typ ("sekera|sekera_stara|motorova_pila", "" = holé ruce)
## time_s: trvání v reálných s při úrovni 1 (zrychluje Skills.bonus)
## stamina: kolik výdrže spotřebuje (0..1)
## skill, xp: dovednost a zisk; level: minimální úroveň
## anim: název akce pro Humanoid.start_action ("chop", "dig", "kneel", "pour", "cast", "aim"…)
## fail_chance: šance neúspěchu při úrovni 1 (klesá s úrovní)
const DEFS := {
	"natrhat_travu": {"name": "Natrhat trávu", "target": "ground", "tool": "", "time_s": 2.0, "stamina": 0.05,
		"skill": "zahradnictvi", "xp": 2, "level": 1, "anim": "kneel", "gives": {"trava": 1}},
}
```

- **Zdroj cílů:** nové kroky budou registrovat „cíle“ ve `World`: `func register_target(t: Dictionary)`
  / `unregister_target`, kde `t = {pos, r, kind, node?, data?}`; `World.targets_near(id, r)` vrátí
  kandidáty. Pro `ground` / `water` se cíl určí paprskem z kamery hráče (`World.aim_point(id)` – z
  pozice a yaw/pitch hráče, `PhysicsRayQueryParameters3D`, max 4 m; `Water.info_at` pro vodu).
- **Výběr akce:** když hráč míří na cíl a má vhodný nástroj, `hud.set_prompt` ukáže „[LMB] Pokácet strom
  (Dřevorubectví 3)“; když chybí úroveň / nástroj, prompt ukáže důvod šedě.
- **Levé tlačítko myši (pěšky, myš zachycená, žádné menu)** = spustit akci → `World.start_action(id, action_id, target)`.

### 2.3 Průběh akce (ve `World` nebo novém uzlu `ActionRunner`, per hráč)
- Kontroly: hráč stojí (ne v autě, ne na koni), není `busy` / `fallen`, má nástroj, úroveň, výdrž.
- Během akce: hráč se nehýbe (`controls_locked` jen pro pohyb – rozhlížet se může), `Humanoid.start_action(anim)`,
  HUD průběh (`notify(id, "action_progress", [name, 0..1])` – přidej do `hud.gd` tenký pruh pod zaměřovačem).
  Pohyb (WASD) nebo Esc akci **přeruší** bez odměny.
- Konec: `fail_chance × (1 − Skills.bonus)` → neúspěch (hláška, polovina XP), jinak výsledek:
  `gives` do inventáře, `wear_tool`, `give_xp`, `emit_game_event(id, "action_done", {action, target_kind, pos})`
  (na to se napojí zákon – M0.5 – a úkoly). Volitelný `callback` v definici pro speciální výsledky
  (kácení stromu apod. – registrují je další kroky: `Actions.set_handler(action_id, Callable)`).
- Animace v `humanoid.gd`: přidej obecné pózy `chop` (sek oběma rukama shora), `dig` (rytí), `kneel`
  (klek a ruce k zemi), `pour` (zalévání), `cast` (nahození udice), `aim` (míření – drží se). Stačí
  jednoduché cyklické pohyby paží a trupu přes existující pivoty (najdi v `_process`, jak se dělá `drink`).

### 2.4 Náklad – jen základ
- `Player.load_kind := ""` (co nese na rameni / v rukou – id z `ItemsDB` nebo speciální „srnec“…),
  `Player.load_kg := 0.0`. Když je náklad: bez sprintu a skoku, rychlost × `LOAD_SPEED` podle kg,
  výdrž ubývá rychleji, `visual` drží tvar (placeholder krabice). **G** = položit náklad na zem
  (vznikne `RigidBody3D` „balík“ s metadaty, jde znovu zvednout G). Celé přepravní možnosti dodá M2.10.

## 3. Mimo rozsah
Konkrétní činnosti (kácení, oheň, …) – jen testovací akce `natrhat_travu` (předmět `trava` přidej do `ItemsDB`, typ `material`).

## 4. Minimum
2.1 (Q + držení nástroje) + 2.2/2.3 s jednou akcí. Náklad (2.4) může přejít do M2.10 – zapiš do logu.

## 5. Hotovo, když
- Q přepíná nástroje (vidět v ruce), LMB na trávě spustí „Natrhat trávu“ s průběhem, animací, výdrží, XP,
  pohyb akci přeruší; prompt ukazuje důvod, proč akce nejde.
- G položí / zvedne testovací náklad (pokud je 2.4 hotové).

## 6. Návrh checklistu ručních testů
1. F2 → Hráč → peníze; v Potravinách (dočasně přidej do `OFFERS` obchodu `motyka`) kup motyku; Q → motyka v ruce, HUD „V ruce“.
2. Holé ruce, miř na trávu u domu → prompt „[LMB] Natrhat trávu“; LMB → průběh, klek, po 2 s tráva v Tab a +XP.
3. Během akce stiskni W → akce se přeruší, nic nepřibude.
4. Vyčerpaná výdrž (sprint) → akce nejde, prompt říká proč.
5. V autě / na koni LMB nic nedělá.
6. G s nákladem (pokud hotovo) → balík na zemi, G znovu → zvednout.

## 7. Závěr
README (Ovládání: Q, 1–5, LMB, G; Systémy), F1, VIZE odškrtnout, roadmapa README, PROJECT_LOG, deník AI,
commit „M0.4 Kontextové akce a nástroje: …“, checklist a čekat.
