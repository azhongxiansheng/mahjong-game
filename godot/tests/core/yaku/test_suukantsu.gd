extends GutTest

func _make_wc(hand_ids: Array, winning_id: int, melds: Array[Meld]) -> WinContext:
	var hand := Hand.new()
	for tid in hand_ids:
		hand.add(Tile.new(tid))
	var winning := Tile.new(winning_id)
	var ctx := GameContext.new()
	var wp := WinPattern.detect(hand, melds, winning)
	return WinContext.new(hand, melds, winning, wp, ctx)

func test_four_kans():
	# 4 个杠（任意类型）+ 1 雀头
	var k1 := Meld.make_ankan([Tile.new(TileId.W1), Tile.new(TileId.W1), Tile.new(TileId.W1), Tile.new(TileId.W1)])
	var k2 := Meld.make_ankan([Tile.new(TileId.W2), Tile.new(TileId.W2), Tile.new(TileId.W2), Tile.new(TileId.W2)])
	var k3 := Meld.make_minkan([Tile.new(TileId.T5), Tile.new(TileId.T5), Tile.new(TileId.T5), Tile.new(TileId.T5)], 1)
	var k4 := Meld.make_ankan([Tile.new(TileId.S9), Tile.new(TileId.S9), Tile.new(TileId.S9), Tile.new(TileId.S9)])
	var hand_ids := [TileId.HAKU]  # 雀头之一,1 张 = 13 - 3*4
	var melds: Array[Meld] = [k1, k2, k3, k4]
	var e := Suukantsu.detect(_make_wc(hand_ids, TileId.HAKU, melds))
	assert_not_null(e, "四槓子成立")
	assert_eq(e.yakuman_multiplier, 1)

func test_three_kans_returns_null():
	var k1 := Meld.make_ankan([Tile.new(TileId.W1), Tile.new(TileId.W1), Tile.new(TileId.W1), Tile.new(TileId.W1)])
	var k2 := Meld.make_ankan([Tile.new(TileId.W2), Tile.new(TileId.W2), Tile.new(TileId.W2), Tile.new(TileId.W2)])
	var k3 := Meld.make_ankan([Tile.new(TileId.T5), Tile.new(TileId.T5), Tile.new(TileId.T5), Tile.new(TileId.T5)])
	# 第 4 个面子是非杠（暗刻）
	var hand_ids := [TileId.S2, TileId.S2, TileId.S2, TileId.HAKU]
	var melds: Array[Meld] = [k1, k2, k3]
	assert_null(Suukantsu.detect(_make_wc(hand_ids, TileId.HAKU, melds)), "三杠不是四杠")
