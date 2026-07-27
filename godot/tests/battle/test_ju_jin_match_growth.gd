extends GutTest

const ABILITY_ID := &"char_tetsuya_passive_v1"


func _battle(owner_seat: int = 0) -> BattleController:
	var bc := BattleController.new(350)
	assert_true(BossAbilityFactory.inject(bc.registry, ABILITY_ID, owner_seat))
	return bc


func _skill(bc: BattleController, ability_id: StringName = ABILITY_ID) -> SkillResource:
	for entry_value in bc.registry.get_all_entries():
		var entry := entry_value as Dictionary
		var skill := entry.get("skill") as SkillResource
		if skill != null and skill.id == ability_id:
			return skill
	return null


func _emit(bc: BattleController, type: StringName, actor: int) -> SkillCtx:
	return bc.call("_emit", type, actor, null, {}) as SkillCtx


func _events_for(bc: BattleController, ability_id: StringName) -> Array:
	return bc.events.filter(func(value):
		if not (value is BattleEvent):
			return false
		var event := value as BattleEvent
		return event.type == &"SKILL_TRIGGERED" \
			and StringName(String(event.extra.get("skill_id", ""))) == ability_id
	)


func _first_win(bc: BattleController) -> BattleEvent:
	for value in bc.events:
		var event := value as BattleEvent
		if event.type == &"WIN_DECLARED":
			return event
	return null


func test_owner_growth_is_match_wide_while_other_results_preserve_it() -> void:
	var bc := _battle(2)
	var skill := _skill(bc)
	for expected_bonus in [1, 2, 3, 4]:
		var ctx := _emit(bc, &"WIN_DECLARED_PRE", 2)
		assert_eq(int(ctx.han_deltas.get(2, 0)), expected_bonus)
		assert_eq(int(skill.params.get("wins", 0)), expected_bonus)
		var triggered := _events_for(bc, ABILITY_ID)
		assert_eq(triggered.size(), expected_bonus)
		assert_eq(int((triggered[-1] as BattleEvent).extra.get("han_delta", 0)),
			expected_bonus, "能力事件必须携带本次真实加番")

	for terminal in [
		{"type": &"WIN_DECLARED_PRE", "actor": 1},
		{"type": &"EXHAUSTIVE_DRAW", "actor": -1},
		{"type": &"ABORTIVE_DRAW", "actor": -1},
	]:
		var before_events := _events_for(bc, ABILITY_ID).size()
		var ctx := _emit(bc, terminal.type, terminal.actor)
		assert_eq(int(ctx.han_deltas.get(2, 0)), 0)
		assert_eq(int(skill.params.get("wins", 0)), 4)
		assert_eq(_events_for(bc, ABILITY_ID).size(), before_events,
			"他家和牌与两类流局只保留阶数，不得伪造触发")


func test_factory_declares_frozen_match_lifecycle_without_streak_reset_triggers() -> void:
	var skill := BossAbilityFactory.build(ABILITY_ID)
	assert_not_null(skill)
	assert_eq(skill.owner_triggers, [&"WIN_DECLARED_PRE"])
	assert_eq(String(skill.params.get("_registry_linger_while_param", "")), "wins")
	assert_true(bool(skill.params.get("_registry_linger_across_hands", false)))
	assert_false(bool(skill.params.get("_registry_keep_registered_while_state", true)),
		"未武装期间必须冻结，不能像连曜真一样留在 registry 接收终局事件")


func test_real_ron_and_tsumo_score_plus_one_two_three_with_generic_attribution() -> void:
	var baseline_by_kind := {false: {}, true: {}}
	for seed_value in range(1, 121):
		if not (baseline_by_kind[false] as Dictionary).is_empty() \
				and not (baseline_by_kind[true] as Dictionary).is_empty():
			break
		var baseline := BattleController.new(seed_value, 0, true)
		var base_result: Dictionary = baseline.run_to_end()
		var base_win := _first_win(baseline)
		if base_win == null or int(base_win.extra.get("yakuman_multiplier", 0)) > 0:
			continue
		var is_tsumo := bool(base_win.extra.get("is_tsumo", false))
		if (baseline_by_kind[is_tsumo] as Dictionary).is_empty():
			baseline_by_kind[is_tsumo] = {
				"seed": seed_value,
				"winner": base_win.actor_seat,
				"han": int(base_win.extra.get("han", 0)),
				"result": base_result,
			}

	for is_tsumo in [false, true]:
		var fixture := baseline_by_kind[is_tsumo] as Dictionary
		assert_false(fixture.is_empty(), "固定 seed 范围必须同时覆盖真实 Ron/Tsumo")
		if fixture.is_empty():
			continue
		for expected_bonus in [1, 2, 3]:
			var powered := BattleController.new(int(fixture.seed), 0, true)
			assert_true(BossAbilityFactory.inject(
				powered.registry, ABILITY_ID, int(fixture.winner)))
			_skill(powered).params["wins"] = expected_bonus - 1
			powered.run_to_end()
			var powered_win := _first_win(powered)
			assert_not_null(powered_win)
			if powered_win == null:
				continue
			assert_eq(powered_win.actor_seat, int(fixture.winner))
			assert_eq(bool(powered_win.extra.get("is_tsumo", false)), is_tsumo)
			assert_eq(int(powered_win.extra.get("han", 0)),
				int(fixture.han) + expected_bonus)
			assert_eq(int(powered_win.extra.get("ability_extra_han_count", 0)),
				expected_bonus)
			assert_eq(powered_win.extra.get("ability_extra_han_sources", []), [{
				"ability_id": String(ABILITY_ID),
				"ability_name": "局进吾·阶升必杀",
				"han": expected_bonus,
			}])
			assert_eq(_events_for(powered, ABILITY_ID).size(), 1)


func test_lian_yao_and_ju_jin_coexist_without_state_or_event_crossing() -> void:
	var bc := _battle(2)
	assert_true(BossAbilityFactory.inject(
		bc.registry, &"char_teru_passive_v1", 1))
	var ju_skill := _skill(bc)
	var lian_skill := _skill(bc, &"char_teru_passive_v1")

	_emit(bc, &"WIN_DECLARED_PRE", 2)
	assert_eq(int(ju_skill.params.get("wins", 0)), 1)
	assert_eq(int(lian_skill.params.get("streak", 0)), 0)
	assert_eq(_events_for(bc, ABILITY_ID).size(), 1)
	assert_eq(_events_for(bc, &"char_teru_passive_v1").size(), 0)

	_emit(bc, &"WIN_DECLARED_PRE", 1)
	assert_eq(int(ju_skill.params.get("wins", 0)), 1,
		"他家和牌不得打断局进吾整场阶升")
	assert_eq(int(lian_skill.params.get("streak", 0)), 1)
	assert_eq(_events_for(bc, ABILITY_ID).size(), 1)
	assert_eq(_events_for(bc, &"char_teru_passive_v1").size(), 1)

	_emit(bc, &"EXHAUSTIVE_DRAW", -1)
	assert_eq(int(ju_skill.params.get("wins", 0)), 1)
	assert_eq(int(lian_skill.params.get("streak", -1)), 0,
		"连曜真仍须被流局打断")
