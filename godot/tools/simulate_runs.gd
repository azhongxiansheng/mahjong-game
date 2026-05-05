extends SceneTree

# 麻将王 — M7 平衡迭代 D4：批量 Run simulation CLI 入口
#
# 跑法：
#   godot --headless --path godot --script tools/simulate_runs.gd -- --runs=100 --seed=42
#   godot --headless --path godot --script tools/simulate_runs.gd -- --runs=10 --starter=fast
#   godot --headless --path godot --script tools/simulate_runs.gd -- --runs=50 --pick=random
#   godot --headless --path godot --script tools/simulate_runs.gd -- --runs=30 --starting-hp=1
#   godot --headless --path godot --script tools/simulate_runs.gd -- --runs=30 --rank-hp-delta=0,-1,-1,-2
#
# 业务逻辑全在 SimulationHarness（可单测）；本文件只解析 args + 打印。
#
# 实验 flags（M7 D6 三步法 用）：
#   --starting-hp=N        覆盖 BalanceConstants.starting_hp（baseline 1/3 假设 C 实验）
#   --rank-hp-delta=a,b,c,d 覆盖 node_rank_hp_delta（baseline 3 假设 H 实验）
#   --heuristic-ai         AI 用 HeuristicAi 启发式弃牌（vs SimpleAi）
#   --fair-tiebreak        启用公平同分裁决（PR #75；解 baseline 1-5 viewer 偏强根因）
#   --ai-seat-abilities    AI seat 1/2/3 也分配随机 ability（baseline 5 假设 J/M）

func _init() -> void:
	var parsed := parse_args(OS.get_cmdline_user_args())
	var unknown_flags: Array = parsed["unknown_flags"]
	for unknown in unknown_flags:
		printerr("⚠ simulate_runs: unknown flag '%s' (silently ignored — typo? check tool docstring)" % unknown)
	var stats := SimulationHarness.simulate(parsed["config"])
	print(SimulationHarness.format_summary(stats))
	quit(0)

# 解析 CLI args → {config, unknown_flags}。静态可测。
# 未识别的 `--xxx` flag 收集到 unknown_flags（不 abort，保留原 silent ignore 行为；
# _init 会 printerr 警告）。引入此函数是因为 baseline 11 PR #102/#106 误用
# `--ai-abilities`（不存在的 flag 名，正确是 `--ai-seat-abilities`），数据偏离。
static func parse_args(args: Array) -> Dictionary:
	var config: Dictionary = {
		"runs": 10,
		"seed": 0,
		"starter": &"starter_control",
		"pick_strategy": "first",
	}
	var unknown_flags: Array = []
	for arg in args:
		var matched: bool = true
		if arg.begins_with("--runs="):
			config["runs"] = int(arg.substr(7))
		elif arg.begins_with("--seed="):
			config["seed"] = int(arg.substr(7))
		elif arg.begins_with("--starter="):
			# 支持 --starter=control（短名）或 --starter=starter_control（全名）
			var raw_name: String = arg.substr(10)
			if raw_name.begins_with("starter_"):
				config["starter"] = StringName(raw_name)
			else:
				config["starter"] = StringName("starter_" + raw_name)
		elif arg.begins_with("--pick="):
			config["pick_strategy"] = arg.substr(7)
		elif arg.begins_with("--max-nodes="):
			config["max_nodes_per_run"] = int(arg.substr(12))
		elif arg == "--heuristic-ai":
			config["heuristic_ai"] = true
		elif arg == "--fair-tiebreak":
			config["fair_tiebreak"] = true
		elif arg == "--ai-seat-abilities":
			config["ai_seat_abilities"] = true
		elif arg == "--shanten-ai":
			# M10 Path A：HeuristicAi 启用 ShantenCalculator-aware 弃牌
			# （隐式开 --heuristic-ai；只在 use_heuristic_ai 时生效）
			config["shanten_ai"] = true
			config["heuristic_ai"] = true
		elif arg.begins_with("--starting-hp="):
			config["starting_hp_override"] = int(arg.substr(14))
		elif arg.begins_with("--rank-hp-delta="):
			# 解析 "0,-1,-1,-2" → [0, -1, -1, -2]
			var raw: String = arg.substr(16)
			var parts: PackedStringArray = raw.split(",")
			var arr: Array = []
			for p in parts:
				arr.append(int(p))
			config["rank_hp_delta_override"] = arr
		else:
			matched = false
		if not matched and arg.begins_with("--"):
			unknown_flags.append(arg)
	return {"config": config, "unknown_flags": unknown_flags}
