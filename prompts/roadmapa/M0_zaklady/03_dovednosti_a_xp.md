# M0.3 – Dovednosti a zkušenosti (RuneScape styl)

> Roadmapa „Život na vsi“ · **M0 Základy** · krok 3/6
> Předpoklady: M0.2 · Navazují: M0.4 (akce dávají XP), všechny činnosti v M2–M6, práce M3 (požadavky na úroveň)

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md`
2. `docs/VIZE_A_ROADMAPA.md` – kap. 1 (vize) a **3.1 Dovednosti** (tabulka dovedností)
3. `scripts/reputation.gd` (celý, 246 ř.) – vzor per-hráč systému napojeného na `emit_game_event` a ukládání
4. `scripts/world.gd` – `add_player` (kde se tvoří `Reputation`), `emit_game_event`, `remove_player`
5. `scripts/hud.gd` – `reputation_changed`, `_journal_bbcode`, `popup`
6. `scripts/save_game.gd` – jak se ukládá pověst (grep `reputation`)
7. `scripts/local_client.gd` – `on_game_event` (jaké události chodí)

## 1. Proč
Jádro nové hry: **všechno, co hráč dělá, ho něco učí.** Úroveň dovednosti odemyká nástroje, recepty,
práce a zlepšuje výsledek (rychlost, výnos, menší šance na nehodu). Hráč si sám volí, čím bude.
„RuneScape“ tu znamená **činnosti ve světě** (dřevo, oheň, rybaření, lov, zahrada…), ne ovládání.

## 2. Návrh
Nový soubor `scripts/skills.gd`, `class_name Skills extends Node` – per hráč, stejně jako `Reputation`
(`World.skills[id]`, vytvořit v `add_player`, zrušit v `remove_player`).

```gdscript
const MAX_LEVEL := 50
## Křivka: XP potřebné pro úroveň L = round(BASE * (pow(GROWTH, L-1) - 1) / (GROWTH - 1))
const BASE := 60.0
const GROWTH := 1.13        # úroveň 10 ≈ 1 100 XP, 30 ≈ 17 000 XP, 50 ≈ 190 000 XP (ověř výpočtem a uprav)

## id → [název, popis, ikona-barva]
const SKILLS := {
	"drevorubectvi": ["Dřevorubectví", "kácení a štípání dřeva", Color(...)],
	"ohen": ["Topení a oheň", ...], "vareni": ["Vaření", ...], "zahradnictvi": ["Zahradničení", ...],
	"chovatelstvi": ["Chovatelství", ...], "rybareni": ["Rybaření", ...], "myslivost": ["Myslivost", ...],
	"strelba": ["Střelba", ...], "kutilstvi": ["Kutilství", ...], "rizeni": ["Řízení", ...],
	"jezdectvi": ["Jezdectví", ...], "skateboarding": ["Skateboarding", ...], "letectvi": ["Letectví", ...],
	"hasicina": ["Hasičina", ...], "kondice": ["Kondice a fotbal", ...], "vyrecnost": ["Výřečnost", ...],
}

## Zisk XP z herních událostí: kind → [dovednost, XP, podmínka / násobek z data]
const EVENT_XP := { ... }

var xp := {}                # id dovednosti → XP (float)
func level(skill: String) -> int
func xp_to_next(skill: String) -> float
func add_xp(skill: String, amount: float, why := "") -> void   # hlášky, level-up
func has_level(skill: String, lvl: int) -> bool
func bonus(skill: String) -> float   # 0..1 podle úrovně – pro rychlost / výnos (lineárně nebo odmocnina)
func on_event(kind: String, data: Dictionary) -> void
func to_dict() -> Dictionary / from_dict(d)
```

- `World.emit_game_event` volá i `skills[id].on_event(kind, data)` (stejně jako pověst).
- `World` dostane pomocnou `func give_xp(id: int, skill: String, amount: float, why := "")` – budoucí
  kroky budou volat tohle.
- **Napojení na to, co už ve hře je** (najdi grepem, jaké události se emitují – `emit_game_event(`):
  - `rizeni`: za ujetou vzdálenost střízlivě bez nehody (např. 1 XP / 200 m; počítej v `_physics_process`
    z `player.car` a rychlosti, jen když `body.promile() < 0.2`), nehoda nic nebere, jen nedá XP,
  - `jezdectvi`: jízda na koni (`player.horse`), víc za klus / cval,
  - `kutilstvi`: oprava auta (`World.repair_car`),
  - `vyrecnost`: slušný rozhovor (najdi v `reputation.gd` / `world.gd`, kde se dává bonus za slušnost),
  - `kondice`: běh / sprint pěšky (malé množství), plavání později,
  - úkoly (`quest_done`) – bonus XP podle úkolu (např. do `vyrecnost` 30 XP).
- **Oznámení:** `World.notify(id, "skill_xp", [skill_name, amount, level, progress])` → v HUD malý
  plovoucí text „+12 XP Řízení“ (nepřekrývat zprávy, shlukovat během 1 s). Level-up: `popup`
  „Nová úroveň: Řízení 5!“ + zvuk (existující `play_sfx`, např. „ding“ – ověř, co `sfx.gd` umí).
- **Deník J, záložka / oddíl „Dovednosti“**: tabulka název – úroveň – progress bar (textově
  `▰▰▰▱▱ 60 %`) – XP do další úrovně. Klávesa **K** otevře deník rovnou na dovednostech (přidej akci
  do `project.godot` input mapy a do F1 / README).
- **Ukládání:** `skills.to_dict()` do `save_game.gd`, starý save → všechny dovednosti 1.

## 3. Mimo rozsah
Odemykání konkrétních věcí úrovní (dělají navazující kroky přes `has_level`), nové činnosti.

## 4. Hotovo, když
- Jízda autem, na koni, oprava auta, slušný rozhovor a běh přidávají XP, HUD to ukazuje, úrovně rostou.
- Deník (J / K) ukazuje dovednosti; stav se ukládá a načítá; starý save funguje.

## 5. Návrh checklistu ručních testů
1. `./run.sh`, K → deník s 16 dovednostmi na úrovni 1.
2. Jeď střízlivě autem ~1 km → „+XP Řízení“ se objevuje, v K roste progress.
3. Po pár pivech jízda → XP za řízení nepřibývá.
4. Jízda na koni klusem → XP Jezdectví.
5. Oprava auta doma → XP Kutilství.
6. F5, F9 → XP zůstanou; načti starou pozici → vše na 1, nic nespadne.
7. (Rychlý test úrovně) F2 → Hráč → přidej cheat „+1000 XP řízení“ (přidej do `World.cheat` a menu) → level-up popup.

## 6. Závěr
README (Systémy → Dovednosti, Ovládání → K), GAME_DESIGN krátce, VIZE odškrtnout, roadmapa README,
PROJECT_LOG, deník AI, commit „M0.3 Dovednosti a XP: …“, checklist a čekat.
