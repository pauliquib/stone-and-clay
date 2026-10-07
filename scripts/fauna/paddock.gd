## Výběh pro koně u domova (M1.7: nájemník bytu má louku pronajatou blízko bydliště; stěhuje se s domovem přes `World.apply_home` → `relocate`): dřevěná ohrada s pevnou kolizí (kůň ani zvěř přes plot neprojdou)
## – obvodový plot a branku (3,4 m mezera uprostřed strany k domu, `GATE_W`) staví `FenceManager` (Fáze 7, typ WOODEN_POST; `gate_in`/`gate_out`/`contains` tu zůstávají jako čistá matematika nad `half`), žlab se senem a napáječka uvnitř.
##
## Místo hledá `World._ground_spot` (volná rovná plocha bez silnice, domu a auta) postupně pro velikosti
## z `SIZES` (největší 20×15 m). Když se nenajde nic, výběh se nepostaví (`ok = false`) a kůň stojí
## u domu jako dřív. Kůň se ve výběhu objeví při startu a `tether` (střed pastvy) je střed výběhu.
##
## Péče (E u žlabu, napáječky nebo u koně): Nakrmit (seno), Napojit, Vyčesat (3 s) – viz Horse.feed_hay /
## give_water / groom. Krmit a napájet jde, jen když je kůň u žlabu (do CARE_R m); přiveď ho hvízdnutím (G).
## Přivolaný kůň ze zavřeného výběhu projde brankou: `gate_in()` → `gate_out()` (Horse.call_to).
class_name Paddock
extends Node3D

const SIZES := [Vector2(20.0, 15.0), Vector2(16.0, 12.0), Vector2(13.0, 10.0)]   # šířka × hloubka (m)
const GATE_W := 3.4                  # šířka branky (m) – mezera v plotu od FenceManageru, uprostřed strany k domu
const CARE_R := 12.0                 # kůň musí být takhle blízko žlabu / napáječky (m)
const GROOM_S := 3.0                 # délka čištění (s)
const SPOT_R0 := 14.0                # hledání místa: nejblíž k domu (m)
const SPOT_R1 := 90.0                # … nejdál od domu (m)
const SPOT_TRIES := 240
const SPOT_MAX_DH := 2.5             # největší převýšení v ploše výběhu (m)
const SPOT_ROAD_GAP := 3.0           # odstup okraje výběhu od osy silnice (m, navíc k půlúhlopříčce)

var world: World
var ok := false
var center := Vector3.ZERO
var yaw := 0.0                       # směr od domu (+Z výběhu)
var half := Vector2.ZERO
var trough := Vector3.ZERO           # poloha žlabu se senem
var water := Vector3.ZERO            # poloha napáječky
var _busy := {}                      # id hráče → true (čistí koně)


func setup(w: World) -> void:
	world = w
	relocate()


## (Pře)hledá volné místo pro výběh u domova hráče 1 a ohradu na něm postaví. Volá `setup` a `World.apply_home`
## při každé změně domova (nájem v bytě, načtení savu, M4.7 koupě) – stará ohrada se zruší a postaví znovu.
func relocate() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	var a: Dictionary = world.home_grounds()
	ok = false
	center = Vector3.ZERO
	for sz in SIZES:
		var size: Vector2 = sz
		var sp: Array = _find_spot(a["door"], a["face"], size)
		if sp.is_empty():
			continue
		center = sp[0]
		yaw = sp[1]
		half = size * 0.5
		ok = true
		break
	if not ok:
		push_warning("Výběh u domova: nenašlo se volné místo – kůň stojí u domu bez ohrady.")
		return
	_build()


## Volné místo pro výběh `size` (šířka × hloubka) v okruhu SPOT_R0–SPOT_R1 od domu: pod všemi 9 body
## (rohy, středy stran, střed) je holý terén (ne silnice, cesta, dům ani strom), převýšení nejvýš
## SPOT_MAX_DH a v kvádru NAD nejvyšším bodem terénu nic nestojí (domy, rekvizity, auta). Kvádr je
## zvednutý nad terén schválně – jinak by na mírném svahu vždy „narazil“ do kolize terénu.
## Vrací [střed, yaw] (yaw = směr od domu) nebo [] .
func _find_spot(around: Vector3, face_from: Vector2, size: Vector2) -> Array:
	var space := world.get_world_3d().direct_space_state
	var bx := BoxShape3D.new()
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = bx
	q.collision_mask = 1 | 8 | 16
	var rng := RandomNumberGenerator.new()
	rng.seed = 2210                  # jen seed (historická hodnota – výběh zůstane na svém místě)
	var diag := size.length() * 0.5
	for i in SPOT_TRIES:
		var a := rng.randf() * TAU
		var r := lerpf(SPOT_R0, SPOT_R1, float(i) / SPOT_TRIES)
		var x := around.x + cos(a) * r
		var z := around.z + sin(a) * r
		if world.dist_to_roads(Vector2(x, z)) < diag + SPOT_ROAD_GAP:
			continue
		var away := Vector2(x, z) - face_from
		var yw := atan2(away.x, away.y)
		var fwd := Vector3(sin(yw), 0, cos(yw))
		var right := Vector3(cos(yw), 0, -sin(yw))
		var ok_ := true
		var hmin := INF
		var hmax := -INF
		for sx in [-1.0, 0.0, 1.0]:
			for sz_ in [-1.0, 0.0, 1.0]:
				var pp: Vector3 = Vector3(x, 0, z) + right * (size.x * 0.5 * float(sx)) + fwd * (size.y * 0.5 * float(sz_))
				var h: float = world.terrain.height_at(pp.x, pp.z)
				hmin = minf(hmin, h)
				hmax = maxf(hmax, h)
				var ray := PhysicsRayQueryParameters3D.create(Vector3(pp.x, h + 40.0, pp.z), Vector3(pp.x, h - 3.0, pp.z), 1)
				var hit := space.intersect_ray(ray)
				if hit.is_empty() or (hit["collider"] as Node).get_meta("surface", "") != "teren":
					ok_ = false
					break
			if not ok_:
				break
		if not ok_ or hmax - hmin > SPOT_MAX_DH:
			continue
		bx.size = Vector3(size.x + 1.0, 2.5, size.y + 1.0)
		q.transform = Transform3D(Basis(Vector3.UP, yw), Vector3(x, hmax + 0.2 + 1.25, z))
		if space.intersect_shape(q, 1).is_empty():
			return [Vector3(x, world.terrain.height_at(x, z), z), yw]
	return []


# ------------------------------------------------------------------ souřadnice

func _fwd() -> Vector3:
	return Vector3(sin(yaw), 0.0, cos(yaw))


func _right() -> Vector3:
	return Vector3(cos(yaw), 0.0, -sin(yaw))


## Místní souřadnice (x doprava, z od domu) → svět; výška z terénu.
func to_world(lx: float, lz: float) -> Vector3:
	var p := center + _right() * lx + _fwd() * lz
	p.y = world.terrain.height_at(p.x, p.z)
	return p


func contains(p: Vector3) -> bool:
	if not ok:
		return false
	var d := p - center
	var lx := d.dot(_right())
	var lz := d.dot(_fwd())
	return absf(lx) < half.x - 0.3 and absf(lz) < half.y - 0.3


## Bod uvnitř výběhu těsně za brankou a bod venku před ní (mezibody přivolaného koně).
func gate_in() -> Vector3:
	return to_world(0.0, -half.y + 2.0)


func gate_out() -> Vector3:
	return to_world(0.0, -half.y - 3.0)


## Kde kůň začíná: střed výběhu, pro víc hráčů vedle sebe. Vrací [poloha, natočení].
func horse_spot(id: int) -> Array:
	var p := to_world(((id - 1) % 3) * 2.5 - 2.5 if id > 1 else 0.0, 1.0)
	return [p, yaw + PI]


# ------------------------------------------------------------------ stavba

## Staví jen výbavu uvnitř výběhu (žlab, napáječka + jejich kolize). Obvodový plot s brankou
## staví `FenceManager` (Fáze 7, `World.fences.rebuild()` po `relocate`) – dřív tu byla jeho
## vlastní řada sloupků + kolizních boxů, nově je to úsek FenceType.WOODEN_POST.
func _build() -> void:
	var body := StaticBody3D.new()
	body.name = "Vybava"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var wood := Color(0.48, 0.34, 0.2)
	var k := MeshKit.new()
	var hx := half.x
	var hz := half.y
	# žlab se senem a napáječka na protější straně
	trough = to_world(-hx * 0.45, hz - 1.4)
	water = to_world(hx * 0.45, hz - 1.4)
	var rot_t := Vector3(0, yaw, 0)
	k.box(trough + Vector3(0, 0.3, 0), Vector3(2.0, 0.12, 0.6), wood, rot_t)
	k.box(trough + Vector3(0, 0.5, 0) + _fwd() * 0.27, Vector3(2.0, 0.3, 0.06), wood, rot_t)
	k.box(trough + Vector3(0, 0.5, 0) - _fwd() * 0.27, Vector3(2.0, 0.3, 0.06), wood, rot_t)
	for s: float in [-1.0, 1.0]:
		k.box(trough + _right() * s * 0.98 + Vector3(0, 0.5, 0), Vector3(0.06, 0.3, 0.6), wood, rot_t)
	k.box(trough + Vector3(0, 0.55, 0), Vector3(1.8, 0.16, 0.42), Color(0.78, 0.66, 0.3), rot_t)     # seno
	k.cylinder(water + Vector3(0, 0.25, 0), 0.62, 0.55, 0.5, Color(0.35, 0.36, 0.38))
	k.cylinder(water + Vector3(0, 0.49, 0), 0.52, 0.52, 0.03, Color(0.3, 0.5, 0.65))
	for tp in [trough, water]:
		var cs2 := CollisionShape3D.new()
		var b2 := BoxShape3D.new()
		b2.size = Vector3(2.0, 0.7, 0.8) if tp == trough else Vector3(1.2, 0.6, 1.2)
		cs2.shape = b2
		var tpv: Vector3 = tp
		cs2.transform = Transform3D(Basis(Vector3.UP, yaw), tpv + Vector3(0, 0.3, 0))
		body.add_child(cs2)
	var mi := MeshKit.mesh_instance(self, k.commit(MeshKit.vc_material(0.85)), 400.0)
	mi.name = "VybavaMesh"


# ------------------------------------------------------------------ péče o koně (E)

func interactables(id: int) -> Array:
	var out := []
	var p: Player = world.players.get(id)
	if not ok or p == null or p.horse != null:
		return out
	out.append({"pos": trough, "r": 2.8, "kind": "custom", "text": "Žlab se senem – nakrmit koně", "action": _care_menu})
	out.append({"pos": water, "r": 2.8, "kind": "custom", "text": "Napáječka – napojit koně", "action": _care_menu})
	var h: Horse = world.fauna.horse_of(id) if world.fauna else null
	if h != null and h.rider == null and h.global_position.distance_to(p.global_position) < 3.2:
		out.append({"pos": h.global_position, "r": 3.2, "kind": "custom", "text": "Kůň – péče (%s)" % h.care_text(),
			"action": _care_menu})
	return out


func _care_menu(id: int) -> void:
	var p: Player = world.players.get(id)
	var h := world.fauna.horse_of(id)
	if p == null or h == null:
		return
	var at_trough := h.global_position.distance_to(trough) < CARE_R or h.global_position.distance_to(water) < CARE_R
	var near_me := h.global_position.distance_to(p.global_position) < 4.0 and h.rider == null
	var text := "Kůň: %s." % h.care_text()
	if not at_trough:
		text += "\nKůň je daleko od žlabu – zahvízdej na něj [G] nebo ho dovez do výběhu."
	var opts := [
		["Nakrmit (seno)", _feed.bind(id), at_trough],
		["Napojit", _drink.bind(id), at_trough],
		["Vyčesat (%d s)" % int(GROOM_S), _groom.bind(id), near_me],
	]
	world.notify(id, "open_menu", ["Kůň – péče", text, opts])


func _feed(id: int) -> void:
	var h := world.fauna.horse_of(id)
	if h == null:
		return
	h.feed_hay()
	world.notify(id, "show_message", ["Kůň se pustil do sena. (sytost %d %%)" % roundi(h.fed * 100.0), 3.0])


func _drink(id: int) -> void:
	var h := world.fauna.horse_of(id)
	if h == null:
		return
	h.give_water()
	world.notify(id, "show_message", ["Kůň se napil. (napojení %d %%)" % roundi(h.watered * 100.0), 3.0])


func _groom(id: int) -> void:
	var p: Player = world.players.get(id)
	var h := world.fauna.horse_of(id)
	if p == null or h == null or _busy.has(id):
		return
	_busy[id] = true
	p.controls_locked = true
	world.notify(id, "show_message", ["Čistíš koně kartáčem…", GROOM_S])
	await get_tree().create_timer(GROOM_S).timeout
	_busy.erase(id)
	if is_instance_valid(p):
		p.controls_locked = false
	if is_instance_valid(h):
		h.groom()
		world.notify(id, "show_message", ["Kůň je vyčesaný a spokojený – rychleji odpočívá.", 3.0])
