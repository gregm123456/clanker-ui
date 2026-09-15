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

func get_wall_layout() -> Dictionary:
	return {
		"columns": int(_get_number("wall", "columns", 2)),
		"rows": int(_get_number("wall", "rows", 1)),
		"monitor_width_mm": float(_get_number("wall", "monitor_width_mm", 168.0)),
		"monitor_height_mm": float(_get_number("wall", "monitor_height_mm", 300.0)),
		"gap_mm": float(_get_number("wall", "gap_mm", 5.0)),
		"this_node_column": int(_get_number("wall", "this_node_column", 0)),
		"this_node_row": int(_get_number("wall", "this_node_row", 0)),
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
	var section_keys := _config.get_section_keys("peers")
	for key in section_keys:
		var raw_value: Variant = _config.get_value("peers", key, "")
		var peer_entry := _parse_peer_entry(String(raw_value))
		if peer_entry.is_empty():
			continue
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
		"fit_mode": int(_get_number("camera", "webcam_fit_mode", 0)),
		"flip_horizontal": _get_bool("camera", "flip_webcam_horizontal", true),
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

[wall]
columns = 2
rows = 1
monitor_width_mm = 168.0
monitor_height_mm = 300.0
gap_mm = 5.0
this_node_column = 0
this_node_row = 0

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

[camera]
feed_index = 0
prefer_csi_camera = true
csi_camera_width = 960
csi_camera_height = 540
csi_camera_fps = 30
csi_camera_name = ""
webcam_fit_mode = 0
flip_webcam_horizontal = true
""".strip_edges()

func _get_string(section: String, key: String, default_value: String) -> String:
	var value = _config.get_value(section, key, default_value)
	if value == null:
		return default_value
	return String(value)

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
		var split_index := normalized.rfind(":")
		var maybe_port := normalized.substr(split_index + 1)
		if maybe_port.is_valid_int():
			host = normalized.substr(0, split_index)
			port = int(maybe_port)
	return {
		"host": host,
		"port": port,
	}
