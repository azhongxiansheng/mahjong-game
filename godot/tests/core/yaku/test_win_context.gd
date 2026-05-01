extends GutTest

func _make_hand(ids: Array) -> Hand:
	var h := Hand.new()
	for tid in ids:
		h.add(Tile.new(tid))
	return h

func test_construct_with_winning_hand():
	var hand := _make_hand([
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.T1,
	])
	var winning := Tile.new(TileId.T1)
	var ctx := GameContext.new()
	var wp_result := WinPattern.detect(hand, [] as Array[Meld], winning)
	var wc := WinContext.new(hand, [] as Array[Meld], winning, wp_result, ctx)
	assert_true(wc.win_result.is_winning)
	assert_true(wc.is_menzen())
	assert_eq(wc.winning_tile.id, TileId.T1)

func test_is_menzen_with_meld():
	var hand := _make_hand([
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.T1,
	])
	var pon := Meld.make_pon([
		Tile.new(TileId.E), Tile.new(TileId.E), Tile.new(TileId.E)
	], 0)
	var winning := Tile.new(TileId.T1)
	var ctx := GameContext.new()
	var wp_result := WinPattern.detect(hand, [pon] as Array[Meld], winning)
	var wc := WinContext.new(hand, [pon] as Array[Meld], winning, wp_result, ctx)
	assert_false(wc.is_menzen())
