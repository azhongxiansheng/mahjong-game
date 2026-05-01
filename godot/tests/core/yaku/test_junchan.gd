extends GutTest

func _make_wc(hand_ids: Array, winning_id: int) -> WinContext:
	var hand := Hand.new()
	for tid in hand_ids:
		hand.add(Tile.new(tid))
	var winning := Tile.new(winning_id)
	var ctx := GameContext.new()
	var wp := WinPattern.detect(hand, [] as Array[Meld], winning)
	return WinContext.new(hand, [] as Array[Meld], winning, wp, ctx)

func test_junchan_no_honor():
	# 123m 789p 123s 789s 11m
	var hand_ids := [
		TileId.W1, TileId.W2, TileId.W3,
		TileId.T7, TileId.T8, TileId.T9,
		TileId.S1, TileId.S2, TileId.S3,
		TileId.S7, TileId.S8, TileId.S9,
		TileId.W1,
	]
	var e := Junchan.detect(_make_wc(hand_ids, TileId.W1))
	assert_not_null(e)
	assert_eq(e.han, 3)

func test_junchan_with_honor_returns_null():
	var hand_ids := [
		TileId.W1, TileId.W2, TileId.W3,
		TileId.T7, TileId.T8, TileId.T9,
		TileId.S1, TileId.S2, TileId.S3,
		TileId.S7, TileId.S8, TileId.S9,
		TileId.E,
	]
	assert_null(Junchan.detect(_make_wc(hand_ids, TileId.E)))
