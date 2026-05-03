class_name SimulationHarness

# 麻将王 — M7 平衡迭代 D4：批量 Run simulation 工具
#
# 不依赖 UI（RunFlow extends Control）；直接驱动 RunState + BattleNodeRunner，
# 跑批量 Run 收集统计，给数值平衡迭代（plan-7 D6 三步法）提供数据。
#
# 用法（GDScript 内）：
#   var stats := SimulationHarness.simulate({"runs": 100, "seed": 42})
# 用法（CLI）：
#   godot --headless --path godot --script tools/simulate_runs.gd -- --runs=100

const DEFAULT_MAX_NODES_PER_RUN: int = 200  # 防死循环（一个 Run 不该超过 100 节点）
const VIEWER_SEAT: int = 0

# 主入口。返统计字典，包含 runs / completed / failed / completion_rate /
# avg_nodes_per_run / final_hp_avg / failed_at_chapter 等。
#
# config 字段：
#   runs: int (default 10)
#   seed: int (default 0；run i 实际用 seed + i)
#   starter: StringName (default &"control"；&"" 表不应用起始包)
#   max_nodes_per_run: int (default 200)
#   pick_strategy: String "first" | "random" (default "first")
static func simulate(config: Dictionary) -> Dictionary:
	var runs: int = int(config.get("runs", 10))
	var base_seed: int = int(config.get("seed", 0))
	# starter id 形如 "starter_control"；CLI 接受 "control" 短名，由
	# simulate_runs.gd 加 "starter_" 前缀
	var starter: StringName = config.get("starter", &"starter_control")
	var max_nodes: int = int(config.get("max_nodes_per_run", DEFAULT_MAX_NODES_PER_RUN))
	var pick_strategy: String = config.get("pick_strategy", "first")
	# M7：是否用 HeuristicAi（保留启发式弃牌）；默认 false 为兼容历史 baseline
	var use_heuristic_ai: bool = bool(config.get("heuristic_ai", false))

	var completed: int = 0
	var failed: int = 0
	var failed_at_chapter: Array[int] = [0, 0, 0]  # 章 1 / 章 2 / 章 3 内 hp 归零
	var nodes_per_run: Array[int] = []
	var final_hp_dist: Array[int] = []
	# M7 D4 扩展（baseline 假设 B 下一步）：hand-level 统计跨所有 Run × 所有节点
	var hand_kind_total: Dictionary = {"tsumo": 0, "ron": 0, "exhaustive_draw": 0}
	# 4 个 seat 节点结束时累计点数（每节点 4 个数字），跨所有 Run 累计后取均值
	var seat_score_sum: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var seat_score_samples: int = 0

	for i in range(runs):
		var run_outcome := _simulate_one(base_seed + i, starter, max_nodes, pick_strategy, use_heuristic_ai)
		if run_outcome.won:
			completed += 1
		elif run_outcome.failed:
			failed += 1
			var ch: int = run_outcome.chapter_at_end
			if ch >= 1 and ch <= 3:
				failed_at_chapter[ch - 1] += 1
		nodes_per_run.append(run_outcome.nodes_visited)
		final_hp_dist.append(run_outcome.final_hp)
		# 累 hand_outcomes
		for k in run_outcome.hand_outcomes.keys():
			hand_kind_total[k] = int(hand_kind_total.get(k, 0)) + int(run_outcome.hand_outcomes[k])
		# 累 seat_scores（按节点取样）
		for sample in run_outcome.seat_score_samples:
			for s in range(4):
				seat_score_sum[s] += float(sample[s])
			seat_score_samples += 1

	var hand_total: int = int(hand_kind_total.get("tsumo", 0)) \
		+ int(hand_kind_total.get("ron", 0)) \
		+ int(hand_kind_total.get("exhaustive_draw", 0))
	var hand_kind_pct: Dictionary = {}
	if hand_total > 0:
		for k in hand_kind_total.keys():
			hand_kind_pct[k] = float(hand_kind_total[k]) / float(hand_total)
	else:
		hand_kind_pct = {"tsumo": 0.0, "ron": 0.0, "exhaustive_draw": 0.0}

	var avg_seat_score: Array[float] = [0.0, 0.0, 0.0, 0.0]
	if seat_score_samples > 0:
		for s in range(4):
			avg_seat_score[s] = seat_score_sum[s] / float(seat_score_samples)

	return {
		"runs": runs,
		"seed": base_seed,
		"starter": starter,
		"completed": completed,
		"failed": failed,
		"completion_rate": float(completed) / float(max(runs, 1)),
		"failed_at_chapter": failed_at_chapter,
		"avg_nodes_per_run": _avg(nodes_per_run),
		"min_nodes": _min(nodes_per_run),
		"max_nodes": _max(nodes_per_run),
		"avg_final_hp": _avg(final_hp_dist),
		"max_hp": BalanceConstants.lookup(&"max_hp"),
		# M7 D4 扩展
		"hand_kind_total": hand_kind_total,
		"hand_kind_pct": hand_kind_pct,
		"hand_total": hand_total,
		"avg_seat_score": avg_seat_score,
		"seat_score_samples": seat_score_samples,
	}

# 跑单 Run 直到 finished 或超过 max_nodes。
# 返 {won, failed, chapter_at_end, nodes_visited, final_hp}
static func _simulate_one(run_seed: int, starter: StringName, max_nodes: int, pick_strategy: String, use_heuristic_ai: bool = false) -> Dictionary:
	var rs := RunState.new(run_seed)
	if starter != &"":
		StarterPacks.apply_to(rs, starter)

	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed * 7919  # 与节点 seed 解耦

	var nodes_visited: int = 0
	var hand_outcomes: Dictionary = {"tsumo": 0, "ron": 0, "exhaustive_draw": 0}
	var seat_score_samples: Array = []  # Array of Array[int]，每节点结束时 4 seats 累计点数
	while not rs.finished and nodes_visited < max_nodes:
		var options: Array = rs.next_node_options()
		if options.is_empty():
			break
		var picked: NodeRef = _pick(options, pick_strategy, rng)
		if not rs.choose_next_node(picked.index):
			break
		var current: NodeRef = rs.current_node_ref()
		if current == null:
			break
		var result: NodeResult
		if NodeKind.is_battle(current.kind):
			var boss_id: StringName = &""
			if current.kind == NodeKind.Kind.BOSS:
				boss_id = ChapterConfig.get_boss_id(rs.chapter)
			var node_seed := run_seed * 1000 + nodes_visited
			# M7 D4：用 with_stats 版本收 hand-level 统计；M7：传 player deck
			# (abilities + tile_variants) 让玩家技能在 sim 真生效
			var ability_ids: Array = []
			var tile_variants: Dictionary = {}
			if rs.player_deck != null:
				for a in rs.player_deck.abilities:
					if a != null:
						ability_ids.append(a.id)
				tile_variants = rs.player_deck.tile_variants
			var node_stats: Dictionary = BattleNodeRunner.run_battle_with_stats(node_seed, boss_id, ability_ids, use_heuristic_ai, tile_variants)
			result = node_stats.node_result
			for k in node_stats.hand_outcomes.keys():
				hand_outcomes[k] = int(hand_outcomes.get(k, 0)) + int(node_stats.hand_outcomes[k])
			seat_score_samples.append(node_stats.final_scores.duplicate())
		else:
			result = BattleNodeRunner.placeholder_result()
		rs.complete_node(result)
		nodes_visited += 1

	return {
		"won": rs.won,
		"failed": rs.finished and not rs.won,
		"chapter_at_end": rs.chapter,
		"nodes_visited": nodes_visited,
		"final_hp": rs.hp,
		"hand_outcomes": hand_outcomes,
		"seat_score_samples": seat_score_samples,
	}

static func _pick(options: Array, strategy: String, rng: RandomNumberGenerator) -> NodeRef:
	if strategy == "random" and options.size() > 1:
		return options[rng.randi_range(0, options.size() - 1)]
	return options[0]

# 把统计字典格式化成易读的多行字符串（CLI 直接 print）。
static func format_summary(stats: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append("=== Simulate Runs ===")
	lines.append("config: runs=%d, seed=%d, starter=%s" % [stats.runs, stats.seed, stats.starter])
	lines.append("")
	var rate_pct: float = stats.completion_rate * 100.0
	lines.append("通关率: %.1f%% (%d / %d)" % [rate_pct, stats.completed, stats.runs])
	lines.append("失败:   %d" % stats.failed)
	var fbc: Array = stats.failed_at_chapter
	lines.append("  章 1: %d / 章 2: %d / 章 3: %d" % [fbc[0], fbc[1], fbc[2]])
	lines.append("")
	lines.append("节点 / Run: avg=%.1f, min=%d, max=%d" % [stats.avg_nodes_per_run, stats.min_nodes, stats.max_nodes])
	lines.append("最终 HP avg: %.1f / %d" % [stats.avg_final_hp, stats.max_hp])
	# M7 D4 扩展
	lines.append("")
	var pct: Dictionary = stats.hand_kind_pct
	lines.append("局结果分布（共 %d 局）:" % stats.hand_total)
	lines.append("  tsumo:           %.1f%% (%d)" % [
		float(pct.get("tsumo", 0.0)) * 100.0,
		int(stats.hand_kind_total.get("tsumo", 0)),
	])
	lines.append("  ron:             %.1f%% (%d)" % [
		float(pct.get("ron", 0.0)) * 100.0,
		int(stats.hand_kind_total.get("ron", 0)),
	])
	lines.append("  exhaustive_draw: %.1f%% (%d)" % [
		float(pct.get("exhaustive_draw", 0.0)) * 100.0,
		int(stats.hand_kind_total.get("exhaustive_draw", 0)),
	])
	var seat_avg: Array = stats.avg_seat_score
	lines.append("")
	lines.append("各 seat 节点终局平均点数（取样 %d 节点）:" % stats.seat_score_samples)
	lines.append("  seat 0 (玩家): %.0f" % seat_avg[0])
	lines.append("  seat 1 (AI):   %.0f" % seat_avg[1])
	lines.append("  seat 2 (AI):   %.0f" % seat_avg[2])
	lines.append("  seat 3 (AI):   %.0f" % seat_avg[3])
	return "\n".join(lines)

# ---- internal stats helpers ----

static func _avg(arr: Array) -> float:
	if arr.is_empty():
		return 0.0
	var total: float = 0.0
	for v in arr:
		total += float(v)
	return total / float(arr.size())

static func _min(arr: Array) -> int:
	if arr.is_empty():
		return 0
	var m: int = arr[0]
	for v in arr:
		if int(v) < m:
			m = int(v)
	return m

static func _max(arr: Array) -> int:
	if arr.is_empty():
		return 0
	var m: int = arr[0]
	for v in arr:
		if int(v) > m:
			m = int(v)
	return m
