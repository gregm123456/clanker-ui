class_name SpinningCubeInputController
extends RefCounted

var hide_mouse_cursor: bool = true
var _preferred_fullscreen_mode: int = DisplayServer.WINDOW_MODE_FULLSCREEN

func apply_startup_state(start_fullscreen: bool, should_hide_mouse_cursor: bool) -> void:
	hide_mouse_cursor = should_hide_mouse_cursor

	if start_fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

	if hide_mouse_cursor:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

func handle_input(event: InputEvent, tree: SceneTree) -> void:
	if not (event is InputEventKey and event.is_pressed() and not event.is_echo()):
		return

	var key_event := event as InputEventKey
	if key_event.keycode == KEY_ESCAPE:
		tree.quit()
	elif key_event.keycode == KEY_F11 or (key_event.keycode == KEY_ENTER and key_event.alt_pressed):
		_toggle_fullscreen()
	elif key_event.keycode == KEY_M:
		_toggle_mouse_mode()

func _toggle_fullscreen() -> void:
	var current_mode := DisplayServer.window_get_mode()
	if current_mode == DisplayServer.WINDOW_MODE_FULLSCREEN or current_mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		_preferred_fullscreen_mode = current_mode
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		if hide_mouse_cursor:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		DisplayServer.window_set_mode(_preferred_fullscreen_mode)
		if hide_mouse_cursor:
			Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

func _toggle_mouse_mode() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_HIDDEN:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
