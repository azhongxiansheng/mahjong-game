extends GutTest

func _make_wc(hand_ids: Array, winning_id: int, is_tsumo: bool, melds: Array[Meld] = [] as Array[Meld]) -> WinContext:
	var hand := Hand.new()
	for tid in hand_ids:
		hand.add(Tile.new(tid))
	var winning := Tile.new(winning_id)
	var ctx := GameContext.new()
	ctx.is_tsumo = is_tsumo
	var wp := WinPattern.detect(hand, melds, winning)
	return WinContext.new(hand, melds, winning, wp, ctx)

func test_four_concealed_triplets_tsumo():
	# 111m 222m 333m 444m + 55s 自摸 5s — 第 4 暗刻完成靠摸（非単騎）
	var hand_ids := [
		TileId.W1, TileId.W1, TileId.W1,
		TileId.W2, TileId.W2, TileId.W2,
		TileId.W3, TileId.W3, TileId.W3,
		TileId.W4, TileId.W4, TileId.W4,
		TileId.S5,
	]
	var e := Suuankou.detect(_make_wc(hand_ids, TileId.S5, true))
	assert_not_null(e, "四暗刻成立")
	assert_eq(e.yaku_id, YakuId.SUUANKOU_TANKI, "雀头単騎 → 双倍")
	assert_eq(e.yakuman_multiplier, 2)

func test_four_concealed_tanki_ron_double():
	# 111m 222m 333m 444m + 5s 单騎 5s 荣胡 — 単騎雀头 ron
	var hand_ids := [
		TileId.W1, TileId.W1, TileId.W1,
		TileId.W2, TileId.W2, TileId.W2,
		TileId.W3, TileId.W3, TileId.W3,
		TileId.W4, TileId.W4, TileId.W4,
		TileId.S5,
	]
	var e := Suuankou.detect(_make_wc(hand_ids, TileId.S5, false))
	assert_not_null(e, "雀头単騎荣胡也是 SUUANKOU_TANKI")
	assert_eq(e.yaku_id, YakuId.SUUANKOU_TANKI)

func test_three_concealed_one_open_returns_null():
	# 副露明刻一个 → 不是暗刻
	var pon_w4 := Meld.make_pon([Tile.new(TileId.W4), Tile.new(TileId.W4), Tile.new(TileId.W4)], 0)
	var hand_ids := [
		TileId.W1, TileId.W1, TileId.W1,
		TileId.W2, TileId.W2, TileId.W2,
		TileId.W3, TileId.W3, TileId.W3,
		TileId.S5,
	]
	assert_null(Suuankou.detect(_make_wc(hand_ids, TileId.S5, true, [pon_w4] as Array[Meld])), "明刻副露破暗")

func test_with_ankan_still_concealed_tsumo():
	# 暗杠 1 个 + 暗刻 3 个 + 雀头 — 暗杠算暗刻
	var ankan_w4 := Meld.make_ankan([Tile.new(TileId.W4), Tile.new(TileId.W4), Tile.new(TileId.W4), Tile.new(TileId.W4)])
	var hand_ids := [
		TileId.W1, TileId.W1, TileId.W1,
		TileId.W2, TileId.W2, TileId.W2,
		TileId.W3, TileId.W3, TileId.W3,
		TileId.S5,
	]
	var e := Suuankou.detect(_make_wc(hand_ids, TileId.S5, true, [ankan_w4] as Array[Meld]))
	assert_not_null(e, "ANKAN 算暗刻 → 四暗刻")
	assert_eq(e.yaku_id, YakuId.SUUANKOU_TANKI, "雀头単騎自摸 → 双倍")
