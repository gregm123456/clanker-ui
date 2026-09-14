extends MeshInstance3D

const SpinningCubeInputControllerScript = preload("res://scripts/spinning_cube_input_controller.gd")
const SpinningCubeMovementControllerScript = preload("res://scripts/spinning_cube_movement_controller.gd")
const WebcamCameraSourceAdapterScript = preload("res://scripts/webcam_camera_source_adapter.gd")
const MeshCalibrationModelScript = preload("res://scripts/mesh_calibration_model.gd")
const MeshSyncServiceScript = preload("res://scripts/mesh_sync_service.gd")
const TransformSyncSchemaScript = preload("res://scripts/transform_sync_schema.gd")

## Speed of 3D tumbling rotation around X, Y, and Z axes (in radians per second)
@export var tumble_speed: Vector3 = Vector3(1.2, 1.8, 0.9)

## Velocity of the cube moving across the screen (X = horizontal, Y = vertical)
@export var move_velocity: Vector2 = Vector2(2.2, 1.4)

## Enable or disable screen boundary wraparound
@export var enable_wraparound: bool = true

## Margin beyond viewport edge before wrapping (in world units)
@export var wrap_margin: float = 1.6

## Enable live webcam feed on the second face (+X)
@export var enable_webcam: bool = true

## Webcam feed index (0 = default / built-in webcam)
@export var webcam_feed_index: int = 0

## Prefer a Raspberry Pi CSI/libcamera feed when one is available. CSI cameras
## exposed through the V4L2 compatibility layer appear as normal CameraFeeds.
@export var prefer_csi_camera: bool = true

## Requested processed stream size for the native Raspberry Pi CSI provider
@export var csi_camera_width: int = 960
@export var csi_camera_height: int = 540
@export var csi_camera_fps: int = 30
@export var csi_camera_name: String = ""

## How the webcam frame fits onto the square cube face:
## 0 = Fit Letterbox (shows full camera frame without distortion/cropping)
## 1 = Cover (crops to fill entire square face)
## 2 = Stretch (stretches to square)
@export_enum("Fit Letterbox:0", "Cover Crop:1", "Stretch:2") var webcam_fit_mode: int = 0

## Flip webcam horizontally (mirror / selfie view)
@export var flip_webcam_horizontal: bool = true

## Automatically start in full screen mode (ideal for Raspberry Pi / standalone displays)
@export var start_fullscreen: bool = true

## Automatically hide mouse cursor (ideal for kiosk / fullscreen runs)
@export var hide_mouse_cursor: bool = true

## Shared scene mesh sync identifiers and calibration resource
@export var mesh_sync_enabled: bool = true
@export var mesh_node_id: String = "local_display"
@export var mesh_peer_id: String = "local"
@export var shared_object_id: String = "spinning_cube"
@export var calibration_model: MeshCalibrationModel

var camera: Camera3D

var _mat: ShaderMaterial
var _input_controller = SpinningCubeInputControllerScript.new()
var _movement_controller = SpinningCubeMovementControllerScript.new()
var _camera_source = WebcamCameraSourceAdapterScript.new()
var _mesh_sync_service = MeshSyncServiceScript.new()
var _transform_schema = TransformSyncSchemaScript.new()
var _owns_default_calibration_model: bool = false
var _webcam_started: bool = false

func _ready() -> void:
	camera = get_viewport().get_camera_3d()
	_configure_components()
	_movement_controller.randomize_speed_and_velocity()
	tumble_speed = _movement_controller.tumble_speed
	move_velocity = _movement_controller.move_velocity
	_input_controller.apply_startup_state(start_fullscreen, hide_mouse_cursor)

	_setup_material()

	if camera == null:
		get_tree().process_frame.connect(_find_camera, CONNECT_ONE_SHOT)

	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_on_viewport_size_changed):
		vp.size_changed.connect(_on_viewport_size_changed)

	_configure_mesh_sync()
	_update_webcam_state()

func _unhandled_input(event: InputEvent) -> void:
	_input_controller.handle_input(event, get_tree())

func _on_viewport_size_changed() -> void:
	camera = _movement_controller.handle_viewport_size_changed(self, camera, get_viewport())
	_publish_calibration()

func _setup_material() -> void:
	var base_mat := get_active_material(0)
	if base_mat == null and mesh != null:
		base_mat = mesh.surface_get_material(0)

	if base_mat is ShaderMaterial:
		_mat = base_mat.duplicate() as ShaderMaterial
		set_surface_override_material(0, _mat)
		if mesh is BoxMesh:
			var bm := mesh as BoxMesh
			_mat.set_shader_parameter("cube_size", bm.size)
		_mat.set_shader_parameter("webcam_flip_h", flip_webcam_horizontal)
		_mat.set_shader_parameter("webcam_fit_mode", webcam_fit_mode)

func _find_camera() -> void:
	camera = get_viewport().get_camera_3d()
	_seed_default_calibration_from_camera()
	_publish_calibration()

func _exit_tree() -> void:
	_camera_source.shutdown()
	_webcam_started = false
	if mesh_sync_enabled:
		_mesh_sync_service.set_peer_online(mesh_peer_id, false)

func _process(delta: float) -> void:
	_update_webcam_state()
	if _webcam_started:
		_camera_source.process(delta)
	camera = _movement_controller.process_transform(self, delta, camera, get_viewport())
	_publish_transform_state()

func _configure_components() -> void:
	_input_controller.hide_mouse_cursor = hide_mouse_cursor

	_movement_controller.tumble_speed = tumble_speed
	_movement_controller.move_velocity = move_velocity
	_movement_controller.enable_wraparound = enable_wraparound
	_movement_controller.wrap_margin = wrap_margin

	var webcam_adapter = _camera_source
	webcam_adapter.webcam_feed_index = webcam_feed_index
	webcam_adapter.prefer_csi_camera = prefer_csi_camera
	webcam_adapter.csi_camera_width = csi_camera_width
	webcam_adapter.csi_camera_height = csi_camera_height
	webcam_adapter.csi_camera_fps = csi_camera_fps
	webcam_adapter.csi_camera_name = csi_camera_name
	webcam_adapter.webcam_fit_mode = webcam_fit_mode
	webcam_adapter.flip_webcam_horizontal = flip_webcam_horizontal

func _update_webcam_state() -> void:
	if enable_webcam and not _webcam_started:
		_camera_source.setup(_mat)
		_webcam_started = true
	elif not enable_webcam and _webcam_started:
		_camera_source.shutdown()
		_webcam_started = false

func _configure_mesh_sync() -> void:
	if not mesh_sync_enabled:
		return

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

func _seed_default_calibration_from_camera() -> void:
	if not _owns_default_calibration_model or calibration_model == null or camera == null:
		return

	calibration_model.camera_offset = camera.transform

func _publish_object_descriptor() -> void:
	if not mesh_sync_enabled:
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
	if not mesh_sync_enabled or calibration_model == null:
		return

	if calibration_model.node_id.is_empty():
		calibration_model.node_id = mesh_node_id

	var vp := get_viewport()
	if vp != null:
		var visible_rect_size := vp.get_visible_rect().size
		calibration_model.viewport_size = Vector2i(int(visible_rect_size.x), int(visible_rect_size.y))

	_mesh_sync_service.publish_calibration(calibration_model)

func _publish_transform_state() -> void:
	if not mesh_sync_enabled:
		return

	_mesh_sync_service.publish_object_transform(
		shared_object_id,
		_transform_schema.serialize_transform(shared_object_id, mesh_peer_id, global_transform)
	)

func _on_calibration_updated(node_id: String, calibration: MeshCalibrationModel) -> void:
	if node_id != mesh_node_id or calibration == null or camera == null:
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
	camera.global_transform = physical_transform * calibration.camera_offset

func _on_shared_object_spawned(object_id: String, descriptor: Dictionary) -> void:
	if object_id != shared_object_id:
		return

	visible = bool(descriptor.get("visible", true))

func _on_shared_object_transform_updated(object_id: String, transform_state: Dictionary) -> void:
	if object_id != shared_object_id:
		return

	if String(transform_state.get("owner_peer_id", "")) == mesh_peer_id:
		return

	var position: Vector3 = transform_state.get("position", global_position)
	var rotation: Quaternion = transform_state.get("rotation", Quaternion.IDENTITY)
	global_transform = Transform3D(Basis(rotation), position)

func _on_shared_object_despawned(object_id: String) -> void:
	if object_id != shared_object_id:
		return

	visible = false
