extends GutTest

# 九種九牌玩家可宣告途中流局(日麻 §3.2)。验证:
# 1. 默认 hook 永返 false → AI 不会自动 abort
# 2. apply_result 检测到 ABORTIVE_DRAW 事件 → 返 kind="abortive_draw"
# 3. advance_or_finish 处理 abortive_draw → renchan(dealer 留任) + honba+1


# 默认 BattleController._should_declare_kyuusyu_kyuuhai 永远返 false
func test_default_hook_returns_false() -> void:
	var bc := BattleController.new(42, 0, false, TileId.E)
	# 调用默认 hook 应同步返 false(非 coroutine 路径)
	var result = bc._should_declare_kyuusyu_kyuuhai(0)
	assert_eq(result, false, "默认 BC 不应主动 abort")


# emit ABORTIVE_DRAW → apply_result 应识别为 abortive_draw kind
func test_apply_result_detects_abortive_draw() -> void:
	var driver := GameDriver.new(7, 4, 4)
	var ev := BattleEvent.new()
	ev.type = &"ABORTIVE_DRAW"
	ev.actor_seat = 0
	ev.extra = {"reason": "kyuusyu_kyuuhai"}
	var result: Dictionary = driver.apply_result([ev])
	assert_eq(result.get("kind"), "abortive_draw")
	assert_eq(result.get("reason"), "kyuusyu_kyuuhai")


# advance_or_finish 处理 abortive_draw → renchan(dealer 留任 + honba+1)
func test_advance_or_finish_abortive_keeps_dealer_and_bumps_honba() -> void:
	var driver := GameDriver.new(7, 4, 4)
	driver.dealer_seat = 0
	driver.hand_index = 0
	driver.honba = 0
	var advance: Dictionary = driver.advance_or_finish({"kind": "abortive_draw"})
	assert_true(advance.get("renchan"), "abortive_draw 应连庄(dealer 留任)")
	assert_eq(driver.dealer_seat, 0, "dealer 不变")
	assert_eq(driver.hand_index, 0, "hand_index 不变")
	assert_eq(driver.honba, 1, "honba 应 +1")


# abortive_draw 不产生 payout(无人胡)+ 不触发流局罚符(noten payout)
func test_abortive_draw_no_score_changes() -> void:
	var driver := GameDriver.new(7, 4, 4)
	var scores_before: Array = driver.cumulative_scores.duplicate()
	driver.advance_or_finish({"kind": "abortive_draw"})
	assert_eq(driver.cumulative_scores, scores_before,
		"abortive_draw 不应改 cumulative_scores")
