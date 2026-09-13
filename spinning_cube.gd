extends MeshInstance3D

const SpinningCubeInputControllerScript = preload("res://scripts/spinning_cube_input_controller.gd")
const SpinningCubeMovementControllerScript = preload("res://scripts/spinning_cube_movement_controller.gd")
const WebcamCameraSourceAdapterScript = preload("res://scripts/webcam_camera_source_adapter.gd")

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

var camera: Camera3D

var _mat: ShaderMaterial
var _input_controller = SpinningCubeInputControllerScript.new()
var _movement_controller = SpinningCubeMovementControllerScript.new()
var _camera_source = WebcamCameraSourceAdapterScript.new()

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

	if enable_webcam:
		_camera_source.setup(_mat)

func _unhandled_input(event: InputEvent) -> void:
	_input_controller.handle_input(event, get_tree())

func _on_viewport_size_changed() -> void:
	camera = _movement_controller.handle_viewport_size_changed(self, camera, get_viewport())

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

func _exit_tree() -> void:
	_camera_source.shutdown()

func _process(delta: float) -> void:
	if enable_webcam:
		_camera_source.process(delta)
	camera = _movement_controller.process_transform(self, delta, camera, get_viewport())

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
