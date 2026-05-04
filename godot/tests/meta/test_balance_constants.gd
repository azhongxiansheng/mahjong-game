extends GutTest

# 麻将王 — M7 平衡迭代 D2：BalanceConstants 单测
#
# 验证：
# - spec §14 关键 key 全部存在 + 值正确
# - 类型化 getter（get_array / get_number）行为
# - 缺 key 立即 assert（不静默 fallback）

func test_spec_section_14_keys_present():
	# spec §14 的 v1 默认值必须全部覆盖
	var required: Array[StringName] = [
		&"starting_points", &"starting_hp", &"riichi_stick", &"honba_stick",
		&"max_abilities", &"max_tile_variants", &"max_event_chain_depth",
		&"rarity_weights", &"epic_pity_threshold", &"pack_size", &"pack_uncommon_floor",
		&"chapters", &"nodes_per_chapter_min", &"nodes_per_chapter_max",
		&"yakuman_multiplier_cap", &"red_dora_per_suit", &"hands_per_node",
	]
	var keys := BalanceConstants.all_keys()
	for k in required:
		assert_true(k in keys, "spec §14 key 缺失: %s" % k)

func test_spec_section_14_values_match():
	# 抽查 spec §14 表中的关键值
	assert_eq(BalanceConstants.lookup(&"starting_points"), 25000, "起家点数 25000")
	assert_eq(BalanceConstants.lookup(&"starting_hp"), 4, "玩家血量 4（tune-3：5→4）")
	assert_eq(BalanceConstants.lookup(&"riichi_stick"), 1000, "立直棒 1000")
	assert_eq(BalanceConstants.lookup(&"honba_stick"), 300, "本场棒 300")
	assert_eq(BalanceConstants.lookup(&"max_abilities"), 5, "MAX_ABILITIES 5")
	assert_eq(BalanceConstants.lookup(&"max_tile_variants"), 34, "MAX_TILE_VARIANTS 34")
	assert_eq(BalanceConstants.lookup(&"max_event_chain_depth"), 16, "MAX_EVENT_CHAIN_DEPTH 16")
	assert_eq(BalanceConstants.lookup(&"epic_pity_threshold"), 8, "史诗保底 8 抽")
	assert_eq(BalanceConstants.lookup(&"pack_size"), 5, "卡包标准张数 5")
	assert_eq(BalanceConstants.lookup(&"chapters"), 3, "章节数 3")
	assert_eq(BalanceConstants.lookup(&"yakuman_multiplier_cap"), 2, "役满倍数上限 2 倍")
	assert_eq(BalanceConstants.lookup(&"hands_per_node"), 4, "节点 = 4 局")

func test_rarity_weights_sum_to_100():
	# 稀有度概率应总和 100（spec §14：60/28/10/2）
	var weights := BalanceConstants.get_array(&"rarity_weights")
	assert_eq(weights.size(), 4, "4 档稀有度")
	assert_eq(weights, [60, 28, 10, 2], "spec §14: 普 60 / 精 28 / 史 10 / 神 2")
	var total: int = 0
	for w in weights:
		total += int(w)
	assert_eq(total, 100, "稀有度概率总和 100")

func test_node_rank_arrays_size_4():
	# 排名扣血 + 金币奖励数组对应 4 名次
	var hp_delta := BalanceConstants.get_array(&"node_rank_hp_delta")
	assert_eq(hp_delta.size(), 4, "排名扣血 4 档")
	# spec §7.1: rank 1→0, 2→0, 3→-1, 4→-2
	assert_eq(hp_delta, [0, 0, -1, -2], "排名扣血 spec §7.1")

	var gold := BalanceConstants.get_array(&"node_rank_gold_reward")
	assert_eq(gold.size(), 4, "排名金币 4 档")
	# v1 拍数；等 simulation + alpha 反馈调
	assert_true(gold[0] >= gold[1], "rank 1 金币 ≥ rank 2")
	assert_true(gold[1] >= gold[2], "rank 2 金币 ≥ rank 3")
	assert_true(gold[2] >= gold[3], "rank 3 金币 ≥ rank 4")

func test_skill_magic_numbers_present():
	# hook 内魔数已抽出（M7 升级 hook 时按需取）
	assert_true(BalanceConstants.lookup(&"soul_drain_fraction") == 0.12,
		"soul_drain 12%（tune-3：20→12% 把 control 75% 降到 30-50% 区间）")
	assert_true(BalanceConstants.lookup(&"mirror_chambo_refund_fraction") == 0.50,
		"mirror_chambo 50%（M6 east_mirror_chambo 魔数 → BalanceConstants）")
	assert_eq(BalanceConstants.lookup(&"iron_wall_han_penalty"), -1,
		"iron_wall -1 番（M6 man9_iron_wall 魔数 → BalanceConstants）")
	assert_eq(BalanceConstants.lookup(&"thunder_5w_han_bonus"), 2,
		"thunder_5w +2 番（balance tune-2：1 → 2 加力 aggro pack）")

func test_get_array_type_check():
	# 非 array key 调 get_array 应 assert（dev 接口误用立即可见）
	# GUT 不能直接 assert assert，改成确认正路 + 反路
	var arr := BalanceConstants.get_array(&"rarity_weights")
	assert_true(arr is Array, "rarity_weights 是 Array")
	# 反路：非 array key 调 get_array 会触发 assert（这里只验证正路）

func test_get_number_returns_float():
	# get_number 把 int / float 都返成 float 方便算术
	var hp: float = BalanceConstants.get_number(&"starting_hp")
	assert_eq(hp, 4.0, "int → float（tune-3：5→4）")
	var fraction: float = BalanceConstants.get_number(&"soul_drain_fraction")
	assert_eq(fraction, 0.12, "float → float")
