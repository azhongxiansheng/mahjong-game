extends GutTest

const ABILITY_ID := &"char_tetsuya_passive_v1"


func _config() -> GameSessionConfig:
	return GameSessionConfig.create_validated(
		GameSessionConfig.ROOM_PRACTICE,
		GameSessionConfig.ROUND_EAST,
		GameSessionConfig.MODE_TRASH_TALK,
		[&"HUMAN", &"AI", &"AI", &"AI"],
		[&"qiu_jue", &"lian_yao", &"ju_jin", &"hua_ling"],
		350,
		"ju-jin-authority-lifecycle",
		"trash_talk_rules_v1")


func _runtime() -> Dictionary:
	var config := _config()
	var bc := PlayableBattleController.new(350)
	var modules := ModeModuleBundle.from_config(config)
	bc.bind_mode_modules(modules)
	modules.item_inventory.set_match_namespace("ju-jin-match")
	return {"config": config, "bc": bc, "modules": modules}


func _grant_pending(modules: ModeModuleBundle, seat: int, source: String,
		target: String, hand_seq: int) -> void:
	var grant := modules.item_inventory.grant_for_seat({
		"seat": seat,
		"item_id": "iron_shield_v1",
		"window_id": source,
		"hand_seq": hand_seq,
		"score": 0,
		"rule_version": "rv",
		"assignment_version": "av",
		"matched_rule_ids": [],
		"affinity_match": true,
		"next_window_id": target,
	})
	assert_true(bool(grant.get("ok", false)))


func _matching_entries(bc: BattleController, seat: int, ability_id: StringName) -> Array:
	return bc.registry.get_all_entries().filter(func(value):
		var entry := value as Dictionary
		var skill := entry.get("skill") as SkillResource
		return int(entry.get("anchor", -1)) == seat \
			and skill != null and skill.id == ability_id)


func test_unarmed_hand_freezes_growth_and_rearm_resumes_from_next_step() -> void:
	var runtime := _runtime()
	var bc := runtime.bc as PlayableBattleController
	var modules := runtime.modules as ModeModuleBundle
	var slot := modules.character_ability_slots[2] as CharacterAbilitySlot
	_grant_pending(modules, 2, "source-1", "w1", 0)
	var armed := ItemAuthority.arm_seats_on_open(
		bc, modules.item_inventory, modules.character_ability_slots, "w1")
	assert_true(bool(armed.get("ok", false)))
	assert_true(slot.armed)
	bc.call("_emit", &"WIN_DECLARED_PRE", 2, null, {})
	bc.call("_emit", &"WIN_DECLARED_PRE", 2, null, {})
	assert_eq(int(slot.skill.params.get("wins", 0)), 2)

	var disarmed := ItemAuthority.disarm_all_active(
		bc, modules.item_inventory, modules.character_ability_slots, "w1")
	assert_true(bool(disarmed.get("ok", false)))
	assert_false(slot.armed)
	assert_false(slot.registry_registered)
	assert_true(_matching_entries(bc, 2, ABILITY_ID).is_empty())
	bc.call("_emit", &"WIN_DECLARED_PRE", 2, null, {})
	assert_eq(int(slot.skill.params.get("wins", 0)), 2,
		"未武装 owner 和牌不增长也不重置")

	_grant_pending(modules, 2, "source-2", "w2", 1)
	var rearmed := ItemAuthority.arm_seats_on_open(
		bc, modules.item_inventory, modules.character_ability_slots, "w2")
	assert_true(bool(rearmed.get("ok", false)))
	assert_eq(_matching_entries(bc, 2, ABILITY_ID).size(), 1)
	var resumed := bc.call("_emit", &"WIN_DECLARED_PRE", 2, null, {}) as SkillCtx
	assert_eq(int(resumed.han_deltas.get(2, 0)), 3)
	assert_eq(int(slot.skill.params.get("wins", 0)), 3)


func test_new_hand_preserves_unregistered_match_state_and_match_clear_resets() -> void:
	var runtime := _runtime()
	var bc := runtime.bc as PlayableBattleController
	var modules := runtime.modules as ModeModuleBundle
	var slot := modules.character_ability_slots[2] as CharacterAbilitySlot
	slot.skill.params["wins"] = 3
	var prepared := ItemAuthority.prepare_new_hand(
		bc, modules.item_inventory, modules.character_ability_slots)
	assert_true(bool(prepared.get("ok", false)))
	assert_false(slot.registry_registered)
	assert_eq(int(slot.skill.params.get("wins", 0)), 3)

	ItemAuthority.clear_match(bc, modules.item_inventory, modules.character_ability_slots)
	assert_eq(int(slot.skill.params.get("wins", -1)), 0)
	assert_false(slot.registry_registered)
	assert_false(slot.armed)


func test_ars_restores_authoritative_instance_then_next_win_is_n_plus_one_once() -> void:
	var runtime := _runtime()
	var bc := runtime.bc as PlayableBattleController
	var modules := runtime.modules as ModeModuleBundle
	var server := LocalLoopbackServer.new(runtime.config, 2, bc, modules)
	var slot := modules.character_ability_slots[2] as CharacterAbilitySlot
	bc.registry.register(slot.skill, 2)
	slot.registry_registered = true
	slot.armed = true
	for _i in range(3):
		bc.call("_emit", &"WIN_DECLARED_PRE", 2, null, {})
	var slot_snapshot: Array = server.call("_capture_ability_slots_arm")
	var authority_snapshot := AuthorityReplaySnapshot.capture(bc)
	assert_not_null(authority_snapshot)
	assert_true(authority_snapshot.restore_into(bc))
	assert_true(bool(server.call("_restore_ability_slots_arm", slot_snapshot)))
	assert_eq(int(slot.skill.params.get("wins", 0)), 3)
	assert_eq(_matching_entries(bc, 2, ABILITY_ID).size(), 1)

	var ctx := bc.call("_emit", &"WIN_DECLARED_PRE", 2, null, {}) as SkillCtx
	assert_eq(int(ctx.han_deltas.get(2, 0)), 4)
	assert_eq(int(slot.skill.params.get("wins", 0)), 4)
	assert_eq(_matching_entries(bc, 2, ABILITY_ID).size(), 1,
		"恢复与重绑不得产生同席双实例")
	var triggers := bc.events.filter(func(value):
		var event := value as BattleEvent
		return event.type == &"SKILL_TRIGGERED" \
			and StringName(String(event.extra.get("skill_id", ""))) == ABILITY_ID)
	assert_eq(triggers.size(), 4, "恢复后只追加一次事件与一次能力语音来源")
