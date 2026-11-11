extends CanvasLayer

signal quit_confirmed
signal speech_toggled(enabled: bool)

const CYAN := Color(0.35, 0.9, 1.0)
const TEXT := Color(0.84, 0.96, 1.0)

var panel_width := 0.0
var _root: Control
var _bar: PanelContainer
var _row: HBoxContainer
var _dialog_backdrop: Control
var _dialog: PanelContainer
var _title: Label
var _speech_button: Button
var _hide_button: Button
var _quit_button: Button
var _compact := false
var _was_visible_before_dialog := false
var _previous_mouse_mode: Input.MouseMode
var _reveal_kind := ""
var _reveal_touch_index := -1
var _active_panel := 0

static func install(parent: Node) -> CanvasLayer:
	var overlay := preload("res://scripts/control_overlay.gd").new()
	overlay.name = "ControlOverlay"
	overlay.quit_confirmed.connect(parent.get_tree().quit)
	parent.add_child(overlay)
	return overlay

func _ready() -> void:
	layer = 20
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_bar = PanelContainer.new()
	_bar.name = "ControlBar"
	_bar.add_theme_stylebox_override("panel", _panel_style(Color(0.02, 0.06, 0.1, 0.94), CYAN))
	_root.add_child(_bar)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 12)
	_bar.add_child(_row)
	_title = Label.new()
	_title.text = "◈  CLANKER // CONTROL"
	_title.add_theme_color_override("font_color", CYAN)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row.add_child(_title)
	_hide_button = _make_button("HIDE", _hide_controls)
	_row.add_child(_hide_button)
	_quit_button = _make_button("QUIT", _request_quit)
	_row.add_child(_quit_button)
	_speech_button = _make_button("SPEECH: OFF", _toggle_speech)
	_speech_button.name = "SpeechButton"
	_speech_button.toggle_mode = true
	_row.add_child(_speech_button)
	_bar.hide()

	_dialog_backdrop = Control.new()
	_dialog_backdrop.name = "Confirmation"
	_dialog_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_dialog_backdrop)
	_dialog = PanelContainer.new()
	_dialog.add_theme_stylebox_override("panel", _panel_style(Color(0.02, 0.06, 0.1, 0.98), CYAN))
	_dialog_backdrop.add_child(_dialog)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	_dialog.add_child(column)
	var heading := Label.new()
	heading.text = "SYSTEM // SHUTDOWN"
	heading.add_theme_color_override("font_color", CYAN)
	column.add_child(heading)
	var message := Label.new()
	message.text = "Quit clankerUI?"
	message.add_theme_color_override("font_color", TEXT)
	column.add_child(message)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	column.add_child(actions)
	var cancel_button := _make_button("CANCEL", _cancel_quit)
	cancel_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(cancel_button)
	var confirm_button := _make_button("CONFIRM QUIT", _confirm_quit)
	confirm_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(confirm_button)
	_dialog_backdrop.hide()
	_update_geometry()

func _panel_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_content_margin_all(12.0)
	return style

func _make_button(label: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(92, 48)
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_stylebox_override("normal", _panel_style(Color(0.04, 0.13, 0.18), CYAN))
	button.add_theme_stylebox_override("hover", _panel_style(Color(0.08, 0.25, 0.3), CYAN))
	button.add_theme_stylebox_override("pressed", _panel_style(Color(0.12, 0.36, 0.42), CYAN))
	button.pressed.connect(action)
	return button

func _toggle_speech() -> void:
	_speech_button.text = "SPEECH: ON" if _speech_button.button_pressed else "SPEECH: OFF"
	speech_toggled.emit(_speech_button.button_pressed)

func _process(_delta: float) -> void:
	_update_geometry()

func _update_geometry() -> void:
	var viewport := get_viewport()
	if viewport == null or _root == null:
		return
	var screen_transform := viewport.get_screen_transform()
	if is_zero_approx(screen_transform.determinant()):
		push_warning("[controls] Invalid display transform")
		return
	transform = screen_transform.affine_inverse()
	var size := Vector2((viewport as Window).size) if viewport is Window else viewport.get_visible_rect().size
	_root.size = size
	var panel_left := 0.0
	var available_width := size.x
	if panel_width > 0.0:
		_active_panel = clampi(_active_panel, 0, maxi(ceili(size.x / panel_width) - 1, 0))
		panel_left = float(_active_panel) * panel_width
		available_width = minf(panel_width, maxf(0.0, size.x - panel_left))
	var compact := available_width < 400.0
	if compact != _compact:
		_compact = compact
		_row.add_theme_constant_override("separation", 8 if compact else 12)
		for button in [_hide_button, _quit_button, _speech_button]:
			button.custom_minimum_size.x = 64 if compact else 92
			button.add_theme_font_size_override("font_size", 14 if compact else 16)
	_bar.position = Vector2(panel_left, 0.0)
	_bar.size = Vector2(available_width, 72)
	_title.visible = available_width >= 560.0
	_dialog_backdrop.size = size
	var dialog_size := Vector2(minf(380.0, available_width), 180.0)
	_dialog.size = dialog_size
	_dialog.position = Vector2(panel_left + (available_width - dialog_size.x) * 0.5, maxf(0.0, (size.y - dialog_size.y) * 0.5))

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if _dialog_backdrop.visible:
			_cancel_quit()
		else:
			_request_quit()
		get_viewport().set_input_as_handled()
		return
	if _reveal_kind != "":
		if _is_reveal_gesture_event(event):
			get_viewport().set_input_as_handled()
			if _is_reveal_release(event):
				call_deferred("_finish_reveal_gesture")
			return
	if _bar.visible or _dialog_backdrop.visible:
		return
	var position := Vector2.ZERO
	if event is InputEventScreenTouch and event.pressed:
		_reveal_kind = "touch"
		_reveal_touch_index = event.index
		position = event.position
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_reveal_kind = "mouse"
		position = event.position
	else:
		return
	if panel_width > 0.0:
		var physical_position := get_viewport().get_screen_transform() * position
		_active_panel = maxi(0, floori(physical_position.x / panel_width))
	_update_geometry()
	_show_controls()
	get_viewport().set_input_as_handled()

func _is_reveal_gesture_event(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		return true
	if event is InputEventScreenTouch:
		return true
	return false

func _is_reveal_release(event: InputEvent) -> bool:
	if _reveal_kind == "touch" and event is InputEventScreenTouch:
		return event.index == _reveal_touch_index and not event.pressed
	if _reveal_kind == "mouse" and event is InputEventMouseButton:
		return event.button_index == MOUSE_BUTTON_LEFT and not event.pressed
	return false

func _finish_reveal_gesture() -> void:
	_reveal_kind = ""
	_reveal_touch_index = -1

func _show_controls() -> void:
	if not _bar.visible:
		_previous_mouse_mode = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_bar.show()

func _hide_controls() -> void:
	_dialog_backdrop.hide()
	_bar.hide()
	if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = _previous_mouse_mode

func _request_quit() -> void:
	if _dialog_backdrop.visible:
		return
	_was_visible_before_dialog = _bar.visible
	_show_controls()
	_dialog_backdrop.show()
	_update_geometry()

func _cancel_quit() -> void:
	_dialog_backdrop.hide()
	if not _was_visible_before_dialog:
		_hide_controls()

func _confirm_quit() -> void:
	quit_confirmed.emit()
