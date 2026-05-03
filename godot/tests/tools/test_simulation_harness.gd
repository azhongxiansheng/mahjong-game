extends GutTest

# 麻将王 — M7 D4 simulation harness 单测

const MIN_RUNS_FOR_STAT_TEST: int = 5

func test_simulate_returns_required_keys():
	var stats := SimulationHarness.simulate({"runs": 2, "seed": 1})
	var required: Array[String] = [
		"runs", "seed", "starter",
		"completed", "failed", "completion_rate",
		"failed_at_chapter",
		"avg_nodes_per_run", "min_nodes", "max_nodes",
		"avg_final_hp", "max_hp",
	]
	for k in required:
		assert_true(stats.has(k), "stats 缺 key: %s" % k)

func test_simulate_completion_rate_in_unit_interval():
	var stats := SimulationHarness.simulate({"runs": MIN_RUNS_FOR_STAT_TEST, "seed": 7})
	var rate: float = stats.completion_rate
	assert_true(rate >= 0.0 and rate <= 1.0,
		"completion_rate 必须 ∈ [0, 1]，得到 %f" % rate)

func test_simulate_runs_count_matches_input():
	var stats := SimulationHarness.simulate({"runs": 3, "seed": 2})
	assert_eq(stats.runs, 3, "runs key 必须等于 input")
	# completed + failed 不必等于 runs（可能 max_nodes 截断；但 ≤ runs）
	assert_true(stats.completed <= stats.runs, "completed ≤ runs")
	assert_true(stats.failed <= stats.runs, "failed ≤ runs")

func test_simulate_failed_at_chapter_size_3():
	var stats := SimulationHarness.simulate({"runs": MIN_RUNS_FOR_STAT_TEST, "seed": 11})
	var fbc: Array = stats.failed_at_chapter
	assert_eq(fbc.size(), 3, "failed_at_chapter 3 元素（章 1/2/3）")
	for v in fbc:
		assert_true(int(v) >= 0, "失败计数 ≥ 0")

func test_simulate_with_no_starter():
	# starter=&"" 应跳过起始包注入，仍然能跑
	var stats := SimulationHarness.simulate({"runs": 2, "seed": 3, "starter": &""})
	assert_eq(stats.runs, 2)
	assert_true(stats.completion_rate >= 0.0)

func test_simulate_deterministic_with_same_seed():
	# 同 seed 同 config 必出同结果（决定性验证；不验证具体数值）
	var stats_a := SimulationHarness.simulate({"runs": 3, "seed": 99})
	var stats_b := SimulationHarness.simulate({"runs": 3, "seed": 99})
	assert_eq(stats_a.completed, stats_b.completed, "通关数同 seed 一致")
	assert_eq(stats_a.failed, stats_b.failed, "失败数同 seed 一致")
	assert_eq(stats_a.avg_final_hp, stats_b.avg_final_hp, "平均 HP 同 seed 一致")

func test_format_summary_contains_key_metrics():
	var stats := SimulationHarness.simulate({"runs": 2, "seed": 5})
	var s: String = SimulationHarness.format_summary(stats)
	assert_true(s.contains("通关率"), "summary 含通关率")
	assert_true(s.contains("失败"), "summary 含失败计数")
	assert_true(s.contains("节点 / Run"), "summary 含节点数")
	assert_true(s.contains("最终 HP"), "summary 含最终 HP")
