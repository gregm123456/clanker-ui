extends SceneTree

const Movement = preload("res://scripts/spinning_cube_movement_controller.gd")
const Sync = preload("res://scripts/spinning_cube_mesh_sync_controller.gd")
const Renderer = preload("res://scripts/remote_object_renderer.gd")
const MeshSyncService = preload("res://scripts/mesh_sync_service.gd")

var failures := 0

func _initialize() -> void:
	call_deferred("_run_tests")

func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		failures += 1

func _run_tests() -> void:
	var cube := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(4.25, 4.25, 0.05)
	cube.mesh = box
	root.add_child(cube)
	var movement = Movement.new()
	movement.floating_portrait = true
	movement.enable_wraparound = false
	movement.move_velocity = Vector3(0.5, 0.2, -1.0)
	movement.initialize_portrait(cube)
	for i in 900:
		movement.process_transform(cube, 0.01, null, null)
		var t := float(i + 1) * 0.01
		_check(absf(cube.rotation.x) <= deg_to_rad(8.01), "Pitch exceeded wobble limit")
		_check(absf(cube.rotation.y) <= deg_to_rad(20.01), "Yaw exceeded wobble limit")
		_check(absf(cube.rotation.z) <= deg_to_rad(5.01), "Roll exceeded wobble limit")
		if t < 6.0:
			_check(absf(cube.position.z) < 0.001, "Portrait left the near view too early")
		_check(cube.position.z >= -10.001 and cube.position.z <= 0.001, "Depth exceeded cycle range")
		if absf(t - 7.5) < 0.001:
			_check(absf(cube.position.z + 10.0) < 0.001, "Exit did not reach fade-out depth")
	_check(absf(cube.position.z) < 0.001, "Portrait did not return to the near view")
	_check(absf(cube.position.x - 4.5) < 0.001, "Horizontal drift changed during the cycle")
	var previous_rotation := cube.rotation
	movement.process_transform(cube, 0.01, null, null)
	_check(cube.rotation.distance_to(previous_rotation) < 0.01, "Wobble jumped at the cycle boundary")

	var sync = Sync.new()
	sync.floating_portrait = true
	sync.configure(cube, null, root, true, "node", "peer", "portrait", null)
	var descriptor: Dictionary = sync.get_mesh_sync_service().get_last_known_object_state("portrait")["descriptor"]
	var renderer = Renderer.new()
	root.add_child(renderer)
	var proxy: MeshInstance3D = renderer._create_proxy_for_descriptor("portrait", descriptor)
	_check((proxy.mesh as BoxMesh).size.is_equal_approx(box.size), "Proxy did not retain the portrait size")
	var material := proxy.material_override as ShaderMaterial
	_check(bool(material.get_shader_parameter("portrait_depth_fade")), "Proxy did not enable the shared depth fade")
	_check(is_equal_approx(float(material.get_shader_parameter("portrait_origin_z")), cube.global_position.z), "Proxy fade origin differs from owner")
	proxy.queue_free()

	var camera := Camera3D.new()
	camera.position.z = 7.0
	root.add_child(camera)
	var service = MeshSyncService.new()
	renderer.configure(service, "local", camera)
	var requests := [0]
	renderer.snapshot_requested.connect(func(_object_id, _peer_id): requests[0] += 1)
	service.publish_object_spawn("remote", descriptor)
	var state: Dictionary = renderer._proxy_states["remote"]
	var remote: MeshInstance3D = state["instance"]
	remote.position = Vector3.ZERO
	renderer.process(0.0)
	remote.position.z = -10.0
	renderer.process(0.0)
	remote.position.z = -8.0
	renderer.process(0.0)
	_check(requests[0] == 2, "Returning from the depth fade did not request a fresh snapshot")
	renderer.shutdown()
	camera.queue_free()
	renderer.queue_free()
	cube.queue_free()
	if failures == 0:
		print("Floating portrait tests passed")
	quit(1 if failures else 0)
