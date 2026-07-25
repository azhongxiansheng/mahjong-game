class_name RelicFactory

# 遗物 → SkillRegistry 注入工厂。
# 遗物是永久被动——每局战斗都注入，hook 不调 consume_self。
# #253：支持同 item_id 多实例（params.item_instance_id 参与 scheduler 去重键）。

const _RELIC_TRIGGERS: Dictionary = {
	&"relic_lucky_cat_v1": [&"WIN_DECLARED_PRE"],
	&"relic_iron_will_v1": [&"WIN_DECLARED_PRE"],
	&"relic_soul_mirror_v1": [&"WIN_DECLARED"],
	&"relic_wall_eye_v1": [&"TILE_DRAWN"],
	&"relic_red_string_v1": [&"WIN_DECLARED_PRE"],
	&"relic_dragon_seal_v1": [&"WIN_DECLARED_PRE"],
	&"relic_wind_charm_v1": [&"WIN_DECLARED_PRE"],
	&"relic_speed_demon_v1": [&"WIN_DECLARED_PRE"],
	&"relic_patience_stone_v1": [&"EXHAUSTIVE_DRAW"],
	&"relic_han_crystal_v1": [&"WIN_DECLARED_PRE"],
	&"relic_comeback_crown_v1": [&"WIN_DECLARED_PRE"],
	# pity_breaker 无运行时 battle hook；不在 grantable 白名单
}

static func build(relic_id: StringName) -> SkillResource:
	if not _RELIC_TRIGGERS.has(relic_id):
		return null
	var item: RelicItem = _find_in_pool(relic_id)
	if item == null or item.hook_resource_path == "":
		return null
	var hook_script: GDScript = load(item.hook_resource_path)
	if hook_script == null:
		return null
	var s := SkillResource.new()
	s.id = relic_id
	s.display_name = item.display_name
	s.description = item.description
	s.rarity = item.rarity
	s.is_ability = true
	var triggers: Array[StringName] = []
	for t in _RELIC_TRIGGERS[relic_id]:
		triggers.append(t)
	s.owner_triggers = triggers
	s.hook_script = hook_script
	return s


## #253：带 instance 身份的构建，供多实例叠加。
static func build_for_instance(
	relic_id: StringName, item_instance_id: String
) -> SkillResource:
	var s: SkillResource = build(relic_id)
	if s == null:
		return null
	s.params = s.params.duplicate(true)
	s.params["item_instance_id"] = item_instance_id
	s.params["item_id"] = String(relic_id)
	return s

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
	return _RELIC_TRIGGERS.keys()

static func _find_in_pool(rid: StringName) -> RelicItem:
	for r in CardPool.all_relics():
		if r.id == rid:
			return r
	return null
