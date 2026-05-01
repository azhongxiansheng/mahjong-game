class_name Riichi

static func detect(wc: WinContext) -> YakuEntry:
	if not wc.game_context.is_riichi:
		return null
	if wc.game_context.is_double_riichi:
		return null
	if not wc.is_menzen():
		return null
	return YakuEntry.new(YakuId.RIICHI, 1, false, 0)
