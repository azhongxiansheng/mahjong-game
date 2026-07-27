extends GutTest

# E2-03（#233）：正式练习配置驱动真实玩家控制器完成东风/半庄。

const SCRIPTED_DECISION_PORT := preload("res://tests/_fixtures/scripted_decision_port.gd")


func _config(round_kind: StringName, seed_value: int) -> GameSessionConfig:
	var intent := SessionIntent.new(&"PRACTICE", round_kind, &"STANDARD", &"lin_yeche")
	var converted := GameSessionConfig.from_intent(
		intent, seed_value, "runner-%s" % String(round_kind), "e2-03-v1", {}
	)
	assert_true(converted.ok)
	return converted.config


func _play_hand(bc: PlayableBattleController, winds: Array, player_actions: Array) -> Dictionary:
	winds.append(bc.state.round_wind)
	var port = SCRIPTED_DECISION_PORT.new()
	port.responder = func(kind: StringName, _context: Dictionary):
		match kind:
			&"discard":
				var hand_tiles: Array[Tile] = bc.state.seats[0].hand.tiles()
				if not hand_tiles.is_empty():
					player_actions.append(&"DISCARD")
					return {
						"action": "discard",
						"tile_instance_id": int(hand_tiles[0].instance_id),
					}
			&"riichi":
				return {"action": "riichi_no"}
			&"claim", &"claim_companions":
				return {"action": "skip"}
			&"kyuusyu":
				return {"action": "kyuusyu_no"}
		return {}
	bc.bind_decision_port(port, get_tree())
	bc.set_ai_think_delay(0.0)
	var result: Dictionary = await bc.run_to_end_async()
	port.responder = Callable()
	bc.bind_decision_port(null)
	return result


func _run_match(round_kind: StringName, seed_value: int) -> Dictionary:
	var winds: Array = []
	var player_actions: Array = []
	var score_updates: Array = []
	var runner := PracticeMatchRunner.new()
	var config := _config(round_kind, seed_value)
	var driver := PracticeSessionLauncher.new().launch(config)
	var summary: Dictionary = await runner.run_async(
		config,
		driver,
		func(bc: PlayableBattleController):
			return await _play_hand(bc, winds, player_actions),
		func(scores: Array, _applied: Dictionary):
			score_updates.append(scores.duplicate())
	)
	summary["observed_winds"] = winds
	summary["player_actions"] = player_actions
	summary["score_updates"] = score_updates
	return summary


func test_fixed_seed_east_match_completes_with_real_rules() -> void:
	var summary := await _run_match(&"EAST", 42)
	assert_true(summary.get("completed", false), str(summary))
	assert_eq(summary.get("round_kind"), &"EAST")
	assert_true(summary.get("score_conserved", false))
	assert_eq(summary.get("final_scores", []).size(), 4)
	assert_gt(summary.get("hand_count", 0), 0)
	assert_lt(summary.get("hand_count", 0), 61)
	assert_false(summary.get("player_actions", []).is_empty())
	assert_eq(summary.get("score_updates", []).size(), summary.get("hand_count", 0),
		"每局权威累计分更新后应通知一次表现层")
	for wind in summary.get("observed_winds", []):
		assert_eq(wind, TileId.E)


func test_fixed_seed_hanchan_reaches_south_and_completes() -> void:
	var summary := await _run_match(&"HANCHAN", 123)
	assert_true(summary.get("completed", false), str(summary))
	assert_eq(summary.get("round_kind"), &"HANCHAN")
	assert_true(summary.get("score_conserved", false))
	assert_eq(summary.get("final_scores", []).size(), 4)
	assert_gt(summary.get("hand_count", 0), 4)
	assert_lt(summary.get("hand_count", 0), 61)
	assert_true(summary.get("observed_winds", []).has(TileId.S_WIND))
	assert_false(summary.get("player_actions", []).is_empty())
