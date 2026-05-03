# 麻将王 — M7 平衡迭代 D2：数值集中表
#
# 把散在 spec §14 + hook 内魔数 + Resource 默认值 + 抽卡概率的
# 数值参数集中到一份字典，单一来源。每次平衡调整改这里 + 跑
# simulation 验证（D6 三步法）。
#
# 用法：BalanceConstants.lookup(&"starting_hp")  → 5
# 用法：BalanceConstants.get_array(&"rarity_weights")  → [60,28,10,2]
#
# 注：方法名用 lookup 而非 get，避免与 Godot 内建 Object.get(name) 冲突
# （class_name + static get 会被 GDScript 解析器识别为属性访问而非方法调用）。
#
# v1 用 const dict + static get；未来需要多套数值（高难度模式 / 玩家
# 自定义）时升级为 .tres Resource。
class_name BalanceConstants

const VALUES: Dictionary = {
	# ---- 经济 / 起始（spec §14） ----
	&"starting_points": 25000,
	&"starting_hp": 5,
	&"max_hp": 5,
	&"riichi_stick": 1000,
	&"honba_stick": 300,

	# ---- 卡组（spec §14） ----
	&"max_abilities": 5,
	&"max_tile_variants": 34,
	&"max_event_chain_depth": 16,

	# ---- 抽卡（spec §9.1 / §14） ----
	# 稀有度概率 [普, 精, 史, 神]，单抽
	&"rarity_weights": [60, 28, 10, 2],
	&"epic_pity_threshold": 8,
	&"pack_size": 5,
	&"pack_uncommon_floor": 1,

	# ---- 章节 / 节点（spec §14） ----
	&"chapters": 3,
	&"nodes_per_chapter_min": 12,
	&"nodes_per_chapter_max": 15,
	# 节点排名扣血映射 [rank1, rank2, rank3, rank4]
	&"node_rank_hp_delta": [0, 0, -1, -2],
	# 节点排名金币奖励（v1 拍数，等 simulation + alpha 反馈调）
	&"node_rank_gold_reward": [30, 15, 5, 0],

	# ---- 役満（spec §14） ----
	&"yakuman_multiplier_cap": 2,
	&"red_dora_per_suit": 1,

	# ---- 局参数（spec §14） ----
	&"hands_per_node": 4,            # 一节点 = 东风战 4 局

	# ---- 技能数值（hook 引用，逐步替换魔数） ----
	# §8.1 增番系
	# tune-2：thunder_5w 1 → 2（aggro pack 加力让 0% 通关向 5%+ 推）
	&"thunder_5w_han_bonus": 2,
	&"east_dynasty_dealer_tsumo_bonus": 2,
	# tune-2：白 / 发 三元牌 holder 自胡 +han（M7 升级前用 add_han 桩；从 1 → 2）
	&"white_haku_holy_han_bonus": 2,
	&"green_hatsu_serenity_han_bonus": 2,
	# §8.3 阻胡
	&"iron_wall_han_penalty": -1,
	# §8.4 抓马
	# soul_drain_fraction: M7 #66 数据显示 control pack 70% 通关偏 OP（baseline-3）；
	# 30% → 20% 降一档，让 control 跟 aggro/fast 拉近
	&"soul_drain_fraction": 0.20,
	&"mirror_chambo_refund_fraction": 0.50,
	&"sou8_scapegoat_han_penalty": -1,
	# §8.6 立直
	&"stick_refund_han_bonus": 1,
	# premature_riichi: aggro 0% 通关偏弱，从 +2 → +3 番尝试加力（spec 双立直 + 一发期望近 +3）
	&"premature_riichi_han_bonus": 3,
	# §8.7 振听操控
	&"man2_lure_han_bonus": 1,
	# §8.8 Dora
	&"sou4_uradora_han_bonus": 2,
	# §8.9 终局
	&"north_sweep_han_bonus": 3,
	# §8.10 角色能力
	# mineu_oni: aggro 0% 通关偏弱；2 → 3 番（杠后 5 选 1 期望应 ≥ +3 番）
	&"mineu_oni_han_bonus": 3,
	&"san_kyoku_kiseki_han_bonus": 1,
	&"ryukyoku_yudou_han_bonus": 1,
	&"tousotsu_han_bonus": 1,
	&"riichi_kago_han_bonus": 1,
	# 章 Boss
	&"boss3_kanmon_han_bonus": 3,
	# §8.5 透明牌（数字桩）
	&"pin2_bluff_han_bonus": 1,
	# §8.2 加速（数字桩）
	&"sou3_skip_han_bonus": 1,
	&"south_breeze_han_bonus": 1,
}

# 取值；缺 key 立即 assert（catch dev typo，不静默 fallback）。
static func lookup(key: StringName) -> Variant:
	assert(VALUES.has(key), "BalanceConstants 缺 key: %s" % key)
	return VALUES[key]

# 数组取值的便捷封装（同 get，但语义清晰；未来可加 .duplicate() 防误改）。
static func get_array(key: StringName) -> Array:
	var v: Variant = lookup(key)
	assert(v is Array, "BalanceConstants[%s] 不是 Array" % key)
	return v

# 数值取值（int / float），方便 hook 内做算术不需要 cast。
static func get_number(key: StringName) -> float:
	var v: Variant = lookup(key)
	assert(v is int or v is float, "BalanceConstants[%s] 不是 int/float" % key)
	return float(v)

# 全部 key 列表（test 用，验证 schema 完整性）。
static func all_keys() -> Array[StringName]:
	var keys: Array[StringName] = []
	for k in VALUES.keys():
		keys.append(k)
	return keys
