class_name FacePortraitOverlay
extends CanvasLayer

const JIGGLE_PIXELS := 10.0
const PORTRAIT_SCALE := 1.5

var max_portraits: int = 4
var _root: Control
var _portraits: Array = []
var _elapsed := 0.0

func _ready() -> void:
	layer = 10
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_update_display_geometry()

func add_faces(faces: Array, capture_order: int) -> void:
	for index in faces.size():
		var face: Dictionary = faces[index]
		var image: Image = face["image"]
		var portrait := Control.new()
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait.size = Vector2(image.get_width(), image.get_height()) * PORTRAIT_SCALE
		var picture := TextureRect.new()
		picture.texture = ImageTexture.create_from_image(image)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.size = portrait.size
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait.add_child(picture)
		var label := Label.new()
		label.text = String(face["label"])
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.position = Vector2(2.0, maxf(0.0, portrait.size.y - 24.0))
		var background := StyleBoxFlat.new()
		background.bg_color = Color(0.0, 0.0, 0.0, 0.75)
		label.add_theme_stylebox_override("normal", background)
		portrait.add_child(label)
		_root.add_child(portrait)
		var available := (_root.size - portrait.size).max(Vector2.ZERO)
		_portraits.append({
			"node": portrait,
			"order": capture_order,
			"index": index,
			"anchor": Vector2(randf() * available.x, randf() * available.y),
			"phase": Vector2(randf_range(0.0, TAU), randf_range(0.0, TAU)),
			"speed": Vector2(
				randf_range(0.8, 30.0),
				randf_range(0.8, 30.0)
			),
		})
	_portraits.sort_custom(_older_first)
	while _portraits.size() > maxi(max_portraits, 1):
		var oldest: Dictionary = _portraits.pop_front()
		oldest["node"].queue_free()

func _older_first(a: Dictionary, b: Dictionary) -> bool:
	return int(a["order"]) < int(b["order"]) or (int(a["order"]) == int(b["order"]) and int(a["index"]) < int(b["index"]))

func _process(delta: float) -> void:
	if _root == null:
		return
	_update_display_geometry()
	_elapsed += delta
	for entry: Dictionary in _portraits:
		var portrait: Control = entry["node"]
		var available := (_root.size - portrait.size).max(Vector2.ZERO)
		var anchor: Vector2 = entry["anchor"]
		anchor = anchor.clamp(Vector2.ZERO, available)
		entry["anchor"] = anchor
		var phase: Vector2 = entry["phase"]
		var speed: Vector2 = entry["speed"]
		var jiggle := Vector2(sin(_elapsed * speed.x + phase.x), sin(_elapsed * speed.y + phase.y)) * JIGGLE_PIXELS
		portrait.position = (anchor + jiggle).clamp(Vector2.ZERO, available)

func _update_display_geometry() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var screen_transform := viewport.get_screen_transform()
	if is_zero_approx(screen_transform.determinant()):
		push_warning("[face] Invalid display transform")
		return
	transform = screen_transform.affine_inverse()
	if viewport is Window:
		_root.size = Vector2((viewport as Window).size)
	else:
		_root.size = viewport.get_visible_rect().size
