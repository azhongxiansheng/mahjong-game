class_name LobbyCodexCatalog extends RefCounted

# 大厅资料馆白名单数据源（E1-05 / #229）。
# 只输出玩家可见字段；不暴露 HP / 金币 / 解锁 / 抽卡 / Run 等。


func characters() -> Array:
	var rows: Array = []
	var abilities := _ability_by_id()
	for character in CharacterPool.all():
		var ability: AbilityCard = abilities.get(String(character.ability_id)) as AbilityCard
		rows.append({
			"ability_description": ability.description if ability else "",
			"ability_name": ability.display_name if ability else "",
			"affinity_labels": [
				_affinity_label(character.affinity_primary),
				_affinity_label(character.affinity_secondary),
			],
			"description": character.description,
			"display_name": character.display_name,
			"id": String(character.id),
			"portrait_path": character.portrait_path,
		})
	return rows


func items() -> Array:
	var rows: Array = []
	for consumable in CardPool.consumables_by_kind(ConsumableItem.Kind.BATTLE):
		rows.append(_item_row(consumable, "一次性道具"))
	for relic in CardPool.all_relics():
		if relic.id == &"relic_pity_breaker_v1":
			continue
		rows.append(_item_row(relic, "常驻道具"))
	return rows


func rules() -> Array:
	return [
		{
			"body": "只打东场四局：东一至东四。适合快速练习与短局匹配。",
			"id": "mode_east",
			"title": "东风战",
		},
		{
			"body": "打完东一至南四共八局。节奏更完整，适合认真对局。",
			"id": "mode_hanchan",
			"title": "半庄战",
		},
		{
			"body": "标准日麻规则：门清立直、一般役种与点数计算。关闭角色能力、道具、PTT/字幕与六巡奖励窗口。电脑练习与公共匹配的默认选项。",
			"id": "mode_standard",
			"title": "标准场",
		},
		{
			"body": "启用角色能力、道具与 PTT。每个约六巡的奖励窗口开始公开四件互不重复道具；累计 24 次权威弃牌后关闭窗口。无和牌时按四席发言与公开牌局情境确定性一对一分配。任意和牌优先取消且不评分、不发奖；终场非和牌只展示。同种道具可重复持有；实际发放且倾向匹配时武装下一窗口角色能力。",
			"id": "mode_trash_talk",
			"title": "嘴强欢乐场",
		},
		{
			"body": "门清听牌时可宣告立直，支付 1000 点立直棒。立直后手牌固定，只能打摸到的牌；胡牌额外 +1 番，并可能触发一发等衍生役。",
			"id": "rule_riichi",
			"title": "立直",
		},
		{
			"body": "可用吃、碰、杠回应他家弃牌（吃仅限上家）。鸣牌后手牌不再门清，部分役种无法成立，但可加速成型。",
			"id": "rule_calls",
			"title": "鸣牌",
		},
		{
			"body": "自己听过的牌若已出现在己方弃牌中，或立直后漏过可荣的牌，会进入振听：此时不能荣和，只能自摸。",
			"id": "rule_furiten",
			"title": "振听",
		},
		{
			"body": "成牌必须至少具备一番有效役种才能和牌。纯形态完成但无役时不能宣告自摸或荣和。",
			"id": "rule_yaku_required",
			"title": "无役不能和",
		},
	]


func yakus() -> Array:
	var rows: Array = []
	var ids: Array[int] = []
	ids.append_array(YakuId.ALL)
	ids.append_array(YakuId.ALL_VARIANTS)
	for yaku_id in ids:
		var meta := YakuId.catalog_metadata(yaku_id)
		rows.append({
			"category": String(meta.get("category", "其他")),
			"closed_han": int(meta.get("base_han_closed", 0)),
			"condition": String(meta.get("condition", "")),
			"description": String(meta.get("description", "")),
			"display_name": String(meta.get("name_zh", "?")),
			"example": String(meta.get("example", "")),
			"id": yaku_id,
			"is_yakuman": bool(meta.get("is_yakuman", false)),
			"open_han": int(meta.get("base_han_open", 0)),
			"yakuman_multiplier": int(meta.get("yakuman_multiplier", 0)),
		})
	return rows


func _item_row(item: Variant, category: String) -> Dictionary:
	return {
		"category": category,
		"description": String(item.description),
		"display_name": String(item.display_name),
		"icon_path": String(item.resolved_icon_path()),
		"id": String(item.id),
		"rarity_label": Rarity.display_name(item.rarity),
	}


func _ability_by_id() -> Dictionary:
	var result := {}
	for ability in CardPool.all_abilities():
		result[String(ability.id)] = ability
	return result


func _affinity_label(affinity: StringName) -> String:
	var enum_value: Variant = Momentum.Attribute.get(String(affinity))
	return String(Momentum.ATTRIBUTE_NAMES.get(enum_value, ""))
