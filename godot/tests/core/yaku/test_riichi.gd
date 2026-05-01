extends GutTest

func _make_wc(is_riichi: bool, is_double: bool = false) -> WinContext:
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
	ctx.is_riichi = is_riichi
	ctx.is_double_riichi = is_double
	var wp := WinPattern.detect(hand, [] as Array[Meld], winning)
	return WinContext.new(hand, [] as Array[Meld], winning, wp, ctx)

func test_riichi_when_declared_returns_entry():
	var e := Riichi.detect(_make_wc(true))
	assert_not_null(e)
	assert_eq(e.yaku_id, YakuId.RIICHI)
	assert_eq(e.han, 1)

func test_riichi_when_not_declared_returns_null():
	assert_null(Riichi.detect(_make_wc(false)))

func test_riichi_does_not_fire_when_double_riichi():
	assert_null(Riichi.detect(_make_wc(true, true)))
