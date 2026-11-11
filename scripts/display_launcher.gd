extends Node

const InstallationConfigScript = preload("res://scripts/installation_config.gd")
const CombinedDisplayGeometryScript = preload("res://scripts/combined_display_geometry.gd")
const CalibrationOverlayScript = preload("res://scripts/display_calibration_overlay.gd")
const FacePortraitOverlayScript = preload("res://scripts/face_portrait_overlay.gd")
const ControlOverlayScript = preload("res://scripts/control_overlay.gd")
const FaceSpeechScript = preload("res://scripts/face_speech_coordinator.gd")
const MainScene = preload("res://main.tscn")

var _combined := false
var _window_rect := Rect2i()
var _scene_viewport: SubViewport
var _input_controller := SpinningCubeInputController.new()
var _display_settings: Dictionary
var _wall_layout: Dictionary
var _layout_check_elapsed := 0.0
var _restarting := false
var _original_scale_mode: Window.ContentScaleMode
var _face_overlay
var _control_overlay
var _face_speech

func _ready() -> void:
	_control_overlay = ControlOverlayScript.install(self)
	var config := InstallationConfigScript.new()
	_face_speech = FaceSpeechScript.install(self, _control_overlay, config.get_speech_settings())
	_face_overlay = FacePortraitOverlayScript.new()
	var max_portraits := int(config.get_face_settings()["max_portraits"])
	if max_portraits < 1:
		push_warning("[face] Invalid portrait limit; using 10")
		max_portraits = 10
	_face_overlay.max_portraits = max_portraits
	add_child(_face_overlay)
	var display: Dictionary = config.get_display_settings()
	if not bool(display["combined_wall"]) and not OS.get_cmdline_user_args().has("--combined-wall"):
		_add_main_scene(self)
		return

	var wall: Dictionary = config.get_wall_layout()
	_display_settings = display
	_wall_layout = wall
	var layout := _find_layout(display, wall)
	if layout.is_empty():
		_start_single_display("Two adjacent, equally sized screens were not found or the wall geometry is invalid")
		return

	_window_rect = layout["window"]
	print("[display] session=", OS.get_environment("XDG_SESSION_TYPE"), " backend=", DisplayServer.get_name(), " requested=", _window_rect, " gap_px=", layout["gap_pixels"])
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	await get_tree().create_timer(0.5).timeout
	# Resize the root viewport as well as the native window.
	get_window().size = _window_rect.size
	get_window().position = _window_rect.position
	await get_tree().create_timer(0.5).timeout
	var actual := Rect2i(DisplayServer.window_get_position(), DisplayServer.window_get_size())
	print("[display] actual window=", actual)
	if actual != _window_rect:
		_start_single_display("Window manager did not honor the requested spanning rectangle")
		return
	_original_scale_mode = get_window().content_scale_mode
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var viewport_size := get_viewport().get_visible_rect().size
	print("[display] root viewport=", viewport_size)
	if get_window().size != _window_rect.size or viewport_size != Vector2(_window_rect.size):
		get_window().content_scale_mode = _original_scale_mode
		_start_single_display("Root viewport did not resize to the spanning window")
		return
	_start_combined_display(layout)

func _find_layout(display: Dictionary, wall: Dictionary, log_screens: bool = true) -> Dictionary:
	var count := DisplayServer.get_screen_count()
	if int(wall["columns"]) != 2 or int(wall["rows"]) != 1:
		return {}
	var left := int(display["left_screen"])
	var right := int(display["right_screen"])
	if left == -1 and right == -1 and count == 2:
		left = 0
		right = 1
	if left < 0 or right < 0 or left == right or left >= count or right >= count:
		return {}
	var first := Rect2i(DisplayServer.screen_get_position(left), DisplayServer.screen_get_size(left))
	var second := Rect2i(DisplayServer.screen_get_position(right), DisplayServer.screen_get_size(right))
	if log_screens:
		print("[display] screen ", left, "=", first, "; screen ", right, "=", second)
	return CombinedDisplayGeometryScript.calculate(first, second, float(wall["monitor_width_mm"]), float(wall["gap_mm"]))

func _start_single_display(reason: String) -> void:
	push_warning("[display] " + reason + "; falling back to one screen")
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	_add_main_scene(self)

func _start_combined_display(layout: Dictionary) -> void:
	_combined = true
	_control_overlay.panel_width = float(layout["panel_size"].x)
	_scene_viewport = SubViewport.new()
	_scene_viewport.name = "CombinedWorld"
	_scene_viewport.size = layout["virtual_size"]
	_scene_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_scene_viewport)

	var scene := MainScene.instantiate()
	var cube := scene.get_node("SpinningCube")
	cube.start_fullscreen = false
	cube.combined_wall = true
	_connect_face_outputs(cube)
	_scene_viewport.add_child(scene)

	if OS.get_cmdline_user_args().has("--calibrate-display"):
		var overlay := CalibrationOverlayScript.new()
		overlay.image_size = layout["virtual_size"]
		_scene_viewport.add_child(overlay)

	var texture := _scene_viewport.get_texture()
	_add_panel(texture, layout["left_region"], Vector2i.ZERO)
	_add_panel(texture, layout["right_region"], Vector2i(layout["panel_size"].x, 0))
	_input_controller.apply_startup_state(false, cube.hide_mouse_cursor)
	if OS.get_cmdline_user_args().has("--calibrate-display"):
		await get_tree().process_frame
		print("[display] root visible=", get_viewport().get_visible_rect(), " window size=", get_window().size,
			" canvas=", get_viewport().get_canvas_transform(), " screen=", get_viewport().get_screen_transform(),
			" scene size=", _scene_viewport.size)
		for child in get_children():
			if child is TextureRect:
				print("[display] panel rect=", child.get_global_rect(), " region=", child.texture.region)

func _add_main_scene(parent: Node) -> void:
	var scene := MainScene.instantiate()
	_connect_face_outputs(scene.get_node("SpinningCube"))
	parent.add_child(scene)

func _connect_face_outputs(cube: Node) -> void:
	cube.face_crops_received.connect(_face_overlay.add_faces)
	cube.face_crops_received.connect(_face_speech.add_faces)

func _exit_tree() -> void:
	if _combined:
		get_window().content_scale_mode = _original_scale_mode

func _process(delta: float) -> void:
	if not _combined or _restarting:
		return
	_layout_check_elapsed += delta
	if _layout_check_elapsed < 2.0:
		return
	_layout_check_elapsed = 0.0
	var layout := _find_layout(_display_settings, _wall_layout, false)
	if layout.is_empty() or layout["window"] != _window_rect:
		_restarting = true
		push_warning("[display] Screen layout changed; restarting display setup")
		get_tree().call_deferred("reload_current_scene")

func _add_panel(texture: Texture2D, region: Rect2i, position: Vector2i) -> void:
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2(region)
	var panel := TextureRect.new()
	panel.texture = atlas
	panel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	panel.stretch_mode = TextureRect.STRETCH_SCALE
	panel.position = Vector2(position)
	panel.size = Vector2(region.size)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

func _unhandled_input(event: InputEvent) -> void:
	if not _combined:
		return
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		var key := event as InputEventKey
		if key.keycode == KEY_F11 or (key.keycode == KEY_ENTER and key.alt_pressed):
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			get_window().size = _window_rect.size
			get_window().position = _window_rect.position
			get_viewport().set_input_as_handled()
			return
	_input_controller.handle_input(event, get_tree())
