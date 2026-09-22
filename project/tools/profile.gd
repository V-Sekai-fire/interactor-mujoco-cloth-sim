extends SceneTree
func _init() -> void:
	var sb = ClassDB.instantiate("Sandbox")
	sb.set("program", load("res://plans/mujoco.elf"))
	sb.set_memory_max(1024); sb.set_allocations_max(1 << 21); sb.set_unboxed_arguments(true)
	sb.vmcall("mjc_load_xml", FileAccess.get_file_as_bytes("res://plans/cloth.xml"))
	var faces := PackedInt32Array()
	var ff: PackedFloat64Array = sb.vmcall("mjc_flexfaces")
	for v in ff: faces.append(int(v))
	var step_us: int = 0
	var mesh_us: int = 0
	var N: int = 60
	for f in range(N):
		var t0: int = Time.get_ticks_usec()
		for _s in range(8): sb.vmcall("mjc_step")
		var t1: int = Time.get_ticks_usec()
		var vv: PackedFloat64Array = sb.vmcall("mjc_flexverts")
		var nv: int = int(vv.size() / 3.0)
		var pts := PackedVector3Array(); pts.resize(nv)
		for i in range(nv): pts[i] = Vector3(vv[i*3], vv[i*3+1], vv[i*3+2])
		var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in range(0, faces.size(), 3):
			st.add_vertex(pts[faces[i]]); st.add_vertex(pts[faces[i+1]]); st.add_vertex(pts[faces[i+2]])
		st.generate_normals(); var m: ArrayMesh = st.commit()
		var t2: int = Time.get_ticks_usec()
		step_us += t1 - t0
		mesh_us += t2 - t1
	print("nflexvert=%d faces_tris=%d" % [int(sb.vmcall("mjc_flexverts").size())/3, faces.size()/3])
	print("STEP avg %.2f ms/frame (8 substeps, interpreted guest)" % (step_us/float(N)/1000.0))
	print("MESH avg %.2f ms/frame (SurfaceTool rebuild+commit)" % (mesh_us/float(N)/1000.0))
	quit()
