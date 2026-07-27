extends GutTest

# turn_engine.declare_riichi_and_discard 必须把"立直宣告时刚弃的牌"在该 seat 的
# discards 中的索引记到 RiichiState.riichi_discard_index — DiscardRiver
# 据此把那张牌旋转 90°(日麻最标志性的视觉记号)。

# 用 BattleController 构造 fresh state(seed 42 dealer 0,标准 4 家发牌)。
# 通过真实原子实体接口验证字段。

func _make_bc() -> BattleController:
	return BattleController.new(42, 0, false, TileId.E)


func test_initial_riichi_discard_index_is_minus_one() -> void:
	var bc := _make_bc()
	for i in range(4):
		assert_eq(bc.state.seats[i].river.riichi_discard_index(), -1,
			"seat %d 起始 riichi_discard_index 应为 -1" % i)


# 把 seat 0 的手做成确定可立直手，让 RiichiValidator 通过，
# 然后原子立直并弃牌 → 验证 index == discards 末尾索引。
func test_declare_riichi_records_last_discard_index() -> void:
	var bc := _make_bc()
	# 把 seat 0 手牌换成 14 张可立直手：七对子形弃 W8 后听 W8。
	# m1m1 m2m2 m3m3 m5m5 m6m6 m7m7 m8 + (drawn) m8
	var seat: Seat = bc.state.seats[0]
	var tiles: Array[Tile] = []
	var ids: Array = [
		TileId.W1, TileId.W1, TileId.W2, TileId.W2, TileId.W3, TileId.W3,
		TileId.W5, TileId.W5, TileId.W6, TileId.W6, TileId.W7, TileId.W7,
		TileId.W8, TileId.W8,
	]
	var serial := 10
	var discard_iid := -1
	for tid in ids:
		var t := Tile.new(tid, false, Tile.NO_OWNER, serial)
		tiles.append(t)
		if tid == TileId.W8:
			discard_iid = serial
		serial += 1
	assert_true(seat.hand.restore_tiles(tiles))
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.DISCARD
	# 原子立直并弃 W8 entity（留下 13 张七对子听牌）
	assert_true(bc.engine.declare_riichi_and_discard(0, discard_iid),
		"declare_riichi_and_discard 应成功")
	var discards_size_after: int = bc.state.seats[0].river.size()
	assert_eq(discards_size_after, 1, "seat 0 此时只弹了 1 张")
	assert_true(seat.riichi.declared)
	# index 应指向 discards 末尾(刚弃的那张 = W8,索引 0)
	assert_eq(seat.river.riichi_discard_index(), 0,
		"刚弃的 W8 是 discards[0],riichi_discard_index 应为 0")


# 多家立直独立:seat 0 立直后 index=0,seat 2 没立直 → index 仍 -1。
func test_riichi_discard_index_per_seat_independent() -> void:
	var bc := _make_bc()
	var seat0: Seat = bc.state.seats[0]
	var tiles: Array[Tile] = []
	var serial2 := 20
	var t8_iid := -1
	for tid in [
		TileId.T1, TileId.T1, TileId.T2, TileId.T2, TileId.T3, TileId.T3,
		TileId.T5, TileId.T5, TileId.T6, TileId.T6, TileId.T7, TileId.T7,
		TileId.T8, TileId.T8,
	]:
		tiles.append(Tile.new(tid, false, Tile.NO_OWNER, serial2))
		if tid == TileId.T8:
			t8_iid = serial2
		serial2 += 1
	assert_true(seat0.hand.restore_tiles(tiles))
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.DISCARD
	assert_true(bc.engine.declare_riichi_and_discard(0, t8_iid))
	assert_eq(bc.state.seats[0].river.riichi_discard_index(), 0)
	assert_eq(bc.state.seats[1].river.riichi_discard_index(), -1, "seat 1 未立直")
	assert_eq(bc.state.seats[2].river.riichi_discard_index(), -1)
	assert_eq(bc.state.seats[3].river.riichi_discard_index(), -1)
