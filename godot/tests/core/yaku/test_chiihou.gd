extends GutTest

func _make_wc(hand_ids: Array, winning_id: int, non_dealer_first: bool, tsumo: bool) -> WinContext:
	var hand := Hand.new()
	for tid in hand_ids:
		hand.add(Tile.new(tid))
	var winning := Tile.new(winning_id)
	var ctx := GameContext.new()
	ctx.is_non_dealer_first_draw = non_dealer_first
	ctx.is_tsumo = tsumo
	var wp := WinPattern.detect(hand, [] as Array[Meld], winning)
	return WinContext.new(hand, [] as Array[Meld], winning, wp, ctx)

const HAND_IDS := [
	0, 1, 2,
	3, 4, 5,
	9, 10, 11,
	18, 19, 20,
	27,
]

func test_chiihou_first_draw_tsumo():
	var e := Chiihou.detect(_make_wc(HAND_IDS, TileId.E, true, true))
	assert_not_null(e, "地和成立")
	assert_eq(e.yaku_id, YakuId.CHIIHOU)
	assert_eq(e.yakuman_multiplier, 1)

func test_chiihou_ron_returns_null():
	assert_null(Chiihou.detect(_make_wc(HAND_IDS, TileId.E, true, false)), "荣胡不是地和")

func test_chiihou_not_first_draw_returns_null():
	assert_null(Chiihou.detect(_make_wc(HAND_IDS, TileId.E, false, true)), "非首摸不是地和")
