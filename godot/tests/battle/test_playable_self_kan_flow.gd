extends GutTest

# 玩家自杠（暗杠/加杠）— context → Action → apply_action（E2-02 第二轮）

const SCRIPTED_DECISION_PORT := preload("res://tests/_fixtures/scripted_decision_port.gd")

var _bc: PlayableBattleController
var _port


func before_each() -> void:
	_bc = PlayableBattleController.new(42, 0, false)
	_bc.set_ai_think_delay(0.0)
	_port = SCRIPTED_DECISION_PORT.new()
	_bc.bind_decision_port(_port, get_tree())


func _set_hand(seat: Seat, ids: Array, start_serial: int = 10) -> void:
	# hand_seq=0 命名空间 serial 仅 0..135
	var tiles: Array[Tile] = []
	var serial: int = start_serial
	for id in ids:
		assert_true(serial <= 135, "fixture serial 必须落在 hand_seq 命名空间")
		tiles.append(Tile.new(id, false, 0, serial))
		serial += 1
	assert_true(seat.hand.restore_tiles(tiles))


func test_player_ankan_via_turn_action_does_not_end_hand() -> void:
	var seat: Seat = _bc.state.seats[0]
	_set_hand(seat, [
		TileId.W1, TileId.W1, TileId.W1, TileId.W1,
		TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N,
		TileId.HAKU, TileId.HATSU, TileId.CHUN,
		TileId.T1, TileId.T9, TileId.S1,
	])
	_bc.state.current_seat = 0
	_bc.state.phase = BattlePhase.Kind.DISCARD
	seat.last_drawn_instance_id = seat.hand.tiles()[0].instance_id
	var ctx: DecisionContext = _bc.decision_context_for_seat(0)
	assert_not_null(ctx)
	assert_true(ctx.has_kind("KAN"))
	var pay: Dictionary = {}
	for offer in ctx.allowed_actions:
		if str(offer.get("kind", "")) != "KAN":
			continue
		for opt in offer.get("payload_options", []):
			if str(opt.get("kan_kind", "")) == "ANKAN":
				pay = opt
	assert_false(pay.is_empty())
	var act := Action.kan(
		0, pay, "local", "550e8400-e29b-41d4-a716-000000000001",
		ctx.decision_id, 0, 1
	)
	var resp: ActionResolution = _bc.apply_action(act, ActionSource.HUMAN)
	assert_true(resp.accepted)
	assert_eq(seat.melds.size(), 1)
	assert_eq(seat.melds.all()[0].kind, Meld.Kind.ANKAN)
	assert_eq(seat.melds.all()[0].tiles.size(), 4)
	assert_false(_bc._settled, "暗杠后本局不应结束")
	assert_eq(_bc.action_journal().size(), 1)



func test_player_added_kan_two_phase_via_action() -> void:
	var seat: Seat = _bc.state.seats[0]
	_set_hand(seat, [
		TileId.W5,
		TileId.T1, TileId.T2, TileId.T3,
		TileId.S1, TileId.S2, TileId.S3,
		TileId.W7, TileId.W8, TileId.W9,
		TileId.E, TileId.E, TileId.S_WIND, TileId.W_WIND,
	], 20)
	var pon := Meld.make_pon([
		Tile.new(TileId.W5, false, 0, 1),
		Tile.new(TileId.W5, false, 0, 2),
		Tile.new(TileId.W5, false, 0, 3),
	], 1, 0)
	seat.melds.restore([pon], 1)
	_bc.state.current_seat = 0
	_bc.state.phase = BattlePhase.Kind.DISCARD
	seat.last_drawn_instance_id = seat.hand.tiles()[0].instance_id
	var ctx: DecisionContext = _bc.decision_context_for_seat(0)
	var pay: Dictionary = {}
	for offer in ctx.allowed_actions:
		if str(offer.get("kind", "")) != "KAN":
			continue
		for opt in offer.get("payload_options", []):
			if str(opt.get("kan_kind", "")) == "ADDED_KAN":
				pay = opt
	assert_false(pay.is_empty())
	assert_eq(int(pay.get("meld_id", -1)), pon.meld_id)
	var added_iid: int = int(pay.get("added_tile_instance_id", -1))
	assert_eq(added_iid, seat.hand.tiles()[0].instance_id)
	assert_true(_bc.apply_action(Action.kan(
		0, pay, "local", "550e8400-e29b-41d4-a716-000000000002",
		ctx.decision_id, 0, 1
	), ActionSource.HUMAN).accepted)
	# ROB 前 domain 零升级
	assert_eq(seat.melds.all()[0].kind, Meld.Kind.PON)
	assert_not_null(seat.hand.find_by_instance_id(added_iid))
	# 全 PASS
	for s in [1, 2, 3]:
		var rctx: DecisionContext = _bc.decision_context_for_seat(s)
		assert_true(_bc.apply_action(Action.make_pass(
			s, "local", "550e8400-e29b-41d4-a716-00000000001%d" % s,
			rctx.decision_id, 0, s + 1
		), ActionSource.HUMAN).accepted)
	assert_eq(seat.melds.all()[0].kind, Meld.Kind.ADDED_KAN, "全 PASS 后升级")
	assert_eq(seat.melds.all()[0].added_tile_instance_id, added_iid)


func test_async_turn_player_ankan_scripted() -> void:
	var seat: Seat = _bc.state.seats[0]
	_set_hand(seat, [
		TileId.W1, TileId.W1, TileId.W1, TileId.W1,
		TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N,
		TileId.HAKU, TileId.HATSU, TileId.CHUN,
		TileId.T1, TileId.T9, TileId.S1,
	])
	_bc.state.current_seat = 0
	_bc.state.phase = BattlePhase.Kind.DISCARD
	seat.last_drawn_instance_id = seat.hand.tiles()[0].instance_id
	var done := {}
	var runner := func():
		await _bc._step_turn_async()
		done["finished"] = true
	runner.call()
	_port.submit({"action": "ankan"})
	await wait_physics_frames(3)
	assert_eq(seat.melds.size(), 1, "暗杠 meld 应成立")
	assert_eq(seat.melds.all()[0].kind, Meld.Kind.ANKAN)
	assert_false(_bc._settled)
	assert_true(done.has("finished"), "TURN 步在 Action 接受后完成")


func test_discard_choice_requires_tile_instance_id() -> void:
	var seat: Seat = _bc.state.seats[0]
	_set_hand(seat, [
		TileId.W2, TileId.W3, TileId.W4, TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4, TileId.E, TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N,
	])
	_bc.state.current_seat = 0
	_bc.state.phase = BattlePhase.Kind.DISCARD
	seat.last_drawn_instance_id = seat.hand.tiles()[0].instance_id
	var done := {}
	var runner := func():
		await _bc._step_turn_async()
		done["finished"] = true
	runner.call()
	# 只有 tile_id 无 instance → 应拒绝并继续等待
	_port.submit({"action": "discard", "tile_id": TileId.W2})
	await wait_physics_frames(2)
	assert_false(done.has("finished"), "tile_id fallback 已删除")
	var iid: int = seat.hand.tiles()[0].instance_id
	_port.submit({"action": "discard", "tile_instance_id": iid})
	await wait_physics_frames(3)
	assert_true(done.has("finished"))
	assert_eq(_bc.state.seats[0].river.tiles()[0].instance_id, iid)
