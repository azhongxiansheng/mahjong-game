extends GutTest

const YAOCHU_13: Array = [
	TileId.W1, TileId.W9, TileId.T1, TileId.T9, TileId.S1, TileId.S9,
	TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N,
	TileId.HAKU, TileId.HATSU, TileId.CHUN,
]

func test_standard_kokushi_with_extra_w1():
	var ids := YAOCHU_13.duplicate()
	ids.append(TileId.W1)  # W1 成为对子
	ids.sort()
	var r := KokushiDetector.detect(ids)
	assert_true(r.is_kokushi)
	assert_false(r.is_thirteen_wait, "对子是 W1，不是 13 面")

func test_thirteen_wait_with_extra_yaochu():
	var ids := YAOCHU_13.duplicate()
	ids.append(TileId.CHUN)
	ids.sort()
	var r := KokushiDetector.detect(ids)
	assert_true(r.is_kokushi)

func test_missing_yaochu_is_not_kokushi():
	var ids := YAOCHU_13.duplicate()
	ids.remove_at(0)  # 缺 W1
	ids.append(TileId.W9)
	ids.append(TileId.W9)
	ids.sort()
	var r := KokushiDetector.detect(ids)
	assert_false(r.is_kokushi)

func test_simple_tile_in_hand_is_not_kokushi():
	var ids := YAOCHU_13.duplicate()
	ids.append(TileId.W5)  # 中张混入
	ids.sort()
	var r := KokushiDetector.detect(ids)
	assert_false(r.is_kokushi)

func test_thirteen_wait_with_winning_tile_param():
	# 听 13 面：手牌 13 张正好是 13 种幺九各 1
	var hand_ids := YAOCHU_13.duplicate()
	hand_ids.sort()
	var r := KokushiDetector.detect_with_winning(hand_ids, TileId.W1)
	assert_true(r.is_kokushi)
	assert_true(r.is_thirteen_wait)

func test_normal_kokushi_with_winning_tile_not_thirteen_wait():
	# 手牌 13 张：12 种幺九各 1 + 1 种 2 张；摸到那个种类外的牌 = 单骑听
	var hand_ids: Array = [
		TileId.W1, TileId.W1,  # 对子
		TileId.W9, TileId.T1, TileId.T9, TileId.S1, TileId.S9,
		TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N,
		TileId.HAKU, TileId.HATSU,
	]
	hand_ids.sort()
	var r := KokushiDetector.detect_with_winning(hand_ids, TileId.CHUN)
	assert_true(r.is_kokushi)
	assert_false(r.is_thirteen_wait)
