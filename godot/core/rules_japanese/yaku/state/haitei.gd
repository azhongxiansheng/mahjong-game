class_name Haitei

static func detect(wc: WinContext) -> YakuEntry:
	if not wc.game_context.is_haitei:
		return null
	if not wc.game_context.is_tsumo:
		return null
	return YakuEntry.new(YakuId.HAITEI, 1, false, 0)
