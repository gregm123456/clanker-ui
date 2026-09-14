class_name InstallationGeometry
extends Resource

## World axis convention for movement:
## +X = right, +Y = up, +Z = toward camera (camera looks along -Z).
## Bounds are evaluated in world space against this installation box.
@export var world_bounds_center: Vector3 = Vector3.ZERO
@export var world_bounds_half_extents: Vector3 = Vector3(8.0, 4.5, 4.0)
