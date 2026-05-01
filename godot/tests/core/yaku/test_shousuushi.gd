extends GutTest

func _make_wc(hand_ids: Array, winning_id: int, melds: Array[Meld] = [] as Array[Meld]) -> WinContext:
	var hand := Hand.new()
	for tid in hand_ids:
		hand.add(Tile.new(tid))
	var winning := Tile.new(winning_id)
	var ctx := GameContext.new()
	var wp := WinPattern.detect(hand, melds, winning)
	return WinContext.new(hand, melds, winning, wp, ctx)

func test_three_winds_triplets_one_pair():
	# 东东东 南南南 西西西 北北 + 中中中
	var hand_ids := [
		TileId.E, TileId.E, TileId.E,
		TileId.S_WIND, TileId.S_WIND, TileId.S_WIND,
		TileId.W_WIND, TileId.W_WIND, TileId.W_WIND,
		TileId.N, TileId.N,
		TileId.CHUN, TileId.CHUN,
	]
	var e := Shousuushi.detect(_make_wc(hand_ids, TileId.CHUN))
	assert_not_null(e, "小四喜成立")
	assert_eq(e.yakuman_multiplier, 1)

func test_two_winds_returns_null():
	# 只有 2 风刻 → 不成
	var hand_ids := [
		TileId.E, TileId.E, TileId.E,
		TileId.S_WIND, TileId.S_WIND, TileId.S_WIND,
		TileId.HAKU, TileId.HAKU, TileId.HAKU,
		TileId.W2, TileId.W3, TileId.W4,
		TileId.N,
	]
	assert_null(Shousuushi.detect(_make_wc(hand_ids, TileId.N)), "2 风刻不是小四喜")

func test_with_wind_pon_meld():
	# 副露 1 个东碰 + 暗南刻 + 暗西刻 + 234m + 北北
	var pon_e := Meld.make_pon([Tile.new(TileId.E), Tile.new(TileId.E), Tile.new(TileId.E)], 0)
	var hand_ids := [
		TileId.S_WIND, TileId.S_WIND, TileId.S_WIND,
		TileId.W_WIND, TileId.W_WIND, TileId.W_WIND,
		TileId.W2, TileId.W3, TileId.W4,
		TileId.N,
	]
	var e := Shousuushi.detect(_make_wc(hand_ids, TileId.N, [pon_e] as Array[Meld]))
	assert_not_null(e, "副露东碰也算小四喜")
