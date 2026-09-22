extends Node3D

const ELF := "res://plans/mujoco.elf"
const MODEL := "res://plans/cloth.xml"
const SUBSTEPS := 8

var _sb: Object
var _holder: Node3D
var _cloth: MeshInstance3D
var _faces: PackedInt32Array = PackedInt32Array()

func _ready() -> void:
	_build_scene()
	_sb = ClassDB.instantiate("Sandbox")
	if _sb == null:
		push_error("Sandbox class missing; enable the godot_sandbox addon")
		return
	_sb.set("program", load(ELF))
	_sb.set_memory_max(1024)
	_sb.set_allocations_max(1 << 21)
	_sb.set_unboxed_arguments(true)
	if not _sb.vmcall("mjc_load_xml", FileAccess.get_file_as_bytes(MODEL)):
		push_error("cloth model failed to load")
		return
	_holder = Node3D.new()
	# MuJoCo is Z-up, Godot is Y-up.
	_holder.rotation = Vector3(-PI / 2.0, 0, 0)
	add_child(_holder)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.3, 0.4)
	mat.roughness = 0.85
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cloth = MeshInstance3D.new()
	_cloth.material_override = mat
	_holder.add_child(_cloth)
	# The triangle connectivity is fixed, so it is read once and reused.
	var f: PackedFloat64Array = _sb.vmcall("mjc_flexfaces")
	for v in f:
		_faces.append(int(v))

func _process(_dt: float) -> void:
	if _sb == null or _sb.vmcall("mjc_nflexvert") == 0:
		return
	for _s in range(SUBSTEPS):
		_sb.vmcall("mjc_step")
	_update_cloth()

func _update_cloth() -> void:
	var v: PackedFloat64Array = _sb.vmcall("mjc_flexverts")
	var nv := int(v.size() / 3.0)
	if nv == 0 or _faces.is_empty():
		return
	var pts := PackedVector3Array()
	pts.resize(nv)
	for i in range(nv):
		pts[i] = Vector3(v[i * 3], v[i * 3 + 1], v[i * 3 + 2])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(0, _faces.size(), 3):
		st.add_vertex(pts[_faces[i]])
		st.add_vertex(pts[_faces[i + 1]])
		st.add_vertex(pts[_faces[i + 2]])
	st.generate_normals()
	_cloth.mesh = st.commit()

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
	cam.position = Vector3(-0.25, 0.85, 1.35)
	cam.fov = 45.0
	add_child(cam)
	cam.look_at(Vector3(-0.25, 0.7, 0.0), Vector3.UP)
