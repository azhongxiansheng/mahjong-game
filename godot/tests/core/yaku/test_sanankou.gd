extends GutTest

func _make_wc(hand_ids: Array, winning_id: int, is_tsumo: bool, melds: Array[Meld] = [] as Array[Meld]) -> WinContext:
	var hand := Hand.new()
	for tid in hand_ids:
		hand.add(Tile.new(tid))
	var winning := Tile.new(winning_id)
	var ctx := GameContext.new()
	ctx.is_tsumo = is_tsumo
	var wp := WinPattern.detect(hand, melds, winning)
	return WinContext.new(hand, melds, winning, wp, ctx)

func test_three_concealed_triplets_tsumo():
	# 111m 222m 333m + 234p + 55s waiting 5s, tsumo
	var hand_ids := [
		TileId.W1, TileId.W1, TileId.W1,
		TileId.W2, TileId.W2, TileId.W2,
		TileId.W3, TileId.W3, TileId.W3,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S5,
	]
	var e := Sanankou.detect(_make_wc(hand_ids, TileId.S5, true))
	assert_not_null(e)
	assert_eq(e.han, 2)

func test_only_two_concealed_returns_null():
	var hand_ids := [
		TileId.W1, TileId.W1, TileId.W1,
		TileId.W2, TileId.W2, TileId.W2,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S5, TileId.S6, TileId.S7,
		TileId.S5,
	]
	assert_null(Sanankou.detect(_make_wc(hand_ids, TileId.S5, true)))

func test_ron_on_third_triplet_only_two_concealed():
	# 111m 222m 333m + 234p + 55s, ron on 3m (third triplet completed by ron -> that triplet is open)
	# 暗刻 = 111m + 222m = 2 暗刻 only -> 三暗刻不成立
	var hand_ids := [
		TileId.W1, TileId.W1, TileId.W1,
		TileId.W2, TileId.W2, TileId.W2,
		TileId.W3, TileId.W3,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S5, TileId.S5,
	]
	assert_null(Sanankou.detect(_make_wc(hand_ids, TileId.W3, false)), "ron 完成的刻子算明刻")
