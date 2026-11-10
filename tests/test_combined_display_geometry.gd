extends SceneTree

const Geometry = preload("res://scripts/combined_display_geometry.gd")
const WallGeometry = preload("res://scripts/wall_geometry_calculator.gd")

func _initialize() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	var left := Rect2i(600, 0, 600, 1024)
	var right := Rect2i(1200, 0, 600, 1024)
	var layout: Dictionary = Geometry.calculate(right, left, 64.8, 6.0)
	assert(layout["window"] == Rect2i(600, 0, 1200, 1024))
	assert(layout["virtual_size"] == Vector2i(1256, 1024))
	assert(layout["gap_pixels"] == 56)
	assert(layout["left_region"] == Rect2i(0, 0, 600, 1024))
	assert(layout["right_region"] == Rect2i(656, 0, 600, 1024))

	var zero_gap: Dictionary = Geometry.calculate(left, right, 64.8, 0.0)
	assert(zero_gap["virtual_size"] == Vector2i(1200, 1024))
	assert(zero_gap["right_region"] == Rect2i(600, 0, 600, 1024))
	assert(Geometry.calculate(left, Rect2i(1201, 0, 600, 1024), 64.8, 6.0).is_empty())
	assert(Geometry.calculate(left, Rect2i(1200, 1, 600, 1024), 64.8, 6.0).is_empty())
	assert(Geometry.calculate(left, Rect2i(1200, 0, 601, 1024), 64.8, 6.0).is_empty())
	assert(Geometry.calculate(left, right, 0.0, 6.0).is_empty())
	assert(Geometry.calculate(left, right, 64.8, -1.0).is_empty())

	var viewport := SubViewport.new()
	viewport.size = Vector2i(1256, 1024)
	root.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.position.z = 7.0
	camera.fov = 65.0
	var scale: float = WallGeometry.compute_combined_world_units_per_mm(camera, 64.8, 6.0)
	var wall_bounds: Dictionary = WallGeometry.compute_wall_world_bounds({
		"columns": 2, "rows": 1, "monitor_width_mm": 64.8,
		"monitor_height_mm": 108.03, "gap_mm": 6.0,
	}, scale)
	var half_extents: Vector3 = wall_bounds["half_extents"]
	assert(is_equal_approx(half_extents.x, WallGeometry.frustum_size_at_distance(camera, 7.0).x))
	viewport.queue_free()
	print("Combined display geometry tests passed")
	quit()
