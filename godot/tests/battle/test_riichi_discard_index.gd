extends GutTest

# turn_engine.declare_riichi 必须把"立直宣告时刚弃的牌"在该 seat 的
# discards 中的索引记到 RiichiState.riichi_discard_index — DiscardRiver
# 据此把那张牌旋转 90°(日麻最标志性的视觉记号)。

# 用 BattleController 构造 fresh state(seed 42 dealer 0,标准 4 家发牌)。
# 然后绕过 turn_engine 的 RiichiValidator,直接调 declare_riichi 验证字段。

func _make_bc() -> BattleController:
	return BattleController.new(42, 0, false, TileId.E)


func test_initial_riichi_discard_index_is_minus_one() -> void:
	var bc := _make_bc()
	for i in range(4):
		assert_eq(bc.state.seats[i].riichi.riichi_discard_index, -1,
			"seat %d 起始 riichi_discard_index 应为 -1" % i)


# 把 seat 0 的手做成确定听牌(七对子听 W9 単騎),让 RiichiValidator 通过,
# 然后 discard 一张 + declare_riichi → 验证 index == discards 末尾索引。
func test_declare_riichi_records_last_discard_index() -> void:
	var bc := _make_bc()
	# 把 seat 0 手牌换成 14 张可立直手:七对子 听 W9
	# m1m1 m2m2 m3m3 m5m5 m6m6 m7m7 m8 + (drawn) m8 → discard m8 后听 m9
	var seat: Seat = bc.state.seats[0]
	seat.hand._tiles.clear()
	var ids: Array = [
		TileId.W1, TileId.W1, TileId.W2, TileId.W2, TileId.W3, TileId.W3,
		TileId.W5, TileId.W5, TileId.W6, TileId.W6, TileId.W7, TileId.W7,
		TileId.W8, TileId.W8,
	]
	for tid in ids:
		seat.hand.add(Tile.new(tid))
	bc.state.current_seat = 0
	# discard W8 (留下 13 张听 W9 七対子)
	assert_true(bc.engine.discard(TileId.W8), "discard 应成功")
	var discards_size_after: int = bc.state.discards_per_seat[0].size()
	assert_eq(discards_size_after, 1, "seat 0 此时只弹了 1 张")
	# declare_riichi 必须成功 — 门清 + 听牌 + 牌山 > 3 全满足
	assert_true(bc.engine.declare_riichi(0), "should declare riichi")
	assert_true(seat.riichi.declared)
	# index 应指向 discards 末尾(刚弃的那张 = W8,索引 0)
	assert_eq(seat.riichi.riichi_discard_index, 0,
		"刚弃的 W8 是 discards[0],riichi_discard_index 应为 0")


# 多家立直独立:seat 0 立直后 index=0,seat 2 没立直 → index 仍 -1。
func test_riichi_discard_index_per_seat_independent() -> void:
	var bc := _make_bc()
	var seat0: Seat = bc.state.seats[0]
	seat0.hand._tiles.clear()
	for tid in [
		TileId.T1, TileId.T1, TileId.T2, TileId.T2, TileId.T3, TileId.T3,
		TileId.T5, TileId.T5, TileId.T6, TileId.T6, TileId.T7, TileId.T7,
		TileId.T8, TileId.T8,
	]:
		seat0.hand.add(Tile.new(tid))
	bc.state.current_seat = 0
	bc.engine.discard(TileId.T8)
	bc.engine.declare_riichi(0)
	assert_eq(bc.state.seats[0].riichi.riichi_discard_index, 0)
	assert_eq(bc.state.seats[1].riichi.riichi_discard_index, -1, "seat 1 未立直")
	assert_eq(bc.state.seats[2].riichi.riichi_discard_index, -1)
	assert_eq(bc.state.seats[3].riichi.riichi_discard_index, -1)
