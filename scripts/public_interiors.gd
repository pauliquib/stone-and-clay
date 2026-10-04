## Interiéry veřejných budov (M1.5): hospoda, Potraviny, obecní úřad, pálenice, vinný sklep, myslivecká chata.
## VŠECHNY půdorysy jsou vymyšlené (reálné vnitřky neznáme), procedurální přes stavebnici `Interior`
## (`wall_line`, `solid`, `deco`, `window`, `lamp`, `exit_door`, `add_object`) a `MeshKit`. Volá se z `Interior.build()`:
## `PublicInteriors.build(it, kind)`; `kind` = klíč místa z pois.json (hospoda, obchod, urad, palenice, sklep, chata).
##
## Souřadnice jsou lokální: x od západu, z od severu (−Z), podlaha y = 0, vchod v jižní stěně (z = +hz).
## Obsluha (`Place.keeper`) se za pult přesune přes `Interior.set_keeper` (Place.set_inside); štamgasti a páteční hosté
## sedí na sedadlech `Interior.add_seat("reg" / "fri", …)`. Interakce s obsluhou = objekt `place:<klíč>` → `InteriorMenu`.
class_name PublicInteriors
extends RefCounted

const STONE := Color(0.5, 0.5, 0.5)
const COPPER := Color(0.75, 0.42, 0.2)
const CHROME := Color(0.8, 0.82, 0.85)
const GLASS := Color(0.62, 0.8, 0.88)
const BRICK := Color(0.35, 0.2, 0.15)

const PAL_BREAD := [Color(0.8, 0.6, 0.3), Color(0.7, 0.5, 0.25), Color(0.85, 0.7, 0.4), Color(0.6, 0.4, 0.2)]
const PAL_DRINKS := [Color(0.2, 0.5, 0.75), Color(0.25, 0.6, 0.3), Color(0.8, 0.25, 0.2), Color(0.9, 0.6, 0.15)]
const PAL_CANS := [Color(0.7, 0.7, 0.72), Color(0.75, 0.2, 0.15), Color(0.3, 0.55, 0.3), Color(0.85, 0.75, 0.3)]
const PAL_DRUG := [Color(0.9, 0.9, 0.92), Color(0.35, 0.55, 0.8), Color(0.9, 0.6, 0.7), Color(0.4, 0.75, 0.7)]
const PAL_FOLDERS := [Color(0.3, 0.4, 0.6), Color(0.6, 0.5, 0.3), Color(0.5, 0.5, 0.5), Color(0.6, 0.25, 0.2)]
const PAL_WINE := [Color(0.15, 0.3, 0.15), Color(0.35, 0.12, 0.12), Color(0.75, 0.7, 0.3)]
const PAL_SPIRIT := [Color(0.85, 0.85, 0.75), Color(0.55, 0.3, 0.12), Color(0.2, 0.4, 0.25), Color(0.8, 0.8, 0.85)]


static func build(it: Interior, kind: String) -> void:
	match kind:
		"hospoda": _hospoda(it)
		"obchod": _obchod(it)
		"urad": _urad(it)
		"palenice": _palenice(it)
		"sklep": _sklep(it)
		"chata": _chata(it)


# ------------------------------------------------------------------ společné pomůcky

## Obvodové stěny, podlaha, strop a dveře v jižní stěně na `door_x`.
static func _room(it: Interior, hx: float, hz: float, door_x: float, wall_col: Color, floor_col: Color) -> void:
	it.shell(hx, hz)
	it.floor_patch(-hx, hx, -hz, hz, floor_col)
	it.wall_line(true, -hz - 0.1, -hx - 0.2, hx + 0.2, 0.2, [], wall_col)
	it.wall_line(true, hz + 0.1, -hx - 0.2, hx + 0.2, 0.2, [[door_x, 0.9]], wall_col)
	it.wall_line(false, -hx - 0.1, -hz, hz, 0.2, [], wall_col)
	it.wall_line(false, hx + 0.1, -hz, hz, 0.2, [], wall_col)
	it.exit_door(door_x, hz)


## Regál / polička s produkty (řady barevných krabiček) – kolize celého kvádru.
static func _shelf(it: Interior, cx: float, cz: float, len_: float, depth: float, along_x: bool, pal: Array,
		h := 1.8, rows := 4) -> void:
	var s := Vector3(len_, h, depth) if along_x else Vector3(depth, h, len_)
	it.solid(Vector3(cx, h * 0.5, cz), s, Color(0.6, 0.55, 0.48))
	var n := int(len_ / 0.32)
	for r in rows:
		var y := 0.35 + r * (h - 0.5) / maxf(rows - 1, 1)
		for i in n:
			var col: Color = pal[(i * 7 + r * 3) % pal.size()]
			var t := -len_ * 0.5 + (i + 0.5) * len_ / n
			for side in [-1.0, 1.0]:
				if along_x:
					it.deco(Vector3(cx + t, y, cz + side * depth * 0.5), Vector3(len_ / n * 0.8, 0.26, 0.08), col)
				else:
					it.deco(Vector3(cx + side * depth * 0.5, y, cz + t), Vector3(0.08, 0.26, len_ / n * 0.8), col)


## Stůl s lavicemi po stranách (jako na zahrádce): rozměr 1,7 × 1,9 m, dlouhá strana podél Z, půllitry na desce.
static func _table(it: Interior, c: Vector3, mugs := true) -> void:
	var wood := Color(0.55, 0.36, 0.2)
	var dk := wood.darkened(0.2)
	it.deco(c + Vector3(0, 0.74, 0), Vector3(0.8, 0.05, 1.9), wood)
	for s in [-1.0, 1.0]:
		it.deco(c + Vector3(0, 0.37, 0.75 * s), Vector3(0.7, 0.74, 0.06), dk)
		it.deco(c + Vector3(0.7 * s, 0.44, 0), Vector3(0.28, 0.05, 1.9), wood)
		it.deco(c + Vector3(0.7 * s, 0.22, 0.75), Vector3(0.28, 0.44, 0.06), dk)
		it.deco(c + Vector3(0.7 * s, 0.22, -0.75), Vector3(0.28, 0.44, 0.06), dk)
	it.collider(c + Vector3(0, 0.39, 0), Vector3(1.7, 0.78, 1.8))   # o 10 cm užší než deska – větší tolerance mezi řadami
	if mugs:
		for m in 3:
			it.deco(c + Vector3(0.05 * (m - 1), 0.83, -0.55 + m * 0.55), Vector3(0.09, 0.12, 0.09), Color(0.92, 0.68, 0.15))


## Tři místa u stolu (dva na západní, jedno na východní lavici) – stejné rozestavění jako na zahrádce.
static func _table_seats(it: Interior, group: String, c: Vector3) -> void:
	for i in 3:
		var side := -1.0 if i < 2 else 1.0
		it.add_seat(group, c + Vector3(0.62 * side, -0.05, -0.45 + (i % 2) * 0.9), PI / 2 if side < 0 else -PI / 2)


## Parůžky na štítku (bez skutečných osob – jen dekor): `c` = střed štítku na stěně, `n` = normála stěny (směr do místnosti).
static func _antlers(it: Interior, c: Vector3, n: Vector3) -> void:
	var yaw := atan2(n.x, n.z)
	var wood := Color(0.4, 0.28, 0.16)
	it.deco_rot(c, Vector3(0.05, 0.5, 0.36) if absf(n.x) > 0.5 else Vector3(0.36, 0.5, 0.05), wood, Vector3.ZERO)
	for s in [-1.0, 1.0]:
		var base: Vector3 = c + n * 0.07 + Vector3(-n.z, 0, n.x) * (0.12 * s) + Vector3(0, 0.28, 0)
		var col := Color(0.85, 0.8, 0.65)
		it.deco_rot(base, Vector3(0.04, 0.42, 0.04), col, Vector3(0, yaw, 0.35 * s))
		it.deco_rot(base + Vector3(0, 0.16, 0) + Vector3(-n.z, 0, n.x) * (0.06 * s) + n * 0.02, Vector3(0.03, 0.2, 0.03), col, Vector3(0, yaw, 0.9 * s))


# ------------------------------------------------------------------ hospoda U Hřiště (14 × 12 m, sál vzadu)
#
#   z −6 +----------------------------------+
#        |  SÁL: pódium, reproduktory,      |   stoly v sále (2), opona
#        |  2 stoly                          |
#   z  0 +------------[  3 m  ]-------------+   příčka s průchodem do sálu; WC dveře (dekor)
#        |  T1 T2 T5          | výčep       |   T1 = štamgasti, T2 = páteční hosté; výčep u východní stěny,
#        |  T3 T4    šipky TV | (obsluha)   |   hostinský za pultem
#   z +6 +----------[dveře x=1]--------------+

static func _hospoda(it: Interior) -> void:
	it.title = "Hospoda U Hřiště"
	var hx := 7.0
	var hz := 6.0
	_room(it, hx, hz, 1.0, Color(0.85, 0.78, 0.62), Color(0.5, 0.36, 0.22))
	it.floor_patch(-hx, hx, -hz, 0.0, Color(0.6, 0.46, 0.3))           # sál: světlejší parkety
	it.wall_line(true, 0.0, -hx, hx, 0.2, [[0.0, 3.0]], Color(0.8, 0.72, 0.58))   # příčka sál | hostinec
	# stoly v hostinci; T1 štamgasti, T2 páteční hosté
	var t1 := Vector3(-4.5, 0, 1.8)
	var t2 := Vector3(-1.5, 0, 1.8)
	var tables := [t1, t2, Vector3(1.4, 0, 1.8), Vector3(-4.5, 0, 4.45), Vector3(-1.5, 0, 4.45), Vector3(-5.3, 0, -2.0), Vector3(5.3, 0, -2.0)]
	for i in tables.size():
		_table(it, tables[i])
		it.spots["stul:%d" % i] = [it.to_global(tables[i] + Vector3(0, 0.8, 0)), 0.0]   # M3.1: cíle úkolu „Uklidit stoly“ (`Jobs`)
	_table_seats(it, "reg", t1)
	_table_seats(it, "fri", t2)
	# výčep: pult podél východní části (1,1 m), zavřený z jihu, hostinský za ním
	it.solid(Vector3(4.6, 0.55, 2.8), Vector3(0.7, 1.1, 5.4), Color(0.45, 0.3, 0.18))
	it.deco(Vector3(4.6, 1.12, 2.8), Vector3(0.85, 0.05, 5.55), Color(0.6, 0.42, 0.26))
	it.solid(Vector3(5.65, 0.55, 5.55), Vector3(2.75, 1.1, 0.12), Color(0.45, 0.3, 0.18))
	it.deco_cyl(Vector3(4.55, 1.28, 2.0), 0.05, 0.3, CHROME)              # pípa
	it.spots["pipa"] = [it.to_global(Vector3(4.3, 1.2, 2.0)), -PI * 0.5]   # M3.2: čepování (`Vycep`), hráč stojí před pultem
	it.deco(Vector3(4.42, 1.4, 2.0), Vector3(0.14, 0.04, 0.04), CHROME)
	for i in 3:
		it.deco(Vector3(4.36, 1.33, 1.85 + i * 0.15), Vector3(0.05, 0.1, 0.03), Color(0.15, 0.15, 0.15))
	it.deco(Vector3(4.6, 1.16, 3.4), Vector3(0.3, 0.05, 0.3), Color(0.25, 0.25, 0.28))              # tácek
	for i in 4:                                                                                       # barové stoličky
		it.deco_cyl(Vector3(3.7, 0.3, 0.9 + i * 1.2), 0.19, 0.6, Color(0.3, 0.2, 0.15))
	for y in [1.25, 1.65]:                                                                            # police s lahvemi
		it.deco(Vector3(6.85, y, 2.8), Vector3(0.25, 0.04, 4.6), Color(0.35, 0.24, 0.15))
		for i in 12:
			it.deco_cyl(Vector3(6.85, y + 0.15, 0.7 + i * 0.36), 0.05, 0.26, PAL_SPIRIT[i % PAL_SPIRIT.size()])
	it.solid(Vector3(6.5, 0.9, 4.9), Vector3(0.65, 1.8, 0.65), Interior.WHITE)                        # chladnička
	it.solid(Vector3(6.55, 0.4, 0.7), Vector3(0.7, 0.8, 0.9), Color(0.5, 0.36, 0.22))                 # bedny s pivem
	it.deco(Vector3(6.55, 0.85, 0.7), Vector3(0.5, 0.1, 0.6), Color(0.2, 0.5, 0.3))
	it.set_keeper(Vector3(5.9, 0.0, 2.8), -PI * 0.5)
	it.add_object(Vector3(3.4, 0.0, 2.8), 2.6, "place:hospoda", "Hostinský Láďa – výčep")
	# šipky, televize, věšák, WC
	it.cyl_rot(Vector3(-6.94, 1.7, 3.1), 0.22, 0.04, Color(0.15, 0.15, 0.15), Vector3(0, 0, PI * 0.5))
	it.cyl_rot(Vector3(-6.91, 1.7, 3.1), 0.12, 0.04, Color(0.75, 0.15, 0.12), Vector3(0, 0, PI * 0.5))
	it.cyl_rot(Vector3(-6.89, 1.7, 3.1), 0.04, 0.04, Color(0.9, 0.9, 0.85), Vector3(0, 0, PI * 0.5))
	it.deco(Vector3(-3.0, 1.95, 0.16), Vector3(1.3, 0.75, 0.08), Interior.DARK)                       # TV na příčce
	it.deco(Vector3(-3.0, 1.95, 0.21), Vector3(1.2, 0.65, 0.02), Color(0.25, 0.35, 0.55))
	it.deco(Vector3(3.0, 1.8, 5.93), Vector3(1.0, 0.05, 0.05), Interior.WOOD_DARK)                    # věšák u dveří
	it.deco(Vector3(2.8, 1.4, 5.85), Vector3(0.35, 0.8, 0.14), Color(0.25, 0.3, 0.4))
	it.deco(Vector3(3.3, 1.45, 5.85), Vector3(0.3, 0.7, 0.14), Color(0.45, 0.3, 0.2))
	for x in [-5.9, -4.8]:                                                                            # WC dveře (dekor)
		it.deco(Vector3(x, 1.0, 0.14), Vector3(0.9, 2.0, 0.05), Color(0.4, 0.28, 0.18))
		it.label(Vector3(x, 2.25, 0.18), "WC", 0.0, 0.004)
	# sál: pódium se schůdkem, reproduktory, mikrofon, opona
	it.solid(Vector3(0, 0.175, -5.0), Vector3(8.0, 0.35, 2.0), Color(0.42, 0.3, 0.2))
	it.solid(Vector3(0, 0.09, -3.85), Vector3(2.0, 0.18, 0.5), Color(0.42, 0.3, 0.2))
	it.solid(Vector3(-3.4, 0.95, -5.3), Vector3(0.6, 1.2, 0.5), Interior.DARK)
	it.solid(Vector3(3.4, 0.95, -5.3), Vector3(0.6, 1.2, 0.5), Interior.DARK)
	it.deco_cyl(Vector3(0.0, 1.1, -4.5), 0.015, 1.5, Interior.DARK)
	it.deco(Vector3(0, 1.3, -5.9), Vector3(7.5, 2.3, 0.05), Color(0.5, 0.1, 0.15))
	# okna
	it.window("S", -5.0, hz)
	it.window("S", -2.5, hz)
	it.window("S", 3.2, hz)
	it.window("W", 4.8, -hx)
	it.window("W", 1.0, -hx)
	it.window("W", -3.0, -hx)
	it.window("E", -3.0, hx)
	# světla
	it.lamp(Vector3(-4.5, 2.45, 2.5), 5.5)
	it.lamp(Vector3(-0.5, 2.45, 3.5), 5.5)
	it.lamp(Vector3(2.5, 2.45, 1.5), 5.0)
	it.lamp(Vector3(5.6, 2.45, 2.8), 5.0)
	it.lamp(Vector3(-3.0, 2.45, -2.5), 6.0)
	it.lamp(Vector3(3.0, 2.45, -2.5), 6.0)
	it.lamp(Vector3(0.0, 2.4, -4.5), 5.0)


# ------------------------------------------------------------------ Potraviny (10 × 8 m)

static func _obchod(it: Interior) -> void:
	it.title = "Potraviny"
	var hx := 5.0
	var hz := 4.0
	_room(it, hx, hz, 3.0, Color(0.9, 0.9, 0.85), Color(0.75, 0.75, 0.72))
	# pokladna u západní stěny: pult 3,5 m, boční zábrana, zadní police (cigarety, lihoviny)
	it.solid(Vector3(-3.25, 0.45, 2.4), Vector3(3.5, 0.9, 0.6), Color(0.85, 0.85, 0.82))
	it.deco(Vector3(-3.25, 0.92, 2.4), Vector3(3.55, 0.03, 0.65), Color(0.3, 0.3, 0.32))
	it.solid(Vector3(-1.6, 0.45, 1.5), Vector3(0.2, 0.9, 1.2), Color(0.85, 0.85, 0.82))
	it.deco(Vector3(-4.0, 1.1, 2.4), Vector3(0.4, 0.3, 0.4), Interior.DARK)                        # pokladna
	it.deco(Vector3(-4.0, 1.3, 2.25), Vector3(0.25, 0.12, 0.03), Color(0.3, 0.6, 0.3))
	it.deco(Vector3(-2.4, 0.95, 2.4), Vector3(0.5, 0.05, 0.4), Color(0.6, 0.6, 0.65))              # váha
	_shelf(it, -3.25, 0.75, 3.5, 0.3, true, PAL_SPIRIT, 2.0, 5)
	it.set_keeper(Vector3(-3.25, 0.0, 1.5), 0.0)
	it.add_object(Vector3(-3.25, 0.0, 3.2), 2.4, "place:obchod", "Prodavačka Jarka – pokladna")
	# čtyři regály: pečivo a nápoje u severní stěny, konzervy a drogerie v ostrůvcích
	_shelf(it, -2.5, -3.6, 4.0, 0.5, true, PAL_BREAD)
	_shelf(it, 2.0, -3.6, 4.0, 0.5, true, PAL_DRINKS)
	_shelf(it, -2.0, -0.8, 3.0, 0.5, true, PAL_CANS, 1.6)
	_shelf(it, 2.5, -0.8, 3.0, 0.5, true, PAL_DRUG, 1.6)
	# M3.3 prodavač/ka (`ProdavacPrace`): pokladna, kde stojí zákazník, a čela regálů k doplnění
	it.spots["pokladna"] = [it.to_global(Vector3(-4.0, 1.1, 2.4)), 0.0]
	it.spots["zakaznik"] = [it.to_global(Vector3(-2.6, 0.0, 1.2)), 0.0]
	for i in 4:
		var sp: Vector3 = [Vector3(-2.5, 1.0, -3.1), Vector3(2.0, 1.0, -3.1), Vector3(-2.0, 1.0, -0.3), Vector3(2.5, 1.0, -0.3)][i]
		it.spots["regal:%d" % i] = [it.to_global(sp), 0.0]
	# chladicí vitrína u východní stěny
	it.solid(Vector3(4.55, 0.9, -1.0), Vector3(0.8, 1.8, 3.0), Interior.WHITE)
	it.deco(Vector3(4.13, 1.0, -1.0), Vector3(0.03, 1.3, 2.8), GLASS)
	for y in [0.45, 0.85, 1.25]:
		for i in 6:
			it.deco(Vector3(4.11, y, -2.1 + i * 0.44), Vector3(0.03, 0.22, 0.3), PAL_DRINKS[(i + int(y * 5)) % 4])
	# košíky u dveří
	it.deco(Vector3(4.3, 0.3, 3.3), Vector3(0.4, 0.6, 0.5), Color(0.8, 0.2, 0.15))
	it.deco(Vector3(4.3, 0.75, 3.3), Vector3(0.4, 0.3, 0.5), Color(0.85, 0.3, 0.2))
	# okna, světla
	it.window("S", -1.0, hz, 1.5, 2.0, 1.1)
	it.window("E", 2.3, hx)
	it.lamp(Vector3(-3.0, 2.45, 2.0), 6.5)
	it.lamp(Vector3(0.0, 2.45, -1.0), 7.0)
	it.lamp(Vector3(3.5, 2.45, -1.5), 7.0)
	it.lamp(Vector3(3.0, 2.45, 2.5), 6.5)


# ------------------------------------------------------------------ Obecní úřad (12 × 8 m)
# Vlajka a znak obce se NEKRESLÍ (právní zásady obsahu) – DOPLNIT: případně obecná trikolóra bez znaku.
# DOPLNIT: obsluhu přepážky dělá `Place.keeper` (Starosta Novák); samostatná postava „úřednice“ zatím není.

static func _urad(it: Interior) -> void:
	it.title = "Obecní úřad"
	var hx := 6.0
	var hz := 4.0
	_room(it, hx, hz, -4.5, Color(0.88, 0.87, 0.82), Color(0.6, 0.6, 0.58))
	it.floor_patch(1.0, hx, -hz, hz, Color(0.55, 0.4, 0.28))
	it.wall_line(false, 1.0, -hz, hz, 0.15, [[1.8, 1.0]], Color(0.88, 0.87, 0.82))    # příčka chodba | kancelář, dveře
	# podatelna: přepážka přes celou šířku chodby, sklo s okénky
	it.solid(Vector3(-2.5, 0.55, -0.6), Vector3(7.0, 1.1, 0.5), Color(0.6, 0.5, 0.4))
	it.deco(Vector3(-2.5, 1.12, -0.6), Vector3(7.05, 0.04, 0.55), Color(0.35, 0.3, 0.25))
	it.deco(Vector3(-4.35, 1.65, -0.6), Vector3(2.3, 1.0, 0.03), GLASS)
	it.deco(Vector3(-1.5, 1.65, -0.6), Vector3(1.9, 1.0, 0.03), GLASS)
	it.solid(Vector3(-4.5, 0.375, -3.2), Vector3(2.0, 0.75, 0.8), Color(0.6, 0.5, 0.38))          # stůl úřednice
	it.deco(Vector3(-4.5, 1.0, -3.4), Vector3(0.45, 0.32, 0.05), Interior.DARK)
	it.solid(Vector3(-3.0, 0.225, -2.5), Vector3(0.42, 0.45, 0.42), Color(0.2, 0.2, 0.25))
	_shelf(it, -2.0, -3.75, 6.0, 0.3, true, PAL_FOLDERS, 2.0, 5)
	it.set_keeper(Vector3(-3.0, 0.0, -1.5), 0.0)
	it.add_object(Vector3(-3.0, 0.0, 0.4), 2.4, "place:urad", "Přepážka – Obecní úřad")
	# nástěnka a lavička na chodbě
	it.deco(Vector3(-5.95, 1.5, 2.0), Vector3(0.04, 1.0, 1.6), Color(0.65, 0.5, 0.3))
	for i in 5:
		it.deco(Vector3(-5.92, 1.5 + (i % 2) * 0.25 - 0.1, 1.45 + i * 0.3), Vector3(0.02, 0.28, 0.2), Color(0.95, 0.95, 0.9))
	it.add_object(Vector3(-5.2, 0.0, 2.0), 1.6, "notice", "Úřední deska")
	it.solid(Vector3(-2.5, 0.225, 3.55), Vector3(2.0, 0.45, 0.4), Interior.WOOD)
	# kancelář starosty: pracovní stůl, křeslo, židle pro návštěvu, knihovna (bez vlajky a znaku)
	it.solid(Vector3(3.5, 0.375, -1.5), Vector3(2.0, 0.75, 0.9), Color(0.4, 0.28, 0.18))
	it.deco(Vector3(3.5, 1.0, -1.7), Vector3(0.5, 0.32, 0.05), Interior.DARK)
	it.solid(Vector3(3.5, 0.3, -2.4), Vector3(0.55, 0.6, 0.55), Color(0.3, 0.2, 0.15))
	it.deco(Vector3(3.5, 0.9, -2.68), Vector3(0.55, 0.6, 0.08), Color(0.3, 0.2, 0.15))
	for x in [3.0, 4.0]:
		it.solid(Vector3(x, 0.225, -0.35), Vector3(0.42, 0.45, 0.42), Interior.WOOD)
	_shelf(it, 5.8, -1.0, 3.0, 0.4, false, PAL_FOLDERS, 2.0, 5)
	# okna, světla
	it.window("S", -1.0, hz)
	it.window("S", 3.5, hz)
	it.window("N", 3.5, -hz)
	it.window("E", 1.5, hx)
	it.lamp(Vector3(-3.5, 2.45, 2.0), 6.0)
	it.lamp(Vector3(-3.5, 2.45, -2.2), 5.0)
	it.lamp(Vector3(3.5, 2.45, 0.0), 6.5)


# ------------------------------------------------------------------ Pálenice U Kotla (8 × 7 m)

static func _palenice(it: Interior) -> void:
	it.title = "Pálenice U Kotla"
	var hx := 4.0
	var hz := 3.5
	_room(it, hx, hz, -2.5, Color(0.82, 0.78, 0.66), Color(0.5, 0.5, 0.48))
	# kotel na cihlovém topeništi s měděnou kupolí, kolona, chladicí trubka
	it.solid(Vector3(-2.6, 0.3, -1.8), Vector3(1.3, 0.6, 1.3), BRICK)
	it.deco(Vector3(-2.6, 0.32, -1.13), Vector3(0.4, 0.3, 0.04), Interior.DARK)
	it.deco_cyl(Vector3(-2.6, 1.05, -1.8), 0.6, 0.9, COPPER)
	it.deco(Vector3(-2.6, 1.55, -1.8), Vector3(0.05, 0.05, 0.05), COPPER)
	it.cyl_rot(Vector3(-2.6, 1.65, -1.8), 0.6, 0.3, COPPER.darkened(0.1), Vector3.ZERO)
	it.deco_cone(Vector3(-2.6, 2.05, -1.8), 0.12, 0.5, 0.5, COPPER)
	it.collider(Vector3(-2.6, 1.0, -1.8), Vector3(1.3, 2.0, 1.3))
	it.deco_cyl(Vector3(-0.9, 1.15, -2.7), 0.2, 2.3, COPPER)
	for y in [0.6, 1.4, 2.1]:
		it.deco_cyl(Vector3(-0.9, y, -2.7), 0.24, 0.06, COPPER.darkened(0.2))
	it.cyl_rot(Vector3(-1.75, 2.1, -2.25), 0.05, 1.9, COPPER, Vector3(0, 0.5, PI * 0.5))
	it.collider(Vector3(-0.9, 1.15, -2.7), Vector3(0.5, 2.3, 0.5))
	# sudy s kvasem u východní stěny
	for i in 4:
		var z := -2.7 + i * 0.95
		it.solid(Vector3(3.3, 0.48, z), Vector3(0.8, 0.95, 0.8), Color(0.5, 0.33, 0.18))
		it.deco_cyl(Vector3(3.3, 0.35, z), 0.43, 0.05, Color(0.25, 0.25, 0.27))
		it.deco_cyl(Vector3(3.3, 0.7, z), 0.43, 0.05, Color(0.25, 0.25, 0.27))
		it.deco_cyl(Vector3(3.3, 0.96, z), 0.2, 0.03, Color(0.15, 0.2, 0.3))
	# stůl s lahvemi, pult s palličem
	it.solid(Vector3(0.9, 0.4, -2.75), Vector3(1.8, 0.8, 0.8), Interior.WOOD)
	for i in 8:
		it.deco_cyl(Vector3(0.2 + i * 0.2, 0.94, -2.75 + (i % 2) * 0.15 - 0.07), 0.05, 0.28, PAL_SPIRIT[i % PAL_SPIRIT.size()])
	it.solid(Vector3(1.5, 0.55, 0.6), Vector3(2.6, 1.1, 0.55), Color(0.45, 0.3, 0.18))
	it.deco(Vector3(1.5, 1.12, 0.6), Vector3(2.7, 0.04, 0.6), Color(0.6, 0.42, 0.26))
	it.set_keeper(Vector3(1.5, 0.0, -0.4), 0.0)
	it.add_object(Vector3(1.5, 0.0, 1.7), 2.4, "place:palenice", "Palič Vojta – pult")
	# okna, světla
	it.window("N", 0.5, -hz)
	it.window("E", 1.8, hx)
	it.window("S", 1.5, hz)
	it.lamp(Vector3(-1.5, 2.45, -1.0), 6.0)
	it.lamp(Vector3(1.5, 2.45, 0.5), 6.0)


# ------------------------------------------------------------------ Vinný sklep (7 × 10 m, klenba)

static func _sklep(it: Interior) -> void:
	it.title = "Vinný sklep"
	var hx := 3.5
	var hz := 5.0
	_room(it, hx, hz, 0.0, Color(0.72, 0.68, 0.6), Color(0.45, 0.43, 0.4))
	# klenba: žebra z lomených segmentů + pilíře
	var pts := [Vector2(-3.4, 1.9), Vector2(-2.5, 2.25), Vector2(-1.3, 2.47), Vector2(0.0, 2.55),
		Vector2(1.3, 2.47), Vector2(2.5, 2.25), Vector2(3.4, 1.9)]
	for z in [-4.0, -2.0, 0.0, 2.0, 4.0]:
		for i in pts.size() - 1:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var mid := (a + b) * 0.5
			it.deco_rot(Vector3(mid.x, mid.y, z), Vector3(a.distance_to(b) + 0.05, 0.22, 0.4), Color(0.6, 0.57, 0.5),
				Vector3(0, 0, atan2(b.y - a.y, b.x - a.x)))
		for s in [-1.0, 1.0]:
			it.deco(Vector3(3.35 * s, 0.95, z), Vector3(0.3, 1.9, 0.4), Color(0.6, 0.57, 0.5))
	# ležaté sudy podél stěn
	for s in [-1.0, 1.0]:
		for z in [-0.5, 2.0, 4.0]:
			it.cyl_rot(Vector3(2.7 * s, 0.62, z), 0.6, 1.7, Color(0.5, 0.33, 0.18), Vector3(PI * 0.5, 0, 0))
			for dz in [-0.5, 0.5]:
				it.cyl_rot(Vector3(2.7 * s, 0.62, z + dz), 0.62, 0.06, Color(0.22, 0.22, 0.24), Vector3(PI * 0.5, 0, 0))
			it.collider(Vector3(2.7 * s, 0.62, z), Vector3(1.2, 1.2, 1.7))
	# degustační stůl se sklenicemi a stoličkami
	it.solid(Vector3(0, 0.475, 1.5), Vector3(2.4, 0.95, 0.9), Color(0.4, 0.28, 0.18))
	for i in 5:
		it.deco_cyl(Vector3(-0.9 + i * 0.45, 1.05, 1.5 + (i % 2) * 0.2 - 0.1), 0.035, 0.14, Color(0.8, 0.85, 0.85))
	for x in [-0.8, 0.8]:
		it.deco_cyl(Vector3(x, 0.35, 2.2), 0.17, 0.7, Color(0.3, 0.2, 0.15))
	# výčep sklepníka a police s lahvemi
	it.solid(Vector3(0, 0.55, -3.0), Vector3(3.0, 1.1, 0.5), Color(0.45, 0.3, 0.18))
	it.deco(Vector3(0, 1.12, -3.0), Vector3(3.1, 0.04, 0.55), Color(0.6, 0.42, 0.26))
	_shelf(it, 0.0, -4.75, 5.0, 0.3, true, PAL_WINE, 2.0, 5)
	it.set_keeper(Vector3(0.0, 0.0, -3.8), 0.0)
	it.add_object(Vector3(0.0, 0.0, -1.9), 2.4, "place:sklep", "Vinař Zdeněk – výčep")
	it.lamp(Vector3(0.0, 2.35, -3.0), 6.0)
	it.lamp(Vector3(0.0, 2.35, 0.5), 6.0)
	it.lamp(Vector3(0.0, 2.35, 3.5), 6.0)


# ------------------------------------------------------------------ Myslivecká chata (7 × 6 m)

static func _chata(it: Interior) -> void:
	it.title = "Myslivecká chata"
	var hx := 3.5
	var hz := 3.0
	_room(it, hx, hz, 1.5, Color(0.5, 0.36, 0.22), Color(0.45, 0.32, 0.2))
	# krb v severní stěně + komín, parůžky na štítcích (jen dekor)
	it.solid(Vector3(0, 0.6, -2.5), Vector3(1.6, 1.2, 0.6), STONE)
	it.deco(Vector3(0, 0.45, -2.19), Vector3(0.7, 0.6, 0.04), Interior.DARK)
	it.deco(Vector3(0, 0.35, -2.17), Vector3(0.4, 0.3, 0.03), Color(0.95, 0.5, 0.15))
	it.deco(Vector3(0, 1.25, -2.15), Vector3(1.8, 0.07, 0.7), Interior.WOOD)
	it.deco(Vector3(0, 1.9, -2.7), Vector3(0.8, 1.4, 0.35), STONE)
	it.lamp(Vector3(0.0, 0.7, -1.8), 3.5, false)
	for x in [-2.4, -1.2, 1.2, 2.4]:
		_antlers(it, Vector3(x, 1.8, -2.92), Vector3(0, 0, 1))
	_antlers(it, Vector3(3.42, 1.8, -0.5), Vector3(-1, 0, 0))
	# stůl s lavicemi
	it.solid(Vector3(0.8, 0.39, 0.6), Vector3(2.2, 0.78, 0.9), Color(0.55, 0.4, 0.25))
	for s in [-1.0, 1.0]:
		it.solid(Vector3(0.8, 0.225, 0.6 + 0.8 * s), Vector3(2.2, 0.45, 0.35), Interior.WOOD)
	# palandy u západní stěny (nocleh je venku pod přístřeškem – propojení nechává M1.4)
	it.collider(Vector3(-3.0, 0.95, 0.0), Vector3(0.9, 1.9, 2.1))
	for zz in [-1.0, 1.0]:
		for xx in [-3.4, -2.6]:
			it.deco(Vector3(xx, 0.95, zz), Vector3(0.06, 1.9, 0.06), Interior.WOOD_DARK)
	for y in [0.4, 1.35]:
		it.deco(Vector3(-3.0, y, 0.0), Vector3(0.9, 0.08, 2.0), Interior.WOOD_DARK)
		it.deco(Vector3(-3.0, y + 0.1, 0.0), Vector3(0.85, 0.12, 1.9), Color(0.35, 0.4, 0.3))
		it.deco(Vector3(-3.0, y + 0.18, -0.75), Vector3(0.5, 0.1, 0.3), Color(0.9, 0.9, 0.85))
	it.add_object(Vector3(-2.0, 0.0, 0.0), 1.6, "bunk", "Palanda (dekor – nocleh je venku pod přístřeškem)")
	# kuchyňský kout, myslivec
	it.solid(Vector3(3.2, 0.45, 1.5), Vector3(0.6, 0.9, 2.0), Color(0.6, 0.5, 0.38))
	it.deco(Vector3(3.2, 0.92, 1.5), Vector3(0.62, 0.03, 2.02), Color(0.3, 0.3, 0.32))
	it.set_keeper(Vector3(2.3, 0.0, -1.5), 0.0)
	it.add_object(Vector3(1.9, 0.0, -0.4), 2.4, "place:chata", "Myslivec Franta")
	it.window("S", -1.5, hz, 1.5, 0.8, 0.9)
	it.window("E", -1.0, hx, 1.5, 0.8, 0.9)
	it.lamp(Vector3(0.5, 2.45, 0.5), 5.5)
