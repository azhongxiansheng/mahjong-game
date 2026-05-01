extends GutTest

func _make_wc(hand_ids: Array, winning_id: int, melds: Array[Meld] = [] as Array[Meld]) -> WinContext:
	var hand := Hand.new()
	for tid in hand_ids:
		hand.add(Tile.new(tid))
	var winning := Tile.new(winning_id)
	var ctx := GameContext.new()
	ctx.bakaze = TileId.E
	ctx.jikaze = TileId.S_WIND
	var wp := WinPattern.detect(hand, melds, winning)
	return WinContext.new(hand, melds, winning, wp, ctx)

func test_one_identical_sequence_pair():
	# 234m 234m 567p 678s 11s waiting 5s -> 1 iipeikou
	var hand_ids := [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7,
		TileId.S1, TileId.S1,
	]
	var e := Iipeikou.detect(_make_wc(hand_ids, TileId.S5))
	assert_not_null(e)
	assert_eq(e.han, 1)

func test_no_identical_sequence_returns_null():
	# 234m 567p 678s 234s 11p waiting 1p
	var hand_ids := [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.T1,
	]
	assert_null(Iipeikou.detect(_make_wc(hand_ids, TileId.T1)))

func test_open_hand_returns_null():
	var hand_ids := [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7,
		TileId.S1, TileId.S1,
	]
	var chi := Meld.make_chi([
		Tile.new(TileId.W2), Tile.new(TileId.W3), Tile.new(TileId.W4)
	], 0)
	assert_null(Iipeikou.detect(_make_wc(hand_ids, TileId.S5, [chi] as Array[Meld])))

func test_two_identical_pairs_returns_null():
	# 234m 234m 678p 678p 11s waiting 1s — 2 pairs = ryanpeikou not iipeikou
	var hand_ids := [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T6, TileId.T7, TileId.T8,
		TileId.T6, TileId.T7, TileId.T8,
		TileId.S1,
	]
	assert_null(Iipeikou.detect(_make_wc(hand_ids, TileId.S1)), "二杯口型不应返回一杯口")
