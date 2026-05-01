extends GutTest

# 麻将王 — M5 第 1 步：CardPack 主题包单测

func test_pack_size_is_5():
	# spec §9.2 第 2 行：5 张牌的捆绑
	assert_eq(CardPack.PACK_SIZE, 5)

func test_guarantee_index_is_last():
	assert_eq(CardPack.GUARANTEE_INDEX, CardPack.PACK_SIZE - 1)

func test_three_themes():
	# 火力 / 速胡 / 控场
	assert_eq(CardPack.Kind.AGGRO, 0)
	assert_eq(CardPack.Kind.FAST, 1)
	assert_eq(CardPack.Kind.CONTROL, 2)

func test_display_names():
	assert_eq(CardPack.display_name(CardPack.Kind.AGGRO), "火力包")
	assert_eq(CardPack.display_name(CardPack.Kind.FAST), "速胡包")
	assert_eq(CardPack.display_name(CardPack.Kind.CONTROL), "控场包")
	assert_eq(CardPack.display_name(99), "?")

func test_theme_from_id():
	assert_eq(CardPack.theme_from_id(&"aggro"), CardPack.Kind.AGGRO)
	assert_eq(CardPack.theme_from_id(&"fast"), CardPack.Kind.FAST)
	assert_eq(CardPack.theme_from_id(&"control"), CardPack.Kind.CONTROL)
	# 未知 id fallback 到 AGGRO
	assert_eq(CardPack.theme_from_id(&"unknown"), CardPack.Kind.AGGRO)

func test_rarity_weights_sum_to_100_per_theme():
	for theme in [CardPack.Kind.AGGRO, CardPack.Kind.FAST, CardPack.Kind.CONTROL]:
		var w: Array = CardPack.rarity_weights_for_theme(theme)
		assert_eq(w.size(), Rarity.COUNT)
		var sum := 0.0
		for v in w:
			sum += float(v)
		assert_almost_eq(sum, 100.0, 0.01, "theme=%d 权重和 100" % theme)

func test_aggro_has_highest_legendary_weight():
	# 火力主题应是 LEGENDARY 权重最高的（v1 设计：5.0 vs FAST 3.0 / CONTROL 4.0）
	var aggro_w: Array = CardPack.rarity_weights_for_theme(CardPack.Kind.AGGRO)
	var fast_w: Array = CardPack.rarity_weights_for_theme(CardPack.Kind.FAST)
	var control_w: Array = CardPack.rarity_weights_for_theme(CardPack.Kind.CONTROL)
	assert_gte(float(aggro_w[Rarity.Kind.LEGENDARY]), float(fast_w[Rarity.Kind.LEGENDARY]))
	assert_gte(float(aggro_w[Rarity.Kind.LEGENDARY]), float(control_w[Rarity.Kind.LEGENDARY]))
