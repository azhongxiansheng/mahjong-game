extends GutTest

# 日麻 §3.2 三家和了 — 三条实际 RON intent 才 sancha（E2-02 第二轮）


func _build_w5_tanki_hand(extra_a: int, extra_b: int, extra_c: int, start_serial: int) -> Hand:
	var h := Hand.new()
	var serial := start_serial
	for tid in [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4,
		extra_a, extra_b, extra_c, TileId.W5,
	]:
		h.add(Tile.new(tid, false, Tile.NO_OWNER, serial))
		serial += 1
	return h


func _setup_three_w5_tenpai() -> BattleController:
	var bc := BattleController.new(42, 0, false, TileId.E)
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.CLAIM
	var discarded := Tile.new(TileId.W5, false, Tile.NO_OWNER, 50)
	bc._last_discarded_tile = discarded
	bc._last_discarder_seat = 0
	bc.state.seats[0].river.restore([discarded])
	bc.state.seats[1].hand = _build_w5_tanki_hand(TileId.S5, TileId.S6, TileId.S7, 10)
	bc.state.seats[2].hand = _build_w5_tanki_hand(TileId.S6, TileId.S7, TileId.S8, 30)
	bc.state.seats[3].hand = _build_w5_tanki_hand(TileId.T5, TileId.T6, TileId.T7, 50)
	for s in [1, 2, 3]:
		bc.state.seats[s].furiten = FuritenState.new()
	return bc


func test_three_actual_ron_intents_abortive_sancha() -> void:
	var bc := _setup_three_w5_tenpai()
	for s in [1, 2, 3]:
		var ctx: DecisionContext = bc.decision_context_for_seat(s)
		assert_not_null(ctx)
		assert_true(ctx.has_kind("RON"), "seat%d 应可 RON" % s)
		var act := Action.ron(s, "local", "550e8400-e29b-41d4-a716-00000000000%d" % s,
			ctx.decision_id, 0, s)
		assert_true(bc.apply_action(act, ActionSource.HUMAN).accepted)
	assert_true(bc._settled)
	var last: BattleEvent = bc.events[bc.events.size() - 1]
	assert_eq(last.type, &"ABORTIVE_DRAW")
	assert_eq(String(last.extra.get("reason", "")), "sancha_houra")


func test_two_ron_one_pass_not_sancha() -> void:
	var bc := _setup_three_w5_tenpai()
	for s in [1, 2, 3]:
		var ctx: DecisionContext = bc.decision_context_for_seat(s)
		var act: Action
		if s == 3:
			act = Action.make_pass(s, "local", "550e8400-e29b-41d4-a716-00000000001%d" % s,
				ctx.decision_id, 0, s)
		else:
			act = Action.ron(s, "local", "550e8400-e29b-41d4-a716-00000000001%d" % s,
				ctx.decision_id, 0, s)
		assert_true(bc.apply_action(act, ActionSource.HUMAN).accepted)
	for ev in bc.events:
		assert_ne(String(ev.extra.get("reason", "")), "sancha_houra")
	var wins := 0
	for ev in bc.events:
		if ev.type == &"WIN_DECLARED":
			wins += 1
	assert_eq(wins, 1, "两家 RON 头跳一家")


func test_zero_ron_no_abortive() -> void:
	var bc := BattleController.new(42, 0, false, TileId.E)
	for s in bc.state.seats:
		assert_true(s.hand.restore_tiles([]))
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.CLAIM
	var discarded := Tile.new(TileId.W5, false, Tile.NO_OWNER, 50)
	bc._last_discarded_tile = discarded
	bc._last_discarder_seat = 0
	bc.state.seats[0].river.restore([discarded])
	for s in [1, 2, 3]:
		var ctx: DecisionContext = bc.decision_context_for_seat(s)
		assert_not_null(ctx)
		assert_true(bc.apply_action(Action.make_pass(
			s, "local", "550e8400-e29b-41d4-a716-00000000002%d" % s,
			ctx.decision_id, 0, s
		), ActionSource.HUMAN).accepted)
	assert_false(bc._settled)
	for ev in bc.events:
		assert_ne(ev.type, &"ABORTIVE_DRAW")
