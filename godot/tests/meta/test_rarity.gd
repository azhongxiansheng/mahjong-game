extends GutTest

# 麻将王 — M5 第 1 步：Rarity 单测

func test_kind_count_is_4():
	assert_eq(Rarity.COUNT, 4)

func test_node_single_weights_sum_to_100():
	var total := 0.0
	for w in Rarity.NODE_SINGLE_WEIGHTS:
		total += float(w)
	assert_almost_eq(total, 100.0, 0.001, "spec §9.1 4 档概率和 100%")

func test_display_names():
	assert_eq(Rarity.display_name(Rarity.Kind.COMMON), "普通")
	assert_eq(Rarity.display_name(Rarity.Kind.UNCOMMON), "精良")
	assert_eq(Rarity.display_name(Rarity.Kind.EPIC), "史诗")
	assert_eq(Rarity.display_name(Rarity.Kind.LEGENDARY), "神话")
	assert_eq(Rarity.display_name(99), "?")

func test_is_epic_or_above():
	assert_false(Rarity.is_epic_or_above(Rarity.Kind.COMMON))
	assert_false(Rarity.is_epic_or_above(Rarity.Kind.UNCOMMON))
	assert_true(Rarity.is_epic_or_above(Rarity.Kind.EPIC))
	assert_true(Rarity.is_epic_or_above(Rarity.Kind.LEGENDARY))

func test_pick_weighted_distribution():
	# 1000 次抽样，验证 spec §9.1 频率 ±5% 内
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var counts: Array = [0, 0, 0, 0]
	const N := 1000
	for i in range(N):
		var k: int = Rarity.pick_weighted(Rarity.NODE_SINGLE_WEIGHTS, rng)
		counts[k] += 1
	# 期望 60/28/10/2，允许 ±5% 绝对偏差
	assert_almost_eq(float(counts[0]) / N, 0.60, 0.05, "COMMON ≈ 60%")
	assert_almost_eq(float(counts[1]) / N, 0.28, 0.05, "UNCOMMON ≈ 28%")
	assert_almost_eq(float(counts[2]) / N, 0.10, 0.05, "EPIC ≈ 10%")
	assert_almost_eq(float(counts[3]) / N, 0.02, 0.02, "LEGENDARY ≈ 2%")

func test_pick_weighted_zero_total_falls_back_to_common():
	var rng := RandomNumberGenerator.new()
	assert_eq(Rarity.pick_weighted([0.0, 0.0, 0.0, 0.0], rng), Rarity.Kind.COMMON)

func test_pack_guarantee_excludes_common():
	# PACK_GUARANTEE_WEIGHTS[COMMON] 必须是 0 — 包内最后一张保底 UNCOMMON+
	assert_eq(Rarity.PACK_GUARANTEE_WEIGHTS[Rarity.Kind.COMMON], 0.0)
	var sum_above := 0.0
	for i in range(1, 4):
		sum_above += float(Rarity.PACK_GUARANTEE_WEIGHTS[i])
	assert_gt(sum_above, 0.0, "保底权重至少有非零档")
