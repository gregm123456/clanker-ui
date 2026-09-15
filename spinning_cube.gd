extends MeshInstance3D

const SpinningCubeInputControllerScript = preload("res://scripts/spinning_cube_input_controller.gd")
const SpinningCubeMovementControllerScript = preload("res://scripts/spinning_cube_movement_controller.gd")
const WebcamCameraSourceAdapterScript = preload("res://scripts/webcam_camera_source_adapter.gd")
const SpinningCubeMeshSyncControllerScript = preload("res://scripts/spinning_cube_mesh_sync_controller.gd")
const InstallationConfigScript = preload("res://scripts/installation_config.gd")
const WallGeometryCalculatorScript = preload("res://scripts/wall_geometry_calculator.gd")
const MeshNetworkBridgeScript = preload("res://scripts/mesh_network_bridge.gd")
const RemoteObjectRendererScript = preload("res://scripts/remote_object_renderer.gd")

## Speed of 3D tumbling rotation around X, Y, and Z axes (in radians per second)
@export var tumble_speed: Vector3 = Vector3(1.2, 1.8, 0.9)

## Velocity of the cube in world space (+X = right, +Y = up, +Z = toward camera)
@export var move_velocity: Vector3 = Vector3(2.2, 1.4, 0.0)

## Constant acceleration in world space, applied to movement velocity each update
@export var move_acceleration: Vector3 = Vector3.ZERO

## Compatibility adapter for legacy 2D tuning (X/Y only)
@export var use_legacy_2d_velocity_adapter: bool = false
@export var legacy_move_velocity_2d: Vector2 = Vector2(2.2, 1.4)

## Enable or disable screen boundary wraparound
@export var enable_wraparound: bool = true

## Margin beyond viewport edge before wrapping (in world units)
@export var wrap_margin: float = 1.6

## Bounds mode strategy:
## 0 = none, 1 = 2D camera-relative wrap, 2 = 3D world-volume bounds
@export_enum("None:0", "2D Viewport Wrap:1", "3D Volume Bounds:2") var bounds_mode: int = 1

## 3D world-volume bounds behavior:
## 0 = wrap to opposite wall, 1 = hard-wall clamp
@export_enum("Wrap:0", "Hard Wall Clamp:1") var bounds_behavior: int = 0

## Optional physical installation geometry for 3D bounds evaluation.
## If unset, bounds_volume_center/half_extents are used directly.
@export var installation_geometry: InstallationGeometry
@export var bounds_volume_center: Vector3 = Vector3.ZERO
@export var bounds_volume_half_extents: Vector3 = Vector3(8.0, 4.5, 4.0)

## Use fixed-step movement updates for deterministic motion progression.
@export var use_fixed_step_movement: bool = false

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
var installation_config: InstallationConfig

var _mat: ShaderMaterial
var _input_controller = SpinningCubeInputControllerScript.new()
var _movement_controller = SpinningCubeMovementControllerScript.new()
var _camera_source = WebcamCameraSourceAdapterScript.new()
var _mesh_sync_controller = SpinningCubeMeshSyncControllerScript.new()
var _mesh_network_bridge
var _remote_object_renderer
var _webcam_started: bool = false

func _ready() -> void:
	installation_config = InstallationConfigScript.new()
	camera = get_viewport().get_camera_3d()
	_apply_runtime_configuration()
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
	_mesh_sync_controller.handle_viewport_size_changed(get_viewport())

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
	_mesh_sync_controller.set_camera(camera)

func _exit_tree() -> void:
	_camera_source.shutdown()
	_webcam_started = false
	if _mesh_network_bridge != null:
		_mesh_network_bridge.shutdown()
	if _remote_object_renderer != null:
		_remote_object_renderer.shutdown()
	_mesh_sync_controller.shutdown()

func _process(delta: float) -> void:
	_update_webcam_state()
	if _webcam_started:
		_camera_source.process(delta)
	if not use_fixed_step_movement:
		camera = _movement_controller.process_transform(self, delta, camera, get_viewport())
	_mesh_sync_controller.process_transform(self)
	if _remote_object_renderer != null:
		_remote_object_renderer.process(delta)

func _physics_process(delta: float) -> void:
	if use_fixed_step_movement:
		camera = _movement_controller.process_transform(self, delta, camera, get_viewport())

func _apply_runtime_configuration() -> void:
	if installation_config == null:
		installation_config = InstallationConfigScript.new()

	var config_node_id := installation_config.get_node_id().strip_edges()
	if not config_node_id.is_empty():
		mesh_node_id = config_node_id

	var config_peer_id := installation_config.get_peer_id().strip_edges()
	if not config_peer_id.is_empty():
		mesh_peer_id = config_peer_id

	var wall_layout: Dictionary = installation_config.get_wall_layout()
	if wall_layout.has("columns") and wall_layout.has("rows"):
		var world_units_per_mm := WallGeometryCalculatorScript.compute_world_units_per_mm(camera, float(wall_layout.get("monitor_width_mm", 168.0)))
		var computed_node_offset := WallGeometryCalculatorScript.compute_node_camera_offset(wall_layout, world_units_per_mm)
		var computed_wall_bounds := WallGeometryCalculatorScript.compute_wall_world_bounds(wall_layout, world_units_per_mm)

		if installation_geometry == null:
			installation_geometry = InstallationGeometry.new()
		installation_geometry.world_bounds_center = computed_wall_bounds.get("center", Vector3.ZERO)
		installation_geometry.world_bounds_half_extents = computed_wall_bounds.get("half_extents", Vector3.ONE)
		bounds_volume_center = installation_geometry.world_bounds_center
		bounds_volume_half_extents = installation_geometry.world_bounds_half_extents
		bounds_mode = 2
		bounds_behavior = 0
		enable_wraparound = true

		if calibration_model == null:
			calibration_model = MeshCalibrationModel.new()
		calibration_model.physical_position = computed_node_offset
		calibration_model.physical_rotation_degrees = Vector3.ZERO
		calibration_model.node_id = mesh_node_id

	var camera_settings: Dictionary = installation_config.get_camera_settings()
	if camera_settings.has("feed_index"):
		webcam_feed_index = int(camera_settings.get("feed_index", webcam_feed_index))
	if camera_settings.has("prefer_csi_camera"):
		prefer_csi_camera = bool(camera_settings.get("prefer_csi_camera", prefer_csi_camera))
	if camera_settings.has("csi_camera_width"):
		csi_camera_width = int(camera_settings.get("csi_camera_width", csi_camera_width))
	if camera_settings.has("csi_camera_height"):
		csi_camera_height = int(camera_settings.get("csi_camera_height", csi_camera_height))
	if camera_settings.has("csi_camera_fps"):
		csi_camera_fps = int(camera_settings.get("csi_camera_fps", csi_camera_fps))
	if camera_settings.has("csi_camera_name"):
		csi_camera_name = String(camera_settings.get("csi_camera_name", csi_camera_name))
	if camera_settings.has("fit_mode"):
		webcam_fit_mode = int(camera_settings.get("fit_mode", webcam_fit_mode))
	if camera_settings.has("flip_horizontal"):
		flip_webcam_horizontal = bool(camera_settings.get("flip_horizontal", flip_webcam_horizontal))

func _configure_components() -> void:
	_input_controller.hide_mouse_cursor = hide_mouse_cursor

	_movement_controller.tumble_speed = tumble_speed
	_movement_controller.move_velocity = move_velocity
	_movement_controller.move_acceleration = move_acceleration
	if use_legacy_2d_velocity_adapter:
		_movement_controller.set_legacy_planar_velocity(legacy_move_velocity_2d)
	_movement_controller.enable_wraparound = enable_wraparound
	_movement_controller.wrap_margin = wrap_margin
	_movement_controller.bounds_mode = bounds_mode
	_movement_controller.bounds_behavior = bounds_behavior
	if installation_geometry != null:
		_movement_controller.bounds_volume_center = installation_geometry.world_bounds_center
		_movement_controller.bounds_volume_half_extents = installation_geometry.world_bounds_half_extents
	else:
		_movement_controller.bounds_volume_center = bounds_volume_center
		_movement_controller.bounds_volume_half_extents = bounds_volume_half_extents

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
	calibration_model = _mesh_sync_controller.configure(
		self,
		camera,
		get_viewport(),
		mesh_sync_enabled,
		mesh_node_id,
		mesh_peer_id,
		shared_object_id,
		calibration_model
	)
	if mesh_sync_enabled:
		_mesh_network_bridge = MeshNetworkBridgeScript.new()
		add_child(_mesh_network_bridge)
		var network_error: Error = _mesh_network_bridge.configure(
			_mesh_sync_controller.get_mesh_sync_service(),
			installation_config.get_network_settings(),
			installation_config.get_peers(),
			mesh_peer_id
		)
		if network_error != OK:
			print("[spinning_cube] Mesh network disabled after setup error: ", network_error)
			_mesh_network_bridge.queue_free()
			_mesh_network_bridge = null
		else:
			_mesh_sync_controller.attach_network_bridge(_mesh_network_bridge)
		_remote_object_renderer = RemoteObjectRendererScript.new()
		add_child(_remote_object_renderer)
		_remote_object_renderer.configure(
			_mesh_sync_controller.get_mesh_sync_service(),
			shared_object_id,
			camera
		)
