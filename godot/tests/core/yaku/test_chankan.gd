extends GutTest

func _make_wc(is_chankan: bool, is_tsumo: bool) -> WinContext:
	var hand := Hand.new()
	for tid in [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.T1,
	]:
		hand.add(Tile.new(tid))
	var winning := Tile.new(TileId.T1)
	var ctx := GameContext.new()
	ctx.is_chankan = is_chankan
	ctx.is_tsumo = is_tsumo
	var wp := WinPattern.detect(hand, [] as Array[Meld], winning)
	return WinContext.new(hand, [] as Array[Meld], winning, wp, ctx)

func test_chankan_with_ron():
	var e := Chankan.detect(_make_wc(true, false))
	assert_not_null(e)

func test_chankan_with_tsumo_returns_null():
	assert_null(Chankan.detect(_make_wc(true, true)), "抢杠必须是荣胡")
