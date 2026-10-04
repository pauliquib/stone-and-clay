## Dovednosti a zkušenosti jednoho hráče (World.skills[id]) – „RuneScape“ styl: všechno, co hráč dělá,
## ho něco učí. Úroveň 1–MAX_LEVEL, XP rostou exponenciálně (parametry BASE / GROWTH níže).
## Úroveň odemyká nástroje, recepty a práce (kroky M0.4+ ptají se přes `has_level`) a zlepšuje výsledek
## (`bonus` 0..1 lineárně od úrovně 1 po MAX_LEVEL).
##
## Zdroje XP: (a) herní události z World.emit_game_event → `EVENT_XP` a `on_event`, (b) průběžné činnosti
## (jízda autem, kůň, sprint) ve `_physics_process`, (c) ostatní systémy přes `World.give_xp`.
## Oznámení: World.notify(id, "skill_xp", [název, XP, úroveň, progress]) → plovoucí text v HUD;
## nová úroveň → popup + zvuk. Ukládání: to_dict / from_dict (starý save bez klíče = vše na 1).
class_name Skills
extends Node

const MAX_LEVEL := 50
## Křivka: XP potřebné pro dosažení úrovně L = round(BASE * (GROWTH^(L-1) - 1) / (GROWTH - 1)).
## Úroveň 10 ≈ 1 040 XP, 30 ≈ 15 500 XP, 50 ≈ 184 000 XP.
const BASE := 60.0
const GROWTH := 1.13

## id → [název, popis, barva ikony]. Pořadí = pořadí v deníku.
const SKILLS := {
	"drevorubectvi": ["Dřevorubectví", "kácení a štípání dřeva", Color(0.65, 0.45, 0.25)],
	"ohen": ["Topení a oheň", "rozdělání ohně, topení v kamnech", Color(0.95, 0.5, 0.15)],
	"vareni": ["Vaření", "opékání a vaření", Color(0.9, 0.75, 0.3)],
	"zahradnictvi": ["Zahradničení", "rytí, setí, sklizeň, sázení", Color(0.4, 0.75, 0.3)],
	"chovatelstvi": ["Chovatelství", "krmení, dojení, sběr vajec", Color(0.85, 0.8, 0.6)],
	"rybareni": ["Rybaření", "lov ryb na udici", Color(0.3, 0.6, 0.9)],
	"myslivost": ["Myslivost", "stopování, čekaná, zpracování zvěře", Color(0.35, 0.55, 0.3)],
	"strelba": ["Střelba", "střelnice, luk, kuše, puška", Color(0.7, 0.7, 0.7)],
	"kutilstvi": ["Kutilství", "opravy a stavby", Color(0.8, 0.6, 0.2)],
	"rizeni": ["Řízení", "jízda autem a motorkou", Color(0.85, 0.3, 0.3)],
	"jezdectvi": ["Jezdectví", "jízda na koni", Color(0.6, 0.4, 0.3)],
	"skateboarding": ["Skateboarding", "triky na ulici a v rampě", Color(0.5, 0.4, 0.8)],
	"letectvi": ["Letectví", "dron, paraglide, rogalo", Color(0.5, 0.8, 0.95)],
	"hasicina": ["Hasičina", "výjezdy, tréninky, požární útok", Color(0.95, 0.25, 0.2)],
	"kondice": ["Kondice a fotbal", "běh, sprint, trénink", Color(0.4, 0.85, 0.6)],
	"vyrecnost": ["Výřečnost", "slušné rozhovory, vyjednávání", Color(0.95, 0.75, 0.85)],
}

## Zisk XP z herních událostí: kind → [dovednost, XP]. Události s podmínkou řeší `on_event` (rozhovor).
const EVENT_XP := {
	"car_repaired": ["kutilstvi", 25.0],
	"quest_done": ["vyrecnost", 30.0],
}
## Slušné rozhovorové záměry (Dialog intent) dávají Výřečnosti XP; urážky a vyhrůžky nic.
const CHAT_XP := 2.0
const CHAT_INTENTS := ["greeting", "goodbye", "thanks", "compliment", "sorry", "howareyou", "introduce", "name", "weather", "joke", "news"]
const CHAT_COOLDOWN_S := 12.0     # skutečné sekundy mezi dvěma odměněnými větami (proti farmení)

## Řízení: XP za ujetou vzdálenost střízlivě a bez nehody.
const DRIVE_M_PER_XP := 100.0
const DRIVE_MAX_PROMILE := 0.2
const DRIVE_MIN_SPEED := 3.0      # m/s
const CRASH_IMPACT := 4.0         # nehoda tohoto nárazu zablokuje zisk XP z řízení na CRASH_PAUSE_S
const CRASH_PAUSE_S := 60.0
## Jízda na koni: XP za sekundu podle chodu (Horse.level: 1 krok … 4 trysk).
const HORSE_XP_PER_S := {1: 0.04, 2: 0.25, 3: 0.5, 4: 0.7}
## Sprint pěšky: XP Kondice za sekundu.
const SPRINT_XP_PER_S := 0.15
## Drobné XP se hromadí a hlásí až po dosažení této hodnoty (ať HUD nebliká).
const FLUSH_XP := 1.0

var game: World
var player: Player
var pid := 0
var xp := {}                      # id dovednosti → XP (float)

var _pending := {}                # id → nevyplacené zlomky XP
var _drive_m := 0.0
var _crash_until := 0.0           # Time msec do kdy nedává řízení XP
var _last_chat_ms := -1.0e9
var _silent := false              # při načítání nehlásit


func setup(g: World, p: Player) -> void:
	game = g
	player = p
	pid = p.id
	for k in SKILLS:
		xp[k] = 0.0


# ------------------------------------------------------------------ křivka a stav

## Kolik XP je celkem potřeba k dosažení úrovně `lvl` (úroveň 1 = 0).
static func xp_for_level(lvl: int) -> float:
	if lvl <= 1:
		return 0.0
	return roundf(BASE * (pow(GROWTH, lvl - 1) - 1.0) / (GROWTH - 1.0))


static func skill_name(skill: String) -> String:
	return String(SKILLS[skill][0]) if SKILLS.has(skill) else skill


func total_xp(skill: String) -> float:
	return float(xp.get(skill, 0.0))


func level(skill: String) -> int:
	var x := total_xp(skill)
	var l := 1
	while l < MAX_LEVEL and x >= xp_for_level(l + 1):
		l += 1
	return l


## Kolik XP chybí do další úrovně (0 na maximu).
func xp_to_next(skill: String) -> float:
	var l := level(skill)
	if l >= MAX_LEVEL:
		return 0.0
	return xp_for_level(l + 1) - total_xp(skill)


## Postup v aktuální úrovni 0..1 (na maximu 1).
func progress(skill: String) -> float:
	var l := level(skill)
	if l >= MAX_LEVEL:
		return 1.0
	var a := xp_for_level(l)
	return clampf((total_xp(skill) - a) / (xp_for_level(l + 1) - a), 0.0, 1.0)


func has_level(skill: String, lvl: int) -> bool:
	return level(skill) >= lvl


## Bonus 0..1 pro rychlost / výnos / bezpečnost: lineárně od úrovně 1 (0) po MAX_LEVEL (1).
func bonus(skill: String) -> float:
	return float(level(skill) - 1) / float(MAX_LEVEL - 1)


# ------------------------------------------------------------------ zisk XP

## Přidá XP; při zvýšení úrovně popup a zvuk, jinak plovoucí „+N XP“ v HUD.
func add_xp(skill: String, amount: float, why := "") -> void:
	if not SKILLS.has(skill) or amount <= 0.0:
		return
	var before := level(skill)
	xp[skill] = total_xp(skill) + amount
	var after := level(skill)
	if _silent or game == null:
		return
	game.notify(pid, "skill_xp", [skill_name(skill), amount, after, progress(skill), why])
	if after > before:
		game.notify(pid, "popup", ["Nová úroveň: %s %d!" % [skill_name(skill), after], 4.5])
		game.play_sfx(pid, "success")


## Drobné XP se sčítají a vyplatí se po FLUSH_XP.
func _add_partial(skill: String, amount: float) -> void:
	var v := float(_pending.get(skill, 0.0)) + amount
	if v >= FLUSH_XP:
		var whole := floorf(v)
		_pending[skill] = v - whole
		add_xp(skill, whole)
	else:
		_pending[skill] = v


func on_event(kind: String, data: Dictionary) -> void:
	if EVENT_XP.has(kind):
		var e: Array = EVENT_XP[kind]
		add_xp(e[0], e[1], kind)
	match kind:
		"chat":
			var now := float(Time.get_ticks_msec())
			if String(data.get("intent", "")) in CHAT_INTENTS and now - _last_chat_ms >= CHAT_COOLDOWN_S * 1000.0:
				_last_chat_ms = now
				add_xp("vyrecnost", CHAT_XP, "rozhovor")
		"car_crash":
			# nehoda nic neubírá, jen na chvíli nedá XP z řízení
			if float(data.get("impact", 0.0)) >= CRASH_IMPACT:
				_crash_until = float(Time.get_ticks_msec()) + CRASH_PAUSE_S * 1000.0
				_drive_m = 0.0
		"hit_person", "busted":
			_crash_until = float(Time.get_ticks_msec()) + CRASH_PAUSE_S * 1000.0
			_drive_m = 0.0
		"exited_car":
			_drive_m = 0.0


func _physics_process(delta: float) -> void:
	if game == null or not game.ready_done or not is_instance_valid(player):
		return
	var c := player.car
	if c:
		if absf(c.speed) > DRIVE_MIN_SPEED and player.body.promile() < DRIVE_MAX_PROMILE \
				and float(Time.get_ticks_msec()) >= _crash_until:
			_drive_m += absf(c.speed) * delta
			if _drive_m >= DRIVE_M_PER_XP:
				var n := floorf(_drive_m / DRIVE_M_PER_XP)
				_drive_m -= n * DRIVE_M_PER_XP
				add_xp("rizeni", n, "jízda")
		return
	_drive_m = 0.0
	var h := player.horse
	if h:
		var per_s: float = HORSE_XP_PER_S.get(clampi(h.level, 0, 4), 0.0)
		if per_s > 0.0 and absf(h.speed) > 1.0:
			_add_partial("jezdectvi", per_s * delta)
	elif player.is_sprinting() and player.is_on_floor() and not player.controls_locked:
		_add_partial("kondice", SPRINT_XP_PER_S * delta)


# ------------------------------------------------------------------ ukládání

func to_dict() -> Dictionary:
	var d := {}
	for k in SKILLS:
		if total_xp(k) > 0.0:
			d[k] = snappedf(total_xp(k), 0.01)
	return {"xp": d}


## Starý save bez klíče = vše na 1; neznámé dovednosti se přeskočí.
func from_dict(d: Dictionary) -> void:
	for k in SKILLS:
		xp[k] = 0.0
	var src: Dictionary = d.get("xp", {})
	for k in src:
		if SKILLS.has(k):
			xp[k] = maxf(float(src[k]), 0.0)
	_pending = {}
	_drive_m = 0.0
	_crash_until = 0.0
