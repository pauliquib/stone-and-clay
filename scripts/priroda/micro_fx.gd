## Vzhled mikroklimatu u klienta (M8.9) – čte jen stav `World.micro` (`Microclimate`), simulaci nedělá.
##
## - **Údolní mlha jako vrstva:** výšková mlha `Environment` (`fog_height`, `fog_height_density`) s horní hranicí
##   = dno údolí pod kamerou (`Site.elev − Site.hand`) + `Microclimate.fog_top_m()`. Godot 4.3 počítá výškovou
##   mlhu bez ohledu na vzdálenost (body pod hranicí jsou zamlžené podle hloubky pod ní) → z kopce je vidět
##   „moře mlhy“ v údolí. Když je kamera uvnitř vrstvy, výšková mlha slábne a místo ní houstne obyčejná
##   (vzdálenostní) mlha – dohled ~200 m, ne bílá stěna u nohou. Volumetrická mlha se nepoužívá (cena GPU).
## - **Rosa a jinovatka:** globální uniformy `micro_dew` (0..1 množství rosy), `micro_frost` (0..1 – rosa na dně
##   údolí je zmrzlá) a `micro_frost_y` (svět Y, pod kterým je zem zmrzlá) → `terrain.gdshader`,
##   `vegetation.gdshader` (tráva lesklejší, pod mrazovou hranicí bělavá).
## Vypnutý přepínač `micro` / bez `site.bin` → výšková mlha 0 a uniformy 0 (vzhled jako dřív).
class_name MicroFx
extends RefCounted

const FOG_H_DENS := 0.08              # 1/m – výšková mlha při plné vrstvě (20 m pod hranicí ≈ 80 % mlhy)
const FOG_IN_DENS := 0.010            # hustota vzdálenostní mlhy, když je kamera uvnitř vrstvy (dohled ~200 m)
const INSIDE_BAND_M := 12.0           # m pod hranicí, kde už je kamera „uvnitř“
const ABOVE_BAND_M := 4.0             # m nad hranicí, kde přechod začíná
const FLOOR_RATE := 6.0               # m/s – jak rychle se posouvá dno údolí pod kamerou (žádné skoky)
const FLOOR_SNAP_M := 60.0            # větší rozdíl (teleport, let) → skočit rovnou
const MIN_TOP_M := 1.0                # tenčí vrstva se nekreslí

var micro: Microclimate
var _floor := NAN
var _off := true


## Jednou za snímek z `Atmosphere.update` (po nastavení obyčejné mlhy – jen přidává).
func update(env: Environment, cam: Camera3D, delta: float, indoor: float) -> void:
	var rs := RenderingServer
	if micro == null or cam == null or not micro.enabled():
		_disable(env)
		return
	var p := cam.global_position
	var fl := micro.floor_y_at(p.x, p.z)
	if is_nan(fl):
		_disable(env)
		return
	if is_nan(_floor) or absf(fl - _floor) > FLOOR_SNAP_M:
		_floor = fl
	else:
		_floor = move_toward(_floor, fl, delta * FLOOR_RATE)
	_off = false
	var top := micro.fog_top_m()
	var k := micro.fog_layer() if top >= MIN_TOP_M else 0.0
	var top_y := _floor + top
	var inside := smoothstep(top_y + ABOVE_BAND_M, top_y - INSIDE_BAND_M, p.y) * k
	env.fog_height = top_y
	env.fog_height_density = FOG_H_DENS * k * (1.0 - inside) * (1.0 - indoor)
	env.fog_density += FOG_IN_DENS * inside * inside * (1.0 - indoor)
	# rosa a jinovatka
	var dew := micro.dew_amount()
	var ft := micro.frost_top_m()
	rs.global_shader_parameter_set("micro_dew", dew)
	rs.global_shader_parameter_set("micro_frost", 1.0 if ft > Microclimate.NO_FROST_M + 1.0 else 0.0)
	rs.global_shader_parameter_set("micro_frost_y", _floor + ft)


func _disable(env: Environment) -> void:
	if _off:
		return
	_off = true
	env.fog_height_density = 0.0
	var rs := RenderingServer
	rs.global_shader_parameter_set("micro_dew", 0.0)
	rs.global_shader_parameter_set("micro_frost", 0.0)
	rs.global_shader_parameter_set("micro_frost_y", -10000.0)
