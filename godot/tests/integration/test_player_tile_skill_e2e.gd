extends GutTest

# 麻将王 — M7 玩家 tile skill 端到端集成测试。
# 验证 wire 后 player skills 在真战斗中真触发 + 影响 cumulative_scores。

# ---- soul_drain_hatsu 跨 hand 转分 ----

func _set_chiitoi_tenpai_for_seat(bc: BattleController, seat_idx: int) -> void:
	var tenpai_ids: Array = [
		TileId.W1, TileId.W1, TileId.W2, TileId.W2, TileId.W3, TileId.W3,
		TileId.W5, TileId.W5, TileId.W6, TileId.W6, TileId.W7, TileId.W7,
		TileId.W9,
	]
	var s: Seat = bc.state.seats[seat_idx]
	s.hand._tiles.clear()
	for tid in tenpai_ids:
		s.hand.add(Tile.new(tid))

class _PickW9Ai extends SimpleAi:
	func _init() -> void:
		super(0)
	func decide_discard(seat: Seat) -> Tile:
		for t in seat.hand._tiles:
			if t.id == TileId.W9:
				return t
		return seat.hand._tiles[0] if not seat.hand._tiles.is_empty() else null

func test_soul_drain_transfers_points_when_opponent_rons():
	# Player (seat 0) 持 soul_drain_hatsu_v1 → seat 1 ron 时玩家应拿 30%
	# 直接调 apply_ron 而非 run_to_end，避免 fixture 让 seat 0 自摸的复杂性
	var bc := BattleController.new(42, 0)
	TileSkillFactory.inject_one(bc.registry, &"soul_drain_hatsu_v1", 0)
	# seat 1 听 W9 单骑
	_set_chiitoi_tenpai_for_seat(bc, 1)

	var pre_score_0: int = bc.state.scores[0]
	var pre_score_1: int = bc.state.scores[1]
	# 模拟：seat 0 弃 W9，seat 1 ron
	var ok: bool = bc.apply_ron(1, Tile.new(TileId.W9), 0)
	assert_true(ok)

	# soul_drain 转分：seat 0 score 应 ↑（+30% × win_total），seat 1 ↓
	var post_score_0: int = bc.state.scores[0]
	var post_score_1: int = bc.state.scores[1]
	assert_gt(post_score_0, pre_score_0, "soul_drain：seat 0 持牌者从对手 ron 中获益")
	assert_lt(post_score_1, pre_score_1, "soul_drain：winner 损失部分点数给 holder")

# ---- thunder_5w 自胡 +1 番 ----

func test_thunder_5w_bumps_player_han_on_self_tsumo():
	# Player (seat 0) 持 thunder_5w_v1 + 自摸 → 应有 +1 番
	# 用同 fixture 让 player 自摸 W9 (七対子)
	var bc := BattleController.new(42, 0)
	TileSkillFactory.inject_one(bc.registry, &"thunder_5w_v1", 0)
	_set_chiitoi_tenpai_for_seat(bc, 0)
	# wall 顶 W9 → seat 0 摸到自摸
	bc.state.wall._tiles[bc.state.wall._draw_index] = Tile.new(TileId.W9)

	var result: Dictionary = bc.run_to_end()
	assert_eq(result.last_event, &"WIN_DECLARED")
	var win_ev: BattleEvent = result.events[result.events.size() - 1]
	# 七対子 = 2 番；thunder_5w +1 番 → 总 ≥ 3 番
	assert_gte(int(win_ev.extra.han), 3, "thunder_5w 应给玩家自胡 +1 番")

# ---- GameDriver 同步 in-hand skill delta ----

func test_game_driver_propagates_skill_transfer_to_cumulative():
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
