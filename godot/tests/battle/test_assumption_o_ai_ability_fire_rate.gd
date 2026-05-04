extends GutTest

# 麻将王 — M8.5：假设 O 实证测试
#
# 假设 O（同事 baseline 6 PR #83 提出，PR #84 收尾未直接验证）：
#   PR #82 `--ai-seat-abilities` 启用 vs 关闭，control 通关率 byte-identical →
#   推测 AI ability injection 在当前 sim ≈ 无操作。机制：AI 胡牌频次低
#   (~10%)，多数 ability 在 WIN_DECLARED_PRE 触发，AI 不胡 → ability 不 fire。
#
# 本测试用 FireCountingHook（res://tests/_fixtures/fire_counting_hook.gd）注册
# 到 AI seat，跑一整场对战，统计实际 fire 次数。用 GAME_BEGIN（每局必触发）
# 作 control，WIN_DECLARED_PRE 作 experiment，对比印证结构性差距。
#
# 这不是回归测试 — 是实证假设 O 的机制定位测试。结论会写进 baseline 7 报告。

const FireCountingHook := preload("res://tests/_fixtures/fire_counting_hook.gd")

# 一个简化的 BattleController 跑场 fixture：用 HeuristicAi、3 AI seats，
# 每场跑到流局/胡。返 (game_begin_fires, win_declared_pre_fires) tuple。
func _run_fight_with_tracked_hooks(seed: int) -> Dictionary:
	var bc := BattleController.new(seed, 0, true)  # use_heuristic_ai=true

	# 给 seat 1 装一个监 GAME_BEGIN 的 hook
	var begin_hook := FireCountingHook.new()
	var begin_skill := SkillResource.new()
	begin_skill.id = &"_test_game_begin_tracker"
	begin_skill.is_ability = true
	begin_skill.owner_triggers = [&"GAME_BEGIN"] as Array[StringName]
	begin_skill.hook_script = null  # registry.register 会优先用 SkillResource 现成 hook
	bc.registry.register(begin_skill, 1)
	# SkillRegistry 通过 hook_script 实例化；改用直接注 entry hook（fixture 路径）
	# 取最后一个 entry，覆盖它的 hook 字段
	var entries: Array = bc.registry.get_all_entries()
	entries[entries.size() - 1].hook = begin_hook

	# 给 seat 2 装一个监 WIN_DECLARED_PRE 的 hook
	var win_hook := FireCountingHook.new()
	var win_skill := SkillResource.new()
	win_skill.id = &"_test_win_pre_tracker"
	win_skill.is_ability = true
	win_skill.owner_triggers = [&"WIN_DECLARED_PRE"] as Array[StringName]
	win_skill.hook_script = null
	bc.registry.register(win_skill, 2)
	entries = bc.registry.get_all_entries()
	entries[entries.size() - 1].hook = win_hook

	bc.run_to_end()
	return {
		"game_begin_fires": begin_hook.fire_count,
		"win_declared_pre_fires": win_hook.fire_count,
	}

# ---- 实证假设 O ----

func test_game_begin_hook_fires_exactly_once_per_battle():
	# 控制项：GAME_BEGIN 每场必恰 1 次 → ability 注册路径 + hook dispatch 工作
	var stats := _run_fight_with_tracked_hooks(42)
	assert_eq(int(stats.game_begin_fires), 1,
		"GAME_BEGIN hook 必须每场恰 1 次（证 ability 注册 + dispatch 健康）")

func test_win_declared_pre_fires_zero_or_one_per_battle():
	# 实验：WIN_DECLARED_PRE 多数场景 0 次（流局），偶尔 1 次（有人胡）
	# 跨多个 seed 看分布
	var fire_counts: Array[int] = []
	for s in [1, 7, 42, 100, 200, 314, 500, 1234]:
		var stats := _run_fight_with_tracked_hooks(s)
		fire_counts.append(int(stats.win_declared_pre_fires))
	# 每场必 ≤ 1（一场最多一次胡 — 此 hook 注在 seat 2 单家）
	for c in fire_counts:
		assert_lte(c, 1, "WIN_DECLARED_PRE 单 seat 单场最多 1 次")
	# 至少有一些场为 0（不胡）—— 这就是假设 O 的核心
	var zero_count: int = 0
	for c in fire_counts:
		if c == 0:
			zero_count += 1
	assert_gte(zero_count, 4,
		"假设 O 实证：8 场中至少一半 (≥4) WIN_DECLARED_PRE seat 2 没 fire（AI 没胡）")

func test_assumption_o_REFUTED_ai_seat_2_win_rate_actually_high():
	# 假设 O **证伪**：以 HeuristicAi 跑单 BattleController（dealer=seat 0），
	# seat 2 单家胡率实测 ~50%+ —— 远高于 baseline 6 报告的"AI 总胡率
	# 10-15%"暗示的"单 AI seat 胡率 ~3-5%"猜测。
	#
	# 含义：PR #82 `--ai-seat-abilities` 在 sim 中"看似无作用"不是因为
	# ability 不 fire（fire 频次足够），而是 **ability 内部 hook 的 mutation
	# 在当前 ctx API 下没真改 state.scores / yaku_list**。
	#
	# 后续 M9 应聚焦：选一两个 ability hook 实证它们的 ctx mutation 是否
	# 真生效（baseline 5 假设 J/M 的真根因），而不是改 sim 选 ability 的池子。
	var total_battles: int = 32
	var seat2_wins: int = 0
	for i in range(total_battles):
		var stats := _run_fight_with_tracked_hooks(i * 13 + 7)
		seat2_wins += int(stats.win_declared_pre_fires)
	var win_rate: float = float(seat2_wins) / float(total_battles)
	# 锁住实测下限：seat 2 胡率 > 25%（远高于 4 家均分预期）
	# 证伪假设 O 的"AI 不胡 → ability 不 fire"机制描述
	assert_gt(win_rate, 0.25,
		"假设 O 证伪：seat 2 单场胡率 %.2f > 25%% 4 家均分预期 — ability fire 不缺机会" % win_rate)
