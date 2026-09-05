#include "csi_camera.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <gst/app/gstappsink.h>
#include <gst/gst.h>

#include <algorithm>
#include <cstring>

namespace godot {

void CsiCamera::_bind_methods() {
	ClassDB::bind_method(D_METHOD("start", "width", "height", "fps", "camera_name"), &CsiCamera::start, DEFVAL(960), DEFVAL(540), DEFVAL(30), DEFVAL(String()));
	ClassDB::bind_method(D_METHOD("stop"), &CsiCamera::stop);
	ClassDB::bind_method(D_METHOD("poll"), &CsiCamera::poll);
	ClassDB::bind_method(D_METHOD("is_running"), &CsiCamera::is_running);
	ClassDB::bind_method(D_METHOD("has_new_frame", "last_seen_frame"), &CsiCamera::has_new_frame);
	ClassDB::bind_method(D_METHOD("get_frame"), &CsiCamera::get_frame);
	ClassDB::bind_method(D_METHOD("get_frame_width"), &CsiCamera::get_frame_width);
	ClassDB::bind_method(D_METHOD("get_frame_height"), &CsiCamera::get_frame_height);
	ClassDB::bind_method(D_METHOD("get_frame_number"), &CsiCamera::get_frame_number);
	ClassDB::bind_method(D_METHOD("get_last_error"), &CsiCamera::get_last_error);
}

void CsiCamera::_set_error(const String &message) {
	last_error = message;
	UtilityFunctions::printerr(String("[csi_camera] ") + message);
}

bool CsiCamera::_pull_sample(bool blocking) {
	if (_appsink == nullptr) {
		return false;
	}

	GstSample *sample = blocking
			? gst_app_sink_pull_sample(GST_APP_SINK(_appsink))
			: gst_app_sink_try_pull_sample(GST_APP_SINK(_appsink), 5 * GST_MSECOND);
	if (sample == nullptr) {
		return false;
	}

	GstCaps *caps = gst_sample_get_caps(sample);
	GstBuffer *buffer = gst_sample_get_buffer(sample);
	GstStructure *structure = caps != nullptr ? gst_caps_get_structure(caps, 0) : nullptr;
	if (structure == nullptr || buffer == nullptr) {
		gst_sample_unref(sample);
		_set_error("appsink returned a sample without caps or buffer");
		return false;
	}
	if (!logged_first_sample) {
		UtilityFunctions::print("[csi_camera] first appsink sample received");
		logged_first_sample = true;
	}

	int width = 0;
	int height = 0;
	if (!gst_structure_get_int(structure, "width", &width) || !gst_structure_get_int(structure, "height", &height) || width <= 0 || height <= 0) {
		gst_sample_unref(sample);
		_set_error("appsink sample has invalid dimensions");
		return false;
	}

	GstMapInfo map;
	if (!gst_buffer_map(buffer, &map, GST_MAP_READ)) {
		gst_sample_unref(sample);
		_set_error("could not map appsink buffer");
		return false;
	}

	const size_t expected_size = static_cast<size_t>(width) * static_cast<size_t>(height) * 4U;
	if (map.size < expected_size) {
		gst_buffer_unmap(buffer, &map);
		gst_sample_unref(sample);
		_set_error("appsink RGBA buffer is smaller than the negotiated frame");
		return false;
	}

	{
		std::lock_guard<std::mutex> lock(frame_mutex);
		frame_bytes.assign(map.data, map.data + expected_size);
		frame_width = width;
		frame_height = height;
		frame_stride = width * 4;
		frame_number++;
	}

	gst_buffer_unmap(buffer, &map);
	gst_sample_unref(sample);
	return true;
}

bool CsiCamera::start(int width, int height, int fps, const String &camera_name) {
	stop();
	last_error = String();

	if (!gst_is_initialized()) {
		gst_init(nullptr, nullptr);
	}
	if (width <= 0 || height <= 0 || fps <= 0) {
		_set_error("invalid capture dimensions or frame rate");
		return false;
	}

	String pipeline_description = "libcamerasrc";
	if (!camera_name.is_empty()) {
		pipeline_description += " camera-name=\\\"" + camera_name + "\\\"";
	}
	pipeline_description += " ! video/x-raw,format=NV12,width=" + String::num_int64(width) + ",height=" + String::num_int64(height) + ",framerate=" + String::num_int64(fps) + "/1 ! videoconvert ! video/x-raw,format=RGBA ! appsink name=csi_sink emit-signals=false sync=false max-buffers=1 drop=true";

	GError *error = nullptr;
	_pipeline = gst_parse_launch(pipeline_description.utf8().get_data(), &error);
	if (_pipeline == nullptr) {
		String message = error != nullptr ? String(error->message) : String("could not create GStreamer pipeline");
		if (error != nullptr) {
			g_error_free(error);
		}
		_set_error(message);
		return false;
	}

	_appsink = gst_bin_get_by_name(GST_BIN(_pipeline), "csi_sink");
	if (_appsink == nullptr) {
		_set_error("GStreamer pipeline did not create appsink");
		stop();
		return false;
	}

	GstStateChangeReturn result = gst_element_set_state(_pipeline, GST_STATE_PLAYING);
	if (result == GST_STATE_CHANGE_FAILURE) {
		_set_error("GStreamer pipeline failed to enter PLAYING state");
		stop();
		return false;
	}

	running = true;
	UtilityFunctions::print("[csi_camera] started ", width, "x", height, " @ ", fps, " fps");
	return true;
}

void CsiCamera::stop() {
	running = false;
	if (_pipeline != nullptr) {
		gst_element_set_state(_pipeline, GST_STATE_NULL);
	}
	if (_appsink != nullptr) {
		gst_object_unref(_appsink);
		_appsink = nullptr;
	}
	if (_pipeline != nullptr) {
		gst_object_unref(_pipeline);
		_pipeline = nullptr;
	}
}

bool CsiCamera::poll() {
	return running && _pull_sample(false);
}

bool CsiCamera::is_running() const {
	return running;
}

bool CsiCamera::has_new_frame(uint64_t last_seen_frame) const {
	std::lock_guard<std::mutex> lock(frame_mutex);
	return frame_number > last_seen_frame;
}

PackedByteArray CsiCamera::get_frame() {
	std::lock_guard<std::mutex> lock(frame_mutex);
	PackedByteArray result;
	if (!frame_bytes.empty()) {
		result.resize(frame_bytes.size());
		std::memcpy(result.ptrw(), frame_bytes.data(), frame_bytes.size());
	}
	return result;
}

int CsiCamera::get_frame_width() const {
	std::lock_guard<std::mutex> lock(frame_mutex);
	return frame_width;
}

int CsiCamera::get_frame_height() const {
	std::lock_guard<std::mutex> lock(frame_mutex);
	return frame_height;
}

uint64_t CsiCamera::get_frame_number() const {
	std::lock_guard<std::mutex> lock(frame_mutex);
	return frame_number;
}

String CsiCamera::get_last_error() const {
	return last_error;
}

CsiCamera::~CsiCamera() {
	stop();
}

} // namespace godot
