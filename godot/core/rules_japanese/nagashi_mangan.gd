class_name NagashiMangan

# 日麻 §6.5 流し満貫 — 流局时所有弃牌都幺九且无人鸣过该座弃牌 → 视满贯胡。
# 检测/支付都是纯函数,不修改 state。BC 与 GameDriver 共用。


# 扫 BattleState 4 座位,首个满足条件的返回 seat_id;无则 -1。
static func detect_winner_seat(state: BattleState) -> int:
	for s in range(4):
		var discards: Array = state.discards_per_seat[s]
		if discards.is_empty():
			continue
		var all_yaochu: bool = true
		for t in discards:
			if t == null or not TileId.is_yaochu(t.id):
				all_yaochu = false
				break
		if not all_yaochu:
			continue
		var called: bool = false
		for other_seat in state.seats:
			for m in other_seat.melds:
				if m != null and int(m.from_seat) == s:
					called = true
					break
			if called:
				break
		if called:
			continue
		return s
	return -1


# 支付计算:庄家流し満貫 12000 (4000×3);闲家 8000 (4000 + 2000×2)。
# 返 {seat:delta} 4-key 字典,正=收,负=出,守恒为 0。
static func payout(winner_seat: int, dealer_seat: int) -> Dictionary:
	var deltas: Dictionary = {0: 0, 1: 0, 2: 0, 3: 0}
	if winner_seat == dealer_seat:
		for s in range(4):
			if s != winner_seat:
				deltas[s] = -4000
				deltas[winner_seat] = int(deltas[winner_seat]) + 4000
	else:
		for s in range(4):
			if s == winner_seat:
				continue
			if s == dealer_seat:
				deltas[s] = -4000
				deltas[winner_seat] = int(deltas[winner_seat]) + 4000
			else:
				deltas[s] = -2000
				deltas[winner_seat] = int(deltas[winner_seat]) + 2000
	return deltas
