class_name StandardDecomposer

# decompose(sorted_ids: Array[int]) -> Array[{melds: Array, pair: int}]
# 输入：升序 id 数组，长度必须是 3n+2（n 为应有面子数）
# 输出：所有合法分解；不合法时返回 []
# 每个 meld 是 [id, id, id]（顺子或刻子）

static func decompose(sorted_ids: Array) -> Array:
	if sorted_ids.size() % 3 != 2:
		return []
	var counts := {}
	for tid in sorted_ids:
		counts[tid] = counts.get(tid, 0) + 1

	var results := []
	# 枚举每个候选雀头（从大到小：确保刻子型的雀头比顺子型先出现）
	var distinct_ids := counts.keys()
	distinct_ids.sort()
	distinct_ids.reverse()
	for pair_id in distinct_ids:
		if counts[pair_id] >= 2:
			var copy := counts.duplicate()
			copy[pair_id] -= 2
			if copy[pair_id] == 0:
				copy.erase(pair_id)
			var melds: Array = []
			if _try_form_melds(copy, melds):
				results.append({"melds": melds.duplicate(true), "pair": pair_id})
	return results

# 尝试将 counts 中所有牌组成顺子/刻子；melds 是输出累积器
static func _try_form_melds(counts: Dictionary, melds: Array) -> bool:
	if counts.is_empty():
		return true
	var keys := counts.keys()
	keys.sort()
	var first_id: int = keys[0]
	# 优先尝试刻子
	if counts[first_id] >= 3:
		var copy := counts.duplicate()
		copy[first_id] -= 3
		if copy[first_id] == 0:
			copy.erase(first_id)
		melds.append([first_id, first_id, first_id])
		if _try_form_melds(copy, melds):
			return true
		melds.pop_back()
	# 再尝试顺子（仅数牌）
	if not TileId.is_honor(first_id):
		var n := TileId.number(first_id)
		if n <= 7:
			var second := first_id + 1
			var third := first_id + 2
			if counts.get(second, 0) >= 1 and counts.get(third, 0) >= 1:
				var copy := counts.duplicate()
				copy[first_id] -= 1
				if copy[first_id] == 0: copy.erase(first_id)
				copy[second] -= 1
				if copy[second] == 0: copy.erase(second)
				copy[third] -= 1
				if copy[third] == 0: copy.erase(third)
				melds.append([first_id, second, third])
				if _try_form_melds(copy, melds):
					return true
				melds.pop_back()
	return false
