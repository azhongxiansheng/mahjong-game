extends GutTest

# 待牌符（标准日麻）：
#   边张 (Penchan)：12 等 3 / 89 等 7 → +2
#   嵌张 (Kanchan)：24 等 3 → +2
#   单骑 (Tanki)：等雀头 → +2
#   双面 (Ryanmen)：23 等 4 → 0
#   双碰 (Shanpon)：55+33 等 5 → 0
#
# 输入：含 winning_tile 的 14 张分解 {melds, pair} + winning_tile_id

# ---- 单骑 ----

func test_single_wait_pair_simple():
	var d := {
		"melds": [
			[TileId.W1, TileId.W2, TileId.W3],
			[TileId.W4, TileId.W5, TileId.W6],
			[TileId.W7, TileId.W8, TileId.W9],
			[TileId.T2, TileId.T3, TileId.T4],
		],
		"pair": TileId.S5,
	}
	assert_eq(WaitFu.fu_for_wait(d, TileId.S5), 2, "单骑 +2")

func test_single_wait_pair_honor():
	var d := {
		"melds": [
			[TileId.W1, TileId.W2, TileId.W3],
			[TileId.W4, TileId.W5, TileId.W6],
			[TileId.W7, TileId.W8, TileId.W9],
			[TileId.T2, TileId.T3, TileId.T4],
		],
		"pair": TileId.E,
	}
	assert_eq(WaitFu.fu_for_wait(d, TileId.E), 2, "字牌单骑 +2")

# ---- 边张 ----

func test_penchan_low_end_3():
	# 12 等 3：分解 [1,2,3]，winning=3
	var d := {
		"melds": [[TileId.W1, TileId.W2, TileId.W3]],
		"pair": TileId.S5,
	}
	assert_eq(WaitFu.fu_for_wait(d, TileId.W3), 2, "边 3 (12 等 3)")

func test_penchan_high_end_7():
	# 89 等 7：分解 [7,8,9]，winning=7
	var d := {
		"melds": [[TileId.W7, TileId.W8, TileId.W9]],
		"pair": TileId.S5,
	}
	assert_eq(WaitFu.fu_for_wait(d, TileId.W7), 2, "边 7 (89 等 7)")

# ---- 嵌张 ----

func test_kanchan_middle():
	# 24 等 3：分解 [2,3,4]，winning=3
	var d := {
		"melds": [[TileId.W2, TileId.W3, TileId.W4]],
		"pair": TileId.S5,
	}
	assert_eq(WaitFu.fu_for_wait(d, TileId.W3), 2, "嵌 3")

func test_kanchan_5_in_456():
	# 46 等 5：分解 [4,5,6]，winning=5
	var d := {
		"melds": [[TileId.T4, TileId.T5, TileId.T6]],
		"pair": TileId.S5,
	}
	assert_eq(WaitFu.fu_for_wait(d, TileId.T5), 2, "嵌 5")

# ---- 双面 ----

func test_ryanmen_low_side():
	# 23 等 1：分解 [1,2,3]，winning=1
	var d := {
		"melds": [[TileId.W1, TileId.W2, TileId.W3]],
		"pair": TileId.S5,
	}
	assert_eq(WaitFu.fu_for_wait(d, TileId.W1), 0, "双面等 1（来自 23）")

func test_ryanmen_high_side_8():
	# 67 等 8：分解 [6,7,8]，winning=8
	var d := {
		"melds": [[TileId.W6, TileId.W7, TileId.W8]],
		"pair": TileId.S5,
	}
	assert_eq(WaitFu.fu_for_wait(d, TileId.W8), 0, "双面等 8（来自 67）")

func test_ryanmen_middle_45_wait_36():
	# 45 等 3 或 6：分解 [3,4,5]，winning=3
	var d := {
		"melds": [[TileId.W3, TileId.W4, TileId.W5]],
		"pair": TileId.S5,
	}
	assert_eq(WaitFu.fu_for_wait(d, TileId.W3), 0, "双面等 3（来自 45）")

# ---- 双碰 ----

func test_shanpon_triplet_simple():
	# 55+33 听双碰：分解里有刻子 [5m,5m,5m] + 雀头 33s，winning=5m
	# 关键：其他 meld 不能含 W5，否则 winning 同时能完成嵌张/边张被 max 选走
	var d := {
		"melds": [
			[TileId.W5, TileId.W5, TileId.W5],
			[TileId.T1, TileId.T2, TileId.T3],
			[TileId.T4, TileId.T5, TileId.T6],
			[TileId.S7, TileId.S8, TileId.S9],
		],
		"pair": TileId.S3,
	}
	assert_eq(WaitFu.fu_for_wait(d, TileId.W5), 0, "双碰 0 fu")

func test_shanpon_yaochu_triplet():
	# 11+EE 双碰，winning=W1：分解里有 [1,1,1] 刻子
	var d := {
		"melds": [
			[TileId.W1, TileId.W1, TileId.W1],
			[TileId.W4, TileId.W5, TileId.W6],
			[TileId.W7, TileId.W8, TileId.W9],
			[TileId.T2, TileId.T3, TileId.T4],
		],
		"pair": TileId.E,
	}
	assert_eq(WaitFu.fu_for_wait(d, TileId.W1), 0, "双碰 0 fu (即使刻子是幺九)")
