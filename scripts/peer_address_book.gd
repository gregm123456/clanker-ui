class_name PeerAddressBook
extends RefCounted

var _entries: Dictionary = {}
var _resolved_addresses: Dictionary = {}
var _next_retry_usec: Dictionary = {}
var _retry_interval_usec: int = 2_000_000

func configure(peers: Dictionary, default_port: int) -> void:
	_entries.clear()
	_resolved_addresses.clear()
	_next_retry_usec.clear()
	for peer_id_variant in peers.keys():
		var peer_id := String(peer_id_variant)
		var entry: Dictionary = peers.get(peer_id_variant, {})
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

func invalidate(peer_id: String = "") -> void:
	if peer_id.is_empty():
		_resolved_addresses.clear()
		_next_retry_usec.clear()
	else:
		_resolved_addresses.erase(peer_id)
		_next_retry_usec.erase(peer_id)

func _is_ipv4_address(host: String) -> bool:
	var parts := host.split(".")
	if parts.size() != 4:
		return false
	for part in parts:
		if not part.is_valid_int() or int(part) < 0 or int(part) > 255:
			return false
	return true