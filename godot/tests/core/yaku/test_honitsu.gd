extends GutTest

func _make_wc(hand_ids: Array, winning_id: int) -> WinContext:
	var hand := Hand.new()
	for tid in hand_ids:
		hand.add(Tile.new(tid))
	var winning := Tile.new(winning_id)
	var ctx := GameContext.new()
	var wp := WinPattern.detect(hand, [] as Array[Meld], winning)
	return WinContext.new(hand, [] as Array[Meld], winning, wp, ctx)

func test_honitsu_man_with_honor():
	# 1m only suit, with E pair
	var hand_ids := [
		TileId.W1, TileId.W2, TileId.W3,
		TileId.W4, TileId.W5, TileId.W6,
		TileId.W7, TileId.W8, TileId.W9,
		TileId.W1, TileId.W2, TileId.W3,
		TileId.E,
	]
	var e := Honitsu.detect(_make_wc(hand_ids, TileId.E))
	assert_not_null(e)
	assert_eq(e.han, 3)

func test_chinitsu_returns_null():
	# Pure single suit (no honor) is Chinitsu, not Honitsu
	var hand_ids := [
		TileId.W1, TileId.W1, TileId.W1,
		TileId.W2, TileId.W3, TileId.W4,
		TileId.W5, TileId.W6, TileId.W7,
		TileId.W2, TileId.W3, TileId.W4,
		TileId.W9,
	]
	assert_null(Honitsu.detect(_make_wc(hand_ids, TileId.W9)), "无字牌应是清一色")

func test_two_suits_returns_null():
	var hand_ids := [
		TileId.W1, TileId.W2, TileId.W3,
		TileId.T4, TileId.T5, TileId.T6,
		TileId.W7, TileId.W8, TileId.W9,
		TileId.W1, TileId.W2, TileId.W3,
		TileId.E,
	]
	assert_null(Honitsu.detect(_make_wc(hand_ids, TileId.E)))
