## Optimalizace CPU (17. 10. 2026): poloha a směr aktivní kamery pro LOD postav (`Humanoid`, `Villager`).
## Čte se jednou za snímek (první volající `refresh`), ostatní jen porovnávají čísla – žádné alokace ani
## dotazy na viewport za postavu. Bez kamery (`ok == false`) se LOD podle kamery nepoužije.
class_name LodCam
extends RefCounted

static var ok := false
static var pos := Vector3.ZERO
static var fwd := Vector3.FORWARD
static var _frame := -1


## Obnoví polohu kamery – jen poprvé v daném snímku (`Engine.get_process_frames`).
static func refresh(n: Node) -> void:
	var f := Engine.get_process_frames()
	if f == _frame:
		return
	_frame = f
	ok = false
	if n == null or not n.is_inside_tree():
		return
	var cam := n.get_viewport().get_camera_3d()
	if cam == null:
		return
	ok = true
	pos = cam.global_position
	fwd = -cam.global_transform.basis.z


## Čtverec vzdálenosti bodu od kamery (bez kamery INF).
static func dist2(p: Vector3) -> float:
	return pos.distance_squared_to(p) if ok else INF


## Bod leží za kamerou o víc než `margin` m (mimo zorné pole při jakémkoli rozumném FOV).
static func behind(p: Vector3, margin: float) -> bool:
	return ok and (p - pos).dot(fwd) < -margin
