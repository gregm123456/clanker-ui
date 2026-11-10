class_name CombinedDisplayGeometry
extends RefCounted

static func calculate(first: Rect2i, second: Rect2i, panel_width_mm: float, gap_mm: float) -> Dictionary:
	if not is_finite(panel_width_mm) or not is_finite(gap_mm) or panel_width_mm <= 0.0 or gap_mm < 0.0:
		return {}
	if first.size.x <= 0 or first.size.y <= 0 or first.size != second.size:
		return {}
	var left := first
	var right := second
	if left.position.x > right.position.x:
		left = second
		right = first
	if left.position.y != right.position.y or left.end.x != right.position.x:
		return {}

	var gap_pixels := roundi(float(left.size.x) * gap_mm / panel_width_mm)
	var window := left.merge(right)
	return {
		"window": window,
		"panel_size": left.size,
		"gap_pixels": gap_pixels,
		"virtual_size": Vector2i(window.size.x + gap_pixels, window.size.y),
		"left_region": Rect2i(Vector2i.ZERO, left.size),
		"right_region": Rect2i(Vector2i(left.size.x + gap_pixels, 0), right.size),
	}
