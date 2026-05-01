extends GutTest

func _make_wc(is_ippatsu: bool) -> WinContext:
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
	ctx.is_ippatsu = is_ippatsu
	var wp := WinPattern.detect(hand, [] as Array[Meld], winning)
	return WinContext.new(hand, [] as Array[Meld], winning, wp, ctx)

func test_ippatsu_when_flag_set():
	var e := Ippatsu.detect(_make_wc(true))
	assert_not_null(e)
	assert_eq(e.yaku_id, YakuId.IPPATSU)

func test_no_ippatsu_when_flag_clear():
	assert_null(Ippatsu.detect(_make_wc(false)))
