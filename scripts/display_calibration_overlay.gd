extends Node2D

var image_size := Vector2i.ZERO

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(image_size)), Color(0.04, 0.04, 0.04))
	for x in range(0, image_size.x, 100):
		draw_line(Vector2(x, 0), Vector2(x, image_size.y), Color(0.4, 0.4, 0.4))
	for y in range(0, image_size.y, 100):
		draw_line(Vector2(0, y), Vector2(image_size.x, y), Color(0.4, 0.4, 0.4))
	draw_line(Vector2.ZERO, Vector2(image_size), Color(1.0, 0.2, 0.2), 3.0)
	draw_line(Vector2(image_size.x * 0.5, 0), Vector2(image_size.x * 0.5, image_size.y), Color(0.2, 0.8, 1.0), 2.0)
