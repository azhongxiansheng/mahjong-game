class_name Houtei

static func detect(wc: WinContext) -> YakuEntry:
	if not wc.game_context.is_houtei:
		return null
	if wc.game_context.is_tsumo:
		return null
	return YakuEntry.new(YakuId.HOUTEI, 1, false, 0)
