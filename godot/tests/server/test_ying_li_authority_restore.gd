extends GutTest

const ABILITY_ID := &"char_momoko_passive_v1"


func _config() -> GameSessionConfig:
	return GameSessionConfig.create_validated(
		GameSessionConfig.ROOM_PRACTICE,
		GameSessionConfig.ROUND_EAST,
		GameSessionConfig.MODE_TRASH_TALK,
		[&"HUMAN", &"AI", &"AI", &"AI"],
		[&"ying_li", &"qiu_jue", &"bai_touli", &"hua_ling"],
		343,
		"ying-li-authority-restore",
		"trash_talk_rules_v1")


func test_config_slot_rebinds_to_restored_authoritative_skill_identity() -> void:
	var config := _config()
	assert_not_null(config)
	var bc := PlayableBattleController.new(343)
	var modules := ModeModuleBundle.from_config(config)
	assert_not_null(modules)
	bc.bind_mode_modules(modules)
	var server := LocalLoopbackServer.new(config, 0, bc, modules)
	var slot := modules.character_ability_slots[0] as CharacterAbilitySlot
	assert_not_null(slot)
	assert_eq(slot.character_id, &"ying_li")
	assert_eq(slot.ability_id, ABILITY_ID)
	assert_not_null(slot.skill)
	assert_eq(slot.skill.id, ABILITY_ID)

	bc.registry.register(slot.skill, 0)
	slot.armed = true
	slot.registry_registered = true
	slot.active_window_id = "w1"
	bc.call("_emit", &"RIICHI_DECLARED", 0, null, {})
	assert_true(bool(slot.skill.params.get("primed", false)))
	var slot_snapshot: Array = server.call("_capture_ability_slots_arm")
	var authority_snapshot := AuthorityReplaySnapshot.capture(bc)
	assert_not_null(authority_snapshot)
	assert_true(authority_snapshot.restore_into(bc))
	var restored_entry := bc.registry.get_all_entries()[0] as Dictionary
	var restored_skill := restored_entry.get("skill") as SkillResource
	assert_not_null(restored_skill)
	assert_true(bool(restored_skill.params.get("primed", false)))
	assert_false(slot.skill == restored_skill,
		"Red 前提：ARS 恢复会替换 registry 内的 SkillResource")

	assert_true(bool(server.call("_restore_ability_slots_arm", slot_snapshot)))
	assert_true(slot.skill == restored_skill,
		"恢复后 slot 必须重绑到 registry 的权威 SkillResource")
	var win_ctx := bc.call("_emit", &"WIN_DECLARED_PRE", 0, null, {}) as SkillCtx
	assert_eq(int(win_ctx.han_deltas.get(0, 0)), 1)
	assert_false(bool(slot.skill.params.get("primed", false)))


func test_restore_true_snapshot_does_not_duplicate_existing_authority_entry() -> void:
	var config := _config()
	var bc := PlayableBattleController.new(343)
	var modules := ModeModuleBundle.from_config(config)
	bc.bind_mode_modules(modules)
	var server := LocalLoopbackServer.new(config, 0, bc, modules)
	var slot := modules.character_ability_slots[0] as CharacterAbilitySlot
	bc.registry.register(slot.skill, slot.seat)
	slot.armed = true
	slot.registry_registered = true
	slot.active_window_id = "w1"
	var slot_snapshot: Array = server.call("_capture_ability_slots_arm")
	var authority_snapshot := AuthorityReplaySnapshot.capture(bc)
	assert_not_null(authority_snapshot)
	assert_true(authority_snapshot.restore_into(bc))
	var restored_skill := (bc.registry.get_all_entries()[0] as Dictionary).get(
		"skill") as SkillResource
	assert_not_null(restored_skill)

	# 模拟事务回滚时当前 slot flag 已清，但 ARS 已恢复 registry 权威 entry。
	slot.registry_registered = false
	assert_true(bool(server.call("_restore_ability_slots_arm", slot_snapshot)))
	assert_true(slot.skill == restored_skill)
	var matching_entries := bc.registry.get_all_entries().filter(func(entry_value):
		if typeof(entry_value) != TYPE_DICTIONARY:
			return false
		var entry := entry_value as Dictionary
		var skill := entry.get("skill") as SkillResource
		return int(entry.get("anchor", -1)) == slot.seat \
			and skill != null and skill.id == ABILITY_ID)
	assert_eq(matching_entries.size(), 1,
		"ARS 已恢复权威 entry 时，slot flag 回滚不得重复 register")
	assert_true((matching_entries[0] as Dictionary).get("skill") == restored_skill)

	bc.call("_emit", &"RIICHI_DECLARED", slot.seat, null, {})
	var win_ctx := bc.call(
		"_emit", &"WIN_DECLARED_PRE", slot.seat, null, {}) as SkillCtx
	assert_eq(int(win_ctx.han_deltas.get(slot.seat, 0)), 1)
	var win_triggers := bc.events.filter(func(event_value):
		if not (event_value is BattleEvent):
			return false
		var event := event_value as BattleEvent
		return event.type == &"SKILL_TRIGGERED" \
			and StringName(String(event.extra.get("skill_id", ""))) == ABILITY_ID \
			and StringName(String(event.extra.get("source_event", ""))) \
				== &"WIN_DECLARED_PRE")
	assert_eq(win_triggers.size(), 1)


func test_restore_failure_does_not_partially_rebind_earlier_slots() -> void:
	var config := _config()
	var bc := PlayableBattleController.new(343)
	var modules := ModeModuleBundle.from_config(config)
	bc.bind_mode_modules(modules)
	var server := LocalLoopbackServer.new(config, 0, bc, modules)
	var first_slot := modules.character_ability_slots[0] as CharacterAbilitySlot
	var later_slot := modules.character_ability_slots[1] as CharacterAbilitySlot
	var original_first_skill := first_slot.skill

	bc.registry.register(first_slot.skill, first_slot.seat)
	bc.registry.register(later_slot.skill, later_slot.seat)
	first_slot.registry_registered = true
	later_slot.registry_registered = true
	var slot_snapshot: Array = server.call("_capture_ability_slots_arm")
	bc.registry.unregister(first_slot.skill, first_slot.seat)
	bc.registry.unregister(later_slot.skill, later_slot.seat)
	var restored_first_skill := BossAbilityFactory.build(first_slot.ability_id)
	bc.registry.register(restored_first_skill, first_slot.seat)

	assert_false(bool(server.call("_restore_ability_slots_arm", slot_snapshot)))
	assert_true(first_slot.skill == original_first_skill,
		"任一后续槽位缺少权威 skill 时，较早槽位不得被部分重绑")


func test_primed_registration_survives_mid_hand_window_disarm_until_consumed() -> void:
	var config := _config()
	var bc := PlayableBattleController.new(343)
	var modules := ModeModuleBundle.from_config(config)
	bc.bind_mode_modules(modules)
	var inventory := modules.item_inventory
	inventory.set_match_namespace("ying-li-lingering")
	assert_true(bool(inventory.grant_for_seat({
		"seat": 0,
		"item_id": "iron_shield_v1",
		"window_id": "w0",
		"hand_seq": 0,
		"score": 0,
		"rule_version": "rv",
		"assignment_version": "av",
		"matched_rule_ids": [],
		"affinity_match": true,
		"next_window_id": "w1",
	}).get("ok", false)))
	var arm := ItemAuthority.arm_seats_on_open(
		bc, inventory, modules.character_ability_slots, "w1")
	assert_true(bool(arm.get("ok", false)))
	var slot := modules.character_ability_slots[0] as CharacterAbilitySlot
	assert_true(slot.registry_registered)

	bc.call("_emit", &"RIICHI_DECLARED", 0, null, {})
	assert_true(bool(slot.skill.params.get("primed", false)))
	var disarm := ItemAuthority.disarm_all_active(
		bc, inventory, modules.character_ability_slots, "w1")
	assert_true(bool(disarm.get("ok", false)))
	assert_false(slot.armed)
	assert_true(slot.registry_registered,
		"奖励窗中途结束后，primed 的权威监听必须保留到本局终点")

	var win_ctx := bc.call("_emit", &"WIN_DECLARED_PRE", 0, null, {}) as SkillCtx
	assert_eq(int(win_ctx.han_deltas.get(0, 0)), 1)
	assert_false(bool(slot.skill.params.get("primed", false)))
	assert_true(bool(ItemAuthority.prepare_new_hand(
		bc, inventory, modules.character_ability_slots).get("ok", false)))
	assert_false(slot.registry_registered,
		"状态消费后，新局准备必须移除本局残留监听")


func test_new_hand_boundary_clears_primed_without_relying_on_terminal_hook() -> void:
	var config := _config()
	var bc := PlayableBattleController.new(343)
	var modules := ModeModuleBundle.from_config(config)
	bc.bind_mode_modules(modules)
	var slot := modules.character_ability_slots[0] as CharacterAbilitySlot
	bc.registry.register(slot.skill, slot.seat)
	slot.registry_registered = true
	slot.skill.params["primed"] = true

	var prepared := ItemAuthority.prepare_new_hand(
		bc, modules.item_inventory, modules.character_ability_slots)
	assert_true(bool(prepared.get("ok", false)))
	assert_false(slot.registry_registered)
	assert_false(bool(slot.skill.params.get("primed", false)),
		"当前局结束后即使未观察到终局 hook，新局权威边界也不得继承 primed")
