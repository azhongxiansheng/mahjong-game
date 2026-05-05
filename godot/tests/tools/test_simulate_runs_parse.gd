extends GutTest

# 麻将王 — simulate_runs.gd parse_args 静态函数单测
# 防止 baseline 11 PR #102/#106 误用 `--ai-abilities`（不存在 flag）类问题再发生。

const SimulateRunsScript := preload("res://tools/simulate_runs.gd")

func _parse(args: Array) -> Dictionary:
	return SimulateRunsScript.parse_args(args)

func test_default_config_when_no_args():
	var parsed := _parse([])
	var c: Dictionary = parsed["config"]
	assert_eq(c["runs"], 10)
	assert_eq(c["seed"], 0)
	assert_eq(c["starter"], &"starter_control")
	assert_eq(c["pick_strategy"], "first")
	assert_eq(parsed["unknown_flags"].size(), 0)

func test_runs_and_seed_parsed():
	var parsed := _parse(["--runs=100", "--seed=42"])
	assert_eq(parsed["config"]["runs"], 100)
	assert_eq(parsed["config"]["seed"], 42)

func test_starter_short_name_normalized():
	var parsed := _parse(["--starter=fast"])
	assert_eq(parsed["config"]["starter"], &"starter_fast")

func test_starter_full_name_passes_through():
	var parsed := _parse(["--starter=starter_aggro"])
	assert_eq(parsed["config"]["starter"], &"starter_aggro")

func test_heuristic_ai_flag():
	var parsed := _parse(["--heuristic-ai"])
	assert_true(parsed["config"].get("heuristic_ai", false))

func test_fair_tiebreak_flag():
	var parsed := _parse(["--fair-tiebreak"])
	assert_true(parsed["config"].get("fair_tiebreak", false))

func test_ai_seat_abilities_flag():
	var parsed := _parse(["--ai-seat-abilities"])
	assert_true(parsed["config"].get("ai_seat_abilities", false))

func test_starting_hp_override():
	var parsed := _parse(["--starting-hp=2"])
	assert_eq(parsed["config"]["starting_hp_override"], 2)

func test_rank_hp_delta_override_parsed():
	var parsed := _parse(["--rank-hp-delta=0,-1,-1,-2"])
	assert_eq(parsed["config"]["rank_hp_delta_override"], [0, -1, -1, -2])

func test_max_nodes_parsed():
	var parsed := _parse(["--max-nodes=50"])
	assert_eq(parsed["config"]["max_nodes_per_run"], 50)

func test_unknown_flag_collected_not_silently_dropped():
	# 这是 baseline 11 误用 `--ai-abilities` 的回归覆盖：未知 flag 必须被
	# parse_args 报告，让 _init 能 printerr 警告，避免再次 silent failure。
	var parsed := _parse(["--ai-abilities"])
	assert_eq(parsed["unknown_flags"], ["--ai-abilities"])
	# 同时 ai_seat_abilities 必须 false（说明误用 flag 没意外被识别）
	assert_false(parsed["config"].get("ai_seat_abilities", false))

func test_multiple_unknown_flags_all_collected():
	var parsed := _parse(["--bogus", "--also-bogus", "--runs=5"])
	assert_eq(parsed["unknown_flags"].size(), 2)
	assert_true(parsed["unknown_flags"].has("--bogus"))
	assert_true(parsed["unknown_flags"].has("--also-bogus"))
	# 已知 flag 仍正常生效
	assert_eq(parsed["config"]["runs"], 5)

func test_non_flag_args_not_collected_as_unknown():
	# 只有 `--xxx` 形式的 args 才视为 flag；其他参数（如位置参数）忽略
	var parsed := _parse(["positional", "value-like", "--runs=3"])
	assert_eq(parsed["unknown_flags"].size(), 0)
	assert_eq(parsed["config"]["runs"], 3)

func test_combined_flags_full_parse():
	var args: Array = [
		"--runs=15", "--seed=1000", "--starter=control",
		"--heuristic-ai", "--fair-tiebreak", "--ai-seat-abilities",
	]
	var parsed := _parse(args)
	var c: Dictionary = parsed["config"]
	assert_eq(c["runs"], 15)
	assert_eq(c["seed"], 1000)
	assert_eq(c["starter"], &"starter_control")
	assert_true(c["heuristic_ai"])
	assert_true(c["fair_tiebreak"])
	assert_true(c["ai_seat_abilities"])
	assert_eq(parsed["unknown_flags"].size(), 0)
