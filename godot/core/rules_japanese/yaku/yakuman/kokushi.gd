class_name KokushiYakuman

# 国士無双 / 国士無双 13 面待ち
# 直接复用 plan 0a 的 KokushiDetector 结果（已写入 win_result.is_kokushi / is_thirteen_wait）
static func detect(wc: WinContext) -> YakuEntry:
	if not wc.win_result.is_kokushi:
		return null
	if wc.win_result.is_thirteen_wait:
		return YakuEntry.new(YakuId.KOKUSHI_13, 0, true, 2)
	return YakuEntry.new(YakuId.KOKUSHI, 0, true, 1)
