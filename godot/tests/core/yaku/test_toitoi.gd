extends GutTest

func _make_wc(hand_ids: Array, winning_id: int, melds: Array[Meld] = [] as Array[Meld]) -> WinContext:
	var hand := Hand.new()
	for tid in hand_ids:
		hand.add(Tile.new(tid))
	var winning := Tile.new(winning_id)
	var ctx := GameContext.new()
	var wp := WinPattern.detect(hand, melds, winning)
	return WinContext.new(hand, melds, winning, wp, ctx)

func test_all_triplets_concealed():
	# 111m 222m 333m 444m 55m waiting 5m
	var hand_ids := [
		TileId.W1, TileId.W1, TileId.W1,
		TileId.W2, TileId.W2, TileId.W2,
		TileId.W3, TileId.W3, TileId.W3,
		TileId.W4, TileId.W4, TileId.W4,
		TileId.W5,
	]
	var e := Toitoi.detect(_make_wc(hand_ids, TileId.W5))
	assert_not_null(e)
	assert_eq(e.han, 2)

func test_with_chi_returns_null():
	var hand_ids := [
		TileId.W1, TileId.W1, TileId.W1,
		TileId.T2, TileId.T2, TileId.T2,
		TileId.S3, TileId.S3, TileId.S3,
		TileId.S5,
	]
	var chi := Meld.make_chi([
		Tile.new(TileId.W2), Tile.new(TileId.W3), Tile.new(TileId.W4)
	], 0)
	assert_null(Toitoi.detect(_make_wc(hand_ids, TileId.S5, [chi] as Array[Meld])))
