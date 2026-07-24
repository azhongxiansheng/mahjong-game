extends GutTest

# #242 E3-07：命令幂等、首次拒绝缓存、非法/伪造拒绝、view_hash 分叉、
# SNAP 兼容、确定性核心事件摘要。真实 Worker / LLS / NBC / 规则路径。
# 网络端到端未验证。

const CHARS := [&"lin_yeche", &"qiu_jue", &"bai_touli", &"hua_ling"]
const PARTS := [&"HUMAN", &"AI", &"AI", &"AI"]
const REWARD_KINDS := [
	"REWARD_WINDOW_OPENED", "REWARD_WINDOW_CLOSING", "REWARD_WINDOW_SETTLED",
	"REWARD_WINDOW_CANCELLED", "ITEM_GRANTED", "ITEM_CONSUMED", "ITEM_APPLIED",
	"CHARACTER_ABILITY_ARMED", "CHARACTER_ABILITY_DISARMED",
]
## 同 seed 确定性摘要共用固定 command 语义（causation_command_id 参与 payload）
const DIGEST_CMD_N := 7001
const DIGEST_SEED := 24270


func _cmd(n: int) -> String:
	return "550e8400-e29b-41d4-a716-%012d" % n


func _public_cfg(room_id: String, seed: int = 24202) -> GameSessionConfig:
	# 公共房：config.session_id == room_id（与 HeadlessRoomSession bootstrap 一致）
	return GameSessionConfig.create_validated(
		GameSessionConfig.ROOM_PUBLIC_CASUAL,
		GameSessionConfig.ROUND_EAST,
		GameSessionConfig.MODE_STANDARD,
		PARTS,
		CHARS,
		seed,
		room_id,
		"riichi-v1",
	)


func _new_worker() -> HeadlessWorker:
	var w := HeadlessWorker.new()
	add_child_autofree(w)
	assert_true(w.configure("0123456789abcdef0123456789abcdef"))
	return w


func _bootstrap_session(
	room_id: String,
	client_session: String,
	seed: int = 24210,
	do_ready: bool = true
) -> HeadlessRoomSession:
	var session := HeadlessRoomSession.new()
	session.set_seed_override_for_test(seed)
	assert_true(session.bootstrap_from_claims({
		"room_id": room_id,
		"seat": 0,
		"session_id": client_session,
		"round_kind": "EAST",
		"game_mode": "STANDARD",
		"participants": ["HUMAN", "AI", "AI", "AI"],
	}))
	assert_true(bool(session.join(0, client_session)["ok"]))
	if do_ready:
		assert_true(bool(session.ready(0, client_session)["ok"]))
		assert_true(session.is_started())
	else:
		assert_false(session.is_started())
	# 公共房 config.session_id 必须等于 room_id（证明不得冒充 client session）
	assert_eq(session.config.session_id, room_id,
		"公共 bootstrap 后 config.session_id 等于 room_id")
	assert_ne(client_session, room_id,
		"测试 client session 必须与 room_id 不同")
	return session


func _assert_error_no_seq_hash(msg: Dictionary, code: String, tag: String) -> void:
	assert_eq(str(msg.get("kind", "")), "ERROR", tag)
	assert_eq(str(msg.get("code", "")), code, tag)
	assert_false(msg.has("server_seq"), "%s 不得含 server_seq" % tag)
	assert_false(msg.has("view_hash"), "%s 不得含 view_hash" % tag)
	assert_false(msg.has("state_hash"), "%s 不得含 state_hash" % tag)
	assert_false(msg.has("full_state_hash"), "%s 不得含 full_state_hash" % tag)
	assert_ne(code, "COMMAND_DUPLICATE", "全仓禁止 COMMAND_DUPLICATE")


func _journal_sizes(session: HeadlessRoomSession) -> Array:
	var out: Array = []
	for s in range(4):
		out.append(session.event_journal(s).size())
	return out


func _cache_size(session: HeadlessRoomSession) -> int:
	if session == null or session.server == null:
		return -1
	var c: Variant = session.server.get("_command_cache")
	if typeof(c) != TYPE_DICTIONARY:
		return -1
	return (c as Dictionary).size()


func _authority_hash(session: HeadlessRoomSession) -> String:
	if session == null or session.server == null:
		return ""
	if session.server.has_method("authority_hash_for_test"):
		return str(session.server.authority_hash_for_test())
	return ""


func _find_discard_meta(session: HeadlessRoomSession) -> Dictionary:
	# 与 test_local_loopback_server._meta 一致：DISCARD.offer.payload_options[0]
	var journal: Array = session.event_journal(0)
	for i in range(journal.size() - 1, -1, -1):
		var ne: NetworkedEvent = journal[i] as NetworkedEvent
		if ne == null or ne.kind != "TURN_PROMPT":
			continue
		var p: Dictionary = ne.payload
		if int(p.get("seat", -1)) != 0:
			continue
		var offers: Variant = p.get("allowed_actions", [])
		if typeof(offers) != TYPE_ARRAY:
			continue
		for off in offers:
			if typeof(off) != TYPE_DICTIONARY:
				continue
			var od: Dictionary = off
			if str(od.get("kind", "")) != "DISCARD":
				continue
			var opts: Array = od.get("payload_options", [])
			if opts.is_empty() or typeof(opts[0]) != TYPE_DICTIONARY:
				continue
			var iid: int = int((opts[0] as Dictionary).get("tile_instance_id", -1))
			if iid < 0:
				continue
			return {
				"seat": int(p.get("seat", 0)),
				"hand_seq": int(p.get("hand_seq", 0)),
				"decision_id": str(p.get("decision_id", "")),
				"tile_instance_id": iid,
				"room_id": session.room_id,
			}
	return {}


func _action_dict(meta: Dictionary, cmd_n: int, client_seq: int = 1) -> Dictionary:
	var room: String = str(meta.get("room_id", "room-e307"))
	return {
		"protocol_version": 1,
		"command_id": _cmd(cmd_n),
		"room_id": room,
		"seat": int(meta.get("seat", 0)),
		"hand_seq": int(meta["hand_seq"]),
		"decision_id": str(meta["decision_id"]),
		"kind": "DISCARD",
		"payload": {"tile_instance_id": int(meta["tile_instance_id"])},
		"client_seq": client_seq,
	}


func _last_error(out: Array) -> Dictionary:
	if out.is_empty():
		return {}
	return out[out.size() - 1] as Dictionary


## P2-1 helper：首次 ERROR → 同指纹重放 → 异指纹 CONFLICT；seq/journal/authority 零变化
func _assert_worker_early_reject_cached(
	w: HeadlessWorker,
	cid: int,
	session: HeadlessRoomSession,
	body: Dictionary,
	expect_code: String,
	tag: String
) -> void:
	var seq0: int = session.current_server_seq()
	var j0: Array = _journal_sizes(session)
	var auth0: String = _authority_hash(session)
	var cache0: int = _cache_size(session)

	w.clear_outbox_for_test(cid)
	w.handle_dict_for_test(cid, body)
	var out1: Array = w.test_outbox(cid)
	assert_gt(out1.size(), 0, "%s 首次须 ERROR" % tag)
	var e1: Dictionary = _last_error(out1)
	_assert_error_no_seq_hash(e1, expect_code, "%s 首次" % tag)
	assert_eq(session.current_server_seq(), seq0, "%s 首次 seq 零变化" % tag)
	assert_eq(JSON.stringify(_journal_sizes(session)), JSON.stringify(j0),
		"%s 首次 journal 零变化" % tag)
	if not auth0.is_empty():
		assert_eq(_authority_hash(session), auth0, "%s 首次 authority 零变化" % tag)
	var cache1: int = _cache_size(session)
	assert_gt(cache1, cache0, "%s 首次拒绝须写入 command_cache" % tag)
	var frozen_err: Dictionary = e1.duplicate(true)

	# 同指纹（仅 client_seq 变）→ 原 ERROR
	w.clear_outbox_for_test(cid)
	var same: Dictionary = body.duplicate(true)
	same["client_seq"] = int(body.get("client_seq", 1)) + 50
	w.handle_dict_for_test(cid, same)
	var out2: Array = w.test_outbox(cid)
	assert_gt(out2.size(), 0, "%s 同指纹须 ERROR" % tag)
	var e2: Dictionary = _last_error(out2)
	assert_eq(str(e2.get("kind", "")), "ERROR", "%s 同指纹 kind" % tag)
	assert_eq(str(e2.get("code", "")), str(frozen_err.get("code", "")),
		"%s 同指纹 code 原结果" % tag)
	assert_eq(str(e2.get("command_id", "")), str(frozen_err.get("command_id", "")),
		"%s 同指纹 command_id" % tag)
	assert_false(e2.has("server_seq"), "%s 同指纹无 server_seq" % tag)
	assert_false(e2.has("view_hash"), "%s 同指纹无 view_hash" % tag)
	assert_false(e2.has("state_hash"), "%s 同指纹无 state_hash" % tag)
	assert_eq(session.current_server_seq(), seq0, "%s 同指纹 seq" % tag)
	assert_eq(JSON.stringify(_journal_sizes(session)), JSON.stringify(j0),
		"%s 同指纹 journal" % tag)
	assert_eq(_cache_size(session), cache1, "%s 同指纹不扩 cache" % tag)

	# 异指纹（换 tile）→ COMMAND_ID_CONFLICT，不覆盖首次
	w.clear_outbox_for_test(cid)
	var conflict: Dictionary = body.duplicate(true)
	var old_iid: int = int((body["payload"] as Dictionary).get("tile_instance_id", 1))
	conflict["payload"] = {"tile_instance_id": old_iid + 1}
	conflict["client_seq"] = int(body.get("client_seq", 1)) + 99
	w.handle_dict_for_test(cid, conflict)
	var out3: Array = w.test_outbox(cid)
	assert_gt(out3.size(), 0, "%s 异指纹须 ERROR" % tag)
	_assert_error_no_seq_hash(_last_error(out3), "COMMAND_ID_CONFLICT", "%s 异指纹" % tag)
	assert_eq(session.current_server_seq(), seq0, "%s CONFLICT seq" % tag)
	assert_eq(JSON.stringify(_journal_sizes(session)), JSON.stringify(j0),
		"%s CONFLICT journal" % tag)
	assert_eq(_cache_size(session), cache1, "%s CONFLICT 不覆盖 cache 条目数" % tag)

	# 再同指纹 → 仍为首次原 code（cache 未覆盖）
	w.clear_outbox_for_test(cid)
	w.handle_dict_for_test(cid, same)
	var e4: Dictionary = _last_error(w.test_outbox(cid))
	assert_eq(str(e4.get("code", "")), str(frozen_err.get("code", "")),
		"%s 冲突后同指纹仍首次 code" % tag)


# ---------------------------------------------------------------------------
# CID-01..03：指纹 session_id = JOIN 绑定客户端 session；首次拒绝缓存
# ---------------------------------------------------------------------------

func test_cid_fingerprint_uses_joined_client_session_not_room_id() -> void:
	var room_id := "room-pub-fp"
	var client_a := "client-session-A"
	var client_b := "client-session-B"
	assert_ne(client_a, room_id)
	var server := LocalLoopbackServer.new(_public_cfg(room_id), 0)
	assert_eq(server._config.session_id, room_id)
	var act := Action.make_pass(0, room_id, _cmd(1), _cmd(2), 0, 1)
	assert_not_null(act)
	var fp_a: String = server._business_fingerprint(act, client_a)
	var fp_b: String = server._business_fingerprint(act, client_b)
	var fp_room: String = server._business_fingerprint(act, room_id)
	assert_eq(fp_a.length(), 64, "client A 指纹须 64 hex")
	assert_eq(fp_b.length(), 64)
	assert_ne(fp_a, fp_b, "不同 client session 必须不同指纹")
	assert_ne(fp_a, fp_room, "不得用 room_id 冒充 client session 指纹")
	var fp_empty: String = server._business_fingerprint(act, "")
	assert_eq(fp_empty, fp_room, "empty bound → 退回 config.session_id(=room_id)")
	assert_ne(fp_empty, fp_a)


func test_cid_first_reject_cached_same_fp_no_state_change() -> void:
	var session := _bootstrap_session("room-e307", "sess-reject-1", 24220)
	var meta := _find_discard_meta(session)
	assert_false(meta.is_empty(), "须有 DISCARD offer")
	if meta.is_empty():
		return
	var seq0: int = session.current_server_seq()
	var j0: Array = _journal_sizes(session)
	var room: String = str(meta.get("room_id", session.room_id))
	var bad := Action.from_dict({
		"protocol_version": 1,
		"command_id": _cmd(100),
		"room_id": room,
		"seat": int(meta.get("seat", 0)),
		"hand_seq": int(meta["hand_seq"]),
		"decision_id": _cmd(999),
		"kind": "DISCARD",
		"payload": {"tile_instance_id": int(meta["tile_instance_id"])},
		"client_seq": 1,
	})
	assert_not_null(bad)
	var cr1: CommandResult = session.submit_action_for_seat(0, bad)
	assert_not_null(cr1)
	assert_eq(cr1.status, "REJECTED")
	assert_ne(cr1.error_code, "COMMAND_ID_CONFLICT")
	assert_ne(cr1.error_code, "COMMAND_DUPLICATE")
	assert_eq(session.current_server_seq(), seq0, "首次拒绝不推进 seq")
	assert_eq(JSON.stringify(_journal_sizes(session)), JSON.stringify(j0))
	var frozen: Dictionary = cr1.to_dict().duplicate(true)

	var bad2 := Action.from_dict({
		"protocol_version": 1,
		"command_id": _cmd(100),
		"room_id": room,
		"seat": int(meta.get("seat", 0)),
		"hand_seq": int(meta["hand_seq"]),
		"decision_id": _cmd(999),
		"kind": "DISCARD",
		"payload": {"tile_instance_id": int(meta["tile_instance_id"])},
		"client_seq": 77,
	})
	var cr2: CommandResult = session.submit_action_for_seat(0, bad2)
	assert_eq(JSON.stringify(cr2.to_dict()), JSON.stringify(frozen),
		"同指纹须回放首次拒绝原 CR")
	assert_eq(session.current_server_seq(), seq0)
	assert_eq(JSON.stringify(_journal_sizes(session)), JSON.stringify(j0))


func test_cid_same_id_diff_fp_conflict_no_overwrite() -> void:
	var session := _bootstrap_session("room-e307", "sess-conflict-1", 24221)
	var meta := _find_discard_meta(session)
	assert_false(meta.is_empty())
	if meta.is_empty():
		return
	var w := _new_worker()
	w.inject_bound_session_for_test(1, session, 0, "sess-conflict-1")
	var body := _action_dict(meta, 200, 1)
	w.handle_dict_for_test(1, body)
	var out1: Array = w.test_outbox(1)
	var saw_accepted := false
	for m in out1:
		if str(m.get("status", "")) == "ACCEPTED":
			saw_accepted = true
			assert_eq(str(m.get("command_id", "")), _cmd(200))
			assert_true(int(m.get("server_seq", 0)) >= 1)
	assert_true(saw_accepted, "首次合法 DISCARD 须 ACCEPTED")
	var seq_ok: int = session.current_server_seq()
	var j_ok: Array = _journal_sizes(session)
	var auth0: String = _authority_hash(session)

	w.clear_outbox_for_test(1)
	var other_iid: int = int(meta["tile_instance_id"]) + 1
	if other_iid > int(meta["hand_seq"]) + 135:
		other_iid = int(meta["tile_instance_id"]) - 1
	var conflict := body.duplicate(true)
	conflict["payload"] = {"tile_instance_id": other_iid}
	conflict["client_seq"] = 2
	w.handle_dict_for_test(1, conflict)
	var out2: Array = w.test_outbox(1)
	assert_gt(out2.size(), 0)
	_assert_error_no_seq_hash(_last_error(out2), "COMMAND_ID_CONFLICT", "异指纹")
	assert_eq(session.current_server_seq(), seq_ok, "CONFLICT 不推进 seq")
	assert_eq(JSON.stringify(_journal_sizes(session)), JSON.stringify(j_ok))
	if not auth0.is_empty():
		assert_eq(_authority_hash(session), auth0)

	w.clear_outbox_for_test(1)
	var replay := body.duplicate(true)
	replay["client_seq"] = 3
	w.handle_dict_for_test(1, replay)
	var out3: Array = w.test_outbox(1)
	var saw_again := false
	for m in out3:
		if str(m.get("status", "")) == "ACCEPTED" and str(m.get("command_id", "")) == _cmd(200):
			saw_again = true
			assert_eq(int(m.get("server_seq", -1)), seq_ok,
				"幂等命中 server_seq 须为首次结果")
	assert_true(saw_again, "冲突后同指纹仍须首次 ACCEPTED")
	assert_eq(session.current_server_seq(), seq_ok)
	assert_eq(JSON.stringify(_journal_sizes(session)), JSON.stringify(j_ok))


func test_cid_session_id_binds_via_room_session_path() -> void:
	var room_id := "room-e307-bind"
	var session := HeadlessRoomSession.new()
	session.set_seed_override_for_test(24222)
	assert_true(session.bootstrap_from_claims({
		"room_id": room_id,
		"seat": 0,
		"session_id": "sess-bind-A",
		"round_kind": "EAST",
		"game_mode": "STANDARD",
		"participants": ["HUMAN", "AI", "AI", "AI"],
	}))
	assert_eq(session.config.session_id, room_id)
	assert_true(bool(session.join(0, "sess-bind-A")["ok"]))
	assert_true(bool(session.ready(0, "sess-bind-A")["ok"]))
	var act := Action.make_pass(0, room_id, _cmd(50), _cmd(51), 0, 1)
	var fp_via_a: String = session.server._business_fingerprint(act, "sess-bind-A")
	var fp_via_room: String = session.server._business_fingerprint(act, room_id)
	assert_ne(fp_via_a, fp_via_room)
	var cr: CommandResult = session.submit_action_for_seat(0, act)
	assert_eq(cr.status, "REJECTED")
	assert_ne(fp_via_a, session.server._business_fingerprint(act, "sess-bind-B"))


# ---------------------------------------------------------------------------
# P2-1：真实 Worker 入口早拒绝缓存（错 seat / 错 room / 未开局 / stale）
# ---------------------------------------------------------------------------

func test_worker_early_reject_wrong_seat_cached() -> void:
	var session := _bootstrap_session("room-e307-ws", "sess-ws-1", 24230)
	var meta := _find_discard_meta(session)
	assert_false(meta.is_empty(), "须有 DISCARD offer")
	if meta.is_empty():
		return
	var w := _new_worker()
	w.inject_bound_session_for_test(1, session, 0, "sess-ws-1")
	var body := _action_dict(meta, 310, 1)
	body["seat"] = 1  # 绑定 seat0，报文越权
	_assert_worker_early_reject_cached(w, 1, session, body, "UNAUTHORIZED", "wrong_seat")


func test_worker_early_reject_wrong_room_cached() -> void:
	var session := _bootstrap_session("room-e307-wr", "sess-wr-1", 24231)
	var meta := _find_discard_meta(session)
	assert_false(meta.is_empty())
	if meta.is_empty():
		return
	var w := _new_worker()
	w.inject_bound_session_for_test(1, session, 0, "sess-wr-1")
	var body := _action_dict(meta, 311, 1)
	body["room_id"] = "other-room-not-bound"
	_assert_worker_early_reject_cached(w, 1, session, body, "UNAUTHORIZED", "wrong_room")


func test_worker_early_reject_not_started_cached() -> void:
	# JOIN 已认证但未 READY/开局
	var session := _bootstrap_session("room-e307-ns", "sess-ns-1", 24232, false)
	assert_false(session.is_started())
	var w := _new_worker()
	w.inject_bound_session_for_test(1, session, 0, "sess-ns-1")
	# 可规范化 DISCARD payload；未开局拒绝须缓存
	var body := {
		"protocol_version": 1,
		"command_id": _cmd(312),
		"room_id": "room-e307-ns",
		"seat": 0,
		"hand_seq": 0,
		"decision_id": _cmd(812),
		"kind": "DISCARD",
		"payload": {"tile_instance_id": 1},
		"client_seq": 1,
	}
	# wire code：NOT_STARTED → COMMAND_REJECTED
	_assert_worker_early_reject_cached(w, 1, session, body, "COMMAND_REJECTED", "not_started")


func test_worker_early_reject_stale_connection_cached() -> void:
	var session := _bootstrap_session("room-e307-st", "sess-st-1", 24233)
	var meta := _find_discard_meta(session)
	assert_false(meta.is_empty())
	if meta.is_empty():
		return
	var w := _new_worker()
	w.inject_bound_session_for_test(1, session, 0, "sess-st-1")
	# 保留 Worker 绑定 session_id，但使 Room 连接失效 → stale
	var frozen: Dictionary = session.capture_seat_control_state(0)
	assert_false(frozen.is_empty())
	frozen["connected"] = false
	frozen["active_conn_id"] = -1
	session.restore_seat_control_state(0, frozen)
	assert_false(session.is_connection_active(0, 1, int(w.test_conn_binding(1).get("generation", -1))))
	var body := _action_dict(meta, 313, 1)
	_assert_worker_early_reject_cached(w, 1, session, body, "UNAUTHORIZED", "stale")


# ---------------------------------------------------------------------------
# 入口拒绝：非法牌 / 伪造服务端 EventKind（含 ITEM_GRANTED）
# ---------------------------------------------------------------------------

func test_entry_illegal_tile_rejected_no_state() -> void:
	var session := _bootstrap_session("room-e307", "sess-entry-1", 24234)
	var meta := _find_discard_meta(session)
	assert_false(meta.is_empty())
	if meta.is_empty():
		return
	var w := _new_worker()
	w.inject_bound_session_for_test(1, session, 0, "sess-entry-1")
	var seq0: int = session.current_server_seq()
	var j0: Array = _journal_sizes(session)
	w.clear_outbox_for_test(1)
	var bad_tile := _action_dict(meta, 301, 1)
	bad_tile["payload"] = {"tile_instance_id": 999999}
	w.handle_dict_for_test(1, bad_tile)
	var out2: Array = w.test_outbox(1)
	assert_gt(out2.size(), 0)
	var last2: Dictionary = _last_error(out2)
	assert_eq(str(last2.get("kind", "")), "ERROR")
	assert_false(last2.has("server_seq"))
	assert_false(last2.has("view_hash"))
	assert_false(last2.has("state_hash"))
	assert_ne(str(last2.get("code", "")), "COMMAND_DUPLICATE")
	assert_eq(session.current_server_seq(), seq0)
	assert_eq(JSON.stringify(_journal_sizes(session)), JSON.stringify(j0))


func test_forgery_server_event_kinds_including_item_granted() -> void:
	var session := _bootstrap_session("room-e307", "sess-forge-1", 24231)
	var w := _new_worker()
	w.inject_bound_session_for_test(1, session, 0, "sess-forge-1")
	var seq0: int = session.current_server_seq()
	var j0: Array = _journal_sizes(session)
	var forge_kinds: Array = ["ITEM_GRANTED", "ROOM_SNAPSHOT", "HAND_SETTLED", "ERROR"]
	for kind in forge_kinds:
		w.clear_outbox_for_test(1)
		w.handle_dict_for_test(1, {
			"protocol_version": 1,
			"kind": kind,
			"room_id": session.room_id,
			"seat": 0,
			"server_seq": 99,
			"payload": {},
			"view_hash": "a".repeat(64),
		})
		var out: Array = w.test_outbox(1)
		assert_gt(out.size(), 0, "kind %s" % kind)
		_assert_error_no_seq_hash(_last_error(out), "FORGERY_REJECTED", "forge %s" % kind)
		assert_eq(session.current_server_seq(), seq0, "forge %s 不推进" % kind)
		assert_eq(JSON.stringify(_journal_sizes(session)), JSON.stringify(j0),
			"forge %s journal 不变" % kind)


func test_illegal_json_and_non_normalizable_not_cached() -> void:
	var session := _bootstrap_session("room-e307", "sess-nocache-1", 24232)
	var w := _new_worker()
	w.inject_bound_session_for_test(1, session, 0, "sess-nocache-1")
	var cache0: int = _cache_size(session)
	w.handle_dict_for_test(1, {
		"protocol_version": 1,
		"command_id": _cmd(400),
		"room_id": session.room_id,
		"seat": 0,
		"hand_seq": 0,
		"decision_id": _cmd(401),
		"kind": "DISCARD",
		"payload": {"wrong_key": 1},
		"client_seq": 1,
	})
	var out: Array = w.test_outbox(1)
	assert_gt(out.size(), 0)
	assert_eq(str(_last_error(out).get("kind", "")), "ERROR")
	assert_eq(_cache_size(session), cache0,
		"不可规范化 payload 不得写入 command_cache")


# ---------------------------------------------------------------------------
# ERR-01：权威事件有 server_seq；ERROR 控制响应无 seq/hash
# ---------------------------------------------------------------------------

func test_err01_all_journal_events_have_seq_and_view_hash() -> void:
	var session := _bootstrap_session("room-e307", "sess-err01", 24240)
	for seat in range(4):
		for ne in session.event_journal(seat):
			assert_true(ne is NetworkedEvent)
			var e: NetworkedEvent = ne as NetworkedEvent
			assert_gt(e.server_seq, 0, "seat%d %s 须有 server_seq" % [seat, e.kind])
			assert_eq(e.view_hash.length(), 64, "seat%d %s 须有 view_hash" % [seat, e.kind])
			assert_ne(e.kind, "ERROR", "ERROR 不得进 journal")
	var w := _new_worker()
	w.inject_bound_session_for_test(1, session, 0, "sess-err01")
	w.handle_dict_for_test(1, {
		"protocol_version": 1,
		"kind": "ITEM_GRANTED",
		"room_id": session.room_id,
	})
	var out: Array = w.test_outbox(1)
	_assert_error_no_seq_hash(_last_error(out), "FORGERY_REJECTED", "ERR-01")


# ---------------------------------------------------------------------------
# 客户端连续性：缺口 / 重复 / view_hash 分叉 → resync
# ---------------------------------------------------------------------------

func test_client_gap_duplicate_and_view_hash_fork() -> void:
	var session := _bootstrap_session("room-e307", "sess-cont-1", 24250)
	var journal: Array = session.event_journal(0)
	assert_gt(journal.size(), 1, "须有真实权威事件")
	var nbc := NetworkedBattleController.new("room-e307", 0)
	assert_true(nbc.ingest_networked_event(journal[0]))
	if journal.size() > 1:
		assert_true(nbc.ingest_networked_event(journal[1]))
	var frozen_seq: int = nbc.current_seq()
	assert_gt(frozen_seq, 0)

	var non_snap: NetworkedEvent = null
	for ne in journal:
		var e: NetworkedEvent = ne as NetworkedEvent
		if e != null and e.kind != "ROOM_SNAPSHOT" and e.server_seq <= frozen_seq:
			non_snap = e
			break
	if non_snap != null:
		assert_true(nbc.ingest_networked_event(non_snap), "重复/过期非 snapshot 须幂等忽略")
		assert_false(nbc.resync_required(), "重复不得 resync")
		assert_eq(nbc.current_seq(), frozen_seq)
	var old_snap: NetworkedEvent = journal[0] as NetworkedEvent
	if old_snap != null and old_snap.kind == "ROOM_SNAPSHOT":
		assert_false(nbc.ingest_networked_event(old_snap), "过期 snapshot 须拒绝")
		assert_eq(nbc.current_seq(), frozen_seq)

	var gap_src: NetworkedEvent = null
	for ne in journal:
		if (ne as NetworkedEvent).kind == "TURN_PROMPT" \
				or (ne as NetworkedEvent).kind == "ACTION_APPLIED":
			gap_src = ne as NetworkedEvent
			break
	if gap_src == null:
		gap_src = journal[journal.size() - 1] as NetworkedEvent
	var gap_d: Dictionary = gap_src.to_dict()
	gap_d["server_seq"] = frozen_seq + 5
	var gap_ne: NetworkedEvent = NetworkedEvent.from_dict(gap_d)
	assert_not_null(gap_ne, "gap fixture 须可构造")
	if gap_ne != null:
		assert_false(nbc.ingest_networked_event(gap_ne), "缺口须失败")
		assert_true(nbc.resync_required(), "缺口 → resync_required")

	var nbc3 := NetworkedBattleController.new("room-e307", 0)
	assert_true(nbc3.ingest_networked_event(journal[0]))
	var base_seq: int = nbc3.current_seq()
	for ne in journal:
		var src: NetworkedEvent = ne as NetworkedEvent
		if src.kind != "TURN_PROMPT":
			continue
		var d: Dictionary = src.to_dict()
		d["server_seq"] = base_seq + 1
		d["view_hash"] = "c".repeat(64)
		var forged: NetworkedEvent = NetworkedEvent.from_dict(d)
		assert_not_null(forged)
		if forged == null:
			break
		assert_true(nbc3.ingest_networked_event(forged), "异 view_hash 下一增量进 pending")
		assert_false(nbc3.resync_required(), "pending 本身不置 resync")
		var snap_src: NetworkedEvent = journal[0] as NetworkedEvent
		assert_eq(snap_src.kind, "ROOM_SNAPSHOT")
		var sd: Dictionary = snap_src.to_dict()
		sd["server_seq"] = base_seq + 2
		var sp: Dictionary = (sd["payload"] as Dictionary).duplicate(true)
		sp["snapshot_server_seq"] = base_seq + 2
		sp["next_server_seq"] = base_seq + 3
		sd["payload"] = sp
		sd["view_hash"] = ProtocolViewCodec.compute_view_hash(sp)
		var bad_snap: NetworkedEvent = NetworkedEvent.from_dict(sd)
		assert_not_null(bad_snap)
		if bad_snap != null:
			assert_ne(bad_snap.view_hash, forged.view_hash)
			assert_false(nbc3.ingest_networked_event(bad_snap), "view_hash 分叉须拒绝")
			assert_true(nbc3.resync_required(), "view_hash 分叉 → resync_required")
		break


# ---------------------------------------------------------------------------
# SNAP-01..05 + provider 真实 round-trip / 原子失败 / RewardWindow 兼容
# ---------------------------------------------------------------------------

func test_snap_fields_and_legacy_last_server_seq_rejected() -> void:
	var session := _bootstrap_session("room-e307", "sess-snap-1", 24260)
	var journal: Array = session.event_journal(0)
	var snap: NetworkedEvent = null
	for ne in journal:
		if (ne as NetworkedEvent).kind == "ROOM_SNAPSHOT":
			snap = ne as NetworkedEvent
			break
	assert_not_null(snap, "须有 ROOM_SNAPSHOT")
	if snap == null:
		return
	var p: Dictionary = snap.payload
	assert_true(p.has("snapshot_server_seq"), "SNAP-01")
	assert_true(p.has("next_server_seq"), "SNAP-01")
	assert_false(p.has("last_server_seq"), "SNAP-04 禁 last_server_seq 出现在合法载荷")
	assert_eq(int(p["snapshot_server_seq"]), snap.server_seq, "SNAP-02")
	assert_eq(int(p["next_server_seq"]), snap.server_seq + 1, "SNAP-02")
	var legacy := {
		"protocol_version": 1,
		"server_seq": 1,
		"room_id": session.room_id,
		"kind": "ROOM_SNAPSHOT",
		"payload": {
			"last_server_seq": 1,
			"seat_view": 0,
			"modules": [],
		},
		"view_hash": "a".repeat(64),
	}
	assert_null(NetworkedEvent.from_dict(legacy), "SNAP-04 last_server_seq 须拒绝")


func test_snapshot_provider_roundtrip_standard_and_reward_compat() -> void:
	# —— STANDARD：真实 BC serialize → ROOM_SNAPSHOT → NBC ingest round-trip ——
	var session := _bootstrap_session("room-e307-snap", "sess-snap-2", 24261)
	var journal: Array = session.event_journal(0)
	var snap: NetworkedEvent = null
	for ne in journal:
		if (ne as NetworkedEvent).kind == "ROOM_SNAPSHOT":
			snap = ne as NetworkedEvent
			break
	assert_not_null(snap, "须有真实 ROOM_SNAPSHOT")
	if snap == null:
		return
	var mods: Array = snap.payload.get("modules", [])
	assert_gt(mods.size(), 0)
	for m in mods:
		assert_ne(str((m as Dictionary).get("module_key", "")), "reward_window",
			"STANDARD 不注册 reward_window")

	var nbc := NetworkedBattleController.new(session.room_id, 0)
	assert_true(nbc.snapshot_registry.is_standard_only())
	assert_true(nbc.ingest_networked_event(snap),
		"STANDARD SNAP 须 ingest err=%s" % nbc.last_snapshot_error())
	assert_eq(nbc.current_seq(), snap.server_seq)
	assert_eq(nbc.expected_next_server_seq(), int(snap.payload["next_server_seq"]))
	var core: Dictionary = nbc.get_core_table_view()
	assert_false(core.is_empty(), "须 restore core_table")
	assert_eq(int(core.get("recipient_seat", -1)), 0)
	# wire round-trip 字段不变（SNAP-05）
	var back: NetworkedEvent = NetworkedEvent.from_dict(snap.to_dict())
	assert_not_null(back)
	assert_eq(int(back.server_seq), snap.server_seq)
	assert_eq(int(back.payload["snapshot_server_seq"]), int(snap.payload["snapshot_server_seq"]))
	assert_eq(int(back.payload["next_server_seq"]), int(snap.payload["next_server_seq"]))

	# —— 未知必需 schema version：原子失败，NBC 状态不变 ——
	var seq_ok: int = nbc.current_seq()
	var j_ok: int = nbc.get_event_journal().size()
	var view_ok: Dictionary = nbc.get_public_view().duplicate(true)
	var core_ok: Dictionary = nbc.get_core_table_view().duplicate(true)
	var bad_schema_mods: Array = []
	for m in mods:
		var md: Dictionary = (m as Dictionary).duplicate(true)
		if str(md.get("module_key", "")) == "core_table":
			md["schema_version"] = 99999
		bad_schema_mods.append(md)
	var bad_payload: Dictionary = snap.payload.duplicate(true)
	bad_payload["modules"] = bad_schema_mods
	bad_payload["snapshot_server_seq"] = seq_ok + 1
	bad_payload["next_server_seq"] = seq_ok + 2
	var bad_vh: String = ProtocolViewCodec.compute_view_hash(bad_payload)
	var bad_ne: NetworkedEvent = NetworkedEvent.make(
		"ROOM_SNAPSHOT", seq_ok + 1, session.room_id, bad_payload, bad_vh
	)
	# NetworkedEvent.make 可能因 payload 校验失败返回 null；registry 路径用 restore 直接证
	var reg := SnapshotModuleRegistry.make_standard()
	var restore_schema: Dictionary = reg.restore_modules(bad_schema_mods, 0, nbc)
	assert_false(bool(restore_schema.get("ok", true)), "未知必需 schema 须失败")
	assert_eq(str(restore_schema.get("code", "")), SnapshotModuleRegistry.ERR_SCHEMA_UNSUPPORTED)
	assert_eq(nbc.current_seq(), seq_ok, "schema 失败不推进 seq")
	assert_eq(nbc.get_event_journal().size(), j_ok, "schema 失败不写 journal")
	assert_eq(JSON.stringify(nbc.get_public_view()), JSON.stringify(view_ok),
		"schema 失败 public_view 不变")
	assert_eq(JSON.stringify(nbc.get_core_table_view()), JSON.stringify(core_ok),
		"schema 失败 modules 不变")

	# —— 损坏 payload：空 core_table → 原子失败 ——
	var corrupt_mods: Array = [{
		"module_key": "core_table",
		"schema_version": 1,
		"payload": {},
	}]
	var restore_corrupt: Dictionary = reg.restore_modules(corrupt_mods, 0, nbc)
	assert_false(bool(restore_corrupt.get("ok", true)), "损坏 payload 须失败")
	assert_eq(nbc.current_seq(), seq_ok, "损坏失败不推进 seq")
	assert_eq(nbc.get_event_journal().size(), j_ok)
	assert_eq(JSON.stringify(nbc.get_core_table_view()), JSON.stringify(core_ok),
		"损坏失败 modules 不变")

	# —— RewardWindow provider：TRASH_TALK 真实 LLS + NBC round-trip（不扩 E5 业务）——
	var cfg_tt := GameSessionConfig.create_validated(
		GameSessionConfig.ROOM_PRACTICE, GameSessionConfig.ROUND_EAST,
		GameSessionConfig.MODE_TRASH_TALK, PARTS, CHARS, 19, "rw-e307-tt", "rv-e307"
	)
	var server_tt := LocalLoopbackServer.new(cfg_tt, 0)
	assert_true(server_tt.snapshot_registry.is_trash_talk_registry())
	var keys_tt: Array = server_tt.snapshot_registry.registered_keys()
	assert_eq(keys_tt.size(), 2)
	assert_eq(str(keys_tt[0]), "core_table")
	assert_eq(str(keys_tt[1]), "reward_window")
	assert_true(server_tt.start())
	assert_true(server_tt.publish_snapshot())
	var snap_tt: NetworkedEvent = null
	for ne in server_tt.event_journal(0):
		if ne is NetworkedEvent and (ne as NetworkedEvent).kind == "ROOM_SNAPSHOT":
			snap_tt = ne as NetworkedEvent
	assert_not_null(snap_tt, "TRASH_TALK 须有 SNAP")
	if snap_tt == null:
		return
	var tt_keys: Array = []
	for m2 in snap_tt.payload.get("modules", []):
		tt_keys.append(str((m2 as Dictionary).get("module_key", "")))
	assert_eq(tt_keys.size(), 2)
	assert_eq(str(tt_keys[0]), "core_table")
	assert_eq(str(tt_keys[1]), "reward_window")
	var room_tt: String = str(server_tt.get("_room_id"))
	var nbc_tt := NetworkedBattleController.new(room_tt, 0)
	nbc_tt.configure_snapshot_registry_for_mode(str(GameSessionConfig.MODE_TRASH_TALK))
	assert_true(nbc_tt.snapshot_registry.is_trash_talk_registry())
	assert_true(
		nbc_tt.ingest_networked_event(snap_tt),
		"RW SNAP 须 restore err=%s" % nbc_tt.last_snapshot_error()
	)
	var rw_view: Dictionary = nbc_tt.get_reward_window_view()
	assert_false(rw_view.is_empty(), "须有 reward_window 公共投影")
	assert_true(rw_view.has("phase") or rw_view.has("window_id"),
		"公开投影含 phase/window_id")
	assert_false(rw_view.has("seed"), "公开投影不得含 seed")
	assert_false(rw_view.has("match_seed"))
	# 不实现/扩张发奖业务
	var kinds_tt: Array = []
	for ne3 in server_tt.event_journal(0):
		kinds_tt.append((ne3 as NetworkedEvent).kind)
	for rk in REWARD_KINDS:
		if rk == "REWARD_WINDOW_OPENED" or rk == "REWARD_WINDOW_CLOSING" \
				or rk == "REWARD_WINDOW_SETTLED" or rk == "REWARD_WINDOW_CANCELLED":
			continue  # 窗口事件可由 #252 权威产生；本 Issue 不扩 ITEM/武装
	assert_false(kinds_tt.has("ITEM_GRANTED"), "#242 不扩 ITEM_GRANTED")
	assert_false(kinds_tt.has("CHARACTER_ABILITY_ARMED"))


# ---------------------------------------------------------------------------
# 确定性核心事件摘要（同 seed + 真实合法命令流）
# ---------------------------------------------------------------------------

func test_core_event_digest_deterministic_same_seed_and_commands() -> void:
	var d1: String = _run_core_digest_once(DIGEST_SEED, "room-dig-a", "sess-dig-a")
	var d2: String = _run_core_digest_once(DIGEST_SEED, "room-dig-b", "sess-dig-b")
	assert_eq(d1.length(), 64, "digest 须 SHA-256 hex")
	assert_eq(d2.length(), 64)
	assert_eq(d1, d2, "同 seed + 同等合法命令流 → 相同核心摘要")
	var d3: String = _run_core_digest_once(DIGEST_SEED + 1, "room-dig-c", "sess-dig-c")
	assert_ne(d1, d3, "不同 seed 核心摘要应不同")


func _run_core_digest_once(seed: int, room_id: String, sess: String) -> String:
	var session := HeadlessRoomSession.new()
	session.set_seed_override_for_test(seed)
	assert_true(session.bootstrap_from_claims({
		"room_id": room_id,
		"seat": 0,
		"session_id": sess,
		"round_kind": "EAST",
		"game_mode": "STANDARD",
		"participants": ["HUMAN", "AI", "AI", "AI"],
	}))
	assert_true(bool(session.join(0, sess)["ok"]))
	assert_true(bool(session.ready(0, sess)["ok"]))
	assert_true(session.is_started())
	assert_true(session.server.has_method("core_event_digest"),
		"LocalLoopbackServer 须暴露 core_event_digest")
	if not session.server.has_method("core_event_digest"):
		return ""
	# 真实合法命令流：提取 offer，固定 command_id 提交至少一条 ACCEPTED DISCARD
	var meta := _find_discard_meta(session)
	assert_false(meta.is_empty(), "须有 DISCARD offer 才能构成合法命令流")
	if meta.is_empty():
		return ""
	var act := Action.from_dict({
		"protocol_version": 1,
		"command_id": _cmd(DIGEST_CMD_N),
		"room_id": room_id,
		"seat": int(meta.get("seat", 0)),
		"hand_seq": int(meta["hand_seq"]),
		"decision_id": str(meta["decision_id"]),
		"kind": "DISCARD",
		"payload": {"tile_instance_id": int(meta["tile_instance_id"])},
		"client_seq": 1,
	})
	assert_not_null(act)
	var cr: CommandResult = session.submit_action_for_seat(0, act)
	assert_not_null(cr)
	assert_eq(cr.status, "ACCEPTED", "合法命令流须至少一条 ACCEPTED")
	# 摘要材料仅 seat0 六类核心；不含 view_hash / Reward-Item-Ability
	var digest: String = str(session.server.core_event_digest(0))
	var saw_aa := false
	for ne in session.event_journal(0):
		var k: String = (ne as NetworkedEvent).kind
		if k == "ACTION_APPLIED":
			saw_aa = true
		assert_false(k in ["ITEM_GRANTED", "ITEM_CONSUMED", "ITEM_APPLIED",
			"CHARACTER_ABILITY_ARMED", "CHARACTER_ABILITY_DISARMED"],
			"核心摘要路径不得依赖 Item/Ability 事件")
	assert_true(saw_aa, "合法命令流后 journal 须含 ACTION_APPLIED")
	return digest


func test_no_command_duplicate_string_in_production_codes() -> void:
	var session := _bootstrap_session("room-e307", "sess-nodup", 24280)
	var w := _new_worker()
	w.inject_bound_session_for_test(1, session, 0, "sess-nodup")
	var meta := _find_discard_meta(session)
	if meta.is_empty():
		return
	var body := _action_dict(meta, 500, 1)
	w.handle_dict_for_test(1, body)
	w.clear_outbox_for_test(1)
	body["client_seq"] = 2
	w.handle_dict_for_test(1, body)
	for m in w.test_outbox(1):
		assert_ne(str(m.get("code", "")), "COMMAND_DUPLICATE")
		assert_ne(str(m.get("error_code", "")), "COMMAND_DUPLICATE")
	w.clear_outbox_for_test(1)
	body["payload"] = {"tile_instance_id": int(meta["tile_instance_id"]) + 1}
	body["client_seq"] = 3
	w.handle_dict_for_test(1, body)
	for m in w.test_outbox(1):
		assert_ne(str(m.get("code", "")), "COMMAND_DUPLICATE")
		if str(m.get("kind", "")) == "ERROR":
			assert_eq(str(m.get("code", "")), "COMMAND_ID_CONFLICT")
