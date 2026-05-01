class_name Tenhou

# 天和：庄家配牌即胡（is_dealer_first_hand + is_tsumo）
static func detect(wc: WinContext) -> YakuEntry:
	if not wc.win_result.is_winning:
		return null
	if not wc.game_context.is_dealer_first_hand:
		return null
	if not wc.game_context.is_tsumo:
		return null
	return YakuEntry.new(YakuId.TENHOU, 0, true, 1)
