@tool
extends EditorPlugin

func _enter_tree() -> void:
	add_custom_type("MujocoWorld", "Node3D", preload("res://addons/mujoco/mujoco_world.gd"), null)

func _exit_tree() -> void:
	remove_custom_type("MujocoWorld")
