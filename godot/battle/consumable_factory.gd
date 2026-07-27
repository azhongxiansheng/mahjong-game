class_name ConsumableFactory

# 战斗消耗品 → SkillRegistry 注入工厂。
# 把 ConsumableItem (BATTLE kind) 转为 one-shot SkillResource 并注册。
# 所有保留的战斗消耗品都通过本工厂注册效果；RUN kind 不走此工厂。
# #253：GAME_BEGIN 型与即时型可在 ITEM_USE 时直接结算；延迟触发型注册 hook。

static func build(consumable_id: StringName) -> SkillResource:
	var definition := ItemCatalog.definition(consumable_id)
	if definition == null or not definition.is_consumable():
		return null
	return ItemSkillBuilder.build(definition)


static func build_for_instance(
	consumable_id: StringName, item_instance_id: String
) -> SkillResource:
	var definition := ItemCatalog.definition(consumable_id)
	if definition == null or not definition.is_consumable():
		return null
	return ItemSkillBuilder.build(definition, item_instance_id)


static func is_immediate_on_use(consumable_id: StringName) -> bool:
	var definition := ItemCatalog.definition(consumable_id)
	return definition != null \
		and definition.use_mode == ItemDefinition.UseMode.IMMEDIATE


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
	var out: Array = []
	for definition in ItemCatalog.consumables():
		out.append((definition as ItemDefinition).id)
	return out
