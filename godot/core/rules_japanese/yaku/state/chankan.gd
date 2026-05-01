class_name Chankan

static func detect(wc: WinContext) -> YakuEntry:
	if not wc.game_context.is_chankan:
		return null
	if wc.game_context.is_tsumo:
		return null
	return YakuEntry.new(YakuId.CHANKAN, 1, false, 0)
