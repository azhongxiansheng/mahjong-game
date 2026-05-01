extends GutTest

func _make_wc(hand_ids: Array, winning_id: int, melds: Array[Meld] = [] as Array[Meld]) -> WinContext:
	var hand := Hand.new()
	for tid in hand_ids:
		hand.add(Tile.new(tid))
	var winning := Tile.new(winning_id)
	var ctx := GameContext.new()
	var wp := WinPattern.detect(hand, melds, winning)
	return WinContext.new(hand, melds, winning, wp, ctx)

func test_three_suits_same_start_concealed():
	# 234m 234p 234s 567s 11p waiting 1p
	var hand_ids := [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.S5, TileId.S6, TileId.S7,
		TileId.T1,
	]
	var e := SanshokuDoujun.detect(_make_wc(hand_ids, TileId.T1))
	assert_not_null(e)
	assert_eq(e.han, 2)

func test_only_two_suits_returns_null():
	# 234m 234p only — missing 234s
	var hand_ids := [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.T1,
	]
	assert_null(SanshokuDoujun.detect(_make_wc(hand_ids, TileId.T1)))

func test_open_three_suits_han_minus_one():
	# Same 234 across 3 suits, but with one chi (open) -> 1 han
	var hand_ids := [
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.S5, TileId.S6, TileId.S7,
		TileId.T1,
	]
	var chi := Meld.make_chi([
		Tile.new(TileId.W2), Tile.new(TileId.W3), Tile.new(TileId.W4)
	], 0)
	var e := SanshokuDoujun.detect(_make_wc(hand_ids, TileId.T1, [chi] as Array[Meld]))
	assert_not_null(e)
	assert_eq(e.han, 1, "副露后 -1 番")
