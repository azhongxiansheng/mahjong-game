extends GutTest

# 麻将王 — 里程碑 3 第 1 步：GameDriver 单测
#
# 通过构造伪 events Array + 伪 result（含 tenpai_array）覆盖：
#   - 庄家自摸/荣胡 → 连庄；闲家胡 → 流转
#   - 流局：庄家听 → 连庄；庄家不听 → 流转
#   - 流局立直棒留台；胡牌时立直棒由胜者收走
#   - 整场结束 / 不结束（东 4 + 连庄不结束）
#   - 点数守恒：sum(scores) + riichi_sticks * 1000 == 100000
#   - start_hand 注入累计分到 BattleController.state

# ---- helpers ----

func _make_tsumo_events(
	winner_seat: int,
	payout: Dictionary,
	winner_total: int,
	han: int = 1,
	fu: int = 30
) -> Array:
	var events: Array = []
	events.append(BattleEvent.make(&"TSUMO_DECLARED", winner_seat))
	events.append(BattleEvent.make(&"WIN_DECLARED", winner_seat, null, {
		"payout": payout,
		"winner_total": winner_total,
		"han": han,
		"fu": fu,
	}))
	return events

func _make_ron_events(
	winner_seat: int,
	discarder_seat: int,
	payout: Dictionary,
	winner_total: int
) -> Array:
	var events: Array = []
	events.append(BattleEvent.make(
		&"RON_DECLARED", winner_seat, null, {"discarder_seat": discarder_seat}
	))
	events.append(BattleEvent.make(&"WIN_DECLARED", winner_seat, null, {
		"payout": payout,
		"winner_total": winner_total,
		"han": 1,
		"fu": 30,
	}))
	return events

func _make_exhaustive_events() -> Array:
	return [BattleEvent.make(&"EXHAUSTIVE_DRAW", -1)]

# ---- 基础初始化 ----

func test_initial_state():
	var d := GameDriver.new()
	assert_eq(d.hand_index, 0)
	assert_eq(d.honba, 0)
	assert_eq(d.riichi_sticks, 0)
	assert_eq(d.dealer_seat, 0)
	assert_eq(d.cumulative_scores.size(), 4)
	for s in d.cumulative_scores:
		assert_eq(s, 25000)
	assert_true(d.is_score_conserved())
	assert_false(d.finished)
	assert_null(d.battle)

# ---- 庄家自摸 → 连庄 ----

func test_dealer_tsumo_renchan():
	var d := GameDriver.new(42)
	# 庄家自摸 mangan：3 闲各出 -2000，庄收 6000
	var events := _make_tsumo_events(0, {1: 2000, 2: 2000, 3: 2000}, 6000)
	var result := d.apply_result(events)
	assert_eq(result.kind, "tsumo")
	assert_eq(result.winner_seat, 0)

	var adv := d.advance_or_finish(result)
	assert_true(adv.renchan, "庄家自摸应连庄")
	assert_false(adv.finished)
	assert_eq(d.honba, 1, "本场 +1")
	assert_eq(d.dealer_seat, 0, "庄家不变")
	assert_eq(d.hand_index, 0, "局数不变")
	assert_eq(d.cumulative_scores[0], 25000 + 6000)
	assert_eq(d.cumulative_scores[1], 25000 - 2000)
	assert_true(d.is_score_conserved())

# ---- 闲家自摸 → 流转 ----

func test_non_dealer_tsumo_advance():
	var d := GameDriver.new(42)
	# seat 1 自摸 mangan 闲家：庄出 -2000，2 闲各出 -1000，胜者收 4000
	var events := _make_tsumo_events(1, {0: 2000, 2: 1000, 3: 1000}, 4000)
	var result := d.apply_result(events)
	var adv := d.advance_or_finish(result)
	assert_false(adv.renchan, "闲家胡应流转")
	assert_eq(d.honba, 0)
	assert_eq(d.dealer_seat, 1, "庄顺转")
	assert_eq(d.hand_index, 1, "进入下一局")
	assert_true(d.is_score_conserved())

# ---- 闲家荣胡庄家 → 流转 ----

func test_non_dealer_ron_dealer_advance():
	var d := GameDriver.new(42)
	# seat 2 荣胡庄(0) 6400 点：庄独出，胜者收 6400
	var events := _make_ron_events(2, 0, {0: 6400}, 6400)
	var result := d.apply_result(events)
	assert_eq(result.kind, "ron")
	assert_eq(result.winner_seat, 2)

	var adv := d.advance_or_finish(result)
	assert_false(adv.renchan)
	assert_eq(d.dealer_seat, 1)
	assert_eq(d.hand_index, 1)
	assert_eq(d.cumulative_scores[0], 25000 - 6400)
	assert_eq(d.cumulative_scores[2], 25000 + 6400)
	assert_true(d.is_score_conserved())

# ---- 流局：庄家听 → 连庄 + 罚符 ----

func test_exhaustive_draw_dealer_tenpai_renchan():
	var d := GameDriver.new(42)
	var events := _make_exhaustive_events()
	var result := d.apply_result(events)
	assert_eq(result.kind, "exhaustive_draw")

	# 仅庄家(0)听
	result["tenpai_array"] = [true, false, false, false]
	var adv := d.advance_or_finish(result)
	assert_true(adv.renchan, "庄家听 → 连庄")
	assert_eq(d.honba, 1)
	assert_eq(d.dealer_seat, 0)
	assert_eq(d.hand_index, 0)
	# 罚符：1 听全收 3000，3 不听各出 -1000
	assert_eq(d.cumulative_scores[0], 25000 + 3000)
	assert_eq(d.cumulative_scores[1], 25000 - 1000)
	assert_eq(d.cumulative_scores[2], 25000 - 1000)
	assert_eq(d.cumulative_scores[3], 25000 - 1000)
	assert_true(d.is_score_conserved())

# ---- 流局：庄家不听 → 流转 + 罚符 ----

func test_exhaustive_draw_dealer_noten_advance():
	var d := GameDriver.new(42)
	var events := _make_exhaustive_events()
	var result := d.apply_result(events)
	# 闲家 1, 2 听
	result["tenpai_array"] = [false, true, true, false]
	var adv := d.advance_or_finish(result)
	assert_false(adv.renchan, "庄家不听 → 流转")
	assert_eq(d.dealer_seat, 1)
	assert_eq(d.hand_index, 1)
	# 罚符：2 听各收 1500，2 不听各出 -1500
	assert_eq(d.cumulative_scores[0], 25000 - 1500)
	assert_eq(d.cumulative_scores[1], 25000 + 1500)
	assert_eq(d.cumulative_scores[2], 25000 + 1500)
	assert_eq(d.cumulative_scores[3], 25000 - 1500)
	assert_true(d.is_score_conserved())

# ---- 流局：全听/全不听 → 0 罚符 ----

func test_exhaustive_draw_all_tenpai_zero_payout():
	var d := GameDriver.new(42)
	var events := _make_exhaustive_events()
	var result := d.apply_result(events)
	result["tenpai_array"] = [true, true, true, true]
	d.advance_or_finish(result)
	for s in d.cumulative_scores:
		assert_eq(s, 25000, "全听 0 罚符")
	assert_true(d.is_score_conserved())

# ---- 流局立直棒跨局保留 ----

func test_riichi_sticks_carry_over_through_draw():
	var d := GameDriver.new(42)
	d.on_riichi_declared(0)
	assert_eq(d.cumulative_scores[0], 24000)
	assert_eq(d.riichi_sticks, 1)
	assert_true(d.is_score_conserved())

	var events := _make_exhaustive_events()
	var result := d.apply_result(events)
	result["tenpai_array"] = [true, true, true, true]
	d.advance_or_finish(result)
	assert_eq(d.riichi_sticks, 1, "立直棒跨局保留")
	assert_true(d.is_score_conserved())

# ---- 立直棒由胜者收走 ----

func test_riichi_sticks_collected_on_win():
	var d := GameDriver.new(42)
	d.on_riichi_declared(0)
	d.on_riichi_declared(2)
	assert_eq(d.riichi_sticks, 2)
	assert_eq(d.cumulative_scores[0], 24000)
	assert_eq(d.cumulative_scores[2], 24000)
	assert_true(d.is_score_conserved())

	# seat 1 自摸：基本 4000 + 2 立直棒 2000 = winner_total 6000
	var events := _make_tsumo_events(1, {0: 2000, 2: 1000, 3: 1000}, 6000)
	d.apply_result(events)
	assert_eq(d.riichi_sticks, 0, "立直棒被胜者收走")
	assert_eq(d.cumulative_scores[1], 25000 + 6000)
	assert_true(d.is_score_conserved())

# ---- 整场结束：东 4 + 不连庄 ----

func test_round_finish_after_east_4_no_renchan():
	var d := GameDriver.new(42)
	# 每局都让当前庄家不听（旁人听一个），保证流转。
	for _i in range(4):
		var tenpai := [false, false, false, false]
		tenpai[(d.dealer_seat + 1) % 4] = true
		var result := {"kind": "exhaustive_draw", "tenpai_array": tenpai}
		d.advance_or_finish(result)
	assert_true(d.finished, "东 4 完且不连庄 → 整场结束")
	assert_eq(d.hand_index, 4)

# ---- 整场不结束：东 4 连庄 ----

func test_round_does_not_finish_with_renchan_at_east_4():
	var d := GameDriver.new(42)
	d.hand_index = 3  # 已到东 4
	# 庄家自摸 → 连庄，不结束
	var result := {"kind": "tsumo", "winner_seat": 0, "payout": {1: -1000, 2: -1000, 3: -1000}, "winner_total": 3000}
	d.advance_or_finish(result)
	assert_false(d.finished, "连庄不结束（spec §3.2 不限上限）")
	assert_eq(d.hand_index, 3)
	assert_eq(d.honba, 1)

# ---- start_hand 注入累计分 ----

func test_start_hand_injects_cumulative_scores():
	var d := GameDriver.new(42)
	d.cumulative_scores = [30000, 20000, 25000, 25000]
	d.honba = 2
	d.riichi_sticks = 1
	var bc := d.start_hand()
	assert_not_null(bc)
	assert_not_null(bc.state)
	assert_eq(bc.state.scores[0], 30000)
	assert_eq(bc.state.scores[1], 20000)
	assert_eq(bc.state.scores[2], 25000)
	assert_eq(bc.state.scores[3], 25000)
	assert_eq(bc.state.honba, 2)
	assert_eq(bc.state.riichi_sticks, 1)

# ---- 完整 4 局走一遍守恒 ----

func test_full_east_round_score_conservation():
	var d := GameDriver.new(123)
	# 东 1：seat 1 自摸 mangan 闲
	d.advance_or_finish(d.apply_result(_make_tsumo_events(1, {0: 2000, 2: 1000, 3: 1000}, 4000)))
	assert_true(d.is_score_conserved())
	# 东 2：seat 2 荣胡 seat 0
	d.advance_or_finish(d.apply_result(_make_ron_events(2, 0, {0: 3900}, 3900)))
	assert_true(d.is_score_conserved())
	# 东 3：流局，庄(2)听
	var draw_result := d.apply_result(_make_exhaustive_events())
	draw_result["tenpai_array"] = [false, false, true, false]
	d.advance_or_finish(draw_result)
	assert_true(d.is_score_conserved())
	# 东 3 连庄（庄=seat 2 听）
	assert_eq(d.dealer_seat, 2)
	assert_eq(d.honba, 1)
	# 东 3 二本场：seat 3 自摸
	d.advance_or_finish(d.apply_result(_make_tsumo_events(3, {0: 1500, 1: 1500, 2: 3000}, 6000)))
	assert_true(d.is_score_conserved())
	# 东 4：庄=seat 3，闲胡 → 流转 → 整场结束
	d.advance_or_finish(d.apply_result(_make_ron_events(0, 3, {3: 8000}, 8000)))
	assert_true(d.finished)
	assert_true(d.is_score_conserved())


# ---- #376：已提交 settlement 推进（不二次计分）----

func _committed_settlement(
	outcome: String,
	scores: Array,
	renchan: bool,
	dealer: int = 0,
	honba_next: int = 0,
	sticks: int = 0,
	hand_seq: int = 0
) -> Dictionary:
	return {
		"hand_seq": hand_seq,
		"outcome": outcome,
		"winner_seats": [0] if outcome in ["RON", "TSUMO", "NAGASHI_MANGAN"] else [],
		"loser_seat": 1 if outcome == "RON" else -1,
		"score_deltas": [
			int(scores[0]) - 25000,
			int(scores[1]) - 25000,
			int(scores[2]) - 25000,
			int(scores[3]) - 25000,
		],
		"scores": scores.duplicate(),
		"dealer_seat": dealer,
		"renchan": renchan,
		"honba": honba_next,
		"riichi_sticks": sticks,
		"adjustments": [],
	}


func test_will_finish_after_settlement_east_last_non_renchan() -> void:
	var d := GameDriver.new(7, 4, 4)
	d.hand_index = 3
	var s_end := _committed_settlement("RON", [30000, 20000, 25000, 25000], false, 3)
	assert_true(d.will_finish_after_settlement(s_end))
	var s_ren := _committed_settlement("TSUMO", [30000, 20000, 25000, 25000], true, 3)
	assert_false(d.will_finish_after_settlement(s_ren), "连庄不得终场")
	d.hand_index = 2
	assert_false(d.will_finish_after_settlement(s_end), "未到东四不得终场")


func test_advance_from_committed_settlement_no_double_score() -> void:
	var d := GameDriver.new(9, 4, 4)
	d.cumulative_scores = [25000, 25000, 25000, 25000]
	d.battle = BattleController.new(1, 0, false, TileId.E, 0)
	var settled := _committed_settlement(
		"TSUMO", [28000, 24000, 24000, 24000], true, 0, 1, 0, 0
	)
	var adv: Dictionary = d.advance_from_committed_settlement(settled)
	assert_true(bool(adv.get("renchan", false)))
	assert_false(bool(adv.get("finished", true)))
	assert_eq(d.cumulative_scores[0], 28000)
	assert_eq(d.honba, 1)
	assert_eq(d.hand_index, 0)
	assert_eq(d.dealer_seat, 0)
	assert_null(d.battle)
	# 再推进一次非连庄 → hand_index+1
	var s2 := _committed_settlement(
		"RON", [30000, 22000, 24000, 24000], false, 0, 0, 0, 1
	)
	var adv2: Dictionary = d.advance_from_committed_settlement(s2)
	assert_false(bool(adv2.get("renchan", true)))
	assert_eq(d.hand_index, 1)
	assert_eq(d.dealer_seat, 1)
	assert_eq(d.honba, 0)
	assert_eq(d.cumulative_scores[0], 30000)


func test_advance_from_committed_settlement_finishes_east() -> void:
	var d := GameDriver.new(3, 4, 4)
	d.hand_index = 3
	d.dealer_seat = 3
	var settled := _committed_settlement(
		"RON", [40000, 20000, 20000, 20000], false, 3, 0, 0, 3
	)
	assert_true(d.will_finish_after_settlement(settled))
	var adv: Dictionary = d.advance_from_committed_settlement(settled)
	assert_true(bool(adv.get("finished", false)))
	assert_true(d.finished)
	assert_eq(d.hand_index, 4)
	var snap: Dictionary = d.export_match_state()
	assert_true(bool(snap.get("finished", false)))
	assert_eq(int(snap.get("hand_index", -1)), 4)
	assert_eq(int(snap.get("round_wind", -1)), TileId.E, "东风终场 round_wind 仍为东")


func test_hanchan_finished_round_wind_stays_south() -> void:
	var d := GameDriver.new(5, 8, 4)
	d.hand_index = 7
	var settled := _committed_settlement(
		"RON", [40000, 20000, 20000, 20000], false, 3, 0, 0, 7
	)
	assert_true(d.will_finish_after_settlement(settled))
	d.advance_from_committed_settlement(settled)
	assert_true(d.finished)
	assert_eq(int(d.export_match_state().get("round_wind", -1)), TileId.S_WIND)


func test_capture_restore_authority_state_roundtrip() -> void:
	var d := GameDriver.new(9, 4, 4)
	d.hand_index = 2
	d.honba = 1
	d.dealer_seat = 2
	d.cumulative_scores = [30000, 20000, 25000, 25000]
	var cap: Dictionary = d.capture_authority_state()
	d.hand_index = 3
	d.honba = 0
	d.dealer_seat = 0
	d.finished = true
	assert_true(d.restore_authority_state(cap))
	assert_eq(d.hand_index, 2)
	assert_eq(d.honba, 1)
	assert_eq(d.dealer_seat, 2)
	assert_false(d.finished)
	assert_eq(d.cumulative_scores[0], 30000)
