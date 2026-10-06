## Obrazovkové efekty podle stavu hráče (promile, nevolnost, zranění, okno).
class_name DrunkFx
extends CanvasLayer

var body: BodyState
var blackout := 0.0
var _rect: ColorRect
var _mat: ShaderMaterial
var _hurt := 0.0
var _t := 0.0


func _ready() -> void:
	layer = 4
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/drunk.gdshader")
	_rect.material = _mat
	add_child(_rect)
	_rect.visible = false


func flash_hurt(amount: float) -> void:
	_hurt = clampf(_hurt + amount / 20.0, 0.0, 1.0)


func _process(delta: float) -> void:
	if body == null:
		return
	_t += delta
	var p := body.promile()
	var d := body.drunk_level()
	# M4.8: psilocybin (lysohlávky) jen jemné vlnění přes stávající uniform `drunk` – jen při zapnuté volbě pro dospělé
	if ItemsDB.adult_on and body.psilo > 0.05:
		d = maxf(d, clampf(body.psilo * 0.25, 0.0, 0.5))
	_hurt = move_toward(_hurt, 0.0, delta * 1.2)
	var dvis := smoothstep(0.9, 2.4, p)
	var bl := smoothstep(0.7, 2.8, p)
	var tun := smoothstep(2.3, 3.8, p) * 0.8
	var active := d > 0.01 or _hurt > 0.0 or blackout > 0.0 or body.nausea > 0.2
	_rect.visible = active
	if not active:
		return
	_mat.set_shader_parameter("drunk", d)
	_mat.set_shader_parameter("double_vision", dvis)
	_mat.set_shader_parameter("blur", bl)
	_mat.set_shader_parameter("tunnel", tun)
	_mat.set_shader_parameter("blackout", clampf(blackout, 0.0, 1.0))
	_mat.set_shader_parameter("nausea", clampf((body.nausea - 0.3) / 0.7, 0.0, 1.0))
	_mat.set_shader_parameter("hurt", _hurt)
	_mat.set_shader_parameter("time_s", _t)
