extends Node3D

const ControlOverlay = preload("res://scripts/control_overlay.gd")

func _ready() -> void:
	if get_parent() == get_tree().root:
		ControlOverlay.install(self)
