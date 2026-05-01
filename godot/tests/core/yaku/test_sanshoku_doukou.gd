extends GutTest

func _make_wc(hand_ids: Array, winning_id: int) -> WinContext:
	var hand := Hand.new()
	for tid in hand_ids:
		hand.add(Tile.new(tid))
	var winning := Tile.new(winning_id)
	var ctx := GameContext.new()
	var wp := WinPattern.detect(hand, [] as Array[Meld], winning)
	return WinContext.new(hand, [] as Array[Meld], winning, wp, ctx)

func test_three_suits_same_number_triplet():
	# 222m 222p 222s + 678m + 55s waiting 5s
	var hand_ids := [
		TileId.W2, TileId.W2, TileId.W2,
		TileId.T2, TileId.T2, TileId.T2,
		TileId.S2, TileId.S2, TileId.S2,
		TileId.W6, TileId.W7, TileId.W8,
		TileId.S5,
	]
	var e := SanshokuDoukou.detect(_make_wc(hand_ids, TileId.S5))
	assert_not_null(e)
	assert_eq(e.han, 2)

func test_two_suits_returns_null():
	var hand_ids := [
		TileId.W2, TileId.W2, TileId.W2,
		TileId.T2, TileId.T2, TileId.T2,
		TileId.W6, TileId.W7, TileId.W8,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.S5,
	]
	assert_null(SanshokuDoukou.detect(_make_wc(hand_ids, TileId.S5)))
