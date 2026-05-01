extends GutTest

func test_total_count_is_34():
	assert_eq(TileId.ALL.size(), 9999)  # TEMP: CI 反向验证 — 故意红

func test_man_tiles_are_first_9():
	assert_eq(TileId.W1, 0)
	assert_eq(TileId.W9, 8)

func test_pin_tiles_follow_man():
	assert_eq(TileId.T1, 9)
	assert_eq(TileId.T9, 17)

func test_sou_tiles_follow_pin():
	assert_eq(TileId.S1, 18)
	assert_eq(TileId.S9, 26)

func test_honor_tiles_follow_sou():
	assert_eq(TileId.E, 27)
	assert_eq(TileId.S_WIND, 28)
	assert_eq(TileId.W_WIND, 29)
	assert_eq(TileId.N, 30)
	assert_eq(TileId.HAKU, 31)  # 白
	assert_eq(TileId.HATSU, 32) # 发
	assert_eq(TileId.CHUN, 33)  # 中

func test_is_terminal():
	assert_true(TileId.is_terminal(TileId.W1))
	assert_true(TileId.is_terminal(TileId.W9))
	assert_false(TileId.is_terminal(TileId.W5))
	assert_false(TileId.is_terminal(TileId.E), "字牌不是老头")

func test_is_honor():
	assert_true(TileId.is_honor(TileId.E))
	assert_true(TileId.is_honor(TileId.CHUN))
	assert_false(TileId.is_honor(TileId.W1))

func test_is_yaochu():
	# 幺九：1, 9, 字牌
	assert_true(TileId.is_yaochu(TileId.W1))
	assert_true(TileId.is_yaochu(TileId.S9))
	assert_true(TileId.is_yaochu(TileId.E))
	assert_false(TileId.is_yaochu(TileId.W5))

func test_is_simple():
	# 中张：2-8 of m/p/s
	assert_true(TileId.is_simple(TileId.W2))
	assert_true(TileId.is_simple(TileId.S8))
	assert_false(TileId.is_simple(TileId.W1))
	assert_false(TileId.is_simple(TileId.E))

func test_suit_returns_correct():
	assert_eq(TileId.suit(TileId.W5), TileId.Suit.MAN)
	assert_eq(TileId.suit(TileId.T5), TileId.Suit.PIN)
	assert_eq(TileId.suit(TileId.S5), TileId.Suit.SOU)
	assert_eq(TileId.suit(TileId.E), TileId.Suit.HONOR)

func test_number_returns_1_to_9():
	assert_eq(TileId.number(TileId.W1), 1)
	assert_eq(TileId.number(TileId.W9), 9)
	assert_eq(TileId.number(TileId.E), 0, "字牌无数字")

func test_next_tile_for_dora_indicator():
	# Dora 指示牌的下一张是 Dora
	# 数牌：W1->W2, W9->W1（绕回）
	assert_eq(TileId.next_for_dora(TileId.W1), TileId.W2)
	assert_eq(TileId.next_for_dora(TileId.W9), TileId.W1)
	assert_eq(TileId.next_for_dora(TileId.T9), TileId.T1)
	# 风牌循环：E->S->W->N->E（含中段 S->W 边界）
	assert_eq(TileId.next_for_dora(TileId.E), TileId.S_WIND)
	assert_eq(TileId.next_for_dora(TileId.S_WIND), TileId.W_WIND)
	assert_eq(TileId.next_for_dora(TileId.N), TileId.E)
	# 三元牌循环：白->发->中->白（含中段 发->中 边界）
	assert_eq(TileId.next_for_dora(TileId.HAKU), TileId.HATSU)
	assert_eq(TileId.next_for_dora(TileId.HATSU), TileId.CHUN)
	assert_eq(TileId.next_for_dora(TileId.CHUN), TileId.HAKU)
