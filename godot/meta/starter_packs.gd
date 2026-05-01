class_name StarterPacks

# 麻将王 — 里程碑 4 第 2 步：起始包占位（plan-4 D7）
#
# spec §7.2 要求 3 套起始包（火力 / 速胡 / 控场）。v1 仅 hardcoded 1 套
# "控场型"占位（因为里程碑 1 已有透明牌 §8.5 类 demo 技能；其余 2 套
# 留给 M6 内容生产）。
#
# StarterPack 数据结构：
#   {id: StringName, display_name: String, description: String,
#    tile_variants: Dictionary, abilities: Array, available: bool}
#
# tile_variants: TileId → SkillResource 路径或 inline 配置（M6 资源化时改 .tres）。
# v1 留空字典即合法（无技能牌时玩家用普通牌跑骨架）。
# abilities: Array[SkillResource]。v1 留空数组合法（plan-4 D7 开放问题 4 已确认）。

# 用 static func 而不是 const，避开 const Dictionary 在 GDScript 4 里
# 引用其他 class_name enum 的静态初始化顺序问题（同 ChapterConfig）。

# 控场型占位（v1 唯一可选）：透明牌系灵感（spec §8.5）
static func control_pack() -> Dictionary:
	return {
		"id": &"starter_control",
		"display_name": "控场型",
		"description": "v1 占位起始包。后续 M6 内容生产时补真实牌技能 + 角色能力配置。",
		"tile_variants": {},  # 留空：M6 内容化（如 reveal_5w_v1.tres）
		"abilities": [],      # 留空：M6 内容化
		"available": true,
	}

# 火力型占位（v1 灰显，M6 实装）
static func aggro_pack() -> Dictionary:
	return {
		"id": &"starter_aggro",
		"display_name": "火力型",
		"description": "（M6 实装）增番系为主，胡牌追加番数。",
		"tile_variants": {},
		"abilities": [],
		"available": false,
	}

# 速胡型占位（v1 灰显，M6 实装）
static func fast_pack() -> Dictionary:
	return {
		"id": &"starter_fast",
		"display_name": "速胡型",
		"description": "（M6 实装）听牌 / 立直加速；牌山见底奖励高。",
		"tile_variants": {},
		"abilities": [],
		"available": false,
	}

static func all() -> Array:
	return [aggro_pack(), fast_pack(), control_pack()]

static func available() -> Array:
	var result: Array = []
	for p in all():
		if p.get("available", false):
			result.append(p)
	return result

# 应用一个起始包到给定 RunState：填 deck.tile_variants + deck.abilities。
# v1 简化：直接覆盖（一 Run 内不允许多次应用，即使可调用也只取最后一次的内容）。
static func apply_to(run_state: RunState, pack_id: StringName) -> bool:
	for p in all():
		if p.id == pack_id:
			if not p.get("available", false):
				return false
			run_state.deck["tile_variants"] = p.tile_variants.duplicate(true)
			run_state.deck["abilities"] = p.abilities.duplicate(true)
			run_state.deck["pack_id"] = p.id
			return true
	return false
