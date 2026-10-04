## Vstup jednoho hráče pro jeden fyzikální krok – čistá data, bez čtení klávesnice.
## Lokálně ji plní `LocalClient` z `Input` (klávesnice, myš, ovladač); v multiplayeru ji půjde
## plnit ze sítě. `Player` (chůze) i `Car` (řízení) čtou jen tuto strukturu.
class_name InputState
extends RefCounted

# --- pohyb (pěšky): jako Input.get_vector(left, right, forward, back) – x vpravo, y dozadu
var move := Vector2.ZERO
# --- řízení auta: síla akcí move_forward / move_back a volant (vlevo kladně)
var throttle := 0.0
var brake := 0.0
var steer := 0.0
# --- tlačítka
var jump := false             # drženo (proměnná výška skoku, ruční brzda v autě)
var jump_pressed := false     # stisknuto v tomto fyzikálním kroku
var sprint := false
var crouch := false
var reel := false             # levé tlačítko drženo (navíjení při rybaření M2.7, natahování luku M2.8)
var aim := false              # pravé tlačítko drženo (míření se zbraní, M2.8)
# --- pohled
var look_axis := Vector2.ZERO # pravá páčka ovladače (-1..1), zpracuje se ve fyzikálním kroku
var _look_delta := Vector2.ZERO   # nasčítaný pohyb myši (px) od posledního odběru
var _zoom_delta := 0.0            # kolečko myši (m)
var _toggle_view := false         # V / Y na ovladači


func add_look(rel: Vector2) -> void:
	_look_delta += rel


func add_zoom(d: float) -> void:
	_zoom_delta += d


func press_toggle_view() -> void:
	_toggle_view = true


## Odebere nasčítaný pohyb myši (px) – kdo ho odebere (postava / kamera auta), ten ho použije.
func take_look() -> Vector2:
	var d := _look_delta
	_look_delta = Vector2.ZERO
	return d


func take_zoom() -> float:
	var d := _zoom_delta
	_zoom_delta = 0.0
	return d


func take_toggle_view() -> bool:
	var t := _toggle_view
	_toggle_view = false
	return t


## Vše pustit (ztráta ovládání, odpojení).
func clear() -> void:
	move = Vector2.ZERO
	throttle = 0.0
	brake = 0.0
	steer = 0.0
	jump = false
	jump_pressed = false
	sprint = false
	crouch = false
	reel = false
	aim = false
	look_axis = Vector2.ZERO
	_look_delta = Vector2.ZERO
	_zoom_delta = 0.0
	_toggle_view = false
