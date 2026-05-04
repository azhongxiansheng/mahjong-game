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

func _init() -> void:
	var config := _parse_args()
	var stats := SimulationHarness.simulate(config)
	print(SimulationHarness.format_summary(stats))
	quit(0)

func _parse_args() -> Dictionary:
	var config: Dictionary = {
		"runs": 10,
		"seed": 0,
		"starter": &"starter_control",
		"pick_strategy": "first",
	}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--runs="):
			config["runs"] = int(arg.substr(7))
		elif arg.begins_with("--seed="):
			config["seed"] = int(arg.substr(7))
		elif arg.begins_with("--starter="):
			# 支持 --starter=control（短名）或 --starter=starter_control（全名）
			var raw_name := arg.substr(10)
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
		elif arg.begins_with("--starting-hp="):
			config["starting_hp_override"] = int(arg.substr(14))
		elif arg.begins_with("--rank-hp-delta="):
			# 解析 "0,-1,-1,-2" → [0, -1, -1, -2]
			var raw := arg.substr(16)
			var parts: PackedStringArray = raw.split(",")
			var arr: Array = []
			for p in parts:
				arr.append(int(p))
			config["rank_hp_delta_override"] = arr
	return config
