extends GutTest

const COORDINATOR_PATH := "res://battle/seat_draw_forecast_coordinator.gd"
const TABLE_SCENE := preload("res://ui/four_player_table/four_player_table.tscn")
const ViewerRevealResolver := preload("res://battle/viewer_reveal_resolver.gd")
const FORECAST_PROJECTION_KIND := "viewer_seat_draw_forecast@1"


func _coordinator():
	assert_true(ResourceLoader.exists(COORDINATOR_PATH),
		"先示须提供独立四席预测协调器")
	if not ResourceLoader.exists(COORDINATOR_PATH):
		return null
	var script := load(COORDINATOR_PATH) as GDScript
	assert_not_null(script)
	return script


func _activate(seed: int, dealer: int, viewer: int, hand_seq: int = 0) -> Dictionary:
	var bc := BattleController.new(seed, dealer, false, TileId.E, hand_seq)
	assert_true(BossAbilityFactory.inject(
		bc.registry, &"char_toki_passive_v1", viewer))
	var ctx := bc.scheduler.emit_event(BattleEvent.make(&"GAME_BEGIN", viewer))
	return {"bc": bc, "ctx": ctx}


func _predictions(coordinator, state: BattleState, viewer: int) -> Array:
	if coordinator == null:
		return []
	return coordinator.predictions_for_viewer(state, viewer)


func _prediction_for_target(predictions: Array, target: int) -> Dictionary:
	for prediction in predictions:
		if int((prediction as Dictionary).get("target_seat", -1)) == target:
			return prediction as Dictionary
	return {}


func _forecast_state_signature(
	coordinator, state: BattleState, viewer: int, skill: SkillResource
) -> String:
	var rows: Array = []
	for value in state.revealed_tiles:
		if not coordinator.is_forecast_record(value):
			continue
		var record := value as Dictionary
		var visible_to := record.get("visible_to", []) as Array
		if not visible_to.has(viewer):
			continue
		var anchor := record.get("tile", null) as TileSkillAnchor
		rows.append({
			"target_seat": anchor.owner_seat if anchor != null else -1,
			"instance_id": anchor.tile.instance_id if anchor != null else -1,
			"anchor_object_id": anchor.get_instance_id() if anchor != null else 0,
			"visible_to": visible_to.duplicate(),
			"projection_kind": str(record.get("projection_kind", "")),
		})
	return JSON.stringify({
		"active": bool(skill.params.get("seat_draw_forecast_active", false)),
		"hand_seq": int(skill.params.get("seat_draw_forecast_hand_seq", -1)),
		"viewer": int(skill.params.get("seat_draw_forecast_viewer", -1)),
		"pending": (skill.params.get("seat_draw_forecast_pending", []) as Array).duplicate(),
		"records": rows,
		"revealed_count": state.revealed_tiles.size(),
	})


func _set_claim_fixture(bc: BattleController, copies: int) -> void:
	var claimant := bc.state.seats[2] as Seat
	var tiles: Array[Tile] = []
	for index in range(copies):
		tiles.append(Tile.new(TileId.W5, false, 2, 80 + index))
	for index in range(13 - copies):
		tiles.append(Tile.new(TileId.T1 + (index % 9), false, 2, 90 + index))
	assert_true(claimant.hand.restore_tiles(tiles))
	var discarded := Tile.new(TileId.W5, false, 0, 70)
	bc.state.seats[0].river.restore([discarded])
	bc._last_discarded_tile = discarded
	bc._last_discarder_seat = 0
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.CLAIM
	bc._invalidate_window()


func _resolve_claim_as_seat2(bc: BattleController, kind: String) -> void:
	for seat in [1, 2, 3]:
		var context := bc.decision_context_for_seat(seat)
		assert_not_null(context)
		var action: Action = null
		if seat == 2:
			var payload: Dictionary = {}
			for offer in context.allowed_actions:
				if str((offer as Dictionary).get("kind", "")) == kind:
					payload = ((offer as Dictionary).get("payload_options", [{}]) as Array)[0]
					break
			assert_false(payload.is_empty())
			if kind == "PON":
				action = Action.pon(2, payload.get("companion_tile_instance_ids", []),
					"local", "550e8400-e29b-41d4-a716-00000000012%d" % seat,
					context.decision_id, bc.state.hand_seq, seat)
			else:
				action = Action.kan(2, payload, "local",
					"550e8400-e29b-41d4-a716-00000000012%d" % seat,
					context.decision_id, bc.state.hand_seq, seat)
		else:
			action = Action.make_pass(seat, "local",
				"550e8400-e29b-41d4-a716-00000000012%d" % seat,
				context.decision_id, bc.state.hand_seq, seat)
		assert_true(bc.apply_action(action, ActionSource.HUMAN).accepted)


func _set_chi_fixture_for_seat1(bc: BattleController) -> void:
	var claimant := bc.state.seats[1] as Seat
	var tiles: Array[Tile] = [
		Tile.new(TileId.W4, false, 1, 80),
		Tile.new(TileId.W6, false, 1, 81),
	]
	for index in range(11):
		tiles.append(Tile.new(TileId.T1 + (index % 9), false, 1, 90 + index))
	assert_true(claimant.hand.restore_tiles(tiles))
	var discarded := Tile.new(TileId.W5, false, 0, 70)
	bc.state.seats[0].river.restore([discarded])
	bc._last_discarded_tile = discarded
	bc._last_discarder_seat = 0
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.CLAIM
	bc._invalidate_window()


func _resolve_chi_as_seat1(bc: BattleController) -> void:
	for seat in [1, 2, 3]:
		var context := bc.decision_context_for_seat(seat)
		assert_not_null(context)
		var action: Action = null
		if seat == 1:
			var payload: Dictionary = {}
			for offer in context.allowed_actions:
				if str((offer as Dictionary).get("kind", "")) == "CHI":
					payload = ((offer as Dictionary).get(
						"payload_options", [{}]) as Array)[0]
					break
			assert_false(payload.is_empty())
			action = Action.chi(1, payload.get("companion_tile_instance_ids", []),
				"local", "550e8400-e29b-41d4-a716-00000000031%d" % seat,
				context.decision_id, bc.state.hand_seq, seat)
		else:
			action = Action.make_pass(seat, "local",
				"550e8400-e29b-41d4-a716-00000000031%d" % seat,
				context.decision_id, bc.state.hand_seq, seat)
		assert_true(bc.apply_action(action, ActionSource.HUMAN).accepted)


func test_four_seats_map_to_distinct_future_live_draws_for_nonzero_viewer() -> void:
	var activated := _activate(347, 2, 3, 7)
	var bc := activated.bc as BattleController
	var expected: Array[Tile] = bc.state.wall.peek_top_n(4)
	var coordinator = _coordinator()
	if coordinator == null:
		return
	var predictions := _predictions(coordinator, bc.state, 3)
	assert_eq(predictions.size(), 4)
	var expected_targets := [2, 3, 0, 1]
	var seen: Dictionary = {}
	for index in range(predictions.size()):
		var prediction := predictions[index] as Dictionary
		assert_eq(int(prediction.get("target_seat", -1)), expected_targets[index])
		var instance := prediction.get("tile", null) as TileSkillAnchor
		assert_not_null(instance)
		if instance != null:
			assert_eq(instance.tile.instance_id, expected[index].instance_id)
			assert_eq(instance.owner_seat, expected_targets[index])
			assert_eq(instance.holder_seat, -1)
			seen[instance.tile.instance_id] = true
	assert_eq(seen.size(), 4, "四席不得复制同一张墙顶牌")
	assert_true(_predictions(coordinator, bc.state, 0).is_empty(),
		"非能力拥有者不得看到任何四席预测")
	assert_eq((activated.ctx as SkillCtx).triggered_skills.size(), 1)


func test_duplicate_game_begin_does_not_retrigger_or_replace_predictions() -> void:
	var activated := _activate(348, 0, 1, 0)
	var bc := activated.bc as BattleController
	var coordinator = _coordinator()
	if coordinator == null:
		return
	var before := _predictions(coordinator, bc.state, 1)
	var ids_before: Array = []
	for prediction in before:
		ids_before.append(((prediction as Dictionary).tile as TileSkillAnchor).tile.instance_id)
	var repeated := bc.scheduler.emit_event(BattleEvent.make(&"GAME_BEGIN", 1))
	var after := _predictions(coordinator, bc.state, 1)
	var ids_after: Array = []
	for prediction in after:
		ids_after.append(((prediction as Dictionary).tile as TileSkillAnchor).tile.instance_id)
	assert_true(repeated.triggered_skills.is_empty(),
		"同局重复 GAME_BEGIN 不得二次触发能力/语音")
	assert_eq(ids_after, ids_before)


func test_real_draw_consumes_exact_target_instance_and_keeps_other_targets() -> void:
	var activated := _activate(349, 1, 2, 4)
	var bc := activated.bc as BattleController
	var coordinator = _coordinator()
	if coordinator == null:
		return
	var before := _predictions(coordinator, bc.state, 2)
	var dealer_prediction := before[0] as Dictionary
	var expected := dealer_prediction.tile as TileSkillAnchor
	assert_eq(int(dealer_prediction.target_seat), 1)
	assert_eq(bc.call("_step_draw"), true,
		"真实 _step_draw 调用链必须以预测 target + exact iid 命中消费")
	assert_eq(bc.state.seats[1].last_drawn_instance_id, expected.tile.instance_id)
	var after := _predictions(coordinator, bc.state, 2)
	assert_eq(after.size(), 3)
	for prediction in after:
		assert_ne(int((prediction as Dictionary).target_seat), 1,
			"已完成下一次实际摸牌的席位不得滚动补出下一巡预测")


func test_same_hand_wrong_instance_cannot_consume_or_recompute_prediction() -> void:
	var activated := _activate(360, 1, 2, 4)
	var bc := activated.bc as BattleController
	var coordinator = _coordinator()
	if coordinator == null:
		return
	var skill: SkillResource = null
	for entry in bc.registry.get_all_entries():
		if (entry.skill as SkillResource).id == &"char_toki_passive_v1":
			skill = entry.skill as SkillResource
			break
	assert_not_null(skill)
	if skill == null:
		return
	var before := _predictions(coordinator, bc.state, 2)
	assert_eq(before.size(), 4)
	var wrong_anchor := (before[1] as Dictionary).tile as TileSkillAnchor
	assert_true(Tile.is_instance_id_in_hand_seq(
		wrong_anchor.tile.instance_id, bc.state.hand_seq),
		"夹具错误 iid 必须属于同一 hand namespace")
	assert_ne(int((before[1] as Dictionary).target_seat), 1)
	var signature_before := _forecast_state_signature(
		coordinator, bc.state, 2, skill)
	assert_false(coordinator.consume_actual_draw(
		bc.state, bc.registry, 1, wrong_anchor.tile.instance_id),
		"同局合法但错误 iid 不得消费 target 预测")
	assert_eq(_forecast_state_signature(coordinator, bc.state, 2, skill),
		signature_before,
		"错误 iid 后 pending 与权威 forecast records 必须完全不变")


func test_cross_hand_instance_cannot_consume_target_prediction() -> void:
	var activated := _activate(357, 1, 2, 4)
	var bc := activated.bc as BattleController
	var coordinator = _coordinator()
	if coordinator == null:
		return
	var before := _predictions(coordinator, bc.state, 2)
	assert_eq(before.size(), 4)
	var foreign_iid := int(
		((before[0] as Dictionary).tile as TileSkillAnchor).tile.instance_id) + 136
	assert_false(coordinator.consume_actual_draw(
		bc.state, bc.registry, 1, foreign_iid),
		"跨局 instance_id 不得命中当前 hand_seq 的消费")
	var after := _predictions(coordinator, bc.state, 2)
	assert_eq(after.size(), 4)
	assert_false(_prediction_for_target(after, 1).is_empty(),
		"三元组校验失败时不得移除目标席预测")


func test_wall_shortage_omits_unavailable_targets_without_duplicates() -> void:
	var activated := _activate(350, 3, 1, 2)
	var bc := activated.bc as BattleController
	var remaining := bc.state.wall.live_end_index() - 2
	assert_true(bc.state.wall.set_draw_index(remaining))
	var skill: SkillResource = null
	for entry in bc.registry.get_all_entries():
		if (entry.skill as SkillResource).id == &"char_toki_passive_v1":
			skill = entry.skill as SkillResource
			break
	assert_not_null(skill)
	var coordinator = _coordinator()
	if coordinator == null or skill == null:
		return
	coordinator.recompute(bc.state, skill)
	var predictions := _predictions(coordinator, bc.state, 1)
	assert_eq(predictions.size(), 2)
	assert_eq(int((predictions[0] as Dictionary).target_seat), 3)
	assert_eq(int((predictions[1] as Dictionary).target_seat), 0)
	assert_ne(
		((predictions[0] as Dictionary).tile as TileSkillAnchor).tile.instance_id,
		((predictions[1] as Dictionary).tile as TileSkillAnchor).tile.instance_id)


func test_authority_restore_preserves_pending_targets_without_retrigger() -> void:
	var activated := _activate(351, 0, 2, 9)
	var source := activated.bc as BattleController
	var coordinator = _coordinator()
	if coordinator == null:
		return
	source._step_draw()
	var expected := _predictions(coordinator, source.state, 2)
	var snapshot := AuthorityReplaySnapshot.capture(source)
	assert_not_null(snapshot)
	assert_true(snapshot.can_restore())
	var restored := BattleController.new(999, 1, false, TileId.S_WIND, 9)
	assert_true(snapshot.restore_into(restored))
	var actual := _predictions(coordinator, restored.state, 2)
	assert_eq(actual.size(), expected.size())
	for index in range(actual.size()):
		assert_eq(int((actual[index] as Dictionary).target_seat),
			int((expected[index] as Dictionary).target_seat))
		assert_eq(
			((actual[index] as Dictionary).tile as TileSkillAnchor).tile.instance_id,
			((expected[index] as Dictionary).tile as TileSkillAnchor).tile.instance_id)
	assert_eq(restored.events.size(), source.events.size(),
		"恢复不得制造新的 SKILL_TRIGGERED")
	var next_hand := BattleController.new(352, 0, false, TileId.E, 10)
	assert_true(_predictions(coordinator, next_hand.state, 2).is_empty(),
		"跨局 hand_seq 不得继承预测")


func test_committed_pon_invalidates_old_route_and_recomputes_pending_targets() -> void:
	var activated := _activate(353, 0, 1, 0)
	var bc := activated.bc as BattleController
	var coordinator = _coordinator()
	if coordinator == null:
		return
	var old_target2 := _prediction_for_target(
		_predictions(coordinator, bc.state, 1), 2)
	var old_iid := (old_target2.tile as TileSkillAnchor).tile.instance_id
	_set_claim_fixture(bc, 2)
	_resolve_claim_as_seat2(bc, "PON")
	assert_eq(bc.state.current_seat, 2)
	assert_eq(bc.state.phase, BattlePhase.Kind.DISCARD)
	var refreshed := _predictions(coordinator, bc.state, 1)
	assert_eq(refreshed.size(), 4)
	var new_target2 := _prediction_for_target(refreshed, 2)
	assert_false(new_target2.is_empty())
	assert_ne((new_target2.tile as TileSkillAnchor).tile.instance_id, old_iid,
		"碰改变行动路径后不得保留旧 live-wall 席位绑定")


func test_committed_chi_invalidates_old_route_and_recomputes_pending_targets() -> void:
	var activated := _activate(358, 0, 3, 0)
	var bc := activated.bc as BattleController
	var coordinator = _coordinator()
	if coordinator == null:
		return
	var old_target1 := _prediction_for_target(
		_predictions(coordinator, bc.state, 3), 1)
	var old_iid := (old_target1.tile as TileSkillAnchor).tile.instance_id
	_set_chi_fixture_for_seat1(bc)
	_resolve_chi_as_seat1(bc)
	assert_eq(bc.state.current_seat, 1)
	assert_eq(bc.state.phase, BattlePhase.Kind.DISCARD)
	var refreshed := _predictions(coordinator, bc.state, 3)
	var new_target1 := _prediction_for_target(refreshed, 1)
	assert_false(new_target1.is_empty())
	assert_ne((new_target1.tile as TileSkillAnchor).tile.instance_id, old_iid,
		"吃改变行动路径后不得保留旧 live-wall 席位绑定")


func test_committed_minkan_consumes_claimant_by_rinshan_not_old_live_prediction() -> void:
	var activated := _activate(354, 0, 3, 0)
	var bc := activated.bc as BattleController
	var coordinator = _coordinator()
	if coordinator == null:
		return
	var old_target2 := _prediction_for_target(
		_predictions(coordinator, bc.state, 3), 2)
	var old_iid := (old_target2.tile as TileSkillAnchor).tile.instance_id
	_set_claim_fixture(bc, 3)
	_resolve_claim_as_seat2(bc, "KAN")
	var rinshan_iid := int((bc.state.seats[2] as Seat).last_drawn_instance_id)
	assert_ne(rinshan_iid, old_iid, "岭上实体不得冒充旧 live-wall 预测")
	var refreshed := _predictions(coordinator, bc.state, 3)
	assert_true(_prediction_for_target(refreshed, 2).is_empty(),
		"席位已完成下一次实际岭上摸牌后必须消费，不滚动补下一巡")
	assert_eq(refreshed.size(), 3)


func test_exhausted_wall_clears_all_pending_forecasts() -> void:
	var activated := _activate(355, 0, 2, 0)
	var bc := activated.bc as BattleController
	var coordinator = _coordinator()
	if coordinator == null:
		return
	assert_true(bc.state.wall.set_draw_index(bc.state.wall.live_end_index()))
	bc.state.phase = BattlePhase.Kind.DRAW
	bc._step_draw()
	assert_true(_predictions(coordinator, bc.state, 2).is_empty())
	for entry in bc.registry.get_all_entries():
		var skill := entry.skill as SkillResource
		if skill.id == &"char_toki_passive_v1":
			assert_false(bool(skill.params.get("seat_draw_forecast_active", true)),
				"墙耗尽须终止预测状态")


func test_added_kan_declaration_suspends_then_rinshan_consumes_actor() -> void:
	var activated := _activate(356, 0, 0, 0)
	var bc := activated.bc as BattleController
	var coordinator = _coordinator()
	if coordinator == null:
		return
	var ordinary_target := _prediction_for_target(
		_predictions(coordinator, bc.state, 0), 0)
	var ordinary_iid := (ordinary_target.tile as TileSkillAnchor).tile.instance_id
	bc._step_draw()
	assert_eq((bc.state.seats[0] as Seat).last_drawn_instance_id, ordinary_iid)
	assert_eq(_predictions(coordinator, bc.state, 0).size(), 3)
	assert_true(_prediction_for_target(
		_predictions(coordinator, bc.state, 0), 0).is_empty(),
		"actor 的本轮普通摸牌须先消费自身预测")
	var seat := bc.state.seats[0] as Seat
	var hand_tiles: Array[Tile] = [Tile.new(TileId.W5, false, 0, 20)]
	for index in range(13):
		hand_tiles.append(Tile.new(TileId.T1 + (index % 9), false, 0, 30 + index))
	assert_true(seat.hand.restore_tiles(hand_tiles))
	var pon := Meld.make_pon([
		Tile.new(TileId.W5, false, 0, 1),
		Tile.new(TileId.W5, false, 0, 2),
		Tile.new(TileId.W5, false, 0, 3),
	], 1, 0)
	assert_true(seat.melds.restore([pon], 1))
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.DISCARD
	seat.last_drawn_instance_id = 20
	var context := bc.decision_context_for_seat(0)
	var payload: Dictionary = {}
	for offer in context.allowed_actions:
		if str((offer as Dictionary).get("kind", "")) != "KAN":
			continue
		for option in (offer as Dictionary).get("payload_options", []):
			if str((option as Dictionary).get("kan_kind", "")) == "ADDED_KAN":
				payload = option as Dictionary
	assert_false(payload.is_empty())
	var declared := Action.kan(
		0, payload, "local", "550e8400-e29b-41d4-a716-000000000201",
		context.decision_id, 0, 1)
	assert_true(bc.apply_action(declared, ActionSource.HUMAN).accepted)
	assert_true(_predictions(coordinator, bc.state, 0).is_empty(),
		"抢杠窗尚未裁决时不得继续展示旧 live-wall 路径")
	for other in [1, 2, 3]:
		var rob_context := bc.decision_context_for_seat(other)
		assert_true(bc.apply_action(Action.make_pass(
			other, "local", "550e8400-e29b-41d4-a716-00000000020%d" % other,
			rob_context.decision_id, 0, other + 1), ActionSource.HUMAN).accepted)
	assert_eq(seat.melds.all()[0].kind, Meld.Kind.ADDED_KAN)
	assert_true(_prediction_for_target(
		_predictions(coordinator, bc.state, 0), 0).is_empty(),
		"加杠成功后的岭上摸牌须消费 actor 的下一摸")
	assert_eq(_predictions(coordinator, bc.state, 0).size(), 3)


func test_ankan_rinshan_consumes_actor_not_old_live_prediction() -> void:
	var activated := _activate(359, 0, 1, 0)
	var bc := activated.bc as BattleController
	var coordinator = _coordinator()
	if coordinator == null:
		return
	var old_target0 := _prediction_for_target(
		_predictions(coordinator, bc.state, 1), 0)
	var old_iid := (old_target0.tile as TileSkillAnchor).tile.instance_id
	bc._step_draw()
	assert_eq((bc.state.seats[0] as Seat).last_drawn_instance_id, old_iid)
	assert_eq(_predictions(coordinator, bc.state, 1).size(), 3)
	assert_true(_prediction_for_target(
		_predictions(coordinator, bc.state, 1), 0).is_empty(),
		"actor 的本轮普通摸牌须先消费自身预测")
	var seat := bc.state.seats[0] as Seat
	var hand_tiles: Array[Tile] = []
	for serial in range(100, 104):
		hand_tiles.append(Tile.new(TileId.W1, false, 0, serial))
	for index in range(10):
		hand_tiles.append(Tile.new(TileId.T1 + (index % 9), false, 0, 110 + index))
	assert_true(seat.hand.restore_tiles(hand_tiles))
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.DISCARD
	seat.last_drawn_instance_id = 100
	var context := bc.decision_context_for_seat(0)
	var payload: Dictionary = {}
	for offer in context.allowed_actions:
		if str((offer as Dictionary).get("kind", "")) != "KAN":
			continue
		for option in (offer as Dictionary).get("payload_options", []):
			if str((option as Dictionary).get("kan_kind", "")) == "ANKAN":
				payload = option as Dictionary
	assert_false(payload.is_empty())
	assert_true(bc.apply_action(Action.kan(
		0, payload, "local", "550e8400-e29b-41d4-a716-000000000401",
		context.decision_id, 0, 1), ActionSource.HUMAN).accepted)
	var rinshan_iid := int(seat.last_drawn_instance_id)
	assert_ne(rinshan_iid, old_iid)
	assert_true(_prediction_for_target(
		_predictions(coordinator, bc.state, 1), 0).is_empty(),
		"暗杠岭上已完成 actor 下一次实际摸牌，不得保留旧 live-wall 预测")
	assert_eq(_predictions(coordinator, bc.state, 1).size(), 3,
		"暗杠后必须为其余 pending 席按新 live-wall 路径重算")


func test_forecast_and_wall_top_authority_records_stay_isolated_through_restore_and_refresh() -> void:
	var bc := BattleController.new(3475, 0, false, TileId.E, 9)
	var wall_ctx := SkillCtx.new(bc.state, BattleEvent.make(&"TILE_DRAWN", 0))
	var hand_anchor := TileSkillAnchor.make(
		(bc.state.seats[1] as Seat).hand.first(), 1)
	hand_anchor.holder_seat = 1
	wall_ctx.reveal_tile_to(hand_anchor, 0)
	assert_eq(wall_ctx.reveal_wall_top_to(0, 3), 3)
	assert_true(BossAbilityFactory.inject(
		bc.registry, &"char_awai_passive_v1", 0))
	assert_true(BossAbilityFactory.inject(
		bc.registry, &"char_toki_passive_v1", 0))
	assert_eq(bc.scheduler.emit_event(
		BattleEvent.make(&"GAME_BEGIN", 0)).triggered_skills.size(), 2)
	var coordinator = _coordinator()
	if coordinator == null:
		return
	var forecasts := _predictions(coordinator, bc.state, 0)
	var wall_top := ViewerRevealResolver.wall_top_for_viewer(bc.state, 0, 3)
	assert_eq(forecasts.size(), 4, "forecast resolver 只读四席预测")
	assert_eq(wall_top.size(), 3, "wall_top resolver 只读潮见墙顶")
	assert_eq((RecipientViewProjector.project_viewer_seat_draw_forecast(
		bc.state, 0) as Array).size(), 4,
		"forecast provider 只序列化四席预测")
	assert_eq(RecipientViewProjector.project_viewer_wall_top(
		bc.state, 0).size(), 3,
		"wall_top provider 只序列化潮见墙顶")
	assert_not_null(ViewerRevealResolver.next_draw_for_viewer(bc.state, 0),
		"#344 next_draw 不得被 forecast recompute 误删")
	assert_eq((ViewerRevealResolver.tiles_by_holder(
		bc.state, 0).get(1, []) as Array).size(), 1,
		"手牌 reveal 不得被 forecast recompute 误删")
	var tagged := 0
	for value in bc.state.revealed_tiles:
		var record := value as Dictionary
		if record.get("projection_kind", "") == FORECAST_PROJECTION_KIND:
			tagged += 1
	assert_eq(tagged, 4, "forecast 身份必须显式存在于权威 revealed_tiles")

	var table = TABLE_SCENE.instantiate()
	add_child_autofree(table)
	table.set_local_seat(0)
	table.bind_battle_state(bc.state, 0, 4)
	assert_eq(table.seat_draw_forecast_count(), 4,
		"四席 UI 只读取 forecast")
	assert_eq(table.next_draw_reveal_count(), 3,
		"潮见 UI 只读取 wall_top")

	var snapshot := AuthorityReplaySnapshot.capture(bc)
	assert_not_null(snapshot)
	assert_true(snapshot.can_restore())
	var restored := BattleController.new(999, 1, false, TileId.E)
	assert_true(snapshot.restore_into(restored))
	assert_eq(_predictions(coordinator, restored.state, 0).size(), 4,
		"ARS roundtrip 后 forecast 身份与记录须保留")
	assert_eq(ViewerRevealResolver.wall_top_for_viewer(
		restored.state, 0, 3).size(), 3,
		"ARS roundtrip 后 wall_top 与 forecast 仍隔离")
	assert_eq((RecipientViewProjector.project_viewer_seat_draw_forecast(
		restored.state, 0) as Array).size(), 4)
	assert_eq(RecipientViewProjector.project_viewer_wall_top(
		restored.state, 0).size(), 3)
	assert_not_null(ViewerRevealResolver.next_draw_for_viewer(restored.state, 0))
	assert_eq((ViewerRevealResolver.tiles_by_holder(
		restored.state, 0).get(1, []) as Array).size(), 1)
	table.bind_battle_state(restored.state, 0, 4)
	assert_eq(table.seat_draw_forecast_count(), 4)
	assert_eq(table.next_draw_reveal_count(), 3)

	var restored_forecast_before := _predictions(
		coordinator, restored.state, 0).size()
	var refresh_ctx := SkillCtx.new(
		restored.state, BattleEvent.make(&"TILE_DRAWN", 0))
	assert_eq(refresh_ctx.reveal_wall_top_to(0, 3), 3)
	assert_eq(_predictions(coordinator, restored.state, 0).size(),
		restored_forecast_before,
		"wall_top 刷新不得清除 forecast")
	assert_not_null(ViewerRevealResolver.next_draw_for_viewer(restored.state, 0),
		"wall_top 刷新不得清除 #344 next_draw")
	assert_eq((ViewerRevealResolver.tiles_by_holder(
		restored.state, 0).get(1, []) as Array).size(), 1,
		"wall_top 刷新不得清除手牌 reveal")
	coordinator.clear_all(restored.state, restored.registry)
	assert_eq(_predictions(coordinator, restored.state, 0).size(), 0)
	assert_eq(ViewerRevealResolver.wall_top_for_viewer(
		restored.state, 0, 3).size(), 3,
		"forecast clear 不得清除 wall_top")
	assert_not_null(ViewerRevealResolver.next_draw_for_viewer(restored.state, 0),
		"forecast clear 不得清除 #344 next_draw")
	assert_eq((ViewerRevealResolver.tiles_by_holder(
		restored.state, 0).get(1, []) as Array).size(), 1,
		"forecast clear 不得清除手牌 reveal")

	for kind in ["unknown_private_projection@1", FORECAST_PROJECTION_KIND]:
		var corrupted_data := snapshot.to_dict()
		var records := corrupted_data.get("revealed", []) as Array
		assert_gt(records.size(), 0)
		var record := (records[records.size() - 1] as Dictionary).duplicate(true)
		record["projection_kind"] = kind
		if kind == FORECAST_PROJECTION_KIND:
			record["unexpected"] = true
		records[records.size() - 1] = record
		corrupted_data["revealed"] = records
		var corrupted := AuthorityReplaySnapshot.new()
		corrupted._data = corrupted_data
		assert_false(corrupted.can_restore(),
			"ARS 必须拒绝未知 projection_kind 与 forecast 多余字段")
	var invalid_shape_data := snapshot.to_dict()
	var invalid_shape_records := invalid_shape_data.get("revealed", []) as Array
	var forecast_record := (invalid_shape_records[
		invalid_shape_records.size() - 1] as Dictionary).duplicate(true)
	var forecast_tile := (forecast_record.get("tile", {}) as Dictionary).duplicate(true)
	forecast_tile["holder_seat"] = 0
	forecast_record["tile"] = forecast_tile
	invalid_shape_records[invalid_shape_records.size() - 1] = forecast_record
	invalid_shape_data["revealed"] = invalid_shape_records
	var invalid_shape := AuthorityReplaySnapshot.new()
	invalid_shape._data = invalid_shape_data
	assert_false(invalid_shape.can_restore(),
		"forecast tag 必须严格约束 holder=-1 的牌墙锚点")
