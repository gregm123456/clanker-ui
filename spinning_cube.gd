extends MeshInstance3D

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

@onready var camera: Camera3D = get_viewport().get_camera_3d()

var webcam_y_texture: CameraTexture
var webcam_cbcr_texture: CameraTexture
var current_feed: CameraFeed
var _feed_last_attempt: Dictionary = {}
var _mat: ShaderMaterial
var _feed_retry_timer: float = 0.0
var _last_webcam_aspect: float = -1.0
var _last_datatype: int = -1
var _csi_provider: CsiCameraProvider

func _ready() -> void:
	_randomize_speed_and_velocity()

	if start_fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

	if hide_mouse_cursor:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

	_setup_material()

	if camera == null:
		get_tree().process_frame.connect(_find_camera, CONNECT_ONE_SHOT)

	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_on_viewport_size_changed):
		vp.size_changed.connect(_on_viewport_size_changed)

	if enable_webcam:
		_setup_webcam()

## Applies an independent random 0.8-1.2 scale factor to each component of
## tumble_speed and move_velocity so each run/instance varies slightly.
func _randomize_speed_and_velocity() -> void:
	tumble_speed = Vector3(
		tumble_speed.x * randf_range(0.01, 1.0),
		tumble_speed.y * randf_range(0.01, 1.0),
		tumble_speed.z * randf_range(0.01, 2.0)
	)
	move_velocity = Vector2(
		move_velocity.x * randf_range(0.01, 4.0),
		move_velocity.y * randf_range(0.1, 1.5)
	)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		var k := event as InputEventKey
		if k.keycode == KEY_ESCAPE:
			get_tree().quit()
		elif k.keycode == KEY_F11 or (k.keycode == KEY_ENTER and k.alt_pressed):
			var current_mode := DisplayServer.window_get_mode()
			if current_mode == DisplayServer.WINDOW_MODE_FULLSCREEN or current_mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
				if hide_mouse_cursor:
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			else:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
				if hide_mouse_cursor:
					Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		elif k.keycode == KEY_M:
			if Input.mouse_mode == Input.MOUSE_MODE_HIDDEN:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			else:
				Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

func _on_viewport_size_changed() -> void:
	if enable_wraparound:
		_handle_screen_wraparound()

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

func _setup_webcam() -> void:
	if prefer_csi_camera and _setup_csi_camera():
		return

	CameraServer.set_monitoring_feeds(true)
	if not CameraServer.camera_feed_added.is_connected(_on_camera_feed_event):
		CameraServer.camera_feed_added.connect(_on_camera_feed_event)
	if not CameraServer.camera_feeds_updated.is_connected(_on_camera_feed_event):
		CameraServer.camera_feeds_updated.connect(_on_camera_feed_event)
	_activate_feed()

func _setup_csi_camera() -> bool:
	_csi_provider = CsiCameraProvider.new()
	if not _csi_provider.start(csi_camera_width, csi_camera_height, csi_camera_fps, csi_camera_name):
		print("[webcam] CSI provider unavailable: ", _csi_provider.get_last_error())
		_csi_provider = null
		return false

	print("[webcam] using CSI camera provider at ", csi_camera_width, "x", csi_camera_height, " @ ", csi_camera_fps, " fps")
	return true

func _update_csi_camera() -> void:
	if _csi_provider == null or _mat == null:
		return
	if _csi_provider.update():
		_mat.set_shader_parameter("webcam_texture", _csi_provider.get_texture())
		_mat.set_shader_parameter("webcam_mode", 1)
		_mat.set_shader_parameter("webcam_aspect", _csi_provider.get_aspect())

func _exit_tree() -> void:
	if _csi_provider != null:
		_csi_provider.stop()
		_csi_provider = null

func _on_camera_feed_event(_arg = null) -> void:
	if current_feed == null or not current_feed.is_active():
		_activate_feed()

func _select_feed_format(feed: CameraFeed) -> void:
	# V4L2 (Linux / Raspberry Pi) requires an explicit format before activation,
	# unlike macOS/iOS which auto-select one. Index 0 can be an oversized or
	# exotic pixel format that hangs or corrupts decoding, so pick the smallest
	# advertised resolution instead, which is the safest/fastest to negotiate.
	var formats := feed.get_formats()
	if formats.is_empty():
		return
	var best_index := 0
	var best_pixels := -1
	for i in formats.size():
		var fmt: Dictionary = formats[i]
		var w := int(fmt.get("width", 0))
		var h := int(fmt.get("height", 0))
		var pixels := w * h
		if pixels > 0 and (best_pixels < 0 or pixels < best_pixels):
			best_pixels = pixels
			best_index = i
	print("[webcam] feed '", feed.get_name(), "' (id=", feed.get_id(), ") selecting format[", best_index, "] = ", formats[best_index])
	feed.set_format(best_index, {})

func _activate_feed() -> void:
	var feeds := CameraServer.feeds()
	if feeds.is_empty():
		return

	var now := Time.get_ticks_msec()
	var candidates: Array = []
	if prefer_csi_camera:
		for f in feeds:
			if _is_csi_feed(f):
				candidates.append(f)
	if webcam_feed_index >= 0 and webcam_feed_index < feeds.size():
		if not candidates.has(feeds[webcam_feed_index]):
			candidates.append(feeds[webcam_feed_index])
	for f in feeds:
		if f != null and not candidates.has(f):
			candidates.append(f)

	var target_feed: CameraFeed = null
	for f in candidates:
		if f == null:
			continue
		if f.is_active():
			target_feed = f
			break
		# Skip feeds that failed recently to avoid hammering the device with
		# repeated set_format/set_active calls every retry tick.
		var fid: int = f.get_id()
		var last: int = _feed_last_attempt.get(fid, -100000)
		if now - last < 3000:
			continue
		_feed_last_attempt[fid] = now
		_select_feed_format(f)
		f.set_active(true)
		if f.is_active():
			target_feed = f
			break
		else:
			f.set_active(false)

	if target_feed == null:
		return

	current_feed = target_feed

	if not current_feed.format_changed.is_connected(_update_feed_mode):
		current_feed.format_changed.connect(_update_feed_mode)

	# Setup Y / Luminance / Primary Texture
	if webcam_y_texture == null:
		webcam_y_texture = CameraTexture.new()
	webcam_y_texture.camera_feed_id = current_feed.get_id()
	webcam_y_texture.which_feed = CameraServer.FEED_Y_IMAGE
	webcam_y_texture.camera_is_active = true

	# Setup CbCr / Chroma Texture (for macOS / iOS YCbCr Bi-Planar)
	if webcam_cbcr_texture == null:
		webcam_cbcr_texture = CameraTexture.new()
	webcam_cbcr_texture.camera_feed_id = current_feed.get_id()
	webcam_cbcr_texture.which_feed = CameraServer.FEED_CBCR_IMAGE
	webcam_cbcr_texture.camera_is_active = true

	if _mat != null:
		_mat.set_shader_parameter("webcam_texture", webcam_y_texture)
		_mat.set_shader_parameter("webcam_cbcr_texture", webcam_cbcr_texture)
		_mat.set_shader_parameter("webcam_flip_h", flip_webcam_horizontal)
		_mat.set_shader_parameter("webcam_fit_mode", webcam_fit_mode)
		_update_feed_mode()

func _is_csi_feed(feed: CameraFeed) -> bool:
		if feed == null:
			return false
		var name := feed.get_name().to_lower()
		for keyword in ["csi", "libcamera", "rpicam", "unicam"]:
			if name.contains(keyword):
				return true
		return false

func _update_feed_mode() -> void:
	if current_feed == null or _mat == null:
		return
	var datatype := current_feed.get_datatype()
	_last_datatype = datatype

	var is_ycbcr := (datatype == CameraFeed.FEED_YCBCR_SEP or datatype == CameraFeed.FEED_YCBCR)
	if is_ycbcr:
		_mat.set_shader_parameter("webcam_mode", 2) # YCbCr 4:2:0 Bi-Planar
	elif datatype == CameraFeed.FEED_RGB:
		_mat.set_shader_parameter("webcam_mode", 1) # Standard RGB
	else:
		# Fallback: on macOS/iOS default is YCbCr bi-planar; on Linux (V4L2) default is RGB
		if OS.get_name() in ["macOS", "iOS"]:
			_mat.set_shader_parameter("webcam_mode", 2)
		else:
			_mat.set_shader_parameter("webcam_mode", 1)

func _process(delta: float) -> void:
	# Retry activating webcam or updating mode if format changed
	if _csi_provider != null:
		_update_csi_camera()

	if enable_webcam and _csi_provider == null:
		if current_feed == null or not current_feed.is_active():
			_feed_retry_timer += delta
			if _feed_retry_timer >= 0.5:
				_feed_retry_timer = 0.0
				_activate_feed()
		elif current_feed != null and current_feed.get_datatype() != _last_datatype:
			_update_feed_mode()

	# Dynamically update camera aspect ratio whenever USB webcam texture size changes
	if webcam_y_texture != null and _mat != null:
		var tw := float(webcam_y_texture.get_width())
		var th := float(webcam_y_texture.get_height())
		if tw > 0.0 and th > 0.0:
			var aspect := tw / th
			if absf(aspect - _last_webcam_aspect) > 0.001:
				_last_webcam_aspect = aspect
				_mat.set_shader_parameter("webcam_aspect", aspect)

	# 1. Continuous tumbling / spinning rotation
	rotate_x(tumble_speed.x * delta)
	rotate_y(tumble_speed.y * delta)
	rotate_z(tumble_speed.z * delta)

	# 2. Movement across the screen
	position.x += move_velocity.x * delta
	position.y += move_velocity.y * delta

	# 3. Screen wraparound
	if enable_wraparound:
		_handle_screen_wraparound()

func _handle_screen_wraparound() -> void:
	if camera == null:
		camera = get_viewport().get_camera_3d()
		if camera == null:
			return

	var vp := get_viewport()
	var vp_size := vp.get_visible_rect().size
	if vp_size.y <= 0:
		return

	var aspect := vp_size.x / vp_size.y
	var cam_pos := camera.global_position
	var z_dist := absf(cam_pos.z - global_position.z)

	var half_h: float
	var half_w: float
	if camera.projection == Camera3D.PROJECTION_PERSPECTIVE:
		var fov_rad := deg_to_rad(camera.fov)
		if camera.keep_aspect == Camera3D.KEEP_WIDTH:
			half_w = tan(fov_rad * 0.5) * z_dist
			half_h = half_w / aspect
		else:
			half_h = tan(fov_rad * 0.5) * z_dist
			half_w = half_h * aspect
	else:
		if camera.keep_aspect == Camera3D.KEEP_WIDTH:
			half_w = camera.size * 0.5
			half_h = half_w / aspect
		else:
			half_h = camera.size * 0.5
			half_w = half_h * aspect

	var bound_x := half_w + wrap_margin
	var bound_y := half_h + wrap_margin

	# Horizontal wraparound
	var rel_x := global_position.x - cam_pos.x
	if rel_x > bound_x:
		global_position.x = cam_pos.x - bound_x
	elif rel_x < -bound_x:
		global_position.x = cam_pos.x + bound_x

	# Vertical wraparound
	var rel_y := global_position.y - cam_pos.y
	if rel_y > bound_y:
		global_position.y = cam_pos.y - bound_y
	elif rel_y < -bound_y:
		global_position.y = cam_pos.y + bound_y
