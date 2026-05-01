extends GutTest

func _hand_with_other_ids(other: Array) -> Hand:
	var h := Hand.new()
	for tid in other:
		h.add(Tile.new(tid))
	return h

func test_haku_pon_in_meld_returns_haku():
	var hand := _hand_with_other_ids([
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.S1,
	])
	var haku_pon := Meld.make_pon([
		Tile.new(TileId.HAKU), Tile.new(TileId.HAKU), Tile.new(TileId.HAKU)
	], 0)
	var winning := Tile.new(TileId.S1)
	var ctx := GameContext.new()
	ctx.bakaze = TileId.E
	ctx.jikaze = TileId.S_WIND
	var wp := WinPattern.detect(hand, [haku_pon] as Array[Meld], winning)
	var wc := WinContext.new(hand, [haku_pon] as Array[Meld], winning, wp, ctx)
	var entries := Yakuhai.detect_all(wc)
	var ids: Array = []
	for e in entries:
		ids.append(e.yaku_id)
	assert_true(ids.has(YakuId.YAKUHAI_HAKU))
	assert_false(ids.has(YakuId.YAKUHAI_HATSU))
	assert_false(ids.has(YakuId.YAKUHAI_CHUN))

func test_haku_in_concealed_hand():
	var hand := _hand_with_other_ids([
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.HAKU, TileId.HAKU, TileId.HAKU,
		TileId.S1,
	])
	var winning := Tile.new(TileId.S1)
	var ctx := GameContext.new()
	ctx.bakaze = TileId.E
	ctx.jikaze = TileId.S_WIND
	var wp := WinPattern.detect(hand, [] as Array[Meld], winning)
	var wc := WinContext.new(hand, [] as Array[Meld], winning, wp, ctx)
	var entries := Yakuhai.detect_all(wc)
	var ids: Array = []
	for e in entries:
		ids.append(e.yaku_id)
	assert_true(ids.has(YakuId.YAKUHAI_HAKU))

func test_bakaze_east_with_east_pon():
	var hand := _hand_with_other_ids([
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.S1,
	])
	var east_pon := Meld.make_pon([
		Tile.new(TileId.E), Tile.new(TileId.E), Tile.new(TileId.E)
	], 0)
	var winning := Tile.new(TileId.S1)
	var ctx := GameContext.new()
	ctx.bakaze = TileId.E
	ctx.jikaze = TileId.S_WIND
	var wp := WinPattern.detect(hand, [east_pon] as Array[Meld], winning)
	var wc := WinContext.new(hand, [east_pon] as Array[Meld], winning, wp, ctx)
	var entries := Yakuhai.detect_all(wc)
	var ids: Array = []
	for e in entries:
		ids.append(e.yaku_id)
	assert_true(ids.has(YakuId.YAKUHAI_BAKAZE))
	assert_false(ids.has(YakuId.YAKUHAI_JIKAZE))

func test_jikaze_south_with_south_pon():
	var hand := _hand_with_other_ids([
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.S1,
	])
	var south_pon := Meld.make_pon([
		Tile.new(TileId.S_WIND), Tile.new(TileId.S_WIND), Tile.new(TileId.S_WIND)
	], 0)
	var winning := Tile.new(TileId.S1)
	var ctx := GameContext.new()
	ctx.bakaze = TileId.E
	ctx.jikaze = TileId.S_WIND
	var wp := WinPattern.detect(hand, [south_pon] as Array[Meld], winning)
	var wc := WinContext.new(hand, [south_pon] as Array[Meld], winning, wp, ctx)
	var entries := Yakuhai.detect_all(wc)
	var ids: Array = []
	for e in entries:
		ids.append(e.yaku_id)
	assert_true(ids.has(YakuId.YAKUHAI_JIKAZE))
	assert_false(ids.has(YakuId.YAKUHAI_BAKAZE))

func test_double_east_when_jikaze_eq_bakaze():
	var hand := _hand_with_other_ids([
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.S1,
	])
	var east_pon := Meld.make_pon([
		Tile.new(TileId.E), Tile.new(TileId.E), Tile.new(TileId.E)
	], 0)
	var winning := Tile.new(TileId.S1)
	var ctx := GameContext.new()
	ctx.bakaze = TileId.E
	ctx.jikaze = TileId.E
	var wp := WinPattern.detect(hand, [east_pon] as Array[Meld], winning)
	var wc := WinContext.new(hand, [east_pon] as Array[Meld], winning, wp, ctx)
	var entries := Yakuhai.detect_all(wc)
	var ids: Array = []
	for e in entries:
		ids.append(e.yaku_id)
	assert_true(ids.has(YakuId.YAKUHAI_BAKAZE))
	assert_true(ids.has(YakuId.YAKUHAI_JIKAZE))

func test_no_yakuhai_for_pair_only():
	# 雀头白 — 不算
	var hand := _hand_with_other_ids([
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.HAKU,
	])
	var winning := Tile.new(TileId.HAKU)
	var ctx := GameContext.new()
	ctx.bakaze = TileId.E
	ctx.jikaze = TileId.S_WIND
	var wp := WinPattern.detect(hand, [] as Array[Meld], winning)
	var wc := WinContext.new(hand, [] as Array[Meld], winning, wp, ctx)
	var entries := Yakuhai.detect_all(wc)
	assert_eq(entries.size(), 0, "雀头不算役牌")

func test_evaluator_integration_picks_yakuhai():
	var hand := _hand_with_other_ids([
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.HAKU, TileId.HAKU, TileId.HAKU,
		TileId.S1,
	])
	var winning := Tile.new(TileId.S1)
	var ctx := GameContext.new()
	ctx.bakaze = TileId.E
	ctx.jikaze = TileId.S_WIND
	var wp := WinPattern.detect(hand, [] as Array[Meld], winning)
	var wc := WinContext.new(hand, [] as Array[Meld], winning, wp, ctx)
	var l := YakuEvaluator.evaluate(wc)
	assert_true(l.id_list().has(YakuId.YAKUHAI_HAKU))
