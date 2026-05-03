extends SceneTree

# 麻将王 — M7 平衡迭代 D4：批量 Run simulation CLI 入口
#
# 跑法：
#   godot --headless --path godot --script tools/simulate_runs.gd -- --runs=100 --seed=42
#   godot --headless --path godot --script tools/simulate_runs.gd -- --runs=10 --starter=fast
#   godot --headless --path godot --script tools/simulate_runs.gd -- --runs=50 --pick=random
#
# 业务逻辑全在 SimulationHarness（可单测）；本文件只解析 args + 打印。

func _init() -> void:
	var config := _parse_args()
	var stats := SimulationHarness.simulate(config)
	print(SimulationHarness.format_summary(stats))
	quit(0)

func _parse_args() -> Dictionary:
	var config: Dictionary = {
		"runs": 10,
		"seed": 0,
		"starter": &"control",
		"pick_strategy": "first",
	}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--runs="):
			config["runs"] = int(arg.substr(7))
		elif arg.begins_with("--seed="):
			config["seed"] = int(arg.substr(7))
		elif arg.begins_with("--starter="):
			config["starter"] = StringName(arg.substr(10))
		elif arg.begins_with("--pick="):
			config["pick_strategy"] = arg.substr(7)
		elif arg.begins_with("--max-nodes="):
			config["max_nodes_per_run"] = int(arg.substr(12))
		elif arg == "--heuristic-ai":
			config["heuristic_ai"] = true
	return config
