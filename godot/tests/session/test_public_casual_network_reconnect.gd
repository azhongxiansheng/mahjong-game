extends GutTest

const SECRET := "0123456789abcdef0123456789abcdef"


func _mint_room_token() -> String:
	var body := {
		"typ": "room", "room_id": "room-323-reconnect", "seat": 0,
		"session_id": "guest-323", "exp": 2_000_000_000,
		"round_kind": "EAST", "game_mode": "STANDARD",
		"participants": ["HUMAN", "AI", "AI", "AI"],
	}
	var payload := Marshalls.raw_to_base64(JSON.stringify(body).to_utf8_buffer())
	payload = payload.replace("+", "-").replace("/", "_").rstrip("=")
	var signing := "v1.r.%s" % payload
	var sig := Crypto.new().hmac_digest(
		HashingContext.HASH_SHA256, SECRET.to_utf8_buffer(), signing.to_utf8_buffer()
	)
	var sig_text := Marshalls.raw_to_base64(sig).replace("+", "-").replace("/", "_").rstrip("=")
	return "%s.%s" % [signing, sig_text]


func _poll_until(worker: HeadlessWorker, session: PublicCasualNetworkSession, done: Callable) -> bool:
	for _i in range(180):
		worker.poll()
		session.poll()
		session.ensure_ready_sent()
		if done.call():
			return true
		await wait_process_frames(1)
	return false


func test_real_worker_closed_retry_and_valid_snapshot_recovery() -> void:
	var worker := HeadlessWorker.new()
	add_child_autofree(worker)
	assert_true(worker.configure(SECRET, "127.0.0.1", 0))
	worker.token_now_unix = 1_700_000_000
	assert_eq(worker.start_listen(), OK)

	var session := PublicCasualNetworkSession.new()
	add_child_autofree(session)
	assert_true(session.configure_from_assigned({
		"worker": "ws://127.0.0.1:%d" % worker.get_listen_port(),
		"room_id": "room-323-reconnect",
		"seat": 0,
		"room_token": _mint_room_token(),
		"game_mode": "STANDARD",
	}, "guest-323"))
	var counts := {"reconnecting": 0, "recovered": 0}
	var terminal_errors: Array[Dictionary] = []
	session.reconnecting.connect(func(_code: String, _message: String): counts["reconnecting"] += 1)
	session.recovered.connect(func(): counts["recovered"] += 1)
	session.terminal_error.connect(func(code: String, message: String): terminal_errors.append({"code": code, "message": message}))
	assert_eq(session.start(), OK)
	assert_true(
		await _poll_until(worker, session, func(): return session.has_committed_snapshot()),
		"初次快照未提交：%s ready=%s room=%s" % [
			terminal_errors, session.is_game_ready_sent(), worker.get_room("room-323-reconnect")
		]
	)

	session.close_connection_for_test()
	assert_true(await _poll_until(worker, session, func(): return counts["reconnecting"] == 1))
	assert_eq(counts["recovered"], 0, "CLOSED 不能猜测恢复")
	assert_eq(session.retry_reconnect(), OK)
	assert_true(await _poll_until(worker, session, func(): return counts["recovered"] == 1))
	assert_true(session.has_committed_snapshot())
	worker.stop()


func test_real_worker_join_error_becomes_terminal_without_token_leak() -> void:
	var worker := HeadlessWorker.new()
	add_child_autofree(worker)
	assert_true(worker.configure(SECRET, "127.0.0.1", 0))
	worker.token_now_unix = 1_700_000_000
	assert_eq(worker.start_listen(), OK)
	var session := PublicCasualNetworkSession.new()
	add_child_autofree(session)
	assert_true(session.configure_from_assigned({
		"worker": "ws://127.0.0.1:%d" % worker.get_listen_port(),
		"room_id": "room-bad-token",
		"seat": 0,
		"room_token": "invalid-secret-room-token",
		"game_mode": "STANDARD",
	}, "guest-323"))
	var errors: Array[Dictionary] = []
	session.terminal_error.connect(func(code: String, message: String): errors.append({"code": code, "message": message}))
	assert_eq(session.start(), OK)
	assert_true(await _poll_until(worker, session, func(): return not errors.is_empty()))
	assert_eq(errors.size(), 1, "同一次失败的连续 ERROR 帧只发布一个 terminal")
	assert_eq(errors[0].get("code"), "UNAUTHORIZED")
	assert_false(JSON.stringify(errors).contains("invalid-secret-room-token"))
	worker.stop()
