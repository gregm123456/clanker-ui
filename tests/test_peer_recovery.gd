extends SceneTree

const Bridge = preload("res://scripts/mesh_network_bridge.gd")
const Renderer = preload("res://scripts/remote_object_renderer.gd")
const Service = preload("res://scripts/mesh_sync_service.gd")
const Schema = preload("res://scripts/transform_sync_schema.gd")
const SnapshotClient = preload("res://scripts/webcam_snapshot_client.gd")
const SnapshotServer = preload("res://scripts/webcam_snapshot_server.gd")

class TransportStub extends RefCounted:
	var sender: String
	var receiver
	var messages: Array = []

	func send(type: String, payload: Dictionary) -> Error:
		messages.append({"type": type, "payload": payload.duplicate(true)})
		if receiver != null:
			receiver._on_message_received({"type": type, "sender_peer_id": sender, "payload": payload.duplicate(true)})
		return OK

class AddressBookStub extends RefCounted:
	func resolve_peer(_peer_id: String) -> Dictionary:
		return {"address": "127.0.0.1"}

class CameraStub extends RefCounted:
	var image: Image

	func get_current_frame_image() -> Image:
		return image

var failures := 0

func _initialize() -> void:
	call_deferred("_run_tests")

func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		failures += 1

func _run_tests() -> void:
	_test_state_replay_after_restart()
	_test_visible_snapshot_retry()
	await _test_snapshot_server_recovery()
	if failures == 0:
		print("Peer recovery tests passed")
	quit(1 if failures else 0)

func _test_state_replay_after_restart() -> void:
	var sender = Bridge.new()
	sender._local_peer_id = "a"
	sender._mesh_sync_service = Service.new()
	var sender_transport := TransportStub.new()
	sender_transport.sender = "a"
	sender._transport = sender_transport
	sender.send_object_spawn("object-a", {"owner_peer_id": "a"})
	var transform: Dictionary = Schema.new().serialize_transform("object-a", "a", Transform3D.IDENTITY)
	sender.send_object_transform(transform)
	sender._last_seen_by_peer["b"] = Time.get_ticks_msec() / 1000.0

	var receiver = Bridge.new()
	receiver._local_peer_id = "b"
	receiver._mesh_sync_service = Service.new()
	receiver._transport = TransportStub.new()
	var renderer = Renderer.new()
	root.add_child(renderer)
	renderer.configure(receiver._mesh_sync_service, "object-b")
	receiver._on_message_received({"type": "transform", "sender_peer_id": "a", "payload": transform})
	sender._on_message_received({"type": "heartbeat", "sender_peer_id": "b", "payload": {}})
	_check(not renderer._proxy_states.has("object-a"), "Restart should not already have the lost descriptor")

	sender_transport.receiver = receiver
	sender._process(4.99)
	_check(not renderer._proxy_states.has("object-a"), "Descriptor was replayed before five seconds")
	sender._process(0.01)
	_check(renderer._proxy_states.has("object-a"), "Periodic replay did not restore the restarted peer's proxy")

	sender.send_object_despawn("object-a")
	_check(not renderer._proxy_states.has("object-a"), "Despawn did not remove the proxy")
	sender._process(5.0)
	_check(not renderer._proxy_states.has("object-a"), "Periodic replay resurrected a despawned object")

	renderer.shutdown()
	renderer.queue_free()
	sender.free()
	receiver.free()

func _test_visible_snapshot_retry() -> void:
	var camera := Camera3D.new()
	camera.position.z = 7.0
	root.add_child(camera)
	var service = Service.new()
	var renderer = Renderer.new()
	root.add_child(renderer)
	renderer.configure(service, "local", camera)
	var requests: Array = []
	renderer.set_snapshot_request_callback(func(object_id, peer_id): requests.append([object_id, peer_id]))
	service.publish_object_spawn("remote", {"owner_peer_id": "peer"})
	var instance: MeshInstance3D = renderer._proxy_states["remote"]["instance"]
	instance.position = Vector3.ZERO
	renderer.process(0.0)
	_check(requests.size() == 1, "Visible proxy did not request its first snapshot")
	renderer.process(4.99)
	_check(requests.size() == 1, "Snapshot retried before five seconds")
	renderer.process(0.01)
	_check(requests.size() == 2, "Unsuccessful snapshot was not retried")
	renderer.process(5.0)
	_check(requests.size() == 3, "Snapshot did not continue retrying")

	var image := Image.create(1, 1, false, Image.FORMAT_RGB8)
	renderer.apply_snapshot("remote", ImageTexture.create_from_image(image))
	renderer.process(10.0)
	_check(requests.size() == 3, "Successful snapshot continued retrying")

	instance.position.z = 10.0
	renderer.process(0.0)
	instance.position.z = 0.0
	renderer.process(0.0)
	_check(requests.size() == 4, "Re-entry did not request a fresh snapshot")
	instance.position.z = 10.0
	renderer.process(10.0)
	_check(requests.size() == 4, "Hidden proxy continued retrying")
	renderer.shutdown()
	renderer.queue_free()
	camera.queue_free()

func _test_snapshot_server_recovery() -> void:
	var source := CameraStub.new()
	var server = SnapshotServer.new()
	root.add_child(server)
	var port := randi_range(40000, 59999)
	var error: Error = server.configure(source, port)
	_check(error == OK, "Could not start snapshot test server")
	if error != OK:
		server.queue_free()
		return
	var client = SnapshotClient.new()
	root.add_child(client)
	client.configure(AddressBookStub.new(), port)
	var camera := Camera3D.new()
	camera.position.z = 7.0
	root.add_child(camera)
	var service = Service.new()
	var renderer = Renderer.new()
	root.add_child(renderer)
	renderer.configure(service, "local", camera)
	renderer.set_snapshot_request_callback(client.request_snapshot)
	var failed := [0]
	var received := [0]
	client.snapshot_failed.connect(func(_object_id, _owner, _reason): failed[0] += 1)
	client.snapshot_received.connect(func(object_id, _owner, texture):
		received[0] += 1
		renderer.apply_snapshot(object_id, texture)
	)
	service.publish_object_spawn("remote", {"owner_peer_id": "peer"})
	renderer.process(0.0)
	for _i in 100:
		if failed[0] > 0:
			break
		await create_timer(0.02).timeout
	_check(failed[0] == 1, "Missing camera frame did not fail the first snapshot")
	source.image = Image.create(2, 2, false, Image.FORMAT_RGB8)
	source.image.fill(Color.RED)
	renderer.process(5.0)
	for _i in 100:
		if received[0] > 0:
			break
		await create_timer(0.02).timeout
	_check(received[0] == 1, "Retry did not fetch a frame after the camera became available")
	renderer.process(10.0)
	_check(not bool(renderer._proxy_states["remote"].get("snapshot_retry_pending", true)), "Successful TCP snapshot did not stop retries")
	client.close()
	server.close()
	renderer.shutdown()
	client.queue_free()
	server.queue_free()
	renderer.queue_free()
	camera.queue_free()
