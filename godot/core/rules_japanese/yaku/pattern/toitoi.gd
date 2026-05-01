class_name Toitoi

# 対々和：4 面子全是刻子（含杠）
static func detect(wc: WinContext) -> YakuEntry:
	if not wc.win_result.is_winning:
		return null
	if wc.win_result.is_chiitoi or wc.win_result.is_kokushi:
		return null
	# 副露顺子立即排除
	for m in wc.melds:
		if m.kind == Meld.Kind.CHI:
			return null
	if wc.win_result.standard_decompositions.size() == 0:
		return null
	for d in wc.win_result.standard_decompositions:
		var all_triplet := true
		for meld_ids in d.melds:
			# Sequence: meld_ids[0] != meld_ids[1]
			if meld_ids[0] != meld_ids[1]:
				all_triplet = false
				break
		if all_triplet:
			return YakuEntry.new(YakuId.TOITOI, 2, false, 0)
	return null
