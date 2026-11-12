extends SceneTree

const AddressBook = preload("res://scripts/peer_address_book.gd")
const Transport = preload("res://scripts/udp_mesh_transport.gd")
const Config = preload("res://scripts/installation_config.gd")
const HttpSelector = preload("res://scripts/http_path_selector.gd")
const SnapshotClient = preload("res://scripts/webcam_snapshot_client.gd")
const SnapshotServer = preload("res://scripts/webcam_snapshot_server.gd")

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		failures += 1

func _run() -> void:
	_test_selection()
	_test_config()
	await _test_udp()
	await _test_legacy_peer()
	await _test_tcp()
	await _test_snapshot()
	if failures == 0:
		print("Path selection tests passed")
	quit(1 if failures else 0)

func _test_selection() -> void:
	var book = AddressBook.new()
	book.configure({"peer": {"candidates": [
		{"host": "127.0.0.1", "port": 9000},
		{"host": "127.0.0.2", "port": 9000}
	]}}, 9000)
	var probes: Array = book.path_probes(1)
	var nonce: String = probes[0]["nonce"]
	book.acknowledge_path("peer", "127.0.0.2", 9000, nonce, 2)
	_check(book.resolve_peer("peer").is_empty(), "An acknowledgement from a different path was accepted")
	book.path_probes(3_000_001)
	probes = book.path_probes(3_000_002)
	_check(probes.size() == 1 and probes[0]["address"] == "127.0.0.2", "Fallback was not attempted after three seconds")
	book.acknowledge_path("peer", "127.0.0.2", 9000, probes[0]["nonce"], 3_000_003)
	_check(book.resolve_peer("peer").get("address") == "127.0.0.2", "Healthy fallback was not selected")
	book.path_probes(5_000_003)
	_check(book.resolve_peer("peer").get("address") == "127.0.0.2", "Healthy fallback changed prematurely")
	book.acknowledge_path("peer", "127.0.0.2", 9000, probes[0]["nonce"], 5_999_999)
	probes = book.path_probes(6_000_003)
	_check(book.resolve_peer("peer").is_empty(), "Failed path remained selected or a replayed acknowledgement extended its lifetime")
	_check(probes.size() == 1 and probes[0]["address"] == "127.0.0.1", "Preferred path was not retried")
	book.path_probes(9_000_003)
	book.path_probes(9_000_004)
	book.path_probes(12_000_004)
	probes = book.path_probes(13_000_004)
	_check(probes.size() == 1 and probes[0]["address"] == "127.0.0.1", "All-path failure did not restart selection")

func _test_config() -> void:
	var config = Config.new()
	config._config = ConfigFile.new()
	config._config.set_value("peers", "old", "example:9000")
	config._config.set_value("peers", "new", ["one:9000", "two:9001"])
	var peers: Dictionary = config.get_peers()
	_check(peers["old"]["host"] == "example", "Legacy peer parsing changed")
	_check(peers["new"]["candidates"].size() == 2, "Ordered peer candidates were not parsed")

func _test_udp() -> void:
	var a = Transport.new()
	var b = Transport.new()
	var a_book = AddressBook.new()
	var b_book = AddressBook.new()
	var port_a := randi_range(41000, 48000)
	var port_b := port_a + 1
	a_book.configure({"b": {"candidates": [{"host": "127.0.0.1", "port": port_b}]}}, port_b)
	b_book.configure({"a": {"candidates": [{"host": "127.0.0.1", "port": port_a}]}}, port_a)
	root.add_child(a)
	root.add_child(b)
	var a_result: Error = a.configure({"mode": "unicast", "udp_port": port_a}, a_book, "a")
	var b_result: Error = b.configure({"mode": "unicast", "udp_port": port_b}, b_book, "b")
	_check(a_result == OK and b_result == OK, "Could not bind test transports")
	if a_result == OK and b_result == OK:
		for i in 100:
			if not a_book.resolve_peer("b").is_empty() and not b_book.resolve_peer("a").is_empty():
				break
			await create_timer(0.02).timeout
		_check(not a_book.resolve_peer("b").is_empty() and not b_book.resolve_peer("a").is_empty(), "Correlated UDP probes did not establish both paths")
	a.close()
	b.close()
	a.queue_free()
	b.queue_free()

func _test_legacy_peer() -> void:
	var port := randi_range(41000, 48000)
	var legacy := PacketPeerUDP.new()
	if legacy.bind(port + 1, "127.0.0.1") != OK:
		_check(false, "Could not bind legacy test peer")
		return
	var book = AddressBook.new()
	book.configure({"legacy": {"candidates": [{"host": "127.0.0.1", "port": port + 1}]}}, port + 1)
	var modern = Transport.new()
	root.add_child(modern)
	var received := [false]
	modern.message_received.connect(func(message): received[0] = message.get("sender_peer_id") == "legacy")
	if modern.configure({"mode": "unicast", "udp_port": port}, book, "modern") != OK:
		_check(false, "Could not bind modern test peer")
		legacy.close()
		modern.queue_free()
		return
	legacy.set_dest_address("127.0.0.1", port)
	legacy.put_packet(JSON.stringify({"version": 1, "type": "heartbeat", "sender_peer_id": "legacy", "payload": {}}).to_utf8_buffer())
	await create_timer(0.1).timeout
	_check(received[0], "Legacy messages were not received")
	_check(book.resolve_peer("legacy").is_empty(), "An unverified legacy path was treated as bidirectionally healthy")
	legacy.close()
	modern.close()
	modern.queue_free()

func _test_snapshot() -> void:
	var port := randi_range(55000, 59000)
	var server = SnapshotServer.new()
	root.add_child(server)
	if server.configure(null, port) != OK:
		_check(false, "Could not start snapshot server")
		server.queue_free()
		return
	var selector = HttpSelector.new()
	root.add_child(selector)
	var url := "http://127.0.0.1:%d" % port
	selector.configure([url])
	for i in 100:
		if selector.selected_url() == url:
			break
		await create_timer(0.02).timeout
	_check(selector.selected_url() == url, "Snapshot path did not connect")
	var book = AddressBook.new()
	book.configure({"peer": {"host": "127.0.0.1", "port": 9000}}, 9000)
	var client = SnapshotClient.new()
	root.add_child(client)
	client.configure(book, port, {"peer": selector})
	var failed := [false]
	client.snapshot_failed.connect(func(_object_id, _owner, _reason): failed[0] = true)
	_check(client.request_snapshot("camera", "peer") == OK, "Could not request test snapshot")
	for i in 100:
		if failed[0]:
			break
		await create_timer(0.02).timeout
	_check(failed[0], "Unavailable frame did not fail snapshot")
	_check(selector.selected_url() == url, "Unavailable camera frame incorrectly invalidated network path")
	client.close()
	server.close()
	client.queue_free()
	server.queue_free()
	selector.queue_free()

func _test_tcp() -> void:
	var port := randi_range(49000, 54000)
	var fallback := TCPServer.new()
	var preferred := TCPServer.new()
	var error := fallback.listen(port + 1, "127.0.0.1")
	_check(error == OK, "Could not start TCP fallback server")
	if error != OK:
		return
	var selector = HttpSelector.new()
	root.add_child(selector)
	var first := "http://127.0.0.1:%d/test" % port
	var second := "http://127.0.0.1:%d/test" % (port + 1)
	_check(selector.configure([first, second]) == OK, "Could not configure TCP endpoints")
	for i in 200:
		if selector.selected_url() == second:
			break
		await create_timer(0.02).timeout
	_check(selector.selected_url() == second, "TCP selector did not fall back")
	_check(selector.selected_address() == "127.0.0.1", "TCP selector did not expose its resolved address")
	_check(preferred.listen(port, "127.0.0.1") == OK, "Could not start preferred server")
	await create_timer(2.2).timeout
	_check(selector.selected_url() == second, "TCP selector left a healthy fallback")
	fallback.stop()
	for i in 250:
		if selector.selected_url() == first:
			break
		await create_timer(0.02).timeout
	_check(selector.selected_url() == first, "TCP selector did not recover to preferred endpoint after failure")
	preferred.stop()
	selector.queue_free()
