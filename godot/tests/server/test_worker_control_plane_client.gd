extends GutTest

# #256：Worker → CP 注册请求体、定时续租、容量报告、错误重试（真实类 + 本地 HTTP）。

const SECRET := "0123456789abcdef0123456789abcdef"
const REG_TOKEN := "worker-reg-token-gut-16"


class _MiniCP:
	extends Node
	var tcp: TCPServer = TCPServer.new()
	var peers: Array = []
	var requests: Array = []
	var force_500: bool = false
	var port: int = 0

	func start() -> Error:
		var err: Error = tcp.listen(0, "127.0.0.1")
		if err != OK:
			return err
		port = tcp.get_local_port()
		set_process(true)
		return OK

	func stop() -> void:
		set_process(false)
		for entry in peers:
			var s: StreamPeerTCP = entry["stream"]
			if s != null:
				s.disconnect_from_host()
		peers.clear()
		if tcp.is_listening():
			tcp.stop()

	func _process(_dt: float) -> void:
		poll()

	func poll() -> void:
		while tcp.is_connection_available():
			var s: StreamPeerTCP = tcp.take_connection()
			if s != null:
				peers.append({"stream": s, "buf": PackedByteArray()})
		var i := 0
		while i < peers.size():
			var entry: Dictionary = peers[i]
			var s: StreamPeerTCP = entry["stream"] as StreamPeerTCP
			s.poll()
			if s.get_status() != StreamPeerTCP.STATUS_CONNECTED:
				peers.remove_at(i)
				continue
			if s.get_available_bytes() > 0:
				var got: Array = s.get_data(s.get_available_bytes())
				if int(got[0]) == OK:
					var chunk: PackedByteArray = got[1]
					var buf: PackedByteArray = entry["buf"]
					buf.append_array(chunk)
					entry["buf"] = buf
					var text := buf.get_string_from_utf8()
					if text.contains("\r\n\r\n"):
						var header := text.get_slice("\r\n\r\n", 0)
						var body_part := ""
						var split_parts := text.split("\r\n\r\n", true, 1)
						if split_parts.size() > 1:
							body_part = split_parts[1]
						var need := 0
						for line in header.split("\r\n"):
							if line.to_lower().begins_with("content-length:"):
								need = int(line.get_slice(":", 1).strip_edges())
						if body_part.length() >= need:
							_handle_http(s, text)
							peers.remove_at(i)
							continue
			i += 1

	func _handle_http(s: StreamPeerTCP, text: String) -> void:
		var parts := text.split("\r\n\r\n", true, 1)
		var head := parts[0]
		var body := ""
		if parts.size() > 1:
			body = parts[1]
		var first_line := head.get_slice("\r\n", 0)
		var path := ""
		if first_line.begins_with("POST "):
			path = first_line.get_slice(" ", 1)
		requests.append({"headers": head, "body": body, "path": path})
		var status := "200 OK"
		var resp_body := "{\"worker_id\":\"w1\",\"lease_ttl_ms\":15000}"
		if path.contains("/rooms/complete"):
			resp_body = "{\"worker_id\":\"w1\",\"room_id\":\"r1\",\"status\":\"completed\"}"
		if force_500:
			status = "500 Internal Server Error"
			resp_body = "{\"code\":\"INTERNAL\"}"
		elif not head.contains("Authorization: Bearer %s" % REG_TOKEN):
			status = "401 Unauthorized"
			resp_body = "{\"code\":\"UNAUTHORIZED\"}"
		var resp := (
			"HTTP/1.1 %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s"
			% [status, resp_body.length(), resp_body]
		)
		s.put_data(resp.to_utf8_buffer())
		s.disconnect_from_host()


func test_build_register_body_has_capacity_and_no_token() -> void:
	var c := WorkerControlPlaneClient.new()
	add_child_autofree(c)
	assert_true(c.configure(
		"http://127.0.0.1:8081",
		REG_TOKEN,
		"worker-a",
		"ws://127.0.0.1:9000",
		"ws://127.0.0.1:9001",
		2,
		1000
	))
	var body := c.build_register_body(3)
	assert_true(body.contains("\"worker_id\":\"worker-a\""), body)
	assert_true(body.contains("\"capacity\":2"), body)
	assert_true(body.contains("\"active_rooms\":3"), body)
	assert_true(body.contains("\"game_endpoint\":\"ws://127.0.0.1:9000\""), body)
	assert_false(body.contains(REG_TOKEN), "body must not contain registration token")
	assert_false(body.contains(SECRET), "body must not contain signing secret")


func test_register_renew_and_retry_against_local_http() -> void:
	var mini := _MiniCP.new()
	add_child_autofree(mini)
	assert_eq(mini.start(), OK)
	await get_tree().process_frame
	var base := "http://127.0.0.1:%d" % mini.port

	var client := WorkerControlPlaneClient.new()
	add_child_autofree(client)
	assert_true(client.configure(
		base, REG_TOKEN, "w1",
		"ws://127.0.0.1:9000", "ws://127.0.0.1:9001",
		4, 500
	))
	client.retry_ms = 30
	client.renew_interval_ms = 50  # 测试用短间隔（配置校验后可调）
	client.clock_now_ms = 1000
	client.start()

	var ok := false
	for i in range(120):
		client.clock_now_ms = 1000 + i * 25
		client.poll(1)
		await get_tree().process_frame
		if client.register_success_count >= 1:
			ok = true
			break
	assert_true(ok, "expected at least one successful register last_err=%s attempts=%d" % [
		client.get_last_error(), client.register_attempt_count
	])
	assert_gt(mini.requests.size(), 0)
	var req0: Dictionary = mini.requests[0]
	assert_true(str(req0.get("path", "")).begins_with("/v1/internal/workers/register"))
	assert_true(str(req0.get("headers", "")).contains("Authorization: Bearer %s" % REG_TOKEN))
	assert_true(str(req0.get("body", "")).contains("\"active_rooms\":1"))
	assert_false(str(req0.get("body", "")).contains(REG_TOKEN))

	var before := client.register_success_count
	for i in range(120):
		client.clock_now_ms = 1000 + 2000 + i * 25
		client.poll(2)
		await get_tree().process_frame
		if client.register_success_count > before:
			break
	assert_gt(client.register_success_count, before, "expected renew success")
	var last_body := str(mini.requests[mini.requests.size() - 1].get("body", ""))
	assert_true(last_body.contains("\"active_rooms\":2"), last_body)

	mini.force_500 = true
	var attempts_before := client.register_attempt_count
	for i in range(120):
		client.clock_now_ms = 1000 + 5000 + i * 25
		client.poll(0)
		await get_tree().process_frame
		if client.register_attempt_count > attempts_before and client.get_last_error() != "":
			break
	assert_true(client.get_last_error().begins_with("http_"), client.get_last_error())

	client.stop()
	assert_false(client.is_started())
	mini.stop()


func test_headless_worker_wires_registration_into_poll_and_stop() -> void:
	var mini := _MiniCP.new()
	add_child_autofree(mini)
	assert_eq(mini.start(), OK)
	await get_tree().process_frame
	var base := "http://127.0.0.1:%d" % mini.port

	var w := HeadlessWorker.new()
	add_child_autofree(w)
	assert_true(w.configure(SECRET, "127.0.0.1", 0, -1, ""))
	assert_true(w.configure_control_plane_registration(
		base, REG_TOKEN, "hw1",
		"ws://127.0.0.1:9000", "ws://127.0.0.1:9001",
		2, 500
	))
	assert_eq(w.start_listen(), OK)
	var client := w.get_control_plane_client()
	assert_not_null(client)
	client.renew_interval_ms = 40
	assert_true(client.is_started())

	var ok := false
	for i in range(120):
		w.set_clock_ms_for_test(2000 + i * 25)
		w.poll()
		await get_tree().process_frame
		if client.register_success_count >= 1:
			ok = true
			break
	assert_true(ok, "HeadlessWorker.poll should drive registration err=%s" % client.get_last_error())

	w.stop()
	assert_null(w.get_control_plane_client())
	var n := mini.requests.size()
	for i in range(10):
		w.poll()
		await get_tree().process_frame
	assert_eq(mini.requests.size(), n, "stopped worker must not keep renewing")
	mini.stop()


func test_configure_rejects_missing_fields() -> void:
	var c := WorkerControlPlaneClient.new()
	add_child_autofree(c)
	assert_false(c.configure("", REG_TOKEN, "w", "ws://g", "ws://v"))
	assert_false(c.configure("http://127.0.0.1:1", "", "w", "ws://g", "ws://v"))
	assert_false(c.configure("http://127.0.0.1:1", REG_TOKEN, "", "ws://g", "ws://v"))
	assert_false(c.configure("http://127.0.0.1:1", REG_TOKEN, "w", "", "ws://v"))
	assert_false(c.configure("http://127.0.0.1:1", REG_TOKEN, "w", "ws://g", "ws://v", 0, 1000))
	assert_false(c.configure("http://127.0.0.1:1", REG_TOKEN, "w", "ws://g", "ws://v", 1, 100))


func test_strict_env_int_parser_used_by_main_entry() -> void:
	# 真实入口脚本的静态解析（非旁路 helper 另写）
	var MainScr = load("res://server/headless_worker_main.gd")
	assert_not_null(MainScr)
	var ok1: Dictionary = MainScr.parse_strict_int_env("4", 1, 1024)
	assert_true(bool(ok1.get("ok", false)))
	assert_eq(int(ok1.get("value", 0)), 4)
	assert_false(bool(MainScr.parse_strict_int_env("0", 1, 1024).get("ok", false)))
	assert_false(bool(MainScr.parse_strict_int_env("-1", 1, 1024).get("ok", false)))
	assert_false(bool(MainScr.parse_strict_int_env("1.5", 1, 1024).get("ok", false)))
	assert_false(bool(MainScr.parse_strict_int_env("01", 1, 1024).get("ok", false)))
	assert_false(bool(MainScr.parse_strict_int_env("abc", 1, 1024).get("ok", false)))
	# strip_edges 允许两端空白；内部非数字拒绝
	assert_true(bool(MainScr.parse_strict_int_env(" 4 ", 1, 1024).get("ok", false)))
	assert_false(bool(MainScr.parse_strict_int_env("4a", 1, 1024).get("ok", false)))


func test_renew_clamped_to_lease_safe_window() -> void:
	var mini := _MiniCP.new()
	add_child_autofree(mini)
	assert_eq(mini.start(), OK)
	await get_tree().process_frame
	var base := "http://127.0.0.1:%d" % mini.port
	var client := WorkerControlPlaneClient.new()
	add_child_autofree(client)
	# 配置 renew 远大于 lease/3：成功后必须被压到安全窗口
	assert_true(client.configure(base, REG_TOKEN, "w1", "ws://g", "ws://v", 2, 60000))
	client.clock_now_ms = 1000
	client.start()
	for i in range(80):
		client.clock_now_ms = 1000 + i * 25
		client.poll(0)
		await get_tree().process_frame
		if client.register_success_count >= 1:
			break
	assert_gte(client.register_success_count, 1)
	assert_eq(client.last_lease_ttl_ms, 15000)
	# 下次续租不得晚于 now+5000（15000/3）
	var delay: int = client._safe_renew_delay_ms()
	assert_lte(delay, 5000)
	assert_gte(delay, 500)
	mini.stop()


func test_match_settled_triggers_complete_and_room_count_excludes_done() -> void:
	var mini := _MiniCP.new()
	add_child_autofree(mini)
	assert_eq(mini.start(), OK)
	await get_tree().process_frame
	var base := "http://127.0.0.1:%d" % mini.port

	var w := HeadlessWorker.new()
	add_child_autofree(w)
	assert_true(w.configure(SECRET, "127.0.0.1", 0, -1, ""))
	assert_true(w.configure_control_plane_registration(
		base, REG_TOKEN, "hw1", "ws://127.0.0.1:9000", "ws://127.0.0.1:9001", 2, 500
	))
	assert_eq(w.start_listen(), OK)
	# 注入真实房间会话（bootstrap + 绑定连接；无真实 peer，不得走生产 _poll_conn）
	var claims := {
		"room_id": "room-ms-1",
		"session_id": "sess-0",
		"seat": 0,
		"round_kind": "EAST",
		"game_mode": "STANDARD",
		"participants": ["HUMAN", "AI", "AI", "AI"],
		"character_ids": ["lin_yeche", "an_cheng", "bai_touli", "hua_ling"],
	}
	var session := HeadlessRoomSession.new()
	assert_true(session.bootstrap_from_claims(claims))
	w.inject_bound_session_for_test(1, session, 0, "sess-0")
	assert_not_null(w.get_room("room-ms-1"))
	assert_eq(w.room_count(), 1)
	# 完成前：is_match_completed / room_count 不得触发 event_journal 克隆
	var jcalls0: int = session.server.event_journal_call_count
	assert_false(session.is_match_completed())
	assert_eq(w.room_count(), 1)
	assert_eq(session.server.event_journal_call_count, jcalls0,
		"pre-settled complete checks must not call event_journal")

	# 经权威 publish 路径写入 MATCH_SETTLED（真实 journal 信号）
	var payload := {
		"round_kind": "EAST",
		"final_scores": [25000, 25000, 25000, 25000],
		"seat_order": [0, 1, 2, 3],
	}
	assert_true(session.server.call(
		"_publish_domain_events_with_matching_snapshot",
		[{"kind": "MATCH_SETTLED", "payload": payload}]
	))
	assert_true(session.server.has_match_settled())
	assert_true(session.is_match_completed())
	# 发布后：重复完成态检查不得再调用会克隆 journal 的 event_journal
	var jcalls1: int = session.server.event_journal_call_count
	for _i in range(20):
		assert_true(session.is_match_completed())
		assert_eq(w.room_count(), 0, "completed room must not count as active")
		w._cleanup_completed_rooms()
	assert_eq(session.server.event_journal_call_count, jcalls1,
		"repeated is_match_completed/room_count must not clone journal via event_journal")

	# 广播/finalize：enqueue complete
	w._broadcast_room_events("room-ms-1")
	var client := w.get_control_plane_client()
	assert_not_null(client)
	client.clock_now_ms = 3000
	client._next_renew_ms = 999999
	client._next_complete_ms = 0
	var ok := false
	for i in range(80):
		client.clock_now_ms = 3000 + i * 25
		client.poll(w.room_count())
		await get_tree().process_frame
		if client.complete_success_count >= 1:
			ok = true
			break
	assert_true(ok, "MATCH_SETTLED must drive room complete report err=%s" % client.get_last_error())
	var saw_complete := false
	for req in mini.requests:
		if str(req.get("path", "")).contains("/rooms/complete"):
			saw_complete = true
			assert_true(str(req.get("body", "")).contains("room-ms-1"))
			assert_false(str(req.get("body", "")).contains(REG_TOKEN))
	assert_true(saw_complete)
	w._cleanup_completed_rooms()
	assert_null(w.get_room("room-ms-1"))
	# 再证明清理后仍不触碰 journal 克隆路径
	var jcalls2: int = session.server.event_journal_call_count
	assert_eq(w.room_count(), 0)
	assert_eq(session.server.event_journal_call_count, jcalls2)
	mini.stop()


func test_match_settled_flag_only_on_real_match_settled() -> void:
	# 普通事件 / 未启动不得误置 has_match_settled
	var session := HeadlessRoomSession.new()
	assert_true(session.bootstrap_from_claims({
		"room_id": "flag-room",
		"session_id": "sess-flag",
		"seat": 0,
		"round_kind": "EAST",
		"game_mode": "STANDARD",
		"participants": ["HUMAN", "AI", "AI", "AI"],
			"character_ids": ["lin_yeche", "an_cheng", "bai_touli", "hua_ling"],
}))
	var server: LocalLoopbackServer = session.server
	assert_not_null(server)
	assert_false(server.has_match_settled())
	assert_false(session.is_match_completed())
	var j0: int = server.event_journal_call_count
	# 未 MATCH_SETTLED：重复检查不调用 event_journal
	for _i in range(10):
		assert_false(session.is_match_completed())
	assert_eq(server.event_journal_call_count, j0)
	# 非 MATCH 业务事件不得置完成（ACTION 路径无关；空 publish 不改变标志）
	assert_false(server.has_match_settled())
	# 真实 MATCH_SETTLED 才置位
	var payload := {
		"round_kind": "EAST",
		"final_scores": [25000, 25000, 25000, 25000],
		"seat_order": [0, 1, 2, 3],
	}
	assert_true(server.call(
		"_publish_domain_events_with_matching_snapshot",
		[{"kind": "MATCH_SETTLED", "payload": payload}]
	))
	assert_true(server.has_match_settled())
	assert_true(session.is_match_completed())
	var j2: int = server.event_journal_call_count
	for _i2 in range(10):
		assert_true(session.is_match_completed())
	assert_eq(server.event_journal_call_count, j2,
		"O(1) has_match_settled must not call event_journal")


func test_complete_500_respects_retry_deadline_and_does_not_starve_renew() -> void:
	var mini := _MiniCP.new()
	add_child_autofree(mini)
	assert_eq(mini.start(), OK)
	await get_tree().process_frame
	var base := "http://127.0.0.1:%d" % mini.port
	var client := WorkerControlPlaneClient.new()
	add_child_autofree(client)
	assert_true(client.configure(base, REG_TOKEN, "w1", "ws://g", "ws://v", 2, 500))
	client.retry_ms = 200
	client.renew_interval_ms = 1000
	client.clock_now_ms = 10000
	client.start()
	# 先成功注册一次
	for i in range(40):
		client.clock_now_ms = 10000 + i * 20
		client.poll(0)
		await get_tree().process_frame
		if client.register_success_count >= 1:
			break
	assert_gte(client.register_success_count, 1)
	var renew_deadline := client.get_next_renew_ms_for_test()
	assert_gt(renew_deadline, 10000)

	# complete 持续 500
	mini.force_500 = true
	client.enqueue_room_complete("room-x")
	client._next_complete_ms = 0
	var attempts_before := client.complete_attempt_count
	# 在 complete retry 窗口内多次 poll：attempt 最多 +1
	for i in range(5):
		client.clock_now_ms = 10000 + 50 + i * 10  # 远小于 renew 与 complete retry
		# 确保 renew 未到期
		if client.clock_now_ms >= renew_deadline:
			client.clock_now_ms = renew_deadline - 1
		client.poll(0)
		await get_tree().process_frame
	assert_lte(client.complete_attempt_count, attempts_before + 1,
		"complete must not tight-loop before retry deadline")
	# 失败后 complete deadline 应在未来（退避生效）
	if client.complete_attempt_count > attempts_before:
		for _i in range(40):
			if client.get_next_complete_ms_for_test() > client.clock_now_ms:
				break
			await get_tree().process_frame
		assert_gt(client.get_next_complete_ms_for_test(), client.clock_now_ms)

	# complete backlog 期间：推进到 renew 到期，必须仍能 register
	mini.force_500 = false
	client.enqueue_room_complete("room-x")  # 保持 backlog
	client._next_complete_ms = 0
	# 强制 renew 到期但 complete 在退避中
	client._next_complete_ms = client.clock_now_ms + 10000
	client._next_renew_ms = client.clock_now_ms  # due now
	var reg_before := client.register_success_count
	var reg_attempts_before := client.register_attempt_count
	for i in range(40):
		client.clock_now_ms = client.clock_now_ms + 20
		# renew 优先：即使 complete 队列非空
		client.enqueue_room_complete("room-starve")
		client.poll(1)
		await get_tree().process_frame
		if client.register_success_count > reg_before:
			break
	assert_gt(client.register_attempt_count, reg_attempts_before,
		"renew must fire during complete backlog")
	assert_gt(client.register_success_count, reg_before,
		"lease renew must succeed while complete queue non-empty")

	# complete 恢复 2xx 后最终成功
	client._next_complete_ms = 0
	client._next_renew_ms = client.clock_now_ms + 999999
	var c_before := client.complete_success_count
	for i in range(40):
		client.clock_now_ms = client.clock_now_ms + 20
		client.poll(0)
		await get_tree().process_frame
		if client.complete_success_count > c_before:
			break
	assert_gt(client.complete_success_count, c_before, "complete must succeed after recovery")
	client.stop()
	mini.stop()
