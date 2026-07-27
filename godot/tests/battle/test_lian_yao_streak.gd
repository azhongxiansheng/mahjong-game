extends GutTest

const ABILITY_ID := &"char_teru_passive_v1"


func _battle(owner_seat: int = 0) -> BattleController:
	var bc := BattleController.new(349)
	assert_true(BossAbilityFactory.inject(bc.registry, ABILITY_ID, owner_seat))
	return bc


func _skill(bc: BattleController) -> SkillResource:
	for entry_value in bc.registry.get_all_entries():
		var entry := entry_value as Dictionary
		var skill := entry.get("skill") as SkillResource
		if skill != null and skill.id == ABILITY_ID:
			return skill
	return null


func _emit(bc: BattleController, type: StringName, actor: int) -> SkillCtx:
	return bc.call("_emit", type, actor, null, {}) as SkillCtx


func _skill_trigger_count(bc: BattleController) -> int:
	return bc.events.filter(func(value):
		if not (value is BattleEvent):
			return false
		var event := value as BattleEvent
		return event.type == &"SKILL_TRIGGERED" \
			and StringName(String(event.extra.get("skill_id", ""))) == ABILITY_ID
	).size()


func test_owner_ron_or_tsumo_advances_one_two_three_and_triggers_once_each() -> void:
	for owner_seat in [0, 2]:
		var bc := _battle(owner_seat)
		var skill := _skill(bc)
		for expected_bonus in [1, 2, 3]:
			var ctx := _emit(bc, &"WIN_DECLARED_PRE", owner_seat)
			assert_eq(int(ctx.han_deltas.get(owner_seat, 0)), expected_bonus)
			assert_eq(int(skill.params.get("streak", 0)), expected_bonus)
		assert_eq(_skill_trigger_count(bc), 3)


func test_other_winner_and_all_draws_reset_without_false_trigger() -> void:
	for terminal_type in [&"WIN_DECLARED_PRE", &"EXHAUSTIVE_DRAW", &"ABORTIVE_DRAW"]:
		var bc := _battle(1)
		var skill := _skill(bc)
		_emit(bc, &"WIN_DECLARED_PRE", 1)
		assert_eq(int(skill.params.get("streak", 0)), 1)
		var before_triggers := _skill_trigger_count(bc)
		var actor := 3 if terminal_type == &"WIN_DECLARED_PRE" else -1
		var ctx := _emit(bc, terminal_type, actor)
		assert_eq(int(ctx.han_deltas.get(1, 0)), 0)
		assert_eq(int(skill.params.get("streak", -1)), 0)
		assert_eq(_skill_trigger_count(bc), before_triggers,
			"重置不得伪造能力触发")


func test_non_terminal_missed_opportunity_does_not_reset_streak() -> void:
	var bc := _battle(0)
	var skill := _skill(bc)
	_emit(bc, &"WIN_DECLARED_PRE", 0)
	_emit(bc, &"TILE_DISCARDED", 0)
	_emit(bc, &"RON_DECLARED", 2)
	assert_eq(int(skill.params.get("streak", 0)), 1,
		"只有权威终局事件可以打断连胡")


func test_authority_snapshot_restores_current_layer_then_continues_with_plus_three() -> void:
	var source := _battle(3)
	_emit(source, &"WIN_DECLARED_PRE", 3)
	_emit(source, &"WIN_DECLARED_PRE", 3)
	var snapshot := AuthorityReplaySnapshot.capture(source)
	assert_not_null(snapshot)

	var restored := BattleController.new(999)
	assert_true(snapshot.restore_into(restored))
	var restored_skill := _skill(restored)
	assert_not_null(restored_skill)
	assert_eq(int(restored_skill.params.get("streak", 0)), 2)
	var ctx := _emit(restored, &"WIN_DECLARED_PRE", 3)
	assert_eq(int(ctx.han_deltas.get(3, 0)), 3)
	assert_eq(int(restored_skill.params.get("streak", 0)), 3)
	assert_eq(_skill_trigger_count(restored), 3,
		"恢复后的历史事件与本次触发均应各自恰好一次")


func test_factory_registers_win_and_both_authoritative_draw_boundaries() -> void:
	var skill := BossAbilityFactory.build(ABILITY_ID)
	assert_not_null(skill)
	assert_eq(skill.owner_triggers, [
		&"WIN_DECLARED_PRE",
		&"EXHAUSTIVE_DRAW",
		&"ABORTIVE_DRAW",
	])
	assert_eq(String(skill.params.get("_registry_linger_while_param", "")), "streak")
	assert_true(bool(skill.params.get("_registry_linger_across_hands", false)))


func test_ron_and_tsumo_bonus_reach_real_score_calculation() -> void:
	var found := {false: false, true: false}
	for seed_value in range(1, 81):
		if bool(found[false]) and bool(found[true]):
			break
		var baseline := BattleController.new(seed_value, 0, true)
		var base_result: Dictionary = baseline.run_to_end()
		var base_win: BattleEvent = null
		for value in base_result.events:
			var event := value as BattleEvent
			if event.type == &"WIN_DECLARED" \
					and int(event.extra.get("yakuman_multiplier", 0)) == 0:
				base_win = event
				break
		if base_win == null:
			continue
		var is_tsumo := bool(base_win.extra.get("is_tsumo", false))
		if bool(found[is_tsumo]):
			continue
		var powered := BattleController.new(seed_value, 0, true)
		assert_true(BossAbilityFactory.inject(powered.registry, ABILITY_ID, base_win.actor_seat))
		_skill(powered).params["streak"] = 1
		var powered_result: Dictionary = powered.run_to_end()
		var powered_win: BattleEvent = null
		for value in powered_result.events:
			var event := value as BattleEvent
			if event.type == &"WIN_DECLARED":
				powered_win = event
				break
		if powered_win == null or powered_win.actor_seat != base_win.actor_seat:
			continue
		assert_eq(int(powered_win.extra.get("han", 0)),
			int(base_win.extra.get("han", 0)) + 2,
			"已有一层后的下一次真实和牌必须 +2 番")
		assert_eq(_skill_trigger_count(powered), 1)
		found[is_tsumo] = true
	assert_true(bool(found[false]), "固定 seed 范围应覆盖真实 Ron")
	assert_true(bool(found[true]), "固定 seed 范围应覆盖真实 Tsumo")
