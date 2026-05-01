extends GutTest

func _make_wc(hand_ids: Array, winning_id: int, dealer_first: bool, tsumo: bool) -> WinContext:
	var hand := Hand.new()
	for tid in hand_ids:
		hand.add(Tile.new(tid))
	var winning := Tile.new(winning_id)
	var ctx := GameContext.new()
	ctx.is_dealer_first_hand = dealer_first
	ctx.is_tsumo = tsumo
	var wp := WinPattern.detect(hand, [] as Array[Meld], winning)
	return WinContext.new(hand, [] as Array[Meld], winning, wp, ctx)

# 任意标准 4 面子 + 雀头作为本测试的"和牌"形态
const HAND_IDS := [
	0, 1, 2,    # 123m
	3, 4, 5,    # 456m
	9, 10, 11,  # 123p
	18, 19, 20, # 123s
	27,         # 东
]

func test_tenhou_dealer_first_tsumo():
	var e := Tenhou.detect(_make_wc(HAND_IDS, TileId.E, true, true))
	assert_not_null(e, "天和成立")
	assert_eq(e.yaku_id, YakuId.TENHOU)
	assert_eq(e.yakuman_multiplier, 1)

func test_tenhou_not_dealer_returns_null():
	assert_null(Tenhou.detect(_make_wc(HAND_IDS, TileId.E, false, true)), "非亲家不是天和")

func test_tenhou_ron_returns_null():
	assert_null(Tenhou.detect(_make_wc(HAND_IDS, TileId.E, true, false)), "荣胡不是天和")
