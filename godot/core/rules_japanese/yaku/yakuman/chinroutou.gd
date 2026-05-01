class_name Chinroutou

# 清老頭：14 张全部为数牌的 1 / 9（无字牌、无 2-8 中张）
static func detect(wc: WinContext) -> YakuEntry:
	if not wc.win_result.is_winning:
		return null
	if wc.win_result.is_kokushi:
		return null
	for tid in wc.all_tile_ids():
		if not TileId.is_terminal(tid):
			return null
	return YakuEntry.new(YakuId.CHINROUTOU, 0, true, 1)
