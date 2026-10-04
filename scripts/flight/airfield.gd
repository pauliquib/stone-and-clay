## Polní letiště (M6.5): posekaná trávníková dráha na louce jihozápadně od návsi,
## větrný rukáv (směr + síla z `Weather.wind_vector`) a otevřený hangár pro motorové rogalo.
## U hangáru stojí inzertní cedule – koupě ojetého triku (World.ul_buy_trike).
##
## Souřadnice dráhy (herní metry, počátek u domu hráče) – ověřeno proti DMR/landuse/trees/roofs:
##   práh A = (-440, 240), směr (sin 30°, cos 30°) ≈ (0.50, 0.87) → práh B = (-310, 465);
##   délka ~260 m, louka (landuse 2), max. výškový rozdíl ~3,7 m (~1,4 %), bez stromů a zástavby,
##   nejbližší polní cesta ~55 m od prahu B. Konstanty níže jsou laditelné.
class_name Airfield
extends Node3D

const RWY_A := Vector2(-440.0, 240.0)       # práh dráhy (start), x/z v herních metrech
const RWY_HEADING := 30.0                    # směr dráhy v herních stupních (0 = −Z)
const RWY_LEN := 260.0                       # m – délka posekaného pásu
const RWY_W := 16.0                          # m – šířka pásu
const RWY_HALF := 16.0                       # m – jak daleko od osy se počítá „na dráze“
const HANGAR_SIDE := 26.0                    # m – odsazení hangáru od osy dráhy (vlevo od startu)
const SOCK_SIDE := 18.0                      # m – větrný rukáv vedle prahu A
const SOCK_H := 5.0                          # m – stožár rukávu

var world: World
var ok := false
var hangar_pos := Vector3.ZERO               # střed hangáru (svět)
var hangar_yaw := 0.0                        # natočení hangáru (otevřená strana k dráze)
var sign_pos := Vector3.ZERO                 # inzertní cedule u hangáru
var _sock: Node3D                            # rukáv (otáčí se s větrem)


func setup(w: World) -> void:
	world = w
	name = "Letiste"
	_build_runway()
	_build_windsock()
	_build_hangar()
	_build_sign()
	ok = true


## Směr dráhy jako jednotkový vektor (x, z) – od prahu A k prahu B.
func dir() -> Vector2:
	return Vector2(sin(deg_to_rad(RWY_HEADING)), cos(deg_to_rad(RWY_HEADING)))


## Bod na zemi nad terénem.
func _ground(p: Vector2) -> Vector3:
	return Vector3(p.x, world.terrain.height_at(p.x, p.y), p.y)


## Je `pos` na dráze (do RWY_HALF od osy, AGL < ~6 m)? Pro přestupek `ul_pristani_mimo`.
func on_runway(pos: Vector3) -> bool:
	var a := _ground(RWY_A)
	var b := _ground(RWY_A + dir() * RWY_LEN)
	var ab := b - a
	var t := clampf((pos - a).dot(ab) / maxf(ab.length_squared(), 0.01), -0.08, 1.08)
	var near := a + ab * t
	var dy := pos.y - world.terrain.height_at(pos.x, pos.z)
	return Vector2(pos.x - near.x, pos.z - near.z).length() <= RWY_HALF and dy < 6.0


## Místo pro spawn triku – před hangárem, natočený podél dráhy (k prahu B).
func trike_spawn() -> Array:
	var p := _ground(RWY_A + dir() * 14.0 - side() * 16.0)
	return [p, _yaw_of(dir())]


## Bod pro teleport F2 → Letiště (u prahu A, pohled podél dráhy).
func teleport_spot() -> Array:
	var p := _ground(RWY_A - dir() * 8.0 + side() * 6.0)
	return [p, _yaw_of(dir())]


## Boční jednotkový vektor (vlevo od směru dráhy).
func side() -> Vector2:
	var d := dir()
	return Vector2(-d.y, d.x)


## Yaw uzlu, jehož −Z míří ve směru `d`.
func _yaw_of(d: Vector2) -> float:
	return atan2(-d.x, -d.y)


# ------------------------------------------------------------------ stavba

## Posekaná dráha: slabé desky světlejší trávy po úsecích kopírujících terén + bílé
## pražce na prazích (MeshKit, jeden mesh, bez kolize – jen vizuální odlišení pásu).
func _build_runway() -> void:
	var mk := MeshKit.new()
	var mow := Color(0.62, 0.6, 0.38)        # posečená louka (světlejší než okolní tráva)
	var white := Color(0.9, 0.9, 0.85)
	var d := dir()
	var s := side()
	var seg := 13.0                          # délka dílce pásu (m)
	var n := int(RWY_LEN / seg)
	for i in n:
		var c := RWY_A + d * (seg * (i + 0.5))
		var g := _ground(c)
		# deska lehce nakloněná podle sklonu v podélném směru
		var h_a := world.terrain.height_at(c.x - d.x * seg * 0.5, c.y - d.y * seg * 0.5)
		var h_b := world.terrain.height_at(c.x + d.x * seg * 0.5, c.y + d.y * seg * 0.5)
		var pitch := -atan2(h_b - h_a, seg)
		mk.box(g + Vector3(0, 0.07, 0), Vector3(RWY_W, 0.05, seg + 0.4), mow,
			Vector3(pitch, _yaw_of(d) + PI, 0.0))
	# pražce na obou prazích
	for t in [0.0, RWY_LEN]:
		var c: Vector2 = RWY_A + d * t
		for off in range(-3, 4, 2):
			var p := _ground(c + s * (float(off) * 2.0))
			mk.box(p + Vector3(0, 0.09, 0), Vector3(1.4, 0.06, 4.0), white, Vector3(0, _yaw_of(d), 0))
	var mi := MeshInstance3D.new()
	mi.mesh = mk.commit(MeshKit.vc_material(0.95))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Větrný rukáv: stožár + rameno + oranžovo-bílý kužel; v `_process` se točí po větru
## a podle síly větru se vztyčuje (klid = visí dolů, >8 m/s = vodorovně).
func _build_windsock() -> void:
	var sp := _ground(RWY_A + side() * SOCK_SIDE)
	var pole := MeshKit.new()
	pole.cylinder(Vector3(0, SOCK_H * 0.5, 0), 0.05, 0.07, SOCK_H, Color(0.75, 0.75, 0.78), Vector3.ZERO, 8)
	pole.box(Vector3(0, SOCK_H + 0.05, 0), Vector3(0.1, 0.1, 0.5), Color(0.6, 0.6, 0.62))   # rameno
	var mi := MeshInstance3D.new()
	mi.mesh = pole.commit(MeshKit.vc_material(0.6, 0.3))
	mi.position = sp
	add_child(mi)
	_sock = Node3D.new()
	_sock.position = sp + Vector3(0, SOCK_H, -0.25)
	add_child(_sock)
	var smk := MeshKit.new()
	var org := Color(0.95, 0.45, 0.1)
	# kužel rukávu směřuje do −Z (oboustranný materiál – vidět i zevnitř)
	for i in range(3):
		var z0 := -float(i) * 0.55
		var r0 := 0.28 - i * 0.07
		var r1 := 0.28 - (i + 1) * 0.07
		smk.cylinder(Vector3(0, 0, z0 - 0.27), r0, r1, 0.55,
			org if i % 2 == 0 else Color(0.95, 0.95, 0.9), Vector3(PI * 0.5, 0, 0), 10)
	var smi := MeshInstance3D.new()
	smi.mesh = smk.commit(MeshKit.vc_material(0.7, 0.0, 0.0, false))
	_sock.add_child(smi)


## Otevřený hangár (12 × 10 m, výška ~4,2 m): dvě boční stěny, zadní stěna, sedlová
## střecha. Stěny mají kolizi (statika), čelo k dráze je volné pro pojezd.
func _build_hangar() -> void:
	var d := dir()
	var s := side()
	hangar_yaw = _yaw_of(-s)                                     # čelo (−Z) míří k dráze
	hangar_pos = _ground(RWY_A + d * 16.0 + s * HANGAR_SIDE)
	var mk := MeshKit.new()
	var wall := Color(0.55, 0.58, 0.6)
	var roof := Color(0.35, 0.4, 0.45)
	mk.box(Vector3(-5.8, 2.1, 0), Vector3(0.25, 4.2, 10.0), wall)            # levá stěna
	mk.box(Vector3(5.8, 2.1, 0), Vector3(0.25, 4.2, 10.0), wall)             # pravá stěna
	mk.box(Vector3(0, 2.1, 4.9), Vector3(11.9, 4.2, 0.25), wall)             # zadní stěna
	mk.box(Vector3(0, 4.35, 0), Vector3(12.4, 0.15, 10.6), roof, Vector3(0.06, 0, 0))  # střecha
	mk.box(Vector3(0, 3.6, -4.95), Vector3(11.9, 1.0, 0.15), wall)           # přední převaz
	var mi := MeshInstance3D.new()
	mi.mesh = mk.commit(MeshKit.vc_material(0.8, 0.15))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var root := StaticBody3D.new()
	root.name = "Hangar"
	root.collision_layer = 1
	root.collision_mask = 0
	root.position = hangar_pos
	root.rotation.y = hangar_yaw
	root.add_child(mi)
	for cfg in [[Vector3(-5.8, 2.1, 0), Vector3(0.3, 4.2, 10.0)], [Vector3(5.8, 2.1, 0), Vector3(0.3, 4.2, 10.0)],
			[Vector3(0, 2.1, 4.9), Vector3(11.9, 4.2, 0.3)]]:
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = cfg[1]
		cs.position = cfg[0]
		cs.shape = bx
		root.add_child(cs)
	add_child(root)
	var lb := Label3D.new()
	lb.text = "LETIŠTĚ DUKELČICE"
	lb.font_size = 40
	lb.pixel_size = 0.008
	lb.modulate = Color(0.95, 0.9, 0.7)
	lb.position = Vector3(0, 4.0, -5.05)
	lb.rotation.y = PI
	lb.visibility_range_end = 300.0
	root.add_child(lb)


## Inzertní cedule u hangáru – koupě ojetého triku (interakce v `interactables`).
func _build_sign() -> void:
	sign_pos = _ground(RWY_A + dir() * 6.0 + side() * (HANGAR_SIDE - 6.0))
	var mk := MeshKit.new()
	mk.box(Vector3(0, 1.2, 0), Vector3(0.1, 2.4, 0.1), Color(0.3, 0.22, 0.14))
	mk.box(Vector3(0, 2.1, 0), Vector3(1.7, 0.8, 0.06), Color(0.9, 0.85, 0.6))
	var mi := MeshInstance3D.new()
	mi.mesh = mk.commit(MeshKit.vc_material(0.8))
	mi.position = sign_pos
	mi.rotation.y = _yaw_of(-side())          # čelem k dráze
	add_child(mi)
	var l := Label3D.new()
	l.text = "PRODÁM\nROGALO"
	l.font_size = 48
	l.pixel_size = 0.004
	l.modulate = Color(0.15, 0.1, 0.05)
	l.position = Vector3(0, 2.1, 0.045)
	mi.add_child(l)


## Interakce E u cedule: „Koupit ojeté rogalo“ (cena v `World.UL_TRIKE_KC`).
func interactables(id: int) -> Array:
	var p: Player = world.players.get(id)
	if p == null or p.inside != "":
		return []
	return [{"pos": sign_pos + Vector3(0, 1.4, 0), "r": 3.5, "kind": "custom",
		"text": "Inzerát: ojeté motorové rogalo (%s)" % Bazaar.kc(World.UL_TRIKE_KC),
		"action": func(pid: int): world.ul_buy_trike(pid)}]


## Rukáv ukazuje, KAM fouká vítr (kónus se stáčí po směru `wind_vector`), a jeho pokles
## sleduje sílu větru (0 m/s = visí dolů, ≥8 m/s = vodorovně).
func _process(_delta: float) -> void:
	if _sock == null or world == null or world.weather == null:
		return
	var wv := world.weather.wind_vector()
	var w2 := Vector2(wv.x, wv.z)
	if w2.length() > 0.05:
		_sock.rotation.y = atan2(-w2.x, -w2.y)            # −Z kuželu ve směru větru
	_sock.rotation.x = lerpf(_sock.rotation.x, -1.1 * (1.0 - clampf(world.weather.wind / 8.0, 0.0, 1.0)), 0.05)
