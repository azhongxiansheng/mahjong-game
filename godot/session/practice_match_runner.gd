class_name PracticeMatchRunner extends RefCounted

# E2-03（#233）+ E2-05（#235）：把正式练习配置、启动器产出的 GameDriver 与单局执行入口
# 串成完整东风/半庄；summary 含 final_scores/seat_order。结算 UI 与导航在协调层。

const HAND_LIMIT: int = 60


func run_async(
	config: GameSessionConfig,
	driver: GameDriver,
	play_hand: Callable,
	after_hand: Callable = Callable()
) -> Dictionary:
	if config == null or driver == null or not play_hand.is_valid():
		return _summary(config, driver, 0, false, &"INVALID_INPUT")
	if config.room_kind != GameSessionConfig.ROOM_PRACTICE:
		return _summary(config, driver, 0, false, &"NOT_PRACTICE")

	var hand_count: int = 0
	while not driver.finished and hand_count < HAND_LIMIT:
		var bc := driver.start_hand() as PlayableBattleController
		if bc == null:
			return _summary(config, driver, hand_count, false, &"START_HAND_FAILED")
		hand_count += 1
		var run_result: Dictionary = await play_hand.call(bc)
		var events: Array = run_result.get("events", [])
		var applied: Dictionary = driver.apply_result(events)
		if after_hand.is_valid():
			after_hand.call(driver.cumulative_scores.duplicate(), applied.duplicate(true))
		if applied.get("kind", "") == "exhaustive_draw":
			applied["tenpai_array"] = _detect_tenpai_array(bc)
		driver.advance_or_finish(applied)

	if not driver.finished:
		return _summary(config, driver, hand_count, false, &"HAND_LIMIT_EXCEEDED")
	return _summary(config, driver, hand_count, true, &"")


static func _detect_tenpai_array(bc: IAuthoritativeBattleController) -> Array:
	var result: Array = []
	for seat_index in range(4):
		var seat: Seat = bc.state.seats[seat_index]
		var melds: Array[Meld] = []
		for meld in seat.melds:
			melds.append(meld)
		result.append(not WaitCalculator.wait_tiles(seat.hand, melds).is_empty())
	return result


static func _summary(
	config: GameSessionConfig,
	driver: GameDriver,
	hand_count: int,
	completed: bool,
	error: StringName
) -> Dictionary:
	var finals: Array = driver.cumulative_scores.duplicate() if driver != null else []
	return {
		"completed": completed,
		"error": error,
		"session_id": config.session_id if config != null else "",
		"round_kind": config.round_kind if config != null else &"",
		"hand_count": hand_count,
		"final_scores": finals,
		"seat_order": MatchSettlement.build_seat_order(finals),
		"riichi_sticks": driver.riichi_sticks if driver != null else 0,
		"score_conserved": driver.is_score_conserved() if driver != null else false,
	}
