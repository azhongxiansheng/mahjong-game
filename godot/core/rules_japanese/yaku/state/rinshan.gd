class_name Rinshan

static func detect(wc: WinContext) -> YakuEntry:
	if not wc.game_context.is_rinshan:
		return null
	if not wc.game_context.is_tsumo:
		return null
	return YakuEntry.new(YakuId.RINSHAN, 1, false, 0)
