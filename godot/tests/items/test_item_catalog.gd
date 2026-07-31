extends GutTest


func test_catalog_is_the_runtime_source_for_every_current_item() -> void:
	var definitions: Array = ItemCatalog.all()
	assert_eq(definitions.size(), 22, "10 个战斗消耗品 + 12 个遗物须统一登记")
	var ids: Dictionary = {}
	for value in definitions:
		assert_true(value is ItemDefinition)
		var definition := value as ItemDefinition
		assert_true(definition.is_valid(), String(definition.id))
		assert_false(ids.has(definition.id), "稳定 item_id 不得重复")
		ids[definition.id] = true
	assert_eq(CardPool.all_consumables().size(), 10)
	assert_eq(CardPool.all_relics().size(), 12)


func test_lookup_reuses_index_without_exposing_catalog_array() -> void:
	var first := ItemCatalog.definition(&"iron_shield_v1")
	var second := ItemCatalog.definition(&"iron_shield_v1")
	assert_same(first, second, "热路径查询须复用已索引定义")
	var snapshot := ItemCatalog.all()
	snapshot.clear()
	assert_eq(ItemCatalog.all().size(), 22, "调用方不得清空目录自身数组")


func test_definition_owns_category_use_mode_triggers_and_presentation() -> void:
	var immediate := ItemCatalog.definition(&"wall_peek_v1")
	assert_not_null(immediate)
	assert_true(immediate.is_consumable())
	assert_eq(immediate.use_mode, ItemDefinition.UseMode.IMMEDIATE)
	assert_true(immediate.is_grantable)
	assert_true(immediate.triggers.has(&"GAME_BEGIN"))
	assert_eq(
		immediate.table_icon_path,
		"res://assets/ui/table_hud/items/item_wall_peek.png",
	)

	var armed := ItemCatalog.definition(&"iron_shield_v1")
	assert_eq(armed.use_mode, ItemDefinition.UseMode.ARMED)
	assert_true(armed.triggers.has(&"RON_DECLARED"))

	var relic := ItemCatalog.definition(&"relic_lucky_cat_v1")
	assert_true(relic.is_relic())
	assert_eq(relic.use_mode, ItemDefinition.UseMode.PASSIVE)
	assert_true(relic.triggers.has(&"WIN_DECLARED_PRE"))


func test_unsettled_items_are_known_but_not_grantable_or_usable() -> void:
	for item_id in [&"seat_swap_v1", &"tsubame_v1"]:
		var definition := ItemCatalog.definition(item_id)
		assert_not_null(definition)
		assert_eq(definition.use_mode, ItemDefinition.UseMode.UNAVAILABLE)
		assert_false(definition.is_grantable)
		assert_false(ItemCatalog.can_use(item_id, ItemInstance.STATUS_HELD))


func test_catalog_drives_authority_and_ui_use_gate() -> void:
	assert_true(ItemCatalog.can_use(&"wall_peek_v1", ItemInstance.STATUS_HELD))
	assert_true(ItemCatalog.can_use(&"iron_shield_v1", ItemInstance.STATUS_HELD))
	assert_false(ItemCatalog.can_use(&"iron_shield_v1", ItemInstance.STATUS_ARMED))
	assert_false(ItemCatalog.can_use(&"relic_lucky_cat_v1", ItemInstance.STATUS_HELD))
	assert_false(ItemCatalog.can_use(&"missing_v1", ItemInstance.STATUS_HELD))


func test_legacy_factories_build_from_catalog_definition() -> void:
	var definition := ItemCatalog.definition(&"dora_charm_v1")
	var skill := ConsumableFactory.build(&"dora_charm_v1")
	assert_not_null(skill)
	assert_eq(skill.display_name, definition.display_name)
	assert_eq(skill.description, definition.description)
	assert_eq(skill.owner_triggers, definition.triggers)

	var relic := ItemCatalog.definition(&"relic_wall_eye_v1")
	var relic_skill := RelicFactory.build(&"relic_wall_eye_v1")
	assert_not_null(relic_skill)
	assert_eq(relic_skill.owner_triggers, relic.triggers)


func test_immediate_runner_executes_definition_hook_without_item_id_branch() -> void:
	var state := BattleState.new()
	state.wall = Wall.new_full_set()
	state.wall.reserve_dead_wall(14)
	var before := state.wall.live_wall_size()
	assert_true(ItemEffectRunner.apply_immediate(
		ItemCatalog.definition(&"wall_collapse_v1"), state, 0))
	assert_eq(state.wall.live_wall_size(), before - 6)

	var reveal_state := BattleState.new()
	reveal_state.wall = Wall.new_full_set()
	reveal_state.wall.reserve_dead_wall(14)
	assert_true(ItemEffectRunner.apply_immediate(
		ItemCatalog.definition(&"wall_peek_v1"), reveal_state, 2))
	assert_eq(reveal_state.revealed_tiles.size(), 3)
	for row in reveal_state.revealed_tiles:
		assert_eq(row.get("visible_to", []), [2])
