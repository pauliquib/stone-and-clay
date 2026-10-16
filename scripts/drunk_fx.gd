## Obrazovkové efekty podle stavu hráče (promile, nevolnost, zranění, okno).
class_name DrunkFx
extends CanvasLayer

var body: BodyState
static var enabled := true   # M4.8: Efekty obrazu (Esc → Nastavení); vypnuto = bez shaderu, stav v HUD zůstává
var blackout := 0.0
var _rect: ColorRect
var _mat: ShaderMaterial
var _hurt := 0.0
var _t := 0.0
## M8.D2b: prahy obrazových efektů – dřív čísla v `_process`, laditelné v menu F3 (Činnosti / Návykové látky a efekty).
static var HURT_FLASH_HP := 20.0      # zranění (HP) = plný červený záblesk
static var HURT_FADE := 1.2           # /s – odeznění záblesku
static var DOUBLE_FROM := 0.9         # ‰ – dvojité vidění od
static var DOUBLE_FULL := 2.4         # ‰ – dvojité vidění naplno
static var BLUR_FROM := 0.7           # ‰ – rozmazání od
static var BLUR_FULL := 2.8           # ‰ – rozmazání naplno
static var TUNNEL_FROM := 2.3         # ‰ – tunelové vidění od
static var TUNNEL_FULL := 3.8         # ‰ – tunelové vidění naplno
static var TUNNEL_MAX := 0.8          # nejsilnější tunelové vidění
static var PSILO_WAVE_K := 0.25       # vlnění obrazu na 1,0 psilocybinu
static var PSILO_WAVE_MAX := 0.5      # strop vlnění z psilocybinu
static var NAUSEA_FX_FROM := 0.3      # nevolnost, od které se obraz houpe


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
	_hurt = clampf(_hurt + amount / HURT_FLASH_HP, 0.0, 1.0)


func _process(delta: float) -> void:
	if body == null:
		return
	_t += delta
	if not enabled:
		_rect.visible = false
		return
	var p := body.promile()
	var d := body.drunk_level()
	# M4.8: psilocybin (lysohlávky) jen jemné vlnění přes stávající uniform `drunk` – jen při zapnuté volbě pro dospělé
	if ItemsDB.adult_on and body.psilo > 0.05:
		d = maxf(d, clampf(body.psilo * PSILO_WAVE_K, 0.0, PSILO_WAVE_MAX))
	_hurt = move_toward(_hurt, 0.0, delta * HURT_FADE)
	var dvis := smoothstep(DOUBLE_FROM, DOUBLE_FULL, p)
	var bl := smoothstep(BLUR_FROM, BLUR_FULL, p)
	var tun := smoothstep(TUNNEL_FROM, TUNNEL_FULL, p) * TUNNEL_MAX
	var ms := body.microsleep_fx()          # M8.16: mikrospánek = krátké zatmění
	var active := d > 0.01 or _hurt > 0.0 or blackout > 0.0 or body.nausea > 0.2 or ms > 0.0
	_rect.visible = active
	if not active:
		return
	_mat.set_shader_parameter("drunk", d)
	_mat.set_shader_parameter("double_vision", dvis)
	_mat.set_shader_parameter("blur", bl)
	_mat.set_shader_parameter("tunnel", tun)
	_mat.set_shader_parameter("blackout", clampf(maxf(blackout, ms), 0.0, 1.0))
	_mat.set_shader_parameter("nausea", clampf((body.nausea - NAUSEA_FX_FROM) / (1.0 - NAUSEA_FX_FROM), 0.0, 1.0))
	_mat.set_shader_parameter("hurt", _hurt)
	_mat.set_shader_parameter("time_s", _t)
