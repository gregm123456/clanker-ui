class_name SpinningCubeBoundsStrategy
extends RefCounted

const WallGeometryCalculatorScript = preload("res://scripts/wall_geometry_calculator.gd")

enum BoundsMode {
	NONE,
	WRAP_2D_VIEWPORT,
	BOUNDS_3D_VOLUME,
	WRAP_SHARED_SCREEN
}

enum BoundsBehavior {
	WRAP,
	CLAMP
}

var _reference_transform := Transform3D.IDENTITY
var _horizontal_tangent := 0.0
var _vertical_tangent := 0.0

func configure_shared_screen(camera: Camera3D, virtual_size: Vector2i) -> bool:
	if camera == null or camera.projection != Camera3D.PROJECTION_PERSPECTIVE \
			or camera.keep_aspect != Camera3D.KEEP_HEIGHT or virtual_size.x <= 0 or virtual_size.y <= 0:
		push_error("[wrap] Shared screen wrapping requires a perspective camera with KEEP_HEIGHT and a valid virtual size")
		return false
	_reference_transform = camera.global_transform
	_vertical_tangent = tan(deg_to_rad(camera.fov) * 0.5)
	_horizontal_tangent = _vertical_tangent * float(virtual_size.x) / float(virtual_size.y)
	return true

func apply_bounds(
		target: Node3D,
		camera: Camera3D,
		viewport: Viewport,
		wrap_margin: float,
		bounds_mode: int,
		bounds_behavior: int,
		volume_center: Vector3,
		volume_half_extents: Vector3,
		velocity: Vector3 = Vector3.ZERO
) -> Camera3D:
	if bounds_mode == BoundsMode.NONE:
		return camera
	if bounds_mode == BoundsMode.WRAP_2D_VIEWPORT:
		return _apply_viewport_wrap_2d(target, camera, viewport, wrap_margin)
	if bounds_mode == BoundsMode.BOUNDS_3D_VOLUME:
		return _apply_volume_bounds_3d(target, camera, bounds_behavior, volume_center, volume_half_extents)
	if bounds_mode == BoundsMode.WRAP_SHARED_SCREEN:
		return _apply_shared_screen_wrap(target, camera, wrap_margin, volume_center, volume_half_extents, velocity)

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

func _apply_shared_screen_wrap(
		target: Node3D,
		camera: Camera3D,
		wrap_margin: float,
		volume_center: Vector3,
		volume_half_extents: Vector3,
		velocity: Vector3
) -> Camera3D:
	if not target is MeshInstance3D or _horizontal_tangent <= 0.0 or _vertical_tangent <= 0.0:
		push_error("[wrap] Shared screen wrapping requires a configured reference view and a mesh")
		return camera

	var world_position := target.global_position
	world_position.z = _wrap_axis(world_position.z, volume_center.z - volume_half_extents.z, volume_center.z + volume_half_extents.z)
	target.global_position = world_position
	var inverse := _reference_transform.affine_inverse()
	var center := inverse * world_position
	var distance := -center.z
	if distance <= 0.0:
		return camera

	var mesh := target as MeshInstance3D
	var aabb := mesh.get_aabb()
	var relative_basis := inverse.basis * target.global_basis
	var min_right := INF
	var max_left := -INF
	var min_top := INF
	var max_bottom := -INF
	for i in 8:
		var offset := relative_basis * aabb.get_endpoint(i)
		min_right = minf(min_right, offset.x + _horizontal_tangent * offset.z)
		max_left = maxf(max_left, offset.x - _horizontal_tangent * offset.z)
		min_top = minf(min_top, offset.y + _vertical_tangent * offset.z)
		max_bottom = maxf(max_bottom, offset.y - _vertical_tangent * offset.z)

	var margin := maxf(wrap_margin, 0.0)
	var left := -_horizontal_tangent * distance - max_left - margin
	var right := _horizontal_tangent * distance - min_right + margin
	var bottom := -_vertical_tangent * distance - max_bottom - margin
	var top := _vertical_tangent * distance - min_top + margin
	var view_velocity := inverse.basis * velocity
	if center.x > right and view_velocity.x > 0.0:
		center.x = left
	elif center.x < left and view_velocity.x < 0.0:
		center.x = right
	if center.y > top and view_velocity.y > 0.0:
		center.y = bottom
	elif center.y < bottom and view_velocity.y < 0.0:
		center.y = top
	target.global_position = _reference_transform * center
	return camera

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
