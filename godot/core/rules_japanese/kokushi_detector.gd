class_name KokushiDetector

const YAOCHU: Array = [
	TileId.W1, TileId.W9, TileId.T1, TileId.T9, TileId.S1, TileId.S9,
	TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N,
	TileId.HAKU, TileId.HATSU, TileId.CHUN,
]

# detect 仅判定是否 14 张构成国士；is_thirteen_wait 在不知和牌张时恒为 false
# 完整 13 面待判定使用 detect_with_winning
static func detect(sorted_ids: Array) -> Dictionary:
	var result := {"is_kokushi": false, "is_thirteen_wait": false}
	if sorted_ids.size() != 14:
		return result
	var counts := {}
	for tid in sorted_ids:
		counts[tid] = counts.get(tid, 0) + 1
	# 必须 14 张全是幺九
	for tid in counts:
		if not _is_yaochu(tid):
			return result
	# 必须 13 种幺九全齐，且其中 1 种 2 张
	if counts.size() != 13:
		return result
	var double_count := 0
	for tid in YAOCHU:
		if not counts.has(tid):
			return result
		if counts[tid] == 2:
			double_count += 1
		elif counts[tid] != 1:
			return result
	if double_count != 1:
		return result
	result.is_kokushi = true
	return result

static func detect_with_winning(hand_13_sorted: Array, winning_tile: int) -> Dictionary:
	# hand_13_sorted: 13 张手牌（升序 id）
	# winning_tile: 即将摸/荣胡的那张
	# 13 面待：13 张恰好是 13 种幺九各 1 张
	var combined := hand_13_sorted.duplicate()
	combined.append(winning_tile)
	combined.sort()
	var r := detect(combined)
	if r.is_kokushi:
		# 检查 13 张本身是否 13 种幺九各 1
		if hand_13_sorted.size() == 13:
			var hand_set := {}
			for tid in hand_13_sorted:
				hand_set[tid] = hand_set.get(tid, 0) + 1
			if hand_set.size() == 13:
				var all_one := true
				for tid in YAOCHU:
					if hand_set.get(tid, 0) != 1:
						all_one = false
						break
				if all_one:
					r.is_thirteen_wait = true
	return r

static func _is_yaochu(tid: int) -> bool:
	return TileId.is_yaochu(tid)
