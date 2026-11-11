extends SceneTree

const Adapter = preload("res://scripts/webcam_camera_source_adapter.gd")

class FakeProvider:
	extends "res://addons/csi_camera/scripts/csi_camera_provider.gd"
	var image: Image

	func get_image() -> Image:
		return image

func _initialize() -> void:
	var image := Image.create_empty(2, 2, false, Image.FORMAT_RGBA8)
	image.set_pixel(0, 0, Color.RED)
	image.set_pixel(1, 0, Color.GREEN)
	image.set_pixel(0, 1, Color.BLUE)
	image.set_pixel(1, 1, Color.WHITE)
	var provider := FakeProvider.new()
	provider.image = image
	var adapter = Adapter.new()
	adapter._csi_provider = provider
	assert(adapter.get_current_frame_image() == image)
	adapter.csi_rotate_180 = true
	var rotated: Image = adapter.get_current_frame_image()
	assert(rotated.get_pixel(0, 0).is_equal_approx(Color.WHITE))
	assert(rotated.get_pixel(1, 0).is_equal_approx(Color.BLUE))
	assert(rotated.get_pixel(0, 1).is_equal_approx(Color.GREEN))
	assert(rotated.get_pixel(1, 1).is_equal_approx(Color.RED))
	assert(image.get_pixel(0, 0).is_equal_approx(Color.RED))
	provider.image = null
	assert(adapter.get_current_frame_image() == null)
	print("CSI rotation tests passed")
	quit()
