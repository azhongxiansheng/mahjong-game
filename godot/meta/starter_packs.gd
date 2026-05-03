class_name StarterPacks

# 麻将王 — 里程碑 6：3 套起始包真实化（plan-6 D + spec §7.2）
#
# 三套：火力 / 速胡 / 控场。每套 8-10 张牌技能 + 1-2 张角色能力（spec §7.2）。
# v1 内容只挑选已实装的 ID（避免引用未注册的卡）；M6 后续认领新卡技能时
# 再扩充本表。
#
# StarterPack 数据结构：
#   {id, display_name, description, tile_variants: Dictionary{TileId→pack_card_id},
#    abilities: Array[ability_id StringName], available: bool}

# 用 static func 而不是 const，避开 const Dictionary 在 GDScript 4 里
# 引用其他 class_name enum 的静态初始化顺序问题（同 ChapterConfig）。

# 控场型（spec §7.2 主题）— 透明牌 / 阻胡 / 抓马
# 已实装：xray_1w_v1 / seal_chun_v1 / west_mirror_v1 / man9_iron_wall_v1 /
# soul_drain_hatsu_v1 / 角色能力 seabed_hunter_v1
static func control_pack() -> Dictionary:
	return {
		"id": &"starter_control",
		"display_name": "控场型",
		"description": "防御 / 透明牌 / 抓马反转。靠阻止对手胡牌 + 镜像取分。",
		"tile_variants": {
			TileId.W1: &"xray_1w_v1",
			TileId.CHUN: &"seal_chun_v1",
			TileId.W_WIND: &"west_mirror_v1",
			TileId.W9: &"man9_iron_wall_v1",
			TileId.HATSU: &"soul_drain_hatsu_v1",
		},
		"abilities": [&"seabed_hunter_v1"],
		"available": true,
	}

# 火力型（spec §7.2 主题）— 增番 + 终局
# 已实装：thunder_5w_v1 / white_haku_holy_v1 / green_hatsu_serenity_v1 /
# pin9_haitei_double_v1 / 角色能力 shichu_kyu_katsu_v1
static func aggro_pack() -> Dictionary:
	return {
		"id": &"starter_aggro",
		"display_name": "火力型",
		"description": "增番 + 终局加成。靠累番打高得分；点棒越低反而越强。",
		"tile_variants": {
			TileId.W5: &"thunder_5w_v1",
			TileId.HAKU: &"white_haku_holy_v1",
			TileId.HATSU: &"green_hatsu_serenity_v1",
			TileId.T9: &"pin9_haitei_double_v1",
		},
		"abilities": [&"shichu_kyu_katsu_v1"],
		"available": true,
	}

# 速胡型（spec §7.2 主题）— 立直 / 加速
# 当前已实装符合速胡主题的：unfuriten_5p_v1（立直系）
# 后续 M6 牌技能新增（south_premature_riichi / pin9_speed 等）会扩充。
static func fast_pack() -> Dictionary:
	return {
		"id": &"starter_fast",
		"display_name": "速胡型",
		"description": "立直 / 加速胡牌。靠立直系减少振听 + 抢先听牌。",
		# M7 balance：fast 此前只有 1 张 tile + 0 abilities，sim 0% 通关。
		# 补齐 spec §7.2 主题（立直 / 加速）：先制立直 + 速胡 + 加速 + 解振听 +
		# 振听干扰 + 立直加護 / 山眼。
		"tile_variants": {
			TileId.T5: &"unfuriten_5p_v1",            # 立直后清振听
			TileId.S_WIND: &"south_premature_riichi_v1",  # 第 1 巡先制立直
			TileId.T9: &"pin9_speed_v1",              # 摸到此牌 force_tsumo（速胡）
			TileId.S3: &"sou3_skip_v1",               # 自胡 +1 番（加速主题）
			TileId.W2: &"man2_lure_v1",               # 自胡 +1 番（伪听干扰）
		},
		"abilities": [&"riichi_kago_v1"],  # 一发期望延长（自胡 +1 番桩，立直主题）
		"available": true,
	}

static func all() -> Array:
	return [aggro_pack(), fast_pack(), control_pack()]

static func available() -> Array:
	var result: Array = []
	for p in all():
		if p.get("available", false):
			result.append(p)
	return result

# 应用一个起始包到 RunState：把 pack 内容塞 deck（dict + abilities array）。
# 注：M5 第 3 步起 RunState.player_deck 是 Deck 对象；deck dict 仍保留作
# "选择记录"（pack_id 来源）。
static func apply_to(run_state: RunState, pack_id: StringName) -> bool:
	for p in all():
		if p.id == pack_id:
			if not p.get("available", false):
				return false
			run_state.deck["tile_variants"] = p.tile_variants.duplicate(true)
			run_state.deck["abilities"] = p.abilities.duplicate(true)
			run_state.deck["pack_id"] = p.id
			# M5+ 路径：把 pack 卡片真实加进 player_deck
			if run_state.player_deck:
				_apply_pack_to_deck(run_state.player_deck, p)
			return true
	return false

# 把 pack 数据真实推进 player_deck。查 CardPool 拿对应 TileVariant / AbilityCard。
static func _apply_pack_to_deck(deck: Deck, pack: Dictionary) -> void:
	var all_tiles: Array = CardPool.all_tile_variants()
	var all_abs: Array = CardPool.all_abilities()
	for tile_id in pack.tile_variants:
		var pack_card_id: StringName = pack.tile_variants[tile_id]
		for v in all_tiles:
			if v.id == pack_card_id:
				deck.add_tile_variant(v)
				break
	for ab_id in pack.abilities:
		for a in all_abs:
			if a.id == ab_id:
				deck.add_ability(a)
				break
