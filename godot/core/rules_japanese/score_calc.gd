class_name ScoreCalc

# 顶层入口：把 WinPattern.detect 结果 + called_melds + yaku_list + win_ctx
# 算成最终结算 dict。
#
# 返回字段：
#   fu, han, base_points, payout, yakuman_multiplier, winner_seat, winner_total
#
# winner_total = sum(payout.values()) + riichi_sticks*1000
#
# yaku_per_decomp 回调（可选）：Callable(decomp_index: int) -> YakuList
# 提供时对每个 standard_decomposition 独立算役 + fu → 选 base_points 最高的分解。
# 解决不同分解产出互斥役被错误合并的问题（如 pinfu+iipeikou vs sanankou）。

static func calculate(win_pattern_result: Dictionary, called_melds: Array, yaku_list: YakuList, win_ctx: ScoreContext, yaku_per_decomp: Callable = Callable()) -> Dictionary:
	var fu: int
	var effective_yaku: YakuList = yaku_list

	if yaku_list.is_yakuman:
		fu = 0
	elif win_pattern_result.is_chiitoi:
		fu = 25
	elif win_pattern_result.is_kokushi:
		fu = 0
	elif yaku_per_decomp.is_valid() and win_pattern_result.standard_decompositions.size() > 1:
		var best := _pick_best_decomposition(win_pattern_result.standard_decompositions, called_melds, win_ctx, yaku_per_decomp)
		fu = best.fu
		effective_yaku = best.yaku_list
	else:
		fu = _pick_best_fu(win_pattern_result.standard_decompositions, called_melds, win_ctx, yaku_list)

	var han := effective_yaku.total_han()
	var base: int = ScoreFormula.base_points(fu, han, effective_yaku.yakuman_multiplier)
	var payout: Dictionary = PayoutCalculator.payout(base, win_ctx)

	var winner_total := 0
	for v in payout.values():
		winner_total += v
	winner_total += win_ctx.riichi_sticks * 1000

	return {
		"fu": fu,
		"han": han,
		"base_points": base,
		"payout": payout,
		"yakuman_multiplier": effective_yaku.yakuman_multiplier,
		"winner_seat": win_ctx.winner_seat,
		"winner_total": winner_total,
	}

static func _pick_best_decomposition(decompositions: Array, called_melds: Array, win_ctx: ScoreContext, yaku_per_decomp: Callable) -> Dictionary:
	var best_base := -1
	var best_fu := 0
	var best_yl: YakuList = YakuList.empty()
	for i in range(decompositions.size()):
		var yl: YakuList = yaku_per_decomp.call(i)
		if yl == null:
			continue
		var fu_i: int = FuCalculator.calculate(decompositions[i], called_melds, win_ctx, yl)
		var base_i: int = ScoreFormula.base_points(fu_i, yl.total_han(), yl.yakuman_multiplier)
		if base_i > best_base or (base_i == best_base and fu_i > best_fu):
			best_base = base_i
			best_fu = fu_i
			best_yl = yl
	return {"fu": best_fu, "yaku_list": best_yl}

static func _pick_best_fu(decompositions: Array, called_melds: Array, win_ctx: ScoreContext, yaku_list: YakuList) -> int:
	var best := 0
	for d in decompositions:
		var fu: int = FuCalculator.calculate(d, called_melds, win_ctx, yaku_list)
		if fu > best:
			best = fu
	return best
