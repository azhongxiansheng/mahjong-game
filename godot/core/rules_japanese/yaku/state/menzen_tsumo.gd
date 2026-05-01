class_name MenzenTsumo

static func detect(wc: WinContext) -> YakuEntry:
	if not wc.game_context.is_tsumo:
		return null
	if not wc.is_menzen():
		return null
	return YakuEntry.new(YakuId.MENZEN_TSUMO, 1, false, 0)
