extends GutTest

# 端到端统计回归：跨完整对局比较终局策略启用前后的立直频率。
# 该测试固定跑 64 场完整对局，属于慢速性能/统计层，不进入日常 core 门禁。

func test_endgame_strategy_reduces_seat_0_riichi_count_when_leading():
	# 跑 32 组相同 seed，seat 0 dealer，注入"seat 0 第 1 + endgame" context
	# 计 RIICHI_DECLARED 事件中 actor_seat == 0 的次数 vs default 行为对比
	var with_strategy: int = 0
	var without_strategy: int = 0
	for s in range(32):
		# with strategy: seat 0 第 1 大幅领先 + endgame
		var bc1 := BattleController.new(s * 7 + 11, 0, true)
		bc1.ai.set_strategic_context([60000, 20000, 10000, 10000], 7, 8)
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
