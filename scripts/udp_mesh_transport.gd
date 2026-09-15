class_name UdpMeshTransport
extends Node

## Versioned JSON-over-UDP contract shared by mesh clients.
## Every datagram is one UTF-8 JSON object with this shape:
## {"version": 1, "type": "transform|calibration|spawn|despawn|heartbeat",
##  "sender_peer_id": "peer-id", "payload": { ... }}
## `sender_peer_id` identifies the sending process and is never a scene object id.
## `payload` is a JSON object. Its contents are:
## - transform: TransformSyncSchema dictionary, including object_id and transform data.
## - calibration: MeshCalibrationModel.to_dictionary() result.
## - spawn: descriptor dictionary; object_id and owner_peer_id are required.
## - despawn: {"object_id": "shared-object-id"}.
## - heartbeat: {} (or future optional presence metadata).
## Receivers must ignore unknown versions/types, packets without a string sender id,
## and packets whose payload is not an object. A malformed datagram must not terminate
## the receiver. This contract contains no SpinningCube-specific fields.

const PROTOCOL_VERSION := 1
const PeerAddressBookScript = preload("res://scripts/peer_address_book.gd")
const MESSAGE_TYPES := ["transform", "calibration", "spawn", "despawn", "heartbeat"]

signal message_received(message: Dictionary)

var _socket := PacketPeerUDP.new()
var _address_book
var _local_peer_id: String = ""
var _mode: String = "broadcast"
var _udp_port: int = 9000
var _broadcast_address: String = "255.255.255.255"
var _bound: bool = false

func configure(network_settings: Dictionary, address_book, local_peer_id: String) -> Error:
	_address_book = address_book
	_local_peer_id = local_peer_id
	_mode = String(network_settings.get("mode", "broadcast")).to_lower()
	_udp_port = int(network_settings.get("udp_port", 9000))
	_broadcast_address = String(network_settings.get("broadcast_address", "255.255.255.255"))
	if _udp_port <= 0 or _udp_port > 65535:
		print("[udp_mesh_transport] Invalid UDP port: ", _udp_port)
		return ERR_INVALID_PARAMETER

	var error: Error = _socket.bind(_udp_port, "*")
	if error != OK:
		print("[udp_mesh_transport] Unable to bind UDP port ", _udp_port, " (error=", error, ")")
		return error
	_socket.set_broadcast_enabled(true)
	_bound = true
	print("[udp_mesh_transport] Listening on UDP port ", _udp_port, " mode=", _mode)
	return OK

func _exit_tree() -> void:
	close()

func _process(_delta: float) -> void:
	if not _bound:
		return
	while _socket.get_available_packet_count() > 0:
		var packet := _socket.get_packet()
		var parsed: Variant = JSON.parse_string(packet.get_string_from_utf8())
		if typeof(parsed) != TYPE_DICTIONARY:
			print("[udp_mesh_transport] Dropped non-dictionary packet")
			continue
		var message: Dictionary = parsed
		if not _is_valid_message(message):
			continue
		message_received.emit(message)

func send(message_type: String, payload: Dictionary) -> Error:
	if not _bound:
		return ERR_UNCONFIGURED
	if not MESSAGE_TYPES.has(message_type) or _local_peer_id.is_empty():
		return ERR_INVALID_PARAMETER

	var envelope := {
		"version": PROTOCOL_VERSION,
		"type": message_type,
		"sender_peer_id": _local_peer_id,
		"payload": payload.duplicate(true)
	}
	var packet := JSON.stringify(envelope).to_utf8_buffer()
	var first_error: Error = OK
	if _mode == "broadcast" or _mode == "both":
		var broadcast_error := _send_packet(_broadcast_address, _udp_port, packet)
		if broadcast_error != OK:
			first_error = broadcast_error
	if _mode == "unicast" or _mode == "both":
		if _address_book != null:
			for peer_id in _address_book.get_peer_ids():
				var peer: Dictionary = _address_book.resolve_peer(peer_id)
				if peer.is_empty():
					continue
				var unicast_error := _send_packet(String(peer.get("address", "")), int(peer.get("port", _udp_port)), packet)
				if unicast_error != OK and first_error == OK:
					first_error = unicast_error
	return first_error

func close() -> void:
	if _bound:
		_socket.close()
		_bound = false

func _send_packet(address: String, port: int, packet: PackedByteArray) -> Error:
	if address.is_empty() or port <= 0 or port > 65535:
		return ERR_INVALID_PARAMETER
	var error := _socket.set_dest_address(address, port)
	if error != OK:
		return error
	return _socket.put_packet(packet)

func _is_valid_message(message: Dictionary) -> bool:
	if int(message.get("version", -1)) != PROTOCOL_VERSION:
		print("[udp_mesh_transport] Dropped unsupported protocol version")
		return false
	var message_type := String(message.get("type", ""))
	var sender_peer_id := String(message.get("sender_peer_id", ""))
	if not MESSAGE_TYPES.has(message_type) or sender_peer_id.is_empty():
		print("[udp_mesh_transport] Dropped malformed message envelope")
		return false
	if typeof(message.get("payload", null)) != TYPE_DICTIONARY:
		print("[udp_mesh_transport] Dropped message with invalid payload")
		return false
	return true