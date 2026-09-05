class_name CsiCameraProvider
extends RefCounted

const DEFAULT_WIDTH := 960
const DEFAULT_HEIGHT := 540
const DEFAULT_FPS := 30

var _camera: Object
var _texture: ImageTexture
var _frame_number: int = 0
var _width: int = 0
var _height: int = 0
var _last_error := ""

func is_available() -> bool:
	return OS.get_name() == "Linux" and ClassDB.class_exists("CsiCamera")

func start(width: int = DEFAULT_WIDTH, height: int = DEFAULT_HEIGHT, fps: int = DEFAULT_FPS, camera_name: String = "") -> bool:
	stop()
	if not is_available():
		_last_error = "CsiCamera GDExtension is unavailable"
		return false

	_camera = ClassDB.instantiate("CsiCamera")
	if _camera == null or not bool(_camera.call("start", width, height, fps, camera_name)):
		_last_error = _camera.call("get_last_error") if _camera != null else "Could not instantiate CsiCamera"
		_camera = null
		return false

	_last_error = ""
	return true

func stop() -> void:
	if _camera != null:
		_camera.call("stop")
	_camera = null

func update() -> bool:
	if _camera == null or not bool(_camera.call("is_running")):
		return false
	if not bool(_camera.call("poll")):
		return false

	var width := int(_camera.call("get_frame_width"))
	var height := int(_camera.call("get_frame_height"))
	var bytes: PackedByteArray = _camera.call("get_frame")
	if width <= 0 or height <= 0 or bytes.is_empty():
		_last_error = "CsiCamera returned an invalid frame"
		return false

	var image := Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, bytes)
	if image == null:
		_last_error = "Could not create a Godot image from CSI frame"
		return false

	if _texture == null or _width != width or _height != height:
		_texture = ImageTexture.create_from_image(image)
	else:
		_texture.update(image)
	_width = width
	_height = height
	_frame_number = int(_camera.call("get_frame_number"))
	if _frame_number == 1:
		print("[csi_camera] first frame received: ", width, "x", height, " bytes=", bytes.size(), " pixel0=", bytes[0], ",", bytes[1], ",", bytes[2], ",", bytes[3])
	_last_error = ""
	return true

func is_active() -> bool:
	return _camera != null and bool(_camera.call("is_running"))

func get_texture() -> Texture2D:
	return _texture

func get_aspect() -> float:
	return float(_width) / float(_height) if _height > 0 else 0.0

func get_frame_number() -> int:
	return _frame_number

func get_last_error() -> String:
	if _last_error.is_empty() and _camera != null:
		return str(_camera.call("get_last_error"))
	return _last_error