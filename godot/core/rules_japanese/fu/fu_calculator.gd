class_name FuCalculator

# 综合符算入口。流程：
#   1. 七対子 → 25 固定
#   2. 役满 → 0（不参与，由 ScoreFormula 直接走役满档）
#   3. 平和自摸 → 20；平和荣胡 → 30
#   4. 否则：副底 20 + 自摸 +2 + 门清荣胡 +10 + 雀头符 + 待牌符 + 面子符
#   5. 向上取整到 10
#
# 门清判定：called_melds 中只允许 ANKAN（暗杠不破坏门清）
# 荣胡完成的刻子（含 winning_tile 的刻子）算明刻

static func calculate(decomposition: Dictionary, called_melds: Array, win_ctx: WinContext, yaku_list: YakuList) -> int:
	if yaku_list.is_yakuman:
		return 0
	if yaku_list.is_chiitoi():
		return 25

	var is_concealed_hand := _is_concealed(called_melds)

	if yaku_list.is_pinfu():
		return 20 if win_ctx.is_tsumo else 30

	var fu := 20  # 副底

	if win_ctx.is_tsumo:
		fu += 2
	elif is_concealed_hand:
		fu += 10  # 门清荣胡

	fu += PairFu.fu_for_pair(decomposition.pair, win_ctx.round_wind, win_ctx.seat_wind)
	fu += WaitFu.fu_for_wait(decomposition, win_ctx.winning_tile.id)

	# decomposition 内的面子（暗牌分解）
	for meld_ids in decomposition.melds:
		var is_concealed_meld := true
		# 荣胡 + 含 winning 的刻子 → 明刻
		if not win_ctx.is_tsumo and meld_ids[0] == meld_ids[1] and (win_ctx.winning_tile.id in meld_ids):
			is_concealed_meld = false
		fu += MeldFu.fu_for_decomp_meld(meld_ids, is_concealed_meld)

	# 副露面子
	for meld in called_melds:
		fu += MeldFu.fu_for_called_meld(meld)

	return _ceil_to_10(fu)

static func _is_concealed(called_melds: Array) -> bool:
	for m in called_melds:
		if m.kind != Meld.Kind.ANKAN:
			return false
	return true

static func _ceil_to_10(fu: int) -> int:
	return ((fu + 9) / 10) * 10
