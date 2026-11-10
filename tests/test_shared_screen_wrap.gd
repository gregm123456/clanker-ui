extends SceneTree

const Bounds = preload("res://scripts/spinning_cube_bounds_strategy.gd")
const Geometry = preload("res://scripts/combined_display_geometry.gd")

var failures := 0

func _initialize() -> void:
	call_deferred("_run_tests")

func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		failures += 1

func _projected_range(camera: Camera3D, cube: MeshInstance3D, horizontal: bool) -> Vector2:
	var result := Vector2(INF, -INF)
	for i in 8:
		var point := camera.unproject_position(cube.global_transform * cube.get_aabb().get_endpoint(i))
		var coordinate := point.x if horizontal else point.y
		result.x = minf(result.x, coordinate)
		result.y = maxf(result.y, coordinate)
	return result

func _apply(bounds, cube: MeshInstance3D, camera: Camera3D, velocity: Vector3) -> void:
	bounds.apply_bounds(cube, camera, camera.get_viewport(), 0.3, Bounds.BoundsMode.WRAP_SHARED_SCREEN,
		Bounds.BoundsBehavior.WRAP, Vector3.ZERO, Vector3(100.0, 100.0, 100.0), velocity)

func _test_edge(bounds, camera: Camera3D, cube: MeshInstance3D, depth: float, horizontal: bool, positive: bool) -> void:
	cube.position = Vector3(0.0, 0.0, depth)
	var axis := 0 if horizontal else 1
	var sign_value := 1.0 if positive else -1.0
	var pixel_limit := float(camera.get_viewport().size.x if horizontal else camera.get_viewport().size.y)
	# Find the actual projected exit with the engine's projection, independently of the wrap calculation.
	var inside := 0.0
	var outside := 100.0
	for _i in 30:
		var middle := (inside + outside) * 0.5
		cube.position[axis] = middle * sign_value
		var projected := _projected_range(camera, cube, horizontal)
		var is_outside := projected.x > pixel_limit if (horizontal and positive) or (not horizontal and not positive) else projected.y < 0.0
		if is_outside:
			outside = middle
		else:
			inside = middle

	var velocity := Vector3.ZERO
	velocity[axis] = sign_value
	cube.position[axis] = inside * sign_value
	var before := cube.position
	_apply(bounds, cube, camera, velocity)
	_check(cube.position.is_equal_approx(before), "Wrapped before the full rotated mesh left the screen")

	cube.position[axis] = (outside + 0.31) * sign_value
	_apply(bounds, cube, camera, velocity)
	_check(cube.position[axis] * sign_value < 0.0, "Failed to wrap after exiting an edge")
	var opposite := _projected_range(camera, cube, horizontal)
	var fully_outside := opposite.y < 0.0 if (horizontal and positive) or (not horizontal and not positive) else opposite.x > pixel_limit
	_check(fully_outside, "Appeared before the full mesh reached the opposite edge")
	var wrapped := cube.position
	cube.rotate_z(0.02)
	_apply(bounds, cube, camera, velocity)
	_check(cube.position.is_equal_approx(wrapped), "Wrapped back while moving inward")

func _run_tests() -> void:
	var layout: Dictionary = Geometry.calculate(Rect2i(0, 0, 600, 1024), Rect2i(600, 0, 600, 1024), 65.8, 6.2)
	var virtual_size: Vector2i = layout["virtual_size"]
	_check(virtual_size == Vector2i(1257, 1024), "Unexpected bezel-aware viewport size")
	var viewport := SubViewport.new()
	viewport.size = virtual_size
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
	_check(bounds.configure_shared_screen(camera, virtual_size), "Could not configure reference view")
	for depth in [0.0, -12.0]:
		for horizontal in [true, false]:
			for positive in [true, false]:
				cube.rotation = Vector3(0.5, 0.7, 0.3)
				_test_edge(bounds, camera, cube, depth, horizontal, positive)

	var peer_viewport := SubViewport.new()
	peer_viewport.size = Vector2i(600, 1024)
	root.add_child(peer_viewport)
	var peer_camera := Camera3D.new()
	peer_camera.position.z = 7.0
	peer_camera.fov = 65.0
	peer_viewport.add_child(peer_camera)
	var peer := MeshInstance3D.new()
	peer.mesh = box
	peer_viewport.add_child(peer)
	var peer_bounds = Bounds.new()
	_check(peer_bounds.configure_shared_screen(peer_camera, virtual_size), "Could not configure peer reference view")
	cube.rotation = Vector3(0.5, 0.7, 0.3)
	peer.rotation = cube.rotation
	cube.position = Vector3(25.0, 0.0, -12.0)
	peer.position = cube.position
	_apply(bounds, cube, camera, Vector3.RIGHT)
	_apply(peer_bounds, peer, peer_camera, Vector3.RIGHT)
	_check(cube.position.is_equal_approx(peer.position), "Peer viewport affected shared wrap")

	cube.position = Vector3(9.0, 0.0, 0.0)
	bounds.apply_bounds(cube, camera, viewport, 0.3, Bounds.BoundsMode.BOUNDS_3D_VOLUME,
		Bounds.BoundsBehavior.WRAP, Vector3.ZERO, Vector3(8.0, 4.5, 12.0), Vector3.RIGHT)
	_check(is_equal_approx(cube.position.x, -8.0), "Legacy volume wrapping changed")
	cube.position = Vector3(0.0, 0.0, -101.0)
	_apply(bounds, cube, camera, Vector3(0.0, 0.0, -1.0))
	_check(is_equal_approx(cube.position.z, 100.0), "Depth wrapping changed")
	viewport.queue_free()
	peer_viewport.queue_free()
	if failures == 0:
		print("Shared screen wrap tests passed")
	quit(1 if failures else 0)
