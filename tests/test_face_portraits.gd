extends SceneTree

const Movement = preload("res://scripts/spinning_cube_movement_controller.gd")
const Schema = preload("res://scripts/transform_sync_schema.gd")
const Renderer = preload("res://scripts/remote_object_renderer.gd")
const MeshSyncService = preload("res://scripts/mesh_sync_service.gd")
const MeshSyncController = preload("res://scripts/spinning_cube_mesh_sync_controller.gd")
const FaceClient = preload("res://scripts/face_attribute_client.gd")
const Overlay = preload("res://scripts/face_portrait_overlay.gd")
const Cube = preload("res://spinning_cube.gd")

class SnapshotStub extends RefCounted:
	var calls := 0

	func request_snapshot(_object_id: String, _owner: String) -> Error:
		calls += 1
		return OK

class FaceStub extends RefCounted:
	var orders: Array = []

	func submit(_jpeg: PackedByteArray, order: int) -> Error:
		orders.append(order)
		return OK

var failures := 0

func _initialize() -> void:
	call_deferred("_run_tests")

func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		failures += 1

func _run_tests() -> void:
	_test_cycles()
	_test_remote_markers()
	_test_mesh_cycle_flow()
	_test_face_parsing()
	_test_face_errors()
	_test_remote_snapshot_freshness()
	await _test_overlay()
	if failures == 0:
		print("Face portrait tests passed")
	quit(1 if failures else 0)

func _test_cycles() -> void:
	var target := Node3D.new()
	root.add_child(target)
	var movement = Movement.new()
	movement.floating_portrait = true
	movement.enable_wraparound = false
	movement.initialize_portrait(target)
	movement._portrait_hold_seconds = 5.0
	var sequences: Array = []
	movement.portrait_reentered.connect(func(sequence): sequences.append(sequence))
	movement.process_transform(target, 6.49, null, null)
	_check(sequences.is_empty(), "Cycle fired before the end of retreat")
	movement.process_transform(target, 0.02, null, null)
	_check(sequences == [1], "Cycle did not fire at re-entry")
	movement.process_transform(target, 30.0, null, null)
	_check(sequences.size() == 2 and int(sequences.back()) >= 3 and sequences.back() == movement.portrait_cycle_sequence, "Large delta did not coalesce missed cycles")
	target.queue_free()

func _test_remote_markers() -> void:
	var schema = Schema.new()
	var legacy: Dictionary = schema.serialize_transform("remote", "peer", Transform3D.IDENTITY)
	_check(not schema.deserialize_transform(legacy).has("portrait_cycle"), "Legacy transform gained a cycle marker")
	var renderer = Renderer.new()
	root.add_child(renderer)
	var events: Array = []
	renderer.portrait_cycle_observed.connect(func(object_id, owner): events.append([object_id, owner]))
	var transform := legacy.duplicate()
	transform["portrait_incarnation"] = "run-a"
	transform["portrait_cycle"] = 2
	var parsed: Dictionary = schema.deserialize_transform(transform)
	_check(parsed.get("portrait_cycle") == 2, "Cycle marker was not deserialized")
	renderer._observe_portrait_cycle("remote", "peer", parsed)
	_check(events.is_empty(), "First remote marker incorrectly triggered a cycle")
	transform["portrait_cycle"] = 3
	renderer._observe_portrait_cycle("remote", "peer", schema.deserialize_transform(transform))
	renderer._observe_portrait_cycle("remote", "peer", schema.deserialize_transform(transform))
	transform["portrait_cycle"] = 2
	renderer._observe_portrait_cycle("remote", "peer", schema.deserialize_transform(transform))
	_check(events == [["remote", "peer"]], "Duplicate or reordered marker triggered a cycle")
	transform["portrait_incarnation"] = "run-b"
	transform["portrait_cycle"] = 0
	renderer._observe_portrait_cycle("remote", "peer", schema.deserialize_transform(transform))
	transform["portrait_incarnation"] = "run-a"
	transform["portrait_cycle"] = 4
	renderer._observe_portrait_cycle("remote", "peer", schema.deserialize_transform(transform))
	transform["portrait_incarnation"] = "run-b"
	transform["portrait_cycle"] = 1
	renderer._observe_portrait_cycle("remote", "peer", schema.deserialize_transform(transform))
	_check(events.size() == 2, "Restart or retired incarnation was handled incorrectly")
	transform["portrait_cycle"] = -1
	_check(schema.deserialize_transform(transform).is_empty(), "Invalid cycle marker was accepted")
	renderer.queue_free()

func _test_face_parsing() -> void:
	_check(FaceClient.gender_label({"male": 0.7, "female": 0.3}) == "?", "70 percent must not match")
	_check(FaceClient.gender_label({"male": 0.701, "female": 0.299}) == "M", "Male threshold did not match")
	_check(FaceClient.gender_label({"male": 0.299, "female": 0.701}) == "F", "Female threshold did not match")
	_check(FaceClient.gender_label({"male": 0.71}) == "M", "Valid score should not require the other score")
	_check(FaceClient.gender_label({"male": 0.8, "female": 0.9}) == "?", "Contradictory scores must be unknown")
	_check(FaceClient.gender_label(null) == "?", "Missing scores must be unknown")
	var image := Image.create(13, 17, false, Image.FORMAT_RGB8)
	image.fill(Color.RED)
	var data := "data:image/jpeg;base64," + Marshalls.raw_to_base64(image.save_jpg_to_buffer())
	var parsed: Array = FaceClient.parse_faces([
		{"crop": data, "gender_scores": {"male": 0.8, "female": 0.2}},
		{"crop": data, "gender_scores": {"male": 0.1, "female": 0.9}},
		{"crop": "not-an-image"},
		{"crop": "data:image/jpeg;base64,YmFk"},
	])
	_check(parsed.size() == 2, "Malformed crops were not skipped")
	if parsed.size() == 2:
		_check(parsed[0]["label"] == "M" and parsed[1]["label"] == "F", "Face labels were incorrect")
		var decoded: Image = parsed[0]["image"]
		_check(decoded.get_size() == Vector2i(13, 17), "Face crop dimensions changed")

func _test_mesh_cycle_flow() -> void:
	var target := MeshInstance3D.new()
	target.mesh = BoxMesh.new()
	root.add_child(target)
	var sync = MeshSyncController.new()
	sync.floating_portrait = true
	sync.configure(target, null, root, true, "node", "peer", "remote", null)
	sync.process_transform(target, 0.5, 4)
	var payload: Dictionary = sync.get_mesh_sync_service().get_last_known_object_state("remote")["transform"]
	_check(payload.get("portrait_cycle") == 4 and not String(payload.get("portrait_incarnation", "")).is_empty(), "Owner did not publish cycle marker")

	var service = MeshSyncService.new()
	var renderer = Renderer.new()
	root.add_child(renderer)
	renderer.configure(service, "local")
	var events: Array = []
	renderer.portrait_cycle_observed.connect(func(object_id, owner): events.append([object_id, owner]))
	service.publish_object_spawn("remote", {"owner_peer_id": "peer"})
	var schema = Schema.new()
	var wire := schema.serialize_transform("remote", "peer", Transform3D.IDENTITY)
	wire["portrait_cycle"] = 0
	wire["portrait_incarnation"] = "run"
	service.publish_object_transform("remote", wire)
	wire["portrait_cycle"] = 1
	service.publish_object_transform("remote", wire)
	_check(events == [["remote", "peer"]], "Remote cycle did not propagate through mesh service")
	service.publish_object_spawn("other", {"owner_peer_id": "other-peer"})
	service.set_peer_online("peer", false)
	_check(not renderer._proxy_states.has("remote") and renderer._proxy_states.has("other"), "Disconnect removed another peer's proxy")
	renderer.shutdown()
	renderer.queue_free()
	target.queue_free()

func _test_face_errors() -> void:
	var client = FaceClient.new()
	root.add_child(client)
	var received: Array = []
	client.faces_received.connect(func(faces, order): received.append([faces, order]))
	client._active_requests = 1
	client._on_request_completed(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray(), HTTPRequest.new(), 1)
	_check(received.is_empty(), "Failed HTTP request produced face results")
	client._active_requests = 1
	client._on_request_completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), "not json".to_utf8_buffer(), HTTPRequest.new(), 2)
	_check(received.is_empty(), "Malformed response produced face results")
	client._active_requests = FaceClient.MAX_ACTIVE_REQUESTS
	_check(client.submit(PackedByteArray([0xff, 0xd8, 0xff]), 3) == ERR_BUSY, "Request limit was not enforced")
	client._active_requests = 0
	client.queue_free()

func _test_remote_snapshot_freshness() -> void:
	var cube = Cube.new()
	var snapshots := SnapshotStub.new()
	var client := FaceStub.new()
	cube._face_snapshot_client = snapshots
	cube._face_client = client
	cube._on_remote_portrait_cycle("remote", "peer")
	cube._on_remote_portrait_cycle("remote", "peer")
	_check(snapshots.calls == 1, "Overlapping cycle reused or duplicated an older snapshot request")
	cube._on_face_snapshot_received("remote", "peer", PackedByteArray([1]))
	_check(client.orders == [1], "Remote snapshot was attributed to the wrong cycle")
	cube._on_remote_portrait_cycle("remote", "peer")
	_check(snapshots.calls == 2, "Later cycle did not request a fresh snapshot")
	cube.free()

func _test_overlay() -> void:
	var original_size := root.size
	var original_scale_size := root.content_scale_size
	var original_scale_mode := root.content_scale_mode
	root.size = Vector2i(1000, 800)
	root.content_scale_size = Vector2i(500, 400)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var overlay = Overlay.new()
	overlay.max_portraits = 3
	root.add_child(overlay)
	await process_frame
	overlay._process(0.0)
	var physical_transform: Transform2D = root.get_screen_transform() * overlay.transform
	_check(physical_transform.is_equal_approx(Transform2D.IDENTITY), "Overlay is not one-to-one under display scaling")
	_check(overlay._root.size == Vector2(root.size), "Overlay does not cover the physical window")
	var image := Image.create(13, 17, false, Image.FORMAT_RGB8)
	var face := {"image": image, "label": "?"}
	overlay.add_faces([face, face], 2)
	overlay.add_faces([face], 3)
	overlay.add_faces([face], 1)
	_check(overlay._portraits.size() == 3, "Portrait limit was not enforced")
	_check(overlay._portraits[0]["order"] == 2 and overlay._portraits[2]["order"] == 3, "Out-of-order completion evicted a newer crop")
	var portrait: Control = overlay._portraits[0]["node"]
	_check(portrait.size == Vector2(13, 17), "Overlay resized the face crop")
	_check((portrait.get_child(0) as TextureRect).size == Vector2(13, 17), "Displayed texture resized the crop")
	_check((portrait.get_child(1) as Label).text == "?", "Portrait label missing")
	overlay._process(0.0)
	var initial := portrait.position
	overlay._process(0.5)
	_check(portrait.position.distance_to(initial) <= 2.0 * sqrt(2.0) * Overlay.JIGGLE_PIXELS, "Jiggle exceeded its bound")
	_check(portrait.position.x >= 0.0 and portrait.position.y >= 0.0, "Portrait escaped the display")
	overlay.queue_free()
	root.size = original_size
	root.content_scale_size = original_scale_size
	root.content_scale_mode = original_scale_mode
