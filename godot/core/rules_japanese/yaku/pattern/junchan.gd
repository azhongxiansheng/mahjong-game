class_name Junchan

# 纯全带幺九：每面子+雀头都含老头（数牌 1/9，无字牌），至少 1 顺子
static func detect(wc: WinContext) -> YakuEntry:
	if not wc.win_result.is_winning:
		return null
	if wc.win_result.is_chiitoi or wc.win_result.is_kokushi:
		return null
	if wc.win_result.standard_decompositions.size() == 0:
		return null
	# 全部 tile 不能含字牌
	for tid in wc.all_tile_ids():
		if TileId.is_honor(tid):
			return null
	for d in wc.win_result.standard_decompositions:
		var ok := true
		var has_sequence := false
		if not TileId.is_terminal(d.pair):
			ok = false
		if ok:
			for m in wc.melds:
				if not _meld_contains_terminal(m.to_id_array()):
					ok = false
					break
				if m.kind == Meld.Kind.CHI:
					has_sequence = true
		if ok:
			for meld_ids in d.melds:
				if not _meld_contains_terminal(meld_ids):
					ok = false
					break
				if meld_ids[0] != meld_ids[1] and meld_ids[2] - meld_ids[0] == 2:
					has_sequence = true
		if ok and has_sequence:
			var han: int = 3 if wc.is_menzen() else 2
			return YakuEntry.new(YakuId.JUNCHAN, han, false, 0)
	return null

static func _meld_contains_terminal(ids: Array) -> bool:
	for tid in ids:
		if TileId.is_terminal(tid):
			return true
	return false
