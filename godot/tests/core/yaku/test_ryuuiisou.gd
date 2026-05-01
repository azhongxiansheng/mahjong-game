extends GutTest

func _make_wc(hand_ids: Array, winning_id: int) -> WinContext:
	var hand := Hand.new()
	for tid in hand_ids:
		hand.add(Tile.new(tid))
	var winning := Tile.new(winning_id)
	var ctx := GameContext.new()
	var wp := WinPattern.detect(hand, [] as Array[Meld], winning)
	return WinContext.new(hand, [] as Array[Meld], winning, wp, ctx)

func test_pure_green_with_hatsu():
	# 234s 234s 666s 88s + 发发
	var hand_ids := [
		TileId.S2, TileId.S3, TileId.S4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.S6, TileId.S6, TileId.S6,
		TileId.S8, TileId.S8,
		TileId.HATSU, TileId.HATSU,
	]
	var e := Ryuuiisou.detect(_make_wc(hand_ids, TileId.HATSU))
	assert_not_null(e, "緑一色成立")
	assert_eq(e.yakuman_multiplier, 1)

func test_with_5sou_returns_null():
	# 5 索不是绿色（中间有黑色花纹）
	var hand_ids := [
		TileId.S2, TileId.S3, TileId.S4,
		TileId.S5, TileId.S6, TileId.S7,
		TileId.S6, TileId.S6, TileId.S6,
		TileId.S8, TileId.S8,
		TileId.HATSU, TileId.HATSU,
	]
	assert_null(Ryuuiisou.detect(_make_wc(hand_ids, TileId.HATSU)), "含 5s 不是绿一色")

func test_with_haku_returns_null():
	# 白不是绿色（虽是字牌）
	var hand_ids := [
		TileId.S2, TileId.S3, TileId.S4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.S6, TileId.S6, TileId.S6,
		TileId.S8, TileId.S8,
		TileId.HAKU, TileId.HAKU,
	]
	assert_null(Ryuuiisou.detect(_make_wc(hand_ids, TileId.HAKU)), "白不算绿")
