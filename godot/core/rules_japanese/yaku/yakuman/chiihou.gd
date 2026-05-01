class_name Chiihou

# 地和：闲家第一摸即胡（is_non_dealer_first_draw + is_tsumo）
static func detect(wc: WinContext) -> YakuEntry:
	if not wc.win_result.is_winning:
		return null
	if not wc.game_context.is_non_dealer_first_draw:
		return null
	if not wc.game_context.is_tsumo:
		return null
	return YakuEntry.new(YakuId.CHIIHOU, 0, true, 1)
