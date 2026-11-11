extends SceneTree

const AddressBook = preload("res://scripts/peer_address_book.gd")
const SnapshotClient = preload("res://scripts/webcam_snapshot_client.gd")
const FaceClient = preload("res://scripts/face_attribute_client.gd")
const Cube = preload("res://spinning_cube.gd")
const Overlay = preload("res://scripts/face_portrait_overlay.gd")

class CameraStub extends RefCounted:
	var image: Image

	func get_current_frame_image() -> Image:
		return image

var _snapshots
var _faces
var _cube
var _camera := CameraStub.new()
var _overlay
var _received := {}
var _total_faces := 0
var _failed := false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var addresses = AddressBook.new()
	addresses.configure({
		"usb": {"host": "pi5ai2sd", "port": 9000},
		"csi": {"host": "m5image", "port": 9000},
	}, 9000)
	_snapshots = SnapshotClient.new()
	root.add_child(_snapshots)
	_snapshots.configure(addresses, 9010)
	_snapshots.snapshot_jpeg_received.connect(_on_snapshot)
	_snapshots.snapshot_failed.connect(_on_snapshot_failed)
	_faces = FaceClient.new()
	root.add_child(_faces)
	_faces.faces_received.connect(_on_faces)
	_cube = Cube.new()
	_cube._camera_source = _camera
	_cube._face_client = _faces
	_cube._face_snapshot_client = _snapshots
	_snapshots.snapshot_jpeg_received.connect(_cube._on_face_snapshot_received)
	_snapshots.snapshot_failed.connect(_cube._on_face_snapshot_failed)
	_faces.faces_received.connect(_cube._on_face_crops_received)
	_overlay = Overlay.new()
	root.add_child(_overlay)
	_cube.face_crops_received.connect(_overlay.add_faces)
	_cube._on_remote_portrait_cycle("csi", "csi")
	if _snapshots.request_snapshot("usb", "usb") != OK:
		push_error("Could not start USB snapshot")
		_failed = true
	var deadline := Time.get_ticks_msec() + 30000
	while not _failed and _received.size() < 2 and Time.get_ticks_msec() < deadline:
		await create_timer(0.1).timeout
	if _received.size() != 2:
		push_error("Live camera/face requests did not both complete")
		_failed = true
	else:
		print("Live camera and Hailo requests passed for USB and CSI")
		if _overlay._portraits.size() != mini(_total_faces, 10):
			push_error("Face crops did not reach the overlay")
			_failed = true
	_snapshots.close()
	_snapshots.queue_free()
	_faces.queue_free()
	_overlay.queue_free()
	_cube.free()
	quit(1 if _failed else 0)

func _on_snapshot(object_id: String, _peer_id: String, jpeg: PackedByteArray) -> void:
	if object_id != "usb":
		return
	var image := Image.new()
	if image.load_jpg_from_buffer(jpeg) != OK:
		push_error("Could not decode USB snapshot")
		_failed = true
		return
	_camera.image = image
	_cube._on_local_portrait_reentered(1)

func _on_snapshot_failed(object_id: String, _peer_id: String, reason: String) -> void:
	push_error("Snapshot failed for %s: %s" % [object_id, reason])
	_failed = true

func _on_faces(faces: Array, order: int) -> void:
	_received[order] = true
	_total_faces += faces.size()
	print("Camera ", order, ": ", faces.size(), " valid face crop(s)")
