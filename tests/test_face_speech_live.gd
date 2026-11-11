extends SceneTree

const Speech = preload("res://scripts/face_speech_coordinator.gd")

class MonitoredDescription extends "res://scripts/face_description_client.gd":
	var stages: Array[String] = []

	func _start_http(stage: String) -> void:
		stages.append(stage)
		super._start_http(stage)

var _description := ""

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var speech := Speech.new()
	speech._description_client = MonitoredDescription.new()
	root.add_child(speech)
	speech._description_client.description_ready.connect(_on_description)
	speech.set_enabled(true)
	var image := Image.create(32, 32, false, Image.FORMAT_RGB8)
	image.fill(Color.CORNFLOWER_BLUE)
	speech.add_faces([{"image": image}], 1)
	var deadline := Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < deadline:
		if speech._player.stream != null:
			var values := _description.split(", ")
			var categories: Dictionary = speech._description_client.categories
			var valid: bool = speech._description_client.stages == ["structured"] and values.size() == categories.size()
			if valid:
				var index := 0
				for category in categories:
					if not categories[category].has(values[index]):
						valid = false
					index += 1
			if not valid:
				push_error("Live interrogation did not return only structured category values")
				speech.queue_free()
				quit(1)
				return
			print("Live interrogation and Piper WAV playback setup passed")
			speech.set_enabled(false)
			speech.queue_free()
			await create_timer(0.25).timeout
			quit(0)
			return
		if not speech._busy:
			break
		await create_timer(0.1).timeout
	push_error("Live face speech did not produce playable WAV audio")
	speech.set_enabled(false)
	speech.queue_free()
	await create_timer(0.25).timeout
	quit(1)

func _on_description(text: String, _token: int) -> void:
	_description = text
