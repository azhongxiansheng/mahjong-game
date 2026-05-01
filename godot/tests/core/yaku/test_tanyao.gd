extends GutTest

func _make_wc(hand_ids: Array, winning_id: int, melds: Array[Meld] = [] as Array[Meld]) -> WinContext:
	var hand := Hand.new()
	for tid in hand_ids:
		hand.add(Tile.new(tid))
	var winning := Tile.new(winning_id)
	var ctx := GameContext.new()
	var wp := WinPattern.detect(hand, melds, winning)
	return WinContext.new(hand, melds, winning, wp, ctx)

func test_all_simples():
	# 234m 234p 234s 567s 22m waiting 2m
	var hand_ids := [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.S5, TileId.S6, TileId.S7,
		TileId.W2,
	]
	var e := Tanyao.detect(_make_wc(hand_ids, TileId.W2))
	assert_not_null(e)
	assert_eq(e.han, 1)

func test_with_terminal_returns_null():
	var hand_ids := [
		TileId.W1, TileId.W2, TileId.W3,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.S5, TileId.S6, TileId.S7,
		TileId.W4,
	]
	assert_null(Tanyao.detect(_make_wc(hand_ids, TileId.W4)))

func test_with_honor_returns_null():
	var hand_ids := [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.S5, TileId.S6, TileId.S7,
		TileId.HAKU,
	]
	assert_null(Tanyao.detect(_make_wc(hand_ids, TileId.HAKU)))
