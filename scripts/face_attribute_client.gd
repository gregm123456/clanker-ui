class_name FaceAttributeClient
extends Node

signal faces_received(faces, capture_order)

const MAX_ACTIVE_REQUESTS := 4
const MAX_RESPONSE_BYTES := 20 * 1024 * 1024
const REQUEST_TIMEOUT_SEC := 20.0
const JPEG_PREFIX := "data:image/jpeg;base64,"

var service_url := "http://pi5ai2sd:5002/v1/attributes"
var _active_requests := 0
var _encodings: Array = []

func submit_image(image: Image, capture_order: int) -> Error:
	if image == null or image.is_empty():
		push_warning("[face] No usable camera image")
		return ERR_INVALID_DATA
	if _encodings.size() + _active_requests >= MAX_ACTIVE_REQUESTS:
		push_warning("[face] Skipping cycle: face request capacity exhausted")
		return ERR_BUSY
	var thread := Thread.new()
	var error := thread.start(_encode_image.bind(image.duplicate()))
	if error != OK:
		push_warning("[face] Could not start frame encoding (error=%s)" % error)
		return error
	_encodings.append({"thread": thread, "order": capture_order})
	return OK

func _process(_delta: float) -> void:
	for index in range(_encodings.size() - 1, -1, -1):
		var job: Dictionary = _encodings[index]
		var thread: Thread = job["thread"]
		if thread.is_alive():
			continue
		var jpeg: PackedByteArray = thread.wait_to_finish()
		_encodings.remove_at(index)
		submit(jpeg, int(job["order"]))

func _exit_tree() -> void:
	for job: Dictionary in _encodings:
		var thread: Thread = job["thread"]
		thread.wait_to_finish()
	_encodings.clear()

static func _encode_image(image: Image) -> PackedByteArray:
	return image.save_jpg_to_buffer(0.85)

func submit(jpeg: PackedByteArray, capture_order: int) -> Error:
	if jpeg.is_empty():
		push_warning("[face] Cannot submit an empty camera frame")
		return ERR_INVALID_DATA
	if _active_requests + _encodings.size() >= MAX_ACTIVE_REQUESTS:
		push_warning("[face] Skipping cycle: face request capacity exhausted")
		return ERR_BUSY
	var request := HTTPRequest.new()
	request.use_threads = true
	request.timeout = REQUEST_TIMEOUT_SEC
	request.body_size_limit = MAX_RESPONSE_BYTES
	add_child(request)
	request.request_completed.connect(_on_request_completed.bind(request, capture_order))
	var body := JSON.stringify({"image": JPEG_PREFIX + Marshalls.raw_to_base64(jpeg)})
	var error := request.request(service_url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
	if error != OK:
		push_warning("[face] Could not start face request (error=%s)" % error)
		request.queue_free()
		return error
	_active_requests += 1
	return OK

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest, capture_order: int) -> void:
	_active_requests -= 1
	request.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		push_warning("[face] Face request failed (result=%s, HTTP=%s)" % [result, response_code])
		return
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK or typeof(json.data) != TYPE_DICTIONARY:
		push_warning("[face] Invalid face service response")
		return
	var response: Dictionary = json.data
	if typeof(response.get("faces")) != TYPE_ARRAY:
		push_warning("[face] Face service response has no faces array")
		return
	var faces := parse_faces(response["faces"])
	faces_received.emit(faces, capture_order)

static func parse_faces(raw_faces: Array) -> Array:
	var faces: Array = []
	for raw_face in raw_faces:
		if typeof(raw_face) != TYPE_DICTIONARY:
			push_warning("[face] Invalid face entry")
			continue
		var crop: Variant = raw_face.get("crop")
		if typeof(crop) != TYPE_STRING or not String(crop).begins_with(JPEG_PREFIX):
			push_warning("[face] Face crop is not a JPEG data URL")
			continue
		var encoded := String(crop).trim_prefix(JPEG_PREFIX)
		var bytes := Marshalls.base64_to_raw(encoded)
		if bytes.size() < 3 or bytes[0] != 0xff or bytes[1] != 0xd8 or bytes[2] != 0xff:
			push_warning("[face] Invalid JPEG face crop")
			continue
		var image := Image.new()
		if image.load_jpg_from_buffer(bytes) != OK or image.is_empty():
			push_warning("[face] Could not decode face crop")
			continue
		faces.append({"image": image, "label": gender_label(raw_face.get("gender_scores"))})
	return faces

static func gender_label(scores: Variant) -> String:
	if typeof(scores) != TYPE_DICTIONARY:
		return "?"
	var male: Variant = scores.get("male")
	var female: Variant = scores.get("female")
	var male_match := _score_over_threshold(male)
	var female_match := _score_over_threshold(female)
	if male_match and not female_match:
		return "M"
	if female_match and not male_match:
		return "F"
	return "?"

static func _score_over_threshold(score: Variant) -> bool:
	return typeof(score) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(score)) \
		and float(score) > 0.70 and float(score) <= 1.0
