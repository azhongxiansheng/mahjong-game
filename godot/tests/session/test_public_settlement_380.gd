extends GutTest

# #380 Red round-2：公共客户端只读消费 committed HAND_SETTLED / MATCH_SETTLED。
# 入口：ingest_authority_wire_for_test → AuthoritySeqBridge → NBC journal → get_settlement_view。
# Fixture：NetworkedEvent.make（生产 validator）+ MatchingMetaSnapshotProvider.fixture_module。
# 禁止：GameDriver / ScoreCalc / 本地 build_seat_order 排名 / 私有 helper 驱动终局。
# 公网四客户端端到端未验证。

const ROOM := "room-380-r2"
const CHARS := ["lin_yeche", "an_cheng", "bai_touli", "hua_ling"]
const PARTS := ["HUMAN", "HUMAN", "AI", "AI"]
const NAMES := ["Alice", "Bob", "CPU-南", "CPU-西"]

const FIXTURE_HAND := "NetworkedEvent.make/HAND_SETTLED ↔ _validate_hand_settled"
const FIXTURE_MATCH := "NetworkedEvent.make/MATCH_SETTLED ↔ _validate_match_settled（分降序+同分 seat 升序）"
const FIXTURE_SNAP := "NetworkedEvent.make/ROOM_SNAPSHOT + ProtocolViewCodec.compute_view_hash"
const FIXTURE_JOIN := "NetworkedEvent.make/PLAYER_JOINED ↔ _validate_player_joined"
const FIXTURE_META := "MatchingMetaSnapshotProvider.fixture_module"

const PROD_FILES_NO_LOCAL_RANK := [
	"res://session/public_casual_network_session.gd",
	"res://ui/lobby/public_match_coordinator.gd",
	"res://ui/four_player_table/playable_table.gd",
	"res://ui/four_player_table/match_settlement_panel.gd",
]


func _iid(tile_id: int, copy: int, hand_seq: int = 0) -> int:
	return hand_seq * 136 + TileId.ALL.find(tile_id) * 4 + copy


func _tile(tile_id: int, copy: int, red := false, hand_seq: int = 0) -> Dictionary:
	return {
		"instance_id": _iid(tile_id, copy, hand_seq),
		"tile_id": tile_id,
		"is_red_dora": red,
		"owner_seat": copy,
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
		"score": score,
		"concealed_tiles": concealed,
		"concealed_count": count,
		"last_drawn_tile_instance_id": -1,
		"river": [],
		"melds": [],
		"riichi_declared": false,
		"riichi_double": false,
		"riichi_discard_index": -1,
	}


func _core(
	recip: int,
	scores: Array,
	hand_seq := 0,
	dealer := 0,
	honba := 0,
	sticks := 0,
	hand_number := 1,
	round_wind: int = TileId.E
) -> Dictionary:
	var seats: Array = []
	for s in range(4):
		seats.append(_seat(s, int(scores[s]), hand_seq, recip))
	return {
		"recipient_seat": recip,
		"hand_seq": hand_seq,
		"dealer_seat": dealer,
		"current_seat": recip,
		"phase": "DRAW",
		"round_wind": round_wind,
		"hand_number": hand_number,
		"honba": honba,
		"riichi_sticks": sticks,
		"live_wall_count": 70,
		"dora_indicators": [_tile(TileId.S1, 0, false, hand_seq)],
		"seats": seats,
	}


func _snap_payload(seq: int, recip: int, core: Dictionary) -> Dictionary:
	return {
		"snapshot_server_seq": seq,
		"next_server_seq": seq + 1,
		"seat_view": recip,
		"modules": [
			{"module_key": "core_table", "schema_version": 1, "payload": core.duplicate(true)},
			MatchingMetaSnapshotProvider.fixture_module(CHARS, PARTS),
		],
	}


func _rs(seq: int, payload: Dictionary, room: String) -> NetworkedEvent:
	var h := ProtocolViewCodec.compute_view_hash(payload)
	var ne := NetworkedEvent.make("ROOM_SNAPSHOT", seq, room, payload, h)
	assert_not_null(ne, FIXTURE_SNAP)
	return ne


func _hand_payload(
	scores: Array,
	outcome := "RON",
	winners: Array = [2],
	loser := 1,
	deltas: Array = [-1000, -2000, 8000, -5000],
	hand_seq := 0,
	dealer := 0,
	renchan := false,
	honba := 1,
	sticks := 0
) -> Dictionary:
	return {
		"hand_seq": hand_seq,
		"outcome": outcome,
		"winner_seats": winners.duplicate(),
		"loser_seat": loser,
		"score_deltas": deltas.duplicate(),
		"scores": scores.duplicate(),
		"dealer_seat": dealer,
		"renchan": renchan,
		"honba": honba,
		"riichi_sticks": sticks,
		"adjustments": [],
	}


func _hs(seq: int, vh: String, payload: Dictionary, room: String) -> NetworkedEvent:
	var ne := NetworkedEvent.make("HAND_SETTLED", seq, room, payload, vh)
	assert_not_null(ne, FIXTURE_HAND)
	return ne


func _ms(
	seq: int,
	vh: String,
	finals: Array,
	order: Array,
	room: String,
	round_kind := "EAST"
) -> NetworkedEvent:
	# 调用方必须提供协议合法 seat_order（分降序、同分 seat 升序）
	var ne := NetworkedEvent.make("MATCH_SETTLED", seq, room, {
		"round_kind": round_kind,
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


func _bind(room: String, seat: int) -> PublicCasualNetworkSession:
	var nbc := NetworkedBattleController.new(room, seat)
	var sess := PublicCasualNetworkSession.new()
	add_child_autofree(sess)
	sess.room_id = room
	sess.seat = seat
	sess.session_id = "guest-380-r2-%d" % seat
	sess.worker_url = "ws://127.0.0.1:9"
	sess.room_token = "tok-380-r2"
	sess.game_mode = "STANDARD"
	sess.nbc = nbc
	sess.seq_bridge.bind_networked_controller(nbc)
	return sess


func _feed(sess: PublicCasualNetworkSession, ne: NetworkedEvent) -> void:
	sess.ingest_authority_wire_for_test(JSON.stringify(ne.to_dict()))


func _bootstrap(sess: PublicCasualNetworkSession, recip: int, scores := [25000, 25000, 25000, 25000]) -> String:
	var room := str(sess.room_id)
	var snap := _rs(1, _snap_payload(1, recip, _core(recip, scores)), room)
	_feed(sess, snap)
	return snap.view_hash


func _roster(sess: PublicCasualNetworkSession, start_seq: int, vh: String) -> int:
	var room := str(sess.room_id)
	var seq := start_seq
	for s in range(4):
		_feed(sess, _pj(seq, vh, s, NAMES[s], room))
		seq += 1
	return seq


func _view(sess: PublicCasualNetworkSession) -> Dictionary:
	# 不因缺 API 提前 return；缺方法时仍走失败断言
	assert_true(sess.has_method("get_settlement_view"),
		"#380 PublicCasualNetworkSession 须暴露 get_settlement_view()")
	assert_true(sess.has_signal("settlement_view_changed"),
		"#380 session 须有 settlement_view_changed")
	if not sess.has_method("get_settlement_view"):
		return {}
	return sess.get_settlement_view()


# ── 接口存在（独立 Red，不跳过）────────────────────────────

func test_settlement_projection_api_exists() -> void:
	var sess := _bind(ROOM + "-api", 0)
	assert_true(sess.has_method("get_settlement_view"),
		"#380 须有 get_settlement_view")
	assert_true(sess.has_signal("settlement_view_changed"),
		"#380 须有 settlement_view_changed")


# ── 仅 committed 入投影 ────────────────────────────────────

func test_only_committed_hand_enters_settlement_view() -> void:
	var room := ROOM + "-commit"
	var recip := 1
	var sess := _bind(room, recip)
	var idle := _view(sess)
	assert_eq(str(idle.get("phase", "")), "idle")

	var vh := _bootstrap(sess, recip)
	var seq := _roster(sess, 2, vh)

	# pending：异 hash HAND 不入 journal 投影
	var pending := _hs(seq, "a".repeat(64), _hand_payload(
		[28000, 24000, 24000, 24000], "TSUMO", [0], -1, [3000, -1000, -1000, -1000]
	), room)
	_feed(sess, pending)
	var after_pending := _view(sess)
	assert_eq(str(after_pending.get("phase", "")), "idle", "pending HAND 不得改 phase")
	assert_true(
		after_pending.get("hand", null) == null
		or str(after_pending.get("hand", "")) == ""
		or (typeof(after_pending.get("hand")) == TYPE_DICTIONARY
			and (after_pending.get("hand") as Dictionary).is_empty()),
		"pending HAND 不得进入 hand 投影"
	)

	# 干净序列 committed HAND（独立 room，避免 pending 占用 seq）
	var room2 := ROOM + "-commit-ok"
	var sess2 := _bind(room2, recip)
	var vh2 := _bootstrap(sess2, recip)
	var seq2 := _roster(sess2, 2, vh2)
	var scores := [24000, 23000, 33000, 20000]
	var hand_ne := _hs(seq2, vh2, _hand_payload(scores), room2)
	_feed(sess2, hand_ne)
	var after := _view(sess2)
	assert_eq(str(after.get("phase", "")), "hand_result")
	var hand: Dictionary = after.get("hand", {}) if typeof(after.get("hand")) == TYPE_DICTIONARY else {}
	assert_eq(str(hand.get("outcome", "")), "RON")
	assert_eq(hand.get("winner_seats", []), [2])
	assert_eq(int(hand.get("loser_seat", -9)), 1)
	assert_eq(hand.get("score_deltas", []), [-1000, -2000, 8000, -5000])
	assert_eq(hand.get("scores", []), scores)
	assert_eq(int(hand.get("server_seq", -1)), seq2)

	# 重复同 seq / 更旧 seq 不覆盖
	_feed(sess2, hand_ne)
	_feed(sess2, _hs(seq2 - 1, vh2, _hand_payload(
		[26000, 24000, 25000, 25000], "TSUMO", [0], -1, [1000, -1000, 0, 0]
	), room2))
	var dup := _view(sess2)
	assert_eq(str(dup.get("phase", "")), "hand_result")
	var hand2: Dictionary = dup.get("hand", {}) if typeof(dup.get("hand")) == TYPE_DICTIONARY else {}
	assert_eq(hand2.get("scores", []), scores, "重复/旧 HAND 不得覆盖权威 scores")
	assert_eq(str(hand2.get("outcome", "")), "RON")


func test_hand_settled_exposes_authority_fields() -> void:
	var room := ROOM + "-fields"
	var sess := _bind(room, 0)
	var vh := _bootstrap(sess, 0)
	var scores := [24000, 24000, 24000, 28000]
	_feed(sess, _hs(2, vh, _hand_payload(
		scores, "TSUMO", [3], -1, [-1000, -1000, -1000, 3000], 0, 3, true, 2, 1
	), room))
	var hand: Dictionary = _view(sess).get("hand", {}) if typeof(_view(sess).get("hand")) == TYPE_DICTIONARY else {}
	# 再取一次避免双重 _view 信号噪音
	var v := _view(sess)
	hand = v.get("hand", {}) if typeof(v.get("hand")) == TYPE_DICTIONARY else {}
	assert_eq(str(hand.get("outcome", "")), "TSUMO")
	assert_eq(hand.get("winner_seats", []), [3])
	assert_eq(int(hand.get("loser_seat", 0)), -1)
	assert_eq(hand.get("score_deltas", []), [-1000, -1000, -1000, 3000])
	assert_eq(hand.get("scores", []), scores)
	assert_eq(int(hand.get("dealer_seat", -1)), 3)
	assert_true(bool(hand.get("renchan", false)))
	assert_eq(int(hand.get("honba", -1)), 2)
	assert_eq(int(hand.get("riichi_sticks", -1)), 1)
	assert_eq(int(v.get("local_seat", -1)), 0)


# ── HAND→SNAP：精确成功 / 精确失败 ─────────────────────────

func test_hand_to_matching_snapshot_closes_hand_result() -> void:
	var room := ROOM + "-snap-ok"
	var recip := 2
	var sess := _bind(room, recip)
	var vh := _bootstrap(sess, recip)
	var settled := [24000, 23000, 33000, 20000]
	_feed(sess, _hs(2, vh, _hand_payload(settled), room))
	assert_eq(str(_view(sess).get("phase", "")), "hand_result")

	var next_core := _core(recip, settled, 1, 1, 0, 0, 2, TileId.E)
	var next_payload := _snap_payload(3, recip, next_core)
	_feed(sess, _rs(3, next_payload, room))
	var after := _view(sess)
	assert_eq(str(after.get("phase", "")), "idle",
		"起分一致后 phase 必须为 idle（自动关单局）")
	assert_true(
		after.get("hand", null) == null
		or (typeof(after.get("hand")) == TYPE_DICTIONARY
			and (after.get("hand") as Dictionary).is_empty()),
		"起分一致后 hand 投影须清空"
	)


func test_hand_to_mismatched_snapshot_resync_keeps_hand_scores() -> void:
	var room := ROOM + "-snap-bad"
	var recip := 2
	var sess := _bind(room, recip)
	var reconnecting_codes: Array = []
	var recovered_count := [0]
	sess.reconnecting.connect(func(code: String, _m: String): reconnecting_codes.append(code))
	sess.recovered.connect(func(): recovered_count[0] += 1)
	var vh := _bootstrap(sess, recip)
	var settled := [24000, 23000, 33000, 20000]
	_feed(sess, _hs(2, vh, _hand_payload(settled), room))
	assert_eq(str(_view(sess).get("phase", "")), "hand_result")

	# 故意错误起分
	var bad_core := _core(recip, [25000, 25000, 25000, 25000], 1, 1, 0, 0, 2)
	_feed(sess, _rs(3, _snap_payload(3, recip, bad_core), room))
	var after := _view(sess)
	assert_eq(str(after.get("phase", "")), "resync",
		"起分不一致 phase 必须为 resync")
	assert_eq(reconnecting_codes.size(), 1, "resync reconnecting 恰好一次")
	assert_eq(str(reconnecting_codes[0]), "SETTLEMENT_SCORE_MISMATCH")
	# HAND 权威 scores 必须保留（不得包在 is_empty 逃逸）
	assert_true(typeof(after.get("hand")) == TYPE_DICTIONARY, "hand 投影须仍在")
	var hand: Dictionary = after.get("hand", {})
	assert_eq(hand.get("scores", []), settled,
		"不一致 SNAP 不得覆盖权威 HAND scores")
	# NBC 不得提交错误 core scores；resync_required 必须 true
	assert_true(sess.nbc != null and sess.nbc.resync_required(),
		"NBC.resync_required 须为 true")
	var core: Dictionary = sess.nbc.get_core_table_view()
	var core_scores: Array = []
	for sv in core.get("seats", []):
		if typeof(sv) == TYPE_DICTIONARY:
			core_scores.append(int((sv as Dictionary).get("score", -1)))
	# 错误 SNAP 未提交：core 仍为局前 25000（bootstrap）
	assert_eq(core_scores, [25000, 25000, 25000, 25000],
		"错误 SNAP 不得进入 NBC core scores")
	assert_eq(recovered_count[0], 0, "错误 SNAP 同帧不得 recovered")


# ── HAND 无 READY 副作用 ───────────────────────────────────

func test_hand_settlement_has_no_ready_side_effect() -> void:
	var room := ROOM + "-noready"
	var sess := _bind(room, 0)
	var vh := _bootstrap(sess, 0)
	var ready_before := sess.is_game_ready_sent()
	_feed(sess, _hs(2, vh, _hand_payload([24000, 23000, 33000, 20000]), room))
	assert_eq(str(_view(sess).get("phase", "")), "hand_result")
	assert_eq(sess.is_game_ready_sent(), ready_before, "HAND 不得改写 READY")
	assert_false(sess.is_command_pending(), "HAND 不得产生 pending 命令")
	assert_false(sess.is_awaiting_authority_commit(), "HAND 不得 awaiting_committed")


# ── MATCH 权威排名 + 协议负例 + 静态边界 ───────────────────

func test_match_settled_uses_payload_seat_order_and_roster() -> void:
	var room := ROOM + "-match"
	var recip := 2
	var sess := _bind(room, recip)
	var vh := _bootstrap(sess, recip)
	var seq := _roster(sess, 2, vh)
	# 协议合法：0=33000 > 2=24000 > 1=23000 > 3=20000 → [0,2,1,3]
	var finals := [33000, 23000, 24000, 20000]
	var order := [0, 2, 1, 3]
	assert_eq(order, MatchSettlement.build_seat_order(finals),
		"fixture 须为生产 validator 可接受的 canonical 序")
	_feed(sess, _hs(seq, vh, _hand_payload(finals, "RON", [0], 3,
		[8000, -2000, -1000, -5000]), room))
	seq += 1
	_feed(sess, _ms(seq, vh, finals, order, room))
	var v := _view(sess)
	assert_eq(str(v.get("phase", "")), "match_result")
	var match_v: Dictionary = v.get("match", {}) if typeof(v.get("match")) == TYPE_DICTIONARY else {}
	assert_eq(match_v.get("seat_order", []), order,
		"排名必须等于 payload.seat_order")
	assert_eq(match_v.get("final_scores", []), finals)
	assert_eq(str(match_v.get("round_kind", "")), "EAST")
	var rows: Array = match_v.get("rows", [])
	assert_eq(rows.size(), 4)
	assert_eq(int((rows[0] as Dictionary).get("seat_id", -1)), 0)
	assert_eq(str((rows[0] as Dictionary).get("name", "")), NAMES[0])
	assert_eq(str((rows[0] as Dictionary).get("character_id", "")), CHARS[0])
	assert_eq(int((rows[0] as Dictionary).get("score", -1)), 33000)
	assert_false(bool((rows[0] as Dictionary).get("is_local", true)))
	assert_eq(int((rows[1] as Dictionary).get("seat_id", -1)), 2)
	assert_eq(str((rows[1] as Dictionary).get("name", "")), NAMES[2])
	assert_true(bool((rows[1] as Dictionary).get("is_local", false)), "本席 recip=2")
	assert_eq(int((rows[2] as Dictionary).get("seat_id", -1)), 1)
	assert_eq(int(v.get("local_seat", -1)), 2)


func test_protocol_rejects_illegal_and_tie_misordered_seat_order() -> void:
	var vh := "b".repeat(64)
	assert_null(NetworkedEvent.make("MATCH_SETTLED", 1, ROOM, {
		"round_kind": "EAST",
		"final_scores": [30000, 25000, 25000, 20000],
		"seat_order": [0, 1, 1, 2],
	}, vh), "重复 seat_order 须拒绝")
	assert_null(NetworkedEvent.make("MATCH_SETTLED", 1, ROOM, {
		"round_kind": "EAST",
		"final_scores": [30000, 25000, 25000, 20000],
		"seat_order": [0, 1, 2],
	}, vh), "残缺 seat_order 须拒绝")
	# 同分 25000 时 [0,2,1,3] 违反 seat 升序 → 协议拒绝
	assert_null(NetworkedEvent.make("MATCH_SETTLED", 1, ROOM, {
		"round_kind": "EAST",
		"final_scores": [30000, 25000, 25000, 20000],
		"seat_order": [0, 2, 1, 3],
	}, vh), "同分乱序 seat_order 须被生产 validator 拒绝")
	assert_not_null(NetworkedEvent.make("MATCH_SETTLED", 1, ROOM, {
		"round_kind": "EAST",
		"final_scores": [30000, 25000, 25000, 20000],
		"seat_order": [0, 1, 2, 3],
	}, vh), "canonical 同分序须接受")


func test_production_settlement_files_do_not_call_local_build_seat_order() -> void:
	for path in PROD_FILES_NO_LOCAL_RANK:
		assert_true(FileAccess.file_exists(path), "生产文件须存在: %s" % path)
		var src := FileAccess.get_file_as_string(path)
		assert_false(src.contains("MatchSettlement.build_seat_order"),
			"#380 生产路径禁止调用 MatchSettlement.build_seat_order: %s" % path)


# ── MATCH 锁存 ─────────────────────────────────────────────

func test_match_settled_latches_against_duplicate_and_late_snapshot() -> void:
	var room := ROOM + "-latch"
	var recip := 1
	var sess := _bind(room, recip)
	var vh := _bootstrap(sess, recip)
	var seq := _roster(sess, 2, vh)
	var finals := [28000, 27000, 24000, 21000]
	var order := [0, 1, 2, 3]
	_feed(sess, _hs(seq, vh, _hand_payload(finals, "TSUMO", [0], -1,
		[3000, -1000, -1000, -1000]), room))
	seq += 1
	_feed(sess, _ms(seq, vh, finals, order, room))
	assert_eq(str(_view(sess).get("phase", "")), "match_result")
	# 重复 MATCH（同 seq 重放）
	_feed(sess, _ms(seq, vh, [1000, 1000, 1000, 97000], [3, 0, 1, 2], room))
	var after_dup := _view(sess)
	assert_eq(str(after_dup.get("phase", "")), "match_result")
	var mv: Dictionary = after_dup.get("match", {}) if typeof(after_dup.get("match")) == TYPE_DICTIONARY else {}
	assert_eq(mv.get("seat_order", []), order, "重复 MATCH 不得覆盖 seat_order")
	assert_eq(mv.get("final_scores", []), finals, "重复 MATCH 不得覆盖 final_scores")
	# 迟到 SNAP：整包丢弃，NBC 不推进
	var seq_before := int(sess.nbc.current_seq())
	var journal_before: int = sess.nbc.get_event_journal().size()
	_feed(sess, _rs(seq + 1, _snap_payload(seq + 1, recip, _core(recip, finals, 1)), room))
	var after_late := _view(sess)
	assert_eq(str(after_late.get("phase", "")), "match_result", "迟到 SNAP 不得覆盖终场")
	var mv2: Dictionary = after_late.get("match", {}) if typeof(after_late.get("match")) == TYPE_DICTIONARY else {}
	assert_eq(mv2.get("final_scores", []), finals)
	assert_eq(int(sess.nbc.current_seq()), seq_before, "终场迟到 SNAP 不得推进 NBC")
	assert_eq(sess.nbc.get_event_journal().size(), journal_before)


func test_local_seat_1_to_3_mapping() -> void:
	for recip in [1, 2, 3]:
		var room := "%s-seat%d" % [ROOM, recip]
		var sess := _bind(room, recip)
		var vh := _bootstrap(sess, recip)
		var seq := _roster(sess, 2, vh)
		var finals := [20000, 22000, 28000, 30000]
		var order := [3, 2, 1, 0]
		_feed(sess, _hs(seq, vh, _hand_payload(finals, "RON", [3], 0,
			[-8000, 0, 0, 8000]), room))
		seq += 1
		_feed(sess, _ms(seq, vh, finals, order, room))
		var v := _view(sess)
		assert_eq(int(v.get("local_seat", -1)), recip)
		var rows: Array = []
		if typeof(v.get("match")) == TYPE_DICTIONARY:
			rows = (v.get("match") as Dictionary).get("rows", [])
		var hits := 0
		for row in rows:
			if typeof(row) != TYPE_DICTIONARY:
				continue
			var d: Dictionary = row
			if int(d.get("seat_id", -1)) == recip:
				assert_true(bool(d.get("is_local", false)))
				assert_eq(str(d.get("name", "")), NAMES[recip])
				assert_eq(str(d.get("character_id", "")), CHARS[recip])
				hits += 1
			else:
				assert_false(bool(d.get("is_local", false)))
		assert_eq(hits, 1, "恰好一行 is_local recip=%d" % recip)


func test_standard_settlement_view_has_no_skill_inventory_voice() -> void:
	var room := ROOM + "-std"
	var sess := _bind(room, 0)
	var vh := _bootstrap(sess, 0)
	_feed(sess, _hs(2, vh, _hand_payload([24000, 23000, 33000, 20000]), room))
	_feed(sess, _ms(3, vh, [33000, 23000, 24000, 20000], [0, 2, 1, 3], room))
	var v := _view(sess)
	var blob := JSON.stringify(v)
	for forbidden in [
		"item_inventory", "reward_window", "skill_attribution",
		"voice_transcript", "ability_armed", "ITEM_GRANTED",
	]:
		assert_false(v.has(forbidden), "STANDARD view 不得含 %s" % forbidden)
		assert_false(blob.contains(forbidden), "STANDARD JSON 不得含 %s" % forbidden)
	assert_eq(str(sess.game_mode), "STANDARD")


# ── 生产 encoder 裁剪 fixture（无私有驱动）────────────────

func test_hand_and_match_fixtures_match_production_encoder_keys() -> void:
	# 来源：对照 NetworkedEvent.HAND_SETTLED_KEYS / MATCH_SETTLED_KEYS 与 make roundtrip
	var hand_p := _hand_payload([25000, 25000, 25000, 25000], "EXHAUSTIVE_DRAW", [], -1,
		[0, 0, 0, 0])
	for k in NetworkedEvent.HAND_SETTLED_KEYS:
		assert_true(hand_p.has(k), "HAND fixture 须含生产键 %s" % k)
	var hand_ne := NetworkedEvent.make("HAND_SETTLED", 9, ROOM, hand_p, "c".repeat(64))
	assert_not_null(hand_ne, FIXTURE_HAND)
	var rt := NetworkedEvent.from_dict(hand_ne.to_dict())
	assert_not_null(rt)
	for k in NetworkedEvent.HAND_SETTLED_KEYS:
		assert_true(rt.payload.has(k), "roundtrip HAND 须保留 %s" % k)

	var match_p := {
		"round_kind": "EAST",
		"final_scores": [30000, 25000, 25000, 20000],
		"seat_order": [0, 1, 2, 3],
	}
	for k in NetworkedEvent.MATCH_SETTLED_KEYS:
		assert_true(match_p.has(k), "MATCH fixture 须含生产键 %s" % k)
	var match_ne := NetworkedEvent.make("MATCH_SETTLED", 10, ROOM, match_p, "d".repeat(64))
	assert_not_null(match_ne, FIXTURE_MATCH)

	# wire 入口消费
	var sess := _bind(ROOM + "-enc", 0)
	var vh := _bootstrap(sess, 0)
	_feed(sess, _hs(2, vh, hand_p, ROOM + "-enc"))
	assert_eq(str(_view(sess).get("phase", "")), "hand_result")


func test_stale_hand_seq_after_next_hand_snap_is_ignored() -> void:
	var room := ROOM + "-stale-hs"
	var recip := 0
	var sess := _bind(room, recip)
	var vh0 := _bootstrap(sess, recip, [25000, 25000, 25000, 25000])
	var scores0 := [24000, 23000, 33000, 20000]
	_feed(sess, _hs(2, vh0, _hand_payload(scores0), room))
	assert_eq(str(_view(sess).get("phase", "")), "hand_result")
	# 合法新局 SNAP hand_seq=1
	var next_core := _core(recip, scores0, 1, 1, 0, 0, 2, TileId.E)
	var next_payload := _snap_payload(3, recip, next_core)
	var snap1 := _rs(3, next_payload, room)
	_feed(sess, snap1)
	assert_eq(str(_view(sess).get("phase", "")), "idle")
	var vh1 := snap1.view_hash
	# 更高 server_seq 但 hand_seq=0 的旧 HAND —— 不得覆盖
	_feed(sess, _hs(4, vh1, _hand_payload(
		[1000, 1000, 97000, 1000], "TSUMO", [2], -1, [-1000, -1000, 3000, -1000], 0
	), room))
	var after := _view(sess)
	assert_eq(str(after.get("phase", "")), "idle", "旧 hand_seq HAND 不得打开 hand_result")
	assert_true(
		after.get("hand", null) == null
		or (typeof(after.get("hand")) == TYPE_DICTIONARY
			and (after.get("hand") as Dictionary).is_empty()),
		"旧 HAND 不得进入投影"
	)


func test_release_clears_identity_fields_idempotent() -> void:
	var sess := _bind(ROOM + "-rel", 2)
	sess.room_token = "secret-token-xyz"
	sess.session_id = "guest-secret"
	sess.worker_url = "ws://127.0.0.1:9999"
	sess.voice_worker_url = "ws://127.0.0.1:9998"
	sess.room_id = "room-secret"
	sess.game_mode = "STANDARD"
	sess.seat = 2
	sess.release()
	assert_eq(sess.room_token, "")
	assert_eq(sess.session_id, "")
	assert_eq(sess.worker_url, "")
	assert_eq(sess.voice_worker_url, "")
	assert_eq(sess.room_id, "")
	assert_eq(sess.seat, -1)
	assert_true(sess._released)
	# 幂等二次 release
	sess.release()
	assert_eq(sess.room_token, "")
	assert_eq(sess.session_id, "")


func test_match_latched_blocks_inventory_revival_phase() -> void:
	# STANDARD：终场后任意迟到 SNAP（无库存模块）静默丢弃，NBC seq/journal 不推进
	var room := ROOM + "-latch-inv"
	var recip := 0
	var sess := _bind(room, recip)
	var vh := _bootstrap(sess, recip)
	var seq := _roster(sess, 2, vh)
	var finals := [28000, 27000, 24000, 21000]
	var order := [0, 1, 2, 3]
	_feed(sess, _hs(seq, vh, _hand_payload(finals, "TSUMO", [0], -1,
		[3000, -1000, -1000, -1000]), room))
	seq += 1
	_feed(sess, _ms(seq, vh, finals, order, room))
	assert_eq(str(_view(sess).get("phase", "")), "match_result")
	var seq_before := int(sess.nbc.current_seq())
	var journal_before: int = sess.nbc.get_event_journal().size()
	var reconnecting := [0]
	var terminal := [0]
	sess.reconnecting.connect(func(_c, _m): reconnecting[0] += 1)
	sess.terminal_error.connect(func(_c, _m): terminal[0] += 1)
	# 迟到 SNAP（STANDARD 无库存 / 等价空库存路径）
	_feed(sess, _rs(seq + 1, _snap_payload(seq + 1, recip, _core(recip, finals, 1)), room))
	var after := _view(sess)
	assert_eq(str(after.get("phase", "")), "match_result")
	var mv: Dictionary = after.get("match", {}) if typeof(after.get("match")) == TYPE_DICTIONARY else {}
	assert_eq(mv.get("final_scores", []), finals)
	assert_eq(mv.get("seat_order", []), order)
	assert_eq(int(sess.nbc.current_seq()), seq_before, "迟到 SNAP 不得推进 NBC seq")
	assert_eq(sess.nbc.get_event_journal().size(), journal_before, "迟到 SNAP 不得写入 journal")
	assert_eq(reconnecting[0], 0, "不得 reconnecting")
	assert_eq(terminal[0], 0, "不得 terminal")
	assert_false(sess.nbc.resync_required())

func test_same_hand_seq_snap_does_not_close_hand_result() -> void:
	var room := ROOM + "-same-hs"
	var recip := 0
	var sess := _bind(room, recip)
	var vh := _bootstrap(sess, recip)
	var settled := [24000, 23000, 33000, 20000]
	_feed(sess, _hs(2, vh, _hand_payload(settled), room))
	assert_eq(str(_view(sess).get("phase", "")), "hand_result")
	# 同 hand_seq=0、更高 server_seq、起分一致的 filler SNAP 不得关弹层
	var filler := _core(recip, settled, 0, 0, 1, 0, 1, TileId.E)
	_feed(sess, _rs(3, _snap_payload(3, recip, filler), room))
	assert_eq(str(_view(sess).get("phase", "")), "hand_result",
		"同/旧 hand_seq SNAP 不得关闭 hand_result")
	var hand: Dictionary = _view(sess).get("hand", {}) if typeof(_view(sess).get("hand")) == TYPE_DICTIONARY else {}
	# 再取
	var v := _view(sess)
	hand = v.get("hand", {}) if typeof(v.get("hand")) == TYPE_DICTIONARY else {}
	assert_eq(hand.get("scores", []), settled)
	# 合法 hand_seq=1 才关闭
	var next := _core(recip, settled, 1, 1, 0, 0, 2, TileId.E)
	_feed(sess, _rs(4, _snap_payload(4, recip, next), room))
	assert_eq(str(_view(sess).get("phase", "")), "idle")


func _reward_window_idle_mod() -> Dictionary:
	# 真实 RewardWindowModule 公开 DTO（IDLE），保证 TRASH registry can_restore
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


func _bind_trash(room: String, seat: int) -> PublicCasualNetworkSession:
	# TRASH_TALK + 真实 NBC snapshot registry（含 item_inventory）
	var nbc := NetworkedBattleController.new(room, seat)
	nbc.configure_snapshot_registry_for_mode("TRASH_TALK")
	assert_true(nbc.snapshot_registry.is_trash_talk_registry(), "须为 TRASH registry")
	var sess := PublicCasualNetworkSession.new()
	add_child_autofree(sess)
	sess.room_id = room
	sess.seat = seat
	sess.session_id = "guest-380-tt-%d" % seat
	sess.worker_url = "ws://127.0.0.1:9"
	sess.voice_worker_url = "ws://127.0.0.1:8"
	sess.room_token = "tok-380-tt"
	sess.game_mode = "TRASH_TALK"
	sess.nbc = nbc
	sess.seq_bridge.bind_networked_controller(nbc)
	return sess


func _trash_snap_payload(seq: int, recip: int, core: Dictionary, inv_items: Array) -> Dictionary:
	# module_key 必须严格升序：core_table < item_inventory < matching_meta < reward_window
	return {
		"snapshot_server_seq": seq,
		"next_server_seq": seq + 1,
		"seat_view": recip,
		"modules": [
			{"module_key": "core_table", "schema_version": 1, "payload": core.duplicate(true)},
			_item_inv_mod(recip, inv_items),
			MatchingMetaSnapshotProvider.fixture_module(CHARS, PARTS),
			_reward_window_idle_mod(),
		],
	}


func _grant_inv_items(room: String, seat: int) -> Array:
	var inv := ItemInventoryModule.new()
	inv.set_match_namespace(room)
	assert_true(bool(inv.grant_for_seat({
		"seat": seat, "item_id": "iron_shield_v1", "window_id": "w0",
		"hand_seq": 0, "score": 1, "rule_version": "rv", "assignment_version": "av",
		"matched_rule_ids": [], "affinity_match": false,
	}).get("ok", false)), "grant 须成功")
	var payload: Dictionary = inv.to_seat_snapshot_dto(seat)["payload"]
	var items: Array = payload.get("items", []) as Array
	assert_gt(items.size(), 0, "fixture 须非空库存")
	return items.duplicate(true)


func test_trash_talk_inventory_kept_on_match_late_snaps_discarded() -> void:
	# 真实 TRASH_TALK registry：非空库存 SNAP 入 NBC → MATCH 锁存但不伪造 restore；
	# 迟到空/非空 SNAP 均静默丢弃，NBC 保留最后一个真实权威库存投影。
	var room := ROOM + "-tt-inv"
	var recip := 0
	var sess := _bind_trash(room, recip)
	var items := _grant_inv_items(room, recip)
	var scores := [25000, 25000, 25000, 25000]
	var p0 := _trash_snap_payload(1, recip, _core(recip, scores), items)
	var snap0 := _rs(1, p0, room)
	_feed(sess, snap0)
	var inv_after: Dictionary = sess.nbc.get_item_inventory_view()
	assert_false(inv_after.is_empty(), "TRASH registry 须消费 item_inventory")
	assert_gt((inv_after.get("items", []) as Array).size(), 0, "NBC 须有非空库存")
	var inv_fp_before := JSON.stringify(inv_after)
	var seq_before_match := int(sess.nbc.current_seq())
	var journal_before_match: int = sess.nbc.get_event_journal().size()
	var vh := snap0.view_hash
	var finals := [28000, 27000, 24000, 21000]
	_feed(sess, _hs(2, vh, _hand_payload(finals, "TSUMO", [0], -1,
		[3000, -1000, -1000, -1000]), room))
	_feed(sess, _ms(3, vh, finals, [0, 1, 2, 3], room))
	assert_eq(str(_view(sess).get("phase", "")), "match_result")
	# MATCH 后 NBC 仍保留最后一个真实权威库存投影（禁止客户端伪造 restore）
	var inv_match: Dictionary = sess.nbc.get_item_inventory_view()
	assert_eq(JSON.stringify(inv_match), inv_fp_before,
		"MATCH 不得伪造 apply_restored_module 清空 NBC 库存")
	assert_gt((inv_match.get("items", []) as Array).size(), 0)
	var seq_at_match := int(sess.nbc.current_seq())
	assert_gt(seq_at_match, seq_before_match, "HAND/MATCH 须推进 NBC seq")
	var journal_at_match: int = sess.nbc.get_event_journal().size()
	assert_gt(journal_at_match, journal_before_match)
	var finals_before = (_view(sess).get("match", {}) as Dictionary).get("final_scores", [])
	var order_before = (_view(sess).get("match", {}) as Dictionary).get("seat_order", [])

	var reconnecting := [0]
	var terminal := [0]
	sess.reconnecting.connect(func(_c, _m): reconnecting[0] += 1)
	sess.terminal_error.connect(func(_c, _m): terminal[0] += 1)

	# 迟到 1：空库存 SNAP
	var p_empty := _trash_snap_payload(4, recip, _core(recip, finals, 1), [])
	var late_empty := NetworkedEvent.make(
		"ROOM_SNAPSHOT", 4, room, p_empty, ProtocolViewCodec.compute_view_hash(p_empty)
	)
	assert_not_null(late_empty)
	_feed(sess, late_empty)
	assert_eq(int(sess.nbc.current_seq()), seq_at_match, "空库存迟到 SNAP 不得推进 seq")
	assert_eq(sess.nbc.get_event_journal().size(), journal_at_match)
	assert_eq(JSON.stringify(sess.nbc.get_item_inventory_view()), inv_fp_before,
		"空库存迟到 SNAP 不得改写权威库存")

	# 迟到 2：非空库存 SNAP
	var p_late := _trash_snap_payload(5, recip, _core(recip, finals, 1), items)
	var late := NetworkedEvent.make(
		"ROOM_SNAPSHOT", 5, room, p_late, ProtocolViewCodec.compute_view_hash(p_late)
	)
	assert_not_null(late, "含真实 item_inventory 的 SNAP 须通过 NetworkedEvent.make")
	_feed(sess, late)
	assert_eq(int(sess.nbc.current_seq()), seq_at_match, "非空迟到 SNAP 不得推进 seq")
	assert_eq(sess.nbc.get_event_journal().size(), journal_at_match)
	assert_eq(JSON.stringify(sess.nbc.get_item_inventory_view()), inv_fp_before,
		"非空迟到 SNAP 不得改写/复活权威库存")

	var after := _view(sess)
	assert_eq(str(after.get("phase", "")), "match_result")
	assert_eq(reconnecting[0], 0, "不得 reconnecting")
	assert_eq(terminal[0], 0, "不得 terminal")
	assert_false(sess.nbc.resync_required(), "不得 force resync")
	var match_after: Dictionary = after.get("match", {}) if typeof(after.get("match")) == TYPE_DICTIONARY else {}
	assert_eq(match_after.get("final_scores", []), finals_before)
	assert_eq(match_after.get("seat_order", []), order_before)
