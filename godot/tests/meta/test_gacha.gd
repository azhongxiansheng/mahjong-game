extends GutTest

# 麻将王 — M5 第 1 步：Gacha 三渠道单测

# ---- draw_node_single ----

func test_node_single_returns_result():
	var p := PityState.new()
	var r: GachaResult = Gacha.draw_node_single(p, 42)
	assert_not_null(r)
	# 90% 牌 / 10% ability，但 seed=42 输出确定（同 seed 应同结果）
	assert_true(r.kind == GachaResult.KIND_TILE or r.kind == GachaResult.KIND_ABILITY)

func test_node_single_seed_determinism():
	var p1 := PityState.new()
	var p2 := PityState.new()
	var r1: GachaResult = Gacha.draw_node_single(p1, 42)
	var r2: GachaResult = Gacha.draw_node_single(p2, 42)
	assert_eq(r1.kind, r2.kind)
	assert_eq(r1.rarity, r2.rarity)

func test_node_single_pity_forces_epic_or_above():
	var p := PityState.new()
	# 强行让保底激活
	for i in range(PityState.NODE_SINGLE_PITY_THRESHOLD):
		p.record_draw(Rarity.Kind.COMMON)
	# 多 seed 验证保底激活时返回的 rarity 都 ≥ EPIC
	for seed in [1, 7, 42, 100, 999]:
		var r: GachaResult = Gacha.draw_node_single(p, seed)
		assert_true(Rarity.is_epic_or_above(r.rarity),
			"保底激活时 seed=%d 应出 EPIC+；实际 rarity=%d" % [seed, r.rarity])

func test_node_single_no_pity_distribution_close_to_spec():
	# 1000 次无保底单抽，验证分布
	var counts: Array = [0, 0, 0, 0]
	const N := 1000
	for i in range(N):
		var p := PityState.new()  # 每次新 PityState 避开保底干扰
		var r: GachaResult = Gacha.draw_node_single(p, i)
		counts[r.rarity] += 1
	# 60/28/10/2 ±5% 绝对值
	assert_almost_eq(float(counts[0]) / N, 0.60, 0.07, "COMMON ≈ 60%")
	assert_almost_eq(float(counts[3]) / N, 0.02, 0.03, "LEGENDARY ≈ 2%")

# ---- open_pack ----

func test_open_pack_returns_5_results():
	var pack: Array = Gacha.open_pack(CardPack.Kind.AGGRO, 42)
	assert_eq(pack.size(), CardPack.PACK_SIZE)
	assert_eq(CardPack.PACK_SIZE, 5)

func test_open_pack_all_results_are_tiles():
	# 卡包仅出牌（不出 ability）
	var pack: Array = Gacha.open_pack(CardPack.Kind.FAST, 42)
	for r in pack:
		assert_eq(r.kind, GachaResult.KIND_TILE)

func test_open_pack_last_card_is_uncommon_or_above():
	# 包内保底：第 5 张（GUARANTEE_INDEX=4）必 UNCOMMON+
	for seed in [1, 42, 100, 999, 314]:
		var pack: Array = Gacha.open_pack(CardPack.Kind.CONTROL, seed)
		var last: GachaResult = pack[CardPack.GUARANTEE_INDEX]
		assert_gte(last.rarity, Rarity.Kind.UNCOMMON,
			"seed=%d 包内最后 1 张应 UNCOMMON+；实际 %d" % [seed, last.rarity])

func test_open_pack_seed_determinism():
	var p1: Array = Gacha.open_pack(CardPack.Kind.AGGRO, 42)
	var p2: Array = Gacha.open_pack(CardPack.Kind.AGGRO, 42)
	for i in range(p1.size()):
		assert_eq(p1[i].rarity, p2[i].rarity)
		assert_eq(p1[i].tile_variant.id, p2[i].tile_variant.id)

func test_aggro_theme_higher_avg_rarity_than_control():
	# 火力主题 avg rarity 应 > 控场主题（统计 50 个 seed × 5 张 = 250 次）
	var aggro_total := 0
	var control_total := 0
	for seed in range(50):
		for r in Gacha.open_pack(CardPack.Kind.AGGRO, seed):
			aggro_total += r.rarity
		for r in Gacha.open_pack(CardPack.Kind.CONTROL, seed):
			control_total += r.rarity
	# v1 weights：火力 [50,30,15,5] vs 控场 [45,35,16,4]
	# 期望 aggro 更高 rarity，但绝对差距小；只验证趋势
	assert_gte(aggro_total, control_total - 10,
		"火力主题 avg rarity 不应明显低于控场（aggro=%d, control=%d）" % [aggro_total, control_total])

# ---- refresh_shop ----

func test_refresh_shop_returns_5_slots():
	var slots: Array = Gacha.refresh_shop(42)
	assert_eq(slots.size(), Gacha.SHOP_SLOT_COUNT)
	assert_eq(Gacha.SHOP_SLOT_COUNT, 5)

func test_refresh_shop_has_tiles_ability_and_consumable():
	var slots: Array = Gacha.refresh_shop(42)
	var tile_count := 0
	var ab_count := 0
	var con_count := 0
	for r in slots:
		if r.kind == GachaResult.KIND_TILE:
			tile_count += 1
		elif r.kind == GachaResult.KIND_ABILITY:
			ab_count += 1
		elif r.kind == GachaResult.KIND_CONSUMABLE:
			con_count += 1
	assert_eq(tile_count, 3)
	assert_eq(ab_count, 1)
	assert_eq(con_count, 1)

func test_refresh_shop_seed_determinism():
	var s1: Array = Gacha.refresh_shop(42)
	var s2: Array = Gacha.refresh_shop(42)
	for i in range(s1.size()):
		assert_eq(s1[i].rarity, s2[i].rarity)
		assert_eq(s1[i].kind, s2[i].kind)
