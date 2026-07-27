extends GutTest

# 麻将王 — M7：HAITEI / HOUTEI 事件 emit + game_ctx 标志接通验证。
# E2-02：canonical live-wall fixture + 统一 Action / DecisionWindow。
# 禁止 apply_ron / is_houtei 布尔参数 / 伪造 CLAIM·WIN / 无 iid 的 Tile.new /
# 直接写 _draw_index 模拟空墙。HOUTEI 仅由 live_wall_size()==0 自动推导。

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


## 清空 active hand/river/meld，draw_index 回绕到 0，
## 非 dead-wall 区全部回到 live 未摸池（实体唯一，无复制）。
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
	var peeked: Tile = w.peek_next_draw()
	assert_not_null(peeked, "peek_next_draw 必须非 null")
	assert_true(peeked == next, "peek_next_draw 必须是目标实体")
	assert_eq(int(peeked.instance_id), iid)
	assert_eq(int(peeked.id), int(tid))
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


## 真实 wall.draw 推进，使 live 恰剩 1 张且该张为 canonical tid（不直接写 _draw_index 空墙）。
func _drain_live_until_one_next(bc: BattleController, next_tid: int) -> Tile:
	var w: Wall = bc.state.wall
	assert_gt(w.live_wall_size(), 1, "drain 前 live 必须 >1")
	# 先把目标 swap 到 live 末槽，再真实 draw 掉前面的，保证最后一张是目标
	var live_idx: int = _find_live_index(w, next_tid)
	assert_true(live_idx >= 0, "live 区无 id=%d 可保留为 last draw" % next_tid)
	var last_i: int = _live_end(w) - 1
	if live_idx != last_i:
		assert_true(w.swap_live_indices(last_i, live_idx))
	while w.live_wall_size() > 1:
		var drained: Tile = w.draw()
		assert_not_null(drained, "drain live 时 draw 不得 null")
	assert_eq(w.live_wall_size(), 1, "drain 后 live 恰剩 1")
	var next: Tile = w.peek_next_draw()
	assert_not_null(next)
	assert_eq(int(next.id), int(next_tid), "last live 必须是目标 tid")
	var iid: int = int(next.instance_id)
	assert_true(Tile.is_instance_id_in_hand_seq(iid, bc.state.hand_seq))
	assert_eq(iid_slots_in_live(w, iid), 1)
	assert_eq(obj_slots_in_live(w, next), 1)
	_assert_iid_absent_from_active_zones(bc, iid)
	_used_wall_iids[iid] = true
	return next


func iid_slots_in_live(w: Wall, iid: int) -> int:
	var n: int = 0
	for i in range(w.draw_index(), _live_end(w)):
		var t: Tile = w.authority_tiles()[i]
		if t != null and int(t.instance_id) == iid:
			n += 1
	return n


func obj_slots_in_live(w: Wall, obj: Tile) -> int:
	var n: int = 0
	for i in range(w.draw_index(), _live_end(w)):
		if w.authority_tiles()[i] == obj:
			n += 1
	return n


## 真实 wall.draw 排空剩余 live pool（禁止直接写 _draw_index 模拟空墙）。
func _drain_live_to_empty(bc: BattleController) -> void:
	var w: Wall = bc.state.wall
	while w.live_wall_size() > 0:
		var drained: Tile = w.draw()
		assert_not_null(drained, "排空 live 时 draw 不得 null")
	assert_eq(w.live_wall_size(), 0, "live 必须排空")


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
func _discard_then_claim_responses(
	bc: BattleController, discarder: int, discard_tile: Tile, responses: Dictionary
) -> void:
	var hs: int = bc.state.hand_seq
	var turn_ctx: DecisionContext = bc.decision_context_for_seat(discarder)
	assert_not_null(turn_ctx, "TURN DecisionContext 必须存在")
	assert_eq(turn_ctx.window_kind, "TURN")
	assert_true(turn_ctx.has_kind("DISCARD"), "TURN 必须 offer DISCARD")
	var disc_cmd: String = _cmd()
	assert_true(ProtocolUuid.is_canonical_v4(disc_cmd), "command_id 必须 canonical v4")
	var disc_act: Action = Action.discard(
		discarder, discard_tile.instance_id, ROOM, disc_cmd,
		turn_ctx.decision_id, hs, _cmd_seq
	)
	assert_eq(disc_act.hand_seq, hs)
	assert_eq(disc_act.decision_id, turn_ctx.decision_id)
	assert_eq(disc_act.client_seq, _cmd_seq)
	var disc_res: ActionResolution = bc.apply_action(disc_act, ActionSource.HUMAN)
	assert_true(disc_res.accepted, "DISCARD Action 必须 accepted")
	assert_eq(bc.state.phase, BattlePhase.Kind.CLAIM, "弃牌后 phase=CLAIM")

	for offset in range(1, 4):
		var s: int = (discarder + offset) % 4
		var ctx: DecisionContext = bc.decision_context_for_seat(s)
		assert_not_null(ctx, "CLAIM DecisionContext seat=%d" % s)
		assert_eq(ctx.window_kind, "CLAIM")
		var kind: String = str(responses.get(s, "PASS"))
		var cmd: String = _cmd()
		assert_true(ProtocolUuid.is_canonical_v4(cmd), "CLAIM command_id 必须 canonical v4")
		var act: Action
		if kind == "RON":
			assert_true(ctx.has_kind("RON"), "seat%d 必须 offer RON" % s)
			act = Action.ron(s, ROOM, cmd, ctx.decision_id, hs, _cmd_seq)
		else:
			act = Action.make_pass(s, ROOM, cmd, ctx.decision_id, hs, _cmd_seq)
		assert_eq(act.hand_seq, hs)
		assert_eq(act.decision_id, ctx.decision_id)
		assert_eq(act.client_seq, _cmd_seq)
		var r: ActionResolution = bc.apply_action(act, ActionSource.HUMAN)
		assert_true(r.accepted, "CLAIM %s seat%d 必须 accepted" % [kind, s])


func _events_of_type(events: Array, type: StringName) -> Array:
	var out: Array = []
	for ev in events:
		if ev.type == type:
			out.append(ev)
	return out


## 事件链可能在 WIN 后追加 SKILL_TRIGGERED；取唯一指定类型事件。
func _unique_event(events: Array, type: StringName) -> BattleEvent:
	var found: Array = _events_of_type(events, type)
	assert_eq(found.size(), 1, "应恰有 1 个 %s 事件，实际 %d" % [type, found.size()])
	return found[0] as BattleEvent


# ---- HAITEI: 自摸最后一张（live 恰剩 1 + 真实 TSUMO）----

func test_haitei_emitted_on_last_tile_tsumo() -> void:
	var bc: BattleController = _bc as BattleController
	_prepare_live_fixture(bc)
	bc.state.seats[0].hand = _hand_from_live(bc, _chiitoi_tenpai_ids())
	# 避免天和役满干扰七対子 + 海底番基线
	bc.state.first_round_active = false
	_drain_live_until_one_next(bc, TileId.W9)
	assert_eq(bc.state.wall.live_wall_size(), 1, "收摸前 live 恰 1（海底条件）")

	var result: Dictionary = bc.run_to_end()
	assert_true(bc._settled, "对局应 settled")
	var win_ev: BattleEvent = _unique_event(result.events, &"WIN_DECLARED")
	assert_eq(win_ev.actor_seat, 0, "自摸者 seat 0")

	var haitei_ev: BattleEvent = _unique_event(result.events, &"HAITEI")
	assert_eq(haitei_ev.actor_seat, 0, "HAITEI 主体是自摸者 seat 0")

	# 七対子 2 + 门前清自摸 1 + 海底 1 ≥ 3
	assert_gt(int(win_ev.extra.han), 2, "haitei 应被算进总番（七対子+海底 ≥ 3）")


func test_no_haitei_when_wall_not_drained() -> void:
	var bc: BattleController = _bc as BattleController
	_prepare_live_fixture(bc)
	bc.state.seats[0].hand = _hand_from_live(bc, _chiitoi_tenpai_ids())
	bc.state.first_round_active = false
	_set_next_draw(bc, TileId.W9)
	assert_gt(bc.state.wall.live_wall_size(), 1, "负例 live 必须 >1（非海底）")

	var result: Dictionary = bc.run_to_end()
	assert_true(bc._settled, "对局应 settled")
	var win_ev: BattleEvent = _unique_event(result.events, &"WIN_DECLARED")
	assert_eq(win_ev.actor_seat, 0)

	var haitei_evs: Array = _events_of_type(result.events, &"HAITEI")
	assert_eq(haitei_evs.size(), 0, "wall 未空 → 不应 emit HAITEI")


# ---- HOUTEI: 真实 DISCARD → CLAIM RON，live_wall_size==0 自动推导 ----

func test_houtei_emitted_when_live_wall_empty_on_ron() -> void:
	var bc: BattleController = _bc as BattleController
	_prepare_live_fixture(bc)
	bc.state.seats[0].hand = _hand_from_live(bc, _chiitoi_tenpai_ids())
	bc.state.seats[0].furiten = FuritenState.new()
	bc.state.first_round_active = false

	var disc: Tile = _setup_discarder_turn(bc, 1, TileId.W9)
	assert_true(ClaimValidator.can_ron(
		bc.state.seats[0].hand, bc.state.seats[0].melds.all(), disc, bc.state.seats[0].furiten),
		"seat0 必须真实可荣 disc.iid=%d" % disc.instance_id)

	# 手牌/弃牌 fixture 完成后真实排空 live；HOUTEI 仅由此推导
	_drain_live_to_empty(bc)
	assert_eq(bc.state.wall.live_wall_size(), 0, "正例收窗前 live 必须为 0")

	_discard_then_claim_responses(bc, 1, disc, {0: "RON", 2: "PASS", 3: "PASS"})

	assert_true(bc._settled, "RON 结算后应 settled")
	var win_ev: BattleEvent = _unique_event(bc.events, &"WIN_DECLARED")
	assert_eq(win_ev.actor_seat, 0, "胡牌者 seat 0")

	var houtei_ev: BattleEvent = _unique_event(bc.events, &"HOUTEI")
	assert_eq(houtei_ev.actor_seat, 0, "HOUTEI 主体是胡牌者 seat 0")
	# 七対子 2 + 河底 1 ≥ 3
	assert_gt(int(win_ev.extra.han), 2, "houtei 应被算进总番（七対子+河底 ≥ 3）")


func test_no_houtei_when_live_wall_not_empty_on_ron() -> void:
	var bc: BattleController = _bc as BattleController
	_prepare_live_fixture(bc)
	bc.state.seats[0].hand = _hand_from_live(bc, _chiitoi_tenpai_ids())
	bc.state.seats[0].furiten = FuritenState.new()
	bc.state.first_round_active = false

	var disc: Tile = _setup_discarder_turn(bc, 1, TileId.W9)
	assert_true(ClaimValidator.can_ron(
		bc.state.seats[0].hand, bc.state.seats[0].melds.all(), disc, bc.state.seats[0].furiten),
		"seat0 必须真实可荣")
	assert_gt(bc.state.wall.live_wall_size(), 0, "负例 live 必须 >0（非河底）")

	_discard_then_claim_responses(bc, 1, disc, {0: "RON", 2: "PASS", 3: "PASS"})

	assert_true(bc._settled, "RON 结算后应 settled")
	var win_ev: BattleEvent = _unique_event(bc.events, &"WIN_DECLARED")
	assert_eq(win_ev.actor_seat, 0)

	var houtei_evs: Array = _events_of_type(bc.events, &"HOUTEI")
	assert_eq(houtei_evs.size(), 0, "live>0 → 不应 emit HOUTEI")


# ---- HAITEI hook 真生效（boss3_kanmon force_yakuman）----

func test_haitei_hook_han_applied_to_score() -> void:
	var bc: BattleController = _bc as BattleController
	_prepare_live_fixture(bc)
	BossAbilityFactory.inject(bc.registry, &"boss3_kanmon_v1", 0)

	bc.state.seats[0].hand = _hand_from_live(bc, _chiitoi_tenpai_ids())
	bc.state.first_round_active = false
	_drain_live_until_one_next(bc, TileId.W9)
	assert_eq(bc.state.wall.live_wall_size(), 1)

	var result: Dictionary = bc.run_to_end()
	assert_true(bc._settled, "对局应 settled")
	var win_ev: BattleEvent = _unique_event(result.events, &"WIN_DECLARED")
	assert_eq(win_ev.actor_seat, 0)
	_unique_event(result.events, &"HAITEI")  # hook 触发前提

	# boss3_kanmon v2：HAITEI 自胡 → force_yakuman；役满路径反映在倍数与点数
	assert_gte(int(win_ev.extra.yakuman_multiplier), 1,
		"boss3_kanmon 应 force_yakuman（yakuman_multiplier≥1）")
	assert_gt(int(win_ev.extra.points_won), 0, "役满结算 points_won 必须 >0")
	# 相对无 hook 七対子基线（约 2~4 番），役满 base 显著更高
	assert_gt(int(win_ev.extra.base_points), 2000,
		"boss3_kanmon 役满 base_points 应高于普通七対子满贯以下")
