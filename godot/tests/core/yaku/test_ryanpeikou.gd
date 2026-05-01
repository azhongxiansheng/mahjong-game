extends GutTest

func _make_wc(hand_ids: Array, winning_id: int) -> WinContext:
	var hand := Hand.new()
	for tid in hand_ids:
		hand.add(Tile.new(tid))
	var winning := Tile.new(winning_id)
	var ctx := GameContext.new()
	var wp := WinPattern.detect(hand, [] as Array[Meld], winning)
	return WinContext.new(hand, [] as Array[Meld], winning, wp, ctx)

func test_two_identical_sequence_pairs():
	# 234m 234m 678p 678p 11s waiting 1s
	var hand_ids := [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T6, TileId.T7, TileId.T8,
		TileId.T6, TileId.T7, TileId.T8,
		TileId.S1,
	]
	var e := Ryanpeikou.detect(_make_wc(hand_ids, TileId.S1))
	assert_not_null(e)
	assert_eq(e.han, 3)

func test_one_pair_returns_null():
	var hand_ids := [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7,
		TileId.S1, TileId.S1,
	]
	assert_null(Ryanpeikou.detect(_make_wc(hand_ids, TileId.S5)))
