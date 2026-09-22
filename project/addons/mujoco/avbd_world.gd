@tool
class_name AvbdWorld
extends Node3D

@export_file("*.elf") var elf_path: String = "res://plans/avbd.elf"
@export var islands: int = 8
@export var nx: int = 10
@export var ny: int = 14
@export var substeps: int = 4
@export var iters: int = 10

var _sandboxes: Array = []

func _enter_tree() -> void:
	var program := ResourceLoader.load(elf_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	for i in range(islands):
		var sb: Object = ClassDB.instantiate("Sandbox")
		if sb == null:
			push_error("Sandbox class missing; enable the godot_sandbox addon")
			return
		sb.set("program", program)
		sb.set_memory_max(512)
		sb.set_allocations_max(1 << 21)
		sb.set_unboxed_arguments(true)
		if not sb.vmcall("avbd_load", nx, ny):
			push_error("AVBD island %d failed to load" % i)
			return
		sb.vmcall("avbd_set_iters", iters)
		_sandboxes.append(sb)

func count() -> int:
	return _sandboxes.size()

func alive() -> bool:
	return _sandboxes.size() > 0 and int(_sandboxes[0].vmcall("avbd_nverts")) > 0

@export var parallel: bool = false

func _step_island(i: int) -> void:
	_sandboxes[i].vmcall("avbd_step", substeps)

func step() -> void:
	if _sandboxes.is_empty():
		return
	if parallel:
		var task := WorkerThreadPool.add_group_task(Callable(self, "_step_island"), _sandboxes.size(), -1, false, "avbd_step")
		WorkerThreadPool.wait_for_group_task_completion(task)
	else:
		for i in range(_sandboxes.size()):
			_step_island(i)

func verts(i: int) -> PackedFloat64Array:
	return _sandboxes[i].vmcall("avbd_verts") if i < _sandboxes.size() else PackedFloat64Array()

func faces(i: int) -> PackedFloat64Array:
	return _sandboxes[i].vmcall("avbd_faces") if i < _sandboxes.size() else PackedFloat64Array()

func digest(i: int) -> int:
	return int(_sandboxes[i].vmcall("avbd_hash")) if i < _sandboxes.size() else 0

func grab(i: int, v: int) -> void:
	if i < _sandboxes.size():
		_sandboxes[i].vmcall("avbd_grab", v)

func drag(i: int, x: float, y: float, z: float) -> void:
	if i < _sandboxes.size():
		_sandboxes[i].vmcall("avbd_drag", x, y, z)

func release(i: int) -> void:
	if i < _sandboxes.size():
		_sandboxes[i].vmcall("avbd_release")

func bar(i: int, x: float, y: float, z: float) -> void:
	if i < _sandboxes.size():
		_sandboxes[i].vmcall("avbd_bar", x, y, z)

func reset(i: int) -> void:
	if i < _sandboxes.size():
		_sandboxes[i].vmcall("avbd_load", nx, ny)
		_sandboxes[i].vmcall("avbd_set_iters", iters)

func snapshot(i: int) -> void:
	if i < _sandboxes.size():
		_sandboxes[i].vmcall("avbd_snapshot")

func restore(i: int) -> void:
	if i < _sandboxes.size():
		_sandboxes[i].vmcall("avbd_restore")

func finite(i: int) -> bool:
	return bool(_sandboxes[i].vmcall("avbd_finite")) if i < _sandboxes.size() else true
