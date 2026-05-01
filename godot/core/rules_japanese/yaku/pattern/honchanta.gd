class_name Honchanta

# 混全带幺九：4 面子+雀头都含幺九（数牌 1/9 或字牌），至少 1 顺子（不然是清老头/字一色）
# Junchan 是其严格子集（不含字牌），互斥由 evaluator 处理
static func detect(wc: WinContext) -> YakuEntry:
	if not wc.win_result.is_winning:
		return null
	if wc.win_result.is_chiitoi or wc.win_result.is_kokushi:
		return null
	if wc.win_result.standard_decompositions.size() == 0:
		return null
	for d in wc.win_result.standard_decompositions:
		var ok := true
		var has_sequence := false  # 至少 1 顺子（区分清老头/字一色）
		# 雀头含幺九
		if not TileId.is_yaochu(d.pair):
			ok = false
		# 副露面子
		if ok:
			for m in wc.melds:
				if not _meld_contains_yaochu(m.to_id_array()):
					ok = false
					break
				if m.kind == Meld.Kind.CHI:
					has_sequence = true
		# 暗 melds
		if ok:
			for meld_ids in d.melds:
				if not _meld_contains_yaochu(meld_ids):
					ok = false
					break
				# 顺子检测
				if meld_ids[0] != meld_ids[1] and meld_ids[2] - meld_ids[0] == 2:
					has_sequence = true
		if ok and has_sequence:
			var han: int = 2 if wc.is_menzen() else 1
			return YakuEntry.new(YakuId.HONCHANTA, han, false, 0)
	return null

static func _meld_contains_yaochu(ids: Array) -> bool:
	for tid in ids:
		if TileId.is_yaochu(tid):
			return true
	return false
