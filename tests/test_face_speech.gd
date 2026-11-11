extends SceneTree

const Description = preload("res://scripts/face_description_client.gd")
const Speech = preload("res://scripts/face_speech_coordinator.gd")
const Controls = preload("res://scripts/control_overlay.gd")

class DescriptionStub extends Node:
	signal description_ready(text: String, token: int)
	var calls: Array = []
	var cancellations := 0

	func describe(image: Image, token: int) -> void:
		calls.append([image, token])

	func cancel() -> void:
		cancellations += 1

class SpeechStub extends "res://scripts/face_speech_coordinator.gd":
	var texts: Array[String] = []

	func _start_tts(text: String, _token: int) -> void:
		texts.append(text)

class InterrogationStub extends "res://scripts/face_description_client.gd":
	var stages: Array[String] = []

	func _start_http(stage: String) -> void:
		stages.append(stage)

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		failures += 1

func _image(color: Color) -> Image:
	var image := Image.create(2, 2, false, Image.FORMAT_RGB8)
	image.fill(color)
	return image

func _run() -> void:
	await _test_fifo()
	_test_descriptions()
	_test_install_settings()
	await _test_wav()
	await create_timer(0.25).timeout
	if failures == 0:
		print("Face speech tests passed")
	quit(1 if failures else 0)

func _test_fifo() -> void:
	var speech := SpeechStub.new()
	var descriptions := DescriptionStub.new()
	speech._description_client = descriptions
	speech.max_jobs = 3
	root.add_child(speech)
	var red := _image(Color.RED)
	var green := _image(Color.GREEN)
	var blue := _image(Color.BLUE)
	var yellow := _image(Color.YELLOW)
	var faces := [{"image": red}, {"image": green}, {"image": blue}, {"image": yellow}]
	speech.add_faces(faces, 1)
	_check(descriptions.calls.is_empty(), "Speech must not classify while off")
	speech.set_enabled(true)
	speech.add_faces(faces, 2)
	_check(descriptions.calls.size() == 1 and descriptions.calls[0][0] == red, "First face was not admitted")
	_check(speech._queue.size() == 2 and speech._saturated, "Configured capacity was not enforced")
	var token: int = descriptions.calls[0][1]
	descriptions.description_ready.emit("first", token)
	_check(speech.texts == ["first"], "Description was not sent to TTS")
	speech.add_faces([{"image": yellow}], 3)
	_check(speech._queue.size() == 2, "Saturated queue accepted a face")
	speech._on_playback_finished()
	await process_frame
	_check(descriptions.calls.size() == 2 and descriptions.calls[1][0] == green, "FIFO second face missing")
	speech.add_faces([{"image": yellow}], 4)
	_check(speech._queue.size() == 1, "Queue resumed before fully draining")
	descriptions.description_ready.emit("second", token)
	speech._on_playback_finished()
	await process_frame
	_check(descriptions.calls.size() == 3 and descriptions.calls[2][0] == blue, "FIFO third face missing")
	descriptions.description_ready.emit("third", token)
	speech._on_playback_finished()
	await process_frame
	_check(not speech._saturated and not speech._busy, "Queue did not recover after draining")
	speech.add_faces([{"image": yellow}], 5)
	_check(descriptions.calls.size() == 4 and descriptions.calls[3][0] == yellow, "New face after drain was not admitted")
	speech.set_enabled(false)
	_check(not speech._busy and speech._queue.is_empty() and not speech._player.playing, "Disable did not interrupt and clear")
	speech.set_enabled(true)
	speech.add_faces([{"image": red}], 6)
	var new_token: int = descriptions.calls.back()[1]
	descriptions.description_ready.emit("stale", token)
	_check(speech.texts == ["first", "second", "third"], "Late description crossed toggle generation")
	descriptions.description_ready.emit("fresh", new_token)
	_check(speech.texts.back() == "fresh", "New generation did not continue")
	speech.queue_free()

func _test_descriptions() -> void:
	var client := InterrogationStub.new()
	client.categories = {"gender": ["woman", "nonbinary"], "age": ["adult", "unknown"]}
	root.add_child(client)
	var received: Array = []
	client.description_ready.connect(func(text, token): received.append([text, token]))
	client.describe(_image(Color.RED), 42)
	_check(client.stages == ["structured"], "Structured request must run first")
	var png := Marshalls.base64_to_raw(client._image_base64)
	_check(png.size() > 8 and png[0] == 137 and png[1] == 80, "Interrogation image was not PNG")
	client._complete_step("structured", {"results": {"gender": {"winner": "nonbinary"}, "age": {"winner": "adult"}}})
	_check(client.stages == ["structured"], "Flat interrogation must be disabled by default")
	_check(received == [["nonbinary, adult", 42]], "Structured output must contain only values in category order")
	client.describe(_image(Color.BLUE), 43)
	client._complete_step("structured", {})
	_check(received.back() == ["", 43] and client.stages == ["structured", "structured"], "Failed structured result must not trigger flat interrogation by default")
	client.flat_interrogation_enabled = true
	client.stages.clear()
	client.describe(_image(Color.RED), 44)
	client._complete_step("structured", {"results": {"gender": {"winner": "nonbinary"}, "age": {"winner": "adult"}}})
	_check(client.stages == ["structured", "flat"], "Flat request did not follow structured")
	client._complete_step("flat", {"caption": "portrait, red"})
	_check(received.back() == ["nonbinary, adult. portrait, red", 44], "Optional combined text or order is wrong")
	client.describe(_image(Color.BLUE), 45)
	client._complete_step("structured", {})
	client._complete_step("flat", {"caption": "portrait"})
	_check(received.back() == ["portrait", 45], "Flat-only partial result was lost")
	client.describe(_image(Color.BLUE), 46)
	client._complete_step("structured", {"results": {"gender": {"winner": "woman"}, "age": {"winner": "unlisted"}}})
	client._complete_step("flat", {})
	_check(received.back() == ["woman", 46], "Structured-only partial result was lost")
	client.describe(_image(Color.BLUE), 47)
	client._complete_step("structured", {})
	client._complete_step("flat", {})
	_check(received.back() == ["", 47], "Empty results must not produce speech")
	client.categories = {}
	client.stages.clear()
	client.describe(_image(Color.BLUE), 48)
	_check(client.stages == ["flat"], "Invalid categories must not prevent flat interrogation")
	client._complete_step("flat", {"caption": "portrait"})
	_check(received.back() == ["portrait", 48], "Flat result was lost with invalid categories")
	client.flat_interrogation_enabled = false
	client.stages.clear()
	client.describe(_image(Color.BLUE), 49)
	_check(client.stages.is_empty() and received.back() == ["", 49], "Invalid categories must not start flat interrogation when disabled")
	client.free()

func _wav() -> PackedByteArray:
	var buffer := StreamPeerBuffer.new()
	buffer.put_data("RIFF".to_ascii_buffer())
	buffer.put_u32(38)
	buffer.put_data("WAVEfmt ".to_ascii_buffer())
	buffer.put_u32(16)
	buffer.put_u16(1)
	buffer.put_u16(1)
	buffer.put_u32(22050)
	buffer.put_u32(44100)
	buffer.put_u16(2)
	buffer.put_u16(16)
	buffer.put_data("data".to_ascii_buffer())
	buffer.put_u32(2)
	buffer.put_u16(0)
	return buffer.data_array

func _test_install_settings() -> void:
	var overlay := Controls.new()
	root.add_child(overlay)
	var speech = Speech.install(root, overlay, {
		"interrogation_url": "http://example.test",
		"tts_url": "http://example.test",
		"max_jobs": 5,
		"flat_interrogation_enabled": true,
	})
	_check(speech._description_client.flat_interrogation_enabled, "Configured flat interrogation was not applied")
	speech.free()
	overlay.free()

func _test_wav() -> void:
	var speech := Speech.new()
	speech._description_client = DescriptionStub.new()
	root.add_child(speech)
	speech.set_enabled(true)
	speech._busy = true
	var request := HTTPRequest.new()
	root.add_child(request)
	speech._on_tts_completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), _wav(), request, speech._generation)
	_check(speech._player.stream is AudioStreamWAV, "Valid WAV was not loaded into the player")
	speech.set_enabled(false)
	_check(speech._player.stream == null and not speech._player.playing, "Disable did not stop active WAV")
	speech.set_enabled(true)
	speech._busy = true
	var stale_token: int = speech._generation - 1
	request = HTTPRequest.new()
	speech._on_tts_completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), _wav(), request, stale_token)
	_check(speech._busy and speech._player.stream == null, "Stale TTS response played after re-enable")
	request.free()
	request = HTTPRequest.new()
	root.add_child(request)
	speech._on_tts_completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), "bad".to_utf8_buffer(), request, speech._generation)
	_check(not speech._busy, "Invalid WAV did not release the job")
	speech._busy = true
	request = HTTPRequest.new()
	root.add_child(request)
	speech._on_tts_completed(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray(), request, speech._generation)
	_check(not speech._busy, "Failed Piper request did not release the job")
	speech.queue_free()
	await process_frame
