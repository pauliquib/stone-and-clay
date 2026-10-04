## Generátor interiérů z půdorysu (M1.8): rodinný dům, bytový dům (schodiště + dveře bytů), hospodářská budova (hala s nářadím).
## Všechny vnitřky jsou VYMYŠLENÉ (reálné interiéry neznáme – právní zásady obsahu), skládají se stavebnicí `Interior`
## (`wall_line`, `solid`, `deco`, `window`, `lamp`, `exit_door`, `add_object`) a `MeshKit`.
##
## Rozměry: z půdorysu nemovitosti (`Estate.info(id)`: `poly`, `door`, `normal`) – šířka = rozsah půdorysu podél fasády se
## dveřmi, hloubka = jak daleko budova sahá dovnitř od dveří; vstup je v jižní stěně (z = +hz) zhruba tam, kde jsou dveře
## na fasádě (lokální +X = doprava při vstupu). Bez půdorysu `DEFAULT_SIZE`. Seed = id budovy → vždy stejný interiér.
##
## `steps(it)` vrací pole kroků (Callable) – jeden krok = jedna místnost / podlaží; `InteriorStreamer` volá jeden krok za snímek
## a `Interior.flush_mesh` po každém kroku sloučí geometrii místnosti do jednoho meshe. Kolize: stěny, podlaha, strop a velký
## nábytek (postel, linka, skříň, stůl); drobnosti jsou jen dekor. Jedno OmniLight bez stínů na místnost.
##
## Místa uvnitř (`Interior.spots`): "res_seat" (obyvatel u stolu), "guest_seat" (host), "floor:<n>" (podlaží schodiště),
## "flat:<n>" (před dveřmi bytu) – vždy [globální pozice, yaw hráče (0 = čelem k −Z)]. Objekty E: "table", "stairs", "flat:<n>", "tools", "mailbox", "exit".
class_name InteriorGen
extends RefCounted

# ------------------------------------------------------------------ laditelné hodnoty

const DEFAULT_SIZE := Vector2(10.0, 8.0)     # m – bez půdorysu (šířka × hloubka)
const HOUSE_W := Vector2(7.0, 14.0)          # m – rozsah šířky rodinného domu (min, max)
const HOUSE_D := Vector2(6.0, 11.0)
const CORRIDOR := 1.4                        # m – šířka chodby od vchodu
const SIDE_MIN := 2.4                        # m – nejužší místnost vedle chodby
const BATH_D := 2.3                          # m – hloubka koupelny, když se vejde i pokojík
const ATTIC_MIN_D := 7.0                     # m – od této hloubky domu je na konci chodby žebřík na půdu (dekor)
const HALL_W := Vector2(6.0, 22.0)           # m – hospodářská budova
const HALL_D := Vector2(5.0, 14.0)
const HALL_H := {"barn": 4.2, "hall": 4.0, "garage": 2.9, "shed": 2.6}
const STAIR_HX := 3.5                        # m – půlrozměry chodby bytového domu
const STAIR_HZ := 3.0
const LEVEL_H := 3.3                         # m – rozestup podlaží schodiště (podlaha → podlaha)
const FLATS_PER_FLOOR := 4                   # nejvýš dveří bytů na podlaží (2 na západní, 2 na severní stěně)

const WALLS := [Color(0.88, 0.85, 0.76), Color(0.84, 0.86, 0.8), Color(0.9, 0.84, 0.72), Color(0.82, 0.8, 0.84)]
const WOODS := [Color(0.58, 0.42, 0.26), Color(0.5, 0.35, 0.22), Color(0.64, 0.5, 0.34)]
const TILES := [Color(0.72, 0.66, 0.55), Color(0.62, 0.62, 0.6), Color(0.7, 0.58, 0.48)]
const FABRIC := [Color(0.35, 0.4, 0.5), Color(0.5, 0.32, 0.28), Color(0.35, 0.45, 0.32), Color(0.55, 0.5, 0.38)]
const BEDDING := [Color(0.3, 0.42, 0.6), Color(0.6, 0.35, 0.35), Color(0.4, 0.55, 0.4), Color(0.75, 0.7, 0.5)]
const DOOR_WOOD := Color(0.42, 0.28, 0.16)
const CONCRETE := Color(0.52, 0.52, 0.5)
const HAY := Color(0.82, 0.72, 0.4)
const METAL := Color(0.45, 0.47, 0.5)
const HALL_KIND_NAME := {"barn": "Stodola", "garage": "Garáž", "hall": "Hospodářská hala", "shed": "Kůlna"}


static func steps(it: Interior) -> Array:
	match it.kind:
		"gen_house":
			return _house(it)
		"gen_flats":
			return _flats(it)
		"gen_hall":
			return _hall(it)
	return []


static func _info(it: Interior) -> Dictionary:
	if it.world == null or it.world.estate == null:
		return {}
	return it.world.estate.info(it.estate_id)


static func _rng(it: Interior, salt: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(it.estate_id) * 7919 + salt
	return rng


static func _pick(rng: RandomNumberGenerator, pal: Array) -> Color:
	return pal[rng.randi() % pal.size()]


## Rozměry z půdorysu: [šířka podél fasády se dveřmi, hloubka, poloha dveří na ose X od středu].
static func footprint(e: Dictionary) -> Array:
	var poly: PackedVector2Array = e.get("poly", PackedVector2Array())
	var door: Vector3 = e.get("door", Vector3.INF)
	var n: Vector3 = e.get("normal", Vector3(0, 0, 1))
	var n2 := Vector2(n.x, n.z)
	if poly.size() < 3 or door == Vector3.INF or n2.length() < 0.01:
		return [DEFAULT_SIZE.x, DEFAULT_SIZE.y, 0.0]
	n2 = n2.normalized()
	var u2 := Vector2(n2.y, -n2.x)            # lokální +X ve světě (doprava při vstupu)
	var d2 := Vector2(door.x, door.z)
	var smin := INF
	var smax := -INF
	var qmax := 0.0
	for v in poly:
		var r: Vector2 = v - d2
		var s: float = r.dot(u2)
		smin = minf(smin, s)
		smax = maxf(smax, s)
		qmax = maxf(qmax, -r.dot(n2))
	return [smax - smin, qmax, -(smin + smax) * 0.5]


## Zárubeň a otevřené dveřní křídlo (dekor) v otvoru příčky. `along_x` = stěna podél X (na z = fixed), `c` = střed otvoru,
## `into` = na kterou stranu stěny je křídlo otevřené (+1 / −1).
static func _door_deco(it: Interior, along_x: bool, fixed: float, c: float, into: float, y0 := 0.0, w := 0.9) -> void:
	var fr := Color(0.9, 0.88, 0.82)
	if along_x:
		it.deco(Vector3(c - w * 0.5, y0 + 1.02, fixed), Vector3(0.06, 2.05, 0.16), fr)
		it.deco(Vector3(c + w * 0.5, y0 + 1.02, fixed), Vector3(0.06, 2.05, 0.16), fr)
		it.deco(Vector3(c, y0 + 2.06, fixed), Vector3(w + 0.12, 0.06, 0.16), fr)
		it.deco(Vector3(c - w * 0.5 + 0.04, y0 + 1.0, fixed + into * 0.42), Vector3(0.04, 1.98, 0.8), DOOR_WOOD)
	else:
		it.deco(Vector3(fixed, y0 + 1.02, c - w * 0.5), Vector3(0.16, 2.05, 0.06), fr)
		it.deco(Vector3(fixed, y0 + 1.02, c + w * 0.5), Vector3(0.16, 2.05, 0.06), fr)
		it.deco(Vector3(fixed, y0 + 2.06, c), Vector3(0.16, 0.06, w + 0.12), fr)
		it.deco(Vector3(fixed + into * 0.42, y0 + 1.0, c - w * 0.5 + 0.04), Vector3(0.8, 1.98, 0.04), DOOR_WOOD)


static func _chair(it: Interior, c: Vector3, yaw: float, col: Color) -> void:
	it.deco(c + Vector3(0, 0.44, 0), Vector3(0.42, 0.05, 0.42), col)
	var back := Vector3(-sin(yaw), 0, -cos(yaw)) * 0.19      # opěradlo za zády (sedící se dívá ve směru yaw)
	it.deco(c + back + Vector3(0, 0.72, 0), Vector3(0.42 if absf(back.z) > 0.1 else 0.05, 0.5, 0.05 if absf(back.z) > 0.1 else 0.42), col)
	for sx in [-0.17, 0.17]:
		for sz in [-0.17, 0.17]:
			it.deco(c + Vector3(float(sx), 0.21, float(sz)), Vector3(0.04, 0.42, 0.04), col.darkened(0.2))


# ------------------------------------------------------------------ rodinný dům
#
#            N (z−)
#   +------------+-----+-------------+     ložnice (sever, strana A)   | chodba | koupelna (+ pokojík)
#   |  ložnice   |  ^  |  koupelna   |     obývák (jih, strana A)      | chodba | kuchyň se stolem (obyvatel)
#   |            |chod-+-------------|     strana A / B se podle seedu prohodí (západ ↔ východ)
#   +---  ---    | ba  |  pokojík    |
#   |  obývák    |     +---  -------|
#   |            |     |  kuchyň     |
#   +------------+[dv.]+-------------+
#            S (z+)

static func _house(it: Interior) -> Array:
	var e := _info(it)
	var fp := footprint(e)
	var w := clampf(float(fp[0]), HOUSE_W.x, HOUSE_W.y)
	var d := clampf(float(fp[1]), HOUSE_D.x, HOUSE_D.y)
	var hx := w * 0.5
	var hz := d * 0.5
	var lim := hx - SIDE_MIN - CORRIDOR * 0.5
	var xd := clampf(float(fp[2]), -lim, lim)
	var xl := xd - CORRIDOR * 0.5
	var xr := xd + CORRIDOR * 0.5
	var zs := hz - maxf(d * 0.5, 3.0)                  # příčka mezi přední (jih) a zadní (sever) částí
	var rng := _rng(it, 11)
	var wall_col := _pick(rng, WALLS)
	var swap := rng.randf() < 0.5                      # obývák na západě / východě
	var west := [-hx, xl]
	var east := [xr, hx]
	var a: Array = east if swap else west              # strana A: obývák + ložnice
	var b: Array = west if swap else east              # strana B: kuchyň + koupelna / pokojík
	var a_out: float = -hx if not swap else hx         # vnější stěna strany A (x)
	var b_out: float = hx if not swap else -hx
	var b_in: float = xr if not swap else xl           # stěna chodby na straně B
	var a_in: float = xl if not swap else xr
	var back_d := zs + hz
	var split := back_d >= BATH_D + 2.4
	var zb := -hz + BATH_D if split else zs            # koupelna na severu strany B, pod ní pokojík
	var title := "Dům %s" % (it.world.estate.label(it.estate_id) if it.world.estate else "")
	it.title = title
	var out := []
	out.append(func() -> void:
		it.shell(hx, hz)
		it.wall_line(true, -hz - 0.1, -hx - 0.2, hx + 0.2, 0.2, [], wall_col)
		it.wall_line(true, hz + 0.1, -hx - 0.2, hx + 0.2, 0.2, [[xd, 0.9]], wall_col)
		it.wall_line(false, -hx - 0.1, -hz, hz, 0.2, [], wall_col)
		it.wall_line(false, hx + 0.1, -hz, hz, 0.2, [], wall_col)
		# chodba: stěny s průchody do místností (dveře jako dekor)
		var a_doors := [[(zs + hz) * 0.5, 0.9], [(-hz + zs) * 0.5, 0.9]]
		var b_doors := [[zs + 0.7, 0.9], [(-hz + zb) * 0.5, 0.9]]      # kuchyň: průchod u příčky, stůl je u jižní stěny
		if split:
			b_doors.append([(zb + zs) * 0.5, 0.9])
		it.wall_line(false, a_in, -hz, hz, 0.12, a_doors, wall_col)
		it.wall_line(false, b_in, -hz, hz, 0.12, b_doors, wall_col)
		for dd in a_doors:
			_door_deco(it, false, a_in, float(dd[0]), signf(a_out - a_in))
		for dd in b_doors:
			_door_deco(it, false, b_in, float(dd[0]), signf(b_out - b_in), 0.0, float(dd[1]))
		it.wall_line(true, zs, float(a[0]), float(a[1]), 0.12, [], wall_col)
		it.wall_line(true, zs, float(b[0]), float(b[1]), 0.12, [], wall_col)
		if split:
			it.wall_line(true, zb, float(b[0]), float(b[1]), 0.12, [], wall_col)
		# chodba: dlažba, věšák, botník, rohožka, (schody na půdu)
		it.floor_patch(xl, xr, -hz, hz, _pick(rng, TILES))
		it.exit_door(xd, hz)
		it.deco(Vector3(xl + 0.05, 1.75, hz - 1.4), Vector3(0.04, 0.08, 0.8), Interior.WOOD_DARK)
		it.deco(Vector3(xl + 0.12, 1.3, hz - 1.25), Vector3(0.14, 0.8, 0.3), _pick(rng, FABRIC))
		it.solid(Vector3(xr - 0.18, 0.3, hz - 1.6), Vector3(0.32, 0.6, 0.8), Interior.WOOD)
		if d >= ATTIC_MIN_D:
			it.deco(Vector3(xd, it.ceil_h + 0.005, -hz + 0.6), Vector3(0.8, 0.02, 0.9), Interior.WOOD_DARK)   # poklop
			for s in [-0.22, 0.22]:
				it.deco(Vector3(xd + float(s), it.ceil_h * 0.5, -hz + 0.08), Vector3(0.04, it.ceil_h, 0.05), Interior.WOOD)
			for i in 8:
				it.deco(Vector3(xd, 0.3 + i * 0.3, -hz + 0.08), Vector3(0.44, 0.03, 0.04), Interior.WOOD)
		it.lamp(Vector3(xd, it.ceil_h - 0.15, 0.0), 4.5)
	)
	out.append(func() -> void:
		_living(it, rng, float(a[0]), float(a[1]), zs, hz, a_out)
	)
	out.append(func() -> void:
		_kitchen(it, rng, float(b[0]), float(b[1]), zs, hz, b_out)
	)
	out.append(func() -> void:
		_bedroom(it, rng, float(a[0]), float(a[1]), -hz, zs, a_out)
	)
	out.append(func() -> void:
		_bathroom(it, rng, float(b[0]), float(b[1]), -hz, zb, b_out)
		if split:
			_small_room(it, rng, float(b[0]), float(b[1]), zb, zs, b_out)
	)
	return out


## Obývák (x0..x1, z0..z1 = příčka..jižní stěna): gauč pod oknem, stolek, televize na příčce, knihovna u vnější stěny, kamna.
static func _living(it: Interior, rng: RandomNumberGenerator, x0: float, x1: float, z0: float, z1: float, x_out: float) -> void:
	var cx := (x0 + x1) * 0.5
	var rw := x1 - x0
	var fab := _pick(rng, FABRIC)
	it.floor_patch(x0, x1, z0, z1, _pick(rng, WOODS))
	var sw := minf(2.0, rw - 0.8)
	it.solid(Vector3(cx, 0.225, z1 - 0.5), Vector3(sw, 0.45, 0.85), fab)
	it.deco(Vector3(cx, 0.65, z1 - 0.15), Vector3(sw, 0.45, 0.18), fab.darkened(0.1))
	it.solid(Vector3(cx, 0.2, z1 - 1.5), Vector3(minf(1.1, rw - 1.2), 0.4, 0.6), Interior.WOOD)
	it.deco(Vector3(cx, 0.014, z1 - 1.4), Vector3(minf(2.2, rw - 0.4), 0.012, 1.6), _pick(rng, FABRIC).darkened(0.25))
	it.solid(Vector3(cx, 0.3, z0 + 0.3), Vector3(minf(1.4, rw - 1.0), 0.6, 0.45), Interior.WOOD_DARK)
	it.deco(Vector3(cx, 0.95, z0 + 0.2), Vector3(1.0, 0.6, 0.06), Interior.DARK)
	var sx := signf(x_out - cx)
	if z1 - z0 >= 3.2:
		it.solid(Vector3(x_out - sx * 0.22, 0.9, (z0 + z1) * 0.5 - 0.3), Vector3(0.4, 1.8, 1.0), Interior.WOOD)
		for i in 4:
			it.deco(Vector3(x_out - sx * 0.43, 0.45 + i * 0.4, (z0 + z1) * 0.5 - 0.3), Vector3(0.03, 0.26, 0.9),
				_pick(rng, FABRIC))
	if rw >= 3.6 and rng.randf() < 0.5:
		it.solid(Vector3(x_out - sx * 0.45, 0.5, z0 + 0.5), Vector3(0.6, 1.0, 0.6), Color(0.17, 0.17, 0.18))   # kamna
		it.deco_cyl(Vector3(x_out - sx * 0.45, (1.0 + it.ceil_h) * 0.5, z0 + 0.5), 0.08, it.ceil_h - 1.0, Color(0.14, 0.14, 0.15))
	it.window("S", cx, z1)
	it.window("W" if x_out < 0.0 else "E", (z0 + z1) * 0.5 + 0.9, x_out)
	it.lamp(Vector3(cx, it.ceil_h - 0.15, (z0 + z1) * 0.5), 5.5)


## Kuchyň se stolem: linka u vnější stěny, lednička, stůl se dvěma židlemi (obyvatel sedí na severní, host na jižní).
static func _kitchen(it: Interior, rng: RandomNumberGenerator, x0: float, x1: float, z0: float, z1: float, x_out: float) -> void:
	var cx := (x0 + x1) * 0.5
	var rd := z1 - z0
	var sx := signf(x_out - cx)
	var x_in := x1 if sx < 0.0 else x0
	it.floor_patch(x0, x1, z0, z1, _pick(rng, TILES))
	var lz := minf(2.4, rd - 1.3)
	var lc := z0 + 0.3 + lz * 0.5
	var unit := Color(0.85, 0.82, 0.75).lerp(_pick(rng, WOODS), rng.randf() * 0.6)
	it.solid(Vector3(x_out - sx * 0.3, 0.45, lc), Vector3(0.6, 0.9, lz), unit)
	it.deco(Vector3(x_out - sx * 0.3, 0.91, lc), Vector3(0.62, 0.03, lz), Color(0.35, 0.35, 0.38))
	it.deco(Vector3(x_out - sx * 0.3, 0.925, lc - lz * 0.25), Vector3(0.38, 0.02, 0.45), Color(0.6, 0.62, 0.65))   # dřez
	for i in 4:
		it.deco_cyl(Vector3(x_out - sx * (0.3 + (0.12 if i % 2 == 0 else -0.12)), 0.915, lc + lz * 0.25 + (0.12 if i < 2 else -0.12)),
			0.07, 0.015, Interior.DARK)
	it.deco(Vector3(x_out - sx * 0.17, 1.75, lc), Vector3(0.32, 0.7, lz), unit.lightened(0.1))
	it.solid(Vector3(x_out - sx * 0.33, 0.9, z1 - 0.4), Vector3(0.65, 1.8, 0.65), Interior.WHITE)            # lednička
	# stůl mezi linkou a chodbou
	var tx := (x_in + (x_out - sx * 0.6)) * 0.5
	var tz := z1 - 1.05
	var wood := _pick(rng, WOODS)
	it.solid(Vector3(tx, 0.375, tz), Vector3(0.7, 0.75, 0.9), wood)   # o 0,1 užší – v úzkých kuchyních zůstane průchod
	it.deco(Vector3(tx, 0.76, tz), Vector3(0.6, 0.01, 0.5), Color(0.9, 0.9, 0.85))                             # ubrus
	var seat_n := Vector3(tx, 0.0, tz - 0.8)      # kapsle hráče (r 0,3) nesmí zasahovat do stolu (hrana 0,45)
	var seat_s := Vector3(tx, 0.0, tz + 0.8)
	_chair(it, seat_n, 0.0, wood.darkened(0.15))
	_chair(it, seat_s, PI, wood.darkened(0.15))
	# yaw v `spots` = yaw hráče (0 = čelem k −Z): obyvatel sedí čelem k jihu (+Z), host čelem k severu
	it.spots["res_seat"] = [it.to_global(seat_n + Vector3(0, -0.05, 0)), PI]
	it.spots["guest_seat"] = [it.to_global(seat_s + Vector3(0, -0.05, 0)), 0.0]
	it.add_object(seat_s, 1.3, "table", "Stůl (posadit se)")
	it.window("W" if x_out < 0.0 else "E", lc, x_out, 1.55, 0.9, 0.9)
	it.lamp(Vector3(tx, it.ceil_h - 0.15, tz), 5.0)


## Ložnice: manželská postel hlavou k severní stěně, noční stolky, šatní skříň.
static func _bedroom(it: Interior, rng: RandomNumberGenerator, x0: float, x1: float, z0: float, z1: float, x_out: float) -> void:
	var cx := (x0 + x1) * 0.5
	var rw := x1 - x0
	var sx := signf(x_out - cx)
	it.floor_patch(x0, x1, z0, z1, _pick(rng, WOODS))
	var bw := minf(1.6, rw - 1.0)
	var bx := cx + sx * minf(0.3, (rw - bw) * 0.5 - 0.05)     # postel blíž k vnější stěně – u dveří z chodby zůstane průchod
	it.solid(Vector3(bx, 0.25, z0 + 1.05), Vector3(bw, 0.5, 2.0), Interior.WOOD_DARK)
	it.deco(Vector3(bx, 0.56, z0 + 1.15), Vector3(bw - 0.1, 0.14, 1.85), Color(0.9, 0.9, 0.92))
	it.deco(Vector3(bx, 0.66, z0 + 1.6), Vector3(bw - 0.1, 0.05, 1.0), _pick(rng, BEDDING))
	it.deco(Vector3(bx, 0.9, z0 + 0.06), Vector3(bw + 0.1, 0.9, 0.08), Interior.WOOD_DARK)
	if rw - bw >= 1.6:
		it.solid(Vector3(bx - bw * 0.5 - 0.25, 0.25, z0 + 0.25), Vector3(0.4, 0.5, 0.4), Interior.WOOD)
		it.solid(Vector3(bx + bw * 0.5 + 0.25, 0.25, z0 + 0.25), Vector3(0.4, 0.5, 0.4), Interior.WOOD)
	if z1 - z0 >= 3.3:
		it.solid(Vector3(x_out - sx * 0.3, 1.0, z1 - 0.8), Vector3(0.6, 2.0, 1.2), Color(0.55, 0.4, 0.26))
		it.deco(Vector3(x_out - sx * 0.61, 1.0, z1 - 0.8), Vector3(0.02, 1.9, 0.02), Interior.DARK)
	it.window("N", cx, z0)
	it.lamp(Vector3(cx, it.ceil_h - 0.15, (z0 + z1) * 0.5), 5.0)


## Koupelna: vana u severní stěny (nebo sprchový kout), umyvadlo se zrcadlem, WC.
static func _bathroom(it: Interior, rng: RandomNumberGenerator, x0: float, x1: float, z0: float, z1: float, x_out: float) -> void:
	var cx := (x0 + x1) * 0.5
	var rw := x1 - x0
	var sx := signf(x_out - cx)
	it.floor_patch(x0, x1, z0, z1, Color(0.8, 0.82, 0.84))
	var tile := Color(0.85, 0.9, 0.92).lerp(_pick(rng, TILES), 0.3)
	it.deco(Vector3(cx, 0.75, z0 + 0.02), Vector3(rw, 1.5, 0.02), tile)                                         # obklad
	if rw >= 2.0:
		it.solid(Vector3(cx, 0.28, z0 + 0.4), Vector3(minf(1.7, rw - 0.3), 0.56, 0.75), Interior.WHITE)
		it.deco(Vector3(cx, 0.55, z0 + 0.4), Vector3(minf(1.5, rw - 0.5), 0.02, 0.55), Color(0.7, 0.8, 0.85))
	else:
		it.deco(Vector3(cx, 0.03, z0 + 0.45), Vector3(0.85, 0.06, 0.85), Interior.WHITE)
		it.deco(Vector3(cx, 1.0, z0 + 0.9), Vector3(0.85, 2.0, 0.02), Color(0.75, 0.85, 0.9))
	var sz := minf(z1 - 0.5, z0 + 1.3)
	it.solid(Vector3(x_out - sx * 0.25, 0.8, sz), Vector3(0.45, 0.16, 0.55), Interior.WHITE)                    # umyvadlo
	it.deco(Vector3(x_out - sx * 0.04, 1.45, sz), Vector3(0.02, 0.6, 0.5), Color(0.75, 0.82, 0.88))            # zrcadlo
	if z1 - z0 >= 2.0:
		it.solid(Vector3(x_out - sx * 0.3, 0.2, z1 - 0.35), Vector3(0.38, 0.4, 0.5), Interior.WHITE)            # WC
		it.deco(Vector3(x_out - sx * 0.08, 0.55, z1 - 0.35), Vector3(0.16, 0.4, 0.4), Interior.WHITE)
	it.lamp(Vector3(cx, it.ceil_h - 0.15, (z0 + z1) * 0.5), 3.5)


## Pokojík (pracovna / dětský pokoj): válenda, psací stůl se židlí, polička.
static func _small_room(it: Interior, rng: RandomNumberGenerator, x0: float, x1: float, z0: float, z1: float, x_out: float) -> void:
	var cx := (x0 + x1) * 0.5
	var sx := signf(x_out - cx)
	it.floor_patch(x0, x1, z0, z1, _pick(rng, WOODS))
	it.solid(Vector3(x_out - sx * 0.47, 0.22, (z0 + z1) * 0.5), Vector3(0.9, 0.44, minf(1.95, z1 - z0 - 0.3)), Interior.WOOD)
	it.deco(Vector3(x_out - sx * 0.47, 0.5, (z0 + z1) * 0.5), Vector3(0.85, 0.12, minf(1.85, z1 - z0 - 0.4)), _pick(rng, BEDDING))
	if x1 - x0 >= 2.6:
		it.solid(Vector3(cx - sx * 0.3, 0.375, z0 + 0.35), Vector3(1.0, 0.75, 0.6), _pick(rng, WOODS))
		_chair(it, Vector3(cx - sx * 0.3, 0.0, z0 + 0.95), PI, Color(0.3, 0.3, 0.35))
	it.deco(Vector3(x_out - sx * 0.12, 1.6, (z0 + z1) * 0.5), Vector3(0.22, 0.03, 1.0), Interior.WOOD_DARK)
	it.window("W" if x_out < 0.0 else "E", (z0 + z1) * 0.5, x_out, 1.5, 0.9, 1.0)
	it.lamp(Vector3(cx, it.ceil_h - 0.15, (z0 + z1) * 0.5), 4.0)


# ------------------------------------------------------------------ bytový dům: chodba se schodištěm, dveře bytů
#
#   Každé podlaží je samostatná chodba 7 × 6 m nad sebou (rozestup LEVEL_H). Schodiště u východní stěny je dekor s kolizí;
#   mezi podlažími se chodí přes E u schodů („stairs“ → nabídka pater). Dveře bytů na západní a severní stěně, cedulka „Byt N“.
#   Vlastní byt → interiér „domov“ (M1.7); cizí byt je zamčený (zazvonit). Přízemí: vchod, schránky, nástěnka.

static func _flats(it: Interior) -> Array:
	var e := _info(it)
	var flats := maxi(int(e.get("flats", 2)), 1)
	var floors := maxi(maxi(int(e.get("floors", 1)), 1), ceili(float(flats) / float(FLATS_PER_FLOOR)))
	var per := mini(ceili(float(flats) / float(floors)), FLATS_PER_FLOOR)
	var rng := _rng(it, 23)
	var wall_col := _pick(rng, WALLS)
	it.title = "Bytový dům %s – chodba" % (it.world.estate.label(it.estate_id) if it.world.estate else "")
	var out := []
	for f in floors:
		var first: int = f * per + 1
		var last: int = mini(first + per - 1, flats)
		var lv: int = f
		out.append(func() -> void:
			_stair_level(it, lv, floors, first, last, wall_col)
		)
	return out


static func _stair_level(it: Interior, f: int, floors: int, first: int, last: int, wall_col: Color) -> void:
	var hx := STAIR_HX
	var hz := STAIR_HZ
	var y := f * LEVEL_H
	# podlaha, strop, stěny
	it.solid(Vector3(0, y - 0.15, 0), Vector3(hx * 2 + 1.2, 0.3, hz * 2 + 1.2), Color(0.55, 0.52, 0.48))
	it.solid(Vector3(0, y + it.ceil_h + 0.15, 0), Vector3(hx * 2 + 1.2, 0.3, hz * 2 + 1.2), Color(0.92, 0.9, 0.85))
	it.deco(Vector3(0, y + 0.006, 0), Vector3(hx * 2, 0.012, hz * 2), Color(0.62, 0.6, 0.55))                  # teraco
	it.deco(Vector3(-hx + 0.02, y + 0.6, 0), Vector3(0.02, 1.2, hz * 2), wall_col.darkened(0.25))               # olejový sokl
	it.deco(Vector3(0, y + 0.6, -hz + 0.02), Vector3(hx * 2, 1.2, 0.02), wall_col.darkened(0.25))
	it.wall_line(true, -hz - 0.1, -hx - 0.2, hx + 0.2, 0.2, [], wall_col, y)
	it.wall_line(true, hz + 0.1, -hx - 0.2, hx + 0.2, 0.2, [[0.0, 1.1]] if f == 0 else [], wall_col, y)
	it.wall_line(false, -hx - 0.1, -hz, hz, 0.2, [], wall_col, y)
	it.wall_line(false, hx + 0.1, -hz, hz, 0.2, [], wall_col, y)
	# schodiště u východní stěny: stupně nahoru k severu (poslední podlaží jen zábradlí), kolize jako blok
	var sx0 := hx - 1.2
	if f < floors - 1:
		for i in 9:
			it.deco(Vector3(sx0 + 0.6, y + 0.09 + i * 0.29, 1.4 - i * 0.29), Vector3(1.2, 0.18, 0.3), Color(0.6, 0.58, 0.54))
		it.collider(Vector3(sx0 + 0.6, y + 1.3, -0.1), Vector3(1.2, 2.6, 3.2))
	else:
		it.collider(Vector3(sx0 + 0.6, y + 0.5, -0.9), Vector3(1.2, 1.0, 1.6))
	it.deco(Vector3(sx0 - 0.02, y + 0.95, -0.4), Vector3(0.04, 0.05, 3.4), Interior.WOOD)                      # madlo
	for i in 7:
		it.deco(Vector3(sx0 - 0.02, y + 0.47, 1.2 - i * 0.55), Vector3(0.025, 0.95, 0.025), METAL)
	var stair_spot := Vector3(sx0 - 0.9, y + 0.1, 2.0)
	it.spots["floor:%d" % f] = [it.to_global(stair_spot), PI * 0.5]          # čelem na západ (do chodby)
	it.add_object(Vector3(sx0 - 0.4, y, 1.6), 1.6, "stairs", "Schodiště (%s)" % floor_name(f))
	it.label(Vector3(hx - 0.02, y + 2.2, 2.3), floor_name(f), -PI * 0.5, 0.004, Color(0.2, 0.2, 0.2))
	# dveře bytů: západní stěna (z = −1,3 / +1,3), severní stěna (x = −1,8 / +0,4)
	var slots := [["W", -1.3], ["W", 1.3], ["N", -1.8], ["N", 0.4]]
	var k := 0
	for n in range(first, last + 1):
		var sl: Array = slots[k % slots.size()]
		k += 1
		var side: String = sl[0]
		var t: float = sl[1]
		var door_c := Vector3(-hx + 0.04, y + 1.0, t) if side == "W" else Vector3(t, y + 1.0, -hz + 0.04)
		var nrm := Vector3(1, 0, 0) if side == "W" else Vector3(0, 0, 1)     # ze dveří do chodby
		var dsz := Vector3(0.06, 2.0, 0.9) if side == "W" else Vector3(0.9, 2.0, 0.06)
		it.deco(door_c, dsz, DOOR_WOOD.lerp(Color(0.6, 0.55, 0.45), 0.25 * float(n % 3)))
		it.deco(door_c + nrm * 0.03 + Vector3(0, 0.08, 0) + (Vector3(0, 0, 0.33) if side == "W" else Vector3(0.33, 0, 0)),
			Vector3(0.04, 0.04, 0.04) * (Vector3(2, 1, 1) if side == "W" else Vector3(1, 1, 2)), Color(0.75, 0.7, 0.4))
		it.deco(door_c + nrm * 0.5 + Vector3(0, -0.99, 0), Vector3(0.7, 0.02, 0.45) if side == "N" else Vector3(0.45, 0.02, 0.7),
			Color(0.35, 0.25, 0.2))
		var lyaw := PI * 0.5 if side == "W" else 0.0
		it.label(door_c + nrm * 0.05 + Vector3(0, 1.2, 0), "Byt %d" % n, lyaw, 0.004, Color(0.95, 0.92, 0.8))
		var front := door_c + nrm * 0.9 + Vector3(0, -0.9, 0)
		it.add_object(front, 1.3, "flat:%d" % n, "Byt %d" % n)
		# hráč vyjde z bytu čelem do chodby (směr nrm)
		it.spots["flat:%d" % n] = [it.to_global(front), atan2(-nrm.x, -nrm.z)]
	if f == 0:
		it.exit_door(0.0, hz, 1.1)
		for i in 6:                                                                                             # schránky
			it.deco(Vector3(1.6 + (i % 3) * 0.32, 1.3 + floori(i / 3.0) * 0.3, hz - 0.08), Vector3(0.3, 0.28, 0.14), Color(0.35, 0.4, 0.35))
		it.add_object(Vector3(2.0, y, hz - 0.8), 1.2, "mailbox", "Poštovní schránky")
		it.deco(Vector3(-1.9, 1.5, hz - 0.03), Vector3(0.9, 0.7, 0.03), Color(0.65, 0.5, 0.3))                  # nástěnka
		it.deco(Vector3(-2.05, 1.55, hz - 0.05), Vector3(0.3, 0.4, 0.01), Color(0.95, 0.95, 0.9))
		it.deco(Vector3(-1.7, 1.5, hz - 0.05), Vector3(0.25, 0.32, 0.01), Color(0.95, 0.95, 0.9))
	else:
		it.window("S", -1.5, hz, y + 1.5, 1.0, 1.1)
	it.lamp(Vector3(0.0, y + it.ceil_h - 0.15, 0.0), 6.5)


static func floor_name(f: int) -> String:
	return "přízemí" if f == 0 else "%d. patro" % f


# ------------------------------------------------------------------ hospodářská budova: hala s nářadím

static func _hall(it: Interior) -> Array:
	var e := _info(it)
	var bkind := String(e.get("kind", "hall"))
	var fp := footprint(e)
	var w := clampf(float(fp[0]), HALL_W.x, HALL_W.y)
	var d := clampf(float(fp[1]), HALL_D.x, HALL_D.y)
	var hx := w * 0.5
	var hz := d * 0.5
	var gw := clampf(float(e.get("door_w", 2.5)), 1.0, minf(3.2, w - 1.0))
	var xd := clampf(float(fp[2]), -hx + gw * 0.5 + 0.3, hx - gw * 0.5 - 0.3)
	it.ceil_h = float(HALL_H.get(bkind, 3.5))
	it.title = String(HALL_KIND_NAME.get(bkind, "Hospodářská budova"))
	var rng := _rng(it, 37)
	var wall_col := Color(0.72, 0.68, 0.6) if bkind != "garage" else Color(0.8, 0.8, 0.78)
	var out := []
	out.append(func() -> void:
		it.shell(hx, hz)
		it.floor_patch(-hx, hx, -hz, hz, CONCRETE if bkind != "barn" else Color(0.5, 0.42, 0.3))
		it.wall_line(true, -hz - 0.1, -hx - 0.2, hx + 0.2, 0.2, [], wall_col)
		it.wall_line(true, hz + 0.1, -hx - 0.2, hx + 0.2, 0.2, [[xd, gw]], wall_col)
		it.wall_line(false, -hx - 0.1, -hz, hz, 0.2, [], wall_col)
		it.wall_line(false, hx + 0.1, -hz, hz, 0.2, [], wall_col)
		it.exit_door(xd, hz, gw)
		if bkind == "barn" or bkind == "hall":
			for i in maxi(2, floori(w / 3.0)):                                                              # trámy
				var tx: float = -hx + (i + 0.5) * w / maxf(2.0, floorf(w / 3.0))
				it.deco(Vector3(tx, it.ceil_h - 0.2, 0), Vector3(0.2, 0.25, d), Interior.WOOD_DARK)
		var n_l := clampi(ceili(w / 8.0), 1, 3)
		for i in n_l:
			it.lamp(Vector3(-hx + (i + 0.5) * w / n_l, it.ceil_h - 0.2, 0.0), maxf(6.0, d * 0.8))
		it.window("N", -hx * 0.5, -hz, minf(2.2, it.ceil_h - 0.6), 1.0, 0.7)
	)
	# ponk s nářadím u západní stěny + deska s nářadím
	out.append(func() -> void:
		var wz := clampf(-hz + 1.6, -hz + 1.1, hz - 1.1)
		it.solid(Vector3(-hx + 0.4, 0.45, wz), Vector3(0.7, 0.9, 2.0), Interior.WOOD)
		it.deco(Vector3(-hx + 0.4, 0.92, wz), Vector3(0.72, 0.04, 2.02), Interior.WOOD_DARK)
		it.deco(Vector3(-hx + 0.55, 1.0, wz + 0.7), Vector3(0.2, 0.12, 0.15), METAL)                           # svěrák
		it.deco(Vector3(-hx + 0.03, 1.55, wz), Vector3(0.03, 0.9, 1.9), Color(0.6, 0.5, 0.35))                   # deska na nářadí
		var tools := [[0.7, 0.05, Color(0.5, 0.35, 0.2)], [0.35, 0.12, METAL], [0.55, 0.04, Color(0.8, 0.2, 0.15)],
			[0.45, 0.2, METAL], [0.3, 0.06, Color(0.2, 0.3, 0.6)], [0.6, 0.03, Color(0.5, 0.35, 0.2)]]
		for i in tools.size():
			var tl: Array = tools[i]
			it.deco(Vector3(-hx + 0.06, 1.55, wz - 0.75 + i * 0.3), Vector3(0.03, float(tl[0]), float(tl[1])), tl[2])
		it.add_object(Vector3(-hx + 1.2, 0.0, wz), 1.6, "tools", "Ponk s nářadím")
		# regál u severní stěny
		PublicInteriors._shelf(it, clampf(hx - 2.0, -hx + 2.0, hx), -hz + 0.35, minf(3.0, w * 0.4), 0.5, true,
			PublicInteriors.PAL_CANS, minf(2.0, it.ceil_h - 0.4), 4)
	)
	# obsah podle druhu: stodola (seno, vůz, vidle), garáž (pneumatiky, zvedák, skříň), hala (pytle, sudy, dřevo)
	out.append(func() -> void:
		match bkind:
			"barn":
				for i in 6:
					var bx: float = hx - 0.7 - (i % 3) * 1.25
					var by: float = 0.35 + floori(i / 3.0) * 0.7
					it.solid(Vector3(bx, by, -hz + 2.0 + (i % 2) * 0.1), Vector3(1.2, 0.7, 0.8), HAY.darkened(rng.randf() * 0.15))
				if w >= 9.0:
					it.solid(Vector3(0.0, 0.6, 0.5), Vector3(1.6, 0.5, 3.0), Interior.WOOD)                            # vůz
					for s in [-1.0, 1.0]:
						for zz in [-0.9, 1.4]:
							it.cyl_rot(Vector3(0.9 * s, 0.45, 0.5 + float(zz)), 0.45, 0.08, Interior.WOOD_DARK, Vector3(0, 0, PI * 0.5))
				for i in 3:
					it.deco_rot(Vector3(-hx + 1.2 + i * 0.25, 0.8, hz - 0.3), Vector3(0.04, 1.6, 0.04), Interior.WOOD,
						Vector3(0.2, 0, 0))
			"garage":
				for i in 4:
					it.cyl_rot(Vector3(hx - 0.5, 0.12 + i * 0.22, hz - 1.2), 0.33, 0.21, Color(0.12, 0.12, 0.13), Vector3.ZERO)
				it.solid(Vector3(hx - 0.35, 0.8, 0.0), Vector3(0.55, 1.6, 1.0), Color(0.7, 0.15, 0.12))                # skříň na nářadí
				it.deco(Vector3(0.0, 0.004, 0.0), Vector3(1.2, 0.006, 0.8), Color(0.2, 0.2, 0.2))                   # olejová skvrna
				it.deco(Vector3(-0.5, 0.12, -1.0), Vector3(0.3, 0.2, 1.0), Color(0.75, 0.15, 0.1))                  # zvedák
			_:
				for i in 5:
					it.solid(Vector3(hx - 0.6, 0.2, -hz + 1.0 + i * 0.7), Vector3(0.8, 0.4, 0.55),
						Color(0.75, 0.68, 0.5).darkened(rng.randf() * 0.2))
				for i in 3:
					it.solid(Vector3(hx - 0.5 - i * 0.7, 0.45, hz - 0.7), Vector3(0.6, 0.9, 0.6), Color(0.3, 0.4, 0.55))
					it.deco_cyl(Vector3(hx - 0.5 - i * 0.7, 0.91, hz - 0.7), 0.1, 0.02, Interior.DARK)
				for i in 8:                                                                                         # hráň dřeva
					it.cyl_rot(Vector3(-hx + 0.3, 0.12 + floori(i / 4.0) * 0.24, hz - 1.0 - (i % 4) * 0.26),
						0.11, 0.5, Color(0.55, 0.4, 0.25), Vector3(0, 0, PI * 0.5))
	)
	return out
