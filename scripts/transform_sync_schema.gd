class_name TransformSyncSchema
extends RefCounted

const SCHEMA_VERSION := 1

func serialize_transform(object_id: String, owner_peer_id: String, transform: Transform3D, timestamp_usec: int = Time.get_ticks_usec()) -> Dictionary:
	var rotation := transform.basis.get_rotation_quaternion()
	return {
		"version": SCHEMA_VERSION,
		"object_id": object_id,
		"owner_peer_id": owner_peer_id,
		"timestamp_usec": timestamp_usec,
		"position": [transform.origin.x, transform.origin.y, transform.origin.z],
		"rotation": [rotation.x, rotation.y, rotation.z, rotation.w]
	}

func deserialize_transform(payload: Dictionary) -> Dictionary:
	if int(payload.get("version", -1)) != SCHEMA_VERSION:
		return {}

	var position_data = payload.get("position", [])
	var rotation_data = payload.get("rotation", [])
	if position_data.size() != 3 or rotation_data.size() != 4:
		return {}

	var opacity: Variant = payload.get("opacity", 1.0)
	if typeof(opacity) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(opacity)) or float(opacity) < 0.0 or float(opacity) > 1.0:
		push_warning("[mesh_sync] Invalid object opacity")
		return {}
	var result := {
		"version": SCHEMA_VERSION,
		"object_id": String(payload.get("object_id", "")),
		"owner_peer_id": String(payload.get("owner_peer_id", "")),
		"timestamp_usec": int(payload.get("timestamp_usec", 0)),
		"opacity": float(opacity),
		"position": Vector3(
			float(position_data[0]),
			float(position_data[1]),
			float(position_data[2])
		),
		"rotation": Quaternion(
			float(rotation_data[0]),
			float(rotation_data[1]),
			float(rotation_data[2]),
			float(rotation_data[3])
		)
	}
	if payload.has("portrait_cycle") or payload.has("portrait_incarnation"):
		var sequence: Variant = payload.get("portrait_cycle")
		var incarnation: Variant = payload.get("portrait_incarnation")
		if typeof(sequence) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(sequence)) \
				or float(sequence) < 0.0 or float(sequence) != floor(float(sequence)) \
				or typeof(incarnation) != TYPE_STRING or String(incarnation).is_empty():
			push_warning("[mesh_sync] Invalid portrait cycle marker")
			return {}
		result["portrait_cycle"] = int(sequence)
		result["portrait_incarnation"] = String(incarnation)
	return result
