@tool
class_name MujocoWorld
extends Node3D

## A MuJoCo model running in the godot-sandbox RISC-V guest. The physics is

@export_file("*.elf") var elf_path: String = "res://plans/mujoco.elf"
@export_file("*.xml") var model_path: String = ""
@export var substeps: int = 4

var _sb: Object

func _enter_tree() -> void:
	_sb = ClassDB.instantiate("Sandbox")
	if _sb == null:
		push_error("Sandbox class missing; enable the godot_sandbox addon")
		return
	_sb.set("program", load(elf_path))
	_sb.set_memory_max(1024)
	_sb.set_allocations_max(1 << 21)
	_sb.set_unboxed_arguments(true)
	if model_path != "" and not _sb.vmcall("mjc_load_xml", FileAccess.get_file_as_bytes(model_path)):
		push_error("MuJoCo model failed to load: " + model_path)

func alive() -> bool:
	return _sb != null and (int(_sb.vmcall("mjc_nq")) > 0 or int(_sb.vmcall("mjc_nflexvert")) > 0)

func step() -> void:
	if _sb == null:
		return
	for _s in range(substeps):
		_sb.vmcall("mjc_step")

func geoms() -> PackedFloat64Array:
	return _sb.vmcall("mjc_geoms") if _sb else PackedFloat64Array()

func flexverts() -> PackedFloat64Array:
	return _sb.vmcall("mjc_flexverts") if _sb else PackedFloat64Array()

func flexfaces() -> PackedFloat64Array:
	return _sb.vmcall("mjc_flexfaces") if _sb else PackedFloat64Array()

func nu() -> int:
	return int(_sb.vmcall("mjc_nu")) if _sb else 0

func set_ctrl(ctrl: PackedFloat64Array) -> void:
	if _sb:
		_sb.vmcall("mjc_set_ctrl", ctrl)
