extends GutTest

# 雀头符：
#   数牌 / 非役风字牌 → 0
#   场风 → +2
#   自风 → +2
#   三元（白发中）→ +2
#   连风（场风==自风==雀头）→ +2（取天凤标准；plan assumption #3）

func test_simple_pair_zero():
	# 数牌 5万 雀头
	assert_eq(PairFu.fu_for_pair(TileId.W5, TileId.E, TileId.S_WIND), 0)

func test_yaochu_number_pair_zero():
	# 1m 雀头不是役牌（幺九数牌不加雀头符）
	assert_eq(PairFu.fu_for_pair(TileId.W1, TileId.E, TileId.S_WIND), 0)

func test_round_wind_pair_two():
	# 东 1 局：场风东，雀头东 → +2
	assert_eq(PairFu.fu_for_pair(TileId.E, TileId.E, TileId.S_WIND), 2)

func test_seat_wind_pair_two():
	# 自风南，雀头南 → +2
	assert_eq(PairFu.fu_for_pair(TileId.S_WIND, TileId.E, TileId.S_WIND), 2)

func test_non_yaku_wind_pair_zero():
	# 场风东、自风南，雀头西/北 → 0
	assert_eq(PairFu.fu_for_pair(TileId.W_WIND, TileId.E, TileId.S_WIND), 0)
	assert_eq(PairFu.fu_for_pair(TileId.N, TileId.E, TileId.S_WIND), 0)

func test_dragon_pair_two_each():
	assert_eq(PairFu.fu_for_pair(TileId.HAKU, TileId.E, TileId.S_WIND), 2)
	assert_eq(PairFu.fu_for_pair(TileId.HATSU, TileId.E, TileId.S_WIND), 2)
	assert_eq(PairFu.fu_for_pair(TileId.CHUN, TileId.E, TileId.S_WIND), 2)

func test_double_wind_pair_still_two():
	# 庄家东 1 局：场风==自风==雀头==东 → +2（连风按 +2，assumption #3）
	assert_eq(PairFu.fu_for_pair(TileId.E, TileId.E, TileId.E), 2)

func test_dragon_independent_of_wind():
	# 三元牌符不依赖场/自风
	assert_eq(PairFu.fu_for_pair(TileId.HAKU, TileId.S_WIND, TileId.W_WIND), 2)
