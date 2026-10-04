## Ploty a ohrady (Fáze 7 – `docs/UPGRADE_PLAN.md` §10, procedurální varianta B): jeden uzel
## ve `World` (`World.fences`) staví obvodové ploty kolem výběhu koně (`Paddock`, typ
## WOODEN_POST s brankou `Paddock.GATE_W` uprostřed strany k domu – `Paddock` už vlastní
## ohradu nestaví, zůstává mu jen výbava: žlab a napáječka), zahrady (`Garden` plocha
## „zahrada“, latěný plot WOODEN_SLAT s brankou `GATE_GARDEN`) a pronajatého pole (plocha
## „pole“, ostnatý drát WIRE s brankou `GATE_FIELD`). Hráčem postavené úseky přibývají přes
## `build_line(..., persist=true)` a ukládají se (klíč `fences` v `SaveGame`).
##
## Geometrie: všechny úseky se skládají přes `MeshKit` do jednoho `ArrayMesh` (jeden draw
## call – ploty jsou statické, žádný MultiMesh). Kolize je JEDEN `StaticBody3D` „Kolize“
## s `BoxShape3D` na úsek (~2 m, tloušťka a výška ~1,1–1,3 m podle typu) – málo fyzických
## těles podle §14. Branka = vynechaný úsek (`gate_gaps` = indexy úseků `points[i]→[i+1]`),
## na jehož koncích stojí vyšší sloupek / pilíř / keř. Plot kopíruje terén – každý bod
## úseku se položí na `Terrain.height_at`, mezery pod plotem na mírném svahu kryje kolizní
## box sahající 0,15 m pod nižší konec.
##
## Stěhování s domovem (M1.7): `World.apply_home` volá nejdřív `clear_auto()` (staré
## procedurální ploty pryč – jinak by jejich kolize blokovala sondu `_find_spot` výběhu /
## zahrady), pak `paddock.relocate()` + `garden.relocate()` a nakonec `rebuild()`. Totéž
## (bez clearu) volají `Garden._add_plot` / `_remove_plot` při pronájmu a vypršení pole.
class_name FenceManager
extends Node3D

enum FenceType { WIRE, WOODEN_SLAT, WOODEN_POST, STONE_WALL, HEDGE }

## Parametry typů: h = výška plotu i kolize (m), thick = tloušťka kolizního boxu (m),
## step = nejdelší úsek mezi dvěma body (m; sloupky / kámen / keř se kladou na jeho konce),
## post = má samostatné sloupky (u kamene a živého plotu ne – jen pilíře/boky u branky).
const TYPES := {
	FenceType.WIRE: {"h": 1.2, "thick": 0.12, "step": 3.0, "post": true},
	FenceType.WOODEN_SLAT: {"h": 1.15, "thick": 0.12, "step": 2.0, "post": true},
	FenceType.WOODEN_POST: {"h": 1.3, "thick": 0.16, "step": 2.5, "post": true},
	FenceType.STONE_WALL: {"h": 1.1, "thick": 0.5, "step": 2.0, "post": false},
	FenceType.HEDGE: {"h": 1.35, "thick": 0.6, "step": 1.4, "post": false},
}
const MARGIN := 0.3              # přesah plotu ven z plochy záhonů (m) – ulička uvnitř oplocení
const MARGIN_PADDOCK := 0.15     # přesah plotu ven z obdélníku výběhu (m)
const GATE_GARDEN := 1.2         # šířka branky zahrady (m) – hráč jí musí projít
const GATE_FIELD := 3.0          # šířka branky pronajatého pole (m)
const VIS_END := 400.0           # viditelnost meshe (m)

const WOOD := Color(0.48, 0.34, 0.2)
const WOOD_DARK := Color(0.34, 0.24, 0.14)
const WIRE_C := Color(0.22, 0.2, 0.18)
const RUST := Color(0.4, 0.24, 0.12)
const STONE := Color(0.55, 0.53, 0.5)
const LEAF := Color(0.2, 0.42, 0.16)
const LEAF_DARK := Color(0.14, 0.3, 0.1)

var world: World
var _auto: Array = []            # procedurální úseky [{pts: PackedVector3Array, type: int, gaps: Array}]
var _custom: Array = []          # trvalé úseky (persist=true) – přežijí rebuild, ukládají se do save
var _body: StaticBody3D          # jediné kolizní těleso všech plotů
var _mi: MeshInstance3D          # jediný mesh všech plotů


func setup(w: World) -> void:
	world = w
	name = "Ploty"
	rebuild()


# ------------------------------------------------------------------ veřejné API

## Zahodí všechny ploty (procedurální i trvalé).
func clear() -> void:
	_auto.clear()
	_custom.clear()
	_rebuild_geometry()


## Zahodí jen procedurální ploty. `World.apply_home` to volá PŘED `paddock.relocate()` /
## `garden.relocate()`: jejich `_find_spot` ověřuje volné místo kolizním kvádrem (maska
## 1|8|16) a starý plot na stejném místě by ho blokoval → výběh/zahrada by ujela jinam.
func clear_auto() -> void:
	_auto.clear()
	_rebuild_geometry()


## Přegeneruje procedurální ploty podle aktuální polohy výběhu a ploch zahrady a všechny
## úseky (včetně trvalých) znovu vystaví. Volá `World.apply_home` (po relocate) a
## `Garden._add_plot` / `_remove_plot` (pronájem / vypršení pole, restore savu).
func rebuild() -> void:
	_auto.clear()
	if world != null and world.terrain != null:
		var pd: Paddock = world.paddock
		if pd != null and pd.ok:
			var rc: Array = _rect(pd.center, pd.yaw, pd.half.x + MARGIN_PADDOCK, pd.half.y + MARGIN_PADDOCK,
				Paddock.GATE_W)
			_auto.append({"pts": rc[0], "type": FenceType.WOODEN_POST, "gaps": rc[1]})
		var gd: Garden = world.garden
		if gd != null:
			for pl in gd.plots:
				var q: Garden.Plot = pl
				var ty := FenceType.WOODEN_SLAT
				var gw := GATE_GARDEN
				if q.key != "zahrada":
					ty = FenceType.WIRE
					gw = GATE_FIELD
				var rc2: Array = _rect(q.center, q.yaw, float(q.w) * 0.5 + MARGIN, float(q.d) * 0.5 + MARGIN, gw)
				_auto.append({"pts": rc2[0], "type": ty, "gaps": rc2[1]})
	_rebuild_geometry()


## Postaví řadu plotu `type` po bodech `points` (světové souřadnice; výška se dopočte
## z terénu). `gate_gaps` = indexy úseků (points[i] → points[i+1]), které se vynechají
## = branky; na jejich koncích stojí vyšší sloupek / pilíř / keř. persist=true → úsek
## přežije `rebuild()` a uloží se do save (hráčem postavené). Vrací index v `_custom`,
## nebo -1 u dočasného úseku (zahodí se při příštím `rebuild()`).
func build_line(points: PackedVector3Array, type: int, gate_gaps := [], persist := true) -> int:
	var run := {"pts": points, "type": clampi(type, 0, FenceType.HEDGE), "gaps": gate_gaps.duplicate()}
	if persist:
		_custom.append(run)
		_rebuild_geometry()
		return _custom.size() - 1
	_auto.append(run)
	_rebuild_geometry()
	return -1


## Všechny registrované úseky (procedurální + trvalé) – pro testy a kontrolu.
func runs() -> Array:
	return _auto + _custom


## Jediné kolizní těleso všech plotů (BoxShape3D na úsek).
func fence_body() -> StaticBody3D:
	return _body


## Jediný mesh všech plotů.
func fence_mesh() -> MeshInstance3D:
	return _mi


# ------------------------------------------------------------------ ukládání

## Ukládá se jen trvalé (hráčské) úseky – procedurální se po načtení přegenerují znovu
## podle polohy výběhu a ploch (`rebuild()`).
func to_dict() -> Dictionary:
	var rs := []
	for r in _custom:
		var ps := []
		for p in (r["pts"] as PackedVector3Array):
			ps.append([snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)])
		rs.append({"type": int(r["type"]), "gaps": (r["gaps"] as Array).duplicate(), "pts": ps})
	return {"runs": rs}


## Starý save bez klíče `fences` = žádné hráčské úseky; procedurální se postaví znovu.
func restore(d: Dictionary) -> void:
	_custom.clear()
	for e in d.get("runs", []):
		var pts := PackedVector3Array()
		for a in e.get("pts", []):
			if a is Array and a.size() >= 3:
				pts.append(Vector3(float(a[0]), float(a[1]), float(a[2])))
		if pts.size() < 2:
			continue
		var gaps := []
		for gi in e.get("gaps", []):
			var i := int(gi)
			if i >= 0 and i < pts.size() - 1:
				gaps.append(i)
		_custom.append({"pts": pts, "type": clampi(int(e.get("type", 0)), 0, FenceType.HEDGE), "gaps": gaps})
	rebuild()


# ------------------------------------------------------------------ pomocné – terén a tvary

func _ground(x: float, z: float) -> float:
	return world.terrain.height_at(x, z) if world != null and world.terrain != null else 0.0


## Klíč pozice pro deduplikaci sloupků na sdílených rozích úseků.
func _key(p: Vector3) -> Vector2i:
	return Vector2i(roundi(p.x * 10.0), roundi(p.z * 10.0))


## Obdélník hw × hd (poloviční rozměry) kolem `center`, natočený `yaw` (fwd = od domu):
## uprostřed strany k domu (−Z lokálně) je branka `gate_w` m. Vrací
## [body uzavřené smyčky ve světě, [index úseku branky]] – bez branky prázdný seznam.
func _rect(center: Vector3, yaw: float, hw: float, hd: float, gate_w: float) -> Array:
	var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var local: Array = []
	var gate := []
	var g := gate_w * 0.5
	if gate_w > 0.1 and g < hw - 0.4:
		local = [Vector2(-hw, -hd), Vector2(-g, -hd), Vector2(g, -hd), Vector2(hw, -hd),
			Vector2(hw, hd), Vector2(-hw, hd)]
		gate = [1]                 # úsek Vector2(-g,-hd) → Vector2(g,-hd)
	else:
		local = [Vector2(-hw, -hd), Vector2(hw, -hd), Vector2(hw, hd), Vector2(-hw, hd)]
	local.append(local[0])
	var pts := PackedVector3Array()
	for l in local:
		var p: Vector3 = center + right * (l as Vector2).x + fwd * (l as Vector2).y
		p.y = _ground(p.x, p.z)
		pts.append(p)
	return [pts, gate]


# ------------------------------------------------------------------ stavba

## Smaže uzly a znovu vystaví mesh + kolize všech registrovaných úseků (auto + custom).
func _rebuild_geometry() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_body = StaticBody3D.new()
	_body.name = "Kolize"
	_body.collision_layer = 1
	_body.collision_mask = 0
	_body.set_meta("surface", "plot")
	add_child(_body)
	var k := MeshKit.new()
	for run in _auto + _custom:
		_build_run(k, run)
	_mi = MeshInstance3D.new()
	_mi.name = "PlotyMesh"
	_mi.visibility_range_end = VIS_END
	add_child(_mi)
	if k.is_empty():
		_mi.mesh = ArrayMesh.new()
	else:
		_mi.mesh = k.commit(MeshKit.vc_material(0.85))


func _build_run(k: MeshKit, run: Dictionary) -> void:
	var pts: PackedVector3Array = run["pts"]
	var cfg: Dictionary = TYPES[int(run["type"])]
	var ty: int = int(run["type"])
	# koncové body branek → místo obyčejného sloupku vyšší sloupek branky
	var gate_pts := {}
	for gi in (run["gaps"] as Array):
		var i := clampi(int(gi), 0, pts.size() - 2)
		gate_pts[_key(pts[i])] = true
		gate_pts[_key(pts[i + 1])] = true
	var post_done := {}
	for i in range(pts.size() - 1):
		if (run["gaps"] as Array).has(i):
			continue
		_segment(k, pts[i], pts[i + 1], ty, cfg, gate_pts, post_done)


## Jeden úsek a→b: body na terénu v rozestupech ≤ step, na nich sloupky (deduplikované
## přes `post_done`; v bodech branky `gate_pts` vyšší sloupek) a výplň + kolize mezi nimi.
func _segment(k: MeshKit, a: Vector3, b: Vector3, ty: int, cfg: Dictionary,
		gate_pts: Dictionary, post_done: Dictionary) -> void:
	var flat := Vector2(b.x - a.x, b.z - a.z).length()
	var n := maxi(ceili(flat / float(cfg["step"])), 1)
	_post(k, a, ty, cfg, gate_pts, post_done)
	var prev := a
	for j in range(1, n + 1):
		var p := a.lerp(b, float(j) / n)
		p.y = _ground(p.x, p.z)
		_post(k, p, ty, cfg, gate_pts, post_done)
		_fill(k, prev, p, ty)
		_collide(prev, p, cfg)
		prev = p


## Sloupek / pilíř / keř v bodě úseku; v rohu branky (`gate_pts`) vyšší dřevěný sloupek,
## kamenný pilíř nebo větší keř podle typu. Bez sloupků u typů post=false (kromě branky).
func _post(k: MeshKit, p: Vector3, ty: int, cfg: Dictionary, gate_pts: Dictionary, post_done: Dictionary) -> void:
	var key := _key(p)
	if post_done.has(key):
		return
	post_done[key] = true
	var h: float = cfg["h"]
	var gate := gate_pts.has(key)
	match ty:
		FenceType.WOODEN_SLAT:
			var ph := 1.6 if gate else h + 0.2
			var w := 0.16 if gate else 0.11
			k.box(p + Vector3(0, ph * 0.5 - 0.12, 0), Vector3(w, ph, w), WOOD_DARK)
		FenceType.WOODEN_POST:
			var ph := 2.0 if gate else h + 0.3
			var w := 0.2 if gate else 0.14
			k.box(p + Vector3(0, ph * 0.5 - 0.15, 0), Vector3(w, ph, w), WOOD_DARK)
		FenceType.WIRE:
			var ph := 1.5 if gate else h + 0.15
			var w := 0.13 if gate else 0.08
			k.box(p + Vector3(0, ph * 0.5 - 0.1, 0), Vector3(w, ph, w), WOOD_DARK if gate else RUST.darkened(0.25))
		FenceType.STONE_WALL:
			if gate:
				k.box(p + Vector3(0, 0.7, 0), Vector3(0.6, 1.4, 0.6), STONE)
		FenceType.HEDGE:
			if gate:
				k.sphere(p + Vector3(0, 1.1, 0), 0.55, LEAF, Vector3(1.0, 1.6, 1.0), Vector3.ZERO, 8, 6)


## Výplň úseku a→b (oba konce už na terénu) podle typu: příčky + latě / dráty + ostny /
## kamenné sklady / keřový pás.
func _fill(k: MeshKit, a: Vector3, b: Vector3, ty: int) -> void:
	var d := b - a
	var len_ := d.length()
	if len_ < 0.05:
		return
	# natočení úseku (pitch podle svahu); rot_y = jen yaw, pro svislé díly (latě, keře)
	var rot := Vector3(-asin(clampf(d.y / len_, -1.0, 1.0)), atan2(d.x, d.z), 0.0)
	var rot_y := Vector3(0.0, rot.y, 0.0)
	var mid := (a + b) * 0.5
	match ty:
		FenceType.WOODEN_SLAT:
			for hh: float in [0.45, 0.95]:
				k.box(mid + Vector3(0, hh, 0), Vector3(0.04, 0.07, len_), WOOD, rot)
			var ns := maxi(1, roundi(len_ / 0.24))
			for s in ns:
				var t := (float(s) + 0.5) / ns
				var lp := a.lerp(b, t)
				lp.y = lerpf(a.y, b.y, t)
				k.box(lp + Vector3(0, 0.55, 0), Vector3(0.09, 0.92, 0.025), WOOD.lightened(0.12), rot_y)
		FenceType.WOODEN_POST:
			for hh: float in [0.55, 1.05]:
				k.box(mid + Vector3(0, hh, 0), Vector3(0.02, 0.02, len_), WIRE_C, rot)
		FenceType.WIRE:
			for hh: float in [0.35, 0.7, 1.05]:
				k.box(mid + Vector3(0, hh, 0), Vector3(0.015, 0.015, len_), WIRE_C, rot)
			# ostny na prostředním drátu – drobné nárůstky ~každých 0,9 m
			var nb := maxi(1, roundi(len_ / 0.9))
			for s in nb:
				var t := (float(s) + 0.5) / nb
				var lp := a.lerp(b, t)
				lp.y = lerpf(a.y, b.y, t)
				k.box(lp + Vector3(0, 0.7, 0), Vector3(0.09, 0.014, 0.014), RUST, rot)
		FenceType.STONE_WALL:
			k.box(mid + Vector3(0, 0.22, 0), Vector3(0.55, 0.44, len_), STONE, rot)
			k.box(mid + Vector3(0, 0.6, 0), Vector3(0.44, 0.34, len_), STONE.darkened(0.08), rot)
			# vrchní řada nepravidelných kamenů
			var nc := maxi(1, roundi(len_ / 0.45))
			for s in nc:
				var t := (float(s) + 0.5) / nc
				var lp := a.lerp(b, t)
				lp.y = lerpf(a.y, b.y, t)
				var jit := sin(float(s) * 2.7 + lp.x * 3.1) * 0.06
				k.box(lp + Vector3(jit, 0.85 + 0.04 * sin(float(s) * 5.1), 0), Vector3(0.34, 0.16, 0.3),
					STONE.lightened(0.08), rot)
		FenceType.HEDGE:
			# souvislý zelený pás + nakumštěné keře (výška kolísá podle pozice)
			k.box(mid + Vector3(0, 0.55, 0), Vector3(0.7, 1.1, len_), LEAF_DARK, rot)
			var nh := maxi(2, roundi(len_ / 0.75))
			for s in nh:
				var lp := a.lerp(b, (float(s) + 0.5) / nh)
				lp.y = _ground(lp.x, lp.z)
				var vv := 1.0 + 0.12 * sin(lp.x * 5.3 + lp.z * 4.1)
				var cc := LEAF.lerp(LEAF_DARK, 0.5 + 0.5 * sin(lp.x * 7.7 + lp.z * 6.3))
				k.sphere(lp + Vector3(0, 0.8, 0), 0.52, cc, Vector3(1.05, 1.35 * vv, 0.85), rot_y, 7, 5)


## Kolizní box úseku a→b (natáčí se podle svahu; saha 0,15 m pod nižší konec, ať zvěř
## neproleze pod plotem na mírném nerovném terénu). Všechny boxy visí na jednom `_body`.
func _collide(a: Vector3, b: Vector3, cfg: Dictionary) -> void:
	var d := b - a
	var len_ := d.length()
	if len_ < 0.05:
		return
	var rot := Vector3(-asin(clampf(d.y / len_, -1.0, 1.0)), atan2(d.x, d.z), 0.0)
	var mid := (a + b) * 0.5
	var h: float = cfg["h"]
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(float(cfg["thick"]), h + 0.3, len_)
	cs.shape = bs
	cs.transform = Transform3D(Basis.from_euler(rot), mid + Vector3(0, (h + 0.3) * 0.5 - 0.15, 0))
	_body.add_child(cs)
