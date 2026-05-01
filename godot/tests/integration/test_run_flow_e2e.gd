extends GutTest

# 麻将王 — M4 第 4 步：Run 流程 e2e 集成测试
#
# 模拟完整 Run：
#   - 起始包应用 → RunState 初始化
#   - 循环：选下层节点 → 跑战斗 / 占位 → complete_node → 直到 finished
#   - 验证：终态 won/failed、hp 不变量、cumulative scores 守恒

const HARD_NODE_LIMIT: int = 100  # 整场 Run 最多走多少节点（防死锁）

# 全自动跑 Run：每次都选可达列表里的第一个节点。
# 战斗用 BattleNodeRunner，占位用 from_placeholder。
func _run_to_end(rs: RunState) -> Dictionary:
	var node_count := 0
	while not rs.finished and node_count < HARD_NODE_LIMIT:
		node_count += 1
		var opts: Array = rs.next_node_options()
		assert_gt(opts.size(), 0, "Run 进行中应至少 1 个选项；node_count=%d" % node_count)
		var chosen: NodeRef = opts[0]
		rs.choose_next_node(chosen.index)
		var result: NodeResult
		if NodeKind.is_battle(chosen.kind):
			var node_seed: int = rs.run_seed * 100 + chosen.index
			result = BattleNodeRunner.run_battle_to_node_result(node_seed)
		else:
			result = NodeResult.from_placeholder()
		rs.complete_node(result)
	return {"node_count": node_count}

# ---- 完整 Run 跑通（多 seed） ----

func test_run_finishes_within_node_limit_seed_42():
	var rs := RunState.new(42)
	StarterPacks.apply_to(rs, &"starter_control")
	var stats := _run_to_end(rs)
	assert_true(rs.finished, "Run 应在节点上限内结束（实际 %d 节点）" % stats.node_count)

func test_run_finishes_within_node_limit_seed_7():
	var rs := RunState.new(7)
	StarterPacks.apply_to(rs, &"starter_control")
	_run_to_end(rs)
	assert_true(rs.finished)

func test_run_finishes_within_node_limit_seed_123():
	var rs := RunState.new(123)
	StarterPacks.apply_to(rs, &"starter_control")
	_run_to_end(rs)
	assert_true(rs.finished)

# ---- 终态属性 ----

func test_finished_run_either_won_or_failed():
	var rs := RunState.new(42)
	StarterPacks.apply_to(rs, &"starter_control")
	_run_to_end(rs)
	assert_true(rs.finished)
	# 必须 won 或 hp <= 0
	if rs.won:
		assert_eq(rs.chapter, 3, "通关时应在章 3")
	else:
		assert_eq(rs.hp, 0, "失败时 hp 应 0")

func test_finished_run_history_is_non_empty():
	var rs := RunState.new(42)
	StarterPacks.apply_to(rs, &"starter_control")
	_run_to_end(rs)
	assert_gt(rs.history.size(), 0, "Run 至少访问 1 个节点")

func test_finished_run_hp_within_bounds():
	var rs := RunState.new(42)
	StarterPacks.apply_to(rs, &"starter_control")
	_run_to_end(rs)
	assert_gte(rs.hp, 0)
	assert_lte(rs.hp, rs.max_hp)

# ---- signal emit 顺序 ----

func test_signals_emit_correct_terminal():
	var rs := RunState.new(42)
	StarterPacks.apply_to(rs, &"starter_control")
	var failed_count := [0]
	var won_count := [0]
	rs.run_failed.connect(func(): failed_count[0] += 1)
	rs.run_won.connect(func(): won_count[0] += 1)
	_run_to_end(rs)
	# 终态必有且仅有 1 个信号触发
	assert_eq(failed_count[0] + won_count[0], 1, "终态信号 emit 1 次")
	if rs.won:
		assert_eq(won_count[0], 1)
	else:
		assert_eq(failed_count[0], 1)
