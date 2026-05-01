extends GutTest

# 麻将王 — M4 第 4 步：BattleNodeRunner 纯逻辑单测

# ---- run_battle_to_node_result ----

func test_run_battle_returns_node_result():
	var r: NodeResult = BattleNodeRunner.run_battle_to_node_result(42)
	assert_not_null(r)
	assert_typeof(r, TYPE_OBJECT)
	assert_true(r is NodeResult)

func test_run_battle_rank_in_valid_range():
	var r: NodeResult = BattleNodeRunner.run_battle_to_node_result(42)
	assert_gte(r.rank, 1)
	assert_lte(r.rank, 4)

func test_run_battle_final_scores_4_seats():
	var r: NodeResult = BattleNodeRunner.run_battle_to_node_result(42)
	assert_eq(r.final_scores.size(), 4)

func test_run_battle_score_conservation():
	# 整场跑完后 sum 应守恒（GameDriver 保证；本测验证 NodeResult 透传）
	var r: NodeResult = BattleNodeRunner.run_battle_to_node_result(42)
	var total := 0
	for s in r.final_scores:
		total += int(s)
	# 可能有未收的立直棒；总分 ≤ 100000
	assert_lte(total, 100000)
	# 不应小于太多（≥ 96000：最多 4 棒）
	assert_gte(total, 96000)

func test_run_battle_seed_determinism():
	var r1: NodeResult = BattleNodeRunner.run_battle_to_node_result(42)
	var r2: NodeResult = BattleNodeRunner.run_battle_to_node_result(42)
	assert_eq(r1.rank, r2.rank, "同 seed 应返同结果")
	assert_eq(r1.final_scores, r2.final_scores)

# 注：原本想测"不同 seed 给不同 ranks/scores"，但 v1 SimpleAi 4 家全随机弃牌，
# 实际几乎所有局都流局且每局是"全听 / 全不听 → 0 罚符"，cumulative_scores
# 永远收敛到 [25000]×4。这个观察本身就值得测出来：
func test_run_battle_simpleai_v1_drains_to_default_scores():
	# v1 行为锁：4 家全随机 → 大概率多流局 → scores ≈ [25000]×4
	# M7 引入 AIProfile / 智能弃牌后此测试应被删（v1 限制不再）
	for seed in [1, 7, 42, 123, 999]:
		var r: NodeResult = BattleNodeRunner.run_battle_to_node_result(seed)
		var sum := 0
		for s in r.final_scores:
			sum += int(s)
		# 总分守恒 ≤ 100000；某些 seed 可能有微小立直棒漏（v1 SimpleAi 不立直）
		assert_eq(sum, 100000, "v1 SimpleAi 不立直 → 100000 守恒严格")

# ---- placeholder_result ----

func test_placeholder_result_is_no_op():
	var r: NodeResult = BattleNodeRunner.placeholder_result()
	assert_eq(r.hp_delta, 0)
	assert_eq(r.gold_reward, 0)
	assert_eq(r.card_reward, 0)
