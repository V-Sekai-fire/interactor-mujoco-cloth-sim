@tool
extends Node3D

const ISLANDS := 8
const SPACING := 0.62
const AvbdWorldScript := preload("res://addons/mujoco/avbd_world.gd")
const BAR_Y := 1.2
const BAR_Z := 0.7
const BAR_SWAY := 0.0
const BAR_RATE := 0.4

var _world
var _meshes: Array[MeshInstance3D] = []
var _faces: PackedInt32Array = PackedInt32Array()
var _boundary: PackedInt32Array = PackedInt32Array()
var _capturing := false
var _frames := 0
var _bar_t := 0.0
var _bar: MeshInstance3D

func _ready() -> void:
	_capturing = OS.get_cmdline_user_args().has("capture")
	_build_scene()
	_world = AvbdWorldScript.new()
	_world.islands = ISLANDS
	_world.nx = 6
	_world.ny = 8
	_world.substeps = 4
	_world.iters = 20
	_world.parallel = true
	add_child(_world)

	var f: PackedFloat64Array = _world.faces(0)
	for v in f:
		_faces.append(int(v))
	_boundary = _compute_boundary(_faces)

	var n: int = _world.count()
	for i in range(n):
		var mat := StandardMaterial3D.new()
		var t: float = 0.0 if n <= 1 else float(i) / float(n - 1)
		mat.albedo_color = Color.from_hsv(lerpf(0.97, 0.78, t), lerpf(0.62, 0.5, t), 0.82)
		mat.roughness = 0.68
		mat.metallic_specular = 0.35
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.backlight_enabled = true
		mat.backlight = Color(0.35, 0.12, 0.16)
		var mi := MeshInstance3D.new()
		mi.material_override = mat
		mi.position = Vector3((float(i) - float(n - 1) * 0.5) * SPACING, 0.0, 0.0)
		add_child(mi)
		_meshes.append(mi)

	_build_bar(n)

func _process(dt: float) -> void:
	if _world == null or not _world.alive():
		return
	# Sway the bar the flags hang from slowly; the free fabric follows.
	_bar_t += dt
	var bx := sin(_bar_t * BAR_RATE) * BAR_SWAY
	for i in range(_world.count()):
		_world.bar(i, bx, 0.0, 0.0)
	if _bar != null:
		_bar.position.x = bx
	_world.substeps = 4
	_world.step()
	for i in range(_meshes.size()):
		_update_island(i)
	_frames += 1
	if _capturing and _frames >= 300:
		get_tree().quit()

func _build_bar(n: int) -> void:
	var span: float = float(n) * SPACING + 0.6
	var box := BoxMesh.new()
	box.size = Vector3(span, 0.05, 0.05)
	_bar = MeshInstance3D.new()
	_bar.mesh = box
	_bar.position = Vector3(0.0, BAR_Y, BAR_Z)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.72, 0.74, 0.8)
	m.metallic = 0.6
	m.roughness = 0.4
	_bar.material_override = m
	add_child(_bar)

func _compute_boundary(faces: PackedInt32Array) -> PackedInt32Array:
	var seen := {}
	for k in range(0, faces.size(), 3):
		for e in range(3):
			var a: int = faces[k + e]
			var b: int = faces[k + (e + 1) % 3]
			var key := (mini(a, b) << 16) | maxi(a, b)
			seen[key] = seen.get(key, 0) + 1
	var out := PackedInt32Array()
	for key in seen:
		if seen[key] == 1:
			out.append(key >> 16)
			out.append(key & 0xFFFF)
	return out

func _update_island(i: int) -> void:
	var v: PackedFloat64Array = _world.verts(i)
	var nv := int(v.size() / 3.0)
	if nv == 0 or _faces.is_empty():
		return
	var pts := PackedVector3Array()
	pts.resize(nv)
	for k in range(nv):
		var p := Vector3(v[k * 3], v[k * 3 + 1], v[k * 3 + 2])
		if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z)):
			_world.reset(i)
			return
		pts[k] = p
	var nrm := PackedVector3Array()
	nrm.resize(nv)
	for k in range(0, _faces.size(), 3):
		var a := _faces[k]
		var b := _faces[k + 1]
		var c := _faces[k + 2]
		var fn := (pts[b] - pts[a]).cross(pts[c] - pts[a])
		nrm[a] = nrm[a] + fn
		nrm[b] = nrm[b] + fn
		nrm[c] = nrm[c] + fn
	var back := PackedVector3Array()
	back.resize(nv)
	var thk := 0.006
	for k in range(nv):
		var n := nrm[k]
		back[k] = pts[k] - (n.normalized() if n.length_squared() > 1e-12 else Vector3.ZERO) * thk
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in range(0, _faces.size(), 3):
		st.add_vertex(pts[_faces[k]])
		st.add_vertex(pts[_faces[k + 1]])
		st.add_vertex(pts[_faces[k + 2]])
	for k in range(0, _faces.size(), 3):
		st.add_vertex(back[_faces[k + 2]])
		st.add_vertex(back[_faces[k + 1]])
		st.add_vertex(back[_faces[k]])
	for e in range(0, _boundary.size(), 2):
		var a := _boundary[e]
		var b := _boundary[e + 1]
		st.add_vertex(pts[a])
		st.add_vertex(pts[b])
		st.add_vertex(back[b])
		st.add_vertex(pts[a])
		st.add_vertex(back[b])
		st.add_vertex(back[a])
	st.generate_normals()
	_meshes[i].mesh = st.commit()

func _build_scene() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.07, 0.1)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.44, 0.55)
	env.ambient_light_energy = 0.55
	we.environment = env
	add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(-0.8, 0.6, 0.0)
	key.light_color = Color(1.0, 0.93, 0.82)
	key.light_energy = 1.2
	add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation = Vector3(0.3, -2.4, 0.0)
	rim.light_color = Color(0.5, 0.6, 0.9)
	rim.light_energy = 0.9
	add_child(rim)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 4.0
	cam.rotation_degrees = Vector3(-35.264, 45.0, 0.0)
	var pivot := Vector3(0.0, 0.4, 0.35)
	cam.position = pivot + cam.transform.basis.z * 8.0
	add_child(cam)
