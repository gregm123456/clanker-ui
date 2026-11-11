extends Node

const DescriptionClient = preload("res://scripts/face_description_client.gd")
const MAX_AUDIO_BYTES := 20 * 1024 * 1024
const MAX_TEXT_LENGTH := 5000
const TIMEOUT_SEC := 30.0

var tts_url := "http://pi5ai2sd:5003/v1/audio/speech"
var max_jobs := 5
var enabled := false
var _queue: Array[Image] = []
var _busy := false
var _saturated := false
var _generation := 0
var _description_client
var _request: HTTPRequest
var _player: AudioStreamPlayer

static func install(parent: Node, overlay, settings: Dictionary) -> Node:
	var coordinator := preload("res://scripts/face_speech_coordinator.gd").new()
	coordinator.name = "FaceSpeech"
	coordinator.tts_url = String(settings["tts_url"])
	coordinator.max_jobs = int(settings["max_jobs"])
	coordinator._description_client = DescriptionClient.new()
	coordinator._description_client.service_url = String(settings["interrogation_url"])
	coordinator._description_client.flat_interrogation_enabled = bool(settings["flat_interrogation_enabled"])
	overlay.speech_toggled.connect(coordinator.set_enabled)
	parent.add_child(coordinator)
	return coordinator

func _ready() -> void:
	if max_jobs < 1:
		push_warning("[speech] Invalid max_jobs; using 5")
		max_jobs = 5
	if _description_client == null:
		_description_client = DescriptionClient.new()
	add_child(_description_client)
	_description_client.description_ready.connect(_on_description_ready)
	_player = AudioStreamPlayer.new()
	add_child(_player)
	_player.finished.connect(_on_playback_finished)

func set_enabled(value: bool) -> void:
	if enabled == value:
		return
	enabled = value
	_generation += 1
	if not enabled:
		_queue.clear()
		_busy = false
		_saturated = false
		_description_client.cancel()
		if is_instance_valid(_request):
			_request.cancel_request()
			_request.queue_free()
			_request = null
		_player.stop()
		_player.stream = null

func add_faces(faces: Array, _capture_order: int) -> void:
	if not enabled:
		return
	for face in faces:
		if _saturated:
			push_warning("[speech] Skipping face while speech queue drains")
			continue
		if typeof(face) != TYPE_DICTIONARY or not face.get("image") is Image or face["image"].is_empty():
			push_warning("[speech] Skipping invalid face crop")
			continue
		_queue.append(face["image"])
		if _queue.size() + int(_busy) >= max_jobs:
			_saturated = true
		_start_next()

func _start_next() -> void:
	if not enabled or _busy:
		return
	if _queue.is_empty():
		_saturated = false
		return
	_busy = true
	var image: Image = _queue.pop_front()
	_description_client.describe(image, _generation)

func _on_description_ready(text: String, token: int) -> void:
	if not enabled or not _busy or token != _generation:
		return
	text = text.strip_edges()
	if text.is_empty():
		push_warning("[speech] No description available for face")
		_finish_job()
		return
	if text.length() > MAX_TEXT_LENGTH:
		push_warning("[speech] Description exceeds Piper's limit; truncating")
		text = text.left(MAX_TEXT_LENGTH)
	_start_tts(text, token)

func _start_tts(text: String, token: int) -> void:
	var request := HTTPRequest.new()
	request.use_threads = true
	request.timeout = TIMEOUT_SEC
	request.body_size_limit = MAX_AUDIO_BYTES
	add_child(request)
	_request = request
	request.request_completed.connect(_on_tts_completed.bind(request, token))
	var error := request.request(tts_url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify({"input": text}))
	if error != OK:
		push_warning("[speech] Could not start Piper request (error=%s)" % error)
		_request = null
		request.queue_free()
		_finish_job()

func _on_tts_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest, token: int) -> void:
	if token != _generation or not enabled or not _busy:
		return
	_request = null
	request.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		push_warning("[speech] Piper request failed (result=%s, HTTP=%s)" % [result, code])
		_finish_job()
		return
	if body.size() < 12 or body.slice(0, 4).get_string_from_ascii() != "RIFF" or body.slice(8, 12).get_string_from_ascii() != "WAVE":
		push_warning("[speech] Piper returned invalid WAV audio")
		_finish_job()
		return
	var stream := AudioStreamWAV.load_from_buffer(body)
	if stream == null or stream.data.is_empty():
		push_warning("[speech] Piper returned invalid or empty WAV audio")
		_finish_job()
		return
	_player.stream = stream
	_player.play()

func _on_playback_finished() -> void:
	if enabled and _busy:
		_player.stream = null
		_finish_job()

func _finish_job() -> void:
	_busy = false
	call_deferred("_start_next")
