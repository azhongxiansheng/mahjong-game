extends GutTest

# 麻将王 — M7 平衡：HeuristicAi 单测
#
# 验证启发式弃牌行为（discard 最孤立的牌）：
# - 单张字牌 vs 数牌邻居：优先弃单张字牌
# - 单张孤立数牌 vs 对子：优先弃孤立单张
# - 同类比较：邻居更少的优先弃

func _make_hand_from(ids: Array) -> Hand:
	var h := Hand.new()
	for tid in ids:
		h.add(Tile.new(tid))
	return h

func _make_seat_with_hand(ids: Array) -> Seat:
	var s := Seat.new(0, TileId.E)
	s.hand = _make_hand_from(ids)
	return s

# ---- 字牌孤立 ----

func test_discards_isolated_honor_over_paired_suited():
	# 手牌：W2 W2（对子）+ 1 张字牌（孤立）→ 应弃字牌
	var ai := HeuristicAi.new(0)
	var seat := _make_seat_with_hand([TileId.W2, TileId.W2, TileId.E])
	var to_discard := ai.decide_discard(seat)
	assert_eq(to_discard.id, TileId.E, "孤立字牌优先弃")

func test_discards_isolated_suited_over_paired():
	# W5 W5 + W9（孤立无邻居 W7/W8）→ 应弃 W9
	var ai := HeuristicAi.new(0)
	var seat := _make_seat_with_hand([TileId.W5, TileId.W5, TileId.W9])
	var to_discard := ai.decide_discard(seat)
	assert_eq(to_discard.id, TileId.W9, "孤立 W9 优先弃")

# ---- 同类邻居比较 ----

func test_keeps_tile_with_neighbors():
	# W3 W4（邻居）+ T9（孤立筒）→ 弃 T9
	var ai := HeuristicAi.new(0)
	var seat := _make_seat_with_hand([TileId.W3, TileId.W4, TileId.T9])
	var to_discard := ai.decide_discard(seat)
	assert_eq(to_discard.id, TileId.T9)

func test_keeps_triplet():
	# W5 W5 W5 + W1（孤立）→ 弃 W1，保刻子
	var ai := HeuristicAi.new(0)
	var seat := _make_seat_with_hand([TileId.W5, TileId.W5, TileId.W5, TileId.W1])
	var to_discard := ai.decide_discard(seat)
	assert_eq(to_discard.id, TileId.W1)

# ---- 多个等分数情况：tie-break 取第一个 ----

func test_tie_break_first_lowest():
	# 全字牌（全孤立 score 0）→ 弃第一个
	var ai := HeuristicAi.new(0)
	var seat := _make_seat_with_hand([TileId.E, TileId.S_WIND, TileId.W_WIND])
	var to_discard := ai.decide_discard(seat)
	assert_eq(to_discard.id, TileId.E, "tie-break 取 hand[0]")

# ---- 边界：空手牌 ----

func test_empty_hand_returns_null():
	var ai := HeuristicAi.new(0)
	var seat := _make_seat_with_hand([])
	assert_null(ai.decide_discard(seat))

# ---- 集成：BattleController 用 HeuristicAi 跑完整 ----

func test_battle_controller_with_heuristic_ai_completes():
	var bc := BattleController.new(42, 0, true)  # use_heuristic_ai=true
	var result: Dictionary = bc.run_to_end()
	# 不应崩；最末事件 ∈ {EXHAUSTIVE_DRAW, WIN_DECLARED}
	var allowed: Array = [&"EXHAUSTIVE_DRAW", &"WIN_DECLARED"]
	assert_true(allowed.has(result.last_event))
	# 守恒：state.scores + 立直棒池（流局未收的）= 100000
	# HeuristicAi 在 tenpai 时会立直 → 单 hand 流局可能留 pool
	var sum := 0
	for s in bc.state.scores:
		sum += s
	assert_eq(sum + bc.state.riichi_sticks * 1000, 100000)
