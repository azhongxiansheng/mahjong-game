extends GutTest

# 里程碑 2 — 端到端集成测试。
# 验证 BattleController 把 TurnEngine + SkillScheduler + 规则引擎串成可跑的一局。
# E2-02：RON 走真实 TURN DISCARD → CLAIM DecisionWindow → RON/PASS apply_action；
# 禁止 apply_ron / _apply_ron_private / 伪造 CLAIM 状态 / 无 iid 的 Tile.new。
# fixture 实体只从 live 未摸区 swap + wall.draw() 消耗，禁止引用已发到他手的 iid。

const SealChunHook := preload("res://skills/hooks/seal_chun_hook.gd")
const ROOM := "local"
const CMD_PREFIX := "550e8400-e29b-41d4-a716-"

var _bc: IBattleController
var _used_wall_iids: Dictionary = {}
var _cmd_seq: int = 0


func before_each() -> void:
	_bc = BattleController.new(42, 0)
	_used_wall_iids.clear()
	_cmd_seq = 0


func _cmd() -> String:
	_cmd_seq += 1
	return "%s%012d" % [CMD_PREFIX, _cmd_seq]


func _chiitoi_tenpai_ids() -> Array:
	return [
		TileId.W1, TileId.W1, TileId.W2, TileId.W2, TileId.W3, TileId.W3,
		TileId.W5, TileId.W5, TileId.W6, TileId.W6, TileId.W7, TileId.W7,
		TileId.W9,
	]


func _noise_13() -> Array:
	return [
		TileId.W2, TileId.W3, TileId.W4, TileId.W6, TileId.W8,
		TileId.T1, TileId.T2, TileId.T3, TileId.T4, TileId.T5,
		TileId.E, TileId.S_WIND, TileId.W_WIND,
	]


func _live_end(w: Wall) -> int:
	return w.authority_tiles().size() - w.dead_wall_size()


## 清空 active hand/river/meld，并把 draw_index 回绕到 0，
## 使非 dead-wall 区全部回到 live 未摸池（实体仍唯一，无复制）。
func _prepare_live_fixture(bc: BattleController) -> void:
	for s in range(4):
		var seat: Seat = bc.state.seats[s]
		seat.hand = Hand.new()
		seat.melds.restore([], 0)
		seat.last_drawn_instance_id = Tile.INVALID_INSTANCE_ID
		seat.furiten = FuritenState.new()
		bc.state.seats[s].river.restore([])
	bc.state.wall.set_draw_index(0)
	_used_wall_iids.clear()


func _assert_iid_absent_from_active_zones(
	bc: BattleController, iid: int, except_seat: int = -1
) -> void:
	for s in range(4):
		if s == except_seat:
			continue
		var seat: Seat = bc.state.seats[s]
		for t in seat.hand.tiles():
			if t == null:
				continue
			assert_ne(int(t.instance_id), iid,
				"iid=%d 不得仍在 seat%d hand" % [iid, s])
		for m in seat.melds.all():
			if m == null:
				continue
			for t2 in m.tiles:
				if t2 == null:
					continue
				assert_ne(int(t2.instance_id), iid,
					"iid=%d 不得仍在 seat%d meld" % [iid, s])
		for t3 in bc.state.seats[s].river.tiles():
			if t3 == null:
				continue
			assert_ne(int(t3.instance_id), iid,
				"iid=%d 不得仍在 seat%d river" % [iid, s])


func _find_live_index(w: Wall, tid: int) -> int:
	var end_i: int = _live_end(w)
	for i in range(w.draw_index(), end_i):
		var t: Tile = w.authority_tiles()[i]
		if t == null or int(t.id) != int(tid):
			continue
		var iid: int = int(t.instance_id)
		if _used_wall_iids.has(iid):
			continue
		return i
	return -1


func _swap_live_to_draw_index(w: Wall, live_idx: int) -> void:
	assert_gte(live_idx, w.draw_index())
	assert_lt(live_idx, _live_end(w))
	assert_true(w.move_live_index_to_top(live_idx))


## 从 live 未摸区找 tid：swap 到 _draw_index 后真实 wall.draw() 消耗。
func _draw_from_live(bc: BattleController, tid: int) -> Tile:
	assert_not_null(bc)
	assert_not_null(bc.state)
	var w: Wall = bc.state.wall
	assert_not_null(w)
	var live_idx: int = _find_live_index(w, tid)
	assert_true(live_idx >= 0, "live 未摸区无剩余 id=%d 的 canonical 实体" % tid)
	_swap_live_to_draw_index(w, live_idx)
	var selected: Tile = w.authority_tiles()[w.draw_index()]
	assert_not_null(selected)
	var iid: int = int(selected.instance_id)
	assert_true(Tile.is_instance_id_in_hand_seq(iid, bc.state.hand_seq),
		"wall tile 必须在本局 hand_seq 命名空间 iid=%d" % iid)
	_assert_iid_absent_from_active_zones(bc, iid)
	var drawn: Tile = w.draw()
	assert_not_null(drawn, "wall.draw() 必须消耗 live 顶")
	assert_true(drawn == selected, "draw 必须返回 swap 后的同一实体对象")
	assert_eq(int(drawn.instance_id), iid)
	_used_wall_iids[iid] = true
	_assert_iid_absent_from_active_zones(bc, iid)
	return drawn


## 只把目标 swap 到 _draw_index，不 draw；供下一次 engine.draw 真正消费。
func _set_next_draw(bc: BattleController, tid: int) -> Tile:
	var w: Wall = bc.state.wall
	var live_idx: int = _find_live_index(w, tid)
	assert_true(live_idx >= 0, "live 未摸区无剩余 id=%d 作 next draw" % tid)
	_swap_live_to_draw_index(w, live_idx)
	var next: Tile = w.authority_tiles()[w.draw_index()]
	assert_not_null(next)
	var iid: int = int(next.instance_id)
	assert_true(Tile.is_instance_id_in_hand_seq(iid, bc.state.hand_seq))
	# live 区内该 iid 唯一，且无复制对象槽位
	var iid_slots: int = 0
	var same_obj_slots: int = 0
	for i in range(w.draw_index(), _live_end(w)):
		var t: Tile = w.authority_tiles()[i]
		if t == null:
			continue
		if int(t.instance_id) == iid:
			iid_slots += 1
		if t == next:
			same_obj_slots += 1
	assert_eq(iid_slots, 1, "next draw iid=%d 在 live 区必须唯一" % iid)
	assert_eq(same_obj_slots, 1, "next draw 实体对象在 live 区不得重复引用")
	# peek 下一次 draw 即该实体
	assert_true(w.authority_tiles()[w.draw_index()] == next, "peek live 顶必须是目标实体")
	assert_eq(int(w.authority_tiles()[w.draw_index()].instance_id), iid)
	_assert_iid_absent_from_active_zones(bc, iid)
	_used_wall_iids[iid] = true
	return next


func _hand_from_live(bc: BattleController, ids: Array) -> Hand:
	var h := Hand.new()
	for tid in ids:
		var t: Tile = _draw_from_live(bc, int(tid))
		assert_not_null(t)
		assert_true(h.add(t), "hand 加入 live draw 实体失败 iid=%d" % t.instance_id)
	return h


## 弃牌者进入真实 TURN（DISCARD phase + 14 张含目标牌），返待弃实体。
func _setup_discarder_turn(bc: BattleController, discarder: int, discard_tid: int) -> Tile:
	var ids: Array = _noise_13().duplicate()
	ids.append(discard_tid)
	bc.state.seats[discarder].hand = _hand_from_live(bc, ids)
	var disc: Tile = null
	for t in bc.state.seats[discarder].hand.tiles():
		if t != null and int(t.id) == int(discard_tid):
			disc = t
			break
	assert_not_null(disc, "弃牌者手中必须有目标牌")
	_assert_iid_absent_from_active_zones(bc, disc.instance_id, discarder)
	bc.state.seats[discarder].last_drawn_instance_id = disc.instance_id
	bc.state.current_seat = discarder
	bc.state.phase = BattlePhase.Kind.DISCARD
	return disc


## 真实 DISCARD → 对所有非弃牌座提交 RON/PASS 收窗。
## responses: seat -> "RON" | "PASS"
func _discard_then_claim_responses(
	bc: BattleController, discarder: int, discard_tile: Tile, responses: Dictionary
) -> void:
	var hs: int = bc.state.hand_seq
	var turn_ctx: DecisionContext = bc.decision_context_for_seat(discarder)
	assert_not_null(turn_ctx, "TURN DecisionContext 必须存在")
	assert_eq(turn_ctx.window_kind, "TURN")
	assert_true(turn_ctx.has_kind("DISCARD"), "TURN 必须 offer DISCARD")
	var disc_act: Action = Action.discard(
		discarder, discard_tile.instance_id, ROOM, _cmd(),
		turn_ctx.decision_id, hs, _cmd_seq
	)
	var disc_res: ActionResolution = bc.apply_action(disc_act, ActionSource.HUMAN)
	assert_true(disc_res.accepted, "DISCARD Action 必须 accepted")
	assert_eq(bc.state.phase, BattlePhase.Kind.CLAIM, "弃牌后 phase=CLAIM")

	for offset in range(1, 4):
		var s: int = (discarder + offset) % 4
		var ctx: DecisionContext = bc.decision_context_for_seat(s)
		assert_not_null(ctx, "CLAIM DecisionContext seat=%d" % s)
		assert_eq(ctx.window_kind, "CLAIM")
		var kind: String = str(responses.get(s, "PASS"))
		var act: Action
		if kind == "RON":
			assert_true(ctx.has_kind("RON"), "seat%d 必须 offer RON" % s)
			act = Action.ron(s, ROOM, _cmd(), ctx.decision_id, hs, _cmd_seq)
		else:
			act = Action.make_pass(s, ROOM, _cmd(), ctx.decision_id, hs, _cmd_seq)
		var r: ActionResolution = bc.apply_action(act, ActionSource.HUMAN)
		assert_true(r.accepted, "CLAIM %s seat%d 必须 accepted" % [kind, s])


# ---- 路径 A：跑到底不崩 ----
func test_path_a_runs_full_hand_without_crash() -> void:
	var result: Dictionary = _bc.run_to_end()

	var allowed: Array = [&"EXHAUSTIVE_DRAW", &"WIN_DECLARED"]
	assert_true(allowed.has(result.last_event),
		"最末事件应是流局或胡牌，实际：%s" % result.last_event)

	var total: int = 0
	for s in _bc.state.scores:
		total += s
	assert_eq(total, 100000, "scores 总和应守恒为 100000")

	assert_eq(_bc.state.event_chain_depth, 0,
		"事件链深度在 run_to_end 退出时应归零")

	assert_gt(result.events.size(), 0, "至少要有一个事件被 emit")
	assert_eq(result.events[0].type, &"GAME_BEGIN",
		"首事件必须是 GAME_BEGIN")


# ---- 路径 B：自摸结算 ----
func test_path_b_tsumo_settles_with_payout() -> void:
	var bc: BattleController = _bc as BattleController
	_prepare_live_fixture(bc)
	bc.state.seats[0].hand = _hand_from_live(bc, _chiitoi_tenpai_ids())
	# 避免天和役满干扰七対子基线断言（仍走真实 TSUMO offer / run_to_end）
	bc.state.first_round_active = false
	_set_next_draw(bc, TileId.W9)

	var result: Dictionary = bc.run_to_end()

	assert_eq(result.last_event, &"WIN_DECLARED",
		"自摸命中后最末事件应为 WIN_DECLARED，实际：%s" % result.last_event)
	var win_event: BattleEvent = result.events[result.events.size() - 1]
	assert_eq(win_event.actor_seat, 0, "胡牌座位应为 0")
	var extra: Dictionary = win_event.extra
	assert_true(extra.has("payout"), "WIN_DECLARED.extra 必含 payout 字典")
	assert_true(extra.has("winner_seat"), "WIN_DECLARED.extra 必含 winner_seat")
	assert_eq(extra.winner_seat, 0)
	assert_gt(extra.han, 0, "han 应为正（七対子至少 2 番）")
	assert_gt(extra.payout.size(), 0, "payout 至少含 1 个支付者")


# ---- 路径 C：荣胡 — owner / holder 归属 ----
# seat 0 听 W9；seat 1 经真实 TURN DISCARD 打出本局 W9 → CLAIM 窗 RON。
func test_path_c_ron_owner_holder_distinction() -> void:
	var bc: BattleController = _bc as BattleController
	_prepare_live_fixture(bc)
	bc.state.seats[0].hand = _hand_from_live(bc, _chiitoi_tenpai_ids())
	bc.state.seats[0].furiten = FuritenState.new()

	var disc: Tile = _setup_discarder_turn(bc, 1, TileId.W9)
	assert_true(ClaimValidator.can_ron(
		bc.state.seats[0].hand, bc.state.seats[0].melds.all(), disc, bc.state.seats[0].furiten),
		"seat0 必须真实可荣 disc.iid=%d" % disc.instance_id)

	_discard_then_claim_responses(bc, 1, disc, {0: "RON", 2: "PASS", 3: "PASS"})

	assert_eq(bc._last_event_type, &"WIN_DECLARED",
		"CLAIM RON 成功后最末事件应为 WIN_DECLARED")
	var win_event: BattleEvent = bc.events[bc.events.size() - 1]
	assert_eq(win_event.actor_seat, 0, "actor 是胡牌人")
	assert_ne(win_event.tile_anchor.owner_seat, win_event.actor_seat,
		"owner（弃牌人 1）必须 ≠ actor（胡牌人 0）— 这是 spec §3.1 的 owner/holder 区分核心")
	assert_eq(win_event.tile_anchor.owner_seat, 1, "owner 应等于弃牌人座 1")

	var has_ron_event := false
	for ev in bc.events:
		if ev.type == &"RON_DECLARED":
			assert_eq(ev.actor_seat, 0, "RON_DECLARED actor 也是胡牌人")
			assert_eq(ev.tile_anchor.owner_seat, 1, "RON_DECLARED owner 也是弃牌人")
			has_ron_event = true
	assert_true(has_ron_event, "结算前必须 emit 一次 RON_DECLARED")


# ---- 路径 D：cancel_ron 技能干预 ----
func test_path_d_seal_chun_cancels_ron() -> void:
	var bc: BattleController = _bc as BattleController
	_prepare_live_fixture(bc)
	bc.state.seats[0].hand = _hand_from_live(bc, _chiitoi_tenpai_ids())
	bc.state.seats[0].furiten = FuritenState.new()

	var skill := SkillResource.new()
	skill.id = &"seal_chun_v1"
	skill.attached_tile = TileId.CHUN
	skill.rarity = 2
	var ot: Array[StringName] = [&"RON_DECLARED"]
	skill.owner_triggers = ot
	skill.hook_script = SealChunHook
	var skill_ti := TileSkillAnchor.make(_draw_from_live(bc, TileId.CHUN), 1, skill)
	bc.registry.register(skill, skill_ti)

	var disc: Tile = _setup_discarder_turn(bc, 1, TileId.W9)
	assert_true(ClaimValidator.can_ron(
		bc.state.seats[0].hand, bc.state.seats[0].melds.all(), disc, bc.state.seats[0].furiten),
		"seat0 必须真实可荣")

	_discard_then_claim_responses(bc, 1, disc, {0: "RON", 2: "PASS", 3: "PASS"})

	assert_true(bc.state.ron_cancelled[0],
		"BattleState.ron_cancelled[0] 应被 SkillCtx.cancel_ron 写为 true")
	assert_ne(bc._last_event_type, &"WIN_DECLARED",
		"最末事件不应是 WIN_DECLARED — 结算被技能取消")
	assert_false(bc._settled, "_settled 应仍为 false — 对局可继续")
	assert_true(skill.consumed, "中·封印一次性触发后应被消耗")
	var ron_count := 0
	for ev in bc.events:
		if ev.type == &"RON_DECLARED":
			ron_count += 1
	assert_eq(ron_count, 1, "RON_DECLARED 应被 emit 1 次")
