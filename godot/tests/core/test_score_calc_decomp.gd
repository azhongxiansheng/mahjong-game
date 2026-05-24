extends GutTest

# ScoreCalc per-decomposition scoring: 验证多分解时应按 (han, fu) → base_points
# 选最优分解，而非错误合并不同分解的役。
#
# Counter-example: hand 2m×3 3m×3 4m×3 5m 6m 7m 8s×2, winning 7m
#   Decomp A: [234m]×3 [567m] pair 8s → pinfu + iipeikou + tanyao = 3 han, fu=30
#   Decomp B: [222m][333m][444m][567m] pair 8s → sanankou + tanyao = 3 han, fu=50
# Bug: union yaku = pinfu+iipeikou+sanankou+tanyao = 5 han → mangan
# Correct: best base_points from decomp B (3 han 50 fu → 1600)

func _make_conflict_decompositions() -> Array:
	# Decomp A: all sequences [234m]×3 + [567m]
	var d_a := {
		"melds": [
			[TileId.W2, TileId.W3, TileId.W4],
			[TileId.W2, TileId.W3, TileId.W4],
			[TileId.W2, TileId.W3, TileId.W4],
			[TileId.W5, TileId.W6, TileId.W7],
		],
		"pair": TileId.S8,
	}
	# Decomp B: 3 triplets + sequence [222m][333m][444m][567m]
	var d_b := {
		"melds": [
			[TileId.W2, TileId.W2, TileId.W2],
			[TileId.W3, TileId.W3, TileId.W3],
			[TileId.W4, TileId.W4, TileId.W4],
			[TileId.W5, TileId.W6, TileId.W7],
		],
		"pair": TileId.S8,
	}
	return [d_a, d_b]

func _make_win_pattern(decomps: Array) -> Dictionary:
	return {
		"is_winning": true,
		"is_chiitoi": false,
		"is_kokushi": false,
		"standard_decompositions": decomps,
	}

func _yaku_for_decomp_a() -> YakuList:
	var y := YakuList.empty()
	y.add_yaku(&"pinfu", 1)
	y.add_yaku(&"iipeikou", 1)
	y.add_yaku(&"tanyao", 1)
	return y

func _yaku_for_decomp_b() -> YakuList:
	var y := YakuList.empty()
	y.add_yaku(&"sanankou", 2)
	y.add_yaku(&"tanyao", 1)
	return y

# ---- Bug demonstration: union yaku inflates score ----

func test_union_yaku_gives_inflated_score():
	var decomps := _make_conflict_decompositions()
	var wp := _make_win_pattern(decomps)
	var ctx := ScoreContext.ron(Tile.new(TileId.W7), TileId.E, TileId.S_WIND, 0, 1, 2)
	# Union yaku (the bug): pinfu+iipeikou+sanankou+tanyao = 5 han
	var union_yaku := YakuList.empty()
	union_yaku.add_yaku(&"pinfu", 1)
	union_yaku.add_yaku(&"iipeikou", 1)
	union_yaku.add_yaku(&"sanankou", 2)
	union_yaku.add_yaku(&"tanyao", 1)
	# Without callback, ScoreCalc uses union yaku — pinfu forces fu=30, 5 han → mangan
	var r := ScoreCalc.calculate(wp, [], union_yaku, ctx)
	assert_eq(r.han, 5, "union gives 5 han (buggy)")
	assert_eq(r.base_points, 2000, "union inflates to mangan (buggy)")

# ---- Fix: per-decomp callback selects best decomposition ----

func test_per_decomp_callback_picks_best_base_points():
	var decomps := _make_conflict_decompositions()
	var wp := _make_win_pattern(decomps)
	var ctx := ScoreContext.ron(Tile.new(TileId.W7), TileId.E, TileId.S_WIND, 0, 1, 2)
	# Provide per-decomp callback
	var callback := func(i: int) -> YakuList:
		if i == 0:
			return _yaku_for_decomp_a()
		else:
			return _yaku_for_decomp_b()
	var r := ScoreCalc.calculate(wp, [], YakuList.empty(), ctx, callback)
	# Decomp A: pinfu+iipeikou+tanyao=3 han, fu=30 → base=30×2^5=960
	# Decomp B: sanankou+tanyao=3 han, fu=50 → base=50×2^5=1600
	# Best = decomp B
	assert_eq(r.fu, 50, "should pick decomp B with higher base_points")
	assert_eq(r.han, 3, "correct han from decomp B (sanankou+tanyao)")
	assert_eq(r.base_points, 1600, "50×2^5=1600 (not mangan)")

func test_per_decomp_prefers_more_han_over_more_fu():
	# Case where lower fu but higher han gives better base_points
	var d_low_fu := {
		"melds": [
			[TileId.W2, TileId.W3, TileId.W4],
			[TileId.W2, TileId.W3, TileId.W4],
			[TileId.T2, TileId.T3, TileId.T4],
			[TileId.S5, TileId.S6, TileId.S7],
		],
		"pair": TileId.S8,
	}
	var d_high_fu := {
		"melds": [
			[TileId.W2, TileId.W2, TileId.W2],
			[TileId.W3, TileId.W3, TileId.W3],
			[TileId.T2, TileId.T3, TileId.T4],
			[TileId.S5, TileId.S6, TileId.S7],
		],
		"pair": TileId.S8,
	}
	var wp := _make_win_pattern([d_low_fu, d_high_fu])
	var ctx := ScoreContext.ron(Tile.new(TileId.T2), TileId.E, TileId.S_WIND, 0, 1, 2)
	var callback := func(i: int) -> YakuList:
		if i == 0:
			# pinfu + iipeikou + tanyao = 3 han, fu=30 → base=960
			var y := YakuList.empty()
			y.add_yaku(&"pinfu", 1)
			y.add_yaku(&"iipeikou", 1)
			y.add_yaku(&"tanyao", 1)
			return y
		else:
			# tanyao only = 1 han, fu=40 → base=40×2^3=320
			var y := YakuList.empty()
			y.add_yaku(&"tanyao", 1)
			return y
	var r := ScoreCalc.calculate(wp, [], YakuList.empty(), ctx, callback)
	# Decomp 0: 3 han 30 fu → 960 > Decomp 1: 1 han 40 fu → 320
	assert_eq(r.han, 3, "should pick decomp with more han (higher base)")
	assert_eq(r.fu, 30, "pinfu forces fu=30")
	assert_eq(r.base_points, 960)

func test_backward_compat_no_callback():
	# Without callback, existing behavior: pick highest fu
	var decomps := _make_conflict_decompositions()
	var wp := _make_win_pattern(decomps)
	var ctx := ScoreContext.ron(Tile.new(TileId.W7), TileId.E, TileId.S_WIND, 0, 1, 2)
	# Manually set correct yaku for decomp B (the winner)
	var y := _yaku_for_decomp_b()
	var r := ScoreCalc.calculate(wp, [], y, ctx)
	# sanankou+tanyao = 3 han. Decomp B fu: 20+10+4+4+4=42→50
	assert_eq(r.fu, 50)
	assert_eq(r.han, 3)
