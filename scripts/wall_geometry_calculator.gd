class_name WallGeometryCalculator
extends RefCounted

static func frustum_size_at_distance(camera: Camera3D, distance: float) -> Vector2:
	if camera == null:
		return Vector2.ZERO

	var resolved_distance := absf(distance)
	if resolved_distance <= 0.0001:
		resolved_distance = 0.0001

	var aspect: float = 1.0
	var viewport := camera.get_viewport()
	if viewport != null:
		var visible_rect := viewport.get_visible_rect().size
		if visible_rect.x > 0.0 and visible_rect.y > 0.0:
			aspect = visible_rect.x / visible_rect.y

	if camera.projection == Camera3D.PROJECTION_PERSPECTIVE:
		var fov_rad := deg_to_rad(camera.fov)
		if camera.keep_aspect == Camera3D.KEEP_WIDTH:
			var half_width_keep_width: float = tan(fov_rad * 0.5) * resolved_distance
			var half_height_keep_width: float = half_width_keep_width / maxf(aspect, 0.0001)
			return Vector2(half_width_keep_width, half_height_keep_width)

		var half_height_fov: float = tan(fov_rad * 0.5) * resolved_distance
		var half_width_fov: float = half_height_fov * maxf(aspect, 0.0001)
		return Vector2(half_width_fov, half_height_fov)

	if camera.keep_aspect == Camera3D.KEEP_WIDTH:
		var ortho_keep_width_half_width: float = camera.size * 0.5
		var ortho_keep_width_half_height: float = ortho_keep_width_half_width / maxf(aspect, 0.0001)
		return Vector2(ortho_keep_width_half_width, ortho_keep_width_half_height)

	var ortho_other_half_height: float = camera.size * 0.5
	var ortho_other_half_width: float = ortho_other_half_height * maxf(aspect, 0.0001)
	return Vector2(ortho_other_half_width, ortho_other_half_height)

static func compute_world_units_per_mm(camera: Camera3D, monitor_width_mm: float) -> float:
	if camera == null:
		return 0.0
	var width_mm := maxf(monitor_width_mm, 0.0001)
	var distance_to_wall := absf(camera.global_position.z)
	if distance_to_wall <= 0.0001:
		distance_to_wall = 0.0001
	var frustum_size := frustum_size_at_distance(camera, distance_to_wall)
	return frustum_size.x / width_mm

static func compute_node_camera_offset(wall_layout: Dictionary, world_units_per_mm: float) -> Vector3:
	var column_count := maxi(int(wall_layout.get("columns", 1)), 1)
	var row_count := maxi(int(wall_layout.get("rows", 1)), 1)
	var monitor_width_mm := maxf(float(wall_layout.get("monitor_width_mm", 168.0)), 0.0001)
	var monitor_height_mm := maxf(float(wall_layout.get("monitor_height_mm", 300.0)), 0.0001)
	var gap_mm := maxf(float(wall_layout.get("gap_mm", 5.0)), 0.0)
	var this_node_column := int(wall_layout.get("this_node_column", 0))
	var this_node_row := int(wall_layout.get("this_node_row", 0))

	var x_mm := (float(this_node_column) - (float(column_count) - 1.0) * 0.5) * (monitor_width_mm + gap_mm)
	var y_mm := (float(this_node_row) - (float(row_count) - 1.0) * 0.5) * (monitor_height_mm + gap_mm)
	return Vector3(
		x_mm * world_units_per_mm,
		y_mm * world_units_per_mm,
		0.0
	)

static func compute_wall_world_bounds(wall_layout: Dictionary, world_units_per_mm: float) -> Dictionary:
	var column_count := maxi(int(wall_layout.get("columns", 1)), 1)
	var row_count := maxi(int(wall_layout.get("rows", 1)), 1)
	var monitor_width_mm := maxf(float(wall_layout.get("monitor_width_mm", 168.0)), 0.0001)
	var monitor_height_mm := maxf(float(wall_layout.get("monitor_height_mm", 300.0)), 0.0001)
	var gap_mm := maxf(float(wall_layout.get("gap_mm", 5.0)), 0.0)

	var total_width_mm := float(column_count) * monitor_width_mm + float(maxi(column_count - 1, 0)) * gap_mm
	var total_height_mm := float(row_count) * monitor_height_mm + float(maxi(row_count - 1, 0)) * gap_mm
	var half_width := (total_width_mm * 0.5) * world_units_per_mm
	var half_height := (total_height_mm * 0.5) * world_units_per_mm
	var half_depth := maxf(12.0, maxf(half_width, half_height) * 4.0)

	return {
		"center": Vector3.ZERO,
		"half_extents": Vector3(half_width, half_height, half_depth)
	}
