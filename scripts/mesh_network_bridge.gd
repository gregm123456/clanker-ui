class_name MeshNetworkBridge
extends Node

const MeshCalibrationModelScript = preload("res://scripts/mesh_calibration_model.gd")
const PeerAddressBookScript = preload("res://scripts/peer_address_book.gd")
const UdpMeshTransportScript = preload("res://scripts/udp_mesh_transport.gd")

var _mesh_sync_service
var _transport
var _address_book
var _local_peer_id: String = ""
var _heartbeat_interval_sec: float = 2.0
var _peer_timeout_sec: float = 15.0
var _heartbeat_elapsed: float = 0.0
var _last_seen_by_peer: Dictionary = {}
var _applying_remote: bool = false

func configure(mesh_sync_service: MeshSyncService, network_settings: Dictionary, peers: Dictionary, local_peer_id: String) -> Error:
	_mesh_sync_service = mesh_sync_service
	_local_peer_id = local_peer_id
	_heartbeat_interval_sec = maxf(float(network_settings.get("heartbeat_interval_sec", 2.0)), 0.1)
	_peer_timeout_sec = maxf(float(network_settings.get("peer_timeout_sec", 15.0)), _heartbeat_interval_sec)
	_address_book = PeerAddressBookScript.new()
	_address_book.configure(peers, int(network_settings.get("udp_port", 9000)))
	_transport = UdpMeshTransportScript.new()
	add_child(_transport)
	_transport.message_received.connect(_on_message_received)
	var error: Error = _transport.configure(network_settings, _address_book, _local_peer_id)
	if error != OK:
		return error
	_heartbeat_elapsed = _heartbeat_interval_sec
	return OK

func _process(delta: float) -> void:
	if _transport == null or _mesh_sync_service == null:
		return
	_heartbeat_elapsed += delta
	if _heartbeat_elapsed >= _heartbeat_interval_sec:
		_heartbeat_elapsed = 0.0
		_transport.send("heartbeat", {})
	var now := Time.get_ticks_msec() / 1000.0
	for peer_id_variant in _last_seen_by_peer.keys():
		var peer_id := String(peer_id_variant)
		if now - float(_last_seen_by_peer[peer_id]) > _peer_timeout_sec:
			_mesh_sync_service.set_peer_online(peer_id, false)
			_last_seen_by_peer.erase(peer_id)

func shutdown() -> void:
	if _transport != null:
		_transport.close()

func send_calibration(calibration: MeshCalibrationModel) -> void:
	if not _can_send() or calibration == null or _applying_remote:
		return
	_transport.send("calibration", calibration.to_dictionary())

func send_object_spawn(object_id: String, descriptor: Dictionary) -> void:
	if not _can_send() or object_id.is_empty() or _applying_remote:
		return
	var payload := descriptor.duplicate(true)
	payload["object_id"] = object_id
	payload["owner_peer_id"] = String(payload.get("owner_peer_id", _local_peer_id))
	_transport.send("spawn", payload)

func send_object_transform(payload: Dictionary) -> void:
	if not _can_send() or _applying_remote:
		return
	_transport.send("transform", payload)

func send_object_despawn(object_id: String) -> void:
	if not _can_send() or object_id.is_empty() or _applying_remote:
		return
	_transport.send("despawn", {"object_id": object_id})

func _can_send() -> bool:
	return _transport != null and _mesh_sync_service != null

func _on_message_received(message: Dictionary) -> void:
	var sender_peer_id := String(message.get("sender_peer_id", ""))
	if sender_peer_id.is_empty() or sender_peer_id == _local_peer_id:
		return
	var now := Time.get_ticks_msec() / 1000.0
	_last_seen_by_peer[sender_peer_id] = now
	_mesh_sync_service.set_peer_online(sender_peer_id, true)

	var payload: Dictionary = message.get("payload", {})
	_applying_remote = true
	match String(message.get("type", "")):
		"heartbeat":
			pass
		"calibration":
			var calibration = MeshCalibrationModelScript.from_dictionary(payload)
			if calibration != null:
				_mesh_sync_service.publish_calibration(calibration)
		"spawn":
			var object_id := String(payload.get("object_id", ""))
			if not object_id.is_empty():
				var descriptor := payload.duplicate(true)
				descriptor.erase("object_id")
				_mesh_sync_service.publish_object_spawn(object_id, descriptor)
		"transform":
			var transform_object_id := String(payload.get("object_id", ""))
			if not transform_object_id.is_empty():
				if String(payload.get("owner_peer_id", "")).is_empty():
					payload["owner_peer_id"] = sender_peer_id
				_mesh_sync_service.publish_object_transform(transform_object_id, payload)
		"despawn":
			var despawn_object_id := String(payload.get("object_id", ""))
			if not despawn_object_id.is_empty():
				_mesh_sync_service.publish_object_despawn(despawn_object_id)
	_applying_remote = false