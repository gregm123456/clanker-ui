#ifndef CSI_CAMERA_H
#define CSI_CAMERA_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/string.hpp>

#include <cstdint>
#include <mutex>
#include <vector>

struct _GstElement;
struct _GstSample;
struct _GstAppSink;

namespace godot {

class CsiCamera : public RefCounted {
	GDCLASS(CsiCamera, RefCounted)

private:
	_GstElement *_pipeline = nullptr;
	_GstElement *_appsink = nullptr;
	mutable std::mutex frame_mutex;
	std::vector<uint8_t> frame_bytes;
	uint64_t frame_number = 0;
	int frame_width = 0;
	int frame_height = 0;
	int frame_stride = 0;
	bool logged_first_sample = false;
	String last_error;
	bool running = false;

	static void _bind_methods();
	void _set_error(const String &message);
	bool _pull_sample(bool blocking = false);

public:
	CsiCamera() = default;
	~CsiCamera() override;

	bool start(int width = 960, int height = 540, int fps = 30, const String &camera_name = String());
	void stop();
	bool poll();
	bool is_running() const;
	bool has_new_frame(uint64_t last_seen_frame) const;
	PackedByteArray get_frame();
	int get_frame_width() const;
	int get_frame_height() const;
	uint64_t get_frame_number() const;
	String get_last_error() const;
};

} // namespace godot

#endif
