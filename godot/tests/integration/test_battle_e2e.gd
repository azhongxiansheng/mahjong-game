extends GutTest

# 里程碑 2 — 端到端集成测试。
# 验证 BattleController 把 TurnEngine + SkillScheduler + 规则引擎串成可跑的一局。

var _bc: BattleController

func before_each() -> void:
	_bc = BattleController.new(42, 0)

# ---- 路径 A：跑到底不崩 ----
# 4 家随机 SimpleAI 弃牌；预期最末事件是流局或自摸（自摸概率极低，但允许）；
# 不应 crash；scores 总和守恒；event_chain_depth 在 emit 之间归零。
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
