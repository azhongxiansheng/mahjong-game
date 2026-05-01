class_name Chinitsu

# 清一色：1 花色数牌（无字牌）
static func detect(wc: WinContext) -> YakuEntry:
	if not wc.win_result.is_winning:
		return null
	if wc.win_result.is_kokushi:
		return null
	var suits: Dictionary = {}
	for tid in wc.all_tile_ids():
		if TileId.is_honor(tid):
			return null
		suits[TileId.suit(tid)] = true
	if suits.size() != 1:
		return null
	var han: int = 6 if wc.is_menzen() else 5
	return YakuEntry.new(YakuId.CHINITSU, han, false, 0)
