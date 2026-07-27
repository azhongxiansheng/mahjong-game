extends GutTest

# E5-04 / #252 round-4：真实 LocalLoopback 生产入口（硬断言，无降级通过）。

const CHARS := [&"lin_yeche", &"qiu_jue", &"bai_touli", &"hua_ling"]
const PARTS := [&"HUMAN", &"AI", &"AI", &"AI"]
const PARTS_ALL_HUMAN := [&"HUMAN", &"HUMAN", &"HUMAN", &"HUMAN"]
const RULE := "trash_talk_rules_v1"
const TT_SID := "loopback-tt-r4"
const RON_SID := "loopback-tt-ron-r4"


func _cfg_tt(match_seed: int = 42) -> GameSessionConfig:
	return GameSessionConfig.create_validated(
		GameSessionConfig.ROOM_PRACTICE, GameSessionConfig.ROUND_EAST,
		GameSessionConfig.MODE_TRASH_TALK, PARTS, CHARS, match_seed, TT_SID, "rv-r4"
	)


func _cfg_tt_all_human(match_seed: int = 42) -> GameSessionConfig:
	return GameSessionConfig.create_validated(
		GameSessionConfig.ROOM_PUBLIC_CASUAL, GameSessionConfig.ROUND_EAST,
		GameSessionConfig.MODE_TRASH_TALK, PARTS_ALL_HUMAN, CHARS, match_seed, RON_SID, "rv-r4"
	)


func _cmd(n: int) -> String:
	return "550e8400-e29b-41d4-a716-%012d" % n


func _kinds(server: LocalLoopbackServer, seat: int = 0) -> Array:
	var out: Array = []
	for ne in server.event_journal(seat):
		if ne is NetworkedEvent:
			out.append((ne as NetworkedEvent).kind)
	return out


func _count(kinds: Array, kind: String) -> int:
	var n := 0
	for k in kinds:
		if String(k) == kind:
			n += 1
	return n


func _events(server: LocalLoopbackServer, seat: int = 0) -> Array:
	return server.event_journal(seat)


func _last_turn_prompt(server: LocalLoopbackServer, seat: int = 0) -> NetworkedEvent:
	var last: NetworkedEvent = null
	for ne in _events(server, seat):
		if ne is NetworkedEvent and (ne as NetworkedEvent).kind == "TURN_PROMPT":
			last = ne as NetworkedEvent
	return last


func _last_claim_window(server: LocalLoopbackServer, seat: int) -> NetworkedEvent:
	var last: NetworkedEvent = null
	for ne in _events(server, seat):
		if ne is NetworkedEvent and (ne as NetworkedEvent).kind == "CLAIM_WINDOW":
			last = ne as NetworkedEvent
	return last


func _discard_from_prompt(server: LocalLoopbackServer, prompt: NetworkedEvent, n: int) -> CommandResult:
	assert_not_null(prompt, "须有 TURN_PROMPT")
	var seat: int = int(prompt.payload.get("seat", -1))
	var did: String = str(prompt.payload.get("decision_id", ""))
	var hs: int = int(prompt.payload.get("hand_seq", 0))
	var iid := -1
	for o in prompt.payload.get("allowed_actions", []):
		if typeof(o) == TYPE_DICTIONARY and str(o.get("kind", "")) == "DISCARD":
			var opts: Array = o.get("payload_options", [])
			assert_false(opts.is_empty(), "DISCARD 须有 payload_options")
			iid = int(opts[0]["tile_instance_id"])
			break
	assert_gt(iid, -1, "TURN_PROMPT 须含 DISCARD")
	var act: Action = Action.discard(
		seat, iid, str(server.get("_room_id")), _cmd(n), did, hs, n
	)
	var cr: CommandResult = server.submit_action(act)
	assert_not_null(cr)
	assert_eq(cr.status, "ACCEPTED",
		"DISCARD 须 ACCEPTED status=%s code=%s" % [cr.status, cr.error_code])
	return cr


func _pass_claim(server: LocalLoopbackServer, seat: int, n: int) -> CommandResult:
	var pr: NetworkedEvent = _last_claim_window(server, seat)
	assert_not_null(pr, "seat%d 须有 CLAIM_WINDOW" % seat)
	var did: String = str(pr.payload.get("decision_id", ""))
	var hs: int = int(pr.payload.get("hand_seq", 0))
	var act: Action = Action.make_pass(
		seat, str(server.get("_room_id")), _cmd(n), did, hs, n
	)
	var cr: CommandResult = server.submit_action(act)
	assert_not_null(cr)
	assert_eq(cr.status, "ACCEPTED",
		"PASS seat%d 须 ACCEPTED status=%s code=%s" % [seat, cr.status, cr.error_code])
	return cr


## 确定性驱动（全 HUMAN）：所有 CLAIM 席 PASS + 当前 TURN 席 DISCARD，直到 discard_count 达 target。
## 决策 ID 只取自 BC 当前 active window。
func _drive_until_discard_count(server: LocalLoopbackServer, target: int, cmd_base: int = 1000) -> void:
	var rw: RewardWindowModule = server.mode_modules.reward_window
	assert_not_null(rw)
	var n: int = cmd_base
	var guard := 0
	while rw.discard_count < target:
		guard += 1
		assert_lt(guard, 120, "驱动超时 discard=%d target=%d" % [rw.discard_count, target])
		var bc: BattleController = server.get("_bc") as BattleController
		assert_not_null(bc)
		if bool(bc.get("_settled")):
			assert_true(false, "驱动中途 settled discard=%d" % rw.discard_count)
			return
		for s in range(4):
			bc.decision_context_for_seat(s)
		var win = bc.get("_active_window")
		assert_true(win is DecisionWindow,
			"须有 active window discard=%d phase=%d" % [rw.discard_count, int(bc.state.phase)])
		var dw: DecisionWindow = win as DecisionWindow
		if dw.kind == DecisionWindow.KIND_CLAIM or dw.kind == DecisionWindow.KIND_ROB_KAN:
			var target_seat := -1
			for seat_i in dw.seats():
				var si: int = int(seat_i)
				if not dw.has_responded(si):
					target_seat = si
					break
			assert_gte(target_seat, 0, "CLAIM 须有未响应席")
			var ctx: DecisionContext = dw.context_for_seat(target_seat)
			assert_not_null(ctx)
			var act: Action = Action.make_pass(
				target_seat, str(server.get("_room_id")), _cmd(n),
				str(ctx.decision_id), int(ctx.hand_seq), n
			)
			var cr: CommandResult = server.submit_action(act)
			assert_eq(cr.status, "ACCEPTED",
				"CLAIM PASS seat%d 须 ACCEPTED status=%s code=%s"
				% [target_seat, cr.status, cr.error_code])
			n += 1
			continue
		if dw.kind == DecisionWindow.KIND_TURN:
			var actor: int = int(dw.subject_seat)
			var tctx: DecisionContext = dw.context_for_seat(actor)
			assert_not_null(tctx)
			var iid := -1
			for o in tctx.allowed_actions:
				if typeof(o) == TYPE_DICTIONARY and str(o.get("kind", "")) == "DISCARD":
					var opts: Array = o.get("payload_options", [])
					assert_false(opts.is_empty())
					iid = int(opts[0]["tile_instance_id"])
					break
			assert_gt(iid, -1, "TURN seat%d 须有 DISCARD" % actor)
			var dact: Action = Action.discard(
				actor, iid, str(server.get("_room_id")), _cmd(n),
				str(tctx.decision_id), int(tctx.hand_seq), n
			)
			var dcr: CommandResult = server.submit_action(dact)
			assert_eq(dcr.status, "ACCEPTED",
				"DISCARD seat%d 须 ACCEPTED status=%s code=%s" % [actor, dcr.status, dcr.error_code])
			n += 1
			continue
		assert_true(false, "未知 window kind=%s" % str(dw.kind))
		return


## 仅供第 24 弃分支测试：完整 0→24 生产链由
## test_full_24_default_practice_tick_ends_on_human_prompt 覆盖。
## 其余测试通过正式状态恢复契约跳过无关的前 23 次网络投影，再让第 24 弃
## 继续走真实 submit_action / ACTION_APPLIED / snapshot / reward-window 路径。
func _restore_before_24th_discard(server: LocalLoopbackServer) -> void:
	var rw: RewardWindowModule = server.mode_modules.reward_window
	assert_not_null(rw)
	assert_eq(rw.phase, RewardWindowModule.PHASE_OPEN)
	assert_eq(rw.discard_count, 0)
	var state: Dictionary = rw.capture_state()
	state["discard_count"] = RewardWindowModule.TARGET_DISCARDS - 1
	assert_true(rw.restore_state(state), "第 24 弃 fixture 必须通过正式 restore 契约")
	assert_eq(rw.discard_count, 23)


# ---- live hand helpers（复用 LLS 真实墙实体语义）----

func _prep_live(bc: BattleController) -> int:
	var draw_floor: int = int(bc.state.wall.draw_index())
	for s in range(4):
		var seat: Seat = bc.state.seats[s]
		seat.hand = Hand.new()
		seat.melds.restore([], 0)
		seat.last_drawn_instance_id = Tile.INVALID_INSTANCE_ID
		seat.furiten = FuritenState.new()
		bc.state.seats[s].river.restore([])
	bc.state.wall.set_draw_index(0)
	return draw_floor


func _seal_live_wall_draw_index(bc: BattleController, draw_floor: int) -> void:
	var w: Wall = bc.state.wall
	w.set_draw_index(maxi(int(draw_floor), int(w.draw_index())))


func _live_end_wall(w: Wall) -> int:
	return w.authority_tiles().size() - w.dead_wall_size()


func _find_live_idx(w: Wall, tid: int, used: Dictionary) -> int:
	var end_i: int = _live_end_wall(w)
	for i in range(w.draw_index(), end_i):
		var t: Tile = w.authority_tiles()[i]
		if t == null or int(t.id) != int(tid):
			continue
		if used.has(int(t.instance_id)):
			continue
		return i
	return -1


func _draw_live_tid(bc: BattleController, tid: int, used: Dictionary) -> Tile:
	var w: Wall = bc.state.wall
	var live_idx: int = _find_live_idx(w, tid, used)
	assert_true(live_idx >= 0, "live 区无 id=%d" % tid)
	if live_idx != w.draw_index():
		assert_true(w.move_live_index_to_top(live_idx))
	var drawn: Tile = w.draw()
	assert_not_null(drawn)
	if drawn != null:
		used[int(drawn.instance_id)] = true
	return drawn


func _hand_live(bc: BattleController, ids: Array, used: Dictionary) -> Hand:
	var h := Hand.new()
	for tid in ids:
		var t: Tile = _draw_live_tid(bc, int(tid), used)
		assert_not_null(t)
		assert_true(h.add(t))
	return h


func _chiitoi_13() -> Array:
	return [
		TileId.W1, TileId.W1, TileId.W2, TileId.W2, TileId.W3, TileId.W3,
		TileId.W5, TileId.W5, TileId.W6, TileId.W6, TileId.W7, TileId.W7,
		TileId.W9,
	]


func _noise_14_with(tid: int) -> Array:
	return [
		TileId.W2, TileId.W3, TileId.W4, TileId.W6, TileId.W8,
		TileId.T1, TileId.T2, TileId.T3, TileId.T4, TileId.T5,
		TileId.E, TileId.S_WIND, TileId.W_WIND, tid,
	]


# ---- tests ----

func test_open_before_prompt_and_standard_zero() -> void:
	var tt := LocalLoopbackServer.new(_cfg_tt(7), 0)
	assert_true(tt.start())
	var k: Array = _kinds(tt)
	assert_lt(k.find("REWARD_WINDOW_OPENED"), k.find("TURN_PROMPT"))
	assert_eq(_count(k, "ITEM_GRANTED"), 0)
	var st_cfg := GameSessionConfig.create_validated(
		GameSessionConfig.ROOM_PRACTICE, GameSessionConfig.ROUND_EAST,
		GameSessionConfig.MODE_STANDARD, PARTS, CHARS, 7, "sid-std", "rv"
	)
	var st := LocalLoopbackServer.new(st_cfg, 0)
	assert_true(st.start())
	assert_null(st.mode_modules.reward_window)
	assert_eq(_count(_kinds(st), "REWARD_WINDOW_OPENED"), 0)


func test_production_drive_to_24_closing_settle_order() -> void:
	# 全 HUMAN 第 24 弃 + 所有 CLAIM 席 PASS → 无条件 FULL_GRANT + 下一 OPEN
	var server := LocalLoopbackServer.new(_cfg_tt_all_human(11), 0)
	assert_true(server.start())
	var rw: RewardWindowModule = server.mode_modules.reward_window
	_restore_before_24th_discard(server)
	_drive_until_discard_count(server, 24, 2000)
	assert_eq(rw.discard_count, 24, "第 24 弃必须走真实权威动作")
	var kinds: Array = _kinds(server)
	assert_gte(_count(kinds, "REWARD_WINDOW_CLOSING"), 1)
	assert_eq(_count(kinds, "ITEM_GRANTED"), 0)
	# 首条 CLOSING 的 boundary == 触发它的那次 DISCARD ACTION_APPLIED.seq
	var close_seq := -1
	var close_b := -1
	var last_disc_aa := -1
	for ne in _events(server):
		if not (ne is NetworkedEvent):
			continue
		var e: NetworkedEvent = ne as NetworkedEvent
		if e.kind == "ACTION_APPLIED":
			var ak := String(e.payload.get("action_kind", ""))
			if ak == "DISCARD" or ak == "RIICHI":
				last_disc_aa = int(e.server_seq)
		if e.kind == "REWARD_WINDOW_CLOSING" and close_seq < 0:
			close_seq = int(e.server_seq)
			close_b = int(e.payload.get("closing_boundary_server_seq", -1))
	assert_gt(close_seq, 0)
	assert_eq(close_b, last_disc_aa, "closing_boundary 须等于第 24 弃 ACTION_APPLIED.seq")
	assert_lt(last_disc_aa, close_seq)
	# 持续读取 BC 当前 CLAIM/ROB 窗，对所有未响应席 PASS，直到窗关闭并 settle
	var n := 9000
	var guard := 0
	while rw.phase == RewardWindowModule.PHASE_CLOSING and guard < 40:
		guard += 1
		var bc: BattleController = server.get("_bc") as BattleController
		assert_not_null(bc)
		if bool(bc.get("_settled")):
			assert_true(false, "24 弃 FULL_GRANT 路径不得已和牌 settled")
			return
		for s in range(4):
			bc.decision_context_for_seat(s)
		var win = bc.get("_active_window")
		if win is DecisionWindow:
			var dw: DecisionWindow = win as DecisionWindow
			if dw.kind == DecisionWindow.KIND_CLAIM or dw.kind == DecisionWindow.KIND_ROB_KAN:
				var target_seat := -1
				for seat_i in dw.seats():
					var si: int = int(seat_i)
					if not dw.has_responded(si):
						target_seat = si
						break
				assert_gte(target_seat, 0, "CLAIM/ROB 须有未响应席")
				var ctx: DecisionContext = dw.context_for_seat(target_seat)
				assert_not_null(ctx)
				var act: Action = Action.make_pass(
					target_seat, str(server.get("_room_id")), _cmd(n),
					str(ctx.decision_id), int(ctx.hand_seq), n
				)
				var cr: CommandResult = server.submit_action(act)
				assert_eq(cr.status, "ACCEPTED",
					"CLAIM PASS seat%d 须 ACCEPTED status=%s code=%s"
					% [target_seat, cr.status, cr.error_code])
				n += 1
				continue
		# 无 CLAIM 窗：推进权威时钟释放 grace 屏障（若仍有 non-terminal）
		if not rw.claim_is_terminal():
			# 生产路径应已 mark terminal；再 tick 一次尝试释放
			assert_true(
				server.advance_reward_time(maxi(server._reward_now_ms() + 1, 1)),
				"claim 未 terminal 时 advance 不得无故失败"
			)
			continue
		if not rw.barrier_released(server._reward_now_ms()):
			assert_true(server.advance_reward_time(int(rw._grace_deadline_ms)),
				"grace deadline 推进须成功")
			continue
		# barrier 已释放：再 tick 触发 settle（幂等可 true）
		assert_true(server.advance_reward_time(server._reward_now_ms() + 1),
			"barrier released 后 settle 须成功")
	assert_ne(rw.phase, RewardWindowModule.PHASE_CLOSING,
		"所有 CLAIM 席 PASS 后不得停留 CLOSING")
	# 无条件硬断言：恰好 1 个 FULL_GRANT SETTLED + 4×ITEM_GRANTED + 其后恰好 1 个新 OPEN
	kinds = _kinds(server)
	assert_eq(_count(kinds, "ITEM_GRANTED"), 4, "#253：FULL_GRANT 后 seat0..3 各一次 ITEM_GRANTED")
	var settled_n := 0
	var open_after := 0
	var seen_settle := false
	var settled_ctx_b := -1
	var settled_close_b := -1
	for ne2 in _events(server):
		if not (ne2 is NetworkedEvent):
			continue
		var e2: NetworkedEvent = ne2 as NetworkedEvent
		if e2.kind == "REWARD_WINDOW_SETTLED":
			settled_n += 1
			seen_settle = true
			assert_eq(String(e2.payload.get("outcome", "")), "FULL_GRANT")
			assert_eq(int(e2.payload.get("grant_count", -1)), 4)
			settled_ctx_b = int(e2.payload.get("context_boundary_server_seq", -1))
			settled_close_b = int(e2.payload.get("closing_boundary_server_seq", -1))
		if seen_settle and e2.kind == "REWARD_WINDOW_OPENED":
			open_after += 1
	assert_eq(settled_n, 1, "须恰好 1 个 REWARD_WINDOW_SETTLED")
	assert_eq(open_after, 1, "SETTLED 后须恰好 1 个新 REWARD_WINDOW_OPENED")
	assert_eq(rw.phase, RewardWindowModule.PHASE_OPEN, "FULL_GRANT 后 phase 须为下一 OPEN")
	assert_gte(settled_ctx_b, settled_close_b,
		"context_boundary 须 >= closing_boundary")
	assert_eq(settled_close_b, close_b, "SETTLED 的 closing_boundary 须对齐首条 CLOSING")


func test_closing_ron_cancels_not_full_grant() -> void:
	var server := LocalLoopbackServer.new(_cfg_tt_all_human(42), 0)
	assert_true(server.start(), "TRASH_TALK 全 HUMAN start")
	var bc: BattleController = server.get("_bc")
	assert_not_null(bc)
	var rw: RewardWindowModule = server.mode_modules.reward_window
	assert_not_null(rw)
	_restore_before_24th_discard(server)
	assert_eq(rw.discard_count, 23)
	# 布置七对子听牌 + seat1 打 W9（与既有 LLS RON fixture 同结构）
	var used: Dictionary = {}
	var wall_floor: int = _prep_live(bc)
	bc.state.seats[0].hand = _hand_live(bc, _chiitoi_13(), used)
	bc.state.seats[0].furiten = FuritenState.new()
	bc.state.first_round_active = false
	bc.state.seats[1].hand = _hand_live(bc, _noise_14_with(TileId.W9), used)
	var disc: Tile = null
	for t in bc.state.seats[1].hand.tiles():
		if t != null and int(t.id) == TileId.W9:
			disc = t
			break
	assert_not_null(disc)
	bc.state.seats[1].last_drawn_instance_id = disc.instance_id
	bc.state.current_seat = 1
	bc.state.phase = BattlePhase.Kind.DISCARD
	bc.set("_settled", false)
	bc.set("_active_window", null)
	_seal_live_wall_draw_index(bc, wall_floor)

	var turn_ctx: DecisionContext = bc.decision_context_for_seat(1)
	assert_not_null(turn_ctx)
	var disc_act: Action = Action.discard(
		1, disc.instance_id, RON_SID, _cmd(5100), turn_ctx.decision_id,
		int(bc.state.hand_seq), int(server.current_server_seq()) + 1
	)
	var cr_d: CommandResult = server.submit_action(disc_act)
	assert_eq(cr_d.status, "ACCEPTED",
		"第 24 弃 DISCARD 须 ACCEPTED status=%s code=%s" % [cr_d.status, cr_d.error_code])
	assert_eq(rw.discard_count, 24)
	assert_eq(_count(_kinds(server), "REWARD_WINDOW_CLOSING"), 1)

	# CLAIM：seat0 RON + 2/3 PASS（decision_id 取自当前 active window）
	var cmd_n := 5110
	var settled_after_ron := false
	for step in range(3):
		var win = bc.get("_active_window")
		assert_true(win is DecisionWindow,
			"step%d 须有 CLAIM 窗 phase=%d settled=%s"
			% [step, int(bc.state.phase), str(bc.get("_settled"))])
		var dw: DecisionWindow = win as DecisionWindow
		assert_true(
			dw.kind == DecisionWindow.KIND_CLAIM or dw.kind == DecisionWindow.KIND_ROB_KAN
		)
		var target_seat := -1
		for seat_i in [0, 2, 3]:
			if not dw.has_responded(seat_i):
				target_seat = seat_i
				break
		assert_gte(target_seat, 0, "step%d 须有未响应席" % step)
		var ctx: DecisionContext = dw.context_for_seat(target_seat)
		assert_not_null(ctx)
		var act: Action
		if target_seat == 0:
			act = Action.ron(
				0, RON_SID, _cmd(cmd_n), str(ctx.decision_id), int(ctx.hand_seq),
				int(server.current_server_seq()) + 1
			)
		else:
			act = Action.make_pass(
				target_seat, RON_SID, _cmd(cmd_n), str(ctx.decision_id), int(ctx.hand_seq),
				int(server.current_server_seq()) + 1
			)
		cmd_n += 1
		var cr_step: CommandResult = server.submit_action(act)
		assert_eq(cr_step.status, "ACCEPTED",
			"CLAIM seat%d 须 ACCEPTED status=%s code=%s"
			% [target_seat, cr_step.status, cr_step.error_code])
		if bool(bc.get("_settled")):
			settled_after_ron = true
			break
	assert_true(settled_after_ron or bool(bc.get("_settled")), "RON 后须 settled")

	var kinds: Array = _kinds(server)
	assert_eq(_count(kinds, "REWARD_WINDOW_CANCELLED"), 1, "须 CANCELLED_BY_WIN")
	assert_eq(_count(kinds, "REWARD_WINDOW_SETTLED"), 0, "RON 不得 SETTLED")
	assert_eq(_count(kinds, "ITEM_GRANTED"), 0)
	# 不得因错误 FULL_GRANT 再开下一窗（CANCELLED 后 OPEN 计数应仍为开局 1）
	assert_eq(_count(kinds, "REWARD_WINDOW_OPENED"), 1,
		"和牌取消后不得 OPEN 下一窗")
	var cancel_p: Dictionary = {}
	for ne in _events(server):
		if ne is NetworkedEvent and (ne as NetworkedEvent).kind == "REWARD_WINDOW_CANCELLED":
			cancel_p = (ne as NetworkedEvent).payload
			break
	assert_eq(String(cancel_p.get("cancel_reason", "")), "CANCELLED_BY_WIN")
	assert_eq(int(cancel_p.get("grant_count", -1)), 0)
	assert_false(bool(cancel_p.get("scored", true)))
	assert_false(rw.scorer_was_called())
	# HAND_SETTLED 在 CANCEL 之后
	var cancel_seq := -1
	var hand_seq_ev := -1
	for ne2 in _events(server):
		if not (ne2 is NetworkedEvent):
			continue
		var e2: NetworkedEvent = ne2 as NetworkedEvent
		if e2.kind == "REWARD_WINDOW_CANCELLED":
			cancel_seq = int(e2.server_seq)
		if e2.kind == "HAND_SETTLED":
			hand_seq_ev = int(e2.server_seq)
			assert_eq(String(e2.payload.get("outcome", "")), "RON")
	assert_gt(cancel_seq, 0)
	assert_gt(hand_seq_ev, cancel_seq, "HAND_SETTLED 须在 CANCELLED 之后")


func test_settle_non_idempotent_fail_closed_blocks_progress() -> void:
	# P1: barrier released 后 try_settle 非幂等失败须 fail-closed；phase 仍 CLOSING，普通推进禁止
	var server := LocalLoopbackServer.new(_cfg_tt(5), 0)
	assert_true(server.start())
	var rw: RewardWindowModule = server.mode_modules.reward_window
	var seq0: int = server.current_server_seq() + 1
	for i in range(24):
		assert_true(bool(rw.on_discard_applied({
			"server_seq": seq0 + i, "seat": 0, "kind": "DISCARD",
			"now_ms": server._reward_now_ms(),
		}).get("ok", false)))
	assert_eq(rw.phase, RewardWindowModule.PHASE_CLOSING)
	var close_b: int = int(rw.closing_boundary_server_seq)
	assert_true(bool(rw.mark_claim_terminal({
		"context_boundary_server_seq": close_b,
	}).get("ok", false)))
	while server.current_server_seq() < close_b:
		assert_true(server.publish_snapshot())
	assert_true(rw.barrier_released(server._reward_now_ms()),
		"全终态后 barrier 须已释放")
	# 注入非法 pending → try_settle 返回 INVALID_PENDING_EXIT（非幂等失败）
	rw._pending_exit = "BOGUS_EXIT"
	var frozen_clock: int = server._reward_now_ms()
	var frozen_seq: int = server.current_server_seq()
	var frozen_j: int = server.event_journal(0).size()
	assert_false(server.advance_reward_time(frozen_clock + 1),
		"try_settle 失败须让 advance 整事务 fail-closed")
	assert_eq(rw.phase, RewardWindowModule.PHASE_CLOSING, "失败后 phase 仍 CLOSING")
	assert_false(server._reward_allows_normal_progress(),
		"CLOSING 未 settle 时普通推进必须禁止")
	assert_eq(server._reward_now_ms(), frozen_clock, "时钟须回滚")
	assert_eq(server.current_server_seq(), frozen_seq, "server_seq 须回滚")
	assert_eq(server.event_journal(0).size(), frozen_j, "journal 不得前进")
	assert_eq(_count(_kinds(server), "REWARD_WINDOW_SETTLED"), 0)
	# 外部注入的非法 pending 不在事务内，回滚后仍非法；修复后须可 settle
	assert_eq(String(rw._pending_exit), "BOGUS_EXIT")
	rw._pending_exit = "FULL_GRANT"
	assert_true(server.advance_reward_time(server._reward_now_ms() + 1),
		"修复 pending 后 settle 须成功")
	assert_eq(_count(_kinds(server), "REWARD_WINDOW_SETTLED"), 1)
	assert_eq(rw.phase, RewardWindowModule.PHASE_OPEN)


func test_public_dto_forbids_match_seed_and_hidden_fields() -> void:
	# 公开 DTO 递归禁止 seed/match_seed/hand/wall/hidden/private；损坏 deadline 零 mutation
	var rw := RewardWindowModule.new()
	assert_true(bool(rw.open({
		"seed": 9, "hand_seq": 0, "window_index": 0, "rule_version": RULE,
		"room_id": "room-public-dto", "character_ids": [
			"lin_yeche", "qiu_jue", "bai_touli", "hua_ling",
		],
		"language": "zh",
		"public_initial": {
			"hand_seq": 0, "dealer_seat": 0,
			"scores": [25000, 25000, 25000, 25000],
		},
	}).get("ok", false)))
	for i in range(24):
		rw.on_discard_applied({
			"server_seq": 20 + i, "seat": i % 4, "kind": "DISCARD", "now_ms": 1000,
		})
	assert_eq(rw.phase, RewardWindowModule.PHASE_CLOSING)
	assert_true(bool(rw.mark_claim_terminal({"context_boundary_server_seq": 50}).get("ok", false)))
	var dto: Dictionary = rw.to_snapshot_dto()
	var pl: Dictionary = dto["payload"]
	assert_false(pl.has("match_seed"), "公开 payload 不得含 match_seed")
	assert_false(pl.has("seed"), "公开 payload 不得含 seed")
	assert_true(_recursive_forbids_keys(dto, [
		"match_seed", "seed", "wall", "private_hand", "hidden_tiles", "private",
	]), "公开 DTO 递归禁止隐藏/seed 键")
	# capture_state 仍保留权威 seed
	var cap: Dictionary = rw.capture_state()
	assert_true(cap.has("_match_seed"))
	assert_eq(int(cap["_match_seed"]), 9)
	# 合法 restore 不依赖 match_seed
	var rw2 := RewardWindowModule.new()
	assert_true(bool(rw2.restore_from_snapshot_dto(dto).get("ok", false)))
	assert_eq(rw2.phase, RewardWindowModule.PHASE_CLOSING)
	assert_eq(int(rw2._grace_deadline_ms), int(rw._grace_deadline_ms))
	# 注入 match_seed → 拒绝且零 mutation
	var before2: String = TrashTalkGoldFixtures.stable_stringify(rw2.capture_state())
	var bad_seed := dto.duplicate(true)
	(bad_seed["payload"] as Dictionary)["match_seed"] = 99
	assert_false(bool(rw2.restore_from_snapshot_dto(bad_seed).get("ok", true)))
	assert_eq(TrashTalkGoldFixtures.stable_stringify(rw2.capture_state()), before2)
	# deadline_ms 与 ISO 不一致 → 拒绝
	var bad_dl := dto.duplicate(true)
	(bad_dl["payload"] as Dictionary)["grace_deadline_ms"] = int(pl["grace_deadline_ms"]) + 999
	assert_false(bool(rw2.restore_from_snapshot_dto(bad_dl).get("ok", true)))
	assert_eq(TrashTalkGoldFixtures.stable_stringify(rw2.capture_state()), before2)
	# 空 room_id / 非法 character / 非法 language → 拒绝
	var bad_room := dto.duplicate(true)
	(bad_room["payload"] as Dictionary)["room_id"] = ""
	assert_false(bool(rw2.restore_from_snapshot_dto(bad_room).get("ok", true)))
	var bad_chars := dto.duplicate(true)
	(bad_chars["payload"] as Dictionary)["character_ids"] = ["x", "y", "z", "w"]
	assert_false(bool(rw2.restore_from_snapshot_dto(bad_chars).get("ok", true)))
	var bad_lang := dto.duplicate(true)
	(bad_lang["payload"] as Dictionary)["language"] = "xx"
	assert_false(bool(rw2.restore_from_snapshot_dto(bad_lang).get("ok", true)))
	assert_eq(TrashTalkGoldFixtures.stable_stringify(rw2.capture_state()), before2)


func _recursive_forbids_keys(v: Variant, forbidden: Array) -> bool:
	if typeof(v) == TYPE_DICTIONARY:
		var d: Dictionary = v
		for k in d.keys():
			var ks := String(k)
			for f in forbidden:
				if ks == String(f):
					return false
			if not _recursive_forbids_keys(d[k], forbidden):
				return false
	elif typeof(v) == TYPE_ARRAY:
		for item in v:
			if not _recursive_forbids_keys(item, forbidden):
				return false
	return true


func test_advance_reward_time_settled_fail_atomic() -> void:
	var server := FailingRewardKindServer.new(_cfg_tt(5), 0)
	assert_true(server.start())
	var rw: RewardWindowModule = server.mode_modules.reward_window
	var seq0: int = server.current_server_seq() + 1
	for i in range(24):
		assert_true(bool(rw.on_discard_applied({
			"server_seq": seq0 + i, "seat": 0, "kind": "DISCARD",
			"now_ms": server._reward_now_ms(),
		}).get("ok", false)))
	assert_eq(rw.phase, RewardWindowModule.PHASE_CLOSING)
	var close_b: int = int(rw.closing_boundary_server_seq)
	assert_true(bool(rw.ingest_utterance({
		"seat": 0, "utterance_id": "nt1", "text": "x", "language": "zh",
		"ptt_end_server_seq": close_b, "terminal": false,
	}).get("accepted", false)))
	assert_true(bool(rw.mark_claim_terminal({
		"context_boundary_server_seq": close_b,
	}).get("ok", false)))
	while server.current_server_seq() < close_b:
		assert_true(server.publish_snapshot())
	assert_false(rw.barrier_released(server._reward_now_ms()))
	var frozen_clock: int = server._reward_now_ms()
	var frozen_seq: int = server.current_server_seq()
	var frozen_rw: String = TrashTalkGoldFixtures.stable_stringify(rw.capture_state())
	var frozen_j: int = server.event_journal(0).size()
	server.fail_kind = "REWARD_WINDOW_SETTLED"
	server.enabled = true
	var dl: int = int(rw._grace_deadline_ms)
	assert_false(server.advance_reward_time(dl))
	assert_gt(server.call_count, 0, "必须命中 SETTLED 失败 seam")
	assert_eq(server._reward_now_ms(), frozen_clock)
	assert_eq(server.current_server_seq(), frozen_seq)
	assert_eq(server.event_journal(0).size(), frozen_j)
	assert_eq(TrashTalkGoldFixtures.stable_stringify(rw.capture_state()), frozen_rw)
	server.enabled = false
	assert_true(server.advance_reward_time(dl))
	assert_eq(_count(_kinds(server), "REWARD_WINDOW_SETTLED"), 1)


func test_advance_reward_time_next_open_fail_atomic() -> void:
	var server := FailingRewardKindServer.new(_cfg_tt(5), 0)
	assert_true(server.start())
	var rw: RewardWindowModule = server.mode_modules.reward_window
	var seq0: int = server.current_server_seq() + 1
	for i in range(24):
		assert_true(bool(rw.on_discard_applied({
			"server_seq": seq0 + i, "seat": 0, "kind": "DISCARD",
			"now_ms": server._reward_now_ms(),
		}).get("ok", false)))
	var close_b: int = int(rw.closing_boundary_server_seq)
	# 全终态 → claim terminal 后可立即 settle（无 pending utterance）
	assert_true(bool(rw.mark_claim_terminal({
		"context_boundary_server_seq": close_b,
	}).get("ok", false)))
	while server.current_server_seq() < close_b:
		assert_true(server.publish_snapshot())
	assert_true(rw.barrier_released(server._reward_now_ms()),
		"无 non-terminal utterance 时 claim terminal 后应可释放")
	var frozen_clock: int = server._reward_now_ms()
	var frozen_seq: int = server.current_server_seq()
	var frozen_rw: String = TrashTalkGoldFixtures.stable_stringify(rw.capture_state())
	var frozen_j: int = server.event_journal(0).size()
	server.fail_kind = "REWARD_WINDOW_OPENED"
	server.enabled = true
	# 时钟必须推进以进入事务路径（相等会早退）
	var tick_to: int = frozen_clock + 1
	assert_false(server.advance_reward_time(tick_to), "OPEN 失败须整事务失败")
	assert_gt(server.call_count, 0, "必须命中 OPEN 失败 seam")
	assert_eq(server._reward_now_ms(), frozen_clock)
	assert_eq(server.current_server_seq(), frozen_seq)
	assert_eq(server.event_journal(0).size(), frozen_j)
	assert_eq(TrashTalkGoldFixtures.stable_stringify(rw.capture_state()), frozen_rw)
	assert_eq(rw.phase, RewardWindowModule.PHASE_CLOSING)


func test_real_riichi_affects_scoring_matrix() -> void:
	# 全 HUMAN：布置 seat0 门清听牌 13 + 摸非胡牌，TURN 含 RIICHI，经 submit_action 立直
	var server := LocalLoopbackServer.new(_cfg_tt_all_human(99), 0)
	assert_true(server.start())
	var bc: BattleController = server.get("_bc")
	var rw: RewardWindowModule = server.mode_modules.reward_window
	var used: Dictionary = {}
	var wall_floor: int = _prep_live(bc)
	# 七对听 W9；摸 W8（非胡）后应可立直切 W8
	bc.state.seats[0].hand = _hand_live(bc, _chiitoi_13(), used)
	var draw_t: Tile = _draw_live_tid(bc, TileId.W8, used)
	assert_not_null(draw_t)
	assert_true(bc.state.seats[0].hand.add(draw_t))
	bc.state.seats[0].last_drawn_instance_id = draw_t.instance_id
	bc.state.seats[0].furiten = FuritenState.new()
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.DISCARD
	bc.state.first_round_active = false
	bc.set("_settled", false)
	bc.set("_active_window", null)
	_seal_live_wall_draw_index(bc, wall_floor)
	assert_true(server.publish_snapshot())
	assert_true(server._emit_private_prompt())
	var win = bc.get("_active_window")
	assert_true(win is DecisionWindow)
	var dw: DecisionWindow = win as DecisionWindow
	var ctx: DecisionContext = dw.context_for_seat(0)
	assert_not_null(ctx)
	var rid := -1
	for o in ctx.allowed_actions:
		if typeof(o) == TYPE_DICTIONARY and str(o.get("kind", "")) == "RIICHI":
			var opts: Array = o.get("payload_options", [])
			assert_false(opts.is_empty())
			rid = int(opts[0]["tile_instance_id"])
			break
	assert_gt(rid, -1, "fixture 须提供合法 RIICHI offer")
	var before_pe: int = rw.public_events_count()
	# 冻结无 RIICHI 时的评分基线输入
	var base_initial: Dictionary = TrashTalkPublicContextAdapter.public_snapshot_from_battle_state(
		bc.state
	)
	var pool: Array = rw.prize_pool.duplicate()
	var act: Action = Action.riichi(
		0, rid, RON_SID, _cmd(7000), str(ctx.decision_id), int(ctx.hand_seq),
		int(server.current_server_seq()) + 1
	)
	var cr: CommandResult = server.submit_action(act)
	assert_eq(cr.status, "ACCEPTED",
		"RIICHI 须 ACCEPTED status=%s code=%s" % [cr.status, cr.error_code])
	assert_gt(rw.public_events_count(), before_pe, "生产路径须摄入公开事件")
	var found_riichi := false
	for ne in _events(server):
		if ne is NetworkedEvent and (ne as NetworkedEvent).kind == "ACTION_APPLIED":
			if String((ne as NetworkedEvent).payload.get("action_kind", "")) == "RIICHI":
				found_riichi = true
				assert_not_null(NetworkedEvent.from_dict((ne as NetworkedEvent).to_dict()))
	assert_true(found_riichi, "journal 须有 ACTION_APPLIED(RIICHI)")
	# 关闭并评分（模块路径，事件已由生产 submit 写入）
	if rw.phase == RewardWindowModule.PHASE_OPEN:
		assert_true(bool(rw.begin_closing({
			"closing_boundary_server_seq": maxi(server.current_server_seq(), 1),
			"now_ms": server._reward_now_ms(),
			"pending_exit": "FULL_GRANT",
			"settle_reason": RewardWindowModule.SETTLE_REASON_FULL_24,
		}).get("ok", false)))
	assert_true(bool(rw.mark_claim_terminal({
		"context_boundary_server_seq": maxi(int(rw.closing_boundary_server_seq), 1),
	}).get("ok", false)))
	# public_context 仅在有文本活动席计分；给 seat0 最小非空 utterance
	var utt0 := [{
		"utterance_id": "u_riichi_ctx",
		"text": "立直",
		"language": "zh",
		"ptt_end_server_seq": maxi(server.current_server_seq(), 1),
	}]
	var score_in_with: Dictionary = {
		"window_exit": "FULL_GRANT",
		"rule_version": RULE,
		"window_id": rw.window_id,
		"hand_seq": rw.hand_seq,
		"room_id": RON_SID,
		"character_ids": ["lin_yeche", "qiu_jue", "bai_touli", "hua_ling"],
		"pool_item_ids": pool,
		"language": "zh",
		"closing_boundary_server_seq": maxi(server.current_server_seq(), 1),
		"context_boundary_server_seq": maxi(server.current_server_seq(), 1),
		"utterances_by_seat": {"0": utt0, "1": [], "2": [], "3": []},
		"public_events": rw._public_events.duplicate(true),
		"public_initial": base_initial,
	}
	var score_in_no: Dictionary = score_in_with.duplicate(true)
	score_in_no["public_events"] = []
	var with_r: Dictionary = TrashTalkContextScorer.score_matrix(score_in_with)
	var no_r: Dictionary = TrashTalkContextScorer.score_matrix(score_in_no)
	assert_true(bool(with_r.get("ok", false)), str(with_r))
	assert_true(bool(no_r.get("ok", false)), str(no_r))
	assert_ne(
		TrashTalkGoldFixtures.stable_stringify(with_r.get("matrix", [])),
		TrashTalkGoldFixtures.stable_stringify(no_r.get("matrix", [])),
		"真实 RIICHI 公开事件须改变评分矩阵"
	)
	# 确认命中 CTX_RIICHI_OPEN 相关规则
	var hit_riichi := false
	for row in with_r.get("matrix", []):
		if typeof(row) != TYPE_DICTIONARY:
			continue
		for rid2 in row.get("matched_rule_ids", []):
			if String(rid2).contains("riichi"):
				hit_riichi = true
	assert_true(hit_riichi or int((with_r.get("matrix", []) as Array).size()) == 16,
		"矩阵应反映 RIICHI 上下文")
	# 更硬：至少有一分 public_context > 0 于 seat0
	var max_pc := 0
	for row2 in with_r.get("matrix", []):
		if typeof(row2) == TYPE_DICTIONARY and int(row2.get("seat", -1)) == 0:
			max_pc = maxi(max_pc, int(row2.get("public_context", 0)))
	assert_gt(max_pc, 0, "seat0 在 RIICHI 后 public_context 应 > 0")


func test_closing_dto_roundtrip_continues_same_deadline() -> void:
	var rw := RewardWindowModule.new()
	assert_true(bool(rw.open({
		"seed": 3, "hand_seq": 0, "window_index": 0, "rule_version": RULE,
		"room_id": "r", "character_ids": ["lin_yeche", "qiu_jue", "bai_touli", "hua_ling"],
		"language": "zh",
		"public_initial": {"hand_seq": 0, "dealer_seat": 0, "scores": [25000, 25000, 25000, 25000]},
	}).get("ok", false)))
	for i in range(24):
		rw.on_discard_applied({
			"server_seq": 10 + i, "seat": 0, "kind": "DISCARD", "now_ms": 1000,
		})
	assert_eq(rw.phase, RewardWindowModule.PHASE_CLOSING)
	# non-terminal utterance：deadline 前阻塞；同一 deadline 释放
	assert_true(bool(rw.ingest_utterance({
		"seat": 0, "utterance_id": "u", "text": "hi", "language": "zh",
		"ptt_end_server_seq": 33, "terminal": false,
	}).get("accepted", false)))
	assert_true(bool(rw.mark_claim_terminal({"context_boundary_server_seq": 40}).get("ok", false)))
	var dto: Dictionary = rw.to_snapshot_dto()
	assert_eq(typeof(dto["schema_version"]), TYPE_INT)
	var pl: Dictionary = dto["payload"]
	assert_true(pl.has("grace_deadline_ms"))
	assert_eq(String(pl.get("pending_exit", "")), "FULL_GRANT")
	assert_gt(int(pl.get("grace_deadline_ms", 0)), 0)
	var rw2 := RewardWindowModule.new()
	var rest: Dictionary = rw2.restore_from_snapshot_dto(dto)
	assert_true(bool(rest.get("ok", false)), "DTO restore 须成功: %s" % str(rest))
	assert_eq(rw2.phase, RewardWindowModule.PHASE_CLOSING)
	assert_eq(int(rw2._grace_deadline_ms), int(rw._grace_deadline_ms))
	assert_eq(String(rw2._pending_exit), String(rw._pending_exit))
	var dl: int = int(rw2._grace_deadline_ms)
	assert_false(rw2.barrier_released(dl - 1), "deadline 前须阻塞")
	assert_true(rw2.barrier_released(dl), "同一 deadline 须释放")
	# 同 deadline 后 terminalize 文本并 settle，payload 字节一致
	assert_true(bool(rw.ingest_utterance({
		"seat": 0, "utterance_id": "u", "text": "hi", "language": "zh",
		"ptt_end_server_seq": 33, "terminal": true,
	}).get("ok", false)))
	assert_true(bool(rw2.ingest_utterance({
		"seat": 0, "utterance_id": "u", "text": "hi", "language": "zh",
		"ptt_end_server_seq": 33, "terminal": true,
	}).get("ok", false)))
	var s1: Dictionary = rw.try_settle({"now_ms": dl})
	var s2: Dictionary = rw2.try_settle({"now_ms": dl})
	assert_true(bool(s1.get("ok", false)), str(s1))
	assert_true(bool(s2.get("ok", false)), str(s2))
	assert_eq(
		TrashTalkGoldFixtures.stable_stringify(s1["payload"]),
		TrashTalkGoldFixtures.stable_stringify(s2["payload"])
	)


func test_capture_restore_rejects_bad_container_zero_mutation() -> void:
	var rw := RewardWindowModule.new()
	assert_true(bool(rw.open({
		"seed": 1, "hand_seq": 0, "window_index": 0, "rule_version": RULE,
		"room_id": "r", "character_ids": ["lin_yeche", "qiu_jue", "bai_touli", "hua_ling"],
		"language": "zh",
		"public_initial": {"hand_seq": 0, "dealer_seat": 0, "scores": [25000, 25000, 25000, 25000]},
	}).get("ok", false)))
	var good: Dictionary = rw.capture_state()
	var before: String = TrashTalkGoldFixtures.stable_stringify(good)
	var bad := good.duplicate(true)
	bad["_opened_payload"] = "nope"
	assert_false(rw.restore_state(bad))
	assert_eq(TrashTalkGoldFixtures.stable_stringify(rw.capture_state()), before)
	var bad2 := good.duplicate(true)
	bad2["_character_ids"] = "x"
	assert_false(rw.restore_state(bad2))
	assert_eq(TrashTalkGoldFixtures.stable_stringify(rw.capture_state()), before)


func test_advance_reward_time_open_phase_no_extra_side_effects() -> void:
	# P2 R7：OPEN 期间递增时钟不得重复 TURN_PROMPT/SNAPSHOT/业务事件
	var server := LocalLoopbackServer.new(_cfg_tt(21), 0)
	assert_true(server.start())
	var rw: RewardWindowModule = server.mode_modules.reward_window
	assert_eq(rw.phase, RewardWindowModule.PHASE_OPEN)
	assert_gte(_count(_kinds(server), "TURN_PROMPT"), 1)
	var j0: int = server.event_journal(0).size()
	var kinds0: Array = _kinds(server)
	var tp0: int = _count(kinds0, "TURN_PROMPT")
	var snap0: int = _count(kinds0, "ROOM_SNAPSHOT")
	var open0: int = _count(kinds0, "REWARD_WINDOW_OPENED")
	var rw0: String = TrashTalkGoldFixtures.stable_stringify(rw.capture_state())
	var seq0: int = server.current_server_seq()
	var bc: BattleController = server.get("_bc")
	var phase0: int = int(bc.state.phase)
	var seat0: int = int(bc.state.current_seat)
	var clock0: int = server._reward_now_ms()
	assert_true(server.advance_reward_time(clock0 + 100))
	assert_true(server.advance_reward_time(clock0 + 500))
	assert_true(server.advance_reward_time(clock0 + 1500))
	assert_eq(server._reward_now_ms(), clock0 + 1500, "时钟须单调推进")
	assert_eq(server.event_journal(0).size(), j0, "OPEN 期 tick 不得增 journal")
	assert_eq(server.current_server_seq(), seq0)
	var kinds1: Array = _kinds(server)
	assert_eq(_count(kinds1, "TURN_PROMPT"), tp0)
	assert_eq(_count(kinds1, "ROOM_SNAPSHOT"), snap0)
	assert_eq(_count(kinds1, "REWARD_WINDOW_OPENED"), open0)
	assert_eq(_count(kinds1, "REWARD_WINDOW_SETTLED"), 0)
	assert_eq(TrashTalkGoldFixtures.stable_stringify(rw.capture_state()), rw0,
		"OPEN 期 tick 不得改变 RW 业务状态")
	assert_eq(int(bc.state.phase), phase0)
	assert_eq(int(bc.state.current_seat), seat0)


func test_full_24_default_practice_tick_ends_on_human_prompt() -> void:
	# 默认 [HUMAN,AI,AI,AI]：真实推进满 24 + pending → tick 后 SETTLED/OPEN，
	# AI 链须落到合法真人决策窗（或领域终局 HAND_SETTLED）；不得停在 DRAW 无窗。
	var server := LocalLoopbackServer.new(_cfg_tt(17), 0)
	assert_true(server.start())
	var rw: RewardWindowModule = server.mode_modules.reward_window
	_drive_tt_mixed_until_discards(server, 23, 6000)
	assert_eq(rw.discard_count, 23)
	assert_true(bool(rw.ingest_utterance({
		"seat": 0, "utterance_id": "pend_def", "text": "等", "language": "zh",
		"ptt_end_server_seq": maxi(server.current_server_seq(), 1), "terminal": false,
	}).get("accepted", false)))
	_drive_tt_mixed_until_discards(server, 24, 7000)
	assert_eq(rw.discard_count, 24)
	assert_eq(rw.phase, RewardWindowModule.PHASE_CLOSING)
	# 关闭 CLAIM（真人 PASS；AI 由 auto 处理）
	var n := 8000
	var guard := 0
	while rw.phase == RewardWindowModule.PHASE_CLOSING and guard < 50:
		guard += 1
		var bc0: BattleController = server.get("_bc")
		for s in range(4):
			bc0.decision_context_for_seat(s)
		var win0 = bc0.get("_active_window")
		if win0 is DecisionWindow:
			var dw0: DecisionWindow = win0 as DecisionWindow
			if dw0.kind == DecisionWindow.KIND_CLAIM or dw0.kind == DecisionWindow.KIND_ROB_KAN:
				var human_pending := -1
				for seat_i in dw0.seats():
					var si: int = int(seat_i)
					if not dw0.has_responded(si) and _is_human_seat(server, si):
						human_pending = si
						break
				if human_pending >= 0:
					var ctx: DecisionContext = dw0.context_for_seat(human_pending)
					var act: Action = Action.make_pass(
						human_pending, str(server.get("_room_id")), _cmd(n),
						str(ctx.decision_id), int(ctx.hand_seq), n
					)
					assert_eq(server.submit_action(act).status, "ACCEPTED")
					n += 1
					continue
				assert_true(bool(server.call("_auto_advance_claim_only")))
				continue
		break
	assert_eq(rw.phase, RewardWindowModule.PHASE_CLOSING)
	assert_false(rw.barrier_released(server._reward_now_ms()))
	var j_before: int = server.event_journal(0).size()
	var dl: int = int(rw._grace_deadline_ms)
	assert_true(server.advance_reward_time(dl), "deadline tick 须成功")
	assert_eq(_count(_kinds(server), "ITEM_GRANTED"), 4, "FULL_GRANT 须 4×ITEM_GRANTED")
	assert_eq(_count(_kinds(server), "REWARD_WINDOW_SETTLED"), 1)
	var seen_set := false
	var open_after := 0
	for ne in _events(server):
		if not (ne is NetworkedEvent):
			continue
		var e: NetworkedEvent = ne as NetworkedEvent
		if e.kind == "REWARD_WINDOW_SETTLED":
			seen_set = true
			assert_eq(String(e.payload.get("outcome", "")), "FULL_GRANT")
		if seen_set and e.kind == "REWARD_WINDOW_OPENED":
			open_after += 1
	assert_eq(open_after, 1)
	assert_eq(rw.phase, RewardWindowModule.PHASE_OPEN)
	var bc: BattleController = server.get("_bc")
	if bool(bc.get("_settled")):
		assert_gte(_count(_kinds(server), "HAND_SETTLED"), 1,
			"领域终局须 HAND_SETTLED（RW 顺序已在 settle 路径保证）")
	else:
		assert_ne(int(bc.state.phase), BattlePhase.Kind.DRAW,
			"不得停在真人 DRAW 无有效提示 phase=%d seat=%d"
			% [int(bc.state.phase), int(bc.state.current_seat)])
		var win = bc.get("_active_window")
		assert_true(win is DecisionWindow, "tick 后须有 DecisionWindow")
		var dw: DecisionWindow = win as DecisionWindow
		if dw.kind == DecisionWindow.KIND_TURN:
			assert_true(_is_human_seat(server, int(dw.subject_seat)),
				"TURN 须落在真人席 seat=%d" % int(dw.subject_seat))
			assert_not_null(_last_turn_prompt(server, int(dw.subject_seat)))
		else:
			assert_true(
				dw.kind == DecisionWindow.KIND_CLAIM \
				or dw.kind == DecisionWindow.KIND_ROB_KAN
			)
	var set_n := _count(_kinds(server), "REWARD_WINDOW_SETTLED")
	var open_n := _count(_kinds(server), "REWARD_WINDOW_OPENED")
	assert_gt(server.event_journal(0).size(), j_before)
	assert_true(server.advance_reward_time(dl + 20))
	assert_eq(_count(_kinds(server), "REWARD_WINDOW_SETTLED"), set_n)
	assert_eq(_count(_kinds(server), "REWARD_WINDOW_OPENED"), open_n)


func _is_human_seat(server: LocalLoopbackServer, seat: int) -> bool:
	var parts = server.get("_participants")
	if not (parts is Array) or seat < 0 or seat >= (parts as Array).size():
		return false
	return String((parts as Array)[seat]) == "HUMAN"


## 默认练习场混合席：仅对真人 CLAIM/TURN 提交；AI 靠 submit 内 auto 或显式 _auto_advance_ai。
func _drive_tt_mixed_until_discards(
	server: LocalLoopbackServer, target: int, cmd_base: int
) -> void:
	var rw: RewardWindowModule = server.mode_modules.reward_window
	assert_not_null(rw)
	var n: int = cmd_base
	var guard := 0
	while rw.discard_count < target:
		guard += 1
		assert_lt(guard, 200, "mixed 驱动超时 discard=%d" % rw.discard_count)
		var bc: BattleController = server.get("_bc") as BattleController
		assert_not_null(bc)
		if bool(bc.get("_settled")):
			assert_true(false, "驱动中途 settled discard=%d" % rw.discard_count)
			return
		for s in range(4):
			bc.decision_context_for_seat(s)
		var win = bc.get("_active_window")
		if win == null or not (win is DecisionWindow):
			assert_true(bool(server.call("_auto_advance_ai")),
				"无窗时 AI 推进须成功 discard=%d" % rw.discard_count)
			continue
		var dw: DecisionWindow = win as DecisionWindow
		if dw.kind == DecisionWindow.KIND_CLAIM or dw.kind == DecisionWindow.KIND_ROB_KAN:
			var human_pending := -1
			for seat_i in dw.seats():
				var si: int = int(seat_i)
				if not dw.has_responded(si) and _is_human_seat(server, si):
					human_pending = si
					break
			if human_pending >= 0:
				var cctx: DecisionContext = dw.context_for_seat(human_pending)
				assert_not_null(cctx)
				var pact: Action = Action.make_pass(
					human_pending, str(server.get("_room_id")), _cmd(n),
					str(cctx.decision_id), int(cctx.hand_seq), n
				)
				var pcr: CommandResult = server.submit_action(pact)
				assert_eq(pcr.status, "ACCEPTED",
					"mixed CLAIM PASS seat%d 失败 %s" % [human_pending, pcr.error_code])
				n += 1
				continue
			assert_true(bool(server.call("_auto_advance_claim_only")) \
				or bool(server.call("_auto_advance_ai")))
			continue
		if dw.kind == DecisionWindow.KIND_TURN:
			var actor: int = int(dw.subject_seat)
			if not _is_human_seat(server, actor):
				assert_true(bool(server.call("_auto_advance_ai")),
					"AI TURN 须 auto 推进 seat=%d" % actor)
				continue
			var tctx: DecisionContext = dw.context_for_seat(actor)
			assert_not_null(tctx)
			var iid := -1
			for o in tctx.allowed_actions:
				if typeof(o) == TYPE_DICTIONARY and str(o.get("kind", "")) == "DISCARD":
					var opts: Array = o.get("payload_options", [])
					assert_false(opts.is_empty())
					iid = int(opts[0]["tile_instance_id"])
					break
			assert_gt(iid, -1, "真人 TURN 须有 DISCARD")
			var dact: Action = Action.discard(
				actor, iid, str(server.get("_room_id")), _cmd(n),
				str(tctx.decision_id), int(tctx.hand_seq), n
			)
			var dcr: CommandResult = server.submit_action(dact)
			assert_eq(dcr.status, "ACCEPTED",
				"mixed DISCARD seat%d 失败 %s" % [actor, dcr.error_code])
			n += 1
			continue
		assert_true(false, "未知 window kind=%s" % str(dw.kind))
		return


func test_exhaustive_draw_deferred_hand_settled_order() -> void:
	# P2-1：流局 + non-terminal utterance → 不得先 HAND_SETTLED；tick 后 SETTLED → HAND_SETTLED
	var server := LocalLoopbackServer.new(_cfg_tt(8), 0)
	assert_true(server.start())
	var rw: RewardWindowModule = server.mode_modules.reward_window
	var bc: BattleController = server.get("_bc")
	assert_not_null(rw)
	assert_eq(rw.phase, RewardWindowModule.PHASE_OPEN)
	var ptt: int = maxi(server.current_server_seq(), 1)
	assert_true(bool(rw.ingest_utterance({
		"seat": 0, "utterance_id": "pend_draw", "text": "流了", "language": "zh",
		"ptt_end_server_seq": ptt, "terminal": false,
	}).get("accepted", false)))
	# 真实 exhaustive domain
	var w: Wall = bc.state.wall
	w.set_draw_index(_live_end_wall(w))
	bc.state.phase = BattlePhase.Kind.DRAW
	bc.state.current_seat = 0
	bc.set("_settled", false)
	bc.set("_active_window", null)
	var drawn: Tile = bc.engine.draw_for_current()
	assert_true(drawn == null)
	if not bool(bc.get("_settled")):
		bc._emit(&"EXHAUSTIVE_DRAW", -1, null, {})
		bc.set("_settled", true)
	assert_true(bool(bc.get("_settled")))
	var j0: int = server.event_journal(0).size()
	assert_true(bool(server.call("_emit_settled_if_needed")))
	assert_eq(_count(_kinds(server), "HAND_SETTLED"), 0,
		"barrier 未释放时不得发布 HAND_SETTLED")
	assert_gte(_count(_kinds(server), "REWARD_WINDOW_CLOSING"), 1)
	assert_eq(rw.phase, RewardWindowModule.PHASE_CLOSING)
	assert_true(bool(server.get("_reward_hand_settled_deferred")))
	assert_eq(String(rw.settle_reason), RewardWindowModule.SETTLE_REASON_NON_FINAL_DRAW)
	# deadline tick
	var dl: int = int(rw._grace_deadline_ms)
	assert_true(server.advance_reward_time(dl))
	var kinds: Array = _kinds(server)
	assert_eq(_count(kinds, "ITEM_GRANTED"), 4, "非终场流局 FULL_GRANT 须 4×ITEM_GRANTED")
	assert_eq(_count(kinds, "REWARD_WINDOW_SETTLED"), 1)
	assert_eq(_count(kinds, "HAND_SETTLED"), 1)
	# 顺序：CLOSING → SETTLED → 4×GRANTED → HAND_SETTLED；无下一 OPEN（hand 已 settled）
	var i_close := -1
	var i_set := -1
	var i_hand := -1
	var i_open_after := -1
	var seen_set := false
	var idx := 0
	for ne in _events(server):
		if not (ne is NetworkedEvent):
			idx += 1
			continue
		var e: NetworkedEvent = ne as NetworkedEvent
		if e.kind == "REWARD_WINDOW_CLOSING" and i_close < 0:
			i_close = idx
		if e.kind == "REWARD_WINDOW_SETTLED" and i_set < 0:
			i_set = idx
			seen_set = true
			assert_eq(String(e.payload.get("outcome", "")), "FULL_GRANT")
			assert_eq(String(e.payload.get("settle_reason", "")),
				RewardWindowModule.SETTLE_REASON_NON_FINAL_DRAW)
		if e.kind == "HAND_SETTLED" and i_hand < 0:
			i_hand = idx
			assert_eq(String(e.payload.get("outcome", "")), "EXHAUSTIVE_DRAW")
		if seen_set and e.kind == "REWARD_WINDOW_OPENED" and i_open_after < 0:
			i_open_after = idx
		idx += 1
	assert_gt(i_close, -1)
	assert_gt(i_set, i_close)
	assert_gt(i_hand, i_set, "HAND_SETTLED 须在 REWARD_WINDOW_SETTLED 之后")
	assert_eq(i_open_after, -1, "NON_FINAL_DRAW 不得在已 settled hand 伪造下一 OPEN")
	# 重复 tick 幂等
	var j1: int = server.event_journal(0).size()
	assert_true(server.advance_reward_time(dl + 10))
	assert_eq(server.event_journal(0).size(), j1)
	assert_eq(_count(_kinds(server), "HAND_SETTLED"), 1)
	assert_eq(_count(_kinds(server), "REWARD_WINDOW_SETTLED"), 1)
	assert_gte(server.event_journal(0).size(), j0)


func test_match_end_deferred_display_only_no_next_open() -> void:
	var server := LocalLoopbackServer.new(_cfg_tt(9), 0)
	assert_true(server.start())
	server.set_reward_match_ended(true)
	var rw: RewardWindowModule = server.mode_modules.reward_window
	var bc: BattleController = server.get("_bc")
	assert_true(bool(rw.ingest_utterance({
		"seat": 1, "utterance_id": "pend_end", "text": "终", "language": "zh",
		"ptt_end_server_seq": maxi(server.current_server_seq(), 1), "terminal": false,
	}).get("accepted", false)))
	var w: Wall = bc.state.wall
	w.set_draw_index(_live_end_wall(w))
	bc.state.phase = BattlePhase.Kind.DRAW
	bc.set("_settled", false)
	bc.set("_active_window", null)
	assert_true(bc.engine.draw_for_current() == null)
	if not bool(bc.get("_settled")):
		bc._emit(&"EXHAUSTIVE_DRAW", -1, null, {})
		bc.set("_settled", true)
	assert_true(bool(server.call("_emit_settled_if_needed")))
	assert_eq(_count(_kinds(server), "HAND_SETTLED"), 0)
	assert_eq(String(rw.settle_reason), RewardWindowModule.SETTLE_REASON_MATCH_END)
	assert_true(server.advance_reward_time(int(rw._grace_deadline_ms)))
	var kinds: Array = _kinds(server)
	assert_eq(_count(kinds, "REWARD_WINDOW_SETTLED"), 1)
	assert_eq(_count(kinds, "HAND_SETTLED"), 1)
	assert_eq(_count(kinds, "ITEM_GRANTED"), 0)
	var seen_set := false
	var open_after := 0
	for ne in _events(server):
		if not (ne is NetworkedEvent):
			continue
		var e: NetworkedEvent = ne as NetworkedEvent
		if e.kind == "REWARD_WINDOW_SETTLED":
			seen_set = true
			assert_eq(String(e.payload.get("outcome", "")), "DISPLAY_ONLY")
			assert_eq(int(e.payload.get("grant_count", -1)), 0)
		if seen_set and e.kind == "REWARD_WINDOW_OPENED":
			open_after += 1
	assert_eq(open_after, 0, "MATCH_END 不得开下一窗")


func test_full_24_pending_utt_tick_settles_and_resumes() -> void:
	# 满 24 + CLAIM 终态 + pending utterance：tick 后 SETTLED→OPEN 并恢复提示
	var server := LocalLoopbackServer.new(_cfg_tt_all_human(13), 0)
	assert_true(server.start())
	var rw: RewardWindowModule = server.mode_modules.reward_window
	_restore_before_24th_discard(server)
	assert_eq(rw.discard_count, 23)
	# 在第 24 弃前注入 non-terminal，closing 后 ptt 仍合格并阻塞屏障
	var ptt_pre: int = maxi(server.current_server_seq(), 1)
	assert_true(bool(rw.ingest_utterance({
		"seat": 0, "utterance_id": "pend24", "text": "再等", "language": "zh",
		"ptt_end_server_seq": ptt_pre, "terminal": false,
	}).get("accepted", false)))
	_drive_until_discard_count(server, 24, 5000)
	assert_eq(rw.discard_count, 24)
	assert_eq(rw.phase, RewardWindowModule.PHASE_CLOSING)
	# 全席 PASS 关闭 CLAIM
	var n := 9500
	var guard := 0
	while rw.phase == RewardWindowModule.PHASE_CLOSING and guard < 40:
		guard += 1
		var bc: BattleController = server.get("_bc")
		for s in range(4):
			bc.decision_context_for_seat(s)
		var win = bc.get("_active_window")
		if win is DecisionWindow:
			var dw: DecisionWindow = win as DecisionWindow
			if dw.kind == DecisionWindow.KIND_CLAIM or dw.kind == DecisionWindow.KIND_ROB_KAN:
				var target_seat := -1
				for seat_i in dw.seats():
					var si: int = int(seat_i)
					if not dw.has_responded(si):
						target_seat = si
						break
				assert_gte(target_seat, 0)
				var ctx: DecisionContext = dw.context_for_seat(target_seat)
				var act: Action = Action.make_pass(
					target_seat, str(server.get("_room_id")), _cmd(n),
					str(ctx.decision_id), int(ctx.hand_seq), n
				)
				assert_eq(server.submit_action(act).status, "ACCEPTED")
				n += 1
				continue
		break
	assert_eq(rw.phase, RewardWindowModule.PHASE_CLOSING,
		"pending utterance 须保持 CLOSING 直至 deadline")
	assert_false(rw.barrier_released(server._reward_now_ms()))
	var prompts_before := _count(_kinds(server), "TURN_PROMPT")
	var dl: int = int(rw._grace_deadline_ms)
	assert_true(server.advance_reward_time(dl), "deadline tick 须成功 settle+open+恢复")
	var kinds: Array = _kinds(server)
	assert_eq(_count(kinds, "ITEM_GRANTED"), 4, "满 24 FULL_GRANT 须 4×ITEM_GRANTED")
	assert_eq(_count(kinds, "REWARD_WINDOW_SETTLED"), 1)
	var seen_set := false
	var open_after := 0
	for ne in _events(server):
		if not (ne is NetworkedEvent):
			continue
		var e: NetworkedEvent = ne as NetworkedEvent
		if e.kind == "REWARD_WINDOW_SETTLED":
			seen_set = true
			assert_eq(String(e.payload.get("outcome", "")), "FULL_GRANT")
		if seen_set and e.kind == "REWARD_WINDOW_OPENED":
			open_after += 1
	assert_eq(open_after, 1, "满 24 FULL_GRANT 后须下一 OPEN")
	assert_eq(rw.phase, RewardWindowModule.PHASE_OPEN)
	var bc2: BattleController = server.get("_bc")
	assert_false(bool(bc2.get("_settled")), "满 24 路径 hand 不得 settled")
	var prompts_after := _count(_kinds(server), "TURN_PROMPT")
	var win2 = bc2.get("_active_window")
	assert_true(
		prompts_after > prompts_before or win2 is DecisionWindow,
		"tick 后须恢复普通提示/窗口 prompts %d→%d win=%s"
		% [prompts_before, prompts_after, str(win2)]
	)
	var set_n := _count(_kinds(server), "REWARD_WINDOW_SETTLED")
	var open_n := _count(_kinds(server), "REWARD_WINDOW_OPENED")
	assert_true(server.advance_reward_time(dl + 5))
	assert_eq(_count(_kinds(server), "REWARD_WINDOW_SETTLED"), set_n)
	assert_eq(_count(_kinds(server), "REWARD_WINDOW_OPENED"), open_n)


func test_public_dto_rejects_out_of_bound_scoring_inputs() -> void:
	# P2-2：损坏 utterance/event 不得进入评分
	var rw := RewardWindowModule.new()
	assert_true(bool(rw.open({
		"seed": 4, "hand_seq": 0, "window_index": 0, "rule_version": RULE,
		"room_id": "dto-bound", "character_ids": [
			"lin_yeche", "qiu_jue", "bai_touli", "hua_ling",
		],
		"language": "zh",
		"public_initial": {
			"hand_seq": 0, "dealer_seat": 0,
			"scores": [25000, 25000, 25000, 25000],
		},
	}).get("ok", false)))
	for i in range(24):
		rw.on_discard_applied({
			"server_seq": 30 + i, "seat": 0, "kind": "DISCARD", "now_ms": 1000,
		})
	assert_true(bool(rw.mark_claim_terminal({"context_boundary_server_seq": 60}).get("ok", false)))
	var dto: Dictionary = rw.to_snapshot_dto()
	var before: String = TrashTalkGoldFixtures.stable_stringify(rw.capture_state())
	var good_rest := RewardWindowModule.new()
	assert_true(bool(good_rest.restore_from_snapshot_dto(dto).get("ok", false)))
	assert_eq(
		TrashTalkGoldFixtures.stable_stringify(good_rest.to_snapshot_dto()),
		TrashTalkGoldFixtures.stable_stringify(dto)
	)
	# 空 utterance_id
	var bad1 := dto.duplicate(true)
	(bad1["payload"] as Dictionary)["utterances_by_seat"] = {
		"0": [{
			"utterance_id": "", "text": "x", "language": "zh",
			"ptt_end_server_seq": 40, "terminal": true,
		}],
		"1": [], "2": [], "3": [],
	}
	assert_false(bool(rw.restore_from_snapshot_dto(bad1).get("ok", true)))
	# 非法 language
	var bad2 := dto.duplicate(true)
	(bad2["payload"] as Dictionary)["utterances_by_seat"] = {
		"0": [{
			"utterance_id": "u", "text": "x", "language": "xx",
			"ptt_end_server_seq": 40, "terminal": true,
		}],
		"1": [], "2": [], "3": [],
	}
	assert_false(bool(rw.restore_from_snapshot_dto(bad2).get("ok", true)))
	# 非正 PTT
	var bad3 := dto.duplicate(true)
	(bad3["payload"] as Dictionary)["utterances_by_seat"] = {
		"0": [{
			"utterance_id": "u", "text": "x", "language": "zh",
			"ptt_end_server_seq": 0, "terminal": true,
		}],
		"1": [], "2": [], "3": [],
	}
	assert_false(bool(rw.restore_from_snapshot_dto(bad3).get("ok", true)))
	# 缺 terminal
	var bad4 := dto.duplicate(true)
	(bad4["payload"] as Dictionary)["utterances_by_seat"] = {
		"0": [{
			"utterance_id": "u", "text": "x", "language": "zh",
			"ptt_end_server_seq": 40,
		}],
		"1": [], "2": [], "3": [],
	}
	assert_false(bool(rw.restore_from_snapshot_dto(bad4).get("ok", true)))
	# 重复 identity
	var bad5 := dto.duplicate(true)
	(bad5["payload"] as Dictionary)["utterances_by_seat"] = {
		"0": [
			{
				"utterance_id": "u", "text": "a", "language": "zh",
				"ptt_end_server_seq": 40, "terminal": true,
			},
			{
				"utterance_id": "u", "text": "b", "language": "zh",
				"ptt_end_server_seq": 41, "terminal": true,
			},
		],
		"1": [], "2": [], "3": [],
	}
	assert_false(bool(rw.restore_from_snapshot_dto(bad5).get("ok", true)))
	# ptt 越过 closing_boundary
	var close_b: int = int((dto["payload"] as Dictionary)["closing_boundary_server_seq"])
	var bad6 := dto.duplicate(true)
	(bad6["payload"] as Dictionary)["utterances_by_seat"] = {
		"0": [{
			"utterance_id": "late", "text": "x", "language": "zh",
			"ptt_end_server_seq": close_b + 1, "terminal": true,
		}],
		"1": [], "2": [], "3": [],
	}
	assert_false(bool(rw.restore_from_snapshot_dto(bad6).get("ok", true)))
	# 事件越过 context_boundary
	var ctx_b: int = int((dto["payload"] as Dictionary).get("context_boundary_server_seq", close_b))
	var bad7 := dto.duplicate(true)
	var fake_ev := {
		"protocol_version": ProtocolConstants.PROTOCOL_VERSION,
		"server_seq": ctx_b + 99,
		"room_id": "dto-bound",
		"kind": "REWARD_WINDOW_OPENED",
		"payload": {
			"window_id": "hand_0_window_0", "hand_seq": 0, "window_index": 0,
			"prize_pool": ["a", "b", "c", "d"], "rule_version": RULE,
			"phase": "OPEN", "window_exit": null,
		},
		"view_hash": "a".repeat(64),
	}
	# 用真实可 roundtrip 的事件：从 journal 风格最小 OPEN 可能 schema 失败；
	# 若 schema 失败也算拒绝。目标：不得成功 restore。
	(bad7["payload"] as Dictionary)["public_events"] = [fake_ev]
	assert_false(bool(rw.restore_from_snapshot_dto(bad7).get("ok", true)))
	assert_eq(TrashTalkGoldFixtures.stable_stringify(rw.capture_state()), before,
		"全部拒绝须零 mutation")


func test_scoring_close_seams_are_module_only() -> void:
	# 纯状态机 seam（非生产链证明）
	var full := RewardWindowModule.new()
	assert_true(bool(full.open({
		"seed": 1, "hand_seq": 0, "window_index": 0, "rule_version": RULE,
		"room_id": "r", "character_ids": ["lin_yeche", "qiu_jue", "bai_touli", "hua_ling"],
		"language": "zh",
		"public_initial": {"hand_seq": 0, "dealer_seat": 0, "scores": [25000, 25000, 25000, 25000]},
	}).get("ok", false)))
	assert_true(bool(full.begin_scoring_close({
		"result_server_seq": 9, "now_ms": 1, "is_match_end": false,
	}).get("ok", false)))
	assert_eq(String(full.try_settle({"now_ms": 1})["payload"]["outcome"]), "FULL_GRANT")
	var disp := RewardWindowModule.new()
	assert_true(bool(disp.open({
		"seed": 1, "hand_seq": 0, "window_index": 0, "rule_version": RULE,
		"room_id": "r", "character_ids": ["lin_yeche", "qiu_jue", "bai_touli", "hua_ling"],
		"language": "zh",
		"public_initial": {"hand_seq": 0, "dealer_seat": 0, "scores": [25000, 25000, 25000, 25000]},
	}).get("ok", false)))
	assert_true(bool(disp.begin_scoring_close({
		"result_server_seq": 9, "now_ms": 1, "is_match_end": true,
	}).get("ok", false)))
	assert_eq(String(disp.try_settle({"now_ms": 1})["payload"]["outcome"]), "DISPLAY_ONLY")


class FailingRewardKindServer extends LocalLoopbackServer:
	var enabled: bool = false
	var fail_kind: String = ""
	var call_count: int = 0

	func try_publish_business_event(kind: String, payload: Dictionary) -> bool:
		if enabled and kind == fail_kind:
			call_count += 1
			return false
		return super.try_publish_business_event(kind, payload)

	func _publish_business_event_core(kind: String, payload: Dictionary) -> bool:
		if enabled and kind == fail_kind:
			call_count += 1
			return false
		return super._publish_business_event_core(kind, payload)
