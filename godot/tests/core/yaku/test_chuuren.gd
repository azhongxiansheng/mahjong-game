extends GutTest

func _make_wc(hand_ids: Array, winning_id: int) -> WinContext:
	var hand := Hand.new()
	for tid in hand_ids:
		hand.add(Tile.new(tid))
	var winning := Tile.new(winning_id)
	var ctx := GameContext.new()
	var wp := WinPattern.detect(hand, [] as Array[Meld], winning)
	return WinContext.new(hand, [] as Array[Meld], winning, wp, ctx)

func test_pure_chuuren_double_yakuman():
	# 起手 1112345678999m，和 5m → 純正九蓮（去掉 5m 后剩 1112345678999）
	var hand_ids := [
		TileId.W1, TileId.W1, TileId.W1,
		TileId.W2, TileId.W3, TileId.W4,
		TileId.W5, TileId.W6, TileId.W7,
		TileId.W8,
		TileId.W9, TileId.W9, TileId.W9,
	]
	var e := Chuuren.detect(_make_wc(hand_ids, TileId.W5))
	assert_not_null(e, "九蓮成立")
	assert_eq(e.yaku_id, YakuId.JUNSEI_CHUUREN, "和 5m 后剩 1112345678999 → 純正")
	assert_eq(e.yakuman_multiplier, 2)

func test_normal_chuuren_single():
	# 起手 1112345678999m + 多一张 2m → 和 2m 后是 11122345678999m，去掉 2m 剩 1112345678998... 不对
	# 正确：起手 11123456789999m？不行,9 有 4 张
	# 让起手 1112345567899m（13 张：1×3 + 2×1 + 3×1 + 4×1 + 5×2 + 6×1 + 7×1 + 8×1 + 9×2 = 13）
	# 和 9m → 总 14：1×3 + 2 + 3 + 4 + 5×2 + 6 + 7 + 8 + 9×3 = 14；满足 chuuren 模式（1≥3, 9≥3, 2-8≥1）
	# 去掉 9m 后剩 1×3 + 2 + 3 + 4 + 5×2 + 6 + 7 + 8 + 9×2 → 5 是 2 不是 1 → 非純正 → 普通
	var hand_ids := [
		TileId.W1, TileId.W1, TileId.W1,
		TileId.W2, TileId.W3, TileId.W4,
		TileId.W5, TileId.W5,
		TileId.W6, TileId.W7, TileId.W8,
		TileId.W9, TileId.W9,
	]
	var e := Chuuren.detect(_make_wc(hand_ids, TileId.W9))
	assert_not_null(e, "九蓮成立")
	assert_eq(e.yaku_id, YakuId.CHUUREN, "非純正 → 普通九蓮")
	assert_eq(e.yakuman_multiplier, 1)

func test_two_suits_returns_null():
	var hand_ids := [
		TileId.W1, TileId.W1, TileId.W1,
		TileId.W2, TileId.W3, TileId.W4,
		TileId.W5, TileId.W6, TileId.W7,
		TileId.W8,
		TileId.W9, TileId.W9,
		TileId.T9,
	]
	assert_null(Chuuren.detect(_make_wc(hand_ids, TileId.T9)), "混色不是九蓮")
