extends GutTest

func _make_hand_from_ids(ids: Array) -> Hand:
	var h := Hand.new()
	for tid in ids:
		h.add(Tile.new(tid))
	return h

func test_standard_win_no_melds():
	# 手 13: 234m 567p 678s 234s 1p；和牌张 1p
	var hand := _make_hand_from_ids([
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.T1,
	])
	var winning := Tile.new(TileId.T1)
	var r := WinPattern.detect(hand, [] as Array[Meld], winning)
	assert_true(r.is_winning)
	assert_false(r.is_chiitoi)
	assert_false(r.is_kokushi)
	assert_gt(r.standard_decompositions.size(), 0)

func test_standard_win_with_pon_meld():
	# 副露 1 个东碰；手剩 10 + 和牌张 1
	var hand := _make_hand_from_ids([
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.T1,
	])
	var east_pon := Meld.make_pon([
		Tile.new(TileId.E), Tile.new(TileId.E), Tile.new(TileId.E)
	], 0)
	var winning := Tile.new(TileId.T1)
	var r := WinPattern.detect(hand, [east_pon] as Array[Meld], winning)
	assert_true(r.is_winning)
	assert_gt(r.standard_decompositions.size(), 0)

func test_chiitoi_win():
	var hand := _make_hand_from_ids([
		TileId.W1, TileId.W1,
		TileId.W3, TileId.W3,
		TileId.T2, TileId.T2,
		TileId.T9, TileId.T9,
		TileId.S5, TileId.S5,
		TileId.E, TileId.E,
		TileId.HAKU,
	])
	var winning := Tile.new(TileId.HAKU)
	var r := WinPattern.detect(hand, [] as Array[Meld], winning)
	assert_true(r.is_winning)
	assert_true(r.is_chiitoi)

func test_kokushi_win_normal():
	var hand := _make_hand_from_ids([
		TileId.W1, TileId.W9, TileId.T1, TileId.T9, TileId.S1, TileId.S9,
		TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N,
		TileId.HAKU, TileId.HATSU, TileId.CHUN,
	])
	var winning := Tile.new(TileId.W1)  # W1 単騎
	var r := WinPattern.detect(hand, [] as Array[Meld], winning)
	assert_true(r.is_winning)
	assert_true(r.is_kokushi)
	assert_true(r.is_thirteen_wait)

func test_not_winning_returns_false():
	var hand := _make_hand_from_ids([
		TileId.W1, TileId.W3, TileId.W5, TileId.W7, TileId.W9,
		TileId.T1, TileId.T3, TileId.T5, TileId.T7, TileId.T9,
		TileId.S1, TileId.S3, TileId.S5,
	])
	var winning := Tile.new(TileId.S7)
	var r := WinPattern.detect(hand, [] as Array[Meld], winning)
	assert_false(r.is_winning)

func test_meld_count_must_match():
	# 副露 1 个 + 手 13 = 总 16 不合法
	var hand := _make_hand_from_ids([
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.T1,
	])
	var east_pon := Meld.make_pon([
		Tile.new(TileId.E), Tile.new(TileId.E), Tile.new(TileId.E)
	], 0)
	var winning := Tile.new(TileId.T1)
	var r := WinPattern.detect(hand, [east_pon] as Array[Meld], winning)
	assert_false(r.is_winning, "総牌数 17 != 14，应拒绝")
