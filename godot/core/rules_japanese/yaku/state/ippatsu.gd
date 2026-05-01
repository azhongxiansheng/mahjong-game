class_name Ippatsu

static func detect(wc: WinContext) -> YakuEntry:
	if not wc.game_context.is_ippatsu:
		return null
	if not wc.is_menzen():
		return null
	return YakuEntry.new(YakuId.IPPATSU, 1, false, 0)
