extends GutTest

func _make_wc(hand_ids: Array, winning_id: int, melds: Array[Meld] = [] as Array[Meld]) -> WinContext:
	var hand := Hand.new()
	for tid in hand_ids:
		hand.add(Tile.new(tid))
	var winning := Tile.new(winning_id)
	var ctx := GameContext.new()
	var wp := WinPattern.detect(hand, melds, winning)
	return WinContext.new(hand, melds, winning, wp, ctx)

func test_one_two_three_four_five_six_seven_eight_nine_man():
	# 123m 456m 789m + 234p + 11s waiting 1s
	var hand_ids := [
		TileId.W1, TileId.W2, TileId.W3,
		TileId.W4, TileId.W5, TileId.W6,
		TileId.W7, TileId.W8, TileId.W9,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S1,
	]
	var e := Ittsu.detect(_make_wc(hand_ids, TileId.S1))
	assert_not_null(e)
	assert_eq(e.han, 2)

func test_missing_one_segment_returns_null():
	# 123m 456m only, missing 789m
	var hand_ids := [
		TileId.W1, TileId.W2, TileId.W3,
		TileId.W4, TileId.W5, TileId.W6,
		TileId.T7, TileId.T8, TileId.T9,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S1,
	]
	assert_null(Ittsu.detect(_make_wc(hand_ids, TileId.S1)))

func test_open_ittsu_han_minus_one():
	# 1 chi opens; if 1-4-7 still complete -> han = 1
	var hand_ids := [
		TileId.W4, TileId.W5, TileId.W6,
		TileId.W7, TileId.W8, TileId.W9,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S1,
	]
	var chi := Meld.make_chi([
		Tile.new(TileId.W1), Tile.new(TileId.W2), Tile.new(TileId.W3)
	], 0)
	var e := Ittsu.detect(_make_wc(hand_ids, TileId.S1, [chi] as Array[Meld]))
	assert_not_null(e)
	assert_eq(e.han, 1)
