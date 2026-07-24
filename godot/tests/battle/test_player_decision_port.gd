extends GutTest

# PlayerDecisionPort / 脚本化 choice 契约（E2-02 / #232）。
# 动作 choice 使用 tile_instance_id；无 tile_id fallback。


class FakeDecisionPort extends PlayerDecisionPort:
	var requests: Array[Dictionary] = []
	var presentations: Array[Dictionary] = []
	var queued_choices: Array[Dictionary] = []

	func request(kind: StringName, context: Dictionary = {}) -> Dictionary:
		requests.append({"kind": kind, "context": context.duplicate(true)})
		if queued_choices.is_empty():
			return {}
		return queued_choices.pop_front()

	func present(state_name: StringName, context: Dictionary = {}) -> void:
		presentations.append({"state": state_name, "context": context.duplicate(true)})


func _first_hand_tile(seat: Seat) -> Tile:
	assert_gt(seat.hand._tiles.size(), 0)
	return seat.hand._tiles[0]


func _seed_riichi_turn(bc: PlayableBattleController) -> int:
	var drawn: Tile = bc.engine.draw_for_current()
	assert_not_null(drawn)
	var seat: Seat = bc.state.seats[0]
	var ids: Array = [
		TileId.W2, TileId.W4,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.S5, TileId.S5,
		TileId.W3,
	]
	assert_eq(seat.hand._tiles.size(), ids.size())
	for i in range(ids.size()):
		var tile: Tile = seat.hand._tiles[i]
		tile.id = ids[i]
		tile.is_red_dora = false
	var discard: Tile = seat.hand._tiles[-1]
	assert_eq(discard.id, TileId.W3)
	return discard.instance_id


func test_controller_selects_discard_action_from_decision_port() -> void:
	var bc := PlayableBattleController.new(42, 0, false)
	bc.set_ai_think_delay(0.0)
	var port := FakeDecisionPort.new()
	bc.bind_decision_port(port)
	# 进入 TURN
	assert_eq(bc.state.phase, BattlePhase.Kind.DRAW)
	var drawn: Tile = bc.engine.draw_for_current()
	assert_not_null(drawn)
	assert_eq(bc.state.phase, BattlePhase.Kind.DISCARD)
	var seat: Seat = bc.state.seats[0]
	var expected: Tile = _first_hand_tile(seat)
	assert_true(Tile.is_valid_instance_id(expected.instance_id))
	port.queued_choices.append({
		"action": "discard",
		"tile_instance_id": expected.instance_id,
	})
	var act: Action = await bc._select_turn_action_async(seat, 0)
	assert_not_null(act)
	assert_eq(act.kind, "DISCARD")
	assert_eq(int(act.payload.get("tile_instance_id", -1)), expected.instance_id,
		"按 instance_id 精确选 Action")
	assert_eq(port.requests.size(), 1)
	assert_eq(port.requests[0].kind, &"discard")
	assert_true(port.presentations.any(func(item): return item.state == &"idle"))


func test_scripted_choice_schema_rejects_tile_id_only_discard() -> void:
	var bc := PlayableBattleController.new(7, 0, false)
	bc.set_ai_think_delay(0.0)
	var port := FakeDecisionPort.new()
	bc.bind_decision_port(port)
	var drawn: Tile = bc.engine.draw_for_current()
	assert_not_null(drawn)
	var seat: Seat = bc.state.seats[0]
	var t: Tile = _first_hand_tile(seat)
	port.queued_choices.append({"action": "discard", "tile_id": t.id})
	port.queued_choices.append({
		"action": "discard",
		"tile_instance_id": t.instance_id,
	})
	var act: Action = await bc._select_turn_action_async(seat, 0)
	assert_not_null(act)
	assert_eq(act.kind, "DISCARD")
	assert_eq(int(act.payload.get("tile_instance_id", -1)), t.instance_id)
	assert_gte(port.requests.size(), 2,
		"仅 tile_id 的 discard choice 不得直接提交，须再请求")


func test_player_accepts_riichi_offer_from_fourteen_tile_decision_context() -> void:
	var bc := PlayableBattleController.new(42, 0, false)
	bc.set_ai_think_delay(0.0)
	var port := FakeDecisionPort.new()
	bc.bind_decision_port(port)
	var discard_iid: int = _seed_riichi_turn(bc)
	var seat: Seat = bc.state.seats[0]
	var ctx: DecisionContext = bc.decision_context_for_seat(0)
	assert_not_null(ctx)
	assert_true(ctx.allows("RIICHI", {"tile_instance_id": discard_iid}),
		"14 张权威窗口应允许切 W3 立直")
	port.queued_choices.append({
		"action": "discard",
		"tile_instance_id": discard_iid,
	})
	port.queued_choices.append({"action": "riichi_yes"})

	var act: Action = await bc._select_turn_action_async(seat, 0)

	assert_not_null(act)
	assert_eq(act.kind, "RIICHI",
		"已冻结的 DecisionContext 允许立直时，不得再用 13 张接口二次拒绝")
	assert_eq(int(act.payload.get("tile_instance_id", -1)), discard_iid)
	assert_eq(port.requests.size(), 2)
	assert_eq(port.requests[1].kind, &"riichi")
	var applied: ActionResolution = bc.apply_action(act, ActionSource.HUMAN)
	assert_true(applied.accepted)
	assert_gt(applied.events.size(), 0)
	if not applied.events.is_empty():
		assert_eq((applied.events[0] as BattleEvent).type, &"ACTION_APPLIED",
			"所有 accepted Action 的事件段必须先确认 ACTION_APPLIED，再发布领域事件")


func test_claim_companions_context_documents_instance_id_fields() -> void:
	var port := FakeDecisionPort.new()
	port.queued_choices.append({
		"action": "claim_tile_pick",
		"tile_instance_id": 42,
	})
	var ctx := {
		"claim_kind": "CHI",
		"options": [[40, 41], [41, 43]],
		"discarded_tile_id": TileId.W3,
		"selected_tile_instance_ids": [],
		"allowed_tile_instance_ids": [40, 41, 43],
	}
	var choice: Dictionary = await port.request(&"claim_companions", ctx)
	assert_eq(port.requests[0].kind, &"claim_companions")
	assert_true(port.requests[0].context.has("allowed_tile_instance_ids"))
	assert_false(port.requests[0].context.has("allowed_tile_ids"),
		"不保留 allowed_tile_ids 兼容")
	assert_eq(int(choice.get("tile_instance_id", -1)), 42)
	assert_false(choice.has("tile_id"))


func _claim_context(kind: String, options: Array) -> DecisionContext:
	var payload_options: Array = []
	for ids in options:
		payload_options.append({"companion_tile_instance_ids": ids.duplicate()})
	return DecisionContext.make(
		DecisionContext.KIND_CLAIM,
		0,
		"550e8400-e29b-41d4-a716-446655440000",
		0,
		[
			{"kind": kind, "payload_options": payload_options},
			{"kind": "PASS", "payload_options": [{}]},
		],
		90,
		3
	)


func test_multi_pon_selects_two_physical_entities_sequentially() -> void:
	var bc := PlayableBattleController.new(42, 0, false)
	var port := FakeDecisionPort.new()
	port.queued_choices.append({"action": "claim_tile_pick", "tile_instance_id": 51})
	port.queued_choices.append({"action": "claim_tile_pick", "tile_instance_id": 52})
	bc.bind_decision_port(port)
	var ctx: DecisionContext = _claim_context("PON", [
		[50, 51], [50, 52], [51, 52],
	])
	assert_not_null(ctx)
	var picked: Array = await bc._pick_claim_companion_iids(
		ctx, "PON", Tile.new(TileId.W5, false, 3, 90)
	)
	assert_eq(picked, [51, 52])
	assert_eq(port.requests.size(), 2)
	assert_eq(port.requests[0].kind, &"claim_companions")
	assert_eq(port.requests[0].context["claim_kind"], "PON")
	assert_eq(port.requests[0].context["selected_tile_instance_ids"], [])
	assert_eq(port.requests[0].context["allowed_tile_instance_ids"], [50, 51, 52])
	assert_eq(port.requests[1].context["selected_tile_instance_ids"], [51])
	assert_eq(port.requests[1].context["allowed_tile_instance_ids"], [50, 52],
		"第一张实体牌须收窄第二张候选")
	assert_true(port.presentations.any(func(item):
		return item.state == &"clear_hand_selection"),
		"实体选择成功后必须清理 clickable/dim 状态")


func test_multi_chi_first_pick_narrows_second_entity_candidates() -> void:
	var bc := PlayableBattleController.new(42, 0, false)
	var port := FakeDecisionPort.new()
	port.queued_choices.append({"action": "claim_tile_pick", "tile_instance_id": 41})
	port.queued_choices.append({"action": "claim_tile_pick", "tile_instance_id": 43})
	bc.bind_decision_port(port)
	var ctx: DecisionContext = _claim_context("CHI", [
		[40, 41], [41, 43], [42, 43],
	])
	assert_not_null(ctx)
	var picked: Array = await bc._pick_claim_companion_iids(
		ctx, "CHI", Tile.new(TileId.W3, false, 3, 90)
	)
	assert_eq(picked, [41, 43])
	assert_eq(port.requests.size(), 2)
	assert_eq(port.requests[1].context["allowed_tile_instance_ids"], [40, 43])


func test_unique_claim_companion_combination_submits_without_picker() -> void:
	var bc := PlayableBattleController.new(42, 0, false)
	var port := FakeDecisionPort.new()
	bc.bind_decision_port(port)
	var ctx: DecisionContext = _claim_context("CHI", [[40, 41]])
	assert_not_null(ctx)
	var picked: Array = await bc._pick_claim_companion_iids(
		ctx, "CHI", Tile.new(TileId.W3, false, 3, 90)
	)
	assert_eq(picked, [40, 41])
	assert_true(port.requests.is_empty(), "唯一物理组合须直接提交，不打开选择 UI")


func test_multi_claim_skip_clears_physical_entity_selection() -> void:
	var bc := PlayableBattleController.new(42, 0, false)
	var port := FakeDecisionPort.new()
	port.queued_choices.append({"action": "skip"})
	bc.bind_decision_port(port)
	var ctx: DecisionContext = _claim_context("CHI", [[40, 41], [41, 43]])
	assert_not_null(ctx)
	var picked: Array = await bc._pick_claim_companion_iids(
		ctx, "CHI", Tile.new(TileId.W3, false, 3, 90)
	)
	assert_true(picked.is_empty())
	assert_true(port.presentations.any(func(item):
		return item.state == &"clear_hand_selection"),
		"跳过取消实体选择后必须清理 clickable/dim 状态")
