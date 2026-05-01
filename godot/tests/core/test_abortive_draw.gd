extends GutTest

# AbortiveDraw: 5 种途中流局纯判定函数（spec §3.2）
# 1. 四风连打 (suufon renda)
# 2. 九种九牌 (kyuusyu kyuuhai)
# 3. 四杠散了 (suukantsu sanra)
# 4. 四家立直 (suucha riichi)
# 5. 三家和了 (sancha houra)

# ---- 四风连打 ----

func test_suufon_all_east():
	var d := [TileId.E, TileId.E, TileId.E, TileId.E]
	assert_true(AbortiveDraw.is_suufon_renda(d))

func test_suufon_mixed_winds_no():
	var d := [TileId.E, TileId.S_WIND, TileId.E, TileId.E]
	assert_false(AbortiveDraw.is_suufon_renda(d))

func test_suufon_all_dragon_not_wind():
	# 全白板不算 — 必须风牌
	var d := [TileId.HAKU, TileId.HAKU, TileId.HAKU, TileId.HAKU]
	assert_false(AbortiveDraw.is_suufon_renda(d))

func test_suufon_all_man_not_wind():
	var d := [TileId.W1, TileId.W1, TileId.W1, TileId.W1]
	assert_false(AbortiveDraw.is_suufon_renda(d))

# ---- 九种九牌 ----

func test_kyuusyu_with_9_distinct_yaochu():
	# 9 种幺九：W1, W9, T1, T9, S1, S9, E, S_WIND, HAKU + 4 张随便
	var hand := [
		TileId.W1, TileId.W9, TileId.T1, TileId.T9, TileId.S1, TileId.S9,
		TileId.E, TileId.S_WIND, TileId.HAKU,
		TileId.W2, TileId.T5, TileId.S6, TileId.T7,
	]
	assert_true(AbortiveDraw.is_kyuusyu_kyuuhai(hand))

func test_kyuusyu_with_8_distinct_no():
	var hand := [
		TileId.W1, TileId.W9, TileId.T1, TileId.T9, TileId.S1, TileId.S9,
		TileId.E, TileId.S_WIND,  # 8 种
		TileId.W2, TileId.T5, TileId.S6, TileId.T7, TileId.W3,
	]
	assert_false(AbortiveDraw.is_kyuusyu_kyuuhai(hand))

func test_kyuusyu_duplicates_count_once():
	# W1 出现 2 次只算 1 种
	var hand := [
		TileId.W1, TileId.W1, TileId.W9, TileId.T1, TileId.T9, TileId.S1, TileId.S9,
		TileId.E, TileId.S_WIND,  # 8 种 distinct
		TileId.W2, TileId.T5, TileId.S6, TileId.T7,
	]
	assert_false(AbortiveDraw.is_kyuusyu_kyuuhai(hand))

func test_kyuusyu_with_10_distinct():
	var hand := [
		TileId.W1, TileId.W9, TileId.T1, TileId.T9, TileId.S1, TileId.S9,
		TileId.E, TileId.S_WIND, TileId.HAKU, TileId.HATSU,  # 10 种
		TileId.W2, TileId.T5, TileId.S6,
	]
	assert_true(AbortiveDraw.is_kyuusyu_kyuuhai(hand))

# ---- 四杠散了 ----

func test_suukantsu_sanra_4_kan_different_seats():
	assert_true(AbortiveDraw.is_suukantsu_sanra([0, 1, 2, 3]))

func test_suukantsu_sanra_4_kan_same_seat_no():
	# 同 1 人 4 杠 → 四杠子役满，不流局
	assert_false(AbortiveDraw.is_suukantsu_sanra([0, 0, 0, 0]))

func test_suukantsu_sanra_3_kan_no():
	# 不到 4 杠不算
	assert_false(AbortiveDraw.is_suukantsu_sanra([0, 1, 2]))

func test_suukantsu_sanra_4_kan_two_owners():
	# 4 杠分 2 人也算流局
	assert_true(AbortiveDraw.is_suukantsu_sanra([0, 0, 1, 1]))

# ---- 四家立直 ----

func test_suucha_riichi_all_4_riichi():
	assert_true(AbortiveDraw.is_suucha_riichi([true, true, true, true]))

func test_suucha_riichi_3_riichi_no():
	assert_false(AbortiveDraw.is_suucha_riichi([true, true, true, false]))

# ---- 三家和了 ----

func test_sancha_houra_3_ron():
	assert_true(AbortiveDraw.is_sancha_houra(3))

func test_sancha_houra_2_ron_no():
	assert_false(AbortiveDraw.is_sancha_houra(2))

func test_sancha_houra_more_than_3_yes():
	assert_true(AbortiveDraw.is_sancha_houra(4))
