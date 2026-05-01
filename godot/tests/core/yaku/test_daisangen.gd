extends GutTest

func _make_wc(hand_ids: Array, winning_id: int, melds: Array[Meld] = [] as Array[Meld]) -> WinContext:
	var hand := Hand.new()
	for tid in hand_ids:
		hand.add(Tile.new(tid))
	var winning := Tile.new(winning_id)
	var ctx := GameContext.new()
	var wp := WinPattern.detect(hand, melds, winning)
	return WinContext.new(hand, melds, winning, wp, ctx)

func test_three_dragons_all_concealed():
	# 白白白 发发发 中中中 + 234m + 11s
	var hand_ids := [
		TileId.HAKU, TileId.HAKU, TileId.HAKU,
		TileId.HATSU, TileId.HATSU, TileId.HATSU,
		TileId.CHUN, TileId.CHUN, TileId.CHUN,
		TileId.W2, TileId.W3, TileId.W4,
		TileId.S1,
	]
	var e := Daisangen.detect(_make_wc(hand_ids, TileId.S1))
	assert_not_null(e, "大三元成立")
	assert_true(e.is_yakuman)
	assert_eq(e.yakuman_multiplier, 1)

func test_two_dragons_pair_returns_null():
	# 小三元（白白白 发发发 中中）→ 不是大三元
	var hand_ids := [
		TileId.HAKU, TileId.HAKU, TileId.HAKU,
		TileId.HATSU, TileId.HATSU, TileId.HATSU,
		TileId.CHUN, TileId.CHUN,
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T5, TileId.T6,
	]
	assert_null(Daisangen.detect(_make_wc(hand_ids, TileId.T7)), "小三元不是大三元")

func test_with_dragon_pon_meld():
	# 副露白碰 + 暗发刻 + 暗中刻 + 234m + 11s
	var pon_haku := Meld.make_pon([Tile.new(TileId.HAKU), Tile.new(TileId.HAKU), Tile.new(TileId.HAKU)], 0)
	var hand_ids := [
		TileId.HATSU, TileId.HATSU, TileId.HATSU,
		TileId.CHUN, TileId.CHUN, TileId.CHUN,
		TileId.W2, TileId.W3, TileId.W4,
		TileId.S1,
	]
	var e := Daisangen.detect(_make_wc(hand_ids, TileId.S1, [pon_haku] as Array[Meld]))
	assert_not_null(e, "副露白碰也算大三元")
