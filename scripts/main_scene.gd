extends Node3D

const ControlOverlay = preload("res://scripts/control_overlay.gd")
const FaceSpeech = preload("res://scripts/face_speech_coordinator.gd")
const InstallationConfigScript = preload("res://scripts/installation_config.gd")

func _ready() -> void:
	if get_parent() == get_tree().root:
		var overlay = ControlOverlay.install(self)
		var config := InstallationConfigScript.new()
		var speech = FaceSpeech.install(self, overlay, config.get_speech_settings())
		var cube := get_node_or_null("SpinningCube")
		if cube != null:
			cube.face_crops_received.connect(speech.add_faces)
