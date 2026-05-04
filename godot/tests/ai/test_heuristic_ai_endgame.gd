extends GutTest

# 麻将王 — M8.5：HeuristicAi 终局策略单测
#
# 验证：set_strategic_context 注入 cumulative_scores + hand_index + total_hands
# 后，decide_riichi 在"终局 + 自家排名第 1"时自动放弃立直（防止立直棒丢 +
# 振听）。其他 8 种组合维持 M7 默认（能立直就立直）。
#
# Endgame = 半庄战剩 ≤ 2 局（hand_index >= total_hands - 2）。东风战 4 局
# 默认进入 endgame 较早，但因 total_hands=4 时 endgame >= 2 即 hand_index >= 2，
# 这是合理的"东 3 / 东 4"行为。

const _STARTING_SCORES := [25000, 25000, 25000, 25000]

func _make_seat_with_riichi_ready_hand() -> Seat:
	# 制作一个听 + 门清的 Seat，让 RiichiValidator 通过。
	# 用 fixture 思路：从已有的立直测试代码挖一个简单可靠的牌型。
	# 这里走"实际跑一场到 tenpai"路径太重，改用预制听牌（mocked）。
	# v1 简化：用一个具体已知听牌（万子顺子型）。
	# 由于 RiichiValidator 走 WaitCalculator 内部，最稳办法是从 Wall.new_full_set
	# 抽 13 张听牌固定组合。
	# 借用 RiichiValidator 测试现成 fixture 思路 — 用 4 万 + 5 万 + 3 万对 + ...
	# 实测：直接构造 Hand 比单测 fixture 维护成本低。
	var seat := Seat.new(1, TileId.S_WIND)  # AI seat 1，自风南
	# 听筒 6（顺子 4-5 / 6-?；已含 4-5 等于听 3-6）
	# 简化：构造听 3 万 OR 6 万 的两面（万 4 5 + 已有的 4 5 + 字牌对 + 三色刻子等）
	# 这部分实测会较复杂；改用"构造一个能通过 can_declare_riichi 的最简组合"。
	# 即 13 张含 1 套对子 + 4 套面子（顺/刻/字）+ 1 单张待和。
	# 使用现成 RiichiValidator 测试的 mock 路径：跑 BattleController 一段时间
	# 再读取 seat.hand 状态。
	# 为简化，本测试不直接验证 can_declare_riichi=true 的边界情况，
	# 只验证 strategic_context 改变 decide_riichi 的"门槛逻辑分支"行为。
	return seat

# ---- _rank_for + endgame 内部计算正确性 ----

func test_default_no_strategic_context_returns_zero_rank():
	var ai := HeuristicAi.new(42)
	assert_eq(ai._rank_for(0), 0, "未注入 context → rank=0 表中性")

func test_strategic_context_rank_for_top_seat():
	var ai := HeuristicAi.new(42)
	ai.set_strategic_context([40000, 30000, 20000, 10000], 0, 8)
	assert_eq(ai._rank_for(0), 1, "40000 第 1")
	assert_eq(ai._rank_for(1), 2)
	assert_eq(ai._rank_for(2), 3)
	assert_eq(ai._rank_for(3), 4)

func test_strategic_context_rank_with_ties():
	var ai := HeuristicAi.new(42)
	ai.set_strategic_context([25000, 25000, 25000, 25000], 0, 8)
	# 同分时各 seat 都是 rank 1（rank_for 不做 tiebreak — AI 决策侧不需要
	# 公平裁决；rank_for_seat tiebreak 是 sim 排名输出层的事）
	for s in range(4):
		assert_eq(ai._rank_for(s), 1, "seat %d 同分 → rank 1" % s)

func test_is_endgame_hanchan_south_4_remaining_2():
	var ai := HeuristicAi.new(42)
	# 半庄 8 局 hand_index=6（南 3）→ 剩 2 局，进入 endgame
	ai.set_strategic_context(_STARTING_SCORES, 6, 8)
	assert_true(ai._is_endgame(), "hand_index=6 total=8 → 剩 2 局，endgame")

func test_is_endgame_hanchan_south_2_not_yet():
	var ai := HeuristicAi.new(42)
	# 半庄 8 局 hand_index=4（南 1）→ 剩 4 局，未进入 endgame
	ai.set_strategic_context(_STARTING_SCORES, 4, 8)
	assert_false(ai._is_endgame(), "hand_index=4 total=8 → 剩 4 局，未到 endgame")

func test_is_endgame_east_round_3():
	var ai := HeuristicAi.new(42)
	# 东风 4 局 hand_index=2（东 3）→ 剩 2 局，endgame
	ai.set_strategic_context(_STARTING_SCORES, 2, 4)
	assert_true(ai._is_endgame(), "东风战剩 2 局也是 endgame（合理 — 东 3/东 4 是终盘）")

# ---- decide_riichi 决策分支：endgame + rank 1 → 拒绝 ----

func test_decide_riichi_endgame_rank_1_refuses():
	# 用 mock seat：构造 RiichiValidator 会返 true 的最小 fixture
	# 通过 monkey-patch RiichiValidator 不现实；改成 BC 跑场后读 seat 路径。
	#
	# v1 简化：跑 32 场 BattleController + 终局领先注入，统计 RIICHI_DECLARED
	# 事件来自 seat 1 的频率。预期 < default（无 endgame strategic context）。
	#
	# 但此实证测试依赖大量 sample，本单测只锁住"领先时 _should_skip_riichi 返 true"
	# 的纯函数逻辑分支。
	var ai := HeuristicAi.new(42)
	ai.set_strategic_context([40000, 25000, 20000, 15000], 6, 8)  # seat 0 第 1
	# seat 1 第 2 位 → endgame 不收紧立直（仍可立）
	assert_false(ai._should_skip_riichi(1), "seat 1 排名 2 → 不应跳过立直")
	# seat 0 第 1 位 + endgame → 跳过
	assert_true(ai._should_skip_riichi(0), "seat 0 排名 1 + endgame → 跳过立直")

func test_decide_riichi_non_endgame_rank_1_does_not_skip():
	var ai := HeuristicAi.new(42)
	ai.set_strategic_context([40000, 25000, 20000, 15000], 0, 8)  # 半庄起始
	# 非 endgame → 不跳过（即使第 1）
	assert_false(ai._should_skip_riichi(0), "非 endgame 第 1 不跳过立直")

func test_decide_riichi_no_context_does_not_skip():
	# 默认未注入 context（兼容 M7 调用）
	var ai := HeuristicAi.new(42)
	assert_false(ai._should_skip_riichi(0), "无 strategic context 不跳过（兼容 M7）")

# ---- 端到端：跨整局 BattleController 跑 + 终局立直频率比较 ----

func test_endgame_strategy_reduces_seat_0_riichi_count_when_leading():
	# 跑 32 场，seat 0 dealer，注入"seat 0 第 1 + endgame" context
	# 计 RIICHI_DECLARED 事件中 actor_seat == 0 的次数 vs default 行为对比
	var with_strategy: int = 0
	var without_strategy: int = 0
	for s in range(32):
		# with strategy: seat 0 第 1 大幅领先 + endgame
		var bc1 := BattleController.new(s * 7 + 11, 0, true)
		bc1.ai.set_strategic_context([60000, 20000, 10000, 10000], 6, 8)
		bc1.run_to_end()
		for ev in bc1.events:
			if ev.type == &"RIICHI_DECLARED" and ev.actor_seat == 0:
				with_strategy += 1
				break  # 一场最多算 1 次（seat 0 立 1 次足以分类）
		# without strategy: 默认 HeuristicAi（M7 行为）
		var bc2 := BattleController.new(s * 7 + 11, 0, true)
		bc2.run_to_end()
		for ev in bc2.events:
			if ev.type == &"RIICHI_DECLARED" and ev.actor_seat == 0:
				without_strategy += 1
				break
	assert_lt(with_strategy, without_strategy,
		"终局领先策略应减少 seat 0 立直次数：with=%d vs without=%d" % [with_strategy, without_strategy])
