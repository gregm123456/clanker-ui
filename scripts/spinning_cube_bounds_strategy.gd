class_name SpinningCubeBoundsStrategy
extends RefCounted

const WallGeometryCalculatorScript = preload("res://scripts/wall_geometry_calculator.gd")

enum BoundsMode {
	NONE,
	WRAP_2D_VIEWPORT,
	BOUNDS_3D_VOLUME
}

enum BoundsBehavior {
	WRAP,
	CLAMP
}

func apply_bounds(
		target: Node3D,
		camera: Camera3D,
		viewport: Viewport,
		wrap_margin: float,
		bounds_mode: int,
		bounds_behavior: int,
		volume_center: Vector3,
		volume_half_extents: Vector3
) -> Camera3D:
	if bounds_mode == BoundsMode.NONE:
		return camera
	if bounds_mode == BoundsMode.WRAP_2D_VIEWPORT:
		return _apply_viewport_wrap_2d(target, camera, viewport, wrap_margin)
	if bounds_mode == BoundsMode.BOUNDS_3D_VOLUME:
		return _apply_volume_bounds_3d(target, camera, bounds_behavior, volume_center, volume_half_extents)

	return camera

func _apply_viewport_wrap_2d(target: Node3D, camera: Camera3D, viewport: Viewport, wrap_margin: float) -> Camera3D:
	var resolved_camera := camera
	if resolved_camera == null and viewport != null:
		resolved_camera = viewport.get_camera_3d()
	if resolved_camera == null or viewport == null:
		return resolved_camera

	var vp_size := viewport.get_visible_rect().size
	if vp_size.y <= 0:
		return resolved_camera

	var cam_pos := resolved_camera.global_position
	var z_dist := absf(cam_pos.z - target.global_position.z)
	var frustum_size := WallGeometryCalculatorScript.frustum_size_at_distance(resolved_camera, z_dist)
	var bound_x := frustum_size.x + wrap_margin
	var bound_y := frustum_size.y + wrap_margin

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

func _apply_volume_bounds_3d(
		target: Node3D,
		camera: Camera3D,
		bounds_behavior: int,
		volume_center: Vector3,
		volume_half_extents: Vector3
) -> Camera3D:
	var next_global_position := target.global_position

	var min_bounds := volume_center - volume_half_extents
	var max_bounds := volume_center + volume_half_extents

	if bounds_behavior == BoundsBehavior.CLAMP:
		next_global_position.x = clampf(next_global_position.x, min_bounds.x, max_bounds.x)
		next_global_position.y = clampf(next_global_position.y, min_bounds.y, max_bounds.y)
		next_global_position.z = clampf(next_global_position.z, min_bounds.z, max_bounds.z)
	else:
		next_global_position.x = _wrap_axis(next_global_position.x, min_bounds.x, max_bounds.x)
		next_global_position.y = _wrap_axis(next_global_position.y, min_bounds.y, max_bounds.y)
		next_global_position.z = _wrap_axis(next_global_position.z, min_bounds.z, max_bounds.z)

	target.global_position = next_global_position
	return camera

func _wrap_axis(value: float, min_value: float, max_value: float) -> float:
	if value > max_value:
		return min_value
	if value < min_value:
		return max_value
	return value
