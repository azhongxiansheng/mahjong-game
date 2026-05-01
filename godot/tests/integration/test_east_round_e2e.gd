extends GutTest

# 麻将王 — 里程碑 3 第 4 步：东风战 e2e 集成测试
#
# 把 GameDriver + BattleController 串起来跑完整场，验证：
#   1. 整场能跑完（不死锁、连庄不无穷）
#   2. 每局守恒：sum(cumulative_scores) + riichi_sticks*1000 == 100000
#   3. 整场结束时 hand_index >= 4（除非有连庄保留 hand_index=3）
#   4. 流局路径走 WaitCalculator + ExhaustiveDraw 正确

const HAND_LIMIT: int = 30  # 连庄保护上限，正常东风战很少 > 10 局

func _run_full_round(seed: int) -> GameDriver:
	var d := GameDriver.new(seed)
	var hand_count := 0

	while not d.finished and hand_count < HAND_LIMIT:
		hand_count += 1

		var bc := d.start_hand()
		var run_result: Dictionary = bc.run_to_end()
		var apply_res: Dictionary = d.apply_result(run_result.events)

		if apply_res.kind == "exhaustive_draw":
			var tenpai_array: Array = []
			for i in range(4):
				var seat: Seat = bc.state.seats[i]
				var typed_melds: Array[Meld] = []
				for m in seat.melds:
					typed_melds.append(m)
				var waits: Array = WaitCalculator.wait_tiles(seat.hand, typed_melds)
				tenpai_array.append(waits.size() > 0)
			apply_res["tenpai_array"] = tenpai_array

		d.advance_or_finish(apply_res)

		# 每局守恒断言
		assert_true(d.is_score_conserved(),
			"hand %d 守恒被破坏: scores=%s sticks=%d" % [
				hand_count, str(d.cumulative_scores), d.riichi_sticks
			])

	assert_true(d.finished, "整场应在 HAND_LIMIT 内结束（实际跑了 %d 局）" % hand_count)
	return d

# ---- 多 seed e2e 跑通 ----

func test_full_east_round_seed_42():
	var d := _run_full_round(42)
	assert_true(d.finished)
	assert_true(d.is_score_conserved())

func test_full_east_round_seed_7():
	var d := _run_full_round(7)
	assert_true(d.finished)
	assert_true(d.is_score_conserved())

func test_full_east_round_seed_123():
	var d := _run_full_round(123)
	assert_true(d.finished)
	assert_true(d.is_score_conserved())

func test_full_east_round_seed_999():
	var d := _run_full_round(999)
	assert_true(d.finished)
	assert_true(d.is_score_conserved())

# ---- 整场守恒压力测试（5 个 seed） ----

func test_score_conservation_across_seeds():
	for seed in [1, 2, 3, 4, 5]:
		var d := _run_full_round(seed)
		var total := 0
		for s in d.cumulative_scores:
			total += int(s)
		assert_eq(total + d.riichi_sticks * GameDriver.RIICHI_STICK_VALUE,
			GameDriver.STARTING_SCORE * 4,
			"seed=%d 守恒错: total=%d sticks=%d" % [seed, total, d.riichi_sticks])

# ---- hand_index 终态 ----

func test_finished_hand_index_in_range():
	var d := _run_full_round(42)
	# 不连庄结束 → hand_index 至少 4；连庄到底也合法但本仓库 SimpleAi 太弱，连庄少
	assert_gte(d.hand_index, 4, "整场结束时至少推进到东 4 后")
	assert_lt(d.hand_index, HAND_LIMIT, "未死锁")
