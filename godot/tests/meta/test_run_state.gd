extends GutTest

# 麻将王 — M4 第 1 步：RunState 单测
# 覆盖：扣血、节点推进、Run 失败、Run 通关、跨章地图重生。

# ---- 初始状态 ----

func test_initial_state():
	var rs := RunState.new(42)
	assert_eq(rs.hp, BalanceConstants.lookup(&"starting_hp"))
	assert_eq(rs.max_hp, BalanceConstants.lookup(&"max_hp"))
	assert_eq(rs.gold, 0)
	assert_eq(rs.chapter, 1, "起始 chapter = 1")
	assert_not_null(rs.current_map)
	assert_false(rs.finished)
	assert_false(rs.won)
	assert_eq(rs.history.size(), 0)
	# 起始可选项 = [entry_node]
	var opts: Array = rs.next_node_options()
	assert_eq(opts.size(), 1)
	assert_eq(opts[0].floor_index, 0)
	assert_eq(opts[0].kind, NodeKind.Kind.NORMAL)

# ---- choose_next_node ----

func test_choose_entry_node_advances():
	var rs := RunState.new(42)
	var entry_index: int = rs.current_map.entry_node
	assert_true(rs.choose_next_node(entry_index))
	assert_eq(rs.current_map.current_node, entry_index)

func test_choose_invalid_node_keeps_state():
	var rs := RunState.new(42)
	assert_false(rs.choose_next_node(99), "非法 index 应拒绝")
	assert_eq(rs.current_map.current_node, -1)

# ---- complete_node 排名 → hp_delta ----

func test_complete_node_rank_1_no_hp_loss():
	var rs := RunState.new(42)
	rs.choose_next_node(rs.current_map.entry_node)
	rs.complete_node(NodeResult.new(1))
	assert_eq(rs.hp, BalanceConstants.lookup(&"starting_hp"), "rank 1 不掉血，hp 同 starting")
	assert_eq(rs.gold, 30, "rank 1 +30 金币")
	assert_eq(rs.history.size(), 1)

func test_complete_node_rank_4_loses_2_hp():
	var rs := RunState.new(42)
	rs.choose_next_node(rs.current_map.entry_node)
	rs.complete_node(NodeResult.new(4))
	assert_eq(rs.hp, int(BalanceConstants.lookup(&"starting_hp")) - 2, "rank 4 -2 hp")
	assert_eq(rs.gold, 0)

func test_complete_node_emits_signal_with_options():
	var rs := RunState.new(42)
	rs.choose_next_node(rs.current_map.entry_node)
	# 用 Array 容器避免 lambda 闭包内直接赋值 var 的 GDScript 4 限制
	var captured: Array = []
	rs.node_completed.connect(func(opts): captured.append(opts))
	rs.complete_node(NodeResult.new(1))
	assert_eq(captured.size(), 1, "node_completed 应 emit 1 次")
	assert_gt(captured[0].size(), 0, "应至少有 1 个下层选项")

# ---- run_failed: hp 归零 ----

func test_hp_zero_emits_run_failed():
	var rs := RunState.new(42)
	rs.hp = 2  # 设到 2 让一次 rank 4 (-2) 归零
	rs.choose_next_node(rs.current_map.entry_node)
	var failed_count := [0]
	rs.run_failed.connect(func(): failed_count[0] += 1)
	rs.complete_node(NodeResult.new(4))
	assert_eq(rs.hp, 0)
	assert_true(rs.finished)
	assert_false(rs.won)
	assert_eq(failed_count[0], 1, "run_failed 应 emit 1 次")

func test_hp_zero_does_not_emit_node_completed():
	var rs := RunState.new(42)
	rs.hp = 2
	rs.choose_next_node(rs.current_map.entry_node)
	var node_completed_count := [0]
	rs.node_completed.connect(func(_o): node_completed_count[0] += 1)
	rs.complete_node(NodeResult.new(4))
	assert_eq(node_completed_count[0], 0, "失败时不应 emit node_completed")

# ---- complete_node 后再调不再触发副作用 ----

func test_complete_after_finish_is_idempotent():
	var rs := RunState.new(42)
	rs.hp = 2
	rs.choose_next_node(rs.current_map.entry_node)
	rs.complete_node(NodeResult.new(4))
	# 再调一次
	rs.complete_node(NodeResult.new(4))
	assert_eq(rs.hp, 0, "hp 已是 0 不应继续掉")
	assert_true(rs.finished)

# ---- Boss 节点：章内推进 / 整 Run 通关 ----

func _advance_to_boss(rs: RunState) -> void:
	# 把 current_node 直接设到 boss_node（绕过 advance_to 的 next_options 检查）
	rs.current_map.current_node = rs.current_map.boss_node

func test_complete_boss_chapter_1_advances_to_chapter_2():
	var rs := RunState.new(42)
	_advance_to_boss(rs)
	rs.complete_node(NodeResult.new(1))
	assert_eq(rs.chapter, 2)
	assert_false(rs.finished)
	assert_not_null(rs.current_map)
	# 新章地图重生，current_node 重置
	assert_eq(rs.current_map.current_node, -1)

func test_complete_boss_chapter_3_emits_run_won():
	var rs := RunState.new(42)
	rs.chapter = 3
	rs._generate_chapter_map(3)
	_advance_to_boss(rs)
	var won_count := [0]
	rs.run_won.connect(func(): won_count[0] += 1)
	rs.complete_node(NodeResult.new(1))
	assert_true(rs.finished)
	assert_true(rs.won)
	assert_eq(won_count[0], 1)

# ---- run_seed 决定章地图 ----

func test_seed_determinism_across_runs():
	var rs1 := RunState.new(42)
	var rs2 := RunState.new(42)
	assert_eq(rs1.current_map.node_count(), rs2.current_map.node_count())

# ---- placeholder 节点 ----

func test_placeholder_node_does_not_change_hp():
	var rs := RunState.new(42)
	rs.choose_next_node(rs.current_map.entry_node)
	rs.complete_node(NodeResult.from_placeholder())
	assert_eq(rs.hp, BalanceConstants.lookup(&"starting_hp"), "占位节点不掉血")
	assert_eq(rs.gold, 0, "占位节点不给金币（M5 实装内部 hook）")
