class_name Iipeikou

# 门清 + 至少 1 对完全相同的顺子（恰好 1 对，2 对是二杯口）
static func detect(wc: WinContext) -> YakuEntry:
	if not wc.win_result.is_winning:
		return null
	if wc.win_result.is_chiitoi or wc.win_result.is_kokushi:
		return null
	if not wc.is_menzen():
		return null
	for d in wc.win_result.standard_decompositions:
		var pairs := _count_identical_sequence_pairs(d)
		if pairs == 1:
			return YakuEntry.new(YakuId.IIPEIKOU, 1, false, 0)
	return null

static func _count_identical_sequence_pairs(decomp: Dictionary) -> int:
	var seq_keys: Dictionary = {}
	for meld_ids in decomp.melds:
		# Sequence: a, a+1, a+2 (a != b)
		if meld_ids[0] != meld_ids[1] and meld_ids[2] - meld_ids[0] == 2:
			var key := str(meld_ids[0]) + "-" + str(meld_ids[1]) + "-" + str(meld_ids[2])
			seq_keys[key] = seq_keys.get(key, 0) + 1
	var pairs := 0
	for k in seq_keys:
		var count: int = seq_keys[k]
		pairs += count / 2  # integer division (3 same -> 1 pair, 4 same -> 2 pairs)
	return pairs
