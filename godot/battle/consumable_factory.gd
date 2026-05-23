class_name ConsumableFactory

# 战斗消耗品 → SkillRegistry 注入工厂。
# 把 ConsumableItem (BATTLE kind) 转为 one-shot SkillResource 并注册。
# 旅途消耗品 (RUN kind) 不走此工厂——它们在 RunState 层直接生效。

const _CONSUMABLE_TRIGGERS: Dictionary = {
	&"iron_shield_v1": [&"RON_DECLARED"],
	&"wall_peek_v1": [&"GAME_BEGIN"],
	&"double_payout_v1": [&"WIN_DECLARED_PRE"],
	&"dora_charm_v1": [&"WIN_DECLARED_PRE"],
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
