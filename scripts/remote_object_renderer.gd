class_name RemoteObjectRenderer
extends Node

signal snapshot_requested(object_id, owner_peer_id)

const WallGeometryCalculatorScript = preload("res://scripts/wall_geometry_calculator.gd")
const SUPPORTED_DESCRIPTOR_KINDS := ["mesh_instance"]

var _mesh_sync_service
var _local_object_id: String = ""
var _camera: Camera3D
var _snapshot_callback: Callable = Callable()
var _proxy_states: Dictionary = {}
var _pending_transforms: Dictionary = {}

func configure(mesh_sync_service, local_object_id: String, camera: Camera3D = null) -> void:
	_mesh_sync_service = mesh_sync_service
	_local_object_id = local_object_id
	_camera = camera
	_connect_service_signals()

func set_camera(camera: Camera3D) -> void:
	_camera = camera

func set_snapshot_request_callback(callback: Callable) -> void:
	_snapshot_callback = callback

func apply_snapshot(object_id: String, texture: Texture2D) -> void:
	if object_id.is_empty() or texture == null:
		return
	var state: Dictionary = _proxy_states.get(object_id, {})
	var instance: MeshInstance3D = state.get("instance")
	if instance == null or not instance.material_override is ShaderMaterial:
		return
	var material := instance.material_override as ShaderMaterial
	material.set_shader_parameter("webcam_texture", texture)
	material.set_shader_parameter("webcam_cbcr_texture", null)
	material.set_shader_parameter("webcam_mode", 1)
	material.set_shader_parameter("use_front_texture", false)

func process(_delta: float) -> void:
	if _mesh_sync_service == null:
		return
	for object_id_variant in _proxy_states.keys():
		var object_id := String(object_id_variant)
		var state: Dictionary = _proxy_states.get(object_id, {})
		var instance: MeshInstance3D = state.get("instance")
		if instance == null or _camera == null:
			continue
		var currently_visible := _is_object_visible_to_camera(instance.global_position)
		var was_visible := bool(state.get("is_visible", false))
		state["is_visible"] = currently_visible
		if not was_visible and currently_visible:
			_request_snapshot(object_id, String(state.get("owner_peer_id", "")))

func shutdown() -> void:
	_disconnect_service_signals()
	for object_id_variant in _proxy_states.keys():
		var object_id := String(object_id_variant)
		var state: Dictionary = _proxy_states.get(object_id, {})
		var instance: MeshInstance3D = state.get("instance")
		if instance != null:
			instance.queue_free()
	_proxy_states.clear()
	_pending_transforms.clear()

func _connect_service_signals() -> void:
	if _mesh_sync_service == null:
		return
	if not _mesh_sync_service.shared_object_spawned.is_connected(_on_shared_object_spawned):
		_mesh_sync_service.shared_object_spawned.connect(_on_shared_object_spawned)
	if not _mesh_sync_service.shared_object_transform_updated.is_connected(_on_shared_object_transform_updated):
		_mesh_sync_service.shared_object_transform_updated.connect(_on_shared_object_transform_updated)
	if not _mesh_sync_service.shared_object_despawned.is_connected(_on_shared_object_despawned):
		_mesh_sync_service.shared_object_despawned.connect(_on_shared_object_despawned)
	if not _mesh_sync_service.peer_connection_changed.is_connected(_on_peer_connection_changed):
		_mesh_sync_service.peer_connection_changed.connect(_on_peer_connection_changed)

func _disconnect_service_signals() -> void:
	if _mesh_sync_service == null:
		return
	if _mesh_sync_service.shared_object_spawned.is_connected(_on_shared_object_spawned):
		_mesh_sync_service.shared_object_spawned.disconnect(_on_shared_object_spawned)
	if _mesh_sync_service.shared_object_transform_updated.is_connected(_on_shared_object_transform_updated):
		_mesh_sync_service.shared_object_transform_updated.disconnect(_on_shared_object_transform_updated)
	if _mesh_sync_service.shared_object_despawned.is_connected(_on_shared_object_despawned):
		_mesh_sync_service.shared_object_despawned.disconnect(_on_shared_object_despawned)
	if _mesh_sync_service.peer_connection_changed.is_connected(_on_peer_connection_changed):
		_mesh_sync_service.peer_connection_changed.disconnect(_on_peer_connection_changed)

func _on_shared_object_spawned(object_id: String, descriptor: Dictionary) -> void:
	if object_id.is_empty() or object_id == _local_object_id:
		return
	var state: Dictionary = _proxy_states.get(object_id, {})
	if state.has("instance") and state.get("instance") != null:
		state["descriptor"] = descriptor
		state["owner_peer_id"] = String(descriptor.get("owner_peer_id", state.get("owner_peer_id", "")))
		return
	var instance := _create_proxy_for_descriptor(object_id, descriptor)
	if instance == null:
		return
	_proxy_states[object_id] = {
		"instance": instance,
		"descriptor": descriptor,
		"owner_peer_id": String(descriptor.get("owner_peer_id", "")),
		"is_visible": false
	}
	var pending_transform: Dictionary = _pending_transforms.get(object_id, {})
	if not pending_transform.is_empty():
		_apply_transform(object_id, pending_transform)
		_pending_transforms.erase(object_id)
	else:
		var known_state: Dictionary = _mesh_sync_service.get_last_known_object_state(object_id)
		var known_transform: Dictionary = known_state.get("transform", {})
		if not known_transform.is_empty():
			_apply_transform(object_id, known_transform)

func _on_shared_object_transform_updated(object_id: String, transform_state: Dictionary) -> void:
	if object_id.is_empty() or object_id == _local_object_id:
		return
	var state: Dictionary = _proxy_states.get(object_id, {})
	var instance: MeshInstance3D = state.get("instance")
	if instance == null:
		_pending_transforms[object_id] = transform_state.duplicate(true)
		return
	_apply_transform(object_id, transform_state)

func _apply_transform(object_id: String, transform_state: Dictionary) -> void:
	var state: Dictionary = _proxy_states.get(object_id, {})
	var instance: MeshInstance3D = state.get("instance")
	if instance == null:
		return
	state["owner_peer_id"] = String(transform_state.get("owner_peer_id", state.get("owner_peer_id", "")))
	var position: Vector3 = transform_state.get("position", instance.global_position)
	var rotation: Quaternion = transform_state.get("rotation", Quaternion.IDENTITY)
	instance.global_transform = Transform3D(Basis(rotation), position)

func _on_shared_object_despawned(object_id: String) -> void:
	if object_id.is_empty() or object_id == _local_object_id:
		return
	var state: Dictionary = _proxy_states.get(object_id, {})
	var instance: MeshInstance3D = state.get("instance")
	if instance != null:
		instance.queue_free()
	_proxy_states.erase(object_id)

func _on_peer_connection_changed(peer_id: String, is_online: bool) -> void:
	if is_online:
		return
	for object_id_variant in _proxy_states.keys():
		var object_id := String(object_id_variant)
		var state: Dictionary = _proxy_states.get(object_id, {})
		if String(state.get("owner_peer_id", "")) == peer_id:
			var instance: MeshInstance3D = state.get("instance")
			if instance != null:
				instance.queue_free()
		_proxy_states.erase(object_id)

func _create_proxy_for_descriptor(object_id: String, descriptor: Dictionary) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = "RemoteProxy_%s" % object_id
	_resolve_descriptor_kind(descriptor)
	var box_mesh := BoxMesh.new()
	box_mesh.size = _resolve_proxy_size(descriptor)
	instance.mesh = box_mesh
	var material := ShaderMaterial.new()
	material.shader = load("res://cube_shader.gdshader")
	material.set_shader_parameter("cube_size", box_mesh.size)
	material.set_shader_parameter("use_front_texture", false)
	material.set_shader_parameter("webcam_mode", 0)
	material.set_shader_parameter("webcam_fit_mode", 0)
	material.set_shader_parameter("webcam_flip_h", true)
	material.set_shader_parameter("webcam_aspect", 1.777777)
	material.set_shader_parameter("webcam_texture", null)
	material.set_shader_parameter("webcam_cbcr_texture", null)
	material.set_shader_parameter("cube_color", Color(0.12, 0.15, 0.22, 1.0))
	material.set_shader_parameter("border_color", Color(0.35, 0.65, 0.95, 1.0))
	instance.material_override = material
	if get_parent() != null:
		get_parent().add_child(instance)
	else:
		add_child(instance)
	return instance

func _resolve_descriptor_kind(descriptor: Dictionary) -> String:
	var descriptor_kind := String(descriptor.get("kind", "mesh_instance"))
	if SUPPORTED_DESCRIPTOR_KINDS.has(descriptor_kind):
		return descriptor_kind
	print("[remote_object_renderer] Unknown descriptor kind '", descriptor_kind, "'; using generic box proxy")
	return "mesh_instance"

func _resolve_proxy_size(descriptor: Dictionary) -> Vector3:
	var render_config: Dictionary = descriptor.get("render_config", {})
	if typeof(render_config) == TYPE_DICTIONARY:
		var candidate: Variant = render_config.get("size", null)
		if typeof(candidate) == TYPE_ARRAY and candidate.size() >= 3:
			return _validated_proxy_size(candidate)
		candidate = render_config.get("box_size", null)
		if typeof(candidate) == TYPE_ARRAY and candidate.size() >= 3:
			return _validated_proxy_size(candidate)
		candidate = render_config.get("scale", null)
		if typeof(candidate) == TYPE_ARRAY and candidate.size() >= 3:
			return _validated_proxy_size(candidate)
	return Vector3(1.8, 1.8, 0.1)

func _validated_proxy_size(candidate: Array) -> Vector3:
	var size := Vector3(float(candidate[0]), float(candidate[1]), float(candidate[2]))
	if not is_finite(size.x) or not is_finite(size.y) or not is_finite(size.z):
		return Vector3(1.8, 1.8, 0.1)
	if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
		return Vector3(1.8, 1.8, 0.1)
	return size

func _is_object_visible_to_camera(position: Vector3) -> bool:
	if _camera == null:
		return false
	var camera_local := _camera.global_transform.affine_inverse() * position
	if camera_local.z >= 0.0:
		return false
	var distance := maxf(absf(camera_local.z), 0.0001)
	var frustum_size := WallGeometryCalculatorScript.frustum_size_at_distance(_camera, distance)
	return absf(camera_local.x) <= frustum_size.x and absf(camera_local.y) <= frustum_size.y

func _request_snapshot(object_id: String, owner_peer_id: String) -> void:
	if object_id.is_empty():
		return
	if _snapshot_callback.is_valid():
		_snapshot_callback.call(object_id, owner_peer_id)
	snapshot_requested.emit(object_id, owner_peer_id)
