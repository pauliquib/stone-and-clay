## Procedurální postava (hráč i vesničané): anatomicky tvarované díly z rotačních těles,
## obličej (oči, obočí, nos, uši, ústa), dlaně s palcem, boty, účesy, vousy, oblečení a uniformy.
## Každý kloub = jeden mesh s barvami vrcholů (sdílený materiál) → málo draw callů.
## Animace je řízená stavem (rychlost, skok, přikrčení) + akce (pití, kouření, jídlo, zvracení),
## opilost (potácení), obezita (břicho) a pózy (sezení v autě, ležení).
class_name Humanoid
extends Node3D

var shirt := Color(0.2, 0.45, 0.8)
var pants := Color(0.18, 0.2, 0.28)
var skin := Color(0.96, 0.7, 0.55)
var hair := Color(0.28, 0.18, 0.1)
var shoes := Color(0.13, 0.09, 0.07)
var hat := false
var female := false
var hair_style := 0          # 0 krátké, 1 pleš s věnečkem, 2 dlouhé, 3 ježek
var moustache := false
var beard := false
var long_sleeves := false
var outfit := ""             # "", "police", "hunter", "bartender", "shopkeeper"
var scale_factor := 1.0
var vis_end := 0.0

## ÚCHOP PŘEDMĚTU V RUCE – konvence.
## Rám ruky (`_hand_r`, pravá ruka visí podél těla, postava kouká do +Z): −Y = od dlaně ke konečkům prstů (podél
## předloktí), +Z = dopředu / směr palce, +X = k tělu (dlaň). Pěst svírá rukojeť kolmo na předloktí → osa pěsti = +Z ruky.
## Rám předmětu (modely v ToolModels / PropModels): počátek = libovolný, bod sevřený v pěsti udává `grip`;
## +Y = osa rukojeti / těla směrem k hlavě nástroje, hrdlu láhve, hrotu; +Z = ostří / hlaveň / špička (dopředu).
## Úchop předmětu = otočení modelu (`rot`, stupně, Euler XYZ v rámu ruky) + bod `grip` (v rámu modelu) přiložený na `HAND_FIST`.
## `rot.x` = náklon osy rukojeti (+Y modelu) od osy předloktí (−Y ruky) směrem dopředu: 0 = podél předloktí k zápěstí,
## 90 = rukojeť kolmo na předloktí dopředu (při vodorovném předloktí stojí svisle, ostří míří dopředu).
const HAND_FIST := Vector3(0.0, -0.06, 0.012)   # střed sevřené pěsti v rámu ruky (dlaň je koule v y −0,045)
const HOLD_GRIPS := {
	"bottle": {"rot": Vector3(40, 0, 0), "grip": Vector3(0, 0.07, 0)},         # láhev / sklenice / půllitr: hrdlo nahoru-dopředu
	"breathalyzer": {"rot": Vector3(40, 0, 0), "grip": Vector3(0, -0.04, 0)},  # dechovka: žlutá rukojeť
	"food": {"rot": Vector3(0, 0, 0), "grip": Vector3(0, 0.01, 0)},           # rohlík, jablko, chléb: drží se na dlani
}
const HOLD_DEFAULT := "food"
const DRINK_WRIST := 0.7          # ohnutí zápěstí při zvednutí láhve k ústům (rad)
const DRINK_WRIST_TILT := 0.95    # další ohnutí při napití (rad × naklonění 0..0,9)
const AIM_FOREARM := 1.65         # úhel předloktí při míření (−arm −fore) → tolik musí dát úchop + zápěstí dohromady


## Náklon úchopu nástroje v ruce (rot.x, rad) – viz ToolModels.GRIPS.
func _tool_grip_x() -> float:
	if _tool and is_instance_valid(_tool):
		return float(_tool.get_meta("grip_x", 0.0))
	return 0.0

## Oblečení hráče (M2.3, `apply_outfit`): styl a barva po slotech; prázdný styl = původní vzhled (triko, džíny, polobotky).
const JACKET_SLEEVED := ["bunda", "vetrovka", "platenka", "prsiplast", "sako"]     # bundy s dlouhými rukávy
const JACKET_LONG := ["platenka", "prsiplast"]                                      # sahají ke kolenům
var top_style := ""          # "", triko, kosile, mikina
var jacket_style := ""       # "", bunda, vetrovka, platenka, prsiplast, sako, reflexni_vesta
var jacket_color := Color.WHITE
var sleeve_c := Color(0, 0, 0, 0)   # barva rukávů (bunda); průhledná = rukávy trička
var pants_style := ""        # "", dziny, monterky, kratasy, plavky
var shoes_style := ""        # "", tenisky, holinky, pracovni_boty
var head_style := ""         # "", cepice, kulich, klobouk, kukla, helma_pila
var head_color := Color(0.4, 0.4, 0.4)
var gloves := false
var glove_color := Color(0.3, 0.3, 0.3)
var _outfit_sig := ""
var _fp := false

## Stav nastavovaný ovladačem každý snímek
var speed := 0.0
var on_floor := true
var vertical_speed := 0.0
var crouching := false
var sliding := false
var waving := false
var drunk := 0.0             # 0..1
var fat := 0.0               # 0..1
var pose := "stand"          # stand / sit / ride / lie
## Póza "ride" (řidič auta, kolo, motorka) – cíle v souřadnicích postavy (počátek = chodidla ve stoje):
##   hips: výška pánve, lean: předklon trupu, hands: [Vector3] úchop volantu / řídítek,
##   feet: [levá, pravá] kotníky (pedály auta, stupačky), nebo crank + crank_r: střed a poloměr klik (kolo),
##   spread: roztažení stehen do stran (kůň – nohy kolem hřbetu, IK nohy pak řeší rovinu odkloněnou o spread)
var ride := {}
var pedal_angle := 0.0       # natočení klik (kolo), nastavuje vozidlo
var action := ""             # "", drink, smoke, eat, vomit, offer

var _root: Node3D
var _hips: Node3D
var _torso: Node3D
var _belly: Node3D
var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _fore_l: Node3D
var _fore_r: Node3D
var _hand_l: Node3D
var _hand_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _shin_l: Node3D
var _shin_r: Node3D
var _meshes: Array[MeshInstance3D] = []
var _held: Node3D
var _cig: Node3D
var _smoke: CPUParticles3D
var _vomit_fx: CPUParticles3D
var _phase := 0.0
var _land := 0.0
var _crouch := 0.0
var _wave := 0.0
var _act_t := 0.0
var _act_w := 0.0
var _sit := 0.0
var _lie := 0.0
var _sway_t := 0.0
var _last_action := ""
var _tool: Node3D               # nástroj v ruce (viz set_tool)

## M8.6 – Gait (fázový cyklus chůze, `scripts/gait.gd`): zapíná `gait_on` (volající čte
## `World.realism_on("gait")`, výchozí zapnuto); bez instance / vypnuto = stará jednoduchá animace
## níž v `_process_impl` (fallback, 00_PRINCIPY kap. 3). Volající (Player/Villager) může nastavit
## `ground_fn` (terén pro sklon pod chodidly), `load_kg` (náklad na rameni), `tired`, `cold` (0..1).
var gait_on := true
var ground_fn := Callable()
var load_kg := 0.0
var tired := 0.0
var cold := 0.0
var _gait: Gait
var _prev_yaw := 0.0


func _ready() -> void:
	_gait = Gait.new()
	scale = Vector3.ONE * scale_factor
	_root = _pivot(self, Vector3.ZERO)
	_hips = _pivot(_root, Vector3(0, 0.95, 0))
	_torso = _pivot(_hips, Vector3(0, 0.0, 0))
	_head = _pivot(_torso, Vector3(0, 0.585, 0))
	var sx := -1.0   # postava kouká do +Z → pravá strana je −X
	_arm_r = _pivot(_torso, Vector3(0.205 * sx, 0.5, -0.01))
	_arm_l = _pivot(_torso, Vector3(-0.205 * sx, 0.5, -0.01))
	_fore_r = _pivot(_arm_r, Vector3(0, -0.285, 0))
	_fore_l = _pivot(_arm_l, Vector3(0, -0.285, 0))
	_hand_r = _pivot(_fore_r, Vector3(0, -0.245, 0))
	_hand_l = _pivot(_fore_l, Vector3(0, -0.245, 0))
	_leg_r = _pivot(_hips, Vector3(0.093 * sx, -0.03, 0))
	_leg_l = _pivot(_hips, Vector3(-0.093 * sx, -0.03, 0))
	_shin_r = _pivot(_leg_r, Vector3(0, -0.44, 0))
	_shin_l = _pivot(_leg_l, Vector3(0, -0.44, 0))
	_build_hips()
	_build_torso()
	_build_head()
	for side in [1.0, -1.0]:
		_build_arm(side)
		_build_leg(side)
	_build_belly()


# ---------------------------------------------------------------- oblečení hráče (M2.3)

## Přestaví postavu podle oblečení `worn` = {slot: id předmětu z `ItemsDB`} (sloty hlava, trup, bunda, nohy, boty, ruce).
## Klíče předmětu: style, color. Chybějící slot = výchozí vzhled. Přestavba jen při změně (stejné oblečení = nic).
func apply_outfit(worn: Dictionary) -> void:
	var sig := var_to_str(worn)
	if sig == _outfit_sig:
		return
	_outfit_sig = sig
	top_style = ""
	jacket_style = ""
	sleeve_c = Color(0, 0, 0, 0)
	pants_style = ""
	shoes_style = ""
	head_style = ""
	gloves = false
	long_sleeves = false
	var it := _worn_info(worn, "trup")
	if not it.is_empty():
		shirt = it.get("color", shirt)
		top_style = String(it.get("style", ""))
		long_sleeves = top_style in ["kosile", "mikina"]
	it = _worn_info(worn, "bunda")
	if not it.is_empty():
		jacket_style = String(it.get("style", ""))
		jacket_color = it.get("color", Color.WHITE)
		if jacket_style in JACKET_SLEEVED:
			long_sleeves = true
			sleeve_c = jacket_color
	it = _worn_info(worn, "nohy")
	if not it.is_empty():
		pants = it.get("color", pants)
		pants_style = String(it.get("style", ""))
	it = _worn_info(worn, "boty")
	if not it.is_empty():
		shoes = it.get("color", shoes)
		shoes_style = String(it.get("style", ""))
	it = _worn_info(worn, "hlava")
	if not it.is_empty():
		head_style = String(it.get("style", ""))
		head_color = it.get("color", head_color)
	it = _worn_info(worn, "ruce")
	if not it.is_empty():
		gloves = true
		glove_color = it.get("color", glove_color)
	if _root != null:
		_rebuild()


func _worn_info(worn: Dictionary, slot: String) -> Dictionary:
	var id := String(worn.get(slot, ""))
	return ItemsDB.info(id) if id != "" and ItemsDB.exists(id) else {}


## Zahodí staré díly a postaví je znovu (jen při změně oblečení; klouby a jejich pivoty zůstávají).
func _rebuild() -> void:
	for m in _meshes:
		if is_instance_valid(m):
			m.queue_free()
	_meshes.clear()
	if _belly != null and is_instance_valid(_belly):
		_belly.queue_free()
	_build_hips()
	_build_torso()
	_build_head()
	for side in [1.0, -1.0]:
		_build_arm(side)
		_build_leg(side)
	_build_belly()
	set_first_person(_fp)


# ---------------------------------------------------------------- stavba

func _commit(pivot: Node3D, kit: MeshKit) -> void:
	var mi := MeshKit.mesh_instance(pivot, kit.commit(MeshKit.vc_material(0.78)), vis_end)
	_meshes.append(mi)


func _build_hips() -> void:
	var k := MeshKit.new()
	var belt := Color(0.12, 0.08, 0.05)
	var prof := PackedVector2Array([Vector2(0.105, -0.13), Vector2(0.15, -0.07), Vector2(0.162, 0.0),
		Vector2(0.155, 0.05), Vector2(0.148, 0.075), Vector2(0.148, 0.1)])
	var cl := PackedColorArray([pants, pants, pants, pants, belt, belt])
	if outfit == "police":
		cl = PackedColorArray([pants, pants, pants, pants, Color(0.05, 0.05, 0.05), Color(0.05, 0.05, 0.05)])
	k.lathe(prof, Transform3D.IDENTITY, pants, 18, 1.0, 0.72, cl, true, false)
	if not female:   # přezka
		k.box(Vector3(0, 0.086, 0.108), Vector3(0.045, 0.03, 0.01), Color(0.7, 0.65, 0.5))
	if outfit == "bartender" or outfit == "shopkeeper":
		var ap := Color(0.95, 0.95, 0.92) if outfit == "bartender" else Color(0.2, 0.35, 0.7)
		k.box(Vector3(0, -0.2, 0.118), Vector3(0.3, 0.55, 0.012), ap, Vector3(0.08, 0, 0))
	_commit(_hips, k)


func _build_torso() -> void:
	var k := MeshKit.new()
	var c := shirt
	var prof: PackedVector2Array
	if female:
		prof = PackedVector2Array([Vector2(0.145, 0.06), Vector2(0.13, 0.16), Vector2(0.135, 0.28),
			Vector2(0.16, 0.37), Vector2(0.165, 0.43), Vector2(0.15, 0.5), Vector2(0.11, 0.545),
			Vector2(0.055, 0.565)])
	else:
		prof = PackedVector2Array([Vector2(0.148, 0.06), Vector2(0.15, 0.16), Vector2(0.158, 0.27),
			Vector2(0.175, 0.37), Vector2(0.18, 0.45), Vector2(0.165, 0.51), Vector2(0.115, 0.55),
			Vector2(0.058, 0.57)])
	k.lathe(prof, Transform3D.IDENTITY, c, 20, 1.12, 0.66, PackedColorArray(), false, true)
	if female:
		for s in [-1.0, 1.0]:
			k.sphere(Vector3(0.062 * s, 0.39, 0.075), 0.068, c, Vector3(1, 0.9, 0.85))
	# ramena (deltové svaly pod tričkem)
	for s in [-1.0, 1.0]:
		k.sphere(Vector3(0.19 * s, 0.49, -0.01), 0.068, c, Vector3(1.0, 0.9, 1.0))
	# krk
	k.lathe(PackedVector2Array([Vector2(0.052, 0.53), Vector2(0.048, 0.6), Vector2(0.05, 0.64)]),
		Transform3D.IDENTITY, skin, 12, 1.0, 1.0)
	# límec
	if outfit in ["police", "bartender"] or long_sleeves:
		k.lathe(PackedVector2Array([Vector2(0.066, 0.545), Vector2(0.062, 0.585)]), Transform3D.IDENTITY,
			c.lightened(0.1) if outfit != "bartender" else Color(1, 1, 1), 14, 1.0, 1.0)
	if top_style == "mikina":       # kapuce kolem krku a kapsa vpředu
		k.lathe(PackedVector2Array([Vector2(0.074, 0.525), Vector2(0.085, 0.56), Vector2(0.072, 0.605)]),
			Transform3D.IDENTITY, c.darkened(0.06), 14, 1.0, 1.0)
		k.box(Vector3(0, 0.2, 0.113), Vector3(0.21, 0.1, 0.02), c.darkened(0.12))
	if pants_style == "monterky":   # náprsenka a šle
		var bc := pants
		k.box(Vector3(0, 0.27, 0.107), Vector3(0.2, 0.25, 0.016), bc, Vector3(-0.04, 0, 0))
		for s in [-1.0, 1.0]:
			k.box(Vector3(0.075 * s, 0.47, 0.06), Vector3(0.036, 0.3, 0.012), bc, Vector3(-0.42, 0, 0))
	if jacket_style != "":
		_add_jacket(k)
	match outfit:
		"police":
			# reflexní vesta
			var vest := Color(0.85, 0.95, 0.15)
			var vp := PackedVector2Array([Vector2(0.162, 0.12), Vector2(0.168, 0.27), Vector2(0.186, 0.37),
				Vector2(0.19, 0.45), Vector2(0.172, 0.5)])
			k.lathe(vp, Transform3D.IDENTITY, vest, 20, 1.12, 0.68)
			k.lathe(PackedVector2Array([Vector2(0.17, 0.24), Vector2(0.172, 0.29)]), Transform3D.IDENTITY,
				Color(0.85, 0.87, 0.88), 20, 1.12, 0.68)
		"hunter":
			for s in [-1.0, 1.0]:
				k.box(Vector3(0.08 * s, 0.34, 0.11), Vector3(0.07, 0.06, 0.02), c.darkened(0.25))
	# břicho u postav s nadváhou se staví zvlášť (_build_belly)
	_commit(_torso, k)
	if outfit == "police":
		var l := Label3D.new()
		l.text = "POLICIE"
		l.font_size = 20
		l.pixel_size = 0.004
		l.modulate = Color(0.1, 0.15, 0.4)
		l.outline_size = 0
		l.position = Vector3(0, 0.36, -0.127)
		l.rotation.y = PI
		l.visibility_range_end = 40.0
		_torso.add_child(l)


## Bunda / vesta / plášť přes trup (M2.3): širší plášť z rotačního tělesa, límec, zip; dlouhé druhy sahají ke kolenům.
func _add_jacket(k: MeshKit) -> void:
	var jc := jacket_color
	if jacket_style == "reflexni_vesta":
		var vp := PackedVector2Array([Vector2(0.162, 0.06), Vector2(0.168, 0.27), Vector2(0.186, 0.37),
			Vector2(0.19, 0.45), Vector2(0.172, 0.5)])
		k.lathe(vp, Transform3D.IDENTITY, jc, 20, 1.12, 0.68)
		for y in [0.16, 0.3]:
			k.lathe(PackedVector2Array([Vector2(0.166 + (y - 0.16) * 0.1, y), Vector2(0.168 + (y - 0.16) * 0.1, y + 0.04)]),
				Transform3D.IDENTITY, Color(0.85, 0.87, 0.88), 20, 1.12, 0.68)
		return
	var prof := PackedVector2Array([Vector2(0.176, 0.0), Vector2(0.174, 0.08), Vector2(0.178, 0.18), Vector2(0.185, 0.28),
		Vector2(0.199, 0.38), Vector2(0.203, 0.45), Vector2(0.187, 0.51), Vector2(0.136, 0.553), Vector2(0.094, 0.575)])
	if jacket_style in JACKET_LONG:     # plášť ke kolenům: rozšířená sukně
		var ext := PackedVector2Array([Vector2(0.226, -0.34), Vector2(0.212, -0.22), Vector2(0.194, -0.08)])
		ext.append_array(prof)
		prof = ext
	elif jacket_style == "sako":
		prof[0] = Vector2(0.18, -0.06)
	k.lathe(prof, Transform3D.IDENTITY, jc, 22, 1.12, 0.68, PackedColorArray(), false, false)
	for s in [-1.0, 1.0]:      # ramena bundy
		k.sphere(Vector3(0.196 * s, 0.49, -0.01), 0.078, jc, Vector3(1.0, 0.9, 1.0))
	k.lathe(PackedVector2Array([Vector2(0.088, 0.55), Vector2(0.094, 0.585), Vector2(0.084, 0.61)]),
		Transform3D.IDENTITY, jc.darkened(0.08), 14, 1.0, 1.0)      # límec
	if jacket_style == "sako":
		for s in [-1.0, 1.0]:
			k.box(Vector3(0.045 * s, 0.44, 0.128), Vector3(0.05, 0.22, 0.012), Color(0.93, 0.93, 0.9), Vector3(0, 0, 0.3 * s))
		k.box(Vector3(0, 0.4, 0.13), Vector3(0.028, 0.2, 0.012), Color(0.55, 0.12, 0.15))            # kravata
	else:
		k.box(Vector3(0, 0.3 if jacket_style not in JACKET_LONG else 0.15, 0.127), Vector3(0.01, 0.5 if jacket_style not in JACKET_LONG else 0.8, 0.008),
			jc.darkened(0.3))                                                                          # zip
	if jacket_style == "platenka":      # kapuce vzadu
		k.sphere(Vector3(0, 0.575, -0.075), 0.085, jc.darkened(0.06), Vector3(1.4, 0.8, 0.9))


func _build_belly() -> void:
	_belly = _pivot(_torso, Vector3(0, 0.2, 0.05))
	var k := MeshKit.new()
	k.sphere(Vector3.ZERO, 0.15, shirt, Vector3(1.05, 1.0, 0.9), Vector3.ZERO, 16, 10)
	_commit(_belly, k)
	_belly.scale = Vector3.ONE * 0.01
	_belly.visible = false


func _build_head() -> void:
	var k := MeshKit.new()
	# lebka + obličej (vejčitý profil)
	var hp := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.04, 0.005), Vector2(0.068, 0.03),
		Vector2(0.085, 0.07), Vector2(0.096, 0.12), Vector2(0.099, 0.16), Vector2(0.093, 0.2),
		Vector2(0.075, 0.232), Vector2(0.042, 0.252), Vector2(0.0, 0.258)])
	k.lathe(hp, Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.005)), skin, 18, 0.9, 1.04)
	var dark := Color(0.08, 0.06, 0.05)
	# oči
	for s in [-1.0, 1.0]:
		k.sphere(Vector3(0.034 * s, 0.14, 0.083), 0.015, Color(0.96, 0.96, 0.94), Vector3.ONE, Vector3.ZERO, 8, 5)
		k.sphere(Vector3(0.034 * s, 0.14, 0.095), 0.0075, Color(0.25, 0.35, 0.45).lerp(dark, 0.4),
			Vector3.ONE, Vector3.ZERO, 6, 4)
		# obočí
		k.box(Vector3(0.036 * s, 0.163, 0.092), Vector3(0.034, 0.008, 0.01), hair.darkened(0.2),
			Vector3(0, 0, -0.12 * s))
		# uši
		k.sphere(Vector3(0.09 * s, 0.13, -0.005), 0.028, skin.darkened(0.05), Vector3(0.4, 1.0, 0.7), Vector3.ZERO, 8, 5)
	# nos
	k.capsule(Vector3(0, 0.118, 0.098), 0.014, 0.05, skin.darkened(0.04), Vector3(-0.35, 0, 0))
	k.sphere(Vector3(0, 0.1, 0.105), 0.016, skin.darkened(0.06), Vector3(1.2, 0.8, 1.0), Vector3.ZERO, 8, 5)
	# ústa
	k.box(Vector3(0, 0.068, 0.088), Vector3(0.036, 0.007, 0.012), Color(0.62, 0.32, 0.3))
	if moustache:
		k.capsule(Vector3(0, 0.082, 0.097), 0.01, 0.06, hair, Vector3(0, 0, PI / 2))
	if beard:
		k.sphere(Vector3(0, 0.045, 0.06), 0.06, hair, Vector3(1.2, 0.9, 0.8), Vector3.ZERO, 10, 6)
	# vlasy
	match hair_style:
		0, 3:
			var th := 0.012 if hair_style == 0 else 0.005
			var cap := PackedVector2Array([Vector2(0.101 + th, 0.11), Vector2(0.104 + th, 0.16),
				Vector2(0.098 + th, 0.2), Vector2(0.08 + th, 0.235), Vector2(0.045 + th, 0.258), Vector2(0.0, 0.265 + th)])
			k.lathe(cap, Transform3D(Basis.IDENTITY, Vector3(0, 0.005, -0.012)), hair, 18, 0.92, 1.06)
			if hair_style == 0:   # ofina
				k.box(Vector3(0, 0.215, 0.082), Vector3(0.12, 0.035, 0.03), hair, Vector3(0.5, 0, 0))
		1:
			var ring := PackedVector2Array([Vector2(0.101, 0.1), Vector2(0.104, 0.14), Vector2(0.098, 0.17)])
			k.lathe(ring, Transform3D(Basis.IDENTITY, Vector3(0, 0.0, -0.02)), hair, 18, 0.93, 1.04)
		2:
			var cap2 := PackedVector2Array([Vector2(0.108, 0.04), Vector2(0.11, 0.12), Vector2(0.108, 0.17),
				Vector2(0.098, 0.21), Vector2(0.08, 0.24), Vector2(0.045, 0.262), Vector2(0.0, 0.272)])
			k.lathe(cap2, Transform3D(Basis.IDENTITY, Vector3(0, 0.0, -0.018)), hair, 18, 0.95, 1.0)
			k.box(Vector3(0, 0.0, -0.075), Vector3(0.19, 0.22, 0.05), hair, Vector3(-0.15, 0, 0))
			k.box(Vector3(0, 0.205, 0.075), Vector3(0.15, 0.04, 0.03), hair, Vector3(0.4, 0, 0))
	# pokrývky hlavy
	if outfit == "police":
		var cap_c := Color(0.1, 0.13, 0.28)
		k.cylinder(Vector3(0, 0.25, -0.005), 0.112, 0.1, 0.07, cap_c)
		k.box(Vector3(0, 0.225, 0.1), Vector3(0.15, 0.012, 0.07), Color(0.05, 0.05, 0.05), Vector3(0.2, 0, 0))
		k.box(Vector3(0, 0.255, 0.1), Vector3(0.05, 0.03, 0.01), Color(0.9, 0.8, 0.3))
	elif head_style != "":
		_add_headgear(k)
	elif outfit == "hunter" or hat:
		var hc := Color(0.24, 0.3, 0.18) if outfit == "hunter" else Color(0.35, 0.25, 0.12)
		k.cylinder(Vector3(0, 0.235, -0.005), 0.16, 0.16, 0.02, hc, Vector3.ZERO, 20)
		k.cylinder(Vector3(0, 0.285, -0.005), 0.085, 0.105, 0.1, hc, Vector3.ZERO, 16)
		k.cylinder(Vector3(0, 0.25, -0.005), 0.107, 0.107, 0.025, hc.darkened(0.4), Vector3.ZERO, 16)
		if outfit == "hunter":   # pírko
			k.capsule(Vector3(-0.1, 0.3, -0.02), 0.01, 0.14, Color(0.3, 0.3, 0.3), Vector3(0, 0, 0.5))
	_commit(_head, k)


## Pokrývky hlavy hráče (M2.3): čepice, kulich, klobouk, včelařská kukla, pilařská helma s chrániči sluchu a štítkem.
func _add_headgear(k: MeshKit) -> void:
	var hc := head_color
	match head_style:
		"cepice":
			k.cylinder(Vector3(0, 0.235, -0.005), 0.108, 0.108, 0.075, hc, Vector3.ZERO, 18)
			k.sphere(Vector3(0, 0.255, -0.005), 0.106, hc, Vector3(1.0, 0.75, 1.0), Vector3.ZERO, 16, 8)
			k.box(Vector3(0, 0.222, 0.115), Vector3(0.15, 0.01, 0.09), hc.darkened(0.15), Vector3(0.12, 0, 0))     # kšilt
		"kulich":
			k.lathe(PackedVector2Array([Vector2(0.108, 0.17), Vector2(0.112, 0.2), Vector2(0.104, 0.245),
				Vector2(0.07, 0.29), Vector2(0.02, 0.305)]), Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.008)), hc, 18, 0.95, 1.05)
			k.lathe(PackedVector2Array([Vector2(0.113, 0.17), Vector2(0.116, 0.2)]), Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.008)),
				hc.lightened(0.15), 18, 0.95, 1.05)
			k.sphere(Vector3(0, 0.315, -0.008), 0.028, hc.lightened(0.25))                                          # bambule
		"klobouk":
			k.cylinder(Vector3(0, 0.235, -0.005), 0.16, 0.16, 0.02, hc, Vector3.ZERO, 20)
			k.cylinder(Vector3(0, 0.285, -0.005), 0.085, 0.105, 0.1, hc, Vector3.ZERO, 16)
			k.cylinder(Vector3(0, 0.25, -0.005), 0.107, 0.107, 0.025, hc.darkened(0.4), Vector3.ZERO, 16)
		"kukla":         # včelařský klobouk se síťkou přes obličej
			k.cylinder(Vector3(0, 0.245, -0.005), 0.19, 0.19, 0.015, hc, Vector3.ZERO, 22)
			k.cylinder(Vector3(0, 0.29, -0.005), 0.09, 0.11, 0.09, hc, Vector3.ZERO, 16)
			k.lathe(PackedVector2Array([Vector2(0.12, -0.06), Vector2(0.13, -0.02), Vector2(0.15, 0.1), Vector2(0.17, 0.24)]),
				Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.005)), hc.darkened(0.25), 20)
		"helma_pila":    # přilba se štítkem a chrániči sluchu
			k.sphere(Vector3(0, 0.2, -0.006), 0.118, hc, Vector3(1.0, 0.95, 1.06), Vector3.ZERO, 16, 8)
			k.box(Vector3(0, 0.222, 0.098), Vector3(0.15, 0.012, 0.075), hc.darkened(0.15), Vector3(0.15, 0, 0))
			k.box(Vector3(0, 0.185, 0.118), Vector3(0.16, 0.085, 0.008), Color(0.25, 0.28, 0.3), Vector3(0.05, 0, 0))   # síťový štít
			for s in [-1.0, 1.0]:
				k.cylinder(Vector3(0.106 * s, 0.125, -0.005), 0.042, 0.042, 0.04, Color(0.2, 0.2, 0.22), Vector3(0, 0, PI / 2), 14)
				k.box(Vector3(0.075 * s, 0.215, -0.005), Vector3(0.012, 0.02, 0.05), Color(0.2, 0.2, 0.22))
		_:
			k.cylinder(Vector3(0, 0.25, -0.005), 0.108, 0.108, 0.05, hc, Vector3.ZERO, 16)


func _build_arm(side: float) -> void:
	var right := side > 0.0
	var arm := _arm_r if right else _arm_l
	var fore := _fore_r if right else _fore_l
	var hand := _hand_r if right else _hand_l
	var sleeve := sleeve_c if sleeve_c.a > 0.0 else shirt
	if outfit == "police":
		sleeve = shirt
	var thick := 1.0
	if sleeve_c.a > 0.0:
		thick = 1.2               # rukáv bundy je objemnější než triko
	elif top_style == "mikina":
		thick = 1.08
	var hskin := glove_color if gloves else skin
	var k := MeshKit.new()
	var up := PackedVector2Array([Vector2(0.055, 0.02), Vector2(0.062, -0.05), Vector2(0.058, -0.14),
		Vector2(0.048, -0.24), Vector2(0.044, -0.29)])
	if long_sleeves:
		k.lathe(up, Transform3D.IDENTITY, sleeve, 14, thick, thick)
	else:   # rukáv trička přes paži, pod ním kůže
		k.lathe(PackedVector2Array([Vector2(0.07, 0.03), Vector2(0.074, -0.06), Vector2(0.069, -0.13),
			Vector2(0.058, -0.132)]), Transform3D.IDENTITY, sleeve, 14)
		k.lathe(up, Transform3D.IDENTITY, skin, 14)
	_commit(arm, k)
	var f := MeshKit.new()
	var fc := sleeve if long_sleeves else skin
	f.lathe(PackedVector2Array([Vector2(0.044, 0.02), Vector2(0.046, -0.05), Vector2(0.038, -0.17),
		Vector2(0.03, -0.235)]), Transform3D.IDENTITY, fc, 12, thick, thick)
	if long_sleeves:
		f.lathe(PackedVector2Array([Vector2(0.036, -0.2), Vector2(0.036, -0.24)]), Transform3D.IDENTITY, sleeve.darkened(0.15), 12, thick, thick)
	elif gloves:
		f.lathe(PackedVector2Array([Vector2(0.034, -0.2), Vector2(0.034, -0.24)]), Transform3D.IDENTITY, hskin, 12)
	_commit(fore, f)
	var h := MeshKit.new()
	var hs := hskin
	h.sphere(Vector3(0, -0.045, 0.004), 0.042 * (1.06 if gloves else 1.0), hs, Vector3(0.62, 1.15, 0.95), Vector3.ZERO, 10, 6)   # dlaň
	h.capsule(Vector3(0, -0.1, 0.01), 0.022 * (1.1 if gloves else 1.0), 0.07, hs, Vector3(0.2, 0, 0), Vector3(1.2, 1.0, 1.5))   # prsty
	h.capsule(Vector3(0.0, -0.035, 0.035), 0.012 * (1.1 if gloves else 1.0), 0.055, hs, Vector3(0.6, 0, 0))                      # palec
	_commit(hand, h)


func _build_leg(side: float) -> void:
	var right := side > 0.0
	var leg := _leg_r if right else _leg_l
	var shin := _shin_r if right else _shin_l
	var k := MeshKit.new()
	var short_y := 0.0                  # kraťasy / plavky: kde nohavice končí (0 = dlouhé)
	if pants_style == "kratasy":
		short_y = -0.2
	elif pants_style == "plavky":
		short_y = -0.11
	if short_y < 0.0:
		var r_cut := 0.086 - (0.086 - 0.075) * (-short_y - 0.06) / 0.19
		k.lathe(PackedVector2Array([Vector2(0.088, 0.03), Vector2(0.086, -0.06), Vector2(r_cut, short_y),
			Vector2(r_cut + 0.004, short_y - 0.005)]), Transform3D.IDENTITY, pants, 14, 1.0, 1.05)
		k.lathe(PackedVector2Array([Vector2(r_cut, short_y), Vector2(0.075, -0.25), Vector2(0.06, -0.4),
			Vector2(0.056, -0.45)]), Transform3D.IDENTITY, skin, 14, 1.0, 1.05)
	else:
		k.lathe(PackedVector2Array([Vector2(0.088, 0.03), Vector2(0.086, -0.06), Vector2(0.075, -0.25),
			Vector2(0.06, -0.4), Vector2(0.056, -0.45)]), Transform3D.IDENTITY, pants, 14, 1.0, 1.05)
	_commit(leg, k)
	var s := MeshKit.new()
	var sp := PackedVector2Array([Vector2(0.056, 0.01), Vector2(0.058, -0.1), Vector2(0.054, -0.2),
		Vector2(0.044, -0.33), Vector2(0.042, -0.4)])
	s.lathe(sp, Transform3D.IDENTITY, pants if short_y == 0.0 else skin, 14, 1.0, 1.08)
	# bota: špička vpředu, podrážka
	var shoe := PackedVector2Array([Vector2(0.0, -0.49), Vector2(0.05, -0.488), Vector2(0.056, -0.46),
		Vector2(0.05, -0.43), Vector2(0.036, -0.405)])
	s.lathe(shoe, Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.045)), shoes, 14, 1.0, 2.2)
	var sole := shoes.darkened(0.5)
	match shoes_style:
		"tenisky":
			sole = Color(0.92, 0.92, 0.9)
			s.box(Vector3(0, -0.478, 0.045), Vector3(0.104, 0.008, 0.252), Color(0.9, 0.9, 0.88))   # bílý pruh podrážky
		"holinky":      # vysoká vodotěsná lýtková část
			var shaft := PackedVector2Array([Vector2(0.069, -0.15), Vector2(0.064, -0.16), Vector2(0.062, -0.2),
				Vector2(0.053, -0.33), Vector2(0.052, -0.42), Vector2(0.056, -0.46)])
			s.lathe(shaft, Transform3D.IDENTITY, shoes, 14, 1.0, 1.08)
			s.lathe(PackedVector2Array([Vector2(0.07, -0.145), Vector2(0.069, -0.16)]), Transform3D.IDENTITY,
				shoes.darkened(0.35), 14, 1.0, 1.08)
			sole = Color(0.1, 0.1, 0.1)
		"pracovni_boty":     # kotníková obuv s šněrováním a silnou podrážkou
			var ankle := PackedVector2Array([Vector2(0.056, -0.3), Vector2(0.05, -0.33), Vector2(0.05, -0.4),
				Vector2(0.056, -0.46)])
			s.lathe(ankle, Transform3D.IDENTITY, shoes, 14, 1.0, 1.08)
			s.lathe(PackedVector2Array([Vector2(0.058, -0.3), Vector2(0.056, -0.31)]), Transform3D.IDENTITY,
				shoes.darkened(0.3), 14, 1.0, 1.08)
			s.box(Vector3(0, -0.435, 0.076), Vector3(0.05, 0.05, 0.012), shoes.lightened(0.15), Vector3(0.9, 0, 0))
	s.box(Vector3(0, -0.49, 0.045), Vector3(0.1, 0.014, 0.25), sole)
	_commit(shin, s)


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


# ---------------------------------------------------------------- veřejné API

func set_first_person(fp: bool) -> void:
	_fp = fp
	for m in _meshes:
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if fp \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func land(impact: float) -> void:
	_land = clampf(impact / 12.0, 0.0, 1.0)


## Vezme předmět do pravé ruky (lahev, jídlo…). null = pustit.
## Nástroj / zbraň v pravé ruce (M0.4). Zůstane i po skončení akce (`stop_action` drží jen `hold`); skrytý,
## dokud se drží lahev / jídlo a mimo stoj (auto, kůň, ležení). null = prázdné ruce.
func set_tool(node: Node3D) -> void:
	if _tool and is_instance_valid(_tool):
		_tool.queue_free()
	_tool = node
	if node:
		# model_for už nastavil úchop (transform podle ToolModels.GRIPS); cizí uzel dostane výchozí úchop
		if not node.has_meta("grip_x"):
			node.transform = grip_transform(ToolModels.GRIPS[""])
			node.set_meta("grip_x", deg_to_rad(float((ToolModels.GRIPS[""]["rot"] as Vector3).x)))
		_hand_r.add_child(node)


## Transformace předmětu v rámu ruky podle záznamu úchopu ({"rot": stupně, "grip": bod modelu}); viz konvence nahoře.
static func grip_transform(g: Dictionary) -> Transform3D:
	var r: Vector3 = g.get("rot", Vector3.ZERO)
	var b := Basis.from_euler(Vector3(deg_to_rad(r.x), deg_to_rad(r.y), deg_to_rad(r.z)))
	var grip: Vector3 = g.get("grip", Vector3.ZERO)
	return Transform3D(b, HAND_FIST - b * grip)


## Vezme předmět do pravé ruky. `kind` = klíč z HOLD_GRIPS; prázdný = meta `hold_kind` uzlu (láhev, dechovka), jinak jídlo.
func hold(node: Node3D, kind := "") -> void:
	if _held and is_instance_valid(_held):
		_held.queue_free()
	_held = node
	if node:
		if kind == "":
			kind = String(node.get_meta("hold_kind", HOLD_DEFAULT))
		var g: Dictionary = HOLD_GRIPS.get(kind, HOLD_GRIPS[HOLD_DEFAULT])
		node.transform = grip_transform(g)
		node.set_meta("grip_x", deg_to_rad(float((g["rot"] as Vector3).x)))
		_hand_r.add_child(node)


func start_action(a: String) -> void:
	action = a
	_act_t = 0.0
	if a == "smoke" and _cig == null:
		_cig = PropModels.cigarette()
		_cig.position = Vector3(0.0, -0.1, 0.03)
		_cig.rotation = Vector3(0.0, 0.0, PI / 2)
		_hand_r.add_child(_cig)
		_smoke = _make_smoke()
		_head.add_child(_smoke)
		_smoke.position = Vector3(0, 0.075, 0.12)
	if a == "vomit":
		if _vomit_fx == null:
			_vomit_fx = _make_vomit()
			_head.add_child(_vomit_fx)
			_vomit_fx.position = Vector3(0, 0.07, 0.1)
		_vomit_fx.restart()
		_vomit_fx.emitting = true


func stop_action() -> void:
	if action == "smoke":
		if _cig:
			_cig.queue_free()
			_cig = null
		if _smoke:
			_smoke.emitting = false
			var s := _smoke
			get_tree().create_timer(3.0).timeout.connect(s.queue_free)
			_smoke = null
	if _vomit_fx:
		_vomit_fx.emitting = false
	action = ""
	hold(null)


func head_node() -> Node3D:
	return _head


# ---------------------------------------------------------------- animace

func _process(delta: float) -> void:
	var __t0 := Tests.prof_t0()
	_process_impl(delta)
	Tests.prof_add("humanoid", __t0)


func _process_impl(delta: float) -> void:
	var run := clampf((speed - 3.5) / 4.0, 0.0, 1.0)
	var moving := clampf(speed / 1.5, 0.0, 1.0)
	_phase += delta * (speed * (2.2 - run * 0.5) + 0.0001)
	_land = move_toward(_land, 0.0, delta * 4.0)
	_crouch = move_toward(_crouch, 1.0 if (crouching or sliding) else 0.0, delta * 6.0)
	_wave = move_toward(_wave, 1.0 if waving else 0.0, delta * 4.0)
	_act_w = move_toward(_act_w, 1.0 if action != "" else 0.0, delta * 3.0)
	_sit = move_toward(_sit, 1.0 if pose == "sit" or pose == "ride" else 0.0, delta * 4.0)
	_lie = move_toward(_lie, 1.0 if pose == "lie" else 0.0, delta * 3.0)
	_act_t += delta
	_sway_t += delta * (0.9 + drunk * 0.6)
	if action != "":
		_last_action = action
	if _tool and is_instance_valid(_tool):
		_tool.visible = pose == "stand" and (_held == null or not is_instance_valid(_held))
	var s := sin(_phase)
	var c := cos(_phase)
	var amp := lerpf(0.55, 1.0, run) * moving
	var leg_l := s * amp
	var leg_r := -s * amp
	var knee_l := maxf(0.0, -c) * (0.4 + run * 0.9) * moving + 0.05
	var knee_r := maxf(0.0, c) * (0.4 + run * 0.9) * moving + 0.05
	var arm_l := -s * amp * 0.8
	var arm_r := s * amp * 0.8
	var elbow := -(0.25 + run * 0.9)
	var lean := run * 0.22 + moving * 0.05
	var bob := absf(c) * 0.05 * amp - _land * 0.18
	var pelvis_x := 0.0
	var slope_roll := 0.0
	# M8.6: fázový cyklus `Gait` (stojná fáze beze klouzání, IK chodidel na terén, kymácení pánve,
	# protipohyb paží) – zapnuto `gait_on` (viz pole výš); bez toho zůstává stará animace nad touto čarou.
	var turn_rate := 0.0
	if delta > 0.0001:
		turn_rate = wrapf(rotation.y - _prev_yaw, -PI, PI) / delta
	_prev_yaw = rotation.y
	if gait_on and _gait != null and on_floor and pose == "stand" and not sliding:
		_gait.scale_factor = scale_factor
		_gait.animate(delta, speed, turn_rate, load_kg, tired)
		leg_l = _gait.leg_l
		leg_r = _gait.leg_r
		knee_l = _gait.knee_l
		knee_r = _gait.knee_r
		arm_l = _gait.arm_l
		arm_r = _gait.arm_r
		elbow = -(0.25 + _gait.run_frac * 0.9)
		bob = _gait.pelvis_y - _land * 0.18
		pelvis_x = _gait.pelvis_x
		lean = _gait.run_frac * 0.22 + _gait.move_w * 0.05
		# terén pod chodidly: podélný sklon → náklon trupu (do kopce vpřed, z kopce vzad), boční
		# sklon → náklon pánve (test „chůze napříč svahem“: chodidla rovnoběžně se svahem, pánev nakloněná)
		if ground_fn.is_valid():
			const SLOPE_D := 0.22
			var fwd := -global_transform.basis.z
			var right := global_transform.basis.x
			var p := global_position
			var h_f: float = ground_fn.call(p.x + fwd.x * SLOPE_D, p.z + fwd.z * SLOPE_D)
			var h_b: float = ground_fn.call(p.x - fwd.x * SLOPE_D, p.z - fwd.z * SLOPE_D)
			var h_r: float = ground_fn.call(p.x + right.x * SLOPE_D, p.z + right.z * SLOPE_D)
			var h_l: float = ground_fn.call(p.x - right.x * SLOPE_D, p.z - right.z * SLOPE_D)
			var slope_fwd := atan2(h_f - h_b, 2.0 * SLOPE_D)
			slope_roll = clampf(atan2(h_r - h_l, 2.0 * SLOPE_D), -0.4, 0.4) * _gait.move_w
			lean += clampf(-slope_fwd, -0.45, 0.45) * _gait.move_w
		# náklad na rameni a vyčerpaná výdrž: shrbení (lean), chlad: ruce blíž k tělu (řeší se níž u `arm_out`)
		lean += clampf(load_kg / Gait.LOAD_MAX_KG, 0.0, 1.0) * Gait.LOAD_LEAN_K * 10.0
		lean += tired * Gait.TIRED_LEAN_K
	if not on_floor and pose == "stand":
		var up := clampf(vertical_speed / 6.0, -1.0, 1.0)
		leg_l = 0.5 + up * 0.3
		leg_r = -0.2
		knee_l = 0.9
		knee_r = 0.4 - up * 0.2
		arm_l = -0.6 - up * 0.6
		arm_r = 0.4 - up * 0.5
		elbow = -0.5
		lean = 0.08
	# přikrčení / skluz
	var hips_y := 0.95 - _crouch * 0.38 + bob
	leg_l = lerpf(leg_l, 1.1 if not sliding else 1.4, _crouch)
	leg_r = lerpf(leg_r, 1.1 if not sliding else 0.2, _crouch)
	knee_l = lerpf(knee_l, 1.9 if not sliding else 1.0, _crouch)
	knee_r = lerpf(knee_r, 1.9 if not sliding else 0.2, _crouch)
	lean = lerpf(lean, 0.35 if not sliding else -0.5, _crouch)
	# opilost: potácení trupu, hlavy, ruce od těla (opilost staví na `Gait`: posun těžiště mimo opěrnou
	# bázi = vrávorání a nápravný krok – `_gait.move_w` zesiluje rozkmit podle toho, jestli postava jde)
	var sway := sin(_sway_t * 1.3) * 0.5 + sin(_sway_t * 2.9 + 1.0) * 0.3
	var roll := sway * 0.16 * drunk + slope_roll
	var head_roll := sin(_sway_t * 1.1 + 0.5) * 0.25 * drunk
	var arm_out := 0.2 * drunk
	lean += drunk * 0.06 * (1.0 + sin(_sway_t * 0.7))
	# chlad: ruce blíž k tělu, občasný třes (deterministický šum z `_sway_t`, ne `randf()`)
	if cold > 0.0:
		arm_out -= cold * 0.14
		var shiver := sin(_sway_t * 26.0) * 0.012 * cold
		roll += shiver
		lean += absf(shiver) * 0.4
	# sezení (lavice) / jízda (auto, kolo, motorka – končetiny dosahují na pedály a řízení přes IK)
	var ik_l := Vector2(1.45, 1.35)
	var ik_r := Vector2(1.45, 1.35)
	var s_hips := 0.5
	var s_lean := -0.12
	var arm_ik := Vector2(0.95, 0.55 + 0.1)
	if pose == "ride" and not ride.is_empty():
		s_hips = ride.get("hips", 0.5)
		s_lean = ride.get("lean", -0.12)
		var hip := Vector2(0.0, s_hips - 0.03)
		var feet: Array = ride.get("feet", [])
		if ride.has("crank"):
			var cc: Vector3 = ride["crank"]
			var cr: float = ride.get("crank_r", 0.17)
			var fl := Vector2(cc.z + sin(pedal_angle) * cr, cc.y - cos(pedal_angle) * cr + 0.07)
			var fr := Vector2(cc.z - sin(pedal_angle) * cr, cc.y + cos(pedal_angle) * cr + 0.07)
			feet = [Vector3(0, fl.y, fl.x), Vector3(0, fr.y, fr.x)]
		if feet.size() == 2:
			ik_l = _leg_ik(hip, Vector2(feet[0].z, feet[0].y))
			ik_r = _leg_ik(hip, Vector2(feet[1].z, feet[1].y))
		var hands: Array = ride.get("hands", [])
		if not hands.is_empty():
			var sh := Vector2(sin(s_lean) * 0.5 - 0.01, s_hips + cos(s_lean) * 0.5)
			var hv: Vector3 = hands[0]
			arm_ik = _arm_ik(sh, Vector2(hv.z, hv.y), s_lean)
	leg_l = lerpf(leg_l, ik_l.x, _sit)
	leg_r = lerpf(leg_r, ik_r.x, _sit)
	knee_l = lerpf(knee_l, ik_l.y, _sit)
	knee_r = lerpf(knee_r, ik_r.y, _sit)
	arm_l = lerpf(arm_l, arm_ik.x, _sit)
	arm_r = lerpf(arm_r, arm_ik.x, _sit)
	elbow = lerpf(elbow, 0.1 - arm_ik.y, _sit)
	lean = lerpf(lean, s_lean, _sit)
	hips_y = lerpf(hips_y, s_hips, _sit)

	_hips.position.y = hips_y
	_hips.position.x = lerpf(pelvis_x, 0.0, _sit)   # boční posun pánve nad stojnou nohou (Gait); v sedu/jízdě vymizí
	_torso.rotation.x = lean
	_torso.rotation.z = roll
	_head.rotation.x = -lean * 0.6
	_head.rotation.z = head_roll
	_leg_l.rotation.x = -leg_l
	_leg_r.rotation.x = -leg_r
	# jízda na koni: stehna roztažená kolem hřbetu (ride.spread, rad)
	var spread := float(ride.get("spread", 0.0)) * _sit if pose == "ride" else 0.0
	_leg_l.rotation.z = spread
	_leg_r.rotation.z = -spread
	_shin_l.rotation.x = knee_l
	_shin_r.rotation.x = knee_r
	_arm_l.rotation.x = -arm_l
	_arm_r.rotation.x = -arm_r
	_fore_l.rotation.x = elbow * maxf(moving, _sit) - 0.1
	_fore_r.rotation.x = elbow * maxf(moving, _sit) - 0.1
	_arm_l.rotation.z = 0.08 + arm_out
	_arm_r.rotation.z = -0.08 - arm_out
	_hand_r.rotation = Vector3.ZERO
	_fore_r.rotation.z = 0.0
	if _wave > 0.0:   # mávání pravou rukou
		_arm_r.rotation.z = lerpf(-0.08, -2.6, _wave)
		_arm_r.rotation.x = 0.0
		_fore_r.rotation.z = sin(Time.get_ticks_msec() * 0.012) * 0.5 * _wave
	# akce pravou rukou (pití, kouření, jídlo)
	if _act_w > 0.0 and _last_action in ["drink", "smoke", "eat"]:
		var raise := 0.0
		var tilt := 0.0
		match _last_action:
			"drink":
				raise = smoothstep(0.0, 0.6, _act_t)
				tilt = smoothstep(0.5, 1.2, _act_t) * 0.9
			"eat":
				raise = 0.5 + 0.5 * sin(_act_t * 5.0)
			"smoke":
				var cyc := fmod(_act_t, 4.5)
				raise = smoothstep(0.2, 0.9, cyc) * (1.0 - smoothstep(1.9, 2.6, cyc))
		raise *= _act_w
		_arm_r.rotation.x = lerpf(_arm_r.rotation.x, -1.05 - tilt * 0.25, raise)
		_arm_r.rotation.z = lerpf(_arm_r.rotation.z, 0.42, raise)
		_fore_r.rotation.x = lerpf(_fore_r.rotation.x, -1.95 + tilt * 0.2, raise)
		_fore_r.rotation.z = 0.0
		# pití: zápěstí přivede hrdlo láhve (+Y modelu, HOLD_GRIPS "bottle") k ústům a při naklonění nahoru (DOPLNIT: doladit ručně)
		var hand_x := (DRINK_WRIST + tilt * DRINK_WRIST_TILT) if _last_action == "drink" else 0.2
		_hand_r.rotation.x = lerpf(0.0, hand_x, raise)
		_head.rotation.x = lerpf(_head.rotation.x, -tilt * 0.5, raise)
	if _last_action == "offer" and _act_w > 0.0:   # podává něco (policista alkohol-tester do okénka)
		_arm_r.rotation.x = lerpf(_arm_r.rotation.x, -1.3, _act_w)
		_arm_r.rotation.z = lerpf(_arm_r.rotation.z, 0.2, _act_w)
		_fore_r.rotation.x = lerpf(_fore_r.rotation.x, -0.45, _act_w)
		_hand_r.rotation.x = lerpf(0.0, -0.3, _act_w)
	if _last_action == "vomit" and _act_w > 0.0:
		_torso.rotation.x = lerpf(_torso.rotation.x, 0.9, _act_w)
		_head.rotation.x = lerpf(_head.rotation.x, 0.3, _act_w)
		_arm_l.rotation.x = lerpf(_arm_l.rotation.x, -0.5, _act_w)
		_arm_r.rotation.x = lerpf(_arm_r.rotation.x, -0.5, _act_w)
		_hips.position.y -= 0.05 * _act_w
	# práce s nástrojem (M0.4): sek, rytí, klek, zalévání, nahození, míření – jednoduché cyklické pohyby paží a trupu
	if _act_w > 0.0 and _last_action in ["chop", "dig", "kneel", "pour", "cast", "aim"]:
		var w := _act_w
		var ph := _act_t
		match _last_action:
			"chop":       # oběma rukama zvednout a sekat shora
				var sw := smoothstep(0.0, 1.0, 0.5 + 0.5 * sin(ph * 4.5))
				var a := lerpf(-2.5, -0.5, sw)
				_arm_r.rotation.x = lerpf(_arm_r.rotation.x, a, w)
				_arm_l.rotation.x = lerpf(_arm_l.rotation.x, a, w)
				_fore_r.rotation.x = lerpf(_fore_r.rotation.x, -0.4, w)
				_torso.rotation.x = lerpf(_torso.rotation.x, lerpf(-0.15, 0.45, sw), w)
			"dig":         # zápich a vyhození – předklon, ruce dolů
				var sw := 0.5 + 0.5 * sin(ph * 3.0)
				_arm_r.rotation.x = lerpf(_arm_r.rotation.x, lerpf(-1.2, -0.5, sw), w)
				_arm_l.rotation.x = lerpf(_arm_l.rotation.x, lerpf(-1.2, -0.5, sw), w)
				_fore_r.rotation.x = lerpf(_fore_r.rotation.x, -0.5, w)
				_torso.rotation.x = lerpf(_torso.rotation.x, 0.3 + sw * 0.35, w)
				_leg_r.rotation.x = lerpf(_leg_r.rotation.x, -0.5 * sw, w)
			"kneel":       # klek, ruce k zemi, drobné šmátrání
				var sw := 0.5 + 0.5 * sin(ph * 6.0)
				_hips.position.y -= 0.32 * w
				_leg_l.rotation.x = lerpf(_leg_l.rotation.x, -1.3, w)
				_leg_r.rotation.x = lerpf(_leg_r.rotation.x, -1.3, w)
				_shin_l.rotation.x = lerpf(_shin_l.rotation.x, 1.9, w)
				_shin_r.rotation.x = lerpf(_shin_r.rotation.x, 1.9, w)
				_torso.rotation.x = lerpf(_torso.rotation.x, 0.65, w)
				_arm_l.rotation.x = lerpf(_arm_l.rotation.x, -1.5 + sw * 0.25, w)
				_arm_r.rotation.x = lerpf(_arm_r.rotation.x, -1.5 + (1.0 - sw) * 0.25, w)
			"pour":        # konev nakloněná dopředu
				_arm_r.rotation.x = lerpf(_arm_r.rotation.x, -1.0, w)
				_fore_r.rotation.x = lerpf(_fore_r.rotation.x, -0.9, w)
				_hand_r.rotation.x = lerpf(0.0, 1.0 + sin(ph * 2.0) * 0.1, w)
				_torso.rotation.x = lerpf(_torso.rotation.x, 0.15, w)
			"cast":        # zpětný švih a nahození
				var sw := smoothstep(0.0, 1.0, fmod(ph, 1.6) / 1.6)
				_arm_r.rotation.x = lerpf(_arm_r.rotation.x, lerpf(-2.3, -0.9, sw), w)
				_fore_r.rotation.x = lerpf(_fore_r.rotation.x, lerpf(-0.6, -0.2, sw), w)
				_torso.rotation.x = lerpf(_torso.rotation.x, lerpf(-0.1, 0.2, sw), w)
			"aim":         # míření – drží se, obě ruce před tělem
				_arm_r.rotation.x = lerpf(_arm_r.rotation.x, -1.5, w)
				_arm_l.rotation.x = lerpf(_arm_l.rotation.x, -1.35, w)
				_arm_l.rotation.z = lerpf(_arm_l.rotation.z, -0.35, w)
				_fore_r.rotation.x = lerpf(_fore_r.rotation.x, -0.15, w)
				# zbraň míří podél předloktí: zápěstí doplní náklon úchopu (rot.x) na ~95° (vodorovná hlaveň)
				_hand_r.rotation.x = lerpf(0.0, AIM_FOREARM - _tool_grip_x(), w)
				_torso.rotation.x = lerpf(_torso.rotation.x, 0.05, w)
	# ležení (pád, okno)
	_root.rotation.x = -PI / 2 * _lie
	_root.position.y = 0.13 * _lie
	if _lie > 0.0:
		_arm_l.rotation.z = lerpf(_arm_l.rotation.z, 1.0, _lie)
		_arm_r.rotation.z = lerpf(_arm_r.rotation.z, -1.2, _lie)
		_leg_l.rotation.x = lerpf(_leg_l.rotation.x, 0.0, _lie)
		_leg_r.rotation.x = lerpf(_leg_r.rotation.x, -0.25, _lie)
		_leg_r.rotation.z = lerpf(0.0, -0.2, _lie)
		_shin_l.rotation.x = lerpf(_shin_l.rotation.x, 0.1, _lie)
		_shin_r.rotation.x = lerpf(_shin_r.rotation.x, 0.5, _lie)
		_torso.rotation.x = lerpf(_torso.rotation.x, 0.0, _lie)
		_head.rotation.z = lerpf(_head.rotation.z, 0.5, _lie)
	# obezita
	if fat > 0.02:
		_belly.visible = true
		_belly.scale = Vector3.ONE * (0.6 + fat * 0.65)
		_belly.position = Vector3(0, 0.2 - fat * 0.03, 0.03 + fat * 0.055)
		_torso.scale = Vector3(1.0 + fat * 0.22, 1.0 + sin(Time.get_ticks_msec() * 0.002) * 0.01, 1.0 + fat * 0.3)
		_hips.scale = Vector3(1.0 + fat * 0.18, 1.0, 1.0 + fat * 0.2)
	else:
		_belly.visible = false
		_torso.scale = Vector3(1.0, 1.0 + sin(Time.get_ticks_msec() * 0.002) * 0.01, 1.0)


## Dvoukloubová IK nohy v rovině YZ: kyčel `hip` → kotník `foot` (z, y). Vrací (úhel stehna vpřed od svislice,
## ohnutí kolena) – přesně hodnoty leg_* a knee_* z _process. Koleno míří dopředu.
func _leg_ik(hip: Vector2, foot: Vector2) -> Vector2:
	const L1 := 0.44
	const L2 := 0.44
	var d := foot - hip
	var dd := clampf(d.length(), 0.05, L1 + L2 - 0.002)
	var phi := atan2(d.x, -d.y)
	var alpha := acos(clampf((L1 * L1 + dd * dd - L2 * L2) / (2.0 * L1 * dd), -1.0, 1.0))
	var beta := acos(clampf((L1 * L1 + L2 * L2 - dd * dd) / (2.0 * L1 * L2), -1.0, 1.0))
	return Vector2(phi + alpha, PI - beta)


## IK paže v rovině YZ: rameno `sh` → úchop `hand` (z, y), trup předkloněný o `lean`.
## Vrací (hodnota arm_* pro _process, ohnutí lokte vpřed). Loket míří dolů / dozadu.
func _arm_ik(sh: Vector2, hand: Vector2, lean: float) -> Vector2:
	const L1 := 0.285
	const L2 := 0.29
	var d := hand - sh
	var dd := clampf(d.length(), 0.05, L1 + L2 - 0.002)
	var phi := atan2(d.x, -d.y)
	var alpha := acos(clampf((L1 * L1 + dd * dd - L2 * L2) / (2.0 * L1 * dd), -1.0, 1.0))
	var beta := acos(clampf((L1 * L1 + L2 * L2 - dd * dd) / (2.0 * L1 * L2), -1.0, 1.0))
	return Vector2(phi - alpha + lean, PI - beta)


func _make_smoke() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 24
	p.lifetime = 2.2
	p.emitting = true
	p.direction = Vector3(0, 1, 0.4)
	p.spread = 25.0
	p.initial_velocity_min = 0.15
	p.initial_velocity_max = 0.35
	p.gravity = Vector3(0, 0.25, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.3))
	curve.add_point(Vector2(1, 1.6))
	p.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(0.85, 0.85, 0.85, 0.45))
	grad.set_color(1, Color(0.8, 0.8, 0.8, 0.0))
	p.color_ramp = grad
	var q := QuadMesh.new()
	q.size = Vector2(0.08, 0.08)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	q.material = m
	p.mesh = q
	return p


func _make_vomit() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 60
	p.lifetime = 0.9
	p.one_shot = false
	p.emitting = false
	p.direction = Vector3(0, -0.3, 1)
	p.spread = 12.0
	p.initial_velocity_min = 1.2
	p.initial_velocity_max = 2.2
	p.gravity = Vector3(0, -9.8, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var s := SphereMesh.new()
	s.radius = 0.02
	s.height = 0.04
	s.radial_segments = 6
	s.rings = 3
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.5, 0.2)
	m.roughness = 0.3
	s.material = m
	p.mesh = s
	return p
