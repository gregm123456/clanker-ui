extends Node

const ATTEMPT_TIMEOUT_USEC := 3_000_000
const PROBE_INTERVAL_USEC := 2_000_000
const RETRY_DELAY_USEC := 1_000_000

var _endpoints: Array[Dictionary] = []
var _index := 0
var _query := -1
var _stream: StreamPeerTCP
var _attempt_started := -1
var _next_attempt := 0
var _selected := false
var _address := ""
var _selected_address := ""
var _last_failure_log := -30_000_000

func configure(urls: Array) -> Error:
	var endpoints: Array[Dictionary] = []
	for value in urls:
		if typeof(value) != TYPE_STRING:
			push_error("[http_path] Endpoint must be a URL string")
			return ERR_INVALID_PARAMETER
		var url := String(value)
		if not url.begins_with("http://"):
			push_error("[http_path] Only explicit HTTP endpoints are supported: " + url)
			return ERR_INVALID_PARAMETER
		var authority := url.trim_prefix("http://").get_slice("/", 0)
		var host := authority.get_slice(":", 0)
		var port := 80
		if authority.count(":") > 1 or host.is_empty() or authority.contains("@") or authority.contains("?") or authority.contains("#"):
			push_error("[http_path] Invalid endpoint: " + url)
			return ERR_INVALID_PARAMETER
		if authority.contains(":"):
			var port_string := authority.get_slice(":", 1)
			if not port_string.is_valid_int():
				push_error("[http_path] Invalid port in " + url)
				return ERR_INVALID_PARAMETER
			port = int(port_string)
		if port < 1 or port > 65535:
			push_error("[http_path] Invalid port in " + url)
			return ERR_INVALID_PARAMETER
		endpoints.append({"url": url, "host": host, "port": port})
	if endpoints.is_empty():
		push_error("[http_path] No valid endpoints configured")
		return ERR_INVALID_PARAMETER
	_endpoints = endpoints
	return OK

func selected_url() -> String:
	if not _selected or _endpoints.is_empty():
		return ""
	return String(_endpoints[_index]["url"])

func selected_address() -> String:
	return _selected_address if _selected else ""

func report_connection_failure(url: String) -> void:
	if _selected and selected_url() == url:
		print("[http_path] Connection failed for ", url, "; retrying preferred endpoints")
		_reset_attempt()
		_selected = false
		_index = 0
		_next_attempt = 0

func _process(_delta: float) -> void:
	_tick(Time.get_ticks_usec())

func _tick(now: int) -> void:
	if _endpoints.is_empty() or now < _next_attempt:
		return
	if _attempt_started < 0:
		_attempt_started = now
		_address = ""
		var host := String(_endpoints[_index]["host"])
		if host.is_valid_ip_address():
			_address = host
		else:
			_query = IP.resolve_hostname_queue_item(host, IP.TYPE_IPV4)
			if _query == IP.RESOLVER_INVALID_ID:
				_failed(now, "DNS lookup could not start")
				return
	if now - _attempt_started >= ATTEMPT_TIMEOUT_USEC:
		_failed(now, "DNS or connection timed out")
		return
	if _query != -1:
		var status := IP.get_resolve_item_status(_query)
		if status == IP.RESOLVER_STATUS_ERROR:
			_failed(now, "DNS lookup failed")
			return
		if status != IP.RESOLVER_STATUS_DONE:
			return
		_address = IP.get_resolve_item_address(_query)
		IP.erase_resolve_item(_query)
		_query = -1
		if _address.is_empty():
			_failed(now, "DNS returned no address")
			return
	if _stream == null:
		_stream = StreamPeerTCP.new()
		var error := _stream.connect_to_host(_address, int(_endpoints[_index]["port"]))
		if error != OK:
			_failed(now, "TCP connect failed: %s" % error)
			return
	_stream.poll()
	var state := _stream.get_status()
	if state == StreamPeerTCP.STATUS_CONNECTED:
		if not _selected:
			print("[http_path] Selected ", _endpoints[_index]["url"], " via ", _address)
		_selected = true
		_selected_address = _address
		_reset_attempt()
		_next_attempt = now + PROBE_INTERVAL_USEC
	elif state == StreamPeerTCP.STATUS_ERROR or state == StreamPeerTCP.STATUS_NONE:
		_failed(now, "TCP connection failed")

func _failed(now: int, reason: String) -> void:
	if _selected or now - _last_failure_log >= 30_000_000:
		print("[http_path] ", reason, ": ", _endpoints[_index]["url"])
		_last_failure_log = now
	_reset_attempt()
	if _selected:
		_selected = false
		_index = 0
	else:
		_index += 1
		if _index >= _endpoints.size():
			_index = 0
			_next_attempt = now + RETRY_DELAY_USEC

func _reset_attempt() -> void:
	if _query != -1:
		IP.erase_resolve_item(_query)
		_query = -1
	if _stream != null:
		_stream.disconnect_from_host()
		_stream = null
	_attempt_started = -1

func _exit_tree() -> void:
	_reset_attempt()
