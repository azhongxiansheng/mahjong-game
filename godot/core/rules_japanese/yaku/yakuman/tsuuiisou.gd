class_name Tsuuiisou

# 字一色：14 张全部为字牌
static func detect(wc: WinContext) -> YakuEntry:
	if not wc.win_result.is_winning:
		return null
	if wc.win_result.is_kokushi:
		return null
	for tid in wc.all_tile_ids():
		if not TileId.is_honor(tid):
			return null
	return YakuEntry.new(YakuId.TSUUIISOU, 0, true, 1)
