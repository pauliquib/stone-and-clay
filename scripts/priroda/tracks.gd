## Stopy ve sněhu – hráč (podrážka), kůň (kopyto) a zvěř (srnec, divočák, zajíc).
##
## Jeden správce na svět (`World.tracks`): pro každý druh stopy jeden MultiMesh s kruhovým bufferem
## (nejstarší stopa se přepíše) → 5 draw callů a nejvýš ~600 stop. Stopa po `life` s reálného času
## vybledne (zavane / roztaje). Vše se ukazuje jen při `Weather.snow_cover > SNOW_MIN`; přidávat stopy
## má smysl jen tehdy (volající to kontroluje, `add` to ale hlídá také).
##
## Tvar stopy = seznam obdélníků [x, z, šířka, délka] (+Z je směr chůze):
##   boot – podrážka, hoof – kopyto (podkova), deer – párová spárkatá, boar – širší s paspárky,
##   hare – „Y“ (zadní nohy vpředu vedle sebe, přední za sebou).
## Počty a životnost se ladí v KINDS.
class_name Tracks
extends Node3D

const SNOW_MIN := 0.15            # od tolika sněhu se stopy zapisují
const SNOW_HIDE := 0.08           # pod tolika sněhu se skryjí všechny (sníh roztál)
const FADE_S := 15.0              # posledních tolik s života stopa bledne
const UPDATE_S := 0.5             # jak často se kontroluje stárnutí stop
const LIFT := 0.03                # o kolik nad terénem leží (m)
const KINDS := {
	"boot": {"n": 200, "life": 150.0, "col": Color(0.16, 0.2, 0.32, 0.85),
		"rects": [[0.0, 0.0, 0.14, 0.3]]},
	"hoof": {"n": 160, "life": 240.0, "col": Color(0.15, 0.18, 0.28, 0.85),
		"rects": [[-0.06, 0.0, 0.035, 0.13], [0.06, 0.0, 0.035, 0.13], [0.0, -0.06, 0.15, 0.035]]},
	"deer": {"n": 100, "life": 300.0, "col": Color(0.17, 0.2, 0.3, 0.8),
		"rects": [[-0.03, 0.0, 0.035, 0.085], [0.03, 0.0, 0.035, 0.085]]},
	"boar": {"n": 70, "life": 300.0, "col": Color(0.17, 0.2, 0.3, 0.8),
		"rects": [[-0.045, 0.0, 0.05, 0.09], [0.045, 0.0, 0.05, 0.09], [-0.05, -0.11, 0.025, 0.04],
			[0.05, -0.11, 0.025, 0.04]]},
	"hare": {"n": 70, "life": 300.0, "col": Color(0.17, 0.2, 0.3, 0.8),
		"rects": [[-0.04, 0.12, 0.05, 0.14], [0.04, 0.12, 0.05, 0.14], [0.0, -0.08, 0.035, 0.07],
			[0.0, -0.16, 0.035, 0.06]]},
}

var world: World
var _mm := {}                     # druh → MultiMesh
var _head := {}                   # druh → kam se zapíše další stopa
var _born := {}                   # druh → PackedFloat32Array (čas vzniku s, -1 = volno)
var _root_mi: Array = []
var _t := 0.0


func setup(w: World) -> void:
	world = w
	for k in KINDS:
		var d: Dictionary = KINDS[k]
		var n: int = d["n"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _mesh(d)
		mm.instance_count = n
		var born := PackedFloat32Array()
		born.resize(n)
		for i in n:
			born[i] = -1.0
			mm.set_instance_transform(i, Transform3D(Basis(), Vector3(0, -5000, 0)))
			mm.set_instance_color(i, Color(1, 1, 1, 1))
		var mi := MultiMeshInstance3D.new()
		mi.name = "Stopy_" + String(k)
		mi.multimesh = mm
		mi.top_level = true
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 220.0
		add_child(mi)
		mi.global_transform = Transform3D.IDENTITY
		_mm[k] = mm
		_head[k] = 0
		_born[k] = born
		_root_mi.append(mi)


func _mesh(d: Dictionary) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	for r in d["rects"]:
		var cx: float = r[0]
		var cz: float = r[1]
		var hw: float = float(r[2]) * 0.5
		var hl: float = float(r[3]) * 0.5
		var base := verts.size()
		for c in [Vector2(-hw, -hl), Vector2(hw, -hl), Vector2(hw, hl), Vector2(-hw, hl)]:
			verts.append(Vector3(cx + c.x, 0.0, cz + c.y))
			norms.append(Vector3.UP)
		idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = d["col"]
	m.surface_set_material(0, mat)
	return m


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## Zapíše stopu druhu `kind` na místo `pos` (výška se vezme z terénu), natočenou ve směru `yaw`.
func add(kind: String, pos: Vector3, yaw: float) -> void:
	if not _mm.has(kind) or world == null or world.weather == null or world.weather.snow_cover < SNOW_MIN:
		return
	var mm: MultiMesh = _mm[kind]
	var i: int = _head[kind]
	_head[kind] = (i + 1) % mm.instance_count
	var at := Vector3(pos.x, world.terrain.height_at(pos.x, pos.z) + LIFT, pos.z)
	mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, yaw), at))
	mm.set_instance_color(i, Color(1, 1, 1, 1))
	var born: PackedFloat32Array = _born[kind]
	born[i] = _now()
	_born[kind] = born


func _process(delta: float) -> void:
	if world == null or world.weather == null:
		return
	var snow: float = world.weather.snow_cover
	for mi in _root_mi:
		(mi as MultiMeshInstance3D).visible = snow > SNOW_HIDE
	_t += delta
	if _t < UPDATE_S:
		return
	_t = 0.0
	var now := _now()
	for k in KINDS:
		var life: float = KINDS[k]["life"]
		var mm: MultiMesh = _mm[k]
		var born: PackedFloat32Array = _born[k]
		for i in born.size():
			if born[i] < 0.0:
				continue
			var age := now - born[i]
			if age >= life:
				born[i] = -1.0
				mm.set_instance_transform(i, Transform3D(Basis(), Vector3(0, -5000, 0)))
			elif age > life - FADE_S:
				mm.set_instance_color(i, Color(1, 1, 1, clampf((life - age) / FADE_S, 0.0, 1.0)))
		_born[k] = born
