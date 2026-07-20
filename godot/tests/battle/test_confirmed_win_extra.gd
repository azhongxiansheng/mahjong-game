extends GutTest

# 公开 bundle 的和牌演出只消费最终确认态。这里走真实规则检查与结算链，
# 固定 WIN_DECLARED 必须携带显式的自摸 / 抢杠语义，不能再由 UI 猜事件历史。


func _make_t1_tanki_hand(include_winning_tile: bool) -> Hand:
	var hand := Hand.new()
	for tile_id in [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.T1,
	]:
		hand.add(Tile.new(tile_id))
	if include_winning_tile:
		hand.add(Tile.new(TileId.T1))
	return hand


func _last_win_event(bc: BattleController) -> BattleEvent:
	for index in range(bc.events.size() - 1, -1, -1):
		var event: BattleEvent = bc.events[index]
		if event.type == &"WIN_DECLARED":
			return event
	return null


func test_apply_ron_chankan_reaches_confirmed_win_extra() -> void:
	var bc := BattleController.new(42, 0, false, TileId.E)
	bc.state.seats[1].hand = _make_t1_tanki_hand(false)
	var won := bc.apply_ron(1, Tile.new(TileId.T1), 0, false, true)

	assert_true(won, "真实 T1 单骑抢杠应完成荣和")
	var win_event := _last_win_event(bc)
	assert_not_null(win_event, "确认成功后必须发 WIN_DECLARED")
	assert_false(bool(win_event.extra.get("is_tsumo", true)))
	assert_true(bool(win_event.extra.get("is_chankan", false)),
		"apply_ron(..., true) 必须把抢杠传到最终确认事件")


func test_tsumo_confirmed_win_extra_is_explicit() -> void:
	var bc := BattleController.new(42, 0, false, TileId.E)
	bc.state.current_seat = 0
	bc.state.seats[0].hand = _make_t1_tanki_hand(true)
	var drawn := Tile.new(TileId.T1)
	var checked: Dictionary = bc._check_tsumo(drawn)
	assert_true(bool(checked.get("is_winning", false)), "测试手牌必须真实自摸成立")
	if not bool(checked.get("is_winning", false)):
		return
	bc._settle_tsumo(drawn, checked.wp, checked.yaku_list)

	var win_event := _last_win_event(bc)
	assert_not_null(win_event)
	assert_true(bool(win_event.extra.get("is_tsumo", false)))
	assert_false(bool(win_event.extra.get("is_chankan", true)))
