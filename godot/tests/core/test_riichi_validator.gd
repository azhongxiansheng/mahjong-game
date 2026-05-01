extends GutTest

# RiichiValidator: 立直触发条件 = 门清 + 听牌 + 点数 ≥1000 + 牌墙剩余 ≥4 + 未立直。
# 输入：Seat（13 张听牌期）+ wall_remaining。

func _seat_with_tenpai_concealed() -> Seat:
	# 听 W3 嵌张型（13 张暗牌、无副露）
	var s := Seat.new(0, TileId.E)
	for tid in [
		TileId.W2, TileId.W4,    # 等 W3
		TileId.T2, TileId.T3, TileId.T4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.S5, TileId.S5,
	]:
		s.add_to_hand(Tile.new(tid))
	return s

func test_concealed_tenpai_can_riichi():
	var s := _seat_with_tenpai_concealed()
	assert_true(RiichiValidator.can_declare_riichi(s, 50))

func test_already_declared_blocks():
	var s := _seat_with_tenpai_concealed()
	s.riichi.declare(3, false)
	assert_false(RiichiValidator.can_declare_riichi(s, 50))

func test_open_melds_blocks():
	var s := _seat_with_tenpai_concealed()
	# 副露 1 个 PON，破门清
	s.melds.append(Meld.make_pon(
		[Tile.new(TileId.W5), Tile.new(TileId.W5), Tile.new(TileId.W5)], 1))
	# hand 也得调短到 10 张以匹配（但本测试只看 is_concealed_hand 失败）
	assert_false(RiichiValidator.can_declare_riichi(s, 50))

func test_ankan_keeps_concealed_can_riichi():
	# ANKAN 不破门清；hand 调到 10 张听 W3 嵌张
	var s := Seat.new(0, TileId.E)
	for tid in [
		TileId.W2, TileId.W4,    # 等 W3
		TileId.T2, TileId.T3, TileId.T4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S5, TileId.S5,
	]:
		s.add_to_hand(Tile.new(tid))
	s.melds.append(Meld.make_ankan([
		Tile.new(TileId.S1), Tile.new(TileId.S1),
		Tile.new(TileId.S1), Tile.new(TileId.S1)]))
	assert_true(RiichiValidator.can_declare_riichi(s, 50))

func test_low_points_blocks():
	var s := _seat_with_tenpai_concealed()
	s.points = 500
	assert_false(RiichiValidator.can_declare_riichi(s, 50))

func test_wall_too_few_blocks():
	var s := _seat_with_tenpai_concealed()
	# 牌墙剩 3 张：玩家立直后无机会再摸 → 拒绝
	assert_false(RiichiValidator.can_declare_riichi(s, 3))

func test_wall_4_is_ok():
	var s := _seat_with_tenpai_concealed()
	assert_true(RiichiValidator.can_declare_riichi(s, 4), "刚好 4 张可立直")

func test_no_tenpai_blocks():
	# 13 张全散不听
	var s := Seat.new(0, TileId.E)
	for tid in [
		TileId.W1, TileId.W3, TileId.W5, TileId.W7, TileId.W9,
		TileId.T1, TileId.T3, TileId.T5, TileId.T7, TileId.T9,
		TileId.S1, TileId.S3, TileId.S5,
	]:
		s.add_to_hand(Tile.new(tid))
	assert_false(RiichiValidator.can_declare_riichi(s, 50))
