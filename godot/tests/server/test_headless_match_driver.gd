extends GutTest

# #376 Round-4：真实 Action/DecisionContext 入口验收；禁止伪造 settlement / 私设 _settled。

const CHARS := ["lin_yeche", "an_cheng", "bai_touli", "hua_ling"]
const PARTS_4H := ["HUMAN", "HUMAN", "HUMAN", "HUMAN"]
const PARTS_1H := ["HUMAN", "AI", "AI", "AI"]


func _claims(
	room: String,
	parts: Array,
	round_kind := "EAST",
	mode := "STANDARD"
) -> Dictionary:
	return {
		"room_id": room,
		"seat": 0,
		"session_id": "sess-0",
		"round_kind": round_kind,
		"game_mode": mode,
		"participants": parts,
		"character_ids": CHARS,
		"expires_at_unix": 9999999999,
	}


func _boot(
	room: String,
	parts: Array = PARTS_1H,
	round_kind := "EAST",
	mode := "STANDARD",
	p_seed: int = 42,
	now_ms: int = 1000
) -> HeadlessRoomSession:
	var s := HeadlessRoomSession.new()
	s.set_seed_override_for_test(p_seed)
	assert_true(s.bootstrap_from_claims(_claims(room, parts, round_kind, mode), now_ms))
	return s


func _join_ready_all_humans(s: HeadlessRoomSession) -> void:
	for i in range(4):
		if not s.is_human_seat(i):
			continue
		assert_true(bool(s.join(i, "sess-%d" % i)["ok"]), "join %d" % i)
	for i2 in range(4):
		if not s.is_human_seat(i2):
			continue
		assert_true(bool(s.ready(i2, "sess-%d" % i2)["ok"]), "ready %d" % i2)
	assert_true(s.is_started())


func _count_kind(session: HeadlessRoomSession, kind: String, seat: int = 0) -> int:
	var n := 0
	for e in session.event_journal(seat):
		if e is NetworkedEvent and (e as NetworkedEvent).kind == kind:
			n += 1
	return n


func _kinds(session: HeadlessRoomSession, seat: int = 0) -> Array:
	var out: Array = []
	for e in session.event_journal(seat):
		if e is NetworkedEvent:
			out.append((e as NetworkedEvent).kind)
	return out


func _last_match_authority(session: HeadlessRoomSession) -> Dictionary:
	var j: Array = session.event_journal(0)
	for i in range(j.size() - 1, -1, -1):
		var e = j[i]
		if not (e is NetworkedEvent):
			continue
		var ne: NetworkedEvent = e as NetworkedEvent
		if ne.kind != "ROOM_SNAPSHOT":
			continue
		for m in ne.payload.get("modules", []):
			if typeof(m) == TYPE_DICTIONARY \
					and str(m.get("module_key", "")) == "match_authority":
				return (m.get("payload", {}) as Dictionary).duplicate(true)
	return {}


func _last_match_settled(session: HeadlessRoomSession) -> Dictionary:
	var j: Array = session.event_journal(0)
	for i in range(j.size() - 1, -1, -1):
		var e = j[i]
		if e is NetworkedEvent and (e as NetworkedEvent).kind == "MATCH_SETTLED":
			return ((e as NetworkedEvent).payload as Dictionary).duplicate(true)
	return {}


func _last_hand_settled(session: HeadlessRoomSession) -> Dictionary:
	var j: Array = session.event_journal(0)
	for i in range(j.size() - 1, -1, -1):
		var e = j[i]
		if e is NetworkedEvent and (e as NetworkedEvent).kind == "HAND_SETTLED":
			return ((e as NetworkedEvent).payload as Dictionary).duplicate(true)
	return {}


func _pull_tid(bc: BattleController, tid: int, used: Dictionary) -> Tile:
	var w: Wall = bc.state.wall
	var end_i: int = w.authority_tiles().size() - w.dead_wall_size()
	for i in range(w.draw_index(), end_i):
		var t: Tile = w.authority_tiles()[i]
		if t == null or int(t.id) != tid:
			continue
		if used.has(int(t.instance_id)):
			continue
		if i != w.draw_index():
			if not w.move_live_index_to_top(i):
				return null
		var drawn: Tile = w.draw()
		if drawn != null:
			used[int(drawn.instance_id)] = true
		return drawn
	return null


func _live_end(w: Wall) -> int:
	return w.authority_tiles().size() - w.dead_wall_size()


## arrange：七对听 + 摸进 TSUMO 窗（最终仍经 submit_action）。
func _arrange_tsumo_ready(bc: BattleController, seat: int) -> bool:
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
		var t: Tile = _pull_tid(bc, int(tid), used)
		if t == null:
			return false
		if not h.add(t):
			return false
	bc.state.seats[seat].hand = h
	bc.state.first_round_active = false
	var win_t: Tile = _pull_tid(bc, TileId.W9, used)
	if win_t == null:
		return false
	if not bc.state.seats[seat].hand.add(win_t):
		return false
	bc.state.seats[seat].last_drawn_instance_id = win_t.instance_id
	bc.state.current_seat = seat
	bc.state.phase = BattlePhase.Kind.DISCARD
	bc.set("_active_window", null)
	bc.state.wall.set_draw_index(maxi(draw_floor, int(bc.state.wall.draw_index())))
	var ctx: DecisionContext = bc.decision_context_for_seat(seat)
	return ctx != null and ctx.has_kind("TSUMO")


func _submit_tsumo(session: HeadlessRoomSession, seat: int) -> bool:
	var bc: BattleController = session.server._bc
	if bc == null:
		return false
	if not _arrange_tsumo_ready(bc, seat):
		return false
	assert_true(session.server.publish_snapshot())
	var ctx: DecisionContext = bc.decision_context_for_seat(seat)
	assert_not_null(ctx)
	assert_true(ctx.has_kind("TSUMO"))
	var act: Action = Action.tsumo(
		seat,
		session.room_id,
		"550e8400-e29b-41d4-a716-%012d" % (2000 + seat + int(bc.state.hand_seq) * 10),
		str(ctx.decision_id),
		int(bc.state.hand_seq),
		1 + int(bc.state.hand_seq)
	)
	var cr: CommandResult = session.submit_action_for_seat(seat, act)
	return cr != null and cr.status == "ACCEPTED"


func _real_non_renchan_hand(session: HeadlessRoomSession) -> bool:
	var bc: BattleController = session.server._bc
	if bc == null:
		return false
	var dealer: int = int(bc.state.dealer_seat)
	var winner: int = (dealer + 1) % 4
	return _submit_tsumo(session, winner)


func _real_renchan_hand(session: HeadlessRoomSession) -> bool:
	var bc: BattleController = session.server._bc
	if bc == null:
		return false
	return _submit_tsumo(session, int(bc.state.dealer_seat))


## 九种九牌：真实 DECLARE_ABORTIVE_DRAW。
func _arrange_abortive_ready(bc: BattleController, seat: int) -> bool:
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
	var yaochu_ids: Array = [
		TileId.W1, TileId.W9, TileId.T1, TileId.T9, TileId.S1, TileId.S9,
		TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N, TileId.HAKU,
		TileId.HATSU, TileId.CHUN,
	]
	var h := Hand.new()
	for tid in yaochu_ids:
		var t: Tile = _pull_tid(bc, int(tid), used)
		if t == null:
			return false
		if not h.add(t):
			return false
	bc.state.seats[seat].hand = h
	var drawn: Tile = _pull_tid(bc, TileId.W2, used)
	if drawn == null:
		return false
	if not bc.state.seats[seat].hand.add(drawn):
		return false
	bc.state.seats[seat].last_drawn_instance_id = drawn.instance_id
	bc.state.current_seat = seat
	bc.state.phase = BattlePhase.Kind.DISCARD
	bc.state.first_round_active = true
	bc.state.turn_count = 0
	bc.set("_active_window", null)
	bc.state.wall.set_draw_index(maxi(draw_floor, int(bc.state.wall.draw_index())))
	var ctx: DecisionContext = bc.decision_context_for_seat(seat)
	return ctx != null and ctx.has_kind("DECLARE_ABORTIVE_DRAW")


func _submit_abortive(session: HeadlessRoomSession, seat: int) -> bool:
	var bc: BattleController = session.server._bc
	if bc == null:
		return false
	if not _arrange_abortive_ready(bc, seat):
		return false
	assert_true(session.server.publish_snapshot())
	var ctx: DecisionContext = bc.decision_context_for_seat(seat)
	assert_not_null(ctx)
	assert_true(ctx.has_kind("DECLARE_ABORTIVE_DRAW"))
	var act: Action = Action.declare_abortive_draw(
		seat,
		"KYUUSYU_KYUUHAI",
		session.room_id,
		"550e8400-e29b-41d4-a716-%012d" % (3000 + seat + int(bc.state.hand_seq) * 10),
		str(ctx.decision_id),
		int(bc.state.hand_seq),
		1 + int(bc.state.hand_seq)
	)
	var cr: CommandResult = session.submit_action_for_seat(seat, act)
	return cr != null and cr.status == "ACCEPTED"


## 流し满贯：非庄家河全幺九 + 空墙 + DISCARD 后全 PASS → 真实 DRAW 荒牌。
func _submit_nagashi_non_dealer(session: HeadlessRoomSession) -> bool:
	var bc: BattleController = session.server._bc
	if bc == null:
		return false
	var dealer: int = int(bc.state.dealer_seat)
	var winner: int = (dealer + 1) % 4
	var discarder: int = (winner + 1) % 4
	var used: Dictionary = {}
	for s in range(4):
		var seat_obj: Seat = bc.state.seats[s]
		seat_obj.hand = Hand.new()
		seat_obj.melds.restore([], 0)
		seat_obj.last_drawn_instance_id = Tile.INVALID_INSTANCE_ID
		seat_obj.furiten = FuritenState.new()
		bc.state.seats[s].river.restore([])
	bc.state.wall.set_draw_index(0)
	# 胜者河：全幺九（至少 1 张）
	var yaochu_ids: Array = [
		TileId.W1, TileId.W9, TileId.T1, TileId.T9, TileId.S1, TileId.E,
	]
	var river_tiles: Array = []
	for tid in yaochu_ids:
		var rt: Tile = _pull_tid(bc, int(tid), used)
		if rt == null:
			return false
		river_tiles.append(rt)
	if not bc.state.seats[winner].river.restore(river_tiles):
		return false
	# discarder 手牌 14 张可弃（噪声）
	var hand_ids := [
		TileId.W2, TileId.W3, TileId.W4, TileId.W5, TileId.W6, TileId.W7, TileId.W8,
		TileId.T2, TileId.T3, TileId.T4, TileId.T5, TileId.T6, TileId.T7, TileId.T8,
	]
	var h := Hand.new()
	for tid2 in hand_ids:
		var t: Tile = _pull_tid(bc, int(tid2), used)
		if t == null:
			return false
		if not h.add(t):
			return false
	bc.state.seats[discarder].hand = h
	bc.state.seats[discarder].last_drawn_instance_id = (
		h.tiles()[h.tiles().size() - 1] as Tile
	).instance_id
	bc.state.current_seat = discarder
	bc.state.phase = BattlePhase.Kind.DISCARD
	bc.state.first_round_active = false
	bc.set("_active_window", null)
	# 耗尽 live wall：下一次 DRAW 必荒牌
	bc.state.wall.set_draw_index(_live_end(bc.state.wall))
	assert_true(session.server.publish_snapshot())
	var ctx: DecisionContext = bc.decision_context_for_seat(discarder)
	assert_not_null(ctx)
	assert_true(ctx.has_kind("DISCARD"), "须有 DISCARD offer")
	var discard_iid: int = -1
	for o in ctx.allowed_actions:
		if typeof(o) == TYPE_DICTIONARY and str(o.get("kind", "")) == "DISCARD":
			var opts: Array = o.get("payload_options", [])
			if not opts.is_empty():
				discard_iid = int(opts[0].get("tile_instance_id", -1))
			break
	if discard_iid < 0:
		# DecisionContext 可能用不同结构
		var tiles_h: Array = bc.state.seats[discarder].hand.tiles()
		if tiles_h.is_empty():
			return false
		discard_iid = int((tiles_h[0] as Tile).instance_id)
	var act: Action = Action.discard(
		discarder,
		discard_iid,
		session.room_id,
		"550e8400-e29b-41d4-a716-%012d" % (4000 + discarder),
		str(ctx.decision_id),
		int(bc.state.hand_seq),
		1
	)
	var cr: CommandResult = session.submit_action_for_seat(discarder, act)
	if cr == null or cr.status != "ACCEPTED":
		return false
	# 其余席 PASS claim（若有窗）
	var guard := 0
	while guard < 8 and not bool(bc.get("_settled")):
		guard += 1
		var progressed := false
		for s2 in range(4):
			if not session.is_human_seat(s2):
				continue
			var c2: DecisionContext = bc.decision_context_for_seat(s2)
			if c2 == null or not c2.has_kind("PASS"):
				continue
			var pass_act: Action = Action.make_pass(
				s2,
				session.room_id,
				"550e8400-e29b-41d4-a716-%012d" % (4100 + s2 + guard * 10),
				str(c2.decision_id),
				int(bc.state.hand_seq),
				2 + guard
			)
			var crp: CommandResult = session.submit_action_for_seat(s2, pass_act)
			if crp != null and crp.status == "ACCEPTED":
				progressed = true
				break
		if not progressed:
			break
	return bool(bc.get("_settled")) and _count_kind(session, "HAND_SETTLED") >= 1


func _freeze_snapshot(session: HeadlessRoomSession) -> Dictionary:
	var server: LocalLoopbackServer = session.server
	var journals: Array = []
	for s in range(4):
		journals.append(session.event_journal(s).size())
	return {
		"match": session.capture_match_authority_state(),
		"seq": server.current_server_seq(),
		"journals": journals,
		"hash": server.authority_hash_for_test(),
		"bc": server._bc,
		"hand_settled": _count_kind(session, "HAND_SETTLED"),
		"match_settled": _count_kind(session, "MATCH_SETTLED"),
		"has_match": server.has_match_settled(),
		"hand_index": session.match_driver.hand_index,
		"dealer": session.match_driver.dealer_seat,
		"honba": session.match_driver.honba,
		"next_hand_seq": session.match_driver.next_hand_seq,
		"finished": session.match_driver.finished,
	}


func _assert_exact_restore(session: HeadlessRoomSession, fr: Dictionary, tag: String) -> void:
	var server: LocalLoopbackServer = session.server
	assert_eq(server.current_server_seq(), int(fr["seq"]), "%s seq" % tag)
	assert_eq(session.match_driver.hand_index, int(fr["hand_index"]), "%s hand_index" % tag)
	assert_eq(session.match_driver.dealer_seat, int(fr["dealer"]), "%s dealer" % tag)
	assert_eq(session.match_driver.honba, int(fr["honba"]), "%s honba" % tag)
	assert_eq(session.match_driver.next_hand_seq, int(fr["next_hand_seq"]), "%s nhs" % tag)
	assert_eq(session.match_driver.finished, bool(fr["finished"]), "%s finished" % tag)
	assert_eq(server.has_match_settled(), bool(fr["has_match"]), "%s has_match" % tag)
	assert_eq(_count_kind(session, "HAND_SETTLED"), int(fr["hand_settled"]), "%s HAND" % tag)
	assert_eq(_count_kind(session, "MATCH_SETTLED"), int(fr["match_settled"]), "%s MATCH" % tag)
	assert_eq(server.authority_hash_for_test(), str(fr["hash"]), "%s hash" % tag)
	assert_true(server._bc == fr["bc"], "%s BC identity" % tag)
	assert_false(server.has_match_transaction_freeze(), "%s freeze 残留" % tag)
	var journals: Array = fr["journals"]
	for s in range(4):
		assert_eq(session.event_journal(s).size(), int(journals[s]),
			"%s journal seat%d" % [tag, s])


# ---------------------------------------------------------------------------
# 既有 happy path
# ---------------------------------------------------------------------------

func test_bootstrap_match_authority_in_snapshot() -> void:
	var s := _boot("room-snap", PARTS_1H)
	_join_ready_all_humans(s)
	var ma: Dictionary = _last_match_authority(s)
	assert_false(ma.is_empty(), "ROOM_SNAPSHOT 须含 match_authority")
	assert_eq(int(ma.get("hand_index", -1)), 0)
	assert_false(bool(ma.get("finished", true)))
	assert_eq(int(ma.get("next_hand_seq", -1)), int(ma.get("hand_seq", -2)) + 1)


func test_east_four_real_tsumo_unique_match_and_final_snap() -> void:
	var s := _boot("room-e4", PARTS_4H, "EAST", "STANDARD", 11, 0)
	_join_ready_all_humans(s)
	for i in range(4):
		assert_false(s.is_match_completed(), "局 %d 前未终场" % i)
		assert_true(_real_non_renchan_hand(s), "真实非连庄 TSUMO hand %d" % i)
	assert_true(s.is_match_completed())
	assert_eq(_count_kind(s, "HAND_SETTLED"), 4)
	assert_eq(_count_kind(s, "MATCH_SETTLED"), 1)
	var ma: Dictionary = _last_match_authority(s)
	assert_true(bool(ma.get("finished", false)), "终态 SNAP finished=true")
	assert_eq(int(ma.get("hand_index", -1)), 4)
	assert_eq(int(ma.get("round_wind", -1)), TileId.E)
	var ms: Dictionary = _last_match_settled(s)
	assert_false(ms.is_empty())
	var finals: Array = ms.get("final_scores", [])
	assert_eq(finals.size(), 4)
	var cum: Array = ma.get("cumulative_scores", [])
	assert_eq(cum.size(), 4)
	for i2 in range(4):
		assert_eq(int(cum[i2]), int(finals[i2]), "match_authority 分 == MATCH_SETTLED")


func test_hanchan_south_and_finish_real() -> void:
	var s := _boot("room-han", PARTS_4H, "HANCHAN", "STANDARD", 13, 0)
	_join_ready_all_humans(s)
	for i in range(4):
		assert_true(_real_non_renchan_hand(s), "东%d" % i)
	assert_eq(s.match_driver.hand_index, 4)
	assert_eq(int(s.export_match_state().get("round_wind", -1)), TileId.S_WIND)
	assert_false(s.is_match_completed())
	for j in range(4):
		assert_true(_real_non_renchan_hand(s), "南%d" % j)
	assert_true(s.is_match_completed())
	var ma: Dictionary = _last_match_authority(s)
	assert_true(bool(ma.get("finished", false)))
	assert_eq(int(ma.get("round_wind", -1)), TileId.S_WIND)


func test_renchan_dealer_tsumo_keeps_hand_index() -> void:
	var s := _boot("room-ren", PARTS_4H, "EAST", "STANDARD", 17, 0)
	_join_ready_all_humans(s)
	var hi0: int = s.match_driver.hand_index
	assert_true(_real_renchan_hand(s))
	assert_eq(s.match_driver.hand_index, hi0)
	assert_gte(s.match_driver.honba, 1)
	assert_false(s.is_match_completed())
	assert_eq(int(s.server._bc.state.hand_seq), 1, "连庄 hand_seq 递增")


func test_tt_modules_persist_single_path_and_standard_isolated() -> void:
	var s_tt := _boot("room-tt", PARTS_4H, "EAST", "TRASH_TALK", 19, 0)
	_join_ready_all_humans(s_tt)
	assert_true(s_tt.mode_modules.is_trash_talk())
	var inv = s_tt.mode_modules.item_inventory
	var rw = s_tt.mode_modules.reward_window
	assert_not_null(inv)
	assert_not_null(rw)
	var hs0: int = int(s_tt.server._bc.state.hand_seq)
	# 单一确定路径：非连庄（闲家 TSUMO）→ hand_seq 必变
	assert_true(_real_non_renchan_hand(s_tt), "TT 非连庄唯一路径")
	assert_true(inv == s_tt.mode_modules.item_inventory, "item_inventory 同 identity")
	assert_true(rw == s_tt.mode_modules.reward_window, "reward_window 同 identity")
	assert_true(s_tt.mode_modules == s_tt.server.mode_modules)
	assert_eq(int(s_tt.server._bc.state.hand_seq), hs0 + 1, "跨局 hand_seq 真实递增")
	var s_std := _boot("room-std", PARTS_1H, "EAST", "STANDARD", 21, 0)
	assert_null(s_std.mode_modules.item_inventory)
	assert_null(s_std.mode_modules.reward_window)


func test_ai_takeover_survives_next_hand() -> void:
	var s := _boot("room-ai", PARTS_4H, "EAST", "STANDARD", 23, 0)
	_join_ready_all_humans(s)
	s.server.set_seat_ai_control(0, true)
	assert_true(s.server.is_seat_ai_controlled(0))
	assert_true(_real_non_renchan_hand(s))
	assert_true(s.server.is_seat_ai_controlled(0), "跨局 AI 接管保持")


func test_final_reconnect_no_duplicate_hand_match() -> void:
	var s := _boot("room-rc", PARTS_4H, "EAST", "STANDARD", 29, 0)
	_join_ready_all_humans(s)
	for i in range(4):
		assert_true(_real_non_renchan_hand(s), "hand %d" % i)
	assert_true(s.is_match_completed())
	assert_eq(_count_kind(s, "HAND_SETTLED"), 4)
	assert_eq(_count_kind(s, "MATCH_SETTLED"), 1)
	var seq_b: int = s.current_server_seq()
	assert_true(s.server._emit_settled_if_needed())
	assert_eq(s.current_server_seq(), seq_b)
	assert_eq(_count_kind(s, "HAND_SETTLED"), 4)
	assert_eq(_count_kind(s, "MATCH_SETTLED"), 1)
	var prep: Dictionary = s.prepare_reconnect_delivery(0)
	assert_true(bool(prep.get("ok", false)))
	var ma: Dictionary = _last_match_authority(s)
	assert_true(bool(ma.get("finished", false)))


# ---------------------------------------------------------------------------
# R4 P1/P2 seams
# ---------------------------------------------------------------------------

func test_next_hand_start_snapshot_fail_precise_rollback() -> void:
	var s := _boot("room-rb", PARTS_4H, "EAST", "STANDARD", 41, 0)
	_join_ready_all_humans(s)
	var server: LocalLoopbackServer = s.server
	var winner: int = (int(server._bc.state.dealer_seat) + 1) % 4
	assert_true(_arrange_tsumo_ready(server._bc, winner))
	var fr: Dictionary = _freeze_snapshot(s)
	# 专用 seam：仅 start_next_hand 首 SNAP
	server.fail_next_hand_start_snapshot_for_test()
	assert_eq(server.fail_next_hand_start_snapshot_hit_count, 0)
	var ctx: DecisionContext = server._bc.decision_context_for_seat(winner)
	var act: Action = Action.tsumo(
		winner, s.room_id,
		"550e8400-e29b-41d4-a716-000000009901",
		str(ctx.decision_id), int(server._bc.state.hand_seq), 9
	)
	var cr: CommandResult = s.submit_action_for_seat(winner, act)
	assert_not_null(cr)
	assert_eq(cr.status, "REJECTED", "下一局首 SNAP 失败须整事务 REJECTED")
	assert_gte(server.fail_next_hand_start_snapshot_hit_count, 1,
		"须命中 start_next_hand 专用 seam")
	_assert_exact_restore(s, fr, "next_hand_snap")


func test_start_hand_failed_no_match_half_commit() -> void:
	var s := _boot("room-shf", PARTS_4H, "EAST", "STANDARD", 43, 0)
	_join_ready_all_humans(s)
	var server: LocalLoopbackServer = s.server
	var winner: int = (int(server._bc.state.dealer_seat) + 1) % 4
	assert_true(_arrange_tsumo_ready(server._bc, winner))
	var fr: Dictionary = _freeze_snapshot(s)
	# factory 返回 null → START_HAND_FAILED（finished 必须 false）
	s.match_driver.bc_factory = func(
		_hs: int, _d: int, _uh: bool, _rw: int, _hseq: int
	) -> BattleController:
		return null
	var ctx: DecisionContext = server._bc.decision_context_for_seat(winner)
	var act: Action = Action.tsumo(
		winner, s.room_id,
		"550e8400-e29b-41d4-a716-000000009911",
		str(ctx.decision_id), int(server._bc.state.hand_seq), 11
	)
	var cr: CommandResult = s.submit_action_for_seat(winner, act)
	assert_not_null(cr)
	assert_eq(cr.status, "REJECTED", "START_HAND_FAILED 须整事务失败")
	assert_eq(_count_kind(s, "MATCH_SETTLED"), 0, "不得伪装终场 MATCH")
	assert_false(server.has_match_settled())
	_assert_exact_restore(s, fr, "start_hand_failed")


func test_no_driver_error_not_match_end() -> void:
	var s := _boot("room-nd", PARTS_4H, "EAST", "STANDARD", 44, 0)
	_join_ready_all_humans(s)
	var server: LocalLoopbackServer = s.server
	var winner: int = (int(server._bc.state.dealer_seat) + 1) % 4
	assert_true(_arrange_tsumo_ready(server._bc, winner))
	var fr: Dictionary = _freeze_snapshot(s)
	var saved_driver = s.match_driver
	s.match_driver = null
	var ctx: DecisionContext = server._bc.decision_context_for_seat(winner)
	var act: Action = Action.tsumo(
		winner, s.room_id,
		"550e8400-e29b-41d4-a716-000000009912",
		str(ctx.decision_id), int(server._bc.state.hand_seq), 12
	)
	var cr: CommandResult = s.submit_action_for_seat(winner, act)
	s.match_driver = saved_driver
	assert_not_null(cr)
	assert_eq(cr.status, "REJECTED", "NO_DRIVER 须失败")
	assert_eq(_count_kind(s, "MATCH_SETTLED"), 0)
	assert_false(server.has_match_settled())
	# match_driver 已恢复引用；状态应与 freeze 一致（callback 失败路径）
	assert_eq(s.match_driver.hand_index, int(fr["hand_index"]))
	assert_eq(server.current_server_seq(), int(fr["seq"]))
	assert_eq(_count_kind(s, "HAND_SETTLED"), int(fr["hand_settled"]))
	assert_false(server.has_match_transaction_freeze())


func test_fail_after_match_settled_restores_match_flag() -> void:
	var s := _boot("room-fam", PARTS_4H, "EAST", "STANDARD", 47, 0)
	_join_ready_all_humans(s)
	# 前 3 局正常非连庄
	for i in range(3):
		assert_true(_real_non_renchan_hand(s), "pre hand %d" % i)
	assert_eq(_count_kind(s, "HAND_SETTLED"), 3)
	assert_eq(_count_kind(s, "MATCH_SETTLED"), 0)
	assert_false(s.server.has_match_settled())
	var server: LocalLoopbackServer = s.server
	var winner: int = (int(server._bc.state.dealer_seat) + 1) % 4
	assert_true(_arrange_tsumo_ready(server._bc, winner))
	var fr: Dictionary = _freeze_snapshot(s)
	server.fail_after_match_settled_for_test()
	assert_eq(server.fail_after_match_settled_hit_count, 0)
	var ctx: DecisionContext = server._bc.decision_context_for_seat(winner)
	var act: Action = Action.tsumo(
		winner, s.room_id,
		"550e8400-e29b-41d4-a716-000000009920",
		str(ctx.decision_id), int(server._bc.state.hand_seq), 20
	)
	var cr: CommandResult = s.submit_action_for_seat(winner, act)
	assert_not_null(cr)
	assert_eq(cr.status, "REJECTED", "MATCH 后失败须整事务 REJECTED")
	assert_gte(server.fail_after_match_settled_hit_count, 1, "须命中 MATCH 后 seam")
	assert_false(server.has_match_settled(), "rollback 后 has_match_settled=false")
	assert_eq(_count_kind(s, "MATCH_SETTLED"), 0, "journal 无 MATCH")
	_assert_exact_restore(s, fr, "fail_after_match")


func test_begin_freeze_requires_valid_ars() -> void:
	var s := _boot("room-ars", PARTS_1H, "EAST", "STANDARD", 53, 0)
	_join_ready_all_humans(s)
	var server: LocalLoopbackServer = s.server
	# BC 存在但 state 无效 → capture 失败 → begin 须 false 且零残留
	var real_bc: BattleController = server._bc
	var broken := BattleController.new(1, 0, false, TileId.E, 0)
	broken.state = null
	server._bc = broken
	assert_false(server.begin_match_transaction_freeze(), "无有效 ARS 须 begin=false")
	assert_false(server.has_match_transaction_freeze(), "失败不得残留 freeze")
	server._bc = real_bc
	assert_true(server.begin_match_transaction_freeze(), "合法 BC 须 begin=true")
	assert_true(server.has_match_transaction_freeze())
	server.clear_match_transaction_freeze()
	assert_false(server.has_match_transaction_freeze())


func test_rejected_action_clears_freeze() -> void:
	var s := _boot("room-fz", PARTS_1H, "EAST", "STANDARD", 43, 0)
	_join_ready_all_humans(s)
	var server: LocalLoopbackServer = s.server
	var bad: Action = Action.from_dict({
		"protocol_version": 1,
		"command_id": "550e8400-e29b-41d4-a716-000000009902",
		"room_id": s.room_id,
		"seat": 0,
		"hand_seq": 0,
		"decision_id": "00000000-0000-4000-8000-000000000099",
		"kind": "PASS",
		"payload": {},
		"client_seq": 1,
	})
	var cr: CommandResult = s.submit_action_for_seat(0, bad)
	assert_not_null(cr)
	assert_eq(cr.status, "REJECTED")
	assert_false(server.has_match_transaction_freeze())


# ---------------------------------------------------------------------------
# R4 真实规则：途中流局 / 流し / RW 延迟
# ---------------------------------------------------------------------------

func test_abortive_draw_renchan_real_action() -> void:
	var s := _boot("room-ab", PARTS_4H, "EAST", "STANDARD", 59, 0)
	_join_ready_all_humans(s)
	var dealer0: int = s.match_driver.dealer_seat
	var hi0: int = s.match_driver.hand_index
	var honba0: int = s.match_driver.honba
	var scores0: Array = s.match_driver.cumulative_scores.duplicate()
	assert_true(_submit_abortive(s, dealer0), "九种九牌须 ACCEPTED")
	var hs: Dictionary = _last_hand_settled(s)
	assert_eq(str(hs.get("outcome", "")), "ABORTIVE_DRAW")
	assert_true(bool(hs.get("renchan", false)), "途中流局连庄")
	assert_eq(s.match_driver.hand_index, hi0, "连庄 hand_index 不变")
	assert_eq(s.match_driver.dealer_seat, dealer0)
	assert_eq(s.match_driver.honba, honba0 + 1)
	assert_false(s.is_match_completed())
	# 零罚符
	for i in range(4):
		assert_eq(int(s.match_driver.cumulative_scores[i]), int(scores0[i]),
			"途中流局零罚符 seat%d" % i)
	assert_eq(_count_kind(s, "HAND_SETTLED"), 1)
	assert_eq(_count_kind(s, "MATCH_SETTLED"), 0)
	# 下一局 hand_seq 递增
	assert_eq(int(s.server._bc.state.hand_seq), 1)


func test_nagashi_mangan_non_renchan_score_advance() -> void:
	var s := _boot("room-nm", PARTS_4H, "EAST", "STANDARD", 61, 0)
	_join_ready_all_humans(s)
	var dealer0: int = s.match_driver.dealer_seat
	var hi0: int = s.match_driver.hand_index
	var scores0: Array = []
	for i in range(4):
		scores0.append(int(s.match_driver.cumulative_scores[i]))
	assert_true(_submit_nagashi_non_dealer(s), "流し须经真实 Action 结算")
	var hs: Dictionary = _last_hand_settled(s)
	assert_eq(str(hs.get("outcome", "")), "NAGASHI_MANGAN",
		"outcome 须 NAGASHI_MANGAN 不得伪装 EXHAUSTIVE")
	assert_false(bool(hs.get("renchan", true)), "闲家流し非连庄")
	assert_eq(s.match_driver.hand_index, hi0 + 1)
	assert_eq(s.match_driver.dealer_seat, (dealer0 + 1) % 4)
	assert_eq(s.match_driver.honba, 0)
	# 计分须推进（非全零 delta）
	var any_delta := false
	for i2 in range(4):
		if int(s.match_driver.cumulative_scores[i2]) != int(scores0[i2]):
			any_delta = true
			break
	assert_true(any_delta, "流し满贯须改分")
	assert_eq(_count_kind(s, "MATCH_SETTLED"), 0)


## outbox wire dict 的业务 kind 序列（跳过 ERROR/COMMAND_RESULT）。
func _outbox_event_kinds(out: Array) -> Array:
	var kinds: Array = []
	for item in out:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var k: String = str(item.get("kind", ""))
		if k.is_empty() or k == "ERROR" or k == "COMMAND_RESULT":
			continue
		kinds.append(k)
	return kinds


## 断言 outbox 中 expected kinds 按相对顺序出现（可夹杂其它事件）。
func _assert_outbox_kind_order(out: Array, expected: Array, tag: String) -> void:
	var kinds: Array = _outbox_event_kinds(out)
	var idx := 0
	for want in expected:
		var found := -1
		for i in range(idx, kinds.size()):
			if str(kinds[i]) == str(want):
				found = i
				break
		assert_gt(found, -1, "%s 缺少 %s；outbox kinds=%s" % [tag, want, kinds])
		idx = found + 1


func _assert_outbox_seq_monotonic(out: Array, tag: String) -> void:
	var last := -1
	for item in out:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		if not item.has("server_seq"):
			continue
		var seq: int = int(item.get("server_seq", -1))
		assert_gt(seq, last, "%s server_seq 须严格单调 last=%d got=%d" % [tag, last, seq])
		last = seq


func _bind_all_human_conns(w: HeadlessWorker, s: HeadlessRoomSession) -> Array:
	var cids: Array = []
	for seat in range(4):
		if not s.is_human_seat(seat):
			continue
		var cid: int = seat + 1
		w.inject_bound_session_for_test(cid, s, seat, "sess-%d" % seat)
		cids.append(cid)
	return cids


func _prepare_conn_delta_flush(w: HeadlessWorker, cids: Array, after_seq: int) -> void:
	for cid in cids:
		w.set_conn_last_seq_for_test(int(cid), after_seq)
		w.clear_outbox_for_test(int(cid))


func _worker_target_for_grace(boot_ms: int, grace_ms: int) -> int:
	return int(boot_ms) + (int(grace_ms) - LocalLoopbackServer.REWARD_CLOCK_BASE_MS) + 1


## #376 R5/R6：必须经 HeadlessWorker.poll 推进权威时钟，禁止直调 advance_reward_time。
## 每个有效绑定连接 outbox 须收到 SETTLED → HAND → 下一局 SNAP。
func test_worker_poll_tt_deferred_hand_then_next() -> void:
	var w := HeadlessWorker.new()
	add_child_autofree(w)
	assert_true(w.configure(
		"0123456789abcdef0123456789abcdef", "127.0.0.1", 0, -1, ""
	))
	assert_eq(w.start_listen(), OK)
	var boot_ms := 1000
	w.set_clock_ms_for_test(boot_ms)
	var s := _boot("room-rw-poll", PARTS_4H, "EAST", "TRASH_TALK", 67, boot_ms)
	_join_ready_all_humans(s)
	var cids: Array = _bind_all_human_conns(w, s)
	assert_eq(cids.size(), 4)
	var rw: RewardWindowModule = s.mode_modules.reward_window
	assert_not_null(rw)
	assert_true(bool(rw.ingest_utterance({
		"seat": 0,
		"utterance_id": "pend_ab_poll",
		"text": "流了",
		"language": "zh",
		"ptt_end_server_seq": maxi(s.server.current_server_seq(), 1),
		"terminal": false,
	}).get("accepted", false)))
	var dealer0: int = s.match_driver.dealer_seat
	var hs0: int = int(s.server._bc.state.hand_seq)
	assert_true(_submit_abortive(s, dealer0), "TT 途中流局须 ACCEPTED")
	assert_eq(_count_kind(s, "HAND_SETTLED"), 0, "grace 前不得 HAND")
	assert_eq(rw.phase, RewardWindowModule.PHASE_CLOSING)
	assert_true(bool(s.server.get("_reward_hand_settled_deferred")))
	var seq_before: int = s.current_server_seq()
	_prepare_conn_delta_flush(w, cids, seq_before)
	var worker_target: int = _worker_target_for_grace(boot_ms, int(rw._grace_deadline_ms))
	assert_gt(worker_target, boot_ms)
	w.set_clock_ms_for_test(worker_target)
	w.poll()
	assert_eq(_count_kind(s, "REWARD_WINDOW_SETTLED"), 1)
	assert_eq(_count_kind(s, "HAND_SETTLED"), 1)
	assert_eq(_count_kind(s, "MATCH_SETTLED"), 0)
	assert_eq(int(s.server._bc.state.hand_seq), hs0 + 1, "poll 后须开下一局")
	# 每个绑定连接 outbox 精确断言（不能只查 journal）
	for cid in cids:
		var out: Array = w.test_outbox(int(cid))
		assert_gt(out.size(), 0, "cid%d 须有增量 outbox" % int(cid))
		_assert_outbox_kind_order(out, [
			"REWARD_WINDOW_SETTLED", "HAND_SETTLED", "ROOM_SNAPSHOT",
		], "cid%d deferred" % int(cid))
		_assert_outbox_seq_monotonic(out, "cid%d deferred" % int(cid))
	# 相同/倒退时钟零副作用
	var j1: int = s.event_journal(0).size()
	var seq1: int = s.current_server_seq()
	_prepare_conn_delta_flush(w, cids, seq1)
	w.set_clock_ms_for_test(worker_target)
	w.poll()
	assert_eq(s.event_journal(0).size(), j1)
	assert_eq(s.current_server_seq(), seq1)
	for cid2 in cids:
		assert_eq(w.test_outbox(int(cid2)).size(), 0, "相同时钟 outbox 须空")
	w.set_clock_ms_for_test(worker_target - 500)
	w.poll()
	assert_eq(s.event_journal(0).size(), j1)
	assert_eq(s.current_server_seq(), seq1)
	assert_false(s.is_room_failed())


## #376 R6：Worker lifecycle 终场 — 东四末局 TT deferred 非连庄 → poll →
## outbox SETTLED→HAND→MATCH→terminal SNAP；CP complete 恰一次；cleanup。
func test_worker_poll_tt_deferred_match_end_complete_cleanup() -> void:
	var w := HeadlessWorker.new()
	add_child_autofree(w)
	assert_true(w.configure(
		"0123456789abcdef0123456789abcdef", "127.0.0.1", 0, -1, ""
	))
	assert_eq(w.start_listen(), OK)
	# dummy CP：只验证 enqueue 队列，不声称 HTTP e2e
	assert_true(w.configure_control_plane_registration(
		"http://127.0.0.1:1",
		"reg-token-r6-dummy",
		"worker-r6-match-end",
		"ws://127.0.0.1:9000",
		"ws://127.0.0.1:9001",
		2,
		500
	))
	var client: WorkerControlPlaneClient = w.get_control_plane_client()
	assert_not_null(client)
	assert_true(client.is_started())
	# 禁止 poll 内真发 HTTP：renew/complete 截止推远
	client.clock_now_ms = 1000
	client._next_renew_ms = 999999999
	client._next_complete_ms = 999999999

	var boot_ms := 1000
	w.set_clock_ms_for_test(boot_ms)
	var room_id := "room-rw-match-end"
	var s := _boot(room_id, PARTS_4H, "EAST", "TRASH_TALK", 83, boot_ms)
	_join_ready_all_humans(s)
	var cids: Array = _bind_all_human_conns(w, s)
	# 前 3 局：真实非连庄 TSUMO（非 deferred）
	for i in range(3):
		assert_true(_real_non_renchan_hand(s), "pre hand %d" % i)
		assert_false(s.is_match_completed())
	assert_eq(s.match_driver.hand_index, 3)
	assert_eq(_count_kind(s, "MATCH_SETTLED"), 0)
	# 末局：pending utterance + 真实流し非连庄 → CLOSING/deferred
	var rw: RewardWindowModule = s.mode_modules.reward_window
	assert_not_null(rw)
	assert_true(bool(rw.ingest_utterance({
		"seat": 0,
		"utterance_id": "pend_match_end",
		"text": "终局流し",
		"language": "zh",
		"ptt_end_server_seq": maxi(s.server.current_server_seq(), 1),
		"terminal": false,
	}).get("accepted", false)))
	assert_true(_submit_nagashi_non_dealer(s), "末局流し须真实 Action")
	assert_eq(_count_kind(s, "HAND_SETTLED"), 3, "grace 前 HAND 仍为前 3 局")
	assert_eq(_count_kind(s, "MATCH_SETTLED"), 0)
	assert_eq(rw.phase, RewardWindowModule.PHASE_CLOSING)
	assert_true(bool(s.server.get("_reward_hand_settled_deferred")))
	assert_false(s.is_match_completed())

	var seq_before: int = s.current_server_seq()
	_prepare_conn_delta_flush(w, cids, seq_before)
	var worker_target: int = _worker_target_for_grace(boot_ms, int(rw._grace_deadline_ms))
	w.set_clock_ms_for_test(worker_target)
	w.poll()

	assert_true(s.is_match_completed(), "deferred 终场后须 match completed")
	assert_eq(_count_kind(s, "MATCH_SETTLED"), 1, "MATCH 恰好一次")
	assert_eq(_count_kind(s, "HAND_SETTLED"), 4)
	assert_eq(client.complete_queue_size_for_test(), 1, "CP complete 恰入队一次")
	assert_eq(client.fail_queue_size_for_test(), 0, "fail queue 须空")
	assert_true(bool(s.get_meta("cp_complete_cleanup_pending", false)),
		"session 须标 cleanup pending")
	assert_true(bool(s.get_meta("cp_complete_enqueued", false)))
	assert_eq(w.room_count(), 0, "completed 不计活跃容量")
	assert_not_null(w.get_room(room_id), "cleanup 前 get_room 仍在")
	assert_false(w.is_room_failed_terminal(room_id), "不得误标 failed tombstone")

	# 连接 outbox：SETTLED → HAND → MATCH → terminal SNAP
	for cid in cids:
		var out: Array = w.test_outbox(int(cid))
		assert_gt(out.size(), 0, "cid%d 终场 outbox 非空" % int(cid))
		_assert_outbox_kind_order(out, [
			"REWARD_WINDOW_SETTLED",
			"HAND_SETTLED",
			"MATCH_SETTLED",
			"ROOM_SNAPSHOT",
		], "cid%d match-end" % int(cid))
		_assert_outbox_seq_monotonic(out, "cid%d match-end" % int(cid))
		# terminal SNAP match_authority
		var saw_fin_snap := false
		for item in out:
			if typeof(item) != TYPE_DICTIONARY:
				continue
			if str(item.get("kind", "")) != "ROOM_SNAPSHOT":
				continue
			var payload: Dictionary = item.get("payload", {})
			if typeof(payload) != TYPE_DICTIONARY:
				continue
			for m in payload.get("modules", []):
				if typeof(m) != TYPE_DICTIONARY:
					continue
				if str(m.get("module_key", "")) != "match_authority":
					continue
				var pl: Dictionary = m.get("payload", {})
				if bool(pl.get("finished", false)):
					saw_fin_snap = true
					assert_eq(int(pl.get("hand_index", -1)), 4)
					var cum: Array = pl.get("cumulative_scores", [])
					var ms: Dictionary = _last_match_settled(s)
					var finals: Array = ms.get("final_scores", [])
					assert_eq(cum.size(), 4)
					assert_eq(finals.size(), 4)
					for si in range(4):
						assert_eq(int(cum[si]), int(finals[si]),
							"match_authority 分对齐 MATCH_SETTLED seat%d" % si)
		assert_true(saw_fin_snap, "cid%d 须有 finished match_authority SNAP" % int(cid))

	# 下一 poll：cleanup 移除房间；complete 不重复入队
	w.poll()
	assert_null(w.get_room(room_id), "cleanup 后 get_room null")
	assert_eq(w.room_count(), 0)
	assert_eq(client.complete_queue_size_for_test(), 1, "complete 不得重复入队")
	assert_eq(client.fail_queue_size_for_test(), 0)
	assert_false(w.is_room_failed_terminal(room_id))


func test_worker_poll_reward_tick_fail_room_failed() -> void:
	var w := HeadlessWorker.new()
	add_child_autofree(w)
	assert_true(w.configure(
		"0123456789abcdef0123456789abcdef", "127.0.0.1", 0, -1, ""
	))
	assert_eq(w.start_listen(), OK)
	var boot_ms := 2000
	w.set_clock_ms_for_test(boot_ms)
	var s := _boot("room-tick-fail", PARTS_4H, "EAST", "TRASH_TALK", 71, boot_ms)
	_join_ready_all_humans(s)
	w.inject_bound_session_for_test(1, s, 0, "sess-0")
	var rw: RewardWindowModule = s.mode_modules.reward_window
	assert_true(bool(rw.ingest_utterance({
		"seat": 0, "utterance_id": "pend_fail", "text": "流",
		"language": "zh",
		"ptt_end_server_seq": maxi(s.server.current_server_seq(), 1),
		"terminal": false,
	}).get("accepted", false)))
	assert_true(_submit_abortive(s, s.match_driver.dealer_seat))
	assert_true(bool(s.server.get("_reward_hand_settled_deferred")))
	# 破坏 ARS：tick 路径 advance 失败
	s.server._bc.state = null
	var grace: int = int(rw._grace_deadline_ms)
	var worker_target: int = boot_ms + (grace - LocalLoopbackServer.REWARD_CLOCK_BASE_MS) + 1
	w.set_clock_ms_for_test(worker_target)
	w.poll()
	assert_true(s.is_room_failed(), "tick 失败须 ROOM_FAILED")
	assert_eq(s.fail_code(), "ROOM_FAILED")
	var out: Array = w.test_outbox(1)
	var saw_err := false
	for item in out:
		if typeof(item) == TYPE_DICTIONARY and str(item.get("code", "")) == "ROOM_FAILED":
			saw_err = true
			break
	assert_true(saw_err, "连接须收到 ROOM_FAILED")


func test_headless_match_authority_invalid_owner_fails_snap_no_fallback() -> void:
	var s := _boot("room-ma-bad", PARTS_4H, "EAST", "STANDARD", 73, 0)
	_join_ready_all_humans(s)
	var server: LocalLoopbackServer = s.server
	var seq0: int = server.current_server_seq()
	var j0: int = s.event_journal(0).size()
	var hash0: String = server.authority_hash_for_test()
	# 污染 owner export：非 EAST/HANCHAN → 禁 fallback BC，SNAP 失败零推进
	s.match_driver.total_hands = 7
	assert_false(server.publish_snapshot(), "非法 owner export 须 SNAP 失败")
	assert_eq(server.current_server_seq(), seq0)
	assert_eq(s.event_journal(0).size(), j0)
	assert_eq(server.authority_hash_for_test(), hash0)
	# 恢复合法 total 后 SNAP 成功且恰有 match_authority
	s.match_driver.total_hands = 4
	assert_true(server.publish_snapshot())
	assert_eq(server.current_server_seq(), seq0 + 1)
	var ma: Dictionary = _last_match_authority(s)
	assert_false(ma.is_empty())
	assert_eq(int(ma.get("total_hands", -1)), 4)


## Action 事务内 match_authority 空 payload（无 BC fallback）须整笔精确回滚。
func test_action_fails_when_match_authority_export_empty() -> void:
	var s := _boot("room-ma-act", PARTS_4H, "EAST", "STANDARD", 77, 0)
	_join_ready_all_humans(s)
	var server: LocalLoopbackServer = s.server
	var winner: int = (int(server._bc.state.dealer_seat) + 1) % 4
	assert_true(_arrange_tsumo_ready(server._bc, winner))
	var fr: Dictionary = _freeze_snapshot(s)
	server.fail_match_authority_payload_for_test()
	var ctx: DecisionContext = server._bc.decision_context_for_seat(winner)
	var act: Action = Action.tsumo(
		winner, s.room_id,
		"550e8400-e29b-41d4-a716-000000009931",
		str(ctx.decision_id), int(server._bc.state.hand_seq), 31
	)
	var cr: CommandResult = s.submit_action_for_seat(winner, act)
	assert_not_null(cr)
	assert_eq(cr.status, "REJECTED", "match_authority 失败须 REJECTED")
	assert_gte(server.fail_match_authority_payload_hit_count, 1, "须命中空 payload seam")
	_assert_exact_restore(s, fr, "ma_act_rollback")


func test_headless_match_authority_null_driver_fails_snap() -> void:
	var s := _boot("room-ma-null", PARTS_1H, "EAST", "STANDARD", 74, 0)
	_join_ready_all_humans(s)
	var server: LocalLoopbackServer = s.server
	var seq0: int = server.current_server_seq()
	var saved = s.match_driver
	s.match_driver = null
	assert_false(server.publish_snapshot(), "无 owner export 须 SNAP 失败")
	assert_eq(server.current_server_seq(), seq0, "失败不得推进 seq")
	s.match_driver = saved
	assert_true(server.publish_snapshot())
	var ma: Dictionary = _last_match_authority(s)
	assert_false(ma.is_empty(), "恢复后须有 match_authority")


func test_headless_snap_always_has_single_match_authority() -> void:
	var s := _boot("room-ma-one", PARTS_4H, "EAST", "STANDARD", 75, 0)
	_join_ready_all_humans(s)
	assert_true(_real_non_renchan_hand(s))
	var j: Array = s.event_journal(0)
	var snap_n := 0
	for e in j:
		if not (e is NetworkedEvent) or (e as NetworkedEvent).kind != "ROOM_SNAPSHOT":
			continue
		snap_n += 1
		var n_ma := 0
		for m in (e as NetworkedEvent).payload.get("modules", []):
			if typeof(m) == TYPE_DICTIONARY \
					and str(m.get("module_key", "")) == "match_authority":
				n_ma += 1
				assert_eq(int(m.get("schema_version", -1)), 1)
		assert_eq(n_ma, 1, "每个 committed SNAP 恰有一个 match_authority@1")
	assert_gt(snap_n, 0)


func test_nbc_reconnect_applies_match_authority() -> void:
	var s := _boot("room-ma-nbc", PARTS_4H, "EAST", "STANDARD", 76, 0)
	_join_ready_all_humans(s)
	assert_true(_real_non_renchan_hand(s))
	var prep: Dictionary = s.prepare_reconnect_delivery(0)
	assert_true(bool(prep.get("ok", false)), "重连交付须成功")
	# 重连 publish 后 journal 含 committed SNAP；NBC 真实 ingest
	var events: Array = s.event_journal(0)
	assert_gt(events.size(), 0)
	var nbc := NetworkedBattleController.new(s.room_id, 0)
	nbc.configure_snapshot_registry_for_mode("STANDARD")
	var applied_ma := false
	var last_hi := -1
	for raw in events:
		if not (raw is NetworkedEvent):
			continue
		var ne: NetworkedEvent = raw as NetworkedEvent
		assert_true(nbc.ingest_networked_event(ne), "NBC 须接受 journal 事件 kind=%s" % ne.kind)
		if ne.kind != "ROOM_SNAPSHOT":
			continue
		for m in ne.payload.get("modules", []):
			if typeof(m) == TYPE_DICTIONARY \
					and str(m.get("module_key", "")) == "match_authority":
				applied_ma = true
				last_hi = int((m.get("payload", {}) as Dictionary).get("hand_index", -1))
	assert_true(applied_ma, "重连 journal 须含 match_authority")
	assert_eq(last_hi, s.match_driver.hand_index)


func test_tombstone_action_and_ptt_room_failed() -> void:
	var w := HeadlessWorker.new()
	add_child_autofree(w)
	assert_true(w.configure(
		"0123456789abcdef0123456789abcdef", "127.0.0.1", 0, -1, ""
	))
	assert_eq(w.start_listen(), OK)
	w.set_clock_ms_for_test(1000)
	var s := _boot("room-tm", PARTS_1H, "EAST", "STANDARD", 7, 1000)
	w.inject_bound_session_for_test(1, s, 0, "sess-0")
	w.set_clock_ms_for_test(1000 + 30000)
	w._tick_ready_timeouts()
	assert_true(w.is_room_failed_terminal("room-tm"))
	w._cleanup_completed_rooms()
	w.handle_dict_for_test(1, {
		"protocol_version": 1,
		"command_id": "550e8400-e29b-41d4-a716-000000009903",
		"room_id": "room-tm",
		"seat": 0,
		"hand_seq": 0,
		"decision_id": "00000000-0000-4000-8000-000000000088",
		"kind": "PASS",
		"payload": {},
		"client_seq": 1,
	})
	var out: Array = w.test_outbox(1)
	assert_gt(out.size(), 0)
	var last: Dictionary = out[out.size() - 1]
	assert_eq(str(last.get("code", "")), "ROOM_FAILED")
	var ptt: Dictionary = w.allocate_ptt_end_authority("room-tm", 0, "sess-0", "utt-1")
	assert_false(bool(ptt.get("ok", true)))
	assert_eq(str(ptt.get("code", "")), "ROOM_FAILED")
	assert_eq(w.room_count(), 0)
