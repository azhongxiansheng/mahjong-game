extends GutTest

func _make_wc(hand_ids: Array, winning_id: int, melds: Array[Meld] = [] as Array[Meld]) -> WinContext:
	var hand := Hand.new()
	for tid in hand_ids:
		hand.add(Tile.new(tid))
	var winning := Tile.new(winning_id)
	var ctx := GameContext.new()
	var wp := WinPattern.detect(hand, melds, winning)
	return WinContext.new(hand, melds, winning, wp, ctx)

func test_four_winds_all_triplets_double_yakuman():
	# 东东东 南南南 西西西 北北北 + 白白
	var hand_ids := [
		TileId.E, TileId.E, TileId.E,
		TileId.S_WIND, TileId.S_WIND, TileId.S_WIND,
		TileId.W_WIND, TileId.W_WIND, TileId.W_WIND,
		TileId.N, TileId.N, TileId.N,
		TileId.HAKU,
	]
	var e := Daisuushi.detect(_make_wc(hand_ids, TileId.HAKU))
	assert_not_null(e, "大四喜成立")
	assert_eq(e.yakuman_multiplier, 2, "大四喜 = 双倍役満")

func test_three_winds_pair_returns_null():
	# 小四喜 → 不是大四喜
	var hand_ids := [
		TileId.E, TileId.E, TileId.E,
		TileId.S_WIND, TileId.S_WIND, TileId.S_WIND,
		TileId.W_WIND, TileId.W_WIND, TileId.W_WIND,
		TileId.N, TileId.N,
		TileId.CHUN, TileId.CHUN,
	]
	assert_null(Daisuushi.detect(_make_wc(hand_ids, TileId.CHUN)), "小四喜不是大四喜")
