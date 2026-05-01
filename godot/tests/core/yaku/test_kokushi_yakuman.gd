extends GutTest

func _make_wc(hand_ids: Array, winning_id: int) -> WinContext:
	var hand := Hand.new()
	for tid in hand_ids:
		hand.add(Tile.new(tid))
	var winning := Tile.new(winning_id)
	var ctx := GameContext.new()
	var wp := WinPattern.detect(hand, [] as Array[Meld], winning)
	return WinContext.new(hand, [] as Array[Meld], winning, wp, ctx)

func test_kokushi_single_yakuman():
	# 13 种幺九齐全 + 一张重复（非 13 面）
	# 起手 13 张：W1 W9 T1 T9 S1 S9 E S W N HAKU HATSU CHUN，重复 W1
	# 和牌张 = CHUN（非雀头牌 → 非 13 面）
	# 起手 = W1×2 + W9 T1 T9 S1 S9 E S W N HAKU HATSU CHUN（13 张），和 CHUN 后 CHUN 成对
	var hand_ids := [
		TileId.W1, TileId.W1, TileId.W9,
		TileId.T1, TileId.T9,
		TileId.S1, TileId.S9,
		TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N,
		TileId.HAKU, TileId.HATSU,
	]
	var e := KokushiYakuman.detect(_make_wc(hand_ids, TileId.CHUN))
	assert_not_null(e, "国士無双成立")
	assert_true(e.is_yakuman)
	assert_eq(e.yakuman_multiplier, 1)
	assert_eq(e.yaku_id, YakuId.KOKUSHI)

func test_kokushi_thirteen_wait_double_yakuman():
	# 13 种幺九各 1 张 → 13 面待，和任意一张幺九都成
	var hand_ids := [
		TileId.W1, TileId.W9,
		TileId.T1, TileId.T9,
		TileId.S1, TileId.S9,
		TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N,
		TileId.HAKU, TileId.HATSU, TileId.CHUN,
	]
	var e := KokushiYakuman.detect(_make_wc(hand_ids, TileId.W1))
	assert_not_null(e, "国士 13 面成立")
	assert_eq(e.yaku_id, YakuId.KOKUSHI_13)
	assert_eq(e.yakuman_multiplier, 2)

func test_non_kokushi_returns_null():
	# 普通 4 面子 + 1 雀头：不是国士
	var hand_ids := [
		TileId.W1, TileId.W2, TileId.W3,
		TileId.W4, TileId.W5, TileId.W6,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S5, TileId.S6, TileId.S7,
		TileId.S1,
	]
	assert_null(KokushiYakuman.detect(_make_wc(hand_ids, TileId.S1)))
