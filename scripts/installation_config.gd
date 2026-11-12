class_name InstallationConfig
extends RefCounted

const TEMPLATE_PATH: String = "res://config/installation.template.cfg"
const CONFIG_PATH: String = "user://installation.cfg"

var _config: ConfigFile = ConfigFile.new()

func _init() -> void:
	_load_or_create()

func reload() -> void:
	_load_or_create()

func get_file_path() -> String:
	return ProjectSettings.globalize_path(CONFIG_PATH)

func get_node_id() -> String:
	return _get_string("node", "node_id", "local_display")

func get_peer_id() -> String:
	return _get_string("node", "peer_id", "local")

func get_display_settings() -> Dictionary:
	return {
		"combined_wall": _get_bool("display", "combined_wall", false),
		"left_screen": int(_get_number("display", "left_screen", -1)),
		"right_screen": int(_get_number("display", "right_screen", -1)),
	}

func get_shared_screen_wrap_settings() -> Dictionary:
	return {
		"enabled": _get_bool("shared_screen_wrap", "enabled", false),
		"panel_width_px": int(_get_number("shared_screen_wrap", "panel_width_px", 0)),
		"panel_height_px": int(_get_number("shared_screen_wrap", "panel_height_px", 0)),
	}

func get_wall_layout() -> Dictionary:
	return {
		"columns": int(_get_number("wall", "columns", 2)),
		"rows": int(_get_number("wall", "rows", 1)),
		"monitor_width_mm": float(_get_number("wall", "monitor_width_mm", 168.0)),
		"monitor_height_mm": float(_get_number("wall", "monitor_height_mm", 300.0)),
		"gap_mm": float(_get_number("wall", "gap_mm", 5.0)),
		"this_node_column": int(_get_number("wall", "this_node_column", 0)),
		"this_node_row": int(_get_number("wall", "this_node_row", 0)),
		"rotation_z_degrees": float(_get_number("wall", "rotation_z_degrees", 0.0)),
	}

func get_network_settings() -> Dictionary:
	return {
		"mode": _get_string("network", "mode", "broadcast").to_lower(),
		"udp_port": int(_get_number("network", "udp_port", 9000)),
		"broadcast_address": _get_string("network", "broadcast_address", "255.255.255.255"),
		"snapshot_tcp_port": int(_get_number("network", "snapshot_tcp_port", 9010)),
		"heartbeat_interval_sec": float(_get_number("network", "heartbeat_interval_sec", 2.0)),
		"peer_timeout_sec": float(_get_number("network", "peer_timeout_sec", 15.0)),
	}

func get_peers() -> Dictionary:
	var peers: Dictionary = {}
	if not _config.has_section("peers"):
		return peers
	var section_keys := _config.get_section_keys("peers")
	for key in section_keys:
		var raw_value: Variant = _config.get_value("peers", key, "")
		if typeof(raw_value) == TYPE_ARRAY or typeof(raw_value) == TYPE_PACKED_STRING_ARRAY:
			var candidates: Array = []
			for item in raw_value:
				if typeof(item) != TYPE_STRING:
					push_error("[installation_config] Peer %s has a non-string endpoint" % key)
					candidates.clear()
					break
				var candidate := _parse_peer_entry(item)
				if candidate.is_empty():
					push_error("[installation_config] Invalid endpoint for peer %s: %s" % [key, item])
					candidates.clear()
					break
				candidates.append(candidate)
			if candidates.is_empty():
				push_error("[installation_config] Peer %s has no valid endpoints" % key)
			else:
				peers[String(key)] = {"candidates": candidates}
		else:
			var peer_entry := _parse_peer_entry(String(raw_value))
			if peer_entry.is_empty():
				push_error("[installation_config] Invalid endpoint for peer %s" % key)
			else:
				peers[String(key)] = peer_entry
	return peers

func get_camera_settings() -> Dictionary:
	return {
		"feed_index": int(_get_number("camera", "feed_index", 0)),
		"prefer_csi_camera": _get_bool("camera", "prefer_csi_camera", true),
		"csi_camera_width": int(_get_number("camera", "csi_camera_width", 960)),
		"csi_camera_height": int(_get_number("camera", "csi_camera_height", 540)),
		"csi_camera_fps": int(_get_number("camera", "csi_camera_fps", 30)),
		"csi_camera_name": _get_string("camera", "csi_camera_name", ""),
		"csi_rotate_180": _get_bool("camera", "csi_rotate_180", false),
		"fit_mode": int(_get_number("camera", "webcam_fit_mode", 0)),
		"flip_horizontal": _get_bool("camera", "flip_webcam_horizontal", true),
	}

func get_face_settings() -> Dictionary:
	return {
		"service_url": _get_string("faces", "service_url", "http://pi5ai2sd:5002/v1/attributes"),
		"service_urls": _get_urls("faces", "service_urls"),
		"max_portraits": int(_get_number("faces", "max_portraits", 10)),
	}

func get_speech_settings() -> Dictionary:
	return {
		"interrogation_url": _get_string("speech", "interrogation_url", "http://m5image:5000"),
		"tts_url": _get_string("speech", "tts_url", "http://pi5ai2sd:5003/v1/audio/speech"),
		"interrogation_urls": _get_urls("speech", "interrogation_urls"),
		"tts_urls": _get_urls("speech", "tts_urls"),
		"max_jobs": int(_get_number("speech", "max_jobs", 5)),
		"flat_interrogation_enabled": _get_bool("speech", "flat_interrogation_enabled", false),
	}

func _load_or_create() -> void:
	var resolved_path := ProjectSettings.globalize_path(CONFIG_PATH)
	var file_exists := FileAccess.file_exists(resolved_path)
	if not file_exists:
		_write_default_config(resolved_path)
		print("[installation_config] Created default config at ", resolved_path)

	var error: Error = _config.load(CONFIG_PATH)
	if error != OK:
		print("[installation_config] Failed to load config ", CONFIG_PATH, " (error=", error, ")")
		return
	if not file_exists:
		print("[installation_config] Loaded default config from ", resolved_path)
	else:
		print("[installation_config] Loaded config from ", resolved_path)

func _write_default_config(resolved_path: String) -> void:
	var template := FileAccess.get_file_as_string(TEMPLATE_PATH)
	if template.is_empty():
		template = _generate_default_template()
	var base_dir := resolved_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(base_dir):
		DirAccess.make_dir_recursive_absolute(base_dir)
	var config_file := FileAccess.open(resolved_path, FileAccess.ModeFlags.WRITE)
	if config_file == null:
		print("[installation_config] Unable to write config file at ", resolved_path)
		return
	config_file.store_string(template)
	config_file.flush()
	config_file.close()

func _generate_default_template() -> String:
	return """
[node]
node_id = "local_display"
peer_id = "local"

[display]
combined_wall = false
left_screen = -1
right_screen = -1

[shared_screen_wrap]
enabled = false
panel_width_px = 600
panel_height_px = 1024

[wall]
columns = 2
rows = 1
monitor_width_mm = 168.0
monitor_height_mm = 300.0
gap_mm = 5.0
this_node_column = 0
this_node_row = 0
rotation_z_degrees = 0.0

[network]
mode = "broadcast"
udp_port = 9000
broadcast_address = "255.255.255.255"
snapshot_tcp_port = 9010
heartbeat_interval_sec = 2.0
peer_timeout_sec = 15.0

[peers]
; Example entries:
; pi_right = "192.168.1.42:9000"
; pi_office = "pi-office.tail123.ts.net:9000"
; pi_remote = ["pi-remote.tail123.ts.net:9000", "pi-remote.local:9000", "192.168.77.46:9000"]

[camera]
feed_index = 0
prefer_csi_camera = true
csi_camera_width = 960
csi_camera_height = 540
csi_camera_fps = 30
csi_camera_name = ""
csi_rotate_180 = false
webcam_fit_mode = 0
flip_webcam_horizontal = true

[faces]
service_url = "http://pi5ai2sd:5002/v1/attributes"
; service_urls = ["http://pi5ai2sd.tail123.ts.net:5002/v1/attributes", "http://pi5ai2sd.local:5002/v1/attributes", "http://192.168.77.1:5002/v1/attributes"]
max_portraits = 10

[speech]
interrogation_url = "http://m5image:5000"
tts_url = "http://pi5ai2sd:5003/v1/audio/speech"
; interrogation_urls = ["http://m5image.tail123.ts.net:5000", "http://m5image.local:5000", "http://192.168.77.46:5000"]
; tts_urls = ["http://pi5ai2sd.tail123.ts.net:5003/v1/audio/speech", "http://pi5ai2sd.local:5003/v1/audio/speech", "http://192.168.77.1:5003/v1/audio/speech"]
max_jobs = 5
flat_interrogation_enabled = false
""".strip_edges()

func _get_string(section: String, key: String, default_value: String) -> String:
	var value = _config.get_value(section, key, default_value)
	if value == null:
		return default_value
	return String(value)

func _get_urls(section: String, key: String) -> Variant:
	var urls: Array[String] = []
	if not _config.has_section_key(section, key):
		return null
	var raw: Variant = _config.get_value(section, key)
	if typeof(raw) != TYPE_ARRAY and typeof(raw) != TYPE_PACKED_STRING_ARRAY:
		push_error("[installation_config] %s.%s must be an array of URLs" % [section, key])
		return urls
	for value in raw:
		if typeof(value) != TYPE_STRING or not String(value).begins_with("http://") or String(value).trim_prefix("http://").get_slice("/", 0).is_empty():
			push_error("[installation_config] Invalid HTTP URL in %s.%s" % [section, key])
			return []
		urls.append(value)
	if urls.is_empty():
		push_error("[installation_config] %s.%s must not be empty" % [section, key])
	return urls

func _get_number(section: String, key: String, default_value: float) -> float:
	var value = _config.get_value(section, key, default_value)
	if value == null:
		return float(default_value)
	if typeof(value) == TYPE_STRING:
		return float(String(value))
	return float(value)

func _get_bool(section: String, key: String, default_value: bool) -> bool:
	var value = _config.get_value(section, key, default_value)
	if value == null:
		return default_value
	return bool(value)

func _parse_peer_entry(raw_value: String) -> Dictionary:
	var normalized := raw_value.strip_edges()
	if normalized.is_empty():
		return {}
	var host := normalized
	var port := 9000
	if normalized.count(":") > 0:
		if normalized.count(":") != 1:
			return {}
		var split_index := normalized.rfind(":")
		var maybe_port := normalized.substr(split_index + 1)
		if not maybe_port.is_valid_int():
			return {}
		host = normalized.substr(0, split_index).strip_edges()
		port = int(maybe_port)
	if host.is_empty() or port < 1 or port > 65535:
		return {}
	return {
		"host": host,
		"port": port,
	}
