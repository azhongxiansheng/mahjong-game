extends GutTest

# 麻将王 — M4 第 1 步：NodeResult 单测
# 覆盖 spec §7.1 排名 → hp_delta + rank_for_seat 推导 + from_placeholder 占位。

# ---- HP_DELTA_BY_RANK / 构造函数 ----

func test_rank_1_no_hp_loss():
	var r := NodeResult.new(1)
	assert_eq(r.rank, 1)
	assert_eq(r.hp_delta, 0, "rank 1 不掉血")
	assert_eq(r.gold_reward, 30)

func test_rank_2_no_hp_loss():
	var r := NodeResult.new(2)
	assert_eq(r.hp_delta, 0, "rank 2 不掉血")
	assert_eq(r.gold_reward, 15)

func test_rank_3_loses_1_hp():
	var r := NodeResult.new(3)
	assert_eq(r.hp_delta, -1, "rank 3 -1 hp")
	assert_eq(r.gold_reward, 5)

func test_rank_4_loses_2_hp():
	var r := NodeResult.new(4)
	assert_eq(r.hp_delta, -2, "rank 4 -2 hp")
	assert_eq(r.gold_reward, 0)

func test_rank_clamped_below_1():
	var r := NodeResult.new(0)
	assert_eq(r.rank, 1, "0 → clamp 到 1")

func test_rank_clamped_above_4():
	var r := NodeResult.new(99)
	assert_eq(r.rank, 4, "99 → clamp 到 4")

func test_card_reward_default_is_1():
	# spec §7：每节点给 1 抽（M5 实装真抽卡）
	assert_eq(NodeResult.new(1).card_reward, 1)

func test_final_scores_passed_through():
	var scores := [30000, 25000, 20000, 25000]
	var r := NodeResult.new(1, scores)
	assert_eq(r.final_scores, scores)

# ---- rank_for_seat 静态推导 ----

func test_rank_for_seat_winner():
	var scores := [30000, 25000, 25000, 20000]
	assert_eq(NodeResult.rank_for_seat(scores, 0), 1, "30000 是最高")

func test_rank_for_seat_last():
	var scores := [30000, 25000, 25000, 20000]
	assert_eq(NodeResult.rank_for_seat(scores, 3), 4, "20000 是最低")

func test_rank_for_seat_tied():
	# 同分时 viewer 优先得高排名（v1 简化）
	var scores := [25000, 25000, 25000, 25000]
	assert_eq(NodeResult.rank_for_seat(scores, 0), 1)
	assert_eq(NodeResult.rank_for_seat(scores, 3), 1)

func test_rank_for_seat_invalid_seat():
	assert_eq(NodeResult.rank_for_seat([25000, 25000, 25000, 25000], -1), 4)
	assert_eq(NodeResult.rank_for_seat([25000, 25000, 25000, 25000], 99), 4)

# ---- from_placeholder ----

func test_from_placeholder_no_hp_no_reward():
	var r := NodeResult.from_placeholder()
	assert_eq(r.hp_delta, 0, "占位节点不掉血")
	assert_eq(r.gold_reward, 0, "占位节点不给金币（由占位场景内部 hook）")
	assert_eq(r.card_reward, 0, "占位节点不给抽卡")
