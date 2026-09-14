class_name SpinningCubeMeshSyncController
extends RefCounted

const MeshCalibrationModelScript = preload("res://scripts/mesh_calibration_model.gd")
const MeshSyncServiceScript = preload("res://scripts/mesh_sync_service.gd")
const TransformSyncSchemaScript = preload("res://scripts/transform_sync_schema.gd")

var enabled: bool = true
var mesh_node_id: String = "local_display"
var mesh_peer_id: String = "local"
var shared_object_id: String = "spinning_cube"
var calibration_model: MeshCalibrationModel

var _owns_default_calibration_model: bool = false
var _camera: Camera3D
var _target: MeshInstance3D
var _viewport: Viewport
var _mesh_sync_service = MeshSyncServiceScript.new()
var _transform_schema = TransformSyncSchemaScript.new()

func configure(target: MeshInstance3D, camera: Camera3D, viewport: Viewport, enabled_value: bool, node_id: String, peer_id: String, object_id: String, calibration: MeshCalibrationModel) -> MeshCalibrationModel:
	_target = target
	_camera = camera
	_viewport = viewport
	enabled = enabled_value
	mesh_node_id = node_id
	mesh_peer_id = peer_id
	shared_object_id = object_id
	calibration_model = calibration
	_owns_default_calibration_model = false

	if not enabled:
		return calibration_model

	if calibration_model == null:
		calibration_model = MeshCalibrationModelScript.new()
		calibration_model.node_id = mesh_node_id
		_owns_default_calibration_model = true

	_mesh_sync_service.local_peer_id = mesh_peer_id
	if not _mesh_sync_service.calibration_updated.is_connected(_on_calibration_updated):
		_mesh_sync_service.calibration_updated.connect(_on_calibration_updated)
	if not _mesh_sync_service.shared_object_spawned.is_connected(_on_shared_object_spawned):
		_mesh_sync_service.shared_object_spawned.connect(_on_shared_object_spawned)
	if not _mesh_sync_service.shared_object_transform_updated.is_connected(_on_shared_object_transform_updated):
		_mesh_sync_service.shared_object_transform_updated.connect(_on_shared_object_transform_updated)
	if not _mesh_sync_service.shared_object_despawned.is_connected(_on_shared_object_despawned):
		_mesh_sync_service.shared_object_despawned.connect(_on_shared_object_despawned)

	_seed_default_calibration_from_camera()
	_publish_object_descriptor()
	_publish_calibration()
	_mesh_sync_service.set_peer_online(mesh_peer_id, true)
	return calibration_model

func set_camera(camera: Camera3D) -> void:
	_camera = camera
	_seed_default_calibration_from_camera()
	_publish_calibration()

func handle_viewport_size_changed(viewport: Viewport) -> void:
	_viewport = viewport
	_publish_calibration()

func process_transform(target: MeshInstance3D) -> void:
	_target = target
	if not enabled or _target == null:
		return

	_mesh_sync_service.publish_object_transform(
		shared_object_id,
		_transform_schema.serialize_transform(shared_object_id, mesh_peer_id, _target.global_transform)
	)

func shutdown() -> void:
	if enabled:
		_mesh_sync_service.set_peer_online(mesh_peer_id, false)

func _seed_default_calibration_from_camera() -> void:
	if not _owns_default_calibration_model or calibration_model == null or _camera == null:
		return

	calibration_model.camera_offset = _camera.transform

func _publish_object_descriptor() -> void:
	if not enabled:
		return

	_mesh_sync_service.publish_object_spawn(shared_object_id, {
		"authority": "single_owner",
		"kind": "mesh_instance",
		"capabilities": PackedStringArray(["shape", "texture", "static_image", "text", "audio"]),
		"render_config": {
			"camera_texture_source": "local_only",
			"shader": "cube_shader",
			"mesh_type": "box"
		},
		"audio_config": {},
		"media_streams": []
	})

func _publish_calibration() -> void:
	if not enabled or calibration_model == null:
		return

	if calibration_model.node_id.is_empty():
		calibration_model.node_id = mesh_node_id

	if _viewport != null:
		var visible_rect_size := _viewport.get_visible_rect().size
		calibration_model.viewport_size = Vector2i(int(visible_rect_size.x), int(visible_rect_size.y))

	_mesh_sync_service.publish_calibration(calibration_model)

func _on_calibration_updated(node_id: String, calibration: MeshCalibrationModel) -> void:
	if node_id != mesh_node_id or calibration == null or _camera == null:
		return

	if (
		calibration.camera_offset == Transform3D.IDENTITY
		and calibration.physical_position == Vector3.ZERO
		and calibration.physical_rotation_degrees == Vector3.ZERO
	):
		return

	var physical_rotation_radians := Vector3(
		deg_to_rad(calibration.physical_rotation_degrees.x),
		deg_to_rad(calibration.physical_rotation_degrees.y),
		deg_to_rad(calibration.physical_rotation_degrees.z)
	)
	var physical_transform := Transform3D(
		Basis.from_euler(physical_rotation_radians),
		calibration.physical_position
	)
	_camera.global_transform = physical_transform * calibration.camera_offset

func _on_shared_object_spawned(object_id: String, descriptor: Dictionary) -> void:
	if object_id != shared_object_id or _target == null:
		return

	_target.visible = bool(descriptor.get("visible", true))

func _on_shared_object_transform_updated(object_id: String, transform_state: Dictionary) -> void:
	if object_id != shared_object_id or _target == null:
		return

	if String(transform_state.get("owner_peer_id", "")) == mesh_peer_id:
		return

	var position: Vector3 = transform_state.get("position", _target.global_position)
	var rotation: Quaternion = transform_state.get("rotation", Quaternion.IDENTITY)
	_target.global_transform = Transform3D(Basis(rotation), position)

func _on_shared_object_despawned(object_id: String) -> void:
	if object_id != shared_object_id or _target == null:
		return

	_target.visible = false
