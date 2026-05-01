extends GutTest

func _make_wc(hand_ids: Array, winning_id: int) -> WinContext:
	var hand := Hand.new()
	for tid in hand_ids:
		hand.add(Tile.new(tid))
	var winning := Tile.new(winning_id)
	var ctx := GameContext.new()
	var wp := WinPattern.detect(hand, [] as Array[Meld], winning)
	return WinContext.new(hand, [] as Array[Meld], winning, wp, ctx)

func test_two_dragon_triplets_one_dragon_pair():
	# 白白白 发发发 中中 + 234m + 567p waiting 7p
	var hand_ids := [
		TileId.HAKU, TileId.HAKU, TileId.HAKU,
		TileId.HATSU, TileId.HATSU, TileId.HATSU,
		TileId.CHUN, TileId.CHUN,
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T5, TileId.T6,
	]
	var e := Shousangen.detect(_make_wc(hand_ids, TileId.T7))
	assert_not_null(e)
	assert_eq(e.han, 2)

func test_only_one_dragon_triplet_returns_null():
	var hand_ids := [
		TileId.HAKU, TileId.HAKU, TileId.HAKU,
		TileId.HATSU, TileId.HATSU,
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7,
	]
	assert_null(Shousangen.detect(_make_wc(hand_ids, TileId.S5)))

func test_no_dragon_pair_returns_null():
	# 白白白 发发发 中中中 (大三元) -> 不是小三元
	var hand_ids := [
		TileId.HAKU, TileId.HAKU, TileId.HAKU,
		TileId.HATSU, TileId.HATSU, TileId.HATSU,
		TileId.CHUN, TileId.CHUN, TileId.CHUN,
		TileId.W2, TileId.W3, TileId.W4,
		TileId.S1,
	]
	assert_null(Shousangen.detect(_make_wc(hand_ids, TileId.S1)), "三元全刻是大三元，不是小三元")
