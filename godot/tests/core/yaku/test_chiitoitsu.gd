extends GutTest

func _make_wc(hand_ids: Array, winning_id: int) -> WinContext:
	var hand := Hand.new()
	for tid in hand_ids:
		hand.add(Tile.new(tid))
	var winning := Tile.new(winning_id)
	var ctx := GameContext.new()
	var wp := WinPattern.detect(hand, [] as Array[Meld], winning)
	return WinContext.new(hand, [] as Array[Meld], winning, wp, ctx)

func test_chiitoitsu_returns_2_han():
	var hand_ids := [
		TileId.W1, TileId.W1,
		TileId.W3, TileId.W3,
		TileId.T2, TileId.T2,
		TileId.T9, TileId.T9,
		TileId.S5, TileId.S5,
		TileId.E, TileId.E,
		TileId.HAKU,
	]
	var e := Chiitoitsu.detect(_make_wc(hand_ids, TileId.HAKU))
	assert_not_null(e)
	assert_eq(e.han, 2)

func test_non_chiitoi_returns_null():
	var hand_ids := [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.S5, TileId.S6, TileId.S7,
		TileId.W2,
	]
	assert_null(Chiitoitsu.detect(_make_wc(hand_ids, TileId.W2)))
