extends GutTest

# 麻将王 — 3 选 1 奖励系统 TDD

func test_gacha_draw_reward_options_returns_3():
	var pity := PityState.new()
	var options: Array = Gacha.draw_reward_options(pity, 42)
	assert_eq(options.size(), 3, "应返回 3 个奖励选项")

func test_each_option_is_valid_gacha_result():
	var pity := PityState.new()
	var options: Array = Gacha.draw_reward_options(pity, 42)
	for r in options:
		assert_true(
			r.kind == GachaResult.KIND_TILE or
			r.kind == GachaResult.KIND_ABILITY or
			r.kind == GachaResult.KIND_CONSUMABLE,
			"每个选项应有有效 kind"
		)

func test_reward_options_deterministic():
	var pity1 := PityState.new()
	var pity2 := PityState.new()
	var o1: Array = Gacha.draw_reward_options(pity1, 42)
	var o2: Array = Gacha.draw_reward_options(pity2, 42)
	for i in range(3):
		assert_eq(o1[i].kind, o2[i].kind, "相同 seed 应产生相同结果")
		assert_eq(o1[i].rarity, o2[i].rarity)

func test_reward_options_different_seeds():
	var pity := PityState.new()
	var o1: Array = Gacha.draw_reward_options(pity, 42)
	var o2: Array = Gacha.draw_reward_options(pity, 999)
	var all_same := true
	for i in range(3):
		if o1[i].rarity != o2[i].rarity or o1[i].kind != o2[i].kind:
			all_same = false
	assert_false(all_same, "不同 seed 应产生不同结果")

func test_reward_pick_view_scene_exists():
	var scene: PackedScene = load("res://ui/run/reward_pick_view.tscn")
	assert_not_null(scene)

func test_skip_gold_reward_constant():
	assert_gt(RewardPickView.SKIP_GOLD_REWARD, 0, "跳过奖励应为正数金币")

func test_reward_count_constant():
	assert_eq(Gacha.REWARD_OPTION_COUNT, 3, "奖励选项应为 3")

func test_10_seeds_all_produce_3_valid_options():
	var pity := PityState.new()
	for s in range(10):
		var options: Array = Gacha.draw_reward_options(pity, s * 13 + 7)
		assert_eq(options.size(), 3, "seed %d 应有 3 选项" % s)
		for r in options:
			assert_not_null(r, "seed %d 不该有 null" % s)
