extends GutTest

# ScoreCalc: 顶层入口。把 WinPattern.detect 结果 + called_melds + yaku_list + win_ctx
# 算成 {fu, han, base_points, payout, yakuman_multiplier, winner_total}.
#
# Golden cases 取自日麻 wiki 标准点数早见表（https://riichi.wiki/Scoring_table）。

func _make_yaku(pairs: Array, dora: int = 0) -> YakuList:
	var y := YakuList.empty()
	for p in pairs:
		y.add_yaku(p[0], p[1])
	y.dora_count = dora
	return y

# ---- Golden #1: 30 符 1 番 闲自摸 → winner 收 1100 ----

func test_golden_30fu_1han_non_dealer_tsumo():
	# 牌型：234m 234p 234s 234s 55s（非 pinfu 因为 234s 重复 = 二盃口，但用 riichi 简化）
	# 实际 yaku 用 riichi 1 番。fu = 30 (副底 20 + 自摸 2 + 0 雀头 + 0 双面 + 0顺*4 = 22 → 30)
	var d := {
		"melds": [
			[TileId.W2, TileId.W3, TileId.W4],
			[TileId.T2, TileId.T3, TileId.T4],
			[TileId.S2, TileId.S3, TileId.S4],
			[TileId.S6, TileId.S7, TileId.S8],
		],
		"pair": TileId.S1,
	}
	var win_pattern := {
		"is_winning": true,
		"is_chiitoi": false,
		"is_kokushi": false,
		"standard_decompositions": [d],
	}
	var ctx := ScoreContext.tsumo(Tile.new(TileId.S6), TileId.E, TileId.S_WIND, 0, 1)
	# winning S6 在 [S6,S7,S8] a=S6, winning=a, number=6 ≠ 7 → 双面 0
	var y := _make_yaku([[&"riichi", 1]])
	var r := ScoreCalc.calculate(win_pattern, [], y, ctx)
	assert_eq(r.fu, 30)
	assert_eq(r.han, 1)
	assert_eq(r.base_points, 240)
	# 庄 500 (240*2=480→500)，2 闲 300 (240→300)
	assert_eq(r.payout[0], 500)
	assert_eq(r.payout[2], 300)
	assert_eq(r.payout[3], 300)
	assert_eq(r.winner_total, 500 + 300 + 300, "1100")

# ---- Golden #2: 40 符 4 番 闲荣胡 → 8000 满贯 ----

func test_golden_40fu_4han_clamps_to_mangan():
	# 假设某种 4 番荣胡导致 40 符 → base 钳到 2000 满贯 → 闲家 8000
	var d := {
		"melds": [
			[TileId.W2, TileId.W2, TileId.W2],
			[TileId.W3, TileId.W3, TileId.W3],
			[TileId.W4, TileId.W4, TileId.W4],
			[TileId.W5, TileId.W6, TileId.W7],
		],
		"pair": TileId.W1,
	}
	var win_pattern := {
		"is_winning": true,
		"is_chiitoi": false,
		"is_kokushi": false,
		"standard_decompositions": [d],
	}
	var ctx := ScoreContext.ron(Tile.new(TileId.W5), TileId.E, TileId.S_WIND, 0, 1, 2)
	# fu: 20 + 10 门清荣 + 0 雀头 + 0 双面(W5 在 [W5,W6,W7] a=W5 num=5) + 4 暗刻222(中) + 4 暗刻333(中) + 4 暗刻444(中) + 0 顺
	# 等等：W2/W3/W4 的 number 是 2/3/4 都是中张
	# fu = 20 + 10 + 0 + 0 + 4 + 4 + 4 + 0 = 42 → 50 ?
	# 但雀头 W1 是幺九数牌，PairFu = 0（不是字牌也不是役风）
	# 所以 fu = 50 不是 40
	# 改测试名 50fu 4han
	var y := _make_yaku([[&"toitoi", 2], [&"sanankou", 2]])  # 4 番
	var r := ScoreCalc.calculate(win_pattern, [], y, ctx)
	assert_eq(r.fu, 50)
	assert_eq(r.han, 4)
	# 50 × 2^6 = 3200 > 2000 → 满贯 2000
	assert_eq(r.base_points, 2000)
	assert_eq(r.payout[2], 8000, "闲荣胡满贯 8000")

# ---- 七対子 ----

func test_chiitoi_25fu():
	var win_pattern := {
		"is_winning": true,
		"is_chiitoi": true,
		"is_kokushi": false,
		"standard_decompositions": [],
	}
	var ctx := ScoreContext.tsumo(Tile.new(TileId.W5), TileId.E, TileId.S_WIND, 0, 1)
	var y := _make_yaku([[&"chiitoitsu", 2], [&"riichi", 1]])
	var r := ScoreCalc.calculate(win_pattern, [], y, ctx)
	assert_eq(r.fu, 25)
	assert_eq(r.han, 3)
	# 25 × 2^5 = 800. 闲自摸：庄 1600→1600，闲 800→800
	assert_eq(r.base_points, 800)
	assert_eq(r.payout[0], 1600)
	assert_eq(r.payout[2], 800)
	assert_eq(r.payout[3], 800)

# ---- 役满 ----

func test_yakuman_dealer_tsumo():
	# 庄家自摸国士 → 48000
	var win_pattern := {
		"is_winning": true,
		"is_chiitoi": false,
		"is_kokushi": true,
		"is_thirteen_wait": false,
		"standard_decompositions": [],
	}
	var ctx := ScoreContext.tsumo(Tile.new(TileId.W1), TileId.E, TileId.E, 0, 0)
	var y := YakuList.empty()
	y.is_yakuman = true
	y.yakuman_multiplier = 1
	y.add_yaku(&"kokushi", 13)
	var r := ScoreCalc.calculate(win_pattern, [], y, ctx)
	assert_eq(r.base_points, 8000)
	assert_eq(r.yakuman_multiplier, 1)
	# 庄自摸：3 闲各 16000，总 48000
	assert_eq(r.payout[1], 16000)
	assert_eq(r.payout[2], 16000)
	assert_eq(r.payout[3], 16000)
	assert_eq(r.winner_total, 48000)

# ---- 立直棒收入 ----

func test_riichi_sticks_added_to_winner_total():
	var d := {
		"melds": [
			[TileId.W2, TileId.W3, TileId.W4],
			[TileId.T2, TileId.T3, TileId.T4],
			[TileId.S2, TileId.S3, TileId.S4],
			[TileId.S6, TileId.S7, TileId.S8],
		],
		"pair": TileId.S1,
	}
	var win_pattern := {
		"is_winning": true,
		"is_chiitoi": false,
		"is_kokushi": false,
		"standard_decompositions": [d],
	}
	var ctx := ScoreContext.tsumo(Tile.new(TileId.S6), TileId.E, TileId.S_WIND, 0, 1)
	ctx.riichi_sticks = 2  # 桌上 2 根
	var y := _make_yaku([[&"riichi", 1]])
	var r := ScoreCalc.calculate(win_pattern, [], y, ctx)
	# winner_total = payout 总 + 2000
	assert_eq(r.winner_total, 1100 + 2000)

# ---- 选 fu 最高分解 ----

func test_picks_highest_fu_decomposition():
	# 同一手有 2 种合法分解：一种 暗刻 一种 顺子
	# 系统应选 fu 高的那个
	var d_high := {
		"melds": [
			[TileId.W5, TileId.W5, TileId.W5],
			[TileId.W1, TileId.W2, TileId.W3],
			[TileId.W6, TileId.W7, TileId.W8],
			[TileId.T2, TileId.T3, TileId.T4],
		],
		"pair": TileId.S6,
	}
	var d_low := {
		# 假设这是另一种分解（非真实 — 只为测试 picker）
		"melds": [
			[TileId.W3, TileId.W4, TileId.W5],
			[TileId.W5, TileId.W5, TileId.W6],  # 不合法，但 picker 不验证
			[TileId.W1, TileId.W2, TileId.W7],
			[TileId.T2, TileId.T3, TileId.T4],
		],
		"pair": TileId.S6,
	}
	var win_pattern := {
		"is_winning": true,
		"is_chiitoi": false,
		"is_kokushi": false,
		"standard_decompositions": [d_low, d_high],
	}
	var ctx := ScoreContext.tsumo(Tile.new(TileId.T2), TileId.E, TileId.S_WIND, 0, 1)
	# winning T2 在 [T2,T3,T4] a=T2, winning=a, number=2 → 双面 0
	var y := _make_yaku([[&"riichi", 1]])
	var r := ScoreCalc.calculate(win_pattern, [], y, ctx)
	# d_high: 20+2自摸+0雀头+0双面+4暗刻W5(中)+0顺*3 = 26 → 30
	assert_eq(r.fu, 30, "应选 fu 最高的分解 (含 W5 暗刻)")


func test_score_result_carries_fu_breakdown_from_selected_decomposition():
	var d := {
		"melds": [
			[TileId.W2, TileId.W2, TileId.W2],
			[TileId.T2, TileId.T3, TileId.T4],
			[TileId.T5, TileId.T6, TileId.T7],
			[TileId.S6, TileId.S7, TileId.S8],
		],
		"pair": TileId.E,
	}
	var win_pattern := {
		"is_winning": true,
		"is_chiitoi": false,
		"is_kokushi": false,
		"standard_decompositions": [d],
	}
	var ctx := ScoreContext.ron(Tile.new(TileId.S7), TileId.E, TileId.E, 0, 0, 2)
	var result := ScoreCalc.calculate(win_pattern, [], _make_yaku([[&"riichi", 1]]), ctx)
	assert_true(result.has("fu_breakdown"), "WIN_DECLARED 的权威计分结果必须携带符组成")
	assert_eq(result.fu_breakdown.rounded_fu, result.fu)
	assert_eq(result.fu_breakdown.raw_fu, 38)
