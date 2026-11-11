extends SceneTree

const Movement = preload("res://scripts/spinning_cube_movement_controller.gd")
const Sync = preload("res://scripts/spinning_cube_mesh_sync_controller.gd")
const Renderer = preload("res://scripts/remote_object_renderer.gd")
const MeshSyncService = preload("res://scripts/mesh_sync_service.gd")
const Bounds = preload("res://scripts/spinning_cube_bounds_strategy.gd")
const Schema = preload("res://scripts/transform_sync_schema.gd")

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
	movement._portrait_hold_seconds = 7.8
	for i in 1030:
		var previous_x := cube.position.x
		movement.process_transform(cube, 0.01, null, null)
		var t := float(i + 1) * 0.01
		_check(absf(cube.rotation.x) <= deg_to_rad(8.01), "Pitch exceeded wobble limit")
		_check(absf(cube.rotation.y) <= deg_to_rad(20.01), "Yaw exceeded wobble limit")
		_check(absf(cube.rotation.z) <= deg_to_rad(5.01), "Roll exceeded wobble limit")
		if t < 7.8:
			_check(absf(cube.position.z) < 0.001, "Portrait left the near view too early")
		_check(cube.position.z >= -60.001 and cube.position.z <= 0.001, "Depth exceeded cycle range")
		_check(absf(cube.position.x - previous_x - movement.move_velocity.x * 0.01) < 0.0001, "Horizontal drift did not follow its velocity")
		if absf(t - 9.21) < 0.001:
			_check(7.0 - cube.position.z >= 3.0 * (7.0 + 12.8) and movement.portrait_opacity > 0.99, "Portrait faded before reaching three times its former visible distance")
		if absf(t - 9.29) < 0.001:
			_check(cube.position.z < -59.0 and movement.portrait_opacity < 0.05, "Exit was not distant and invisible")
		if absf(t - 9.31) < 0.001:
			_check(absf(cube.position.z) < 0.001 and movement.portrait_opacity < 0.01, "Portrait did not re-enter invisibly at the front")
		if absf(t - 9.8) < 0.001:
			_check(absf(cube.position.z) < 0.001 and movement.portrait_opacity > 0.4, "Portrait did not fade in at the front")
	_check(absf(cube.position.z) < 0.001, "Portrait did not stay at the front after re-entry")
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
	var schema = Schema.new()
	var hidden := schema.serialize_transform("remote", "peer", Transform3D(Basis.IDENTITY, Vector3(0, 0, -20)))
	hidden["opacity"] = 0.0
	service.publish_object_transform("remote", hidden)
	renderer.process(0.0)
	_check(is_zero_approx(float((remote.material_override as ShaderMaterial).get_shader_parameter("portrait_opacity"))), "Remote opacity was not synchronized")
	var visible := schema.serialize_transform("remote", "peer", Transform3D.IDENTITY)
	visible["opacity"] = 0.5
	service.publish_object_transform("remote", visible)
	renderer.process(0.0)
	_check(requests[0] == 2, "Re-entering at the front did not request a fresh snapshot")
	_check(is_equal_approx(float((remote.material_override as ShaderMaterial).get_shader_parameter("portrait_opacity")), 0.5), "Remote fade-in opacity was not synchronized")
	_check(is_equal_approx(float(schema.deserialize_transform(schema.serialize_transform("remote", "peer", Transform3D.IDENTITY))["opacity"]), 1.0), "Old transform without opacity is not opaque")
	renderer.shutdown()
	camera.queue_free()
	renderer.queue_free()
	cube.queue_free()
	_test_reentry_direction()
	_test_shared_reentry_visibility()
	_test_vertical_walls()
	if failures == 0:
		print("Floating portrait tests passed")
	quit(1 if failures else 0)

func _test_reentry_direction() -> void:
	var cube := Node3D.new()
	root.add_child(cube)
	var movement = Movement.new()
	movement.floating_portrait = true
	movement.enable_wraparound = false
	movement.move_velocity = Vector3(0.5, 0.2, 0.0)
	seed(123456)
	movement.initialize_portrait(cube)
	var saw_left := false
	var saw_right := false
	var shortest_hold := 8.0
	var longest_hold := 5.0
	for _i in 24:
		var hold: float = movement._portrait_hold_seconds
		_check(hold >= 5.0 and hold <= 8.0, "Front hold was outside the requested range")
		shortest_hold = minf(shortest_hold, hold)
		longest_hold = maxf(longest_hold, hold)
		movement.process_transform(cube, hold - movement._portrait_stage_elapsed - 0.01, null, null)
		_check(absf(cube.position.z) < 0.001, "Portrait retreated before its chosen hold ended")
		movement.process_transform(cube, 0.02, null, null)
		_check(cube.position.z < 0.0, "Portrait did not retreat after its chosen hold")
		var previous_velocity: Vector3 = movement.move_velocity
		movement.process_transform(cube, 1.48, null, null)
		_check(movement.move_velocity == previous_velocity, "Horizontal direction changed before re-entry")
		movement.process_transform(cube, 0.02, null, null)
		var velocity: Vector3 = movement.move_velocity
		var next_hold: float = movement._portrait_hold_seconds
		saw_left = saw_left or velocity.x < 0.0
		saw_right = saw_right or velocity.x > 0.0
		_check(is_equal_approx(absf(velocity.x), 0.5) and is_equal_approx(velocity.y, 0.2), "Re-entry changed drift speed or vertical velocity")
		movement.process_transform(cube, 0.02, null, null)
		_check(movement.move_velocity == velocity, "Horizontal direction changed again during fade-in")
		_check(is_equal_approx(movement._portrait_hold_seconds, next_hold), "Hold changed again during fade-in")
		movement.process_transform(cube, 1.0, null, null)
	_check(saw_left and saw_right, "Re-entry did not choose both horizontal directions")
	_check(longest_hold - shortest_hold > 1.5, "Front holds did not vary across cycles")
	var skipped = Movement.new()
	skipped.floating_portrait = true
	skipped.enable_wraparound = false
	skipped.move_velocity = Vector3(0.5, 0.2, 0.0)
	skipped.initialize_portrait(cube)
	seed(123456)
	var expected_direction := 1.0 if randi_range(0, 1) == 1 else -1.0
	seed(123456)
	skipped.process_transform(cube, 10.4, null, null)
	_check(is_equal_approx(skipped.move_velocity.x, 0.5 * expected_direction), "Skipped re-entry did not choose a direction")
	var stepped = Movement.new()
	stepped.floating_portrait = true
	stepped.enable_wraparound = false
	stepped.move_velocity = Vector3(0.5, 0.2, 0.0)
	cube.position = Vector3.ZERO
	cube.rotation = Vector3.ZERO
	seed(789)
	stepped.initialize_portrait(cube)
	for _i in 320:
		stepped.process_transform(cube, 0.1, null, null)
	var expected_depth := cube.position.z
	var fast = Movement.new()
	fast.floating_portrait = true
	fast.enable_wraparound = false
	fast.move_velocity = Vector3(0.5, 0.2, 0.0)
	cube.position = Vector3.ZERO
	cube.rotation = Vector3.ZERO
	seed(789)
	fast.initialize_portrait(cube)
	fast.process_transform(cube, 32.0, null, null)
	_check(is_equal_approx(fast._portrait_hold_seconds, stepped._portrait_hold_seconds) and fast._portrait_in_entry == stepped._portrait_in_entry and is_equal_approx(fast.move_velocity.x, stepped.move_velocity.x) and absf(cube.position.z - expected_depth) < 0.001, "Long frame skipped or repeated a randomized reset")
	cube.queue_free()

func _test_shared_reentry_visibility() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1257, 1024)
	root.add_child(viewport)
	var camera := Camera3D.new()
	camera.position.z = 7.0
	camera.fov = 65.0
	viewport.add_child(camera)
	var cube := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(4.25, 4.25, 0.05)
	cube.mesh = box
	viewport.add_child(cube)
	var saw_left := false
	var saw_right := false
	for seed_value in [11, 12, 13, 14, 15, 16, 17, 18]:
		seed(seed_value)
		var movement = Movement.new()
		movement.floating_portrait = true
		movement.bounds_mode = Bounds.BoundsMode.WRAP_SHARED_SCREEN
		movement.bounds_volume_half_extents = Vector3(20.0, 20.0, 60.0)
		movement.move_velocity = Vector3(0.66, 0.2, 0.0)
		_check(movement.configure_shared_screen(camera, viewport.size), "Could not configure shared re-entry view")
		cube.position = Vector3(8.0 if seed_value % 2 == 0 else -8.0, 0.0, 0.0)
		cube.rotation = Vector3.ZERO
		movement.initialize_portrait(cube)
		movement._portrait_hold_seconds = 5.0
		movement.process_transform(cube, 6.49, camera, viewport)
		_check(cube.position.z < -59.0 and movement.portrait_opacity < 0.05, "Portrait was not hidden before re-entry")
		movement.process_transform(cube, 0.02, camera, viewport)
		_check(movement.portrait_opacity < 0.01 and is_zero_approx(cube.position.z), "Portrait was not hidden when repositioned")
		_check(cube.position.x * movement.move_velocity.x < 0.0, "Portrait did not enter opposite its direction")
		saw_left = saw_left or movement.move_velocity.x < 0.0
		saw_right = saw_right or movement.move_velocity.x > 0.0
		movement._portrait_hold_seconds = 8.0
		for _i in 180:
			var projected_left := INF
			var projected_right := -INF
			for j in 8:
				var projected := camera.unproject_position(cube.global_transform * cube.get_aabb().get_endpoint(j))
				projected_left = minf(projected_left, projected.x)
				projected_right = maxf(projected_right, projected.x)
			var visible_width := maxf(0.0, minf(projected_right, viewport.size.x) - maxf(projected_left, 0.0))
			_check(visible_width >= 0.95 * (projected_right - projected_left), "Portrait spent front time mostly off the shared wall")
			movement.process_transform(cube, 0.05, camera, viewport)
	_check(saw_left and saw_right, "Re-entry visibility test did not cover both directions")
	viewport.queue_free()

func _test_vertical_walls() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1257, 1024)
	root.add_child(viewport)
	var camera := Camera3D.new()
	camera.position.z = 7.0
	camera.fov = 65.0
	viewport.add_child(camera)
	var cube := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(4.25, 4.25, 0.05)
	cube.mesh = box
	viewport.add_child(cube)
	var bounds = Bounds.new()
	_check(bounds.configure_shared_screen(camera, viewport.size), "Could not configure shared vertical walls")
	for depth in [0.0, -60.0]:
		for direction in [-1.0, 1.0]:
			cube.rotation = Vector3(0.13, 0.3, 0.08)
			cube.position = Vector3(0.0, direction * 100.0, depth)
			var reflected: Vector3 = bounds.bounce_vertical(cube, camera, viewport, Bounds.BoundsMode.WRAP_SHARED_SCREEN, Vector3(0.5, direction, 0.0))
			_check(reflected.y * direction < 0.0, "Vertical velocity did not bounce")
			for i in 8:
				var projected := camera.unproject_position(cube.global_transform * cube.get_aabb().get_endpoint(i))
				_check(projected.y >= -0.02 and projected.y <= 1024.02, "Rotated portrait crossed a vertical screen edge")

	var movement = Movement.new()
	movement.floating_portrait = true
	movement.bounds_mode = Bounds.BoundsMode.WRAP_SHARED_SCREEN
	movement.bounds_volume_half_extents = Vector3(20.0, 20.0, 60.0)
	movement.move_velocity = Vector3(0.0, 4.0, 0.0)
	_check(movement.configure_shared_screen(camera, viewport.size), "Could not configure movement reference view")
	cube.position = Vector3.ZERO
	cube.rotation = Vector3.ZERO
	movement.initialize_portrait(cube)
	var bounced_top := false
	var bounced_bottom := false
	var deepest := 0.0
	for _i in 1030:
		var before_velocity: float = movement.move_velocity.y
		movement.process_transform(cube, 0.01, camera, viewport)
		deepest = minf(deepest, cube.position.z)
		if before_velocity > 0.0 and movement.move_velocity.y < 0.0:
			bounced_top = true
		if before_velocity < 0.0 and movement.move_velocity.y > 0.0:
			bounced_bottom = true
		for i in 8:
			var projected := camera.unproject_position(cube.global_transform * cube.get_aabb().get_endpoint(i))
			_check(projected.y >= -0.02 and projected.y <= 1024.02, "Portrait escaped a wall during movement")
	_check(bounced_top and bounced_bottom, "Portrait did not bounce off both vertical walls")
	_check(deepest < -59.0, "Shared-screen bounds prevented the distant retreat")
	viewport.queue_free()
