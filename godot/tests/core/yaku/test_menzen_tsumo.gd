extends GutTest

func _make_wc(is_tsumo: bool, melds: Array[Meld] = [] as Array[Meld]) -> WinContext:
	var hand_ids: Array
	if melds.size() == 0:
		hand_ids = [
			TileId.W2, TileId.W3, TileId.W4,
			TileId.T5, TileId.T6, TileId.T7,
			TileId.S6, TileId.S7, TileId.S8,
			TileId.S2, TileId.S3, TileId.S4,
			TileId.T1,
		]
	else:
		hand_ids = [
			TileId.W2, TileId.W3, TileId.W4,
			TileId.T5, TileId.T6, TileId.T7,
			TileId.S6, TileId.S7, TileId.S8,
			TileId.T1,
		]
	var hand := Hand.new()
	for tid in hand_ids:
		hand.add(Tile.new(tid))
	var winning := Tile.new(TileId.T1)
	var ctx := GameContext.new()
	ctx.is_tsumo = is_tsumo
	var wp := WinPattern.detect(hand, melds, winning)
	return WinContext.new(hand, melds, winning, wp, ctx)

func test_when_menzen_and_tsumo():
	var e := MenzenTsumo.detect(_make_wc(true))
	assert_not_null(e)
	assert_eq(e.yaku_id, YakuId.MENZEN_TSUMO)

func test_not_when_ron():
	assert_null(MenzenTsumo.detect(_make_wc(false)))

func test_not_when_open():
	var pon := Meld.make_pon([
		Tile.new(TileId.E), Tile.new(TileId.E), Tile.new(TileId.E)
	], 0)
	assert_null(MenzenTsumo.detect(_make_wc(true, [pon] as Array[Meld])))
