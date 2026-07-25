class_name ConsumableFactory

# 战斗消耗品 → SkillRegistry 注入工厂。
# 把 ConsumableItem (BATTLE kind) 转为 one-shot SkillResource 并注册。
# 所有保留的战斗消耗品都通过本工厂注册效果；RUN kind 不走此工厂。
# #253：GAME_BEGIN 型与即时型可在 ITEM_USE 时直接结算；延迟触发型注册 hook。

const _CONSUMABLE_TRIGGERS: Dictionary = {
	&"iron_shield_v1": [&"RON_DECLARED"],
	&"wall_peek_v1": [&"GAME_BEGIN"],
	&"double_payout_v1": [&"WIN_DECLARED_PRE"],
	&"dora_charm_v1": [&"WIN_DECLARED_PRE"],
	&"wall_collapse_v1": [&"GAME_BEGIN"],
	&"dora_flip_v1": [&"TILE_DRAWN"],
	&"seat_swap_v1": [&"GAME_BEGIN"],
	&"furiten_bomb_v1": [&"WIN_DECLARED_PRE"],
	&"point_shield_v1": [&"RON_DECLARED"],
	&"tsubame_v1": [&"GAME_BEGIN"],
}

## 使用时立即结算（不等待事件）的消耗品。
## seat_swap / tsubame：产品语义未钉死，不在此表（USE 拒绝）。
const _IMMEDIATE_ON_USE: Dictionary = {
	&"wall_peek_v1": true,
	&"wall_collapse_v1": true,
}

static func build(consumable_id: StringName) -> SkillResource:
	if not _CONSUMABLE_TRIGGERS.has(consumable_id):
		return null
	var item: ConsumableItem = _find_in_pool(consumable_id)
	if item == null or item.hook_resource_path == "":
		return null
	var hook_script: GDScript = load(item.hook_resource_path)
	if hook_script == null:
		return null
	var s := SkillResource.new()
	s.id = consumable_id
	s.display_name = item.display_name
	s.description = item.description
	s.rarity = item.rarity
	s.is_ability = true
	var triggers: Array[StringName] = []
	for t in _CONSUMABLE_TRIGGERS[consumable_id]:
		triggers.append(t)
	s.owner_triggers = triggers
	s.hook_script = hook_script
	return s


static func build_for_instance(
	consumable_id: StringName, item_instance_id: String
) -> SkillResource:
	var s: SkillResource = build(consumable_id)
	if s == null:
		return null
	s.params = s.params.duplicate(true)
	s.params["item_instance_id"] = item_instance_id
	s.params["item_id"] = String(consumable_id)
	return s


static func is_immediate_on_use(consumable_id: StringName) -> bool:
	return bool(_IMMEDIATE_ON_USE.get(consumable_id, false))


static func inject(registry: SkillRegistry, consumable_id: StringName, player_seat: int = 0) -> bool:
	var sk: SkillResource = build(consumable_id)
	if sk == null:
		return false
	registry.register(sk, player_seat)
	return true

static func inject_all(registry: SkillRegistry, consumable_ids: Array, player_seat: int = 0) -> int:
	var count: int = 0
	for raw_id in consumable_ids:
		var id := raw_id as StringName
		if inject(registry, id, player_seat):
			count += 1
	return count

static func known_battle_ids() -> Array:
	return _CONSUMABLE_TRIGGERS.keys()

static func _find_in_pool(cid: StringName) -> ConsumableItem:
	for c in CardPool.all_consumables():
		if c.id == cid:
			return c
	return null
