extends GutTest

func _make_wc(is_haitei: bool, is_tsumo: bool) -> WinContext:
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
	ctx.is_haitei = is_haitei
	ctx.is_tsumo = is_tsumo
	var wp := WinPattern.detect(hand, [] as Array[Meld], winning)
	return WinContext.new(hand, [] as Array[Meld], winning, wp, ctx)

func test_haitei_with_tsumo():
	var e := Haitei.detect(_make_wc(true, true))
	assert_not_null(e)

func test_haitei_without_tsumo_returns_null():
	assert_null(Haitei.detect(_make_wc(true, false)), "海底捞月必须是自摸")
