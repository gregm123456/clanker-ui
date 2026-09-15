class_name WebcamSnapshotServer
extends Node

## TCP snapshot contract shared by mesh clients.
## The client sends the UTF-8 bytes `GET /snapshot\n` and then waits for the
## response. The response starts with one little-endian uint32 byte length,
## followed by exactly that many JPEG bytes. The server closes the connection
## after the complete response. The length must be in (0, 20 MiB]. There is no
## HTTP status line or chunking, and the image is a still captured locally at
## request time. Invalid requests, unavailable frames, and oversized images are
## rejected by closing the connection; callers should treat that as a failed
## snapshot and retain their existing proxy appearance.

const MAX_REQUEST_BYTES: int = 256
const JPEG_QUALITY: float = 0.85
const MAX_CONNECTION_AGE_SEC: float = 5.0

var _server := TCPServer.new()
var _camera_source
var _port: int = 0
var _connections: Array = []
var _listening: bool = false

func configure(camera_source, port: int) -> Error:
	_camera_source = camera_source
	_port = port
	if _port <= 0 or _port > 65535:
		return ERR_INVALID_PARAMETER
	var error: Error = _server.listen(_port, "0.0.0.0")
	if error != OK:
		print("[webcam_snapshot_server] Unable to listen on TCP port ", _port, " (error=", error, ")")
		return error
	_listening = true
	print("[webcam_snapshot_server] Listening on TCP port ", _port)
	return OK

func _exit_tree() -> void:
	close()

func _process(delta: float) -> void:
	if not _listening:
		return
	while _server.is_connection_available():
		var connection := _server.take_connection()
		if connection != null:
			_connections.append({"peer": connection, "request": PackedByteArray(), "age": 0.0})

	for index in range(_connections.size() - 1, -1, -1):
		var connection: Dictionary = _connections[index]
		connection["age"] = float(connection.get("age", 0.0)) + delta
		var peer: StreamPeerTCP = connection.get("peer")
		if peer == null or float(connection.get("age", 0.0)) > MAX_CONNECTION_AGE_SEC:
			_close_connection(index)
			continue
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			if peer.get_status() == StreamPeerTCP.STATUS_ERROR:
				_close_connection(index)
			else:
				_connections[index] = connection
			continue
		var available := peer.get_available_bytes()
		if available <= 0:
			_connections[index] = connection
			continue
		var result: Array = peer.get_partial_data(mini(available, MAX_REQUEST_BYTES))
		if result.size() < 2 or result[0] != OK:
			_close_connection(index)
			continue
		var request: PackedByteArray = connection.get("request", PackedByteArray())
		request.append_array(result[1])
		connection["request"] = request
		_connections[index] = connection
		if request.size() >= MAX_REQUEST_BYTES or request.has(10):
			_serve_request(index)

func close() -> void:
	for index in range(_connections.size() - 1, -1, -1):
		_close_connection(index)
	if _listening:
		_server.stop()
		_listening = false

func _serve_request(index: int) -> void:
	var connection: Dictionary = _connections[index]
	var peer: StreamPeerTCP = connection.get("peer")
	if peer == null:
		_close_connection(index)
		return
	var request: String = String(PackedByteArray(connection.get("request", PackedByteArray())).get_string_from_utf8()).strip_edges()
	if request != "GET /snapshot":
		_close_connection(index)
		return
	if _camera_source == null:
		_close_connection(index)
		return
	var image: Image = _camera_source.get_current_frame_image()
	if image == null or image.is_empty():
		print("[webcam_snapshot_server] No camera frame available for snapshot request")
		_close_connection(index)
		return
	var jpeg: PackedByteArray = image.save_jpg_to_buffer(JPEG_QUALITY)
	if jpeg.is_empty() or jpeg.size() > 20 * 1024 * 1024:
		print("[webcam_snapshot_server] Failed to encode a usable JPEG snapshot")
		_close_connection(index)
		return
	var response := PackedByteArray()
	response.resize(4)
	response.encode_u32(0, jpeg.size())
	response.append_array(jpeg)
	peer.put_data(response)
	_close_connection(index)

func _close_connection(index: int) -> void:
	if index < 0 or index >= _connections.size():
		return
	var connection: Dictionary = _connections[index]
	var peer: StreamPeerTCP = connection.get("peer")
	if peer != null:
		peer.disconnect_from_host()
	_connections.remove_at(index)
