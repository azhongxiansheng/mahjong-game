extends GutTest

func _make_wc(hand_ids: Array, winning_id: int) -> WinContext:
	var hand := Hand.new()
	for tid in hand_ids:
		hand.add(Tile.new(tid))
	var winning := Tile.new(winning_id)
	var ctx := GameContext.new()
	var wp := WinPattern.detect(hand, [] as Array[Meld], winning)
	return WinContext.new(hand, [] as Array[Meld], winning, wp, ctx)

func test_all_terminals_4_triplets_pair():
	# 111m 999m 111p 999s + 99p (雀头) — hand 13 张 + 和 T9
	var hand_ids := [
		TileId.W1, TileId.W1, TileId.W1,
		TileId.W9, TileId.W9, TileId.W9,
		TileId.T1, TileId.T1, TileId.T1,
		TileId.S9, TileId.S9, TileId.S9,
		TileId.T9,
	]
	var e := Chinroutou.detect(_make_wc(hand_ids, TileId.T9))
	assert_not_null(e, "清老頭成立")
	assert_eq(e.yakuman_multiplier, 1)

func test_with_honor_returns_null():
	# 含字牌 → 不是清老頭 (hand 13 + winning 1)
	var hand_ids := [
		TileId.W1, TileId.W1, TileId.W1,
		TileId.W9, TileId.W9, TileId.W9,
		TileId.T1, TileId.T1, TileId.T1,
		TileId.HAKU, TileId.HAKU, TileId.HAKU,
		TileId.S1,
	]
	assert_null(Chinroutou.detect(_make_wc(hand_ids, TileId.S1)), "含字牌不是清老頭")

func test_with_middle_tile_returns_null():
	# 含中张 → 不是清老頭 (hand 13 + winning 1)
	var hand_ids := [
		TileId.W1, TileId.W1, TileId.W1,
		TileId.W9, TileId.W9, TileId.W9,
		TileId.T1, TileId.T1, TileId.T1,
		TileId.S5, TileId.S5, TileId.S5,
		TileId.S9,
	]
	assert_null(Chinroutou.detect(_make_wc(hand_ids, TileId.S9)), "含中张不是清老頭")
