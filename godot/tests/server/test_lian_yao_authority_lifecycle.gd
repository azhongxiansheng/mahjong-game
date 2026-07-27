extends GutTest

const ABILITY_ID := &"char_teru_passive_v1"


func _config() -> GameSessionConfig:
	return GameSessionConfig.create_validated(
		GameSessionConfig.ROOM_PRACTICE,
		GameSessionConfig.ROUND_EAST,
		GameSessionConfig.MODE_TRASH_TALK,
		[&"HUMAN", &"AI", &"AI", &"AI"],
		[&"lian_yao", &"qiu_jue", &"bai_touli", &"hua_ling"],
		349,
		"lian-yao-authority-lifecycle",
		"trash_talk_rules_v1")


func _runtime() -> Dictionary:
	var config := _config()
	var bc := PlayableBattleController.new(349)
	var modules := ModeModuleBundle.from_config(config)
	bc.bind_mode_modules(modules)
	return {"config": config, "bc": bc, "modules": modules}


func test_config_slot_and_atomic_restore_continue_from_current_layer_once() -> void:
	var runtime := _runtime()
	var bc := runtime.bc as PlayableBattleController
	var modules := runtime.modules as ModeModuleBundle
	var server := LocalLoopbackServer.new(runtime.config, 0, bc, modules)
	var slot := modules.character_ability_slots[0] as CharacterAbilitySlot
	assert_eq(slot.character_id, &"lian_yao")
	assert_eq(slot.ability_id, ABILITY_ID)
	bc.registry.register(slot.skill, 0)
	slot.registry_registered = true
	slot.armed = true
	bc.call("_emit", &"WIN_DECLARED_PRE", 0, null, {})
	bc.call("_emit", &"WIN_DECLARED_PRE", 0, null, {})
	var slot_snapshot: Array = server.call("_capture_ability_slots_arm")
	var authority_snapshot := AuthorityReplaySnapshot.capture(bc)
	assert_true(authority_snapshot.restore_into(bc))
	assert_true(bool(server.call("_restore_ability_slots_arm", slot_snapshot)))
	assert_eq(int(slot.skill.params.get("streak", 0)), 2)

	var ctx := bc.call("_emit", &"WIN_DECLARED_PRE", 0, null, {}) as SkillCtx
	assert_eq(int(ctx.han_deltas.get(0, 0)), 3)
	var entries := bc.registry.get_all_entries().filter(func(value):
		var entry := value as Dictionary
		var skill := entry.get("skill") as SkillResource
		return int(entry.get("anchor", -1)) == 0 \
			and skill != null and skill.id == ABILITY_ID)
	assert_eq(entries.size(), 1)
	var triggers := bc.events.filter(func(value):
		var event := value as BattleEvent
		return event.type == &"SKILL_TRIGGERED" \
			and StringName(String(event.extra.get("skill_id", ""))) == ABILITY_ID)
	assert_eq(triggers.size(), 3)


func test_owner_streak_survives_new_hand_prepare_but_is_not_registered_until_rearmed() -> void:
	var runtime := _runtime()
	var bc := runtime.bc as PlayableBattleController
	var modules := runtime.modules as ModeModuleBundle
	var slot := modules.character_ability_slots[0] as CharacterAbilitySlot
	bc.registry.register(slot.skill, 0)
	slot.registry_registered = true
	slot.armed = true
	bc.call("_emit", &"WIN_DECLARED_PRE", 0, null, {})
	modules.item_inventory.set_match_namespace("lian-yao-cross-hand")
	var grant := modules.item_inventory.grant_for_seat({
		"seat": 0,
		"item_id": "iron_shield_v1",
		"window_id": "w1",
		"hand_seq": 0,
		"score": 0,
		"rule_version": "rv",
		"assignment_version": "av",
		"matched_rule_ids": [],
		"affinity_match": true,
		"next_window_id": "w2",
	})
	assert_true(bool(grant.get("ok", false)))

	var prepared := ItemAuthority.prepare_new_hand(
		bc, modules.item_inventory, modules.character_ability_slots)
	assert_true(bool(prepared.get("ok", false)))
	assert_false(slot.registry_registered)
	assert_false(slot.armed)
	assert_eq(int(slot.skill.params.get("streak", 0)), 1,
		"owner 连胡层数必须跨新局保留")

	var arm := ItemAuthority.arm_seats_on_open(
		bc, modules.item_inventory, modules.character_ability_slots, "w2")
	assert_true(bool(arm.get("ok", false)))
	assert_true(slot.registry_registered)
	assert_true(slot.armed)
	var ctx := bc.call("_emit", &"WIN_DECLARED_PRE", 0, null, {}) as SkillCtx
	assert_eq(int(ctx.han_deltas.get(0, 0)), 2)


func test_match_clear_resets_streak_and_unregisters_authority_skill() -> void:
	var runtime := _runtime()
	var bc := runtime.bc as PlayableBattleController
	var modules := runtime.modules as ModeModuleBundle
	var slot := modules.character_ability_slots[0] as CharacterAbilitySlot
	bc.registry.register(slot.skill, 0)
	slot.registry_registered = true
	slot.armed = true
	bc.call("_emit", &"WIN_DECLARED_PRE", 0, null, {})

	ItemAuthority.clear_match(bc, modules.item_inventory, modules.character_ability_slots)
	assert_false(slot.registry_registered)
	assert_false(slot.armed)
	assert_eq(int(slot.skill.params.get("streak", -1)), 0)
	assert_true(bc.registry.get_all_entries().is_empty())
