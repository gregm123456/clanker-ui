extends Node

signal description_ready(text: String, token: int)

const Categories = preload("res://config/face_categories.gd")
const MAX_RESPONSE_BYTES := 2 * 1024 * 1024
const TIMEOUT_SEC := 30.0

var service_url := "http://m5image:5000"
var flat_interrogation_enabled := false
var categories: Dictionary = Categories.CATEGORIES.duplicate(true)
var _request: HTTPRequest
var _generation := 0
var _token := 0
var _image_base64 := ""
var _structured := ""

func describe(image: Image, token: int) -> void:
	cancel()
	_token = token
	if image == null or image.is_empty():
		push_warning("[speech] Cannot describe an invalid face image")
		description_ready.emit("", token)
		return
	var png := image.save_png_to_buffer()
	if png.is_empty():
		push_warning("[speech] Could not encode face as PNG")
		description_ready.emit("", token)
		return
	_image_base64 = Marshalls.raw_to_base64(png)
	_structured = ""
	if _categories_valid():
		_start_http("structured")
	else:
		push_warning("[speech] Invalid category configuration; skipping structured interrogation")
		if flat_interrogation_enabled:
			_start_http("flat")
		else:
			_finish_description("")

func cancel() -> void:
	_generation += 1
	if is_instance_valid(_request):
		_request.cancel_request()
		_request.queue_free()
		_request = null
	_image_base64 = ""
	_structured = ""

func _exit_tree() -> void:
	cancel()

func _categories_valid() -> bool:
	if categories.is_empty():
		return false
	for name in categories:
		if typeof(name) != TYPE_STRING or String(name).strip_edges().is_empty():
			return false
		var values: Variant = categories[name]
		if typeof(values) != TYPE_ARRAY or values.is_empty():
			return false
		for value in values:
			if typeof(value) != TYPE_STRING or String(value).strip_edges().is_empty():
				return false
	return true

func _start_http(stage: String) -> void:
	var path := "/sdapi/v1/interrogate/structured" if stage == "structured" else "/sdapi/v1/interrogate"
	var payload := {"image": _image_base64}
	if stage == "structured":
		payload["categories"] = categories
	var request := HTTPRequest.new()
	request.use_threads = true
	request.timeout = TIMEOUT_SEC
	request.body_size_limit = MAX_RESPONSE_BYTES
	add_child(request)
	_request = request
	request.request_completed.connect(_on_http_completed.bind(request, stage, _generation))
	var error := request.request(service_url.trim_suffix("/") + path, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		push_warning("[speech] Could not start %s interrogation (error=%s)" % [stage, error])
		_request = null
		request.queue_free()
		_complete_step(stage, {})

func _on_http_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest, stage: String, generation: int) -> void:
	if generation != _generation:
		return
	_request = null
	request.queue_free()
	var response := {}
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		push_warning("[speech] %s interrogation failed (result=%s, HTTP=%s)" % [stage, result, code])
	else:
		var json := JSON.new()
		if json.parse(body.get_string_from_utf8()) != OK or typeof(json.data) != TYPE_DICTIONARY:
			push_warning("[speech] Invalid %s interrogation response" % stage)
		else:
			response = json.data
	_complete_step(stage, response)

func _complete_step(stage: String, response: Dictionary) -> void:
	if stage == "structured":
		_structured = _structured_text(response)
		if flat_interrogation_enabled:
			_start_http("flat")
		else:
			_finish_description(_structured)
		return
	var caption: Variant = response.get("caption")
	var flat := ""
	if typeof(caption) == TYPE_STRING:
		flat = String(caption).strip_edges()
	if flat.is_empty():
		push_warning("[speech] Flat interrogation returned no caption")
	var parts: Array[String] = []
	if not _structured.is_empty():
		parts.append(_structured)
	if not flat.is_empty():
		parts.append(flat)
	_finish_description(". ".join(parts))

func _finish_description(text: String) -> void:
	var token := _token
	_image_base64 = ""
	_structured = ""
	description_ready.emit(text, token)

func _structured_text(response: Dictionary) -> String:
	var results: Variant = response.get("results")
	if typeof(results) != TYPE_DICTIONARY:
		push_warning("[speech] Structured interrogation returned no results")
		return ""
	var parts: Array[String] = []
	for category in categories:
		var result: Variant = results.get(category)
		if typeof(result) != TYPE_DICTIONARY:
			push_warning("[speech] Structured interrogation omitted category %s" % category)
			continue
		var winner: Variant = result.get("winner")
		if typeof(winner) != TYPE_STRING or not categories[category].has(winner):
			push_warning("[speech] Structured interrogation returned invalid winner for %s" % category)
			continue
		parts.append(String(winner))
	return ", ".join(parts)
