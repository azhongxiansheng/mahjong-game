extends GutTest

func _make_basic_wc() -> WinContext:
	var hand := Hand.new()
	for tid in [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.T1,
	]:
		hand.add(Tile.new(tid))
	var winning := Tile.new(TileId.T1)
	var ctx := GameContext.new()
	var wp := WinPattern.detect(hand, [] as Array[Meld], winning)
	return WinContext.new(hand, [] as Array[Meld], winning, wp, ctx)

func test_evaluator_returns_empty_for_no_yaku():
	var l := YakuEvaluator.evaluate(_make_basic_wc())
	assert_eq(l.size(), 0)

func test_evaluator_picks_up_riichi():
	var wc := _make_basic_wc()
	wc.game_context.is_riichi = true
	var l := YakuEvaluator.evaluate(wc)
	assert_true(l.id_list().has(YakuId.RIICHI))

func test_evaluator_picks_up_riichi_and_tsumo_together():
	var wc := _make_basic_wc()
	wc.game_context.is_riichi = true
	wc.game_context.is_tsumo = true
	var l := YakuEvaluator.evaluate(wc)
	var ids := l.id_list()
	assert_true(ids.has(YakuId.RIICHI))
	assert_true(ids.has(YakuId.MENZEN_TSUMO))
	assert_eq(l.total_han(), 2)
