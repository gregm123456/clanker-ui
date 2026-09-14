class_name SpinningCubeMovementController
extends RefCounted

const SpinningCubeBoundsStrategyScript = preload("res://scripts/spinning_cube_bounds_strategy.gd")

var tumble_speed: Vector3 = Vector3(1.2, 1.8, 0.9)
var move_velocity: Vector3 = Vector3(2.2, 1.4, 0.0)
var move_acceleration: Vector3 = Vector3.ZERO
var enable_wraparound: bool = true
var wrap_margin: float = 1.6
var bounds_mode: int = SpinningCubeBoundsStrategy.BoundsMode.WRAP_2D_VIEWPORT
var bounds_behavior: int = SpinningCubeBoundsStrategy.BoundsBehavior.WRAP
var bounds_volume_center: Vector3 = Vector3.ZERO
var bounds_volume_half_extents: Vector3 = Vector3(8.0, 4.5, 4.0)

var _bounds_strategy := SpinningCubeBoundsStrategyScript.new()

func set_legacy_planar_velocity(legacy_velocity: Vector2) -> void:
	move_velocity = Vector3(legacy_velocity.x, legacy_velocity.y, move_velocity.z)

func randomize_speed_and_velocity() -> void:
	tumble_speed = Vector3(
		tumble_speed.x * randf_range(0.5, 2.0),
		tumble_speed.y * randf_range(0.5, 2.0),
		tumble_speed.z * randf_range(0.01, 2.0)
	)
	move_velocity = Vector3(
		move_velocity.x * randf_range(0.01, 4.0),
		move_velocity.y * randf_range(0.1, 1.5),
		move_velocity.z * randf_range(0.1, 1.5)
	)

func process_transform(target: Node3D, delta: float, camera: Camera3D, viewport: Viewport) -> Camera3D:
	target.rotate_x(tumble_speed.x * delta)
	target.rotate_y(tumble_speed.y * delta)
	target.rotate_z(tumble_speed.z * delta)

	move_velocity += move_acceleration * delta
	target.position += move_velocity * delta

	if enable_wraparound:
		return _bounds_strategy.apply_bounds(
			target,
			camera,
			viewport,
			wrap_margin,
			bounds_mode,
			bounds_behavior,
			bounds_volume_center,
			bounds_volume_half_extents
		)

	return camera

func handle_viewport_size_changed(target: Node3D, camera: Camera3D, viewport: Viewport) -> Camera3D:
	if enable_wraparound:
		return _bounds_strategy.apply_bounds(
			target,
			camera,
			viewport,
			wrap_margin,
			bounds_mode,
			bounds_behavior,
			bounds_volume_center,
			bounds_volume_half_extents
		)

	return camera
