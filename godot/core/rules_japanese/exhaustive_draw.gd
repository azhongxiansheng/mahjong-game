class_name ExhaustiveDraw

# 牌墙耗尽流局：不听罚符 3000 共享 + 庄家听则连庄。
# 全听或全不听 → 0 罚符。

# 不听罚符分配：返回 {seat: net_change} (正=收, 负=出)。
# 公式：听家共收 3000、不听家共出 3000。
static func noten_payout(tenpai_array: Array) -> Dictionary:
	var result := {0: 0, 1: 0, 2: 0, 3: 0}
	var t_count := 0
	for tenpai in tenpai_array:
		if tenpai:
			t_count += 1
	var n_count := tenpai_array.size() - t_count
	if t_count == 0 or n_count == 0:
		return result
	@warning_ignore("integer_division")
	var per_tenpai: int = 3000 / t_count
	@warning_ignore("integer_division")
	var per_noten: int = -3000 / n_count
	for seat in range(tenpai_array.size()):
		result[seat] = per_tenpai if tenpai_array[seat] else per_noten
	return result

static func is_dealer_renchan(dealer_seat: int, tenpai_array: Array) -> bool:
	return tenpai_array[dealer_seat]
