class_name Chiitoitsu

static func detect(wc: WinContext) -> YakuEntry:
	if wc.win_result.is_chiitoi:
		return YakuEntry.new(YakuId.CHIITOITSU, 2, false, 0)
	return null
