class_name RiichiValidator

# 立直触发条件（标准日麻）：门清 + 听牌 + 点数 ≥1000 + 牌墙剩余 ≥4 + 未立直。
# 输入：Seat（13 张听牌期）+ wall_remaining；此函数纯函数不修改 state。

const MIN_POINTS_TO_RIICHI: int = 1000
const MIN_WALL_REMAINING: int = 4

static func can_declare_riichi(seat: Seat, wall_remaining: int) -> bool:
	if seat.riichi.declared:
		return false
	if not seat.is_concealed_hand():
		return false
	if seat.points < MIN_POINTS_TO_RIICHI:
		return false
	if wall_remaining < MIN_WALL_REMAINING:
		return false
	return WaitCalculator.wait_tiles(seat.hand, seat.melds).size() > 0
