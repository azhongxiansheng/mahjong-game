class_name ItemCatalog extends RefCounted

const ITEM_ICON_DIR := "res://assets/ui/table_hud/items/"

static var _definitions: Array = []
static var _by_id: Dictionary = {}


static func all() -> Array:
	_ensure_index()
	return _definitions.duplicate()


static func _build_definitions() -> Array:
	return [
		_consumable(&"iron_shield_v1", "铁盾", "你下一次放铳的弃牌，其全部荣和被取消（消耗品）",
			Rarity.Kind.UNCOMMON, ItemDefinition.UseMode.ARMED,
			[&"RON_DECLARED", &"TILE_DRAWN", &"WIN_DECLARED",
				&"EXHAUSTIVE_DRAW", &"ABORTIVE_DRAW"],
			"consumable_iron_shield_hook.gd", "item_iron_shield.png"),
		_consumable(&"wall_peek_v1", "千里眼", "查看牌墙接下来 3 张，仅自己可见（消耗品）",
			Rarity.Kind.COMMON, ItemDefinition.UseMode.IMMEDIATE, [&"GAME_BEGIN"],
			"consumable_wall_peek_hook.gd", "item_wall_peek.png"),
		_consumable(&"double_payout_v1", "倍率券", "下次胡牌番数 ×2，额外至多 +3 番；役满不放大（消耗品）",
			Rarity.Kind.EPIC, ItemDefinition.UseMode.ARMED, [&"WIN_DECLARED_PRE"],
			"consumable_double_payout_hook.gd", "item_double_payout.png"),
		_consumable(&"dora_charm_v1", "宝牌护符", "下次胡牌额外 +2 Dora（消耗品）",
			Rarity.Kind.EPIC, ItemDefinition.UseMode.ARMED, [&"WIN_DECLARED_PRE"],
			"consumable_dora_charm_hook.gd", "item_dora_charm.png"),
		_consumable(&"wall_collapse_v1", "牌墙崩塌", "移除活牌墙顶 6 张；余量不足时不可用（消耗品）",
			Rarity.Kind.UNCOMMON, ItemDefinition.UseMode.IMMEDIATE, [&"GAME_BEGIN"],
			"consumable_wall_collapse_hook.gd", "item_wall_collapse.png"),
		_consumable(&"dora_flip_v1", "翻宝牌", "摸牌时额外 +1 Dora 并消耗（消耗品）",
			Rarity.Kind.UNCOMMON, ItemDefinition.UseMode.ARMED, [&"TILE_DRAWN"],
			"consumable_dora_flip_hook.gd", "item_dora_flip.png"),
		_consumable(&"seat_swap_v1", "换座", "开局交换座位（消耗品）",
			Rarity.Kind.COMMON, ItemDefinition.UseMode.UNAVAILABLE, [&"GAME_BEGIN"],
			"consumable_seat_swap_hook.gd", "item_seat_swap.png", false),
		_consumable(&"furiten_bomb_v1", "振听炸弹", "取消下一名对手的荣和，对自摸无效（消耗品）",
			Rarity.Kind.EPIC, ItemDefinition.UseMode.ARMED, [&"RON_DECLARED"],
			"consumable_furiten_bomb_hook.gd", "item_furiten_bomb.png"),
		_consumable(&"point_shield_v1", "点棒护盾", "放铳结算后收回本次净失点的 30%（消耗品）",
			Rarity.Kind.EPIC, ItemDefinition.UseMode.ARMED, [&"WIN_DECLARED"],
			"consumable_point_shield_hook.gd", "item_point_shield.png"),
		_consumable(&"tsubame_v1", "燕返", "开局手牌重洗（消耗品）",
			Rarity.Kind.COMMON, ItemDefinition.UseMode.UNAVAILABLE, [&"GAME_BEGIN"],
			"consumable_tsubame_hook.gd", "item_tsubame.png", false),
		_relic(&"relic_lucky_cat_v1", "招财猫", "每次胡牌额外 +1 Dora",
			Rarity.Kind.UNCOMMON, [&"WIN_DECLARED_PRE"],
			"relic_lucky_cat_hook.gd", "item_relic_lucky_cat.png"),
		_relic(&"relic_iron_will_v1", "铁壁意志", "你放铳时和牌者计分番 -1（最低 1 番）",
			Rarity.Kind.UNCOMMON, [&"WIN_DECLARED_PRE"],
			"relic_iron_will_hook.gd", "item_relic_iron_will.png"),
		_relic(&"relic_soul_mirror_v1", "魂镜", "对手胡牌结算后转移其本次得点 5% 给你",
			Rarity.Kind.EPIC, [&"WIN_DECLARED"],
			"relic_soul_mirror_hook.gd", "item_relic_soul_mirror.png"),
		_relic(&"relic_wall_eye_v1", "墙眼", "每次摸牌后查看牌墙接下来 1/2/3 张（按持有件数）",
			Rarity.Kind.LEGENDARY, [&"TILE_DRAWN"],
			"relic_wall_eye_hook.gd", "item_relic_wall_eye.png"),
		_relic(&"relic_red_string_v1", "红线", "门清胡牌额外 +1 赤 Dora",
			Rarity.Kind.UNCOMMON, [&"WIN_DECLARED_PRE"],
			"relic_red_string_hook.gd", "item_relic_red_string.png"),
		_relic(&"relic_dragon_seal_v1", "龙印", "胡牌含白/发/中刻子役时 +1 番",
			Rarity.Kind.UNCOMMON, [&"WIN_DECLARED_PRE"],
			"relic_dragon_seal_hook.gd", "item_relic_dragon_seal.png"),
		_relic(&"relic_wind_charm_v1", "风铃", "胡牌含自风或场风役时 +1 番",
			Rarity.Kind.UNCOMMON, [&"WIN_DECLARED_PRE"],
			"relic_wind_charm_hook.gd", "item_relic_wind_charm.png"),
		_relic(&"relic_speed_demon_v1", "速攻鬼", "第 6 次舍牌前胡牌 +1 番",
			Rarity.Kind.EPIC, [&"WIN_DECLARED_PRE"],
			"relic_speed_demon_hook.gd", "item_relic_speed_demon.png"),
		_relic(&"relic_patience_stone_v1", "忍石", "荒牌流局时听牌 +1000 点",
			Rarity.Kind.UNCOMMON, [&"EXHAUSTIVE_DRAW"],
			"relic_patience_stone_hook.gd", "item_relic_patience_stone.png"),
		_relic(&"relic_han_crystal_v1", "番水晶", "立直状态下胡牌 +1 番",
			Rarity.Kind.EPIC, [&"WIN_DECLARED_PRE"],
			"relic_han_crystal_hook.gd", "item_relic_han_crystal.png"),
		_relic(&"relic_comeback_crown_v1", "逆转王冠", "胡牌时严格最低分 +2 番，并列最低 +1 番",
			Rarity.Kind.EPIC, [&"WIN_DECLARED_PRE"],
			"relic_comeback_crown_hook.gd", "item_relic_comeback_crown.png"),
		_relic(&"relic_pity_breaker_v1", "天命打破", "连续两局未胡后充能：下次胡牌至少满贯",
			Rarity.Kind.LEGENDARY, [&"WIN_DECLARED_PRE"],
			"relic_pity_breaker_hook.gd", "", false),
	]


static func definition(item_id: StringName) -> ItemDefinition:
	_ensure_index()
	return _by_id.get(item_id, null) as ItemDefinition


static func consumables() -> Array:
	var out: Array = []
	for value in all():
		var definition := value as ItemDefinition
		if definition != null and definition.is_consumable():
			out.append(definition)
	return out


static func relics() -> Array:
	var out: Array = []
	for value in all():
		var definition := value as ItemDefinition
		if definition != null and definition.is_relic():
			out.append(definition)
	return out


static func grantable_ids() -> Array:
	var out: Array = []
	for value in all():
		var definition := value as ItemDefinition
		if definition != null and definition.is_grantable:
			out.append(String(definition.id))
	return out


static func can_use(item_id: StringName, status: String) -> bool:
	var item := definition(item_id)
	return item != null and item.can_use(status)


static func _ensure_index() -> void:
	if not _definitions.is_empty():
		return
	_definitions = _build_definitions()
	for value in _definitions:
		var definition := value as ItemDefinition
		if definition != null and not _by_id.has(definition.id):
			_by_id[definition.id] = definition


static func _consumable(
	id: StringName,
	display_name: String,
	description: String,
	rarity: int,
	use_mode: int,
	triggers: Array,
	hook_file: String,
	icon_file: String,
	grantable: bool = true
) -> ItemDefinition:
	return ItemDefinition.new(
		id, display_name, description, rarity,
		ItemDefinition.Category.CONSUMABLE, use_mode, triggers,
		"res://skills/hooks/%s" % hook_file,
		ITEM_ICON_DIR + icon_file,
		grantable,
	)


static func _relic(
	id: StringName,
	display_name: String,
	description: String,
	rarity: int,
	triggers: Array,
	hook_file: String,
	icon_file: String,
	grantable: bool = true
) -> ItemDefinition:
	return ItemDefinition.new(
		id, display_name, description, rarity,
		ItemDefinition.Category.RELIC, ItemDefinition.UseMode.PASSIVE, triggers,
		"res://skills/hooks/%s" % hook_file,
		ITEM_ICON_DIR + icon_file if not icon_file.is_empty() else "",
		grantable,
	)
