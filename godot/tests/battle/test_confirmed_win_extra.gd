extends GutTest

# 公开 bundle 的和牌演出只消费最终确认态。走 Action.ron / Action.tsumo。


func _make_t1_tanki_hand(include_winning_tile: bool, start_serial: int = 0) -> Hand:
	var hand := Hand.new()
	var serial := start_serial
	var ids: Array = [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.T1,
	]
	if include_winning_tile:
		ids.append(TileId.T1)
	for tile_id in ids:
		hand.add(Tile.new(tile_id, false, Tile.NO_OWNER, serial))
		serial += 1
	return hand


func _last_win_event(bc: BattleController) -> BattleEvent:
	for index in range(bc.events.size() - 1, -1, -1):
		var event: BattleEvent = bc.events[index]
		if event.type == &"WIN_DECLARED":
			return event
	return null


func test_chankan_ron_action_reaches_confirmed_win_extra() -> void:
	var bc := BattleController.new(42, 0, false, TileId.E)
	bc.state.seats[1].hand = _make_t1_tanki_hand(false, 10)
	bc.state.seats[1].furiten = FuritenState.new()
	# 杠家 seat0 宣告 ADDED_KAN T1
	bc.state.seats[0].hand = Hand.new()
	var added := Tile.new(TileId.T1, false, Tile.NO_OWNER, 100)
	bc.state.seats[0].hand.add(added)
	for tid in [
		TileId.W2, TileId.W3, TileId.W4, TileId.S2, TileId.S3, TileId.S4,
		TileId.W7, TileId.W8, TileId.W9, TileId.E, TileId.E, TileId.S_WIND,
	]:
		bc.state.seats[0].hand.add(Tile.new(tid, false, Tile.NO_OWNER, 101 + bc.state.seats[0].hand.size()))
	var pon := Meld.make_pon([
		Tile.new(TileId.T1, false, 0, 1),
		Tile.new(TileId.T1, false, 0, 2),
		Tile.new(TileId.T1, false, 0, 3),
	], 2, 0)
	bc.state.seats[0].melds.restore([pon], 1)
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.DISCARD
	bc.state.seats[0].last_drawn_instance_id = added.instance_id
	var ctx: DecisionContext = bc.decision_context_for_seat(0)
	assert_not_null(ctx)
	var pay: Dictionary = {}
	for offer in ctx.allowed_actions:
		if str(offer.get("kind", "")) != "KAN":
			continue
		for opt in offer.get("payload_options", []):
			if str(opt.get("kan_kind", "")) == "ADDED_KAN":
				pay = opt
	assert_false(pay.is_empty(), "应 offer ADDED_KAN")
	assert_true(bc.apply_action(Action.kan(
		0, pay, "local", "550e8400-e29b-41d4-a716-000000000001",
		ctx.decision_id, 0, 1
	), ActionSource.HUMAN).accepted)
	# 对家 1 RON，2/3 PASS
	for s in [1, 2, 3]:
		var rctx: DecisionContext = bc.decision_context_for_seat(s)
		assert_not_null(rctx)
		var a: Action
		if s == 1:
			assert_true(rctx.has_kind("RON"))
			a = Action.ron(1, "local", "550e8400-e29b-41d4-a716-00000000001%d" % s,
				rctx.decision_id, 0, s + 1)
		else:
			a = Action.make_pass(s, "local", "550e8400-e29b-41d4-a716-00000000001%d" % s,
				rctx.decision_id, 0, s + 1)
		assert_true(bc.apply_action(a, ActionSource.HUMAN).accepted)
	var win_event := _last_win_event(bc)
	assert_not_null(win_event, "确认成功后必须发 WIN_DECLARED")
	assert_false(bool(win_event.extra.get("is_tsumo", true)))
	assert_true(bool(win_event.extra.get("is_chankan", false)),
		"抢杠 RON 必须把 is_chankan 传到最终确认事件")
	assert_true(win_event.extra.has("dora_count"),
		"RON 确认事件必须公开权威 Dora 总数")
	assert_eq(int(win_event.extra.get("ability_extra_dora_count", -1)), 0,
		"无角色能力时 RON 的能力 Dora 归因必须显式为 0")


func test_tsumo_action_confirmed_win_extra_is_explicit() -> void:
	var bc := BattleController.new(42, 0, false, TileId.E)
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.DISCARD
	bc.state.seats[0].hand = _make_t1_tanki_hand(true, 0)
	var drawn: Tile = bc.state.seats[0].hand.tiles()[bc.state.seats[0].hand.tiles().size() - 1]
	bc.state.seats[0].last_drawn_instance_id = drawn.instance_id
	var checked: Dictionary = bc._check_tsumo(drawn)
	assert_true(bool(checked.get("is_winning", false)), "测试手牌必须真实自摸成立")
	var ctx: DecisionContext = bc.decision_context_for_seat(0)
	assert_not_null(ctx)
	assert_true(ctx.has_kind("TSUMO"))
	assert_true(bc.apply_action(Action.tsumo(
		0, "local", "550e8400-e29b-41d4-a716-000000000099",
		ctx.decision_id, 0, 1
	), ActionSource.HUMAN).accepted)
	var win_event := _last_win_event(bc)
	assert_not_null(win_event)
	assert_true(bool(win_event.extra.get("is_tsumo", false)))
	assert_false(bool(win_event.extra.get("is_chankan", true)))
	assert_true(win_event.extra.has("dora_count"),
		"TSUMO 确认事件必须公开权威 Dora 总数")
	assert_eq(int(win_event.extra.get("ability_extra_dora_count", -1)), 0,
		"无角色能力时 TSUMO 的能力 Dora 归因必须显式为 0")
