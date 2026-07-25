class_name CardPool

# 麻将王 — 里程碑 5 第 1 步：卡牌池 v1 hardcoded（plan-5 D4）
#
# v1 内容：M1 demo 5 张牌技能 + 30 张占位"无技能牌"（每个数字花色一个普通占位
# 共 9+9+9=27 张，加 4 风 + 3 龙 = 34 张，但 v1 只取 30 简化）+ M1 demo 1 张
# 角色能力 + 5 张占位 ability。
#
# M6 内容生产时改为 ResourceLoader 扫 res://meta/data/cards/ 加载 .tres。

# ---- tile variants ----

# v1 池子：5 demo + 30 普通占位 + 一些精良/史诗占位
static func all_tile_variants() -> Array:
	var pool: Array = []

	# M1 demo skill 牌技能（rarity 由各自 demo 性质拍）
	var t5w := _mk_tile(&"thunder_5w_v1", "5万·闪电", "owner 自胡 +1 番（M1 demo）",
		TileId.W5, Rarity.Kind.UNCOMMON, "res://skills/hooks/thunder_5w_hook.gd")
	t5w.upgraded_skill_resource_path = "res://skills/hooks/thunder_5w_hook_plus.gd"
	pool.append(t5w)
	var sc := _mk_tile(&"seal_chun_v1", "中·封印", "持有者出铳被荣胡时取消",
		TileId.CHUN, Rarity.Kind.EPIC, "res://skills/hooks/seal_chun_hook.gd")
	sc.upgraded_skill_resource_path = "res://skills/hooks/seal_chun_hook_plus.gd"
	pool.append(sc)
	pool.append(_mk_tile(&"soul_drain_hatsu_v1", "发·吸魂", "对手胡牌时转 30% 给 holder",
		TileId.HATSU, Rarity.Kind.EPIC, "res://skills/hooks/soul_drain_hatsu_hook.gd"))
	var x1w := _mk_tile(&"xray_1w_v1", "1万·透视", "owner 摸牌后 reveal 一张他家",
		TileId.W1, Rarity.Kind.LEGENDARY, "res://skills/hooks/xray_1w_hook.gd")
	x1w.upgraded_skill_resource_path = "res://skills/hooks/xray_1w_hook_plus.gd"
	pool.append(x1w)
	pool.append(_mk_tile(&"unfuriten_5p_v1", "5筒·解振听", "owner 进入振听时清除",
		TileId.T5, Rarity.Kind.UNCOMMON, "res://skills/hooks/unfuriten_5p_hook.gd"))

	# M6 内容生产：增番系（§8.1）
	pool.append(_mk_tile(&"white_haku_holy_v1", "白板·圣光", "持牌者作三元牌一员胡牌时 +1 番（v1 简化）",
		TileId.HAKU, Rarity.Kind.UNCOMMON, "res://skills/hooks/white_haku_holy_hook.gd"))
	pool.append(_mk_tile(&"green_hatsu_serenity_v1", "发·禅意", "任意人作三元牌一员胡牌时 +1 番（v1 简化为 holder 自胡）",
		TileId.HATSU, Rarity.Kind.UNCOMMON, "res://skills/hooks/green_hatsu_serenity_hook.gd"))

	# M6 内容生产：阻胡系（§8.3）
	pool.append(_mk_tile(&"man9_iron_wall_v1", "9 万·铁壁", "owner 被荣胡时役 -1 番",
		TileId.W9, Rarity.Kind.UNCOMMON, "res://skills/hooks/man9_iron_wall_hook.gd"))
	pool.append(_mk_tile(&"west_mirror_v1", "西风·镜像", "owner 立直时清振听 1 次",
		TileId.W_WIND, Rarity.Kind.EPIC, "res://skills/hooks/west_mirror_hook.gd"))

	# M6 内容生产：终局系（§8.9）
	pool.append(_mk_tile(&"pin9_haitei_double_v1", "9 筒·龙断", "海底/河底自摸 +1 番（v1 简化×2）",
		TileId.T9, Rarity.Kind.LEGENDARY, "res://skills/hooks/pin9_haitei_double_hook.gd"))

	# M6 内容生产：振听操控系（§8.7）
	pool.append(_mk_tile(&"east_phantom_v1", "东·迷踪", "owner 弃东被荣胡时取消（v1 简化版振听操控）",
		TileId.E, Rarity.Kind.EPIC, "res://skills/hooks/east_phantom_hook.gd"))
	pool.append(_mk_tile(&"man2_lure_v1", "2 万·诱铳", "owner 自胡 +1 番（v1 模拟伪装听牌收益）",
		TileId.W2, Rarity.Kind.EPIC, "res://skills/hooks/man2_lure_hook.gd"))
	pool.append(_mk_tile(&"chun_substitute_v1", "中·替身", "owner 自胡时若振听则清除（替身代担）",
		TileId.CHUN, Rarity.Kind.UNCOMMON, "res://skills/hooks/chun_substitute_hook.gd"))

	# M6 内容生产：增番系（§8.1 续）
	pool.append(_mk_tile(&"east_dynasty_v1", "东风·王者气", "owner 是庄家且自胡 +2 番（需 dealer_seat extra）",
		TileId.E, Rarity.Kind.LEGENDARY, "res://skills/hooks/east_dynasty_hook.gd"))

	# M6 内容生产：加速胡牌系（§8.2）
	pool.append(_mk_tile(&"pin9_speed_v1", "9 筒·速胡", "owner 自摸时强制海底（force_tsumo 模拟双摸收益）",
		TileId.T9, Rarity.Kind.UNCOMMON, "res://skills/hooks/pin9_speed_hook.gd"))
	pool.append(_mk_tile(&"sou3_skip_v1", "3 索·跳跃", "owner 自胡 +1 番（v1 模拟跳过下家收益）",
		TileId.S3, Rarity.Kind.UNCOMMON, "res://skills/hooks/sou3_skip_hook.gd"))
	pool.append(_mk_tile(&"south_riichi_breeze_v1", "南风·风行", "owner 自胡 +1 番（v1 模拟立直多看牌收益）",
		TileId.S_WIND, Rarity.Kind.EPIC, "res://skills/hooks/south_riichi_breeze_hook.gd"))

	# M6 内容生产：抓马反向得分系（§8.4）
	pool.append(_mk_tile(&"east_mirror_chambo_v1", "东·镜抓", "owner 放铳被荣胡时拿回 50% 得分（v1：transfer_points 实施）",
		TileId.E, Rarity.Kind.EPIC, "res://skills/hooks/east_mirror_chambo_hook.gd"))
	pool.append(_mk_tile(&"sou8_scapegoat_v1", "8 索·替罪", "owner 放铳时给胜者 -1 番（v1 模拟责任转嫁）",
		TileId.S8, Rarity.Kind.UNCOMMON, "res://skills/hooks/sou8_scapegoat_hook.gd"))

	# M6 内容生产：立直系（§8.6 续）
	pool.append(_mk_tile(&"south_premature_riichi_v1", "南·先制立直", "owner 自胡 +2 番（v1 模拟先制立直收益）",
		TileId.S_WIND, Rarity.Kind.LEGENDARY, "res://skills/hooks/south_premature_riichi_hook.gd"))
	pool.append(_mk_tile(&"hatsu_stick_refund_v1", "发·点棒返还", "owner 自胡 +1 番（v1 模拟立直棒返还）",
		TileId.HATSU, Rarity.Kind.UNCOMMON, "res://skills/hooks/hatsu_stick_refund_hook.gd"))

	# M6 内容生产：终局系（§8.9 续）
	pool.append(_mk_tile(&"north_sweep_v1", "北·一扫", "owner 自胡 +3 番（v1 模拟役满全场分摊）",
		TileId.N, Rarity.Kind.LEGENDARY, "res://skills/hooks/north_sweep_hook.gd"))
	pool.append(_mk_tile(&"white_mangan_floor_v1", "白·役满下限", "owner 自胡 +5 番（v1 模拟满贯下限，消耗品）",
		TileId.HAKU, Rarity.Kind.LEGENDARY, "res://skills/hooks/white_mangan_floor_hook.gd"))

	# M6 内容生产：透明牌 / 信息系（§8.5）
	pool.append(_mk_tile(&"white_oracle_v1", "白·占卜", "owner 摸牌后 reveal 一张未翻 Dora 占位",
		TileId.HAKU, Rarity.Kind.UNCOMMON, "res://skills/hooks/white_oracle_hook.gd"))
	pool.append(_mk_tile(&"pin2_bluff_v1", "2 筒·诈和", "owner 自胡 +1 番（v1 模拟伪装手牌收益）",
		TileId.T2, Rarity.Kind.EPIC, "res://skills/hooks/pin2_bluff_hook.gd"))

	# M6 内容生产：Dora 系（§8.8）
	pool.append(_mk_tile(&"man6_treasure_v1", "6 万·夺宝", "owner 自胡 +1 番（v1 模拟额外 Dora）",
		TileId.W6, Rarity.Kind.LEGENDARY, "res://skills/hooks/man6_treasure_hook.gd"))
	pool.append(_mk_tile(&"white_red_change_v1", "白·赤变", "owner 自胡 +1 番（v1 模拟红 5 dora）",
		TileId.HAKU, Rarity.Kind.UNCOMMON, "res://skills/hooks/white_red_change_hook.gd"))
	pool.append(_mk_tile(&"sou4_uradora_pick_v1", "4 索·指示牌操纵", "owner 自胡 +2 番（v1 模拟重选最优裏 Dora）",
		TileId.S4, Rarity.Kind.EPIC, "res://skills/hooks/sou4_uradora_pick_hook.gd"))

	# M12 新增牌技能
	pool.append(_mk_tile(&"w7_flow_ride_v1", "7 万·顺流", "owner 摸牌且 turn >= 3 时 reveal 牌墙顶 3 张",
		TileId.W7, Rarity.Kind.UNCOMMON, "res://skills/hooks/w7_flow_ride_hook.gd"))
	pool.append(_mk_tile(&"t5_double_draw_v1", "5 筒·双摸", "owner 胡牌 +1 番（双摸加成）",
		TileId.T5, Rarity.Kind.UNCOMMON, "res://skills/hooks/t5_double_draw_hook.gd"))
	pool.append(_mk_tile(&"s7_counter_ron_v1", "7 索·反击", "owner 被荣胡时偷回 20% 得分",
		TileId.S7, Rarity.Kind.EPIC, "res://skills/hooks/s7_counter_ron_hook.gd"))
	pool.append(_mk_tile(&"w3_furiten_spread_v1", "3 万·振听扩散", "owner 胡牌 +1 番（防御加成）",
		TileId.W3, Rarity.Kind.UNCOMMON, "res://skills/hooks/w3_furiten_spread_hook.gd"))
	pool.append(_mk_tile(&"t7_ippatsu_extend_v1", "7 筒·一发延长", "owner 立直下胡牌 +1 番",
		TileId.T7, Rarity.Kind.EPIC, "res://skills/hooks/t7_ippatsu_extend_hook.gd"))
	pool.append(_mk_tile(&"s1_yakuhai_boost_v1", "1 索·役牌加成", "owner 胡牌 +1 番（役牌加成）",
		TileId.S1, Rarity.Kind.UNCOMMON, "res://skills/hooks/s1_yakuhai_boost_hook.gd"))
	pool.append(_mk_tile(&"w8_kan_bonus_v1", "8 万·杠加成", "owner 有杠时胡牌 +2 番",
		TileId.W8, Rarity.Kind.EPIC, "res://skills/hooks/w8_kan_bonus_hook.gd"))
	pool.append(_mk_tile(&"chun_blood_pact_v1", "中·血盟", "owner 胡牌时从三家各转 1000 点",
		TileId.CHUN, Rarity.Kind.EPIC, "res://skills/hooks/chun_blood_pact_hook.gd"))

	# 30 张普通占位"无技能牌"，覆盖 30 个 TileId（万 9 + 筒 9 + 条 9 + 3 风）
	var placeholder_ids: Array = []
	for i in range(9):
		placeholder_ids.append(TileId.W1 + i)
		placeholder_ids.append(TileId.T1 + i)
		placeholder_ids.append(TileId.S1 + i)
	placeholder_ids.append(TileId.E)
	placeholder_ids.append(TileId.S_WIND)
	placeholder_ids.append(TileId.W_WIND)
	for tid in placeholder_ids:
		pool.append(_mk_tile(
			StringName("placeholder_%d" % tid),
			"普通牌（占位）",
			"v1 占位无技能牌；M6 内容化时替换",
			tid, Rarity.Kind.COMMON, ""
		))

	return pool

# 按 rarity 过滤
static func tile_variants_by_rarity(rarity: int) -> Array:
	var result: Array = []
	for v in all_tile_variants():
		if v.rarity == rarity:
			result.append(v)
	return result

# ---- abilities ----

static func all_abilities() -> Array:
	var pool: Array = []
	# M1 demo 1 张角色能力
	pool.append(_mk_ability(&"seabed_hunter_v1", "海底狩人",
		"海底捞月时强制 owner 自摸（M1 demo）",
		Rarity.Kind.LEGENDARY, "res://skills/hooks/seabed_hunter_hook.gd"))

	# M6 内容生产：神级角色能力（§8.10）
	pool.append(_mk_ability(&"shichu_kyu_katsu_v1", "死中求活",
		"owner 点棒 < 5000 时所有役 +2 番（spec §8.10 #11）",
		Rarity.Kind.LEGENDARY, "res://skills/hooks/shichu_kyu_katsu_hook.gd"))

	# M6 内容生产：3 章 Boss 签名能力（plan-6 C）
	pool.append(_mk_ability(&"boss1_iron_curtain_v1", "铁幕",
		"章 1 Boss：受到 RON 时强制取消（v1 简化：每次都取消，无消耗追踪）",
		Rarity.Kind.LEGENDARY, "res://skills/hooks/boss1_iron_curtain_hook.gd"))
	pool.append(_mk_ability(&"boss2_fortune_runner_v1", "福星",
		"章 2 Boss：自胡 +2 番（v1 简化模拟额外 Dora）",
		Rarity.Kind.LEGENDARY, "res://skills/hooks/boss2_fortune_runner_hook.gd"))
	pool.append(_mk_ability(&"boss3_kanmon_v1", "关门",
		"章 3 Boss：海底/河底自胡 +3 番（v1 简化模拟役满升级）",
		Rarity.Kind.LEGENDARY, "res://skills/hooks/boss3_kanmon_hook.gd"))

	# M6 内容生产：神级角色能力（§8.10 #1/#7/#4）
	pool.append(_mk_ability(&"mineu_no_oni_v1", "嶺上の鬼",
		"杠后岭上摸 5 选 1（v1：自胡 +2 番）",
		Rarity.Kind.LEGENDARY, "res://skills/hooks/mineu_no_oni_hook.gd"))
	pool.append(_mk_ability(&"san_kyoku_kiseki_v1", "三局一奇跡",
		"每 3 局起手保证 1 役牌刻（v1：自胡 +1 番）",
		Rarity.Kind.LEGENDARY, "res://skills/hooks/san_kyoku_kiseki_hook.gd"))
	pool.append(_mk_ability(&"isshun_senken_v1", "一巡先見",
		"每巡可花 1 巡看下次摸牌（v1：DRAW 时 reveal 占位）",
		Rarity.Kind.LEGENDARY, "res://skills/hooks/isshun_senken_hook.gd"))

	# M6 内容生产：史诗角色能力（§8.10 #3/#5/#6/#8/#9）
	pool.append(_mk_ability(&"yamagan_v1", "山眼",
		"GAME_BEGIN 看牌墙顶 10 张（v1：reveal 1 张占位）",
		Rarity.Kind.EPIC, "res://skills/hooks/yamagan_hook.gd"))
	pool.append(_mk_ability(&"tenpai_seethru_v1", "听牌看穿",
		"对手 HAND_FORMED 时看其听牌张（v1：reveal 占位给 owner）",
		Rarity.Kind.EPIC, "res://skills/hooks/tenpai_seethru_hook.gd"))
	pool.append(_mk_ability(&"ryukyoku_yudou_v1", "流局誘導",
		"巡数 ≥ 12 后弃牌可强制流局（v1：自胡 +1 番）",
		Rarity.Kind.EPIC, "res://skills/hooks/ryukyoku_yudou_hook.gd"))
	pool.append(_mk_ability(&"tousotsu_v1", "統率",
		"其它 ability 触发额度 +1（v1：自胡 +1 番）",
		Rarity.Kind.EPIC, "res://skills/hooks/tousotsu_hook.gd"))
	pool.append(_mk_ability(&"riichi_kago_v1", "立直加護",
		"一发窗口延长至 2 巡（v1：自胡 +1 番）",
		Rarity.Kind.EPIC, "res://skills/hooks/riichi_kago_hook.gd"))

	# 角色被动（ability_id 冻结；显示名为独立中二技名，非姓名拆字）
	pool.append(_mk_ability(&"char_akagi_passive_v1", "林夜彻·脊读鬼神",
		"每次摸牌后透视下家 1 张手牌（角色被动）",
		Rarity.Kind.LEGENDARY, "res://skills/hooks/char_akagi_passive_hook.gd"))
	pool.append(_mk_ability(&"char_kaiji_passive_v1", "裘绝·绝崖翻盘",
		"分数 < 15000 时胡牌 +2 番（角色被动）",
		Rarity.Kind.LEGENDARY, "res://skills/hooks/char_kaiji_passive_hook.gd"))
	pool.append(_mk_ability(&"char_washizu_passive_v1", "白透璃·万透镜华",
		"开局透视所有对手各 2 张手牌（角色被动）",
		Rarity.Kind.LEGENDARY, "res://skills/hooks/char_washizu_passive_hook.gd"))

	pool.append(_mk_ability(&"char_saki_passive_v1", "华岭澄·宝华绽放",
		"胡牌时额外 +2 Dora（角色被动）",
		Rarity.Kind.LEGENDARY, "res://skills/hooks/char_saki_passive_hook.gd"))
	pool.append(_mk_ability(&"char_teru_passive_v1", "连曜真·叠曜连斩",
		"每次胡牌 +N 番（N=连续胡牌次数，累积）",
		Rarity.Kind.LEGENDARY, "res://skills/hooks/char_teru_passive_hook.gd"))
	pool.append(_mk_ability(&"char_awai_passive_v1", "安澄青·无风净界",
		"开局清振听 + 预知下张摸牌（角色被动）",
		Rarity.Kind.LEGENDARY, "res://skills/hooks/char_awai_passive_hook.gd"))

	pool.append(_mk_ability(&"char_koromo_passive_v1", "渊汐·底牌潮掌",
		"海底/河底胡牌 +3 番 + 摸牌时墙顶 3 枚透视（角色被动）",
		Rarity.Kind.LEGENDARY, "res://skills/hooks/char_koromo_passive_hook.gd"))
	pool.append(_mk_ability(&"char_nodoka_passive_v1", "纪枢·概率圣裁",
		"胡牌 +1 番 + 对手听牌时透视手牌 1 枚（角色被动）",
		Rarity.Kind.LEGENDARY, "res://skills/hooks/char_nodoka_passive_hook.gd"))
	pool.append(_mk_ability(&"char_toki_passive_v1", "先示·四席窥运",
		"开局时透视全 4 席下一摸（角色被动）",
		Rarity.Kind.LEGENDARY, "res://skills/hooks/char_toki_passive_hook.gd"))
	pool.append(_mk_ability(&"char_kuro_passive_v1", "宝络绯·赤线缠宝",
		"胡牌时 +2 extra Dora（角色被动）",
		Rarity.Kind.LEGENDARY, "res://skills/hooks/char_kuro_passive_hook.gd"))
	pool.append(_mk_ability(&"char_momoko_passive_v1", "影立静·消影一发",
		"立直后下一次自胡 +1 番（角色被动）",
		Rarity.Kind.LEGENDARY, "res://skills/hooks/char_momoko_passive_hook.gd"))
	pool.append(_mk_ability(&"char_tetsuya_passive_v1", "局进吾·阶升必杀",
		"胡牌每回累加加番（角色被动）",
		Rarity.Kind.LEGENDARY, "res://skills/hooks/char_tetsuya_passive_hook.gd"))

	# M7 收尾：M6 唯一 holdout（plan-6 §8.10 #12）
	pool.append(_mk_ability(&"tougenkyo_v1", "偷天换日",
		"每局 1 次手牌↔弃牌河交换（v1 简化：自胡 +3 番 + 消耗）",
		Rarity.Kind.LEGENDARY, "res://skills/hooks/tougenkyo_hook.gd"))

	# M12 可抽 ability（id 冻结；显示文案原创化，与 12 人被动身份分离）
	pool.append(_mk_ability(&"hisa_bad_wait_v1", "恶听熟手",
		"任意自胡 +2 番（恶听熟练表现）",
		Rarity.Kind.EPIC, "res://skills/hooks/hisa_bad_wait_hook.gd"))
	pool.append(_mk_ability(&"mako_memory_v1", "牌墙记忆",
		"巡数 >= 6 时摸牌后透视牌墙顶 3 枚",
		Rarity.Kind.EPIC, "res://skills/hooks/mako_memory_hook.gd"))
	pool.append(_mk_ability(&"koromo_haitei_ability_v1", "底牌压制",
		"HAITEI/HOUTEI 自胡 +3 番 + 满贯下限",
		Rarity.Kind.LEGENDARY, "res://skills/hooks/koromo_haitei_ability_hook.gd"))
	pool.append(_mk_ability(&"toki_foresight_v1", "巡初窥摸",
		"GAME_BEGIN 全 4 席下一摸 reveal（代价 -1000 点）",
		Rarity.Kind.LEGENDARY, "res://skills/hooks/toki_foresight_hook.gd"))
	pool.append(_mk_ability(&"kuro_dora_love_v1", "宝牌吸引",
		"自胡 +2 Dora + DORA_REVEALED 时 +1 追加 Dora",
		Rarity.Kind.LEGENDARY, "res://skills/hooks/kuro_dora_love_hook.gd"))
	pool.append(_mk_ability(&"momoko_stealth_ability_v1", "潜影立直",
		"立直后的自胡 +1 番",
		Rarity.Kind.EPIC, "res://skills/hooks/momoko_stealth_ability_hook.gd"))
	pool.append(_mk_ability(&"tsubame_gaeshi_v1", "燕返一击",
		"自胡 +3 番（仅一次·消耗）",
		Rarity.Kind.LEGENDARY, "res://skills/hooks/tsubame_gaeshi_hook.gd"))
	pool.append(_mk_ability(&"streak_escalation_v1", "连胜攀升",
		"连胜每次 +N 番累积（流局重置）",
		Rarity.Kind.LEGENDARY, "res://skills/hooks/streak_escalation_hook.gd"))

	# M12 新増 Boss 変種能力（3 張）
	pool.append(_mk_ability(&"boss1_stealth_wall_v1", "ステルス壁",
		"章 1 Boss 変種：自胡 +1 番（ステルス優位）",
		Rarity.Kind.LEGENDARY, "res://skills/hooks/boss1_stealth_wall_hook.gd"))
	pool.append(_mk_ability(&"boss2_dora_thief_v1", "Dora 泥棒",
		"章 2 Boss 変種：自胡 +2 extra Dora",
		Rarity.Kind.LEGENDARY, "res://skills/hooks/boss2_dora_thief_hook.gd"))
	pool.append(_mk_ability(&"boss3_yakuman_pressure_v1", "役満プレッシャー",
		"章 3 Boss 変種：自胡 +4 番 + 2 回目ごとに役満化",
		Rarity.Kind.LEGENDARY, "res://skills/hooks/boss3_yakuman_pressure_hook.gd"))

	return pool

static func abilities_by_rarity(rarity: int) -> Array:
	var result: Array = []
	for a in all_abilities():
		if a.rarity == rarity:
			result.append(a)
	return result

# ---- relics ----

static func all_relics() -> Array:
	var pool: Array = []
	pool.append(_mk_relic(&"relic_lucky_cat_v1", "招财猫",
		"每次胡牌额外 +1 Dora",
		Rarity.Kind.UNCOMMON, "res://skills/hooks/relic_lucky_cat_hook.gd"))
	pool.append(_mk_relic(&"relic_iron_will_v1", "铁壁意志",
		"被荣胡时对手 -1 番",
		Rarity.Kind.UNCOMMON, "res://skills/hooks/relic_iron_will_hook.gd"))
	pool.append(_mk_relic(&"relic_soul_mirror_v1", "魂镜",
		"对手胡牌时偷取 10% 得分",
		Rarity.Kind.EPIC, "res://skills/hooks/relic_soul_mirror_hook.gd"))
	pool.append(_mk_relic(&"relic_wall_eye_v1", "墙眼",
		"每次摸牌后预知下 1 张",
		Rarity.Kind.LEGENDARY, "res://skills/hooks/relic_wall_eye_hook.gd"))

	# M12 新增遗物
	pool.append(_mk_relic(&"relic_red_string_v1", "红线",
		"每次胡牌额外 +1 赤 Dora",
		Rarity.Kind.UNCOMMON, "res://skills/hooks/relic_red_string_hook.gd"))
	pool.append(_mk_relic(&"relic_dragon_seal_v1", "龙印",
		"胡牌时 +1 番（三元牌加成）",
		Rarity.Kind.UNCOMMON, "res://skills/hooks/relic_dragon_seal_hook.gd"))
	pool.append(_mk_relic(&"relic_wind_charm_v1", "风铃",
		"胡牌时 +1 番（风役加成）",
		Rarity.Kind.UNCOMMON, "res://skills/hooks/relic_wind_charm_hook.gd"))
	pool.append(_mk_relic(&"relic_speed_demon_v1", "速攻鬼",
		"巡数 < 8 时胡牌 +1 番",
		Rarity.Kind.EPIC, "res://skills/hooks/relic_speed_demon_hook.gd"))
	pool.append(_mk_relic(&"relic_patience_stone_v1", "忍石",
		"流局时获得 +2000 点",
		Rarity.Kind.UNCOMMON, "res://skills/hooks/relic_patience_stone_hook.gd"))
	pool.append(_mk_relic(&"relic_han_crystal_v1", "番水晶",
		"立直状态下胡牌 +1 番",
		Rarity.Kind.EPIC, "res://skills/hooks/relic_han_crystal_hook.gd"))
	pool.append(_mk_relic(&"relic_comeback_crown_v1", "逆转王冠",
		"四家最低分时胡牌 +2 番",
		Rarity.Kind.EPIC, "res://skills/hooks/relic_comeback_crown_hook.gd"))
	pool.append(_mk_relic(&"relic_pity_breaker_v1", "天命打破",
		"保底概率提升（被动 gacha 修改器）",
		Rarity.Kind.LEGENDARY, "res://skills/hooks/relic_pity_breaker_hook.gd"))

	return pool

static func relics_by_rarity(rarity: int) -> Array:
	var result: Array = []
	for r in all_relics():
		if r.rarity == rarity:
			result.append(r)
	return result

# ---- consumables ----

static func all_consumables() -> Array:
	var pool: Array = []

	pool.append(_mk_consumable(&"iron_shield_v1", "铁盾",
		"本局被荣胡时取消 1 次（消耗品）",
		ConsumableItem.Kind.BATTLE, Rarity.Kind.UNCOMMON,
		"res://skills/hooks/consumable_iron_shield_hook.gd"))

	pool.append(_mk_consumable(&"wall_peek_v1", "千里眼",
		"开局 reveal 牌墙顶 5 张（消耗品）",
		ConsumableItem.Kind.BATTLE, Rarity.Kind.COMMON,
		"res://skills/hooks/consumable_wall_peek_hook.gd"))

	pool.append(_mk_consumable(&"double_payout_v1", "倍率券",
		"下次胡牌番数 ×2（消耗品）",
		ConsumableItem.Kind.BATTLE, Rarity.Kind.EPIC,
		"res://skills/hooks/consumable_double_payout_hook.gd"))

	pool.append(_mk_consumable(&"dora_charm_v1", "宝牌护符",
		"下次胡牌额外 +3 Dora（消耗品）",
		ConsumableItem.Kind.BATTLE, Rarity.Kind.EPIC,
		"res://skills/hooks/consumable_dora_charm_hook.gd"))

	# M12 新增消耗品
	pool.append(_mk_consumable(&"wall_collapse_v1", "牌墙崩塌",
		"开局减少牌墙 10 张（消耗品）",
		ConsumableItem.Kind.BATTLE, Rarity.Kind.UNCOMMON,
		"res://skills/hooks/consumable_wall_collapse_hook.gd"))
	pool.append(_mk_consumable(&"dora_flip_v1", "翻宝牌",
		"摸牌时额外 +1 Dora 并消耗（消耗品）",
		ConsumableItem.Kind.BATTLE, Rarity.Kind.UNCOMMON,
		"res://skills/hooks/consumable_dora_flip_hook.gd"))
	pool.append(_mk_consumable(&"seat_swap_v1", "换座",
		"开局交换座位（消耗品）",
		ConsumableItem.Kind.BATTLE, Rarity.Kind.COMMON,
		"res://skills/hooks/consumable_seat_swap_hook.gd"))
	pool.append(_mk_consumable(&"furiten_bomb_v1", "振听炸弹",
		"取消对手荣胡 1 次（消耗品）",
		ConsumableItem.Kind.BATTLE, Rarity.Kind.EPIC,
		"res://skills/hooks/consumable_furiten_bomb_hook.gd"))
	pool.append(_mk_consumable(&"point_shield_v1", "点棒护盾",
		"被荣胡时偷回 50% 点数（消耗品）",
		ConsumableItem.Kind.BATTLE, Rarity.Kind.EPIC,
		"res://skills/hooks/consumable_point_shield_hook.gd"))
	pool.append(_mk_consumable(&"tsubame_v1", "燕返",
		"开局手牌重洗（消耗品）",
		ConsumableItem.Kind.BATTLE, Rarity.Kind.COMMON,
		"res://skills/hooks/consumable_tsubame_hook.gd"))

	return pool

static func consumables_by_kind(kind: int) -> Array:
	var result: Array = []
	for c in all_consumables():
		if c.kind == kind:
			result.append(c)
	return result

# ---- internal ----

static func _mk_tile(id: StringName, name: String, desc: String, tile_id: int, rarity: int, hook_path: String) -> TileVariant:
	var v := TileVariant.new(id, tile_id, rarity)
	v.display_name = name
	v.description = desc
	v.skill_resource_path = hook_path
	return v

static func _mk_ability(id: StringName, name: String, desc: String, rarity: int, hook_path: String) -> AbilityCard:
	var a := AbilityCard.new(id, rarity)
	a.display_name = name
	a.description = desc
	a.hook_resource_path = hook_path
	return a

static func _mk_relic(id: StringName, name: String, desc: String, rarity: int, hook_path: String) -> RelicItem:
	var r := RelicItem.new(id, rarity)
	r.display_name = name
	r.description = desc
	r.hook_resource_path = hook_path
	r.icon_path = RelicItem.default_icon_path(id)
	return r

static func _mk_consumable(id: StringName, name: String, desc: String, kind: int, rarity: int, hook_path: String) -> ConsumableItem:
	var c := ConsumableItem.new(id, kind, rarity)
	c.display_name = name
	c.description = desc
	c.hook_resource_path = hook_path
	c.icon_path = ConsumableItem.default_icon_path(id)
	return c
