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

	return {
		"version": SCHEMA_VERSION,
		"object_id": String(payload.get("object_id", "")),
		"owner_peer_id": String(payload.get("owner_peer_id", "")),
		"timestamp_usec": int(payload.get("timestamp_usec", 0)),
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
