class_name DoubleRiichi

static func detect(wc: WinContext) -> YakuEntry:
	if not wc.game_context.is_double_riichi:
		return null
	if not wc.is_menzen():
		return null
	return YakuEntry.new(YakuId.DOUBLE_RIICHI, 2, false, 0)
