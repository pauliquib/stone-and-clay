## M8.6 – Biomechanika lidské chůze (fázový cyklus, podle 00_PRINCIPY kap. 8 „Člověk – pohyb“:
## stojná fáze ~60 % při chůzi / ~35 % při běhu, Hildebrandovy chody; duty factor a dynamická podobnost
## jako u `fauna/quadruped_rig.gd`, jen pro dvě nohy). Jedna instance na `Humanoid` (`_gait`), čte
## jen rychlost / náklon / otáčení, nic si nepamatuje o světě – `Humanoid` zapojí výstup do kostry
## a doplní terénní IK a stav těla (náklad, únava, chlad), protože ty už `Humanoid` zná.
##
## Přechod chůze ↔ běh kolem `RUN_SPEED` (~2 m/s, Froudovo číslo ~0,5 pro nohu ~0,9 m). Délka kroku
## (`stride`) vychází z rychlosti a délky nohy (`leg_len`, ∝ `scale_factor`, tj. výška postavy),
## kmitočet kroku ze stejného vztahu jako u zvěře (kyvadlo nohy, dynamická podobnost).
## Stojná noha se posouvá vzad přesně tak rychle, jak se tělo posouvá vpřed (lineární výkyv úhlu
## v rozsahu stojné fáze) → chodidlo neklouže; ve švihu opisuje chodidlo oblouk (`swing_lift`).
class_name Gait
extends RefCounted

const LEG_LEN := 0.44            # m – délka nohy (stehno + holeň, shoduje se s `Humanoid._leg_ik`)
const DUTY_WALK := 0.6           # podíl stojné fáze při chůzi
const DUTY_RUN := 0.35           # podíl stojné fáze při běhu (zbytek = letová fáze, oba chodidla ve vzduchu)
const RUN_SPEED := 2.0           # m/s – práh chůze → běh
const RUN_SPAN := 3.0            # m/s – šířka přechodu (plynulé duty/kadence)
const STEP_K := 0.85             # ladění kadence (dynamická podobnost, jako `QuadrupedRig.GAITS.k`)
const RUN_K := 1.25
const LIFT_WALK := 0.5           # zdvih chodidla ve švihu (rad ekvivalent přes koleno)
const LIFT_RUN := 1.0
const ARM_SWING_K := 0.8         # protipohyb paží vůči protilehlé noze
const PELVIS_SHIFT := 0.045      # m – boční posun pánve nad stojnou nohou
const PELVIS_BOB := 0.045        # m – svislý pohup (dvakrát za cyklus)
const TURN_SHUFFLE_MIN_RATE := 0.3   # rad/s – od kdy se otočka na místě řeší přešlapováním
const LOAD_MAX_KG := 30.0
const LOAD_LEAN_K := 0.012       # rad náklonu vpřed na kg (shrbení pod břemenem)
const LOAD_STEP_K := 0.3         # zkrácení kroku s nákladem (0..1 na LOAD_MAX_KG)
const TIRED_LEAN_K := 0.1        # rad shrbení při vyčerpané výdrži
const TIRED_CADENCE_K := 0.25    # zpomalení kadence při vyčerpané výdrži

var scale_factor := 1.0          # výška postavy (Humanoid.scale_factor) – délka kroku ∝ výška

var phase := 0.0                 # 0..1, levá noha ve stojné fázi na [0, duty)
var move_w := 0.0                 # 0..1 vyhlazené „jde/stojí“ (pro útlum při zastavení)
var duty := DUTY_WALK
var run_frac := 0.0              # 0..1 chůze→běh (pro Humanoid – sklon, houpání)

var leg_l := 0.0
var leg_r := 0.0
var knee_l := 0.05
var knee_r := 0.05
var arm_l := 0.0
var arm_r := 0.0
var pelvis_x := 0.0
var pelvis_y := 0.0              # svislý pohup (přidat k `hips_y`)
var cadence_hz := 0.0            # kroky/s – pro budoucí zvuk kroků (8.16/8.17)

var _prev_v := 0.0
var _turn_w := 0.0


## `speed`: m/s dopředu (vždy ≥ 0 – `Humanoid.speed` je velikost rychlosti); `turn_rate`: rad/s otáčení
## (jen pro přešlapování při otočce na místě, 0 když volající nepočítá); `load_kg`, `tired`, `cold`
## (0..1 u tired/cold): postoj. Nic nevrací – výsledek je ve veřejných polích výše.
func animate(delta: float, speed: float, turn_rate: float, load_kg: float, tired: float) -> void:
	var v := maxf(speed, 0.0)
	run_frac = clampf((v - RUN_SPEED) / RUN_SPAN, 0.0, 1.0)
	duty = lerpf(DUTY_WALK, DUTY_RUN, run_frac)
	var leg_len := LEG_LEN * clampf(scale_factor, 0.55, 1.6)
	var k := lerpf(STEP_K, RUN_K, run_frac) * (1.0 - tired * TIRED_CADENCE_K)
	var freq := k * sqrt(9.8 / leg_len) / PI
	# přešlapování při otočce na místě (ne „na kolíku“ – jako `QuadrupedRig._pick_gait` turning_in_place)
	var turning_in_place := v < 0.1 and absf(turn_rate) > TURN_SHUFFLE_MIN_RATE
	_turn_w = move_toward(_turn_w, 1.0 if turning_in_place else 0.0, delta * 5.0)
	var vv := v
	if turning_in_place:
		vv = clampf(absf(turn_rate) * 0.6, 0.15, 0.9)
	move_w = move_toward(move_w, 1.0 if vv > 0.04 else 0.0, delta * 5.0)
	cadence_hz = freq if move_w > 0.01 else 0.0
	if vv > 0.02:
		phase = fposmod(phase + freq * delta, 1.0)
	var stride := vv / maxf(freq, 0.05)
	var amp := clampf(atan(stride * duty * 0.5 / leg_len), 0.0, 0.9) * move_w
	var load_frac := clampf(load_kg / LOAD_MAX_KG, 0.0, 1.0)
	amp *= 1.0 - load_frac * LOAD_STEP_K
	var lift := lerpf(LIFT_WALK, LIFT_RUN, run_frac) * move_w
	var offs := [0.0, 0.5]
	var legs := [0.0, 0.0]
	var knees := [0.05, 0.05]
	for i in 2:
		var p := fposmod(phase + offs[i], 1.0)
		var s := 0.0
		var f := 0.0
		if p < duty:
			s = amp * (1.0 - 2.0 * p / duty)         # stojná fáze: lineární výkyv vzad = rychlost těla vpřed (bez klouzání)
		else:
			var t := (p - duty) / (1.0 - duty)
			s = amp * (-1.0 + 2.0 * smoothstep(0.0, 1.0, t))
			f = sin(PI * t) * lift                   # švihová fáze: oblouk nad terénem
		legs[i] = s
		knees[i] = 0.05 + f * (0.5 + run_frac * 0.85)
	leg_l = legs[0]
	leg_r = legs[1]
	knee_l = knees[0]
	knee_r = knees[1]
	# protipohyb paží vůči protilehlé noze (kontralaterální koordinace)
	arm_l = -leg_r * ARM_SWING_K
	arm_r = -leg_l * ARM_SWING_K
	if tired > 0.0:    # vyčerpaná výdrž: menší rozkmit paží
		arm_l *= 1.0 - tired * 0.4
		arm_r *= 1.0 - tired * 0.4
	# pánev: boční posun nad stojnou nohou + svislý pohup dvakrát za cyklus
	pelvis_x = PELVIS_SHIFT * sin(phase * TAU) * move_w
	pelvis_y = PELVIS_BOB * (0.5 - 0.5 * cos(phase * TAU * 2.0)) * move_w
	_prev_v = v
