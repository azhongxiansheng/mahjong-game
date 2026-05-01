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
	pool.append(_mk_tile(&"thunder_5w_v1", "5万·闪电", "owner 自胡 +1 番（M1 demo）",
		TileId.W5, Rarity.Kind.UNCOMMON, "res://skills/hooks/thunder_5w_hook.gd"))
	pool.append(_mk_tile(&"seal_chun_v1", "中·封印", "持有者出铳被荣胡时取消",
		TileId.CHUN, Rarity.Kind.EPIC, "res://skills/hooks/seal_chun_hook.gd"))
	pool.append(_mk_tile(&"soul_drain_hatsu_v1", "发·吸魂", "对手胡牌时转 30% 给 holder",
		TileId.HATSU, Rarity.Kind.EPIC, "res://skills/hooks/soul_drain_hatsu_hook.gd"))
	pool.append(_mk_tile(&"xray_1w_v1", "1万·透视", "owner 摸牌后 reveal 一张他家",
		TileId.W1, Rarity.Kind.LEGENDARY, "res://skills/hooks/xray_1w_hook.gd"))
	pool.append(_mk_tile(&"unfuriten_5p_v1", "5筒·解振听", "owner 进入振听时清除",
		TileId.T5, Rarity.Kind.UNCOMMON, "res://skills/hooks/unfuriten_5p_hook.gd"))

	# M6 内容生产：增番系（§8.1）
	pool.append(_mk_tile(&"white_haku_holy_v1", "白板·圣光", "持牌者作三元牌一员胡牌时 +1 番（v1 简化）",
		TileId.HAKU, Rarity.Kind.UNCOMMON, "res://skills/hooks/white_haku_holy_hook.gd"))

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
	# 5 张占位 ability
	for i in range(5):
		pool.append(_mk_ability(
			StringName("placeholder_ability_%d" % i),
			"占位能力 %d" % (i + 1),
			"v1 占位；M6 内容生产时填",
			Rarity.Kind.COMMON, ""
		))
	return pool

static func abilities_by_rarity(rarity: int) -> Array:
	var result: Array = []
	for a in all_abilities():
		if a.rarity == rarity:
			result.append(a)
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
