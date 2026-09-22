@tool
extends Node3D

const ISLANDS := 8
const SPACING := 0.62
const SUBSTEP_H := 0.005  # AVBD fixed substep, matches ClothSim::H
const AvbdWorldScript := preload("res://addons/mujoco/avbd_world.gd")

var _world
var _meshes: Array[MeshInstance3D] = []
var _faces: PackedInt32Array = PackedInt32Array()
var _capturing := false
var _frames := 0

func _ready() -> void:
	_capturing = OS.get_cmdline_user_args().has("capture")
	_build_scene()
	_world = AvbdWorldScript.new()
	_world.islands = ISLANDS
	_world.substeps = 4
	_world.iters = 20
	_world.parallel = true
	add_child(_world)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.3, 0.4)
	mat.roughness = 0.85
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var f: PackedFloat64Array = _world.faces(0)
	for v in f:
		_faces.append(int(v))

	for i in range(_world.count()):
		var mi := MeshInstance3D.new()
		mi.material_override = mat
		mi.position = Vector3((float(i) - float(_world.count() - 1) * 0.5) * SPACING, 0.0, 0.0)
		add_child(mi)
		_meshes.append(mi)

func _process(_dt: float) -> void:
	if _world == null or not _world.alive():
		return
	_world.substeps = 4
	_world.step()
	for i in range(_meshes.size()):
		_update_island(i)
	_frames += 1
	if _capturing and _frames >= 300:
		get_tree().quit()

func _update_island(i: int) -> void:
	var v: PackedFloat64Array = _world.verts(i)
	var nv := int(v.size() / 3.0)
	if nv == 0 or _faces.is_empty():
		return
	var pts := PackedVector3Array()
	pts.resize(nv)
	for k in range(nv):
		pts[k] = Vector3(v[k * 3], v[k * 3 + 1], v[k * 3 + 2])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in range(0, _faces.size(), 3):
		st.add_vertex(pts[_faces[k]])
		st.add_vertex(pts[_faces[k + 1]])
		st.add_vertex(pts[_faces[k + 2]])
	st.generate_normals()
	_meshes[i].mesh = st.commit()

func _build_scene() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.1, 0.13)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.66)
	env.ambient_light_energy = 0.8
	we.environment = env
	add_child(we)
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(-0.9, 0.5, 0.0)
	add_child(light)
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 2.5, 3.2)
	cam.fov = 55.0
	add_child(cam)
	cam.look_at(Vector3(0.0, 0.55, 0.25), Vector3.UP)
