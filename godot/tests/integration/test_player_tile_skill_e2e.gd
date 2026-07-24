extends GutTest

# 麻将王 — M7 玩家 tile skill 端到端集成测试。
# E2-02：统一真实 Action / DecisionWindow 路径。
# fixture 实体只从 live 未摸区 swap + wall.draw() 消耗；禁止 apply_ron /
# 伪造 CLAIM / 无 iid Tile.new / 把 events[-1] 误当 WIN_DECLARED。

const ROOM := "local"
const CMD_PREFIX := "550e8400-e29b-41d4-a716-"
const SEED := 42

var _used_wall_iids: Dictionary = {}
var _cmd_seq: int = 0


func before_each() -> void:
	_used_wall_iids.clear()
	_cmd_seq = 0


func _cmd() -> String:
	_cmd_seq += 1
	return "%s%012d" % [CMD_PREFIX, _cmd_seq]


func _chiitoi_tenpai_ids() -> Array:
	# 听 W9 单骑七对；不含 W5 对，便于 thunder 独立 live-draw W5 作 registry anchor。
	return [
		TileId.W1, TileId.W1, TileId.W2, TileId.W2, TileId.W3, TileId.W3,
		TileId.W4, TileId.W4, TileId.W6, TileId.W6, TileId.W7, TileId.W7,
		TileId.W9,
	]


func _noise_13() -> Array:
	return [
		TileId.W2, TileId.W3, TileId.W4, TileId.W6, TileId.W8,
		TileId.T1, TileId.T2, TileId.T3, TileId.T4, TileId.T5,
		TileId.E, TileId.S_WIND, TileId.W_WIND,
	]


func _live_end(w: Wall) -> int:
	return w._tiles.size() - w._dead_wall_size


## 清空 active hand/river/meld，draw_index 回绕到 0，
## 使非 dead-wall 区全部回到 live 未摸池（实体仍唯一，无复制）。
func _prepare_live_fixture(bc: BattleController) -> void:
	for s in range(4):
		var seat: Seat = bc.state.seats[s]
		seat.hand = Hand.new()
		seat.melds = []
		seat.last_drawn_instance_id = Tile.INVALID_INSTANCE_ID
		seat.furiten = FuritenState.new()
		bc.state.discards_per_seat[s] = []
	bc.state.wall._draw_index = 0
	_used_wall_iids.clear()


func _assert_iid_absent_from_active_zones(
	bc: BattleController, iid: int, except_seat: int = -1
) -> void:
	for s in range(4):
		if s == except_seat:
			continue
		var seat: Seat = bc.state.seats[s]
		for t in seat.hand._tiles:
			if t == null:
				continue
			assert_ne(int(t.instance_id), iid,
				"iid=%d 不得仍在 seat%d hand" % [iid, s])
		for m in seat.melds:
			if m == null:
				continue
			for t2 in m.tiles:
				if t2 == null:
					continue
				assert_ne(int(t2.instance_id), iid,
					"iid=%d 不得仍在 seat%d meld" % [iid, s])
		for t3 in bc.state.discards_per_seat[s]:
			if t3 == null:
				continue
			assert_ne(int(t3.instance_id), iid,
				"iid=%d 不得仍在 seat%d river" % [iid, s])
	for item in bc.state.revealed_tiles:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var raw = (item as Dictionary).get("tile", null)
		if raw is TileInstance and (raw as TileInstance).tile != null:
			assert_ne(int((raw as TileInstance).tile.instance_id), iid,
				"iid=%d 不得仍在 revealed" % iid)
		elif raw is Tile:
			assert_ne(int((raw as Tile).instance_id), iid,
				"iid=%d 不得仍在 revealed" % iid)


func _find_live_index(w: Wall, tid: int) -> int:
	var end_i: int = _live_end(w)
	for i in range(w._draw_index, end_i):
		var t: Tile = w._tiles[i]
		if t == null or int(t.id) != int(tid):
			continue
		var iid: int = int(t.instance_id)
		if _used_wall_iids.has(iid):
			continue
		return i
	return -1


func _swap_live_to_draw_index(w: Wall, live_idx: int) -> void:
	assert_gte(live_idx, w._draw_index)
	assert_lt(live_idx, _live_end(w))
	if live_idx == w._draw_index:
		return
	var tmp: Tile = w._tiles[w._draw_index]
	w._tiles[w._draw_index] = w._tiles[live_idx]
	w._tiles[live_idx] = tmp


## 从 live 未摸区找 tid：swap 到 _draw_index 后真实 wall.draw() 消耗。
func _draw_from_live(bc: BattleController, tid: int) -> Tile:
	assert_not_null(bc)
	assert_not_null(bc.state)
	var w: Wall = bc.state.wall
	assert_not_null(w)
	var live_idx: int = _find_live_index(w, tid)
	assert_true(live_idx >= 0, "live 未摸区无剩余 id=%d 的 canonical 实体" % tid)
	_swap_live_to_draw_index(w, live_idx)
	var selected: Tile = w._tiles[w._draw_index]
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
	var next: Tile = w._tiles[w._draw_index]
	assert_not_null(next)
	var iid: int = int(next.instance_id)
	assert_true(Tile.is_instance_id_in_hand_seq(iid, bc.state.hand_seq))
	# live 区内该 iid 唯一，且无复制对象槽位
	var iid_slots: int = 0
	var same_obj_slots: int = 0
	for i in range(w._draw_index, _live_end(w)):
		var t: Tile = w._tiles[i]
		if t == null:
			continue
		if int(t.instance_id) == iid:
			iid_slots += 1
		if t == next:
			same_obj_slots += 1
	assert_eq(iid_slots, 1, "next draw iid=%d 在 live 区必须唯一" % iid)
	assert_eq(same_obj_slots, 1, "next draw 实体对象在 live 区不得重复引用")
	var peeked: Tile = w.peek_next_draw()
	assert_not_null(peeked, "peek_next_draw 必须非空")
	assert_true(peeked == next, "peek_next_draw 必须指向目标实体")
	assert_eq(int(peeked.instance_id), iid)
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


## 用 live 实体作 skill anchor；register=false 时仍 draw 同 tile 以对齐 wall 消耗。
## 返回 anchor Tile（无论是否 register），供 skill case 断言 registry anchor 不在活动区。
func _consume_skill_anchor_from_live(
	bc: BattleController, variant_id: StringName, register: bool
) -> Tile:
	var sk: SkillResource = TileSkillFactory.build(variant_id)
	assert_not_null(sk, "TileSkillFactory.build(%s) 必须成功" % variant_id)
	var anchor_tile: Tile = _draw_from_live(bc, int(sk.attached_tile))
	assert_not_null(anchor_tile)
	assert_true(Tile.is_instance_id_in_hand_seq(anchor_tile.instance_id, bc.state.hand_seq))
	if not register:
		return anchor_tile
	var ti: TileInstance = TileInstance.make(anchor_tile, 0, sk)
	if not sk.holder_triggers.is_empty():
		ti.holder_seat = 0
	bc.registry.register(sk, ti)
	return anchor_tile


## 严格 ARS roundtrip：capture 非 null；sha256 恰 64 位 lowercase hex；
## restore_into 全新 BattleController 成功；restore 后 re-capture 的 sha256 与原 hash 完全相同。
## 仅 hash 不足——必须 restore 严格校验成功。失败返回 false（安全，不制造无关崩溃）。
## 禁止 has_method / 恒真。
func _authority_snapshot_strict_ok(bc: BattleController) -> bool:
	if bc == null or bc.state == null:
		return false
	var snap: AuthorityReplaySnapshot = AuthorityReplaySnapshot.capture(bc)
	if snap == null:
		return false
	var h: String = snap.sha256()
	if h.length() != 64:
		return false
	if h != h.to_lower():
		return false
	if not h.is_valid_hex_number():
		return false
	var target := BattleController.new(SEED, 0)
	if target == null or target.state == null:
		return false
	if not snap.restore_into(target):
		return false
	var snap2: AuthorityReplaySnapshot = AuthorityReplaySnapshot.capture(target)
	if snap2 == null:
		return false
	if snap2.sha256() != h:
		return false
	return true


## seat0 进入真实 TURN（DISCARD + 14 张含本局 W9），返待弃实体。
func _setup_seat0_discard_w9(bc: BattleController) -> Tile:
	var ids: Array = _noise_13().duplicate()
	ids.append(TileId.W9)
	bc.state.seats[0].hand = _hand_from_live(bc, ids)
	var disc: Tile = null
	for t in bc.state.seats[0].hand._tiles:
		if t != null and int(t.id) == TileId.W9:
			disc = t
			break
	assert_not_null(disc, "seat0 手中必须有本局 canonical W9")
	_assert_iid_absent_from_active_zones(bc, disc.instance_id, 0)
	bc.state.seats[0].last_drawn_instance_id = disc.instance_id
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.DISCARD
	return disc


## 真实 seat0 DISCARD → CLAIM 窗 seat1 RON、其余 eligible PASS。
func _seat0_discard_seat1_ron(bc: BattleController, discard_tile: Tile) -> void:
	var hs: int = bc.state.hand_seq
	var turn_ctx: DecisionContext = bc.decision_context_for_seat(0)
	assert_not_null(turn_ctx, "seat0 TURN DecisionContext 必须存在")
	assert_eq(turn_ctx.window_kind, "TURN")
	assert_true(turn_ctx.has_kind("DISCARD"), "TURN 必须 offer DISCARD")
	var disc_act: Action = Action.discard(
		0, discard_tile.instance_id, ROOM, _cmd(),
		turn_ctx.decision_id, hs, _cmd_seq
	)
	var disc_res: ActionResolution = bc.apply_action(disc_act, ActionSource.HUMAN)
	assert_true(disc_res.accepted, "seat0 DISCARD 必须 accepted")
	assert_eq(bc.state.phase, BattlePhase.Kind.CLAIM, "弃牌后 phase=CLAIM")

	for offset in range(1, 4):
		var s: int = (0 + offset) % 4
		var ctx: DecisionContext = bc.decision_context_for_seat(s)
		assert_not_null(ctx, "CLAIM DecisionContext seat=%d" % s)
		assert_eq(ctx.window_kind, "CLAIM")
		var act: Action
		if s == 1:
			assert_true(ctx.has_kind("RON"), "seat1 必须 offer RON")
			act = Action.ron(s, ROOM, _cmd(), ctx.decision_id, hs, _cmd_seq)
		else:
			act = Action.make_pass(s, ROOM, _cmd(), ctx.decision_id, hs, _cmd_seq)
		var r: ActionResolution = bc.apply_action(act, ActionSource.HUMAN)
		assert_true(r.accepted, "CLAIM seat%d 必须 accepted" % s)


## 扫描事件链：恰好一个 WIN_DECLARED（允许其后有 SKILL_TRIGGERED）。
func _find_unique_win_declared(events: Array) -> BattleEvent:
	var found: BattleEvent = null
	var n: int = 0
	for ev in events:
		if ev is BattleEvent and (ev as BattleEvent).type == &"WIN_DECLARED":
			n += 1
			found = ev as BattleEvent
	assert_eq(n, 1, "事件链必须恰好 1 个 WIN_DECLARED，实际 %d" % n)
	assert_not_null(found)
	return found


## 同 seed / 同 canonical fixture；control 与 skill 对齐 wall 消耗（anchor 均 draw）。
func _run_soul_drain_ron_fixture(with_skill: bool) -> Dictionary:
	_used_wall_iids.clear()
	_cmd_seq = 0
	var bc := BattleController.new(SEED, 0)
	_prepare_live_fixture(bc)
	# 两边都从 live 消耗 HATSU anchor；仅 skill case 注册
	var anchor_tile: Tile = _consume_skill_anchor_from_live(
		bc, &"soul_drain_hatsu_v1", with_skill
	)
	if with_skill:
		assert_not_null(anchor_tile, "skill case registry anchor tile 必须存在")
		var anchor_iid: int = int(anchor_tile.instance_id)
		# registry tile-anchor 不得与 hand/river/meld 活动区重复
		_assert_iid_absent_from_active_zones(bc, anchor_iid)

	bc.state.seats[1].hand = _hand_from_live(bc, _chiitoi_tenpai_ids())
	bc.state.seats[1].furiten = FuritenState.new()

	var disc: Tile = _setup_seat0_discard_w9(bc)
	assert_true(ClaimValidator.can_ron(
		bc.state.seats[1].hand, bc.state.seats[1].melds, disc, bc.state.seats[1].furiten),
		"seat1 必须真实可荣 disc.iid=%d" % disc.instance_id)
	# control / skill：fixture 就绪后、真实 CLAIM 前做 ARS 严格 restore（与 thunder 时机对齐）
	assert_true(
		_authority_snapshot_strict_ok(bc),
		"soul_drain fixture ARS strict restore 必须成功 with_skill=%s" % with_skill
	)

	_seat0_discard_seat1_ron(bc, disc)

	assert_true(bc._settled, "真实 CLAIM RON 后必须 settled")
	var win_ev: BattleEvent = _find_unique_win_declared(bc.events)
	assert_eq(win_ev.actor_seat, 1, "winner 必须是 seat1")
	assert_true(win_ev.extra.has("points_won"), "WIN_DECLARED 必须含 points_won")
	var points_won: int = int(win_ev.extra.points_won)
	assert_gt(points_won, 0, "points_won 必须 > 0")
	var scores: Array = []
	for i in range(4):
		scores.append(int(bc.state.scores[i]))
	return {
		"scores": scores,
		"points_won": points_won,
		"win_event": win_ev,
	}


# ---- soul_drain_hatsu：真实对手 ron 触发转分 ----

func test_soul_drain_transfers_points_when_opponent_rons() -> void:
	# 同 seed/同 fixture：control 无技能 vs skill seat0 持 soul_drain
	var control: Dictionary = _run_soul_drain_ron_fixture(false)
	var skill_case: Dictionary = _run_soul_drain_ron_fixture(true)

	var c0: int = int(control.scores[0])
	var c1: int = int(control.scores[1])
	var s0: int = int(skill_case.scores[0])
	var s1: int = int(skill_case.scores[1])
	var points_won: int = int(skill_case.points_won)
	assert_eq(int(control.points_won), points_won,
		"同 fixture 下 control/skill 的 points_won 必须一致")
	assert_gt(points_won, 0, "真实 ron 必须有正 points_won")

	var fraction: float = BalanceConstants.get_number(&"soul_drain_fraction")
	var expected_xfer: int = int(points_won * fraction)
	assert_gt(expected_xfer, 0, "soul_drain 转分量必须 > 0")

	assert_eq(s0 - c0, expected_xfer,
		"holder seat0 相对 control 应 +points_won*fraction")
	assert_eq(c1 - s1, expected_xfer,
		"winner seat1 相对 control 应 -points_won*fraction")
	assert_gt(s0, c0, "skill case holder 高于 control")
	assert_lt(s1, c1, "skill case winner 低于 control")

	var sum_skill := 0
	for v in skill_case.scores:
		sum_skill += int(v)
	assert_eq(sum_skill, 100000, "soul_drain 转分后总分守恒")
	var sum_ctrl := 0
	for v in control.scores:
		sum_ctrl += int(v)
	assert_eq(sum_ctrl, 100000, "control 总分守恒")


# ---- thunder_5w 自胡 +han ----

func test_thunder_5w_bumps_player_han_on_self_tsumo() -> void:
	_used_wall_iids.clear()
	_cmd_seq = 0
	var bc := BattleController.new(SEED, 0)
	_prepare_live_fixture(bc)
	# 1) 独立 live swap+draw 消费 canonical W5 作 registry-only anchor（不进 hand/river/meld/revealed）
	var anchor_w5: Tile = _consume_skill_anchor_from_live(bc, &"thunder_5w_v1", true)
	assert_not_null(anchor_w5, "thunder W5 anchor 必须 live-draw 成功")
	assert_eq(int(anchor_w5.id), TileId.W5)
	assert_true(Tile.is_instance_id_in_hand_seq(anchor_w5.instance_id, bc.state.hand_seq))
	var anchor_iid: int = int(anchor_w5.instance_id)
	_assert_iid_absent_from_active_zones(bc, anchor_iid)

	# 2) 七对子听 W9：W1–W4/W6/W7 对 + W9，不含 W5 对
	bc.state.seats[0].hand = _hand_from_live(bc, _chiitoi_tenpai_ids())
	_assert_iid_absent_from_active_zones(bc, anchor_iid)
	assert_true(
		_authority_snapshot_strict_ok(bc),
		"thunder 注册后 ARS strict restore 必须成功（anchor 仅在 registry）"
	)

	# 避免天和役满干扰七対子 + skill han 基线
	bc.state.first_round_active = false
	var next: Tile = _set_next_draw(bc, TileId.W9)
	assert_eq(int(next.id), TileId.W9)
	assert_true(Tile.is_instance_id_in_hand_seq(next.instance_id, bc.state.hand_seq))
	assert_true(bc.state.wall.peek_next_draw() == next)
	_assert_iid_absent_from_active_zones(bc, anchor_iid)

	var result: Dictionary = bc.run_to_end()
	assert_eq(result.last_event, &"WIN_DECLARED",
		"自摸命中后最末事件应为 WIN_DECLARED，实际：%s" % result.last_event)
	var win_ev: BattleEvent = _find_unique_win_declared(result.events)
	assert_eq(win_ev.actor_seat, 0, "自摸座位应为 seat0")
	assert_true(win_ev.extra.has("han"), "WIN_DECLARED.extra 必含 han")
	# 七対子 2 番 + thunder_5w_han_bonus → 总 ≥ 3
	assert_gte(int(win_ev.extra.han), 3, "thunder_5w 应给玩家自胡 +han → 总 ≥ 3")
	assert_true(bc._settled, "自摸结算后必须 settled")


# ---- GameDriver 同步 in-hand skill delta ----

func test_game_driver_propagates_skill_transfer_to_cumulative() -> void:
	# 直接构造 driver + battle，模拟 soul_drain 转分，验证 GameDriver
	# apply_result 后 cumulative_scores 反映 transfer
	var driver := GameDriver.new(42)
	var bc := driver.start_hand()
	# 模拟一次 transfer：state.scores 分布变化（无需真胡）
	bc.state.scores[0] += 1000
	bc.state.scores[1] -= 1000
	# 模拟空 events 走 exhaustive_draw 路径
	var apply_res := driver.apply_result([])
	assert_eq(apply_res.kind, "exhaustive_draw")
	# cumulative 应反映 transfer
	assert_eq(driver.cumulative_scores[0], 25000 + 1000, "in-hand transfer 应进入 cumulative")
	assert_eq(driver.cumulative_scores[1], 25000 - 1000)
	# 守恒
	var sum := 0
	for s in driver.cumulative_scores:
		sum += s
	assert_eq(sum, 100000, "in-hand skill delta 不破坏总分守恒")
