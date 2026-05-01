extends GutTest

func _make_wc(hand_ids: Array, winning_id: int, melds: Array[Meld] = [] as Array[Meld], jikaze: int = TileId.S_WIND) -> WinContext:
	var hand := Hand.new()
	for tid in hand_ids:
		hand.add(Tile.new(tid))
	var winning := Tile.new(winning_id)
	var ctx := GameContext.new()
	ctx.bakaze = TileId.E
	ctx.jikaze = jikaze
	var wp := WinPattern.detect(hand, melds, winning)
	return WinContext.new(hand, melds, winning, wp, ctx)

func test_pure_pinfu_pattern():
	# 234m 234p 567p 678s 11s waiting 5s/8s, draw 5s
	# Hand 13: 234m + 234p + 567p + 67s + 11s = 3+3+3+2+2 = 13 ✓
	var hand_ids := [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7,
		TileId.S1, TileId.S1,
	]
	var wc := _make_wc(hand_ids, TileId.S5)
	var e := Pinfu.detect(wc)
	assert_not_null(e, "标准平和应识别")
	assert_eq(e.han, 1)

func test_fails_with_pon():
	# Triplet 555m breaks pinfu condition 2
	var hand_ids := [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.W5, TileId.W5, TileId.W5,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7,
		TileId.S1, TileId.S1,
	]
	var wc := _make_wc(hand_ids, TileId.S5)
	assert_null(Pinfu.detect(wc))

func test_fails_with_yakuhai_pair_haku():
	# Pair = HAKU
	var hand_ids := [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7,
		TileId.HAKU, TileId.HAKU,
	]
	var wc := _make_wc(hand_ids, TileId.S5)
	assert_null(Pinfu.detect(wc))

func test_fails_with_jikaze_pair():
	# jikaze = SOUTH; pair = SOUTH
	var hand_ids := [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7,
		TileId.S_WIND, TileId.S_WIND,
	]
	var wc := _make_wc(hand_ids, TileId.S5, [] as Array[Meld], TileId.S_WIND)
	assert_null(Pinfu.detect(wc))

func test_fails_when_open():
	# Has chi → not menzen
	var hand_ids := [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S6, TileId.S7,
		TileId.S1, TileId.S1,
	]
	var chi := Meld.make_chi([
		Tile.new(TileId.T5), Tile.new(TileId.T6), Tile.new(TileId.T7)
	], 0)
	var wc := _make_wc(hand_ids, TileId.S5, [chi] as Array[Meld])
	assert_null(Pinfu.detect(wc))

func test_fails_with_kanchan_wait():
	# 1m_3m kanchan waiting 2m: hand has 1m 3m, winning 2m closes 123m via嵌张
	# Full hand: 1m 3m + 234p + 567p + 678s + 11s waiting 2m
	# Total暗 13: 1m+3m + 234p + 567p + 678s + 11s = 2+3+3+3+2 = 13 ✓
	var hand_ids := [
		TileId.W1, TileId.W3,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.S1, TileId.S1,
	]
	var wc := _make_wc(hand_ids, TileId.W2)
	assert_null(Pinfu.detect(wc), "嵌张待ち 2m 不算平和")

func test_fails_with_penchan_low_end():
	# 1-2 waiting 3 (penchan, low end)
	# Hand: 1m 2m + 234p + 567p + 678s + 11s waiting 3m
	var hand_ids := [
		TileId.W1, TileId.W2,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.S1, TileId.S1,
	]
	var wc := _make_wc(hand_ids, TileId.W3)
	assert_null(Pinfu.detect(wc), "12 待 3 边张待ち不算平和")

func test_fails_with_penchan_high_end():
	# 8-9 waiting 7 (penchan, high end)
	var hand_ids := [
		TileId.W8, TileId.W9,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.S1, TileId.S1,
	]
	var wc := _make_wc(hand_ids, TileId.W7)
	assert_null(Pinfu.detect(wc), "89 待 7 边张待ち不算平和")

func test_fails_with_tanki_wait():
	# Pair 単騎待ち: hand has 4 complete sequences + 1 lone non-yakuhai tile waiting its pair
	# 234m + 234p + 567p + 678s + 1s waiting 1s
	var hand_ids := [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.S1,
	]
	var wc := _make_wc(hand_ids, TileId.S1)
	assert_null(Pinfu.detect(wc), "雀头単騎不算平和")
