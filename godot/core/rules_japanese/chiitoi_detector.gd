class_name ChiitoiDetector

static func is_chiitoi(sorted_ids: Array) -> bool:
	if sorted_ids.size() != 14:
		return false
	var counts := {}
	for tid in sorted_ids:
		counts[tid] = counts.get(tid, 0) + 1
	if counts.size() != 7:
		return false
	for tid in counts:
		if counts[tid] != 2:
			return false
	return true
