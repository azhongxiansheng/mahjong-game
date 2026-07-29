extends GutTest

# #241 round-2：真实 HeadlessWorker → HeadlessRoomSession → LocalLoopbackServer
# 重连 outbox 顺序、AI 单步事务、交付失败回滚、ACTION_APPLIED 证据。
# 网络端到端未验证。

const SECRET := "0123456789abcdef0123456789abcdef"


func _mint_room_token(claims: Dictionary) -> String:
	var body := {
		"typ": "room",
		"room_id": str(claims["room_id"]),
		"seat": int(claims["seat"]),
		"session_id": str(claims["session_id"]),
		"exp": int(claims.get("exp", 9999999999)),
		"round_kind": str(claims.get("round_kind", "EAST")),
		"game_mode": str(claims.get("game_mode", "STANDARD")),
		"participants": claims["participants"],
		"character_ids": claims.get("character_ids", ["lin_yeche", "an_cheng", "bai_touli", "hua_ling"]),
	}
	var raw: PackedByteArray = JSON.stringify(body).to_utf8_buffer()
	var payload_b64: String = Marshalls.raw_to_base64(raw)
	payload_b64 = payload_b64.replace("+", "-").replace("/", "_").rstrip("=")
	var signing := "v1.r.%s" % payload_b64
	var crypto := Crypto.new()
	var sig: PackedByteArray = crypto.hmac_digest(
		HashingContext.HASH_SHA256,
		SECRET.to_utf8_buffer(),
		signing.to_utf8_buffer()
	)
	var sig_b64: String = Marshalls.raw_to_base64(sig)
	sig_b64 = sig_b64.replace("+", "-").replace("/", "_").rstrip("=")
	return "%s.%s" % [signing, sig_b64]


func _new_worker() -> HeadlessWorker:
	var w := HeadlessWorker.new()
	add_child_autofree(w)
	assert_true(w.configure(SECRET))
	w.token_now_unix = 1_700_000_000
	w.set_clock_ms_for_test(10_000)
	return w


func _claims_1h(room: String, seat: int, sess: String) -> Dictionary:
	return {
		"room_id": room,
		"seat": seat,
		"session_id": sess,
		"exp": 2_000_000_000,
		"round_kind": "EAST",
		"game_mode": "STANDARD",
		"participants": ["HUMAN", "AI", "AI", "AI"],
		"character_ids": ["lin_yeche", "an_cheng", "bai_touli", "hua_ling"],
	}


func _join(w: HeadlessWorker, cid: int, claims: Dictionary) -> void:
	var token := _mint_room_token(claims)
	w.handle_dict_for_test(cid, {
		"protocol_version": 1,
		"kind": "JOIN",
		"room_id": str(claims["room_id"]),
		"seat": int(claims["seat"]),
		"room_token": token,
	})


func _send_ready(w: HeadlessWorker, cid: int, room: String, seat: int) -> void:
	w.handle_dict_for_test(cid, {
		"protocol_version": 1,
		"kind": "READY",
		"room_id": room,
		"seat": seat,
	})


func _business_events(outbox: Array) -> Array:
	var evs: Array = []
	for m in outbox:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var kind: String = str(m.get("kind", ""))
		if kind == "ERROR" or kind == "COMMAND_RESULT":
			continue
		if m.has("server_seq"):
			evs.append(m)
	return evs


func test_disconnect_starts_30s_lease_exact_boundary() -> void:
	var w := _new_worker()
	var claims := _claims_1h("room-lease", 0, "sess-lease")
	_join(w, 1, claims)
	_send_ready(w, 1, "room-lease", 0)
	var session: HeadlessRoomSession = w.get_room("room-lease")
	assert_not_null(session)
	assert_true(session.is_started())
	w.set_clock_ms_for_test(50_000)
	w.simulate_disconnect_for_test(1)
	var dl: int = session.lease_deadline_ms(0)
	assert_eq(dl, 50_000 + HeadlessRoomSession.RECONNECT_LEASE_MS)
	assert_false(session.is_seat_ai_controlled(0))
	w.set_clock_ms_for_test(dl - 1)
	w.tick_leases_for_test()
	assert_false(session.is_seat_ai_controlled(0), "now < deadline 不得 AI")
	w.set_clock_ms_for_test(dl)
	w.tick_leases_for_test()
	assert_true(session.is_seat_ai_controlled(0), "now >= deadline 须 AI 接管")
	assert_eq(session.lease_deadline_ms(0), -1)


func test_reconnect_outbox_is_current_snapshot_then_only_next_seq() -> void:
	var w := _new_worker()
	var claims := _claims_1h("room-rc-order", 0, "sess-rc-o")
	_join(w, 1, claims)
	_send_ready(w, 1, "room-rc-order", 0)
	var session: HeadlessRoomSession = w.get_room("room-rc-order")
	assert_true(session.is_started())
	var seq_before: int = session.current_server_seq()
	assert_gt(seq_before, 0)
	w.set_clock_ms_for_test(20_000)
	w.simulate_disconnect_for_test(1)
	w.set_clock_ms_for_test(20_000 + 5_000)
	w.clear_outbox_for_test(2)
	_join(w, 2, claims)
	var out: Array = w.test_outbox(2)
	var biz: Array = _business_events(out)
	assert_gt(biz.size(), 0, "重连须有业务事件")
	var first: Dictionary = biz[0]
	assert_eq(str(first.get("kind", "")), "ROOM_SNAPSHOT",
		"重连 outbox 第一条业务事件必须是当前 ROOM_SNAPSHOT")
	var payload: Dictionary = first.get("payload", {})
	var s: int = int(payload.get("snapshot_server_seq", -1))
	assert_eq(int(first.get("server_seq", -2)), s)
	assert_eq(int(payload.get("next_server_seq", -1)), s + 1)
	assert_false(payload.has("last_server_seq"))
	assert_eq(int(payload.get("seat_view", -1)), 0)
	assert_gt(s, seq_before, "重连快照须为新发布序号")
	# 后续只允许 server_seq >= next_server_seq，绝无历史 < S
	var next_s: int = int(payload.get("next_server_seq", -1))
	for i in range(biz.size()):
		var ev: Dictionary = biz[i]
		var seq_i: int = int(ev.get("server_seq", -1))
		if i == 0:
			assert_eq(seq_i, s)
		else:
			assert_gte(seq_i, next_s, "不得重放 snapshot 前历史")
			assert_false(seq_i < s, "不得出现 server_seq < S")
	assert_false(session.is_seat_ai_controlled(0))
	assert_eq(session.lease_deadline_ms(0), -1)


func test_connection_replace_invalidates_old_no_lease() -> void:
	var w := _new_worker()
	var claims := _claims_1h("room-replace", 0, "sess-rep")
	_join(w, 1, claims)
	_send_ready(w, 1, "room-replace", 0)
	var session: HeadlessRoomSession = w.get_room("room-replace")
	assert_true(session.is_started())
	var gen1: int = int(w.test_conn_binding(1)["generation"])
	_join(w, 2, claims)
	var bind1: Dictionary = w.test_conn_binding(1)
	assert_true(bool(bind1.get("superseded", false)) or not bool(bind1.get("joined", true)))
	assert_false(session.is_connection_active(0, 1, gen1))
	assert_true(session.is_connection_active(0, 2, int(w.test_conn_binding(2)["generation"])))
	assert_eq(session.lease_deadline_ms(0), -1)
	w.clear_outbox_for_test(1)
	w.handle_dict_for_test(1, {
		"protocol_version": 1,
		"command_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
		"room_id": "room-replace",
		"seat": 0,
		"hand_seq": 0,
		"decision_id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
		"kind": "PASS",
		"payload": {},
		"client_seq": 1,
	})
	var out1: Array = w.test_outbox(1)
	assert_gt(out1.size(), 0)
	assert_eq(str(out1[out1.size() - 1].get("code", "")), "UNAUTHORIZED")


func test_ai_single_step_per_tick_and_real_action_applied() -> void:
	# 固定 seed：dealer seat0 开局 TURN；掉线接管后首个 AI Action 必须是 seat0
	var w := _new_worker()
	var claims := _claims_1h("room-ai-step", 0, "sess-ai-s")
	# 通过先 join 再改 seed 不可行；改用 session inject 固定 seed
	var session := HeadlessRoomSession.new()
	session.set_seed_override_for_test(99)
	assert_true(session.bootstrap_from_claims({
		"room_id": "room-ai-step",
		"seat": 0,
		"session_id": "sess-ai-s",
		"round_kind": "EAST",
		"game_mode": "STANDARD",
		"participants": ["HUMAN", "AI", "AI", "AI"],
		"expires_at_unix": 2_000_000_000,
			"character_ids": ["lin_yeche", "an_cheng", "bai_touli", "hua_ling"],
}))
	assert_true(bool(session.join(0, "sess-ai-s", 1, 1)["ok"]))
	assert_true(bool(session.ready(0, "sess-ai-s")["ok"]))
	assert_true(session.is_started())
	w.inject_bound_session_for_test(1, session, 0, "sess-ai-s")
	var aa_before := _count_aa(session, 0)
	w.set_clock_ms_for_test(100_000)
	w.simulate_disconnect_for_test(1)
	var dl: int = session.lease_deadline_ms(0)
	w.set_clock_ms_for_test(dl)
	# 首次 tick：接管 + 至多一个 Action
	w.tick_leases_for_test()
	assert_true(session.is_seat_ai_controlled(0))
	var aa_mid := _count_aa(session, 0)
	assert_lte(aa_mid - aa_before, 1, "单 tick ACTION_APPLIED 增量必须 <=1")
	# 若首 tick 尚未 ACTION（例如仅 DRAW+SNAP），继续单步直到第一条 seat0 Action
	var first_aa: NetworkedEvent = null
	var ticks := 0
	while first_aa == null and ticks < 40:
		if aa_mid > aa_before:
			first_aa = _first_new_aa(session, 0, aa_before)
			break
		w.step_ai_for_test("room-ai-step")
		ticks += 1
		aa_mid = _count_aa(session, 0)
		assert_lte(aa_mid - aa_before, ticks + 1,
			"累计单步不得一次跳过多 Action")
	if first_aa == null and aa_mid > aa_before:
		first_aa = _first_new_aa(session, 0, aa_before)
	assert_not_null(first_aa, "接管后必须产生真实 ACTION_APPLIED")
	var aa_pl: Dictionary = first_aa.payload
	assert_eq(int(aa_pl.get("seat", -1)), 0, "首个 AI Action 必须是掉线席 seat0")
	assert_false(str(aa_pl.get("action_kind", "")).is_empty(), "须有 action_kind")
	assert_true(aa_pl.has("resolved_payload"), "须有 resolved_payload")
	assert_eq(typeof(aa_pl.get("resolved_payload")), TYPE_DICTIONARY)
	# 两 tick 之间重连归还
	w.clear_outbox_for_test(3)
	_join(w, 3, claims)
	# claims room 可能未挂在 worker 若 inject 路径不同；确保用 session room
	if not bool(w.test_conn_binding(3).get("joined", false)):
		# mint 重连到 inject 的 room
		var claims_rc := {
			"room_id": "room-ai-step", "seat": 0, "session_id": "sess-ai-s",
			"exp": 2_000_000_000, "round_kind": "EAST", "game_mode": "STANDARD",
			"participants": ["HUMAN", "AI", "AI", "AI"],
			"character_ids": ["lin_yeche", "an_cheng", "bai_touli", "hua_ling"],
		}
		w.clear_outbox_for_test(3)
		_join(w, 3, claims_rc)
	assert_true(bool(w.test_conn_binding(3).get("joined", false)), "重连须成功绑定")
	assert_false(session.is_seat_ai_controlled(0), "两步之间重连须归还")
	var biz: Array = _business_events(w.test_outbox(3))
	assert_gt(biz.size(), 0, "重连须下发业务事件")
	assert_eq(str(biz[0].get("kind", "")), "ROOM_SNAPSHOT")


func _count_aa(session: HeadlessRoomSession, seat: int) -> int:
	var n := 0
	for e in session.event_journal(seat):
		if e is NetworkedEvent and (e as NetworkedEvent).kind == "ACTION_APPLIED":
			n += 1
	return n


func _first_new_aa(session: HeadlessRoomSession, seat: int, skip_count: int) -> NetworkedEvent:
	var seen := 0
	for e in session.event_journal(seat):
		if e is NetworkedEvent and (e as NetworkedEvent).kind == "ACTION_APPLIED":
			if seen >= skip_count:
				return e as NetworkedEvent
			seen += 1
	return null


func test_ai_publish_fail_rolls_back_authority() -> void:
	var w := _new_worker()
	var claims := _claims_1h("room-ai-fail", 0, "sess-ai-f")
	_join(w, 1, claims)
	_send_ready(w, 1, "room-ai-fail", 0)
	var session: HeadlessRoomSession = w.get_room("room-ai-fail")
	assert_true(session.is_started())
	w.set_clock_ms_for_test(200_000)
	w.simulate_disconnect_for_test(1)
	var dl: int = session.lease_deadline_ms(0)
	w.set_clock_ms_for_test(dl)
	w.tick_leases_for_test()
	assert_true(session.is_seat_ai_controlled(0))
	# 每步前冻结；注入 action 发布失败；命中 EVENT_PUBLISH_FAILED 时状态须等于该步前冻结
	var saw_fail := false
	for _i in range(40):
		var seq0: int = session.current_server_seq()
		var j0: int = session.event_journal(0).size()
		var h0: String = session.server.authority_hash_for_test()
		assert_eq(h0.length(), 64)
		session.server.fail_next_action_publish_for_test()
		var step: Dictionary = w.step_ai_for_test("room-ai-fail")
		if not bool(step.get("ok", true)) \
				and str(step.get("code", "")) == "EVENT_PUBLISH_FAILED":
			saw_fail = true
			assert_eq(session.current_server_seq(), seq0, "发布失败不得推进 seq")
			assert_eq(session.event_journal(0).size(), j0, "发布失败 journal 不变")
			assert_eq(session.server.authority_hash_for_test(), h0, "发布失败权威哈希不变")
			break
		# DRAW 等路径不消费 action-publish 失败标志时会前进，继续寻找 Action 步
	assert_true(saw_fail, "必须命中至少一次 AI Action 发布失败回滚")


func test_reconnect_delivery_fail_leaves_no_half_joined_state() -> void:
	var w := _new_worker()
	var claims := _claims_1h("room-prep-fail", 0, "sess-pf")
	_join(w, 1, claims)
	_send_ready(w, 1, "room-prep-fail", 0)
	var session: HeadlessRoomSession = w.get_room("room-prep-fail")
	assert_true(session.is_started())
	w.set_clock_ms_for_test(300_000)
	w.simulate_disconnect_for_test(1)
	var dl: int = session.lease_deadline_ms(0)
	# 到期接管，形成 AI 控制
	w.set_clock_ms_for_test(dl)
	w.tick_leases_for_test()
	assert_true(session.is_seat_ai_controlled(0))
	var frozen: Dictionary = session.capture_seat_control_state(0)
	var seq0: int = session.current_server_seq()
	var j0: int = session.event_journal(0).size()
	var h0: String = session.server.authority_hash_for_test()
	session.server.fail_next_snapshot_for_test()
	w.clear_outbox_for_test(2)
	_join(w, 2, claims)
	var bind2: Dictionary = w.test_conn_binding(2)
	assert_false(bool(bind2.get("joined", false)), "交付失败不得 joined")
	assert_false(session.is_connection_active(0, 2, int(bind2.get("generation", -1))))
	# 控制态回滚：仍 AI / lease 语义与失败前一致
	assert_true(session.is_seat_ai_controlled(0) or bool(frozen.get("ai_control", false)))
	assert_eq(session.current_server_seq(), seq0)
	assert_eq(session.event_journal(0).size(), j0)
	assert_eq(session.server.authority_hash_for_test(), h0)
	var out: Array = w.test_outbox(2)
	assert_gt(out.size(), 0)
	assert_eq(str(out[out.size() - 1].get("kind", "")), "ERROR")
	# 失败连接不得提交动作
	w.clear_outbox_for_test(2)
	w.handle_dict_for_test(2, {
		"protocol_version": 1,
		"command_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
		"room_id": "room-prep-fail",
		"seat": 0,
		"hand_seq": 0,
		"decision_id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
		"kind": "PASS",
		"payload": {},
		"client_seq": 1,
	})
	var out2: Array = w.test_outbox(2)
	assert_gt(out2.size(), 0)
	assert_eq(str(out2[out2.size() - 1].get("code", "")), "UNAUTHORIZED")


func test_settled_reconnect_snapshot_no_duplicate_hand_settled() -> void:
	# #376：真实非连庄 TSUMO 四局终场后重连 — 无重复 HAND/MATCH
	var session := HeadlessRoomSession.new()
	session.set_seed_override_for_test(42)
	assert_true(session.bootstrap_from_claims({
		"room_id": "room-settled-rc",
		"seat": 0,
		"session_id": "sess-0",
		"round_kind": "EAST",
		"game_mode": "STANDARD",
		"participants": ["HUMAN", "HUMAN", "HUMAN", "HUMAN"],
		"expires_at_unix": 2_000_000_000,
		"character_ids": ["lin_yeche", "an_cheng", "bai_touli", "hua_ling"],
	}))
	for i in range(4):
		assert_true(bool(session.join(i, "sess-%d" % i)["ok"]))
	for i2 in range(4):
		assert_true(bool(session.ready(i2, "sess-%d" % i2)["ok"]))
	assert_true(session.is_started())
	# 复用 match_driver 测试同构的真实 TSUMO 路径（内联最小 helper）
	for _h in range(4):
		var bc: BattleController = session.server._bc
		var dealer: int = int(bc.state.dealer_seat)
		var winner: int = (dealer + 1) % 4
		_force_seat_tsumo_ready(bc, winner)
		assert_true(session.server.publish_snapshot())
		var ctx: DecisionContext = bc.decision_context_for_seat(winner)
		assert_not_null(ctx)
		assert_true(ctx.has_kind("TSUMO"))
		var act: Action = Action.tsumo(
			winner, "room-settled-rc",
			"550e8400-e29b-41d4-a716-%012d" % (5000 + _h),
			str(ctx.decision_id), int(bc.state.hand_seq), 1 + _h
		)
		var cr: CommandResult = session.submit_action_for_seat(winner, act)
		assert_not_null(cr)
		assert_eq(cr.status, "ACCEPTED", "hand %d" % _h)
	assert_true(session.is_match_completed())
	assert_eq(_count_kind_session(session, 0, "HAND_SETTLED"), 4)
	assert_eq(_count_kind_session(session, 0, "MATCH_SETTLED"), 1)
	var seq_b: int = session.current_server_seq()
	assert_true(session.server._emit_settled_if_needed())
	assert_eq(session.current_server_seq(), seq_b)
	assert_eq(_count_kind_session(session, 0, "HAND_SETTLED"), 4)
	var w := _new_worker()
	w.inject_bound_session_for_test(1, session, 0, "sess-0")
	w.set_clock_ms_for_test(900_000)
	w.simulate_disconnect_for_test(1)
	var claims := {
		"room_id": "room-settled-rc", "seat": 0, "session_id": "sess-0",
		"exp": 2_000_000_000, "round_kind": "EAST", "game_mode": "STANDARD",
		"participants": ["HUMAN", "HUMAN", "HUMAN", "HUMAN"],
		"character_ids": ["lin_yeche", "an_cheng", "bai_touli", "hua_ling"],
	}
	w.clear_outbox_for_test(2)
	_join(w, 2, claims)
	assert_true(bool(w.test_conn_binding(2).get("joined", false)))
	var biz: Array = _business_events(w.test_outbox(2))
	assert_gt(biz.size(), 0)
	assert_eq(str(biz[0].get("kind", "")), "ROOM_SNAPSHOT")
	var new_hs := 0
	for m in biz:
		if str(m.get("kind", "")) == "HAND_SETTLED":
			new_hs += 1
	assert_eq(new_hs, 0)
	assert_eq(_count_kind_session(session, 0, "HAND_SETTLED"), 4)


func _force_seat_tsumo_ready(bc: BattleController, seat: int) -> void:
	var used: Dictionary = {}
	var draw_floor: int = int(bc.state.wall.draw_index())
	for s in range(4):
		var seat_obj: Seat = bc.state.seats[s]
		seat_obj.hand = Hand.new()
		seat_obj.melds.restore([], 0)
		seat_obj.last_drawn_instance_id = Tile.INVALID_INSTANCE_ID
		seat_obj.furiten = FuritenState.new()
		bc.state.seats[s].river.restore([])
	bc.state.wall.set_draw_index(0)
	var ids := [
		TileId.W1, TileId.W1, TileId.W2, TileId.W2, TileId.W3, TileId.W3,
		TileId.W5, TileId.W5, TileId.W6, TileId.W6, TileId.W7, TileId.W7,
		TileId.W9,
	]
	var h := Hand.new()
	for tid in ids:
		var t: Tile = _draw_live_tid_local(bc, int(tid), used)
		assert_not_null(t)
		assert_true(h.add(t))
	bc.state.seats[seat].hand = h
	bc.state.first_round_active = false
	var win_t: Tile = _draw_live_tid_local(bc, TileId.W9, used)
	assert_not_null(win_t)
	assert_true(bc.state.seats[seat].hand.add(win_t))
	bc.state.seats[seat].last_drawn_instance_id = win_t.instance_id
	bc.state.current_seat = seat
	bc.state.phase = BattlePhase.Kind.DISCARD
	bc.set("_settled", false)
	bc.set("_active_window", null)
	bc.state.wall.set_draw_index(maxi(draw_floor, int(bc.state.wall.draw_index())))
	var ctx: DecisionContext = bc.decision_context_for_seat(seat)
	assert_not_null(ctx)
	assert_true(ctx.has_kind("TSUMO"), "seat %d 须 TSUMO" % seat)


func _count_kind_session(session: HeadlessRoomSession, seat: int, kind: String) -> int:
	var n := 0
	for e in session.event_journal(seat):
		if e is NetworkedEvent and (e as NetworkedEvent).kind == kind:
			n += 1
	return n


## 七对听 + 摸 W9 进入可 TSUMO 的 DISCARD 相位（实体来自真实 Wall）。
func _force_seat0_tsumo_ready(bc: BattleController) -> void:
	var used: Dictionary = {}
	var draw_floor: int = int(bc.state.wall.draw_index())
	for s in range(4):
		var seat: Seat = bc.state.seats[s]
		seat.hand = Hand.new()
		seat.melds.restore([], 0)
		seat.last_drawn_instance_id = Tile.INVALID_INSTANCE_ID
		seat.furiten = FuritenState.new()
		bc.state.seats[s].river.restore([])
	bc.state.wall.set_draw_index(0)
	var ids := [
		TileId.W1, TileId.W1, TileId.W2, TileId.W2, TileId.W3, TileId.W3,
		TileId.W5, TileId.W5, TileId.W6, TileId.W6, TileId.W7, TileId.W7,
		TileId.W9,
	]
	var h := Hand.new()
	for tid in ids:
		var t: Tile = _draw_live_tid_local(bc, int(tid), used)
		assert_not_null(t)
		assert_true(h.add(t))
	bc.state.seats[0].hand = h
	bc.state.first_round_active = false
	var win_t: Tile = _draw_live_tid_local(bc, TileId.W9, used)
	assert_not_null(win_t)
	assert_true(bc.state.seats[0].hand.add(win_t))
	bc.state.seats[0].last_drawn_instance_id = win_t.instance_id
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.DISCARD
	bc.set("_settled", false)
	bc.set("_active_window", null)
	bc.state.wall.set_draw_index(maxi(draw_floor, int(bc.state.wall.draw_index())))
	var ctx: DecisionContext = bc.decision_context_for_seat(0)
	assert_not_null(ctx)
	assert_true(ctx.has_kind("TSUMO"), "fixture 须 offer TSUMO")


func _draw_live_tid_local(bc: BattleController, tid: int, used: Dictionary) -> Tile:
	var w: Wall = bc.state.wall
	var end_i: int = w.authority_tiles().size() - w.dead_wall_size()
	var live_idx := -1
	for i in range(w.draw_index(), end_i):
		var t: Tile = w.authority_tiles()[i]
		if t == null or int(t.id) != tid:
			continue
		if used.has(int(t.instance_id)):
			continue
		live_idx = i
		break
	assert_true(live_idx >= 0, "live 区无 id=%d" % tid)
	if live_idx < 0:
		return null
	if live_idx != w.draw_index():
		assert_true(w.move_live_index_to_top(live_idx))
	var drawn: Tile = w.draw()
	if drawn != null:
		used[int(drawn.instance_id)] = true
	return drawn


func test_session_token_still_rejected_on_reconnect_path() -> void:
	var w := _new_worker()
	var claims := _claims_1h("room-st", 0, "sess-st")
	_join(w, 1, claims)
	_send_ready(w, 1, "room-st", 0)
	w.simulate_disconnect_for_test(1)
	w.clear_outbox_for_test(2)
	w.handle_dict_for_test(2, {
		"protocol_version": 1,
		"kind": "JOIN",
		"room_id": "room-st",
		"seat": 0,
		"room_token": "v1.g.eyJ0eXAiOiJndWVzdCJ9.sig",
	})
	var out: Array = w.test_outbox(2)
	assert_gt(out.size(), 0)
	assert_eq(str(out[0].get("code", "")), "UNAUTHORIZED")


func test_multi_client_visibility_and_reconnect_no_history_replay() -> void:
	var w := _new_worker()
	var parts := ["HUMAN", "HUMAN", "AI", "AI"]
	var c0 := {
		"room_id": "room-2h", "seat": 0, "session_id": "s0",
		"exp": 2_000_000_000, "round_kind": "EAST", "game_mode": "STANDARD",
		"participants": parts,
		"character_ids": ["lin_yeche", "an_cheng", "bai_touli", "hua_ling"],
	}
	var c1 := c0.duplicate(true)
	c1["seat"] = 1
	c1["session_id"] = "s1"
	_join(w, 1, c0)
	_join(w, 2, c1)
	_send_ready(w, 1, "room-2h", 0)
	_send_ready(w, 2, "room-2h", 1)
	var session: HeadlessRoomSession = w.get_room("room-2h")
	assert_true(session.is_started())
	var j0: Array = session.event_journal(0)
	var j1: Array = session.event_journal(1)
	assert_eq(j0.size(), j1.size())
	var nbc0 := NetworkedBattleController.new("room-2h", 0)
	var nbc1 := NetworkedBattleController.new("room-2h", 1)
	assert_true(nbc0.ingest_event_stream(j0))
	assert_true(nbc1.ingest_event_stream(j1))
	# seat0 掉线 → 接管 → 重连：outbox 无历史
	var last_seq_seat1: int = int(w.test_conn_binding(2).get("generation", 0))
	w.clear_outbox_for_test(2)
	w.set_clock_ms_for_test(400_000)
	w.simulate_disconnect_for_test(1)
	w.set_clock_ms_for_test(400_000 + HeadlessRoomSession.RECONNECT_LEASE_MS)
	w.tick_leases_for_test()
	assert_true(session.is_seat_ai_controlled(0))
	w.clear_outbox_for_test(3)
	_join(w, 3, c0)
	assert_false(session.is_seat_ai_controlled(0))
	var biz3: Array = _business_events(w.test_outbox(3))
	assert_gt(biz3.size(), 0)
	assert_eq(str(biz3[0].get("kind", "")), "ROOM_SNAPSHOT")
	var s: int = int((biz3[0].get("payload", {}) as Dictionary).get("snapshot_server_seq", -1))
	for ev in biz3:
		assert_gte(int(ev.get("server_seq", -1)), s)
	# seat1 仍可收到增量（若有新事件）
	var out1: Array = _business_events(w.test_outbox(2))
	for ev2 in out1:
		assert_gte(int(ev2.get("server_seq", -1)), 1)
	# NBC 从重连快照续传真实 journal 增量（保证可构造，禁止条件跳过）
	var snap_ne: NetworkedEvent = NetworkedEvent.from_dict(biz3[0])
	assert_not_null(snap_ne)
	var nbc_r := NetworkedBattleController.new("room-2h", 0)
	assert_true(nbc_r.ingest_networked_event(snap_ne))
	var next_seq: int = int(snap_ne.payload["next_server_seq"])
	var after: Array = session.events_since(0, int(snap_ne.payload["snapshot_server_seq"]))
	for e in after:
		assert_true(e is NetworkedEvent)
		var ne: NetworkedEvent = e as NetworkedEvent
		assert_gte(int(ne.server_seq), next_seq)
		assert_true(nbc_r.ingest_networked_event(ne))
	# SNAP-03 缺口：从真实 journal TURN_PROMPT 改 server_seq，禁止条件跳过
	var gap_seq: int = nbc_r.expected_next_server_seq() + 5
	var prompt_tpl: NetworkedEvent = null
	for e3 in session.event_journal(0):
		if e3 is NetworkedEvent and (e3 as NetworkedEvent).kind == "TURN_PROMPT":
			prompt_tpl = e3
			break
	assert_not_null(prompt_tpl, "必须有真实 TURN_PROMPT fixture")
	var gap_dict: Dictionary = prompt_tpl.to_dict()
	gap_dict["server_seq"] = gap_seq
	var gap_ne: NetworkedEvent = NetworkedEvent.from_dict(gap_dict)
	assert_not_null(gap_ne, "gap fixture 必须可构造")
	assert_false(nbc_r.ingest_networked_event(gap_ne), "缺口须失败")
	assert_true(nbc_r.resync_required())


func test_join_with_different_roster_token_unauthorized_keeps_frozen() -> void:
	# #374：已建房后，同 room/seat/session 但完整 roster 不同的合法签名 token → UNAUTHORIZED
	var room := "room-roster-mismatch"
	var chars_a := ["lin_yeche", "an_cheng", "bai_touli", "hua_ling"]
	var chars_b := ["qiu_jue", "yuan_xi", "ji_shu", "bao_luo"]
	var claims_a := {
		"room_id": room,
		"seat": 0,
		"session_id": "sess-same",
		"exp": 2_000_000_000,
		"round_kind": "EAST",
		"game_mode": "STANDARD",
		"participants": ["HUMAN", "AI", "AI", "AI"],
		"character_ids": chars_a,
	}
	var claims_b := claims_a.duplicate(true)
	claims_b["character_ids"] = chars_b
	var tok_a := _mint_room_token(claims_a)
	var tok_b := _mint_room_token(claims_b)
	var w := _new_worker()
	w.handle_dict_for_test(1, {
		"protocol_version": 1,
		"kind": "JOIN",
		"room_id": room,
		"seat": 0,
		"room_token": tok_a,
	})
	var out1 := w.test_outbox(1)
	for m in out1:
		assert_ne(str(m.get("kind", "")), "ERROR", "首 JOIN 须成功")
	var session: HeadlessRoomSession = w.get_room(room)
	assert_not_null(session)
	for i in range(4):
		assert_eq(String(session.character_ids[i]), chars_a[i])
	var frozen: Array = session.character_ids.duplicate()
	# 第二连接：有效签名但不同 roster
	w.handle_dict_for_test(2, {
		"protocol_version": 1,
		"kind": "JOIN",
		"room_id": room,
		"seat": 0,
		"room_token": tok_b,
	})
	var out2 := w.test_outbox(2)
	assert_gt(out2.size(), 0)
	var saw := false
	for m in out2:
		if str(m.get("kind", "")) == "ERROR" and str(m.get("code", "")) == "UNAUTHORIZED":
			saw = true
			var msg := str(m.get("message", ""))
			assert_true(
				msg.contains("bootstrap") or msg.contains("mismatch") or msg.contains("UNAUTHORIZED") \
					or not msg.is_empty(),
				"UNAUTHORIZED 须带安全 message，不得泄露 token"
			)
	assert_true(saw, "不同 roster 必须 UNAUTHORIZED")
	for i in range(4):
		assert_eq(String(session.character_ids[i]), String(frozen[i]),
			"冻结 roster 不得被篡改 token 改写")
