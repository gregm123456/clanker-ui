class_name MeshSyncService
extends RefCounted

const TransformSyncSchemaScript = preload("res://scripts/transform_sync_schema.gd")

signal calibration_updated(node_id, calibration)
signal shared_object_spawned(object_id, descriptor)
signal shared_object_transform_updated(object_id, transform_state)
signal shared_object_despawned(object_id)
signal peer_connection_changed(peer_id, is_online)

var local_peer_id: String = "local"

var _calibrations: Dictionary = {}
var _shared_objects: Dictionary = {}
var _peer_status: Dictionary = {}
var _transform_schema = TransformSyncSchemaScript.new()

func publish_calibration(calibration: MeshCalibrationModel) -> void:
	if calibration == null or calibration.node_id.is_empty():
		return

	var snapshot := calibration.duplicate_model()
	_calibrations[snapshot.node_id] = snapshot
	calibration_updated.emit(snapshot.node_id, snapshot)

func publish_object_spawn(object_id: String, descriptor: Dictionary) -> void:
	if object_id.is_empty():
		return

	var normalized := _normalize_descriptor(object_id, descriptor)
	var existing_state: Dictionary = _shared_objects.get(object_id, {})
	_shared_objects[object_id] = {
		"descriptor": normalized,
		"transform": existing_state.get("transform", {})
	}
	shared_object_spawned.emit(object_id, normalized)

func publish_object_transform(object_id: String, payload: Dictionary) -> void:
	if object_id.is_empty():
		return

	var normalized_transform := _transform_schema.deserialize_transform(payload)
	if normalized_transform.is_empty():
		return

	if normalized_transform.get("object_id", "").is_empty():
		normalized_transform["object_id"] = object_id
	if normalized_transform.get("owner_peer_id", "").is_empty():
		normalized_transform["owner_peer_id"] = local_peer_id

	var existing_state: Dictionary = _shared_objects.get(object_id, {})
	if existing_state.is_empty():
		existing_state = {
			"descriptor": _normalize_descriptor(object_id, {})
		}
	existing_state["transform"] = normalized_transform
	_shared_objects[object_id] = existing_state
	shared_object_transform_updated.emit(object_id, normalized_transform)

func publish_object_despawn(object_id: String) -> void:
	if object_id.is_empty():
		return

	if _shared_objects.has(object_id):
		_shared_objects.erase(object_id)
	shared_object_despawned.emit(object_id)

func set_peer_online(peer_id: String, is_online: bool) -> void:
	if peer_id.is_empty():
		return

	_peer_status[peer_id] = is_online
	peer_connection_changed.emit(peer_id, is_online)

func get_last_known_object_state(object_id: String) -> Dictionary:
	return _shared_objects.get(object_id, {}).duplicate(true)

func get_calibration(node_id: String) -> MeshCalibrationModel:
	return _calibrations.get(node_id, null)

func _normalize_descriptor(object_id: String, descriptor: Dictionary) -> Dictionary:
	var normalized := descriptor.duplicate(true)
	normalized["object_id"] = object_id
	if not normalized.has("authority"):
		normalized["authority"] = "single_owner"
	if not normalized.has("kind"):
		normalized["kind"] = "mesh_instance"
	if not normalized.has("capabilities"):
		normalized["capabilities"] = PackedStringArray(["shape", "texture", "static_image", "text", "audio"])
	if not normalized.has("render_config"):
		normalized["render_config"] = {}
	if not normalized.has("audio_config"):
		normalized["audio_config"] = {}
	if not normalized.has("media_streams"):
		normalized["media_streams"] = []
	return normalized
