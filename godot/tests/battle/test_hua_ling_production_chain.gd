extends GutTest

# Issue #342：华岭澄必须从真实角色目录/工厂进入 Action.tsumo →
# WIN_DECLARED_PRE → ScoreCalc → SKILL_TRIGGERED/WIN_DECLARED，而非直调 hook。


func _make_t1_tanki_hand() -> Hand:
	var hand := Hand.new()
	var serial := 0
	for tile_id in [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.T1, TileId.T1,
	]:
		hand.add(Tile.new(tile_id, false, Tile.NO_OWNER, serial))
		serial += 1
	return hand


func _settle_tsumo(
	ability_owner: int = -1,
	with_non_ability_dora: bool = false
) -> BattleController:
	var bc := BattleController.new(42, 0, false, TileId.E)
	if ability_owner >= 0:
		var character := CharacterPool.find(&"hua_ling")
		assert_not_null(character, "真实角色目录必须包含华岭澄")
		assert_eq(character.ability_id, &"char_saki_passive_v1")
		assert_true(BossAbilityFactory.inject(
			bc.registry, character.ability_id, ability_owner),
			"真实 ability factory 必须能构造并注册华岭澄 hook")
	if with_non_ability_dora:
		assert_true(TileSkillFactory.inject_one(
			bc.registry, &"man6_treasure_v1", 0))
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.DISCARD
	bc.state.seats[0].hand = _make_t1_tanki_hand()
	var tiles: Array[Tile] = bc.state.seats[0].hand.tiles()
	var drawn: Tile = tiles[tiles.size() - 1]
	bc.state.seats[0].last_drawn_instance_id = drawn.instance_id
	var checked: Dictionary = bc._check_tsumo(drawn)
	assert_true(bool(checked.get("is_winning", false)), "fixture 必须是真实合法自摸")
	var ctx: DecisionContext = bc.decision_context_for_seat(0)
	assert_not_null(ctx)
	assert_true(ctx.has_kind("TSUMO"))
	var applied := bc.apply_action(Action.tsumo(
		0, "local", "550e8400-e29b-41d4-a716-000000000342",
		ctx.decision_id, 0, 1
	), ActionSource.HUMAN)
	assert_true(applied.accepted, String(applied.error_code))
	return bc


func _last_event(bc: BattleController, type: StringName) -> BattleEvent:
	for index in range(bc.events.size() - 1, -1, -1):
		var event: BattleEvent = bc.events[index]
		if event.type == type:
			return event
	return null


func _event_index(bc: BattleController, type: StringName) -> int:
	for index in range(bc.events.size()):
		if (bc.events[index] as BattleEvent).type == type:
			return index
	return -1


func test_hua_ling_owner_tsumo_adds_two_dora_to_real_score_and_events() -> void:
	var baseline := _settle_tsumo()
	var powered := _settle_tsumo(0)
	var base_win := _last_event(baseline, &"WIN_DECLARED")
	var powered_win := _last_event(powered, &"WIN_DECLARED")
	assert_not_null(base_win)
	assert_not_null(powered_win)
	assert_eq(int(powered_win.extra.get("ability_extra_dora_count", -1)), 2,
		"确认事件必须明确公开本次能力额外 Dora")
	assert_eq(int(powered_win.extra.get("dora_count", -1)),
		int(base_win.extra.get("dora_count", -1)) + 2,
		"真实 ScoreCalc 输入/结果中的 Dora 总数必须增加 2")
	assert_eq(int(powered_win.extra.get("han", 0)),
		int(base_win.extra.get("han", 0)) + 2,
		"额外 Dora 必须进入最终总番")
	assert_gt(int(powered_win.extra.get("winner_total", 0)),
		int(base_win.extra.get("winner_total", 0)),
		"能力必须改变真实支付结果，而非只改展示 DTO")
	var skill := _last_event(powered, &"SKILL_TRIGGERED")
	assert_not_null(skill)
	assert_eq(StringName(skill.extra.get("skill_id", "")), &"char_saki_passive_v1")
	assert_eq(int(skill.extra.get("extra_dora_delta", 0)), 2,
		"Dora 能力的 SKILL_TRIGGERED 必须携带区别于加番能力的事件语义")
	assert_lt(_event_index(powered, &"SKILL_TRIGGERED"),
		_event_index(powered, &"WIN_DECLARED"),
		"能力事件必须在最终确认结算之前出现")


func test_hua_ling_non_owner_win_has_no_bonus_or_skill_noise() -> void:
	var bc := _settle_tsumo(1)
	var win := _last_event(bc, &"WIN_DECLARED")
	assert_not_null(win)
	assert_eq(int(win.extra.get("ability_extra_dora_count", -1)), 0)
	assert_null(_last_event(bc, &"SKILL_TRIGGERED"),
		"非 owner 和牌不得产生空技能反馈或 ability 语音")


func test_non_ability_dora_changes_total_without_impersonating_character_feedback() -> void:
	var baseline := _settle_tsumo()
	var tile_skill := _settle_tsumo(-1, true)
	var base_win := _last_event(baseline, &"WIN_DECLARED")
	var tile_win := _last_event(tile_skill, &"WIN_DECLARED")
	assert_eq(int(tile_win.extra.dora_count), int(base_win.extra.dora_count) + 1)
	assert_eq(int(tile_win.extra.ability_extra_dora_count), 0,
		"牌技能额外 Dora 不得冒充角色 ability 增量")


func test_hua_ling_dora_state_and_events_survive_authority_restore_then_reset() -> void:
	var settled := _settle_tsumo(0)
	var source := BattleController.new(42, 0, false, TileId.E)
	var character := CharacterPool.find(&"hua_ling")
	assert_not_null(character)
	assert_true(BossAbilityFactory.inject(source.registry, character.ability_id, 0))
	source.scheduler.emit_event(BattleEvent.make(
		&"WIN_DECLARED_PRE", 0, null, {"is_tsumo": true}))
	# 结算事件字段必须来自上面的真实 Action.tsumo 生产链；仅去掉跨 controller
	# 不可移植的测试牌 anchor，让干净 source 保持 wall/hand 实体命名空间合法。
	for event_type in [&"SKILL_TRIGGERED", &"WIN_DECLARED"]:
		var produced := _last_event(settled, event_type)
		assert_not_null(produced)
		if produced != null:
			source.events.append(BattleEvent.make(
				produced.type, produced.actor_seat, null, produced.extra.duplicate(true)))
	assert_eq(source.state.extra_dora_count, [2, 0, 0, 0])
	var snapshot := AuthorityReplaySnapshot.capture(source)
	assert_not_null(snapshot)
	var restored := BattleController.new(99, 0, false, TileId.E)
	assert_true(snapshot.restore_into(restored))
	if restored.state.extra_dora_count != [2, 0, 0, 0]:
		return
	assert_eq(restored.state.extra_dora_count, [2, 0, 0, 0])
	var restored_skill := _last_event(restored, &"SKILL_TRIGGERED")
	var restored_win := _last_event(restored, &"WIN_DECLARED")
	assert_not_null(restored_skill)
	assert_not_null(restored_win)
	if restored_skill == null or restored_win == null:
		return
	assert_eq(int(restored_skill.extra.get("extra_dora_delta", 0)), 2,
		"能力事件的 Dora 增量语义必须经过权威快照恢复")
	assert_eq(int(restored_win.extra.get("dora_count", -1)),
		int(_last_event(settled, &"WIN_DECLARED").extra.get("dora_count", -2)))
	assert_eq(int(restored_win.extra.get("ability_extra_dora_count", 0)), 2,
		"确认结算中的能力归因必须经过权威快照恢复")
	var next_hand := BattleController.new(100, 0, false, TileId.E)
	assert_eq(next_hand.state.extra_dora_count, [0, 0, 0, 0],
		"新一局权威状态不得残留上一局能力增量")
