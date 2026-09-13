class_name WebcamCameraSourceAdapter
extends "res://scripts/camera_source_adapter.gd"

const CsiCameraProviderScript = preload("res://addons/csi_camera/scripts/csi_camera_provider.gd")

var webcam_feed_index: int = 0
var prefer_csi_camera: bool = true
var csi_camera_width: int = 960
var csi_camera_height: int = 540
var csi_camera_fps: int = 30
var csi_camera_name: String = ""
var webcam_fit_mode: int = 0
var flip_webcam_horizontal: bool = true

var webcam_y_texture: CameraTexture
var webcam_cbcr_texture: CameraTexture
var current_feed: CameraFeed
var _feed_last_attempt: Dictionary = {}
var _pending_deactivation_feed_ids: Dictionary = {}
var _current_feed_owned: bool = false
var _deactivation_generation: int = 0
var _feed_retry_timer: float = 0.0
var _last_webcam_aspect: float = -1.0
var _last_datatype: int = -1
var _material: ShaderMaterial
var _csi_provider: CsiCameraProvider

func setup(material: ShaderMaterial) -> void:
	shutdown()
	_material = material
	_reset_material_webcam_state()
	if prefer_csi_camera and _setup_csi_camera():
		return

	CameraServer.set_monitoring_feeds(true)
	if not CameraServer.camera_feed_added.is_connected(_on_camera_feed_event):
		CameraServer.camera_feed_added.connect(_on_camera_feed_event)
	if not CameraServer.camera_feeds_updated.is_connected(_on_camera_feed_event):
		CameraServer.camera_feeds_updated.connect(_on_camera_feed_event)
	_activate_feed()

func process(delta: float) -> void:
	if _csi_provider != null:
		_update_csi_camera()

	if _csi_provider == null:
		if current_feed == null or not current_feed.is_active():
			_feed_retry_timer += delta
			if _feed_retry_timer >= 0.5:
				_feed_retry_timer = 0.0
				_activate_feed()
		elif current_feed.get_datatype() != _last_datatype:
			_update_feed_mode()

	if _csi_provider == null and webcam_y_texture != null and _material != null:
		var tw := float(webcam_y_texture.get_width())
		var th := float(webcam_y_texture.get_height())
		if tw > 0.0 and th > 0.0:
			var aspect := tw / th
			if absf(aspect - _last_webcam_aspect) > 0.001:
				_last_webcam_aspect = aspect
				_material.set_shader_parameter("webcam_aspect", aspect)

func shutdown() -> void:
	_deactivation_generation += 1
	if CameraServer.camera_feed_added.is_connected(_on_camera_feed_event):
		CameraServer.camera_feed_added.disconnect(_on_camera_feed_event)
	if CameraServer.camera_feeds_updated.is_connected(_on_camera_feed_event):
		CameraServer.camera_feeds_updated.disconnect(_on_camera_feed_event)
	if current_feed != null and current_feed.format_changed.is_connected(_update_feed_mode):
		current_feed.format_changed.disconnect(_update_feed_mode)
	if current_feed != null:
		if _current_feed_owned:
			current_feed.set_active(false)
		current_feed = null
	_current_feed_owned = false
	if _csi_provider != null:
		_csi_provider.stop()
		_csi_provider = null
	if _material != null:
		_reset_material_webcam_state()
	webcam_y_texture = null
	webcam_cbcr_texture = null
	_material = null
	_feed_last_attempt.clear()
	_pending_deactivation_feed_ids.clear()
	_feed_retry_timer = 0.0
	_last_webcam_aspect = -1.0
	_last_datatype = -1

func _setup_csi_camera() -> bool:
	_csi_provider = CsiCameraProviderScript.new()
	if not _csi_provider.start(csi_camera_width, csi_camera_height, csi_camera_fps, csi_camera_name):
		_csi_provider.stop()
		print("[webcam] CSI provider unavailable: ", _csi_provider.get_last_error())
		_csi_provider = null
		return false

	if _material != null:
		_material.set_shader_parameter("webcam_texture", _csi_provider.get_texture())
		_material.set_shader_parameter("webcam_cbcr_texture", null)
		_material.set_shader_parameter("webcam_mode", 1)
		if csi_camera_height > 0:
			_material.set_shader_parameter("webcam_aspect", float(csi_camera_width) / float(csi_camera_height))
	print("[webcam] using CSI camera provider at ", csi_camera_width, "x", csi_camera_height, " @ ", csi_camera_fps, " fps")
	return true

func _update_csi_camera() -> void:
	if _csi_provider == null or _material == null:
		return
	if _csi_provider.update():
		_material.set_shader_parameter("webcam_texture", _csi_provider.get_texture())
		_material.set_shader_parameter("webcam_mode", 1)
		_material.set_shader_parameter("webcam_aspect", _csi_provider.get_aspect())

func _on_camera_feed_event(_arg = null) -> void:
	if current_feed == null or not current_feed.is_active():
		_activate_feed()

func _select_feed_format(feed: CameraFeed) -> void:
	var formats := feed.get_formats()
	if formats.is_empty():
		return
	var best_index := 0
	var best_pixels := -1
	for i in formats.size():
		var fmt: Dictionary = formats[i]
		var width := int(fmt.get("width", 0))
		var height := int(fmt.get("height", 0))
		var pixels := width * height
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
		for feed in feeds:
			if _is_csi_feed(feed):
				candidates.append(feed)
	if webcam_feed_index >= 0 and webcam_feed_index < feeds.size():
		if not candidates.has(feeds[webcam_feed_index]):
			candidates.append(feeds[webcam_feed_index])
	for feed in feeds:
		if feed != null and not candidates.has(feed):
			candidates.append(feed)

	var target_feed: CameraFeed = null
	var target_feed_owned := false
	for feed in candidates:
		if feed == null:
			continue
		var feed_id := feed.get_id()
		if _pending_deactivation_feed_ids.get(feed_id, false):
			continue
		if feed.is_active():
			target_feed = feed
			target_feed_owned = (feed == current_feed and _current_feed_owned)
			break
		var last_attempt: int = _feed_last_attempt.get(feed_id, -100000)
		if now - last_attempt < 3000:
			continue
		_feed_last_attempt[feed_id] = now
		_select_feed_format(feed)
		feed.set_active(true)
		if feed.is_active():
			target_feed = feed
			target_feed_owned = true
			break

	if target_feed == null:
		return

	var previous_feed := current_feed
	var previous_feed_owned := _current_feed_owned
	if current_feed != null and current_feed != target_feed:
		if current_feed.format_changed.is_connected(_update_feed_mode):
			current_feed.format_changed.disconnect(_update_feed_mode)

	current_feed = target_feed
	_current_feed_owned = target_feed_owned
	if not current_feed.format_changed.is_connected(_update_feed_mode):
		current_feed.format_changed.connect(_update_feed_mode)

	if webcam_y_texture == null:
		webcam_y_texture = CameraTexture.new()
	webcam_y_texture.camera_feed_id = current_feed.get_id()
	webcam_y_texture.which_feed = CameraServer.FEED_Y_IMAGE
	webcam_y_texture.camera_is_active = true

	if webcam_cbcr_texture == null:
		webcam_cbcr_texture = CameraTexture.new()
	webcam_cbcr_texture.camera_feed_id = current_feed.get_id()
	webcam_cbcr_texture.which_feed = CameraServer.FEED_CBCR_IMAGE
	webcam_cbcr_texture.camera_is_active = true

	if _material != null:
		_material.set_shader_parameter("webcam_texture", webcam_y_texture)
		_material.set_shader_parameter("webcam_cbcr_texture", webcam_cbcr_texture)
		_material.set_shader_parameter("webcam_flip_h", flip_webcam_horizontal)
		_material.set_shader_parameter("webcam_fit_mode", webcam_fit_mode)
		_update_feed_mode()

	if previous_feed != null and previous_feed != current_feed and previous_feed_owned:
		_schedule_feed_deactivation(previous_feed)

func _is_csi_feed(feed: CameraFeed) -> bool:
	if feed == null:
		return false
	var name := feed.get_name().to_lower()
	for keyword in ["csi", "libcamera", "rpicam", "unicam"]:
		if name.contains(keyword):
			return true
	return false

func _update_feed_mode() -> void:
	if current_feed == null or _material == null:
		return
	var datatype := current_feed.get_datatype()
	_last_datatype = datatype

	var is_ycbcr := datatype == CameraFeed.FEED_YCBCR_SEP or datatype == CameraFeed.FEED_YCBCR
	if is_ycbcr:
		_material.set_shader_parameter("webcam_mode", 2)
	elif datatype == CameraFeed.FEED_RGB:
		_material.set_shader_parameter("webcam_mode", 1)
	else:
		if OS.get_name() in ["macOS", "iOS"]:
			_material.set_shader_parameter("webcam_mode", 2)
		else:
			_material.set_shader_parameter("webcam_mode", 1)

func _reset_material_webcam_state() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("webcam_texture", null)
	_material.set_shader_parameter("webcam_cbcr_texture", null)
	_material.set_shader_parameter("webcam_mode", 0)
	_material.set_shader_parameter("webcam_aspect", 1.777778)

func _schedule_feed_deactivation(feed: CameraFeed) -> void:
	if feed == null:
		return
	_pending_deactivation_feed_ids[feed.get_id()] = _deactivation_generation
	call_deferred("_finish_feed_deactivation", feed, _deactivation_generation)

func _finish_feed_deactivation(feed: CameraFeed, generation: int) -> void:
	if feed == null:
		return
	var feed_id := feed.get_id()
	if _pending_deactivation_feed_ids.get(feed_id, -1) != generation:
		return
	feed.set_active(false)
	_pending_deactivation_feed_ids.erase(feed_id)
