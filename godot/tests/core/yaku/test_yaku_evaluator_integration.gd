extends GutTest

func _make_wc(hand_ids: Array, winning_id: int, is_tsumo: bool, is_riichi: bool, melds: Array[Meld] = [] as Array[Meld]) -> WinContext:
	var hand := Hand.new()
	for tid in hand_ids:
		hand.add(Tile.new(tid))
	var winning := Tile.new(winning_id)
	var ctx := GameContext.new()
	ctx.is_tsumo = is_tsumo
	ctx.is_riichi = is_riichi
	ctx.bakaze = TileId.E
	ctx.jikaze = TileId.S_WIND
	var wp := WinPattern.detect(hand, melds, winning)
	return WinContext.new(hand, melds, winning, wp, ctx)

func test_riichi_tsumo_pinfu_iipeikou():
	# 234m 234m 567p 678s + 11s 待 5s/8s 自摸 5s
	var hand_ids := [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7,
		TileId.S1, TileId.S1,
	]
	var wc := _make_wc(hand_ids, TileId.S5, true, true)
	var list := YakuEvaluator.evaluate(wc)
	var ids := list.id_list()
	assert_true(ids.has(YakuId.RIICHI), "应有立直")
	assert_true(ids.has(YakuId.MENZEN_TSUMO), "应有自摸")
	assert_true(ids.has(YakuId.PINFU), "应有平和")
	assert_true(ids.has(YakuId.IIPEIKOU), "应有一杯口")
	assert_eq(list.total_han(), 4, "立直1+自摸1+平和1+一杯口1=4")

func test_chinitsu_excludes_honitsu_in_evaluator():
	# 111m 234m 234m 567m + 99m 单一花色万 → 清一色
	var hand_ids := [
		TileId.W1, TileId.W1, TileId.W1,
		TileId.W2, TileId.W3, TileId.W4,
		TileId.W2, TileId.W3, TileId.W4,
		TileId.W5, TileId.W6, TileId.W7,
		TileId.W9,
	]
	var wc := _make_wc(hand_ids, TileId.W9, false, false)
	var list := YakuEvaluator.evaluate(wc)
	var ids := list.id_list()
	assert_true(ids.has(YakuId.CHINITSU), "应有清一色")
	assert_false(ids.has(YakuId.HONITSU), "清一色应排除混一色")

func test_daisangen_yakuman_excludes_yakuhai():
	# 白白白 发发发 中中中 234m + 11s 雀 — 全暗 不构成立直/自摸默认
	var hand_ids := [
		TileId.HAKU, TileId.HAKU, TileId.HAKU,
		TileId.HATSU, TileId.HATSU, TileId.HATSU,
		TileId.CHUN, TileId.CHUN, TileId.CHUN,
		TileId.W2, TileId.W3, TileId.W4,
		TileId.S1,
	]
	var wc := _make_wc(hand_ids, TileId.S1, false, false)
	var list := YakuEvaluator.evaluate(wc)
	assert_true(list.is_yakuman(), "大三元命中")
	assert_eq(list.yakuman_total_multiplier(), 1)
	var ids := list.id_list()
	assert_false(ids.has(YakuId.YAKUHAI_HAKU), "大三元排白役牌")
	assert_false(ids.has(YakuId.YAKUHAI_HATSU))
	assert_false(ids.has(YakuId.YAKUHAI_CHUN))
	assert_false(ids.has(YakuId.SHOUSANGEN))

func test_suuankou_tanki_double_yakuman():
	# 111m 222m 333m 444m + 5s 単騎自摸
	var hand_ids := [
		TileId.W1, TileId.W1, TileId.W1,
		TileId.W2, TileId.W2, TileId.W2,
		TileId.W3, TileId.W3, TileId.W3,
		TileId.W4, TileId.W4, TileId.W4,
		TileId.S5,
	]
	var wc := _make_wc(hand_ids, TileId.S5, true, false)
	var list := YakuEvaluator.evaluate(wc)
	assert_true(list.is_yakuman())
	assert_eq(list.yakuman_total_multiplier(), 2, "四暗刻単騎 = 双倍")
	var ids := list.id_list()
	assert_true(ids.has(YakuId.SUUANKOU_TANKI))
	assert_false(ids.has(YakuId.SUUANKOU), "単騎排单倍四暗")
	assert_false(ids.has(YakuId.TOITOI), "排対々和")
	assert_false(ids.has(YakuId.SANANKOU), "排三暗刻")
