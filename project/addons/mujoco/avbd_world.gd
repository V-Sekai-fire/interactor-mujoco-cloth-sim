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
	var program := load(elf_path)
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
