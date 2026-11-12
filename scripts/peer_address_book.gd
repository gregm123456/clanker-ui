class_name PeerAddressBook
extends RefCounted

var _entries: Dictionary = {}
var _resolved_addresses: Dictionary = {}
var _next_retry_usec: Dictionary = {}
var _retry_interval_usec: int = 2_000_000
const PATH_TIMEOUT_USEC := 3_000_000
const PROBE_INTERVAL_USEC := 1_000_000
const RETRY_DELAY_USEC := 1_000_000
var _paths: Dictionary = {}

func configure(peers: Dictionary, default_port: int) -> void:
	_entries.clear()
	_resolved_addresses.clear()
	_next_retry_usec.clear()
	for path in _paths.values():
		_cancel_lookup(path)
	_paths.clear()
	for peer_id_variant in peers.keys():
		var peer_id := String(peer_id_variant)
		var entry: Dictionary = peers.get(peer_id_variant, {})
		if entry.has("candidates"):
			var candidates: Array = entry["candidates"]
			if not peer_id.is_empty() and not candidates.is_empty():
				_entries[peer_id] = entry.duplicate(true)
				_paths[peer_id] = {
					"candidates": candidates.duplicate(true), "index": 0,
					"started": -1, "query": -1, "address": "",
					"nonces": {}, "last_probe": -1, "last_ack": 0,
					"active": false, "retry_at": 0, "last_failure_log": -30_000_000
				}
			continue
		var host := String(entry.get("host", "")).strip_edges()
		if host.is_empty() or peer_id.is_empty():
			continue
		_entries[peer_id] = {
			"host": host,
			"port": int(entry.get("port", default_port)) if int(entry.get("port", default_port)) > 0 else default_port
		}

func get_peer_ids() -> Array[String]:
	var peer_ids: Array[String] = []
	for peer_id_variant in _entries.keys():
		peer_ids.append(String(peer_id_variant))
	return peer_ids

func resolve_peer(peer_id: String) -> Dictionary:
	if not _entries.has(peer_id):
		return {}
	if _paths.has(peer_id):
		var path: Dictionary = _paths[peer_id]
		if not bool(path["active"]):
			return {}
		var candidate: Dictionary = path["candidates"][path["index"]]
		return {"peer_id": peer_id, "host": candidate["host"], "address": path["address"], "port": candidate["port"]}
	if _resolved_addresses.has(peer_id):
		return _resolved_addresses[peer_id].duplicate()
	var now_usec := Time.get_ticks_usec()
	if _next_retry_usec.has(peer_id) and now_usec < int(_next_retry_usec[peer_id]):
		return {}

	var entry: Dictionary = _entries[peer_id]
	var host := String(entry.get("host", ""))
	var address := host
	if not _is_ipv4_address(host):
		address = IP.resolve_hostname(host, IP.TYPE_IPV4)
		if address.is_empty():
			print("[peer_address_book] Unable to resolve peer ", peer_id, " (", host, ")")
			_next_retry_usec[peer_id] = now_usec + _retry_interval_usec
			return {}

	var resolved := {"peer_id": peer_id, "host": host, "address": address, "port": int(entry.get("port", 9000))}
	_resolved_addresses[peer_id] = resolved
	_next_retry_usec.erase(peer_id)
	return resolved.duplicate()

func path_probes(now_usec: int) -> Array:
	var probes: Array = []
	for peer_id in _paths:
		var path: Dictionary = _paths[peer_id]
		if now_usec < int(path["retry_at"]):
			continue
		if bool(path["active"]) and now_usec - int(path["last_ack"]) >= PATH_TIMEOUT_USEC:
			print("[peer_address_book] Path to ", peer_id, " timed out; retrying preferred paths")
			_reset_path(path, 0)
		if int(path["started"]) < 0:
			path["started"] = now_usec
			var candidate: Dictionary = path["candidates"][path["index"]]
			var host := String(candidate["host"])
			if _is_ipv4_address(host):
				path["address"] = host
			else:
				path["query"] = IP.resolve_hostname_queue_item(host, IP.TYPE_IPV4)
				if int(path["query"]) == IP.RESOLVER_INVALID_ID:
					print("[peer_address_book] Unable to queue DNS lookup for ", peer_id, " (", host, ")")
					_advance_path(peer_id, path, now_usec)
					continue
		if not bool(path["active"]) and now_usec - int(path["started"]) >= PATH_TIMEOUT_USEC:
			_log_failure(path, now_usec, "No path acknowledgement for %s candidate %s (unreachable, asymmetric, or older peer)" % [peer_id, path["index"]])
			_advance_path(peer_id, path, now_usec)
			continue
		if int(path["query"]) != -1:
			var status := IP.get_resolve_item_status(int(path["query"]))
			if status == IP.RESOLVER_STATUS_DONE:
				path["address"] = IP.get_resolve_item_address(int(path["query"]))
				_cancel_lookup(path)
				if String(path["address"]).is_empty():
					_advance_path(peer_id, path, now_usec)
					continue
			elif status == IP.RESOLVER_STATUS_ERROR:
				_log_failure(path, now_usec, "DNS lookup failed for %s candidate %s" % [peer_id, path["index"]])
				_advance_path(peer_id, path, now_usec)
				continue
		if not String(path["address"]).is_empty() and (int(path["last_probe"]) < 0 or now_usec - int(path["last_probe"]) >= PROBE_INTERVAL_USEC):
			var nonces: Dictionary = path["nonces"]
			for previous_nonce in nonces.keys():
				if now_usec - int(nonces[previous_nonce]) >= PATH_TIMEOUT_USEC:
					nonces.erase(previous_nonce)
			var nonce := Crypto.new().generate_random_bytes(16).hex_encode()
			if nonce.is_empty():
				push_error("[peer_address_book] Could not generate path probe nonce")
				continue
			nonces[nonce] = now_usec
			path["last_probe"] = now_usec
			var candidate: Dictionary = path["candidates"][path["index"]]
			probes.append({"peer_id": peer_id, "address": path["address"], "port": candidate["port"], "nonce": nonce})
	return probes

func acknowledge_path(peer_id: String, address: String, port: int, nonce: String, now_usec: int) -> void:
	if not _paths.has(peer_id):
		return
	var path: Dictionary = _paths[peer_id]
	var candidate: Dictionary = path["candidates"][path["index"]]
	var nonces: Dictionary = path["nonces"]
	if not nonces.has(nonce) or now_usec - int(nonces[nonce]) >= PATH_TIMEOUT_USEC or address != String(path["address"]) or port != int(candidate["port"]):
		return
	nonces.erase(nonce)
	if not bool(path["active"]):
		print("[peer_address_book] Path to ", peer_id, " active via ", candidate["host"], " (", address, ")")
	path["active"] = true
	path["last_ack"] = now_usec

func _advance_path(peer_id: String, path: Dictionary, now_usec: int) -> void:
	var next := int(path["index"]) + 1
	if next >= path["candidates"].size():
		_log_failure(path, now_usec, "All paths to %s unverified; retrying" % peer_id)
		_reset_path(path, 0)
		path["retry_at"] = now_usec + RETRY_DELAY_USEC
	else:
		_reset_path(path, next)

func _cancel_lookup(path: Dictionary) -> void:
	if int(path["query"]) != -1:
		IP.erase_resolve_item(int(path["query"]))
		path["query"] = -1

func _log_failure(path: Dictionary, now_usec: int, message: String) -> void:
	if now_usec - int(path["last_failure_log"]) >= 30_000_000:
		print("[peer_address_book] ", message)
		path["last_failure_log"] = now_usec

func _reset_path(path: Dictionary, index: int) -> void:
	_cancel_lookup(path)
	path["index"] = index
	path["started"] = -1
	path["address"] = ""
	path["nonces"] = {}
	path["last_probe"] = -1
	path["last_ack"] = 0
	path["active"] = false
	path["retry_at"] = 0

func invalidate(peer_id: String = "") -> void:
	if peer_id.is_empty():
		_resolved_addresses.clear()
		_next_retry_usec.clear()
		for path in _paths.values():
			_reset_path(path, 0)
	else:
		_resolved_addresses.erase(peer_id)
		_next_retry_usec.erase(peer_id)
		if _paths.has(peer_id):
			_reset_path(_paths[peer_id], 0)

func _is_ipv4_address(host: String) -> bool:
	var parts := host.split(".")
	if parts.size() != 4:
		return false
	for part in parts:
		if not part.is_valid_int() or int(part) < 0 or int(part) > 255:
			return false
	return true