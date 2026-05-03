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
	# M7 D4 扩展
	assert_true(s.contains("局结果分布"), "summary 含局结果分布")
	assert_true(s.contains("各 seat"), "summary 含 seat 平均点数")

# ---- M7 D4 扩展统计 ----

func test_simulate_returns_extended_keys():
	var stats := SimulationHarness.simulate({"runs": 2, "seed": 13})
	var required: Array[String] = [
		"hand_kind_total", "hand_kind_pct", "hand_total",
		"avg_seat_score", "seat_score_samples",
	]
	for k in required:
		assert_true(stats.has(k), "stats 缺 M7 D4 扩展 key: %s" % k)

func test_hand_kind_total_keys():
	var stats := SimulationHarness.simulate({"runs": 2, "seed": 17})
	var hkt: Dictionary = stats.hand_kind_total
	for k in ["tsumo", "ron", "exhaustive_draw"]:
		assert_true(hkt.has(k), "hand_kind_total 含 %s" % k)
		assert_true(int(hkt[k]) >= 0, "%s 计数 ≥ 0" % k)

func test_hand_total_equals_sum_of_kinds():
	var stats := SimulationHarness.simulate({"runs": 2, "seed": 19})
	var hkt: Dictionary = stats.hand_kind_total
	var sum: int = int(hkt.get("tsumo", 0)) + int(hkt.get("ron", 0)) + int(hkt.get("exhaustive_draw", 0))
	assert_eq(stats.hand_total, sum, "hand_total = sum(hand_kind_total)")

func test_hand_kind_pct_sums_to_1():
	var stats := SimulationHarness.simulate({"runs": 3, "seed": 23})
	if stats.hand_total == 0:
		return  # 没局打 → 跳过百分比测试
	var pct: Dictionary = stats.hand_kind_pct
	var sum: float = 0.0
	for v in pct.values():
		sum += float(v)
	assert_almost_eq(sum, 1.0, 0.001, "hand_kind_pct 总和 ≈ 1.0")

func test_avg_seat_score_size_4():
	var stats := SimulationHarness.simulate({"runs": 2, "seed": 29})
	var ass: Array = stats.avg_seat_score
	assert_eq(ass.size(), 4, "avg_seat_score 4 元素（4 seats）")

func test_avg_seat_score_sum_close_to_100000():
	# 麻将守恒：4 家点数总和 = 4 × 25000 = 100000（不计立直棒）
	# 节点结束时立直棒收走 / 跨局保留，所以节点终局点数 sum 可能偏离少量
	# 但 |sum - 100000| 应在 ±立直棒数 × 1000 范围内（v1 不立直 → 应严格 100000）
	var stats := SimulationHarness.simulate({"runs": 5, "seed": 31})
	var ass: Array = stats.avg_seat_score
	if stats.seat_score_samples == 0:
		return
	var total: float = 0.0
	for s in ass:
		total += float(s)
	# 当前 SimpleAi 不立直 → 立直棒永远 0，4 家应严格守恒
	assert_almost_eq(total, 100000.0, 100.0,
		"4 家平均点数总和 ≈ 100000（守恒 + SimpleAi 不立直）")
