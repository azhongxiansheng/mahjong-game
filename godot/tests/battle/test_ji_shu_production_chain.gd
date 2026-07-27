extends GutTest

# Issue #346：纪枢必须从真实 config/slot 武装，经 BattleController 合法行动
# 产生权威听牌跃迁；禁止测试直调 hook 或客户端自行推导。

const PARTICIPANTS := [&"HUMAN", &"HUMAN", &"HUMAN", &"HUMAN"]
const BASE_CHARACTERS := [&"qiu_jue", &"hua_ling", &"lin_yeche", &"bai_touli"]


func _bind_ji_shu_slot(bc: BattleController, owner_seat: int) -> CharacterAbilitySlot:
	var characters := BASE_CHARACTERS.duplicate()
	characters[owner_seat] = &"ji_shu"
	var config := GameSessionConfig.create_validated(
		GameSessionConfig.ROOM_PUBLIC_CASUAL,
		GameSessionConfig.ROUND_EAST,
		GameSessionConfig.MODE_TRASH_TALK,
		PARTICIPANTS,
		characters,
		346,
		"issue-346-ji-shu-%d" % owner_seat,
		"issue-346-v1")
	assert_not_null(config)
	var bundle := ModeModuleBundle.from_config(config)
	assert_not_null(bundle)
	var slot := bundle.character_ability_slots[owner_seat] as CharacterAbilitySlot
	assert_not_null(slot)
	assert_eq(slot.character_id, &"ji_shu")
	assert_eq(slot.ability_id, &"char_nodoka_passive_v1")
	assert_not_null(slot.skill, "真实 factory 必须构造纪枢独立 hook")
	var inventory := bundle.item_inventory
	inventory.set_match_namespace("issue-346")
	assert_true(bool(inventory.grant_for_seat({
		"seat": owner_seat,
		"item_id": "iron_shield_v1",
		"window_id": "w0",
		"hand_seq": 0,
		"score": 0,
		"rule_version": "issue-346-v1",
		"assignment_version": "assign-v1",
		"matched_rule_ids": [],
		"affinity_match": true,
		"next_window_id": "w1",
		"match_namespace": "issue-346",
	}).get("ok", false)))
	var armed := ItemAuthority.arm_seats_on_open(
		bc, inventory, bundle.character_ability_slots, "w1")
	assert_true(bool(armed.get("ok", false)), str(armed))
	assert_true(slot.armed)
	assert_true(slot.registry_registered)
	return slot


func _tenpai_plus_discard_hand() -> Hand:
	var hand := Hand.new()
	var ids := [
		TileId.W1, TileId.W2, TileId.W3,
		TileId.T1, TileId.T2, TileId.T3,
		TileId.S1, TileId.S2, TileId.S3,
		TileId.E, TileId.E, TileId.E,
		TileId.S_WIND,
		TileId.W9,
	]
	for index in range(ids.size()):
		hand.add(Tile.new(ids[index], false, Tile.NO_OWNER, index))
	return hand


func _hand_from_ids(ids: Array) -> Hand:
	var hand := Hand.new()
	for index in range(ids.size()):
		hand.add(Tile.new(ids[index], false, Tile.NO_OWNER, index))
	return hand


func _non_tenpai_plus_discard_hand() -> Hand:
	return _hand_from_ids([
		TileId.W1, TileId.W4, TileId.W7,
		TileId.T1, TileId.T4, TileId.T7,
		TileId.S1, TileId.S4, TileId.S7,
		TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N,
		TileId.W9,
	])


func _multi_wait_plus_discard_hand() -> Hand:
	return _hand_from_ids([
		TileId.W1, TileId.W2, TileId.W3, TileId.W4, TileId.W5,
		TileId.T1, TileId.T2, TileId.T3,
		TileId.S1, TileId.S2, TileId.S3,
		TileId.E, TileId.E,
		TileId.T9,
	])


func _apply_discard_hand(
	bc: BattleController, seat_id: int, hand: Hand, client_seq: int
) -> ActionResolution:
	var unique_hand := Hand.new()
	for tile_value in hand.tiles():
		var source := tile_value as Tile
		unique_hand.add(Tile.new(
			source.id, source.is_red_dora, Tile.NO_OWNER,
			source.instance_id + client_seq * 14))
	bc.state.current_seat = seat_id
	bc.state.phase = BattlePhase.Kind.DISCARD
	bc._invalidate_window()
	bc.state.seats[seat_id].hand = unique_hand
	var tile := unique_hand.tiles()[-1] as Tile
	bc.state.seats[seat_id].last_drawn_instance_id = tile.instance_id
	var context := bc.decision_context_for_seat(seat_id)
	return bc.apply_action(Action.discard(
		seat_id, tile.instance_id, "local",
		"550e8400-e29b-41d4-a716-%012d" % (346 + client_seq),
		context.decision_id, 0, client_seq), ActionSource.HUMAN)


func _discard_last(bc: BattleController, seat_id: int) -> ActionResolution:
	bc.state.current_seat = seat_id
	bc.state.phase = BattlePhase.Kind.DISCARD
	bc.state.seats[seat_id].hand = _tenpai_plus_discard_hand()
	var tile := bc.state.seats[seat_id].hand.tiles()[-1] as Tile
	bc.state.seats[seat_id].last_drawn_instance_id = tile.instance_id
	var context := bc.decision_context_for_seat(seat_id)
	assert_not_null(context)
	return bc.apply_action(Action.discard(
		seat_id,
		tile.instance_id,
		"local",
		"550e8400-e29b-41d4-a716-000000000346",
		context.decision_id,
		0,
		1), ActionSource.HUMAN)


func _discard_last_with_authority_tiles(
	bc: BattleController, seat_id: int
) -> ActionResolution:
	for seat_value in bc.state.seats:
		(seat_value as Seat).hand = Hand.new()
	var wanted := [
		TileId.W1, TileId.W2, TileId.W3,
		TileId.T1, TileId.T2, TileId.T3,
		TileId.S1, TileId.S2, TileId.S3,
		TileId.E, TileId.E, TileId.E,
		TileId.S_WIND, TileId.W9,
	]
	var hand := Hand.new()
	var used: Dictionary = {}
	for tile_id in wanted:
		var found: Tile = null
		for tile_value in bc.state.wall.authority_tiles():
			var tile := tile_value as Tile
			if tile.id == tile_id and not used.has(tile.instance_id):
				found = tile
				break
		assert_not_null(found)
		if found != null:
			used[found.instance_id] = true
			hand.add(found)
	bc.state.current_seat = seat_id
	bc.state.phase = BattlePhase.Kind.DISCARD
	bc._invalidate_window()
	bc.state.seats[seat_id].hand = hand
	var discard := hand.tiles()[-1] as Tile
	bc.state.seats[seat_id].last_drawn_instance_id = discard.instance_id
	var context := bc.decision_context_for_seat(seat_id)
	return bc.apply_action(Action.discard(
		seat_id, discard.instance_id, "local",
		"550e8400-e29b-41d4-a716-000000000361",
		context.decision_id, 0, 1), ActionSource.HUMAN)


func _events_of_type(bc: BattleController, event_type: StringName) -> Array:
	var out: Array = []
	for value in bc.events:
		var event := value as BattleEvent
		if event.type == event_type:
			out.append(event)
	return out


func _winning_tsumo_hand() -> Hand:
	var hand := Hand.new()
	var ids := [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.T1, TileId.T1,
	]
	for index in range(ids.size()):
		hand.add(Tile.new(ids[index], false, Tile.NO_OWNER, index))
	return hand


func _settle_tsumo(owner_seat: int = -1) -> BattleController:
	var bc := BattleController.new(346, 0, false, TileId.E, 0)
	if owner_seat >= 0:
		_bind_ji_shu_slot(bc, owner_seat)
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.DISCARD
	bc.state.seats[0].hand = _winning_tsumo_hand()
	var drawn := bc.state.seats[0].hand.tiles()[-1] as Tile
	bc.state.seats[0].last_drawn_instance_id = drawn.instance_id
	var context := bc.decision_context_for_seat(0)
	assert_not_null(context)
	assert_true(context.has_kind("TSUMO"))
	var applied := bc.apply_action(Action.tsumo(
		0, "local", "550e8400-e29b-41d4-a716-000000000360",
		context.decision_id, 0, 1), ActionSource.HUMAN)
	assert_true(applied.accepted, String(applied.error_code))
	return bc


func _winning_ron_hand() -> Hand:
	return _hand_from_ids([
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.T1,
	])


func _settle_chankan_ron(owner_seat: int = -1) -> BattleController:
	var bc := BattleController.new(346, 0, false, TileId.E, 0)
	if owner_seat >= 0:
		_bind_ji_shu_slot(bc, owner_seat)
	bc.state.seats[1].hand = _winning_ron_hand()
	bc.state.seats[1].furiten = FuritenState.new()
	bc.state.seats[0].hand = _hand_from_ids([
		TileId.T1,
		TileId.W2, TileId.W3, TileId.W4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.W7, TileId.W8, TileId.W9,
		TileId.E, TileId.E, TileId.S_WIND,
	])
	var pon := Meld.make_pon([
		Tile.new(TileId.T1, false, 0, 40),
		Tile.new(TileId.T1, false, 0, 41),
		Tile.new(TileId.T1, false, 0, 42),
	], 2, 0)
	bc.state.seats[0].melds.restore([pon], 1)
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.DISCARD
	bc.state.seats[0].last_drawn_instance_id = 0
	var context := bc.decision_context_for_seat(0)
	var payload: Dictionary = {}
	for offer_value in context.allowed_actions:
		var offer := offer_value as Dictionary
		if str(offer.get("kind", "")) != "KAN":
			continue
		for option_value in offer.get("payload_options", []) as Array:
			var option := option_value as Dictionary
			if str(option.get("kan_kind", "")) == "ADDED_KAN":
				payload = option
	assert_false(payload.is_empty())
	assert_true(bc.apply_action(Action.kan(
		0, payload, "local", "550e8400-e29b-41d4-a716-000000000372",
		context.decision_id, 0, 1), ActionSource.HUMAN).accepted)
	for seat_id in [1, 2, 3]:
		var claim := bc.decision_context_for_seat(seat_id)
		var action: Action
		if seat_id == 1:
			assert_true(claim.has_kind("RON"))
			action = Action.ron(
				seat_id, "local", "550e8400-e29b-41d4-a716-00000000037%d" % seat_id,
				claim.decision_id, 0, seat_id + 1)
		else:
			action = Action.make_pass(
				seat_id, "local", "550e8400-e29b-41d4-a716-00000000037%d" % seat_id,
				claim.decision_id, 0, seat_id + 1)
		assert_true(bc.apply_action(action, ActionSource.HUMAN).accepted)
	return bc


func _last_event(bc: BattleController, event_type: StringName) -> BattleEvent:
	for index in range(bc.events.size() - 1, -1, -1):
		var event := bc.events[index] as BattleEvent
		if event.type == event_type:
			return event
	return null


func _apply_open_claim(
	bc: BattleController, kind: String, claimant: int, discarded_id: int, hand_ids: Array,
	client_seq: int
) -> void:
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.CLAIM
	bc._invalidate_window()
	var discarded := Tile.new(discarded_id, false, 0, 100 + client_seq)
	bc._last_discarded_tile = discarded
	bc._last_discarder_seat = 0
	bc.state.seats[0].river.restore([discarded])
	bc.state.seats[claimant].hand = _hand_from_ids(hand_ids)
	for seat_id in [1, 2, 3]:
		bc.state.seats[seat_id].furiten = FuritenState.new()
		var context := bc.decision_context_for_seat(seat_id)
		assert_not_null(context)
		var action: Action
		if seat_id == claimant:
			var payload: Dictionary = {}
			for offer_value in context.allowed_actions:
				var offer := offer_value as Dictionary
				if str(offer.get("kind", "")) == kind:
					payload = (offer.get("payload_options", [{}]) as Array)[0]
			assert_false(payload.is_empty(), "夹具必须提供真实 %s offer" % kind)
			match kind:
				"CHI":
					action = Action.chi(
						claimant, payload.companion_tile_instance_ids, "local",
						"550e8400-e29b-41d4-a716-%012d" % (380 + client_seq * 4 + seat_id),
						context.decision_id, 0, client_seq * 4 + seat_id)
				"PON":
					action = Action.pon(
						claimant, payload.companion_tile_instance_ids, "local",
						"550e8400-e29b-41d4-a716-%012d" % (380 + client_seq * 4 + seat_id),
						context.decision_id, 0, client_seq * 4 + seat_id)
				"KAN":
					action = Action.kan(
						claimant, payload, "local",
						"550e8400-e29b-41d4-a716-%012d" % (380 + client_seq * 4 + seat_id),
						context.decision_id, 0, client_seq * 4 + seat_id)
		else:
			action = Action.make_pass(
				seat_id, "local",
				"550e8400-e29b-41d4-a716-%012d" % (380 + client_seq * 4 + seat_id),
				context.decision_id, 0, client_seq * 4 + seat_id)
		var result := bc.apply_action(action, ActionSource.HUMAN)
		assert_true(result.accepted, "%s seat=%d error=%s" % [kind, seat_id, result.error_code])


func test_real_discard_enters_tenpai_once_and_reveals_only_to_ji_shu() -> void:
	var bc := BattleController.new(346, 0, false, TileId.E, 0)
	_bind_ji_shu_slot(bc, 0)
	var result := _discard_last(bc, 1)
	assert_true(result.accepted, String(result.error_code))
	var entered := _events_of_type(bc, &"TENPAI_ENTERED")
	assert_eq(entered.size(), 1, "合法弃牌必须从真实行动链产生一次权威跃迁")
	if not entered.is_empty():
		assert_eq((entered[0] as BattleEvent).actor_seat, 1)
		assert_true((entered[0] as BattleEvent).extra.is_empty(),
			"领域事件不得携带等待牌或隐藏手牌")
	var skill_events := _events_of_type(bc, &"SKILL_TRIGGERED")
	assert_eq(skill_events.size(), 1, "真实新信息必须发动一次纪枢能力")
	if not skill_events.is_empty():
		assert_eq(StringName(String((skill_events[0] as BattleEvent).extra.skill_id)),
			&"char_nodoka_passive_v1")
	assert_true(bc.state.tenpai_flags[1])
	assert_eq(bc.state.tenpai_wait_reveals, {
		0: {1: [TileId.S_WIND]},
	}, "等待牌只能授权给纪枢 owner")


func test_without_ji_shu_real_discard_keeps_private_projection_empty() -> void:
	var bc := BattleController.new(346, 0, false, TileId.E, 0)
	var result := _discard_last(bc, 1)
	assert_true(result.accepted, String(result.error_code))
	assert_eq(_events_of_type(bc, &"TENPAI_ENTERED").size(), 1,
		"听牌领域事实不依赖是否装备纪枢")
	assert_true(bc.state.tenpai_wait_reveals.is_empty(),
		"未装备能力时不得产生私有等待牌")
	assert_true(_events_of_type(bc, &"SKILL_TRIGGERED").is_empty())


func test_owner_real_tsumo_adds_one_han_but_non_owner_does_not() -> void:
	var baseline := _settle_tsumo()
	var owner := _settle_tsumo(0)
	var non_owner := _settle_tsumo(1)
	var base_win := _last_event(baseline, &"WIN_DECLARED")
	var owner_win := _last_event(owner, &"WIN_DECLARED")
	var non_owner_win := _last_event(non_owner, &"WIN_DECLARED")
	assert_not_null(base_win)
	assert_not_null(owner_win)
	assert_not_null(non_owner_win)
	assert_eq(int(owner_win.extra.get("han", 0)), int(base_win.extra.get("han", 0)) + 1,
		"owner 的既有 WIN_DECLARED_PRE +1 必须进入最终计分")
	assert_eq(int(non_owner_win.extra.get("han", 0)), int(base_win.extra.get("han", 0)),
		"非 owner 和牌不得获得纪枢加番")
	assert_eq(_events_of_type(owner, &"SKILL_TRIGGERED").size(), 1)
	assert_true(_events_of_type(non_owner, &"SKILL_TRIGGERED").is_empty())


func test_owner_real_ron_adds_one_han_to_final_score() -> void:
	var baseline := _settle_chankan_ron()
	var powered := _settle_chankan_ron(1)
	var base_win := _last_event(baseline, &"WIN_DECLARED")
	var win := _last_event(powered, &"WIN_DECLARED")
	assert_not_null(base_win)
	assert_not_null(win)
	assert_false(bool(win.extra.get("is_tsumo", true)))
	assert_eq(int(win.extra.get("han", 0)), int(base_win.extra.get("han", 0)) + 1)
	assert_gt(int(win.extra.get("winner_total", 0)), int(base_win.extra.get("winner_total", 0)))
	var skill_events := _events_of_type(powered, &"SKILL_TRIGGERED").filter(
		func(event): return StringName(String(event.extra.get("skill_id", ""))) \
			== &"char_nodoka_passive_v1")
	assert_eq(skill_events.size(), 1)


func test_authority_restore_preserves_transition_and_does_not_retrigger() -> void:
	var source := BattleController.new(346, 0, false, TileId.E, 0)
	_bind_ji_shu_slot(source, 0)
	assert_true(_discard_last_with_authority_tiles(source, 1).accepted)
	var snapshot := AuthorityReplaySnapshot.capture(source)
	assert_not_null(snapshot)
	assert_true(AuthorityReplaySnapshot._validate_restore_shape(snapshot.to_dict()),
		"ARS schema 必须接受听牌字段")
	var contradictory := snapshot.to_dict()
	contradictory.tenpai_flags[1] = false
	assert_false(AuthorityReplaySnapshot._validate_restore_shape(contradictory),
		"ARS 必须拒绝等待牌投影与权威听牌门闩矛盾的快照")
	assert_true(snapshot.can_restore(), "ARS 必须原子捕获听牌跃迁状态")
	var restored := BattleController.new(999, 0, false, TileId.E, 0)
	assert_true(snapshot.restore_into(restored))
	assert_true(restored.state.tenpai_flags[1])
	assert_eq(restored.state.tenpai_wait_reveals, {0: {1: [TileId.S_WIND]}})
	var before := _events_of_type(restored, &"TENPAI_ENTERED").size()
	# 首次进入已经由上面的真实 Action 证明；此处只验证 ARS 恢复后的跃迁门闩。
	restored._refresh_tenpai_state(1)
	assert_eq(_events_of_type(restored, &"TENPAI_ENTERED").size(), before,
		"恢复后仍处于听牌不得重复触发")


func test_terminal_and_new_hand_clear_private_waits() -> void:
	var bc := BattleController.new(346, 0, false, TileId.E, 0)
	_bind_ji_shu_slot(bc, 0)
	assert_true(_discard_last(bc, 1).accepted)
	bc._emit(&"EXHAUSTIVE_DRAW", -1, null, {})
	assert_eq(bc.state.tenpai_flags, [false, false, false, false])
	assert_true(bc.state.tenpai_wait_reveals.is_empty())
	var next_hand := BattleController.new(347, 0, false, TileId.E, 1)
	assert_eq(next_hand.state.tenpai_flags, [false, false, false, false])
	assert_true(next_hand.state.tenpai_wait_reveals.is_empty())


func test_zero_repeat_leave_reenter_and_multi_wait_use_real_discards() -> void:
	var bc := BattleController.new(346, 0, false, TileId.E, 0)
	_bind_ji_shu_slot(bc, 0)
	assert_true(_apply_discard_hand(bc, 1, _non_tenpai_plus_discard_hand(), 1).accepted)
	assert_false(bc.state.tenpai_flags[1])
	assert_true(_events_of_type(bc, &"TENPAI_ENTERED").is_empty())
	assert_true(_apply_discard_hand(bc, 1, _tenpai_plus_discard_hand(), 2).accepted)
	assert_eq(_events_of_type(bc, &"TENPAI_ENTERED").size(), 1)
	assert_true(_apply_discard_hand(bc, 1, _tenpai_plus_discard_hand(), 3).accepted)
	assert_eq(_events_of_type(bc, &"TENPAI_ENTERED").size(), 1,
		"持续听牌不得重复刷屏")
	assert_true(_apply_discard_hand(bc, 1, _non_tenpai_plus_discard_hand(), 4).accepted)
	assert_false(bc.state.tenpai_flags[1])
	assert_true(bc.state.tenpai_wait_reveals.is_empty())
	assert_true(_apply_discard_hand(bc, 1, _multi_wait_plus_discard_hand(), 5).accepted)
	assert_eq(_events_of_type(bc, &"TENPAI_ENTERED").size(), 2,
		"脱离后再次进入必须重新触发")
	assert_gt((bc.state.tenpai_wait_reveals[0][1] as Array).size(), 1,
		"多面听必须投影完整等待牌集合")


func test_different_owner_and_target_seats_keep_recipient_private() -> void:
	var bc := BattleController.new(346, 0, false, TileId.E, 0)
	_bind_ji_shu_slot(bc, 2)
	assert_true(_apply_discard_hand(bc, 3, _tenpai_plus_discard_hand(), 6).accepted)
	assert_eq(bc.state.tenpai_wait_reveals, {2: {3: [TileId.S_WIND]}})


func test_real_riichi_discard_emits_single_tenpai_transition() -> void:
	var bc := BattleController.new(346, 0, false, TileId.E, 0)
	_bind_ji_shu_slot(bc, 2)
	bc.state.current_seat = 1
	bc.state.phase = BattlePhase.Kind.DISCARD
	bc._invalidate_window()
	bc.state.seats[1].hand = _tenpai_plus_discard_hand()
	var context := bc.decision_context_for_seat(1)
	var riichi_iid := -1
	for offer_value in context.allowed_actions:
		var offer := offer_value as Dictionary
		if str(offer.get("kind", "")) == "RIICHI":
			var options := offer.get("payload_options", []) as Array
			if not options.is_empty():
				riichi_iid = int((options[0] as Dictionary).get("tile_instance_id", -1))
	assert_gt(riichi_iid, -1, "夹具必须提供真实立直弃牌")
	var applied := bc.apply_action(Action.riichi(
		1, riichi_iid, "local", "550e8400-e29b-41d4-a716-000000000370",
		context.decision_id, 0, 7), ActionSource.HUMAN)
	assert_true(applied.accepted, String(applied.error_code))
	assert_eq(_events_of_type(bc, &"TENPAI_ENTERED").size(), 1)
	assert_eq(bc.state.tenpai_wait_reveals.keys(), [2])


func test_real_ankan_recomputes_stable_thirteen_tile_shape() -> void:
	var bc := BattleController.new(346, 0, false, TileId.E, 0)
	_bind_ji_shu_slot(bc, 2)
	bc.state.current_seat = 1
	bc.state.phase = BattlePhase.Kind.DISCARD
	bc._invalidate_window()
	bc.state.seats[1].hand = _hand_from_ids([
		TileId.W1, TileId.W1, TileId.W1, TileId.W1,
		TileId.T1, TileId.T2, TileId.T3,
		TileId.S1, TileId.S2, TileId.S3,
		TileId.E, TileId.E, TileId.E,
		TileId.S_WIND,
	])
	bc.state.seats[1].last_drawn_instance_id = 0
	var context := bc.decision_context_for_seat(1)
	var payload: Dictionary = {}
	for offer_value in context.allowed_actions:
		var offer := offer_value as Dictionary
		if str(offer.get("kind", "")) != "KAN":
			continue
		for option_value in offer.get("payload_options", []) as Array:
			var option := option_value as Dictionary
			if str(option.get("kan_kind", "")) == "ANKAN":
				payload = option
	assert_false(payload.is_empty(), "夹具必须提供真实暗杠")
	var applied := bc.apply_action(Action.kan(
		1, payload, "local", "550e8400-e29b-41d4-a716-000000000371",
		context.decision_id, 0, 8), ActionSource.HUMAN)
	assert_true(applied.accepted, String(applied.error_code))
	assert_eq(_events_of_type(bc, &"TENPAI_ENTERED").size(), 1)
	assert_eq(bc.state.tenpai_wait_reveals, {2: {1: [TileId.S_WIND]}})


func test_real_chi_pon_and_minkan_paths_update_authoritative_tenpai() -> void:
	var cases := [
		{
			"kind": "CHI", "claimant": 1, "discarded": TileId.W3,
			"hand": [
				TileId.W1, TileId.W2,
				TileId.T1, TileId.T2, TileId.T3,
				TileId.S1, TileId.S2, TileId.S3,
				TileId.W4, TileId.W5, TileId.W6,
				TileId.E, TileId.N,
			],
		},
		{
			"kind": "PON", "claimant": 2, "discarded": TileId.HAKU,
			"hand": [
				TileId.HAKU, TileId.HAKU,
				TileId.T1, TileId.T2, TileId.T3,
				TileId.S1, TileId.S2, TileId.S3,
				TileId.W4, TileId.W5, TileId.W6,
				TileId.E, TileId.N,
			],
		},
		{
			"kind": "KAN", "claimant": 3, "discarded": TileId.HATSU,
			"hand": [
				TileId.HATSU, TileId.HATSU, TileId.HATSU,
				TileId.T1, TileId.T2, TileId.T3,
				TileId.S1, TileId.S2, TileId.S3,
				TileId.W4, TileId.W5, TileId.W6,
				TileId.E,
			],
		},
	]
	for index in range(cases.size()):
		var fixture := cases[index] as Dictionary
		var bc := BattleController.new(346 + index, 0, false, TileId.E, 0)
		_bind_ji_shu_slot(bc, 0)
		_apply_open_claim(
			bc, fixture.kind, int(fixture.claimant), int(fixture.discarded),
			fixture.hand, 20 + index)
		var claimant := int(fixture.claimant)
		var discard := bc.state.seats[claimant].hand.tiles()[-1] as Tile
		bc.state.seats[claimant].last_drawn_instance_id = discard.instance_id
		var context := bc.decision_context_for_seat(claimant)
		assert_not_null(context)
		assert_true(bc.apply_action(Action.discard(
			claimant, discard.instance_id, "local",
			"550e8400-e29b-41d4-a716-%012d" % (410 + index),
			context.decision_id, 0, 40 + index), ActionSource.HUMAN).accepted)
		assert_true(bc.state.tenpai_flags[int(fixture.claimant)],
			"%s 真实链必须更新权威听牌" % fixture.kind)
		assert_eq(_events_of_type(bc, &"TENPAI_ENTERED").size(), 1)
		assert_true(bc.state.tenpai_wait_reveals.has(0))
		if bc.state.tenpai_wait_reveals.has(0):
			assert_true((bc.state.tenpai_wait_reveals[0] as Dictionary).has(fixture.claimant))
