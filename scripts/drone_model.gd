## Procedurální model dronu (M6.1) + katalog modelů `MODELS` (specifikace pro simulaci `Drone`).
## Staví `MeshKit`em: trup s rameny do X, motorky na koncích, podvozek, kamerová koule pod předkem,
## navigační LEDky. Rotory jsou zvlášť (`rotor_mesh`) – v `Drone.vis` se točí nezávisle.
## Vysílačka (`remote`) se drží v ruce pilota (`Humanoid.hold`).
class_name DroneModel
extends RefCounted

## Specifikace modelů dronu. `kg` = vzletová hmotnost, `batt` = výdrž motorů v reálných sekundách
## (design ~30/38 min letu → herně škálované; mráz a sport zkracují), `range`/`range_nlos` = dosah
## řídicího signálu volný / za překážkou (m), `wind_k` = jak moc dron strhuje větrem (0.4..1.2),
## `needs_a1a3` = vyžaduje osvědčení A1/A3 (nad 250 g), `repair` = cena opravy po nehodě (Kč).
const MODELS := {
	"dron": {"name": "Dron Ptáček Mini", "kg": 0.249, "spd": 15.0, "sport": 19.0, "climb": 5.0,
		"batt": 720.0, "range": 1500.0, "range_nlos": 400.0, "wind_k": 1.0, "repair": 1500,
		"size": 0.13, "needs_a1a3": false, "col": Color(0.82, 0.83, 0.88)},
	"dron_velky": {"name": "Dron Ptáček Pro XL", "kg": 2.5, "spd": 16.0, "sport": 21.0, "climb": 6.0,
		"batt": 900.0, "range": 2000.0, "range_nlos": 500.0, "wind_k": 0.55, "repair": 4500,
		"size": 0.24, "needs_a1a3": true, "col": Color(0.2, 0.22, 0.27)},
}

const ROTOR_R := 0.85                  # poloměr rotoru × size (lopatky nepřesahují ~2× trup)


static func spec(id: String) -> Dictionary:
	return MODELS.get(id, MODELS["dron"])


static func ids() -> Array:
	return MODELS.keys()


static func is_drone(id: String) -> bool:
	return MODELS.has(id)


## Pozice čtyř rotorů (ramena do X) v lokálních souřadnicích trupu, na ose y.
static func rotor_offsets(id: String) -> Array:
	var s: float = float(spec(id)["size"])
	var a := s * 1.05
	return [Vector3(a, s * 0.42, a), Vector3(-a, s * 0.42, a), Vector3(a, s * 0.42, -a), Vector3(-a, s * 0.42, -a)]


## Trup: tělo, ramena, motorky, podvozek, kamerová gimbal-koule vepředu dole.
static func body_mesh(id: String) -> ArrayMesh:
	var sp := spec(id)
	var s: float = sp["size"]
	var col: Color = sp["col"]
	var dark := col.darkened(0.45)
	var k := MeshKit.new()
	k.box(Vector3(0, 0, 0), Vector3(s * 1.15, s * 0.42, s * 0.9), col)                  # tělo
	k.box(Vector3(0, s * 0.05, s * 0.52), Vector3(s * 0.62, s * 0.3, s * 0.16), dark)   # „obličej" / baterie
	for off in rotor_offsets(id):
		var d: Vector3 = off.normalized()
		k.box(Vector3(off.x * 0.55, off.y * 0.4, off.z * 0.55), Vector3(absf(d.x) * s * 0.62 + s * 0.1, s * 0.1, absf(d.z) * s * 0.62 + s * 0.1), col)
		k.cylinder(off, s * 0.13, s * 0.15, s * 0.16, dark, Vector3.ZERO, 10)            # motorek
	for sx in [-1.0, 1.0]:
		k.box(Vector3(sx * s * 0.42, -s * 0.42, s * 0.1), Vector3(s * 0.09, s * 0.42, s * 0.09), dark)   # nožky
		k.box(Vector3(sx * s * 0.42, -s * 0.64, s * 0.1), Vector3(s * 0.12, s * 0.07, s * 0.6), dark)    # lyžiny
	k.sphere(Vector3(0, -s * 0.36, s * 0.42), s * 0.17, dark, Vector3.ONE, Vector3.ZERO, 10, 6)        # gimbal
	k.sphere(Vector3(0, -s * 0.4, s * 0.5), s * 0.09, Color(0.05, 0.06, 0.08), Vector3.ONE, Vector3.ZERO, 10, 6)  # objektiv
	return k.commit()


## Jeden rotor: střed + dvě lopatky (točí se kolem y).
static func rotor_mesh(id: String) -> ArrayMesh:
	var s: float = float(spec(id)["size"]) * ROTOR_R
	var k := MeshKit.new()
	var c := Color(0.16, 0.16, 0.18)
	k.cylinder(Vector3.ZERO, s * 0.09, s * 0.11, s * 0.07, c, Vector3.ZERO, 10)
	for a in [0.0, PI]:
		k.box(Vector3(cos(a) * s * 0.5, 0, -sin(a) * s * 0.5), Vector3(s * 0.98, s * 0.02, s * 0.11), c,
			Vector3(0.05, a, 0.0))
	return k.commit()


## Malá navigační LEDka (emissivní) – bliká v `Drone._process`.
static func led_mesh(id: String) -> ArrayMesh:
	var s: float = float(spec(id)["size"])
	var k := MeshKit.new()
	k.sphere(Vector3(s * 0.4, s * 0.28, -s * 0.3), s * 0.06, Color(1.0, 0.05, 0.05), Vector3.ONE, Vector3.ZERO, 8, 4)
	k.sphere(Vector3(-s * 0.4, s * 0.28, -s * 0.3), s * 0.06, Color(0.05, 1.0, 0.15), Vector3.ONE, Vector3.ZERO, 8, 4)
	return k.commit(MeshKit.vc_material(0.4, 0.0, 0.9))


## Přistávací značka pod „domovský bod" (home) – plochý kruh na zemi.
static func pad_mesh(id: String) -> ArrayMesh:
	var s: float = float(spec(id)["size"])
	var k := MeshKit.new()
	k.cylinder(Vector3(0, 0.015, 0), s * 1.6, s * 1.6, 0.03, Color(0.9, 0.75, 0.1), Vector3.ZERO, 18)
	k.cylinder(Vector3(0, 0.032, 0), s * 1.2, s * 1.2, 0.02, Color(0.15, 0.15, 0.18), Vector3.ZERO, 18)
	k.box(Vector3(0, 0.045, 0), Vector3(s * 0.2, 0.02, s * 1.1), Color(0.95, 0.95, 0.9))    # písmeno „H" (2+1)
	k.box(Vector3(-s * 0.45, 0.045, 0), Vector3(s * 0.18, 0.02, s * 1.1), Color(0.95, 0.95, 0.9))
	k.box(Vector3(s * 0.45, 0.045, 0), Vector3(s * 0.18, 0.02, s * 1.1), Color(0.95, 0.95, 0.9))
	return k.commit(MeshKit.vc_material(0.7, 0.0, 0.25))


## Vysílačka do ruky pilota (Humanoid.hold drží MeshInstance3D).
static func remote() -> MeshInstance3D:
	var k := MeshKit.new()
	var c := Color(0.12, 0.13, 0.15)
	k.box(Vector3(0, 0.02, 0), Vector3(0.16, 0.035, 0.09), c)                       # tělo
	k.box(Vector3(-0.03, 0.045, -0.03), Vector3(0.05, 0.05, 0.02), Color(0.1, 0.35, 0.5))   # displej
	for sx in [-0.055, 0.055]:
		k.cylinder(Vector3(sx, 0.05, 0.02), 0.006, 0.006, 0.05, c, Vector3(-0.5, 0, 0), 8)  # anténky
		k.sphere(Vector3(sx * 0.6, 0.048, 0.045), 0.012, c, Vector3.ONE, Vector3.ZERO, 8, 4) # kniplíky
	var mi := MeshInstance3D.new()
	mi.mesh = k.commit(MeshKit.vc_material(0.5, 0.1))
	return mi
