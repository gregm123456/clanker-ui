class_name WebcamSnapshotClient
extends Node

signal snapshot_received(object_id, owner_peer_id, texture)
signal snapshot_failed(object_id, owner_peer_id, reason)

const MAX_JPEG_BYTES: int = 20 * 1024 * 1024
const REQUEST_TIMEOUT_SEC: float = 5.0

var _address_book
var _snapshot_port: int = 9010
var _requests: Dictionary = {}

func configure(address_book, snapshot_port: int) -> Error:
	_address_book = address_book
	_snapshot_port = snapshot_port
	if _snapshot_port <= 0 or _snapshot_port > 65535:
		return ERR_INVALID_PARAMETER
	return OK

func request_snapshot(object_id: String, owner_peer_id: String) -> Error:
	if object_id.is_empty() or owner_peer_id.is_empty():
		return ERR_INVALID_PARAMETER
	if _requests.has(object_id):
		return ERR_BUSY
	if _address_book == null:
		return ERR_UNCONFIGURED
	var peer_address: Dictionary = _address_book.resolve_peer(owner_peer_id)
	if peer_address.is_empty():
		return ERR_CANT_RESOLVE
	var stream := StreamPeerTCP.new()
	var address := String(peer_address.get("address", ""))
	var error: Error = stream.connect_to_host(address, _snapshot_port)
	if error != OK:
		return _fail_immediately(object_id, owner_peer_id, "connect_to_host failed: %s" % error)
	_requests[object_id] = {
		"object_id": object_id,
		"owner_peer_id": owner_peer_id,
		"stream": stream,
		"state": "connecting",
		"header": PackedByteArray(),
		"body": PackedByteArray(),
		"expected_bytes": -1,
		"age": 0.0
	}
	return OK

func _process(delta: float) -> void:
	for object_id_variant in _requests.keys().duplicate():
		var object_id := String(object_id_variant)
		var request: Dictionary = _requests.get(object_id, {})
		var stream: StreamPeerTCP = request.get("stream")
		if stream == null:
			_fail_request(object_id, request, "missing TCP stream")
			continue
		request["age"] = float(request.get("age", 0.0)) + delta
		if float(request.get("age", 0.0)) > REQUEST_TIMEOUT_SEC:
			_fail_request(object_id, request, "snapshot request timed out")
			continue
		stream.poll()
		var status := stream.get_status()
		if status == StreamPeerTCP.STATUS_ERROR or status == StreamPeerTCP.STATUS_NONE:
			_fail_request(object_id, request, "TCP connection failed")
			continue
		if String(request.get("state", "")) == "connecting":
			if status == StreamPeerTCP.STATUS_CONNECTED:
				var send_error: Error = stream.put_data("GET /snapshot\n".to_utf8_buffer())
				if send_error != OK:
					_fail_request(object_id, request, "snapshot request send failed")
					continue
				request["state"] = "header"
			_requests[object_id] = request
			continue
		if status != StreamPeerTCP.STATUS_CONNECTED:
			_fail_request(object_id, request, "TCP connection closed before snapshot")
			continue
		var available := stream.get_available_bytes()
		if available <= 0:
			_requests[object_id] = request
			continue
		var result: Array = stream.get_partial_data(available)
		if result.size() < 2 or result[0] != OK:
			_fail_request(object_id, request, "snapshot data read failed")
			continue
		var bytes: PackedByteArray = result[1]
		if String(request.get("state", "")) == "header":
			var header: PackedByteArray = request.get("header", PackedByteArray())
			header.append_array(bytes)
			if header.size() < 4:
				request["header"] = header
				_requests[object_id] = request
				continue
			var expected_bytes := int(header.decode_u32(0))
			if expected_bytes <= 0 or expected_bytes > MAX_JPEG_BYTES:
				_fail_request(object_id, request, "invalid snapshot length")
				continue
			request["expected_bytes"] = expected_bytes
			request["body"] = header.slice(4)
			request["state"] = "body"
		else:
			var incoming_body: PackedByteArray = request.get("body", PackedByteArray())
			incoming_body.append_array(bytes)
			request["body"] = incoming_body
		var body: PackedByteArray = request.get("body", PackedByteArray())
		var expected := int(request.get("expected_bytes", -1))
		if body.size() < expected:
			_requests[object_id] = request
			continue
		_process_body(object_id, request)

func close() -> void:
	for object_id_variant in _requests.keys().duplicate():
		var request: Dictionary = _requests.get(object_id_variant, {})
		var stream: StreamPeerTCP = request.get("stream")
		if stream != null:
			stream.disconnect_from_host()
	_requests.clear()

func _process_body(object_id: String, request: Dictionary) -> void:
	var body: PackedByteArray = request.get("body", PackedByteArray())
	var image := Image.new()
	var image_error: Error = image.load_jpg_from_buffer(body)
	if image_error != OK or image.is_empty():
		_fail_request(object_id, request, "JPEG decode failed")
		return
	var texture := ImageTexture.create_from_image(image)
	var stream: StreamPeerTCP = request.get("stream")
	if stream != null:
		stream.disconnect_from_host()
	_requests.erase(object_id)
	snapshot_received.emit(object_id, String(request.get("owner_peer_id", "")), texture)

func _fail_request(object_id: String, request: Dictionary, reason: String) -> void:
	var stream: StreamPeerTCP = request.get("stream")
	if stream != null:
		stream.disconnect_from_host()
	_requests.erase(object_id)
	snapshot_failed.emit(object_id, String(request.get("owner_peer_id", "")), reason)

func _fail_immediately(object_id: String, owner_peer_id: String, reason: String) -> Error:
	snapshot_failed.emit(object_id, owner_peer_id, reason)
	return ERR_CANT_CONNECT
