extends GutTest

func _make_wc(hand_ids: Array, winning_id: int, melds: Array[Meld] = [] as Array[Meld]) -> WinContext:
	var hand := Hand.new()
	for tid in hand_ids:
		hand.add(Tile.new(tid))
	var winning := Tile.new(winning_id)
	var ctx := GameContext.new()
	var wp := WinPattern.detect(hand, melds, winning)
	return WinContext.new(hand, melds, winning, wp, ctx)

func test_honchanta_with_honor_pair_concealed():
	# 123m 789p 123s 789s + EE waiting E
	var hand_ids := [
		TileId.W1, TileId.W2, TileId.W3,
		TileId.T7, TileId.T8, TileId.T9,
		TileId.S1, TileId.S2, TileId.S3,
		TileId.S7, TileId.S8, TileId.S9,
		TileId.E,
	]
	var e := Honchanta.detect(_make_wc(hand_ids, TileId.E))
	assert_not_null(e)
	assert_eq(e.han, 2)

func test_honchanta_no_honor_returns_junchan_territory():
	# All terminals only (Junchan, not Honchanta-by-honor) — Honchanta still matches if every meld含幺九 and at least 1 顺子
	# Actually Honchanta detects this hand too — Junchan is upper, exclusion in evaluator
	# Test: Honchanta should still return entry on Junchan-shaped hand
	var hand_ids := [
		TileId.W1, TileId.W2, TileId.W3,
		TileId.T7, TileId.T8, TileId.T9,
		TileId.S1, TileId.S2, TileId.S3,
		TileId.S7, TileId.S8, TileId.S9,
		TileId.W1,
	]
	var e := Honchanta.detect(_make_wc(hand_ids, TileId.W1))
	assert_not_null(e, "Junchan 型也是 Honchanta 子集；互斥由 evaluator 处理")

func test_no_terminal_in_meld_returns_null():
	# 234m has no 1/9 → fails
	var hand_ids := [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T7, TileId.T8, TileId.T9,
		TileId.S1, TileId.S2, TileId.S3,
		TileId.S7, TileId.S8, TileId.S9,
		TileId.E, TileId.E,
	]
	assert_null(Honchanta.detect(_make_wc(hand_ids, TileId.E)))

func test_simple_pair_returns_null():
	var hand_ids := [
		TileId.W1, TileId.W2, TileId.W3,
		TileId.T7, TileId.T8, TileId.T9,
		TileId.S1, TileId.S2, TileId.S3,
		TileId.S7, TileId.S8, TileId.S9,
		TileId.W5,
	]
	assert_null(Honchanta.detect(_make_wc(hand_ids, TileId.W5)))
