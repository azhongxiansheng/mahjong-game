class_name RelicFactory

# 遗物 → SkillRegistry 注入工厂。
# 遗物是永久被动——每局战斗都注入，hook 不调 consume_self。
# #253：支持同 item_id 多实例（params.item_instance_id 参与 scheduler 去重键）。

static func build(relic_id: StringName) -> SkillResource:
	var definition := ItemCatalog.definition(relic_id)
	if definition == null or not definition.is_relic():
		return null
	return ItemSkillBuilder.build(definition)


## #253：带 instance 身份的构建，供多实例叠加。
static func build_for_instance(
	relic_id: StringName, item_instance_id: String
) -> SkillResource:
	var definition := ItemCatalog.definition(relic_id)
	if definition == null or not definition.is_relic():
		return null
	return ItemSkillBuilder.build(definition, item_instance_id)

static func inject(registry: SkillRegistry, relic_id: StringName, player_seat: int = 0) -> bool:
	var sk: SkillResource = build(relic_id)
	if sk == null:
		return false
	registry.register(sk, player_seat)
	return true

static func inject_all(registry: SkillRegistry, relic_ids: Array, player_seat: int = 0) -> int:
	var count: int = 0
	for raw_id in relic_ids:
		if inject(registry, raw_id as StringName, player_seat):
			count += 1
	return count

static func known_relic_ids() -> Array:
	var out: Array = []
	for definition in ItemCatalog.relics():
		if not (definition as ItemDefinition).triggers.is_empty():
			out.append((definition as ItemDefinition).id)
	return out
