## Provizorní místo na spaní (E → přečkat noc / zdřímnout si): seník pod plachtou za hospodou,
## dřevěná palanda pod přístřeškem u Myslivecké chaty. Spí se hůř než doma (méně zdraví, v mrazu zima),
## ale je to zadarmo a kousek od hospody. Kromě toho jde přespat kdekoli venku ve spacáku (Potraviny).
class_name SleepSpot
extends Node3D

## druh → [název, zdraví po noci, popis]
const KINDS := {
	"senik": ["Seník za hospodou", 15.0, "Balíky sena pod plachtou. Píchá to a voní, ale je tam sucho."],
	"palanda": ["Palanda u Myslivecké chaty", 20.0, "Dřevěná palanda s dekou pod přístřeškem."],
	"spacak": ["Spacák pod širákem", 12.0, "Karimatka a spacák, kdekoli venku."],
}

var kind := "senik"
var yaw := 0.0


static func make(k: String, pos: Vector3, yaw_: float) -> SleepSpot:
	var s := SleepSpot.new()
	s.kind = k
	s.yaw = yaw_
	s.position = pos
	s.rotation.y = yaw_
	s.name = "Nocleh_" + k
	return s


func title() -> String:
	return KINDS[kind][0]


func _ready() -> void:
	var k := MeshKit.new()
	var wood := Color(0.42, 0.28, 0.15)
	var dark := wood.darkened(0.3)
	match kind:
		"senik":
			var hay := Color(0.82, 0.7, 0.35)
			# dvě řady balíků + jeden nahoře jako „polštář“
			for i in 3:
				k.box(Vector3(-0.55 + i * 0.55, 0.2, 0.0), Vector3(0.52, 0.4, 1.0), hay.darkened(0.05 * i))
			k.box(Vector3(0.0, 0.2, 1.0), Vector3(1.6, 0.4, 1.0), hay.darkened(0.08))
			k.box(Vector3(0.0, 0.5, -0.3), Vector3(1.0, 0.2, 0.4), hay.lightened(0.05))
			# přístřešek: čtyři kůly a šikmá plachta
			for s in [-1.0, 1.0]:
				k.box(Vector3(1.05 * s, 1.0, -0.65), Vector3(0.09, 2.0, 0.09), dark)
				k.box(Vector3(1.05 * s, 0.7, 1.65), Vector3(0.09, 1.4, 0.09), dark)
			k.box(Vector3(0.0, 1.72, 0.5), Vector3(2.4, 0.03, 2.6), Color(0.2, 0.35, 0.25), Vector3(-0.23, 0, 0))
			# stará deka
			k.box(Vector3(0.1, 0.42, 0.6), Vector3(0.9, 0.03, 1.1), Color(0.55, 0.2, 0.15))
		"palanda":
			# rám a matrace
			for s in [-1.0, 1.0]:
				for z in [-0.95, 0.95]:
					k.box(Vector3(0.45 * s, 0.22, z), Vector3(0.08, 0.44, 0.08), dark)
			k.box(Vector3(0, 0.42, 0), Vector3(1.0, 0.06, 2.0), wood)
			k.box(Vector3(0, 0.5, 0.05), Vector3(0.9, 0.1, 1.85), Color(0.35, 0.4, 0.3))
			k.box(Vector3(0, 0.6, -0.72), Vector3(0.6, 0.12, 0.35), Color(0.85, 0.83, 0.78))
			k.box(Vector3(0, 0.57, 0.35), Vector3(0.92, 0.05, 1.0), Color(0.5, 0.15, 0.12))
			# přístřešek s pultovou střechou
			for s in [-1.0, 1.0]:
				k.box(Vector3(0.8 * s, 1.1, -1.2), Vector3(0.1, 2.2, 0.1), dark)
				k.box(Vector3(0.8 * s, 0.9, 1.2), Vector3(0.1, 1.8, 0.1), dark)
			k.box(Vector3(0.0, 2.05, 0.0), Vector3(2.0, 0.06, 2.9), Color(0.3, 0.22, 0.14), Vector3(0.14, 0, 0))
			k.box(Vector3(0.0, 1.1, -1.25), Vector3(1.7, 1.9, 0.05), wood.darkened(0.1))
		"spacak":
			k.box(Vector3(0, 0.02, 0), Vector3(0.6, 0.02, 1.9), Color(0.15, 0.4, 0.55))
			k.capsule(Vector3(0, 0.14, 0.05), 0.25, 1.7, Color(0.8, 0.3, 0.1), Vector3(PI / 2, 0, 0), Vector3(1.0, 0.55, 1.0))
	MeshKit.mesh_instance(self, k.commit(MeshKit.vc_material(0.9, 0.0, 0.0, false)), 250.0)
	if kind == "spacak":
		return
	# kolize (ležení i střecha – aby hráč neprošel skrz)
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.set_meta("surface", "budova")
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.7, 0.5, 2.0) if kind == "senik" else Vector3(1.0, 0.55, 2.0)
	cs.shape = bs
	cs.position = Vector3(0, bs.size.y * 0.5, 0.4 if kind == "senik" else 0.0)
	sb.add_child(cs)
	add_child(sb)
	# cedulka
	var l := Label3D.new()
	l.text = title()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 30
	l.outline_size = 8
	l.position = Vector3(0, 2.4, 0)
	l.modulate = Color(1.0, 0.95, 0.75)
	l.visibility_range_end = 25.0
	add_child(l)
