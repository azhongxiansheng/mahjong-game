class_name DrawDetector

# 包装 0d 流局判定，从 BattleState 提取所需切面。
# 九种九牌 / 三家和了 不放这（属玩家选择/时机性，turn_engine 直接调 0d 函数）。

# 牌墙耗尽流局：live wall 摸尽
static func should_exhaustive_draw(state: BattleState) -> bool:
	return state.wall.live_wall_size() == 0

# 四风连打：4 家都弃了至少 1 张 + 仍在第 1 巡 + 4 家第 1 弃同字风
static func is_suufon_renda(state: BattleState) -> bool:
	if not state.first_round_active:
		return false
	var first_discards: Array = []
	for seat_discards in state.discards_per_seat:
		if seat_discards.size() == 0:
			return false
		first_discards.append(seat_discards[0].id)
	return AbortiveDraw.is_suufon_renda(first_discards)

# 四家立直：4 个 seat 全 riichi.declared
static func is_suucha_riichi(state: BattleState) -> bool:
	var arr: Array = []
	for seat in state.seats:
		arr.append(seat.riichi.declared)
	return AbortiveDraw.is_suucha_riichi(arr)

# 四杠散了：扫所有 seat 的 melds 收集杠的 owner，看是否 4 杠且非全同人
static func is_suukantsu_sanra(state: BattleState) -> bool:
	var kan_seats: Array = []
	for seat in state.seats:
		for m in seat.melds:
			if m.is_kan():
				kan_seats.append(seat.seat_id)
	return AbortiveDraw.is_suukantsu_sanra(kan_seats)
