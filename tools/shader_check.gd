## Kontrola překladu shaderů (`--check-only` u `.gd` je nepokrývá). Otevře okno na ~10 snímků, nespouští hru.
##   godot --path . --rendering-method mobile -s res://tools/shader_check.gd 2>&1 | grep -E "SHADER ERROR|E +[0-9]+->|ERROR"
## Výstup musí být prázdný (vyzkoušej i --rendering-method forward_plus).
extends SceneTree

var _frames := 0


func _initialize() -> void:
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(0, 0, 8)
	var i := 0
	for p in _shaders("res://shaders"):
		var sh: Shader = load(p)
		if sh == null or sh.get_mode() != Shader.MODE_SPATIAL:
			continue
		var m := MeshInstance3D.new()
		m.mesh = BoxMesh.new()
		var mat := ShaderMaterial.new()
		mat.shader = sh
		m.material_override = mat
		m.position = Vector3(i * 1.5 - 6.0, 0, 0)
		root.add_child(m)
		i += 1


func _shaders(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gdshader"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_shaders(dir.path_join(d)))
	return out


func _process(_delta: float) -> bool:
	_frames += 1
	return _frames > 10
