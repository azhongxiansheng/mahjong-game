extends GutTest

const ABILITY_ID := &"char_momoko_passive_v1"


func _battle(owner_seat: int = 0) -> BattleController:
	var bc := BattleController.new(343)
	assert_true(BossAbilityFactory.inject(bc.registry, ABILITY_ID, owner_seat))
	return bc


func _skill(bc: BattleController) -> SkillResource:
	for entry_value in bc.registry.get_all_entries():
		var entry := entry_value as Dictionary
		var skill := entry.get("skill") as SkillResource
		if skill != null and skill.id == ABILITY_ID:
			return skill
	return null


func _emit(bc: BattleController, event_type: StringName, actor_seat: int) -> SkillCtx:
	return bc.call("_emit", event_type, actor_seat, null, {}) as SkillCtx


func test_real_battle_event_chain_primes_and_owner_win_consumes_one_han() -> void:
	var bc := _battle(2)
	var skill := _skill(bc)
	assert_not_null(skill)

	_emit(bc, &"RIICHI_DECLARED", 2)
	assert_true(bool(skill.params.get("primed", false)))

	var win_ctx := _emit(bc, &"WIN_DECLARED_PRE", 2)
	assert_eq(int(win_ctx.han_deltas.get(2, 0)), 1)
	assert_false(bool(skill.params.get("primed", false)))
	var triggered := bc.events[-1] as BattleEvent
	assert_eq(triggered.type, &"SKILL_TRIGGERED")
	assert_eq(StringName(String(triggered.extra.get("skill_id", ""))), ABILITY_ID)
	assert_eq(StringName(String(triggered.extra.get("source_event", ""))), &"WIN_DECLARED_PRE")


func test_repeated_owner_riichi_is_idempotent_and_never_stacks() -> void:
	var bc := _battle(1)
	var skill := _skill(bc)
	_emit(bc, &"RIICHI_DECLARED", 1)
	_emit(bc, &"RIICHI_DECLARED", 1)
	var first_win := _emit(bc, &"WIN_DECLARED_PRE", 1)
	var second_win := _emit(bc, &"WIN_DECLARED_PRE", 1)
	assert_eq(int(first_win.han_deltas.get(1, 0)), 1)
	assert_eq(int(second_win.han_deltas.get(1, 0)), 0)
	assert_false(bool(skill.params.get("primed", false)))


func test_other_seat_win_cancels_without_bonus_or_false_trigger() -> void:
	var bc := _battle(0)
	var skill := _skill(bc)
	_emit(bc, &"RIICHI_DECLARED", 0)
	var before_events := bc.events.size()
	var other_win := _emit(bc, &"WIN_DECLARED_PRE", 3)
	assert_eq(int(other_win.han_deltas.get(0, 0)), 0)
	assert_false(bool(skill.params.get("primed", false)))
	assert_eq(bc.events.size(), before_events + 1,
		"取消状态不得伪造能力生效 SKILL_TRIGGERED")


func test_all_draw_boundaries_clear_primed() -> void:
	for terminal_event in [&"EXHAUSTIVE_DRAW", &"ABORTIVE_DRAW"]:
		var bc := _battle(0)
		var skill := _skill(bc)
		_emit(bc, &"RIICHI_DECLARED", 0)
		_emit(bc, terminal_event, -1)
		assert_false(bool(skill.params.get("primed", false)),
			"%s 必须清除当前局 primed" % String(terminal_event))


func test_authority_snapshot_restores_primed_then_consumes_once() -> void:
	var source := _battle(3)
	_emit(source, &"RIICHI_DECLARED", 3)
	var snapshot := AuthorityReplaySnapshot.capture(source)
	assert_not_null(snapshot)

	var restored := BattleController.new(999)
	assert_true(snapshot.restore_into(restored))
	var restored_skill := _skill(restored)
	assert_not_null(restored_skill)
	assert_true(bool(restored_skill.params.get("primed", false)))
	var win_ctx := _emit(restored, &"WIN_DECLARED_PRE", 3)
	assert_eq(int(win_ctx.han_deltas.get(3, 0)), 1)
	assert_false(bool(restored_skill.params.get("primed", false)))


func test_factory_registers_all_authoritative_lifecycle_events() -> void:
	var skill := BossAbilityFactory.build(ABILITY_ID)
	assert_not_null(skill)
	assert_eq(skill.owner_triggers, [
		&"RIICHI_DECLARED",
		&"WIN_DECLARED_PRE",
		&"EXHAUSTIVE_DRAW",
		&"ABORTIVE_DRAW",
	])


func test_accepted_riichi_action_primes_through_real_command_entry() -> void:
	var bc := PlayableBattleController.new(343)
	assert_true(BossAbilityFactory.inject(bc.registry, ABILITY_ID, 0))
	var used: Dictionary = {}
	var draw_floor := int(bc.state.wall.draw_index())
	for seat_value in bc.state.seats:
		var seat := seat_value as Seat
		seat.hand = Hand.new()
		seat.melds.restore([], 0)
		seat.last_drawn_instance_id = Tile.INVALID_INSTANCE_ID
		seat.furiten = FuritenState.new()
		seat.river.restore([])
	bc.state.wall.set_draw_index(0)
	bc.state.seats[0].hand = _hand_from_live_wall(bc, [
		TileId.W1, TileId.W1, TileId.W2, TileId.W2, TileId.W3, TileId.W3,
		TileId.W5, TileId.W5, TileId.W6, TileId.W6, TileId.W7, TileId.W7,
		TileId.W9,
	], used)
	var drawn := _draw_live_tile(bc, TileId.W8, used)
	assert_true(bc.state.seats[0].hand.add(drawn))
	bc.state.seats[0].last_drawn_instance_id = drawn.instance_id
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.DISCARD
	bc.state.first_round_active = false
	bc.set("_settled", false)
	bc.set("_active_window", null)
	bc.state.wall.set_draw_index(maxi(draw_floor, bc.state.wall.draw_index()))

	var decision := bc.decision_context_for_seat(0)
	assert_not_null(decision)
	var riichi_iid := -1
	for offer_value in decision.allowed_actions:
		var offer := offer_value as Dictionary
		if String(offer.get("kind", "")) == "RIICHI":
			var options: Array = offer.get("payload_options", [])
			assert_false(options.is_empty())
			riichi_iid = int(options[0].get("tile_instance_id", -1))
			break
	assert_gt(riichi_iid, -1)
	var action := Action.riichi(
		0, riichi_iid, "local", "550e8400-e29b-41d4-a716-000000000343",
		String(decision.decision_id), int(decision.hand_seq), 1)
	var resolution := bc.apply_action(action, ActionSource.HUMAN)
	assert_true(resolution.accepted)
	assert_true(bool(_skill(bc).params.get("primed", false)))
	assert_true(bc.events.any(func(event_value):
		return event_value is BattleEvent \
			and (event_value as BattleEvent).type == &"RIICHI_DECLARED" \
			and (event_value as BattleEvent).actor_seat == 0))


func test_primed_bonus_reaches_real_score_calculation() -> void:
	var compared := false
	for seed_value in [42, 99, 200, 555, 1001]:
		var baseline := BattleController.new(seed_value, 0, true)
		var base_result: Dictionary = baseline.run_to_end()
		var base_win: BattleEvent = null
		for event_value in base_result.events:
			var event := event_value as BattleEvent
			if event.type == &"WIN_DECLARED" \
					and int(event.extra.get("yakuman_multiplier", 0)) == 0:
				base_win = event
				break
		if base_win == null:
			continue
		var powered := BattleController.new(seed_value, 0, true)
		assert_true(BossAbilityFactory.inject(
			powered.registry, ABILITY_ID, base_win.actor_seat))
		_skill(powered).params["primed"] = true
		var powered_result: Dictionary = powered.run_to_end()
		var powered_win: BattleEvent = null
		for event_value in powered_result.events:
			var event := event_value as BattleEvent
			if event.type == &"WIN_DECLARED":
				powered_win = event
				break
		if powered_win == null or powered_win.actor_seat != base_win.actor_seat:
			continue
		assert_eq(
			int(powered_win.extra.get("han", 0)),
			int(base_win.extra.get("han", 0)) + 1,
			"消影一发的 +1 番必须进入真实 ScoreCalc 结果")
		compared = true
		break
	assert_true(compared, "固定 seed 中应找到可比较的非役满真实和牌")


func _draw_live_tile(bc: BattleController, tile_id: int, used: Dictionary) -> Tile:
	var wall := bc.state.wall
	var live_end := wall.authority_tiles().size() - wall.dead_wall_size()
	var found_index := -1
	for index in range(wall.draw_index(), live_end):
		var tile := wall.authority_tiles()[index] as Tile
		if tile != null and tile.id == tile_id and not used.has(tile.instance_id):
			found_index = index
			break
	assert_gte(found_index, 0)
	if found_index != wall.draw_index():
		assert_true(wall.move_live_index_to_top(found_index))
	var drawn := wall.draw()
	assert_not_null(drawn)
	used[drawn.instance_id] = true
	return drawn


func _hand_from_live_wall(
	bc: BattleController, tile_ids: Array, used: Dictionary
) -> Hand:
	var hand := Hand.new()
	for tile_id in tile_ids:
		assert_true(hand.add(_draw_live_tile(bc, int(tile_id), used)))
	return hand
