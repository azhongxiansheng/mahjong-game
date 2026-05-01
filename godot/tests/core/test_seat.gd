extends GutTest

# Seat (spec §5)：一座位的数据 + 简单 helper。
# 弃牌河不存这（由 BattleState.discards_per_seat 单独维护，risk plan §风险 #4）。
# deck_owner 字段属于卡组系统（里程碑 4），0e 不实装。

func test_factory_defaults():
	var s := Seat.new(1, TileId.S_WIND)
	assert_eq(s.seat_id, 1)
	assert_eq(s.seat_wind, TileId.S_WIND)
	assert_eq(s.points, 25000, "起家点数默认 25000")
	assert_eq(s.hand.size(), 0)
	assert_eq(s.melds.size(), 0)
	assert_not_null(s.riichi)
	assert_not_null(s.furiten)

func test_factory_custom_points():
	var s := Seat.new(0, TileId.E, 30000)
	assert_eq(s.points, 30000)

func test_add_to_hand_appends_tile():
	var s := Seat.new(0, TileId.E)
	s.add_to_hand(Tile.new(TileId.W5))
	assert_eq(s.hand.size(), 1)

func test_discard_from_hand_removes_first_match():
	var s := Seat.new(0, TileId.E)
	s.add_to_hand(Tile.new(TileId.W5))
	s.add_to_hand(Tile.new(TileId.W3))
	assert_true(s.discard_from_hand(TileId.W5))
	assert_eq(s.hand.size(), 1)
	assert_eq(s.hand.to_id_array(), [TileId.W3])

func test_discard_from_hand_returns_false_when_absent():
	var s := Seat.new(0, TileId.E)
	s.add_to_hand(Tile.new(TileId.W5))
	assert_false(s.discard_from_hand(TileId.W9))
	assert_eq(s.hand.size(), 1)

func test_is_concealed_hand_no_melds():
	var s := Seat.new(0, TileId.E)
	assert_true(s.is_concealed_hand(), "无副露 → 门清")

func test_is_concealed_hand_with_ankan_still_concealed():
	var s := Seat.new(0, TileId.E)
	var ankan := Meld.make_ankan([
		Tile.new(TileId.W1), Tile.new(TileId.W1),
		Tile.new(TileId.W1), Tile.new(TileId.W1)])
	s.melds.append(ankan)
	assert_true(s.is_concealed_hand(), "暗杠不破坏门清")

func test_is_concealed_hand_with_pon_breaks():
	var s := Seat.new(0, TileId.E)
	var pon := Meld.make_pon(
		[Tile.new(TileId.W1), Tile.new(TileId.W1), Tile.new(TileId.W1)], 1)
	s.melds.append(pon)
	assert_false(s.is_concealed_hand(), "pon 破坏门清")

func test_adjust_points():
	var s := Seat.new(0, TileId.E)
	s.adjust_points(-1500)
	assert_eq(s.points, 23500)
	s.adjust_points(3000)
	assert_eq(s.points, 26500)
