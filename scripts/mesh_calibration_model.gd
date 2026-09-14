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
		"physical_position": physical_position,
		"physical_rotation_degrees": physical_rotation_degrees,
		"viewport_size": viewport_size,
		"camera_offset": camera_offset
	}
