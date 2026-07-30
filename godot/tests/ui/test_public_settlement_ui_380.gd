extends GutTest

# #380 Red round-2：公共结算 UI + Coordinator 导航。
# 入口：session.ingest_authority_wire_for_test → 投影 → PlayableTable 弹层；
# 导航：request_rematch / request_return_lobby（公开 API）+ 真实 HTTP queue fixture。
# Fixture：NetworkedEvent.make 生产 validator；QueueHttpFixture 隔离 CP。
# 公网四客户端端到端未验证。

const PlayableScr := preload("res://ui/four_player_table/playable_table.gd")
const LOBBY_SCENE := preload("res://ui/lobby/lobby_shell.tscn")

const ROOM := "room-380-ui-r2"
const CHARS := ["lin_yeche", "an_cheng", "bai_touli", "hua_ling"]
const PARTS := ["HUMAN", "HUMAN", "AI", "AI"]
const NAMES := ["北风客", "东家", "南家AI", "西家AI"]

const FIXTURE_HAND := "NetworkedEvent.make/HAND_SETTLED 生产 validator"
const FIXTURE_MATCH := "NetworkedEvent.make/MATCH_SETTLED 生产 validator（canonical seat_order）"
const FIXTURE_SNAP := "NetworkedEvent.make/ROOM_SNAPSHOT + ProtocolViewCodec"
const FIXTURE_JOIN := "NetworkedEvent.make/PLAYER_JOINED 生产 validator"


## 最小真实 HTTP fixture：可观察 guest + ticket 次数（来源对齐 test_casual_queue_client）
class QueueHttpFixture380 extends Node:
	var server := TCPServer.new()
	var port := 0
	var requests: Array[String] = []
	var guest_posts := 0
	var ticket_posts := 0
	var last_ticket_body: String = ""
	var _peers: Array[StreamPeerTCP] = []
	var _guest_n := 0

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
			guest_posts += 1
			_guest_n += 1
			body = {
				"guest_id": "guest-380-%d" % _guest_n,
				"display_name": "游客-380",
				"session_token": "secret-session-token-%d" % _guest_n,
				"expires_at": "2026-07-27T00:00:00Z",
			}
		elif first_line.begins_with("POST /v1/queues/casual "):
			ticket_posts += 1
			var body_start := raw.find("\r\n\r\n")
			last_ticket_body = raw.substr(body_start + 4) if body_start >= 0 else raw
			body = {
				"ticket_id": "ticket-380-%d" % ticket_posts,
				"round_kind": "EAST",
				"game_mode": "STANDARD",
				"status": "waiting",
				"queued_at": "2026-07-26T00:00:00Z",
				"deadline_at": "2026-07-26T00:00:30Z",
			}
		elif first_line.contains("GET /v1/queues/casual/"):
			body = {
				"ticket_id": "ticket-380-poll",
				"round_kind": "EAST",
				"game_mode": "STANDARD",
				"status": "waiting",
				"queued_at": "2026-07-26T00:00:00Z",
				"deadline_at": "2026-07-26T00:00:30Z",
			}
		elif first_line.contains("DELETE /v1/queues/casual/"):
			body = {
				"ticket_id": "ticket-380-x",
				"round_kind": "EAST",
				"game_mode": "STANDARD",
				"status": "cancelled",
				"queued_at": "2026-07-26T00:00:00Z",
				"deadline_at": "2026-07-26T00:00:30Z",
			}
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


func _iid(tile_id: int, copy: int, hand_seq: int = 0) -> int:
	return hand_seq * 136 + TileId.ALL.find(tile_id) * 4 + copy


func _tile(tile_id: int, copy: int, red := false, hand_seq: int = 0) -> Dictionary:
	return {
		"instance_id": _iid(tile_id, copy, hand_seq),
		"tile_id": tile_id, "is_red_dora": red, "owner_seat": copy,
	}


func _seat(s: int, score: int, hand_seq: int, recip: int) -> Dictionary:
	var concealed: Array = []
	var count := 13
	if s == recip:
		concealed = [_tile(TileId.W5, 0, true, hand_seq), _tile(TileId.W5, 1, false, hand_seq)]
		count = 2
	return {
		"seat": s,
		"seat_wind": [TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N][s],
		"score": score, "concealed_tiles": concealed, "concealed_count": count,
		"last_drawn_tile_instance_id": -1, "river": [], "melds": [],
		"riichi_declared": false, "riichi_double": false, "riichi_discard_index": -1,
	}


func _core(
	recip: int, scores: Array, hand_seq := 0, dealer := 0, honba := 0, sticks := 0,
	hand_number := 1, round_wind: int = TileId.E
) -> Dictionary:
	var seats: Array = []
	for s in range(4):
		seats.append(_seat(s, int(scores[s]), hand_seq, recip))
	return {
		"recipient_seat": recip, "hand_seq": hand_seq, "dealer_seat": dealer,
		"current_seat": recip, "phase": "DRAW", "round_wind": round_wind,
		"hand_number": hand_number, "honba": honba, "riichi_sticks": sticks,
		"live_wall_count": 70,
		"dora_indicators": [_tile(TileId.S1, 0, false, hand_seq)],
		"seats": seats,
	}


func _snap_payload(seq: int, recip: int, core: Dictionary) -> Dictionary:
	return {
		"snapshot_server_seq": seq, "next_server_seq": seq + 1, "seat_view": recip,
		"modules": [
			{"module_key": "core_table", "schema_version": 1, "payload": core.duplicate(true)},
			MatchingMetaSnapshotProvider.fixture_module(CHARS, PARTS),
		],
	}


func _rs(seq: int, payload: Dictionary, room: String) -> NetworkedEvent:
	var ne := NetworkedEvent.make(
		"ROOM_SNAPSHOT", seq, room, payload, ProtocolViewCodec.compute_view_hash(payload)
	)
	assert_not_null(ne, FIXTURE_SNAP)
	return ne


func _hs(seq: int, vh: String, scores: Array, room: String) -> NetworkedEvent:
	var ne := NetworkedEvent.make("HAND_SETTLED", seq, room, {
		"hand_seq": 0, "outcome": "RON", "winner_seats": [2], "loser_seat": 1,
		"score_deltas": [-1000, -2000, 8000, -5000], "scores": scores.duplicate(),
		"dealer_seat": 0, "renchan": false, "honba": 1, "riichi_sticks": 0,
		"adjustments": [],
	}, vh)
	assert_not_null(ne, FIXTURE_HAND)
	return ne


func _ms(seq: int, vh: String, finals: Array, order: Array, room: String) -> NetworkedEvent:
	var ne := NetworkedEvent.make("MATCH_SETTLED", seq, room, {
		"round_kind": "EAST",
		"final_scores": finals.duplicate(),
		"seat_order": order.duplicate(),
	}, vh)
	assert_not_null(ne, FIXTURE_MATCH)
	return ne


func _pj(seq: int, vh: String, seat: int, name: String, room: String) -> NetworkedEvent:
	var ne := NetworkedEvent.make("PLAYER_JOINED", seq, room, {
		"seat": seat,
		"participant_kind": "HUMAN" if seat < 2 else "AI",
		"display_name": name,
		"connected": true,
	}, vh)
	assert_not_null(ne, FIXTURE_JOIN)
	return ne


func _pair_table() -> Node:
	var table = PlayableScr.new()
	add_child_autofree(table)
	await get_tree().process_frame
	if table._table == null:
		var fpt = load("res://ui/four_player_table/four_player_table.gd").new()
		table.add_child(fpt)
		table._table = fpt
		await get_tree().process_frame
	return table


func _bind_public(table: Node, room: String, seat: int) -> PublicCasualNetworkSession:
	var nbc := NetworkedBattleController.new(room, seat)
	var sess := PublicCasualNetworkSession.new()
	add_child_autofree(sess)
	sess.room_id = room
	sess.seat = seat
	sess.session_id = "guest-ui-%d" % seat
	sess.worker_url = "ws://127.0.0.1:9"
	sess.room_token = "tok-ui-380"
	sess.game_mode = "STANDARD"
	sess.nbc = nbc
	sess.seq_bridge.bind_networked_controller(nbc)
	sess.bind_playable_table(table)
	return sess


func _feed(sess: PublicCasualNetworkSession, ne: NetworkedEvent) -> void:
	sess.ingest_authority_wire_for_test(JSON.stringify(ne.to_dict()))


func _sync(table: Node) -> void:
	if table.has_method("sync_public_table_projection"):
		table.sync_public_table_projection()
	await get_tree().process_frame
	await get_tree().process_frame


func _bootstrap(sess: PublicCasualNetworkSession, recip: int) -> String:
	var room := str(sess.room_id)
	var snap := _rs(1, _snap_payload(1, recip, _core(recip, [25000, 25000, 25000, 25000])), room)
	_feed(sess, snap)
	return snap.view_hash


func _roster(sess: PublicCasualNetworkSession, start: int, vh: String) -> int:
	var room := str(sess.room_id)
	var seq := start
	for s in range(4):
		_feed(sess, _pj(seq, vh, s, NAMES[s], room))
		seq += 1
	return seq


func _find_named(root: Node, names: Array) -> Node:
	for n in names:
		var found := root.find_child(str(n), true, false)
		if found != null:
			return found
	return null


func _collect_text(root: Node) -> String:
	var parts: PackedStringArray = []
	_walk_text(root, parts)
	return " ".join(parts)


func _walk_text(n: Node, parts: PackedStringArray) -> void:
	if n is Label:
		parts.append((n as Label).text)
	elif n is Button:
		parts.append((n as Button).text)
	for c in n.get_children():
		_walk_text(c, parts)


func _match_settlement_panel_visible(coordinator: PublicMatchCoordinator, table: Node) -> bool:
	if str(coordinator.get_view().get("state", "")) != "match_settled":
		return false
	if table == null:
		return false
	var p := table.find_child("PublicMatchSettlementPanel", true, false)
	if p == null:
		p = table.find_child("MatchSettlementPanel", true, false)
	return p != null and bool(p.visible)


func _wait_until(done: Callable, max_frames := 120) -> bool:
	for _i in range(max_frames):
		if done.call():
			return true
		await wait_process_frames(1)
	return false


# ── 单局弹层：自动关 + 局况刷新 ─────────────────────────────

func test_public_hand_overlay_auto_close_and_refresh_table_fields() -> void:
	var room := ROOM + "-hand"
	var recip := 1
	var table := await _pair_table()
	var sess := _bind_public(table, room, recip)
	var vh := _bootstrap(sess, recip)
	var scores := [24000, 23000, 33000, 20000]
	_feed(sess, _hs(2, vh, scores, room))
	await _sync(table)

	assert_true(sess.has_method("get_settlement_view"),
		"#380 session 结算投影 API 须存在（UI 消费）")
	var phase := ""
	if sess.has_method("get_settlement_view"):
		phase = str(sess.get_settlement_view().get("phase", ""))
	assert_eq(phase, "hand_result")

	var overlay := _find_named(table, [
		"PublicHandSettlementOverlay", "HandSettlementOverlay",
		"PublicHandResultPanel", "HandSettlementPanel",
	])
	assert_not_null(overlay, "方案 A：单局中央弹层须挂到 PlayableTable")
	assert_true(overlay == null or overlay.is_visible_in_tree(), "单局弹层可见")
	if overlay != null:
		assert_null(overlay.find_child("ContinueButton", true, false), "无继续按钮")
		assert_null(overlay.find_child("ReadyButton", true, false), "无 READY 按钮")
		var blob := _collect_text(overlay)
		assert_true(
			blob.contains("RON") or blob.contains("荣") or blob.contains("8000")
			or blob.contains("33000"),
			"须展示权威 outcome/delta/scores blob=%s" % blob.substr(0, 120)
		)
	assert_false(sess.is_command_pending(), "HAND 无命令副作用")

	# 下一局 SNAP：起分一致 + 刷新庄/场/本场/立直棒
	var next_core := _core(recip, scores, 1, 1, 2, 3, 2, TileId.S_WIND)
	_feed(sess, _rs(3, _snap_payload(3, recip, next_core), room))
	await _sync(table)

	var phase2 := ""
	if sess.has_method("get_settlement_view"):
		phase2 = str(sess.get_settlement_view().get("phase", ""))
	assert_eq(phase2, "idle", "起分一致后 phase 必须 idle")
	var still := _find_named(table, [
		"PublicHandSettlementOverlay", "HandSettlementOverlay",
		"PublicHandResultPanel", "HandSettlementPanel",
	])
	assert_true(
		still == null or not still.is_visible_in_tree(),
		"单局弹层须关闭"
	)

	var fpt = table._table
	assert_not_null(fpt, "须有 FourPlayerTable")
	assert_not_null(fpt.center_info, "须有 center_info")
	assert_eq(int(fpt.center_info.get("_honba")), 2, "honba 须刷新为 2")
	assert_eq(int(fpt.center_info.get("_riichi_sticks")), 3, "riichi_sticks 须刷新为 3")
	# dealer_seat=1 → 相对本席(recip=1) 的相对槽 0 为庄（set_is_dealer → _dealer_override=1）
	assert_true(fpt.seat_panels.size() >= 4, "须有四席面板")
	var dealer_rel := (1 - recip + 4) % 4
	var sp = fpt.seat_panels[dealer_rel]
	assert_not_null(sp, "庄家相对槽须存在")
	assert_eq(int(sp.get("_dealer_override")), 1,
		"dealer_seat=1 须映射到相对槽庄标记 _dealer_override=1")


# ── 终场弹层按钮幂等 ───────────────────────────────────────

func test_public_match_overlay_buttons_and_local_highlight() -> void:
	var room := ROOM + "-match"
	var recip := 2
	var table := await _pair_table()
	var sess := _bind_public(table, room, recip)
	var vh := _bootstrap(sess, recip)
	var seq := _roster(sess, 2, vh)
	# 合法 canonical 序
	var finals := [33000, 23000, 24000, 20000]
	var order := [0, 2, 1, 3]
	assert_eq(order, MatchSettlement.build_seat_order(finals))
	_feed(sess, _hs(seq, vh, finals, room))
	seq += 1
	_feed(sess, _ms(seq, vh, finals, order, room))
	await _sync(table)

	assert_true(sess.has_method("get_settlement_view"),
		"#380 session 结算投影 API 须存在（终场 UI）")
	var phase := ""
	if sess.has_method("get_settlement_view"):
		phase = str(sess.get_settlement_view().get("phase", ""))
	assert_eq(phase, "match_result")

	var panel := _find_named(table, [
		"PublicMatchSettlementPanel", "MatchSettlementPanel",
		"PublicMatchSettlementOverlay", "MatchSettlementOverlay",
	])
	assert_not_null(panel, "终场中央弹层须存在")
	assert_true(panel == null or panel.is_visible_in_tree())
	var rematch := panel.find_child("RematchButton", true, false) as Button if panel else null
	var ret := panel.find_child("ReturnLobbyButton", true, false) as Button if panel else null
	assert_not_null(rematch, "须有再次匹配按钮")
	assert_not_null(ret, "须有返回大厅按钮")
	assert_true(rematch != null and (
		rematch.text.contains("再次匹配") or rematch.text.contains("再来一局")
	), "Rematch 文案")
	assert_true(ret != null and ret.text.contains("返回大厅"), "Return 文案")

	var blob := _collect_text(panel) if panel else ""
	assert_true(blob.contains(NAMES[0]), "须显示 PLAYER_JOINED 名")
	assert_true(blob.contains(NAMES[2]), "须显示本席名")

	var rematch_count := [0]
	var return_count := [0]
	if panel != null and panel.has_signal("rematch_requested"):
		panel.rematch_requested.connect(func(): rematch_count[0] += 1)
	if panel != null and panel.has_signal("return_lobby_requested"):
		panel.return_lobby_requested.connect(func(): return_count[0] += 1)
	if rematch != null:
		rematch.pressed.emit()
		rematch.pressed.emit()
	if ret != null:
		ret.pressed.emit()
	assert_true(
		rematch != null and rematch.disabled and ret != null and ret.disabled,
		"首次点击后两按钮同时禁用"
	)
	if panel != null and panel.has_signal("rematch_requested"):
		assert_eq(rematch_count[0], 1, "rematch 只发一次")
		assert_eq(return_count[0], 0, "已点 rematch 后 return 不得再发")


# ── Coordinator 再次匹配：真实 HTTP queue + 公开入口 ────────

func test_coordinator_rematch_creates_new_guest_ticket_once() -> void:
	var fixture := QueueHttpFixture380.new()
	add_child_autofree(fixture)
	fixture.start()

	var had_url := OS.has_environment("CONTROL_PLANE_URL")
	var old_url := OS.get_environment("CONTROL_PLANE_URL")
	OS.set_environment("CONTROL_PLANE_URL", fixture.base_url())

	var host := Control.new()
	add_child_autofree(host)
	var coordinator := PublicMatchCoordinator.new()
	host.add_child(coordinator)
	await wait_process_frames(1)

	assert_true(coordinator.has_method("request_rematch"))
	assert_true(coordinator.has_method("begin_network_from_assigned_for_test"),
		"#380 须有 begin_network_from_assigned_for_test 公开测试 seam")
	assert_true(coordinator.has_method("set_last_public_intent_for_test"))
	coordinator.set_last_public_intent_for_test(
		SessionIntent.new(&"PUBLIC_CASUAL", &"EAST", &"STANDARD", &"lin_yeche")
	)

	# 真实 runtime：公开 seam 启动 session+table（WS 可失败，但对象须存在）
	var assigned := {
		"status": "assigned",
		"round_kind": "EAST",
		"game_mode": "STANDARD",
		"worker": "ws://127.0.0.1:9",
		"room_id": "room-old-380",
		"seat": 1,
		"room_token": "old-room-token-secret",
		"session_id": "guest-old-380",
	}
	coordinator.begin_network_from_assigned_for_test(assigned)
	await wait_process_frames(2)

	var old_session := coordinator.get_active_session()
	var old_table := coordinator.get_active_table()
	assert_not_null(old_session, "须建立真实 session runtime")
	assert_not_null(old_table, "须建立真实 table runtime")
	var old_session_id := old_session.get_instance_id()
	var old_table_id := old_table.get_instance_id()
	var old_token := str(old_session.room_token)
	assert_false(old_token.is_empty(), "旧 session 须有 token 可证清空")

	# 终场态：公开 view 走 settlement 信号路径 — 直接注入 MATCH 投影
	# 用 consume matched + settlement phase via session wire
	var room := str(old_session.room_id)
	var recip := int(old_session.seat)
	if old_session.nbc == null:
		old_session.nbc = NetworkedBattleController.new(room, recip)
		old_session.seq_bridge.bind_networked_controller(old_session.nbc)
	# bootstrap + hand + match via wire
	var scores := [25000, 25000, 25000, 25000]
	var core := _core(recip, scores)
	var snap_p := _snap_payload(1, recip, core)
	var snap := _rs(1, snap_p, room)
	_feed(old_session, snap)
	var vh := snap.view_hash
	var seq := 2
	for s in range(4):
		_feed(old_session, _pj(seq, vh, s, NAMES[s], room))
		seq += 1
	var finals := [33000, 23000, 24000, 20000]
	var order := [0, 2, 1, 3]
	_feed(old_session, _hs(seq, vh, finals, room))
	seq += 1
	_feed(old_session, _ms(seq, vh, finals, order, room))
	await wait_process_frames(1)
	assert_eq(str(old_session.get_settlement_view().get("phase", "")), "match_result")
	# coordinator 应收 settlement → match_settled
	assert_eq(str(coordinator.get_view().get("state", "")), "match_settled",
		"MATCH 后 coordinator view 须 match_settled")

	var ok1 := bool(coordinator.request_rematch())
	coordinator.request_rematch()  # 连点

	assert_true(
		await _wait_until(func(): return fixture.guest_posts >= 1 and fixture.ticket_posts >= 1),
		"再次匹配须创建新 guest+ticket g=%d t=%d" % [fixture.guest_posts, fixture.ticket_posts]
	)
	assert_eq(fixture.guest_posts, 1, "连点 guest 恰好一次")
	assert_eq(fixture.ticket_posts, 1, "连点 ticket 恰好一次")
	assert_true(
		fixture.last_ticket_body.contains("EAST")
		and fixture.last_ticket_body.contains("STANDARD")
		and fixture.last_ticket_body.contains("lin_yeche"),
		"须保留原 round/game/character body=%s" % fixture.last_ticket_body.substr(0, 200)
	)
	assert_true(ok1, "request_rematch 须成功")

	# 旧 runtime 强制断言：release 后要么仍可读取且字段清空，要么已 queue_free
	var session_released := not is_instance_valid(old_session)
	if is_instance_valid(old_session):
		session_released = bool(old_session._released) \
			and str(old_session.room_token).is_empty() \
			and str(old_session.session_id).is_empty() \
			and old_session.get_parent() == null
	assert_true(session_released, "旧 session 须 released 且凭证清空（或已 free）")
	var table_released := not is_instance_valid(old_table)
	if is_instance_valid(old_table):
		table_released = old_table.get_parent() == null
	assert_true(table_released, "旧 table 须移出树（或已 free）")
	assert_true(
		coordinator.get_active_session() == null
		or coordinator.get_active_session().get_instance_id() != old_session_id,
		"active session 不得仍指向旧实例"
	)
	var new_sess := coordinator.get_active_session()
	# rematch 仅入队，未必立刻有新 session
	if new_sess != null:
		assert_ne(new_sess.get_instance_id(), old_session_id)
	assert_true(old_table_id != 0)

	# 缺 intent 不得默认角色（须先真实 MATCH 终场，否则只是 pre-MATCH 拒绝）
	var coord2 := PublicMatchCoordinator.new()
	host.add_child(coord2)
	await wait_process_frames(1)
	coord2.begin_network_from_assigned_for_test({
		"status": "assigned", "round_kind": "EAST", "game_mode": "STANDARD",
		"worker": "ws://127.0.0.1:9", "room_id": "room-no-intent-380", "seat": 0,
		"room_token": "tok-no-intent", "session_id": "guest-no-intent",
	})
	await wait_process_frames(2)
	var sess2 := coord2.get_active_session()
	assert_not_null(sess2)
	if sess2.nbc == null:
		sess2.nbc = NetworkedBattleController.new(sess2.room_id, sess2.seat)
		sess2.seq_bridge.bind_networked_controller(sess2.nbc)
	var room2 := str(sess2.room_id)
	var snap2 := _rs(1, _snap_payload(1, 0, _core(0, [25000, 25000, 25000, 25000])), room2)
	_feed(sess2, snap2)
	var vh2 := snap2.view_hash
	var s2 := 2
	for seat_i in range(4):
		_feed(sess2, _pj(s2, vh2, seat_i, NAMES[seat_i], room2))
		s2 += 1
	_feed(sess2, _hs(s2, vh2, [33000, 23000, 24000, 20000], room2))
	s2 += 1
	_feed(sess2, _ms(s2, vh2, [33000, 23000, 24000, 20000], [0, 2, 1, 3], room2))
	await wait_process_frames(1)
	assert_eq(str(coord2.get_view().get("state", "")), "match_settled")
	# 不设置 last intent（或空角色）
	coord2.set_last_public_intent_for_test(
		SessionIntent.new(&"PUBLIC_CASUAL", &"EAST", &"STANDARD", &"")
	)
	var ok_bad := coord2.request_rematch()
	assert_false(ok_bad, "缺 intent 不得 rematch")
	assert_eq(str(coord2.get_view().get("error_code", "")), "NO_INTENT")

	if had_url:
		OS.set_environment("CONTROL_PLANE_URL", old_url)
	else:
		OS.unset_environment("CONTROL_PLANE_URL")
	fixture.stop()


func test_coordinator_return_lobby_releases_once() -> void:
	var lobby := LOBBY_SCENE.instantiate() as LobbyShell
	add_child_autofree(lobby)
	await wait_process_frames(1)
	var coordinator := lobby.get_node("PublicMatchCoordinator") as PublicMatchCoordinator
	assert_not_null(coordinator)
	assert_true(coordinator.has_method("request_return_lobby"))
	assert_true(coordinator.has_method("begin_network_from_assigned_for_test"))

	coordinator.set_last_public_intent_for_test(
		SessionIntent.new(&"PUBLIC_CASUAL", &"EAST", &"STANDARD", &"lin_yeche")
	)
	coordinator.begin_network_from_assigned_for_test({
		"status": "assigned", "round_kind": "EAST", "game_mode": "STANDARD",
		"worker": "ws://127.0.0.1:9", "room_id": "room-ret-380", "seat": 0,
		"room_token": "return-token-secret",
		"session_id": "guest-ret-380",
	})
	await wait_process_frames(2)
	var old_session := coordinator.get_active_session()
	var old_table := coordinator.get_active_table()
	assert_not_null(old_session, "返回前须有 session")
	assert_not_null(old_table, "返回前须有 table")
	assert_false(str(old_session.room_token).is_empty())

	# #380：须先投影 MATCH 终场；未终场 return 无副作用
	assert_false(coordinator.request_return_lobby(), "未 MATCH 不得 return")
	if old_session.nbc == null:
		old_session.nbc = NetworkedBattleController.new(old_session.room_id, old_session.seat)
		old_session.seq_bridge.bind_networked_controller(old_session.nbc)
	var room := str(old_session.room_id)
	var recip := int(old_session.seat)
	var snap := _rs(1, _snap_payload(1, recip, _core(recip, [25000, 25000, 25000, 25000])), room)
	_feed(old_session, snap)
	var vh := snap.view_hash
	var seq := 2
	for s in range(4):
		_feed(old_session, _pj(seq, vh, s, NAMES[s], room))
		seq += 1
	var finals := [33000, 23000, 24000, 20000]
	_feed(old_session, _hs(seq, vh, finals, room))
	seq += 1
	_feed(old_session, _ms(seq, vh, finals, [0, 2, 1, 3], room))
	await wait_process_frames(1)
	assert_eq(str(coordinator.get_view().get("state", "")), "match_settled",
		"return 前须真实 MATCH 终场")

	var match_btn := lobby.get_node_or_null("%MatchButton") as Control
	assert_not_null(match_btn, "须有 %MatchButton")

	var ok := bool(coordinator.request_return_lobby())
	assert_true(ok, "返回大厅须成功")
	assert_eq(str(coordinator.get_view().get("state", "")), "idle")
	assert_true(old_session._released, "旧 session released")
	assert_eq(old_session.room_token, "", "token 清空")
	assert_null(coordinator.get_active_session())
	assert_null(coordinator.get_active_table())
	if is_instance_valid(old_table):
		assert_null(old_table.get_parent(), "table 移出树")
	await wait_process_frames(3)
	# P1-2：销毁后不得残留 _reward_sync_loop await 错误
	var prod_src := FileAccess.get_file_as_string("res://ui/four_player_table/playable_table.gd")
	assert_false(prod_src.contains("func _reward_sync_loop"),
		"生产须移除 self-owned _reward_sync_loop 协程")
	assert_true(prod_src.contains("set_process(true)") and prod_src.contains("func _process"),
		"奖励同步须走 Node._process")
	var focus_owner = get_viewport().gui_get_focus_owner()
	assert_true(
		focus_owner == match_btn or (focus_owner != null and str(focus_owner.name).contains("Match")),
		"返回大厅须聚焦 MatchButton，实际=%s" % str(focus_owner)
	)
	var am = get_node_or_null("/root/AudioManager")
	if am != null and am.get("_bgm_player") != null:
		var bgm_player = am._bgm_player
		if bgm_player != null and bgm_player.stream != null:
			assert_eq(
				String(bgm_player.stream.resource_path),
				LobbyShell.LOBBY_BGM_PATH,
				"返回大厅应恢复大厅 BGM"
			)

	var st := str(coordinator.get_view().get("state", ""))
	coordinator.request_return_lobby()
	coordinator.request_return_lobby()
	assert_eq(str(coordinator.get_view().get("state", "")), st, "连点不改变状态")


func _reward_window_idle_mod() -> Dictionary:
	var rw := RewardWindowModule.new()
	var dto: Dictionary = rw.to_snapshot_dto()
	return {
		"module_key": str(dto.get("module_key", "reward_window")),
		"schema_version": int(dto.get("schema_version", RewardWindowModule.SCHEMA_VERSION)),
		"payload": (dto.get("payload", {}) as Dictionary).duplicate(true),
	}


func _item_inv_mod(seat: int, items: Array) -> Dictionary:
	return {
		"module_key": "item_inventory",
		"schema_version": ItemInventoryModule.SCHEMA_VERSION,
		"payload": {
			"seat": seat,
			"items": items.duplicate(true),
			"active_window_id": null,
			"pending_window_id": null,
		},
	}


func _bind_public_trash(table: Node, room: String, seat: int) -> PublicCasualNetworkSession:
	var nbc := NetworkedBattleController.new(room, seat)
	nbc.configure_snapshot_registry_for_mode("TRASH_TALK")
	var sess := PublicCasualNetworkSession.new()
	add_child_autofree(sess)
	sess.room_id = room
	sess.seat = seat
	sess.session_id = "guest-ui-tt-%d" % seat
	sess.worker_url = "ws://127.0.0.1:9"
	sess.voice_worker_url = "ws://127.0.0.1:8"
	sess.room_token = "tok-ui-tt"
	sess.game_mode = "TRASH_TALK"
	sess.nbc = nbc
	sess.seq_bridge.bind_networked_controller(nbc)
	sess.bind_playable_table(table)
	return sess


func _grant_inv_items(room: String, seat: int) -> Array:
	var inv := ItemInventoryModule.new()
	inv.set_match_namespace(room)
	assert_true(bool(inv.grant_for_seat({
		"seat": seat, "item_id": "iron_shield_v1", "window_id": "w0",
		"hand_seq": 0, "score": 1, "rule_version": "rv", "assignment_version": "av",
		"matched_rule_ids": [], "affinity_match": false,
	}).get("ok", false)))
	var payload: Dictionary = inv.to_seat_snapshot_dto(seat)["payload"]
	return (payload.get("items", []) as Array).duplicate(true)


func test_standard_match_settled_does_not_revive_inventory_ui() -> void:
	var room := ROOM + "-std"
	var recip := 0
	var table := await _pair_table()
	var sess := _bind_public(table, room, recip)
	var vh := _bootstrap(sess, recip)
	_feed(sess, _hs(2, vh, [24000, 23000, 33000, 20000], room))
	_feed(sess, _ms(3, vh, [33000, 23000, 24000, 20000], [0, 2, 1, 3], room))
	await _sync(table)

	assert_true(sess.has_method("get_settlement_view"),
		"#380 session 结算投影 API 须存在（STANDARD 隔离）")
	var inv_view: Dictionary = sess.nbc.get_item_inventory_view() if sess.nbc != null else {}
	assert_true(inv_view.is_empty() or int(inv_view.get("instance_count", 0)) == 0)

	var drawer := table.find_child("ItemInventoryDrawer", true, false)
	assert_true(
		drawer == null or not bool(drawer.visible),
		"STANDARD 终场后库存抽屉不得可见"
	)
	# 奖励 HUD 节点可存在于树；不得展示奖池/授予内容（STANDARD 无 reward 模块）
	var reward_hud := table.find_child("RewardPoolHud", true, false)
	if reward_hud != null:
		var hud_text := _collect_text(reward_hud).strip_edges()
		assert_false(
			hud_text.contains("ITEM_") or hud_text.contains("授予")
			or hud_text.contains("奖池") or hud_text.contains("GRANTED")
			or hud_text.contains("item_"),
			"STANDARD 终场不得复活奖励展示文案: %s" % hud_text.substr(0, 80)
		)
		assert_false(
			hud_text.contains("×") or hud_text.contains("持有"),
			"STANDARD 终场不得展示库存数量文案"
		)


func test_trash_match_result_hides_inventory_while_nbc_keeps_authority() -> void:
	# 真实 wire → settlement_view_changed + Node._process 刷新；不直调私有 helper。
	# NBC 保留权威非空库存；match_result 展示边界投影空库存。
	var room := ROOM + "-tt-ui-inv"
	var recip := 0
	var table := await _pair_table()
	var sess := _bind_public_trash(table, room, recip)
	var items := _grant_inv_items(room, recip)
	assert_gt(items.size(), 0)
	var fpt: FourPlayerTable = table._table as FourPlayerTable
	assert_not_null(fpt, "PlayableTable 须挂载真实 FourPlayerTable")

	var p0 := {
		"snapshot_server_seq": 1, "next_server_seq": 2, "seat_view": recip,
		"modules": [
			{"module_key": "core_table", "schema_version": 1,
				"payload": _core(recip, [25000, 25000, 25000, 25000])},
			_item_inv_mod(recip, items),
			MatchingMetaSnapshotProvider.fixture_module(CHARS, PARTS),
			_reward_window_idle_mod(),
		],
	}
	var snap0 := _rs(1, p0, room)
	_feed(sess, snap0)
	assert_true(
		await _wait_until(func(): return int(fpt.inventory_count()) > 0),
		"MATCH 前须经生产同步链出现库存展示 inventory_count>0"
	)
	var nbc_inv: Dictionary = sess.nbc.get_item_inventory_view()
	assert_gt((nbc_inv.get("items", []) as Array).size(), 0, "MATCH 前 NBC 须有库存")
	assert_gt(int(fpt.inventory_count()), 0, "MATCH 前展示层应有库存")

	var vh := snap0.view_hash
	var finals := [33000, 23000, 24000, 20000]
	_feed(sess, _hs(2, vh, finals, room))
	_feed(sess, _ms(3, vh, finals, [0, 2, 1, 3], room))
	assert_true(
		await _wait_until(func(): return str(sess.get_settlement_view().get("phase", "")) == "match_result" and int(fpt.inventory_count()) == 0),
		"MATCH 后须经 settlement signal/_process 到 match_result 且展示库存为 0"
	)

	assert_eq(str(sess.get_settlement_view().get("phase", "")), "match_result")
	var nbc_after: Dictionary = sess.nbc.get_item_inventory_view()
	assert_gt((nbc_after.get("items", []) as Array).size(), 0,
		"MATCH 后 NBC 须保留真实权威库存")
	assert_eq(int(fpt.inventory_count()), 0, "match_result 展示库存须为空")
	assert_eq((fpt.inventory_row_ids() as Array).size(), 0, "match_result 展示行须为空")
	assert_false(bool(fpt.is_inventory_drawer_open()), "终场抽屉不得打开")
	var drawer := table.find_child("ItemInventoryDrawer", true, false)
	assert_true(
		drawer == null or not bool(drawer.visible),
		"终场库存抽屉不得可见"
	)


func test_settlement_modal_centered_for_default_viewport() -> void:
	assert_eq(DT.VIEW_W, 1600)
	assert_eq(DT.VIEW_H, 900)
	var panel := MatchSettlementPanel.new()
	add_child_autofree(panel)
	await get_tree().process_frame
	var modal := panel.find_child("SettlementModal", true, false) as Panel
	assert_not_null(modal)
	assert_eq(modal.position.x, (DT.VIEW_W - modal.custom_minimum_size.x) / 2.0)
	assert_eq(modal.position.y, (DT.VIEW_H - modal.custom_minimum_size.y) / 2.0)


func test_production_ui_files_forbid_local_seat_order_builder() -> void:
	for path in [
		"res://ui/four_player_table/playable_table.gd",
		"res://ui/four_player_table/match_settlement_panel.gd",
		"res://ui/lobby/public_match_coordinator.gd",
	]:
		var src := FileAccess.get_file_as_string(path)
		assert_false(src.contains("MatchSettlement.build_seat_order"),
			"生产 UI 禁止本地 build_seat_order: %s" % path)

func test_lobby_match_settled_latches_against_status_overlay() -> void:
	# 真实 LobbyShell + Coordinator + session wire
	var lobby := LOBBY_SCENE.instantiate() as LobbyShell
	add_child_autofree(lobby)
	await wait_process_frames(2)
	var coordinator := lobby.get_node("PublicMatchCoordinator") as PublicMatchCoordinator
	assert_not_null(coordinator)
	var overlay := lobby.get_node_or_null("PublicMatchStatusOverlay") as PublicMatchStatusOverlay
	assert_not_null(overlay)

	coordinator.set_last_public_intent_for_test(
		SessionIntent.new(&"PUBLIC_CASUAL", &"EAST", &"STANDARD", &"lin_yeche")
	)
	coordinator.begin_network_from_assigned_for_test({
		"status": "assigned", "round_kind": "EAST", "game_mode": "STANDARD",
		"worker": "ws://127.0.0.1:9", "room_id": "room-lobby-latch", "seat": 2,
		"room_token": "tok-lobby-latch", "session_id": "guest-lobby-latch",
	})
	await wait_process_frames(2)
	var sess := coordinator.get_active_session()
	var table := coordinator.get_active_table()
	assert_not_null(sess)
	assert_not_null(table)
	if sess.nbc == null:
		sess.nbc = NetworkedBattleController.new(sess.room_id, sess.seat)
		sess.seq_bridge.bind_networked_controller(sess.nbc)

	var room := str(sess.room_id)
	var recip := int(sess.seat)
	var scores := [25000, 25000, 25000, 25000]
	var snap := _rs(1, _snap_payload(1, recip, _core(recip, scores)), room)
	_feed(sess, snap)
	var vh := snap.view_hash
	var seq := 2
	for s in range(4):
		_feed(sess, _pj(seq, vh, s, NAMES[s], room))
		seq += 1
	var finals := [33000, 23000, 24000, 20000]
	var order := [0, 2, 1, 3]
	_feed(sess, _hs(seq, vh, finals, room))
	seq += 1
	_feed(sess, _ms(seq, vh, finals, order, room))
	# 等待真实 settlement_view_changed → 终场面板可见（禁止直调 _sync_public_settlement_ui）
	assert_true(
		await _wait_until(func(): return _match_settlement_panel_visible(coordinator, table)),
		"MATCH 后须经 signal 链创建并显示终场面板"
	)

	assert_eq(str(coordinator.get_view().get("state", "")), "match_settled")
	assert_false(overlay.is_blocking(), "match_settled 遮罩不得阻塞")
	assert_false(overlay.visible, "match_settled 遮罩须隐藏")

	# terminal SNAP（下一局/清场）不得覆盖 match_settled
	_feed(sess, _rs(seq + 1, _snap_payload(seq + 1, recip, _core(recip, finals, 1)), room))
	await wait_process_frames(1)
	assert_eq(str(coordinator.get_view().get("state", "")), "match_settled",
		"terminal SNAP 不得覆盖 match_settled")

	# 经真实 session signal 触发 reconnecting / terminal_error，不得覆盖 match_settled
	assert_true(sess.reconnecting.get_connections().size() > 0,
		"session.reconnecting 须已接到 coordinator")
	sess.reconnecting.emit("WS_CLOSED", "断线")
	await wait_process_frames(1)
	assert_eq(str(coordinator.get_view().get("state", "")), "match_settled",
		"session.reconnecting 不得覆盖 match_settled")
	assert_false(overlay.is_blocking())
	sess.terminal_error.emit("ROOM_FAILED", "失败")
	await wait_process_frames(1)
	assert_eq(str(coordinator.get_view().get("state", "")), "match_settled",
		"session.terminal_error 不得覆盖 match_settled")
	assert_false(overlay.is_blocking())

	var panel := table.find_child("PublicMatchSettlementPanel", true, false)
	if panel == null:
		panel = table.find_child("MatchSettlementPanel", true, false)
	assert_not_null(panel, "终场面板须存在")
	assert_true(panel.visible)
	var rematch := panel.find_child("RematchButton", true, false) as Button
	var ret := panel.find_child("ReturnLobbyButton", true, false) as Button
	assert_not_null(rematch)
	assert_not_null(ret)
	assert_false(rematch.disabled)
	assert_false(ret.disabled)


func test_match_panel_shows_character_identities_and_local_highlight() -> void:
	var panel := MatchSettlementPanel.new()
	add_child_autofree(panel)
	await get_tree().process_frame
	var rows := [
		{"rank": 1, "seat_id": 0, "name": NAMES[0], "character_id": CHARS[0], "score": 33000, "is_local": false},
		{"rank": 2, "seat_id": 2, "name": NAMES[2], "character_id": CHARS[2], "score": 24000, "is_local": true},
		{"rank": 3, "seat_id": 1, "name": NAMES[1], "character_id": CHARS[1], "score": 23000, "is_local": false},
		{"rank": 4, "seat_id": 3, "name": NAMES[3], "character_id": "unknown_char_x", "score": 20000, "is_local": false},
	]
	panel.present({"title": "对局结束", "rows": rows, "rematch_label": "再次匹配"})
	await get_tree().process_frame
	var blob := _collect_text(panel)
	for i in range(3):
		var cid: String = str(CHARS[i])
		var ch: Character = CharacterPool.find(StringName(cid))
		assert_not_null(ch, "角色池须有 %s" % cid)
		var dn: String = str(ch.display_name)
		assert_true(blob.contains(dn), "须显示角色 display_name %s（id=%s）" % [dn, cid])
	assert_true(blob.contains("unknown_char_x"), "未知角色须显示原始 ID")
	assert_true(blob.contains(NAMES[0]) and blob.contains(NAMES[2]))
	var local_hits := 0
	var host := panel.find_child("RankRows", true, false)
	assert_not_null(host)
	for child in host.get_children():
		if child is Label and bool(child.get_meta("is_local", false)):
			local_hits += 1
	assert_eq(local_hits, 1, "恰好一行本席高亮")


func test_nav_actions_require_match_settled_latch() -> void:
	var host := Control.new()
	add_child_autofree(host)
	var coordinator := PublicMatchCoordinator.new()
	host.add_child(coordinator)
	await wait_process_frames(1)
	coordinator.set_last_public_intent_for_test(
		SessionIntent.new(&"PUBLIC_CASUAL", &"EAST", &"STANDARD", &"lin_yeche")
	)
	# matched 未 MATCH
	coordinator.consume_ticket_for_test({
		"status": "assigned", "round_kind": "EAST", "game_mode": "STANDARD",
		"worker": "ws://127.0.0.1:9", "room_id": "r-pre", "seat": 0,
		"room_token": "tok", "session_id": "g-pre",
	})
	assert_eq(str(coordinator.get_view().get("state", "")), "matched")
	assert_false(coordinator.request_rematch(), "matched 不得 rematch")
	assert_false(coordinator.request_return_lobby(), "matched 不得 return")
	assert_eq(str(coordinator.get_view().get("state", "")), "matched")

	# 真实 MATCH 后才可
	coordinator.begin_network_from_assigned_for_test({
		"status": "assigned", "round_kind": "EAST", "game_mode": "STANDARD",
		"worker": "ws://127.0.0.1:9", "room_id": "r-match-nav", "seat": 0,
		"room_token": "tok2", "session_id": "g-match-nav",
	})
	await wait_process_frames(2)
	var sess := coordinator.get_active_session()
	assert_not_null(sess)
	if sess.nbc == null:
		sess.nbc = NetworkedBattleController.new(sess.room_id, sess.seat)
		sess.seq_bridge.bind_networked_controller(sess.nbc)
	var room := str(sess.room_id)
	var recip := int(sess.seat)
	var snap := _rs(1, _snap_payload(1, recip, _core(recip, [25000, 25000, 25000, 25000])), room)
	_feed(sess, snap)
	var vh := snap.view_hash
	var seq := 2
	for s in range(4):
		_feed(sess, _pj(seq, vh, s, NAMES[s], room))
		seq += 1
	var finals := [33000, 23000, 24000, 20000]
	_feed(sess, _hs(seq, vh, finals, room))
	seq += 1
	_feed(sess, _ms(seq, vh, finals, [0, 2, 1, 3], room))
	await wait_process_frames(1)
	assert_eq(str(coordinator.get_view().get("state", "")), "match_settled")

	# 缺 intent 负例：必须先有真实 MATCH 终场，再清 intent
	coordinator.set_last_public_intent_for_test(
		SessionIntent.new(&"PUBLIC_CASUAL", &"EAST", &"STANDARD", &"")
	)
	var ok_no_intent := coordinator.request_rematch()
	assert_false(ok_no_intent, "缺角色 intent 不得 rematch 成功")
	assert_eq(str(coordinator.get_view().get("error_code", "")), "NO_INTENT",
		"须 terminal NO_INTENT")
