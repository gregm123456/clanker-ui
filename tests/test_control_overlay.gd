extends SceneTree

const Overlay = preload("res://scripts/control_overlay.gd")
const MainScene = preload("res://main.tscn")
const Launcher = preload("res://scripts/display_launcher.gd")

class InputProbe extends Node:
	var events: Array[InputEvent] = []

	func _unhandled_input(event: InputEvent) -> void:
		events.append(event)

class CubeStub extends Node:
	signal face_crops_received(faces, capture_order)

class FaceSink extends RefCounted:
	var calls := 0

	func add_faces(_faces: Array, _order: int) -> void:
		calls += 1

var failures := 0
var confirmations := 0

func _initialize() -> void:
	call_deferred("_run_tests")

func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		failures += 1

func _mouse(pressed: bool, position: Vector2, device: int = 0) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = position
	event.global_position = position
	event.device = device
	root.push_input(event)

func _touch(pressed: bool, position: Vector2, device: int = 0) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.pressed = pressed
	event.position = position
	event.device = device
	root.push_input(event)

func _escape() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	root.push_input(event)

func _click(control: Control) -> void:
	var pos := control.get_global_rect().get_center()
	_mouse(true, pos)
	_mouse(false, pos)

func _main_without_cube() -> Node:
	var scene := MainScene.instantiate()
	var cube := scene.get_node("SpinningCube")
	scene.remove_child(cube)
	cube.free()
	return scene

func _test_entry_paths() -> void:
	var direct := _main_without_cube()
	var cube := CubeStub.new()
	cube.name = "SpinningCube"
	direct.add_child(cube)
	root.add_child(direct)
	_check(direct.has_node("ControlOverlay"), "Direct main scene did not install its overlay")
	_check(direct.has_node("FaceSpeech"), "Direct main scene did not install speech")
	var speech = direct.get_node("FaceSpeech")
	_check(cube.face_crops_received.is_connected(speech.add_faces), "Direct scene did not connect speech to face crops")
	direct.get_node("ControlOverlay").speech_toggled.emit(true)
	_check(speech.enabled, "Direct scene toggle did not enable speech")
	direct.free()

	var output_launcher := Launcher.new()
	var face_sink := FaceSink.new()
	var speech_sink := FaceSink.new()
	output_launcher._face_overlay = face_sink
	output_launcher._face_speech = speech_sink
	var output_cube := CubeStub.new()
	output_launcher._connect_face_outputs(output_cube)
	output_cube.face_crops_received.emit([], 1)
	_check(face_sink.calls == 1 and speech_sink.calls == 1, "Launcher did not connect both face consumers")
	output_cube.free()
	output_launcher.free()

	var launcher := Node.new()
	root.add_child(launcher)
	Overlay.install(launcher)
	var single := _main_without_cube()
	launcher.add_child(single)
	_check(launcher.has_node("ControlOverlay") and not single.has_node("ControlOverlay"), "Single-display scene installed duplicate or missing overlays")
	single.free()

	var viewport := SubViewport.new()
	launcher.add_child(viewport)
	var combined := _main_without_cube()
	viewport.add_child(combined)
	_check(launcher.has_node("ControlOverlay") and not combined.has_node("ControlOverlay"), "Combined-wall scene installed duplicate or missing overlays")
	launcher.free()

func _run_tests() -> void:
	_test_entry_paths()
	root.size = Vector2i(1200, 800)
	root.content_scale_size = Vector2i(600, 400)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var probe := InputProbe.new()
	root.add_child(probe)
	var overlay = Overlay.new()
	overlay.quit_confirmed.connect(func(): confirmations += 1)
	root.add_child(overlay)
	await process_frame
	_check(not overlay._bar.visible, "Controls must start hidden")
	_check((root.get_screen_transform() * overlay.transform).is_equal_approx(Transform2D.IDENTITY), "Overlay is not aligned with physical pixels")
	_check(overlay._root.size == Vector2(root.size), "Overlay does not cover the physical window")
	overlay.panel_width = 320.0
	overlay._update_geometry()
	overlay._show_controls()
	await process_frame
	var narrow_button: Button = overlay._bar.get_child(0).get_node("SpeechButton")
	_check(narrow_button.get_global_rect().end.x <= 320.0, "Speech button crosses a narrow panel")
	overlay.panel_width = 560.0
	overlay._update_geometry()
	await process_frame
	_check(narrow_button.get_global_rect().end.x <= 560.0, "Speech button crosses a panel with title visible")
	overlay._hide_controls()
	overlay.panel_width = 600.0
	overlay._update_geometry()
	_check(overlay._bar.position.x == 0.0 and overlay._bar.size.x == 600.0, "Bar is not confined to the first panel")
	_check(overlay._dialog.position.x >= 0.0 and overlay._dialog.position.x + overlay._dialog.size.x <= 600.0, "Dialog crosses the physical panel boundary")
	var scaled_right := Vector2(900, 30)
	_touch(true, scaled_right)
	_touch(false, scaled_right)
	await process_frame
	_check(overlay._bar.position.x == 600.0 and overlay._bar.size.x == 600.0, "Scaled touch did not select the right physical panel")
	overlay._hide_controls()
	probe.events.clear()
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	await process_frame
	overlay._update_geometry()

	var point := Vector2(30, 30)
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	right_click.position = point
	root.push_input(right_click)
	_check(not overlay._bar.visible, "Right click unexpectedly revealed the controls")
	probe.events.clear()
	_touch(true, point)
	_mouse(true, point, InputEvent.DEVICE_ID_EMULATION)
	_check(overlay._bar.visible, "Touch press did not reveal the bar")
	_check(overlay._bar.position.x == 0.0, "Left touch did not select the left panel")
	_check(not overlay._dialog_backdrop.visible, "Reveal gesture activated a control")
	_touch(false, point)
	_mouse(false, point, InputEvent.DEVICE_ID_EMULATION)
	await process_frame
	_check(probe.events.is_empty(), "Reveal touch or emulated mouse event leaked into the scene")
	overlay._hide_controls()
	var right_point := Vector2(900, 30)
	_mouse(true, right_point)
	_touch(true, right_point, InputEvent.DEVICE_ID_EMULATION)
	_mouse(false, right_point)
	_touch(false, right_point, InputEvent.DEVICE_ID_EMULATION)
	await process_frame
	_check(overlay._bar.visible, "Mouse click did not reveal the bar")
	_check(overlay._bar.position.x == 600.0 and overlay._bar.size.x == 600.0, "Right mouse click did not select the right panel")
	_check(probe.events.is_empty(), "Reveal mouse or emulated touch event leaked into the scene")

	overlay._hide_controls()
	_escape()
	_check(overlay._bar.visible and overlay._dialog_backdrop.visible, "Escape did not request confirmation")
	_escape()
	_check(not overlay._bar.visible and not overlay._dialog_backdrop.visible, "Escape did not cancel and restore hidden state")
	_check(confirmations == 0, "Cancel unexpectedly quit")

	_mouse(true, right_point)
	_mouse(false, right_point)
	await process_frame
	var row: HBoxContainer = overlay._bar.get_child(0)
	var quit_button: Button = row.get_child(2)
	_click(quit_button)
	_check(overlay._dialog_backdrop.visible, "Quit button did not open confirmation")
	_check(overlay._dialog.position.x >= 600.0 and overlay._dialog.position.x + overlay._dialog.size.x <= 1200.0, "Confirmation is not on the selected panel")
	await process_frame
	var column: VBoxContainer = overlay._dialog.get_child(0)
	var actions: HBoxContainer = column.get_child(2)
	var cancel_button: Button = actions.get_child(0)
	var confirm_button: Button = actions.get_child(1)
	_click(cancel_button)
	_check(overlay._bar.visible and not overlay._dialog_backdrop.visible, "Cancel did not preserve visible bar")
	_click(quit_button)
	await process_frame
	_click(confirm_button)
	_check(confirmations == 1, "Confirm button did not emit exactly one quit request")
	overlay._cancel_quit()
	var hide_button: Button = row.get_child(1)
	var speech_button: Button = row.get_node("SpeechButton")
	var changes: Array = []
	overlay.speech_toggled.connect(func(value): changes.append(value))
	_check(not speech_button.button_pressed and speech_button.text == "SPEECH: OFF", "Speech must start off")
	_click(speech_button)
	_check(speech_button.button_pressed and speech_button.text == "SPEECH: ON" and changes == [true], "Speech toggle did not enable")
	_click(hide_button)
	_check(not overlay._bar.visible and not overlay._dialog_backdrop.visible, "Hide did not close the interface")
	overlay._show_controls()
	_check(speech_button.button_pressed and changes == [true], "Hiding controls changed speech state")
	_click(speech_button)
	_check(not speech_button.button_pressed and changes == [true, false], "Speech toggle did not disable")
	overlay.queue_free()
	probe.queue_free()
	await process_frame
	if failures == 0:
		print("Control overlay tests passed")
	quit(1 if failures else 0)
