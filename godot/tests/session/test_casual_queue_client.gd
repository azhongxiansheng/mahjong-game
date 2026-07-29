extends GutTest

# #323：真实 127.0.0.1 TCP HTTP fixture；不 mock HTTPRequest 或队列响应解析。

class QueueHttpFixture extends Node:
	var server := TCPServer.new()
	var port := 0
	var requests: Array[String] = []
	var _peers: Array[StreamPeerTCP] = []

	func start() -> void:
		assert(server.listen(0, "127.0.0.1") == OK)
		port = server.get_local_port()
		set_process(true)

	func stop() -> void:
		set_process(false)
		for peer in _peers:
			peer.disconnect_from_host()
		_peers.clear()
		if server.is_listening():
			server.stop()

	func base_url() -> String:
		return "http://127.0.0.1:%d" % port

	func _process(_delta: float) -> void:
		if server.is_connection_available():
			var peer := server.take_connection()
			if peer != null:
				_peers.append(peer)
		var keep: Array[StreamPeerTCP] = []
		for peer in _peers:
			peer.poll()
			if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
				if peer.get_available_bytes() == 0:
					keep.append(peer)
					continue
				var raw := peer.get_utf8_string(peer.get_available_bytes())
				requests.append(raw)
				_respond(peer, raw)
		_peers = keep

	func _respond(peer: StreamPeerTCP, raw: String) -> void:
		var first_line := raw.split("\r\n")[0]
		var body := {}
		var status := "200 OK"
		if first_line.begins_with("POST /v1/guest-sessions "):
			status = "201 Created"
			body = {
				"guest_id": "guest-323",
				"display_name": "游客-0323",
				"session_token": "secret-session-token",
				"expires_at": "2026-07-27T00:00:00Z",
			}
		elif first_line.begins_with("POST /v1/queues/casual "):
			body = _ticket("waiting")
		elif first_line.begins_with("GET /v1/queues/casual/ticket-323 "):
			body = _ticket("assigned")
			body.merge({
				"worker": "ws://127.0.0.1:9323",
				"room_id": "room-323",
				"seat": 2,
				"room_token": "secret-room-token",
			}, true)
		elif first_line.begins_with("DELETE /v1/queues/casual/ticket-323 "):
			body = _ticket("cancelled")
		else:
			status = "404 Not Found"
			body = {"code": "NOT_FOUND", "message": "not found"}
		var payload := JSON.stringify(body)
		var response := (
			"HTTP/1.1 %s\r\nContent-Type: application/json\r\n"
			+ "Content-Length: %d\r\nConnection: close\r\n\r\n%s"
		) % [status, payload.to_utf8_buffer().size(), payload]
		peer.put_data(response.to_utf8_buffer())
		peer.disconnect_from_host()

	func _ticket(status: String) -> Dictionary:
		return {
			"ticket_id": "ticket-323",
			"round_kind": "EAST",
			"game_mode": "STANDARD",
			"status": status,
			"queued_at": "2026-07-26T00:00:00Z",
			"deadline_at": "2026-07-26T00:00:30Z",
		}


var _fixture: QueueHttpFixture


func before_each() -> void:
	_fixture = QueueHttpFixture.new()
	add_child_autofree(_fixture)
	_fixture.start()


func after_each() -> void:
	_fixture.stop()


func _wait_until(done: Callable, max_frames: int = 120) -> bool:
	for _i in range(max_frames):
		if done.call():
			return true
		await wait_process_frames(1)
	return false


func test_real_http_guest_enqueue_poll_and_private_tokens() -> void:
	var client := CasualQueueClient.new()
	add_child_autofree(client)
	client.configure(_fixture.base_url())
	var tickets: Array[Dictionary] = []
	client.ticket_updated.connect(func(ticket: Dictionary): tickets.append(ticket.duplicate(true)))
	client.begin(SessionIntent.new(&"PUBLIC_CASUAL", &"EAST", &"STANDARD", &"lin_yeche"))
	assert_true(await _wait_until(func(): return tickets.size() == 1))
	assert_eq(tickets[0].get("status"), "waiting")
	assert_eq(client.get_session_id(), "guest-323")
	assert_false(client.get_public_debug_view().has("session_token"))
	assert_false(client.get_public_debug_view().has("room_token"))
	assert_true(_fixture.requests[1].contains("Authorization: Bearer secret-session-token"))

	client.poll_ticket()
	assert_true(await _wait_until(func(): return tickets.size() == 2))
	assert_eq(tickets[1].get("status"), "assigned")
	assert_eq(tickets[1].get("room_token"), "secret-room-token")


func test_real_http_cancel_uses_delete_and_waits_for_authority_response() -> void:
	var client := CasualQueueClient.new()
	add_child_autofree(client)
	client.configure(_fixture.base_url())
	var statuses: Array[String] = []
	client.ticket_updated.connect(func(ticket: Dictionary): statuses.append(str(ticket.get("status", ""))))
	client.begin(SessionIntent.new(&"PUBLIC_CASUAL", &"EAST", &"STANDARD", &"lin_yeche"))
	assert_true(await _wait_until(func(): return statuses.size() == 1))
	client.cancel_ticket()
	assert_eq(statuses, ["waiting"], "DELETE 返回前不得乐观伪造 cancelled")
	assert_true(await _wait_until(func(): return statuses.size() == 2))
	assert_eq(statuses, ["waiting", "cancelled"])
	assert_true(_fixture.requests[2].begins_with("DELETE /v1/queues/casual/ticket-323 "))


func test_enqueue_body_includes_own_character_id_only() -> void:
	var client := CasualQueueClient.new()
	add_child_autofree(client)
	client.configure(_fixture.base_url())
	var tickets: Array[Dictionary] = []
	client.ticket_updated.connect(func(ticket: Dictionary): tickets.append(ticket.duplicate(true)))
	assert_true(client.begin(SessionIntent.new(&"PUBLIC_CASUAL", &"EAST", &"STANDARD", &"qiu_jue")))
	assert_true(await _wait_until(func(): return tickets.size() == 1))
	var enqueue_raw := ""
	for r in _fixture.requests:
		if str(r).begins_with("POST /v1/queues/casual "):
			enqueue_raw = str(r)
			break
	assert_false(enqueue_raw.is_empty(), "must POST enqueue")
	assert_true(enqueue_raw.contains("\"character_id\":\"qiu_jue\""), enqueue_raw)
	assert_false(enqueue_raw.contains("ability_id"), "不得提交 ability_id")
	assert_false(enqueue_raw.contains("character_ids"), "不得提交四席 character_ids")
	# 空角色拒绝
	var client2 := CasualQueueClient.new()
	add_child_autofree(client2)
	client2.configure(_fixture.base_url())
	assert_false(client2.begin(SessionIntent.new(&"PUBLIC_CASUAL", &"EAST", &"STANDARD")))
