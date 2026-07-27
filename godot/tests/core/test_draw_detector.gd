extends GutTest

# DrawDetector: 包装 0d 流局判定，从 BattleState 提取所需切面。
# 九种九牌 / 三家和了 不放这（属玩家选择/时机性，turn_engine 直接调 0d 函数）。

func _empty_state_with_4_seats() -> BattleState:
	return BattleState.for_east_round(42, 0, 1, 0, 0)

# ---- should_exhaustive_draw ----

func test_exhaustive_false_at_start():
	var s := _empty_state_with_4_seats()
	assert_false(DrawDetector.should_exhaustive_draw(s))

func test_exhaustive_true_when_live_wall_empty():
	var s := _empty_state_with_4_seats()
	# 摸完所有 live wall（70 张）
	for _i in range(70):
		s.wall.draw()
	assert_true(DrawDetector.should_exhaustive_draw(s))

# ---- is_suufon_renda ----

func test_suufon_renda_all_east_first_round():
	var s := _empty_state_with_4_seats()
	for seat in range(4):
		s.seats[seat].river.append_discard(Tile.new(TileId.E))
	# first_round_active 默认 true
	assert_true(DrawDetector.is_suufon_renda(s))

func test_suufon_renda_blocked_after_first_round():
	var s := _empty_state_with_4_seats()
	for seat in range(4):
		s.seats[seat].river.append_discard(Tile.new(TileId.E))
	s.first_round_active = false
	assert_false(DrawDetector.is_suufon_renda(s))

func test_suufon_renda_not_all_seats_discarded_yet():
	var s := _empty_state_with_4_seats()
	for seat in range(3):
		s.seats[seat].river.append_discard(Tile.new(TileId.E))
	# seat 3 还没弃
	assert_false(DrawDetector.is_suufon_renda(s))

func test_suufon_renda_mixed_winds_no():
	var s := _empty_state_with_4_seats()
	s.seats[0].river.append_discard(Tile.new(TileId.E))
	s.seats[1].river.append_discard(Tile.new(TileId.S_WIND))
	s.seats[2].river.append_discard(Tile.new(TileId.E))
	s.seats[3].river.append_discard(Tile.new(TileId.E))
	assert_false(DrawDetector.is_suufon_renda(s))

func test_suufon_renda_all_dragon_no():
	var s := _empty_state_with_4_seats()
	for seat in range(4):
		s.seats[seat].river.append_discard(Tile.new(TileId.HAKU))
	assert_false(DrawDetector.is_suufon_renda(s), "白板不算字风")

# ---- is_suucha_riichi ----

func test_suucha_riichi_all_4_declared():
	var s := _empty_state_with_4_seats()
	for seat in s.seats:
		seat.riichi.declare(3, false)
	assert_true(DrawDetector.is_suucha_riichi(s))

func test_suucha_riichi_only_3_no():
	var s := _empty_state_with_4_seats()
	for seat_id in range(3):
		s.seats[seat_id].riichi.declare(3, false)
	assert_false(DrawDetector.is_suucha_riichi(s))

# ---- is_suukantsu_sanra ----

func test_suukantsu_sanra_4_kans_different_seats():
	var s := _empty_state_with_4_seats()
	for seat_id in range(4):
		s.seats[seat_id].melds.add_existing(Meld.make_ankan([
			Tile.new(TileId.W1), Tile.new(TileId.W1),
			Tile.new(TileId.W1), Tile.new(TileId.W1)]))
	assert_true(DrawDetector.is_suukantsu_sanra(s))

func test_suukantsu_sanra_4_kans_same_seat_no():
	# 同 1 人 4 杠 → 四杠子役满，不流局
	var s := _empty_state_with_4_seats()
	for _i in range(4):
		s.seats[0].melds.add_existing(Meld.make_ankan([
			Tile.new(TileId.W1), Tile.new(TileId.W1),
			Tile.new(TileId.W1), Tile.new(TileId.W1)]))
	assert_false(DrawDetector.is_suukantsu_sanra(s))

func test_suukantsu_sanra_3_kans_no():
	var s := _empty_state_with_4_seats()
	for seat_id in range(3):
		s.seats[seat_id].melds.add_existing(Meld.make_ankan([
			Tile.new(TileId.W1), Tile.new(TileId.W1),
			Tile.new(TileId.W1), Tile.new(TileId.W1)]))
	assert_false(DrawDetector.is_suukantsu_sanra(s))
