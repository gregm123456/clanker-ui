class_name MeshCalibrationModel
extends Resource

@export var node_id: String = "local_display"
@export var physical_position: Vector3 = Vector3.ZERO
@export var physical_rotation_degrees: Vector3 = Vector3.ZERO
@export var viewport_size: Vector2i = Vector2i.ZERO
@export var camera_offset: Transform3D = Transform3D.IDENTITY

func duplicate_model() -> MeshCalibrationModel:
	var copy := MeshCalibrationModel.new()
	copy.node_id = node_id
	copy.physical_position = physical_position
	copy.physical_rotation_degrees = physical_rotation_degrees
	copy.viewport_size = viewport_size
	copy.camera_offset = camera_offset
	return copy

func to_dictionary() -> Dictionary:
	return {
		"node_id": node_id,
		"physical_position": _vector3_to_array(physical_position),
		"physical_rotation_degrees": _vector3_to_array(physical_rotation_degrees),
		"viewport_size": [viewport_size.x, viewport_size.y],
		"camera_offset": {
			"origin": _vector3_to_array(camera_offset.origin),
			"rotation": _quaternion_to_array(camera_offset.basis.get_rotation_quaternion())
		}
	}

static func from_dictionary(data: Dictionary) -> MeshCalibrationModel:
	var model := MeshCalibrationModel.new()
	model.node_id = String(data.get("node_id", ""))
	var position_data: Variant = data.get("physical_position", [])
	var rotation_data: Variant = data.get("physical_rotation_degrees", [])
	var viewport_data: Variant = data.get("viewport_size", [])
	if typeof(position_data) != TYPE_ARRAY or position_data.size() != 3:
		return null
	if typeof(rotation_data) != TYPE_ARRAY or rotation_data.size() != 3:
		return null
	if typeof(viewport_data) != TYPE_ARRAY or viewport_data.size() != 2:
		return null
	model.physical_position = _array_to_vector3(position_data)
	model.physical_rotation_degrees = _array_to_vector3(rotation_data)
	model.viewport_size = Vector2i(int(viewport_data[0]), int(viewport_data[1]))
	var camera_data: Variant = data.get("camera_offset", {})
	if typeof(camera_data) == TYPE_DICTIONARY:
		var origin_data: Variant = camera_data.get("origin", [])
		var camera_rotation_data: Variant = camera_data.get("rotation", [])
		if typeof(origin_data) == TYPE_ARRAY and origin_data.size() == 3 and typeof(camera_rotation_data) == TYPE_ARRAY and camera_rotation_data.size() == 4:
			model.camera_offset = Transform3D(Basis(Quaternion(
				float(camera_rotation_data[0]),
				float(camera_rotation_data[1]),
				float(camera_rotation_data[2]),
				float(camera_rotation_data[3])
			)), _array_to_vector3(origin_data))
	return model

static func _vector3_to_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]

static func _quaternion_to_array(value: Quaternion) -> Array[float]:
	return [value.x, value.y, value.z, value.w]

static func _array_to_vector3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
