class_name SpinningCubeMovementController
extends RefCounted

var tumble_speed: Vector3 = Vector3(1.2, 1.8, 0.9)
var move_velocity: Vector2 = Vector2(2.2, 1.4)
var enable_wraparound: bool = true
var wrap_margin: float = 1.6

func randomize_speed_and_velocity() -> void:
	tumble_speed = Vector3(
		tumble_speed.x * randf_range(0.01, 1.0),
		tumble_speed.y * randf_range(0.01, 1.0),
		tumble_speed.z * randf_range(0.01, 2.0)
	)
	move_velocity = Vector2(
		move_velocity.x * randf_range(0.01, 4.0),
		move_velocity.y * randf_range(0.1, 1.5)
	)

func process_transform(target: Node3D, delta: float, camera: Camera3D, viewport: Viewport) -> Camera3D:
	target.rotate_x(tumble_speed.x * delta)
	target.rotate_y(tumble_speed.y * delta)
	target.rotate_z(tumble_speed.z * delta)

	target.position.x += move_velocity.x * delta
	target.position.y += move_velocity.y * delta

	if enable_wraparound:
		return handle_wraparound(target, camera, viewport)

	return camera

func handle_viewport_size_changed(target: Node3D, camera: Camera3D, viewport: Viewport) -> Camera3D:
	if enable_wraparound:
		return handle_wraparound(target, camera, viewport)

	return camera

func handle_wraparound(target: Node3D, camera: Camera3D, viewport: Viewport) -> Camera3D:
	var resolved_camera := camera
	if resolved_camera == null and viewport != null:
		resolved_camera = viewport.get_camera_3d()
	if resolved_camera == null or viewport == null:
		return resolved_camera

	var vp_size := viewport.get_visible_rect().size
	if vp_size.y <= 0:
		return resolved_camera

	var aspect := vp_size.x / vp_size.y
	var cam_pos := resolved_camera.global_position
	var z_dist := absf(cam_pos.z - target.global_position.z)

	var half_h: float
	var half_w: float
	if resolved_camera.projection == Camera3D.PROJECTION_PERSPECTIVE:
		var fov_rad := deg_to_rad(resolved_camera.fov)
		if resolved_camera.keep_aspect == Camera3D.KEEP_WIDTH:
			half_w = tan(fov_rad * 0.5) * z_dist
			half_h = half_w / aspect
		else:
			half_h = tan(fov_rad * 0.5) * z_dist
			half_w = half_h * aspect
	else:
		if resolved_camera.keep_aspect == Camera3D.KEEP_WIDTH:
			half_w = resolved_camera.size * 0.5
			half_h = half_w / aspect
		else:
			half_h = resolved_camera.size * 0.5
			half_w = half_h * aspect

	var bound_x := half_w + wrap_margin
	var bound_y := half_h + wrap_margin

	var next_global_position := target.global_position
	var rel_x := next_global_position.x - cam_pos.x
	if rel_x > bound_x:
		next_global_position.x = cam_pos.x - bound_x
	elif rel_x < -bound_x:
		next_global_position.x = cam_pos.x + bound_x

	var rel_y := next_global_position.y - cam_pos.y
	if rel_y > bound_y:
		next_global_position.y = cam_pos.y - bound_y
	elif rel_y < -bound_y:
		next_global_position.y = cam_pos.y + bound_y

	target.global_position = next_global_position

	return resolved_camera
