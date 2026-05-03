class_name TileSkillFactory

# 麻将王 — M7：把玩家 deck.tile_variants 接入 BattleController.registry。
#
# 此前 28 张牌技能 hook 注册在 CardPool 但永不在真战斗 fire — 类似 PR #56
# 之于 ability。本工厂提供并行的 inject 路径：
#   - BossAbilityFactory.inject_player_abilities(reg, ability_ids, seat=0)
#   - TileSkillFactory.inject_player_tile_variants(reg, variants_dict, seat=0)
#
# 不同于 ability anchored 到 seat int，tile skill anchor 必须是 TileInstance
# （SkillScheduler._collect 据此分流）。本工厂构造一个 fixture TileInstance
# (tile_id=variant.tile_id, owner_seat=player_seat)，作为该牌的"代表"在
# registry 持有。当事件 emit 时，scheduler 读 anchor.owner_seat / holder_seat
# 决定是否触发，无需事件中的物理 tile 与 anchor TileInstance 对齐。
#
# 加新 tile_variant：在 _TILE_TRIGGERS 加 entry（owner / holder 列表）。

# variant id → {owner: [...], holder: [...]} 触发器映射。
const _TILE_TRIGGERS: Dictionary = {
	# M1 demo
	&"thunder_5w_v1": {"owner": [&"WIN_DECLARED_PRE"], "holder": []},
	&"seal_chun_v1": {"owner": [&"RON_DECLARED"], "holder": []},
	# soul_drain_hatsu: 用 transfer_points + points_won → 必须是 WIN_DECLARED post
	&"soul_drain_hatsu_v1": {"owner": [], "holder": [&"WIN_DECLARED"]},
	&"xray_1w_v1": {"owner": [&"TILE_DRAWN"], "holder": []},
	&"unfuriten_5p_v1": {"owner": [&"WIN_DECLARED_PRE"], "holder": []},
	# §8.1 增番
	&"white_haku_holy_v1": {"owner": [&"WIN_DECLARED_PRE"], "holder": []},
	&"green_hatsu_serenity_v1": {"owner": [&"WIN_DECLARED_PRE"], "holder": []},
	&"east_dynasty_v1": {"owner": [&"WIN_DECLARED_PRE"], "holder": []},
	# §8.2 加速
	&"pin9_speed_v1": {"owner": [&"TILE_DRAWN"], "holder": []},
	&"sou3_skip_v1": {"owner": [&"WIN_DECLARED_PRE"], "holder": []},
	&"south_riichi_breeze_v1": {"owner": [&"WIN_DECLARED_PRE"], "holder": []},
	# §8.3 阻胡
	# man9_iron_wall: -1 番 → WIN_DECLARED_PRE（在 ScoreCalc 之前才能影响计分；
	# RON_DECLARED 的 han_deltas 会被丢弃）
	&"man9_iron_wall_v1": {"owner": [&"WIN_DECLARED_PRE"], "holder": []},
	&"west_mirror_v1": {"owner": [&"RIICHI_DECLARED"], "holder": []},
	# §8.4 抓马
	# east_mirror_chambo: 用 transfer_points，需要 points_won → WIN_DECLARED post-score
	&"east_mirror_chambo_v1": {"owner": [&"WIN_DECLARED"], "holder": []},
	# sou8_scapegoat: -1 番 → WIN_DECLARED_PRE 同 iron_wall 路径
	&"sou8_scapegoat_v1": {"owner": [&"WIN_DECLARED_PRE"], "holder": []},
	# §8.5 透明牌
	&"white_oracle_v1": {"owner": [&"TILE_DRAWN"], "holder": []},
	&"pin2_bluff_v1": {"owner": [&"WIN_DECLARED_PRE"], "holder": []},
	# §8.6 立直
	&"south_premature_riichi_v1": {"owner": [&"WIN_DECLARED_PRE"], "holder": []},
	&"hatsu_stick_refund_v1": {"owner": [&"WIN_DECLARED_PRE"], "holder": []},
	# §8.7 振听操控
	&"east_phantom_v1": {"owner": [&"RON_DECLARED"], "holder": []},
	&"man2_lure_v1": {"owner": [&"WIN_DECLARED_PRE"], "holder": []},
	&"chun_substitute_v1": {"owner": [&"WIN_DECLARED_PRE"], "holder": []},
	# §8.8 Dora
	&"man6_treasure_v1": {"owner": [&"WIN_DECLARED_PRE"], "holder": []},
	&"white_red_change_v1": {"owner": [&"WIN_DECLARED_PRE"], "holder": []},
	&"sou4_uradora_pick_v1": {"owner": [&"WIN_DECLARED_PRE"], "holder": []},
	# §8.9 终局
	&"pin9_haitei_double_v1": {"owner": [], "holder": [&"HAITEI", &"HOUTEI"]},
	&"north_sweep_v1": {"owner": [&"WIN_DECLARED_PRE"], "holder": []},
	&"white_mangan_floor_v1": {"owner": [&"WIN_DECLARED_PRE"], "holder": []},
}

# 已知 variant id（GUT 用）
static func known_variant_ids() -> Array:
	return _TILE_TRIGGERS.keys()

# 用 variant id 从 CardPool 查 skill_resource_path + 用 _TILE_TRIGGERS 取
# triggers 构造 fresh SkillResource。返 null 表示 id 未知或无 hook。
static func build(variant_id: StringName) -> SkillResource:
	if variant_id == &"" or not _TILE_TRIGGERS.has(variant_id):
		return null
	var variant: TileVariant = _find_variant_in_pool(variant_id)
	if variant == null or variant.skill_resource_path == "":
		return null
	var hook_script: GDScript = load(variant.skill_resource_path)
	if hook_script == null:
		return null
	var s := SkillResource.new()
	s.id = variant_id
	s.display_name = variant.display_name
	s.description = variant.description
	s.rarity = variant.rarity
	s.attached_tile = variant.tile_id
	s.is_ability = false
	var triggers: Dictionary = _TILE_TRIGGERS[variant_id]
	var ot: Array[StringName] = []
	for t in triggers.owner:
		ot.append(t)
	s.owner_triggers = ot
	var ht: Array[StringName] = []
	for t in triggers.holder:
		ht.append(t)
	s.holder_triggers = ht
	s.hook_script = hook_script
	return s

# 把 SkillResource 注册到 SkillRegistry，anchor = fixture TileInstance（tile_id
# 来自 variant，owner_seat=玩家座位）。holder_triggers 非空时还设 holder_seat。
static func inject_one(registry: SkillRegistry, variant_id: StringName, player_seat: int = 0) -> bool:
	var sk: SkillResource = build(variant_id)
	if sk == null:
		return false
	var ti := TileInstance.make(Tile.new(sk.attached_tile), player_seat, sk)
	if not sk.holder_triggers.is_empty():
		ti.holder_seat = player_seat
	registry.register(sk, ti)
	return true

# 批量：把 player_deck.tile_variants Dictionary[TileId → variant_id 或 TileVariant]
# 注入。返成功注册的张数。未知 / 无 hook / 普通占位牌静默跳过。
# 兼容两种 input 形式：
#   - {tile_id: variant_id (StringName)} — RunState.deck.tile_variants
#   - {tile_id: TileVariant} — Deck.tile_variants（M5+ Deck 类）
static func inject_player_tile_variants(registry: SkillRegistry, variants: Dictionary, player_seat: int = 0) -> int:
	var count: int = 0
	for tile_id in variants:
		var raw: Variant = variants[tile_id]
		var variant_id: StringName = &""
		if raw is StringName:
			variant_id = raw
		elif raw is TileVariant:
			variant_id = raw.id
		if variant_id == &"":
			continue
		if inject_one(registry, variant_id, player_seat):
			count += 1
	return count

# ---- internal ----

static func _find_variant_in_pool(variant_id: StringName) -> TileVariant:
	for v in CardPool.all_tile_variants():
		if v.id == variant_id:
			return v
	return null
