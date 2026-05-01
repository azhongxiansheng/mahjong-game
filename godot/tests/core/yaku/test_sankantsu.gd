extends GutTest

func _make_wc(hand_ids: Array, winning_id: int, melds: Array[Meld]) -> WinContext:
	var hand := Hand.new()
	for tid in hand_ids:
		hand.add(Tile.new(tid))
	var winning := Tile.new(winning_id)
	var ctx := GameContext.new()
	var wp := WinPattern.detect(hand, melds, winning)
	return WinContext.new(hand, melds, winning, wp, ctx)

func test_three_kans_returns_entry():
	# 3 副露杠 + 暗 4 张: 234m + 55s (winning 5s)
	var hand_ids := [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.S5,
	]
	var kan1 := Meld.make_minkan([
		Tile.new(TileId.E), Tile.new(TileId.E), Tile.new(TileId.E), Tile.new(TileId.E)
	], 0)
	var kan2 := Meld.make_minkan([
		Tile.new(TileId.S_WIND), Tile.new(TileId.S_WIND), Tile.new(TileId.S_WIND), Tile.new(TileId.S_WIND)
	], 1)
	var kan3 := Meld.make_ankan([
		Tile.new(TileId.HAKU), Tile.new(TileId.HAKU), Tile.new(TileId.HAKU), Tile.new(TileId.HAKU)
	])
	var e := Sankantsu.detect(_make_wc(hand_ids, TileId.S5, [kan1, kan2, kan3] as Array[Meld]))
	assert_not_null(e)
	assert_eq(e.han, 2)

func test_two_kans_returns_null():
	var hand_ids := [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.W5, TileId.W6, TileId.W7,
		TileId.S5,
	]
	var kan1 := Meld.make_minkan([
		Tile.new(TileId.E), Tile.new(TileId.E), Tile.new(TileId.E), Tile.new(TileId.E)
	], 0)
	var kan2 := Meld.make_minkan([
		Tile.new(TileId.S_WIND), Tile.new(TileId.S_WIND), Tile.new(TileId.S_WIND), Tile.new(TileId.S_WIND)
	], 1)
	assert_null(Sankantsu.detect(_make_wc(hand_ids, TileId.S5, [kan1, kan2] as Array[Meld])))
