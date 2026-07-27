extends GutTest

# Issue #345：渊汐必须从真实 config/slot 武装进入权威摸牌与 Ron/Tsumo 结算链。

const CHARACTERS := [&"qiu_jue", &"hua_ling", &"lin_yeche", &"bai_touli"]
const PARTICIPANTS := [&"HUMAN", &"HUMAN", &"HUMAN", &"HUMAN"]
const Resolver := preload("res://battle/viewer_reveal_resolver.gd")


func _make_config(yuan_seat: int) -> GameSessionConfig:
	var characters := CHARACTERS.duplicate()
	characters[yuan_seat] = &"yuan_xi"
	return GameSessionConfig.create_validated(
		GameSessionConfig.ROOM_PUBLIC_CASUAL,
		GameSessionConfig.ROUND_EAST,
		GameSessionConfig.MODE_TRASH_TALK,
		PARTICIPANTS,
		characters,
		345,
		"issue-345-yuan-xi-%d" % yuan_seat,
		"issue-345-v1"
	)


func _arm_yuan_slot(bc: BattleController, yuan_seat: int) -> ModeModuleBundle:
	var config := _make_config(yuan_seat)
	assert_not_null(config)
	var bundle := ModeModuleBundle.from_config(config)
	assert_not_null(bundle)
	var slot := bundle.character_ability_slots[yuan_seat] as CharacterAbilitySlot
	assert_not_null(slot)
	assert_eq(slot.character_id, &"yuan_xi")
	assert_eq(slot.ability_id, &"char_koromo_passive_v1")
	assert_not_null(slot.skill, "真实 factory 必须构造渊汐 hook")
	assert_false(slot.armed)
	var inv := bundle.item_inventory
	inv.set_match_namespace("issue-345")
	assert_true(bool(inv.grant_for_seat({
		"seat": yuan_seat,
		"item_id": "iron_shield_v1",
		"window_id": "w0",
		"hand_seq": 0,
		"score": 0,
		"rule_version": "issue-345-v1",
		"assignment_version": "assign-v1",
		"matched_rule_ids": [],
		"affinity_match": true,
		"next_window_id": "w1",
		"match_namespace": "issue-345",
	}).get("ok", false)))
	var armed := ItemAuthority.arm_seats_on_open(
		bc, inv, bundle.character_ability_slots, "w1")
	assert_true(bool(armed.get("ok", false)), str(armed))
	assert_true(slot.armed)
	assert_true(slot.registry_registered)
	return bundle


func _make_t1_tanki_hand(include_win_tile: bool) -> Hand:
	var hand := Hand.new()
	var ids := [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.T1,
	]
	if include_win_tile:
		ids.append(TileId.T1)
	for index in range(ids.size()):
		hand.add(Tile.new(ids[index], false, Tile.NO_OWNER, index))
	return hand


func _last_event(bc: BattleController, type: StringName) -> BattleEvent:
	for index in range(bc.events.size() - 1, -1, -1):
		var event := bc.events[index] as BattleEvent
		if event.type == type:
			return event
	return null


func _skill_events(bc: BattleController) -> Array:
	var out: Array = []
	for event_value in bc.events:
		var event := event_value as BattleEvent
		if event.type == &"SKILL_TRIGGERED" \
				and StringName(String(event.extra.get("skill_id", ""))) \
				== &"char_koromo_passive_v1":
			out.append(event)
	return out


func _settle_last_tsumo(yuan_seat: int = -1, rinshan: bool = false) -> BattleController:
	var bc := BattleController.new(42, 0, false, TileId.E)
	if yuan_seat >= 0:
		_arm_yuan_slot(bc, yuan_seat)
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.DISCARD
	bc.state.seats[0].hand = _make_t1_tanki_hand(true)
	var drawn := bc.state.seats[0].hand.tiles()[-1] as Tile
	bc.state.seats[0].last_drawn_instance_id = drawn.instance_id
	bc.state.seats[0].last_draw_is_rinshan = rinshan
	assert_true(bc.state.wall.set_draw_index(bc.state.wall.live_end_index()))
	var ctx := bc.decision_context_for_seat(0)
	assert_not_null(ctx)
	assert_true(ctx.has_kind("TSUMO"))
	var result := bc.apply_action(Action.tsumo(
		0, "local", "550e8400-e29b-41d4-a716-000000000345",
		ctx.decision_id, 0, 1), ActionSource.HUMAN)
	assert_true(result.accepted, String(result.error_code))
	return bc


func _settle_last_ron(yuan_seat: int = -1, rinshan_discard: bool = false) -> BattleController:
	var bc := BattleController.new(43, 0, false, TileId.E)
	if yuan_seat >= 0:
		_arm_yuan_slot(bc, yuan_seat)
	bc.state.seats[1].hand = _make_t1_tanki_hand(false)
	bc.state.seats[1].furiten = FuritenState.new()
	bc.state.seats[1].riichi.declared = true
	bc.state.seats[0].hand = Hand.new()
	var discard := Tile.new(TileId.T1, false, Tile.NO_OWNER, 100)
	bc.state.seats[0].hand.add(discard)
	for tile_id in [
		TileId.W2, TileId.W3, TileId.W4, TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4, TileId.E, TileId.E, TileId.S_WIND,
		TileId.S_WIND,
	]:
		bc.state.seats[0].hand.add(Tile.new(
			tile_id, false, Tile.NO_OWNER, 101 + bc.state.seats[0].hand.size()))
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.DISCARD
	bc.state.seats[0].last_drawn_instance_id = discard.instance_id
	bc.state.seats[0].last_draw_is_rinshan = rinshan_discard
	assert_true(bc.state.wall.set_draw_index(bc.state.wall.live_end_index()))
	var turn := bc.decision_context_for_seat(0)
	assert_not_null(turn)
	assert_true(bc.apply_action(Action.discard(
		0, discard.instance_id, "local",
		"550e8400-e29b-41d4-a716-000000000346", turn.decision_id, 0, 1
	), ActionSource.HUMAN).accepted)
	for seat in [1, 2, 3]:
		var claim := bc.decision_context_for_seat(seat)
		assert_not_null(claim)
		var action: Action
		if seat == 1:
			assert_true(claim.has_kind("RON"), "夹具必须提供真实 RON offer")
			action = Action.ron(
				seat, "local", "550e8400-e29b-41d4-a716-00000000034%d" % seat,
				claim.decision_id, 0, seat + 2)
		else:
			action = Action.make_pass(
				seat, "local", "550e8400-e29b-41d4-a716-00000000034%d" % seat,
				claim.decision_id, 0, seat + 2)
		assert_true(bc.apply_action(action, ActionSource.HUMAN).accepted)
	return bc


func _wall_top_for_viewer(state: BattleState, viewer_seat: int, limit: int = 3) -> Array:
	var resolver := Resolver.new()
	assert_true(resolver.has_method("wall_top_for_viewer"),
		"必须提供角色无关的 live-wall 顶部序列 resolver")
	if not resolver.has_method("wall_top_for_viewer"):
		return []
	return resolver.call("wall_top_for_viewer", state, viewer_seat, limit) as Array


func test_owner_real_haitei_tsumo_adds_three_han_to_final_score() -> void:
	var baseline := _settle_last_tsumo()
	var powered := _settle_last_tsumo(0)
	var base_win := _last_event(baseline, &"WIN_DECLARED")
	var win := _last_event(powered, &"WIN_DECLARED")
	assert_not_null(_last_event(powered, &"HAITEI"))
	assert_eq(int(win.extra.get("han", 0)), int(base_win.extra.get("han", 0)) + 3)
	assert_eq(_skill_events(powered).size(), 1)
	assert_eq(String((_skill_events(powered)[0] as BattleEvent).extra.source_event), "HAITEI")


func test_owner_real_houtei_ron_adds_three_han_to_final_score() -> void:
	var baseline := _settle_last_ron()
	var powered := _settle_last_ron(1)
	var base_win := _last_event(baseline, &"WIN_DECLARED")
	var win := _last_event(powered, &"WIN_DECLARED")
	assert_not_null(_last_event(powered, &"HOUTEI"))
	assert_eq(int(win.extra.get("han", 0)), int(base_win.extra.get("han", 0)) + 3)
	assert_eq(_skill_events(powered).size(), 1)
	assert_eq(String((_skill_events(powered)[0] as BattleEvent).extra.source_event), "HOUTEI")


func test_rinshan_tsumo_and_discard_are_not_haitei_or_houtei() -> void:
	for bc in [_settle_last_tsumo(0, true), _settle_last_ron(1, true)]:
		assert_null(_last_event(bc, &"HAITEI"))
		assert_null(_last_event(bc, &"HOUTEI"))
		assert_eq(_skill_events(bc).size(), 0,
			"岭上和牌不得触发渊汐末巡加番或能力语音")


func test_non_owner_last_tile_win_has_no_yuan_bonus() -> void:
	for bc in [_settle_last_tsumo(1), _settle_last_ron(0)]:
		assert_eq(_skill_events(bc).size(), 0)


func test_owner_normal_draw_reveals_post_draw_live_wall_top_three_only_to_owner() -> void:
	var bc := BattleController.new(44, 0, false, TileId.E)
	_arm_yuan_slot(bc, 0)
	assert_true(bc.state.wall.set_draw_index(bc.state.wall.live_end_index() - 4))
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.DRAW
	bc._step_draw()
	var expected := bc.state.wall.peek_top_n(3)
	var owner_view := _wall_top_for_viewer(bc.state, 0)
	assert_eq(owner_view.size(), 3)
	for index in range(3):
		assert_eq((owner_view[index] as TileSkillAnchor).tile.instance_id,
			(expected[index] as Tile).instance_id)
	assert_eq(_wall_top_for_viewer(bc.state, 1).size(), 0,
		"非零 recipient 也必须严格防泄漏")
	assert_eq(_skill_events(bc).size(), 1)


func test_wall_top_zero_one_two_three_boundaries_and_zero_has_no_trigger() -> void:
	for remaining_after_draw in [0, 1, 2, 3, 5]:
		var bc := BattleController.new(50 + remaining_after_draw, 0, false, TileId.E)
		_arm_yuan_slot(bc, 2)
		assert_true(bc.state.wall.set_draw_index(
			bc.state.wall.live_end_index() - remaining_after_draw - 1))
		bc.state.current_seat = 2
		bc.state.phase = BattlePhase.Kind.DRAW
		bc._step_draw()
		assert_eq(_wall_top_for_viewer(bc.state, 2).size(), mini(3, remaining_after_draw))
		assert_eq(_skill_events(bc).size(), 0 if remaining_after_draw == 0 else 1,
			"墙余 0 不得产生空信息反馈")


func test_other_live_draws_consume_without_refill_and_rinshan_does_not_consume() -> void:
	var bc := BattleController.new(60, 0, false, TileId.E)
	_arm_yuan_slot(bc, 0)
	assert_true(bc.state.wall.set_draw_index(bc.state.wall.live_end_index() - 8))
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.DRAW
	bc._step_draw()
	var initial := _wall_top_for_viewer(bc.state, 0)
	assert_eq(initial.size(), 3)
	var rinshan := bc.state.wall.take_rinshan()
	assert_not_null(rinshan)
	assert_eq(_wall_top_for_viewer(bc.state, 0).size(), 3,
		"岭上摸不属于 live wall，不得消费潮见序列")
	for expected_count in [2, 1, 0]:
		assert_not_null(bc.state.wall.draw())
		assert_eq(_wall_top_for_viewer(bc.state, 0).size(), expected_count,
			"其他普通摸只消费已揭示牌，不得补入第四张")


func test_terminal_and_new_hand_clear_wall_top_projection() -> void:
	var bc := BattleController.new(70, 0, false, TileId.E)
	_arm_yuan_slot(bc, 0)
	bc.scheduler.emit_event(BattleEvent.make(&"TILE_DRAWN", 0))
	assert_gt(_wall_top_for_viewer(bc.state, 0).size(), 0)
	bc._emit(&"ABORTIVE_DRAW", -1, null, {"reason": "suufon_renda"})
	assert_eq(_wall_top_for_viewer(bc.state, 0).size(), 0,
		"终局事件必须立即使私有牌墙投影失效")
	var next := BattleController.new(71, 0, false, TileId.E, 1)
	assert_eq(_wall_top_for_viewer(next.state, 0).size(), 0,
		"新 hand_seq 不得继承上一局墙顶信息")


func test_wall_top_survives_atomic_authority_restore_in_same_hand_namespace() -> void:
	var source := BattleController.new(80, 0, false, TileId.E, 12)
	assert_true(BossAbilityFactory.inject(
		source.registry, &"char_koromo_passive_v1", 3))
	source._emit(&"TILE_DRAWN", 3, null, {})
	var expected := _wall_top_for_viewer(source.state, 3)
	assert_eq(expected.size(), 3)
	var snapshot := AuthorityReplaySnapshot.capture(source)
	assert_not_null(snapshot)
	var target := BattleController.new(81, 0, false, TileId.E, 1)
	assert_true(snapshot.restore_into(target), "ARS 必须通过 staging 原子恢复私有牌墙信息")
	assert_eq(target.state.hand_seq, 12)
	var restored := _wall_top_for_viewer(target.state, 3)
	assert_eq(restored.size(), 3)
	for index in range(3):
		var restored_tile := (restored[index] as TileSkillAnchor).tile
		assert_eq(restored_tile.instance_id,
			(expected[index] as TileSkillAnchor).tile.instance_id)
		assert_true(Tile.is_instance_id_in_hand_seq(restored_tile.instance_id, 12))
	assert_eq(_wall_top_for_viewer(target.state, 0).size(), 0)
