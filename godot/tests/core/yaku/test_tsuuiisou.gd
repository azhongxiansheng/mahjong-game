extends GutTest

func _make_wc(hand_ids: Array, winning_id: int) -> WinContext:
	var hand := Hand.new()
	for tid in hand_ids:
		hand.add(Tile.new(tid))
	var winning := Tile.new(winning_id)
	var ctx := GameContext.new()
	var wp := WinPattern.detect(hand, [] as Array[Meld], winning)
	return WinContext.new(hand, [] as Array[Meld], winning, wp, ctx)

func test_all_honors_4_triplets_pair():
	# 东东东 南南南 西西西 北北 + 白白白
	var hand_ids := [
		TileId.E, TileId.E, TileId.E,
		TileId.S_WIND, TileId.S_WIND, TileId.S_WIND,
		TileId.W_WIND, TileId.W_WIND, TileId.W_WIND,
		TileId.N, TileId.N,
		TileId.HAKU, TileId.HAKU,
	]
	var e := Tsuuiisou.detect(_make_wc(hand_ids, TileId.HAKU))
	assert_not_null(e, "全字牌成立")
	assert_eq(e.yakuman_multiplier, 1)

func test_one_number_tile_returns_null():
	var hand_ids := [
		TileId.E, TileId.E, TileId.E,
		TileId.S_WIND, TileId.S_WIND, TileId.S_WIND,
		TileId.W_WIND, TileId.W_WIND,
		TileId.HAKU, TileId.HAKU, TileId.HAKU,
		TileId.W2, TileId.W3,
	]
	assert_null(Tsuuiisou.detect(_make_wc(hand_ids, TileId.W4)), "含数牌不是字一色")
