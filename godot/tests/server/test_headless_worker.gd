extends GutTest

# #240 round-2：Worker 控制面、错误通道、伪造枚举、二次 JOIN、二进制帧。

const FIXTURE := "res://tests/_fixtures/room_token_crosslang.json"
const SECRET := "0123456789abcdef0123456789abcdef"


func after_each() -> void:
	# 清零本轮 HeadlessWorker Node orphan
	pass


func _load_fixture() -> Dictionary:
	if not FileAccess.file_exists(FIXTURE):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	if typeof(d) != TYPE_DICTIONARY:
		return {}
	return d


func _new_worker(secret: String = SECRET) -> HeadlessWorker:
	var w := HeadlessWorker.new()
	add_child_autofree(w)
	assert_true(w.configure(secret))
	return w


func _worker_from_fixture() -> HeadlessWorker:
	var fix := _load_fixture()
	assert_false(fix.is_empty(), "need crosslang fixture")
	if fix.is_empty():
		return null
	var w := _new_worker(str(fix["secret"]))
	w.token_now_unix = int(fix["issued_at_unix"])
	return w


func _assert_error_no_seq(msg: Dictionary, code: String, tag: String) -> void:
	assert_eq(str(msg.get("kind", "")), "ERROR", tag)
	assert_eq(str(msg.get("code", "")), code, tag)
	assert_false(msg.has("server_seq"), "%s 不得含 server_seq" % tag)
	assert_false(msg.has("view_hash"), "%s 不得含 view_hash" % tag)


func test_join_exact_schema_and_token() -> void:
	var fix := _load_fixture()
	if fix.is_empty():
		return
	var w := _worker_from_fixture()
	if w == null:
		return
	var token: String = str(fix["token"])
	var claims: Dictionary = fix["claims"]
	w.handle_dict_for_test(1, {
		"protocol_version": 1,
		"kind": "JOIN",
		"room_id": str(claims["room_id"]),
		"seat": int(claims["seat"]),
		"room_token": token,
		"extra": 1,
	})
	var out := w.test_outbox(1)
	assert_gt(out.size(), 0)
	_assert_error_no_seq(out[0], "COMMAND_REJECTED", "bad schema")
	w.handle_dict_for_test(2, {
		"protocol_version": 1,
		"kind": "JOIN",
		"room_id": str(claims["room_id"]),
		"seat": int(claims["seat"]),
		"room_token": token,
	})
	var out2 := w.test_outbox(2)
	for m in out2:
		assert_ne(str(m.get("kind", "")), "ERROR", "合法 JOIN 不得 ERROR")
	var room: HeadlessRoomSession = w.get_room(str(claims["room_id"]))
	assert_not_null(room)
	assert_true(room.is_bootstrapped())
	assert_false(room.is_started())


func test_ready_before_join_and_binding() -> void:
	var fix := _load_fixture()
	if fix.is_empty():
		return
	var w := _worker_from_fixture()
	if w == null:
		return
	var claims: Dictionary = fix["claims"]
	w.handle_dict_for_test(1, {
		"protocol_version": 1,
		"kind": "READY",
		"room_id": str(claims["room_id"]),
		"seat": int(claims["seat"]),
	})
	var out := w.test_outbox(1)
	assert_gt(out.size(), 0)
	assert_eq(str(out[0].get("code", "")), "UNAUTHORIZED")
	w.handle_dict_for_test(2, {
		"protocol_version": 1,
		"kind": "JOIN",
		"room_id": str(claims["room_id"]),
		"seat": int(claims["seat"]),
		"room_token": str(fix["token"]),
	})
	w.handle_dict_for_test(2, {
		"protocol_version": 1,
		"kind": "READY",
		"room_id": str(claims["room_id"]),
		"seat": 0 if int(claims["seat"]) != 0 else 2,
	})
	var out2 := w.test_outbox(2)
	var saw_unauth := false
	for m in out2:
		if str(m.get("kind", "")) == "ERROR" and str(m.get("code", "")) == "UNAUTHORIZED":
			saw_unauth = true
	assert_true(saw_unauth, "越权 seat READY 须 UNAUTHORIZED")


func test_session_token_join_fails() -> void:
	var fix := _load_fixture()
	if fix.is_empty():
		return
	var w := _worker_from_fixture()
	if w == null:
		return
	var claims: Dictionary = fix["claims"]
	w.handle_dict_for_test(1, {
		"protocol_version": 1,
		"kind": "JOIN",
		"room_id": str(claims["room_id"]),
		"seat": int(claims["seat"]),
		"room_token": "v1.g.eyJ0eXAiOiJndWVzdCJ9.sig",
	})
	var out := w.test_outbox(1)
	assert_gt(out.size(), 0)
	assert_eq(str(out[0].get("code", "")), "UNAUTHORIZED")


func test_all_server_event_kinds_forgery_rejected() -> void:
	var w := _new_worker()
	var kinds: Array = NetworkedEvent.EVENT_KINDS.duplicate()
	kinds.append("ERROR")
	for kind in kinds:
		w.clear_outbox_for_test(1)
		w.handle_dict_for_test(1, {
			"protocol_version": 1,
			"kind": kind,
			"room_id": "r",
			"seat": 0,
			"server_seq": 1,
			"payload": {},
			"view_hash": "a".repeat(64),
		})
		var out := w.test_outbox(1)
		assert_gt(out.size(), 0, "kind %s" % kind)
		_assert_error_no_seq(out[out.size() - 1], "FORGERY_REJECTED", "kind %s" % kind)


func test_second_join_on_same_connection_rejected_binding_frozen() -> void:
	var fix := _load_fixture()
	if fix.is_empty():
		return
	var w := _worker_from_fixture()
	if w == null:
		return
	var claims: Dictionary = fix["claims"]
	var token: String = str(fix["token"])
	var room_id: String = str(claims["room_id"])
	var seat: int = int(claims["seat"])
	w.handle_dict_for_test(1, {
		"protocol_version": 1,
		"kind": "JOIN",
		"room_id": room_id,
		"seat": seat,
		"room_token": token,
	})
	var bind1: Dictionary = w.test_conn_binding(1)
	assert_true(bool(bind1["joined"]))
	assert_eq(str(bind1["room_id"]), room_id)
	assert_eq(int(bind1["seat"]), seat)
	var sess1: String = str(bind1["session_id"])
	w.clear_outbox_for_test(1)
	# 二次 JOIN（即使相同 token）必须拒绝，绑定不变
	w.handle_dict_for_test(1, {
		"protocol_version": 1,
		"kind": "JOIN",
		"room_id": room_id,
		"seat": seat,
		"room_token": token,
	})
	var out := w.test_outbox(1)
	assert_gt(out.size(), 0)
	_assert_error_no_seq(out[out.size() - 1], "COMMAND_REJECTED", "second JOIN")
	var bind2: Dictionary = w.test_conn_binding(1)
	assert_true(bool(bind2["joined"]))
	assert_eq(str(bind2["room_id"]), room_id)
	assert_eq(int(bind2["seat"]), seat)
	assert_eq(str(bind2["session_id"]), sess1)


func test_binary_frame_rejected_no_join_no_state() -> void:
	var w := _new_worker()
	var raw: PackedByteArray = JSON.stringify({
		"protocol_version": 1,
		"kind": "JOIN",
		"room_id": "r",
		"seat": 0,
		"room_token": "x",
	}).to_utf8_buffer()
	w.handle_binary_for_test(1, raw)
	var out := w.test_outbox(1)
	assert_gt(out.size(), 0)
	_assert_error_no_seq(out[0], "COMMAND_REJECTED", "binary")
	var bind: Dictionary = w.test_conn_binding(1)
	assert_false(bool(bind.get("joined", false)), "二进制不得完成 JOIN")
	assert_eq(w.room_count(), 0, "二进制不得建房")
	assert_true(bool(bind.get("binary_rejected", false)))


func test_invalid_command_id_rejected_at_worker_entry_no_state_change() -> void:
	# Worker 真实 Action 入口：非法 / 非 canonical v4 command_id → ERROR，无序号，权威不变
	var session := HeadlessRoomSession.new()
	session.set_seed_override_for_test(77)
	assert_true(session.bootstrap_from_claims({
		"room_id": "room-cid",
		"seat": 0,
		"session_id": "s0",
		"round_kind": "EAST",
		"game_mode": "STANDARD",
		"participants": ["HUMAN", "AI", "AI", "AI"],
	}))
	assert_true(bool(session.join(0, "s0")["ok"]))
	assert_true(bool(session.ready(0, "s0")["ok"]))
	assert_true(session.is_started())
	var seq0: int = session.current_server_seq()
	var j_sizes: Array = []
	for s in range(4):
		j_sizes.append(session.event_journal(s).size())
	var w := _new_worker()
	w.inject_bound_session_for_test(1, session, 0, "s0")
	for bad_cmd in ["", "not-a-uuid", "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA", 123]:
		w.clear_outbox_for_test(1)
		var body := {
			"protocol_version": 1,
			"command_id": bad_cmd,
			"room_id": "room-cid",
			"seat": 0,
			"hand_seq": 0,
			"decision_id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
			"kind": "DISCARD",
			"payload": {"tile_instance_id": 1},
			"client_seq": 1,
		}
		w.handle_dict_for_test(1, body)
		var out := w.test_outbox(1)
		assert_gt(out.size(), 0, "bad cmd=%s 须 ERROR" % str(bad_cmd))
		var last: Dictionary = out[out.size() - 1]
		_assert_error_no_seq(last, "COMMAND_REJECTED", "cmd=%s" % str(bad_cmd))
		assert_eq(session.current_server_seq(), seq0, "非法 command_id 不得推进 seq")
		for s2 in range(4):
			assert_eq(session.event_journal(s2).size(), int(j_sizes[s2]),
				"seat%d journal 不得变化" % s2)


func test_domain_reject_maps_to_error_without_server_seq() -> void:
	# 真实规则：JOIN/READY 后错 decision → ERROR COMMAND_REJECTED，seq/journal 不变
	var session := HeadlessRoomSession.new()
	session.set_seed_override_for_test(2024)
	assert_true(session.bootstrap_from_claims({
		"room_id": "room-rej",
		"seat": 0,
		"session_id": "s0",
		"round_kind": "EAST",
		"game_mode": "STANDARD",
		"participants": ["HUMAN", "AI", "AI", "AI"],
	}))
	assert_true(bool(session.join(0, "s0")["ok"]))
	assert_true(bool(session.ready(0, "s0")["ok"]))
	assert_true(session.is_started())
	var seq0: int = session.current_server_seq()
	var j0_len: int = session.event_journal(0).size()
	var w := _new_worker()
	w.inject_bound_session_for_test(1, session, 0, "s0")
	# 错 decision_id 的 DISCARD
	w.handle_dict_for_test(1, {
		"protocol_version": 1,
		"command_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
		"room_id": "room-rej",
		"seat": 0,
		"hand_seq": 0,
		"decision_id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
		"kind": "DISCARD",
		"payload": {"tile_instance_id": 1},
		"client_seq": 1,
	})
	var out := w.test_outbox(1)
	assert_gt(out.size(), 0)
	var last: Dictionary = out[out.size() - 1]
	_assert_error_no_seq(last, "COMMAND_REJECTED", "bad decision")
	assert_eq(session.current_server_seq(), seq0, "拒绝不得推进 server_seq")
	assert_eq(session.event_journal(0).size(), j0_len, "拒绝不得写 journal")
	# 不得出现 CommandResult REJECTED 线上包
	for m in out:
		assert_ne(str(m.get("status", "")), "REJECTED", "不得发送 REJECTED CommandResult")


func test_join_ready_start_with_single_human_fixture() -> void:
	var fix := _load_fixture()
	if fix.is_empty():
		return
	var w := _worker_from_fixture()
	if w == null:
		return
	var claims: Dictionary = fix["claims"]
	w.handle_dict_for_test(1, {
		"protocol_version": 1,
		"kind": "JOIN",
		"room_id": str(claims["room_id"]),
		"seat": int(claims["seat"]),
		"room_token": str(fix["token"]),
	})
	w.handle_dict_for_test(1, {
		"protocol_version": 1,
		"kind": "READY",
		"room_id": str(claims["room_id"]),
		"seat": int(claims["seat"]),
	})
	var room: HeadlessRoomSession = w.get_room(str(claims["room_id"]))
	assert_not_null(room)
	assert_false(room.is_started(), "另一 HUMAN 未 READY 不得开局")
