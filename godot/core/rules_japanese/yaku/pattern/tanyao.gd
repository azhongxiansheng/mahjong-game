class_name Tanyao

static func detect(wc: WinContext) -> YakuEntry:
	if not wc.win_result.is_winning:
		return null
	for tid in wc.all_tile_ids():
		if not TileId.is_simple(tid):
			return null
	return YakuEntry.new(YakuId.TANYAO, 1, false, 0)
