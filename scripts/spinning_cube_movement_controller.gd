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
var floating_portrait: bool = false

var _bounds_strategy := SpinningCubeBoundsStrategyScript.new()
var _portrait_elapsed := 0.0
var _portrait_origin_z := 0.0
var _portrait_base_rotation := Vector3.ZERO
var _portrait_phase := 0.0

const PORTRAIT_HOLD_SECONDS := 6.0
const PORTRAIT_TRAVEL_SECONDS := 1.5
const PORTRAIT_EXIT_DISTANCE := 10.0

func initialize_portrait(target: Node3D) -> void:
	_portrait_origin_z = target.global_position.z
	_portrait_base_rotation = target.rotation
	_portrait_phase = randf_range(0.0, TAU)

func configure_shared_screen(camera: Camera3D, virtual_size: Vector2i) -> bool:
	return _bounds_strategy.configure_shared_screen(camera, virtual_size)

func set_legacy_planar_velocity(legacy_velocity: Vector2) -> void:
	move_velocity = Vector3(legacy_velocity.x, legacy_velocity.y, move_velocity.z)

func randomize_speed_and_velocity() -> void:
	if floating_portrait:
		move_velocity.x *= randf_range(0.7, 1.2)
		move_velocity.y *= randf_range(0.7, 1.2)
		return
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
	if floating_portrait:
		_process_portrait(target, delta)
	else:
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
			bounds_volume_half_extents,
			move_velocity
		)

	return camera

func _process_portrait(target: Node3D, delta: float) -> void:
	var cycle_duration := PORTRAIT_HOLD_SECONDS + 2.0 * PORTRAIT_TRAVEL_SECONDS
	_portrait_elapsed += delta
	var cycle_time := fposmod(_portrait_elapsed, cycle_duration)
	var wobble_time := _portrait_elapsed + _portrait_phase
	target.rotation = _portrait_base_rotation + Vector3(
		deg_to_rad(8.0) * sin(wobble_time * TAU / 8.0),
		deg_to_rad(20.0) * sin(wobble_time * TAU / 9.0 + _portrait_phase),
		deg_to_rad(5.0) * sin(wobble_time * TAU / 7.0 + _portrait_phase)
	)
	var depth_fraction := 0.0
	if cycle_time >= PORTRAIT_HOLD_SECONDS:
		if cycle_time < PORTRAIT_HOLD_SECONDS + PORTRAIT_TRAVEL_SECONDS:
			var progress := (cycle_time - PORTRAIT_HOLD_SECONDS) / PORTRAIT_TRAVEL_SECONDS
			depth_fraction = progress * progress
		else:
			var progress := (cycle_time - PORTRAIT_HOLD_SECONDS - PORTRAIT_TRAVEL_SECONDS) / PORTRAIT_TRAVEL_SECONDS
			depth_fraction = (1.0 - progress) * (1.0 - progress)
	target.position += Vector3(move_velocity.x, move_velocity.y, 0.0) * delta
	var world_position := target.global_position
	world_position.z = _portrait_origin_z - PORTRAIT_EXIT_DISTANCE * depth_fraction
	target.global_position = world_position

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
			bounds_volume_half_extents,
			move_velocity
		)

	return camera
