extends GutTest

# 麻将王 — M8 Step 2: GameDriver 半庄战参数化单测
#
# 验证：
# - 默认 total_hands=4 / hands_per_round=4 兼容 M7
# - 半庄战 total_hands=8 / hands_per_round=4：hand_index>=4 时 round_wind=S_WIND
# - 终局判定: hand_index>=total_hands AND not renchan
# - 连庄/流转/立直棒/本场棒在 E4→S1 切换处的连续性

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

# ---- 默认值兼容 M7 ----

func test_default_total_hands_is_4_east_round():
	var d := GameDriver.new(42)
	assert_eq(d.total_hands, 4, "默认 total_hands=4 兼容 M7")
	assert_eq(d.hands_per_round, 4, "默认 hands_per_round=4")

# ---- 风圈推进函数 ----

func test_compute_round_wind_east_when_hand_index_lt_hands_per_round():
	var d := GameDriver.new(42, 4, 4)  # 半庄
	d.hand_index = 0
	assert_eq(d._compute_current_round_wind(), TileId.E, "hand_index=0 → 东")
	d.hand_index = 3
	assert_eq(d._compute_current_round_wind(), TileId.E, "hand_index=3 → 东 4")

func test_compute_round_wind_south_when_hand_index_gte_hands_per_round():
	var d := GameDriver.new(42, 8, 4)  # total=8, per_round=4
	d.hand_index = 4
	assert_eq(d._compute_current_round_wind(), TileId.S_WIND, "hand_index=4 → 南 1")
	d.hand_index = 7
	assert_eq(d._compute_current_round_wind(), TileId.S_WIND, "hand_index=7 → 南 4")

# ---- 半庄战终局 ----

func test_hanchan_finishes_at_hand_8_no_renchan():
	var d := GameDriver.new(42, 8, 4)
	# 每局都让当前庄家不听 → 流转
	for _i in range(8):
		var tenpai := [false, false, false, false]
		tenpai[(d.dealer_seat + 1) % 4] = true
		d.advance_or_finish({"kind": "exhaustive_draw", "tenpai_array": tenpai})
	assert_true(d.finished, "半庄 8 局完且不连庄 → 整场结束")
	assert_eq(d.hand_index, 8)

func test_hanchan_does_not_finish_at_hand_4():
	var d := GameDriver.new(42, 8, 4)
	for _i in range(4):
		var tenpai := [false, false, false, false]
		tenpai[(d.dealer_seat + 1) % 4] = true
		d.advance_or_finish({"kind": "exhaustive_draw", "tenpai_array": tenpai})
	assert_false(d.finished, "半庄战 hand_index=4 不结束（要打到 8）")
	assert_eq(d.hand_index, 4)

# ---- 连庄不切风圈 ----

func test_renchan_at_east_4_keeps_east_round_extends_past_4():
	var d := GameDriver.new(42, 8, 4)
	d.hand_index = 3  # 东 4
	# 庄家自摸 → 连庄
	var result := {
		"kind": "tsumo",
		"winner_seat": 0,
		"payout": {1: 2000, 2: 2000, 3: 2000},
		"winner_total": 6000,
	}
	d.advance_or_finish(result)
	assert_false(d.finished, "连庄不结束")
	assert_eq(d.hand_index, 3, "连庄 hand_index 不递增")
	assert_eq(d.honba, 1)
	assert_eq(d._compute_current_round_wind(), TileId.E, "hand_index 仍 3 → 仍东")

# ---- 极端连庄触发 HAND_LIMIT 由调用方保护 ----

func test_renchan_at_south_4_extends_past_total():
	var d := GameDriver.new(42, 8, 4)
	d.hand_index = 7  # 南 4
	var result := {
		"kind": "tsumo",
		"winner_seat": d.dealer_seat,
		"payout": {1: 2000, 2: 2000, 3: 2000},
		"winner_total": 6000,
	}
	d.advance_or_finish(result)
	assert_false(d.finished, "南 4 庄连庄不结束")
	assert_eq(d.hand_index, 7)
	assert_eq(d._compute_current_round_wind(), TileId.S_WIND, "南 4 连庄仍南")

# ---- 立直棒跨场风 ----

func test_riichi_sticks_carry_e4_to_s1():
	var d := GameDriver.new(42, 8, 4)
	# 模拟东 4 流局，立直棒留台到南 1
	d.hand_index = 3
	d.riichi_sticks = 2
	# 东 4 流局，庄家不听 → 流转到南 1
	var tenpai := [false, false, false, false]
	tenpai[(d.dealer_seat + 1) % 4] = true
	d.advance_or_finish({"kind": "exhaustive_draw", "tenpai_array": tenpai})
	assert_eq(d.hand_index, 4, "进入南 1")
	assert_eq(d.riichi_sticks, 2, "立直棒跨场风保留")
	assert_eq(d._compute_current_round_wind(), TileId.S_WIND, "现在是南")

# ---- 本场棒在风圈切换时正常重置（按规则：庄流转 honba 清零）----

func test_honba_resets_on_dealer_advance_at_e4_to_s1():
	var d := GameDriver.new(42, 8, 4)
	d.hand_index = 3
	d.honba = 5  # 之前累计了 5 本场
	var tenpai := [false, false, false, false]
	tenpai[(d.dealer_seat + 1) % 4] = true
	d.advance_or_finish({"kind": "exhaustive_draw", "tenpai_array": tenpai})
	assert_eq(d.honba, 0, "庄家流转 honba 清零（spec §5）— 风圈切换时也按此规则")

# ---- start_hand 注入 round_wind ----

func test_start_hand_injects_round_wind_east_default():
	var d := GameDriver.new(42)
	d.hand_index = 0
	var bc := d.start_hand()
	assert_eq(bc.state.round_wind, TileId.E, "hand 1 → 东")

func test_start_hand_injects_round_wind_south_in_hanchan():
	var d := GameDriver.new(42, 8, 4)
	d.hand_index = 4  # 南 1
	var bc := d.start_hand()
	assert_eq(bc.state.round_wind, TileId.S_WIND, "hand_index=4 半庄 → 场风南")

func test_start_hand_injects_round_wind_east_in_hanchan_first_half():
	var d := GameDriver.new(42, 8, 4)
	d.hand_index = 2  # 东 3
	var bc := d.start_hand()
	assert_eq(bc.state.round_wind, TileId.E, "hand_index=2 半庄前半 → 场风东")
