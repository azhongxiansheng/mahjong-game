class_name Honitsu

# 混一色：1 花色数牌 + 字牌
static func detect(wc: WinContext) -> YakuEntry:
	if not wc.win_result.is_winning:
		return null
	if wc.win_result.is_kokushi:
		return null
	# 收集除字牌外的所有花色
	var suits: Dictionary = {}
	var has_honor := false
	for tid in wc.all_tile_ids():
		if TileId.is_honor(tid):
			has_honor = true
		else:
			suits[TileId.suit(tid)] = true
	if suits.size() != 1:
		return null  # 0 = 全字牌（字一色）；2+ = 多色
	if not has_honor:
		return null  # 无字牌 = 清一色
	var han: int = 3 if wc.is_menzen() else 2
	return YakuEntry.new(YakuId.HONITSU, han, false, 0)
